import Foundation

// AndroidKit: Kotlin stdlib semantics that the Android app relies on, bit for bit.
//
// Base: the proven Sports/Core/KotlinCompat.swift (KotlinRandom, JavaOrder, floorMod, shuffles, stable sort,
// javaHashCode, kotlinIsBlank, javaPrecedes, KotlinEnum, KotlinNumber) under the CORE-API names, extended to the
// whole kotlin.random / kotlin.math / kotlin.collections / kotlin.text surface the app uses. Sources checked:
// kotlin-stdlib 2.3.21 (Random.kt, XorWowRandom.kt, MathJVM.kt, _Collections.kt, Sequences.kt, Strings.kt,
// CharJVM.kt) and AOSP libcore main (java.lang.Math, java.util.HashMap/HashSet, java.lang.String).

// MARK: - Constants

/// `Math.PI.toFloat()` = 3.1415927f (bits 0x40490FDB). Never use `Float.pi` (0x40490FDA).
let PI_F: Float = Float(Double.pi)
/// `Math.E.toFloat()` = 2.7182817f.
let E_F: Float = Float(M_E)

// MARK: - kotlin.random

/// Bit-exact port of Kotlin's `kotlin.random.XorWowRandom` with the default implementations of
/// `kotlin.random.Random` (stdlib 2.3.21). `KotlinRandom(seed: Int64)` is Kotlin `Random(seed: Long)`,
/// `KotlinRandom(seed: Int)` is Kotlin `Random(seed: Int)`; every `next*` consumes exactly the same
/// raw values in the same order as Kotlin, including the rejection loops.
final class KotlinRandom {
    private var x: Int32
    private var y: Int32
    private var z: Int32
    private var w: Int32
    private var v: Int32
    private var addend: Int32

    /// Kotlin `Random(seed: Long)` = `XorWowRandom(seed.toInt(), seed.shr(32).toInt())`.
    convenience init(seed: Int64) {
        self.init(seed1: Int32(truncatingIfNeeded: seed), seed2: Int32(truncatingIfNeeded: seed &>> 32))
    }

    /// Kotlin `Random(seed: Int)` = `XorWowRandom(seed, seed.shr(31))`. A Swift `Int` carrying a Kotlin `Int`
    /// is truncated to its 32-bit value first, like the Kotlin parameter type.
    convenience init(seed: Int) {
        let s = Int32(truncatingIfNeeded: seed)
        self.init(seed1: s, seed2: s &>> 31)
    }

    /// `XorWowRandom(seed1, seed2)`: x = seed1, y = seed2, z = 0, w = 0, v = seed1.inv(),
    /// addend = (seed1 shl 10) xor (seed2 ushr 4); then 64 values are discarded.
    private init(seed1: Int32, seed2: Int32) {
        x = seed1
        y = seed2
        z = 0
        w = 0
        v = ~seed1
        addend = (seed1 &<< 10) ^ Int32(bitPattern: UInt32(bitPattern: seed2) &>> 4)
        precondition((x | y | z | w | v) != 0, "Initial state must have at least one non-zero element.")
        // Kotlin discards the first 64 values ("some trivial seeds can produce several values with zeroes").
        for _ in 0..<64 { _ = nextInt() }
    }

    /// Kotlin `Random.Default`. On Android it is the platform generator, never reproducible; here it is one
    /// XorWow instance seeded once from the system generator (the same distributions).
    static let Default: KotlinRandom = KotlinRandom(seed: Int64(bitPattern: UInt64.random(in: UInt64.min...UInt64.max)))

    /// Kotlin `nextInt()` (XorWowRandom.nextInt): the raw 32-bit value.
    func nextInt() -> Int32 {
        var t = x
        t = t ^ Int32(bitPattern: UInt32(bitPattern: t) &>> 2)
        x = y
        y = z
        z = w
        let v0 = v
        w = v0
        t = (t ^ (t &<< 1)) ^ v0 ^ (v0 &<< 4)
        v = t
        addend = addend &+ 362437
        return t &+ addend
    }

    /// Same as `nextInt()` (the name used by the older Swift ports and their tests).
    func nextRawInt() -> Int32 {
        return nextInt()
    }

    /// Kotlin `nextBits(bitCount)` = `nextInt().takeUpperBits(bitCount)`; always consumes one value.
    func nextBits(_ bitCount: Int) -> Int32 {
        return KotlinRandom.takeUpperBits(nextInt(), bitCount)
    }

    /// Kotlin `Int.takeUpperBits(bitCount)` = `this.ushr(32 - bitCount) and (-bitCount).shr(31)`
    /// (JVM shift counts are masked to 5 bits).
    static func takeUpperBits(_ value: Int32, _ bitCount: Int) -> Int32 {
        let shift = UInt32(truncatingIfNeeded: 32 &- bitCount) & 31
        let shifted = Int32(bitPattern: UInt32(bitPattern: value) &>> shift)
        let mask = Int32(truncatingIfNeeded: 0 &- bitCount) &>> 31
        return shifted & mask
    }

    /// Kotlin `fastLog2(value)` = `31 - value.countLeadingZeroBits()`.
    private static func fastLog2(_ value: Int32) -> Int {
        return 31 - value.leadingZeroBitCount
    }

    /// Kotlin `nextInt(until)` = `nextInt(0, until)`.
    func nextInt(_ until: Int) -> Int {
        return nextInt(0, until)
    }

    /// Kotlin `nextInt(from, until)` including the power-of-two path, the rejection loop and the
    /// full-range loop. An empty range crashes like Kotlin's IllegalArgumentException.
    func nextInt(_ from: Int, _ until: Int) -> Int {
        let low = Int32(truncatingIfNeeded: from)
        let high = Int32(truncatingIfNeeded: until)
        precondition(high > low, "Random range is empty: [\(low), \(high)).")
        let n = high &- low
        if n > 0 || n == Int32.min {
            let rnd: Int32
            if n & (0 &- n) == n {
                let bitCount = KotlinRandom.fastLog2(n)
                rnd = nextBits(bitCount)
            } else {
                var value: Int32
                var bits: Int32
                repeat {
                    bits = Int32(bitPattern: UInt32(bitPattern: nextInt()) &>> 1)
                    value = bits % n
                } while bits &- value &+ (n &- 1) < 0
                rnd = value
            }
            return Int(low &+ rnd)
        } else {
            while true {
                let rnd = nextInt()
                if rnd >= low && rnd < high { return Int(rnd) }
            }
        }
    }

    /// Kotlin `Random.nextInt(range: IntRange)` (and so `IntRange.random(random)`).
    func nextInt(_ range: ClosedRange<Int>) -> Int {
        let first = range.lowerBound
        let last = range.upperBound
        if last < Int(Int32.max) { return nextInt(first, last + 1) }
        if first > Int(Int32.min) { return nextInt(first - 1, last) + 1 }
        return Int(nextInt())
    }

    /// Kotlin `nextLong()` = `nextInt().toLong().shl(32) + nextInt()` (the second value sign-extended).
    func nextLong() -> Int64 {
        let high = Int64(nextInt()) &<< 32
        let low = Int64(nextInt())
        return high &+ low
    }

    /// Kotlin `nextLong(until)` = `nextLong(0, until)`.
    func nextLong(_ until: Int64) -> Int64 {
        return nextLong(0, until)
    }

