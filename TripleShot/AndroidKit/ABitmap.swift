import CoreGraphics
import Foundation
import ImageIO

// android.graphics.Bitmap and BitmapFactory (VIEW-API "Graphics"). A bitmap is either an immutable decoded image
// (resources, BitmapFactory) or a mutable premultiplied RGBA8888 sRGB pixel buffer (createBitmap) that an
// ACanvas can draw into. Pixel coordinates are top-left based like Android.

final class ABitmap: CustomStringConvertible {
    enum Config { case ARGB_8888, RGB_565, ALPHA_8 }

    let width: Int
    let height: Int
    let config: Config
    let isMutable: Bool
    private(set) var isRecycled = false

    private var image: CGImage?
    private var context: CGContext?
    /// Pixel buffer of an immutable image, made on the first pixel read.
    private var readback: CGContext?

    /// An immutable bitmap of a decoded image (pixel size = the image's size).
    init(cgImage: CGImage) {
        width = cgImage.width
        height = cgImage.height
        config = .ARGB_8888
        isMutable = false
        image = cgImage
    }

    private init(mutableWidth w: Int, height h: Int, config: Config) {
        width = w
        height = h
        self.config = config
        isMutable = true
        context = ABitmap.makeContext(w, h)
    }

    var description: String { return "android.graphics.Bitmap(\(width)x\(height))" }

    static func makeContext(_ w: Int, _ h: Int) -> CGContext? {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: KitGraphics.sRGB,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
        ctx?.clear(CGRect(x: 0, y: 0, width: w, height: h))
        return ctx
    }

    // MARK: Creation

    /// `Bitmap.createBitmap(width, height, config)`: a mutable, fully transparent bitmap.
    static func createBitmap(_ width: Int, _ height: Int, _ config: Config) -> ABitmap {
        precondition(width > 0 && height > 0, "java.lang.IllegalArgumentException: width and height must be > 0")
        return ABitmap(mutableWidth: width, height: height, config: config)
    }

    /// `Bitmap.createBitmap(colors, width, height, config)`: an immutable bitmap of ARGB colours (row-major).
    static func createBitmap(_ colors: [Int], _ width: Int, _ height: Int, _ config: Config) -> ABitmap {
        precondition(width > 0 && height > 0, "java.lang.IllegalArgumentException: width and height must be > 0")
        precondition(colors.count >= width * height, "java.lang.ArrayIndexOutOfBoundsException")
        let b = ABitmap(mutableWidth: width, height: height, config: config)
        for y in 0..<height {
            for x in 0..<width {
                b.writePixel(x, y, colors[y * width + x])
            }
        }
        if let img = b.context?.makeImage() {
            return ABitmap(cgImage: img)
        }
        return b
    }

    /// `Bitmap.createBitmap(source)`.
    static func createBitmap(_ source: ABitmap) -> ABitmap {
        return createBitmap(source, 0, 0, source.width, source.height)
    }

    /// `Bitmap.createBitmap(source, x, y, width, height)`.
    static func createBitmap(_ source: ABitmap, _ x: Int, _ y: Int, _ width: Int, _ height: Int) -> ABitmap {
        return createBitmap(source, x, y, width, height, nil, false)
    }

    /// `Bitmap.createBitmap(source, x, y, width, height, m, filter)`: the subset, transformed by `m`; the source
    /// itself when it is immutable and nothing changes (Android).
    static func createBitmap(_ source: ABitmap, _ x: Int, _ y: Int, _ width: Int, _ height: Int,
                             _ m: AMatrix?, _ filter: Bool) -> ABitmap {
        precondition(x >= 0, "java.lang.IllegalArgumentException: x must be >= 0")
        precondition(y >= 0, "java.lang.IllegalArgumentException: y must be >= 0")
        precondition(width > 0, "java.lang.IllegalArgumentException: width must be > 0")
        precondition(height > 0, "java.lang.IllegalArgumentException: height must be > 0")
        precondition(x + width <= source.width, "java.lang.IllegalArgumentException: x + width must be <= bitmap.width()")
        precondition(y + height <= source.height, "java.lang.IllegalArgumentException: y + height must be <= bitmap.height()")
        precondition(!source.isRecycled, "java.lang.IllegalArgumentException: cannot use a recycled source in createBitmap")

        // check if we can just return our argument unchanged
        if !source.isMutable && x == 0 && y == 0 && width == source.width && height == source.height
            && (m == nil || m!.isIdentity()) {
            return source
        }

        var neww = width
        var newh = height
        let srcR = ARect(x, y, x + width, y + height)
        let dstR = ARectF(0, 0, Float(width), Float(height))
        let deviceR = ARectF()
        var paint: APaint?
        var newConfig = source.config
        if let matrix = m, !matrix.isIdentity() {
            let transformed = !matrix.rectStaysRect()
            matrix.mapRect(deviceR, dstR)
            neww = KitGraphics.mathRound(deviceR.width())
            newh = KitGraphics.mathRound(deviceR.height())
            if transformed && newConfig != .ARGB_8888 { newConfig = .ARGB_8888 }
            let p = APaint()
            p.isFilterBitmap = filter
            if transformed { p.isAntiAlias = true }
            paint = p
        }
        let bitmap = createBitmap(neww, newh, newConfig)
        let canvas = ACanvas(bitmap)
        canvas.translate(-deviceR.left, -deviceR.top)
        if let matrix = m { canvas.concat(matrix) }
        canvas.drawBitmap(source, srcR, dstR, paint)
        return bitmap
    }

