import Foundation

/// Port of MinikFamilyServices `FamilySkyDrawable.java` (family snapshot 2f75e98), statement by statement.
///
/// Maze's glossy, raised surfaces. All depth is drawn INSIDE the existing bounds.
/// Keeps the host's dimensions, padding, listeners and state-dependent color choices.
///
/// Like Android it extends the GradientDrawable port, whose state the overridden setters still feed, so Kotlin factories
/// such as `FamilySkyDrawable().apply { setColor(c); cornerRadius = r; setStroke(w, c) }` (typed as GradientDrawable or
/// not) reach the overrides. `draw` paints only the sky surface: a tint or colour filter set on it has no visible effect
/// (as on Android, where the AppCompat/Material tint lands on GradientDrawable's own paints, which are never used here).
/// The Java field `colors` is `skyColors` here (AGradientDrawable already has `colors`, its gradient array).
/// Lengths are Android pixels.
///
/// Swift API: the Java parameter names are the labels (DESIGN 2.1); unlabelled forms that read like the Java call sites
/// forward to them. Overrides of AndroidKit's GradientDrawable keep its unlabelled signatures.
final class FamilySkyDrawable: AGradientDrawable, ADrawableOutlineProvider {
    private var skyColors: AColorStateList? = AColorStateList.valueOf(AColor.TRANSPARENT)
    private var radius: Float = 18, strokeWidth: Float = 0
    private var strokeColor: Int = AColor.TRANSPARENT, opacity: Int = 255
    private let panel: Bool
    private let paint = APaint(APaint.ANTI_ALIAS_FLAG)
    private let box = ARectF(), face = ARectF(), inner = ARectF()
    private var dirty = true, pressed = false, enabled = true, focused = false
    private var base: Int = 0, edge: Int = 0
    private var depth: Float = 0, rim: Float = 0
    private var faceShader: AShader?, shineShader: AShader?
    private var customFaceGradient: [Int]?

