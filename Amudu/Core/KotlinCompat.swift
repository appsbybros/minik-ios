import Foundation

/// Kotlin `kotlin.random.Random(seed: Long)` (XorWow), so seeded house players make the same choices as on Android.
/// Only the calls the Spud engine uses are ported: nextInt(), nextInt(until), nextDouble(), nextDouble(from, until)
/// and `Collection.random(random)` (nextIndex).
struct KotlinRandom {
    private var x: Int32
    private var y: Int32
    private var z: Int32
    private var w: Int32
    private var v: Int32
    private var addend: Int32

    init(seed: Int64) {
        let seed1 = Int32(truncatingIfNeeded: seed)
        let seed2 = Int32(truncatingIfNeeded: seed >> 32)
        x = seed1
        y = seed2
        z = 0
        w = 0
        v = ~seed1
        addend = (seed1 << 10) ^ Int32(bitPattern: UInt32(bitPattern: seed2) >> 4)
        for _ in 0..<64 { _ = nextInt() }
    }

    mutating func nextInt() -> Int32 {
        var t = x
        t = t ^ Int32(bitPattern: UInt32(bitPattern: t) >> 2)
        x = y
        y = z
        z = w
        let v0 = v
        w = v0
        t = (t ^ (t << 1)) ^ v0 ^ (v0 << 4)
        v = t
        addend = addend &+ 362437
        return t &+ addend
    }

    /// Kotlin `XorWowRandom.nextBits` (`takeUpperBits`).
    mutating func nextBits(_ bitCount: Int) -> Int32 {
        let raw = nextInt()
        if bitCount <= 0 { return 0 }
        return Int32(bitPattern: UInt32(bitPattern: raw) >> UInt32(32 - bitCount))
    }

    /// Kotlin `Random.nextDouble()`: 53 random bits in [0, 1).
    mutating func nextDouble() -> Double {
        let high = Int64(nextBits(26))
        let low = Int64(nextBits(27))
        return Double((high << 27) + low) / Double(Int64(1) << 53)
    }

    /// Kotlin `Random.nextDouble(from, until)` for finite bounds.
    mutating func nextDouble(_ from: Double, _ until: Double) -> Double {
        let r = from + nextDouble() * (until - from)
        return r >= until ? until.nextDown : r
    }

    /// Kotlin `Random.nextInt(until)` for `until > 0`.
    mutating func nextInt(until n: Int32) -> Int32 {
        if n & (0 &- n) == n {
            let bitCount = 31 - n.leadingZeroBitCount
            return nextBits(bitCount)
        }
        var bits: Int32 = 0
        var value: Int32 = 0
        repeat {
            bits = Int32(bitPattern: UInt32(bitPattern: nextInt()) >> 1)
            value = bits % n
        } while bits &- value &+ (n &- 1) < 0
        return value
    }

    /// Kotlin `Collection.random(random)` index: `random.nextInt(size)`.
    mutating func nextIndex(_ until: Int) -> Int {
        if until <= 0 { return 0 }
        return Int(nextInt(until: Int32(truncatingIfNeeded: until)))
    }

    /// Kotlin `Random.nextInt(from, until)` for `until > from`: `from + nextInt(until - from)`.
    mutating func nextInt(from: Int, until: Int) -> Int {
        return from + Int(nextInt(until: Int32(truncatingIfNeeded: until - from)))
    }

    /// Kotlin `Random.nextBoolean()`: `nextBits(1) != 0`.
    mutating func nextBoolean() -> Bool {
        return nextBits(1) != 0
    }

    /// Kotlin `MutableList.shuffle(random)` / `Iterable.shuffled(random)` (Fisher–Yates from the last index down).
    mutating func shuffled<T>(_ items: [T]) -> [T] {
        var list = items
        var i = list.count - 1
        while i >= 1 {
            let j = Int(nextInt(until: Int32(truncatingIfNeeded: i + 1)))
            list.swapAt(i, j)
            i -= 1
        }
        return list
    }
}

/// Kotlin/Java helpers whose exact semantics the Android code relies on.
enum Kotlin {
    /// `Math.floorMod` for Int.
    static func floorMod(_ value: Int, _ modulus: Int) -> Int {
        let r = value % modulus
        return (r != 0 && ((r < 0) != (modulus < 0))) ? r + modulus : r
    }

    /// `Math.floorMod` for Long.
    static func floorMod(_ value: Int64, _ modulus: Int64) -> Int64 {
        let r = value % modulus
        return (r != 0 && ((r < 0) != (modulus < 0))) ? r + modulus : r
    }

    /// Java `String.hashCode()` over UTF-16 code units.
    static func hashCode(_ text: String) -> Int32 {
        var h: Int32 = 0
        for unit in text.utf16 { h = h &* 31 &+ Int32(unit) }
        return h
    }

    /// Kotlin `String.compareTo`: lexicographic by UTF-16 code units.
    static func less(_ a: String, _ b: String) -> Bool {
        return Array(a.utf16).lexicographicallyPrecedes(Array(b.utf16))
    }

