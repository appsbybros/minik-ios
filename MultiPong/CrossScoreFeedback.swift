import UIKit

/// Android cross/CrossScoreFeedback.kt (MinikCrossPong 7254ab2). Point feedback does not depend on the score change: a forgiven
/// fault at zero still flashes. The losing box flashes pink, an awarded point green, for 1.8 seconds (220 ms on, 220 ms off);
/// then the original outline returns. The same outcome delivered again (a repeated snapshot) does not restart it.
final class CrossScoreFeedback {
    static let duration: TimeInterval = 1.8
    static let gain = UIColor(red: 0x48 / 255.0, green: 0xd5 / 255.0, blue: 0x97 / 255.0, alpha: 1)
    static let loss = UIColor(red: 0xe9 / 255.0, green: 0x1e / 255.0, blue: 0x63 / 255.0, alpha: 1)
    enum Change: Equatable { case gain, loss }

    private var last: CrossRallyOutcome?
    private var since: TimeInterval = 0
    private var changes: [Int: Change] = [:]

    func clear() { last = nil; changes = [:] }
    func record(_ outcome: CrossRallyOutcome, now: TimeInterval) {
        if outcome == last { return }
        last = outcome; since = now
        var next: [Int: Change] = [:]
        for (seat, delta) in outcome.deltas.enumerated() {
            if delta > 0 { next[seat] = .gain } else if delta < 0 { next[seat] = .loss }
        }
        if let loser = outcome.loser, loser >= 0, loser < outcome.deltas.count { next[loser] = .loss }
        changes = next
    }
    /// The flash for a seat at this moment, or nil when its box keeps its usual outline.
    func change(_ seat: Int, now: TimeInterval) -> Change? {
        let age = now - since
        guard age >= 0, age < CrossScoreFeedback.duration, Int(age * 1000) / 220 % 2 == 0 else { return nil }
        return changes[seat]
    }
    func color(_ seat: Int, now: TimeInterval) -> UIColor? {
        change(seat, now: now).map { $0 == .gain ? CrossScoreFeedback.gain : CrossScoreFeedback.loss }
    }
    /// Android Color.luminance: relative luminance of an sRGB colour given as 0–255 components.
    static func luminance(_ c: (Double, Double, Double)) -> Double {
        func linear(_ v: Double) -> Double { let x = v / 255; return x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(c.0) + 0.7152 * linear(c.1) + 0.0722 * linear(c.2)
    }
}
