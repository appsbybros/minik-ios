import Foundation

// AndroidKit: Java library services the Android app uses, with Android libcore semantics.
// - org.json (JSONObject, JSONArray, JSONStringer, JSONTokener, JSON) ported from libcore main: insertion
//   ordered objects, the lenient tokener (comments, unquoted names/literals, ';' and '=' separators, octal and
//   hex integers), Integer/Long/Double literal typing, the getX/optX coercions, NULL handling and Android's
//   writer ("\/" escaping, numberToString: 0.0 -> "0", -0.0 -> "-0").
// - org.w3c.dom as Android's DocumentBuilder builds it (libcore DocumentBuilderImpl over KXmlParser, ported in
//   pure Swift: attributes in source order, comments kept as nodes, adjacent text merged, CDATA kept as its own
//   node, getElementsByTagName in document order, textContent without comments).
// - java.text.SimpleDateFormat / java.util.Calendar / TimeZone / Date for the patterns and fields the app uses.

// MARK: - org.json

/// org.json.JSONObject.NULL: equal to itself, prints "null".
final class AJSONNull: CustomStringConvertible, Hashable {
    static let instance = AJSONNull()
    private init() {}
    var description: String { return "null" }
    static func == (lhs: AJSONNull, rhs: AJSONNull) -> Bool { return true }
    func hash(into hasher: inout Hasher) { hasher.combine(0) }
}

/// org.json.JSONException.
struct AJSONException: Error, CustomStringConvertible {
    let message: String
    var description: String { return message }
}

/// org.json.JSON helpers (coercions, number formatting, writing).
enum AJSON {
    /// Normalizes a Swift value to the Java object org.json stores: Int (Integer), Int64 (Long), Double,
    /// Float, Bool, String, Character, AJSONNull, AJSONObject, AJSONArray. nil stays nil.
    static func normalize(_ value: Any?) -> Any? {
        guard let v = unwrap(value) else { return nil }
        // Numbers and Bool are matched by their exact type (JavaArg.classifyExact): a dynamic cast like
        // `v as? Int` may bridge through NSNumber on Darwin and turn `true` into 1.
        if let exact = JavaArg.classify(v).storedValue { return exact }
        if let s = v as? Substring { return String(s) }
        return v
    }

    /// Exact-type views of a stored value (Java `instanceof Integer/Long/Float/Double/Boolean`).
    static func exactInt(_ v: Any) -> Int? { return type(of: v) == Int.self ? (v as! Int) : nil }
    static func exactLong(_ v: Any) -> Int64? { return type(of: v) == Int64.self ? (v as! Int64) : nil }
    static func exactFloat(_ v: Any) -> Float? { return type(of: v) == Float.self ? (v as! Float) : nil }
    static func exactDouble(_ v: Any) -> Double? { return type(of: v) == Double.self ? (v as! Double) : nil }
    static func exactBool(_ v: Any) -> Bool? { return type(of: v) == Bool.self ? (v as! Bool) : nil }

    private static func unwrap(_ value: Any?) -> Any? {
        guard let v = value else { return nil }
        let mirror = Mirror(reflecting: v)
        if mirror.displayStyle == .optional {
            guard let child = mirror.children.first else { return nil }
            return unwrap(child.value)
        }
        return v
    }

    static func isNumber(_ v: Any) -> Bool {
        return doubleValue(v) != nil
    }

    /// Number.doubleValue().
    static func doubleValue(_ v: Any) -> Double? {
        if let i = exactInt(v) { return Double(i) }
        if let i = exactLong(v) { return Double(i) }
        if let d = exactDouble(v) { return d }
        if let f = exactFloat(v) { return Double(f) }
        return nil
    }

    /// JSON.checkDouble.
    static func checkDouble(_ d: Double) throws {
        if d.isInfinite || d.isNaN {
            throw AJSONException(message: "Forbidden numeric value: \(AKotlinFloatingDecimal.toJavaFormatString(d))")
        }
    }

    /// JSON.toBoolean.
    static func toBoolean(_ value: Any?) -> Bool? {
        guard let v = value else { return nil }
        if let b = exactBool(v) { return b }
        if doubleValue(v) != nil { return nil }
        if let s = v as? String {
            if s.kequalsIgnoreCase("true") { return true }
            if s.kequalsIgnoreCase("false") { return false }
        }
        return nil
    }

    /// JSON.toDouble.
    static func toDouble(_ value: Any?) -> Double? {
        guard let v = value else { return nil }
        if let d = doubleValue(v) { return d }
        if exactBool(v) != nil { return nil }
        if let s = v as? String { return JavaParse.parseDouble(s) }
        return nil
    }

    /// JSON.toInteger: Number.intValue() or (int) Double.parseDouble(string).
    static func toInteger(_ value: Any?) -> Int? {
        guard let v = value else { return nil }
        if let i = exactInt(v) { return i }
        if let i = exactLong(v) { return Int(Int32(truncatingIfNeeded: i)) }
        if let d = exactDouble(v) { return Int(KMath.d2i(d)) }
        if let f = exactFloat(v) { return Int(KMath.f2i(f)) }
        if exactBool(v) != nil { return nil }
        if let s = v as? String { return JavaParse.parseDouble(s).map { Int(KMath.d2i($0)) } }
        return nil
    }

    /// JSON.toLong: Number.longValue() or (long) Double.parseDouble(string).
    static func toLong(_ value: Any?) -> Int64? {
        guard let v = value else { return nil }
        if let i = exactLong(v) { return i }
        if let i = exactInt(v) { return Int64(i) }
        if let d = exactDouble(v) { return KMath.d2l(d) }
        if let f = exactFloat(v) { return KMath.f2l(f) }
        if exactBool(v) != nil { return nil }
        if let s = v as? String { return JavaParse.parseDouble(s).map { KMath.d2l($0) } }
        return nil
    }

    /// JSON.toString: the String itself or String.valueOf(value).
    static func toString(_ value: Any?) -> String? {
        guard let v = value else { return nil }
        if doubleValue(v) == nil && exactBool(v) == nil, let s = v as? String { return s }
        return valueOf(v)
    }

    /// String.valueOf for stored values.
    static func valueOf(_ v: Any) -> String {
        if let exact = JavaArg.classifyExact(v) { return exact.javaString }
        switch v {
        case let s as String: return s
        case let o as AJSONObject: return o.toString()
        case let a as AJSONArray: return a.toString()
        case is AJSONNull: return "null"
        default: return JavaArg.classify(v).javaString
        }
    }

    /// actual.getClass().getName() for error messages.
    static func className(_ v: Any) -> String {
        switch v {
        case is AJSONObject: return "org.json.JSONObject"
        case is AJSONArray: return "org.json.JSONArray"
        case is AJSONNull: return "org.json.JSONObject$1"
        default: return JavaArg.classify(v).className
        }
    }

    /// JSON.typeMismatch(indexOrName, actual, requiredType).
    static func typeMismatch(_ indexOrName: Any, _ actual: Any?, _ requiredType: String) -> AJSONException {
        guard let actual = actual else {
            return AJSONException(message: "Value at \(indexOrName) is null.")
        }
        return AJSONException(message: "Value \(valueOf(actual)) at \(indexOrName) of type \(className(actual)) cannot be converted to \(requiredType)")
    }

    /// JSON.typeMismatch(actual, requiredType).
    static func typeMismatch(_ actual: Any, _ requiredType: String) -> AJSONException {
        return AJSONException(message: "Value \(valueOf(actual)) of type \(className(actual)) cannot be converted to \(requiredType)")
    }

    /// JSONObject.wrap(o).
    static func wrap(_ o: Any?) -> Any? {
        guard let v = normalize(o) else { return AJSONNull.instance }
        if v is AJSONArray || v is AJSONObject || v is AJSONNull { return v }
        if doubleValue(v) != nil || exactBool(v) != nil || v is Character || v is String { return v }
        if let list = v as? [Any?] { return AJSONArray(list) }
        return nil
    }

    /// JSONObject.numberToString(number).
    static func numberToString(_ number: Any) throws -> String {
        guard let doubleValue = doubleValue(number) else {
            throw AJSONException(message: "Number must be non-null")
        }
        try checkDouble(doubleValue)
        // the original returns "-0" instead of "-0.0" for negative zero
        if let d = exactDouble(number), d == 0 && d.sign == .minus {
            return "-0"
        }
        let longValue: Int64
        if let i = exactInt(number) {
            longValue = Int64(i)
        } else if let i = exactLong(number) {
            longValue = i
        } else if let f = exactFloat(number) {
            longValue = KMath.f2l(f)
        } else {
            longValue = KMath.d2l(doubleValue)
        }
        if doubleValue == Double(longValue) {
            return String(longValue)
        }
        if let f = exactFloat(number) {
            return AKotlinDecimal.floatToString(f) // Float.toString (libcore main)
        }
        if let d = exactDouble(number) {
            return AKotlinFloatingDecimal.toJavaFormatString(d) // Double.toString
        }
        return String(longValue)
    }

    /// JSONStringer.string(value).
    static func quote(_ value: String, _ out: inout String) {
        var units: [UInt16] = [0x22]
        for c in value.utf16 {
            switch c {
            case 0x22, 0x5C, 0x2F: // '"', '\\', '/'
                units.append(0x5C)
                units.append(c)
            case 0x09: units.append(contentsOf: [0x5C, 0x74])
            case 0x08: units.append(contentsOf: [0x5C, 0x62])
            case 0x0A: units.append(contentsOf: [0x5C, 0x6E])
            case 0x0D: units.append(contentsOf: [0x5C, 0x72])
            case 0x0C: units.append(contentsOf: [0x5C, 0x66])
            default:
                if c <= 0x1F {
                    let hex = String(c, radix: 16)
                    units.append(contentsOf: Array(("\\u" + String(repeating: "0", count: 4 - hex.count) + hex).utf16))
                } else {
                    units.append(c)
                }
            }
        }
        units.append(0x22)
        out += String(decoding: units, as: UTF16.self)
    }

