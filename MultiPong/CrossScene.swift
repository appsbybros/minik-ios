import SpriteKit
import UIKit

/// Android PongPlayerAtlas (MinikCrossPong 5c1aa4d): complete authored paddle poses, no detached limbs or synthetic legs. Each
/// character sheet (`mpx_pose_<id>`, and `mpx_pose_<id>_walk`) holds 12 frames: rows FRONT, SIDE, REAR of 4 phases. The frame's
/// foot, visible bounds and paddle centre are in frame pixels (`mpx_pose_atlas`, Android `pong-poses/atlas.json`).
final class MPXPoseAtlas {
    enum Facing: Int { case front = 0, side = 1, rear = 2 }
    struct Geometry { var bounds: CGRect; var racket: CGPoint; var radius: Double }
    private struct Frame { var source: CGRect; var visible: CGRect; var foot: CGPoint; var paddle: CGPoint; var radius: Double }
    private struct Sheet { var sheet: SKTexture; var size: CGSize; var frames: [Frame]; var heights: [Double] }
    static let shared = MPXPoseAtlas()
    private lazy var manifest: [String: Any] = {
        guard let data = NSDataAsset(name: "mpx_pose_atlas")?.data, let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return value
    }()
    private var characters: [String: Sheet] = [:]
    private var textures: [String: SKTexture] = [:]
    /// "amber" → `mpx_pose_amber`, "amber-walk" → `mpx_pose_amber_walk`.
    private static func asset(_ id: String) -> String { "mpx_pose_" + id.replacingOccurrences(of: "-", with: "_") }
    func has(_ id: String) -> Bool { manifest[id] != nil }
    private func character(_ id: String) -> Sheet? {
        if let known = characters[id] { return known }
        guard let data = manifest[id] as? [String: Any], let list = data["frames"] as? [[String: Any]], list.count >= 12,
              let image = UIImage(named: MPXPoseAtlas.asset(id)) else { return nil }
        func numbers(_ value: Any?) -> [Double] { (value as? [Any] ?? []).map { ($0 as? NSNumber)?.doubleValue ?? 0 } }
        let frames = list.map { f -> Frame in
            let r = numbers(f["rect"]), b = numbers(f["bounds"]), foot = numbers(f["foot"]), p = numbers(f["paddle"])
            func at(_ a: [Double], _ i: Int) -> Double { i < a.count ? a[i] : 0 }
            return Frame(source: CGRect(x: at(r, 0), y: at(r, 1), width: at(r, 2) - at(r, 0), height: at(r, 3) - at(r, 1)),
                         visible: CGRect(x: at(b, 0), y: at(b, 1), width: at(b, 2) - at(b, 0), height: at(b, 3) - at(b, 1)),
                         foot: CGPoint(x: at(foot, 0), y: at(foot, 1)), paddle: CGPoint(x: at(p, 0), y: at(p, 1)),
                         radius: (f["radius"] as? NSNumber)?.doubleValue ?? 20)
        }
        let size = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let sheet = SKTexture(image: image)
        sheet.filteringMode = .linear
        let value = Sheet(sheet: sheet, size: size, frames: frames, heights: (0...2).map { Double(frames[$0 * 4].visible.height) })
        characters[id] = value
        return value
    }
    private func frame(_ id: String, _ facing: Facing, _ phase: Int) -> (Sheet, Frame)? {
        guard let c = character(id) else { return nil }
        return (c, c.frames[facing.rawValue * 4 + min(3, max(0, phase))])
    }
    /// View coordinates (y down): the drawn bounds, the paddle centre and its radius for a pose standing on `foot`.
    func geometry(_ id: String, _ facing: Facing, mirror: Bool, foot: CGPoint, height: Double, phase: Int) -> Geometry? {
        guard let pair = frame(id, facing, phase) else { return nil }
        let (c, f) = pair
        let scale = height / max(1, c.heights[facing.rawValue])
        func x(_ v: Double) -> Double { Double(foot.x) + (v - Double(f.foot.x)) * scale * (mirror ? -1 : 1) }
        func y(_ v: Double) -> Double { Double(foot.y) + (v - Double(f.foot.y)) * scale }
        let l = x(Double(f.visible.minX)), r = x(Double(f.visible.maxX))
        return Geometry(bounds: CGRect(x: min(l, r), y: y(Double(f.visible.minY)), width: abs(r - l), height: Double(f.visible.height) * scale),
                        racket: CGPoint(x: x(Double(f.paddle.x)), y: y(Double(f.paddle.y))), radius: f.radius * scale)
    }
    /// Places `node` (anchor at the foot) for the pose; `sk` turns view coordinates into the scene's.
    @discardableResult func place(_ node: SKSpriteNode, _ id: String, _ facing: Facing, mirror: Bool, foot: CGPoint, height: Double, phase: Int,
                                  sk: (CGPoint) -> CGPoint) -> Geometry? {
        guard let pair = frame(id, facing, phase) else { node.isHidden = true; return nil }
        let (c, f) = pair
        let key = id + "/" + String(facing.rawValue * 4 + min(3, max(0, phase)))
        let texture: SKTexture
        if let known = textures[key] { texture = known }
        else {
            let w = Double(c.size.width), h = Double(c.size.height)
            texture = SKTexture(rect: CGRect(x: Double(f.source.minX) / w, y: 1 - Double(f.source.maxY) / h,
                                             width: Double(f.source.width) / w, height: Double(f.source.height) / h), in: c.sheet)
            textures[key] = texture
        }
        let scale = height / max(1, c.heights[facing.rawValue])
        node.isHidden = false
        node.texture = texture
        // A sprite's size includes its scale: reset last frame's mirror before sizing, or the next mirror cancels out.
        node.xScale = 1
        node.size = CGSize(width: max(1, Double(f.source.width) * scale), height: max(1, Double(f.source.height) * scale))
        node.anchorPoint = CGPoint(x: Double(f.foot.x) / max(1, Double(f.source.width)), y: 1 - Double(f.foot.y) / max(1, Double(f.source.height)))
        node.xScale = mirror ? -1 : 1
        node.position = sk(foot)
        return geometry(id, facing, mirror: mirror, foot: foot, height: height, phase: phase)
    }
    /// Android BotPortrait (5c1aa4d): the first FRONT pose, cropped to its visible bounds.
    func portrait(_ id: String) -> UIImage? {
        guard let data = manifest[id] as? [String: Any], let list = data["frames"] as? [[String: Any]], let first = list.first,
              let image = UIImage(named: MPXPoseAtlas.asset(id)), let cg = image.cgImage else { return nil }
        let r = (first["rect"] as? [Any] ?? []).map { ($0 as? NSNumber)?.doubleValue ?? 0 }
        let b = (first["bounds"] as? [Any] ?? []).map { ($0 as? NSNumber)?.doubleValue ?? 0 }
        guard r.count >= 2, b.count >= 4 else { return nil }
        let crop = CGRect(x: r[0] + b[0], y: r[1] + b[1], width: b[2] - b[0], height: b[3] - b[1])
        guard let part = cg.cropping(to: crop) else { return nil }
        return UIImage(cgImage: part)
    }
}

/// Android ReceptionCamera (5c1aa4d): an eased zoom toward the receiving paddle and the ball, a reversible screen transform that
/// stays fixed while a finger is down. "zoom" asks for it on this player's own returns, "follow" on another human's.
struct CrossReceptionCamera {
    private(set) var amount = 0.0
    private var x = 0.0, y = 0.0, tx = 0.0, ty = 0.0
    var zoom: Double { 1 + 0.42 * amount }
    mutating func update(_ dt: Double, assist: CrossReception, local: Int, focus: CGPoint, width: Double, height: Double, holding: Bool,
                         zoomOwn: Bool, follow: Bool) {
        if holding { return }
        let own = assist.receiver == local
        let allowed = (own ? zoomOwn : follow) && assist.receiver >= 0 && !UIAccessibility.isReduceMotionEnabled
        let target = allowed ? assist.strength : 0
        let k = 1 - exp(-min(0.075, max(0, dt)) * 4)
        amount += (target - amount) * k
        if amount < 0.0001 { amount = 0; x = Double(focus.x); y = Double(focus.y) }
        else { x += (Double(focus.x) - x) * k; y += (Double(focus.y) - y) * k }
        x = min(width * 0.88, max(width * 0.12, x)); y = min(height * 0.88, max(height * 0.12, y))
        tx = (width * 0.5 - x) * amount; ty = (height * 0.62 - y) * amount
    }
    /// Base (camera-free) view point → painted view point.
    func painted(_ p: CGPoint) -> CGPoint { CGPoint(x: x + (Double(p.x) - x) * zoom + tx, y: y + (Double(p.y) - y) * zoom + ty) }
    /// Painted view point → base view point (touches).
    func base(_ p: CGPoint) -> CGPoint { CGPoint(x: x + (Double(p.x) - tx - x) / zoom, y: y + (Double(p.y) - ty - y) / zoom) }
    /// The camera's focus and translation (view coordinates).
    var focus: CGPoint { CGPoint(x: x, y: y) }
    var shift: CGPoint { CGPoint(x: tx, y: ty) }
}

