import SpriteKit
import UIKit

/// Android `ModernCourt`: the singles court. Geometry is computed in view points with a top-left origin, as Android's
/// pixels, and converted with `sk(_:)` into SpriteKit's y-up scene. Indoors and Park use the large daily table
/// (`MPLargeMatch`); every other arena, and the guide, the compact court.
final class MPScene: SKScene {
    var engine: MPEngine
    var onFrame: (([MPEvent]) -> Void)?
    /// The online opponent's character id; "" draws `remoteIcon` (Android `remoteCharacterId` blank); nil = the bot.
    var remoteCharacter: String?
    var remoteIcon = "🐱"
    /// Android `remoteHumanName`: an online opponent's name for the name tag (nil: the house player's name).
    var remoteName: String?
    /// Name tags in Hebrew ("אתם") or English ("You").
    var hebrew = false
    var guidePoint: MPPoint?
    var guideDirection: Double?
    /// Android `ModernCourt.tutorial`: the guide lesson on this court (nil in a match). The guide keeps the compact
    /// court and the paddle, never names, and only the spin lessons read Pro gestures.
    var tutorialStep: MPTutorialStep? { didSet { if tutorialStep != oldValue { layoutCourt() } } }
    /// Android `ModernCourt.selectedArena` (set before the match): Indoors and Park play on the large table, whose
    /// grounded contact plane is 0.96 (Android `returnBaseline`).
    var selectedArena: MPArena = .legacy { didSet { applyArena(); if selectedArena != oldValue { layoutCourt() } } }
    /// Android `localCharacterId`: the player's own avatar (Standard and Pro), from the roster ids.
    var localCharacterId = "miniko" { didSet { if localCharacterId != oldValue { render() } } }
    /// Android `localRankColor` (the player's colour rank) and `remoteRankColor` (`PongTeamColors.fill(1)` until the
    /// opponent's badge is known): the name tag colours.
    var localRankColor: UIColor = MPRanking().rank.uiColor
    var remoteRankColor: UIColor = MPTeamColors.uiFill(1)
    /// The full-screen backdrop's frame in this scene's view (points, top-left origin). When the game screen draws
    /// `MPSinglesArenaBackdrop` behind its HUD, pass that view's frame here so the court's scenery lines up; nil: the
    /// scenery fills the scene.
    var backdropFrame: CGRect? { didSet { if backdropFrame != oldValue { layoutBackdrop() } } }
    private var previousTime: TimeInterval = 0, accumulator = 0.0
    private var activeTouch: UITouch?, previousTouch: MPPoint?, previousTouchTime = 0.0
    // Android ModernCourt geometry (points, top-left origin): the arena image rect and its table, scales and actors.
    private var arena = CGRect.zero, tableRect = CGRect.zero, actorScale: CGFloat = 1
    private var playerHeight: CGFloat = 0
    private let backdropNode = SKSpriteNode(), sceneryNode = SKSpriteNode(), shadeNode = SKSpriteNode()
    private let foliage = SKCropNode(), foliageMask = SKShapeNode(), foliageNode = SKSpriteNode()
    private let compactFrame = SKSpriteNode()
    /// The arena cut-out mask: separate shapes (their union), since a single path's overlaps could fill even-odd.
    private let floorCrop = SKCropNode(), floorMask = SKNode()
    private let floorNode = SKSpriteNode(), actorNode = SKSpriteNode(), paddleNode = SKSpriteNode()
    /// Android ModernCourt: Minik's FOLLOW pose drawn under READY while the recovery cross-fades.
    private let recoveryNode = SKSpriteNode()
    private let actorCrop = SKCropNode(), actorMask = SKShapeNode(), actorMaskGroup = SKNode(), bodyCrop = SKCropNode(), bodyMask = SKShapeNode(), bodyNode = SKSpriteNode()
    private let frontCrop = SKCropNode(), frontMask = SKShapeNode(), armCrop = SKCropNode(), armMask = SKShapeNode(), armNode = SKSpriteNode()
    private let ballNode = SKShapeNode(circleOfRadius: 1), shadowNode = SKShapeNode(ellipseOf: CGSize(width: 2, height: 1)), spinNode = MPSpinArt.node()
    private let bounceNode = SKShapeNode(), guideNode = SKShapeNode(), iconNode = SKLabelNode()
    /// Owner report 2026-10: red rings where a short or double bounce landed, and around a ball that hit the
    /// net (Android ModernCourt), so the reason for a point is visible on the table.
    private let faultNode = SKShapeNode(), netNode = SKShapeNode()
    /// Android full-player view (Standard and Pro): the player's own avatar from behind, with its floor shadow.
    private let playerNode = SKSpriteNode(), playerShadow = SKShapeNode()
    private let compact = SKNode(), nameLayer = SKNode()
    private var textures: [String: SKTexture] = [:]
    private let poses = MPPoseSprites()
    private var large: MPLargeMatch?
    /// Android 496a709 `compactRival`: in a local match the compact court's house player also stands on the floor with
    /// its complete poses (needs the bundled pose art; the guide and online opponents keep their drawings).
    private var compactRival: MPGroundedRival?
    private var compactTabletop: CGPath = CGMutablePath()
    /// Android `ping_pong_arena` drawn behind a grounded rival on the original court (the table itself is cut out).
    private let legacyBackNode = SKSpriteNode()
    /// Android `groundedBot`.
    private var groundedBot: Bool { !guide && !engine.networked && MPPoseAtlas.available }
    /// Android ModernCourt.receptionCamera (2026-10): an optional zoom toward the receiver. The scenery follows the zoom
    /// (Android `ReceptionCamera.scenery`); a still copy behind it fills any edge the zoom uncovers.
    private let cameraNode = SKCameraNode()
    private var receptionCamera = MPReceptionCamera()
    // Android full-player state (compact court).
    private var playerFoot: CGPoint?, playerMirror = false, playerStrokeId = -1, observedContact = -1
    private var contactAge = 10.0, walking: CGFloat = 0, playerMoving = false
    private(set) var localPlayerGeometry: MPPoseAtlas.Geometry?
    private var farNameBounds: CGRect?
    // Android tapTouch / proTouch / sendTouch state.
    private var dragStartX: CGFloat = 0, dragPaddle = MPPoint(0.5, 0.87), dragWidth: CGFloat = 1
    private var proPath: [MPPoint] = [], proStarted = 0.0
    private var tapDown = CGPoint.zero, tapDragged = false, standardCommitted = false
    /// Android 838c209 `positioningServe`: while a serve is awaited, a drag repositions the player and a tap serves at
    /// finger-up, independently of rally swipe detection. Once a gesture has moved, returning to its start is still
    /// movement.
    private var positioningServe = false
    private var tracker = MPTouchVelocity()
    init(engine: MPEngine) {
        self.engine = engine
        super.init(size: CGSize(width: 430, height: 760))
        scaleMode = .resizeFill; backgroundColor = UIColor(red: 0.92, green: 0.68, blue: 0.45, alpha: 1)
        backdropNode.zPosition = -3; shadeNode.zPosition = -1.5; sceneryNode.zPosition = -2
        [backdropNode, sceneryNode, foliageNode].forEach { $0.anchorPoint = CGPoint(x: 0, y: 1) }
        shadeNode.anchorPoint = CGPoint(x: 0, y: 1)
        foliage.maskNode = foliageMask; foliage.addChild(foliageNode); foliage.zPosition = 20
        foliageMask.fillColor = .white; foliageMask.strokeColor = .clear
        compactFrame.anchorPoint = CGPoint(x: 0, y: 1); compactFrame.zPosition = -0.5
        // Android ModernCourt fades the arena's decorative outer floor into that setting; the fade is baked into this texture.
        floorNode.anchorPoint = CGPoint(x: 0, y: 1); floorNode.texture = texture("ping_pong_arena_faded")
        floorCrop.addChild(floorNode)
        floorCrop.zPosition = 0; actorNode.zPosition = 1; bounceNode.zPosition = 2; shadowNode.zPosition = 3; paddleNode.zPosition = 4; ballNode.zPosition = 5; spinNode.zPosition = 5.1; guideNode.zPosition = 6; iconNode.zPosition = 2
        playerShadow.zPosition = 3.5; playerNode.zPosition = 4
        playerShadow.fillColor = UIColor(red: 7 / 255, green: 28 / 255, blue: 39 / 255, alpha: 85 / 255); playerShadow.strokeColor = .clear
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
        legacyBackNode.anchorPoint = CGPoint(x: 0, y: 1); legacyBackNode.zPosition = -0.7; legacyBackNode.isHidden = true
        let nodes: [SKNode] = [legacyBackNode, compactFrame, floorCrop, bodyCrop, actorCrop, frontCrop, bounceNode, faultNode, shadowNode, playerShadow, playerNode, paddleNode, ballNode, spinNode, netNode, guideNode, iconNode]
        nodes.forEach(compact.addChild)
        addChild(sceneryNode); addChild(compact); addChild(foliage)
        nameLayer.zPosition = 30
        cameraNode.addChild(backdropNode); cameraNode.addChild(shadeNode); cameraNode.addChild(nameLayer); addChild(cameraNode); camera = cameraNode
        cameraNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
        applyArena()
    }
    required init?(coder: NSCoder) { return nil }
    override func didMove(to view: SKView) { view.isMultipleTouchEnabled = false; layoutCourt() }
    override func didChangeSize(_ oldSize: CGSize) { layoutCourt() }
    func setActive(_ active: Bool) { engine.paused = !active; isPaused = !active; previousTime = 0; accumulator = 0; if !active { cancelTouch() } }
    func replaceEngine(_ engine: MPEngine) {
        cancelTouch(); self.engine = engine; previousTime = 0; accumulator = 0; large?.root.removeFromParent(); large = nil; playerFoot = nil
        compactRival?.body.removeFromParent(); compactRival?.above.removeFromParent(); compactRival = nil
        applyArena(); layoutCourt()
    }
    private func applyArena() { engine.returnBaseline = selectedArena.largeTable ? 0.96 : 0.90 }
    private var guide: Bool { tutorialStep != nil }
    /// Android `usesLargeTable` (needs the bundled pose art; otherwise the compact court is kept).
    var usesLargeTable: Bool { selectedArena.largeTable && !guide && MPPoseAtlas.available }
    /// Android `showsLocalAvatar`: Standard and Pro show the player's own avatar (when the pose art is bundled).
    var showsLocalAvatar: Bool { engine.level != .beginner && !guide && MPPoseAtlas.available }
    private var selectedLocalCharacter: String { MPRoster.find(localCharacterId)?.id ?? "miniko" }
    private var remoteAvatar: String { remoteCharacter ?? engine.bot?.characterId ?? "" }
    private func texture(_ name: String) -> SKTexture {
        if let existing = textures[name] { return existing }
        let value = SKTexture(imageNamed: "mp_" + name); value.filteringMode = .linear; textures[name] = value; return value
    }
    /// View point (top-left origin) to scene point (y-up).
    private func sk(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: size.height - p.y) }
    private func sk(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: size.height - r.maxY, width: r.width, height: r.height) }
    // MARK: Layout (Android onSizeChanged)
    private func layoutCourt() {
        let w = size.width, h = size.height
        guard w > 1, h > 1 else { return }
        layoutBackdrop()
        playerFoot = nil
        if usesLargeTable {
            compact.isHidden = true
            let renderer = large ?? MPLargeMatch(engine: engine, poses: poses)
            if large == nil { large = renderer; addChild(renderer.root) }
            renderer.root.isHidden = false
            renderer.resize(size, scene: sk)
            let g = renderer.layout
            tableRect = CGRect(x: g.left, y: g.top, width: g.width, height: g.depth)
            renderer.update(0, local: localCharacterId, remote: remoteAvatar)
            render(); return
        }
        large?.root.isHidden = true; compact.isHidden = false
        let sceneHeight: CGFloat = 1672 + 365
        let originalScale = min(w / 941, h / sceneHeight)
        // Reconstruct the previous framing as the fixed reference for Minik's size. The table can then grow
        // independently, without enlarging the character.
        let previousScale = min(originalScale * 1.15, (w - 16) / 754, h / (340 + 1453))
        // Full-player framing reserves floor behind the near baseline. Beginner keeps its table scale and paddle.
        actorScale = previousScale
        let fitted = showsLocalAvatar ? min((h - 24) / 2180, (w - 16) / 1120) : min((h - 24) / 1997, (w - 16) / 754)
        // Beach framing uses the spare scenic border: 12% larger table and actors.
        let beach = selectedArena == .beach && !guide ? fitted * 1.12 : fitted
        // Landscape: the headroom freed by the sideline HUD; the table's projected width grows, not the actors.
        let wide = w > h && !guide && selectedArena != .legacy
        let scale = beach * (wide ? 1.08 : 1)
        playerHeight = 550 * scale
        if showsLocalAvatar { actorScale = scale }
        let horizontal = wide ? min(scale * 1.85, (w - 32) / 941) : scale
        let x = (w - 941 * horizontal) / 2
        // The extra table height uses spare floor below, not the far opponent's headroom.
        let landscapeFloor = wide ? h * 0.07 : 0
        let y = max(440 * scale - 186 * scale, h - 24 - (1437 + (showsLocalAvatar ? 390 : 220)) * scale + landscapeFloor)
        arena = CGRect(x: x, y: y, width: 941 * horizontal, height: 1672 * scale)
        tableRect = CGRect(x: x + 93 * horizontal, y: y + 186 * scale, width: 754 * horizontal, height: 1251 * scale)
        floorNode.position = sk(arena.origin); floorNode.size = arena.size
        // The original table's tapered outside edge, in arena image pixels (clockwise on screen).
        let cut = CGMutablePath()
        cut.move(to: CGPoint(x: 155, y: 186)); cut.addLine(to: CGPoint(x: 785, y: 186)); cut.addQuadCurve(to: CGPoint(x: 821, y: 222), control: CGPoint(x: 820, y: 186))
        cut.addLine(to: CGPoint(x: 849, y: 1406)); cut.addQuadCurve(to: CGPoint(x: 804, y: 1457), control: CGPoint(x: 850, y: 1457))
        cut.addLine(to: CGPoint(x: 133, y: 1457)); cut.addQuadCurve(to: CGPoint(x: 91, y: 1409), control: CGPoint(x: 91, y: 1457))
        cut.addLine(to: CGPoint(x: 122, y: 222)); cut.addQuadCurve(to: CGPoint(x: 155, y: 186), control: CGPoint(x: 122, y: 186)); cut.closeSubpath()
        // Android 496a709 `compactTabletop`: the same outline in view points.
        var toView = CGAffineTransform(translationX: arena.minX, y: arena.minY).scaledBy(x: arena.width / 941, y: arena.height / 1672)
        compactTabletop = cut.copy(using: &toView) ?? cut
        // Android 496a709: on the original court a grounded rival stands in front of the full arena image, behind the
        // cut-out table.
        legacyBackNode.isHidden = !(groundedBot && selectedArena == .legacy)
        if !legacyBackNode.isHidden { legacyBackNode.texture = texture("ping_pong_arena"); legacyBackNode.size = arena.size; legacyBackNode.position = sk(arena.origin) }
        // Android: a chosen arena keeps every original table pixel, but not its baked-in decorative floor. Trace the
        // original table's tapered outside edge; a rectangular cut-out leaves wedges of the old green rug.
        if (selectedArena == .legacy && !groundedBot) || guide { floorCrop.maskNode = nil }
        else {
            let outline: CGPath = cut
            let pieces: [CGPath] = [outline,
                CGPath(roundedRect: CGRect(x: 73, y: 694, width: 39, height: 110), cornerWidth: 18, cornerHeight: 18, transform: nil),
                CGPath(roundedRect: CGRect(x: 829, y: 694, width: 39, height: 110), cornerWidth: 18, cornerHeight: 18, transform: nil),
                CGPath(rect: CGRect(x: 96, y: 727, width: 750, height: 59), transform: nil)]
            // Image pixels → view points → scene (y-up).
            var t = CGAffineTransform(translationX: arena.minX, y: h - arena.minY).scaledBy(x: arena.width / 941, y: -arena.height / 1672)
            floorMask.removeAllChildren()
            for piece in pieces {
                let shape = SKShapeNode(path: piece.copy(using: &t) ?? piece); shape.fillColor = .white; shape.strokeColor = .clear; shape.lineWidth = 0
                floorMask.addChild(shape)
            }
            floorCrop.maskNode = floorMask
        }
        renderCompactFrame()
        configureCompactRival()
        render()
    }
    /// Android 496a709 `ModernCourt.onSizeChanged`: register each complete avatar against the compact table's physical
    /// racket height (its floor is 190 source pixels below the surface); one scale through every animation.
    private func configureCompactRival() {
        guard groundedBot else {
            compactRival?.setHidden(true); engine.botCanReach = nil; return
        }
        let rival: MPGroundedRival
        if let existing = compactRival { rival = existing }
        else {
            rival = MPGroundedRival(engine: engine, poses: poses)
            rival.body.zPosition = -0.6; rival.above.zPosition = 1
            compact.addChild(rival.body); compact.addChild(rival.above); compactRival = rival
        }
        let vs = arena.height / 1672
        let farId = MPRoster.find(remoteAvatar)?.id ?? "minik"
        let readyHeight = -(poses.geometry(farId, .front, mirror: false, foot: .zero, height: 1, phase: 0)?.racket.y ?? -0.5)
        let farHeight = min(520, 215 / max(readyHeight, 0.2)) * vs
        let table = tableRect, frame = arena, nearAvatar = showsLocalAvatar
        rival.configure(height: farHeight, ground: { [unowned self] p in CGPoint(x: self.sceneX(p.x), y: self.sceneY(p.y) + 190 * vs) },
                        world: { p in
                            let image = Double((p.y - 190 * vs - frame.minY) / frame.height * 1672)
                            return MPPoint(Double((p.x - table.minX) / table.width), nearAvatar ? MPNearPlayerProjection.tableY(image) : MPProjection.tableY(image))
                        },
                        ballPoint: { [unowned self] p, z in CGPoint(x: self.sceneX(p.x), y: self.sceneY(p.y, z)) })
        rival.update(0, character: remoteAvatar)
        engine.botCanReach = { [weak rival] p, z in rival?.canReach(p, z) ?? true }
    }
    /// Android `drawCompactFrame`: legs, floor shadow and the near rail of the compact table (not in the guide).
    private func renderCompactFrame() {
        guard !guide, tableRect.width > 1 else { compactFrame.isHidden = true; return }
        let scale = arena.height / 1672, drop = 190 * scale, w = tableRect.width * 0.027, table = tableRect
        let bounds = CGRect(x: table.minX - table.width * 0.05, y: table.maxY - 20 * scale, width: table.width * 1.1, height: 20 * scale + drop * 1.3 + 24 * scale)
        let image = UIGraphicsImageRenderer(size: bounds.size).image { context in
            let c = context.cgContext; c.translateBy(x: -bounds.minX, y: -bounds.minY)
            c.setFillColor(MPColor.ui(0x35091e28).cgColor)
            c.fillEllipse(in: CGRect(x: table.minX - table.width * 0.04, y: table.maxY + drop * 0.55, width: table.width * 1.08, height: drop * 0.73))
            for x in [table.minX + w * 2, table.maxX - w * 2] {
                let leg = CGPath(roundedRect: CGRect(x: x - w, y: table.maxY - 20 * scale, width: 2 * w, height: drop + 20 * scale), cornerWidth: w * 0.4, cornerHeight: w * 0.4, transform: nil)
                c.saveGState(); c.addPath(leg); c.clip()
                let colors = [MPColor.ui(0xff1c4050).cgColor, MPColor.ui(0xff8fb7bd).cgColor, MPColor.ui(0xff20485a).cgColor] as CFArray
                if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: nil) {
                    c.drawLinearGradient(g, start: CGPoint(x: x - w, y: 0), end: CGPoint(x: x + w, y: 0), options: [])
                }
                c.restoreGState()
                c.setFillColor(MPColor.ui(0xff142e3c).cgColor)
                c.fillEllipse(in: CGRect(x: x - w * 1.6, y: table.maxY + drop - w * 0.4, width: w * 3.2, height: w * 0.8))
            }
            c.setFillColor(MPColor.ui(0xff193e50).cgColor)
            c.addPath(CGPath(roundedRect: CGRect(x: table.minX + w, y: table.maxY - 15 * scale, width: table.width - 2 * w, height: 39 * scale), cornerWidth: 12 * scale, cornerHeight: 12 * scale, transform: nil)); c.fillPath()
        }
        compactFrame.isHidden = false; compactFrame.texture = SKTexture(image: image); compactFrame.size = bounds.size; compactFrame.position = sk(bounds.origin)
    }
    /// Android `ArenaBackdrop`: the arena scenery (or `modern_surround`), the caption shade and the castle foliage.
    private func layoutBackdrop() {
        let frame = backdropFrame ?? CGRect(origin: .zero, size: size)
        let wide = frame.width > frame.height
        guard frame.width > 1, frame.height > 1, let image = MPSinglesArena.image(selectedArena, wide: wide) else { return }
        let key = "arena/" + selectedArena.wire + (wide ? "/wide" : "/tall")
        let art: SKTexture
        if let cached = textures[key] { art = cached } else { art = SKTexture(image: image); textures[key] = art }
        var rect = MPSinglesArena.destination(image.size, in: frame.size, arena: selectedArena)
        rect.origin.x += frame.minX; rect.origin.y += frame.minY
        for node in [backdropNode, sceneryNode, foliageNode] { node.texture = art; node.size = rect.size }
        sceneryNode.position = sk(rect.origin); foliageNode.position = sk(rect.origin)
        // The camera child is placed relative to the camera (scene centre).
        backdropNode.position = CGPoint(x: rect.minX - size.width / 2, y: size.height / 2 - rect.minY)
        let shade = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height * 0.25)
        shadeNode.texture = textures["shade"] ?? {
            let t = SKTexture(image: UIGraphicsImageRenderer(size: CGSize(width: 4, height: 64)).image { context in
                let colors = [MPSinglesArena.captionShade.cgColor, UIColor.clear.cgColor] as CFArray
                if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: nil) {
                    context.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: 64), options: [])
                }
            }); textures["shade"] = t; return t
        }()
        shadeNode.size = shade.size; shadeNode.position = CGPoint(x: shade.minX - size.width / 2, y: size.height / 2 - shade.minY)
        let polygons = MPSinglesArena.foliage(selectedArena, wide: wide)
        foliage.isHidden = polygons.isEmpty
        if !polygons.isEmpty {
            let path = CGMutablePath()
            for polygon in polygons {
                for (i, p) in polygon.enumerated() {
                    let q = sk(CGPoint(x: rect.minX + p.x * rect.width, y: rect.minY + p.y * rect.height))
                    if i == 0 { path.move(to: q) } else { path.addLine(to: q) }
                }
                path.closeSubpath()
            }
            foliageMask.path = path
        }
    }
    // MARK: Android projection (compact court)
    private func sceneX(_ x: Double) -> CGFloat { tableRect.minX + CGFloat(x) * tableRect.width }
    private func sceneY(_ y: Double, _ height: Double = 0) -> CGFloat {
        let ground = showsLocalAvatar ? MPNearPlayerProjection.imageY(y) : MPProjection.imageY(y)
        return arena.minY + CGFloat((ground - height * (MPProjection.bottom - MPProjection.top) * 0.075) / 1672) * arena.height
    }
    /// Android `screenPoint`: a table point at a height, in view points.
    func screenPoint(_ p: MPPoint, _ height: Double = 0) -> CGPoint {
        if usesLargeTable, let large { return large.ballPoint(p, height) }
        return CGPoint(x: sceneX(p.x), y: sceneY(p.y, height))
    }
    private var inputHeight: Double { max(engine.flight?.height ?? 0.055, 0) }
    /// Android `point(x, y)`: the table point under a view point (clamped to the table).
    private func point(_ v: CGPoint) -> MPPoint? {
        if usesLargeTable, let large { return large.input(v.x, v.y, inputHeight) }
        guard (0...size.width).contains(v.x), (0...size.height).contains(v.y), tableRect.width > 0, arena.height > 0 else { return nil }
        let image = Double((v.y - arena.minY) / arena.height) * 1672 + inputHeight * (MPProjection.bottom - MPProjection.top) * 0.075
        let y = showsLocalAvatar ? MPNearPlayerProjection.tableY(image) : MPProjection.tableY(image)
        return MPPoint(Double((v.x - tableRect.minX) / tableRect.width).mpClamp(0, 1), y.mpClamp(0, 1))
    }
    private var nearFloorY: CGFloat { usesLargeTable ? large?.nearFloorY ?? 0 : tableRect.maxY + 190 * arena.height / 1672 }
    // MARK: Frame
    override func update(_ currentTime: TimeInterval) {
        let raw = previousTime == 0 ? 0 : max(0, currentTime - previousTime)
        let elapsed = min(1.0 / 30, raw); previousTime = currentTime
        // Android ModernCourt.doFrame: a local match always offers this player's own slow-motion choice; online the
        // match link sets the shared clock.
        if !engine.networked { engine.reception.enabled = true; engine.reception.slow[0] = MPReceptionSettings.slow }
        updateVisibleBodies()
        accumulator += elapsed
        while accumulator >= 1.0 / 120 { engine.advance(1.0 / 120); accumulator -= 1.0 / 120 }
        updateCamera(min(raw, 0.1))
        // Android 496a709 `updateActorPresentation`.
        if usesLargeTable { large?.update(elapsed, local: localCharacterId, remote: remoteAvatar) }
        else {
            if showsLocalAvatar { updateLocalPlayer(elapsed) }
            if groundedBot { compactRival?.update(elapsed, character: remoteAvatar) }
        }
        onFrame?(engine.drainEvents()); render()
    }
    /// Android `updateVisibleBodies`: the drawn players as loose-ball obstacles, and the large table's reach test.
    private func updateVisibleBodies() {
        engine.childCanReach = usesLargeTable && showsLocalAvatar ? { [weak self] p, z in self?.large?.canReturn(p, z) ?? true } : nil
        if usesLargeTable { large?.bodies(); return }
        let scale = arena.height / 1672
        let lift = Double((MPProjection.bottom - MPProjection.top) * 0.075) * Double(scale)
        guard lift > 0 else { return }
        engine.visibleFloor = -190 * Double(scale) / lift
        let nearX = playerFoot?.x ?? sceneX(0.5)
        let farX = arena.minX + CGFloat(engine.motion.body.x) * arena.width / 941
        let grounded = groundedBot ? compactRival?.floorFoot : nil
        engine.visibleBodies = [
            MPLooseBall.Body(x: Double((nearX - tableRect.minX) / tableRect.width), y: 1.06, radiusX: 0.15, radiusY: 0.06, bottom: engine.visibleFloor, top: 2.7),
            MPLooseBall.Body(x: grounded?.x ?? Double((farX - tableRect.minX) / tableRect.width), y: grounded?.y ?? -0.06, radiusX: 0.14, radiusY: 0.06, bottom: engine.visibleFloor, top: 2.7)]
    }
    /// Android ModernCourt: the camera centres between the receiving paddle (or the far server) and the ball.
    private func updateCamera(_ dt: Double) {
        let at = engine.reception.receiver == 1 ? MPEngine.servePoint : (engine.paddle ?? engine.restingPaddle)
        let a = screenPoint(at), b = screenPoint(engine.ball, engine.renderedHeight)
        let focus = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        receptionCamera.update(dt, assist: engine.reception, local: 0, focus: focus, size: size, holding: activeTouch != nil, reduceMotion: UIAccessibility.isReduceMotionEnabled)
        // Android 579de33 `constrainReceptionCamera`: both players stay whole while zoomed. Android lets the far player
        // draw up under its transparent HUD; this court view cannot draw beyond its own edges, so they bound the frame.
        if activeTouch == nil, proPath.isEmpty, let rival = usesLargeTable ? large?.farGeometry?.bounds : compactRival?.geometry?.bounds,
           let local = localPlayerGeometry?.bounds {
            receptionCamera.keepPlayersVisible(top: rival.minY, bottom: local.maxY, visibleTop: 6, visibleBottom: size.height - 6)
        }
        placeCamera()
    }
    /// The view centre in the court's top-left coordinates, converted to the scene's y-up coordinates.
    private func placeCamera() {
        let c = receptionCamera, zoom = max(c.zoom, 0.01)
        let centre = CGPoint(x: c.x + (size.width / 2 - c.x - c.tx) / zoom, y: c.y + (size.height / 2 - c.y - c.ty) / zoom)
        cameraNode.position = c.amount == 0 ? CGPoint(x: size.width / 2, y: size.height / 2) : CGPoint(x: centre.x, y: size.height - centre.y)
        cameraNode.setScale(1 / zoom)
    }
    // MARK: Full player (compact court)
    private func playerTarget() -> (MPPoint, Double) {
        let s = engine.childStroke
        if s.active { return (s.point, s.height) }
        return (engine.paddle ?? engine.restingPaddle, engine.restingHeight)
    }
    private func targetFoot() -> CGPoint {
        let (p, z) = playerTarget()
        let racket = poses.geometry(selectedLocalCharacter, .rear, mirror: playerMirror, foot: .zero, height: playerHeight, phase: 2)?.racket ?? .zero
        // Finger/paddle depth is not permission to step through the end of the table, for idle movement, empty swings
        // and contact snaps alike.
        return CGPoint(x: sceneX(p.x) - racket.x, y: max(nearFloorY, sceneY(p.y, z) - racket.y))
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
        let distance = hypot(x - previous.x, y - previous.y)
        playerMoving = distance > playerHeight * 0.001
        walking += distance / max(1, playerHeight) * 7
        playerFoot = CGPoint(x: x, y: y)
    }
    private func renderLocalPlayer() -> Bool {
        guard showsLocalAvatar else { return false }
        if playerFoot == nil { updateLocalPlayer(0) }
        guard var foot = playerFoot else { return false }
        let s = engine.childStroke
        let phase = !s.active ? 0 : !s.contacted ? (selectedLocalCharacter == "minik" ? 0 : 1) : contactAge < 0.085 ? 2 : contactAge < 0.27 ? 3 : 0
        // At impact the engine's actual contact is authoritative; later frames keep the same floor anchor.
        if s.active && s.contacted && contactAge < 0.04 { foot = targetFoot(); playerFoot = foot }
        playerShadow.isHidden = false; playerShadow.position = sk(foot)
        playerShadow.path = CGPath(ellipseIn: CGRect(x: -playerHeight * 0.24, y: -playerHeight * 0.035, width: playerHeight * 0.48, height: playerHeight * 0.06), transform: nil)
        let walkingNow = playerMoving && !s.active
        localPlayerGeometry = poses.show(playerNode, selectedLocalCharacter + (walkingNow ? "-walk" : ""), .rear, mirror: playerMirror, foot: foot,
                                         height: playerHeight, phase: walkingNow ? Int(walking) % 4 : phase, scene: sk)
        return localPlayerGeometry != nil
    }
    // MARK: Render
    private func render() {
        if usesLargeTable, let large {
            large.render(showLocal: showsLocalAvatar, scene: sk)
            localPlayerGeometry = large.localGeometry
            renderNames(); guideNode.isHidden = true; return
        }
        let p = engine.renderedBall, height = engine.renderedHeight
        let radius = tableRect.width * 0.017 * (1 + min(height, 0.4) * 0.55)
        let ball = screenPoint(p, height), visible = engine.ballVisible
        ballNode.position = sk(ball); ballNode.setScale(radius); ballNode.isHidden = !visible
        // A single soft shadow follows the actual surface position; higher balls separate from it.
        let lift = min(height / 0.5, 1)
        shadowNode.position = sk(CGPoint(x: ball.x + radius * (0.12 + lift * 0.35), y: screenPoint(p).y + radius * 0.35))
        shadowNode.xScale = radius * (0.85 + lift * 0.6); shadowNode.yScale = radius * (0.42 + lift * 0.25)
        shadowNode.alpha = 0.3 - lift * 0.18; shadowNode.isHidden = !visible
        MPSpinArt.update(spinNode, at: sk(ball), radius: radius, flight: engine.flight, visible: visible)
        if let bounce = engine.bouncePoint, engine.bounceAge < 0.38 {
            bounceNode.isHidden = false; bounceNode.position = sk(screenPoint(bounce))
            let r = tableRect.width * (0.035 + engine.bounceAge * 0.10)
            bounceNode.path = CGPath(ellipseIn: CGRect(x: -r, y: -r / 2, width: 2 * r, height: r), transform: nil)
            bounceNode.alpha = 1 - engine.bounceAge / 0.38
        } else { bounceNode.isHidden = true }
        if let mark = engine.faultMark, engine.faultAge < 3 {
            faultNode.isHidden = false; faultNode.position = sk(screenPoint(mark))
            let r = tableRect.width * (0.045 + 0.012 * sin(engine.faultAge * 8))
            faultNode.path = CGPath(ellipseIn: CGRect(x: -r, y: -r / 2, width: 2 * r, height: r), transform: nil)
        } else { faultNode.isHidden = true }
        if engine.netAge < 0.5 {
            netNode.isHidden = false; netNode.position = ballNode.position
            let r = radius * (1.5 + engine.netAge * 4)
            netNode.path = CGPath(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r), transform: nil)
            netNode.alpha = 1 - engine.netAge / 0.5
        } else { netNode.isHidden = true }
        let avatar = renderLocalPlayer()
        if !avatar { playerNode.isHidden = true; playerShadow.isHidden = true; localPlayerGeometry = nil }
        renderPaddle(hidden: avatar)
        renderOpponent()
        renderCoach(height)
        renderNames()
    }
    private func renderPaddle(hidden: Bool) {
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
        let factor = min(tableRect.width * 0.31 / max(1, imageSize.width), tableRect.height * 0.16 / max(1, imageSize.height))
        paddleNode.size = CGSize(width: imageSize.width * factor, height: imageSize.height * factor)
        paddleNode.anchorPoint = CGPoint(x: levelName == "starter" ? 0.5 : left ? 0.28 : 0.76, y: 0.72)
        paddleNode.position = sk(screenPoint(position, atContact ? stroke.height : engine.paddle != nil ? inputHeight : engine.restingHeight))
        paddleNode.isHidden = hidden || !(position.strikeZone || stroke.active)
        // Aiming a serve does not move the racket to the selected remote target.
        // Android rotates clockwise by (tilt + swing angle) degrees; SpriteKit's zRotation is counter-clockwise.
        paddleNode.zRotation = UIAccessibility.isReduceMotionEnabled ? 0 : -(engine.paddleTilt + stroke.angle) * .pi / 180
    }
    /// Android `drawCoach`: the guide's pulsing target, aiming arrow, or (spin lessons) the gesture path.
    private func renderCoach(_ height: Double) {
        if let step = tutorialStep, step.spin {
            guard engine.trainingResult == nil else { guideNode.isHidden = true; return }
            // Android: a curve of a quarter of the view's short side, centred at 50 % / 70 %, with a dot moving along it.
            let s = min(size.width, size.height) * 0.25, cx = size.width * 0.5, cy = size.height * 0.70
            var points: [CGPoint] = []
            func cubic(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) {
                for i in 1...24 { let t = CGFloat(i) / 24, u = 1 - t
                    points.append(CGPoint(x: u * u * u * a.x + 3 * u * u * t * b.x + 3 * u * t * t * c.x + t * t * t * d.x, y: u * u * u * a.y + 3 * u * u * t * b.y + 3 * u * t * t * c.y + t * t * t * d.y)) }
            }
            func quad(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) {
                for i in 1...16 { let t = CGFloat(i) / 16, u = 1 - t
                    points.append(CGPoint(x: u * u * a.x + 2 * u * t * b.x + t * t * c.x, y: u * u * a.y + 2 * u * t * b.y + t * t * c.y)) }
            }
            let start = CGPoint(x: cx + s * 0.35, y: cy + s * 0.35); points.append(start)
            if step == .topspin { cubic(start, CGPoint(x: cx + s * 0.3, y: cy - s * 0.2), CGPoint(x: cx - s * 0.1, y: cy - s * 0.5), CGPoint(x: cx - s * 0.45, y: cy - s * 0.5)) }
            else {
                let mid = CGPoint(x: cx - s * 0.3, y: cy - s * 0.2)
                cubic(start, CGPoint(x: cx - s * 0.6, y: cy + s * 0.25), CGPoint(x: cx - s * 0.5, y: cy - s * 0.1), mid)
                quad(mid, CGPoint(x: cx + s * 0.1, y: cy - s * 0.35), CGPoint(x: cx + s * 0.5, y: cy - s * 0.55))
            }
            let path = CGMutablePath()
            for (i, p) in points.enumerated() { if i == 0 { path.move(to: sk(p)) } else { path.addLine(to: sk(p)) } }
            let pulse = CGFloat((sin(engine.trainingTime * 7) + 1) * 0.5)
            let lengths = zip(points, points.dropFirst()).map { hypot($1.x - $0.x, $1.y - $0.y) }
            var remaining = lengths.reduce(0, +) * pulse, dot = points[0]
            for (i, l) in lengths.enumerated() {
                if remaining <= l { let f = l > 0 ? remaining / l : 0; dot = CGPoint(x: points[i].x + (points[i + 1].x - points[i].x) * f, y: points[i].y + (points[i + 1].y - points[i].y) * f); break }
                remaining -= l; dot = points[i + 1]
            }
            let d = sk(dot); path.addEllipse(in: CGRect(x: d.x - 8, y: d.y - 8, width: 16, height: 16))
            guideNode.position = .zero; guideNode.path = path; guideNode.isHidden = false
            guideNode.strokeColor = UIColor(red: 1, green: 238 / 255, blue: 142 / 255, alpha: 160 / 255); guideNode.lineWidth = 3
            return
        }
        guideNode.strokeColor = .yellow; guideNode.lineWidth = 4
        guideNode.isHidden = guidePoint == nil
        if let point = guidePoint {
            guideNode.position = sk(screenPoint(point, height))
            let path = CGMutablePath()
            if let direction = guideDirection {
                let dx = 35 * direction; path.move(to: CGPoint(x: -dx / 2, y: -25)); path.addLine(to: CGPoint(x: dx, y: 25))
                path.addLine(to: CGPoint(x: dx - 12 * direction, y: 20)); path.move(to: CGPoint(x: dx, y: 25)); path.addLine(to: CGPoint(x: dx, y: 10))
            } else { path.addEllipse(in: CGRect(x: -22, y: -22, width: 44, height: 44)) }
            guideNode.path = path
        }
    }
    /// Android `drawNames` / `PongNameSpace`: "You" and the opponent beside their bodies, in their colours, on screen.
    private var nameTags: [(SKShapeNode, SKLabelNode)] = []
    private func renderNames() {
        nameTags.forEach { $0.0.isHidden = true; $0.1.isHidden = true }
        guard !guide else { return }
        let camera = receptionCamera
        func painted(_ r: CGRect?) -> CGRect? {
            r.map { let a = camera.painted(CGPoint(x: $0.minX, y: $0.minY)), b = camera.painted(CGPoint(x: $0.maxX, y: $0.maxY)); return CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y) }
        }
        let opponent = remoteName ?? (MPRoster.find(engine.bot?.characterId ?? "") ?? MPRoster.all[0]).name(hebrew: hebrew)
        let bodies = [showsLocalAvatar ? painted(localPlayerGeometry?.bounds) : nil, painted(usesLargeTable ? large?.farGeometry?.bounds : farNameBounds)]
        let tags = MPSinglesNames.layout([hebrew ? "אתם" : "You", opponent], bodies: bodies, table: painted(tableRect) ?? tableRect,
                                      width: size.width, height: size.height, colors: [localRankColor, remoteRankColor])
        for (i, tag) in tags.enumerated() {
            if i >= nameTags.count {
                let shape = SKShapeNode(), label = SKLabelNode(fontNamed: MPSinglesNames.font.fontName)
                shape.strokeColor = .clear; label.fontSize = 13; label.verticalAlignmentMode = .center; label.horizontalAlignmentMode = .center
                nameLayer.addChild(shape); nameLayer.addChild(label); nameTags.append((shape, label))
            }
            let (shape, label) = nameTags[i]
            // Camera children are placed relative to the view centre.
            let box = CGRect(x: -tag.box.width / 2, y: -tag.box.height / 2, width: tag.box.width, height: tag.box.height)
            let centre = CGPoint(x: tag.box.midX - size.width / 2, y: size.height / 2 - tag.box.midY)
            if shape.path?.boundingBox.size != box.size { shape.path = CGPath(roundedRect: box, cornerWidth: 7, cornerHeight: 7, transform: nil) }
            shape.fillColor = tag.fill; shape.position = centre; shape.isHidden = false
            if label.text != tag.text { label.text = tag.text }
            label.fontColor = tag.ink; label.position = centre; label.isHidden = false
        }
    }
    private func renderOpponent() {
        if groundedBot, let rival = compactRival {
            // Android 496a709: the grounded rival — the full body under the table, the part outside or above it on top.
            actorCrop.isHidden = true; bodyCrop.isHidden = true; frontCrop.isHidden = true; iconNode.isHidden = true; rival.setHidden(false)
            rival.render(tabletop: compactTabletop, bounds: CGRect(origin: .zero, size: size).insetBy(dx: -size.width, dy: -size.height), scene: sk)
            farNameBounds = rival.geometry?.bounds
            return
        }
        compactRival?.setHidden(true); actorCrop.isHidden = false
        // Android ActorPresentation: keep the last swing's hand until a new swing starts, including
        // through recovery and footwork. Footwork translates the ready pose; there is no walk cycle.
        let motion = engine.motion, stroke = engine.minikStroke, facingLeft = stroke.left
        let tableTop = tableRect.minY, vs = arena.height / 1672, hs = arena.width / 941
        let edge = size.height - tableTop
        bodyCrop.isHidden = true; frontCrop.isHidden = true; recoveryNode.isHidden = true; actorNode.alpha = 1
        actorCrop.maskNode = actorMask
        actorMask.path = CGPath(rect: CGRect(x: 0, y: 0, width: size.width, height: size.height), transform: nil)
        farNameBounds = CGRect(x: sceneX(0.5) - tableRect.width * 0.2, y: 0, width: tableRect.width * 0.4, height: tableTop)
        let character = remoteCharacter ?? engine.bot?.characterId ?? "minik"
        if remoteCharacter == "" { actorNode.isHidden = true; iconNode.isHidden = false; iconNode.text = remoteIcon; iconNode.position = sk(screenPoint(.init(engine.ball.x.mpClamp(0.1, 0.9), 0.04))); return }
        actorNode.isHidden = false; iconNode.isHidden = true
        let phase: Int = stroke.active ? (stroke.age < 0.11 ? 2 : stroke.age < 0.20 ? 3 : stroke.age <= 0.27 ? 4 : stroke.age < 0.44 ? 5 : 0) : 0
        if character != "minik", MPRoster.find(character) != nil {
            let sheet = texture("bot_" + character)
            let cell = [0, 0, facingLeft ? 5 : 2, facingLeft ? 6 : 3, facingLeft ? 6 : 3, facingLeft ? 7 : 4][phase]
            let key = character + "/" + String(cell)
            let frame = textures[key] ?? SKTexture(rect: CGRect(x: Double(cell % 4) / 4, y: cell < 4 ? 0.5 : 0, width: 0.25, height: 0.5), in: sheet)
            textures[key] = frame; actorNode.texture = frame
            // Android drawBot (2026-10): up to 600 source pixels tall, 72 % of it above the table's far edge.
            let clearance: CGFloat = 8
            let imageHeight = min(600 * actorScale, max(1, (tableTop - clearance) / 0.72))
            let imageWidth = imageHeight * frame.size().width / max(1, frame.size().height)
            let face = MPArt.face(character, left: facingLeft)
            let physical = MPProjection.ball(stroke.point, stroke.height)
            let contactX = arena.minX + CGFloat(physical.x) * hs - CGFloat(face.x) * imageWidth
            let contactY = arena.minY + CGFloat(physical.y) * vs - CGFloat(face.y) * imageHeight
            let restX = arena.minX + CGFloat(motion.body.x) * hs - imageWidth * 0.5
            let restY = max(clearance, min(tableTop - imageHeight * 0.72, arena.minY + CGFloat(motion.body.y) * vs - imageHeight * 0.65))
            let blend = !stroke.active ? 0 : stroke.age <= 0.27 ? (stroke.age / 0.20).mpClamp(0, 1) : ((stroke.total - stroke.age) / (stroke.total - 0.27)).mpClamp(0, 1)
            let lean = CGFloat(blend * blend * (3 - 2 * blend))
            let x = restX + (contactX - restX) * lean, y = restY + (contactY - restY) * lean
            farNameBounds = CGRect(x: x, y: y, width: imageWidth, height: imageHeight)
            actorNode.anchorPoint = CGPoint(x: 0, y: 1); actorNode.size = CGSize(width: imageWidth, height: imageHeight)
            actorNode.position = sk(CGPoint(x: x, y: y))
            if MPProjection.besideTable(motion.body) {
                // Android c9f5fa6/38b58b4: a side return must not crop the head at the far baseline. Keep the real
                // tabletop in front of lower body parts (not empty air); separate shapes form an explicit union.
                let plane = sceneY(stroke.active ? stroke.point.y : MPProjection.tableY(physical.y))
                let t = sk(tableRect), top = size.height - min(0, y)
                actorMaskGroup.removeAllChildren()
                for r in [CGRect(x: 0, y: t.maxY, width: size.width, height: max(0, top - t.maxY)), CGRect(x: 0, y: 0, width: size.width, height: t.minY),
                          CGRect(x: 0, y: t.minY, width: t.minX, height: t.height), CGRect(x: t.maxX, y: t.minY, width: max(0, size.width - t.maxX), height: t.height),
                          CGRect(x: 0, y: size.height - plane, width: size.width, height: max(0, top - (size.height - plane)))] {
                    let shape = SKShapeNode(rect: r); shape.fillColor = .white; shape.strokeColor = .clear; shape.lineWidth = 0
                    actorMaskGroup.addChild(shape)
                }
                actorCrop.maskNode = actorMaskGroup
            } else {
                // The table occludes the player's torso and hips.
                actorMask.path = CGPath(rect: CGRect(x: 0, y: edge, width: size.width, height: max(0, size.height - edge)), transform: nil)
            }
            if phase == 3 || phase == 4 {
                // Reveal the intact illustrated striking arm and racket over the far edge (same sprite and transform).
                frontCrop.isHidden = false; frontMask.path = CGPath(rect: CGRect(x: 0, y: 0, width: size.width, height: max(0, edge)), transform: nil)
                armNode.texture = actorNode.texture; armNode.size = actorNode.size; armNode.anchorPoint = actorNode.anchorPoint; armNode.position = actorNode.position
                let path = CGMutablePath(), px = actorNode.position.x, py = actorNode.position.y
                for (index, p) in MPArt.arm(character, left: facingLeft).enumerated() {
                    let point = CGPoint(x: px + p.x * imageWidth, y: py - p.y * imageHeight)
                    if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }; path.closeSubpath()
                let radius = MPArt.radius(character, left: facingLeft), grip = MPArt.grip(character, left: facingLeft)
                for (center, r) in [(face, radius), (grip, MPPoint(0.06, 0.065))] {
                    path.addEllipse(in: CGRect(x: px + (center.x - r.x) * imageWidth, y: py - (center.y + r.y) * imageHeight, width: 2 * r.x * imageWidth, height: 2 * r.y * imageHeight))
                }; armMask.path = path
            }
        } else {
            let names = ["ready", "ready", "windup", "accelerate", "contact", "follow"]
            // Android drawMinik: keep the registered racket contact with the previous character size (`actorScale`).
            let offset = MPProjection.offset(facingLeft)
            let bodyPosition = sk(CGPoint(x: arena.minX + CGFloat(motion.body.x) * hs + CGFloat(offset.x) * (hs - actorScale),
                                          y: arena.minY + CGFloat(motion.body.y) * vs + CGFloat(offset.y) * (vs - actorScale)))
            func pose(_ node: SKSpriteNode, _ index: Int, alpha: Double) {
                node.texture = texture((facingLeft ? "minik_left_" : "minik_motion_") + names[index])
                let registration: (Double, Double, Double)
                if facingLeft { registration = index == 5 ? (0.507, 0.652, 0.994) : (0.5, 0.65, 1) }
                else if index == 5 { registration = (0.490, 0.729, 0.879) }
                else { registration = (0.5, 0.65, 1) }
                node.size = CGSize(width: 600 * actorScale * registration.2, height: 600 * actorScale * registration.2)
                node.anchorPoint = CGPoint(x: registration.0, y: 1 - registration.1)
                node.position = bodyPosition; node.alpha = CGFloat(alpha)
            }
            // Android ModernCourt/ActorPresentation.recoveryBlend: after the follow-through, FOLLOW fades into READY
            // over 0.16 s instead of snapping between the two drawings.
            let recovery = stroke.recoveryBlend
            if phase == 0 && recovery < 1 {
                recoveryNode.isHidden = false; pose(recoveryNode, 5, alpha: 1 - recovery); pose(actorNode, 0, alpha: recovery)
            } else { pose(actorNode, phase, alpha: 1) }
            bodyCrop.isHidden = false; bodyNode.texture = texture("minik_motion_body"); bodyNode.size = CGSize(width: 600 * actorScale, height: 600 * actorScale)
            bodyNode.anchorPoint = CGPoint(x: 0.5, y: 0.35); bodyNode.position = bodyPosition
            bodyMask.path = CGPath(rect: CGRect(x: 0, y: edge, width: size.width, height: max(0, bodyPosition.y + 40 * vs - edge)), transform: nil)
        }
    }
    // MARK: Input (Android worldTouch, tapTouch, proTouch, sendTouch)
    /// Court point (top-left view points, before the camera zoom) of a touch.
    private func court(_ touch: UITouch) -> CGPoint { let p = touch.location(in: self); return CGPoint(x: p.x, y: size.height - p.y) }
    private var gestureScale: CGFloat { max(min(size.width, size.height), 1) * 0.82 }
    private enum Pipeline { case tap, pro, direct }
    private var pipeline: Pipeline {
        if !engine.level.pro && !engine.automaticContact { return .tap }
        if engine.level.pro && (tutorialStep == nil || tutorialStep?.spin == true) { return .pro }
        return .direct
    }
    /// Footwork uses one fixed floor plane for the entire drag. Ball height and the finger's first location must not
    /// teleport or reverse the player.
    private func beginFootwork(_ x: CGFloat) {
        dragStartX = x; dragPaddle = engine.restingPaddle
        dragWidth = max(abs(screenPoint(MPPoint(1, 0.94), 0.18).x - screenPoint(MPPoint(0, 0.94), 0.18).x), 1)
    }
    private func footwork(_ x: CGFloat) -> MPPoint {
        // Android c9f5fa6: sideline footwork may step beside the table (-0.24...1.24).
        MPPoint((dragPaddle.x + Double((x - dragStartX) / dragWidth)).mpClamp(-0.24, 1.24), dragPaddle.y.mpClamp(0.72, 1))
    }
    private func sample(_ v: CGPoint) { proPath.append(MPPoint(Double(v.x / gestureScale), Double(v.y / gestureScale))); if proPath.count > 160 { proPath.remove(at: 1) } }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard activeTouch == nil, let touch = touches.first else { return }
        activeTouch = touch; let v = court(touch); tracker.reset(); tracker.add(v, touch.timestamp); previousTouchTime = touch.timestamp
        if engine.awaitingServe {
            positioningServe = true; beginFootwork(v.x); tapDown = v; tapDragged = false
            engine.endTouch(cancelled: true); return
        }
        switch pipeline {
        case .tap: beginFootwork(v.x); tapDown = v; tapDragged = false; standardCommitted = false
        case .pro: proPath = []; beginFootwork(v.x); proStarted = touch.timestamp; sample(v); engine.touch(point(v), movePaddle: !showsLocalAvatar)
        case .direct:
            let p = point(v); previousTouch = p
            engine.touch(p)
        }
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        let samples = event?.coalescedTouches(for: touch) ?? [touch]
        for item in samples where item.timestamp > previousTouchTime { tracker.add(court(item), item.timestamp) }
        let v = court(touch)
        if positioningServe {
            if hypot(v.x - tapDown.x, v.y - tapDown.y) > 12 { tapDragged = true }
            if tapDragged { engine.prepareGesture(footwork(v.x)) }
            previousTouchTime = touch.timestamp; return
        }
        switch pipeline {
        case .tap:
            if hypot(v.x - tapDown.x, v.y - tapDown.y) > 12 { tapDragged = true }
            if tapDragged && !standardCommitted {
                let velocity = tracker.velocity
                standardCommitted = engine.standardSwipe(MPPoint(Double(velocity.dx / gestureScale), Double(velocity.dy / gestureScale)))
                if !standardCommitted { engine.prepareGesture(footwork(v.x)); engine.guidePreparedTap(from: point(tapDown), to: point(v)) }
            }
            previousTouchTime = touch.timestamp
        case .pro:
            for item in samples where item.timestamp > previousTouchTime { sample(court(item)) }
            previousTouchTime = touch.timestamp
            engine.prepareGesture(footwork(v.x))
        case .direct:
            for item in samples {
                let p = point(court(item)), old = previousTouch
                guard item.timestamp > previousTouchTime, p != old else { continue }
                send(p, old: old, down: false)
                previousTouch = p; previousTouchTime = item.timestamp
            }
        }
    }
    /// Android `sendTouch`: gesture velocity is normalised by the view, not the table projection, so the same visible
    /// swipe has the same power in every arena; Pro gets an equal physical finger allowance (32 pt).
    private func send(_ p: MPPoint?, old: MPPoint?, down: Bool) {
        let v = tracker.velocity
        let velocity = p != nil && old != nil ? MPPoint(Double(v.dx / gestureScale), Double(v.dy / gestureScale)) : .zero
        if let p, engine.level.pro {
            let q = screenPoint(p, inputHeight)
            let dx = abs(screenPoint(MPPoint(p.x + 0.001, p.y), inputHeight).x - q.x) * 1000
            let dy = abs(screenPoint(MPPoint(p.x, p.y + 0.001), inputHeight).y - q.y) * 1000
            engine.swipeTouchTolerance = max(engine.tuning.swipeCollisionForgiveness, min(Double(32 / max(min(dx, dy), 1)), 0.35))
        }
        engine.touch(p, movement: velocity, down: down)
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        let v = court(touch)
        if positioningServe {
            // Also handles a final displacement without an intervening move.
            if hypot(v.x - tapDown.x, v.y - tapDown.y) > 12 { tapDragged = true }
            if !tapDragged && engine.awaitingServe { engine.touch(point(v), movePaddle: false); engine.endTouch() } else { engine.endTouch(cancelled: true) }
            positioningServe = false; activeTouch = nil; previousTouch = nil; previousTouchTime = 0; tapDragged = false
            return
        }
        switch pipeline {
        case .tap:
            if !tapDragged { engine.touch(point(v), movePaddle: !showsLocalAvatar) }
            else if !standardCommitted { engine.prepareGesture(footwork(v.x)) }
            engine.endTouch()
        case .pro:
            sample(v)
            if let stroke = MPPongStroke.read(proPath, durationMs: Int64(((touch.timestamp - proStarted) * 1000).rounded())) { engine.completeGesture(stroke) }
            engine.endTouch(); proPath = []
        case .direct:
            let p = point(v); if p != previousTouch { tracker.add(v, touch.timestamp); send(p, old: previousTouch, down: false) }
            engine.endTouch()
        }
        activeTouch = nil; previousTouch = nil; previousTouchTime = 0
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { cancelTouch() }
    private func cancelTouch() { engine.release(); activeTouch = nil; previousTouch = nil; previousTouchTime = 0; proPath = []; tapDragged = false; positioningServe = false }
}
/// Android `VelocityTracker` (least squares over the last 100 ms), in view points per second.
struct MPTouchVelocity {
    private var samples: [(CGPoint, TimeInterval)] = []
    mutating func reset() { samples = [] }
    mutating func add(_ p: CGPoint, _ t: TimeInterval) {
        samples.append((p, t)); samples.removeAll { t - $0.1 > 0.1 }
    }
    var velocity: CGVector {
        guard samples.count >= 2, let last = samples.last?.1 else { return .zero }
        let n = Double(samples.count)
        let ts = samples.map { $0.1 - last }, mt = ts.reduce(0, +) / n
        let mx = samples.map { Double($0.0.x) }.reduce(0, +) / n, my = samples.map { Double($0.0.y) }.reduce(0, +) / n
        var stt = 0.0, stx = 0.0, sty = 0.0
        for (i, s) in samples.enumerated() { let dt = ts[i] - mt; stt += dt * dt; stx += dt * (Double(s.0.x) - mx); sty += dt * (Double(s.0.y) - my) }
        guard stt > 1e-9 else { return .zero }
        return CGVector(dx: stx / stt, dy: sty / stt)
    }
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
