import Foundation

/// Android `SnapshotWire`: public presentation precision; the atomic host-recovery checkpoint keeps full precision.
enum SnapshotWire {
    static func presentation(_ state: Node) -> Node {
        return AmuduCodec.node(compact(state))
    }

    /// Kotlin `compact`: a finite Double below one million (and every Float) is rounded to 4 decimals with
    /// `kotlin.math.round` (half to even); Int/Long, Booleans, Strings and nulls pass unchanged.
    static func compact(_ value: Any?) -> Any? {
        guard let value else { return nil }
        if value is NSNull { return value }
        if let map = value as? [String: Any] {
            var out: [String: Any] = [:]
            for (key, item) in map { out[key] = compact(item) ?? NSNull() }
            return out
        }
        if value is String { return value }
        if let list = value as? [Any] {
            return list.map { compact($0) ?? NSNull() }
        }
        let kind = type(of: value)
        if kind == Double.self, let d = value as? Double {
            if d.isFinite && abs(d) < 1_000_000 { return (d * 10_000).rounded(.toNearestOrEven) / 10_000 }
            return d
        }
        if kind == Float.self, let f = value as? Float {
            return (Double(f) * 10_000).rounded(.toNearestOrEven) / 10_000
        }
        // An NSNumber (a value read back from Firebase or JSON): only a floating-point number is a Kotlin Double.
        if kind is NSNumber.Type, let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), CFNumberIsFloatType(n) {
            let d = n.doubleValue
            if d.isFinite && abs(d) < 1_000_000 { return (d * 10_000).rounded(.toNearestOrEven) / 10_000 }
            return d
        }
        return value
    }
}

/// Kotlin `==` on the snapshot values (`Map`, `List`, Boolean, number, String, null) as a deep comparison. A missing
/// key and a null value are the same (Kotlin `map[key]` is null for both); Booleans never equal numbers.
enum NodeEquality {
    static func same(_ a: Any?, _ b: Any?) -> Bool {
        let aNull = AmuduCodec.isNull(a)
        let bNull = AmuduCodec.isNull(b)
        if aNull || bNull { return aNull && bNull }
        guard let a, let b else { return false }
        if let x = a as? [String: Any] {
            guard let y = b as? [String: Any] else { return false }
            for (key, value) in x where !same(value, y[key]) { return false }
            for (key, value) in y where x[key] == nil && !AmuduCodec.isNull(value) { return false }
            return true
        }
        if b is [String: Any] { return false }
        if let x = a as? String {
            guard let y = b as? String else { return false }
            return x == y
        }
        if b is String { return false }
        if let x = a as? [Any] {
            guard let y = b as? [Any], x.count == y.count else { return false }
            for i in 0..<x.count where !same(x[i], y[i]) { return false }
            return true
        }
        if b is [Any] { return false }
        let ab = AmuduCodec.boolean(a)
        let bb = AmuduCodec.boolean(b)
        if ab != nil || bb != nil { return ab == bb }
        if let x = AmuduCodec.number(a), let y = AmuduCodec.number(b) { return x == y }
        return false
    }
}
