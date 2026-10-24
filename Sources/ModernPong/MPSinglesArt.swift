import SpriteKit
import SwiftUI
import UIKit

/// Android `ArenaBackdrop` (a4174b6, 920caca): the game-only scenery behind a singles match. Legacy and Indoors keep the
/// original `modern_surround`; Beach, Park and Castle use the arena art (standalone app only; others fall back).
enum MPSinglesArena {
    static func image(_ arena: MPArena, wide: Bool) -> UIImage? { arena.backdrop(wide: wide) ?? UIImage(named: "mp_modern_surround") }
    /// Android `ArenaBackdrop.onDraw`: aspect fill, centred; landscape Beach keeps the shoreline above the far baseline
    /// (a top-anchored crop put landscape opponents in the sea). `bounds` is the backdrop's own size.
    static func destination(_ image: CGSize, in bounds: CGSize, arena: MPArena) -> CGRect {
        let wide = bounds.width > bounds.height
        let scale = max(bounds.width / max(image.width, 1), bounds.height / max(image.height, 1))
        let w = image.width * scale, h = image.height * scale
        let top = wide && arena == .beach ? min(max(bounds.height * 0.12 - h * 0.26, bounds.height - h), 0) : 0
        return CGRect(x: (bounds.width - w) / 2, y: top, width: w, height: h)
    }
    /// Android: white match captions stay legible on sky, sea and sunlit grass (top quarter, 0x9c10243b to clear).
    static let captionShade = UIColor(red: 0x10 / 255, green: 0x24 / 255, blue: 0x3b / 255, alpha: CGFloat(0x9c) / 255)
    /// Android `ArenaBackdrop.drawForeground`: only the castle's foreground foliage is traced (fractions of the image).
    /// Reusing the exact bitmap transform preserves the approved art; it is a depth pass, not a pasted image.
    static func foliage(_ arena: MPArena, wide: Bool) -> [[CGPoint]] {
        guard arena == .castle else { return [] }
        func p(_ v: [CGFloat]) -> [CGPoint] { stride(from: 0, to: v.count, by: 2).map { CGPoint(x: v[$0], y: v[$0 + 1]) } }
        if !wide {
            return [p([0, 0.735, 0.054, 0.731, 0.028, 0.755, 0.011, 0.772, 0.081, 0.763, 0.124, 0.768, 0.062, 0.785, 0.018, 0.801, 0.08, 0.787, 0.14, 0.802, 0.065, 0.809, 0.13, 0.822, 0.153, 0.803, 0.166, 0.824, 0.189, 0.811, 0.181, 0.836, 0.218, 0.831, 0.245, 0.848, 0.204, 0.843, 0.217, 0.867, 0.177, 0.85, 0.165, 0.879, 0.246, 0.886, 0.285, 0.912, 0.232, 0.902, 0.193, 0.904, 0.249, 0.931, 0.214, 0.928, 0.279, 0.949, 0.312, 0.951, 0.262, 0.966, 0.314, 0.985, 0.311, 1, 0, 1]),
                    p([1, 0.739, 0.962, 0.735, 0.98, 0.753, 0.949, 0.759, 0.916, 0.77, 0.978, 0.768, 0.95, 0.792, 0.92, 0.805, 0.89, 0.807, 0.92, 0.822, 0.858, 0.823, 0.814, 0.813, 0.851, 0.839, 0.9, 0.859, 0.818, 0.86, 0.857, 0.875, 0.76, 0.879, 0.813, 0.894, 0.849, 0.903, 0.757, 0.905, 0.698, 0.922, 0.754, 0.923, 0.808, 0.932, 0.764, 0.956, 0.697, 0.977, 0.738, 0.976, 0.735, 1, 1, 1])]
        }
        return [p([0, 0.67, 0.025, 0.66, 0.006, 0.706, 0.061, 0.737, 0.086, 0.733, 0.062, 0.762, 0.11, 0.747, 0.09, 0.791, 0.14, 0.774, 0.17, 0.738, 0.164, 0.787, 0.19, 0.77, 0.21, 0.789, 0.24, 0.76, 0.232, 0.806, 0.267, 0.831, 0.25, 0.867, 0.273, 0.91, 0.26, 0.954, 0.287, 1, 0, 1]),
                p([1, 0.773, 0.97, 0.743, 0.987, 0.802, 0.948, 0.828, 0.925, 0.807, 0.936, 0.866, 0.889, 0.874, 0.865, 0.86, 0.879, 0.895, 0.833, 0.883, 0.803, 0.929, 0.834, 0.937, 0.81, 0.976, 0.797, 1, 1, 1])]
    }
}

