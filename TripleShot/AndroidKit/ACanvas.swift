import CoreGraphics
import CoreText
import Foundation
import UIKit

// android.graphics.Canvas over a Core Graphics context (VIEW-API "Graphics"). The context's CTM maps
// 1 unit = 1 Android pixel with the origin at the top left (y down), so every coordinate, stroke width,
// text size and shadow offset below is in Android pixels, transformed by the canvas matrix like Skia.
//
// Android 12 (hwui SkiaCanvas + Skia) semantics kept here: save/restore counts (save() returns the count to
// restore to, restore underflow is an error), saveLayer/saveLayerAlpha as bounded transparency layers (a layer
// paint's colour filter applies to the layer), scale/rotate around pivots with Skia's matrices, sorted rects,
// non-anti-aliased rect clips snapped to whole pixels (SkRect::round), anti-aliased path clips, hwui's
// getClipBounds (no outset), round-rect radii scaled to fit, arcs with Skia's rules, Paint styles FILL / STROKE /
// FILL_AND_STROKE (one combined outline like Skia), hairline strokes (width 0 = 1 device px), caps/joins/miter
// (default miter 4), dash path effects, anti-aliasing and bitmap filtering flags, gradient shaders in canvas
// coordinates with premultiplied colour interpolation (hwui's kInterpolateColorsInPremul_Flag) modulated by the
// paint alpha, SRC_IN colour filters (drawable tints), shadow layers (sigma = 0.57735 r + 0.5, offset and blur in
// canvas px), drawLine/drawPoint ignoring the paint style, the native paint alpha, and text drawn with Core Text
// at the baseline with Paint.Align: laid out at Minikin's integral size, glyphs drawn at the full text size, with
// letter spacing, FreeType fake bold, underline / strike-through and RTL (bidi).

final class ACanvas {
    /// One entry per save()/saveLayer().
    private struct KGSave {
        /// A transparency layer (saveLayer / saveLayerAlpha).
        let isLayer: Bool
        /// The SRC_IN colour filter of the layer paint, applied to the layer content when it is restored.
        let filter: Int?
        /// The layer's area in device space (for the filter pass).
        let deviceRect: CGRect?
    }

    private let ctx: CGContext?
    private let widthPx: Int
    private let heightPx: Int
    /// saveCount = count + 1.
    private var saveStack: [KGSave] = []
    /// px space of the canvas at creation -> the context's base space (shadow offsets are base space).
    private let pxToBase: CGAffineTransform
    private let initialCTM: CGAffineTransform
    private let initialCTMInverse: CGAffineTransform
    /// The bitmap of an offscreen canvas (kept alive; its context is restored when the canvas goes away).
    private let ownedBitmap: ABitmap?
    /// Canvas.isHardwareAccelerated(): view canvases are, bitmap canvases are not.
    let isHardwareAccelerated: Bool

    /// A canvas on a UIKit drawing context whose CTM already maps 1 unit = 1 px, origin top left. The
    /// context's base space is UIKit's (points, y down), so px -> base is a 1/density scale.
    init(_ context: CGContext, _ widthPx: Int, _ heightPx: Int) {
        ctx = context
        self.widthPx = widthPx
        self.heightPx = heightPx
        let d = KitGraphics.density
        pxToBase = CGAffineTransform(scaleX: 1 / d, y: 1 / d)
        initialCTM = context.ctm
        initialCTMInverse = initialCTM.inverted()
        ownedBitmap = nil
        isHardwareAccelerated = true
    }

    /// `new Canvas(bitmap)`: draws into a mutable bitmap (offscreen, px = bitmap pixels).
    init(_ bitmap: ABitmap) {
        precondition(bitmap.isMutable, "java.lang.IllegalStateException: Immutable bitmap passed to Canvas constructor")
        precondition(!bitmap.isRecycled, "java.lang.RuntimeException: Canvas: trying to use a recycled bitmap \(bitmap)")
        let c = bitmap.kgContext!
        c.saveGState()
        c.translateBy(x: 0, y: CGFloat(bitmap.height))
        c.scaleBy(x: 1, y: -1)
        ctx = c
        widthPx = bitmap.width
        heightPx = bitmap.height
        initialCTM = c.ctm
        initialCTMInverse = initialCTM.inverted()
        // A bitmap context's base space is its device space.
        pxToBase = CGAffineTransform(a: initialCTM.a, b: initialCTM.b, c: initialCTM.c, d: initialCTM.d, tx: 0, ty: 0)
        ownedBitmap = bitmap
        isHardwareAccelerated = false
    }

    private init() {
        ctx = nil
        widthPx = 0
        heightPx = 0
        pxToBase = .identity
        initialCTM = .identity
        initialCTMInverse = .identity
        ownedBitmap = nil
        isHardwareAccelerated = true
    }

    /// A canvas that draws nothing (views drawn in the Choreographer traversal build their snapshots with it).
    /// save/restore counting still works. Each access is a new canvas with save count 1, like the fresh
    /// recording canvas Android gives every view's onDraw (an unbalanced save in one draw cannot leak into the next).
    static var noop: ACanvas { return ACanvas() }

    deinit {
        guard ownedBitmap != nil, let c = ctx else { return }
        while let entry = saveStack.popLast() {
            if entry.isLayer { c.endTransparencyLayer() }
            c.restoreGState()
        }
        c.restoreGState()
    }

    var width: Int { return widthPx }
    var height: Int { return heightPx }
    func getWidth() -> Int { return widthPx }
    func getHeight() -> Int { return heightPx }

    /// The Core Graphics context (nil for the no-op canvas), for code that draws with Core Graphics directly.
    var cgContext: CGContext? { return ctx }

    /// The current user space -> the canvas's pixel space at creation (y down).
    private func kgUserToPx(_ c: CGContext) -> CGAffineTransform {
        return c.ctm.concatenating(initialCTMInverse)
    }

    // MARK: Save / restore

    var saveCount: Int { return saveStack.count + 1 }
    func getSaveCount() -> Int { return saveCount }

    /// `save()`: returns the value to pass to restoreToCount to balance this save.
    @discardableResult
    func save() -> Int {
        let count = saveCount
        ctx?.saveGState()
        saveStack.append(KGSave(isLayer: false, filter: nil, deviceRect: nil))
        return count
    }

    /// `saveLayerAlpha(bounds, alpha)`: draws until the matching restore go to a layer composited with `alpha`
    /// (clamped to 0...255 like Canvas.saveLayerAlpha) and clipped to `bounds` (nil = the clip).
    @discardableResult
    func saveLayerAlpha(_ bounds: ARectF?, _ alpha: Int) -> Int {
        let a = min(255, max(0, alpha))
        return kgSaveLayer(bounds?.cgRect, CGFloat(a) / 255, nil)
    }

