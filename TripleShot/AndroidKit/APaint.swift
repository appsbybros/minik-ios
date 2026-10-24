import CoreGraphics
import CoreText
import Foundation
import UIKit

// android.graphics.Paint, Typeface, Shader/LinearGradient/RadialGradient, DashPathEffect, Paint.FontMetrics
// (VIEW-API "Graphics"). Sizes are Android pixels. Text is shaped with Core Text at `textSize / density`
// points (the point size UIKit uses for that text, so the system font picks the same optical size) and
// every measurement is converted back to pixels.

// MARK: - Typeface

/// android.graphics.Typeface over the iOS system font. Android 12's fonts.xml families and aliases map to the
/// closest system design: sans-serif (Roboto, weights 100...900) -> San Francisco, sans-serif-condensed -> SF
/// condensed width, serif (Noto Serif) -> New York, monospace (Droid Sans Mono) -> SF Mono, serif-monospace
/// (Cutive Mono) -> Courier New, casual (Coming Soon) -> SF Rounded, cursive (Dancing Script) -> Snell Roundhand.
/// Weights follow Android (an alias like `sans-serif-medium` is its family at weight 500, BOLD adds 300 to the
/// family weight like Typeface.create). Family names are matched exactly (Typeface.sSystemFontMap is a
/// case-sensitive map); an unknown name gives DEFAULT. Instances are cached like Android, so identity
/// comparisons (`===`, `==`) behave as on Android.
final class ATypeface: Hashable, CustomStringConvertible {
    static let NORMAL = 0
    static let BOLD = 1
    static let ITALIC = 2
    static let BOLD_ITALIC = 3

    /// The system design a family maps to.
    enum KGDesign { case sansSerif, condensed, serif, monospace, serifMonospace, rounded, cursive }

    /// Family name of the system font this typeface comes from (`getSystemFontFamilyName()`).
    let familyName: String
    let design: KGDesign
    /// The family's own weight (Typeface fBaseWeight): 400 for sans-serif, 500 for sans-serif-medium, ...
    let baseWeight: Int
    /// The weight used for drawing (`getWeight()`).
    let weight: Int
    let isItalic: Bool
    /// `getStyle()`: NORMAL, BOLD, ITALIC or BOLD_ITALIC.
    let style: Int

    var isBold: Bool { return (style & ATypeface.BOLD) != 0 }

    func getStyle() -> Int { return style }
    func getWeight() -> Int { return weight }

    private init(_ familyName: String, _ design: KGDesign, _ baseWeight: Int, _ weight: Int, _ italic: Bool, _ style: Int) {
        self.familyName = familyName
        self.design = design
        self.baseWeight = baseWeight
        self.weight = weight
        self.isItalic = italic
        self.style = style
    }

