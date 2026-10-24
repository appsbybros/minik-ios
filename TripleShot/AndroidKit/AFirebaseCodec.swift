import Foundation

// Firebase Android value semantics in pure Swift (no Firebase import; unit-tested in
// Tests/TripleShotTests/FirebaseCodecTests.swift against vectors produced by the real firebase-database 22.0.1
// classes on the JVM).
//
// Three representations meet here:
// 1. Firebase iOS values: what FirebaseDatabase hands out and accepts (NSDictionary / NSArray / NSNumber /
//    NSString / NSNull), and the Swift equivalents ([String: Any], [Any], Int64, Double, Bool, String).
// 2. AFirebaseNode: a database node as both SDKs hold it (empty, a leaf, or children in index order), built with
//    Android's NodeUtilities.NodeFromJSON rules.
// 3. "Plain" values: what Android's DataSnapshot.getValue() / MutableData.getValue() return and what
//    CustomClassMapper works on: String, Boolean, Long (Int64), Double, Map ([String: Any]) and List ([Any],
//    NSNull for a missing element). A node with array-like keys becomes a List exactly when Android's
//    ChildrenNode.getValue says so (all keys non-negative 32-bit integers without a leading zero and
//    maxKey < 2 * count), otherwise a Map.
//
// Kotlin model classes are mapped by the model layer (TripleShot/Model/TripleShotModelsFirebase.swift:
// `toFirebaseMap()` / `fromFirebaseOrThrow(_:)`, the CustomClassMapper output for every wire class including the
// "tms" and "finished" keys). AFirebaseMappable connects those codecs to DataSnapshot.getValue(X.self),
// MutableData.getValue/setValue and DatabaseReference.setValue/updateChildren.

// MARK: - Nodes

/// One leaf as Firebase Android holds it (StringNode, BooleanNode, LongNode, DoubleNode).
enum AFirebaseLeaf: Equatable {
    case string(String)
    case bool(Bool)
    case long(Int64)
    case double(Double)
}

/// A named child (Android NamedNode).
struct AFirebaseNamedNode: Equatable {
    let key: String
    let node: AFirebaseNode
}

/// A Firebase Realtime Database node (Android com.google.firebase.database.snapshot.Node).
/// `children` are in index order (child-key order, or the query's order for the top level of a query snapshot);
/// like Android's ChildrenNode the list is never empty and holds no empty child.
enum AFirebaseNode: Equatable {
    case empty
    case leaf(AFirebaseLeaf)
    case children([AFirebaseNamedNode])

    var isEmpty: Bool {
        if case .empty = self { return true }
        return false
    }

    var isLeafNode: Bool {
        if case .leaf = self { return true }
        return false
    }

    var namedChildren: [AFirebaseNamedNode] {
        if case .children(let kids) = self { return kids }
        return []
    }

    /// Node.getChildCount(): 0 for leaves and the empty node.
    var childCount: Int {
        return namedChildren.count
    }

    /// Node.getImmediateChild: the empty node for a missing key and for any key of a leaf.
    func child(_ key: String) -> AFirebaseNode {
        for kid in namedChildren where kid.key == key {
            return kid.node
        }
        return .empty
    }

    /// Node.getChild(Path).
    func child(path segments: [String]) -> AFirebaseNode {
        var node = self
        for segment in segments {
            node = node.child(segment)
            if node.isEmpty { return .empty }
        }
        return node
    }

    /// Node.updateChild(Path, Node): this node with `newChild` at `segments` (an empty node removes the child).
    func updatingChild(path segments: ArraySlice<String>, with newChild: AFirebaseNode) -> AFirebaseNode {
        guard let first = segments.first else { return newChild }
        let replaced = child(first).updatingChild(path: segments.dropFirst(), with: newChild)
        var kids = isLeafNode ? [] : namedChildren
        kids.removeAll { $0.key == first }
        if !replaced.isEmpty {
            kids.append(AFirebaseNamedNode(key: first, node: replaced))
            kids.sort { AFirebaseCodec.childKeyPrecedes($0.key, $1.key) }
        }
        return kids.isEmpty ? .empty : .children(kids)
    }
}

