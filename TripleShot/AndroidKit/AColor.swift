import CoreGraphics
import UIKit

// android.graphics.Color, android.content.res.ColorStateList and android.util.StateSet (VIEW-API "Graphics").
//
// An Android colour is a Java int (32-bit ARGB). Here it is carried in a Swift Int that holds the
// sign-extended 32-bit value, i.e. exactly the number Kotlin prints for the same colour
// (0xFF000000.toInt() == -16777216). All arithmetic below is done on 32 bits like Java.

/// Kotlin `0xFF101724.toInt()`: an ARGB literal as an Android colour Int (sign-extended 32-bit value).
func argbInt(_ v: UInt32) -> Int {
    return Int(Int32(bitPattern: v))
}

enum AColor {
    static let BLACK: Int = argbInt(0xFF000000)
    static let DKGRAY: Int = argbInt(0xFF444444)
    static let GRAY: Int = argbInt(0xFF888888)
    static let LTGRAY: Int = argbInt(0xFFCCCCCC)
    static let WHITE: Int = argbInt(0xFFFFFFFF)
    static let RED: Int = argbInt(0xFFFF0000)
    static let GREEN: Int = argbInt(0xFF00FF00)
    static let BLUE: Int = argbInt(0xFF0000FF)
    static let YELLOW: Int = argbInt(0xFFFFFF00)
    static let CYAN: Int = argbInt(0xFF00FFFF)
    static let MAGENTA: Int = argbInt(0xFFFF00FF)
    static let TRANSPARENT: Int = 0

    /// Java int conversion of a Kotlin Int argument (Kotlin Ints are 32-bit).
    private static func j32(_ v: Int) -> Int32 {
        return Int32(truncatingIfNeeded: v)
    }

    /// `Color.alpha(color)`: `color >>> 24`.
    static func alpha(_ color: Int) -> Int {
        return Int(UInt32(truncatingIfNeeded: color) >> 24)
    }

    /// `Color.red(color)`: `(color >> 16) & 0xFF`.
    static func red(_ color: Int) -> Int {
        return Int((j32(color) >> 16) & 0xFF)
    }

    /// `Color.green(color)`: `(color >> 8) & 0xFF`.
    static func green(_ color: Int) -> Int {
        return Int((j32(color) >> 8) & 0xFF)
    }

    /// `Color.blue(color)`: `color & 0xFF`.
    static func blue(_ color: Int) -> Int {
        return Int(j32(color) & 0xFF)
    }

    /// `Color.rgb(red, green, blue)`: `0xff000000 | (red << 16) | (green << 8) | blue` on Java ints
    /// (out-of-range components spill into the neighbouring bytes exactly like Android).
    static func rgb(_ red: Int, _ green: Int, _ blue: Int) -> Int {
        let v: Int32 = Int32(bitPattern: 0xFF00_0000) | (j32(red) &<< 16) | (j32(green) &<< 8) | j32(blue)
        return Int(v)
    }

    /// `Color.argb(alpha, red, green, blue)`: `(alpha << 24) | (red << 16) | (green << 8) | blue` on Java ints.
    static func argb(_ alpha: Int, _ red: Int, _ green: Int, _ blue: Int) -> Int {
        let v: Int32 = (j32(alpha) &<< 24) | (j32(red) &<< 16) | (j32(green) &<< 8) | j32(blue)
        return Int(v)
    }

    /// `Color.parseColor(colorString)`: "#RRGGBB", "#AARRGGBB" or one of Android's colour names
    /// (case-insensitive). Android throws IllegalArgumentException for anything else; no caller catches it,
    /// so an invalid string stops the app here too.
    static func parseColor(_ colorString: String) -> Int {
        let units = Array(colorString.utf16)
        precondition(!units.isEmpty, "java.lang.StringIndexOutOfBoundsException: index 0, length 0")
        if units[0] == 0x23 /* '#' */ {
            // Use a long to avoid rollovers on #ffXXXXXX (Long.parseLong(colorString.substring(1), 16)).
            guard var color = javaParseLong(units[1...], 16) else {
                preconditionFailure("java.lang.NumberFormatException: For input string: \"\(colorString)\"")
            }
            if units.count == 7 {
                // Set the alpha value
                color |= 0x0000_0000_ff00_0000
            } else if units.count != 9 {
                preconditionFailure("java.lang.IllegalArgumentException: Unknown color")
            }
            return Int(Int32(truncatingIfNeeded: color))
        } else {
            // sColorNameMap.get(colorString.toLowerCase(Locale.ROOT))
            if let color = colorNames[colorString.lowercased()] {
                return color
            }
        }
        preconditionFailure("java.lang.IllegalArgumentException: Unknown color")
    }