    /// JSONStringer.value(Object).
    static func writeValue(_ value: Any?, _ out: inout String) throws {
        guard let v = value else {
            out += "null"
            return
        }
        if let b = exactBool(v) {
            out += b ? "true" : "false"
            return
        }
        if isNumber(v) {
            out += try numberToString(v)
            return
        }
        switch v {
        case let a as AJSONArray: try a.writeTo(&out)
        case let o as AJSONObject: try o.writeTo(&out)
        case is AJSONNull: out += "null"
        default: quote(valueOf(v), &out)
        }
    }
}

/// org.json.JSONObject (Android): insertion-ordered name/value pairs.
final class AJSONObject: CustomStringConvertible {
    /// JSONObject.NULL.
    static let NULL = AJSONNull.instance

    private var order: [String] = []
    private var pairs: [String: Any] = [:]

    init() {}

    /// `JSONObject(String json)`: parses with the lenient JSONTokener; trailing text is ignored.
    init(_ json: String) throws {
        let value = try AJSONTokener(json).nextValue()
        guard let object = value as? AJSONObject else {
            throw AJSON.typeMismatch(value, "JSONObject")
        }
        order = object.order
        pairs = object.pairs
    }

    func length() -> Int { return order.count }

    /// `put(name, value)`: nil removes the name; numbers must be finite (Kotlin crashes on the
    /// JSONException otherwise). Returns this object for chaining.
    @discardableResult
    func put(_ name: String, _ value: Any?) -> AJSONObject {
        do {
            return try putChecked(name, value)
        } catch {
            preconditionFailure("JSONException: \(error)")
        }
    }

    /// `put(name, value)` that throws the JSONException instead of crashing.
    @discardableResult
    func putChecked(_ name: String, _ value: Any?) throws -> AJSONObject {
        guard let v = AJSON.normalize(value) else {
            _ = remove(name)
            return self
        }
        if let d = AJSON.doubleValue(v) {
            // deviate from the original by checking all Numbers, not just floats & doubles
            try AJSON.checkDouble(d)
        }
        if pairs.updateValue(v, forKey: name) == nil {
            order.append(name)
        }
        return self
    }

    /// `putOpt(name, value)`.
    @discardableResult
    func putOpt(_ name: String?, _ value: Any?) -> AJSONObject {
        guard let name = name, AJSON.normalize(value) != nil else { return self }
        return put(name, value)
    }

    @discardableResult
    func remove(_ name: String) -> Any? {
        guard let previous = pairs.removeValue(forKey: name) else { return nil }
        if let index = order.firstIndex(of: name) { order.remove(at: index) }
        return previous
    }

    func isNull(_ name: String) -> Bool {
        guard let value = pairs[name] else { return true }
        return value is AJSONNull
    }

    func has(_ name: String) -> Bool { return pairs[name] != nil }

    func get(_ name: String) throws -> Any {
        guard let result = pairs[name] else {
            throw AJSONException(message: "No value for \(name)")
        }
        return result
    }

    func opt(_ name: String) -> Any? { return pairs[name] }

    func getBoolean(_ name: String) throws -> Bool {
        let object = try get(name)
        guard let result = AJSON.toBoolean(object) else { throw AJSON.typeMismatch(name, object, "boolean") }
        return result
    }

    func optBoolean(_ name: String, _ fallback: Bool = false) -> Bool {
        return AJSON.toBoolean(opt(name)) ?? fallback
    }

    func getDouble(_ name: String) throws -> Double {
        let object = try get(name)
        guard let result = AJSON.toDouble(object) else { throw AJSON.typeMismatch(name, object, "double") }
        return result
    }

    func optDouble(_ name: String, _ fallback: Double = .nan) -> Double {
        return AJSON.toDouble(opt(name)) ?? fallback
    }

    func getInt(_ name: String) throws -> Int {
        let object = try get(name)
        guard let result = AJSON.toInteger(object) else { throw AJSON.typeMismatch(name, object, "int") }
        return result
    }

    func optInt(_ name: String, _ fallback: Int = 0) -> Int {
        return AJSON.toInteger(opt(name)) ?? fallback
    }

    func getLong(_ name: String) throws -> Int64 {
        let object = try get(name)
        guard let result = AJSON.toLong(object) else { throw AJSON.typeMismatch(name, object, "long") }
        return result
    }

    func optLong(_ name: String, _ fallback: Int64 = 0) -> Int64 {
        return AJSON.toLong(opt(name)) ?? fallback
    }

    func getString(_ name: String) throws -> String {
        let object = try get(name)
        guard let result = AJSON.toString(object) else { throw AJSON.typeMismatch(name, object, "String") }
        return result
    }

    /// `optString(name, fallback)`: note that a NULL value gives "null" on Android.
    func optString(_ name: String, _ fallback: String = "") -> String {
        return AJSON.toString(opt(name)) ?? fallback
    }

    func getJSONArray(_ name: String) throws -> AJSONArray {
        let object = try get(name)
        guard let array = object as? AJSONArray else { throw AJSON.typeMismatch(name, object, "JSONArray") }
        return array
    }

    func optJSONArray(_ name: String) -> AJSONArray? { return opt(name) as? AJSONArray }

    func getJSONObject(_ name: String) throws -> AJSONObject {
        let object = try get(name)
        guard let result = object as? AJSONObject else { throw AJSON.typeMismatch(name, object, "JSONObject") }
        return result
    }

    func optJSONObject(_ name: String) -> AJSONObject? { return opt(name) as? AJSONObject }

    /// `keys()`: the names in insertion order.
    func keys() -> [String] { return order }

    /// `names()`: nil when empty.
    func names() -> AJSONArray? {
        return order.isEmpty ? nil : AJSONArray(order.map { $0 as Any? })
    }

    /// `toString()`: compact JSON. Android returns null when a nested NaN/infinite number cannot be written;
    /// that case returns "null" here (see `toStringOrNull()`).
    func toString() -> String {
        return toStringOrNull() ?? "null"
    }

    /// `toString()` with Android's null result for unwritable numbers.
    func toStringOrNull() -> String? {
        var out = ""
        do {
            try writeTo(&out)
        } catch {
            return nil
        }
        return out
    }

    var description: String { return toString() }

    func writeTo(_ out: inout String) throws {
        out += "{"
        var first = true
        for name in order {
            if !first { out += "," }
            first = false
            AJSON.quote(name, &out)
            out += ":"
            try AJSON.writeValue(pairs[name], &out)
        }
        out += "}"
    }

    /// `JSONObject.quote(data)`.
    static func quote(_ data: String?) -> String {
        guard let data = data else { return "\"\"" }
        var out = ""
        AJSON.quote(data, &out)
        return out
    }

    /// `JSONObject.numberToString(number)`.
    static func numberToString(_ number: Any) throws -> String {
        return try AJSON.numberToString(AJSON.normalize(number) ?? number)
    }
}

/// org.json.JSONArray (Android). A Java null element (from `put(null)` or ",," in the input) is nil.
final class AJSONArray: CustomStringConvertible {
    private var values: [Any?] = []

    init() {}

    /// `JSONArray(String json)`.
    init(_ json: String) throws {
        let value = try AJSONTokener(json).nextValue()
        guard let array = value as? AJSONArray else {
            throw AJSON.typeMismatch(value, "JSONArray")
        }
        values = array.values
    }

    /// `JSONArray(Collection copyFrom)`: every element goes through JSONObject.wrap (nil -> NULL, lists ->
    /// JSONArray, unsupported objects -> Java null).
    init(_ copyFrom: [Any?]) {
        for element in copyFrom {
            values.append(AJSON.wrap(element))
        }
    }

    func length() -> Int { return values.count }

    /// `put(value)`: a Double goes through put(double) (finite only, Kotlin crashes otherwise); any other value
    /// is put(Object) unchecked; nil appends a Java null.
    @discardableResult
    func put(_ value: Any?) -> AJSONArray {
        let v = AJSON.normalize(value)
        if let v = v, let d = AJSON.exactDouble(v) {
            do {
                try AJSON.checkDouble(d)
            } catch {
                preconditionFailure("JSONException: \(error)")
            }
        }
        values.append(v)
        return self
    }

    /// The tokener's `result.put(value)` (put(Object): no check).
    func appendRaw(_ value: Any?) {
        values.append(value)
    }

    /// `put(index, value)`: pads with Java nulls.
    @discardableResult
    func put(_ index: Int, _ value: Any?) throws -> AJSONArray {
        let v = AJSON.normalize(value)
        if let v = v, let d = AJSON.doubleValue(v) {
            try AJSON.checkDouble(d)
        }
        while values.count <= index { values.append(nil) }
        values[index] = v
        return self
    }

    func isNull(_ index: Int) -> Bool {
        guard let value = opt(index) else { return true }
        return value is AJSONNull
    }

    func get(_ index: Int) throws -> Any {
        if index < 0 || index >= values.count {
            throw AJSONException(message: "Index \(index) out of range [0..\(values.count))")
        }
        guard let value = values[index] else {
            throw AJSONException(message: "Value at \(index) is null.")
        }
        return value
    }

    func opt(_ index: Int) -> Any? {
        if index < 0 || index >= values.count { return nil }
        return values[index]
    }

    @discardableResult
    func remove(_ index: Int) -> Any? {
        if index < 0 || index >= values.count { return nil }
        return values.remove(at: index)
    }

    func getBoolean(_ index: Int) throws -> Bool {
        let object = try get(index)
        guard let result = AJSON.toBoolean(object) else { throw AJSON.typeMismatch(index, object, "boolean") }
        return result
    }

    func optBoolean(_ index: Int, _ fallback: Bool = false) -> Bool {
        return AJSON.toBoolean(opt(index)) ?? fallback
    }

    func getDouble(_ index: Int) throws -> Double {
        let object = try get(index)
        guard let result = AJSON.toDouble(object) else { throw AJSON.typeMismatch(index, object, "double") }
        return result
    }

    func optDouble(_ index: Int, _ fallback: Double = .nan) -> Double {
        return AJSON.toDouble(opt(index)) ?? fallback
    }

    func getInt(_ index: Int) throws -> Int {
        let object = try get(index)
        guard let result = AJSON.toInteger(object) else { throw AJSON.typeMismatch(index, object, "int") }
        return result
    }

    func optInt(_ index: Int, _ fallback: Int = 0) -> Int {
        return AJSON.toInteger(opt(index)) ?? fallback
    }

    func getLong(_ index: Int) throws -> Int64 {
        let object = try get(index)
        guard let result = AJSON.toLong(object) else { throw AJSON.typeMismatch(index, object, "long") }
        return result
    }

