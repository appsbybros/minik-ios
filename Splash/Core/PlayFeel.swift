import Foundation

/// Port of Android core/PlayFeel.kt: shared balance constants, independent of screen size.
/// Wire enum names stay compatible (EASY is shown as Standard, STANDARD as Hard).
enum PlayFeel {
    /// About ten walking steps.
    static let runAfterDistance = 6.5
    static let runMultiplier = 1.48
    static let acceleration = 14.0
    static let braking = 19.0

    /// Hard throwing: a faster swipe (dp per second) throws harder.
    static func powerFromSwipe(_ dpPerSecond: Double) -> Double {
        return min(max(0.72 + dpPerSecond / 1400.0, 0.72), 1.55)
    }

    /// Standard throwing: the lift that lands the balloon at the tapped distance.
    static func lift(_ distance: Double, _ speed: Double, _ release: Double, _ gravity: Double) -> Double {
        let t = min(max(max(distance - 0.42, 0.25) / speed, 0.06), 12.0)
        return min(max((0.65 - release + 0.5 * gravity * t * t) / t, -3.0), 18.0)
    }

    /// Smooth acceleration and braking; sustained travel in one direction starts a run.
    static func advance(_ a: SplashActor, _ baseSpeed: Double, _ dt: Double) -> V {
        let requested = a.move
        if requested.length() > 0.1 {
            let u = requested.unit()
            let same = u.x * a.travelDirection.x + u.y * a.travelDirection.y > 0.82
            a.travelDistance = same ? a.travelDistance + a.velocity.length() * dt : 0.0
            a.travelDirection = u
        } else {
            a.travelDistance = 0.0
        }
        let running = a.travelDistance >= runAfterDistance ? runMultiplier : 1.0
        var speed = baseSpeed * running
        if let target = a.walkTarget {
            speed = min(speed, sqrt(2 * braking * max((target - a.position).length(), 0.0)))
        }
        let desired = requested * speed
        let delta = desired - a.velocity
        let rate = desired.length() < a.velocity.length() ? braking : acceleration
        a.velocity = delta.length() <= rate * dt ? desired : a.velocity + delta.unit() * (rate * dt)
        let targetBlend = running > 1.0 && requested.length() > 0.1 ? 1.0 : 0.0
        a.runBlend += (targetBlend - a.runBlend) * (1 - exp(-dt * 5))
        return a.velocity * dt
    }
}

/// Android `SplashRank`: colour ranks earned with points (ink is the text colour on the rank).
struct SplashRank: Equatable {
    let threshold: Int
    let en: String
    let he: String
    let color: UInt32
    let ink: UInt32

    init(_ threshold: Int, _ en: String, _ he: String, _ color: UInt32, _ ink: UInt32 = 0xff17283f) {
        self.threshold = threshold
        self.en = en
        self.he = he
        self.color = color
        self.ink = ink
    }
}

enum SplashRanks {
    static let all: [SplashRank] = [
        SplashRank(0, "White", "לבן", 0xfffafafa), SplashRank(100, "Yellow", "צהוב", 0xffffe761),
        SplashRank(250, "Cyan", "טורקיז", 0xff62eced), SplashRank(500, "Light blue", "תכלת", 0xff8dcaff),
        SplashRank(1000, "Orange", "כתום", 0xffffa64f), SplashRank(1800, "Pink", "ורוד", 0xffff75b5),
        SplashRank(3000, "Red", "אדום", 0xffef5350), SplashRank(5000, "Blue", "כחול", 0xff2459c5, 0xffffffff),
        SplashRank(8000, "Brown", "חום", 0xff795548, 0xffffffff), SplashRank(12000, "Silver", "כסף", 0xffd8e0e9),
        SplashRank(18000, "Gold", "זהב", 0xffffcf40)
    ]

    static func at(_ points: Int) -> SplashRank {
        return all.last(where: { points >= $0.threshold }) ?? all[0]
    }

    /// Two points per correct answer and five per hit.
    static func earned(_ a: SplashActor) -> Int {
        return a.answers.filter { $0.correct }.count * 2 + a.hits * 5
    }
}
