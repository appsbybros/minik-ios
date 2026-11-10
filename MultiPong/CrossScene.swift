import SpriteKit
import UIKit

/// Android PongPlayerAtlas (MinikCrossPong 5c1aa4d, dd94c09): complete authored paddle poses, no detached limbs or synthetic legs.
/// Each character sheet (`mpx_pose_<id>`, and `mpx_pose_<id>_walk`) holds 12 frames: rows FRONT, SIDE, REAR of 4 phases. The
/// frame's foot, visible bounds and paddle centre are in frame pixels (`mpx_pose_atlas`, Android `pong-poses/atlas.json`).
/// Android a9140c3: every frame is registered to its pelvis (`hipX`) instead of the shoe touching the bottom row, and the floor
/// support of both shoes (`floorSupports`) is read from the same pixels. Android 4969038, d376d64, b0cdeb3, fcfd6b2: the traced
/// front hands and paddle of Minik, Mia, Flare and Kyra (`frontHands`), the only part of a far player drawn over the table.
final class MPXPoseAtlas {
    enum Facing: Int { case front = 0, side = 1, rear = 2 }
    struct Geometry { var bounds: CGRect; var racket: CGPoint; var radius: Double }
    private struct Frame { var source: CGRect; var visible: CGRect; var foot: CGPoint; var paddle: CGPoint; var radius: Double }
    private struct Sheet { var sheet: SKTexture; var size: CGSize; var frames: [Frame]; var heights: [Double]; var soles: [[CGPoint]] }
    static let shared = MPXPoseAtlas()
    private lazy var manifest: [String: Any] = {
        guard let data = NSDataAsset(name: "mpx_pose_atlas")?.data, let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return value
    }()
    private var characters: [String: Sheet] = [:]
    private var textures: [String: SKTexture] = [:]
    /// "amber" → `mpx_pose_amber`, "amber-walk" → `mpx_pose_amber_walk`.
    private static func asset(_ id: String) -> String { "mpx_pose_" + id.replacingOccurrences(of: "-", with: "_") }
    func has(_ id: String) -> Bool { manifest[id] != nil }
    private func character(_ id: String) -> Sheet? {
        if let known = characters[id] { return known }
        guard let data = manifest[id] as? [String: Any], let list = data["frames"] as? [[String: Any]], list.count >= 12,
              let image = UIImage(named: MPXPoseAtlas.asset(id)) else { return nil }
        func numbers(_ value: Any?) -> [Double] { (value as? [Any] ?? []).map { ($0 as? NSNumber)?.doubleValue ?? 0 } }
        let frames = list.map { f -> Frame in
            let r = numbers(f["rect"]), b = numbers(f["bounds"]), foot = numbers(f["foot"]), p = numbers(f["paddle"])
            func at(_ a: [Double], _ i: Int) -> Double { i < a.count ? a[i] : 0 }
            return Frame(source: CGRect(x: at(r, 0), y: at(r, 1), width: at(r, 2) - at(r, 0), height: at(r, 3) - at(r, 1)),
                         visible: CGRect(x: at(b, 0), y: at(b, 1), width: at(b, 2) - at(b, 0), height: at(b, 3) - at(b, 1)),
                         foot: CGPoint(x: at(foot, 0), y: at(foot, 1)), paddle: CGPoint(x: at(p, 0), y: at(p, 1)),
                         radius: (f["radius"] as? NSNumber)?.doubleValue ?? 20)
        }
        let size = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let sheet = SKTexture(image: image)
        sheet.filteringMode = .linear
        // Android a9140c3: a common pelvis anchor for every phase, not a different planted shoe for each drawing; mirroring now
        // turns about the body instead of moving it. Feet and racket stay intact in each original image. The alpha channel is
        // read once and released.
        var registered = frames
        var soles = frames.map { [$0.foot] }
        if let cg = image.cgImage, let alpha = Alpha(cg) {
            registered = frames.map { f -> Frame in
                var r = f
                r.foot.x = CGFloat(MPXPoseAtlas.hipX(alpha, f))
                return r
            }
            soles = registered.map { MPXPoseAtlas.soles(alpha, $0) }
        }
        let value = Sheet(sheet: sheet, size: size, frames: registered, heights: (0...2).map { Double(frames[$0 * 4].visible.height) }, soles: soles)
        characters[id] = value
        return value
    }
    /// The sheet's alpha channel, top row first (Android `Bitmap.getPixel` alpha).
    private struct Alpha {
        let width: Int, height: Int, values: [UInt8]
        init?(_ image: CGImage) {
            let w = image.width, h = image.height
            guard w > 0, h > 0 else { return nil }
            var rgba = [UInt8](repeating: 0, count: w * h * 4)
            let drawn: Bool = rgba.withUnsafeMutableBytes { buffer in
                guard let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
                return true
            }
            guard drawn else { return nil }
            width = w; height = h; values = stride(from: 3, to: rgba.count, by: 4).map { rgba[$0] }
        }
        func at(_ x: Int, _ y: Int) -> Int { x >= 0 && y >= 0 && x < width && y < height ? Int(values[y * width + x]) : 0 }
    }
    /// Android a9140c3 `hipX`: the median alpha-weighted centre (alpha ≥ 128) of the rows 60…68 % down the visible body, in
    /// Kotlin Float arithmetic; the authored foot when no row has an opaque pixel.
    private static func hipX(_ alpha: Alpha, _ f: Frame) -> Float {
        var centers: [Float] = []
        let top = Float(f.visible.minY), height = Float(f.visible.height)
        let first = Int(top + height * Float(0.60)), last = Int(top + height * Float(0.68))
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
    /// Android a9140c3 `floorSupports` pixels: in each column of the bottom 16 % of the visible body the lowest pixel with alpha
    /// ≥ 160; the first and last such column (frame pixels), or the registered foot when there is none.
    private static func soles(_ alpha: Alpha, _ f: Frame) -> [CGPoint] {
        var columns: [CGPoint] = []
        let top = Int(Float(f.visible.maxY) - Float(f.visible.height) * Float(0.16)), bottom = Int(Float(f.visible.maxY)) - 1
        let left = Int(Float(f.visible.minX)), right = Int(Float(f.visible.maxX))
        let sourceX = Int(f.source.minX), sourceY = Int(f.source.minY)
        if bottom >= top {
            for x in left..<max(left, right) {
                for y in stride(from: bottom, through: top, by: -1) where alpha.at(sourceX + x, sourceY + y) >= 160 {
                    columns.append(CGPoint(x: Double(x), y: Double(y)))
                    break
                }
            }
        }
        guard let first = columns.first, let last = columns.last else { return [f.foot] }
        return [first, last]
    }
    private func frame(_ id: String, _ facing: Facing, _ phase: Int) -> (Sheet, Frame)? {
        guard let c = character(id) else { return nil }
        return (c, c.frames[facing.rawValue * 4 + min(3, max(0, phase))])
    }
    /// View coordinates (y down): the drawn bounds, the paddle centre and its radius for a pose standing on `foot`.
    func geometry(_ id: String, _ facing: Facing, mirror: Bool, foot: CGPoint, height: Double, phase: Int) -> Geometry? {
        guard let pair = frame(id, facing, phase) else { return nil }
        let (c, f) = pair
        let scale = height / max(1, c.heights[facing.rawValue])
        func x(_ v: Double) -> Double { Double(foot.x) + (v - Double(f.foot.x)) * scale * (mirror ? -1 : 1) }
        func y(_ v: Double) -> Double { Double(foot.y) + (v - Double(f.foot.y)) * scale }
        let l = x(Double(f.visible.minX)), r = x(Double(f.visible.maxX))
        return Geometry(bounds: CGRect(x: min(l, r), y: y(Double(f.visible.minY)), width: abs(r - l), height: Double(f.visible.height) * scale),
                        racket: CGPoint(x: x(Double(f.paddle.x)), y: y(Double(f.paddle.y))), radius: f.radius * scale)
    }
    /// Android a9140c3 `floorSupports`: the ground support of both shoes, not just the single registration anchor (view
    /// coordinates, y down). Empty when the art is missing.
    func floorSupports(_ id: String, _ facing: Facing, mirror: Bool, foot: CGPoint, height: Double, phase: Int) -> [CGPoint] {
        guard let c = character(id) else { return [] }
        let index = facing.rawValue * 4 + min(3, max(0, phase))
        let f = c.frames[index], scale = height / max(1, c.heights[facing.rawValue])
        return c.soles[index].map {
            CGPoint(x: Double(foot.x) + (Double($0.x) - Double(f.foot.x)) * scale * (mirror ? -1 : 1), y: Double(foot.y) + (Double($0.y) - Double(f.foot.y)) * scale)
        }
    }
    /// Android `drawMinikFrontHands` / `drawMiaFrontHands` / `drawFlareFrontHands` / `drawKyraFrontHands` (4969038, d376d64, b0cdeb3,
    /// fcfd6b2): the traced hands, forearms and paddle of the FRONT pose as one path in view coordinates (y down), with the frame's
    /// registration, scale and mirror. Nil for a character without traced hands. The caller clips the same pose to it.
    func frontHands(_ id: String, mirror: Bool, foot: CGPoint, height: Double, phase: Int) -> CGPath? {
        guard let masks = MPXPoseAtlas.frontHandMasks[id], masks.count == 4, let pair = frame(id, .front, phase) else { return nil }
        let (c, f) = pair
        let scale = height / max(1, c.heights[Facing.front.rawValue]), m: Double = mirror ? -1 : 1
        let registration = CGAffineTransform(a: CGFloat(scale * m), b: 0, c: 0, d: CGFloat(scale),
                                      tx: CGFloat(Double(foot.x) - Double(f.foot.x) * scale * m), ty: CGFloat(Double(foot.y) - Double(f.foot.y) * scale))
        let path = CGMutablePath()
        for polygon in masks[min(3, max(0, phase))] where polygon.count >= 6 {
            path.move(to: CGPoint(x: polygon[0], y: polygon[1]), transform: registration)
            for i in stride(from: 2, to: polygon.count - 1, by: 2) { path.addLine(to: CGPoint(x: polygon[i], y: polygon[i + 1]), transform: registration) }
            path.closeSubpath()
        }
        return path
    }
    /// Android PongPlayerAtlas `minikFrontHands`, `miaFrontHands`, `flareFrontHands`, `kyraFrontHands`: per phase, the polygons
    /// (x, y pairs in frame pixels) of the four complete FRONT drawings.
    private static let frontHandMasks: [String: [[[Double]]]] = ["minik": minikFrontHands, "mia": miaFrontHands, "flare": flareFrontHands, "kyra": kyraFrontHands]
    private static let minikFrontHands: [[[Double]]] = [
        [[126, 211, 151, 209, 169, 221, 179, 240, 178, 256, 164, 267, 152, 275, 141, 273, 137, 267, 127, 261, 119, 245, 120, 227],
         [165, 215, 174, 203, 190, 199, 207, 203, 217, 215, 222, 232, 217, 249, 205, 260, 190, 264, 175, 259, 164, 247, 161, 232],
         [263, 208, 284, 209, 300, 220, 309, 236, 303, 250, 284, 258, 265, 255, 251, 244, 249, 226]],
        [[40, 123, 67, 119, 92, 130, 104, 151, 103, 175, 90, 190, 115, 176, 139, 181, 181, 194, 183, 220, 129, 225, 104, 214, 96, 221, 84, 220, 76, 209, 71, 192, 51, 188, 35, 175, 31, 152],
         [217, 211, 243, 213, 259, 224, 264, 240, 254, 253, 233, 256, 215, 246, 208, 229]],
        [[135, 209, 156, 208, 176, 218, 187, 230, 185, 247, 173, 260, 154, 263, 137, 254, 127, 242, 127, 224],
         [181, 224, 197, 219, 199, 205, 214, 193, 235, 191, 255, 198, 266, 215, 266, 234, 255, 250, 236, 260, 214, 257, 201, 245, 185, 245],
         [270, 204, 293, 209, 308, 221, 310, 237, 296, 245, 277, 241, 265, 230]],
        [[151, 196, 174, 199, 239, 207, 258, 215, 273, 227, 276, 240, 263, 252, 249, 253, 237, 246, 173, 240, 151, 231],
         [267, 211, 274, 191, 288, 179, 308, 175, 326, 183, 335, 198, 334, 219, 321, 235, 301, 243, 283, 238, 273, 228, 262, 234, 256, 226]]
    ]
    private static let miaFrontHands: [[[Double]]] = [
        [[126, 97, 109, 118, 96, 148, 99, 172, 112, 186, 123, 190, 133, 189, 140, 184, 151, 185, 158, 180, 166, 170, 162, 152, 146, 150, 133, 156, 131, 138, 139, 116],
         [215, 99, 230, 100, 252, 130, 279, 158, 282, 180, 266, 188, 245, 178, 227, 158, 213, 137]],
        [[159, 102, 140, 123, 128, 154, 105, 177, 96, 182, 80, 174, 58, 177, 50, 190, 54, 208, 75, 216, 96, 207, 109, 204, 142, 184, 157, 164, 173, 135],
         [236, 100, 265, 116, 285, 140, 291, 164, 278, 181, 257, 174, 247, 155, 229, 140]],
        [[130, 94, 115, 115, 120, 145, 135, 169, 157, 177, 182, 171, 196, 159, 198, 141, 185, 128, 167, 126, 152, 134, 147, 112],
         [213, 99, 233, 112, 243, 143, 260, 136, 276, 137, 281, 154, 272, 175, 249, 183, 230, 169, 215, 143]],
        [[123, 94, 107, 112, 109, 134, 140, 153, 205, 160, 243, 151, 260, 145, 275, 146, 296, 141, 307, 127, 307, 108, 295, 96, 279, 92, 265, 101, 260, 114, 242, 113, 213, 121, 165, 117, 149, 99]]
    ]
    private static let flareFrontHands: [[[Double]]] = [
        [[119, 108, 103, 129, 89, 158, 88, 183, 104, 201, 123, 208, 140, 204, 160, 203, 177, 190, 178, 170, 166, 157, 148, 157, 134, 170, 128, 169, 132, 139, 141, 118],
         [238, 108, 256, 124, 273, 151, 291, 173, 299, 195, 291, 217, 278, 215, 264, 201, 257, 179, 240, 163]],
        [[111, 115, 101, 143, 82, 147, 79, 127, 60, 119, 41, 126, 37, 145, 44, 162, 62, 168, 72, 180, 91, 176, 116, 170, 133, 150, 138, 126],
         [249, 110, 271, 120, 288, 140, 301, 168, 293, 191, 274, 207, 250, 208, 236, 196, 246, 180, 265, 172, 244, 149]],
        [[112, 108, 101, 128, 111, 155, 131, 173, 151, 179, 174, 176, 195, 169, 203, 152, 198, 137, 181, 130, 164, 134, 150, 148, 139, 143, 133, 114],
         [231, 109, 251, 120, 269, 143, 283, 175, 302, 188, 303, 207, 291, 216, 278, 202, 262, 197, 247, 169, 231, 149]],
        [[133, 111, 123, 130, 134, 151, 156, 165, 184, 170, 210, 170, 243, 168, 264, 172, 278, 167, 298, 164, 310, 151, 310, 136, 300, 123, 283, 122, 268, 133, 261, 149, 235, 148, 204, 143, 174, 132, 153, 116],
         [244, 177, 264, 176, 284, 185, 295, 202, 291, 219, 278, 224, 262, 209, 243, 199]]
    ]
    private static let kyraFrontHands: [[[Double]]] = [
        [[128, 109, 110, 128, 101, 155, 95, 180, 109, 198, 135, 201, 150, 191, 174, 194, 185, 179, 187, 159, 175, 145, 154, 145, 145, 157, 140, 146, 153, 121],
         [238, 108, 257, 120, 266, 145, 280, 172, 284, 187, 276, 204, 260, 210, 244, 199, 242, 181, 250, 169, 233, 146]],
        [[139, 110, 136, 138, 121, 156, 104, 161, 95, 154, 89, 146, 69, 146, 52, 154, 48, 175, 60, 190, 78, 194, 92, 202, 108, 192, 134, 184, 157, 170, 164, 128],
         [227, 109, 246, 120, 267, 143, 285, 168, 287, 185, 275, 202, 255, 202, 243, 192, 241, 177, 250, 165, 231, 151]],
        [[132, 104, 119, 116, 118, 139, 127, 161, 148, 174, 169, 180, 190, 176, 201, 162, 204, 143, 193, 131, 172, 126, 159, 135, 151, 120],
         [219, 110, 240, 123, 256, 150, 279, 166, 301, 178, 312, 196, 311, 212, 295, 220, 280, 207, 270, 196, 249, 186, 229, 170, 216, 143]],
        [[140, 109, 125, 120, 124, 139, 138, 154, 161, 165, 191, 175, 217, 174, 237, 168, 248, 176, 270, 177, 281, 163, 281, 144, 269, 128, 249, 124, 235, 132, 228, 146, 211, 147, 179, 137, 157, 117],
         [240, 178, 264, 178, 287, 185, 301, 202, 299, 215, 284, 218, 269, 208, 245, 201]]
    ]
    /// Places `node` (anchor at the foot) for the pose; `sk` turns view coordinates into the scene's.
    @discardableResult func place(_ node: SKSpriteNode, _ id: String, _ facing: Facing, mirror: Bool, foot: CGPoint, height: Double, phase: Int,
                                  sk: (CGPoint) -> CGPoint) -> Geometry? {
        guard let pair = frame(id, facing, phase) else { node.isHidden = true; return nil }
        let (c, f) = pair
        let key = id + "/" + String(facing.rawValue * 4 + min(3, max(0, phase)))
        let texture: SKTexture
        if let known = textures[key] { texture = known }
        else {
            let w = Double(c.size.width), h = Double(c.size.height)
            texture = SKTexture(rect: CGRect(x: Double(f.source.minX) / w, y: 1 - Double(f.source.maxY) / h,
                                             width: Double(f.source.width) / w, height: Double(f.source.height) / h), in: c.sheet)
            textures[key] = texture
        }
        let scale = height / max(1, c.heights[facing.rawValue])
        node.isHidden = false
        node.texture = texture
        // A sprite's size includes its scale: reset last frame's mirror before sizing, or the next mirror cancels out.
        node.xScale = 1
        node.size = CGSize(width: max(1, Double(f.source.width) * scale), height: max(1, Double(f.source.height) * scale))
        node.anchorPoint = CGPoint(x: Double(f.foot.x) / max(1, Double(f.source.width)), y: 1 - Double(f.foot.y) / max(1, Double(f.source.height)))
        node.xScale = mirror ? -1 : 1
        node.position = sk(foot)
        return geometry(id, facing, mirror: mirror, foot: foot, height: height, phase: phase)
    }
    /// Android BotPortrait (5c1aa4d): the first FRONT pose, cropped to its visible bounds.
    func portrait(_ id: String) -> UIImage? {
        guard let data = manifest[id] as? [String: Any], let list = data["frames"] as? [[String: Any]], let first = list.first,
              let image = UIImage(named: MPXPoseAtlas.asset(id)), let cg = image.cgImage else { return nil }
        let r = (first["rect"] as? [Any] ?? []).map { ($0 as? NSNumber)?.doubleValue ?? 0 }
        let b = (first["bounds"] as? [Any] ?? []).map { ($0 as? NSNumber)?.doubleValue ?? 0 }
        guard r.count >= 2, b.count >= 4 else { return nil }
        let crop = CGRect(x: r[0] + b[0], y: r[1] + b[1], width: b[2] - b[0], height: b[3] - b[1])
        guard let part = cg.cropping(to: crop) else { return nil }
        return UIImage(cgImage: part)
    }
}

/// Android ReceptionCamera (5375378): an eased zoom toward this player's (or another human's) return, a reversible screen
/// transform that stays fixed while a finger is down. "zoom" asks for it on this player's own returns, "follow" on another
/// human's. The pivot is fixed at (50 %, 62 %) of the view: assistance changes the magnification, never pans the court sideways.
/// Used by the classic court (`MPScene`); the cross court has its own `CrossCamera` since Android a9140c3.
struct CrossReceptionCamera {
    private(set) var amount = 0.0
    private var x = 0.0, y = 0.0
    var zoom: Double { 1 + 0.42 * amount }
    mutating func update(_ dt: Double, assist: CrossReception, local: Int, width: Double, height: Double, holding: Bool,
                         zoomOwn: Bool, follow: Bool) {
        if holding { return }
        let own = assist.receiver == local
        let allowed = (own ? zoomOwn : follow) && assist.receiver >= 0 && !UIAccessibility.isReduceMotionEnabled
        let target = allowed ? assist.strength : 0
        let k = 1 - exp(-min(0.075, max(0, dt)) * 4)
        amount += (target - amount) * k
        if amount < 0.0001 { amount = 0 }
        x = width * 0.5; y = height * 0.62
    }
    /// Base (camera-free) view point → painted view point.
    func painted(_ p: CGPoint) -> CGPoint { CGPoint(x: x + (Double(p.x) - x) * zoom, y: y + (Double(p.y) - y) * zoom) }
    /// Painted view point → base view point (touches).
    func base(_ p: CGPoint) -> CGPoint { CGPoint(x: x + (Double(p.x) - x) / zoom, y: y + (Double(p.y) - y) / zoom) }
    /// The fixed pivot (view coordinates).
    var focus: CGPoint { CGPoint(x: x, y: y) }
}

/// Android CrossCamera (a9140c3, 5375378): a reversible scene transform. The whole-court view (the default) is completely
/// stationary; the close view fits the ball and the relevant players by scaling around the fixed centre of the court area, at most
/// 1.48 times, with no tracking pan. Touches use the exact inverse; a held finger freezes it.
struct CrossCamera {
    private(set) var zoom = 1.0
    private var dx = 0.0, dy = 0.0
    mutating func reset() { zoom = 1; dx = 0; dy = 0 }
    /// `viewport` and `required` are camera-free view rectangles (y down).
    mutating func update(_ dt: Double, close: Bool, viewport: CGRect, required: CGRect, holding: Bool) {
        if holding || viewport.width <= 0 || viewport.height <= 0 { return }
        let px = Double(viewport.midX), py = Double(viewport.midY)
        func limit(_ distance: Double, _ space: Double) -> Double { distance > 0 ? space / distance : .infinity }
        let desired = close ? max(1, min(1.48,
                                         limit(px - Double(required.minX), px - Double(viewport.minX)),
                                         limit(Double(required.maxX) - px, Double(viewport.maxX) - px),
                                         limit(py - Double(required.minY), py - Double(viewport.minY)),
                                         limit(Double(required.maxY) - py, Double(viewport.maxY) - py))) : 1
        let k = 1 - exp(-min(0.1, max(0, dt)) / (desired < zoom ? 0.20 : 0.65))
        zoom += (desired - zoom) * k
        if abs(zoom - 1) < 0.0005 { zoom = 1 }
        // Translation is only the offset of scaling around this fixed pivot: with an unchanged zoom nothing can slide.
        dx = px * (1 - zoom); dy = py * (1 - zoom)
    }
    /// Base (camera-free) view point → painted view point.
    func painted(_ p: CGPoint) -> CGPoint { CGPoint(x: Double(p.x) * zoom + dx, y: Double(p.y) * zoom + dy) }
    /// Painted view point → base view point (touches).
    func base(_ p: CGPoint) -> CGPoint { CGPoint(x: (Double(p.x) - dx) / zoom, y: (Double(p.y) - dy) / zoom) }
    /// The translation of the transform (view coordinates).
    var shift: CGPoint { CGPoint(x: dx, y: dy) }
}

/// Android 3b52d51 `SunsetTerrace.drawForeground`: the foreground foliage traced in the original terrace painting, drawn again
/// over the court with the painting's exact transform (a depth pass, not a pasted image). The polygons are fractions of the
/// painting's width and height (y down); the portrait painting's when the terrace is not wider than tall, else the landscape one's.
enum MPXTerraceFoliage {
    /// The foliage of the painting drawn into `rect` (view coordinates, y down), as one path filled by the non-zero rule.
    static func path(portrait: Bool, in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        for polygon in (portrait ? MPXTerraceFoliage.portrait : MPXTerraceFoliage.landscape) where polygon.count >= 6 {
            func point(_ i: Int) -> CGPoint { CGPoint(x: Double(rect.minX) + polygon[i] * Double(rect.width), y: Double(rect.minY) + polygon[i + 1] * Double(rect.height)) }
            path.move(to: point(0))
            for i in stride(from: 2, to: polygon.count - 1, by: 2) { path.addLine(to: point(i)) }
            path.closeSubpath()
        }
        // Android Path's default WINDING fill, made explicit for the SpriteKit mask.
        return path.normalized(using: .winding)
    }
    private static let portrait: [[Double]] = [
        [0, 0.735, 0.054, 0.731, 0.028, 0.755, 0.011, 0.772, 0.081, 0.763, 0.124, 0.768, 0.062, 0.785, 0.018, 0.801, 0.08, 0.787, 0.14, 0.802, 0.065, 0.809, 0.13, 0.822, 0.153, 0.803, 0.166, 0.824, 0.189, 0.811, 0.181, 0.836, 0.218, 0.831, 0.245, 0.848, 0.204, 0.843, 0.217, 0.867, 0.177, 0.85, 0.165, 0.879, 0.246, 0.886, 0.285, 0.912, 0.232, 0.902, 0.193, 0.904, 0.249, 0.931, 0.214, 0.928, 0.279, 0.949, 0.312, 0.951, 0.262, 0.966, 0.314, 0.985, 0.311, 1, 0, 1],
        [1, 0.739, 0.962, 0.735, 0.98, 0.753, 0.949, 0.759, 0.916, 0.77, 0.978, 0.768, 0.95, 0.792, 0.92, 0.805, 0.89, 0.807, 0.92, 0.822, 0.858, 0.823, 0.814, 0.813, 0.851, 0.839, 0.9, 0.859, 0.818, 0.86, 0.857, 0.875, 0.76, 0.879, 0.813, 0.894, 0.849, 0.903, 0.757, 0.905, 0.698, 0.922, 0.754, 0.923, 0.808, 0.932, 0.764, 0.956, 0.697, 0.977, 0.738, 0.976, 0.735, 1, 1, 1]
    ]
    private static let landscape: [[Double]] = [
        [0, 0.67, 0.025, 0.66, 0.006, 0.706, 0.061, 0.737, 0.086, 0.733, 0.062, 0.762, 0.11, 0.747, 0.09, 0.791, 0.14, 0.774, 0.17, 0.738, 0.164, 0.787, 0.19, 0.77, 0.21, 0.789, 0.24, 0.76, 0.232, 0.806, 0.267, 0.831, 0.25, 0.867, 0.273, 0.91, 0.26, 0.954, 0.287, 1, 0, 1],
        [1, 0.773, 0.97, 0.743, 0.987, 0.802, 0.948, 0.828, 0.925, 0.807, 0.936, 0.866, 0.889, 0.874, 0.865, 0.86, 0.879, 0.895, 0.833, 0.883, 0.803, 0.929, 0.834, 0.937, 0.81, 0.976, 0.797, 1, 1, 1]
    ]
}

/// One rendered world for every seat (Android cross/CrossCourt.kt, MinikCrossPong 5c1aa4d, dd94c09): the shared table rotated so
/// the viewer's seat is at the bottom, with thickness, supports, mesh nets and a sunset sheen; whole authored player poses that
/// walk and swing outside the table (the local player seen from behind, holding the real paddle; far players behind the table rim
/// with only their hands and paddle over it); one large fixed whole-court view and the optional close camera (Android a9140c3);
/// the terrace's foreground foliage over the court (3b52d51); team colours and a team scoreboard; and the daily practice targets
/// and paint. Drawing, input and collision all use CrossGeometry. Android draws in view coordinates (y down);
/// here "view" points are those coordinates and `sk` turns them into SpriteKit's (y up).
final class CrossScene: SKScene {
    static let depth = 4.2
    static let near = 1.45
    static let liftMax = 0.62
    static let liftScale = 0.75
    static let ballSize = 0.042
    static let stand = 0.10
    static let seatColors: [(Double, Double, Double)] = [(183, 53, 120), (37, 112, 205), (34, 197, 94), (250, 204, 21)]
    static let ink = UIColor(red: 23 / 255, green: 62 / 255, blue: 86 / 255, alpha: 1)

