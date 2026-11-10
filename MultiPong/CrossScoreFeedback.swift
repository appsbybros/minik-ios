import UIKit

/// Android cross/CrossScoreFeedback.kt (MinikCrossPong 7254ab2; d376d64, 80fc74e). Point feedback does not depend on the score
/// change: a forgiven fault at zero still receives a steady highlight. The losing box gets a pink outline, an awarded point a green
/// one: fully opaque for 2.15 s, then fading out until 2.75 s (Android d376d64 replaced the 220 ms blinking with this steady
/// highlight; 80fc74e extended it from 1.8 / 2.4 s). Then the original outline returns. The same outcome delivered again (a
/// repeated snapshot) does not restart it.
final class CrossScoreFeedback {
    /// Android `HOLD` and `DURATION`, in milliseconds.
    static let hold = 2150
    static let duration = 2750
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
    /// Android `now - since`, in whole milliseconds.
    private func elapsed(_ now: TimeInterval) -> Int { Int(((now - since) * 1000).rounded()) }
    /// The highlight of a seat at this moment, or nil when its box keeps its usual outline.
    func change(_ seat: Int, now: TimeInterval) -> Change? {
        let age = elapsed(now)
        guard age >= 0, age < CrossScoreFeedback.duration else { return nil }
        return changes[seat]
    }
    /// Android `color`'s alpha: 255 until `hold`, then (duration − age) × 255 / (duration − hold), in whole numbers.
    func alpha(now: TimeInterval) -> Int {
        let age = elapsed(now)
        if age < CrossScoreFeedback.hold { return 255 }
        return (CrossScoreFeedback.duration - age) * 255 / (CrossScoreFeedback.duration - CrossScoreFeedback.hold)
    }
    func color(_ seat: Int, now: TimeInterval) -> UIColor? {
        guard let kind = change(seat, now: now) else { return nil }
        let base = kind == .gain ? CrossScoreFeedback.gain : CrossScoreFeedback.loss
        return base.withAlphaComponent(CGFloat(alpha(now: now)) / 255)
    }
    /// Android Color.luminance: relative luminance of an sRGB colour given as 0–255 components.
    static func luminance(_ c: (Double, Double, Double)) -> Double {
        func linear(_ v: Double) -> Double { let x = v / 255; return x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(c.0) + 0.7152 * linear(c.1) + 0.0722 * linear(c.2)
    }
}
