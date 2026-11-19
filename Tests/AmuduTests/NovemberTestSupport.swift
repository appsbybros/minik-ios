import Foundation
@testable import MinikAmudu

/// Shared helpers for the ports of Android's 2026-11 core tests.
enum NovemberSupport {
    /// Kotlin `n[key].node()`.
    static func child(_ n: Node, _ key: String) -> Node {
        return AmuduCodec.node(n[key])
    }

    /// Kotlin `repeat((seconds * hz).toInt()) { e.tick(1.0 / hz) }`.
    static func run(_ e: AmuduEngine, _ seconds: Double, hz: Double) {
        let steps = Int(seconds * hz)
        for _ in 0..<steps { e.tick(1.0 / hz) }
    }

    /// Kotlin `List<Double>.average()` (NaN for an empty list).
    static func average(_ values: [Double]) -> Double {
        return values.reduce(0.0, +) / Double(values.count)
    }

    /// Kotlin `snapshot["x"]` is null: the key is missing or holds JSON null.
    static func isNull(_ value: Any?) -> Bool {
        return AmuduCodec.isNull(value)
    }
}

/// `java.util.Random(seed)`: the 48-bit linear congruential generator Android's tests use for placement.
struct JavaRandom {
    private var seed: UInt64
    private static let multiplier: UInt64 = 0x5DEECE66D
    private static let mask: UInt64 = (1 << 48) - 1

    init(_ seed: Int64) {
        self.seed = (UInt64(bitPattern: seed) ^ JavaRandom.multiplier) & JavaRandom.mask
    }

    private mutating func next(_ bits: Int) -> Int64 {
        seed = (seed &* JavaRandom.multiplier &+ 0xB) & JavaRandom.mask
        return Int64(Int32(truncatingIfNeeded: seed >> UInt64(48 - bits)))
    }

    /// Java `nextDouble()`: `((long) next(26) << 27) + next(27)) * 0x1.0p-53`.
    mutating func nextDouble() -> Double {
        let high = next(26)
        let low = next(27)
        return Double((high << 27) + low) * 0x1.0p-53
    }
}
