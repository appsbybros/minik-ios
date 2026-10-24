import Foundation

/// Port of Android core/GroundBalloons.kt: where the four private answer balloons land.
/// Nearby balloons land 45-140% of the ring away (team wall battles keep them in the middle strip, away from the X-edge walls) and keep a minimum 3.2 separation; all-over spreads use 22% of the smaller arena
/// side. Colour and answer correctness never enter placement. The random-number order is
/// Android's exactly (one angle per attempt, even when it is not used), so shared rooms deal
/// identical layouts on both platforms.
enum GroundBalloons {
    static func place(_ width: Double, _ depth: Double, _ origin: V, _ nearby: Bool, _ ring: Double, _ r: KotlinRandom, _ wallMode: Bool = false, _ sideWalls: Bool = false) -> [V] {
        let margin = min(min(width, depth) * 0.4, ring * 1.3 + 0.8)
        // Team paint walls stand on the X edges. The old Y-only exclusion was
        // for the single practice wall and allowed answers behind the near team wall.
        let wallInset = wallMode && sideWalls ? min(width * 0.30, 10.5) : 0.7
        let centerInset = max(margin, wallInset)
        var spots: [V] = []
        let center = V(min(max(origin.x, centerInset), width - centerInset), min(max(origin.y, margin), depth - margin))
        let gap = nearby ? min(3.2, ring) : min(width, depth) * 0.22
        // Restart a partial packing if its first three random points leave no room
        // for a fourth. Restricting the wall strip must never produce fewer answers.
        for _ in 0..<(sideWalls ? 60 : 1) {
            spots.removeAll()
            for _ in 0..<(sideWalls ? 300 : 3000) where spots.count < 4 {
                let angle = r.nextDouble() * 2 * Double.pi
                let at: V
                if nearby {
                    at = center + V(cos(angle), sin(angle)) * (ring * (0.45 + r.nextDouble() * 0.95))
                } else {
                    at = V(1 + r.nextDouble() * (width - 2), 1 + r.nextDouble() * (depth - 2))
                }
                if at.x >= wallInset && at.x <= width - wallInset && (!wallMode || sideWalls || (at.y >= 3.05 && at.y <= depth - 3.05)) &&
                    at.y >= 0.8 && at.y <= depth - 0.7 && spots.allSatisfy({ ($0 - at).length() >= gap }) {
                    spots.append(at)
                }
            }
            if spots.count == 4 { return spots.kotlinShuffled(r) }
        }
        // Android `error(...)` cannot happen for valid arenas; a corrupt size fills the rest
        // beside the centre instead of terminating.
        while spots.count < 4 {
            spots.append(center + V(Double(spots.count) - 1.5, 0))
        }
        return spots.kotlinShuffled(r)
    }
}
