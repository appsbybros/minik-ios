import UIKit

// AndroidKit widgets (area kit-widgets): android.widget.EditText on ATextView with a UIKit editor (UITextField for
// single-line text, UITextView for multi-line text), android.text.InputType, android.view.inputmethod.EditorInfo,
// android.text.InputFilter (LengthFilter / AllCaps in UTF-16 units) and the DigitsKeyListener filter of number fields,
// TextView.setError with the framework error icon and ErrorPopup, com.google.android.material.textfield.TextInputLayout
// (FilledBox) with TextInputEditText and its CollapsingTextHelper label, and android.widget.Switch.
//
// EditText (Widget.Material.Light.EditText, android:editTextStyle of Theme.TripleShot): 18 sp, ?android:editTextColor
// (87 % black, disabled 26 %), hint ?android:textColorHint (60 % black), gravity center_vertical, focusable /
// focusableInTouchMode / clickable / long-clickable, break strategy simple, input type text|multiLine, background
// edit_text_material (inset 4/10/4/7 dp around the textfield nine-patch: a 1 dp colorControlNormal line, 2 dp
// colorControlActivated when focused or pressed; padding 4/10/4/11 dp). The TextView measures and lays out the text and
// hint exactly as Android (AWidgetsText); UIKit only edits and draws the typed text, its first baseline placed on the
// Android baseline; the hint is drawn by the TextView itself. Edits follow SpannableStringBuilder.replace: the input
// filters (then the key listener filter) run on (source, dest, dstart, dend), watchers get beforeTextChanged /
// onTextChanged / afterTextChanged, an unchanged error is hidden after an edit, and setText puts the cursor at 0
// (ArrowKeyMovementMethod.initialize). The view keeps the Android focus when the keyboard is hidden by the IME action
// (Android hides the soft input but the field stays focused).
//
// Ported from the Android 15 framework (TextView, Editor error popup, EditText, Switch, CompoundButton), material
// 1.12.0 (TextInputLayout, TextInputEditText, CollapsingTextHelper, StaticLayoutBuilderCompat) and androidx
// interpolator 1.0.0 (FastOutSlowInInterpolator). The error popup backgrounds and the error icon are the framework's
// own images (android-36 res, xhdpi / xxhdpi), embedded below.

// MARK: - android.text.InputType

enum AInputType {
    static let TYPE_MASK_CLASS = 0x0000000f
    static let TYPE_MASK_VARIATION = 0x00000ff0
    static let TYPE_MASK_FLAGS = 0x00fff000
    static let TYPE_NULL = 0x00000000
    static let TYPE_CLASS_TEXT = 0x00000001
    static let TYPE_TEXT_FLAG_CAP_CHARACTERS = 0x00001000
    static let TYPE_TEXT_FLAG_CAP_WORDS = 0x00002000
    static let TYPE_TEXT_FLAG_CAP_SENTENCES = 0x00004000
    static let TYPE_TEXT_FLAG_AUTO_CORRECT = 0x00008000
    static let TYPE_TEXT_FLAG_AUTO_COMPLETE = 0x00010000
    static let TYPE_TEXT_FLAG_MULTI_LINE = 0x00020000
    static let TYPE_TEXT_FLAG_IME_MULTI_LINE = 0x00040000
    static let TYPE_TEXT_FLAG_NO_SUGGESTIONS = 0x00080000
    static let TYPE_TEXT_FLAG_ENABLE_TEXT_CONVERSION_SUGGESTIONS = 0x00100000
    static let TYPE_TEXT_VARIATION_NORMAL = 0x00000000
    static let TYPE_TEXT_VARIATION_URI = 0x00000010
    static let TYPE_TEXT_VARIATION_EMAIL_ADDRESS = 0x00000020
    static let TYPE_TEXT_VARIATION_EMAIL_SUBJECT = 0x00000030
    static let TYPE_TEXT_VARIATION_SHORT_MESSAGE = 0x00000040
    static let TYPE_TEXT_VARIATION_LONG_MESSAGE = 0x00000050
    static let TYPE_TEXT_VARIATION_PERSON_NAME = 0x00000060
    static let TYPE_TEXT_VARIATION_POSTAL_ADDRESS = 0x00000070
    static let TYPE_TEXT_VARIATION_PASSWORD = 0x00000080
    static let TYPE_TEXT_VARIATION_VISIBLE_PASSWORD = 0x00000090
    static let TYPE_TEXT_VARIATION_WEB_EDIT_TEXT = 0x000000a0
    static let TYPE_TEXT_VARIATION_FILTER = 0x000000b0
    static let TYPE_TEXT_VARIATION_PHONETIC = 0x000000c0
    static let TYPE_TEXT_VARIATION_WEB_EMAIL_ADDRESS = 0x000000d0
    static let TYPE_TEXT_VARIATION_WEB_PASSWORD = 0x000000e0
    static let TYPE_CLASS_NUMBER = 0x00000002
    static let TYPE_NUMBER_FLAG_SIGNED = 0x00001000
    static let TYPE_NUMBER_FLAG_DECIMAL = 0x00002000
    static let TYPE_NUMBER_VARIATION_NORMAL = 0x00000000
    static let TYPE_NUMBER_VARIATION_PASSWORD = 0x00000010
    static let TYPE_CLASS_PHONE = 0x00000003
    static let TYPE_CLASS_DATETIME = 0x00000004
    static let TYPE_DATETIME_VARIATION_NORMAL = 0x00000000
    static let TYPE_DATETIME_VARIATION_DATE = 0x00000010
    static let TYPE_DATETIME_VARIATION_TIME = 0x00000020
}

// MARK: - android.view.inputmethod.EditorInfo

/// android.view.inputmethod.EditorInfo (which also implements InputType: the input type constants are on AInputType).
enum AEditorInfo {
    static let IME_MASK_ACTION = 0x000000ff
    static let IME_ACTION_UNSPECIFIED = 0x00000000
    static let IME_ACTION_NONE = 0x00000001
    static let IME_ACTION_GO = 0x00000002
    static let IME_ACTION_SEARCH = 0x00000003
    static let IME_ACTION_SEND = 0x00000004
    static let IME_ACTION_NEXT = 0x00000005
    static let IME_ACTION_DONE = 0x00000006
    static let IME_ACTION_PREVIOUS = 0x00000007
    static let IME_FLAG_NO_PERSONALIZED_LEARNING = 0x1000000
    static let IME_FLAG_NO_FULLSCREEN = 0x2000000
    static let IME_FLAG_NAVIGATE_PREVIOUS = 0x4000000
    static let IME_FLAG_NAVIGATE_NEXT = 0x8000000
    static let IME_FLAG_NO_EXTRACT_UI = 0x10000000
    static let IME_FLAG_NO_ACCESSORY_ACTION = 0x20000000
    static let IME_FLAG_NO_ENTER_ACTION = 0x40000000
    /// 0x80000000 as a Java int.
    static let IME_FLAG_FORCE_ASCII = Int(Int32.min)
    static let IME_NULL = 0x00000000
}

// MARK: - android.text.InputFilter

/// android.text.InputFilter: `filter` returns the replacement for source[start, end) (UTF-16 offsets), or nil to accept
/// it as it is. `dest` is the text being edited and [dstart, dend) the range the source replaces.
protocol AInputFilter: AnyObject {
    func filter(_ source: String, _ start: Int, _ end: Int, _ dest: String, _ dstart: Int, _ dend: Int) -> String?
}

/// android.text.InputFilter.LengthFilter: at most `max` UTF-16 units; a cut never leaves a lone high surrogate.
final class ALengthFilter: AInputFilter {
    private let mMax: Int

    init(_ max: Int) { mMax = max }

    func getMax() -> Int { return mMax }
    var max: Int { return mMax }

    func filter(_ source: String, _ start: Int, _ end: Int, _ dest: String, _ dstart: Int, _ dend: Int) -> String? {
        var keep = mMax - (dest.utf16.count - (dend - dstart))
        if keep <= 0 {
            return ""
        } else if keep >= end - start {
            return nil // keep original
        } else {
            keep += start
            let units = Array(source.utf16)
            if UTF16.isLeadSurrogate(units[keep - 1]) {
                keep -= 1
                if keep == start {
                    return ""
                }
            }
            return String(decoding: units[start..<keep], as: UTF16.self)
        }
    }
}

/// android.text.InputFilter.AllCaps (locale: the default locale, like `new AllCaps()`).
final class AAllCapsFilter: AInputFilter {
    private let mLocale: ALocale?

    init() { mLocale = nil }
    init(_ locale: ALocale) { mLocale = locale }

    func filter(_ source: String, _ start: Int, _ end: Int, _ dest: String, _ dstart: Int, _ dend: Int) -> String? {
        let units = Array(source.utf16)
        let part = String(decoding: units[start..<end], as: UTF16.self)
        var lowerOrTitleFound = false
        for s in part.unicodeScalars {
            let cat = s.properties.generalCategory
            if cat == .lowercaseLetter || cat == .titlecaseLetter || s.properties.isLowercase {
                lowerOrTitleFound = true
                break
            }
        }
        if !lowerOrTitleFound {
            return nil // keep original
        }
        let locale = Locale(identifier: (mLocale ?? ALocale.getDefault()).toLanguageTag())
        let upper = part.uppercased(with: locale)
        if upper == part {
            return nil
        }
        return upper
    }
}

/// android.text.method.DigitsKeyListener as the InputFilter TextView adds for TYPE_CLASS_NUMBER (NumberKeyListener.filter
/// over the accepted characters, then the sign / decimal-point rules of DigitsKeyListener.filter).
final class AWDigitsKeyFilter: AInputFilter {
    /// DigitsKeyListener DEFAULT_SIGN_CHARS / DEFAULT_DECIMAL_POINT_CHARS.
    private static let SIGN_CHARS: Set<UInt16> = Set("-+\u{2212}".utf16)
    private static let DECIMAL_POINT_CHARS: Set<UInt16> = Set(".".utf16)

    private let mSign: Bool
    private let mDecimal: Bool
    /// COMPATIBILITY_CHARACTERS of the kind (no locale: TextView.getCustomLocaleForKeyListenerOrNull is null).
    private let mAccepted: [UInt16]

    init(_ sign: Bool, _ decimal: Bool) {
        mSign = sign
        mDecimal = decimal
        var chars = "0123456789"
        if sign { chars += "-+" }
        if decimal { chars += "." }
        mAccepted = Array(chars.utf16)
    }

    private func ok(_ c: UInt16) -> Bool { return mAccepted.contains(c) }
    private static func isSignChar(_ c: UInt16) -> Bool { return SIGN_CHARS.contains(c) }
    private static func isDecimalPointChar(_ c: UInt16) -> Bool { return DECIMAL_POINT_CHARS.contains(c) }

    /// NumberKeyListener.filter (its loop reads `source.charAt(j)` with the range-relative j, as AOSP does).
    private func numberFilter(_ units: [UInt16], _ start: Int, _ end: Int) -> [UInt16]? {
        var i = start
        while i < end {
            if !ok(units[i]) { break }
            i += 1
        }
        if i == end {
            return nil
        }
        if end - start == 1 {
            return []
        }
        var filtered = Array(units[start..<end])
        i -= start
        let end2 = end - start
        var j = end2 - 1
        while j >= i {
            if !ok(units[j]) {
                filtered.remove(at: j)
            }
            j -= 1
        }
        return filtered
    }

    /// DigitsKeyListener.filter.
    func filter(_ source: String, _ start0: Int, _ end0: Int, _ dest: String, _ dstart: Int, _ dend: Int) -> String? {
        var units = Array(source.utf16)
        var start = start0, end = end0
        let out = numberFilter(units, start, end)
        if !mSign && !mDecimal {
            return out.map { String(decoding: $0, as: UTF16.self) }
        }
        if let o = out {
            units = o
            start = 0
            end = o.count
        }
        var sign = -1
        var decimal = -1
        let destUnits = Array(dest.utf16)
        let dlen = destUnits.count
        var i = 0
        while i < dstart {
            let c = destUnits[i]
            if AWDigitsKeyFilter.isSignChar(c) {
                sign = i
            } else if AWDigitsKeyFilter.isDecimalPointChar(c) {
                decimal = i
            }
            i += 1
        }
        i = dend
        while i < dlen {
            let c = destUnits[i]
            if AWDigitsKeyFilter.isSignChar(c) {
                return "" // Nothing can be inserted in front of a sign character.
            } else if AWDigitsKeyFilter.isDecimalPointChar(c) {
                decimal = i
            }
            i += 1
        }
        var stripped: [UInt16]? = nil
        i = end - 1
        while i >= start {
            let c = units[i]
            var strip = false
            if AWDigitsKeyFilter.isSignChar(c) {
                if i != start || dstart != 0 {
                    strip = true
                } else if sign >= 0 {
                    strip = true
                } else {
                    sign = i
                }
            } else if AWDigitsKeyFilter.isDecimalPointChar(c) {
                if decimal >= 0 {
                    strip = true
                } else {
                    decimal = i
                }
            }
            if strip {
                if end == start + 1 {
                    return "" // Only one character, and it was stripped.
                }
                if stripped == nil {
                    stripped = Array(units[start..<end])
                }
                stripped!.remove(at: i - start)
            }
            i -= 1
        }
        if let s = stripped {
            return String(decoding: s, as: UTF16.self)
        } else if let o = out {
            return String(decoding: o, as: UTF16.self)
        }
        return nil
    }
}

// MARK: - Interpolation helpers

/// androidx.interpolator.view.animation.FastOutSlowInInterpolator (LookupTableInterpolator over 201 values).
final class AFastOutSlowInInterpolator: ATimeInterpolator {
    private static let VALUES: [Float] = [
        0.0000, 0.0001, 0.0002, 0.0005, 0.0009, 0.0014, 0.0020,
        0.0027, 0.0036, 0.0046, 0.0058, 0.0071, 0.0085, 0.0101,
        0.0118, 0.0137, 0.0158, 0.0180, 0.0205, 0.0231, 0.0259,
        0.0289, 0.0321, 0.0355, 0.0391, 0.0430, 0.0471, 0.0514,
        0.0560, 0.0608, 0.0660, 0.0714, 0.0771, 0.0830, 0.0893,
        0.0959, 0.1029, 0.1101, 0.1177, 0.1257, 0.1339, 0.1426,
        0.1516, 0.1610, 0.1707, 0.1808, 0.1913, 0.2021, 0.2133,
        0.2248, 0.2366, 0.2487, 0.2611, 0.2738, 0.2867, 0.2998,
        0.3131, 0.3265, 0.3400, 0.3536, 0.3673, 0.3810, 0.3946,
        0.4082, 0.4217, 0.4352, 0.4485, 0.4616, 0.4746, 0.4874,
        0.5000, 0.5124, 0.5246, 0.5365, 0.5482, 0.5597, 0.5710,
        0.5820, 0.5928, 0.6033, 0.6136, 0.6237, 0.6335, 0.6431,
        0.6525, 0.6616, 0.6706, 0.6793, 0.6878, 0.6961, 0.7043,
        0.7122, 0.7199, 0.7275, 0.7349, 0.7421, 0.7491, 0.7559,
        0.7626, 0.7692, 0.7756, 0.7818, 0.7879, 0.7938, 0.7996,
        0.8053, 0.8108, 0.8162, 0.8215, 0.8266, 0.8317, 0.8366,
        0.8414, 0.8461, 0.8507, 0.8551, 0.8595, 0.8638, 0.8679,
        0.8720, 0.8760, 0.8798, 0.8836, 0.8873, 0.8909, 0.8945,
        0.8979, 0.9013, 0.9046, 0.9078, 0.9109, 0.9139, 0.9169,
        0.9198, 0.9227, 0.9254, 0.9281, 0.9307, 0.9333, 0.9358,
        0.9382, 0.9406, 0.9429, 0.9452, 0.9474, 0.9495, 0.9516,
        0.9536, 0.9556, 0.9575, 0.9594, 0.9612, 0.9629, 0.9646,
        0.9663, 0.9679, 0.9695, 0.9710, 0.9725, 0.9739, 0.9753,
        0.9766, 0.9779, 0.9791, 0.9803, 0.9815, 0.9826, 0.9837,
        0.9848, 0.9858, 0.9867, 0.9877, 0.9885, 0.9894, 0.9902,
        0.9910, 0.9917, 0.9924, 0.9931, 0.9937, 0.9944, 0.9949,
        0.9955, 0.9960, 0.9964, 0.9969, 0.9973, 0.9977, 0.9980,
        0.9984, 0.9986, 0.9989, 0.9991, 0.9993, 0.9995, 0.9997,
        0.9998, 0.9999, 0.9999, 1.0000, 1.0000
    ]
    private static let STEP_SIZE: Float = 1 / Float(VALUES.count - 1)

    init() {}

    func getInterpolation(_ input: Float) -> Float {
        if input >= 1.0 { return 1.0 }
        if input <= 0 { return 0 }
        let values = AFastOutSlowInInterpolator.VALUES
        let position = Swift.min(AWMath.javaInt(input * Float(values.count - 1)), values.count - 2)
        let quantized = Float(position) * AFastOutSlowInInterpolator.STEP_SIZE
        let diff = input - quantized
        let weight = diff / AFastOutSlowInInterpolator.STEP_SIZE
        return values[position] + weight * (values[position + 1] - values[position])
    }
}

/// com.google.android.material.animation.AnimationUtils.
enum AWAnimationUtils {
    static let FAST_OUT_SLOW_IN_INTERPOLATOR = AFastOutSlowInInterpolator()

    static func lerp(_ startValue: Float, _ endValue: Float, _ fraction: Float) -> Float {
        return startValue + (fraction * (endValue - startValue))
    }

    static func lerp(_ startValue: Int, _ endValue: Int, _ fraction: Float) -> Int {
        return startValue + AWMath.round(fraction * Float(endValue - startValue))
    }
}

// MARK: - Framework images (nine-patches)

/// A framework nine-patch: the PNG without its 1 px border, one stretchable run per axis, its padding (l, t, r, b),
/// all in the pixels of its density bucket (drawn 1:1 on a device of that density, scaled otherwise).
struct AWNinePatch {
    let density: Int
    let width: Int
    let height: Int
    let stretchX: Range<Int>
    let stretchY: Range<Int>
    let padding: (Int, Int, Int, Int)
    let above: Bool
    let png: String

    /// The bucket closest to the device density (xhdpi for 2x, xxhdpi for 3x).
    static func select(_ list: [AWNinePatch], above: Bool) -> AWNinePatch {
        let d = AWidgetEnv.density
        let candidates = list.filter { $0.above == above }
        return candidates.min { abs(Float($0.density) - d) < abs(Float($1.density) - d) } ?? candidates[0]
    }

    var scale: Float { return AWidgetEnv.density / Float(density) }

    /// Padding in device px (NinePatchDrawable scales the bucket padding to the device density).
    func paddingPx() -> ARect {
        let s = scale
        return ARect(AWMath.round(Float(padding.0) * s), AWMath.round(Float(padding.1) * s),
                     AWMath.round(Float(padding.2) * s), AWMath.round(Float(padding.3) * s))
    }

    nonisolated(unsafe) private static var bitmaps: [String: ABitmap] = [:]

    func bitmap() -> ABitmap? {
        let key = "\(density)-\(above)-\(width)x\(height)-\(png.count)"
        if let b = AWNinePatch.bitmaps[key] { return b }
        guard let data = Data(base64Encoded: png), let image = UIImage(data: data)?.cgImage else { return nil }
        let b = ABitmap(cgImage: image)
        AWNinePatch.bitmaps[key] = b
        return b
    }

    /// NinePatch.draw into `dst` (px): the fixed edges keep their (density-scaled) size, the stretch runs fill the rest.
    func draw(_ canvas: ACanvas, _ dst: ARect, _ paint: APaint?) {
        guard let b = bitmap() else { return }
        let s = scale
        let xs = [0, stretchX.lowerBound, stretchX.upperBound, width]
        let ys = [0, stretchY.lowerBound, stretchY.upperBound, height]
        let fixedW = Float(width - stretchX.count) * s
        let fixedH = Float(height - stretchY.count) * s
        let extraW = Swift.max(Float(dst.width()) - fixedW, 0)
        let extraH = Swift.max(Float(dst.height()) - fixedH, 0)
        func dxs() -> [Float] {
            let l = Float(stretchX.lowerBound) * s
            return [Float(dst.left), Float(dst.left) + l, Float(dst.left) + l + extraW, Float(dst.right)]
        }
        func dys() -> [Float] {
            let t = Float(stretchY.lowerBound) * s
            return [Float(dst.top), Float(dst.top) + t, Float(dst.top) + t + extraH, Float(dst.bottom)]
        }
        let dx = dxs(), dy = dys()
        for row in 0..<3 {
            for col in 0..<3 {
                if xs[col + 1] <= xs[col] || ys[row + 1] <= ys[row] { continue }
                if dx[col + 1] <= dx[col] || dy[row + 1] <= dy[row] { continue }
                canvas.drawBitmap(b, ARect(xs[col], ys[row], xs[col + 1], ys[row + 1]),
                                  ARectF(dx[col], dy[row], dx[col + 1], dy[row + 1]), paint)
            }
        }
    }
}

