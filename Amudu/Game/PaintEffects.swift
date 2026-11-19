import UIKit

/// Android `PaintEffects`: small procedural textures, clipped to the actual animated sprite alpha — paint patches on
/// players hit by the paint balloon, ground splashes with their droplets, and the balloon itself.
final class PaintEffects {
    private struct Surface {
        let field: [Double]
        let visible: [Int]
    }

    private var surfaces: [String: Surface] = [:]
    private var textures: [String: UIImage] = [:]

    private static let maskWidth = 96
    private static let maskHeight = 192

    /// Android `body`: draws the actor's paint over the sprite already drawn in `rect` (inside a transparency layer, so
    /// `sourceAtop` keeps it on the sprite's own pixels; mirroring is inherited from the caller's transform). `sprite`
    /// is the current cell (Android passes the sheet and the cell rectangle). The face oval stays unpainted.
    func body(_ ctx: CGContext, _ rect: CGRect, _ a: GameActor, _ rules: RuleSet, _ sprite: UIImage, _ face: CGRect? = nil) {
        if a.paintHits.isEmpty { return }
        let hits = a.paintHits.map { UInt32(truncatingIfNeeded: $0) }
        let key = a.member.id + ":" + rules.rawValue + ":" + hits.map { String(Int32(bitPattern: $0)) }.joined(separator: ",")
        let texture: UIImage
        if let cached = textures[key] {
            texture = cached
        } else {
            if textures.count > 30 { textures.removeAll() }
            let surface: Surface
            if let known = surfaces[a.member.id] {
                surface = known
            } else {
                surface = PaintEffects.surface(a.member.id, sprite)
                surfaces[a.member.id] = surface
            }
            texture = PaintEffects.texture(surface, hits, rules)
            textures[key] = texture
        }
        ctx.saveGState()
        if let f = face {
            // Excluded eyes/mouth do not redistribute nominal paint coverage elsewhere.
            let oval = CGRect(x: rect.minX + rect.width * f.minX, y: rect.minY + rect.height * f.minY,
                              width: rect.width * f.width, height: rect.height * f.height)
            ctx.addRect(ctx.boundingBoxOfClipPath.union(rect))
            ctx.addEllipse(in: oval)
            ctx.clip(using: .evenOdd)
        }
        texture.draw(in: rect, blendMode: .sourceAtop, alpha: 1)
        ctx.restoreGState()
    }

    /// Allocate each colour by visible silhouette area, not transparent atlas area. The first painted pose is cached so
    /// patches remain stable during animation.
    private static func surface(_ id: String, _ sprite: UIImage) -> Surface {
        let mw = maskWidth
        let mh = maskHeight
        var random = KotlinRandom(seed: Int64(Kotlin.hashCode(id)))
        var cells: [(Double, Double, Int)] = []
        for i in 0..<48 {
            let u = random.nextDouble()
            let v = random.nextDouble()
            cells.append((u, v, i))
        }
        // Kotlin `cells.indices.shuffled(random)`: Fisher–Yates from the last index down.
        var order = Array(0..<cells.count)
        var i = order.count - 1
        while i >= 1 {
            let j = Int(random.nextInt(until: Int32(i + 1)))
            order.swapAt(i, j)
            i -= 1
        }
        var rank = [Int](repeating: 0, count: cells.count)
        for (n, j) in order.enumerated() { rank[j] = n }
        let alpha = PaintEffects.alphaMask(sprite, mw, mh)
        var field = [Double](repeating: 0, count: mw * mh)
        var waveX = [[Double]](repeating: [], count: mw)
        for x in 0..<mw { waveX[x] = (0..<cells.count).map { sin(Double(x) * 0.28 + Double($0)) } }
        let waveY = (0..<mh).map { sin(Double($0) * 0.19) }
        for y in 0..<mh {
            for x in 0..<mw {
                let u = Double(x) / Double(mw)
                let v = Double(y) / Double(mh)
                var best = 0
                var bestValue = Double.infinity
                for c in cells {
                    let dx = u - c.0
                    let dy = v - c.1
                    let value = dx * dx + dy * dy + 0.0015 * waveX[x][c.2] * waveY[y]
                    if value < bestValue {
                        bestValue = value
                        best = c.2
                    }
                }
                field[y * mw + x] = Double(rank[best]) + 0.5 + 0.25 * waveX[x][best] * waveY[y]
            }
        }
        let visible = Kotlin.stableSorted(field.indices.filter { alpha[$0] > 96 }) { field[$0] < field[$1] }
        let all = Kotlin.stableSorted(Array(field.indices)) { field[$0] < field[$1] }
        return Surface(field: field, visible: visible.isEmpty ? all : visible)
    }