    func optLong(_ index: Int, _ fallback: Int64 = 0) -> Int64 {
        return AJSON.toLong(opt(index)) ?? fallback
    }

    func getString(_ index: Int) throws -> String {
        let object = try get(index)
        guard let result = AJSON.toString(object) else { throw AJSON.typeMismatch(index, object, "String") }
        return result
    }

    func optString(_ index: Int, _ fallback: String = "") -> String {
        return AJSON.toString(opt(index)) ?? fallback
    }

    func getJSONArray(_ index: Int) throws -> AJSONArray {
        let object = try get(index)
        guard let result = object as? AJSONArray else { throw AJSON.typeMismatch(index, object, "JSONArray") }
        return result
    }

    func optJSONArray(_ index: Int) -> AJSONArray? { return opt(index) as? AJSONArray }

    func getJSONObject(_ index: Int) throws -> AJSONObject {
        let object = try get(index)
        guard let result = object as? AJSONObject else { throw AJSON.typeMismatch(index, object, "JSONObject") }
        return result
    }

    func optJSONObject(_ index: Int) -> AJSONObject? { return opt(index) as? AJSONObject }

    /// `toString()`: compact JSON; "null" where Android returns null (see `toStringOrNull()`).
    func toString() -> String {
        return toStringOrNull() ?? "null"
    }

    /// `toString()` with Android's null result (a NaN/infinite number cannot be written).
    func toStringOrNull() -> String? {
        var out = ""
        do {
            try writeTo(&out)
        } catch {
            return nil
        }
        return out
    }

    var description: String { return toString() }

    func writeTo(_ out: inout String) throws {
        out += "["
        var first = true
        for value in values {
            if !first { out += "," }
            first = false
            try AJSON.writeValue(value, &out)
        }
        out += "]"
    }
}

/// org.json.JSONTokener (Android), over UTF-16 units.
final class AJSONTokener {
    private let source: String
    private let input: [UInt16]
    private var pos = 0

    init(_ text: String) {
        var units = Array(text.utf16)
        // consume an optional byte order mark (BOM) if it exists
        if units.first == 0xFEFF {
            units.removeFirst()
        }
        input = units
        source = String(decoding: units, as: UTF16.self)
    }

    func nextValue() throws -> Any {
        let c = try nextCleanInternal()
        switch c {
        case -1:
            throw syntaxError("End of input")
        case 0x7B: // '{'
            return try readObject()
        case 0x5B: // '['
            return try readArray()
        case 0x27, 0x22: // '\'' '"'
            return try nextString(UInt16(c))
        default:
            pos -= 1
            return try readLiteral()
        }
    }

    private func nextCleanInternal() throws -> Int {
        let inLength = input.count
        while pos < inLength {
            let c = input[pos]
            pos += 1
            switch c {
            case 0x09, 0x20, 0x0A, 0x0D:
                continue
            case 0x2F: // '/'
                if pos == inLength {
                    return Int(c)
                }
                let peek = input[pos]
                switch peek {
                case 0x2A: // '*': skip a /* c-style comment */
                    pos += 1
                    guard let commentEnd = indexOf(0x2A, 0x2F, from: pos) else {
                        throw syntaxError("Unterminated comment")
                    }
                    pos = commentEnd + 2
                    continue
                case 0x2F: // '/': skip a // end-of-line comment
                    pos += 1
                    skipToEndOfLine()
                    continue
                default:
                    return Int(c)
                }
            case 0x23: // '#': skip a # hash end-of-line comment
                skipToEndOfLine()
                continue
            default:
                return Int(c)
            }
        }
        return -1
    }

    private func indexOf(_ a: UInt16, _ b: UInt16, from: Int) -> Int? {
        var i = from
        while i + 1 < input.count {
            if input[i] == a && input[i + 1] == b { return i }
            i += 1
        }
        return nil
    }

    private func skipToEndOfLine() {
        while pos < input.count {
            let c = input[pos]
            if c == 0x0D || c == 0x0A {
                pos += 1
                break
            }
            pos += 1
        }
    }

    /// Returns the string up to but not including `quote`, unescaping any character escape sequences.
    func nextString(_ quote: UInt16) throws -> String {
        var builder: [UInt16]? = nil
        // the index of the first character not yet appended to the builder.
        var start = pos
        while pos < input.count {
            let c = input[pos]
            pos += 1
            if c == quote {
                if var b = builder {
                    b.append(contentsOf: input[start..<(pos - 1)])
                    return String(decoding: b, as: UTF16.self)
                }
                return String(decoding: input[start..<(pos - 1)], as: UTF16.self)
            }
            if c == 0x5C { // '\\'
                if pos == input.count {
                    throw syntaxError("Unterminated escape sequence")
                }
                var b = builder ?? []
                b.append(contentsOf: input[start..<(pos - 1)])
                b.append(try readEscapeCharacter())
                builder = b
                start = pos
            }
        }
        throw syntaxError("Unterminated string")
    }

    private func readEscapeCharacter() throws -> UInt16 {
        let escaped = input[pos]
        pos += 1
        switch escaped {
        case 0x75: // 'u'
            if pos + 4 > input.count {
                throw syntaxError("Unterminated escape sequence")
            }
            let hex = String(decoding: input[pos..<(pos + 4)], as: UTF16.self)
            pos += 4
            guard let value = JavaParse.parseInt(hex, 16) else {
                throw syntaxError("Invalid escape sequence: " + hex)
            }
            return UInt16(truncatingIfNeeded: value)
        case 0x74: return 0x09 // 't'
        case 0x62: return 0x08 // 'b'
        case 0x6E: return 0x0A // 'n'
        case 0x72: return 0x0D // 'r'
        case 0x66: return 0x0C // 'f'
        default: return escaped // '\'', '"', '\\' and anything else
        }
    }

    private func readLiteral() throws -> Any {
        let literal = nextToInternal(Array("{}[]/\\:,=;# \t\u{0C}".utf16))
        if literal.isEmpty {
            throw syntaxError("Expected literal value")
        }
        let text = String(decoding: literal, as: UTF16.self)
        if text.kequalsIgnoreCase("null") {
            return AJSONNull.instance
        } else if text.kequalsIgnoreCase("true") {
            return true
        } else if text.kequalsIgnoreCase("false") {
            return false
        }

        /* try to parse as an integral type... */
        if !literal.contains(0x2E) {
            var base = 10
            var number = literal
            if number.count >= 2 && number[0] == 0x30 && (number[1] == 0x78 || number[1] == 0x58) {
                number = Array(number[2...])
                base = 16
            } else if number.count > 1 && number[0] == 0x30 {
                number = Array(number[1...])
                base = 8
            }
            if let longValue = JavaParse.parseLong(String(decoding: number, as: UTF16.self), base) {
                if longValue <= Int64(Int32.max) && longValue >= Int64(Int32.min) {
                    return Int(longValue)
                }
                return longValue
            }
            // integral numbers greater than Long.MAX_VALUE, exponential form (5e-10) and unquoted strings fall
            // through to floating point.
        }

        /* ...next try to parse as a floating point... */
        if let d = JavaParse.parseDouble(text) {
            return d
        }

        /* ... finally give up. We have an unquoted string */
        return text
    }

    private func nextToInternal(_ excluded: [UInt16]) -> [UInt16] {
        let start = pos
        while pos < input.count {
            let c = input[pos]
            if c == 0x0D || c == 0x0A || excluded.contains(c) {
                return Array(input[start..<pos])
            }
            pos += 1
        }
        return Array(input[start...])
    }

    private func readObject() throws -> AJSONObject {
        let result = AJSONObject()

        /* Peek to see if this is the empty object. */
        let first = try nextCleanInternal()
        if first == 0x7D { // '}'
            return result
        } else if first != -1 {
            pos -= 1
        }

        while true {
            let name = try nextValue()
            guard let key = name as? String else {
                throw syntaxError("Names must be strings, but \(AJSON.valueOf(name)) is of type \(AJSON.className(name))")
            }

            /* Expect the name/value separator to be either a colon ':', an equals sign '=', or an arrow "=>". */
            let separator = try nextCleanInternal()
            if separator != 0x3A && separator != 0x3D {
                throw syntaxError("Expected ':' after " + key)
            }
            if pos < input.count && input[pos] == 0x3E { // '>'
                pos += 1
            }

            try result.putChecked(key, try nextValue())

            switch try nextCleanInternal() {
            case 0x7D: // '}'
                return result
            case 0x3B, 0x2C: // ';' ','
                continue
            default:
                throw syntaxError("Unterminated object")
            }
        }
    }

    private func readArray() throws -> AJSONArray {
        let result = AJSONArray()

        /* to cover input that ends with ",]". */
        var hasTrailingSeparator = false

        while true {
            switch try nextCleanInternal() {
            case -1:
                throw syntaxError("Unterminated array")
            case 0x5D: // ']'
                if hasTrailingSeparator {
                    result.appendRaw(nil)
                }
                return result
            case 0x2C, 0x3B: // ',' ';'
                /* A separator without a value first means "null". */
                result.appendRaw(nil)
                hasTrailingSeparator = true
                continue
            default:
                pos -= 1
            }

            result.appendRaw(try nextValue())

            switch try nextCleanInternal() {
            case 0x5D: // ']'
                return result
            case 0x2C, 0x3B: // ',' ';'
                hasTrailingSeparator = true
                continue
            default:
                throw syntaxError("Unterminated array")
            }
        }
    }

    func syntaxError(_ message: String) -> AJSONException {
        return AJSONException(message: message + " at character \(pos) of \(source)")
    }
}

// MARK: - java.lang number parsing

/// Integer.parseInt / Long.parseLong / Double.parseDouble with Java's grammar.
enum JavaParse {
    /// Character.digit(c, radix) for ASCII digits and letters and Unicode decimal digits.
    static func digit(_ c: UInt16, _ radix: Int) -> Int {
        var d = -1
        if c >= 0x30 && c <= 0x39 {
            d = Int(c) - 0x30
        } else if c >= 0x61 && c <= 0x7A {
            d = Int(c) - 0x61 + 10
        } else if c >= 0x41 && c <= 0x5A {
            d = Int(c) - 0x41 + 10
        } else if c >= 0xFF21 && c <= 0xFF3A {
            d = Int(c) - 0xFF21 + 10 // fullwidth Latin capital letters
        } else if c >= 0xFF41 && c <= 0xFF5A {
            d = Int(c) - 0xFF41 + 10 // fullwidth Latin small letters
        } else if let scalar = Unicode.Scalar(c), scalar.properties.numericType == .decimal,
                  let value = scalar.properties.numericValue {
            d = Int(value)
        }
        return d < radix ? d : -1
    }