    static func == (a: ATypeface, b: ATypeface) -> Bool { return a === b }
    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }

    var description: String { return "Typeface(\(familyName), weight \(weight), style \(style))" }

    // MARK: System fonts (fonts.xml families and aliases)

    /// Typeface.sSystemFontMap of Android 12 (data/fonts/fonts.xml): families, then aliases (an alias with a
    /// weight is its family re-based at that weight, Typeface.createWeightAlias).
    private static let systemFontMap: [String: ATypeface] = {
        var map: [String: ATypeface] = [:]
        func family(_ name: String, _ design: KGDesign) {
            map[name] = ATypeface(name, design, 400, 400, false, NORMAL)
        }
        func alias(_ name: String, _ to: String, _ weight: Int? = nil) {
            guard let base = map[to] else { return }
            if let w = weight {
                map[name] = ATypeface(base.familyName, base.design, w, w, false, NORMAL)
            } else {
                map[name] = base
            }
        }
        family("sans-serif", .sansSerif)
        alias("sans-serif-thin", "sans-serif", 100)
        alias("sans-serif-light", "sans-serif", 300)
        alias("sans-serif-medium", "sans-serif", 500)
        alias("sans-serif-black", "sans-serif", 900)
        alias("arial", "sans-serif")
        alias("helvetica", "sans-serif")
        alias("tahoma", "sans-serif")
        alias("verdana", "sans-serif")
        family("sans-serif-condensed", .condensed)
        alias("sans-serif-condensed-light", "sans-serif-condensed", 300)
        alias("sans-serif-condensed-medium", "sans-serif-condensed", 500)
        family("serif", .serif)
        alias("serif-bold", "serif", 700)
        alias("times", "serif")
        alias("times new roman", "serif")
        alias("palatino", "serif")
        alias("georgia", "serif")
        alias("baskerville", "serif")
        alias("goudy", "serif")
        alias("fantasy", "serif")
        alias("ITC Stone Serif", "serif")
        family("monospace", .monospace)
        alias("sans-serif-monospace", "monospace")
        alias("monaco", "monospace")
        family("serif-monospace", .serifMonospace)
        alias("courier", "serif-monospace")
        alias("courier new", "serif-monospace")
        family("casual", .rounded)
        family("cursive", .cursive)
        family("sans-serif-smallcaps", .sansSerif)
        family("source-sans-pro", .sansSerif)
        alias("source-sans-pro-semi-bold", "source-sans-pro", 600)
        return map
    }()

    static let DEFAULT: ATypeface = systemFontMap["sans-serif"]!
    static let DEFAULT_BOLD: ATypeface = create(nil as ATypeface?, BOLD)
    /// Android: the same object as DEFAULT (both are the "sans-serif" family).
    static let SANS_SERIF: ATypeface = create("sans-serif", NORMAL)
    static let SERIF: ATypeface = create("serif", NORMAL)
    static let MONOSPACE: ATypeface = create("monospace", NORMAL)

    private static let defaults: [ATypeface] = [DEFAULT, DEFAULT_BOLD, create(nil as ATypeface?, ITALIC),
                                                create(nil as ATypeface?, BOLD_ITALIC)]

    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var styledCache: [ObjectIdentifier: [Int: ATypeface]] = [:]
    nonisolated(unsafe) private static var weightCache: [ObjectIdentifier: [Int: ATypeface]] = [:]

    /// `Typeface.create(family, style)`: the family with BOLD (+300 weight) and/or ITALIC applied to the
    /// family's own weight; the same object for the same request.
    static func create(_ family: ATypeface?, _ style: Int) -> ATypeface {
        var style = style
        if (style & ~BOLD_ITALIC) != 0 {
            style = NORMAL
        }
        let base = family ?? DEFAULT
        // Return early if we're asked for the same face/style
        if base.style == style {
            return base
        }
        cacheLock.lock()
        defer { cacheLock.unlock() }
        let key = ObjectIdentifier(base)
        if let cached = styledCache[key]?[style] {
            return cached
        }
        // Typeface::createRelative: computeRelativeStyle(fBaseWeight, style), weight clamped to 1...1000.
        let weight = max(1, min(1000, base.baseWeight + ((style & BOLD) != 0 ? 300 : 0)))
        let tf = ATypeface(base.familyName, base.design, base.baseWeight, weight, (style & ITALIC) != 0, style)
        styledCache[key, default: [:]][style] = tf
        return tf
    }

    /// `Typeface.create(familyName, style)`: a system family (unknown names fall back to DEFAULT).
    static func create(_ familyName: String?, _ style: Int) -> ATypeface {
        let base = familyName.flatMap { systemFontMap[$0] } ?? DEFAULT
        return create(base, style)
    }

    /// `Typeface.create(family, weight, italic)` (API 28): an exact weight 1..1000 (the base weight is kept, so
    /// a later create(tf, BOLD) is relative to the family's weight like Android).
    static func create(_ family: ATypeface?, _ weight: Int, _ italic: Bool) -> ATypeface {
        precondition(weight >= 0 && weight <= 1000, "java.lang.IllegalArgumentException: weight is out of range of [0, 1000]")
        let base = family ?? DEFAULT
        cacheLock.lock()
        defer { cacheLock.unlock() }
        let key = ObjectIdentifier(base)
        let inner = (weight << 1) | (italic ? 1 : 0)
        if let cached = weightCache[key]?[inner] {
            return cached
        }
        let style = weight >= 600 ? (italic ? BOLD_ITALIC : BOLD) : (italic ? ITALIC : NORMAL)
        let tf = ATypeface(base.familyName, base.design, base.baseWeight, max(1, weight), italic, style)
        weightCache[key, default: [:]][inner] = tf
        return tf
    }

    /// `Typeface.defaultFromStyle(style)`.
    static func defaultFromStyle(_ style: Int) -> ATypeface {
        return defaults[style]
    }

    // MARK: Fonts

    private let fontLock = NSLock()
    private var fontCache: [CGFloat: UIFont] = [:]

    /// The UIKit font for this typeface at a POINT size (pt = px / density).
    func uiFont(_ pointSize: CGFloat) -> UIFont {
        fontLock.lock()
        defer { fontLock.unlock() }
        if let cached = fontCache[pointSize] {
            return cached
        }
        let uiWeight = ATypeface.uiWeight(weight)
        var font: UIFont
        switch design {
        case .sansSerif:
            font = UIFont.systemFont(ofSize: pointSize, weight: uiWeight)
        case .condensed:
            font = UIFont.systemFont(ofSize: pointSize, weight: uiWeight, width: .condensed)
        case .monospace:
            font = UIFont.monospacedSystemFont(ofSize: pointSize, weight: uiWeight)
        case .serifMonospace:
            font = UIFont(name: weight >= 600 ? "CourierNewPS-BoldMT" : "CourierNewPSMT", size: pointSize)
                ?? UIFont.monospacedSystemFont(ofSize: pointSize, weight: uiWeight)
        case .serif, .rounded:
            let system = UIFont.systemFont(ofSize: pointSize, weight: uiWeight)
            let systemDesign: UIFontDescriptor.SystemDesign = design == .serif ? .serif : .rounded
            if let d = system.fontDescriptor.withDesign(systemDesign) {
                font = UIFont(descriptor: d, size: pointSize)
            } else {
                font = system
            }
        case .cursive:
            font = UIFont(name: "SnellRoundhand", size: pointSize) ?? UIFont.systemFont(ofSize: pointSize, weight: uiWeight)
        }
        if isItalic {
            let traits = font.fontDescriptor.symbolicTraits.union(.traitItalic)
            if let d = font.fontDescriptor.withSymbolicTraits(traits) {
                font = UIFont(descriptor: d, size: pointSize)
            }
        }
        fontCache[pointSize] = font
        return font
    }

    /// Android weight 100...900 -> the SF weight of the same rank.
    static func uiWeight(_ weight: Int) -> UIFont.Weight {
        switch weight {
        case ..<150: return .ultraLight
        case ..<250: return .thin
        case ..<350: return .light
        case ..<450: return .regular
        case ..<550: return .medium
        case ..<650: return .semibold
        case ..<750: return .bold
        case ..<850: return .heavy
        default: return .black
        }
    }

    private let ctFontLock = NSLock()
    private var ctFontCache: [KGFontKey: CTFont] = [:]

    private struct KGFontKey: Hashable {
        let pointSize: CGFloat
        let scaleX: Float
        let skewX: Float
    }

    /// The Core Text font at `pointSize` with Paint.textScaleX / textSkewX applied as the font matrix
    /// (Skia: glyphs scaled by scaleX, then skewed by skewX, in y-down space).
    func kgCTFont(_ pointSize: CGFloat, _ scaleX: Float, _ skewX: Float) -> CTFont {
        let base = uiFont(pointSize) as CTFont
        if scaleX == 1 && skewX == 0 {
            return base
        }
        let key = KGFontKey(pointSize: pointSize, scaleX: scaleX, skewX: skewX)
        ctFontLock.lock()
        defer { ctFontLock.unlock() }
        if let cached = ctFontCache[key] {
            return cached
        }
        var matrix = CGAffineTransform(a: CGFloat(scaleX), b: 0, c: CGFloat(-skewX), d: 1, tx: 0, ty: 0)
        let font = CTFontCreateCopyWithAttributes(base, pointSize, &matrix, nil)
        ctFontCache[key] = font
        return font
    }
}