    @discardableResult
    func saveLayerAlpha(_ left: Float, _ top: Float, _ right: Float, _ bottom: Float, _ alpha: Int) -> Int {
        return saveLayerAlpha(ARectF(left, top, right, bottom), alpha)
    }

    /// `saveLayer(bounds, paint)`: a layer composited with the paint's alpha and colour filter.
    @discardableResult
    func saveLayer(_ bounds: ARectF?, _ paint: APaint?) -> Int {
        return kgSaveLayer(bounds?.cgRect, CGFloat(paint?.kgNativeAlpha ?? 255) / 255, paint?.kgColorFilter)
    }

    @discardableResult
    func saveLayer(_ left: Float, _ top: Float, _ right: Float, _ bottom: Float, _ paint: APaint?) -> Int {
        return saveLayer(ARectF(left, top, right, bottom), paint)
    }

    private func kgSaveLayer(_ rect: CGRect?, _ alpha: CGFloat, _ filter: Int?) -> Int {
        let count = saveCount
        var deviceRect: CGRect?
        if let c = ctx {
            c.saveGState()
            c.setAlpha(alpha)
            if let r = rect?.standardized {
                c.clip(to: r)
                deviceRect = r.applying(c.ctm)
                c.beginTransparencyLayer(in: r, auxiliaryInfo: nil)
            } else {
                deviceRect = c.boundingBoxOfClipPath.applying(c.ctm)
                c.beginTransparencyLayer(auxiliaryInfo: nil)
            }
        }
        saveStack.append(KGSave(isLayer: true, filter: filter, deviceRect: deviceRect))
        return count
    }

    /// `restore()`: undoes the last save; more restores than saves is an error (Android throws).
    func restore() {
        guard let entry = saveStack.popLast() else {
            preconditionFailure("java.lang.IllegalStateException: Underflow in restore - more restores than saves")
        }
        if let c = ctx {
            if entry.isLayer {
                if let f = entry.filter {
                    // The layer paint's SRC_IN colour filter: the filter colour with the layer's coverage.
                    c.saveGState()
                    c.resetClip()
                    c.concatenate(c.ctm.inverted())
                    c.setBlendMode(.sourceIn)
                    c.setFillColor(AColor.cgColor(f))
                    c.fill(entry.deviceRect ?? c.boundingBoxOfClipPath)
                    c.restoreGState()
                }
                c.endTransparencyLayer()
            }
            c.restoreGState()
        }
    }

    /// `restoreToCount(saveCount)`: restores until `getSaveCount() == saveCount` (a larger count does nothing).
    func restoreToCount(_ saveCount: Int) {
        precondition(saveCount >= 1, "java.lang.IllegalArgumentException: Underflow in restoreToCount - more restores than saves")
        while self.saveCount > saveCount {
            restore()
        }
    }

    // MARK: Matrix

    func translate(_ dx: Float, _ dy: Float) {
        if dx == 0 && dy == 0 { return }
        ctx?.translateBy(x: CGFloat(dx), y: CGFloat(dy))
    }

    func scale(_ sx: Float, _ sy: Float) {
        if sx == 1 && sy == 1 { return }
        ctx?.scaleBy(x: CGFloat(sx), y: CGFloat(sy))
    }

    /// `scale(sx, sy, px, py)`: translate(px, py); scale(sx, sy); translate(-px, -py).
    func scale(_ sx: Float, _ sy: Float, _ px: Float, _ py: Float) {
        if sx == 1 && sy == 1 { return }
        translate(px, py)
        scale(sx, sy)
        translate(-px, -py)
    }

    /// `rotate(degrees)`: clockwise on screen, Skia's matrix (sin/cos snapped to 0 near multiples of 90°).
    func rotate(_ degrees: Float) {
        if degrees == 0 { return }
        let m = AMatrix()
        m.setRotate(degrees)
        ctx?.concatenate(m.cgAffineTransform)
    }

    func rotate(_ degrees: Float, _ px: Float, _ py: Float) {
        if degrees == 0 { return }
        translate(px, py)
        rotate(degrees)
        translate(-px, -py)
    }

    func skew(_ sx: Float, _ sy: Float) {
        if sx == 0 && sy == 0 { return }
        let m = AMatrix()
        m.setSkew(sx, sy)
        ctx?.concatenate(m.cgAffineTransform)
    }

    /// `concat(matrix)`: pre-concatenates the matrix (its affine part).
    func concat(_ matrix: AMatrix?) {
        guard let m = matrix, !m.isIdentity() else { return }
        ctx?.concatenate(m.cgAffineTransform)
    }

    /// `setMatrix(matrix)`: replaces the canvas matrix (nil = identity) relative to the canvas origin.
    func setMatrix(_ matrix: AMatrix?) {
        guard let c = ctx else { return }
        let target = (matrix?.cgAffineTransform ?? .identity).concatenating(initialCTM)
        c.concatenate(target.concatenating(c.ctm.inverted()))
    }

    /// `getMatrix(ctm)`: the current canvas matrix relative to the canvas origin.
    func getMatrix(_ ctm: AMatrix) {
        let t = (ctx?.ctm ?? .identity).concatenating(initialCTMInverse)
        ctm.setValues([Float(t.a), Float(t.c), Float(t.tx), Float(t.b), Float(t.d), Float(t.ty), 0, 0, 1])
    }

    // MARK: Clip

    /// `clipRect(...)`: intersects the clip with the (sorted) rect, not anti-aliased like hwui's
    /// SkCanvas::clipRect(rect, op): on an axis-aligned matrix the device edges snap to whole pixels
    /// (SkRect::round, floor(x + 0.5)). A non-finite rect leaves the clip unchanged. False when the clip is empty.
    @discardableResult
    func clipRect(_ left: Float, _ top: Float, _ right: Float, _ bottom: Float) -> Bool {
        let r = CGRect(x: CGFloat(left), y: CGFloat(top), width: CGFloat(right - left), height: CGFloat(bottom - top)).standardized
        guard let c = ctx else { return !r.isEmpty }
        if !(left.isFinite && top.isFinite && right.isFinite && bottom.isFinite) { return !c.boundingBoxOfClipPath.isEmpty }
        let toPx = kgUserToPx(c)
        if toPx.b == 0 && toPx.c == 0 {
            let p = r.applying(toPx)
            let l = (p.minX + 0.5).rounded(.down), t = (p.minY + 0.5).rounded(.down)
            let rr = (p.maxX + 0.5).rounded(.down), b = (p.maxY + 0.5).rounded(.down)
            c.clip(to: CGRect(x: l, y: t, width: max(0, rr - l), height: max(0, b - t)).applying(toPx.inverted()))
        } else {
            c.setShouldAntialias(false)
            c.clip(to: r)
            c.setShouldAntialias(true)
        }
        return !c.boundingBoxOfClipPath.isEmpty
    }