/// The framework images of TextView.setError (Theme.Material.Light: errorMessageBackground =
/// popup_inline_error_holo_light, errorMessageAboveBackground = popup_inline_error_above_holo_light;
/// indicator_input_error), AOSP android-36 res (Apache 2.0), xhdpi and xxhdpi.
enum AWFrameworkImages {
    static let errorPopups: [AWNinePatch] = [
        AWNinePatch(density: 2, width: 124, height: 100, stretchX: 44..<64, stretchY: 48..<76, padding: (40, 48, 38, 24), above: false,
                    png: "iVBORw0KGgoAAAANSUhEUgAAAHwAAABkCAYAAABEm1RIAAAER0lEQVR42u2dT2tjVRiHn/fmJmliw4xMW9pRRhFGK2YhTlEQdeVCBau4cucHEMGvoiuXrgRBF34Ddwp2mUFwRHQoM1DaTmymTXJz7zkuctKGmbbkTv9wE38PZBFIDrnnye+c974nEPPeI/4/RJoCCRcSLiRcSLiQcCHhQsKFhAsJFxIuJFycSqwpyEmzaYCFZ55Wa6pOn0ynZROLjoBSCMmRcEiBjFbLSfhspToOj7kgHiADekF6Og1pl/DJkh0B88Ac/0YvsB19BMCC+4kr7i+gC+wDruhJ1x4+WWE7SvY87ehdEvsYgHa0zxX3XXhdPyTdKeHTu4xHQA2o4XmWrdLrbEdfA5XwqoQF9wVL2W8YmyHp3ZB0r4RPFyPhVaDGbvQyHVsfkw1QoWMfEkcdrrmdkO5+KOa8Ej5d+3Y1PJbZtxvcjb/FsXLCon+PG+lnPOU3gftBelLE/VyNl5OX8jIwR8+W2I3ewbF84nscK+xGb9O3hbAFVAALYynhBZddDsIW8VzlTvkrBrzxyFJ+HAll/ws30y8x2sA2kACDIu3nSvjjHbRyWMrn2Y1WSXltAtnD/Ty1WzyIVoFGGCMuWtLzJfzogxuzV6CNumhPAw3+jj+na5/guJ4zQpvU/A88n34DdIAHoUGTXsJ1DGWesqLEOQuZ0f4WzZD00XWUw6NB35bo2XsnFmmn4XiGnr1PYj9S8RwWcEfdOX+Bsh3gaDb9SQXjZAkfyh5NSD18USoztCXYYVW+VXqTdvQpA94604gV/zNX3fcsul/HpF+UbBfGT4EDYBBqB5c/4Y/vbY0guzZDSR8Jr7BnH5Dy6plHHNgt9qI9Ft2dIKN/QcJHye6OdfuGhzrNpj26vMc5irs60OB2+U+AZOXaTNZulf7OeWlo0LP1ZHd5/VI+9/0dMnxWeiV9MdQOyXFt3jhHxyker1ZLD7uq7CfgMufJDz1VwmpsZynaLAw0d3ghnQPZnET45c/TXFjeR1ux1304+k3bJIVBwvCwXxSUEOVeqNKPPcCJclSBaZAuik0yJvyJ93AX7u+yl6q/b1XNrG5mkdnMtdymMdXOew689z3n/B/cbIfbM/dkwlstT7Ppw7eGTpb5rhkHZl7CiyM88d4Phk205PBe/JgW62QJb7UczeYASHeyzJmZqr2C4YDQNe0G2e5svfShdBt4r1QXNe1D4af+vCr3ebiZ3dPUFlr6dZ2HCwmXcCHhQsKFhAsJFxIuJFxIuJBwIeFCwoWECwkXEi7hQsKFhAsJFxIuJFxIuJBwIeFCwoWECwkXEi7hQsKFhAsJFxIuJFxIuJBwIeFCwoWECwkXEi4kXMKFhAsJFxIupoQ47xuq1WrC8G8oRYHo9/sZ8PDchdfr9btZlq1qdSic8AFwm3P9/3BgbW3tOU1v8djY2PjnQpZ0oK3pnV5yJ1yoShcSLiRcSLiQcCHhQsKFhAsJF8fwH+Ntbl5bfdCcAAAAAElFTkSuQmCC"),
        AWNinePatch(density: 2, width: 124, height: 100, stretchX: 44..<64, stretchY: 28..<56, padding: (40, 28, 38, 44), above: true,
                    png: "iVBORw0KGgoAAAANSUhEUgAAAHwAAABkCAYAAABEm1RIAAAEU0lEQVR42u2dz2scZRjHP8/s7I8kTUy2GGwCFSsehM1VL9qr4FFv7VH8I7z7VwgeLV68KFYRD6JeBMlptRYFUUiiNpHQjcnu7Oz7eNh321TWzW43aabb7wcCS5gMzPvZ59c7Q8bcHfHkkGgJJFxIuJBwIeFCwoWECwkXEi4kXEi4mJR00j8ws4+Al9fX18tavuKwtbXVBb5z9zdPVTiwASStVitomQuXrTdODNhJ75aZ2bbWtri4+5pquJBwCRcSLiRcSLiQcCHhQsKFhAsJFxIuJFxIuJBwIeESLiRcSLiQcCHhQsKFhAsJFxIuJFxIuJBwIeESLiRcSLiQcCHhQsKFhAsJFxIuJFxIuJBwIeFCwiVcSLiQcCHhgll8I0KjYQaYmVaOQv6vdGg0jGbTpxfeaCSAlc0wM6WGghEAH2TtRsNpNsPDC+/LLgPli6VSkppZxYzEDMX6OUc1ENzJ3L3bf7vFHNCl0egOk56Ok8YBi8Kri6WSVc1s3swkvDjCD929HYIDlfjrfFh6Tydo7uaBxdudF1e1zMWkizvky0ALyGKmn7hLt3hcGr89othUYja2acYyiyeqaT2LSzRcOybcNIdrDh+7N8iA9k51ttu0Sx0/1fM9yvXqApehHT/6/UltMuEei38OZNszXsUvdU73fI9yvXrgl/uB2R0me5IID8Ah0Pv+Srg6516Zh1oCifH4T2YGVoFKCmVu23Uyu4pzYcqTtqj6V3vPhQ9z6GaQ+f9ImHIs8x6EI2gfmmUv5ewDnWEd+njCm02n0fD4reEp9505SOegHIXPQrNjNfdKBaoscZN9W6LLK1OdtOybLIWbdef3DLK22VkJJ0AoQ1Z2z2PpzQEftsU6/rtH49ZqbPQSmJk9l8F1lOPP03RslV/T9+nx/ENcp1PiZ67kb1HxO8DuMQlwBtL/U3pDlB2m20tvNkPcdQszJPu49F6U0qLqUPPPObI3CKwx2f3HLeb8Myq+CxwMSuEx4Zzxxhujbp5M/HbhmeX+FvJcnGXX2Es2+LP0Hs7CmF+bA57pvU09/ABsA0f0u2YfJQHdDz8H+kIGvUoHOKAebpGyGVPySWSkbLISfoqR3RlVS88tlSnCh0Z6CVgA5mnbC9xJXuNu8s6IUuYshXdZDV9Q9V9iGu+n8gLJVoSPHkMz4Iia/8VK+JqEP0as4g718A1V341pvH/jomCyFeEnTyUlYAlYYC95lb+Ta2T2+gPHVf1TVsINLoZvgX+AuzGyA3qmjcfuVnOsxUfUw48s+seD/Yh7dXvRP6EebsXI7jz48EkBxxFF+ImRnsbxdRm4wG/pNQ7tOgDz/gHP5jdik7YP5DSbOTPzEOOTW8/zOF7BcviSPFm497kvux2PCUW/GEX4+J37INJrsbYTN1QGsvMiNmkSPn0Tlx7rfQbRX9gmTcJPb0eOom2qSLjQWCbhQsKFhAsJFxIuJFxIuJBwIeFCwoWEiwn5Fyn7hDKBv3d3AAAAAElFTkSuQmCC"),
        AWNinePatch(density: 3, width: 180, height: 150, stretchX: 60..<90, stretchY: 72..<114, padding: (54, 72, 57, 36), above: false,
                    png: "iVBORw0KGgoAAAANSUhEUgAAALQAAACWCAYAAAB3qaIPAAAGZElEQVR42u3cz28UZRzH8c8zOzvTli0FhASlIMRqUhB/xJjogUQj0QQCBoNIuBA4qIkmhgQT6w9EE+OBgwlRD3pA0BBPHjyQIFH8AzDRgzHxIHrTGG9Y2/0xjwdnmodxdndm2/3R7vuVbKC/tmV579PvPDOtsdYKWCk8HgIQNEDQAEEDBA2CBggaIGiAoAGCBkEDBA0QNEDQAEGDoAGCBggaIGiAoEHQwHLj8xAsL8YYk/V6y4/vE/Qyjdg0eR/iJuhlE7NxYjaS9OXY9BeStH/2p6eSjuObjDFDGzUz9PKI2cT/V54k79zI1Ok9s+G+PbPhvnMjU6fdtyXv32w0IWgMSswlSf6ZcOuBg/NjM6X4FQfnx2bOhFsPxN9tS8MeNUEvn5hLJ4JN00dq4xcq1lv4f6tYzztcq5w/EWyaTt5vmKMm6GUS8y5/Yu3xxsTXt0WlIP0xk5EfHmtMXNnlT6wd9qgJeoDbTsYMSeW3za1X724Ea5q9885GsO5Ns/ErSWVn/GDkwECszp6z0vqfB1OfPVIbubPdxz9WG91+MZg67wS9sFIPyypN0IMZ88JB4PvhtlcOVit7897PoWpl/9lw20upg8ShiZqgBzNmX5L/VrjlyaPV8ZdLBe6rJOlYdfzUa8Hmx4dx54OgB+sgMJmbS88FG6eP11Z/5O5o5FWxnvd8feLTI+UNtw9b1AQ9gDsaD/ur17zQWHdpMvLDTu97MvLDk3bDN3eURlcN084HQQ/mjsblnY1g3WLv9P56sP4Db8tlZ+fDW+k7HwQ9YDsaF4OpT3bXRqeX6vM8URu950Iw9WEyl6/0nQ+CHqAdjbPhtpOHqpX9S/35DldXPfNeuPXFYdj5IOgBuUbjVLh577Hq+EypC5+zLGOOVleffjWcfHSlHySaIlcZNvmHGzItPC8bd3vu2WDj9jfq679dzEFgHtdL9dnXvT8eulj78zdJNUkNSZGcS08HgF3MDy+0DdqJuNmfhF0sZrkr84P++JqPtfm7e+vBLb34Aq75878/ba8/8Gtj7kYcdBK1+hy1bfLyTX+2i7tl0E0uLs+6EXSxMW8h6Cvh9NXd8+GOXn4Bl0bmr+2d+2mPpLoTdDQgMdsWt6RpWzjoVMzJvOVZ3TdHk+iFG8ZG4/aHMWcsitpF7RdYUTwOItHTZfu/ZpOrBpOYo05/pjDzaJyHGb2bQ6yJm2s444hpNe97OQ4E3QtmyjzM6LFyeu+81a9z8ItsLxE0+iBIHSxGcZe2kxMr6bNZBI1+rdClPNeiFJmhfUm+0fd/SaryOKNHq3MyHdQztooXtUJ7HBRC/fllSDf9zhF1cC2HyTizxbYd1McTUV6eE3lewWsPCBr9Crrt6twu6KxT3ASNfgSd+zILr4OrxAD16aIudTpDA4MYMxf4g9+cBBA0QNAAQQMEDYIGCBogaICgAYIGQQMEDRA0QNAAQYOgAYIGCBogaICgQdAAQQMEDRA0CBogaICgAYIGCBoEDRA0QNAAQQMEDYIGCBogaICgAYIGQQMEDRA0QNAAQYOgAYIGCBogaICgQdAAQQMEDRA0QNAgaICgAYIGCBogaBA0QNAAQQMEDYIGCBogaICgAYIGQQMEDRA0MCBBWx4y9JjtVtDuHRseZ3SZ6SRqr03ANuPvyccRNboZs+f02arFm/g5V+bkFkn6RdJdkhqMIOhi0CVJP8fN2XYhtwvaZsScBP2upBlJO3jc0UU/SnonI2jbagwx1v7/9caY5BniSypLCiSNSBqVtErSWPxyGL+9nPoWARQRxbdafJuXNCdpVtLfkv6JX67Gb69LatiMeP0Co0YjvtXiOzbOF9MgaCxB0HUn6CTepLtco4efY36OnGhr8ce4w3o9Xs1LHChCnW/NJeHW45jnnRW74XRoO5mhlbE611OrcPKM8uOY2fnAYoJ2O3NHj4URI7VK5w/aWmvjOdr9RCY1ZiTPJD9j3CBsFD234Y4dDSfqrKCVNT8XWaFNfIfusyk9aphU9IAKbgu7o0eyWtczRo5FzdDJsycduefciBlLFXWUOm7LHXPLoOOxw/12YDOCZmVGt1bqKHVbeFuzcaPImcJ02FEqYsPsjCWYpZud0Mt9ptC0iD19okU5AiZoLMUVdVmBy+aINVfQTeImZHT9UlFbMNDCQQPiJ1YAggYIGgQNEDRA0ECX/QvxJNU2Y0X1rQAAAABJRU5ErkJggg=="),
        AWNinePatch(density: 3, width: 180, height: 150, stretchX: 60..<90, stretchY: 42..<84, padding: (54, 42, 57, 66), above: true,
                    png: "iVBORw0KGgoAAAANSUhEUgAAALQAAACWCAYAAAB3qaIPAAAHsElEQVR42u2cX4gdVx3Hv2fm7u7Nvyah+uCfpPnnmw8KKvFNBJ+CRFEICEFKIbRVixixVKTVh0g0QiCiYBDMQ4wRo00FyWNQWpqQ0pbaJ2vSJAuxMS2b3Wx27969M8eHzKxnT87cO7O799/u5wOH2dzMzr05+9nf/M7v/CbGWiuA1ULEFABCAyA0AEIDIDQgNABCAyA0AEIDIDQgNABCAyA0AEIDdKBW9RuMMSb0MlMJK8BDvcy2Yn+zKXO+I3HREbFhJUW2oWMZuWsVRY6yr93RTnCAKkK7R3ekmY8do3aZlMOVN9q6devuTZs2HYvj+PPh7ANgmXZbqyRJLt27d+/7ExMTVwukr5ZyZNF5QeR8bNy48W/1ev2TktIkSXh+C1acOI6NpKjRaLw9PT29L4vQ+bBZkLZLFTqSFDvjX7VazWa/Rcw+dENoGWPUarVqknZLSpyRthO61iHViJwRSxqRNNJqtZpMO3QLJ1BGmXNuXi0nUpcT2lsM5jLXnIsD9IqRwCJRxhgTitK1EotBhIZ+C516wxRF6KhEhcNPOQB6LXTseGiWuvVtAlE6Zn6h12tER2h//2NJvRx+2gGgHrdnxGWiczuhTSBKG5qZQP1poGu3O72kCI3QMChCa7k5tMpeDKBLlHYxqnhRgH4J3ZUGf6SGgZWZJ1aAR7AAEBoAoQEQGhAaAKEBEBoAoQEQGhAaAKEBEBoAoQEQGhAaAKEBEBoAoQEQGhAaAKEBEBoAoQEQGhAaAKEBEBoAoQEQGhAaAKEBEBoAoQEQGhAaAKEBEBoAoQEQGhAaAKEBEBoAoQGhARAaAKEBEBoAoQGhARAaAKEBEBoAoQGhARAaAKEBEBoAoQGhARAaAKEBEBoAoQGhARAaAKEBEBoAoQGhAYaBWtVvsPrUo0wb9IIpJXaz/kmEBlIOgEHFdktoW/XiAF2Q2i5VaBsYKXMLvcLI5M5ZL6Da5URoV2aEhh6GZWsc70plCMbah88xxhhJsR5UQUazUZe03hl1SWOSRrLzYkmGH0OHoPP/OYokmXPacfRr2vLxXn6I05q4dlA3nvfuuv1MKa2kRFJLUjMbDUkzzmhImpM0n52X2IC8nYSOM2FzoeuOzPXs9RHnXIQuJ7TJhI62KN5wQbtO7NWGTb34AC/r/t0v6eq3G0qbgejXb6GTTNhc6IYjcyN7fT4/t6rQkSO0L3Xdidw1R2goFtkXOp+z+NNat+0v2vmLHRod6eaHeEdzzX269sw7mrudSZFmx9I5ahdJCqK0L3MudLoUoaNMWFfqMU9mN90gQpcTOnKErkka+ao27z2l7c89orgrc3hXSfoN3fjJBU294d62HbH7KbT10g5X6jnn6/zv0iKhayUXgy1P2Py1miN+hNClxHYDRR4sWi9q8pUdeu/0MX30YLzC09iU1Y/0n1MXNPWaF+kWCdLnlCN1Rv655r00o+PiMCi0tdZmUTp/I5O9gZvvhGRG6GpC53e+MUnpcd35w06NfuI7+vDelXzTE7rz91/p/XNZtCuMeH0WOiR14sm88BlD0bkw5XDSDuNJGwVERubqQvsLbnd9MnZeO3+zX5u3rcQb/ll3r39d15/ORHbz0aYTpfstdJHUiSfzwudcjtBypPUljgLlKOhc5fCFHnMX3I+qtuWCdp36rNYvq/JxWTNTX9S/D84onc5EnnXEdhdYyQDsBBdt5Lm/bKmTRFQTOiC1aTOE0KrSbhB5df6xbKzLRv0zWr/nT9rxy6VWPq6rOb9f7z71lmavZyI3nOOctzDs96aZ7SD2ogWrbSNtW6EdqRUQ1xSs5KFztcMV2i+JLkh9QFu+cFLbfli18jGlxH5TN184r8lXvVrurJdDu7d0DUCEDv150dF2ELZjP7RzAXehiMjLk7rddu7Cne+PuvuPxzS656f6yIGylY9EVj/We6fPa/Kyk164xzm/njtgjWe2jYNa0Qb/ggvTgVfF5sVpXMubP+OvV36u//5uu0Z3fksf+lyZ6/9a7186rju/9zYlGk5kDubOVaQZ6PldJf+OYZXaL+GFUo91kup/1a7fflmPfKzddV/S5PhX9O4hJ71wx1xRZcOuIglo8O/HPfWBQNYrT+UbCXOBFKH5uG4+86Zm7xdd83XNTj+h8e8Gtox9kZPVKjNCD47UiSd106sbNz5Qa/KQxr93S/Mt/1rjmm89qfHDH6g16f0ihGROVqvMCD1YT2T4Qj8k9RXNXD2sW0fvK10Q8b5S+wPdOnpFM1cDeXMzILTlmULodpT20w83Si+S+qwmLh7R7TOJrBJZHdHtM2c1cbEgzWh6C8B0tS0CWRQOzyKxFtpFzHvQT2rbzyTpkMafDeTefu68KisaCD28lY8xZ7g96PJ6iIty53Q1581azn80A91LP7JN2dQR1W8v8Dsd3Vbe+YKcec3IjNCDL7Uvs9+HrkD/8JqpaCD0cFY+FBA69oR2y37JWqloIPRwRWl5HXB56hB7TwfZQO/wmqhoIPRwS+0+dxcSOtQ/vKZkpsoxPJWPdn3ohf3Ddg3+cBF6uLrz2j0ZVLoJHqFhEKTu1H9ul9I/jNAwSHILiREaRHMSAEIDIDQAQgMgNCA0AEIDIDQAQgNCMwWA0AAIDYDQAJX4H93OtFV1w9LfAAAAAElFTkSuQmCC"),
    ]

