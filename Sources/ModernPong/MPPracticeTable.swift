import SwiftUI
import UIKit

/// The Ping Pong art that only the standalone app bundles (`Resources/ModernPongArt`, a folder reference):
/// Android `assets/pong-poses`, `assets/team-celebration`, `tournament_remove`, the arena scenery (`arenas/`) and the
/// menu music. Every caller must tolerate nil (Minik Plus and Math Plus do not bundle it).
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
/// the feet. Atlases are decoded on demand and released with the court that uses them. Since Android 29f5dc7 a
/// walking atlas (`<id>-walk`) is registered to the pelvis of the standing body instead of the shoe touching the
/// bottom row, so a step no longer translates the whole body sideways.
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
    /// The atlas' alpha channel, top row first (Android `Bitmap.getPixel` alpha).
    private struct Alpha {
        let width: Int, height: Int, values: [UInt8]
        init?(_ image: CGImage) {
            let w = image.width, h = image.height
            guard w > 0, h > 0 else { return nil }
            var rgba = [UInt8](repeating: 0, count: w * h * 4)
            let drawn: Bool = rgba.withUnsafeMutableBytes { buffer in
                guard let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h)); return true
            }
            guard drawn else { return nil }
            width = w; height = h; values = stride(from: 3, to: rgba.count, by: 4).map { rgba[$0] }
        }
        func at(_ x: Int, _ y: Int) -> Int { x >= 0 && y >= 0 && x < width && y < height ? Int(values[y * width + x]) : 0 }
    }
    /// Android `PongPlayerAtlas.hipX`: the median alpha-weighted centre of the rows 60...68 % down the visible body
    /// (Kotlin Float math), or the authored foot when no opaque pixel is found.
    private static func hipX(_ alpha: Alpha, _ f: Frame) -> Float {
        var centers: [Float] = []
        let top = Float(f.visible.minY), height = Float(f.visible.height)
        let first = Int(top + height * 0.60), last = Int(top + height * 0.68)
        let left = Int(Float(f.visible.minX)), right = Int(Float(f.visible.maxX))
        let sourceX = Int(f.source.minX), sourceY = Int(f.source.minY)
        if first <= last {
            for y in first...last {
                var weight = 0.0, moment = 0.0
                for x in left..<max(left, right) {
                    let a = alpha.at(sourceX + x, sourceY + y)
                    if a >= 128 { weight += Double(a); moment += Double(a) * Double(x) }
                }
                if weight > 0 { centers.append(Float(moment / weight)) }
            }
        }
        let sorted = centers.sorted()
        return sorted.isEmpty ? Float(f.foot.x) : sorted[sorted.count / 2]
    }
    private func sheet(_ id: String) -> Sheet? {
        if let sheet = sheets[id] { return sheet }
        guard let frames = MPPoseAtlas.frames(id), let image = MPArtFiles.image("pong-poses/" + id + ".png")?.cgImage else { return nil }
        let heights = (0..<3).map { frames[$0 * 4].visible.height }
        var registered = frames
        if id.hasSuffix("-walk"), let base = sheet(String(id.dropLast(5))), let walkAlpha = Alpha(image), let baseAlpha = Alpha(base.image) {
            registered = frames.enumerated().map { i, f in
                let facing = i / 4, rest = base.frames[facing * 4]
                let offset = (Float(rest.foot.x) - MPPoseAtlas.hipX(baseAlpha, rest)) / Float(base.heights[facing]) * Float(heights[facing])
                return Frame(source: f.source, visible: f.visible, foot: CGPoint(x: CGFloat(MPPoseAtlas.hipX(walkAlpha, f) + offset), y: f.foot.y),
                             paddle: f.paddle, radius: f.radius)
            }
        }
        let sheet = Sheet(image: image, frames: registered, heights: heights)
        sheets[id] = sheet; return sheet
    }
    private func parts(_ id: String, _ facing: Facing, _ phase: Int) -> (Sheet, Frame, Int)? {
        guard let sheet = sheet(id) else { return nil }
        let index = facing.rawValue * 4 + min(max(phase, 0), 3)
        return (sheet, sheet.frames[index], index)
    }
    /// The registered foot of a frame in atlas pixels (tests and the large-table renderer).
    func foot(_ id: String, _ facing: Facing, phase: Int) -> CGPoint? { parts(id, facing, phase)?.1.foot }
    /// Android `geometry(id, facing, mirror, foot, height, phase)`: `mirror` flips the pose about the foot (the
    /// other hand reaches a ball on the far side of the body).
    func geometry(_ id: String, _ facing: Facing, mirror: Bool = false, foot: CGPoint, height: CGFloat, phase: Int) -> Geometry? {
        guard let (sheet, f, index) = parts(id, facing, phase) else { return nil }
        let scale = height / max(sheet.heights[facing.rawValue], 1)
        func x(_ v: CGFloat) -> CGFloat { foot.x + (v - f.foot.x) * scale * (mirror ? -1 : 1) }
        func y(_ v: CGFloat) -> CGFloat { foot.y + (v - f.foot.y) * scale }
        let l = x(f.visible.minX), r = x(f.visible.maxX)
        return Geometry(bounds: CGRect(x: min(l, r), y: y(f.visible.minY), width: abs(r - l), height: f.visible.height * scale),
                        racket: CGPoint(x: x(f.paddle.x), y: y(f.paddle.y)), radius: f.radius * scale, frame: index)
    }
    @discardableResult func draw(_ id: String, _ facing: Facing, mirror: Bool = false, foot: CGPoint, height: CGFloat, phase: Int) -> Geometry? {
        guard let (sheet, f, index) = parts(id, facing, phase) else { return nil }
        let key = id + "/" + String(index)
        let crop: UIImage
        if let cached = crops[key] { crop = cached }
        else {
            guard let cg = sheet.image.cropping(to: f.source) else { return nil }
            crop = UIImage(cgImage: cg); crops[key] = crop
        }
        let scale = height / max(sheet.heights[facing.rawValue], 1)
        let destination = CGRect(x: foot.x - f.foot.x * scale, y: foot.y - f.foot.y * scale, width: f.source.width * scale, height: f.source.height * scale)
        if mirror, let c = UIGraphicsGetCurrentContext() {
            c.saveGState(); c.translateBy(x: foot.x, y: foot.y); c.scaleBy(x: -1, y: 1); c.translateBy(x: -foot.x, y: -foot.y)
            crop.draw(in: destination); c.restoreGState()
        } else { crop.draw(in: destination) }
        return geometry(id, facing, mirror: mirror, foot: foot, height: height, phase: phase)
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

/// Android `PracticeTableLayout` (a4174b6, landscape 0e65e52): the daily table's actual layout, also used by large-table
/// friendly matches. Screen units are points (Android pixels; `density` 1 on iOS).
struct MPPracticeTableLayout: Equatable {
    var left: Double, top: Double, width: Double, depth: Double, actorHeight: Double, floorDrop: Double, lift: Double
    /// Table point `v` (screen orientation) at height `z` (table units of `lift`).
    func project(_ v: MPPoint, _ z: Double = 0) -> MPPoint {
        MPPoint(left + width * (0.5 + (v.x - 0.5) * (0.72 + 0.28 * v.y)), top + depth * v.y - z * lift)
    }
    /// The exact inverse of `project` at height `z`.
    func ground(x: Double, y: Double, z: Double = 0) -> MPPoint {
        let yy = (y - top + z * lift) / depth
        return MPPoint(0.5 + (x - left - width * 0.5) / (width * (0.72 + 0.28 * yy)), yy)
    }
    static func fit(_ w: Double, _ h: Double, density: Double = 1) -> MPPracticeTableLayout {
        let landscape = w > h
        let tw = min(w * (landscape ? 0.95 : 0.91), h * 1.9), actor = min(h * 0.27, tw * 0.34)
        let depth = landscape ? max(min(h * 0.64, (h - actor * 1.28 - 12 * density) / 1.035), h * 0.36)
            : max(min(h * 0.61, (h - actor - 40 * density) / 1.14), h * 0.36)
        // Reserve both the far character's head and the larger friendly-table floor offset. This keeps the larger
        // landscape table from clipping feet or labels.
        let top = landscape ? actor * 0.62 + depth * 0.035 + 4 * density : actor * 0.54 + depth * 0.07 + 12 * density
        return MPPracticeTableLayout(left: (w - tw) / 2, top: top, width: tw, depth: depth, actorHeight: actor, floorDrop: actor * 0.40, lift: min(depth * 0.62, tw * 0.62))
    }
}

/// Android `PongNameSpace.fits`: a name label is drawn only fully inside the view and clear of bodies and other labels.
enum MPNameSpace {
    static func fits(_ box: CGRect, width: CGFloat, height: CGFloat, obstacles: [CGRect]) -> Bool {
        box.minX >= 2 && box.maxX <= width - 2 && box.minY >= 2 && box.maxY <= height - 2 && !obstacles.contains { intersects(box, $0) }
    }
    /// Android `RectF.intersects`: open intervals (touching edges do not intersect).
    static func intersects(_ a: CGRect, _ b: CGRect) -> Bool { a.minX < b.maxX && b.minX < a.maxX && a.minY < b.maxY && b.minY < a.maxY }
}

/// Android `PracticeTableArt`: the shared daily-table surfaces, legs and net (Core Graphics). Practice overlays are
/// drawn by their caller. `project` maps a table point and height to the view.
final class MPPracticeTableArt {
    typealias Project = (MPPoint, Double) -> CGPoint
    private func color(_ argb: UInt32) -> CGColor { MPColor.ui(argb).cgColor }
    private func polygon(_ c: CGContext, _ project: Project, _ points: [MPPoint]) -> CGPath {
        let path = CGMutablePath()
        for (i, v) in points.enumerated() { let q = project(v, 0); if i == 0 { path.move(to: q) } else { path.addLine(to: q) } }
        path.closeSubpath(); return path
    }
    private func gradient(_ c: CGContext, _ clip: CGPath, from: CGFloat, to: CGFloat, _ a: UInt32, _ b: UInt32) {
        guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [color(a), color(b)] as CFArray, locations: [0, 1]) else { return }
        c.saveGState(); c.addPath(clip); c.clip()
        c.drawLinearGradient(g, start: CGPoint(x: 0, y: from), end: CGPoint(x: 0, y: to), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        c.restoreGState()
    }
    private func line(_ c: CGContext, _ project: Project, _ a: MPPoint, _ b: MPPoint, _ argb: UInt32, _ width: CGFloat, z: Double = 0) {
        let x = project(a, z), y = project(b, z)
        c.setStrokeColor(color(argb)); c.setLineWidth(width); c.setLineCap(.butt)
        c.move(to: x); c.addLine(to: y); c.strokePath()
    }
    /// Legs, feet and the near edge of the table top. `tw` is the table width and `drop` the floor drop in points.
    func frame(_ c: CGContext, _ project: Project, tw: CGFloat, drop: CGFloat) {
        for v in [MPPoint(0.06, 0.08), MPPoint(0.94, 0.08), MPPoint(0.06, 0.92), MPPoint(0.94, 0.92)] {
            let q = project(v, 0), w = tw * 0.018
            c.setFillColor(color(0xff163344))
            c.addPath(UIBezierPath(roundedRect: CGRect(x: q.x - w, y: q.y + 4, width: w * 2, height: max(0, drop - 4)), cornerRadius: w * 0.3).cgPath); c.fillPath()
            c.setFillColor(color(0xff6c98a4)); c.fill(CGRect(x: q.x - w, y: q.y + 4, width: w * 0.7, height: max(0, drop - 9)))
            c.setFillColor(color(0xff172f3b)); c.fillEllipse(in: CGRect(x: q.x - w * 1.5, y: q.y + drop - w * 0.4, width: w * 3, height: w * 0.8))
        }
        let l = project(MPPoint(0, 1), 0), r = project(MPPoint(1, 1), 0)
        c.setFillColor(color(0xff112d43)); c.fill(CGRect(x: l.x, y: l.y, width: r.x - l.x, height: r.y + tw * 0.027 - l.y))
    }
    /// The two table halves with their vertical gradients (`top`/`depth` of the layout, in points).
    func surface(_ c: CGContext, _ project: Project, top: CGFloat, depth: CGFloat) {
        gradient(c, polygon(c, project, [MPPoint(0, 0), MPPoint(1, 0), MPPoint(1, 0.5), MPPoint(0, 0.5)]), from: top, to: top + depth, 0xff2b6197, 0xff102f56)
        gradient(c, polygon(c, project, [MPPoint(0, 0.5), MPPoint(1, 0.5), MPPoint(1, 1), MPPoint(0, 1)]), from: top + depth * 0.5, to: top + depth, 0xff256c81, 0xff164b65)
    }
    /// Edge lines and the faint centre line.
    func lines(_ c: CGContext, _ project: Project) {
        let white: UInt32 = 0xffe9fbff
        for (a, b) in [(MPPoint(0, 0), MPPoint(1, 0)), (MPPoint(0, 0), MPPoint(0, 1)), (MPPoint(1, 0), MPPoint(1, 1)), (MPPoint(0, 1), MPPoint(1, 1))] { line(c, project, a, b, white, 4) }
        line(c, project, MPPoint(0.5, 0), MPPoint(0.5, 1), 0x66ffffff, 2)
    }
    /// Android `PongSpinArt.draw`: a blue stripe and dot that turn with the simulated spin; ordinary balls keep
    /// their original artwork.
    func spin(_ c: CGContext, x: CGFloat, y: CGFloat, r: CGFloat, flight f: MPFlight?) {
        guard let f, !(f.topSpin < 0.04 && abs(f.spin) < 0.04) else { return }
        c.saveGState(); c.translateBy(x: x, y: y); c.rotate(by: CGFloat(f.spinAngle) * (f.spin < 0 ? -1 : 1) * .pi / 180)
        c.setStrokeColor(color(0xff1870c5)); c.setLineWidth(max(1.5, r * 0.23))
        // Android drawArc(oval -0.72r…0.72r × -0.8r…0.8r, start −95°, sweep 170°).
        let arc = CGMutablePath()
        arc.addArc(center: .zero, radius: 1, startAngle: -95 * .pi / 180, endAngle: 75 * .pi / 180, clockwise: false,
                   transform: CGAffineTransform(scaleX: r * 0.72, y: r * 0.8))
        c.addPath(arc); c.strokePath()
        c.setFillColor(color(0xff1870c5)); c.fillEllipse(in: CGRect(x: -r * 0.28 - r * 0.16, y: -r * 0.4 - r * 0.16, width: r * 0.32, height: r * 0.32))
        c.restoreGState()
    }
    /// The net: 33 posts from the table to height 0.12, six strings and the top tape (heights in `project` units).
    func net(_ c: CGContext, _ project: Project) {
        for i in 0...32 {
            let x = Double(i) / 32
            line(c, project, MPPoint(x, 0.5), MPPoint(x, 0.5), 0x9affffff, 1)
            let a = project(MPPoint(x, 0.5), 0), b = project(MPPoint(x, 0.5), 0.12)
            c.setStrokeColor(color(0x99e1f7ff)); c.setLineWidth(1.4); c.move(to: a); c.addLine(to: b); c.strokePath()
        }
        for i in 0...5 { line(c, project, MPPoint(0, 0.5), MPPoint(1, 0.5), 0x99efffff, 1.4, z: Double(i) * 0.024) }
        line(c, project, MPPoint(-0.025, 0.5), MPPoint(1.025, 0.5), 0xffe9fbff, 4, z: 0.12)
    }
}