    var engine: CrossEngine { didSet { if engine !== oldValue { rebuild() } } }
    /// Who advances the clock: a multi-stage match drives its current table; a practice its own engines; by default the engine.
    var step: ((Double) -> Void)?
    /// Once per frame after the clock advanced (the controller drains events here).
    var onFrame: (() -> Void)?
    var tutorialTarget: Int?
    /// The daily practice whose targets, marks and paint are drawn on the table.
    var practice: CrossPractice? { didSet { if (oldValue?.stage.skill == .serve) != (practice?.stage.skill == .serve) { layoutCourt() } } }
    var acceptsInput = true
    var names: [String] = []
    /// Kept for the room screens; remote players without a character are shown by their name tag only (5c1aa4d).
    var avatarIcons: [Int: String] = [:]
    /// The close camera (Android `fullScreen`, a9140c3): a reversible zoom toward the rally, at most 1.48 times and without pan;
    /// off (the default, Android `cross/close_camera` false), the stable large whole-court view. Switching never resizes the table.
    var fullScreen = false { didSet { if oldValue != fullScreen { scoreFeedback.clear() } } }
    /// Reception assistance and sound settings (Android `reception_assistance`, `cross_skill_journey/sound`).
    var preferences = MPPreferences()
    /// Team and practice screens: every engine event plays its cue while the court runs (Android CrossCourt.soundEffects).
    var playCue: ((CrossCue) -> Void)? { didSet { bindSounds(force: true) } }

