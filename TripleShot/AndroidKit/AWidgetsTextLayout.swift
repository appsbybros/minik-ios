import UIKit
import CoreText

// AndroidKit widgets, text engine (helper of AWidgetsText.swift; area kit-widgets): android.text.Layout with the
// StaticLayout / BoringLayout semantics TextView relies on, android.text.TextDirectionHeuristics, minikin's optimal and
// greedy line breakers, and the vertical font metrics Android's TextView uses for line boxes.
//
// Ported from the Android 15 sources (frameworks/base android15-release: StaticLayout.generate/out/calculateEllipsis,
// Layout.drawText/getLineLeft/getLineRight/getLineVisibleEnd, BoringLayout.isBoring; frameworks/minikin
// android15-release: OptimalLineBreaker, GreedyLineBreaker, LineBreakerUtil CharProcessor, LayoutCore letter spacing).
//
// Units are Android pixels. Glyphs are shaped with Core Text using exactly the fonts and letter spacing of
// APaint.kgLine (kit-graphics), so widths agree with Paint.measureText and every run is drawn through
// ACanvas.drawTextRun (stroke/fill/fake bold/shadow/underline semantics of the Canvas port). Vertical metrics are the
// Android fonts' (Roboto for the default family; Noto Sans Hebrew, Noto Sans Symbols, ... as the fallbacks used by a
// line, `useFallbackLineSpacing` = true for targetSdk >= 28), read from the font files of Android Studio's layoutlib,
// so line boxes, view heights and baselines are the Android ones even though iOS draws its own glyphs.

// MARK: - Environment

/// Density used by the widget layer (DisplayMetrics.density = UIScreen scale; fontScale 1 per DESIGN 2.5).
enum AWidgetEnv {
    static var density: Float { return AResources.density }
    /// DisplayMetrics.scaledDensity (= density: Dynamic Type is not applied, DESIGN 2.5).
    static var scaledDensity: Float { return AResources.density }
    /// `Resources.getDimensionPixelSize` of a dp dimension (style values, XML attributes).
    static func dpSize(_ value: Float) -> Int {
        return ATypedValue.toDimensionPixelSize(ATypedValue.COMPLEX_UNIT_DIP, value)
    }
}

/// A dp style dimension in px, rounded like `getDimensionPixelSize`.
@inline(__always) func aw_dpx(_ value: Float) -> Int { return AWidgetEnv.dpSize(value) }

/// Java / Skia rounding helpers used by the text code.
enum AWMath {
    /// Java `(int) f`: NaN -> 0, saturating, truncation toward zero.
    static func javaInt(_ f: Float) -> Int {
        if f.isNaN { return 0 }
        if f >= 2147483647.0 { return Int(Int32.max) }
        if f <= -2147483648.0 { return Int(Int32.min) }
        return Int(f.rounded(.towardZero))
    }

    static func javaInt(_ d: Double) -> Int {
        if d.isNaN { return 0 }
        if d >= 2147483647.0 { return Int(Int32.max) }
        if d <= -2147483648.0 { return Int(Int32.min) }
        return Int(d.rounded(.towardZero))
    }

    /// Java `Math.round(float)` (floor(f + 1/2) without double rounding).
    static func round(_ f: Float) -> Int {
        if f.isNaN { return 0 }
        return javaInt((Double(f) + 0.5).rounded(.down))
    }

    /// `(int) Math.ceil(f)` / `(int) Math.floor(f)` (computed in double like Java).
    static func ceil(_ f: Float) -> Int { return javaInt(Double(f).rounded(.up)) }
    static func floor(_ f: Float) -> Int { return javaInt(Double(f).rounded(.down)) }

    /// com.android.internal.util.FastMath.round: `(int) (((long) (value * 2^24) + 0x800000) >> 24)`.
    static func fastRound(_ value: Float) -> Int {
        let scaled = value * Float(65536 * 256)
        let lx: Int64
        if scaled.isNaN { lx = 0 } else if scaled >= 9.223372e18 { lx = Int64.max } else if scaled <= -9.223372e18 { lx = Int64.min }
        else { lx = Int64(scaled.rounded(.towardZero)) }
        return Int(Int32(truncatingIfNeeded: (lx &+ 0x800000) >> 24))
    }

    /// Skia `SkScalarRoundToInt` (floorf(x + 0.5f), float addition) / `SkScalarFloorToInt` / `SkScalarCeilToInt`.
    static func skRound(_ x: Float) -> Int { return javaInt((x + Float(0.5)).rounded(.down)) }
    static func skFloor(_ x: Float) -> Int { return javaInt(x.rounded(.down)) }
    static func skCeil(_ x: Float) -> Int { return javaInt(x.rounded(.up)) }
}

// MARK: - android.text.TextDirectionHeuristics

/// The TextDirectionHeuristics constants TextView chooses from (getTextDirectionHeuristic).
enum ATextDirectionHeuristic {
    case LTR, RTL, FIRSTSTRONG_LTR, FIRSTSTRONG_RTL, ANYRTL_LTR, LOCALE

    /// TextDirectionHeuristic.isRtl over UTF-16 units [start, end).
    func isRtl(_ units: [UInt16], _ start: Int, _ end: Int) -> Bool {
        switch self {
        case .LTR: return false
        case .RTL: return true
        case .LOCALE:
            return AView.isRtlLanguage(ALocale.getDefault().language.lowercased())
        case .FIRSTSTRONG_LTR, .FIRSTSTRONG_RTL:
            switch AWBidi.firstStrong(units, start, end) {
            case 1: return true
            case 0: return false
            default: return self == .FIRSTSTRONG_RTL
            }
        case .ANYRTL_LTR:
            switch AWBidi.anyStrong(units, start, end, lookForRtl: true) {
            case 1: return true
            default: return false
            }
        }
    }

    func isRtl(_ text: String) -> Bool {
        let units = Array(text.utf16)
        return isRtl(units, 0, units.count)
    }
}

/// Character.getDirectionality reduced to what the heuristics need (TextDirectionHeuristics.isRtlCodePoint).
enum AWBidi {
    static let STATE_TRUE = 1, STATE_FALSE = 0, STATE_UNKNOWN = 2