    static let errorIcons: [(density: Int, size: Int, png: String)] = [
        (density: 2, size: 40, png: "iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAAFZ0lEQVR42s2ZSWxbVRSGv3vffc927KSJk6a0ZSpjWyizkCqGBQsGsQCVHUIIxKILNixZlhUrWEElkBArBGVRsQCE2LBgFEWtWjGLoaJQiEnj1LH95ntY+L6QhBBiu1Q50tWzLOv6v2f4z7n/U6xhMr1PAdqtAPCAMmDI0xpxd4o0vBqRKjafRqSKUiFKdVBeA6VbVDd9iSl1gQjI3DMHUkBU47BdC4NaBzjjgFUAnzSqE7UvIQnvQex2RK4AqSJMgYyAilB0Qf0JLKC942j9CyMT71EaaQJdBy4CrAMrqnFY1gXQAVOA78BVgYDWzB2kye3k6aNAjf4tQqmT+JXnKNeOUa79CiRA6EBmq4FcDaBeEkqfLN5Md2EnSftprN0NjDGMKX0C7X3C6ORBgpE5YMF5NAHsSpBqFc+VgACx47Sbu4haLyJyqQv3OTR1Gu19wPjWZzB+C2i5HF3mSb0CrOeKocTC7C3EnScQuezcgwOQbdjsATpnbieLx93/GkA7Z/3tQRdWv+c5qdOevZFw4TVghP/fUpQ+wuSFj6LNQuFJ1TicsQStWgTYaV5JEj50nsAB+Ii9iU7zOkQqDodXeFHJ9D7jXLuJpDvN2Zm3XFjXZ57/KtWJQyAJIjmgUMqQJduI2o9g87vXl5JqBm3eZPKiZ11ld4DcLHKd2DJh6xZEdvSX66pDuTbjQpO6/XzCVoBS0fpTUrZgs/vJkhcwQeb2sUWHqDD/+8Mk4YG1yPtfds7dieeBpltnEUkQpL+t5DJaM/tJulsdm5iiU/jk2W2IbO+/GJGCaN1Ke0+xA2Vknu8lau8uOpgBKnTnL8fm9zqa6R9ibxVtS7vP1n3f5252L0kYAR8C0vNgEu0cENz/Y2J3IhIAnqY7v4Msvo+NZCJbWfjzZqCkSeOLEbmQjWZ5dnHPg1lyI2L3bDiANrueuFvXIHVX0mywME+QxXWDyHT/3PePka0Ybr0ln/VQ+4psJkunjSPqYeAVU5Bx1OK4VQ07AQUggXHcNQzC4jowvqzVKRU48AP7EHfqZMhcqRK1t4BMLBsW8nQKkfJQYxgqMSg169AOdto8fZxW4/FzXiRKzWD8PzSoOSDecFWs1Bx+eU7jB0fR+sSGA6jNcYLKvMGUTpFEvwK3DkqpvbuuClckZ3WoqdzzT/UG1pHxkyTRuyTdfQNuNY9fepmJ7a+7cUsBhjOnniJPHxswvL8xNnUUiDWQEVS+dZsPY7EbXMOhmUHp70ClQKaBkJFNP6O9d4bkxHzFGhTcJwSVl4qD6sUp2DOfodRvwzH/4vIHLw7vU8q1bxzp50qm9wVOSZik1biLuPtKn5wYo/Q3aP3T8tKx1yD26j5z7wcmtt+PCZrF/bjonxlKR1TGviAJf0Hkkj62LSH2BnJ7w5DEdwZt3scEhVZjAfEOVHfJ4r3C80NsfhyblRDZfR5ZL6ZU28+mCw6h1FlXcKlqHBbthBpxuZhQq39FUHnDqU7nB5zWn1ObOILWhXaYr6Zu6SVCZYn2mZuIuw+Sp/uHnBfXyrkGpeqTVOvH8Myso6dlMpxZMd4U0izUJr9Gmw6d5p2IvWrFb88FuJNo8y5jm4+4LpS4KC7TCP9NwNROwAzIkinCs7uIOgcc0JEhgX2H9j5mdPPzBJXmEgEzXU3A/Mdd+EB11/I+q72cUrVBGs0Cc4i9wt1h+g17G6W/xy8fpDL6NuXaaVcMhahu1yUB/4eIbrD5KHF7mnDhbsTuwNo9IHWE0d6AoMKe5qf+QNFEm4/xzI/UJj/C87uuQwwuoq/xGqIQ1Uu9p5SJOpPE7WuxdhKxY38DVCnaO4325qjVT6C9ZMlriLif1xB/AWgtXT2FzrSeAAAAAElFTkSuQmCC"),
        (density: 3, size: 60, png: "iVBORw0KGgoAAAANSUhEUgAAADwAAAA8CAYAAAA6/NlyAAADiUlEQVR42uWbb2RVYRzHP+fejDFuxhglYoyl2bEsY1niTuxdyjKWpUhE2ehNRFOiyMaUpkjTbETMIqZsmkbKE2PEZcQYI43LGNfTi+c5Om27O/fenXPuOc/9vjn3xbnnns/9nfN7fv8eS0pJJelAYFe27DqgEzgKNAC1+rNzXANWtx0zwAJSrAR2W75a2LIbgV6gB2jcx5V+Ae+BcaRYjB6wZaeBe0B7AEb5CTxGipflB7bsFuARkA7h9VsCbiPFh/CBLfsIcB/oK4PfmQcGkeJ7OMCW3Q88BarL7HCHgCGkyAUDbNlVwHOgP0KrzAJwASnW/AW27BpgRi8zUVMG6Cp0KfMGtuwUMAe0RDieWANOIUXG68SEB2wSeBNxWIB6YEYbZx/A8BDojknU2AhMaiOV8Ehbdh/w2ocbyQKnCzivBXjhw+89QYrB4oAtuxX4AlT5cAMbSHGwAMfYAXz2ydpX80VmiTzLz6RPsOXSMJZ9qNB3eEBnN3FWjQ55PYBVSnfHkNS3F8tu87LwgP53TNHd/MBqDbtuWIGjW2d0u1r4PJDCPF3JB9yHmerVK48LWOW3nYYC17oLFI6FOzBbZ7YDpw0H3mHhdsOBm3ROTwLLrjYgsvJS0mFMoIriScxXowNcT2Wo3gGuqxDgGgc4WSHAqUJKPCYp5wBvVAhwFlS7NBv4kqBKRgV50TCA10NwFt+IRu2aBKpyn6uAR3pJAUuxpaFNd1gZt5eeNxz4hzZsxQDPsm2o5ZM2e1BByCaw7BHctwTcRAfcnQfL/uhOlH13GFI0s3eH8k+A3vmw0zh3R1rjhj7OU+4pATfwW+C3gcBj7Fq1lCILjBgG+w4plvfqPIyEEGqGqQfs2WqRYmO3k2Kqid1Gm3b2h1XRWgBN+Dt4ctEj3p7z8fc2gGNIsVpoQ7wN1ZyOa4/4ElKMFz7jIcVXYDCmsOP5YPeueEgxCkzELmaGa+xjiueyDjvjIGdAbbN0YJVhnItBcuHAru93TstZqrq2RywR0jxw0r/Rw/+99w1gOEKl3VHgVjETtaWMD6dRY021ZQTd0qDPiv1i8XVpKWaBZmCqTLCLwIlSYP3YApBGzWO2hgC6ghoIf0UENnmcBW6iGs/JACw6pgOKXNS28aQ0dI8+pkp8P2eBaWC6mGn38IF3zlqngeOoZnSrq6nVwL/NWaDqXRlU7XhW5+Yx2KgVA/0F7xwehqPX8nsAAAAASUVORK5CYII="),
    ]

    nonisolated(unsafe) private static var iconBitmap: ABitmap?
    nonisolated(unsafe) private static var iconDensity = 0

    /// indicator_input_error as a bitmap of the closest density bucket, with that bucket's density.
    static func errorIcon() -> (bitmap: ABitmap, density: Int)? {
        if let b = iconBitmap { return (b, iconDensity) }
        let d = AWidgetEnv.density
        guard let entry = errorIcons.min(by: { abs(Float($0.density) - d) < abs(Float($1.density) - d) }),
              let data = Data(base64Encoded: entry.png), let image = UIImage(data: data)?.cgImage else { return nil }
        let b = ABitmap(cgImage: image)
        iconBitmap = b
        iconDensity = entry.density
        return (b, entry.density)
    }
}

/// indicator_input_error (TextView.setError's icon): the framework PNG, 20 dp.
final class AWErrorIconDrawable: ADrawable {
    override var intrinsicWidth: Int {
        guard let icon = AWFrameworkImages.errorIcon() else { return aw_dpx(20) }
        return AWMath.round(Float(icon.bitmap.width) * AWidgetEnv.density / Float(icon.density))
    }

    override var intrinsicHeight: Int {
        guard let icon = AWFrameworkImages.errorIcon() else { return aw_dpx(20) }
        return AWMath.round(Float(icon.bitmap.height) * AWidgetEnv.density / Float(icon.density))
    }

    override func draw(_ canvas: ACanvas) {
        guard let icon = AWFrameworkImages.errorIcon() else { return }
        let b = bounds
        let p = APaint(APaint.FILTER_BITMAP_FLAG)
        p.alpha = alpha
        canvas.drawBitmap(icon.bitmap, nil, ARectF(Float(b.left), Float(b.top), Float(b.right), Float(b.bottom)), p)
    }
}

// MARK: - edit_text_material

/// edit_text_material: InsetDrawable(4, 10, 4, 7 dp) around a selector of the textfield nine-patches
/// (textfield_default_mtrl_alpha: a 1 dp line 1 dp above the bottom, tinted ?colorControlNormal; when focused or
/// pressed textfield_activated_mtrl_alpha: a 2 dp line at the bottom, tinted ?colorControlActivated; disabled: the
/// default image with colorControlNormal's disabled colour). Padding = the nine-patch's 4 dp bottom padding plus the
/// insets. A background tint list (View.setBackgroundTintList) replaces the selector's tints (SRC_IN).
final class AWEditTextBackground: ADrawable {
    private var aw_tintList: AColorStateList?
    private var aw_hasTint = false
    private let aw_paint = APaint(APaint.ANTI_ALIAS_FLAG)

    override var isStateful: Bool { return true }
    override func onStateChange(_ state: [Int]) -> Bool { return true }

    override func setTintList(_ l: AColorStateList?) {
        aw_tintList = l
        aw_hasTint = true
        invalidateSelf()
    }

    override func getPadding(_ r: ARect) -> Bool {
        r.set(aw_dpx(4), aw_dpx(10), aw_dpx(4), aw_dpx(7) + aw_dpx(4))
        return true
    }

    override func draw(_ canvas: ACanvas) {
        let b = bounds
        let left = b.left + aw_dpx(4), right = b.right - aw_dpx(4)
        let bottom = b.bottom - aw_dpx(7)
        if right <= left { return }
        let s = state
        let enabled = s.contains(AStateSet.state_enabled)
        let activated = enabled && (s.contains(AStateSet.state_pressed) || s.contains(AStateSet.state_focused))
        var color: Int
        if activated {
            color = AWMaterialColors.colorControlActivated
        } else {
            color = AWMaterialColors.colorControlNormalList.getColorForState(s, AWMaterialColors.colorControlNormal)
        }
        if aw_hasTint {
            guard let t = aw_tintList else {
                // A null tint list leaves the white alpha mask untinted.
                color = AColor.WHITE
                aw_drawLine(canvas, left, right, bottom, activated, color)
                return
            }
            color = t.getColorForState(s, t.defaultColor)
        }
        aw_drawLine(canvas, left, right, bottom, activated, color)
    }

    private func aw_drawLine(_ canvas: ACanvas, _ left: Int, _ right: Int, _ bottom: Int, _ activated: Bool, _ color: Int) {
        aw_paint.style = .FILL
        aw_paint.color = color
        aw_paint.alpha = AColor.alpha(color) * alpha / 255
        if activated {
            canvas.drawRect(Float(left), Float(bottom - aw_dpx(2)), Float(right), Float(bottom), aw_paint)
        } else {
            canvas.drawRect(Float(left), Float(bottom - aw_dpx(2)), Float(right), Float(bottom - aw_dpx(1)), aw_paint)
        }
    }
}

// MARK: - The UIKit editors

/// The single-line editor: UIKit draws the typed text and the caret in `aw_textBox` (pt, the field's own bounds),
/// whose first baseline is the Android baseline.
final class AWTextField: UITextField {
    var aw_textBox: CGRect = .zero

    override func textRect(forBounds bounds: CGRect) -> CGRect { return aw_textBox.isEmpty ? bounds : aw_textBox }
    override func editingRect(forBounds bounds: CGRect) -> CGRect { return aw_textBox.isEmpty ? bounds : aw_textBox }
    override func placeholderRect(forBounds bounds: CGRect) -> CGRect { return aw_textBox.isEmpty ? bounds : aw_textBox }
}

/// The multi-line editor (TYPE_TEXT_FLAG_MULTI_LINE without single line).
final class AWTextArea: UITextView {}

/// Keyboard frame tracking for the error popup's display frame (the window minus the soft input).
final class AWKeyboardTracker {
    static let shared = AWKeyboardTracker()
    private(set) var frameInScreen: CGRect?
    private var observers: [NSObjectProtocol] = []

    private init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification, object: nil,
                                            queue: .main) { note in
            let frame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
            AWKeyboardTracker.shared.frameInScreen = frame
        })
        observers.append(center.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil,
                                            queue: .main) { _ in
            AWKeyboardTracker.shared.frameInScreen = nil
        })
    }

    static func start() { _ = shared }
}

// MARK: - TextView error popup (Editor.ErrorPopup)

/// Editor.ErrorPopup: a PopupWindow showing a TextView (layout textview_hint: ?textAppearanceSmall 14 sp,
/// ?textColorPrimaryInverse white) on the error background nine-patch, below the error icon (or above the field,
/// with the "above" background, when it does not fit below in the window's visible frame).
final class AWErrorPopupView: UIView {
    let text: String
    private(set) var above = false
    private let paint = APaint(APaint.ANTI_ALIAS_FLAG)
    private var textLayout: ALayout?
    private var widthPx = 0
    private var heightPx = 0

    init(_ text: String) {
        self.text = text
        super.init(frame: .zero)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        contentScaleFactor = CGFloat(AWidgetEnv.density)
        paint.textSize = Float(ATypedValue.toDimensionPixelSize(ATypedValue.COMPLEX_UNIT_SP, 14))
        paint.typeface = ATypeface.create("sans", ATypeface.NORMAL)
        paint.color = AColor.WHITE
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private var background: AWNinePatch { return AWNinePatch.select(AWFrameworkImages.errorPopups, above: above) }

    /// Editor.chooseSize: a StaticLayout of the error at textview_error_popup_default_width (240 dp); the popup is the
    /// widest line plus the background padding wide and the layout plus the padding tall.
    func chooseSize() -> (width: Int, height: Int) {
        let pad = background.paddingPx()
        let defaultWidthInPixels = aw_dpx(240)
        let l = ALayout(text: text, paint: paint, width: defaultWidthInPixels, alignment: .ALIGN_NORMAL,
                        textDir: .FIRSTSTRONG_LTR, spacingMult: 1, spacingAdd: 0, includePad: true, ellipsize: nil,
                        ellipsizedWidth: defaultWidthInPixels, maxLines: Int(Int32.max),
                        breakStrategy: ALayout.BREAK_STRATEGY_HIGH_QUALITY)
        var maxW: Float = 0
        for i in 0..<l.lineCount { maxW = Swift.max(maxW, l.getLineWidth(i)) }
        widthPx = pad.left + pad.right + AWMath.ceil(maxW)
        heightPx = pad.top + pad.bottom + l.getHeight()
        textLayout = nil
        return (widthPx, heightPx)
    }

    /// ErrorPopup.fixDirection.
    func fixDirection(_ above: Bool) {
        if self.above != above {
            self.above = above
            textLayout = nil
            _ = chooseSize()
        }
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let d = CGFloat(AWidgetEnv.density)
        ctx.saveGState()
        ctx.scaleBy(x: 1 / d, y: 1 / d)
        let canvas = ACanvas(ctx, widthPx, heightPx)
        let bg = background
        bg.draw(canvas, ARect(0, 0, widthPx, heightPx), APaint(APaint.FILTER_BITMAP_FLAG))
        let pad = bg.paddingPx()
        let innerWidth = Swift.max(widthPx - pad.left - pad.right, 0)
        if textLayout == nil {
            textLayout = ALayout(text: text, paint: paint, width: innerWidth, alignment: .ALIGN_NORMAL,
                                 textDir: .FIRSTSTRONG_LTR, spacingMult: 1, spacingAdd: 0, includePad: true, ellipsize: nil,
                                 ellipsizedWidth: innerWidth, maxLines: Int(Int32.max),
                                 breakStrategy: ALayout.BREAK_STRATEGY_HIGH_QUALITY)
        }
        canvas.save()
        canvas.translate(Float(pad.left), Float(pad.top))
        textLayout?.draw(canvas)
        canvas.restore()
        ctx.restoreGState()
    }
}

// MARK: - android.widget.EditText

/// android.widget.EditText (also AppCompatEditText). A framework `new EditText(context)` under Theme.TripleShot.
class AEditText: ATextView, UITextFieldDelegate, UITextViewDelegate {
    // Editor input state (Editor.mInputType, mInputContentType)
    private(set) var aw_inputType = AInputType.TYPE_CLASS_TEXT
    private var aw_imeOptions = AEditorInfo.IME_NULL
    /// Editor.mInputContentType != null (setImeOptions / setOnEditorActionListener were called).
    private var aw_hasInputContentType = false
    private var aw_onEditorActionListener: ((ATextView, Int, AnyObject?) -> Bool)?
    /// The key listener's InputFilter (DigitsKeyListener for number fields), appended to the Editable's filters.
    private var aw_keyListenerFilter: AInputFilter?

    // Editor error state
    private(set) var aw_error: String?
    private var aw_errorWasChanged = false
    private var aw_showErrorAfterAttach = false
    private var aw_errorPopup: AWErrorPopupView?
    private var aw_errorPopupListener: AOnPreDrawListener?

    // UIKit editor
    private var aw_field: AWTextField?
    private var aw_area: AWTextArea?
    private var aw_syncing = false
    private var aw_pendingEdit: (start: Int, before: Int, after: Int, beforeSent: Bool)?
    private var aw_hideKeyboardKeepsFocus = false
    private var aw_focusFromEditor = false
    /// The caret colour (?colorControlActivated of the view's theme; TextInputLayout tints it with its own).
    var aw_cursorColor: Int = AWMaterialColors.colorControlActivated

    /// The editor that shows the soft keyboard (focus moving between fields keeps the keyboard up, like the IME).
    nonisolated(unsafe) private static weak var aw_keyboardOwner: AEditText?