    /// `Bitmap.createScaledBitmap(src, dstWidth, dstHeight, filter)`.
    static func createScaledBitmap(_ src: ABitmap, _ dstWidth: Int, _ dstHeight: Int, _ filter: Bool) -> ABitmap {
        let m = AMatrix()
        let width = src.width
        let height = src.height
        if width != dstWidth || height != dstHeight {
            let sx = Float(dstWidth) / Float(width)
            let sy = Float(dstHeight) / Float(height)
            m.setScale(sx, sy)
        }
        return createBitmap(src, 0, 0, width, height, m, filter)
    }

    /// `copy(config, isMutable)`.
    func copy(_ config: Config, _ isMutable: Bool) -> ABitmap? {
        guard !isRecycled, let img = cgImage else { return nil }
        if !isMutable {
            return ABitmap(cgImage: img)
        }
        let b = ABitmap(mutableWidth: width, height: height, config: config)
        b.context?.draw(img, in: CGRect(x: 0, y: 0, width: width, height: height))
        return b
    }

    // MARK: State

    /// The current pixels as an image (a snapshot for a mutable bitmap); nil once recycled.
    var cgImage: CGImage? {
        if isRecycled { return nil }
        if let c = context { return c.makeImage() }
        return image
    }

    /// The drawing context of a mutable bitmap (y-up Core Graphics space; ACanvas flips it).
    var kgContext: CGContext? {
        return isRecycled ? nil : context
    }

    /// `recycle()`: frees the pixels; drawing or reading the bitmap afterwards is an error like Android.
    func recycle() {
        isRecycled = true
        image = nil
        context = nil
        readback = nil
    }

    var hasAlpha: Bool { return config != .RGB_565 }

    private var bytesPerPixel: Int {
        switch config {
        case .ARGB_8888: return 4
        case .RGB_565: return 2
        case .ALPHA_8: return 1
        }
    }

    var rowBytes: Int { return width * bytesPerPixel }
    var byteCount: Int { return rowBytes * height }
    var allocationByteCount: Int { return byteCount }

    func getWidth() -> Int { return width }
    func getHeight() -> Int { return height }

    // MARK: Pixels

    private func pixelContext() -> CGContext? {
        if let c = context { return c }
        if let r = readback { return r }
        guard let img = image, let r = ABitmap.makeContext(width, height) else { return nil }
        r.draw(img, in: CGRect(x: 0, y: 0, width: width, height: height))
        readback = r
        return r
    }

    private func checkPixelAccess(_ x: Int, _ y: Int) {
        precondition(x >= 0, "java.lang.IllegalArgumentException: x must be >= 0")
        precondition(y >= 0, "java.lang.IllegalArgumentException: y must be >= 0")
        precondition(x < width, "java.lang.IllegalArgumentException: x must be < bitmap.width()")
        precondition(y < height, "java.lang.IllegalArgumentException: y must be < bitmap.height()")
    }

    /// Unpremultiplied ARGB of a stored premultiplied RGBA pixel (memory row 0 = top row).
    private func readPixel(_ ctx: CGContext, _ x: Int, _ y: Int) -> Int {
        guard let data = ctx.data else { return 0 }
        let p = data.assumingMemoryBound(to: UInt8.self)
        let o = y * ctx.bytesPerRow + x * 4
        let a = Int(p[o + 3])
        if a == 0 { return 0 }
        func unpremul(_ c: UInt8) -> Int {
            if a == 255 { return Int(c) }
            let v = min(Float(1), (Float(c) / 255) / (Float(a) / 255))
            return KitGraphics.javaInt(v * 255 + 0.5)
        }
        var r = unpremul(p[o]), g = unpremul(p[o + 1]), b = unpremul(p[o + 2])
        var alpha = a
        switch config {
        case .ALPHA_8: r = 0; g = 0; b = 0
        case .RGB_565: alpha = 255
        case .ARGB_8888: break
        }
        return AColor.argb(alpha, r, g, b)
    }