    private var scale = 1.0, cx = 0.0, cy = 0.0
    private var tilt = 0.52
    /// Android keeps a pan in its projection; since a9140c3 it is always 0 (the court never slides).
    private var pan = 0.0, panY = 0.0
    /// Android CrossCourt `receptionCamera` (a CrossCamera since a9140c3); `camera` is SKScene's own camera node.
    private var courtCamera = CrossCamera()
    /// Android a9140c3 `updateCamera`: the last committed strike and how long ago it was seen.
    private var shotKey = "", shotAge = 10.0
    /// Android 3b52d51 `ballPresentationOffset`: the committed strike whose flight starts at the drawn paddle, and that offset.
    private var contactFlightKey = "", contactFlightOffset = CGPoint.zero
    /// Android a9140c3 `stanceSoles`: both shoes' floor supports of every standing and walking pose, per character/facing/mirror.
    private var stanceSoles: [String: [CGPoint]] = [:]
    private var notes: [Int: (text: String, at: TimeInterval)] = [:]
    private var previousTime: TimeInterval = 0
    private var hasRendered = false
    private var activeTouch: UITouch?
    private var downPoint = CGPoint.zero
    private var samples: [(time: TimeInterval, point: CGPoint)] = []
    private var lastTapAt: TimeInterval = -1000, lastTapPoint = CGPoint.zero, raisedTap = false
    /// Android 971e958: the second tap of a double tap counts within the system's double-tap timeout (Android
    /// `ViewConfiguration.getDoubleTapTimeout()`, 300 ms; iOS exposes no such value).
    static let doubleTapTimeout = 0.300
    /// Android fcfd6b2 `standardGesture`: on a Starter/Standard court away from the own serve (not a raised ball, not a learning
    /// court), a finger first tells a tap from footwork. A finger that never moves 12 points is one tap: a return from the current
    /// stance at finger-up, aimed at the court it lifted on (d0bed3b). A drag walks the player sideways, or, once the incoming
    /// ball is reachable (`canAimReturn`), aims the bound return from where aiming began.
    private var standardGesture = false, standardDragged = false, standardAiming = false, standardStarted = false
    private var standardAnchor = MPPoint.zero, standardWidth = 1.0, aimStartX = 0.0
    /// Android 6fcb446/971e958 `practiceDrag`: on a learning court a drag that starts on the visible local body (not on a raised
    /// ball) walks that player, whatever table area its head overlaps.
    private var practiceDrag = false
    private var walkDistance: [Int: Double] = [:], lastLateral: [Int: Double] = [:], lastStep: [Int: TimeInterval] = [:]
    private var walkFrame: [Int: Int] = [:], walkFrameAt: [Int: TimeInterval] = [:]
    private var bodyBounds: [Int: CGRect] = [:]
    private var contactRackets: [Int: CGPoint] = [:]
    private var soundEngine: CrossEngine?
    private var soundPolicy = CrossSoundPolicy(localSeat: nil)
    private var running = false
    private let canvas = SKNode()
    private let hud = SKNode()
    private let castShadow = SKShapeNode(), supports = SKNode(), tableUnder = SKShapeNode(), tableRim = SKShapeNode(), tableFill = SKShapeNode()
    private let sheenCrop = SKCropNode(), sheenMask = SKShapeNode(), sheen = SKSpriteNode()
    private let centreLines = SKShapeNode(), tableEdge = SKShapeNode(), highlightNode = SKShapeNode(), bounceNode = SKShapeNode()
    private var territoryNodes: [SKShapeNode] = []
    private var territoryPaths: [CGPath] = []
    private var tablePath: CGPath = CGMutablePath()
    /// Android 80fc74e `tableBodyMask`: the table with its visible 5 pt rim, which hides a far (FRONT) player's body.
    private var tableBodyMask: CGPath = CGMutablePath()
    private var outsidePath: CGPath = CGMutablePath()
    private let practiceCrop = SKCropNode(), practiceMask = SKShapeNode(), practiceNode = SKNode()
    private let netsNode = SKNode()
    private var actors: [Int: CrossActorNodes] = [:]
    private let ballShadow = SKShapeNode(circleOfRadius: 1), ballNode = SKShapeNode(circleOfRadius: 1), ballShine = SKShapeNode(circleOfRadius: 1)
    private let netFlash = SKShapeNode(circleOfRadius: 1)
    private let paddleNode = SKNode()
    private let arrowNode = SKShapeNode()
    private var tags: [Int: CrossTagNodes] = [:]
    private var boards: [Int: CrossBoardNodes] = [:]
    private static let font = "HelveticaNeue-Bold"
    private var width: Double { Double(size.width) }
    private var height: Double { Double(size.height) }
    /// Android 7254ab2: serving practice shows neither the match scoreboard nor the score beside each name.
    private var showsScores: Bool { practice?.stage.skill != .serve }
    private var scoreboardHeight: Double { !showsScores ? 0 : (width > height ? 48 : 66) }
    private let scoreFeedback = CrossScoreFeedback()
    /// Android 3b52d51 `SunsetTerrace.foreground`: the terrace painting's foreground foliage, drawn over the court (not zoomed).
    private let foliageCrop = SKCropNode(), foliageMask = SKShapeNode(), foliage = SKSpriteNode()
    private var foliageFrame = CGRect.null, foliageWindow = CGSize.zero

    init(engine: CrossEngine) {
        self.engine = engine
        super.init(size: CGSize(width: 430, height: 760))
        scaleMode = .resizeFill
        backgroundColor = .clear
        canvas.zPosition = 0; hud.zPosition = 20
        addChild(canvas); addChild(hud)
        castShadow.fillColor = UIColor(red: 8 / 255, green: 20 / 255, blue: 32 / 255, alpha: 70 / 255); castShadow.strokeColor = .clear; castShadow.zPosition = 0.2
        supports.zPosition = 0.3
        tableUnder.fillColor = UIColor(red: 20 / 255, green: 42 / 255, blue: 59 / 255, alpha: 1); tableUnder.strokeColor = .clear; tableUnder.zPosition = 0.4
        tableRim.strokeColor = UIColor(red: 119 / 255, green: 173 / 255, blue: 192 / 255, alpha: 1); tableRim.lineWidth = 5; tableRim.lineJoin = .round
        tableRim.fillColor = .clear; tableRim.zPosition = 0.5
        tableFill.fillColor = .white; tableFill.strokeColor = .clear; tableFill.zPosition = 0.6
        tableFill.fillTexture = CrossScene.gradient([(20, 104, 126), (44, 179, 192), (16, 108, 141)], vertical: true)
        sheenMask.fillColor = .white; sheenMask.strokeColor = .clear; sheenCrop.maskNode = sheenMask; sheenCrop.zPosition = 0.7
        sheen.texture = CrossScene.sheenTexture(); sheenCrop.addChild(sheen)
        centreLines.strokeColor = UIColor(white: 1, alpha: 210 / 255); centreLines.lineWidth = 1.6; centreLines.zPosition = 1.3
        tableEdge.strokeColor = UIColor(white: 1, alpha: 210 / 255); tableEdge.lineWidth = 2.6; tableEdge.fillColor = .clear; tableEdge.lineJoin = .round; tableEdge.zPosition = 1.4
        highlightNode.strokeColor = UIColor(red: 1, green: 221 / 255, blue: 87 / 255, alpha: 235 / 255); highlightNode.lineWidth = 3.4; highlightNode.fillColor = .clear
        highlightNode.lineJoin = .round; highlightNode.zPosition = 1.5
        bounceNode.fillColor = .clear; bounceNode.strokeColor = .white; bounceNode.lineWidth = 2; bounceNode.zPosition = 1.6
        practiceMask.fillColor = .white; practiceMask.strokeColor = .clear; practiceCrop.maskNode = practiceMask; practiceCrop.zPosition = 1.7
        practiceCrop.addChild(practiceNode)
        netsNode.zPosition = 4
        ballShadow.fillColor = UIColor(red: 10 / 255, green: 34 / 255, blue: 45 / 255, alpha: 1); ballShadow.strokeColor = .clear; ballShadow.zPosition = 4.8
        netFlash.fillColor = .clear; netFlash.strokeColor = UIColor(red: 1, green: 84 / 255, blue: 84 / 255, alpha: 1); netFlash.zPosition = 5.1
        ballNode.fillColor = UIColor(red: 245 / 255, green: 248 / 255, blue: 251 / 255, alpha: 1)
        ballNode.strokeColor = UIColor(red: 171 / 255, green: 186 / 255, blue: 200 / 255, alpha: 1); ballNode.zPosition = 5
        ballShine.fillColor = .white; ballShine.strokeColor = .clear; ballShine.zPosition = 5.05
        paddleNode.zPosition = 6
        // Android draws the edge arrow inside the camera transform, after the ball and the paddle.
        arrowNode.fillColor = UIColor(white: 1, alpha: 230 / 255); arrowNode.strokeColor = .clear; arrowNode.zPosition = 7
        let arrow = CGMutablePath()
        arrow.move(to: CGPoint(x: 10, y: 0)); arrow.addLine(to: CGPoint(x: -6, y: -7)); arrow.addLine(to: CGPoint(x: -6, y: 7)); arrow.closeSubpath()
        arrowNode.path = arrow
        for node in [castShadow, tableUnder, tableRim, tableFill] { canvas.addChild(node) }
        canvas.addChild(supports); canvas.addChild(sheenCrop)
        for node in [centreLines, tableEdge, highlightNode, bounceNode] { canvas.addChild(node) }
        canvas.addChild(practiceCrop)
        canvas.addChild(netsNode)
        for node in [ballShadow, ballNode, ballShine, netFlash] { canvas.addChild(node) }
        canvas.addChild(paddleNode)
        canvas.addChild(arrowNode)
        // Android 3b52d51: the foliage pass is drawn after the camera's content, before the tags and the scoreboard.
        foliageMask.fillColor = .white; foliageMask.strokeColor = .clear; foliageMask.lineWidth = 0
        foliageCrop.maskNode = foliageMask; foliageCrop.addChild(foliage); foliageCrop.zPosition = 10; foliageCrop.isHidden = true
        addChild(foliageCrop)
        buildPaddle()
        rebuild()
    }
    required init?(coder: NSCoder) { return nil }
    override func didMove(to view: SKView) { view.isMultipleTouchEnabled = false; layoutCourt() }
    override func didChangeSize(_ oldSize: CGSize) { layoutCourt() }
    /// Starts or stops the frame loop (Android resumeFrames/stopFrames); pausing play itself is the controller's job.
    func setActive(_ active: Bool) {
        running = active; isPaused = !active; previousTime = 0
        if !active { cancelTouch() }
        bindSounds(force: false)
    }
    /// Android `toggleCamera`: the close camera or the whole court; the owner remembers it (`cross/close_camera`).
    func toggleCamera() { fullScreen.toggle() }

    private var g: CrossGeometry { engine.geometry }
    private var viewSeat: Int { engine.localSeat ?? 0 }