    /// Kotlin `nextLong(from, until)` with the three power-of-two cases, the rejection loop and the
    /// full-range loop.
    func nextLong(_ from: Int64, _ until: Int64) -> Int64 {
        precondition(until > from, "Random range is empty: [\(from), \(until)).")
        let n = until &- from
        if n > 0 {
            let rnd: Int64
            if n & (0 &- n) == n {
                let nLow = Int32(truncatingIfNeeded: n)
                let nHigh = Int32(truncatingIfNeeded: Int64(bitPattern: UInt64(bitPattern: n) &>> 32))
                if nLow != 0 {
                    let bitCount = KotlinRandom.fastLog2(nLow)
                    // toUInt().toLong()
                    rnd = Int64(UInt32(bitPattern: nextBits(bitCount)))
                } else if nHigh == 1 {
                    // toUInt().toLong()
                    rnd = Int64(UInt32(bitPattern: nextInt()))
                } else {
                    let bitCount = KotlinRandom.fastLog2(nHigh)
                    let high = Int64(nextBits(bitCount)) &<< 32
                    rnd = high &+ Int64(UInt32(bitPattern: nextInt()))
                }
            } else {
                var value: Int64
                var bits: Int64
                repeat {
                    bits = Int64(bitPattern: UInt64(bitPattern: nextLong()) &>> 1)
                    value = bits % n
                } while bits &- value &+ (n &- 1) < 0
                rnd = value
            }
            return from &+ rnd
        } else {
            while true {
                let rnd = nextLong()
                if rnd >= from && rnd < until { return rnd }
            }
        }
    }

    /// Kotlin `Random.nextLong(range: LongRange)`.
    func nextLong(_ range: ClosedRange<Int64>) -> Int64 {
        let first = range.lowerBound
        let last = range.upperBound
        if last < Int64.max { return nextLong(first, last + 1) }
        if first > Int64.min { return nextLong(first - 1, last) + 1 }
        return nextLong()
    }

    /// Kotlin `nextFloat()` = `nextBits(24) / (1 shl 24).toFloat()`.
    func nextFloat() -> Float {
        return Float(nextBits(24)) / Float(1 << 24)
    }

    /// Kotlin `nextDouble()` = `doubleFromParts(nextBits(26), nextBits(27))`.
    func nextDouble() -> Double {
        let hi26 = nextBits(26)
        let low27 = nextBits(27)
        return Double((Int64(hi26) &<< 27) &+ Int64(low27)) / Double(Int64(1) &<< 53)
    }

    /// Kotlin `nextDouble(until)` = `nextDouble(0.0, until)`.
    func nextDouble(_ until: Double) -> Double {
        return nextDouble(0.0, until)
    }

    /// Kotlin `nextDouble(from, until)`: never returns `until` itself.
    func nextDouble(_ from: Double, _ until: Double) -> Double {
        precondition(until > from, "Random range is empty: [\(from), \(until)).")
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

    /// Kotlin `nextBoolean()` = `nextBits(1) != 0`.
    func nextBoolean() -> Bool {
        return nextBits(1) != 0
    }
}

// MARK: - Kotlin enums

/// Kotlin `enum class`: raw value = case name, case order = ordinal order.
protocol KotlinEnum: RawRepresentable, CaseIterable, Hashable where RawValue == String {}

extension KotlinEnum {
    /// Kotlin `name`.
    var name: String { return rawValue }
    /// Kotlin `ordinal` (declaration order).
    var ordinal: Int { return Array(Self.allCases).firstIndex(of: self) ?? 0 }
    /// Kotlin `valueOf(s)` without the exception: nil for an unknown name.
    static func named(_ value: String) -> Self? { return Self(rawValue: value) }
}

// MARK: - References and ordered collections

/// A shared mutable box: Kotlin reference semantics for values that Swift would copy.
final class KRef<T> {
    var value: T
    init(_ value: T) { self.value = value }
}

/// Kotlin `LinkedHashMap` / `mutableMapOf` / `linkedMapOf`: insertion-ordered; re-setting a key keeps its
/// position, removing it forgets the position. Iterates `(key:, value:)` pairs in insertion order.
struct KLinkedMap<K: Hashable, V>: Sequence {
    private var order: [K] = []
    private var storage: [K: V] = [:]

    init() {}

    /// `linkedMapOf(pairs)`: a repeated key keeps its first position and takes the last value.
    init(_ pairs: [(K, V)]) {
        for (k, v) in pairs { self[k] = v }
    }

    subscript(key: K) -> V? {
        get { return storage[key] }
        set {
            if let value = newValue {
                if storage.updateValue(value, forKey: key) == nil { order.append(key) }
            } else if storage.removeValue(forKey: key) != nil {
                if let index = order.firstIndex(of: key) { order.remove(at: index) }
            }
        }
    }

    /// Dictionary-style default subscript; a set inserts a new key at the end (Kotlin `getOrPut`).
    subscript(key: K, default defaultValue: @autoclosure () -> V) -> V {
        get { return storage[key] ?? defaultValue() }
        set { self[key] = newValue }
    }

    var count: Int { return order.count }
    var isEmpty: Bool { return order.isEmpty }
    var keys: [K] { return order }
    var values: [V] { return order.map { storage[$0]! } }
    var entries: [(key: K, value: V)] { return order.map { (key: $0, value: storage[$0]!) } }

    func containsKey(_ k: K) -> Bool { return storage[k] != nil }

    /// Kotlin `getOrDefault`.
    func getOrDefault(_ k: K, _ defaultValue: V) -> V { return storage[k] ?? defaultValue }

    /// Kotlin `getOrPut`: inserts `make()` at the end when the key is missing.
    @discardableResult
    mutating func getOrPut(_ k: K, _ make: () -> V) -> V {
        if let existing = storage[k] { return existing }
        let created = make()
        self[k] = created
        return created
    }

    /// Kotlin `put`: returns the previous value; an existing key keeps its position.
    @discardableResult
    mutating func put(_ k: K, _ value: V) -> V? {
        let previous = storage[k]
        self[k] = value
        return previous
    }

    @discardableResult
    mutating func remove(_ k: K) -> V? {
        let previous = storage[k]
        self[k] = nil
        return previous
    }

    mutating func clear() {
        order.removeAll()
        storage.removeAll()
    }

    func makeIterator() -> IndexingIterator<[(key: K, value: V)]> {
        return entries.makeIterator()
    }
}

extension KLinkedMap: ExpressibleByDictionaryLiteral {
    /// `linkedMapOf("a" to 1, "b" to 2)` written as `["a": 1, "b": 2]` keeps the literal order.
    init(dictionaryLiteral elements: (K, V)...) {
        self.init()
        for (k, v) in elements { self[k] = v }
    }
}

extension KLinkedMap: Equatable where V: Equatable {
    /// java.util.AbstractMap.equals: same keys and equal values, order ignored.
    static func == (lhs: KLinkedMap<K, V>, rhs: KLinkedMap<K, V>) -> Bool {
        return lhs.storage == rhs.storage
    }
}

/// Kotlin `LinkedHashSet` / `mutableSetOf` / `setOf` / `toSet()`: insertion-ordered, first occurrence wins.
struct KLinkedSet<T: Hashable>: Sequence {
    private(set) var elements: [T] = []
    private var members: Set<T> = []

    init() {}

    init<S: Sequence>(_ s: S) where S.Element == T {
        for e in s { add(e) }
    }

    @discardableResult
    mutating func add(_ t: T) -> Bool {
        if members.insert(t).inserted {
            elements.append(t)
            return true
        }
        return false
    }

    /// Kotlin `addAll`: true when the set changed.
    @discardableResult
    mutating func addAll<S: Sequence>(_ s: S) -> Bool where S.Element == T {
        var changed = false
        for e in s where add(e) { changed = true }
        return changed
    }

    @discardableResult
    mutating func remove(_ t: T) -> Bool {
        if members.remove(t) != nil {
            if let index = elements.firstIndex(of: t) { elements.remove(at: index) }
            return true
        }
        return false
    }