    private func writePixel(_ x: Int, _ y: Int, _ color: Int) {
        guard let ctx = context, let data = ctx.data else { return }
        let p = data.assumingMemoryBound(to: UInt8.self)
        let o = y * ctx.bytesPerRow + x * 4
        let a = config == .RGB_565 ? 255 : AColor.alpha(color)
        func premul(_ c: Int) -> UInt8 {
            if config == .ALPHA_8 { return 0 }
            // SkMulDiv255Round
            let prod = c * a + 128
            return UInt8((prod + (prod >> 8)) >> 8)
        }
        p[o] = premul(AColor.red(color))
        p[o + 1] = premul(AColor.green(color))
        p[o + 2] = premul(AColor.blue(color))
        p[o + 3] = UInt8(a)
    }

    /// `getPixel(x, y)`: the unpremultiplied ARGB colour.
    func getPixel(_ x: Int, _ y: Int) -> Int {
        precondition(!isRecycled, "java.lang.IllegalStateException: Can't call getPixel() on a recycled bitmap")
        checkPixelAccess(x, y)
        guard let ctx = pixelContext() else { return 0 }
        return readPixel(ctx, x, y)
    }

    /// `getPixels(pixels, offset, stride, x, y, width, height)`.
    func getPixels(_ pixels: inout [Int], _ offset: Int, _ stride: Int, _ x: Int, _ y: Int, _ width: Int, _ height: Int) {
        precondition(!isRecycled, "java.lang.IllegalStateException: Can't call getPixels() on a recycled bitmap")
        if width == 0 || height == 0 { return }
        checkPixelAccess(x, y)
        precondition(x + width <= self.width, "java.lang.IllegalArgumentException: x + width must be <= bitmap.width()")
        precondition(y + height <= self.height, "java.lang.IllegalArgumentException: y + height must be <= bitmap.height()")
        precondition(abs(stride) >= width, "java.lang.IllegalArgumentException: abs(stride) must be >= width")
        guard let ctx = pixelContext() else { return }
        for row in 0..<height {
            for col in 0..<width {
                pixels[offset + row * stride + col] = readPixel(ctx, x + col, y + row)
            }
        }
    }

    /// `setPixel(x, y, color)` (mutable bitmaps only).
    func setPixel(_ x: Int, _ y: Int, _ color: Int) {
        precondition(!isRecycled, "java.lang.IllegalStateException: Can't call setPixel() on a recycled bitmap")
        precondition(isMutable, "java.lang.IllegalStateException")
        checkPixelAccess(x, y)
        writePixel(x, y, color)
    }

    /// `eraseColor(color)`: every pixel replaced by the colour.
    func eraseColor(_ color: Int) {
        precondition(!isRecycled, "java.lang.IllegalStateException: Can't erase a recycled bitmap")
        precondition(isMutable, "java.lang.IllegalStateException: cannot erase immutable bitmaps")
        guard let ctx = context else { return }
        ctx.saveGState()
        ctx.setBlendMode(.copy)
        ctx.setFillColor(AColor.cgColor(color))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.restoreGState()
    }
}

// MARK: - BitmapFactory

/// android.graphics.BitmapFactory for the app's drawables (by resource name) and encoded bytes.
enum ABitmapFactory {
    /// `BitmapFactory.Options`.
    final class Options {
        var inJustDecodeBounds = false
        /// Values <= 1 decode at full size.
        var inSampleSize = 0
        var inScaled = true
        var inMutable = false
        var inPreferredConfig: ABitmap.Config? = .ARGB_8888
        var inPremultiplied = true
        var inDensity = 0
        var inTargetDensity = 0
        var inScreenDensity = 0
        var outWidth = 0
        var outHeight = 0
        var outMimeType: String?
        init() {}
    }

    /// `BitmapFactory.decodeResource(res, id, opts)` (`res` is the app's resources).
    static func decodeResource(_ res: AResources.Type, _ id: ADrawableRes, _ opts: Options?) -> ABitmap? {
        return decodeResource(id, opts)
    }

    static func decodeResource(_ res: AResources.Type, _ id: ADrawableRes) -> ABitmap? {
        return decodeResource(id, nil)
    }