/// One rendered world for every seat (Android cross/CrossCourt.kt, MinikCrossPong 5c1aa4d): the shared table rotated so the
/// viewer's seat is at the bottom, with thickness, supports, mesh nets and a sunset sheen; whole authored player poses that walk
/// and swing outside the table (the local player seen from behind, holding the real paddle); a fitted overview and, in
/// landscape, an optional gently zooming action camera; the reception zoom; team colours and a team scoreboard; and the daily
/// practice targets and paint. Drawing, input and collision all use CrossGeometry. Android draws in view coordinates (y down);
/// here "view" points are those coordinates and `sk` turns them into SpriteKit's (y up).
final class CrossScene: SKScene {
    static let depth = 4.2
    static let near = 1.45
    static let liftMax = 0.62
    static let liftScale = 0.75
    static let ballSize = 0.042
    static let stand = 0.10
    static let seatColors: [(Double, Double, Double)] = [(183, 53, 120), (37, 112, 205), (34, 197, 94), (250, 204, 21)]
    static let ink = UIColor(red: 23 / 255, green: 62 / 255, blue: 86 / 255, alpha: 1)

    var engine: CrossEngine { didSet { if engine !== oldValue { rebuild() } } }
    /// Who advances the clock: a multi-stage match drives its current table; a practice its own engines; by default the engine.
    var step: ((Double) -> Void)?
    /// Once per frame after the clock advanced (the controller drains events here).
    var onFrame: (() -> Void)?
    var tutorialTarget: Int?
    /// The daily practice whose targets, marks and paint are drawn on the table.
    var practice: CrossPractice?
    var acceptsInput = true
    var names: [String] = []
    /// Kept for the room screens; remote players without a character are shown by their name tag only (5c1aa4d).
    var avatarIcons: [Int: String] = [:]
    /// The landscape action camera (Android `fullScreen`); portrait always fits the table and every body.
    var fullScreen = true { didSet { if oldValue != fullScreen { layoutCourt() } } }
    /// Reception assistance and sound settings (Android `reception_assistance`, `cross_skill_journey/sound`).
    var preferences = MPPreferences()
    /// Team and practice screens: every engine event plays its cue while the court runs (Android CrossCourt.soundEffects).
    var playCue: ((CrossCue) -> Void)? { didSet { bindSounds(force: true) } }

    private var scale = 1.0, cx = 0.0, cy = 0.0
    private var tilt = 0.72
    private var pan = 0.0, panY = 0.0, panMin = 0.0, panMax = 0.0
    private var fittedScale = 1.0, scaleLimit = 1.0
    private var tableMinX = 0.0, tableMaxX = 0.0, tableMinY = 0.0, tableMaxY = 0.0
    private var receptionCamera = CrossReceptionCamera()
    private var notes: [Int: (text: String, at: TimeInterval)] = [:]
    private var previousTime: TimeInterval = 0
    private var hasRendered = false
    private var activeTouch: UITouch?
    private var downPoint = CGPoint.zero
    private var samples: [(time: TimeInterval, point: CGPoint)] = []
    private var lastTapAt: TimeInterval = -1000, lastTapPoint = CGPoint.zero, raisedTap = false
    private var walkDistance: [Int: Double] = [:], lastLateral: [Int: Double] = [:], lastStep: [Int: TimeInterval] = [:]
    private var walkFrame: [Int: Int] = [:], walkFrameAt: [Int: TimeInterval] = [:]
    private var bodyBounds: [Int: CGRect] = [:]
    private var contactRackets: [Int: CGPoint] = [:]
    private var soundEngine: CrossEngine?
    private var soundPolicy = CrossSoundPolicy(localSeat: nil)
    private var running = false
    private let canvas = SKNode()
    private let hud = SKNode()
    private let castShadow = SKShapeNode(), supports = SKNode(), tableUnder = SKShapeNode(), tableRim = SKShapeNode(), tableFill = SKShapeNode()
    private let sheenCrop = SKCropNode(), sheenMask = SKShapeNode(), sheen = SKSpriteNode()
    private let centreLines = SKShapeNode(), tableEdge = SKShapeNode(), highlightNode = SKShapeNode(), bounceNode = SKShapeNode()
    private var territoryNodes: [SKShapeNode] = []
    private var territoryPaths: [CGPath] = []
    private var tablePath: CGPath = CGMutablePath()
    private var outsidePath: CGPath = CGMutablePath()
    private let practiceCrop = SKCropNode(), practiceMask = SKShapeNode(), practiceNode = SKNode()
    private let netsNode = SKNode()
    private var actors: [Int: CrossActorNodes] = [:]
    private let ballShadow = SKShapeNode(circleOfRadius: 1), ballNode = SKShapeNode(circleOfRadius: 1), ballShine = SKShapeNode(circleOfRadius: 1)
    private let netFlash = SKShapeNode(circleOfRadius: 1)
    private let paddleNode = SKNode()
    private let arrowNode = SKShapeNode()
    private var tags: [Int: CrossTagNodes] = [:]
    private var boards: [Int: CrossBoardNodes] = [:]
    private static let font = "HelveticaNeue-Bold"
    private var width: Double { Double(size.width) }
    private var height: Double { Double(size.height) }
    private var scoreboardHeight: Double { width > height ? 48 : 66 }
    private var actionView: Bool { fullScreen && width > height }

    init(engine: CrossEngine) {
        self.engine = engine
        super.init(size: CGSize(width: 430, height: 760))
        scaleMode = .resizeFill
        backgroundColor = .clear
        canvas.zPosition = 0; hud.zPosition = 20
        addChild(canvas); addChild(hud)
        castShadow.fillColor = UIColor(red: 8 / 255, green: 20 / 255, blue: 32 / 255, alpha: 70 / 255); castShadow.strokeColor = .clear; castShadow.zPosition = 0.2
        supports.zPosition = 0.3
        tableUnder.fillColor = UIColor(red: 20 / 255, green: 42 / 255, blue: 59 / 255, alpha: 1); tableUnder.strokeColor = .clear; tableUnder.zPosition = 0.4
        tableRim.strokeColor = UIColor(red: 119 / 255, green: 173 / 255, blue: 192 / 255, alpha: 1); tableRim.lineWidth = 5; tableRim.lineJoin = .round
        tableRim.fillColor = .clear; tableRim.zPosition = 0.5
        tableFill.fillColor = .white; tableFill.strokeColor = .clear; tableFill.zPosition = 0.6
        tableFill.fillTexture = CrossScene.gradient([(20, 104, 126), (44, 179, 192), (16, 108, 141)], vertical: true)
        sheenMask.fillColor = .white; sheenMask.strokeColor = .clear; sheenCrop.maskNode = sheenMask; sheenCrop.zPosition = 0.7
        sheen.texture = CrossScene.sheenTexture(); sheenCrop.addChild(sheen)
        centreLines.strokeColor = UIColor(white: 1, alpha: 210 / 255); centreLines.lineWidth = 1.6; centreLines.zPosition = 1.3
        tableEdge.strokeColor = UIColor(white: 1, alpha: 210 / 255); tableEdge.lineWidth = 2.6; tableEdge.fillColor = .clear; tableEdge.lineJoin = .round; tableEdge.zPosition = 1.4
        highlightNode.strokeColor = UIColor(red: 1, green: 221 / 255, blue: 87 / 255, alpha: 235 / 255); highlightNode.lineWidth = 3.4; highlightNode.fillColor = .clear
        highlightNode.lineJoin = .round; highlightNode.zPosition = 1.5
        bounceNode.fillColor = .clear; bounceNode.strokeColor = .white; bounceNode.lineWidth = 2; bounceNode.zPosition = 1.6
        practiceMask.fillColor = .white; practiceMask.strokeColor = .clear; practiceCrop.maskNode = practiceMask; practiceCrop.zPosition = 1.7
        practiceCrop.addChild(practiceNode)
        netsNode.zPosition = 4
        ballShadow.fillColor = UIColor(red: 10 / 255, green: 34 / 255, blue: 45 / 255, alpha: 1); ballShadow.strokeColor = .clear; ballShadow.zPosition = 4.8
        netFlash.fillColor = .clear; netFlash.strokeColor = UIColor(red: 1, green: 84 / 255, blue: 84 / 255, alpha: 1); netFlash.zPosition = 5.1
        ballNode.fillColor = UIColor(red: 245 / 255, green: 248 / 255, blue: 251 / 255, alpha: 1)
        ballNode.strokeColor = UIColor(red: 171 / 255, green: 186 / 255, blue: 200 / 255, alpha: 1); ballNode.zPosition = 5
        ballShine.fillColor = .white; ballShine.strokeColor = .clear; ballShine.zPosition = 5.05
        paddleNode.zPosition = 6
        arrowNode.fillColor = UIColor(white: 1, alpha: 230 / 255); arrowNode.strokeColor = .clear; arrowNode.zPosition = 30
        let arrow = CGMutablePath()
        arrow.move(to: CGPoint(x: 10, y: 0)); arrow.addLine(to: CGPoint(x: -6, y: -7)); arrow.addLine(to: CGPoint(x: -6, y: 7)); arrow.closeSubpath()
        arrowNode.path = arrow
        for node in [castShadow, tableUnder, tableRim, tableFill] { canvas.addChild(node) }
        canvas.addChild(supports); canvas.addChild(sheenCrop)
        for node in [centreLines, tableEdge, highlightNode, bounceNode] { canvas.addChild(node) }
        canvas.addChild(practiceCrop)
        canvas.addChild(netsNode)
        for node in [ballShadow, ballNode, ballShine, netFlash] { canvas.addChild(node) }
        canvas.addChild(paddleNode)
        hud.addChild(arrowNode)
        buildPaddle()
        rebuild()
    }
    required init?(coder: NSCoder) { return nil }
    override func didMove(to view: SKView) { view.isMultipleTouchEnabled = false; layoutCourt() }
    override func didChangeSize(_ oldSize: CGSize) { layoutCourt() }
    /// Starts or stops the frame loop (Android resumeFrames/stopFrames); pausing play itself is the controller's job.
    func setActive(_ active: Bool) {
        running = active; isPaused = !active; previousTime = 0
        if !active { cancelTouch() }
        bindSounds(force: false)
    }
    /// Android `toggleCamera`: the landscape action camera or every player in view; remembered.
    func toggleCamera() { fullScreen.toggle() }

