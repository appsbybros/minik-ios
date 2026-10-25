import SpriteKit
import UIKit

/// Android `LargeMatchRenderer` (a4174b6 … 29f5dc7): the ordinary match engine on the daily table (Indoors and Park
/// singles). No second physics simulation. View coordinates are points with a top-left origin (Android pixels);
/// `scene` converts them into the SpriteKit scene. Only used when the pose atlases are bundled.
final class MPLargeMatch {
    private(set) var layout = MPPracticeTableLayout.fit(1, 1)
    private let poses: MPPoseSprites
    private unowned let engine: MPEngine
    let root = SKNode()
    private var feet = [CGPoint.zero, CGPoint.zero]
    private var walk = [0.0, 0.0], moving = [false, false]
    private let gait = [MPGait(), MPGait()]
    private var settledMirror = [false, false]
    private var ids = ["miniko", "minik"]
    private var contactIds = [-1, -1]
    private var ages = [10.0, 10.0]
    private var impactPoses: [ReachPose?] = [nil, nil]
    private var positioned = false
    private(set) var localGeometry: MPPoseAtlas.Geometry?
    private(set) var farGeometry: MPPoseAtlas.Geometry?
    var localFoot: CGPoint { feet[0] }
    var nearFloorY: CGFloat { CGFloat(layout.top + layout.depth + layout.floorDrop + layout.actorHeight * 0.04) }
    private var size = CGSize(width: 1, height: 1)
    // Nodes, in Android's drawing order (zPosition within `root`).
    private let shadows = [SKShapeNode(), SKShapeNode()]
    private let players = [SKSpriteNode(), SKSpriteNode()]
    private let tableNode = SKSpriteNode(), netNode = SKSpriteNode()
    private let bounceNode = SKShapeNode(), faultNode = SKShapeNode()
    private let reveal = SKCropNode(), revealMask = SKShapeNode(), revealPlayer = SKSpriteNode()
    private let ballNode = SKSpriteNode(), ballShadow = SKShapeNode(), spin = MPSpinArt.node()
    private let paddleHandle = SKShapeNode(), paddleFace = SKShapeNode()
    /// Android 496a709: the local house player stands on the floor with its complete poses (`GroundedRival`).
    private let rival: MPGroundedRival
    /// Android `rivalFloor`: the grounded rival's feet (world coordinates).
    var rivalFloor: MPPoint { rival.floorFoot }

