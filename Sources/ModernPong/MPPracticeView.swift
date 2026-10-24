import SwiftUI
import UIKit

// MPArtFiles, MPPoseAtlas and the shared table layout/art live in MPPracticeTable.swift.

/// Android `PongPracticeView` (29f5dc7): the daily-journey and team table. The far players stand behind the table, the
/// near players in front of it, drawn larger. The ball's flight is never warped toward a paddle: the whole-body pose
/// that reaches the real contact is chosen instead (`reachPose`), and in team play that rendered racket decides the
/// contact (`MPPlay.contactReach`). Online friends only draw the authority's snapshots (`simulate = false`) and send
/// moves, taps and strokes.
final class MPPracticeCourtView: UIView {
    /// Online friends receive a new restored table with every snapshot; its event serial continues the authority's,
    /// so a changed serial still plays the hit sounds (Android `heardEvent`).
    var game: MPPlay { didSet { if game !== oldValue { attachSound(); oldValue.contactReach = nil } } }
    var hebrew = false
    var names: [Int: String] = [:]
    var localSeat = 0
    var simulate = true
    var soundsEnabled: () -> Bool = { true }
    var onMove: ((MPPoint) -> Void)?
    var onTap: ((MPPoint) -> Void)?
    /// Android `onStroke`: online friends send Standard/Pro strokes to the host instead of playing them locally.
    var onStroke: ((MPPongStroke) -> Void)?
    /// Android `controlOverride`: the online player's chosen control (the friend's snapshot may lag behind it).
    var controlOverride: Int?
    var onFrame: (() -> Void)?
    /// Android `PongCourtStyle.landscape` (`clipChildren = false`): in landscape the view spans the side gutters too, so
    /// players who yield outward stay visible there; the table itself is laid out between them.
    var gutter: CGFloat = 0 { didSet { if gutter != oldValue { setNeedsLayout(); setNeedsDisplay() } } }
    /// Android `ReceptionCamera.scenery` / `ArenaBackdrop.foreground`: the arena scenery behind the table, if any.
    var scenery: MPArenaScenery?
    private var control: Int { controlOverride ?? (game.controls.indices.contains(localSeat) ? game.controls[localSeat] : 0) }
    private let atlas = MPPoseAtlas()
    private let tableArt = MPPracticeTableArt()
    private(set) var layout = MPPracticeTableLayout.fit(1, 1)
    private let audio = MPAudio()
    private var camera = MPReceptionCamera()
    private var link: CADisplayLink?
    private var stamp: CFTimeInterval = 0, drawn = false, heardEvent = 0
    private var lastAt: [Int: MPPoint] = [:], walked: [Int: Double] = [:], stepAt: [Int: CFTimeInterval] = [:]
    private var bodyBoxes: [Int: CGRect] = [:], racketPoints: [Int: CGPoint] = [:], racketRadii: [Int: CGFloat] = [:]
    private struct ReachPose { let phase: Int; let mirrored: Bool; let lean: CGFloat; let gap: CGFloat }
    private var impactPoses: [Int: (Double, ReachPose)] = [:]
    private var labelRequests: [(Int, CGPoint, Bool)] = []
    private var labels: [Int: CGRect] = [:]
    private var actorHeight: CGFloat = 1, floorDrop: CGFloat = 1, lift: CGFloat = 1, left: CGFloat = 0, top: CGFloat = 0, tw: CGFloat = 1, depth: CGFloat = 1
    private var down = CGPoint.zero, downAt: CFTimeInterval = 0, dragging = false
    private var dragStart = MPPoint(0.5, 0.88), dragOrigin = MPPoint(0.5, 0.88)
    private var strokePath: [CGPoint] = [], tapSent = false, playerDrag = false
    /// Android `VelocityTracker`: recent finger samples (time, point) for the swipe velocity in points per second.
    private var samples: [(CFTimeInterval, CGPoint)] = []
    private var laidOut: (CGSize, Bool) = (.zero, false)
    /// The court View of Android: the view without its gutters.
    private var courtSize: CGSize { CGSize(width: max(bounds.width - gutter * 2, 1), height: bounds.height) }
    /// The court origin in the scenery's points, while both are on screen.
    private var sceneryOffset: CGPoint? {
        guard let view = scenery?.view, let window, view.window === window else { return nil }
        return convert(CGPoint(x: gutter, y: 0), to: view)
    }
    private let ink = UIColor(red: 0x17 / 255, green: 0x3e / 255, blue: 0x56 / 255, alpha: 1)