    private var g: CrossGeometry { engine.geometry }
    private var viewSeat: Int { engine.localSeat ?? 0 }

    // ---- projection -------------------------------------------------------------------------------
    private func k(_ y: Double) -> Double { CrossScene.depth / (CrossScene.depth + (CrossScene.near - y)) }
    /// Concave display height: low balls separate clearly from the net band, high lobs stay on screen.
    private func lift(_ h: Double) -> Double { CrossScene.liftMax * (1 - exp(-max(h, 0) / CrossScene.liftScale)) }
    /// Android `screen`: view coordinates (y down) including the camera pan (not the reception zoom).
    func screen(_ p: MPPoint, _ h: Double = 0) -> CGPoint {
        let q = unpanned(p, h)
        return CGPoint(x: Double(q.x) - pan, y: Double(q.y) - panY)
    }
    /// The same point without the pan, for nodes inside the panned canvas.
    private func unpanned(_ p: MPPoint, _ h: Double = 0) -> CGPoint {
        let v = g.toView(viewSeat, p), kk = k(v.y)
        return CGPoint(x: cx + v.x * scale * kk, y: cy + (v.y * tilt - lift(h)) * scale * kk)
    }
    /// View coordinates (y down) → SpriteKit (y up).
    private func sk(_ q: CGPoint) -> CGPoint { CGPoint(x: q.x, y: size.height - q.y) }
    private func sizeAt(_ p: MPPoint) -> Double { scale * k(g.toView(viewSeat, p).y) }
    /// Inverse of `screen` for points on the table plane (height 0).
    func world(_ sx: Double, _ sy: Double) -> MPPoint {
        let yy = (sy + panY - cy) / (scale * tilt)
        let y = yy * (CrossScene.depth + CrossScene.near) / (CrossScene.depth + yy)
        return g.fromView(viewSeat, MPPoint((sx + pan - cx) / (scale * k(y)), y))
    }