    /// Long.parseLong(s, radix); nil where Java throws NumberFormatException.
    static func parseLong(_ s: String, _ radix: Int) -> Int64? {
        let units = Array(s.utf16)
        let len = units.count
        if len == 0 { return nil }
        var negative = false
        var i = 0
        var limit = -Int64.max
        let firstChar = units[0]
        if firstChar < 0x30 { // Possible leading "+" or "-"
            if firstChar == 0x2D {
                negative = true
                limit = Int64.min
            } else if firstChar != 0x2B {
                return nil
            }
            if len == 1 { return nil } // Cannot have lone "+" or "-"
            i += 1
        }
        let r = Int64(radix)
        let multmin = limit / r
        var result: Int64 = 0
        while i < len {
            // Accumulating negatively avoids surprises near MAX_VALUE
            let d = digit(units[i], radix)
            i += 1
            if d < 0 || result < multmin { return nil }
            result *= r
            if result < limit + Int64(d) { return nil }
            result -= Int64(d)
        }
        return negative ? result : -result
    }

    /// Integer.parseInt(s, radix).
    static func parseInt(_ s: String, _ radix: Int) -> Int32? {
        guard let value = parseLong(s, radix), value >= Int64(Int32.min), value <= Int64(Int32.max) else {
            return nil
        }
        return Int32(value)
    }

    /// Double.parseDouble(s) / Double.valueOf(s): trimmed (units <= ' '), optional sign, "NaN", "Infinity",
    /// decimal digits with an optional point and exponent and an optional f/F/d/D suffix, or a hexadecimal
    /// "0x...p..." literal. nil where Java throws NumberFormatException.
    static func parseDouble(_ text: String) -> Double? {
        let units = Array(text.javaTrim().utf16)
        let len = units.count
        if len == 0 { return nil }
        var i = 0
        var negative = false
        if units[0] == 0x2D {
            negative = true
            i = 1
        } else if units[0] == 0x2B {
            i = 1
        }
        if i >= len { return nil }
        let rest = String(decoding: units[i...], as: UTF16.self)
        if units[i] == 0x4E { // 'N'
            return rest == "NaN" ? Double.nan : nil
        }
        if units[i] == 0x49 { // 'I'
            return rest == "Infinity" ? (negative ? -Double.infinity : Double.infinity) : nil
        }
        if units[i] == 0x30 && i + 1 < len && (units[i + 1] == 0x78 || units[i + 1] == 0x58) {
            return parseHex(units, i + 2, negative)
        }
        var intDigits: [UInt16] = []
        var fracDigits: [UInt16] = []
        var decSeen = false
        var anyDigit = false
        while i < len {
            let c = units[i]
            if c >= 0x30 && c <= 0x39 {
                if decSeen { fracDigits.append(c) } else { intDigits.append(c) }
                anyDigit = true
            } else if c == 0x2E {
                if decSeen { return nil } // multiple points
                decSeen = true
            } else {
                break
            }
            i += 1
        }
        if !anyDigit { return nil }
        var expText = "0"
        if i < len && (units[i] == 0x65 || units[i] == 0x45) {
            i += 1
            if i >= len { return nil }
            var expSign = ""
            if units[i] == 0x2D {
                expSign = "-"
                i += 1
            } else if units[i] == 0x2B {
                i += 1
            }
            let expAt = i
            while i < len && units[i] >= 0x30 && units[i] <= 0x39 { i += 1 }
            if i == expAt { return nil }
            var digits = Array(units[expAt..<i])
            while digits.count > 1 && digits[0] == 0x30 { digits.removeFirst() }
            // Exponents beyond what Double can express saturate exactly like Java (0 or infinity).
            expText = expSign + (digits.count > 9 ? "999999999" : String(decoding: digits, as: UTF16.self))
        }
        // Leftovers: only one trailing f/F/d/D is allowed.
        if i < len {
            let c = units[i]
            if i != len - 1 || (c != 0x66 && c != 0x46 && c != 0x64 && c != 0x44) { return nil }
        }
        let canonical = (negative ? "-" : "")
            + (intDigits.isEmpty ? "0" : String(decoding: intDigits, as: UTF16.self))
            + "." + (fracDigits.isEmpty ? "0" : String(decoding: fracDigits, as: UTF16.self))
            + "e" + expText
        return Double(canonical)
    }

    private static func parseHex(_ units: [UInt16], _ start: Int, _ negative: Bool) -> Double? {
        let len = units.count
        var i = start
        var mantissa: [UInt16] = []
        var sawDigit = false
        var sawPoint = false
        while i < len {
            let c = units[i]
            if digit(c, 16) >= 0 && c < 0x80 {
                mantissa.append(c)
                sawDigit = true
            } else if c == 0x2E && !sawPoint {
                mantissa.append(c)
                sawPoint = true
            } else {
                break
            }
            i += 1
        }
        if !sawDigit || i >= len || (units[i] != 0x70 && units[i] != 0x50) { return nil }
        i += 1
        var exponent: [UInt16] = []
        if i < len && (units[i] == 0x2B || units[i] == 0x2D) {
            exponent.append(units[i])
            i += 1
        }
        let expAt = i
        while i < len && units[i] >= 0x30 && units[i] <= 0x39 {
            exponent.append(units[i])
            i += 1
        }
        if i == expAt { return nil }
        if i < len {
            let c = units[i]
            if i != len - 1 || (c != 0x66 && c != 0x46 && c != 0x64 && c != 0x44) { return nil }
        }
        let canonical = (negative ? "-" : "") + "0x" + String(decoding: mantissa, as: UTF16.self)
            + "p" + String(decoding: exponent, as: UTF16.self)
        return Double(canonical)
    }
}

// MARK: - org.w3c.dom (javax.xml.parsers.DocumentBuilder on Android)

// DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(stream) on Android is libcore's
// org.apache.harmony.xml.parsers.DocumentBuilderImpl over KXmlParser (nextToken mode, not namespace aware, not
// coalescing, comments kept). Ported here statement by statement for the subset of XML the app reads:
// - input decoding as KXmlParser.setInput(stream, null): BOM / "<?xm" sniffing of the first 4 bytes (those bytes
//   are taken as Latin-1 chars), the declared encoding, otherwise UTF-8;
// - text: "\r\n" and "\r" become "\n"; "]]>" is an error; predefined (lt gt amp apos quot) and numeric character
//   references are merged into the surrounding text node; any other entity becomes an empty EntityReference node;
// - attribute values: "\r\n", "\r" and "\n" become ' ' (tabs are kept, unlike XML 1.0 normalization); references
//   are resolved, an unknown one stays as "&name;"; attributes keep source order (ElementImpl's ArrayList; a
//   repeated name moves to the end with the last value);
// - CDATA sections are their own nodes (empty ones are dropped), comments and processing instructions are nodes,
//   whitespace outside the root element is dropped, text merges into a preceding text node.
// A DOCTYPE is read and kept as a node, but its internal subset is only skipped (no entity or default-attribute
// declarations are applied; the app's XML has no DOCTYPE).

/// SAXException / DOMException / XmlPullParserException of DocumentBuilder.parse.
struct AXmlException: Error, CustomStringConvertible {
    let message: String
    var description: String { return message }
}

/// org.w3c.dom.Node.
class AXmlNode {
    static let ELEMENT_NODE = 1
    static let ATTRIBUTE_NODE = 2
    static let TEXT_NODE = 3
    static let CDATA_SECTION_NODE = 4
    static let ENTITY_REFERENCE_NODE = 5
    static let PROCESSING_INSTRUCTION_NODE = 7
    static let COMMENT_NODE = 8
    static let DOCUMENT_NODE = 9
    static let DOCUMENT_TYPE_NODE = 10

    var nodeName: String
    var nodeType: Int
    /// Node.getNodeValue(): the data of text, CDATA, comment and processing-instruction nodes and the value of an
    /// attribute; nil for elements, entity references, document types and the document.
    var nodeValue: String?
    fileprivate(set) var childNodes: [AXmlNode] = []
    weak fileprivate(set) var parentNode: AXmlNode?

    init(nodeName: String, nodeType: Int, nodeValue: String? = nil) {
        self.nodeName = nodeName
        self.nodeType = nodeType
        self.nodeValue = nodeValue
    }

    /// Node.getTextContent(): the value of text, CDATA, comment, processing-instruction and attribute nodes; for
    /// elements and entity references the text content of the children without comments and processing
    /// instructions (InnerNodeImpl.hasTextContent); "" for the document and document types (DOM: null).
    var textContent: String {
        switch nodeType {
        case AXmlNode.TEXT_NODE, AXmlNode.CDATA_SECTION_NODE, AXmlNode.COMMENT_NODE,
             AXmlNode.PROCESSING_INSTRUCTION_NODE, AXmlNode.ATTRIBUTE_NODE:
            return nodeValue ?? ""
        case AXmlNode.DOCUMENT_NODE, AXmlNode.DOCUMENT_TYPE_NODE:
            return ""
        default:
            var units: [UInt16] = []
            appendTextContent(&units)
            return String(decoding: units, as: UTF16.self)
        }
    }

    private func appendTextContent(_ units: inout [UInt16]) {
        for child in childNodes {
            switch child.nodeType {
            case AXmlNode.COMMENT_NODE, AXmlNode.PROCESSING_INSTRUCTION_NODE:
                continue
            case AXmlNode.TEXT_NODE, AXmlNode.CDATA_SECTION_NODE:
                units.append(contentsOf: (child.nodeValue ?? "").utf16)
            default:
                child.appendTextContent(&units)
            }
        }
    }

    var firstChild: AXmlNode? { return childNodes.first }
    var lastChild: AXmlNode? { return childNodes.last }
    func hasChildNodes() -> Bool { return !childNodes.isEmpty }

