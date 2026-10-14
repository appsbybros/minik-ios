import Foundation

// Android cross/CrossShots.kt (MinikCrossPong 5c1aa4d).

/// A two-bounce serve: `launch` from `start`/`height` lands at `first` in the server's own serve zone, where the ball takes
/// `rebound`. `second` is the planned receiving bounce (nil for a driven Pro serve).
struct CrossServe {
    var server: Int
    var start: MPPoint
    var height: Double
    var first: MPPoint
    var launch: CrossLaunch
    var rebound: CrossLaunch
    var second: MPPoint? = nil
}

enum CrossShots {
    static let clearance = 0.03
    static let minTime = 0.45
    static let maxTime = 2.4
    /// Classic pace → world units/s for targeted shots (Standard/Beginner base 0.40 → 0.98; 5c1aa4d raised it from 2.2).
    static let paceScale = 2.45
    /// Classic table length (1.66 W) → world units for the driven impulse.
    static let drivenScale = 1.66
    static let maxAngle = 70 * Double.pi / 180
    static let contactHeight = 0.055
    /// Lift lost by a quality-0 contact (as the classic driven shot).
    static let qualityLift = 0.16
    private static let tapU = 0.30
    private static let tapNear = 0.62
    private static let tapDepth = 0.78
    private static let tapFar = 0.92
    private static let swipeU = 0.34
    private static let swipeDepth = 0.80
    static func basePace(_ t: MPTuning) -> Double { t.ballBaseSpeed * paceScale }
    /// Beginner passes power 0; Standard adds +35 % x gesture power (0..1).
    static func pace(_ t: MPTuning, power: Double = 0) -> Double { basePace(t) * (1 + 0.35 * power.mpClamp(0, 1)) }
    /// Pace time, raised to the minimum that clears every net/post the straight path meets by `clearance`: at fraction f the
    /// height is h0(1-f) + g t^2 f(1-f)/2. Kept within [minTime, maxTime].
    static func flightTime(_ g: CrossGeometry, _ t: MPTuning, from: MPPoint, height: Double, target: MPPoint, pace: Double) -> Double {
        var time = (target - from).length / max(pace, 0.05)
        let need = t.netHeight + clearance
        for span in g.netSpans(from, target) {
            for f in [span.start, span.end] {
                let lack = need - height * (1 - f)
                if lack <= 0 { continue }
                let k = f * (1 - f)
                time = k <= 1e-9 ? maxTime : max(time, sqrt(2 * lack / (t.gravity * k)))
            }
        }
        return time.mpClamp(minTime, maxTime)
    }
    /// Assisted shot (Beginner/Standard humans, house players, serves) whose first bounce is exactly `target`. Quality loss
    /// lowers the lift, so a poor contact can net; callers move `target` for aim noise, so a poor aim can go out. Nothing
    /// bends the flight back onto the table.
    static func targeted(_ g: CrossGeometry, _ t: MPTuning, from: MPPoint, height: Double, target: MPPoint, pace: Double, quality: Double = 1) -> CrossLaunch {
        let time = flightTime(g, t, from: from, height: height, target: target, pace: pace)
        let loss = (1 - quality.mpClamp(0, 1)) * qualityLift
        return CrossLaunch(velocity: (target - from) * (1 / time), lift: (0.5 * t.gravity * time * time - height) / time - loss)
    }
    /// Pro impulse, ported from the classic driven shot. `swipe` is the stroke velocity in the striker's view frame (+x right,
    /// +y toward the viewer); forward speed sets power and pace, the lateral/forward angle sets the direction from the
    /// striker's inward axis. No target: gravity, nets and the table decide (net/out allowed).
    static func driven(_ g: CrossGeometry, _ t: MPTuning, striker: Int, swipe: MPPoint, height: Double, incoming: MPPoint, quality: Double = 1) -> CrossLaunch {
        let forward = max(0, -swipe.y)
        let power = (forward / t.maximumSwipeSpeed).mpClamp(0, 3)
        let pace = drivenScale * (0.18 + power * 1.28 + min(incoming.length * t.incomingVelocityInfluence, 0.06))
        let angle = (1.25 * atan2(swipe.x, forward)).mpClamp(-maxAngle, maxAngle)
        let surge: Double = 1.55 * (1 - exp(-power * 4))
        let loss: Double = (1 - quality.mpClamp(0, 1)) * qualityLift
        let lift: Double = 0.25 + surge - 0.20 * power - height * 0.45 - loss
        return CrossLaunch(velocity: g.fromView(striker, MPPoint(sin(angle), -cos(angle)) * pace), lift: lift)
    }
    /// Two-bounce serve: own serve zone at `first`, then the rebound toward `second` in a target territory.
    static func serve(_ g: CrossGeometry, _ t: MPTuning, server: Int, start: MPPoint, first: MPPoint, second: MPPoint, pace: Double,
                      height: Double = CrossShots.contactHeight) -> CrossServe {
        CrossServe(server: g.wrap(server), start: start, height: height, first: first,
                   launch: targeted(g, t, from: start, height: height, target: first, pace: pace),
                   rebound: targeted(g, t, from: first, height: 0, target: second, pace: pace), second: second)
    }
    /// Beginner/Standard tap serve: a tap on the own arm picks the first bounce, kept well inside the serve zone (elsewhere a
    /// central first bounce). `second` comes from the aim map.
    static func tapServe(_ g: CrossGeometry, _ t: MPTuning, server: Int, start: MPPoint, tap: MPPoint?, second: MPPoint, pace: Double) -> CrossServe {
        var local: CrossLocal?
        if let tap, g.inArm(server, tap) { local = g.toLocal(server, tap) }
        let first = g.fromLocal(server, (local?.u ?? 0).mpClamp(-tapU, tapU), (local?.v ?? tapDepth).mpClamp(tapNear, tapFar))
        return serve(g, t, server: server, start: start, first: first, second: second, pace: pace)
    }
    /// Pro swipe serve, ported from the classic swipe serve: nil for a weak or backward swipe (a bad serve). The own bounce's
    /// lateral is assisted by serveAssistance; the rebound is the same swipe's driven impulse.
    static func swipeServe(_ g: CrossGeometry, _ t: MPTuning, server: Int, start: MPPoint, swipe: MPPoint) -> CrossServe? {
        let speed = swipe.length
        if speed < 0.04 || swipe.y >= -0.04 { return nil }
        let raw = g.toLocal(server, start).u + (swipe.x * 0.28).mpClamp(-0.55, 0.55) * 0.35
        let u = raw * (1 - t.serveAssistance) + raw.mpClamp(-swipeU, swipeU) * t.serveAssistance
        let first = g.fromLocal(server, u, swipeDepth)
        let pace = paceScale * min(t.ballBaseSpeed + speed * t.swipeVelocityScale * 0.35, t.maximumBallSpeed)
        return CrossServe(server: g.wrap(server), start: start, height: contactHeight, first: first,
                          launch: targeted(g, t, from: start, height: contactHeight, target: first, pace: pace),
                          rebound: driven(g, t, striker: server, swipe: swipe, height: 0, incoming: MPPoint(0, 0)))
    }
}