// MARK: - Shaders

/// android.graphics.Shader.TileMode.
enum ATileMode { case CLAMP, REPEAT, MIRROR }

/// android.graphics.Shader.
class AShader {
    /// The local matrix (nil = identity).
    private(set) var localMatrix: AMatrix?

    init() {}

    /// `setLocalMatrix(matrix)`.
    func setLocalMatrix(_ matrix: AMatrix?) {
        if let m = matrix, !m.isIdentity() {
            localMatrix = AMatrix(m)
        } else {
            localMatrix = nil
        }
    }

    /// `getLocalMatrix(localM)`: true when the local matrix is not the identity.
    func getLocalMatrix(_ localM: AMatrix) -> Bool {
        if let m = localMatrix {
            localM.set(m)
            return true
        }
        localM.reset()
        return false
    }
}

/// android.graphics.LinearGradient (colours interpolated unpremultiplied in sRGB, like Skia's default).
final class ALinearGradient: AShader {
    let x0: Float, y0: Float, x1: Float, y1: Float
    let colors: [Int]
    let positions: [Float]?
    let tileMode: ATileMode

    init(_ x0: Float, _ y0: Float, _ x1: Float, _ y1: Float, _ colors: [Int], _ positions: [Float]?, _ tile: ATileMode) {
        precondition(colors.count >= 2, "java.lang.IllegalArgumentException: needs >= 2 number of colors")
        precondition(positions == nil || positions!.count == colors.count,
                     "java.lang.IllegalArgumentException: color and position arrays must be of equal length")
        self.x0 = x0; self.y0 = y0; self.x1 = x1; self.y1 = y1
        self.colors = colors
        self.positions = positions
        self.tileMode = tile
        super.init()
    }

    convenience init(_ x0: Float, _ y0: Float, _ x1: Float, _ y1: Float, _ color0: Int, _ color1: Int, _ tile: ATileMode) {
        self.init(x0, y0, x1, y1, [color0, color1], nil, tile)
    }
}

/// android.graphics.RadialGradient.
final class ARadialGradient: AShader {
    let centerX: Float, centerY: Float, radius: Float
    let colors: [Int]
    let positions: [Float]?
    let tileMode: ATileMode

    init(_ centerX: Float, _ centerY: Float, _ radius: Float, _ colors: [Int], _ stops: [Float]?, _ tileMode: ATileMode) {
        precondition(radius > 0, "java.lang.IllegalArgumentException: radius must be > 0")
        precondition(colors.count >= 2, "java.lang.IllegalArgumentException: needs >= 2 number of colors")
        precondition(stops == nil || stops!.count == colors.count,
                     "java.lang.IllegalArgumentException: color and position arrays must be of equal length")
        self.centerX = centerX; self.centerY = centerY; self.radius = radius
        self.colors = colors
        self.positions = stops
        self.tileMode = tileMode
        super.init()
    }

    convenience init(_ centerX: Float, _ centerY: Float, _ radius: Float, _ centerColor: Int, _ edgeColor: Int, _ tileMode: ATileMode) {
        self.init(centerX, centerY, radius, [centerColor, edgeColor], nil, tileMode)
    }
}