    /// The sprite cell scaled to 96x192 (Android draws it without filtering) and read back as alpha values 0…255.
    private static func alphaMask(_ sprite: UIImage, _ w: Int, _ h: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        guard let cg = sprite.cgImage, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return [UInt8](repeating: 0, count: w * h) }
        bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return }
            context.interpolationQuality = .none
            // CGContext rows start at the bottom; drawing the image unflipped puts its top row in the buffer's first row.
            context.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        var alpha = [UInt8](repeating: 0, count: w * h)
        for i in 0..<(w * h) { alpha[i] = bytes[i * 4 + 3] }
        return alpha
    }

    private static func texture(_ surface: Surface, _ hits: [UInt32], _ rules: RuleSet) -> UIImage {
        let w = maskWidth
        let h = maskHeight
        let field = surface.field
        let visible = surface.visible
        let coverage = PaintBalloon.coverage(hits.count, rules)
        var cutoffs: [Double] = []
        for n in 0..<hits.count {
            // Kotlin `((n + 1) * coverage * visible.size / hits.size).toInt().coerceIn(0, visible.lastIndex)`.
            let raw = Kotlin.toInt(Double(n + 1) * coverage * Double(visible.count) / Double(hits.count))
            cutoffs.append(field[visible[min(max(raw, 0), visible.count - 1)]])
        }
        // Colour (rgb of the hit) with alpha 210, premultiplied for the bitmap context.
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        for i in 0..<field.count {
            guard let index = cutoffs.firstIndex(where: { field[i] <= $0 }) else { continue }
            let color = hits[index]
            let r = Int((color >> 16) & 0xff)
            let g = Int((color >> 8) & 0xff)
            let b = Int(color & 0xff)
            bytes[i * 4] = UInt8((r * 210 + 127) / 255)
            bytes[i * 4 + 1] = UInt8((g * 210 + 127) / 255)
            bytes[i * 4 + 2] = UInt8((b * 210 + 127) / 255)
            bytes[i * 4 + 3] = 210
        }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return UIImage() }
        let image: CGImage? = bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return nil }
            return context.makeImage()
        }
        guard let image else { return UIImage() }
        return UIImage(cgImage: image, scale: 1, orientation: .up)
    }

    /// Android `ground`: the splash patches on the ground (alpha 180) and, for 0.65 s, the flying droplets. `project`
    /// is the arena's ball-height projection; `pixel` is one device pixel in points (Android's droplet radius is in px).
    func ground(_ ctx: CGContext, _ s: PaintSplash, _ at: Double, pixel: CGFloat, _ project: (V, Double) -> CGPoint) {
        var random = KotlinRandom(seed: Int64(s.seed))
        let color = UInt32(truncatingIfNeeded: s.color) & 0x00ffffff
        let scale = sqrt(Kotlin.clamp(s.areaScale, 1.0, 1.25))
        ctx.setFillColor(argbColor(color | (180 << 24)).cgColor)
        for _ in 0..<10 {
            let angle = random.nextDouble() * 2 * Double.pi
            let distance = random.nextDouble() * 0.65 * scale
            let radius = (0.12 + random.nextDouble() * 0.24) * scale
            let centre = s.position + V(cos(angle), sin(angle)) * distance
            for i in 0..<17 {
                let t = Double(i) * 2 * Double.pi / 16
                let p = project(centre + V(cos(t), sin(t)) * radius, 0.025)
                if i == 0 { ctx.move(to: p) } else { ctx.addLine(to: p) }
            }
            ctx.closePath()
            ctx.fillPath()
        }
        let age = at - s.at
        if age >= 0.0 && age <= 0.65 {
            let alpha = UInt32(max(0, min(255, Kotlin.toInt((1 - age / 0.65) * 255))))
            ctx.setFillColor(argbColor(color | (alpha << 24)).cgColor)
            for i in 0..<12 {
                let angle = Double(i) * 2 * Double.pi / 12
                let p = project(s.position + V(cos(angle), sin(angle)) * (age * 2.0), 0.25 + age * 2 - age * age * 3)
                let r = max(CGFloat(4 * (1 - age / 0.65)), 1) * pixel
                ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            }
        }
    }

    /// Android `PaintEffects.balloon()` in the first paint colour.
    static func balloon() -> UIImage {
        return balloon(UInt32(truncatingIfNeeded: PaintBalloon.colors[0]))
    }

    /// Android `PaintEffects.balloon(color)`: a 192x192 balloon in the actual hue with untinted gloss. (Multiplying a
    /// grey ball by yellow made most of its body ochre, indistinguishable from the beach.)
    static func balloon<C: BinaryInteger>(_ value: C) -> UIImage {
        let color = UInt32(truncatingIfNeeded: value)
        let red = Double((color >> 16) & 0xff)
        let green = Double((color >> 8) & 0xff)
        let blue = Double(color & 0xff)
        func mix(_ to: UInt32, _ t: Double) -> UIColor {
            let r = (red * (1 - t) + Double((to >> 16) & 0xff) * t).rounded()
            let g = (green * (1 - t) + Double((to >> 8) & 0xff) * t).rounded()
            let b = (blue * (1 - t) + Double(to & 0xff) * t).rounded()
            return UIColor(red: CGFloat(r / 255), green: CGFloat(g / 255), blue: CGFloat(b / 255), alpha: 1)
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 192, height: 192), format: format)
        return renderer.image { context in
            let c = context.cgContext
            let shape = CGMutablePath()
            shape.move(to: CGPoint(x: 96, y: 166))
            shape.addCurve(to: CGPoint(x: 36, y: 70), control1: CGPoint(x: 49, y: 149), control2: CGPoint(x: 28, y: 113))
            shape.addCurve(to: CGPoint(x: 156, y: 70), control1: CGPoint(x: 45, y: 12), control2: CGPoint(x: 146, y: 12))
            shape.addCurve(to: CGPoint(x: 96, y: 166), control1: CGPoint(x: 165, y: 113), control2: CGPoint(x: 143, y: 149))
            shape.closeSubpath()
            let opaque = argbColor(color | 0xff000000)
            let colors = [mix(0xffffffff, 0.32).cgColor, opaque.cgColor, opaque.cgColor, mix(0xff000000, 0.17).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.28, 0.72, 1]) {
                c.saveGState()
                c.addPath(shape)
                c.clip()
                c.drawRadialGradient(gradient, startCenter: CGPoint(x: 68, y: 55), startRadius: 0, endCenter: CGPoint(x: 68, y: 55),
                                     endRadius: 139, options: [.drawsAfterEndLocation])
                c.restoreGState()
            }
            let knot = CGMutablePath()
            knot.move(to: CGPoint(x: 92, y: 161))
            knot.addLine(to: CGPoint(x: 87, y: 176))
            knot.addQuadCurve(to: CGPoint(x: 106, y: 176), control: CGPoint(x: 96, y: 182))
            knot.addLine(to: CGPoint(x: 100, y: 161))
            knot.closeSubpath()
            c.setFillColor(mix(0xff000000, 0.10).cgColor)
            c.addPath(knot)
            c.fillPath()
            c.saveGState()
            c.translateBy(x: 65, y: 62)
            c.rotate(by: 25 * CGFloat.pi / 180)
            c.translateBy(x: -65, y: -62)
            c.setFillColor(argbColor(0xb2ffffff).cgColor)
            c.fillEllipse(in: CGRect(x: 52, y: 39, width: 17, height: 41))
            c.restoreGState()
        }
    }
}