    /// `Color.sColorNameMap`.
    private static let colorNames: [String: Int] = [
        "black": BLACK,
        "darkgray": DKGRAY,
        "gray": GRAY,
        "lightgray": LTGRAY,
        "white": WHITE,
        "red": RED,
        "green": GREEN,
        "blue": BLUE,
        "yellow": YELLOW,
        "cyan": CYAN,
        "magenta": MAGENTA,
        "aqua": argbInt(0xFF00FFFF),
        "fuchsia": argbInt(0xFFFF00FF),
        "darkgrey": DKGRAY,
        "grey": GRAY,
        "lightgrey": LTGRAY,
        "lime": argbInt(0xFF00FF00),
        "maroon": argbInt(0xFF800000),
        "navy": argbInt(0xFF000080),
        "olive": argbInt(0xFF808000),
        "purple": argbInt(0xFF800080),
        "silver": argbInt(0xFFC0C0C0),
        "teal": argbInt(0xFF008080),
    ]

    /// `java.lang.Long.parseLong(s, radix)` over UTF-16 units (ASCII digits and letters); nil = NumberFormatException.
    private static func javaParseLong(_ s: ArraySlice<UInt16>, _ radix: Int) -> Int64? {
        if s.isEmpty { return nil }
        var negative = false
        var i = s.startIndex
        var limit = -Int64.max
        let first = s[i]
        if first < 0x30 { // Possible leading "+" or "-"
            if first == 0x2D { // '-'
                negative = true
                limit = Int64.min
            } else if first != 0x2B { // '+'
                return nil
            }
            if s.count == 1 { return nil } // Cannot have lone "+" or "-"
            i += 1
        }
        let radix64 = Int64(radix)
        let multmin = limit / radix64
        var result: Int64 = 0
        while i < s.endIndex {
            guard let digit = asciiDigit(s[i], radix) else { return nil }
            i += 1
            if result < multmin { return nil }
            result *= radix64
            if result < limit + Int64(digit) { return nil }
            result -= Int64(digit)
        }
        return negative ? result : -result
    }

    private static func asciiDigit(_ c: UInt16, _ radix: Int) -> Int? {
        let value: Int
        switch c {
        case 0x30...0x39: value = Int(c) - 0x30
        case 0x41...0x5A: value = Int(c) - 0x41 + 10
        case 0x61...0x7A: value = Int(c) - 0x61 + 10
        default: return nil
        }
        return value < radix ? value : nil
    }

    /// `Color.colorToHSV(color, hsv)`: `RGBToHSV(red, green, blue, hsv)`.
    static func colorToHSV(_ color: Int, _ hsv: inout [Float]) {
        RGBToHSV((color >> 16) & 0xFF, (color >> 8) & 0xFF, color & 0xFF, &hsv)
    }

    /// `Color.RGBToHSV(red, green, blue, hsv)` = Skia `SkRGBToHSV` (float maths, unsigned 8-bit components):
    /// hue in [0, 360), saturation `delta / max`, value `max / 255`; a grey gets hue and saturation 0.
    static func RGBToHSV(_ red: Int, _ green: Int, _ blue: Int, _ hsv: inout [Float]) {
        precondition(hsv.count >= 3, "java.lang.RuntimeException: 3 components required for hsv")
        let r = UInt32(truncatingIfNeeded: red)
        let g = UInt32(truncatingIfNeeded: green)
        let b = UInt32(truncatingIfNeeded: blue)
        let mn = min(r, min(g, b))
        let mx = max(r, max(g, b))
        let delta = mx &- mn

        // ByteToScalar(max): SkIntToScalar(x) / 255
        let v = Float(Int32(bitPattern: mx)) / Float(255)
        if delta == 0 { // we're a shade of gray
            hsv[0] = 0
            hsv[1] = 0
            hsv[2] = v
            return
        }
        // ByteDivToScalar(numer, denom): SkIntToScalar(numer) / (int)denom
        let fdelta = Float(Int32(bitPattern: delta))
        let s = fdelta / Float(Int32(bitPattern: mx))
        var h: Float
        if r == mx {
            h = Float(Int32(bitPattern: g &- b)) / fdelta
        } else if g == mx {
            h = Float(2) + Float(Int32(bitPattern: b &- r)) / fdelta
        } else { // b == max
            h = Float(4) + Float(Int32(bitPattern: r &- g)) / fdelta
        }
        h *= 60
        if h < 0 {
            h += Float(360)
        }
        hsv[0] = h
        hsv[1] = s
        hsv[2] = v
    }

