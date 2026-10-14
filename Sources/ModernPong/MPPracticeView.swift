import SwiftUI
import UIKit

/// The Ping Pong art that only the standalone app bundles (`Resources/ModernPongArt`, a folder reference):
/// Android `assets/pong-poses`, `assets/team-celebration`, `tournament_remove` and the menu music.
enum MPArtFiles {
    static var directory: URL? { Bundle.main.url(forResource: "ModernPongArt", withExtension: nil) }
    static func url(_ path: String) -> URL? {
        guard let directory else { return nil }
        let url = directory.appendingPathComponent(path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    static func image(_ path: String) -> UIImage? { url(path).flatMap { UIImage(contentsOfFile: $0.path) } }
}

/// Android `PongPlayerAtlas`: complete authored paddle poses (front, side and rear; four phases each), anchored at
/// the feet. Atlases are decoded on demand and released with the court that uses them.
final class MPPoseAtlas {
    enum Facing: Int { case front, side, rear }
    struct Geometry { let bounds: CGRect; let racket: CGPoint; let radius: CGFloat; let frame: Int }
    private struct Frame { let source: CGRect; let visible: CGRect; let foot: CGPoint; let paddle: CGPoint; let radius: CGFloat }
    private struct Sheet { let image: CGImage; let frames: [Frame]; let heights: [CGFloat] }
    private var sheets: [String: Sheet] = [:]
    private var crops: [String: UIImage] = [:]
    private static var manifestCache: [String: Any]?
    private static var portraits: [String: UIImage] = [:]
    private static func manifest() -> [String: Any]? {
        if let manifestCache { return manifestCache }
        guard let url = MPArtFiles.url("pong-poses/atlas.json"), let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        manifestCache = json; return json
    }
    private static func frames(_ id: String) -> [Frame]? {
        guard let entry = manifest()?[id] as? [String: Any], let list = entry["frames"] as? [[String: Any]], list.count >= 12 else { return nil }
        func numbers(_ value: Any?) -> [CGFloat] { ((value as? [Any]) ?? []).compactMap { ($0 as? NSNumber).map { CGFloat($0.doubleValue) } } }
        var out: [Frame] = []
        for item in list {
            let r = numbers(item["rect"]), b = numbers(item["bounds"]), f = numbers(item["foot"]), p = numbers(item["paddle"])
            guard r.count == 4, b.count == 4, f.count == 2, p.count == 2 else { return nil }
            out.append(Frame(source: CGRect(x: r[0], y: r[1], width: r[2] - r[0], height: r[3] - r[1]),
                             visible: CGRect(x: b[0], y: b[1], width: b[2] - b[0], height: b[3] - b[1]),
                             foot: CGPoint(x: f[0], y: f[1]), paddle: CGPoint(x: p[0], y: p[1]),
                             radius: CGFloat((item["radius"] as? NSNumber)?.doubleValue ?? 20)))
        }
        return out
    }
    static var available: Bool { manifest() != nil }
    private func sheet(_ id: String) -> Sheet? {
        if let sheet = sheets[id] { return sheet }
        guard let frames = MPPoseAtlas.frames(id), let image = MPArtFiles.image("pong-poses/" + id + ".png")?.cgImage else { return nil }
        let sheet = Sheet(image: image, frames: frames, heights: (0..<3).map { frames[$0 * 4].visible.height })
        sheets[id] = sheet; return sheet
    }
    private func parts(_ id: String, _ facing: Facing, _ phase: Int) -> (Sheet, Frame, Int)? {
        guard let sheet = sheet(id) else { return nil }
        let index = facing.rawValue * 4 + min(max(phase, 0), 3)
        return (sheet, sheet.frames[index], index)
    }
    func geometry(_ id: String, _ facing: Facing, foot: CGPoint, height: CGFloat, phase: Int) -> Geometry? {
        guard let (sheet, f, index) = parts(id, facing, phase) else { return nil }
        let scale = height / max(sheet.heights[facing.rawValue], 1)
        func x(_ v: CGFloat) -> CGFloat { foot.x + (v - f.foot.x) * scale }
        func y(_ v: CGFloat) -> CGFloat { foot.y + (v - f.foot.y) * scale }
        return Geometry(bounds: CGRect(x: x(f.visible.minX), y: y(f.visible.minY), width: (f.visible.width) * scale, height: f.visible.height * scale),
                        racket: CGPoint(x: x(f.paddle.x), y: y(f.paddle.y)), radius: f.radius * scale, frame: index)
    }
    @discardableResult func draw(_ id: String, _ facing: Facing, foot: CGPoint, height: CGFloat, phase: Int) -> Geometry? {
        guard let (sheet, f, index) = parts(id, facing, phase) else { return nil }
        let key = id + "/" + String(index)
        let crop: UIImage
        if let cached = crops[key] { crop = cached }
        else {
            guard let cg = sheet.image.cropping(to: f.source) else { return nil }
            crop = UIImage(cgImage: cg); crops[key] = crop
        }
        let scale = height / max(sheet.heights[facing.rawValue], 1)
        crop.draw(in: CGRect(x: foot.x - f.foot.x * scale, y: foot.y - f.foot.y * scale, width: f.source.width * scale, height: f.source.height * scale))
        return geometry(id, facing, foot: foot, height: height, phase: phase)
    }
    /// Android `BotPortrait`: the first front pose cropped to its visible body, kept as a small image so the large
    /// atlas is not held in memory for a menu.
    static func portrait(_ id: String) -> UIImage? {
        if let cached = portraits[id] { return cached }
        guard let frames = frames(id), let atlas = MPArtFiles.image("pong-poses/" + id + ".png")?.cgImage else { return nil }
        let f = frames[0]
        let rect = CGRect(x: f.source.minX + f.visible.minX, y: f.source.minY + f.visible.minY, width: f.visible.width, height: f.visible.height)
        guard let cropped = atlas.cropping(to: rect) else { return nil }
        let scale = min(1, 320 / max(rect.height, 1)), size = CGSize(width: rect.width * scale, height: rect.height * scale)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let small = UIGraphicsImageRenderer(size: size, format: format).image { _ in UIImage(cgImage: cropped).draw(in: CGRect(origin: .zero, size: size)) }
        portraits[id] = small; return small
    }
}

/// Android `PongPracticeView`: the daily-journey and team table. The far players stand behind the table, the near
/// players in front of it; the visible ball end is blended into the intact ready paddle. Online friends only draw
/// the authority's snapshots (`simulate = false`) and send moves and taps.
final class MPPracticeCourtView: UIView {
    /// Online friends receive a new restored table with every snapshot; its event serial continues the authority's,
    /// so a changed serial still plays the hit sounds (Android `heardEvent`).
    var game: MPPlay { didSet { if game !== oldValue { attachSound() } } }
    var hebrew = false
    var names: [Int: String] = [:]
    var localSeat = 0
    var simulate = true
    var soundsEnabled: () -> Bool = { true }
    var onMove: ((MPPoint) -> Void)?
    var onTap: ((MPPoint) -> Void)?
    var onFrame: (() -> Void)?
    private let atlas = MPPoseAtlas()
    private let audio = MPAudio()
    private var camera = MPReceptionCamera()
    private var link: CADisplayLink?
    private var stamp: CFTimeInterval = 0, drawn = false, heardEvent = 0
    private var lastX: [Int: Double] = [:], walked: [Int: Double] = [:], stepAt: [Int: CFTimeInterval] = [:]
    private var bodyBoxes: [Int: CGRect] = [:]
    private var labelRequests: [(Int, CGPoint, Bool)] = []
    private var actorHeight: CGFloat = 1, floorDrop: CGFloat = 1, lift: CGFloat = 1, left: CGFloat = 0, top: CGFloat = 0, tw: CGFloat = 1, depth: CGFloat = 1
    private var down = CGPoint.zero, holding = false, dragging = false
    private var lastFlightOffset = CGPoint.zero, endingSeen: MPRallyEnding?, endingOffset = CGPoint.zero
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
    override func willMove(toWindow newWindow: UIWindow?) { super.willMove(toWindow: newWindow); if newWindow == nil { setRunning(false) } }
    @objc private func step(_ display: CADisplayLink) {
        let now = display.timestamp
        let cameraElapsed = stamp == 0 ? 0 : min(max(now - stamp, 0), 0.1)
        let dt = stamp == 0 || !drawn ? 0 : min(now - stamp, 1.0 / 30)
        stamp = now
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
            camera.update(cameraElapsed, assist: game.reception, local: localSeat, focus: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2), size: bounds.size, holding: holding, reduceMotion: UIAccessibility.isReduceMotionEnabled)
        }
        onFrame?()
        setNeedsDisplay()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width, h = bounds.height
        tw = min(w * 0.91, h * 1.9); left = (w - tw) / 2
        actorHeight = min(h * 0.27, tw * 0.34); floorDrop = actorHeight * 0.40
        depth = max(min(h * 0.61, (h - actorHeight - 40) / 1.14), h * 0.36)
        lift = min(depth * 0.62, tw * 0.62)
        top = actorHeight * 0.54 + depth * 0.07 + 12
    }
    private var nearTeam: Int { game.actors.indices.contains(localSeat) ? game.actors[localSeat].team : 0 }
    private func screen(_ v: MPPoint) -> MPPoint { nearTeam == 0 ? v : MPPoint(1 - v.x, 1 - v.y) }
    func project(_ world: MPPoint, _ z: Double = 0) -> CGPoint {
        let v = screen(world)
        return CGPoint(x: left + tw * (0.5 + (CGFloat(v.x) - 0.5) * (0.72 + 0.28 * CGFloat(v.y))), y: top + depth * CGFloat(v.y) - CGFloat(z) * lift)
    }
    private func facing(_ index: Int) -> MPPoseAtlas.Facing { game.actors[index].team == nearTeam ? .rear : .front }
    /// Feet belong to the floor outside the end line, never to a ball contact.
    private func floorFoot(_ index: Int) -> CGPoint {
        let a = game.actors[index]
        let clearance = Double(actorHeight * 0.08 / depth)
        let at = project(MPPoint(a.at.x, a.team == 0 ? 1 + clearance : -clearance))
        return CGPoint(x: at.x, y: at.y + floorDrop)
    }
    private func visibleLoft(_ z: Double) -> Double { z <= 0.16 ? z : 0.16 + 0.16 * (1 - exp(-(z - 0.16) / 0.16)) }
    /// Android `renderedBallPoint`: the table flight is unchanged; only its visible end blends into the ready paddle.
    private func renderedBallPoint(_ position: MPPoint, _ z: Double) -> CGPoint {
        let raw = project(position, z < 0 ? z * Double(floorDrop) / (1.25 * Double(lift)) : visibleLoft(z))
        if let ending = game.ending, game.flight == nil {
            if endingSeen != ending { endingSeen = ending; endingOffset = lastFlightOffset }
            let u = CGFloat((ending.remaining / 1.65).mpClamp(0, 1)), weight = u * u * (3 - 2 * u)
            return CGPoint(x: raw.x + endingOffset.x * weight, y: raw.y + endingOffset.y * weight)
        }
        endingSeen = nil; lastFlightOffset = .zero
        let side = position.y > 0.5 ? 0 : 1
        let distance = MPContactGeometry.distanceToEnd(side, position.y)
        let u = ((0.24 - distance) / (0.24 - MPContactGeometry.endInset)).mpClamp(0, 1)
        if u <= 0 || z > 1.2 { return raw }
        let f = game.flight
        let outgoing = f.map { ($0.striker == .child ? 0 : 1) == side } ?? false
        let index: Int
        if outgoing { index = game.hitter }
        else if game.team && game.alternate { index = game.nextHitter[side] }
        else if let nearest = game.actors.indices.filter({ game.actors[$0].team == side }).min(by: { abs(game.actors[$0].at.x - position.x) < abs(game.actors[$1].at.x - position.x) }) { index = nearest }
        else { return raw }
        guard game.actors.indices.contains(index) else { return raw }
        let a = game.actors[index]
        if abs(a.at.x - position.x) > MPContactGeometry.lateralReach { return raw }
        guard let ready = atlas.geometry(a.character, facing(index), foot: floorFoot(index), height: actorHeight, phase: 0) else { return raw }
        // One contact-height reference, so the ball does not dip at the paddle.
        var time = 0.0
        if let f, abs(f.velocity.y) > 0.0001 { time = max((MPContactGeometry.baseline(side) - position.y) / f.velocity.y, 0) }
        let contactZ: Double
        if outgoing { contactZ = game.contactHeight }
        else if let f { contactZ = max(0, z + f.lift * time - 0.5 * game.tuning.gravity * time * time) }
        else { contactZ = z }
        let plane = project(MPPoint(a.at.x, MPContactGeometry.baseline(side)), visibleLoft(contactZ))
        let weight = CGFloat(u * u * (3 - 2 * u))
        lastFlightOffset = CGPoint(x: (ready.racket.x - plane.x) * weight, y: (ready.racket.y - plane.y) * weight)
        return CGPoint(x: raw.x + lastFlightOffset.x, y: raw.y + lastFlightOffset.y)
    }
    private func ground(_ p: CGPoint) -> MPPoint {
        let yy = Double((p.y - top) / max(depth, 1))
        let x = 0.5 + Double(p.x - left - tw * 0.5) / Double(tw * (0.72 + 0.28 * CGFloat(yy)))
        return screen(MPPoint(x.mpClamp(0, 1), yy))
    }
    private func color(_ argb: UInt32) -> UIColor {
        UIColor(red: CGFloat((argb >> 16) & 0xff) / 255, green: CGFloat((argb >> 8) & 0xff) / 255, blue: CGFloat(argb & 0xff) / 255, alpha: CGFloat(argb >> 24) / 255)
    }
    private func path(_ points: [MPPoint]) -> CGPath {
        let p = CGMutablePath()
        for (i, v) in points.enumerated() { let q = project(v); if i == 0 { p.move(to: q) } else { p.addLine(to: q) } }
        p.closeSubpath(); return p
    }
    private func line(_ c: CGContext, _ a: MPPoint, _ b: MPPoint, _ argb: UInt32, _ width: CGFloat = 2, z: Double = 0) {
        let x = project(a, z), y = project(b, z)
        c.setStrokeColor(color(argb).cgColor); c.setLineWidth(width); c.setLineCap(.butt)
        c.move(to: x); c.addLine(to: y); c.strokePath()
    }
    private func gradient(_ c: CGContext, _ clip: CGPath, from: CGFloat, to: CGFloat, _ a: UInt32, _ b: UInt32) {
        guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [color(a).cgColor, color(b).cgColor] as CFArray, locations: [0, 1]) else { return }
        c.saveGState(); c.addPath(clip); c.clip()
        c.drawLinearGradient(g, start: CGPoint(x: 0, y: from), end: CGPoint(x: 0, y: to), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        c.restoreGState()
    }
    private func text(_ value: String, at: CGPoint, size: CGFloat, color: UIColor) {
        let font = UIFont.systemFont(ofSize: size, weight: .bold)
        let rounded = font.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? font
        let attributed = NSAttributedString(string: value, attributes: [.font: rounded, .foregroundColor: color])
        let measured = attributed.size()
        attributed.draw(at: CGPoint(x: at.x - measured.width / 2, y: at.y - measured.height / 2))
    }
    private func drawActor(_ c: CGContext, _ index: Int) {
        let a = game.actors[index], rear = a.team == nearTeam, foot = floorFoot(index), face = facing(index)
        let f = game.flight, age = game.clock - game.lastContact
        var incoming = false
        if let f, !f.resolved, f.receiver, (f.striker == .minik) == (a.team == 0), abs(f.position.x - a.at.x) < MPContactGeometry.lateralReach,
           MPContactGeometry.distanceToEnd(a.team, f.position.y) < 0.20 { incoming = true }
        let walking = !(game.hitter == index && age < 0.34) && !incoming && CACurrentMediaTime() - (stepAt[index] ?? 0) < 0.13
        let art = walking ? a.character + "-walk" : a.character
        let phase: Int
        if game.hitter == index && age < 0.10 { phase = 0 }
        else if game.hitter == index && age < 0.34 { phase = 3 }
        else if incoming { phase = a.character == "minik" && rear ? 0 : 1 }
        else if walking { phase = Int((walked[index] ?? 0) / 0.045) % 4 }
        else { phase = 0 }
        guard let body = atlas.draw(art, face, foot: foot, height: actorHeight, phase: phase) ?? atlas.draw(a.character, face, foot: foot, height: actorHeight, phase: phase) else {
            // Without the pose art (a build that does not bundle it) a simple marker keeps the place visible.
            c.setFillColor(color(a.team == 0 ? 0xff4bf4c7 : 0xffff74b6).cgColor)
            c.fillEllipse(in: CGRect(x: foot.x - actorHeight * 0.12, y: foot.y - actorHeight * 0.5, width: actorHeight * 0.24, height: actorHeight * 0.5))
            labelRequests.append((index, CGPoint(x: foot.x, y: rear ? foot.y + 14 : foot.y - actorHeight * 0.55 - 15), game.team && game.alternate && game.nextHitter[a.team] == index))
            return
        }
        bodyBoxes[index] = body.bounds
        let active = game.team && game.alternate && game.nextHitter[a.team] == index
        labelRequests.append((index, CGPoint(x: body.bounds.midX, y: rear ? foot.y + 14 : body.bounds.minY - 15), active))
    }
    private func drawLabel(_ c: CGContext, _ index: Int, _ at: CGPoint, _ active: Bool) {
        let name = names[index] ?? (index == localSeat ? (hebrew ? "אתם" : "You") : (MPRoster.find(game.actors[index].character) ?? MPRoster.all[0]).name(hebrew: hebrew))
        let size = min(13, bounds.height * 0.035)
        let font = UIFont.systemFont(ofSize: size, weight: .bold)
        let half = (name as NSString).size(withAttributes: [.font: font]).width / 2 + 12
        // A player zoomed out of frame takes the label too; clamping it onto the table looks wrong.
        if at.y < -size * 0.8 || at.y > bounds.height + size * 0.8 || at.x < -half || at.x > bounds.width + half { return }
        var cx = min(max(at.x, half + 2), bounds.width - half - 2), cy = min(max(at.y, size * 0.8 + 2), bounds.height - size * 0.8 - 2)
        // A shallow landscape window can clamp an above-head label onto the head: place it beside that player.
        if game.actors[index].team != nearTeam, let body = bodyBoxes[index] {
            let head = camera.painted(CGPoint(x: body.midX, y: body.minY))
            if cy + size * 0.8 > head.y - 3 {
                let outward: CGFloat = head.x < bounds.width * 0.5 ? -1 : 1
                let edge = camera.painted(CGPoint(x: outward < 0 ? body.minX : body.maxX, y: body.minY + size))
                cx = min(max(edge.x + outward * (half + 6), half + 2), bounds.width - half - 2)
                cy = min(max(edge.y, size * 0.8 + 2), bounds.height - size * 0.8 - 2)
            }
        }
        let box = CGRect(x: cx - half, y: cy - size * 0.8, width: half * 2, height: size * 1.6)
        c.setFillColor(color(active ? 0xffffd665 : 0xf4ffffff).cgColor)
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
        let at = CGPoint(x: min(max(raw.x, r * 2), bounds.width - r * 2), y: min(max(raw.y, r * 2), bounds.height - r * 2))
        c.setFillColor(color(0x65001d2a).cgColor)
        c.fillEllipse(in: CGRect(x: shadow.x - r, y: shadow.y - r * 0.35, width: r * 2, height: r * 0.7))
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [UIColor.white.cgColor, color(0xffffe084).cgColor, color(0xffe7aa35).cgColor] as CFArray, locations: [0, 0.5, 1]) {
            c.saveGState(); c.addEllipse(in: CGRect(x: at.x - r, y: at.y - r, width: r * 2, height: r * 2)); c.clip()
            let centre = CGPoint(x: at.x - r * 0.3, y: at.y - r * 0.4)
            c.drawRadialGradient(g, startCenter: centre, startRadius: 0, endCenter: centre, endRadius: r * 1.5, options: [.drawsAfterEndLocation])
            c.restoreGState()
        }
        if at != raw {
            // An edge marker points toward a ball that has left the view.
            c.setStrokeColor(UIColor.white.cgColor); c.setLineWidth(3)
            c.move(to: at); c.addLine(to: CGPoint(x: at.x + min(max(raw.x - at.x, -r * 2), r * 2), y: at.y + min(max(raw.y - at.y, -r * 2), r * 2))); c.strokePath()
        }
    }
    private func tableFrame(_ c: CGContext) {
        for v in [MPPoint(0.06, 0.08), MPPoint(0.94, 0.08), MPPoint(0.06, 0.92), MPPoint(0.94, 0.92)] {
            let q = project(screen(v)), w = tw * 0.018
            c.setFillColor(color(0xff163344).cgColor)
            c.addPath(UIBezierPath(roundedRect: CGRect(x: q.x - w, y: q.y + 4, width: w * 2, height: max(0, floorDrop - 4)), cornerRadius: w * 0.3).cgPath); c.fillPath()
            c.setFillColor(color(0xff6c98a4).cgColor); c.fill(CGRect(x: q.x - w, y: q.y + 4, width: w * 0.7, height: max(0, floorDrop - 9)))
            c.setFillColor(color(0xff172f3b).cgColor); c.fillEllipse(in: CGRect(x: q.x - w * 1.5, y: q.y + floorDrop - w * 0.4, width: w * 3, height: w * 0.8))
        }
        let l = project(screen(MPPoint(0, 1))), r = project(screen(MPPoint(1, 1)))
        c.setFillColor(color(0xff112d43).cgColor); c.fill(CGRect(x: l.x, y: l.y, width: r.x - l.x, height: tw * 0.027))
    }
    override func draw(_ rect: CGRect) {
        guard let c = UIGraphicsGetCurrentContext() else { return }
        drawn = true; labelRequests = []; bodyBoxes = [:]
        let now = CACurrentMediaTime()
        for (i, a) in game.actors.enumerated() {
            let prior = lastX[i] ?? a.at.x; lastX[i] = a.at.x
            let travel = abs(a.at.x - prior)
            if travel > 0.0003 { walked[i] = (walked[i] ?? 0) + travel; stepAt[i] = now }
        }
        c.saveGState(); camera.apply(c)
        for i in game.actors.indices {
            let f = floorFoot(i), r = actorHeight * 0.19
            c.setFillColor(color(0x380d1930).cgColor); c.fillEllipse(in: CGRect(x: f.x - r, y: f.y - r * 0.2, width: r * 2, height: r * 0.4))
        }
        // A far-end ball is drawn behind the far players and the table, never over the tabletop.
        if farEnding { drawBall(c) }
        for i in game.actors.indices.filter({ game.actors[$0].team != nearTeam }).sorted(by: { game.actors[$0].at.x < game.actors[$1].at.x }) { drawActor(c, i) }
        tableFrame(c)
        gradient(c, path([MPPoint(0, 0), MPPoint(1, 0), MPPoint(1, 0.5), MPPoint(0, 0.5)]), from: top, to: top + depth, 0xff2b6197, 0xff102f56)
        gradient(c, path([MPPoint(0, 0.5), MPPoint(1, 0.5), MPPoint(1, 1), MPPoint(0, 1)]), from: top + depth * 0.5, to: top + depth, 0xff256c81, 0xff164b65)
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
        let white: UInt32 = 0xffe9fbff
        line(c, MPPoint(0, 0), MPPoint(1, 0), white, 4); line(c, MPPoint(0, 0), MPPoint(0, 1), white, 4)
        line(c, MPPoint(1, 0), MPPoint(1, 1), white, 4); line(c, MPPoint(0, 1), MPPoint(1, 1), white, 4)
        line(c, MPPoint(0.5, 0), MPPoint(0.5, 1), 0x66ffffff, 2)
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
        for i in 0...32 {
            let a = project(MPPoint(Double(i) / 32, 0.5)), b = project(MPPoint(Double(i) / 32, 0.5), 0.12)
            c.setStrokeColor(color(0x99e1f7ff).cgColor); c.setLineWidth(1.4); c.move(to: a); c.addLine(to: b); c.strokePath()
        }
        for i in 0...5 { line(c, MPPoint(0, 0.5), MPPoint(1, 0.5), 0x99efffff, 1.4, z: Double(i) * 0.024) }
        line(c, MPPoint(-0.025, 0.5), MPPoint(1.025, 0.5), white, 4, z: 0.12)
        for i in game.actors.indices.filter({ game.actors[$0].team == nearTeam }).sorted(by: { game.actors[$0].at.x < game.actors[$1].at.x }) { drawActor(c, i) }
        if !farEnding { drawBall(c) }
        c.restoreGState()
        for (index, point, active) in labelRequests { drawLabel(c, index, camera.painted(point), active) }
    }
    // MARK: Input (Android: a drag moves the player, a tap aims a serve or return)
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        down = touch.location(in: self); holding = true; dragging = false
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let p = touch.location(in: self)
        if hypot(p.x - down.x, p.y - down.y) > 8 { dragging = true }
        if dragging { move(ground(camera.base(p))) }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        holding = false
        let point = ground(camera.base(touch.location(in: self)))
        if dragging { move(point) } else { tap(point) }
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { holding = false; dragging = false }
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
    var soundsEnabled: () -> Bool = { true }
    var onMove: ((MPPoint) -> Void)? = nil
    var onTap: ((MPPoint) -> Void)? = nil
    var onFrame: (() -> Void)? = nil
    func makeUIView(context: Context) -> MPPracticeCourtView { MPPracticeCourtView(game: game) }
    func updateUIView(_ view: MPPracticeCourtView, context: Context) {
        view.game = game; view.hebrew = hebrew; view.localSeat = localSeat; view.simulate = simulate; view.names = names
        view.soundsEnabled = soundsEnabled; view.onMove = onMove; view.onTap = onTap; view.onFrame = onFrame
        view.accessibilityLabel = hebrew ? "שולחן האימון. גררו כדי לזוז והקישו על יעד כדי לחבוט." : "Practice table. Drag to move and tap a target to hit."
        view.setRunning(running)
    }
    static func dismantleUIView(_ view: MPPracticeCourtView, coordinator: ()) { view.setRunning(false) }
}
