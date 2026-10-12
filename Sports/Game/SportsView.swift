import SpriteKit
import UIKit

/// Calls the court once per display frame without the display link retaining the view.
@MainActor
private final class SportsFrameTarget: NSObject {
    weak var view: SportsView?

    @objc func tick(_ link: CADisplayLink) {
        guard let view = view else {
            link.invalidate()
            return
        }
        view.frameTick()
    }
}

/// The Canvas layer: everything Android draws in `SportsView.onDraw` above the static backdrop.
private final class SportsCanvas: UIView {
    weak var owner: SportsView?

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        owner?.onDraw(context)
    }
}

/// Android `drawBitmapMesh(volley_beach, 24, 20, oceanMesh)`: the beach image over a 25 x 21 vertex
/// grid whose water band waves with the match clock (SpriteKit warp geometry, on the GPU). The
/// bottom fade (`LinearGradient` with `DST_IN`) is baked into the texture: the faded rows never move.
private final class OceanScene: SKScene {
    private let sprite: SKSpriteNode
    private var source: [SIMD2<Float>] = []
    private var meshHeight: CGFloat = 1

    init(texture: SKTexture, size: CGSize) {
        sprite = SKSpriteNode(texture: texture)
        super.init(size: size)
        backgroundColor = .clear
        scaleMode = .resizeFill
        anchorPoint = .zero
        sprite.anchorPoint = .zero
        addChild(sprite)
        for row in 0...20 {
            for column in 0...24 { source.append(SIMD2(Float(column) / 24, 1 - Float(row) / 20)) }
        }
    }

    required init?(coder: NSCoder) {
        return nil
    }

    /// `width` x `meshHeight` from the top of the view (Android `top = 0`, `bottom = scaledHeight`).
    func layout(width: CGFloat, viewHeight: CGFloat, meshHeight: CGFloat) {
        size = CGSize(width: width, height: viewHeight)
        self.meshHeight = max(meshHeight, 1)
        sprite.size = CGSize(width: width, height: self.meshHeight)
        sprite.position = CGPoint(x: 0, y: viewHeight - self.meshHeight)
    }

    /// Android rebuilds the mesh every frame from the match clock.
    func warp(_ t: Double) {
        let width = Double(size.width)
        let scaled = Double(meshHeight)
        guard width > 0 else { return }
        var destination: [SIMD2<Float>] = []
        destination.reserveCapacity(source.count)
        for row in 0...20 {
            for column in 0...24 {
                let u = Double(column) / 24.0
                let v = Double(row) / 20.0
                var water = 0.0
                if v >= 0.22 && v <= 0.58 { water = pow(sin((v - 0.22) / 0.36 * Double.pi), 2.0) * pow(sin(u * Double.pi), 2.0) }
                let x = u * width + sin(v * 65 + t * 1.4) * width * 0.0035 * water
                let y = v * scaled + sin(u * 30 + v * 21 - t * 1.1) * scaled * 0.004 * water
                destination.append(SIMD2(Float(x / width), Float(1 - y / scaled)))
            }
        }
        sprite.warpGeometry = SKWarpGeometryGrid(columns: 24, rows: 20, sourcePositions: source, destinationPositions: destination)
    }
}

/// Port of Android SportsView.kt: the squash pseudo-3D court and the volleyball camera court, the
/// moving beach water, the reception zoom, actors sized by their visible body with stable name
/// tags, the ball with its trail, contact blend and landing ring, the HUD, practice targets and the
/// touch grammar (move, wall/floor taps, strokes, volleyball taps, double taps, swipes and blocks).
/// Android draws on a Canvas in pixels scaled by density; iOS draws the same geometry with Core
/// Graphics in points, with the static backdrop and squash court pre-rendered once per size.
@MainActor
final class SportsView: UIView {
    let engine: SportsEngine
    let localId: String
    let he: Bool
    private let art = SportsArt.shared
    private let send: (String, Double, Double, Double) -> Void
    private let onEvent: (GameEvent) -> Void
    private let onFinish: () -> Void

    private var firstFrame = true
    private var last: CFTimeInterval = 0
    private var previousEvent: Int
    private var done = false
    var running = true {
        didSet { if running { startLink() } }
    }
    var authority = true
    var replicaAge = 0.0
    private var camera = ArenaCamera(0.0, 0.0, 26.0, 1.0, 0.9, 52.0, 0.60)
    private var restingCamera = ArenaCamera(0.0, 0.0, 26.0, 1.0, 0.9, 52.0, 0.60)
    var receptionZoom = true
    var receptionFollow = true
    private var zoomAmount = 0.0
    private var zoomX: Float = 0
    private var zoomY: Float = 0
    private var zoomFactor: Float { return Float(1.0 + 0.48 * zoomAmount) }

    private var downX: CGFloat = 0
    private var downY: CGFloat = 0
    private var dragging = false
    private var downTime: Double = 0
    private var touch: UITouch?
    private var frozen = ArenaCamera(0.0, 0.0, 26.0, 1.0, 0.9, 52.0, 0.60)
    /// Android `pendingVolleyTap` (a Runnable posted for 210 ms), identified so a stale timer is ignored.
    private var pendingVolleyTap: (id: Int, run: () -> Void)?
    private var tapSerial = 0
    private var pendingTapAt: Double = 0
    private var pendingTapPoint = CGPoint.zero
    private var gesture = ""
    private var wallTap = Vec()
    private var ballAtDown = CGPoint.zero
    private var arena = CGRect.zero
    private var selected = -1
    private var targetRects: [CGRect] = Array(repeating: .null, count: 4)
    private let labelPlacer = StableLabels()
    private var occupiedLabels: [LabelBox] = []
    private var drawnHands: [String: CGPoint] = [:]
    private var drawnBall = CGPoint.zero
    private var contactShot = -1
    private var contactSeenAt = -10.0
    private var trail: [(Double, Double, Double)] = []
    private var fonts: [Int: UIFont] = [:]
    private var lastSize = CGSize.zero

    private let backdrop = UIImageView()
    private let courtClip = UIView()
    private let court = UIImageView()
    private var ocean: SKView?
    private var oceanScene: OceanScene?
    private let canvas = SportsCanvas()
    private var displayLink: CADisplayLink?
    private let frameTarget = SportsFrameTarget()

    init(engine: SportsEngine, localId: String, hebrew: Bool, send: @escaping (String, Double, Double, Double) -> Void,
         onEvent: @escaping (GameEvent) -> Void, onFinish: @escaping () -> Void) {
        self.engine = engine
        self.localId = localId
        self.he = hebrew
        self.send = send
        self.onEvent = onEvent
        self.onFinish = onFinish
        self.previousEvent = engine.eventId
        super.init(frame: .zero)
        backgroundColor = SportsPalette.ui(0xffc7ebef)
        isMultipleTouchEnabled = false
        isAccessibilityElement = true
        accessibilityLabel = hebrew ? "מגרש המשחק" : "Sports court"
        backdrop.contentMode = .scaleToFill
        backdrop.isUserInteractionEnabled = false
        addSubview(backdrop)
        if engine.config.sport == .volley && engine.config.arena == "beach" {
            let view = SKView(frame: .zero)
            view.allowsTransparency = true
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
            view.preferredFramesPerSecond = 60
            view.ignoresSiblingOrder = true
            addSubview(view)
            ocean = view
        }
        courtClip.clipsToBounds = true
        courtClip.isUserInteractionEnabled = false
        court.isUserInteractionEnabled = false
        court.layer.anchorPoint = .zero
        courtClip.addSubview(court)
        addSubview(courtClip)
        canvas.owner = self
        canvas.isOpaque = false
        canvas.backgroundColor = .clear
        canvas.isUserInteractionEnabled = false
        canvas.contentMode = .redraw
        addSubview(canvas)
        frameTarget.view = self
    }

    required init?(coder: NSCoder) {
        return nil
    }

    // MARK: Lifecycle

    override func setNeedsDisplay() {
        super.setNeedsDisplay()
        canvas.setNeedsDisplay()
    }