    /// Node.getNextSibling().
    var nextSibling: AXmlNode? {
        guard let parent = parentNode, let i = parent.childNodes.firstIndex(where: { $0 === self }) else { return nil }
        return i + 1 < parent.childNodes.count ? parent.childNodes[i + 1] : nil
    }

    /// Node.getPreviousSibling().
    var previousSibling: AXmlNode? {
        guard let parent = parentNode, let i = parent.childNodes.firstIndex(where: { $0 === self }) else { return nil }
        return i > 0 ? parent.childNodes[i - 1] : nil
    }

    fileprivate func appendChild(_ child: AXmlNode) {
        child.parentNode = self
        childNodes.append(child)
    }

    /// InnerNodeImpl.getElementsByTagName: descendant elements named `name` ("*" for all) in document order.
    fileprivate func collectElements(_ name: String, _ out: inout [AXmlElement]) {
        for child in childNodes {
            if let element = child as? AXmlElement {
                if name == "*" || element.nodeName == name { out.append(element) }
                element.collectElements(name, &out)
            }
        }
    }
}

/// org.w3c.dom.Attr.
final class AXmlAttr: AXmlNode {
    weak fileprivate(set) var ownerElement: AXmlElement?

    init(name: String, value: String) {
        super.init(nodeName: name, nodeType: AXmlNode.ATTRIBUTE_NODE, nodeValue: value)
    }

    /// Attr.getName().
    var name: String { return nodeName }
    /// Attr.getValue().
    var value: String { return nodeValue ?? "" }
}

/// org.w3c.dom.Element.
final class AXmlElement: AXmlNode {
    /// Element.getAttributes() (the NamedNodeMap): the attributes in source order.
    fileprivate(set) var attributes: [AXmlAttr] = []

    init(tagName: String) {
        super.init(nodeName: tagName, nodeType: AXmlNode.ELEMENT_NODE)
    }

    /// Element.getTagName().
    var tagName: String { return nodeName }

    /// Element.getAttributeNode(name).
    func getAttributeNode(_ n: String) -> AXmlAttr? {
        for attr in attributes where attr.nodeName == n { return attr }
        return nil
    }

    /// Element.getAttribute(name): "" when the attribute is missing.
    func getAttribute(_ n: String) -> String { return getAttributeNode(n)?.value ?? "" }

    func hasAttribute(_ n: String) -> Bool { return getAttributeNode(n) != nil }

    func hasAttributes() -> Bool { return !attributes.isEmpty }

    /// ElementImpl.setAttributeNode: a repeated name is removed and the new attribute goes to the end.
    fileprivate func setAttributeNode(_ attr: AXmlAttr) {
        if let i = attributes.firstIndex(where: { $0.nodeName == attr.nodeName }) {
            attributes.remove(at: i)
        }
        attributes.append(attr)
        attr.ownerElement = self
    }

    /// Element.getElementsByTagName(name): descendants in document order (this element excluded).
    func getElementsByTagName(_ name: String) -> [AXmlElement] {
        var out: [AXmlElement] = []
        collectElements(name, &out)
        return out
    }
}

/// org.w3c.dom.Document from DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(...).
final class AXmlDocument {
    /// The #document node: its children are the comments, processing instructions, document type and root element.
    let document: AXmlNode
    let documentElement: AXmlElement

    private init(document: AXmlNode, documentElement: AXmlElement) {
        self.document = document
        self.documentElement = documentElement
    }

    /// DocumentBuilder.parse(InputStream): throws AXmlException where Android throws SAXException (or the
    /// DOMException of a second root element). A document without a root element (Android returns a Document whose
    /// getDocumentElement() is null) throws as well.
    static func parse(_ data: Data) throws -> AXmlDocument {
        return try build(AXmlPullParser.decode(data))
    }

    /// DocumentBuilder.parse(InputSource(StringReader(text))): no byte-level encoding detection.
    static func parse(_ text: String) throws -> AXmlDocument {
        return try build(Array(text.utf16))
    }

    private static func build(_ units: [UInt16]) throws -> AXmlDocument {
        var builder = AXmlPullParser(units)
        let document = try builder.parseDocument()
        guard let element = document.childNodes.compactMap({ $0 as? AXmlElement }).first else {
            throw AXmlException(message: "No document element")
        }
        return AXmlDocument(document: document, documentElement: element)
    }

    /// Document.getChildNodes().
    var childNodes: [AXmlNode] { return document.childNodes }

    /// Document.getElementsByTagName(name): every element in document order, the root included.
    func getElementsByTagName(_ name: String) -> [AXmlElement] {
        var out: [AXmlElement] = []
        document.collectElements(name, &out)
        return out
    }
}

/// KXmlParser (Android libcore, android14-release) in nextToken() mode, not relaxed, not namespace aware, driven
/// by DocumentBuilderImpl.parse. Works on UTF-16 units like the Java char buffer.
private struct AXmlPullParser {
    private enum Token { case startTag, endTag, endDocument, entityRef, text, ignorableWhitespace, cdsect, comment, pi, docdecl }

    private let s: [UInt16]
    private var position = 0
    private var depth = 0
    private var degenerated = false
    private var parsedTopLevelStartTag = false
    private var hasSystemId = false
    private var openNames: [String] = []

    // The current token (KXmlParser.type, text, name, attributes).
    private var type: Token = .endDocument
    private var text: String? = nil
    private var name: String = ""
    private var attributeNames: [String] = []
    private var attributeValues: [String] = []
    private var isWhitespace = true

    init(_ units: [UInt16]) {
        s = units
    }

    // MARK: Input decoding (KXmlParser.setInput(InputStream, null))

