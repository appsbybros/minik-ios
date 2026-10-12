import CoreGraphics
import UIKit

/// Android `Rect` (integer pixel rectangle: left, top, right, bottom).
struct PixelRect: Equatable {
    var left: Int
    var top: Int
    var right: Int
    var bottom: Int

    init(_ left: Int, _ top: Int, _ right: Int, _ bottom: Int) {
        self.left = left
        self.top = top
        self.right = right
        self.bottom = bottom
    }

    var width: Int { return right - left }
    var height: Int { return bottom - top }
    var cg: CGRect { return CGRect(x: left, y: top, width: width, height: height) }
}

/// Decoded alpha channel of an atlas for the opaque-bounds and racket-grip searches
/// (Android `Bitmap.getPixel` alpha).
final class AlphaMap {
    let width: Int
    let height: Int
    private let alpha: [UInt8]

    init?(_ image: CGImage) {
        let w = image.width
        let h = image.height
        guard w > 0, h > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setBlendMode(.copy)
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = context.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var values = [UInt8](repeating: 0, count: w * h)
        // CGContext rows start at the top of the drawn image.
        for i in 0..<(w * h) { values[i] = pixels[i * 4 + 3] }
        width = w
        height = h
        alpha = values
    }

    func at(_ x: Int, _ y: Int) -> Int {
        guard x >= 0, y >= 0, x < width, y < height else { return 0 }
        return Int(alpha[y * width + x])
    }
}

/// Port of Android SportsArt.kt: the character atlases (front, directional, locomotion, volleyball
/// actions and passes), opaque-body anchors, portraits, the squash racket and its grip on the
/// sprite. Art is the Android WebP converted losslessly to PNG.
@MainActor
final class SportsArt {
    static let shared = SportsArt()

    private var atlas: [String: Any] = [:]
    private var directions: [String: Any] = [:]
    private var volleyActions: [String: Any] = [:]
    private var volleyPasses: [String: Any] = [:]
    private var images: [String: UIImage] = [:]
    private var alphas: [String: AlphaMap] = [:]
    private var cells: [String: UIImage] = [:]
    private var portraits: [String: UIImage] = [:]
    private var bounds: [String: PixelRect] = [:]
    private var grips: [String: CGPoint] = [:]

    private init() {
        atlas = SportsArt.characters("atlas")
        directions = SportsArt.characters("directions")
        volleyActions = SportsArt.characters("volley-actions")
        volleyPasses = SportsArt.characters("volley-passes")
    }

