import UIKit

/// Calls the arena once per display frame without the display link retaining the view.
@MainActor
private final class ArenaFrameTarget: NSObject {
    weak var view: SplashArenaView?

    @objc func tick(_ link: CADisplayLink) {
        guard let view = view else {
            link.invalidate()
            return
        }
        view.frameTick()
    }
}

/// The dynamic layer: everything Android draws on the Canvas above the GPU arena.
private final class ArenaCanvas: UIView {
    weak var owner: SplashArenaView?

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        owner?.render(context)
    }
}

private struct ParagraphLayout {
    let text: NSAttributedString
    let width: CGFloat
    let height: CGFloat
}

/// Port of Android SplashView.kt: the arena camera (follow, focus, player view and orbit), the
/// GPU ground underneath (ArenaWorldView), private answers, actors sized by their visible body,
/// stable name tags, aiming, particles, the whole-field close-up, paint walls and journey drills,
/// hit testing, gestures and the "Learn to play" lesson overlay. Android draws with Canvas in pixels scaled by density; iOS
/// draws the same geometry with Core Graphics in points.
@MainActor
final class SplashArenaView: UIView {
    let engine: SplashEngine
    let localId: String
    private let art: ArtStore
    var onExit: () -> Void
    var onFinish: (MatchResult) -> Void
    var onSpeak: (String) -> Void
    var tutorialCompleted: (() -> Void)?
    var onControlSettings: ((PlayerSettings) -> Void)?
    var sendCommand: ((Command) -> Void)?
    var spectatorSnapshot: (() -> Void)?
    /// Android `onRotate`: the ↻ button turns the game between portrait and landscape.
    var onRotate: (() -> Void)?
    /// Android `rankPoints`: the colour rank of the local name tag and score.
    var rankPoints = 0
    var remote = false
    var networkStatus = "" {
        didSet { if networkStatus != oldValue { canvas.setNeedsDisplay() } }
    }
    private(set) var running = true
    private(set) var tutorialStep = -1

    private let local: SplashActor
    private let worldView = ArenaWorldView(frame: .zero)
    private let canvas = ArenaCanvas()
    private var loadingView: BattleLoadingView?
    private var displayLink: CADisplayLink?
    private let frameTarget = ArenaFrameTarget()
    private var gesture: Gestures!
    private var arenaSize = CGSize.zero
    private var layouts: [String: ParagraphLayout] = [:]
    private var layoutOrder: [String] = []
    private var fonts: [Int: UIFont] = [:]
    private var timerSecond = -1
    private var timerText = ""
    private var seq: Int64 = 0
    private var last: Int64 = 0
    private var finished = false
    private var highlighted = -1
    /// Android `mutableMapOf<String, RectF>`: insertion (draw) order.
    private var actorRects: [(id: String, rect: CGRect)] = []
    private var choiceRects: [Int: CGRect] = [:]
    private var labelRects: [CGRect] = []
    /// Android `drillObstacle`: the drill target ring (with a margin) that name tags avoid.
    private var drillObstacle: CGRect? = nil
    private let stableLabels = StableLabels()
    /// Android `linkedMapOf`: name tags in drawing order (the local player first).
    private var nameTargets: [(id: String, rect: CGRect)] = []
    private var focusedOpponent: String? = nil
    private var focusUntil = 0.0
    private var buttons: [String: CGRect] = [:]
    private var buttonOrder: [String] = []
    private var aimPoints: [CGPoint] = []
    private(set) var aimGrip = CGPoint.zero
    private var aimGripRect = CGRect.null
    private(set) var lastTouchSummary = ""
    private var lessonDone = false
    private var lessonStarted = 0.0
    private var lessonPosition = V(0, 0)
    private var lessonAnswers = 0
    private var pointerIds: [ObjectIdentifier: Int] = [:]
    private var touchesById: [Int: UITouch] = [:]

    // Camera (Android SplashView 2026-10-05).
    private var playerCamera = false
    private var arenaCamera: ArenaCamera
    private var cameraAt: Int64 = 0
    private var activePointers = Set<Int>()
    private var cameraButton = CGRect.zero
    private var renderWidth = 0
    private var renderHeight = 0
    private var orbitYaw = 0.0
    private var orbitPointer = -1
    private var orbitX: CGFloat = 0
    private var orbitRect = CGRect.zero
    private var billboard = CGRect.zero
    private var aimStarted: [Int: Int64] = [:]

    private let colors = SplashPalette.balloonColors
    private let white = SplashPalette.white
    private let ink = SplashPalette.ink

    init(engine: SplashEngine, localId: String, art: ArtStore, onExit: @escaping () -> Void,
         onFinish: @escaping (MatchResult) -> Void, onSpeak: @escaping (String) -> Void) {
        self.engine = engine
        self.localId = localId
        self.art = art
        self.onExit = onExit
        self.onFinish = onFinish
        self.onSpeak = onSpeak
        self.local = engine.actor(localId) ?? engine.actors[0]
        // Android: ArenaCamera(width / 2, depth / 2, PRO_EDITION ? 24 : 34).
        self.arenaCamera = ArenaCamera(engine.config.width / 2, engine.config.depth / 2,
                                       distance: SplashLaunch.proEdition ? 24.0 : 34.0)
        super.init(frame: .zero)
        let config = engine.config
        gesture = Gestures(window: config.doubleTapMs, slop: config.gestureSlopDp, doubleDistance: config.doubleTapDistanceDp) { [weak self] action in
            self?.touchAction(action)
        }
        backgroundColor = SplashPalette.ui(SplashPalette.sky)
        isMultipleTouchEnabled = true
        isAccessibilityElement = true
        accessibilityLabel = "Minik Splash arena"
        addSubview(worldView)
        canvas.owner = self
        canvas.isOpaque = false
        canvas.backgroundColor = .clear
        canvas.isUserInteractionEnabled = false
        canvas.contentMode = .redraw
        canvas.layer.drawsAsynchronously = true
        addSubview(canvas)
        frameTarget.view = self
    }

    required init?(coder: NSCoder) {
        return nil
    }

    // MARK: Lifecycle

    func stop() {
        running = false
        last = 0
        gesture.cancel()
        activePointers.removeAll()
        engine.paused = true
        local.move = V(0, 0)
        canvas.setNeedsDisplay()
    }

    func start() {
        running = true
        engine.paused = false
        last = 0
        startLink()
    }

    /// Releases the display link; the view is discarded afterwards.
    func teardown() {
        running = false
        displayLink?.invalidate()
        displayLink = nil
        sendCommand = nil
        spectatorSnapshot = nil
        worldView.firstFrame = nil
        loadingView?.stopAnimating()
    }

    /// Android `BattleLoadingView` in `present`: drawn at once, faded after the first GPU frame;
    /// `ready` runs when the fade ends (Android then marks the battle ready and starts it).
    func showLoading(avatar: String, ready: @escaping () -> Void) {
        loadingView?.removeFromSuperview()
        let loading = BattleLoadingView(art: art, avatar: avatar)
        loading.frame = bounds
        loading.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(loading)
        loadingView = loading
        worldView.firstFrame = { [weak self, weak loading] in
            guard let loading = loading else { return }
            UIView.animate(withDuration: 0.4, animations: {
                loading.alpha = 0
            }, completion: { _ in
                loading.stopAnimating()
                loading.removeFromSuperview()
                if self?.loadingView === loading { self?.loadingView = nil }
                ready()
            })
        }
    }