/// Android `ArenaBackdrop` as a SwiftUI view for the whole game screen (the rooms agent places it behind the HUD and
/// the court). The court (`MPScene`) draws the same scenery within its own frame; pass `MPScene.backdropFrame` so both
/// line up, and the castle's foreground foliage is drawn by the scene over the court.
struct MPSinglesArenaBackdrop: View {
    var arena: MPArena
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size, wide = size.width > size.height
            ZStack(alignment: .topLeading) {
                Color(red: 17 / 255, green: 29 / 255, blue: 57 / 255)
                if let image = MPSinglesArena.image(arena, wide: wide) {
                    let rect = MPSinglesArena.destination(image.size, in: size, arena: arena)
                    Image(uiImage: image).resizable().frame(width: rect.width, height: rect.height).offset(x: rect.minX, y: rect.minY)
                }
                LinearGradient(colors: [Color(MPSinglesArena.captionShade), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(width: size.width, height: size.height * 0.25)
            }.frame(width: size.width, height: size.height, alignment: .topLeading).clipped()
        }
        .ignoresSafeArea().accessibilityHidden(true)
    }
}

/// Android `PongNameSpace.draw` (the singles court): one name tag per visible player, beside its body, never over the
/// table, another body or another tag (`MPNameSpace.fits`); dropped when no candidate fits. View points, top-left origin.
enum MPSinglesNames {
    struct Tag { var text: String; var box: CGRect; var fill: UIColor; var ink: UIColor }
    /// A named bold face, so SpriteKit labels and the measured width use the same font.
    static let font = UIFont(name: "HelveticaNeue-Bold", size: 13) ?? .boldSystemFont(ofSize: 13)
    static func layout(_ names: [String], bodies: [CGRect?], table: CGRect, width: CGFloat, height: CGFloat, colors: [UIColor]) -> [Tag] {
        var occupied = bodies.compactMap { $0 }; occupied.append(table)
        var out: [Tag] = []
        for (i, name) in names.enumerated() {
            guard i < bodies.count, let b = bodies[i] else { continue }
            let half = (name as NSString).size(withAttributes: [.font: font]).width / 2 + 8, h: CGFloat = 11, gap: CGFloat = 5
            let centres = [CGPoint(x: b.midX, y: b.maxY + gap + h), CGPoint(x: b.midX, y: b.minY - gap - h),
                           CGPoint(x: b.minX - gap - half, y: b.minY + h), CGPoint(x: b.maxX + gap + half, y: b.minY + h)]
            guard let box = centres.map({ CGRect(x: $0.x - half, y: $0.y - h, width: half * 2, height: h * 2) }).first(where: { MPNameSpace.fits($0, width: width, height: height, obstacles: occupied) }) else { continue }
            let fill = i < colors.count ? colors[i] : MPTeamColors.uiFill(i)
            out.append(Tag(text: name, box: box, fill: fill, ink: MPColor.ui(MPRanks.ink(argb(fill))))); occupied.append(box)
        }
        return out
    }
    /// The opaque ARGB value of a colour (Android colour ints), for `MPRanks.ink`.
    static func argb(_ color: UIColor) -> UInt32 {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        func c(_ v: CGFloat) -> UInt32 { UInt32((min(max(v, 0), 1) * 255).rounded()) }
        return c(a) << 24 | c(r) << 16 | c(g) << 8 | c(b)
    }
}

/// Android `PongSpinArt`: the stripe follows the simulated spin; ordinary balls keep their original artwork. The node
/// is drawn in a unit-radius, y-down frame and placed by `update`.
enum MPSpinArt {
    static func node() -> SKNode {
        let root = SKNode()
        let arc = CGMutablePath()
        for i in 0...24 {
            let t = (-95 + 170 * Double(i) / 24) * .pi / 180
            let p = CGPoint(x: 0.72 * cos(t), y: 0.8 * sin(t))
            if i == 0 { arc.move(to: p) } else { arc.addLine(to: p) }
        }
        let stripe = SKShapeNode(path: arc); stripe.name = "stripe"; stripe.fillColor = .clear; stripe.lineCap = .butt
        let blue = MPColor.ui(0xff1870c5)
        stripe.strokeColor = blue
        let dot = SKShapeNode(circleOfRadius: 0.16); dot.position = CGPoint(x: -0.28, y: -0.4); dot.fillColor = blue; dot.strokeColor = .clear
        root.addChild(stripe); root.addChild(dot); root.isHidden = true
        return root
    }
    /// `at` is the ball centre in scene coordinates (y-up) and `radius` its drawn radius in points.
    static func update(_ node: SKNode, at: CGPoint, radius: CGFloat, flight: MPFlight?, visible: Bool) {
        guard visible, let f = flight, !(f.topSpin < 0.04 && abs(f.spin) < 0.04), radius > 0 else { node.isHidden = true; return }
        node.isHidden = false; node.position = at
        node.xScale = radius; node.yScale = -radius
        // Android rotates clockwise by spinAngle (times the side-spin sign) on a y-down canvas.
        node.zRotation = -CGFloat(f.spinAngle * (f.spin < 0 ? -1 : 1)) * .pi / 180
        (node.childNode(withName: "stripe") as? SKShapeNode)?.lineWidth = max(1.5, radius * 0.23) / radius
    }
}