    // ---- projection -------------------------------------------------------------------------------
    private func k(_ y: Double) -> Double { CrossScene.depth / (CrossScene.depth + (CrossScene.near - y)) }
    /// Concave display height: low balls separate clearly from the net band, high lobs stay on screen. Android 5375378: a
    /// height below the table plane continues the curve's slope at 0 linearly.
    private func lift(_ h: Double) -> Double {
        h < 0 ? h * CrossScene.liftMax / CrossScene.liftScale : CrossScene.liftMax * (1 - exp(-h / CrossScene.liftScale))
    }
    /// Android `screen`: view coordinates (y down) including the camera pan (always 0), not the close camera's zoom.
    func screen(_ p: MPPoint, _ h: Double = 0) -> CGPoint {
        let q = unpanned(p, h)
        return CGPoint(x: Double(q.x) - pan, y: Double(q.y) - panY)
    }
    /// The same point without the pan, for nodes inside the panned canvas.
    private func unpanned(_ p: MPPoint, _ h: Double = 0) -> CGPoint {
        let v = g.toView(viewSeat, p), kk = k(v.y)
        return CGPoint(x: cx + v.x * scale * kk, y: cy + (v.y * tilt - lift(h)) * scale * kk)
    }
    /// View coordinates (y down) → SpriteKit (y up).
    private func sk(_ q: CGPoint) -> CGPoint { CGPoint(x: q.x, y: size.height - q.y) }
    private func sizeAt(_ p: MPPoint) -> Double { scale * k(g.toView(viewSeat, p).y) }
    /// Inverse of `screen` for points on the table plane (height 0).
    func world(_ sx: Double, _ sy: Double) -> MPPoint {
        let yy = (sy + panY - cy) / (scale * tilt)
        let y = yy * (CrossScene.depth + CrossScene.near) / (CrossScene.depth + yy)
        return g.fromView(viewSeat, MPPoint((sx + pan - cx) / (scale * k(y)), y))
    }

    /// Android a9140c3/0285385 `layoutFor`: one large fixed projection for both camera views. The fit holds the table arms and every
    /// player's grounded rest and contact poses at the middle of their reach (the same feet, anchors and heights as renderPlayer,
    /// at scale 1), with an 8 pt margin and 99 % of the fit. The close camera only adds a reversible zoom; it never resizes the table.
    func layoutCourt() {
        let w = width, h = height
        guard w > 1, h > 1 else { return }
        contactFlightKey = ""; contactFlightOffset = .zero
        tilt = w > h ? 0.52 : 1.72
        courtCamera.reset()
        var minX = 0.0, maxX = 0.0, minY = 0.0, maxY = 0.0
        let geometry = g, seat = viewSeat, t = tilt
        func include(_ p: MPPoint, up: Double = 0, down: Double = 0, half: Double = 0) {
            let v = geometry.toView(seat, p), kk = k(v.y)
            minX = min(minX, (v.x - half) * kk); maxX = max(maxX, (v.x + half) * kk)
            minY = min(minY, (v.y * t - up) * kk); maxY = max(maxY, (v.y * t + down) * kk)
        }
        for s in geometry.seats { geometry.armCorners(s).forEach { include($0) } }
        func unit(_ p: MPPoint, _ height: Double) -> CGPoint {
            let v = geometry.toView(seat, p), kk = k(v.y)
            return CGPoint(x: v.x * kk, y: (v.y * t - lift(height)) * kk)
        }
        let atlas = MPXPoseAtlas.shared
        for s in geometry.seats where s < engine.seats.count {
            let info = engine.seats[s]
            let botCharacter = info.bot?.characterId ?? ""
            let id = botCharacter.isEmpty ? info.characterId : botCharacter
            guard !id.isEmpty, atlas.has(id) else { continue }
            let view = geometry.toView(seat, geometry.home(s))
            let facing: MPXPoseAtlas.Facing = view.y > 0.45 ? .rear : (view.y < -0.45 ? .front : .side)
            let mirror = view.x > 0.45, actorHeight = id == "minik" ? 0.76 : 0.84
            let contactPose = 2
            // Android a9140c3: the middle of the reach only (u = 0), the rest and the contact pose.
            guard let foot = playerFoot(id, facing, mirror: mirror, seat: s, u: 0, unitScale: 1, project: unit) else { continue }
            for pose in [0, contactPose] {
                guard let bounds = atlas.geometry(id, facing, mirror: mirror, foot: foot, height: actorHeight, phase: pose)?.bounds else { continue }
                minX = min(minX, Double(bounds.minX)); maxX = max(maxX, Double(bounds.maxX))
                minY = min(minY, Double(bounds.minY)); maxY = max(maxY, Double(bounds.maxY))
            }
        }
        let margin = 8.0, board = scoreboardHeight + 16
        scale = max(1, min((w - 2 * margin) / max(0.01, maxX - minX), (h - board - 2 * margin) / max(0.01, maxY - minY)) * 0.99)
        pan = 0; panY = 0
        cx = w / 2 - (minX + maxX) * scale / 2
        cy = board + (h - board - (maxY - minY) * scale) * 0.5 - minY * scale
        buildPaths()
        render()
    }
    /// Android a9140c3 `playerFoot`: the authored contact pose's racket defines where the feet stand at the rest depth; the paddle
    /// depth never moves a body onto the table. A side player stands on the floor just beyond its arm's edge (reach + 0.05) with
    /// BOTH shoes outside the enlarged arm (the innermost floor support of every standing and walking pose), not one shoe at its
    /// edge while the other leg and hip stay inside the table. `project` is `unpanned` (or the layout's unit projection).
    private func playerFoot(_ id: String, _ facing: MPXPoseAtlas.Facing, mirror: Bool, seat: Int, u: Double, unitScale: Double,
                            project: (MPPoint, Double) -> CGPoint) -> CGPoint? {
        let atlas = MPXPoseAtlas.shared
        let actorHeight = unitScale * (id == "minik" ? 0.76 : 0.84)
        let contactPose = 2
        guard let contact = atlas.geometry(id, facing, mirror: mirror, foot: .zero, height: actorHeight, phase: contactPose) else { return nil }
        let rest = project(g.fromLocal(seat, u, CrossGeometry.homeDepth), 0.15)
        var foot = CGPoint(x: rest.x - contact.racket.x, y: rest.y - contact.racket.y)
        let view = g.toView(viewSeat, g.home(seat))
        if seat != viewSeat && abs(view.x) > 0.45 {
            let floor = project(g.fromLocal(seat, u, CrossGeometry.reach + 0.05), 0)
            let key = id + "/" + String(facing.rawValue) + "/" + String(mirror)
            let offsets: [CGPoint]
            if let known = stanceSoles[key] { offsets = known }
            else {
                var found: [CGPoint] = []
                for art in [id, id + "-walk"] {
                    for phase in 0...3 { found += atlas.floorSupports(art, facing, mirror: mirror, foot: .zero, height: 1, phase: phase) }
                }
                stanceSoles[key] = found
                offsets = found
            }
            let xs = offsets.map { Double($0.x) }
            let inward = (view.x > 0 ? xs.min() : xs.max()) ?? 0
            foot.x = CGFloat(Double(floor.x) - inward * actorHeight)
            foot.y = CGFloat(Double(floor.y) + unitScale * k(view.y) * 0.32)
        }
        return foot
    }
    /// Per-seat nodes for the current table (a new stage may have fewer seats).
    private func rebuild() {
        cancelTouch()
        actors.values.forEach { $0.remove() }
        tags.values.forEach { $0.remove() }
        boards.values.forEach { $0.remove() }
        actors = [:]; tags = [:]; boards = [:]
        for s in g.seats {
            actors[s] = CrossActorNodes(parent: canvas)
            tags[s] = CrossTagNodes(parent: hud, font: CrossScene.font)
            boards[s] = CrossBoardNodes(parent: hud, font: CrossScene.font)
        }
        notes = [:]; walkDistance = [:]; lastLateral = [:]; lastStep = [:]; walkFrame = [:]; walkFrameAt = [:]
        scoreFeedback.clear()
        bindSounds(force: false)
        layoutCourt()
    }
    private func buildPaths() {
        // Paths are built camera-free inside the canvas, which the pan and the reception zoom move.
        var table: CGPath?
        for s in g.seats {
            let corners = g.armCorners(s).map { sk(unpanned($0)) }
            let arm = CGMutablePath()
            arm.addLines(between: corners); arm.closeSubpath()
            table = table.map { $0.union(arm) } ?? arm
        }
        if g.hub > 0 {
            let hub = CGMutablePath()
            for i in 0...72 {
                let a = Double(i) * 2 * Double.pi / 72
                let q = sk(unpanned(MPPoint(sin(a) * g.hub, cos(a) * g.hub)))
                if i == 0 { hub.move(to: q) } else { hub.addLine(to: q) }
            }
            hub.closeSubpath()
            table = table.map { $0.union(hub) } ?? hub
        }
        let shape: CGPath = table ?? CGMutablePath()
        tablePath = shape
        // Android 80fc74e: the visible rim (the 5 pt round-joined stroke) extends outside the playing surface. Bodies behind it are
        // hidden there too; their hands are restored separately.
        tableBodyMask = shape.union(shape.copy(strokingWithWidth: 5, lineCap: .butt, lineJoin: .round, miterLimit: 4))
        // Cast shadow and support legs are behind the extruded table, never collision surfaces.
        castShadow.path = shape; castShadow.position = CGPoint(x: 8, y: -scale * 0.27)
        tableUnder.path = shape; tableUnder.position = CGPoint(x: 0, y: -8)
        tableRim.path = shape; tableFill.path = shape; tableEdge.path = shape
        sheenMask.path = shape
        practiceMask.path = shape
        let box = shape.boundingBoxOfPath
        sheen.size = CGSize(width: max(1, 2 * scale), height: max(1, box.height + 40))
        sheen.position = CGPoint(x: cx, y: box.midY)
        supports.removeAllChildren()
        for seat in g.seats {
            for u in [-0.38, 0.38] {
                let foot = sk(unpanned(g.fromLocal(seat, u, CrossGeometry.reach - 0.12)))
                let leg = sizeAt(g.home(seat)) * 0.32
                let post = SKShapeNode(rect: CGRect(x: Double(foot.x) - 3, y: Double(foot.y) - leg, width: 8, height: leg), cornerRadius: 2)
                post.fillColor = UIColor(red: 70 / 255, green: 88 / 255, blue: 101 / 255, alpha: 1); post.strokeColor = .clear
                supports.addChild(post)
                let base = SKShapeNode(ellipseIn: CGRect(x: Double(foot.x) - 6, y: Double(foot.y) - leg - 3, width: 14, height: 5))
                base.fillColor = UIColor(red: 14 / 255, green: 23 / 255, blue: 36 / 255, alpha: 1); base.strokeColor = .clear
                supports.addChild(base)
            }
        }
        territoryNodes.forEach { $0.removeFromParent() }
        territoryNodes = []; territoryPaths = []
        for s in g.seats {
            let wedge = CGMutablePath()
            wedge.move(to: sk(unpanned(MPPoint(0, 0))))
            let from = g.angle(s) - g.sector / 2
            for i in 0...24 {
                let a = from + g.sector * Double(i) / 24
                wedge.addLine(to: sk(unpanned(MPPoint(sin(a), cos(a)) * 3.0)))
            }
            wedge.closeSubpath()
            let clipped = wedge.intersection(shape)
            territoryPaths.append(clipped)
            let node = SKShapeNode(path: clipped)
            let c = CrossScene.seatColors[colorIndex(s) % CrossScene.seatColors.count]
            node.fillColor = UIColor(red: CGFloat(c.0 / 255), green: CGFloat(c.1 / 255), blue: CGFloat(c.2 / 255), alpha: CGFloat(s == viewSeat ? 14.0 / 255 : 24.0 / 255))
            node.strokeColor = .clear; node.lineWidth = 0; node.zPosition = 1.2
            canvas.addChild(node); territoryNodes.append(node)
        }
        // Centre lines along each arm, like the classic table markings.
        let lines = CGMutablePath()
        for s in g.seats {
            lines.move(to: sk(unpanned(g.fromLocal(s, 0, max(g.netLength, 0.62)))))
            lines.addLine(to: sk(unpanned(g.fromLocal(s, 0, CrossGeometry.reach))))
        }
        centreLines.path = lines
        // Bodies are drawn outside the table (Android clipOutPath); a far (FRONT) body outside the table and its rim (80fc74e). The
        // floor shadow is clipped by the table alone.
        let everything = CGPath(rect: CGRect(x: -3 * width, y: -height, width: 7 * width, height: 3 * height), transform: nil)
        outsidePath = everything.subtracting(shape)
        let outsideBody = everything.subtracting(tableBodyMask)
        for (seat, nodes) in actors {
            let front = g.toView(viewSeat, g.home(seat)).y < -0.45
            nodes.setMasks(body: front ? outsideBody : outsidePath, shadow: outsidePath)
        }
        buildNets()
    }
    private func buildNets() {
        netsNode.removeAllChildren()
        let netHeight = engine.physics.netHeight
        let meshColor = UIColor(red: 117 / 255, green: 205 / 255, blue: 217 / 255, alpha: 210 / 255)
        for net in g.nets {
            let steps = 20
            let base = (0...steps).map { sk(unpanned(net.end * (Double($0) / Double(steps)))) }
            let top = (0...steps).map { sk(unpanned(net.end * (Double($0) / Double(steps)), netHeight)) }
            let band = CGMutablePath()
            band.addLines(between: base + top.reversed()); band.closeSubpath()
            let fill = SKShapeNode(path: band)
            fill.fillColor = UIColor(red: 13 / 255, green: 43 / 255, blue: 64 / 255, alpha: 185 / 255); fill.strokeColor = .clear; fill.zPosition = 0
            netsNode.addChild(fill)
            let mesh = CGMutablePath()
            for i in 1..<steps { mesh.move(to: base[i]); mesh.addLine(to: top[i]) }
            for row in 1...4 {
                let line = (0...steps).map { sk(unpanned(net.end * (Double($0) / Double(steps)), netHeight * Double(row) / 5)) }
                mesh.addLines(between: line)
            }
            let meshNode = SKShapeNode(path: mesh)
            meshNode.strokeColor = meshColor; meshNode.lineWidth = 0.65; meshNode.zPosition = 0.1
            netsNode.addChild(meshNode)
            let tape = CGMutablePath()
            tape.move(to: top[0]); tape.addLine(to: top[steps])
            let tapeNode = SKShapeNode(path: tape)
            tapeNode.strokeColor = .white; tapeNode.lineWidth = 2.4; tapeNode.zPosition = 0.2
            netsNode.addChild(tapeNode)
            // Posts at the table edge.
            let post = CGMutablePath()
            post.move(to: base[steps]); post.addLine(to: CGPoint(x: top[steps].x, y: top[steps].y + 2))
            let postNode = SKShapeNode(path: post)
            postNode.strokeColor = UIColor(red: 30 / 255, green: 80 / 255, blue: 150 / 255, alpha: 1); postNode.lineWidth = 3.2; postNode.zPosition = 0.3
            netsNode.addChild(postNode)
        }
        if g.players == 2 { return }
        let c0 = sk(unpanned(MPPoint(0, 0))), c1 = sk(unpanned(MPPoint(0, 0), netHeight))
        let centre = CGMutablePath()
        centre.move(to: c0); centre.addLine(to: CGPoint(x: c1.x, y: c1.y + 2))
        let centreNode = SKShapeNode(path: centre)
        centreNode.strokeColor = UIColor(red: 30 / 255, green: 80 / 255, blue: 150 / 255, alpha: 1); centreNode.lineWidth = 4; centreNode.zPosition = 0.4
        netsNode.addChild(centreNode)
        let cap = SKShapeNode(circleOfRadius: 3.2)
        cap.fillColor = UIColor(red: 250 / 255, green: 214 / 255, blue: 90 / 255, alpha: 1); cap.strokeColor = .clear
        cap.position = CGPoint(x: c1.x, y: c1.y + 2); cap.zPosition = 0.5
        netsNode.addChild(cap)
    }
    /// Team colour index of a seat (Android `teams?.seats?.get(s) ?: s`).
    private func colorIndex(_ seat: Int) -> Int {
        if let teams = engine.teams, seat >= 0, seat < teams.seats.count { return teams.seats[seat] }
        return seat
    }