    static func decode(_ data: Data) throws -> [UInt16] {
        let b = [UInt8](data)
        var charset: String? = nil
        var prefix: [UInt16] = []
        var start = 0
        // read the four bytes looking for an indication of the encoding in use
        let limit = Swift.min(4, b.count)
        for i in 0..<limit { prefix.append(UInt16(b[i])) }
        start = limit
        if limit == 4 {
            let f = UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3])
            switch f {
            case 0x0000_FEFF: // UTF-32BE BOM
                charset = "UTF-32BE"; prefix = []
            case 0xFFFE_0000: // UTF-32LE BOM
                charset = "UTF-32LE"; prefix = []
            case 0x0000_003C: // '<' in UTF-32BE
                charset = "UTF-32BE"; prefix = [0x3C]
            case 0x3C00_0000: // '<' in UTF-32LE
                charset = "UTF-32LE"; prefix = [0x3C]
            case 0x003C_003F: // "<?" in UTF-16BE
                charset = "UTF-16BE"; prefix = [0x3C, 0x3F]
            case 0x3C00_3F00: // "<?" in UTF-16LE
                charset = "UTF-16LE"; prefix = [0x3C, 0x3F]
            case 0x3C3F_786D: // "<?xm" in ASCII etc.
                var i = 4
                while i < b.count {
                    let c = b[i]
                    i += 1
                    prefix.append(UInt16(c))
                    if c == 0x3E { // '>'
                        let decl = Array(String(decoding: prefix, as: UTF16.self).utf16)
                        if let i0 = AXmlPullParser.indexOf(decl, Array("encoding".utf16)) {
                            var j = i0
                            while j < decl.count && decl[j] != 0x22 && decl[j] != 0x27 { j += 1 }
                            if j >= decl.count {
                                throw AXmlException(message: "Invalid stream or encoding: StringIndexOutOfBoundsException")
                            }
                            do {
                                let deli = decl[j]
                                j += 1
                                var k = j
                                while k < decl.count && decl[k] != deli { k += 1 }
                                if k < decl.count {
                                    charset = String(decoding: decl[j..<k], as: UTF16.self)
                                } else {
                                    throw AXmlException(message: "Invalid stream or encoding: StringIndexOutOfBoundsException")
                                }
                            }
                        }
                        break
                    }
                }
                start = i
            default:
                // handle a byte order mark followed by something other than <?
                if f & 0xFFFF_0000 == 0xFEFF_0000 {
                    charset = "UTF-16BE"; prefix = [UInt16(b[2]) << 8 | UInt16(b[3])]
                } else if f & 0xFFFF_0000 == 0xFFFE_0000 {
                    charset = "UTF-16LE"; prefix = [UInt16(b[3]) << 8 | UInt16(b[2])]
                } else if f & 0xFFFF_FF00 == 0xEFBB_BF00 {
                    charset = "UTF-8"; prefix = [UInt16(b[3])]
                }
            }
        }
        let rest = Array(b[start...])
        return prefix + (try decodeBytes(rest, charset ?? "UTF-8"))
    }

    private static func decodeBytes(_ bytes: [UInt8], _ charset: String) throws -> [UInt16] {
        switch charset.uppercased() {
        case "UTF-8", "UTF8":
            return Array(String(decoding: bytes, as: UTF8.self).utf16)
        case "UTF-16BE", "UTF-16", "UTF16", "UNICODE":
            var bigEndian = true
            var body = bytes[...]
            if charset.uppercased() != "UTF-16BE" && bytes.count >= 2 {
                if bytes[0] == 0xFF && bytes[1] == 0xFE { bigEndian = false; body = bytes[2...] }
                else if bytes[0] == 0xFE && bytes[1] == 0xFF { body = bytes[2...] }
            }
            return utf16Units(Array(body), bigEndian: bigEndian)
        case "UTF-16LE":
            return utf16Units(bytes, bigEndian: false)
        case "UTF-32BE", "UTF-32LE":
            let big = charset.uppercased() == "UTF-32BE"
            var scalars = String.UnicodeScalarView()
            var i = 0
            while i + 3 < bytes.count {
                let v = big
                    ? UInt32(bytes[i]) << 24 | UInt32(bytes[i + 1]) << 16 | UInt32(bytes[i + 2]) << 8 | UInt32(bytes[i + 3])
                    : UInt32(bytes[i + 3]) << 24 | UInt32(bytes[i + 2]) << 16 | UInt32(bytes[i + 1]) << 8 | UInt32(bytes[i])
                scalars.append(Unicode.Scalar(v) ?? "\u{FFFD}")
                i += 4
            }
            return Array(String(scalars).utf16)
        case "ISO-8859-1", "ISO8859-1", "ISO8859_1", "LATIN1", "L1":
            return bytes.map { UInt16($0) }
        case "US-ASCII", "ASCII":
            return bytes.map { $0 < 0x80 ? UInt16($0) : 0xFFFD }
        default:
            throw AXmlException(message: "Invalid stream or encoding: java.io.UnsupportedEncodingException: \(charset)")
        }
    }

    private static func utf16Units(_ bytes: [UInt8], bigEndian: Bool) -> [UInt16] {
        var out: [UInt16] = []
        out.reserveCapacity(bytes.count / 2)
        var i = 0
        while i + 1 < bytes.count {
            out.append(bigEndian ? UInt16(bytes[i]) << 8 | UInt16(bytes[i + 1]) : UInt16(bytes[i + 1]) << 8 | UInt16(bytes[i]))
            i += 2
        }
        if i < bytes.count { out.append(0xFFFD) } // a dangling byte is malformed input
        return out
    }

    private static func indexOf(_ hay: [UInt16], _ needle: [UInt16]) -> Int? {
        if needle.isEmpty || hay.count < needle.count { return nil }
        for i in 0...(hay.count - needle.count) where hay[i..<(i + needle.count)].elementsEqual(needle) { return i }
        return nil
    }

    // MARK: DocumentBuilderImpl.parse

    mutating func parseDocument() throws -> AXmlNode {
        let document = AXmlNode(nodeName: "#document", nodeType: AXmlNode.DOCUMENT_NODE)
        if try nextToken() == .endDocument {
            throw AXmlException(message: "Unexpected end of document")
        }
        try parse(document, document, isDocument: true)
        return document
    }

    /// DocumentBuilderImpl.parse(parser, document, node, endToken): the current token is the first one to handle.
    private mutating func parse(_ document: AXmlNode, _ node: AXmlNode, isDocument: Bool) throws {
        var token = type
        let endToken: Token = isDocument ? .endDocument : .endTag
        while token != endToken && token != .endDocument {
            switch token {
            case .pi:
                // Found a processing instruction: split the token text at the first space.
                let t = Array((text ?? "").utf16)
                let dot = t.firstIndex(of: 0x20)
                let target = dot != nil ? String(decoding: t[..<dot!], as: UTF16.self) : String(decoding: t, as: UTF16.self)
                let data = dot != nil ? String(decoding: t[(dot! + 1)...], as: UTF16.self) : ""
                try append(node, AXmlNode(nodeName: target, nodeType: AXmlNode.PROCESSING_INSTRUCTION_NODE, nodeValue: data))
            case .docdecl:
                try append(document, AXmlNode(nodeName: name, nodeType: AXmlNode.DOCUMENT_TYPE_NODE))
            case .comment:
                try append(node, AXmlNode(nodeName: "#comment", nodeType: AXmlNode.COMMENT_NODE, nodeValue: text ?? ""))
            case .ignorableWhitespace:
                // Whitespace before and after the document element is always ignored.
                if !isDocument { try appendText(node, token, text ?? "") }
            case .text, .cdsect:
                try appendText(node, token, text ?? "")
            case .entityRef:
                if let resolved = AXmlPullParser.resolvePredefinedOrCharacterEntity(name) {
                    try appendText(node, token, resolved)
                } else {
                    try append(node, AXmlNode(nodeName: name, nodeType: AXmlNode.ENTITY_REFERENCE_NODE))
                }
            case .startTag:
                let element = AXmlElement(tagName: name)
                try append(node, element)
                for i in attributeNames.indices {
                    element.setAttributeNode(AXmlAttr(name: attributeNames[i], value: attributeValues[i]))
                }
                // Recursive descent
                _ = try nextToken()
                try parse(document, element, isDocument: false)
                // Expect the element's end tag here
                if type != .endTag || name != element.nodeName {
                    throw AXmlException(message: "expected: END_TAG {null}\(element.nodeName)")
                }
            case .endTag, .endDocument:
                break
            }
            token = try nextToken()
        }
    }

    private func append(_ parent: AXmlNode, _ child: AXmlNode) throws {
        if parent.nodeType == AXmlNode.DOCUMENT_NODE {
            if child is AXmlElement && parent.childNodes.contains(where: { $0 is AXmlElement }) {
                throw AXmlException(message: "Only one root element allowed")
            }
            if child.nodeType == AXmlNode.DOCUMENT_TYPE_NODE
                && parent.childNodes.contains(where: { $0.nodeType == AXmlNode.DOCUMENT_TYPE_NODE }) {
                throw AXmlException(message: "Only one DOCTYPE element allowed")
            }
        }
        parent.appendChild(child)
    }

    /// DocumentBuilderImpl.appendText: empty runs are ignored; text (not CDATA) merges into a preceding text node.
    private func appendText(_ parent: AXmlNode, _ token: Token, _ value: String) throws {
        if value.isEmpty { return }
        if token != .cdsect, let last = parent.lastChild, last.nodeType == AXmlNode.TEXT_NODE {
            last.nodeValue = (last.nodeValue ?? "") + value
            return
        }
        try append(parent, token == .cdsect
            ? AXmlNode(nodeName: "#cdata-section", nodeType: AXmlNode.CDATA_SECTION_NODE, nodeValue: value)
            : AXmlNode(nodeName: "#text", nodeType: AXmlNode.TEXT_NODE, nodeValue: value))
    }

    private static func resolvePredefinedOrCharacterEntity(_ entityName: String) -> String? {
        // Character references, section 4.1 of the XML specification.
        if entityName.hasPrefix("#x") {
            return resolveCharacterReference(String(entityName.dropFirst(2)), 16)
        } else if entityName.hasPrefix("#") {
            return resolveCharacterReference(String(entityName.dropFirst(1)), 10)
        }
        // Predefined entities, section 4.6 of the XML specification.
        switch entityName {
        case "lt": return "<"
        case "gt": return ">"
        case "amp": return "&"
        case "apos": return "'"
        case "quot": return "\""
        default: return nil
        }
    }

    private static func resolveCharacterReference(_ value: String, _ base: Int) -> String? {
        guard let codePoint = JavaParse.parseInt(value, base), let units = codePointUnits(Int(codePoint)) else {
            return nil
        }
        return String(decoding: units, as: UTF16.self)
    }

    /// Character.toChars(codePoint); nil for an invalid code point (IllegalArgumentException).
    private static func codePointUnits(_ c: Int) -> [UInt16]? {
        if c < 0 || c > 0x10FFFF { return nil }
        if c < 0x10000 { return [UInt16(c)] }
        let v = c - 0x10000
        return [UInt16(0xD800 + (v >> 10)), UInt16(0xDC00 + (v & 0x3FF))]
    }

    // MARK: KXmlParser.next(justOneToken = true)

    private func fail(_ message: String) -> AXmlException {
        return AXmlException(message: message + " (position:\(position))")
    }

    private func peekCharacter() -> Int {
        return position < s.count ? Int(s[position]) : -1
    }

    private mutating func nextToken() throws -> Token {
        if type == .endTag {
            depth -= 1
            openNames.removeLast()
        }
        if degenerated {
            degenerated = false
            type = .endTag
            return type
        }
        var t = try peekType()
        if t == nil {
            try readXmlDeclaration()
            t = try peekType()
            if t == nil { throw fail("processing instructions must not start with xml") }
        }
        type = t!
        text = nil
        isWhitespace = true
        name = ""
        attributeNames = []
        attributeValues = []
        switch type {
        case .startTag:
            try parseStartTag()
            return type
        case .endTag:
            try readEndTag()
            return type
        case .endDocument:
            return type
        case .entityRef:
            var units: [UInt16] = []
            try readEntity(&units, isEntityToken: true, throwOnResolveFailure: false, attribute: false)
            text = String(decoding: units, as: UTF16.self)
        case .text, .ignorableWhitespace:
            text = try readValue(0x3C, resolveEntities: false, attribute: false)
            type = depth == 0 && isWhitespace ? .ignorableWhitespace : .text
        case .cdsect:
            try read(Array("<![CDATA[".utf16))
            text = try readUntil(Array("]]>".utf16))
        case .comment:
            try read(Array("<!--".utf16))
            text = try readUntil(Array("--".utf16))
            if peekCharacter() != 0x3E { throw fail("Comments may not contain --") }
            position += 1
        case .pi:
            try read(Array("<?".utf16))
            text = try readUntil(Array("?>".utf16))
        case .docdecl:
            try readDoctype()
            if parsedTopLevelStartTag { throw fail("Unexpected token") }
        }
        if depth == 0 && (type == .entityRef || type == .text || type == .cdsect) {
            throw fail("Unexpected token")
        }
        return type
    }

    /// KXmlParser.peekType(false); nil for an XML declaration ("<?xml ", case-insensitive name).
    private func peekType() throws -> Token? {
        if position >= s.count { return .endDocument }
        switch s[position] {
        case 0x26: // '&'
            return .entityRef
        case 0x3C: // '<'
            if position + 3 >= s.count { throw fail("Dangling <") }
            switch s[position + 1] {
            case 0x2F: // '/'
                return .endTag
            case 0x3F: // '?'
                if position + 5 < s.count
                    && (s[position + 2] == 0x78 || s[position + 2] == 0x58)
                    && (s[position + 3] == 0x6D || s[position + 3] == 0x4D)
                    && (s[position + 4] == 0x6C || s[position + 4] == 0x4C)
                    && s[position + 5] == 0x20 {
                    return nil
                }
                return .pi
            case 0x21: // '!'
                switch s[position + 2] {
                case 0x44: return .docdecl // <!D
                case 0x5B: return .cdsect // <![
                case 0x2D: return .comment // <!-
                case 0x45, 0x41, 0x4E: // <!EL <!EN <!A <!N outside a DTD
                    throw fail("Unexpected token")
                default:
                    throw fail("Unexpected <!")
                }
            default:
                return .startTag
            }
        default:
            return .text
        }
    }

    private mutating func readXmlDeclaration() throws {
        if position != 0 {
            throw fail("processing instructions must not start with xml")
        }
        try read(Array("<?".utf16))
        try parseStartTag(xmldecl: true)
        if attributeNames.isEmpty || attributeNames[0] != "version" {
            throw fail("version expected")
        }
        var pos = 1
        if pos < attributeNames.count && attributeNames[pos] == "encoding" {
            pos += 1
        }
        if pos < attributeNames.count && attributeNames[pos] == "standalone" {
            let st = attributeValues[pos]
            if st != "yes" && st != "no" {
                throw fail("illegal standalone value: " + st)
            }
            pos += 1
        }
        if pos != attributeNames.count {
            throw fail("unexpected attributes in XML declaration")
        }
        isWhitespace = true
        text = nil
    }

    private mutating func read(_ expected: UInt16) throws {
        let c = peekCharacter()
        if c != Int(expected) {
            throw fail("expected: '\(String(decoding: [expected], as: UTF16.self))' actual: '\(c < 0 ? "\u{FFFF}" : String(decoding: [UInt16(c)], as: UTF16.self))'")
        }
        position += 1
    }

    private mutating func read(_ chars: [UInt16]) throws {
        if position + chars.count > s.count {
            throw fail("expected: '\(String(decoding: chars, as: UTF16.self))' but was EOF")
        }
        for i in 0..<chars.count where s[position + i] != chars[i] {
            throw fail("expected: \"\(String(decoding: chars, as: UTF16.self))\"")
        }
        position += chars.count
    }

    /// Reads text up to the delimiter (exclusive) and consumes the delimiter.
    private mutating func readUntil(_ delimiter: [UInt16]) throws -> String {
        let start = position
        while true {
            if position + delimiter.count > s.count {
                throw fail("Unexpected EOF")
            }
            var match = true
            for i in 0..<delimiter.count where s[position + i] != delimiter[i] {
                match = false
                break
            }
            if match { break }
            position += 1
        }
        let end = position
        position += delimiter.count
        return String(decoding: s[start..<end], as: UTF16.self)
    }

    private mutating func skip() {
        while position < s.count && s[position] <= 0x20 {
            position += 1
        }
    }

    /// KXmlParser.readName (non-relaxed).
    private mutating func readName() throws -> String {
        if position >= s.count { throw fail("name expected") }
        let start = position
        let c = s[position]
        if (c >= 0x61 && c <= 0x7A) || (c >= 0x41 && c <= 0x5A) || c == 0x5F || c == 0x3A || c >= 0xC0 {
            position += 1
        } else {
            throw fail("name expected")
        }
        while position < s.count {
            let d = s[position]
            if (d >= 0x61 && d <= 0x7A) || (d >= 0x41 && d <= 0x5A) || (d >= 0x30 && d <= 0x39)
                || d == 0x5F || d == 0x2D || d == 0x3A || d == 0x2E || d >= 0xB7 {
                position += 1
                continue
            }
            break
        }
        return String(decoding: s[start..<position], as: UTF16.self)
    }

    /// KXmlParser.parseStartTag (also used for the XML declaration).
    private mutating func parseStartTag(xmldecl: Bool = false) throws {
        if !xmldecl {
            try read(0x3C)
        }
        name = try readName()
        attributeNames = []
        attributeValues = []
        while true {
            skip()
            if position >= s.count { throw fail("Unexpected EOF") }
            let c = s[position]
            if xmldecl {
                if c == 0x3F { // '?'
                    position += 1
                    try read(0x3E)
                    return
                }
            } else {
                if c == 0x2F { // '/'
                    degenerated = true
                    position += 1
                    skip()
                    try read(0x3E)
                    break
                } else if c == 0x3E { // '>'
                    position += 1
                    break
                }
            }
            let attrName = try readName()
            skip()
            if position >= s.count { throw fail("Unexpected EOF") }
            if s[position] == 0x3D { // '='
                position += 1
                skip()
                if position >= s.count { throw fail("Unexpected EOF") }
                let delimiter = s[position]
                if delimiter == 0x27 || delimiter == 0x22 {
                    position += 1
                } else {
                    throw fail("attr value delimiter missing!")
                }
                let value = try readValue(delimiter, resolveEntities: true, attribute: true, throwOnResolveFailure: xmldecl)
                if peekCharacter() == Int(delimiter) {
                    position += 1 // end quote
                }
                attributeNames.append(attrName)
                attributeValues.append(value)
            } else {
                throw fail("Attr.value missing f. " + attrName)
            }
        }
        depth += 1
        if depth == 1 {
            parsedTopLevelStartTag = true
        }
        openNames.append(name)
    }

    private mutating func readEndTag() throws {
        try read(0x3C)
        try read(0x2F)
        name = try readName()
        skip()
        try read(0x3E)
        if depth == 0 {
            throw fail("read end tag \(name) with no tags open")
        }
        if name != openNames[depth - 1] {
            throw fail("expected: /\(openNames[depth - 1]) read: \(name)")
        }
    }

    /// KXmlParser.readValue for text (delimiter '<') and quoted attribute values.
    private mutating func readValue(_ delimiter: UInt16, resolveEntities: Bool, attribute: Bool,
                                    throwOnResolveFailure: Bool = false) throws -> String {
        var result: [UInt16] = []
        while position < s.count {
            var c = s[position]
            if c == delimiter || (c == 0x26 && !resolveEntities) {
                break
            }
            if c != 0x0D && (c != 0x0A || !attribute) && c != 0x26 && c != 0x3C && (c != 0x5D || attribute) {
                isWhitespace = isWhitespace && c <= 0x20
                result.append(c)
                position += 1
                continue
            }
            if c == 0x0D { // '\r'
                if position + 1 < s.count && s[position + 1] == 0x0A {
                    position += 1
                }
                c = attribute ? 0x20 : 0x0A
            } else if c == 0x0A { // '\n' in an attribute value
                c = 0x20
            } else if c == 0x26 { // '&'
                isWhitespace = false
                try readEntity(&result, isEntityToken: false, throwOnResolveFailure: throwOnResolveFailure, attribute: attribute)
                continue
            } else if c == 0x3C { // '<' (only reachable in attribute values)
                throw fail("Illegal: \"<\" inside attribute value")
            } else if c == 0x5D { // ']' in text
                if position + 2 < s.count && s[position + 1] == 0x5D && s[position + 2] == 0x3E {
                    throw fail("Illegal: \"]]>\" outside CDATA section")
                }
                isWhitespace = false
            }
            position += 1
            result.append(c)
        }
        return String(decoding: result, as: UTF16.self)
    }

    /// KXmlParser.readEntity: resolves into `out`; an unresolved reference stays as "&name;".
    private mutating func readEntity(_ out: inout [UInt16], isEntityToken: Bool, throwOnResolveFailure: Bool,
                                     attribute: Bool) throws {
        let start = out.count
        position += 1 // '&'
        out.append(0x26)
        while true {
            let c = peekCharacter()
            if c == 0x3B { // ';'
                out.append(0x3B)
                position += 1
                break
            } else if c >= 128 || (c >= 0x30 && c <= 0x39) || (c >= 0x61 && c <= 0x7A) || (c >= 0x41 && c <= 0x5A)
                        || c == 0x5F || c == 0x2D || c == 0x23 {
                position += 1
                out.append(UInt16(c))
            } else {
                throw fail("unterminated entity ref")
            }
        }
        let code = String(decoding: out[(start + 1)..<(out.count - 1)], as: UTF16.self)
        if isEntityToken {
            name = code
        }
        if code.hasPrefix("#") {
            let value = code.hasPrefix("#x")
                ? JavaParse.parseInt(String(code.dropFirst(2)), 16)
                : JavaParse.parseInt(String(code.dropFirst(1)), 10)
            guard let v = value, let units = AXmlPullParser.codePointUnits(Int(v)) else {
                throw fail("Invalid character reference: &" + code)
            }
            out.removeSubrange(start...)
            out.append(contentsOf: units)
            return
        }
        if let defaultEntity = AXmlPullParser.resolvePredefinedOrCharacterEntity(code) {
            out.removeSubrange(start...)
            out.append(contentsOf: defaultEntity.utf16)
            return
        }
        // The parser skipped an external DTD: an unknown entity maps to the empty string.
        if hasSystemId {
            out.removeSubrange(start...)
            return
        }
        // keep the unresolved entity "&code;" in the text
        if throwOnResolveFailure {
            throw fail("unresolved: &\(code);")
        }
    }

    /// KXmlParser.readDoctype: the root element name and external id are read; the internal subset is skipped.
    private mutating func readDoctype() throws {
        try read(Array("<!DOCTYPE".utf16))
        skip()
        name = try readName()
        skip()
        let c = peekCharacter()
        if c == 0x53 { // 'S'
            try read(Array("SYSTEM".utf16))
            skip()
            _ = try readQuotedId()
            hasSystemId = true
        } else if c == 0x50 { // 'P'
            try read(Array("PUBLIC".utf16))
            skip()
            _ = try readQuotedId()
            skip()
            _ = try readQuotedId()
            hasSystemId = true
        }
        skip()
        if peekCharacter() == 0x5B { // '[': skip the internal subset, honouring quotes and comments
            position += 1
            while true {
                if position >= s.count { throw fail("Unexpected EOF") }
                let d = s[position]
                if d == 0x5D { // ']'
                    position += 1
                    break
                } else if d == 0x22 || d == 0x27 {
                    _ = try readQuotedId()
                } else if d == 0x3C && position + 3 < s.count && s[position + 1] == 0x21 && s[position + 2] == 0x2D
                            && s[position + 3] == 0x2D {
                    position += 4
                    _ = try readUntil(Array("-->".utf16))
                } else {
                    position += 1
                }
            }
        }
        skip()
        try read(0x3E)
        skip()
    }

    private mutating func readQuotedId() throws -> String {
        let quote = peekCharacter()
        if quote != 0x22 && quote != 0x27 {
            throw fail("Expected a quoted string")
        }
        position += 1
        return try readUntil([UInt16(quote)])
    }
}