extension AShader {
    /// Skia SkGradientShaderBase stops: a dummy first/last stop when positions do not start at 0 / end at 1,
    /// every position pinned to [previous, 1]; nil positions = evenly spaced.
    static func kgStops(_ colors: [Int], _ positions: [Float]?) -> (colors: [Int], stops: [Float]) {
        guard let pos = positions else {
            let n = colors.count
            return (colors, (0..<n).map { Float($0) / Float(n - 1) })
        }
        let count = colors.count
        let dummyFirst = pos[0] != 0
        let dummyLast = pos[count - 1] != 1
        var outColors: [Int] = []
        if dummyFirst { outColors.append(colors[0]) }
        outColors.append(contentsOf: colors)
        if dummyLast { outColors.append(colors[count - 1]) }
        var outPos: [Float] = [0]
        var prev: Float = 0
        let startIndex = dummyFirst ? 0 : 1
        let end = count + (dummyLast ? 1 : 0)
        var i = startIndex
        while i < end {
            // Pin the last value to 1.0, and make sure pos is monotonic.
            let curr: Float = (i == count) ? 1 : max(prev, min(pos[i], 1))
            outPos.append(curr)
            prev = curr
            i += 1
        }
        return (outColors, outPos)
    }
}

// MARK: - Path effect, font metrics

/// android.graphics.DashPathEffect: [on, off, on, off, ...] intervals and a phase, in px.
final class ADashPathEffect {
    let intervals: [Float]
    let phase: Float

    init(_ intervals: [Float], _ phase: Float) {
        precondition(intervals.count >= 2, "java.lang.ArrayIndexOutOfBoundsException")
        self.intervals = intervals
        self.phase = phase
    }

    /// Skia SkDashPath::ValidDashPath: an even count of non-negative intervals with a positive sum
    /// (an invalid effect draws undashed, like Android's null path effect).
    var isValid: Bool {
        if intervals.count < 2 || (intervals.count & 1) != 0 { return false }
        var length: Float = 0
        for v in intervals {
            if v < 0 { return false }
            length += v
        }
        return length > 0 && length.isFinite && phase.isFinite
    }

    /// The phase Skia uses (SkDashPath::CalcDashParameters): in [0, total length), a negative phase flipped.
    var normalizedPhase: Float {
        let len = intervals.reduce(Float(0), +)
        var p = phase
        if p < 0 {
            p = -p
            if p > len { p = p.truncatingRemainder(dividingBy: len) }
            p = len - p
            // Due to finite precision, it's possible that phase == len, even after the subtract.
            if p == len { p = 0 }
        } else if p >= len {
            p = p.truncatingRemainder(dividingBy: len)
        }
        return p
    }
}

/// android.graphics.Paint.FontMetrics (px; ascent/top negative = above the baseline).
final class AFontMetrics {
    var top: Float = 0
    var ascent: Float = 0
    var descent: Float = 0
    var bottom: Float = 0
    var leading: Float = 0
    init() {}
}

/// android.graphics.Paint.FontMetricsInt.
final class AFontMetricsInt {
    var top: Int = 0
    var ascent: Int = 0
    var descent: Int = 0
    var bottom: Int = 0
    var leading: Int = 0
    init() {}
}

// MARK: - Paint

/// android.graphics.Paint. Colours are Android ARGB Ints; sizes are px.
final class APaint {
    static let ANTI_ALIAS_FLAG = 0x01
    static let FILTER_BITMAP_FLAG = 0x02
    static let DITHER_FLAG = 0x04
    static let UNDERLINE_TEXT_FLAG = 0x08
    static let STRIKE_THRU_TEXT_FLAG = 0x10
    static let FAKE_BOLD_TEXT_FLAG = 0x20
    static let LINEAR_TEXT_FLAG = 0x40
    static let SUBPIXEL_TEXT_FLAG = 0x80
    static let DEV_KERN_TEXT_FLAG = 0x100
    static let LCD_RENDER_TEXT_FLAG = 0x200
    static let EMBEDDED_BITMAP_TEXT_FLAG = 0x400
    static let AUTO_HINTING_TEXT_FLAG = 0x800
    static let VERTICAL_TEXT_FLAG = 0x1000
    /// Flags Android (API 29+) always sets on a new or reset paint, even with flags 0.
    static let HIDDEN_DEFAULT_PAINT_FLAGS = DEV_KERN_TEXT_FLAG | EMBEDDED_BITMAP_TEXT_FLAG | FILTER_BITMAP_FLAG

    enum Style { case FILL, STROKE, FILL_AND_STROKE }
    enum Cap { case BUTT, ROUND, SQUARE }
    enum Join { case MITER, ROUND, BEVEL }
    enum Align { case LEFT, CENTER, RIGHT }

