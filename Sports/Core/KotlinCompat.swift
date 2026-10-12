import Foundation

/// Bit-exact port of Kotlin's `kotlin.random.Random(seed: Long)` (the XorWow generator).
/// Android seeds every question, rally decision and house-player choice with it, so an iOS
/// authority, a restored checkpoint or a saved match produces exactly the Android sequence.
final class KotlinRandom {
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
        // Kotlin discards the first 64 values of trivial seeds.
        for _ in 0..<64 { _ = nextRawInt() }
    }

    /// Kotlin `nextInt()`.
    func nextRawInt() -> Int32 {
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

    /// Kotlin `nextBits(bitCount)`: always consumes one value, even for zero bits.
    func nextBits(_ bitCount: Int) -> Int32 {
        let raw = UInt32(bitPattern: nextRawInt())
        if bitCount <= 0 { return 0 }
        if bitCount >= 32 { return Int32(bitPattern: raw) }
        return Int32(bitPattern: raw >> UInt32(32 - bitCount))
    }

    /// Kotlin `nextInt(until)`.
    func nextInt(_ until: Int) -> Int {
        return nextInt(0, until)
    }

    /// Kotlin `nextInt(from, until)` including its rejection sampling.
    func nextInt(_ from: Int, _ until: Int) -> Int {
        let low = Int32(truncatingIfNeeded: from)
        let high = Int32(truncatingIfNeeded: until)
        precondition(high > low, "Random range is empty")
        let n = high &- low
        if n > 0 || n == Int32.min {
            let rnd: Int32
            if n & (0 &- n) == n {
                let bitCount = 31 - n.leadingZeroBitCount
                rnd = nextBits(bitCount)
            } else {
                var value: Int32 = 0
                while true {
                    let bits = Int32(bitPattern: UInt32(bitPattern: nextRawInt()) >> 1)
                    value = bits % n
                    if bits &- value &+ (n &- 1) >= 0 { break }
                }
                rnd = value
            }
            return Int(low &+ rnd)
        }
        while true {
            let rnd = nextRawInt()
            if rnd >= low && rnd < high { return Int(rnd) }
        }
    }

    /// Kotlin `nextDouble()`.
    func nextDouble() -> Double {
        let hi = Int64(nextBits(26))
        let lo = Int64(nextBits(27))
        return Double((hi << 27) + lo) / Double(Int64(1) << 53)
    }

    /// Kotlin `nextDouble(from, until)`: never returns `until` itself.
    func nextDouble(_ from: Double, _ until: Double) -> Double {
        precondition(until > from, "Random range is empty")
        let size = until - from
        let r: Double
        if size.isInfinite && from.isFinite && until.isFinite {
            let r1 = nextDouble() * (until / 2 - from / 2)
            r = from + r1 + r1
        } else {
            r = from + nextDouble() * size
        }
        return r >= until ? until.nextDown : r
    }
}

/// Java `Math.floorMod`: the result has the sign of the divisor.
func floorMod(_ a: Int, _ n: Int) -> Int {
    let r = a % n
    return r != 0 && (r < 0) != (n < 0) ? r + n : r
}

extension Array {
    /// Kotlin `shuffled(random)` (Fisher-Yates from the last index down).
    func kotlinShuffled(_ random: KotlinRandom) -> [Element] {
        var result = self
        var i = result.count - 1
        while i >= 1 {
            let j = random.nextInt(i + 1)
            result.swapAt(i, j)
            i -= 1
        }
        return result
    }

    /// Kotlin `sortedBy` / `sortedWith` are stable; Swift's sort is not documented as stable.
    func stableSorted(by areInIncreasingOrder: (Element, Element) -> Bool) -> [Element] {
        let indexed = Array<(offset: Int, element: Element)>(self.enumerated())
        let ordered = indexed.sorted { a, b in
            if areInIncreasingOrder(a.element, b.element) { return true }
            if areInIncreasingOrder(b.element, a.element) { return false }
            return a.offset < b.offset
        }
        return ordered.map { $0.element }
    }
}

extension String {
    /// `java.lang.String.hashCode()` over UTF-16 code units.
    var javaHashCode: Int32 {
        var h: Int32 = 0
        for unit in utf16 { h = 31 &* h &+ Int32(unit) }
        return h
    }