    /// `Color.HSVToColor(hsv)`: opaque.
    static func HSVToColor(_ hsv: [Float]) -> Int {
        return HSVToColor(0xFF, hsv)
    }

    /// `Color.HSVToColor(alpha, hsv)` = Skia `SkHSVToColor`.
    static func HSVToColor(_ alpha: Int, _ hsv: [Float]) -> Int {
        precondition(hsv.count >= 3, "java.lang.RuntimeException: 3 components required for hsv")
        let a = alpha & 0xFF
        let s = max(Float(0), min(hsv[1], Float(1)))
        let v = max(Float(0), min(hsv[2], Float(1)))
        let vByte = skRoundToInt(v * 255)
        if abs(s) <= KitGraphics.nearlyZero { // shade of gray
            return argb(a, vByte, vByte, vByte)
        }
        let hx: Float = (hsv[0] < 0 || hsv[0] >= Float(360)) ? 0 : hsv[0] / 60
        let w = hx.rounded(.down)
        let f = hx - w
        let p = skRoundToInt((Float(1) - s) * v * 255)
        let q = skRoundToInt((Float(1) - (s * f)) * v * 255)
        let t = skRoundToInt((Float(1) - (s * (Float(1) - f))) * v * 255)
        let r: Int, g: Int, b: Int
        switch KitGraphics.javaInt(w) {
        case 0: r = vByte; g = t; b = p
        case 1: r = q; g = vByte; b = p
        case 2: r = p; g = vByte; b = t
        case 3: r = p; g = q; b = vByte
        case 4: r = t; g = p; b = vByte
        default: r = vByte; g = p; b = q
        }
        return argb(a, r, g, b)
    }

    /// Skia `SkScalarRoundToInt`: `(int) floorf(x + 0.5f)`.
    private static func skRoundToInt(_ x: Float) -> Int {
        return KitGraphics.javaInt((x + 0.5).rounded(.down))
    }

    /// The colour for UIKit (sRGB, like Android).
    static func uiColor(_ c: Int) -> UIColor {
        return UIColor(cgColor: cgColor(c))
    }

    /// The colour for Core Graphics (sRGB, like Android).
    static func cgColor(_ c: Int) -> CGColor {
        return CGColor(srgbRed: CGFloat(red(c)) / 255, green: CGFloat(green(c)) / 255,
                       blue: CGFloat(blue(c)) / 255, alpha: CGFloat(alpha(c)) / 255)
    }
}

/// android.util.StateSet and the android.R.attr state ids used by drawable states.
enum AStateSet {
    static let state_focused = 16842908       // 0x0101009c
    static let state_window_focused = 16842909 // 0x0101009d
    static let state_enabled = 16842910       // 0x0101009e
    static let state_checkable = 16842911     // 0x0101009f
    static let state_checked = 16842912       // 0x010100a0
    static let state_selected = 16842913      // 0x010100a1
    static let state_pressed = 16842919       // 0x010100a7
    static let state_activated = 16843518     // 0x010102fe
    static let state_hovered = 16843623       // 0x01010367

    /// `StateSet.WILD_CARD` (matches every state) and `StateSet.NOTHING`.
    static let WILD_CARD: [Int] = []
    static let NOTHING: [Int] = [0]

    /// `StateSet.isWildCard(stateSetOrSpec)`.
    static func isWildCard(_ stateSetOrSpec: [Int]?) -> Bool {
        guard let s = stateSetOrSpec else { return true }
        return s.isEmpty || s[0] == 0
    }