    // ---- frame loop ---------------------------------------------------------------------------------
    override func update(_ currentTime: TimeInterval) {
        bindSounds(force: false)
        let cameraElapsed = previousTime == 0 ? 0 : min(0.1, max(0, currentTime - previousTime))
        let elapsed = previousTime == 0 || !hasRendered ? 0 : min(0.10, max(0, currentTime - previousTime))
        previousTime = currentTime
        if !engine.networked {
            engine.reception.enabled = true
            if let local = engine.localSeat { engine.reception.slow[local] = preferences.receptionSlow }
        }
        // Keep real-time pace under rendering load; physics still receives small steps.
        var remaining = elapsed
        while remaining > 1e-9 {
            let slice = min(remaining, 1.0 / 60)
            if let step { step(slice) } else { engine.advance(slice) }
            remaining -= slice
        }
        updateCamera(cameraElapsed)
        onFrame?()
        render()
    }
    /// Android a9140c3/5375378 `updateCamera`: the close camera keeps the ball and the relevant players in view — every player
    /// while a point starts, a hitter prepares or for 0.42 s after a strike, then the predicted receiver (and the hitter until
    /// 0.70 s) — inside the court area below the scoreboard. Bodies count down to 79 % of their height. Frozen while a finger is
    /// down so a drag keeps its coordinates. Uses the previous frame's bodies and rackets, as Android does.
    private func updateCamera(_ dt: Double) {
        guard width > 1, height > 1 else { return }
        let key = engine.lastCommittedStrike.map { "\($0.rallyId)/\($0.hitIndex)/\($0.seat)" } ?? ""
        if key != shotKey { shotKey = key; shotAge = 0 } else { shotAge += dt }
        let ball = renderedBallPoint()
        var required = CGRect(x: Double(ball.x) - 16, y: Double(ball.y) - 16, width: 32, height: 32)
        let starting = engine.referee.phase == .awaitingServe || engine.referee.phase == .resolved
        // See the hitter prepare and release before following the reception.
        let preparing = g.seats.contains { let s = engine.stroke($0); return s.active && !s.contacted }
        let visible: [Int]
        if starting || preparing || shotAge < 0.42 { visible = Array(g.seats) }
        else { visible = [engine.predictedReceiver, shotAge < 0.70 ? engine.lastCommittedStrike?.seat : nil].compactMap { $0 } }
        for seat in visible {
            if let r = bodyBounds[seat] {
                required = CrossScene.union(required, CGRect(x: Double(r.minX) - 8, y: Double(r.minY) - 10, width: Double(r.width) + 16, height: Double(r.height) * 0.79 + 10))
            }
            if let c = contactRackets[seat] { required = CrossScene.union(required, CGRect(x: Double(c.x) - 16, y: Double(c.y) - 16, width: 32, height: 32)) }
        }
        let viewport = CGRect(x: 8, y: scoreboardHeight + 8, width: max(0, width - 16), height: max(0, height - scoreboardHeight - 16))
        courtCamera.update(dt, close: fullScreen, viewport: viewport, required: required, holding: activeTouch != nil)
    }
    /// Android RectF.union: an empty rectangle adds nothing.
    private static func union(_ a: CGRect, _ b: CGRect) -> CGRect {
        if b.width <= 0 || b.height <= 0 { return a }
        if a.width <= 0 || a.height <= 0 { return b }
        return a.union(b)
    }

    // ---- sounds -------------------------------------------------------------------------------------
    private func bindSounds(force: Bool) {
        guard playCue != nil else {
            if soundEngine != nil { soundEngine?.onEvent = nil; soundEngine = nil }
            return
        }
        if force || soundEngine !== engine {
            soundEngine?.onEvent = nil
            soundEngine = engine
            let policy = CrossSoundPolicy(localSeat: engine.localSeat)
            soundPolicy = policy
            engine.onEvent = { [weak self] event in
                guard let self, self.running, self.preferences.journeySound, let play = self.playCue else { return }
                for cue in policy.cues(event) { play(cue) }
            }
        }
    }

