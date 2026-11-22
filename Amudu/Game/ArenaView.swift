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
    /// Android `networkWaiting`: the room's connection is lost (or a guest's snapshots stopped); input is blocked, but a
    /// guest keeps playing back the known ball path.
    var networkWaiting = false
    /// Android `speechAvailable`: the "…" phrase button shows only while the speech engine works.
    var speechAvailable = false

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
    /// Android `catchButton` / `duckButton`: the match action bar (Catch, Jump ↑, Duck) while the ball is loose.
    private(set) var catchRect = CGRect.zero
    private(set) var duckRect = CGRect.zero
    private var practiceObstacle: CGRect?
    private let paintEffects = PaintEffects()
    /// Android `displayedAim`: the moving target dot of the Standard (timed target) control, as last drawn.
    private var displayedAim: TargetThrow.Aim?
    /// Android `attackFlight` / `attackTarget`: the defender an attack is heading for (camera framing only).
    private var attackFlight = ""
    private var attackTarget: String?

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
        // The world view is opaque: if its art did not load (bug report 2026-11-22: the park, grass and sky were all
        // missing because the five world textures were not in the Spud bundle), the arena picture shows, never navy.
        world.isHidden = !world.ready
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

    private func fieldBottom() -> CGFloat { return wide ? bounds.height - 70 : bounds.height * 0.845 }

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
        LagDiagnostics.frame(numericCast(ms))
        // A late packet does not stop a known ballistic path. Input remains blocked by the reconnect overlay.
        if remote {
            remoteUpdate?()
        } else if !networkWaiting {
            engine.tick(Double(ms) / 1000.0)
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
        if engine.phase == .resolve && engine.statusSerial > 0 && engine.time - engine.phaseAt >= 2.0 && shownStatus != engine.statusSerial {
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

    /// Android `tr`: the localized text ("balloon" for "ball" with the paint balloon) with the stop call replaced by this
    /// rule set's call (SPUD letters word).
    private func tr(_ en: String, _ he: String) -> String {
        let stop = ArenaView.trimBang(GameText.stopCall())
        let call = ArenaView.trimBang(RuleText.call(engine.config.rules))
        let text = ProjectileText.apply(GameText.t(en, he, hebrew: hebrew), kind: engine.config.ball, language: hebrew ? "he" : AppText.language)
        if stop.isEmpty || stop == call { return text }
        return text.replacingOccurrences(of: stop, with: call)
    }

    // MARK: Camera (Android `updateWorld`, `aimedCamera`, `targetCamera`, `framedCamera`)

    private func updateWorld() {
        let now = uptimeMs()
        let initial = cameraAt == 0
        let dt = initial ? 0.0 : Double(now - cameraAt) / 1000.0
        cameraAt = now
        let action = attackCamera()
        let base = practiceCamera() ?? action ?? aimedCamera() ?? framedCamera(targetCamera())
        normalCamera = base
        // Ground-only framing can lose a tall name-call toss above the screen. Anticipate
        // the ascent for smooth zoom-out, then contain the actual ball after camera easing.
        let target = frameAirborneBall(action != nil ? base : receptionCamera(base, dt), 0.35)
        let eased = initial ? target : arenaCamera.toward(target, min(dt, 0.033))
        arenaCamera = frameAirborneBall(eased, 0.0)
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

    /// Android `frameAirborneBall`: backs the camera off just enough to keep a loose airborne ball (and, with `lead`, where
    /// it is rising to) on screen. Presentation only.
    private func frameAirborneBall(_ base: ArenaCamera, _ lead: Double) -> ArenaCamera {
        let b = engine.ball
        if engine.practice != nil || b.holder != nil || !(engine.phase == .air || engine.phase == .flight || engine.phase == .retrieve) {
            return base
        }
        let gravity = engine.config.scene.gravity
        let ahead = min(lead, max(0.0, b.vz) / gravity)
        let futureHeight = max(b.height, b.height + b.vz * ahead - 0.5 * gravity * ahead * ahead)
        let points: [(Double, Double, Double)] = [(b.position.x, b.position.y, b.height * 2),
                                                  (b.position.x + b.velocity.x * ahead, b.position.y + b.velocity.y * ahead, futureHeight * 2)]
        let w = Double(bounds.width)
        let h = Double(bounds.height)
        return AirborneFraming.fit(base, points, w, h, Double(fieldLeft()) + 16, w - 24, Double(fieldTop()) + 20, Double(fieldBottom()) - 12)
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
                          close.project(nearBall.x, nearBall.y, ball.height * 2, w, h)]
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
        let shown = engine.actors.filter { !$0.member.bot || d.stage.cooperative || d.stage.defence || d.stage.skill == .tag }
        let positions = shown.map { $0.position } + [d.target]
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

    /// Android `attackCamera`: during an attack and its first 2.1 s of outcome, frame the defender the ball is heading for
    /// (chosen once per flight), the players near them and the ball.
    private func attackCamera() -> ArenaCamera? {
        if engine.practice != nil { return nil }
        let flight = engine.phase == .flight
        let aftermath = engine.phase == .resolve && engine.time - engine.phaseAt < 2.1
        if !flight && !aftermath {
            attackFlight = ""
            attackTarget = nil
            return nil
        }
        let b = engine.ball
        if flight && attackFlight != b.flightId {
            attackFlight = b.flightId
            let direction = b.velocity.unit()
            var best: GameActor?
            var bestScore = Double.infinity
            for a in engine.activeActors where a.member.id != engine.thrower {
                let d = a.position - b.position
                let along = d.x * direction.x + d.y * direction.y
                let score = along < 0 ? 1000.0 + d.length() : abs(d.x * direction.y - d.y * direction.x) * 4 + along * 0.15
                if best == nil || score < bestScore {
                    best = a
                    bestScore = score
                }
            }
            attackTarget = best?.member.id
        }
        guard let id = b.holder ?? attackTarget, let target = engine.actor(id)?.position else { return nil }
        let vicinity = engine.activeActors.filter { ($0.position - target).length() < 4 }.map { $0.position }
        var points: [(Double, Double, Double)] = []
        for p in vicinity + [target] {
            points.append((p.x, p.y, 0.0))
            points.append((p.x, p.y, 4.0))
        }
        points.append((b.position.x, b.position.y, b.height * 2))
        let mid = target * 0.72 + b.position * 0.28
        let w = Double(bounds.width)
        let h = Double(bounds.height)
        let left = Double(fieldLeft()) + 12
        let right = w - 20
        let top = Double(fieldTop()) + 8
        let bottom = Double(fieldBottom()) - 8
        if right <= left || bottom <= top { return nil }
        return TightFraming.fit(arenaCamera.copy(x: mid.x, y: mid.y, focusHeight: 1.0, tilt: 0.86), points, w, h, left, right, top, bottom, 16.0)
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
        let followed = engine.ball.holder ?? ((engine.phase == .air || engine.phase == .retrieve || engine.phase == .resolve) ? engine.called : engine.thrower)
        let actor = engine.actor(followed)?.position ?? me
        let ball = engine.ball
        let focus: V
        switch engine.phase {
        case .air: focus = ball.vz > 0 ? ball.position : actor * 0.7 + ball.position * 0.3
        case .retrieve: focus = actor * 0.5 + ball.position * 0.5
        case .shout, .aim, .flight: focus = actor * 0.5 + ball.position * 0.5
        default: focus = engine.ball.holder != nil ? actor : ball.position
        }
        let distance: Double
        switch engine.phase {
        case .air: distance = 24.0 + ball.height * 0.48
        case .aim, .shout: distance = 27.0
        default: distance = 24.0
        }
        let middle = engine.phase == .resolve ? focus : me * 0.30 + focus * 0.70
        let base = normalCamera.copy(x: middle.x, y: middle.y, distance: Kotlin.clamp(distance, 20.0, 40.0),
                                     focusHeight: engine.phase == .air ? ball.height * 0.30 : 0.0)
        var framed: [(Double, Double)] = engine.phase == .resolve ? [] : [(me.x, me.y)]
        framed.append((actor.x, actor.y))
        framed.append((ball.position.x, ball.position.y))
        let w = Double(bounds.width)
        let h = Double(bounds.height)
        return LandscapeFraming.fit(base, framed, w, h, Double(fieldLeft()), w - 16, Double(fieldTop()), Double(fieldBottom()), 4.2)
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
        // Action view centres on the players (owner's request 2026-11-22), not on the middle of the field.
        let actors = engine.activeActors.map { $0.position }
        let middle = actors.count >= 2
            ? V((actors.map { $0.x }.min()! + actors.map { $0.x }.max()!) / 2, (actors.map { $0.y }.min()! + actors.map { $0.y }.max()!) / 2)
            : V(cfg.width / 2, cfg.depth / 2)
        // Only while everyone stands in the circle does Action view fit all the players; once play starts it follows
        // the action (the thrower, the called player, you and the ball, as `targetCamera` frames them), as portrait
        // does, so the players stay large instead of the whole field shrinking them (owner's request 2026-11-22).
        let fitEveryone = engine.phase == .circle
        var camera = base.copy(x: playerCamera || !fitEveryone ? base.x : middle.x, y: playerCamera || !fitEveryone ? base.y : middle.y,
                               distance: base.distance * 0.78,
                               focusHeight: playerCamera || !fitEveryone ? base.focusHeight : 0.0, centerX: (left + right) / 2 / w,
                               centerY: (top + bottom) / 2 / h, tilt: 0.76)
        if !playerCamera && !fitEveryone {
            // `targetCamera` already fitted you, the followed player and the ball into the field area; keep its
            // distance and only centre it on the field area beside the side column.
            return base.copy(centerX: (left + right) / 2 / w, centerY: (top + bottom) / 2 / h)
        }
        if !playerCamera {
            // Owner's request 2026-11-22 (players too small): landscape Action view frames the players head to toe,
            // not the four field corners as well, so the players fill the view (Android still adds the corners).
            var points: [(Double, Double, Double)] = []
            if engine.activeActors.count < 2 {
                points = [V(0.5, 0.5), V(cfg.width - 0.5, 0.5), V(0.5, cfg.depth - 0.5),
                          V(cfg.width - 0.5, cfg.depth - 0.5)].map { ($0.x, $0.y, 0.0) }
            }
            for a in engine.activeActors {
                points.append((a.position.x, a.position.y, 0.0))
                points.append((a.position.x, a.position.y, 4.0))
            }
            camera = TightFraming.fit(camera, points, w, h, left + 10, right - 10, top + 8, bottom - 8)
        } else if engine.phase == .circle && engine.circleFormation {
            camera = LandscapeFraming.fit(camera, engine.activeActors.map { ($0.position.x, $0.position.y) }, w, h, left, right, top, bottom, 3.8)
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

    /// Android `drawText` at a baseline, centered, right-aligned or left-aligned.
    private func text(_ s: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ color: UInt32 = 0xffffffff, right: Bool = false,
                      left: Bool = false) {
        let f = font(size)
        let attributes: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: argbColor(color)]
        let string = s as NSString
        let width = string.size(withAttributes: attributes).width
        let originX = left ? x : (right ? x - width : x - width / 2)
        string.draw(at: CGPoint(x: originX, y: y - f.ascender), withAttributes: attributes)
    }

    /// Android `paragraphHeight`: the height of `s` laid out in a box `w` wide (minus the 12-point side insets).
    private func paragraphHeight(_ s: String, _ w: CGFloat, _ size: CGFloat) -> CGFloat {
        let attributed = NSAttributedString(string: s, attributes: [.font: font(size)])
        let bounding = attributed.boundingRect(with: CGSize(width: max(w - 24, 1), height: CGFloat.greatestFiniteMagnitude),
                                               options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        return ceil(bounding.height)
    }

    /// Android `paragraph`: a `StaticLayout` inset in `box` (6 points each side when centered, 12 when start-aligned),
    /// vertically centered, written in the language's direction.
    ///
    /// Bug report 2026-11-22 (3.2, 4.1, 4.2, 5.1, 5.3): a text taller than its box used to be centred on it, so its
    /// first line rose above the box (onto the dark top bar, where the dark ink vanished: "name to bring the target…"
    /// with the start of the sentence missing) and its last line fell under the next control. Now a text that does not
    /// fit first shrinks, down to 75% (never under 11 points); if it still does not fit it starts at the box's top and
    /// is clipped at the box, so the beginning of a sentence is always shown.
    private func paragraph(_ s: String, _ box: CGRect, _ size: CGFloat, _ color: UInt32 = 0xffffffff, center: Bool = true) {
        let rect = box.insetBy(dx: center ? 6 : 12, dy: 3)
        let w = max(rect.width, 1)
        let smallest = max(11, size * 0.75)
        var fitted = size
        var entry = paragraphLayout(s, w, fitted, color, center)
        while entry.1 > rect.height && fitted - 0.5 >= smallest {
            fitted -= 0.5
            entry = paragraphLayout(s, w, fitted, color, center)
        }
        let top = entry.1 > rect.height ? rect.minY : rect.minY + (rect.height - entry.1) / 2
        let context = UIGraphicsGetCurrentContext()
        context?.saveGState()
        context?.clip(to: box)
        entry.0.draw(with: CGRect(x: rect.minX, y: top, width: w, height: entry.1), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        context?.restoreGState()
    }

    /// The shaped paragraph and its height (cached like Android's `StaticLayout`s).
    private func paragraphLayout(_ s: String, _ w: CGFloat, _ size: CGFloat, _ color: UInt32, _ center: Bool) -> (NSAttributedString, CGFloat) {
        let key = "\(s)/\(Int(w))/\(Double(size))/\(color)/\(center)"
        if let cached = cachedLayouts[key] { return cached }
        if cachedLayouts.count > 90 { cachedLayouts.removeAll() }
        let style = NSMutableParagraphStyle()
        style.alignment = center ? .center : .natural
        style.baseWritingDirection = AppText.rtl ? .rightToLeft : .leftToRight
        style.lineBreakMode = .byWordWrapping
        let attributed = NSAttributedString(string: s, attributes: [.font: font(size), .foregroundColor: argbColor(color), .paragraphStyle: style])
        let bounding = attributed.boundingRect(with: CGSize(width: w, height: CGFloat.greatestFiniteMagnitude),
                                               options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        let entry = (attributed, ceil(bounding.height))
        cachedLayouts[key] = entry
        return entry
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
        if engine.phase == .air || engine.phase == .retrieve {
            let p = project(engine.phase == .air ? engine.landing : engine.ball.position)
            ctx.setStrokeColor(argbColor(0x66fff06a).cgColor)
            ctx.setLineWidth(3)
            ctx.strokeEllipse(in: CGRect(x: p.x - 23, y: p.y - 10, width: 46, height: 20))
        }
        let pixel = 1 / max(traitCollection.displayScale, 1)
        for splash in engine.paintSplashes {
            paintEffects.ground(ctx, splash, engine.time, pixel: pixel) { v, z in self.ballPoint(v, z) }
        }
        drawPractice(ctx)
        actorRects.removeAll()
        handPoints.removeAll()
        tags.removeAll()
        let loose = engine.ball.holder == nil && !engine.ball.burst
        if !engine.ball.burst { drawBallShadow(ctx) }
        if let practice = engine.practice {
            for shot in practice.shots where shot.ball.flightId != engine.ball.flightId && !shot.ball.burst {
                drawBallShadow(ctx, shot.ball)
            }
        }
        var ballDrawn = false
        // Eliminated players stay visible while they walk off; practice hides house players a lesson does not use.
        let shown = engine.actors.filter { a in
            if !EliminationExit.visible(a, engine.time) { return false }
            guard let d = engine.practice else { return true }
            return !a.member.bot || d.stage.cooperative || d.stage.defence || d.stage.skill == .tag || d.stage.skill == .freeze
        }
        let ordered = Kotlin.stableSorted(shown) { EliminationExit.position($0, engine.time).y < EliminationExit.position($1, engine.time).y }
        for a in ordered {
            if loose && !ballDrawn && engine.ball.position.y < EliminationExit.position(a, engine.time).y {
                drawFlyingBall(ctx)
                ballDrawn = true
            }
            drawActor(ctx, a, width, height)
        }
        if loose && !ballDrawn { drawFlyingBall(ctx) }
        // Kotlin draws every practice ball that is not the engine's ball object; flights have unique IDs.
        if let practice = engine.practice {
            for shot in practice.shots where shot.ball.flightId != engine.ball.flightId {
                drawFlyingBall(ctx, shot.ball)
            }
        }
        // During reception zoom, show a translucent locator at the actual ball position
        // if a nearer avatar hides it. This is presentation only: no catch radius or physics change.
        receptionBallLocatorVisible = false
        if loose && receptionZoom.amount > 0.1 && receptionZoom.incoming(engine, ownId, receptionZoomEnabled, followHumanZoomEnabled) != nil {
            let ball = engine.ball
            let point = ballPoint(ball.position, ball.height)
            let size = ballSize(ball.position, ball.height)
            let hidden = engine.actors.filter { EliminationExit.visible($0, engine.time) }.contains { actor in
                EliminationExit.position(actor, engine.time).y > ball.position.y && (actorRects[actor.member.id]?.contains(point) ?? false)
            }
            if hidden {
                receptionBallLocatorVisible = true
                let r = size * 0.62
                ctx.setStrokeColor(argbColor(0xffbafff4).cgColor)
                ctx.setLineWidth(2)
                ctx.strokeEllipse(in: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2))
                ballArt(CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size), alpha: 195.0 / 255.0)
            }
        }
        // Arena lighting of the ground is drawn by the world renderer; this tints the actors, not the HUD.
        drawLighting(ctx, width, height)
        drawAim(ctx, rect)
        drawTags(ctx, width, height)
        drawTarget(ctx)
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
                // The practice tree artwork, 6 m tall, standing on the target point, with drifting glow motes.
                let ground = project(t)
                let top = project(t, 6.0)
                let tall = ground.y - top.y
                let treeSize = art.practiceTree.size
                let treeWidth = treeSize.height > 0 ? tall * treeSize.width / treeSize.height : 0
                art.practiceTree.draw(in: CGRect(x: ground.x - treeWidth / 2, y: top.y, width: treeWidth, height: tall))
                ctx.setFillColor(argbColor(0xbaffec93).cgColor)
                for i in 0...7 {
                    let phase = engine.time * 0.8 + Double(i)
                    let glow = project(V(t.x + sin(phase) * 1.3, t.y), 2.5 + cos(phase * 0.7) * 1.1)
                    ctx.fillEllipse(in: CGRect(x: glow.x - 1.5, y: glow.y - 1.5, width: 3, height: 3))
                }
            }
        }
        if skill == .ring || skill == .ground {
            let isGround = skill == .ground
            let radius = (skill == .tree || skill == .rebound) ? 0.5 : d.radius
            let path = CGMutablePath()
            for i in 0...48 {
                let angle = Double(i) * 2 * Double.pi / 48
                let point = V(t.x + cos(angle) * radius, t.y + (isGround ? sin(angle) * radius : 0.0))
                let pt = project(point, isGround ? 0.24 : (d.targetHeight + sin(angle) * radius) * 2)
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
        if d.stage.cooperative || d.stage.skill == .tag {
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
    /// coach names the control mode and ball, then only the gesture (it fits even short landscape screens).
    func practiceInstruction(_ d: SpudPractice) -> String {
        let action: String
        if engine.time < engine.infoUntil && !Kotlin.isBlank(engine.infoEn) {
            action = tr(engine.infoEn, engine.infoHe)
        } else if d.stage.skill == .freeze {
            action = d.freezeReady ? tr("SPUD · stay still", "עמודו · עצרו במקום") : tr("RUN · drag to move", "רוצו · גררו לתנועה")
        } else if d.stage.skill == .call && engine.ball.holder == ownId {
            action = tr("Tap the starred partner, then swipe up from your ball", "געו בשותף המסומן ואז החליקו מעלה מהכדור")
        } else if d.stage.defence {
            switch d.stage.skill {
            case .duck: action = tr("Double-tap to duck", "נגיעה כפולה לכיפוף")
            case .jump: action = tr("Tap Jump at the right moment", "געו בקפיצה ברגע הנכון")
            case .move: action = tr("Drag to move aside", "גררו כדי לזוז הצדה")
            default: action = tr("Move, jump or duck", "זוזו, קפצו או התכופפו")
            }
        } else if d.stage.throwing && engine.ball.holder == ownId {
            action = tr(PracticeGuidance.live(d.stage, engine.config.throwMode, false), PracticeGuidance.live(d.stage, engine.config.throwMode, true))
        } else if d.stage.skill == .catching && d.stage.moving {
            action = tr("Drag to the marker, then tap Catch as the ball arrives.", "גררו לסימון וגעו בתפיסה כשהכדור מגיע.")
        } else if [DrillSkill.tree, .ring, .ground, .tag, .call].contains(d.stage.skill) {
            action = tr("Watch where your throw goes. Adjust your next throw.", "עקבו אחרי הכדור והתאימו את הזריקה הבאה.")
        } else {
            // Bug report 2026-11-22 (10.2): no promised duration (the window is `CatchPhysics.HUMAN_WINDOW`).
            action = tr(SpudIOSText.catchBrief, "געו בתפיסה כשהכדור מגיע, לפני שהוא נוגע בקרקע.")
        }
        return tr(engine.config.throwMode.en, engine.config.throwMode.he) + " · " + tr(engine.config.ball.en, engine.config.ball.he) + "\n" + action
    }

    /// The aim line, kept off every character (Android `clipOutRect` of each actor).
    private func drawAim(_ ctx: CGContext, _ area: CGRect) {
        guard engine.canAim(ownId), let mine = engine.actor(ownId), engine.practice == nil, engine.config.throwMode == .standard else { return }
        ctx.saveGState()
        for body in actorRects.values {
            ctx.addRect(area)
            ctx.addRect(body)
            ctx.clip(using: .evenOdd)
        }
        let origin = handPoints[ownId] ?? project(mine.position, 1.2)
        let end = ballPoint(mine.position + mine.direction * 4.5, 1.1)
        ctx.setStrokeColor(argbColor(0xffffe466).cgColor)
        ctx.setLineWidth(3)
        ctx.setLineCap(.round)
        ctx.setLineDash(phase: 0, lengths: [8, 6])
        ctx.move(to: origin)
        ctx.addLine(to: end)
        ctx.strokePath()
        ctx.setLineDash(phase: 0, lengths: [])
        ctx.restoreGState()
    }

    private func drawHud(_ ctx: CGContext, _ width: CGFloat, _ height: CGFloat) {
        let mine = engine.actor(ownId)
        let cfg = engine.config
        let rules = cfg.rules
        let top = CGRect(x: 12, y: 7, width: width - 24, height: (wide ? 53 : 62) - 7)
        panel(ctx, top)
        let rtl = AppText.rtl
        backRect = CGRect(x: rtl ? top.maxX - 52 : top.minX, y: top.minY, width: 52, height: top.height)
        rotateRect = CGRect(x: rtl ? backRect.minX - 50 : backRect.maxX + 2, y: top.minY, width: 48, height: top.height)
        // Bug report 2026-11-22 (3.4): the touch area stays the bar's height, but the drawn button is a compact face
        // inside it (room above and below), with the rotate symbol centred on it both ways.
        let rotateFace = rotateRect.insetBy(dx: 5, dy: wide ? 6 : 8)
        ctx.setFillColor(argbColor(0xe01b5668).cgColor)
        ctx.addPath(UIBezierPath(roundedRect: rotateFace, cornerRadius: 12).cgPath)
        ctx.fillPath()
        if let symbol = UIImage(systemName: "arrow.clockwise", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .bold))?
            .withTintColor(.white, renderingMode: .alwaysOriginal) {
            let s = symbol.size
            symbol.draw(in: CGRect(x: rotateFace.midX - s.width / 2, y: rotateFace.midY - s.height / 2, width: s.width, height: s.height))
        }
        let cx = backRect.midX
        let cy = backRect.midY
        let arrow: CGFloat = rtl ? -5 : 5
        for outline in [true, false] {
            let color: UInt32 = outline ? 0xfffff6df : 0xffff5b86
            let stroke: CGFloat = outline ? 6 : 3.5
            line(ctx, CGPoint(x: cx + arrow, y: cy - 9), CGPoint(x: cx - arrow, y: cy), color, stroke)
            line(ctx, CGPoint(x: cx - arrow, y: cy), CGPoint(x: cx + arrow, y: cy + 9), color, stroke)
        }
        let turnText: String
        if let practice = engine.practice {
            turnText = "\(practice.successes) / \(practice.goal)"
        } else if cfg.turns == 0 {
            turnText = tr("Turn \(engine.turn) · ∞", "תור \u{2066}\(engine.turn) · ∞\u{2069}")
        } else {
            turnText = tr("Turn \(engine.turn) / \(cfg.turns)", "תור \u{2066}\(engine.turn) / \(cfg.turns)\u{2069}")
        }
        let penaltyText: String
        if let practice = engine.practice {
            penaltyText = "♥ \(3 - practice.mistakes)"
        } else {
            penaltyText = mine.map { tr("Penalty: ", "חובה: ") + RuleText.score($0, rules) } ?? "—"
        }
        // Reserve the real translated score width instead of letting it collide with
        // the centered turn counter on compact Spanish/Dutch displays.
        let textLeft = rtl ? top.minX + 15 : rotateRect.maxX + 8
        let textRight = rtl ? rotateRect.minX - 8 : top.maxX - 15
        let available = max(textRight - textLeft - 10, 1)
        let needed = measure(turnText, 17) + measure(penaltyText, 17)
        let hudSize = 17 * min(1, available / max(needed, 1))
        let turnWidth = measure(turnText, hudSize)
        let penaltyWidth = measure(penaltyText, hudSize)
        let turnLeft = rtl ? textLeft + penaltyWidth + 10 : textLeft
        let turnRight = rtl ? textRight : textRight - penaltyWidth - 10
        let low = turnLeft + turnWidth / 2
        let high = max(turnRight - turnWidth / 2, low)
        let turnCenter = min(max(width / 2, low), high)
        text(turnText, turnCenter, top.midY + 6, hudSize)
        text(penaltyText, rtl ? textLeft : textRight, top.midY + 6, hudSize, 0xffffc6cb, right: !rtl, left: rtl)
        var instructionText = instruction()
        let seconds = engine.countdownSeconds()
        if seconds >= 0 && seconds <= 5 {
            instructionText += "\n" + (engine.actor(engine.actionActor).map { RuleText.name($0, ownId) } ?? "") + " · " + String(seconds)
        }
        if engine.phase == .aim && engine.thrower == ownId && cfg.stepsAfterCall > 0 {
            let steps = engine.stepRemaining / (min(cfg.width, cfg.depth) * cfg.stepLengthFraction)
            instructionText += "\n" + RuleText.format(RuleText["stepsLeft"], steps)
        }
        // Bug report 2026-11-22: landscape boxes are as tall as their text plus a little (5.2: "You are watching" had
        // 13 points above and below its one line); the portrait box may grow to the top of the field for a long text.
        let instructionBox: CGRect
        if wide {
            let bottom = min(height - 166, 64 + paragraphHeight(instructionText, sideWidth - 12, 16) + 12)
            instructionBox = CGRect(x: 12, y: 64, width: sideWidth - 12, height: max(bottom - 64, 1))
        } else {
            let need = paragraphHeight(instructionText, width - 28, 16) + 8
            let most = max(fieldTop() - 6 - 72, 1)
            instructionBox = CGRect(x: 14, y: 72, width: width - 28, height: min(max(height * 0.215 - 72, need), most))
        }
        panel(ctx, instructionBox, 0xf066b9ef)
        paragraph(instructionText, instructionBox, 16, 0xff102940, center: false)
        if engine.phase == .shout && engine.called == ownId {
            shoutRect = wide ? CGRect(x: 12, y: height - 122, width: sideWidth - 12, height: 52)
                : CGRect(x: width * 0.2, y: height * 0.86, width: width * 0.6, height: height * 0.08)
            panel(ctx, shoutRect, 0xffffe05e)
            text(RuleText.call(rules), shoutRect.midX, shoutRect.midY + 9, 26, 0xff173047)
        } else {
            shoutRect = .zero
            let status: String
            if !cfg.practiceLesson.isEmpty {
                status = LearningCopy.get("lesson_status")
            } else if engine.practice != nil {
                status = tr("Practice at your own pace · progress is saved", "מתאמנים בקצב שלכם · ההתקדמות נשמרת")
            } else if engine.time < engine.infoUntil {
                status = feedbackText()
            } else if mine?.active == false {
                // A player who is out cannot run or catch: no running hint (bug report 2026-11-22, 5.x).
                status = ""
            } else {
                status = tr("Drag to run · Time your catch\nJump low balls · Duck high balls", "גררו לריצה · תזמנו את התפיסה\nקפצו מעל כדור נמוך · התכופפו מתחת לגבוה")
            }
            let r: CGRect
            if wide {
                // Bug report 2026-11-22 (5.1, 5.3): the status ends above the box drawn at height - 122 (the "Out"
                // box, the call or "Choose player"), which used to cover its last lines.
                let lowerBoxShown = mine?.active == false || (engine.phase == .circle && engine.thrower == ownId)
                let limit = lowerBoxShown ? height - 130 : height - 66
                let statusTop = instructionBox.maxY + 8
                let statusBottom = min(limit, instructionBox.maxY + 20 + paragraphHeight(status, sideWidth - 12, 14))
                r = CGRect(x: 12, y: statusTop, width: sideWidth - 12, height: max(statusBottom - statusTop, 0))
            } else {
                // Bug report 2026-11-22 (3.2): the box ends 6 points above the view button and grows upwards to hold
                // its text (never above the action bar's top).
                let bottom = height - 50
                let need = paragraphHeight(status, width - 24, 14) + 8
                let topEdge = max(min(height * 0.865, bottom - need), height * 0.795)
                r = CGRect(x: 12, y: topEdge, width: width - 24, height: max(bottom - topEdge, 1))
            }
            // In landscape the thrower's "Choose player" button takes this place.
            if !status.isEmpty && r.height > 8 && !(wide && engine.phase == .circle && engine.thrower == ownId) {
                panel(ctx, r)
                paragraph(status, r, 14, center: false)
            }
        }
        returnRect = .zero
        if let mine, !mine.active {
            shoutRect = .zero
            // Bug report 2026-11-22 (5.4): the same 14-point, reading-edge text as the status above it; in landscape the
            // box is as tall as its text and ends above the view button.
            let outText = engine.time < engine.infoUntil ? feedbackText() : (rules == .spud ? RuleText["spudOut"] : RuleText["askReturn"])
            let outHeight = wide ? max(44, paragraphHeight(outText, sideWidth - 12, 14) + 14) : 0
            let box = wide ? CGRect(x: 12, y: height - 66 - outHeight, width: sideWidth - 12, height: outHeight)
                : CGRect(x: 12, y: height * 0.855, width: width - 24, height: height - 50 - height * 0.855)
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
            paragraph(engine.time < engine.infoUntil ? feedbackText() : label, box, 14, center: false)
            returnRect = canRequest ? box : .zero
        }
        // Bug report 2026-11-22 (3.3): 8 points under the bottom buttons in portrait (3 before).
        cameraRect = CGRect(x: 12, y: height - (wide ? 60 : 44), width: (wide ? sideWidth - 49 : width - 70) - 12, height: wide ? 48 : 36)
        if engine.practice == nil {
            panel(ctx, cameraRect, 0xe01b5668)
            paragraph(playerCamera ? tr("Your view · switch", "המבט שלכם · החלפה") : tr("Action view · switch", "מבט כללי · החלפה"), cameraRect, 13)
        }
        jumpRect = .zero
        catchRect = .zero
        duckRect = .zero
        let actionPhases: [Phase] = [.retrieve, .shout, .aim, .flight]
        if engine.practice == nil, let mine, mine.active, engine.ball.holder != ownId,
           actionPhases.contains(engine.phase) || (engine.phase == .air && engine.called == ownId) {
            let bar = wide ? CGRect(x: sideWidth + 12, y: height - 60, width: width - 12 - (sideWidth + 12), height: 48)
                : CGRect(x: 12, y: height * 0.795, width: width - 24, height: height * 0.855 - height * 0.795)
            let actionEnabled = (engine.phase == .air || actionPhases.contains(engine.phase)) && engine.ball.holder != ownId
            let groundPickup = engine.phase == .retrieve && engine.ball.height < 0.35 && abs(engine.ball.vz) < 0.7
            let eligible = engine.called == ownId
            let callCatch = engine.phase == .air
            let count = callCatch ? 1 : 3
            let cell = (bar.width - 6 * CGFloat(count - 1)) / CGFloat(count)
            var cells: [CGRect] = []
            for i in 0..<count {
                cells.append(CGRect(x: bar.minX + CGFloat(i) * (cell + 6), y: bar.minY, width: cell, height: bar.height))
            }
            catchRect = cells[0]
            if !callCatch {
                jumpRect = cells[1]
                duckRect = cells[2]
            }
            for r in cells { panel(ctx, r, actionEnabled ? 0xffffdf70 : 0xff93a0a8) }
            paragraph(groundPickup && eligible ? tr("Pick up", "איסוף") : tr("Catch", "תפיסה"), catchRect, 16, 0xff173047)
            if !callCatch {
                paragraph(tr("Jump ↑", "קפיצה ↑"), jumpRect, 16, 0xff173047)
                paragraph(tr("Duck", "כיפוף"), duckRect, 16, 0xff173047)
            }
            if !actionEnabled {
                jumpRect = .zero
                catchRect = .zero
                duckRect = .zero
            }
        }
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
        if engine.practice == nil && speechAvailable {
            chatRect = wide ? CGRect(x: sideWidth - 44, y: height - 60, width: 44, height: 48) : CGRect(x: width - 57, y: height - 44, width: 45, height: 36)
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
        if engine.actor(ownId)?.active == false && engine.phase != .returnVote {
            return engine.time < engine.infoUntil ? feedbackText() : RuleText["spectating"]
        }
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
                if engine.config.requireCall { return RuleText.format(RuleText["mustCall"], RuleText.call(engine.config.rules)) }
                return attackInstruction()
            }
            return tr("Keep running, or stop and prepare to catch.", "המשיכו לרוץ, או עצרו והתכוננו לתפוס.")
        case .aim:
            if engine.thrower == ownId { return attackInstruction() }
            return tr("SPUD! Stay still.\nTap to catch · Double-tap to duck", "עמודו! עמדו במקום.\nנגיעה לתפיסה · נגיעה כפולה להתכופפות")
        case .flight:
            return tr("Catch, jump or duck!", "תפסו, קפצו או התכופפו!")
        case .resolve:
            return feedbackText()
        case .huddle:
            if engine.huddleTarget == ownId {
                return tr("The other players are choosing a nickname for you.\nThe game will continue when they finish.",
                          "השחקנים האחרים בוחרים לכם כינוי.\nהמשחק ימשיך כשיסיימו.")
            }
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
        let displayPosition = EliminationExit.position(a, engine.time)
        let floor = project(displayPosition)
        let p = project(displayPosition, a.jumpHeight * 2)
        let head = project(displayPosition, a.jumpHeight * 2 + engine.config.standingHeight * 2)
        let visibleHeight = min(max(p.y - head.y, 14), height * 0.34)
        let visual = art.visual(a, engine)
        let f = visual.frame
        let anchor = art.anchor(a.member.character, visual)
        let rect = anchor.destination(p.x, p.y, visibleHeight, f.rect.width, f.rect.height, mirrored: visual.mirrored)
        let w = rect.width
        let h = rect.height
        ctx.setFillColor(argbColor(0x40091326).cgColor)
        ctx.fillEllipse(in: CGRect(x: floor.x - w * 0.3, y: floor.y - h * 0.05, width: w * 0.6, height: h * 0.095))
        let id = a.member.id
        if id == ownId || id == engine.selected || id == engine.called {
            ctx.setStrokeColor(argbColor(id == ownId ? 0xff00e5ff : 0xffffea00).cgColor)
            ctx.setLineWidth(2.5)
            ctx.strokeEllipse(in: CGRect(x: floor.x - w * 0.4, y: floor.y - h * 0.03, width: w * 0.8, height: h * 0.075))
        }
        let palm = CGPoint(x: rect.minX + w * (visual.mirrored ? 1 - f.handX : f.handX), y: rect.minY + h * f.handY)
        let b = ballSize(a.position, 1.2 + a.jumpHeight)
        // The hand supports the lower edge, rather than a sphere being pasted over
        // its centre. Back/side fingers and forearms naturally occlude the sphere.
        let minik = a.member.character == "minik"
        let offsetX: CGFloat
        switch visual.facing {
        case "front": offsetX = 0.18
        case "back": offsetX = minik ? 0.35 : -0.12
        default: offsetX = minik ? 0.40 : 0.25
        }
        let holding = engine.ball.holder == id
        let hand = holding ? CGPoint(x: palm.x + b * offsetX * (visual.mirrored ? -1 : 1),
                                     y: palm.y - b * (minik && visual.facing != "front" ? 0.20 : 0.34)) : palm
        handPoints[id] = hand
        let sx = visibleHeight / anchor.height
        let half = (anchor.right - anchor.left) * sx / 2
        actorRects[id] = CGRect(x: p.x - half, y: p.y - visibleHeight, width: half * 2, height: visibleHeight)
        /// The sprite, with its paint patches composited onto its own pixels (Android `saveLayer` + `SRC_ATOP`).
        func sprite() {
            let painted = !a.paintHits.isEmpty
            ctx.saveGState()
            if painted { ctx.beginTransparencyLayer(in: rect, auxiliaryInfo: nil) }
            ctx.saveGState()
            if visual.mirrored {
                ctx.translateBy(x: rect.midX, y: rect.midY)
                ctx.scaleBy(x: -1, y: 1)
                ctx.translateBy(x: -rect.midX, y: -rect.midY)
            }
            visual.image.draw(in: rect)
            paintEffects.body(ctx, rect, a, engine.config.rules, visual.image, f.face)
            ctx.restoreGState()
            if painted { ctx.endTransparencyLayer() }
            ctx.restoreGState()
        }
        func heldBall() {
            ballArt(CGRect(x: hand.x - b / 2, y: hand.y - b / 2, width: b, height: b))
        }
        if holding && visual.facing != "front" { heldBall() }
        sprite()
        if holding && visual.facing == "front" {
            heldBall()
            // Reuse actual foreground palm pixels, sized from the artwork (not from
            // the ball). Torso stays behind it; fingers support the lower rim.
            let paw = a.member.character == "minik" || a.member.character == "miniko"
            let rx = w * (paw ? 0.046 : 0.028)
            let ry = h * (paw ? 0.032 : 0.023)
            ctx.saveGState()
            ctx.addEllipse(in: CGRect(x: palm.x - rx, y: palm.y - ry, width: rx * 2, height: ry * 2))
            ctx.clip()
            sprite()
            ctx.restoreGState()
        }
        let label = id == ownId ? tr("You", "אתם") : a.fullName(hebrew: hebrew)
        // Kotlin `label.split(" ")`: at most four words, then "…".
        let words = label.components(separatedBy: " ")
        let shown = words.count > 4 ? words.prefix(4).joined(separator: " ") + "…" : label
        let score = a.penalties == 0 ? "" : " · " + RuleText.score(a, engine.config.rules)
        tags.append(Tag(actor: a, text: shown + score, base: p, width: w * 1.24))
        if engine.time < a.catchUntil {
            let fraction = Kotlin.clamp((a.catchUntil - engine.time) / CatchPhysics.window(a, engine.config), 0.0, 1.0)
            let sweep = CGFloat(2 * Double.pi * fraction)
            let arc = UIBezierPath(arcCenter: hand, radius: w * 0.25, startAngle: -CGFloat.pi / 2, endAngle: -CGFloat.pi / 2 + sweep, clockwise: true)
            ctx.setStrokeColor(argbColor(0xb2ffe96a).cgColor)
            ctx.setLineWidth(2)
            ctx.addPath(arc.cgPath)
            ctx.strokePath()
        }
    }

    /// Android `ballPoint`: the ball's drawing height is doubled to match the doubled sprite scale.
    private func ballPoint(_ v: V, _ z: Double) -> CGPoint {
        return project(v, z * 2.0)
    }

    /// Android `ballSize`: one physical-looking diameter for possession, flight and shadows. Never enlarge a held ball to
    /// make its touch target easier; input has its own hit tolerance.
    ///
    /// Bug report 2026-11-22 (3.1, 6.1): the beach ball and the paint balloon are drawn larger (`BallKind.drawScale`),
    /// in proportion to the players; catching and hitting still use `BallContact.radius`, so the game plays the same.
    private func ballSize(_ v: V, _ z: Double) -> CGFloat {
        let r = BallContact.radius(engine.config.ball)
        let a = project(V(v.x - r, v.y), z * 2)
        let b = project(V(v.x + r, v.y), z * 2)
        return abs(b.x - a.x) * CGFloat(engine.config.ball.drawScale)
    }

    /// Android `ballArt`: the paint balloon in the current paint colour, or the ball artwork.
    private func ballArt(_ r: CGRect, alpha: CGFloat = 1) {
        let image = engine.config.ball == .paint ? art.paintBalloon(engine.paintColor) : art.ball(engine.config.ball)
        image.draw(in: r, blendMode: .normal, alpha: alpha)
    }

    /// Android `drawTags`: stable slots (StableLabels) near the feet, kept off bodies and other tags inside the field;
    /// the local player's tag wears their colour rank.
    private func drawTags(_ ctx: CGContext, _ width: CGFloat, _ height: CGFloat) {
        var used: [LabelBox] = []
        tagRects.removeAll()
        let obstacles = Array(actorRects.values) + (practiceObstacle.map { [$0] } ?? [])
        let bodies = obstacles.map { LabelBox(x: Float($0.minX - 3), y: Float($0.minY - 3), w: Float($0.width + 6), h: Float($0.height + 6)) }
        let left = fieldLeft()
        // Bug report 2026-11-22 (4.3): in portrait a tag never goes under the Catch / Jump / Duck bar drawn over the field.
        let lowest = wide ? height - 70 : min(fieldBottom(), catchRect == .zero ? fieldBottom() : catchRect.minY - 4)
        let bounds = LabelBox(x: Float(left), y: Float(fieldTop()), w: Float(width - left - 5), h: Float(lowest - fieldTop()))
        let ordered = tags.sorted { l, r in
            let lo = l.actor.member.id == ownId ? 0 : 1
            let ro = r.actor.member.id == ownId ? 0 : 1
            if lo != ro { return lo < ro }
            return Kotlin.less(l.actor.member.id, r.actor.member.id)
        }
        let size: CGFloat = engine.actors.count >= 9 ? 10 : 11
        let rank = ProgressRanks.at(rankPoints)
        for tag in ordered {
            let w = min(max(measure(tag.text, size) + 16, 45), min(CGFloat(bounds.w), 220))
            let mine = tag.actor.member.id == ownId
            // The thrower's chosen caller target is highlighted in yellow.
            let selected = engine.phase == .circle && engine.thrower == ownId && tag.actor.member.id == engine.selected
            let ink: UInt32 = selected ? 0xff122e43 : (mine ? rank.ink : 0xffffffff)
            let shaped = tagLayout(tag.text, w - 12, size, ink)
            let tagH = max(22, shaped.1 + 6)
            // Bug report 2026-11-22 (4.3): a tag sits beside its own player (below, above, right or left), never over
            // another player; a player without a drawn body keeps the old search around the feet.
            let id = tag.actor.member.id
            let b: LabelBox
            if let own = actorRects[id] {
                let body = LabelBox(x: Float(own.minX), y: Float(own.minY), w: Float(own.width), h: Float(own.height))
                let others = obstacles.enumerated().filter { $0.element != own }.map { bodies[$0.offset] }
                b = stableLabels.placeNear(id, body: body, Float(w), Float(tagH), bounds, others, used)
            } else {
                b = stableLabels.place(id, Float(tag.base.x), Float(tag.base.y + 5), Float(w), Float(tagH), bounds, bodies, used, 24)
            }
            let rect = CGRect(x: CGFloat(b.x), y: CGFloat(b.y), width: CGFloat(b.w), height: CGFloat(b.h))
            used.append(b)
            if tag.actor.active { tagRects.append((tag.actor.member.id, rect)) }
            // A leader line only when the tag is away from its player (pinned at the edge, or pushed off by others).
            let besideOwner = actorRects[id].map { $0.insetBy(dx: -14, dy: -14).intersects(rect) } ?? false
            if !besideOwner && distance2D(CGFloat(b.cx) - tag.base.x, CGFloat(b.y) - tag.base.y) > 28 {
                line(ctx, tag.base, CGPoint(x: CGFloat(b.cx), y: CGFloat(b.cy)), 0x88122e43, 1)
            }
            panel(ctx, rect, selected ? 0xffffea00 : (mine ? rank.color : 0xf0153043))
            if selected {
                ctx.setStrokeColor(UIColor.white.cgColor)
                ctx.setLineWidth(2)
                ctx.addPath(UIBezierPath(roundedRect: rect, cornerRadius: 14).cgPath)
                ctx.strokePath()
            }
            let layoutWidth = max(w - 12, 1)
            shaped.0.draw(with: CGRect(x: CGFloat(b.cx) - layoutWidth / 2, y: CGFloat(b.cy) - shaped.1 / 2, width: layoutWidth, height: shaped.1),
                          options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine], context: nil)
        }
    }

    /// Android's tag `StaticLayout`: centered, at most two lines, ellipsized at the end (cached like `cachedLayouts`).
    private func tagLayout(_ s: String, _ width: CGFloat, _ size: CGFloat, _ ink: UInt32) -> (NSAttributedString, CGFloat) {
        let w = max(width, 1)
        let key = "tag/\(s)/\(Double(w))/\(Double(size))/\(ink)"
        if let cached = cachedLayouts[key] { return cached }
        if cachedLayouts.count > 90 { cachedLayouts.removeAll() }
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.baseWritingDirection = AppText.rtl ? .rightToLeft : .leftToRight
        style.lineBreakMode = .byWordWrapping
        let f = font(size)
        let attributed = NSAttributedString(string: s, attributes: [.font: f, .foregroundColor: argbColor(ink), .paragraphStyle: style])
        let bounding = attributed.boundingRect(with: CGSize(width: w, height: CGFloat.greatestFiniteMagnitude),
                                               options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        let entry = (attributed, min(ceil(bounding.height), ceil(f.lineHeight * 2)))
        cachedLayouts[key] = entry
        return entry
    }

    /// Android `drawBallShadow`: soft footprints projected on the ground plane — perspective, penumbra and light direction
    /// follow the same world coordinates as the ball, never its future landing marker.
    private func drawBallShadow(_ ctx: CGContext, _ ball: Ball? = nil) {
        let b = ball ?? engine.ball
        if b.burst { return }
        for s in BallShadow.project(b, engine.config, engine.time) {
            for layer in stride(from: 5, through: 0, by: -1) {
                let t = Double(layer) / 5.0
                let rx = s.radiusX + s.softness * t
                let ry = s.radiusY + s.softness * t
                for i in 0...24 {
                    let angle = Double(i) * 2 * Double.pi / 24
                    let x = cos(angle) * rx
                    let y = sin(angle) * ry
                    let p = project(s.center + V(x * cos(s.angle) - y * sin(s.angle), x * sin(s.angle) + y * cos(s.angle)))
                    if i == 0 { ctx.move(to: p) } else { ctx.addLine(to: p) }
                }
                ctx.closePath()
                let alpha = UInt32(min(max(Kotlin.toInt(255 * s.opacity / 6), 0), 255))
                ctx.setFillColor(argbColor((alpha << 24) | 0x000c111c).cgColor)
                ctx.fillPath()
            }
        }
    }

    private func drawFlyingBall(_ ctx: CGContext, _ ball: Ball? = nil) {
        let b = ball ?? engine.ball
        if b.burst { return }
        let p = ballPoint(b.position, b.height)
        let size = ballSize(b.position, b.height)
        // No altitude clamp: a powerful lob can leave the viewport and return naturally.
        if engine.ballWithinReach(ownId) {
            let r = size * 0.72
            fillRadial(ctx, p, r * 1.45, [0xb200e5ff, 0x00000000], [0, 1])
            ctx.setStrokeColor(argbColor(0xffbafff4).cgColor)
            ctx.setLineWidth(2.5)
            ctx.strokeEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        }
        // Bug report 2026-11-22 (6.2): a paint balloon lying on the ground lies on its side, a little squashed,
        // instead of standing upright on its knot.
        if engine.config.ball == .paint && b.holder == nil && b.height <= 0.24 && abs(b.vz) < 0.7 {
            let ground = ballPoint(b.position, 0)
            ctx.saveGState()
            ctx.translateBy(x: p.x, y: max(p.y, ground.y - size * 0.3))
            ctx.rotate(by: (b.position.x < engine.config.width / 2 ? 1 : -1) * .pi / 2)
            ctx.scaleBy(x: 0.82, y: 1)
            ballArt(CGRect(x: -size / 2, y: -size / 2, width: size, height: size))
            ctx.restoreGState()
            return
        }
        ballArt(CGRect(x: p.x - size / 2, y: p.y - size / 2, width: size, height: size))
    }

    /// Android `outcomeExplanation()`: the explanation the result/score pages repeat.
    func outcomeExplanation() -> String { return feedbackText() }

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
        if catchRect.contains(point) {
            command(.catchBall)
            return
        }
        if duckRect.contains(point) {
            command(.duck)
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
        } else if engine.canAim(ownId) && engine.config.throwMode == .standard && onBall {
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
                if engine.config.throwMode == .standard {
                    aimedAt = nil
                    command(.aim(inverseVector(dx, dy)))
                }
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
                // Physical points and gesture time (Android dp and milliseconds).
                let power = TossGesture.power(Double(-dy), numericCast(now - startAt))
                let drift = Double(dx / max(abs(dy), 30))
                command(.toss(power: power, drift: Kotlin.clamp(drift, -1, 1)))
            }
            if gesture == "throw" {
                let speed = Double(distance2D(dx, dy)) / Double(max(Int64(45), now - startAt)) * 1000
                command(.throwBall(power: Kotlin.clamp((speed - 100) / 1700, 0, 1)))
            }
            command(.move(V.zero))
            return
        }
        if engine.canAim(ownId) && engine.config.throwMode != .standard {
            singleTap(x, y)
            return
        }
        if secondTap {
            secondTap = false
            command(.duck)
            return
        }
        if catchCommitted { return }
        // Catch-only lessons have no double-tap duck to disambiguate. Respond to
        // the tap now; movement drags already returned above.
        if engine.ball.holder != ownId {
            singleTap(x, y)
            tapAt = now
            tapX = x
            tapY = y
            // Remember a possible second tap without delaying the first catch.
            let forget: @MainActor () -> Void = { [weak self] in
                guard let self else { return }
                self.pendingTap = nil
                self.pendingTapAction = nil
            }
            pendingTapAction = forget
            pendingTap = afterDelay(Double(engine.config.doubleTapMs) / 1000.0) { forget() }
            return
        }
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
        if engine.canAim(ownId) && engine.config.throwMode != .standard {
            tapThrow(x, y, target)
            return
        }
        if let d = engine.practice, engine.canAim(ownId) {
            guard let me = engine.actor(ownId) else { return }
            let marked = ballPoint(d.target, d.stage.skill == .ground ? 0.0 : d.targetHeight)
            if distance2D(x - marked.x, y - marked.y) < 80 || target != nil {
                let aimAt = target.flatMap { engine.actor($0)?.position } ?? d.target
                command(.aim(aimAt - me.position))
                return
            }
            // Android inverts the projected 16 m square at the target's (ball-scaled) height (Matrix.setPolyToPoly); the
            // camera's own inverse at that height is the same mapping.
            let at = arenaCamera.ground(Double(x), Double(y), max(Double(bounds.width), 1), max(Double(bounds.height), 1), d.targetHeight * 2)
            command(.aim(V(at.x, at.y) - me.position))
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

    // MARK: Tap and timed-target throws (Android `aimCentre`, `drawTarget`, `pointAt`, `tapThrow`)

    private func aimCentre() -> V? {
        if let p = engine.practice, p.stage.throwing && p.stage.skill != .call { return p.target }
        guard let id = aimedAt, let a = engine.actor(id), a.active else { return nil }
        return a.position
    }

    private func aimSide(_ target: V) -> V {
        let from = engine.actor(ownId)?.position ?? target
        let d = (target - from).unit()
        return V(-d.y, d.x)
    }

    /// The Standard control's moving dot over the chosen player (or practice target), in the player's rank colour.
    private func drawTarget(_ ctx: CGContext) {
        displayedAim = nil
        if !engine.canAim(ownId) || engine.config.throwMode != .target || networkWaiting { return }
        guard let centre = aimCentre(), let me = engine.actor(ownId) else { return }
        let dot = TargetThrow.dot(engine.time, (centre - me.position).length())
        let base = engine.practice?.targetHeight ?? 1.03
        let aim = TargetThrow.Aim(position: centre + aimSide(centre) * dot.0, height: dot.1 + base - 1.03)
        displayedAim = aim
        let p = ballPoint(aim.position, aim.height)
        let color = ProgressRanks.at(me.member.points ?? rankPoints).color
        for (radius, fill) in [(CGFloat(9), UInt32(0xff17283f)), (7.5, 0xffffffff), (5.5, color)] {
            ctx.setFillColor(argbColor(fill).cgColor)
            ctx.fillEllipse(in: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2))
        }
    }

    /// Invert the projected vertical target plane, preserving foot/face and side taps.
    private func pointAt(_ x: CGFloat, _ y: CGFloat, _ centre: V) -> TargetThrow.Aim? {
        let side = aimSide(centre)
        let source: [Double] = [-2, -0.6, 2, -0.6, 2, 3.4, -2, 3.4]
        let camera = gestureCamera ?? arenaCamera
        let w = Double(bounds.width)
        let h = Double(bounds.height)
        var screen: [Double] = []
        for i in 0...3 {
            let v = centre + side * source[2 * i]
            let p = camera.project(v.x, v.y, source[2 * i + 1] * 2.0, w, h)
            screen.append(p.x)
            screen.append(p.y)
        }
        guard let mapped = ArenaView.mapThroughQuad(screen, source, Double(x), Double(y)) else { return nil }
        let aim = TargetThrow.Aim(position: centre + side * mapped.0, height: mapped.1)
        return TargetThrow.valid(aim.position, aim.height, engine.config) ? aim : nil
    }

    /// Android `Matrix.setPolyToPoly(src, 0, dst, 0, 4)` + `mapPoints`: the perspective transform taking the four `from`
    /// points (x0, y0, …, x3, y3) to the four `to` points, applied to (x, y).
    static func mapThroughQuad(_ from: [Double], _ to: [Double], _ x: Double, _ y: Double) -> (Double, Double)? {
        // Unknowns h0…h7 of u = (h0 x + h1 y + h2) / (h6 x + h7 y + 1), v = (h3 x + h4 y + h5) / (h6 x + h7 y + 1).
        var m = [[Double]](repeating: [Double](repeating: 0, count: 9), count: 8)
        for i in 0...3 {
            let sx = from[2 * i]
            let sy = from[2 * i + 1]
            let u = to[2 * i]
            let v = to[2 * i + 1]
            m[2 * i] = [sx, sy, 1, 0, 0, 0, -sx * u, -sy * u, u]
            m[2 * i + 1] = [0, 0, 0, sx, sy, 1, -sx * v, -sy * v, v]
        }
        for col in 0..<8 {
            var pivot = col
            for row in col..<8 where abs(m[row][col]) > abs(m[pivot][col]) { pivot = row }
            if abs(m[pivot][col]) < 1e-12 { return nil }
            m.swapAt(col, pivot)
            for row in 0..<8 where row != col {
                let factor = m[row][col] / m[col][col]
                if factor == 0 { continue }
                for k in col..<9 { m[row][k] -= factor * m[col][k] }
            }
        }
        let hm = (0..<8).map { m[$0][8] / m[$0][$0] }
        let d = hm[6] * x + hm[7] * y + 1
        if abs(d) < 1e-12 { return nil }
        return ((hm[0] * x + hm[1] * y + hm[2]) / d, (hm[3] * x + hm[4] * y + hm[5]) / d)
    }

    /// Android `tapThrow`: Easy throws at the exact tapped point; Standard first picks a target, then throws at the
    /// moving dot when tapped.
    private func tapThrow(_ x: CGFloat, _ y: CGFloat, _ target: String?) {
        var other: String?
        if let t = target, t != ownId, engine.actor(t)?.active == true { other = t }
        let point = CGPoint(x: x, y: y)
        let label = other.flatMap { id in tagRects.first(where: { $0.0 == id })?.1.contains(point) } ?? false
        if engine.config.throwMode == .target {
            if let o = other, aimedAt == nil || (label && o != aimedAt), engine.practice == nil {
                aimedAt = o
                playerCamera = false
                displayedAim = nil
                return
            }
            if let aim = displayedAim {
                command(.pointThrow(point: aim.position, height: aim.height))
                displayedAim = nil
            }
            return
        }
        if label {
            aimedAt = other
            playerCamera = false
            return
        }
        var centre: V?
        if let p = engine.practice {
            centre = p.target
        } else if let o = other, let a = engine.actor(o) {
            centre = a.position
        } else if let c = aimCentre() {
            centre = c
        } else {
            var best: GameActor?
            var bestDistance = CGFloat.greatestFiniteMagnitude
            for a in engine.activeActors where a.member.id != ownId {
                let p = ballPoint(a.position, 1.0)
                let d = distance2D(x - p.x, y - p.y)
                if best == nil || d < bestDistance {
                    best = a
                    bestDistance = d
                }
            }
            centre = best?.position
        }
        guard let c = centre, let aim = pointAt(x, y, c) else { return }
        command(.pointThrow(point: aim.position, height: aim.height))
    }

    private func attackInstruction() -> String {
        switch engine.config.throwMode {
        case .easy:
            return tr("Tap the exact spot to throw. Tap a name to bring the target into view.", "געו במקום המדויק כדי לזרוק. געו בשם כדי לראות את המטרה.")
        case .target:
            if aimCentre() == nil {
                return tr("Choose a player or name to show the moving target.", "בחרו שחקן או שם כדי להציג את הנקודה הנעה.")
            }
            return tr("Tap when the dot is where you want to hit. Farther means faster.", "געו כשהנקודה במקום שבו רוצים לפגוע. רחוק יותר פירושו מהר יותר.")
        case .standard:
            return tr("Aim by tapping a player or their name label.\nFlick from your ball to throw.", "כוונו בנגיעה בשחקן או בתווית השם שלו.\nהחליקו מהכדור כדי לזרוק.")
        }
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