    /// `StateSet.stateSetMatches(stateSpec, stateSet)`: positive spec entries must be present, negative ones
    /// must be absent; a 0 ends either array.
    static func stateSetMatches(_ stateSpec: [Int], _ stateSet: [Int]?) -> Bool {
        guard let stateSet = stateSet else {
            return isWildCard(stateSpec)
        }
        let stateSetSize = stateSet.count
        for i in 0..<stateSpec.count {
            var stateSpecState = stateSpec[i]
            if stateSpecState == 0 {
                // We've reached the end of the cases to match against.
                return true
            }
            let mustMatch: Bool
            if stateSpecState > 0 {
                mustMatch = true
            } else {
                // We use negative values to indicate must-NOT-match states.
                mustMatch = false
                stateSpecState = -stateSpecState
            }
            var found = false
            var j = 0
            while j < stateSetSize {
                let state = stateSet[j]
                if state == 0 {
                    // We've reached the end of states to match.
                    if mustMatch {
                        // We didn't find this must-match state.
                        return false
                    } else {
                        // Continue checking other must-not-match states.
                        break
                    }
                }
                if state == stateSpecState {
                    if mustMatch {
                        found = true
                        // Continue checking other other must-match states.
                        break
                    } else {
                        // Any match of a must-not-match state returns false.
                        return false
                    }
                }
                j += 1
            }
            if mustMatch && !found {
                // We've reached the end of states to match and we didn't
                // find a must-match state.
                return false
            }
        }
        return true
    }
}

/// android.content.res.ColorStateList. Not Equatable: Android compares ColorStateLists by identity.
final class AColorStateList {
    /// `ColorStateList.DEFAULT_COLOR` (used when there are no specs).
    private static let DEFAULT_COLOR = argbInt(0xFFFF0000)

    private let stateSpecs: [[Int]]
    private let colorList: [Int]
    /// The colour of the last empty (wild-card) spec, else the first colour (Android `onColorsChanged`).
    let defaultColor: Int
    /// All colours are opaque.
    let isOpaque: Bool

    /// `new ColorStateList(states, colors)`.
    init(_ states: [[Int]], _ colors: [Int]) {
        stateSpecs = states
        colorList = colors
        var defaultColor = AColorStateList.DEFAULT_COLOR
        var isOpaque = true
        let n = states.count
        if n > 0 {
            defaultColor = colors[0]
            var i = n - 1
            while i > 0 {
                if states[i].isEmpty {
                    defaultColor = colors[i]
                    break
                }
                i -= 1
            }
            for c in 0..<n where AColor.alpha(colors[c]) != 0xFF {
                isOpaque = false
                break
            }
        }
        self.defaultColor = defaultColor
        self.isOpaque = isOpaque
    }

    /// `ColorStateList.valueOf(color)`: one wild-card spec.
    static func valueOf(_ color: Int) -> AColorStateList {
        return AColorStateList([[]], [color])
    }

    /// `getColorForState(stateSet, defaultColor)`: the colour of the first matching spec.
    func getColorForState(_ stateSet: [Int]?, _ defaultColor: Int) -> Int {
        for i in 0..<stateSpecs.count where AStateSet.stateSetMatches(stateSpecs[i], stateSet) {
            return colorList[i]
        }
        return defaultColor
    }

    /// `isStateful()`: the first spec is not a wild card.
    var isStateful: Bool {
        return stateSpecs.count >= 1 && !stateSpecs[0].isEmpty
    }

    /// `getDefaultColor()`.
    func getDefaultColor() -> Int {
        return defaultColor
    }

    /// `withAlpha(alpha)`: every colour with the given alpha.
    func withAlpha(_ alpha: Int) -> AColorStateList {
        let colors = colorList.map { c -> Int in
            Int((Int32(truncatingIfNeeded: c) & 0xFFFFFF) | (Int32(truncatingIfNeeded: alpha) &<< 24))
        }
        return AColorStateList(stateSpecs, colors)
    }

    /// `getStates()` / `getColors()` (hidden API on Android; useful for ports of custom drawables).
    func getStates() -> [[Int]] { return stateSpecs }
    func getColors() -> [Int] { return colorList }
}