    private func startLink() {
        guard displayLink == nil, window != nil, running else {
            canvas.setNeedsDisplay()
            return
        }
        let link = CADisplayLink(target: frameTarget, selector: #selector(SportsFrameTarget.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    /// Android `postInvalidateOnAnimation` while running.
    func frameTick() {
        oceanScene?.warp(engine.clock)
        canvas.setNeedsDisplay()
        if !running { stopLink() }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            // Android onDetachedFromWindow (keepScreenOn ends with the court).
            cancelPendingTap()
            running = false
            stopLink()
            ocean?.isPaused = true
            UIApplication.shared.isIdleTimerDisabled = false
        } else {
            // Android `keepScreenOn = true` while the court is shown.
            UIApplication.shared.isIdleTimerDisabled = true
            ocean?.isPaused = false
            startLink()
        }
    }

    /// Releases the display link and the water renderer; the view is discarded afterwards.
    func teardown() {
        cancelPendingTap()
        running = false
        stopLink()
        ocean?.presentScene(nil)
        ocean?.isPaused = true
    }

    func cancelTouches() {
        cancelPendingTap()
        touch = nil
        dragging = false
    }

    private func cancelPendingTap() {
        pendingVolleyTap = nil
    }

    private func firePendingTap(_ id: Int) {
        guard let pending = pendingVolleyTap, pending.id == id else { return }
        pendingVolleyTap = nil
        pending.run()
    }

    // MARK: Geometry

    private var vw: CGFloat { return bounds.width }
    private var vh: CGFloat { return bounds.height }
    private var iw: Int { return Int(vw) }
    private var ih: Int { return Int(vh) }
    private var wide: Bool { return vw > vh }
    private var sidePanel: CGFloat { return engine.config.sport == .volley ? 146 : 192 }
    private var rtl: Bool { return AppText.rtl }
    private var local: Athlete { return engine.player(localId) ?? engine.players[0] }
    private var squash: Bool { return engine.config.sport == .squash }
    private var reduceMotion: Bool { return UIAccessibility.isReduceMotionEnabled }

    private func tr(_ en: String, _ he: String) -> String { return SportsText.t(en, he, self.he) }

    private func shown(_ a: Athlete) -> Vec {
        return authority ? a.p : a.p + a.velocity * (replicaAge * engine.receptionScale)
    }

    private func project(_ x: Double, _ y: Double, _ z: Double = 0.0) -> ScreenPoint {
        if !squash {
            // A stable wide court must not shrink whenever a high set goes up. Compress only
            // the upper visual arc smoothly; simulation height, timing and collision stay exact.
            let shownZ = wide && z > 3.5 ? 3.5 + 1.5 * (1 - exp(-(z - 3.5) / 1.5)) : z
            return camera.project(x, y, shownZ, iw, ih)
        }
        let depth = (y + engine.config.halfDepth) / (2 * engine.config.halfDepth)
        let breadth = Double(arena.width) * (0.82 + 0.18 * depth)
        let wallHeight = Double(arena.height) * (wide ? 0.43 : 0.38)
        let floorBack = Double(arena.minY) + wallHeight
        return ScreenPoint(x: Float(Double(arena.midX) + x / 6.4 * breadth),
                           y: Float(floorBack + depth * (Double(arena.maxY) - floorBack) - z / 4.8 * wallHeight * (1 + 0.25 * depth)), depth: 20 - y)
    }

    private func squashGround(_ x: CGFloat, _ y: CGFloat) -> Vec {
        let wallHeight = Double(arena.height) * (wide ? 0.43 : 0.38)
        let back = Double(arena.minY) + wallHeight
        let depth = (Double(y) - back) / (Double(arena.maxY) - back)
        return Vec((Double(x) - Double(arena.midX)) / (Double(arena.width) * (0.82 + 0.18 * depth)) * 6.4, depth * 9.75 - 4.875)
    }

    private func squashWall(_ x: CGFloat, _ y: CGFloat) -> Vec {
        let wallHeight = Double(arena.height) * (wide ? 0.43 : 0.38)
        return Vec((Double(x) - Double(arena.midX)) / (Double(arena.width) * 0.82) * 6.4, (Double(arena.minY) + wallHeight - Double(y)) / wallHeight * 4.8)
    }

    private func wallContains(_ x: CGFloat, _ y: CGFloat) -> Bool {
        let w = squashWall(x, y)
        return w.x >= -3.2 && w.x <= 3.2 && w.y >= 0.0 && w.y <= 4.8
    }

    private func pt(_ p: ScreenPoint) -> CGPoint { return CGPoint(x: CGFloat(p.x), y: CGFloat(p.y)) }

    // MARK: Drawing helpers

    private func font(_ size: CGFloat, _ bold: Bool) -> UIFont {
        let key = Int(size * 10) * 2 + (bold ? 1 : 0)
        if let cached = fonts[key] { return cached }
        let made = UIFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
        fonts[key] = made
        return made
    }

    private func measure(_ s: String, _ size: CGFloat, _ bold: Bool) -> CGFloat {
        return (s as NSString).size(withAttributes: [.font: font(size, bold)]).width
    }

    /// Android `text()`: one line centred on (x, y).
    private func text(_ s: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ color: UInt32, bold: Bool = true) {
        let f = font(max(size, 1), bold)
        let attributes: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: SportsPalette.ui(color)]
        let width = (s as NSString).size(withAttributes: attributes).width
        let top = y - (f.ascender - f.descender) / 2
        (s as NSString).draw(at: CGPoint(x: x - width / 2, y: top), withAttributes: attributes)
    }

    private func polygon(_ c: CGContext, _ points: [(Double, Double, Double)], _ color: UInt32, stroke: Bool = false) {
        guard let first = points.first else { return }
        c.beginPath()
        c.move(to: pt(project(first.0, first.1, first.2)))
        for p in points.dropFirst() { c.addLine(to: pt(project(p.0, p.1, p.2))) }
        c.closePath()
        if stroke {
            c.setLineWidth(1.5)
            c.setStrokeColor(SportsPalette.cg(color))
            c.strokePath()
        } else {
            c.setFillColor(SportsPalette.cg(color))
            c.fillPath()
        }
    }

    private func line(_ c: CGContext, _ x1: Double, _ y1: Double, _ z1: Double, _ x2: Double, _ y2: Double, _ z2: Double, _ color: UInt32, _ width: CGFloat = 1.5) {
        let a = project(x1, y1, z1)
        let b = project(x2, y2, z2)
        c.setStrokeColor(SportsPalette.cg(color))
        c.setLineWidth(width)
        c.strokeLineSegments(between: [pt(a), pt(b)])
    }

    private func roundRect(_ c: CGContext, _ r: CGRect, _ radius: CGFloat, _ color: UInt32) {
        c.setFillColor(SportsPalette.cg(color))
        c.addPath(CGPath(roundedRect: r, cornerWidth: min(radius, r.width / 2), cornerHeight: min(radius, r.height / 2), transform: nil))
        c.fillPath()
    }

    // MARK: Layout (Android onSizeChanged)

    override func layoutSubviews() {
        super.layoutSubviews()
        backdrop.frame = bounds
        canvas.frame = bounds
        ocean?.frame = bounds
        if bounds.size != lastSize && vw > 0 && vh > 0 {
            lastSize = bounds.size
            sizeChanged()
            rebuildBackdrop()
            if squash { rebuildCourt() }
        }
        courtClip.frame = squash ? arena : .zero
        applyZoomToCourt()
        canvas.setNeedsDisplay()
    }

    private func sizeChanged() {
        touch = nil
        dragging = false
        cancelPendingTap()
        let w = iw
        let h = ih
        let fw = CGFloat(w)
        let fh = CGFloat(h)
        if squash {
            if w > h {
                arena = ltrb(rtl ? 10 : 192, 12, rtl ? fw - 192 : fw - 10, fh - 14)
            } else {
                arena = ltrb(10, engine.config.tutorial ? 139 : 96, fw - 10, fh - 112)
            }
            return
        }
        arena = ltrb(wide && !rtl ? sidePanel : 8, 10, wide && rtl ? fw - sidePanel : fw - 8, fh - 10)
        let cfg = engine.config
        var distance = 7.0
        let top = wide ? 2.8 : 4.5
        for _ in 0..<160 {
            let landscape = w > h
            var cam = ArenaCamera(0.0, 0.0, distance, 1.1, h > w ? 0.54 : 0.55, landscape ? 25.0 : 52.0, 0.5, landscape ? 1.42 : 0.0,
                                  landscape ? 1.10 : 1.0, orthographic: landscape)
            // Include the server behind the baseline, not only the painted court.
            let framingDepth = cfg.halfDepth + 0.9
            var fitPoints: [(Double, Double, Double)] = []
            for x in [-cfg.halfWidth, cfg.halfWidth] {
                for y in [-framingDepth, framingDepth] {
                    for z in [0.0, y < 0 ? top : 0.0] { fitPoints.append((x, y, z)) }
                }
            }
            let projected = fitPoints.map { cam.project($0.0, $0.1, $0.2, w, h) }
            let topLimit: Float = wide ? 12 : max(cfg.tutorial ? 140 : 83, Float(h) * 0.12)
            let bottomLimit: Float = Float(h) - (wide ? 12 : 106)
            let minY = projected.map { $0.y }.min() ?? 0
            let maxY = projected.map { $0.y }.max() ?? 0
            if wide {
                // Fit the playable floor to this actual window, rather than leaving spare width
                // on long phones. Sprites retain their own body aspect ratio.
                let spanX = (projected.map { $0.x }.max() ?? 0) - (projected.map { $0.x }.min() ?? 0)
                cam.horizontalScale = cam.horizontalScale * Double(Float(arena.width) - 14) / Double(bottomLimit - topLimit) * Double(maxY - minY) / Double(spanX)
            }
            let shift = ((topLimit + bottomLimit - minY - maxY) / 2) / Float(h)
            cam.centerY = 0.5 + Double(shift)
            cam.centerX = wide ? Double(arena.midX) / Double(w) : 0.5
            let shifted = fitPoints.map { cam.project($0.0, $0.1, $0.2, w, h).x }
            let margin: Float = wide ? 6 : 10
            if shifted.allSatisfy({ $0 > Float(arena.minX) + margin && $0 < Float(arena.maxX) - margin }) && maxY - minY < bottomLimit - topLimit {
                camera = cam
                restingCamera = cam
                return
            }
            distance += 0.2
        }
    }