    func layoutCourt() {
        let w = width, h = height
        guard w > 1, h > 1 else { return }
        tilt = w > h ? 0.72 : 1.28
        var minX = 0.0, maxX = 0.0, minY = 0.0, maxY = 0.0
        let geometry = g, seat = viewSeat, t = tilt
        func include(_ p: MPPoint, up: Double = 0, down: Double = 0, half: Double = 0) {
            let v = geometry.toView(seat, p), kk = k(v.y)
            minX = min(minX, (v.x - half) * kk); maxX = max(maxX, (v.x + half) * kk)
            minY = min(minY, (v.y * t - up) * kk); maxY = max(maxY, (v.y * t + down) * kk)
        }
        for s in geometry.seats { geometry.armCorners(s).forEach { include($0) } }
        tableMinX = minX; tableMaxX = maxX; tableMinY = minY; tableMaxY = maxY
        let board = scoreboardHeight
        scaleLimit = min((w - 24) / max(0.01, maxX - minX), (h - board - 24) / max(0.01, maxY - minY))
        if actionView {
            // Crop the near/far players if necessary, but reserve floor space beside both lateral arms so a camera zoom never
            // pushes bodies into the table.
            for s in geometry.seats where abs(geometry.toView(seat, geometry.home(s)).x) > 0.45 {
                include(geometry.fromLocal(s, 0, CrossGeometry.reach + CrossScene.stand), half: 0.72)
            }
        } else {
            for s in geometry.seats { include(geometry.fromLocal(s, 0, CrossGeometry.reach + CrossScene.stand), up: 0.43, down: 0.48, half: 0.48) }
        }
        let fit = min((w - 20) / max(0.01, maxX - minX), (h - board - 20) / max(0.01, maxY - minY))
        scale = max(1, actionView ? min(fit * 0.91, scaleLimit * 0.94) : fit)
        fittedScale = scale; pan = 0; panY = 0
        cx = w / 2 - (minX + maxX) * scale / 2
        cy = board + (h - board - (maxY - minY) * scale) * 0.5 - minY * scale
        panMin = fullScreen ? -scale * 0.12 : 0; panMax = fullScreen ? scale * 0.12 : 0
        pan = pan.mpClamp(panMin, panMax)
        buildPaths()
        render()
    }
    /// Per-seat nodes for the current table (a new stage may have fewer seats).
    private func rebuild() {
        cancelTouch()
        actors.values.forEach { $0.remove() }
        tags.values.forEach { $0.remove() }
        boards.values.forEach { $0.remove() }
        actors = [:]; tags = [:]; boards = [:]
        for s in g.seats {
            actors[s] = CrossActorNodes(parent: canvas)
            tags[s] = CrossTagNodes(parent: hud, font: CrossScene.font)
            boards[s] = CrossBoardNodes(parent: hud, font: CrossScene.font)
        }
        notes = [:]; walkDistance = [:]; lastLateral = [:]; lastStep = [:]; walkFrame = [:]; walkFrameAt = [:]
        bindSounds(force: false)
        layoutCourt()
    }
    private func buildPaths() {
        // Paths are built camera-free inside the canvas, which the pan and the reception zoom move.
        var table: CGPath?
        for s in g.seats {
            let corners = g.armCorners(s).map { sk(unpanned($0)) }
            let arm = CGMutablePath()
            arm.addLines(between: corners); arm.closeSubpath()
            table = table.map { $0.union(arm) } ?? arm
        }
        if g.hub > 0 {
            let hub = CGMutablePath()
            for i in 0...72 {
                let a = Double(i) * 2 * Double.pi / 72
                let q = sk(unpanned(MPPoint(sin(a) * g.hub, cos(a) * g.hub)))
                if i == 0 { hub.move(to: q) } else { hub.addLine(to: q) }
            }
            hub.closeSubpath()
            table = table.map { $0.union(hub) } ?? hub
        }
        let shape: CGPath = table ?? CGMutablePath()
        tablePath = shape
        // Cast shadow and support legs are behind the extruded table, never collision surfaces.
        castShadow.path = shape; castShadow.position = CGPoint(x: 8, y: -scale * 0.27)
        tableUnder.path = shape; tableUnder.position = CGPoint(x: 0, y: -8)
        tableRim.path = shape; tableFill.path = shape; tableEdge.path = shape
        sheenMask.path = shape
        practiceMask.path = shape
        let box = shape.boundingBoxOfPath
        sheen.size = CGSize(width: max(1, 2 * scale), height: max(1, box.height + 40))
        sheen.position = CGPoint(x: cx, y: box.midY)
        supports.removeAllChildren()
        for seat in g.seats {
            for u in [-0.38, 0.38] {
                let foot = sk(unpanned(g.fromLocal(seat, u, CrossGeometry.reach - 0.12)))
                let leg = sizeAt(g.home(seat)) * 0.32
                let post = SKShapeNode(rect: CGRect(x: Double(foot.x) - 3, y: Double(foot.y) - leg, width: 8, height: leg), cornerRadius: 2)
                post.fillColor = UIColor(red: 70 / 255, green: 88 / 255, blue: 101 / 255, alpha: 1); post.strokeColor = .clear
                supports.addChild(post)
                let base = SKShapeNode(ellipseIn: CGRect(x: Double(foot.x) - 6, y: Double(foot.y) - leg - 3, width: 14, height: 5))
                base.fillColor = UIColor(red: 14 / 255, green: 23 / 255, blue: 36 / 255, alpha: 1); base.strokeColor = .clear
                supports.addChild(base)
            }
        }
        territoryNodes.forEach { $0.removeFromParent() }
        territoryNodes = []; territoryPaths = []
        for s in g.seats {
            let wedge = CGMutablePath()
            wedge.move(to: sk(unpanned(MPPoint(0, 0))))
            let from = g.angle(s) - g.sector / 2
            for i in 0...24 {
                let a = from + g.sector * Double(i) / 24
                wedge.addLine(to: sk(unpanned(MPPoint(sin(a), cos(a)) * 3.0)))
            }
            wedge.closeSubpath()
            let clipped = wedge.intersection(shape)
            territoryPaths.append(clipped)
            let node = SKShapeNode(path: clipped)
            let c = CrossScene.seatColors[colorIndex(s) % CrossScene.seatColors.count]
            node.fillColor = UIColor(red: CGFloat(c.0 / 255), green: CGFloat(c.1 / 255), blue: CGFloat(c.2 / 255), alpha: CGFloat(s == viewSeat ? 14.0 / 255 : 24.0 / 255))
            node.strokeColor = .clear; node.lineWidth = 0; node.zPosition = 1.2
            canvas.addChild(node); territoryNodes.append(node)
        }
        // Centre lines along each arm, like the classic table markings.
        let lines = CGMutablePath()
        for s in g.seats {
            lines.move(to: sk(unpanned(g.fromLocal(s, 0, max(g.netLength, 0.62)))))
            lines.addLine(to: sk(unpanned(g.fromLocal(s, 0, CrossGeometry.reach))))
        }
        centreLines.path = lines
        // Bodies are drawn outside the table (Android clipOutPath).
        outsidePath = CGPath(rect: CGRect(x: -3 * width, y: -height, width: 7 * width, height: 3 * height), transform: nil).subtracting(shape)
        actors.values.forEach { $0.setMask(outsidePath) }
        buildNets()
    }
    private func buildNets() {
        netsNode.removeAllChildren()
        let netHeight = engine.physics.netHeight
        let meshColor = UIColor(red: 117 / 255, green: 205 / 255, blue: 217 / 255, alpha: 210 / 255)
        for net in g.nets {
            let steps = 20
            let base = (0...steps).map { sk(unpanned(net.end * (Double($0) / Double(steps)))) }
            let top = (0...steps).map { sk(unpanned(net.end * (Double($0) / Double(steps)), netHeight)) }
            let band = CGMutablePath()
            band.addLines(between: base + top.reversed()); band.closeSubpath()
            let fill = SKShapeNode(path: band)
            fill.fillColor = UIColor(red: 13 / 255, green: 43 / 255, blue: 64 / 255, alpha: 185 / 255); fill.strokeColor = .clear; fill.zPosition = 0
            netsNode.addChild(fill)
            let mesh = CGMutablePath()
            for i in 1..<steps { mesh.move(to: base[i]); mesh.addLine(to: top[i]) }
            for row in 1...4 {
                let line = (0...steps).map { sk(unpanned(net.end * (Double($0) / Double(steps)), netHeight * Double(row) / 5)) }
                mesh.addLines(between: line)
            }
            let meshNode = SKShapeNode(path: mesh)
            meshNode.strokeColor = meshColor; meshNode.lineWidth = 0.65; meshNode.zPosition = 0.1
            netsNode.addChild(meshNode)
            let tape = CGMutablePath()
            tape.move(to: top[0]); tape.addLine(to: top[steps])
            let tapeNode = SKShapeNode(path: tape)
            tapeNode.strokeColor = .white; tapeNode.lineWidth = 2.4; tapeNode.zPosition = 0.2
            netsNode.addChild(tapeNode)
            // Posts at the table edge.
            let post = CGMutablePath()
            post.move(to: base[steps]); post.addLine(to: CGPoint(x: top[steps].x, y: top[steps].y + 2))
            let postNode = SKShapeNode(path: post)
            postNode.strokeColor = UIColor(red: 30 / 255, green: 80 / 255, blue: 150 / 255, alpha: 1); postNode.lineWidth = 3.2; postNode.zPosition = 0.3
            netsNode.addChild(postNode)
        }
        if g.players == 2 { return }
        let c0 = sk(unpanned(MPPoint(0, 0))), c1 = sk(unpanned(MPPoint(0, 0), netHeight))
        let centre = CGMutablePath()
        centre.move(to: c0); centre.addLine(to: CGPoint(x: c1.x, y: c1.y + 2))
        let centreNode = SKShapeNode(path: centre)
        centreNode.strokeColor = UIColor(red: 30 / 255, green: 80 / 255, blue: 150 / 255, alpha: 1); centreNode.lineWidth = 4; centreNode.zPosition = 0.4
        netsNode.addChild(centreNode)
        let cap = SKShapeNode(circleOfRadius: 3.2)
        cap.fillColor = UIColor(red: 250 / 255, green: 214 / 255, blue: 90 / 255, alpha: 1); cap.strokeColor = .clear
        cap.position = CGPoint(x: c1.x, y: c1.y + 2); cap.zPosition = 0.5
        netsNode.addChild(cap)
    }
    /// Team colour index of a seat (Android `teams?.seats?.get(s) ?: s`).
    private func colorIndex(_ seat: Int) -> Int {
        if let teams = engine.teams, seat >= 0, seat < teams.seats.count { return teams.seats[seat] }
        return seat
    }

