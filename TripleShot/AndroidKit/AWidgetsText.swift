import UIKit
import CoreText

// AndroidKit widgets (VIEW-API "Widgets"; area kit-widgets): android.widget.TextView (also AppCompatTextView /
// MaterialTextView), android.util.TypedValue, android.text.TextUtils, CharSequence + spans (SpannableString and the
// character styles the app uses), android.text.TextWatcher and androidx TextViewCompat.
//
// TextView is ported from the Android 15 source (frameworks/base android15-release TextView.java): onMeasure,
// makeNewLayout / makeSingleLayout (BoringLayout or StaticLayout), checkForRelayout, getDesiredHeight,
// getVerticalOffset, getExtendedPaddingTop/Bottom, getBaseline, bringTextIntoView, onDraw, the transformation
// methods (all caps / single line are exclusive, like Android's single TransformationMethod), setText with filters
// and watchers. Text is shaped and drawn by the engine in AWidgetsTextLayout.swift (Core Text glyphs, Android line
// metrics). Sizes are Android pixels; `textSize` is set in sp and read in px.
//
// Default style (a TextView created in code or inflated from <TextView> under Theme.TripleShot): android:textViewStyle
// = Widget.AppCompat.TextView -> TextAppearance.Material.Small: 14 sp, textColorTertiary (#8A000000, disabled #24000000),
// hint textColorHint (#99000000, Android 15/16 values), highlight colorAccent @ 40 % (#66FFC83D), the theme's
// android:fontFamily "sans" (an unknown family -> Typeface.DEFAULT, Roboto Regular on Android), break strategy
// high_quality, hyphenation none, gravity top|start, includeFontPadding true. Material light colours (VIEW-API).

// MARK: - android.util.TypedValue

enum ATypedValue {
    static let COMPLEX_UNIT_PX = 0, COMPLEX_UNIT_DIP = 1, COMPLEX_UNIT_SP = 2, COMPLEX_UNIT_PT = 3,
               COMPLEX_UNIT_IN = 4, COMPLEX_UNIT_MM = 5

    /// TypedValue.applyDimension (xdpi = 160 * density; linear sp at fontScale 1).
    static func applyDimension(_ unit: Int, _ value: Float, _ metrics: ADisplayMetrics) -> Float {
        switch unit {
        case COMPLEX_UNIT_PX: return value
        case COMPLEX_UNIT_DIP: return value * metrics.density
        case COMPLEX_UNIT_SP: return value * metrics.scaledDensity
        case COMPLEX_UNIT_PT: return value * (160 * metrics.density) * (Float(1) / 72)
        case COMPLEX_UNIT_IN: return value * (160 * metrics.density)
        case COMPLEX_UNIT_MM: return value * (160 * metrics.density) * (Float(1) / Float(25.4))
        default: return 0
        }
    }

    static func applyDimension(_ unit: Int, _ value: Float) -> Float {
        let d = AWidgetEnv.density
        return applyDimension(unit, value, ADisplayMetrics(density: d, widthPixels: 0, heightPixels: 0,
                                                           scaledDensity: AWidgetEnv.scaledDensity))
    }

    /// TypedValue.complexToDimensionPixelSize: what `getDimensionPixelSize` reads from XML (textSize, padding,
    /// margins, sizes, lineSpacingExtra): rounded half away from zero, a non-zero value never becomes 0.
    static func toDimensionPixelSize(_ unit: Int, _ value: Float) -> Int {
        return toDimensionPixelSize(unit, value, ADisplayMetrics(density: AWidgetEnv.density, widthPixels: 0, heightPixels: 0,
                                                                 scaledDensity: AWidgetEnv.scaledDensity))
    }

    static func toDimensionPixelSize(_ unit: Int, _ value: Float, _ metrics: ADisplayMetrics) -> Int {
        let f = applyDimension(unit, value, metrics)
        let res = AWMath.javaInt(f >= 0 ? (f + Float(0.5)) : (f - Float(0.5)))
        if res != 0 { return res }
        if value == 0 { return 0 }
        if value > 0 { return 1 }
        return -1
    }

    /// TypedValue.complexToDimensionPixelOffset: truncated (`getDimensionPixelOffset`).
    static func toDimensionPixelOffset(_ unit: Int, _ value: Float) -> Int {
        return AWMath.javaInt(applyDimension(unit, value))
    }

    static func toDimensionPixelOffset(_ unit: Int, _ value: Float, _ metrics: ADisplayMetrics) -> Int {
        return AWMath.javaInt(applyDimension(unit, value, metrics))
    }
}

// MARK: - android.text.TextUtils

enum ATextUtils {
    enum TruncateAt { case START, MIDDLE, END, MARQUEE, END_SMALL }

    static func isEmpty(_ s: ACharSequence?) -> Bool { return s == nil || s!.aw_plain.isEmpty }
    static func isEmpty(_ s: String?) -> Bool { return s == nil || s!.isEmpty }

    static func equals(_ a: ACharSequence?, _ b: ACharSequence?) -> Bool {
        if a == nil && b == nil { return true }
        guard let a = a, let b = b else { return false }
        return a.aw_plain == b.aw_plain
    }

    /// TextUtils.getEllipsisString: "…" (U+2026), and the two-dot leader "‥" for END_SMALL (marquee fallback).
    static func getEllipsisString(_ where_: TruncateAt) -> String {
        return where_ == .END_SMALL ? "\u{2025}" : "\u{2026}"
    }

    /// TextUtils.getLayoutDirectionFromLocale.
    static func getLayoutDirectionFromLocale(_ locale: ALocale?) -> Int {
        guard let locale = locale else { return AView.LAYOUT_DIRECTION_LTR }
        return AView.isRtlLanguage(locale.language.lowercased()) ? AView.LAYOUT_DIRECTION_RTL : AView.LAYOUT_DIRECTION_LTR
    }

    /// TextUtils.couldAffectRtl.
    static func couldAffectRtl(_ c: UInt16) -> Bool { return AWBidi.couldAffectRtl(c) }
}

/// androidx.core.widget.TextViewCompat (the members the app calls).
enum ATextViewCompat {
    static let AUTO_SIZE_TEXT_TYPE_NONE = 0, AUTO_SIZE_TEXT_TYPE_UNIFORM = 1

    /// Auto-sizing is never enabled in the app (TextView and MaterialButton default NONE; Home sets NONE explicitly).
    static func setAutoSizeTextTypeWithDefaults(_ textView: ATextView, _ autoSizeTextType: Int) {}

    static func getCompoundDrawablesRelative(_ textView: ATextView) -> [ADrawable?] { return textView.compoundDrawablesRelative }

    static func setCompoundDrawablesRelative(_ textView: ATextView, _ start: ADrawable?, _ top: ADrawable?,
                                             _ end: ADrawable?, _ bottom: ADrawable?) {
        textView.setCompoundDrawablesRelative(start, top, end, bottom)
    }
}

// MARK: - CharSequence and spans

/// java.lang.CharSequence: String and ASpannableString. `toString()` and `length` (UTF-16) like Kotlin.
protocol ACharSequence {
    /// The plain text (CharSequence.toString()).
    var aw_plain: String { get }
}

extension ACharSequence {
    func toString() -> String { return aw_plain }
}

extension String: ACharSequence {
    var aw_plain: String { return self }
}

/// android.text.style.CharacterStyle: the spans TextView renders. Metric-affecting spans change the measuring paint
/// (MetricAffectingSpan.updateMeasureState); every span updates the drawing paint (updateDrawState).
class ACharacterStyle {
    init() {}
    var aw_affectsMetrics: Bool { return false }
    func aw_updateMeasureState(_ tp: APaint) {}
    func aw_updateDrawState(_ tp: APaint) {}
}

/// android.text.style.ForegroundColorSpan.
final class AForegroundColorSpan: ACharacterStyle {
    let foregroundColor: Int
    init(_ color: Int) { foregroundColor = color }
    func getForegroundColor() -> Int { return foregroundColor }
    override func aw_updateDrawState(_ tp: APaint) { tp.color = foregroundColor }
}

/// android.text.style.BackgroundColorSpan (drawn behind its glyph runs).
final class ABackgroundColorSpan: ACharacterStyle {
    let backgroundColor: Int
    init(_ color: Int) { backgroundColor = color }
    func getBackgroundColor() -> Int { return backgroundColor }
}

/// android.text.style.StyleSpan (ATypeface.BOLD / ITALIC / BOLD_ITALIC).
final class AStyleSpan: ACharacterStyle {
    let style: Int
    init(_ style: Int) { self.style = style }
    func getStyle() -> Int { return style }
    override var aw_affectsMetrics: Bool { return true }
    override func aw_updateMeasureState(_ tp: APaint) { AStyleSpan.apply(tp, style) }
    override func aw_updateDrawState(_ tp: APaint) { AStyleSpan.apply(tp, style) }

    /// StyleSpan.apply: the requested style on the paint's typeface, faked when the family lacks it.
    static func apply(_ paint: APaint, _ style: Int) {
        let old = paint.typeface
        let oldStyle = old?.style ?? 0
        let want = oldStyle | style
        let tf = old == nil ? ATypeface.defaultFromStyle(want) : ATypeface.create(old, want)
        let fake = want & ~tf.style
        if (fake & ATypeface.BOLD) != 0 { paint.isFakeBoldText = true }
        if (fake & ATypeface.ITALIC) != 0 { paint.textSkewX = -0.25 }
        paint.typeface = tf
    }
}

/// android.text.style.RelativeSizeSpan.
final class ARelativeSizeSpan: ACharacterStyle {
    let sizeChange: Float
    init(_ proportion: Float) { sizeChange = proportion }
    func getSizeChange() -> Float { return sizeChange }
    override var aw_affectsMetrics: Bool { return true }
    override func aw_updateMeasureState(_ tp: APaint) { tp.textSize = tp.textSize * sizeChange }
    override func aw_updateDrawState(_ tp: APaint) { tp.textSize = tp.textSize * sizeChange }
}

/// android.text.style.AbsoluteSizeSpan (px, or dp when `dip`).
final class AAbsoluteSizeSpan: ACharacterStyle {
    let size: Int
    let dip: Bool
    init(_ size: Int) { self.size = size; self.dip = false }
    init(_ size: Int, _ dip: Bool) { self.size = size; self.dip = dip }
    override var aw_affectsMetrics: Bool { return true }
    override func aw_updateMeasureState(_ tp: APaint) { apply(tp) }
    override func aw_updateDrawState(_ tp: APaint) { apply(tp) }
    private func apply(_ tp: APaint) { tp.textSize = dip ? Float(size) * AWidgetEnv.density : Float(size) }
}

