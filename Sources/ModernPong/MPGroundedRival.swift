import SpriteKit
import UIKit

/// Android `GroundedRival` (496a709, recovery 3010b3e): the local house player drawn with its complete authored poses,
/// feet travelling around the floor footprint (never across the tabletop). A planned contact never places the torso
/// on the tabletop or hides missing legs, and the drawn racket must really reach the ball (`canReach`, the engine's
/// `botCanReach`). Used by both singles tables in local matches; online opponents and the guide keep their own drawing.
/// View coordinates are points with a top-left origin (Android pixels); world coordinates are table units, y < 0
/// behind the far end line.
final class MPGroundedRival {
    private let poses: MPPoseSprites
    private unowned let engine: MPEngine
    private var id = "minik"
    private var height: CGFloat = 1
    private var project: (MPPoint) -> CGPoint = { _ in .zero }
    private var inverse: (CGPoint) -> MPPoint = { _ in MPPoint(0.5, -0.10) }
    private var ball: (MPPoint, Double) -> CGPoint = { _, _ in .zero }
    /// Android `floorFoot`: where the feet stand, in world coordinates.
    private(set) var floorFoot = MPPoint(0.5, -0.10)
    private var route = [MPPoint(0.5, -0.10)]
    private var elapsed = 0.0, duration = 0.0
    private var lastPlan: MPIntercept?
    private var returning = false
    private var serveStroke = -1
    private let gait = MPGait()
    private struct Pose { var foot: MPPoint; var facing: MPPoseAtlas.Facing; var mirror: Bool; var phase: Int }
    private var pose = Pose(foot: MPPoint(0.5, -0.10), facing: .front, mirror: false, phase: 2)
    private(set) var geometry: MPPoseAtlas.Geometry?
    /// The complete sprite (the caller places it under the tabletop) and the copy revealed above the table.
    let body = SKSpriteNode()
    let above = SKCropNode()
    private let aboveNode = SKSpriteNode()
    private let mask = SKNode(), outside = SKShapeNode(), upper = SKShapeNode(), hand = SKShapeNode()