    private func startLink() {
        guard displayLink == nil, window != nil else {
            canvas.setNeedsDisplay()
            return
        }
        let link = CADisplayLink(target: frameTarget, selector: #selector(ArenaFrameTarget.tick(_:)))
        // Core Graphics drawing is budgeted for 60 Hz; the simulation itself is time-based.
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            stopLink()
        } else if running {
            startLink()
        } else {
            updateWorld()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        worldView.frame = bounds
        canvas.frame = bounds
        loadingView?.frame = bounds
        if bounds.size != arenaSize {
            // Android onSizeChanged.
            arenaSize = bounds.size
            stableLabels.clear()
            nameTargets.removeAll()
            cameraAt = 0
            orbitPointer = -1
            layouts.removeAll()
            layoutOrder.removeAll()
            gesture.cancel()
            activePointers.removeAll()
            local.move = V(0, 0)
            last = 0
            worldView.layoutIfNeeded()
            updateWorld()
            canvas.setNeedsDisplay()
        }
    }

    private func command(_ c: Command) {
        if let send = sendCommand {
            send(c)
        } else {
            engine.command(localId, "touch-\(seq)", c)
            seq += 1
        }
    }

    /// One display frame: Android onDraw's simulation half and `updateWorld()`.
    func frameTick() {
        let now = SplashClock.uptimeMillis()
        if running {
            gesture.flush(now)
            if last > 0 && !remote { engine.tick(Double(now - last) / 1000.0) }
            spectatorSnapshot?()
            last = now
        }
        updateWorld()
        if let result = engine.result, !finished {
            finished = true
            Task { @MainActor [weak self] in self?.onFinish(result) }
        }
        canvas.setNeedsDisplay()
        if !running { stopLink() }
    }

    // MARK: Camera

    private var viewWidth: CGFloat { return bounds.width }
    private var viewHeight: CGFloat { return bounds.height }
    private var landscape: Bool { return viewWidth > viewHeight }
    private var sceneWidth: Int { return renderWidth > 0 ? renderWidth : Int(viewWidth) }
    private var sceneHeight: Int { return renderHeight > 0 ? renderHeight : Int(viewHeight) }

    private func updateWorld() {
        guard viewWidth > 0 && viewHeight > 0 else { return }
        let now = SplashClock.uptimeMillis()
        let dt = cameraAt == 0 ? 1.0 : Double(now - cameraAt) / 1000.0
        cameraAt = now
        let target = targetCamera()
        // The camera holds still while a finger is down, so drags and aims stay where they started.
        if activePointers.isEmpty { arenaCamera = dt >= 1.0 ? target : arenaCamera.toward(target, dt) }
        var inset: ArenaInset? = nil
        let area = billboardBounds()
        if !area.isEmpty {
            inset = ArenaInset(camera: closeCamera(), left: Int(area.minX), top: Int(area.minY), width: Int(area.width), height: Int(area.height))
        }
        worldView.submit(ArenaFrame(camera: arenaCamera, scene: local.settings.arena.rawValue.lowercased(), width: engine.config.width,
                                    depth: engine.config.depth, time: engine.time, night: 0, inset: inset))
    }

    private func targetCamera() -> ArenaCamera {
        let me = local.position
        let width = Int(viewWidth)
        let height = Int(viewHeight)
        var base = arenaCamera
        base.yaw = orbitYaw
        base.centerY = landscape ? 0.61 : 0.68
        base.tilt = landscape ? 0.96 : 1.02
        let w = Double(width)
        let h = Double(height)
        if let d = engine.drill {
            // A drill frames the thrower(s), the target and the answers from a low, close camera.
            let points = engine.actors.map { $0.position } + [d.target] + local.choices.map { $0.position }
            var cam = base
            cam.x = engine.config.width * 0.5
            cam.y = engine.config.depth * 0.48
            cam.distance = 12.0
            cam.focusHeight = 1.3
            cam.tilt = 0.78
            cam.yaw = orbitYaw + (landscape ? Double.pi / 3 : 0.0)
            cam.centerY = landscape ? 0.56 : 0.55
            let top = h * (landscape ? 0.25 : 0.22)
            for _ in 0..<130 {
                let visible = points.allSatisfy { v in
                    [0.0, 5.3].allSatisfy { z in
                        let pt = cam.project(v.x, v.y, z, width, height)
                        let px = Double(pt.x)
                        let py = Double(pt.y)
                        return px >= w * 0.07 && px <= w * 0.93 && py >= top && py <= h * 0.79
                    }
                }
                if visible { return cam }
                cam.distance += 0.5
            }
            return cam
        }
        if engine.practice {
            var practice = base
            practice.x = me.x
            practice.y = me.y - 1.0
            practice.distance = landscape ? 17.0 : 24.0
            return practice
        }
        if let id = focusedOpponent, let other = engine.actor(id), engine.time < focusUntil {
            // A tapped opponent: frame both players (feet and heads) between the HUD and the advice.
            let pts = [GroundPoint(me.x, me.y), GroundPoint(other.position.x, other.position.y)]
            var c = base.frameGround(pts, max(width, 1), max(height, 1), base.focusHeight)
            let top = h * (landscape ? 0.20 : 0.42)
            for _ in 0..<160 {
                let visible = pts.allSatisfy { v in
                    [0.0, 4.7].allSatisfy { z in
                        let p = c.project(v.x, v.y, base.focusHeight + z, width, height)
                        let px = Double(p.x)
                        let py = Double(p.y)
                        return px >= w * 0.08 && px <= w * 0.92 && py >= top && py <= h * 0.82
                    }
                }
                if visible { return c }
                c.distance += 0.5
            }
            return c
        }
        if engine.paintSession.active || engine.paintSession.passing {
            // Walls (both ends of each) and every player stay in view between the HUD and the advice.
            let points = engine.paintSession.walls.flatMap { wall in [wall.world(0.0, 0.0), wall.world(1.0, 0.0)] } + engine.actors.map { $0.position }
            var cam = base
            cam.x = engine.config.width / 2
            cam.y = engine.config.depth * 0.45
            cam.distance = 10.0
            cam.focusHeight = landscape ? 2.0 : 0.0
            cam.tilt = landscape ? 1.18 : 1.02
            cam.centerY = landscape ? 0.55 : 0.66
            let top = h * (landscape ? 0.27 : 0.43)
            for _ in 0..<120 {
                let visible = points.allSatisfy { v in
                    [0.0, 6.4].allSatisfy { z in
                        let pt = cam.project(v.x, v.y, z, width, height)
                        let px = Double(pt.x)
                        let py = Double(pt.y)
                        return px >= w * 0.06 && px <= w * 0.94 && py >= top && py <= h * 0.80
                    }
                }
                if visible { return cam }
                cam.distance += 0.5
            }
            return cam
        }
        if playerCamera {
            var follow = base
            follow.x = me.x
            follow.y = me.y
            follow.distance = landscape ? 19.0 : 27.0
            return follow
        }
        let places = local.choices.map { GroundPoint($0.position.x, $0.position.y) } + [GroundPoint(me.x, me.y)]
        var fit = base.frameGround(places, max(width, 1), max(height, 1), 0.0)
        // Collecting never changes framing; keep the same action context and nearby opponents.
        fit.distance = max(fit.distance, landscape ? 25.0 : 32.0)
        return fit
    }

    /// Android `overviewCamera()`: the whole field (every corner up to 5 high) inside the close-up box.
    func overviewCamera() -> ArenaCamera {
        let box = billboardBounds()
        let w = max(Int(box.width), 1)
        let h = max(Int(box.height), 1)
        var view = ArenaCamera(engine.config.width / 2, engine.config.depth / 2, distance: 26.0, focusHeight: 1.5, tilt: 1.15,
                               centerY: 0.59, yaw: 0.0)
        for _ in 0..<180 {
            let inside = [0.0, engine.config.width].allSatisfy { x in
                [0.0, engine.config.depth].allSatisfy { y in
                    [0.0, 5.0].allSatisfy { z in
                        let pt = view.project(x, y, z, w, h)
                        let px = Double(pt.x)
                        let py = Double(pt.y)
                        return px >= Double(w) * 0.06 && px <= Double(w) * 0.94 && py >= Double(h) * 0.22 && py <= Double(h) * 0.94
                    }
                }
            }
            if inside { return view }
            view.distance += 1
        }
        return view
    }

    private func closeCamera() -> ArenaCamera { return overviewCamera() }

    /// The live whole-field box above the action (none in landscape, practice or drills).
    private func billboardBounds() -> CGRect {
        if landscape || engine.practice || engine.drill != nil { return .zero }
        return ltrb(viewWidth * 0.16, 145, viewWidth * 0.84, max(viewHeight * 0.39, 245))
    }

    // MARK: Projection

    /// Android RenderConfig for balloon sizes and the aiming lift.
    private var camera: RenderConfig {
        var c = engine.config.render
        if engine.practice {
            c.floorTop = 0.40
            c.floorDepth = 0.48
            c.characterWidth = 0.205
        } else if !local.settings.court {
            c.floorTop = 0.30
            c.floorDepth = 0.60
            c.horizontalPadding = 2.4
        }
        return c
    }

    func screen(_ v: V, _ z: Double = 0) -> CGPoint {
        let p = arenaCamera.project(v.x, v.y, z, max(sceneWidth, 1), max(sceneHeight, 1))
        return CGPoint(x: CGFloat(p.x), y: CGFloat(p.y))
    }

    private func world(_ x: CGFloat, _ y: CGFloat) -> V {
        let g = arenaCamera.ground(Float(x), Float(y), Int(viewWidth), Int(viewHeight))
        return V(g.x, g.y)
    }

    func buttonCenter(_ key: String) -> CGPoint? {
        guard let r = buttons[key] else { return nil }
        return CGPoint(x: r.midX, y: r.midY)
    }

    func actorCenter(_ id: String) -> CGPoint? {
        guard let r = actorRects.first(where: { $0.id == id })?.rect else { return nil }
        return CGPoint(x: r.midX, y: r.midY)
    }

    func balloonCenter(_ index: Int) -> CGPoint? {
        guard let r = choiceRects[index] else { return nil }
        return CGPoint(x: r.midX, y: r.midY)
    }

    /// Android `tagBounds()`: the touchable name tags.
    func tagBounds() -> [String: CGRect] {
        var result: [String: CGRect] = [:]
        for entry in nameTargets { result[entry.id] = entry.rect }
        return result
    }

    // MARK: Drawing helpers

    private func font(_ size: CGFloat, _ bold: Bool) -> UIFont {
        let key = Int(size * 10) * 2 + (bold ? 1 : 0)
        if let cached = fonts[key] { return cached }
        let made = UIFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
        fonts[key] = made
        return made
    }

    private func tr(_ en: String, _ he: String) -> String {
        return AppText.t(en, he, hebrew: engine.hebrew)
    }

    private func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// Android `RectF(left, top, right, bottom)`.
    private func ltrb(_ l: CGFloat, _ t: CGFloat, _ r: CGFloat, _ b: CGFloat) -> CGRect {
        return CGRect(x: l, y: t, width: r - l, height: b - t)
    }

    private func rounded(_ c: CGContext, _ b: CGRect, _ radius: CGFloat, _ color: UInt32) {
        c.setFillColor(SplashPalette.ui(color).cgColor)
        if radius <= 0 {
            c.fill(b)
        } else {
            c.addPath(UIBezierPath(roundedRect: b, cornerRadius: radius).cgPath)
            c.fillPath()
        }
    }

    private func fillOval(_ c: CGContext, _ b: CGRect, _ color: UIColor) {
        c.setFillColor(color.cgColor)
        c.fillEllipse(in: b)
    }

    private func line(_ c: CGContext, _ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat, _ width: CGFloat, _ color: UInt32) {
        c.setStrokeColor(SplashPalette.ui(color).cgColor)
        c.setLineWidth(width)
        c.move(to: CGPoint(x: x1, y: y1))
        c.addLine(to: CGPoint(x: x2, y: y2))
        c.strokePath()
    }

    /// Android `text()`: single line, vertically centred on y.
    private func text(_ s: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ color: UInt32, bold: Bool = false, alignLeft: Bool = false) {
        let f = font(size, bold)
        let string = NSAttributedString(string: s, attributes: [.font: f, .foregroundColor: SplashPalette.ui(color)])
        let width = string.size().width
        let top = y - (f.ascender - f.descender) / 2
        string.draw(at: CGPoint(x: alignLeft ? x : x - width / 2, y: top))
    }

    private func measure(_ s: String, _ size: CGFloat) -> CGFloat {
        return NSAttributedString(string: s, attributes: [.font: font(size, true)]).size().width
    }

    /// Android StaticLayout paragraph: centred, bold, at most `maxLines` lines, ellipsised.
    private func paragraph(_ s: String, _ b: CGRect, _ size: CGFloat, _ color: UInt32, maxLines: Int = 3, rtl: Bool? = nil) {
        let isRTL = rtl ?? AppText.rtl
        let key = "\(s)|\(Int(b.width))|\(size)|\(color)|\(maxLines)|\(isRTL)"
        let layout: ParagraphLayout
        if let cached = layouts[key] {
            layout = cached
        } else {
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            style.baseWritingDirection = isRTL ? .rightToLeft : .natural
            style.lineBreakMode = .byWordWrapping
            let f = font(size, true)
            let attributed = NSAttributedString(string: s, attributes: [.font: f, .foregroundColor: SplashPalette.ui(color), .paragraphStyle: style])
            let width = max(1, floor(b.width))
            let full = attributed.boundingRect(with: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude),
                                               options: [.usesLineFragmentOrigin], context: nil)
            let height = min(ceil(full.height), ceil(f.lineHeight * CGFloat(maxLines)) + 1)
            layout = ParagraphLayout(text: attributed, width: width, height: height)
            if layoutOrder.count >= 128 {
                let first = layoutOrder.removeFirst()
                layouts.removeValue(forKey: first)
            }
            layouts[key] = layout
            layoutOrder.append(key)
        }
        let rect = CGRect(x: b.minX, y: b.midY - layout.height / 2, width: layout.width, height: layout.height)
        layout.text.draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
    }