    /// Kotlin `removeAll(predicate)` on a MutableSet: true when something was removed.
    @discardableResult
    mutating func removeAll(where shouldRemove: (T) -> Bool) -> Bool {
        var kept: [T] = []
        var removedAny = false
        for e in elements {
            if shouldRemove(e) {
                members.remove(e)
                removedAny = true
            } else {
                kept.append(e)
            }
        }
        elements = kept
        return removedAny
    }

    func contains(_ t: T) -> Bool { return members.contains(t) }
    var count: Int { return elements.count }
    var isEmpty: Bool { return elements.isEmpty }
    /// Kotlin `first()` / `firstOrNull()`.
    var first: T? { return elements.first }

    mutating func clear() {
        elements.removeAll()
        members.removeAll()
    }

    func makeIterator() -> IndexingIterator<[T]> {
        return elements.makeIterator()
    }
}

extension KLinkedSet: Equatable, Hashable {
    /// java.util.AbstractSet.equals / hashCode: element equality, order ignored.
    static func == (lhs: KLinkedSet<T>, rhs: KLinkedSet<T>) -> Bool {
        return lhs.members == rhs.members
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(members)
    }
}

extension KLinkedSet: ExpressibleByArrayLiteral {
    /// `setOf(a, b, c)` written as `[a, b, c]`.
    init(arrayLiteral elements: T...) {
        self.init(elements)
    }
}

// MARK: - Kotlin ranges (empty when the bounds are reversed; Swift ranges would trap)

/// Kotlin `a..b`.
func krange(_ a: Int, _ b: Int) -> StrideThrough<Int> { return stride(from: a, through: b, by: 1) }
/// Kotlin `a until b`.
func kuntil(_ a: Int, _ b: Int) -> StrideTo<Int> { return stride(from: a, to: b, by: 1) }
/// Kotlin `a downTo b`.
func kdownTo(_ a: Int, _ b: Int) -> StrideThrough<Int> { return stride(from: a, through: b, by: -1) }
/// Kotlin `a..b` on Long.
func krange(_ a: Int64, _ b: Int64) -> StrideThrough<Int64> { return stride(from: a, through: b, by: 1) }
/// Kotlin `a until b` on Long.
func kuntil(_ a: Int64, _ b: Int64) -> StrideTo<Int64> { return stride(from: a, to: b, by: 1) }
/// Kotlin `a downTo b` on Long.
func kdownTo(_ a: Int64, _ b: Int64) -> StrideThrough<Int64> { return stride(from: a, through: b, by: -1) }

// MARK: - kotlin.math on Float (computed in Double like the JVM: nativeMath.f(x.toDouble()).toFloat())

func ksin(_ x: Float) -> Float { return Float(sin(Double(x))) }
func kcos(_ x: Float) -> Float { return Float(cos(Double(x))) }
func ktan(_ x: Float) -> Float { return Float(tan(Double(x))) }
func kasin(_ x: Float) -> Float { return Float(asin(Double(x))) }
func kacos(_ x: Float) -> Float { return Float(acos(Double(x))) }
func katan(_ x: Float) -> Float { return Float(atan(Double(x))) }
func katan2(_ y: Float, _ x: Float) -> Float { return Float(atan2(Double(y), Double(x))) }
func kexp(_ x: Float) -> Float { return Float(exp(Double(x))) }
func kln(_ x: Float) -> Float { return Float(log(Double(x))) }
func klog10(_ x: Float) -> Float { return Float(log10(Double(x))) }
func kpow(_ x: Float, _ y: Float) -> Float { return Float(pow(Double(x), Double(y))) }
/// Kotlin `Float.pow(n: Int)` = `nativeMath.pow(this.toDouble(), n.toDouble()).toFloat()`.
func kpow(_ x: Float, _ n: Int) -> Float { return Float(pow(Double(x), Double(n))) }
func khypot(_ x: Float, _ y: Float) -> Float { return Float(hypot(Double(x), Double(y))) }
func ksqrt(_ x: Float) -> Float { return Float(sqrt(Double(x))) }
func kcbrt(_ x: Float) -> Float { return Float(cbrt(Double(x))) }
/// Kotlin `expm1(Float)`.
func kexpm1(_ x: Float) -> Float { return Float(expm1(Double(x))) }

/// java.lang.Math.min(float, float): NaN wins, -0.0 is smaller than +0.0.
func kmin(_ a: Float, _ b: Float) -> Float {
    if a.isNaN { return a }
    if a == 0 && b == 0 && b.bitPattern == (-Float(0)).bitPattern { return b }
    return a <= b ? a : b
}

/// java.lang.Math.max(float, float): NaN wins, +0.0 is larger than -0.0.
func kmax(_ a: Float, _ b: Float) -> Float {
    if a.isNaN { return a }
    if a == 0 && b == 0 && a.bitPattern == (-Float(0)).bitPattern { return b }
    return a >= b ? a : b
}

/// java.lang.Math.min(double, double).
func kmin(_ a: Double, _ b: Double) -> Double {
    if a.isNaN { return a }
    if a == 0 && b == 0 && b.bitPattern == (-Double(0)).bitPattern { return b }
    return a <= b ? a : b
}

/// java.lang.Math.max(double, double).
func kmax(_ a: Double, _ b: Double) -> Double {
    if a.isNaN { return a }
    if a == 0 && b == 0 && a.bitPattern == (-Double(0)).bitPattern { return b }
    return a >= b ? a : b
}

/// java.lang.Math.floorMod(int, int): the result has the sign of the divisor.
func floorMod(_ a: Int, _ n: Int) -> Int {
    precondition(n != 0, "/ by zero")
    let r = a.remainderReportingOverflow(dividingBy: n).partialValue
    return (a ^ n) < 0 && r != 0 ? r + n : r
}

/// java.lang.Math.floorDiv(int, int): rounds toward negative infinity.
func floorDiv(_ a: Int, _ n: Int) -> Int {
    precondition(n != 0, "/ by zero")
    let q = a.dividedReportingOverflow(by: n).partialValue
    return (a ^ n) < 0 && q &* n != a ? q - 1 : q
}

/// java.lang.Math.floorMod(long, long).
func floorMod(_ a: Int64, _ n: Int64) -> Int64 {
    precondition(n != 0, "/ by zero")
    let r = a.remainderReportingOverflow(dividingBy: n).partialValue
    return (a ^ n) < 0 && r != 0 ? r + n : r
}

/// java.lang.Math.floorDiv(long, long).
func floorDiv(_ a: Int64, _ n: Int64) -> Int64 {
    precondition(n != 0, "/ by zero")
    let q = a.dividedReportingOverflow(by: n).partialValue
    return (a ^ n) < 0 && q &* n != a ? q - 1 : q
}

/// java.lang.Math.round(float) (int result): floor(a + 1/2) computed exactly; NaN gives 0, out-of-range
/// values saturate. Kotlin `Float.roundToInt()` is this function (DESIGN 2.2: NaN maps to 0 instead of
/// Kotlin's IllegalArgumentException).
func javaMathRound(_ a: Float) -> Int {
    return Int(KMath.round(a))
}

/// java.lang.Math.round(double) (long result).
func javaMathRound(_ a: Double) -> Int64 {
    return KMath.round(a)
}

/// java.lang.Math.toDegrees(double) = angrad * 57.29577951308232.
func mathToDegrees(_ angrad: Double) -> Double { return angrad * 57.29577951308232 }
/// java.lang.Math.toRadians(double) = angdeg * 0.017453292519943295.
func mathToRadians(_ angdeg: Double) -> Double { return angdeg * 0.017453292519943295 }

/// JVM primitive conversions and comparisons (f2i, d2l, Math.round, Float.compare, ...).
enum KMath {
    /// JVM `(int) f`: truncation toward zero, NaN -> 0, saturation.
    static func f2i(_ f: Float) -> Int32 {
        if f.isNaN { return 0 }
        if f >= 2147483648.0 { return Int32.max }
        if f <= -2147483648.0 { return Int32.min }
        return Int32(f)
    }