// MARK: - java.util.TimeZone / Date / Calendar and java.text.SimpleDateFormat

/// java.util.TimeZone.
final class ATimeZone {
    let id: String
    let timeZone: TimeZone

    private init(id: String, timeZone: TimeZone) {
        self.id = id
        self.timeZone = timeZone
    }

    /// TimeZone.getTimeZone(id): unknown ids give GMT, like Java.
    static func getTimeZone(_ id: String) -> ATimeZone {
        if let tz = TimeZone(identifier: id) {
            return ATimeZone(id: id, timeZone: tz)
        }
        return ATimeZone(id: "GMT", timeZone: TimeZone(secondsFromGMT: 0)!)
    }

    /// TimeZone.getDefault().
    static func getDefault() -> ATimeZone {
        let tz = TimeZone.current
        return ATimeZone(id: tz.identifier, timeZone: tz)
    }

    func getID() -> String { return id }
}

/// java.util.Date (milliseconds since the epoch).
struct ADate {
    let time: Int64

    /// `Date()`: now.
    init() {
        time = Int64((Date().timeIntervalSince1970 * 1000).rounded(.down))
    }

    /// `Date(ms)`.
    init(_ ms: Int64) {
        time = ms
    }

    func getTime() -> Int64 { return time }

    var foundationDate: Date {
        return Date(timeIntervalSince1970: Double(time) / 1000)
    }
}

