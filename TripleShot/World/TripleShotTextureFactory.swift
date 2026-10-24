import CoreGraphics
import Foundation
import ImageIO
import Metal

// The texture preparation of view/TripleShotGpuWorldView.kt (TripleShotGame 6c38131): `decode` (lines 87-96) and
// `prepareActor` (lines 97-139), statement by statement (spec 06 sections 4.3, 7 and 9.3), plus the pixel upload of
// TripleShotPremiumRenderer.upload (GLUtils.texImage2D, lines 124-133). Everything here runs on the preparation
// worker (a serial queue, like Android's single-thread executor) and touches no view or renderer state.
//
// Android Bitmap work -> AndroidKit ABitmap/ACanvas/APaint (CoreGraphics, premultiplied RGBA8888 sRGB, row 0 = top):
//  - BitmapFactory bounds decodes (`inJustDecodeBounds`, `inScaled = false`) read the pixel size table
//    (ABitmapFactory, no image I/O); the pixel decode is ImageIO (WebP/PNG, native pixels, not cached), sampled
//    like Skia's SkAndroidCodec for `inSampleSize` (WebP scales natively and rounds the size, PNG floors it, JPEG
//    ceils it) and drawn into a mutable bitmap of exactly that size;
//  - Bitmap.createScaledBitmap(filter = true), Canvas.drawBitmap with Paint(ANTI_ALIAS | FILTER_BITMAP) and the
//    transparent ARGB_8888 atlas are the AndroidKit equivalents (bilinear, Skia kLinear without mipmaps);
//  - the vector fallback rasterises TripleShotPlayerRenderer's legacy drawing into a 512 x 512 bitmap through
//    ACanvas, exactly like Kotlin's Canvas(bitmap);
//  - the upload copies the premultiplied RGBA bytes into an .rgba8Unorm MTLTexture (GLUtils.texImage2D uploads an
//    Android bitmap as stored: premultiplied, row 0 = image top = v 0).
// Kotlin `require(...)` / `requireNotNull(...)` failures are thrown (the worker catches and logs them, like Android).
// Region keys are the frame drawable names (Android: resIds); the vector fallback's region key 0 is
// `TripleShotPreparedTexture.VECTOR_REGION`.

enum TripleShotTextureFactory {
    /// The IllegalArgumentException of Kotlin `require` / `requireNotNull` (logged by the worker).
    struct PrepareError: Error, CustomStringConvertible {
        let description: String
    }

    /// Kotlin `data class Slot(id, x, y, w, h, sw, sh)` local to prepareActor: an atlas cell and the frame's
    /// ORIGINAL pixel size.
    struct Slot: Equatable {
        let id: ADrawableRes
        let x: Int
        let y: Int
        let w: Int
        let h: Int
        let sw: Int
        let sh: Int
    }

    /// Kotlin `decode(id, maxEdge)`: power-of-two subsampled decode, then a bilinear downscale to `maxEdge`.
    static func decode(id: ADrawableRes, maxEdge: Int) throws -> ABitmap {
        let opts = ABitmapFactory.Options()
        opts.inJustDecodeBounds = true; opts.inScaled = false; opts.inSampleSize = 1
        _ = ABitmapFactory.decodeResource(AResources.self, id, opts)
        opts.inJustDecodeBounds = false
        while Swift.max(opts.outWidth, opts.outHeight) / opts.inSampleSize > maxEdge * 2 { opts.inSampleSize *= 2 }
        guard let bitmap = decodeResource(id: id, opts: opts) else {
            throw PrepareError(description: "java.lang.IllegalArgumentException: Required value was null. (\(id))")
        }
        if Swift.max(bitmap.width, bitmap.height) <= maxEdge { return bitmap }
        let factor: Float = maxEdge.toFloat() / Swift.max(bitmap.width, bitmap.height).toFloat()
        let scaled = ABitmap.createScaledBitmap(bitmap, Swift.max(1, (bitmap.width.toFloat() * factor).toInt()),
                                                Swift.max(1, (bitmap.height.toFloat() * factor).toInt()), true)
        bitmap.recycle()
        return scaled
    }

