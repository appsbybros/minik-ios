import UIKit

/// Android `world/SpriteAnchor`: the opaque bounds of a character cell, used to stand every character on its feet at
/// the same visible height whatever empty margin its art has.
struct SpriteAnchor: Equatable {
    let left: CGFloat
    let top: CGFloat
    let right: CGFloat
    let bottom: CGFloat

    var height: CGFloat { return max(bottom - top, 1) }

    /// Where a `w`x`h` cell is drawn so its opaque part is `height` tall with the feet centered on (`x`, `y`).
    func destination(_ x: CGFloat, _ y: CGFloat, _ height: CGFloat, _ w: CGFloat, _ h: CGFloat, mirrored: Bool = false) -> CGRect {
        let scale = height / self.height
        let center = mirrored ? w - (left + right) / 2 : (left + right) / 2
        let minX = x - center * scale
        let minY = y - bottom * scale
        return CGRect(x: minX, y: minY, width: (x + (w - center) * scale) - minX, height: (y + (h - bottom) * scale) - minY)
    }
}

/// Android `world/SpriteSizing`.
enum SpriteSizing {
    /// The bounds of the pixels whose alpha is above 96 (the whole cell when it is empty).
    static func anchor(_ cell: UIImage) -> SpriteAnchor {
        guard let image = cell.cgImage else { return SpriteAnchor(left: 0, top: 0, right: 256, bottom: 320) }
        let w = image.width
        let h = image.height
        if w <= 0 || h <= 0 { return SpriteAnchor(left: 0, top: 0, right: 256, bottom: 320) }
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        if !drawn { return SpriteAnchor(left: 0, top: 0, right: CGFloat(w), bottom: CGFloat(h)) }
        var left = w
        var right = -1
        var top = h
        var bottom = -1
        // The bitmap context's first row in memory is the top of the image.
        for y in 0..<h {
            for x in 0..<w where pixels[(y * w + x) * 4 + 3] > 96 {
                left = min(left, x)
                right = max(right, x)
                top = min(top, y)
                bottom = max(bottom, y)
            }
        }
        if right < left { return SpriteAnchor(left: 0, top: 0, right: CGFloat(w), bottom: CGFloat(h)) }
        return SpriteAnchor(left: CGFloat(left), top: CGFloat(top), right: CGFloat(right + 1), bottom: CGFloat(bottom + 1))
    }

    /// Android `SpriteSizing.portrait`: a 256x320 portrait with the character standing at (128, 304).
    static func portrait(_ cell: UIImage, _ anchor: SpriteAnchor) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 256, height: 320), format: format)
        let w = cell.size.width * cell.scale
        let h = cell.size.height * cell.scale
        let height = min(280, 240 * anchor.height / max(anchor.right - anchor.left, 1))
        let rect = anchor.destination(128, 304, height, w, h)
        return renderer.image { _ in
            cell.draw(in: rect)
        }
    }
}