    /// JVM `(long) f`.
    static func f2l(_ f: Float) -> Int64 {
        if f.isNaN { return 0 }
        if f >= 9223372036854775808.0 { return Int64.max }
        if f <= -9223372036854775808.0 { return Int64.min }
        return Int64(f)
    }

    /// JVM `(int) d`.
    static func d2i(_ d: Double) -> Int32 {
        if d.isNaN { return 0 }
        if d >= 2147483647.0 { return Int32.max }
        if d <= -2147483648.0 { return Int32.min }
        return Int32(d)
    }

    /// JVM `(long) d`.
    static func d2l(_ d: Double) -> Int64 {
        if d.isNaN { return 0 }
        if d >= 9223372036854775808.0 { return Int64.max }
        if d <= -9223372036854775808.0 { return Int64.min }
        return Int64(d)
    }

    /// java.lang.Math.round(float), statement by statement (FloatConsts: SIGNIFICAND_WIDTH 24, EXP_BIAS 127).
    static func round(_ a: Float) -> Int32 {
        let intBits = Int32(bitPattern: a.bitPattern)
        let biasedExp = (intBits & 0x7F80_0000) &>> 23
        let shift = (24 - 2 + 127) - biasedExp
        if (shift & -32) == 0 {
            var r = (intBits & 0x007F_FFFF) | (0x007F_FFFF + 1)
            if intBits < 0 { r = 0 &- r }
            return ((r &>> shift) &+ 1) &>> 1
        } else {
            return f2i(a)
        }
    }

    /// java.lang.Math.round(double), statement by statement (DoubleConsts: SIGNIFICAND_WIDTH 53, EXP_BIAS 1023).
    static func round(_ a: Double) -> Int64 {
        let longBits = Int64(bitPattern: a.bitPattern)
        let biasedExp = (longBits & 0x7FF0_0000_0000_0000) &>> 52
        let shift = (53 - 2 + 1023) - biasedExp
        if (shift & -64) == 0 {
            var r = (longBits & 0x000F_FFFF_FFFF_FFFF) | (0x000F_FFFF_FFFF_FFFF + 1)
            if longBits < 0 { r = 0 &- r }
            return ((r &>> shift) &+ 1) &>> 1
        } else {
            return d2l(a)
        }
    }

    /// java.lang.Float.compare: -0.0 < 0.0, NaN is the largest value and equal to itself.
    static func compare(_ f1: Float, _ f2: Float) -> Int {
        if f1 < f2 { return -1 }
        if f1 > f2 { return 1 }
        let thisBits = f1.toBits()
        let anotherBits = f2.toBits()
        return thisBits == anotherBits ? 0 : (thisBits < anotherBits ? -1 : 1)
    }

    /// java.lang.Double.compare.
    static func compare(_ d1: Double, _ d2: Double) -> Int {
        if d1 < d2 { return -1 }
        if d1 > d2 { return 1 }
        let thisBits = d1.toBits()
        let anotherBits = d2.toBits()
        return thisBits == anotherBits ? 0 : (thisBits < anotherBits ? -1 : 1)
    }

    /// Kotlin `compareValues(a, b)` for the key types the app sorts by: String compares UTF-16 units
    /// (String.compareTo), Float/Double use the total order of Float.compare/Double.compare, everything
    /// else uses Comparable.
    static func compareValues<C: Comparable>(_ a: C, _ b: C) -> Int {
        if let x = a as? String, let y = b as? String { return x.kcompareTo(y) }
        if let x = a as? Float, let y = b as? Float { return compare(x, y) }
        if let x = a as? Double, let y = b as? Double { return compare(x, y) }
        if a < b { return -1 }
        if b < a { return 1 }
        return 0
    }
}

// MARK: - Numeric conversions with Kotlin/JVM semantics

extension Float {
    /// Kotlin `Float.toInt()`: truncation, NaN -> 0, saturation to the Int range.
    func toInt() -> Int { return Int(KMath.f2i(self)) }
    /// Kotlin `Float.toLong()`.
    func toLong() -> Int64 { return KMath.f2l(self) }
    func toFloat() -> Float { return self }
    func toDouble() -> Double { return Double(self) }
    /// Kotlin `roundToInt()` = Math.round(float); NaN -> 0 (DESIGN 2.2).
    func roundToInt() -> Int { return Int(KMath.round(self)) }
    /// Kotlin `roundToLong()` = `toDouble().roundToLong()` = Math.round(double); NaN -> 0.
    func roundToLong() -> Int64 { return KMath.round(Double(self)) }
    /// Kotlin `sign` = Math.signum: NaN and +-0.0 return themselves.
    var ksign: Float {
        if self == 0 || isNaN { return self }
        return self < 0 ? -1 : 1
    }
    /// Kotlin `coerceIn`, except that min > max returns min (DESIGN 12.4) instead of throwing.
    func coerceIn(_ minimumValue: Float, _ maximumValue: Float) -> Float {
        if minimumValue > maximumValue { return minimumValue }
        if self < minimumValue { return minimumValue }
        if self > maximumValue { return maximumValue }
        return self
    }
    func coerceAtLeast(_ minimumValue: Float) -> Float { return self < minimumValue ? minimumValue : self }
    func coerceAtMost(_ maximumValue: Float) -> Float { return self > maximumValue ? maximumValue : self }
    /// Kotlin `toBits()` = Float.floatToIntBits (every NaN becomes 0x7FC00000).
    func toBits() -> Int32 { return isNaN ? 0x7FC0_0000 : Int32(bitPattern: bitPattern) }
    /// Kotlin `toRawBits()` = Float.floatToRawIntBits.
    func toRawBits() -> Int32 { return Int32(bitPattern: bitPattern) }
    /// Kotlin `Float.fromBits(bits)` = Float.intBitsToFloat.
    static func fromBits(_ b: Int32) -> Float { return Float(bitPattern: UInt32(bitPattern: b)) }
}

extension Double {
    /// Kotlin `Double.toInt()`: truncation, NaN -> 0, saturation to the Int range.
    func toInt() -> Int { return Int(KMath.d2i(self)) }
    /// Kotlin `Double.toLong()`.
    func toLong() -> Int64 { return KMath.d2l(self) }
    func toFloat() -> Float { return Float(self) }
    func toDouble() -> Double { return self }
    /// Kotlin `Double.roundToInt()`: NaN -> 0 (DESIGN 2.2), saturates, else Math.round(this).toInt().
    func roundToInt() -> Int {
        if isNaN { return 0 }
        if self > 2147483647.0 { return Int(Int32.max) }
        if self < -2147483648.0 { return Int(Int32.min) }
        return Int(Int32(truncatingIfNeeded: KMath.round(self)))
    }
    /// Kotlin `Double.roundToLong()` = Math.round(double); NaN -> 0.
    func roundToLong() -> Int64 { return KMath.round(self) }
    /// Kotlin `sign` = Math.signum.
    var ksign: Double {
        if self == 0 || isNaN { return self }
        return self < 0 ? -1 : 1
    }
    func coerceIn(_ minimumValue: Double, _ maximumValue: Double) -> Double {
        if minimumValue > maximumValue { return minimumValue }
        if self < minimumValue { return minimumValue }
        if self > maximumValue { return maximumValue }
        return self
    }
    func coerceAtLeast(_ minimumValue: Double) -> Double { return self < minimumValue ? minimumValue : self }
    func coerceAtMost(_ maximumValue: Double) -> Double { return self > maximumValue ? maximumValue : self }
    /// Kotlin `toBits()` = Double.doubleToLongBits (every NaN becomes 0x7FF8000000000000).
    func toBits() -> Int64 { return isNaN ? 0x7FF8_0000_0000_0000 : Int64(bitPattern: bitPattern) }
    /// Kotlin `toRawBits()`.
    func toRawBits() -> Int64 { return Int64(bitPattern: bitPattern) }
    static func fromBits(_ b: Int64) -> Double { return Double(bitPattern: UInt64(bitPattern: b)) }
}

extension Int {
    func toInt() -> Int { return self }
    func toLong() -> Int64 { return Int64(self) }
    func toFloat() -> Float { return Float(self) }
    func toDouble() -> Double { return Double(self) }
    func coerceIn(_ minimumValue: Int, _ maximumValue: Int) -> Int {
        if minimumValue > maximumValue { return minimumValue }
        if self < minimumValue { return minimumValue }
        if self > maximumValue { return maximumValue }
        return self
    }
    func coerceAtLeast(_ minimumValue: Int) -> Int { return self < minimumValue ? minimumValue : self }
    func coerceAtMost(_ maximumValue: Int) -> Int { return self > maximumValue ? maximumValue : self }
}

extension Int64 {
    /// Kotlin `Long.toInt()`: keeps the low 32 bits (wraps).
    func toInt() -> Int { return Int(Int32(truncatingIfNeeded: self)) }
    func toLong() -> Int64 { return self }
    func toFloat() -> Float { return Float(self) }
    func toDouble() -> Double { return Double(self) }
    func coerceIn(_ minimumValue: Int64, _ maximumValue: Int64) -> Int64 {
        if minimumValue > maximumValue { return minimumValue }
        if self < minimumValue { return minimumValue }
        if self > maximumValue { return maximumValue }
        return self
    }
    func coerceAtLeast(_ minimumValue: Int64) -> Int64 { return self < minimumValue ? minimumValue : self }
    func coerceAtMost(_ maximumValue: Int64) -> Int64 { return self > maximumValue ? maximumValue : self }
}

extension Int32 {
    func toInt() -> Int { return Int(self) }
    func toLong() -> Int64 { return Int64(self) }
    func toFloat() -> Float { return Float(self) }
    func toDouble() -> Double { return Double(self) }
    func coerceIn(_ minimumValue: Int32, _ maximumValue: Int32) -> Int32 {
        if minimumValue > maximumValue { return minimumValue }
        if self < minimumValue { return minimumValue }
        if self > maximumValue { return maximumValue }
        return self
    }
    func coerceAtLeast(_ minimumValue: Int32) -> Int32 { return self < minimumValue ? minimumValue : self }
    func coerceAtMost(_ maximumValue: Int32) -> Int32 { return self > maximumValue ? maximumValue : self }
}

/// Kotlin `Double.toInt()` / `toLong()` under the old Sports name.
enum KotlinNumber {
    static func int(_ value: Double) -> Int { return value.toInt() }
    static func long(_ value: Double) -> Int64 { return value.toLong() }
}

// MARK: - kotlin.collections

extension Array {
    /// Kotlin `shuffled(random)` = `toMutableList().apply { shuffle(random) }`.
    func kShuffled(_ random: KotlinRandom) -> [Element] {
        var result = self
        result.kShuffle(random)
        return result
    }

