import Foundation

/// Android `core/CircleFormation.kt`: even gaps, but no permanent roster seats. Conflicts are resolved by the minimum
/// total travel.
enum CircleFormation {
    static let RADIUS = 4.5

    static func spots(_ center: V, _ count: Int, _ angle: Double) -> [V] {
        return (0..<max(count, 0)).map { i in
            let a = angle + 2 * Double.pi * Double(i) / Double(count)
            return center + V(cos(a), sin(a)) * RADIUS
        }
    }

    /// Kotlin `nearest(positions, spots)` (at most 9 players): a bitmask dynamic programme over spot assignments.
    static func nearest(_ positions: [V], _ spots: [V]) -> [V] {
        precondition(positions.count == spots.count && positions.count <= 9)
        let n = positions.count
        if n == 0 { return [] }
        var costs = [Double](repeating: Double.infinity, count: 1 << n)
        costs[0] = 0.0
        var chosen = [Int](repeating: -1, count: costs.count)
        for mask in 0..<costs.count {
            let who = mask.nonzeroBitCount
            if who == n { continue }
            for j in 0..<n where mask & (1 << j) == 0 {
                let next = mask | (1 << j)
                let cost = costs[mask] + (positions[who] - spots[j]).length()
                if cost < costs[next] - 1e-9 {
                    costs[next] = cost
                    chosen[next] = j
                }
            }
        }
        var mask = costs.count - 1
        var result = [V](repeating: spots[0], count: n)
        var i = n - 1
        while i >= 0 {
            let j = chosen[mask]
            result[i] = spots[j]
            mask = mask ^ (1 << j)
            i -= 1
        }
        return result
    }
}