    var flags: Int
    /// `getColor()` / `setColor(color)`: the Java-side colour (Paint.mColor) as an ARGB Int (default opaque black).
    /// Setting it also sets the native colour that is drawn.
    var color: Int {
        get { return javaColor }
        set {
            javaColor = newValue
            kgNativeAlpha = AColor.alpha(newValue)
        }
    }
    private var javaColor: Int = AColor.BLACK
    /// The alpha the native SkPaint draws with. It equals `alpha` for every value set in 0...255; Android 12's
    /// `setAlpha` pins other values natively (U8CPU: a negative Int becomes a huge unsigned value, so it draws
    /// opaque) while the Java colour keeps `(int) (a / 255f * 255f + 0.5f) << 24`.
    private(set) var kgNativeAlpha: Int = 255
    /// A SRC_IN colour filter (BlendModeColorFilter(color, SRC_IN), what Drawable tints install): solid colours
    /// become this colour with alpha = filter alpha x paint alpha; shaders and bitmaps keep only their coverage.
    var kgColorFilter: Int?
    var style: Style = .FILL
    /// Stroke width in px; 0 = hairline (one device pixel). Negative values are ignored like Skia.
    var strokeWidth: Float = 0 {
        didSet { if !(strokeWidth >= 0) { strokeWidth = oldValue } }
    }
    var strokeCap: Cap = .BUTT
    var strokeJoin: Join = .MITER
    var strokeMiter: Float = 4 {
        didSet { if !(strokeMiter >= 0) { strokeMiter = oldValue } }
    }
    /// Text size in px (default 12). Negative values are ignored.
    var textSize: Float = 12 {
        didSet { if !(textSize >= 0) { textSize = oldValue } }
    }
    var textScaleX: Float = 1
    var textSkewX: Float = 0
    var typeface: ATypeface?
    var textAlign: Align = .LEFT
    /// Letter spacing in ems.
    var letterSpacing: Float = 0
    var wordSpacing: Float = 0
    var shader: AShader?
    var pathEffect: ADashPathEffect?
    var isElegantTextHeight = false
    private(set) var shadowLayerRadius: Float = 0
    private(set) var shadowLayerDx: Float = 0
    private(set) var shadowLayerDy: Float = 0
    private(set) var shadowLayerColor: Int = 0

    /// `new Paint()`: anti-aliased (Android: this(ANTI_ALIAS_FLAG)), with the hidden default flags.
    init() {
        flags = APaint.ANTI_ALIAS_FLAG | APaint.HIDDEN_DEFAULT_PAINT_FLAGS
    }

    /// `new Paint(flags)`.
    init(_ flags: Int) {
        self.flags = flags | APaint.HIDDEN_DEFAULT_PAINT_FLAGS
    }

    /// `new Paint(paint)`.
    init(_ other: APaint) {
        flags = other.flags
        set(other)
    }

    /// `set(src)`: copies every attribute.
    func set(_ src: APaint) {
        if src === self { return }
        flags = src.flags
        javaColor = src.javaColor
        kgNativeAlpha = src.kgNativeAlpha
        kgColorFilter = src.kgColorFilter
        style = src.style
        strokeWidth = src.strokeWidth
        strokeCap = src.strokeCap
        strokeJoin = src.strokeJoin
        strokeMiter = src.strokeMiter
        textSize = src.textSize
        textScaleX = src.textScaleX
        textSkewX = src.textSkewX
        typeface = src.typeface
        textAlign = src.textAlign
        letterSpacing = src.letterSpacing
        wordSpacing = src.wordSpacing
        shader = src.shader
        pathEffect = src.pathEffect
        isElegantTextHeight = src.isElegantTextHeight
        shadowLayerRadius = src.shadowLayerRadius
        shadowLayerDx = src.shadowLayerDx
        shadowLayerDy = src.shadowLayerDy
        shadowLayerColor = src.shadowLayerColor
    }

    /// `reset()`.
    func reset() {
        set(APaint())
    }

    /// `getAlpha()` / `setAlpha(a)` (Android 12): the getter is `Math.round(Color.alpha(mColor) * 255f)`, the alpha
    /// byte of `color`; the setter keeps the RGB and repacks `mColor` with `a * (1f / 255)` like Color.pack, and
    /// sets the native alpha (`kgNativeAlpha`), pinned to 0...255 (negative values draw opaque, as on Android).
    var alpha: Int {
        get { return AColor.alpha(javaColor) }
        set {
            let f = Float(newValue) * (Float(1) / Float(255))
            let packed = KitGraphics.javaInt(f * Float(255) + Float(0.5))
            javaColor = Int((Int32(truncatingIfNeeded: javaColor) & 0x00FF_FFFF) | (Int32(truncatingIfNeeded: packed) &<< 24))
            kgNativeAlpha = (newValue >= 0 && newValue <= 255) ? newValue : 255
        }
    }

    /// The ARGB colour the native paint draws with (`color` with the native alpha).
    var kgDrawColor: Int {
        return Int((Int32(truncatingIfNeeded: javaColor) & 0x00FF_FFFF) | (Int32(kgNativeAlpha) &<< 24))
    }

    func setARGB(_ a: Int, _ r: Int, _ g: Int, _ b: Int) {
        color = AColor.argb(a, r, g, b)
    }

    // Java-style accessors (ports of Java code call these).
    func setColor(_ color: Int) { self.color = color }
    func getColor() -> Int { return color }
    func setAlpha(_ a: Int) { alpha = a }
    func getAlpha() -> Int { return alpha }
    func setStyle(_ style: Style) { self.style = style }
    func getStyle() -> Style { return style }
    func setStrokeWidth(_ width: Float) { strokeWidth = width }
    func getStrokeWidth() -> Float { return strokeWidth }
    func setStrokeCap(_ cap: Cap) { strokeCap = cap }
    func setStrokeJoin(_ join: Join) { strokeJoin = join }
    func setStrokeMiter(_ miter: Float) { strokeMiter = miter }
    func setTextSize(_ size: Float) { textSize = size }
    func getTextSize() -> Float { return textSize }
    func setTextAlign(_ align: Align) { textAlign = align }
    func setAntiAlias(_ aa: Bool) { isAntiAlias = aa }
    func setFilterBitmap(_ filter: Bool) { isFilterBitmap = filter }
    func setDither(_ dither: Bool) { isDither = dither }
    func setFakeBoldText(_ fakeBold: Bool) { isFakeBoldText = fakeBold }
    func setUnderlineText(_ underline: Bool) { isUnderlineText = underline }
    func setLetterSpacing(_ spacing: Float) { letterSpacing = spacing }
    func setFlags(_ flags: Int) { self.flags = flags }
    func getFlags() -> Int { return flags }
    @discardableResult func setShader(_ shader: AShader?) -> AShader? { self.shader = shader; return shader }
    func getShader() -> AShader? { return shader }
    @discardableResult func setPathEffect(_ effect: ADashPathEffect?) -> ADashPathEffect? { pathEffect = effect; return effect }
    @discardableResult func setTypeface(_ typeface: ATypeface?) -> ATypeface? { self.typeface = typeface; return typeface }
    func getTypeface() -> ATypeface? { return typeface }