    /// isRtlCodePoint: STATE_TRUE for R/AL, STATE_FALSE for L, STATE_UNKNOWN for neutral and weak classes.
    static func isRtlCodePoint(_ cp: UInt32) -> Int {
        if cp == 0x200E { return STATE_FALSE }                       // LRM
        if cp == 0x200F || cp == 0x061C { return STATE_TRUE }        // RLM, ALM
        // Hebrew: letters and the punctuation maqaf/paseq/sof pasuq/nun hafukha are R; points and accents are NSM.
        if cp >= 0x0590 && cp <= 0x05FF {
            if cp == 0x05BE || cp == 0x05C0 || cp == 0x05C3 || cp == 0x05C6 { return STATE_TRUE }
            if cp >= 0x0591 && cp <= 0x05C7 { return STATE_UNKNOWN }
            return STATE_TRUE
        }
        if cp >= 0x0600 && cp <= 0x06FF {
            if (cp >= 0x0660 && cp <= 0x0669) || (cp >= 0x06F0 && cp <= 0x06F9) { return STATE_UNKNOWN } // AN / EN
            if (cp >= 0x064B && cp <= 0x065F) || cp == 0x0670 || (cp >= 0x06D6 && cp <= 0x06ED) { return STATE_UNKNOWN } // NSM
            if cp <= 0x0605 || cp == 0x060C || cp == 0x060E || cp == 0x060F || cp == 0x066A || cp == 0x06DD
                || cp == 0x06DE || cp == 0x06E9 { return STATE_UNKNOWN }
            return STATE_TRUE
        }
        if cp >= 0x0700 && cp <= 0x08FF { return STATE_TRUE }       // Syriac, Thaana, NKo, Samaritan, Mandaic, Arabic ext.
        if (cp >= 0xFB1D && cp <= 0xFDFF) || (cp >= 0xFE70 && cp <= 0xFEFE) { return STATE_TRUE }
        if (cp >= 0x10800 && cp <= 0x10FFF) || (cp >= 0x1E800 && cp <= 0x1EFFF) { return STATE_TRUE }
        guard let scalar = Unicode.Scalar(cp) else { return STATE_UNKNOWN }
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter, .spacingMark, .letterNumber:
            return STATE_FALSE
        case .unassigned:
            if (cp >= 0x2065 && cp <= 0x2069) || (cp >= 0xFFF0 && cp <= 0xFFF8) || (cp >= 0xE0000 && cp <= 0xE0FFF)
                || (cp >= 0xFDD0 && cp <= 0xFDEF) || (cp & 0xFFFE) == 0xFFFE || (cp >= 0x20A0 && cp <= 0x20CF) {
                return STATE_UNKNOWN
            }
            return STATE_FALSE
        default:
            return STATE_UNKNOWN
        }
    }

    /// TextDirectionHeuristics.FirstStrong.checkRtl (isolates skipped).
    static func firstStrong(_ units: [UInt16], _ start: Int, _ end: Int) -> Int {
        var result = STATE_UNKNOWN
        var openIsolateCount = 0
        forEachScalar(units, start, end) { cp in
            if cp >= 0x2066 && cp <= 0x2068 {
                openIsolateCount += 1
            } else if cp == 0x2069 {
                if openIsolateCount > 0 { openIsolateCount -= 1 }
            } else if openIsolateCount == 0 {
                result = isRtlCodePoint(cp)
            }
            return result == STATE_UNKNOWN
        }
        return result
    }

    /// TextDirectionHeuristics.AnyStrong.checkRtl.
    static func anyStrong(_ units: [UInt16], _ start: Int, _ end: Int, lookForRtl: Bool) -> Int {
        var haveUnlookedFor = false
        var openIsolateCount = 0
        var found = STATE_UNKNOWN
        forEachScalar(units, start, end) { cp in
            if cp >= 0x2066 && cp <= 0x2068 {
                openIsolateCount += 1
            } else if cp == 0x2069 {
                if openIsolateCount > 0 { openIsolateCount -= 1 }
            } else if openIsolateCount == 0 {
                switch isRtlCodePoint(cp) {
                case STATE_TRUE:
                    if lookForRtl { found = STATE_TRUE; return false }
                    haveUnlookedFor = true
                case STATE_FALSE:
                    if !lookForRtl { found = STATE_FALSE; return false }
                    haveUnlookedFor = true
                default:
                    break
                }
            }
            return true
        }
        if found != STATE_UNKNOWN { return found }
        if haveUnlookedFor { return lookForRtl ? STATE_FALSE : STATE_TRUE }
        return STATE_UNKNOWN
    }

    /// TextUtils.couldAffectRtl.
    static func couldAffectRtl(_ c: UInt16) -> Bool {
        return (0x0590 <= c && c <= 0x08FF) || c == 0x200E || c == 0x200F || (0x202A <= c && c <= 0x202E)
            || (0x2066 <= c && c <= 0x2069) || (0xD800 <= c && c <= 0xDFFF) || (0xFB1D <= c && c <= 0xFDFF)
            || (0xFE70 <= c && c <= 0xFEFE)
    }

    /// Visits the code points of UTF-16 units [start, end) until the visitor returns false.
    static func forEachScalar(_ units: [UInt16], _ start: Int, _ end: Int, _ visit: (UInt32) -> Bool) {
        var i = start
        while i < end {
            let u = units[i]
            var cp = UInt32(u)
            var step = 1
            if u >= 0xD800 && u <= 0xDBFF && i + 1 < end {
                let l = units[i + 1]
                if l >= 0xDC00 && l <= 0xDFFF {
                    cp = 0x10000 + ((UInt32(u) - 0xD800) << 10) + (UInt32(l) - 0xDC00)
                    step = 2
                }
            }
            if !visit(cp) { return }
            i += step
        }
    }
}

// MARK: - Android font metrics

/// Vertical metrics of Android's fonts as Skia/minikin compute them (FreeType: hhea ascent/descent unless the OS/2
/// USE_TYPO_METRICS bit is set, head bbox for top/bottom), from the layoutlib fonts of Android Studio:
/// Roboto upm 2048 hhea 1900/-500 bbox 2163/-555; NotoSansHebrew upm 1000 1068/-292 (typo); NotoSansSymbols and
/// NotoNaskhArabicUI upm 2048 2189/-600; NotoSansDevanagariUI 896/-408 (per 1000); NotoSansEthiopic 1069/-293;
/// NotoSansCJK 1160/-288; NotoColorEmoji 950/-250 per 1024 (= Roboto's ascent/descent).
enum AWFontMetrics {
    /// Paint.FontMetrics of the default family (floats, Android signs: top/ascent negative).
    struct Metrics { let top: Float; let ascent: Float; let descent: Float; let bottom: Float; let leading: Float }

    /// Paint.FontMetricsInt of the default family.
    struct IntMetrics { let top: Int; let ascent: Int; let descent: Int; let bottom: Int; let leading: Int }

    /// SkScalerContext_FreeType::generateFontMetrics of Roboto at `size` px.
    static func metrics(_ size: Float) -> Metrics {
        let upem = Float(2048)
        let ascent = -Float(1900) / upem
        let descent = -Float(-500) / upem
        let ymax = -Float(2163) / upem
        let ymin = -Float(-555) / upem
        return Metrics(top: ymax * size, ascent: ascent * size, descent: descent * size, bottom: ymin * size, leading: 0)
    }

    /// Paint.getFontMetricsInt (top floor, ascent/descent/leading round, bottom ceil).
    static func intMetrics(_ size: Float) -> IntMetrics {
        let m = metrics(size)
        return IntMetrics(top: AWMath.skFloor(m.top), ascent: AWMath.skRound(m.ascent), descent: AWMath.skRound(m.descent),
                          bottom: AWMath.skCeil(m.bottom), leading: AWMath.skRound(m.leading))
    }

    /// The return value of Paint.getFontMetricsInt(null): round(descent - ascent + leading) of the float metrics.
    static func fontSpacing(_ size: Float) -> Int {
        let m = metrics(size)
        return AWMath.skRound(m.descent - m.ascent + m.leading)
    }

    // Roboto (Android 15/16 Roboto-Regular.ttf) cmap coverage, inclusive ranges.
    private static let robotoCoverage: [(UInt32, UInt32)] = [
        (0x0, 0x7E), (0xA0, 0x377), (0x37A, 0x37F), (0x384, 0x38A), (0x38C, 0x38C), (0x38E, 0x3A1), (0x3A3, 0x3E1),
        (0x3F0, 0x52F), (0x1AB0, 0x1ABE), (0x1D00, 0x1DF5), (0x1DFC, 0x1F15), (0x1F18, 0x1F1D), (0x1F20, 0x1F45),
        (0x1F48, 0x1F4D), (0x1F50, 0x1F57), (0x1F59, 0x1F59), (0x1F5B, 0x1F5B), (0x1F5D, 0x1F5D), (0x1F5F, 0x1F7D),
        (0x1F80, 0x1FB4), (0x1FB6, 0x1FC4), (0x1FC6, 0x1FD3), (0x1FD6, 0x1FDB), (0x1FDD, 0x1FEF), (0x1FF2, 0x1FF4),
        (0x1FF6, 0x1FFE), (0x2000, 0x2029), (0x202F, 0x205F), (0x2070, 0x2071), (0x2074, 0x208E), (0x2090, 0x209C),
        (0x20A0, 0x20BE), (0x20C1, 0x20C1), (0x20DB, 0x20DC), (0x20E8, 0x20E8), (0x20F0, 0x20F0), (0x2100, 0x2101),
        (0x2103, 0x2103), (0x2105, 0x2106), (0x2109, 0x2109), (0x2113, 0x2113), (0x2116, 0x2117), (0x211E, 0x2123),
        (0x2125, 0x2126), (0x212A, 0x212B), (0x212E, 0x212E), (0x2132, 0x2132), (0x213B, 0x213B), (0x214D, 0x214D),
        (0x214F, 0x2189), (0x2202, 0x2202), (0x2206, 0x2206), (0x220F, 0x220F), (0x2211, 0x2212), (0x221A, 0x221A),
        (0x221E, 0x221E), (0x222B, 0x222B), (0x2248, 0x2248), (0x2260, 0x2260), (0x2264, 0x2265), (0x2423, 0x2423),
        (0x25A0, 0x25A0), (0x25CA, 0x25CB), (0x25CF, 0x25CF), (0x27E6, 0x27EF), (0x2B4E, 0x2B4F), (0x2B5A, 0x2B5F),
        (0x2C60, 0x2C7F), (0x2DE0, 0x2E42), (0xA640, 0xA69D), (0xA69F, 0xA69F), (0xA700, 0xA7AD), (0xA7B0, 0xA7B1),
        (0xA7F7, 0xA7FF), (0xA92E, 0xA92E), (0xAB30, 0xAB5F), (0xAB64, 0xAB65), (0xEE01, 0xEE02), (0xF6C3, 0xF6C3),
        (0xFB00, 0xFB06), (0xFE20, 0xFE2D), (0xFEFF, 0xFEFF), (0xFFFC, 0xFFFD), (0x1F16A, 0x1F16B),
    ]