    // ---- drawing --------------------------------------------------------------------------------------
    private func render() {
        guard size.width > 1, size.height > 1 else { return }
        hasRendered = true
        // The pan (always 0), then the close camera's zoom about its fixed pivot (Android CrossCamera.begin): a base view point p is
        // painted at p × zoom + shift.
        let z = courtCamera.zoom, shift = courtCamera.shift
        canvas.setScale(CGFloat(z))
        canvas.position = CGPoint(x: Double(shift.x) - pan * z, y: height * (1 - z) - Double(shift.y) + panY * z)
        bodyBounds = [:]; contactRackets = [:]
        let receiver = tutorialTarget ?? engine.predictedReceiver
        if let receiver, receiver >= 0, receiver < territoryPaths.count {
            highlightNode.isHidden = false; highlightNode.path = territoryPaths[receiver]
        } else { highlightNode.isHidden = true }
        if let bounce = engine.bouncePoint, engine.bounceAge < 0.38 {
            let q = sk(unpanned(bounce)), r = sizeAt(bounce) * (0.04 + engine.bounceAge * 0.10)
            bounceNode.isHidden = false
            bounceNode.path = CGPath(ellipseIn: CGRect(x: q.x - CGFloat(r), y: q.y - CGFloat(r), width: CGFloat(2 * r), height: CGFloat(2 * r)), transform: nil)
            bounceNode.alpha = CGFloat(1 - engine.bounceAge / 0.38) * 220 / 255
        } else { bounceNode.isHidden = true }
        renderPractice()
        let ballDepth: Double
        if engine.postPointBall {
            // Android 5375378: live contact uses the traced racket anchors; after a point the freely bouncing ball is depth-sorted
            // with the bodies (nets first, then the players back to front, the ball before the first player nearer than it), so it
            // cannot be pasted onto a tail.
            netsNode.zPosition = 1.9
            func depthOf(_ seat: Int) -> Double { g.toView(viewSeat, g.home(seat)).y }
            let ball = g.toView(viewSeat, engine.renderBallPosition).y
            var drawn: Double?
            for (order, seat) in g.seats.sorted(by: { depthOf($0) < depthOf($1) || (depthOf($0) == depthOf($1) && $0 < $1) }).enumerated() {
                let depth = 2 + Double(order) * 0.1
                if drawn == nil && ball < depthOf(seat) { drawn = depth - 0.05 }
                renderPlayer(seat, depth: depth)
            }
            ballDepth = drawn ?? (2 + Double(engine.players) * 0.1)
        } else {
            netsNode.zPosition = 4
            // Back-to-front: farther players first, so nearer bodies overlap correctly; the local player last. A spectator (the
            // friendly host watching a house final) sees the nearest seat's player there too (Android 1fc4bc2 `drawLocalAvatar`).
            let others = g.seats.filter { $0 != viewSeat }.sorted { screen(g.home($0)).y < screen(g.home($1)).y }
            for (order, seat) in others.enumerated() { renderPlayer(seat, depth: 2 + Double(order) * 0.1) }
            renderPlayer(viewSeat, depth: 3)
            ballDepth = 4.8
        }
        renderBall(depth: ballDepth)
        renderPaddle()
        renderForeground()
        renderTags()
        if showsScores {
            if let last = engine.referee.lastOutcome { scoreFeedback.record(last, now: CACurrentMediaTime()) }
            renderScoreboard()
        } else { boards.values.forEach { $0.hide() } }
    }
    /// Android drawPractice: paint cells, landed marks, the shape outline and its numbered circles, the golden targets.
    private var practiceSignature = ""
    private func renderPractice() {
        guard let p = practice else {
            if !practiceSignature.isEmpty { practiceNode.removeAllChildren(); practiceSignature = "" }
            return
        }
        // Rebuilt only when something drawn changes (the canvas transform moves it otherwise).
        let signature = "\(p.stage.id)|\(scale)|\(cx)|\(cy)|\(tilt)|\(p.paint.owners.hashValue)|\(p.marks.count)|\(p.painted.count)|\(p.attempts)|\(viewSeat)"
        if signature == practiceSignature { return }
        practiceSignature = signature
        practiceNode.removeAllChildren()
        func patch(_ at: MPPoint, _ radius: Double, _ color: UIColor) {
            let path = CGMutablePath()
            for i in 0...32 {
                let angle = Double(i) * 2 * Double.pi / 32
                let v = sk(unpanned(at + MPPoint(cos(angle) * radius, sin(angle) * radius)))
                if i == 0 { path.move(to: v) } else { path.addLine(to: v) }
            }
            path.closeSubpath()
            let node = SKShapeNode(path: path)
            node.fillColor = color; node.strokeColor = .clear
            practiceNode.addChild(node)
        }
        func argb(_ value: UInt32) -> UIColor {
            UIColor(red: CGFloat((value >> 16) & 0xff) / 255, green: CGFloat((value >> 8) & 0xff) / 255, blue: CGFloat(value & 0xff) / 255, alpha: CGFloat(value >> 24) / 255)
        }
        if p.stage.skill == .paint {
            let grid = p.paint, half = grid.span / Double(grid.size) / 2
            let ours = CGMutablePath(), theirs = CGMutablePath()
            for (i, owner) in grid.owners.enumerated() where owner >= 0 {
                let at = grid.point(i)
                let corners = [MPPoint(-half, -half), MPPoint(half, -half), MPPoint(half, half), MPPoint(-half, half)].map { sk(unpanned(at + $0)) }
                let target = owner == 0 ? ours : theirs
                target.addLines(between: corners); target.closeSubpath()
            }
            for (path, color) in [(ours, argb(0xb244e4ca)), (theirs, argb(0xb2ff8abb))] {
                let node = SKShapeNode(path: path)
                node.fillColor = color; node.strokeColor = .clear
                practiceNode.addChild(node)
            }
            return
        }
        p.marks.forEach { patch($0, 0.07, argb(0xb250ebd3)) }
        let targets = p.targets()
        if p.stage.skill == .shape {
            let outline = CGMutablePath()
            outline.addLines(between: targets.map { sk(unpanned($0)) }); outline.closeSubpath()
            let node = SKShapeNode(path: outline)
            node.strokeColor = argb(0xaac2f1ff); node.lineWidth = 2; node.fillColor = .clear
            practiceNode.addChild(node)
        }
        if p.stage.aimed {
            for (i, at) in targets.enumerated() {
                let done = p.painted.contains(i)
                let next = p.stage.skill != .shape || i == p.painted.count
                patch(at, p.radius, done ? argb(0xff46dfc2) : (next ? argb(0xffffd663) : argb(0x88b7eaff)))
                if p.stage.skill == .shape {
                    let label = SKLabelNode(fontNamed: CrossScene.font)
                    label.text = done ? "✓" : String(i + 1)
                    label.fontSize = 13; label.fontColor = UIColor(red: 20 / 255, green: 52 / 255, blue: 65 / 255, alpha: 1)
                    label.horizontalAlignmentMode = .center; label.verticalAlignmentMode = .baseline
                    let q = unpanned(at)
                    label.position = sk(CGPoint(x: q.x, y: q.y + 4))
                    practiceNode.addChild(label)
                }
            }
        }
    }
    /// Android drawPlayer (5c1aa4d, dd94c09): a whole authored pose standing outside the table, walking with its racket's sideways
    /// moves, winding up, meeting the ball and following through. The contact pose's racket defines where the feet stand
    /// (`playerFoot`); the paddle depth never moves a body onto the table. A far (FRONT) player stands behind the table and its rim:
    /// the tabletop hides the whole body and only the traced hands and paddle of Minik, Mia, Flare and Kyra cross it (4969038,
    /// d376d64, 80fc74e, b0cdeb3, fcfd6b2). A side player's connected upper body is in front of the raised tabletop down to its
    /// waist (0285385); the lower body and shoes stay behind it.
    private func renderPlayer(_ seat: Int, depth: Double) {
        guard let nodes = actors[seat], seat < engine.seats.count else { return }
        nodes.setDepth(depth)
        nodes.hideAll()
        let info = engine.seats[seat]
        let botCharacter = info.bot?.characterId ?? ""
        let id = botCharacter.isEmpty ? info.characterId : botCharacter
        let atlas = MPXPoseAtlas.shared
        guard !id.isEmpty, atlas.has(id) else { return }
        let local = g.toLocal(seat, engine.racket(seat))
        // Android 6fcb446/971e958: on a learning court the local player walks as far as its footwork reach.
        let u = engine.tapTargets && seat == viewSeat ? local.u.mpClamp(-CrossGeometry.strikeHalf, engine.localFootworkRight) : local.u.mpClamp(-0.48, 0.48)
        let view = g.toView(viewSeat, g.home(seat))
        let facing: MPXPoseAtlas.Facing = view.y > 0.45 ? .rear : (view.y < -0.45 ? .front : .side)
        let mirror = view.x > 0.45
        let actorHeight = scale * (id == "minik" ? 0.76 : 0.84)
        let stroke = engine.stroke(seat)
        let now = CACurrentMediaTime()
        let previous = lastLateral[seat] ?? u
        lastLateral[seat] = u
        if abs(u - previous) > 0.0015 { walkDistance[seat] = (walkDistance[seat] ?? 0) + abs(u - previous); lastStep[seat] = now }
        let walking = !stroke.active && now - (lastStep[seat] ?? 0) < 0.240
        let desired = Int((walkDistance[seat] ?? 0) / 0.11) % 4
        if now - (walkFrameAt[seat] ?? 0) >= 0.110 && walkFrame[seat] != desired { walkFrame[seat] = desired; walkFrameAt[seat] = now }
        let artId = walking && atlas.has(id + "-walk") ? id + "-walk" : id
        // Android a9140c3: every character meets the ball in its contact pose 2.
        let contactPose = 2
        let phase: Int
        if walking { phase = walkFrame[seat] ?? 0 }
        else if !stroke.active { phase = 0 }
        // Android 47ad0c9: around the actual impact time, not the earliest allowed contact time.
        else if stroke.age < stroke.impactAt - 0.04 { phase = id == "minik" && facing == .rear ? 0 : 1 }
        else if stroke.age <= stroke.impactAt + 0.075 { phase = contactPose }
        else if stroke.age < stroke.followEnd { phase = 3 }
        else { phase = 0 }
        guard let foot = playerFoot(id, facing, mirror: mirror, seat: seat, u: u, unitScale: scale, project: { self.unpanned($0, $1) }) else { return }
        if let racket = atlas.geometry(id, facing, mirror: mirror, foot: foot, height: actorHeight, phase: contactPose)?.racket { contactRackets[seat] = racket }
        let shadow = CGRect(x: Double(foot.x) - actorHeight * 0.21, y: Double(foot.y) - actorHeight * 0.025, width: actorHeight * 0.42, height: actorHeight * 0.06)
        nodes.showShadow(CGPath(ellipseIn: CGRect(x: shadow.minX, y: height - shadow.maxY, width: shadow.width, height: shadow.height), transform: nil))
        let skPoint: (CGPoint) -> CGPoint = { [unowned self] p in self.sk(p) }
        let rendered = atlas.place(facing == .rear ? nodes.free : nodes.body, artId, facing, mirror: mirror, foot: foot, height: actorHeight, phase: phase, sk: skPoint)
        if let rendered { bodyBounds[seat] = rendered.bounds }
        // The body was clipped out of this mask (CrossActorNodes.setMasks); what crosses it is drawn inside it.
        let bodyMask = facing == .front ? tableBodyMask : tablePath
        if facing == .front && ["mia", "minik", "flare", "kyra"].contains(id) {
            // The tabletop occludes the whole body; restore only the traced hands and paddle. A low racket never extends a torso
            // mask into the shorts. Nothing crosses the table while walking.
            if !walking, let hands = atlas.frontHands(id, mirror: mirror, foot: foot, height: actorHeight, phase: phase) {
                let skHands = CGMutablePath()
                skHands.addPath(hands, transform: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: size.height))
                nodes.showUpper(bodyMask.intersection(skHands))
                atlas.place(nodes.upper, id, facing, mirror: mirror, foot: foot, height: actorHeight, phase: phase, sk: skPoint)
            }
        } else if facing != .rear, let rendered {
            // The paddle is in front of the table even when its authored pose is lower than the torso cutoff: reveal one connected
            // upper body down to the waist (Android 0285385, 3b52d51), not a round paddle patch that could sever the wrist.
            let waist = max(Double(foot.y) - actorHeight * 0.48, Double(rendered.racket.y) + rendered.radius * 1.45)
            let above = CGPath(rect: CGRect(x: Double(rendered.bounds.minX), y: height - waist, width: Double(rendered.bounds.width),
                                            height: max(0, waist - Double(rendered.bounds.minY))), transform: nil)
            nodes.showUpper(bodyMask.intersection(above))
            atlas.place(nodes.upper, artId, facing, mirror: mirror, foot: foot, height: actorHeight, phase: phase, sk: skPoint)
        }
    }
    /// Android 3b52d51/1fc4bc2 `ballPresentationOffset` (drawing and touch only, never game time, ownership, score or network
    /// state). A committed strike's first flight starts at the drawn contact paddle and joins the simulated path linearly by its
    /// first real bounce (the offset fades with the flight time, no extra acceleration). Otherwise only an incoming anticipation:
    /// the responsible receiver's swing meets the ball at its paddle within 0.16 s of the impact, while the swing's point is within
    /// 0.20 of the ball; an old follow-through never pulls a returned ball back. The loose ball after a point has no offset
    /// (Android 5375378).
    private func ballOffset() -> CGPoint {
        if engine.postPointBall { return .zero }
        if let hit = engine.lastCommittedStrike {
            let key = "\(hit.rallyId)/\(hit.hitIndex)/\(hit.seat)"
            if key != contactFlightKey, let racket = contactRackets[hit.seat] {
                contactFlightKey = key
                let p = unpanned(hit.point, hit.height)
                contactFlightOffset = CGPoint(x: racket.x - p.x, y: racket.y - p.y)
            }
            let firstFlight = hit.serve ? engine.referee.phase == .serveOwn : engine.referee.phase == .toReceiver
            if firstFlight && key == contactFlightKey && !engine.ballState.stopped {
                let gravity = engine.physics.gravity
                let duration = (hit.ball.lift + sqrt(hit.ball.lift * hit.ball.lift + 2 * gravity * max(0, hit.ball.height))) / gravity
                let elapsed = (hit.ball.lift - engine.ballState.lift) / gravity
                let weight = (1 - elapsed / max(0.001, duration)).mpClamp(0, 1)
                return CGPoint(x: Double(contactFlightOffset.x) * weight, y: Double(contactFlightOffset.y) * weight)
            }
        }
        var best: (seat: Int, distance: Double)?
        for seat in g.seats where seat == engine.referee.receiver && engine.referee.phase == .receivable && contactRackets[seat] != nil {
            let s = engine.stroke(seat)
            guard s.active && !s.contacted && s.point.distance(engine.ballPosition) < 0.20 else { continue }
            let d = abs(s.age - s.impactAt)
            if best == nil || d < best!.distance { best = (seat, d) }
        }
        guard let chosen = best, chosen.distance < 0.16, let racket = contactRackets[chosen.seat] else { return .zero }
        let stroke = engine.stroke(chosen.seat)
        let weight = (1 + cos(Double.pi * chosen.distance / 0.16)) / 2
        let physics = unpanned(stroke.point, stroke.height)
        return CGPoint(x: Double(racket.x - physics.x) * weight, y: Double(racket.y - physics.y) * weight)
    }
    /// Android `renderedBallPoint`: where the ball is drawn (base view coordinates, the contact offset included).
    func renderedBallPoint() -> CGPoint {
        let b = screen(engine.renderBallPosition, engine.renderHeight), o = ballOffset()
        return CGPoint(x: b.x + o.x, y: b.y + o.y)
    }
    /// Android drawBall at `depth` (its shadow, the net flash, the ball and the edge arrow in Android's order). Android 5375378: no
    /// ball before a serve swing (`ballVisible`), none under the tabletop, and the loose ball's height below the table plane uses
    /// the linear branch of `lift`.
    private func renderBall(depth: Double) {
        let ground = engine.renderBallPosition
        let h = engine.renderHeight
        guard engine.ballVisible, !(h < 0 && g.onTable(ground)) else {
            for node in [ballShadow, ballNode, ballShine, netFlash, arrowNode] { node.isHidden = true }
            return
        }
        ballShadow.zPosition = CGFloat(depth); netFlash.zPosition = CGFloat(depth + 0.01)
        ballNode.zPosition = CGFloat(depth + 0.02); ballShine.zPosition = CGFloat(depth + 0.025); arrowNode.zPosition = CGFloat(depth + 0.03)
        ballNode.isHidden = false; ballShine.isHidden = false
        let unit = sizeAt(ground)
        let radius = unit * CrossScene.ballSize * (1 + h.mpClamp(0, 0.4) * 0.35)
        let offset = ballOffset()
        let lifted = unpanned(ground, h)
        let s = sk(unpanned(ground)), b = sk(CGPoint(x: lifted.x + offset.x, y: lifted.y + offset.y))
        let raised = h.mpClamp(0, 1.5) / 1.5
        if h >= 0 && g.onTable(ground) {
            ballShadow.isHidden = false
            ballShadow.position = CGPoint(x: s.x + CGFloat(radius * 0.15), y: s.y - CGFloat(radius * 0.2))
            ballShadow.xScale = CGFloat(radius * (1 + raised * 0.6)); ballShadow.yScale = CGFloat(radius * (0.5 + raised * 0.25))
            ballShadow.alpha = CGFloat(110 - 70 * raised) / 255 * 0.8
        } else { ballShadow.isHidden = true }
        if engine.netAge < 0.5 {
            netFlash.isHidden = false
            netFlash.position = b
            netFlash.setScale(CGFloat(radius * (1.5 + engine.netAge * 4)))
            netFlash.lineWidth = CGFloat(2.5 / max(0.5, radius * (1.5 + engine.netAge * 4)))
            netFlash.alpha = CGFloat(1 - engine.netAge / 0.5) * 240 / 255
        } else { netFlash.isHidden = true }
        ballNode.position = b; ballNode.setScale(CGFloat(max(0.5, radius)))
        ballNode.lineWidth = CGFloat(0.8 / max(0.5, radius))
        ballShine.position = CGPoint(x: b.x - CGFloat(radius * 0.3), y: b.y + CGFloat(radius * 0.35)); ballShine.setScale(CGFloat(max(0.2, radius * 0.35)))
        // A ball outside the visible area gets a small edge arrow pointing to it (Android: from the drawn ball, inside the camera).
        let inset = 14.0
        let bx = Double(lifted.x + offset.x) - pan, by = Double(lifted.y + offset.y) - panY
        if bx < 0 || bx > width || by < 0 || by > height {
            let ex = bx.mpClamp(inset, width - inset), ey = by.mpClamp(inset, height - inset)
            let angle = atan2(by - ey, bx - ex)
            arrowNode.isHidden = false
            arrowNode.position = sk(CGPoint(x: ex, y: ey))
            arrowNode.zRotation = CGFloat(-angle)
        } else { arrowNode.isHidden = true }
    }
    /// Android drawRacket: handle, dark rim and red face, drawn at the engine's contact centre.
    private func buildPaddle() {
        let handle = SKShapeNode(rect: CGRect(x: -0.23, y: -1.65, width: 0.46, height: 1.1), cornerRadius: 0.16)
        handle.fillColor = UIColor(red: 232 / 255, green: 181 / 255, blue: 113 / 255, alpha: 1); handle.strokeColor = .clear
        let rim = SKShapeNode(ellipseIn: CGRect(x: -1.06, y: -1.2, width: 2.12, height: 2.4))
        rim.fillColor = UIColor(red: 51 / 255, green: 32 / 255, blue: 38 / 255, alpha: 1); rim.strokeColor = .clear
        let face = SKShapeNode(ellipseIn: CGRect(x: -1, y: -1.12, width: 2, height: 2.24))
        face.fillColor = UIColor(red: 224 / 255, green: 44 / 255, blue: 74 / 255, alpha: 1)
        face.strokeColor = UIColor(red: 1, green: 213 / 255, blue: 157 / 255, alpha: 1); face.lineWidth = 0.08
        for node in [handle, rim, face] { paddleNode.addChild(node) }
    }
    private func renderPaddle() {
        // The local player's own character holds the paddle; only a player without one sees the bare paddle.
        guard let local = engine.localSeat, engine.seats[local].characterId.trimmingCharacters(in: .whitespaces).isEmpty else { paddleNode.isHidden = true; return }
        let stroke = engine.stroke(local)
        let at = engine.paddle ?? engine.restingPaddle
        // Android d0bed3b `CrossPaddlePose`: after the impact the paddle eases from the contact back to the player's stance.
        let pose = CrossPaddlePose.at(stroke, at)
        let p = pose.point
        paddleNode.isHidden = false
        paddleNode.position = sk(unpanned(p, pose.height))
        paddleNode.setScale(CGFloat(max(1, sizeAt(p) * 0.09)))
        let degrees = UIAccessibility.isReduceMotionEnabled ? 0 : engine.paddleTilt + stroke.angle
        paddleNode.zRotation = CGFloat(-degrees * Double.pi / 180)
    }
    /// Android 3b52d51 `SunsetTerrace.foreground(this, canvas)`: after the camera's content and before the tags, the terrace's
    /// foreground foliage is drawn again over the court, unzoomed. The terrace (`MPXSunsetBackground`) aspect-fills the whole
    /// window, top aligned and horizontally centred; this scene finds its own place in the window and draws that painting's
    /// foliage at the same spot. Rebuilt only when the scene moves or resizes.
    private func renderForeground() {
        guard let view, let window = view.window, window.bounds.width > 0, window.bounds.height > 0 else { foliageCrop.isHidden = true; return }
        let frame = view.convert(view.bounds, to: nil), terrace = window.bounds.size
        if frame == foliageFrame && terrace == foliageWindow && !foliageCrop.isHidden { return }
        foliageFrame = frame; foliageWindow = terrace
        let landscape = terrace.width > terrace.height
        guard let image = UIImage(named: landscape ? "mpx_sunset_landscape" : "mpx_sunset_portrait"), image.size.width > 0, image.size.height > 0 else {
            foliageCrop.isHidden = true; return
        }
        let cover = max(terrace.width / image.size.width, terrace.height / image.size.height)
        let w = image.size.width * cover, h = image.size.height * cover
        // The painting's rectangle in this scene's view coordinates (y down).
        let destination = CGRect(x: (terrace.width - w) / 2 - frame.minX, y: -frame.minY, width: w, height: h)
        let skMask = CGMutablePath()
        skMask.addPath(MPXTerraceFoliage.path(portrait: !landscape, in: destination), transform: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: size.height))
        foliageMask.path = skMask
        foliage.texture = SKTexture(image: image)
        foliage.texture?.filteringMode = .linear
        foliage.size = CGSize(width: w, height: h)
        foliage.position = sk(CGPoint(x: destination.midX, y: destination.midY))
        foliageCrop.isHidden = false
    }
    /// Android 7254ab2: light seat colours (Gaya's yellow and green) are darkened to 60 % so the white names stay readable.
    private func tagColor(_ seat: Int) -> UIColor {
        let c = CrossScene.seatColors[colorIndex(seat) % CrossScene.seatColors.count]
        let f = CrossScoreFeedback.luminance(c) > 0.20 ? 0.60 : 1.0
        return UIColor(red: CGFloat((c.0 * f).rounded(.down) / 255), green: CGFloat((c.1 * f).rounded(.down) / 255),
                       blue: CGFloat((c.2 * f).rounded(.down) / 255), alpha: 245 / 255)
    }
    private func seatColor(_ seat: Int, alpha: Double) -> UIColor {
        let c = CrossScene.seatColors[colorIndex(seat) % CrossScene.seatColors.count]
        return UIColor(red: CGFloat(c.0 / 255), green: CGFloat(c.1 / 255), blue: CGFloat(c.2 / 255), alpha: CGFloat(alpha / 255))
    }
    /// Base view point (pan included) → painted view point (the close camera's zoom).
    private func painted(_ unpannedPoint: CGPoint) -> CGPoint {
        courtCamera.painted(CGPoint(x: Double(unpannedPoint.x) - pan, y: Double(unpannedPoint.y) - panY))
    }
    /// Name (and, individually, score) next to every player, with a server marker and floating +1/−1 notes. The badges sit above
    /// the drawn heads; a side player on the right has it below, a far head near the score strip has it beside.
    private func renderTags() {
        let now = CACurrentMediaTime()
        let ref = engine.referee
        let minimumY = scoreboardHeight + 26
        for s in g.seats {
            guard let tag = tags[s] else { continue }
            var at: CGPoint
            let homeView = g.toView(viewSeat, g.home(s))
            if s == viewSeat {
                if let box = bodyBounds[s] { at = painted(CGPoint(x: box.midX, y: box.minY - 12)) } else { at = CGPoint(x: width / 2, y: height - 9) }
            } else if let box = bodyBounds[s] {
                at = painted(CGPoint(x: box.midX, y: homeView.x > 0.5 ? box.maxY + 24 : box.minY - 12))
            } else {
                let lateral = g.toLocal(s, engine.racket(s)).u.mpClamp(-0.75, 0.75)
                at = painted(unpanned(g.fromLocal(s, lateral, CrossGeometry.reach + CrossScene.stand)))
            }
            let serving = ref.server == s && ref.phase == .awaitingServe
            let label = (serving ? "🏓 " : "") + (s < names.count ? names[s] : "") + (showsScores && engine.teams == nil ? "  " + String(ref.score(s)) : "")
            tag.label.text = label
            tag.label.fontSize = 13.5
            let boxWidth = Double(tag.label.frame.width) + 16
            var badge = at
            if homeView.y < -0.45, Double(at.y) < minimumY, let box = bodyBounds[s] {
                // Android 9862dc6: the central far badge shares the left neighbour's head row, so it goes to the right of its head;
                // genuinely left-hand seats keep their outside-left badge.
                let left = homeView.x < -0.05
                badge = painted(CGPoint(x: left ? Double(box.minX) - boxWidth / 2 - 10 : Double(box.maxX) + boxWidth / 2 + 10, y: Double(box.minY) + 22))
            }
            let x = Double(badge.x).mpClamp(boxWidth / 2 + 2, max(boxWidth / 2 + 2, width - boxWidth / 2 - 2))
            let y = Double(badge.y).mpClamp(minimumY, max(minimumY, height - 12))
            let box = CGRect(x: x - boxWidth / 2, y: height - (y + 6), width: boxWidth, height: 21)
            tag.box.path = CrossScene.rounded(box, 10)
            tag.box.fillColor = tagColor(s)
            let highlight = (tutorialTarget ?? engine.predictedReceiver) == s
            tag.outline.isHidden = !highlight
            tag.outline.path = tag.box.path
            tag.label.position = CGPoint(x: x, y: height - y)
            // Beginner/Standard: who a return would go to now, following the latest sideways swipe.
            if engine.aimTarget == s {
                tag.aim.isHidden = false
                tag.aim.position = CGPoint(x: x, y: height - (y - 20))
                tag.aim.alpha = CGFloat((170 + 85 * sin(now * 1000 / 160)).mpClamp(0, 255) / 255)
            } else { tag.aim.isHidden = true }
            if showsScores, let note = notes[s] {
                let age = (now - note.at) / 1.6
                if age >= 1 { notes[s] = nil; tag.note.isHidden = true }
                else {
                    tag.note.isHidden = false
                    tag.note.text = note.text
                    tag.note.fontColor = note.text.hasPrefix("+") ? UIColor(red: 140 / 255, green: 1, blue: 160 / 255, alpha: 1)
                        : (note.text.hasPrefix("−") ? UIColor(red: 1, green: 140 / 255, blue: 140 / 255, alpha: 1) : .white)
                    tag.note.alpha = CGFloat(1 - age)
                    tag.note.position = CGPoint(x: x, y: height - (y - 22 - age * 26))
                }
            } else { tag.note.isHidden = true }
        }
    }
    /// Every participant's score in one readable row above the table, the server marked; teams share one box per team.
    private func renderScoreboard() {
        if let teams = engine.teams { renderTeamScoreboard(teams); return }
        let ref = engine.referee
        let order = g.seats.map { g.wrap(viewSeat + $0) }
        let gap = 6.0, top = 6.0, h = scoreboardHeight - 12
        let w = (width - gap * Double(order.count + 1)) / Double(max(1, order.count))
        for (i, s) in order.enumerated() {
            guard let board = boards[s] else { continue }
            board.box.isHidden = false; board.name.isHidden = false; board.score.isHidden = false
            let x = gap + Double(i) * (w + gap)
            let rect = CGRect(x: x, y: height - (top + h), width: max(1, w), height: h)
            board.box.path = CrossScene.rounded(rect, 14)
            let c = CrossScene.seatColors[colorIndex(s) % CrossScene.seatColors.count]
            board.box.fillColor = UIColor(red: CGFloat((c.0 / 2 + 15) / 255), green: CGFloat((c.1 / 2 + 15) / 255), blue: CGFloat((c.2 / 2 + 25) / 255), alpha: 225 / 255)
            board.outline.isHidden = !(ref.winner == s || (tutorialTarget ?? engine.predictedReceiver) == s)
            board.outline.path = board.box.path
            board.showFlash(scoreFeedback.color(s, now: CACurrentMediaTime()))
            let name = s < names.count ? names[s] : ""
            let shown = name.count > 10 ? String(name.prefix(9)) + "…" : name
            board.name.text = (ref.server == s ? "🏓 " : "") + shown
            board.name.fontSize = 13
            board.name.position = CGPoint(x: x + w / 2, y: height - (top + h * 0.36))
            board.score.text = String(ref.score(s))
            board.score.fontSize = width > height ? 19 : 25
            board.score.position = CGPoint(x: x + w / 2, y: height - (top + h * 0.86))
        }
    }
    private func renderTeamScoreboard(_ teams: CrossTeams) {
        let mine = teams.seats[min(viewSeat, teams.seats.count - 1)]
        var ids = [mine]
        for id in teams.seats where !ids.contains(id) { ids.append(id) }
        let gap = 6.0, h = scoreboardHeight - 12
        let w = (width - gap * Double(ids.count + 1)) / Double(ids.count)
        let hebrew = MPText.language == "he"
        for (s, board) in boards {
            let index = ids.firstIndex(of: teams.seats[min(s, teams.seats.count - 1)]) ?? 0
            let members = g.seats.filter { teams.seats[$0] == ids[index] }
            // One box per team, drawn by its first seat.
            guard members.first == s else { board.hide(); continue }
            board.box.isHidden = false; board.name.isHidden = false; board.score.isHidden = false; board.outline.isHidden = true
            let x = gap + Double(index) * (w + gap), y = 6.0
            // Android dd94c09: each team box (and its highlight) reaches 4 pt further down; the texts keep their places.
            let bottomPadding = 4.0
            board.box.path = CrossScene.rounded(CGRect(x: x, y: height - (y + h + bottomPadding), width: max(1, w), height: h + bottomPadding), 12)
            let now = CACurrentMediaTime()
            board.showFlash(members.lazy.compactMap { self.scoreFeedback.color($0, now: now) }.first)
            let c = CrossScene.seatColors[ids[index] % CrossScene.seatColors.count]
            board.box.fillColor = UIColor(red: CGFloat(c.0 / 255), green: CGFloat(c.1 / 255), blue: CGFloat(c.2 / 255), alpha: 1)
            // iOS (2026-11-10, owner decision): the joining word in every app language (MPTextIOS; Android: English or Hebrew).
            let title = members.map { $0 < names.count ? names[$0] : engine.seats[$0].name }.joined(separator: MPText.t(" and ", " ו־", hebrew))
            board.name.text = title
            var font = 13.0
            board.name.fontSize = CGFloat(font)
            while Double(board.name.frame.width) > w - 12 && font > 10 { font -= 0.5; board.name.fontSize = CGFloat(font) }
            board.name.position = CGPoint(x: x + w / 2, y: height - (y + h * 0.34))
            board.score.text = String(engine.referee.score(members[0]))
            board.score.fontSize = width > height ? 19 : 25
            board.score.position = CGPoint(x: x + w / 2, y: height - (y + h * 0.88))
        }
    }
    /// A rounded rectangle whose corner radius always fits (CGPath requires it).
    private static func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
        guard rect.width > 0, rect.height > 0 else { return CGMutablePath() }
        let r = min(radius, rect.width / 2 - 0.01, rect.height / 2 - 0.01)
        guard r > 0 else { return CGPath(rect: rect, transform: nil) }
        return CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
    }
    /// A gradient fill texture (Android LinearGradient), from the first colour to the last.
    private static func gradient(_ colors: [(Double, Double, Double)], vertical: Bool) -> SKTexture {
        let size = vertical ? CGSize(width: 4, height: 256) : CGSize(width: 256, height: 4)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let cg = colors.map { UIColor(red: CGFloat($0.0 / 255), green: CGFloat($0.1 / 255), blue: CGFloat($0.2 / 255), alpha: 1).cgColor } as CFArray
            guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cg, locations: nil) else { return }
            context.cgContext.drawLinearGradient(g, start: .zero, end: vertical ? CGPoint(x: 0, y: size.height) : CGPoint(x: size.width, y: 0), options: [])
        }
        return SKTexture(image: image)
    }
    /// The narrow sunset sheen across the table (transparent → warm 70/255 at 68 % → transparent).
    private static func sheenTexture() -> SKTexture {
        let size = CGSize(width: 256, height: 4)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let warm = UIColor(red: 1, green: 240 / 255, blue: 174 / 255, alpha: 70 / 255).cgColor, clear = UIColor(red: 1, green: 240 / 255, blue: 174 / 255, alpha: 0).cgColor
            guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [clear, warm, clear] as CFArray, locations: [0, 0.68, 1]) else { return }
            context.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: size.width, y: 0), options: [])
        }
        return SKTexture(image: image)
    }
    /// Show the score change of a resolved rally next to every affected player (individual play only).
    func showOutcome(_ outcome: CrossRallyOutcome) {
        scoreFeedback.record(outcome, now: CACurrentMediaTime())
        if engine.teams != nil { return }
        let now = CACurrentMediaTime()
        for s in g.seats {
            let d = s < outcome.deltas.count ? outcome.deltas[s] : 0
            if d > 0 { notes[s] = ("+\(d)", now) }
            else if d < 0 { notes[s] = ("−\(-d)", now) }
            else if outcome.faultOwner == s || (outcome.kind == .missed && outcome.receiver == s) { notes[s] = ("0", now) }
        }
    }

    // ---- input --------------------------------------------------------------------------------------
    /// The touch in base view coordinates: the close camera's zoom is undone, as Android transforms the MotionEvent.
    private func viewPoint(_ touch: UITouch) -> CGPoint {
        let p = touch.location(in: self)
        return courtCamera.base(CGPoint(x: p.x, y: size.height - p.y))
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard acceptsInput, activeTouch == nil, let touch = touches.first else { return }
        activeTouch = touch
        let p = viewPoint(touch)
        downPoint = p
        samples = [(touch.timestamp, p)]
        let serving = engine.localSeat.map { engine.referee.mayServe($0) } ?? true
        standardGesture = (engine.control == .starter || engine.control == .standard) && !serving && !engine.receivingSet && !engine.tapTargets
        standardDragged = false; standardStarted = false; standardAiming = engine.canAimReturn()
        // A drag starting on the visible local body remains footwork even when its head or shoulder overlaps a selectable table
        // area; on a raised ball it is the smash.
        let visibleBall = renderedBallPoint()
        let startsOnBall = hypot(Double(p.x - visibleBall.x), Double(p.y - visibleBall.y)) < max(44, scale * 0.16)
        practiceDrag = engine.tapTargets && !(engine.receivingSet && startsOnBall) && !serving && bodyBounds[viewSeat]?.contains(p) == true
        standardAnchor = engine.restingPaddle; aimStartX = Double(p.x)
        let anchor = g.toView(viewSeat, standardAnchor)
        standardWidth = max(1, abs(Double(screen(g.fromView(viewSeat, MPPoint(anchor.x + 1, anchor.y))).x - screen(standardAnchor).x)))
        // Team play: a second quick tap near the first arms one raised pass to the teammate.
        raisedTap = false
        if engine.teams != nil {
            let gap = touch.timestamp - lastTapAt
            raisedTap = gap >= 0.001 && gap <= CrossScene.doubleTapTimeout && hypot(p.x - lastTapPoint.x, p.y - lastTapPoint.y) < 56 && engine.liftToTeammate()
        }
        send(p, down: true)
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard acceptsInput, let touch = activeTouch, touches.contains(touch) else { return }
        for sample in event?.coalescedTouches(for: touch) ?? [touch] {
            let p = viewPoint(sample)
            samples.append((sample.timestamp, p))
            send(p, down: false)
        }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        if acceptsInput {
            let p = viewPoint(touch)
            samples.append((touch.timestamp, p))
            if hypot(p.x - downPoint.x, p.y - downPoint.y) < 12 { lastTapAt = raisedTap ? -1000 : touch.timestamp; lastTapPoint = p }
            else { lastTapAt = -1000 }
            send(p, down: false, up: true)
            engine.endTouch(cancelled: false)
        }
        activeTouch = nil; samples = []
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { cancelTouch() }
    func cancelTouch() {
        if activeTouch != nil { engine.release() }
        activeTouch = nil; samples = []; practiceDrag = false
    }
    /// Android VelocityTracker: the finger's speed over the last few samples, in points per second.
    private func fingerVelocity() -> CGVector {
        guard let last = samples.last else { return .zero }
        samples = samples.filter { last.time - $0.time <= 0.08 }
        guard let first = samples.first, last.time - first.time > 0.004 else { return .zero }
        let dt = CGFloat(last.time - first.time)
        return CGVector(dx: (last.point.x - first.point.x) / dt, dy: (last.point.y - first.point.y) / dt)
    }
    private func send(_ p: CGPoint, down: Bool, up: Bool = false) {
        // Android 971e958: the second tap armed a set; it keeps the current footwork and aim.
        if raisedTap { return }
        if standardGesture { standardTouch(p, down: down, up: up); return }
        // Android 5375378: a finger on the airborne ball (nearer to the drawn ball than to its ground point) is a touch at the ball's
        // world position, not at the farther table surface behind it; the drag and aim displacement are kept.
        let rawBall = screen(engine.renderBallPosition, engine.renderHeight)
        let offset = ballOffset()
        let groundBall = screen(engine.ballPosition)
        let visibleDistance = hypot(Double(p.x - rawBall.x - offset.x), Double(p.y - rawBall.y - offset.y))
        let touchingBall = engine.predictedReceiver == engine.localSeat &&
            visibleDistance < max(44, scale * 0.16) && visibleDistance < hypot(Double(p.x - groundBall.x), Double(p.y - groundBall.y))
        let projected = touchingBall ? world(Double(groundBall.x + p.x - rawBall.x - offset.x), Double(groundBall.y + p.y - rawBall.y - offset.y))
            : world(Double(p.x), Double(p.y))
        // Android c93e760/6fcb446/971e958: learners drag the visible player, whose feet are below the table: a drag from the body
        // walks it sideways from where it stood; any other touch below the far strike edge is projected onto the legal racket
        // depth (up to the footwork reach). Other courts still select aim; the smash keeps its swept ball gesture.
        let serving = engine.localSeat.map { engine.referee.mayServe($0) } ?? true
        let point: MPPoint
        if practiceDrag {
            let at = g.toLocal(viewSeat, standardAnchor)
            point = g.fromLocal(viewSeat, (at.u + Double(p.x - downPoint.x) / standardWidth).mpClamp(-CrossGeometry.strikeHalf, engine.localFootworkRight), at.v)
        } else if engine.tapTargets && !serving {
            let at = g.toLocal(viewSeat, projected)
            point = at.v >= CrossGeometry.strikeNear ? g.fromLocal(viewSeat, at.u.mpClamp(-CrossGeometry.strikeHalf, engine.localFootworkRight),
                                                                    at.v.mpClamp(CrossGeometry.strikeNear, CrossGeometry.strikeFar)) : projected
        } else { point = projected }
        let here = g.toView(viewSeat, point)
        let unit = max(1, scale * k(here.y))
        let finger = fingerVelocity()
        let velocity = MPPoint(Double(finger.dx) / unit, Double(finger.dy) / (unit * tilt))
        let drag = MPPoint(Double(p.x - downPoint.x), Double(p.y - downPoint.y))
        if practiceDrag && engine.receivingSet { engine.moveOnly(point); return }
        engine.touch(point, drag: drag, velocity: velocity, down: down)
    }
    /// Android fcfd6b2/d0bed3b `standardTouch` (base view points, y down).
    private func standardTouch(_ p: CGPoint, down: Bool, up: Bool) {
        if down { return } // distinguish a tap from footwork first
        standardDragged = standardDragged || hypot(p.x - downPoint.x, p.y - downPoint.y) > 12
        let finger = fingerVelocity()
        if standardDragged {
            if !standardAiming && engine.canAimReturn() { standardAiming = true; aimStartX = Double(p.x) }
            if standardAiming {
                let speed = hypot(Double(finger.dx), Double(finger.dy)) / standardWidth
                // Keep the stance for the whole aiming gesture, including its follow-through.
                if !standardStarted { standardStarted = engine.aimReturn(drag: Double(p.x) - aimStartX, speed: speed, start: true) }
                else { engine.aimReturn(drag: Double(p.x) - aimStartX, speed: speed, start: false) }
            } else {
                let anchor = g.toView(viewSeat, standardAnchor)
                let u = (anchor.x + Double(p.x - downPoint.x) / standardWidth).mpClamp(-CrossGeometry.strikeHalf, CrossGeometry.strikeHalf)
                engine.moveOnly(g.fromView(viewSeat, MPPoint(u, anchor.y.mpClamp(CrossGeometry.strikeNear, CrossGeometry.strikeFar))))
            }
        } else if up {
            // A single tap returns from the current stance; no teleport to the tapped pixel. The court it lifted on is its target.
            engine.aimReturn(drag: 0, speed: 0, start: true, target: world(Double(p.x), Double(p.y)))
        }
    }
}