    private func flag(_ f: Int) -> Bool { return (flags & f) != 0 }
    private func setFlag(_ f: Int, _ on: Bool) { flags = on ? (flags | f) : (flags & ~f) }

    var isAntiAlias: Bool { get { return flag(APaint.ANTI_ALIAS_FLAG) } set { setFlag(APaint.ANTI_ALIAS_FLAG, newValue) } }
    var isFilterBitmap: Bool { get { return flag(APaint.FILTER_BITMAP_FLAG) } set { setFlag(APaint.FILTER_BITMAP_FLAG, newValue) } }
    var isDither: Bool { get { return flag(APaint.DITHER_FLAG) } set { setFlag(APaint.DITHER_FLAG, newValue) } }
    var isUnderlineText: Bool { get { return flag(APaint.UNDERLINE_TEXT_FLAG) } set { setFlag(APaint.UNDERLINE_TEXT_FLAG, newValue) } }
    var isStrikeThruText: Bool { get { return flag(APaint.STRIKE_THRU_TEXT_FLAG) } set { setFlag(APaint.STRIKE_THRU_TEXT_FLAG, newValue) } }
    var isFakeBoldText: Bool { get { return flag(APaint.FAKE_BOLD_TEXT_FLAG) } set { setFlag(APaint.FAKE_BOLD_TEXT_FLAG, newValue) } }
    var isLinearText: Bool { get { return flag(APaint.LINEAR_TEXT_FLAG) } set { setFlag(APaint.LINEAR_TEXT_FLAG, newValue) } }
    var isSubpixelText: Bool { get { return flag(APaint.SUBPIXEL_TEXT_FLAG) } set { setFlag(APaint.SUBPIXEL_TEXT_FLAG, newValue) } }

    /// `setShadowLayer(radius, dx, dy, shadowColor)`: a blurred copy drawn below every draw with this paint
    /// (hwui BlurDrawLooper). A radius <= 0 removes the shadow (Android).
    func setShadowLayer(_ radius: Float, _ dx: Float, _ dy: Float, _ shadowColor: Int) {
        shadowLayerRadius = radius
        shadowLayerDx = dx
        shadowLayerDy = dy
        shadowLayerColor = shadowColor
    }

    func clearShadowLayer() {
        setShadowLayer(0, 0, 0, 0)
    }

    func hasShadowLayer() -> Bool {
        return shadowLayerRadius > 0
    }

    // MARK: Text measurement

    /// `measureText(text)`: the advance width in px of Minikin's layout (at `kgLayoutSize`), rounded up like
    /// Android (`Math.ceil`).
    func measureText(_ text: String) -> Float {
        if text.isEmpty { return 0 }
        return Float(Double(kgAdvance(text)).rounded(.up))
    }

    /// `measureText(text, start, end)` (UTF-16 indices).
    func measureText(_ text: String, _ start: Int, _ end: Int) -> Float {
        return measureText(KitGraphics.utf16Substring(text, start, end))
    }

    /// `getTextBounds(text, start, end, bounds)`: the ink bounds of Minikin's layout (glyphs at `kgLayoutSize`)
    /// relative to (x, baseline), rounded out. Fake bold grows the glyphs to the right and upwards (FreeType
    /// emboldening at the layout size).
    func getTextBounds(_ text: String, _ start: Int, _ end: Int, _ bounds: ARect) {
        let sub = KitGraphics.utf16Substring(text, start, end)
        if sub.isEmpty || !(kgLayoutSize > 0) {
            bounds.set(0, 0, 0, 0)
            return
        }
        let line = kgLine(sub, nil, nil)
        let r = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        if r.isNull || r.isInfinite || (r.width == 0 && r.height == 0) {
            bounds.set(0, 0, 0, 0)
            return
        }
        let d = KitGraphics.density
        let half = kgLetterSpacing().halfLeft
        let left = Float(r.minX * d + half)
        var right = Float(r.maxX * d + half)
        var top = Float(-r.maxY * d)
        let bottom = Float(-r.minY * d)
        if isFakeBoldText {
            let growth = KitGraphics.fakeBoldGrowth(kgLayoutSize)
            right += growth
            top -= growth
        }
        bounds.set(KitGraphics.floorInt(left), KitGraphics.floorInt(top), KitGraphics.ceilInt(right), KitGraphics.ceilInt(bottom))
    }

    func getTextBounds(_ text: String, _ start: Int, _ end: Int, _ bounds: ARectF) {
        let r = ARect()
        getTextBounds(text, start, end, r)
        bounds.set(r)
    }