    /// `BitmapFactory.decodeResource(resources, id, opts)` for the pixels: ImageIO, honouring `inSampleSize` (Skia's
    /// sampled dimensions) and `inScaled` (drawable/ = mdpi, scaled by densityDpi / 160; drawable-nodpi never). The
    /// result is a mutable premultiplied RGBA bitmap of exactly the Android size (outWidth x outHeight).
    static func decodeResource(id: ADrawableRes, opts: ABitmapFactory.Options) -> ABitmap? {
        opts.outWidth = -1
        opts.outHeight = -1
        guard let file = AResources.drawables[id], file.width > 0, file.height > 0 else { return nil }
        let format = file.file.lowercased().split(separator: ".").last.map(String.init) ?? ""
        var w = file.width
        var h = file.height
        if opts.inSampleSize > 1 {
            w = sampledDimension(w, opts.inSampleSize, format)
            h = sampledDimension(h, opts.inSampleSize, format)
        }
        if opts.inScaled && file.file.hasPrefix("drawable/") {
            let densityDpi = Int((AResources.density * 160).rounded())
            let scale = densityDpi.toFloat() / 160
            if scale != 1 {
                w = (w.toFloat() * scale + 0.5).toInt()
                h = (h.toFloat() * scale + 0.5).toInt()
            }
        }
        opts.outWidth = w
        opts.outHeight = h
        if opts.inJustDecodeBounds { return nil }
        guard let url = AResources.drawableURL(id),
              let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let bitmap = ABitmap.createBitmap(w, h, .ARGB_8888)
        guard let ctx = bitmap.kgContext else { return nil }
        ctx.saveGState()
        ctx.setBlendMode(.copy)
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        ctx.restoreGState()
        return bitmap
    }

    /// SkAndroidCodec's sampled size for `inSampleSize`: WebP decodes natively at `round(dim / sample)` (min 1), JPEG
    /// at libjpeg's `ceil(dim / sample)`, PNG subsamples to `dim / sample` (1 when the sample exceeds the size).
    static func sampledDimension(_ dim: Int, _ sample: Int, _ format: String) -> Int {
        switch format {
        case "webp":
            let scale: Float = 1 / sample.toFloat()
            return Swift.max(1, (scale * dim.toFloat() + 0.5).rounded(.down).toInt())
        case "jpg", "jpeg":
            return (dim + sample - 1) / sample
        default:
            if sample > dim { return 1 }
            return dim / sample
        }
    }

    /// Kotlin `prepareActor(id)`: the character's sprite atlas (2048 wide), or the vector fallback.
    static func prepareActor(id: String) throws -> TripleShotPreparedTexture {
        let set = TripleShotCharacterVisualCatalog.find(characterId: id)
        if set == nil {
            // Preserve the existing vector fallback; this is a one-time rasterization of its code.
            let bitmap = ABitmap.createBitmap(512, 512, ABitmap.Config.ARGB_8888)
            do {
                let canvas = ACanvas(bitmap)
                let scale: Float = 400 / (AResources.density * 120)
                canvas.scale(scale, scale)
                TripleShotPlayerRenderer(context: nil).draw(
                    canvas: canvas,
                    state: TripleShotPlayerRenderer.State(256 / scale, 480 / scale, 0, 0, 0, false, characterId: id)
                )
            }
            return TripleShotPreparedTexture(
                key: "actor:\(id)", bitmap: bitmap,
                regions: [TripleShotPreparedTexture.VECTOR_REGION: TripleShotSpriteRegion(u0: 0, v0: 0, u1: 1, v1: 1, sourceWidth: 512, sourceHeight: 512)]
            )
        }
        let frames = spriteFrames(set: set!, id: id)
        let (slots, height) = try packSlots(frames: frames, id: id)
        let atlas = ABitmap.createBitmap(2048, height, ABitmap.Config.ARGB_8888)
        let canvas = ACanvas(atlas); let paint = APaint(APaint.ANTI_ALIAS_FLAG | APaint.FILTER_BITMAP_FLAG)
        var regions: [ADrawableRes: TripleShotSpriteRegion] = [:]
        for slot in slots {
            let bitmap = try decode(id: slot.id, maxEdge: 768)
            canvas.drawBitmap(bitmap, nil, ARect(slot.x, slot.y, slot.x + slot.w, slot.y + slot.h), paint); bitmap.recycle()
            regions[slot.id] = region(slot: slot, height: height)
        }
        return TripleShotPreparedTexture(key: "actor:\(id)", bitmap: atlas, regions: regions)
    }