/// android.text.style.UnderlineSpan.
final class AUnderlineSpan: ACharacterStyle {
    override func aw_updateDrawState(_ tp: APaint) { tp.isUnderlineText = true }
}

/// android.text.style.StrikethroughSpan.
final class AStrikethroughSpan: ACharacterStyle {
    override func aw_updateDrawState(_ tp: APaint) { tp.isStrikeThruText = true }
}

/// android.text.Spanned flags.
enum ASpanned {
    static let SPAN_INCLUSIVE_EXCLUSIVE = 17, SPAN_INCLUSIVE_INCLUSIVE = 18,
               SPAN_EXCLUSIVE_EXCLUSIVE = 33, SPAN_EXCLUSIVE_INCLUSIVE = 34
}

/// android.text.SpannableString: immutable text with mutable span markup (UTF-16 offsets).
final class ASpannableString: ACharSequence {
    struct SpanRecord { let span: AnyObject; let start: Int; let end: Int; let flags: Int }

    private let string: String
    private(set) var spans: [SpanRecord] = []

    /// `new SpannableString(source)`: copies the text and, for a Spanned source, its spans.
    init(_ source: ACharSequence) {
        string = source.aw_plain
        if let other = source as? ASpannableString { spans = other.spans }
    }

    var aw_plain: String { return string }
    func toString() -> String { return string }
    var length: Int { return string.utf16.count }

    /// Spannable.setSpan: replaces the span's previous range; bounds checked like SpannableStringInternal.
    func setSpan(_ what: AnyObject, _ start: Int, _ end: Int, _ flags: Int) {
        precondition(start >= 0 && end >= start && end <= string.utf16.count,
                     "java.lang.IndexOutOfBoundsException: setSpan (\(start) ... \(end)) ends beyond length \(string.utf16.count)")
        if let i = spans.firstIndex(where: { $0.span === what }) {
            spans[i] = SpanRecord(span: what, start: start, end: end, flags: flags)
        } else {
            spans.append(SpanRecord(span: what, start: start, end: end, flags: flags))
        }
    }

    func removeSpan(_ what: AnyObject) { spans.removeAll { $0.span === what } }
    func getSpanStart(_ what: AnyObject) -> Int { return spans.first { $0.span === what }?.start ?? -1 }
    func getSpanEnd(_ what: AnyObject) -> Int { return spans.first { $0.span === what }?.end ?? -1 }
    func getSpanFlags(_ what: AnyObject) -> Int { return spans.first { $0.span === what }?.flags ?? 0 }

    /// Spanned.getSpans(start, end, type): spans intersecting [start, end) (empty spans at the edges included).
    func getSpans<T>(_ start: Int, _ end: Int, _ type: T.Type) -> [T] {
        var out: [T] = []
        for r in spans {
            guard let s = r.span as? T else { continue }
            if r.start > end || r.end < start { continue }
            if r.start != r.end && start != end {
                if r.start == end || r.end == start { continue }
            }
            out.append(s)
        }
        return out
    }

    /// Spanned.nextSpanTransition (any span kind).
    func nextSpanTransition(_ start: Int, _ limit: Int) -> Int {
        var next = limit
        for r in spans {
            if r.start > start && r.start < next { next = r.start }
            if r.end > start && r.end < next { next = r.end }
        }
        return next
    }

    func charAt(_ index: Int) -> UInt16 { return Array(string.utf16)[index] }

    /// CharSequence.subSequence: a SpannableString keeping the spans clipped to the range.
    func subSequence(_ start: Int, _ end: Int) -> ASpannableString {
        let units = Array(string.utf16)
        let sub = ASpannableString(String(decoding: units[start..<end], as: UTF16.self))
        for r in spans where r.end > start && r.start < end {
            sub.spans.append(SpanRecord(span: r.span, start: max(r.start, start) - start, end: min(r.end, end) - start, flags: r.flags))
        }
        return sub
    }

    /// The same spans on another text of the same length (transformation methods that keep the length).
    fileprivate func aw_withText(_ text: String) -> ASpannableString {
        let copy = ASpannableString(text)
        copy.spans = spans
        return copy
    }
}

// MARK: - TextWatcher

/// android.text.TextWatcher (the CharSequence / Editable is passed as its String).
protocol ATextWatcher: AnyObject {
    func beforeTextChanged(_ s: String, _ start: Int, _ count: Int, _ after: Int)
    func onTextChanged(_ s: String, _ start: Int, _ before: Int, _ count: Int)
    func afterTextChanged(_ s: String)
}

extension ATextWatcher {
    func beforeTextChanged(_ s: String, _ start: Int, _ count: Int, _ after: Int) {}
    func onTextChanged(_ s: String, _ start: Int, _ before: Int, _ count: Int) {}
    func afterTextChanged(_ s: String) {}
}

/// Closure TextWatcher (androidx core-ktx doBeforeTextChanged / doOnTextChanged / doAfterTextChanged).
final class ASimpleTextWatcher: ATextWatcher {
    private let before: ((String, Int, Int, Int) -> Void)?
    private let on: ((String, Int, Int, Int) -> Void)?
    private let after: ((String) -> Void)?

    init(beforeTextChanged: ((String, Int, Int, Int) -> Void)? = nil,
         onTextChanged: ((String, Int, Int, Int) -> Void)? = nil,
         afterTextChanged: ((String) -> Void)? = nil) {
        before = beforeTextChanged
        on = onTextChanged
        after = afterTextChanged
    }

    func beforeTextChanged(_ s: String, _ start: Int, _ count: Int, _ after: Int) { before?(s, start, count, after) }
    func onTextChanged(_ s: String, _ start: Int, _ before: Int, _ count: Int) { on?(s, start, before, count) }
    func afterTextChanged(_ s: String) { after?(s) }
}

// MARK: - android.widget.TextView

/// android.widget.TextView. Sizes in px; `textSize` is set in sp and read in px (Kotlin property semantics).
class ATextView: AView {
    static let VERY_WIDE = 1024 * 1024
    /// TextView.LINES / EMS / PIXELS (max/min modes).
    static let LINES = 1, EMS = 1, PIXELS = 2
    /// TextView.MAX_LENGTH_FOR_SINGLE_LINE_EDIT_TEXT.
    static let MAX_LENGTH_FOR_SINGLE_LINE_EDIT_TEXT = 5000

    /// TextView's TransformationMethod (one at a time): AllCapsTransformationMethod, SingleLineTransformationMethod,
    /// PasswordTransformationMethod.
    enum AWTransformation { case NONE, ALL_CAPS, SINGLE_LINE, PASSWORD }

    /// BoringLayout.Metrics as TextView passes it around (UNKNOWN_BORING, null, or the boring width).
    enum AWBoring { case UNKNOWN, NOT_BORING, BORING(Int) }

    /// The TextPaint (Paint.ANTI_ALIAS_FLAG), shared with the layouts like mTextPaint.
    let paint = APaint(APaint.ANTI_ALIAS_FLAG)

    // Text
    var aw_text: ACharSequence = ""
    var aw_transformed: ACharSequence = ""
    var aw_transformation: AWTransformation = .NONE
    var aw_hint: ACharSequence?
    var aw_filters: [AInputFilter] = []
    var aw_listeners: [ATextWatcher] = []
    var aw_singleLineLengthFilter: ALengthFilter?

    // Layouts
    var aw_layout: ALayout?
    var aw_hintLayout: ALayout?
    var aw_textDir: ATextDirectionHeuristic?

    // Sizes (mMaximum / mMaxMode ... mMinWidth / mMinWidthMode)
    var aw_maximum = Int(Int32.max), aw_maxMode = ATextView.LINES
    var aw_minimum = 0, aw_minMode = ATextView.LINES
    var aw_oldMaximum = Int(Int32.max), aw_oldMaxMode = ATextView.LINES
    var aw_maxWidthValue = Int(Int32.max), aw_maxWidthMode = ATextView.PIXELS
    var aw_minWidthValue = 0, aw_minWidthMode = ATextView.PIXELS
    var aw_desiredHeightAtMeasure = -1

    // Flags
    var aw_singleLine = false
    var aw_horizontallyScrolling = false
    var aw_ellipsize: ATextUtils.TruncateAt?
    var aw_includePad = true
    var aw_spacingMult: Float = 1
    var aw_spacingAdd: Float = 0
    var aw_gravity = AGravity.TOP | AGravity.START
    var aw_breakStrategy = ALayout.BREAK_STRATEGY_HIGH_QUALITY
    var aw_hyphenationFrequency = ALayout.HYPHENATION_FREQUENCY_NONE
    var aw_justificationMode = ALayout.JUSTIFICATION_MODE_NONE

    // Colours
    var aw_textColor: AColorStateList = AColorStateList([[-AStateSet.state_enabled], []],
                                                        [argbInt(0x24000000), argbInt(0x8A000000)])
    var aw_curTextColor = argbInt(0x8A000000)
    var aw_hintTextColor: AColorStateList? = AColorStateList.valueOf(argbInt(0x99000000))
    var aw_curHintTextColor = argbInt(0x99000000)
    var aw_highlightColor = argbInt(0x66FFC83D)

    // Shadow layer (mShadowRadius / Dx / Dy / Color)
    var aw_shadowRadius: Float = 0, aw_shadowDx: Float = 0, aw_shadowDy: Float = 0, aw_shadowColor = 0

    // View.setBackgroundTintList (TintInfo of the background)
    var aw_backgroundTint: AColorStateList?
    var aw_hasBackgroundTint = false

    // Compound drawables (TextView.Drawables)
    var aw_drawableLeft: ADrawable?, aw_drawableTop: ADrawable?, aw_drawableRight: ADrawable?, aw_drawableBottom: ADrawable?
    var aw_drawableStart: ADrawable?, aw_drawableEnd: ADrawable?
    var aw_relativeDrawables = false
    var aw_drawablePadding = 0
    /// The error icon of EditText.setError (shown at the end, Editor.setErrorIcon).
    var aw_errorDrawable: ADrawable?

    /// Whether this TextView draws its text layout (an EditText's UIKit field draws the text instead).
    var aw_drawsOwnText = true
    private var aw_preDrawListener: AOnPreDrawListener?