    @discardableResult
    func clipRect(_ left: Int, _ top: Int, _ right: Int, _ bottom: Int) -> Bool {
        return clipRect(Float(left), Float(top), Float(right), Float(bottom))
    }

    @discardableResult
    func clipRect(_ rect: ARectF) -> Bool {
        return clipRect(rect.left, rect.top, rect.right, rect.bottom)
    }

    @discardableResult
    func clipRect(_ rect: ARect) -> Bool {
        return clipRect(Float(rect.left), Float(rect.top), Float(rect.right), Float(rect.bottom))
    }

    /// `clipPath(path)`: anti-aliased like hwui (`clipPath(path, op, true)`), with the path's fill type.
    @discardableResult
    func clipPath(_ path: APath) -> Bool {
        guard let c = ctx else { return true }
        c.addPath(path.cgPath)
        c.clip(using: path.cgFillRule)
        return !c.boundingBoxOfClipPath.isEmpty
    }

    /// `clipOutRect(...)` (API 26): removes the rect from the clip.
    @discardableResult
    func clipOutRect(_ left: Float, _ top: Float, _ right: Float, _ bottom: Float) -> Bool {
        guard let c = ctx else { return true }
        let r = CGRect(x: CGFloat(left), y: CGFloat(top), width: CGFloat(right - left), height: CGFloat(bottom - top)).standardized
        c.addRect(c.boundingBoxOfClipPath)
        c.addRect(r)
        c.clip(using: .evenOdd)
        return !c.boundingBoxOfClipPath.isEmpty
    }

    @discardableResult
    func clipOutRect(_ rect: ARectF) -> Bool { return clipOutRect(rect.left, rect.top, rect.right, rect.bottom) }

    @discardableResult
    func clipOutRect(_ rect: ARect) -> Bool {
        return clipOutRect(Float(rect.left), Float(rect.top), Float(rect.right), Float(rect.bottom))
    }

    /// `getClipBounds(bounds)` (hwui SkiaCanvas::getClipBounds + JNI): the device clip bounds (whole pixels,
    /// rounded out), mapped back through the inverse matrix without Skia's outset, then rounded (SkRect::round);
    /// false when the clip is empty.
    @discardableResult
    func getClipBounds(_ bounds: ARect) -> Bool {
        guard let c = ctx else {
            bounds.set(0, 0, widthPx, heightPx)
            return widthPx > 0 && heightPx > 0
        }
        let local = c.boundingBoxOfClipPath
        if local.isNull || local.isEmpty {
            bounds.set(0, 0, 0, 0)
            return false
        }
        let toPx = kgUserToPx(c)
        let device = local.applying(toPx)
        let l = device.minX.rounded(.down), t = device.minY.rounded(.down)
        let ideviceRect = CGRect(x: l, y: t, width: device.maxX.rounded(.up) - l, height: device.maxY.rounded(.up) - t)
        if ideviceRect.isEmpty {
            bounds.set(0, 0, 0, 0)
            return false
        }
        let r = ideviceRect.applying(toPx.inverted())
        func skRound(_ v: CGFloat) -> Int { return KitGraphics.javaInt((Float(v) + 0.5).rounded(.down)) }
        bounds.set(skRound(r.minX), skRound(r.minY), skRound(r.maxX), skRound(r.maxY))
        return true
    }

    func getClipBounds() -> ARect {
        let r = ARect()
        getClipBounds(r)
        return r
    }

    // MARK: Colour

    /// `drawColor(color)`: fills the whole clip (SRC_OVER).
    func drawColor(_ color: Int) {
        guard let c = ctx else { return }
        c.saveGState()
        c.setFillColor(AColor.cgColor(color))
        c.fill(c.boundingBoxOfClipPath)
        c.restoreGState()
    }

    func drawRGB(_ r: Int, _ g: Int, _ b: Int) {
        drawColor(AColor.rgb(r, g, b))
    }

    func drawARGB(_ a: Int, _ r: Int, _ g: Int, _ b: Int) {
        drawColor(AColor.argb(a, r, g, b))
    }

    /// `drawPaint(paint)`: fills the whole clip with the paint (colour or shader).
    func drawPaint(_ paint: APaint) {
        guard let c = ctx else { return }
        let fill = APaint(paint)
        fill.style = .FILL
        kgDraw(CGPath(rect: c.boundingBoxOfClipPath, transform: nil), .winding, fill)
    }

    // MARK: Shapes

    func drawRect(_ left: Float, _ top: Float, _ right: Float, _ bottom: Float, _ paint: APaint) {
        let l = min(left, right), r = max(left, right), t = min(top, bottom), b = max(top, bottom)
        let p = APath()
        p.addRect(l, t, r, b, .CW)
        kgDraw(p.cgPath, .winding, paint)
    }

    func drawRect(_ rect: ARectF, _ paint: APaint) {
        drawRect(rect.left, rect.top, rect.right, rect.bottom, paint)
    }

    func drawRect(_ r: ARect, _ paint: APaint) {
        drawRect(Float(r.left), Float(r.top), Float(r.right), Float(r.bottom), paint)
    }

    /// `drawRoundRect(rect, rx, ry, paint)`: a plain rect unless both radii are > 0; radii scaled to fit.
    func drawRoundRect(_ rect: ARectF, _ rx: Float, _ ry: Float, _ paint: APaint) {
        drawRoundRect(rect.left, rect.top, rect.right, rect.bottom, rx, ry, paint)
    }

    func drawRoundRect(_ left: Float, _ top: Float, _ right: Float, _ bottom: Float, _ rx: Float, _ ry: Float, _ paint: APaint) {
        if rx > 0 && ry > 0 {
            let p = APath()
            p.addRoundRect(left, top, right, bottom, rx, ry, .CW)
            kgDraw(p.cgPath, .winding, paint)
        } else {
            drawRect(left, top, right, bottom, paint)
        }
    }

    /// `drawCircle(cx, cy, radius, paint)`: nothing for radius <= 0 (hwui), else the oval of the circle's square.
    func drawCircle(_ cx: Float, _ cy: Float, _ radius: Float, _ paint: APaint) {
        if !(radius > 0) { return }
        drawOval(cx - radius, cy - radius, cx + radius, cy + radius, paint)
    }

    func drawOval(_ oval: ARectF, _ paint: APaint) {
        drawOval(oval.left, oval.top, oval.right, oval.bottom, paint)
    }

    func drawOval(_ left: Float, _ top: Float, _ right: Float, _ bottom: Float, _ paint: APaint) {
        let l = min(left, right), r = max(left, right), t = min(top, bottom), b = max(top, bottom)
        let p = APath()
        p.addOval(l, t, r, b, .CW)
        kgDraw(p.cgPath, .winding, paint)
    }