    override init() {
        super.init()
        aw_configureEditText()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The style defaults (Widget.Material.Light.EditText) and the editable-text setup of the TextView constructor.
    func aw_configureEditText() {
        aw_drawsOwnText = false
        aw_breakStrategy = ALayout.BREAK_STRATEGY_SIMPLE
        aw_hyphenationFrequency = ALayout.HYPHENATION_FREQUENCY_NONE
        applyXmlTextSize(18)
        setTextColor(AWMaterialColors.textColorPrimary)
        setHintTextColor(AColorStateList.valueOf(AWMaterialColors.textColorHint))
        setGravity(AGravity.CENTER_VERTICAL)
        setBackgroundDrawable(AWEditTextBackground())
        isFocusable = true
        isFocusableInTouchMode = true
        isClickable = true
        isLongClickable = true
        // Editable text: TYPE_CLASS_TEXT; not single line -> TYPE_TEXT_FLAG_MULTI_LINE (setInputTypeSingleLine(false)).
        aw_inputType = AInputType.TYPE_CLASS_TEXT
        aw_setInputTypeSingleLine(false)
        aw_applySingleLine(false, applyTransformation: false, changeMaxLines: false, changeMaxLength: false)
        aw_ensureEditor()
        AWKeyboardTracker.start()
    }

    override var aw_isEditable: Bool { return true }

    // MARK: Text (EditText.getText / setText)

    /// TextView.setText on editable text: the movement method puts the selection at 0.
    override func aw_textDidChange() {
        aw_pushTextToEditor()
        aw_setEditorSelection(0, 0)
    }

    /// EditText.setSelection(index).
    func setSelection(_ index: Int) {
        setSelection(index, index)
    }

    /// EditText.setSelection(start, stop): IndexOutOfBoundsException outside the text.
    func setSelection(_ start: Int, _ stop: Int) {
        let length = aw_text.aw_plain.utf16.count
        precondition(start >= 0 && start <= length && stop >= 0 && stop <= length,
                     "java.lang.IndexOutOfBoundsException: setSpan (\(start) ... \(stop)) ends beyond length \(length)")
        aw_setEditorSelection(start, stop)
    }

    /// EditText.selectAll.
    func selectAll() {
        setSelection(0, aw_text.aw_plain.utf16.count)
    }

    var selectionStart: Int { return aw_editorSelection().start }
    var selectionEnd: Int { return aw_editorSelection().end }
    func getSelectionStart() -> Int { return selectionStart }
    func getSelectionEnd() -> Int { return selectionEnd }

    private func aw_editorSelection() -> (start: Int, end: Int) {
        if let f = aw_field, let r = f.selectedTextRange {
            return (f.offset(from: f.beginningOfDocument, to: r.start), f.offset(from: f.beginningOfDocument, to: r.end))
        }
        if let a = aw_area {
            let r = a.selectedRange
            return (r.location, r.location + r.length)
        }
        return (-1, -1)
    }

    private func aw_setEditorSelection(_ start: Int, _ stop: Int) {
        if let f = aw_field, let a = f.position(from: f.beginningOfDocument, offset: start),
           let b = f.position(from: f.beginningOfDocument, offset: stop) {
            f.selectedTextRange = f.textRange(from: a, to: b)
        }
        if let t = aw_area {
            t.selectedRange = NSRange(location: Swift.min(start, stop), length: abs(stop - start))
        }
    }

    // MARK: Input type, IME options, editor action (TextView)

    var inputType: Int {
        get { return getInputType() }
        set { setInputType(newValue) }
    }

    func getInputType() -> Int { return aw_inputType }

    private static func isPasswordInputType(_ inputType: Int) -> Bool {
        let variation = inputType & (AInputType.TYPE_MASK_CLASS | AInputType.TYPE_MASK_VARIATION)
        return variation == (AInputType.TYPE_CLASS_TEXT | AInputType.TYPE_TEXT_VARIATION_PASSWORD)
            || variation == (AInputType.TYPE_CLASS_TEXT | AInputType.TYPE_TEXT_VARIATION_WEB_PASSWORD)
            || variation == (AInputType.TYPE_CLASS_NUMBER | AInputType.TYPE_NUMBER_VARIATION_PASSWORD)
    }

    private static func isVisiblePasswordInputType(_ inputType: Int) -> Bool {
        let variation = inputType & (AInputType.TYPE_MASK_CLASS | AInputType.TYPE_MASK_VARIATION)
        return variation == (AInputType.TYPE_CLASS_TEXT | AInputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD)
    }

    private static func isMultilineInputType(_ type: Int) -> Bool {
        return (type & (AInputType.TYPE_MASK_CLASS | AInputType.TYPE_TEXT_FLAG_MULTI_LINE))
            == (AInputType.TYPE_CLASS_TEXT | AInputType.TYPE_TEXT_FLAG_MULTI_LINE)
    }

    /// TextView.setInputType: the key listener of the class, password transformation and monospace typeface, and
    /// single-line mode from the multi-line flag.
    func setInputType(_ type: Int) {
        let wasPassword = AEditText.isPasswordInputType(getInputType())
        let wasVisiblePassword = AEditText.isVisiblePasswordInputType(getInputType())
        aw_setInputTypeInternal(type)
        let isPassword = AEditText.isPasswordInputType(type)
        let isVisiblePassword = AEditText.isVisiblePasswordInputType(type)
        var forceUpdate = false
        if isPassword {
            aw_setTransformation(.PASSWORD)
            setTypeface(ATypeface.MONOSPACE)
        } else if isVisiblePassword {
            if aw_transformation == .PASSWORD { forceUpdate = true }
            setTypeface(ATypeface.MONOSPACE)
        } else if wasPassword || wasVisiblePassword {
            setTypeface(ATypeface.DEFAULT)
            if aw_transformation == .PASSWORD { forceUpdate = true }
        }
        let singleLine = !AEditText.isMultilineInputType(type)
        if isSingleLine != singleLine || forceUpdate {
            aw_applySingleLine(singleLine, applyTransformation: !isPassword, changeMaxLines: true, changeMaxLength: true)
        }
        aw_syncKeyboard()
    }

    /// TextView.setInputType(type, direct): the key listener (and its filter) of the input class.
    private func aw_setInputTypeInternal(_ type: Int) {
        let cls = type & AInputType.TYPE_MASK_CLASS
        if cls == AInputType.TYPE_CLASS_NUMBER {
            aw_keyListenerFilter = AWDigitsKeyFilter((type & AInputType.TYPE_NUMBER_FLAG_SIGNED) != 0,
                                                     (type & AInputType.TYPE_NUMBER_FLAG_DECIMAL) != 0)
        } else {
            aw_keyListenerFilter = nil
        }
        aw_inputType = type
    }

    /// TextView.setRawInputType.
    func setRawInputType(_ type: Int) {
        aw_inputType = type
        aw_syncKeyboard()
    }

    /// TextView.setInputTypeSingleLine.
    override func aw_setInputTypeSingleLine(_ singleLine: Bool) {
        if (aw_inputType & AInputType.TYPE_MASK_CLASS) == AInputType.TYPE_CLASS_TEXT {
            if singleLine {
                aw_inputType &= ~AInputType.TYPE_TEXT_FLAG_MULTI_LINE
            } else {
                aw_inputType |= AInputType.TYPE_TEXT_FLAG_MULTI_LINE
            }
        }
    }

    override func aw_singleLineDidChange() {
        aw_ensureEditor()
        aw_syncKeyboard()
    }

    var imeOptions: Int {
        get { return getImeOptions() }
        set { setImeOptions(newValue) }
    }

    func getImeOptions() -> Int { return aw_hasInputContentType ? aw_imeOptions : AEditorInfo.IME_NULL }

    /// TextView.setImeOptions (creates the input content type).
    func setImeOptions(_ imeOptions: Int) {
        aw_hasInputContentType = true
        aw_imeOptions = imeOptions
        aw_syncKeyboard()
    }

    /// TextView.setOnEditorActionListener((v, actionId, event) -> handled).
    func setOnEditorActionListener(_ l: ((ATextView, Int, AnyObject?) -> Bool)?) {
        aw_hasInputContentType = true
        aw_onEditorActionListener = l
    }

    /// TextView.onEditorAction: the listener, then the default handling of NEXT / PREVIOUS / DONE when explicit IME
    /// options exist; otherwise the IME's Enter key (a single-line field moves focus down or hides the keyboard).
    func onEditorAction(_ actionCode: Int) {
        if aw_hasInputContentType {
            if let l = aw_onEditorActionListener, l(self, actionCode, nil) {
                return
            }
            if actionCode == AEditorInfo.IME_ACTION_NEXT {
                if let v = aw_focusSearch(AView.FOCUS_FORWARD) {
                    precondition(v.aw_requestFocusFromIme(), "java.lang.IllegalStateException: focus search returned a view that wasn't able to take focus!")
                }
                return
            } else if actionCode == AEditorInfo.IME_ACTION_PREVIOUS {
                if let v = aw_focusSearch(AView.FOCUS_BACKWARD) {
                    precondition(v.aw_requestFocusFromIme(), "java.lang.IllegalStateException: focus search returned a view that wasn't able to take focus!")
                }
                return
            } else if actionCode == AEditorInfo.IME_ACTION_DONE {
                aw_hideSoftInput()
                return
            }
        }
        // KEYCODE_ENTER with FLAG_EDITOR_ACTION (TextView.onKeyUp): a single-line field moves the focus down, or hides
        // the IME when there is nothing below; a multi-line field inserts the newline itself (UIKit).
        if isSingleLine {
            if let v = aw_focusSearch(AView.FOCUS_DOWN) {
                precondition(v.aw_requestFocusFromIme(), "java.lang.IllegalStateException: focus search returned a view that wasn't able to take focus!")
            } else {
                aw_hideSoftInput()
            }
        }
    }

    /// The action of the IME's action key (TextView.onCreateInputConnection: an unspecified action becomes NEXT when
    /// the focus can move down, DONE otherwise).
    func aw_imeActionId() -> Int {
        var action = (aw_hasInputContentType ? aw_imeOptions : AEditorInfo.IME_NULL) & AEditorInfo.IME_MASK_ACTION
        if isSingleLine && action == AEditorInfo.IME_ACTION_UNSPECIFIED {
            action = aw_focusSearch(AView.FOCUS_DOWN) != nil ? AEditorInfo.IME_ACTION_NEXT : AEditorInfo.IME_ACTION_DONE
        }
        return action
    }

    /// FocusFinder.findNextFocus in touch mode: the focusable-in-touch-mode editors of this window, FORWARD / BACKWARD
    /// in focus order, UP / DOWN by FocusFinder's beam and weighted-distance rules.
    func aw_focusSearch(_ direction: Int) -> AEditText? {
        var all: [AEditText] = []
        func collect(_ v: AView) {
            if v.visibility != AView.VISIBLE { return }
            if let e = v as? AEditText, e !== self, e.isEnabled, e.isFocusable, e.isFocusableInTouchMode, e.isShown {
                all.append(e)
            }
            if let g = v as? AViewGroup { for c in g.children { collect(c) } }
        }
        collect(rootView)
        if direction == AView.FOCUS_FORWARD || direction == AView.FOCUS_BACKWARD {
            var ordered: [AEditText] = []
            func order(_ v: AView) {
                if v.visibility != AView.VISIBLE { return }
                if let e = v as? AEditText, e === self || all.contains(where: { $0 === e }) { ordered.append(e) }
                if let g = v as? AViewGroup { for c in g.children { order(c) } }
            }
            order(rootView)
            guard let i = ordered.firstIndex(where: { $0 === self }) else { return nil }
            if direction == AView.FOCUS_FORWARD { return i + 1 < ordered.count ? ordered[i + 1] : nil }
            return i > 0 ? ordered[i - 1] : nil
        }
        let src = aw_windowRect(self)
        var best: AEditText?
        var bestRect: ARect?
        for e in all {
            let r = aw_windowRect(e)
            guard AEditText.isCandidate(src, r, direction) else { continue }
            if bestRect == nil || AEditText.isBetterCandidate(direction, src, r, bestRect!) {
                best = e
                bestRect = r
            }
        }
        return best
    }

    private func aw_windowRect(_ v: AView) -> ARect {
        var loc = [0, 0]
        v.getLocationInWindow(&loc)
        return ARect(loc[0], loc[1], loc[0] + v.width, loc[1] + v.height)
    }

    /// FocusFinder.isCandidate (UP / DOWN).
    private static func isCandidate(_ src: ARect, _ dest: ARect, _ direction: Int) -> Bool {
        if direction == AView.FOCUS_DOWN {
            return (src.top < dest.top || src.bottom <= dest.top) && src.bottom < dest.bottom
        }
        return (src.bottom > dest.bottom || src.top >= dest.bottom) && src.top > dest.top
    }

    /// FocusFinder.beamsOverlap (vertical directions: horizontal overlap).
    private static func beamsOverlap(_ r1: ARect, _ r2: ARect) -> Bool {
        return r2.right > r1.left && r2.left < r1.right
    }

    private static func majorAxisDistance(_ direction: Int, _ source: ARect, _ dest: ARect) -> Int {
        return Swift.max(0, direction == AView.FOCUS_DOWN ? dest.top - source.bottom : source.top - dest.bottom)
    }

    private static func minorAxisDistance(_ source: ARect, _ dest: ARect) -> Int {
        return abs((source.left + source.width() / 2) - (dest.left + dest.width() / 2))
    }

    /// FocusFinder.isBetterCandidate (beam first, then 13 * major^2 + minor^2).
    private static func isBetterCandidate(_ direction: Int, _ source: ARect, _ rect1: ARect, _ rect2: ARect) -> Bool {
        let b1 = beamsOverlap(source, rect1), b2 = beamsOverlap(source, rect2)
        if b1 && !b2 { return true }
        if b2 && !b1 { return false }
        let d1 = majorAxisDistance(direction, source, rect1), d2 = majorAxisDistance(direction, source, rect2)
        let m1 = minorAxisDistance(source, rect1), m2 = minorAxisDistance(source, rect2)
        return 13 * d1 * d1 + m1 * m1 < 13 * d2 * d2 + m2 * m2
    }

    /// InputMethodManager.hideSoftInputFromWindow: the keyboard goes away, the field keeps its (Android) focus.
    private func aw_hideSoftInput() {
        aw_hideKeyboardKeepsFocus = true
        aw_field?.resignFirstResponder()
        aw_area?.resignFirstResponder()
        aw_hideKeyboardKeepsFocus = false
        if AEditText.aw_keyboardOwner === self { AEditText.aw_keyboardOwner = nil }
    }

    // MARK: Filters

    override func aw_filtersDidChange() {}

    /// The Editable's filters: the TextView's, then the key listener's (TextView.setFilters(Editable, filters)).
    private var aw_editableFilters: [AInputFilter] {
        if let k = aw_keyListenerFilter { return aw_filters + [k] }
        return aw_filters
    }

    // MARK: Error (TextView.setError / Editor.setError)

    var error: String? {
        get { return getError() }
        set { setError(newValue) }
    }

    func getError() -> String? { return aw_error }

    /// TextView.setError(CharSequence): the indicator_input_error icon at its intrinsic size.
    func setError(_ error: String?) {
        if error == nil {
            setError(nil, nil)
        } else {
            let dr = AWErrorIconDrawable()
            dr.setBounds(0, 0, dr.intrinsicWidth, dr.intrinsicHeight)
            setError(error, dr)
        }
    }

    /// TextView.setError(CharSequence, Drawable) -> Editor.setError.
    func setError(_ error: String?, _ icon: ADrawable?) {
        aw_error = error
        aw_errorWasChanged = true
        if aw_error == nil {
            aw_setErrorIcon(nil)
            aw_dismissErrorPopup()
            aw_showErrorAfterAttach = false
        } else {
            aw_setErrorIcon(icon)
            if isFocusedSelf {
                aw_showError()
            }
        }
    }

    /// Editor.setErrorIcon -> Drawables.setErrorDrawable: the icon takes the end drawable's place.
    private func aw_setErrorIcon(_ icon: ADrawable?) {
        if let old = aw_errorDrawable, old !== icon { old.callbackView = nil }
        aw_errorDrawable = icon
        if let icon = icon {
            if icon.isStateful { _ = icon.setState(drawableState) }
            icon.callbackView = self
        }
        aw_layoutEditor()
        invalidate()
        requestLayout()
    }

    /// Editor.hideErrorIfUnchanged (sendAfterTextChanged).
    private func aw_hideErrorIfUnchanged() {
        if aw_error != nil && !aw_errorWasChanged {
            setError(nil, nil)
        }
    }

    override func aw_sendAfterTextChanged(_ s: String) {
        super.aw_sendAfterTextChanged(s)
        aw_hideErrorIfUnchanged()
    }

    /// Editor.showError.
    private func aw_showError() {
        guard isAttachedToWindow, window != nil else {
            aw_showErrorAfterAttach = true
            return
        }
        guard let message = aw_error else { return }
        if aw_errorPopup == nil || aw_errorPopup!.text != message {
            aw_errorPopup?.removeFromSuperview()
            aw_errorPopup = AWErrorPopupView(message)
        }
        aw_positionErrorPopup()
        if aw_errorPopupListener == nil {
            let l = AOnPreDrawListener { [weak self] in
                self?.aw_positionErrorPopup()
                return true
            }
            aw_errorPopupListener = l
            viewTreeObserver.addOnPreDrawListener(l)
        }
    }

    private func aw_dismissErrorPopup() {
        aw_errorPopup?.removeFromSuperview()
        aw_errorPopup = nil
        if let l = aw_errorPopupListener {
            viewTreeObserver.removeOnPreDrawListener(l)
            aw_errorPopupListener = nil
        }
    }

    /// PopupWindow.showAsDropDown(this, getErrorX(), getErrorY(), TOP | LEFT) with findDropDownPosition /
    /// tryFitVertical, then ErrorPopup.fixDirection(isAboveAnchor).
    private func aw_positionErrorPopup() {
        guard let popup = aw_errorPopup, let win = window else { return }
        let d = CGFloat(AWidgetEnv.density)
        var size = popup.chooseSize()
        let iconW = aw_errorDrawable?.bounds.width() ?? 0
        let iconH = aw_errorDrawable?.bounds.height() ?? 0
        // getErrorX: the background's point is 25 dp from its right edge, centred on the icon.
        let errorX: Int
        if isLayoutRtl {
            let offset = iconW / 2 - AWMath.javaInt(25 * AWidgetEnv.density + 0.5)
            errorX = paddingLeft + offset
        } else {
            let offset = -iconW / 2 + AWMath.javaInt(25 * AWidgetEnv.density + 0.5)
            errorX = width - size.width - paddingRight + offset
        }
        // getErrorY: the point is 2 dp below the background's top edge, at the icon's bottom.
        let cpt = compoundPaddingTop
        let vspace = height - compoundPaddingBottom - cpt
        let icontop = cpt + (vspace - iconH) / 2
        let errorY = icontop + iconH - height - AWMath.javaInt(2 * AWidgetEnv.density + 0.5)
        var loc = [0, 0]
        getLocationInWindow(&loc)
        let x = loc[0] + errorX
        var y = loc[1] + height + errorY
        // The window's visible display frame (without the soft keyboard).
        var displayBottom = Int(win.bounds.height * d)
        if let kb = AWKeyboardTracker.shared.frameInScreen {
            let kbInWindow = win.convert(kb, from: nil)
            if kbInWindow.minY < win.bounds.height { displayBottom = Int(kbInWindow.minY * d) }
        }
        let displayTop = Int(win.safeAreaInsets.top * d)
        var isAbove = false
        if !(y >= displayTop && size.height <= displayBottom - y) {
            let spaceAbove = y - height - displayTop
            if size.height <= spaceAbove {
                isAbove = true
            }
        }
        popup.fixDirection(isAbove)
        size = popup.chooseSize()
        if isAbove {
            y = loc[1] - size.height + errorY
        }
        if popup.superview !== win { win.addSubview(popup) }
        popup.frame = CGRect(x: CGFloat(x) / d, y: CGFloat(y) / d, width: CGFloat(size.width) / d, height: CGFloat(size.height) / d)
        popup.setNeedsDisplay()
        win.bringSubviewToFront(popup)
    }

    // MARK: Focus (Editor.onFocusChanged)

    override func onFocusChanged(_ gainFocus: Bool, _ direction: Int, _ previouslyFocusedRect: ARect?) {
        super.onFocusChanged(gainFocus, direction, previouslyFocusedRect)
        if gainFocus {
            if aw_error != nil { aw_showError() }
            // A programmatic focus move keeps the soft keyboard on the focused editor (when it is up).
            if !aw_focusFromEditor, let owner = AEditText.aw_keyboardOwner, owner !== self, owner.aw_editorIsFirstResponder {
                aw_becomeFirstResponder()
            }
        } else {
            aw_dismissErrorPopup()
            if aw_editorIsFirstResponder {
                aw_hideKeyboardKeepsFocus = true
                aw_field?.resignFirstResponder()
                aw_area?.resignFirstResponder()
                aw_hideKeyboardKeepsFocus = false
            }
        }
        invalidate()
    }

    /// requestFocus for an IME focus move: the keyboard follows the focus.
    fileprivate func aw_requestFocusFromIme() -> Bool {
        let ok = requestFocus()
        if ok { aw_becomeFirstResponder() }
        return ok
    }

    private var aw_editorIsFirstResponder: Bool {
        return (aw_field?.isFirstResponder ?? false) || (aw_area?.isFirstResponder ?? false)
    }

    private func aw_becomeFirstResponder() {
        if let f = aw_field { _ = f.becomeFirstResponder() }
        if let a = aw_area { _ = a.becomeFirstResponder() }
    }

    override func setEnabled(_ enabled: Bool) {
        super.setEnabled(enabled)
        aw_field?.isEnabled = enabled
        aw_area?.isEditable = enabled
        if !enabled && aw_editorIsFirstResponder { aw_hideSoftInput() }
        aw_syncColors()
    }

    override func onAttachedToWindow() {
        super.onAttachedToWindow()
        if aw_showErrorAfterAttach {
            aw_showErrorAfterAttach = false
            post { [weak self] in
                guard let self = self, self.aw_error != nil, self.isFocusedSelf else { return }
                self.aw_showError()
            }
        }
    }

    override func onDetachedFromWindow() {
        super.onDetachedFromWindow()
        if aw_errorPopup != nil {
            aw_dismissErrorPopup()
            if aw_error != nil { aw_showErrorAfterAttach = true }
        }
        if aw_editorIsFirstResponder {
            aw_hideSoftInput()
        }
    }

    // MARK: The UIKit editor

    /// Creates (or swaps) the UIKit editor for the current mode: UITextField when single line, UITextView otherwise.
    private func aw_ensureEditor() {
        if isSingleLine {
            if let a = aw_area {
                a.delegate = nil
                a.removeFromSuperview()
                aw_area = nil
            }
            if aw_field == nil {
                let f = AWTextField()
                f.borderStyle = .none
                f.backgroundColor = .clear
                f.contentVerticalAlignment = .top
                f.clearButtonMode = .never
                f.delegate = self
                f.addTarget(self, action: #selector(aw_editorEditingChanged), for: .editingChanged)
                f.isEnabled = isEnabled
                addSubview(f)
                aw_field = f
            }
        } else {
            if let f = aw_field {
                f.delegate = nil
                f.removeFromSuperview()
                aw_field = nil
            }
            if aw_area == nil {
                let a = AWTextArea()
                a.backgroundColor = .clear
                a.textContainerInset = .zero
                a.textContainer.lineFragmentPadding = 0
                a.isScrollEnabled = true
                a.delegate = self
                a.isEditable = isEnabled
                addSubview(a)
                aw_area = a
            }
        }
        aw_pushTextToEditor()
        aw_syncFont()
        aw_syncColors()
        aw_syncKeyboard()
        aw_layoutEditor()
    }

    private func aw_pushTextToEditor() {
        aw_syncing = true
        let s = aw_transformation == .PASSWORD ? aw_text.aw_plain : aw_transformed.aw_plain
        if let f = aw_field, f.text != s { f.text = s }
        if let a = aw_area, a.text != s { a.text = s }
        aw_syncing = false
        aw_syncAlignment()
    }

    override func aw_hintDidChange() {
        invalidate()
    }

    override func aw_styleDidChange() {
        aw_syncFont()
        aw_syncAlignment()
        aw_layoutEditor()
    }

    override func aw_colorsDidChange() {
        aw_syncColors()
    }

    override func aw_paddingDidChange() {
        aw_layoutEditor()
    }

    override func aw_layoutDidChange() {
        aw_layoutEditor()
    }

    /// The UIKit font of the paint, with the letter spacing as kerning.
    private func aw_syncFont() {
        let font = paint.uiFont()
        let kern = CGFloat(paint.letterSpacing * paint.textSize / AWidgetEnv.density)
        if let f = aw_field {
            f.font = font
            var attrs = f.defaultTextAttributes
            attrs[.font] = font
            attrs[.kern] = kern
            attrs[.foregroundColor] = AColor.uiColor(currentTextColor)
            f.defaultTextAttributes = attrs
        }
        if let a = aw_area {
            a.font = font
            var attrs = a.typingAttributes
            attrs[.font] = font
            attrs[.kern] = kern
            a.typingAttributes = attrs
        }
    }

    private func aw_syncColors() {
        let color = AColor.uiColor(currentTextColor)
        if let f = aw_field {
            f.textColor = color
            var attrs = f.defaultTextAttributes
            attrs[.foregroundColor] = color
            f.defaultTextAttributes = attrs
            f.tintColor = AColor.uiColor(aw_cursorColor)
        }
        if let a = aw_area {
            a.textColor = color
            a.tintColor = AColor.uiColor(aw_cursorColor)
        }
    }

    /// The keyboard of the input type (InputMethodManager / EditorInfo -> UITextInputTraits).
    private func aw_syncKeyboard() {
        let cls = aw_inputType & AInputType.TYPE_MASK_CLASS
        let variation = aw_inputType & AInputType.TYPE_MASK_VARIATION
        let flags = aw_inputType & AInputType.TYPE_MASK_FLAGS
        var keyboard: UIKeyboardType = .default
        var caps: UITextAutocapitalizationType = .none
        var correction: UITextAutocorrectionType = .no
        var secure = false
        switch cls {
        case AInputType.TYPE_CLASS_NUMBER:
            if (flags & AInputType.TYPE_NUMBER_FLAG_DECIMAL) != 0 {
                keyboard = (flags & AInputType.TYPE_NUMBER_FLAG_SIGNED) != 0 ? .numbersAndPunctuation : .decimalPad
            } else {
                keyboard = (flags & AInputType.TYPE_NUMBER_FLAG_SIGNED) != 0 ? .numbersAndPunctuation : .asciiCapableNumberPad
            }
            secure = variation == AInputType.TYPE_NUMBER_VARIATION_PASSWORD
        case AInputType.TYPE_CLASS_PHONE:
            keyboard = .phonePad
        case AInputType.TYPE_CLASS_DATETIME:
            keyboard = .numbersAndPunctuation
        default:
            if (flags & AInputType.TYPE_TEXT_FLAG_CAP_CHARACTERS) != 0 {
                caps = .allCharacters
            } else if (flags & AInputType.TYPE_TEXT_FLAG_CAP_WORDS) != 0 {
                caps = .words
            } else if (flags & AInputType.TYPE_TEXT_FLAG_CAP_SENTENCES) != 0 {
                caps = .sentences
            }
            if (flags & AInputType.TYPE_TEXT_FLAG_AUTO_CORRECT) != 0 { correction = .yes }
            switch variation {
            case AInputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS, AInputType.TYPE_TEXT_VARIATION_WEB_EMAIL_ADDRESS:
                keyboard = .emailAddress
            case AInputType.TYPE_TEXT_VARIATION_URI:
                keyboard = .URL
            case AInputType.TYPE_TEXT_VARIATION_PASSWORD, AInputType.TYPE_TEXT_VARIATION_WEB_PASSWORD:
                secure = true
            case AInputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD:
                keyboard = .asciiCapable
            default:
                break
            }
        }
        let returnKey: UIReturnKeyType
        switch aw_imeActionId() {
        case AEditorInfo.IME_ACTION_GO: returnKey = .go
        case AEditorInfo.IME_ACTION_SEARCH: returnKey = .search
        case AEditorInfo.IME_ACTION_SEND: returnKey = .send
        case AEditorInfo.IME_ACTION_NEXT: returnKey = .next
        case AEditorInfo.IME_ACTION_DONE: returnKey = .done
        default: returnKey = .default
        }
        if let f = aw_field {
            f.keyboardType = keyboard
            f.autocapitalizationType = caps
            f.autocorrectionType = correction
            f.spellCheckingType = .no
            f.smartQuotesType = .no
            f.smartDashesType = .no
            f.smartInsertDeleteType = .no
            f.isSecureTextEntry = secure
            f.returnKeyType = returnKey
        }
        if let a = aw_area {
            a.keyboardType = keyboard
            a.autocapitalizationType = caps
            a.autocorrectionType = correction
            a.spellCheckingType = .no
            a.smartQuotesType = .no
            a.smartDashesType = .no
        }
    }

    /// Phone input is laid out in the direction of the locale's digits (TextView.getTextDirectionHeuristic): LTR for
    /// the app's languages.
    override func aw_phoneInputDirection() -> ATextDirectionHeuristic? {
        return (aw_inputType & AInputType.TYPE_MASK_CLASS) == AInputType.TYPE_CLASS_PHONE ? .LTR : nil
    }

    /// The editor's alignment and writing direction from the Android layout of the text (Layout.getParagraphDirection
    /// and the layout alignment).
    private func aw_syncAlignment() {
        let units = Array(aw_transformed.aw_plain.utf16)
        let dirHeuristic = aw_textDir ?? aw_textDirectionHeuristic()
        let rtl = dirHeuristic.isRtl(units, 0, units.count)
        let ns: NSTextAlignment
        switch aw_layoutAlignment() {
        case .ALIGN_CENTER: ns = .center
        case .ALIGN_LEFT: ns = .left
        case .ALIGN_RIGHT: ns = .right
        case .ALIGN_NORMAL: ns = rtl ? .right : .left
        case .ALIGN_OPPOSITE: ns = rtl ? .left : .right
        }
        let semantic: UISemanticContentAttribute = rtl ? .forceRightToLeft : .forceLeftToRight
        if let f = aw_field {
            if f.textAlignment != ns { f.textAlignment = ns }
            if f.semanticContentAttribute != semantic { f.semanticContentAttribute = semantic }
        }
        if let a = aw_area {
            if a.textAlignment != ns { a.textAlignment = ns }
            if a.semanticContentAttribute != semantic { a.semanticContentAttribute = semantic }
        }
    }

    /// Places the UIKit editor: it covers the view (taps anywhere focus it, like Android), its text box is the
    /// compound-padded content box, and its first baseline is the Android one (getExtendedPaddingTop +
    /// getVerticalOffset + the layout's first baseline).
    func aw_layoutEditor() {
        let d = CGFloat(AWidgetEnv.density)
        guard width > 0 && height > 0 else { return }
        let layout = aw_assumeLayout()
        var voffset = 0
        if (aw_gravity & AGravity.VERTICAL_GRAVITY_MASK) != AGravity.TOP { voffset = aw_verticalOffset(true) }
        let baselinePx = extendedPaddingTop + voffset + (layout.lineCount > 0 ? layout.getLineBaseline(0) : 0) - scrollY
        let left = CGFloat(compoundPaddingLeft) / d
        let right = CGFloat(width - compoundPaddingRight) / d
        let font = paint.uiFont()
        if let f = aw_field {
            f.frame = CGRect(x: 0, y: 0, width: CGFloat(width) / d, height: CGFloat(height) / d)
            let top = CGFloat(baselinePx) / d - font.ascender
            f.aw_textBox = CGRect(x: left, y: top, width: Swift.max(right - left, 0), height: font.lineHeight)
            f.setNeedsLayout()
        }
        if let a = aw_area {
            let top = CGFloat(baselinePx) / d - font.ascender
            let bottom = CGFloat(height - extendedPaddingBottom) / d
            a.frame = CGRect(x: left, y: top, width: Swift.max(right - left, 0), height: Swift.max(bottom - top, font.lineHeight))
        }
        aw_syncAlignment()
    }

    override func onLayout(_ changed: Bool, _ l: Int, _ t: Int, _ r: Int, _ b: Int) {
        super.onLayout(changed, l, t, r, b)
        aw_layoutEditor()
    }

    override func onSizeChanged(_ w: Int, _ h: Int, _ oldw: Int, _ oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        aw_layoutEditor()
    }

    /// TextView.onDraw: the hint is drawn by the TextView (empty text), the typed text by UIKit.
    override func onDraw(_ canvas: ACanvas) {
        aw_drawsOwnText = aw_text.aw_plain.isEmpty
        super.onDraw(canvas)
        aw_drawsOwnText = false
    }

    // MARK: Edits from UIKit (SpannableStringBuilder.replace + TextView.ChangeWatcher)

    /// The edit as SpannableStringBuilder.replace applies it: the filters may replace the source; an empty edit of an
    /// empty range does nothing; the watchers get beforeTextChanged with the filtered length.
    private func aw_shouldChange(_ range: NSRange, _ replacement: String, _ markedText: Bool) -> Bool {
        if aw_syncing { return true }
        let dest = aw_text.aw_plain
        let dstart = range.location, dend = range.location + range.length
        if markedText {
            // IME composition: UIKit owns the marked text; the change is reported when it lands.
            if aw_pendingEdit == nil {
                aw_sendBeforeTextChanged(dest, 0, dest.utf16.count, 0)
                aw_pendingEdit = (0, dest.utf16.count, -1, true)
            }
            return true
        }
        var source = replacement
        var filtered = false
        for f in aw_editableFilters {
            if let out = f.filter(source, 0, source.utf16.count, dest, dstart, dend) {
                source = out
                filtered = true
            }
        }
        let origLen = dend - dstart
        let newLen = source.utf16.count
        if origLen == 0 && newLen == 0 {
            return false
        }
        aw_sendBeforeTextChanged(dest, dstart, origLen, newLen)
        aw_pendingEdit = (dstart, origLen, newLen, true)
        if !filtered || source == replacement {
            return true
        }
        let newText = (dest as NSString).replacingCharacters(in: range, with: source)
        aw_syncing = true
        if let f = aw_field {
            f.text = newText
            if let pos = f.position(from: f.beginningOfDocument, offset: dstart + newLen) {
                f.selectedTextRange = f.textRange(from: pos, to: pos)
            }
        }
        if let a = aw_area {
            a.text = newText
            a.selectedRange = NSRange(location: dstart + newLen, length: 0)
        }
        aw_syncing = false
        aw_editorTextChanged()
        return false
    }

    /// TextView.handleTextChanged + sendAfterTextChanged for the editor's new text.
    private func aw_editorTextChanged() {
        if aw_syncing { return }
        let s = aw_field?.text ?? aw_area?.text ?? ""
        let old = aw_text.aw_plain
        if s == old && aw_pendingEdit == nil { return }
        var edit = aw_pendingEdit ?? (0, old.utf16.count, s.utf16.count, false)
        aw_pendingEdit = nil
        if edit.after < 0 { edit.after = s.utf16.count }
        if !edit.beforeSent { aw_sendBeforeTextChanged(old, edit.start, edit.before, edit.after) }
        aw_text = s
        aw_transformed = aw_transform(s)
        // The Editable's layout follows the text (DynamicLayout): rebuilt at the current widths, then checkForResize.
        if let l = aw_layout {
            let hintWant = aw_hintLayout?.getWidth() ?? 0
            aw_makeNewLayout(l.getWidth(), hintWant, .UNKNOWN, .UNKNOWN, l.getEllipsizedWidth(), false)
        }
        aw_checkForResize()
        invalidate()
        aw_errorWasChanged = false
        aw_sendOnTextChanged(s, edit.start, edit.before, edit.after)
        onTextChanged(s, edit.start, edit.before, edit.after)
        aw_sendAfterTextChanged(s)
        updateAccessibility()
        aw_syncAlignment()
    }

    @objc private func aw_editorEditingChanged() {
        if aw_field?.markedTextRange != nil { return }
        aw_editorTextChanged()
    }

    // MARK: UITextFieldDelegate

    func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
        return isEnabled && visibility == AView.VISIBLE
    }

    func textFieldDidBeginEditing(_ textField: UITextField) {
        aw_editorDidBegin()
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        aw_editorDidEnd()
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        return aw_shouldChange(range, string, textField.markedTextRange != nil)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        onEditorAction(aw_imeActionId())
        return false
    }

    // MARK: UITextViewDelegate

    func textViewShouldBeginEditing(_ textView: UITextView) -> Bool {
        return isEnabled && visibility == AView.VISIBLE
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        aw_editorDidBegin()
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        aw_editorDidEnd()
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        return aw_shouldChange(range, text, textView.markedTextRange != nil)
    }

    func textViewDidChange(_ textView: UITextView) {
        if textView.markedTextRange != nil { return }
        aw_editorTextChanged()
    }

    /// The UIKit editor became first responder (a tap): the view takes the Android focus.
    private func aw_editorDidBegin() {
        AEditText.aw_keyboardOwner = self
        if !isFocusedSelf {
            aw_focusFromEditor = true
            _ = requestFocus()
            aw_focusFromEditor = false
        }
    }

    /// The UIKit editor resigned: the Android focus stays (only the soft input is gone).
    private func aw_editorDidEnd() {
        if AEditText.aw_keyboardOwner === self && !aw_hideKeyboardKeepsFocus {
            AEditText.aw_keyboardOwner = nil
        }
    }

    // MARK: Accessibility

    override var providesAccessibilityText: Bool { return false }

    /// The UIKit editor is the accessibility element (labelled with the content description or the hint).
    override func updateAccessibility() {
        super.updateAccessibility()
        isAccessibilityElement = false
        let label = contentDescription ?? aw_hint?.aw_plain
        aw_field?.accessibilityLabel = label
        aw_area?.accessibilityLabel = label
    }
}

/// A FrameLayout with setAddStatesFromChildren(true) (TextInputLayout's input frame).
final class AWAddStatesFrameLayout: AFrameLayout {
    override func onCreateDrawableState(_ extraSpace: Int) -> [Int] {
        var state = super.onCreateDrawableState(extraSpace)
        for child in children {
            state = AView.mergeDrawableStates(state, child.drawableState)
        }
        return state
    }