    // ---- frame loop ---------------------------------------------------------------------------------
    override func update(_ currentTime: TimeInterval) {
        bindSounds(force: false)
        let cameraElapsed = previousTime == 0 ? 0 : min(0.1, max(0, currentTime - previousTime))
        let elapsed = previousTime == 0 || !hasRendered ? 0 : min(0.10, max(0, currentTime - previousTime))
        previousTime = currentTime
        if !engine.networked {
            engine.reception.enabled = true
            if let local = engine.localSeat { engine.reception.slow[local] = preferences.receptionSlow }
        }
        // Keep real-time pace under rendering load; physics still receives small steps.
        var remaining = elapsed
        while remaining > 1e-9 {
            let slice = min(remaining, 1.0 / 60)
            if let step { step(slice) } else { engine.advance(slice) }
            remaining -= slice
        }
        follow(elapsed)
        let receiver = g.seats.contains(engine.reception.receiver) ? engine.reception.receiver : viewSeat
        let a = screen(engine.racket(receiver)), b = screen(engine.renderBallPosition, engine.ballHeight)
        receptionCamera.update(cameraElapsed, assist: engine.reception, local: viewSeat, focus: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2),
                      width: width, height: height, holding: activeTouch != nil, zoomOwn: preferences.receptionZoom, follow: preferences.receptionFollow)
        onFrame?()
        render()
    }
    /// The action camera follows the ball with a slight zoom; it freezes while a finger is down so a drag keeps its coordinates.
    private func follow(_ dt: Double) {
        guard actionView, width > 1, activeTouch == nil else { return }
        let v = g.toView(viewSeat, engine.renderBallPosition)
        let ease = 1 - exp(-dt / 0.55)
        let wanted = min(scaleLimit, fittedScale * (1 + 0.035 * (abs(v.y) / 1.4).mpClamp(0, 1)))
        let old = scale
        scale += (wanted - scale) * ease
        let margin = 12.0, board = scoreboardHeight
        let xLow = cx + tableMaxX * scale - (width - margin)
        let xHigh = cx + tableMinX * scale - margin
        let yLow = cy + tableMaxY * scale - (height - margin)
        let yHigh = cy + tableMinY * scale - (board + margin)
        func bounded(_ x: Double, _ lo: Double, _ hi: Double) -> Double { lo <= hi ? x.mpClamp(lo, hi) : (lo + hi) / 2 }
        let targetX = bounded(v.x * scale * 0.16, xLow, xHigh)
        let targetY = bounded(v.y * scale * 0.10, yLow, yHigh)
        pan += (targetX - pan) * ease; panY += (targetY - panY) * ease
        pan = bounded(pan, xLow, xHigh); panY = bounded(panY, yLow, yHigh)
        if abs(scale - old) > 0.005 { buildPaths() }
    }

    // ---- sounds -------------------------------------------------------------------------------------
    private func bindSounds(force: Bool) {
        guard playCue != nil else {
            if soundEngine != nil { soundEngine?.onEvent = nil; soundEngine = nil }
            return
        }
        if force || soundEngine !== engine {
            soundEngine?.onEvent = nil
            soundEngine = engine
            let policy = CrossSoundPolicy(localSeat: engine.localSeat)
            soundPolicy = policy
            engine.onEvent = { [weak self] event in
                guard let self, self.running, self.preferences.journeySound, let play = self.playCue else { return }
                for cue in policy.cues(event) { play(cue) }
            }
        }
    }

    // ---- drawing --------------------------------------------------------------------------------------
    private func render() {
        guard size.width > 1, size.height > 1 else { return }
        hasRendered = true
        // The pan, then the reception zoom about its focus (Android ReceptionCamera.begin).
        let z = receptionCamera.zoom, focus = sk(receptionCamera.focus), shift = receptionCamera.shift
        canvas.setScale(CGFloat(z))
        canvas.position = CGPoint(x: -pan * z + Double(focus.x) * (1 - z) + Double(shift.x), y: panY * z + Double(focus.y) * (1 - z) - Double(shift.y))
        bodyBounds = [:]; contactRackets = [:]
        let receiver = tutorialTarget ?? engine.predictedReceiver
        if let receiver, receiver >= 0, receiver < territoryPaths.count {
            highlightNode.isHidden = false; highlightNode.path = territoryPaths[receiver]
        } else { highlightNode.isHidden = true }
        if let bounce = engine.bouncePoint, engine.bounceAge < 0.38 {
            let q = sk(unpanned(bounce)), r = sizeAt(bounce) * (0.04 + engine.bounceAge * 0.10)
            bounceNode.isHidden = false
            bounceNode.path = CGPath(ellipseIn: CGRect(x: q.x - CGFloat(r), y: q.y - CGFloat(r), width: CGFloat(2 * r), height: CGFloat(2 * r)), transform: nil)
            bounceNode.alpha = CGFloat(1 - engine.bounceAge / 0.38) * 220 / 255
        } else { bounceNode.isHidden = true }
        renderPractice()
        // Back-to-front: farther players first, so nearer bodies overlap correctly; the local player last.
        let others = g.seats.filter { $0 != viewSeat }.sorted { screen(g.home($0)).y < screen(g.home($1)).y }
        for (order, seat) in others.enumerated() { renderPlayer(seat, depth: 2 + Double(order) * 0.1) }
        if let local = engine.localSeat { renderPlayer(local, depth: 3) } else { actors[viewSeat]?.hideAll() }
        renderBall()
        renderPaddle()
        renderTags()
        renderScoreboard()
    }
    /// Android drawPractice: paint cells, landed marks, the shape outline and its numbered circles, the golden targets.
    private var practiceSignature = ""
    private func renderPractice() {
        guard let p = practice else {
            if !practiceSignature.isEmpty { practiceNode.removeAllChildren(); practiceSignature = "" }
            return
        }
        // Rebuilt only when something drawn changes (the canvas transform moves it otherwise).
        let signature = "\(p.stage.id)|\(scale)|\(cx)|\(cy)|\(tilt)|\(p.paint.owners.hashValue)|\(p.marks.count)|\(p.painted.count)|\(p.attempts)|\(viewSeat)"
        if signature == practiceSignature { return }
        practiceSignature = signature
        practiceNode.removeAllChildren()
        func patch(_ at: MPPoint, _ radius: Double, _ color: UIColor) {
            let path = CGMutablePath()
            for i in 0...32 {
                let angle = Double(i) * 2 * Double.pi / 32
                let v = sk(unpanned(at + MPPoint(cos(angle) * radius, sin(angle) * radius)))
                if i == 0 { path.move(to: v) } else { path.addLine(to: v) }
            }
            path.closeSubpath()
            let node = SKShapeNode(path: path)
            node.fillColor = color; node.strokeColor = .clear
            practiceNode.addChild(node)
        }
        func argb(_ value: UInt32) -> UIColor {
            UIColor(red: CGFloat((value >> 16) & 0xff) / 255, green: CGFloat((value >> 8) & 0xff) / 255, blue: CGFloat(value & 0xff) / 255, alpha: CGFloat(value >> 24) / 255)
        }
        if p.stage.skill == .paint {
            let grid = p.paint, half = grid.span / Double(grid.size) / 2
            let ours = CGMutablePath(), theirs = CGMutablePath()
            for (i, owner) in grid.owners.enumerated() where owner >= 0 {
                let at = grid.point(i)
                let corners = [MPPoint(-half, -half), MPPoint(half, -half), MPPoint(half, half), MPPoint(-half, half)].map { sk(unpanned(at + $0)) }
                let target = owner == 0 ? ours : theirs
                target.addLines(between: corners); target.closeSubpath()
            }
            for (path, color) in [(ours, argb(0xb244e4ca)), (theirs, argb(0xb2ff8abb))] {
                let node = SKShapeNode(path: path)
                node.fillColor = color; node.strokeColor = .clear
                practiceNode.addChild(node)
            }
            return
        }
        p.marks.forEach { patch($0, 0.07, argb(0xb250ebd3)) }
        let targets = p.targets()
        if p.stage.skill == .shape {
            let outline = CGMutablePath()
            outline.addLines(between: targets.map { sk(unpanned($0)) }); outline.closeSubpath()
            let node = SKShapeNode(path: outline)
            node.strokeColor = argb(0xaac2f1ff); node.lineWidth = 2; node.fillColor = .clear
            practiceNode.addChild(node)
        }
        if p.stage.aimed {
            for (i, at) in targets.enumerated() {
                let done = p.painted.contains(i)
                let next = p.stage.skill != .shape || i == p.painted.count
                patch(at, p.radius, done ? argb(0xff46dfc2) : (next ? argb(0xffffd663) : argb(0x88b7eaff)))
                if p.stage.skill == .shape {
                    let label = SKLabelNode(fontNamed: CrossScene.font)
                    label.text = done ? "✓" : String(i + 1)
                    label.fontSize = 13; label.fontColor = UIColor(red: 20 / 255, green: 52 / 255, blue: 65 / 255, alpha: 1)
                    label.horizontalAlignmentMode = .center; label.verticalAlignmentMode = .baseline
                    let q = unpanned(at)
                    label.position = sk(CGPoint(x: q.x, y: q.y + 4))
                    practiceNode.addChild(label)
                }
            }
        }
    }
    /// Android drawPlayer (5c1aa4d): a whole authored pose standing outside the table, walking with its racket's sideways moves,
    /// winding up, meeting the ball and following through. The contact pose's racket defines where the feet stand; the paddle
    /// depth never moves a body onto the table. Facing players' upper bodies are in front of the raised tabletop.
    private func renderPlayer(_ seat: Int, depth: Double) {
        guard let nodes = actors[seat], seat < engine.seats.count else { return }
        nodes.setDepth(depth)
        nodes.hideAll()
        let info = engine.seats[seat]
        let botCharacter = info.bot?.characterId ?? ""
        let id = botCharacter.isEmpty ? info.characterId : botCharacter
        let atlas = MPXPoseAtlas.shared
        guard !id.isEmpty, atlas.has(id) else { return }
        let local = g.toLocal(seat, engine.racket(seat))
        let u = local.u.mpClamp(-0.48, 0.48)
        let view = g.toView(viewSeat, g.home(seat))
        let facing: MPXPoseAtlas.Facing = view.y > 0.45 ? .rear : (view.y < -0.45 ? .front : .side)
        let mirror = view.x > 0.45
        let actorHeight = scale * (id == "minik" ? 0.76 : 0.84)
        let stroke = engine.stroke(seat)
        let now = CACurrentMediaTime()
        let previous = lastLateral[seat] ?? u
        lastLateral[seat] = u
        if abs(u - previous) > 0.0015 { walkDistance[seat] = (walkDistance[seat] ?? 0) + abs(u - previous); lastStep[seat] = now }
        let walking = !stroke.active && now - (lastStep[seat] ?? 0) < 0.240
        let desired = Int((walkDistance[seat] ?? 0) / 0.11) % 4
        if now - (walkFrameAt[seat] ?? 0) >= 0.110 && walkFrame[seat] != desired { walkFrame[seat] = desired; walkFrameAt[seat] = now }
        let artId = walking && atlas.has(id + "-walk") ? id + "-walk" : id
        let contactPose = id == "minik" && facing == .front ? 2 : 0
        let phase: Int
        if walking { phase = walkFrame[seat] ?? 0 }
        else if !stroke.active { phase = 0 }
        else if stroke.age < stroke.contactAt - 0.04 { phase = id == "minik" && facing == .rear ? 0 : 1 }
        else if stroke.age <= stroke.contactAt + 0.075 { phase = contactPose }
        else if stroke.age < stroke.followEnd { phase = 3 }
        else { phase = 0 }
        guard let contact = atlas.geometry(id, facing, mirror: mirror, foot: .zero, height: actorHeight, phase: contactPose) else { return }
        let rest = unpanned(g.fromLocal(seat, u, CrossGeometry.homeDepth), 0.15)
        var foot = CGPoint(x: rest.x - contact.racket.x, y: rest.y - contact.racket.y)
        if let extent = atlas.geometry(artId, facing, mirror: mirror, foot: foot, height: actorHeight, phase: phase)?.bounds, !actionView {
            // Keep the whole body on screen in the fitted view.
            let edge = 4.0
            if Double(extent.minX) - pan < edge { foot.x += CGFloat(edge - (Double(extent.minX) - pan)) }
            if Double(extent.maxX) - pan > width - edge { foot.x -= CGFloat(Double(extent.maxX) - pan - (width - edge)) }
        }
        if let racket = atlas.geometry(id, facing, mirror: mirror, foot: foot, height: actorHeight, phase: contactPose)?.racket { contactRackets[seat] = racket }
        let shadow = CGRect(x: Double(foot.x) - actorHeight * 0.21, y: Double(foot.y) - actorHeight * 0.025, width: actorHeight * 0.42, height: actorHeight * 0.06)
        nodes.showShadow(CGPath(ellipseIn: CGRect(x: shadow.minX, y: height - shadow.maxY, width: shadow.width, height: shadow.height), transform: nil))
        let skPoint: (CGPoint) -> CGPoint = { [unowned self] p in self.sk(p) }
        let rendered = atlas.place(facing == .rear ? nodes.free : nodes.body, artId, facing, mirror: mirror, foot: foot, height: actorHeight, phase: phase, sk: skPoint)
        if let rendered { bodyBounds[seat] = rendered.bounds }
        // At the raised tabletop the intact upper body is in front of the surface; lower body and shoes stay behind it.
        if facing != .rear, let rendered {
            let line = Double(foot.y) - actorHeight * 0.48
            let above = CGRect(x: Double(rendered.bounds.minX), y: height - line, width: Double(rendered.bounds.width), height: max(0, line - Double(rendered.bounds.minY)))
            nodes.showUpper(tablePath.intersection(CGPath(rect: above, transform: nil)))
            atlas.place(nodes.upper, artId, facing, mirror: mirror, foot: foot, height: actorHeight, phase: phase, sk: skPoint)
        }
    }
    /// A short smooth contact arc joins the simulated flight to the authored paddle pose: drawing and touch only, never game time,
    /// score or network state.
    private func ballOffset() -> CGPoint {
        var best: (seat: Int, distance: Double)?
        for seat in g.seats where contactRackets[seat] != nil && engine.stroke(seat).active {
            let s = engine.stroke(seat), d = abs(s.age - s.contactAt)
            if best == nil || d < best!.distance { best = (seat, d) }
        }
        guard let chosen = best, chosen.distance < 0.16, let racket = contactRackets[chosen.seat] else { return .zero }
        let stroke = engine.stroke(chosen.seat)
        let weight = (1 + cos(Double.pi * chosen.distance / 0.16)) / 2
        let physics = unpanned(stroke.point, stroke.height)
        return CGPoint(x: Double(racket.x - physics.x) * weight, y: Double(racket.y - physics.y) * weight)
    }
    private func renderBall() {
        let state = engine.ballState
        let ground = engine.renderBallPosition
        let h = state.height
        let unit = sizeAt(ground)
        let radius = unit * CrossScene.ballSize * (1 + min(h, 0.4) * 0.35)
        let offset = ballOffset()
        let lifted = unpanned(ground, h)
        let s = sk(unpanned(ground)), b = sk(CGPoint(x: lifted.x + offset.x, y: lifted.y + offset.y))
        let raised = min(h, 1.5) / 1.5
        if g.onTable(ground) {
            ballShadow.isHidden = false
            ballShadow.position = CGPoint(x: s.x + CGFloat(radius * 0.15), y: s.y - CGFloat(radius * 0.2))
            ballShadow.xScale = CGFloat(radius * (1 + raised * 0.6)); ballShadow.yScale = CGFloat(radius * (0.5 + raised * 0.25))
            ballShadow.alpha = CGFloat(110 - 70 * raised) / 255 * 0.8
        } else { ballShadow.isHidden = true }
        if engine.netAge < 0.5 {
            netFlash.isHidden = false
            netFlash.position = b
            netFlash.setScale(CGFloat(radius * (1.5 + engine.netAge * 4)))
            netFlash.lineWidth = CGFloat(2.5 / max(0.5, radius * (1.5 + engine.netAge * 4)))
            netFlash.alpha = CGFloat(1 - engine.netAge / 0.5) * 240 / 255
        } else { netFlash.isHidden = true }
        ballNode.position = b; ballNode.setScale(CGFloat(max(0.5, radius)))
        ballNode.lineWidth = CGFloat(0.8 / max(0.5, radius))
        ballShine.position = CGPoint(x: b.x - CGFloat(radius * 0.3), y: b.y + CGFloat(radius * 0.35)); ballShine.setScale(CGFloat(max(0.2, radius * 0.35)))
        // A ball outside the visible area gets a small edge arrow pointing to it.
        let onScreen = screen(ground, h)
        let inset = 14.0
        let bx = Double(onScreen.x), by = Double(onScreen.y)
        if bx < 0 || bx > width || by < 0 || by > height {
            let ex = bx.mpClamp(inset, width - inset), ey = by.mpClamp(inset, height - inset)
            let angle = atan2(by - ey, bx - ex)
            arrowNode.isHidden = false
            arrowNode.position = sk(CGPoint(x: ex, y: ey))
            arrowNode.zRotation = CGFloat(-angle)
        } else { arrowNode.isHidden = true }
    }
    /// Android drawRacket: handle, dark rim and red face, drawn at the engine's contact centre.
    private func buildPaddle() {
        let handle = SKShapeNode(rect: CGRect(x: -0.23, y: -1.65, width: 0.46, height: 1.1), cornerRadius: 0.16)
        handle.fillColor = UIColor(red: 232 / 255, green: 181 / 255, blue: 113 / 255, alpha: 1); handle.strokeColor = .clear
        let rim = SKShapeNode(ellipseIn: CGRect(x: -1.06, y: -1.2, width: 2.12, height: 2.4))
        rim.fillColor = UIColor(red: 51 / 255, green: 32 / 255, blue: 38 / 255, alpha: 1); rim.strokeColor = .clear
        let face = SKShapeNode(ellipseIn: CGRect(x: -1, y: -1.12, width: 2, height: 2.24))
        face.fillColor = UIColor(red: 224 / 255, green: 44 / 255, blue: 74 / 255, alpha: 1)
        face.strokeColor = UIColor(red: 1, green: 213 / 255, blue: 157 / 255, alpha: 1); face.lineWidth = 0.08
        for node in [handle, rim, face] { paddleNode.addChild(node) }
    }
    private func renderPaddle() {
        // The local player's own character holds the paddle; only a player without one sees the bare paddle.
        guard let local = engine.localSeat, engine.seats[local].characterId.trimmingCharacters(in: .whitespaces).isEmpty else { paddleNode.isHidden = true; return }
        let stroke = engine.stroke(local)
        let at = engine.paddle ?? engine.restingPaddle
        let contact = stroke.active && stroke.contacted && stroke.age < stroke.contactAt + 0.07
        let p = contact ? stroke.point : at
        paddleNode.isHidden = false
        paddleNode.position = sk(unpanned(p, contact ? stroke.height : 0))
        paddleNode.setScale(CGFloat(max(1, sizeAt(p) * 0.09)))
        let degrees = UIAccessibility.isReduceMotionEnabled ? 0 : engine.paddleTilt + stroke.angle
        paddleNode.zRotation = CGFloat(-degrees * Double.pi / 180)
    }
    private func seatColor(_ seat: Int, alpha: Double) -> UIColor {
        let c = CrossScene.seatColors[colorIndex(seat) % CrossScene.seatColors.count]
        return UIColor(red: CGFloat(c.0 / 255), green: CGFloat(c.1 / 255), blue: CGFloat(c.2 / 255), alpha: CGFloat(alpha / 255))
    }
    /// Base view point (pan included) → painted view point (reception zoom).
    private func painted(_ unpannedPoint: CGPoint) -> CGPoint {
        receptionCamera.painted(CGPoint(x: Double(unpannedPoint.x) - pan, y: Double(unpannedPoint.y) - panY))
    }
    /// Name (and, individually, score) next to every player, with a server marker and floating +1/−1 notes. The badges sit above
    /// the drawn heads; a side player on the right has it below, a far head near the score strip has it beside.
    private func renderTags() {
        let now = CACurrentMediaTime()
        let ref = engine.referee
        let minimumY = scoreboardHeight + 26
        for s in g.seats {
            guard let tag = tags[s] else { continue }
            var at: CGPoint
            let homeView = g.toView(viewSeat, g.home(s))
            if s == viewSeat {
                if let box = bodyBounds[s] { at = painted(CGPoint(x: box.midX, y: box.minY - 12)) } else { at = CGPoint(x: width / 2, y: height - 9) }
            } else if let box = bodyBounds[s] {
                at = painted(CGPoint(x: box.midX, y: homeView.x > 0.5 ? box.maxY + 24 : box.minY - 12))
            } else {
                let lateral = g.toLocal(s, engine.racket(s)).u.mpClamp(-0.75, 0.75)
                at = painted(unpanned(g.fromLocal(s, lateral, CrossGeometry.reach + CrossScene.stand)))
            }
            let serving = ref.server == s && ref.phase == .awaitingServe
            let label = (serving ? "🏓 " : "") + (s < names.count ? names[s] : "") + (engine.teams == nil ? "  " + String(ref.score(s)) : "")
            tag.label.text = label
            tag.label.fontSize = 13.5
            let boxWidth = Double(tag.label.frame.width) + 16
            var badge = at
            if homeView.y < -0.45, Double(at.y) < minimumY, let box = bodyBounds[s] {
                badge = painted(CGPoint(x: Double(box.minX) - boxWidth / 2 - 10, y: Double(box.minY) + 22))
            }
            let x = Double(badge.x).mpClamp(boxWidth / 2 + 2, max(boxWidth / 2 + 2, width - boxWidth / 2 - 2))
            let y = Double(badge.y).mpClamp(minimumY, max(minimumY, height - 12))
            let box = CGRect(x: x - boxWidth / 2, y: height - (y + 6), width: boxWidth, height: 21)
            tag.box.path = CrossScene.rounded(box, 10)
            tag.box.fillColor = seatColor(s, alpha: 245)
            let highlight = (tutorialTarget ?? engine.predictedReceiver) == s
            tag.outline.isHidden = !highlight
            tag.outline.path = tag.box.path
            tag.label.position = CGPoint(x: x, y: height - y)
            // Beginner/Standard: who a return would go to now, following the latest sideways swipe.
            if engine.aimTarget == s {
                tag.aim.isHidden = false
                tag.aim.position = CGPoint(x: x, y: height - (y - 20))
                tag.aim.alpha = CGFloat((170 + 85 * sin(now * 1000 / 160)).mpClamp(0, 255) / 255)
            } else { tag.aim.isHidden = true }
            if let note = notes[s] {
                let age = (now - note.at) / 1.6
                if age >= 1 { notes[s] = nil; tag.note.isHidden = true }
                else {
                    tag.note.isHidden = false
                    tag.note.text = note.text
                    tag.note.fontColor = note.text.hasPrefix("+") ? UIColor(red: 140 / 255, green: 1, blue: 160 / 255, alpha: 1)
                        : (note.text.hasPrefix("−") ? UIColor(red: 1, green: 140 / 255, blue: 140 / 255, alpha: 1) : .white)
                    tag.note.alpha = CGFloat(1 - age)
                    tag.note.position = CGPoint(x: x, y: height - (y - 22 - age * 26))
                }
            } else { tag.note.isHidden = true }
        }
    }
    /// Every participant's score in one readable row above the table, the server marked; teams share one box per team.
    private func renderScoreboard() {
        if let teams = engine.teams { renderTeamScoreboard(teams); return }
        let ref = engine.referee
        let order = g.seats.map { g.wrap(viewSeat + $0) }
        let gap = 6.0, top = 6.0, h = scoreboardHeight - 12
        let w = (width - gap * Double(order.count + 1)) / Double(max(1, order.count))
        for (i, s) in order.enumerated() {
            guard let board = boards[s] else { continue }
            board.box.isHidden = false; board.name.isHidden = false; board.score.isHidden = false
            let x = gap + Double(i) * (w + gap)
            let rect = CGRect(x: x, y: height - (top + h), width: max(1, w), height: h)
            board.box.path = CrossScene.rounded(rect, 14)
            let c = CrossScene.seatColors[colorIndex(s) % CrossScene.seatColors.count]
            board.box.fillColor = UIColor(red: CGFloat((c.0 / 2 + 15) / 255), green: CGFloat((c.1 / 2 + 15) / 255), blue: CGFloat((c.2 / 2 + 25) / 255), alpha: 225 / 255)
            board.outline.isHidden = !(ref.winner == s || (tutorialTarget ?? engine.predictedReceiver) == s)
            board.outline.path = board.box.path
            let name = s < names.count ? names[s] : ""
            let shown = name.count > 10 ? String(name.prefix(9)) + "…" : name
            board.name.text = (ref.server == s ? "🏓 " : "") + shown
            board.name.fontSize = 13
            board.name.position = CGPoint(x: x + w / 2, y: height - (top + h * 0.36))
            board.score.text = String(ref.score(s))
            board.score.fontSize = width > height ? 19 : 25
            board.score.position = CGPoint(x: x + w / 2, y: height - (top + h * 0.86))
        }
    }
    private func renderTeamScoreboard(_ teams: CrossTeams) {
        let mine = teams.seats[min(viewSeat, teams.seats.count - 1)]
        var ids = [mine]
        for id in teams.seats where !ids.contains(id) { ids.append(id) }
        let gap = 6.0, h = scoreboardHeight - 12
        let w = (width - gap * Double(ids.count + 1)) / Double(ids.count)
        let hebrew = MPText.language == "he"
        for (s, board) in boards {
            let index = ids.firstIndex(of: teams.seats[min(s, teams.seats.count - 1)]) ?? 0
            let members = g.seats.filter { teams.seats[$0] == ids[index] }
            // One box per team, drawn by its first seat.
            guard members.first == s else { board.box.isHidden = true; board.outline.isHidden = true; board.name.isHidden = true; board.score.isHidden = true; continue }
            board.box.isHidden = false; board.name.isHidden = false; board.score.isHidden = false; board.outline.isHidden = true
            let x = gap + Double(index) * (w + gap), y = 6.0
            board.box.path = CrossScene.rounded(CGRect(x: x, y: height - (y + h), width: max(1, w), height: h), 12)
            let c = CrossScene.seatColors[ids[index] % CrossScene.seatColors.count]
            board.box.fillColor = UIColor(red: CGFloat(c.0 / 255), green: CGFloat(c.1 / 255), blue: CGFloat(c.2 / 255), alpha: 1)
            let title = members.map { $0 < names.count ? names[$0] : engine.seats[$0].name }.joined(separator: hebrew ? " ו־" : " and ")
            board.name.text = title
            var font = 13.0
            board.name.fontSize = CGFloat(font)
            while Double(board.name.frame.width) > w - 12 && font > 10 { font -= 0.5; board.name.fontSize = CGFloat(font) }
            board.name.position = CGPoint(x: x + w / 2, y: height - (y + h * 0.34))
            board.score.text = String(engine.referee.score(members[0]))
            board.score.fontSize = width > height ? 19 : 25
            board.score.position = CGPoint(x: x + w / 2, y: height - (y + h * 0.88))
        }
    }
    /// A rounded rectangle whose corner radius always fits (CGPath requires it).
    private static func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
        guard rect.width > 0, rect.height > 0 else { return CGMutablePath() }
        let r = min(radius, rect.width / 2 - 0.01, rect.height / 2 - 0.01)
        guard r > 0 else { return CGPath(rect: rect, transform: nil) }
        return CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
    }
    /// A gradient fill texture (Android LinearGradient), from the first colour to the last.
    private static func gradient(_ colors: [(Double, Double, Double)], vertical: Bool) -> SKTexture {
        let size = vertical ? CGSize(width: 4, height: 256) : CGSize(width: 256, height: 4)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let cg = colors.map { UIColor(red: CGFloat($0.0 / 255), green: CGFloat($0.1 / 255), blue: CGFloat($0.2 / 255), alpha: 1).cgColor } as CFArray
            guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cg, locations: nil) else { return }
            context.cgContext.drawLinearGradient(g, start: .zero, end: vertical ? CGPoint(x: 0, y: size.height) : CGPoint(x: size.width, y: 0), options: [])
        }
        return SKTexture(image: image)
    }
    /// The narrow sunset sheen across the table (transparent → warm 70/255 at 68 % → transparent).
    private static func sheenTexture() -> SKTexture {
        let size = CGSize(width: 256, height: 4)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let warm = UIColor(red: 1, green: 240 / 255, blue: 174 / 255, alpha: 70 / 255).cgColor, clear = UIColor(red: 1, green: 240 / 255, blue: 174 / 255, alpha: 0).cgColor
            guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [clear, warm, clear] as CFArray, locations: [0, 0.68, 1]) else { return }
            context.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: size.width, y: 0), options: [])
        }
        return SKTexture(image: image)
    }
    /// Show the score change of a resolved rally next to every affected player (individual play only).
    func showOutcome(_ outcome: CrossRallyOutcome) {
        if engine.teams != nil { return }
        let now = CACurrentMediaTime()
        for s in g.seats {
            let d = s < outcome.deltas.count ? outcome.deltas[s] : 0
            if d > 0 { notes[s] = ("+\(d)", now) }
            else if d < 0 { notes[s] = ("−\(-d)", now) }
            else if outcome.faultOwner == s || (outcome.kind == .missed && outcome.receiver == s) { notes[s] = ("0", now) }
        }
    }

    // ---- input --------------------------------------------------------------------------------------
    /// The touch in base view coordinates: the reception zoom is undone, as Android transforms the MotionEvent.
    private func viewPoint(_ touch: UITouch) -> CGPoint {
        let p = touch.location(in: self)
        return receptionCamera.base(CGPoint(x: p.x, y: size.height - p.y))
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard acceptsInput, activeTouch == nil, let touch = touches.first else { return }
        activeTouch = touch
        let p = viewPoint(touch)
        downPoint = p
        samples = [(touch.timestamp, p)]
        // Team play: a second quick tap near the first arms one raised pass to the teammate.
        raisedTap = false
        if engine.teams != nil {
            let gap = touch.timestamp - lastTapAt
            raisedTap = gap > 0.001 && gap <= 0.280 && hypot(p.x - lastTapPoint.x, p.y - lastTapPoint.y) < 56 && engine.liftToTeammate()
        }
        send(p, down: !raisedTap)
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard acceptsInput, let touch = activeTouch, touches.contains(touch) else { return }
        for sample in event?.coalescedTouches(for: touch) ?? [touch] {
            let p = viewPoint(sample)
            samples.append((sample.timestamp, p))
            send(p, down: false)
        }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        if acceptsInput {
            let p = viewPoint(touch)
            samples.append((touch.timestamp, p))
            if hypot(p.x - downPoint.x, p.y - downPoint.y) < 12 { lastTapAt = raisedTap ? -1000 : touch.timestamp; lastTapPoint = p }
            else { lastTapAt = -1000 }
            send(p, down: false)
            engine.endTouch(cancelled: false)
        }
        activeTouch = nil; samples = []
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { cancelTouch() }
    func cancelTouch() {
        if activeTouch != nil { engine.release() }
        activeTouch = nil; samples = []
    }
    /// Android VelocityTracker: the finger's speed over the last few samples, in points per second.
    private func fingerVelocity() -> CGVector {
        guard let last = samples.last else { return .zero }
        samples = samples.filter { last.time - $0.time <= 0.08 }
        guard let first = samples.first, last.time - first.time > 0.004 else { return .zero }
        let dt = CGFloat(last.time - first.time)
        return CGVector(dx: (last.point.x - first.point.x) / dt, dy: (last.point.y - first.point.y) / dt)
    }
    private func send(_ p: CGPoint, down: Bool) {
        // A finger on the drawn ball means the simulated ball (the contact arc only moves the picture).
        let rawBall = screen(engine.renderBallPosition, engine.ballState.height)
        let offset = ballOffset()
        let touchingBall = engine.predictedReceiver == engine.localSeat &&
            hypot(Double(p.x - rawBall.x - offset.x), Double(p.y - rawBall.y - offset.y)) < max(44, scale * 0.16)
        let point = touchingBall ? world(Double(p.x - offset.x), Double(p.y - offset.y)) : world(Double(p.x), Double(p.y))
        let here = g.toView(viewSeat, point)
        let unit = max(1, scale * k(here.y))
        let finger = fingerVelocity()
        let velocity = MPPoint(Double(finger.dx) / unit, Double(finger.dy) / (unit * tilt))
        let drag = MPPoint(Double(p.x - downPoint.x), Double(p.y - downPoint.y))
        engine.touch(point, drag: drag, velocity: velocity, down: down)
    }
}