    /// Kotlin `MutableList.shuffle(random)`: `for (i in lastIndex downTo 1) { j = random.nextInt(i + 1); swap }`.
    mutating func kShuffle(_ random: KotlinRandom) {
        var i = count - 1
        while i >= 1 {
            let j = random.nextInt(i + 1)
            swapAt(i, j)
            i -= 1
        }
    }

    /// The old Sports name of `kShuffled`.
    func kotlinShuffled(_ random: KotlinRandom) -> [Element] {
        return kShuffled(random)
    }

    /// Kotlin `Sequence.shuffled(random)`: lazy, one `nextInt(buffer.size)` per pulled element.
    func kShuffledSequence(_ random: KotlinRandom) -> KShuffledSequence<Element> {
        return KShuffledSequence(self, random)
    }

    /// Kotlin `Collection.random(random)` = `elementAt(random.nextInt(size))`; an empty list crashes before
    /// any draw, like NoSuchElementException("Collection is empty.").
    func kRandom(_ random: KotlinRandom) -> Element {
        precondition(!isEmpty, "Collection is empty.")
        return self[random.nextInt(count)]
    }

    /// Kotlin `randomOrNull(random)`.
    func kRandomOrNull(_ random: KotlinRandom) -> Element? {
        if isEmpty { return nil }
        return self[random.nextInt(count)]
    }

    /// Kotlin `getOrNull(index)`.
    func getOrNull(_ i: Int) -> Element? {
        return i >= 0 && i < count ? self[i] : nil
    }

    /// Kotlin `sortedWith`: a stable sort (equal elements keep their order).
    func stableSorted(by areInIncreasingOrder: (Element, Element) -> Bool) -> [Element] {
        let indexed = Array<(offset: Int, element: Element)>(enumerated())
        let ordered = indexed.sorted { a, b in
            if areInIncreasingOrder(a.element, b.element) { return true }
            if areInIncreasingOrder(b.element, a.element) { return false }
            return a.offset < b.offset
        }
        return ordered.map { $0.element }
    }

    /// Kotlin `sortedBy { key }` (stable; String/Float/Double keys use the JVM orders).
    func kSortedBy<C: Comparable>(_ key: (Element) -> C) -> [Element] {
        let keys = map(key)
        let order = Array<Int>(indices).sorted { i, j in
            let c = KMath.compareValues(keys[i], keys[j])
            return c != 0 ? c < 0 : i < j
        }
        return order.map { self[$0] }
    }

    /// Kotlin `sortedByDescending { key }`: reversed comparator, still stable (equal keys keep their order).
    func kSortedByDescending<C: Comparable>(_ key: (Element) -> C) -> [Element] {
        let keys = map(key)
        let order = Array<Int>(indices).sorted { i, j in
            let c = KMath.compareValues(keys[j], keys[i])
            return c != 0 ? c < 0 : i < j
        }
        return order.map { self[$0] }
    }

    /// Kotlin `maxByOrNull { key }`: the first maximum; the selector is not called for a single element.
    func kMaxBy<C: Comparable>(_ key: (Element) -> C) -> Element? {
        guard var maxElem = first else { return nil }
        if count == 1 { return maxElem }
        var maxValue = key(maxElem)
        for e in self[1...] {
            let v = key(e)
            if KMath.compareValues(maxValue, v) < 0 {
                maxElem = e
                maxValue = v
            }
        }
        return maxElem
    }

    /// Kotlin `minByOrNull { key }`: the first minimum.
    func kMinBy<C: Comparable>(_ key: (Element) -> C) -> Element? {
        guard var minElem = first else { return nil }
        if count == 1 { return minElem }
        var minValue = key(minElem)
        for e in self[1...] {
            let v = key(e)
            if KMath.compareValues(minValue, v) > 0 {
                minElem = e
                minValue = v
            }
        }
        return minElem
    }

    /// Kotlin `maxOf { Float }` = fold with Math.max (NaN propagates). Crashes when empty like Kotlin.
    func kMaxOf(_ selector: (Element) -> Float) -> Float {
        precondition(!isEmpty, "Collection is empty.")
        var maxValue = selector(self[0])
        for e in self[1...] { maxValue = kmax(maxValue, selector(e)) }
        return maxValue
    }

