import UIKit

/// Android ARGB int (0xAARRGGBB) as a UIColor.
func argbColor(_ value: UInt32) -> UIColor {
    let a = CGFloat((value >> 24) & 0xff) / 255
    let r = CGFloat((value >> 16) & 0xff) / 255
    let g = CGFloat((value >> 8) & 0xff) / 255
    let b = CGFloat(value & 0xff) / 255
    return UIColor(red: r, green: g, blue: b, alpha: a)
}

/// `hypot` on CGFloat values, computed in Double.
func distance2D(_ dx: CGFloat, _ dy: CGFloat) -> CGFloat {
    return CGFloat(hypot(Double(dx), Double(dy)))
}

/// Monotonic milliseconds (Android `SystemClock.uptimeMillis()`).
func uptimeMs() -> Int64 {
    return Int64(ProcessInfo.processInfo.systemUptime * 1000)
}

/// Android `postDelayed`: runs on the main thread after `seconds`; cancel the returned item to remove it.
@MainActor func afterDelay(_ seconds: Double, _ action: @escaping @MainActor () -> Void) -> DispatchWorkItem {
    let item = DispatchWorkItem {
        MainActor.assumeIsolated { action() }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    return item
}

@MainActor private final class DisplayLinkProxy: NSObject {
    weak var target: ArenaView?

    @objc func step(_ link: CADisplayLink) {
        target?.frameTick()
    }
}

/// Draws the arena every frame (Android `onDraw`), into a transparent layer above the world renderer.
private final class ArenaCanvas: UIView {
    var renderer: ((CGContext, CGRect) -> Void)?

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        renderer?(ctx, bounds)
    }
}

/// Android `AmuduView`: the camera-projected arena over the world renderer, HUD, stable name tags, lighting, the frame
/// loop and the exact touch arbitration (190 ms double tap, held catch, drag to run, swipe toss/throw). Sizes are in
/// points (Android dp). A view wider than tall uses Android's landscape layout (side column + wide court).
final class ArenaView: UIView {
    let engine: AmuduEngine
    let ownId: String
    let art: ArtStore
    let hebrew: Bool
    /// Android `rankPoints`: the local player's colour-rank total; their own name tag uses that rank's colours.
    var rankPoints = 0
    /// Android `receptionZoomEnabled` / `followHumanZoomEnabled` (Settings & feedback switches).
    var receptionZoomEnabled = true
    var followHumanZoomEnabled = true
    private let receptionZoom = SpudReceptionZoom()
    func receptionZoomAmount() -> Double { return receptionZoom.amount }
    private(set) var receptionBallLocatorVisible = false
    /// Android `sceneReady`: a practice starts only after the world's first frame.
    var sceneReady: Bool
    var onRotate: (@MainActor () -> Void)?
    var onBack: (@MainActor () -> Void)?
    var onResult: (@MainActor (Outcome) -> Void)?
    var onHuddle: (@MainActor () -> Void)?
    var onReturnVote: (@MainActor () -> Void)?
    var onStatus: (@MainActor () -> Void)?
    var onChoose: (@MainActor (GameActor) -> Void)?
    var onRoster: (@MainActor () -> Void)?
    var onSay: (@MainActor () -> Void)?
    var onEvent: (@MainActor (GameEvent) -> Void)?
    var sendCommand: (@MainActor (GameCommand) -> Void)?
    var remote = false
    var remoteUpdate: (@MainActor () -> Void)?
    /// Android `networkWaiting`: the room's connection is lost (or a guest's snapshots stopped); play is frozen.
    var networkWaiting = false

    /// Shown only when Metal is unavailable (Android always has the world renderer).
    private let backgroundView = UIImageView()
    private let world = ArenaWorldView(frame: .zero)
    private let canvas = ArenaCanvas()
    private var link: CADisplayLink?
    private let proxy = DisplayLinkProxy()
    private(set) var running = false
    private var lastMs: Int64 = 0
    private var eventCursor: Int
    private var shownResult = false
    private var shownHuddle = -1
    private var shownReturn = -1
    private var shownStatus = -1
    private var lastSize = CGSize.zero
    private(set) var actorRects: [String: CGRect] = [:]
    private(set) var handPoints: [String: CGPoint] = [:]
    /// Android `tagRects` (a LinkedHashMap): name-tag rectangles in drawing order, own tag first.
    private(set) var tagRects: [(String, CGRect)] = []
    private let stableLabels = StableLabels()
    private var aimedAt: String?
    private var playerCamera = false
    private(set) var arenaCamera: ArenaCamera
    private var normalCamera: ArenaCamera
    private var cameraAt: Int64 = 0
    private var gestureCamera: ArenaCamera?
    private var gestureOrigin: V?
    private var activeTouches = Set<UITouch>()
    private var pointer: UITouch?
    private var startX: CGFloat = 0
    private var startY: CGFloat = 0
    private var startAt: Int64 = 0
    private var dragged = false
    private var gesture = ""
    private var heldCatch: DispatchWorkItem?
    private var catchCommitted = false
    private var secondTap = false
    private var pendingTap: DispatchWorkItem?
    private var pendingTapAction: (@MainActor () -> Void)?
    private var tapAt: Int64 = 0
    private var tapX: CGFloat = 0
    private var tapY: CGFloat = 0
    private(set) var backRect = CGRect.zero
    private(set) var rotateRect = CGRect.zero
    private(set) var shoutRect = CGRect.zero
    private(set) var chatRect = CGRect.zero
    private(set) var returnRect = CGRect.zero
    private(set) var cameraRect = CGRect.zero
    private(set) var rosterRect = CGRect.zero
    private(set) var jumpRect = CGRect.zero
    private var practiceObstacle: CGRect?

    private struct Tag {
        let actor: GameActor
        let text: String
        let base: CGPoint
        let width: CGFloat
    }

    private var tags: [Tag] = []
    private var cachedLayouts: [String: (NSAttributedString, CGFloat)] = [:]