    /// Android `canvas.scale(sx, sy, px, py)`.
    private func scale(_ c: CGContext, _ sx: CGFloat, _ sy: CGFloat, _ px: CGFloat, _ py: CGFloat) {
        c.translateBy(x: px, y: py)
        c.scaleBy(x: sx, y: sy)
        c.translateBy(x: -px, y: -py)
    }

    /// Kotlin `Char.isDigit()` (Unicode decimal digits).
    private static func isDigit(_ ch: Character) -> Bool {
        return ch.unicodeScalars.first?.properties.generalCategory == .decimalNumber
    }

    /// Kotlin `Char.isLetter()` (Unicode letter categories).
    private static func isLetter(_ ch: Character) -> Bool {
        guard let category = ch.unicodeScalars.first?.properties.generalCategory else { return false }
        switch category {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter: return true
        default: return false
        }
    }

    /// Digits without letters (a sum, an answer) stay left to right inside RTL text.
    private static func isolatedNumber(_ value: String) -> Bool {
        return value.contains(where: { isDigit($0) }) && !value.contains(where: { isLetter($0) })
    }

    private func setActorRect(_ id: String, _ rect: CGRect) {
        if let index = actorRects.firstIndex(where: { $0.id == id }) {
            actorRects[index] = (id: id, rect: rect)
        } else {
            actorRects.append((id: id, rect: rect))
        }
    }

    private func setNameTarget(_ id: String, _ rect: CGRect) {
        if let index = nameTargets.firstIndex(where: { $0.id == id }) {
            nameTargets[index] = (id: id, rect: rect)
        } else {
            nameTargets.append((id: id, rect: rect))
        }
    }

    // MARK: Frame

    func render(_ c: CGContext) {
        guard viewWidth > 0 && viewHeight > 0 else { return }
        c.interpolationQuality = .medium
        drawFloorEffects(c)
        drawGameObjects(c)
        drawBillboard(c)
        drawHud(c)
        if tutorialStep < 0 {
            let bottom = viewHeight - (landscape ? 55 : 104)
            cameraButton = ltrb(12, bottom - 34, 166, bottom)
            rounded(c, cameraButton, 10, 0xee1b5668)
            let cameraTitle: String
            if local.held != nil && local.settings.throwing == .standard {
                cameraTitle = tr("Throw balloon", "זריקת הבלון")
            } else if playerCamera {
                cameraTitle = tr("Your view · switch", "המבט שלכם · החלפה")
            } else {
                cameraTitle = tr("Action view · switch", "מבט כללי · החלפה")
            }
            text(cameraTitle, cameraButton.midX, cameraButton.midY, 12, white, bold: true)
            orbitRect = ltrb(viewWidth - 160, bottom - 34, viewWidth - 12, bottom)
            rounded(c, orbitRect, 10, 0xee1b5668)
            text(tr("↔ Rotate view", "↔ סיבוב המבט"), orbitRect.midX, orbitRect.midY, 12, white, bold: true)
        }
        if tutorialStep >= 0 {
            updateLesson()
            drawTutorial(c)
        }
        if !running {
            rounded(c, box(viewWidth * 0.12, viewHeight * 0.40, viewWidth * 0.76, viewHeight * 0.18), 24, 0xee102c46)
            text(tr("Paused · tap to continue", "המשחק מושהה · נגיעה להמשך"), viewWidth * 0.5, viewHeight * 0.49, 17, white, bold: true)
        }
    }

    // MARK: Paint walls and journey drills

    /// Android `wallMatrix(wall)`: the wall's (u, v) square on screen; v = 0 is the ground.
    private func wallMap(_ wall: PaintWall) -> PlanarMap {
        func corner(_ u: Double, _ v: Double) -> CGPoint { return screen(wall.world(u, v), v * wall.height) }
        return PlanarMap.square(corner(0, 0), corner(1, 0), corner(1, 1), corner(0, 1))
    }

    /// Android `wallPoint(id, u, v)`: a wall point on screen (UI tests).
    func wallPoint(_ id: Int, _ u: Double, _ v: Double) -> CGPoint {
        let wall = engine.paintSession.walls[id]
        return screen(wall.world(u, v), v * wall.height)
    }

    private func drillTap(_ x: CGFloat, _ y: CGFloat) -> Bool {
        guard let d = engine.drill else { return false }
        if !d.spec.aiming || local.held == nil { return false }
        let target = d.target
        // Map a real point on the target plane. Touches outside the ring remain misses.
        let a = screen(V(0.0, target.y), 0.0)
        let b = screen(V(engine.config.width, target.y), 0.0)
        let h = screen(V(0.0, target.y), 5.0)
        let corner = screen(V(engine.config.width, target.y), 5.0)
        // The plane runs 0...width across and 0...5 up: (0,0), (width,0), (width,5), (0,5).
        guard let inverse = PlanarMap.square(a, b, corner, h).inverted() else { return false }
        let pt = inverse.map(Double(x), Double(y))
        if d.spec.ground {
            let at = world(x, y)
            command(.aim(at - local.position))
            command(.throwBalloon)
        } else {
            command(.drillAim(x: Double(Float(Double(pt.x) * engine.config.width)), height: Double(Float(Double(pt.y) * 5.0))))
            command(.throwBalloon)
        }
        return true
    }

    private func drawDrill(_ c: CGContext) {
        drillObstacle = nil
        guard let d = engine.drill else { return }
        let color: UInt32 = engine.time - d.lastSuccess < 0.5 ? 0xffa4ffaf : 0xffffdf70
        if d.spec.aiming {
            let path = CGMutablePath()
            let t = d.target
            for i in 0...48 {
                let angle = Double(i) * 2 * Double.pi / 48
                let v = d.spec.ground ? V(t.x + cos(angle) * d.radius, t.y + sin(angle) * d.radius) : V(t.x + cos(angle) * d.radius, t.y)
                let at = screen(v, d.spec.ground ? 0.12 : d.height + sin(angle) * d.radius)
                if i == 0 { path.move(to: at) } else { path.addLine(to: at) }
            }
            path.closeSubpath()
            drillObstacle = path.boundingBoxOfPath.insetBy(dx: -34, dy: -32)
            c.setStrokeColor(SplashPalette.ui(0xff173f55).cgColor)
            c.setLineWidth(10)
            c.addPath(path)
            c.strokePath()
            c.setStrokeColor(SplashPalette.ui(color).cgColor)
            c.setLineWidth(6)
            c.addPath(path)
            c.strokePath()
            let top = screen(d.target, d.spec.ground ? 0.2 : d.height + d.radius + 0.4)
            rounded(c, ltrb(top.x - 29, top.y - 13, top.x + 29, top.y + 13), 10, 0xee173f55)
            text("\(d.successes)/\(d.goal)", top.x, top.y, 18, color, bold: true)
        } else {
            for id in d.cueBots {
                guard let a = engine.actor(id) else { continue }
                let at = screen(a.position, 2.5)
                text(d.cueHigh ? tr("DUCK ↓", "להתכופף ↓") : tr("JUMP ↑", "לקפוץ ↑"), at.x, at.y, 16, color, bold: true)
            }
        }
    }

    private func paintTap(_ x: CGFloat, _ y: CGFloat) -> Bool {
        if local.held == nil { return false }
        for wall in engine.paintSession.walls {
            if engine.config.wallBattle && wall.id == local.member.team { continue }
            guard let inverse = wallMap(wall).inverted() else { continue }
            let point = inverse.map(Double(x), Double(y))
            // Android maps the touch in Float.
            let u = Float(point.x)
            let v = Float(point.y)
            if u >= 0 && u <= 1 && v >= 0 && v <= 1 {
                command(.paintAt(wall: wall.id, u: Double(u), v: Double(v)))
                command(.throwBalloon)
                return true
            }
        }
        return false
    }

    /// Android `drawRect` under the wall matrix: the mapped quadrilateral.
    private func wallQuad(_ m: PlanarMap, _ l: Double, _ t: Double, _ r: Double, _ b: Double, _ path: CGMutablePath) {
        path.move(to: m.map(l, t))
        path.addLine(to: m.map(r, t))
        path.addLine(to: m.map(r, b))
        path.addLine(to: m.map(l, b))
        path.closeSubpath()
    }

