import Foundation

/// Android `PaintSplash`: a paint mark on the ground (colour is a signed ARGB Int like Android's `Int`).
struct PaintSplash: Equatable {
    let position: V
    let color: Int
    let seed: Int64
    let at: Double
    let areaScale: Double

    init(_ position: V, _ color: Int, _ seed: Int64, _ at: Double, _ areaScale: Double = 1.0) {
        self.position = position
        self.color = color
        self.seed = seed
        self.at = at
        self.areaScale = areaScale
    }
}

/// Android `BalloonBurstCycle`: count accepted releases, not contacts or frames. Reset only after an actual burst.
final class BalloonBurstCycle {
    private let seed: Int64
    var `throws` = 0
    var extra = 0
    var bursts = 0

    init(_ seed: Int64) {
        self.seed = seed
    }

    func released(_ qualified: Bool) -> Bool {
        `throws` += 1
        if `throws` >= 10 && extra == 0 {
            var random = KotlinRandom(seed: seed ^ (Int64(bursts) &* 7919))
            extra = random.nextInt(from: 1, until: 4)
        }
        return `throws` > 10 + extra && qualified
    }

    func burst() {
        `throws` = 0
        extra = 0
        bursts += 1
    }
}

/// Android `PaintBalloon`: balloon colours, splash size and the paint coverage of a hit player.
enum PaintBalloon {
    static let colors: [Int] = [0xffffea00, 0xffe91e63, 0xffff5ba6, 0xffff5b67, 0xff48d597, 0xff369bff, 0xffffffff, 0xffffc83d,
                                0xfffff4dc].map { (value: Int64) -> Int in Int(Int32(truncatingIfNeeded: value)) }

    static func next(_ seed: Int64, _ point: Int, _ previous: Int) -> Int {
        let choices = colors.filter { $0 != previous }
        var random = KotlinRandom(seed: seed ^ (Int64(point) &* 7919))
        return choices[random.nextIndex(choices.count)]
    }

    static func splashArea(_ speed: Double) -> Double {
        return 1.0 + 0.25 * Kotlin.clamp((speed - 3.0) / 19.0, 0.0, 1.0)
    }

    static func coverage(_ hits: Int, _ rules: RuleSet) -> Double {
        return Kotlin.clamp(Double(hits) / (rules == .spud ? 4 : 6), 0.0, 1.0)
    }

    /// All hits contribute equally after saturation, including repeated colours (Kotlin's map keeps first-hit order;
    /// `orderedShares` keeps that order, `shares` is the same values as a dictionary).
    static func orderedShares(_ hits: [Int], _ rules: RuleSet) -> [(color: Int, share: Double)] {
        if hits.isEmpty { return [] }
        let covered = coverage(hits.count, rules)
        var order: [Int] = []
        var counts: [Int: Int] = [:]
        for h in hits {
            if counts[h] == nil { order.append(h) }
            counts[h, default: 0] += 1
        }
        return order.map { (color: $0, share: Double(counts[$0] ?? 0) * covered / Double(hits.count)) }
    }

    static func shares(_ hits: [Int], _ rules: RuleSet) -> [Int: Double] {
        var map: [Int: Double] = [:]
        for entry in orderedShares(hits, rules) { map[entry.color] = entry.share }
        return map
    }
}