    init(game: MPPlay) {
        self.game = game
        super.init(frame: .zero)
        heardEvent = game.eventSerial
        isOpaque = false; backgroundColor = .clear; contentMode = .redraw; isMultipleTouchEnabled = false
        isAccessibilityElement = true
        attachSound()
    }
    required init?(coder: NSCoder) { return nil }
    private func attachSound() {
        game.onSound = { [weak self] names in
            guard let self, self.link != nil, self.soundsEnabled() else { return }
            names.forEach { self.audio.play($0) }
        }
    }
    func setRunning(_ on: Bool) {
        if on {
            guard link == nil else { return }
            stamp = 0
            let display = CADisplayLink(target: self, selector: #selector(step(_:)))
            display.add(to: .main, forMode: .common); link = display
        } else {
            link?.invalidate(); link = nil; audio.stop()
        }
    }
    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil { setRunning(false); game.contactReach = nil }
    }
    @objc private func step(_ display: CADisplayLink) {
        let now = display.timestamp
        let cameraElapsed = stamp == 0 ? 0 : min(max(now - stamp, 0), 0.1)
        let dt = stamp == 0 || !drawn ? 0 : min(now - stamp, 1.0 / 30)
        stamp = now
        // Android: in team play the drawn racket decides the contact. Without the pose art (Math Plus, Minik Plus)
        // the table keeps its geometric reach.
        game.contactReach = game.team && MPPoseAtlas.available ? { [weak self] i, at, z in self?.visibleReach(i, at, z) ?? false } : nil
        if !simulate && heardEvent != game.eventSerial {
            heardEvent = game.eventSerial
            if soundsEnabled() {
                switch game.lastEvent {
                case "serve", "contact": audio.play("minik_kick2"); audio.play("minik_kick")
                case "win": audio.play("minik_claps")
                default: break
                }
            }
        }
        if drawn && simulate {
            game.reception.enabled = true; game.reception.slow[localSeat] = MPReceptionSettings.slow; game.start()
            var rest = dt
            while rest > 0 { let n = min(rest, 1.0 / 120); game.advance(n); rest -= n }
        }
        let receiver = game.actors.indices.contains(game.reception.receiver) ? game.reception.receiver : localSeat
        if game.actors.indices.contains(receiver) {
            let a = project(game.actors[receiver].at)
            let b = game.flight.map { project($0.position, $0.height) } ?? a
            camera.update(cameraElapsed, assist: game.reception, local: localSeat, focus: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2), size: courtSize, holding: downAt != 0, reduceMotion: UIAccessibility.isReduceMotionEnabled)
        }
        if let offset = sceneryOffset { scenery?.view?.follow(camera, offset: offset) }
        onFrame?()
        setNeedsDisplay()
    }
    override func layoutSubviews() { super.layoutSubviews(); relayout() }
    /// Android `onSizeChanged`: the shared table layout; alternating teams reserve the retreat floor, including the
    /// near player's feet and label.
    private func relayout() {
        let flags = game.team && game.alternate
        let size = courtSize
        if laidOut.0 == size && laidOut.1 == flags { return }
        laidOut = (size, flags)
        let g = MPPracticeTableLayout.fit(Double(size.width), Double(size.height)); layout = g
        tw = CGFloat(g.width); left = CGFloat(g.left); actorHeight = CGFloat(g.actorHeight); floorDrop = CGFloat(g.floorDrop)
        depth = CGFloat(g.depth); lift = CGFloat(g.lift); top = CGFloat(g.top)
        if flags {
            let maxDepth = (bounds.height - top - floorDrop - actorHeight * 0.06 - 20) / (1 + CGFloat(MPTeamMovement.retreat) * 0.45)
            depth = min(depth, maxDepth); lift = min(depth * 0.62, tw * 0.62)
        }
    }
    private var nearTeam: Int { game.actors.indices.contains(localSeat) ? game.actors[localSeat].team : 0 }
    private func screen(_ v: MPPoint) -> MPPoint { nearTeam == 0 ? v : MPPoint(1 - v.x, 1 - v.y) }
    func project(_ world: MPPoint, _ z: Double = 0) -> CGPoint {
        let v = screen(world)
        return CGPoint(x: left + tw * (0.5 + (CGFloat(v.x) - 0.5) * (0.72 + 0.28 * CGFloat(v.y))), y: top + depth * CGFloat(v.y) - CGFloat(z) * lift)
    }
    private func facing(_ index: Int) -> MPPoseAtlas.Facing { game.actors[index].team == nearTeam ? .rear : .front }
    /// Near players are drawn 22 % larger (Android 305914e).
    private func playerHeight(_ index: Int) -> CGFloat { actorHeight * (game.actors[index].team == nearTeam ? 1.22 : 1) }
    /// Feet belong to the floor outside the end line, never to a ball contact. A retreat behind the baseline is drawn
    /// at 45 % (the full step for a house player beside the sideline). Lane coordinates locate the ready paddle, not
    /// the centre of a wide torso.
    private func floorFoot(_ index: Int) -> CGPoint {
        let a = game.actors[index]
        let clearance = Double(actorHeight * 0.06 / depth)
        let y = a.team == 0 ? (nearTeam == 0 ? 1 + clearance : 1.0) : (nearTeam == 1 ? -clearance : 0.0)
        let baseline = a.team == 0 ? 0.88 : 0.12
        let side = !a.human && (a.at.x < 0.02 || a.at.x > 0.98)
        let at = project(MPPoint(a.at.x, y + (a.at.y - baseline) * (side ? 1.0 : 0.45)))
        var foot = CGPoint(x: at.x, y: at.y + floorDrop)
        if let anchor = atlas.geometry(a.character, facing(index), foot: .zero, height: playerHeight(index), phase: a.team == nearTeam ? 2 : 0) { foot.x -= anchor.racket.x }
        return foot
    }
    private var ballRadius: CGFloat { max(5, tw * 0.012) }
    /// Android `visibleLoft`: the common elevated-ball scale (`TableBallProjection.rise`).
    private func visibleLoft(_ z: Double) -> Double { MPTableBallProjection.rise(z) * Double(depth / lift) }
    /// One projection for table, net, live ball and rebound. Never warp a bounce toward a paddle.
    private func renderedBallPoint(_ position: MPPoint, _ z: Double) -> CGPoint {
        let raised = z < 0 ? z * Double(floorDrop) / (1.25 * Double(lift)) : visibleLoft(z)
        var p = project(position, raised); p.y -= ballRadius
        return p
    }
    /// Android `reachPose`: the authored pose, mirror and small lean (±15°, about the planted feet) whose racket
    /// touches the drawn ball; otherwise the closest one.
    private func reachPose(_ index: Int, _ position: MPPoint, _ z: Double) -> ReachPose {
        let ball = renderedBallPoint(position, z), foot = floorFoot(index), actor = game.actors[index]
        var best = ReachPose(phase: 2, mirrored: false, lean: 0, gap: .greatestFiniteMagnitude)
        let degrees = [0] + (1...15).flatMap { [$0, -$0] }
        for phase in [2, 0, 1, 3] {
            for mirror in [false, true] {
                guard let g = atlas.geometry(actor.character, facing(index), mirror: mirror, foot: foot, height: playerHeight(index), phase: phase) else { return best }
                for d in degrees {
                    let a = Double(d) * .pi / 180, x = Double(g.racket.x - foot.x), y = Double(g.racket.y - foot.y)
                    let gap = CGFloat(hypot(Double(ball.x - foot.x) - x * cos(a) + y * sin(a), Double(ball.y - foot.y) - x * sin(a) - y * cos(a)) - Double(g.radius) - Double(ballRadius))
                    if gap <= 0 { return ReachPose(phase: phase, mirrored: mirror, lean: CGFloat(d), gap: gap) }
                    if gap < best.gap { best = ReachPose(phase: phase, mirrored: mirror, lean: CGFloat(d), gap: gap) }
                }
            }
        }
        return best
    }
    /// Android `visibleReach`: the drawn racket reaches the drawn ball (within a point).
    func visibleReach(_ index: Int, _ position: MPPoint, _ z: Double) -> Bool {
        guard game.actors.indices.contains(index) else { return false }
        relayout()
        return reachPose(index, position, z).gap <= 1
    }
    private func ground(_ p: CGPoint) -> MPPoint {
        let yy = Double((p.y - top) / max(depth, 1))
        let x = 0.5 + Double(p.x - left - tw * 0.5) / Double(tw * (0.72 + 0.28 * CGFloat(yy)))
        return screen(MPPoint(x.mpClamp(0, 1), yy))
    }
    private func color(_ argb: UInt32) -> UIColor { MPColor.ui(argb) }
    private func path(_ points: [MPPoint]) -> CGPath {
        let p = CGMutablePath()
        for (i, v) in points.enumerated() { let q = project(v); if i == 0 { p.move(to: q) } else { p.addLine(to: q) } }
        p.closeSubpath(); return p
    }
    private func text(_ value: String, at: CGPoint, size: CGFloat, color: UIColor, rounded: Bool = true) {
        let font = UIFont.systemFont(ofSize: size, weight: .bold)
        let face = rounded ? (font.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? font) : font
        let attributed = NSAttributedString(string: value, attributes: [.font: face, .foregroundColor: color])
        let measured = attributed.size()
        attributed.draw(at: CGPoint(x: at.x - measured.width / 2, y: at.y - measured.height / 2))
    }
    private func drawActor(_ c: CGContext, _ index: Int) {
        let a = game.actors[index], rear = a.team == nearTeam, foot = floorFoot(index), face = facing(index)
        let age = game.clock - game.lastContact
        let incoming = game.preparingReturn(index)
        let walking = !(game.hitter == index && age < 0.34) && !incoming && CACurrentMediaTime() - (stepAt[index] ?? 0) < 0.13
        let art = walking ? a.character + "-walk" : a.character
        let contact = game.hitter == index && age < 0.34
        var impact: ReachPose?
        if contact {
            if let cached = impactPoses[index], cached.0 == game.lastContact { impact = cached.1 }
            else { let pose = reachPose(index, game.contactAt, game.contactHeight); impactPoses[index] = (game.lastContact, pose); impact = pose }
        }
        let phase: Int
        if contact && age < 0.10 { phase = impact?.phase ?? 0 }
        else if game.hitter == index && age < 0.34 { phase = 3 }
        else if incoming { phase = a.character == "minik" && rear ? 0 : 1 }
        else if walking { phase = Int((walked[index] ?? 0) / 0.10) % 4 }
        else { phase = 0 }
        // A small whole-body reach pivots at the planted feet. Keep the actual ball trajectory and the intact pose.
        let lean: CGFloat = game.hitter == index && age < 0.34 ? (impact?.lean ?? 0) * CGFloat(1 - ((age - 0.10) / 0.24).mpClamp(0, 1)) : 0
        let mirror = impact?.mirrored ?? false, height = playerHeight(index)
        c.saveGState()
        c.translateBy(x: foot.x, y: foot.y); c.rotate(by: lean * .pi / 180); c.translateBy(x: -foot.x, y: -foot.y)
        let drawnBody = atlas.draw(art, face, mirror: mirror, foot: foot, height: height, phase: phase) ?? atlas.draw(a.character, face, mirror: mirror, foot: foot, height: height, phase: phase)
        c.restoreGState()
        let active = game.team && game.alternate && game.nextHitter[a.team] == index
        guard let drawn = drawnBody else {
            // Without the pose art (a build that does not bundle it) a simple marker keeps the place visible.
            c.setFillColor(color(a.team == 0 ? 0xff4bf4c7 : 0xffff74b6).cgColor)
            c.fillEllipse(in: CGRect(x: foot.x - actorHeight * 0.12, y: foot.y - actorHeight * 0.5, width: actorHeight * 0.24, height: actorHeight * 0.5))
            labelRequests.append((index, CGPoint(x: foot.x, y: rear ? foot.y + 14 : foot.y - actorHeight * 0.55 - 15), active))
            return
        }
        let transform = CGAffineTransform(translationX: foot.x, y: foot.y).rotated(by: lean * .pi / 180).translatedBy(x: -foot.x, y: -foot.y)
        let bounds = drawn.bounds.applying(transform), racket = drawn.racket.applying(transform)
        bodyBoxes[index] = bounds; racketPoints[index] = racket; racketRadii[index] = drawn.radius
        labelRequests.append((index, CGPoint(x: bounds.midX, y: rear ? foot.y + 14 : bounds.minY - 15), active))
    }
    private func drawLabel(_ c: CGContext, _ index: Int, _ at: CGPoint, _ active: Bool) {
        let name = names[index] ?? (index == localSeat ? (hebrew ? "אתם" : "You") : (MPRoster.find(game.actors[index].character) ?? MPRoster.all[0]).name(hebrew: hebrew))
        let size = min(13, bounds.height * 0.035)
        let font = UIFont.systemFont(ofSize: size, weight: .bold)
        let half = (name as NSString).size(withAttributes: [.font: font]).width / 2 + 12
        // When reception zoom moves a player out of frame, their label leaves too. Clamping it onto the tabletop makes an
        // off-screen player look submerged. In landscape players may yield into the side gutters: their labels stay
        // with those bodies rather than clipping at the court (Android then drops any that leave it, in `fits`).
        let width = courtSize.width, visibleLeft = -gutter, visibleRight = width + gutter
        if at.y < -size * 0.8 || at.y > bounds.height + size * 0.8 || at.x < visibleLeft - half || at.x > visibleRight + half { return }
        var cx = min(max(at.x, visibleLeft + half + 2), visibleRight - half - 2), cy = min(max(at.y, size * 0.8 + 2), bounds.height - size * 0.8 - 2)
        // A shallow landscape window can clamp an above-head label onto the head: place it beside that player.
        if game.actors[index].team != nearTeam, let body = bodyBoxes[index] {
            let head = camera.painted(CGPoint(x: body.midX, y: body.minY))
            if cy + size * 0.8 > head.y - 3 {
                let outward: CGFloat = head.x < width * 0.5 ? -1 : 1
                let edge = camera.painted(CGPoint(x: outward < 0 ? body.minX : body.maxX, y: body.minY + size))
                cx = min(max(edge.x + outward * (half + 6), half + 2), width - half - 2)
                cy = min(max(edge.y, size * 0.8 + 2), bounds.height - size * 0.8 - 2)
            }
        }
        let box = CGRect(x: cx - half, y: cy - size * 0.8, width: half * 2, height: size * 1.6)
        // Android PongNameSpace: names never cover a body or another name.
        let obstacles = bodyBoxes.values.map { r -> CGRect in
            let a = camera.painted(CGPoint(x: r.minX, y: r.minY)), b = camera.painted(CGPoint(x: r.maxX, y: r.maxY))
            return CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)
        } + Array(labels.values)
        if !MPNameSpace.fits(box, width: width, height: bounds.height, obstacles: obstacles) { return }
        labels[index] = box
        let fill: UInt32 = game.team ? MPTeamColors.fill(game.actors[index].team, seed: game.seed) : active ? 0xffffd665 : 0xf4ffffff
        c.setFillColor(color(fill).cgColor)
        c.addPath(UIBezierPath(roundedRect: box, cornerRadius: 12).cgPath); c.fillPath()
        text(name, at: CGPoint(x: cx, y: cy), size: size, color: ink)
    }
    private var farEnding: Bool { game.flight == nil && (game.ending.map { screen($0.position).y < 0 } ?? false) }
    private func drawBall(_ c: CGContext) {
        let ball: (MPPoint, Double)?
        if let f = game.flight { ball = (f.position, f.height) } else if let e = game.ending { ball = (e.position, e.height) } else { ball = nil }
        guard let (position, z) = ball else { return }
        let raw = renderedBallPoint(position, z)
        var shadow = project(position); if !position.inside { shadow.y += floorDrop }
        let r = max(5, tw * 0.012)
        let at = CGPoint(x: min(max(raw.x, r * 2), courtSize.width - r * 2), y: min(max(raw.y, r * 2), bounds.height - r * 2))
        c.setFillColor(color(0x65001d2a).cgColor)
        c.fillEllipse(in: CGRect(x: shadow.x - r, y: shadow.y - r * 0.35, width: r * 2, height: r * 0.7))
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [UIColor.white.cgColor, color(0xffffe084).cgColor, color(0xffe7aa35).cgColor] as CFArray, locations: [0, 0.5, 1]) {
            c.saveGState(); c.addEllipse(in: CGRect(x: at.x - r, y: at.y - r, width: r * 2, height: r * 2)); c.clip()
            let centre = CGPoint(x: at.x - r * 0.3, y: at.y - r * 0.4)
            c.drawRadialGradient(g, startCenter: centre, startRadius: 0, endCenter: centre, endRadius: r * 1.5, options: [.drawsAfterEndLocation])
            c.restoreGState()
        }
        tableArt.spin(c, x: at.x, y: at.y, r: r, flight: game.flight)
        if at != raw {
            // An edge marker points toward a ball that has left the view.
            c.setStrokeColor(UIColor.white.cgColor); c.setLineWidth(3)
            c.move(to: at); c.addLine(to: CGPoint(x: at.x + min(max(raw.x - at.x, -r * 2), r * 2), y: at.y + min(max(raw.y - at.y, -r * 2), r * 2))); c.strokePath()
        }
    }
    private func tableFrame(_ c: CGContext) { tableArt.frame(c, { v, z in self.project(self.screen(v), z) }, tw: tw, drop: floorDrop) }
    override func draw(_ rect: CGRect) {
        guard let c = UIGraphicsGetCurrentContext() else { return }
        relayout()
        drawn = true; labels = [:]; labelRequests = []; bodyBoxes = [:]; racketPoints = [:]
        let now = CACurrentMediaTime()
        for (i, a) in game.actors.enumerated() {
            let prior = lastAt[i] ?? a.at; lastAt[i] = a.at
            let travel = hypot(a.at.x - prior.x, (a.at.y - prior.y) * MPTeamMovement.depthScale)
            if travel > 0.0003 { walked[i] = (walked[i] ?? 0) + travel; stepAt[i] = now }
        }
        c.saveGState(); c.translateBy(x: gutter, y: 0); defer { c.restoreGState() }
        c.saveGState(); camera.apply(c)
        for i in game.actors.indices {
            let f = floorFoot(i), r = actorHeight * 0.19
            c.setFillColor(color(0x380d1930).cgColor); c.fillEllipse(in: CGRect(x: f.x - r, y: f.y - r * 0.2, width: r * 2, height: r * 0.4))
        }
        // A far-end ball is drawn behind the far players and the table, never over the tabletop.
        if farEnding { drawBall(c) }
        for i in game.actors.indices.filter({ game.actors[$0].team != nearTeam }).sorted(by: { screen(game.actors[$0].at).y < screen(game.actors[$1].at).y }) { drawActor(c, i) }
        tableFrame(c)
        tableArt.surface(c, { v, z in self.project(v, z) }, top: top, depth: depth)
        if game.stage?.territory == true {
            let paint = game.paint
            for y in 0..<MPPaint.rows { for x in 0..<MPPaint.cols {
                let owner = paint.owners[y * MPPaint.cols + x]
                if owner == (y < MPPaint.rows / 2 ? 1 : 0) { continue }
                let a = Double(x) / Double(MPPaint.cols), b = Double(y) / Double(MPPaint.rows), s = 1.0 / Double(MPPaint.cols)
                c.setFillColor(color(owner == 0 ? 0xff4bf4c7 : 0xffff74b6).cgColor)
                c.addPath(path([MPPoint(a, b), MPPoint(a + s, b), MPPoint(a + s, b + s), MPPoint(a, b + s)])); c.fillPath()
            } }
        } else {
            for mark in game.marks {
                let at = project(mark.at)
                c.setFillColor(color(0x997af1d8).cgColor)
                c.fillEllipse(in: CGRect(x: at.x - tw * 0.038, y: at.y - depth * 0.025, width: tw * 0.076, height: depth * 0.05))
            }
        }
        tableArt.lines(c, { v, z in self.project(v, z) })
        // Android bcee181: a ring where the ball last bounced (0.45 s) and a red cross where a ball left the table.
        if let bounce = game.bounceAt, game.clock - game.bounceTime < 0.45 {
            let q = project(bounce)
            c.setStrokeColor(color(0xff8ef5df).cgColor); c.setLineWidth(max(2, tw * 0.005))
            c.strokeEllipse(in: CGRect(x: q.x - tw * 0.025, y: q.y - tw * 0.012, width: tw * 0.05, height: tw * 0.024))
        }
        if let ending = game.ending, ending.fault == .leftTable {
            let q = project(ending.outAt), r = tw * 0.018
            c.setStrokeColor(color(0xffff5b67).cgColor); c.setLineWidth(max(3, tw * 0.007)); c.setLineCap(.butt)
            c.move(to: CGPoint(x: q.x - r, y: q.y - r)); c.addLine(to: CGPoint(x: q.x + r, y: q.y + r))
            c.move(to: CGPoint(x: q.x - r, y: q.y + r)); c.addLine(to: CGPoint(x: q.x + r, y: q.y - r)); c.strokePath()
        }
        // When reaching around a sideline, the authored paddle may extend over the tabletop. Reveal only the
        // contacting hand, never the whole far body.
        if game.clock - game.lastContact < 0.10, game.actors.indices.contains(game.hitter), game.actors[game.hitter].team != nearTeam,
           let q = racketPoints[game.hitter], let r = racketRadii[game.hitter] {
            c.saveGState(); c.addEllipse(in: CGRect(x: q.x - r * 1.25, y: q.y - r * 1.25, width: r * 2.5, height: r * 2.5)); c.clip()
            drawActor(c, game.hitter); c.restoreGState()
        }
        if game.targeted || game.stage?.serve == true {
            let targets = game.targets()
            for (i, t) in targets.enumerated() {
                let done = game.painted.contains(i), next = game.stage?.skill != .shape || i == game.painted.count
                let radius = game.stage?.skill == .shape ? 0.046 : game.radius
                c.setFillColor(color(done ? 0xff65f5cf : next ? 0xffffd76c : 0xffc5eafa).cgColor)
                c.addPath(path((0...32).map { j in let angle = Double(j) * 2 * .pi / 32; return MPPoint(t.x + cos(angle) * radius, t.y + sin(angle) * radius) })); c.fillPath()
                if game.stage?.skill == .shape { text(done ? "✓" : String(i + 1), at: project(t), size: min(tw * 0.03, 16), color: ink) }
            }
        }
        // A ball beyond the net is drawn before it, so the net covers it.
        let behindNet = !farEnding && screen(game.flight?.position ?? game.ending?.position ?? MPPoint(0.5, 1)).y < 0.5
        if behindNet { drawBall(c) }
        let netScale = game.tuning.netHeight / 0.12
        tableArt.net(c, { v, z in self.project(v, self.visibleLoft(z * netScale)) })
        for i in game.actors.indices.filter({ game.actors[$0].team == nearTeam }).sorted(by: { screen(game.actors[$0].at).y < screen(game.actors[$1].at).y }) { drawActor(c, i) }
        if !farEnding && !behindNet { drawBall(c) }
        c.restoreGState()
        // Android `ArenaBackdrop.foreground`: the castle's foreground foliage, through the same camera, covers the
        // table and the players; the names stay above it.
        if let backdrop = scenery?.view, let offset = sceneryOffset, !backdrop.foliage.isEmpty {
            c.saveGState(); camera.apply(c); c.translateBy(x: -offset.x, y: -offset.y)
            for (piece, box) in backdrop.foliage { piece.draw(in: box) }
            c.restoreGState()
        }
        for (index, point, active) in labelRequests { drawLabel(c, index, camera.painted(point), active) }
        if game.showServeFaultBadge {
            let message = hebrew ? "הגשה פסולה" : "Fault"
            let size = min(27, bounds.height * 0.085)
            let font = UIFont.systemFont(ofSize: size, weight: .bold)
            let half = (message as NSString).size(withAttributes: [.font: font]).width / 2 + size * 0.75, cy = bounds.height * 0.32
            let box = CGRect(x: courtSize.width / 2 - half, y: cy - size, width: half * 2, height: size * 2)
            c.setFillColor(color(0xf2e91e63).cgColor)
            c.addPath(UIBezierPath(roundedRect: box, cornerRadius: size * 0.55).cgPath); c.fillPath()
            text(message, at: CGPoint(x: courtSize.width / 2, y: cy), size: size, color: .white, rounded: false)
        }
    }
    // MARK: Input (Android `worldTouch`: a drag moves the player, a tap aims a serve or return, a Standard swipe
    // returns as the ball arrives, a Pro stroke is read on release)
    private func velocity() -> CGPoint {
        guard let last = samples.last, let first = samples.first(where: { last.0 - $0.0 <= 0.1 }), last.0 - first.0 > 0.001 else { return .zero }
        let dt = CGFloat(last.0 - first.0)
        return CGPoint(x: (last.1.x - first.1.x) / dt, y: (last.1.y - first.1.y) / dt)
    }
    /// A point in court coordinates (without the gutter).
    private func court(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x - gutter, y: p.y) }
    /// Android: the gutters belong to the sidebar, not to the court View.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        super.point(inside: point, with: event) && point.x >= gutter && point.x <= bounds.width - gutter
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let p = camera.base(court(touch.location(in: self)))
        down = p; downAt = touch.timestamp; dragging = false
        if game.actors.indices.contains(localSeat) { dragStart = game.actors[localSeat].at }
        dragOrigin = ground(p); tapSent = false; samples = [(touch.timestamp, p)]
        playerDrag = control == 3 && screen(ground(p)).y > 1.0
        strokePath = [p]
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let p = camera.base(court(touch.location(in: self)))
        samples.append((touch.timestamp, p)); samples.removeAll { touch.timestamp - $0.0 > 0.15 }
        let moved = hypot(p.x - down.x, p.y - down.y) > 12
        let scale = Double(max(min(courtSize.width, courtSize.height), 1)) * 0.82
        if game.stage?.standard == true && !tapSent && moved {
            let v = velocity()
            tapSent = game.standardSwipe(MPPoint(Double(v.x) / scale, Double(v.y) / scale))
        }
        if game.stage == nil && !tapSent && (control == 0 || control == 1) && game.canPrepareStandard(localSeat) && moved {
            let v = velocity(), vx = Double(v.x) / scale, vy = Double(v.y) / scale, speed = hypot(vx, vy)
            if speed > 0.045 {
                let stroke = MPPongStroke(aim: (vx / max(speed, 0.001)).mpClamp(-1, 1), power: 1 - exp(-speed / 1.15))
                let world = nearTeam == 0 ? stroke : stroke.reflected
                if let onStroke { onStroke(world); tapSent = true } else { tapSent = game.strokeSeat(localSeat, world) }
            }
        }
        if tapSent { return }
        for t in event?.coalescedTouches(for: touch) ?? [touch] { strokePath.append(camera.base(court(t.location(in: self)))) }
        if moved { dragging = true }
        if dragging && (control != 3 || playerDrag) {
            let at = ground(p), delta = MPPoint(at.x - dragOrigin.x, at.y - dragOrigin.y)
            // Relative drags never pull a player back to the finger's starting point. Small vertical finger wobble
            // must not move the player off the hitting line.
            let vertical = abs(p.y - down.y) > max(24, abs(p.x - down.x) * 0.65)
            move(MPPoint(dragStart.x + delta.x, dragStart.y + (vertical ? delta.y / 0.45 : 0)))
        }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let p = camera.base(court(touch.location(in: self)))
        samples = []; strokePath.append(p)
        defer { downAt = 0 }
        if playerDrag { return }
        if control == 3 {
            let scale = Double(max(min(courtSize.width, courtSize.height), 1)) * 0.82
            let points = strokePath.map { MPPoint(Double($0.x) / scale, Double($0.y) / scale) }
            if let stroke = MPPongStroke.read(points, durationMs: Int64((touch.timestamp - downAt) * 1000)) {
                let world = nearTeam == 0 ? stroke : stroke.reflected
                if let onStroke { onStroke(world) } else { game.strokeSeat(localSeat, world) }
            } else if game.waitingServe { tap(ground(p)) }
        } else if !dragging && !tapSent { tap(ground(p)) }
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { samples = []; downAt = 0; dragging = false }
    private func move(_ to: MPPoint) { if let onMove { onMove(to) } else { game.moveSeat(localSeat, to) } }
    private func tap(_ to: MPPoint) { if let onTap { onTap(to) } else { game.tapSeat(localSeat, to) } }
}