    init(engine: MPEngine, poses: MPPoseSprites) {
        self.engine = engine; self.poses = poses
        for shape in [outside, upper, hand] { shape.fillColor = .white; shape.strokeColor = .clear; shape.lineWidth = 0; mask.addChild(shape) }
        above.maskNode = mask; above.addChild(aboveNode)
    }
    /// Android `configure`: the actor height and the floor / inverse / ball projections. The world position is kept
    /// through rotation; only the projection changes.
    func configure(height: CGFloat, ground: @escaping (MPPoint) -> CGPoint, world: @escaping (CGPoint) -> MPPoint, ballPoint: @escaping (MPPoint, Double) -> CGPoint) {
        self.height = max(height, 1); project = ground; inverse = world; ball = ballPoint
        lastPlan = nil
    }
    private func legal(_ p: MPPoint) -> Bool { p.y <= -0.004 || p.x <= -0.004 || p.x >= 1.004 }
    private func offFootprint(_ q: MPPoint) -> Bool { q.y <= 0 || q.x <= -0.004 || q.x >= 1.004 }
    /// Android `poseFor`: the cheapest legal pose whose drawn racket meets the ball with both shoes off the tabletop.
    private func poseFor(_ point: MPPoint, _ z: Double) -> Pose {
        let at = ball(point, z)
        var best: Pose?, cost = Double.greatestFiniteMagnitude
        for facing in [MPPoseAtlas.Facing.front, .side] {
            for mirror in [false, true] {
                for phase in [2, 1, 0, 3] {
                    guard let g = poses.geometry(id, facing, mirror: mirror, foot: .zero, height: height, phase: phase) else { continue }
                    let exact = inverse(CGPoint(x: at.x - g.racket.x, y: at.y - g.racket.y))
                    let soles = poses.floorSupports(id, facing, mirror: mirror, foot: project(exact), height: height, phase: phase).map(inverse)
                    let left = MPPoint(exact.x - max((soles.map(\.x).max() ?? exact.x) + 0.006, 0), exact.y)
                    let right = MPPoint(exact.x + max(1.006 - (soles.map(\.x).min() ?? exact.x), 0), exact.y)
                    for p in [exact, MPPoint(exact.x, min(exact.y, -0.006)), left, right] {
                        guard legal(p), poses.floorSupports(id, facing, mirror: mirror, foot: project(p), height: height, phase: phase).allSatisfy({ offFootprint(inverse($0)) }),
                              let actual = poses.geometry(id, facing, mirror: mirror, foot: project(p), height: height, phase: phase) else { continue }
                        let gap = Double(hypot(at.x - actual.racket.x, at.y - actual.racket.y))
                        if gap > Double(actual.radius + height * 0.025) { continue }
                        let c = floorFoot.distance(p) + gap / Double(height) * 0.12 + (phase == 2 ? 0 : 0.015)
                        if c < cost { cost = c; best = Pose(foot: p, facing: facing, mirror: mirror, phase: phase) }
                    }
                }
            }
        }
        if let best { return best }
        let mirror = point.x < 0.5
        let racket = poses.geometry(id, .front, mirror: mirror, foot: .zero, height: height, phase: 2)?.racket ?? .zero
        let p = inverse(CGPoint(x: at.x - racket.x, y: at.y - racket.y))
        return Pose(foot: MPPoint(p.x, min(p.y, -0.10)), facing: .front, mirror: mirror, phase: 2)
    }
    /// Android `canReach` (engine `botCanReach`).
    func canReach(_ point: MPPoint, _ z: Double) -> Bool {
        let p = poseFor(point, z), at = ball(point, z)
        guard let g = poses.geometry(id, p.facing, mirror: p.mirror, foot: project(p.foot), height: height, phase: p.phase) else { return true }
        return hypot(at.x - g.racket.x, at.y - g.racket.y) <= g.radius + height * 0.025
    }
    /// Android `moveTo`: around the far corners when the feet change side or leave the footprint. A recovery's
    /// smoothstep peak (1.5 × the average speed) is bounded by the player's movement (3010b3e); an incoming contact
    /// keeps its deadline.
    private func moveTo(_ p: MPPoint, _ seconds: Double, recovering: Bool = false) {
        var nodes = [floorFoot]
        let opposite = (floorFoot.x < 0.5) != (p.x < 0.5)
        if floorFoot.y > -0.004 && (p.y <= -0.004 || opposite) { nodes.append(MPPoint(floorFoot.x, -0.10)) }
        if p.y > -0.004 && (floorFoot.y <= -0.004 || opposite) { nodes.append(MPPoint(p.x, -0.10)) }
        nodes.append(p); route = nodes; elapsed = 0
        let distance = zip(nodes, nodes.dropFirst()).reduce(0) { $0 + $1.0.distance($1.1) }
        let speed = 1.6 * (engine.bot?.movement ?? 1)
        duration = recovering ? max(max(seconds, 0.08), 1.5 * distance / speed) : max(seconds, 0.08)
    }
    /// Android `update`.
    func update(_ dt: Double, character: String) {
        id = MPRoster.find(character)?.id ?? "minik"
        let previous = project(floorFoot), stroke = engine.minikStroke
        if let plan = engine.botIntercept, plan != lastPlan {
            pose = poseFor(plan.point, plan.height)
            moveTo(pose.foot, max((engine.botContactAfter ?? plan.after) - 0.20, 0.08))
            lastPlan = plan; returning = false
        } else if engine.botIntercept == nil && stroke.active && stroke.id != serveStroke && engine.rally == 0 {
            serveStroke = stroke.id; pose = poseFor(stroke.point, stroke.height)
            moveTo(pose.foot, 0.20); returning = false
        } else if engine.botIntercept == nil && !returning &&
                    (engine.awaitingServe || engine.lastResolution != nil || engine.flight?.striker == .minik && stroke.age >= 0.44) {
            // Recover after the return's follow-through, before the human replies (3010b3e).
            moveTo(MPPoint(0.5, -0.10), 0.7, recovering: true); returning = true; lastPlan = nil
        }
        if elapsed < duration {
            elapsed = min(elapsed + dt, duration)
            let t = elapsed / duration
            var d = zip(route, route.dropFirst()).reduce(0) { $0 + $1.0.distance($1.1) } * (t * t * (3 - 2 * t))
            for (a, b) in zip(route, route.dropFirst()) {
                let length = a.distance(b)
                if d <= length { let f = length < 0.0001 ? 1 : d / length; floorFoot = MPPoint(a.x + (b.x - a.x) * f, a.y + (b.y - a.y) * f); break }
                d -= length; floorFoot = b
            }
        }
        let now = project(floorFoot)
        gait.update(dt, travel: Float(hypot(now.x - previous.x, now.y - previous.y) / height), stroke: stroke.active && !returning)
    }
    private func show(_ node: SKSpriteNode, scene: (CGPoint) -> CGPoint) -> MPPoseAtlas.Geometry? {
        let s = engine.minikStroke, active = s.active && !returning
        let phase = !active ? 0 : !s.contacted ? 1 : s.age <= 0.35 ? pose.phase : s.age < 0.50 ? 3 : 0
        let walking = gait.walking && !active
        return poses.show(node, id + (walking ? "-walk" : ""), active || floorFoot.y > -0.004 ? pose.facing : .front, mirror: pose.mirror,
                          foot: project(floorFoot), height: height, phase: walking ? gait.phase : phase, championRank: engine.championLevel, scene: scene)
    }
    /// Android `draw` and `drawAboveTable`: the complete body (the caller keeps it under the tabletop), and the same
    /// pose revealed outside the tabletop, above the feet's table line, and around a contacting racket. The table hides
    /// the lower leg behind its corner. `tabletop` and `bounds` are view coordinates; the tabletop runs clockwise on
    /// screen, so the outside region is (bounds − tabletop) under either fill rule.
    func render(tabletop: CGPath, bounds: CGRect, scene: (CGPoint) -> CGPoint) {
        geometry = show(body, scene: scene)
        _ = show(aboveNode, scene: scene)
        let o = scene(.zero), ex = scene(CGPoint(x: 1, y: 0)), ey = scene(CGPoint(x: 0, y: 1))
        var t = CGAffineTransform(a: ex.x - o.x, b: ex.y - o.y, c: ey.x - o.x, d: ey.y - o.y, tx: o.x, ty: o.y)
        let region = CGMutablePath()
        // Counter-clockwise outer rectangle on screen, opposite to the tabletop's winding.
        region.move(to: CGPoint(x: bounds.minX, y: bounds.minY)); region.addLine(to: CGPoint(x: bounds.minX, y: bounds.maxY))
        region.addLine(to: CGPoint(x: bounds.maxX, y: bounds.maxY)); region.addLine(to: CGPoint(x: bounds.maxX, y: bounds.minY)); region.closeSubpath()
        region.addPath(tabletop)
        outside.path = region.copy(using: &t)
        let line = ball(floorFoot, 0).y
        upper.path = CGPath(rect: CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: max(0, line - bounds.minY)), transform: &t)
        // The contacting hand is above the surface even when the body is behind it.
        if let g = geometry, engine.minikStroke.active {
            let r = g.radius * 1.25
            hand.path = CGPath(ellipseIn: CGRect(x: g.racket.x - r, y: g.racket.y - r, width: 2 * r, height: 2 * r), transform: &t)
        } else { hand.path = nil }
    }
    func setHidden(_ hidden: Bool) { body.isHidden = hidden; above.isHidden = hidden }
}
