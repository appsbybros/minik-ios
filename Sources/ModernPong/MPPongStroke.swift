import Foundation

/// Kotlin `sign(Double)`: -1, 0 or 1 (NaN stays NaN).
func mpSign(_ value: Double) -> Double { value > 0 ? 1 : value < 0 ? -1 : value }

/// Android `PongStroke` (22f756e): a Pro spin gesture. Gesture coordinates are display-normalized, never derived from
/// the moving ball. Wire (team inputs, saved tables): `{aim, power, top, side}`.
struct MPPongStroke: Codable, Equatable {
    var aim: Double, power: Double, top = 0.0, side = 0.0
    init(aim: Double, power: Double, top: Double = 0, side: Double = 0) { self.aim = aim; self.power = power; self.top = top; self.side = side }
    var valid: Bool {
        [aim, power, top, side].allSatisfy(\.isFinite) && (-1...1).contains(aim) && (0...1).contains(power) &&
            (0...1).contains(top) && (-1...1).contains(side)
    }
    var reflected: Self { .init(aim: -aim, power: power, top: top, side: -side) }

    /// Android `PongStroke.read(points, durationMs)`: a sideways reversal is side spin, a bent (arched) path is top
    /// spin; otherwise a flat stroke. `nil` for a too-short or malformed gesture.
    static func read(_ points: [MPPoint], durationMs: Int64) -> MPPongStroke? {
        if points.count < 2 { return nil }
        let p = points.filter { $0.x.isFinite && $0.y.isFinite }; if p.count != points.count { return nil }
        let pairs = zip(p, p.dropFirst())
        let length = pairs.reduce(0.0) { $0 + $1.0.distance($1.1) }
        if length < 0.035 { return nil }
        let first = p[0], last = p[p.count - 1], dx = last.x - first.x, dy = last.y - first.y
        let speed = length / (Double(min(max(durationMs, 40), 2000)) / 1000.0)
        let power = (1 - exp(-speed / 1.15)).mpClamp(0, 1)
        let left = pairs.reduce(0.0) { $0 + max(0, $1.0.x - $1.1.x) }
        let right = pairs.reduce(0.0) { $0 + max(0, $1.1.x - $1.0.x) }
        let reversal = min(left, right) > 0.045
        let tail = p[p.count * 2 / 3], finalX = last.x - tail.x
        let heading = reversal && abs(finalX) > 0.015 ? mpSign(finalX) : (dx / max(abs(dy), 0.12)).mpClamp(-1, 1)
        let chord = max(first.distance(last), 0.001)
        let bend = p.map { abs(dx * ($0.y - first.y) - dy * ($0.x - first.x)) / chord }.max() ?? 0
        let arc = !reversal && bend > 0.018 && length / chord > 1.08
        let top = arc ? (0.35 + power * 0.65) * (bend / 0.06).mpClamp(0.5, 1) : 0
        let side = reversal ? -mpSign(finalX) * (0.35 + 0.65 * power) : 0
        return MPPongStroke(aim: heading, power: power, top: top, side: side)
    }
}

/// Android `PongSpinShot`: launch once; the flight integrates gravity (plus top spin) and the lateral Magnus
/// acceleration. No in-flight target correction, no teleport at a bounce.
enum MPPongSpinShot {
    static func solve(_ point: MPPoint, height: Double, stroke: MPPongStroke, tuning t: MPTuning, side player: MPSide) -> MPShot {
        precondition(stroke.valid, "Invalid spin stroke") // Android `require(stroke.valid())`
        let target = MPPoint((0.5 + stroke.aim * 0.29).mpClamp(0.12, 0.88), player == .child ? 0.24 : 0.76)
        let gravity = t.gravity + stroke.top * 2.2
        let pace = 0.85 + stroke.power * 0.45
        var time = abs(target.y - point.y) / pace
        let fraction = ((0.5 - point.y) / (target.y - point.y)).mpClamp(0.05, 0.95)
        let clearance = max(0, t.netHeight + 0.045 - height * (1 - fraction))
        time = max(time, sqrt(2 * clearance / (gravity * fraction * (1 - fraction))))
        time = max(time, 0.38)
        let acceleration = stroke.side * 0.85
        let sideways = acceleration * (time / 1.4 - (1 - exp(-1.4 * time)) / (1.4 * 1.4))
        return MPShot(velocity: .init((target.x - point.x - sideways) / time, (target.y - point.y) / time), arc: (0.5 * gravity * time * time - height) / time)
    }
}
