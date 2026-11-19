import Foundation

/// Android `core/TossGesture.kt`: physical dp (points) and gesture time, independent of resolution, locale and frame
/// rate. A short flick stays gentle even when fast; a long slow swipe stays gentle too.
enum TossGesture {
    static func power(_ upDp: Double, _ millis: Int64) -> Double {
        if !upDp.isFinite || upDp < 18 { return 0.0 }
        let velocity = Kotlin.clamp((upDp / Double(max(Int64(60), millis)) * 1000 - 140) / 1600, 0.0, 1.0)
        let travel = Kotlin.clamp((upDp - 18) / 180, 0.0, 1.0)
        return min(velocity, travel)
    }
}