/// java.util.Calendar (GregorianCalendar) for the fields the app reads.
final class ACalendar {
    static let ERA = 0, YEAR = 1, MONTH = 2, WEEK_OF_YEAR = 3, WEEK_OF_MONTH = 4, DATE = 5, DAY_OF_MONTH = 5,
               DAY_OF_YEAR = 6, DAY_OF_WEEK = 7, DAY_OF_WEEK_IN_MONTH = 8, AM_PM = 9, HOUR = 10,
               HOUR_OF_DAY = 11, MINUTE = 12, SECOND = 13, MILLISECOND = 14
    static let SUNDAY = 1, MONDAY = 2, TUESDAY = 3, WEDNESDAY = 4, THURSDAY = 5, FRIDAY = 6, SATURDAY = 7
    static let JANUARY = 0, FEBRUARY = 1, MARCH = 2, APRIL = 3, MAY = 4, JUNE = 5, JULY = 6, AUGUST = 7,
               SEPTEMBER = 8, OCTOBER = 9, NOVEMBER = 10, DECEMBER = 11

    var timeZone: ATimeZone
    var timeInMillis: Int64
    /// First day of the week (SUNDAY = 1 ... SATURDAY = 7); the locale's CLDR value by default.
    var firstDayOfWeek: Int
    /// Minimal days in the first week of the year; the locale's CLDR value by default.
    var minimalDaysInFirstWeek: Int

    private init(_ zone: ATimeZone, _ locale: ALocale) {
        timeZone = zone
        timeInMillis = ADate().time
        var cal = Calendar(identifier: .gregorian)
        cal.locale = locale.foundationLocale
        firstDayOfWeek = cal.firstWeekday
        minimalDaysInFirstWeek = cal.minimumDaysInFirstWeek
    }

    static func getInstance() -> ACalendar { return ACalendar(ATimeZone.getDefault(), ALocale.getDefault()) }
    static func getInstance(_ zone: ATimeZone) -> ACalendar { return ACalendar(zone, ALocale.getDefault()) }
    static func getInstance(_ locale: ALocale) -> ACalendar { return ACalendar(ATimeZone.getDefault(), locale) }
    static func getInstance(_ zone: ATimeZone, _ locale: ALocale) -> ACalendar { return ACalendar(zone, locale) }

    /// `getTime()`.
    func getTime() -> ADate { return ADate(timeInMillis) }
    /// `setTime(date)`.
    func setTime(_ date: ADate) { timeInMillis = date.time }

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone.timeZone
        cal.firstWeekday = firstDayOfWeek
        cal.minimumDaysInFirstWeek = minimalDaysInFirstWeek
        return cal
    }

    /// `get(field)`.
    func get(_ field: Int) -> Int {
        let cal = calendar
        let date = ADate(timeInMillis).foundationDate
        switch field {
        case ACalendar.ERA: return cal.component(.era, from: date)
        case ACalendar.YEAR: return cal.component(.year, from: date)
        case ACalendar.MONTH: return cal.component(.month, from: date) - 1
        case ACalendar.WEEK_OF_YEAR: return cal.component(.weekOfYear, from: date)
        case ACalendar.WEEK_OF_MONTH: return cal.component(.weekOfMonth, from: date)
        case ACalendar.DAY_OF_MONTH: return cal.component(.day, from: date)
        case ACalendar.DAY_OF_YEAR: return cal.ordinality(of: .day, in: .year, for: date) ?? 1
        case ACalendar.DAY_OF_WEEK: return cal.component(.weekday, from: date)
        case ACalendar.DAY_OF_WEEK_IN_MONTH: return cal.component(.weekdayOrdinal, from: date)
        case ACalendar.AM_PM: return cal.component(.hour, from: date) < 12 ? 0 : 1
        case ACalendar.HOUR: return cal.component(.hour, from: date) % 12
        case ACalendar.HOUR_OF_DAY: return cal.component(.hour, from: date)
        case ACalendar.MINUTE: return cal.component(.minute, from: date)
        case ACalendar.SECOND: return cal.component(.second, from: date)
        case ACalendar.MILLISECOND: return Int(floorMod(timeInMillis, 1000))
        default: preconditionFailure("ArrayIndexOutOfBoundsException: Calendar field \(field)")
        }
    }
}

/// java.text.SimpleDateFormat for the pattern letters G y M L d H k K h m s S E a D (quoted text and other
/// characters are literal). Numbers use the locale's zero digit like Android's ICU-backed formatter.
final class ASimpleDateFormat {
    let pattern: String
    let locale: ALocale
    var timeZone: ATimeZone = ATimeZone.getDefault()

    private enum Token {
        case literal(String)
        case field(Character, Int)
    }

    private let tokens: [Token]

    /// `SimpleDateFormat(pattern, locale)`.
    init(_ pattern: String, _ locale: ALocale) {
        self.pattern = pattern
        self.locale = locale
        self.tokens = ASimpleDateFormat.compile(pattern)
    }

    /// `SimpleDateFormat(pattern)` with the default locale.
    convenience init(_ pattern: String) {
        self.init(pattern, ALocale.getDefault())
    }

    private static func compile(_ pattern: String) -> [Token] {
        var tokens: [Token] = []
        let chars = Array(pattern)
        var i = 0
        var literal = ""
        func flushLiteral() {
            if !literal.isEmpty {
                tokens.append(.literal(literal))
                literal = ""
            }
        }
        while i < chars.count {
            let c = chars[i]
            if c == "'" {
                if i + 1 < chars.count && chars[i + 1] == "'" {
                    literal.append("'")
                    i += 2
                    continue
                }
                // quoted text up to the next single quote ('' inside is a quote)
                i += 1
                while i < chars.count {
                    if chars[i] == "'" {
                        if i + 1 < chars.count && chars[i + 1] == "'" {
                            literal.append("'")
                            i += 2
                            continue
                        }
                        break
                    }
                    literal.append(chars[i])
                    i += 1
                }
                precondition(i < chars.count, "IllegalArgumentException: Unterminated quote")
                i += 1
                continue
            }
            if c.isASCII && c.isLetter {
                guard "GyMLdHkKhmsSEaD".contains(c) else {
                    preconditionFailure("IllegalArgumentException: Illegal pattern character '\(c)'")
                }
                flushLiteral()
                var count = 1
                while i + count < chars.count && chars[i + count] == c { count += 1 }
                tokens.append(.field(c, count))
                i += count
                continue
            }
            literal.append(c)
            i += 1
        }
        flushLiteral()
        return tokens
    }

    /// `format(date)`.
    func format(_ date: ADate) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone.timeZone
        let d = date.foundationDate
        let parts = cal.dateComponents([.era, .year, .month, .day, .hour, .minute, .second, .weekday], from: d)
        let millis = Int(floorMod(date.time, 1000))
        let symbols = DateFormatter()
        symbols.locale = locale.foundationLocale
        var out = ""
        for token in tokens {
            switch token {
            case .literal(let s):
                out += s
            case .field(let c, let count):
                switch c {
                case "G":
                    out += (parts.era ?? 1) == 1 ? "AD" : "BC"
                case "y":
                    let year = parts.year ?? 1970
                    out += count == 2 ? number(year % 100, 2) : number(year, count)
                case "M", "L":
                    let month = parts.month ?? 1
                    if count >= 4 {
                        out += (c == "L" ? symbols.standaloneMonthSymbols : symbols.monthSymbols)[month - 1]
                    } else if count == 3 {
                        out += (c == "L" ? symbols.shortStandaloneMonthSymbols : symbols.shortMonthSymbols)[month - 1]
                    } else {
                        out += number(month, count)
                    }
                case "d":
                    out += number(parts.day ?? 1, count)
                case "H":
                    out += number(parts.hour ?? 0, count)
                case "k":
                    let h = parts.hour ?? 0
                    out += number(h == 0 ? 24 : h, count)
                case "K":
                    out += number((parts.hour ?? 0) % 12, count)
                case "h":
                    let h = (parts.hour ?? 0) % 12
                    out += number(h == 0 ? 12 : h, count)
                case "m":
                    out += number(parts.minute ?? 0, count)
                case "s":
                    out += number(parts.second ?? 0, count)
                case "S":
                    out += number(millis, count)
                case "E":
                    let weekday = (parts.weekday ?? 1) - 1
                    out += (count >= 4 ? symbols.weekdaySymbols : symbols.shortWeekdaySymbols)[weekday]
                case "a":
                    out += (parts.hour ?? 0) < 12 ? symbols.amSymbol : symbols.pmSymbol
                case "D":
                    out += number(cal.ordinality(of: .day, in: .year, for: d) ?? 1, count)
                default:
                    break
                }
            }
        }
        return out
    }

    /// `format(date)` for a Foundation Date.
    func format(_ date: Date) -> String {
        return format(ADate(Int64((date.timeIntervalSince1970 * 1000).rounded(.down))))
    }

    /// zeroPaddingNumber: at least `minDigits` digits with the locale's zero digit.
    private func number(_ value: Int, _ minDigits: Int) -> String {
        let digits = String(value)
        let padded = digits.count < minDigits ? String(repeating: "0", count: minDigits - digits.count) + digits : digits
        let zero: UInt16 = locale.isUS || locale.language.isEmpty ? 0x30 : AFormatLocaleData.of(locale).zeroDigit
        if zero == 0x30 { return padded }
        return String(decoding: padded.utf16.map { $0 >= 0x30 && $0 <= 0x39 ? $0 - 0x30 + zero : $0 }, as: UTF16.self)
    }
}