// MARK: - Codec

enum AFirebaseCodec {

    // MARK: Firebase iOS value -> node (NodeUtilities.NodeFromJSON)

    /// A Firebase iOS value (or its Swift equivalent) as a node: NSNull/nil -> empty; keys starting with "."
    /// are skipped and empty children dropped, like Android's NodeFromJSON; children sorted in Firebase key
    /// order; NSArray/[Any] children are keyed "0", "1", ... ; a map with ".sv" (a server value placeholder that
    /// was not resolved yet) is resolved the way the server would on an empty location.
    static func node(fromFirebaseValue value: Any?) -> AFirebaseNode {
        guard let value = unwrapped(value), !(value is NSNull) else { return .empty }
        if let text = value as? String {
            return .leaf(.string(text))
        }
        if let number = value as? NSNumber {
            return .leaf(leaf(of: number))
        }
        if let map = stringKeyedMap(value) {
            var source = map
            if let inner = source[".value"] {
                return node(fromFirebaseValue: inner)
            }
            if let serverValue = source[".sv"] {
                return resolvedServerValue(serverValue)
            }
            source.removeValue(forKey: ".priority")
            var kids: [AFirebaseNamedNode] = []
            for (key, item) in source where !key.hasPrefix(".") {
                let child = node(fromFirebaseValue: item)
                if !child.isEmpty {
                    kids.append(AFirebaseNamedNode(key: key, node: child))
                }
            }
            kids.sort { childKeyPrecedes($0.key, $1.key) }
            return kids.isEmpty ? .empty : .children(kids)
        }
        if let list = value as? [Any] {
            var kids: [AFirebaseNamedNode] = []
            for (index, item) in list.enumerated() {
                let child = node(fromFirebaseValue: item)
                if !child.isEmpty {
                    kids.append(AFirebaseNamedNode(key: String(index), node: child))
                }
            }
            return kids.isEmpty ? .empty : .children(kids)
        }
        if let plain = value as? AFirebaseNode {
            return plain
        }
        // Android: DatabaseException("Failed to parse node with class ...").
        ALog.w(LOG_TAG, "Failed to parse node with class \(type(of: value))")
        return .empty
    }

    /// The leaf an NSNumber stands for: CFBoolean -> Boolean; floating point -> Double; integers -> Long.
    /// NSDecimalNumber (JSONSerialization output for long literals) is read from its exact decimal text.
    static func leaf(of number: NSNumber) -> AFirebaseLeaf {
        if isBoolean(number) {
            return .bool(number.boolValue)
        }
        if number is NSDecimalNumber {
            let text = number.stringValue
            if let exact = Int64(text) { return .long(exact) }
            if let exact = Double(text) { return .double(exact) }
            return .double(number.doubleValue)
        }
        if CFNumberIsFloatType(number as CFNumber) {
            return .double(number.doubleValue)
        }
        return .long(number.int64Value)
    }