    override func childDrawableStateChanged(_ child: AView) {
        refreshDrawableState()
    }
}

// MARK: - TextInputLayout box drawables (MaterialShapeDrawable)

/// The FilledBox background MaterialShapeDrawable: the fill colour in a rectangle with the shape's top corners
/// (ShapeAppearance.MaterialComponents.SmallComponent 4 dp, FilledBox overlay: bottom corners 0).
final class AWBoxBackgroundDrawable: ADrawable {
    var fillColor: Int = AColor.TRANSPARENT
    var topCornerSize: Float = 0
    var bottomCornerSize: Float = 0
    private let aw_paint = APaint(APaint.ANTI_ALIAS_FLAG)

    override func draw(_ canvas: ACanvas) {
        let b = bounds
        if b.width() <= 0 || b.height() <= 0 || AColor.alpha(fillColor) == 0 { return }
        aw_paint.style = .FILL
        aw_paint.color = fillColor
        aw_paint.alpha = AColor.alpha(fillColor) * alpha / 255
        let maxR = Float(Swift.min(b.width(), b.height())) / 2
        let t = Swift.min(topCornerSize, maxR), bt = Swift.min(bottomCornerSize, maxR)
        let path = APath()
        path.addRoundRect(ARectF(Float(b.left), Float(b.top), Float(b.right), Float(b.bottom)), [t, t, t, t, bt, bt, bt, bt], .CW)
        canvas.drawPath(path, aw_paint)
    }
}

/// The box underline MaterialShapeDrawables (a filled rectangle).
final class AWBoxUnderlineDrawable: ADrawable {
    var fillColor: Int = AColor.TRANSPARENT
    private let aw_paint = APaint(APaint.ANTI_ALIAS_FLAG)

    override func draw(_ canvas: ACanvas) {
        let b = bounds
        if b.width() <= 0 || b.height() <= 0 || AColor.alpha(fillColor) == 0 { return }
        aw_paint.style = .FILL
        aw_paint.color = fillColor
        aw_paint.alpha = AColor.alpha(fillColor) * alpha / 255
        canvas.drawRect(Float(b.left), Float(b.top), Float(b.right), Float(b.bottom), aw_paint)
    }
}

/// The TextInputLayout's own drawing over its children (TextInputLayout.draw: drawHint + drawBoxUnderline), installed
/// as the layout's foreground so that it is drawn above the EditText like on Android.
final class AWTextInputOverlay: ADrawable {
    weak var owner: ATextInputLayout?
    override func draw(_ canvas: ACanvas) { owner?.aw_drawOverlay(canvas) }
}

// MARK: - CollapsingTextHelper

/// com.google.android.material.internal.CollapsingTextHelper (single line, no fade mode, no texture): the label is a
/// StaticLayout (StaticLayoutBuilderCompat: ellipsized END, RTL text aligned OPPOSITE) drawn at a lerp of the
/// expanded and collapsed positions, scaled from the expanded size. Font metrics are Android's (AWFontMetrics).
final class AWCollapsingTextHelper {
    private weak var view: AView?

    private var expandedFraction: Float = 0
    private let expandedBounds = ARect()
    private let collapsedBounds = ARect()
    private let currentBounds = ARectF()
    private var expandedTextGravity = AGravity.CENTER_VERTICAL
    private var collapsedTextGravity = AGravity.CENTER_VERTICAL
    private var expandedTextSize: Float = 15
    private var collapsedTextSize: Float = 15
    private(set) var expandedTextColor: AColorStateList?
    private(set) var collapsedTextColor: AColorStateList?

    private var expandedDrawY: Float = 0
    private var collapsedDrawY: Float = 0
    private var expandedDrawX: Float = 0
    private var collapsedDrawX: Float = 0
    private var currentDrawX: Float = 0
    private var currentDrawY: Float = 0
    private var collapsedTypeface: ATypeface?
    private var expandedTypeface: ATypeface?
    private var currentTypeface: ATypeface?

    private(set) var text: String?
    private var textToDraw: String?
    private var isRtl = false
    private var scale: Float = 1
    private var currentTextSize: Float = 0
    private var state: [Int]?
    private var boundsChanged = false

    private let textPaint = APaint(APaint.ANTI_ALIAS_FLAG | APaint.SUBPIXEL_TEXT_FLAG)
    private let tmpPaint = APaint(APaint.ANTI_ALIAS_FLAG | APaint.SUBPIXEL_TEXT_FLAG)
    var positionInterpolator: ATimeInterpolator?
    var textSizeInterpolator: ATimeInterpolator?

    private var collapsedLetterSpacing: Float = 0
    private var expandedLetterSpacing: Float = 0
    private var currentLetterSpacing: Float = 0

    private var textLayout: ALayout?
    private var collapsedTextWidth: Float = 0
    private var textToDrawCollapsed: String?

    init(_ view: AView) {
        self.view = view
    }

    private static func ascent(_ size: Float) -> Float { return AWFontMetrics.metrics(size).ascent }
    private static func descent(_ size: Float) -> Float { return AWFontMetrics.metrics(size).descent }

    func setTextSizeInterpolator(_ interpolator: ATimeInterpolator?) {
        textSizeInterpolator = interpolator
        recalculate()
    }

    func setPositionInterpolator(_ interpolator: ATimeInterpolator?) {
        positionInterpolator = interpolator
        recalculate()
    }

    func setExpandedTextSize(_ textSize: Float) {
        if expandedTextSize != textSize {
            expandedTextSize = textSize
            recalculate()
        }
    }

    func setCollapsedTextSize(_ textSize: Float) {
        if collapsedTextSize != textSize {
            collapsedTextSize = textSize
            recalculate()
        }
    }

    func setCollapsedTextColor(_ textColor: AColorStateList?) {
        if collapsedTextColor !== textColor {
            collapsedTextColor = textColor
            recalculate()
        }
    }

    func setExpandedTextColor(_ textColor: AColorStateList?) {
        if expandedTextColor !== textColor {
            expandedTextColor = textColor
            recalculate()
        }
    }

    func setCollapsedAndExpandedTextColor(_ textColor: AColorStateList?) {
        if collapsedTextColor !== textColor || expandedTextColor !== textColor {
            collapsedTextColor = textColor
            expandedTextColor = textColor
            recalculate()
        }
    }

    func setExpandedLetterSpacing(_ letterSpacing: Float) {
        if expandedLetterSpacing != letterSpacing {
            expandedLetterSpacing = letterSpacing
            recalculate()
        }
    }

    /// setCollapsedTextAppearance of the TextInputLayout's hintTextAppearance (TextAppearance.MaterialComponents.Caption:
    /// 12 sp read with getDimension, letter spacing 0.0333333333, ?android:textColorSecondary).
    func setCollapsedTextAppearance(textColor: AColorStateList?, textSize: Float, letterSpacing: Float) {
        if let c = textColor { collapsedTextColor = c }
        if textSize != 0 { collapsedTextSize = textSize }
        collapsedLetterSpacing = letterSpacing
        recalculate()
    }

    func setExpandedBounds(_ left: Int, _ top: Int, _ right: Int, _ bottom: Int) {
        if !(expandedBounds.left == left && expandedBounds.top == top && expandedBounds.right == right && expandedBounds.bottom == bottom) {
            expandedBounds.set(left, top, right, bottom)
            boundsChanged = true
        }
    }

    func setExpandedBounds(_ bounds: ARect) { setExpandedBounds(bounds.left, bounds.top, bounds.right, bounds.bottom) }

    func setCollapsedBounds(_ left: Int, _ top: Int, _ right: Int, _ bottom: Int) {
        if !(collapsedBounds.left == left && collapsedBounds.top == top && collapsedBounds.right == right && collapsedBounds.bottom == bottom) {
            collapsedBounds.set(left, top, right, bottom)
            boundsChanged = true
        }
    }

    func setCollapsedBounds(_ bounds: ARect) { setCollapsedBounds(bounds.left, bounds.top, bounds.right, bounds.bottom) }

    func getExpandedTextHeight() -> Float {
        return -AWCollapsingTextHelper.ascent(expandedTextSize)
    }

    func getCollapsedTextHeight() -> Float {
        return -AWCollapsingTextHelper.ascent(collapsedTextSize)
    }

    func setExpandedTextGravity(_ gravity: Int) {
        if expandedTextGravity != gravity {
            expandedTextGravity = gravity
            recalculate()
        }
    }

    func setCollapsedTextGravity(_ gravity: Int) {
        if collapsedTextGravity != gravity {
            collapsedTextGravity = gravity
            recalculate()
        }
    }

    func setTypefaces(_ typeface: ATypeface?) {
        var changed = false
        if collapsedTypeface !== typeface { collapsedTypeface = typeface; changed = true }
        if expandedTypeface !== typeface { expandedTypeface = typeface; changed = true }
        if changed { recalculate() }
    }

    func setExpansionFraction(_ fraction0: Float) {
        let fraction = Swift.min(Swift.max(fraction0, 0), 1)
        if fraction != expandedFraction {
            expandedFraction = fraction
            calculateCurrentOffsets()
        }
    }

    func getExpansionFraction() -> Float { return expandedFraction }

    @discardableResult
    func setState(_ state: [Int]) -> Bool {
        self.state = state
        if isStateful() {
            recalculate()
            return true
        }
        return false
    }

    func isStateful() -> Bool {
        return (collapsedTextColor?.isStateful ?? false) || (expandedTextColor?.isStateful ?? false)
    }

    private func calculateCurrentOffsets() {
        calculateOffsets(expandedFraction)
    }

    private static func lerp(_ startValue: Float, _ endValue: Float, _ fraction0: Float, _ interpolator: ATimeInterpolator?) -> Float {
        var fraction = fraction0
        if let i = interpolator { fraction = i.getInterpolation(fraction) }
        return AWAnimationUtils.lerp(startValue, endValue, fraction)
    }

    /// CollapsingTextHelper.blendARGB.
    static func blendARGB(_ color1: Int, _ color2: Int, _ ratio: Float) -> Int {
        let inverseRatio = 1 - ratio
        let a = Float(AColor.alpha(color1)) * inverseRatio + Float(AColor.alpha(color2)) * ratio
        let r = Float(AColor.red(color1)) * inverseRatio + Float(AColor.red(color2)) * ratio
        let g = Float(AColor.green(color1)) * inverseRatio + Float(AColor.green(color2)) * ratio
        let b = Float(AColor.blue(color1)) * inverseRatio + Float(AColor.blue(color2)) * ratio
        return AColor.argb(AWMath.round(a), AWMath.round(r), AWMath.round(g), AWMath.round(b))
    }