    static func decodeResource(_ id: ADrawableRes) -> ABitmap? {
        return decodeResource(id, nil)
    }

    /// Decodes an image resource like Android: `inSampleSize` subsamples (WebP rounds the sampled size,
    /// other formats floor it), drawable/ (mdpi) images are scaled by densityDpi / 160 when `inScaled`,
    /// drawable-nodpi images keep their pixel size. `inJustDecodeBounds` only fills outWidth/outHeight.
    static func decodeResource(_ id: ADrawableRes, _ opts: Options?) -> ABitmap? {
        opts?.outWidth = -1
        opts?.outHeight = -1
        guard let file = AResources.drawables[id], file.width > 0, file.height > 0 else { return nil }
        let isWebp = file.file.lowercased().hasSuffix(".webp")
        let isMdpi = file.file.hasPrefix("drawable/")
        var w = file.width, h = file.height
        let sample = opts?.inSampleSize ?? 0
        if sample > 1 {
            w = sampledDimension(w, sample, isWebp)
            h = sampledDimension(h, sample, isWebp)
        }
        if (opts?.inScaled ?? true) && isMdpi {
            let densityDpi = Int((AResources.density * 160).rounded())
            let scale = Float(densityDpi) / Float(160)
            if scale != 1 {
                w = KitGraphics.javaInt(Float(w) * scale + 0.5)
                h = KitGraphics.javaInt(Float(h) * scale + 0.5)
            }
        }
        if let o = opts {
            o.outWidth = w
            o.outHeight = h
            o.outMimeType = isWebp ? "image/webp" : (file.file.lowercased().hasSuffix(".png") ? "image/png" : "image/jpeg")
            if o.inJustDecodeBounds { return nil }
        }
        guard let image = AResources.cgImage(id) else { return nil }
        return finish(image, w, h, opts?.inMutable ?? false)
    }

    /// `BitmapFactory.decodeByteArray(data, offset, length, opts)`.
    static func decodeByteArray(_ data: [UInt8], _ offset: Int, _ length: Int, _ opts: Options?) -> ABitmap? {
        precondition(offset >= 0 && length >= 0 && offset + length <= data.count, "java.lang.ArrayIndexOutOfBoundsException")
        return decodeData(Data(data[offset..<(offset + length)]), opts)
    }

    static func decodeByteArray(_ data: [UInt8], _ offset: Int, _ length: Int) -> ABitmap? {
        return decodeByteArray(data, offset, length, nil)
    }

    /// Decodes encoded image bytes (PNG, JPEG, WebP, ...).
    static func decodeData(_ data: Data, _ opts: Options?) -> ABitmap? {
        opts?.outWidth = -1
        opts?.outHeight = -1
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pw = props[kCGImagePropertyPixelWidth] as? Int, let ph = props[kCGImagePropertyPixelHeight] as? Int,
              pw > 0, ph > 0 else { return nil }
        let type = (CGImageSourceGetType(source) as String?) ?? ""
        let isWebp = type.lowercased().contains("webp")
        var w = pw, h = ph
        let sample = opts?.inSampleSize ?? 0
        if sample > 1 {
            w = sampledDimension(w, sample, isWebp)
            h = sampledDimension(h, sample, isWebp)
        }
        if let o = opts {
            o.outWidth = w
            o.outHeight = h
            o.outMimeType = isWebp ? "image/webp" : (type.contains("png") ? "image/png" : (type.contains("jpeg") ? "image/jpeg" : nil))
            if o.inJustDecodeBounds { return nil }
        }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return finish(image, w, h, opts?.inMutable ?? false)
    }

    /// SkAndroidCodec sampled size: WebP scales natively (`round(dim / sample)`), others floor (min 1).
    private static func sampledDimension(_ dim: Int, _ sample: Int, _ isWebp: Bool) -> Int {
        if isWebp {
            let scale = Float(1) / Float(sample)
            return max(1, KitGraphics.javaInt((scale * Float(dim) + 0.5).rounded(.down)))
        }
        if sample > dim { return 1 }
        return dim / sample
    }

    private static func finish(_ image: CGImage, _ w: Int, _ h: Int, _ mutable: Bool) -> ABitmap? {
        if w == image.width && h == image.height && !mutable {
            return ABitmap(cgImage: image)
        }
        let b = ABitmap.createBitmap(w, h, .ARGB_8888)
        guard let ctx = b.kgContext else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        if mutable { return b }
        if let img = ctx.makeImage() { return ABitmap(cgImage: img) }
        return b
    }
}