    /// `getFontMetrics()`: a new FontMetrics.
    var fontMetrics: AFontMetrics { return getFontMetrics() }

    func getFontMetrics() -> AFontMetrics {
        let fm = AFontMetrics()
        _ = getFontMetrics(fm)
        return fm
    }

    /// `getFontMetrics(metrics)`: fills `metrics` (when given) and returns the recommended line spacing
    /// `descent - ascent + leading`.
    @discardableResult
    func getFontMetrics(_ metrics: AFontMetrics?) -> Float {
        let v = kgFontMetricValues()
        if let m = metrics {
            m.top = v.top
            m.ascent = v.ascent
            m.descent = v.descent
            m.bottom = v.bottom
            m.leading = v.leading
        }
        return v.descent - v.ascent + v.leading
    }

    var fontMetricsInt: AFontMetricsInt { return getFontMetricsInt() }

    func getFontMetricsInt() -> AFontMetricsInt {
        let fmi = AFontMetricsInt()
        _ = getFontMetricsInt(fmi)
        return fmi
    }

    /// `getFontMetricsInt(fmi)`: top floored, bottom ceiled, ascent/descent/leading rounded (Skia).
    @discardableResult
    func getFontMetricsInt(_ fmi: AFontMetricsInt?) -> Int {
        let v = kgFontMetricValues()
        let ascent = KitGraphics.javaInt((v.ascent + 0.5).rounded(.down))
        let descent = KitGraphics.javaInt((v.descent + 0.5).rounded(.down))
        let leading = KitGraphics.javaInt((v.leading + 0.5).rounded(.down))
        if let m = fmi {
            m.top = KitGraphics.javaInt(v.top.rounded(.down))
            m.ascent = ascent
            m.descent = descent
            m.bottom = KitGraphics.javaInt(v.bottom.rounded(.up))
            m.leading = leading
        }
        return descent - ascent + leading
    }

    /// `getFontSpacing()`.
    var fontSpacing: Float { return getFontMetrics(nil) }

    /// `ascent()`: negative (above the baseline).
    func ascent() -> Float { return kgFontMetricValues().ascent }

    /// `descent()`: positive.
    func descent() -> Float { return kgFontMetricValues().descent }

    /// `getUnderlinePosition()` / `getUnderlineThickness()` (API 29), px; the position is below the baseline.
    func getUnderlinePosition() -> Float { return kgUnderlineMetrics().position }
    func getUnderlineThickness() -> Float { return kgUnderlineMetrics().thickness }

    // MARK: Text engine (shared with ACanvas)

    /// The text size Minikin lays text out at (MinikinUtils::prepareMinikinPaint): `(int) textSize` unless
    /// LINEAR_TEXT_FLAG is set. Advances, glyph positions, ink bounds and letter spacing use it; the glyphs
    /// themselves are drawn at the full `textSize` (hwui draws with the paint's own SkFont), and font metrics
    /// are the full size's (Paint.getFontMetrics reads the paint's SkFont).
    var kgLayoutSize: Float {
        return isLinearText ? textSize : textSize.rounded(.towardZero)
    }

    /// The point size Core Text shapes this paint's text at (`kgLayoutSize / density`).
    var kgLayoutPointSize: CGFloat {
        return CGFloat(kgLayoutSize) / KitGraphics.density
    }

    /// The point size of the drawn glyphs and of the font metrics (`textSize / density`).
    var kgPointSize: CGFloat {
        return CGFloat(textSize) / KitGraphics.density
    }

    /// The layout font (at `kgLayoutPointSize`, with textScaleX / textSkewX as the font matrix).
    func kgFont() -> CTFont {
        return (typeface ?? ATypeface.DEFAULT).kgCTFont(kgLayoutPointSize, textScaleX, textSkewX)
    }

    /// The UIKit font of this paint (point size = textSize / density, no scale/skew), for UIKit-drawn text.
    func uiFont() -> UIFont {
        return (typeface ?? ATypeface.DEFAULT).uiFont(kgPointSize)
    }

    /// Minikin (Android 12 LayoutPiece) letter spacing: `letterSpacing * size * scaleX` px per cluster, with
    /// Minikin's size (`kgLayoutSize`), not rounded; half of it before the first cluster (`halfLeft`) and half
    /// after the last.
    func kgLetterSpacing() -> (perCluster: CGFloat, halfLeft: CGFloat) {
        if letterSpacing == 0 { return (0, 0) }
        let letterSpace = Double(letterSpacing) * Double(kgLayoutSize) * Double(textScaleX)
        return (CGFloat(letterSpace), CGFloat(letterSpace * 0.5))
    }

    /// Android fake bold growth of the glyphs in px at this paint's size on an unscaled canvas
    /// (KitGraphics.fakeBoldGrowth: FreeType emboldening with SK_OUTLINE_EMBOLDEN_DIVISOR 34).
    func kgFakeBoldExtra() -> Float {
        return KitGraphics.fakeBoldGrowth(textSize)
    }

