import Foundation

/// Android `typealias Node = Map<String, Any?>` with its tolerant accessors. Values come from
/// Swift code, JSONSerialization or Firebase (NSNumber, NSString, NSArray, NSDictionary).
typealias Node = [String: Any]

enum NodeValue {
    /// Firebase and JSONSerialization return booleans as CFBoolean-backed NSNumbers.
    static func isBoolean(_ value: Any) -> Bool {
        guard let boxed = value as? NSNumber else { return false }
        return CFGetTypeID(boxed) == CFBooleanGetTypeID()
    }

    /// Kotlin `as? Number` (a Boolean is not a Number), as exact as org.json's `Double.valueOf`.
    /// JSONSerialization writes 17 significant digits and returns a long fixed-point number such as
    /// "0.070000000000000007" as an NSDecimalNumber whose `doubleValue` is not correctly rounded
    /// (0.07 would come back as 0.07000000000000003); its exact decimal text reads back as the original.
    static func number(_ value: Any?) -> Double? {
        guard let value = value, !(value is NSNull), let boxed = value as? NSNumber, !isBoolean(boxed) else { return nil }
        if boxed is NSDecimalNumber, let exact = Double(boxed.stringValue) { return exact }
        return boxed.doubleValue
    }

    /// Kotlin `(x as? Number)?.toLong()` without passing through Double.
    static func int64(_ value: Any?) -> Int64? {
        guard let value = value, !(value is NSNull), let boxed = value as? NSNumber, !isBoolean(boxed) else { return nil }
        if CFNumberIsFloatType(boxed as CFNumber) { return KotlinNumber.long(boxed.doubleValue) }
        return boxed.int64Value
    }

    /// Kotlin `as? Boolean`.
    static func bool(_ value: Any?) -> Bool? {
        guard let value = value, !(value is NSNull), let boxed = value as? NSNumber, isBoolean(boxed) else { return nil }
        return boxed.boolValue
    }

    static func node(_ value: Any?) -> Node {
        return (value as? [String: Any]) ?? [:]
    }

    /// Kotlin `as? List<*> ?: (as? Map<*,*>)?.values`. Sparse Firebase arrays arrive as maps.
    static func list(_ value: Any?) -> [Any] {
        if let array = value as? [Any] { return array }
        if let map = value as? [String: Any] {
            let keys = map.keys.sorted(by: JavaOrder.firebaseKeyPrecedes)
            return keys.compactMap { map[$0] }
        }
        return []
    }

    /// Kotlin `toString()` for list items that should be strings.
    static func text(_ value: Any) -> String {
        if let s = value as? String { return s }
        if let boxed = value as? NSNumber {
            if isBoolean(boxed) { return boxed.boolValue ? "true" : "false" }
            return boxed.stringValue
        }
        return "\(value)"
    }

    /// Firebase and JSONSerialization reject NaN and infinity (and raise an exception), so
    /// every outgoing payload is sanitised: Android's engine never produces them either.
    static func sanitized(_ value: Any) -> Any {
        if let map = value as? [String: Any] {
            var out: [String: Any] = [:]
            for (key, item) in map { out[key] = sanitized(item) }
            return out
        }
        if let array = value as? [Any] { return array.map { sanitized($0) } }
        if let boxed = value as? NSNumber, !isBoolean(boxed), CFNumberIsFloatType(boxed as CFNumber), !boxed.doubleValue.isFinite {
            return 0.0
        }
        return value
    }
}

extension Dictionary where Key == String, Value == Any {
    func num(_ key: String, _ fallback: Double = 0) -> Double { return NodeValue.number(self[key]) ?? fallback }
    func str(_ key: String, _ fallback: String = "") -> String { return (self[key] as? String) ?? fallback }
    func flag(_ key: String) -> Bool { return NodeValue.bool(self[key]) ?? false }
    func list(_ key: String) -> [Any] { return NodeValue.list(self[key]) }
    func node(_ key: String) -> Node { return NodeValue.node(self[key]) }
    func has(_ key: String) -> Bool {
        guard let value = self[key] else { return false }
        return !(value is NSNull)
    }
}

enum NodeJSON {
    /// JSON text for persistence; nil instead of an exception for invalid content.
    static func string(_ node: Node) -> String? {
        let clean = NodeValue.sanitized(node)
        guard JSONSerialization.isValidJSONObject(clean),
              let data = try? JSONSerialization.data(withJSONObject: clean, options: []) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func node(_ text: String?) -> Node? {
        guard let text = text, let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: []) else { return nil }
        return object as? [String: Any]
    }
}
