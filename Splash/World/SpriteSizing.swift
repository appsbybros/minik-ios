import CoreGraphics
import UIKit

/// Port of Android world/SpriteSizing.kt: the opaque bounds of a sprite cell (alpha above 96),
/// used to size every character by its visible body instead of its padded cell.
struct SpriteAnchor: Equatable {
    let left: Float
    let top: Float
    let right: Float
    let bottom: Float

    var height: Float { return max(bottom - top, 1) }

    /// Android `destination(x, y, height, w, h, mirrored)`: the cell rectangle that puts the
    /// visible feet at (x, y) with the visible body `height` tall (RectF left, top, right, bottom).
    func destination(_ x: Float, _ y: Float, _ height: Float, _ w: Int, _ h: Int, mirrored: Bool = false) -> CGRect {
        let scale = height / self.height
        let center = mirrored ? Float(w) - (left + right) / 2 : (left + right) / 2
        let l = x - center * scale
        let t = y - bottom * scale
        let r = x + (Float(w) - center) * scale
        let b = y + (Float(h) - bottom) * scale
        return CGRect(x: CGFloat(l), y: CGFloat(t), width: CGFloat(r - l), height: CGFloat(b - t))
    }
}

enum SpriteSizing {
    /// Alpha bounding box of `frame` inside `image` (pixels), or the whole cell when empty.
    static func anchor(_ image: CGImage, _ frame: CGRect) -> SpriteAnchor {
        let w = Int(frame.width)
        let h = Int(frame.height)
        guard w > 0, h > 0, let cell = image.cropping(to: frame), cell.width == w, cell.height == h,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return SpriteAnchor(left: 0, top: 0, right: Float(max(w, 1)), bottom: Float(max(h, 1)))
        }
        context.setBlendMode(.copy)
        context.draw(cell, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = context.data else {
            return SpriteAnchor(left: 0, top: 0, right: Float(w), bottom: Float(h))
        }
        let pixels = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var left = w
        var right = -1
        var top = h
        var bottom = -1
        // CGContext rows start at the top of the drawn image (row 0 = cell top).
        for y in 0..<h {
            let row = y * w * 4
            for x in 0..<w where pixels[row + x * 4 + 3] > 96 {
                left = min(left, x)
                right = max(right, x)
                top = min(top, y)
                bottom = max(bottom, y)
            }
        }
        if right < left { return SpriteAnchor(left: 0, top: 0, right: Float(w), bottom: Float(h)) }
        return SpriteAnchor(left: Float(left), top: Float(top), right: Float(right + 1), bottom: Float(bottom + 1))
    }

    /// A 256 x 320 portrait with the visible body at most 280 tall and 240 wide, feet at y 304.
    static func portrait(_ image: CGImage, _ frame: CGRect, _ anchor: SpriteAnchor) -> UIImage? {
        guard let cell = image.cropping(to: frame) else { return nil }
        let h = min(Float(280), Float(240) * anchor.height / max(anchor.right - anchor.left, 1))
        let target = anchor.destination(128, 304, h, Int(frame.width), Int(frame.height))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 256, height: 320), format: format)
        let drawn = UIImage(cgImage: cell, scale: 1, orientation: .up)
        return renderer.image { context in
            context.cgContext.interpolationQuality = .high
            drawn.draw(in: target)
        }
    }
}