    /// `drawArc(oval, startAngle, sweepAngle, useCenter, paint)`: degrees, clockwise; a full oval when
    /// |sweep| >= 360 (hwui); otherwise nothing for an empty (or unsorted) oval or a zero sweep
    /// (SkCanvas::drawArc), else SkPathPriv::CreateDrawArcPath (a wedge through the centre when `useCenter`).
    func drawArc(_ oval: ARectF, _ startAngle: Float, _ sweepAngle: Float, _ useCenter: Bool, _ paint: APaint) {
        drawArc(oval.left, oval.top, oval.right, oval.bottom, startAngle, sweepAngle, useCenter, paint)
    }

    func drawArc(_ left: Float, _ top: Float, _ right: Float, _ bottom: Float,
                 _ startAngle: Float, _ sweepAngle: Float, _ useCenter: Bool, _ paint: APaint) {
        if abs(sweepAngle) >= 360 {
            drawOval(left, top, right, bottom, paint)
            return
        }
        // SkRect::isEmpty on the rect as given (not sorted).
        if !(left < right && top < bottom) || sweepAngle == 0 { return }
        let p = APath()
        if useCenter {
            p.moveTo(KGPathMath.centerOf(left, right), KGPathMath.centerOf(top, bottom))
        }
        p.arcTo(left, top, right, bottom, startAngle, sweepAngle, !useCenter)
        if useCenter {
            p.close()
        }
        kgDraw(p.cgPath, .winding, paint)
    }