    init(engine: AmuduEngine, ownId: String, art: ArtStore, hebrew: Bool) {
        self.engine = engine
        self.ownId = ownId
        self.art = art
        self.hebrew = hebrew
        eventCursor = engine.events.map { $0.id }.max() ?? 0
        // Android: ArenaCamera(width / 2, depth / 2, if (PRO_EDITION) 24.0 else 34.0); this is the standard edition.
        let camera = ArenaCamera(x: engine.config.width / 2, y: engine.config.depth / 2, distance: 34.0)
        arenaCamera = camera
        normalCamera = camera
        sceneReady = engine.practice == nil
        super.init(frame: .zero)
        isMultipleTouchEnabled = true
        semanticContentAttribute = .forceLeftToRight
        backgroundColor = argbColor(0xff10263c)
        backgroundView.image = art.scene(engine.config.scene)
        backgroundView.contentMode = .scaleAspectFill
        backgroundView.clipsToBounds = true
        backgroundView.isUserInteractionEnabled = false
        backgroundView.isHidden = world.ready
        canvas.isOpaque = false
        canvas.backgroundColor = .clear
        canvas.contentMode = .redraw
        canvas.isUserInteractionEnabled = false
        addSubview(backgroundView)
        addSubview(world)
        addSubview(canvas)
        proxy.target = self
        canvas.renderer = { [weak self] ctx, area in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.render(ctx, area)
            }
        }
        isAccessibilityElement = true
        accessibilityLabel = GameText.t("Amudu playing arena")
    }

    required init?(coder: NSCoder) {
        return nil
    }

    /// Android `ArenaWorldView.onFirstFrame` (the world view belongs to this view on iOS).
    var onFirstFrame: (@MainActor () -> Void)? {
        get { return world.onFirstFrame }
        set { world.onFirstFrame = newValue }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        backgroundView.frame = bounds
        world.frame = bounds
        canvas.frame = bounds
        if bounds.size != lastSize {
            // Android `onSizeChanged` (also a rotation).
            lastSize = bounds.size
            cancelInput()
            stableLabels.clear()
            tagRects.removeAll()
            cachedLayouts.removeAll()
            actorRects.removeAll()
            handPoints.removeAll()
            cameraAt = 0
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // Drawn content is redrawn every frame; two pixels per point keeps it sharp without overloading older phones.
        let scale = max(traitCollection.displayScale, 1)
        canvas.contentScaleFactor = min(scale, 2)
    }

    // MARK: Layout (Android `wide`, `sideWidth`, `fieldLeft/Top/Bottom`)

    private var wide: Bool { return bounds.width > bounds.height }

    private var sideWidth: CGFloat { return min(max(bounds.width * 0.23, 158), 210) }

    private func fieldLeft() -> CGFloat { return wide ? sideWidth + 18 : 8 }

    private func fieldTop() -> CGFloat { return wide ? 64 : bounds.height * 0.24 }

    private func fieldBottom() -> CGFloat { return wide ? bounds.height - 12 : bounds.height * 0.845 }

    // MARK: Frame loop

    func start() {
        if running || !sceneReady { return }
        running = true
        lastMs = 0
        let displayLink = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.step(_:)))
        displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        displayLink.add(to: .main, forMode: .common)
        link = displayLink
    }

    func stop() {
        running = false
        link?.invalidate()
        link = nil
        cancelInput()
    }

    func frameTick() {
        if !running { return }
        let now = uptimeMs()
        let ms = lastMs == 0 ? 16 : now - lastMs
        lastMs = now
        if !networkWaiting {
            if !remote {
                engine.tick(Double(ms) / 1000.0)
            } else {
                remoteUpdate?()
            }
        }
        let fresh = engine.events.filter { $0.id > eventCursor }
        for e in fresh {
            eventCursor = e.id
            onEvent?(e)
        }
        if engine.phase == .huddle && shownHuddle != engine.huddleSerial {
            shownHuddle = engine.huddleSerial
            onHuddle?()
        }
        if engine.phase == .returnVote && shownReturn != engine.returnSerial {
            shownReturn = engine.returnSerial
            onReturnVote?()
        }
        if engine.phase == .resolve && engine.statusSerial > 0 && shownStatus != engine.statusSerial {
            shownStatus = engine.statusSerial
            onStatus?()
        }
        if let r = engine.result, !shownResult {
            shownResult = true
            onResult?(r)
        }
        canvas.setNeedsDisplay()
    }

    func command(_ cmd: GameCommand) {
        if let send = sendCommand {
            send(cmd)
        } else {
            engine.command(ownId, UUID().uuidString.lowercased(), cmd)
        }
    }

    private static func trimBang(_ s: String) -> String {
        var t = s
        while t.hasSuffix("!") { t.removeLast() }
        return t
    }

    /// Android `tr`: the localized text with the stop call replaced by this rule set's call (SPUD letters word).
    private func tr(_ en: String, _ he: String) -> String {
        let stop = ArenaView.trimBang(GameText.stopCall())
        let call = ArenaView.trimBang(RuleText.call(engine.config.rules))
        let text = GameText.t(en, he, hebrew: hebrew)
        if stop.isEmpty || stop == call { return text }
        return text.replacingOccurrences(of: stop, with: call)
    }

    // MARK: Camera (Android `updateWorld`, `aimedCamera`, `targetCamera`, `framedCamera`)

    private func updateWorld() {
        let now = uptimeMs()
        let initial = cameraAt == 0
        let dt = initial ? 0.0 : Double(now - cameraAt) / 1000.0
        cameraAt = now
        let base = practiceCamera() ?? aimedCamera() ?? framedCamera(targetCamera())
        normalCamera = base
        let target = receptionCamera(base, dt)
        arenaCamera = initial ? target : arenaCamera.toward(target, min(dt, 0.033))
        let night: Float
        switch engine.config.daylight {
        case .morning: night = 0.15
        case .evening: night = 0.46
        case .night: night = 0.78
        case .noon: night = 0
        }
        world.submit(ArenaFrame(camera: arenaCamera, scene: engine.config.scene.rawValue.lowercased(), width: engine.config.width,
                                depth: engine.config.depth, time: engine.time, night: night))
    }

    /// Android `receptionCamera`: eases toward a close view of a human receiver and the incoming ball.
    private func receptionCamera(_ base: ArenaCamera, _ dt: Double) -> ArenaCamera {
        guard let focus = receptionZoom.step(receptionZoom.incoming(engine, ownId, receptionZoomEnabled, followHumanZoomEnabled), dt) else {
            return base
        }
        let w = Double(bounds.width)
        let h = Double(bounds.height)
        let left = Double(fieldLeft()) + 18
        let right = w - 20
        let top = Double(fieldTop()) + 10
        let bottom = Double(fieldBottom()) - 25
        if w < 1 || h < 1 || right <= left || bottom <= top { return base }
        let receiver = engine.actor(focus.receiver)?.position ?? focus.position
        let ball = receptionZoom.live(focus, engine)
        let nearBall = ball.position
        let middle = receiver * 0.8 + nearBall * 0.2
        var close = base.copy(x: middle.x, y: middle.y, distance: min(base.distance, 16.0), focusHeight: 1.1, centerX: (left + right) / 2.0 / w,
                              centerY: (top + (bottom - top) * 0.58) / h, tilt: 0.68)
        // Fit the receiver's whole body and the actual airborne ball, including tall catches.
        for _ in 0..<110 {
            let points = [close.project(receiver.x, receiver.y, 0.0, w, h), close.project(receiver.x, receiver.y, 4.0, w, h),
                          close.project(nearBall.x, nearBall.y, ball.height, w, h)]
            if points.contains(where: { $0.x < left || $0.x > right || $0.y < top || $0.y > bottom }) {
                close = close.copy(distance: close.distance + 0.35)
            }
        }
        close = close.copy(distance: min(base.distance, close.distance))
        let a = receptionZoom.amount
        return base.copy(x: base.x + (close.x - base.x) * a, y: base.y + (close.y - base.y) * a,
                         distance: base.distance + (close.distance - base.distance) * a,
                         focusHeight: base.focusHeight + (close.focusHeight - base.focusHeight) * a,
                         centerX: base.centerX + (close.centerX - base.centerX) * a, centerY: base.centerY + (close.centerY - base.centerY) * a,
                         tilt: base.tilt + (close.tilt - base.tilt) * a)
    }

    /// Android `practiceCamera`: the smallest distance that shows every actor and the target, head to feet.
    private func practiceCamera() -> ArenaCamera? {
        guard let d = engine.practice else { return nil }
        let positions = engine.actors.map { $0.position } + [d.target]
        let w = Double(bounds.width)
        let h = Double(bounds.height)
        let left = Double(fieldLeft()) + 15
        let right = w - 18
        let top = Double(fieldTop()) + 8
        let bottom = Double(fieldBottom()) - 20
        if w < 1 || h < 1 || right <= left || bottom <= top { return arenaCamera }
        var cam = arenaCamera.copy(x: 8.0, y: 8.0, distance: 12.0, focusHeight: 1.3, centerX: (left + right) / 2.0 / w,
                                   centerY: (top + (bottom - top) * 0.58) / h, tilt: 0.78)
        for _ in 0..<140 {
            let inside = positions.allSatisfy { v in
                [0.0, 4.0].allSatisfy { z in
                    let pt = cam.project(v.x, v.y, z, w, h)
                    return pt.x >= left && pt.x <= right && pt.y >= top && pt.y <= bottom
                }
            }
            if inside { return cam }
            cam = cam.copy(distance: cam.distance + 0.4)
        }
        return cam
    }

    /// While aiming at a tapped player, frame the thrower and that player together.
    private func aimedCamera() -> ArenaCamera? {
        if !engine.canAim(ownId) {
            aimedAt = nil
            return nil
        }
        guard let id = aimedAt, let me = engine.actor(ownId)?.position else { return nil }
        guard let otherActor = engine.actor(id), otherActor.active else { return nil }
        let other = otherActor.position
        let w = Double(bounds.width)
        let h = Double(bounds.height)
        let left = Double(fieldLeft()) + 18
        let right = w - 24
        let top = Double(fieldTop()) + 12
        let bottom = Double(fieldBottom()) - 35
        if right <= left || bottom <= top { return nil }
        let middle = (me + other) * 0.5
        let base = arenaCamera.copy(x: middle.x, y: middle.y, distance: 20.0, focusHeight: 0.0, centerX: (left + right) / 2 / w,
                                    centerY: (top + (bottom - top) * 0.62) / h, tilt: 0.9)
        return LandscapeFraming.fit(base, [(me.x, me.y), (other.x, other.y)], w, h, left, right, top, bottom, 4.2)
    }

    private func targetCamera() -> ArenaCamera {
        let cfg = engine.config
        let me = engine.actor(ownId)?.position ?? V(cfg.width / 2, cfg.depth / 2)
        if engine.phase == .circle && engine.circleFormation && !playerCamera {
            return normalCamera.copy(x: cfg.width / 2, y: cfg.depth / 2, distance: 24.0, focusHeight: 0.0)
        }
        if playerCamera { return normalCamera.copy(x: me.x, y: me.y, distance: 20.0, focusHeight: 0.0) }
        let followed = (engine.phase == .air || engine.phase == .retrieve) ? engine.called : engine.thrower
        let actor = engine.actor(followed)?.position ?? me
        let ball = engine.ball
        let focus: V
        switch engine.phase {
        case .air: focus = ball.vz > 0 ? ball.position : actor * 0.7 + ball.position * 0.3
        case .retrieve: focus = actor * 0.5 + ball.position * 0.5
        case .shout, .aim, .flight: focus = actor * 0.5 + ball.position * 0.5
        default: focus = actor
        }
        let distance: Double
        switch engine.phase {
        case .air: distance = 24.0 + ball.height * 0.48
        case .aim, .shout: distance = 27.0
        default: distance = 24.0
        }
        return normalCamera.copy(x: focus.x, y: focus.y, distance: Kotlin.clamp(distance, 20.0, 40.0),
                                 focusHeight: engine.phase == .air ? ball.height * 0.42 : 0.0)
    }

    private func framedCamera(_ base: ArenaCamera) -> ArenaCamera {
        let w = Double(bounds.width)
        let h = Double(bounds.height)
        let cfg = engine.config
        if !wide {
            let camera = base.copy(centerX: 0.5, centerY: 0.61, tilt: engine.circleFormation ? 0.86 : 1.02)
            if engine.phase == .circle && engine.circleFormation {
                return LandscapeFraming.fit(camera, engine.activeActors.map { ($0.position.x, $0.position.y) }, w, h, 30, w - 30,
                                            Double(fieldTop()), Double(fieldBottom()) - 28, 4.2)
            }
            return camera
        }
        let left = Double(fieldLeft())
        let right = w - 12
        let top = Double(fieldTop())
        let bottom = Double(fieldBottom())
        var camera = base.copy(x: playerCamera ? base.x : cfg.width / 2, y: playerCamera ? base.y : cfg.depth / 2, distance: base.distance * 0.78,
                               focusHeight: playerCamera ? base.focusHeight : 0.0, centerX: (left + right) / 2 / w,
                               centerY: (top + (bottom - top) * 0.52) / h, tilt: 0.68)
        let points: [V]
        if !playerCamera {
            points = [V(0.6, 0.6), V(cfg.width - 0.6, 0.6), V(0.6, cfg.depth - 0.6), V(cfg.width - 0.6, cfg.depth - 0.6)]
        } else if engine.phase == .circle && engine.circleFormation {
            points = engine.activeActors.map { $0.position }
        } else {
            points = []
        }
        if !points.isEmpty {
            camera = LandscapeFraming.fit(camera, points.map { ($0.x, $0.y) }, w, h, left, right, top, bottom, 3.8)
        }
        return camera
    }

    // MARK: Projection

    func project(_ v: V, _ z: Double = 0.0) -> CGPoint {
        let p = arenaCamera.project(v.x, v.y, z, max(Double(bounds.width), 1), max(Double(bounds.height), 1))
        return CGPoint(x: p.x, y: p.y)
    }

    /// A screen drag from the player's feet, mapped onto the ground through the camera of the touch-down moment.
    private func inverseVector(_ dx: CGFloat, _ dy: CGFloat) -> V {
        let cfg = engine.config
        let me = gestureOrigin ?? engine.actor(ownId)?.position ?? V(cfg.width / 2, cfg.depth / 2)
        let camera = gestureCamera ?? arenaCamera
        let w = Double(bounds.width)
        let h = Double(bounds.height)
        let p = camera.project(me.x, me.y, 0.0, w, h)
        let end = camera.ground(p.x + Double(dx), p.y + Double(dy), w, h)
        return V(end.x - me.x, end.y - me.y).unit()
    }

    // MARK: Drawing helpers

    private func font(_ size: CGFloat) -> UIFont {
        return UIFont.boldSystemFont(ofSize: size)
    }

    private func measure(_ s: String, _ size: CGFloat) -> CGFloat {
        return (s as NSString).size(withAttributes: [.font: font(size)]).width
    }

    /// Android `drawText` at a baseline, centered or right-aligned.
    private func text(_ s: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ color: UInt32 = 0xffffffff, right: Bool = false) {
        let f = font(size)
        let attributes: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: argbColor(color)]
        let string = s as NSString
        let width = string.size(withAttributes: attributes).width
        let originX = right ? x - width : x - width / 2
        string.draw(at: CGPoint(x: originX, y: y - f.ascender), withAttributes: attributes)
    }

    /// Android `StaticLayout` centered horizontally and vertically in `rect`.
    private func paragraph(_ s: String, _ rect: CGRect, _ size: CGFloat, _ color: UInt32 = 0xffffffff) {
        let w = max(rect.width, 1)
        let key = s + "/" + String(Int(w)) + "/" + String(Double(size)) + "/" + String(color)
        let entry: (NSAttributedString, CGFloat)
        if let cached = cachedLayouts[key] {
            entry = cached
        } else {
            if cachedLayouts.count > 90 { cachedLayouts.removeAll() }
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            style.baseWritingDirection = .natural
            style.lineBreakMode = .byWordWrapping
            let attributed = NSAttributedString(string: s, attributes: [.font: font(size), .foregroundColor: argbColor(color), .paragraphStyle: style])
            let bounding = attributed.boundingRect(with: CGSize(width: w, height: CGFloat.greatestFiniteMagnitude),
                                                   options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
            entry = (attributed, ceil(bounding.height))
            cachedLayouts[key] = entry
        }
        let target = CGRect(x: rect.minX, y: rect.minY + (rect.height - entry.1) / 2, width: w, height: entry.1)
        entry.0.draw(with: target, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
    }

    private func panel(_ ctx: CGContext, _ r: CGRect, _ color: UInt32 = 0xe6173049) {
        ctx.setFillColor(argbColor(color).cgColor)
        ctx.addPath(UIBezierPath(roundedRect: r, cornerRadius: 18).cgPath)
        ctx.fillPath()
    }

    private func line(_ ctx: CGContext, _ a: CGPoint, _ b: CGPoint, _ color: UInt32, _ width: CGFloat) {
        ctx.setStrokeColor(argbColor(color).cgColor)
        ctx.setLineWidth(width)
        ctx.setLineCap(.round)
        ctx.move(to: a)
        ctx.addLine(to: b)
        ctx.strokePath()
    }

    private func radialGradient(_ colors: [UInt32], _ locations: [CGFloat]) -> CGGradient? {
        let cgColors = colors.map { argbColor($0).cgColor } as CFArray
        return CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cgColors, locations: locations)
    }

    private func fillRadial(_ ctx: CGContext, _ center: CGPoint, _ radius: CGFloat, _ colors: [UInt32], _ locations: [CGFloat]) {
        guard radius > 0, let gradient = radialGradient(colors, locations) else { return }
        ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
    }

    // MARK: Frame

    private func render(_ ctx: CGContext, _ rect: CGRect) {
        let width = rect.width
        let height = rect.height
        if width <= 1 || height <= 1 { return }
        updateWorld()
        let cfg = engine.config
        // Painted field outline and a circle are grounded in the same projection as actors.
        let corners = [V(0.5, 0.5), V(cfg.width - 0.5, 0.5), V(cfg.width - 0.5, cfg.depth - 0.5), V(0.5, cfg.depth - 0.5)].map { project($0) }
        ctx.setLineCap(.butt)
        ctx.setStrokeColor(argbColor(0x60ffffff).cgColor)
        ctx.setLineWidth(1.5)
        ctx.move(to: corners[0])
        for p in corners.dropFirst() { ctx.addLine(to: p) }
        ctx.closePath()
        ctx.strokePath()
        if engine.phase == .circle && engine.circleFormation {
            for i in 0...64 {
                let a = Double(i) * 2 * Double.pi / 64
                let pt = project(V(cfg.width / 2 + cos(a) * 4.5, cfg.depth / 2 + sin(a) * 4.5))
                if i == 0 { ctx.move(to: pt) } else { ctx.addLine(to: pt) }
            }
            ctx.setStrokeColor(argbColor(0x99ffffff).cgColor)
            ctx.setLineWidth(2)
            ctx.strokePath()
        }
        if engine.phase == .air {
            let p = project(engine.landing)
            ctx.setStrokeColor(argbColor(0x66fff06a).cgColor)
            ctx.setLineWidth(3)
            ctx.strokeEllipse(in: CGRect(x: p.x - 23, y: p.y - 10, width: 46, height: 20))
        }
        drawPractice(ctx)
        actorRects.removeAll()
        handPoints.removeAll()
        tags.removeAll()
        let loose = engine.ball.holder == nil
        if loose { drawBallShadow(ctx, width, height) }
        var ballDrawn = false
        let ordered = Kotlin.stableSorted(engine.activeActors) { $0.position.y < $1.position.y }
        for a in ordered {
            if loose && !ballDrawn && engine.ball.position.y < a.position.y {
                drawFlyingBall(ctx, width, height)
                ballDrawn = true
            }
            drawActor(ctx, a, width, height)
        }
        if loose && !ballDrawn { drawFlyingBall(ctx, width, height) }
        // Kotlin draws every practice ball that is not the engine's ball object; flights have unique IDs.
        if let practice = engine.practice {
            for shot in practice.shots where shot.ball.flightId != engine.ball.flightId {
                drawFlyingBall(ctx, width, height, shot.ball)
            }
        }
        // During reception zoom, show a translucent locator at the actual ball position
        // if a nearer avatar hides it. This is presentation only: no catch radius or physics change.
        receptionBallLocatorVisible = false
        if loose && receptionZoom.amount > 0.1 && receptionZoom.incoming(engine, ownId, receptionZoomEnabled, followHumanZoomEnabled) != nil {
            let ball = engine.ball
            let point = project(ball.position, ball.height)
            let size = min(width, height) * 0.067 * CGFloat(engine.config.ball.visualScale)
            let hidden = engine.activeActors.contains { actor in
                actor.position.y > ball.position.y && (actorRects[actor.member.id]?.contains(point) ?? false)
            }
            if hidden {
                receptionBallLocatorVisible = true
                let r = size * 0.62
                ctx.setStrokeColor(argbColor(0xffbafff4).cgColor)
                ctx.setLineWidth(2)
                ctx.strokeEllipse(in: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2))
                art.ball(engine.config.ball).draw(in: CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size),
                                                  blendMode: .normal, alpha: 195.0 / 255.0)
            }
        }
        // Arena lighting of the ground is drawn by the world renderer; this tints the actors, not the HUD.
        drawLighting(ctx, width, height)
        drawAim(ctx, rect)
        drawTags(ctx, width, height)
        drawHud(ctx, width, height)
    }

    /// Android `drawPractice`: the tree, ring or island target, the partner's star, the cue above each thrower and the
    /// landing marker of an incoming pass.
    private func drawPractice(_ ctx: CGContext) {
        practiceObstacle = nil
        guard let d = engine.practice else { return }
        let t = d.target
        let skill = d.stage.skill
        if skill == .ring || skill == .ground || skill == .tree || skill == .rebound {
            if skill == .tree || skill == .rebound {
                let ground = project(t)
                let top = project(t, 3.3)
                let left = project(V(t.x - 0.65, t.y))
                let right = project(V(t.x + 0.65, t.y))
                let rw = (right.x - left.x) * 0.5
                let height = ground.y - top.y
                ctx.setFillColor(argbColor(0x5540291b).cgColor)
                ctx.fillEllipse(in: CGRect(x: ground.x - rw * 1.5, y: ground.y - 9, width: rw * 3, height: 19))
                let trunk = CGMutablePath()
                trunk.move(to: CGPoint(x: ground.x - rw, y: ground.y))
                trunk.addLine(to: CGPoint(x: top.x - rw * 0.65, y: top.y))
                trunk.addLine(to: CGPoint(x: top.x + rw * 0.65, y: top.y))
                trunk.addLine(to: CGPoint(x: ground.x + rw, y: ground.y))
                trunk.closeSubpath()
                let bark = [argbColor(0xff67412b).cgColor, argbColor(0xffb5814e).cgColor, argbColor(0xff72432a).cgColor] as CFArray
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: bark, locations: [0, 0.5, 1]) {
                    ctx.saveGState()
                    ctx.addPath(trunk)
                    ctx.clip()
                    ctx.drawLinearGradient(gradient, start: CGPoint(x: left.x, y: top.y), end: CGPoint(x: right.x, y: top.y),
                                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
                    ctx.restoreGState()
                }
                ctx.setStrokeColor(argbColor(0xff67452f).cgColor)
                ctx.setLineWidth(1.5)
                ctx.setLineCap(.round)
                for i in -2...2 {
                    let x = ground.x + CGFloat(i) * rw * 0.25
                    ctx.move(to: CGPoint(x: x, y: ground.y - 6))
                    ctx.addCurve(to: CGPoint(x: x, y: top.y + 4), control1: CGPoint(x: x - rw * 0.16, y: ground.y - height * 0.3),
                                 control2: CGPoint(x: x + rw * 0.16, y: ground.y - height * 0.6))
                    ctx.strokePath()
                }
                let leaves: [UInt32] = [0xff246a50, 0xff35865d, 0xff53a76a, 0xff6abd79]
                for i in 0...6 {
                    let dx = CGFloat(i % 3 - 1) * rw * 0.75
                    let dy: CGFloat = i < 3 ? -rw * 0.9 : (i < 6 ? -rw * 0.1 : -rw * 1.5)
                    ctx.setFillColor(argbColor(leaves[i % 4]).cgColor)
                    ctx.fillEllipse(in: CGRect(x: top.x + dx - rw, y: top.y + dy - rw * 0.65, width: rw * 2, height: rw * 1.2))
                }
                ctx.setFillColor(argbColor(0xffa9dc83).cgColor)
                for i in 0...5 {
                    let x = top.x + CGFloat(i % 3 - 1) * rw * 0.7
                    let y = top.y - rw * (0.9 + CGFloat(i / 3) * 0.4)
                    ctx.fillEllipse(in: CGRect(x: x, y: y, width: rw * 0.22, height: rw * 0.1))
                }
            }
            let isGround = skill == .ground
            let radius = (skill == .tree || skill == .rebound) ? 0.5 : d.radius
            let path = CGMutablePath()
            for i in 0...48 {
                let angle = Double(i) * 2 * Double.pi / 48
                let point = V(t.x + cos(angle) * radius, t.y + (isGround ? sin(angle) * radius : 0.0))
                let pt = project(point, isGround ? 0.24 : d.targetHeight + sin(angle) * radius)
                if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }
            path.closeSubpath()
            practiceObstacle = path.boundingBoxOfPath.insetBy(dx: -5, dy: -5)
            ctx.setLineCap(.butt)
            ctx.setStrokeColor(argbColor(0xff173f55).cgColor)
            ctx.setLineWidth(8)
            ctx.addPath(path)
            ctx.strokePath()
            ctx.setStrokeColor(argbColor(engine.time - d.lastSuccess < 0.6 ? 0xffa5ffd7 : 0xffffdf70).cgColor)
            ctx.setLineWidth(4)
            ctx.addPath(path)
            ctx.strokePath()
        }
        if d.stage.cooperative {
            let at = project(d.partner(engine).position, 3.8)
            text("★", at.x, at.y, 23, 0xffffdf70)
        }
        if d.releaseAt > engine.time {
            for id in d.cue {
                guard let a = engine.actor(id) else { continue }
                let at = project(a.position, 3.7)
                let cue: String
                if d.stage.defence {
                    cue = d.cueHigh ? tr("DUCK ↓", "להתכופף ↓") : tr("JUMP ↑", "לקפוץ ↑")
                } else {
                    cue = tr("Ready!", "מוכנים!")
                }
                text(cue, at.x, at.y, 15, 0xffffdf70)
            }
        }
        if d.shots.contains(where: { $0.incoming }) && !d.stage.defence {
            let pt = project(engine.landing)
            ctx.setStrokeColor(argbColor(0xffa4ffdc).cgColor)
            ctx.setLineWidth(3)
            ctx.strokeEllipse(in: CGRect(x: pt.x - 18, y: pt.y - 7, width: 36, height: 14))
        }
    }

    /// Android `practiceInstruction`: the briefing names the lesson and the top HUD shows goal and hearts, so the live
    /// coach names only the gesture (it fits even short landscape screens).
    func practiceInstruction(_ d: SpudPractice) -> String {
        if d.stage.skill == .freeze {
            return d.freezeReady ? tr("SPUD · stay still", "עמודו · עצרו במקום") : tr("RUN · drag to move", "רוצו · גררו לתנועה")
        }
        if d.stage.skill == .call {
            return tr("Tap the starred partner, then swipe up from your ball", "געו בשותף המסומן ואז החליקו מעלה מהכדור")
        }
        if d.stage.defence {
            switch d.stage.skill {
            case .duck: return tr("Double-tap to duck", "נגיעה כפולה לכיפוף")
            case .jump: return tr("Tap Jump at the right moment", "געו בקפיצה ברגע הנכון")
            case .move: return tr("Drag to move aside", "גררו כדי לזוז הצדה")
            default: return tr("Move, jump or duck", "זוזו, קפצו או התכופפו")
            }
        }
        if engine.ball.holder == ownId {
            return tr("Tap a target to aim · swipe from your ball to throw", "נגיעה במטרה לכיוון · החלקה מהכדור לזריקה")
        }
        return tr("Drag into position · tap or hold to catch", "גררו למקום · געו או החזיקו לתפיסה")
    }

    /// The aim line, kept off every character (Android `clipOutRect` of each actor).
    private func drawAim(_ ctx: CGContext, _ area: CGRect) {
        guard engine.canAim(ownId), let mine = engine.actor(ownId) else { return }
        ctx.saveGState()
        for body in actorRects.values {
            ctx.addRect(area)
            ctx.addRect(body)
            ctx.clip(using: .evenOdd)
        }
        let origin = handPoints[ownId] ?? project(mine.position, 1.2)
        let end = project(mine.position + mine.direction * 4.5, 1.1)
        ctx.setStrokeColor(argbColor(0xffffe466).cgColor)
        ctx.setLineWidth(3)
        ctx.setLineCap(.round)
        ctx.setLineDash(phase: 0, lengths: [8, 6])
        ctx.move(to: origin)
        ctx.addLine(to: end)
        ctx.strokePath()
        ctx.setLineDash(phase: 0, lengths: [])
        ctx.strokeEllipse(in: CGRect(x: end.x - 12, y: end.y - 12, width: 24, height: 24))
        ctx.restoreGState()
    }

    private func drawHud(_ ctx: CGContext, _ width: CGFloat, _ height: CGFloat) {
        let mine = engine.actor(ownId)
        let cfg = engine.config
        let rules = cfg.rules
        let top = CGRect(x: 12, y: 7, width: width - 24, height: (wide ? 53 : 62) - 7)
        panel(ctx, top)
        backRect = CGRect(x: top.minX, y: top.minY, width: 52, height: top.height)
        rotateRect = CGRect(x: backRect.maxX + 2, y: top.minY, width: 48, height: top.height)
        panel(ctx, rotateRect, 0xe01b5668)
        text("↻", rotateRect.midX, rotateRect.midY + 8, 26)
        let cx = backRect.midX
        let cy = backRect.midY
        line(ctx, CGPoint(x: cx + 5, y: cy - 9), CGPoint(x: cx - 5, y: cy), 0xff7effe2, 4)
        line(ctx, CGPoint(x: cx - 5, y: cy), CGPoint(x: cx + 5, y: cy + 9), 0xff7effe2, 4)
        let turnText: String
        if let practice = engine.practice {
            turnText = "\(practice.successes) / \(practice.goal)"
        } else if cfg.turns == 0 {
            turnText = tr("Turn \(engine.turn) · ∞", "תור \u{2066}\(engine.turn) · ∞\u{2069}")
        } else {
            turnText = tr("Turn \(engine.turn) / \(cfg.turns)", "תור \u{2066}\(engine.turn) / \(cfg.turns)\u{2069}")
        }
        text(turnText, width / 2, top.midY + 6, 17)
        let scoreText: String
        if let practice = engine.practice {
            scoreText = "♥ \(3 - practice.mistakes)"
        } else {
            scoreText = mine.map { RuleText.score($0, rules) } ?? "—"
        }
        text(scoreText, top.maxX - 15, top.midY + 6, 17, 0xffffc6cb, right: true)
        var instructionText = instruction()
        let seconds = engine.countdownSeconds()
        if seconds >= 0 && seconds <= 5 {
            instructionText += "\n" + (engine.actor(engine.actionActor).map { RuleText.name($0, ownId) } ?? "") + " · " + String(seconds)
        }
        if engine.phase == .aim && engine.thrower == ownId && cfg.stepsAfterCall > 0 {
            let steps = engine.stepRemaining / (min(cfg.width, cfg.depth) * cfg.stepLengthFraction)
            instructionText += "\n" + RuleText.format(RuleText["stepsLeft"], steps)
        }
        let instructionBox = wide ? CGRect(x: 12, y: 64, width: sideWidth - 12, height: max(height - 132 - 64, 1))
            : CGRect(x: 14, y: 72, width: width - 28, height: max(height * 0.215 - 72, 1))
        panel(ctx, instructionBox, 0xd9163049)
        paragraph(instructionText, instructionBox, 16)
        if engine.phase == .shout && engine.called == ownId {
            shoutRect = wide ? CGRect(x: 12, y: height - 122, width: sideWidth - 12, height: 52)
                : CGRect(x: width * 0.2, y: height * 0.86, width: width * 0.6, height: height * 0.08)
            panel(ctx, shoutRect, 0xffffe05e)
            text(RuleText.call(rules), shoutRect.midX, shoutRect.midY + 9, 26, 0xff173047)
        } else {
            shoutRect = .zero
            let status: String
            if engine.practice != nil {
                status = tr("Practice at your own pace · progress is saved", "מתאמנים בקצב שלכם · ההתקדמות נשמרת")
            } else if engine.time < engine.infoUntil {
                status = feedbackText()
            } else {
                status = tr("Drag to run · Tap / hold to catch\nDouble-tap to duck", "גררו כדי לרוץ · נגיעה או לחיצה לתפיסה\nנגיעה כפולה להתכופפות")
            }
            let r = wide ? CGRect(x: 12, y: height - 122, width: sideWidth - 12, height: 56)
                : CGRect(x: 12, y: height * 0.865, width: width - 24, height: height * 0.946 - height * 0.865)
            // In landscape the thrower's "Choose player" button takes this place.
            if !(wide && engine.phase == .circle && engine.thrower == ownId) {
                panel(ctx, r)
                paragraph(status, r, 14)
            }
        }
        returnRect = .zero
        if let mine, !mine.active {
            shoutRect = .zero
            let box = wide ? CGRect(x: 12, y: height - 122, width: sideWidth - 12, height: 56)
                : CGRect(x: 12, y: height * 0.855, width: width - 24, height: height * 0.947 - height * 0.855)
            let canRequest = rules == .nicknames && mine.returnAttempts < cfg.returnAttemptLimit && !mine.returnQueued && engine.returnTarget != ownId
            let label: String
            if rules == .spud {
                label = RuleText["spudOut"]
            } else if mine.returnQueued || engine.returnTarget == ownId {
                label = RuleText["queued"]
            } else if !canRequest {
                label = RuleText["noRequests"]
            } else {
                label = RuleText["askReturn"]
            }
            panel(ctx, box, canRequest ? 0xffe91e63 : 0xff173047)
            paragraph(label, box, 16)
            returnRect = canRequest ? box : .zero
        }
        cameraRect = CGRect(x: 12, y: height - (wide ? 60 : 39), width: (wide ? sideWidth - 49 : width - 70) - 12, height: wide ? 48 : 36)
        if engine.practice == nil {
            panel(ctx, cameraRect, 0xe01b5668)
            paragraph(playerCamera ? tr("Your view · switch", "המבט שלכם · החלפה") : tr("Action view · switch", "מבט כללי · החלפה"), cameraRect, 13)
        }
        jumpRect = .zero
        if let d = engine.practice {
            if d.allowsJump {
                var r = cameraRect
                if !wide { r = CGRect(x: r.minX, y: r.maxY - 52, width: r.width, height: 52) }
                jumpRect = r
                panel(ctx, jumpRect, 0xffffdf70)
                paragraph(tr("Jump ↑", "קפיצה ↑"), jumpRect, 18, 0xff173047)
            }
            cameraRect = .zero
        }
        if engine.phase == .circle && engine.thrower == ownId {
            rosterRect = wide ? CGRect(x: 12, y: height - 122, width: sideWidth - 12, height: 48)
                : CGRect(x: width - 137, y: height * 0.235, width: 125, height: 38)
            panel(ctx, rosterRect, 0xee20777c)
            text(tr("Choose player", "בחירת שחקן"), rosterRect.midX, rosterRect.midY + 5, 13)
        } else {
            rosterRect = .zero
        }
        if engine.practice == nil {
            chatRect = wide ? CGRect(x: sideWidth - 44, y: height - 60, width: 44, height: 48) : CGRect(x: width - 57, y: height - 39, width: 45, height: 36)
            panel(ctx, chatRect, 0xc5173049)
            ctx.setFillColor(UIColor.white.cgColor)
            for i in -1...1 {
                let dotX = chatRect.midX + CGFloat(i) * 6
                ctx.fillEllipse(in: CGRect(x: dotX - 1.8, y: chatRect.midY - 1.8, width: 3.6, height: 3.6))
            }
        } else {
            chatRect = .zero
        }
    }

    private func drawLighting(_ ctx: CGContext, _ width: CGFloat, _ height: CGFloat) {
        let daylight = engine.config.daylight
        let area = CGRect(x: 0, y: 0, width: width, height: height)
        switch daylight {
        case .noon:
            return
        case .morning:
            ctx.setFillColor(argbColor(0x3d7c6238).cgColor)
            ctx.fill(area)
            return
        case .evening:
            ctx.setFillColor(argbColor(0x8f202542).cgColor)
            ctx.fill(area)
            return
        case .night:
            break
        }
        let cfg = engine.config
        let lamps = [project(V(0.7, 2.2)), project(V(cfg.width - 0.7, 6.5)), project(V(1.2, cfg.depth - 1.0))]
        var spots: [CGPoint] = []
        for i in 0...2 {
            let x = cfg.width * (0.5 + 0.36 * sin(engine.time * 0.32 + Double(i) * 2.1))
            let y = cfg.depth * (0.52 + 0.36 * cos(engine.time * 0.24 + Double(i) * 2.0))
            spots.append(project(V(x, y)))
        }
        ctx.saveGState()
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.setFillColor(argbColor(0xd10a1329).cgColor)
        ctx.fill(area)
        ctx.setBlendMode(.destinationOut)
        for (i, p) in (lamps + spots).enumerated() {
            let radius = width * (i < 3 ? 0.26 : 0.21)
            fillRadial(ctx, p, radius, [0xddffffff, 0x88ffffff, 0x00ffffff], [0, 0.42, 1])
        }
        ctx.setBlendMode(.normal)
        ctx.endTransparencyLayer()
        ctx.restoreGState()
        for p in lamps {
            line(ctx, p, CGPoint(x: p.x, y: p.y - 60), 0xff667782, 4)
            ctx.setFillColor(argbColor(0xffffe7a0).cgColor)
            ctx.addPath(UIBezierPath(roundedRect: CGRect(x: p.x - 6, y: p.y - 68, width: 12, height: 13), cornerRadius: 3).cgPath)
            ctx.fillPath()
            fillRadial(ctx, CGPoint(x: p.x, y: p.y - 61), 30, [0x99ffe493, 0x00000000], [0, 1])
        }
        let colors: [UInt32] = [0x7756dfff, 0x77f556cd, 0x77bfef69]
        for (i, p) in spots.enumerated() {
            let oval = CGRect(x: p.x - width * 0.20, y: p.y - height * 0.085, width: width * 0.40, height: height * 0.17)
            ctx.saveGState()
            ctx.addEllipse(in: oval)
            ctx.clip()
            fillRadial(ctx, p, width * 0.20, [colors[i], 0x00000000], [0, 1])
            ctx.restoreGState()
            let source = lamps[i]
            ctx.setFillColor(argbColor((colors[i] & 0x00ffffff) | 0x18000000).cgColor)
            ctx.move(to: CGPoint(x: source.x, y: source.y - 60))
            ctx.addLine(to: CGPoint(x: p.x - width * 0.14, y: p.y))
            ctx.addLine(to: CGPoint(x: p.x + width * 0.14, y: p.y))
            ctx.closePath()
            ctx.fillPath()
        }
    }

    /// Android `visible(a)`: "You" for the local player, everyone else by their current (nick)name.
    private func visibleName(_ a: GameActor?) -> String {
        guard let a else { return "" }
        if a.member.id == ownId { return tr("You", "אתם") }
        return a.fullName(hebrew: hebrew)
    }

    /// Android `instruction()`.
    func instruction() -> String {
        if networkWaiting { return RuleText["connectionLost"] }
        if let practice = engine.practice { return practiceInstruction(practice) }
        let owner = engine.actor(engine.thrower)
        let target = engine.actor(engine.called)
        if engine.sharedPause { return tr("Your game is paused.", "המשחק מושהה.") }
        if engine.actor(ownId)?.active == false && engine.phase != .returnVote { return RuleText["spectating"] }
        switch engine.phase {
        case .circle:
            if engine.thrower == ownId {
                if Kotlin.isBlank(engine.selected) {
                    return tr("Choose a player.\nThen swipe your ball upward!", "בחרו שחקן.\nואז החליקו את הכדור שלכם כלפי מעלה!")
                }
                return tr("Swipe up from your ball.\nFaster swipe → higher throw!", "החליקו מעלה מהכדור שלכם.\nהחלקה מהירה → זריקה גבוהה!")
            }
            let name = visibleName(owner)
            return tr("\(name) is choosing who to call.", "הגיע התור של \(name) לבחור למי לקרוא.")
        case .air:
            if engine.called == ownId {
                return tr("Your ball! Run to the landing ring.\nTap or hold briefly as it comes down.", "הכדור שלכם! רוצו לטבעת הנחיתה.\nגעו או לחצו קצרות כשהכדור יורד.")
            }
            let name = visibleName(target)
            return tr("Run! \(name) is trying to catch.", "רוצו! עכשיו התור של \(name) לתפוס.")
        case .retrieve:
            if engine.called == ownId { return tr("Pick up the ball: get close and tap.", "אספו את הכדור: התקרבו וגעו.") }
            return tr("Keep running until SPUD!", "המשיכו לרוץ עד עמודו!")
        case .shout:
            if engine.called == ownId {
                return RuleText.format(RuleText[engine.config.requireCall ? "mustCall" : "mayCall"], RuleText.call(engine.config.rules))
            }
            return tr("Keep running, or stop and prepare to catch.", "המשיכו לרוץ, או עצרו והתכוננו לתפוס.")
        case .aim:
            if engine.thrower == ownId { return tr("Aim by tapping a player.\nFlick from your ball to throw.", "כוונו בנגיעה בשחקן.\nהחליקו מהכדור כדי לזרוק.") }
            return tr("SPUD! Stay still.\nTap to catch · Double-tap to duck", "עמודו! עמדו במקום.\nנגיעה לתפיסה · נגיעה כפולה להתכופפות")
        case .flight:
            return tr("Catch it or duck!", "תפסו או התכופפו!")
        case .resolve:
            return feedbackText()
        case .huddle:
            if engine.huddleTarget == ownId { return tr("Take a break.\nThe next round is on its way.", "זמן להפסקה קצרה.\nעוד מעט ממשיכים.") }
            return tr("Choose one funny word privately.", "בוחרים בסוד מילה מצחיקה אחת.")
        case .returnVote:
            return RuleText["pausedVote"]
        case .waiting:
            return RuleText["waiting"]
        case .finished:
            return tr("What a game!", "איזה משחק!")
        }
    }

    /// Android `drawActor`: every character stands on its feet with the same visible height for its depth (from its
    /// art's opaque bounds), and the touch target is that visible body.
    private func drawActor(_ ctx: CGContext, _ a: GameActor, _ width: CGFloat, _ height: CGFloat) {
        let p = project(a.position, a.jumpHeight)
        let head = project(a.position, a.jumpHeight + 3.5)
        let visibleHeight = min(max(p.y - head.y, 28), height * 0.27)
        let visual = art.visual(a, engine)
        let f = visual.frame
        let anchor = art.anchor(a.member.character, visual)
        let rect = anchor.destination(p.x, p.y, visibleHeight, f.rect.width, f.rect.height, mirrored: visual.mirrored)
        let w = rect.width
        let h = rect.height
        ctx.setFillColor(argbColor(0x40091326).cgColor)
        ctx.fillEllipse(in: CGRect(x: p.x - w * 0.3, y: p.y - h * 0.05, width: w * 0.6, height: h * 0.095))
        let id = a.member.id
        if id == ownId || id == engine.selected || id == engine.called {
            ctx.setStrokeColor(argbColor(id == ownId ? 0xff00e5ff : 0xffffea00).cgColor)
            ctx.setLineWidth(2.5)
            ctx.strokeEllipse(in: CGRect(x: p.x - w * 0.4, y: p.y - h * 0.03, width: w * 0.8, height: h * 0.075))
        }
        let handX = rect.minX + w * (visual.mirrored ? 1 - f.handX : f.handX)
        let hand = CGPoint(x: handX, y: rect.minY + h * f.handY)
        handPoints[id] = hand
        let sx = visibleHeight / anchor.height
        let half = (anchor.right - anchor.left) * sx / 2
        actorRects[id] = CGRect(x: p.x - half, y: p.y - visibleHeight, width: half * 2, height: visibleHeight)
        let holding = engine.ball.holder == id
        if holding && visual.facing == "back" { drawHeldBall(hand, w) }
        if visual.mirrored {
            ctx.saveGState()
            ctx.translateBy(x: rect.midX, y: rect.midY)
            ctx.scaleBy(x: -1, y: 1)
            ctx.translateBy(x: -rect.midX, y: -rect.midY)
            visual.image.draw(in: rect)
            ctx.restoreGState()
        } else {
            visual.image.draw(in: rect)
        }
        if holding && visual.facing != "back" { drawHeldBall(hand, w) }
        let label = id == ownId ? tr("You", "אתם") : a.fullName(hebrew: hebrew)
        let maxLength = engine.actors.count >= 9 ? 10 : 14
        var shown = label
        if label.utf16.count > maxLength {
            shown = String(decoding: Array(label.utf16.prefix(maxLength - 1)), as: UTF16.self) + "…"
        }
        let score = a.penalties == 0 ? "" : " · " + RuleText.score(a, engine.config.rules)
        tags.append(Tag(actor: a, text: shown + score, base: p, width: w * 1.24))
        if engine.time < a.catchUntil {
            let sweep = CGFloat(2 * Double.pi * (a.catchUntil - engine.time) / engine.config.catchWindow)
            let arc = UIBezierPath(arcCenter: hand, radius: w * 0.25, startAngle: -CGFloat.pi / 2, endAngle: -CGFloat.pi / 2 + sweep, clockwise: true)
            ctx.setStrokeColor(argbColor(0xb2ffe96a).cgColor)
            ctx.setLineWidth(2)
            ctx.addPath(arc.cgPath)
            ctx.strokePath()
        }
    }

    private func drawHeldBall(_ hand: CGPoint, _ w: CGFloat) {
        let b = w * 0.342 * CGFloat(engine.config.ball.visualScale)
        art.ball(engine.config.ball).draw(in: CGRect(x: hand.x - b / 2, y: hand.y - b / 2, width: b, height: b))
    }

    /// Android `drawTags`: stable slots (StableLabels) near the feet, kept off bodies and other tags inside the field;
    /// the local player's tag wears their colour rank.
    private func drawTags(_ ctx: CGContext, _ width: CGFloat, _ height: CGFloat) {
        var used: [LabelBox] = []
        tagRects.removeAll()
        let obstacles = Array(actorRects.values) + (practiceObstacle.map { [$0] } ?? [])
        let bodies = obstacles.map { LabelBox(x: Float($0.minX - 3), y: Float($0.minY - 3), w: Float($0.width + 6), h: Float($0.height + 6)) }
        let left = fieldLeft()
        let bounds = LabelBox(x: Float(left), y: Float(fieldTop()), w: Float(width - left - 5), h: Float(fieldBottom() - fieldTop()))
        let ordered = tags.sorted { l, r in
            let lo = l.actor.member.id == ownId ? 0 : 1
            let ro = r.actor.member.id == ownId ? 0 : 1
            if lo != ro { return lo < ro }
            return Kotlin.less(l.actor.member.id, r.actor.member.id)
        }
        let size: CGFloat = engine.actors.count >= 9 ? 10 : 11
        let rank = ProgressRanks.at(rankPoints)
        let tagFont = font(size)
        for tag in ordered {
            let w = min(max(measure(tag.text, size) + 16, 45), CGFloat(bounds.w))
            let b = stableLabels.place(tag.actor.member.id, Float(tag.base.x), Float(tag.base.y + 5), Float(w), 22, bounds, bodies, used, 24)
            let rect = CGRect(x: CGFloat(b.x), y: CGFloat(b.y), width: CGFloat(b.w), height: CGFloat(b.h))
            used.append(b)
            tagRects.append((tag.actor.member.id, rect))
            if distance2D(CGFloat(b.cx) - tag.base.x, CGFloat(b.y) - tag.base.y) > 28 {
                line(ctx, tag.base, CGPoint(x: CGFloat(b.cx), y: CGFloat(b.cy)), 0x88122e43, 1)
            }
            let mine = tag.actor.member.id == ownId
            panel(ctx, rect, mine ? rank.color : 0xf0153043)
            // Android baseline: cy - (ascent + descent) / 2 (UIKit descender is negative).
            text(tag.text, CGFloat(b.cx), CGFloat(b.cy) + (tagFont.ascender + tagFont.descender) / 2, size, mine ? rank.ink : 0xffffffff)
        }
    }

    private func drawBallShadow(_ ctx: CGContext, _ width: CGFloat, _ height: CGFloat) {
        let ground = project(engine.ball.position)
        let size = min(width, height) * 0.067 * CGFloat(engine.config.ball.visualScale)
        ctx.setFillColor(argbColor(0x450a1830).cgColor)
        ctx.fillEllipse(in: CGRect(x: ground.x - size * 0.6, y: ground.y - size * 0.15, width: size * 1.2, height: size * 0.3))
    }

    private func drawFlyingBall(_ ctx: CGContext, _ width: CGFloat, _ height: CGFloat, _ ball: Ball? = nil) {
        let b = ball ?? engine.ball
        let p = project(b.position, b.height)
        let size = min(width, height) * 0.067 * CGFloat(engine.config.ball.visualScale)
        // No altitude clamp: a powerful lob can leave the viewport and return naturally.
        if engine.ballWithinReach(ownId) {
            let r = size * 0.72
            fillRadial(ctx, p, r * 1.45, [0xb200e5ff, 0x00000000], [0, 1])
            ctx.setStrokeColor(argbColor(0xffbafff4).cgColor)
            ctx.setLineWidth(2.5)
            ctx.strokeEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        }
        art.ball(engine.config.ball).draw(in: CGRect(x: p.x - size / 2, y: p.y - size / 2, width: size, height: size))
    }

    /// Android `feedbackText()`: names the actor ("You" only for the local player, nicknames as they are now).
    func feedbackText() -> String {
        let actor = engine.actor(engine.infoActor)
        let name = actor.map { RuleText.name($0, ownId) } ?? tr("That player", "השחקן הזה")
        let you = engine.infoActor == ownId
        switch engine.infoCode {
        case "timeout":
            return RuleText.format(RuleText["timeout"], name)
        case "air_catch":
            return you ? tr("You caught the ball! Your turn to call.", "תפסתם את הכדור! תורכם לקרוא.")
                : tr("\(name) caught the ball! Their turn to call.", "תפיסה של \(name)! עכשיו התור של \(name) לקרוא.")
        case "tag_catch":
            return you ? tr("You caught the ball! The thrower gets a penalty.", "תפסתם את הכדור! נקודת חובה לזורק.")
                : tr("\(name) caught the ball! The thrower gets a penalty.", "הכדור נתפס על ידי \(name)! נקודת חובה לזורק.")
        case "tagged":
            return you ? tr("The ball hit you. One penalty.", "הכדור פגע בכם. נקודת חובה אחת.")
                : tr("The ball hit \(name). One penalty.", "הכדור פגע ב\(name). נקודת חובה אחת.")
        case "air_hit":
            return you ? tr("The ball touched you. Get close and tap to pick it up.", "הכדור נגע בכם. התקרבו וגעו כדי לאסוף אותו.")
                : tr("The ball touched \(name). They need to pick it up.", "הכדור נגע ב\(name). עכשיו על \(name) לאסוף אותו.")
        case "pickup":
            return you ? tr("Get close and tap to pick up the ball.", "התקרבו וגעו כדי לאסוף את הכדור.")
                : tr("\(name) needs to pick up the ball.", "על \(name) לאסוף את הכדור.")
        case "miss":
            return you ? tr("Your throw missed. One penalty.", "הזריקה שלכם החטיאה. נקודת חובה אחת.")
                : tr("\(name) missed. One penalty.", "הזריקה של \(name) החטיאה. נקודת חובה אחת.")
        case "wrong_nickname":
            return you ? tr("Incorrect nickname: one penalty.", "כינוי שגוי: נקודת חובה אחת.")
                : tr("\(name) used the wrong nickname. One penalty.", "כינוי שגוי מצד \(name). נקודת חובה אחת.")
        default:
            return tr(engine.infoEn, engine.infoHe)
        }
    }

    // MARK: Accessibility (Android `onInitializeAccessibilityNodeInfo` / `performAccessibilityAction`)

    override var accessibilityLabel: String? {
        get {
            if let d = engine.practice { return practiceInstruction(d) }
            return super.accessibilityLabel
        }
        set { super.accessibilityLabel = newValue }
    }

    override var accessibilityCustomActions: [UIAccessibilityCustomAction]? {
        get {
            guard let d = engine.practice else { return super.accessibilityCustomActions }
            var actions: [UIAccessibilityCustomAction] = []
            if d.allowsJump {
                actions.append(UIAccessibilityCustomAction(name: tr("Jump", "קפיצה")) { [weak self] _ in
                    self?.command(.jump)
                    return true
                })
            }
            if d.allowsDuck {
                actions.append(UIAccessibilityCustomAction(name: tr("Duck", "כיפוף")) { [weak self] _ in
                    self?.command(.duck)
                    return true
                })
            }
            if !d.stage.defence {
                actions.append(UIAccessibilityCustomAction(name: tr("Catch", "תפיסה")) { [weak self] _ in
                    self?.command(.catchBall)
                    return true
                })
            }
            return actions
        }
        set { super.accessibilityCustomActions = newValue }
    }

    // MARK: Touch (Android onTouchEvent)

    /// Name tags first (they are what players see), then the nearest visible body under the finger.
    private func hitActor(_ x: CGFloat, _ y: CGFloat) -> String? {
        let point = CGPoint(x: x, y: y)
        if let tag = tagRects.first(where: { $0.1.contains(point) }) { return tag.0 }
        var best: String?
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for (id, rect) in actorRects where rect.contains(point) {
            let d = distance2D(rect.midX - x, rect.midY - y)
            if d < bestDistance {
                bestDistance = d
                best = id
            }
        }
        return best
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let wasEmpty = activeTouches.isEmpty
        activeTouches.formUnion(touches)
        guard wasEmpty, let touch = touches.first else { return }
        actionDown(touch, touch.location(in: self))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let primary = pointer, touches.contains(primary) else { return }
        actionMove(primary.location(in: self))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            activeTouches.remove(touch)
            let primary = pointer === touch
            if activeTouches.isEmpty {
                actionUp(touch.location(in: self), touch.timestamp)
            } else if primary {
                // ACTION_POINTER_UP of the primary pointer.
                cancelInput()
            }
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        activeTouches.subtract(touches)
        cancelInput()
    }

    private func actionDown(_ touch: UITouch, _ point: CGPoint) {
        let x = point.x
        let y = point.y
        if jumpRect.contains(point) {
            command(.jump)
            return
        }
        if rotateRect.contains(point) {
            cancelInput()
            onRotate?()
            return
        }
        if rosterRect.contains(point) {
            onRoster?()
            return
        }
        if cameraRect.contains(point) {
            playerCamera = !playerCamera
            return
        }
        if returnRect.contains(point) {
            command(.requestReturn)
            return
        }
        if backRect.contains(point) {
            onBack?()
            return
        }
        if engine.actor(ownId)?.active == true && chatRect.contains(point) {
            onSay?()
            return
        }
        if networkWaiting || engine.actor(ownId)?.active == false { return }
        if shoutRect.contains(point) {
            command(.shout)
            return
        }
        gestureCamera = arenaCamera
        gestureOrigin = engine.actor(ownId)?.position
        pointer = touch
        startX = x
        startY = y
        startAt = Int64(touch.timestamp * 1000)
        dragged = false
        catchCommitted = false
        secondTap = pendingTap != nil && startAt - tapAt <= Int64(engine.config.doubleTapMs) && distance2D(x - tapX, y - tapY) < 42
        if secondTap {
            pendingTap?.cancel()
            pendingTap = nil
            pendingTapAction = nil
        }
        var onBall = false
        if let hand = handPoints[ownId] { onBall = distance2D(x - hand.x, y - hand.y) < 45 }
        if engine.thrower == ownId && engine.phase == .circle && onBall {
            gesture = "toss"
        } else if engine.canAim(ownId) && onBall {
            gesture = "throw"
        } else {
            gesture = "move"
        }
        let catchPhase = (engine.phase == .air && engine.called == ownId) || (engine.phase == .flight && engine.thrower != ownId)
        if !secondTap && catchPhase {
            heldCatch = afterDelay(Double(engine.config.doubleTapMs) / 1000.0) { [weak self] in
                guard let self else { return }
                self.heldCatch = nil
                if self.pointer != nil && !self.dragged {
                    self.command(.catchBall)
                    self.catchCommitted = true
                }
            }
        }
    }

    private func actionMove(_ point: CGPoint) {
        let dx = point.x - startX
        let dy = point.y - startY
        let distance = distance2D(dx, dy)
        if distance > 10 {
            dragged = true
            heldCatch?.cancel()
            heldCatch = nil
            pendingTap?.cancel()
            pendingTap = nil
            pendingTapAction = nil
        }
        if dragged {
            switch gesture {
            case "move":
                command(.move(inverseVector(dx, dy) * min(1.0, Double(distance / 40))))
            case "throw":
                aimedAt = nil
                command(.aim(inverseVector(dx, dy)))
            default:
                break
            }
        }
    }

    private func actionUp(_ point: CGPoint, _ time: TimeInterval) {
        if pointer == nil { return }
        heldCatch?.cancel()
        heldCatch = nil
        pointer = nil
        let x = point.x
        let y = point.y
        let now = Int64(time * 1000)
        let dx = x - startX
        let dy = y - startY
        if dragged {
            if gesture == "toss" && dy < -18 {
                let speed = Double(-dy) / Double(max(Int64(60), now - startAt)) * 1000
                let drift = Double(dx / max(abs(dy), 30))
                command(.toss(power: Kotlin.clamp((speed - 180) / 1900, 0, 1), drift: Kotlin.clamp(drift, -1, 1)))
            }
            if gesture == "throw" {
                let speed = Double(distance2D(dx, dy)) / Double(max(Int64(45), now - startAt)) * 1000
                command(.throwBall(power: Kotlin.clamp((speed - 100) / 1700, 0, 1)))
            }
            command(.move(V.zero))
            return
        }
        if secondTap {
            secondTap = false
            command(.duck)
            return
        }
        if catchCommitted { return }
        if let previous = pendingTapAction {
            pendingTap?.cancel()
            pendingTap = nil
            pendingTapAction = nil
            previous()
        }
        tapAt = now
        tapX = x
        tapY = y
        let action: @MainActor () -> Void = { [weak self] in
            guard let self else { return }
            self.pendingTap = nil
            self.pendingTapAction = nil
            self.singleTap(x, y)
        }
        pendingTapAction = action
        pendingTap = afterDelay(Double(engine.config.doubleTapMs) / 1000.0) { action() }
    }

    private func singleTap(_ x: CGFloat, _ y: CGFloat) {
        let target = hitActor(x, y)
        if engine.phase == .circle && engine.thrower == ownId {
            if let t = target, t != ownId, let chosen = engine.actor(t) {
                if let choose = onChoose { choose(chosen) } else { command(.select(target: t)) }
            }
            return
        }
        if let d = engine.practice, engine.canAim(ownId) {
            // Android inverts the projected 16 m square at the target's height (Matrix.setPolyToPoly); the camera's own
            // inverse at that height is the same mapping.
            if let me = engine.actor(ownId) {
                let at = arenaCamera.ground(Double(x), Double(y), max(Double(bounds.width), 1), max(Double(bounds.height), 1), d.targetHeight)
                command(.aim(V(at.x, at.y) - me.position))
            }
            return
        }
        if engine.canAim(ownId) {
            if let t = target, t != ownId, let other = engine.actor(t), let me = engine.actor(ownId) {
                aimedAt = t
                playerCamera = false
                command(.aim((other.position - me.position).unit()))
            }
            return
        }
        command(.catchBall)
    }

    private func cancelInput() {
        heldCatch?.cancel()
        heldCatch = nil
        catchCommitted = false
        secondTap = false
        pendingTap?.cancel()
        pendingTap = nil
        pendingTapAction = nil
        pointer = nil
        gestureCamera = nil
        gestureOrigin = nil
        if engine.result == nil { command(.move(V.zero)) }
    }
}
