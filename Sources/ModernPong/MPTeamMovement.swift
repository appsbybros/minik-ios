import Foundation

/// Android `PongTeamMovement` (79e1148, 29f5dc7): floor movement behind the baseline, shared by local and authoritative
/// team play. Floor distances scale the depth axis so a body is a circle of `bodyWidth`.
enum MPTeamMovement {
    static let bodyWidth = 0.35
    static let bodyDepth = 0.13
    static let depthScale = bodyWidth / bodyDepth
    static let retreat = 0.16
    static func waitingY(_ team: Int) -> Double { team == 0 ? 0.88 + retreat : 0.12 - retreat }
    static func distance(_ a: MPPoint, _ b: MPPoint) -> Double { hypot(a.x - b.x, (a.y - b.y) * depthScale) }
    /// A forward sideline receiver returns around the corner, never diagonally through the tabletop. This only plans
    /// bot routes; it does not move humans.
    static func aroundCorner(_ at: MPPoint, _ goal: MPPoint, _ team: Int) -> MPPoint {
        let base = team == 0 ? 0.88 : 0.12
        let forward = team == 0 ? at.y < base - 0.001 : at.y > base + 0.001
        let crosses = (0.02...0.98).contains(goal.x) || (at.x < 0.5) != (goal.x < 0.5)
        return forward && crosses ? MPPoint(at.x, base) : goal
    }
    static func step(_ at: MPPoint, _ goal: MPPoint, _ limit: Double) -> MPPoint {
        let x = goal.x - at.x, y = (goal.y - at.y) * depthScale, length = hypot(x, y)
        let factor = length <= limit || length < 1e-12 ? 1.0 : limit / length
        return MPPoint(x * factor, y * factor / depthScale)
    }
    /// Swept circle contact in floor space. Keep separating/tangential motion; cancel only movement into the other
    /// body. Sliding stays inside the floor corridor behind the baseline, never forward through the table.
    static func separate(_ a: MPPoint, _ b: MPPoint, _ da: MPPoint, _ db: MPPoint, wideA: Bool = false, wideB: Bool = false) -> (MPPoint, MPPoint) {
        let rx = b.x - a.x, ry = (b.y - a.y) * depthScale
        let ax = da.x, ay = da.y * depthScale, bx = db.x, by = db.y * depthScale
        let dx = bx - ax, dy = by - ay, aa = dx * dx + dy * dy
        let bb = 2 * (rx * dx + ry * dy), cc = rx * rx + ry * ry - bodyWidth * bodyWidth
        let disc = bb * bb - 4 * aa * cc
        if aa < 1e-18 || bb >= 0 || disc < 0 { return (da, db) }
        let t = max((-bb - sqrt(disc)) / (2 * aa), 0)
        if t > 1 { return (da, db) }
        let nx0 = rx + t * dx, ny0 = ry + t * dy, len = max(hypot(nx0, ny0), 1e-9)
        let nx = nx0 / len, ny = ny0 / len, rest = 1 - t
        func slide(_ at: MPPoint, _ vx: Double, _ vy: Double, _ nx: Double, _ ny: Double, _ wide: Bool) -> MPPoint {
            let far = at.y < 0.5
            let forward = wide && (far ? at.y > 0.120001 : at.y < 0.879999)
            let low = far ? waitingY(1) : forward ? 0.52 : 0.88
            let high = far ? (forward ? 0.48 : 0.12) : waitingY(0)
            let left = !wide ? 0.06 : forward && at.x > 0.5 ? 0.98 : -0.14
            let right = !wide ? 0.94 : forward && at.x < 0.5 ? 0.02 : 1.14
            // Standing still is always allowed; collision response never teleports anyone.
            let minX = min(0, left - at.x), maxX = max(0, right - at.x)
            let minY = min(0, (low - at.y) * depthScale), maxY = max(0, (high - at.y) * depthScale)
            let x = kotlinCoerce(vx, minX, maxX), y = kotlinCoerce(vy, minY, maxY)
            if x * nx + y * ny <= 0 { return MPPoint(x, y / depthScale) }
            // Closest allowed motion on the tangent, intersected with the floor boundaries.
            let tx = -ny, ty = nx
            var from = -Double.infinity, to = Double.infinity
            func bound(_ v: Double, _ lo: Double, _ hi: Double) {
                if abs(v) > 1e-12 { let a = lo / v, b = hi / v; from = max(from, min(a, b)); to = min(to, max(a, b)) }
            }
            bound(tx, minX, maxX); bound(ty, minY, maxY)
            let along = kotlinCoerce(vx * tx + vy * ty, from, to)
            return MPPoint(tx * along, ty * along / depthScale)
        }
        let sa = slide(MPPoint(a.x + ax * t, a.y + ay * t / depthScale), ax * rest, ay * rest, nx, ny, wideA)
        let sb = slide(MPPoint(b.x + bx * t, b.y + by * t / depthScale), bx * rest, by * rest, -nx, -ny, wideB)
        return (MPPoint(ax * t + sa.x, ay * t / depthScale + sa.y), MPPoint(bx * t + sb.x, by * t / depthScale + sb.y))
    }
    /// Kotlin `Double.coerceIn(lo, hi)`: below `lo` gives `lo`, above `hi` gives `hi`, otherwise (also NaN) the value.
    /// Kotlin throws for an empty range; the callers above never pass one except the tangent interval, where Kotlin
    /// would also throw — that interval always contains 0 because standing still is allowed.
    static func kotlinCoerce(_ v: Double, _ lo: Double, _ hi: Double) -> Double { v < lo ? lo : v > hi ? hi : v }
}
