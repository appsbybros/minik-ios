import Foundation
import XCTest
@testable import MinikTripleShot

// AndroidKit parity tests for the Kotlin/Java layer: AKotlin.swift (kotlin.random, kotlin.math, numbers,
// collections, text, hash codes and Java hash order), AKotlinDecimal.swift / AKotlinFloatingDecimal.swift
// (Float/Double.toString), AFormat.swift (java.util.Formatter), AJava.swift (org.json, org.w3c.dom),
// APrefs.swift (SharedPreferences) and ALocale.swift (java.util.Locale).
//
// The vectors in AndroidKitKotlinVectors (end of this file) were generated on the JVM by the harness
// KitVectors.kt: kotlin-stdlib 2.3.21 (the app's Kotlin), Android libcore main java.util.Formatter and
// FormattedFloatingDecimal patched into java.base, AOSP org.json, firebase-database 22.0.1 ChildKey, and the legacy
// jdk.internal.math.FloatingDecimal (ART's Double.toString). The DOM dumps come from Android's KXmlParser driven
// like libcore DocumentBuilderImpl. Floats and doubles are compared by bit pattern.

final class AndroidKitKotlinTests: XCTestCase {
    private typealias V = AndroidKitKotlinVectors

    // MARK: - Helpers

    private static func hex32(_ v: UInt32) -> String {
        let s = String(v, radix: 16, uppercase: true)
        return "0x" + String(repeating: "0", count: 8 - s.count) + s
    }

    private static func hex64(_ v: UInt64) -> String {
        let s = String(v, radix: 16, uppercase: true)
        return "0x" + String(repeating: "0", count: 16 - s.count) + s
    }

    /// One step of a harness script (KitVectors.kt `runOp`): the result as the harness printed it.
    private static func run(_ r: KotlinRandom, _ op: String) -> String {
        let p = op.split(separator: ":").map(String.init)
        switch p[0] {
        case "int": return String(r.nextInt())
        case "bits": return String(r.nextBits(Int(p[1])!))
        case "until": return String(r.nextInt(Int(p[1])!))
        case "range": return String(r.nextInt(Int(p[1])!, Int(p[2])!))
        case "irange": return String(r.nextInt(Int(p[1])!...Int(p[2])!))
        case "long": return String(r.nextLong())
        case "luntil": return String(r.nextLong(Int64(p[1])!))
        case "lrange": return String(r.nextLong(Int64(p[1])!, Int64(p[2])!))
        case "float": return hex32(r.nextFloat().bitPattern)
        case "double": return hex64(r.nextDouble().bitPattern)
        case "duntil": return hex64(r.nextDouble(Double(p[1])!).bitPattern)
        case "drange": return hex64(r.nextDouble(Double(p[1])!, Double(p[2])!).bitPattern)
        case "bool": return r.nextBoolean() ? "true" : "false"
        default:
            XCTFail("unknown random op \(op)")
            return ""
        }
    }

    private static let categories = ["GENERAL_KNOWLEDGE", "PROGRAMMING", "SCIENCE", "ASTRONOMY", "PARADOX", "AI", "HISTORY",
                                     "ENGLISH", "KIDS_ARITHMETIC", "MATH", "MATRICULATION_MATH"]

    // MARK: - kotlin.random (XorWowRandom + Random defaults)

    func testRandomFirstIntsForLongSeeds() {
        for v in V.randomFirst {
            let r = KotlinRandom(seed: v.seed)
            XCTAssertEqual((0..<12).map { _ in r.nextInt() }, v.ints, "Random(\(v.seed)L)")
        }
    }

    func testRandomIntSeeds() {
        for v in V.randomIntSeed {
            let r = KotlinRandom(seed: v.seed)
            XCTAssertEqual((0..<8).map { _ in r.nextInt() }, v.ints, "Random(\(v.seed))")
            XCTAssertEqual((0..<2).map { _ in r.nextFloat().bitPattern }, v.floats, "Random(\(v.seed)).nextFloat()")
        }
        // Random(Int) equals Random(Long) of the sign-extended value.
        for seed in [0, 1, -1, -7, 12345, Int(Int32.min), Int(Int32.max)] {
            let a = KotlinRandom(seed: seed)
            let b = KotlinRandom(seed: Int64(seed))
            XCTAssertEqual((0..<6).map { _ in a.nextInt() }, (0..<6).map { _ in b.nextInt() }, "seed \(seed)")
        }
    }

    func testRandomScripts() {
        for v in V.randomScripts + V.appSeedScripts {
            let r = KotlinRandom(seed: v.seed)
            for (op, expected) in v.steps {
                XCTAssertEqual(Self.run(r, op), expected, "Random(\(v.seed)L) \(op)")
            }
        }
    }

    func testRandomIntSeedScripts() {
        for v in V.randomIntSeedScripts {
            let r = KotlinRandom(seed: v.seed)
            for (op, expected) in v.steps {
                XCTAssertEqual(Self.run(r, op), expected, "Random(\(v.seed)) \(op)")
            }
        }
    }

    /// The KotlinRandom tables of specs 02 (A.10), 15 and 17.
    func testSpecRandomTables() {
        for v in V.specScripts {
            let r = v.seedLong.map { KotlinRandom(seed: $0) } ?? KotlinRandom(seed: v.seedInt!)
            for (op, expected) in v.steps {
                XCTAssertEqual(Self.run(r, op), expected, v.label + " " + op)
            }
        }
        let r = KotlinRandom(seed: Int64(31337))
        XCTAssertEqual((0..<5).map { _ in r.nextInt(100) }, [64, 67, 85, 75, 44])
        XCTAssertEqual(KotlinRandom(seed: Int64(42)).nextLong(), 4174779793377534016)
        XCTAssertEqual(KotlinRandom(seed: Int64(42)).nextLong(0, 1700), 1308)
        XCTAssertEqual(KotlinRandom(seed: Int64(31337)).nextLong(), 1680326617120332127)
        XCTAssertEqual(KotlinRandom(seed: Int64(31337)).nextLong(0, 1700), 1263)
        XCTAssertEqual(KotlinRandom(seed: Int64(-7)).nextLong(), 2119902869140302831)
        XCTAssertEqual(KotlinRandom(seed: Int64(-7)).nextLong(0, 1700), 1615)
        XCTAssertEqual(KotlinRandom(seed: Int64(1760000000000)).nextLong(), -1450066263658712945)
        XCTAssertEqual(KotlinRandom(seed: Int64(1760000000000)).nextLong(0, 1700), 335)
        let twelve = KotlinRandom(seed: Int64(12345))
        XCTAssertEqual([twelve.nextInt(100), twelve.nextInt(100), twelve.nextInt(100)], [36, 41, 28])
    }

    func testRandomDefaultIsUsable() {
        let r = KotlinRandom.Default
        for _ in 0..<100 {
            let v = r.nextInt(10)
            XCTAssertTrue(v >= 0 && v < 10)
            let f = r.nextFloat()
            XCTAssertTrue(f >= 0 && f < 1)
        }
    }

    // MARK: - Shuffles and random elements

    func testShuffled() {
        for v in V.shuffles {
            let r = KotlinRandom(seed: v.seed)
            XCTAssertEqual(Array(0..<v.n).kShuffled(r), v.shuffled, "(0 until \(v.n)).shuffled(Random(\(v.seed)L))")
            XCTAssertEqual(r.nextInt(), v.next, "next value after the shuffle")
            var inPlace = Array(0..<v.n)
            inPlace.kShuffle(KotlinRandom(seed: v.seed))
            XCTAssertEqual(inPlace, v.shuffled)
        }
    }

    func testRandomElement() {
        for v in V.randomPicks {
            let r = KotlinRandom(seed: v.seed)
            let list = [10, 20, 30, 40, 50]
            XCTAssertEqual((0..<6).map { _ in list.kRandom(r) }, v.picks, "seed \(v.seed)")
        }
        XCTAssertNil([Int]().kRandomOrNull(KotlinRandom(seed: 1)))
    }

    func testSequenceShuffled() {
        for v in V.sequenceShuffles {
            let r = KotlinRandom(seed: v.seed)
            XCTAssertEqual(Array(Array(0..<v.n).kShuffledSequence(r).prefix(v.take)), v.taken, "n \(v.n) take \(v.take)")
            XCTAssertEqual(r.nextInt(), v.next, "draws consumed by the lazy shuffle")
        }
    }

    // MARK: - Float/Double.toString

    func testFloatToString() {
        for (bits, shortest, legacy) in V.floatStrings {
            let f = Float(bitPattern: bits)
            XCTAssertEqual(javaString(f), shortest, "Float.toString(\(Self.hex32(bits)))")
            XCTAssertEqual(javaLegacyString(f), legacy, "legacy Float.toString(\(Self.hex32(bits)))")
        }
        for (bits, text) in V.floatTemplates {
            XCTAssertEqual(javaString(Float(bitPattern: bits)), text)
        }
        XCTAssertEqual(javaString(Float(1)), "1.0")
        XCTAssertEqual(javaString(Float(1.0E-4)), "1.0E-4")
        XCTAssertEqual(javaString(Float(1.0E7)), "1.0E7")
        XCTAssertEqual(javaString(Float.nan), "NaN")
        XCTAssertEqual(javaString(-Float.infinity), "-Infinity")
    }

    func testDoubleToString() {
        for (bits, legacy, shortest) in V.doubleStrings {
            let d = Double(bitPattern: bits)
            XCTAssertEqual(javaString(d), legacy, "Double.toString(\(Self.hex64(bits)))")
            XCTAssertEqual(javaShortestString(d), shortest, "JDK 19+ Double.toString(\(Self.hex64(bits)))")
        }
        XCTAssertEqual(javaString(2.0E23), "1.9999999999999998E23")
        XCTAssertEqual(javaShortestString(2.0E23), "2.0E23")
        XCTAssertEqual(javaString(0.1 + 0.2), "0.30000000000000004")
        XCTAssertEqual(javaString(100.0), "100.0")
        XCTAssertEqual(javaString(-0.0), "-0.0")
    }

    // MARK: - java.util.Formatter

    func testFormatterVectors() {
        for v in V.formats + V.formats2 {
            XCTAssertEqual(AFormat.format(ALocale.forLanguageTag(v.locale), v.pattern, v.args), v.expected,
                           "String.format(\(v.locale), \(v.pattern))")
        }
    }

    func testFormatterAppPatterns() {
        XCTAssertEqual(AFormat.format(ALocale.US, "%04d-W%02d", 2026, 7), "2026-W07")
        XCTAssertEqual(AFormat.format(ALocale.US, "W%02d/%02d", 42, 26), "W42/26")
        XCTAssertEqual(AFormat.format(ALocale("he"), "🟡 תשובה חלקית (%1$d%%)", 7), "🟡 תשובה חלקית (7%)")
        XCTAssertEqual(AFormat.format(ALocale.ENGLISH, "%1$s gave a partial answer (%2$d%%).", "Maya", 50),
                       "Maya gave a partial answer (50%).")
        XCTAssertEqual(AFormat.format(ALocale.ROOT, "%d topics selected", 3), "3 topics selected")
        XCTAssertEqual(AFormat.format(ALocale("he"), "%1$s • %2$s", "א", "ב"), "א • ב")
        XCTAssertEqual(AFormat.format(ALocale.ENGLISH, "%s|%s|%s", Float(0.1), 0.5, Int64(7)), "0.1|0.5|7")
        let optionalName: String? = nil
        XCTAssertEqual(AFormat.format(ALocale.ENGLISH, "%s", optionalName), "null")
        XCTAssertEqual(AFormat.format(ALocale.ENGLISH, "%d|%s", 1, true), "1|true")
        XCTAssertEqual(AFormat.javaToString(Float(2.5)), "2.5")
    }

    // MARK: - Hash codes and Java hash iteration order

    func testJavaHashCodes() {
        for (s, h) in V.stringHashes + V.specStringHashes {
            XCTAssertEqual(s.javaHashCode, h, s)
            XCTAssertEqual(JavaHash.of(s), h, s)
        }
        for (l, h) in V.longHashes {
            XCTAssertEqual(JavaHash.of(l), h, "\(l)L")
        }
        for (bits, h) in V.floatHashes {
            XCTAssertEqual(JavaHash.of(Float(bitPattern: bits)), h, Self.hex32(bits))
        }
        for (bits, h) in V.doubleHashes {
            XCTAssertEqual(JavaHash.of(Double(bitPattern: bits)), h, Self.hex64(bits))
        }
        for (list, h) in V.boolListHashes + V.specBoolListHashes {
            XCTAssertEqual(list.javaHashCode, h, "\(list)")
            XCTAssertEqual(JavaHash.ofList(list.map { JavaHash.of($0) }), h, "\(list)")
        }
        for (list, h) in V.stringListHashes {
            XCTAssertEqual(list.javaHashCode, h, "\(list)")
        }
        for (b, h) in V.boolHashes {
            XCTAssertEqual(JavaHash.of(b), h)
        }
        XCTAssertEqual(JavaHash.of(Int32(-5)), -5)
        XCTAssertEqual("0-0-7".javaHashCode, 45717181)
        XCTAssertEqual("7-7-0".javaHashCode, 52188548)
    }

    func testHashSetOrder() {
        for v in V.hashSetOrders {
            XCTAssertEqual(JavaOrder.hashSetOrder(v.input), v.added, "HashSet().addAll(\(v.input))")
            XCTAssertEqual(JavaOrder.hashSetCopyOrder(v.input), v.copy, "HashSet(LinkedHashSet(\(v.input)))")
            XCTAssertEqual(JavaOrder.hashSetOrder(v.copy), v.reload, "reload of \(v.copy)")
        }
        for v in V.categorySubsetOrders {
            XCTAssertEqual(JavaOrder.hashSetCopyOrder(v.input), v.copy, "\(v.input)")
            XCTAssertEqual(JavaOrder.hashSetOrder(v.input), v.copy, "\(v.input)")
        }
        // spec 01: the 11 topics inserted in ordinal order.
        XCTAssertEqual(JavaOrder.hashSetOrder(Self.categories),
                       ["PARADOX", "PROGRAMMING", "MATRICULATION_MATH", "ASTRONOMY", "ENGLISH", "KIDS_ARITHMETIC",
                        "GENERAL_KNOWLEDGE", "AI", "SCIENCE", "MATH", "HISTORY"])
    }

    func testFirebaseKeyOrderAndHashMapOrder() {
        for v in V.firebaseOrders {
            XCTAssertEqual(v.keys.sorted(by: JavaOrder.firebaseKeyPrecedes), v.sorted, "\(v.keys)")
            XCTAssertEqual(JavaOrder.hashMapOrder(v.keys), v.hashMap, "\(v.keys)")
        }
    }

    // MARK: - kotlin.text

    func testTrimAndBlank() {
        for (s, trimmed, blank, javaTrimmed) in V.trims {
            XCTAssertEqual(s.ktrim(), trimmed, "trim of \(Array(s.unicodeScalars).map { $0.value })")
            XCTAssertEqual(s.kotlinIsBlank, blank, "isBlank of \(Array(s.unicodeScalars).map { $0.value })")
            XCTAssertEqual(s.javaTrim(), javaTrimmed, "Java trim of \(Array(s.unicodeScalars).map { $0.value })")
        }
        XCTAssertEqual("  a b ".ktrimStart(), "a b ")
        XCTAssertEqual("  a b ".ktrimEnd(), "  a b")
    }

    func testCompareAndCase() {
        for (a, b, c) in V.compares {
            XCTAssertEqual(a.kcompareTo(b), c, "\(a) vs \(b)")
            XCTAssertEqual(a.javaPrecedes(b), c < 0, "\(a) vs \(b)")
        }
        for (a, b, e) in V.equalsIgnoreCase {
            XCTAssertEqual(a.kequalsIgnoreCase(b), e, "\(a) vs \(b)")
        }
        for (s, parts) in V.splits {
            XCTAssertEqual(s.ksplit(","), parts, s)
        }
        for (s, int, long) in V.toNumbers {
            XCTAssertEqual(s.ktoIntOrNull().map { String($0) } ?? "nil", int, "\(Array(s.unicodeScalars).map { $0.value }).toIntOrNull()")
            XCTAssertEqual(s.ktoLongOrNull().map { String($0) } ?? "nil", long, "\(Array(s.unicodeScalars).map { $0.value }).toLongOrNull()")
        }
    }

    func testUtf16StringHelpers() {
        let s = "a😀bא"
        XCTAssertEqual(s.length, 5)
        XCTAssertEqual(s.ksubstring(1, 3), "😀")
        XCTAssertEqual(s.ksubstring(3), "bא")
        XCTAssertEqual(s.ktake(3), "a😀")
        XCTAssertEqual(s.ktake(99), s)
        XCTAssertEqual(s.ktakeLast(2), "bא")
        XCTAssertEqual(s.kdrop(3), "bא")
        XCTAssertEqual("5".kpadStart(2, "0"), "05")
        XCTAssertEqual("59".kpadStart(2, "0"), "59")
        XCTAssertEqual("123".kpadStart(2, "0"), "123")
        XCTAssertEqual("😀".kpadStart(3), " 😀")
        XCTAssertEqual("a".kpadEnd(3, "."), "a..")
        XCTAssertEqual("".length, 0)
        XCTAssertTrue("".kotlinIsBlank)
        XCTAssertTrue(" \u{3000}\t\n".kotlinIsBlank)
        XCTAssertFalse("\u{200B}".kotlinIsBlank)
        XCTAssertFalse("\u{00A0}x".kotlinIsBlank)
        XCTAssertTrue(Character("\u{2007}").kIsWhitespace)
    }

    // MARK: - Numbers

    func testFloatAndDoubleConversions() {
        for (bits, i, l, ri, rl) in V.floatConversions {
            let f = Float(bitPattern: bits)
            XCTAssertEqual(f.toInt(), i, "\(Self.hex32(bits)).toInt()")
            XCTAssertEqual(f.toLong(), l, "\(Self.hex32(bits)).toLong()")
            XCTAssertEqual(f.roundToInt(), ri, "\(Self.hex32(bits)).roundToInt()")
            XCTAssertEqual(f.roundToLong(), rl, "\(Self.hex32(bits)).roundToLong()")
        }
        for (bits, i, l, ri, rl) in V.doubleConversions {
            let d = Double(bitPattern: bits)
            XCTAssertEqual(d.toInt(), i, "\(Self.hex64(bits)).toInt()")
            XCTAssertEqual(d.toLong(), l, "\(Self.hex64(bits)).toLong()")
            XCTAssertEqual(d.roundToInt(), ri, "\(Self.hex64(bits)).roundToInt()")
            XCTAssertEqual(d.roundToLong(), rl, "\(Self.hex64(bits)).roundToLong()")
        }
        for (bits, r) in V.mathRoundFloat {
            XCTAssertEqual(KMath.round(Float(bitPattern: bits)), r, "Math.round(\(Self.hex32(bits)))")
        }
        for (bits, r) in V.mathRoundDouble {
            XCTAssertEqual(KMath.round(Double(bitPattern: bits)), r, "Math.round(\(Self.hex64(bits)))")
        }
        // DESIGN 2.2: NaN converts to 0 (Kotlin's roundToInt would throw).
        XCTAssertEqual(Float.nan.toInt(), 0)
        XCTAssertEqual(Float.nan.roundToInt(), 0)
        XCTAssertEqual(Double.nan.toLong(), 0)
        XCTAssertEqual(Int64(0x1_0000_0005).toInt(), 5)
        XCTAssertEqual(Int64(0xFFFF_FFFF).toInt(), -1)
        XCTAssertEqual(Int32(-3).toLong(), -3)
    }

    func testMinMaxSignFloorCoerce() {
        for (a, b, mn, mx) in V.floatMinMax {
            XCTAssertEqual(kmin(Float(bitPattern: a), Float(bitPattern: b)).bitPattern, mn, "min(\(Self.hex32(a)), \(Self.hex32(b)))")
            XCTAssertEqual(kmax(Float(bitPattern: a), Float(bitPattern: b)).bitPattern, mx, "max(\(Self.hex32(a)), \(Self.hex32(b)))")
        }
        for (a, b, mn, mx) in V.doubleMinMax {
            XCTAssertEqual(kmin(Double(bitPattern: a), Double(bitPattern: b)).bitPattern, mn)
            XCTAssertEqual(kmax(Double(bitPattern: a), Double(bitPattern: b)).bitPattern, mx)
        }
        for (bits, sign) in V.floatSigns {
            XCTAssertEqual(Float(bitPattern: bits).ksign.bitPattern, sign, Self.hex32(bits))
        }
        for (a, n, mod, div) in V.floorModDiv {
            XCTAssertEqual(floorMod(a, n), mod, "floorMod(\(a), \(n))")
            XCTAssertEqual(floorDiv(a, n), div, "floorDiv(\(a), \(n))")
            if a >= Int64(Int32.min) && a <= Int64(Int32.max) {
                XCTAssertEqual(floorMod(Int(a), Int(n)), Int(mod))
                XCTAssertEqual(floorDiv(Int(a), Int(n)), Int(div))
            }
        }
        for (bits, coerced) in V.floatCoerce {
            XCTAssertEqual(Float(bitPattern: bits).coerceIn(-1, 1).bitPattern, coerced, Self.hex32(bits))
        }
        for (x, deg) in V.toDegrees {
            XCTAssertEqual(mathToDegrees(Double(bitPattern: x)).bitPattern, deg)
        }
        // DESIGN 12.4: coerceIn with min > max returns min instead of throwing.
        XCTAssertEqual(Float(5).coerceIn(2, 1), 2)
        XCTAssertEqual(7.coerceIn(10, 3), 10)
        XCTAssertEqual(Float(5).coerceAtMost(1), 1)
        XCTAssertEqual(Float(-5).coerceAtLeast(0), 0)
        XCTAssertTrue(Float.nan.coerceIn(0, 1).isNaN)
    }

    func testFloatMath() {
        for (xb, expected) in V.floatMath {
            let x = Float(bitPattern: xb)
            let values: [Float] = [ksin(x), kcos(x), ktan(x), kasin(x / 16), kacos(x / 16), katan(x), kexp(x / 8),
                                   kln(Swift.abs(x) + 1), klog10(Swift.abs(x) + 1), ksqrt(Swift.abs(x)), kcbrt(x), kexpm1(x / 8)]
            XCTAssertEqual(values.map { $0.bitPattern }, expected, "x = \(Self.hex32(xb))")
        }
        for (yb, xb, atan2Bits, hypotBits, powBits) in V.floatMath2 {
            let y = Float(bitPattern: yb)
            let x = Float(bitPattern: xb)
            XCTAssertEqual(katan2(y, x).bitPattern, atan2Bits, "atan2(\(Self.hex32(yb)), \(Self.hex32(xb)))")
            XCTAssertEqual(khypot(y, x).bitPattern, hypotBits, "hypot(\(Self.hex32(yb)), \(Self.hex32(xb)))")
            XCTAssertEqual(kpow(Swift.abs(y), x).bitPattern, powBits, "pow(\(Self.hex32(yb)), \(Self.hex32(xb)))")
        }
    }

    func testConstantsAndBits() {
        XCTAssertEqual(PI_F.bitPattern, 0x4049_0FDB)
        XCTAssertNotEqual(PI_F.bitPattern, Float.pi.bitPattern)
        XCTAssertEqual(E_F.bitPattern, 0x402D_F854)
        XCTAssertEqual(Float.fromBits(0x3F80_0000), 1)
        XCTAssertEqual(Float(1.5).toBits(), 0x3FC0_0000)
        XCTAssertEqual(Float.nan.toBits(), 0x7FC0_0000)
        XCTAssertEqual(Float(bitPattern: 0x7FC0_0001).toBits(), 0x7FC0_0000)
        XCTAssertEqual(Float(bitPattern: 0x7FC0_0001).toRawBits(), 0x7FC0_0001)
        XCTAssertEqual(Double.nan.toBits(), 0x7FF8_0000_0000_0000)
        XCTAssertEqual(Double.fromBits(0x3FF0_0000_0000_0000), 1)
    }

    // MARK: - Sorting and collections

    func testSorting() {
        let floats = V.floatSort.input.map { Float(bitPattern: $0) }
        XCTAssertEqual(floats.kSortedBy { $0 }.map { $0.bitPattern }, V.floatSort.sorted)
        XCTAssertEqual(floats.kMaxBy { $0 }!.bitPattern, V.floatSort.maxBy)
        XCTAssertEqual(floats.kMinBy { $0 }!.bitPattern, V.floatSort.minBy)
        XCTAssertEqual(V.stringSort.input.kSortedBy { $0 }, V.stringSort.sorted)
        XCTAssertEqual(V.stringSort.input.kSortedByDescending { $0 }, V.stringSort.descending)
        let w = V.lengthSort
        XCTAssertEqual(w.input.kSortedBy { $0.length }, w.ascending)
        XCTAssertEqual(w.input.kSortedByDescending { $0.length }, w.descending)
        XCTAssertEqual(w.input.kMaxBy { $0.length }, w.maxBy)
        XCTAssertEqual(w.input.kMinBy { $0.length }, w.minBy)
        XCTAssertEqual(w.input.stableSorted { $0.count < $1.count }, w.ascending)
        XCTAssertNil([Int]().kMaxBy { $0 })
        XCTAssertEqual([3, 9, 9, 1].kMaxOf { Float($0) }, 9)
        XCTAssertEqual([3, 9, 9, 1].kMinOf { Double($0) }, 1)
        for v in V.windows {
            XCTAssertEqual(Array(1...7).kWindowed(v.size, v.step, v.partial), v.result, "windowed(\(v.size), \(v.step), \(v.partial))")
        }
        XCTAssertEqual(Array(1...7).kChunked(3), [[1, 2, 3], [4, 5, 6], [7]])
    }

    func testLinkedMapAndSet() {
        var m = KLinkedMap<String, Int>()
        m["b"] = 1
        m["a"] = 2
        m["c"] = 3
        m["b"] = 10 // re-setting keeps the position
        XCTAssertEqual(m.keys, ["b", "a", "c"])
        XCTAssertEqual(m.values, [10, 2, 3])
        m["a"] = nil // removing forgets the position
        m["a"] = 4
        XCTAssertEqual(m.keys, ["b", "c", "a"])
        XCTAssertEqual(m.getOrPut("d") { 5 }, 5)
        XCTAssertEqual(m.getOrPut("b") { 99 }, 10)
        XCTAssertEqual(m.remove("c"), 3)
        XCTAssertNil(m.remove("zz"))
        XCTAssertEqual(m.map { $0.key }, ["b", "a", "d"])
        XCTAssertEqual(m.entries.map { $0.value }, [10, 4, 5])
        XCTAssertTrue(m.containsKey("d"))
        XCTAssertEqual(m.count, 3)
        m.clear()
        XCTAssertTrue(m.isEmpty)
        let pairs = KLinkedMap([("x", 1), ("y", 2), ("x", 3)])
        XCTAssertEqual(pairs.keys, ["x", "y"])
        XCTAssertEqual(pairs["x"], 3)

        var s = KLinkedSet<String>()
        XCTAssertTrue(s.add("q"))
        XCTAssertTrue(s.add("p"))
        XCTAssertFalse(s.add("q"))
        XCTAssertEqual(s.elements, ["q", "p"])
        XCTAssertTrue(s.contains("p"))
        XCTAssertTrue(s.remove("q"))
        XCTAssertFalse(s.remove("q"))
        XCTAssertEqual(s.count, 1)
        XCTAssertEqual(Array(KLinkedSet(["c", "a", "c", "b"])), ["c", "a", "b"])
        s.clear()
        XCTAssertTrue(s.isEmpty)

        let box = KRef([1, 2])
        let alias = box
        alias.value.append(3)
        XCTAssertEqual(box.value, [1, 2, 3])
    }

    func testRangesAndCollectionHelpers() {
        XCTAssertEqual(Array(krange(1, 3)), [1, 2, 3])
        XCTAssertEqual(Array(krange(3, 1)), [Int]())
        XCTAssertEqual(Array(kuntil(1, 3)), [1, 2])
        XCTAssertEqual(Array(kuntil(3, 3)), [Int]())
        XCTAssertEqual(Array(kdownTo(3, 1)), [3, 2, 1])
        XCTAssertEqual(Array(kdownTo(1, 3)), [Int]())
        XCTAssertEqual([1, 2, 3].getOrNull(2), 3)
        XCTAssertNil([1, 2, 3].getOrNull(3))
        XCTAssertNil([1, 2, 3].getOrNull(-1))
        let groups = ["apple", "bob", "avocado", "cat", "banana"].kGroupBy { String($0.prefix(1)) }
        XCTAssertEqual(groups.keys, ["a", "b", "c"])
        XCTAssertEqual(groups["a"], ["apple", "avocado"])
        XCTAssertEqual(groups["b"], ["bob", "banana"])
        let byFirst = ["x1", "y1", "x2"].kAssociateBy { String($0.prefix(1)) }
        XCTAssertEqual(byFirst.keys, ["x", "y"])
        XCTAssertEqual(byFirst["x"], "x2")
        XCTAssertEqual(["b", "a", "b", "c", "a"].kDistinct(), ["b", "a", "c"])
        XCTAssertEqual(["aa", "b", "cc", "d"].kDistinctBy { $0.count }, ["aa", "b"])
    }

    // MARK: - org.json

    func testJSONRoundTrips() throws {
        for (input, expected) in V.jsonRoundTrips {
            let text = try (input.ktrim().hasPrefix("[") ? AJSONArray(input).toString() : AJSONObject(input).toString())
            XCTAssertEqual(text, expected, input)
        }
    }

    func testJSONFailures() {
        for (input, expected) in V.jsonFailures {
            var message = "OK"
            do {
                if input.ktrim().hasPrefix("[") {
                    _ = try AJSONArray(input)
                } else {
                    _ = try AJSONObject(input)
                }
            } catch let e as AJSONException {
                message = e.message
            } catch {
                message = "unexpected \(error)"
            }
            XCTAssertEqual(message, expected, input)
        }
    }

    private static func jsonOp(_ o: AJSONObject, _ op: String, _ k: String) -> String {
        func run(_ f: () throws -> String) -> String {
            do {
                return try f()
            } catch let e as AJSONException {
                return "EXC:" + e.message
            } catch {
                return "EXC?\(error)"
            }
        }
        func d(_ x: Double) -> String { return "D:" + hex64(x.bitPattern) }
        switch op {
        case "getInt": return run { String(try o.getInt(k)) }
        case "getLong": return run { String(try o.getLong(k)) }
        case "getDouble": return run { d(try o.getDouble(k)) }
        case "getString": return run { try o.getString(k) }
        case "getBoolean": return run { String(try o.getBoolean(k)) }
        case "optString": return o.optString(k, "fb")
        case "optInt": return String(o.optInt(k, -9))
        case "optLong": return String(o.optLong(k, -9))
        case "optDouble": return d(o.optDouble(k, -9.5))
        case "optBoolean": return String(o.optBoolean(k, true))
        case "isNull": return String(o.isNull(k))
        case "has": return String(o.has(k))
        case "keys": return o.keys().joined(separator: ",")
        case "length": return String(o.length())
        default:
            XCTFail("unknown JSON op \(op)")
            return ""
        }
    }

    func testJSONGetters() throws {
        let o = try AJSONObject(V.jsonGetterInput)
        for (op, expected) in V.jsonGetters {
            let parts = op.split(separator: ":", maxSplits: 1).map(String.init)
            XCTAssertEqual(Self.jsonOp(o, parts[0], parts.count > 1 ? parts[1] : ""), expected, op)
        }
    }

    func testJSONBuildAndWrite() throws {
        let built = AJSONObject().put("version", 1).put("id", "uuid/with\"quote").put("seed", Int64(1760000000000))
            .put("number", 3).put("created", Int64(1760000000123)).put("matchSeconds", 0).put("half", 0.5)
            .put("f", Float(1.25)).put("negZero", -0.0).put("flag", true).put("text", "שלום\n😀").put("nothing", nil)
        built.put("teams", AJSONArray([AJSONObject().put("id", 0).put("color", -16777216).put("roster", AJSONArray(["bob", "maya"]))]))
        XCTAssertEqual(built.toString(), V.jsonBuilt)
        let snapshot = AJSONArray([0.0, 2.5, 3.0, 0.1 + 0.2, 1e-5, 12345678.9])
        XCTAssertEqual(snapshot.toString(), V.jsonSnapshot)
        XCTAssertEqual(AJSONArray([1.0, Double.nan]).toStringOrNull(), V.jsonNaNArrayToString)
        let back = try AJSONArray(snapshot.toString())
        XCTAssertEqual(try (0..<back.length()).map { try back.getDouble($0).bitPattern }, V.jsonSnapshotBack)
        // Kotlin Bool/Int values keep their Java types (no NSNumber bridging between them).
        let typed = AJSONObject().put("one", 1).put("yes", true).put("zero", 0).put("no", false)
        XCTAssertEqual(typed.toString(), "{\"one\":1,\"yes\":true,\"zero\":0,\"no\":false}")
        XCTAssertThrowsError(try typed.getBoolean("one"))
        XCTAssertThrowsError(try typed.getInt("yes"))
        XCTAssertEqual(try typed.getInt("one"), 1)
        XCTAssertEqual(try typed.getBoolean("yes"), true)
        XCTAssertEqual(typed.optString("one"), "1")
        XCTAssertEqual(typed.optString("yes"), "true")
    }

    // MARK: - org.w3c.dom (Android DocumentBuilder = KXmlParser + DocumentBuilderImpl)

    private static func esc(_ s: String) -> String {
        var b = ""
        for c in s.utf16 {
            switch c {
            case 0x5C: b += "\\\\"
            case 0x0A: b += "\\n"
            case 0x0D: b += "\\r"
            case 0x09: b += "\\t"
            case 0x20..<0x7F: b += String(UnicodeScalar(UInt8(c)))
            default:
                let h = String(c, radix: 16, uppercase: true)
                b += "\\u" + String(repeating: "0", count: 4 - h.count) + h
            }
        }
        return b
    }

    private static func dump(_ n: AXmlNode, _ depth: Int, _ out: inout String) {
        let ind = String(repeating: "  ", count: depth)
        switch n.nodeType {
        case AXmlNode.DOCUMENT_NODE: out += "D\n"
        case AXmlNode.ELEMENT_NODE:
            let e = n as! AXmlElement
            let a = e.attributes.map { esc($0.nodeName) + "=" + esc($0.nodeValue ?? "") }.joined(separator: "|")
            out += ind + "E " + esc(e.tagName) + " {" + a + "}\n"
        case AXmlNode.TEXT_NODE: out += ind + "T " + esc(n.nodeValue ?? "") + "\n"
        case AXmlNode.CDATA_SECTION_NODE: out += ind + "C " + esc(n.nodeValue ?? "") + "\n"
        case AXmlNode.COMMENT_NODE: out += ind + "M " + esc(n.nodeValue ?? "") + "\n"
        case AXmlNode.PROCESSING_INSTRUCTION_NODE: out += ind + "P " + esc(n.nodeName) + " " + esc(n.nodeValue ?? "") + "\n"
        case AXmlNode.ENTITY_REFERENCE_NODE: out += ind + "R " + esc(n.nodeName) + "\n"
        case AXmlNode.DOCUMENT_TYPE_NODE: out += ind + "Y " + esc(n.nodeName) + "\n"
        default: out += ind + "? \(n.nodeType)\n"
        }
        for k in n.childNodes { dump(k, depth + 1, &out) }
    }

    func testXmlDocumentsMatchAndroid() {
        for (name, xml, expected) in V.xmlCases {
            var out = ""
            do {
                let doc = try AXmlDocument.parse(Data(xml.utf8))
                Self.dump(doc.document, 0, &out)
                for e in doc.getElementsByTagName("*") {
                    out += "X " + Self.esc(e.tagName) + " = " + Self.esc(e.textContent) + "\n"
                }
            } catch {
                out = "ERROR\n"
            }
            XCTAssertEqual(out, expected, name)
        }
    }

    func testXmlQuestionBankShape() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <question-bank version="1" mode="ARITHMETIC" language="he">
          <question id="q1" level="2">
            <prompt lang="he">2 &amp; 3</prompt>
            <answer correct="true">5</answer>
            <answer>6</answer>
          </question>
        </question-bank>
        """
        let doc = try AXmlDocument.parse(Data(xml.utf8))
        XCTAssertEqual(doc.documentElement.tagName, "question-bank")
        XCTAssertEqual(doc.documentElement.getAttribute("mode"), "ARITHMETIC")
        let answers = doc.getElementsByTagName("answer")
        XCTAssertEqual(answers.map { $0.textContent }, ["5", "6"])
        XCTAssertEqual(answers[1].getAttribute("correct"), "")
        XCTAssertFalse(answers[1].hasAttribute("correct"))
        XCTAssertTrue(answers[0].hasAttribute("correct"))
        XCTAssertEqual(doc.getElementsByTagName("prompt").first?.textContent, "2 & 3")
        XCTAssertTrue(answers[0].parentNode === doc.getElementsByTagName("question").first)
        XCTAssertEqual(doc.documentElement.childNodes.first?.nodeType, AXmlNode.TEXT_NODE)
        XCTAssertThrowsError(try AXmlDocument.parse(Data("<r></s>".utf8)))
    }

    // MARK: - java.util.Calendar / SimpleDateFormat (Firebase leaderboard keys, Progress, Journey)

    /// TripleShotFirebaseRepository.utcWeekKey, statement by statement (a shared Firebase path segment).
    private static func utcWeekKey(_ nowMs: Int64) -> String {
        let cal = ACalendar.getInstance(ATimeZone.getTimeZone("UTC"), ALocale.US)
        cal.timeInMillis = nowMs
        cal.firstDayOfWeek = ACalendar.MONDAY
        cal.minimalDaysInFirstWeek = 4
        let adjust: Int
        if cal.get(ACalendar.MONTH) == ACalendar.JANUARY && cal.get(ACalendar.WEEK_OF_YEAR) >= 52 {
            adjust = -1
        } else if cal.get(ACalendar.MONTH) == ACalendar.DECEMBER && cal.get(ACalendar.WEEK_OF_YEAR) == 1 {
            adjust = 1
        } else {
            adjust = 0
        }
        return AFormat.format(ALocale.US, "%04d-W%02d", cal.get(ACalendar.YEAR) + adjust, cal.get(ACalendar.WEEK_OF_YEAR))
    }

    /// TripleShotFirebaseRepository.utcMonthKey.
    private static func utcMonthKey(_ nowMs: Int64) -> String {
        let format = ASimpleDateFormat("yyyy-MM", ALocale.US)
        format.timeZone = ATimeZone.getTimeZone("UTC")
        return format.format(ADate(nowMs))
    }

    /// TripleShotProgressFragment.weekKey.
    private static func progressWeekKey(_ ms: Int64, _ tz: ATimeZone) -> String {
        let cal = ACalendar.getInstance(tz, ALocale.US)
        cal.timeInMillis = ms
        cal.firstDayOfWeek = ACalendar.MONDAY
        cal.minimalDaysInFirstWeek = 4
        return AFormat.format(ALocale.US, "W%02d/%02d", cal.get(ACalendar.WEEK_OF_YEAR), cal.get(ACalendar.YEAR) % 100)
    }

    /// TripleShotProgressFragment.monthKey.
    private static func progressMonthKey(_ ms: Int64, _ tz: ATimeZone) -> String {
        let format = ASimpleDateFormat("MM/yy", ALocale.US)
        format.timeZone = tz
        return format.format(ADate(ms))
    }

    func testCalendarKeysMatchAndroid() {
        let utc = ATimeZone.getTimeZone("UTC")
        for (ms, week, month, progressWeek, progressMonth, day) in V.dateKeys {
            XCTAssertEqual(Self.utcWeekKey(ms), week, "utcWeekKey(\(ms))")
            XCTAssertEqual(Self.utcMonthKey(ms), month, "utcMonthKey(\(ms))")
            XCTAssertEqual(Self.progressWeekKey(ms, utc), progressWeek, "weekKey(\(ms))")
            XCTAssertEqual(Self.progressMonthKey(ms, utc), progressMonth, "monthKey(\(ms))")
            let dayFormat = ASimpleDateFormat("yyyy-MM-dd", ALocale.ROOT)
            dayFormat.timeZone = utc
            XCTAssertEqual(dayFormat.format(ADate(ms)), day, "yyyy-MM-dd of \(ms)")
        }
    }

    func testZonedDatesMatchAndroid() {
        for (ms, zone, text, progressWeek, progressMonth) in V.zonedDates {
            let tz = ATimeZone.getTimeZone(zone)
            XCTAssertEqual(tz.getID(), zone)
            let format = ASimpleDateFormat("dd/MM/yyyy HH:mm", ALocale("he"))
            format.timeZone = tz
            XCTAssertEqual(format.format(ADate(ms)), text, "\(zone) \(ms)")
            XCTAssertEqual(Self.progressWeekKey(ms, tz), progressWeek, "weekKey \(zone) \(ms)")
            XCTAssertEqual(Self.progressMonthKey(ms, tz), progressMonth, "monthKey \(zone) \(ms)")
        }
    }

    // MARK: - SharedPreferences

    func testSharedPreferences() {
        let name = "androidkit_kotlin_tests_" + UUID().uuidString
        let prefs = getSharedPreferences(name, MODE_PRIVATE)
        defer { prefs.edit().clear().commit() }
        XCTAssertTrue(getSharedPreferences(name, MODE_PRIVATE) === prefs)
        XCTAssertEqual(prefs.getString("s", "d"), "d")
        XCTAssertNil(prefs.getString("s", nil))
        XCTAssertEqual(prefs.getInt("i", 7), 7)
        XCTAssertEqual(prefs.getLong("l", -1), -1)
        XCTAssertEqual(prefs.getFloat("f", 1.5), 1.5)
        XCTAssertTrue(prefs.getBoolean("b", true))
        XCTAssertFalse(prefs.contains("i"))

        prefs.edit().putString("s", "v").putInt("i", 42).putLong("l", 1760000000000).putFloat("f", 0.25)
            .putBoolean("b", false).apply()
        XCTAssertEqual(prefs.getString("s", nil), "v")
        XCTAssertEqual(prefs.getInt("i", 0), 42)
        XCTAssertEqual(prefs.getLong("l", 0), 1760000000000)
        XCTAssertEqual(prefs.getFloat("f", 0), 0.25)
        XCTAssertFalse(prefs.getBoolean("b", true))
        XCTAssertTrue(prefs.contains("i"))
        XCTAssertEqual(UserDefaults.standard.object(forKey: name + ".s") as? String, "v")
        XCTAssertEqual(prefs.getAll().count, 5)

        // A null String removes the key; remove() removes it.
        XCTAssertTrue(prefs.edit().remove("i").putString("s", nil).commit())
        XCTAssertFalse(prefs.contains("i"))
        XCTAssertFalse(prefs.contains("s"))

        // clear() runs before the puts of the same editor.
        prefs.edit().putInt("kept", 1).clear().commit()
        XCTAssertEqual(prefs.getInt("kept", 0), 1)
        XCTAssertFalse(prefs.contains("l"))

        // String sets come back in java.util.HashSet order (spec 01 / 18: the selected topics).
        prefs.edit().putStringSet("selected_categories", Self.categories).apply()
        XCTAssertEqual(prefs.getStringSet("selected_categories", nil), V.hashSetOrders[0].copy)
        XCTAssertEqual(prefs.getStringSet("missing", ["x"]), ["x"])
        XCTAssertNil(prefs.getStringSet("missing", nil))
        prefs.edit().putStringSet("pair", ["HISTORY", "SCIENCE"]).apply()
        XCTAssertEqual(prefs.getStringSet("pair", nil), ["SCIENCE", "HISTORY"])

        // A set read from storage (a later process): `new HashSet()` filled in the stored order.
        let other = name + "_reload"
        UserDefaults.standard.set(Array(Self.categories.reversed()), forKey: other + ".selected_categories")
        XCTAssertEqual(getSharedPreferences(other, MODE_PRIVATE).getStringSet("selected_categories", nil), V.hashSetOrders[1].added)
        UserDefaults.standard.removeObject(forKey: other + ".selected_categories")
    }

    // MARK: - java.util.Locale

    func testLocale() {
        for (tag, language, country, script, languageTag, text) in V.localeTags {
            let l = ALocale.forLanguageTag(tag)
            XCTAssertEqual(l.language, language, tag)
            XCTAssertEqual(l.country, country, tag)
            XCTAssertEqual(l.script, script, tag)
            XCTAssertEqual(l.toLanguageTag(), languageTag, tag)
            XCTAssertEqual(l.toString(), text, tag)
        }
        XCTAssertEqual(ALocale("iw", "il").language, "he")
        XCTAssertEqual(ALocale("iw", "il").country, "IL")
        XCTAssertEqual(ALocale("EN").language, "en")
        XCTAssertEqual(ALocale.ROOT.toLanguageTag(), "und")
        XCTAssertEqual(ALocale.US, ALocale("en", "US"))
        XCTAssertEqual(ALocale.ENGLISH.toLanguageTag(), "en")
        XCTAssertTrue(ALocale.US.isUS)
        XCTAssertFalse(ALocale.ENGLISH.isUS)
        let d = ALocale.getDefault()
        XCTAssertEqual(d, ALocale.forLanguageTag(Locale.preferredLanguages.first ?? "en"))
        XCTAssertNotEqual(d.language, "iw")
        XCTAssertEqual(d.language, d.language.lowercased())
    }
}

// MARK: - Golden vectors (generated by KitVectors.kt; do not edit by hand)

private enum AndroidKitKotlinVectors {
    /// Kotlin Random(seed: Long): the first 12 nextInt() values.
    static let randomFirst: [(seed: Int64, ints: [Int32])] = [
        (seed: 0, ints: [-1934310868, 1409199696, -649160781, -1454478562, -1464141532, 801930215, 34307923, 811657455, 1395731628, -587880378, 43427776, 269723129]),
        (seed: 1, ints: [600123930, -1531902544, -527218591, -1598672019, -541439398, 1143743615, -166807693, -2022884062, 315684520, 970147242, 1329509210, -802272133]),
        (seed: -1, ints: [-280203964, -1115932487, -2122700674, 1389910083, 1386645512, 629351389, 1721609398, -371340633, -376319616, -179223823, 1691798198, -370338194]),
        (seed: 42, ints: [972016666, 1740578880, -408207414, -112774692, 1162768683, 649964064, -126744254, -95941416, 788572539, 274632774, -1749679591, -1406331962]),
        (seed: 31337, ints: [391231528, -803776161, 87738370, -1882149745, -1009391807, -118316173, -1321478216, 1998708508, -1139616296, 618706223, 1899328564, 1077912089]),
        (seed: 1234567890123, ints: [-978035486, 581284957, 963480238, -1799220487, -581640217, 259267099, 1649400318, -1032363530, -127752132, -888858645, 1608488777, -669753466]),
        (seed: 9223372036854775807, ints: [-823365724, 1568422073, -1299975770, 1402130883, -1728149584, 1076044765, -1522684746, -1566013411, -424745778, -308149519, 1195084470, 291264110]),
        (seed: -9223372036854775808, ints: [-1399536436, 67022416, 138246747, -1507543906, 1662187900, 1718385639, -408191149, -1995068967, 1426850230, 914745414, 1207035840, -347871751]),
        (seed: 2147483647, ints: [-1519020059, 1146489314, 755292399, -1464272916, -472017895, 1425676998, -1804245459, -515255030, -1186729171, -1521124622, 1378109101, -2083916438]),
        (seed: -2147483648, ints: [-468773749, -303786953, 2109491522, 1936655093, 905126675, 1522713278, -117195824, 448050892, 593943127, -1930336187, 887695797, -2052682533]),
        (seed: 4294967296, ints: [669068263, -1630568617, 635679789, 1939280705, -1158684384, 1610734455, 2036517150, 2136851624, 338902759, -2085760830, 2065529352, 1384434602]),
        (seed: 1760000000000, ints: [-337619862, 2111320207, 791028487, -1220119171, 972859982, 1374168436, -84924896, 1086278909, -29719162, -196833032, -1074181589, -74079359]),
        (seed: 1760004855747, ints: [22617712, 764669011, 743074983, -1187325702, 207351439, -1959536002, 1664676543, -476633932, 783110711, 82580426, -1283531019, 870431173]),
        (seed: 1760040272716, ints: [-515371332, -2073413947, -1515566490, 519734602, -300728456, 205002276, 2095415567, 1546699153, 1193043060, 102268802, -978499907, -1205669175]),
        (seed: 1760369498109, ints: [-1912451465, 881415603, -1267024707, 1410781279, 1958127554, -1766367880, -1555172231, -1612429602, -478459675, -1182214402, -174773328, 1392095211]),
    ]
    /// Kotlin Random(seed: Int): the first 8 nextInt() values and two nextFloat() bit patterns.
    static let randomIntSeed: [(seed: Int, ints: [Int32], floats: [UInt32])] = [
        (seed: 0, ints: [-1934310868, 1409199696, -649160781, -1454478562, -1464141532, 801930215, 34307923, 811657455], floats: [0x3EA66258, 0x3F5CF5A8]),
        (seed: 1, ints: [600123930, -1531902544, -527218591, -1598672019, -541439398, 1143743615, -166807693, -2022884062], floats: [0x3D9687B0, 0x3E674D14]),
        (seed: -1, ints: [-280203964, -1115932487, -2122700674, 1389910083, 1386645512, 629351389, 1721609398, -371340633], floats: [0x3F6991D1, 0x3F755142]),
        (seed: 12345, ints: [-984488024, -139740814, -704757440, -2028879536, -1482499884, -381046028, -779990893, 407561407], floats: [0x3F26CA5F, 0x3EF39102]),
        (seed: -2147483648, ints: [-468773749, -303786953, 2109491522, 1936655093, 905126675, 1522713278, -117195824, 448050892], floats: [0x3E0D9B68, 0x3F0CF168]),
        (seed: 2147483647, ints: [-1519020059, 1146489314, 755292399, -1464272916, -472017895, 1425676998, -1804245459, -515255030], floats: [0x3F3943F3, 0x3F25557A]),
        (seed: 1540483477, ints: [-1355411244, -1461155895, -1185907530, 2045371084, -1236618634, -1999254873, 1714992188, -1022268189], floats: [0x3F6A52A8, 0x3EE6C0BA]),
    ]
    /// Fresh Random(seed) per script; every step is (operation, expected result).
    static let randomScripts: [(seed: Int64, steps: [(String, String)])] = [
        (seed: 0, steps: [("int", "-1934310868"), ("int", "1409199696"), ("int", "-649160781"), ("int", "-1454478562"), ("bits:0", "0"), ("bits:1", "0"), ("bits:5", "0"), ("bits:16", "12384"), ("bits:31", "697865814"), ("bits:32", "-587880378"), ("int", "43427776")]),
        (seed: 0, steps: [("until:1", "0"), ("until:2", "0"), ("until:3", "0"), ("until:7", "3"), ("until:10", "2"), ("until:16", "2"), ("until:100", "61"), ("until:1000", "727"), ("until:2147483647", "697865814"), ("until:1073741824", "926771729"), ("range:-5:5", "3"), ("range:2:9", "7"), ("range:-2147483648:2147483647", "-1998983480"), ("range:-2147483648:0", "-1644715186"), ("range:-1000000000:2000000000", "1569193737"), ("range:-4:5", "0"), ("range:1000:9999", "4528"), ("irange:1:5", "1"), ("irange:-2147483648:2147483647", "-1666136984"), ("irange:0:2147483647", "1924871339"), ("irange:-2147483648:-1", "-936756469"), ("until:100", "18")]),
        (seed: 0, steps: [("long", "-8307801916948173232"), ("long", "-2788124325695296738"), ("long", "-6288439995853407257"), ("luntil:1099511627776", "9401592047"), ("luntil:10", "5"), ("luntil:4294967296", "43427776"), ("luntil:4", "0"), ("luntil:9223372036854775807", "4930587701435409230"), ("luntil:2147483648", "1485368663"), ("lrange:-700:701", "46"), ("lrange:0:1700", "1061"), ("lrange:-9223372036854775808:9223372036854775807", "-7156003857381299882"), ("lrange:-4611686018427387904:4611686018427387909", "3113159664496217180"), ("lrange:1760000000000:1760000005000", "1760000002347"), ("luntil:3", "2"), ("luntil:8589934592", "1525745488"), ("luntil:1", "0")]),
        (seed: 0, steps: [("float", "0x3F0CB4C2"), ("float", "0x3EA7FD5C"), ("float", "0x3F594E97"), ("float", "0x3F294E6B"), ("double", "0x3FE5175F217E63DF"), ("double", "0x3F805BFA60C1D1C0"), ("double", "0x3FD4CC4B2DCF5A84"), ("duntil:10.0", "0x3FB9E28DA8311EB0"), ("drange:-1.0:1.0", "0x3FB1B3DD9DF7A340"), ("drange:-1.7976931348623157E308:1.7976931348623157E308", "0x7FD888ED4BB0FFDE"), ("drange:0.0:1.0E-300", "0x01A452ECAC9010E8"), ("duntil:4.9E-324", "0x0000000000000000"), ("bool", "true"), ("bool", "true"), ("bool", "false"), ("bool", "false"), ("bool", "false"), ("bool", "true")]),
        (seed: 0, steps: [("float", "0x3F0CB4C2"), ("until:100", "48"), ("bool", "true"), ("lrange:-700:701", "-528"), ("double", "0x3FC7E63DE0416FE8"), ("int", "811657455"), ("range:-4:5", "-4"), ("float", "0x3F5CF5A8"), ("float", "0x3C25A9C0"), ("until:3", "2"), ("lrange:0:1700", "530"), ("bool", "true")]),
        (seed: 1, steps: [("int", "600123930"), ("int", "-1531902544"), ("int", "-527218591"), ("int", "-1598672019"), ("bits:0", "0"), ("bits:1", "0"), ("bits:5", "30"), ("bits:16", "34669"), ("bits:31", "157842260"), ("bits:32", "970147242"), ("int", "1329509210")]),
        (seed: 1, steps: [("until:1", "0"), ("until:2", "1"), ("until:3", "1"), ("until:7", "5"), ("until:10", "9"), ("until:16", "4"), ("until:100", "1"), ("until:1000", "617"), ("until:2147483647", "157842260"), ("until:1073741824", "242536810"), ("range:-5:5", "0"), ("range:2:9", "8"), ("range:-2147483648:2147483647", "-845605708"), ("range:-2147483648:0", "-1508068647"), ("range:-1000000000:2000000000", "-574689477"), ("range:-4:5", "0"), ("range:1000:9999", "1322"), ("irange:1:5", "3"), ("irange:-2147483648:2147483647", "-2009757078"), ("irange:0:2147483647", "1870491047"), ("irange:-2147483648:-1", "-1783975888"), ("until:100", "8")]),
        (seed: 1, steps: [("long", "2577512651365090736"), ("long", "-2264386607786871955"), ("long", "-2325464506032184193"), ("luntil:1099511627776", "1058834038050"), ("luntil:10", "1"), ("luntil:4294967296", "1329509210"), ("luntil:4", "3"), ("luntil:9223372036854775807", "7407447606908728025"), ("luntil:2147483648", "1561744528"), ("lrange:-700:701", "320"), ("lrange:0:1700", "1317"), ("lrange:-9223372036854775808:9223372036854775807", "-8631840923468506290"), ("lrange:-4611686018427387904:4611686018427387909", "3122507882718949737"), ("lrange:1760000000000:1760000005000", "1760000004709"), ("luntil:3", "1"), ("luntil:8589934592", "6302620600"), ("luntil:1", "0")]),
        (seed: 1, steps: [("float", "0x3E0F14A8"), ("float", "0x3F24B105"), ("float", "0x3F609348"), ("float", "0x3F20B633"), ("double", "0x3FEBF7494A216123"), ("double", "0x3FEEC1D6EC3B69E9"), ("double", "0x3FB2D0F68E74D168"), ("duntil:10.0", "0x4008C39814439DF8"), ("drange:-1.0:1.0", "0x3FE3664524C3965A"), ("drange:-1.7976931348623157E308:1.7976931348623157E308", "0x7FDD16549BB7DDE2"), ("drange:0.0:1.0E-300", "0x01736B3CBDAE714F"), ("duntil:4.9E-324", "0x0000000000000000"), ("bool", "true"), ("bool", "false"), ("bool", "false"), ("bool", "true"), ("bool", "false"), ("bool", "true")]),
        (seed: 1, steps: [("float", "0x3E0F14A8"), ("until:100", "76"), ("bool", "true"), ("lrange:-700:701", "-277"), ("double", "0x3FD10B091F60EB76"), ("int", "-2022884062"), ("range:-4:5", "4"), ("float", "0x3E674D14"), ("float", "0x3E9E7D66"), ("until:3", "1"), ("lrange:0:1700", "825"), ("bool", "true")]),
        (seed: -1, steps: [("int", "-280203964"), ("int", "-1115932487"), ("int", "-2122700674"), ("int", "1389910083"), ("bits:0", "0"), ("bits:1", "0"), ("bits:5", "12"), ("bits:16", "59869"), ("bits:31", "1959323840"), ("bits:32", "-179223823"), ("int", "1691798198")]),
        (seed: -1, steps: [("until:1", "0"), ("until:2", "1"), ("until:3", "0"), ("until:7", "4"), ("until:10", "6"), ("until:16", "2"), ("until:100", "99"), ("until:1000", "331"), ("until:2147483647", "1959323840"), ("until:1073741824", "1028935868"), ("range:-5:5", "4"), ("range:2:9", "3"), ("range:-2147483648:2147483647", "667567539"), ("range:-2147483648:0", "-35003134"), ("range:-1000000000:2000000000", "1380466697"), ("range:-4:5", "-3"), ("range:1000:9999", "3086"), ("irange:1:5", "1"), ("irange:-2147483648:2147483647", "-1470239172"), ("irange:0:2147483647", "613474958"), ("irange:-2147483648:-1", "-1021525341"), ("until:100", "75")]),
        (seed: -1, steps: [("long", "-1203466862705493831"), ("long", "-9116929972637247421"), ("long", "5955597125814526941"), ("luntil:1099511627776", "442010290855"), ("luntil:10", "8"), ("luntil:4294967296", "1691798198"), ("luntil:4", "3"), ("luntil:9223372036854775807", "1433590373903099138"), ("luntil:2147483648", "1336338661"), ("lrange:-700:701", "493"), ("lrange:0:1700", "263"), ("lrange:-9223372036854775808:9223372036854775807", "-2197088583279259560"), ("lrange:-4611686018427387904:4611686018427387909", "2023329283030089052"), ("lrange:1760000000000:1760000005000", "1760000004162"), ("luntil:3", "1"), ("luntil:8589934592", "7158862229"), ("luntil:1", "0")]),
        (seed: -1, steps: [("float", "0x3F6F4C6D"), ("float", "0x3F3D7C38"), ("float", "0x3F017A28"), ("float", "0x3EA5B0B0"), ("double", "0x3FD4A9A20258323C"), ("double", "0x3FD9A76B2E9DDCAA"), ("double", "0x3FED323A37AA8A17"), ("duntil:10.0", "0x400F831F5A4685C0"), ("drange:-1.0:1.0", "0xBFE60D6E9042C360"), ("drange:-1.7976931348623157E308:1.7976931348623157E308", "0x7FCF4DD1ED71B65C"), ("drange:0.0:1.0E-300", "0x01A01069D3C8082D"), ("duntil:4.9E-324", "0x0000000000000000"), ("bool", "true"), ("bool", "true"), ("bool", "false"), ("bool", "true"), ("bool", "true"), ("bool", "false")]),
        (seed: -1, steps: [("float", "0x3F6F4C6D"), ("until:100", "4"), ("bool", "true"), ("lrange:-700:701", "-54"), ("double", "0x3FC2C191ECD3B594"), ("int", "-371340633"), ("range:-4:5", "4"), ("float", "0x3F755142"), ("float", "0x3EC9AD94"), ("until:3", "1"), ("lrange:0:1700", "238"), ("bool", "true")]),
        (seed: 42, steps: [("int", "972016666"), ("int", "1740578880"), ("int", "-408207414"), ("int", "-112774692"), ("bits:0", "0"), ("bits:1", "0"), ("bits:5", "31"), ("bits:16", "64072"), ("bits:31", "394286269"), ("bits:32", "274632774"), ("int", "-1749679591")]),
        (seed: 42, steps: [("until:1", "0"), ("until:2", "0"), ("until:3", "2"), ("until:7", "1"), ("until:10", "1"), ("until:16", "2"), ("until:100", "21"), ("until:1000", "940"), ("until:2147483647", "394286269"), ("until:1073741824", "68658193"), ("range:-5:5", "-3"), ("range:2:9", "4"), ("range:-2147483648:2147483647", "1264238559"), ("range:-2147483648:0", "-582034545"), ("range:-1000000000:2000000000", "593343317"), ("range:-4:5", "0"), ("range:1000:9999", "6473"), ("irange:1:5", "1"), ("irange:-2147483648:2147483647", "367139253"), ("irange:0:2147483647", "411305113"), ("irange:-2147483648:-1", "-782978279"), ("until:100", "7")]),
        (seed: 42, steps: [("long", "4174779793377534016"), ("long", "-1753237493227507236"), ("long", "4994053466947955232"), ("luntil:1099511627776", "1069350915288"), ("luntil:10", "9"), ("luntil:4294967296", "2545287705"), ("luntil:4", "2"), ("luntil:9223372036854775807", "2714931632041548687"), ("luntil:2147483648", "296671658"), ("lrange:-700:701", "181"), ("lrange:0:1700", "1374"), ("lrange:-9223372036854775808:9223372036854775807", "3533084016459212338"), ("lrange:-4611686018427387904:4611686018427387909", "306962418377429987"), ("lrange:1760000000000:1760000005000", "1760000001155"), ("luntil:3", "2"), ("luntil:8589934592", "2194430520"), ("luntil:1", "0")]),
        (seed: 42, steps: [("float", "0x3E67BF30"), ("float", "0x3ECF7E40"), ("float", "0x3F67AB3F"), ("float", "0x3F794731"), ("double", "0x3FD1539C426BDAA2"), ("double", "0x3FEF0E412FD24066"), ("double", "0x3FC78054A20BD208"), ("duntil:10.0", "0x4017B47056B9C2C6"), ("drange:-1.0:1.0", "0xBFDA52A008AC4920"), ("drange:-1.7976931348623157E308:1.7976931348623157E308", "0xFFE7289320EA5C49"), ("drange:0.0:1.0E-300", "0x01996B65A5ED7079"), ("duntil:4.9E-324", "0x0000000000000000"), ("bool", "true"), ("bool", "false"), ("bool", "true"), ("bool", "false"), ("bool", "false"), ("bool", "false")]),
        (seed: 42, steps: [("float", "0x3E67BF30"), ("until:100", "40"), ("bool", "true"), ("lrange:-700:701", "515"), ("double", "0x3FC35ED51F0E4128"), ("int", "-95941416"), ("range:-4:5", "0"), ("float", "0x3D82F480"), ("float", "0x3F17B602"), ("until:3", "1"), ("lrange:0:1700", "1587"), ("bool", "false")]),
        (seed: 31337, steps: [("int", "391231528"), ("int", "-803776161"), ("int", "87738370"), ("int", "-1882149745"), ("bits:0", "0"), ("bits:1", "1"), ("bits:5", "22"), ("bits:16", "30497"), ("bits:31", "1577675500"), ("bits:32", "618706223"), ("int", "1899328564")]),
        (seed: 31337, steps: [("until:1", "0"), ("until:2", "1"), ("until:3", "2"), ("until:7", "5"), ("until:10", "4"), ("until:16", "15"), ("until:100", "40"), ("until:1000", "254"), ("until:2147483647", "1577675500"), ("until:1073741824", "154676555"), ("range:-5:5", "-3"), ("range:2:9", "6"), ("range:-2147483648:2147483647", "1241401319"), ("range:-2147483648:0", "-816333083"), ("range:-1000000000:2000000000", "1426896398"), ("range:-4:5", "-1"), ("range:1000:9999", "2925"), ("irange:1:5", "5"), ("irange:-2147483648:2147483647", "-67361867"), ("irange:0:2147483647", "1536440179"), ("irange:-2147483648:-1", "-559258250"), ("until:100", "79")]),
        (seed: 31337, steps: [("long", "1680326617120332127"), ("long", "376833427872197775"), ("long", "-4335304800033660045"), ("luntil:1099511627776", "762207919900"), ("luntil:10", "1"), ("luntil:4294967296", "1899328564"), ("luntil:4", "1"), ("luntil:9223372036854775807", "2665889032341798629"), ("luntil:2147483648", "713448199"), ("lrange:-700:701", "606"), ("lrange:0:1700", "830"), ("lrange:-9223372036854775808:9223372036854775807", "-5248823428402328852"), ("lrange:-4611686018427387904:4611686018427387909", "-2052130810986414837"), ("lrange:1760000000000:1760000005000", "1760000004346"), ("luntil:3", "1"), ("luntil:8589934592", "5002466260"), ("luntil:1", "0")]),
        (seed: 31337, steps: [("float", "0x3DBA8DC0"), ("float", "0x3F501759"), ("float", "0x3CA75900"), ("float", "0x3F0FD0AC"), ("double", "0x3FE87ABCEFC7951B"), ("double", "0x3FE6277AF3B90EF8"), ("double", "0x3FE7825AB92705A9"), ("duntil:10.0", "0x4011B05A22827C54"), ("drange:-1.0:1.0", "0xBFDB00DC0C2A1048"), ("drange:-1.7976931348623157E308:1.7976931348623157E308", "0xFFD579A4E3F2B72B"), ("drange:0.0:1.0E-300", "0x018800043CE29331"), ("duntil:4.9E-324", "0x0000000000000000"), ("bool", "true"), ("bool", "true"), ("bool", "false"), ("bool", "false"), ("bool", "true"), ("bool", "true")]),
        (seed: 31337, steps: [("float", "0x3DBA8DC0"), ("until:100", "67"), ("bool", "false"), ("lrange:-700:701", "-523"), ("double", "0x3FEF1E546D89DEBD"), ("int", "1998708508"), ("range:-4:5", "3"), ("float", "0x3E1382D4"), ("float", "0x3EE26AE8"), ("until:3", "2"), ("lrange:0:1700", "729"), ("bool", "false")]),
        (seed: 1234567890123, steps: [("int", "-978035486"), ("int", "581284957"), ("int", "963480238"), ("int", "-1799220487"), ("bits:0", "0"), ("bits:1", "0"), ("bits:5", "12"), ("bits:16", "49783"), ("bits:31", "2083607582"), ("bits:32", "-888858645"), ("int", "1608488777")]),
        (seed: 1234567890123, steps: [("until:1", "0"), ("until:2", "0"), ("until:3", "2"), ("until:7", "1"), ("until:10", "9"), ("until:16", "0"), ("until:100", "59"), ("until:1000", "883"), ("until:2147483647", "2083607582"), ("until:1073741824", "851527162"), ("range:-5:5", "3"), ("range:2:9", "2"), ("range:-2147483648:2147483647", "1534272929"), ("range:-2147483648:0", "-833164791"), ("range:-1000000000:2000000000", "1813278758"), ("range:-4:5", "0"), ("range:1000:9999", "2027"), ("irange:1:5", "4"), ("irange:-2147483648:2147483647", "1776890273"), ("irange:0:2147483647", "106906943"), ("irange:-2147483648:-1", "-1039058337"), ("until:100", "43")]),
        (seed: 1234567890123, steps: [("long", "-4200630426116180899"), ("long", "4138116110753075961"), ("long", "-2498125709794076133"), ("luntil:1099511627776", "424169398774"), ("luntil:10", "9"), ("luntil:4294967296", "1608488777"), ("luntil:4", "3"), ("luntil:9223372036854775807", "3294826025763400201"), ("luntil:2147483648", "906639379"), ("lrange:-700:701", "157"), ("lrange:0:1700", "572"), ("lrange:-9223372036854775808:9223372036854775807", "918323645722555582"), ("lrange:-4611686018427387904:4611686018427387909", "-2232271493565676329"), ("lrange:1760000000000:1760000005000", "1760000003411"), ("luntil:3", "0"), ("luntil:8589934592", "6553214120"), ("luntil:1", "0")]),
        (seed: 1234567890123, steps: [("float", "0x3F45B45C"), ("float", "0x3E0A96D0"), ("float", "0x3E65B628"), ("float", "0x3F14C212"), ("double", "0x3FEBAA9BF87BA0D0"), ("double", "0x3FD893F67C27761E"), ("double", "0x3FEF0C55065828BF"), ("duntil:10.0", "0x400DF5DF54E19776"), ("drange:-1.0:1.0", "0xBFD2466D2C6A4580"), ("drange:-1.7976931348623157E308:1.7976931348623157E308", "0xFFC3EB8FFA33DE96"), ("drange:0.0:1.0E-300", "0x019F74F5CEE17F01"), ("duntil:4.9E-324", "0x0000000000000000"), ("bool", "true"), ("bool", "true"), ("bool", "false"), ("bool", "false"), ("bool", "false"), ("bool", "false")]),
        (seed: 1234567890123, steps: [("float", "0x3F45B45C"), ("until:100", "78"), ("bool", "false"), ("lrange:-700:701", "-695"), ("double", "0x3FAEE8343127ECF0"), ("int", "-1032363530"), ("range:-4:5", "1"), ("float", "0x3F4B0517"), ("float", "0x3EBFBF2E"), ("until:3", "0"), ("lrange:0:1700", "1501"), ("bool", "false")]),
        (seed: 9223372036854775807, steps: [("int", "-823365724"), ("int", "1568422073"), ("int", "-1299975770"), ("int", "1402130883"), ("bits:0", "0"), ("bits:1", "0"), ("bits:5", "20"), ("bits:16", "41640"), ("bits:31", "1935110759"), ("bits:32", "-308149519"), ("int", "1195084470")]),
        (seed: 9223372036854775807, steps: [("until:1", "0"), ("until:2", "0"), ("until:3", "1"), ("until:7", "6"), ("until:10", "6"), ("until:16", "4"), ("until:100", "75"), ("until:1000", "942"), ("until:2147483647", "1935110759"), ("until:1073741824", "996704444"), ("range:-5:5", "0"), ("range:2:9", "4"), ("range:-2147483648:2147483647", "-477669202"), ("range:-2147483648:0", "-2075259030"), ("range:-1000000000:2000000000", "-445850017"), ("range:-4:5", "0"), ("range:1000:9999", "1327"), ("irange:1:5", "2"), ("irange:-2147483648:2147483647", "-764819087"), ("irange:0:2147483647", "241164853"), ("irange:-2147483648:-1", "-1021047505"), ("until:100", "52")]),
        (seed: 9223372036854775807, steps: [("long", "-3536328855658940231"), ("long", "-5583353416340287037"), ("long", "-7422345944799960099"), ("luntil:1099511627776", "711398557725"), ("luntil:10", "4"), ("luntil:4294967296", "1195084470"), ("luntil:4", "0"), ("luntil:9223372036854775807", "8197585236478791530"), ("luntil:2147483648", "1517725133"), ("lrange:-700:701", "603"), ("lrange:0:1700", "1044"), ("lrange:-9223372036854775808:9223372036854775807", "-3284872965539249046"), ("lrange:-4611686018427387904:4611686018427387909", "-809661182975962132"), ("lrange:1760000000000:1760000005000", "1760000000243"), ("luntil:3", "1"), ("luntil:8589934592", "1225944705"), ("luntil:1", "0")]),
        (seed: 9223372036854775807, steps: [("float", "0x3F4EEC6F"), ("float", "0x3EBAF870"), ("float", "0x3F3283F1"), ("float", "0x3EA725A2"), ("double", "0x3FE31FD0F201191E"), ("double", "0x3FE4A7B595154440"), ("double", "0x3FECD5DC9F6D1017"), ("duntil:10.0", "0x4006429B495B36C0"), ("drange:-1.0:1.0", "0x3FE8E1D62089C1EC"), ("drange:-1.7976931348623157E308:1.7976931348623157E308", "0x7FDA76A5DCAD9BC6"), ("drange:0.0:1.0E-300", "0x01901A65DE3153BC"), ("duntil:4.9E-324", "0x0000000000000000"), ("bool", "false"), ("bool", "true"), ("bool", "true"), ("bool", "true"), ("bool", "true"), ("bool", "true")]),
        (seed: 9223372036854775807, steps: [("float", "0x3F4EEC6F"), ("until:100", "36"), ("bool", "true"), ("lrange:-700:701", "-165"), ("double", "0x3FD008C8FA53DACA"), ("int", "-1566013411"), ("range:-4:5", "1"), ("float", "0x3F6DA202"), ("float", "0x3E8E7714"), ("until:3", "1"), ("lrange:0:1700", "430"), ("bool", "true")]),
        (seed: -9223372036854775808, steps: [("int", "-1399536436"), ("int", "67022416"), ("int", "138246747"), ("int", "-1507543906"), ("bits:0", "0"), ("bits:1", "0"), ("bits:5", "28"), ("bits:16", "35093"), ("bits:31", "713425115"), ("bits:32", "914745414"), ("int", "1207035840")]),
        (seed: -9223372036854775808, steps: [("until:1", "0"), ("until:2", "0"), ("until:3", "1"), ("until:7", "5"), ("until:10", "0"), ("until:16", "6"), ("until:100", "73"), ("until:1000", "164"), ("until:2147483647", "713425115"), ("until:1073741824", "228686353"), ("range:-5:5", "-5"), ("range:2:9", "2"), ("range:-2147483648:2147483647", "1651958747"), ("range:-2147483648:0", "-1538044634"), ("range:-1000000000:2000000000", "1661095476"), ("range:-4:5", "0"), ("range:1000:9999", "7575"), ("irange:1:5", "2"), ("irange:-2147483648:2147483647", "-724868216"), ("irange:0:2147483647", "1597588738"), ("irange:-2147483648:-1", "-252768741"), ("until:100", "11")]),
        (seed: -9223372036854775808, steps: [("long", "-6010963222113374640"), ("long", "593765255635842206"), ("long", "7139042672025304039"), ("luntil:1099511627776", "994437343705"), ("luntil:10", "7"), ("luntil:4294967296", "1207035840"), ("luntil:4", "3"), ("luntil:9223372036854775807", "3547554396962508070"), ("luntil:2147483648", "1641591167"), ("lrange:-700:701", "-290"), ("lrange:0:1700", "880"), ("lrange:-9223372036854775808:9223372036854775807", "-5217052253545077880"), ("lrange:-4611686018427387904:4611686018427387909", "3812568694456197296"), ("lrange:1760000000000:1760000005000", "1760000001594"), ("luntil:3", "1"), ("luntil:8589934592", "6544779503"), ("luntil:1", "0")]),
        (seed: -9223372036854775808, steps: [("float", "0x3F2C94C4"), ("float", "0x3C7FAB80"), ("float", "0x3D03D7A0"), ("float", "0x3F2624B4"), ("double", "0x3FD8C4BE5666C7BE"), ("double", "0x3FECF56FEC48AD4E"), ("double", "0x3FD5430063685E84"), ("duntil:10.0", "0x40067B987E614DF6"), ("drange:-1.0:1.0", "0xBFCD891C2DD65970"), ("drange:-1.7976931348623157E308:1.7976931348623157E308", "0x7FE0EC58B7E2E031"), ("drange:0.0:1.0E-300", "0x0190938F5A1554ED"), ("duntil:4.9E-324", "0x0000000000000000"), ("bool", "true"), ("bool", "true"), ("bool", "true"), ("bool", "false"), ("bool", "false"), ("bool", "false")]),
        (seed: -9223372036854775808, steps: [("float", "0x3F2C94C4"), ("until:100", "8"), ("bool", "false"), ("lrange:-700:701", "91"), ("double", "0x3FD99B1EFE7AB7F4"), ("int", "-1995068967"), ("range:-4:5", "-2"), ("float", "0x3E5A17A0"), ("float", "0x3E8FE3CE"), ("until:3", "1"), ("lrange:0:1700", "1670"), ("bool", "true")]),
        (seed: 2147483647, steps: [("int", "-1519020059"), ("int", "1146489314"), ("int", "755292399"), ("int", "-1464272916"), ("bits:0", "0"), ("bits:1", "0"), ("bits:5", "18"), ("bits:16", "57673"), ("bits:31", "1554119062"), ("bits:32", "-1521124622"), ("int", "1378109101")]),
        (seed: 2147483647, steps: [("until:1", "0"), ("until:2", "0"), ("until:3", "1"), ("until:7", "5"), ("until:10", "0"), ("until:16", "5"), ("until:100", "18"), ("until:1000", "133"), ("until:2147483647", "1554119062"), ("until:1073741824", "693460668"), ("range:-5:5", "-5"), ("range:2:9", "3"), ("range:-2147483648:2147483647", "-1708485999"), ("range:-2147483648:0", "-536098901"), ("range:-1000000000:2000000000", "-959221221"), ("range:-4:5", "-3"), ("range:1000:9999", "2961"), ("irange:1:5", "2"), ("irange:-2147483648:2147483647", "639746881"), ("irange:0:2147483647", "1070669977"), ("irange:-2147483648:-1", "-1182657926"), ("until:100", "68")]),
        (seed: 2147483647, steps: [("long", "-6524141474226501150"), ("long", "3243956151158110188"), ("long", "-2027301420726084922"), ("luntil:1099511627776", "639434872074"), ("luntil:10", "9"), ("luntil:4294967296", "1378109101"), ("luntil:4", "2"), ("luntil:9223372036854775807", "5554426290629232555"), ("luntil:2147483648", "1667873037"), ("lrange:-700:701", "-267"), ("lrange:0:1700", "576"), ("lrange:-9223372036854775808:9223372036854775807", "9196985073977795829"), ("lrange:-4611686018427387904:4611686018427387909", "1174489455104525704"), ("lrange:1760000000000:1760000005000", "1760000002852"), ("luntil:3", "2"), ("luntil:8589934592", "250931697"), ("luntil:1", "0")]),
        (seed: 2147483647, steps: [("float", "0x3F257597"), ("float", "0x3E88AC12"), ("float", "0x3E341360"), ("float", "0x3F28B8F7"), ("double", "0x3FEC7BB282A7D0D6"), ("double", "0x3FE28EACC70A4EA8"), ("double", "0x3FE7287E652AABD7"), ("duntil:10.0", "0x4009AB56124BC72C"), ("drange:-1.0:1.0", "0x3FCA2A92B005E3D0"), ("drange:-1.7976931348623157E308:1.7976931348623157E308", "0x7FE1B4DC85AD519B"), ("drange:0.0:1.0E-300", "0x018069F40E649C48"), ("duntil:4.9E-324", "0x0000000000000000"), ("bool", "false"), ("bool", "false"), ("bool", "true"), ("bool", "false"), ("bool", "false"), ("bool", "true")]),
        (seed: 2147483647, steps: [("float", "0x3F257597"), ("until:100", "57"), ("bool", "false"), ("lrange:-700:701", "375"), ("double", "0x3FD53E86B9475662"), ("int", "-515255030"), ("range:-4:5", "3"), ("float", "0x3F25557A"), ("float", "0x3EA4488C"), ("until:3", "1"), ("lrange:0:1700", "1655"), ("bool", "true")]),
        (seed: -2147483648, steps: [("int", "-468773749"), ("int", "-303786953"), ("int", "2109491522"), ("int", "1936655093"), ("bits:0", "0"), ("bits:1", "0"), ("bits:5", "31"), ("bits:16", "6836"), ("bits:31", "296971563"), ("bits:32", "-1930336187"), ("int", "887695797")]),
        (seed: -2147483648, steps: [("until:1", "0"), ("until:2", "1"), ("until:3", "1"), ("until:7", "4"), ("until:10", "7"), ("until:16", "5"), ("until:100", "36"), ("until:1000", "446"), ("until:2147483647", "296971563"), ("until:1073741824", "591157777"), ("range:-5:5", "3"), ("range:2:9", "4"), ("range:-2147483648:2147483647", "993692132"), ("range:-2147483648:0", "-804156954"), ("range:-1000000000:2000000000", "-644910466"), ("range:-4:5", "2"), ("range:1000:9999", "4951"), ("irange:1:5", "4"), ("irange:-2147483648:2147483647", "-1117706785"), ("irange:0:2147483647", "220751662"), ("irange:-2147483648:-1", "-712735236"), ("until:100", "52")]),
        (seed: -2147483648, steps: [("long", "-2013367921482099657"), ("long", "9060197100115919605"), ("long", "3887489469384934078"), ("luntil:1099511627776", "1069894907596"), ("luntil:10", "2"), ("luntil:4294967296", "887695797"), ("luntil:4", "2"), ("luntil:9223372036854775807", "2133937603812100582"), ("luntil:2147483648", "1825028415"), ("lrange:-700:701", "229"), ("lrange:0:1700", "1475"), ("lrange:-9223372036854775808:9223372036854775807", "1896242340524788729"), ("lrange:-4611686018427387904:4611686018427387909", "2362543898476827953"), ("lrange:1760000000000:1760000005000", "1760000003097"), ("luntil:3", "1"), ("luntil:8589934592", "1797304588"), ("luntil:1", "0")]),
        (seed: -2147483648, steps: [("float", "0x3F640F14"), ("float", "0x3F6DE494"), ("float", "0x3EFB7892"), ("float", "0x3EE6DE04"), ("double", "0x3FCAF9918B585854"), ("double", "0x3FEF207778D5A5B6"), ("double", "0x3FC1B36D319E2D08"), ("duntil:10.0", "0x400088DD027102FF"), ("drange:-1.0:1.0", "0xBFE1315D85FDCEC4"), ("drange:-1.7976931348623157E308:1.7976931348623157E308", "0x7FE663DC9D895B6B"), ("drange:0.0:1.0E-300", "0x0176DFC9FB56CF87"), ("duntil:4.9E-324", "0x0000000000000000"), ("bool", "true"), ("bool", "false"), ("bool", "true"), ("bool", "true"), ("bool", "true"), ("bool", "false")]),
        (seed: -2147483648, steps: [("float", "0x3F640F14"), ("until:100", "71"), ("bool", "false"), ("lrange:-700:701", "47"), ("double", "0x3FD6B0B0AF903BBC"), ("int", "448050892"), ("range:-4:5", "-1"), ("float", "0x3F0CF168"), ("float", "0x3E53A4A4"), ("until:3", "0"), ("lrange:0:1700", "1682"), ("bool", "true")]),
        (seed: 4294967296, steps: [("int", "669068263"), ("int", "-1630568617"), ("int", "635679789"), ("int", "1939280705"), ("bits:0", "0"), ("bits:1", "0"), ("bits:5", "15"), ("bits:16", "32605"), ("bits:31", "169451379"), ("bits:32", "-2085760830"), ("int", "2065529352")]),
        (seed: 4294967296, steps: [("until:1", "0"), ("until:2", "1"), ("until:3", "1"), ("until:7", "2"), ("until:10", "6"), ("until:16", "6"), ("until:100", "75"), ("until:1000", "812"), ("until:2147483647", "169451379"), ("until:1073741824", "552301616"), ("range:-5:5", "1"), ("range:2:9", "8"), ("range:-2147483648:2147483647", "-87222721"), ("range:-2147483648:0", "-1450974092"), ("range:-1000000000:2000000000", "1049167313"), ("range:-4:5", "-4"), ("range:1000:9999", "8822"), ("irange:1:5", "2"), ("irange:-2147483648:2147483647", "213921952"), ("irange:0:2147483647", "2029287836"), ("irange:-2147483648:-1", "-730090091"), ("until:100", "78")]),
        (seed: 4294967296, steps: [("long", "2873626306745958231"), ("long", "2730223906422461249"), ("long", "-4976511534055171209"), ("luntil:1099511627776", "521827894440"), ("luntil:10", "7"), ("luntil:4294967296", "2065529352"), ("luntil:4", "1"), ("luntil:9223372036854775807", "9036062670469719156"), ("luntil:2147483648", "1385201660"), ("lrange:-700:701", "-582"), ("lrange:0:1700", "569"), ("lrange:-9223372036854775808:9223372036854775807", "918787787500090168"), ("lrange:-4611686018427387904:4611686018427387909", "4293649285386436087"), ("lrange:1760000000000:1760000005000", "1760000003961"), ("luntil:3", "0"), ("luntil:8589934592", "1361501773"), ("luntil:1", "0")]),
        (seed: 4294967296, steps: [("float", "0x3E1F84AC"), ("float", "0x3F1ECF7F"), ("float", "0x3E178ED0"), ("float", "0x3EE72E26"), ("double", "0x3FE75DFC23000EDB"), ("double", "0x3FDE58B247F5DC4A"), ("double", "0x3FB4333EE0EB7430"), ("duntil:10.0", "0x40133C9B13392FF4"), ("drange:-1.0:1.0", "0x3FEEB34585307C8E"), ("drange:-1.7976931348623157E308:1.7976931348623157E308", "0x7FD2907FE7D120B6"), ("drange:0.0:1.0E-300", "0x01851DA8252FAFE2"), ("duntil:4.9E-324", "0x0000000000000000"), ("bool", "true"), ("bool", "true"), ("bool", "false"), ("bool", "false"), ("bool", "true"), ("bool", "false")]),
        (seed: 4294967296, steps: [("float", "0x3E1F84AC"), ("until:100", "39"), ("bool", "false"), ("lrange:-700:701", "453"), ("double", "0x3FD80076D7962C90"), ("int", "2136851624"), ("range:-4:5", "-4"), ("float", "0x3F03ADD0"), ("float", "0x3EF63AF4"), ("until:3", "1"), ("lrange:0:1700", "956"), ("bool", "true")]),
        (seed: 1760000000000, steps: [("int", "-337619862"), ("int", "2111320207"), ("int", "791028487"), ("int", "-1220119171"), ("bits:0", "0"), ("bits:1", "0"), ("bits:5", "31"), ("bits:16", "16575"), ("bits:31", "2132624067"), ("bits:32", "-196833032"), ("int", "-1074181589")]),
        (seed: 1760000000000, steps: [("until:1", "0"), ("until:2", "0"), ("until:3", "0"), ("until:7", "6"), ("until:10", "1"), ("until:16", "5"), ("until:100", "0"), ("until:1000", "454"), ("until:2147483647", "2132624067"), ("until:1073741824", "1024533566"), ("range:-5:5", "-2"), ("range:2:9", "5"), ("range:-2147483648:2147483647", "-1924281693"), ("range:-2147483648:0", "-1178711452"), ("range:-1000000000:2000000000", "-364901427"), ("range:-4:5", "2"), ("range:1000:9999", "7144"), ("irange:1:5", "4"), ("irange:-2147483648:2147483647", "8675277"), ("irange:0:2147483647", "926744244"), ("irange:-2147483648:-1", "-760115136"), ("until:100", "42")]),
        (seed: 1760000000000, steps: [("long", "-1450066263658712945"), ("long", "3397441480649241981"), ("long", "4178401807651317108"), ("luntil:1099511627776", "1074828102909"), ("luntil:10", "6"), ("luntil:4294967296", "3220785707"), ("luntil:4", "3"), ("luntil:9223372036854775807", "5091008567960291940"), ("luntil:2147483648", "1539890227"), ("lrange:-700:701", "658"), ("lrange:0:1700", "550"), ("lrange:-9223372036854775808:9223372036854775807", "37260032852229481"), ("lrange:-4611686018427387904:4611686018427387909", "832176119544581231"), ("lrange:1760000000000:1760000005000", "1760000004449"), ("luntil:3", "2"), ("luntil:8589934592", "196577531"), ("luntil:1", "0")]),
        (seed: 1760000000000, steps: [("float", "0x3F6BE054"), ("float", "0x3EFBB060"), ("float", "0x3E3C988C"), ("float", "0x3F374675"), ("double", "0x3FCCFE552A3D04AC"), ("double", "0x3FEF5E04C205FA67"), ("double", "0x3FEFC750B7A22487"), ("duntil:10.0", "0x401DFEF399D3D863"), ("drange:-1.0:1.0", "0x3FBA9B9539BE4A60"), ("drange:-1.7976931348623157E308:1.7976931348623157E308", "0x7FDBC8DC3D480176"), ("drange:0.0:1.0E-300", "0x01886003C1E0D4FA"), ("duntil:4.9E-324", "0x0000000000000000"), ("bool", "false"), ("bool", "true"), ("bool", "false"), ("bool", "false"), ("bool", "true"), ("bool", "true")]),
        (seed: 1760000000000, steps: [("float", "0x3F6BE054"), ("until:100", "3"), ("bool", "false"), ("lrange:-700:701", "177"), ("double", "0x3FD47A095FAF0262"), ("int", "1086278909"), ("range:-4:5", "2"), ("float", "0x3F744490"), ("float", "0x3F3FF94A"), ("until:3", "2"), ("lrange:0:1700", "840"), ("bool", "true")]),
        (seed: 1760004855747, steps: [("int", "22617712"), ("int", "764669011"), ("int", "743074983"), ("int", "-1187325702"), ("bits:0", "0"), ("bits:1", "1"), ("bits:5", "12"), ("bits:16", "58263"), ("bits:31", "391555355"), ("bits:32", "82580426"), ("int", "-1283531019")]),
        (seed: 1760004855747, steps: [("until:1", "0"), ("until:2", "0"), ("until:3", "1"), ("until:7", "4"), ("until:10", "9"), ("until:16", "8"), ("until:100", "71"), ("until:1000", "682"), ("until:2147483647", "391555355"), ("until:1073741824", "20645106"), ("range:-5:5", "3"), ("range:2:9", "3"), ("range:-2147483648:2147483647", "256375819"), ("range:-2147483648:0", "-564088886"), ("range:-1000000000:2000000000", "866181002"), ("range:-4:5", "1"), ("range:1000:9999", "7378"), ("irange:1:5", "2"), ("irange:-2147483648:2147483647", "-1935733260"), ("irange:0:2147483647", "1027436693"), ("irange:-2147483648:-1", "-1501738992"), ("until:100", "48")]),
        (seed: 1760004855747, steps: [("long", "97142334115015763"), ("long", "3191482749273430266"), ("long", "890567647324002942"), ("luntil:1099511627776", "429020095668"), ("luntil:10", "1"), ("luntil:4294967296", "3011436277"), ("luntil:4", "0"), ("luntil:9223372036854775807", "550562878481018826"), ("luntil:2147483648", "433090501"), ("lrange:-700:701", "91"), ("lrange:0:1700", "1286"), ("lrange:-9223372036854775808:9223372036854775807", "8825613991582273569"), ("lrange:-4611686018427387904:4611686018427387909", "-1677277497210312687"), ("lrange:1760000000000:1760000005000", "1760000001744"), ("luntil:3", "2"), ("luntil:8589934592", "2084361592"), ("luntil:1", "0")]),
        (seed: 1760004855747, steps: [("float", "0x3BAC8F00"), ("float", "0x3E364FB0"), ("float", "0x3E3129B0"), ("float", "0x3F393AD8"), ("double", "0x3FA8B7DD4599ED30"), ("double", "0x3FD8CE3CAE39724A"), ("double", "0x3FC756A9009D8278"), ("duntil:10.0", "0x401C0BD2D006D142"), ("drange:-1.0:1.0", "0xBFEC2E00F433EA08"), ("drange:-1.7976931348623157E308:1.7976931348623157E308", "0xFFE317C8107C49FB"), ("drange:0.0:1.0E-300", "0x0188A8CE246DFCD4"), ("duntil:4.9E-324", "0x0000000000000000"), ("bool", "false"), ("bool", "true"), ("bool", "true"), ("bool", "true"), ("bool", "false"), ("bool", "false")]),
        (seed: 1760004855747, steps: [("float", "0x3BAC8F00"), ("until:100", "5"), ("bool", "false"), ("lrange:-700:701", "313"), ("double", "0x3FE1667B4B19C795"), ("int", "-476633932"), ("range:-4:5", "1"), ("float", "0x3C9D8260"), ("float", "0x3F337EDE"), ("until:3", "0"), ("lrange:0:1700", "826"), ("bool", "false")]),
        (seed: 1760040272716, steps: [("int", "-515371332"), ("int", "-2073413947"), ("int", "-1515566490"), ("int", "519734602"), ("bits:0", "0"), ("bits:1", "0"), ("bits:5", "15"), ("bits:16", "23600"), ("bits:31", "596521530"), ("bits:32", "102268802"), ("int", "-978499907")]),
        (seed: 1760040272716, steps: [("until:1", "0"), ("until:2", "1"), ("until:3", "2"), ("until:7", "1"), ("until:10", "0"), ("until:16", "0"), ("until:100", "83"), ("until:1000", "576"), ("until:2147483647", "596521530"), ("until:1073741824", "25567200"), ("range:-5:5", "-1"), ("range:2:9", "5"), ("range:-2147483648:2147483647", "1009614626"), ("range:-2147483648:0", "-541208445"), ("range:-1000000000:2000000000", "595564045"), ("range:-4:5", "-2"), ("range:1000:9999", "3500"), ("irange:1:5", "5"), ("irange:-2147483648:2147483647", "861528556"), ("irange:0:2147483647", "1854210119"), ("irange:-2147483648:-1", "-1312925165"), ("until:100", "50")]),
        (seed: 1760040272716, steps: [("long", "-2213503018309372219"), ("long", "-6509308508943776438"), ("long", "-1291618883291572700"), ("luntil:1099511627776", "534122643857"), ("luntil:10", "1"), ("luntil:4294967296", "3316467389"), ("luntil:4", "2"), ("luntil:9223372036854775807", "2168130899575427203"), ("luntil:2147483648", "297782022"), ("lrange:-700:701", "545"), ("lrange:0:1700", "550"), ("lrange:-9223372036854775808:9223372036854775807", "-2519200430005898202"), ("lrange:-4611686018427387904:4611686018427387909", "-450072807055584145"), ("lrange:1760000000000:1760000005000", "1760000004939"), ("luntil:3", "1"), ("luntil:8589934592", "5207003699"), ("luntil:1", "0")]),
        (seed: 1760040272716, steps: [("float", "0x3F61480E"), ("float", "0x3F046A36"), ("float", "0x3F25AA4A"), ("float", "0x3DF7D428"), ("double", "0x3FEDC267E861C0B1"), ("double", "0x3FDF396045C30C18"), ("double", "0x3FD1C719106187F8"), ("duntil:10.0", "0x401EE3130B315D7C"), ("drange:-1.0:1.0", "0xBFE0F4A0340845F0"), ("drange:-1.7976931348623157E308:1.7976931348623157E308", "0xFFE7201A79111BBD"), ("drange:0.0:1.0E-300", "0x01502A514D53CE47"), ("duntil:4.9E-324", "0x0000000000000000"), ("bool", "false"), ("bool", "false"), ("bool", "true"), ("bool", "false"), ("bool", "true"), ("bool", "true")]),
        (seed: 1760040272716, steps: [("float", "0x3F61480E"), ("until:100", "74"), ("bool", "true"), ("lrange:-700:701", "-474"), ("double", "0x3FA8702C3E72C080"), ("int", "1546699153"), ("range:-4:5", "-4"), ("float", "0x3CC30FE0"), ("float", "0x3F45AD46"), ("until:3", "0"), ("lrange:0:1700", "203"), ("bool", "false")]),
        (seed: 1760369498109, steps: [("int", "-1912451465"), ("int", "881415603"), ("int", "-1267024707"), ("int", "1410781279"), ("bits:0", "0"), ("bits:1", "1"), ("bits:5", "20"), ("bits:16", "40932"), ("bits:31", "1908253810"), ("bits:32", "-1182214402"), ("int", "-174773328")]),
        (seed: 1760369498109, steps: [("until:1", "0"), ("until:2", "0"), ("until:3", "0"), ("until:7", "2"), ("until:10", "7"), ("until:16", "9"), ("until:100", "32"), ("until:1000", "847"), ("until:2147483647", "1908253810"), ("until:1073741824", "778188223"), ("range:-5:5", "-1"), ("range:2:9", "3"), ("range:-2147483648:2147483647", "-1115091198"), ("range:-2147483648:0", "-940021345"), ("range:-1000000000:2000000000", "1629628437"), ("range:-4:5", "1"), ("range:1000:9999", "1389"), ("irange:1:5", "1"), ("irange:-2147483648:2147483647", "-142219142"), ("irange:0:2147483647", "353065233"), ("irange:-2147483648:-1", "-2147084499"), ("until:100", "14")]),
        (seed: 1760369498109, steps: [("long", "-8213916496480873037"), ("long", "-5441829678378200993"), ("long", "8410093804060106104"), ("luntil:1099511627776", "702762206942"), ("luntil:10", "7"), ("luntil:4294967296", "4120193968"), ("luntil:4", "1"), ("luntil:9223372036854775807", "6828731922181024159"), ("luntil:2147483648", "814814218"), ("lrange:-700:701", "495"), ("lrange:0:1700", "937"), ("lrange:-9223372036854775808:9223372036854775807", "3032807258180038234"), ("lrange:-4611686018427387904:4611686018427387909", "3046272059013311589"), ("lrange:1760000000000:1760000005000", "1760000003657"), ("luntil:3", "2"), ("luntil:8589934592", "2013547038"), ("luntil:1", "0")]),
        (seed: 1760369498109, steps: [("float", "0x3F0E024E"), ("float", "0x3E522554"), ("float", "0x3F347ABC"), ("float", "0x3EA82DA0"), ("double", "0x3FDD2DA9F96B75D6"), ("double", "0x3FE469BE8CFF2236"), ("double", "0x3FEC6F691DCC46B7"), ("duntil:10.0", "0x40232FA7679EE06F"), ("drange:-1.0:1.0", "0x3FDEC48791FE1A64"), ("drange:-1.7976931348623157E308:1.7976931348623157E308", "0xFFCEDDD7DFF60186"), ("drange:0.0:1.0E-300", "0x0183E5BF53B3A332"), ("duntil:4.9E-324", "0x0000000000000000"), ("bool", "false"), ("bool", "false"), ("bool", "false"), ("bool", "false"), ("bool", "false"), ("bool", "false")]),
        (seed: 1760369498109, steps: [("float", "0x3F0E024E"), ("until:100", "1"), ("bool", "true"), ("lrange:-700:701", "377"), ("double", "0x3FE2D6EBAD1A6FA3"), ("int", "-1612429602"), ("range:-4:5", "-3"), ("float", "0x3F3988D6"), ("float", "0x3F75952B"), ("until:3", "1"), ("lrange:0:1700", "159"), ("bool", "false")]),
    ]
    /// Random(seed: Int) scripts.
    static let randomIntSeedScripts: [(seed: Int, steps: [(String, String)])] = [
        (seed: 0, steps: [("int", "-1934310868"), ("int", "1409199696"), ("int", "-649160781"), ("int", "-1454478562"), ("bits:0", "0"), ("bits:1", "0"), ("bits:5", "0"), ("bits:16", "12384"), ("bits:31", "697865814"), ("bits:32", "-587880378"), ("int", "43427776")]),
        (seed: 0, steps: [("float", "0x3F0CB4C2"), ("float", "0x3EA7FD5C"), ("float", "0x3F594E97"), ("float", "0x3F294E6B"), ("double", "0x3FE5175F217E63DF"), ("double", "0x3F805BFA60C1D1C0"), ("double", "0x3FD4CC4B2DCF5A84"), ("duntil:10.0", "0x3FB9E28DA8311EB0"), ("drange:-1.0:1.0", "0x3FB1B3DD9DF7A340"), ("drange:-1.7976931348623157E308:1.7976931348623157E308", "0x7FD888ED4BB0FFDE"), ("drange:0.0:1.0E-300", "0x01A452ECAC9010E8"), ("duntil:4.9E-324", "0x0000000000000000"), ("bool", "true"), ("bool", "true"), ("bool", "false"), ("bool", "false"), ("bool", "false"), ("bool", "true")]),
        (seed: 1, steps: [("int", "600123930"), ("int", "-1531902544"), ("int", "-527218591"), ("int", "-1598672019"), ("bits:0", "0"), ("bits:1", "0"), ("bits:5", "30"), ("bits:16", "34669"), ("bits:31", "157842260"), ("bits:32", "970147242"), ("int", "1329509210")]),
        (seed: 1, steps: [("float", "0x3E0F14A8"), ("float", "0x3F24B105"), ("float", "0x3F609348"), ("float", "0x3F20B633"), ("double", "0x3FEBF7494A216123"), ("double", "0x3FEEC1D6EC3B69E9"), ("double", "0x3FB2D0F68E74D168"), ("duntil:10.0", "0x4008C39814439DF8"), ("drange:-1.0:1.0", "0x3FE3664524C3965A"), ("drange:-1.7976931348623157E308:1.7976931348623157E308", "0x7FDD16549BB7DDE2"), ("drange:0.0:1.0E-300", "0x01736B3CBDAE714F"), ("duntil:4.9E-324", "0x0000000000000000"), ("bool", "true"), ("bool", "false"), ("bool", "false"), ("bool", "true"), ("bool", "false"), ("bool", "true")]),
        (seed: -1, steps: [("int", "-280203964"), ("int", "-1115932487"), ("int", "-2122700674"), ("int", "1389910083"), ("bits:0", "0"), ("bits:1", "0"), ("bits:5", "12"), ("bits:16", "59869"), ("bits:31", "1959323840"), ("bits:32", "-179223823"), ("int", "1691798198")]),
        (seed: -1, steps: [("float", "0x3F6F4C6D"), ("float", "0x3F3D7C38"), ("float", "0x3F017A28"), ("float", "0x3EA5B0B0"), ("double", "0x3FD4A9A20258323C"), ("double", "0x3FD9A76B2E9DDCAA"), ("double", "0x3FED323A37AA8A17"), ("duntil:10.0", "0x400F831F5A4685C0"), ("drange:-1.0:1.0", "0xBFE60D6E9042C360"), ("drange:-1.7976931348623157E308:1.7976931348623157E308", "0x7FCF4DD1ED71B65C"), ("drange:0.0:1.0E-300", "0x01A01069D3C8082D"), ("duntil:4.9E-324", "0x0000000000000000"), ("bool", "true"), ("bool", "true"), ("bool", "false"), ("bool", "true"), ("bool", "true"), ("bool", "false")]),
        (seed: 12345, steps: [("int", "-984488024"), ("int", "-139740814"), ("int", "-704757440"), ("int", "-2028879536"), ("bits:0", "0"), ("bits:1", "1"), ("bits:5", "26"), ("bits:16", "6218"), ("bits:31", "1399140295"), ("bits:32", "2043183599"), ("int", "1697031951")]),
        (seed: 12345, steps: [("float", "0x3F4551E7"), ("float", "0x3F77ABB9"), ("float", "0x3F55FE41"), ("float", "0x3F0711C1"), ("double", "0x3FE4F45B1F4A4D97"), ("double", "0x3FEA304910C25725"), ("double", "0x3FE4D94BF3CE440F"), ("duntil:10.0", "0x400F9C143619DB00"), ("drange:-1.0:1.0", "0x3FE0DFFD24A6F836"), ("drange:-1.7976931348623157E308:1.7976931348623157E308", "0x7FB495AD3B4BAC48"), ("drange:0.0:1.0E-300", "0x01A2D056220C90D4"), ("duntil:4.9E-324", "0x0000000000000000"), ("bool", "false"), ("bool", "false"), ("bool", "true"), ("bool", "true"), ("bool", "false"), ("bool", "false")]),
        (seed: -2147483648, steps: [("int", "-468773749"), ("int", "-303786953"), ("int", "2109491522"), ("int", "1936655093"), ("bits:0", "0"), ("bits:1", "0"), ("bits:5", "31"), ("bits:16", "6836"), ("bits:31", "296971563"), ("bits:32", "-1930336187"), ("int", "887695797")]),
        (seed: -2147483648, steps: [("float", "0x3F640F14"), ("float", "0x3F6DE494"), ("float", "0x3EFB7892"), ("float", "0x3EE6DE04"), ("double", "0x3FCAF9918B585854"), ("double", "0x3FEF207778D5A5B6"), ("double", "0x3FC1B36D319E2D08"), ("duntil:10.0", "0x400088DD027102FF"), ("drange:-1.0:1.0", "0xBFE1315D85FDCEC4"), ("drange:-1.7976931348623157E308:1.7976931348623157E308", "0x7FE663DC9D895B6B"), ("drange:0.0:1.0E-300", "0x0176DFC9FB56CF87"), ("duntil:4.9E-324", "0x0000000000000000"), ("bool", "true"), ("bool", "false"), ("bool", "true"), ("bool", "true"), ("bool", "true"), ("bool", "false")]),
        (seed: 2147483647, steps: [("int", "-1519020059"), ("int", "1146489314"), ("int", "755292399"), ("int", "-1464272916"), ("bits:0", "0"), ("bits:1", "0"), ("bits:5", "18"), ("bits:16", "57673"), ("bits:31", "1554119062"), ("bits:32", "-1521124622"), ("int", "1378109101")]),
        (seed: 2147483647, steps: [("float", "0x3F257597"), ("float", "0x3E88AC12"), ("float", "0x3E341360"), ("float", "0x3F28B8F7"), ("double", "0x3FEC7BB282A7D0D6"), ("double", "0x3FE28EACC70A4EA8"), ("double", "0x3FE7287E652AABD7"), ("duntil:10.0", "0x4009AB56124BC72C"), ("drange:-1.0:1.0", "0x3FCA2A92B005E3D0"), ("drange:-1.7976931348623157E308:1.7976931348623157E308", "0x7FE1B4DC85AD519B"), ("drange:0.0:1.0E-300", "0x018069F40E649C48"), ("duntil:4.9E-324", "0x0000000000000000"), ("bool", "false"), ("bool", "false"), ("bool", "true"), ("bool", "false"), ("bool", "false"), ("bool", "true")]),
        (seed: 1540483477, steps: [("int", "-1355411244"), ("int", "-1461155895"), ("int", "-1185907530"), ("int", "2045371084"), ("bits:0", "0"), ("bits:1", "1"), ("bits:5", "12"), ("bits:16", "49937"), ("bits:31", "1965642759"), ("bits:32", "1935695265"), ("int", "573227145")]),
        (seed: 1540483477, steps: [("float", "0x3F2F3610"), ("float", "0x3F28E887"), ("float", "0x3F39507C"), ("float", "0x3EF3D3C4"), ("double", "0x3FE6C9564C46AE55"), ("double", "0x3FD98E2D0C3116CE"), ("double", "0x3FED4A55039B02ED"), ("duntil:10.0", "0x3FF55AB86E4335E1"), ("drange:-1.0:1.0", "0x3FCFF7EFBC238470"), ("drange:-1.7976931348623157E308:1.7976931348623157E308", "0x7FEFA7F961BCC075"), ("drange:0.0:1.0E-300", "0x019C14A82F1B3138"), ("duntil:4.9E-324", "0x0000000000000000"), ("bool", "false"), ("bool", "true"), ("bool", "false"), ("bool", "false"), ("bool", "false"), ("bool", "true")]),
    ]
    /// (0 until n).toList().shuffled(Random(seed)) and the next nextInt().
    static let shuffles: [(seed: Int64, n: Int, shuffled: [Int], next: Int32)] = [
        (seed: 0, n: 10, shuffled: [9, 7, 1, 5, 2, 8, 3, 6, 0, 4], next: -587880378),
        (seed: 1, n: 10, shuffled: [1, 4, 0, 6, 2, 8, 9, 7, 3, 5], next: 970147242),
        (seed: 42, n: 10, shuffled: [5, 0, 4, 9, 2, 8, 1, 7, 6, 3], next: 274632774),
        (seed: 31337, n: 10, shuffled: [7, 9, 3, 6, 1, 2, 5, 8, 0, 4], next: 618706223),
        (seed: 1760000000000, n: 10, shuffled: [8, 5, 2, 4, 3, 9, 6, 1, 0, 7], next: -196833032),
        (seed: 7, n: 0, shuffled: [], next: -182312124),
        (seed: 7, n: 1, shuffled: [0], next: -182312124),
        (seed: 7, n: 2, shuffled: [0, 1], next: 11901178),
        (seed: 7, n: 5, shuffled: [4, 2, 3, 0, 1], next: 1560878315),
        (seed: 7, n: 20, shuffled: [11, 2, 9, 4, 13, 3, 0, 8, 7, 16, 19, 14, 1, 12, 10, 5, 18, 15, 17, 6], next: -658841554),
        (seed: 7, n: 52, shuffled: [50, 0, 38, 36, 35, 6, 12, 29, 25, 20, 46, 41, 17, 33, 15, 26, 31, 45, 39, 22, 32, 21, 30, 47, 19, 48, 43, 7, 24, 40, 49, 4, 9, 18, 10, 42, 1, 3, 27, 51, 34, 13, 37, 2, 44, 16, 28, 5, 8, 23, 11, 14], next: 1816352671),
    ]
    /// listOf(10, 20, 30, 40, 50).random(r) six times.
    static let randomPicks: [(seed: Int64, picks: [Int])] = [
        (seed: 99, picks: [30, 20, 30, 50, 50, 40]),
        (seed: 0, picks: [50, 40, 30, 30, 30, 30]),
        (seed: -5, picks: [40, 50, 40, 20, 40, 20]),
    ]
    /// (0 until n).asSequence().shuffled(r).take(k).toList() and the next nextInt().
    static let sequenceShuffles: [(seed: Int64, n: Int, take: Int, taken: [Int], next: Int32)] = [
        (seed: 3, n: 10, take: 3, taken: [0, 6, 7], next: -921540604),
        (seed: 3, n: 5, take: 5, taken: [0, 2, 1, 3, 4], next: -1076052217),
        (seed: 3, n: 4, take: 0, taken: [], next: -2124332895),
        (seed: 3, n: 0, take: 2, taken: [], next: -2124332895),
        (seed: 11, n: 12, take: 4, taken: [5, 7, 3, 11], next: 1238224458),
        (seed: 11, n: 3, take: 10, taken: [2, 1, 0], next: 1123485076),
    ]
    /// (bits, Float.toString on libcore main = JDK 19+ FloatToDecimal, legacy FloatingDecimal of Android <= 15).
    static let floatStrings: [(UInt32, String, String)] = [
        (0x00000000, "0.0", "0.0"),
        (0x80000000, "-0.0", "-0.0"),
        (0x3F800000, "1.0", "1.0"),
        (0xBF800000, "-1.0", "-1.0"),
        (0x3DCCCCCD, "0.1", "0.1"),
        (0x3E4CCCCD, "0.2", "0.2"),
        (0x3E99999A, "0.3", "0.3"),
        (0x3E99999A, "0.3", "0.3"),
        (0x3F8CCCCD, "1.1", "1.1"),
        (0x42C80000, "100.0", "100.0"),
        (0x447A0000, "1000.0", "1000.0"),
        (0x4B189680, "1.0E7", "1.0E7"),
        (0x4B18967F, "9999999.0", "9999999.0"),
        (0x4B189680, "1.0E7", "1.0E7"),
        (0x4B3C614E, "1.2345678E7", "1.2345678E7"),
        (0x4B3C614E, "1.2345678E7", "1.2345678E7"),
        (0x3A83126F, "0.001", "0.001"),
        (0x38D1B717, "1.0E-4", "1.0E-4"),
        (0x3A83126E, "9.999999E-4", "9.999999E-4"),
        (0x3A83126F, "0.001", "0.001"),
        (0x3727C5AC, "1.0E-5", "1.0E-5"),
        (0x7F7FFFFF, "3.4028235E38", "3.4028235E38"),
        (0x00800000, "1.1754944E-38", "1.17549435E-38"),
        (0x00000001, "1.4E-45", "1.4E-45"),
        (0x00000002, "2.8E-45", "2.8E-45"),
        (0x501502F9, "1.0E10", "1.0E10"),
        (0x32ABCC77, "2.0E-8", "2.0E-8"),
        (0x03AA2425, "1.0E-36", "1.0E-36"),
        (0x4C000000, "3.3554432E7", "3.3554432E7"),
        (0x4B800000, "1.6777216E7", "1.6777216E7"),
        (0x4B800000, "1.6777216E7", "1.6777216E7"),
        (0x7FC00000, "NaN", "NaN"),
        (0x7F800000, "Infinity", "Infinity"),
        (0xFF800000, "-Infinity", "-Infinity"),
        (0x40490FDB, "3.1415927", "3.1415927"),
        (0x402DF854, "2.7182817", "2.7182817"),
        (0x3F000000, "0.5", "0.5"),
        (0x3E800000, "0.25", "0.25"),
        (0x3FC00000, "1.5", "1.5"),
        (0x40200000, "2.5", "2.5"),
        (0x449A5000, "1234.5", "1234.5"),
        (0x3BA0902E, "0.0049", "0.0049"),
        (0xC3889333, "-273.15", "-273.15"),
        (0x66FF0C2F, "6.022141E23", "6.022141E23"),
        (0x00000001, "1.4E-45", "1.4E-45"),
        (0x411CCCCD, "9.8", "9.8"),
        (0x3F333333, "0.7", "0.7"),
        (0x408B3333, "4.35", "4.35"),
        (0x3C888889, "0.016666668", "0.016666668"),
        (0x7E800000, "8.507059E37", "8.507059E37"),
        (0x7E967699, "1.0E38", "1.0E38"),
        (0x4EEE6B28, "2.0E9", "2.0E9"),
        (0x4F800000, "4.2949673E9", "4.2949673E9"),
        (0x47F12065, "123456.79", "123456.79"),
        (0x3EAAAAAB, "0.33333334", "0.33333334"),
        (0x3F2AAAAB, "0.6666667", "0.6666667"),
        (0x92A4609C, "-1.0373671E-27", "-1.0373671E-27"),
        (0x6F191219, "4.7373085E28", "4.7373085E28"),
        (0x0B5E9548, "4.2867951E-32", "4.2867951E-32"),
        (0xB64D22F8, "-3.0567735E-6", "-3.0567735E-6"),
        (0xC132C01E, "-11.171904", "-11.171904"),
        (0x259DB1D7, "2.7355668E-16", "2.7355668E-16"),
        (0xAE0D3FAD, "-3.2116244E-11", "-3.2116244E-11"),
        (0x7E28DC7C, "5.611378E37", "5.611378E37"),
        (0xF21BAEAC, "-3.083606E30", "-3.083606E30"),
        (0x97FBF2D4, "-1.6281793E-24", "-1.6281793E-24"),
        (0x4E4249B4, "8.149025E8", "8.1490253E8"),
        (0x296B0019, "5.2180567E-14", "5.2180567E-14"),
        (0x7E6821E9, "7.713924E37", "7.713924E37"),
        (0x520F4F72, "1.538783E11", "1.53878299E11"),
        (0xA0BE4B87, "-3.2237232E-19", "-3.2237232E-19"),
        (0xEF76227C, "-7.6175E28", "-7.6175E28"),
        (0xDAAFA2AA, "-2.4718486E16", "-2.4718486E16"),
        (0x1866FA68, "2.9853226E-24", "2.9853226E-24"),
        (0x75B43DD4, "4.5696653E32", "4.5696653E32"),
        (0x426EA88D, "59.6646", "59.6646"),
        (0x183084ED, "2.2814577E-24", "2.2814577E-24"),
        (0xCECAE9A1, "-1.7021544E9", "-1.70215437E9"),
        (0x2967F4E3, "5.150471E-14", "5.150471E-14"),
        (0xF3B926F4, "-2.933853E31", "-2.933853E31"),
        (0x7E1F2B0A, "5.289268E37", "5.289268E37"),
        (0x014C2B63, "3.750001E-38", "3.750001E-38"),
        (0x61D0B8EA, "4.812809E20", "4.812809E20"),
        (0x4C80B5DF, "6.7481336E7", "6.7481336E7"),
        (0xDAC9C828, "-2.8398272E16", "-2.83982722E16"),
        (0x6C22E9B4, "7.8779846E26", "7.8779846E26"),
        (0x375C8FA0, "1.3146462E-5", "1.3146462E-5"),
        (0x09683D01, "2.7954668E-33", "2.7954668E-33"),
        (0x841155F2, "-1.7084132E-36", "-1.7084132E-36"),
        (0x75DEBFF8, "5.6473803E32", "5.6473803E32"),
        (0xD3A60B0F, "-1.4263002E12", "-1.42630021E12"),
        (0xC935FBDD, "-745405.8", "-745405.8"),
        (0x298FB189, "6.381273E-14", "6.381273E-14"),
        (0x309446DE, "1.0788559E-9", "1.0788559E-9"),
        (0x8BB7B1AE, "-7.075638E-32", "-7.075638E-32"),
        (0x1578D243, "5.0249068E-26", "5.0249068E-26"),
        (0x53CE13BB, "1.7701886E12", "1.77018857E12"),
        (0x5BFCFA7D, "1.4241422E17", "1.42414218E17"),
        (0xD19553AE, "-8.0169255E10", "-8.0169255E10"),
        (0x1E1B0D1B, "8.208342E-21", "8.208342E-21"),
        (0xE26E5875, "-1.0991748E21", "-1.0991748E21"),
        (0xAA2CDEB9, "-1.5353941E-13", "-1.5353941E-13"),
        (0xEB74E194, "-2.9604316E26", "-2.9604316E26"),
        (0xF5CEBB60, "-5.2412772E32", "-5.2412772E32"),
        (0xF25CC976, "-4.3731362E30", "-4.3731362E30"),
        (0x74D385EB, "1.340687E32", "1.340687E32"),
        (0xE3959807, "-5.519039E21", "-5.519039E21"),
        (0x417BCF6F, "15.738143", "15.738143"),
        (0x24476045, "4.323279E-17", "4.323279E-17"),
        (0x48345DC1, "184695.02", "184695.02"),
        (0x633D94EA, "3.497165E21", "3.497165E21"),
        (0x10989082, "6.017608E-29", "6.017608E-29"),
        (0x4DF2B365, "5.0898038E8", "5.08980384E8"),
        (0x755C6661, "2.7939009E32", "2.7939009E32"),
        (0x435329AD, "211.1628", "211.1628"),
        (0xEBD92076, "-5.249804E26", "-5.249804E26"),
        (0xB5D402C6, "-1.5796038E-6", "-1.5796038E-6"),
        (0xECD9B7D4, "-2.10564E27", "-2.10564E27"),
        (0x3E887EE0, "0.26659298", "0.26659298"),
        (0x0B2B19D4, "3.2952833E-32", "3.2952833E-32"),
        (0x42DB177D, "109.545876", "109.545876"),
        (0x489B79A2, "318413.06", "318413.06"),
        (0xE1655D08, "-2.64438E20", "-2.64438E20"),
        (0x4FBE8A0E, "6.393437E9", "6.3934372E9"),
        (0xB1CDEAB7, "-5.9929692E-9", "-5.9929692E-9"),
        (0x5CE730B8, "5.205943E17", "5.20594292E17"),
        (0x2CE42EB6, "6.4853357E-12", "6.4853357E-12"),
        (0xD32DCC08, "-7.464524E11", "-7.4645242E11"),
        (0x414347EB, "12.205058", "12.205058"),
        (0x3FBA8792, "1.4572623", "1.4572623"),
        (0x4E148FD4, "6.231135E8", "6.2311347E8"),
        (0x1DEA06DA, "6.194637E-21", "6.194637E-21"),
        (0x2C68DE4E, "3.3092587E-12", "3.3092587E-12"),
        (0x31BEF495, "5.5575335E-9", "5.5575335E-9"),
        (0xD186FE42, "-7.247392E10", "-7.2473919E10"),
        (0xED2A54D4, "-3.2946877E27", "-3.2946877E27"),
        (0x3E94758C, "0.2899593", "0.2899593"),
        (0x9666E2BC, "-1.8650797E-25", "-1.8650797E-25"),
        (0x296A7FA1, "5.2069138E-14", "5.2069138E-14"),
        (0xA7F7D6C1, "-6.878911E-15", "-6.878911E-15"),
        (0x3D6739B4, "0.056451514", "0.056451514"),
        (0x78224077, "1.3163431E34", "1.3163431E34"),
        (0xA27E506D, "-3.4465996E-18", "-3.4465996E-18"),
        (0x8BD13770, "-8.0587285E-32", "-8.0587285E-32"),
        (0x88455273, "-5.937945E-34", "-5.937945E-34"),
        (0x5C1298CF, "1.6505345E17", "1.65053446E17"),
        (0xBB86F051, "-0.0041180034", "-0.0041180034"),
        (0x4804636F, "135565.73", "135565.73"),
        (0x39533984, "2.0143954E-4", "2.0143954E-4"),
        (0x34851ACD, "2.479268E-7", "2.479268E-7"),
        (0x8E171FB6, "-1.8627455E-30", "-1.8627455E-30"),
        (0x4B857919, "1.7494578E7", "1.7494578E7"),
        (0x214D8467, "6.9631935E-19", "6.9631935E-19"),
        (0x84FB331C, "-5.9056753E-36", "-5.9056753E-36"),
        (0xBB72A29C, "-0.0037023192", "-0.0037023192"),
        (0xCFF634D3, "-8.261314E9", "-8.261314E9"),
        (0xEBA71550, "-4.039825E26", "-4.039825E26"),
        (0x9BF09BED, "-3.9805434E-22", "-3.9805434E-22"),
        (0x5659DCAD, "5.9885455E13", "5.9885455E13"),
        (0x8E015D92, "-1.594553E-30", "-1.594553E-30"),
        (0x8EA4E762, "-4.0651935E-30", "-4.0651935E-30"),
        (0xA018071A, "-1.287725E-19", "-1.287725E-19"),
        (0x17EA9A8F, "1.5160912E-24", "1.5160912E-24"),
        (0xA761F59F, "-3.1358174E-15", "-3.1358174E-15"),
        (0x52EDEA1C, "5.1091748E11", "5.10917476E11"),
        (0xEEB5C68E, "-2.8128412E28", "-2.8128412E28"),
        (0xF3B39C79, "-2.8460534E31", "-2.8460534E31"),
        (0x5A26339E, "1.16954E16", "1.16954E16"),
        (0x5A78A013, "1.7495449E16", "1.74954494E16"),
        (0x715216E3, "1.0403123E30", "1.0403123E30"),
        (0xCADDB608, "-7265028.0", "-7265028.0"),
        (0x6B3A87CC, "2.2550149E26", "2.2550149E26"),
        (0xB72774E1, "-9.981189E-6", "-9.981189E-6"),
        (0x8872F04C, "-7.3106694E-34", "-7.3106694E-34"),
        (0x99269753, "-8.6125585E-24", "-8.6125585E-24"),
        (0x54493187, "3.4564774E12", "3.45647743E12"),
        (0x20FFFE5D, "4.3367004E-19", "4.3367004E-19"),
        (0x79A781B4, "1.0871803E35", "1.0871803E35"),
        (0x5D96933C, "1.3562602E18", "1.35626024E18"),
        (0x56BF2913, "1.0509157E14", "1.05091567E14"),
        (0xF1F89D0B, "-2.4621483E30", "-2.4621483E30"),
        (0xE72DBA27, "-8.204033E23", "-8.204033E23"),
        (0x259BF709, "2.7055611E-16", "2.7055611E-16"),
        (0xDB8F619A, "-8.071647E16", "-8.0716471E16"),
        (0xAD1B2FD6, "-8.821352E-12", "-8.821352E-12"),
        (0x491C8471, "641095.06", "641095.06"),
        (0xC8CBC732, "-417337.56", "-417337.56"),
        (0x7959A774, "7.06328E34", "7.06328E34"),
        (0x6772CEFC, "1.1466309E24", "1.1466309E24"),
        (0x21839904, "8.917408E-19", "8.917408E-19"),
        (0xE730F57C, "-8.356649E23", "-8.356649E23"),
        (0x992A9EA9, "-8.820835E-24", "-8.820835E-24"),
        (0x8625C249, "-3.117579E-35", "-3.117579E-35"),
        (0x509C0A1E, "2.094327E10", "2.09432699E10"),
        (0xC9106446, "-591428.4", "-591428.4"),
        (0xC15EA5B3, "-13.915454", "-13.915454"),
        (0x7D7C2687, "2.0947844E37", "2.0947844E37"),
        (0x8232EE2B, "-1.3145726E-37", "-1.3145726E-37"),
        (0x96994B22, "-2.4765899E-25", "-2.4765899E-25"),
        (0xD689A087, "-7.566128E13", "-7.5661276E13"),
        (0x53A6F634, "1.4341903E12", "1.43419035E12"),
        (0xCC29CC67, "-4.4511644E7", "-4.4511644E7"),
        (0x955ED0A7, "-4.499714E-26", "-4.499714E-26"),
        (0x2FE1EFD6, "4.1097675E-10", "4.1097675E-10"),
        (0x57226975, "1.7857382E14", "1.78573818E14"),
        (0xC57EAFC7, "-4074.986", "-4074.986"),
        (0x59F0ED84, "8.476893E15", "8.4768932E15"),
        (0xBFCD1890, "-1.6023121", "-1.6023121"),
        (0xA6C9E14B, "-1.4008243E-15", "-1.4008243E-15"),
        (0x48080419, "139280.39", "139280.39"),
        (0x22B7ECD8, "4.9853017E-18", "4.9853017E-18"),
        (0x1E10DFA9, "7.669548E-21", "7.669548E-21"),
        (0x3862D203, "5.4078188E-5", "5.4078188E-5"),
        (0xC32EA169, "-174.63051", "-174.63051"),
        (0x6F971DC1, "9.353641E28", "9.353641E28"),
        (0x5013DE1E, "9.92323E9", "9.9232297E9"),
        (0x0CC760F3, "3.0719154E-31", "3.0719154E-31"),
        (0x35B2A9A7, "1.3311409E-6", "1.3311409E-6"),
        (0xC5108A32, "-2312.6372", "-2312.6372"),
        (0x58C4D13A, "1.7312232E15", "1.7312232E15"),
        (0x3E30A962, "0.17252114", "0.17252114"),
        (0x262E1C86, "6.0407033E-16", "6.0407033E-16"),
        (0xDAECC70A, "-3.332347E16", "-3.33234701E16"),
        (0x05702B15, "1.1292659E-35", "1.1292659E-35"),
        (0xC8ABDCC7, "-351974.22", "-351974.22"),
        (0xFFD245A6, "NaN", "NaN"),
        (0x0B073161, "2.6037203E-32", "2.6037203E-32"),
        (0xFB3FA75D, "-9.951232E35", "-9.951232E35"),
        (0x05C4B236, "1.8497216E-35", "1.8497216E-35"),
        (0x310B68F4, "2.0286821E-9", "2.0286821E-9"),
        (0x0E102D24, "1.7771105E-30", "1.7771105E-30"),
        (0xA297E858, "-4.1174636E-18", "-4.1174636E-18"),
        (0x3622D917, "2.4266244E-6", "2.4266244E-6"),
        (0x0E885151, "3.3604893E-30", "3.3604893E-30"),
        (0x271C38E3, "2.1680187E-15", "2.1680187E-15"),
        (0x5E446028, "3.5375885E18", "3.5375885E18"),
        (0x757F6318, "3.237416E32", "3.237416E32"),
        (0x74D9A571, "1.379497E32", "1.379497E32"),
        (0x14EFEAE9, "2.4225489E-26", "2.4225489E-26"),
        (0x34A20A51, "3.0182358E-7", "3.0182358E-7"),
        (0xA2325964, "-2.4170821E-18", "-2.4170821E-18"),
        (0x37B72705, "2.183347E-5", "2.183347E-5"),
        (0x16662B8D, "1.8592994E-25", "1.8592994E-25"),
        (0x24FDB978, "1.10035456E-16", "1.10035456E-16"),
        (0x18E7F114, "5.9955527E-24", "5.9955527E-24"),
        (0xCE37401C, "-7.68608E8", "-7.68608E8"),
        (0x374F40C7, "1.2353244E-5", "1.2353244E-5"),
        (0x4B62FD6D, "1.4876013E7", "1.4876013E7"),
        (0x5A1012E6, "1.0138294E16", "1.01382939E16"),
        (0x292782C6, "3.7194877E-14", "3.7194877E-14"),
        (0xF9FC7F05, "-1.6387938E35", "-1.6387938E35"),
        (0x6D64E56B, "4.4274957E27", "4.4274957E27"),
        (0x68922A2C, "5.5219475E24", "5.5219475E24"),
        (0xF27AFEFA, "-4.971488E30", "-4.971488E30"),
        (0x6095B33F, "8.629628E19", "8.629628E19"),
        (0xD33A229E, "-7.994447E11", "-7.994447E11"),
        (0xCB7A6F06, "-1.6412422E7", "-1.6412422E7"),
        (0x74AD92B9, "1.1001504E32", "1.1001504E32"),
        (0xC5929A48, "-4691.285", "-4691.285"),
        (0x6E1A4EE4, "1.1939016E28", "1.1939016E28"),
        (0xE5F51FD3, "-1.44695855E23", "-1.44695855E23"),
        (0x55499872, "1.3853537E13", "1.38535366E13"),
        (0xDD83F967, "-1.1887182E18", "-1.18871817E18"),
        (0x47625BD7, "57947.84", "57947.84"),
        (0xD53F5DE4, "-1.3150624E13", "-1.31506236E13"),
        (0x08AF97A8, "1.0568084E-33", "1.0568084E-33"),
        (0x7AFD2C26, "6.5727327E35", "6.5727327E35"),
        (0x57E26E0B, "4.9792452E14", "4.97924518E14"),
        (0x2A7CA172, "2.2438109E-13", "2.2438109E-13"),
        (0x3515DBD1, "5.58267E-7", "5.58267E-7"),
        (0x29283B69, "3.7355024E-14", "3.7355024E-14"),
        (0x0417A894, "1.7827372E-36", "1.7827372E-36"),
        (0xD1DAF8D2, "-1.1755967E11", "-1.17559673E11"),
        (0x09B01581, "4.239068E-33", "4.239068E-33"),
        (0xA79BD1C1, "-4.3248558E-15", "-4.3248558E-15"),
        (0x2538ACCA, "1.6017999E-16", "1.6017999E-16"),
        (0xE85F86E6, "-4.2223047E24", "-4.2223047E24"),
        (0x2B4D69C7, "7.2977426E-13", "7.2977426E-13"),
        (0x93ABA102, "-4.3325235E-27", "-4.3325235E-27"),
        (0x5823D24F, "7.2049466E14", "7.2049466E14"),
        (0x7957F4D6, "7.0081855E34", "7.0081855E34"),
        (0x33BD93D7, "8.82789E-8", "8.82789E-8"),
        (0xBDE10D12, "-0.10988821", "-0.10988821"),
        (0x1EAA5B51, "1.8037218E-20", "1.8037218E-20"),
        (0x6304CB00, "2.449598E21", "2.449598E21"),
        (0xB333FCE9, "-4.1906706E-8", "-4.1906706E-8"),
        (0x86D33003, "-7.9439925E-35", "-7.9439925E-35"),
        (0x95A4290C, "-6.630383E-26", "-6.630383E-26"),
        (0x72DBE52C, "8.7109464E30", "8.7109464E30"),
        (0x24E9EE5F, "1.0145146E-16", "1.0145146E-16"),
        (0x32728B64, "1.4117948E-8", "1.4117948E-8"),
        (0x3EEBB492, "0.46036202", "0.46036202"),
        (0x14017604, "6.53611E-27", "6.53611E-27"),
        (0xB8AF422D, "-8.3569765E-5", "-8.3569765E-5"),
        (0x0D4DFAD4, "6.3472426E-31", "6.3472426E-31"),
        (0xCA1A4FCE, "-2528243.5", "-2528243.5"),
        (0x51894DC2, "7.3714385E10", "7.3714385E10"),
        (0x342B3575, "1.5945064E-7", "1.5945064E-7"),
        (0xF99BBBD7, "-1.0107698E35", "-1.0107698E35"),
        (0x4DD8F2C5, "4.549736E8", "4.549736E8"),
        (0x08F9582A, "1.500687E-33", "1.500687E-33"),
        (0x66854170, "3.1464093E23", "3.1464093E23"),
        (0x0B2A9EEC, "3.286037E-32", "3.286037E-32"),
        (0xF61A191F, "-7.8137034E32", "-7.8137034E32"),
        (0xC3A185BB, "-323.04477", "-323.04477"),
        (0xC2481E95, "-50.029865", "-50.029865"),
        (0xC43D5B2E, "-757.4247", "-757.4247"),
        (0xC1876360, "-16.923523", "-16.923523"),
        (0xC46E6DEF, "-953.7177", "-953.7177"),
        (0xC447970E, "-798.3602", "-798.3602"),
        (0xC3DE7106, "-444.883", "-444.883"),
        (0x43253C60, "165.23584", "165.23584"),
        (0x4456F80E, "859.87585", "859.87585"),
        (0xC3E7A8A0, "-463.31738", "-463.31738"),
        (0x43D752C8, "430.64673", "430.64673"),
        (0x43163C60, "150.23584", "150.23584"),
        (0x43701C88, "240.11145", "240.11145"),
        (0x4330DF00, "176.8711", "176.8711"),
        (0x44742F48, "976.7388", "976.7388"),
        (0xC46D2FED, "-948.74884", "-948.74884"),
        (0xC3D3BBA0, "-423.46582", "-423.46582"),
        (0x438E4F88, "284.62134", "284.62134"),
        (0xC3A39DAA, "-327.23175", "-327.23175"),
        (0xC4380018, "-736.00146", "-736.00146"),
        (0xC3D33598, "-422.4187", "-422.4187"),
        (0xC39B66FA, "-310.8045", "-310.8045"),
        (0xC4125E95, "-585.47784", "-585.47784"),
        (0x445B8194, "878.02466", "878.02466"),
        (0x443315FC, "716.3435", "716.3435"),
        (0x4455C36C, "855.05347", "855.05347"),
        (0x42EE3540, "119.104004", "119.104004"),
        (0xC40BFDCE, "-559.9657", "-559.9657"),
        (0x44473760, "796.86523", "796.86523"),
        (0xC441647C, "-773.57007", "-773.57007"),
        (0x40A9D580, "5.307312", "5.307312"),
        (0xC46EBD26, "-954.95544", "-954.95544"),
        (0xC3CFDB08, "-415.71118", "-415.71118"),
        (0x43CF4944, "414.5724", "414.5724"),
        (0x43E40708, "456.05493", "456.05493"),
        (0x4449215C, "804.52124", "804.52124"),
        (0xC3D3CC82, "-423.59772", "-423.59772"),
        (0x436626F0, "230.1521", "230.1521"),
        (0xC452981C, "-842.3767", "-842.3767"),
        (0x43C422DC, "392.27234", "392.27234"),
        (0xC423CA98, "-655.1655", "-655.1655"),
        (0xC45A072E, "-872.1122", "-872.1122"),
        (0xC355C8D4, "-213.78448", "-213.78448"),
        (0xC3348DC4, "-180.55377", "-180.55377"),
        (0xC3FB0D2E, "-502.10297", "-502.10297"),
        (0x43C69A8C, "397.2074", "397.2074"),
        (0xC330B984, "-176.72467", "-176.72467"),
        (0xC463236C, "-908.55347", "-908.55347"),
        (0x442932D4, "676.7942", "676.7942"),
        (0xC30F1520, "-143.08252", "-143.08252"),
        (0xC386DDF4, "-269.734", "-269.734"),
        (0xC3846AB2, "-264.83356", "-264.83356"),
        (0x43E6DE74, "461.7379", "461.7379"),
        (0xC4599511, "-870.32916", "-870.32916"),
        (0x43E69DC8, "461.23267", "461.23267"),
        (0xC44FBB72, "-830.92883", "-830.92883"),
        (0xC4138B4F, "-590.1767", "-590.1767"),
        (0xC42EBA72, "-698.9132", "-698.9132"),
        (0xC3DF537A, "-446.65216", "-446.65216"),
        (0xC304EE7C, "-132.93158", "-132.93158"),
        (0xC421822F, "-646.0341", "-646.0341"),
        (0xC4461D3A, "-792.45667", "-792.45667"),
        (0x43C00830, "384.06396", "384.06396"),
        (0x441A2DF0, "616.7178", "616.7178"),
        (0xC3AF29BC, "-350.32605", "-350.32605"),
        (0xC42881D1, "-674.0284", "-674.0284"),
        (0x4453BF70, "846.9912", "846.9912"),
        (0x4448578E, "801.36804", "801.36804"),
        (0x438108A4, "258.0675", "258.0675"),
        (0xC3BE1AE2, "-380.21002", "-380.21002"),
        (0x4277BAC0, "61.932373", "61.932373"),
        (0x43F1DC2C, "483.7201", "483.7201"),
        (0x4447EFD2, "799.7472", "799.7472"),
        (0x43B8FED0, "369.99072", "369.99072"),
        (0xC32152B4, "-161.32306", "-161.32306"),
        (0xC3C51A50, "-394.20557", "-394.20557"),
        (0x439BC0F4, "311.50745", "311.50745"),
        (0xC412B5F4, "-586.843", "-586.843"),
        (0x44241B5A, "656.42737", "656.42737"),
        (0x43AEA5D4, "349.29553", "349.29553"),
        (0x42C6B950, "99.36194", "99.36194"),
        (0x41BF7D40, "23.936157", "23.936157"),
        (0xC3755EB4, "-245.36993", "-245.36993"),
        (0x442386DC, "654.1072", "654.1072"),
        (0xC40F7C78, "-573.9448", "-573.9448"),
        (0x43CA4408, "404.5315", "404.5315"),
        (0x440D91E0, "566.2793", "566.2793"),
        (0xC4581ACD, "-864.41876", "-864.41876"),
        (0xC32F71D8, "-175.4447", "-175.4447"),
        (0xC45592A9, "-854.29156", "-854.29156"),
        (0x444EDD64, "827.4592", "827.4592"),
        (0xC366E744, "-230.90338", "-230.90338"),
        (0xC3EEB2F2, "-477.398", "-477.398"),
        (0xC3AE484A, "-348.56476", "-348.56476"),
        (0x42B28590, "89.260864", "89.260864"),
        (0xC4227E86, "-649.9769", "-649.9769"),
        (0x43071E08, "135.11731", "135.11731"),
        (0xC4475342, "-797.3009", "-797.3009"),
        (0xC3F09D28, "-481.22778", "-481.22778"),
        (0x423BAF20, "46.92102", "46.92102"),
        (0xC3A25920, "-324.6963", "-324.6963"),
        (0x442BA4CC, "686.57495", "686.57495"),
        (0x43DBAD9C, "439.35632", "439.35632"),
        (0xC3E87E8A, "-464.9886", "-464.9886"),
        (0x442F7D1A, "701.9547", "701.9547"),
        (0xC29250C8, "-73.157776", "-73.157776"),
        (0xC42A85AE, "-682.08875", "-682.08875"),
        (0x446C95AE, "946.33875", "946.33875"),
        (0xC3BFBC4E, "-383.47113", "-383.47113"),
        (0xC397E6FE, "-303.80463", "-303.80463"),
        (0x4398C450, "305.5337", "305.5337"),
        (0xC2358EA0, "-45.389282", "-45.389282"),
        (0x4431F120, "711.7676", "711.7676"),
        (0xC3319014, "-177.5628", "-177.5628"),
        (0xC465A1F9, "-918.5308", "-918.5308"),
        (0x411985C0, "9.595154", "9.595154"),
        (0xC4103189, "-576.774", "-576.774"),
        (0xC46B6BFE, "-941.6874", "-941.6874"),
        (0xC2CB8AD0, "-101.77112", "-101.77112"),
        (0x43B55714, "362.6803", "362.6803"),
        (0xC3BD4AC2, "-378.58405", "-378.58405"),
        (0xC3CFCA6A, "-415.58136", "-415.58136"),
        (0x441E2C29, "632.69", "632.69"),
        (0x441428F6, "592.64", "592.64"),
        (0x444528F6, "788.64", "788.64"),
        (0x42EA3852, "117.11", "117.11"),
        (0x4403E99A, "527.65", "527.65"),
        (0x4304D70A, "132.84", "132.84"),
        (0x44729666, "970.35", "970.35"),
        (0x440718F6, "540.39", "540.39"),
        (0x43F24000, "484.5", "484.5"),
        (0x43D9570A, "434.68", "434.68"),
        (0x4426151F, "664.33", "664.33"),
        (0x44294A3D, "677.16", "677.16"),
        (0x4413EB85, "591.68", "591.68"),
        (0x42C96B85, "100.71", "100.71"),
        (0x43E08F5C, "449.12", "449.12"),
        (0x445B928F, "878.29", "878.29"),
        (0x43D16A3D, "418.83", "418.83"),
        (0x44258000, "662.0", "662.0"),
        (0x4458CC29, "867.19", "867.19"),
        (0x420828F6, "34.04", "34.04"),
        (0x4165C28F, "14.36", "14.36"),
        (0x438C747B, "280.91", "280.91"),
        (0x4474A148, "978.52", "978.52"),
        (0x43F4E000, "489.75", "489.75"),
        (0x446263D7, "905.56", "905.56"),
        (0x437B4000, "251.25", "251.25"),
        (0x44517E14, "837.97", "837.97"),
        (0x444981EC, "806.03", "806.03"),
        (0x446E9666, "954.35", "954.35"),
        (0x4417947B, "606.32", "606.32"),
        (0x428423D7, "66.07", "66.07"),
        (0x43E53D71, "458.48", "458.48"),
        (0x44233148, "652.77", "652.77"),
        (0x443D2C29, "756.69", "756.69"),
        (0x4370B333, "240.7", "240.7"),
        (0x44650EB8, "916.23", "916.23"),
        (0x44109B85, "578.43", "578.43"),
        (0x42AE0000, "87.0", "87.0"),
        (0x444B5CCD, "813.45", "813.45"),
        (0x4423A852, "654.63", "654.63"),
        (0x40CD1EB8, "6.41", "6.41"),
        (0x4420999A, "642.4", "642.4"),
        (0x44253E14, "660.97", "660.97"),
        (0x4220EB85, "40.23", "40.23"),
        (0x43D40148, "424.01", "424.01"),
        (0x4460C666, "899.1", "899.1"),
        (0x42C6851F, "99.26", "99.26"),
        (0x442E7F5C, "697.99", "697.99"),
        (0x436E999A, "238.6", "238.6"),
        (0x44159666, "598.35", "598.35"),
        (0x440CD5C3, "563.34", "563.34"),
        (0x4239E148, "46.47", "46.47"),
        (0x4442999A, "778.4", "778.4"),
        (0x439BF1EC, "311.89", "311.89"),
        (0x43501C29, "208.11", "208.11"),
        (0x42BD23D7, "94.57", "94.57"),
        (0x41C87AE1, "25.06", "25.06"),
        (0x440BD852, "559.38", "559.38"),
        (0x434C0000, "204.0", "204.0"),
        (0x43A64000, "332.5", "332.5"),
    ]
    /// (bits, Double.toString on Android = legacy FloatingDecimal, JDK 19+ DoubleToDecimal).
    static let doubleStrings: [(UInt64, String, String)] = [
        (0x0000000000000000, "0.0", "0.0"),
        (0x8000000000000000, "-0.0", "-0.0"),
        (0x3FF0000000000000, "1.0", "1.0"),
        (0xBFF0000000000000, "-1.0", "-1.0"),
        (0x3FB999999999999A, "0.1", "0.1"),
        (0x3FC999999999999A, "0.2", "0.2"),
        (0x3FD3333333333333, "0.3", "0.3"),
        (0x3FD3333333333334, "0.30000000000000004", "0.30000000000000004"),
        (0x3FF199999999999A, "1.1", "1.1"),
        (0x4059000000000000, "100.0", "100.0"),
        (0x416312D000000000, "1.0E7", "1.0E7"),
        (0x416312CFFFF7CED9, "9999999.999", "9999999.999"),
        (0x416312D000000000, "1.0E7", "1.0E7"),
        (0x41678C29C0000000, "1.2345678E7", "1.2345678E7"),
        (0x3F50624DD2F1A9FC, "0.001", "0.001"),
        (0x3F1A36E2EB1C432D, "1.0E-4", "1.0E-4"),
        (0x3F50624DD2F1A9FC, "0.001", "0.001"),
        (0x3EE4F8B588E368F1, "1.0E-5", "1.0E-5"),
        (0x7FEFFFFFFFFFFFFF, "1.7976931348623157E308", "1.7976931348623157E308"),
        (0x0010000000000000, "2.2250738585072014E-308", "2.2250738585072014E-308"),
        (0x0000000000000001, "4.9E-324", "4.9E-324"),
        (0x44C52D02C7E14AF6, "1.9999999999999998E23", "2.0E23"),
        (0x44B52D02C7E14AF6, "9.999999999999999E22", "1.0E23"),
        (0x447C7E83209E90B2, "8.409999999999999E21", "8.41E21"),
        (0x438F67EA69ED3795, "2.82879384806159008E17", "2.82879384806159E17"),
        (0x00000000016E3600, "1.18575755E-316", "1.18575755E-316"),
        (0x4340000000000000, "9.007199254740992E15", "9.007199254740992E15"),
        (0x4340000000000000, "9.007199254740992E15", "9.007199254740992E15"),
        (0x7FF8000000000000, "NaN", "NaN"),
        (0x7FF0000000000000, "Infinity", "Infinity"),
        (0xFFF0000000000000, "-Infinity", "-Infinity"),
        (0x400921FB54442D18, "3.141592653589793", "3.141592653589793"),
        (0x4005BF0A8B145769, "2.718281828459045", "2.718281828459045"),
        (0x3FE0000000000000, "0.5", "0.5"),
        (0x3FF8000000000000, "1.5", "1.5"),
        (0x4004000000000000, "2.5", "2.5"),
        (0x3FD5555555555555, "0.3333333333333333", "0.3333333333333333"),
        (0x3FE5555555555555, "0.6666666666666666", "0.6666666666666666"),
        (0x40934A456D5CFAAD, "1234.5678", "1234.5678"),
        (0x0000000000000001, "4.9E-324", "4.9E-324"),
        (0x7E37E43C8800759C, "1.0E300", "1.0E300"),
        (0x01A56E1FC2F8F359, "1.0E-300", "1.0E-300"),
        (0x4011666666666666, "4.35", "4.35"),
        (0x3F91111111111111, "0.016666666666666666", "0.016666666666666666"),
        (0x7FEFFFFFFFFFFFFF, "1.7976931348623157E308", "1.7976931348623157E308"),
        (0x4000000000000000, "2.0", "2.0"),
        (0x4008000000000000, "3.0", "3.0"),
        (0x4029000000000000, "12.5", "12.5"),
        (0x3F04F8B588E368F1, "4.0E-5", "4.0E-5"),
        (0x419D6F3454000000, "1.23456789E8", "1.23456789E8"),
        (0x430C6BF526340000, "1.0E15", "1.0E15"),
        (0x4341C37937E08000, "1.0E16", "1.0E16"),
        (0x4376345785D8A000, "1.0E17", "1.0E17"),
        (0x43ABC16D674EC800, "1.0E18", "1.0E18"),
        (0x43E0000000000000, "9.223372036854776E18", "9.223372036854776E18"),
        (0x43E158E460913D00, "1.0E19", "1.0E19"),
        (0xC3D5CF54073F0B4C, "-6.2862687402992067E18", "-6.286268740299207E18"),
        (0x43A05F35D63DD86A, "5.8986041083561293E17", "5.898604108356129E17"),
        (0x4365FE3C3D5A15E6, "4.9524073533845296E16", "4.95240735338453E16"),
        (0x3FD3333333333334, "0.30000000000000004", "0.30000000000000004"),
        (0x3E7AD7F29ABCAF48, "1.0E-7", "1.0E-7"),
        (0x3F46F0068DB8BAC7, "7.0E-4", "7.0E-4"),
        (0xFE2B9A837C2A151A, "-5.776847961045437E299", "-5.776847961045437E299"),
        (0x69894E302B3B9EA6, "2.4212560927400138E200", "2.4212560927400138E200"),
        (0x0EB115CA5852CE9E, "6.55935954283789E-238", "6.55935954283789E-238"),
        (0x393DE504A3AAE90C, "5.7574909245351255E-33", "5.7574909245351255E-33"),
        (0xB9005605661F3823, "-3.932753732588398E-34", "-3.932753732588398E-34"),
        (0xFE3A3F1A4E648538, "-1.0985681821428573E300", "-1.0985681821428573E300"),
        (0x0634615A38B1B5E0, "8.982024439983707E-279", "8.982024439983707E-279"),
        (0xF8A0EBD972C73147, "-1.1442461758757135E273", "-1.1442461758757135E273"),
        (0x0B2FA892F308F233, "8.433811869125093E-255", "8.433811869125093E-255"),
        (0x6501834C9060045A, "3.54833971482541E178", "3.54833971482541E178"),
        (0xAE1B87EC88782FE9, "-1.3839566977194593E-86", "-1.3839566977194593E-86"),
        (0xD82CC51C2CFAD478, "-5.667970942850421E116", "-5.667970942850421E116"),
        (0xC51E81306ADBFCBC, "-9.219463252117617E24", "-9.219463252117617E24"),
        (0xCDB732B318B896B2, "-2.443039312429795E66", "-2.443039312429795E66"),
        (0x077382FEB509081C, "9.016936790995068E-273", "9.016936790995068E-273"),
        (0x42CE98C183691D87, "6.7282860954171055E13", "6.7282860954171055E13"),
        (0x01DDD171238B2232, "1.1131271335289502E-299", "1.1131271335289502E-299"),
        (0xC85A3BEAEA57D98A, "-3.570794296881852E40", "-3.570794296881852E40"),
        (0x1B1A63DF2AA6A721, "4.070277380821041E-178", "4.070277380821041E-178"),
        (0x02A49CB536918041, "6.303436127801651E-296", "6.303436127801651E-296"),
        (0x9DA8CBFEFEEEDA8E, "-8.410253419215468E-166", "-8.410253419215468E-166"),
        (0x3D4906C643A2BD50, "1.778237132415677E-13", "1.778237132415677E-13"),
        (0xEF52FA3109E7F762, "-1.7982555124126433E228", "-1.7982555124126433E228"),
        (0x2F0E5F50C42E51D7, "5.002985534873684E-82", "5.002985534873684E-82"),
        (0x6D7C73189E53F7CE, "2.5106891156125117E219", "2.5106891156125117E219"),
        (0x95FBE6CD06BB4617, "-8.899211113419051E-203", "-8.899211113419051E-203"),
        (0x74B6CA6CAC35598F, "1.6709152275218127E254", "1.6709152275218127E254"),
        (0x3F8BE1E75002115B, "0.01361447060504222", "0.01361447060504222"),
        (0xA3A2770F13836272, "-4.961843122852781E-137", "-4.961843122852781E-137"),
        (0xD6AB5DB85309DC15, "-3.2135218326315016E109", "-3.2135218326315016E109"),
        (0x7A00545E2A3FA91A, "4.631487764480633E279", "4.631487764480633E279"),
        (0x6075833A20D54046, "4.614990168367661E156", "4.614990168367661E156"),
        (0xAE4964C83F54E601, "-1.0212143199256462E-85", "-1.0212143199256462E-85"),
        (0x4C8C2DF7BB702C23, "5.660351149091493E60", "5.660351149091493E60"),
        (0x6B67A9A2C3A350BC, "2.4310293226606015E209", "2.4310293226606015E209"),
        (0xFDD6BA043126CAF5, "-1.4863144451512177E298", "-1.4863144451512177E298"),
        (0xA684243D3E1F0D82, "-3.808595724071302E-123", "-3.808595724071302E-123"),
        (0x7F8B3D2DCEC79840, "2.3909827999564798E306", "2.3909827999564798E306"),
        (0xBF8B5430FB296EEE, "-0.01334417597279677", "-0.01334417597279677"),
        (0xF7F59F7201510127, "-7.139515372573666E269", "-7.139515372573666E269"),
        (0x174AC6FC3A961003, "1.7910982131729933E-196", "1.7910982131729933E-196"),
        (0x49B346B0FA8D380E, "1.1004729383017801E47", "1.1004729383017801E47"),
        (0x791F8CCF77590A71, "2.7308382535593594E275", "2.7308382535593594E275"),
        (0x1C5149A40F251E81, "2.795881054840452E-172", "2.795881054840452E-172"),
        (0x7D56A6A4BFEBCD16, "5.786583272333061E295", "5.786583272333061E295"),
        (0x51A65E0D29DD6953, "2.1726214783263023E85", "2.1726214783263023E85"),
        (0x11DDC1983B4A56C7, "1.2862373347303726E-222", "1.2862373347303726E-222"),
        (0x4D20F62E153F630A, "3.488807127921061E63", "3.488807127921061E63"),
        (0x61F3D3702C42D94F, "7.135612131415231E163", "7.135612131415231E163"),
        (0xA8D5417EE520F07A, "-5.5240798213203305E-112", "-5.5240798213203305E-112"),
        (0x786E6C7C97EE08B7, "1.285817164335889E272", "1.285817164335889E272"),
        (0x389E049A7A95BBAF, "5.645754952373498E-36", "5.645754952373498E-36"),
        (0x5C21D2A634C69AC7, "6.477168271565001E135", "6.477168271565001E135"),
        (0xF95E7C7A210DA910, "-4.2220160540598523E276", "-4.2220160540598523E276"),
        (0x884739C14A3ABACD, "-8.792673121479861E-269", "-8.792673121479861E-269"),
        (0xA0A2C0E42902FAC0, "-1.790334138090721E-151", "-1.790334138090721E-151"),
        (0x949DAD2384FA759C, "-2.2566963127328632E-209", "-2.2566963127328632E-209"),
        (0x82BF5A245DDCC647, "-1.9175696330107233E-295", "-1.9175696330107233E-295"),
        (0x87B77E7A96F261D7, "-1.737168547558031E-271", "-1.737168547558031E-271"),
        (0xFA67FDFC57D0A071, "-4.355066590194375E281", "-4.355066590194375E281"),
        (0xA2AF4DDB6312086F, "-1.2835526070211163E-141", "-1.2835526070211163E-141"),
        (0x1FC0A7D931D8A376, "9.704966528016997E-156", "9.704966528016997E-156"),
        (0xC59CFF16D8F1D169, "-2.2434910632458898E27", "-2.2434910632458898E27"),
        (0x9D6B8047B581335A, "-5.8296487557310935E-167", "-5.8296487557310935E-167"),
        (0xB8D43051EB6478E4, "-6.075330960954381E-35", "-6.075330960954381E-35"),
        (0xB34947A6DCA42496, "-1.229040162678275E-61", "-1.229040162678275E-61"),
        (0x657B05D4E33C505A, "7.008215306472669E180", "7.008215306472669E180"),
        (0xCFC9381EC25D28F8, "-2.2813953885280406E76", "-2.2813953885280406E76"),
        (0x21A15F21E54CD025, "1.086856519808823E-146", "1.086856519808823E-146"),
        (0xA50092D10ADDA6C7, "-1.8679540008982946E-130", "-1.8679540008982946E-130"),
        (0xC5EDC948CC353D45, "-7.374722521536323E28", "-7.374722521536323E28"),
        (0xBD914C4F1B845E2A, "-3.9331285016670866E-12", "-3.9331285016670866E-12"),
        (0xFE76C2796C096760, "-1.5241985759520686E301", "-1.5241985759520686E301"),
        (0x89EA8C4C83FF80C9, "-6.7447564606142815E-261", "-6.7447564606142815E-261"),
        (0xB2B422D933B9C309, "-1.9120395559986175E-64", "-1.9120395559986175E-64"),
        (0xCFE4F496EC861FB4, "-7.58272743527646E76", "-7.58272743527646E76"),
        (0x12DDBE97A66C6444, "8.426162740459635E-218", "8.426162740459635E-218"),
        (0xB067E34616A01383, "-1.6503917233827E-75", "-1.6503917233827E-75"),
        (0xC0C99541DA0C9D49, "-13098.514466835784", "-13098.514466835784"),
        (0xE7E4242DBBC1C2BF, "-2.871674668836098E192", "-2.871674668836098E192"),
        (0x28AD2254906F4588, "9.464404289115121E-113", "9.464404289115121E-113"),
        (0x0A43C599B9736A80, "3.214856851796893E-259", "3.214856851796893E-259"),
        (0xC84AA31469C5ECED, "-1.8128223389057587E40", "-1.8128223389057587E40"),
        (0xB8B6043B4C11CD57, "-1.656339610094632E-35", "-1.656339610094632E-35"),
        (0x424C659A69FB7F65, "2.4392740555899527E11", "2.4392740555899527E11"),
        (0xDAB9825B81B06C6D, "-1.105134532890246E129", "-1.105134532890246E129"),
        (0x6D1D7530AB391C9F, "4.061970928843675E217", "4.061970928843675E217"),
        (0xDB363E5A5C83AEEC, "-2.4669624873552046E131", "-2.4669624873552046E131"),
        (0x61B037E3B67A2817, "3.648240812315205E162", "3.648240812315205E162"),
        (0xA19BFC52C1BB9B9D, "-8.75462066927993E-147", "-8.75462066927993E-147"),
        (0x0C98D151F402D54F, "5.54605733834045E-248", "5.54605733834045E-248"),
        (0x3D11171CA51E08D1, "1.5179218626795677E-14", "1.5179218626795677E-14"),
        (0x23EA5EC3D8FCB45F, "1.133770077522341E-135", "1.133770077522341E-135"),
        (0xF808EC7A5D396685, "-1.6458845827641839E270", "-1.6458845827641839E270"),
        (0x33A3608189B102B0, "6.029161068177398E-60", "6.029161068177398E-60"),
        (0x3C5858888DF786C0, "5.2791611484212035E-18", "5.2791611484212035E-18"),
        (0xD266E4624110C404, "-9.107828252079821E88", "-9.107828252079821E88"),
        (0x7651F47E21EA0840, "8.834111062063695E261", "8.834111062063695E261"),
        (0xF60545A0DAB6E7B8, "-3.270651710866459E260", "-3.270651710866459E260"),
        (0x17DB0C94C4204755, "9.263526386489809E-194", "9.263526386489809E-194"),
        (0xD43095F4CC90FE4D, "-3.542698241200428E97", "-3.542698241200428E97"),
        (0x46058142BEF0F90B, "2.1297445873317437E29", "2.1297445873317437E29"),
        (0x1CE603E1E51F4324, "1.8229485316188062E-169", "1.8229485316188062E-169"),
        (0x5BCA07ADFE1FD48E, "1.478094611320396E134", "1.478094611320396E134"),
        (0x9AD6D24C7B04FE88, "-2.199917471972005E-179", "-2.199917471972005E-179"),
        (0xB6417D5EC669EECA, "-2.393391420963018E-47", "-2.393391420963018E-47"),
        (0x27B0B54CDEAE83F2, "1.6564238454033702E-117", "1.6564238454033702E-117"),
        (0x99734335F809AC51, "-4.427069017478699E-186", "-4.427069017478699E-186"),
        (0x3FCEA847CF625087, "0.23951051355527772", "0.23951051355527772"),
        (0x03B9D39DFF6D6D82, "1.0352182779820175E-290", "1.0352182779820175E-290"),
        (0x87D8913E36670DE4, "-7.26611591926373E-271", "-7.26611591926373E-271"),
        (0x081E07FFED6A58E6, "1.4211413862128676E-269", "1.4211413862128676E-269"),
        (0x0869455F45407D1E, "3.8268024328583224E-268", "3.8268024328583224E-268"),
        (0x891CC17C30E6E7DD, "-8.918037571637262E-265", "-8.918037571637262E-265"),
        (0x5537C2E453A18E04, "3.326202429869292E102", "3.326202429869292E102"),
        (0xA451E8D59D8F1979, "-9.856111907451786E-134", "-9.856111907451786E-134"),
        (0xEFB9B41B0ED226A6, "-1.5587971711092619E230", "-1.5587971711092619E230"),
        (0xB7BEF9AE77DE6FA9, "-3.5557921701542993E-40", "-3.5557921701542993E-40"),
        (0xF6028FC30B2B5F1B, "-2.853914587960428E260", "-2.853914587960428E260"),
        (0x02128CF434EA1A9A, "1.108006482766678E-298", "1.108006482766678E-298"),
        (0x2703EA98E935357D, "9.641009137622513E-121", "9.641009137622513E-121"),
        (0x8BB996992E17F659, "-3.4901544726210124E-252", "-3.4901544726210124E-252"),
        (0xDA88CE319F1CFE38, "-1.3433067318475997E128", "-1.3433067318475997E128"),
        (0x4DDA4A8A4C953EBC, "1.1075134623448988E67", "1.1075134623448988E67"),
        (0x368F290B34EC1484, "6.822643550751286E-46", "6.822643550751286E-46"),
        (0xA9E3DCD9602A1D82, "-6.765963550252043E-107", "-6.765963550252043E-107"),
        (0x7A3FABDE425A8F2F, "7.186256113693932E280", "7.186256113693932E280"),
        (0xE75D913C8F3576B9, "-8.233593064932309E189", "-8.233593064932309E189"),
        (0x09F5A835A891FD9F, "1.10043257813538E-260", "1.10043257813538E-260"),
        (0xF952CDBBD46E975F, "-2.604102854087389E276", "-2.604102854087389E276"),
        (0x34CDC44484F07117, "2.4279573518883487E-54", "2.4279573518883487E-54"),
        (0x986124A678C0AA4C, "-3.00596397291143E-191", "-3.00596397291143E-191"),
        (0xBC4B97F4E41C5639, "-2.9917019914982752E-18", "-2.9917019914982752E-18"),
        (0x554889C4AE6E174E, "6.869901118882808E102", "6.869901118882808E102"),
        (0x9713873BC2BDE2CB, "-1.6327748585143916E-197", "-1.6327748585143916E-197"),
        (0xA92D26D114E83095, "-2.4243449332825536E-110", "-2.4243449332825536E-110"),
        (0x69B76DB3E33B1BBD, "1.7933377435802928E201", "1.7933377435802928E201"),
        (0xE7BD8328CCA9D251, "-5.259699401183622E191", "-5.259699401183622E191"),
        (0xC969EF69AA1FB76A, "-4.6269953766633883E45", "-4.6269953766633883E45"),
        (0xFB66F2BF9629D899, "-2.7299531817626897E286", "-2.7299531817626897E286"),
        (0xA55582F4CDAA601E, "-7.758424290049864E-129", "-7.758424290049864E-129"),
        (0xD7ED805518E48F8E, "-3.6325323298189857E115", "-3.6325323298189857E115"),
        (0x999188CA348D1AD8, "-1.6119515693801353E-185", "-1.6119515693801353E-185"),
        (0xE35BC6E61DC981C0, "-4.1931664414331413E170", "-4.1931664414331413E170"),
        (0x738103CEEC86D650, "2.3793330248631003E248", "2.3793330248631003E248"),
        (0x3B926E66254D48D0, "9.757420451541427E-22", "9.757420451541427E-22"),
        (0xA80BC72CF758663B, "-8.812378023720383E-116", "-8.812378023720383E-116"),
        (0xAF063FAD13354455, "-3.6648525754537956E-82", "-3.6648525754537956E-82"),
        (0xD1DC2D699BF76ECC, "-2.1895737719832613E86", "-2.1895737719832613E86"),
        (0xA4B703AE9B2D5B03, "-8.105900055098804E-132", "-8.105900055098804E-132"),
        (0xBDD8ACB58706047E, "-8.976583517814443E-11", "-8.976583517814443E-11"),
        (0xA958A1EFF7962A0A, "-1.6388200733624514E-109", "-1.6388200733624514E-109"),
        (0xE7B1DC83E8BE0410, "-3.18326254166716E191", "-3.18326254166716E191"),
        (0x394B323731FC46BB, "1.0475577746699924E-32", "1.0475577746699924E-32"),
        (0x34D2C05BC3EB66D1, "3.0589648921464784E-54", "3.0589648921464784E-54"),
        (0xEF95F580B88F7671, "-3.329271250923371E229", "-3.329271250923371E229"),
        (0xF28A6BEF2981171D, "-5.6377513811313745E243", "-5.6377513811313745E243"),
        (0xFCE46A381FFB00AE, "-4.074491805325417E293", "-4.074491805325417E293"),
        (0xAA23546B4B080927, "-1.0535084928699981E-105", "-1.0535084928699981E-105"),
        (0x9DC3EFA4236E7F84, "-2.70465923670936E-165", "-2.70465923670936E-165"),
        (0xE40DE3104BE09BF7, "-9.239944561421852E173", "-9.239944561421852E173"),
        (0xD853ACA137B8D235, "-3.100833076164717E117", "-3.100833076164717E117"),
        (0xE7891D02F24A86B6, "-5.594631813510603E190", "-5.594631813510603E190"),
        (0xAE7FAD92404D161D, "-1.0191524721679007E-84", "-1.0191524721679007E-84"),
        (0x6F8D7461BDA7D629, "2.232852777025434E229", "2.232852777025434E229"),
        (0xF5FB6D953023C9D0, "-2.1085860311650513E260", "-2.1085860311650513E260"),
        (0x0D6B16982BB3BE7B, "4.959005905435393E-244", "4.959005905435393E-244"),
        (0x69BF3EF80AE87E7F, "2.3917245683131284E201", "2.3917245683131284E201"),
        (0xF6CE4BF0D2AE453E, "-1.9080103670274392E264", "-1.9080103670274392E264"),
        (0x3D0F46E9E706BB9F, "1.3889781133299253E-14", "1.3889781133299253E-14"),
        (0x8CF1BC70670A07B3, "-2.5366552212630314E-246", "-2.5366552212630314E-246"),
        (0x654A0075352EF8CB, "8.429283280076807E179", "8.429283280076807E179"),
        (0x5EEFADE04839A149, "2.0253595171898045E149", "2.0253595171898045E149"),
        (0x11277AAAC816D1E9, "4.955596940316257E-226", "4.955596940316257E-226"),
        (0x6EA08F280E0E7663, "7.66171969846658E224", "7.66171969846658E224"),
        (0xE8F1C61F5DC5D98C, "-3.321546211430239E197", "-3.321546211430239E197"),
        (0x578664E30EF2E75E, "4.30845731741069E113", "4.30845731741069E113"),
        (0xFED24596E4F2AD99, "-7.831370837760034E302", "-7.831370837760034E302"),
        (0xB729EB2F83662FD2, "-5.81117211876722E-43", "-5.81117211876722E-43"),
        (0xFFD6D5FF6B0A322C, "-6.414373767294419E307", "-6.414373767294419E307"),
        (0x074780C4D4C07617, "1.3576796659265353E-273", "1.3576796659265353E-273"),
        (0xA90D019EB4B516BC, "-6.0306532883538334E-111", "-6.0306532883538334E-111"),
        (0x79772F49A0A9CF0A, "1.2843335614079847E277", "1.2843335614079847E277"),
        (0x9F40B28F894E097C, "-3.800526868543384E-158", "-3.800526868543384E-158"),
        (0x62DC64E3E0173A10, "1.6743480378025665E168", "1.6743480378025665E168"),
        (0x1ECF186BE3FD3D04, "2.764702565971528E-160", "2.764702565971528E-160"),
        (0x4A1F330E8C4CD95A, "1.1399508429718296E49", "1.1399508429718296E49"),
        (0x12D5B543A1542430, "6.149562579282874E-218", "6.149562579282874E-218"),
        (0xABBA26AFAE94EA6A, "-4.78246373818175E-98", "-4.78246373818175E-98"),
        (0xBB10C5D6188E8848, "-3.4685333505209266E-24", "-3.4685333505209266E-24"),
        (0x55C50D6A644F42D6, "1.5088644047580053E105", "1.5088644047580053E105"),
        (0x4D3B78FEFA4C5D61, "1.1301588848366462E64", "1.1301588848366462E64"),
        (0xB6163C2F70F5554C, "-3.803468009884433E-48", "-3.803468009884433E-48"),
        (0xD4F7AA6E0DE9F902, "-2.0705164358448044E101", "-2.0705164358448044E101"),
        (0x51192B1A26EB02D5, "4.7747856630545063E82", "4.7747856630545063E82"),
        (0xD36A149A20D28F09, "-6.800239301337692E93", "-6.800239301337692E93"),
        (0x9E527A7BEEB4BC5D, "-1.283535760166E-162", "-1.283535760166E-162"),
        (0xD1132DF4FA8318CF, "-3.638618707312661E82", "-3.638618707312661E82"),
        (0xD676B53476AFB872, "-3.333144368801894E108", "-3.333144368801894E108"),
        (0xB83C25611AB20A8A, "-8.271369803376482E-38", "-8.271369803376482E-38"),
        (0x877A644393F1414C, "-1.2196369731643691E-272", "-1.2196369731643691E-272"),
        (0x97D2B1E2BF727AF3, "-6.402434750075781E-194", "-6.402434750075781E-194"),
        (0x8A5747A053BE5F0D, "-7.570469232564897E-259", "-7.570469232564897E-259"),
        (0x8505A996656FA128, "-1.8209654334558395E-284", "-1.8209654334558395E-284"),
        (0xD5ABC8476C5D6249, "-4.978027965320831E104", "-4.978027965320831E104"),
        (0x109F93E0FEC7CCD2, "1.3017366637675967E-228", "1.3017366637675967E-228"),
        (0x8D16F796A81712C7, "-1.3139248108855547E-245", "-1.3139248108855547E-245"),
        (0xFB3BAAEC3BDC3C8A, "-4.1142288858542855E285", "-4.1142288858542855E285"),
        (0x1884AFDC96558689, "1.450939889623188E-190", "1.450939889623188E-190"),
        (0x0445004ED6DD7678, "4.310010527713549E-288", "4.310010527713549E-288"),
        (0x55C2AA2A912AE509, "1.3377340996829549E105", "1.3377340996829549E105"),
        (0x5276B90C2532073D, "1.80809553780111E89", "1.80809553780111E89"),
        (0x82F09D6E496A9AC5, "-1.6259367840521618E-294", "-1.6259367840521618E-294"),
        (0xB48F94BEAB4FCB12, "-1.609967693356762E-55", "-1.609967693356762E-55"),
        (0x0EEABABEA523C0FD, "8.209633948708744E-237", "8.209633948708744E-237"),
        (0xF55A3412DE7E2531, "-1.9672256346755268E257", "-1.9672256346755268E257"),
        (0x5EEF1AF8E3F3BDBB, "1.9886717607854747E149", "1.9886717607854747E149"),
        (0x8A4ED2781679C973, "-5.011602298029161E-259", "-5.011602298029161E-259"),
        (0xF3B3F18B0E946013, "-2.2310968155652608E249", "-2.2310968155652608E249"),
        (0xC72A67124558FC3A, "-6.854512704002458E34", "-6.854512704002458E34"),
        (0x652D988D9378FCAC, "2.3986072359219175E179", "2.3986072359219175E179"),
        (0x762260F3D8996C90, "1.130320328035353E261", "1.130320328035353E261"),
        (0xF8A0CA193D824E7E, "-1.1353309909581594E273", "-1.1353309909581594E273"),
        (0xAB1B728D092F0C90, "-4.9018915450098445E-101", "-4.9018915450098445E-101"),
        (0x418E9AD414091FDC, "6.41829145044553E7", "6.41829145044553E7"),
        (0x03BD20625BFD8C04, "1.1674882286017927E-290", "1.1674882286017927E-290"),
        (0x40CD09CB18FBFFB5, "14867.58669996248", "14867.58669996248"),
        (0x5DA306FC8E9C594F, "1.1601253665468306E143", "1.1601253665468306E143"),
        (0xD6F83983B2CC8716, "-9.102825472799348E110", "-9.102825472799348E110"),
        (0xAA880C242FDF4C8D, "-8.388032851525213E-104", "-8.388032851525213E-104"),
        (0x7D95A65210ACF2F2, "8.84926943670441E296", "8.84926943670441E296"),
        (0xAF56EF4D9E9C60F8, "-1.2089148541896466E-80", "-1.2089148541896466E-80"),
        (0x0603EDEB38671625, "1.0979122134360796E-279", "1.0979122134360796E-279"),
        (0x99CEED51ADC9208D, "-2.274525699168757E-184", "-2.274525699168757E-184"),
        (0x5BE6FC382A21E7B6, "5.220798970951745E134", "5.220798970951745E134"),
        (0xD8226B613190A5EE, "-3.6288167711375166E116", "-3.6288167711375166E116"),
        (0xD369B16B9FFB315C, "-6.6992210031906695E93", "-6.6992210031906695E93"),
        (0x19E0DD35D7AD588A, "4.961076220202303E-184", "4.961076220202303E-184"),
        (0x8FAB555829AF2243, "-3.4386395403021115E-233", "-3.4386395403021115E-233"),
        (0xE8DC5A8AE45FC6FA, "-1.3246667736856792E197", "-1.3246667736856792E197"),
        (0xCC406BFB87DFCA0F, "-2.0616270398502326E59", "-2.0616270398502326E59"),
        (0x9ECE97CE5F0E43AE, "-2.7200336902134943E-160", "-2.7200336902134943E-160"),
        (0xE313BF60432AC021, "-1.863163980592501E169", "-1.863163980592501E169"),
        (0x588836146C2F27C8, "3.0527097216279857E118", "3.0527097216279857E118"),
        (0x6F6DB2A5195B7B18, "5.628225223923067E228", "5.628225223923067E228"),
        (0xD4B09E4DAFD9E047, "-9.087137047097772E99", "-9.087137047097772E99"),
        (0xECB5325652ED1C9A, "-4.566923381542101E215", "-4.566923381542101E215"),
        (0x49CBDBB9AB792968, "3.1808557626591115E47", "3.1808557626591115E47"),
        (0x34DED602BCF6B553, "5.030353834385333E-54", "5.030353834385333E-54"),
        (0x409F299ACBDB1C48, "1994.4011682735454", "1994.4011682735454"),
        (0x4079BBE77A1C51B0, "411.74401293813844", "411.74401293813844"),
        (0xC0632630B8F1C63C, "-153.19344756337694", "-153.19344756337694"),
        (0x40412B853D4FB240, "34.340003646768764", "34.340003646768764"),
        (0x4058F292C3B7AAF0, "99.79020779548932", "99.79020779548932"),
        (0x406DC0EF197B7850, "238.0291869555972", "238.0291869555972"),
        (0xC07897B64BAAF86E, "-393.4820057562382", "-393.4820057562382"),
        (0x405DE88A96A51960, "119.6334587681099", "119.6334587681099"),
        (0xC08146729488AEC6, "-552.8059473684632", "-552.8059473684632"),
        (0xC06DA8B1FF2B6BE4, "-237.2717281196666", "-237.2717281196666"),
        (0x403178398F7282A0, "17.46962830110226", "17.46962830110226"),
        (0x4051CD9F5E773760, "71.21285211221903", "71.21285211221903"),
        (0xC081EC7DF3752265, "-573.5614995146867", "-573.5614995146867"),
        (0x407C6F814133F3E8, "454.9690563229947", "454.9690563229947"),
        (0xC075FBF4D9C81A3A, "-351.74727800526637", "-351.74727800526637"),
        (0xC0844C328808C084, "-649.5246735271216", "-649.5246735271216"),
        (0x4087FA470144896C, "767.2846703867376", "767.2846703867376"),
        (0x407DFD031DAB4EF4, "479.81326071660374", "479.81326071660374"),
        (0xC03731672B0706C0, "-23.192980469909116", "-23.192980469909116"),
        (0x4085057A5A519F7A, "672.6847425820154", "672.6847425820154"),
        (0x408D4E5B7B5FF700, "937.7946689126256", "937.7946689126256"),
        (0xC062945D31BC32E4, "-148.63637625463082", "-148.63637625463082"),
        (0xC085F97E6F150860, "-703.1867353099042", "-703.1867353099042"),
        (0x407A1B4A3D8D96BC, "417.7056251078427", "417.7056251078427"),
        (0xC07769082F6A114C, "-374.56449834282535", "-374.56449834282535"),
        (0xC0812C72AF0859A2, "-549.555997910724", "-549.555997910724"),
        (0xC0722229674992AA, "-290.13510826816", "-290.13510826816"),
        (0x4084123AA7BA0AF8, "642.2786402258489", "642.2786402258489"),
        (0x40746550162F2A50, "326.33205240653933", "326.33205240653933"),
        (0x407023B38BB54BF4, "258.2313344079878", "258.2313344079878"),
        (0xC07727EB71E889B6, "-370.49498167834406", "-370.49498167834406"),
        (0x406AC5336B91F478, "214.16252687937572", "214.16252687937572"),
        (0xC0723FCCD8558AC4, "-291.9875109998213", "-291.9875109998213"),
        (0x408DA1E01A893A88, "948.2344256134975", "948.2344256134975"),
        (0xC08681260A3170B4, "-720.1435741293449", "-720.1435741293449"),
        (0x4080BDDB54023F20, "535.7320938277735", "535.7320938277735"),
        (0xC05F8792C812D438, "-126.11833383406417", "-126.11833383406417"),
        (0x4082343E587789C4, "582.5304421748083", "582.5304421748083"),
        (0xC08DFA4E34FFD5C8, "-959.2881870257488", "-959.2881870257488"),
        (0xC08C9CE27D657F07, "-915.6105907372847", "-915.6105907372847"),
        (0x407B10C276DB090C, "433.04747663078956", "433.04747663078956"),
        (0x4081F17B1F0BB15C, "574.1851178086758", "574.1851178086758"),
        (0x406592F5CDBE7AE8, "172.59250533297677", "172.59250533297677"),
        (0xC07AE9776884F0A2, "-430.5916524117439", "-430.5916524117439"),
        (0xC083C7DDE1B73E55, "-632.9833406749627", "-632.9833406749627"),
        (0x407324C82026AE9C, "306.29885878668006", "306.29885878668006"),
        (0x407C16CCFDF0AF14, "449.42504686371944", "449.42504686371944"),
        (0x408BCCCED5FA86F4, "889.6009940693316", "889.6009940693316"),
        (0x40554AA4667D1FE0, "85.16628420085135", "85.16628420085135"),
        (0xC0641BA619BC4B38, "-160.86402594352853", "-160.86402594352853"),
        (0xC07D2E014A5C000C, "-466.8753150552518", "-466.8753150552518"),
        (0x4071175473D64700, "273.4581182832917", "273.4581182832917"),
        (0x40882E4FF98C1CEC, "773.7890501924826", "773.7890501924826"),
        (0x408EF27BB4424BDA, "990.3104024104498", "990.3104024104498"),
        (0x4080FC20F697E070, "543.5160953393333", "543.5160953393333"),
        (0x408F097447635722, "993.1817767868963", "993.1817767868963"),
        (0xC089F8CD36824420, "-831.1002016236343", "-831.1002016236343"),
        (0x408718222E19B448, "739.0166894920485", "739.0166894920485"),
        (0xC088BAB35FCD6206, "-791.337585072092", "-791.337585072092"),
        (0xC060B68CFD169FD4, "-133.70471052569212", "-133.70471052569212"),
        (0xC08858F258791481, "-779.1183328112967", "-779.1183328112967"),
        (0x4077FCF7577D56F4, "383.81038617096715", "383.81038617096715"),
        (0x406C1A0A1A17D048, "224.8137331452474", "224.8137331452474"),
        (0x40789476FAF818C4, "393.2790479365615", "393.2790479365615"),
        (0xC06CD1DA6BA2F098, "-230.5579126532", "-230.5579126532"),
        (0x4065CEA835363898, "174.458033185864", "174.458033185864"),
        (0x4027A780F9EA02C0, "11.82715588552071", "11.82715588552071"),
        (0xC065A1A759761230, "-173.05167840061904", "-173.05167840061904"),
        (0xC0858E19CF9B1B37, "-689.762603008049", "-689.762603008049"),
        (0x406E3C90EACC86B0, "241.8926900858546", "241.8926900858546"),
        (0xC0543CBFDE531698, "-80.94921072115028", "-80.94921072115028"),
        (0x4086C86DA19B95BC, "729.0535308985777", "729.0535308985777"),
        (0xC088B0A9F2A60C4A, "-790.0829823467732", "-790.0829823467732"),
        (0x4081B29A69CCCF8C, "566.3253971100653", "566.3253971100653"),
        (0x405D9395F7F4C730, "118.30602835563764", "118.30602835563764"),
        (0xC0766266144CD5DC, "-358.14992170347045", "-358.14992170347045"),
        (0x4073A3A92CD6FFF4, "314.22880252823165", "314.22880252823165"),
        (0xC0811F5A68D95F74, "-547.9191452963119", "-547.9191452963119"),
        (0xC055509D80208D98, "-85.25961306742681", "-85.25961306742681"),
        (0xC08326CE4CE4E1E1, "-612.8507326013024", "-612.8507326013024"),
        (0x4088D1BA69FC3946, "794.2160224633196", "794.2160224633196"),
        (0xC07E14308E75164C, "-481.26185460793636", "-481.26185460793636"),
        (0xC08ED8430CEE0FE5, "-987.0327395056344", "-987.0327395056344"),
        (0xC088EAF824A3CB80, "-797.371163634918", "-797.371163634918"),
        (0x407206E15B2F1630, "288.4300186003993", "288.4300186003993"),
        (0x4081DD68C6465E76, "571.6761594293191", "571.6761594293191"),
        (0x4078B0BCCB236108, "395.0460921651834", "395.0460921651834"),
        (0x407B2F22EEB3F560, "434.94602842613494", "434.94602842613494"),
        (0x408CE3C253D8D8B2, "924.4698864880686", "924.4698864880686"),
        (0xC05DB7437124A820, "-118.86349133090744", "-118.86349133090744"),
        (0x408C14004FA83E0E, "898.5001519340456", "898.5001519340456"),
        (0x4089FBB376811F1C, "831.462628372919", "831.462628372919"),
        (0xC0766F230C9286BA, "-358.9460569118197", "-358.9460569118197"),
        (0x407796F1DAE52478, "377.43404664524815", "377.43404664524815"),
        (0x40746B516F8C6954, "326.7073817715475", "326.7073817715475"),
        (0xC0788D7F3FFC80EA, "-392.84356688150604", "-392.84356688150604"),
        (0x4077E3779F96AEAC, "382.21670492992666", "382.21670492992666"),
        (0x404E7AC551CE6CE0, "60.959146714967346", "60.959146714967346"),
        (0xC0335BB2D53BB1A0, "-19.35819752414102", "-19.35819752414102"),
        (0x4079A8F468F6E830, "410.5596704144291", "410.5596704144291"),
        (0xC0890F11796F2052, "-801.8835323983897", "-801.8835323983897"),
        (0xC07D6DDE7DCAE46E, "-470.8668191838723", "-470.8668191838723"),
        (0x408B30AA9DB0E710, "870.0833085842623", "870.0833085842623"),
        (0x405215221008D8D0, "72.3302040182491", "72.3302040182491"),
        (0x404F2A11784D1220, "62.32865813983176", "62.32865813983176"),
        (0x408D53F212236B10, "938.4931986586616", "938.4931986586616"),
        (0x4081006D7B44DD44, "544.053457773211", "544.053457773211"),
        (0xC0797AC4345431EA, "-407.6729014672152", "-407.6729014672152"),
        (0x4072F643527874E8, "303.391436071905", "303.391436071905"),
        (0x408DA4C7C07CD746, "948.5975351098248", "948.5975351098248"),
        (0xC0806CFBD1C8BA49, "-525.622958725152", "-525.622958725152"),
        (0x4069BA7F6B705F70, "205.82805416057408", "205.82805416057408"),
        (0xC0499EB4F97279C0, "-51.23989790048245", "-51.23989790048245"),
        (0x406D6EB83A287310, "235.45998866939817", "235.45998866939817"),
        (0xC087F8BB5638EDBE, "-767.0914730498841", "-767.0914730498841"),
        (0xC07B1358980C9E36, "-433.20912938050185", "-433.20912938050185"),
        (0x408F01BDBBA0CF76, "992.2176430285751", "992.2176430285751"),
        (0xC08EC21CD1581F33, "-984.2640711674234", "-984.2640711674234"),
        (0xC0852F2C6D1B26E8, "-677.896692478299", "-677.896692478299"),
        (0xC08C415FEFC79B5C, "-904.1718440622603", "-904.1718440622603"),
        (0x4083696F752A0036, "621.1794226914706", "621.1794226914706"),
        (0x4085D90624DD2F1B, "699.128", "699.128"),
        (0x405247AE147AE148, "73.12", "73.12"),
        (0x407C9EC49BA5E354, "457.923", "457.923"),
        (0x406F612F1A9FBE77, "251.037", "251.037"),
        (0x40824520C49BA5E3, "584.641", "584.641"),
        (0x407E0AD916872B02, "480.678", "480.678"),
        (0x4075E20C49BA5E35, "350.128", "350.128"),
        (0x40770DE353F7CED9, "368.868", "368.868"),
        (0x4079892F1A9FBE77, "408.574", "408.574"),
        (0x40654A2D0E560419, "170.318", "170.318"),
        (0x402E6353F7CED917, "15.194", "15.194"),
        (0x408CF4126E978D50, "926.509", "926.509"),
        (0x40747126E978D4FE, "327.072", "327.072"),
        (0x408417FBE76C8B44, "642.998", "642.998"),
        (0x408183A5E353F7CF, "560.456", "560.456"),
        (0x408CC7C8B4395810, "920.973", "920.973"),
        (0x408562D2F1A9FBE7, "684.353", "684.353"),
        (0x408942D70A3D70A4, "808.355", "808.355"),
        (0x407672B020C49BA6, "359.168", "359.168"),
        (0x4067DB2B020C49BA, "190.849", "190.849"),
        (0x40731224DD2F1AA0, "305.134", "305.134"),
        (0x407A46AC083126E9, "420.417", "420.417"),
        (0x4088F99374BC6A7F, "799.197", "799.197"),
        (0x407279B645A1CAC1, "295.607", "295.607"),
        (0x408B2172B020C49C, "868.181", "868.181"),
        (0x40822EA9FBE76C8B, "581.833", "581.833"),
        (0x4070CBEB851EB852, "268.745", "268.745"),
        (0x407EAC24DD2F1AA0, "490.759", "490.759"),
        (0x4082BD89374BC6A8, "599.692", "599.692"),
        (0x408DFE6C8B439581, "959.803", "959.803"),
        (0x40859C5A1CAC0831, "691.544", "691.544"),
        (0x40726B810624DD2F, "294.719", "294.719"),
        (0x4084E65C28F5C28F, "668.795", "668.795"),
        (0x408EDECED916872B, "987.851", "987.851"),
        (0x407C8B4BC6A7EF9E, "456.706", "456.706"),
        (0x406DB30A3D70A3D7, "237.595", "237.595"),
        (0x4069E28F5C28F5C3, "207.08", "207.08"),
        (0x40862072B020C49C, "708.056", "708.056"),
        (0x408AA0353F7CED91, "852.026", "852.026"),
        (0x4088E50624DD2F1B, "796.628", "796.628"),
        (0x408C44D916872B02, "904.606", "904.606"),
        (0x4077EDEF9DB22D0E, "382.871", "382.871"),
        (0x40859F189374BC6A, "691.887", "691.887"),
        (0x408A6A9DB22D0E56, "845.327", "845.327"),
        (0x407FBC49BA5E353F, "507.768", "507.768"),
        (0x408C8B604189374C, "913.422", "913.422"),
        (0x40851122D0E56042, "674.142", "674.142"),
        (0x4063D8C49BA5E354, "158.774", "158.774"),
        (0x40867145A1CAC083, "718.159", "718.159"),
        (0x4086EE916872B021, "733.821", "733.821"),
        (0x4088AA20C49BA5E3, "789.266", "789.266"),
        (0x408ED7D70A3D70A4, "986.98", "986.98"),
        (0x4053EF7CED916873, "79.742", "79.742"),
        (0x40833A8D4FDF3B64, "615.319", "615.319"),
        (0x4080B19DB22D0E56, "534.202", "534.202"),
        (0x408A38C8B4395810, "839.098", "839.098"),
        (0x40855620C49BA5E3, "682.766", "682.766"),
        (0x403BF2F1A9FBE76D, "27.949", "27.949"),
        (0x40766E28F5C28F5C, "358.885", "358.885"),
        (0x40810F7AE147AE14, "545.935", "545.935"),
        (0xC28DFAA43D155000, "-4.12029181201E12", "-4.12029181201E12"),
        (0xC28E78041E12C000, "-4.187601748568E12", "-4.187601748568E12"),
        (0xC2EF5C4348BB46A0, "-2.75849010338357E14", "-2.75849010338357E14"),
        (0x430B35FC2AA2A810, "9.5739769181517E14", "9.5739769181517E14"),
        (0x420704BBFE800000, "1.2357959632E10", "1.2357959632E10"),
        (0x41B106EADC000000, "2.85666012E8", "2.85666012E8"),
        (0x41AF25455A000000, "2.61268141E8", "2.61268141E8"),
        (0xC3865F4467DCF3EB, "-2.01510300562652512E17", "-2.015103005626525E17"),
        (0xC238FF1835960000, "-1.07358991766E11", "-1.07358991766E11"),
        (0xC205B45CC5F80000, "-1.1652536511E10", "-1.1652536511E10"),
        (0x42FDD549852DA5C0, "5.248303792687E14", "5.248303792687E14"),
        (0x42ACE069CC21EA00, "1.5875086618869E13", "1.5875086618869E13"),
        (0xC272FC15C0791000, "-1.304619124625E12", "-1.304619124625E12"),
        (0x41941862B4000000, "8.4285613E7", "8.4285613E7"),
        (0x424AE83CA0308000, "2.31130873953E11", "2.31130873953E11"),
        (0xC208349937F80000, "-1.2995208959E10", "-1.2995208959E10"),
        (0xC13FEF6300000000, "-2092899.0", "-2092899.0"),
        (0x4334213CFAF2A5E4, "5.666045326173668E15", "5.666045326173668E15"),
        (0x41C1817119000000, "5.87391538E8", "5.87391538E8"),
        (0x424B6BE8BDBA8000, "2.35549064053E11", "2.35549064053E11"),
        (0xC2B87E89F1CB2700, "-2.6931759270695E13", "-2.6931759270695E13"),
        (0x41730AEFF0000000, "1.9967743E7", "1.9967743E7"),
        (0xC257E3EE37228000, "-4.1043315009E11", "-4.1043315009E11"),
        (0x433DE41E09ABC295, "8.413591987012245E15", "8.413591987012245E15"),
        (0x43907BB5BFC06C20, "2.9693569047848755E17", "2.9693569047848755E17"),
        (0x41CC0B9FBF800000, "9.41047679E8", "9.41047679E8"),
        (0xC3DE197BDEF3A59F, "-8.6756035722251131E18", "-8.675603572225113E18"),
        (0x418687F8D0000000, "4.7251226E7", "4.7251226E7"),
        (0x42DA0950F91AE780, "1.14509262121886E14", "1.14509262121886E14"),
        (0x436423CA66CCE93F, "4.5350813994273272E16", "4.535081399427327E16"),
        (0xC2F3F5E329CB63A0, "-3.51148785317434E14", "-3.51148785317434E14"),
        (0xC2EEE5D786AE0680, "-2.71780098175028E14", "-2.71780098175028E14"),
        (0xC3A36DF4C682E84A, "-7.0002209630952781E17", "-7.000220963095278E17"),
        (0x4390163F014DED99, "2.8979580723235386E17", "2.8979580723235386E17"),
        (0xC256D3C154024000, "-3.92167772169E11", "-3.92167772169E11"),
        (0xC173FE80A0000000, "-2.0965386E7", "-2.0965386E7"),
        (0x42309DEAA41F0000, "7.1368877087E10", "7.1368877087E10"),
        (0xC223153491980000, "-4.0980072652E10", "-4.0980072652E10"),
        (0xC392F02725779255, "-3.4115843224165306E17", "-3.4115843224165306E17"),
        (0xC184EB6678000000, "-4.3871439E7", "-4.3871439E7"),
    ]
    /// String.format(Locale.forLanguageTag(tag), pattern, args) with libcore main's Formatter.
    static let formats: [(locale: String, pattern: String, args: [Any?], expected: String)] = [
        (locale: "he", pattern: "%1$d%%", args: [42], expected: "42%"),
        (locale: "he", pattern: "\u{1F7E1} \u{5EA}\u{5E9}\u{5D5}\u{5D1}\u{5D4} \u{5D7}\u{5DC}\u{5E7}\u{5D9}\u{5EA} (%1$d%%)", args: [7], expected: "\u{1F7E1} \u{5EA}\u{5E9}\u{5D5}\u{5D1}\u{5D4} \u{5D7}\u{5DC}\u{5E7}\u{5D9}\u{5EA} (7%)"),
        (locale: "he", pattern: "%1$s gave a partial answer (%2$d%%).", args: ["Maya", 50], expected: "Maya gave a partial answer (50%)."),
        (locale: "he", pattern: "\u{5D4}\u{5EA}\u{5E9}\u{5D5}\u{5D1}\u{5D4} \u{5E9}\u{5DC} %1$s \u{5D7}\u{5DC}\u{5E7}\u{5D9}\u{5EA} (%2$d%%).", args: ["BOB", 33], expected: "\u{5D4}\u{5EA}\u{5E9}\u{5D5}\u{5D1}\u{5D4} \u{5E9}\u{5DC} BOB \u{5D7}\u{5DC}\u{5E7}\u{5D9}\u{5EA} (33%)."),
        (locale: "he", pattern: "Shot quality \u{2022} %1$d%%", args: [87], expected: "Shot quality \u{2022} 87%"),
        (locale: "he", pattern: "%d topics selected", args: [3], expected: "3 topics selected"),
        (locale: "he", pattern: "%d \u{5E0}\u{5D5}\u{5E9}\u{5D0}\u{5D9}\u{5DD} \u{5E0}\u{5D1}\u{5D7}\u{5E8}\u{5D5}", args: [11], expected: "11 \u{5E0}\u{5D5}\u{5E9}\u{5D0}\u{5D9}\u{5DD} \u{5E0}\u{5D1}\u{5D7}\u{5E8}\u{5D5}"),
        (locale: "he", pattern: "%,d|%,d|%,d", args: [1234567, -1234567, 999], expected: "1,234,567|-1,234,567|999"),
        (locale: "he", pattern: "%.2f|%.0f|%10.3f|%-10.1f|", args: [Double(bitPattern: 0x400921F9F01B866E), Double(bitPattern: 0x4004000000000000), Double(bitPattern: 0xBFD5555555555555), Double(bitPattern: 0x3FD0000000000000)], expected: "3.14|3|    -0.333|0.3       |"),
        (locale: "he", pattern: "%s|%s|%s|%s", args: [Double(bitPattern: 0x3FF8000000000000), Float(bitPattern: 0x3DCCCCCD), 100, Int64(1234567890123)], expected: "1.5|0.1|100|1234567890123"),
        (locale: "en", pattern: "%1$d%%", args: [42], expected: "42%"),
        (locale: "en", pattern: "\u{1F7E1} \u{5EA}\u{5E9}\u{5D5}\u{5D1}\u{5D4} \u{5D7}\u{5DC}\u{5E7}\u{5D9}\u{5EA} (%1$d%%)", args: [7], expected: "\u{1F7E1} \u{5EA}\u{5E9}\u{5D5}\u{5D1}\u{5D4} \u{5D7}\u{5DC}\u{5E7}\u{5D9}\u{5EA} (7%)"),
        (locale: "en", pattern: "%1$s gave a partial answer (%2$d%%).", args: ["Maya", 50], expected: "Maya gave a partial answer (50%)."),
        (locale: "en", pattern: "\u{5D4}\u{5EA}\u{5E9}\u{5D5}\u{5D1}\u{5D4} \u{5E9}\u{5DC} %1$s \u{5D7}\u{5DC}\u{5E7}\u{5D9}\u{5EA} (%2$d%%).", args: ["BOB", 33], expected: "\u{5D4}\u{5EA}\u{5E9}\u{5D5}\u{5D1}\u{5D4} \u{5E9}\u{5DC} BOB \u{5D7}\u{5DC}\u{5E7}\u{5D9}\u{5EA} (33%)."),
        (locale: "en", pattern: "Shot quality \u{2022} %1$d%%", args: [87], expected: "Shot quality \u{2022} 87%"),
        (locale: "en", pattern: "%d topics selected", args: [3], expected: "3 topics selected"),
        (locale: "en", pattern: "%d \u{5E0}\u{5D5}\u{5E9}\u{5D0}\u{5D9}\u{5DD} \u{5E0}\u{5D1}\u{5D7}\u{5E8}\u{5D5}", args: [11], expected: "11 \u{5E0}\u{5D5}\u{5E9}\u{5D0}\u{5D9}\u{5DD} \u{5E0}\u{5D1}\u{5D7}\u{5E8}\u{5D5}"),
        (locale: "en", pattern: "%,d|%,d|%,d", args: [1234567, -1234567, 999], expected: "1,234,567|-1,234,567|999"),
        (locale: "en", pattern: "%.2f|%.0f|%10.3f|%-10.1f|", args: [Double(bitPattern: 0x400921F9F01B866E), Double(bitPattern: 0x4004000000000000), Double(bitPattern: 0xBFD5555555555555), Double(bitPattern: 0x3FD0000000000000)], expected: "3.14|3|    -0.333|0.3       |"),
        (locale: "en", pattern: "%s|%s|%s|%s", args: [Double(bitPattern: 0x3FF8000000000000), Float(bitPattern: 0x3DCCCCCD), 100, Int64(1234567890123)], expected: "1.5|0.1|100|1234567890123"),
        (locale: "und", pattern: "%1$d%%", args: [42], expected: "42%"),
        (locale: "und", pattern: "\u{1F7E1} \u{5EA}\u{5E9}\u{5D5}\u{5D1}\u{5D4} \u{5D7}\u{5DC}\u{5E7}\u{5D9}\u{5EA} (%1$d%%)", args: [7], expected: "\u{1F7E1} \u{5EA}\u{5E9}\u{5D5}\u{5D1}\u{5D4} \u{5D7}\u{5DC}\u{5E7}\u{5D9}\u{5EA} (7%)"),
        (locale: "und", pattern: "%1$s gave a partial answer (%2$d%%).", args: ["Maya", 50], expected: "Maya gave a partial answer (50%)."),
        (locale: "und", pattern: "\u{5D4}\u{5EA}\u{5E9}\u{5D5}\u{5D1}\u{5D4} \u{5E9}\u{5DC} %1$s \u{5D7}\u{5DC}\u{5E7}\u{5D9}\u{5EA} (%2$d%%).", args: ["BOB", 33], expected: "\u{5D4}\u{5EA}\u{5E9}\u{5D5}\u{5D1}\u{5D4} \u{5E9}\u{5DC} BOB \u{5D7}\u{5DC}\u{5E7}\u{5D9}\u{5EA} (33%)."),
        (locale: "und", pattern: "Shot quality \u{2022} %1$d%%", args: [87], expected: "Shot quality \u{2022} 87%"),
        (locale: "und", pattern: "%d topics selected", args: [3], expected: "3 topics selected"),
        (locale: "und", pattern: "%d \u{5E0}\u{5D5}\u{5E9}\u{5D0}\u{5D9}\u{5DD} \u{5E0}\u{5D1}\u{5D7}\u{5E8}\u{5D5}", args: [11], expected: "11 \u{5E0}\u{5D5}\u{5E9}\u{5D0}\u{5D9}\u{5DD} \u{5E0}\u{5D1}\u{5D7}\u{5E8}\u{5D5}"),
        (locale: "und", pattern: "%,d|%,d|%,d", args: [1234567, -1234567, 999], expected: "1,234,567|-1,234,567|999"),
        (locale: "und", pattern: "%.2f|%.0f|%10.3f|%-10.1f|", args: [Double(bitPattern: 0x400921F9F01B866E), Double(bitPattern: 0x4004000000000000), Double(bitPattern: 0xBFD5555555555555), Double(bitPattern: 0x3FD0000000000000)], expected: "3.14|3|    -0.333|0.3       |"),
        (locale: "und", pattern: "%s|%s|%s|%s", args: [Double(bitPattern: 0x3FF8000000000000), Float(bitPattern: 0x3DCCCCCD), 100, Int64(1234567890123)], expected: "1.5|0.1|100|1234567890123"),
        (locale: "en-US", pattern: "%1$d%%", args: [42], expected: "42%"),
        (locale: "en-US", pattern: "\u{1F7E1} \u{5EA}\u{5E9}\u{5D5}\u{5D1}\u{5D4} \u{5D7}\u{5DC}\u{5E7}\u{5D9}\u{5EA} (%1$d%%)", args: [7], expected: "\u{1F7E1} \u{5EA}\u{5E9}\u{5D5}\u{5D1}\u{5D4} \u{5D7}\u{5DC}\u{5E7}\u{5D9}\u{5EA} (7%)"),
        (locale: "en-US", pattern: "%1$s gave a partial answer (%2$d%%).", args: ["Maya", 50], expected: "Maya gave a partial answer (50%)."),
        (locale: "en-US", pattern: "\u{5D4}\u{5EA}\u{5E9}\u{5D5}\u{5D1}\u{5D4} \u{5E9}\u{5DC} %1$s \u{5D7}\u{5DC}\u{5E7}\u{5D9}\u{5EA} (%2$d%%).", args: ["BOB", 33], expected: "\u{5D4}\u{5EA}\u{5E9}\u{5D5}\u{5D1}\u{5D4} \u{5E9}\u{5DC} BOB \u{5D7}\u{5DC}\u{5E7}\u{5D9}\u{5EA} (33%)."),
        (locale: "en-US", pattern: "Shot quality \u{2022} %1$d%%", args: [87], expected: "Shot quality \u{2022} 87%"),
        (locale: "en-US", pattern: "%d topics selected", args: [3], expected: "3 topics selected"),
        (locale: "en-US", pattern: "%d \u{5E0}\u{5D5}\u{5E9}\u{5D0}\u{5D9}\u{5DD} \u{5E0}\u{5D1}\u{5D7}\u{5E8}\u{5D5}", args: [11], expected: "11 \u{5E0}\u{5D5}\u{5E9}\u{5D0}\u{5D9}\u{5DD} \u{5E0}\u{5D1}\u{5D7}\u{5E8}\u{5D5}"),
        (locale: "en-US", pattern: "%,d|%,d|%,d", args: [1234567, -1234567, 999], expected: "1,234,567|-1,234,567|999"),
        (locale: "en-US", pattern: "%.2f|%.0f|%10.3f|%-10.1f|", args: [Double(bitPattern: 0x400921F9F01B866E), Double(bitPattern: 0x4004000000000000), Double(bitPattern: 0xBFD5555555555555), Double(bitPattern: 0x3FD0000000000000)], expected: "3.14|3|    -0.333|0.3       |"),
        (locale: "en-US", pattern: "%s|%s|%s|%s", args: [Double(bitPattern: 0x3FF8000000000000), Float(bitPattern: 0x3DCCCCCD), 100, Int64(1234567890123)], expected: "1.5|0.1|100|1234567890123"),
        (locale: "he-IL", pattern: "%1$d%%", args: [42], expected: "42%"),
        (locale: "he-IL", pattern: "\u{1F7E1} \u{5EA}\u{5E9}\u{5D5}\u{5D1}\u{5D4} \u{5D7}\u{5DC}\u{5E7}\u{5D9}\u{5EA} (%1$d%%)", args: [7], expected: "\u{1F7E1} \u{5EA}\u{5E9}\u{5D5}\u{5D1}\u{5D4} \u{5D7}\u{5DC}\u{5E7}\u{5D9}\u{5EA} (7%)"),
        (locale: "he-IL", pattern: "%1$s gave a partial answer (%2$d%%).", args: ["Maya", 50], expected: "Maya gave a partial answer (50%)."),
        (locale: "he-IL", pattern: "\u{5D4}\u{5EA}\u{5E9}\u{5D5}\u{5D1}\u{5D4} \u{5E9}\u{5DC} %1$s \u{5D7}\u{5DC}\u{5E7}\u{5D9}\u{5EA} (%2$d%%).", args: ["BOB", 33], expected: "\u{5D4}\u{5EA}\u{5E9}\u{5D5}\u{5D1}\u{5D4} \u{5E9}\u{5DC} BOB \u{5D7}\u{5DC}\u{5E7}\u{5D9}\u{5EA} (33%)."),
        (locale: "he-IL", pattern: "Shot quality \u{2022} %1$d%%", args: [87], expected: "Shot quality \u{2022} 87%"),
        (locale: "he-IL", pattern: "%d topics selected", args: [3], expected: "3 topics selected"),
        (locale: "he-IL", pattern: "%d \u{5E0}\u{5D5}\u{5E9}\u{5D0}\u{5D9}\u{5DD} \u{5E0}\u{5D1}\u{5D7}\u{5E8}\u{5D5}", args: [11], expected: "11 \u{5E0}\u{5D5}\u{5E9}\u{5D0}\u{5D9}\u{5DD} \u{5E0}\u{5D1}\u{5D7}\u{5E8}\u{5D5}"),
        (locale: "he-IL", pattern: "%,d|%,d|%,d", args: [1234567, -1234567, 999], expected: "1,234,567|-1,234,567|999"),
        (locale: "he-IL", pattern: "%.2f|%.0f|%10.3f|%-10.1f|", args: [Double(bitPattern: 0x400921F9F01B866E), Double(bitPattern: 0x4004000000000000), Double(bitPattern: 0xBFD5555555555555), Double(bitPattern: 0x3FD0000000000000)], expected: "3.14|3|    -0.333|0.3       |"),
        (locale: "he-IL", pattern: "%s|%s|%s|%s", args: [Double(bitPattern: 0x3FF8000000000000), Float(bitPattern: 0x3DCCCCCD), 100, Int64(1234567890123)], expected: "1.5|0.1|100|1234567890123"),
        (locale: "en-US", pattern: "%04d-W%02d", args: [2026, 7], expected: "2026-W07"),
        (locale: "en-US", pattern: "W%02d/%02d", args: [42, 26], expected: "W42/26"),
        (locale: "en-US", pattern: "%04d-W%02d", args: [2025, 52], expected: "2025-W52"),
        (locale: "he", pattern: "%1$s %2$s %1$s", args: ["a", "b"], expected: "a b a"),
        (locale: "he", pattern: "%2$s-%1$s", args: ["x", "y"], expected: "y-x"),
        (locale: "he", pattern: "%s %<s %s", args: ["a", "b"], expected: "a a b"),
        (locale: "he", pattern: "%s %2$s %s", args: ["a", "b", "c"], expected: "a b b"),
        (locale: "en", pattern: "%5d|%-5d|%05d|%+d|% d|%(d|%(5d|", args: [42, 42, -42, 7, 7, -7, -7], expected: "   42|42   |-0042|+7| 7|(7)|  (7)|"),
        (locale: "en", pattern: "%d|%d|%d|%d", args: [-2147483648, 2147483647, Int64(-9223372036854775808), Int64(9223372036854775807)], expected: "-2147483648|2147483647|-9223372036854775808|9223372036854775807"),
        (locale: "en", pattern: "%x|%x|%X|%o|%#x|%#o|%08X|%x|%x", args: [-1, Int64(-1), 255, 8, 255, 8, 48879, Int8(-1), Int16(-1)], expected: "ffffffff|ffffffffffffffff|FF|10|0xff|010|0000BEEF|ff|ffff"),
        (locale: "en", pattern: "%c|%c|%c|%-3c|%C", args: [Character("A"), Character("\u{5D0}"), 128512, Character("z"), Character("q")], expected: "A|\u{5D0}|\u{1F600}|z  |Q"),
        (locale: "en", pattern: "%b|%b|%b|%b|%B", args: [true, false, nil, "x", true], expected: "true|false|false|true|TRUE"),
        (locale: "en", pattern: "%s|%S|%.3s|%-8s|%8s|%s|%s", args: [nil, "hello", "abcdef", "ab", "cd", Character("c"), false], expected: "null|HELLO|abc|ab      |      cd|c|false"),
        (locale: "en", pattern: "%s|%s|%s|%s|%s|%s", args: [Float(bitPattern: 0x3DCCCCCD), Float(bitPattern: 0x501502F9), Float(bitPattern: 0x3727C5AC), Double(bitPattern: 0x4059000000000000), Double(bitPattern: 0x416312D000000000), Double(bitPattern: 0x3F1A36E2EB1C432D)], expected: "0.1|1.0E10|1.0E-5|100.0|1.0E7|1.0E-4"),
        (locale: "en", pattern: "%h|%h|%h", args: ["hello", 42, nil], expected: "5e918d2|2a|null"),
        (locale: "en", pattern: "line%nnext|%5%|%-5%|%%", args: [], expected: "line\u{A}next|    %|%    |%"),
        (locale: "en", pattern: "%.2f|%.2f|%.2f|%.2f|%.2f|%.2f|%.2f", args: [Double(bitPattern: 0x3FC0000000000000), Double(bitPattern: 0x400921F9F01B866E), Double(bitPattern: 0x8000000000000000), Double(bitPattern: 0x4415AF1D78B58C40), Double(bitPattern: 0x3FE0000000000000), Double(bitPattern: 0x3FF0147AE147AE14), Double(bitPattern: 0x4005666666666666)], expected: "0.13|3.14|-0.00|100000000000000000000.00|0.50|1.01|2.68"),
        (locale: "en", pattern: "%.0f|%.0f|%.0f|%.0f|%.0f", args: [Double(bitPattern: 0x3FE0000000000000), Double(bitPattern: 0x3FF8000000000000), Double(bitPattern: 0x4004000000000000), Double(bitPattern: 0xBFE0000000000000), Double(bitPattern: 0x3FDFFFFFFFFFFFFF)], expected: "1|2|3|-1|0"),
        (locale: "en", pattern: "%f|%f|%f|%f", args: [Double(bitPattern: 0x3FD5555555555555), Double(bitPattern: 0x0000000000000000), Double(bitPattern: 0x40FE240C9FBE76C9), Double(bitPattern: 0x3E7AD7F29ABCAF48)], expected: "0.333333|0.000000|123456.789000|0.000000"),
        (locale: "en", pattern: "%010.2f|%+.1f|%,.2f|%#.0f|%(.2f", args: [Double(bitPattern: 0xC00C000000000000), Double(bitPattern: 0x4000000000000000), Double(bitPattern: 0x4132D687E4189375), Double(bitPattern: 0x4008000000000000), Double(bitPattern: 0xC002000000000000)], expected: "-000003.50|+2.0|1,234,567.89|3.|(2.25)"),
        (locale: "en", pattern: "%e|%.2e|%E|%e|%.0e|%12.3e|", args: [Double(bitPattern: 0x40C81CD6C8B43958), Double(bitPattern: 0x3F201F31F46ED246), Double(bitPattern: 0x3DDB7CDFD9D7BDBB), Double(bitPattern: 0x0000000000000000), Double(bitPattern: 0x4016000000000000), Double(bitPattern: 0xC023C0C9D9D3458D)], expected: "1.234568e+04|1.23e-04|1.000000E-10|0.000000e+00|6e+00|  -9.877e+00|"),
        (locale: "en", pattern: "%g|%g|%g|%g|%.3g|%G|%g", args: [Double(bitPattern: 0x3F202C9DEDBC309D), Double(bitPattern: 0x40FE240000000000), Double(bitPattern: 0x4132D68700000000), Double(bitPattern: 0x0000000000000000), Double(bitPattern: 0x3EE4F8B588E368F1), Double(bitPattern: 0x54B249AD2594C37D), Double(bitPattern: 0x4059000000000000)], expected: "0.000123400|123456|1.23457e+06|0.00000|1.00e-05|1.00000E+100|100.000"),
        (locale: "en", pattern: "%.3f|%f|%e", args: [Float(bitPattern: 0x3DCCCCCD), Float(bitPattern: 0x3FC00000), Float(bitPattern: 0x7F7FFFFF)], expected: "0.100|1.500000|3.402823e+38"),
        (locale: "en", pattern: "%f|%f|%f|%8.2f|%e|%g", args: [Double(bitPattern: 0x7FF8000000000000), Double(bitPattern: 0x7FF0000000000000), Double(bitPattern: 0xFFF0000000000000), Double(bitPattern: 0x7FF8000000000000), Double(bitPattern: 0xFFF0000000000000), Double(bitPattern: 0x7FF8000000000000)], expected: "NaN|Infinity|-Infinity|     NaN|-Infinity|NaN"),
        (locale: "en", pattern: "%s|%10s|%-10s|", args: ["\u{5E9}\u{5DC}\u{5D5}\u{5DD}", "\u{1F600}x", "\u{5D0}\u{5D1}"], expected: "\u{5E9}\u{5DC}\u{5D5}\u{5DD}|       \u{1F600}x|\u{5D0}\u{5D1}        |"),
        (locale: "ar-EG", pattern: "%d|%,d|%05d|%x", args: [1234, 1234567, 42, 255], expected: "\u{661}\u{662}\u{663}\u{664}|\u{661}\u{66C}\u{662}\u{663}\u{664}\u{66C}\u{665}\u{666}\u{667}|\u{660}\u{660}\u{660}\u{664}\u{662}|ff"),
        (locale: "ar-EG", pattern: "%.2f|%s|%s", args: [Double(bitPattern: 0x400921F9F01B866E), 12, "abc"], expected: "\u{663}\u{66B}\u{661}\u{664}|12|abc"),
        (locale: "fa", pattern: "%d|%,d", args: [1234, 1234567], expected: "\u{6F1}\u{6F2}\u{6F3}\u{6F4}|\u{6F1}\u{66C}\u{6F2}\u{6F3}\u{6F4}\u{66C}\u{6F5}\u{6F6}\u{6F7}"),
    ]
    static let stringHashes: [(String, Int32)] = [
        ("", 0),
        ("a", 97),
        ("Hello, World", -505841268),
        ("BOB", 65941),
        ("minik", 103900916),
        ("\u{5E9}\u{5DC}\u{5D5}\u{5DD}", 46563067),
        ("\u{5DE}\u{5EA}\u{5DE}\u{5D8}\u{5D9}\u{5E7}\u{5D4} \u{5DC}\u{5D1}\u{5D2}\u{5E8}\u{5D5}\u{5EA} - \u{5EA}\u{5E8}\u{5D2}\u{5D5}\u{5DC}", 1717604008),
        ("\u{1F600}", 1772899),
        ("a\u{1F600}b", 57849694),
        ("\u{0}", 0),
        ("0:1-2", 46105420),
        ("artificial_intelligence_003", 371070488),
        ("Aa", 2112),
        ("BB", 2112),
        ("polygenelubricants", -2147483648),
        ("zephyr", -705494852),
        ("kyra_original", -1996614733),
        ("The quick brown fox jumps over the lazy dog", -609428141),
        ("GENERAL_KNOWLEDGE", -1530810969),
        ("PROGRAMMING", -1130695495),
        ("SCIENCE", -1658902972),
        ("ASTRONOMY", 1062762444),
        ("PARADOX", -75521715),
        ("AI", 2088),
        ("HISTORY", 1644916852),
        ("ENGLISH", -885774768),
        ("KIDS_ARITHMETIC", -732401220),
        ("MATH", 2359048),
        ("MATRICULATION_MATH", 661018037),
    ]
    static let longHashes: [(Int64, Int32)] = [
        (0, 0),
        (1, 1),
        (-1, 0),
        (4294967296, 1),
        (-9223372036854775808, -2147483648),
        (9223372036854775807, -2147483648),
        (1760000000000, -936590951),
        (-1760000000000, -936591770),
    ]
    static let floatHashes: [(UInt32, Int32)] = [
        (0x00000000, 0),
        (0x80000000, -2147483648),
        (0x3FC00000, 1069547520),
        (0x7FC00000, 2143289344),
        (0x7FC00001, 2143289344),
        (0x7F800000, 2139095040),
        (0xC0300000, -1070596096),
    ]
    static let doubleHashes: [(UInt64, Int32)] = [
        (0x0000000000000000, 0),
        (0x8000000000000000, -2147483648),
        (0x3FF8000000000000, 1073217536),
        (0x7FF8000000000000, 2146959360),
        (0x7FF8000000000001, 2146959360),
        (0x7E37E43C8800759C, -164130400),
        (0xC006000000000000, -1073348608),
        (0x400921FB54442D18, 340593891),
    ]
    static let boolListHashes: [([Bool], Int32)] = [
        ([true, false, true], 1252360),
        ([false], 1268),
        ([], 1),
        ([true, true, true], 1252174),
        ([false, false, true], 1258126),
    ]
    static let stringListHashes: [([String], Int32)] = [
        (["a", "b"], 4066),
        ([], 1),
        (["BOB"], 65972),
        (["GENERAL_KNOWLEDGE", "PROGRAMMING", "SCIENCE", "ASTRONOMY", "PARADOX", "AI", "HISTORY", "ENGLISH", "KIDS_ARITHMETIC", "MATH", "MATRICULATION_MATH"], 2062500759),
    ]
    static let boolHashes: [(Bool, Int32)] = [(true, 1231), (false, 1237)]
    /// HashSet() + add in order, HashSet(LinkedHashSet) copy, and a default HashSet refilled in copy order.
    static let hashSetOrders: [(input: [String], added: [String], copy: [String], reload: [String])] = [
        (input: ["GENERAL_KNOWLEDGE", "PROGRAMMING", "SCIENCE", "ASTRONOMY", "PARADOX", "AI", "HISTORY", "ENGLISH", "KIDS_ARITHMETIC", "MATH", "MATRICULATION_MATH"], added: ["PARADOX", "PROGRAMMING", "MATRICULATION_MATH", "ASTRONOMY", "ENGLISH", "KIDS_ARITHMETIC", "GENERAL_KNOWLEDGE", "AI", "SCIENCE", "MATH", "HISTORY"], copy: ["PARADOX", "PROGRAMMING", "MATRICULATION_MATH", "ASTRONOMY", "ENGLISH", "KIDS_ARITHMETIC", "GENERAL_KNOWLEDGE", "AI", "SCIENCE", "MATH", "HISTORY"], reload: ["PARADOX", "PROGRAMMING", "MATRICULATION_MATH", "ASTRONOMY", "ENGLISH", "KIDS_ARITHMETIC", "GENERAL_KNOWLEDGE", "AI", "SCIENCE", "MATH", "HISTORY"]),
        (input: ["MATRICULATION_MATH", "MATH", "KIDS_ARITHMETIC", "ENGLISH", "HISTORY", "AI", "PARADOX", "ASTRONOMY", "SCIENCE", "PROGRAMMING", "GENERAL_KNOWLEDGE"], added: ["PARADOX", "MATRICULATION_MATH", "PROGRAMMING", "KIDS_ARITHMETIC", "ENGLISH", "ASTRONOMY", "GENERAL_KNOWLEDGE", "AI", "MATH", "SCIENCE", "HISTORY"], copy: ["PARADOX", "MATRICULATION_MATH", "PROGRAMMING", "KIDS_ARITHMETIC", "ENGLISH", "ASTRONOMY", "GENERAL_KNOWLEDGE", "AI", "MATH", "SCIENCE", "HISTORY"], reload: ["PARADOX", "MATRICULATION_MATH", "PROGRAMMING", "KIDS_ARITHMETIC", "ENGLISH", "ASTRONOMY", "GENERAL_KNOWLEDGE", "AI", "MATH", "SCIENCE", "HISTORY"]),
        (input: ["solo"], added: ["solo"], copy: ["solo"], reload: ["solo"]),
        (input: ["b", "a"], added: ["a", "b"], copy: ["a", "b"], reload: ["a", "b"]),
        (input: ["item0", "item1", "item2", "item3", "item4", "item5", "item6", "item7", "item8", "item9", "item10"], added: ["item0", "item2", "item1", "item8", "item7", "item9", "item4", "item3", "item10", "item6", "item5"], copy: ["item0", "item2", "item1", "item8", "item7", "item9", "item4", "item3", "item10", "item6", "item5"], reload: ["item0", "item2", "item1", "item8", "item7", "item9", "item4", "item3", "item10", "item6", "item5"]),
        (input: ["item0", "item1", "item2", "item3", "item4", "item5", "item6", "item7", "item8", "item9", "item10", "item11"], added: ["item0", "item2", "item1", "item8", "item7", "item9", "item4", "item11", "item3", "item10", "item6", "item5"], copy: ["item0", "item2", "item1", "item8", "item7", "item9", "item4", "item11", "item3", "item10", "item6", "item5"], reload: ["item0", "item2", "item1", "item8", "item7", "item9", "item4", "item11", "item3", "item10", "item6", "item5"]),
        (input: ["item0", "item1", "item2", "item3", "item4", "item5", "item6", "item7", "item8", "item9", "item10", "item11", "item12"], added: ["item0", "item2", "item1", "item12", "item11", "item10", "item8", "item7", "item9", "item4", "item3", "item6", "item5"], copy: ["item0", "item2", "item1", "item12", "item11", "item10", "item8", "item7", "item9", "item4", "item3", "item6", "item5"], reload: ["item0", "item2", "item1", "item12", "item11", "item10", "item8", "item7", "item9", "item4", "item3", "item6", "item5"]),
        (input: ["item0", "item1", "item2", "item3", "item4", "item5", "item6", "item7", "item8", "item9", "item10", "item11", "item12", "item13", "item14", "item15", "item16", "item17", "item18", "item19", "item20", "item21", "item22", "item23"], added: ["item0", "item2", "item1", "item19", "item18", "item17", "item16", "item15", "item14", "item13", "item12", "item23", "item11", "item22", "item10", "item21", "item20", "item8", "item7", "item9", "item4", "item3", "item6", "item5"], copy: ["item0", "item2", "item1", "item19", "item18", "item17", "item16", "item15", "item14", "item13", "item12", "item23", "item11", "item22", "item10", "item21", "item20", "item8", "item7", "item9", "item4", "item3", "item6", "item5"], reload: ["item0", "item2", "item1", "item19", "item18", "item17", "item16", "item15", "item14", "item13", "item12", "item23", "item11", "item22", "item10", "item21", "item20", "item8", "item7", "item9", "item4", "item3", "item6", "item5"]),
        (input: ["item0", "item1", "item2", "item3", "item4", "item5", "item6", "item7", "item8", "item9", "item10", "item11", "item12", "item13", "item14", "item15", "item16", "item17", "item18", "item19", "item20", "item21", "item22", "item23", "item24"], added: ["item0", "item2", "item1", "item19", "item18", "item17", "item16", "item15", "item14", "item13", "item12", "item11", "item10", "item24", "item23", "item22", "item21", "item20", "item8", "item7", "item9", "item4", "item3", "item6", "item5"], copy: ["item0", "item2", "item1", "item19", "item18", "item17", "item16", "item15", "item14", "item13", "item12", "item11", "item10", "item24", "item23", "item22", "item21", "item20", "item8", "item7", "item9", "item4", "item3", "item6", "item5"], reload: ["item0", "item2", "item1", "item19", "item18", "item17", "item16", "item15", "item14", "item13", "item12", "item11", "item10", "item24", "item23", "item22", "item21", "item20", "item8", "item7", "item9", "item4", "item3", "item6", "item5"]),
        (input: ["item0", "item1", "item2", "item3", "item4", "item5", "item6", "item7", "item8", "item9", "item10", "item11", "item12", "item13", "item14", "item15", "item16", "item17", "item18", "item19", "item20", "item21", "item22", "item23", "item24", "item25", "item26", "item27", "item28", "item29", "item30", "item31", "item32", "item33", "item34", "item35", "item36", "item37", "item38", "item39", "item40", "item41", "item42", "item43", "item44", "item45", "item46", "item47"], added: ["item0", "item2", "item1", "item19", "item18", "item17", "item39", "item16", "item38", "item15", "item37", "item14", "item36", "item13", "item35", "item12", "item34", "item11", "item33", "item10", "item32", "item31", "item30", "item29", "item28", "item27", "item26", "item25", "item47", "item24", "item46", "item23", "item45", "item22", "item44", "item21", "item43", "item20", "item42", "item41", "item40", "item8", "item7", "item9", "item4", "item3", "item6", "item5"], copy: ["item0", "item2", "item1", "item19", "item18", "item17", "item39", "item16", "item38", "item15", "item37", "item14", "item36", "item13", "item35", "item12", "item34", "item11", "item33", "item10", "item32", "item31", "item30", "item29", "item28", "item27", "item26", "item25", "item47", "item24", "item46", "item23", "item45", "item22", "item44", "item21", "item43", "item20", "item42", "item41", "item40", "item8", "item7", "item9", "item4", "item3", "item6", "item5"], reload: ["item0", "item2", "item1", "item19", "item18", "item17", "item39", "item16", "item38", "item15", "item37", "item14", "item36", "item13", "item35", "item12", "item34", "item11", "item33", "item10", "item32", "item31", "item30", "item29", "item28", "item27", "item26", "item25", "item47", "item24", "item46", "item23", "item45", "item22", "item44", "item21", "item43", "item20", "item42", "item41", "item40", "item8", "item7", "item9", "item4", "item3", "item6", "item5"]),
        (input: ["item0", "item1", "item2", "item3", "item4", "item5", "item6", "item7", "item8", "item9", "item10", "item11", "item12", "item13", "item14", "item15", "item16", "item17", "item18", "item19", "item20", "item21", "item22", "item23", "item24", "item25", "item26", "item27", "item28", "item29", "item30", "item31", "item32", "item33", "item34", "item35", "item36", "item37", "item38", "item39", "item40", "item41", "item42", "item43", "item44", "item45", "item46", "item47", "item48"], added: ["item0", "item2", "item1", "item39", "item38", "item37", "item36", "item35", "item34", "item33", "item32", "item31", "item30", "item29", "item28", "item27", "item26", "item25", "item24", "item23", "item22", "item21", "item20", "item19", "item18", "item17", "item16", "item15", "item14", "item13", "item12", "item11", "item10", "item48", "item47", "item46", "item45", "item44", "item43", "item42", "item41", "item40", "item8", "item7", "item9", "item4", "item3", "item6", "item5"], copy: ["item0", "item2", "item1", "item39", "item38", "item37", "item36", "item35", "item34", "item33", "item32", "item31", "item30", "item29", "item28", "item27", "item26", "item25", "item24", "item23", "item22", "item21", "item20", "item19", "item18", "item17", "item16", "item15", "item14", "item13", "item12", "item11", "item10", "item48", "item47", "item46", "item45", "item44", "item43", "item42", "item41", "item40", "item8", "item7", "item9", "item4", "item3", "item6", "item5"], reload: ["item0", "item2", "item1", "item39", "item38", "item37", "item36", "item35", "item34", "item33", "item32", "item31", "item30", "item29", "item28", "item27", "item26", "item25", "item24", "item23", "item22", "item21", "item20", "item19", "item18", "item17", "item16", "item15", "item14", "item13", "item12", "item11", "item10", "item48", "item47", "item46", "item45", "item44", "item43", "item42", "item41", "item40", "item8", "item7", "item9", "item4", "item3", "item6", "item5"]),
        (input: ["item0", "item1", "item2", "item3", "item4", "item5", "item6", "item7", "item8", "item9", "item10", "item11", "item12", "item13", "item14", "item15", "item16", "item17", "item18", "item19", "item20", "item21", "item22", "item23", "item24", "item25", "item26", "item27", "item28", "item29", "item30", "item31", "item32", "item33", "item34", "item35", "item36", "item37", "item38", "item39", "item40", "item41", "item42", "item43", "item44", "item45", "item46", "item47", "item48", "item49", "item50", "item51", "item52", "item53", "item54", "item55", "item56", "item57", "item58", "item59", "item60", "item61", "item62", "item63", "item64", "item65", "item66", "item67", "item68", "item69", "item70", "item71", "item72", "item73", "item74", "item75", "item76", "item77", "item78", "item79", "item80", "item81", "item82", "item83", "item84", "item85", "item86", "item87", "item88", "item89", "item90", "item91", "item92", "item93", "item94", "item95", "item96", "item97", "item98", "item99"], added: ["item39", "item38", "item37", "item36", "item35", "item34", "item33", "item32", "item31", "item30", "item29", "item28", "item27", "item26", "item25", "item24", "item23", "item22", "item21", "item20", "item59", "item58", "item57", "item56", "item55", "item54", "item53", "item52", "item51", "item50", "item49", "item48", "item47", "item46", "item45", "item44", "item43", "item42", "item41", "item40", "item8", "item7", "item9", "item4", "item3", "item6", "item5", "item0", "item2", "item1", "item79", "item78", "item77", "item76", "item75", "item74", "item73", "item72", "item71", "item70", "item69", "item68", "item67", "item66", "item65", "item64", "item63", "item62", "item61", "item60", "item19", "item18", "item17", "item16", "item15", "item14", "item13", "item12", "item11", "item99", "item10", "item98", "item97", "item96", "item95", "item94", "item93", "item92", "item91", "item90", "item89", "item88", "item87", "item86", "item85", "item84", "item83", "item82", "item81", "item80"], copy: ["item39", "item38", "item37", "item36", "item35", "item34", "item33", "item32", "item31", "item30", "item29", "item28", "item27", "item26", "item25", "item24", "item23", "item22", "item21", "item20", "item59", "item58", "item57", "item56", "item55", "item54", "item53", "item52", "item51", "item50", "item49", "item48", "item47", "item46", "item45", "item44", "item43", "item42", "item41", "item40", "item8", "item7", "item9", "item4", "item3", "item6", "item5", "item0", "item2", "item1", "item79", "item78", "item77", "item76", "item75", "item74", "item73", "item72", "item71", "item70", "item69", "item68", "item67", "item66", "item65", "item64", "item63", "item62", "item61", "item60", "item19", "item18", "item17", "item16", "item15", "item14", "item13", "item12", "item11", "item99", "item10", "item98", "item97", "item96", "item95", "item94", "item93", "item92", "item91", "item90", "item89", "item88", "item87", "item86", "item85", "item84", "item83", "item82", "item81", "item80"], reload: ["item39", "item38", "item37", "item36", "item35", "item34", "item33", "item32", "item31", "item30", "item29", "item28", "item27", "item26", "item25", "item24", "item23", "item22", "item21", "item20", "item59", "item58", "item57", "item56", "item55", "item54", "item53", "item52", "item51", "item50", "item49", "item48", "item47", "item46", "item45", "item44", "item43", "item42", "item41", "item40", "item8", "item7", "item9", "item4", "item3", "item6", "item5", "item0", "item2", "item1", "item79", "item78", "item77", "item76", "item75", "item74", "item73", "item72", "item71", "item70", "item69", "item68", "item67", "item66", "item65", "item64", "item63", "item62", "item61", "item60", "item19", "item18", "item17", "item16", "item15", "item14", "item13", "item12", "item11", "item99", "item10", "item98", "item97", "item96", "item95", "item94", "item93", "item92", "item91", "item90", "item89", "item88", "item87", "item86", "item85", "item84", "item83", "item82", "item81", "item80"]),
        (input: ["AaAaAaAa", "BBAaAaAa", "AaBBAaAa", "BBBBAaAa", "AaAaBBAa", "BBAaBBAa", "AaBBBBAa", "BBBBBBAa", "AaAaAaBB"], added: ["AaAaAaAa", "BBAaAaAa", "AaBBAaAa", "BBBBAaAa", "AaAaBBAa", "BBAaBBAa", "AaBBBBAa", "BBBBBBAa", "AaAaAaBB"], copy: ["AaAaAaAa", "BBAaAaAa", "AaBBAaAa", "BBBBAaAa", "AaAaBBAa", "BBAaBBAa", "AaBBBBAa", "BBBBBBAa", "AaAaAaBB"], reload: ["AaAaAaAa", "BBAaAaAa", "AaBBAaAa", "BBBBAaAa", "AaAaBBAa", "BBAaBBAa", "AaBBBBAa", "BBBBBBAa", "AaAaAaBB"]),
        (input: ["AaAaAaAa", "BBAaAaAa", "AaBBAaAa", "BBBBAaAa", "AaAaBBAa", "BBAaBBAa", "AaBBBBAa", "BBBBBBAa", "AaAaAaBB", "BBAaAaBB"], added: ["AaAaAaAa", "BBAaAaAa", "AaBBAaAa", "BBBBAaAa", "AaAaBBAa", "BBAaBBAa", "AaBBBBAa", "BBBBBBAa", "AaAaAaBB", "BBAaAaBB"], copy: ["AaAaAaAa", "BBAaAaAa", "AaBBAaAa", "BBBBAaAa", "AaAaBBAa", "BBAaBBAa", "AaBBBBAa", "BBBBBBAa", "AaAaAaBB", "BBAaAaBB"], reload: ["AaAaAaAa", "BBAaAaAa", "AaBBAaAa", "BBBBAaAa", "AaAaBBAa", "BBAaBBAa", "AaBBBBAa", "BBBBBBAa", "AaAaAaBB", "BBAaAaBB"]),
        (input: ["Aa", "BB", "C#", "item1", "AaAa", "BBBB"], added: ["Aa", "BB", "C#", "item1", "AaAa", "BBBB"], copy: ["Aa", "BB", "C#", "item1", "AaAa", "BBBB"], reload: ["Aa", "BB", "C#", "item1", "AaAa", "BBBB"]),
        (input: ["a", "b", "a", "c", "b"], added: ["a", "b", "c"], copy: ["a", "b", "c"], reload: ["a", "b", "c"]),
    ]
    /// (keys, Firebase Android child order, HashMap iteration after filling it in that order).
    static let firebaseOrders: [(keys: [String], sorted: [String], hashMap: [String])] = [
        (keys: ["b", "a", "10", "2", "007", "7", "-3", "-0", "0", "A", "-Nabc", "Zed", "234567", "99999999999", "abc", "_x", "~z", "1"], sorted: ["-3", "0", "-0", "1", "2", "7", "007", "10", "234567", "-Nabc", "99999999999", "A", "Zed", "_x", "a", "abc", "b", "~z"], hashMap: ["A", "a", "b", "-0", "abc", "-3", "0", "1", "2", "99999999999", "7", "007", "Zed", "_x", "234567", "~z", "-Nabc", "10"]),
        (keys: ["-OAbcDeFgHiJkLmNoPq", "-OAbcDeFgHiJkLmNoPr", "-OAbcDeFgHiJkLmNoPa", "UidAlphaBeta123", "uidalpha", "XK3pQ9"], sorted: ["-OAbcDeFgHiJkLmNoPa", "-OAbcDeFgHiJkLmNoPq", "-OAbcDeFgHiJkLmNoPr", "UidAlphaBeta123", "XK3pQ9", "uidalpha"], hashMap: ["-OAbcDeFgHiJkLmNoPr", "uidalpha", "-OAbcDeFgHiJkLmNoPa", "-OAbcDeFgHiJkLmNoPq", "XK3pQ9", "UidAlphaBeta123"]),
        (keys: ["ABCDEF", "234567", "ZZZZZZ", "A2B3C4", "999999", "HJKLMN", "23456A"], sorted: ["234567", "999999", "23456A", "A2B3C4", "ABCDEF", "HJKLMN", "ZZZZZZ"], hashMap: ["999999", "ZZZZZZ", "23456A", "HJKLMN", "A2B3C4", "234567", "ABCDEF"]),
        (keys: ["player0", "player1", "player2", "player3", "player4", "player5", "player6", "player7", "player8", "player9", "player10", "player11", "player12", "player13", "player14", "player15", "player16", "player17", "player18", "player19"], sorted: ["player0", "player1", "player10", "player11", "player12", "player13", "player14", "player15", "player16", "player17", "player18", "player19", "player2", "player3", "player4", "player5", "player6", "player7", "player8", "player9"], hashMap: ["player13", "player5", "player12", "player6", "player11", "player7", "player10", "player8", "player1", "player17", "player16", "player2", "player15", "player3", "player14", "player4", "player19", "player18", "player9", "player0"]),
        (keys: ["2147483647", "2147483648", "-2147483648", "-2147483649", "12345678901", "123456789012"], sorted: ["-2147483648", "2147483647", "-2147483649", "12345678901", "123456789012", "2147483648"], hashMap: ["123456789012", "2147483647", "2147483648", "12345678901", "-2147483649", "-2147483648"]),
    ]
    /// (s, s.trim(), s.isBlank(), Java s.trim()).
    static let trims: [(String, String, Bool, String)] = [
        ("  a  ", "a", false, "a"),
        ("\u{9}\u{A} a b \u{D}", "a b", false, "a b"),
        ("\u{A0}x\u{A0}", "x", false, "\u{A0}x\u{A0}"),
        ("\u{2007}y\u{202F}", "y", false, "\u{2007}y\u{202F}"),
        ("\u{3000}z\u{3000}", "z", false, "\u{3000}z\u{3000}"),
        ("\u{1C}q\u{1F}", "q", false, "q"),
        ("\u{200B}w\u{200B}", "\u{200B}w\u{200B}", false, "\u{200B}w\u{200B}"),
        ("\u{FEFF}v", "\u{FEFF}v", false, "\u{FEFF}v"),
        ("", "", true, ""),
        ("   ", "", true, ""),
        ("\u{85}x", "\u{85}x", false, "\u{85}x"),
        ("\u{1680}a", "a", false, "\u{1680}a"),
        ("\u{2028}b\u{2029}", "b", false, "\u{2028}b\u{2029}"),
        ("\u{205F}c", "c", false, "\u{205F}c"),
        ("\u{1F600} ", "\u{1F600}", false, "\u{1F600}"),
        (" \u{0} ", "\u{0}", false, ""),
        ("\u{B}\u{C}", "", true, ""),
        ("\u{180E}x", "\u{180E}x", false, "\u{180E}x"),
        (" ab cd ", "ab cd", false, "ab cd"),
        ("\u{A0}", "", true, "\u{A0}"),
        ("\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2008}\u{2009}\u{200A}", "", true, "\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2008}\u{2009}\u{200A}"),
    ]
    /// (a, b, a.compareTo(b)).
    static let compares: [(String, String, Int)] = [
        ("a", "b", -1),
        ("b", "a", 1),
        ("abc", "ab", 1),
        ("", "a", -1),
        ("\u{FFFF}", "\u{1F600}", 10178),
        ("\u{5D0}", "a", 1391),
        ("ABC", "abc", -32),
        ("same", "same", 0),
        ("a\u{1F600}", "a\u{E000}", -1987),
        ("player10", "player2", -1),
    ]
    /// (a, b, a.equals(b, ignoreCase = true)).
    static let equalsIgnoreCase: [(String, String, Bool)] = [
        ("true", "TRUE", true),
        ("True", "true", true),
        ("null", "NULL", true),
        ("\u{DF}", "SS", false),
        ("\u{130}", "i", true),
        ("abc", "abd", false),
        ("a", "aa", false),
        ("\u{1F80}", "\u{1F88}", true),
        ("\u{1FB3}", "\u{1FBC}", true),
        ("\u{3C2}", "\u{3A3}", true),
        ("\u{3C3}", "\u{3C2}", true),
        ("\u{131}", "I", true),
        ("\u{131}", "i", true),
        ("\u{212A}", "k", true),
        ("\u{1C5}", "\u{1C6}", true),
        ("\u{1C5}", "\u{1C4}", true),
        ("\u{FB00}", "FF", false),
        ("\u{149}", "\u{149}", true),
        ("\u{3A9}", "\u{3C9}", true),
        ("\u{5E9}\u{5DC}\u{5D5}\u{5DD}", "\u{5E9}\u{5DC}\u{5D5}\u{5DD}", true),
        ("\u{C0}\u{C9}\u{CE}", "\u{E0}\u{E9}\u{EE}", true),
    ]
    /// (s, s.toIntOrNull(), s.toLongOrNull()) with "nil" for null.
    static let toNumbers: [(String, String, String)] = [
        ("1", "1", "1"),
        ("+5", "5", "5"),
        ("-0", "0", "0"),
        ("007", "7", "7"),
        ("", "nil", "nil"),
        ("+", "nil", "nil"),
        ("-", "nil", "nil"),
        (" 5", "nil", "nil"),
        ("5 ", "nil", "nil"),
        ("1e3", "nil", "nil"),
        ("2147483647", "2147483647", "2147483647"),
        ("2147483648", "nil", "2147483648"),
        ("-2147483648", "-2147483648", "-2147483648"),
        ("-2147483649", "nil", "-2147483649"),
        ("9223372036854775807", "nil", "9223372036854775807"),
        ("9223372036854775808", "nil", "nil"),
        ("-9223372036854775808", "nil", "-9223372036854775808"),
        ("\u{663}", "3", "3"),
        ("\u{661}\u{662}", "12", "12"),
        ("\u{FF15}", "5", "5"),
        ("\u{6F4}\u{6F2}", "42", "42"),
        ("0x1F", "nil", "nil"),
        ("12a", "nil", "nil"),
        ("--5", "nil", "nil"),
        ("+-5", "nil", "nil"),
        ("3.0", "nil", "nil"),
        ("\u{0}", "nil", "nil"),
        ("\u{1D7D3}", "nil", "nil"),
    ]
    /// (s, s.split(",")).
    static let splits: [(String, [String])] = [
        ("a,b,c", ["a", "b", "c"]),
        ("a,,b,", ["a", "", "b", ""]),
        (",", ["", ""]),
        ("", [""]),
        ("abc", ["abc"]),
        ("x, y ,z", ["x", " y ", "z"]),
    ]
    /// (bits, toInt(), toLong(), roundToInt(), roundToLong()).
    static let floatConversions: [(UInt32, Int, Int64, Int, Int64)] = [
        (0x00000000, 0, 0, 0, 0),
        (0x80000000, 0, 0, 0, 0),
        (0x3F000000, 0, 0, 1, 1),
        (0xBF000000, 0, 0, 0, 0),
        (0x3FC00000, 1, 1, 2, 2),
        (0x40200000, 2, 2, 3, 3),
        (0xC0200000, -2, -2, -2, -2),
        (0x3EFFFFFF, 0, 0, 0, 0),
        (0xBEFFFFFF, 0, 0, 0, 0),
        (0x501502F9, 2147483647, 10000000000, 2147483647, 10000000000),
        (0xD01502F9, -2147483648, -10000000000, -2147483648, -10000000000),
        (0x4F4AA7E2, 2147483647, 3400000000, 2147483647, 3400000000),
        (0x4EFFFFFF, 2147483520, 2147483520, 2147483520, 2147483520),
        (0x4F000000, 2147483647, 2147483648, 2147483647, 2147483648),
        (0xCF000000, -2147483648, -2147483648, -2147483648, -2147483648),
        (0x5F000000, 2147483647, 9223372036854775807, 2147483647, 9223372036854775807),
        (0x60AD78EC, 2147483647, 9223372036854775807, 2147483647, 9223372036854775807),
        (0xE0AD78EC, -2147483648, -9223372036854775808, -2147483648, -9223372036854775808),
        (0x7F800000, 2147483647, 9223372036854775807, 2147483647, 9223372036854775807),
        (0xFF800000, -2147483648, -9223372036854775808, -2147483648, -9223372036854775808),
        (0x00000001, 0, 0, 0, 0),
        (0x4AFFFFFF, 8388607, 8388607, 8388608, 8388608),
        (0x4B000000, 8388608, 8388608, 8388608, 8388608),
        (0x4B7FFFFF, 16777215, 16777215, 16777215, 16777215),
        (0xCB800000, -16777216, -16777216, -16777216, -16777216),
        (0x42F6E979, 123, 123, 123, 123),
        (0xC2F6E979, -123, -123, -123, -123),
    ]
    /// (bits, toInt(), toLong(), roundToInt(), roundToLong()).
    static let doubleConversions: [(UInt64, Int, Int64, Int, Int64)] = [
        (0x0000000000000000, 0, 0, 0, 0),
        (0x8000000000000000, 0, 0, 0, 0),
        (0x3FE0000000000000, 0, 0, 1, 1),
        (0xBFE0000000000000, 0, 0, 0, 0),
        (0x3FF8000000000000, 1, 1, 2, 2),
        (0x4004000000000000, 2, 2, 3, 3),
        (0xC004000000000000, -2, -2, -2, -2),
        (0x3FDFFFFFFFFFFFFF, 0, 0, 0, 0),
        (0xBFDFFFFFFFFFFFFF, 0, 0, 0, 0),
        (0x4202A05F20000000, 2147483647, 10000000000, 2147483647, 10000000000),
        (0xC202A05F20000000, -2147483648, -10000000000, -2147483648, -10000000000),
        (0x41DFFFFFFFD9999A, 2147483647, 2147483647, 2147483647, 2147483647),
        (0x41DFFFFFFFE66666, 2147483647, 2147483647, 2147483647, 2147483648),
        (0xC1E00000000CCCCD, -2147483648, -2147483648, -2147483648, -2147483648),
        (0xC1E0000000133333, -2147483648, -2147483648, -2147483648, -2147483649),
        (0x43E0000000000000, 2147483647, 9223372036854775807, 2147483647, 9223372036854775807),
        (0x43E158E460913D00, 2147483647, 9223372036854775807, 2147483647, 9223372036854775807),
        (0xC3E158E460913D00, -2147483648, -9223372036854775808, -2147483648, -9223372036854775808),
        (0x7FF0000000000000, 2147483647, 9223372036854775807, 2147483647, 9223372036854775807),
        (0xFFF0000000000000, -2147483648, -9223372036854775808, -2147483648, -9223372036854775808),
        (0x0000000000000001, 0, 0, 0, 0),
        (0x432FFFFFFFFFFFFF, 2147483647, 4503599627370495, 2147483647, 4503599627370496),
        (0x4330000000000000, 2147483647, 4503599627370496, 2147483647, 4503599627370496),
        (0xC05EDD2F1A9FBE77, -123, -123, -123, -123),
        (0x42799C82CC000B33, 2147483647, 1760000000000, 2147483647, 1760000000001),
    ]
    /// Math.round(float) including NaN (0).
    static let mathRoundFloat: [(UInt32, Int32)] = [
        (0x00000000, 0),
        (0x80000000, 0),
        (0x3F000000, 1),
        (0xBF000000, 0),
        (0x3FC00000, 2),
        (0x40200000, 3),
        (0xC0200000, -2),
        (0x3EFFFFFF, 0),
        (0xBEFFFFFF, 0),
        (0x501502F9, 2147483647),
        (0xD01502F9, -2147483648),
        (0x4F4AA7E2, 2147483647),
        (0x4EFFFFFF, 2147483520),
        (0x4F000000, 2147483647),
        (0xCF000000, -2147483648),
        (0x5F000000, 2147483647),
        (0x60AD78EC, 2147483647),
        (0xE0AD78EC, -2147483648),
        (0x7F800000, 2147483647),
        (0xFF800000, -2147483648),
        (0x00000001, 0),
        (0x4AFFFFFF, 8388608),
        (0x4B000000, 8388608),
        (0x4B7FFFFF, 16777215),
        (0xCB800000, -16777216),
        (0x42F6E979, 123),
        (0xC2F6E979, -123),
        (0x7FC00000, 0),
    ]
    static let mathRoundDouble: [(UInt64, Int64)] = [
        (0x0000000000000000, 0),
        (0x8000000000000000, 0),
        (0x3FE0000000000000, 1),
        (0xBFE0000000000000, 0),
        (0x3FF8000000000000, 2),
        (0x4004000000000000, 3),
        (0xC004000000000000, -2),
        (0x3FDFFFFFFFFFFFFF, 0),
        (0xBFDFFFFFFFFFFFFF, 0),
        (0x4202A05F20000000, 10000000000),
        (0xC202A05F20000000, -10000000000),
        (0x41DFFFFFFFD9999A, 2147483647),
        (0x41DFFFFFFFE66666, 2147483648),
        (0xC1E00000000CCCCD, -2147483648),
        (0xC1E0000000133333, -2147483649),
        (0x43E0000000000000, 9223372036854775807),
        (0x43E158E460913D00, 9223372036854775807),
        (0xC3E158E460913D00, -9223372036854775808),
        (0x7FF0000000000000, 9223372036854775807),
        (0xFFF0000000000000, -9223372036854775808),
        (0x0000000000000001, 0),
        (0x432FFFFFFFFFFFFF, 4503599627370496),
        (0x4330000000000000, 4503599627370496),
        (0xC05EDD2F1A9FBE77, -123),
        (0x42799C82CC000B33, 1760000000001),
        (0x7FF8000000000000, 0),
    ]
    /// (a, b, Math.min, Math.max) as bit patterns.
    static let floatMinMax: [(UInt32, UInt32, UInt32, UInt32)] = [
        (0x00000000, 0x80000000, 0x80000000, 0x00000000),
        (0x80000000, 0x00000000, 0x80000000, 0x00000000),
        (0x7FC00000, 0x3F800000, 0x7FC00000, 0x7FC00000),
        (0x3F800000, 0x7FC00000, 0x7FC00000, 0x7FC00000),
        (0x3F800000, 0x40000000, 0x3F800000, 0x40000000),
        (0xBF800000, 0xC0000000, 0xC0000000, 0xBF800000),
        (0x40400000, 0x40400000, 0x40400000, 0x40400000),
        (0x80000000, 0x80000000, 0x80000000, 0x80000000),
    ]
    static let doubleMinMax: [(UInt64, UInt64, UInt64, UInt64)] = [
        (0x0000000000000000, 0x8000000000000000, 0x8000000000000000, 0x0000000000000000),
        (0x8000000000000000, 0x0000000000000000, 0x8000000000000000, 0x0000000000000000),
        (0x7FF8000000000000, 0x3FF0000000000000, 0x7FF8000000000000, 0x7FF8000000000000),
        (0x3FF0000000000000, 0x7FF8000000000000, 0x7FF8000000000000, 0x7FF8000000000000),
        (0x3FF0000000000000, 0x4000000000000000, 0x3FF0000000000000, 0x4000000000000000),
    ]
    /// (bits, Math.signum(float)).
    static let floatSigns: [(UInt32, UInt32)] = [
        (0x00000000, 0x00000000),
        (0x80000000, 0x80000000),
        (0x40200000, 0x3F800000),
        (0xC0200000, 0xBF800000),
        (0x7FC00000, 0x7FC00000),
        (0xFF800000, 0xBF800000),
        (0x00000001, 0x3F800000),
    ]
    /// (a, n, Math.floorMod, Math.floorDiv) on Long.
    static let floorModDiv: [(Int64, Int64, Int64, Int64)] = [
        (7, 3, 1, 2),
        (-7, 3, 2, -3),
        (7, -3, -2, -3),
        (-7, -3, -1, 2),
        (0, 5, 0, 0),
        (-1, 1000, 999, -1),
        (-9223372036854775808, -1, 0, -9223372036854775808),
        (13, 13, 0, 1),
        (-13, 13, 0, -1),
    ]
    /// (bits, coerceIn(-1, 1)) on Float.
    static let floatCoerce: [(UInt32, UInt32)] = [
        (0xC0000000, 0xBF800000),
        (0xBF800000, 0xBF800000),
        (0x00000000, 0x00000000),
        (0x3F000000, 0x3F000000),
        (0x3F800000, 0x3F800000),
        (0x40000000, 0x3F800000),
        (0x7FC00000, 0x7FC00000),
        (0x80000000, 0x80000000),
    ]
    /// Math.toDegrees(x) for x in radians.
    static let toDegrees: [(UInt64, UInt64)] = [
        (0x0000000000000000, 0x0000000000000000),
        (0x3FF0000000000000, 0x404CA5DC1A63C1F8),
        (0x400921FB54442D18, 0x4066800000000000),
        (0xBFE0000000000000, 0xC03CA5DC1A63C1F8),
        (0x3F50624DD2F1A9FC, 0x3FAD55DF566A3F75),
        (0x405EDD2F1A9FBE77, 0x40BBA181FC44D305),
    ]
    /// Floats sortedBy { it } (Float.compareTo total order) as bit patterns.
    static let floatSort: (input: [UInt32], sorted: [UInt32], maxBy: UInt32, minBy: UInt32) = (
        input: [0x40400000, 0x80000000, 0x7FC00000, 0x00000000, 0xBF800000, 0x7F800000, 0x40000000, 0x7FC00000, 0x80000000, 0x3F800000],
        sorted: [0xBF800000, 0x80000000, 0x80000000, 0x00000000, 0x3F800000, 0x40000000, 0x40400000, 0x7F800000, 0x7FC00000, 0x7FC00000],
        maxBy: 0x7FC00000,
        minBy: 0xBF800000)
    /// Strings sortedBy { it } (String.compareTo, UTF-16 order).
    static let stringSort: (input: [String], sorted: [String], descending: [String]) = (
        input: ["b", "\u{FFFF}", "\u{1F600}", "a", "B", "\u{E000}", "aa", "", "\u{5D0}"],
        sorted: ["", "B", "a", "aa", "b", "\u{5D0}", "\u{1F600}", "\u{E000}", "\u{FFFF}"],
        descending: ["\u{FFFF}", "\u{E000}", "\u{1F600}", "\u{5D0}", "b", "aa", "a", "B", ""])
    /// Words sortedByDescending { it.length } and sortedBy { it.length } (stable).
    static let lengthSort: (input: [String], ascending: [String], descending: [String], maxBy: String, minBy: String) = (
        input: ["bb", "a", "ccc", "dd", "e", "fff", "gg"],
        ascending: ["a", "e", "bb", "dd", "gg", "ccc", "fff"],
        descending: ["ccc", "fff", "bb", "dd", "gg", "a", "e"],
        maxBy: "ccc", minBy: "a")
    /// windowed / chunked.
    static let windows: [(size: Int, step: Int, partial: Bool, result: [[Int]])] = [
        (size: 3, step: 1, partial: false, result: [[1, 2, 3], [2, 3, 4], [3, 4, 5], [4, 5, 6], [5, 6, 7]]),
        (size: 3, step: 2, partial: true, result: [[1, 2, 3], [3, 4, 5], [5, 6, 7], [7]]),
        (size: 2, step: 3, partial: false, result: [[1, 2], [4, 5]]),
        (size: 7, step: 1, partial: false, result: [[1, 2, 3, 4, 5, 6, 7]]),
        (size: 8, step: 1, partial: true, result: [[1, 2, 3, 4, 5, 6, 7], [2, 3, 4, 5, 6, 7], [3, 4, 5, 6, 7], [4, 5, 6, 7], [5, 6, 7], [6, 7], [7]]),
        (size: 3, step: 3, partial: true, result: [[1, 2, 3], [4, 5, 6], [7]]),
    ]
    /// (input, JSONObject/JSONArray(input).toString()).
    static let jsonRoundTrips: [(String, String)] = [
        ("{\"version\":1,\"id\":\"abc\",\"seed\":1760000000000,\"number\":3,\"created\":1760000000123,\"matchSeconds\":0}", "{\"version\":1,\"id\":\"abc\",\"seed\":1760000000000,\"number\":3,\"created\":1760000000123,\"matchSeconds\":0}"),
        ("{\"a\":1.0,\"b\":1.5,\"c\":-0.0,\"d\":-0,\"e\":012,\"f\":0x1F,\"g\":08,\"h\":1e5,\"i\":123456789012,\"j\":9223372036854775808}", "{\"a\":1,\"b\":1.5,\"c\":-0,\"d\":0,\"e\":10,\"f\":31,\"g\":8,\"h\":100000,\"i\":123456789012,\"j\":9223372036854775807}"),
        ("{a: 'single', b = 2; c => true, // comment\u{A}            d: null, /* block */ e: [1,,2,], f: #hash\u{A}            \"x\"}", "{\"a\":\"single\",\"b\":2,\"c\":true,\"d\":null,\"e\":[1,null,2,null],\"f\":\"x\"}"),
        ("[1, \"two\", 3.25, true, null, {\"k\": [] }, -7, 2147483648, 1.0E300, \"\u{E9}\\/\\\"\\\\\"]", "[1,\"two\",3.25,true,null,{\"k\":[]},-7,2147483648,1.0E300,\"\u{E9}\\/\\\"\\\\\"]"),
        ("  {\"nested\":{\"deep\":{\"list\":[{\"x\":1},{\"y\":[2,3]}]}}} trailing", "{\"nested\":{\"deep\":{\"list\":[{\"x\":1},{\"y\":[2,3]}]}}}"),
        ("{\"name\":\"\u{5E9}\u{5DC}\u{5D5}\u{5DD}\",\"emoji\":\"\u{1F600}\",\"ctl\":\"a\\tb\\nc\\u0001d\\u001fe\"}", "{\"name\":\"\u{5E9}\u{5DC}\u{5D5}\u{5DD}\",\"emoji\":\"\u{1F600}\",\"ctl\":\"a\\tb\\nc\\u0001d\\u001fe\"}"),
        ("[,]", "[null,null]"),
        ("[;1;]", "[null,1,null]"),
        ("{\"dup\":1,\"dup\":2,\"other\":3}", "{\"dup\":2,\"other\":3}"),
        ("[0.1, 100.0, 1.0E7, 0.001, 1.0E-4, 12.5, 2.0E23]", "[0.1,100,10000000,0.001,1.0E-4,12.5,1.9999999999999998E23]"),
    ]
    /// (input, JSONException message) for JSONObject(input) (JSONArray when it starts with '[').
    static let jsonFailures: [(String, String)] = [
        ("{\"a\":NaN}", "Forbidden numeric value: NaN"),
        ("{\"a\":1", "Unterminated object at character 6 of {\"a\":1"),
        ("{\"a\" 1}", "Expected ':' after a at character 6 of {\"a\" 1}"),
        ("[1 2]", "Unterminated array at character 4 of [1 2]"),
        ("{1:2}", "Names must be strings, but 1 is of type java.lang.Integer at character 2 of {1:2}"),
        ("", "End of input at character 0 of "),
        ("  ", "End of input at character 2 of   "),
        ("nul", "Value nul of type java.lang.String cannot be converted to JSONObject"),
        ("{\"a\":\"x", "Unterminated string at character 7 of {\"a\":\"x"),
        ("{\"k\":\"\\u12\"}", "Invalid escape sequence: 12\"} at character 12 of {\"k\":\"\\u12\"}"),
        ("[1,2", "Unterminated array at character 4 of [1,2"),
        ("{\"a\":1}}", "OK"),
        ("{\"a\":[}", "Expected literal value at character 6 of {\"a\":[}"),
    ]
    /// Getter results on JSONObject(jsonGetterInput): (operation:name, result) where doubles are D:<bits>
    /// and JSONExceptions EXC:<message>.
    static let jsonGetterInput = "{\"i\":5,\"l\":123456789012,\"d\":12.7,\"nd\":-12.7,\"s\":\"12.7\",\"sb\":\"TRUE\",\"n\":null,\"b\":true,\"o\":{\"x\":1},\"a\":[1,\"2\"],\"big\":1e20,\"neg\":-1e20,\"str\":\"abc\",\"tf\":\"false\"}"
    static let jsonGetters: [(String, String)] = [
        ("getInt:i", "5"),
        ("getLong:i", "5"),
        ("getDouble:i", "D:0x4014000000000000"),
        ("getString:i", "5"),
        ("getBoolean:i", "EXC:Value 5 at i of type java.lang.Integer cannot be converted to boolean"),
        ("optString:i", "5"),
        ("optInt:i", "5"),
        ("optLong:i", "5"),
        ("optDouble:i", "D:0x4014000000000000"),
        ("optBoolean:i", "true"),
        ("isNull:i", "false"),
        ("has:i", "true"),
        ("getInt:l", "-1097262572"),
        ("getLong:l", "123456789012"),
        ("getDouble:l", "D:0x423CBE991A140000"),
        ("getString:l", "123456789012"),
        ("getBoolean:l", "EXC:Value 123456789012 at l of type java.lang.Long cannot be converted to boolean"),
        ("optString:l", "123456789012"),
        ("optInt:l", "-1097262572"),
        ("optLong:l", "123456789012"),
        ("optDouble:l", "D:0x423CBE991A140000"),
        ("optBoolean:l", "true"),
        ("isNull:l", "false"),
        ("has:l", "true"),
        ("getInt:d", "12"),
        ("getLong:d", "12"),
        ("getDouble:d", "D:0x4029666666666666"),
        ("getString:d", "12.7"),
        ("getBoolean:d", "EXC:Value 12.7 at d of type java.lang.Double cannot be converted to boolean"),
        ("optString:d", "12.7"),
        ("optInt:d", "12"),
        ("optLong:d", "12"),
        ("optDouble:d", "D:0x4029666666666666"),
        ("optBoolean:d", "true"),
        ("isNull:d", "false"),
        ("has:d", "true"),
        ("getInt:nd", "-12"),
        ("getLong:nd", "-12"),
        ("getDouble:nd", "D:0xC029666666666666"),
        ("getString:nd", "-12.7"),
        ("getBoolean:nd", "EXC:Value -12.7 at nd of type java.lang.Double cannot be converted to boolean"),
        ("optString:nd", "-12.7"),
        ("optInt:nd", "-12"),
        ("optLong:nd", "-12"),
        ("optDouble:nd", "D:0xC029666666666666"),
        ("optBoolean:nd", "true"),
        ("isNull:nd", "false"),
        ("has:nd", "true"),
        ("getInt:s", "12"),
        ("getLong:s", "12"),
        ("getDouble:s", "D:0x4029666666666666"),
        ("getString:s", "12.7"),
        ("getBoolean:s", "EXC:Value 12.7 at s of type java.lang.String cannot be converted to boolean"),
        ("optString:s", "12.7"),
        ("optInt:s", "12"),
        ("optLong:s", "12"),
        ("optDouble:s", "D:0x4029666666666666"),
        ("optBoolean:s", "true"),
        ("isNull:s", "false"),
        ("has:s", "true"),
        ("getInt:sb", "EXC:Value TRUE at sb of type java.lang.String cannot be converted to int"),
        ("getLong:sb", "EXC:Value TRUE at sb of type java.lang.String cannot be converted to long"),
        ("getDouble:sb", "EXC:Value TRUE at sb of type java.lang.String cannot be converted to double"),
        ("getString:sb", "TRUE"),
        ("getBoolean:sb", "true"),
        ("optString:sb", "TRUE"),
        ("optInt:sb", "-9"),
        ("optLong:sb", "-9"),
        ("optDouble:sb", "D:0xC023000000000000"),
        ("optBoolean:sb", "true"),
        ("isNull:sb", "false"),
        ("has:sb", "true"),
        ("getInt:n", "EXC:Value null at n of type org.json.JSONObject$1 cannot be converted to int"),
        ("getLong:n", "EXC:Value null at n of type org.json.JSONObject$1 cannot be converted to long"),
        ("getDouble:n", "EXC:Value null at n of type org.json.JSONObject$1 cannot be converted to double"),
        ("getString:n", "null"),
        ("getBoolean:n", "EXC:Value null at n of type org.json.JSONObject$1 cannot be converted to boolean"),
        ("optString:n", "null"),
        ("optInt:n", "-9"),
        ("optLong:n", "-9"),
        ("optDouble:n", "D:0xC023000000000000"),
        ("optBoolean:n", "true"),
        ("isNull:n", "true"),
        ("has:n", "true"),
        ("getInt:b", "EXC:Value true at b of type java.lang.Boolean cannot be converted to int"),
        ("getLong:b", "EXC:Value true at b of type java.lang.Boolean cannot be converted to long"),
        ("getDouble:b", "EXC:Value true at b of type java.lang.Boolean cannot be converted to double"),
        ("getString:b", "true"),
        ("getBoolean:b", "true"),
        ("optString:b", "true"),
        ("optInt:b", "-9"),
        ("optLong:b", "-9"),
        ("optDouble:b", "D:0xC023000000000000"),
        ("optBoolean:b", "true"),
        ("isNull:b", "false"),
        ("has:b", "true"),
        ("getInt:o", "EXC:Value {\"x\":1} at o of type org.json.JSONObject cannot be converted to int"),
        ("getLong:o", "EXC:Value {\"x\":1} at o of type org.json.JSONObject cannot be converted to long"),
        ("getDouble:o", "EXC:Value {\"x\":1} at o of type org.json.JSONObject cannot be converted to double"),
        ("getString:o", "{\"x\":1}"),
        ("getBoolean:o", "EXC:Value {\"x\":1} at o of type org.json.JSONObject cannot be converted to boolean"),
        ("optString:o", "{\"x\":1}"),
        ("optInt:o", "-9"),
        ("optLong:o", "-9"),
        ("optDouble:o", "D:0xC023000000000000"),
        ("optBoolean:o", "true"),
        ("isNull:o", "false"),
        ("has:o", "true"),
        ("getInt:a", "EXC:Value [1,\"2\"] at a of type org.json.JSONArray cannot be converted to int"),
        ("getLong:a", "EXC:Value [1,\"2\"] at a of type org.json.JSONArray cannot be converted to long"),
        ("getDouble:a", "EXC:Value [1,\"2\"] at a of type org.json.JSONArray cannot be converted to double"),
        ("getString:a", "[1,\"2\"]"),
        ("getBoolean:a", "EXC:Value [1,\"2\"] at a of type org.json.JSONArray cannot be converted to boolean"),
        ("optString:a", "[1,\"2\"]"),
        ("optInt:a", "-9"),
        ("optLong:a", "-9"),
        ("optDouble:a", "D:0xC023000000000000"),
        ("optBoolean:a", "true"),
        ("isNull:a", "false"),
        ("has:a", "true"),
        ("getInt:big", "2147483647"),
        ("getLong:big", "9223372036854775807"),
        ("getDouble:big", "D:0x4415AF1D78B58C40"),
        ("getString:big", "1.0E20"),
        ("getBoolean:big", "EXC:Value 1.0E20 at big of type java.lang.Double cannot be converted to boolean"),
        ("optString:big", "1.0E20"),
        ("optInt:big", "2147483647"),
        ("optLong:big", "9223372036854775807"),
        ("optDouble:big", "D:0x4415AF1D78B58C40"),
        ("optBoolean:big", "true"),
        ("isNull:big", "false"),
        ("has:big", "true"),
        ("getInt:neg", "-2147483648"),
        ("getLong:neg", "-9223372036854775808"),
        ("getDouble:neg", "D:0xC415AF1D78B58C40"),
        ("getString:neg", "-1.0E20"),
        ("getBoolean:neg", "EXC:Value -1.0E20 at neg of type java.lang.Double cannot be converted to boolean"),
        ("optString:neg", "-1.0E20"),
        ("optInt:neg", "-2147483648"),
        ("optLong:neg", "-9223372036854775808"),
        ("optDouble:neg", "D:0xC415AF1D78B58C40"),
        ("optBoolean:neg", "true"),
        ("isNull:neg", "false"),
        ("has:neg", "true"),
        ("getInt:str", "EXC:Value abc at str of type java.lang.String cannot be converted to int"),
        ("getLong:str", "EXC:Value abc at str of type java.lang.String cannot be converted to long"),
        ("getDouble:str", "EXC:Value abc at str of type java.lang.String cannot be converted to double"),
        ("getString:str", "abc"),
        ("getBoolean:str", "EXC:Value abc at str of type java.lang.String cannot be converted to boolean"),
        ("optString:str", "abc"),
        ("optInt:str", "-9"),
        ("optLong:str", "-9"),
        ("optDouble:str", "D:0xC023000000000000"),
        ("optBoolean:str", "true"),
        ("isNull:str", "false"),
        ("has:str", "true"),
        ("getInt:tf", "EXC:Value false at tf of type java.lang.String cannot be converted to int"),
        ("getLong:tf", "EXC:Value false at tf of type java.lang.String cannot be converted to long"),
        ("getDouble:tf", "EXC:Value false at tf of type java.lang.String cannot be converted to double"),
        ("getString:tf", "false"),
        ("getBoolean:tf", "false"),
        ("optString:tf", "false"),
        ("optInt:tf", "-9"),
        ("optLong:tf", "-9"),
        ("optDouble:tf", "D:0xC023000000000000"),
        ("optBoolean:tf", "false"),
        ("isNull:tf", "false"),
        ("has:tf", "true"),
        ("getInt:missing", "EXC:No value for missing"),
        ("getLong:missing", "EXC:No value for missing"),
        ("getDouble:missing", "EXC:No value for missing"),
        ("getString:missing", "EXC:No value for missing"),
        ("getBoolean:missing", "EXC:No value for missing"),
        ("optString:missing", "fb"),
        ("optInt:missing", "-9"),
        ("optLong:missing", "-9"),
        ("optDouble:missing", "D:0xC023000000000000"),
        ("optBoolean:missing", "true"),
        ("isNull:missing", "true"),
        ("has:missing", "false"),
        ("keys", "i,l,d,nd,s,sb,n,b,o,a,big,neg,str,tf"),
        ("length", "14"),
    ]
    static let jsonBuilt = "{\"version\":1,\"id\":\"uuid\\/with\\\"quote\",\"seed\":1760000000000,\"number\":3,\"created\":1760000000123,\"matchSeconds\":0,\"half\":0.5,\"f\":1.25,\"negZero\":-0,\"flag\":true,\"text\":\"\u{5E9}\u{5DC}\u{5D5}\u{5DD}\\n\u{1F600}\",\"teams\":[{\"id\":0,\"color\":-16777216,\"roster\":[\"bob\",\"maya\"]}]}"
    static let jsonSnapshot = "[0,2.5,3,0.30000000000000004,1.0E-5,1.23456789E7]"
    static let jsonNaNArrayToString: String? = nil
    static let jsonSnapshotBack: [UInt64] = [0x0000000000000000, 0x4004000000000000, 0x4008000000000000, 0x3FD3333333333334, 0x3EE4F8B588E368F1, 0x41678C29DCCCCCCD]
    /// Fresh Random(seed) per script for seeds built like the app builds them.
    static let appSeedScripts: [(seed: Int64, steps: [(String, String)])] = [
        (seed: 5569068490923650336, steps: [("float", "0x3F3C5E7A"), ("until:100", "66"), ("bool", "false"), ("lrange:-700:701", "-541"), ("double", "0x3FE9954F1C2AD5CC"), ("int", "682738294"), ("range:-4:5", "1"), ("float", "0x3E46B9F0"), ("float", "0x3F447AF4"), ("until:3", "2"), ("lrange:0:1700", "552"), ("bool", "true")]),
        (seed: 5569068490923650336, steps: [("long", "-4873323383286519483"), ("lrange:0:1700", "761"), ("float", "0x3ED5EC9C"), ("float", "0x3F4CAA78"), ("float", "0x3F055AB9"), ("luntil:841", "230"), ("luntil:521", "357"), ("luntil:1801", "1410")]),
        (seed: 18663993446797140, steps: [("float", "0x3EF40EFC"), ("until:100", "78"), ("bool", "false"), ("lrange:-700:701", "-431"), ("double", "0x3FD4CC3412E1CCFA"), ("int", "-141266231"), ("range:-4:5", "-4"), ("float", "0x3E424C18"), ("float", "0x3DE8B2F8"), ("until:3", "2"), ("lrange:0:1700", "88"), ("bool", "true")]),
        (seed: 18663993446797140, steps: [("long", "8793135965602795332"), ("lrange:0:1700", "136"), ("float", "0x3F242760"), ("float", "0x3EA661A0"), ("float", "0x3E38733C"), ("luntil:841", "443"), ("luntil:521", "515"), ("luntil:1801", "949")]),
        (seed: 6287386602245427795, steps: [("float", "0x3F041A32"), ("until:100", "56"), ("bool", "true"), ("lrange:-700:701", "0"), ("double", "0x3FEA07B46DB54661"), ("int", "1499041927"), ("range:-4:5", "-2"), ("float", "0x3EA738D4"), ("float", "0x3F6B5A5F"), ("until:3", "2"), ("lrange:0:1700", "431"), ("bool", "false")]),
        (seed: 6287386602245427795, steps: [("long", "-8927767916912928983"), ("lrange:0:1700", "226"), ("float", "0x3C575840"), ("float", "0x3F503DA3"), ("float", "0x3F36A8CC"), ("luntil:841", "261"), ("luntil:521", "164"), ("luntil:1801", "616")]),
        (seed: 4848196285111306580, steps: [("float", "0x3F38CD15"), ("until:100", "13"), ("bool", "true"), ("lrange:-700:701", "-546"), ("double", "0x3FE7C0D414C8770F"), ("int", "-1760282898"), ("range:-4:5", "4"), ("float", "0x3D167710"), ("float", "0x3F4B0099"), ("until:3", "0"), ("lrange:0:1700", "1658"), ("bool", "false")]),
        (seed: 4848196285111306580, steps: [("long", "-5130420834407780830"), ("lrange:0:1700", "1647"), ("float", "0x3F33F103"), ("float", "0x3F3E06A0"), ("float", "0x3F190EE1"), ("luntil:841", "232"), ("luntil:521", "206"), ("luntil:1801", "813")]),
        (seed: 1413823268, steps: [("float", "0x3DE55158"), ("until:100", "34"), ("bool", "true"), ("lrange:-700:701", "502"), ("double", "0x3FEFE4FB7E946BD8"), ("int", "-26589865"), ("range:-4:5", "0"), ("float", "0x3E8DD962"), ("float", "0x3EB07BFA"), ("until:3", "1"), ("lrange:0:1700", "629"), ("bool", "false")]),
        (seed: 1413823268, steps: [("long", "2065510745945896084"), ("lrange:0:1700", "950"), ("float", "0x3F589745"), ("float", "0x3F7F27DB"), ("float", "0x3F528D7B"), ("luntil:841", "42"), ("luntil:521", "156"), ("luntil:1801", "374")]),
        (seed: -1759016904014, steps: [("float", "0x3EF65188"), ("until:100", "69"), ("bool", "true"), ("lrange:-700:701", "-35"), ("double", "0x3FE2A48485F09212"), ("int", "-510839548"), ("range:-4:5", "1"), ("float", "0x3E44347C"), ("float", "0x3EE4C6CC"), ("until:3", "1"), ("lrange:0:1700", "15"), ("bool", "true")]),
        (seed: -1759016904014, steps: [("long", "8874559566143078178"), ("lrange:0:1700", "113"), ("float", "0x3E4A646C"), ("float", "0x3F152424"), ("float", "0x3F3E1242"), ("luntil:841", "19"), ("luntil:521", "266"), ("luntil:1801", "525")]),
        (seed: 1760369496506, steps: [("float", "0x3EA29FDA"), ("until:100", "51"), ("bool", "true"), ("lrange:-700:701", "-636"), ("double", "0x3FE3016B97363772"), ("int", "-1754237961"), ("range:-4:5", "2"), ("float", "0x3F1A4858"), ("float", "0x3F5E3DD9"), ("until:3", "1"), ("lrange:0:1700", "1136"), ("bool", "true")]),
        (seed: 1760369496506, steps: [("long", "5859162735407956583"), ("lrange:0:1700", "15"), ("float", "0x3D981698"), ("float", "0x3F180B5C"), ("float", "0x3F66C6EE"), ("luntil:841", "459"), ("luntil:521", "463"), ("luntil:1801", "1252")]),
        (seed: 12345, steps: [("float", "0x3F4551E7"), ("until:100", "41"), ("bool", "true"), ("lrange:-700:701", "357"), ("double", "0x3FED29365E8C1244"), ("int", "407561407"), ("range:-4:5", "3"), ("float", "0x3EF39102"), ("float", "0x3ECA4D4E"), ("until:3", "2"), ("lrange:0:1700", "521"), ("bool", "true")]),
        (seed: 12345, steps: [("long", "-4228343866523403918"), ("lrange:0:1700", "1020"), ("float", "0x3F27A2D8"), ("float", "0x3F6949B2"), ("float", "0x3F518248"), ("luntil:841", "138"), ("luntil:521", "219"), ("luntil:1801", "1360")]),
        (seed: -7, steps: [("float", "0x3DEB5B40"), ("until:100", "63"), ("bool", "true"), ("lrange:-700:701", "236"), ("double", "0x3FE6BD79EA836E91"), ("int", "-1632324291"), ("range:-4:5", "2"), ("float", "0x3F2195CE"), ("float", "0x3E829702"), ("until:3", "0"), ("lrange:0:1700", "1486"), ("bool", "false")]),
        (seed: -7, steps: [("long", "2119902869140302831"), ("lrange:0:1700", "1413"), ("float", "0x3F561CE1"), ("float", "0x3F35EBCF"), ("float", "0x3EA0DBA4"), ("luntil:841", "628"), ("luntil:521", "94"), ("luntil:1801", "572")]),
        (seed: 42, steps: [("float", "0x3E67BF30"), ("until:100", "40"), ("bool", "true"), ("lrange:-700:701", "515"), ("double", "0x3FC35ED51F0E4128"), ("int", "-95941416"), ("range:-4:5", "0"), ("float", "0x3D82F480"), ("float", "0x3F17B602"), ("until:3", "1"), ("lrange:0:1700", "1587"), ("bool", "false")]),
        (seed: 42, steps: [("long", "4174779793377534016"), ("lrange:0:1700", "1690"), ("float", "0x3E8A9CE2"), ("float", "0x3E1AF6A8"), ("float", "0x3F787209"), ("luntil:841", "381"), ("luntil:521", "153"), ("luntil:1801", "1267")]),
    ]
    /// The KotlinRandom tables of specs 02 (A.10), 15 and 17, recomputed exactly (seedInt: Random(Int)).
    static let specScripts: [(label: String, seedLong: Int64?, seedInt: Int?, steps: [(String, String)])] = [
        (label: "02 A.10 Random(12345L)", seedLong: Int64(12345), seedInt: nil, steps: [("until:100", "36"), ("until:100", "41"), ("until:100", "28"), ("bool", "true"), ("bool", "true"), ("bool", "true"), ("float", "0x3F518248"), ("float", "0x3DC25720"), ("float", "0x3F26CA5F")]),
        (label: "02 A.10 Random(-7) Int seed", seedLong: nil, seedInt: -7, steps: [("float", "0x3DEB5B40"), ("float", "0x3F01706B"), ("bool", "true")]),
        (label: "02 A.10 Random(-7L)", seedLong: Int64(-7), seedInt: nil, steps: [("float", "0x3DEB5B40"), ("float", "0x3F01706B"), ("bool", "true")]),
        (label: "15 Random(31337) floats", seedLong: Int64(31337), seedInt: nil, steps: [("float", "0x3DBA8DC0"), ("float", "0x3F501759"), ("float", "0x3CA75900"), ("float", "0x3F0FD0AC"), ("float", "0x3F43D5E7")]),
        (label: "15 Random(31337) ints", seedLong: Int64(31337), seedInt: nil, steps: [("until:100", "64"), ("until:100", "67"), ("until:100", "85"), ("until:100", "75"), ("until:100", "44")]),
        (label: "15 Random(31337) bools", seedLong: Int64(31337), seedInt: nil, steps: [("bool", "false"), ("bool", "true"), ("bool", "false"), ("bool", "true"), ("bool", "true"), ("bool", "true"), ("bool", "true"), ("bool", "false")]),
        (label: "17 Random(42)", seedLong: Int64(42), seedInt: nil, steps: [("long", "4174779793377534016")]),
        (label: "17 Random(42) range", seedLong: Int64(42), seedInt: nil, steps: [("lrange:0:1700", "1308")]),
        (label: "17 Random(42) floats", seedLong: Int64(42), seedInt: nil, steps: [("float", "0x3E67BF30"), ("float", "0x3ECF7E40"), ("float", "0x3F67AB3F")]),
        (label: "17 Random(-7L) long", seedLong: Int64(-7), seedInt: nil, steps: [("long", "2119902869140302831")]),
        (label: "17 Random(1760000000000) long", seedLong: Int64(1760000000000), seedInt: nil, steps: [("long", "-1450066263658712945"), ("lrange:0:1700", "990")]),
        (label: "02 A.10 steal seed Int", seedLong: nil, seedInt: 1172167495, steps: [("bool", "false"), ("float", "0x3E797728"), ("float", "0x3EC203F4")]),
    ]
    /// String.hashCode() of the strings other specs quote.
    static let specStringHashes: [(String, Int32)] = [
        ("H0", 2280),
        ("H1", 2281),
        ("H2", 2282),
        ("O0", 2497),
        ("O1", 2498),
        ("O2", 2499),
        ("qa-seasons", -1170156749),
        ("words_fruits_a-0", -1693003846),
        ("0-0-7", 45717181),
        ("7-7-0", 52188548),
        ("nova", 3387436),
        ("woman_dark", -552926701),
        ("unicorn_32", 792758118),
        ("\u{5D1}\u{5D5}\u{5D1}", 1478701),
        ("\u{5DE}\u{5D9}\u{5D4}", 1491321),
        ("\u{1F3C0}", 1773316),
        ("\u{D1}and\u{FA}", 196014676),
        ("\u{FB01}", 64257),
    ]
    /// List<Boolean>.hashCode() of the specs' history lists.
    static let specBoolListHashes: [([Bool], Int32)] = [
        ([], 1),
        ([true], 1262),
        ([false], 1268),
        ([true, false], 40359),
        ([true, true], 40353),
        ([true, false, true], 1252360),
        ([true, true, true], 1252174),
        ([false, false, false], 1258132),
    ]
    /// HashSet copy order of category subsets given in LinkedHashSet order.
    static let categorySubsetOrders: [(input: [String], copy: [String])] = [
        (input: ["SCIENCE", "HISTORY"], copy: ["SCIENCE", "HISTORY"]),
        (input: ["HISTORY", "SCIENCE"], copy: ["SCIENCE", "HISTORY"]),
        (input: ["MATH", "KIDS_ARITHMETIC", "ENGLISH"], copy: ["KIDS_ARITHMETIC", "ENGLISH", "MATH"]),
        (input: ["AI", "PARADOX", "ASTRONOMY", "PROGRAMMING"], copy: ["PARADOX", "PROGRAMMING", "ASTRONOMY", "AI"]),
        (input: ["GENERAL_KNOWLEDGE", "PROGRAMMING", "SCIENCE", "ASTRONOMY", "PARADOX", "HISTORY", "ENGLISH", "KIDS_ARITHMETIC", "MATH", "MATRICULATION_MATH"], copy: ["PARADOX", "PROGRAMMING", "MATRICULATION_MATH", "ASTRONOMY", "ENGLISH", "KIDS_ARITHMETIC", "GENERAL_KNOWLEDGE", "SCIENCE", "MATH", "HISTORY"]),
        (input: ["GENERAL_KNOWLEDGE", "PROGRAMMING", "SCIENCE", "ASTRONOMY", "PARADOX", "HISTORY", "ENGLISH", "KIDS_ARITHMETIC", "MATRICULATION_MATH"], copy: ["PARADOX", "PROGRAMMING", "MATRICULATION_MATH", "ASTRONOMY", "ENGLISH", "KIDS_ARITHMETIC", "GENERAL_KNOWLEDGE", "SCIENCE", "HISTORY"]),
        (input: ["GENERAL_KNOWLEDGE"], copy: ["GENERAL_KNOWLEDGE"]),
    ]
    /// (tag, getLanguage(), getCountry(), getScript(), toLanguageTag(), toString()) of Locale.forLanguageTag(tag).
    static let localeTags: [(String, String, String, String, String, String)] = [
        ("he-IL", "he", "IL", "", "he-IL", "he_IL"),
        ("iw-IL", "he", "IL", "", "he-IL", "he_IL"),
        ("he", "he", "", "", "he", "he"),
        ("iw", "he", "", "", "he", "he"),
        ("en-US", "en", "US", "", "en-US", "en_US"),
        ("en", "en", "", "", "en", "en"),
        ("en-GB", "en", "GB", "", "en-GB", "en_GB"),
        ("zh-Hans-CN", "zh", "CN", "Hans", "zh-Hans-CN", "zh_CN_#Hans"),
        ("zh-Hant-TW", "zh", "TW", "Hant", "zh-Hant-TW", "zh_TW_#Hant"),
        ("es-419", "es", "419", "", "es-419", "es_419"),
        ("pt-BR", "pt", "BR", "", "pt-BR", "pt_BR"),
        ("ar", "ar", "", "", "ar", "ar"),
        ("ar-EG", "ar", "EG", "", "ar-EG", "ar_EG"),
        ("fr-CA", "fr", "CA", "", "fr-CA", "fr_CA"),
        ("in-ID", "id", "ID", "", "id-ID", "id_ID"),
        ("ji", "yi", "", "", "yi", "yi"),
        ("sr-Latn-RS", "sr", "RS", "Latn", "sr-Latn-RS", "sr_RS_#Latn"),
        ("und", "", "", "", "und", ""),
        ("EN-us", "en", "US", "", "en-US", "en_US"),
        ("de-DE-u-co-phonebk", "de", "DE", "", "de-DE", "de_DE"),
        ("ja-JP", "ja", "JP", "", "ja-JP", "ja_JP"),
    ]
    /// More String.format cases (CORE-API locales he, en, und).
    static let formats2: [(locale: String, pattern: String, args: [Any?], expected: String)] = [
        (locale: "he", pattern: "%1$s \u{2022} %2$s \u{2022} %3$s", args: ["\u{5D0}", "B", "\u{1F600}"], expected: "\u{5D0} \u{2022} B \u{2022} \u{1F600}"),
        (locale: "he", pattern: "%1$d/%2$d/%3$d/%4$d/%5$d", args: [1, -2, 300, 4000, 2147483647], expected: "1/-2/300/4000/2147483647"),
        (locale: "he", pattern: "Shot chance: %1$d%%", args: [0], expected: "Shot chance: 0%"),
        (locale: "he", pattern: "%.1f|%.3f|%,.1f|%s", args: [Double(bitPattern: 0x4058FCCCCCCCCCCD), Double(bitPattern: 0x3FF0020C49BA5E35), Double(bitPattern: 0x40F81CD6E147AE14), Double(bitPattern: 0x3FD3333333333334)], expected: "100.0|1.001|98,765.4|0.30000000000000004"),
        (locale: "he", pattern: "%s %s", args: [Float(bitPattern: 0x4B189680), Float(bitPattern: 0x3A83126F)], expected: "1.0E7 0.001"),
        (locale: "he", pattern: "%2$s %1$s %2$s", args: ["x", Int64(12345678901)], expected: "12345678901 x 12345678901"),
        (locale: "en", pattern: "%1$s \u{2022} %2$s \u{2022} %3$s", args: ["\u{5D0}", "B", "\u{1F600}"], expected: "\u{5D0} \u{2022} B \u{2022} \u{1F600}"),
        (locale: "en", pattern: "%1$d/%2$d/%3$d/%4$d/%5$d", args: [1, -2, 300, 4000, 2147483647], expected: "1/-2/300/4000/2147483647"),
        (locale: "en", pattern: "Shot chance: %1$d%%", args: [0], expected: "Shot chance: 0%"),
        (locale: "en", pattern: "%.1f|%.3f|%,.1f|%s", args: [Double(bitPattern: 0x4058FCCCCCCCCCCD), Double(bitPattern: 0x3FF0020C49BA5E35), Double(bitPattern: 0x40F81CD6E147AE14), Double(bitPattern: 0x3FD3333333333334)], expected: "100.0|1.001|98,765.4|0.30000000000000004"),
        (locale: "en", pattern: "%s %s", args: [Float(bitPattern: 0x4B189680), Float(bitPattern: 0x3A83126F)], expected: "1.0E7 0.001"),
        (locale: "en", pattern: "%2$s %1$s %2$s", args: ["x", Int64(12345678901)], expected: "12345678901 x 12345678901"),
        (locale: "und", pattern: "%1$s \u{2022} %2$s \u{2022} %3$s", args: ["\u{5D0}", "B", "\u{1F600}"], expected: "\u{5D0} \u{2022} B \u{2022} \u{1F600}"),
        (locale: "und", pattern: "%1$d/%2$d/%3$d/%4$d/%5$d", args: [1, -2, 300, 4000, 2147483647], expected: "1/-2/300/4000/2147483647"),
        (locale: "und", pattern: "Shot chance: %1$d%%", args: [0], expected: "Shot chance: 0%"),
        (locale: "und", pattern: "%.1f|%.3f|%,.1f|%s", args: [Double(bitPattern: 0x4058FCCCCCCCCCCD), Double(bitPattern: 0x3FF0020C49BA5E35), Double(bitPattern: 0x40F81CD6E147AE14), Double(bitPattern: 0x3FD3333333333334)], expected: "100.0|1.001|98,765.4|0.30000000000000004"),
        (locale: "und", pattern: "%s %s", args: [Float(bitPattern: 0x4B189680), Float(bitPattern: 0x3A83126F)], expected: "1.0E7 0.001"),
        (locale: "und", pattern: "%2$s %1$s %2$s", args: ["x", Int64(12345678901)], expected: "12345678901 x 12345678901"),
    ]
    /// (x bits, sin, cos, tan, asin(x/16), acos(x/16), atan, exp(x/8), ln(|x|+1), log10(|x|+1), sqrt(|x|), cbrt, expm1(x/8)) on Float.
    static let floatMath: [(UInt32, [UInt32])] = [
        (0x00000000, [0x00000000, 0x3F800000, 0x00000000, 0x00000000, 0x3FC90FDB, 0x00000000, 0x3F800000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000]),
        (0x80000000, [0x80000000, 0x3F800000, 0x80000000, 0x80000000, 0x3FC90FDB, 0x80000000, 0x3F800000, 0x00000000, 0x00000000, 0x00000000, 0x80000000, 0x80000000]),
        (0x3F000000, [0x3EF57744, 0x3F60A940, 0x3F0BDA7B, 0x3D000556, 0x3FC50FB0, 0x3EED6338, 0x3F88415B, 0x3ECF991F, 0x3E345144, 0x3F3504F3, 0x3F4B2FF5, 0x3D8415AC]),
        (0xBF400000, [0xBF2E7FE1, 0x3F3B4FF6, 0xBF6E7D1B, 0xBD401205, 0x3FCF106B, 0xBF24BC7D, 0x3F691735, 0x3F0F42FB, 0x3E78DEF7, 0x3F5DB3D7, 0xBF689768, 0xBDB74658]),
        (0x3F800000, [0x3F576AA4, 0x3F0A5140, 0x3FC75923, 0x3D80155F, 0x3FC10E85, 0x3F490FDB, 0x3F910B02, 0x3F317218, 0x3E9A209B, 0x3F800000, 0x3F800000, 0x3E085811]),
        (0x3FC90FDB, [0x3F800000, 0xB33BBD2E, 0xCBAE8A4A, 0x3DC962E6, 0x3FBC79AC, 0x3F807F4C, 0x3F9BC517, 0x3F71B820, 0x3ED1F465, 0x3FA06C99, 0x3F94CB13, 0x3E5E28B9]),
        (0x40490FDB, [0xB3BBBD2E, 0xBF800000, 0x33BBBD2E, 0x3E4A6076, 0x3FAFC3CC, 0x3FA19DC5, 0x3FBD9083, 0x3FB5E5F7, 0x3F1DFEAF, 0x3FE2DFC5, 0x3FBB77BF, 0x3EF6420D]),
        (0xC016CBE4, [0xBF3504F3, 0xBF3504F3, 0x3F800000, 0xBE1758CC, 0x3FDBFAF4, 0xBF95AFA6, 0x3F3EB0D7, 0x3F9AFBC0, 0x3F069DEB, 0x3FC47A8E, 0xBFAA5365, 0xBE829E53]),
        (0x3A83126F, [0x3A83126E, 0x3F7FFFF8, 0x3A831272, 0x3883126F, 0x3FC90DCE, 0x3A83126C, 0x3F800419, 0x3A83033B, 0x39E3979D, 0x3D0186E3, 0x3DCCCCCD, 0x39031488]),
        (0x41480000, [0xBD87D3C6, 0x3F7F6FB5, 0xBD882080, 0x3F658BE4, 0x3F2C93D1, 0x3FBED7FC, 0x4098A9D9, 0x40269278, 0x3F90AEC7, 0x40624630, 0x401487E5, 0x407153B1]),
        (0x42C80000, [0xBF01A12E, 0x3F5CC0EE, 0xBF1653A7, 0xFFC00000, 0xFFC00000, 0x3FC7C82F, 0x48830629, 0x4093AF11, 0x400046CD, 0x41200000, 0x409487E5, 0x48830609]),
        (0x358637BD, [0x358637BD, 0x3F800000, 0x358637BD, 0x338637BD, 0x3FC90FDA, 0x358637BD, 0x3F800001, 0x357FFFF8, 0x34DE5BD2, 0x3A83126F, 0x3C23D70A, 0x340637BE]),
        (0x40C90FDB, [0x343BBD2E, 0x3F800000, 0x343BBD2E, 0x3ECEA006, 0x3F9567D9, 0x3FB4DC0B, 0x400C5EB3, 0x3FFE271A, 0x3F5CC118, 0x40206C99, 0x3FEC31D0, 0x3F98BD67]),
        (0x3EAAAAAB, [0x3EA78611, 0x3F71E8B3, 0x3EB14826, 0x3CAAADD4, 0x3FC66523, 0x3EA4BC7D, 0x3F85722D, 0x3E934B12, 0x3DFFDFE3, 0x3F13CD3A, 0x3F318020, 0x3D2E45AA]),
        (0x402DF854, [0x3ED251EF, 0xBF696764, 0xBEE6AE71, 0x3E2ED168, 0x3FB335AE, 0x3F9BF0B2, 0x3FB3CB70, 0x3FA818F5, 0x3F1201F4, 0x3FD3094C, 0x3FB2A36D, 0x3ECF2DBE]),
    ]
    /// (y bits, x bits, atan2(y, x), hypot(y, x), y.pow(x) for y > 0 else |y|.pow(x)) on Float.
    static let floatMath2: [(UInt32, UInt32, UInt32, UInt32, UInt32)] = [
        (0x3F800000, 0x3F800000, 0x3F490FDB, 0x3FB504F3, 0x3F800000),
        (0xBF800000, 0x3F000000, 0xBF8DB70D, 0x3F8F1BBD, 0x3F800000),
        (0x40400000, 0x40800000, 0x3F24BC7D, 0x40A00000, 0x42A20000),
        (0x3E800000, 0xC1000000, 0x40471005, 0x41000FFF, 0x47800000),
        (0x44001800, 0x44880800, 0x3EE14C6C, 0x44965AC7, 0x7F800000),
        (0x80000000, 0xBF800000, 0xC0490FDB, 0x3F800000, 0x7F800000),
        (0x40000000, 0x41200000, 0x3E4A2210, 0x41232B2B, 0x44800000),
        (0x3FC00000, 0x3EAAA64C, 0x3FAD1334, 0x3FC4AEC5, 0x3F92857D),
    ]
    /// (bits, "$f" on Android 16+ = FloatToDecimal).
    static let floatTemplates: [(UInt32, String)] = [
        (0x3DCCCCCD, "0.1"),
        (0x501502F9, "1.0E10"),
        (0x4E4249B4, "8.149025E8"),
        (0x7F7FFFFF, "3.4028235E38"),
        (0x00800000, "1.1754944E-38"),
    ]
    /// (ms, utcWeekKey, utcMonthKey, Progress weekKey UTC, Progress monthKey UTC, "yyyy-MM-dd" ROOT UTC) on the JVM.
    static let dateKeys: [(Int64, String, String, String, String, String)] = [
        (1420070400000, "2015-W01", "2015-01", "W01/15", "01/15", "2015-01-01"),
        (1420156799999, "2015-W01", "2015-01", "W01/15", "01/15", "2015-01-01"),
        (1420156800000, "2015-W01", "2015-01", "W01/15", "01/15", "2015-01-02"),
        (1420243199999, "2015-W01", "2015-01", "W01/15", "01/15", "2015-01-02"),
        (1420243200000, "2015-W01", "2015-01", "W01/15", "01/15", "2015-01-03"),
        (1420329599999, "2015-W01", "2015-01", "W01/15", "01/15", "2015-01-03"),
        (1420329600000, "2015-W01", "2015-01", "W01/15", "01/15", "2015-01-04"),
        (1420415999999, "2015-W01", "2015-01", "W01/15", "01/15", "2015-01-04"),
        (1420416000000, "2015-W02", "2015-01", "W02/15", "01/15", "2015-01-05"),
        (1420502399999, "2015-W02", "2015-01", "W02/15", "01/15", "2015-01-05"),
        (1420502400000, "2015-W02", "2015-01", "W02/15", "01/15", "2015-01-06"),
        (1420588799999, "2015-W02", "2015-01", "W02/15", "01/15", "2015-01-06"),
        (1420588800000, "2015-W02", "2015-01", "W02/15", "01/15", "2015-01-07"),
        (1420675199999, "2015-W02", "2015-01", "W02/15", "01/15", "2015-01-07"),
        (1451001600000, "2015-W52", "2015-12", "W52/15", "12/15", "2015-12-25"),
        (1451087999999, "2015-W52", "2015-12", "W52/15", "12/15", "2015-12-25"),
        (1451260800000, "2015-W53", "2015-12", "W53/15", "12/15", "2015-12-28"),
        (1451347199999, "2015-W53", "2015-12", "W53/15", "12/15", "2015-12-28"),
        (1451347200000, "2015-W53", "2015-12", "W53/15", "12/15", "2015-12-29"),
        (1451433599999, "2015-W53", "2015-12", "W53/15", "12/15", "2015-12-29"),
        (1451433600000, "2015-W53", "2015-12", "W53/15", "12/15", "2015-12-30"),
        (1451519999999, "2015-W53", "2015-12", "W53/15", "12/15", "2015-12-30"),
        (1451520000000, "2015-W53", "2015-12", "W53/15", "12/15", "2015-12-31"),
        (1451606399999, "2015-W53", "2015-12", "W53/15", "12/15", "2015-12-31"),
        (1434326400000, "2015-W25", "2015-06", "W25/15", "06/15", "2015-06-15"),
        (1434412799999, "2015-W25", "2015-06", "W25/15", "06/15", "2015-06-15"),
        (1451606400000, "2015-W53", "2016-01", "W53/16", "01/16", "2016-01-01"),
        (1451692799999, "2015-W53", "2016-01", "W53/16", "01/16", "2016-01-01"),
        (1451692800000, "2015-W53", "2016-01", "W53/16", "01/16", "2016-01-02"),
        (1451779199999, "2015-W53", "2016-01", "W53/16", "01/16", "2016-01-02"),
        (1451779200000, "2015-W53", "2016-01", "W53/16", "01/16", "2016-01-03"),
        (1451865599999, "2015-W53", "2016-01", "W53/16", "01/16", "2016-01-03"),
        (1451865600000, "2016-W01", "2016-01", "W01/16", "01/16", "2016-01-04"),
        (1451951999999, "2016-W01", "2016-01", "W01/16", "01/16", "2016-01-04"),
        (1451952000000, "2016-W01", "2016-01", "W01/16", "01/16", "2016-01-05"),
        (1452038399999, "2016-W01", "2016-01", "W01/16", "01/16", "2016-01-05"),
        (1452038400000, "2016-W01", "2016-01", "W01/16", "01/16", "2016-01-06"),
        (1452124799999, "2016-W01", "2016-01", "W01/16", "01/16", "2016-01-06"),
        (1452124800000, "2016-W01", "2016-01", "W01/16", "01/16", "2016-01-07"),
        (1452211199999, "2016-W01", "2016-01", "W01/16", "01/16", "2016-01-07"),
        (1482624000000, "2016-W51", "2016-12", "W51/16", "12/16", "2016-12-25"),
        (1482710399999, "2016-W51", "2016-12", "W51/16", "12/16", "2016-12-25"),
        (1482883200000, "2016-W52", "2016-12", "W52/16", "12/16", "2016-12-28"),
        (1482969599999, "2016-W52", "2016-12", "W52/16", "12/16", "2016-12-28"),
        (1482969600000, "2016-W52", "2016-12", "W52/16", "12/16", "2016-12-29"),
        (1483055999999, "2016-W52", "2016-12", "W52/16", "12/16", "2016-12-29"),
        (1483056000000, "2016-W52", "2016-12", "W52/16", "12/16", "2016-12-30"),
        (1483142399999, "2016-W52", "2016-12", "W52/16", "12/16", "2016-12-30"),
        (1483142400000, "2016-W52", "2016-12", "W52/16", "12/16", "2016-12-31"),
        (1483228799999, "2016-W52", "2016-12", "W52/16", "12/16", "2016-12-31"),
        (1465948800000, "2016-W24", "2016-06", "W24/16", "06/16", "2016-06-15"),
        (1466035199999, "2016-W24", "2016-06", "W24/16", "06/16", "2016-06-15"),
        (1483228800000, "2016-W52", "2017-01", "W52/17", "01/17", "2017-01-01"),
        (1483315199999, "2016-W52", "2017-01", "W52/17", "01/17", "2017-01-01"),
        (1483315200000, "2017-W01", "2017-01", "W01/17", "01/17", "2017-01-02"),
        (1483401599999, "2017-W01", "2017-01", "W01/17", "01/17", "2017-01-02"),
        (1483401600000, "2017-W01", "2017-01", "W01/17", "01/17", "2017-01-03"),
        (1483487999999, "2017-W01", "2017-01", "W01/17", "01/17", "2017-01-03"),
        (1483488000000, "2017-W01", "2017-01", "W01/17", "01/17", "2017-01-04"),
        (1483574399999, "2017-W01", "2017-01", "W01/17", "01/17", "2017-01-04"),
        (1483574400000, "2017-W01", "2017-01", "W01/17", "01/17", "2017-01-05"),
        (1483660799999, "2017-W01", "2017-01", "W01/17", "01/17", "2017-01-05"),
        (1483660800000, "2017-W01", "2017-01", "W01/17", "01/17", "2017-01-06"),
        (1483747199999, "2017-W01", "2017-01", "W01/17", "01/17", "2017-01-06"),
        (1483747200000, "2017-W01", "2017-01", "W01/17", "01/17", "2017-01-07"),
        (1483833599999, "2017-W01", "2017-01", "W01/17", "01/17", "2017-01-07"),
        (1514160000000, "2017-W52", "2017-12", "W52/17", "12/17", "2017-12-25"),
        (1514246399999, "2017-W52", "2017-12", "W52/17", "12/17", "2017-12-25"),
        (1514419200000, "2017-W52", "2017-12", "W52/17", "12/17", "2017-12-28"),
        (1514505599999, "2017-W52", "2017-12", "W52/17", "12/17", "2017-12-28"),
        (1514505600000, "2017-W52", "2017-12", "W52/17", "12/17", "2017-12-29"),
        (1514591999999, "2017-W52", "2017-12", "W52/17", "12/17", "2017-12-29"),
        (1514592000000, "2017-W52", "2017-12", "W52/17", "12/17", "2017-12-30"),
        (1514678399999, "2017-W52", "2017-12", "W52/17", "12/17", "2017-12-30"),
        (1514678400000, "2017-W52", "2017-12", "W52/17", "12/17", "2017-12-31"),
        (1514764799999, "2017-W52", "2017-12", "W52/17", "12/17", "2017-12-31"),
        (1497484800000, "2017-W24", "2017-06", "W24/17", "06/17", "2017-06-15"),
        (1497571199999, "2017-W24", "2017-06", "W24/17", "06/17", "2017-06-15"),
        (1514764800000, "2018-W01", "2018-01", "W01/18", "01/18", "2018-01-01"),
        (1514851199999, "2018-W01", "2018-01", "W01/18", "01/18", "2018-01-01"),
        (1514851200000, "2018-W01", "2018-01", "W01/18", "01/18", "2018-01-02"),
        (1514937599999, "2018-W01", "2018-01", "W01/18", "01/18", "2018-01-02"),
        (1514937600000, "2018-W01", "2018-01", "W01/18", "01/18", "2018-01-03"),
        (1515023999999, "2018-W01", "2018-01", "W01/18", "01/18", "2018-01-03"),
        (1515024000000, "2018-W01", "2018-01", "W01/18", "01/18", "2018-01-04"),
        (1515110399999, "2018-W01", "2018-01", "W01/18", "01/18", "2018-01-04"),
        (1515110400000, "2018-W01", "2018-01", "W01/18", "01/18", "2018-01-05"),
        (1515196799999, "2018-W01", "2018-01", "W01/18", "01/18", "2018-01-05"),
        (1515196800000, "2018-W01", "2018-01", "W01/18", "01/18", "2018-01-06"),
        (1515283199999, "2018-W01", "2018-01", "W01/18", "01/18", "2018-01-06"),
        (1515283200000, "2018-W01", "2018-01", "W01/18", "01/18", "2018-01-07"),
        (1515369599999, "2018-W01", "2018-01", "W01/18", "01/18", "2018-01-07"),
        (1545696000000, "2018-W52", "2018-12", "W52/18", "12/18", "2018-12-25"),
        (1545782399999, "2018-W52", "2018-12", "W52/18", "12/18", "2018-12-25"),
        (1545955200000, "2018-W52", "2018-12", "W52/18", "12/18", "2018-12-28"),
        (1546041599999, "2018-W52", "2018-12", "W52/18", "12/18", "2018-12-28"),
        (1546041600000, "2018-W52", "2018-12", "W52/18", "12/18", "2018-12-29"),
        (1546127999999, "2018-W52", "2018-12", "W52/18", "12/18", "2018-12-29"),
        (1546128000000, "2018-W52", "2018-12", "W52/18", "12/18", "2018-12-30"),
        (1546214399999, "2018-W52", "2018-12", "W52/18", "12/18", "2018-12-30"),
        (1546214400000, "2019-W01", "2018-12", "W01/18", "12/18", "2018-12-31"),
        (1546300799999, "2019-W01", "2018-12", "W01/18", "12/18", "2018-12-31"),
        (1529020800000, "2018-W24", "2018-06", "W24/18", "06/18", "2018-06-15"),
        (1529107199999, "2018-W24", "2018-06", "W24/18", "06/18", "2018-06-15"),
        (1546300800000, "2019-W01", "2019-01", "W01/19", "01/19", "2019-01-01"),
        (1546387199999, "2019-W01", "2019-01", "W01/19", "01/19", "2019-01-01"),
        (1546387200000, "2019-W01", "2019-01", "W01/19", "01/19", "2019-01-02"),
        (1546473599999, "2019-W01", "2019-01", "W01/19", "01/19", "2019-01-02"),
        (1546473600000, "2019-W01", "2019-01", "W01/19", "01/19", "2019-01-03"),
        (1546559999999, "2019-W01", "2019-01", "W01/19", "01/19", "2019-01-03"),
        (1546560000000, "2019-W01", "2019-01", "W01/19", "01/19", "2019-01-04"),
        (1546646399999, "2019-W01", "2019-01", "W01/19", "01/19", "2019-01-04"),
        (1546646400000, "2019-W01", "2019-01", "W01/19", "01/19", "2019-01-05"),
        (1546732799999, "2019-W01", "2019-01", "W01/19", "01/19", "2019-01-05"),
        (1546732800000, "2019-W01", "2019-01", "W01/19", "01/19", "2019-01-06"),
        (1546819199999, "2019-W01", "2019-01", "W01/19", "01/19", "2019-01-06"),
        (1546819200000, "2019-W02", "2019-01", "W02/19", "01/19", "2019-01-07"),
        (1546905599999, "2019-W02", "2019-01", "W02/19", "01/19", "2019-01-07"),
        (1577232000000, "2019-W52", "2019-12", "W52/19", "12/19", "2019-12-25"),
        (1577318399999, "2019-W52", "2019-12", "W52/19", "12/19", "2019-12-25"),
        (1577491200000, "2019-W52", "2019-12", "W52/19", "12/19", "2019-12-28"),
        (1577577599999, "2019-W52", "2019-12", "W52/19", "12/19", "2019-12-28"),
        (1577577600000, "2019-W52", "2019-12", "W52/19", "12/19", "2019-12-29"),
        (1577663999999, "2019-W52", "2019-12", "W52/19", "12/19", "2019-12-29"),
        (1577664000000, "2020-W01", "2019-12", "W01/19", "12/19", "2019-12-30"),
        (1577750399999, "2020-W01", "2019-12", "W01/19", "12/19", "2019-12-30"),
        (1577750400000, "2020-W01", "2019-12", "W01/19", "12/19", "2019-12-31"),
        (1577836799999, "2020-W01", "2019-12", "W01/19", "12/19", "2019-12-31"),
        (1560556800000, "2019-W24", "2019-06", "W24/19", "06/19", "2019-06-15"),
        (1560643199999, "2019-W24", "2019-06", "W24/19", "06/19", "2019-06-15"),
        (1577836800000, "2020-W01", "2020-01", "W01/20", "01/20", "2020-01-01"),
        (1577923199999, "2020-W01", "2020-01", "W01/20", "01/20", "2020-01-01"),
        (1577923200000, "2020-W01", "2020-01", "W01/20", "01/20", "2020-01-02"),
        (1578009599999, "2020-W01", "2020-01", "W01/20", "01/20", "2020-01-02"),
        (1578009600000, "2020-W01", "2020-01", "W01/20", "01/20", "2020-01-03"),
        (1578095999999, "2020-W01", "2020-01", "W01/20", "01/20", "2020-01-03"),
        (1578096000000, "2020-W01", "2020-01", "W01/20", "01/20", "2020-01-04"),
        (1578182399999, "2020-W01", "2020-01", "W01/20", "01/20", "2020-01-04"),
        (1578182400000, "2020-W01", "2020-01", "W01/20", "01/20", "2020-01-05"),
        (1578268799999, "2020-W01", "2020-01", "W01/20", "01/20", "2020-01-05"),
        (1578268800000, "2020-W02", "2020-01", "W02/20", "01/20", "2020-01-06"),
        (1578355199999, "2020-W02", "2020-01", "W02/20", "01/20", "2020-01-06"),
        (1578355200000, "2020-W02", "2020-01", "W02/20", "01/20", "2020-01-07"),
        (1578441599999, "2020-W02", "2020-01", "W02/20", "01/20", "2020-01-07"),
        (1608854400000, "2020-W52", "2020-12", "W52/20", "12/20", "2020-12-25"),
        (1608940799999, "2020-W52", "2020-12", "W52/20", "12/20", "2020-12-25"),
        (1609113600000, "2020-W53", "2020-12", "W53/20", "12/20", "2020-12-28"),
        (1609199999999, "2020-W53", "2020-12", "W53/20", "12/20", "2020-12-28"),
        (1609200000000, "2020-W53", "2020-12", "W53/20", "12/20", "2020-12-29"),
        (1609286399999, "2020-W53", "2020-12", "W53/20", "12/20", "2020-12-29"),
        (1609286400000, "2020-W53", "2020-12", "W53/20", "12/20", "2020-12-30"),
        (1609372799999, "2020-W53", "2020-12", "W53/20", "12/20", "2020-12-30"),
        (1609372800000, "2020-W53", "2020-12", "W53/20", "12/20", "2020-12-31"),
        (1609459199999, "2020-W53", "2020-12", "W53/20", "12/20", "2020-12-31"),
        (1592179200000, "2020-W25", "2020-06", "W25/20", "06/20", "2020-06-15"),
        (1592265599999, "2020-W25", "2020-06", "W25/20", "06/20", "2020-06-15"),
        (1609459200000, "2020-W53", "2021-01", "W53/21", "01/21", "2021-01-01"),
        (1609545599999, "2020-W53", "2021-01", "W53/21", "01/21", "2021-01-01"),
        (1609545600000, "2020-W53", "2021-01", "W53/21", "01/21", "2021-01-02"),
        (1609631999999, "2020-W53", "2021-01", "W53/21", "01/21", "2021-01-02"),
        (1609632000000, "2020-W53", "2021-01", "W53/21", "01/21", "2021-01-03"),
        (1609718399999, "2020-W53", "2021-01", "W53/21", "01/21", "2021-01-03"),
        (1609718400000, "2021-W01", "2021-01", "W01/21", "01/21", "2021-01-04"),
        (1609804799999, "2021-W01", "2021-01", "W01/21", "01/21", "2021-01-04"),
        (1609804800000, "2021-W01", "2021-01", "W01/21", "01/21", "2021-01-05"),
        (1609891199999, "2021-W01", "2021-01", "W01/21", "01/21", "2021-01-05"),
        (1609891200000, "2021-W01", "2021-01", "W01/21", "01/21", "2021-01-06"),
        (1609977599999, "2021-W01", "2021-01", "W01/21", "01/21", "2021-01-06"),
        (1609977600000, "2021-W01", "2021-01", "W01/21", "01/21", "2021-01-07"),
        (1610063999999, "2021-W01", "2021-01", "W01/21", "01/21", "2021-01-07"),
        (1640390400000, "2021-W51", "2021-12", "W51/21", "12/21", "2021-12-25"),
        (1640476799999, "2021-W51", "2021-12", "W51/21", "12/21", "2021-12-25"),
        (1640649600000, "2021-W52", "2021-12", "W52/21", "12/21", "2021-12-28"),
        (1640735999999, "2021-W52", "2021-12", "W52/21", "12/21", "2021-12-28"),
        (1640736000000, "2021-W52", "2021-12", "W52/21", "12/21", "2021-12-29"),
        (1640822399999, "2021-W52", "2021-12", "W52/21", "12/21", "2021-12-29"),
        (1640822400000, "2021-W52", "2021-12", "W52/21", "12/21", "2021-12-30"),
        (1640908799999, "2021-W52", "2021-12", "W52/21", "12/21", "2021-12-30"),
        (1640908800000, "2021-W52", "2021-12", "W52/21", "12/21", "2021-12-31"),
        (1640995199999, "2021-W52", "2021-12", "W52/21", "12/21", "2021-12-31"),
        (1623715200000, "2021-W24", "2021-06", "W24/21", "06/21", "2021-06-15"),
        (1623801599999, "2021-W24", "2021-06", "W24/21", "06/21", "2021-06-15"),
        (1640995200000, "2021-W52", "2022-01", "W52/22", "01/22", "2022-01-01"),
        (1641081599999, "2021-W52", "2022-01", "W52/22", "01/22", "2022-01-01"),
        (1641081600000, "2021-W52", "2022-01", "W52/22", "01/22", "2022-01-02"),
        (1641167999999, "2021-W52", "2022-01", "W52/22", "01/22", "2022-01-02"),
        (1641168000000, "2022-W01", "2022-01", "W01/22", "01/22", "2022-01-03"),
        (1641254399999, "2022-W01", "2022-01", "W01/22", "01/22", "2022-01-03"),
        (1641254400000, "2022-W01", "2022-01", "W01/22", "01/22", "2022-01-04"),
        (1641340799999, "2022-W01", "2022-01", "W01/22", "01/22", "2022-01-04"),
        (1641340800000, "2022-W01", "2022-01", "W01/22", "01/22", "2022-01-05"),
        (1641427199999, "2022-W01", "2022-01", "W01/22", "01/22", "2022-01-05"),
        (1641427200000, "2022-W01", "2022-01", "W01/22", "01/22", "2022-01-06"),
        (1641513599999, "2022-W01", "2022-01", "W01/22", "01/22", "2022-01-06"),
        (1641513600000, "2022-W01", "2022-01", "W01/22", "01/22", "2022-01-07"),
        (1641599999999, "2022-W01", "2022-01", "W01/22", "01/22", "2022-01-07"),
        (1671926400000, "2022-W51", "2022-12", "W51/22", "12/22", "2022-12-25"),
        (1672012799999, "2022-W51", "2022-12", "W51/22", "12/22", "2022-12-25"),
        (1672185600000, "2022-W52", "2022-12", "W52/22", "12/22", "2022-12-28"),
        (1672271999999, "2022-W52", "2022-12", "W52/22", "12/22", "2022-12-28"),
        (1672272000000, "2022-W52", "2022-12", "W52/22", "12/22", "2022-12-29"),
        (1672358399999, "2022-W52", "2022-12", "W52/22", "12/22", "2022-12-29"),
        (1672358400000, "2022-W52", "2022-12", "W52/22", "12/22", "2022-12-30"),
        (1672444799999, "2022-W52", "2022-12", "W52/22", "12/22", "2022-12-30"),
        (1672444800000, "2022-W52", "2022-12", "W52/22", "12/22", "2022-12-31"),
        (1672531199999, "2022-W52", "2022-12", "W52/22", "12/22", "2022-12-31"),
        (1655251200000, "2022-W24", "2022-06", "W24/22", "06/22", "2022-06-15"),
        (1655337599999, "2022-W24", "2022-06", "W24/22", "06/22", "2022-06-15"),
        (1672531200000, "2022-W52", "2023-01", "W52/23", "01/23", "2023-01-01"),
        (1672617599999, "2022-W52", "2023-01", "W52/23", "01/23", "2023-01-01"),
        (1672617600000, "2023-W01", "2023-01", "W01/23", "01/23", "2023-01-02"),
        (1672703999999, "2023-W01", "2023-01", "W01/23", "01/23", "2023-01-02"),
        (1672704000000, "2023-W01", "2023-01", "W01/23", "01/23", "2023-01-03"),
        (1672790399999, "2023-W01", "2023-01", "W01/23", "01/23", "2023-01-03"),
        (1672790400000, "2023-W01", "2023-01", "W01/23", "01/23", "2023-01-04"),
        (1672876799999, "2023-W01", "2023-01", "W01/23", "01/23", "2023-01-04"),
        (1672876800000, "2023-W01", "2023-01", "W01/23", "01/23", "2023-01-05"),
        (1672963199999, "2023-W01", "2023-01", "W01/23", "01/23", "2023-01-05"),
        (1672963200000, "2023-W01", "2023-01", "W01/23", "01/23", "2023-01-06"),
        (1673049599999, "2023-W01", "2023-01", "W01/23", "01/23", "2023-01-06"),
        (1673049600000, "2023-W01", "2023-01", "W01/23", "01/23", "2023-01-07"),
        (1673135999999, "2023-W01", "2023-01", "W01/23", "01/23", "2023-01-07"),
        (1703462400000, "2023-W52", "2023-12", "W52/23", "12/23", "2023-12-25"),
        (1703548799999, "2023-W52", "2023-12", "W52/23", "12/23", "2023-12-25"),
        (1703721600000, "2023-W52", "2023-12", "W52/23", "12/23", "2023-12-28"),
        (1703807999999, "2023-W52", "2023-12", "W52/23", "12/23", "2023-12-28"),
        (1703808000000, "2023-W52", "2023-12", "W52/23", "12/23", "2023-12-29"),
        (1703894399999, "2023-W52", "2023-12", "W52/23", "12/23", "2023-12-29"),
        (1703894400000, "2023-W52", "2023-12", "W52/23", "12/23", "2023-12-30"),
        (1703980799999, "2023-W52", "2023-12", "W52/23", "12/23", "2023-12-30"),
        (1703980800000, "2023-W52", "2023-12", "W52/23", "12/23", "2023-12-31"),
        (1704067199999, "2023-W52", "2023-12", "W52/23", "12/23", "2023-12-31"),
        (1686787200000, "2023-W24", "2023-06", "W24/23", "06/23", "2023-06-15"),
        (1686873599999, "2023-W24", "2023-06", "W24/23", "06/23", "2023-06-15"),
        (1704067200000, "2024-W01", "2024-01", "W01/24", "01/24", "2024-01-01"),
        (1704153599999, "2024-W01", "2024-01", "W01/24", "01/24", "2024-01-01"),
        (1704153600000, "2024-W01", "2024-01", "W01/24", "01/24", "2024-01-02"),
        (1704239999999, "2024-W01", "2024-01", "W01/24", "01/24", "2024-01-02"),
        (1704240000000, "2024-W01", "2024-01", "W01/24", "01/24", "2024-01-03"),
        (1704326399999, "2024-W01", "2024-01", "W01/24", "01/24", "2024-01-03"),
        (1704326400000, "2024-W01", "2024-01", "W01/24", "01/24", "2024-01-04"),
        (1704412799999, "2024-W01", "2024-01", "W01/24", "01/24", "2024-01-04"),
        (1704412800000, "2024-W01", "2024-01", "W01/24", "01/24", "2024-01-05"),
        (1704499199999, "2024-W01", "2024-01", "W01/24", "01/24", "2024-01-05"),
        (1704499200000, "2024-W01", "2024-01", "W01/24", "01/24", "2024-01-06"),
        (1704585599999, "2024-W01", "2024-01", "W01/24", "01/24", "2024-01-06"),
        (1704585600000, "2024-W01", "2024-01", "W01/24", "01/24", "2024-01-07"),
        (1704671999999, "2024-W01", "2024-01", "W01/24", "01/24", "2024-01-07"),
        (1735084800000, "2024-W52", "2024-12", "W52/24", "12/24", "2024-12-25"),
        (1735171199999, "2024-W52", "2024-12", "W52/24", "12/24", "2024-12-25"),
        (1735344000000, "2024-W52", "2024-12", "W52/24", "12/24", "2024-12-28"),
        (1735430399999, "2024-W52", "2024-12", "W52/24", "12/24", "2024-12-28"),
        (1735430400000, "2024-W52", "2024-12", "W52/24", "12/24", "2024-12-29"),
        (1735516799999, "2024-W52", "2024-12", "W52/24", "12/24", "2024-12-29"),
        (1735516800000, "2025-W01", "2024-12", "W01/24", "12/24", "2024-12-30"),
        (1735603199999, "2025-W01", "2024-12", "W01/24", "12/24", "2024-12-30"),
        (1735603200000, "2025-W01", "2024-12", "W01/24", "12/24", "2024-12-31"),
        (1735689599999, "2025-W01", "2024-12", "W01/24", "12/24", "2024-12-31"),
        (1718409600000, "2024-W24", "2024-06", "W24/24", "06/24", "2024-06-15"),
        (1718495999999, "2024-W24", "2024-06", "W24/24", "06/24", "2024-06-15"),
        (1735689600000, "2025-W01", "2025-01", "W01/25", "01/25", "2025-01-01"),
        (1735775999999, "2025-W01", "2025-01", "W01/25", "01/25", "2025-01-01"),
        (1735776000000, "2025-W01", "2025-01", "W01/25", "01/25", "2025-01-02"),
        (1735862399999, "2025-W01", "2025-01", "W01/25", "01/25", "2025-01-02"),
        (1735862400000, "2025-W01", "2025-01", "W01/25", "01/25", "2025-01-03"),
        (1735948799999, "2025-W01", "2025-01", "W01/25", "01/25", "2025-01-03"),
        (1735948800000, "2025-W01", "2025-01", "W01/25", "01/25", "2025-01-04"),
        (1736035199999, "2025-W01", "2025-01", "W01/25", "01/25", "2025-01-04"),
        (1736035200000, "2025-W01", "2025-01", "W01/25", "01/25", "2025-01-05"),
        (1736121599999, "2025-W01", "2025-01", "W01/25", "01/25", "2025-01-05"),
        (1736121600000, "2025-W02", "2025-01", "W02/25", "01/25", "2025-01-06"),
        (1736207999999, "2025-W02", "2025-01", "W02/25", "01/25", "2025-01-06"),
        (1736208000000, "2025-W02", "2025-01", "W02/25", "01/25", "2025-01-07"),
        (1736294399999, "2025-W02", "2025-01", "W02/25", "01/25", "2025-01-07"),
        (1766620800000, "2025-W52", "2025-12", "W52/25", "12/25", "2025-12-25"),
        (1766707199999, "2025-W52", "2025-12", "W52/25", "12/25", "2025-12-25"),
        (1766880000000, "2025-W52", "2025-12", "W52/25", "12/25", "2025-12-28"),
        (1766966399999, "2025-W52", "2025-12", "W52/25", "12/25", "2025-12-28"),
        (1766966400000, "2026-W01", "2025-12", "W01/25", "12/25", "2025-12-29"),
        (1767052799999, "2026-W01", "2025-12", "W01/25", "12/25", "2025-12-29"),
        (1767052800000, "2026-W01", "2025-12", "W01/25", "12/25", "2025-12-30"),
        (1767139199999, "2026-W01", "2025-12", "W01/25", "12/25", "2025-12-30"),
        (1767139200000, "2026-W01", "2025-12", "W01/25", "12/25", "2025-12-31"),
        (1767225599999, "2026-W01", "2025-12", "W01/25", "12/25", "2025-12-31"),
        (1749945600000, "2025-W24", "2025-06", "W24/25", "06/25", "2025-06-15"),
        (1750031999999, "2025-W24", "2025-06", "W24/25", "06/25", "2025-06-15"),
        (1767225600000, "2026-W01", "2026-01", "W01/26", "01/26", "2026-01-01"),
        (1767311999999, "2026-W01", "2026-01", "W01/26", "01/26", "2026-01-01"),
        (1767312000000, "2026-W01", "2026-01", "W01/26", "01/26", "2026-01-02"),
        (1767398399999, "2026-W01", "2026-01", "W01/26", "01/26", "2026-01-02"),
        (1767398400000, "2026-W01", "2026-01", "W01/26", "01/26", "2026-01-03"),
        (1767484799999, "2026-W01", "2026-01", "W01/26", "01/26", "2026-01-03"),
        (1767484800000, "2026-W01", "2026-01", "W01/26", "01/26", "2026-01-04"),
        (1767571199999, "2026-W01", "2026-01", "W01/26", "01/26", "2026-01-04"),
        (1767571200000, "2026-W02", "2026-01", "W02/26", "01/26", "2026-01-05"),
        (1767657599999, "2026-W02", "2026-01", "W02/26", "01/26", "2026-01-05"),
        (1767657600000, "2026-W02", "2026-01", "W02/26", "01/26", "2026-01-06"),
        (1767743999999, "2026-W02", "2026-01", "W02/26", "01/26", "2026-01-06"),
        (1767744000000, "2026-W02", "2026-01", "W02/26", "01/26", "2026-01-07"),
        (1767830399999, "2026-W02", "2026-01", "W02/26", "01/26", "2026-01-07"),
        (1798156800000, "2026-W52", "2026-12", "W52/26", "12/26", "2026-12-25"),
        (1798243199999, "2026-W52", "2026-12", "W52/26", "12/26", "2026-12-25"),
        (1798416000000, "2026-W53", "2026-12", "W53/26", "12/26", "2026-12-28"),
        (1798502399999, "2026-W53", "2026-12", "W53/26", "12/26", "2026-12-28"),
        (1798502400000, "2026-W53", "2026-12", "W53/26", "12/26", "2026-12-29"),
        (1798588799999, "2026-W53", "2026-12", "W53/26", "12/26", "2026-12-29"),
        (1798588800000, "2026-W53", "2026-12", "W53/26", "12/26", "2026-12-30"),
        (1798675199999, "2026-W53", "2026-12", "W53/26", "12/26", "2026-12-30"),
        (1798675200000, "2026-W53", "2026-12", "W53/26", "12/26", "2026-12-31"),
        (1798761599999, "2026-W53", "2026-12", "W53/26", "12/26", "2026-12-31"),
        (1781481600000, "2026-W25", "2026-06", "W25/26", "06/26", "2026-06-15"),
        (1781567999999, "2026-W25", "2026-06", "W25/26", "06/26", "2026-06-15"),
        (1798761600000, "2026-W53", "2027-01", "W53/27", "01/27", "2027-01-01"),
        (1798847999999, "2026-W53", "2027-01", "W53/27", "01/27", "2027-01-01"),
        (1798848000000, "2026-W53", "2027-01", "W53/27", "01/27", "2027-01-02"),
        (1798934399999, "2026-W53", "2027-01", "W53/27", "01/27", "2027-01-02"),
        (1798934400000, "2026-W53", "2027-01", "W53/27", "01/27", "2027-01-03"),
        (1799020799999, "2026-W53", "2027-01", "W53/27", "01/27", "2027-01-03"),
        (1799020800000, "2027-W01", "2027-01", "W01/27", "01/27", "2027-01-04"),
        (1799107199999, "2027-W01", "2027-01", "W01/27", "01/27", "2027-01-04"),
        (1799107200000, "2027-W01", "2027-01", "W01/27", "01/27", "2027-01-05"),
        (1799193599999, "2027-W01", "2027-01", "W01/27", "01/27", "2027-01-05"),
        (1799193600000, "2027-W01", "2027-01", "W01/27", "01/27", "2027-01-06"),
        (1799279999999, "2027-W01", "2027-01", "W01/27", "01/27", "2027-01-06"),
        (1799280000000, "2027-W01", "2027-01", "W01/27", "01/27", "2027-01-07"),
        (1799366399999, "2027-W01", "2027-01", "W01/27", "01/27", "2027-01-07"),
        (1829692800000, "2027-W51", "2027-12", "W51/27", "12/27", "2027-12-25"),
        (1829779199999, "2027-W51", "2027-12", "W51/27", "12/27", "2027-12-25"),
        (1829952000000, "2027-W52", "2027-12", "W52/27", "12/27", "2027-12-28"),
        (1830038399999, "2027-W52", "2027-12", "W52/27", "12/27", "2027-12-28"),
        (1830038400000, "2027-W52", "2027-12", "W52/27", "12/27", "2027-12-29"),
        (1830124799999, "2027-W52", "2027-12", "W52/27", "12/27", "2027-12-29"),
        (1830124800000, "2027-W52", "2027-12", "W52/27", "12/27", "2027-12-30"),
        (1830211199999, "2027-W52", "2027-12", "W52/27", "12/27", "2027-12-30"),
        (1830211200000, "2027-W52", "2027-12", "W52/27", "12/27", "2027-12-31"),
        (1830297599999, "2027-W52", "2027-12", "W52/27", "12/27", "2027-12-31"),
        (1813017600000, "2027-W24", "2027-06", "W24/27", "06/27", "2027-06-15"),
        (1813103999999, "2027-W24", "2027-06", "W24/27", "06/27", "2027-06-15"),
        (1830297600000, "2027-W52", "2028-01", "W52/28", "01/28", "2028-01-01"),
        (1830383999999, "2027-W52", "2028-01", "W52/28", "01/28", "2028-01-01"),
        (1830384000000, "2027-W52", "2028-01", "W52/28", "01/28", "2028-01-02"),
        (1830470399999, "2027-W52", "2028-01", "W52/28", "01/28", "2028-01-02"),
        (1830470400000, "2028-W01", "2028-01", "W01/28", "01/28", "2028-01-03"),
        (1830556799999, "2028-W01", "2028-01", "W01/28", "01/28", "2028-01-03"),
        (1830556800000, "2028-W01", "2028-01", "W01/28", "01/28", "2028-01-04"),
        (1830643199999, "2028-W01", "2028-01", "W01/28", "01/28", "2028-01-04"),
        (1830643200000, "2028-W01", "2028-01", "W01/28", "01/28", "2028-01-05"),
        (1830729599999, "2028-W01", "2028-01", "W01/28", "01/28", "2028-01-05"),
        (1830729600000, "2028-W01", "2028-01", "W01/28", "01/28", "2028-01-06"),
        (1830815999999, "2028-W01", "2028-01", "W01/28", "01/28", "2028-01-06"),
        (1830816000000, "2028-W01", "2028-01", "W01/28", "01/28", "2028-01-07"),
        (1830902399999, "2028-W01", "2028-01", "W01/28", "01/28", "2028-01-07"),
        (1861315200000, "2028-W52", "2028-12", "W52/28", "12/28", "2028-12-25"),
        (1861401599999, "2028-W52", "2028-12", "W52/28", "12/28", "2028-12-25"),
        (1861574400000, "2028-W52", "2028-12", "W52/28", "12/28", "2028-12-28"),
        (1861660799999, "2028-W52", "2028-12", "W52/28", "12/28", "2028-12-28"),
        (1861660800000, "2028-W52", "2028-12", "W52/28", "12/28", "2028-12-29"),
        (1861747199999, "2028-W52", "2028-12", "W52/28", "12/28", "2028-12-29"),
        (1861747200000, "2028-W52", "2028-12", "W52/28", "12/28", "2028-12-30"),
        (1861833599999, "2028-W52", "2028-12", "W52/28", "12/28", "2028-12-30"),
        (1861833600000, "2028-W52", "2028-12", "W52/28", "12/28", "2028-12-31"),
        (1861919999999, "2028-W52", "2028-12", "W52/28", "12/28", "2028-12-31"),
        (1844640000000, "2028-W24", "2028-06", "W24/28", "06/28", "2028-06-15"),
        (1844726399999, "2028-W24", "2028-06", "W24/28", "06/28", "2028-06-15"),
        (1861920000000, "2029-W01", "2029-01", "W01/29", "01/29", "2029-01-01"),
        (1862006399999, "2029-W01", "2029-01", "W01/29", "01/29", "2029-01-01"),
        (1862006400000, "2029-W01", "2029-01", "W01/29", "01/29", "2029-01-02"),
        (1862092799999, "2029-W01", "2029-01", "W01/29", "01/29", "2029-01-02"),
        (1862092800000, "2029-W01", "2029-01", "W01/29", "01/29", "2029-01-03"),
        (1862179199999, "2029-W01", "2029-01", "W01/29", "01/29", "2029-01-03"),
        (1862179200000, "2029-W01", "2029-01", "W01/29", "01/29", "2029-01-04"),
        (1862265599999, "2029-W01", "2029-01", "W01/29", "01/29", "2029-01-04"),
        (1862265600000, "2029-W01", "2029-01", "W01/29", "01/29", "2029-01-05"),
        (1862351999999, "2029-W01", "2029-01", "W01/29", "01/29", "2029-01-05"),
        (1862352000000, "2029-W01", "2029-01", "W01/29", "01/29", "2029-01-06"),
        (1862438399999, "2029-W01", "2029-01", "W01/29", "01/29", "2029-01-06"),
        (1862438400000, "2029-W01", "2029-01", "W01/29", "01/29", "2029-01-07"),
        (1862524799999, "2029-W01", "2029-01", "W01/29", "01/29", "2029-01-07"),
        (1892851200000, "2029-W52", "2029-12", "W52/29", "12/29", "2029-12-25"),
        (1892937599999, "2029-W52", "2029-12", "W52/29", "12/29", "2029-12-25"),
        (1893110400000, "2029-W52", "2029-12", "W52/29", "12/29", "2029-12-28"),
        (1893196799999, "2029-W52", "2029-12", "W52/29", "12/29", "2029-12-28"),
        (1893196800000, "2029-W52", "2029-12", "W52/29", "12/29", "2029-12-29"),
        (1893283199999, "2029-W52", "2029-12", "W52/29", "12/29", "2029-12-29"),
        (1893283200000, "2029-W52", "2029-12", "W52/29", "12/29", "2029-12-30"),
        (1893369599999, "2029-W52", "2029-12", "W52/29", "12/29", "2029-12-30"),
        (1893369600000, "2030-W01", "2029-12", "W01/29", "12/29", "2029-12-31"),
        (1893455999999, "2030-W01", "2029-12", "W01/29", "12/29", "2029-12-31"),
        (1876176000000, "2029-W24", "2029-06", "W24/29", "06/29", "2029-06-15"),
        (1876262399999, "2029-W24", "2029-06", "W24/29", "06/29", "2029-06-15"),
        (1893456000000, "2030-W01", "2030-01", "W01/30", "01/30", "2030-01-01"),
        (1893542399999, "2030-W01", "2030-01", "W01/30", "01/30", "2030-01-01"),
        (1893542400000, "2030-W01", "2030-01", "W01/30", "01/30", "2030-01-02"),
        (1893628799999, "2030-W01", "2030-01", "W01/30", "01/30", "2030-01-02"),
        (1893628800000, "2030-W01", "2030-01", "W01/30", "01/30", "2030-01-03"),
        (1893715199999, "2030-W01", "2030-01", "W01/30", "01/30", "2030-01-03"),
        (1893715200000, "2030-W01", "2030-01", "W01/30", "01/30", "2030-01-04"),
        (1893801599999, "2030-W01", "2030-01", "W01/30", "01/30", "2030-01-04"),
        (1893801600000, "2030-W01", "2030-01", "W01/30", "01/30", "2030-01-05"),
        (1893887999999, "2030-W01", "2030-01", "W01/30", "01/30", "2030-01-05"),
        (1893888000000, "2030-W01", "2030-01", "W01/30", "01/30", "2030-01-06"),
        (1893974399999, "2030-W01", "2030-01", "W01/30", "01/30", "2030-01-06"),
        (1893974400000, "2030-W02", "2030-01", "W02/30", "01/30", "2030-01-07"),
        (1894060799999, "2030-W02", "2030-01", "W02/30", "01/30", "2030-01-07"),
        (1924387200000, "2030-W52", "2030-12", "W52/30", "12/30", "2030-12-25"),
        (1924473599999, "2030-W52", "2030-12", "W52/30", "12/30", "2030-12-25"),
        (1924646400000, "2030-W52", "2030-12", "W52/30", "12/30", "2030-12-28"),
        (1924732799999, "2030-W52", "2030-12", "W52/30", "12/30", "2030-12-28"),
        (1924732800000, "2030-W52", "2030-12", "W52/30", "12/30", "2030-12-29"),
        (1924819199999, "2030-W52", "2030-12", "W52/30", "12/30", "2030-12-29"),
        (1924819200000, "2031-W01", "2030-12", "W01/30", "12/30", "2030-12-30"),
        (1924905599999, "2031-W01", "2030-12", "W01/30", "12/30", "2030-12-30"),
        (1924905600000, "2031-W01", "2030-12", "W01/30", "12/30", "2030-12-31"),
        (1924991999999, "2031-W01", "2030-12", "W01/30", "12/30", "2030-12-31"),
        (1907712000000, "2030-W24", "2030-06", "W24/30", "06/30", "2030-06-15"),
        (1907798399999, "2030-W24", "2030-06", "W24/30", "06/30", "2030-06-15"),
        (1924992000000, "2031-W01", "2031-01", "W01/31", "01/31", "2031-01-01"),
        (1925078399999, "2031-W01", "2031-01", "W01/31", "01/31", "2031-01-01"),
        (1925078400000, "2031-W01", "2031-01", "W01/31", "01/31", "2031-01-02"),
        (1925164799999, "2031-W01", "2031-01", "W01/31", "01/31", "2031-01-02"),
        (1925164800000, "2031-W01", "2031-01", "W01/31", "01/31", "2031-01-03"),
        (1925251199999, "2031-W01", "2031-01", "W01/31", "01/31", "2031-01-03"),
        (1925251200000, "2031-W01", "2031-01", "W01/31", "01/31", "2031-01-04"),
        (1925337599999, "2031-W01", "2031-01", "W01/31", "01/31", "2031-01-04"),
        (1925337600000, "2031-W01", "2031-01", "W01/31", "01/31", "2031-01-05"),
        (1925423999999, "2031-W01", "2031-01", "W01/31", "01/31", "2031-01-05"),
        (1925424000000, "2031-W02", "2031-01", "W02/31", "01/31", "2031-01-06"),
        (1925510399999, "2031-W02", "2031-01", "W02/31", "01/31", "2031-01-06"),
        (1925510400000, "2031-W02", "2031-01", "W02/31", "01/31", "2031-01-07"),
        (1925596799999, "2031-W02", "2031-01", "W02/31", "01/31", "2031-01-07"),
        (1955923200000, "2031-W52", "2031-12", "W52/31", "12/31", "2031-12-25"),
        (1956009599999, "2031-W52", "2031-12", "W52/31", "12/31", "2031-12-25"),
        (1956182400000, "2031-W52", "2031-12", "W52/31", "12/31", "2031-12-28"),
        (1956268799999, "2031-W52", "2031-12", "W52/31", "12/31", "2031-12-28"),
        (1956268800000, "2032-W01", "2031-12", "W01/31", "12/31", "2031-12-29"),
        (1956355199999, "2032-W01", "2031-12", "W01/31", "12/31", "2031-12-29"),
        (1956355200000, "2032-W01", "2031-12", "W01/31", "12/31", "2031-12-30"),
        (1956441599999, "2032-W01", "2031-12", "W01/31", "12/31", "2031-12-30"),
        (1956441600000, "2032-W01", "2031-12", "W01/31", "12/31", "2031-12-31"),
        (1956527999999, "2032-W01", "2031-12", "W01/31", "12/31", "2031-12-31"),
        (1939248000000, "2031-W24", "2031-06", "W24/31", "06/31", "2031-06-15"),
        (1939334399999, "2031-W24", "2031-06", "W24/31", "06/31", "2031-06-15"),
        (1956528000000, "2032-W01", "2032-01", "W01/32", "01/32", "2032-01-01"),
        (1956614399999, "2032-W01", "2032-01", "W01/32", "01/32", "2032-01-01"),
        (1956614400000, "2032-W01", "2032-01", "W01/32", "01/32", "2032-01-02"),
        (1956700799999, "2032-W01", "2032-01", "W01/32", "01/32", "2032-01-02"),
        (1956700800000, "2032-W01", "2032-01", "W01/32", "01/32", "2032-01-03"),
        (1956787199999, "2032-W01", "2032-01", "W01/32", "01/32", "2032-01-03"),
        (1956787200000, "2032-W01", "2032-01", "W01/32", "01/32", "2032-01-04"),
        (1956873599999, "2032-W01", "2032-01", "W01/32", "01/32", "2032-01-04"),
        (1956873600000, "2032-W02", "2032-01", "W02/32", "01/32", "2032-01-05"),
        (1956959999999, "2032-W02", "2032-01", "W02/32", "01/32", "2032-01-05"),
        (1956960000000, "2032-W02", "2032-01", "W02/32", "01/32", "2032-01-06"),
        (1957046399999, "2032-W02", "2032-01", "W02/32", "01/32", "2032-01-06"),
        (1957046400000, "2032-W02", "2032-01", "W02/32", "01/32", "2032-01-07"),
        (1957132799999, "2032-W02", "2032-01", "W02/32", "01/32", "2032-01-07"),
        (1987545600000, "2032-W52", "2032-12", "W52/32", "12/32", "2032-12-25"),
        (1987631999999, "2032-W52", "2032-12", "W52/32", "12/32", "2032-12-25"),
        (1987804800000, "2032-W53", "2032-12", "W53/32", "12/32", "2032-12-28"),
        (1987891199999, "2032-W53", "2032-12", "W53/32", "12/32", "2032-12-28"),
        (1987891200000, "2032-W53", "2032-12", "W53/32", "12/32", "2032-12-29"),
        (1987977599999, "2032-W53", "2032-12", "W53/32", "12/32", "2032-12-29"),
        (1987977600000, "2032-W53", "2032-12", "W53/32", "12/32", "2032-12-30"),
        (1988063999999, "2032-W53", "2032-12", "W53/32", "12/32", "2032-12-30"),
        (1988064000000, "2032-W53", "2032-12", "W53/32", "12/32", "2032-12-31"),
        (1988150399999, "2032-W53", "2032-12", "W53/32", "12/32", "2032-12-31"),
        (1970870400000, "2032-W25", "2032-06", "W25/32", "06/32", "2032-06-15"),
        (1970956799999, "2032-W25", "2032-06", "W25/32", "06/32", "2032-06-15"),
        (1988150400000, "2032-W53", "2033-01", "W53/33", "01/33", "2033-01-01"),
        (1988236799999, "2032-W53", "2033-01", "W53/33", "01/33", "2033-01-01"),
        (1988236800000, "2032-W53", "2033-01", "W53/33", "01/33", "2033-01-02"),
        (1988323199999, "2032-W53", "2033-01", "W53/33", "01/33", "2033-01-02"),
        (1988323200000, "2033-W01", "2033-01", "W01/33", "01/33", "2033-01-03"),
        (1988409599999, "2033-W01", "2033-01", "W01/33", "01/33", "2033-01-03"),
        (1988409600000, "2033-W01", "2033-01", "W01/33", "01/33", "2033-01-04"),
        (1988495999999, "2033-W01", "2033-01", "W01/33", "01/33", "2033-01-04"),
        (1988496000000, "2033-W01", "2033-01", "W01/33", "01/33", "2033-01-05"),
        (1988582399999, "2033-W01", "2033-01", "W01/33", "01/33", "2033-01-05"),
        (1988582400000, "2033-W01", "2033-01", "W01/33", "01/33", "2033-01-06"),
        (1988668799999, "2033-W01", "2033-01", "W01/33", "01/33", "2033-01-06"),
        (1988668800000, "2033-W01", "2033-01", "W01/33", "01/33", "2033-01-07"),
        (1988755199999, "2033-W01", "2033-01", "W01/33", "01/33", "2033-01-07"),
        (2019081600000, "2033-W51", "2033-12", "W51/33", "12/33", "2033-12-25"),
        (2019167999999, "2033-W51", "2033-12", "W51/33", "12/33", "2033-12-25"),
        (2019340800000, "2033-W52", "2033-12", "W52/33", "12/33", "2033-12-28"),
        (2019427199999, "2033-W52", "2033-12", "W52/33", "12/33", "2033-12-28"),
        (2019427200000, "2033-W52", "2033-12", "W52/33", "12/33", "2033-12-29"),
        (2019513599999, "2033-W52", "2033-12", "W52/33", "12/33", "2033-12-29"),
        (2019513600000, "2033-W52", "2033-12", "W52/33", "12/33", "2033-12-30"),
        (2019599999999, "2033-W52", "2033-12", "W52/33", "12/33", "2033-12-30"),
        (2019600000000, "2033-W52", "2033-12", "W52/33", "12/33", "2033-12-31"),
        (2019686399999, "2033-W52", "2033-12", "W52/33", "12/33", "2033-12-31"),
        (2002406400000, "2033-W24", "2033-06", "W24/33", "06/33", "2033-06-15"),
        (2002492799999, "2033-W24", "2033-06", "W24/33", "06/33", "2033-06-15"),
        (2019686400000, "2033-W52", "2034-01", "W52/34", "01/34", "2034-01-01"),
        (2019772799999, "2033-W52", "2034-01", "W52/34", "01/34", "2034-01-01"),
        (2019772800000, "2034-W01", "2034-01", "W01/34", "01/34", "2034-01-02"),
        (2019859199999, "2034-W01", "2034-01", "W01/34", "01/34", "2034-01-02"),
        (2019859200000, "2034-W01", "2034-01", "W01/34", "01/34", "2034-01-03"),
        (2019945599999, "2034-W01", "2034-01", "W01/34", "01/34", "2034-01-03"),
        (2019945600000, "2034-W01", "2034-01", "W01/34", "01/34", "2034-01-04"),
        (2020031999999, "2034-W01", "2034-01", "W01/34", "01/34", "2034-01-04"),
        (2020032000000, "2034-W01", "2034-01", "W01/34", "01/34", "2034-01-05"),
        (2020118399999, "2034-W01", "2034-01", "W01/34", "01/34", "2034-01-05"),
        (2020118400000, "2034-W01", "2034-01", "W01/34", "01/34", "2034-01-06"),
        (2020204799999, "2034-W01", "2034-01", "W01/34", "01/34", "2034-01-06"),
        (2020204800000, "2034-W01", "2034-01", "W01/34", "01/34", "2034-01-07"),
        (2020291199999, "2034-W01", "2034-01", "W01/34", "01/34", "2034-01-07"),
        (2050617600000, "2034-W52", "2034-12", "W52/34", "12/34", "2034-12-25"),
        (2050703999999, "2034-W52", "2034-12", "W52/34", "12/34", "2034-12-25"),
        (2050876800000, "2034-W52", "2034-12", "W52/34", "12/34", "2034-12-28"),
        (2050963199999, "2034-W52", "2034-12", "W52/34", "12/34", "2034-12-28"),
        (2050963200000, "2034-W52", "2034-12", "W52/34", "12/34", "2034-12-29"),
        (2051049599999, "2034-W52", "2034-12", "W52/34", "12/34", "2034-12-29"),
        (2051049600000, "2034-W52", "2034-12", "W52/34", "12/34", "2034-12-30"),
        (2051135999999, "2034-W52", "2034-12", "W52/34", "12/34", "2034-12-30"),
        (2051136000000, "2034-W52", "2034-12", "W52/34", "12/34", "2034-12-31"),
        (2051222399999, "2034-W52", "2034-12", "W52/34", "12/34", "2034-12-31"),
        (2033942400000, "2034-W24", "2034-06", "W24/34", "06/34", "2034-06-15"),
        (2034028799999, "2034-W24", "2034-06", "W24/34", "06/34", "2034-06-15"),
        (2051222400000, "2035-W01", "2035-01", "W01/35", "01/35", "2035-01-01"),
        (2051308799999, "2035-W01", "2035-01", "W01/35", "01/35", "2035-01-01"),
        (2051308800000, "2035-W01", "2035-01", "W01/35", "01/35", "2035-01-02"),
        (2051395199999, "2035-W01", "2035-01", "W01/35", "01/35", "2035-01-02"),
        (2051395200000, "2035-W01", "2035-01", "W01/35", "01/35", "2035-01-03"),
        (2051481599999, "2035-W01", "2035-01", "W01/35", "01/35", "2035-01-03"),
        (2051481600000, "2035-W01", "2035-01", "W01/35", "01/35", "2035-01-04"),
        (2051567999999, "2035-W01", "2035-01", "W01/35", "01/35", "2035-01-04"),
        (2051568000000, "2035-W01", "2035-01", "W01/35", "01/35", "2035-01-05"),
        (2051654399999, "2035-W01", "2035-01", "W01/35", "01/35", "2035-01-05"),
        (2051654400000, "2035-W01", "2035-01", "W01/35", "01/35", "2035-01-06"),
        (2051740799999, "2035-W01", "2035-01", "W01/35", "01/35", "2035-01-06"),
        (2051740800000, "2035-W01", "2035-01", "W01/35", "01/35", "2035-01-07"),
        (2051827199999, "2035-W01", "2035-01", "W01/35", "01/35", "2035-01-07"),
        (2082153600000, "2035-W52", "2035-12", "W52/35", "12/35", "2035-12-25"),
        (2082239999999, "2035-W52", "2035-12", "W52/35", "12/35", "2035-12-25"),
        (2082412800000, "2035-W52", "2035-12", "W52/35", "12/35", "2035-12-28"),
        (2082499199999, "2035-W52", "2035-12", "W52/35", "12/35", "2035-12-28"),
        (2082499200000, "2035-W52", "2035-12", "W52/35", "12/35", "2035-12-29"),
        (2082585599999, "2035-W52", "2035-12", "W52/35", "12/35", "2035-12-29"),
        (2082585600000, "2035-W52", "2035-12", "W52/35", "12/35", "2035-12-30"),
        (2082671999999, "2035-W52", "2035-12", "W52/35", "12/35", "2035-12-30"),
        (2082672000000, "2036-W01", "2035-12", "W01/35", "12/35", "2035-12-31"),
        (2082758399999, "2036-W01", "2035-12", "W01/35", "12/35", "2035-12-31"),
        (2065478400000, "2035-W24", "2035-06", "W24/35", "06/35", "2035-06-15"),
        (2065564799999, "2035-W24", "2035-06", "W24/35", "06/35", "2035-06-15"),
        (1879273671780, "2029-W29", "2029-07", "W29/29", "07/29", "2029-07-20"),
        (1851288260648, "2028-W35", "2028-08", "W35/28", "08/28", "2028-08-30"),
        (1614919301672, "2021-W09", "2021-03", "W09/21", "03/21", "2021-03-05"),
        (1594949043167, "2020-W29", "2020-07", "W29/20", "07/20", "2020-07-17"),
        (1840132952023, "2028-W16", "2028-04", "W16/28", "04/28", "2028-04-23"),
        (1990235611592, "2033-W04", "2033-01", "W04/33", "01/33", "2033-01-25"),
        (1652828473365, "2022-W20", "2022-05", "W20/22", "05/22", "2022-05-17"),
        (1594109345524, "2020-W28", "2020-07", "W28/20", "07/20", "2020-07-07"),
        (1712706281679, "2024-W15", "2024-04", "W15/24", "04/24", "2024-04-09"),
        (1914200423486, "2030-W35", "2030-08", "W35/30", "08/30", "2030-08-29"),
        (2000305968813, "2033-W20", "2033-05", "W20/33", "05/33", "2033-05-21"),
        (1695562551489, "2023-W38", "2023-09", "W38/23", "09/23", "2023-09-24"),
        (1893375186111, "2030-W01", "2029-12", "W01/29", "12/29", "2029-12-31"),
        (1664052855885, "2022-W38", "2022-09", "W38/22", "09/22", "2022-09-24"),
        (1532023181089, "2018-W29", "2018-07", "W29/18", "07/18", "2018-07-19"),
        (1795195534957, "2026-W47", "2026-11", "W47/26", "11/26", "2026-11-20"),
        (1552465620625, "2019-W11", "2019-03", "W11/19", "03/19", "2019-03-13"),
        (1941380411973, "2031-W28", "2031-07", "W28/31", "07/31", "2031-07-09"),
        (1528766095807, "2018-W24", "2018-06", "W24/18", "06/18", "2018-06-12"),
        (1790826366869, "2026-W40", "2026-10", "W40/26", "10/26", "2026-10-01"),
        (1894242531292, "2030-W02", "2030-01", "W02/30", "01/30", "2030-01-10"),
        (1780483657982, "2026-W23", "2026-06", "W23/26", "06/26", "2026-06-03"),
        (1786154265903, "2026-W32", "2026-08", "W32/26", "08/26", "2026-08-08"),
        (1895018559072, "2030-W03", "2030-01", "W03/30", "01/30", "2030-01-19"),
        (1439900084271, "2015-W34", "2015-08", "W34/15", "08/15", "2015-08-18"),
        (1645972273017, "2022-W08", "2022-02", "W08/22", "02/22", "2022-02-27"),
        (1936224568490, "2031-W19", "2031-05", "W19/31", "05/31", "2031-05-11"),
        (1683694730508, "2023-W19", "2023-05", "W19/23", "05/23", "2023-05-10"),
        (2034834968447, "2034-W25", "2034-06", "W25/34", "06/34", "2034-06-25"),
        (1870338186437, "2029-W14", "2029-04", "W14/29", "04/29", "2029-04-08"),
        (1723385967273, "2024-W32", "2024-08", "W32/24", "08/24", "2024-08-11"),
        (1604149981654, "2020-W44", "2020-10", "W44/20", "10/20", "2020-10-31"),
        (2019576523710, "2033-W52", "2033-12", "W52/33", "12/33", "2033-12-30"),
        (1937925455313, "2031-W22", "2031-05", "W22/31", "05/31", "2031-05-30"),
        (1821889879668, "2027-W38", "2027-09", "W38/27", "09/27", "2027-09-25"),
        (1653042169144, "2022-W20", "2022-05", "W20/22", "05/22", "2022-05-20"),
        (1647445985097, "2022-W11", "2022-03", "W11/22", "03/22", "2022-03-16"),
        (1694407613208, "2023-W37", "2023-09", "W37/23", "09/23", "2023-09-11"),
        (1708706998793, "2024-W08", "2024-02", "W08/24", "02/24", "2024-02-23"),
        (1718408642212, "2024-W24", "2024-06", "W24/24", "06/24", "2024-06-14"),
        (1716094901931, "2024-W20", "2024-05", "W20/24", "05/24", "2024-05-19"),
        (1942236602561, "2031-W29", "2031-07", "W29/31", "07/31", "2031-07-19"),
        (1515394267703, "2018-W02", "2018-01", "W02/18", "01/18", "2018-01-08"),
        (1946366742233, "2031-W36", "2031-09", "W36/31", "09/31", "2031-09-05"),
        (1710593687717, "2024-W11", "2024-03", "W11/24", "03/24", "2024-03-16"),
        (1597153973688, "2020-W33", "2020-08", "W33/20", "08/20", "2020-08-11"),
        (1543753601443, "2018-W48", "2018-12", "W48/18", "12/18", "2018-12-02"),
        (1533219190755, "2018-W31", "2018-08", "W31/18", "08/18", "2018-08-02"),
        (1966450352875, "2032-W17", "2032-04", "W17/32", "04/32", "2032-04-24"),
        (1727183069392, "2024-W39", "2024-09", "W39/24", "09/24", "2024-09-24"),
        (1685767534583, "2023-W22", "2023-06", "W22/23", "06/23", "2023-06-03"),
        (1819507434552, "2027-W34", "2027-08", "W34/27", "08/27", "2027-08-29"),
        (1861787583551, "2028-W52", "2028-12", "W52/28", "12/28", "2028-12-30"),
        (1619090581910, "2021-W16", "2021-04", "W16/21", "04/21", "2021-04-22"),
        (1780849699075, "2026-W23", "2026-06", "W23/26", "06/26", "2026-06-07"),
        (1654235548658, "2022-W22", "2022-06", "W22/22", "06/22", "2022-06-03"),
        (1970317925872, "2032-W24", "2032-06", "W24/32", "06/32", "2032-06-08"),
        (1928609095923, "2031-W07", "2031-02", "W07/31", "02/31", "2031-02-11"),
        (1808994899737, "2027-W17", "2027-04", "W17/27", "04/27", "2027-04-29"),
        (1656348056314, "2022-W26", "2022-06", "W26/22", "06/22", "2022-06-27"),
        (0, "1970-W01", "1970-01", "W01/70", "01/70", "1970-01-01"),
        (1760000000000, "2025-W41", "2025-10", "W41/25", "10/25", "2025-10-09"),
        (1760040272716, "2025-W41", "2025-10", "W41/25", "10/25", "2025-10-09"),
        (1767225599999, "2026-W01", "2025-12", "W01/25", "12/25", "2025-12-31"),
        (1767225600000, "2026-W01", "2026-01", "W01/26", "01/26", "2026-01-01"),
    ]
    /// (ms, zone, "dd/MM/yyyy HH:mm" in Locale("he"), Progress weekKey, Progress monthKey) in a named zone.
    static let zonedDates: [(Int64, String, String, String, String)] = [
        (1420070400000, "Asia/Jerusalem", "01/01/2015 02:00", "W01/15", "01/15"),
        (1420070400000, "America/New_York", "31/12/2014 19:00", "W01/14", "12/14"),
        (1420070400000, "Asia/Tokyo", "01/01/2015 09:00", "W01/15", "01/15"),
        (1420156799999, "Asia/Jerusalem", "02/01/2015 01:59", "W01/15", "01/15"),
        (1420156799999, "America/New_York", "01/01/2015 18:59", "W01/15", "01/15"),
        (1420156799999, "Asia/Tokyo", "02/01/2015 08:59", "W01/15", "01/15"),
        (1420156800000, "Asia/Jerusalem", "02/01/2015 02:00", "W01/15", "01/15"),
        (1420156800000, "America/New_York", "01/01/2015 19:00", "W01/15", "01/15"),
        (1420156800000, "Asia/Tokyo", "02/01/2015 09:00", "W01/15", "01/15"),
        (1420243199999, "Asia/Jerusalem", "03/01/2015 01:59", "W01/15", "01/15"),
        (1420243199999, "America/New_York", "02/01/2015 18:59", "W01/15", "01/15"),
        (1420243199999, "Asia/Tokyo", "03/01/2015 08:59", "W01/15", "01/15"),
        (1420243200000, "Asia/Jerusalem", "03/01/2015 02:00", "W01/15", "01/15"),
        (1420243200000, "America/New_York", "02/01/2015 19:00", "W01/15", "01/15"),
        (1420243200000, "Asia/Tokyo", "03/01/2015 09:00", "W01/15", "01/15"),
        (1420329599999, "Asia/Jerusalem", "04/01/2015 01:59", "W01/15", "01/15"),
        (1420329599999, "America/New_York", "03/01/2015 18:59", "W01/15", "01/15"),
        (1420329599999, "Asia/Tokyo", "04/01/2015 08:59", "W01/15", "01/15"),
        (1420329600000, "Asia/Jerusalem", "04/01/2015 02:00", "W01/15", "01/15"),
        (1420329600000, "America/New_York", "03/01/2015 19:00", "W01/15", "01/15"),
        (1420329600000, "Asia/Tokyo", "04/01/2015 09:00", "W01/15", "01/15"),
        (1420415999999, "Asia/Jerusalem", "05/01/2015 01:59", "W02/15", "01/15"),
        (1420415999999, "America/New_York", "04/01/2015 18:59", "W01/15", "01/15"),
        (1420415999999, "Asia/Tokyo", "05/01/2015 08:59", "W02/15", "01/15"),
        (1420416000000, "Asia/Jerusalem", "05/01/2015 02:00", "W02/15", "01/15"),
        (1420416000000, "America/New_York", "04/01/2015 19:00", "W01/15", "01/15"),
        (1420416000000, "Asia/Tokyo", "05/01/2015 09:00", "W02/15", "01/15"),
        (1420502399999, "Asia/Jerusalem", "06/01/2015 01:59", "W02/15", "01/15"),
        (1420502399999, "America/New_York", "05/01/2015 18:59", "W02/15", "01/15"),
        (1420502399999, "Asia/Tokyo", "06/01/2015 08:59", "W02/15", "01/15"),
        (1420502400000, "Asia/Jerusalem", "06/01/2015 02:00", "W02/15", "01/15"),
        (1420502400000, "America/New_York", "05/01/2015 19:00", "W02/15", "01/15"),
        (1420502400000, "Asia/Tokyo", "06/01/2015 09:00", "W02/15", "01/15"),
        (1420588799999, "Asia/Jerusalem", "07/01/2015 01:59", "W02/15", "01/15"),
        (1420588799999, "America/New_York", "06/01/2015 18:59", "W02/15", "01/15"),
        (1420588799999, "Asia/Tokyo", "07/01/2015 08:59", "W02/15", "01/15"),
        (1420588800000, "Asia/Jerusalem", "07/01/2015 02:00", "W02/15", "01/15"),
        (1420588800000, "America/New_York", "06/01/2015 19:00", "W02/15", "01/15"),
        (1420588800000, "Asia/Tokyo", "07/01/2015 09:00", "W02/15", "01/15"),
        (1420675199999, "Asia/Jerusalem", "08/01/2015 01:59", "W02/15", "01/15"),
        (1420675199999, "America/New_York", "07/01/2015 18:59", "W02/15", "01/15"),
        (1420675199999, "Asia/Tokyo", "08/01/2015 08:59", "W02/15", "01/15"),
        (1451001600000, "Asia/Jerusalem", "25/12/2015 02:00", "W52/15", "12/15"),
        (1451001600000, "America/New_York", "24/12/2015 19:00", "W52/15", "12/15"),
        (1451001600000, "Asia/Tokyo", "25/12/2015 09:00", "W52/15", "12/15"),
        (1451087999999, "Asia/Jerusalem", "26/12/2015 01:59", "W52/15", "12/15"),
        (1451087999999, "America/New_York", "25/12/2015 18:59", "W52/15", "12/15"),
        (1451087999999, "Asia/Tokyo", "26/12/2015 08:59", "W52/15", "12/15"),
        (1451260800000, "Asia/Jerusalem", "28/12/2015 02:00", "W53/15", "12/15"),
        (1451260800000, "America/New_York", "27/12/2015 19:00", "W52/15", "12/15"),
        (1451260800000, "Asia/Tokyo", "28/12/2015 09:00", "W53/15", "12/15"),
        (1451347199999, "Asia/Jerusalem", "29/12/2015 01:59", "W53/15", "12/15"),
        (1451347199999, "America/New_York", "28/12/2015 18:59", "W53/15", "12/15"),
        (1451347199999, "Asia/Tokyo", "29/12/2015 08:59", "W53/15", "12/15"),
        (1451347200000, "Asia/Jerusalem", "29/12/2015 02:00", "W53/15", "12/15"),
        (1451347200000, "America/New_York", "28/12/2015 19:00", "W53/15", "12/15"),
        (1451347200000, "Asia/Tokyo", "29/12/2015 09:00", "W53/15", "12/15"),
        (1451433599999, "Asia/Jerusalem", "30/12/2015 01:59", "W53/15", "12/15"),
        (1451433599999, "America/New_York", "29/12/2015 18:59", "W53/15", "12/15"),
        (1451433599999, "Asia/Tokyo", "30/12/2015 08:59", "W53/15", "12/15"),
        (1451433600000, "Asia/Jerusalem", "30/12/2015 02:00", "W53/15", "12/15"),
        (1451433600000, "America/New_York", "29/12/2015 19:00", "W53/15", "12/15"),
        (1451433600000, "Asia/Tokyo", "30/12/2015 09:00", "W53/15", "12/15"),
        (1451519999999, "Asia/Jerusalem", "31/12/2015 01:59", "W53/15", "12/15"),
        (1451519999999, "America/New_York", "30/12/2015 18:59", "W53/15", "12/15"),
        (1451519999999, "Asia/Tokyo", "31/12/2015 08:59", "W53/15", "12/15"),
        (1451520000000, "Asia/Jerusalem", "31/12/2015 02:00", "W53/15", "12/15"),
        (1451520000000, "America/New_York", "30/12/2015 19:00", "W53/15", "12/15"),
        (1451520000000, "Asia/Tokyo", "31/12/2015 09:00", "W53/15", "12/15"),
        (1451606399999, "Asia/Jerusalem", "01/01/2016 01:59", "W53/16", "01/16"),
        (1451606399999, "America/New_York", "31/12/2015 18:59", "W53/15", "12/15"),
        (1451606399999, "Asia/Tokyo", "01/01/2016 08:59", "W53/16", "01/16"),
        (1434326400000, "Asia/Jerusalem", "15/06/2015 03:00", "W25/15", "06/15"),
        (1434326400000, "America/New_York", "14/06/2015 20:00", "W24/15", "06/15"),
        (1434326400000, "Asia/Tokyo", "15/06/2015 09:00", "W25/15", "06/15"),
        (1434412799999, "Asia/Jerusalem", "16/06/2015 02:59", "W25/15", "06/15"),
        (1434412799999, "America/New_York", "15/06/2015 19:59", "W25/15", "06/15"),
        (1434412799999, "Asia/Tokyo", "16/06/2015 08:59", "W25/15", "06/15"),
        (1451606400000, "Asia/Jerusalem", "01/01/2016 02:00", "W53/16", "01/16"),
        (1451606400000, "America/New_York", "31/12/2015 19:00", "W53/15", "12/15"),
        (1451606400000, "Asia/Tokyo", "01/01/2016 09:00", "W53/16", "01/16"),
        (1451692799999, "Asia/Jerusalem", "02/01/2016 01:59", "W53/16", "01/16"),
        (1451692799999, "America/New_York", "01/01/2016 18:59", "W53/16", "01/16"),
        (1451692799999, "Asia/Tokyo", "02/01/2016 08:59", "W53/16", "01/16"),
        (1451692800000, "Asia/Jerusalem", "02/01/2016 02:00", "W53/16", "01/16"),
        (1451692800000, "America/New_York", "01/01/2016 19:00", "W53/16", "01/16"),
        (1451692800000, "Asia/Tokyo", "02/01/2016 09:00", "W53/16", "01/16"),
        (1451779199999, "Asia/Jerusalem", "03/01/2016 01:59", "W53/16", "01/16"),
        (1451779199999, "America/New_York", "02/01/2016 18:59", "W53/16", "01/16"),
        (1451779199999, "Asia/Tokyo", "03/01/2016 08:59", "W53/16", "01/16"),
        (1451779200000, "Asia/Jerusalem", "03/01/2016 02:00", "W53/16", "01/16"),
        (1451779200000, "America/New_York", "02/01/2016 19:00", "W53/16", "01/16"),
        (1451779200000, "Asia/Tokyo", "03/01/2016 09:00", "W53/16", "01/16"),
        (1451865599999, "Asia/Jerusalem", "04/01/2016 01:59", "W01/16", "01/16"),
        (1451865599999, "America/New_York", "03/01/2016 18:59", "W53/16", "01/16"),
        (1451865599999, "Asia/Tokyo", "04/01/2016 08:59", "W01/16", "01/16"),
        (1451865600000, "Asia/Jerusalem", "04/01/2016 02:00", "W01/16", "01/16"),
        (1451865600000, "America/New_York", "03/01/2016 19:00", "W53/16", "01/16"),
        (1451865600000, "Asia/Tokyo", "04/01/2016 09:00", "W01/16", "01/16"),
        (1451951999999, "Asia/Jerusalem", "05/01/2016 01:59", "W01/16", "01/16"),
        (1451951999999, "America/New_York", "04/01/2016 18:59", "W01/16", "01/16"),
        (1451951999999, "Asia/Tokyo", "05/01/2016 08:59", "W01/16", "01/16"),
        (1451952000000, "Asia/Jerusalem", "05/01/2016 02:00", "W01/16", "01/16"),
        (1451952000000, "America/New_York", "04/01/2016 19:00", "W01/16", "01/16"),
        (1451952000000, "Asia/Tokyo", "05/01/2016 09:00", "W01/16", "01/16"),
        (1452038399999, "Asia/Jerusalem", "06/01/2016 01:59", "W01/16", "01/16"),
        (1452038399999, "America/New_York", "05/01/2016 18:59", "W01/16", "01/16"),
        (1452038399999, "Asia/Tokyo", "06/01/2016 08:59", "W01/16", "01/16"),
        (1452038400000, "Asia/Jerusalem", "06/01/2016 02:00", "W01/16", "01/16"),
        (1452038400000, "America/New_York", "05/01/2016 19:00", "W01/16", "01/16"),
        (1452038400000, "Asia/Tokyo", "06/01/2016 09:00", "W01/16", "01/16"),
        (1452124799999, "Asia/Jerusalem", "07/01/2016 01:59", "W01/16", "01/16"),
        (1452124799999, "America/New_York", "06/01/2016 18:59", "W01/16", "01/16"),
        (1452124799999, "Asia/Tokyo", "07/01/2016 08:59", "W01/16", "01/16"),
        (1452124800000, "Asia/Jerusalem", "07/01/2016 02:00", "W01/16", "01/16"),
        (1452124800000, "America/New_York", "06/01/2016 19:00", "W01/16", "01/16"),
        (1452124800000, "Asia/Tokyo", "07/01/2016 09:00", "W01/16", "01/16"),
        (1452211199999, "Asia/Jerusalem", "08/01/2016 01:59", "W01/16", "01/16"),
        (1452211199999, "America/New_York", "07/01/2016 18:59", "W01/16", "01/16"),
        (1452211199999, "Asia/Tokyo", "08/01/2016 08:59", "W01/16", "01/16"),
        (1482624000000, "Asia/Jerusalem", "25/12/2016 02:00", "W51/16", "12/16"),
        (1482624000000, "America/New_York", "24/12/2016 19:00", "W51/16", "12/16"),
        (1482624000000, "Asia/Tokyo", "25/12/2016 09:00", "W51/16", "12/16"),
        (1482710399999, "Asia/Jerusalem", "26/12/2016 01:59", "W52/16", "12/16"),
        (1482710399999, "America/New_York", "25/12/2016 18:59", "W51/16", "12/16"),
        (1482710399999, "Asia/Tokyo", "26/12/2016 08:59", "W52/16", "12/16"),
        (1482883200000, "Asia/Jerusalem", "28/12/2016 02:00", "W52/16", "12/16"),
        (1482883200000, "America/New_York", "27/12/2016 19:00", "W52/16", "12/16"),
        (1482883200000, "Asia/Tokyo", "28/12/2016 09:00", "W52/16", "12/16"),
        (1482969599999, "Asia/Jerusalem", "29/12/2016 01:59", "W52/16", "12/16"),
        (1482969599999, "America/New_York", "28/12/2016 18:59", "W52/16", "12/16"),
        (1482969599999, "Asia/Tokyo", "29/12/2016 08:59", "W52/16", "12/16"),
        (1482969600000, "Asia/Jerusalem", "29/12/2016 02:00", "W52/16", "12/16"),
        (1482969600000, "America/New_York", "28/12/2016 19:00", "W52/16", "12/16"),
        (1482969600000, "Asia/Tokyo", "29/12/2016 09:00", "W52/16", "12/16"),
        (1483055999999, "Asia/Jerusalem", "30/12/2016 01:59", "W52/16", "12/16"),
        (1483055999999, "America/New_York", "29/12/2016 18:59", "W52/16", "12/16"),
        (1483055999999, "Asia/Tokyo", "30/12/2016 08:59", "W52/16", "12/16"),
        (1483056000000, "Asia/Jerusalem", "30/12/2016 02:00", "W52/16", "12/16"),
        (1483056000000, "America/New_York", "29/12/2016 19:00", "W52/16", "12/16"),
        (1483056000000, "Asia/Tokyo", "30/12/2016 09:00", "W52/16", "12/16"),
        (1483142399999, "Asia/Jerusalem", "31/12/2016 01:59", "W52/16", "12/16"),
        (1483142399999, "America/New_York", "30/12/2016 18:59", "W52/16", "12/16"),
        (1483142399999, "Asia/Tokyo", "31/12/2016 08:59", "W52/16", "12/16"),
        (1483142400000, "Asia/Jerusalem", "31/12/2016 02:00", "W52/16", "12/16"),
        (1483142400000, "America/New_York", "30/12/2016 19:00", "W52/16", "12/16"),
        (1483142400000, "Asia/Tokyo", "31/12/2016 09:00", "W52/16", "12/16"),
        (1483228799999, "Asia/Jerusalem", "01/01/2017 01:59", "W52/17", "01/17"),
        (1483228799999, "America/New_York", "31/12/2016 18:59", "W52/16", "12/16"),
        (1483228799999, "Asia/Tokyo", "01/01/2017 08:59", "W52/17", "01/17"),
        (1465948800000, "Asia/Jerusalem", "15/06/2016 03:00", "W24/16", "06/16"),
        (1465948800000, "America/New_York", "14/06/2016 20:00", "W24/16", "06/16"),
        (1465948800000, "Asia/Tokyo", "15/06/2016 09:00", "W24/16", "06/16"),
        (1466035199999, "Asia/Jerusalem", "16/06/2016 02:59", "W24/16", "06/16"),
        (1466035199999, "America/New_York", "15/06/2016 19:59", "W24/16", "06/16"),
        (1466035199999, "Asia/Tokyo", "16/06/2016 08:59", "W24/16", "06/16"),
        (1483228800000, "Asia/Jerusalem", "01/01/2017 02:00", "W52/17", "01/17"),
        (1483228800000, "America/New_York", "31/12/2016 19:00", "W52/16", "12/16"),
        (1483228800000, "Asia/Tokyo", "01/01/2017 09:00", "W52/17", "01/17"),
        (1483315199999, "Asia/Jerusalem", "02/01/2017 01:59", "W01/17", "01/17"),
        (1483315199999, "America/New_York", "01/01/2017 18:59", "W52/17", "01/17"),
        (1483315199999, "Asia/Tokyo", "02/01/2017 08:59", "W01/17", "01/17"),
        (1483315200000, "Asia/Jerusalem", "02/01/2017 02:00", "W01/17", "01/17"),
        (1483315200000, "America/New_York", "01/01/2017 19:00", "W52/17", "01/17"),
        (1483315200000, "Asia/Tokyo", "02/01/2017 09:00", "W01/17", "01/17"),
        (1483401599999, "Asia/Jerusalem", "03/01/2017 01:59", "W01/17", "01/17"),
        (1483401599999, "America/New_York", "02/01/2017 18:59", "W01/17", "01/17"),
        (1483401599999, "Asia/Tokyo", "03/01/2017 08:59", "W01/17", "01/17"),
        (1483401600000, "Asia/Jerusalem", "03/01/2017 02:00", "W01/17", "01/17"),
        (1483401600000, "America/New_York", "02/01/2017 19:00", "W01/17", "01/17"),
        (1483401600000, "Asia/Tokyo", "03/01/2017 09:00", "W01/17", "01/17"),
        (1483487999999, "Asia/Jerusalem", "04/01/2017 01:59", "W01/17", "01/17"),
        (1483487999999, "America/New_York", "03/01/2017 18:59", "W01/17", "01/17"),
        (1483487999999, "Asia/Tokyo", "04/01/2017 08:59", "W01/17", "01/17"),
        (1483488000000, "Asia/Jerusalem", "04/01/2017 02:00", "W01/17", "01/17"),
        (1483488000000, "America/New_York", "03/01/2017 19:00", "W01/17", "01/17"),
        (1483488000000, "Asia/Tokyo", "04/01/2017 09:00", "W01/17", "01/17"),
        (1483574399999, "Asia/Jerusalem", "05/01/2017 01:59", "W01/17", "01/17"),
        (1483574399999, "America/New_York", "04/01/2017 18:59", "W01/17", "01/17"),
        (1483574399999, "Asia/Tokyo", "05/01/2017 08:59", "W01/17", "01/17"),
        (1483574400000, "Asia/Jerusalem", "05/01/2017 02:00", "W01/17", "01/17"),
        (1483574400000, "America/New_York", "04/01/2017 19:00", "W01/17", "01/17"),
        (1483574400000, "Asia/Tokyo", "05/01/2017 09:00", "W01/17", "01/17"),
        (1483660799999, "Asia/Jerusalem", "06/01/2017 01:59", "W01/17", "01/17"),
        (1483660799999, "America/New_York", "05/01/2017 18:59", "W01/17", "01/17"),
        (1483660799999, "Asia/Tokyo", "06/01/2017 08:59", "W01/17", "01/17"),
        (1483660800000, "Asia/Jerusalem", "06/01/2017 02:00", "W01/17", "01/17"),
        (1483660800000, "America/New_York", "05/01/2017 19:00", "W01/17", "01/17"),
        (1483660800000, "Asia/Tokyo", "06/01/2017 09:00", "W01/17", "01/17"),
        (1483747199999, "Asia/Jerusalem", "07/01/2017 01:59", "W01/17", "01/17"),
        (1483747199999, "America/New_York", "06/01/2017 18:59", "W01/17", "01/17"),
        (1483747199999, "Asia/Tokyo", "07/01/2017 08:59", "W01/17", "01/17"),
        (1483747200000, "Asia/Jerusalem", "07/01/2017 02:00", "W01/17", "01/17"),
        (1483747200000, "America/New_York", "06/01/2017 19:00", "W01/17", "01/17"),
        (1483747200000, "Asia/Tokyo", "07/01/2017 09:00", "W01/17", "01/17"),
        (1483833599999, "Asia/Jerusalem", "08/01/2017 01:59", "W01/17", "01/17"),
        (1483833599999, "America/New_York", "07/01/2017 18:59", "W01/17", "01/17"),
        (1483833599999, "Asia/Tokyo", "08/01/2017 08:59", "W01/17", "01/17"),
        (1514160000000, "Asia/Jerusalem", "25/12/2017 02:00", "W52/17", "12/17"),
        (1514160000000, "America/New_York", "24/12/2017 19:00", "W51/17", "12/17"),
        (1514160000000, "Asia/Tokyo", "25/12/2017 09:00", "W52/17", "12/17"),
        (1514246399999, "Asia/Jerusalem", "26/12/2017 01:59", "W52/17", "12/17"),
        (1514246399999, "America/New_York", "25/12/2017 18:59", "W52/17", "12/17"),
        (1514246399999, "Asia/Tokyo", "26/12/2017 08:59", "W52/17", "12/17"),
        (1514419200000, "Asia/Jerusalem", "28/12/2017 02:00", "W52/17", "12/17"),
        (1514419200000, "America/New_York", "27/12/2017 19:00", "W52/17", "12/17"),
        (1514419200000, "Asia/Tokyo", "28/12/2017 09:00", "W52/17", "12/17"),
        (1514505599999, "Asia/Jerusalem", "29/12/2017 01:59", "W52/17", "12/17"),
        (1514505599999, "America/New_York", "28/12/2017 18:59", "W52/17", "12/17"),
        (1514505599999, "Asia/Tokyo", "29/12/2017 08:59", "W52/17", "12/17"),
        (1514505600000, "Asia/Jerusalem", "29/12/2017 02:00", "W52/17", "12/17"),
        (1514505600000, "America/New_York", "28/12/2017 19:00", "W52/17", "12/17"),
        (1514505600000, "Asia/Tokyo", "29/12/2017 09:00", "W52/17", "12/17"),
        (1514591999999, "Asia/Jerusalem", "30/12/2017 01:59", "W52/17", "12/17"),
        (1514591999999, "America/New_York", "29/12/2017 18:59", "W52/17", "12/17"),
        (1514591999999, "Asia/Tokyo", "30/12/2017 08:59", "W52/17", "12/17"),
        (1514592000000, "Asia/Jerusalem", "30/12/2017 02:00", "W52/17", "12/17"),
        (1514592000000, "America/New_York", "29/12/2017 19:00", "W52/17", "12/17"),
        (1514592000000, "Asia/Tokyo", "30/12/2017 09:00", "W52/17", "12/17"),
        (1514678399999, "Asia/Jerusalem", "31/12/2017 01:59", "W52/17", "12/17"),
        (1514678399999, "America/New_York", "30/12/2017 18:59", "W52/17", "12/17"),
        (1514678399999, "Asia/Tokyo", "31/12/2017 08:59", "W52/17", "12/17"),
        (1514678400000, "Asia/Jerusalem", "31/12/2017 02:00", "W52/17", "12/17"),
        (1514678400000, "America/New_York", "30/12/2017 19:00", "W52/17", "12/17"),
        (1514678400000, "Asia/Tokyo", "31/12/2017 09:00", "W52/17", "12/17"),
        (1514764799999, "Asia/Jerusalem", "01/01/2018 01:59", "W01/18", "01/18"),
        (1514764799999, "America/New_York", "31/12/2017 18:59", "W52/17", "12/17"),
        (1514764799999, "Asia/Tokyo", "01/01/2018 08:59", "W01/18", "01/18"),
        (1497484800000, "Asia/Jerusalem", "15/06/2017 03:00", "W24/17", "06/17"),
        (1497484800000, "America/New_York", "14/06/2017 20:00", "W24/17", "06/17"),
        (1497484800000, "Asia/Tokyo", "15/06/2017 09:00", "W24/17", "06/17"),
        (1497571199999, "Asia/Jerusalem", "16/06/2017 02:59", "W24/17", "06/17"),
        (1497571199999, "America/New_York", "15/06/2017 19:59", "W24/17", "06/17"),
        (1497571199999, "Asia/Tokyo", "16/06/2017 08:59", "W24/17", "06/17"),
        (1514764800000, "Asia/Jerusalem", "01/01/2018 02:00", "W01/18", "01/18"),
        (1514764800000, "America/New_York", "31/12/2017 19:00", "W52/17", "12/17"),
        (1514764800000, "Asia/Tokyo", "01/01/2018 09:00", "W01/18", "01/18"),
        (1514851199999, "Asia/Jerusalem", "02/01/2018 01:59", "W01/18", "01/18"),
        (1514851199999, "America/New_York", "01/01/2018 18:59", "W01/18", "01/18"),
        (1514851199999, "Asia/Tokyo", "02/01/2018 08:59", "W01/18", "01/18"),
        (1597153973688, "Asia/Jerusalem", "11/08/2020 16:52", "W33/20", "08/20"),
        (1597153973688, "America/New_York", "11/08/2020 09:52", "W33/20", "08/20"),
        (1597153973688, "Asia/Tokyo", "11/08/2020 22:52", "W33/20", "08/20"),
        (1543753601443, "Asia/Jerusalem", "02/12/2018 14:26", "W48/18", "12/18"),
        (1543753601443, "America/New_York", "02/12/2018 07:26", "W48/18", "12/18"),
        (1543753601443, "Asia/Tokyo", "02/12/2018 21:26", "W48/18", "12/18"),
        (1533219190755, "Asia/Jerusalem", "02/08/2018 17:13", "W31/18", "08/18"),
        (1533219190755, "America/New_York", "02/08/2018 10:13", "W31/18", "08/18"),
        (1533219190755, "Asia/Tokyo", "02/08/2018 23:13", "W31/18", "08/18"),
        (1966450352875, "Asia/Jerusalem", "24/04/2032 23:12", "W17/32", "04/32"),
        (1966450352875, "America/New_York", "24/04/2032 16:12", "W17/32", "04/32"),
        (1966450352875, "Asia/Tokyo", "25/04/2032 05:12", "W17/32", "04/32"),
        (1727183069392, "Asia/Jerusalem", "24/09/2024 16:04", "W39/24", "09/24"),
        (1727183069392, "America/New_York", "24/09/2024 09:04", "W39/24", "09/24"),
        (1727183069392, "Asia/Tokyo", "24/09/2024 22:04", "W39/24", "09/24"),
        (1685767534583, "Asia/Jerusalem", "03/06/2023 07:45", "W22/23", "06/23"),
        (1685767534583, "America/New_York", "03/06/2023 00:45", "W22/23", "06/23"),
        (1685767534583, "Asia/Tokyo", "03/06/2023 13:45", "W22/23", "06/23"),
        (1819507434552, "Asia/Jerusalem", "29/08/2027 05:43", "W34/27", "08/27"),
        (1819507434552, "America/New_York", "28/08/2027 22:43", "W34/27", "08/27"),
        (1819507434552, "Asia/Tokyo", "29/08/2027 11:43", "W34/27", "08/27"),
        (1861787583551, "Asia/Jerusalem", "30/12/2028 13:13", "W52/28", "12/28"),
        (1861787583551, "America/New_York", "30/12/2028 06:13", "W52/28", "12/28"),
        (1861787583551, "Asia/Tokyo", "30/12/2028 20:13", "W52/28", "12/28"),
        (1619090581910, "Asia/Jerusalem", "22/04/2021 14:23", "W16/21", "04/21"),
        (1619090581910, "America/New_York", "22/04/2021 07:23", "W16/21", "04/21"),
        (1619090581910, "Asia/Tokyo", "22/04/2021 20:23", "W16/21", "04/21"),
        (1780849699075, "Asia/Jerusalem", "07/06/2026 19:28", "W23/26", "06/26"),
        (1780849699075, "America/New_York", "07/06/2026 12:28", "W23/26", "06/26"),
        (1780849699075, "Asia/Tokyo", "08/06/2026 01:28", "W24/26", "06/26"),
        (1654235548658, "Asia/Jerusalem", "03/06/2022 08:52", "W22/22", "06/22"),
        (1654235548658, "America/New_York", "03/06/2022 01:52", "W22/22", "06/22"),
        (1654235548658, "Asia/Tokyo", "03/06/2022 14:52", "W22/22", "06/22"),
        (1970317925872, "Asia/Jerusalem", "08/06/2032 17:32", "W24/32", "06/32"),
        (1970317925872, "America/New_York", "08/06/2032 10:32", "W24/32", "06/32"),
        (1970317925872, "Asia/Tokyo", "08/06/2032 23:32", "W24/32", "06/32"),
        (1928609095923, "Asia/Jerusalem", "11/02/2031 22:44", "W07/31", "02/31"),
        (1928609095923, "America/New_York", "11/02/2031 15:44", "W07/31", "02/31"),
        (1928609095923, "Asia/Tokyo", "12/02/2031 05:44", "W07/31", "02/31"),
        (1808994899737, "Asia/Jerusalem", "29/04/2027 13:34", "W17/27", "04/27"),
        (1808994899737, "America/New_York", "29/04/2027 06:34", "W17/27", "04/27"),
        (1808994899737, "Asia/Tokyo", "29/04/2027 19:34", "W17/27", "04/27"),
        (1656348056314, "Asia/Jerusalem", "27/06/2022 19:40", "W26/22", "06/22"),
        (1656348056314, "America/New_York", "27/06/2022 12:40", "W26/22", "06/22"),
        (1656348056314, "Asia/Tokyo", "28/06/2022 01:40", "W26/22", "06/22"),
        (0, "Asia/Jerusalem", "01/01/1970 02:00", "W01/70", "01/70"),
        (0, "America/New_York", "31/12/1969 19:00", "W01/69", "12/69"),
        (0, "Asia/Tokyo", "01/01/1970 09:00", "W01/70", "01/70"),
        (1760000000000, "Asia/Jerusalem", "09/10/2025 11:53", "W41/25", "10/25"),
        (1760000000000, "America/New_York", "09/10/2025 04:53", "W41/25", "10/25"),
        (1760000000000, "Asia/Tokyo", "09/10/2025 17:53", "W41/25", "10/25"),
        (1760040272716, "Asia/Jerusalem", "09/10/2025 23:04", "W41/25", "10/25"),
        (1760040272716, "America/New_York", "09/10/2025 16:04", "W41/25", "10/25"),
        (1760040272716, "Asia/Tokyo", "10/10/2025 05:04", "W41/25", "10/25"),
        (1767225599999, "Asia/Jerusalem", "01/01/2026 01:59", "W01/26", "01/26"),
        (1767225599999, "America/New_York", "31/12/2025 18:59", "W01/25", "12/25"),
        (1767225599999, "Asia/Tokyo", "01/01/2026 08:59", "W01/26", "01/26"),
        (1767225600000, "Asia/Jerusalem", "01/01/2026 02:00", "W01/26", "01/26"),
        (1767225600000, "America/New_York", "31/12/2025 19:00", "W01/25", "12/25"),
        (1767225600000, "Asia/Tokyo", "01/01/2026 09:00", "W01/26", "01/26"),
    ]
    /// (case, XML text, dump of Android's DOM: KXmlParser driven like libcore DocumentBuilderImpl).
    static let xmlCases: [(String, String, String)] = [
        ("c01_full.xml", "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!-- c1 -->\n<root a=\"1\" b='two' c=\"x&amp;y&lt;&#65;&#x42;&unknown;\">\r\n  text &amp; more\r  <child/>tail<![CDATA[ raw <&> ]]>after<?pi data here?><!--in-->x&#x1F600;y&custom;z\n<e2   attr = \"v\tw\nx\r\ny\" ></e2  ></root>\n<!-- c2 -->  \n", "D\n  M  c1 \n  E root {a=1|b=two|c=x&y<AB&unknown;}\n    T \\n  text & more\\n  \n    E child {}\n    T tail\n    C  raw <&> \n    T after\n    P pi data here\n    M in\n    T x\\uD83D\\uDE00y\n    R custom\n    T z\\n\n    E e2 {attr=v\\tw x y}\n  M  c2 \nX root = \\n  text & more\\n  tail raw <&> afterx\\uD83D\\uDE00yz\\n\nX child = \nX e2 = \n"),
        ("c04_dupattr.xml", "<r a=\"1\" b=\"2\" a=\"3\"/>", "D\n  E r {b=2|a=3}\nX r = \n"),
        ("c05_ws.xml", "<r>   <a/>   </r>", "D\n  E r {}\n    T    \n    E a {}\n    T    \nX r =       \nX a = \n"),
        ("c06_emptycdata.xml", "<r><![CDATA[]]>x<![CDATA[y]]>z</r>", "D\n  E r {}\n    T x\n    C y\n    T z\nX r = xyz\n"),
        ("c12_predef.xml", "<r t=\"&lt;&gt;&quot;&apos;&amp;\">&lt;&gt;&quot;&apos;&amp;</r>", "D\n  E r {t=<>\"'&}\n    T <>\"'&\nX r = <>\"'&\n"),
        ("c13_attrnl.xml", "<r a=\"1&#10;2&#13;3&#9;4\" b=\"x\r\ny\rz\nw\"/>", "D\n  E r {a=1\\n2\\r3\\t4|b=x y z w}\nX r = \n"),
        ("c14_crlf.xml", "<r>\r\n line1\r\n line2\r line3\n</r>", "D\n  E r {}\n    T \\n line1\\n line2\\n line3\\n\nX r = \\n line1\\n line2\\n line3\\n\n"),
        ("c17_entity_tokens.xml", "<r>&#65;&#x42;&amp;tail &unknown; more</r>", "D\n  E r {}\n    T AB&tail \n    R unknown\n    T  more\nX r = AB&tail  more\n"),
        ("e02_mismatch.xml", "<r></s>", "ERROR\n"),
    ]
}
