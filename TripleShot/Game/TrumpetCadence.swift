import Foundation

// Port of game/TrumpetCadence.kt (Android 6c38131), statement by statement.
// Kotlin Long subtraction never traps, so the time difference uses wrapping `&-`.

/** One count for offense changes, made distance shots and dunks; never three separate counters. */
final class TrumpetCadence {
    enum Event: String, KotlinEnum { case OFFENSE, DISTANCE_BASKET, DUNK }

    private let random: KotlinRandom
    private(set) var count = 0
    private(set) var total = 0
    private(set) var played = 0
    private(set) var target = 0
    private var lastPlayed: Int64 = -60_000

    init(random: KotlinRandom = KotlinRandom.Default) {
        self.random = random
        // Kotlin property order: count, total, played, then target = next(), then lastPlayed.
        target = next()
    }

    private func next() -> Int { random.nextInt(7, 13) }

    func event(event: Event, liveMillis: Int64) -> Bool {
        total += 1; count += 1
        return played < 5 && count >= target && liveMillis &- lastPlayed >= 18_000
    }

    func acknowledge(liveMillis: Int64) { played += 1; count = 0; lastPlayed = liveMillis; target = next() }

    func reset() { count = 0; total = 0; played = 0; lastPlayed = -60_000; target = next() }

    func snapshot() -> [Int64] { [count.toLong(), total.toLong(), played.toLong(), target.toLong(), lastPlayed] }

    func restore(s: [Int64]?) {
        guard let s = s, s.count == 5 else { return }
        count = s[0].toInt(); total = s[1].toInt(); played = s[2].toInt(); target = s[3].toInt(); lastPlayed = s[4]
    }
}