    static func robotoCovers(_ cp: UInt32) -> Bool {
        var lo = 0, hi = robotoCoverage.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let r = robotoCoverage[mid]
            if cp < r.0 { hi = mid - 1 } else if cp > r.1 { lo = mid + 1 } else { return true }
        }
        return false
    }

    private static func isDefaultIgnorable(_ cp: UInt32) -> Bool {
        return cp < 0x20 || cp == 0xAD || cp == 0x34F || cp == 0x61C || (cp >= 0x180B && cp <= 0x180F)
            || (cp >= 0x200B && cp <= 0x200F) || (cp >= 0x202A && cp <= 0x202E) || (cp >= 0x2060 && cp <= 0x206F)
            || (cp >= 0xFE00 && cp <= 0xFE0F) || cp == 0xFEFF || (cp >= 0xE0000 && cp <= 0xE0FFF)
    }

    /// The (ascent, descent) em fractions of the fallback font that renders `cp` instead of Roboto, or nil when the
    /// code point does not extend the line (Roboto itself, the emoji font, default-ignorables).
    static func fallbackExtent(_ cp: UInt32, emojiVariation: Bool) -> (ascent: Float, descent: Float)? {
        if isDefaultIgnorable(cp) || emojiVariation { return nil }
        if let s = Unicode.Scalar(cp), s.properties.isEmojiPresentation { return nil }
        if robotoCovers(cp) { return nil }
        if (cp >= 0x0590 && cp <= 0x05FF) || (cp >= 0xFB1D && cp <= 0xFB4F) {
            return (Float(1068) / Float(1000), Float(292) / Float(1000))
        }
        if (cp >= 0x0900 && cp <= 0x097F) || (cp >= 0xA8E0 && cp <= 0xA8FF) {
            return (Float(896) / Float(1000), Float(408) / Float(1000))
        }
        if (cp >= 0x1200 && cp <= 0x139F) || (cp >= 0x2D80 && cp <= 0x2DDF) || (cp >= 0xAB00 && cp <= 0xAB2F) {
            return (Float(1069) / Float(1000), Float(293) / Float(1000))
        }
        if (cp >= 0x2E80 && cp <= 0x9FFF) || (cp >= 0xAC00 && cp <= 0xD7AF) || (cp >= 0xF900 && cp <= 0xFAFF)
            || (cp >= 0xFF00 && cp <= 0xFFEF) || (cp >= 0x20000 && cp <= 0x3FFFF) {
            return (Float(1160) / Float(1000), Float(288) / Float(1000))
        }
        // Arabic (NotoNaskhArabicUI), Noto Sans Symbols and the other Noto fallbacks.
        return (Float(2189) / Float(2048), Float(600) / Float(2048))
    }

    /// minikin MeasuredText.getExtent for UTF-16 units [start, end): the min ascent / max descent (px, Android signs)
    /// of the fonts that render them, `sizeAt` giving each unit's text size. Roboto is always part of a non-empty range.
    static func extent(_ units: [UInt16], _ start: Int, _ end: Int, _ sizeAt: (Int) -> Float) -> (ascent: Float, descent: Float) {
        var ascent: Float = 0, descent: Float = 0
        var k = start
        while k < end {
            var cp = UInt32(units[k])
            var step = 1
            if units[k] >= 0xD800 && units[k] <= 0xDBFF && k + 1 < end && units[k + 1] >= 0xDC00 && units[k + 1] <= 0xDFFF {
                cp = 0x10000 + ((UInt32(units[k]) - 0xD800) << 10) + (UInt32(units[k + 1]) - 0xDC00)
                step = 2
            }
            let size = sizeAt(k)
            let roboto = metrics(size)
            if roboto.ascent < ascent { ascent = roboto.ascent }
            if roboto.descent > descent { descent = roboto.descent }
            let emojiVariation = k + step < end && units[k + step] == 0xFE0F
            if let e = fallbackExtent(cp, emojiVariation: emojiVariation) {
                let a = (-e.ascent) * size, d = e.descent * size
                if a < ascent { ascent = a }
                if d > descent { descent = d }
            }
            k += step
        }
        return (ascent, descent)
    }
}

// MARK: - Shaping (the APaint.kgLine rules applied to attributed paragraphs)

enum AWShaping {
    /// Attribute carrying the index of the character-style run (spans) a range belongs to, so Core Text splits
    /// glyph runs wherever the drawing paint changes.
    static let styleKey = NSAttributedString.Key("AndroidKit.textStyleRun")
    static let fontKey = NSAttributedString.Key(kCTFontAttributeName as String)
    static let kernKey = NSAttributedString.Key(kCTKernAttributeName as String)
    static let ligatureKey = NSAttributedString.Key(kCTLigatureAttributeName as String)
    static let paragraphKey = NSAttributedString.Key(kCTParagraphStyleAttributeName as String)

    /// Applies `paint`'s font and minikin letter spacing to `range` of `ns` (exactly what APaint.kgLine does for a
    /// whole string): a kern of letterSpacing * textSize * textScaleX on the last UTF-16 unit of every grapheme
    /// cluster in a letter-spacing capable script, optional ligatures off when |letterSpacing| > 0.03.
    static func apply(_ ns: NSMutableAttributedString, _ range: NSRange, _ paint: APaint) {
        if range.length <= 0 { return }
        ns.addAttribute(fontKey, value: paint.kgFont(), range: range)
        let spacing = paint.kgLetterSpacing().perCluster
        if spacing == 0 { return }
        if abs(paint.letterSpacing) > 0.03 {
            ns.addAttribute(ligatureKey, value: NSNumber(value: 0), range: range)
        }
        let kern = NSNumber(value: Double(spacing / KitGraphics.density))
        let sub = (ns.string as NSString).substring(with: range)
        var offset = range.location
        for ch in sub {
            let n = ch.utf16.count
            if n > 0 && APaint.kgScriptOkForLetterSpacing(ch) {
                ns.addAttribute(kernKey, value: kern, range: NSRange(location: offset + n - 1, length: 1))
            }
            offset += n
        }
    }

    /// A paragraph style forcing the base direction.
    static func paragraphStyle(_ rtl: Bool) -> CTParagraphStyle {
        var direction: CTWritingDirection = rtl ? .rightToLeft : .leftToRight
        return withUnsafeMutablePointer(to: &direction) { ptr -> CTParagraphStyle in
            var setting = CTParagraphStyleSetting(spec: .baseWritingDirection, valueSize: MemoryLayout<CTWritingDirection>.size, value: ptr)
            return CTParagraphStyleCreate(&setting, 1)
        }
    }

    /// The typographic width of a Core Text line in px.
    static func width(_ line: CTLine) -> Float {
        return Float(CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) * KitGraphics.density)
    }
}

// MARK: - android.text.Layout

/// android.text.Layout as TextView builds it (StaticLayout semantics; a BoringLayout is a one-line layout whose line
/// width is the ceil'd boring width). Line tops, descents, baselines and ellipsis follow StaticLayout.out exactly.
final class ALayout {
    enum Alignment { case ALIGN_NORMAL, ALIGN_OPPOSITE, ALIGN_CENTER, ALIGN_LEFT, ALIGN_RIGHT }

    static let DIR_LEFT_TO_RIGHT = 1, DIR_RIGHT_TO_LEFT = -1
    static let BREAK_STRATEGY_SIMPLE = 0, BREAK_STRATEGY_HIGH_QUALITY = 1, BREAK_STRATEGY_BALANCED = 2
    static let HYPHENATION_FREQUENCY_NONE = 0, HYPHENATION_FREQUENCY_NORMAL = 1, HYPHENATION_FREQUENCY_FULL = 2,
               HYPHENATION_FREQUENCY_NORMAL_FAST = 3, HYPHENATION_FREQUENCY_FULL_FAST = 4
    static let JUSTIFICATION_MODE_NONE = 0, JUSTIFICATION_MODE_INTER_WORD = 1
    /// StaticLayout.DEFAULT_MAX_LINE_HEIGHT.
    private static let DEFAULT_MAX_LINE_HEIGHT = -1
    /// StaticLayout.EXTRA_ROUNDING.
    private static let EXTRA_ROUNDING = 0.5

    /// One line (the StaticLayout mLines columns).
    struct Line {
        var start: Int
        var top: Int
        var descent: Int      // below + extra
        var extra: Int
        var dir: Int
        var paragraph: Int    // index into `paragraphs`, -1 for the empty line after a trailing '\n'
        var ellipsisStart: Int = 0
        var ellipsisCount: Int = 0
    }

    /// A measured paragraph (MeasuredParagraph): the text without its '\n', direction, Core Text typesetter and
    /// minikin-style advances per UTF-16 unit (a cluster's advance on its first unit, letter spacing included).
    final class Paragraph {
        let start: Int
        let textEnd: Int
        let dir: Int
        let string: String
        let attributed: NSAttributedString
        let typesetter: CTTypesetter
        let widths: [Float]
        init(start: Int, textEnd: Int, dir: Int, string: String, attributed: NSAttributedString, typesetter: CTTypesetter, widths: [Float]) {
            self.start = start; self.textEnd = textEnd; self.dir = dir; self.string = string
            self.attributed = attributed; self.typesetter = typesetter; self.widths = widths
        }
    }