    /// Kotlin `minOf { Float }` = fold with Math.min.
    func kMinOf(_ selector: (Element) -> Float) -> Float {
        precondition(!isEmpty, "Collection is empty.")
        var minValue = selector(self[0])
        for e in self[1...] { minValue = kmin(minValue, selector(e)) }
        return minValue
    }

    /// Kotlin `maxOf { Double }`.
    func kMaxOf(_ selector: (Element) -> Double) -> Double {
        precondition(!isEmpty, "Collection is empty.")
        var maxValue = selector(self[0])
        for e in self[1...] { maxValue = kmax(maxValue, selector(e)) }
        return maxValue
    }

    /// Kotlin `minOf { Double }`.
    func kMinOf(_ selector: (Element) -> Double) -> Double {
        precondition(!isEmpty, "Collection is empty.")
        var minValue = selector(self[0])
        for e in self[1...] { minValue = kmin(minValue, selector(e)) }
        return minValue
    }

    /// Kotlin `maxOf { Comparable }`: the first maximum value.
    func kMaxOf<C: Comparable>(_ selector: (Element) -> C) -> C {
        precondition(!isEmpty, "Collection is empty.")
        var maxValue = selector(self[0])
        for e in self[1...] {
            let v = selector(e)
            if KMath.compareValues(maxValue, v) < 0 { maxValue = v }
        }
        return maxValue
    }

    /// Kotlin `minOf { Comparable }`.
    func kMinOf<C: Comparable>(_ selector: (Element) -> C) -> C {
        precondition(!isEmpty, "Collection is empty.")
        var minValue = selector(self[0])
        for e in self[1...] {
            let v = selector(e)
            if KMath.compareValues(minValue, v) > 0 { minValue = v }
        }
        return minValue
    }

    /// Kotlin `distinctBy { key }`: first occurrences, in order.
    func kDistinctBy<K: Hashable>(_ key: (Element) -> K) -> [Element] {
        var seen = Set<K>()
        var result: [Element] = []
        for e in self where seen.insert(key(e)).inserted { result.append(e) }
        return result
    }

    /// Kotlin `groupBy { key }`: a LinkedHashMap in first-occurrence order of the keys.
    func kGroupBy<K: Hashable>(_ key: (Element) -> K) -> KLinkedMap<K, [Element]> {
        var result = KLinkedMap<K, [Element]>()
        for e in self { result[key(e), default: []].append(e) }
        return result
    }

    /// Kotlin `associateBy { key }`: the last element for a key wins, the key keeps its first position.
    func kAssociateBy<K: Hashable>(_ key: (Element) -> K) -> KLinkedMap<K, Element> {
        var result = KLinkedMap<K, Element>()
        for e in self { result[key(e)] = e }
        return result
    }

    /// Kotlin `chunked(size)` = `windowed(size, size, partialWindows = true)`.
    func kChunked(_ size: Int) -> [[Element]] {
        return kWindowed(size, size, true)
    }

    /// Kotlin `windowed(size, step, partialWindows)` for random-access lists.
    func kWindowed(_ size: Int, _ step: Int, _ partial: Bool) -> [[Element]] {
        precondition(size > 0 && step > 0, size != step
            ? "Both size \(size) and step \(step) must be greater than zero."
            : "size \(size) must be greater than zero.")
        var result: [[Element]] = []
        var index = 0
        while 0 <= index && index < count {
            let windowSize = Swift.min(size, count - index)
            if windowSize < size && !partial { break }
            result.append(Array(self[index..<(index + windowSize)]))
            index += step
        }
        return result
    }
}

extension Array where Element: Hashable {
    /// Kotlin `distinct()`: first occurrences, in order.
    func kDistinct() -> [Element] {
        var seen = Set<Element>()
        var result: [Element] = []
        for e in self where seen.insert(e).inserted { result.append(e) }
        return result
    }
}

/// Kotlin `Sequence<T>.shuffled(random)` (Sequences.kt): each pulled element costs one
/// `random.nextInt(buffer.size)`; pulling stops as soon as the consumer stops. Iterating a copy starts a new
/// shuffle of the original elements with the shared generator, like re-iterating the Kotlin sequence.
struct KShuffledSequence<Element>: Sequence, IteratorProtocol {
    private var buffer: [Element]
    private let random: KotlinRandom

    init(_ elements: [Element], _ random: KotlinRandom) {
        self.buffer = elements
        self.random = random
    }

    mutating func next() -> Element? {
        if buffer.isEmpty { return nil }
        let j = random.nextInt(buffer.count)
        let last = buffer.removeLast()
        if j < buffer.count {
            let value = buffer[j]
            buffer[j] = last
            return value
        }
        return last
    }
}

// MARK: - kotlin.text (UTF-16 semantics)

/// Kotlin `Char.isWhitespace()` on the JVM = Character.isWhitespace(c) || Character.isSpaceChar(c):
/// every Zs/Zl/Zp character plus U+0009-U+000D and U+001C-U+001F.
func kIsWhitespace(_ unit: UInt16) -> Bool {
    switch unit {
    case 0x0009...0x000D, 0x001C...0x0020, 0x00A0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000:
        return true
    default:
        return false
    }
}

extension Character {
    /// Kotlin `Char.isWhitespace()` for a character that is one UTF-16 unit.
    var kIsWhitespace: Bool {
        let units = Array(String(self).utf16)
        return units.count == 1 && AndroidKitText.isWhitespace(units[0])
    }
}

/// Shared text helpers (namespaced so they never clash with local names).
enum AndroidKitText {
    static func isWhitespace(_ unit: UInt16) -> Bool { return kIsWhitespace(unit) }

    static func string(_ units: ArraySlice<UInt16>) -> String {
        return String(decoding: units, as: UTF16.self)
    }

    /// Java `Character.toUpperCase(char)`: the simple (UnicodeData) uppercase mapping. Swift exposes the full
    /// mappings; where the full uppercase mapping has several units, the simple mapping is the single-unit
    /// titlecase mapping when there is one (U+1F80 → U+1F88) and otherwise the character itself (ß, ŉ, ﬀ, ...).
    static func upper(_ c: UInt16) -> UInt16 {
        guard let scalar = Unicode.Scalar(c) else { return c }
        let mapped = Array(scalar.properties.uppercaseMapping.utf16)
        if mapped.count == 1 { return mapped[0] }
        let title = Array(scalar.properties.titlecaseMapping.utf16)
        return title.count == 1 ? title[0] : c
    }

    /// Java `Character.toLowerCase(char)`: the simple (UnicodeData) lowercase mapping. The only full lowercase
    /// mapping with several units is U+0130 (İ → i + U+0307), whose simple mapping is 'i'.
    static func lower(_ c: UInt16) -> UInt16 {
        if c == 0x0130 { return 0x0069 }
        guard let scalar = Unicode.Scalar(c) else { return c }
        let mapped = Array(scalar.properties.lowercaseMapping.utf16)
        return mapped.count == 1 ? mapped[0] : c
    }
}

extension String {
    /// Kotlin `length`: UTF-16 units.
    var length: Int { return utf16.count }

    /// Kotlin `substring(start, end)` on UTF-16 indices; bad indices crash like StringIndexOutOfBoundsException.
    func ksubstring(_ start: Int, _ end: Int) -> String {
        let units = Array(utf16)
        precondition(start >= 0 && end <= units.count && start <= end,
                     "begin \(start), end \(end), length \(units.count)")
        if start == 0 && end == units.count { return self }
        return String(decoding: units[start..<end], as: UTF16.self)
    }

