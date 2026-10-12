import Foundation

/// Port of Android world/StableLabels.kt (`LabelBox` uses Float like Android, so the placement
/// costs and ties resolve identically).
struct LabelBox: Equatable {
    let x: Float
    let y: Float
    let w: Float
    let h: Float

    init(_ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }

    var right: Float { return x + w }
    var bottom: Float { return y + h }
    var cx: Float { return x + w / 2 }
    var cy: Float { return y + h / 2 }

    func overlaps(_ b: LabelBox) -> Bool {
        return x < b.right && right > b.x && y < b.bottom && bottom > b.y
    }
}

/// Name tags keep their previous slot until an actual obstruction demands a change.
final class StableLabels {
    private var offsets: [String: (Float, Float)] = [:]

    func clear() { offsets.removeAll() }

    func place(_ id: String, _ x: Float, _ y: Float, _ w: Float, _ h: Float, _ bounds: LabelBox,
               _ obstacles: [LabelBox], _ used: [LabelBox], _ unit: Float) -> LabelBox {
        func box(_ dx: Float, _ dy: Float) -> LabelBox {
            let bx = min(max(x + dx - w / 2, bounds.x), max(bounds.x, bounds.right - w))
            let by = min(max(y + dy, bounds.y), max(bounds.y, bounds.bottom - h))
            return LabelBox(bx, by, w, h)
        }
        func blocked(_ b: LabelBox) -> Bool {
            return obstacles.contains { b.overlaps($0) } || used.contains { b.overlaps($0) }
        }
        let old = offsets[id]
        if let old = old {
            let b = box(old.0, old.1)
            if !blocked(b) { return b }
        }
        var best = box(0, 0)
        var score = Float.greatestFiniteMagnitude
        var chosen: (Float, Float) = (0, 0)
        func consider(_ dx: Float, _ dy: Float) {
            let b = box(dx, dy)
            let overlap = Float(obstacles.filter { b.overlaps($0) }.count) * 1000000 + Float(used.filter { b.overlaps($0) }.count) * 3000000
            var movement: Float = 0
            if let old = old {
                let mx = dx - old.0
                let my = dy - old.1
                movement = (mx * mx + my * my) * 0.35
            }
            let ex = b.cx - x
            let ey = b.y - y
            let cost = overlap + ex * ex + ey * ey + movement
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
}