    static func isBoolean(_ number: NSNumber) -> Bool {
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    private static func resolvedServerValue(_ placeholder: Any) -> AFirebaseNode {
        // ServerValues.resolveDeferredValue on a location without a numeric value.
        if let name = placeholder as? String, name == "timestamp" {
            return .leaf(.long(Int64((Date().timeIntervalSince1970 * 1000).rounded(.down))))
        }
        if let op = stringKeyedMap(placeholder), let delta = op["increment"] as? NSNumber {
            return .leaf(leaf(of: delta))
        }
        return .empty
    }

    private static func stringKeyedMap(_ value: Any) -> [String: Any]? {
        if let map = value as? [String: Any] {
            return map
        }
        if let map = value as? [AnyHashable: Any] {
            var result: [String: Any] = [:]
            for (key, item) in map {
                guard let text = key.base as? String else { return nil }
                result[text] = item
            }
            return result
        }
        return nil
    }

    // MARK: Child keys (ChildKey.compareTo, Utilities.tryParseInt)

    /// Utilities.tryParseInt: at most 11 UTF-16 units, an optional '-', ASCII digits (leading zeros allowed), and
    /// within the 32-bit range.
    static func tryParseInt(_ text: String) -> Int32? {
        let units = Array(text.utf16)
        if units.count > 11 || units.isEmpty { return nil }
        var i = 0
        var negative = false
        if units[0] == 0x2D {
            if units.count == 1 { return nil }
            negative = true
            i = 1
        }
        var number: Int64 = 0
        while i < units.count {
            let c = units[i]
            if c < 0x30 || c > 0x39 { return nil }
            number = number * 10 + Int64(c - 0x30)
            i += 1
        }
        if negative {
            if -number < Int64(Int32.min) { return nil }
            return Int32(-number)
        }
        if number > Int64(Int32.max) { return nil }
        return Int32(number)
    }

    /// ChildKey.compareTo < 0: 32-bit integer keys first (by value, then by length), then the other keys by
    /// String.compareTo (UTF-16 code units).
    static func childKeyPrecedes(_ a: String, _ b: String) -> Bool {
        return compareChildKeys(a, b) < 0
    }

    static func compareChildKeys(_ a: String, _ b: String) -> Int {
        if a == b { return 0 }
        if a == MIN_KEY_NAME || b == MAX_KEY_NAME { return -1 }
        if b == MIN_KEY_NAME || a == MAX_KEY_NAME { return 1 }
        let ia = tryParseInt(a)
        let ib = tryParseInt(b)
        if let ia = ia {
            guard let ib = ib else { return -1 }
            if ia != ib { return ia < ib ? -1 : 1 }
            let la = a.utf16.count
            let lb = b.utf16.count
            return la == lb ? 0 : (la < lb ? -1 : 1)
        }
        if ib != nil { return 1 }
        return javaCompare(a, b)
    }

    /// java.lang.String.compareTo sign.
    static func javaCompare(_ a: String, _ b: String) -> Int {
        var ia = a.utf16.makeIterator()
        var ib = b.utf16.makeIterator()
        while true {
            switch (ia.next(), ib.next()) {
            case let (x?, y?):
                if x != y { return x < y ? -1 : 1 }
            case (nil, nil):
                return 0
            case (nil, _?):
                return -1
            case (_?, nil):
                return 1
            }
        }
    }

    static let MIN_KEY_NAME = "[MIN_NAME]"
    static let MAX_KEY_NAME = "[MAX_KEY]"

    // MARK: Node -> plain value (ChildrenNode.getValue / LeafNode.getValue)

    /// DataSnapshot.getValue(): nil for an empty node; String, Bool, Int64 (Long) or Double for a leaf; for
    /// children a [String: Any] (HashMap) or, when Android would build an ArrayList, an [Any] of length
    /// maxKey + 1 with NSNull for missing indices.
    static func plainValue(_ node: AFirebaseNode) -> Any? {
        switch node {
        case .empty:
            return nil
        case .leaf(let leaf):
            switch leaf {
            case .string(let s): return s
            case .bool(let b): return b
            case .long(let l): return l
            case .double(let d): return d
            }
        case .children(let kids):
            var result: [String: Any] = [:]
            var numKeys = 0
            var maxKey = 0
            var allIntegerKeys = true
            for kid in kids {
                result[kid.key] = plainValue(kid.node) ?? NSNull()
                numKeys += 1
                if allIntegerKeys {
                    if kid.key.utf16.count > 1 && kid.key.utf16.first == 0x30 {
                        allIntegerKeys = false
                    } else if let keyAsInt = tryParseInt(kid.key), keyAsInt >= 0 {
                        if Int(keyAsInt) > maxKey { maxKey = Int(keyAsInt) }
                    } else {
                        allIntegerKeys = false
                    }
                }
            }
            if allIntegerKeys && maxKey < 2 * numKeys {
                var array: [Any] = []
                array.reserveCapacity(maxKey + 1)
                for i in 0...maxKey {
                    array.append(result[String(i)] ?? NSNull())
                }
                return array
            }
            return result
        }
    }

    // MARK: Plain value -> Kotlin primitives (CustomClassMapper.deserializeToPrimitive / convertString)

    /// The java.lang class Android would name for a plain value (used in the exception texts).
    static func javaClassName(_ value: Any) -> String {
        if value is String { return "java.lang.String" }
        if let number = value as? NSNumber {
            if isBoolean(number) { return "java.lang.Boolean" }
            if case .double = leaf(of: number) { return "java.lang.Double" }
            return "java.lang.Long"
        }
        if value is [Any] { return "java.util.ArrayList" }
        if stringKeyedMap(value) != nil { return "java.util.HashMap" }
        return String(describing: type(of: value))
    }

    private enum JavaNumber {
        case long(Int64)
        case double(Double)
    }

    private static func javaNumber(_ value: Any) -> JavaNumber? {
        guard !(value is String), let number = value as? NSNumber, !isBoolean(number) else { return nil }
        switch leaf(of: number) {
        case .long(let l): return .long(l)
        case .double(let d): return .double(d)
        default: return nil
        }
    }

    /// Java `(long) d`: truncation toward zero, NaN -> 0, saturating at the Long range.
    static func javaLong(_ d: Double) -> Int64 {
        if d.isNaN { return 0 }
        if d >= 0x1p63 { return Int64.max }
        if d <= -0x1p63 { return Int64.min }
        return Int64(d)
    }

    /// convertInteger (Kotlin Int field / getValue(Int::class.java)).
    static func convertInteger(_ value: Any) throws -> Int {
        guard let number = javaNumber(value) else {
            throw ADatabaseException("Failed to convert a value of type \(javaClassName(value)) to int")
        }
        switch number {
        case .long(let l):
            let d = Double(l)
            if d >= -2147483648.0 && d <= 2147483647.0 { return Int(l) }
            throw ADatabaseException(
                "Numeric value out of 32-bit integer range: \(javaString(d)). Did you mean to use a long or double instead of an int?")
        case .double(let d):
            if d >= -2147483648.0 && d <= 2147483647.0 { return Int(d.rounded(.towardZero)) }
            throw ADatabaseException(
                "Numeric value out of 32-bit integer range: \(javaString(d)). Did you mean to use a long or double instead of an int?")
        }
    }

    /// convertLong (Kotlin Long field / getValue(Long::class.java)): a Double is truncated toward zero.
    static func convertLong(_ value: Any) throws -> Int64 {
        guard let number = javaNumber(value) else {
            throw ADatabaseException("Failed to convert a value of type \(javaClassName(value)) to long")
        }
        switch number {
        case .long(let l):
            return l
        case .double(let d):
            if d >= -0x1p63 && d <= 0x1p63 { return javaLong(d) }
            throw ADatabaseException(
                "Numeric value out of 64-bit long range: \(javaString(d)). Did you mean to use a double instead of a long?")
        }
    }

    /// convertDouble: a Long must survive the round trip through double.
    static func convertDouble(_ value: Any) throws -> Double {
        guard let number = javaNumber(value) else {
            throw ADatabaseException("Failed to convert a value of type \(javaClassName(value)) to double")
        }
        switch number {
        case .long(let l):
            let d = Double(l)
            if javaLong(d) == l { return d }
            throw ADatabaseException(
                "Loss of precision while converting number to double: \(l). Did you mean to use a 64-bit long instead?")
        case .double(let d):
            return d
        }
    }

    /// Float: `convertDouble(o).floatValue()`.
    static func convertFloat(_ value: Any) throws -> Float {
        return Float(try convertDouble(value))
    }

    /// convertBoolean: only a JSON boolean.
    static func convertBoolean(_ value: Any) throws -> Bool {
        if !(value is String), let number = value as? NSNumber, isBoolean(number) {
            return number.boolValue
        }
        throw ADatabaseException("Failed to convert value of type \(javaClassName(value)) to boolean")
    }

    /// convertString: only a JSON string.
    static func convertString(_ value: Any) throws -> String {
        if let text = value as? String {
            return text
        }
        throw ADatabaseException("Failed to convert value of type \(javaClassName(value)) to String")
    }

    // MARK: Swift value -> plain value (CustomClassMapper.convertToPlainJavaTypes)

    /// CustomClassMapper.serialize for the values Kotlin code writes: nil/NSNull -> nil; String; Bool;
    /// integers -> Int64; Float/Double -> Int64 when integral within +-2^63 (Java `longValue()`), else Double;
    /// a Kotlin enum -> its name; [String: Any] / KLinkedMap -> [String: Any] (nil values kept as NSNull so an
    /// update map can delete); [Any] -> [Any]; an AFirebaseMappable model -> its `toFirebaseMap()`. Unsupported
    /// types crash with the text of the DatabaseException Android throws.
    static func serialize(_ value: Any?) -> Any? {
        guard let value = unwrapped(value), !(value is NSNull) else { return nil }
        if let text = value as? String {
            return text
        }
        if let model = value as? any AFirebaseMappable {
            return serialize(model.toFirebaseMap())
        }
        if let kotlinEnum = value as? any KotlinEnum {
            // `((Enum<?>) o).name()`.
            return kotlinEnum.name
        }
        if value is AFirebaseUnorderedCollection || value is NSSet {
            preconditionFailure("Serializing Collections is not supported, please use Lists instead")
        }
        if let number = value as? NSNumber {
            return serializeNumber(number)
        }
        if let pairs = value as? AFirebaseOrderedPairs {
            var result: [String: Any] = [:]
            for (key, item) in pairs.aFirebasePairs {
                result[key] = serialize(item) ?? NSNull()
            }
            return result
        }
        if let map = value as? [String: Any] {
            var result: [String: Any] = [:]
            for (key, item) in map {
                result[key] = serialize(item) ?? NSNull()
            }
            return result
        }
        if value is [AnyHashable: Any] {
            preconditionFailure("Maps with non-string keys are not supported")
        }
        if let list = value as? [Any] {
            return list.map { serialize($0) ?? NSNull() }
        }
        if value is Character {
            preconditionFailure("Characters are not supported, please use Strings")
        }
        preconditionFailure("No properties to serialize found on class \(type(of: value))")
    }

    /// Numbers: Boolean stays Boolean; Float/Double -> Long when integral and within +-2^63, else Double;
    /// Integer/Long unchanged.
    static func serializeNumber(_ number: NSNumber) -> Any {
        switch leaf(of: number) {
        case .bool(let b):
            return b
        case .long(let l):
            return l
        case .double(let d):
            return serializeFloatingPoint(d)
        case .string(let s):
            return s
        }
    }

    /// `if (d <= Long.MAX_VALUE && d >= Long.MIN_VALUE && Math.floor(d) == d) return longValue(); return d;`
    static func serializeFloatingPoint(_ d: Double) -> Any {
        if d <= 0x1p63 && d >= -0x1p63 && d.rounded(.down) == d {
            return javaLong(d)
        }
        return d
    }

    /// A plain value as the Foundation objects FirebaseDatabase iOS accepts (NSNumber with the exact CFNumber
    /// type: Long -> SInt64, Double -> Float64, Boolean -> CFBoolean).
    static func firebaseValue(fromPlain value: Any?) -> Any {
        guard let value = unwrapped(value), !(value is NSNull) else { return NSNull() }
        if let text = value as? String {
            return text as NSString
        }
        if let number = value as? NSNumber {
            switch leaf(of: number) {
            case .bool(let b): return NSNumber(value: b)
            case .long(let l): return NSNumber(value: l)
            case .double(let d): return NSNumber(value: d)
            case .string(let s): return s as NSString
            }
        }
        if let map = stringKeyedMap(value) {
            let result = NSMutableDictionary(capacity: map.count)
            for (key, item) in map {
                result[key] = firebaseValue(fromPlain: item)
            }
            return result
        }
        if let list = value as? [Any] {
            let result = NSMutableArray(capacity: list.count)
            for item in list {
                result.add(firebaseValue(fromPlain: item))
            }
            return result
        }
        return value
    }

    // MARK: Validation (core/utilities/Validation.java)

    /// Validation.validatePathString: '.', '#', '$', '[' and ']' are not allowed (an empty path is allowed).
    static func pathProblem(_ path: String) -> String? {
        if path.utf16.contains(where: { $0 == 0x2E || $0 == 0x23 || $0 == 0x24 || $0 == 0x5B || $0 == 0x5D }) {
            return "Invalid Firebase Database path: \(path). Firebase Database paths must not contain '.', '#', '$', '[', or ']'"
        }
        return nil
    }

    /// Validation.validateRootPathString: like pathProblem, but ".info" is allowed at the start.
    static func rootPathProblem(_ path: String) -> String? {
        if path.hasPrefix(".info") { return pathProblem(String(path.dropFirst(5))) }
        if path.hasPrefix("/.info") { return pathProblem(String(path.dropFirst(6))) }
        return pathProblem(path)
    }

    /// new Path(pathString): the non-empty "/"-separated segments.
    static func pathSegments(_ path: String) -> [String] {
        return path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }

    /// Validation.validateWritableKey.
    static func writableKeyProblem(_ key: String) -> String? {
        let writable = !key.isEmpty
            && (key == ".value" || key == ".priority"
                || (!key.hasPrefix(".") && !key.utf16.contains(where: isInvalidKeyUnit)))
        if writable { return nil }
        return "Invalid key: \(key). Keys must not contain '/', '.', '#', '$', '[', or ']'"
    }

    private static func isInvalidKeyUnit(_ unit: UInt16) -> Bool {
        return unit == 0x5B || unit == 0x5D || unit == 0x2E || unit == 0x23 || unit == 0x24 || unit == 0x2F
            || unit <= 0x1F || unit == 0x7F
    }

    /// Validation.validateWritableObject on a plain value: keys of nested maps (not of server-value maps) must
    /// be writable keys, and no Double may be NaN or infinite.
    static func writableObjectProblem(_ value: Any?) -> String? {
        guard let value = unwrapped(value), !(value is NSNull) else { return nil }
        if value is String { return nil }
        if let number = value as? NSNumber {
            if case .double(let d) = leaf(of: number), !d.isFinite {
                return "Invalid value: Value cannot be NaN, Inf or -Inf."
            }
            return nil
        }
        if let map = stringKeyedMap(value) {
            if map[".sv"] != nil { return nil }
            for (key, item) in map {
                if let problem = writableKeyProblem(key) { return problem }
                if let problem = writableObjectProblem(item) { return problem }
            }
            return nil
        }
        if let list = value as? [Any] {
            for item in list {
                if let problem = writableObjectProblem(item) { return problem }
            }
        }
        return nil
    }

    // MARK: Push ids (core/utilities/PushIdGenerator.java)

    private static let PUSH_CHARS = Array("-0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz")
    nonisolated(unsafe) private static var lastPushTime: Int64 = 0
    nonisolated(unsafe) private static var lastRandChars = [Int](repeating: 0, count: 12)

    /// PushIdGenerator.generatePushChildName(now): 8 time characters (base 64, most significant first) and 12
    /// random characters, incremented instead of redrawn within the same millisecond. Used only when the
    /// Firebase SDK is unavailable (DatabaseReference.push() otherwise uses FirebaseDatabase's own generator,
    /// which is the same algorithm).
    static func generatePushChildName(_ now: Int64) -> String {
        let duplicateTime = now == lastPushTime
        lastPushTime = now
        var remaining = now
        var timeStampChars = [Character](repeating: "-", count: 8)
        for i in stride(from: 7, through: 0, by: -1) {
            timeStampChars[i] = PUSH_CHARS[Int(remaining % 64)]
            remaining = remaining / 64
        }
        if !duplicateTime {
            for i in 0..<12 {
                lastRandChars[i] = Int.random(in: 0..<64)
            }
        } else {
            for i in stride(from: 11, through: 0, by: -1) {
                if lastRandChars[i] != 63 {
                    lastRandChars[i] += 1
                    break
                }
                lastRandChars[i] = 0
            }
        }
        var result = String(timeStampChars)
        for i in 0..<12 {
            result.append(PUSH_CHARS[lastRandChars[i]])
        }
        return result
    }

    // MARK: Helpers

    static let LOG_TAG = "ClassMapper"

    /// The DatabaseException a conversion failure is on Android (the model codecs throw their own error type with
    /// the same text), so DatabaseError.fromException shows "com.google.firebase.database.DatabaseException: ...".
    static func databaseException(_ error: Error) -> Error {
        if error is AFirebaseException {
            return error
        }
        let text = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        return ADatabaseException(text)
    }

    /// An Optional boxed in Any (e.g. a Kotlin nullable stored in a map) unwrapped.
    static func unwrapped(_ value: Any?) -> Any? {
        guard let value = value else { return nil }
        if let box = value as? AFirebaseOptionalBox {
            return unwrapped(box.aFirebaseWrapped)
        }
        return value
    }
}

private protocol AFirebaseOptionalBox {
    var aFirebaseWrapped: Any? { get }
}

extension Optional: AFirebaseOptionalBox {
    fileprivate var aFirebaseWrapped: Any? {
        switch self {
        case .some(let wrapped): return wrapped
        case .none: return nil
        }
    }
}

/// An insertion-ordered String-keyed map (Kotlin LinkedHashMap) written as a Firebase object.
protocol AFirebaseOrderedPairs {
    var aFirebasePairs: [(String, Any?)] { get }
}

extension KLinkedMap: AFirebaseOrderedPairs where K == String {
    var aFirebasePairs: [(String, Any?)] {
        return entries.map { ($0.key, $0.value as Any?) }
    }
}

/// Kotlin sets, which CustomClassMapper refuses ("Serializing Collections is not supported").
private protocol AFirebaseUnorderedCollection {}

extension Set: AFirebaseUnorderedCollection {}
extension KLinkedSet: AFirebaseUnorderedCollection {}

// MARK: - Kotlin wire classes (CustomClassMapper beans)

/// A Kotlin data class that Firebase Android (de)serializes by reflection. The model layer supplies the exact
/// CustomClassMapper mapping; AFirebase uses it for `getValue(X.self)` on snapshots and mutable data and for
/// writing the object with `setValue` / `updateChildren` / `MutableData.value`.
protocol AFirebaseMappable {
    /// DataSnapshot.getValue(X::class.java) on the plain value: nil for no data; throws where Android's
    /// CustomClassMapper throws a DatabaseException.
    static func fromFirebaseOrThrow(_ value: Any?) throws -> Self?
    /// CustomClassMapper.convertToPlainJavaTypes(object).
    func toFirebaseMap() -> [String: Any]
}

extension RoomMeta: AFirebaseMappable {}
extension LivePlayerState: AFirebaseMappable {}
extension LiveHorseState: AFirebaseMappable {}
extension LeaderboardEntry: AFirebaseMappable {}
extension ShotReplaySample: AFirebaseMappable {}
extension LiveShotEvent: AFirebaseMappable {}