/// Chosen opponent and landing target; `wide` = beyond the end of the target arm (a genuine out).
struct CrossAim: Equatable {
    var opponent: Int
    var point: MPPoint
    var wide = false
}

/// Beginner/Standard aiming: the lateral drag since touch-down (dp, viewer frame, + = right) picks the opponent by bands and
/// the target inside that opponent's arm. Within a band the opponent never changes.
struct CrossAimMap {
    static let dpPerUnit = 40.0
    static let maxGesture = 3.0
    static let bandFour = 0.8
    static let bandThree = 0.25
    static let farGesture = 2.6
    /// Two players: the drag (gesture units) that reaches the safe edge of the opponent's half.
    static let farTwo = 2.2
    static let sideNear = 0.62
    /// In-band targets keep >= 0.12 from the target arm's side edges.
    static let edgeU = CrossGeometry.half - 0.12
    /// Beyond the Beginner automatic reach (0.17) of a resting paddle on the arm's centre line.
    static let varyU = 0.25

    let geometry: CrossGeometry
    init(_ geometry: CrossGeometry) { self.geometry = geometry }
    var players: Int { geometry.players }
    /// Neutral band half-width in gesture units: ~32 dp (4 players) / 10 dp (3 players) of deliberate drag.
    var bandStart: Double { players == 4 ? CrossAimMap.bandFour : CrossAimMap.bandThree }
    /// Opponents ordered left → right as seen by `striker`.
    func opponents(_ striker: Int) -> [Int] {
        let offsets: [Int]
        switch players {
        case 4: offsets = [3, 2, 1]
        case 3: offsets = [2, 1]
        default: offsets = [1]
        }
        return offsets.map { geometry.wrap(striker + $0) }
    }
    func gesture(_ dragDp: Double) -> Double { (dragDp / CrossAimMap.dpPerUnit).mpClamp(-CrossAimMap.maxGesture, CrossAimMap.maxGesture) }
    /// `sender` = who sent the ball (3 players: the neutral band returns it); for a serve pass `serveLateral`, the tap's lateral
    /// offset in the server's frame (its side picks the 3-player neutral opponent). `variation` (-1..1) moves an assisted
    /// target sideways inside the chosen arm by up to `varyU`, so identical no-gesture returns never land on an idle
    /// receiver's resting paddle again and again.
    func aim(_ striker: Int, dragDp: Double, power: Double = 0, sender: Int? = nil, serveLateral: Double? = nil, variation: Double = 0) -> CrossAim {
        let edge = CrossAimMap.edgeU, far = CrossAimMap.farGesture
        let vary = variation.mpClamp(-1, 1) * CrossAimMap.varyU
        let g = gesture(dragDp)
        let order = opponents(striker)
        let magnitude = abs(g)
        if players == 2 {
            // One opponent straight ahead: the drag places the ball across their half; a very wide drag goes out.
            let depth = CrossGeometry.reach - 0.38 + 0.15 * power.mpClamp(0, 1)
            let farTwo = CrossAimMap.farTwo
            let sign: Double = g > 0 ? 1 : (g < 0 ? -1 : 0)
            let lateral = magnitude <= farTwo ? g / farTwo * edge + vary * (1 - magnitude / farTwo) : sign * (edge + (magnitude - farTwo) * 0.5)
            return CrossAim(opponent: order[0], point: geometry.fromView(striker, MPPoint(lateral.mpClamp(-1.5, 1.5), -depth)), wide: abs(lateral) > CrossGeometry.half)
        }
        if magnitude < bandStart {
            let depth = CrossGeometry.reach - 0.38 + 0.15 * power.mpClamp(0, 1)
            if players == 4 {
                let lateral = (g / bandStart * 0.30 + vary).mpClamp(-edge, edge)
                return CrossAim(opponent: order[1], point: geometry.fromView(striker, MPPoint(lateral, -depth)))
            }
            let back: Int
            if let sender, geometry.wrap(sender) != geometry.wrap(striker) { back = geometry.wrap(sender) }
            else { back = (serveLateral ?? 0) < 0 ? order[0] : order[order.count - 1] }
            return CrossAim(opponent: back, point: geometry.fromLocal(back, vary.mpClamp(-edge, edge), depth))
        }
        let side = g < 0 ? order[0] : order[order.count - 1]
        let end = CrossGeometry.reach - 0.12
        let depth = magnitude <= far ? CrossAimMap.sideNear + (magnitude - bandStart) / (far - bandStart) * (end - CrossAimMap.sideNear)
            : end + (magnitude - far) * 0.9
        return CrossAim(opponent: side, point: geometry.fromLocal(side, (vary * 0.8).mpClamp(-edge, edge), depth), wide: depth > CrossGeometry.reach)
    }
}