/// Android `PongPlayerAtlas` drawn as SpriteKit sprites: each frame is a sub-texture of the decoded atlas (no copies).
/// Registered feet (including the walking atlases' pelvis registration) and paddle geometry come from `MPPoseAtlas`.
/// Mirroring (Android `mirror`) reflects about the foot. Every lookup returns nil when the art is not bundled.
final class MPPoseSprites {
    let atlas = MPPoseAtlas()
    private struct Entry { let texture: SKTexture; let rects: [CGRect]; let heights: [CGFloat]; let size: CGSize }
    private var entries: [String: Entry] = [:], frames: [String: SKTexture] = [:]
    private static var manifest: [String: Any]?
    private static func rects(_ id: String) -> ([CGRect], [CGFloat])? {
        if manifest == nil, let url = MPArtFiles.url("pong-poses/atlas.json"), let data = try? Data(contentsOf: url) {
            manifest = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        }
        guard let list = (manifest?[id] as? [String: Any])?["frames"] as? [[String: Any]], list.count >= 12 else { return nil }
        func numbers(_ value: Any?) -> [CGFloat] { ((value as? [Any]) ?? []).compactMap { ($0 as? NSNumber).map { CGFloat($0.doubleValue) } } }
        var rects: [CGRect] = [], visible: [CGFloat] = []
        for item in list {
            let r = numbers(item["rect"]), b = numbers(item["bounds"])
            guard r.count == 4, b.count == 4 else { return nil }
            rects.append(CGRect(x: r[0], y: r[1], width: r[2] - r[0], height: r[3] - r[1])); visible.append(b[3] - b[1])
        }
        return (rects, (0..<3).map { visible[$0 * 4] })
    }
    private func entry(_ id: String) -> Entry? {
        if let e = entries[id] { return e }
        guard let (rects, heights) = Self.rects(id), let image = MPArtFiles.image("pong-poses/" + id + ".png") else { return nil }
        let texture = SKTexture(image: image); texture.filteringMode = .linear
        let e = Entry(texture: texture, rects: rects, heights: heights, size: image.size)
        entries[id] = e; return e
    }
    func available(_ id: String) -> Bool { entry(id) != nil }
    /// Android `PongPlayerAtlas.geometry(id, facing, mirror, foot, height, phase)`; `foot` in view points, y down.
    func geometry(_ id: String, _ facing: MPPoseAtlas.Facing, mirror: Bool, foot: CGPoint, height: CGFloat, phase: Int) -> MPPoseAtlas.Geometry? {
        guard let g = atlas.geometry(id, facing, foot: foot, height: height, phase: phase) else { return nil }
        guard mirror else { return g }
        return MPPoseAtlas.Geometry(bounds: CGRect(x: 2 * foot.x - g.bounds.maxX, y: g.bounds.minY, width: g.bounds.width, height: g.bounds.height),
                                    racket: CGPoint(x: 2 * foot.x - g.racket.x, y: g.racket.y), radius: g.radius, frame: g.frame)
    }
    /// Android `PongPlayerAtlas.draw`: configures `node` to show the pose with its foot at `foot` (view points, y down),
    /// converted by `scene` into the node's (y-up) coordinates. Returns the pose geometry, or nil (node hidden).
    @discardableResult func show(_ node: SKSpriteNode, _ id: String, _ facing: MPPoseAtlas.Facing, mirror: Bool, foot: CGPoint, height: CGFloat,
                                 phase: Int, lean: CGFloat = 0, scene: (CGPoint) -> CGPoint) -> MPPoseAtlas.Geometry? {
        let index = facing.rawValue * 4 + min(max(phase, 0), 3)
        guard let e = entry(id), index < e.rects.count, let f = atlas.foot(id, facing, phase: phase) else { node.isHidden = true; return nil }
        let r = e.rects[index], key = id + "/" + String(index)
        let texture: SKTexture
        if let cached = frames[key] { texture = cached }
        else {
            texture = SKTexture(rect: CGRect(x: r.minX / e.size.width, y: 1 - r.maxY / e.size.height, width: r.width / e.size.width, height: r.height / e.size.height), in: e.texture)
            frames[key] = texture
        }
        let scale = height / max(e.heights[facing.rawValue], 1)
        node.isHidden = false
        if node.texture !== texture { node.texture = texture }
        node.xScale = 1; node.yScale = 1
        node.size = CGSize(width: r.width * scale, height: r.height * scale)
        node.anchorPoint = CGPoint(x: f.x / max(r.width, 1), y: 1 - f.y / max(r.height, 1))
        node.position = scene(foot); node.xScale = mirror ? -1 : 1
        // Android `canvas.rotate(lean, foot)`: clockwise degrees on a y-down canvas.
        node.zRotation = -lean * .pi / 180
        return geometry(id, facing, mirror: mirror, foot: foot, height: height, phase: phase)
    }
}