    private func calculateOffsets(_ fraction: Float) {
        interpolateBounds(fraction)
        let textBlendFraction = fraction
        currentDrawX = AWCollapsingTextHelper.lerp(expandedDrawX, collapsedDrawX, fraction, positionInterpolator)
        currentDrawY = AWCollapsingTextHelper.lerp(expandedDrawY, collapsedDrawY, fraction, positionInterpolator)
        setInterpolatedTextSize(fraction)
        if collapsedTextColor !== expandedTextColor {
            textPaint.color = AWCollapsingTextHelper.blendARGB(getCurrentExpandedTextColor(), getCurrentCollapsedTextColor(),
                                                               textBlendFraction)
        } else {
            textPaint.color = getCurrentCollapsedTextColor()
        }
        if collapsedLetterSpacing != expandedLetterSpacing {
            textPaint.letterSpacing = AWCollapsingTextHelper.lerp(expandedLetterSpacing, collapsedLetterSpacing, fraction,
                                                                  AWAnimationUtils.FAST_OUT_SLOW_IN_INTERPOLATOR)
        } else {
            textPaint.letterSpacing = collapsedLetterSpacing
        }
        textPaint.setShadowLayer(0, 0, 0, 0)
        view?.postInvalidateOnAnimation()
    }

    private func getCurrentExpandedTextColor() -> Int { return getCurrentColor(expandedTextColor) }
    func getCurrentCollapsedTextColor() -> Int { return getCurrentColor(collapsedTextColor) }

    private func getCurrentColor(_ colorStateList: AColorStateList?) -> Int {
        guard let c = colorStateList else { return 0 }
        if let s = state { return c.getColorForState(s, 0) }
        return c.defaultColor
    }

    private func calculateBaseOffsets(_ forceRecalculate: Bool) {
        calculateUsingTextSize(1, forceRecalculate)
        if let t = textToDraw, let l = textLayout {
            textToDrawCollapsed = AWCollapsingTextHelper.ellipsize(t, textPaint, l.getWidth())
        }
        if let c = textToDrawCollapsed {
            collapsedTextWidth = textPaint.measureText(c)
        } else {
            collapsedTextWidth = 0
        }
        let collapsedAbsGravity = AGravity.getAbsoluteGravity(collapsedTextGravity,
                                                              isRtl ? AView.LAYOUT_DIRECTION_RTL : AView.LAYOUT_DIRECTION_LTR)
        switch collapsedAbsGravity & AGravity.VERTICAL_GRAVITY_MASK {
        case AGravity.BOTTOM:
            collapsedDrawY = Float(collapsedBounds.bottom) + AWCollapsingTextHelper.ascent(textPaint.textSize)
        case AGravity.TOP:
            collapsedDrawY = Float(collapsedBounds.top)
        default:
            let textOffset = (AWCollapsingTextHelper.descent(textPaint.textSize) - AWCollapsingTextHelper.ascent(textPaint.textSize)) / 2
            collapsedDrawY = Float(collapsedBounds.centerY()) - textOffset
        }
        switch collapsedAbsGravity & AGravity.RELATIVE_HORIZONTAL_GRAVITY_MASK {
        case AGravity.CENTER_HORIZONTAL:
            collapsedDrawX = Float(collapsedBounds.centerX()) - (collapsedTextWidth / 2)
        case AGravity.RIGHT:
            collapsedDrawX = Float(collapsedBounds.right) - collapsedTextWidth
        default:
            collapsedDrawX = Float(collapsedBounds.left)
        }
        calculateUsingTextSize(0, forceRecalculate)
        let expandedTextHeight: Float = textLayout.map { Float($0.getHeight()) } ?? 0
        var expandedTextWidth: Float = 0
        if let t = textToDraw {
            expandedTextWidth = textPaint.measureText(t)
        }
        let expandedAbsGravity = AGravity.getAbsoluteGravity(expandedTextGravity,
                                                             isRtl ? AView.LAYOUT_DIRECTION_RTL : AView.LAYOUT_DIRECTION_LTR)
        switch expandedAbsGravity & AGravity.VERTICAL_GRAVITY_MASK {
        case AGravity.BOTTOM:
            expandedDrawY = Float(expandedBounds.bottom) - expandedTextHeight + AWCollapsingTextHelper.descent(textPaint.textSize)
        case AGravity.TOP:
            expandedDrawY = Float(expandedBounds.top)
        default:
            let textOffset = expandedTextHeight / 2
            expandedDrawY = Float(expandedBounds.centerY()) - textOffset
        }
        switch expandedAbsGravity & AGravity.RELATIVE_HORIZONTAL_GRAVITY_MASK {
        case AGravity.CENTER_HORIZONTAL:
            expandedDrawX = Float(expandedBounds.centerX()) - (expandedTextWidth / 2)
        case AGravity.RIGHT:
            expandedDrawX = Float(expandedBounds.right) - expandedTextWidth
        default:
            expandedDrawX = Float(expandedBounds.left)
        }
        setInterpolatedTextSize(expandedFraction)
    }

    /// TextUtils.ellipsize(text, paint, avail, END) for one line.
    private static func ellipsize(_ text: String, _ paint: APaint, _ avail: Int) -> String {
        if paint.measureText(text) <= Float(avail) { return text }
        let l = ALayout(text: text, paint: paint, width: avail, alignment: .ALIGN_NORMAL, textDir: .FIRSTSTRONG_LTR,
                        spacingMult: 1, spacingAdd: 0, includePad: false, ellipsize: .END, ellipsizedWidth: avail, maxLines: 1,
                        breakStrategy: ALayout.BREAK_STRATEGY_SIMPLE)
        guard l.lineCount > 0, l.getEllipsisCount(0) > 0 else { return text }
        let units = Array(text.utf16)
        let start = Swift.min(l.getEllipsisStart(0), units.count)
        return String(decoding: units[0..<start], as: UTF16.self) + ATextUtils.getEllipsisString(.END)
    }

    private func interpolateBounds(_ fraction: Float) {
        currentBounds.left = AWCollapsingTextHelper.lerp(Float(expandedBounds.left), Float(collapsedBounds.left), fraction, positionInterpolator)
        currentBounds.top = AWCollapsingTextHelper.lerp(expandedDrawY, collapsedDrawY, fraction, positionInterpolator)
        currentBounds.right = AWCollapsingTextHelper.lerp(Float(expandedBounds.right), Float(collapsedBounds.right), fraction, positionInterpolator)
        currentBounds.bottom = AWCollapsingTextHelper.lerp(Float(expandedBounds.bottom), Float(collapsedBounds.bottom), fraction, positionInterpolator)
    }

    func draw(_ canvas: ACanvas) {
        let saveCount = canvas.save()
        if textToDraw != nil, let layout = textLayout, currentBounds.width() > 0, currentBounds.height() > 0 {
            textPaint.textSize = currentTextSize
            let x = currentDrawX
            let y = currentDrawY
            if scale != 1 {
                canvas.scale(scale, scale, x, y)
            }
            canvas.translate(x, y)
            layout.draw(canvas)
        }
        canvas.restoreToCount(saveCount)
    }

    private func calculateIsRtl(_ text: String) -> Bool {
        let defaultIsRtl = (view?.isLayoutRtl ?? false)
        let units = Array(text.utf16)
        return (defaultIsRtl ? ATextDirectionHeuristic.FIRSTSTRONG_RTL : ATextDirectionHeuristic.FIRSTSTRONG_LTR).isRtl(units, 0, units.count)
    }

    private func setInterpolatedTextSize(_ fraction: Float) {
        calculateUsingTextSize(fraction)
        view?.postInvalidateOnAnimation()
    }

    private static func isClose(_ value: Float, _ targetValue: Float) -> Bool {
        return abs(value - targetValue) < 0.00001
    }

    private func calculateUsingTextSize(_ fraction: Float, _ forceRecalculate: Bool = false) {
        guard let text = text else { return }
        let collapsedWidth = Float(collapsedBounds.width())
        let expandedWidth = Float(expandedBounds.width())
        var availableWidth: Float
        var newTextSize: Float
        var newLetterSpacing: Float
        var newTypeface: ATypeface?
        if AWCollapsingTextHelper.isClose(fraction, 1) {
            newTextSize = collapsedTextSize
            newLetterSpacing = collapsedLetterSpacing
            scale = 1
            newTypeface = collapsedTypeface
            availableWidth = collapsedWidth
        } else {
            newTextSize = expandedTextSize
            newLetterSpacing = expandedLetterSpacing
            newTypeface = expandedTypeface
            if AWCollapsingTextHelper.isClose(fraction, 0) {
                scale = 1
            } else {
                scale = AWCollapsingTextHelper.lerp(expandedTextSize, collapsedTextSize, fraction, textSizeInterpolator) / expandedTextSize
            }
            let textSizeRatio = collapsedTextSize / expandedTextSize
            let scaledDownWidth = expandedWidth * textSizeRatio
            if forceRecalculate {
                availableWidth = expandedWidth
            } else {
                availableWidth = scaledDownWidth > collapsedWidth ? Swift.min(collapsedWidth / textSizeRatio, expandedWidth) : expandedWidth
            }
        }
        var updateDrawText: Bool
        if availableWidth > 0 {
            let textSizeChanged = currentTextSize != newTextSize
            let letterSpacingChanged = currentLetterSpacing != newLetterSpacing
            let typefaceChanged = currentTypeface !== newTypeface
            let availableWidthChanged = textLayout != nil && availableWidth != Float(textLayout!.getWidth())
            updateDrawText = textSizeChanged || letterSpacingChanged || availableWidthChanged || typefaceChanged || boundsChanged
            currentTextSize = newTextSize
            currentLetterSpacing = newLetterSpacing
            currentTypeface = newTypeface
            boundsChanged = false
            textPaint.isLinearText = scale != 1
        } else {
            updateDrawText = false
        }
        if textToDraw == nil || updateDrawText {
            textPaint.textSize = currentTextSize
            textPaint.typeface = currentTypeface
            textPaint.letterSpacing = currentLetterSpacing
            isRtl = calculateIsRtl(text)
            textLayout = createStaticLayout(availableWidth, isRtl, text)
            textToDraw = textLayout?.getText()
        }
    }

    /// StaticLayoutBuilderCompat.build (maxLines 1): pre-ellipsized text, ALIGN_OPPOSITE for RTL text, no include pad.
    private func createStaticLayout(_ availableWidth0: Float, _ isRtl: Bool, _ source: String) -> ALayout {
        let availableWidth = Swift.max(0, AWMath.javaInt(availableWidth0))
        let textToDraw = AWCollapsingTextHelper.ellipsize(source, textPaint, availableWidth)
        let alignment: ALayout.Alignment = isRtl ? .ALIGN_OPPOSITE : .ALIGN_NORMAL
        return ALayout(text: textToDraw, paint: textPaint, width: availableWidth, alignment: alignment,
                       textDir: isRtl ? .RTL : .LTR, spacingMult: 1, spacingAdd: 0, includePad: false, ellipsize: .END,
                       ellipsizedWidth: availableWidth, maxLines: 1, breakStrategy: ALayout.BREAK_STRATEGY_HIGH_QUALITY)
    }

    func recalculate(_ forceRecalculate: Bool = false) {
        guard let v = view else { return }
        if (v.height > 0 && v.width > 0) || forceRecalculate {
            calculateBaseOffsets(forceRecalculate)
            calculateCurrentOffsets()
        }
    }

    func setText(_ text: String?) {
        if text == nil || self.text != text {
            self.text = text
            textToDraw = nil
            recalculate()
        }
    }
}

// MARK: - TextInputEditText

/// com.google.android.material.textfield.TextInputEditText inflated inside a TextInputLayout (FilledBox theme overlay:
/// Widget.MaterialComponents.TextInputEditText.FilledBox: padding 16/24/16/10 dp, background null,
/// TextAppearance.MaterialComponents.Subtitle1 16 sp, letter spacing 0.009375, colorControlActivated = colorPrimary).
class ATextInputEditText: AEditText {
    override func aw_configureEditText() {
        super.aw_configureEditText()
        setBackgroundDrawable(nil)
        applyXmlTextSize(16)
        setLetterSpacing(0.009375)
        setPadding(aw_dpx(16), aw_dpx(24), aw_dpx(16), aw_dpx(10))
        aw_cursorColor = AWMaterialColors.colorPrimary
    }

    /// The TextInputLayout this field belongs to (TextInputEditText.getTextInputLayout: the first ancestor).
    var textInputLayout: ATextInputLayout? {
        var p: AViewGroup? = parentGroup
        while let cur = p {
            if let til = cur as? ATextInputLayout { return til }
            p = cur.parentGroup
        }
        return nil
    }

    /// TextInputEditText.getHint: the layout's hint while it provides the hint.
    override var hint: String? {
        get { return getHint() }
        set { setHint(newValue) }
    }

    override func getHint() -> String? {
        if let layout = textInputLayout, layout.isProvidingHint() {
            return layout.getHint()
        }
        return super.getHint()
    }
}

// MARK: - TextInputLayout

/// com.google.android.material.textfield.TextInputLayout (material 1.12.0) with the theme's textInputStyle
/// Widget.MaterialComponents.TextInputLayout.FilledBox: a vertical LinearLayout holding the input frame (a FrameLayout)
/// that receives the EditText; the box background (boxBackgroundColor layered on colorSurface, 4 dp top corners) is
/// set on the EditText; the underline (1 dp default stroke colour, 2 dp focused colorPrimary expanding from the
/// middle) and the floating label (CollapsingTextHelper: 16 sp expanded, 12 sp Caption collapsed at
/// boxCollapsedPaddingTop 10 dp, 167 ms FastOutSlowIn) are drawn over it. Error / helper / counter / icons are not used
/// by the app and not ported.
class ATextInputLayout: ALinearLayout {
    static let BOX_BACKGROUND_NONE = 0, BOX_BACKGROUND_FILLED = 1, BOX_BACKGROUND_OUTLINE = 2
    private static let LABEL_SCALE_ANIMATION_DURATION: Int64 = 167
    private static let NO_WIDTH = -1

    /// The FrameLayout the EditText lives in (inputFrame.setAddStatesFromChildren(true)).
    let inputFrame: AFrameLayout = AWAddStatesFrameLayout()
    private(set) var aw_editText: AEditText?
    private lazy var collapsingTextHelper = AWCollapsingTextHelper(self)
    private let aw_overlay = AWTextInputOverlay()

    private var hintEnabled = true
    private var aw_hint: String?
    private var aw_isProvidingHint = false
    private var hintExpanded = false
    private var hintAnimationEnabled = true
    private var expandedHintEnabled = true
    private var animator: AValueAnimator?
    private var inDrawableStateChanged = false

    private var minWidth = ATextInputLayout.NO_WIDTH
    private var maxWidth = ATextInputLayout.NO_WIDTH

    private var boxBackground: AWBoxBackgroundDrawable?
    private var boxBackgroundApplied = false
    private var boxUnderlineDefault: AWBoxUnderlineDrawable?
    private var boxUnderlineFocused: AWBoxUnderlineDrawable?
    private var aw_boxBackgroundMode = ATextInputLayout.BOX_BACKGROUND_NONE
    private var boxCollapsedPaddingTopPx = 0
    private var boxStrokeWidthPx = 0
    private var boxStrokeWidthDefaultPx = 0
    private var boxStrokeWidthFocusedPx = 0
    private var boxStrokeColor = 0
    private var aw_boxBackgroundColor = 0
    private var shapeTopCornerSize: Float = 0
    private var shapeBottomCornerSize: Float = 0

    private var defaultHintTextColor: AColorStateList?
    private var focusedTextColor: AColorStateList?
    private var defaultStrokeColor = 0
    private var hoveredStrokeColor = 0
    private var focusedStrokeColor = 0
    private var disabledColor = 0
    private var defaultFilledBackgroundColor = 0
    private var disabledFilledBackgroundColor = 0
    private var focusedFilledBackgroundColor = 0
    private var hoveredFilledBackgroundColor = 0

    private let tmpRect = ARect()
    private let tmpBoundsRect = ARect()