    /// Kotlin `substring(start)`.
    func ksubstring(_ start: Int) -> String {
        return ksubstring(start, utf16.count)
    }

    /// Kotlin `take(n)`: the first n UTF-16 units (a split surrogate pair becomes U+FFFD in Swift).
    func ktake(_ n: Int) -> String {
        precondition(n >= 0, "Requested character count \(n) is less than zero.")
        return ksubstring(0, Swift.min(n, utf16.count))
    }

    /// Kotlin `takeLast(n)`.
    func ktakeLast(_ n: Int) -> String {
        precondition(n >= 0, "Requested character count \(n) is less than zero.")
        let length = utf16.count
        return ksubstring(length - Swift.min(n, length))
    }

    /// Kotlin `drop(n)`.
    func kdrop(_ n: Int) -> String {
        precondition(n >= 0, "Requested character count \(n) is less than zero.")
        return ksubstring(Swift.min(n, utf16.count))
    }

    /// Kotlin `trim()`: strips Kotlin whitespace (Char.isWhitespace) from both ends, unit by unit.
    func ktrim() -> String {
        let units = Array(utf16)
        var startIndex = 0
        var endIndex = units.count - 1
        var startFound = false
        while startIndex <= endIndex {
            let index = !startFound ? startIndex : endIndex
            let match = kIsWhitespace(units[index])
            if !startFound {
                if !match { startFound = true } else { startIndex += 1 }
            } else {
                if !match { break } else { endIndex -= 1 }
            }
        }
        if startIndex == 0 && endIndex == units.count - 1 { return self }
        return String(decoding: units[startIndex..<(endIndex + 1)], as: UTF16.self)
    }

    /// Kotlin `trimStart()`.
    func ktrimStart() -> String {
        let units = Array(utf16)
        var i = 0
        while i < units.count && kIsWhitespace(units[i]) { i += 1 }
        return i == 0 ? self : String(decoding: units[i...], as: UTF16.self)
    }

    /// Kotlin `trimEnd()`.
    func ktrimEnd() -> String {
        let units = Array(utf16)
        var e = units.count
        while e > 0 && kIsWhitespace(units[e - 1]) { e -= 1 }
        return e == units.count ? self : String(decoding: units[..<e], as: UTF16.self)
    }

    /// Java `String.trim()` (used by the family Java code): strips every unit <= U+0020 from both ends.
    func javaTrim() -> String {
        let units = Array(utf16)
        var st = 0
        var len = units.count
        while st < len && units[st] <= 0x20 { st += 1 }
        while st < len && units[len - 1] <= 0x20 { len -= 1 }
        return st > 0 || len < units.count ? String(decoding: units[st..<len], as: UTF16.self) : self
    }

    /// Kotlin `isBlank()` on the JVM: empty or only Char.isWhitespace units.
    var kotlinIsBlank: Bool {
        for unit in utf16 where !kIsWhitespace(unit) { return false }
        return true
    }

    /// `java.lang.String.hashCode()` over UTF-16 units.
    var javaHashCode: Int32 {
        var h: Int32 = 0
        for unit in utf16 { h = 31 &* h &+ Int32(unit) }
        return h
    }

    /// `java.lang.String.compareTo(other) < 0` (UTF-16 unit order).
    func javaPrecedes(_ other: String) -> Bool {
        return utf16.lexicographicallyPrecedes(other.utf16)
    }

    /// `java.lang.String.compareTo(other)`: the first differing unit difference, else the length difference.
    func kcompareTo(_ other: String) -> Int {
        var a = utf16.makeIterator()
        var b = other.utf16.makeIterator()
        while true {
            switch (a.next(), b.next()) {
            case let (x?, y?):
                if x != y { return Int(x) - Int(y) }
            case (nil, nil):
                return 0
            case (nil, _?):
                return utf16.count - other.utf16.count
            case (_?, nil):
                return utf16.count - other.utf16.count
            }
        }
    }

    /// Kotlin `equals(other, ignoreCase = true)` = String.equalsIgnoreCase (unit by unit, simple case mapping).
    func kequalsIgnoreCase(_ other: String) -> Bool {
        let a = Array(utf16)
        let b = Array(other.utf16)
        if a.count != b.count { return false }
        for i in a.indices {
            let c1 = a[i]
            let c2 = b[i]
            if c1 == c2 { continue }
            let u1 = AndroidKitText.upper(c1)
            let u2 = AndroidKitText.upper(c2)
            if u1 == u2 { continue }
            if AndroidKitText.lower(u1) == AndroidKitText.lower(u2) { continue }
            return false
        }
        return true
    }

    /// Kotlin `split(delimiter)` with one non-empty delimiter: keeps empty parts, including trailing ones
    /// (unlike Java's String.split).
    func ksplit(_ delimiter: String) -> [String] {
        precondition(!delimiter.isEmpty, "the delimiter must not be empty")
        let units = Array(utf16)
        let d = Array(delimiter.utf16)
        var result: [String] = []
        var start = 0
        var i = 0
        while i + d.count <= units.count {
            if units[i..<(i + d.count)].elementsEqual(d) {
                result.append(String(decoding: units[start..<i], as: UTF16.self))
                i += d.count
                start = i
            } else {
                i += 1
            }
        }
        result.append(String(decoding: units[start...], as: UTF16.self))
        return result
    }

    /// Kotlin `split(char)`.
    func ksplit(_ delimiter: Character) -> [String] {
        return ksplit(String(delimiter))
    }

    /// Kotlin `padStart(length, padChar)`: pads to `length` UTF-16 units; a longer string is returned unchanged.
    func kpadStart(_ length: Int, _ padChar: Character = " ") -> String {
        precondition(length >= 0, "Desired length \(length) is less than zero.")
        let n = utf16.count
        if length <= n { return self }
        return String(repeating: String(padChar), count: length - n) + self
    }

    /// Kotlin `padEnd(length, padChar)`.
    func kpadEnd(_ length: Int, _ padChar: Character = " ") -> String {
        precondition(length >= 0, "Desired length \(length) is less than zero.")
        let n = utf16.count
        if length <= n { return self }
        return self + String(repeating: String(padChar), count: length - n)
    }

    /// Kotlin `toIntOrNull()`: an optional '+'/'-' and digits by Character.digit (any Unicode decimal digit), in
    /// the Int range; nil otherwise (no whitespace, no empty string). Swift's `Int(String)` accepts ASCII only.
    func ktoIntOrNull() -> Int? {
        return JavaParse.parseInt(self, 10).map { Int($0) }
    }