    func setFaceGradient(value: Int...) { setFaceGradient(value) }
    func setFaceGradient(_ value: Int...) { setFaceGradient(value) }
    /// Java `setFaceGradient(int... value)` with an array (Kotlin `setFaceGradient(*colors)`); the array is copied.
    func setFaceGradient(_ value: [Int]) { customFaceGradient = value; dirty = true; invalidateSelf() }
    /// The colours as set (before the palette).
    func sourceColors() -> AColorStateList! { return skyColors }
    /// Java `isPanel()` (Kotlin reads it as the property `isPanel`).
    var isPanel: Bool { return panel }
    /// Same face rectangle used by draw(), including the pressed state.
    func copyFaceBounds(out: ARectF) { if dirty { prepare() }; out.set(face) }
    func copyFaceBounds(_ out: ARectF) { copyFaceBounds(out: out) }
    /// Lettering belongs in the body below the bright upper gloss, excluding
    /// the lower extrusion too. The full face still describes the painted shape.
    func copyTextFaceBounds(out: ARectF) {
        copyFaceBounds(out: out)
        if !panel { out.top += kmin(face.height() * 0.20, radius * 0.65) }
    }
    func copyTextFaceBounds(_ out: ARectF) { copyTextFaceBounds(out: out) }
    /// `new FamilySkyDrawable()`: a raised button face.
    convenience override init() { self.init(panel: false) }
    /// `new FamilySkyDrawable(panel)`: a panel never sinks, has no gloss and no disabled look.
    init(panel: Bool) { self.panel = panel; super.init() }
    convenience init(_ panel: Bool) { self.init(panel: panel) }
    override func setColor(_ value: Int) { setColor(AColorStateList.valueOf(value)) }
    override func setColor(_ value: AColorStateList?) { skyColors = value; dirty = true; super.setColor(value); invalidateSelf() }
    /// Java `setCornerRadius(float)`: AndroidKit's final `setCornerRadius(_:)` and Kotlin's `cornerRadius = x` both set
    /// this property, so both land here.
    override var cornerRadius: Float {
        get { return super.cornerRadius }
        set { radius = newValue; dirty = true; super.cornerRadius = newValue }
    }
    override func setStroke(_ width: Int, _ color: Int) { strokeWidth = Float(width); strokeColor = color; dirty = true; super.setStroke(width, color) }
    /// Java `setAlpha(int)` (whole-surface opacity): AndroidKit's final `setAlpha(_:)` and Kotlin's `alpha = x` land here.
    override var alpha: Int {
        get { return super.alpha }
        set { opacity = newValue; super.alpha = newValue; invalidateSelf() }
    }
    override var isStateful: Bool { return true }
    /// Also cover standalone windows whose controls bypass the activity decorators.
    /// View attaches itself as the drawable callback before applying state/bounds.
    /// Binding only registers the layout listener; it never changes padding in draw().
    private func bindButtonOwner() {
        if !panel, let button = getCallback() as? AButton {
            FamilyButtonAlignment.bind(button: button)
        }
    }
    override func onStateChange(_ states: [Int]) -> Bool {
        bindButtonOwner()
        _ = super.onStateChange(states); pressed = false; enabled = false; focused = false
        for state in states {
            if state == android.R.attr.state_pressed { pressed = true }
            if state == android.R.attr.state_enabled { enabled = true }
            if state == android.R.attr.state_focused { focused = true }
        }
        dirty = true; invalidateSelf(); return true
    }
    override func onBoundsChange(_ bounds: ARect) { super.onBoundsChange(bounds); dirty = true; bindButtonOwner() }
    /// Java `private static int blend(int a, int b, float t)`: `Color.rgb(Math.round(red(a)*(1-t)+red(b)*t), ...)` in
    /// float maths, always opaque. (Internal instead of private only so the parity tests can check the colour table.)
    static func blend(_ a: Int, _ b: Int, _ t: Float) -> Int {
        return AColor.rgb((Float(AColor.red(a)) * (1 - t) + Float(AColor.red(b)) * t).roundToInt(),
                          (Float(AColor.green(a)) * (1 - t) + Float(AColor.green(b)) * t).roundToInt(),
                          (Float(AColor.blue(a)) * (1 - t) + Float(AColor.blue(b)) * t).roundToInt())
    }
    /// Keep hue roles, including purple; only replace pale fills with Maze equivalents.
    static func palette(color: Int) -> Int {
        var hsv: [Float] = [0, 0, 0]; AColor.colorToHSV(color, &hsv)
        if hsv[1] < 0.12 { return color }
        if hsv[1] > 0.48 { return color } // strong selected/error colors keep their contrast
        let h = hsv[0]
        let mapped = h >= 265 && h < 325 ? argbInt(0xffd8bfff) : h >= 175 && h < 265 ? argbInt(0xffa6dcff)
            : h >= 65 && h < 175 ? argbInt(0xffb1eddb) : h >= 30 && h < 65 ? argbInt(0xffffe59d) : color
        return (color & argbInt(0xff000000)) | (mapped & 0xffffff)
    }
    static func palette(_ color: Int) -> Int { return palette(color: color) }
    private func prepare() {
        let source = skyColors == nil ? 0 : skyColors!.getColorForState(getState(), skyColors!.defaultColor); base = FamilySkyDrawable.palette(color: source)
        box.set(getBounds()); let shortSide = kmin(box.width(), box.height())
        depth = kmin(shortSide * 0.075, kmax(2, radius * 0.28)); rim = kmax(1, kmin(shortSide * 0.026, radius * 0.08))
        let pale = max(AColor.red(base), max(AColor.green(base), AColor.blue(base))) - min(AColor.red(base), min(AColor.green(base), AColor.blue(base))) < 132
        // Dark HUD/selection surfaces carry white text; do not wash them into pale gray.
        let dark = (AColor.red(base) * 299 + AColor.green(base) * 587 + AColor.blue(base) * 114) / 1000 < 130
        var upper = FamilySkyDrawable.blend(base, AColor.WHITE, dark ? 0.08 : pale ? 0.75 : 0.22), lower = FamilySkyDrawable.blend(base, AColor.WHITE, dark ? 0.015 : pale ? 0.32 : 0.02)
        edge = FamilySkyDrawable.blend(base, argbInt(0xff204878), 0.28)
        if !enabled && !panel { upper = argbInt(0xffeef3f7); lower = argbInt(0xffdce7ef); edge = argbInt(0xffb4cadb) }
        face.set(box); face.inset(rim, rim); face.top += pressed && !panel ? depth * 0.65 : 0; face.bottom -= pressed && !panel ? depth * 0.3 : depth
        if panel || (AColor.red(base) > 238 && AColor.green(base) > 238 && AColor.blue(base) > 238) {
            faceShader = ALinearGradient(face.left, face.top, face.right, face.bottom,
                                         [FamilySkyDrawable.blend(argbInt(0xffdff5ff), base, 0.1), argbInt(0xfffffef2), argbInt(0xfff4fbff),
                                          FamilySkyDrawable.blend(argbInt(0xffffdeeb), base, 0.08)], nil, .CLAMP)
        } else { faceShader = ALinearGradient(0, face.top, 0, face.bottom, [upper, lower, lower], [0, 0.48, 1], .CLAMP) }
        if let custom = customFaceGradient { faceShader = ALinearGradient(0, face.top, 0, face.bottom, custom, nil, .CLAMP) }
        shineShader = ALinearGradient(0, face.top, 0, face.top + kmin(face.height() * 0.40, radius), argbInt(0xbbffffff), argbInt(0x00ffffff), .CLAMP)
        dirty = false
    }
    /// Java `getOutline(Outline)`: the rounded `box inset rim` with the base alpha (elevation shadows follow the face).
    func getOutline(_ outline: AOutline) {
        if dirty { prepare() }; outline.setRoundRect((box.left + rim).roundToInt(), (box.top + rim).roundToInt(), (box.right - rim).roundToInt(), (box.bottom - rim).roundToInt(), radius); outline.setAlpha(Float(AColor.alpha(base)) / 255)
    }
    override func draw(_ canvas: ACanvas) {
        if dirty { prepare() }; if AColor.alpha(base) == 0 || box.isEmpty() { return }
        let save = canvas.saveLayerAlpha(box, opacity * AColor.alpha(base) / 255)
        paint.shader = nil; paint.style = .FILL; paint.color = edge
        inner.set(box); inner.inset(rim, rim); canvas.drawRoundRect(inner, radius, radius, paint)
        paint.shader = faceShader; canvas.drawRoundRect(face, radius, radius, paint); paint.shader = nil
        paint.style = .STROKE; paint.strokeWidth = strokeWidth > 0 ? strokeWidth : rim
        paint.color = strokeWidth > 0 ? strokeColor : FamilySkyDrawable.blend(base, AColor.WHITE, 0.22); canvas.drawRoundRect(face, radius, radius, paint)
        inner.set(face); inner.inset(rim * 2, rim * 2); paint.strokeWidth = rim; paint.color = argbInt(0xb8ffffff); canvas.drawRoundRect(inner, kmax(1, radius - rim * 2), kmax(1, radius - rim * 2), paint)
        // The paint still carries #B8FFFFFF for the shine: as on Android, the paint alpha modulates the shader.
        if !panel { inner.set(face); inner.inset(kmin(radius * 0.8, face.width() * 0.12), rim * 3); inner.bottom = kmin(inner.bottom, inner.top + face.height() * 0.25); paint.style = .FILL; paint.shader = shineShader; canvas.drawRoundRect(inner, inner.height() / 2, inner.height() / 2, paint); paint.shader = nil }
        if focused { paint.style = .STROKE; paint.color = argbInt(0xff2587d6); paint.strokeWidth = rim * 2; canvas.drawRoundRect(face, radius, radius, paint) }
        canvas.restoreToCount(save)
    }
}