    override init() {
        super.init()
        orientation = ALinearLayout.VERTICAL
        setWillNotDraw(false)
        collapsingTextHelper.setTextSizeInterpolator(ALinearInterpolator())
        collapsingTextHelper.setPositionInterpolator(ALinearInterpolator())
        collapsingTextHelper.setCollapsedTextGravity(AGravity.TOP | AGravity.START)
        // Widget.MaterialComponents.TextInputLayout.FilledBox under Theme.TripleShot (light).
        minWidth = aw_dpx(56)
        maxWidth = aw_dpx(488)
        shapeTopCornerSize = Float(aw_dpx(4))
        shapeBottomCornerSize = 0
        boxCollapsedPaddingTopPx = ATypedValue.toDimensionPixelOffset(ATypedValue.COMPLEX_UNIT_DIP, 10)
        boxStrokeWidthDefaultPx = aw_dpx(1)
        boxStrokeWidthFocusedPx = aw_dpx(2)
        boxStrokeWidthPx = boxStrokeWidthDefaultPx
        // boxBackgroundColor = mtrl_filled_background_color (stateful).
        defaultFilledBackgroundColor = AWMaterialColors.withAlpha(AWMaterialColors.colorOnSurface, 0.12)
        aw_boxBackgroundColor = defaultFilledBackgroundColor
        disabledFilledBackgroundColor = AWMaterialColors.withAlpha(AWMaterialColors.colorOnSurface, 0.04)
        focusedFilledBackgroundColor = AWMaterialColors.withAlpha(AWMaterialColors.colorOnSurface, 0.12)
        hoveredFilledBackgroundColor = AWMaterialColors.withAlpha(AWMaterialColors.colorOnSurface, 0.16)
        // android:textColorHint = mtrl_indicator_text_color.
        defaultHintTextColor = AColorStateList([[-AStateSet.state_enabled], []],
                                               [AWMaterialColors.withAlpha(AWMaterialColors.colorOnSurface, 0.38),
                                                AWMaterialColors.withAlpha(AWMaterialColors.colorOnSurface, 0.6)])
        focusedTextColor = defaultHintTextColor
        // boxStrokeColor = mtrl_filled_stroke_color (setBoxStrokeColorStateList).
        defaultStrokeColor = AWMaterialColors.withAlpha(AWMaterialColors.colorOnSurface, 0.42)
        disabledColor = AWMaterialColors.withAlpha(AWMaterialColors.colorOnSurface, 0.38)
        hoveredStrokeColor = AWMaterialColors.withAlpha(AWMaterialColors.colorOnSurface, 0.46)
        focusedStrokeColor = AWMaterialColors.colorPrimary
        // hintTextAppearance = TextAppearance.MaterialComponents.Caption (12 sp, 0.0333333333 em, textColorSecondary).
        collapsingTextHelper.setCollapsedTextAppearance(textColor: AWMaterialColors.textColorSecondary,
                                                        textSize: ATypedValue.applyDimension(ATypedValue.COMPLEX_UNIT_SP, 12),
                                                        letterSpacing: 0.0333333333)
        focusedTextColor = collapsingTextHelper.collapsedTextColor
        // hintTextColor = ?colorPrimary.
        setHintTextColor(AColorStateList.valueOf(AWMaterialColors.colorPrimary))
        setBoxBackgroundMode(ATextInputLayout.BOX_BACKGROUND_FILLED)
        importantForAccessibility = AView.IMPORTANT_FOR_ACCESSIBILITY_NO
        aw_overlay.owner = self
        foreground = aw_overlay
        addView(inputFrame)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: Children (TextInputLayout.addView)

    /// An EditText goes into the input frame (centred vertically) and takes the given params for the frame.
    override func addView(_ child: AView, _ index: Int, _ params: AViewGroup.LayoutParams) {
        if let edit = child as? AEditText {
            let flp = AFrameLayout.LayoutParams(params as AViewGroup.LayoutParams)
            flp.gravity = AGravity.CENTER_VERTICAL | (flp.gravity & ~AGravity.VERTICAL_GRAVITY_MASK)
            inputFrame.addView(child, flp)
            inputFrame.layoutParams = checkLayoutParams(params) ? params : generateLayoutParams(params)
            updateInputLayoutMargins()
            setEditText(edit)
        } else {
            super.addView(child, index, params)
        }
    }

    /// TextInputLayout.getEditText.
    var editText: AEditText? { return aw_editText }
    func getEditText() -> AEditText? { return aw_editText }

    private func setEditText(_ editText: AEditText) {
        precondition(aw_editText == nil, "java.lang.IllegalArgumentException: We already have an EditText, can only have one")
        aw_editText = editText
        if minWidth != ATextInputLayout.NO_WIDTH { editText.setMinWidth(minWidth) }
        if maxWidth != ATextInputLayout.NO_WIDTH { editText.setMaxWidth(maxWidth) }
        boxBackgroundApplied = false
        onApplyBoxBackgroundMode()
        collapsingTextHelper.setTypefaces(editText.typeface)
        collapsingTextHelper.setExpandedTextSize(editText.textSize)
        collapsingTextHelper.setExpandedLetterSpacing(editText.letterSpacing)
        let editTextGravity = editText.gravity
        collapsingTextHelper.setCollapsedTextGravity(AGravity.TOP | (editTextGravity & ~AGravity.VERTICAL_GRAVITY_MASK))
        collapsingTextHelper.setExpandedTextGravity(editTextGravity)
        editText.addTextChangedListener(ASimpleTextWatcher(afterTextChanged: { [weak self] _ in
            self?.updateLabelState(true)
        }))
        if defaultHintTextColor == nil {
            defaultHintTextColor = editText.hintTextColors
        }
        if hintEnabled {
            if (aw_hint ?? "").isEmpty {
                setHint(editText.aw_hint?.aw_plain)
                editText.setHint(nil as ACharSequence?)
            }
            aw_isProvidingHint = true
        }
        editText.aw_cursorColor = AWMaterialColors.colorPrimary
        editText.aw_colorsDidChange()
        if !isEnabled {
            editText.setEnabled(false)
        }
        updateLabelState(false, true)
    }

    private func updateInputLayoutMargins() {
        if aw_boxBackgroundMode != ATextInputLayout.BOX_BACKGROUND_FILLED,
           let lp = inputFrame.layoutParams as? AViewGroup.MarginLayoutParams {
            let newTopMargin = calculateLabelMarginTop()
            if newTopMargin != lp.topMargin {
                lp.topMargin = newTopMargin
                inputFrame.requestLayout()
            }
        }
    }

    // MARK: Box (setBoxBackgroundMode / setBoxBackgroundColor / applyBoxAttributes)

    var boxBackgroundMode: Int {
        get { return aw_boxBackgroundMode }
        set { setBoxBackgroundMode(newValue) }
    }

    func getBoxBackgroundMode() -> Int { return aw_boxBackgroundMode }

    func setBoxBackgroundMode(_ boxBackgroundMode: Int) {
        if boxBackgroundMode == aw_boxBackgroundMode { return }
        aw_boxBackgroundMode = boxBackgroundMode
        if aw_editText != nil {
            onApplyBoxBackgroundMode()
        }
    }

    private func onApplyBoxBackgroundMode() {
        assignBoxBackgroundByMode()
        updateEditTextBoxBackgroundIfNeeded()
        updateTextInputBoxState()
        if aw_boxBackgroundMode != ATextInputLayout.BOX_BACKGROUND_NONE {
            updateInputLayoutMargins()
        }
    }

    private func assignBoxBackgroundByMode() {
        switch aw_boxBackgroundMode {
        case ATextInputLayout.BOX_BACKGROUND_FILLED:
            let bg = AWBoxBackgroundDrawable()
            bg.topCornerSize = shapeTopCornerSize
            bg.bottomCornerSize = shapeBottomCornerSize
            boxBackground = bg
            boxUnderlineDefault = AWBoxUnderlineDrawable()
            boxUnderlineFocused = AWBoxUnderlineDrawable()
        case ATextInputLayout.BOX_BACKGROUND_OUTLINE:
            let bg = AWBoxBackgroundDrawable()
            bg.topCornerSize = shapeTopCornerSize
            bg.bottomCornerSize = shapeTopCornerSize
            boxBackground = bg
            boxUnderlineDefault = nil
            boxUnderlineFocused = nil
        case ATextInputLayout.BOX_BACKGROUND_NONE:
            boxBackground = nil
            boxUnderlineDefault = nil
            boxUnderlineFocused = nil
        default:
            preconditionFailure("java.lang.IllegalArgumentException: \(aw_boxBackgroundMode) is illegal; only @BoxBackgroundMode constants are supported.")
        }
    }

    /// TextInputLayout.updateEditTextBoxBackgroundIfNeeded: the box goes on the EditText unless the EditText brought a
    /// background of its own before the box was first applied.
    func updateEditTextBoxBackgroundIfNeeded() {
        guard let e = aw_editText, let box = boxBackground else { return }
        if !boxBackgroundApplied && e.background != nil { return }
        if aw_boxBackgroundMode == ATextInputLayout.BOX_BACKGROUND_NONE { return }
        e.setBackgroundDrawable(box)
        boxBackgroundApplied = true
    }

    var boxBackgroundColor: Int {
        get { return aw_boxBackgroundColor }
        set { setBoxBackgroundColor(newValue) }
    }

    func getBoxBackgroundColor() -> Int { return aw_boxBackgroundColor }

    func setBoxBackgroundColor(_ boxBackgroundColor: Int) {
        if aw_boxBackgroundColor != boxBackgroundColor {
            aw_boxBackgroundColor = boxBackgroundColor
            defaultFilledBackgroundColor = boxBackgroundColor
            focusedFilledBackgroundColor = boxBackgroundColor
            hoveredFilledBackgroundColor = boxBackgroundColor
            applyBoxAttributes()
        }
    }

    /// calculateBoxBackgroundColor: the filled colour layered over ?colorSurface (MaterialColors.layer).
    private func calculateBoxBackgroundColor() -> Int {
        var backgroundColor = aw_boxBackgroundColor
        if aw_boxBackgroundMode == ATextInputLayout.BOX_BACKGROUND_FILLED {
            backgroundColor = ATextInputLayout.compositeColors(aw_boxBackgroundColor, AWMaterialColors.colorSurface)
        }
        return backgroundColor
    }

    /// androidx.core.graphics.ColorUtils.compositeColors.
    static func compositeColors(_ foreground: Int, _ background: Int) -> Int {
        let bgAlpha = AColor.alpha(background)
        let fgAlpha = AColor.alpha(foreground)
        let a = 0xFF - (((0xFF - bgAlpha) * (0xFF - fgAlpha)) / 0xFF)
        func component(_ fgC: Int, _ bgC: Int) -> Int {
            if a == 0 { return 0 }
            return ((0xFF * fgC * fgAlpha) + (bgC * bgAlpha * (0xFF - fgAlpha))) / (a * 0xFF)
        }
        return AColor.argb(a, component(AColor.red(foreground), AColor.red(background)),
                           component(AColor.green(foreground), AColor.green(background)),
                           component(AColor.blue(foreground), AColor.blue(background)))
    }

    private func applyBoxAttributes() {
        guard let box = boxBackground else { return }
        aw_boxBackgroundColor = calculateBoxBackgroundColor()
        box.fillColor = aw_boxBackgroundColor
        box.invalidateSelf()
        applyBoxUnderlineAttributes()
        updateEditTextBoxBackgroundIfNeeded()
    }

    private func applyBoxUnderlineAttributes() {
        guard let def = boxUnderlineDefault, let foc = boxUnderlineFocused else { return }
        if canDrawStroke() {
            def.fillColor = (aw_editText?.isFocusedSelf ?? false) ? defaultStrokeColor : boxStrokeColor
            foc.fillColor = boxStrokeColor
        }
        invalidate()
    }

    private func canDrawStroke() -> Bool {
        return boxStrokeWidthPx > -1 && boxStrokeColor != AColor.TRANSPARENT
    }

    // MARK: Hint

    var hint: String? {
        get { return getHint() }
        set { setHint(newValue) }
    }

    func getHint() -> String? { return hintEnabled ? aw_hint : nil }

    func setHint(_ hint: String?) {
        if hintEnabled {
            setHintInternal(hint)
        }
    }

    func setHint(res: AStringRes) { setHint(getString(res)) }

    private func setHintInternal(_ hint: String?) {
        if hint != aw_hint {
            aw_hint = hint
            collapsingTextHelper.setText(hint)
            invalidate()
        }
    }

    var isHintEnabled: Bool {
        get { return hintEnabled }
        set { setHintEnabled(newValue) }
    }

    func setHintEnabled(_ enabled: Bool) {
        if enabled != hintEnabled {
            hintEnabled = enabled
            if !hintEnabled {
                aw_isProvidingHint = false
                if let e = aw_editText, !(aw_hint ?? "").isEmpty, (e.aw_hint?.aw_plain ?? "").isEmpty {
                    e.setHint(aw_hint)
                }
                setHintInternal(nil)
            } else if let e = aw_editText {
                let editTextHint = e.aw_hint?.aw_plain
                if !(editTextHint ?? "").isEmpty {
                    if (aw_hint ?? "").isEmpty { setHint(editTextHint) }
                    e.setHint(nil as ACharSequence?)
                }
                aw_isProvidingHint = true
            }
            if aw_editText != nil { updateInputLayoutMargins() }
        }
    }

    func isProvidingHint() -> Bool { return aw_isProvidingHint }

    /// TextInputLayout.setHintTextColor (the focused label colour).
    func setHintTextColor(_ hintTextColor: AColorStateList?) {
        if focusedTextColor !== hintTextColor {
            if defaultHintTextColor == nil {
                collapsingTextHelper.setCollapsedTextColor(hintTextColor)
            }
            focusedTextColor = hintTextColor
            if aw_editText != nil { updateLabelState(false) }
        }
    }

    var hintTextColor: AColorStateList? {
        get { return focusedTextColor }
        set { setHintTextColor(newValue) }
    }

    var defaultHintTextColorList: AColorStateList? { return defaultHintTextColor }

    func setDefaultHintTextColor(_ textColor: AColorStateList?) {
        defaultHintTextColor = textColor
        focusedTextColor = textColor
        if aw_editText != nil { updateLabelState(false) }
    }

    var isHintAnimationEnabled: Bool {
        get { return hintAnimationEnabled }
        set { hintAnimationEnabled = newValue }
    }

    private func calculateLabelMarginTop() -> Int {
        if !hintEnabled { return 0 }
        switch aw_boxBackgroundMode {
        case ATextInputLayout.BOX_BACKGROUND_OUTLINE:
            return AWMath.javaInt(collapsingTextHelper.getCollapsedTextHeight() / 2)
        case ATextInputLayout.BOX_BACKGROUND_NONE:
            return AWMath.javaInt(collapsingTextHelper.getCollapsedTextHeight())
        default:
            return 0
        }
    }

    // MARK: Label state (updateLabelState / collapseHint / expandHint)

    func updateLabelState(_ animate: Bool) {
        updateLabelState(animate, false)
    }

    private func updateLabelState(_ animate: Bool, _ force: Bool) {
        let enabled = isEnabled
        let hasText = !(aw_editText?.text.isEmpty ?? true)
        let hasFocus = aw_editText?.hasFocus() ?? false
        if let d = defaultHintTextColor {
            collapsingTextHelper.setCollapsedAndExpandedTextColor(d)
        }
        if !enabled {
            let disabledHintColor = defaultHintTextColor?.getColorForState([-AStateSet.state_enabled], disabledColor) ?? disabledColor
            collapsingTextHelper.setCollapsedAndExpandedTextColor(AColorStateList.valueOf(disabledHintColor))
        } else if hasFocus, let f = focusedTextColor {
            collapsingTextHelper.setCollapsedTextColor(f)
        }
        if hasText || !expandedHintEnabled || (isEnabled && hasFocus) {
            if force || hintExpanded {
                collapseHint(animate)
            }
        } else {
            if force || !hintExpanded {
                expandHint(animate)
            }
        }
    }

    private func collapseHint(_ animate: Bool) {
        if let a = animator, a.isRunning { a.cancel() }
        if animate && hintAnimationEnabled {
            animateToExpansionFraction(1)
        } else {
            collapsingTextHelper.setExpansionFraction(1)
        }
        hintExpanded = false
    }

    private func expandHint(_ animate: Bool) {
        if let a = animator, a.isRunning { a.cancel() }
        if animate && hintAnimationEnabled {
            animateToExpansionFraction(0)
        } else {
            collapsingTextHelper.setExpansionFraction(0)
        }
        hintExpanded = true
    }

    private func animateToExpansionFraction(_ target: Float) {
        if collapsingTextHelper.getExpansionFraction() == target { return }
        if animator == nil {
            let a = AValueAnimator()
            a.interpolator = AWAnimationUtils.FAST_OUT_SLOW_IN_INTERPOLATOR
            a.setDuration(ATextInputLayout.LABEL_SCALE_ANIMATION_DURATION)
            a.addUpdateListener { [weak self] anim in
                self?.collapsingTextHelper.setExpansionFraction(anim.animatedValueFloat)
            }
            animator = a
        }
        animator!.setFloatValues(collapsingTextHelper.getExpansionFraction(), target)
        animator!.start()
    }

    // MARK: State (addStatesFromChildren, drawableStateChanged, updateTextInputBoxState)

    /// ViewGroup.onCreateDrawableState with FLAG_ADD_STATES_FROM_CHILDREN (setAddStatesFromChildren(true)): the
    /// children's states are merged in.
    override func onCreateDrawableState(_ extraSpace: Int) -> [Int] {
        var state = super.onCreateDrawableState(extraSpace)
        for child in children {
            state = AView.mergeDrawableStates(state, child.drawableState)
        }
        return state
    }

    /// ViewGroup.childDrawableStateChanged (addStatesFromChildren): the layout's state follows its children.
    override func childDrawableStateChanged(_ child: AView) {
        refreshDrawableState()
    }

    override func drawableStateChanged() {
        if inDrawableStateChanged { return }
        inDrawableStateChanged = true
        super.drawableStateChanged()
        let state = drawableState
        var changed = false
        changed = collapsingTextHelper.setState(state) || changed
        if aw_editText != nil {
            updateLabelState(isLaidOut && isEnabled)
        }
        updateTextInputBoxState()
        if changed { invalidate() }
        inDrawableStateChanged = false
    }

    /// View.isHovered (touch screens never hover).
    private var aw_isHovered: Bool { return false }

    func updateTextInputBoxState() {
        guard boxBackground != nil, aw_boxBackgroundMode != ATextInputLayout.BOX_BACKGROUND_NONE else { return }
        let hasFocus = isFocusedSelf || (aw_editText?.hasFocus() ?? false)
        let isHovered = aw_isHovered
        if !isEnabled {
            boxStrokeColor = disabledColor
        } else if hasFocus {
            boxStrokeColor = focusedStrokeColor
        } else if isHovered {
            boxStrokeColor = hoveredStrokeColor
        } else {
            boxStrokeColor = defaultStrokeColor
        }
        if aw_boxBackgroundMode == ATextInputLayout.BOX_BACKGROUND_OUTLINE {
            boxStrokeWidthPx = hasFocus && isEnabled ? boxStrokeWidthFocusedPx : boxStrokeWidthDefaultPx
        }
        if aw_boxBackgroundMode == ATextInputLayout.BOX_BACKGROUND_FILLED {
            if !isEnabled {
                aw_boxBackgroundColor = disabledFilledBackgroundColor
            } else if isHovered && !hasFocus {
                aw_boxBackgroundColor = hoveredFilledBackgroundColor
            } else if hasFocus {
                aw_boxBackgroundColor = focusedFilledBackgroundColor
            } else {
                aw_boxBackgroundColor = defaultFilledBackgroundColor
            }
        }
        applyBoxAttributes()
    }

    /// TextInputLayout.setEnabled: the children follow (addStatesFromChildren would otherwise keep them enabled).
    override func setEnabled(_ enabled: Bool) {
        ATextInputLayout.recursiveSetEnabled(self, enabled)
        super.setEnabled(enabled)
    }

    private static func recursiveSetEnabled(_ vg: AViewGroup, _ enabled: Bool) {
        for child in vg.children {
            child.setEnabled(enabled)
            if let g = child as? AViewGroup { recursiveSetEnabled(g, enabled) }
        }
    }

    // MARK: Layout and drawing

    override func onLayout(_ changed: Bool, _ l: Int, _ t: Int, _ r: Int, _ b: Int) {
        super.onLayout(changed, l, t, r, b)
        guard let e = aw_editText else { return }
        let rect = tmpRect
        aw_descendantRect(e, rect)
        updateBoxUnderlineBounds(rect)
        if hintEnabled {
            collapsingTextHelper.setExpandedTextSize(e.textSize)
            let editTextGravity = e.gravity
            collapsingTextHelper.setCollapsedTextGravity(AGravity.TOP | (editTextGravity & ~AGravity.VERTICAL_GRAVITY_MASK))
            collapsingTextHelper.setExpandedTextGravity(editTextGravity)
            collapsingTextHelper.setCollapsedBounds(calculateCollapsedTextBounds(rect))
            collapsingTextHelper.setExpandedBounds(calculateExpandedTextBounds(rect))
            collapsingTextHelper.recalculate()
        }
        aw_overlay.setBounds(0, 0, width, height)
    }

    /// DescendantOffsetUtils.getDescendantRect: the descendant's bounds in this view's coordinates.
    private func aw_descendantRect(_ descendant: AView, _ out: ARect) {
        var x = 0, y = 0
        var v: AView? = descendant
        while let cur = v, cur !== self {
            x += cur.left - cur.scrollX
            y += cur.top - cur.scrollY
            v = cur.parentGroup
        }
        out.set(x, y, x + descendant.width, y + descendant.height)
    }

    private func updateBoxUnderlineBounds(_ bounds: ARect) {
        if let d = boxUnderlineDefault {
            let top = bounds.bottom - boxStrokeWidthDefaultPx
            d.setBounds(bounds.left, top, bounds.right, bounds.bottom)
        }
        if let f = boxUnderlineFocused {
            let top = bounds.bottom - boxStrokeWidthFocusedPx
            f.setBounds(bounds.left, top, bounds.right, bounds.bottom)
        }
    }

    private func calculateCollapsedTextBounds(_ rect: ARect) -> ARect {
        guard let e = aw_editText else { preconditionFailure("java.lang.IllegalStateException") }
        let bounds = tmpBoundsRect
        bounds.bottom = rect.bottom
        switch aw_boxBackgroundMode {
        case ATextInputLayout.BOX_BACKGROUND_OUTLINE:
            bounds.left = rect.left + e.paddingLeft
            bounds.top = rect.top - calculateLabelMarginTop()
            bounds.right = rect.right - e.paddingRight
        case ATextInputLayout.BOX_BACKGROUND_FILLED:
            bounds.left = rect.left + e.compoundPaddingLeft
            bounds.top = rect.top + boxCollapsedPaddingTopPx
            bounds.right = rect.right - e.compoundPaddingRight
        default:
            bounds.left = rect.left + e.compoundPaddingLeft
            bounds.top = paddingTop
            bounds.right = rect.right - e.compoundPaddingRight
        }
        return bounds
    }

    private func calculateExpandedTextBounds(_ rect: ARect) -> ARect {
        guard let e = aw_editText else { preconditionFailure("java.lang.IllegalStateException") }
        let bounds = tmpBoundsRect
        let labelHeight = collapsingTextHelper.getExpandedTextHeight()
        bounds.left = rect.left + e.compoundPaddingLeft
        bounds.top = calculateExpandedLabelTop(rect, labelHeight)
        bounds.right = rect.right - e.compoundPaddingRight
        bounds.bottom = calculateExpandedLabelBottom(rect, bounds, labelHeight)
        return bounds
    }

    private func isSingleLineFilledTextField() -> Bool {
        return aw_boxBackgroundMode == ATextInputLayout.BOX_BACKGROUND_FILLED && (aw_editText?.minLines ?? 0) <= 1
    }

    private func calculateExpandedLabelTop(_ rect: ARect, _ labelHeight: Float) -> Int {
        if isSingleLineFilledTextField() {
            return AWMath.javaInt(Float(rect.centerY()) - labelHeight / 2)
        }
        return rect.top + (aw_editText?.compoundPaddingTop ?? 0)
    }

    private func calculateExpandedLabelBottom(_ rect: ARect, _ bounds: ARect, _ labelHeight: Float) -> Int {
        if isSingleLineFilledTextField() {
            return AWMath.javaInt(Float(bounds.top) + labelHeight)
        }
        return rect.bottom - (aw_editText?.compoundPaddingBottom ?? 0)
    }

    /// TextInputLayout.draw after super.draw: drawHint, then drawBoxUnderline.
    func aw_drawOverlay(_ canvas: ACanvas) {
        if hintEnabled {
            collapsingTextHelper.draw(canvas)
        }
        guard let def = boxUnderlineDefault, let foc = boxUnderlineFocused, let e = aw_editText else { return }
        def.draw(canvas)
        if e.isFocusedSelf {
            let focusedUnderlineBounds = foc.bounds
            let defaultUnderlineBounds = def.bounds
            let hintExpansionFraction = collapsingTextHelper.getExpansionFraction()
            let midpointX = defaultUnderlineBounds.centerX()
            let left = AWAnimationUtils.lerp(midpointX, defaultUnderlineBounds.left, hintExpansionFraction)
            let right = AWAnimationUtils.lerp(midpointX, defaultUnderlineBounds.right, hintExpansionFraction)
            foc.setBounds(left, focusedUnderlineBounds.top, right, focusedUnderlineBounds.bottom)
            foc.draw(canvas)
        }
    }

    override func getBaseline() -> Int {
        if let e = aw_editText {
            return e.getBaseline() + paddingTop + calculateLabelMarginTop()
        }
        return super.getBaseline()
    }
}

// MARK: - Switch drawables (switch_track_material, switch_thumb_material_anim)

/// switch_track_material: a 14 dp rectangle with 7 dp corners, 4 dp in from both ends, centred vertically, white at
/// 30 % (white_disabled_material) tinted SRC_IN with switch_track_material (colorForeground, colorControlActivated when
/// checked, colorForeground at disabledAlpha when disabled), or the Switch's track tint.
final class AWSwitchTrackDrawable: ADrawable {
    var tintList: AColorStateList? = AWMaterialColors.switchTrack
    private let aw_paint = APaint(APaint.ANTI_ALIAS_FLAG)

    override var isStateful: Bool { return true }
    override func onStateChange(_ state: [Int]) -> Bool { return true }
    override var intrinsicHeight: Int { return aw_dpx(14) }
    override var intrinsicWidth: Int { return -1 }

    override func setTintList(_ l: AColorStateList?) {
        tintList = l
        invalidateSelf()
    }