    /// prepareActor's region of a slot: atlas UVs (2048 wide, `height` high) and the frame's original pixel size.
    static func region(slot: Slot, height: Int) -> TripleShotSpriteRegion {
        return TripleShotSpriteRegion(
            u0: slot.x.toFloat() / 2048, v0: slot.y.toFloat() / height.toFloat(),
            u1: (slot.x + slot.w).toFloat() / 2048, v1: (slot.y + slot.h).toFloat() / height.toFloat(),
            sourceWidth: slot.sw, sourceHeight: slot.sh
        )
    }

    /// prepareActor's frame list, in this exact order (duplicates kept; `packSlots` drops them by resId).
    static func spriteFrames(set: CharacterSpriteSet, id: String) -> [CharacterSpriteFrame] {
        var frames: [CharacterSpriteFrame] = []
        frames += [set.idleBack, set.idleFront, set.winner, set.loser, set.spectator]
        for it in [set.shotBack, set.shotSide, set.shotFront] {
            frames += [it.low, it.mid, it.set]
            if let release = it.release { frames.append(release) }
        }
        for it in [set.steal, set.block, set.rebound].compactMap({ $0 }) { frames += [it.back, it.side, it.front] }
        frames += set.dunks.map { $0.frame }
        for it in TripleShotPlayerRenderer.Facing.allCases.compactMap({ BasketballFeedbackArt.dribble(id: id, facing: $0) }) { frames.append(it) }
        if let idleSide = set.idleSide { frames.append(idleSide) }
        if let playfulHold = set.playfulHold { frames.append(playfulHold) }
        for it in set.locomotion { frames += [it.back, it.side, it.front] }
        return frames
    }

    /// prepareActor's shelf packing (2 px border, 4 px gutters, slots at most 384 x 320, never upscaled) and the atlas
    /// height (the next multiple of 128, at most 4096).
    static func packSlots(frames: [CharacterSpriteFrame], id: String) throws -> (slots: [Slot], height: Int) {
        var slots: [Slot] = []; var x = 2; var y = 2; var rowH = 0
        for frame in frames.kDistinctBy({ $0.resId }) {
            let options = ABitmapFactory.Options()
            options.inJustDecodeBounds = true; options.inScaled = false
            _ = ABitmapFactory.decodeResource(AResources.self, frame.resId, options)
            guard options.outWidth > 0 && options.outHeight > 0 else {
                throw PrepareError(description: "java.lang.IllegalArgumentException: Failed requirement. (\(frame.resId))")
            }
            let scale: Float = kmin(320 / options.outHeight.toFloat(), 384 / options.outWidth.toFloat()).coerceAtMost(1)
            let w = Swift.max(1, (options.outWidth.toFloat() * scale).roundToInt()); let h = Swift.max(1, (options.outHeight.toFloat() * scale).roundToInt())
            if x + w + 2 > 2048 { x = 2; y += rowH + 4; rowH = 0 }
            slots.append(Slot(id: frame.resId, x: x, y: y, w: w, h: h, sw: options.outWidth, sh: options.outHeight))
            x += w + 4; rowH = Swift.max(rowH, h)
        }
        let height = ((y + rowH + 4 + 127) / 128) * 128
        guard height <= 4096 else {
            throw PrepareError(description: "java.lang.IllegalArgumentException: Sprite pack exceeds Pixel 3 atlas budget: \(id)")
        }
        return (slots: slots, height: height)
    }

    /// GLUtils.texImage2D(GL_TEXTURE_2D, 0, bitmap, 0): the bitmap's premultiplied RGBA bytes as an .rgba8Unorm
    /// texture, row 0 = the image's top row (texture v 0). Thread-safe (MTLDevice is).
    static func makeTexture(device: MTLDevice, bitmap: ABitmap) -> MTLTexture? {
        if bitmap.isRecycled { return nil }
        let w = bitmap.width, h = bitmap.height
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: w, height: h, mipmapped: false)
        descriptor.usage = [.shaderRead]
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        if let ctx = bitmap.kgContext, let data = ctx.data {
            texture.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: data, bytesPerRow: ctx.bytesPerRow)
            return texture
        }
        // An immutable bitmap: its pixels drawn as stored into a premultiplied RGBA context.
        guard let image = bitmap.cgImage, let ctx = ABitmap.makeContext(w, h), let data = ctx.data else { return nil }
        ctx.setBlendMode(.copy)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        texture.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: data, bytesPerRow: ctx.bytesPerRow)
        return texture
    }
}