    /// `drawLine(...)`: always stroked (the paint style is ignored), with the paint's cap.
    func drawLine(_ startX: Float, _ startY: Float, _ stopX: Float, _ stopY: Float, _ paint: APaint) {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: CGFloat(startX), y: CGFloat(startY)))
        p.addLine(to: CGPoint(x: CGFloat(stopX), y: CGFloat(stopY)))
        kgDraw(p, .winding, paint, strokeOnly: true)
    }

    /// `drawLines(pts, paint)`: segments (x0, y0, x1, y1) of 4 floats each.
    func drawLines(_ pts: [Float], _ paint: APaint) {
        drawLines(pts, 0, pts.count, paint)
    }

    func drawLines(_ pts: [Float], _ offset: Int, _ count: Int, _ paint: APaint) {
        if count < 4 { return }
        let p = CGMutablePath()
        var i = offset
        let end = offset + (count & ~3)
        while i + 3 < end {
            p.move(to: CGPoint(x: CGFloat(pts[i]), y: CGFloat(pts[i + 1])))
            p.addLine(to: CGPoint(x: CGFloat(pts[i + 2]), y: CGFloat(pts[i + 3])))
            i += 4
        }
        kgDraw(p, .winding, paint, strokeOnly: true)
    }

    /// `drawPoint(x, y, paint)`: a square (BUTT/SQUARE cap) or round dot of strokeWidth (hairline = 1 px).
    func drawPoint(_ x: Float, _ y: Float, _ paint: APaint) {
        drawPoints([x, y], 0, 2, paint)
    }

    func drawPoints(_ pts: [Float], _ paint: APaint) {
        drawPoints(pts, 0, pts.count, paint)
    }

    func drawPoints(_ pts: [Float], _ offset: Int, _ count: Int, _ paint: APaint) {
        guard let c = ctx, count >= 2 else { return }
        let w = CGFloat(paint.strokeWidth > 0 ? paint.strokeWidth : 0)
        let size = w > 0 ? w : hairlineWidth(c)
        let p = CGMutablePath()
        var i = offset
        while i + 1 < offset + count {
            let x = CGFloat(pts[i]), y = CGFloat(pts[i + 1])
            let r = CGRect(x: x - size / 2, y: y - size / 2, width: size, height: size)
            if paint.strokeCap == .ROUND && w > 0 {
                p.addEllipse(in: r)
            } else {
                p.addRect(r)
            }
            i += 2
        }
        let fill = APaint(paint)
        fill.style = .FILL
        kgDraw(p, .winding, fill)
    }

    /// `drawPath(path, paint)` with the path's fill type; nothing for a path without verbs.
    func drawPath(_ path: APath, _ paint: APaint) {
        if path.isEmpty { return }
        kgDraw(path.cgPath, path.cgFillRule, paint)
    }

    // MARK: Bitmaps

    /// `drawBitmap(bitmap, left, top, paint)`: at its pixel size.
    func drawBitmap(_ bitmap: ABitmap, _ left: Float, _ top: Float, _ paint: APaint?) {
        kgDrawBitmap(bitmap, nil, CGRect(x: CGFloat(left), y: CGFloat(top), width: CGFloat(bitmap.width), height: CGFloat(bitmap.height)), paint)
    }

    /// `drawBitmap(bitmap, src, dst, paint)`: the src subset (nil = whole bitmap) scaled into dst.
    func drawBitmap(_ bitmap: ABitmap, _ src: ARect?, _ dst: ARectF, _ paint: APaint?) {
        kgDrawBitmap(bitmap, src, dst.cgRect, paint)
    }

    func drawBitmap(_ bitmap: ABitmap, _ src: ARect?, _ dst: ARect, _ paint: APaint?) {
        kgDrawBitmap(bitmap, src, dst.cgRect, paint)
    }

    /// `drawBitmap(bitmap, matrix, paint)`.
    func drawBitmap(_ bitmap: ABitmap, _ matrix: AMatrix, _ paint: APaint?) {
        guard let c = ctx else { return }
        c.saveGState()
        c.concatenate(matrix.cgAffineTransform)
        kgDrawBitmap(bitmap, nil, CGRect(x: 0, y: 0, width: bitmap.width, height: bitmap.height), paint)
        c.restoreGState()
    }

    /// Skia drawImageRect: bilinear without mipmaps when the paint filters (SkFilterMode::kLinear), nearest
    /// otherwise or without a paint; edges anti-aliased only with ANTI_ALIAS_FLAG; modulated by the paint alpha,
    /// through the paint's colour filter, with its shadow layer.
    private func kgDrawBitmap(_ bitmap: ABitmap, _ src: ARect?, _ dst: CGRect, _ paint: APaint?) {
        precondition(!bitmap.isRecycled, "java.lang.RuntimeException: Canvas: trying to use a recycled bitmap \(bitmap)")
        guard let c = ctx, var image = bitmap.cgImage else { return }
        if let p = paint, p.kgNativeAlpha == 0 { return }
        var dstRect = dst
        if let s = src {
            // Skia: clip the src to the bitmap bounds and shrink the dst accordingly.
            let srcF = ARectF(Float(s.left), Float(s.top), Float(s.right), Float(s.bottom))
            if srcF.isEmpty() { return }
            let bounds = ARectF(0, 0, Float(bitmap.width), Float(bitmap.height))
            if !bounds.contains(srcF) {
                let m = AMatrix()
                m.setRectToRect(srcF, ARectF(Float(dst.minX), Float(dst.minY), Float(dst.maxX), Float(dst.maxY)), .FILL)
                let clipped = ARectF(srcF)
                if !clipped.intersect(bounds) { return }
                let mapped = ARectF()
                m.mapRect(mapped, clipped)
                dstRect = mapped.cgRect
                srcF.set(clipped)
            }
            let cropRect = CGRect(x: CGFloat(srcF.left), y: CGFloat(srcF.top), width: CGFloat(srcF.width()), height: CGFloat(srcF.height()))
            if cropRect.minX != 0 || cropRect.minY != 0 || cropRect.width != CGFloat(image.width) || cropRect.height != CGFloat(image.height) {
                guard let cropped = image.cropping(to: cropRect.integral) else { return }
                image = cropped
            }
        }
        if dstRect.isEmpty { return }
        c.saveGState()
        c.setShouldAntialias(paint?.isAntiAlias ?? false)
        c.interpolationQuality = (paint?.isFilterBitmap ?? false) ? .low : .none
        var filter: Int?
        if let p = paint {
            c.setAlpha(CGFloat(p.kgNativeAlpha) / 255)
            _ = kgApplyShadow(c, p)
            filter = p.kgColorFilter
        }
        if filter != nil { c.beginTransparencyLayer(in: dstRect, auxiliaryInfo: nil) }
        c.saveGState()
        c.translateBy(x: dstRect.minX, y: dstRect.maxY)
        c.scaleBy(x: 1, y: -1)
        c.draw(image, in: CGRect(x: 0, y: 0, width: dstRect.width, height: dstRect.height))
        c.restoreGState()
        if let f = filter {
            c.setBlendMode(.sourceIn)
            c.setFillColor(AColor.cgColor(f))
            c.fill(dstRect.insetBy(dx: -1, dy: -1))
            c.endTransparencyLayer()
        }
        c.restoreGState()
    }

    /// Draws a drawable (DESIGN 4.4 helper; Android code calls `drawable.draw(canvas)`).
    func drawDrawable(_ drawable: ADrawable) {
        drawable.draw(self)
    }

    // MARK: Text

    /// `drawText(text, x, y, paint)`: y is the baseline; Paint.Align places x at the left / centre / right
    /// of the text's advance. Bidirectional text is ordered by Core Text (first strong direction, like
    /// Android's default BIDI_DEFAULT_LTR).
    func drawText(_ text: String, _ x: Float, _ y: Float, _ paint: APaint) {
        kgDrawText(text, x, y, paint, nil)
    }

    /// `drawText(text, start, end, x, y, paint)` (UTF-16 indices).
    func drawText(_ text: String, _ start: Int, _ end: Int, _ x: Float, _ y: Float, _ paint: APaint) {
        kgDrawText(KitGraphics.utf16Substring(text, start, end), x, y, paint, nil)
    }

    /// `drawTextRun(text, start, end, contextStart, contextEnd, x, y, isRtl, paint)`: one direction forced.
    func drawTextRun(_ text: String, _ start: Int, _ end: Int, _ contextStart: Int, _ contextEnd: Int,
                     _ x: Float, _ y: Float, _ isRtl: Bool, _ paint: APaint) {
        precondition(contextStart <= start && start <= end && end <= contextEnd, "java.lang.IndexOutOfBoundsException")
        kgDrawText(KitGraphics.utf16Substring(text, start, end), x, y, paint, isRtl)
    }

    /// hwui Canvas::drawText: Minikin lays the text out at `paint.kgLayoutSize` (positions, advance, alignment
    /// offset), the glyphs are drawn at the full text size at those positions.
    private func kgDrawText(_ text: String, _ x: Float, _ y: Float, _ paint: APaint, _ forcedRtl: Bool?) {
        guard let c = ctx, !text.isEmpty, paint.textSize > 0, paint.kgLayoutSize > 0, paint.kgNativeAlpha != 0 else { return }
        let d = KitGraphics.density
        let simple = paint.shader == nil && paint.style == .FILL && !paint.isFakeBoldText
        let color = kgSolidColor(paint)
        let line = paint.kgLine(text, simple ? color : nil, forcedRtl)
        var ascent: CGFloat = 0, descent: CGFloat = 0
        let advance = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil)) * d
        var originX = CGFloat(x)
        switch paint.textAlign {
        case .LEFT: break
        case .CENTER: originX -= advance / 2
        case .RIGHT: originX -= advance
        }
        let baseline = CGFloat(y)
        let halfLeft = paint.kgLetterSpacing().halfLeft
        // line space (points, y up, origin at the baseline start) -> canvas px
        let lineToCanvas = CGAffineTransform(a: d, b: 0, c: 0, d: -d, tx: originX + halfLeft, ty: baseline)
        // Generous bounds for transparency layers (ink can exceed the typographic box).
        let pad = CGFloat(paint.textSize) + CGFloat(paint.strokeWidth) + CGFloat(abs(paint.shadowLayerDx) + abs(paint.shadowLayerDy))
            + 3 * CGFloat(paint.shadowLayerRadius)
        let layerRect = CGRect(x: originX - pad, y: baseline - ascent * d - pad, width: advance + 2 * pad, height: (ascent + descent) * d + 2 * pad)
        if simple {
            let runs = CTLineGetGlyphRuns(line) as! [CTRun]
            c.saveGState()
            c.setShouldAntialias(paint.isAntiAlias)
            let shadow = kgApplyShadow(c, paint)
            let layered = shadow && runs.count > 1
            if layered { c.beginTransparencyLayer(in: layerRect, auxiliaryInfo: nil) }
            c.concatenate(lineToCanvas)
            if paint.kgLayoutSize == paint.textSize {
                c.textMatrix = .identity
                c.textPosition = .zero
                CTLineDraw(line, c)
            } else {
                c.setFillColor(color)
                for run in runs {
                    kgDrawRunGlyphs(c, run, paint)
                }
            }
            if layered { c.endTransparencyLayer() }
            c.restoreGState()
        } else {
            kgDrawLineAsPaths(c, line, lineToCanvas, layerRect, paint)
        }
        if paint.isUnderlineText || paint.isStrikeThruText {
            kgDrawTextDecorations(Float(originX), y, Float(advance), paint)
        }
    }

    /// One glyph run at its layout positions with the run's font at the drawing size (context in line space).
    private func kgDrawRunGlyphs(_ c: CGContext, _ run: CTRun, _ paint: APaint) {
        let attributes = CTRunGetAttributes(run) as NSDictionary
        guard let fontValue = attributes[kCTFontAttributeName as String] else { return }
        let font = paint.kgDrawFont(fontValue as! CTFont)
        let count = CTRunGetGlyphCount(run)
        if count == 0 { return }
        var glyphs = [CGGlyph](repeating: 0, count: count)
        var positions = [CGPoint](repeating: .zero, count: count)
        CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
        CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
        c.textMatrix = CTRunGetTextMatrix(run)
        CTFontDrawGlyphs(font, glyphs, positions, count, c)
    }

    /// Glyph outlines drawn like any path with the paint (stroke, fill-and-stroke, fake bold, shader, colour
    /// filter), colour glyphs (emoji) drawn as images.
    private func kgDrawLineAsPaths(_ c: CGContext, _ line: CTLine, _ lineToCanvas: CGAffineTransform,
                                   _ layerRect: CGRect, _ paint: APaint) {
        let outlines = CGMutablePath()
        var colorRuns: [CTRun] = []
        let runs = CTLineGetGlyphRuns(line) as! [CTRun]
        for run in runs {
            let attributes = CTRunGetAttributes(run) as NSDictionary
            guard let fontValue = attributes[kCTFontAttributeName as String] else { continue }
            let font = paint.kgDrawFont(fontValue as! CTFont)
            if CTFontGetSymbolicTraits(font).contains(.traitColorGlyphs) {
                colorRuns.append(run)
                continue
            }
            let count = CTRunGetGlyphCount(run)
            if count == 0 { continue }
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
            let runMatrix = CTRunGetTextMatrix(run)
            for i in 0..<count {
                var t = runMatrix.concatenating(CGAffineTransform(translationX: positions[i].x, y: positions[i].y))
                    .concatenating(lineToCanvas)
                if let glyphPath = CTFontCreatePathForGlyph(font, glyphs[i], &t) {
                    outlines.addPath(glyphPath)
                }
            }
        }
        var outline: CGPath = outlines
        if paint.isFakeBoldText && !outlines.isEmpty {
            // Android 12's Skia (SK_USE_FREETYPE_EMBOLDEN): FT_Outline_Embolden at the device text size moves every
            // outline edge out by s/2 (miter-like up to ~160 degree turns) and the whole outline by s/2 to the right
            // and up, s = KitGraphics.fakeBoldGrowth(device size); the paint's style then applies to that outline.
            let scale = KitGraphics.uniformScale(kgUserToPx(c))
            let s = CGFloat(KitGraphics.fakeBoldGrowth(Float(CGFloat(paint.textSize) * scale))) / scale
            if s > 0 {
                let band = outlines.copy(strokingWithWidth: s, lineCap: .butt, lineJoin: .miter, miterLimit: 5.76)
                let grown = outlines.union(band, using: .winding)
                var shift = CGAffineTransform(translationX: s / 2, y: -s / 2)
                outline = grown.copy(using: &shift) ?? grown
            }
        }
        if colorRuns.isEmpty {
            kgDraw(outline, .winding, paint)
            return
        }
        c.saveGState()
        let shadow = kgApplyShadow(c, paint)
        if shadow { c.beginTransparencyLayer(in: layerRect, auxiliaryInfo: nil) }
        kgDraw(outline, .winding, paint, applyShadow: false)
        c.saveGState()
        c.setShouldAntialias(paint.isAntiAlias)
        c.setAlpha(CGFloat(paint.kgNativeAlpha) / 255)
        c.concatenate(lineToCanvas)
        for run in colorRuns {
            if paint.kgLayoutSize == paint.textSize {
                c.textMatrix = .identity
                c.textPosition = .zero
                CTRunDraw(run, c, CFRange(location: 0, length: 0))
            } else {
                kgDrawRunGlyphs(c, run, paint)
            }
        }
        c.restoreGState()
        if shadow { c.endTransparencyLayer() }
        c.restoreGState()
    }

    /// hwui Canvas::drawTextDecorations: underline at the font's position/thickness, strike-through at
    /// -6/21 em (thickness 1/18 em), each a rect at least 1 px tall drawn with the paint.
    private func kgDrawTextDecorations(_ x: Float, _ y: Float, _ length: Float, _ paint: APaint) {
        let left = x
        let right = x + length
        let textSize = paint.textSize
        let rectPaint = APaint(paint)
        rectPaint.isUnderlineText = false
        rectPaint.isStrikeThruText = false
        if paint.isUnderlineText {
            let u = paint.kgUnderlineMetrics()
            let top = y + u.position
            drawRect(left, top, right, top + max(u.thickness, 1), rectPaint)
        }
        if paint.isStrikeThruText {
            let position = textSize * (Float(-6) / Float(21))
            let thickness = textSize * (Float(1) / Float(18))
            let top = y + position
            drawRect(left, top, right, top + max(thickness, 1), rectPaint)
        }
    }

    // MARK: Paint pipeline

    /// One device pixel in user units (a hairline).
    private func hairlineWidth(_ c: CGContext) -> CGFloat {
        let m = c.ctm
        let scale = sqrt(abs(m.a * m.d - m.b * m.c))
        return scale > 0 ? 1 / scale : 1
    }

    /// The colour a solid paint draws with: its native colour, or through its SRC_IN colour filter the filter
    /// colour with alpha = filter alpha x paint alpha (computed in floats like Skia).
    private func kgSolidColor(_ paint: APaint) -> CGColor {
        let pc = paint.kgDrawColor
        guard let f = paint.kgColorFilter else { return AColor.cgColor(pc) }
        let a = (CGFloat(AColor.alpha(f)) / 255) * (CGFloat(AColor.alpha(pc)) / 255)
        return CGColor(srgbRed: CGFloat(AColor.red(f)) / 255, green: CGFloat(AColor.green(f)) / 255,
                       blue: CGFloat(AColor.blue(f)) / 255, alpha: a)
    }

    private func applyStroke(_ c: CGContext, _ paint: APaint) {
        c.setLineWidth(paint.strokeWidth > 0 ? CGFloat(paint.strokeWidth) : hairlineWidth(c))
        switch paint.strokeCap {
        case .BUTT: c.setLineCap(.butt)
        case .ROUND: c.setLineCap(.round)
        case .SQUARE: c.setLineCap(.square)
        }
        switch paint.strokeJoin {
        case .MITER: c.setLineJoin(.miter)
        case .ROUND: c.setLineJoin(.round)
        case .BEVEL: c.setLineJoin(.bevel)
        }
        c.setMiterLimit(CGFloat(paint.strokeMiter))
        if let dash = paint.pathEffect, dash.isValid {
            c.setLineDash(phase: CGFloat(dash.normalizedPhase), lengths: dash.intervals.map { CGFloat($0) })
        }
    }

    /// The stroke outline of `path` with the paint's stroke settings (dashes applied first).
    private func strokeOutline(_ c: CGContext, _ path: CGPath, _ paint: APaint) -> CGPath {
        var source = path
        if let dash = paint.pathEffect, dash.isValid {
            source = path.copy(dashingWithPhase: CGFloat(dash.normalizedPhase), lengths: dash.intervals.map { CGFloat($0) })
        }
        let cap: CGLineCap
        switch paint.strokeCap {
        case .BUTT: cap = .butt
        case .ROUND: cap = .round
        case .SQUARE: cap = .square
        }
        let join: CGLineJoin
        switch paint.strokeJoin {
        case .MITER: join = .miter
        case .ROUND: join = .round
        case .BEVEL: join = .bevel
        }
        let width = paint.strokeWidth > 0 ? CGFloat(paint.strokeWidth) : hairlineWidth(c)
        return source.copy(strokingWithWidth: width, lineCap: cap, lineJoin: join, miterLimit: CGFloat(paint.strokeMiter))
    }

    /// Paint.setShadowLayer as a Core Graphics shadow: hwui sigma = 0.57735 * radius + 0.5 in canvas px,
    /// CG blur = 2 sigma, offset and blur converted to the context's base space through the current matrix
    /// (the looper translates the canvas and the blur respects the CTM). The shadow colour goes through the
    /// paint's colour filter like the shadow paint does in Skia.
    @discardableResult
    private func kgApplyShadow(_ c: CGContext, _ paint: APaint) -> Bool {
        let radius = paint.shadowLayerRadius
        if !(radius > 0) { return false }
        let sigma = CGFloat(Float(0.57735) * radius + 0.5)
        let userToBase = c.ctm.concatenating(initialCTMInverse).concatenating(pxToBase)
        let offset = CGSize(width: CGFloat(paint.shadowLayerDx), height: CGFloat(paint.shadowLayerDy)).applying(userToBase)
        let scale = sqrt(abs(userToBase.a * userToBase.d - userToBase.b * userToBase.c))
        var shadowColor = AColor.cgColor(paint.shadowLayerColor)
        if let f = paint.kgColorFilter {
            let a = (CGFloat(AColor.alpha(f)) / 255) * (CGFloat(AColor.alpha(paint.shadowLayerColor)) / 255)
            shadowColor = CGColor(srgbRed: CGFloat(AColor.red(f)) / 255, green: CGFloat(AColor.green(f)) / 255,
                                  blue: CGFloat(AColor.blue(f)) / 255, alpha: a)
        }
        c.setShadow(offset: offset, blur: 2 * sigma * scale, color: shadowColor)
        return true
    }

    /// Draws a shape with the paint: style, stroke, anti-aliasing, colour or shader, colour filter, shadow.
    private func kgDraw(_ path: CGPath, _ rule: CGPathFillRule, _ paint: APaint, strokeOnly: Bool = false, applyShadow: Bool = true) {
        guard let c = ctx else { return }
        if paint.kgNativeAlpha == 0 { return }   // SkPaint::nothingToDraw
        let style: APaint.Style = strokeOnly ? .STROKE : paint.style
        c.saveGState()
        c.setShouldAntialias(paint.isAntiAlias)
        let shadow = applyShadow ? kgApplyShadow(c, paint) : false
        if let shader = paint.shader {
            let geometry: CGPath
            let geometryRule: CGPathFillRule
            switch style {
            case .FILL:
                geometry = path
                geometryRule = rule
            case .STROKE:
                geometry = strokeOutline(c, path, paint)
                geometryRule = .winding
            case .FILL_AND_STROKE:
                geometry = path.union(strokeOutline(c, path, paint), using: rule)
                geometryRule = .winding
            }
            let filter = paint.kgColorFilter
            let box = geometry.boundingBoxOfPath
            let layered = shadow || filter != nil
            if layered {
                let pad = CGFloat(abs(paint.shadowLayerDx) + abs(paint.shadowLayerDy) + 3 * paint.shadowLayerRadius) + 1
                c.beginTransparencyLayer(in: box.insetBy(dx: -pad, dy: -pad), auxiliaryInfo: nil)
            }
            c.saveGState()
            c.addPath(geometry)
            c.clip(using: geometryRule)
            kgFillShader(c, shader, paint.kgNativeAlpha)
            if let f = filter {
                // SRC_IN colour filter on the shaded pixels: the filter colour with their coverage.
                c.setBlendMode(.sourceIn)
                c.setFillColor(AColor.cgColor(f))
                c.fill(box.insetBy(dx: -1, dy: -1))
            }
            c.restoreGState()
            if layered { c.endTransparencyLayer() }
        } else {
            let color = kgSolidColor(paint)
            switch style {
            case .FILL:
                c.setFillColor(color)
                c.addPath(path)
                c.fillPath(using: rule)
            case .STROKE:
                applyStroke(c, paint)
                c.setStrokeColor(color)
                c.addPath(path)
                c.strokePath()
            case .FILL_AND_STROKE:
                if color.alpha >= 1 && !shadow {
                    applyStroke(c, paint)
                    c.setFillColor(color)
                    c.setStrokeColor(color)
                    c.addPath(path)
                    c.drawPath(using: rule == .evenOdd ? .eoFillStroke : .fillStroke)
                } else {
                    // Skia fills fill ∪ stroke once (no double blending of translucent colours).
                    let combined = path.union(strokeOutline(c, path, paint), using: rule)
                    c.setFillColor(color)
                    c.addPath(combined)
                    c.fillPath(using: .winding)
                }
            }
        }
        c.restoreGState()
    }

    // MARK: Shaders

    /// Fills the current clip with the shader (in canvas coordinates, through its local matrix), modulated
    /// by the paint alpha.
    private func kgFillShader(_ c: CGContext, _ shader: AShader, _ paintAlpha: Int) {
        c.saveGState()
        if let lm = shader.localMatrix {
            c.concatenate(lm.cgAffineTransform)
        }
        c.setAlpha(CGFloat(paintAlpha) / 255)
        if let g = shader as? ALinearGradient {
            kgDrawLinear(c, g)
        } else if let g = shader as? ARadialGradient {
            kgDrawRadial(c, g)
        }
        c.restoreGState()
    }

    private static let degenerateThreshold: Float = Float(1) / Float(1 << 15)

    private func makeGradient(_ colors: [Int], _ stops: [Float]) -> CGGradient? {
        let cgColors = colors.map { AColor.cgColor($0) } as CFArray
        var locations = stops.map { CGFloat($0) }
        return CGGradient(colorsSpace: KitGraphics.sRGB, colors: cgColors, locations: &locations)
    }

    /// Gradient stops with Android's premultiplied interpolation (hwui creates every gradient with
    /// SkGradientShader::kInterpolateColorsInPremul_Flag), drawn by `draw`. Core Graphics interpolates
    /// unpremultiplied colours, which is the same only when every stop has the same alpha; otherwise each stop
    /// is drawn as its own tent (its colour, alpha rising from 0 at the previous stop and falling to 0 at the
    /// next) and the tents are added with plusLighter in a transparency layer: the sum is exactly the
    /// premultiplied interpolation (a fade to TRANSPARENT keeps its hue instead of darkening).
    private func kgDrawStops(_ c: CGContext, _ colors: [Int], _ stops: [Float], _ draw: (CGGradient) -> Void) {
        let alpha0 = AColor.alpha(colors[0])
        if colors.allSatisfy({ AColor.alpha($0) == alpha0 }) {
            if let gradient = makeGradient(colors, stops) { draw(gradient) }
            return
        }
        c.saveGState()
        c.beginTransparencyLayer(auxiliaryInfo: nil)
        c.setBlendMode(.plusLighter)
        let n = colors.count
        for i in 0..<n where AColor.alpha(colors[i]) != 0 {
            let clear = colors[i] & 0x00FF_FFFF
            var tentColors: [Int] = []
            var tentStops: [Float] = []
            if i > 0 {
                tentColors.append(clear)
                tentStops.append(stops[i - 1])
            }
            tentColors.append(colors[i])
            tentStops.append(stops[i])
            if i < n - 1 {
                tentColors.append(clear)
                tentStops.append(stops[i + 1])
            }
            if let gradient = makeGradient(tentColors, tentStops) { draw(gradient) }
        }
        c.endTransparencyLayer()
        c.restoreGState()
    }

    /// Skia make_degenerate_gradient: CLAMP -> the last colour, REPEAT / MIRROR -> the average colour.
    private func fillDegenerate(_ c: CGContext, _ colors: [Int], _ stops: [Float], _ mode: ATileMode) {
        let color: Int
        if mode == .CLAMP {
            color = colors[colors.count - 1]
        } else {
            var a: Float = 0, r: Float = 0, g: Float = 0, b: Float = 0
            for i in 0..<(colors.count - 1) {
                let w = stops[i + 1] - stops[i]
                let c0 = colors[i], c1 = colors[i + 1]
                a += w * Float(AColor.alpha(c0) + AColor.alpha(c1)) / 2
                r += w * Float(AColor.red(c0) + AColor.red(c1)) / 2
                g += w * Float(AColor.green(c0) + AColor.green(c1)) / 2
                b += w * Float(AColor.blue(c0) + AColor.blue(c1)) / 2
            }
            color = AColor.argb(KitGraphics.mathRound(a), KitGraphics.mathRound(r), KitGraphics.mathRound(g), KitGraphics.mathRound(b))
        }
        c.setFillColor(AColor.cgColor(color))
        c.fill(c.boundingBoxOfClipPath)
    }

    /// Colours and stops for the periods [k0, k1) of a REPEAT / MIRROR gradient, normalised to [0, 1].
    private func tiledStops(_ colors: [Int], _ stops: [Float], _ mode: ATileMode, _ k0: Int, _ k1: Int) -> ([Int], [Float]) {
        var outColors: [Int] = []
        var outStops: [Float] = []
        let periods = Float(k1 - k0)
        for k in k0..<k1 {
            let mirrored = mode == .MIRROR && (k & 1) != 0
            for i in 0..<colors.count {
                let j = mirrored ? colors.count - 1 - i : i
                let s = mirrored ? 1 - stops[j] : stops[j]
                outColors.append(colors[j])
                outStops.append((Float(k - k0) + s) / periods)
            }
        }
        return (outColors, outStops)
    }

    private func kgDrawLinear(_ c: CGContext, _ g: ALinearGradient) {
        let (colors, stops) = AShader.kgStops(g.colors, g.positions)
        let dx = g.x1 - g.x0, dy = g.y1 - g.y0
        if Float(hypot(Double(dx), Double(dy))) <= ACanvas.degenerateThreshold {
            fillDegenerate(c, colors, stops, g.tileMode)
            return
        }
        let p0 = CGPoint(x: CGFloat(g.x0), y: CGFloat(g.y0))
        let p1 = CGPoint(x: CGFloat(g.x1), y: CGFloat(g.y1))
        if g.tileMode == .CLAMP {
            kgDrawStops(c, colors, stops) { gradient in
                c.drawLinearGradient(gradient, start: p0, end: p1, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            }
            return
        }
        // REPEAT / MIRROR: one CG gradient over the periods that cover the clip.
        let box = c.boundingBoxOfClipPath
        let vx = p1.x - p0.x, vy = p1.y - p0.y
        let len2 = vx * vx + vy * vy
        var tMin = CGFloat.infinity, tMax = -CGFloat.infinity
        for corner in [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
                       CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: box.minX, y: box.maxY)] {
            let t = ((corner.x - p0.x) * vx + (corner.y - p0.y) * vy) / len2
            tMin = min(tMin, t)
            tMax = max(tMax, t)
        }
        if !tMin.isFinite || !tMax.isFinite { return }
        var k0 = Int(tMin.rounded(.down)), k1 = Int(tMax.rounded(.up))
        if k1 <= k0 { k1 = k0 + 1 }
        if k1 - k0 > 512 { k0 = max(k0, k1 - 512) }
        let (tc, ts) = tiledStops(colors, stops, g.tileMode, k0, k1)
        let start = CGPoint(x: p0.x + vx * CGFloat(k0), y: p0.y + vy * CGFloat(k0))
        let end = CGPoint(x: p0.x + vx * CGFloat(k1), y: p0.y + vy * CGFloat(k1))
        kgDrawStops(c, tc, ts) { gradient in
            c.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
    }

    private func kgDrawRadial(_ c: CGContext, _ g: ARadialGradient) {
        let (colors, stops) = AShader.kgStops(g.colors, g.positions)
        if g.radius < 0 || abs(g.radius) <= ACanvas.degenerateThreshold {
            fillDegenerate(c, colors, stops, g.tileMode)
            return
        }
        let center = CGPoint(x: CGFloat(g.centerX), y: CGFloat(g.centerY))
        let r = CGFloat(g.radius)
        if g.tileMode == .CLAMP {
            kgDrawStops(c, colors, stops) { gradient in
                c.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: r,
                                     options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            }
            return
        }
        let box = c.boundingBoxOfClipPath
        var tMax: CGFloat = 0
        for corner in [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
                       CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: box.minX, y: box.maxY)] {
            tMax = max(tMax, hypot(corner.x - center.x, corner.y - center.y) / r)
        }
        if !tMax.isFinite { return }
        let k1 = min(512, max(1, Int(tMax.rounded(.up))))
        let (tc, ts) = tiledStops(colors, stops, g.tileMode, 0, k1)
        kgDrawStops(c, tc, ts) { gradient in
            c.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: r * CGFloat(k1),
                                 options: [.drawsAfterEndLocation])
        }
    }
}