    private static func characters(_ name: String) -> [String: Any] {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let root = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any] else { return [:] }
        return (root["characters"] as? [String: Any]) ?? [:]
    }

    /// Android `bitmap(name)`.
    func bitmap(_ name: String) -> UIImage? {
        if let cached = images[name] { return cached }
        guard let loaded = UIImage(named: name) else { return nil }
        images[name] = loaded
        return loaded
    }

    private func alpha(_ name: String) -> AlphaMap? {
        if let cached = alphas[name] { return cached }
        guard let image = bitmap(name)?.cgImage, let map = AlphaMap(image) else { return nil }
        alphas[name] = map
        return map
    }

    private func cell(_ name: String, _ src: PixelRect) -> UIImage? {
        let key = "\(name):\(src.left):\(src.top):\(src.right):\(src.bottom)"
        if let cached = cells[key] { return cached }
        guard let image = bitmap(name)?.cgImage, let cropped = image.cropping(to: src.cg) else { return nil }
        let made = UIImage(cgImage: cropped, scale: 1, orientation: .up)
        cells[key] = made
        return made
    }

    /// Releases decoded art after a memory warning; everything reloads on demand.
    func purge() {
        images.removeAll()
        alphas.removeAll()
        cells.removeAll()
    }

    /// Android `portrait(id)`: the ready pose cropped to its visible body.
    func portrait(_ id: String) -> UIImage? {
        if let cached = portraits[id] { return cached }
        guard let map = alpha(id), let source = bitmap(id)?.cgImage else { return nil }
        let b = SportsArt.alphaBounds(map, PixelRect(0, 0, 256, 320))
        let left = max(b.left, 0)
        let top = max(b.top, 0)
        let crop = CGRect(x: left, y: top, width: min(b.width, 256 - b.left), height: min(b.height, 320 - b.top))
        guard crop.width > 0, crop.height > 0, let cropped = source.cropping(to: crop) else { return nil }
        let made = UIImage(cgImage: cropped, scale: 1, orientation: .up)
        portraits[id] = made
        return made
    }

    /// Android `alphaBounds(b, r)`: alpha above 40 sampled every second pixel, relative to `r`.
    static func alphaBounds(_ b: AlphaMap, _ r: PixelRect) -> PixelRect {
        var x0 = r.right
        var y0 = r.bottom
        var x1 = r.left
        var y1 = r.top
        var y = r.top
        while y < r.bottom {
            var x = r.left
            while x < r.right {
                if b.at(x, y) > 40 {
                    x0 = min(x0, x)
                    y0 = min(y0, y)
                    x1 = max(x1, x)
                    y1 = max(y1, y)
                }
                x += 2
            }
            y += 2
        }
        return PixelRect(x0 - r.left, y0 - r.top, x1 - r.left + 2, y1 - r.top + 2)
    }

    private func hand(_ table: [String: Any], _ character: String, _ index: Int) -> (Double, Double) {
        let entry = (table[character] as? [String: Any]) ?? [:]
        let frames = entry["frames"] as? [Any] ?? []
        guard index >= 0 && index < frames.count, let frame = frames[index] as? [String: Any] else { return (0, 0) }
        let h = NodeValue.list(frame["hand"]).map { NodeValue.number($0) ?? 0 }
        return h.count >= 2 ? (h[0], h[1]) : (0, 0)
    }

    private func actionHand(_ table: [String: Any], _ character: String, _ index: Int) -> (Double, Double, Int) {
        let entry = (table[character] as? [String: Any]) ?? [:]
        let body = KotlinNumber.int(NodeValue.number(entry["bodyHeight"]) ?? 0)
        let hands = entry["hands"] as? [Any] ?? []
        guard index >= 0 && index < hands.count else { return (0, 0, body) }
        let h = NodeValue.list(hands[index]).map { NodeValue.number($0) ?? 0 }
        return h.count >= 2 ? (h[0], h[1], body) : (0, 0, body)
    }

    /// Android `draw(c, a, footX, footY, height, squash, clock, paint, yaw)`: draws the athlete with
    /// visible feet at (footX, footY) and the visible body `height` tall; returns the drawn hand.
    @discardableResult
    func draw(_ c: CGContext, _ a: Athlete, _ footX: Float, _ footY: Float, _ height: Float, _ squash: Bool, _ yaw: Double = 0.0) -> CGPoint {
        let moving = a.velocity.length() > 0.25 && a.poseTime <= 0
        let face = Vec(cos(yaw) * a.facing.x - sin(yaw) * a.facing.y, sin(yaw) * a.facing.x + cos(yaw) * a.facing.y)
        let back = face.y < -0.25 && abs(face.y) >= abs(face.x) * 0.65
        let side = abs(face.x) > abs(face.y) * 0.75
        let flip = side && face.x < 0
        let character = a.member.character
        let name: String
        let src: PixelRect
        let anchor: String
        var handX: Float = 0.56
        var handY: Float = 0.52
        var actionBound: PixelRect? = nil
        if !squash && ["serve_prepare", "serve", "spike", "block"].contains(a.pose) {
            name = character + "_volley"
            let row = back ? 2 : (side ? 1 : 0)
            let pose: Int
            switch a.pose {
            case "block": pose = 3
            case "serve_prepare": pose = 0
            default: pose = a.poseTime > 0.43 ? 1 : 2
            }
            src = PixelRect(pose * 192, row * 280, (pose + 1) * 192, (row + 1) * 280)
            anchor = character + "volley"
            let h = actionHand(volleyActions, character, row * 4 + pose)
            actionBound = PixelRect(0, 270 - h.2, 192, 270)
            handX = Float(h.0 / 192)
            handY = Float(h.1 / 280)
        } else if !squash && ["receive", "set", "dive"].contains(a.pose) {
            name = character + "_passes"
            let row = back ? 2 : (side ? 1 : 0)
            let pose = a.pose == "set" ? 1 : (a.pose == "dive" ? 2 : 0)
            src = PixelRect(pose * 320, row * 280, (pose + 1) * 320, (row + 1) * 280)
            anchor = character + "passes"
            let h = actionHand(volleyPasses, character, row * 3 + pose)
            actionBound = PixelRect(0, 270 - h.2, 320, 270)
            handX = Float(h.0 / 320)
            handY = Float(h.1 / 280)
        } else if moving {
            name = character + "_locomotion"
            let running = a.velocity.length() > 3.0
            let row = (back ? 4 : (side ? 2 : 0)) + (running ? 1 : 0)
            let frame = KotlinNumber.int(a.steps * (running ? 2.2 : 2.9)) % 4
            src = PixelRect(frame * 192, row * 240, (frame + 1) * 192, (row + 1) * 240)
            anchor = character + "motion\(row)"
        } else if back || side {
            name = character + "_directions"
            let base: Int
            switch a.pose {
            case "hit", "spike": base = 5
            case "receive", "dive": base = 7
            case "set": base = 4
            case "jump", "block": base = 6
            default: base = 0
            }
            let pose = base + (back ? 8 : 0)
            src = PixelRect(pose % 4 * 192, pose / 4 * 240, (pose % 4 + 1) * 192, (pose / 4 + 1) * 240)
            anchor = character + "dir" + (back ? "1" : "0")
            let h = hand(directions, character, pose)
            handX = Float(h.0 / 256)
            handY = Float(h.1 / 320)
        } else {
            name = character
            let pose: Int
            switch a.pose {
            case "hit", "spike": pose = a.poseTime > 0.28 ? 5 : 6
            case "receive": pose = 3
            case "dive": pose = 10
            case "set": pose = 6
            case "jump", "block": pose = 8
            default: pose = 0
            }
            src = PixelRect(pose % 4 * 256, pose / 4 * 320, (pose % 4 + 1) * 256, (pose / 4 + 1) * 320)
            anchor = character + "front"
            let h = hand(atlas, character, pose)
            handX = Float(h.0 / 256)
            handY = Float(h.1 / 320)
        }
        let bound: PixelRect
        if let actionBound = actionBound {
            bound = actionBound
        } else if let cached = bounds[anchor] {
            bound = cached
        } else {
            let top = anchor.contains("motion") ? src.top : (back ? 480 : 0)
            let neutral = PixelRect(0, top, src.width, top + src.height)
            let made = alpha(name).map { SportsArt.alphaBounds($0, neutral) } ?? PixelRect(0, 0, src.width, src.height)
            bounds[anchor] = made
            bound = made
        }
        let scale = height / Float(max(bound.height, 100))
        let dw = Float(src.width) * scale
        let dh = Float(src.height) * scale
        let left = footX - (Float(bound.left) + Float(bound.width) / 2) * scale
        let top = footY - Float(bound.bottom) * scale
        c.saveGState()
        if flip {
            c.translateBy(x: CGFloat(footX), y: CGFloat(footY))
            c.scaleBy(x: -1, y: 1)
            c.translateBy(x: CGFloat(-footX), y: CGFloat(-footY))
        }
        if let image = cell(name, src) {
            UIGraphicsPushContext(c)
            image.draw(in: CGRect(x: CGFloat(left), y: CGFloat(top), width: CGFloat(dw), height: CGFloat(dh)))
            UIGraphicsPopContext()
        }
        let grip = squash ? gripOnSprite(name, src, handX, handY) : CGPoint(x: CGFloat(handX), y: CGFloat(handY))
        let hand = CGPoint(x: CGFloat(left) + CGFloat(dw) * grip.x, y: CGFloat(top) + CGFloat(dh) * grip.y)
        if squash {
            let angle: CGFloat = a.pose == "hit" ? (a.poseTime > 0.28 ? -55 : 70) : 15
            c.saveGState()
            c.translateBy(x: hand.x, y: hand.y)
            c.rotate(by: angle * .pi / 180)
            c.translateBy(x: -hand.x, y: -hand.y)
            let s = CGFloat(height) * 0.24
            c.setLineCap(.round)
            c.setLineWidth(s * 0.09)
            c.setStrokeColor(SportsPalette.cg(0xff174157))
            c.strokeLineSegments(between: [hand, CGPoint(x: hand.x + s * 0.35, y: hand.y - s * 0.60)])
            let oval = CGRect(x: hand.x + s * 0.08, y: hand.y - s * 1.3, width: s * 0.64, height: s * 0.8)
            c.setStrokeColor(SportsPalette.cg(0xff12becc))
            c.strokeEllipse(in: oval)
            c.setLineWidth(s * 0.025)
            c.setStrokeColor(SportsPalette.cg(0xdceafaff))
            for i in 1...4 {
                let xx = oval.minX + oval.width * CGFloat(i) / 5
                c.strokeLineSegments(between: [CGPoint(x: xx, y: oval.minY + oval.height * 0.15), CGPoint(x: xx, y: oval.maxY - oval.height * 0.15)])
                let yy = oval.minY + oval.height * CGFloat(i) / 5
                c.strokeLineSegments(between: [CGPoint(x: oval.minX + oval.width * 0.12, y: yy), CGPoint(x: oval.maxX - oval.width * 0.12, y: yy)])
            }
            c.restoreGState()
        }
        c.restoreGState()
        return !squash && flip ? CGPoint(x: 2 * CGFloat(footX) - hand.x, y: hand.y) : hand
    }

    /// Android `gripOnSprite`: balloon anchors can lie just beyond a hand; a racket grip must touch
    /// opaque artwork (alpha above 90), or the nearest strongly opaque point to its front.
    func gripOnSprite(_ name: String, _ frame: PixelRect, _ hx: Float, _ hy: Float) -> CGPoint {
        let key = "\(name):\(frame.left):\(frame.top):\(hx):\(hy)"
        if let cached = grips[key] { return cached }
        guard let map = alpha(name) else { return CGPoint(x: CGFloat(hx), y: CGFloat(hy)) }
        let fw = frame.width
        let fh = frame.height
        let x = min(max(KotlinNumber.int(Double(hx * Float(fw))), 0), fw - 1)
        let y = min(max(KotlinNumber.int(Double(hy * Float(fh))), 0), fh - 1)
        let result: CGPoint
        if map.at(frame.left + x, frame.top + y) > 90 {
            result = CGPoint(x: CGFloat(hx), y: CGFloat(hy))
        } else {
            var best = -Float.greatestFiniteMagnitude
            var bx = x
            var by = y
            let loX = max(KotlinNumber.int(Double(Float(x) - Float(fw) * 0.20)), 0)
            let hiX = min(KotlinNumber.int(Double(Float(x) + Float(fw) * 0.12)), fw - 2)
            let loY = max(KotlinNumber.int(Double(Float(y) - Float(fh) * 0.20)), KotlinNumber.int(Double(Float(fh) * 0.18)))
            let hiY = min(KotlinNumber.int(Double(Float(y) + Float(fh) * 0.36)), KotlinNumber.int(Double(Float(fh) * 0.82)))
            if loY <= hiY && loX <= hiX {
                for py in loY...hiY {
                    for px in loX...hiX {
                        if map.at(frame.left + px, frame.top + py) < 180 || map.at(frame.left + max(0, px - 2), frame.top + py) < 100 { continue }
                        let score = Float(px) - Float(abs(py - y)) * 0.06
                        if score > best {
                            best = score
                            bx = px
                            by = py
                        }
                    }
                }
            }
            result = CGPoint(x: CGFloat(Float(bx) / Float(fw)), y: CGFloat(Float(by) / Float(fh)))
        }
        grips[key] = result
        return result
    }
}