    /// Android `drawOval` / `drawCircle` under the wall matrix, as a mapped 48-point outline.
    private func wallOval(_ m: PlanarMap, _ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ path: CGMutablePath) {
        for j in 0..<48 {
            let angle = Double(j) * 2 * Double.pi / 48
            let pt = m.map(cx + cos(angle) * rx, cy + sin(angle) * ry)
            if j == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.closeSubpath()
    }

    private func fillPath(_ c: CGContext, _ path: CGPath, _ color: UInt32, evenOdd: Bool = false) {
        c.setFillColor(SplashPalette.ui(color).cgColor)
        c.addPath(path)
        c.fillPath(using: evenOdd ? .evenOdd : .winding)
    }

    private func drawWalls(_ c: CGContext) {
        let session = engine.paintSession
        for wall in session.walls {
            let m = wallMap(wall)
            let base = CGMutablePath()
            wallQuad(m, 0, 0, 1, 1, base)
            fillPath(c, base, 0xfffff5dd)
            // Cells batched by colour (same rectangles as Android, one fill per colour).
            var cells: [UInt32: CGMutablePath] = [:]
            var order: [UInt32] = []
            let columns = Double(wall.columns)
            let rows = Double(wall.rows)
            for i in wall.cells.indices {
                let x = Double(i % wall.columns) / columns
                let y = Double(i / wall.columns) / rows
                let color = wall.cells[i]
                let ink: UInt32
                if color >= 0 {
                    ink = Teams.style(color).color
                } else if i < session.targetMask.count && !session.targetMask[i] {
                    ink = 0xffdce8e7
                } else {
                    ink = 0xfffff9e9
                }
                if cells[ink] == nil {
                    cells[ink] = CGMutablePath()
                    order.append(ink)
                }
                if let path = cells[ink] { wallQuad(m, x + 0.002, y + 0.003, x + 1 / columns - 0.002, y + 1 / rows - 0.003, path) }
            }
            for ink in order { if let path = cells[ink] { fillPath(c, path, ink) } }
            // A colorful graffiti cornice stays outside the scored wall: decoration is never coverage.
            let cornice = CGMutablePath()
            let left = -0.015, top = 1.015, right = 1.015, bottom = 1.22, rx = 0.025, ry = 0.035
            let arcs: [(Double, Double, Double)] = [(right - rx, top + ry, -Double.pi / 2), (right - rx, bottom - ry, 0),
                                                    (left + rx, bottom - ry, Double.pi / 2), (left + rx, top + ry, Double.pi)]
            for (index, arc) in arcs.enumerated() {
                for step in 0...6 {
                    let angle = arc.2 + Double(step) * Double.pi / 12
                    let pt = m.map(arc.0 + cos(angle) * rx, arc.1 + sin(angle) * ry)
                    if index == 0 && step == 0 { cornice.move(to: pt) } else { cornice.addLine(to: pt) }
                }
            }
            cornice.closeSubpath()
            c.saveGState()
            c.addPath(cornice)
            c.clip()
            let gradientColors = [SplashPalette.ui(0xff794dcc).cgColor, SplashPalette.ui(0xffee6191).cgColor, SplashPalette.ui(0xff21b9b5).cgColor]
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: gradientColors as CFArray, locations: nil) {
                c.drawLinearGradient(gradient, start: m.map(0, 1), end: m.map(1, 1.2), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            }
            c.restoreGState()
            for i in 0...6 {
                let x = 0.065 + Double(i) * 0.145
                let y = 1.115
                let shape = CGMutablePath()
                if i % 2 == 0 {
                    for j in 0...9 {
                        let angle = Double(j) * Double.pi / 5
                        let radius = j % 2 == 0 ? 0.044 : 0.021
                        let pt = m.map(x + sin(angle) * radius, y + cos(angle) * radius * 1.5)
                        if j == 0 { shape.move(to: pt) } else { shape.addLine(to: pt) }
                    }
                } else {
                    // Android cubicTo pair (a heart), sampled before the perspective map.
                    let curves: [[(Double, Double)]] = [[(x, y - 0.055), (x - 0.09, y + 0.02), (x - 0.025, y + 0.105), (x, y + 0.045)],
                                                        [(x, y + 0.045), (x + 0.025, y + 0.105), (x + 0.09, y + 0.02), (x, y - 0.055)]]
                    shape.move(to: m.map(x, y - 0.055))
                    for curve in curves {
                        for step in 1...12 {
                            let t = Double(step) / 12
                            let s = 1 - t
                            let px = s * s * s * curve[0].0 + 3 * s * s * t * curve[1].0 + 3 * s * t * t * curve[2].0 + t * t * t * curve[3].0
                            let py = s * s * s * curve[0].1 + 3 * s * s * t * curve[1].1 + 3 * s * t * t * curve[2].1 + t * t * t * curve[3].1
                            shape.addLine(to: m.map(px, py))
                        }
                    }
                }
                shape.closeSubpath()
                fillPath(c, shape, i % 2 == 0 ? 0xffffe796 : 0xffffb5d0)
                let dot = CGMutablePath()
                wallOval(m, x + 0.06, y + 0.01, 0.007, 0.007, dot)
                fillPath(c, dot, 0xccffffff)
            }
            if session.kind?.isTarget == true {
                // Stroke width .006 in wall space: each ring is the band between two mapped ovals.
                for radius in [0.46, 0.30, 0.18, 0.08] {
                    let ring = CGMutablePath()
                    wallOval(m, 0.5, 0.5, radius / 1.4 + 0.003, radius + 0.003, ring)
                    wallOval(m, 0.5, 0.5, radius / 1.4 - 0.003, radius - 0.003, ring)
                    fillPath(c, ring, 0xff173d60, evenOdd: true)
                }
            }
            // The border: stroke width .015 in wall space.
            let border = CGMutablePath()
            wallQuad(m, -0.0075, -0.0075, 1.0075, 1.0075, border)
            wallQuad(m, 0.0075, 0.0075, 0.9925, 0.9925, border)
            fillPath(c, border, engine.config.wallBattle ? Teams.style(wall.id).color : 0xff19b8b1, evenOdd: true)
            if renderWidth == 0 {
                let at = screen(wall.world(0.5, 1.0), wall.height + 1.3)
                let title: String
                if engine.config.wallBattle {
                    title = Teams.style(wall.id).name(engine.hebrew)
                } else if let challenge = engine.config.challenge {
                    title = engine.hebrew ? challenge.he : AppText.t(challenge.en)
                } else {
                    title = ""
                }
                let tw = measure(title, 12) + 24
                rounded(c, ltrb(at.x - tw / 2, at.y - 17, at.x + tw / 2, at.y + 6), 8, 0xee183953)
                text(title, at.x, at.y, 12, white, bold: true)
            }
        }
    }

    private func drawGameObjects(_ c: CGContext, inset: Bool = false) {
        let a = local
        drawWalls(c)
        drawDrill(c)
        // Passing drills and dodging drills have no answer balloons on screen.
        let showChoices = a.held == nil && !engine.paintSession.passing && engine.drill?.spec.defending != true
        if a.held == nil {
            var best: Choice? = nil
            var bestDistance = Double.greatestFiniteMagnitude
            for choice in a.choices {
                let distance = (choice.position - a.position).length()
                if distance <= engine.config.pickupRadius && distance < bestDistance {
                    best = choice
                    bestDistance = distance
                }
            }
            highlighted = best?.index ?? -1
        } else {
            highlighted = -1
        }
        choiceRects.removeAll()
        // Private choices are drawn only for this user. Never render remote question sets.
        if showChoices {
            for choice in a.choices { drawChoice(c, choice) }
        }
        actorRects.removeAll()
        labelRects.removeAll()
        if !inset { nameTargets.removeAll() }
        // Far to near along the camera's view direction.
        let sy = sin(arenaCamera.yaw)
        let cy = cos(arenaCamera.yaw)
        for actor in engine.actors.stableSorted(by: { sy * $0.position.x + cy * $0.position.y < sy * $1.position.x + cy * $1.position.y }) {
            drawActor(c, actor)
        }
        if !inset {
            let ordered = engine.actors.stableSorted { x, y in
                let rx = x.member.id == localId ? 0 : 1
                let ry = y.member.id == localId ? 0 : 1
                if rx != ry { return rx < ry }
                return x.member.id.javaPrecedes(y.member.id)
            }
            for actor in ordered { drawActorLabel(c, actor) }
        }
        // Keep personal answer faces legible even when a body overlaps their world position.
        if showChoices {
            for choice in a.choices {
                guard let face = choiceRects[choice.index] else { continue }
                if actorRects.contains(where: { $0.rect.intersects(face) }) { drawChoice(c, choice) }
            }
        }
        if !inset && a.held != nil && a.settings.throwing == .standard {
            drawAim(c, a)
        } else if !inset {
            aimPoints.removeAll()
            aimGripRect = .null
        }
        for shot in engine.shots { drawShot(c, shot) }
        drawParticles(c)
    }

    /// The live close-up of the local player above the action (portrait only).
    private func drawBillboard(_ c: CGContext) {
        billboard = billboardBounds()
        if billboard.isEmpty { return }
        let savedCamera = arenaCamera
        let savedActors = actorRects
        let savedChoices = choiceRects
        let savedLabels = labelRects
        renderWidth = Int(billboard.width)
        renderHeight = Int(billboard.height)
        arenaCamera = closeCamera()
        c.saveGState()
        c.clip(to: billboard)
        c.translateBy(x: billboard.minX, y: billboard.minY)
        drawFloorEffects(c)
        drawGameObjects(c, inset: true)
        c.restoreGState()
        arenaCamera = savedCamera
        renderWidth = 0
        renderHeight = 0
        actorRects = savedActors
        choiceRects = savedChoices
        labelRects = savedLabels
        c.setStrokeColor(SplashPalette.ui(0xff82f4e9).cgColor)
        c.setLineWidth(2)
        c.addPath(UIBezierPath(roundedRect: billboard, cornerRadius: 10).cgPath)
        c.strokePath()
        let header = ltrb(billboard.minX, billboard.minY, billboard.maxX, billboard.minY + 24)
        rounded(c, header, 4, 0xee163b50)
        text(tr("Whole field · live", "כל המגרש · שידור חי"), header.midX, header.midY, 11, white, bold: true)
    }

    private func drawFloorEffects(_ c: CGContext) {
        if engine.paintSession.passing {
            // Where each pass will come down at catching height.
            for shot in engine.shots where shot.owner != localId {
                let gravity = engine.config.gravity * (engine.actor(shot.owner)?.settings.projectileGravityFactor ?? 1.0)
                let t = (shot.vz + sqrt(shot.vz * shot.vz + 2 * gravity * max(shot.height - 1.05, 0.0))) / gravity
                let target = shot.position + shot.velocity * t
                let pos = screen(target)
                let ring = ltrb(pos.x - 30, pos.y - 12, pos.x + 30, pos.y + 12)
                fillOval(c, ring, SplashPalette.ui(0x5536e6cb))
                c.setStrokeColor(SplashPalette.ui(0xff8affdf).cgColor)
                c.setLineWidth(3)
                c.strokeEllipse(in: ring)
            }
        }
        for b in engine.bursts {
            let pos = screen(b.position)
            let age = engine.time - b.at
            let alpha = min(max(KotlinNumber.int(130 * (1 - age / 7)), 0), 130)
            art.splash(3, b.color)?.draw(in: ltrb(pos.x - 24, pos.y - 9, pos.x + 24, pos.y + 9), blendMode: .normal, alpha: CGFloat(alpha) / 255)
        }
    }

    private func displayText(_ text: String) -> String {
        return local.question?.skill == .english ? text : AppText.t(text)
    }

    private func drawChoice(_ c: CGContext, _ ch: Choice) {
        let pos = screen(ch.position)
        let displayAnswer = displayText(ch.text)
        var longest = 0
        for other in local.choices { longest = max(longest, displayText(other.text).utf16.count) }
        let wordChoices = longest > 3
        let cam = camera
        let fraction = longest > 6 ? cam.longWordBalloonWidth : (wordChoices ? cam.wordBalloonWidth : cam.numberBalloonWidth)
        // Landscape balloons follow the height, so they keep their portrait size.
        let reference = sceneWidth > sceneHeight ? Double(sceneHeight) * 1.25 : Double(sceneWidth)
        // The whole-field close-up shows smaller balloons.
        let w = (renderWidth > 0 ? 0.48 : 1) * CGFloat(Float(reference * fraction))
        let h = w * (wordChoices ? 1.22 : 1.02)
        let age = max(engine.time - local.questionAt, 0)
        let pop = age < 0.35 ? sin(age / 0.35 * Double.pi) * 5 : 0.0
        let bob = CGFloat(sin(engine.time * 2.8 + Double(ch.index)) * 1.3 - pop)
        let b = ltrb(pos.x - w / 2, pos.y - h + bob, pos.x + w / 2, pos.y + bob)
        choiceRects[ch.index] = b
        fillOval(c, ltrb(pos.x - w * 0.32, pos.y - 3, pos.x + w * 0.32, pos.y + 5), SplashPalette.ui(0x55302b47))
        if (ch.position - local.position).length() <= engine.config.pickupRadius {
            c.setStrokeColor(SplashPalette.ui(0xffd5fff5).cgColor)
            c.setLineWidth(2.5)
            c.strokeEllipse(in: ltrb(pos.x - w * 0.62, pos.y - 6, pos.x + w * 0.62, pos.y + 7))
            text(tr("TAP", "געו"), pos.x, b.minY - 5, 9, 0xffd5fff5, bold: true)
        }
        let squash = age < 0.4 ? CGFloat(sin(age / 0.4 * Double.pi) * 0.12) : 0
        c.saveGState()
        scale(c, 1 + squash, 1 - squash, b.midX, b.maxY)
        let balloon = wordChoices ? art.wordBalloon(ch.color) : art.balloon(ch.color)
        balloon?.draw(in: b)
        c.restoreGState()
        let label = ltrb(b.midX - w * 0.34, b.minY + h * 0.40, b.midX + w * 0.34, b.minY + h * 0.86)
        var answerSize: CGFloat = longest > 10 ? 10.5 : (wordChoices ? 12 : 17)
        if wordChoices {
            var widest: CGFloat = 0
            for word in displayAnswer.components(separatedBy: " ") { widest = max(widest, measure(word, answerSize)) }
            if widest > label.width { answerSize = max(answerSize * label.width / widest, 9.5) }
        }
        paragraph(displayAnswer, label, answerSize, ink, maxLines: 2, rtl: AppText.rtl && local.question?.skill != .english)
    }

    /// Characters are sized by their visible body (feet to a head 4.7 world units above).
    private func drawActor(_ c: CGContext, _ a: SplashActor) {
        let feet = screen(a.position, a.height)
        let frameIndex = SplashPose.frame(a, engine.time)
        guard let visual = art.visual(a, frameIndex, arenaCamera.yaw) else { return }
        let frame = visual.frame
        let head = screen(a.position, a.height + 4.7)
        let minimum: CGFloat = renderWidth > 0 ? 6 : 28
        let visibleHeight = min(max(feet.y - head.y, minimum), CGFloat(sceneHeight) * 0.65)
        let anchor = art.anchor(a.member.character, visual)
        let b = anchor.destination(Float(feet.x), Float(feet.y), Float(visibleHeight), Int(frame.rect.width), Int(frame.rect.height),
                                   mirrored: visual.mirrored)
        let h = b.height
        let size = b.width
        let sx = visibleHeight / CGFloat(anchor.height)
        let half = CGFloat(anchor.right - anchor.left) * sx / 2
        setActorRect(a.member.id, ltrb(feet.x - half, feet.y - visibleHeight, feet.x + half, feet.y))
        let ground = screen(a.position)
        let sh = CGFloat(min(max(1 - a.height * 0.18, 0.5), 1.0))
        fillOval(c, ltrb(ground.x - size * 0.28 * sh, ground.y - 3, ground.x + size * 0.28 * sh, ground.y + 6), SplashPalette.ui(0x603d1738))
        // Ground contact shadow above remains fixed while the character jumps.
        var alpha: CGFloat = 1
        if engine.time < a.shieldUntil && KotlinNumber.int(engine.time * 12) % 2 == 0 { alpha = 170.0 / 255.0 }
        let body = art.painted(a, frameIndex, arenaCamera.yaw) ?? frame.image
        c.saveGState()
        if visual.mirrored { scale(c, -1, 1, b.midX, b.midY) }
        body?.draw(in: b, blendMode: .normal, alpha: alpha)
        c.restoreGState()
        if let held = a.held {
            let color = a.choices.first(where: { $0.index == held })?.color ?? a.publicHeldColor
            let fx = frame.handX / max(frame.rect.width, 1)
            let hx = b.minX + (visual.mirrored ? 1 - fx : fx) * size
            let hy = b.minY + frame.handY / max(frame.rect.height, 1) * h
            let sw = size * 0.29
            let sway = CGFloat(sin(engine.time * 4) * 1.2)
            art.balloon(color)?.draw(in: ltrb(hx - sw / 2, hy - sw * 0.65 + sway, hx + sw / 2, hy + sw * 0.35 + sway))
        }
        if !a.paint.isEmpty {
            let pw: CGFloat = 7
            let layers = engine.config.paintLayers
            let px = feet.x - CGFloat(layers - 1) * pw * 0.7
            let r = pw * 0.46
            for i in 0..<layers {
                let color = i < a.paint.count ? colors[min(max(a.paint[i].color, 0), 5)] : 0xff243a50
                let dot = CGRect(x: px + CGFloat(i) * pw * 1.4 - r, y: b.minY - 7 - r, width: r * 2, height: r * 2)
                fillOval(c, dot, SplashPalette.ui(color))
                c.setStrokeColor(SplashPalette.ui(white).cgColor)
                c.setLineWidth(1)
                c.strokeEllipse(in: dot)
            }
            if engine.time - a.hitAt < 0.7, let mark = a.paint.last {
                text(tr("SPLASH!", "פגיעה!"), feet.x, b.minY - 22, 14, colors[min(max(mark.color, 0), 5)], bold: true)
            }
        }
    }

    /// Name tags stay in their slot until something actually covers them; a thin leader line
    /// joins a moved tag to its player. The local tag wears the colour rank.
    private func drawActorLabel(_ c: CGContext, _ a: SplashActor) {
        let feet = screen(a.position, a.height)
        let ground = screen(a.position)
        let name: String
        if a.member.id == localId {
            name = tr("You", "אתם")
        } else if a.member.bot {
            name = Characters.get(a.member.character).name(engine.hebrew)
        } else {
            name = a.member.name
        }
        let team = Teams.style(a.member.team)
        let teams = engine.mode == .teams
        let label = teams ? team.emblem + " " + name : name
        let nameSize: CGFloat = engine.actors.count > 6 ? 10.5 : 12
        let labelWidth = measure(label + " · \(a.score)", nameSize) + 18
        if renderWidth > 0 { return }
        let top: CGFloat = landscape ? 70 : viewHeight * 0.42
        let bottom: CGFloat = landscape ? viewHeight - 135 : min(viewHeight * 0.84, viewHeight - 144)
        let area = LabelBox(4, Float(top), Float(viewWidth - 8), Float(bottom - top))
        var obstacles: [LabelBox] = []
        for r in actorRects.map({ $0.rect }) + Array(choiceRects.values) + (drillObstacle.map { [$0] } ?? []) {
            obstacles.append(LabelBox(Float(r.minX - 2), Float(r.minY - 2), Float(r.width + 4), Float(r.height + 4)))
        }
        let used = labelRects.map { LabelBox(Float($0.minX), Float($0.minY), Float($0.width), Float($0.height)) }
        let b = stableLabels.place(a.member.id, Float(feet.x), Float(ground.y + 8), Float(min(labelWidth, viewWidth * 0.6)), 22,
                                   area, obstacles, used, 24)
        let tag = CGRect(x: CGFloat(b.x), y: CGFloat(b.y), width: CGFloat(b.w), height: CGFloat(b.h))
        setNameTarget(a.member.id, tag)
        if hypot(CGFloat(b.cx) - feet.x, CGFloat(b.y) - ground.y) > 30 {
            line(c, feet.x, ground.y, CGFloat(b.cx), CGFloat(b.cy), 1, 0x8891e9ed)
        }
        labelRects.append(tag)
        let rank = SplashRanks.at(rankPoints)
        let mine = a.member.id == localId
        rounded(c, tag, 8, mine ? rank.color : (teams ? team.color : 0xe0092037))
        text(label + " · \(a.score)", tag.midX, tag.midY, nameSize, mine ? rank.ink : (teams ? team.ink : white), bold: true)
    }

    private func drawAim(_ c: CGContext, _ a: SplashActor) {
        let dir = a.direction.unit()
        let releaseHeight = a.height + (engine.time < a.crouchUntil ? 0.48 : 1.15)
        aimPoints.removeAll()
        guard let visual = art.visual(a, SplashPose.frame(a, engine.time), arenaCamera.yaw),
              let body = actorRects.first(where: { $0.id == a.member.id })?.rect else { return }
        let sprite = visual.frame
        let anchor = art.anchor(a.member.character, visual)
        let destination = anchor.destination(Float(body.midX), Float(body.maxY), Float(body.height), Int(sprite.rect.width),
                                             Int(sprite.rect.height), mirrored: visual.mirrored)
        let fx = sprite.handX / max(sprite.rect.width, 1)
        let origin = CGPoint(x: destination.minX + (visual.mirrored ? 1 - fx : fx) * destination.width,
                             y: destination.minY + sprite.handY / max(sprite.rect.height, 1) * destination.height)
        let path = CGMutablePath()
        path.move(to: origin)
        aimPoints.append(origin)
        let gravity = engine.config.gravity * a.settings.projectileGravityFactor
        let speed = engine.throwSpeed(a)
        let lift = engine.launchLift(a)
        for i in 1...22 {
            let t = Double(i) * 0.052
            let pos = a.position + dir * (0.42 + speed * t)
            let z = releaseHeight + lift * t - 0.5 * gravity * t * t
            let pt = screen(pos, z)
            path.addLine(to: pt)
            aimPoints.append(pt)
        }
        // The dashed arc never covers a character (Android clipOutRect per body).
        c.saveGState()
        let whole = CGRect(x: -viewWidth, y: -viewHeight, width: viewWidth * 3, height: viewHeight * 3)
        for entry in actorRects {
            c.addRect(whole)
            c.addRect(entry.rect)
            c.clip(using: .evenOdd)
        }
        c.setStrokeColor(SplashPalette.ui(0xfff4ffd4).cgColor)
        c.setLineWidth(2.3)
        c.setLineDash(phase: 0, lengths: [5, 5])
        c.addPath(path)
        c.strokePath()
        c.restoreGState()
        let reach = CGFloat(engine.config.arcTouchDp)
        let exclusion = body.insetBy(dx: -reach, dy: -reach)
        let avoid = (actorRects.map { $0.rect } + nameTargets.map { $0.rect }).map { $0.insetBy(dx: -3, dy: -3) }
        let minimumY: CGFloat = landscape ? 75 : 170
        let reachable = aimPoints.dropFirst(5).first { p in
            !exclusion.contains(p) && !avoid.contains(where: { $0.contains(p) }) && !billboard.contains(p) && !cameraButton.contains(p)
                && !orbitRect.contains(p) && !buttons.values.contains(where: { $0.contains(p) })
                && p.x > 30 && p.x < viewWidth - 30 && p.y > minimumY && p.y < viewHeight * 0.84
        }
        let grip = reachable ?? (tutorialStep < 0 ? CGPoint(x: 89, y: viewHeight - (landscape ? 72 : 121)) : aimPoints[aimPoints.count - 1])
        aimGrip = CGPoint(x: min(max(grip.x, 26), viewWidth - 26), y: min(max(grip.y, landscape ? 75 : 175), viewHeight * 0.84))
        aimGripRect = ltrb(aimGrip.x - 22, aimGrip.y - 22, aimGrip.x + 22, aimGrip.y + 22)
        // The arc itself is the control; its forgiving hit area is invisible.
        // When the whole arc is occluded, the labeled Throw action remains reachable.
    }

    private func drawShot(_ c: CGContext, _ s: Shot) {
        let pos = screen(s.position, s.height)
        let ground = screen(s.position)
        fillOval(c, ltrb(ground.x - 7, ground.y - 2, ground.x + 7, ground.y + 3), SplashPalette.ui(0x40351f40))
        let size = viewWidth * 0.066
        c.saveGState()
        c.translateBy(x: pos.x, y: pos.y)
        c.rotate(by: CGFloat(atan2(s.velocity.y, s.velocity.x) + Double.pi / 2))
        c.translateBy(x: -pos.x, y: -pos.y)
        art.balloon(s.color)?.draw(in: ltrb(pos.x - size * 0.42, pos.y - size * 0.58, pos.x + size * 0.42, pos.y + size * 0.58))
        c.restoreGState()
    }

    private func drawParticles(_ c: CGContext) {
        var budget = engine.config.particleLimit
        for b in engine.bursts {
            let age = engine.time - b.at
            if age < 0 || age > 1.1 { continue }
            let burstCenter = screen(b.position, b.height)
            let size = viewWidth * CGFloat(0.095 * (0.45 + min(age, 0.25) * 3))
            let splashAlpha = CGFloat(KotlinNumber.int((1 - age / 1.1) * 245)) / 255
            art.splash(age < 0.15 ? 4 : 0, b.color)?.draw(in: ltrb(burstCenter.x - size, burstCenter.y - size, burstCenter.x + size, burstCenter.y + size),
                                                          blendMode: .normal, alpha: splashAlpha)
            let dropAlpha = KotlinNumber.int((1 - age / 1.1) * 255)
            let dropColor = SplashPalette.ui(colors[min(max(b.color, 0), 5)], alpha: dropAlpha)
            let spin = Double(b.id.javaHashCode % 6)
            for i in 0..<16 {
                if budget <= 0 { break }
                budget -= 1
                let angle = Double(i) * 2.399 + spin
                let speed = Double(18 + i % 5 * 5)
                let dx = CGFloat(cos(angle) * speed * age)
                let dy = CGFloat(sin(angle) * speed * age + 48 * age * age)
                fillOval(c, ltrb(burstCenter.x + dx, burstCenter.y + dy, burstCenter.x + dx + 3, burstCenter.y + dy + CGFloat(3 + i % 3)), dropColor)
            }
        }
    }

    private func drawHud(_ c: CGContext) {
        buttons.removeAll()
        buttonOrder.removeAll()
        let top: CGFloat = 7
        let barBottom = top + 43
        rounded(c, ltrb(10, top, viewWidth - 10, barBottom), 16, 0xe0132746)
        let back = ltrb(14, top + 3, 53, barBottom - 3)
        setButton("back", back)
        rounded(c, back, 12, 0xffe91e63)
        text("❮", back.midX, back.midY, 22, white, bold: true)
        let rotate = ltrb(60, top + 3, 99, barBottom - 3)
        setButton("rotate", rotate)
        rounded(c, rotate, 10, 0xff316577)
        text("↻", rotate.midX, rotate.midY, 23, white, bold: true)
        let left = KotlinNumber.int(ceil(max(engine.config.duration - engine.time, 0.0)))
        if left != timerSecond {
            timerSecond = left
            let seconds = left % 60
            timerText = "\(left / 60):" + (seconds < 10 ? "0" : "") + "\(seconds)"
        }
        if engine.config.challenge?.untimed == true { timerText = "∞" }
        if !landscape {
            text(engine.practice ? tr("Practice", "תרגול") : timerText, viewWidth * 0.52, top + 22, 19, white, bold: true)
        }
        text(tr("You", "אתם") + " \(local.score)", viewWidth - 49, top + 22, 13, SplashRanks.at(rankPoints).color, bold: true)
        let q = landscape ? ltrb(viewWidth * 0.30, top, viewWidth * 0.73, top + 61) : ltrb(16, barBottom + 9, viewWidth - 16, barBottom + 76)
        rounded(c, q, 14, 0xe0113447)
        let defending = engine.drill?.spec.defending == true
        let question: String
        if defending, let challenge = engine.config.challenge {
            question = engine.hebrew ? challenge.he : AppText.t(challenge.en)
        } else if engine.paintSession.passing {
            question = tr("Keep the balloon flying", "שומרים את הבלון באוויר")
        } else {
            question = local.question?.text(engine.hebrew) ?? ""
        }
        let number = SplashArenaView.isolatedNumber(question)
        paragraph(number ? "\u{2066}" + question + "\u{2069}" : AppText.t(question), ltrb(q.minX + 6, q.minY + 4, q.maxX - 6, q.maxY - 23),
                  number ? 25 : 15, white, maxLines: 2, rtl: number ? false : AppText.rtl)
        let caption: String
        if defending {
            caption = tr("Watch the thrower · choose your timing", "עקבו אחרי הזורק · תזמנו את התנועה")
        } else if engine.paintSession.passing {
            caption = tr("Move to catch · tap partner to pass", "זזים לתפיסה · נוגעים בשותף למסירה")
        } else {
            caption = tr("Your question", "השאלה שלכם")
        }
        text(caption, q.midX, q.maxY - 12, 13, 0xff9bf4ec, bold: true)
        setButton("speak", ltrb(q.maxX - 32, q.minY, q.maxX, q.minY + 32))
        if landscape && !engine.practice { text(timerText, 138, top + 22, 16, white, bold: true) }
        if engine.mode == .teams {
            for team in 0...1 {
                let x = team == 0 ? viewWidth * 0.24 : viewWidth * 0.76
                let y: CGFloat = landscape ? top + 75 : 133
                let style = Teams.style(team)
                let score = team < engine.teamScores.count ? engine.teamScores[team] : 0
                text(style.emblem + " \(score)", x, y, 12, style.color, bold: true)
            }
        }
        if !engine.practice {
            let advice = contextAdvice()
            if !advice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let b = ltrb(12, viewHeight - (landscape ? 48 : 84), viewWidth - 12, viewHeight - 8)
                rounded(c, b, 12, 0xe6103048)
                paragraph(advice, ltrb(b.minX + 8, b.minY, b.maxX - 8, b.maxY), landscape ? 13 : 14, white, maxLines: landscape ? 2 : 3)
            }
        }
        if !networkStatus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text(networkStatus, viewWidth / 2, viewHeight - 4, 9, 0xffbdf8ff)
        }
    }

    private func setButton(_ key: String, _ rect: CGRect) {
        if buttons[key] == nil { buttonOrder.append(key) }
        buttons[key] = rect
    }

    private func feedbackExplanation(_ f: Feedback) -> String {
        let value = AppText.t(f.explanation)
        return SplashArenaView.isolatedNumber(value) ? "\u{2066}" + value + "\u{2069}" : value
    }

    /// The journey and wall-battle lines shared by the advice bar and the lesson card (nil otherwise).
    private func paintAdvice() -> String? {
        let session = engine.paintSession
        if session.passing {
            return tr("Catches \(session.catches)/\(session.catchGoal) · Move to the ring. Catch automatically, then tap your partner to pass.",
                      "תפיסות \(session.catches)/\(session.catchGoal) · זוזו לעיגול לתפיסה אוטומטית, ואז געו בשותף כדי למסור.")
        }
        if engine.config.wallBattle && engine.time < local.cleanUntil {
            let seconds = KotlinNumber.int(ceil(local.cleanUntil - engine.time))
            return tr("Resting · back in \(seconds) seconds", "נחים · חוזרים בעוד \(seconds) שניות")
        }
        if session.active {
            let progress: String
            if session.kind == .timedTarget {
                progress = tr("Points \(session.score(0)) : \(session.score(1))", "נקודות \(session.score(0)) : \(session.score(1))")
            } else if session.kind == .target {
                progress = tr("Points \(session.score(0)) : \(session.score(1)) · Throws \(session.throwsTaken[0])/10",
                              "נקודות \(session.score(0)) : \(session.score(1)) · זריקות \(session.throwsTaken[0])/10")
            } else if session.cooperative {
                progress = tr("Painted \(session.score(0))%", "נצבעו \(session.score(0))%")
            } else {
                progress = tr("Paint \(session.score(0))% : \(session.score(1))%", "צביעה \(session.score(0))% : \(session.score(1))%")
            }
            let action = local.held != nil
                ? tr("Tap the wall where you want your balloon to land.", "געו בקיר במקום שאליו תרצו לזרוק את הבלון.")
                : tr("Answer, then collect a balloon. Tap the wall to paint it.", "ענו ואספו בלון. געו בקיר כדי לצבוע אותו.")
            return progress + " · " + action
        }
        return nil
    }

    private func contextAdvice() -> String {
        if let d = engine.drill { return AppText.t(d.advice(engine.hebrew)) }
        if let paint = paintAdvice() { return paint }
        if let f = local.feedback, engine.time < f.expires, !f.correct {
            let why = feedbackExplanation(f)
            return tr("Previous question: \(why) That wrong-answer balloon burst in your hand. Choose the right balloon, then throw!",
                      "השאלה הקודמת: \(why) הבלון עם התשובה השגויה התפוצץ ביד. בחרו את הבלון הנכון ואז זרקו!")
        }
        let threat = engine.shots.first { shot in
            shot.owner != localId && (engine.mode == .solo || engine.actor(shot.owner)?.member.team != local.member.team)
                && (shot.position - local.position).length() < 3.2
        }
        if let threat = threat {
            if threat.height > 1 {
                return tr("Incoming balloon! Double-tap to duck, or move away.", "בלון מתקרב! געו פעמיים כדי להתכופף, או התרחקו.")
            }
            return tr("Low balloon! Tap your character to jump, or dodge.", "בלון נמוך! געו בדמות כדי לקפוץ, או התחמקו.")
        }
        if local.height > 0.2 { return tr("Nice jump! You can still aim and throw in the air.", "קפיצה יפה! אפשר לכוון ולזרוק גם באוויר.") }
        if local.held != nil {
            if local.settings.throwing == .easy {
                return tr("Balloon ready. Tap any ground point or player to throw there.", "הבלון מוכן. געו בנקודה במגרש או בשחקן כדי לזרוק לשם.")
            }
            return tr("Balloon ready. Drag the arc to aim. A faster swipe throws harder; tap to use your saved aim.",
                      "הבלון מוכן. גררו את הקשת לכיוון. החלקה מהירה יותר זורקת חזק יותר; נגיעה משתמשת בכיוון ששמרתם.")
        }
        let tip = KotlinNumber.int(engine.time) / 7 % 3
        if tip == 1 { return tr("Double-tap your character to crouch under a high balloon.", "געו פעמיים בדמות כדי להתכופף מתחת לבלון גבוה.") }
        if tip == 2 { return tr("Tap your character once to jump over a low balloon.", "געו פעם אחת בדמות כדי לקפוץ מעל בלון נמוך.") }
        if local.walkTarget != nil { return tr("On your way! Watch for incoming balloons.", "אתם בדרך! שימו לב לבלונים מתקרבים.") }
        if local.settings.walk == .easy {
            return tr("Solve your question. Tap a balloon to walk over and collect it.", "פתרו את השאלה. געו בבלון כדי להגיע אליו ולאסוף אותו.")
        }
        return tr("Tap a place or drag your character. Tap a nearby glowing balloon.", "געו במקום או גררו את הדמות. געו בבלון מואר קרוב לאיסוף.")
    }

    // MARK: Learn to play

    func beginTutorial() {
        engine.practice = true
        enterLesson(0)
    }

    private func enterLesson(_ step: Int) {
        gesture.cancel()
        tutorialStep = min(max(step, 0), 10)
        lessonDone = false
        lessonStarted = engine.time
        lessonPosition = local.position
        lessonAnswers = local.answers.count
        local.move = V(0, 0)
        local.walkTarget = nil
        local.feedback = nil
        switch tutorialStep {
        case 1: local.settings.walk = .easy
        case 2: local.settings.walk = .standard
        case 4: local.settings.throwing = .easy
        case 5: local.settings.throwing = .standard
        default: break
        }
        if [1, 2, 4, 5, 6].contains(tutorialStep) { engine.resetPracticeQuestion(localId) }
        if [1, 2, 4, 5].contains(tutorialStep) { onControlSettings?(local.settings) }
        canvas.setNeedsDisplay()
    }

    private func updateLesson() {
        let recent = Array(local.answers.dropFirst(min(lessonAnswers, local.answers.count)))
        var done = false
        switch tutorialStep {
        case 1, 2: done = local.held != nil
        case 4, 5: done = recent.contains { $0.correct }
        case 6: done = recent.contains { !$0.correct }
        case 7: done = local.height > 0.25
        case 8: done = engine.time < local.crouchUntil
        case 9: done = recent.filter { $0.correct }.count >= 4
        default: done = false
        }
        lessonDone = lessonDone || done
    }

    private func lessonText() -> String {
        if let paint = paintAdvice() { return paint }
        if let f = local.feedback, !f.correct, engine.time < f.expires {
            let why = feedbackExplanation(f)
            return tr("The previous answer was wrong, so that balloon burst in your hand. \(why) Choose a correct answer and your balloon will fly where you throw it.",
                      "הבלון התפוצץ ביד כי התשובה לשאלה הקודמת הייתה שגויה. \(why) בלון עם תשובה נכונה יעוף לכיוון שתזרקו ולא יתפוצץ ביד.")
        }
        if let held = local.choices.first(where: { $0.index == local.held }), [1, 2, 4, 5].contains(tutorialStep) {
            let correct = held.text == local.question?.answer
            if correct {
                local.hinted = true
                let easy = local.settings.throwing == .easy
                let en = "Great! You picked the balloon with the correct answer. " + (easy
                    ? "Tap your teacher or any ground point to throw. A wrong answer would burst in your hand."
                    : "Drag the aiming arc, then tap it to throw. A wrong answer would burst in your hand.")
                let he = "נהדר! אספתם את הבלון עם התשובה הנכונה. " + (easy
                    ? "געו במורה או בנקודה במגרש כדי לזרוק. תשובה שגויה תתפוצץ ביד."
                    : "גררו את קשת הכיוון ואז געו בה כדי לזרוק. תשובה שגויה תתפוצץ ביד.")
                return tr(en, he)
            }
            return tr("You chose a wrong answer. Try throwing it to see why it bursts. Then choose the correct answer.",
                      "בחרתם תשובה שגויה. נסו לזרוק וראו שהיא מתפוצצת ביד. אחר כך בחרו את התשובה הנכונה.")
        }
        switch tutorialStep {
        case 0:
            return tr("Choose how to walk. Easy: tap an answer balloon to walk and collect it. Standard: walk first, then tap the nearby balloon. Both let you tap a place to walk there.",
                      "בחרו דרך הליכה. קלה: נגיעה בבלון מובילה אליו ואוספת אותו. רגילה: מתקרבים ואז נוגעים בבלון. בשתיהן אפשר לגעת במקום כדי להגיע אליו.")
        case 1:
            return tr("Try Easy walking: solve the question and tap its balloon. Your character walks there and picks it up.",
                      "נסו הליכה קלה: פתרו את השאלה וגעו בבלון המתאים. הדמות תגיע אליו ותאסוף אותו.")
        case 2:
            return tr("Try Standard walking: drag from your character, or tap a place. When a balloon glows nearby, tap it to collect.",
                      "נסו הליכה רגילה: גררו מהדמות או געו במקום. כשהבלון הקרוב מואר, געו בו לאיסוף.")
        case 3:
            return tr("Choose how to throw. Standard: tap any ground point or player. Hard: aim with the arc and swipe faster for more power. Try both.",
                      "בחרו דרך זריקה. רגילה: נגיעה בנקודה או בשחקן. קשה: כיוון בקשת והחלקה מהירה לעוצמה גבוהה. נסו את שתיהן.")
        case 4:
            return tr("Try Standard throwing: collect the correct balloon, then tap your teacher or a ground point. The balloon flies towards him; he can still dodge.",
                      "נסו זריקה רגילה: אספו בלון נכון ואז געו במורה או בנקודה במגרש. הבלון יעוף אליו; עדיין אפשר להתחמק.")
        case 5:
            return tr("Try Hard throwing: collect a correct balloon. Swipe the arc toward your target and release to throw. Faster means stronger. You can also tap to throw with the saved aim.",
                      "נסו זריקה קשה: אספו בלון נכון. החליקו בקשת לכיוון המטרה ושחררו כדי לזרוק. מהר יותר פירושו חזק יותר. אפשר גם לגעת בקשת כדי להשתמש בכיוון ששמרתם.")
        case 6:
            return tr("Try a wrong answer on purpose. Throw it: it bursts in your hand and adds paint. The correct answer appears, then you can try again.",
                      "נסו בכוונה תשובה שגויה וזרקו: היא מתפוצצת ביד ומוסיפה צבע. התשובה הנכונה תופיע, ואז אפשר לנסות שוב.")
        case 7:
            return tr("Tap your character once to jump over a low balloon. You can jump while holding a balloon. In Andromeda you stay airborne longer.",
                      "געו פעם אחת בדמות כדי לקפוץ מעל בלון נמוך. אפשר לקפוץ גם עם בלון ביד. באנדרומדה נשארים באוויר יותר זמן.")
        case 8:
            return tr("Double-tap the arena to duck under a high balloon. Your character really becomes lower. One tap and two taps are different actions.",
                      "געו פעמיים ברצף בזירה כדי להתכופף מתחת לבלון גבוה. הדמות באמת נעשית נמוכה יותר. נגיעה אחת ושתי נגיעות הן פעולות שונות.")
        case 9:
            return tr("Warm up with four correct answers, at your own pace. You may continue practicing as long as you like. No timer and no ads here.",
                      "תרגלו ארבע תשובות נכונות, בקצב שלכם. אפשר להמשיך לתרגל כמה שרוצים. אין כאן טיימר או פרסומות.")
        default:
            return tr("Ready to splash! Your control choices are saved in Settings. Finish learning to return to the main menu.",
                      "מוכנים להתיז! הבחירות נשמרו בהגדרות. סיימו את הלימוד כדי לחזור לתפריט הראשי.")
        }
    }

    private static let lessonTitlesHe = ["איך הולכים?", "הליכה קלה", "הליכה רגילה", "איך זורקים?", "זריקה רגילה", "זריקה קשה",
                                         "לומדים גם מטעות", "קופצים", "מתכופפים", "תרגול חופשי", "כל הכבוד!"]
    private static let lessonTitlesEn = ["How to walk", "Easy walking", "Standard walking", "How to throw", "Standard throwing",
                                         "Hard throwing", "Learning from mistakes", "Jump", "Duck", "Free practice", "Well done!"]

    private func drawTutorial(_ c: CGContext) {
        let top: CGFloat = landscape ? 76 : 142
        let bottom = landscape ? viewHeight - 12 : min(viewHeight * 0.43, top + 188)
        let b = ltrb(12, top, landscape ? viewWidth * 0.37 : viewWidth - 12, bottom)
        rounded(c, b, 16, 0xf0143c59)
        let titles = engine.hebrew ? SplashArenaView.lessonTitlesHe : SplashArenaView.lessonTitlesEn
        let title = titles[min(max(tutorialStep, 0), titles.count - 1)]
        text((lessonDone ? "✓ " : "") + AppText.t(title), b.midX, top + 15, 17, 0xffa8fff0, bold: true)
        paragraph(lessonText(), ltrb(b.minX + 10, top + 30, b.maxX - 10, b.maxY - 45), 15, white, maxLines: 5)
        let w = (b.width - 20) / 3
        func nav(_ key: String, _ title: String, _ left: CGFloat, _ color: UInt32) {
            let r = ltrb(left, bottom - 38, left + w, bottom - 5)
            setButton(key, r)
            rounded(c, r, 10, color)
            paragraph(title, r, 13, ink, maxLines: 2)
        }
        nav("lessonPrev", tr("Previous", "הקודם"), b.minX + 4, 0xffd0e5ff)
        if tutorialStep == 0 || tutorialStep == 3 {
            nav("lessonEasy", tutorialStep == 3 ? tr("Try Standard", "נסו רגילה") : tr("Try Easy", "נסו קלה"), b.minX + w + 8, 0xffb4f6e7)
            nav("lessonStandard", tutorialStep == 3 ? tr("Try Hard", "נסו קשה") : tr("Try Standard", "נסו רגילה"), b.minX + 2 * w + 12, 0xffffe5a4)
        } else {
            let tryMode = [1, 2, 4, 5].contains(tutorialStep)
            if tryMode {
                nav("lessonOther", tr("Try other mode", "נסו מצב אחר"), b.minX + w + 8, 0xffffe5a4)
            } else {
                nav("lessonRetry", tr("Try again", "נסו שוב"), b.minX + w + 8, 0xffffe5a4)
            }
            let nextTitle: String
            if tutorialStep == 10 {
                nextTitle = tr("Main menu", "תפריט ראשי")
            } else if tryMode {
                nextTitle = tr("Use this mode", "בחירת המצב")
            } else {
                nextTitle = tr("Next", "הבא")
            }
            nav("lessonNext", nextTitle, b.minX + 2 * w + 12, 0xffb4f6e7)
        }
    }

    private func lessonButton(_ key: String) {
        switch key {
        case "lessonPrev":
            let previous: Int
            switch tutorialStep {
            case 1, 2: previous = 0
            case 4, 5: previous = 3
            default: previous = max(tutorialStep - 1, 0)
            }
            enterLesson(previous)
        case "lessonEasy": enterLesson(tutorialStep == 0 ? 1 : 4)
        case "lessonStandard": enterLesson(tutorialStep == 0 ? 2 : 5)
        case "lessonOther":
            let other: Int
            switch tutorialStep {
            case 1: other = 2
            case 2: other = 1
            case 4: other = 5
            default: other = 4
            }
            enterLesson(other)
        case "lessonRetry": enterLesson(tutorialStep)
        case "lessonNext":
            if tutorialStep == 10 {
                tutorialCompleted?()
            } else {
                let next: Int
                switch tutorialStep {
                case 1, 2: next = 3
                case 4, 5: next = 6
                default: next = tutorialStep + 1
                }
                enterLesson(next)
            }
        default: break
        }
    }

    // MARK: Touch

    private func touchAction(_ e: TouchAction) {
        if e.type != "press" { lastTouchSummary = "\(e.type):\(e.target.kind) held=\(String(describing: local.held)) time=\(engine.time)" }
        switch e.type {
        case "press":
            if e.target.kind == .arc { aimStarted[e.pointer] = SplashClock.uptimeMillis() }
            return
        case "end":
            if e.target.kind == .body { command(.move(V(0, 0))) }
            if e.target.kind == .arc {
                aimStarted.removeValue(forKey: e.pointer)
                // A released Hard-throw swipe throws; a cancelled pointer (no drag length) does not.
                if e.dx > 0 { command(.throwBalloon) }
            }
        case "double":
            command(.crouch)
        case "drag":
            let dragScale = engine.config.movementDragDp
            if e.target.kind == .body {
                // Screen drags turn with the camera, so "up" always walks away from the viewer.
                let rx = e.dx / dragScale
                let ry = e.dy / dragScale
                let yaw = arenaCamera.yaw
                let v = V(cos(yaw) * rx + sin(yaw) * ry, -sin(yaw) * rx + cos(yaw) * ry)
                command(.move(v.length() > 1 ? v.unit() : v))
            }
            if e.target.kind == .arc {
                let lift = viewHeight * CGFloat(camera.heightScale)
                let aim = world(CGFloat(e.x), CGFloat(e.y) + lift) - local.position
                let now = SplashClock.uptimeMillis()
                let elapsed = Double(max(now - (aimStarted[e.pointer] ?? now), 40)) / 1000.0
                // Swipe speed in points (dp) per second sets the Hard-throw power.
                let power = PlayFeel.powerFromSwipe(hypot(e.dx, e.dy) / elapsed)
                command(.aim(aim.unit() * power))
            }
        case "tap":
            switch e.target.kind {
            case .body:
                if e.target.balloon >= 0 { collectOrWalk(e.target) } else { command(.jump) }
            case .arc: command(.throwBalloon)
            case .balloon: collectOrWalk(e.target)
            case .opponent:
                focusedOpponent = e.target.actorId
                focusUntil = engine.time + 4.0
                playerCamera = false
                if local.settings.throwing == .easy || engine.paintSession.passing {
                    command(.shootAt(e.target.actorId))
                } else if let other = engine.actor(e.target.actorId) {
                    command(.aim((other.position - local.position).unit()))
                }
            case .world:
                if drillTap(CGFloat(e.x), CGFloat(e.y)) || paintTap(CGFloat(e.x), CGFloat(e.y)) { return }
                let point = world(CGFloat(e.x), CGFloat(e.y))
                if local.held != nil && local.settings.throwing == .easy {
                    command(.aim(point - local.position))
                    command(.throwBalloon)
                } else {
                    command(.walkTo(point))
                }
            }
        default:
            return
        }
    }

    private func collectOrWalk(_ target: TouchTarget) {
        if local.settings.walk == .easy {
            guard let ch = local.choices.first(where: { $0.index == target.balloon }) else { return }
            command(.walkTo(ch.position, questionId: target.questionId, index: target.balloon))
        } else {
            command(.pickup(questionId: target.questionId, index: target.balloon))
        }
    }

    private func allocatePointer(_ touch: UITouch) -> Int {
        let key = ObjectIdentifier(touch)
        if let existing = pointerIds[key] { return existing }
        var id = 0
        while touchesById[id] != nil { id += 1 }
        pointerIds[key] = id
        touchesById[id] = touch
        return id
    }

    private func releasePointer(_ touch: UITouch) -> Int? {
        let key = ObjectIdentifier(touch)
        guard let id = pointerIds.removeValue(forKey: key) else { return nil }
        touchesById.removeValue(forKey: id)
        return id
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches.sorted(by: { $0.timestamp < $1.timestamp }) {
            let first = touchesById.isEmpty
            let id = allocatePointer(touch)
            let p = touch.location(in: self)
            if first {
                // Android ACTION_DOWN: the camera controls and the close-up come before gestures.
                if buttons["rotate"]?.contains(p) == true {
                    gesture.cancel()
                    onRotate?()
                    continue
                }
                if cameraButton.contains(p) && tutorialStep < 0 {
                    gesture.cancel()
                    // With a balloon in Hard throwing the button is "Throw balloon".
                    if local.held != nil && local.settings.throwing == .standard {
                        command(.throwBalloon)
                    } else {
                        playerCamera.toggle()
                    }
                    continue
                }
                if orbitRect.contains(p) && tutorialStep < 0 {
                    orbitPointer = id
                    orbitX = p.x
                    gesture.cancel()
                    continue
                }
                if !billboard.isEmpty && billboard.contains(p) { continue }
            }
            if orbitPointer >= 0 { continue }
            activePointers.insert(id)
            pointerDown(id, p.x, p.y, Int64(touch.timestamp * 1000), first)
        }
    }

    private func pointerDown(_ id: Int, _ x: CGFloat, _ y: CGFloat, _ now: Int64, _ first: Bool) {
        let point = CGPoint(x: x, y: y)
        if first {
            if buttons["back"]?.contains(point) == true {
                stop()
                onExit()
                return
            }
            if buttons["speak"]?.contains(point) == true {
                onSpeak(AppText.t(local.question?.text(engine.hebrew) ?? ""))
                return
            }
            if let key = buttonOrder.first(where: { $0.hasPrefix("lesson") && buttons[$0]?.contains(point) == true }) {
                lessonButton(key)
                return
            }
        }
        let body = actorRects.first(where: { $0.id == localId })?.rect
        let bodyTarget = body?.insetBy(dx: -9, dy: -7).contains(point) ?? false
        // Nearby balloon face has explicit pickup priority, then body, then a wide arc band.
        var choice: Int? = nil
        if local.held == nil {
            var nearest = CGFloat.greatestFiniteMagnitude
            for ch in local.choices {
                guard let rect = choiceRects[ch.index], rect.contains(point) else { continue }
                let reachable = local.settings.walk == .easy || (ch.position - local.position).length() <= engine.config.pickupRadius
                let dx = rect.midX - x
                let dy = rect.midY - y
                let d = dx * dx + dy * dy
                if reachable && d < nearest {
                    nearest = d
                    choice = ch.index
                }
            }
        }
        func opposing(_ actorId: String) -> Bool {
            return actorId != localId && (engine.mode == .solo || engine.actor(actorId)?.member.team != local.member.team)
        }
        var opponent: String? = nil
        if local.held != nil && !bodyTarget {
            // Name tags first (stable, easy to touch), then the front-most body.
            opponent = nameTargets.first(where: { opposing($0.id) && $0.rect.contains(point) })?.id
                ?? actorRects.last(where: { opposing($0.id) && $0.rect.contains(point) })?.id
        }
        var core = CGRect.null
        if let body = body {
            core = ltrb(body.midX - body.width * 0.18, body.minY + body.height * 0.25, body.midX + body.width * 0.18, body.minY + body.height * 0.7)
        }
        let hard = local.settings.throwing == .standard
        let questionId = local.question?.id ?? ""
        let target: TouchTarget
        if engine.drill?.spec.aiming == true && local.held != nil {
            // An aiming drill: every touch aims at the target plane.
            target = TouchTarget(kind: .world)
        } else if let opponent = opponent {
            target = TouchTarget(kind: .opponent, actorId: opponent)
        } else if let choice = choice, bodyTarget {
            target = TouchTarget(kind: .body, balloon: choice, questionId: questionId)
        } else if core.contains(point) {
            target = TouchTarget(kind: .body)
        } else if let choice = choice {
            target = TouchTarget(kind: .balloon, balloon: choice, questionId: questionId)
        } else if local.held != nil && hard && aimGripRect.contains(point) {
            target = TouchTarget(kind: .arc)
        } else if bodyTarget {
            target = TouchTarget(kind: .body)
        } else if local.held != nil && hard && nearArc(point) {
            target = TouchTarget(kind: .arc)
        } else {
            target = TouchTarget(kind: .world)
        }
        gesture.down(id, Double(x), Double(y), now, target)
    }

    private func nearArc(_ p: CGPoint) -> Bool {
        guard aimPoints.count >= 2 else { return false }
        let reach = CGFloat(engine.config.arcTouchDp)
        for i in 0..<(aimPoints.count - 1) {
            let a = aimPoints[i]
            let b = aimPoints[i + 1]
            let dx = b.x - a.x
            let dy = b.y - a.y
            let t = min(max(((p.x - a.x) * dx + (p.y - a.y) * dy) / max(dx * dx + dy * dy, 1), 0), 1)
            if hypot(p.x - a.x - t * dx, p.y - a.y - t * dy) < reach { return true }
        }
        return false
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if orbitPointer >= 0 {
            // Android: an orbit drag turns the camera 1 radian per 145 dp and owns the gesture.
            if let touch = touchesById[orbitPointer], touches.contains(touch) {
                let p = touch.location(in: self)
                orbitYaw += Double((p.x - orbitX) / 145)
                orbitX = p.x
            }
            return
        }
        // Android ACTION_MOVE reports every pointer.
        let ids = touchesById.keys.sorted()
        for id in ids {
            guard let touch = touchesById[id] else { continue }
            let p = touch.location(in: self)
            gesture.move(id, Double(p.x), Double(p.y))
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches.sorted(by: { $0.timestamp < $1.timestamp }) {
            let p = touch.location(in: self)
            guard let id = releasePointer(touch) else { continue }
            let lastPointer = touchesById.isEmpty
            if orbitPointer >= 0 {
                if lastPointer { orbitPointer = -1 }
                continue
            }
            if !running && lastPointer {
                start()
                continue
            }
            activePointers.remove(id)
            gesture.up(id, Double(p.x), Double(p.y), Int64(touch.timestamp * 1000))
            // Recognition has its own deadline; a busy graphics frame must not postpone a tap.
            let delay = UInt64(engine.config.doubleTapMs + 1) * 1_000_000
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: delay)
                guard let self = self, self.running else { return }
                self.gesture.flush(SplashClock.uptimeMillis())
            }
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { _ = releasePointer(touch) }
        if orbitPointer >= 0 {
            orbitPointer = -1
            return
        }
        activePointers.removeAll()
        gesture.cancel()
    }
}