    /// Kotlin `Double.toInt()`: truncates, NaN becomes 0 and out-of-range values saturate.
    static func toInt(_ d: Double) -> Int {
        if d.isNaN { return 0 }
        if d >= Double(Int32.max) { return Int(Int32.max) }
        if d <= Double(Int32.min) { return Int(Int32.min) }
        return Int(d)
    }

    /// Kotlin `Double.toLong()`.
    static func toLong(_ d: Double) -> Int64 {
        if d.isNaN { return 0 }
        if d >= 9_223_372_036_854_775_807.0 { return Int64.max }
        if d <= -9_223_372_036_854_775_808.0 { return Int64.min }
        return Int64(d)
    }

    /// Kotlin `CharSequence.isBlank()`.
    static func isBlank(_ text: String) -> Bool {
        return text.unicodeScalars.allSatisfy { isWhitespace($0) }
    }

    /// Kotlin `Char.isWhitespace()` (Java isWhitespace || isSpaceChar).
    static func isWhitespace(_ s: Unicode.Scalar) -> Bool {
        switch s.value {
        case 0x09...0x0D, 0x1C...0x1F:
            return true
        default:
            break
        }
        switch s.properties.generalCategory {
        case .spaceSeparator, .lineSeparator, .paragraphSeparator:
            return true
        default:
            return false
        }
    }

    /// Kotlin `String.trim()`.
    static func trim(_ text: String) -> String {
        let scalars = Array(text.unicodeScalars)
        var start = 0
        var end = scalars.count
        while start < end && isWhitespace(scalars[start]) { start += 1 }
        while end > start && isWhitespace(scalars[end - 1]) { end -= 1 }
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars[start..<end])
        return String(view)
    }

    /// Leading characters for which `isWhitespace` holds (Kotlin `takeWhile`).
    static func leadingWhitespace(_ text: String) -> String {
        var view = String.UnicodeScalarView()
        for s in text.unicodeScalars {
            if !isWhitespace(s) { break }
            view.append(s)
        }
        return String(view)
    }

    /// Trailing characters for which `isWhitespace` holds (Kotlin `takeLastWhile`).
    static func trailingWhitespace(_ text: String) -> String {
        var collected: [Unicode.Scalar] = []
        for s in text.unicodeScalars.reversed() {
            if !isWhitespace(s) { break }
            collected.append(s)
        }
        var view = String.UnicodeScalarView()
        view.append(contentsOf: collected.reversed())
        return String(view)
    }

    /// Kotlin `coerceIn` for Double.
    static func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double {
        if value < low { return low }
        if value > high { return high }
        return value
    }

    /// Stable sort (Kotlin `sortedBy` is stable; Swift's `sorted` is not documented as stable).
    static func stableSorted<T>(_ items: [T], by less: (T, T) -> Bool) -> [T] {
        let indexed = Array(items.enumerated())
        let sorted = indexed.sorted { l, r in
            if less(l.element, r.element) { return true }
            if less(r.element, l.element) { return false }
            return l.offset < r.offset
        }
        return sorted.map { $0.element }
    }
}

/// Kotlin `linkedMapOf<String, String>()`: insertion-ordered; replacing a value keeps its position.
struct OrderedStringMap: Equatable {
    private(set) var keys: [String] = []
    private var storage: [String: String] = [:]

    init() {}

    init(_ pairs: [(String, String)]) {
        for (k, v) in pairs { self[k] = v }
    }

    subscript(key: String) -> String? {
        get { return storage[key] }
        set {
            if let value = newValue {
                if storage[key] == nil { keys.append(key) }
                storage[key] = value
            } else if storage[key] != nil {
                storage[key] = nil
                keys.removeAll { $0 == key }
            }
        }
    }

    var isEmpty: Bool { return keys.isEmpty }
    var count: Int { return keys.count }
    var values: [String] { return keys.compactMap { storage[$0] } }
    var entries: [(key: String, value: String)] { return keys.compactMap { k in storage[k].map { (key: k, value: $0) } } }
    var dictionary: [String: String] { return storage }

    mutating func removeAll() {
        keys.removeAll()
        storage.removeAll()
    }
}

/// Kotlin `LinkedHashSet<String>` used for consumed command IDs.
struct OrderedStringSet {
    private(set) var items: [String] = []
    private var members: Set<String> = []
    private var head = 0

    var count: Int { return members.count }

    /// Returns true when the value was not present (Kotlin `add`).
    mutating func insert(_ value: String) -> Bool {
        if members.contains(value) { return false }
        members.insert(value)
        items.append(value)
        return true
    }

    /// Kotlin `remove(first())`.
    mutating func removeFirst() {
        guard head < items.count else { return }
        members.remove(items[head])
        head += 1
        if head > 4096 {
            items.removeFirst(head)
            head = 0
        }
    }

    var ordered: [String] { return Array(items[head...]) }

    mutating func replace(with values: [String]) {
        items = []
        members = []
        head = 0
        for v in values { _ = insert(v) }
    }

    func contains(_ value: String) -> Bool { return members.contains(value) }
}