    /// Minikin isScriptOkForLetterspacing: no letter spacing for connected scripts (Arabic, NKo, Psalter
    /// Pahlavi, Mandaic, Mongolian, Phags-pa, Devanagari, Bengali, Gurmukhi, Modi, Sharada, Syloti Nagri,
    /// Tirhuta, Ogham).
    static func kgScriptOkForLetterSpacing(_ ch: Character) -> Bool {
        guard let v = ch.unicodeScalars.first?.value else { return true }
        switch v {
        case 0x0600...0x06FF, 0x0750...0x077F, 0x0870...0x08FF, 0xFB50...0xFDFF, 0xFE70...0xFEFF, 0x10E60...0x10E7F,
             0x1EE00...0x1EEFF:                     // Arabic
            return false
        case 0x07C0...0x07FF: return false          // NKo
        case 0x10B80...0x10BAF: return false        // Psalter Pahlavi
        case 0x0840...0x085F: return false          // Mandaic
        case 0x1800...0x18AF, 0x11660...0x1167F: return false   // Mongolian
        case 0xA840...0xA87F: return false          // Phags-pa
        case 0x0900...0x097F, 0xA8E0...0xA8FF: return false     // Devanagari
        case 0x0980...0x09FF: return false          // Bengali
        case 0x0A00...0x0A7F: return false          // Gurmukhi
        case 0x11600...0x1165F: return false        // Modi
        case 0x11180...0x111DF: return false        // Sharada
        case 0xA800...0xA82F: return false          // Syloti Nagri
        case 0x11480...0x114DF: return false        // Tirhuta
        case 0x1680...0x169F: return false          // Ogham
        default: return true
        }
    }

    /// A Core Text line for `text` with this paint's font and letter spacing (applied after the last UTF-16 unit
    /// of every grapheme cluster; optional ligatures off when |letterSpacing| > 0.03 like Minikin). `color` sets
    /// the glyph colour (nil = none, for measuring or path drawing); `forcedRtl` forces one direction
    /// (drawTextRun).
    func kgLine(_ text: String, _ color: CGColor?, _ forcedRtl: Bool?) -> CTLine {
        var attrs: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): kgFont()]
        if let c = color {
            attrs[NSAttributedString.Key(kCTForegroundColorAttributeName as String)] = c
        }
        if let rtl = forcedRtl {
            // kCTWritingDirectionOverride (2) | RightToLeft (1) / LeftToRight (0)
            attrs[NSAttributedString.Key(kCTWritingDirectionAttributeName as String)] = [NSNumber(value: rtl ? 3 : 2)]
        }
        let spacing = kgLetterSpacing().perCluster
        if spacing == 0 {
            return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
        }
        if abs(letterSpacing) > 0.03 {
            // Required ligatures only (Minikin turns 'liga' and 'clig' off).
            attrs[NSAttributedString.Key(kCTLigatureAttributeName as String)] = NSNumber(value: 0)
        }
        let s = NSMutableAttributedString(string: text, attributes: attrs)
        let kernKey = NSAttributedString.Key(kCTKernAttributeName as String)
        let kern = NSNumber(value: Double(spacing / KitGraphics.density))
        var offset = 0
        for ch in text {
            let n = ch.utf16.count
            if n > 0 && APaint.kgScriptOkForLetterSpacing(ch) {
                s.addAttribute(kernKey, value: kern, range: NSRange(location: offset + n - 1, length: 1))
            }
            offset += n
        }
        return CTLineCreateWithAttributedString(s)
    }

    /// The advance width in px of the layout (not rounded), letter spacing included.
    func kgAdvance(_ text: String) -> Float {
        if text.isEmpty || !(kgLayoutSize > 0) { return 0 }
        let line = kgLine(text, nil, nil)
        return Float(CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) * KitGraphics.density)
    }

    /// A layout run's font at the drawing size (`kgPointSize`) with its font matrix kept; the run font itself when
    /// the layout and drawing sizes are equal (the usual case: an integral textSize).
    func kgDrawFont(_ runFont: CTFont) -> CTFont {
        if kgLayoutSize == textSize { return runFont }
        var matrix = CTFontGetMatrix(runFont)
        return CTFontCreateCopyWithAttributes(runFont, kgPointSize, &matrix, nil)
    }

    /// Font metrics in px (Android signs: ascent/top negative).
    func kgFontMetricValues() -> (top: Float, ascent: Float, descent: Float, bottom: Float, leading: Float) {
        if !(textSize > 0) { return (0, 0, 0, 0, 0) }
        let font = uiFont() as CTFont
        let d = KitGraphics.density
        let bbox = CTFontGetBoundingBox(font)
        return (top: -Float(bbox.maxY * d),
                ascent: -Float(CTFontGetAscent(font) * d),
                descent: Float(CTFontGetDescent(font) * d),
                bottom: -Float(bbox.minY * d),
                leading: Float(CTFontGetLeading(font) * d))
    }

    /// Underline position (top of the stroke, positive below the baseline) and thickness in px; Android's
    /// defaults (textSize / 9, textSize / 18) when the font has none.
    func kgUnderlineMetrics() -> (position: Float, thickness: Float) {
        if !(textSize > 0) { return (0, 0) }
        let font = uiFont() as CTFont
        let d = KitGraphics.density
        let position = CTFontGetUnderlinePosition(font)
        let thickness = CTFontGetUnderlineThickness(font)
        let pos = position != 0 ? -Float(position * d) : textSize * (Float(1) / 9)
        let th = thickness > 0 ? Float(thickness * d) : textSize * (Float(1) / 18)
        return (pos, th)
    }
}