    override init() {
        super.init()
        // Widget.AppCompat.TextView / TextAppearance.Material.Small, theme android:fontFamily "sans".
        paint.textSize = ATypedValue.applyDimension(ATypedValue.COMPLEX_UNIT_SP, 14)
        paint.typeface = ATypeface.create("sans", ATypeface.NORMAL)
        isOpaque = false
        aw_updateTextColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: Text (TextView.setText / getText)

    /// Kotlin `text`: getText().toString() / setText(CharSequence).
    var text: String {
        get { return aw_text.aw_plain }
        set { setText(newValue) }
    }

    /// TextView.getText() as the CharSequence it holds (String or ASpannableString).
    var textCharSequence: ACharSequence { return aw_text }
    func getText() -> ACharSequence { return aw_text }

    /// TextView.setText(CharSequence): literal text, even when it spells a string-resource name; string resources use
    /// setText(res:) (the @StringRes int overload).
    func setText(_ text: String) {
        aw_setText(text, notifyBefore: true)
    }

    func setText(_ text: ACharSequence?) {
        if let s = text as? String { setText(s); return }
        aw_setText(text ?? "", notifyBefore: true)
    }

    /// TextView.setText(@StringRes int).
    func setText(res: AStringRes) { aw_setText(getString(res), notifyBefore: true) }

    /// TextView.setText(CharSequence, BufferType, notifyBefore, oldlen).
    func aw_setText(_ value: ACharSequence, notifyBefore: Bool) {
        var text: ACharSequence = value
        var oldlen = 0
        for f in aw_filters {
            if let out = f.filter(text.aw_plain, 0, text.aw_plain.utf16.count, "", 0, 0) {
                text = out
            }
        }
        if notifyBefore {
            oldlen = aw_text.aw_plain.utf16.count
            aw_sendBeforeTextChanged(aw_text.aw_plain, 0, oldlen, text.aw_plain.utf16.count)
        }
        // TextUtils.stringOrSpannedString: the TextView keeps its own copy of the spans.
        if let sp = text as? ASpannableString { text = ASpannableString(sp) }
        aw_text = text
        aw_transformed = aw_transform(text)
        aw_textDidChange()
        let textLength = text.aw_plain.utf16.count
        if aw_layout != nil { aw_checkForRelayout() }
        aw_sendOnTextChanged(text.aw_plain, 0, oldlen, textLength)
        onTextChanged(text.aw_plain, 0, oldlen, textLength)
        if !aw_listeners.isEmpty { aw_sendAfterTextChanged(text.aw_plain) }
        updateAccessibility()
    }

    /// Override point (TextView.onTextChanged).
    func onTextChanged(_ text: String, _ start: Int, _ lengthBefore: Int, _ lengthAfter: Int) {}

    /// Hook for AEditText (its UIKit editor mirrors the text).
    func aw_textDidChange() {}

    func aw_sendBeforeTextChanged(_ s: String, _ start: Int, _ before: Int, _ after: Int) {
        for w in aw_listeners { w.beforeTextChanged(s, start, before, after) }
    }

    func aw_sendOnTextChanged(_ s: String, _ start: Int, _ before: Int, _ after: Int) {
        for w in aw_listeners { w.onTextChanged(s, start, before, after) }
    }

    func aw_sendAfterTextChanged(_ s: String) {
        for w in aw_listeners { w.afterTextChanged(s) }
    }

    /// The transformation method applied to `text` (mTransformation.getTransformation).
    func aw_transform(_ text: ACharSequence) -> ACharSequence {
        switch aw_transformation {
        case .NONE:
            return text
        case .ALL_CAPS:
            // AllCapsTransformationMethod: upper case in the view's locale; spans kept when the length is.
            let upper = text.aw_plain.uppercased(with: Locale(identifier: ALocale.getDefault().language))
            if let sp = text as? ASpannableString {
                return upper.utf16.count == sp.aw_plain.utf16.count ? sp.aw_withText(upper) : upper
            }
            return upper
        case .SINGLE_LINE:
            // SingleLineTransformationMethod: '\n' -> ' ', '\r' -> U+FEFF.
            let replaced = String(decoding: text.aw_plain.utf16.map { $0 == 0x0A ? 0x20 : ($0 == 0x0D ? 0xFEFF : $0) }, as: UTF16.self)
            if let sp = text as? ASpannableString { return sp.aw_withText(replaced) }
            return replaced
        case .PASSWORD:
            return String(repeating: "\u{2022}", count: text.aw_plain.utf16.count)
        }
    }

    /// TextView.setTransformationMethod: a new method re-runs setText(mText).
    func aw_setTransformation(_ method: AWTransformation) {
        if method == aw_transformation { return }
        aw_transformation = method
        aw_setText(aw_text, notifyBefore: true)
        aw_textDir = aw_textDirectionHeuristic()
    }

    /// TextView.length().
    func length() -> Int { return aw_text.aw_plain.utf16.count }

    var hint: String? {
        get { return aw_hint?.aw_plain }
        set { setHint(newValue) }
    }

    /// TextView.setHint.
    func setHint(_ hint: ACharSequence?) {
        aw_hint = hint.map { $0 is ASpannableString ? $0 : $0.aw_plain }
        if aw_layout != nil { aw_checkForRelayout() }
        if aw_text.aw_plain.isEmpty { invalidate() }
        aw_hintDidChange()
    }

    func setHint(res: AStringRes) { setHint(getString(res)) }
    func getHint() -> String? { return aw_hint?.aw_plain }

    /// Hook for AEditText.
    func aw_hintDidChange() {}

    // MARK: Text size, typeface, paint flags

    /// Kotlin `textSize`: set in sp (TextView.setTextSize(float)), read in px (getTextSize()).
    var textSize: Float {
        get { return paint.textSize }
        set { setTextSize(ATypedValue.COMPLEX_UNIT_SP, newValue) }
    }

    func getTextSize() -> Float { return paint.textSize }

    func setTextSize(_ size: Float) { setTextSize(ATypedValue.COMPLEX_UNIT_SP, size) }

    func setTextSize(_ unit: Int, _ size: Float) {
        aw_setRawTextSize(ATypedValue.applyDimension(unit, size), shouldRequestLayout: true)
    }

    /// An XML `android:textSize="15.5sp"`: TextView reads it with getDimensionPixelSize (whole pixels).
    func applyXmlTextSize(_ sp: Float) {
        aw_setRawTextSize(Float(ATypedValue.toDimensionPixelSize(ATypedValue.COMPLEX_UNIT_SP, sp)), shouldRequestLayout: true)
    }

    /// TextView.setRawTextSize.
    func aw_setRawTextSize(_ size: Float, shouldRequestLayout: Bool) {
        if size != paint.textSize {
            paint.textSize = size
            if shouldRequestLayout && aw_layout != nil {
                aw_nullLayouts()
                requestLayout()
                invalidate()
            }
            aw_styleDidChange()
        }
    }

    /// Hook for AEditText (its UIKit editor mirrors the font).
    func aw_styleDidChange() {}

    var typeface: ATypeface? {
        get { return paint.typeface }
        set { setTypeface(newValue) }
    }

    func getTypeface() -> ATypeface? { return paint.typeface }

    /// TextView.setTypeface(Typeface).
    func setTypeface(_ tf: ATypeface?) {
        if paint.typeface !== tf {
            paint.typeface = tf
            if aw_layout != nil {
                aw_nullLayouts()
                requestLayout()
                invalidate()
            }
            aw_styleDidChange()
        }
    }

    /// TextView.setTypeface(Typeface, int): the styled family; a style the family lacks is faked (bold, skew).
    func setTypeface(_ tf: ATypeface?, _ style: Int) {
        if style > 0 {
            let t = tf == nil ? ATypeface.defaultFromStyle(style) : ATypeface.create(tf, style)
            setTypeface(t)
            let typefaceStyle = t.style
            let need = style & ~typefaceStyle
            paint.isFakeBoldText = (need & ATypeface.BOLD) != 0
            paint.textSkewX = (need & ATypeface.ITALIC) != 0 ? -0.25 : 0
        } else {
            paint.isFakeBoldText = false
            paint.textSkewX = 0
            setTypeface(tf)
        }
    }

    var letterSpacing: Float {
        get { return paint.letterSpacing }
        set { setLetterSpacing(newValue) }
    }

    func getLetterSpacing() -> Float { return paint.letterSpacing }

    func setLetterSpacing(_ letterSpacing: Float) {
        if letterSpacing != paint.letterSpacing {
            paint.letterSpacing = letterSpacing
            if aw_layout != nil {
                aw_nullLayouts()
                requestLayout()
                invalidate()
            }
            aw_styleDidChange()
        }
    }

    var textScaleX: Float {
        get { return paint.textScaleX }
        set {
            if newValue != paint.textScaleX {
                paint.textScaleX = newValue
                if aw_layout != nil {
                    aw_nullLayouts()
                    requestLayout()
                    invalidate()
                }
            }
        }
    }

    var paintFlags: Int {
        get { return paint.flags }
        set { setPaintFlags(newValue) }
    }

    func getPaintFlags() -> Int { return paint.flags }

    func setPaintFlags(_ flags: Int) {
        if paint.flags != flags {
            paint.flags = flags
            if aw_layout != nil {
                aw_nullLayouts()
                requestLayout()
                invalidate()
            }
        }
    }

    func getPaint() -> APaint { return paint }

    // MARK: Colours

    func setTextColor(_ color: Int) {
        aw_textColor = AColorStateList.valueOf(color)
        aw_updateTextColors()
    }

    /// TextView.setTextColor(ColorStateList): null throws like Android.
    func setTextColor(_ colors: AColorStateList?) {
        guard let colors = colors else { preconditionFailure("java.lang.NullPointerException: setTextColor(null)") }
        aw_textColor = colors
        aw_updateTextColors()
    }

    var textColors: AColorStateList { return aw_textColor }
    func getTextColors() -> AColorStateList { return aw_textColor }
    var currentTextColor: Int { return aw_curTextColor }
    func getCurrentTextColor() -> Int { return aw_curTextColor }

    func setHintTextColor(_ color: Int) {
        aw_hintTextColor = AColorStateList.valueOf(color)
        aw_updateTextColors()
    }

    func setHintTextColor(_ colors: AColorStateList?) {
        aw_hintTextColor = colors
        aw_updateTextColors()
    }

    var hintTextColors: AColorStateList? { return aw_hintTextColor }
    var currentHintTextColor: Int { return aw_hintTextColor != nil ? aw_curHintTextColor : aw_curTextColor }

    var highlightColor: Int {
        get { return aw_highlightColor }
        set { setHighlightColor(newValue) }
    }

    func setHighlightColor(_ color: Int) {
        if aw_highlightColor != color {
            aw_highlightColor = color
            invalidate()
        }
    }

    /// TextView.updateTextColors.
    func aw_updateTextColors() {
        var inval = false
        let state = drawableState
        let color = aw_textColor.getColorForState(state, 0)
        if color != aw_curTextColor {
            aw_curTextColor = color
            inval = true
        }
        if let h = aw_hintTextColor {
            let hc = h.getColorForState(state, 0)
            if hc != aw_curHintTextColor {
                aw_curHintTextColor = hc
                if aw_text.aw_plain.isEmpty { inval = true }
            }
        }
        aw_colorsDidChange()
        if inval { invalidate() }
    }

    /// Hook for AEditText (its UIKit editor mirrors the colours).
    func aw_colorsDidChange() {}

    /// TextView.drawableStateChanged: stateful text colours and the compound drawables follow the view state.
    override func drawableStateChanged() {
        super.drawableStateChanged()
        if aw_textColor.isStateful || (aw_hintTextColor?.isStateful ?? false) {
            aw_updateTextColors()
        }
        let state = drawableState
        for dr in aw_showingDrawables() {
            if let dr = dr, dr.isStateful, dr.setState(state) { invalidateDrawable(dr) }
        }
    }

    override func verifyDrawable(_ who: ADrawable) -> Bool {
        if super.verifyDrawable(who) { return true }
        for dr in aw_showingDrawables() where dr === who { return true }
        return false
    }

    // MARK: Background tint (View.setBackgroundTintList)

    var backgroundTintList: AColorStateList? {
        get { return getBackgroundTintList() }
        set { setBackgroundTintList(newValue) }
    }

    func getBackgroundTintList() -> AColorStateList? { return aw_backgroundTint }

    /// View.setBackgroundTintList: the tint (or null) is kept and applied to this and every later background.
    func setBackgroundTintList(_ tint: AColorStateList?) {
        aw_backgroundTint = tint
        aw_hasBackgroundTint = true
        aw_applyBackgroundTint()
    }

    /// View.applyBackgroundTint.
    func aw_applyBackgroundTint() {
        if aw_hasBackgroundTint, let bg = background {
            bg.mutate()
            bg.setTintList(aw_backgroundTint)
            if bg.isStateful { bg.setState(drawableState) }
            invalidate()
        }
    }

    /// View.setBackgroundDrawable + applyBackgroundTint (the kept tint goes onto the new background).
    override func setBackgroundDrawable(_ background: ADrawable?) {
        super.setBackgroundDrawable(background)
        if aw_hasBackgroundTint { aw_applyBackgroundTint() }
    }

    // MARK: Padding (TextView.setPadding / setPaddingRelative null the layouts)

    override func setPadding(_ left: Int, _ top: Int, _ right: Int, _ bottom: Int) {
        if left != paddingLeft || right != paddingRight || top != paddingTop || bottom != paddingBottom {
            aw_nullLayouts()
        }
        super.setPadding(left, top, right, bottom)
        invalidate()
        aw_paddingDidChange()
    }

    override func setPaddingRelative(_ start: Int, _ top: Int, _ end: Int, _ bottom: Int) {
        if start != paddingStart || end != paddingEnd || top != paddingTop || bottom != paddingBottom {
            aw_nullLayouts()
        }
        super.setPaddingRelative(start, top, end, bottom)
        invalidate()
        aw_paddingDidChange()
    }

    /// Hook for AEditText.
    func aw_paddingDidChange() {}

    // MARK: Gravity, lines, sizes

    var gravity: Int {
        get { return aw_gravity }
        set { setGravity(newValue) }
    }

    func getGravity() -> Int { return aw_gravity }

    /// TextView.setGravity: START and TOP are added when the axis is unset.
    func setGravity(_ g: Int) {
        var gravity = g
        if (gravity & AGravity.RELATIVE_HORIZONTAL_GRAVITY_MASK) == 0 { gravity |= AGravity.START }
        if (gravity & AGravity.VERTICAL_GRAVITY_MASK) == 0 { gravity |= AGravity.TOP }
        var newLayout = false
        if (gravity & AGravity.RELATIVE_HORIZONTAL_GRAVITY_MASK) != (aw_gravity & AGravity.RELATIVE_HORIZONTAL_GRAVITY_MASK) {
            newLayout = true
        }
        if gravity != aw_gravity { invalidate() }
        aw_gravity = gravity
        if let layout = aw_layout, newLayout {
            let want = layout.getWidth()
            let hintWant = aw_hintLayout?.getWidth() ?? 0
            aw_makeNewLayout(want, hintWant, .UNKNOWN, .UNKNOWN, width - compoundPaddingLeft - compoundPaddingRight, true)
        }
        aw_styleDidChange()
    }

    /// Kotlin `maxLines` (getMaxLines: -1 unless the maximum is in lines).
    var maxLines: Int {
        get { return aw_maxMode == ATextView.LINES ? aw_maximum : -1 }
        set { setMaxLines(newValue) }
    }

    func getMaxLines() -> Int { return maxLines }

    func setMaxLines(_ maxLines: Int) {
        aw_maximum = maxLines
        aw_maxMode = ATextView.LINES
        requestLayout()
        invalidate()
    }

    var minLines: Int {
        get { return aw_minMode == ATextView.LINES ? aw_minimum : -1 }
        set { setMinLines(newValue) }
    }

    func setMinLines(_ minLines: Int) {
        aw_minimum = minLines
        aw_minMode = ATextView.LINES
        requestLayout()
        invalidate()
    }

    /// TextView.setLines.
    func setLines(_ lines: Int) {
        aw_maximum = lines
        aw_minimum = lines
        aw_maxMode = ATextView.LINES
        aw_minMode = ATextView.LINES
        requestLayout()
        invalidate()
    }

    /// TextView's own maximum height (px; separate from View.minimumHeight like Android).
    var maxHeight: Int {
        get { return aw_maxMode == ATextView.PIXELS ? aw_maximum : -1 }
        set { setMaxHeight(newValue) }
    }

    func setMaxHeight(_ maxPixels: Int) {
        aw_maximum = maxPixels
        aw_maxMode = ATextView.PIXELS
        requestLayout()
        invalidate()
    }

    /// Kotlin `minHeight` (TextView.setMinHeight / getMinHeight: -1 unless set in pixels).
    var minHeight: Int {
        get { return aw_minMode == ATextView.PIXELS ? aw_minimum : -1 }
        set { setMinHeight(newValue) }
    }

    func setMinHeight(_ minPixels: Int) {
        aw_minimum = minPixels
        aw_minMode = ATextView.PIXELS
        requestLayout()
        invalidate()
    }

    /// TextView.setHeight: exact height in px.
    func setHeight(_ pixels: Int) {
        aw_maximum = pixels
        aw_minimum = pixels
        aw_maxMode = ATextView.PIXELS
        aw_minMode = ATextView.PIXELS
        requestLayout()
        invalidate()
    }

    var maxWidth: Int {
        get { return aw_maxWidthMode == ATextView.PIXELS ? aw_maxWidthValue : -1 }
        set { setMaxWidth(newValue) }
    }

    func setMaxWidth(_ maxPixels: Int) {
        aw_maxWidthValue = maxPixels
        aw_maxWidthMode = ATextView.PIXELS
        requestLayout()
        invalidate()
    }

    var minWidth: Int {
        get { return aw_minWidthMode == ATextView.PIXELS ? aw_minWidthValue : -1 }
        set { setMinWidth(newValue) }
    }

    func setMinWidth(_ minPixels: Int) {
        aw_minWidthValue = minPixels
        aw_minWidthMode = ATextView.PIXELS
        requestLayout()
        invalidate()
    }

    /// TextView.setWidth: exact width in px.
    func setWidth(_ pixels: Int) {
        aw_maxWidthValue = pixels
        aw_minWidthValue = pixels
        aw_maxWidthMode = ATextView.PIXELS
        aw_minWidthMode = ATextView.PIXELS
        requestLayout()
        invalidate()
    }

    func setEms(_ ems: Int) {
        aw_maxWidthValue = ems
        aw_minWidthValue = ems
        aw_maxWidthMode = ATextView.EMS
        aw_minWidthMode = ATextView.EMS
        requestLayout()
        invalidate()
    }

    var ellipsize: ATextUtils.TruncateAt? {
        get { return aw_ellipsize }
        set { setEllipsize(newValue) }
    }

    func getEllipsize() -> ATextUtils.TruncateAt? { return aw_ellipsize }

    func setEllipsize(_ where_: ATextUtils.TruncateAt?) {
        if aw_ellipsize != where_ {
            aw_ellipsize = where_
            if aw_layout != nil {
                aw_nullLayouts()
                requestLayout()
                invalidate()
            }
        }
    }

    var includeFontPadding: Bool {
        get { return aw_includePad }
        set { setIncludeFontPadding(newValue) }
    }

    func getIncludeFontPadding() -> Bool { return aw_includePad }

    func setIncludeFontPadding(_ includepad: Bool) {
        if aw_includePad != includepad {
            aw_includePad = includepad
            if aw_layout != nil {
                aw_nullLayouts()
                requestLayout()
                invalidate()
            }
        }
    }

    /// TextView.setLineSpacing(add px, mult).
    func setLineSpacing(_ add: Float, _ mult: Float) {
        if aw_spacingAdd != add || aw_spacingMult != mult {
            aw_spacingAdd = add
            aw_spacingMult = mult
            if aw_layout != nil {
                aw_nullLayouts()
                requestLayout()
                invalidate()
            }
        }
    }

    var lineSpacingExtra: Float { return aw_spacingAdd }
    var lineSpacingMultiplier: Float { return aw_spacingMult }

    var breakStrategy: Int {
        get { return aw_breakStrategy }
        set { aw_breakStrategy = newValue; if aw_layout != nil { aw_nullLayouts(); requestLayout(); invalidate() } }
    }

    var hyphenationFrequency: Int {
        get { return aw_hyphenationFrequency }
        set { aw_hyphenationFrequency = newValue; if aw_layout != nil { aw_nullLayouts(); requestLayout(); invalidate() } }
    }

    var isSingleLine: Bool { return aw_singleLine }

    func setSingleLine() { setSingleLine(true) }

    /// TextView.setSingleLine(boolean): setInputTypeSingleLine, then applySingleLine(singleLine, true, true, true).
    func setSingleLine(_ singleLine: Bool) {
        aw_setInputTypeSingleLine(singleLine)
        aw_applySingleLine(singleLine, applyTransformation: true, changeMaxLines: true, changeMaxLength: true)
    }

    /// An XML `android:singleLine`: TextView's constructor applies it without the length filter, and a non-editable
    /// single-line TextView without android:ellipsize gets END.
    func applyXmlSingleLine(_ singleLine: Bool, hasXmlEllipsize: Bool = false) {
        aw_setInputTypeSingleLine(singleLine)
        aw_applySingleLine(singleLine, applyTransformation: singleLine, changeMaxLines: singleLine, changeMaxLength: false)
        if singleLine && !aw_isEditable && !hasXmlEllipsize { setEllipsize(.END) }
    }

    /// Hook for AEditText (EditorInfo multi-line flag).
    func aw_setInputTypeSingleLine(_ singleLine: Bool) {}

    /// TextView.applySingleLine.
    func aw_applySingleLine(_ singleLine: Bool, applyTransformation: Bool, changeMaxLines: Bool, changeMaxLength: Bool) {
        aw_singleLine = singleLine
        if singleLine {
            setLines(1)
            setHorizontallyScrolling(true)
            if applyTransformation { aw_setTransformation(.SINGLE_LINE) }
            if !changeMaxLength || !aw_isEditable { aw_singleLineDidChange(); return }
            if aw_filters.contains(where: { $0 is ALengthFilter }) { aw_singleLineDidChange(); return }
            if aw_singleLineLengthFilter == nil {
                aw_singleLineLengthFilter = ALengthFilter(ATextView.MAX_LENGTH_FOR_SINGLE_LINE_EDIT_TEXT)
            }
            setFilters(aw_filters + [aw_singleLineLengthFilter!])
            aw_setText(aw_text, notifyBefore: true)
        } else {
            if changeMaxLines { setMaxLines(Int(Int32.max)) }
            setHorizontallyScrolling(false)
            if applyTransformation { aw_setTransformation(.NONE) }
            if changeMaxLength && aw_isEditable, let f = aw_singleLineLengthFilter,
               let i = aw_filters.firstIndex(where: { $0 === f }) {
                var filters = aw_filters
                filters.remove(at: i)
                setFilters(filters)
                aw_singleLineLengthFilter = nil
            }
        }
        aw_singleLineDidChange()
    }

    /// Hook for AEditText (UITextField vs UITextView).
    func aw_singleLineDidChange() {}

    func setHorizontallyScrolling(_ whether: Bool) {
        if aw_horizontallyScrolling != whether {
            aw_horizontallyScrolling = whether
            if aw_layout != nil {
                aw_nullLayouts()
                requestLayout()
                invalidate()
            }
        }
    }

    /// Kotlin `isAllCaps` (AppCompat keeps the flag; Android infers it from the transformation method).
    var isAllCaps: Bool {
        get { return aw_transformation == .ALL_CAPS }
        set { setAllCaps(newValue) }
    }

    /// TextView.setAllCaps: `setTransformationMethod(allCaps ? AllCapsTransformationMethod : null)`. Like Android,
    /// setAllCaps(false) removes whatever transformation is set (a single-line one too), not only all caps.
    func setAllCaps(_ allCaps: Bool) {
        aw_setTransformation(allCaps ? .ALL_CAPS : .NONE)
    }

    var filters: [AInputFilter] {
        get { return aw_filters }
        set { setFilters(newValue) }
    }

    func getFilters() -> [AInputFilter] { return aw_filters }

    /// TextView.setFilters: the filters apply to later edits and setText calls (not to the current text).
    func setFilters(_ filters: [AInputFilter]) {
        aw_filters = filters
        aw_filtersDidChange()
    }

    /// Hook for AEditText.
    func aw_filtersDidChange() {}

    func addTextChangedListener(_ watcher: ATextWatcher) { aw_listeners.append(watcher) }

    func removeTextChangedListener(_ watcher: ATextWatcher) {
        if let i = aw_listeners.firstIndex(where: { $0 === watcher }) { aw_listeners.remove(at: i) }
    }

    // MARK: Shadow

    /// TextView.setShadowLayer: the paint's shadow layer plus the values the clip of onDraw uses.
    func setShadowLayer(_ radius: Float, _ dx: Float, _ dy: Float, _ color: Int) {
        paint.setShadowLayer(radius, dx, dy, color)
        aw_shadowRadius = radius
        aw_shadowDx = dx
        aw_shadowDy = dy
        aw_shadowColor = color
        invalidate()
    }

    var shadowRadius: Float { return aw_shadowRadius }
    var shadowDx: Float { return aw_shadowDx }
    var shadowDy: Float { return aw_shadowDy }
    var shadowColor: Int { return aw_shadowColor }

    // MARK: Compound drawables (TextView.Drawables)

    var compoundDrawablePadding: Int {
        get { return aw_drawablePadding }
        set { setCompoundDrawablePadding(newValue) }
    }

    func setCompoundDrawablePadding(_ pad: Int) {
        aw_drawablePadding = pad
        invalidate()
        requestLayout()
    }

    /// TextView.setCompoundDrawables: drawables with their own bounds.
    func setCompoundDrawables(_ left: ADrawable?, _ top: ADrawable?, _ right: ADrawable?, _ bottom: ADrawable?) {
        for d in aw_showingDrawables() { d?.callbackView = nil }
        aw_relativeDrawables = false
        aw_drawableLeft = left; aw_drawableTop = top; aw_drawableRight = right; aw_drawableBottom = bottom
        aw_drawableStart = nil; aw_drawableEnd = nil
        aw_attachDrawables([left, top, right, bottom])
        invalidate()
        requestLayout()
    }

    /// TextView.setCompoundDrawablesRelative: start/end resolved with the layout direction.
    func setCompoundDrawablesRelative(_ start: ADrawable?, _ top: ADrawable?, _ end: ADrawable?, _ bottom: ADrawable?) {
        for d in aw_showingDrawables() { d?.callbackView = nil }
        aw_relativeDrawables = true
        aw_drawableStart = start; aw_drawableEnd = end
        aw_drawableTop = top; aw_drawableBottom = bottom
        aw_resolveDrawables()
        aw_attachDrawables([start, top, end, bottom])
        invalidate()
        requestLayout()
    }

    func setCompoundDrawablesWithIntrinsicBounds(_ left: ADrawable?, _ top: ADrawable?, _ right: ADrawable?, _ bottom: ADrawable?) {
        for d in [left, top, right, bottom] { if let d = d { d.setBounds(0, 0, d.intrinsicWidth, d.intrinsicHeight) } }
        setCompoundDrawables(left, top, right, bottom)
    }

    func setCompoundDrawablesRelativeWithIntrinsicBounds(_ start: ADrawable?, _ top: ADrawable?, _ end: ADrawable?, _ bottom: ADrawable?) {
        for d in [start, top, end, bottom] { if let d = d { d.setBounds(0, 0, d.intrinsicWidth, d.intrinsicHeight) } }
        setCompoundDrawablesRelative(start, top, end, bottom)
    }

    private func aw_attachDrawables(_ drawables: [ADrawable?]) {
        let state = drawableState
        for d in drawables {
            guard let d = d else { continue }
            if d.isStateful { d.setState(state) }
            d.callbackView = self
        }
    }

    var compoundDrawables: [ADrawable?] {
        aw_resolveDrawables()
        return [aw_drawableLeft, aw_drawableTop, aw_drawableRight, aw_drawableBottom]
    }

    var compoundDrawablesRelative: [ADrawable?] {
        if aw_relativeDrawables { return [aw_drawableStart, aw_drawableTop, aw_drawableEnd, aw_drawableBottom] }
        return isLayoutRtl ? [aw_drawableRight, aw_drawableTop, aw_drawableLeft, aw_drawableBottom]
                           : [aw_drawableLeft, aw_drawableTop, aw_drawableRight, aw_drawableBottom]
    }

    /// TextView.Drawables.resolveWithLayoutDirection.
    func aw_resolveDrawables() {
        if aw_relativeDrawables {
            if isLayoutRtl {
                aw_drawableLeft = aw_drawableEnd
                aw_drawableRight = aw_drawableStart
            } else {
                aw_drawableLeft = aw_drawableStart
                aw_drawableRight = aw_drawableEnd
            }
        }
    }

    /// mShowing: the left/right drawables with the EditText error icon taking the end side.
    func aw_showingLeft() -> ADrawable? {
        aw_resolveDrawables()
        if let e = aw_errorDrawable, isLayoutRtl { return e }
        return aw_drawableLeft
    }

    func aw_showingRight() -> ADrawable? {
        aw_resolveDrawables()
        if let e = aw_errorDrawable, !isLayoutRtl { return e }
        return aw_drawableRight
    }

    func aw_showingDrawables() -> [ADrawable?] {
        return [aw_showingLeft(), aw_drawableTop, aw_showingRight(), aw_drawableBottom]
    }

    var compoundPaddingLeft: Int {
        guard let d = aw_showingLeft() else { return paddingLeft }
        return paddingLeft + aw_drawablePadding + d.bounds.width()
    }

    var compoundPaddingRight: Int {
        guard let d = aw_showingRight() else { return paddingRight }
        return paddingRight + aw_drawablePadding + d.bounds.width()
    }

    var compoundPaddingTop: Int {
        guard let d = aw_drawableTop else { return paddingTop }
        return paddingTop + aw_drawablePadding + d.bounds.height()
    }

    var compoundPaddingBottom: Int {
        guard let d = aw_drawableBottom else { return paddingBottom }
        return paddingBottom + aw_drawablePadding + d.bounds.height()
    }

    var compoundPaddingStart: Int { return isLayoutRtl ? compoundPaddingRight : compoundPaddingLeft }
    var compoundPaddingEnd: Int { return isLayoutRtl ? compoundPaddingLeft : compoundPaddingRight }

    func getCompoundPaddingLeft() -> Int { return compoundPaddingLeft }
    func getCompoundPaddingRight() -> Int { return compoundPaddingRight }
    func getCompoundPaddingTop() -> Int { return compoundPaddingTop }
    func getCompoundPaddingBottom() -> Int { return compoundPaddingBottom }

    /// TextView.getExtendedPaddingTop: the compound padding plus the gravity offset of the first maxLines lines.
    var extendedPaddingTop: Int {
        if aw_maxMode != ATextView.LINES { return compoundPaddingTop }
        let layout = aw_assumeLayout()
        if layout.lineCount <= aw_maximum { return compoundPaddingTop }
        let top = compoundPaddingTop
        let bottom = compoundPaddingBottom
        let viewht = height - top - bottom
        let layoutht = layout.getLineTop(aw_maximum)
        if layoutht >= viewht { return top }
        let g = aw_gravity & AGravity.VERTICAL_GRAVITY_MASK
        if g == AGravity.TOP { return top }
        if g == AGravity.BOTTOM { return top + viewht - layoutht }
        return top + (viewht - layoutht) / 2
    }

    /// TextView.getExtendedPaddingBottom.
    var extendedPaddingBottom: Int {
        if aw_maxMode != ATextView.LINES { return compoundPaddingBottom }
        let layout = aw_assumeLayout()
        if layout.lineCount <= aw_maximum { return compoundPaddingBottom }
        let top = compoundPaddingTop
        let bottom = compoundPaddingBottom
        let viewht = height - top - bottom
        let layoutht = layout.getLineTop(aw_maximum)
        if layoutht >= viewht { return bottom }
        let g = aw_gravity & AGravity.VERTICAL_GRAVITY_MASK
        if g == AGravity.TOP { return bottom + viewht - layoutht }
        if g == AGravity.BOTTOM { return bottom }
        return bottom + (viewht - layoutht) / 2
    }

    func getExtendedPaddingTop() -> Int { return extendedPaddingTop }
    func getExtendedPaddingBottom() -> Int { return extendedPaddingBottom }

    var totalPaddingLeft: Int { return compoundPaddingLeft }
    var totalPaddingRight: Int { return compoundPaddingRight }
    var totalPaddingStart: Int { return compoundPaddingStart }
    var totalPaddingEnd: Int { return compoundPaddingEnd }
    var totalPaddingTop: Int { return extendedPaddingTop + aw_verticalOffset(true) }
    var totalPaddingBottom: Int { return extendedPaddingBottom + aw_bottomVerticalOffset(true) }

    // MARK: Layout access

    /// TextView.getLayout().
    var layout: ALayout? { return aw_layout }
    func getLayout() -> ALayout? { return aw_layout }
    var hintLayout: ALayout? { return aw_hintLayout }

    /// TextView.getLineCount.
    var lineCount: Int { return aw_layout?.lineCount ?? 0 }
    func getLineCount() -> Int { return lineCount }

    /// TextView.getLineHeight: FastMath.round(getFontMetricsInt(null) * mult + add).
    var lineHeight: Int {
        return AWMath.fastRound(Float(AWFontMetrics.fontSpacing(paint.textSize)) * aw_spacingMult + aw_spacingAdd)
    }

    func getLineHeight() -> Int { return lineHeight }

    /// TextView.getBaseline.
    override func getBaseline() -> Int {
        guard let layout = aw_layout else { return super.getBaseline() }
        return aw_baselineOffset() + layout.getLineBaseline(0)
    }

    /// TextView.getBaselineOffset.
    func aw_baselineOffset() -> Int {
        var voffset = 0
        if (aw_gravity & AGravity.VERTICAL_GRAVITY_MASK) != AGravity.TOP { voffset = aw_verticalOffset(true) }
        return extendedPaddingTop + voffset
    }

    // MARK: Directions and alignment

    /// TextView.getTextDirectionHeuristic.
    func aw_textDirectionHeuristic() -> ATextDirectionHeuristic {
        if aw_transformation == .PASSWORD { return .LTR }
        if let phone = aw_phoneInputDirection() { return phone }
        let defaultIsRtl = isLayoutRtl
        switch textDirection {
        case AView.TEXT_DIRECTION_ANY_RTL: return .ANYRTL_LTR
        case AView.TEXT_DIRECTION_LTR: return .LTR
        case AView.TEXT_DIRECTION_RTL: return .RTL
        case AView.TEXT_DIRECTION_LOCALE: return .LOCALE
        case AView.TEXT_DIRECTION_FIRST_STRONG_LTR: return .FIRSTSTRONG_LTR
        case AView.TEXT_DIRECTION_FIRST_STRONG_RTL: return .FIRSTSTRONG_RTL
        default: return defaultIsRtl ? .FIRSTSTRONG_RTL : .FIRSTSTRONG_LTR
        }
    }

    /// Hook for AEditText: phone input is in the direction of the locale's digits (LTR for the app's languages).
    func aw_phoneInputDirection() -> ATextDirectionHeuristic? { return nil }

    /// TextView.getLayoutAlignment.
    func aw_layoutAlignment() -> ALayout.Alignment {
        switch textAlignment {
        case AView.TEXT_ALIGNMENT_GRAVITY:
            switch aw_gravity & AGravity.RELATIVE_HORIZONTAL_GRAVITY_MASK {
            case AGravity.START: return .ALIGN_NORMAL
            case AGravity.END: return .ALIGN_OPPOSITE
            case AGravity.LEFT: return .ALIGN_LEFT
            case AGravity.RIGHT: return .ALIGN_RIGHT
            case AGravity.CENTER_HORIZONTAL: return .ALIGN_CENTER
            default: return .ALIGN_NORMAL
            }
        case AView.TEXT_ALIGNMENT_TEXT_START: return .ALIGN_NORMAL
        case AView.TEXT_ALIGNMENT_TEXT_END: return .ALIGN_OPPOSITE
        case AView.TEXT_ALIGNMENT_CENTER: return .ALIGN_CENTER
        case AView.TEXT_ALIGNMENT_VIEW_START: return layoutDirection == AView.LAYOUT_DIRECTION_RTL ? .ALIGN_RIGHT : .ALIGN_LEFT
        case AView.TEXT_ALIGNMENT_VIEW_END: return layoutDirection == AView.LAYOUT_DIRECTION_RTL ? .ALIGN_LEFT : .ALIGN_RIGHT
        default: return .ALIGN_NORMAL
        }
    }

    /// TextView.onRtlPropertiesChanged: a new text direction heuristic re-lays the text out; the relative compound
    /// drawables are re-resolved (onResolveDrawables).
    override func onRtlPropertiesChanged(_ layoutDirection: Int) {
        super.onRtlPropertiesChanged(layoutDirection)
        aw_resolveDrawables()
        let newTextDir = aw_textDirectionHeuristic()
        if aw_textDir != newTextDir {
            aw_textDir = newTextDir
            if aw_layout != nil { aw_checkForRelayout() }
        }
        aw_styleDidChange()
    }

    // MARK: Layout building (TextView.makeNewLayout / nullLayouts / checkForRelayout)

    /// TextView.nullLayouts.
    func aw_nullLayouts() {
        aw_layout = nil
        aw_hintLayout = nil
    }

    /// TextView.assumeLayout (returns the layout).
    @discardableResult
    func aw_assumeLayout() -> ALayout {
        if let l = aw_layout { return l }
        var w = width - compoundPaddingLeft - compoundPaddingRight
        if w < 1 { w = 0 }
        let physicalWidth = w
        if aw_horizontallyScrolling { w = ATextView.VERY_WIDE }
        aw_makeNewLayout(w, physicalWidth, .UNKNOWN, .UNKNOWN, physicalWidth, false)
        return aw_layout!
    }

    /// Editable text (EditText) has a key listener: no ellipsis, a DynamicLayout (StaticLayout semantics here).
    var aw_isEditable: Bool { return false }

    /// TextView.makeNewLayout.
    func aw_makeNewLayout(_ wantWidth0: Int, _ hintWidth0: Int, _ boring: AWBoring, _ hintBoring: AWBoring,
                          _ ellipsisWidth: Int, _ bringIntoView: Bool) {
        aw_oldMaximum = aw_maximum
        aw_oldMaxMode = aw_maxMode
        let wantWidth = max(0, wantWidth0)
        var hintWidth = max(0, hintWidth0)
        let alignment = aw_layoutAlignment()
        let testDirChange = aw_singleLine && aw_layout != nil && (alignment == .ALIGN_NORMAL || alignment == .ALIGN_OPPOSITE)
        var oldDir = 0
        if testDirChange { oldDir = aw_layout!.getParagraphDirection(0) }
        var shouldEllipsize = aw_ellipsize != nil && !aw_isEditable
        var effectiveEllipsize = aw_ellipsize
        // Phones have no fading marquee (MARQUEE_FADE_SWITCH_SHOW_ELLIPSIS): MARQUEE shows END_SMALL.
        if aw_ellipsize == .MARQUEE { effectiveEllipsize = .END_SMALL }
        if aw_textDir == nil { aw_textDir = aw_textDirectionHeuristic() }
        aw_layout = aw_makeSingleLayout(wantWidth, boring, ellipsisWidth, alignment, shouldEllipsize, effectiveEllipsize)
        shouldEllipsize = aw_ellipsize != nil
        aw_hintLayout = nil
        if let hint = aw_hint {
            if shouldEllipsize { hintWidth = wantWidth }
            var hb = hintBoring
            if case .UNKNOWN = hb {
                if let w = ALayout.isBoringWidth(hint, paint, aw_textDir!) { hb = .BORING(w) } else { hb = .NOT_BORING }
            }
            if case .BORING(let bw) = hb {
                if bw <= hintWidth && (!shouldEllipsize || bw <= ellipsisWidth) {
                    aw_hintLayout = aw_buildLayout(hint, hintWidth, alignment, nil, ellipsisWidth, 1, boringWidth: bw)
                } else if shouldEllipsize && bw <= hintWidth {
                    aw_hintLayout = aw_buildLayout(hint, hintWidth, alignment, aw_ellipsize, ellipsisWidth, 1, boringWidth: nil)
                }
            }
            if aw_hintLayout == nil {
                aw_hintLayout = aw_buildLayout(hint, hintWidth, alignment, shouldEllipsize ? aw_ellipsize : nil, ellipsisWidth,
                                               aw_maxMode == ATextView.LINES ? aw_maximum : Int(Int32.max), boringWidth: nil)
            }
        }
        if bringIntoView || (testDirChange && oldDir != aw_layout!.getParagraphDirection(0)) {
            aw_registerForPreDraw()
        }
        aw_layoutDidChange()
    }

    /// TextView.makeSingleLayout (no DynamicLayout: an EditText's layout is a StaticLayout without ellipsis).
    func aw_makeSingleLayout(_ wantWidth: Int, _ boring0: AWBoring, _ ellipsisWidth: Int, _ alignment: ALayout.Alignment,
                             _ shouldEllipsize: Bool, _ effectiveEllipsize: ATextUtils.TruncateAt?) -> ALayout {
        var result: ALayout?
        if !aw_isEditable {
            var boring = boring0
            if case .UNKNOWN = boring {
                if let w = ALayout.isBoringWidth(aw_transformed, paint, aw_textDir!) { boring = .BORING(w) } else { boring = .NOT_BORING }
            }
            if case .BORING(let bw) = boring {
                if bw <= wantWidth && (effectiveEllipsize == nil || bw <= ellipsisWidth) {
                    result = aw_buildLayout(aw_transformed, wantWidth, alignment, nil, wantWidth, 1, boringWidth: bw)
                } else if shouldEllipsize && bw <= wantWidth {
                    result = aw_buildLayout(aw_transformed, wantWidth, alignment, effectiveEllipsize, ellipsisWidth, 1, boringWidth: nil)
                }
            }
        }
        if let r = result { return r }
        return aw_buildLayout(aw_transformed, wantWidth, alignment, shouldEllipsize ? effectiveEllipsize : nil, ellipsisWidth,
                              aw_maxMode == ATextView.LINES ? aw_maximum : Int(Int32.max), boringWidth: nil)
    }

    private func aw_buildLayout(_ source: ACharSequence, _ width: Int, _ alignment: ALayout.Alignment,
                                _ ellipsize: ATextUtils.TruncateAt?, _ ellipsizedWidth: Int, _ maxLines: Int,
                                boringWidth: Int?) -> ALayout {
        return ALayout(text: source, paint: paint, width: width, alignment: alignment, textDir: aw_textDir ?? .FIRSTSTRONG_LTR,
                       spacingMult: aw_spacingMult, spacingAdd: aw_spacingAdd, includePad: aw_includePad,
                       ellipsize: ellipsize, ellipsizedWidth: ellipsizedWidth, maxLines: maxLines,
                       breakStrategy: aw_breakStrategy, boringWidth: boringWidth)
    }

    /// Hook: the layouts were rebuilt (AEditText places its editor).
    func aw_layoutDidChange() {}

    /// TextView.checkForRelayout.
    func aw_checkForRelayout() {
        let lpWidth = layoutParams?.width ?? AViewGroup.LayoutParams.WRAP_CONTENT
        let lpHeight = layoutParams?.height ?? AViewGroup.LayoutParams.WRAP_CONTENT
        let hspace = width - compoundPaddingLeft - compoundPaddingRight
        if (lpWidth != AViewGroup.LayoutParams.WRAP_CONTENT
                || (aw_maxWidthMode == aw_minWidthMode && aw_maxWidthValue == aw_minWidthValue))
            && (aw_hint == nil || aw_hintLayout != nil)
            && hspace > 0, let old = aw_layout {
            let oldht = old.getHeight()
            let want = old.getWidth()
            let hintWant = aw_hintLayout?.getWidth() ?? 0
            aw_makeNewLayout(want, hintWant, .UNKNOWN, .UNKNOWN, hspace, false)
            if aw_ellipsize != .MARQUEE {
                if lpHeight != AViewGroup.LayoutParams.WRAP_CONTENT && lpHeight != AViewGroup.LayoutParams.MATCH_PARENT {
                    invalidate()
                    return
                }
                if aw_layout!.getHeight() == oldht && (aw_hintLayout == nil || aw_hintLayout!.getHeight() == oldht) {
                    invalidate()
                    return
                }
            }
            requestLayout()
            invalidate()
        } else {
            aw_nullLayouts()
            requestLayout()
            invalidate()
        }
    }

    /// TextView.checkForResize (an edited EditText).
    func aw_checkForResize() {
        var sizeChanged = false
        if aw_layout != nil {
            let lp = layoutParams
            if (lp?.width ?? AViewGroup.LayoutParams.WRAP_CONTENT) == AViewGroup.LayoutParams.WRAP_CONTENT {
                sizeChanged = true
                invalidate()
            }
            let lpHeight = lp?.height ?? AViewGroup.LayoutParams.WRAP_CONTENT
            if lpHeight == AViewGroup.LayoutParams.WRAP_CONTENT {
                if aw_desiredHeight() != height { sizeChanged = true }
            } else if lpHeight == AViewGroup.LayoutParams.MATCH_PARENT {
                if aw_desiredHeightAtMeasure >= 0 && aw_desiredHeight() != aw_desiredHeightAtMeasure { sizeChanged = true }
            }
        }
        if sizeChanged { requestLayout() }
    }

    // MARK: Measure (TextView.onMeasure)

    /// TextView.desired(Layout): -1 when a line was wrapped (not ended by '\n').
    private static func desired(_ layout: ALayout) -> Int {
        let n = layout.lineCount
        let units = layout.units
        if n > 1 {
            for i in 0..<(n - 1) {
                let end = layout.getLineEnd(i)
                if end == 0 || units[end - 1] != 0x0A { return -1 }
            }
        }
        var maxW: Float = 0
        for i in 0..<n { maxW = Swift.max(maxW, layout.getLineMax(i)) }
        return AWMath.ceil(maxW)
    }

    override func onMeasure(_ widthMeasureSpec: Int, _ heightMeasureSpec: Int) {
        let widthMode = AMeasureSpec.getMode(widthMeasureSpec)
        let heightMode = AMeasureSpec.getMode(heightMeasureSpec)
        let widthSize = AMeasureSpec.getSize(widthMeasureSpec)
        let heightSize = AMeasureSpec.getSize(heightMeasureSpec)
        var width: Int
        var height: Int
        var boring: AWBoring = .UNKNOWN
        var hintBoring: AWBoring = .UNKNOWN
        if aw_textDir == nil { aw_textDir = aw_textDirectionHeuristic() }
        var des = -1
        var fromexisting = false
        let widthLimit: Float = widthMode == AMeasureSpec.AT_MOST ? Float(widthSize) : Float.greatestFiniteMagnitude

        if widthMode == AMeasureSpec.EXACTLY {
            width = widthSize
        } else {
            if let l = aw_layout, aw_ellipsize == nil { des = ATextView.desired(l) }
            if des < 0 {
                if !aw_isEditable, let w = ALayout.isBoringWidth(aw_transformed, paint, aw_textDir!) {
                    boring = .BORING(w)
                } else {
                    boring = .NOT_BORING
                }
            } else {
                fromexisting = true
            }
            _ = fromexisting // assigned, never read (like TextView.onMeasure)
            if case .BORING(let bw) = boring {
                width = bw
            } else {
                if des < 0 {
                    des = AWMath.ceil(ALayout.getDesiredWidthWithLimit(aw_transformed, 0, aw_transformed.aw_plain.utf16.count,
                                                                       paint, aw_textDir!, widthLimit))
                }
                width = des
            }
            if let t = aw_drawableTop { width = Swift.max(width, t.bounds.width()) }
            if let b = aw_drawableBottom { width = Swift.max(width, b.bounds.width()) }
            if let hint = aw_hint {
                var hintDes = -1
                let hintWidth: Int
                if let hl = aw_hintLayout, aw_ellipsize == nil { hintDes = ATextView.desired(hl) }
                if hintDes < 0 {
                    if let w = ALayout.isBoringWidth(hint, paint, aw_textDir!) { hintBoring = .BORING(w) } else { hintBoring = .NOT_BORING }
                }
                if case .BORING(let hbw) = hintBoring {
                    hintWidth = hbw
                } else {
                    if hintDes < 0 {
                        hintDes = AWMath.ceil(ALayout.getDesiredWidthWithLimit(hint, 0, hint.aw_plain.utf16.count, paint,
                                                                               aw_textDir!, widthLimit))
                    }
                    hintWidth = hintDes
                }
                if hintWidth > width { width = hintWidth }
            }
            width += compoundPaddingLeft + compoundPaddingRight
            if aw_maxWidthMode == ATextView.EMS { width = Swift.min(width, aw_maxWidthValue * lineHeight) }
            else { width = Swift.min(width, aw_maxWidthValue) }
            if aw_minWidthMode == ATextView.EMS { width = Swift.max(width, aw_minWidthValue * lineHeight) }
            else { width = Swift.max(width, aw_minWidthValue) }
            width = Swift.max(width, getSuggestedMinimumWidth())
            if widthMode == AMeasureSpec.AT_MOST { width = Swift.min(widthSize, width) }
        }

        var want = width - compoundPaddingLeft - compoundPaddingRight
        let unpaddedWidth = want
        if aw_horizontallyScrolling { want = ATextView.VERY_WIDE }
        let hintWant = want
        let hintWidth = aw_hintLayout?.getWidth() ?? hintWant
        if aw_layout == nil {
            aw_makeNewLayout(want, hintWant, boring, hintBoring, width - compoundPaddingLeft - compoundPaddingRight, false)
        } else {
            let l = aw_layout!
            let layoutChanged = l.getWidth() != want || hintWidth != hintWant
                || l.getEllipsizedWidth() != width - compoundPaddingLeft - compoundPaddingRight
            let maximumChanged = aw_maxMode != aw_oldMaxMode || aw_maximum != aw_oldMaximum
            if layoutChanged || maximumChanged {
                // Layout.increaseWidthTo keeps the same lines when they all fit; a rebuild produces those lines.
                aw_makeNewLayout(want, hintWant, boring, hintBoring, width - compoundPaddingLeft - compoundPaddingRight, false)
            }
        }

        if heightMode == AMeasureSpec.EXACTLY {
            height = heightSize
            aw_desiredHeightAtMeasure = -1
        } else {
            let desired = aw_desiredHeight()
            height = desired
            aw_desiredHeightAtMeasure = desired
            if heightMode == AMeasureSpec.AT_MOST { height = Swift.min(desired, heightSize) }
        }

        var unpaddedHeight = height - compoundPaddingTop - compoundPaddingBottom
        if aw_maxMode == ATextView.LINES, let l = aw_layout, l.lineCount > aw_maximum {
            unpaddedHeight = Swift.min(unpaddedHeight, l.getLineTop(aw_maximum))
        }
        if let l = aw_layout, l.getWidth() > unpaddedWidth || l.getHeight() > unpaddedHeight {
            aw_registerForPreDraw()
        } else {
            scrollTo(0, 0)
        }
        setMeasuredDimension(width, height)
        aw_didMeasure(width, height)
    }

    /// Hook after measuring.
    func aw_didMeasure(_ width: Int, _ height: Int) {}

    /// TextView.getDesiredHeight().
    func aw_desiredHeight() -> Int {
        return Swift.max(aw_desiredHeight(aw_layout, true), aw_desiredHeight(aw_hintLayout, aw_ellipsize != nil))
    }

    private func aw_desiredHeight(_ layout: ALayout?, _ cap: Bool) -> Int {
        guard let layout = layout else { return 0 }
        var desired = layout.getHeight(cap)
        if let l = aw_showingLeft() { desired = Swift.max(desired, l.bounds.height()) }
        if let r = aw_showingRight() { desired = Swift.max(desired, r.bounds.height()) }
        var linecount = layout.lineCount
        let padding = compoundPaddingTop + compoundPaddingBottom
        desired += padding
        if aw_maxMode != ATextView.LINES {
            desired = Swift.min(desired, aw_maximum)
        } else if cap && linecount > aw_maximum && (aw_isEditable || layout.boringWidth != nil) {
            desired = layout.getLineTop(aw_maximum)
            if let l = aw_showingLeft() { desired = Swift.max(desired, l.bounds.height()) }
            if let r = aw_showingRight() { desired = Swift.max(desired, r.bounds.height()) }
            desired += padding
            linecount = aw_maximum
        }
        if aw_minMode == ATextView.LINES {
            if linecount < aw_minimum { desired += lineHeight * (aw_minimum - linecount) }
        } else {
            desired = Swift.max(desired, aw_minimum)
        }
        desired = Swift.max(desired, getSuggestedMinimumHeight())
        return desired
    }

    // MARK: Vertical offsets

    /// TextView.getBoxHeight.
    private func aw_boxHeight(_ l: ALayout) -> Int {
        let padding = (l === aw_hintLayout) ? compoundPaddingTop + compoundPaddingBottom : extendedPaddingTop + extendedPaddingBottom
        return measuredHeight - padding
    }

    /// TextView.getVerticalOffset.
    func aw_verticalOffset(_ forceNormal: Bool) -> Int {
        var voffset = 0
        let g = aw_gravity & AGravity.VERTICAL_GRAVITY_MASK
        guard var l = aw_layout else { return 0 }
        if !forceNormal && aw_text.aw_plain.isEmpty, let hl = aw_hintLayout { l = hl }
        if g != AGravity.TOP {
            let boxht = aw_boxHeight(l)
            let textht = l.getHeight()
            if textht < boxht {
                if g == AGravity.BOTTOM { voffset = boxht - textht } else { voffset = (boxht - textht) >> 1 }
            }
        }
        return voffset
    }

    /// TextView.getBottomVerticalOffset.
    func aw_bottomVerticalOffset(_ forceNormal: Bool) -> Int {
        var voffset = 0
        let g = aw_gravity & AGravity.VERTICAL_GRAVITY_MASK
        guard var l = aw_layout else { return 0 }
        if !forceNormal && aw_text.aw_plain.isEmpty, let hl = aw_hintLayout { l = hl }
        if g != AGravity.BOTTOM {
            let boxht = aw_boxHeight(l)
            let textht = l.getHeight()
            if textht < boxht {
                if g == AGravity.TOP { voffset = boxht - textht } else { voffset = (boxht - textht) >> 1 }
            }
        }
        return voffset
    }

    // MARK: Pre-draw (TextView.registerForPreDraw / onPreDraw / bringTextIntoView)

    func aw_registerForPreDraw() {
        if aw_preDrawListener != nil { return }
        let l = AOnPreDrawListener { [weak self] in self?.aw_onPreDraw() ?? true }
        aw_preDrawListener = l
        viewTreeObserver.addOnPreDrawListener(l)
    }

    func aw_unregisterForPreDraw() {
        if let l = aw_preDrawListener {
            viewTreeObserver.removeOnPreDrawListener(l)
            aw_preDrawListener = nil
        }
    }

    /// TextView.onPreDraw.
    private func aw_onPreDraw() -> Bool {
        if aw_layout == nil { aw_assumeLayout() }
        aw_bringTextIntoView()
        aw_unregisterForPreDraw()
        return true
    }

    /// TextView.bringTextIntoView.
    @discardableResult
    func aw_bringTextIntoView() -> Bool {
        let showingHint = aw_text.aw_plain.isEmpty && !(aw_hint?.aw_plain.isEmpty ?? true)
        guard let layout = showingHint ? aw_hintLayout : aw_layout, layout.lineCount > 0 else { return false }
        var line = 0
        if (aw_gravity & AGravity.VERTICAL_GRAVITY_MASK) == AGravity.BOTTOM { line = layout.lineCount - 1 }
        var a = layout.getParagraphAlignment(line)
        let dir = layout.getParagraphDirection(line)
        let hspace = width - compoundPaddingLeft - compoundPaddingRight
        let vspace = height - extendedPaddingTop - extendedPaddingBottom
        let ht = layout.getHeight()
        if a == .ALIGN_NORMAL {
            a = dir == ALayout.DIR_LEFT_TO_RIGHT ? .ALIGN_LEFT : .ALIGN_RIGHT
        } else if a == .ALIGN_OPPOSITE {
            a = dir == ALayout.DIR_LEFT_TO_RIGHT ? .ALIGN_RIGHT : .ALIGN_LEFT
        }
        var scrollx: Int
        if a == .ALIGN_CENTER {
            let left = AWMath.floor(layout.getLineLeft(line))
            let right = AWMath.ceil(layout.getLineRight(line))
            if right - left < hspace {
                scrollx = (right + left) / 2 - hspace / 2
            } else {
                scrollx = dir < 0 ? right - hspace : left
            }
        } else if a == .ALIGN_RIGHT {
            let right = AWMath.ceil(layout.getLineRight(line))
            scrollx = right - hspace
        } else {
            scrollx = AWMath.floor(layout.getLineLeft(line))
        }
        var scrolly = 0
        if ht >= vspace && (aw_gravity & AGravity.VERTICAL_GRAVITY_MASK) == AGravity.BOTTOM { scrolly = ht - vspace }
        if scrollx != scrollX || scrolly != scrollY {
            scrollTo(scrollx, scrolly)
            return true
        }
        return false
    }

    // MARK: Drawing (TextView.onDraw)

    override func onDraw(_ canvas: ACanvas) {
        super.onDraw(canvas)
        // View.draw translates the canvas by (-mScrollX, -mScrollY) for the content (not for the background).
        let scrollSave = canvas.save()
        let sx = scrollX, sy = scrollY
        canvas.translate(Float(-sx), Float(-sy))
        let cpl = compoundPaddingLeft, cpt = compoundPaddingTop, cpr = compoundPaddingRight, cpb = compoundPaddingBottom
        let viewW = width, viewH = height
        // Compound drawables (not clipped by the extended padding).
        let vspaceC = viewH - cpb - cpt
        let hspaceC = viewW - cpr - cpl
        if let l = aw_showingLeft() {
            let s = canvas.save()
            canvas.translate(Float(sx + paddingLeft), Float(sy + cpt + (vspaceC - l.bounds.height()) / 2))
            l.draw(canvas)
            canvas.restoreToCount(s)
        }
        if let r = aw_showingRight() {
            let s = canvas.save()
            canvas.translate(Float(sx + viewW - paddingRight - r.bounds.width()), Float(sy + cpt + (vspaceC - r.bounds.height()) / 2))
            r.draw(canvas)
            canvas.restoreToCount(s)
        }
        if let t = aw_drawableTop {
            let s = canvas.save()
            canvas.translate(Float(sx + cpl + (hspaceC - t.bounds.width()) / 2), Float(sy + paddingTop))
            t.draw(canvas)
            canvas.restoreToCount(s)
        }
        if let b = aw_drawableBottom {
            let s = canvas.save()
            canvas.translate(Float(sx + cpl + (hspaceC - b.bounds.width()) / 2), Float(sy + viewH - paddingBottom - b.bounds.height()))
            b.draw(canvas)
            canvas.restoreToCount(s)
        }
        if aw_drawsOwnText {
            var color = aw_curTextColor
            let mainLayout = aw_assumeLayout()
            var layout = mainLayout
            if aw_hint != nil && aw_text.aw_plain.isEmpty, let hl = aw_hintLayout {
                if aw_hintTextColor != nil { color = aw_curHintTextColor }
                layout = hl
            }
            paint.color = color
            let s = canvas.save()
            let ept = extendedPaddingTop
            let epb = extendedPaddingBottom
            let vspace = viewH - cpb - cpt
            let maxScrollY = mainLayout.getHeight() - vspace
            var clipLeft = Float(cpl + sx)
            var clipTop: Float = sy == 0 ? 0 : Float(ept + sy)
            var clipRight = Float(viewW - cpr + sx)
            var clipBottom = Float(viewH + sy - (sy == maxScrollY ? 0 : epb))
            if aw_shadowRadius != 0 {
                clipLeft += Swift.min(0, aw_shadowDx - aw_shadowRadius)
                clipRight += Swift.max(0, aw_shadowDx + aw_shadowRadius)
                clipTop += Swift.min(0, aw_shadowDy - aw_shadowRadius)
                clipBottom += Swift.max(0, aw_shadowDy + aw_shadowRadius)
            }
            canvas.clipRect(clipLeft, clipTop, clipRight, clipBottom)
            var voffsetText = 0
            if (aw_gravity & AGravity.VERTICAL_GRAVITY_MASK) != AGravity.TOP { voffsetText = aw_verticalOffset(false) }
            canvas.translate(Float(cpl), Float(ept + voffsetText))
            layout.draw(canvas)
            canvas.restoreToCount(s)
        }
        canvas.restoreToCount(scrollSave)
    }

    override func onDetachedFromWindow() {
        super.onDetachedFromWindow()
        aw_unregisterForPreDraw()
    }

    // MARK: Accessibility

    override var providesAccessibilityText: Bool { return true }

    override var accessibilityLabel: String? {
        get { return contentDescription ?? (aw_text.aw_plain.isEmpty ? aw_hint?.aw_plain : aw_transformed.aw_plain) }
        set { super.accessibilityLabel = newValue }
    }
}