/// SwiftUI host for the practice and team table.
struct MPPracticeCourt: UIViewRepresentable {
    let game: MPPlay
    var hebrew: Bool
    var localSeat = 0
    var simulate = true
    var running: Bool
    var names: [Int: String] = [:]
    var controlOverride: Int? = nil
    var soundsEnabled: () -> Bool = { true }
    var onMove: ((MPPoint) -> Void)? = nil
    var onTap: ((MPPoint) -> Void)? = nil
    var onStroke: ((MPPongStroke) -> Void)? = nil
    var onFrame: (() -> Void)? = nil
    var gutter: CGFloat = 0
    var scenery: MPArenaScenery? = nil
    func makeUIView(context: Context) -> MPPracticeCourtView { MPPracticeCourtView(game: game) }
    func updateUIView(_ view: MPPracticeCourtView, context: Context) {
        view.game = game; view.hebrew = hebrew; view.localSeat = localSeat; view.simulate = simulate; view.names = names
        view.controlOverride = controlOverride; view.gutter = gutter; view.scenery = scenery
        view.soundsEnabled = soundsEnabled; view.onMove = onMove; view.onTap = onTap; view.onStroke = onStroke; view.onFrame = onFrame
        view.accessibilityLabel = hebrew ? "שולחן האימון. גררו כדי לזוז והקישו על יעד כדי לחבוט." : "Practice table. Drag to move and tap a target to hit."
        view.setRunning(running)
    }
    /// Android `PongCourtStyle.landscape`: the court spans `value` points of gutter on each side.
    func withGutter(_ value: CGFloat) -> MPPracticeCourt { var court = self; court.gutter = value; return court }
    static func dismantleUIView(_ view: MPPracticeCourtView, coordinator: ()) { view.setRunning(false); view.game.contactReach = nil }
}