    init(engine: MPEngine, poses: MPPoseSprites) {
        self.engine = engine; self.poses = poses; rival = MPGroundedRival(engine: engine, poses: poses)
        rival.body.zPosition = 3; rival.above.zPosition = 6
        for (i, s) in shadows.enumerated() { s.fillColor = MPColor.ui(0x380d1930); s.strokeColor = .clear; s.zPosition = 1; s.isHidden = i == 0 }
        players[1].zPosition = 3; tableNode.zPosition = 4; bounceNode.zPosition = 5; faultNode.zPosition = 5.1
        reveal.zPosition = 6; netNode.zPosition = 8; players[0].zPosition = 9; paddleHandle.zPosition = 9; paddleFace.zPosition = 9.1
        bounceNode.fillColor = .clear; bounceNode.strokeColor = MPColor.ui(0xbbffffff)
        faultNode.fillColor = .clear; faultNode.strokeColor = MPColor.ui(0xffff5454)
        ballShadow.fillColor = MPColor.ui(0x65001d2a); ballShadow.strokeColor = .clear
        paddleHandle.fillColor = MPColor.ui(0xffdda75d); paddleHandle.strokeColor = .clear
        paddleFace.fillColor = MPColor.ui(0xffe53a64); paddleFace.strokeColor = .clear
        revealMask.fillColor = .white; revealMask.strokeColor = .clear; reveal.maskNode = revealMask; reveal.addChild(revealPlayer)
        tableNode.anchorPoint = CGPoint(x: 0, y: 1); netNode.anchorPoint = CGPoint(x: 0, y: 1)
        ([shadows[0], shadows[1], players[1], rival.body, tableNode, bounceNode, faultNode, reveal, rival.above, netNode, players[0], paddleHandle, paddleFace, ballShadow, ballNode, spin] as [SKNode]).forEach(root.addChild)
    }
    /// Android `resize`: full-size characters need the table at racket/waist height, with their feet on its floor.
    func resize(_ size: CGSize, scene: (CGPoint) -> CGPoint) {
        self.size = size
        let fit = MPPracticeTableLayout.fit(Double(size.width), Double(size.height))
        layout = fit; layout.floorDrop = fit.actorHeight * 0.62; positioned = false
        let drop = layout.floorDrop
        rival.configure(height: actorHeight(1), ground: { [unowned self] p in var q = self.projected(p); q.y += CGFloat(drop); return q },
                        world: { [unowned self] p in self.layout.ground(x: Double(p.x), y: Double(p.y) - drop) },
                        ballPoint: { [unowned self] p, z in self.ballPoint(p, z) })
        let corners = [MPPoint(0, 0), MPPoint(1, 0), MPPoint(1, 1), MPPoint(0, 1)].map { projected($0) }
        let outline = CGMutablePath(); outline.addLines(between: corners); outline.closeSubpath()
        tableOutline = outline
        engine.botCanReach = engine.networked ? nil : { [weak self] p, z in self?.rival.canReach(p, z) ?? true }
        renderTable(scene: scene)
    }
    private var tableOutline: CGPath = CGMutablePath()
    private func actorHeight(_ i: Int) -> CGFloat { CGFloat(layout.actorHeight) * (i == 0 ? 1.50 : 1.08) }
    private func projected(_ v: MPPoint, _ z: Double = 0) -> CGPoint { let p = layout.project(v, z); return CGPoint(x: p.x, y: p.y) }
    private func face(_ i: Int) -> MPPoseAtlas.Facing { i == 0 ? .rear : .front }
    private func stroke(_ i: Int) -> MPStroke { i == 0 ? engine.childStroke : engine.minikStroke }
    private func contact(_ i: Int) -> Double {
        let s = stroke(i)
        return s.active ? s.point.y.mpClamp(i == 0 ? 0.72 : 0, i == 0 ? 1 : 0.28) : i == 0 ? 0.94 : 0.02
    }
    private var ballRadius: CGFloat { max(5, CGFloat(layout.width) * 0.014) }
    private func contactPhase(_ i: Int) -> Int {
        // Android c9f5fa6: the extended arm keeps the body outside the sideline during a short wide return.
        if i == 1 && MPProjection.besideTable(engine.motion.body) { return 1 }
        let s = stroke(i)
        let impact = ballPoint(s.point, s.height).y
        let floor = i == 0 ? nearFloorY : CGFloat(layout.top + layout.floorDrop)
        func gap(_ phase: Int) -> CGFloat {
            guard let g = poses.geometry(ids[i], face(i), mirror: mirror(i), foot: .zero, height: actorHeight(i), phase: phase) else { return .greatestFiniteMagnitude }
            return max((i == 0 ? floor + g.racket.y - impact : impact - floor - g.racket.y) - g.radius - ballRadius, 0)
        }
        // Pick an authored low-racket pose only when the normal strike cannot reach this ball from the floor.
        return [2, 0, 1, 3].min { gap($0) < gap($1) } ?? 2
    }
    private struct ReachPose { var phase: Int; var mirrored: Bool; var lean: CGFloat; var gap: CGFloat }
    private func reachPose(_ i: Int, _ point: MPPoint? = nil, _ height: Double? = nil) -> ReachPose {
        let ball = ballPoint(point ?? stroke(i).point, height ?? stroke(i).height), foot = feet[i]
        var best = ReachPose(phase: 2, mirrored: false, lean: 0, gap: .greatestFiniteMagnitude)
        for phase in [2, 0, 1, 3] {
            for mirrored in [false, true] {
                guard let g = poses.geometry(ids[i], face(i), mirror: mirrored, foot: foot, height: actorHeight(i), phase: phase) else { continue }
                // A bounded whole-body lean keeps the feet planted. Never detach the hand, translate the ball, or slide
                // a human to manufacture a return.
                for degrees in [0, 1, -1, 2, -2, 3, -3, 4, -4, 5, -5, 6, -6, 7, -7, 8, -8] {
                    let a = Double(degrees) * .pi / 180, dx = Double(g.racket.x - foot.x), dy = Double(g.racket.y - foot.y)
                    let x = Double(foot.x) + dx * cos(a) - dy * sin(a), y = Double(foot.y) + dx * sin(a) + dy * cos(a)
                    let gap = CGFloat(hypot(Double(ball.x) - x, Double(ball.y) - y)) - g.radius - ballRadius
                    if gap <= 0 { return ReachPose(phase: phase, mirrored: mirrored, lean: CGFloat(degrees), gap: gap) }
                    if gap < best.gap { best = ReachPose(phase: phase, mirrored: mirrored, lean: CGFloat(degrees), gap: gap) }
                }
            }
        }
        return best
    }
    /// Android `canReturn` (engine `childCanReach`): the planted player can actually reach this ball.
    func canReturn(_ point: MPPoint, _ z: Double) -> Bool { !positioned || reachPose(0, point, z).gap <= 1 }
    func racketPoint(_ i: Int) -> CGPoint { (i == 0 ? localGeometry : farGeometry)?.racket ?? feet[i] }
    func contactAllowance(_ i: Int) -> CGFloat { ((i == 0 ? localGeometry : farGeometry)?.radius ?? 0) + ballRadius }
    private func targetX(_ i: Int) -> Double {
        if i == 0 { return (engine.paddle ?? engine.restingPaddle).x }
        let s = stroke(i); if s.active { return s.point.x }
        // Android c9f5fa6: follow the racket hand, which may be beside the table.
        let motion = engine.motion, hand = MPProjection.racket(motion.body, motion.left)
        return ((hand.x - MPProjection.left) / MPProjection.tableWidth).mpClamp(-0.25, 1.25)
    }
    private func mirror(_ i: Int) -> Bool { i == 1 && MPProjection.besideTable(engine.motion.body) ? engine.motion.body.x < 470.5 : stroke(i).left }
    func update(_ dt: Double, local: String, remote: String) {
        ids[0] = MPRoster.find(local)?.id ?? "miniko"; ids[1] = MPRoster.find(remote)?.id ?? "minik"
        if !engine.networked {
            rival.update(dt, character: ids[1])
            var q = projected(rival.floorFoot); q.y += CGFloat(layout.floorDrop); feet[1] = q
        }
        for i in 0...1 {
            if i == 1 && !engine.networked { continue }
            let s = stroke(i); ages[i] += dt
            let freshContact = s.contacted && contactIds[i] != s.id
            if freshContact { contactIds[i] = s.id; ages[i] = 0 }
            if !s.active { impactPoses[i] = nil }
            let anchor = poses.geometry(ids[i], face(i), mirror: i == 0 ? false : mirror(i), foot: .zero, height: actorHeight(i), phase: i == 0 || !s.active ? 0 : contactPhase(i))?.racket ?? .zero
            let z = s.active ? s.height : i == 0 ? 0.18 : 0.085
            // Android c9f5fa6: an online opponent beside the table stands at its racket's depth, not the far end line.
            let motion = engine.motion, side = i == 1 && MPProjection.besideTable(motion.body)
            let farY = side ? (s.active ? s.point.y : MPProjection.tableY(MPProjection.racket(motion.body, motion.left).y)) : contact(i)
            let impact = ballPoint(MPPoint(targetX(i), i == 0 ? 0.94 : farY), i == 0 ? 0.18 : z)
            let x = impact.x - anchor.x
            // The tabletop is not the floor. A complete pose may step back from the baseline, but never lift its feet
            // through the table to follow a high ball.
            let floorY = i == 0 ? nearFloorY : side ? impact.y - anchor.y : min(impact.y - anchor.y, CGFloat(layout.top + layout.floorDrop))
            let previous = feet[i].x
            let fraction = !positioned || s.contacted && ages[i] < 0.04 ? 1 : CGFloat(1 - exp(-dt / (s.active ? 0.025 : 0.08)))
            feet[i] = CGPoint(x: previous + (x - previous) * fraction, y: !positioned ? floorY : feet[i].y + (floorY - feet[i].y) * fraction)
            let distance = abs(feet[i].x - previous); moving[i] = positioned && Double(distance) > layout.actorHeight * 0.001
            walk[i] += Double(distance) / layout.actorHeight * 7
            gait[i].update(dt, travel: Float(distance / actorHeight(i)), stroke: s.active)
            if freshContact { let pose = reachPose(i); settledMirror[i] = pose.mirrored; impactPoses[i] = pose }
        }
        positioned = true
    }
    /// One continuous, time-independent projection for both incoming and outgoing flights. Net and elevated ball share
    /// a smooth perspective scale; table bounce height stays exactly zero.
    private var heightScale: Double { layout.depth * 0.45 }
    private func loft(_ z: Double) -> Double { MPTableBallProjection.rise(z) * layout.depth / layout.lift }
    private func groundPoint(_ v: MPPoint) -> CGPoint { projected(v) }
    func ballPoint(_ v: MPPoint, _ z: Double) -> CGPoint { var p = projected(v, loft(z)); p.y -= ballRadius; return p }
    /// Android `input`: the touched table point at the ball's height; nil far outside the table.
    func input(_ x: CGFloat, _ y: CGFloat, _ z: Double) -> MPPoint? {
        let v = layout.ground(x: Double(x), y: Double(y + ballRadius), z: loft(z))
        guard (-0.35...1.35).contains(v.x), (-0.25...1.45).contains(v.y) else { return nil }
        return MPPoint(v.x.mpClamp(0, 1), v.y.mpClamp(0, 1))
    }
    func velocity(_ point: MPPoint, _ dx: CGFloat, _ dy: CGFloat, _ z: Double) -> MPPoint {
        let q = ballPoint(point, z), at = layout.ground(x: Double(q.x + dx * 0.001), y: Double(q.y + ballRadius + dy * 0.001), z: loft(z))
        return MPPoint((at.x - point.x) * 1000, (at.y - point.y) * 1000)
    }
    /// Android `bodies`: the drawn players as loose-ball obstacles.
    func bodies() {
        guard positioned else { return }
        engine.visibleFloor = -layout.floorDrop / heightScale
        engine.visibleBodies = (0...1).map { i in
            let local = i == 1 && !engine.networked
            let y = i == 0 ? 1.06 : local ? rival.floorFoot.y : -0.06
            let x = local ? rival.floorFoot.x : layout.ground(x: Double(feet[i].x), y: layout.top + layout.depth * y).x
            let top = MPTableBallProjection.height((layout.top + layout.depth * y - Double(feet[i].y - actorHeight(i))) / layout.depth)
            return MPLooseBall.Body(x: x, y: y, radiusX: 0.13, radiusY: 0.06, bottom: engine.visibleFloor, top: top)
        }
    }
    @discardableResult private func player(_ node: SKSpriteNode, _ i: Int, scene: (CGPoint) -> CGPoint) -> MPPoseAtlas.Geometry? {
        let s = stroke(i), contact = s.contacted && ages[i] < 0.085
        let pose = contact ? (impactPoses[i] ?? reachPose(i)) : nil
        let phase = pose?.phase ?? (!s.active ? 0 : !s.contacted ? (i == 0 && ids[i] == "minik" ? 0 : 1) : ages[i] < 0.27 ? 3 : 0)
        let walking = gait[i].walking && !s.active
        let follow = s.active && s.contacted ? impactPoses[i] : nil
        let lean = pose?.lean ?? (follow?.lean ?? 0) * CGFloat(1 - ((ages[i] - 0.085) / 0.185).mpClamp(0, 1))
        let mirrored = pose?.mirrored ?? follow?.mirrored ?? (s.active ? mirror(i) : settledMirror[i])
        guard let original = poses.show(node, ids[i] + (walking ? "-walk" : ""), face(i), mirror: mirrored, foot: feet[i], height: actorHeight(i),
                                        phase: walking ? gait[i].phase : phase, lean: lean, championRank: i == 1 ? engine.championLevel : -1, scene: scene) else { return nil }
        // The geometry follows the same rotation about the foot (bounds as their rotated bounding box).
        let t = CGAffineTransform(translationX: feet[i].x, y: feet[i].y).rotated(by: lean * .pi / 180).translatedBy(x: -feet[i].x, y: -feet[i].y)
        return MPPoseAtlas.Geometry(bounds: original.bounds.applying(t), racket: original.racket.applying(t), radius: original.radius, frame: original.frame)
    }
    /// Android `draw(canvas, showLocal)`.
    func render(showLocal: Bool, scene: (CGPoint) -> CGPoint) {
        let tw = CGFloat(layout.width)
        for i in 0...1 {
            let f = feet[i]; shadows[i].isHidden = i == 0 && !showLocal
            shadows[i].path = CGPath(ellipseIn: CGRect(x: -tw * 0.06, y: -tw * 0.009, width: tw * 0.12, height: tw * 0.018), transform: nil)
            shadows[i].position = scene(f)
        }
        let renderBall = engine.renderedBall
        let farOut = renderBall.y < 0 && (engine.looseBall?.bodyHits ?? 0) == 0
        if !engine.networked {
            // Android 496a709: the grounded rival — its full body under the tabletop, and the part outside or above it.
            players[1].isHidden = true; reveal.isHidden = true; rival.setHidden(false)
            rival.render(tabletop: tableOutline, bounds: CGRect(origin: .zero, size: size).insetBy(dx: -size.width, dy: -size.height), scene: scene)
            farGeometry = rival.geometry
        } else {
            rival.setHidden(true)
            farGeometry = player(players[1], 1, scene: scene)
            let motion = engine.motion, s = engine.minikStroke
            if MPProjection.besideTable(motion.body) {
                // Android c9f5fa6: a player outside a sideline stands beside the tabletop, not behind it. Reveal the
                // head and torso above the surface; the real tabletop still occludes any lower leg projected inside it.
                let y = s.active ? s.point.y : MPProjection.tableY(MPProjection.racket(motion.body, motion.left).y)
                let line = groundPoint(MPPoint(targetX(1), y)).y
                reveal.isHidden = false
                let a = scene(CGPoint(x: -10000, y: -10000)), b = scene(CGPoint(x: 10000, y: line))
                revealMask.path = CGPath(rect: CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y)), transform: nil)
                player(revealPlayer, 1, scene: scene)
            } else if let g = farGeometry, s.contacted && ages[1] < 0.085 {
                // Only the striking hand can reach over the far edge. Never reveal an idle patch of torso through the
                // tabletop.
                reveal.isHidden = false
                let r = g.radius * 1.25, c = scene(g.racket)
                revealMask.path = CGPath(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r), transform: nil)
                player(revealPlayer, 1, scene: scene)
            } else { reveal.isHidden = true }
        }
        if let b = engine.bouncePoint, engine.bounceAge < 0.38 {
            bounceNode.isHidden = false; bounceNode.lineWidth = tw * 0.006; bounceNode.position = scene(groundPoint(b))
            bounceNode.path = CGPath(ellipseIn: CGRect(x: -tw * 0.045, y: -tw * 0.022, width: tw * 0.09, height: tw * 0.044), transform: nil)
        } else { bounceNode.isHidden = true }
        if let m = engine.faultMark, engine.faultAge < 3 {
            faultNode.isHidden = false; faultNode.lineWidth = tw * 0.009; faultNode.position = scene(groundPoint(m))
            faultNode.path = CGPath(ellipseIn: CGRect(x: -tw * 0.035, y: -tw * 0.035, width: tw * 0.07, height: tw * 0.07), transform: nil)
        } else { faultNode.isHidden = true }
        // Depth ordering near the mesh: an airborne ball on the far half can be behind the net on screen without
        // physically striking it.
        let behindNet = !farOut && renderBall.y < 0.5
        let ballZ: CGFloat = farOut ? 2 : behindNet ? 7 : 10
        if showLocal {
            localGeometry = player(players[0], 0, scene: scene); paddleHandle.isHidden = true; paddleFace.isHidden = true
        } else {
            players[0].isHidden = true; localGeometry = nil; paddleHandle.isHidden = false; paddleFace.isHidden = false
            let s = engine.childStroke
            let at = ballPoint(s.active ? s.point : engine.paddle ?? engine.restingPaddle, s.active ? s.height : engine.restingHeight)
            paddleHandle.path = CGPath(roundedRect: CGRect(x: -tw * 0.012, y: -tw * 0.09, width: tw * 0.024, height: tw * 0.09), cornerWidth: tw * 0.01, cornerHeight: tw * 0.01, transform: nil)
            paddleHandle.position = scene(at)
            paddleFace.path = CGPath(ellipseIn: CGRect(x: -tw * 0.045, y: -tw * 0.025, width: tw * 0.09, height: tw * 0.085), transform: nil)
            paddleFace.position = scene(at)
        }
        let visible = engine.ballVisible
        ballNode.isHidden = !visible; ballShadow.isHidden = !visible
        let r = ballRadius, at = ballPoint(renderBall, engine.renderedHeight), shadow = groundPoint(renderBall)
        ballNode.zPosition = ballZ; ballShadow.zPosition = ballZ - 0.01; spin.zPosition = ballZ + 0.01
        if ballNode.texture == nil { ballNode.texture = Self.ballTexture() }
        ballNode.size = CGSize(width: 2 * r, height: 2 * r); ballNode.position = scene(at)
        ballShadow.path = CGPath(ellipseIn: CGRect(x: -r, y: -r * 0.35, width: 2 * r, height: r * 0.7), transform: nil); ballShadow.position = scene(shadow)
        MPSpinArt.update(spin, at: scene(at), radius: r, flight: engine.flight, visible: visible)
    }
    /// Android `ball`: the yellow match ball (white → 0xffffe084 → 0xffe7aa35 radial gradient from the upper left).
    private static func ballTexture() -> SKTexture {
        let side: CGFloat = 64
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { context in
            let c = context.cgContext, r = side / 2
            c.addEllipse(in: CGRect(x: 0, y: 0, width: side, height: side)); c.clip()
            let colors = [UIColor.white.cgColor, MPColor.ui(0xffffe084).cgColor, MPColor.ui(0xffe7aa35).cgColor] as CFArray
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: nil) {
                let centre = CGPoint(x: r - r * 0.3, y: r - r * 0.4)
                c.drawRadialGradient(g, startCenter: centre, startRadius: 0, endCenter: centre, endRadius: r * 1.5, options: [.drawsAfterEndLocation])
            }
        }
        return SKTexture(image: image)
    }
    /// Android `PracticeTableArt.frame/surface/lines` and `net` (`net` uses the ball's loft for the net height), drawn once
    /// per size into two textures placed in view coordinates.
    private func renderTable(scene: (CGPoint) -> CGPoint) {
        let art = MPPracticeTableArt(), tw = CGFloat(layout.width), drop = CGFloat(layout.floorDrop)
        let netHeight = engine.tuning.netHeight
        let format = UIGraphicsImageRendererFormat(); format.scale = min(UIScreen.main.scale, 3); format.opaque = false
        let table = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let c = context.cgContext, project: MPPracticeTableArt.Project = { v, z in self.projected(v, z) }
            art.frame(c, project, tw: tw, drop: drop); art.surface(c, project, top: CGFloat(layout.top), depth: CGFloat(layout.depth)); art.lines(c, project)
        }
        let net = UIGraphicsImageRenderer(size: size, format: format).image { context in
            art.net(context.cgContext) { v, z in self.projected(v, self.loft(z * netHeight / 0.12)) }
        }
        for (node, image) in [(tableNode, table), (netNode, net)] {
            node.texture = SKTexture(image: image); node.size = size; node.position = scene(.zero)
        }
    }
}