    /// A range with one set of character-style spans (drawing paint) and its metric paint.
    struct StyleRun {
        let start: Int
        let end: Int
        let spans: [ACharacterStyle]
        let measurePaint: APaint
    }

    // MARK: Inputs

    let text: ACharSequence
    let units: [UInt16]
    /// The TextView's TextPaint: read at draw time (colour, style, shadow) like Android's mPaint.
    let paint: APaint
    let width: Int
    let alignment: Alignment
    let textDir: ATextDirectionHeuristic
    let spacingMultiplier: Float
    let spacingAdd: Float
    let includePad: Bool
    let ellipsize: ATextUtils.TruncateAt?
    let ellipsizedWidth: Int
    let maximumVisibleLineCount: Int
    let breakStrategy: Int
    /// BoringLayout: the ceil'd width of the single line (getLineMax / getLineWidth), nil for StaticLayout.
    let boringWidth: Int?

    // MARK: Results

    private(set) var lines: [Line] = []
    private var lineTops: [Int] = [0]
    private(set) var paragraphs: [Paragraph] = []
    private(set) var styleRuns: [StyleRun] = []
    private(set) var topPadding = 0
    private(set) var bottomPadding = 0
    private var maxLineHeight = ALayout.DEFAULT_MAX_LINE_HEIGHT
    private(set) var isEllipsized = false
    private var lineCache: [Int: (line: CTLine, display: String, width: Float)] = [:]

    // MARK: Building (StaticLayout.Builder.build / BoringLayout)

    init(text: ACharSequence, paint: APaint, width: Int, alignment: Alignment, textDir: ATextDirectionHeuristic,
         spacingMult: Float, spacingAdd: Float, includePad: Bool, ellipsize: ATextUtils.TruncateAt?,
         ellipsizedWidth: Int, maxLines: Int, breakStrategy: Int, boringWidth: Int? = nil) {
        self.text = text
        self.units = Array(text.aw_plain.utf16)
        self.paint = paint
        self.width = width
        self.alignment = alignment
        self.textDir = textDir
        self.spacingMultiplier = spacingMult
        self.spacingAdd = spacingAdd
        self.includePad = includePad
        self.ellipsize = ellipsize
        self.ellipsizedWidth = ellipsizedWidth
        self.maximumVisibleLineCount = maxLines
        self.breakStrategy = breakStrategy
        self.boringWidth = boringWidth
        self.styleRuns = ALayout.buildStyleRuns(text, paint, units.count)
        generate()
    }

    /// Splits the text at every character-style span transition; each run keeps its spans (Spanned.getSpans order)
    /// and a paint updated by the metric-affecting ones (MetricAffectingSpan.updateMeasureState).
    static func buildStyleRuns(_ text: ACharSequence, _ paint: APaint, _ length: Int) -> [StyleRun] {
        let records = (text as? ASpannableString)?.spans.filter { $0.span is ACharacterStyle && $0.end > $0.start } ?? []
        if records.isEmpty {
            return [StyleRun(start: 0, end: length, spans: [], measurePaint: paint)]
        }
        var bounds = Set<Int>([0, length])
        for r in records {
            bounds.insert(max(0, min(r.start, length)))
            bounds.insert(max(0, min(r.end, length)))
        }
        let sorted = bounds.sorted()
        var runs: [StyleRun] = []
        for i in 0..<(sorted.count - 1) {
            let s = sorted[i], e = sorted[i + 1]
            if e <= s { continue }
            let spans = records.filter { $0.start <= s && $0.end >= e }.map { $0.span as! ACharacterStyle }
            var mp = paint
            if spans.contains(where: { $0.aw_affectsMetrics }) {
                mp = APaint(paint)
                for sp in spans where sp.aw_affectsMetrics { sp.aw_updateMeasureState(mp) }
            }
            runs.append(StyleRun(start: s, end: e, spans: spans, measurePaint: mp))
        }
        return runs
    }