/// One player's sprites: a floor shadow clipped to the space outside the table, the body clipped to the space outside the table
/// (a far player: outside the table and its rim), what crosses the tabletop (a side player's upper body, a far player's traced
/// hands and paddle) and an unclipped body (the local player seen from behind).
private final class CrossActorNodes {
    let crop = SKCropNode(), mask = SKShapeNode()
    let shadowCrop = SKCropNode(), shadowMask = SKShapeNode(), shadow = SKShapeNode()
    let body = SKSpriteNode(), free = SKSpriteNode()
    let upperCrop = SKCropNode(), upperMask = SKShapeNode(), upper = SKSpriteNode()
    init(parent: SKNode) {
        for m in [mask, shadowMask, upperMask] { m.fillColor = .white; m.strokeColor = .clear; m.lineWidth = 0 }
        crop.maskNode = mask; crop.addChild(body)
        shadowCrop.maskNode = shadowMask; shadowCrop.addChild(shadow)
        shadow.fillColor = UIColor(red: 13 / 255, green: 29 / 255, blue: 38 / 255, alpha: 65 / 255); shadow.strokeColor = .clear
        upperCrop.maskNode = upperMask; upperCrop.addChild(upper)
        parent.addChild(shadowCrop); parent.addChild(crop); parent.addChild(upperCrop); parent.addChild(free)
    }
    func setMasks(body: CGPath, shadow: CGPath) { mask.path = body; shadowMask.path = shadow }
    func setDepth(_ z: Double) {
        shadowCrop.zPosition = CGFloat(z); crop.zPosition = CGFloat(z + 0.01); upperCrop.zPosition = CGFloat(z + 0.02); free.zPosition = CGFloat(z + 0.03)
    }
    func hideAll() { shadow.isHidden = true; body.isHidden = true; free.isHidden = true; upperCrop.isHidden = true }
    func showShadow(_ path: CGPath) { shadow.isHidden = false; shadow.path = path }
    func showUpper(_ path: CGPath) { upperCrop.isHidden = false; upperMask.path = path }
    func remove() { [shadowCrop, crop, upperCrop, free].forEach { $0.removeFromParent() } }
}