/// One player's sprites: a floor shadow and the body clipped to the space outside the table, the upper body over the tabletop
/// (facing players) and an unclipped body (the local player seen from behind).
private final class CrossActorNodes {
    let crop = SKCropNode(), mask = SKShapeNode()
    let shadowCrop = SKCropNode(), shadowMask = SKShapeNode(), shadow = SKShapeNode()
    let body = SKSpriteNode(), free = SKSpriteNode()
    let upperCrop = SKCropNode(), upperMask = SKShapeNode(), upper = SKSpriteNode()
    init(parent: SKNode) {
        for m in [mask, shadowMask, upperMask] { m.fillColor = .white; m.strokeColor = .clear; m.lineWidth = 0 }
        crop.maskNode = mask; crop.addChild(body)
        shadowCrop.maskNode = shadowMask; shadowCrop.addChild(shadow)
        shadow.fillColor = UIColor(red: 13 / 255, green: 29 / 255, blue: 38 / 255, alpha: 65 / 255); shadow.strokeColor = .clear
        upperCrop.maskNode = upperMask; upperCrop.addChild(upper)
        parent.addChild(shadowCrop); parent.addChild(crop); parent.addChild(upperCrop); parent.addChild(free)
    }
    func setMask(_ path: CGPath) { mask.path = path; shadowMask.path = path }
    func setDepth(_ z: Double) {
        shadowCrop.zPosition = CGFloat(z); crop.zPosition = CGFloat(z + 0.01); upperCrop.zPosition = CGFloat(z + 0.02); free.zPosition = CGFloat(z + 0.03)
    }
    func hideAll() { shadow.isHidden = true; body.isHidden = true; free.isHidden = true; upperCrop.isHidden = true }
    func showShadow(_ path: CGPath) { shadow.isHidden = false; shadow.path = path }
    func showUpper(_ path: CGPath) { upperCrop.isHidden = false; upperMask.path = path }
    func remove() { [shadowCrop, crop, upperCrop, free].forEach { $0.removeFromParent() } }
}