    private func styleRunIndex(at index: Int) -> Int {
        var lo = 0, hi = styleRuns.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let r = styleRuns[mid]
            if index < r.start { hi = mid - 1 } else if index >= r.end { lo = mid + 1 } else { return mid }
        }
        return max(0, min(styleRuns.count - 1, lo))
    }

    private func textSizeAt(_ index: Int) -> Float {
        if styleRuns.count == 1 { return styleRuns[0].measurePaint.textSize }
        return styleRuns[styleRunIndex(at: index)].measurePaint.textSize
    }

    /// Builds the attributed text of [start, end) with each style run's font, letter spacing and run index.
    static func attributed(_ units: [UInt16], _ start: Int, _ end: Int, _ runs: [StyleRun], _ rtl: Bool) -> NSMutableAttributedString {
        let string = String(decoding: units[start..<end], as: UTF16.self)
        let ns = NSMutableAttributedString(string: string)
        if end <= start { return ns }
        ns.addAttribute(AWShaping.paragraphKey, value: AWShaping.paragraphStyle(rtl), range: NSRange(location: 0, length: end - start))
        for (i, r) in runs.enumerated() {
            let s = max(r.start, start), e = min(r.end, end)
            if e <= s { continue }
            let range = NSRange(location: s - start, length: e - s)
            AWShaping.apply(ns, range, r.measurePaint)
            ns.addAttribute(AWShaping.styleKey, value: NSNumber(value: i), range: range)
        }
        return ns
    }

    /// MeasuredParagraph: shaping and per-unit advances of one paragraph.
    private func measureParagraph(_ start: Int, _ textEnd: Int, _ dir: Int) -> Paragraph {
        let ns = ALayout.attributed(units, start, textEnd, styleRuns, dir == ALayout.DIR_RIGHT_TO_LEFT)
        let typesetter = CTTypesetterCreateWithAttributedString(ns as CFAttributedString)
        var widths = [Float](repeating: 0, count: textEnd - start)
        if textEnd > start {
            let line = CTTypesetterCreateLine(typesetter, CFRange(location: 0, length: 0))
            let d = KitGraphics.density
            for item in (CTLineGetGlyphRuns(line) as NSArray) {
                let run = item as! CTRun
                let count = CTRunGetGlyphCount(run)
                if count == 0 { continue }
                var advances = [CGSize](repeating: .zero, count: count)
                var indices = [CFIndex](repeating: 0, count: count)
                CTRunGetAdvances(run, CFRange(location: 0, length: 0), &advances)
                CTRunGetStringIndices(run, CFRange(location: 0, length: 0), &indices)
                for g in 0..<count {
                    let idx = indices[g]
                    if idx >= 0 && idx < widths.count { widths[idx] += Float(advances[g].width * d) }
                }
            }
        }
        return Paragraph(start: start, textEnd: textEnd, dir: dir, string: ns.string, attributed: ns,
                         typesetter: typesetter, widths: widths)
    }

    // MARK: minikin line breaking

    /// One break candidate (minikin OptimalLineBreaker Candidate): preBreak = width up to here when the line
    /// continues, postBreak = width up to here when the line breaks here (trailing line-end spaces dropped).
    private struct Candidate {
        let offset: Int
        let preBreak: Float
        let postBreak: Float
        let penalty: Float
    }

    private static let SCORE_INFTY = Float.greatestFiniteMagnitude
    private static let SCORE_OVERFULL: Float = 1e12
    private static let SCORE_DESPERATE: Float = 1e10
    private static let LINE_PENALTY_MULTIPLIER: Float = 2
    private static let LAST_LINE_PENALTY_MULTIPLIER: Float = 4

    /// LineBreakerUtil isLineEndSpace (TextLine.isLineEndSpace plus '\n').
    static func isLineEndSpace(_ c: UInt16) -> Bool {
        return c == 0x0A || c == 0x20 || c == 0x1680 || (0x2000 <= c && c <= 0x200A && c != 0x2007) || c == 0x205F || c == 0x3000
    }

    /// TextLine.isLineEndSpace (Layout.getLineVisibleEnd).
    static func isTextLineEndSpace(_ c: UInt16) -> Bool {
        return c == 0x20 || c == 0x09 || c == 0x1680 || (0x2000 <= c && c <= 0x200A && c != 0x2007) || c == 0x205F || c == 0x3000
    }

    /// The word break offsets (ICU line breaking, as minikin's WordBreaker) of a paragraph, relative to it, ending
    /// with its length.
    private func wordBreaks(_ p: Paragraph) -> [Int] {
        let length = p.textEnd - p.start
        if length == 0 { return [] }
        let tokenizer = CFStringTokenizerCreate(kCFAllocatorDefault, p.string as CFString, CFRange(location: 0, length: length),
                                                kCFStringTokenizerUnitLineBreak, nil)
        var out: [Int] = []
        while !CFStringTokenizerAdvanceToNextToken(tokenizer).isEmpty {
            let r = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            var offset = r.location + r.length
            // The break opportunity follows the spaces after a word (UAX #14 LB18).
            while offset < length && ALayout.isLineEndSpace(units[p.start + offset]) { offset += 1 }
            if offset > 0 && offset <= length && (out.last ?? 0) < offset { out.append(offset) }
        }
        if out.last != length { out.append(length) }
        return out
    }

    /// minikin populateCandidates (no hyphenation, no phrase breaking, letter_spacing_justification off).
    private func candidates(_ p: Paragraph, _ lineWidth: Float) -> (cands: [Candidate], linePenalty: Float) {
        var result = [Candidate(offset: 0, preBreak: 0, postBreak: 0, penalty: 0)]
        let breaks = wordBreaks(p)
        let length = p.textEnd - p.start
        // computePenalties: hyphenPenalty = 0.5 * size * scaleX * lineWidth; linePenalty = hyphenPenalty * 2.
        var linePenalty: Float = 0
        for r in styleRuns where r.end > p.start && r.start < p.textEnd {
            let hyphenPenalty = Float(0.5) * r.measurePaint.textSize * r.measurePaint.textScaleX * lineWidth
            linePenalty = max(linePenalty, hyphenPenalty * ALayout.LINE_PENALTY_MULTIPLIER)
        }
        var sumOfCharWidths: Float = 0
        var effectiveWidth: Float = 0
        var sumAtPrevWordBreak: Float = 0
        var prevWordBreak = 0
        var bi = 0
        var nextWordBreak = breaks.isEmpty ? length : breaks[0]
        for i in 0..<length {
            // CharProcessor.feedChar
            if i == nextWordBreak {
                prevWordBreak = nextWordBreak
                sumAtPrevWordBreak = sumOfCharWidths
                bi += 1
                nextWordBreak = bi < breaks.count ? breaks[bi] : length
            }
            let c = units[p.start + i]
            let w = p.widths[i]
            sumOfCharWidths += w
            if !ALayout.isLineEndSpace(c) { effectiveWidth = sumOfCharWidths }
            let next = i + 1
            if next != nextWordBreak { continue }
            if effectiveWidth - sumAtPrevWordBreak > lineWidth {
                // populateDesperatePoints over the context range [prevWordBreak, nextWordBreak).
                var width = p.widths[prevWordBreak]
                var k = prevWordBreak + 1
                while k < nextWordBreak {
                    let wk = p.widths[k]
                    if wk != 0 {
                        let sum = sumAtPrevWordBreak + width
                        result.append(Candidate(offset: k, preBreak: sum, postBreak: sum, penalty: ALayout.SCORE_DESPERATE))
                        width += wk
                    }
                    k += 1
                }
            }
            result.append(Candidate(offset: next, preBreak: sumOfCharWidths, postBreak: effectiveWidth, penalty: 0))
        }
        return (result, linePenalty)
    }

    /// minikin LineBreakOptimizer.computeBreaks (ragged right, BreakStrategy HighQuality/Balanced).
    private func optimalBreaks(_ cands: [Candidate], _ linePenalty: Float, _ width: Float) -> [(offset: Int, width: Float)] {
        let nCand = cands.count
        var scores = [Float](repeating: 0, count: nCand)
        var prevs = [Int](repeating: 0, count: nCand)
        var active = 0
        for i in 1..<nCand {
            let atEnd = i == nCand - 1
            var best = ALayout.SCORE_INFTY
            var bestPrev = 0
            let leftEdge = cands[i].postBreak - width
            var bestHope: Float = 0
            var j = active
            while j < i {
                let jScore = scores[j]
                if jScore + bestHope >= best { j += 1; continue }
                let delta = cands[j].preBreak - leftEdge
                var widthScore: Float = 0
                var additionalPenalty: Float = 0
                if delta < 0 {
                    widthScore = ALayout.SCORE_OVERFULL
                } else if atEnd && breakStrategy != ALayout.BREAK_STRATEGY_BALANCED {
                    additionalPenalty = ALayout.LAST_LINE_PENALTY_MULTIPLIER * cands[j].penalty
                } else {
                    widthScore = delta * delta
                }
                if delta < 0 { active = j + 1 } else { bestHope = widthScore }
                let score = jScore + widthScore + additionalPenalty
                if score <= best {
                    best = score
                    bestPrev = j
                }
                j += 1
            }
            scores[i] = best + cands[i].penalty + linePenalty
            prevs[i] = bestPrev
        }
        var out: [(offset: Int, width: Float)] = []
        var i = nCand - 1
        while i > 0 {
            let prev = prevs[i]
            out.append((cands[i].offset, cands[i].postBreak - cands[prev].preBreak))
            i = prev
        }
        return out.reversed()
    }

    /// minikin GreedyLineBreaker (BreakStrategy Simple, no hyphenation).
    private func greedyBreaks(_ p: Paragraph, _ limit: Float) -> [(offset: Int, width: Float)] {
        let length = p.textEnd - p.start
        let breaks = wordBreaks(p)
        var out: [(offset: Int, width: Float)] = []
        var lineWidth: Float = 0
        var sumOfCharWidths: Float = 0
        var prevWordBoundsOffset = -1
        var lineWidthAtPrevWordBoundary: Float = 0
        var sumAtPrevWordBoundary: Float = 0
        func prevLineBreakOffset() -> Int { return out.last?.offset ?? 0 }
        func breakLineAt(_ offset: Int, _ width: Float, _ remainingNextLineWidth: Float, _ remainingNextSum: Float) {
            out.append((offset, width))
            lineWidth = remainingNextLineWidth
            sumOfCharWidths = remainingNextSum
            prevWordBoundsOffset = -1
            lineWidthAtPrevWordBoundary = 0
            sumAtPrevWordBoundary = 0
        }
        /// doLineBreakWithGraphemeBounds: true when the whole range fit on the (new) line.
        func breakWithGraphemeBounds(_ start: Int, _ end: Int) -> Bool {
            if start >= end {
                breakLineAt(end, lineWidth, 0, 0)
                return true
            }
            var width = p.widths[start]
            var i = start + 1
            while i < end {
                let w = p.widths[i]
                if w == 0 { i += 1; continue }
                if width + w > limit {
                    breakLineAt(i, width, lineWidth - width, sumOfCharWidths - width)
                    return false
                }
                width += w
                i += 1
            }
            breakLineAt(end, lineWidth, 0, 0)
            return true
        }
        var bi = 0
        var nextWordBoundary = breaks.isEmpty ? length : breaks[0]
        var i = 0
        while i < length {
            let c = units[p.start + i]
            sumOfCharWidths += p.widths[i]
            if !ALayout.isLineEndSpace(c) { lineWidth = sumOfCharWidths }
            if i + 1 == nextWordBoundary {
                let offset = i + 1
                var done = false
                while lineWidth > limit {
                    if prevWordBoundsOffset != -1 {
                        breakLineAt(prevWordBoundsOffset, lineWidthAtPrevWordBoundary,
                                    lineWidth - sumAtPrevWordBoundary, sumOfCharWidths - sumAtPrevWordBoundary)
                        continue
                    }
                    if breakWithGraphemeBounds(prevLineBreakOffset(), offset) { done = true; break }
                }
                if !done {
                    prevWordBoundsOffset = offset
                    lineWidthAtPrevWordBoundary = lineWidth
                    sumAtPrevWordBoundary = sumOfCharWidths
                }
                bi += 1
                nextWordBoundary = bi < breaks.count ? breaks[bi] : length
            }
            i += 1
        }
        if prevLineBreakOffset() != length && prevWordBoundsOffset != -1 {
            breakLineAt(prevWordBoundsOffset, lineWidth, 0, 0)
        }
        return out
    }

    /// LineBreaker.computeLineBreaks for one paragraph: (break offset relative to the paragraph, line width,
    /// ascent, descent) per line.
    private func computeLineBreaks(_ p: Paragraph, _ width: Int) -> [(offset: Int, width: Float, ascent: Float, descent: Float)] {
        let length = p.textEnd - p.start
        if length == 0 { return [] }
        let lineWidth = Float(width)
        var breaks: [(offset: Int, width: Float)]
        if breakStrategy == ALayout.BREAK_STRATEGY_SIMPLE || units[p.start..<p.textEnd].contains(0x09) {
            breaks = greedyBreaks(p, lineWidth)
        } else {
            let (cands, linePenalty) = candidates(p, lineWidth)
            breaks = cands.count <= 1 ? [(offset: length, width: Float(0))] : optimalBreaks(cands, linePenalty, lineWidth)
        }
        var out: [(offset: Int, width: Float, ascent: Float, descent: Float)] = []
        var prev = 0
        for b in breaks {
            let e = AWFontMetrics.extent(units, p.start + prev, p.start + b.offset) { self.textSizeAt($0) }
            out.append((b.offset, b.width, e.ascent, e.descent))
            prev = b.offset
        }
        return out
    }

    // MARK: StaticLayout.generate

    private func generate() {
        let bufEnd = units.count
        let needMultiply = spacingMultiplier != 1 || spacingAdd != 0
        maxLineHeight = maximumVisibleLineCount < 1 ? 0 : ALayout.DEFAULT_MAX_LINE_HEIGHT
        var v = 0
        var paraStart = 0
        while paraStart < bufEnd {
            var textEnd = paraStart
            while textEnd < bufEnd && units[textEnd] != 0x0A { textEnd += 1 }
            let paraEnd = textEnd < bufEnd ? textEnd + 1 : textEnd
            let dir = textDir.isRtl(units, paraStart, paraEnd) ? ALayout.DIR_RIGHT_TO_LEFT : ALayout.DIR_LEFT_TO_RIGHT
            let p = measureParagraph(paraStart, textEnd, dir)
            paragraphs.append(p)
            let paraIndex = paragraphs.count - 1

            var res = computeLineBreaks(p, width)
            if res.isEmpty { res = [(0, 0, 0, 0)] }
            var breaks = res.map { $0.offset }
            var lineWidths = res.map { $0.width }
            let ascents = res.map { $0.ascent }
            let descents = res.map { $0.descent }
            // The paragraph's '\n' (a zero-width line-end space) belongs to its last line.
            if paraEnd > textEnd { breaks[breaks.count - 1] = paraEnd - paraStart }
            var breakCount = breaks.count

            let remainingLineCount = maximumVisibleLineCount - lines.count
            let ellipsisMayBeApplied = ellipsize != nil
                && (ellipsize == .END || (maximumVisibleLineCount == 1 && ellipsize != .MARQUEE))
            if 0 < remainingLineCount && remainingLineCount < breakCount && ellipsisMayBeApplied {
                var w: Float = 0
                for i in (remainingLineCount - 1)..<breakCount {
                    if i == breakCount - 1 {
                        w += lineWidths[i]
                    } else {
                        let from = i == 0 ? 0 : breaks[i - 1]
                        var j = from
                        while j < breaks[i] {
                            if j < p.widths.count { w += p.widths[j] }
                            j += 1
                        }
                    }
                }
                // Treat the last line and overflowed lines as a single line.
                breaks[remainingLineCount - 1] = breaks[breakCount - 1]
                lineWidths[remainingLineCount - 1] = w
                breakCount = remainingLineCount
            }

            // Font metrics of the style runs (fmCache) and the per-line extents (StaticLayout.generate loop).
            var here = paraStart
            var fmTop = 0, fmBottom = 0, fmAscent = 0, fmDescent = 0
            var breakIndex = 0
            var spanStart = paraStart
            while spanStart < paraEnd {
                let ri = styleRunIndex(at: spanStart)
                let spanEnd = min(styleRuns[ri].end, paraEnd)
                let fm = AWFontMetrics.intMetrics(styleRuns[ri].measurePaint.textSize)
                if fm.top < fmTop { fmTop = fm.top }
                if fm.ascent < fmAscent { fmAscent = fm.ascent }
                if fm.descent > fmDescent { fmDescent = fm.descent }
                if fm.bottom > fmBottom { fmBottom = fm.bottom }
                while breakIndex < breakCount && paraStart + breaks[breakIndex] < spanStart { breakIndex += 1 }
                while breakIndex < breakCount && paraStart + breaks[breakIndex] <= spanEnd {
                    let endPos = paraStart + breaks[breakIndex]
                    let moreChars = endPos < bufEnd
                    let ascent = min(fmAscent, AWMath.round(ascents[min(breakIndex, ascents.count - 1)]))
                    let descent = max(fmDescent, AWMath.round(descents[min(breakIndex, descents.count - 1)]))
                    // The fallback ascent/descent may be larger than top/bottom of the default font metrics.
                    if ascent < fmTop { fmTop = ascent }
                    if descent > fmBottom { fmBottom = descent }
                    v = out(here, endPos, ascent, descent, fmTop, fmBottom, v, needMultiply, p, paraIndex, lineWidths[breakIndex], moreChars)
                    if endPos < spanEnd {
                        fmTop = min(0, fm.top)
                        fmBottom = max(0, fm.bottom)
                        fmAscent = min(0, fm.ascent)
                        fmDescent = max(0, fm.descent)
                    } else {
                        fmTop = 0; fmBottom = 0; fmAscent = 0; fmDescent = 0
                    }
                    here = endPos
                    breakIndex += 1
                    if lines.count >= maximumVisibleLineCount && isEllipsized { return }
                }
                spanStart = spanEnd
            }
            if paraEnd == bufEnd { break }
            paraStart = paraEnd
        }
        if (bufEnd == 0 || units[bufEnd - 1] == 0x0A) && lines.count < maximumVisibleLineCount {
            let fm = AWFontMetrics.intMetrics(paint.textSize)
            v = out(bufEnd, bufEnd, fm.ascent, fm.descent, fm.top, fm.bottom, v, needMultiply, nil, -1, 0, false)
        }
    }

    /// StaticLayout.out.
    private func out(_ start: Int, _ end: Int, _ above0: Int, _ below0: Int, _ top: Int, _ bottom: Int, _ v0: Int,
                     _ needMultiply: Bool, _ p: Paragraph?, _ paraIndex: Int, _ textWidth: Float, _ moreChars: Bool) -> Int {
        var above = above0, below = below0
        let j = lines.count
        let dir = p?.dir ?? ALayout.DIR_LEFT_TO_RIGHT
        var line = Line(start: start, top: v0, descent: 0, extra: 0, dir: dir, paragraph: paraIndex)
        let firstLine = j == 0
        let currentLineIsTheLastVisibleOne = j + 1 == maximumVisibleLineCount
        if let ellipsize = ellipsize {
            let forceEllipsis = moreChars && (lines.count + 1 == maximumVisibleLineCount)
            let doEllipsis = (((maximumVisibleLineCount == 1 && moreChars) || (firstLine && !moreChars)) && ellipsize != .MARQUEE)
                || (!firstLine && (currentLineIsTheLastVisibleOne || !moreChars) && ellipsize == .END)
            if doEllipsis, let p = p {
                calculateEllipsis(&line, start, end, p, Float(ellipsizedWidth), ellipsize, textWidth, forceEllipsis)
            }
        }
        let lastLine: Bool
        if isEllipsized {
            lastLine = true
        } else {
            let bufEnd = units.count
            let lastCharIsNewLine = start != bufEnd && bufEnd > 0 && units[bufEnd - 1] == 0x0A
            if end == bufEnd && !lastCharIsNewLine {
                lastLine = true
            } else if start == bufEnd && lastCharIsNewLine {
                lastLine = true
            } else {
                lastLine = false
            }
        }
        if firstLine {
            topPadding = top - above
            if includePad { above = top }
        }
        var extra: Int
        if lastLine {
            bottomPadding = bottom - below
            if includePad { below = bottom }
        }
        if needMultiply && !lastLine {
            let ex = Double(below - above) * Double(spacingMultiplier - 1) + Double(spacingAdd)
            if ex >= 0 {
                extra = AWMath.javaInt(ex + ALayout.EXTRA_ROUNDING)
            } else {
                extra = -AWMath.javaInt(-ex + ALayout.EXTRA_ROUNDING)
            }
        } else {
            extra = 0
        }
        line.descent = below + extra
        line.extra = extra
        if !isEllipsized && currentLineIsTheLastVisibleOne {
            let maxLineBelow = includePad ? bottom : below
            maxLineHeight = v0 + (maxLineBelow - above)
        }
        let v = v0 + (below - above) + extra
        lines.append(line)
        lineTops.append(v)
        return v
    }

    /// StaticLayout.calculateEllipsis (char widths of the measured paragraph).
    private func calculateEllipsis(_ line: inout Line, _ lineStart: Int, _ lineEnd: Int, _ p: Paragraph, _ avail: Float,
                                   _ where_: ATextUtils.TruncateAt, _ textWidth: Float, _ forceEllipsis: Bool) {
        if textWidth <= avail && !forceEllipsis {
            line.ellipsisStart = 0
            line.ellipsisCount = 0
            return
        }
        let ellipsisWidth = paint.measureText(ATextUtils.getEllipsisString(where_))
        func w(_ i: Int) -> Float {
            let k = i + lineStart - p.start
            return k >= 0 && k < p.widths.count ? p.widths[k] : 0
        }
        var ellipsisStart = 0, ellipsisCount = 0
        let len = lineEnd - lineStart
        switch where_ {
        case .START:
            if maximumVisibleLineCount == 1 {
                var sum: Float = 0
                var i = len
                while i > 0 {
                    let cw = w(i - 1)
                    if cw + sum + ellipsisWidth > avail {
                        while i < len && w(i) == 0 { i += 1 }
                        break
                    }
                    sum += cw
                    i -= 1
                }
                ellipsisStart = 0
                ellipsisCount = i
            }
        case .END, .MARQUEE, .END_SMALL:
            var sum: Float = 0
            var i = 0
            while i < len {
                let cw = w(i)
                if cw + sum + ellipsisWidth > avail { break }
                sum += cw
                i += 1
            }
            ellipsisStart = i
            ellipsisCount = len - i
            if forceEllipsis && ellipsisCount == 0 && len > 0 {
                ellipsisStart = len - 1
                ellipsisCount = 1
            }
        case .MIDDLE:
            if maximumVisibleLineCount == 1 {
                var lsum: Float = 0, rsum: Float = 0
                var left = 0, right = len
                let ravail = (avail - ellipsisWidth) / 2
                right = len
                while right > 0 {
                    let cw = w(right - 1)
                    if cw + rsum > ravail {
                        while right < len && w(right) == 0 { right += 1 }
                        break
                    }
                    rsum += cw
                    right -= 1
                }
                let lavail = avail - ellipsisWidth - rsum
                left = 0
                while left < right {
                    let cw = w(left)
                    if cw + lsum > lavail { break }
                    lsum += cw
                    left += 1
                }
                ellipsisStart = left
                ellipsisCount = right - left
            }
        }
        isEllipsized = true
        line.ellipsisStart = ellipsisStart
        line.ellipsisCount = ellipsisCount
    }

    // MARK: Line accessors (Layout / StaticLayout)

    var lineCount: Int { return lines.count }
    func getLineCount() -> Int { return lines.count }
    var height: Int { return getLineTop(lineCount) }
    func getHeight() -> Int { return height }
    func getWidth() -> Int { return width }
    func getText() -> String { return text.aw_plain }
    func getPaint() -> APaint { return paint }
    func getEllipsizedWidth() -> Int { return ellipsizedWidth }
    func getTopPadding() -> Int { return topPadding }
    func getBottomPadding() -> Int { return bottomPadding }
    func getAlignment() -> Alignment { return alignment }
    func getSpacingMultiplier() -> Float { return spacingMultiplier }
    func getSpacingAdd() -> Float { return spacingAdd }

    /// StaticLayout.getHeight(cap): the height of the first maxLines lines when the text has more.
    func getHeight(_ cap: Bool) -> Int {
        return cap && lines.count > maximumVisibleLineCount && maxLineHeight != ALayout.DEFAULT_MAX_LINE_HEIGHT
            ? maxLineHeight : height
    }

    func getLineTop(_ line: Int) -> Int { return lineTops[line] }
    func getLineBottom(_ line: Int) -> Int { return lineTops[line + 1] }
    func getLineDescent(_ line: Int) -> Int { return lines[line].descent }
    func getLineExtra(_ line: Int) -> Int { return lines[line].extra }
    func getLineBaseline(_ line: Int) -> Int { return getLineTop(line + 1) - getLineDescent(line) }
    func getLineAscent(_ line: Int) -> Int { return getLineTop(line) - (getLineTop(line + 1) - getLineDescent(line)) }
    func getLineStart(_ line: Int) -> Int { return line >= lines.count ? units.count : lines[line].start }
    func getLineEnd(_ line: Int) -> Int { return getLineStart(line + 1) }
    func getParagraphDirection(_ line: Int) -> Int { return lines[line].dir }
    /// Layout.getParagraphAlignment: the last AlignmentSpan (getParagraphSpans over the line's range) wins over the
    /// layout's alignment.
    func getParagraphAlignment(_ line: Int) -> Alignment {
        var align = alignment
        guard let sp = text as? ASpannableString else { return align }
        let start = getLineStart(line), end = getLineEnd(line)
        for record in sp.spans where record.end > record.start {   // getParagraphSpans drops empty spans
            // SpannableStringBuilder.getSpans(start, end): overlapping, but not only touching a non-empty range.
            guard record.start <= end && record.end >= start else { continue }
            if start != end && (record.start == end || record.end == start) { continue }
            if let a = record.span as? AAlignmentSpan.Standard { align = a.getAlignment() }
        }
        return align
    }
    func getEllipsisStart(_ line: Int) -> Int { return lines[line].ellipsisStart }
    func getEllipsisCount(_ line: Int) -> Int { return lines[line].ellipsisCount }

    /// Layout.getLineVisibleEnd (trailing spaces of the last line count as visible, Android 15).
    func getLineVisibleEnd(_ line: Int) -> Int {
        return lineVisibleEnd(line, getLineStart(line), getLineStart(line + 1), true)
    }

    private func lineVisibleEnd(_ line: Int, _ start: Int, _ end0: Int, _ trailingSpaceAtLastLineIsVisible: Bool) -> Int {
        var end = end0
        if trailingSpaceAtLastLineIsVisible && line == lineCount - 1 { return end }
        while end > start {
            let ch = units[end - 1]
            if ch == 0x0A { return end - 1 }
            if !ALayout.isTextLineEndSpace(ch) { break }
            end -= 1
        }
        return end
    }

    /// StaticLayout.getLineForVertical.
    func getLineForVertical(_ vertical: Int) -> Int {
        var high = lineCount, low = -1
        while high - low > 1 {
            let guess = (high + low) >> 1
            if lineTops[guess] > vertical { high = guess } else { low = guess }
        }
        return low < 0 ? 0 : low
    }

    /// Layout.getLineForOffset.
    func getLineForOffset(_ offset: Int) -> Int {
        var high = lineCount, low = -1
        while high - low > 1 {
            let guess = (high + low) / 2
            if getLineStart(guess) > offset { high = guess } else { low = guess }
        }
        return low < 0 ? 0 : low
    }

    // MARK: Line extents (TextLine.metrics)

    /// The shaped line [start, end) of `line` as drawn: the paragraph text, or the ellipsized display string
    /// (ellipsis "…"/"‥" at the ellipsis start with that position's style, the rest of the range dropped).
    private func shapedLine(_ index: Int, _ end: Int) -> (line: CTLine, display: String, offset: Int, width: Float)? {
        let l = lines[index]
        guard l.paragraph >= 0 else { return nil }
        let p = paragraphs[l.paragraph]
        let s = l.start - p.start
        let e = max(s, min(end, p.textEnd) - p.start)
        if l.ellipsisCount > 0 {
            if let c = lineCache[index] { return (c.line, c.display, -1, c.width) }
            let a = NSMutableAttributedString()
            let es = s + l.ellipsisStart
            let ee = min(es + l.ellipsisCount, p.textEnd - p.start)
            if es > s { a.append(p.attributed.attributedSubstring(from: NSRange(location: s, length: es - s))) }
            let attrIndex = p.attributed.length > 0 ? min(max(es, 0), p.attributed.length - 1) : 0
            let attrs = p.attributed.length > 0 ? p.attributed.attributes(at: attrIndex, effectiveRange: nil) : [:]
            let ellipsis = NSMutableAttributedString(string: ATextUtils.getEllipsisString(ellipsize ?? .END), attributes: attrs)
            ellipsis.removeAttribute(AWShaping.kernKey, range: NSRange(location: 0, length: ellipsis.length))
            if let run = styleRuns.getOrNull((attrs[AWShaping.styleKey] as? NSNumber)?.intValue ?? 0) {
                AWShaping.apply(ellipsis, NSRange(location: 0, length: ellipsis.length), run.measurePaint)
            }
            a.append(ellipsis)
            if e > ee { a.append(p.attributed.attributedSubstring(from: NSRange(location: ee, length: e - ee))) }
            a.addAttribute(AWShaping.paragraphKey, value: AWShaping.paragraphStyle(p.dir == ALayout.DIR_RIGHT_TO_LEFT),
                           range: NSRange(location: 0, length: a.length))
            let ct = CTLineCreateWithAttributedString(a as CFAttributedString)
            let w = AWShaping.width(ct)
            lineCache[index] = (ct, a.string, w)
            return (ct, a.string, -1, w)
        }
        let ct = CTTypesetterCreateLine(p.typesetter, CFRange(location: s, length: e - s))
        return (ct, p.string, p.start, AWShaping.width(ct))
    }

    /// Layout.getLineExtent: signed (negative for RTL paragraphs) like TextLine.metrics.
    private func lineExtent(_ index: Int, full: Bool) -> Float {
        let l = lines[index]
        guard l.paragraph >= 0 else { return 0 }
        let end = full ? getLineEnd(index) : getLineVisibleEnd(index)
        guard let shaped = shapedLine(index, end) else { return 0 }
        return l.dir == ALayout.DIR_RIGHT_TO_LEFT ? -shaped.width : shaped.width
    }

    /// Layout.getLineWidth: the full line width (trailing spaces included).
    func getLineWidth(_ line: Int) -> Float {
        if let b = boringWidth { return line == 0 ? Float(b) : 0 }
        return abs(lineExtent(line, full: true))
    }

    /// Layout.getLineMax: the visible line width.
    func getLineMax(_ line: Int) -> Float {
        if let b = boringWidth { return Float(b) }
        return abs(lineExtent(line, full: false))
    }

    private func resolvedAlignment(_ line: Int) -> Alignment {
        let dir = getParagraphDirection(line)
        switch getParagraphAlignment(line) {
        case .ALIGN_NORMAL: return dir == ALayout.DIR_RIGHT_TO_LEFT ? .ALIGN_RIGHT : .ALIGN_LEFT
        case .ALIGN_OPPOSITE: return dir == ALayout.DIR_RIGHT_TO_LEFT ? .ALIGN_LEFT : .ALIGN_RIGHT
        case .ALIGN_CENTER: return .ALIGN_CENTER
        case .ALIGN_RIGHT: return .ALIGN_RIGHT
        case .ALIGN_LEFT: return .ALIGN_LEFT
        }
    }

    /// Layout.getLineLeft.
    func getLineLeft(_ line: Int) -> Float {
        switch resolvedAlignment(line) {
        case .ALIGN_CENTER:
            let max = getLineMax(line)
            return Float((Double(0) + Double((Float(width) - max) / 2)).rounded(.down))
        case .ALIGN_RIGHT:
            return Float(width) - getLineMax(line)
        default:
            return 0
        }
    }

    /// Layout.getLineRight.
    func getLineRight(_ line: Int) -> Float {
        switch resolvedAlignment(line) {
        case .ALIGN_CENTER:
            let max = getLineMax(line)
            return Float((Double(width) - Double((Float(width) - max) / 2)).rounded(.up))
        case .ALIGN_RIGHT:
            return Float(width)
        default:
            return getLineMax(line)
        }
    }

    // MARK: Desired width

    /// Layout.getDesiredWidthWithLimit: the widest paragraph (trailing spaces included), capped at `upperLimit`.
    static func getDesiredWidthWithLimit(_ source: ACharSequence, _ start: Int, _ end: Int, _ paint: APaint,
                                         _ textDir: ATextDirectionHeuristic, _ upperLimit: Float) -> Float {
        let units = Array(source.aw_plain.utf16)
        let runs = buildStyleRuns(source, paint, units.count)
        var need: Float = 0
        var i = start
        while i <= end {
            var next = i
            while next < end && units[next] != 0x0A { next += 1 }
            let rtl = textDir.isRtl(units, i, next)
            let w: Float
            if next > i {
                let ns = attributed(units, i, next, runs, rtl)
                w = AWShaping.width(CTLineCreateWithAttributedString(ns as CFAttributedString))
            } else {
                w = 0
            }
            if w > upperLimit { return upperLimit }
            if w > need { need = w }
            i = next + 1
        }
        return need
    }

    static func getDesiredWidth(_ source: ACharSequence, _ paint: APaint) -> Float {
        let n = source.aw_plain.utf16.count
        return getDesiredWidthWithLimit(source, 0, n, paint, .FIRSTSTRONG_LTR, Float.greatestFiniteMagnitude)
    }

    /// BoringLayout.isBoring: the ceil'd width of a one-line LTR text without RTL-affecting characters, newlines,
    /// tabs or paragraph spans; nil when the text is not boring.
    static func isBoringWidth(_ source: ACharSequence, _ paint: APaint, _ textDir: ATextDirectionHeuristic) -> Int? {
        let units = Array(source.aw_plain.utf16)
        for c in units where c == 0x0A || c == 0x09 || AWBidi.couldAffectRtl(c) { return nil }
        if textDir.isRtl(units, 0, units.count) { return nil }
        let runs = buildStyleRuns(source, paint, units.count)
        if units.isEmpty { return 0 }
        let ns = attributed(units, 0, units.count, runs, false)
        return AWMath.ceil(AWShaping.width(CTLineCreateWithAttributedString(ns as CFAttributedString)))
    }

    // MARK: Drawing (Layout.draw)

    /// Layout.draw(canvas): the lines inside the canvas clip, placed as Layout.drawText places them and drawn run by
    /// run with ACanvas.drawTextRun using the layout's paint as it is now, updated by the character-style spans.
    func draw(_ canvas: ACanvas) {
        if lines.isEmpty { return }
        let clip = ARect()
        if !canvas.getClipBounds(clip) { return }
        let top = max(clip.top, 0)
        let bottom = min(getLineTop(lineCount), clip.bottom)
        if top >= bottom { return }
        let firstLine = getLineForVertical(top)
        let lastLine = getLineForVertical(bottom)
        drawText(canvas, firstLine, lastLine)
    }

    /// Layout.drawText.
    func drawText(_ canvas: ACanvas, _ firstLine: Int, _ lastLine: Int) {
        if firstLine > lastLine { return }
        for lineNum in firstLine...lastLine {
            guard lineNum < lines.count else { break }
            let l = lines[lineNum]
            guard l.paragraph >= 0 else { continue }
            let end = getLineVisibleEnd(lineNum)
            guard let shaped = shapedLine(lineNum, end) else { continue }
            let lbaseline = getLineBaseline(lineNum)
            let ltop = getLineTop(lineNum), lbottom = getLineBottom(lineNum)
            let dir = l.dir
            let left = 0, right = width
            var align = getParagraphAlignment(lineNum)   // Layout.drawText: the paragraph's AlignmentSpan
            if align == .ALIGN_LEFT {
                align = dir == ALayout.DIR_LEFT_TO_RIGHT ? .ALIGN_NORMAL : .ALIGN_OPPOSITE
            } else if align == .ALIGN_RIGHT {
                align = dir == ALayout.DIR_LEFT_TO_RIGHT ? .ALIGN_OPPOSITE : .ALIGN_NORMAL
            }
            var x: Int
            if align == .ALIGN_NORMAL {
                x = dir == ALayout.DIR_LEFT_TO_RIGHT ? left : right
            } else {
                var max = AWMath.javaInt(dir == ALayout.DIR_RIGHT_TO_LEFT ? -shaped.width : shaped.width)
                if align == .ALIGN_OPPOSITE {
                    x = dir == ALayout.DIR_LEFT_TO_RIGHT ? right - max : left - max
                } else {
                    max = max & ~1
                    x = (right + left - max) >> 1
                }
            }
            // x is the start edge of the line in its paragraph direction; Core Text lines run left to right.
            let lineLeft = dir == ALayout.DIR_RIGHT_TO_LEFT ? Float(x) - shaped.width : Float(x)
            drawShapedLine(canvas, shaped.line, shaped.display, lineLeft, Float(lbaseline), Float(ltop), Float(lbottom))
        }
    }

    /// Draws every glyph run of a shaped line with its span paint (TextLine.drawRun / handleText).
    private func drawShapedLine(_ canvas: ACanvas, _ line: CTLine, _ display: String, _ lineLeft: Float, _ baseline: Float,
                                _ top: Float, _ bottom: Float) {
        let d = KitGraphics.density
        for item in (CTLineGetGlyphRuns(line) as NSArray) {
            let run = item as! CTRun
            let count = CTRunGetGlyphCount(run)
            if count == 0 { continue }
            let range = CTRunGetStringRange(run)
            if range.length <= 0 { continue }
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
            var minX = positions[0].x
            for pt in positions where pt.x < minX { minX = pt.x }
            let runLeft = lineLeft + Float(minX * d)
            let isRtl = CTRunGetStatus(run).contains(.rightToLeft)
            let attrs = CTRunGetAttributes(run) as NSDictionary
            let styleIndex = (attrs[AWShaping.styleKey.rawValue] as? NSNumber)?.intValue ?? 0
            let wp = drawPaint(styleIndex)
            if wp.aw_backgroundColor != 0 {
                let runWidth = Float(CGFloat(CTRunGetTypographicBounds(run, CFRange(location: 0, length: 0), nil, nil, nil)) * d)
                let bg = APaint()
                bg.color = wp.aw_backgroundColor
                canvas.drawRect(runLeft, top, runLeft + runWidth, bottom, bg)
            }
            canvas.drawTextRun(display, range.location, range.location + range.length, range.location,
                               range.location + range.length, runLeft, baseline, isRtl, wp.aw_plain)
        }
    }

    /// The drawing paint of a style run: the layout's paint now, updated by the run's spans
    /// (CharacterStyle.updateDrawState in span order), left aligned.
    private func drawPaint(_ styleIndex: Int) -> AWDrawPaint {
        let wp = APaint(paint)
        wp.textAlign = .LEFT
        var background = 0
        if let run = styleRuns.getOrNull(styleIndex) {
            for sp in run.spans {
                sp.aw_updateDrawState(wp)
                if let b = sp as? ABackgroundColorSpan { background = b.backgroundColor }
            }
        }
        return AWDrawPaint(aw_plain: wp, aw_backgroundColor: background)
    }
}

/// A drawing paint plus the TextPaint.bgColor of BackgroundColorSpan.
struct AWDrawPaint {
    let aw_plain: APaint
    let aw_backgroundColor: Int
}