/// A player's name tag: box, highlight outline, label, the 🎯 aim marker and the floating score note.
private final class CrossTagNodes {
    let box = SKShapeNode(), outline = SKShapeNode()
    let label: SKLabelNode, aim: SKLabelNode, note: SKLabelNode
    init(parent: SKNode, font: String) {
        label = SKLabelNode(fontNamed: font); aim = SKLabelNode(text: "🎯"); note = SKLabelNode(fontNamed: font)
        box.strokeColor = .clear; box.zPosition = 0
        outline.fillColor = .clear; outline.strokeColor = UIColor(red: 1, green: 221 / 255, blue: 87 / 255, alpha: 1); outline.lineWidth = 2.2; outline.zPosition = 0.1
        label.fontColor = .white; label.horizontalAlignmentMode = .center; label.verticalAlignmentMode = .baseline; label.zPosition = 0.2
        aim.fontSize = 20; aim.horizontalAlignmentMode = .center; aim.verticalAlignmentMode = .baseline; aim.zPosition = 0.3
        note.fontSize = 22; note.horizontalAlignmentMode = .center; note.verticalAlignmentMode = .baseline; note.zPosition = 0.4
        for node in [box, outline] { parent.addChild(node) }
        for node in [label, aim, note] { parent.addChild(node) }
    }
    func remove() { [box, outline].forEach { $0.removeFromParent() }; [label, aim, note].forEach { $0.removeFromParent() } }
}

/// One scoreboard box: background, highlight outline, name and score.
private final class CrossBoardNodes {
    let box = SKShapeNode(), outline = SKShapeNode()
    let name: SKLabelNode, score: SKLabelNode
    init(parent: SKNode, font: String) {
        name = SKLabelNode(fontNamed: font); score = SKLabelNode(fontNamed: font)
        box.strokeColor = .clear; box.zPosition = 0
        outline.fillColor = .clear; outline.strokeColor = UIColor(red: 1, green: 221 / 255, blue: 87 / 255, alpha: 1); outline.lineWidth = 2.5; outline.zPosition = 0.1
        for label in [name, score] {
            label.fontColor = .white; label.horizontalAlignmentMode = .center; label.verticalAlignmentMode = .baseline; label.zPosition = 0.2
        }
        for node in [box, outline] { parent.addChild(node) }
        for node in [name, score] { parent.addChild(node) }
    }
    let flash = SKShapeNode()
    func hide() { box.isHidden = true; outline.isHidden = true; flash.isHidden = true; name.isHidden = true; score.isHidden = true }
    /// The timed gain/loss outline over the box (Android CrossScoreFeedback), drawn above the highlight outline.
    func showFlash(_ color: UIColor?) {
        guard let color else { flash.isHidden = true; return }
        if flash.parent == nil, let parent = box.parent {
            flash.fillColor = .clear; flash.lineWidth = 3; flash.zPosition = 0.15; parent.addChild(flash)
        }
        flash.isHidden = false; flash.strokeColor = color; flash.path = box.path
    }
    func remove() { [box, outline, flash].forEach { $0.removeFromParent() }; [name, score].forEach { $0.removeFromParent() } }
}