    /// Kotlin `toLongOrNull()`.
    func ktoLongOrNull() -> Int64? {
        return JavaParse.parseLong(self, 10)
    }
}

// MARK: - java.lang.Float/Double.toString

/// `Float.toString(f)` / `"$f"` on current Android (libcore main and android16: FloatToDecimal, the
/// JDK 19+ shortest-decimal algorithm): "1.0", "0.001", "1.0E-4", "1.0E7", "NaN", "-Infinity".
func javaString(_ x: Float) -> String {
    return AKotlinDecimal.floatToString(x)
}

/// `Double.toString(d)` / `String.valueOf(d)` on Android. Every libcore version, including main, still
/// implements Double.toString with the legacy jdk.internal.math.FloatingDecimal (JDK <= 18 digits, which can
/// be longer than the shortest: 2.0E23 prints "1.9999999999999998E23"). Within 1e-3..1e7 and for ordinary
/// fractions it equals the JDK 19+ result.
func javaString(_ x: Double) -> String {
    return AKotlinFloatingDecimal.toJavaFormatString(x)
}

/// `Float.toString(f)` on Android 15 and earlier libcore (legacy FloatingDecimal).
func javaLegacyString(_ x: Float) -> String {
    return AKotlinFloatingDecimal.toJavaFormatString(x)
}

/// JDK 19+ `Double.toString(d)` (DoubleToDecimal). On Android 16+ this is what `StringBuilder.append(double)`
/// prints, i.e. a Kotlin string template like "x=$d".
func javaShortestString(_ x: Double) -> String {
    return AKotlinDecimal.doubleToString(x)
}

// MARK: - Java hash codes

/// java.lang hashCode() of boxed primitives, String and java.util.List.
enum JavaHash {
    /// Boolean.hashCode: 1231 / 1237.
    static func of(_ b: Bool) -> Int32 { return b ? 1231 : 1237 }
    /// Integer.hashCode.
    static func of(_ i: Int32) -> Int32 { return i }
    /// Integer.hashCode of a Kotlin Int carried in a Swift Int.
    static func of(_ i: Int) -> Int32 { return Int32(truncatingIfNeeded: i) }
    /// Long.hashCode = (int)(value ^ (value >>> 32)).
    static func of(_ l: Int64) -> Int32 {
        return Int32(truncatingIfNeeded: l ^ Int64(bitPattern: UInt64(bitPattern: l) &>> 32))
    }
    /// Float.hashCode = floatToIntBits.
    static func of(_ f: Float) -> Int32 { return f.toBits() }
    /// Double.hashCode = Long.hashCode(doubleToLongBits).
    static func of(_ d: Double) -> Int32 { return of(d.toBits()) }
    /// String.hashCode.
    static func of(_ s: String) -> Int32 { return s.javaHashCode }
    /// java.util.List.hashCode from the element hashes (null elements hash to 0).
    static func ofList(_ hashes: [Int32]) -> Int32 {
        var h: Int32 = 1
        for e in hashes { h = 31 &* h &+ e }
        return h
    }
}

extension Array where Element == Bool {
    /// `List<Boolean>.hashCode()`.
    var javaHashCode: Int32 { return JavaHash.ofList(map { JavaHash.of($0) }) }
}

extension Array where Element == String {
    /// `List<String>.hashCode()`.
    var javaHashCode: Int32 { return JavaHash.ofList(map { $0.javaHashCode }) }
}

// MARK: - Java hash iteration order

/// Android iterates HashMap/HashSet in java.util.HashMap order; Firebase hands snapshots over as HashMaps
/// filled in Firebase child order. These helpers reproduce those orders exactly for String keys.
enum JavaOrder {
    /// Firebase Android child-key order (ChildKey.compareTo, firebase-database 22): integer keys first by value
    /// then by length ("7" before "007", "0" before "-0"), then the other keys in String.compareTo order.
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

    /// Firebase Android `Utilities.tryParseInt`: at most 11 units, an optional leading '-', ASCII digits only
    /// (leading zeros allowed), inside the 32-bit range.
    static func integerKey(_ key: String) -> Int32? {
        let units = Array(key.utf16)
        if units.count > 11 || units.isEmpty { return nil }
        var i = 0
        var negative = false
        if units[0] == 0x2D {
            if units.count == 1 { return nil }
            negative = true
            i = 1
        }
        // long to prevent overflow
        var number: Int64 = 0
        while i < units.count {
            let c = units[i]
            if c < 0x30 || c > 0x39 { return nil }
            number = number * 10 + Int64(c - 0x30)
            i += 1
        }
        if negative {
            return -number < Int64(Int32.min) ? nil : Int32(-number)
        }
        return number > Int64(Int32.max) ? nil : Int32(number)
    }

    /// Iteration order of a `java.util.HashMap<String, *>` filled in Firebase child order.
    static func hashMapOrder(_ keys: [String]) -> [String] {
        return hashOrder(keys.sorted(by: firebaseKeyPrecedes), initialCapacity: nil)
    }

    /// Iteration order of `HashSet<String>()` after adding `elements` in this order (duplicates ignored).
    static func hashSetOrder(_ elements: [String]) -> [String] {
        return hashOrder(elements, initialCapacity: nil)
    }

    /// Iteration order of `HashSet<String>(collection)` where `collection` iterates `elements` (libcore main:
    /// `HashMap.newHashMap(max(size, 12))`). SharedPreferences `putStringSet` makes this copy.
    static func hashSetCopyOrder(_ elements: [String]) -> [String] {
        // The source collection is a set: its size counts each element once.
        var seen = Set<String>()
        let unique = elements.filter { seen.insert($0).inserted }
        let numMappings = Swift.max(unique.count, 12)
        // HashMap.calculateHashMapCapacity: (int) Math.ceil(numMappings / (double) 0.75f)
        let capacity = Int((Double(numMappings) / Double(Float(0.75))).rounded(.up))
        return hashOrder(unique, initialCapacity: capacity)
    }

    /// java.util.HashMap: the bucket index is `(h ^ (h >>> 16)) & (table.length - 1)`, nodes keep insertion
    /// order inside a bucket (resizes split buckets order-preservingly), the table doubles when the size
    /// exceeds the threshold and when a bucket would get its 9th node while the table is smaller than 64.
    /// Treeified buckets (9+ colliding keys in a 64+ table) are not modelled.
    static func hashOrder(_ insertion: [String], initialCapacity: Int?) -> [String] {
        let maximumCapacity = 1 << 30
        var capacity = 0
        var threshold: Int = initialCapacity.map { tableSizeFor($0) } ?? 0
        var size = 0
        var keys: [String] = []
        var hashes: [UInt32] = []
        var present = Set<String>()

        func resize() {
            let oldCap = capacity
            let oldThr = threshold
            var newCap = 0
            var newThr = 0
            if oldCap > 0 {
                if oldCap >= maximumCapacity {
                    threshold = Int(Int32.max)
                    return
                }
                newCap = oldCap << 1
                if newCap < maximumCapacity && oldCap >= 16 { newThr = oldThr << 1 }
            } else if oldThr > 0 {
                newCap = oldThr
            } else {
                newCap = 16
                newThr = 12
            }
            if newThr == 0 {
                let ft = Float(newCap) * Float(0.75)
                newThr = newCap < maximumCapacity && ft < Float(maximumCapacity) ? Int(ft) : Int(Int32.max)
            }
            threshold = newThr
            capacity = newCap
        }

        for key in insertion {
            if capacity == 0 { resize() }
            if present.contains(key) { continue }
            let h = UInt32(bitPattern: key.javaHashCode)
            let spread = h ^ (h >> 16)
            let bucket = spread & UInt32(capacity - 1)
            var binCount = 0
            for other in hashes where other & UInt32(capacity - 1) == bucket { binCount += 1 }
            present.insert(key)
            keys.append(key)
            hashes.append(spread)
            if binCount >= 8 && capacity < 64 { resize() }
            size += 1
            if size > threshold { resize() }
        }
        let mask = UInt32(Swift.max(capacity, 1) - 1)
        let order = Array(keys.indices).sorted { a, b in
            let ba = hashes[a] & mask, bb = hashes[b] & mask
            return ba != bb ? ba < bb : a < b
        }
        return order.map { keys[$0] }
    }

    /// java.util.HashMap.tableSizeFor.
    static func tableSizeFor(_ cap: Int) -> Int {
        let c = Int32(truncatingIfNeeded: cap)
        let n = Int32(bitPattern: UInt32.max &>> UInt32((c &- 1).leadingZeroBitCount))
        if n < 0 { return 1 }
        return n >= (1 << 30) ? (1 << 30) : Int(n) + 1
    }
}
