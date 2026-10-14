import SpriteKit
import UIKit

final class MPScene: SKScene {
    var engine: MPEngine
    var onFrame: (([MPEvent]) -> Void)?
    var remoteCharacter: String?
    var remoteIcon = "🐱"
    var guidePoint: MPPoint?
    var guideDirection: Double?
    private var previousTime: TimeInterval = 0, accumulator = 0.0
    private var activeTouch: UITouch?, previousTouch: MPPoint?, previousTouchTime = 0.0
    private var arenaOrigin = CGPoint.zero, worldScale = 1.0
    /// Android LocalizedActivity's illustrated setting: modern_surround fills the whole screen behind the court.
    private let backdropNode = SKSpriteNode()
    private let floorNode = SKSpriteNode(), actorNode = SKSpriteNode(), paddleNode = SKSpriteNode()
    /// Android ModernCourt: Minik's FOLLOW pose drawn under READY while the recovery cross-fades.
    private let recoveryNode = SKSpriteNode()
    private let actorCrop = SKCropNode(), actorMask = SKShapeNode(), bodyCrop = SKCropNode(), bodyMask = SKShapeNode(), bodyNode = SKSpriteNode()
    private let frontCrop = SKCropNode(), frontMask = SKShapeNode(), armCrop = SKCropNode(), armMask = SKShapeNode(), armNode = SKSpriteNode()
    private let ballNode = SKShapeNode(circleOfRadius: 1), shadowNode = SKShapeNode(ellipseOf: CGSize(width: 2, height: 1))
    private let bounceNode = SKShapeNode(), guideNode = SKShapeNode(), iconNode = SKLabelNode()
    /// Owner report 2026-10: red rings where a short or double bounce landed, and around a ball that hit the
    /// net (Android ModernCourt), so the reason for a point is visible on the table.
    private let faultNode = SKShapeNode(), netNode = SKShapeNode()
    private var textures: [String: SKTexture] = [:]
    /// Android ModernCourt.receptionCamera (2026-10): an optional zoom toward the receiver. The backdrop is a child of
    /// the camera so the illustrated setting stays still while the court zooms.
    private let cameraNode = SKCameraNode()
    private var receptionCamera = MPReceptionCamera()
    init(engine: MPEngine) {
        self.engine = engine
        super.init(size: CGSize(width: 430, height: 760))
        scaleMode = .resizeFill; backgroundColor = UIColor(red: 0.92, green: 0.68, blue: 0.45, alpha: 1)
        backdropNode.texture = texture("modern_surround"); backdropNode.zPosition = -1
        // Android ModernCourt fades the arena's decorative outer floor into that setting; the fade is baked into this texture.
        floorNode.anchorPoint = CGPoint(x: 0, y: 1); floorNode.texture = texture("ping_pong_arena_faded")
        floorNode.zPosition = 0; actorNode.zPosition = 1; bounceNode.zPosition = 2; shadowNode.zPosition = 3; paddleNode.zPosition = 4; ballNode.zPosition = 5; guideNode.zPosition = 6; iconNode.zPosition = 2
        ballNode.fillColor = .white; ballNode.strokeColor = .lightGray; ballNode.lineWidth = 0.8
        shadowNode.fillColor = .black; shadowNode.strokeColor = .clear; shadowNode.alpha = 0.22
        bounceNode.fillColor = .clear; bounceNode.strokeColor = .white; bounceNode.lineWidth = 2
        guideNode.fillColor = .clear; guideNode.strokeColor = .yellow; guideNode.lineWidth = 4
        let faultRed = UIColor(red: 1, green: 84 / 255, blue: 84 / 255, alpha: 1)
        faultNode.fillColor = .clear; faultNode.strokeColor = faultRed; faultNode.lineWidth = 4; faultNode.zPosition = 2.5; faultNode.isHidden = true
        netNode.fillColor = .clear; netNode.strokeColor = faultRed; netNode.lineWidth = 3; netNode.zPosition = 5.5; netNode.isHidden = true
        iconNode.fontSize = 38
        actorCrop.maskNode = actorMask; actorCrop.addChild(recoveryNode); actorCrop.addChild(actorNode); actorCrop.zPosition = 1
        recoveryNode.zPosition = 0.9; recoveryNode.isHidden = true
        bodyCrop.maskNode = bodyMask; bodyCrop.addChild(bodyNode); bodyCrop.zPosition = 0.8
        frontCrop.maskNode = frontMask; frontCrop.addChild(armCrop); armCrop.maskNode = armMask; armCrop.addChild(armNode); frontCrop.zPosition = 1.2
        [actorMask, bodyMask, frontMask, armMask].forEach { $0.fillColor = .white; $0.strokeColor = .clear; $0.lineWidth = 0 }
        let nodes: [SKNode] = [floorNode, bodyCrop, actorCrop, frontCrop, bounceNode, faultNode, shadowNode, paddleNode, ballNode, netNode, guideNode, iconNode]
        nodes.forEach(addChild)
        cameraNode.addChild(backdropNode); addChild(cameraNode); camera = cameraNode
        cameraNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
    }
    required init?(coder: NSCoder) { return nil }
    override func didMove(to view: SKView) { view.isMultipleTouchEnabled = false; layoutCourt() }
    override func didChangeSize(_ oldSize: CGSize) { layoutCourt() }
    func setActive(_ active: Bool) { engine.paused = !active; isPaused = !active; previousTime = 0; accumulator = 0; if !active { cancelTouch() } }
    func replaceEngine(_ engine: MPEngine) { cancelTouch(); self.engine = engine; previousTime = 0; accumulator = 0; render() }
    private func texture(_ name: String) -> SKTexture {
        if let existing = textures[name] { return existing }
        let value = SKTexture(imageNamed: "mp_" + name); value.filteringMode = .linear; textures[name] = value; return value
    }
    private func layoutCourt() {
        let scale = min((Double(size.width) - 16) / MPProjection.tableWidth, (Double(size.height) - 32) / (340 + 1437))
        worldScale = max(scale, 0.01)
        // Cover the whole scene, as Android's full-screen setting does, keeping the art's proportions.
        let cover = max(Double(size.width) / 841, Double(size.height) / 1870)
        backdropNode.size = CGSize(width: 841 * cover, height: 1870 * cover)
        backdropNode.position = .zero
        placeCamera()
        arenaOrigin = CGPoint(x: (Double(size.width) - 941 * worldScale) / 2, y: 1437 * worldScale + 24)
        floorNode.position = arenaOrigin; floorNode.size = CGSize(width: 941 * worldScale, height: 1672 * worldScale)
        render()
    }
    private func screen(_ p: MPPoint, height: Double = 0) -> CGPoint {
        let image = MPProjection.ball(p, height)
        return CGPoint(x: arenaOrigin.x + image.x * worldScale, y: arenaOrigin.y - image.y * worldScale)
    }
    private func table(_ point: CGPoint) -> MPPoint {
        let h = engine.level.pro ? max(engine.flight?.height ?? 0, 0) : 0
        return .init((point.x - arenaOrigin.x - MPProjection.left * worldScale) / (MPProjection.tableWidth * worldScale),
            MPProjection.tableY((arenaOrigin.y - point.y) / worldScale + h * (MPProjection.bottom - MPProjection.top) * 0.075))
    }
    override func update(_ currentTime: TimeInterval) {
        let raw = previousTime == 0 ? 0 : max(0, currentTime - previousTime)
        let elapsed = min(1.0 / 30, raw); previousTime = currentTime
        // Android ModernCourt.doFrame: a local match always offers this player's own slow-motion choice; online the
        // match link sets the shared clock.
        if !engine.networked { engine.reception.enabled = true; engine.reception.slow[0] = MPReceptionSettings.slow }
        accumulator += elapsed
        while accumulator >= 1.0 / 120 { engine.advance(1.0 / 120); accumulator -= 1.0 / 120 }
        updateCamera(min(raw, 0.1))
        onFrame?(engine.drainEvents()); render()
    }
    /// Android ModernCourt: the camera centres between the receiving paddle (or the far server) and the ball.
    private func updateCamera(_ dt: Double) {
        let at = engine.reception.receiver == 1 ? MPPoint(0.5, 0.13) : (engine.paddle ?? engine.restingPaddle)
        let a = screen(at), b = screen(engine.renderedBall, height: engine.renderedHeight)
        let focus = CGPoint(x: (a.x + b.x) / 2, y: size.height - (a.y + b.y) / 2)
        receptionCamera.update(dt, assist: engine.reception, local: 0, focus: focus, size: size, holding: activeTouch != nil, reduceMotion: UIAccessibility.isReduceMotionEnabled)
        placeCamera()
    }
    /// The view centre in the court's top-left coordinates, converted to the scene's y-up coordinates.
    private func placeCamera() {
        let c = receptionCamera, zoom = max(c.zoom, 0.01)
        let centre = CGPoint(x: c.x + (size.width / 2 - c.x - c.tx) / zoom, y: c.y + (size.height / 2 - c.y - c.ty) / zoom)
        cameraNode.position = c.amount == 0 ? CGPoint(x: size.width / 2, y: size.height / 2) : CGPoint(x: centre.x, y: size.height - centre.y)
        cameraNode.setScale(1 / zoom)
    }
    private func render() {
        let p = engine.renderedBall, height = engine.renderedHeight
        let radius = MPProjection.tableWidth * worldScale * 0.017 * (1 + min(height, 0.4) * 0.55)
        ballNode.position = screen(p, height: height); ballNode.setScale(radius)
        shadowNode.position = screen(p); shadowNode.xScale = radius * (0.85 + min(height / 0.5, 1) * 0.6); shadowNode.yScale = radius * 0.6
        shadowNode.alpha = 0.3 - min(height / 0.5, 1) * 0.18
        if let bounce = engine.bouncePoint, engine.bounceAge < 0.38 {
            bounceNode.isHidden = false; bounceNode.position = screen(bounce)
            let r = MPProjection.tableWidth * worldScale * (0.035 + engine.bounceAge * 0.10)
            bounceNode.path = CGPath(ellipseIn: CGRect(x: -r, y: -r / 2, width: 2 * r, height: r), transform: nil)
            bounceNode.alpha = 1 - engine.bounceAge / 0.38
        } else { bounceNode.isHidden = true }
        if let mark = engine.faultMark, engine.faultAge < 3 {
            faultNode.isHidden = false; faultNode.position = screen(mark)
            let r = MPProjection.tableWidth * worldScale * (0.045 + 0.012 * sin(engine.faultAge * 8))
            faultNode.path = CGPath(ellipseIn: CGRect(x: -r, y: -r / 2, width: 2 * r, height: r), transform: nil)
        } else { faultNode.isHidden = true }
        if engine.netAge < 0.5 {
            netNode.isHidden = false; netNode.position = ballNode.position
            let r = radius * (1.5 + engine.netAge * 4)
            netNode.path = CGPath(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r), transform: nil)
            netNode.alpha = 1 - engine.netAge / 0.5
        } else { netNode.isHidden = true }
        let stroke = engine.childStroke
        let resting = engine.paddle ?? engine.restingPaddle
        // Android ModernCourt: the drawn paddle follows the player's position except for a brief impact frame.
        let atContact = stroke.active && stroke.contacted && stroke.age < stroke.contactAt + 0.07
        let position = atContact ? stroke.point : resting
        let left = stroke.active ? stroke.left : position.x < 0.5
        let levelName: String
        switch engine.level {
        case .beginner, .easy: levelName = "starter"
        case .medium: levelName = "easy"
        case .hard: levelName = "medium"
        case .superHard: levelName = "hard"
        }
        let name = levelName == "starter" ? "ping_pong_player_starter_paddle" : "ping_pong_player_" + levelName + (left ? "_backhand" : "_forehand")
        let image = texture(name), imageSize = image.size()
        paddleNode.texture = image
        let factor = min(MPProjection.tableWidth * worldScale * 0.31 / max(1, imageSize.width), (1437 - 186) * worldScale * 0.16 / max(1, imageSize.height))
        paddleNode.size = CGSize(width: imageSize.width * factor, height: imageSize.height * factor)
        paddleNode.anchorPoint = CGPoint(x: levelName == "starter" ? 0.5 : left ? 0.28 : 0.76, y: 0.72)
        paddleNode.position = screen(position, height: atContact ? stroke.height : engine.paddle != nil && engine.level.pro ? height : engine.restingHeight)
        paddleNode.isHidden = !(position.strikeZone || stroke.active)
        // Aiming a serve does not move the racket to the selected remote target.
        // Android rotates clockwise by (tilt + swing angle) degrees; SpriteKit's zRotation is counter-clockwise.
        paddleNode.zRotation = -(engine.paddleTilt + stroke.angle) * .pi / 180
        renderOpponent()
        guideNode.isHidden = guidePoint == nil
        if let point = guidePoint {
            guideNode.position = screen(point, height: height)
            let path = CGMutablePath()
            if let direction = guideDirection {
                let dx = 35 * direction; path.move(to: CGPoint(x: -dx / 2, y: -25)); path.addLine(to: CGPoint(x: dx, y: 25))
                path.addLine(to: CGPoint(x: dx - 12 * direction, y: 20)); path.move(to: CGPoint(x: dx, y: 25)); path.addLine(to: CGPoint(x: dx, y: 10))
            } else { path.addEllipse(in: CGRect(x: -22, y: -22, width: 44, height: 44)) }
            guideNode.path = path
        }
    }
    private func renderOpponent() {
        // Android ActorPresentation: keep the last swing's hand until a new swing starts, including
        // through recovery and footwork. Footwork translates the ready pose; there is no walk cycle.
        let motion = engine.motion, stroke = engine.minikStroke, facingLeft = stroke.left
        let edge = screen(.init(0, 0)).y
        bodyCrop.isHidden = true; frontCrop.isHidden = true; recoveryNode.isHidden = true; actorNode.alpha = 1
        actorMask.path = CGPath(rect: CGRect(x: 0, y: 0, width: size.width, height: size.height), transform: nil)
        let character = remoteCharacter ?? engine.bot?.characterId ?? "minik"
        if remoteCharacter == "" { actorNode.isHidden = true; iconNode.isHidden = false; iconNode.text = remoteIcon; iconNode.position = screen(.init(engine.ball.x.mpClamp(0.1, 0.9), 0.04)); return }
        actorNode.isHidden = false; iconNode.isHidden = true
        let phase: Int = stroke.active ? (stroke.age < 0.11 ? 2 : stroke.age < 0.20 ? 3 : stroke.age <= 0.27 ? 4 : stroke.age < 0.44 ? 5 : 0) : 0
        if character != "minik", MPRoster.find(character) != nil {
            let sheet = texture("bot_" + character)
            let cell = [0, 0, facingLeft ? 5 : 2, facingLeft ? 6 : 3, facingLeft ? 6 : 3, facingLeft ? 7 : 4][phase]
            let key = character + "/" + String(cell)
            let frame = textures[key] ?? SKTexture(rect: CGRect(x: Double(cell % 4) / 4, y: cell < 4 ? 0.5 : 0, width: 0.25, height: 0.5), in: sheet)
            textures[key] = frame; actorNode.texture = frame
            let imageHeight = min(540 * worldScale, max(1, (Double(size.height) - screen(.init(0, 0)).y - 8) / 0.86))
            let imageWidth = imageHeight * frame.size().width / max(1, frame.size().height)
            let face = MPArt.face(character, left: facingLeft)
            let contactPoint = screen(stroke.point, height: stroke.height)
            let contactX = contactPoint.x - face.x * imageWidth, contactY = contactPoint.y + face.y * imageHeight
            let restX = arenaOrigin.x + motion.body.x * worldScale - imageWidth * 0.5
            let restY = min(Double(size.height) - 8, max(screen(.init(0, 0)).y + imageHeight * 0.72, arenaOrigin.y - motion.body.y * worldScale + imageHeight * 0.65))
            let blend = !stroke.active ? 0 : stroke.age <= 0.27 ? (stroke.age / 0.20).mpClamp(0, 1) : ((stroke.total - stroke.age) / (stroke.total - 0.27)).mpClamp(0, 1)
            let lean = blend * blend * (3 - 2 * blend)
            actorNode.anchorPoint = CGPoint(x: 0, y: 1); actorNode.size = CGSize(width: imageWidth, height: imageHeight)
            actorNode.position = CGPoint(x: restX + (contactX - restX) * lean, y: restY + (contactY - restY) * lean)
            actorMask.path = CGPath(rect: CGRect(x: 0, y: edge, width: size.width, height: max(0, size.height - edge)), transform: nil)
            if phase == 3 || phase == 4 {
                frontCrop.isHidden = false; frontMask.path = CGPath(rect: CGRect(x: 0, y: 0, width: size.width, height: max(0, edge)), transform: nil)
                armNode.texture = actorNode.texture; armNode.size = actorNode.size; armNode.anchorPoint = actorNode.anchorPoint; armNode.position = actorNode.position
                let path = CGMutablePath(), x = actorNode.position.x, y = actorNode.position.y
                for (index, p) in MPArt.arm(character, left: facingLeft).enumerated() {
                    let point = CGPoint(x: x + p.x * imageWidth, y: y - p.y * imageHeight)
                    if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }; path.closeSubpath()
                let radius = MPArt.radius(character, left: facingLeft), grip = MPArt.grip(character, left: facingLeft)
                for (center, r) in [(face, radius), (grip, MPPoint(0.06, 0.065))] {
                    path.addEllipse(in: CGRect(x: x + (center.x - r.x) * imageWidth, y: y - (center.y + r.y) * imageHeight, width: 2 * r.x * imageWidth, height: 2 * r.y * imageHeight))
                }; armMask.path = path
            }
        } else {
            let names = ["ready", "ready", "windup", "accelerate", "contact", "follow"]
            let bodyPosition = CGPoint(x: arenaOrigin.x + motion.body.x * worldScale, y: arenaOrigin.y - motion.body.y * worldScale)
            func pose(_ node: SKSpriteNode, _ index: Int, alpha: Double) {
                node.texture = texture((facingLeft ? "minik_left_" : "minik_motion_") + names[index])
                let registration: (Double, Double, Double)
                if facingLeft { registration = index == 5 ? (0.507, 0.652, 0.994) : (0.5, 0.65, 1) }
                else if index == 5 { registration = (0.490, 0.729, 0.879) }
                else { registration = (0.5, 0.65, 1) }
                node.size = CGSize(width: 600 * worldScale * registration.2, height: 600 * worldScale * registration.2)
                node.anchorPoint = CGPoint(x: registration.0, y: 1 - registration.1)
                node.position = bodyPosition; node.alpha = CGFloat(alpha)
            }
            // Android ModernCourt/ActorPresentation.recoveryBlend: after the follow-through, FOLLOW fades into READY
            // over 0.16 s instead of snapping between the two drawings.
            let recovery = stroke.recoveryBlend
            if phase == 0 && recovery < 1 {
                recoveryNode.isHidden = false; pose(recoveryNode, 5, alpha: 1 - recovery); pose(actorNode, 0, alpha: recovery)
            } else { pose(actorNode, phase, alpha: 1) }
            bodyCrop.isHidden = false; bodyNode.texture = texture("minik_motion_body"); bodyNode.size = CGSize(width: 600 * worldScale, height: 600 * worldScale)
            bodyNode.anchorPoint = CGPoint(x: 0.5, y: 0.35); bodyNode.position = actorNode.position
            bodyMask.path = CGPath(rect: CGRect(x: 0, y: edge, width: size.width, height: max(0, actorNode.position.y + 40 * worldScale - edge)), transform: nil)
        }
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard activeTouch == nil, let touch = touches.first else { return }
        activeTouch = touch; let p = table(touch.location(in: self)); previousTouch = p; previousTouchTime = touch.timestamp
        engine.touch(p)
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        let samples = event?.coalescedTouches(for: touch) ?? [touch]
        for sample in samples {
            let p = table(sample.location(in: self)), old = previousTouch ?? p, dt = max(1.0 / 120, sample.timestamp - previousTouchTime)
            guard sample.timestamp > previousTouchTime, p.distance(old) > 0.00001 else { continue }
            engine.touch(p, movement: .init((p.x - old.x) / dt, (p.y - old.y) / dt), down: false)
            previousTouch = p; previousTouchTime = sample.timestamp
        }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { touchesMoved(touches, with: event); engine.endTouch(); activeTouch = nil; previousTouch = nil }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { cancelTouch() }
    private func cancelTouch() { engine.release(); activeTouch = nil; previousTouch = nil }
}
enum MPArt {
    private static func originalGrip(_ id: String, left: Bool) -> MPPoint {
        let values: [String: [Double]] = ["miniko": [0.278,0.532,0.742,0.520], "coach67": [0.245,0.553,0.760,0.630], "flare": [0.27,0.70,0.63,0.75], "kyra": [0.28,0.70,0.63,0.75], "gaya": [0.31,0.67,0.70,0.74], "mia": [0.265,0.688,0.71,0.75], "amber": [0.335,0.715,0.67,0.815], "comet": [0.265,0.684,0.69,0.81], "june": [0.225,0.64,0.71,0.79]]
        let p = values[id] ?? [0.28,0.718,0.57,0.70], i = left ? 0 : 2; return .init(p[i], p[i + 1])
    }
    private static func padded(_ p: MPPoint) -> MPPoint { .init((p.x * 384 + 32) / 448, p.y) }
    static func grip(_ id: String, left: Bool) -> MPPoint { padded(originalGrip(id, left: left)) }
    static func arm(_ id: String, left: Bool) -> [MPPoint] {
        let g = originalGrip(id, left: left)
        return (left ? [MPPoint(0.27,0.31), .init(0.49,0.33), .init(0.43,0.54), .init(g.x+0.06,g.y-0.035), .init(g.x+0.055,g.y+0.04), .init(g.x-0.055,g.y+0.035), .init(0.26,0.51)] : [MPPoint(0.27,0.30), .init(0.51,0.33), .init(0.54,0.58), .init(g.x+0.06,g.y-0.035), .init(g.x+0.055,g.y+0.04), .init(g.x-0.055,g.y+0.035), .init(0.38,0.54)]).map(padded)
    }
    static func radius(_ id: String, left: Bool) -> MPPoint {
        let p = id == "amber" ? MPPoint(0.105,0.08) : id == "kyra" ? .init(0.108,left ? 0.10 : 0.085) : id == "moshiko" ? .init(0.100,0.08) : .init(0.12,0.087)
        return .init(p.x * 384 / 448, p.y)
    }
    static func face(_ id: String, left: Bool) -> MPPoint {
        let values: [String: [Double]] = ["miniko": [0.176,0.563,0.875,0.528], "coach67": [0.115,0.565,0.867,0.682], "flare": [0.104,0.686,0.768,0.805], "kyra": [0.352,0.768,0.762,0.807], "gaya": [0.143,0.704,0.846,0.772], "mia": [0.122,0.684,0.856,0.767], "amber": [0.164,0.718,0.815,0.835], "comet": [0.075,0.720,0.835,0.862], "june": [0.110,0.713,0.828,0.814], "moshiko": [0.154,0.723,0.667,0.770]]
        let p = values[id] ?? [0.2,0.6,0.67,0.6], i = left ? 0 : 2
        return .init((p[i] * 384 + 32) / 448, p[i + 1])
    }
}
