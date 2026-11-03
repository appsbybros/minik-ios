import SpriteKit
import UIKit

final class MPScene: SKScene {
    var engine: MPEngine
    var onFrame: (([MPEvent]) -> Void)?
    var remoteCharacter: String?
    var remoteIcon = "🐱"
    var guidePoint: MPPoint?
    var guideDirection: Double?
    /// Ball assistance (Android `reception_assistance`): slow motion for this player's return and the reception zoom.
    var preferences = MPPreferences()
    private var receptionView = CrossReceptionCamera()
    private let cameraNode = SKCameraNode()
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
    private var textures: [String: SKTexture] = [:]
    /// Android 7254ab2 `localCharacterId`: the player's own avatar, drawn whole from behind in a classic one-on-one match.
    var localCharacterId = "miniko" { didSet { if localCharacterId != oldValue { playerFoot = nil; render() } } }
    /// Android `tutorial != null`: the guide keeps the paddle-only court.
    var tutorial = false { didSet { if tutorial != oldValue { layoutCourt() } } }
    private let atlas = MPXPoseAtlas.shared
    private var selectedLocalCharacter: String { MPRoster.find(localCharacterId)?.id ?? "miniko" }
    /// Android `showsLocalAvatar` (needs the bundled pose art).
    var showsLocalAvatar: Bool { !tutorial && atlas.has(selectedLocalCharacter) }
    /// The table's horizontal scale: wider than `worldScale` in landscape, where the projected table grows, not the players.
    private var horizontalScale = 1.0
    private var playerHeight = 0.0
    /// The avatar's foot in view coordinates (y down), eased toward the paddle.
    private var playerFoot: CGPoint?
    private var playerMirror = false, playerStrokeId = -1, observedContact = -1, contactAge = 10.0
    private let gait = MPGait()
    private let playerNode = SKSpriteNode(), playerShadow = SKShapeNode(), compactFrame = SKSpriteNode()
    private(set) var localPlayerGeometry: MPXPoseAtlas.Geometry?
    init(engine: MPEngine) {
        self.engine = engine
        super.init(size: CGSize(width: 430, height: 760))
        scaleMode = .resizeFill; backgroundColor = UIColor(red: 0.92, green: 0.68, blue: 0.45, alpha: 1)
        // Android 5c1aa4d: the evening terrace (SunsetTerrace) is the setting around the classic table too.
        backdropNode.texture = SKTexture(imageNamed: "mpx_sunset_portrait"); backdropNode.zPosition = -1
        // Android ModernCourt fades the arena's decorative outer floor into that setting; the fade is baked into this texture.
        floorNode.anchorPoint = CGPoint(x: 0, y: 1); floorNode.texture = texture("ping_pong_arena_faded")
        floorNode.zPosition = 0; actorNode.zPosition = 1; bounceNode.zPosition = 2; shadowNode.zPosition = 3; paddleNode.zPosition = 4; ballNode.zPosition = 5; guideNode.zPosition = 6; iconNode.zPosition = 2
        ballNode.fillColor = .white; ballNode.strokeColor = .lightGray; ballNode.lineWidth = 0.8
        shadowNode.fillColor = .black; shadowNode.strokeColor = .clear; shadowNode.alpha = 0.22
        bounceNode.fillColor = .clear; bounceNode.strokeColor = .white; bounceNode.lineWidth = 2
        guideNode.fillColor = .clear; guideNode.strokeColor = .yellow; guideNode.lineWidth = 4
        iconNode.fontSize = 38
        compactFrame.anchorPoint = CGPoint(x: 0, y: 1); compactFrame.zPosition = 0.5; compactFrame.isHidden = true
        playerShadow.fillColor = UIColor(red: 7 / 255, green: 28 / 255, blue: 39 / 255, alpha: 85 / 255); playerShadow.strokeColor = .clear
        playerShadow.zPosition = 3.5; playerShadow.isHidden = true; playerNode.zPosition = 4; playerNode.isHidden = true
        actorCrop.maskNode = actorMask; actorCrop.addChild(recoveryNode); actorCrop.addChild(actorNode); actorCrop.zPosition = 1
        recoveryNode.zPosition = 0.9; recoveryNode.isHidden = true
        bodyCrop.maskNode = bodyMask; bodyCrop.addChild(bodyNode); bodyCrop.zPosition = 0.8
        frontCrop.maskNode = frontMask; frontCrop.addChild(armCrop); armCrop.maskNode = armMask; armCrop.addChild(armNode); frontCrop.zPosition = 1.2
        [actorMask, bodyMask, frontMask, armMask].forEach { $0.fillColor = .white; $0.strokeColor = .clear; $0.lineWidth = 0 }
        let nodes: [SKNode] = [backdropNode, floorNode, compactFrame, bodyCrop, actorCrop, frontCrop, bounceNode, shadowNode, playerShadow, playerNode, paddleNode, ballNode, guideNode, iconNode]
        nodes.forEach(addChild)
        // Android ReceptionCamera: a camera that zooms toward the receiving paddle and the ball; touches map back through it.
        addChild(cameraNode); camera = cameraNode
    }
    required init?(coder: NSCoder) { return nil }
    override func didMove(to view: SKView) { view.isMultipleTouchEnabled = false; layoutCourt() }
    override func didChangeSize(_ oldSize: CGSize) { layoutCourt() }
    func setActive(_ active: Bool) { engine.paused = !active; isPaused = !active; previousTime = 0; accumulator = 0; if !active { cancelTouch() } }
    func replaceEngine(_ engine: MPEngine) { cancelTouch(); self.engine = engine; previousTime = 0; accumulator = 0; render() }
    private func texture(_ name: String) -> SKTexture {
        if let existing = textures[name] { return existing }
        // Multi Ping Pong keeps the Minik frames its Android twin (MinikCrossPong) ships; the shared catalog now holds
        // Ping Pong's newer drawings, so these come from the Multi-only mpx_ copies.
        let frozen = (name.hasPrefix("minik_left_") || name.hasPrefix("minik_motion_")) && name != "minik_motion_body"
        let value = SKTexture(imageNamed: (frozen ? "mpx_" : "mp_") + name); value.filteringMode = .linear; textures[name] = value; return value
    }
    /// Android 7254ab2 `ModernCourt.onSizeChanged`: the ordinary Pong full-avatar framing. Both feet and the table legs get real
    /// floor space; changing the view never changes match physics. The guide keeps the paddle-only framing.
    private func layoutCourt() {
        let w = Double(size.width), h = Double(size.height)
        guard w > 1, h > 1 else { return }
        let top: Double
        if showsLocalAvatar {
            let fitted = min((h - 24) / 2180, (w - 16) / 1120)
            worldScale = max(0.01, fitted * (w > h ? 1.08 : 1))
            horizontalScale = w > h ? min(worldScale * 1.85, (w - 32) / 941) : worldScale
            top = max(254 * worldScale, h - 24 - 1827 * worldScale)
        } else {
            worldScale = max(0.01, min((h - 24) / 1793, (w - 16) / MPProjection.tableWidth))
            horizontalScale = worldScale
            top = h - 24 - 1437 * worldScale
        }
        playerHeight = 550 * worldScale; playerFoot = nil
        // Cover the whole scene, top aligned, keeping the art's proportions (Android SunsetTerrace).
        let landscape = size.width > size.height
        let art = landscape ? (width: 1794.0, height: 877.0) : (width: 941.0, height: 1672.0)
        backdropNode.texture = SKTexture(imageNamed: landscape ? "mpx_sunset_landscape" : "mpx_sunset_portrait")
        let cover = max(Double(size.width) / art.width, Double(size.height) / art.height)
        backdropNode.size = CGSize(width: art.width * cover, height: art.height * cover)
        backdropNode.position = CGPoint(x: Double(size.width) / 2, y: Double(size.height) - art.height * cover / 2)
        placeCamera()
        arenaOrigin = CGPoint(x: (w - 941 * horizontalScale) / 2, y: h - top)
        floorNode.position = arenaOrigin; floorNode.size = CGSize(width: 941 * horizontalScale, height: 1672 * worldScale)
        renderCompactFrame()
        render()
    }
    /// A table point at a height, in scene coordinates (y up). The full avatar uses the near-side perspective.
    private func screen(_ p: MPPoint, height: Double = 0) -> CGPoint {
        let ground = showsLocalAvatar ? MPNearPlayerProjection.imageY(p.y) : MPProjection.imageY(p.y)
        let y = ground - max(0, height) * (MPProjection.bottom - MPProjection.top) * 0.075
        return CGPoint(x: arenaOrigin.x + (MPProjection.left + p.x * MPProjection.tableWidth) * horizontalScale, y: arenaOrigin.y - y * worldScale)
    }
    private func table(_ point: CGPoint) -> MPPoint {
        let h = engine.level.pro ? max(engine.flight?.height ?? 0, 0) : 0
        let image = (arenaOrigin.y - point.y) / worldScale + h * (MPProjection.bottom - MPProjection.top) * 0.075
        return .init((point.x - arenaOrigin.x - MPProjection.left * horizontalScale) / (MPProjection.tableWidth * horizontalScale),
                     showsLocalAvatar ? MPNearPlayerProjection.tableY(image) : MPProjection.tableY(image))
    }
    /// View coordinates (y down) ↔ scene coordinates (y up).
    private func flip(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: size.height - p.y) }
    /// Android `nearFloorY`: the floor 190 source pixels below the near table edge, in view coordinates.
    private var nearFloorY: CGFloat { flip(screen(MPPoint(0, 1))).y + 190 * worldScale }
    /// Android `drawCompactFrame`: the legs, the floor shadow and the near rail of the table under the full avatar.
    private func renderCompactFrame() {
        guard showsLocalAvatar else { compactFrame.isHidden = true; return }
        let scale = worldScale, drop = 190 * scale
        let tableTop = Double(size.height) - Double(arenaOrigin.y) + 186 * scale
        let table = CGRect(x: Double(arenaOrigin.x) + 93 * horizontalScale, y: tableTop, width: 754 * horizontalScale, height: 1251 * scale)
        let w = table.width * 0.027
        let bounds = CGRect(x: table.minX - table.width * 0.05, y: table.maxY - 20 * scale, width: table.width * 1.1, height: 20 * scale + drop * 1.3 + 24 * scale)
        guard bounds.width > 1, bounds.height > 1 else { compactFrame.isHidden = true; return }
        func color(_ argb: UInt32) -> CGColor {
            UIColor(red: CGFloat((argb >> 16) & 0xff) / 255, green: CGFloat((argb >> 8) & 0xff) / 255, blue: CGFloat(argb & 0xff) / 255,
                    alpha: CGFloat((argb >> 24) & 0xff) / 255).cgColor
        }
        let image = UIGraphicsImageRenderer(size: bounds.size).image { context in
            let c = context.cgContext; c.translateBy(x: -bounds.minX, y: -bounds.minY)
            c.setFillColor(color(0x35091e28))
            c.fillEllipse(in: CGRect(x: table.minX - table.width * 0.04, y: table.maxY + drop * 0.55, width: table.width * 1.08, height: drop * 0.73))
            for x in [table.minX + w * 2, table.maxX - w * 2] {
                let leg = CGPath(roundedRect: CGRect(x: x - w, y: table.maxY - 20 * scale, width: 2 * w, height: drop + 20 * scale), cornerWidth: w * 0.4, cornerHeight: w * 0.4, transform: nil)
                c.saveGState(); c.addPath(leg); c.clip()
                let colors = [color(0xff1c4050), color(0xff8fb7bd), color(0xff20485a)] as CFArray
                if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: nil) {
                    c.drawLinearGradient(g, start: CGPoint(x: x - w, y: 0), end: CGPoint(x: x + w, y: 0), options: [])
                }
                c.restoreGState()
                c.setFillColor(color(0xff142e3c))
                c.fillEllipse(in: CGRect(x: x - w * 1.6, y: table.maxY + drop - w * 0.4, width: w * 3.2, height: w * 0.8))
            }
            c.setFillColor(color(0xff193e50))
            c.addPath(CGPath(roundedRect: CGRect(x: table.minX + w, y: table.maxY - 15 * scale, width: table.width - 2 * w, height: 39 * scale), cornerWidth: 12 * scale, cornerHeight: 12 * scale, transform: nil)); c.fillPath()
        }
        compactFrame.isHidden = false; compactFrame.texture = SKTexture(image: image); compactFrame.size = bounds.size; compactFrame.position = flip(bounds.origin)
    }
    // ---- the full avatar (Android 7254ab2 ModernCourt.updateLocalPlayer / drawLocalPlayer) -------------------------------------
    private func targetFoot() -> CGPoint {
        let s = engine.childStroke
        let (p, z) = s.active ? (s.point, s.height) : (engine.paddle ?? engine.restingPaddle, engine.restingHeight)
        let racket = atlas.geometry(selectedLocalCharacter, .rear, mirror: playerMirror, foot: .zero, height: playerHeight, phase: 2)?.racket ?? .zero
        // Finger/paddle depth is not permission to step through the end of the table: idle movement, empty swings and
        // contact snaps alike.
        let at = flip(screen(p, height: z))
        return CGPoint(x: at.x - racket.x, y: max(nearFloorY, at.y - racket.y))
    }
    private func updateLocalPlayer(_ dt: Double) {
        guard playerHeight > 0 else { return }
        let stroke = engine.childStroke
        // Choose a side at the start of a stroke, never alternate poses as the ball crosses the middle.
        if stroke.id != playerStrokeId { playerStrokeId = stroke.id; playerMirror = stroke.point.x < 0.38 }
        contactAge += dt
        if stroke.contacted && observedContact != stroke.id { observedContact = stroke.id; contactAge = 0 }
        let target = targetFoot()
        guard let previous = playerFoot else { playerFoot = target; return }
        let factor = CGFloat(1 - exp(-dt / (stroke.active ? 0.018 : 0.075)))
        let x = previous.x + (target.x - previous.x) * factor, y = previous.y + (target.y - previous.y) * factor
        gait.update(dt, travel: Double(hypot(x - previous.x, y - previous.y)) / max(1, playerHeight), stroke: stroke.active)
        playerFoot = CGPoint(x: x, y: y)
    }
    private func renderLocalPlayer() {
        guard showsLocalAvatar else { playerNode.isHidden = true; playerShadow.isHidden = true; localPlayerGeometry = nil; return }
        if playerFoot == nil { updateLocalPlayer(0) }
        guard var foot = playerFoot else { return }
        let s = engine.childStroke
        let phase = !s.active ? 0 : !s.contacted ? (selectedLocalCharacter == "minik" ? 0 : 1) : contactAge < 0.085 ? 2 : contactAge < 0.27 ? 3 : 0
        // At impact the engine's actual contact is authoritative; later frames keep the same floor anchor.
        if s.active && s.contacted && contactAge < 0.04 { foot = targetFoot(); playerFoot = foot }
        playerShadow.isHidden = false; playerShadow.position = flip(foot)
        playerShadow.path = CGPath(ellipseIn: CGRect(x: -playerHeight * 0.24, y: -playerHeight * 0.035, width: playerHeight * 0.48, height: playerHeight * 0.06), transform: nil)
        let walkingNow = gait.walking && !s.active
        let walk = selectedLocalCharacter + "-walk"
        let id = walkingNow && atlas.has(walk) ? walk : selectedLocalCharacter
        localPlayerGeometry = atlas.place(playerNode, id, .rear, mirror: playerMirror, foot: foot, height: playerHeight,
                                          phase: walkingNow ? gait.phase : phase, sk: { [unowned self] in self.flip($0) })
    }
    override func update(_ currentTime: TimeInterval) {
        let cameraElapsed = previousTime == 0 ? 0 : min(0.1, max(0, currentTime - previousTime))
        let elapsed = previousTime == 0 ? 0 : min(1.0 / 30, max(0, currentTime - previousTime)); previousTime = currentTime
        if !engine.networked { engine.reception.enabled = true; engine.reception.slow[0] = preferences.receptionSlow }
        accumulator += elapsed
        while accumulator >= 1.0 / 120 { engine.advance(1.0 / 120); accumulator -= 1.0 / 120 }
        if showsLocalAvatar { updateLocalPlayer(elapsed) }
        // The focus between the receiving paddle and the ball, in view coordinates (y down).
        // Android ModernCourt: the other side's receiver is focused at Minik's serve point (ActorPresentation.servePoint).
        let at = engine.reception.receiver == 1 ? MPPoint(0.5, 0.13) : (engine.paddle ?? engine.restingPaddle)
        let a = screen(at), b = screen(engine.renderedBall, height: max(0, engine.flight?.height ?? 0.055))
        receptionView.update(cameraElapsed, assist: engine.reception, local: 0, focus: CGPoint(x: (a.x + b.x) / 2, y: size.height - (a.y + b.y) / 2),
                             width: Double(size.width), height: Double(size.height), holding: activeTouch != nil,
                             zoomOwn: preferences.receptionZoom, follow: preferences.receptionFollow)
        placeCamera()
        onFrame?(engine.drainEvents()); render()
    }
    /// The camera shows the scene at the reception zoom: a point p appears at focus + (p − focus) × zoom + shift.
    private func placeCamera() {
        let z = receptionView.zoom, focus = receptionView.focus, shift = receptionView.shift
        let fx = Double(focus.x), fy = Double(size.height) - Double(focus.y)
        let cx = (Double(size.width) / 2 - fx * (1 - z) - Double(shift.x)) / z
        let cy = (Double(size.height) / 2 - fy * (1 - z) + Double(shift.y)) / z
        cameraNode.setScale(CGFloat(1 / z))
        cameraNode.position = receptionView.amount == 0 ? CGPoint(x: size.width / 2, y: size.height / 2) : CGPoint(x: cx, y: cy)
    }
    private func render() {
        let p = engine.renderedBall, height = max(0, engine.flight?.height ?? 0.055)
        let radius = MPProjection.tableWidth * horizontalScale * 0.017 * (1 + min(height, 0.4) * 0.55)
        ballNode.position = screen(p, height: height); ballNode.setScale(radius)
        shadowNode.position = screen(p); shadowNode.xScale = radius * (0.85 + min(height / 0.5, 1) * 0.6); shadowNode.yScale = radius * 0.6
        shadowNode.alpha = 0.3 - min(height / 0.5, 1) * 0.18
        if let bounce = engine.bouncePoint, engine.bounceAge < 0.38 {
            bounceNode.isHidden = false; bounceNode.position = screen(bounce)
            let r = MPProjection.tableWidth * horizontalScale * (0.035 + engine.bounceAge * 0.10)
            bounceNode.path = CGPath(ellipseIn: CGRect(x: -r, y: -r / 2, width: 2 * r, height: r), transform: nil)
            bounceNode.alpha = 1 - engine.bounceAge / 0.38
        } else { bounceNode.isHidden = true }
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
        // Android 7254ab2: the full avatar holds the paddle; the bare paddle is the guide's.
        paddleNode.isHidden = showsLocalAvatar || !(position.strikeZone || stroke.active)
        renderLocalPlayer()
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
            let restX = arenaOrigin.x + motion.body.x * horizontalScale - imageWidth * 0.5
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
            let bodyPosition = CGPoint(x: arenaOrigin.x + motion.body.x * horizontalScale, y: arenaOrigin.y - motion.body.y * worldScale)
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