/// A player's name tag: box, highlight outline, label, the 🎯 aim marker and the floating score note.
private final class CrossTagNodes {
    let box = SKShapeNode(), outline = SKShapeNode()
    let label: SKLabelNode, aim: SKLabelNode, note: SKLabelNode
    init(parent: SKNode, font: String) {
        label = SKLabelNode(fontNamed: font); aim = SKLabelNode(text: "🎯"); note = SKLabelNode(fontNamed: font)
        box.strokeColor = .clear; box.zPosition = 0
        outline.fillColor = .clear; outline.strokeColor = UIColor(red: 1, green: 221 / 255, blue: 87 / 255, alpha: 1); outline.lineWidth = 2.2; outline.zPosition = 0.1
        label.fontColor = .white; label.horizontalAlignmentMode = .center; label.verticalAlignmentMode = .baseline; label.zPosition = 0.2
        aim.fontSize = 20; aim.horizontalAlignmentMode = .center; aim.verticalAlignmentMode = .baseline; aim.zPosition = 0.3
        note.fontSize = 22; note.horizontalAlignmentMode = .center; note.verticalAlignmentMode = .baseline; note.zPosition = 0.4
        for node in [box, outline] { parent.addChild(node) }
        for node in [label, aim, note] { parent.addChild(node) }
    }
    func remove() { [box, outline].forEach { $0.removeFromParent() }; [label, aim, note].forEach { $0.removeFromParent() } }
}

/// One scoreboard box: background, highlight outline, name and score.
private final class CrossBoardNodes {
    let box = SKShapeNode(), outline = SKShapeNode()
    let name: SKLabelNode, score: SKLabelNode
    init(parent: SKNode, font: String) {
        name = SKLabelNode(fontNamed: font); score = SKLabelNode(fontNamed: font)
        box.strokeColor = .clear; box.zPosition = 0
        outline.fillColor = .clear; outline.strokeColor = UIColor(red: 1, green: 221 / 255, blue: 87 / 255, alpha: 1); outline.lineWidth = 2.5; outline.zPosition = 0.1
        for label in [name, score] {
            label.fontColor = .white; label.horizontalAlignmentMode = .center; label.verticalAlignmentMode = .baseline; label.zPosition = 0.2
        }
        for node in [box, outline] { parent.addChild(node) }
        for node in [name, score] { parent.addChild(node) }
    }
    func remove() { [box, outline].forEach { $0.removeFromParent() }; [name, score].forEach { $0.removeFromParent() } }
}
