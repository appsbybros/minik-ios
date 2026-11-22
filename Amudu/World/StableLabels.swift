import Foundation

/// Android `world/LabelBox` (Float, like Kotlin, so label placement makes the same choices).
struct LabelBox: Equatable {
    let x: Float
    let y: Float
    let w: Float
    let h: Float

    var right: Float { return x + w }
    var bottom: Float { return y + h }
    var cx: Float { return x + w / 2 }
    var cy: Float { return y + h / 2 }

    func overlaps(_ b: LabelBox) -> Bool {
        return x < b.right && right > b.x && y < b.bottom && bottom > b.y
    }
}

/// Android `world/StableLabels`: keep the previous slot until an actual obstruction demands a change.
final class StableLabels {
    private var offsets: [String: (Float, Float)] = [:]

    func clear() {
        offsets.removeAll()
    }

    func place(_ id: String, _ x: Float, _ y: Float, _ w: Float, _ h: Float, _ bounds: LabelBox, _ obstacles: [LabelBox],
               _ used: [LabelBox], _ unit: Float) -> LabelBox {
        func coerce(_ value: Float, _ low: Float, _ high: Float) -> Float {
            if value < low { return low }
            if value > high { return high }
            return value
        }
        func box(_ dx: Float, _ dy: Float) -> LabelBox {
            return LabelBox(x: coerce(x + dx - w / 2, bounds.x, max(bounds.x, bounds.right - w)),
                            y: coerce(y + dy, bounds.y, max(bounds.y, bounds.bottom - h)), w: w, h: h)
        }
        func blocked(_ b: LabelBox) -> Bool {
            return obstacles.contains { b.overlaps($0) } || used.contains { b.overlaps($0) }
        }
        let old = offsets[id]
        if let old {
            let b = box(old.0, old.1)
            if !blocked(b) { return b }
        }
        var best = box(0, 0)
        var score = Float.greatestFiniteMagnitude
        var chosen: (Float, Float) = (0, 0)
        func consider(_ dx: Float, _ dy: Float) {
            let b = box(dx, dy)
            let overlap = Float(obstacles.filter { b.overlaps($0) }.count) * 1_000_000 + Float(used.filter { b.overlaps($0) }.count) * 3_000_000
            var movement: Float = 0
            if let old {
                let mx = dx - old.0
                let my = dy - old.1
                movement = (mx * mx + my * my) * 0.35
            }
            let ox = b.cx - x
            let oy = b.y - y
            let cost = overlap + ox * ox + oy * oy + movement
            if cost < score {
                score = cost
                best = b
                chosen = (dx, dy)
            }
        }
        consider(0, 0)
        for ring in 1...8 {
            for i in 0..<16 {
                let a = Double(i) * Double.pi / 8
                consider(Float(cos(a) * Double(unit) * Double(ring)), Float(sin(a) * Double(unit) * Double(ring)))
            }
        }
        offsets[id] = chosen
        return best
    }

    // MARK: Next to the owner (iOS, bug report 2026-11-22, 4.3)

    private var sides: [String: Int] = [:]

    /// A name tag beside its own player: below the feet, above the head, then to the right or the left of the body,
    /// each with small nudges. A slot over another player or another tag is used only when every slot is blocked, the
    /// tag keeps its side while it stays free (no jumping around), and the tag is kept inside `bounds`, so it stays
    /// visible at the screen's edge when its player is off screen. `body` is the player's drawn body; `others` are
    /// the other players' bodies (and obstacles).
    func placeNear(_ id: String, body: LabelBox, _ w: Float, _ h: Float, _ bounds: LabelBox, _ others: [LabelBox],
                   _ used: [LabelBox]) -> LabelBox {
        func coerce(_ value: Float, _ low: Float, _ high: Float) -> Float {
            return min(max(value, low), max(low, high))
        }
        func slot(_ side: Int, _ nx: Float, _ ny: Float) -> LabelBox {
            let x: Float, y: Float
            switch side {
            case 0: x = body.cx - w / 2; y = body.bottom + 3
            case 1: x = body.cx - w / 2; y = body.y - h - 3
            case 2: x = body.right + 4; y = body.cy - h / 2
            default: x = body.x - w - 4; y = body.cy - h / 2
            }
            return LabelBox(x: coerce(x + nx, bounds.x, bounds.right - w), y: coerce(y + ny, bounds.y, bounds.bottom - h), w: w, h: h)
        }
        func overlap(_ b: LabelBox) -> Float {
            return Float(others.filter { b.overlaps($0) }.count) * 1_000_000 + Float(used.filter { b.overlaps($0) }.count) * 3_000_000
        }
        if let side = sides[id] {
            let b = slot(side, 0, 0)
            if overlap(b) == 0 { return b }
        }
        let nudges: [Float] = [0, 8, -8, 16, -16]
        var best = slot(0, 0, 0)
        var bestCost = Float.greatestFiniteMagnitude
        var bestSide = 0
        for side in 0..<4 {
            for nx in nudges {
                for ny in nudges {
                    let b = slot(side, nx, ny)
                    // Prefer the order below, above, right, left; then the smallest nudge; then the old side.
                    let cost = overlap(b) + Float(side) * 400 + nx * nx + ny * ny + (sides[id] == side ? 0 : 50)
                    if cost < bestCost {
                        bestCost = cost
                        best = b
                        bestSide = side
                    }
                }
            }
        }
        sides[id] = bestSide
        return best
    }
}