    private func ltrb(_ l: CGFloat, _ t: CGFloat, _ r: CGFloat, _ b: CGFloat) -> CGRect {
        return CGRect(x: l, y: t, width: r - l, height: b - t)
    }

    /// Android `drawWorld`: the scene art (aspect fill), or on the beach the mirrored sand texture
    /// under the water mesh. Static per size; the water moves in the SpriteKit layer.
    private func rebuildBackdrop() {
        let size = bounds.size
        let config = engine.config
        let scene = squash ? "squash" : (config.arena == "beach" ? "volley_beach" : config.arena)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        if !squash && config.arena == "beach" {
            let scale = window?.screen.scale ?? UIScreen.main.scale
            backdrop.image = renderer.image { context in
                SportsPalette.ui(0xffc7ebef).setFill()
                context.fill(CGRect(origin: .zero, size: size))
                guard let tile = art.bitmap("volley_sand_tile") else { return }
                // Android BitmapShader(MIRROR, MIRROR) at the texture's pixel size.
                let tw = tile.size.width / scale
                let th = tile.size.height / scale
                var row = 0
                var y: CGFloat = 0
                while y < size.height {
                    var column = 0
                    var x: CGFloat = 0
                    while x < size.width {
                        let cg = context.cgContext
                        cg.saveGState()
                        cg.translateBy(x: x + (column % 2 == 1 ? tw : 0), y: y + (row % 2 == 1 ? th : 0))
                        cg.scaleBy(x: column % 2 == 1 ? -1 : 1, y: row % 2 == 1 ? -1 : 1)
                        tile.draw(in: CGRect(x: 0, y: 0, width: tw, height: th))
                        cg.restoreGState()
                        x += tw
                        column += 1
                    }
                    y += th
                    row += 1
                }
            }
            guard let beach = art.bitmap("volley_beach") else { return }
            let meshHeight = wide ? size.height * 0.52 : size.width * beach.size.height / beach.size.width
            guard let ocean = ocean else {
                let sand = backdrop.image
                backdrop.image = renderer.image { _ in
                    sand?.draw(in: CGRect(origin: .zero, size: size))
                    SportsView.fadedBeach(beach)?.draw(in: CGRect(x: 0, y: 0, width: size.width, height: meshHeight))
                }
                return
            }
            if oceanScene == nil, let texture = SportsView.fadedBeach(beach) {
                let made = OceanScene(texture: SKTexture(image: texture), size: size)
                oceanScene = made
                ocean.presentScene(made)
            }
            oceanScene?.layout(width: size.width, viewHeight: size.height, meshHeight: meshHeight)
            oceanScene?.warp(engine.clock)
            return
        }
        guard let image = art.bitmap(scene) else {
            backdrop.image = nil
            return
        }
        backdrop.image = renderer.image { _ in
            let s = max(size.width / image.size.width, size.height / image.size.height)
            let w = image.size.width * s
            let h = image.size.height * s
            image.draw(in: CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h))
        }
    }

    /// The beach texture with Android's bottom fade (white to transparent over the lowest 24%).
    private static func fadedBeach(_ image: UIImage) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        let w = cg.width
        let h = cg.height
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = context.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        for row in 0..<h {
            let v = (Double(row) + 0.5) / Double(h)
            let alpha = min(max((1 - v) / 0.24, 0.0), 1.0)
            if alpha >= 1 { continue }
            for x in 0..<w {
                let i = (row * w + x) * 4
                for k in 0..<4 { pixels[i + k] = UInt8((Double(pixels[i + k]) * alpha).rounded()) }
            }
        }
        guard let made = context.makeImage() else { return nil }
        return UIImage(cgImage: made)
    }

    /// The static squash wall and floor (Android `wall` and `floor` minus the question targets),
    /// rendered once per size and zoomed with the court.
    private func rebuildCourt() {
        let size = bounds.size
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        court.image = renderer.image { context in
            let c = context.cgContext
            // Android's racket sets a round stroke cap on the shared Paint after the first frame.
            c.setLineCap(.round)
            let x = engine.config.halfWidth
            let y = -engine.config.halfDepth
            polygon(c, [(-x, y, 0.0), (x, y, 0.0), (x, y, 4.8), (-x, y, 4.8)], 0xffecf6f4)
            line(c, -x, y, 0.48, x, y, 0.48, 0xffce626c, 2)
            line(c, -x, y, 1.78, x, y, 1.78, 0x65bd5260, 1.3)
            line(c, -x, y, 4.57, x, y, 4.57, 0xffce626c, 2)
            let fy = engine.config.halfDepth
            let verts = [(-x, -fy, 0.0), (x, -fy, 0.0), (x, fy, 0.0), (-x, fy, 0.0)]
            polygon(c, verts, 0xffe8c49a)
            polygon(c, verts, 0xffeddbb6)
            if let texture = art.bitmap("wood") {
                let quad = verts.map { pt(project($0.0, $0.1, $0.2)) }
                drawPerspective(c, texture, quad)
            }
            for i in 0...30 {
                let xx = -x + 2 * x * Double(i) / 30
                line(c, xx, -fy, 0.0, xx, fy, 0.0, 0x35a56e3c, 0.6)
            }
            for i in 0...18 {
                let yy = -fy + 2 * fy * Double(i) / 18
                line(c, -x, yy, 0.0, x, yy, 0.0, 0x20aa793f, 0.5)
            }
            polygon(c, verts, 0xffbd5260, stroke: true)
            line(c, -x, 0.65, 0.0, x, 0.65, 0.0, 0xffc35c61)
            line(c, 0.0, 0.65, 0.0, 0.0, fy, 0.0, 0xffc35c61)
            for s in [-1.0, 1.0] {
                let left = s < 0 ? -x : x - 1.6
                polygon(c, [(left, 0.65, 0.0), (left + 1.6, 0.65, 0.0), (left + 1.6, 2.25, 0.0), (left, 2.25, 0.0)], 0xffc35c61, stroke: true)
            }
        }
    }

    /// Android `Matrix.setPolyToPoly(texture corners, floor quad)` + `drawBitmap` clipped to the
    /// floor: the perspective map drawn as thin strips, each through its own affine map.
    private func drawPerspective(_ c: CGContext, _ texture: UIImage, _ quad: [CGPoint]) {
        guard quad.count == 4, let cg = texture.cgImage else { return }
        let map = PlanarMap.square(quad[0], quad[1], quad[2], quad[3])
        c.saveGState()
        c.beginPath()
        c.move(to: quad[0])
        for p in quad.dropFirst() { c.addLine(to: p) }
        c.closePath()
        c.clip()
        let strips = 96
        let tw = CGFloat(cg.width)
        let th = CGFloat(cg.height)
        let image = UIImage(cgImage: cg)
        for i in 0..<strips {
            let v0 = Double(i) / Double(strips)
            let v1 = Double(i + 1) / Double(strips)
            let p00 = map.map(0, v0)
            let p10 = map.map(1, v0)
            let p01 = map.map(0, v1)
            // Affine map of the texture strip (0..tw, th*v0..th*v1) onto p00, p10, p01.
            let sy0 = th * CGFloat(v0)
            let sh = th * CGFloat(v1 - v0)
            let a = (p10.x - p00.x) / tw
            let b = (p10.y - p00.y) / tw
            let cc = (p01.x - p00.x) / sh
            let d = (p01.y - p00.y) / sh
            let transform = CGAffineTransform(a: a, b: b, c: cc, d: d, tx: p00.x - cc * sy0, ty: p00.y - d * sy0)
            c.saveGState()
            c.concatenate(transform)
            // A hair of overlap hides seams between strips.
            c.clip(to: CGRect(x: 0, y: sy0 - 0.5, width: tw, height: sh + 1))
            UIGraphicsPushContext(c)
            image.draw(in: CGRect(x: 0, y: 0, width: tw, height: th))
            UIGraphicsPopContext()
            c.restoreGState()
        }
        c.restoreGState()
    }

    private func applyZoomToCourt() {
        let z = CGFloat(zoomFactor)
        let zx = CGFloat(zoomX)
        let zy = CGFloat(zoomY)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        court.layer.anchorPoint = .zero
        court.layer.position = CGPoint(x: -arena.minX, y: -arena.minY)
        court.layer.bounds = CGRect(origin: .zero, size: bounds.size)
        // Android `c.scale(zoomFactor, zoomFactor, zoomX, zoomY)` in view coordinates.
        court.layer.setAffineTransform(CGAffineTransform(a: z, b: 0, c: 0, d: z, tx: zx - z * zx, ty: zy - z * zy))
        CATransaction.commit()
    }

    // MARK: Reception camera

    private func updateReceptionCamera(_ dt: Double) {
        if touch != nil { return } // Retain the exact projection for an in-progress drag.
        let f = SportsReception.incoming(engine)
        let enabled = f != nil && (f!.id == localId ? receptionZoom : receptionFollow)
        let goal = enabled && !reduceMotion ? f!.strength : 0.0
        zoomAmount = SportsReception.smooth(zoomAmount, goal, dt)
        if enabled, let focus = f, let receiver = engine.player(focus.id) {
            let foot = project(receiver.p.x, receiver.p.y)
            let head = project(receiver.p.x, receiver.p.y, 2.0)
            let ball = project(engine.ball.p.x, engine.ball.p.y, engine.ball.z)
            let x = (min(foot.x, ball.x) + max(foot.x, ball.x)) * 0.5
            let y = (min(head.y, ball.y) + max(foot.y, ball.y)) * 0.5
            if zoomAmount < 0.015 {
                zoomX = x
                zoomY = y
            } else {
                let a = Float(1 - exp(-dt * 4))
                zoomX += (x - zoomX) * a
                zoomY += (y - zoomY) * a
            }
        }
    }

    // MARK: Frame (Android onDraw)

    func onDraw(_ c: CGContext) {
        let now = CACurrentMediaTime()
        let dt = last == 0 ? 0.0 : min(max(now - last, 0.0), 0.05)
        last = now
        if running && authority && !firstFrame {
            engine.update(dt)
        } else if !authority {
            replicaAge = min(replicaAge + dt, 0.15)
        }
        for event in engine.events where event.id > previousEvent {
            onEvent(event)
            previousEvent = event.id
        }
        updateReceptionCamera(dt)
        if squash { applyZoomToCourt() }
        c.saveGState()
        c.clip(to: arena)
        let z = CGFloat(zoomFactor)
        c.translateBy(x: CGFloat(zoomX), y: CGFloat(zoomY))
        c.scaleBy(x: z, y: z)
        c.translateBy(x: -CGFloat(zoomX), y: -CGFloat(zoomY))
        if squash {
            c.setLineCap(.round)
            wallQuestion(c)
        }
        floor(c)
        practiceTargets(c)
        if !squash { net(c, false) }
        // Occlusion is by world depth; stable name labels are painted after all bodies.
        let actors = engine.players.enumerated().map { ($0.offset, $0.element, project($0.element.p.x, $0.element.p.y).depth) }
            .sorted { a, b in a.2 != b.2 ? a.2 > b.2 : a.0 < b.0 }.map { $0.1 }
        let firstNear = actors.first { $0.p.y > 0 }
        for a in actors {
            if !squash && a.p.y > 0 && firstNear === a { net(c, true) }
            actor(c, a)
        }
        if !squash && !actors.contains(where: { $0.p.y > 0 }) { net(c, true) }
        if squash && engine.phase == .rally && engine.canReturn(local) && (engine.ball.p - local.p).length() < 1.45
            && engine.ball.z >= 0.12 && engine.ball.z <= 2.05 {
            let b = project(engine.ball.p.x, engine.ball.p.y, engine.ball.z)
            c.setStrokeColor(SportsPalette.cg(0xffe91e63))
            c.setLineWidth(2)
            c.strokeEllipse(in: CGRect(x: CGFloat(b.x) - 14, y: CGFloat(b.y) - 14, width: 28, height: 28))
        }
        drawBall(c)
        if !squash && engine.phase == .finished && engine.winner == local.member.team && !reduceMotion { celebrate(c) }
        occupiedLabels.removeAll()
        let ordered = engine.players.filter { $0.member.id == localId } + engine.players.filter { $0.member.id != localId }
        for a in ordered { label(c, a) }
        c.restoreGState()
        hud(c)
        if engine.phase == .finished && !done {
            done = true
            let delay: UInt64 = squash ? 1_100_000_000 : 2_300_000_000
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: delay)
                self?.onFinish()
            }
        }
        firstFrame = false
    }

    private func floor(_ c: CGContext) {
        let cfg = engine.config
        let x = cfg.halfWidth
        let y = cfg.halfDepth
        if squash { return } // Pre-rendered with the wall (rebuildCourt).
        let verts = [(-x, -y, 0.0), (x, -y, 0.0), (x, y, 0.0), (-x, y, 0.0)]
        if cfg.arena == "park" { polygon(c, verts, 0xff89bd84) }
        polygon(c, verts, 0xff14a6b2, stroke: true)
        let pixel = 1 / (window?.screen.scale ?? UIScreen.main.scale)
        c.setStrokeColor(SportsPalette.cg(0x24a9835c))
        c.setLineWidth(pixel)
        for i in 0...50 {
            let xx = sin(Double(i) * 31.0) * x
            let yy = cos(Double(i) * 23.0) * y
            let a = pt(project(xx, yy))
            c.strokeLineSegments(between: [a, CGPoint(x: a.x + 2, y: a.y + pixel)])
        }
    }

    /// Android `wall()` after the static wall: the question and its four answer circles.
    private func wallQuestion(_ c: CGContext) {
        let y = -engine.config.halfDepth
        let window = engine.answerFor(localId)
        let q: Question?
        if let w = window {
            q = w.question
        } else if engine.shotHasQuestion && engine.ball.hitter == localId && !engine.ball.scoringChecked {
            q = engine.shotQuestion
        } else {
            q = nil
        }
        guard let question = q else {
            targetRects = Array(repeating: .null, count: 4)
            if engine.practice != nil { return }
            let title = project(0.0, y, 3.7)
            text(tr("AIM · RALLY · PLAY", "מכוונים · חובטים · משחקים"), CGFloat(title.x), CGFloat(title.y), wide ? 18 : 20, 0xff398797)
            return
        }
        let title = project(0.0, y, 4.0)
        text(he ? question.he : question.en, CGFloat(title.x), CGFloat(title.y), wide ? 23 : 25, 0xff155b6e)
        for i in 0...3 {
            let t = project(engine.targetX(i), y, engine.targetZ(i))
            let edge = project(engine.targetX(i) + 0.48, y, engine.targetZ(i))
            let r = max(min(CGFloat(edge.x - t.x), wide ? 23 : 25), 16)
            let chosen = window?.selected == i || (local.chosen == i && engine.serveRequested && engine.players[engine.server] === local)
            let center = pt(t)
            let circle = CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)
            c.setFillColor(SportsPalette.cg(chosen ? 0xffc3f5ed : 0xffffffff))
            c.fillEllipse(in: circle)
            c.setStrokeColor(SportsPalette.cg(chosen ? 0xff008a94 : 0xff84bfc6))
            c.setLineWidth(chosen ? 2.8 : 1.4)
            c.strokeEllipse(in: circle)
            let option = question.options[i]
            text(option, center.x, center.y, option.utf16.count > 4 ? 13 : 18, 0xff173e50)
            let hit = max(r, 22)
            targetRects[i] = CGRect(x: center.x - hit, y: center.y - hit, width: 2 * hit, height: 2 * hit)
        }
    }

    private func net(_ c: CGContext, _ mesh: Bool) {
        let h = engine.config.netHeight
        if mesh {
            for i in -16...16 { line(c, Double(i) * 0.25, 0.0, 0.1, Double(i) * 0.25, 0.0, h, 0x85729298, 0.5) }
            for i in 1...8 { line(c, -4.0, 0.0, Double(i) * 0.24, 4.0, 0.0, Double(i) * 0.24, 0x85729298, 0.5) }
            line(c, -4.0, 0.0, h, 4.0, 0.0, h, 0xffffffff, 3)
        } else {
            for s in [-1.0, 1.0] { line(c, s * 4.15, 0.0, 0.0, s * 4.15, 0.0, h + 0.25, 0xff00869b, 5) }
        }
    }

    private func minimumActorHeight() -> CGFloat {
        return wide && !squash ? max(72, vh * 0.145) : (wide ? 54 : 64)
    }

    private func actor(_ c: CGContext, _ a: Athlete) {
        let pos = shown(a)
        let foot = project(pos.x, pos.y, a.jump)
        let head = project(pos.x, pos.y, a.jump + 2.05)
        let ground = project(pos.x, pos.y)
        let g = pt(ground)
        c.setFillColor(SportsPalette.cg(0x3e213d39))
        c.fillEllipse(in: CGRect(x: g.x - 13, y: g.y - 4, width: 26, height: 8))
        let height = max(CGFloat(foot.y - head.y), minimumActorHeight())
        drawnHands[a.member.id] = art.draw(c, a, foot.x, foot.y, Float(height), squash, camera.yaw)
        if a === local {
            c.setStrokeColor(SportsPalette.cg(0xff00bfc3))
            c.setLineWidth(2)
            c.strokeEllipse(in: CGRect(x: g.x - 12, y: g.y - 3, width: 24, height: 6))
        }
    }

    private func label(_ c: CGContext, _ a: Athlete) {
        let pos = shown(a)
        let foot = project(pos.x, pos.y, a.jump)
        let head = project(pos.x, pos.y, a.jump + 2.05)
        let minimum = Float(minimumActorHeight())
        let p = ScreenPoint(x: foot.x, y: foot.y - max(foot.y - head.y, minimum) - 17, depth: foot.depth)
        let isLocal = a === local
        let name = isLocal ? tr("You", "אתם") : (!a.member.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? a.member.name : a.character.name(he))
        let rank = ProgressRanks.at(a.member.rankPoints)
        let color: UInt32 = isLocal ? rank.color : (!squash ? VolleyPalette.color(engine.config.teamColors[a.member.team]) : 0xffffdcc4)
        let half = Float(max(23, measure(name, 12, true) / 2 + 8))
        let bounds = wide && !squash ? LabelBox(Float(arena.minX) + 6, 8, Float(arena.width) - 12, Float(vh) - 20)
            : LabelBox(8, 65, Float(vw) - 16, Float(vh) - (wide ? 30 : 150))
        var bodies: [LabelBox] = engine.players.map { other in
            let f = project(other.p.x, other.p.y, other.jump)
            let h = project(other.p.x, other.p.y, other.jump + 2.05)
            let tall = max(f.y - h.y, minimum)
            return LabelBox(f.x - 19, f.y - tall, 38, tall)
        }
        if !squash { bodies.append(LabelBox(Float(drawnBall.x) - 14, Float(drawnBall.y) - 14, 28, 28)) }
        let box: LabelBox
        if squash {
            let lx = min(max(p.x - half, Float(arena.minX)), max(Float(arena.maxX) - half * 2, Float(arena.minX)))
            box = LabelBox(lx, p.y - 12, half * 2, 24)
        } else {
            box = labelPlacer.place(a.member.id, p.x, p.y - 12, half * 2, 24, bounds, bodies, occupiedLabels, 25)
        }
        occupiedLabels.append(box)
        let xx = CGFloat(box.cx)
        let yy = CGFloat(box.cy)
        if !squash && hypot(xx - CGFloat(p.x), yy - CGFloat(p.y)) > 26 {
            c.setStrokeColor(SportsPalette.cg(0x80507080))
            c.setLineWidth(1)
            c.strokeLineSegments(between: [CGPoint(x: xx, y: yy), CGPoint(x: CGFloat(p.x), y: CGFloat(p.y) + 10)])
        }
        let h = CGFloat(half)
        roundRect(c, CGRect(x: xx - h, y: yy - 12, width: 2 * h, height: 24), 9, color)
        let ink: UInt32 = isLocal ? rank.ink : (!squash && engine.config.teamColors[a.member.team] == "berry" ? 0xffffffff : 0xff173e50)
        text(name, xx, yy, 12, ink)
    }

    private func drawBall(_ c: CGContext) {
        let b = engine.ball
        let presentationClock = engine.clock + (authority ? 0.0 : replicaAge)
        if b.shot != contactShot {
            contactShot = b.shot
            contactSeenAt = presentationClock
            trail.removeAll()
        }
        if b.active {
            trail.append((b.p.x, b.p.y, b.z))
            while trail.count > 9 { trail.removeFirst() }
        } else {
            trail.removeAll()
        }
        for (i, t) in trail.enumerated() {
            let a = pt(project(t.0, t.1, t.2))
            c.setFillColor(SportsPalette.cg((UInt32(i * 10) << 24) | 0x00fcf9c8))
            let r = 2 + CGFloat(i) * 0.35
            c.fillEllipse(in: CGRect(x: a.x - r, y: a.y - r, width: 2 * r, height: 2 * r))
        }
        let s = pt(project(b.p.x, b.p.y))
        c.setFillColor(SportsPalette.cg(0x55335159))
        c.fillEllipse(in: CGRect(x: s.x - 6, y: s.y - 2, width: 12, height: 4))
        let age = authority || !b.active ? 0.0 : replicaAge * engine.timeScale * engine.receptionScale
        var p = project(b.p.x + b.velocity.x * age, b.p.y + b.velocity.y * age, b.z + b.vz * age - 0.5 * engine.config.gravity * age * age)
        let r: Float = squash ? 5.5 : 10
        if !squash && b.active && presentationClock - engine.poseStamp < 0.25, let hand = drawnHands[b.hitter] {
            // The first release frame visibly touches the actual sprite hand. Blend into the
            // authority trajectory over 100ms; no delay or change to gameplay contact/score.
            let t = Float(min(max((presentationClock - contactSeenAt) / 0.10, 0.0), 1.0))
            let blend = 1 - (1 - t) * (1 - t)
            let hx = Float(hand.x)
            let hy = Float(hand.y)
            p.x = hx + (p.x - hx) * blend
            p.y = hy - r * 0.35 + (p.y - hy + r * 0.35) * blend
        }
        drawnBall = pt(p)
        let center = pt(p)
        let radius = CGFloat(r)
        let middle: UInt32 = squash ? 0xff33bed8 : VolleyPalette.color(engine.config.ballStyle)
        let outer: UInt32 = squash ? 0xff168ba5 : 0xff204356
        if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                     colors: [SportsPalette.cg(0xffffffff), SportsPalette.cg(middle), SportsPalette.cg(outer)] as CFArray,
                                     locations: [0, 0.5, 1]) {
            c.saveGState()
            c.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius))
            c.clip()
            c.drawRadialGradient(gradient, startCenter: CGPoint(x: center.x - radius * 0.4, y: center.y - radius * 0.45), startRadius: 0,
                                 endCenter: CGPoint(x: center.x - radius * 0.4, y: center.y - radius * 0.45), endRadius: radius * 1.7,
                                 options: [.drawsAfterEndLocation])
            c.restoreGState()
        }
        if !squash {
            c.saveGState()
            let angle = CGFloat(engine.clock * 130) * .pi / 180
            c.translateBy(x: center.x, y: center.y)
            c.rotate(by: angle)
            c.translateBy(x: -center.x, y: -center.y)
            if engine.config.ballStyle == "rainbow" { sweep(c, center, radius) }
            c.setStrokeColor(SportsPalette.cg(engine.config.ballStyle == "classic" ? 0xff248db7 : 0xffecf9ff))
            c.setLineWidth(1.7)
            arc(c, CGRect(x: center.x - radius * 0.8, y: center.y - radius, width: radius * 1.4, height: radius * 2), -75, 190)
            arc(c, CGRect(x: center.x - radius, y: center.y - radius * 0.5, width: radius * 2, height: radius * 1.3), 10, 175)
            c.restoreGState()
        }
        if b.active && !squash {
            let land = engine.predictLanding()
            let l = pt(project(land.x, land.y))
            c.setStrokeColor(SportsPalette.cg(0x85ffffff))
            c.setLineWidth(1.5)
            c.strokeEllipse(in: CGRect(x: l.x - 14, y: l.y - 5, width: 28, height: 10))
        }
    }

    /// Android `drawArc(oval, start, sweep, useCenter = false)` (degrees, clockwise on screen).
    private func arc(_ c: CGContext, _ oval: CGRect, _ start: CGFloat, _ sweep: CGFloat) {
        let path = CGMutablePath()
        let transform = CGAffineTransform(translationX: oval.midX, y: oval.midY).scaledBy(x: oval.width / 2, y: oval.height / 2)
        path.addRelativeArc(center: .zero, radius: 1, startAngle: start * .pi / 180, delta: sweep * .pi / 180, transform: transform)
        c.addPath(path)
        c.strokePath()
    }

    /// Android `SweepGradient(yellow, pink, blue, aqua, yellow)` from 3 o'clock, clockwise.
    private func sweep(_ c: CGContext, _ center: CGPoint, _ radius: CGFloat) {
        let stops: [UInt32] = [0xffffdd42, 0xffe91e63, 0xff2979ff, 0xff00daca, 0xffffdd42]
        let wedges = 48
        for i in 0..<wedges {
            let t = (Double(i) + 0.5) / Double(wedges) * 4
            let k = min(Int(t), 3)
            let f = t - Double(k)
            func channel(_ shift: UInt32) -> Double {
                let a = Double((stops[k] >> shift) & 0xff)
                let b = Double((stops[k + 1] >> shift) & 0xff)
                return a + (b - a) * f
            }
            c.setFillColor(red: CGFloat(channel(16) / 255), green: CGFloat(channel(8) / 255), blue: CGFloat(channel(0) / 255), alpha: 1)
            let a0 = CGFloat(i) / CGFloat(wedges) * 2 * .pi
            let a1 = CGFloat(i + 1) / CGFloat(wedges) * 2 * .pi + 0.01
            c.move(to: center)
            c.addArc(center: center, radius: radius, startAngle: a0, endAngle: a1, clockwise: false)
            c.closePath()
            c.fillPath()
        }
    }

    // MARK: HUD

    private struct WrappedLine {
        let text: String
        let y: CGFloat
        let size: CGFloat
    }

    /// Android `wrapped()`: greedy word wrap at the rect width minus 20 dp, lines `size + 4` apart
    /// (squeezed to fit), each centred. A newline in the text starts a new line.
    private func wrapped(_ s: String, _ rect: CGRect, _ size: CGFloat, _ color: UInt32, centerVertically: Bool = false) {
        var lines: [String] = []
        for paragraph in s.components(separatedBy: "\n") {
            var line = ""
            for word in paragraph.components(separatedBy: " ") {
                let candidate = line.trimmingCharacters(in: .whitespaces).isEmpty ? word : line + " " + word
                if measure(candidate, size, false) > rect.width - 20 && !line.trimmingCharacters(in: .whitespaces).isEmpty {
                    lines.append(line)
                    line = word
                } else {
                    line = candidate
                }
            }
            if !line.trimmingCharacters(in: .whitespaces).isEmpty { lines.append(line) }
        }
        let spacing = size + 4
        let actual = min(spacing, rect.height / CGFloat(max(lines.count, 1)))
        let startY = centerVertically ? rect.midY - actual * CGFloat(lines.count) / 2 : rect.minY
        for (i, l) in lines.enumerated() {
            text(l, rect.midX, startY + actual * (CGFloat(i) + 0.5), min(size, actual - 2), color, bold: false)
        }
    }

    private func hud(_ c: CGContext) {
        let w = vw
        let h = vh
        let side: CGFloat = rtl ? w - (sidePanel - 6) : 6
        let score = wide ? ltrb(side + 8, 56, side + sidePanel - 18, 99) : ltrb(w * 0.22, 9, w * 0.78, 53)
        roundRect(c, score, 16, 0xf4f7feff)
        let scoreText: String
        if let d = engine.practice {
            scoreText = "\(d.successes) / \(d.goal)  ♥ \(3 - d.mistakes)"
        } else if engine.config.tutorial {
            scoreText = tr("Practice", "תרגול")
        } else {
            scoreText = "\(engine.scores[0])   :   \(engine.scores[1])"
        }
        text(scoreText, score.midX, score.midY, 23, 0xff14455c)
        if !wide {
            let second: String
            if let d = engine.practice {
                second = tr(d.stage.en, d.stage.he)
            } else if !squash {
                second = tr("Team touches", "נגיעות הקבוצה") + "  \(min(engine.ball.touches, 3)) / 3"
            } else {
                second = tr("Learning", "למידה") + "  \(local.correct)"
            }
            text(second, w / 2, 68, 14, 0xff14455c)
        }
        let cx = squash ? arena.midX : w / 2
        let cy = squash ? arena.midY : h * 0.5
        if engine.phase == .ready && engine.countdown > 0 { text(String(KotlinNumber.int(ceil(engine.countdown))), cx, cy, 64, 0xff126f84) }
        if engine.phase == .point || engine.phase == .finished {
            let caption: String
            if let d = engine.practice {
                caption = d.won ? tr("Challenge complete!", "האתגר הושלם!") : tr("Let's try again", "מנסים שוב")
            } else if engine.phase == .finished {
                caption = tr("Match complete", "המשחק הסתיים")
            } else {
                caption = reason(engine.reason)
            }
            let bannerWidth = min(wide ? arena.width - 24 : w * 0.84, max(128, measure(caption, 20, false) + 48))
            let bannerX = wide ? arena.midX : w * 0.5
            let r = ltrb(bannerX - bannerWidth / 2, cy - 27, bannerX + bannerWidth / 2, cy + 27)
            roundRect(c, r, 18, 0xee123f57)
            wrapped(caption, r, 20, 0xffffffff, centerVertically: true)
        }
        let answer = engine.answerFor(localId)
        var timer = ""
        if let a = answer, a.remaining > 0 {
            timer = tr("Answer time", "זמן לתשובה") + " · " + String(KotlinNumber.int(ceil(a.remaining))) + "s"
        } else if engine.phase == .ready && engine.serveRequested {
            timer = tr("Serve queued", "ההגשה מוכנה")
        }
        let hint: String
        if engine.practice != nil {
            hint = practiceHint()
        } else if engine.feedbackUntil > engine.clock {
            hint = SportsText.feedback(engine.feedbackEn, engine.feedbackHe, he)
        } else if engine.config.tutorial {
            hint = tutorialHint()
        } else if squash {
            if let a = answer, !a.onServe, a.selected < 0, a.remaining > 0 {
                hint = tr("Solve while the ball slows down. Tap an answer to choose it, then time your return.", "פתרו כשהכדור מואט. הקישו על תשובה לבחירה, ואז תזמנו את החבטה.")
            } else if let a = answer, !a.onServe, a.selected >= 0 {
                hint = engine.effectiveControl == .pro
                    ? tr("Answer chosen. Move close and swipe the ball to that circle.", "התשובה נבחרה. התקרבו והחליקו על הכדור לעבר המעגל.")
                    : tr("Answer chosen. Tap that circle again as the ball reaches your racket.", "התשובה נבחרה. הקישו שוב על המעגל כשהכדור מגיע למחבט.")
            } else if engine.phase == .ready && engine.players[engine.server] !== local && answer != nil {
                hint = tr("Answer now. Your learning point does not depend on your opponent's serve.", "ענו עכשיו. נקודת הלמידה שלכם אינה תלויה בהגשת היריב.")
            } else if engine.effectiveControl == .beginner {
                hint = tr("Your player follows the ball. Tap your wall target as it arrives.", "הדמות עוקבת אחרי הכדור. הקישו על היעד בקיר כשהוא מגיע.")
            } else if engine.effectiveControl == .standard {
                hint = tr("Drag your player into reach. Tap the wall to aim; a floor shot is a fault.", "גררו את הדמות אל הכדור. הקישו על הקיר לכיוון; חבטה לרצפה היא עבירה.")
            } else {
                hint = tr("Move close, then swipe the ball itself. Direction and speed shape your shot.", "התקרבו והחליקו על הכדור עצמו. הכיוון והמהירות קובעים את החבטה.")
            }
        } else {
            hint = volleyHint()
        }
        var tip = wide ? ltrb(side + 8, engine.config.tutorial ? 167 : 111, side + sidePanel - 18, h - 18) : ltrb(14, h - 99, w - 14, h - 22)
        roundRect(c, tip, 15, 0xf2f6fdff)
        if !timer.trimmingCharacters(in: .whitespaces).isEmpty {
            text(timer, tip.midX, tip.minY + 14, 14, 0xff087b88)
            tip = ltrb(tip.minX, tip.minY + 30, tip.maxX, tip.maxY)
        } else {
            tip = ltrb(tip.minX, tip.minY + 7, tip.maxX, tip.maxY)
        }
        tip = ltrb(tip.minX, tip.minY, tip.maxX, tip.maxY - 6)
        wrapped(hint, tip, wide && !squash ? 14 : (wide ? 15 : 16), 0xff193f54)
    }

    private func practiceHint() -> String {
        guard let d = engine.practice else { return "" }
        let base: String
        switch d.stage.skill {
        case .aim, .serve, .paint, .order:
            base = squash ? tr("Tap a golden wall target. Let your ball paint it!", "הקישו על יעד זהוב בקיר. הכדור יצבע אותו!")
                : tr("Tap the golden island to serve. Land inside it.", "הקישו על האי הזהוב להגשה. נחתו בתוכו.")
        case .ret:
            base = squash ? tr("Tap the wall target as the ball reaches your racket.", "הקישו על היעד בקיר כשהכדור מגיע למחבט.")
                : tr("Tap the other court as the ball arrives.", "הקישו על מגרש היריב כשהכדור מגיע.")
        case .move: base = tr("Drag toward the landing ring. Then tap to return.", "גררו לעבר סימן הנחיתה. אז הקישו להחזרה.")
        case .pass: base = tr("Tap your teammate as the ball reaches you.", "הקישו על חבר הקבוצה כשהכדור מגיע אליכם.")
        case .set: base = tr("Double-tap a low ball to set for your teammate.", "געו פעמיים בכדור נמוך כדי להרים לחבר הקבוצה.")
        case .spike: base = tr("Double-tap as the high ball arrives. Jump and spike!", "געו פעמיים כשהכדור הגבוה מגיע. קופצים ומנחיתים!")
        case .block: base = tr("Stand near the net. Tap it as the ball arrives to block.", "עמדו ליד הרשת. הקישו עליה כשהכדור מגיע כדי לחסום.")
        }
        return base + (d.stage.streak ? "\n" + tr("Keep your streak!", "שמרו על הרצף!") : "")
    }

    private func practiceTargets(_ c: CGContext) {
        guard let d = engine.practice else { return }
        if !squash && !d.serve { return }
        let halfDepth = engine.config.halfDepth
        if d.shape {
            let targets = d.targets()
            let middle = pt(project(0.0, -halfDepth, 2.95))
            let fills: [UInt32] = [0xff9be9d3, 0xffffc7da, 0xffc5baff, 0xffa2e3ff]
            for i in targets.indices {
                let a = targets[i]
                let b = targets[(i + 1) % targets.count]
                let pa = pt(project(a.x, -halfDepth, a.y))
                let pb = pt(project(b.x, -halfDepth, b.y))
                c.beginPath()
                c.move(to: middle)
                c.addLine(to: pa)
                c.addLine(to: pb)
                c.closePath()
                c.setFillColor(SportsPalette.cg(d.painted.contains(i) ? fills[i % 4] : 0x1b46889f))
                c.fillPath()
                c.setStrokeColor(SportsPalette.cg(0xff43889c))
                c.setLineWidth(1.5)
                c.strokeLineSegments(between: [pa, pb])
            }
        }
        let colours: [UInt32] = [0xff6be1bf, 0xffffb7cf, 0xffb7abff, 0xff94dfff]
        for (i, t) in d.targets().enumerated() {
            let wall = squash
            let center = wall ? project(t.x, -halfDepth, t.y) : project(t.x, t.y, 0.04)
            let shownRadius = d.shape ? min(d.radius, 0.24) : d.radius
            let left = wall ? project(t.x - shownRadius, -halfDepth, t.y) : project(t.x - shownRadius, t.y, 0.04)
            let top = wall ? project(t.x, -halfDepth, t.y + shownRadius) : project(t.x, t.y - shownRadius, 0.04)
            let rx = max(CGFloat(abs(center.x - left.x)), 8)
            let ry = max(CGFloat(abs(center.y - top.y)), 5)
            let colored = d.painted.contains(i)
            let next = d.stage.skill != .order || i == d.painted.count
            let oval = CGRect(x: CGFloat(center.x) - rx, y: CGFloat(center.y) - ry, width: 2 * rx, height: 2 * ry)
            c.setFillColor(SportsPalette.cg(colored ? colours[i % 4] : (next ? 0xffffd763 : 0xc5ffffff)))
            c.fillEllipse(in: oval)
            c.setStrokeColor(SportsPalette.cg(0xff163f56))
            c.setLineWidth(next && !colored ? 2.5 : 1.3)
            c.strokeEllipse(in: oval)
            if d.shape { text(colored ? "✓" : "\(i + 1)", CGFloat(center.x), CGFloat(center.y), min(16, rx), 0xff163f56) }
        }
    }

    private func tutorialHint() -> String {
        if !squash {
            switch engine.tutorialStage {
            case 0: return tr("Drag your player or tap an empty part of your court to move. Follow the landing ring.", "גררו את הדמות או הקישו על שטח פנוי בצד שלכם לתנועה. עקבו אחר סימן הנחיתה.")
            case 1: return tr("Beginner serve: tap any target in the other team's court. The serve is timed for you.", "הגשת מתחילים: הקישו על יעד בצד היריב. תזמון ההגשה אוטומטי.")
            case 2: return tr("Beginner: move within reach. Low and high contacts happen automatically. Tap a target to choose a pass or attack.", "מתחילים: התקרבו לכדור. חבטות נמוכות וגבוהות אוטומטיות. הקישו על יעד למסירה או להתקפה.")
            case 3: return tr("Standard serve: stand behind the line, watch the automatic toss, and tap while it is above your shoulder. One retry after a miss.", "הגשה רגילה: עומדים מאחורי הקו, צופים בזריקה האוטומטית ומקישים כשהכדור מעל הכתף. ניסיון נוסף אחרי החטאה.")
            case 4: return tr("Standard: move close, then tap a court target at contact. Tap yourself for a smart pass. Double-tap a low ball to set (touch 1 or 2).", "רגיל: התקרבו והקישו בזמן על יעד. הקשה על הדמות למסירה חכמה. הקשה כפולה בכדור נמוך מרימה בנגיעה הראשונה או השנייה.")
            case 5: return tr("Double-tap a high ball to jump and spike. A normal tap cannot reach a high set; wait until it drops. A low third ball cannot be spiked in Standard.", "הקשה כפולה בכדור גבוה לקפיצה והנחתה. הקשה רגילה לא מגיעה להרמה גבוהה; המתינו לירידה. ברגיל אי אפשר להנחית כדור נמוך בנגיעה השלישית.")
            case 6: return tr("Block: move near the net and tap it to jump with both hands up. Timing and Blocking skill matter. A stretched reach may trigger a riskier dive.", "חסימה: התקרבו לרשת והקישו עליה לקפיצה בידיים מורמות. התזמון ומיומנות החסימה חשובים. כדור מעט רחוק מוביל לזינוק מסוכן יותר.")
            default: return tr("Pro: tap to toss, then swipe from the ball within 10 seconds. Swipe up for a high set, down to drive, faster for power. Double-tap a high ball to spike. Net and out are possible.", "מקצועני: הקישו לזריקה ואז החליקו מהכדור בתוך 10 שניות. למעלה להרמה, למטה לחבטה, מהר לעוצמה. הקשה כפולה בכדור גבוה להנחתה. אפשר לפגוע ברשת או בחוץ.")
            }
        }
        switch engine.tutorialStage {
        case 0: return tr("Move: drag your player or tap the floor. Beginner mode will run to the next ball for you.", "תנועה: גררו את הדמות או הקישו על הרצפה. במצב מתחילים הדמות תרוץ לכדור הבא בשבילכם.")
        case 1: return tr("Serve: solve first, then tap the answer circle. The ball will hit your exact wall target.", "הגשה: פתרו ואז הקישו על מעגל התשובה. הכדור יפגע בדיוק ביעד שבחרתם בקיר.")
        case 2: return tr("Beginner: let your player run, then tap the wall as the ball arrives. Correct answers earn learning points, not match points.", "מתחילים: תנו לדמות לרוץ והקישו על הקיר כשהכדור מגיע. תשובות נכונות נותנות נקודות למידה, ולא נקודות משחק.")
        case 3: return tr("Standard: drag your player close, then tap your wall target in time. A floor-first shot is a fault.", "רגיל: גררו את הדמות לכדור ואז הקישו בזמן על היעד בקיר. רצפה לפני הקיר היא עבירה.")
        default: return tr("Pro: move close and swipe the ball itself. Aim your swipe at the wall; swipe faster for more power.", "מקצועני: התקרבו והחליקו על הכדור עצמו. כוונו את ההחלקה לקיר; החלקה מהירה מוסיפה עוצמה.")
        }
    }

    private func reason(_ r: String) -> String {
        switch r {
        case "two_bounces": return tr("Two bounces", "שתי קפיצות")
        case "net": return tr("Into the net", "הכדור פגע ברשת")
        case "out": return tr("Out", "חוץ")
        case "tin": return tr("Below the line", "מתחת לקו")
        case "serve_fault": return tr("Service fault", "הגשה לא תקינה")
        case "floor_before_wall": return tr("Floor before wall", "רצפה לפני הקיר")
        default: return tr("Point!", "נקודה!")
        }
    }

    private func volleyHint() -> String {
        if engine.phase == .ready {
            if engine.players[engine.server] !== local {
                return tr("Get ready to receive. Move toward the landing ring when the serve crosses the net.", "התכוננו לקבלה. התקדמו לסימן הנחיתה כשההגשה עוברת את הרשת.")
            }
            switch engine.volley.serveMode {
            case .beginner: return tr("Tap anywhere in the other team's court to aim your serve.", "הקישו בכל מקום בצד היריב כדי לכוון את ההגשה.")
            case .standard: return tr("Automatic toss: tap your target when the ball is above your shoulder. One retry.", "זריקה אוטומטית: הקישו על היעד כשהכדור מעל הכתף. ניסיון נוסף אחד.")
            case .pro:
                return !engine.volley.toss
                    ? tr("Tap to toss, then swipe the ball to serve. 10 seconds; too soft hits the net, too hard can go out.", "הקישו לזריקה ואז החליקו על הכדור להגשה. 10 שניות; חלש לרשת, חזק עלול לצאת.")
                    : tr("Swipe from the ball now. Direction aims; speed adds power.", "החליקו עכשיו מהכדור. הכיוון מכוון והמהירות מוסיפה עוצמה.")
            }
        }
        if abs(local.p.y) < 1.3 && engine.returnTeam == local.member.team {
            return tr("Tap the net to jump and block. Or move back to receive.", "הקישו על הרשת לקפיצה וחסימה, או חזרו לאחור לקבלה.")
        }
        if engine.returnTeam != local.member.team {
            return tr("Spread out to defend. Watch where the other team sends the ball.", "התפזרו להגנה. שימו לב לאן היריבים שולחים את הכדור.")
        }
        switch engine.effectiveControl {
        case .beginner: return tr("Move to the landing ring. Contact is automatic; tap a court target to aim.", "התקדמו לסימן הנחיתה. החבטה אוטומטית; הקישו על יעד כדי לכוון.")
        case .standard:
            return engine.ball.z > 2.5
                ? tr("High set! Double-tap at the right time to jump and spike, or wait for a lower ball.", "הרמה גבוהה! הקישו פעמיים בזמן לקפיצה והנחתה, או המתינו לכדור נמוך.")
                : tr("Move close. Tap your target as the ball arrives. Double-tap a low first/second ball to set.", "התקרבו. הקישו על היעד כשהכדור מגיע. הקשה כפולה בכדור נמוך ראשון או שני להרמה.")
        case .pro: return tr("Move close, then swipe from the ball. Up lifts, down drives, speed adds power. Double-tap a high ball to spike.", "התקרבו והחליקו מהכדור. למעלה מרים, למטה מנחית, מהר מוסיף עוצמה. הקשה כפולה בכדור גבוה להנחתה.")
        }
    }

    private func celebrate(_ c: CGContext) {
        let t = Float(engine.phaseTime)
        let colors: [UInt32] = [0xffffcf36, 0xffe91e63, 0xff00cddb, 0xffffffff]
        let width = Float(vw)
        let height = Float(vh)
        guard width > 0, height > 0 else { return }
        for i in 0...85 {
            let x = (Float(i) * 73.7).truncatingRemainder(dividingBy: width) + sin(t + Float(i)) * 12
            let y = (t * 100 + Float(i * 47)).truncatingRemainder(dividingBy: height)
            c.saveGState()
            c.translateBy(x: CGFloat(x), y: CGFloat(y))
            c.rotate(by: CGFloat(t * 90 + Float(i) * 17) * .pi / 180)
            c.translateBy(x: CGFloat(-x), y: CGFloat(-y))
            c.setFillColor(SportsPalette.cg(colors[i % 4]))
            c.fill(CGRect(x: CGFloat(x), y: CGFloat(y), width: 4, height: 9))
            c.restoreGState()
        }
    }

    private func netTap(_ x: CGFloat, _ y: CGFloat) -> Bool {
        let a = project(-4.0, 0.0)
        let b = project(4.0, 0.0)
        let top = project(0.0, 0.0, engine.config.netHeight)
        let fx = Float(x)
        let fy = Float(y)
        return fx >= min(a.x, b.x) - 15 && fx <= max(a.x, b.x) + 15 && fy >= top.y - 15 && fy <= max(a.y, b.y) + 15
    }

    // MARK: Touches (Android onTouchEvent)

    /// The touch in court coordinates: the inverse of the reception zoom.
    private func courtPoint(_ t: UITouch) -> CGPoint {
        let p = t.location(in: self)
        let z = CGFloat(zoomFactor)
        let zx = CGFloat(zoomX)
        let zy = CGFloat(zoomY)
        return CGPoint(x: zx + (p.x - zx) / z, y: zy + (p.y - zy) / z)
    }

    private func millis(_ t: UITouch) -> Double { return t.timestamp * 1000 }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard touch == nil, let t = touches.first else { return }
        touch = t
        let p = courtPoint(t)
        downX = p.x
        downY = p.y
        downTime = millis(t)
        dragging = false
        if squash {
            let ballPoint = pt(project(engine.ball.p.x, engine.ball.p.y, engine.ball.z))
            ballAtDown = ballPoint
            let hits = targetRects.indices.filter { !targetRects[$0].isNull && targetRects[$0].contains(p) }
            selected = hits.min { a, b in
                hypot(p.x - targetRects[a].midX, p.y - targetRects[a].midY) < hypot(p.x - targetRects[b].midX, p.y - targetRects[b].midY)
            } ?? -1
            if engine.effectiveControl == .pro && hypot(p.x - ballPoint.x, p.y - ballPoint.y) < 35 {
                gesture = "stroke"
            } else {
                gesture = wallContains(p.x, p.y) ? "wall" : "move"
            }
            wallTap = squashWall(p.x, p.y)
            return
        }
        frozen = camera
        let b = pt(project(engine.ball.p.x, engine.ball.p.y, engine.ball.z))
        ballAtDown = b
        let pro = engine.phase == .ready ? engine.volley.serveMode == .pro : engine.effectiveControl == .pro
        gesture = pro && hypot(p.x - b.x, p.y - b.y) < 45 ? "volleyStroke" : "move"
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touch, touches.contains(t) else { return }
        let p = courtPoint(t)
        if squash {
            if hypot(p.x - downX, p.y - downY) > 8 { dragging = true }
            if dragging && gesture == "move" {
                let g = squashGround(p.x, p.y)
                send("move", g.x, g.y, 0.0)
            }
            return
        }
        if hypot(p.x - downX, p.y - downY) > 10 {
            dragging = true
            cancelPendingTap()
        }
        if dragging && gesture == "move" {
            let g = frozen.ground(Float(p.x), Float(p.y), iw, ih)
            send("move", g.x, g.y, 0.0)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touch, touches.contains(t) else { return }
        touch = nil
        let p = courtPoint(t)
        let time = millis(t)
        if squash {
            squashUp(p, time)
        } else {
            volleyUp(p, time)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touch, touches.contains(t) else { return }
        touch = nil
        dragging = false
        if squash {
            gesture = ""
        } else {
            cancelPendingTap()
        }
    }

    private func squashUp(_ p: CGPoint, _ time: Double) {
        let server = engine.players[engine.server] === local
        switch gesture {
        case "wall":
            if !dragging {
                if selected >= 0 {
                    local.chosen = selected
                    send("answer", Double(selected), 0.0, 0.5)
                }
                if engine.effectiveControl != .pro && (engine.phase != .ready || server) {
                    let target = selected >= 0 ? Vec(engine.targetX(selected), engine.targetZ(selected)) : wallTap
                    send("wall", target.x, target.y, 0.5)
                }
            }
        case "stroke":
            if dragging {
                let distance = Double(hypot(p.x - downX, p.y - downY))
                let speed = distance / max(30.0, time - downTime)
                let power = min(max(speed / 2.5, 0.0), 1.0)
                let target = squashWall(p.x, p.y)
                send("stroke", target.x, target.y, power)
            }
        default:
            if !dragging {
                let g = squashGround(p.x, p.y)
                let reachable = (engine.ball.p - local.p).length() < 1.5 && engine.ball.z < 2.1
                    && !(engine.config.tutorial && engine.tutorialStage == 0) && engine.countdown <= 0
                if engine.effectiveControl != .pro && reachable && ((engine.phase == .rally && engine.canReturn(local)) || (engine.phase == .ready && server)) {
                    send("floor", g.x, g.y, 0.5)
                } else {
                    send("move", g.x, g.y, 0.0)
                }
            }
        }
    }

    private func volleyUp(_ p: CGPoint, _ time: Double) {
        if hypot(p.x - downX, p.y - downY) > 10 {
            dragging = true
            cancelPendingTap()
        }
        let g = frozen.ground(Float(p.x), Float(p.y), iw, ih)
        if dragging && gesture == "volleyStroke" {
            let from = frozen.ground(Float(downX), Float(downY), iw, ih)
            let dir = Vec(g.x - from.x, g.y - from.y).unit()
            let dx = p.x - downX
            let dy = p.y - downY
            let speed = Double(hypot(dx, dy)) / max(35.0, time - downTime)
            let kind = abs(dy) > abs(dx) * 0.65 ? (dy < 0 ? "volley_up" : "volley_down") : "volley_swipe"
            send(kind, dir.x, dir.y, min(max(speed / 2.8, 0.0), 1.0))
        } else if !dragging {
            if pendingVolleyTap != nil && time - pendingTapAt < 240 && hypot(p.x - pendingTapPoint.x, p.y - pendingTapPoint.y) < 48 {
                cancelPendingTap()
                send("volley_spike", g.x, g.y, 0.8)
            } else {
                if let previous = pendingVolleyTap {
                    pendingVolleyTap = nil
                    previous.run()
                }
                pendingTapAt = time
                pendingTapPoint = p
                let foot = pt(project(local.p.x, local.p.y))
                let own = hypot(p.x - foot.x, p.y - foot.y) < 45
                let tapX = p.x
                let tapY = p.y
                tapSerial += 1
                let id = tapSerial
                pendingVolleyTap = (id, { [weak self] in self?.volleyTap(g, own, tapX, tapY) })
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 210_000_000)
                    self?.firePendingTap(id)
                }
            }
        }
    }

    private func volleyTap(_ g: GroundPoint, _ own: Bool, _ tapX: CGFloat, _ tapY: CGFloat) {
        if engine.phase == .ready && engine.players[engine.server] === local {
            send(own ? "volley_auto" : "volley_tap", g.x, g.y, 0.5)
        } else if abs(local.p.y) < 1.3 && (abs(g.y) < 0.8 || netTap(tapX, tapY)) {
            send("volley_block", g.x, g.y, 0.5)
        } else if (engine.ball.p - local.p).length() < 2.2 && engine.returnTeam == local.member.team {
            send(own ? "volley_auto" : "volley_tap", g.x, g.y, 0.5)
        } else {
            send("move", g.x, g.y, 0.0)
        }
    }
}
