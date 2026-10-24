import CoreGraphics
import Foundation

// Shared internals of the AndroidKit graphics layer (area kit-graphics: AColor, AGeometry, APaint, APath, ACanvas,
// ABitmap, ADrawable). Not an Android API; everything else in the app uses the Android-named types.

enum KitGraphics {

    /// DisplayMetrics.density (px per dp), as CGFloat. Text is shaped at `textSize / density` points
    /// (the point size UIKit would use for that text) and drawn scaled back to pixels.
    static var density: CGFloat {
        let d = CGFloat(AResources.density)
        return d > 0 ? d : 1
    }

    /// Android colours are sRGB.
    static let sRGB: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    /// Skia `SK_ScalarNearlyZero` (1 / 4096).
    static let nearlyZero: Float = 1.0 / 4096.0

    /// Skia `SK_ScalarPI` (3.14159265f).
    static let skPI: Float = 3.14159265

    /// Java `(int) f`: NaN -> 0, saturating at the Int32 range, truncation toward zero.
    static func javaInt(_ f: Float) -> Int {
        if f.isNaN { return 0 }
        if f >= 2147483647.0 { return Int(Int32.max) }
        if f <= -2147483648.0 { return Int(Int32.min) }
        return Int(f.rounded(.towardZero))
    }

    /// Java `(int) d`.
    static func javaInt(_ d: Double) -> Int {
        if d.isNaN { return 0 }
        if d >= 2147483647.0 { return Int(Int32.max) }
        if d <= -2147483648.0 { return Int(Int32.min) }
        return Int(d.rounded(.towardZero))
    }

    /// Java `(long) f`.
    static func javaLong(_ f: Float) -> Int64 {
        if f.isNaN { return 0 }
        if f >= 9.223372e18 { return Int64.max }
        if f <= -9.223372e18 { return Int64.min }
        return Int64(f.rounded(.towardZero))
    }

    /// Java `Math.round(float)`: floor(f + 1/2) computed exactly, NaN -> 0, saturating at the Int32 range.
    static func mathRound(_ f: Float) -> Int {
        if f.isNaN { return 0 }
        return javaInt((Double(f) + 0.5).rounded(.down))
    }

    /// Java `(int) Math.floor(f)` / `(int) Math.ceil(f)` (Math.floor/ceil compute in double).
    static func floorInt(_ f: Float) -> Int { javaInt(Double(f).rounded(.down)) }
    static func ceilInt(_ f: Float) -> Int { javaInt(Double(f).rounded(.up)) }

    /// `TypedValue.complexToDimensionPixelSize` of a dp value (`Resources.getDimensionPixelSize`): rounds half away
    /// from zero, and a non-zero dimension never becomes 0 px.
    static func dimensionPixelSize(dp value: Float) -> Int {
        return dimensionPixelSize(dp: value, density: AResources.density)
    }

    /// `TypedValue.complexToDimensionPixelSize` of a dp value at a given density.
    static func dimensionPixelSize(dp value: Float, density: Float) -> Int {
        let f = value * density
        let res = javaInt(f >= 0 ? f + 0.5 : f - 0.5)
        if res != 0 { return res }
        if value == 0 { return 0 }
        if value > 0 { return 1 }
        return -1
    }

    /// `TypedValue.complexToDimension` of a dp value (`Resources.getDimension`).
    static func dimension(dp value: Float) -> Float {
        return value * AResources.density
    }

    /// Skia `SkDegreesToRadians` (float maths with `SK_ScalarPI / 180`).
    static func degreesToRadians(_ degrees: Float) -> Float {
        return degrees * (skPI / Float(180))
    }

    /// Skia `SkScalarSinSnapToZero` / `SkScalarCosSnapToZero`.
    static func sinSnapToZero(_ radians: Float) -> Float {
        let v = sinf(radians)
        return abs(v) <= nearlyZero ? 0 : v
    }

    static func cosSnapToZero(_ radians: Float) -> Float {
        let v = cosf(radians)
        return abs(v) <= nearlyZero ? 0 : v
    }

    /// Android fake bold (Paint.setFakeBoldText): the framework's Skia is built with SK_USE_FREETYPE_EMBOLDEN and
    /// SK_OUTLINE_EMBOLDEN_DIVISOR 34, so every glyph outline goes through FT_Outline_Embolden with
    /// strength = FT_MulFix(units_per_EM, y_scale) / 34 (26.6 fixed point, about ppem * 64 / 34). FreeType moves
    /// each edge out by strength / 2 (integer 26.6 division) and shifts the outline by the same amount, so the
    /// left and bottom ink edges stay and the glyph grows by 2 * (strength / 2) to the right and upwards.
    /// Returns that growth in device pixels for a device text size.
    static func fakeBoldGrowth(_ deviceTextSize: Float) -> Float {
        if !(deviceTextSize > 0) || !deviceTextSize.isFinite { return 0 }
        // SkScalarToFDot6(size) = (FT_F26Dot6) (size * 64); FT_MulFix(upem, y_scale) gives it back.
        let ppem26_6 = Int((deviceTextSize * 64).rounded(.towardZero))
        let strength = ppem26_6 / 34
        let half = strength / 2
        return Float(2 * half) / 64
    }

    /// The uniform scale of a CG transform (sqrt |det|), 1 when degenerate.
    static func uniformScale(_ t: CGAffineTransform) -> CGFloat {
        let s = sqrt(abs(t.a * t.d - t.b * t.c))
        return s > 0 && s.isFinite ? s : 1
    }

    /// The UTF-16 range [start, end) of a String (Kotlin/Java indices), as a Swift String.
    static func utf16Substring(_ text: String, _ start: Int, _ end: Int) -> String {
        let units = Array(text.utf16)
        precondition(start >= 0 && end >= start && end <= units.count,
                     "java.lang.IndexOutOfBoundsException: start \(start), end \(end), length \(units.count)")
        if start == 0 && end == units.count { return text }
        return String(decoding: units[start..<end], as: UTF16.self)
    }
}