    override func draw(_ canvas: ACanvas) {
        let b = bounds
        let h = aw_dpx(14)
        let top = b.top + (b.height() - h) / 2
        let left = b.left + aw_dpx(4), right = b.right - aw_dpx(4)
        if right <= left { return }
        let source = argbInt(0x4DFFFFFF)
        var color = source
        if let t = tintList {
            let tint = t.getColorForState(state, t.defaultColor)
            // SRC_IN: the tint colour with the source's alpha.
            color = AWMaterialColors.withAlpha(tint, Float(AColor.alpha(source)) / 255)
        }
        aw_paint.style = .FILL
        aw_paint.color = color
        aw_paint.alpha = AColor.alpha(color) * alpha / 255
        let r = Float(aw_dpx(7))
        canvas.drawRoundRect(ARectF(Float(left), Float(top), Float(right), Float(top + h)), r, r, aw_paint)
    }
}

/// switch_thumb_material_anim: the btn_switch_to_on/off nine-patches (a 20 dp disc with a soft shadow in a 27 dp box,
/// 11 / 7 px padding and optical insets at xxhdpi / xhdpi) tinted MULTIPLY with colorSwitchThumbNormal (#F1F1F1,
/// disabled #BDBDBD) or colorControlActivated when checked; a checked change plays the 12-frame, 15 ms transition (the
/// disc shrinks to 90 % and grows back, the tint switches at frame 7). The disc and its shadow are drawn as vectors with
/// the frames' measured sizes.
final class AWSwitchThumbDrawable: ADrawable {
    /// The disc diameter of each transition frame relative to the static frame (both directions, measured from the
    /// framework images).
    private static let FRAME_SCALE: [Float] = [1.0, 0.9946, 0.9563, 0.9240, 0.9058, 0.9011, 0.9001, 0.9063, 0.9443, 0.9762, 0.9955, 1.0]
    private static let FRAME_DURATION: Int64 = 15

    var tintList: AColorStateList?
    private var aw_checked = false
    private var aw_enabled = true
    private var aw_transitionStart: Int64 = -1
    private var aw_transitionFromChecked = false
    private let aw_paint = APaint(APaint.ANTI_ALIAS_FLAG)

    /// The bucket geometry: (density, size, padding).
    private static var geometry: (density: Int, size: Int, padding: Int) {
        return AWidgetEnv.density >= 2.5 ? (3, 81, 11) : (2, 54, 7)
    }

    override var isStateful: Bool { return true }

    override var intrinsicWidth: Int {
        let g = AWSwitchThumbDrawable.geometry
        return AWMath.round(Float(g.size) * AWidgetEnv.density / Float(g.density))
    }

    override var intrinsicHeight: Int { return intrinsicWidth }

    override func getPadding(_ r: ARect) -> Bool {
        let g = AWSwitchThumbDrawable.geometry
        let p = AWMath.round(Float(g.padding) * AWidgetEnv.density / Float(g.density))
        r.set(p, p, p, p)
        return true
    }

    /// NinePatchDrawable.getOpticalInsets (the red layout-bounds marks).
    var opticalInset: Int {
        let g = AWSwitchThumbDrawable.geometry
        return AWMath.round(Float(g.padding) * AWidgetEnv.density / Float(g.density))
    }

    override func setTintList(_ l: AColorStateList?) {
        tintList = l
        invalidateSelf()
    }

    override func onStateChange(_ state: [Int]) -> Bool {
        let checked = state.contains(AStateSet.state_checked)
        let enabled = state.contains(AStateSet.state_enabled)
        var changed = false
        if enabled != aw_enabled {
            aw_enabled = enabled
            aw_transitionStart = -1
            changed = true
        }
        if checked != aw_checked {
            if aw_enabled {
                aw_transitionFromChecked = aw_checked
                aw_transitionStart = ASystemClock.uptimeMillis()
            }
            aw_checked = checked
            changed = true
        }
        return changed
    }

    /// AnimatedStateListDrawable.jumpToCurrentState.
    override func jumpToCurrentState() {
        aw_transitionStart = -1
        invalidateSelf()
    }

    override func draw(_ canvas: ACanvas) {
        let b = bounds
        let pad = ARect()
        _ = getPadding(pad)
        let innerW = b.width() - pad.left - pad.right
        let innerH = b.height() - pad.top - pad.bottom
        if innerW <= 0 || innerH <= 0 { return }
        var frameScale: Float = 1
        var checkedLook = aw_checked
        if aw_transitionStart >= 0 {
            let elapsed = ASystemClock.uptimeMillis() - aw_transitionStart
            let frame = Int(elapsed / AWSwitchThumbDrawable.FRAME_DURATION)
            if frame >= AWSwitchThumbDrawable.FRAME_SCALE.count {
                aw_transitionStart = -1
            } else {
                frameScale = AWSwitchThumbDrawable.FRAME_SCALE[frame]
                checkedLook = frame < 6 ? aw_transitionFromChecked : aw_checked
                callbackView?.postInvalidateOnAnimation()
            }
        }
        let thumbColor: Int
        if let t = tintList {
            thumbColor = t.getColorForState(state, t.defaultColor)
        } else if !aw_enabled {
            thumbColor = argbInt(0xFFBDBDBD)
        } else if checkedLook {
            thumbColor = AWMaterialColors.colorControlActivated
        } else {
            thumbColor = argbInt(0xFFF1F1F1)
        }
        // MULTIPLY of the image's #FAFAFA disc.
        let disc = AColor.argb(255, AColor.red(thumbColor) * 250 / 255, AColor.green(thumbColor) * 250 / 255,
                               AColor.blue(thumbColor) * 250 / 255)
        let cx = Float(b.left) + Float(b.width()) / 2
        let cy = Float(b.top) + Float(b.height()) / 2
        let radius = Float(Swift.min(innerW, innerH)) / 2 * frameScale
        aw_paint.style = .FILL
        aw_paint.color = disc
        aw_paint.alpha = alpha
        let d = AWidgetEnv.density
        aw_paint.setShadowLayer(1.0 * d, 0, 0.75 * d, AColor.argb(AWMath.javaInt(Float(70) * Float(alpha) / 255), 0, 0, 0))
        canvas.drawCircle(cx, cy, radius, aw_paint)
        aw_paint.clearShadowLayer()
    }
}

// MARK: - android.widget.Switch

/// android.widget.Switch (Widget.Material.Light.CompoundButton.Switch): the text at the start, the switch (track and
/// thumb) at the end; the thumb slides in 250 ms (ObjectAnimator THUMB_POS) and can be dragged.
class ASwitch: ACompoundButton {
    private static let THUMB_ANIMATION_DURATION: Int64 = 250
    private static let TOUCH_MODE_IDLE = 0, TOUCH_MODE_DOWN = 1, TOUCH_MODE_DRAGGING = 2

    private var mThumbDrawable: AWSwitchThumbDrawable? = AWSwitchThumbDrawable()
    private var mTrackDrawable: AWSwitchTrackDrawable? = AWSwitchTrackDrawable()
    private var mThumbTintList: AColorStateList?
    private var mTrackTintList: AColorStateList?
    private var mSwitchMinWidth = 0
    private var mSwitchPadding = 0
    private var mShowText = false
    private var mTextOn: String = "ON"
    private var mTextOff: String = "OFF"
    private var mTouchMode = ASwitch.TOUCH_MODE_IDLE
    private var mTouchSlop = 0
    private var mTouchX: Float = 0
    private var mTouchY: Float = 0
    private let mVelocityTracker = AVelocityTracker.obtain()
    private var mMinFlingVelocity = 0
    private var mThumbPosition: Float = 0
    private var mSwitchWidth = 0
    private var mSwitchHeight = 0
    private var mThumbWidth = 0
    private var mSwitchLeft = 0
    private var mSwitchTop = 0
    private var mSwitchRight = 0
    private var mSwitchBottom = 0
    private var mPositionAnimator: AValueAnimator?
    private let mTempRect = ARect()

    override init() {
        super.init()
        aw_configureSwitch()
    }

    override init(style: Style) {
        super.init(style: style)
        aw_configureSwitch()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func aw_configureSwitch() {
        mThumbDrawable?.callbackView = self
        mTrackDrawable?.callbackView = self
        let config = AViewConfiguration.get()
        mTouchSlop = config.scaledTouchSlop
        mMinFlingVelocity = config.scaledMinimumFlingVelocity
        // Widget.Material.Light.CompoundButton.Switch: textAppearance ?textAppearance (14 sp), textColorPrimaryDisableOnly.
        isClickable = true
        isFocusable = true
        refreshDrawableState()
        setChecked(isChecked)
    }

    // MARK: Attributes

    var switchPadding: Int {
        get { return mSwitchPadding }
        set { mSwitchPadding = newValue; requestLayout() }
    }

    func setSwitchPadding(_ pixels: Int) { switchPadding = pixels }

    var switchMinWidth: Int {
        get { return mSwitchMinWidth }
        set { mSwitchMinWidth = newValue; requestLayout() }
    }

    var showText: Bool {
        get { return mShowText }
        set { if mShowText != newValue { mShowText = newValue; requestLayout() } }
    }

    var textOn: String {
        get { return mTextOn }
        set { mTextOn = newValue; requestLayout() }
    }

    var textOff: String {
        get { return mTextOff }
        set { mTextOff = newValue; requestLayout() }
    }

    var thumbTintList: AColorStateList? {
        get { return mThumbTintList }
        set { mThumbTintList = newValue; mThumbDrawable?.setTintList(newValue) }
    }

    var trackTintList: AColorStateList? {
        get { return mTrackTintList }
        set { mTrackTintList = newValue; mTrackDrawable?.setTintList(newValue ?? AWMaterialColors.switchTrack) }
    }

    // MARK: Checked state and thumb animation

    override func setChecked(_ checked: Bool) {
        super.setChecked(checked)
        let realChecked = isChecked
        if isAttachedToWindow && isLaidOut {
            animateThumbToCheckedState(realChecked)
        } else {
            cancelPositionAnimator()
            setThumbPosition(realChecked ? 1 : 0)
        }
    }

    override func toggle() {
        setChecked(!isChecked)
    }

    private func animateThumbToCheckedState(_ newCheckedState: Bool) {
        let targetPosition: Float = newCheckedState ? 1 : 0
        // ObjectAnimator.setAutoCancel(true): a new animation of THUMB_POS replaces the running one.
        mPositionAnimator?.cancel()
        let a = AValueAnimator.ofFloat(mThumbPosition, targetPosition)
        a.setDuration(ASwitch.THUMB_ANIMATION_DURATION)
        a.addUpdateListener { [weak self] anim in
            self?.setThumbPosition(anim.animatedValueFloat)
        }
        mPositionAnimator = a
        a.start()
    }

    private func cancelPositionAnimator() {
        mPositionAnimator?.cancel()
    }

    private func getTargetCheckedState() -> Bool {
        return mThumbPosition > 0.5
    }

    private func setThumbPosition(_ position: Float) {
        mThumbPosition = position
        invalidate()
    }

    // MARK: Measure and layout

    override func onMeasure(_ widthMeasureSpec: Int, _ heightMeasureSpec: Int) {
        let padding = mTempRect
        let thumbWidth: Int
        let thumbHeight: Int
        if let t = mThumbDrawable {
            _ = t.getPadding(padding)
            thumbWidth = t.intrinsicWidth - padding.left - padding.right
            thumbHeight = t.intrinsicHeight
        } else {
            thumbWidth = 0
            thumbHeight = 0
        }
        var maxTextWidth = 0
        if mShowText {
            let p = APaint(paint)
            maxTextWidth = Swift.max(AWMath.ceil(p.measureText(mTextOn)), AWMath.ceil(p.measureText(mTextOff)))
        }
        mThumbWidth = Swift.max(maxTextWidth, thumbWidth)
        let trackHeight: Int
        if let tr = mTrackDrawable {
            _ = tr.getPadding(padding)
            trackHeight = tr.intrinsicHeight
        } else {
            padding.setEmpty()
            trackHeight = 0
        }
        var paddingLeft = padding.left
        var paddingRight = padding.right
        if let t = mThumbDrawable {
            paddingLeft = Swift.max(paddingLeft, t.opticalInset)
            paddingRight = Swift.max(paddingRight, t.opticalInset)
        }
        let switchWidth = Swift.max(mSwitchMinWidth, 2 * mThumbWidth + paddingLeft + paddingRight)
        let switchHeight = Swift.max(trackHeight, thumbHeight)
        mSwitchWidth = switchWidth
        mSwitchHeight = switchHeight
        super.onMeasure(widthMeasureSpec, heightMeasureSpec)
        let measuredHeight = self.measuredHeight
        if measuredHeight < switchHeight {
            setMeasuredDimension(measuredWidthAndState, switchHeight)
        }
    }

    override func onLayout(_ changed: Bool, _ left: Int, _ top: Int, _ right: Int, _ bottom: Int) {
        super.onLayout(changed, left, top, right, bottom)
        var opticalInsetLeft = 0
        var opticalInsetRight = 0
        if let t = mThumbDrawable {
            let trackPadding = mTempRect
            if let tr = mTrackDrawable { _ = tr.getPadding(trackPadding) } else { trackPadding.setEmpty() }
            opticalInsetLeft = Swift.max(0, t.opticalInset - trackPadding.left)
            opticalInsetRight = Swift.max(0, t.opticalInset - trackPadding.right)
        }
        let switchRight: Int
        let switchLeft: Int
        if isLayoutRtl {
            switchLeft = paddingLeft + opticalInsetLeft
            switchRight = switchLeft + mSwitchWidth - opticalInsetLeft - opticalInsetRight
        } else {
            switchRight = width - paddingRight - opticalInsetRight
            switchLeft = switchRight - mSwitchWidth + opticalInsetLeft + opticalInsetRight
        }
        let switchTop: Int
        let switchBottom: Int
        switch gravity & AGravity.VERTICAL_GRAVITY_MASK {
        case AGravity.CENTER_VERTICAL:
            switchTop = (paddingTop + height - paddingBottom) / 2 - mSwitchHeight / 2
            switchBottom = switchTop + mSwitchHeight
        case AGravity.BOTTOM:
            switchBottom = height - paddingBottom
            switchTop = switchBottom - mSwitchHeight
        default:
            switchTop = paddingTop
            switchBottom = switchTop + mSwitchHeight
        }
        mSwitchLeft = switchLeft
        mSwitchTop = switchTop
        mSwitchBottom = switchBottom
        mSwitchRight = switchRight
    }

    /// Switch.getCompoundPaddingLeft / Right: the switch's width (plus switchPadding when there is text) on its side.
    override var compoundPaddingLeft: Int {
        if !isLayoutRtl { return super.compoundPaddingLeft }
        var padding = super.compoundPaddingLeft + mSwitchWidth
        if !text.isEmpty { padding += mSwitchPadding }
        return padding
    }

    override var compoundPaddingRight: Int {
        if isLayoutRtl { return super.compoundPaddingRight }
        var padding = super.compoundPaddingRight + mSwitchWidth
        if !text.isEmpty { padding += mSwitchPadding }
        return padding
    }

    // MARK: Drawing (Switch.draw / onDraw)

    private func getThumbOffset() -> Int {
        let thumbPosition = isLayoutRtl ? 1 - mThumbPosition : mThumbPosition
        return AWMath.javaInt(thumbPosition * Float(getThumbScrollRange()) + 0.5)
    }

    private func getThumbScrollRange() -> Int {
        guard let tr = mTrackDrawable else { return 0 }
        let padding = mTempRect
        _ = tr.getPadding(padding)
        let inset = mThumbDrawable?.opticalInset ?? 0
        return mSwitchWidth - mThumbWidth - padding.left - padding.right - inset - inset
    }

    /// Switch.draw: the track and thumb bounds for this frame.
    private func aw_layoutSwitchDrawables() {
        let padding = mTempRect
        var thumbInitialLeft = mSwitchLeft + getThumbOffset()
        let inset = mThumbDrawable?.opticalInset ?? 0
        if let tr = mTrackDrawable {
            _ = tr.getPadding(padding)
            thumbInitialLeft += padding.left
            var trackLeft = mSwitchLeft
            let trackTop = mSwitchTop
            var trackRight = mSwitchRight
            let trackBottom = mSwitchBottom
            if inset != 0 {
                if inset > padding.left { trackLeft -= inset - padding.left }
                if inset > padding.right { trackRight += inset - padding.right }
            }
            tr.setBounds(trackLeft, trackTop, trackRight, trackBottom)
        }
        if let t = mThumbDrawable {
            _ = t.getPadding(padding)
            let thumbLeft = thumbInitialLeft - padding.left
            let thumbRight = thumbInitialLeft + mThumbWidth + padding.right
            t.setBounds(thumbLeft, mSwitchTop, thumbRight, mSwitchBottom)
        }
    }

    override func onDraw(_ canvas: ACanvas) {
        aw_layoutSwitchDrawables()
        super.onDraw(canvas)
        mTrackDrawable?.draw(canvas)
        let saveCount = canvas.save()
        mThumbDrawable?.draw(canvas)
        canvas.restoreToCount(saveCount)
    }

    override func drawableStateChanged() {
        super.drawableStateChanged()
        let state = drawableState
        var changed = false
        if let t = mThumbDrawable, t.isStateful { changed = t.setState(state) || changed }
        if let tr = mTrackDrawable, tr.isStateful { changed = tr.setState(state) || changed }
        if changed { invalidate() }
    }

    override func verifyDrawable(_ who: ADrawable) -> Bool {
        return super.verifyDrawable(who) || who === mThumbDrawable || who === mTrackDrawable
    }

    /// View.onAttachedToWindow -> jumpDrawablesToCurrentState: no thumb transition for the state set before attach;
    /// Switch.jumpDrawablesToCurrentState ends a running thumb animation.
    override func onAttachedToWindow() {
        super.onAttachedToWindow()
        mThumbDrawable?.jumpToCurrentState()
        mTrackDrawable?.jumpToCurrentState()
        if let a = mPositionAnimator, a.isStarted {
            a.end()
            mPositionAnimator = nil
        }
    }

    // MARK: Touch (Switch.onTouchEvent: the thumb can be dragged)

    private func hitThumb(_ x: Float, _ y: Float) -> Bool {
        guard let t = mThumbDrawable else { return false }
        let thumbOffset = getThumbOffset()
        _ = t.getPadding(mTempRect)
        let thumbTop = mSwitchTop - mTouchSlop
        let thumbLeft = mSwitchLeft + thumbOffset - mTouchSlop
        let thumbRight = thumbLeft + mThumbWidth + mTempRect.left + mTempRect.right + mTouchSlop
        let thumbBottom = mSwitchBottom + mTouchSlop
        return x > Float(thumbLeft) && x < Float(thumbRight) && y > Float(thumbTop) && y < Float(thumbBottom)
    }

    override func onTouchEvent(_ ev: AMotionEvent) -> Bool {
        mVelocityTracker.addMovement(ev)
        let action = ev.actionMasked
        switch action {
        case AMotionEvent.ACTION_DOWN:
            let x = ev.x, y = ev.y
            if isEnabled && hitThumb(x, y) {
                mTouchMode = ASwitch.TOUCH_MODE_DOWN
                mTouchX = x
                mTouchY = y
            }
        case AMotionEvent.ACTION_MOVE:
            switch mTouchMode {
            case ASwitch.TOUCH_MODE_DOWN:
                let x = ev.x, y = ev.y
                if abs(x - mTouchX) > Float(mTouchSlop) || abs(y - mTouchY) > Float(mTouchSlop) {
                    mTouchMode = ASwitch.TOUCH_MODE_DRAGGING
                    parentGroup?.requestDisallowInterceptTouchEvent(true)
                    mTouchX = x
                    mTouchY = y
                    return true
                }
            case ASwitch.TOUCH_MODE_DRAGGING:
                let x = ev.x
                let thumbScrollRange = getThumbScrollRange()
                let thumbScrollOffset = x - mTouchX
                var dPos: Float
                if thumbScrollRange != 0 {
                    dPos = thumbScrollOffset / Float(thumbScrollRange)
                } else {
                    dPos = thumbScrollOffset > 0 ? 1 : -1
                }
                if isLayoutRtl { dPos = -dPos }
                let newPos = Swift.min(Swift.max(mThumbPosition + dPos, 0), 1)
                if newPos != mThumbPosition {
                    mTouchX = x
                    setThumbPosition(newPos)
                }
                return true
            default:
                break
            }
        case AMotionEvent.ACTION_UP, AMotionEvent.ACTION_CANCEL:
            if mTouchMode == ASwitch.TOUCH_MODE_DRAGGING {
                stopDrag(ev)
                _ = super.onTouchEvent(ev)
                return true
            }
            mTouchMode = ASwitch.TOUCH_MODE_IDLE
            mVelocityTracker.clear()
        default:
            break
        }
        return super.onTouchEvent(ev)
    }

    private func cancelSuperTouch(_ ev: AMotionEvent) {
        let cancel = AMotionEvent.obtain(ev)
        cancel.setAction(AMotionEvent.ACTION_CANCEL)
        _ = super.onTouchEvent(cancel)
        cancel.recycle()
    }

    private func stopDrag(_ ev: AMotionEvent) {
        mTouchMode = ASwitch.TOUCH_MODE_IDLE
        let commitChange = ev.action == AMotionEvent.ACTION_UP && isEnabled
        let oldState = isChecked
        let newState: Bool
        if commitChange {
            mVelocityTracker.computeCurrentVelocity(1000)
            let xvel = mVelocityTracker.getXVelocity()
            if abs(xvel) > Float(mMinFlingVelocity) {
                newState = isLayoutRtl ? (xvel < 0) : (xvel > 0)
            } else {
                newState = getTargetCheckedState()
            }
        } else {
            newState = oldState
        }
        setChecked(newState)
        cancelSuperTouch(ev)
    }

    override var accessibilityValue: String? {
        get { return isChecked ? "1" : "0" }
        set { super.accessibilityValue = newValue }
    }
}