    /// Kotlin `isBlank()` on the JVM: empty, or only `Character.isWhitespace` characters (Unicode
    /// space, line and paragraph separators, U+0009-U+000D and U+001C-U+001F).
    var kotlinIsBlank: Bool {
        return unicodeScalars.allSatisfy { s in
            (0x09...0x0D).contains(s.value) || (0x1C...0x1F).contains(s.value)
                || [.spaceSeparator, .lineSeparator, .paragraphSeparator].contains(s.properties.generalCategory)
        }
    }

    /// `java.lang.String.compareTo` (UTF-16 code unit order).
    func javaPrecedes(_ other: String) -> Bool {
        return Array(utf16).lexicographicallyPrecedes(Array(other.utf16))
    }
}

/// Android iterates Firebase maps in `java.util.HashMap` order. Room rosters, team assignment
/// and the lobby list follow that order, so iOS reproduces it exactly.
enum JavaOrder {
    /// Firebase child-key order: 32-bit integer keys numerically first, then UTF-16 order.
    static func firebaseKeyPrecedes(_ a: String, _ b: String) -> Bool {
        let ia = integerKey(a), ib = integerKey(b)
        if let ia = ia, let ib = ib {
            if ia != ib { return ia < ib }
            return a.utf16.count < b.utf16.count
        }
        if ia != nil { return true }
        if ib != nil { return false }
        return a.javaPrecedes(b)
    }

    private static func integerKey(_ key: String) -> Int32? {
        guard !key.isEmpty, key.utf16.count <= 11 else { return nil }
        var digits = Substring(key)
        if digits.hasPrefix("-") { digits = digits.dropFirst() }
        guard !digits.isEmpty, digits.allSatisfy({ $0 >= "0" && $0 <= "9" }) else { return nil }
        if digits.count > 1 && digits.hasPrefix("0") { return nil }
        return Int32(key)
    }

    /// Iteration order of a `java.util.HashMap<String, *>` filled in Firebase child order.
    static func hashMapOrder(_ keys: [String]) -> [String] {
        let sorted = keys.sorted(by: firebaseKeyPrecedes)
        var capacity = 16
        while Double(sorted.count) > Double(capacity) * 0.75 { capacity *= 2 }
        let mask = UInt32(capacity - 1)
        let buckets: [(bucket: UInt32, offset: Int, key: String)] = sorted.enumerated().map { pair in
            let h = UInt32(bitPattern: pair.element.javaHashCode)
            return (bucket: (h ^ (h >> 16)) & mask, offset: pair.offset, key: pair.element)
        }
        return buckets.sorted { a, b in
            if a.bucket != b.bucket { return a.bucket < b.bucket }
            return a.offset < b.offset
        }.map { $0.key }
    }
}

/// Kotlin enums travel by `name`; `ordinal` drives ordering and settings indices.
protocol KotlinEnum: RawRepresentable, CaseIterable, Hashable where RawValue == String {}

extension KotlinEnum {
    var name: String { return rawValue }
    var ordinal: Int { return Array(Self.allCases).firstIndex(of: self) ?? 0 }
    static func named(_ value: String) -> Self? { return Self(rawValue: value) }
}

/// Kotlin `Double.toInt()` / `toLong()`: truncation, NaN to zero, saturation instead of a trap.
enum KotlinNumber {
    static func int(_ value: Double) -> Int {
        if value.isNaN { return 0 }
        if value >= 2_147_483_647 { return Int(Int32.max) }
        if value <= -2_147_483_648 { return Int(Int32.min) }
        return Int(value)
    }

    static func long(_ value: Double) -> Int64 {
        if value.isNaN { return 0 }
        if value >= 0x1p63 { return Int64.max }
        if value <= -0x1p63 { return Int64.min }
        return Int64(value)
    }
}

/// `SystemClock.uptimeMillis()` and `System.currentTimeMillis()` equivalents.
enum SportsClock {
    static func uptimeMillis() -> Int64 {
        return Int64(ProcessInfo.processInfo.systemUptime * 1000)
    }

    static func currentTimeMillis() -> Int64 {
        return Int64(Date().timeIntervalSince1970 * 1000)
    }
}
