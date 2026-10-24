import UIKit

/// Port of MinikFamilyServices `FamilyMoreFrame.java` (family snapshot 2f75e98), statement by statement.
///
/// Reserved menu scroll cue. Its touch target never overlaps an action.
/// AndroidKit views take no Context; the Java constructors' Context only decides the copy (`localized`), so it stays a
/// parameter. Swift API: the Java parameter names are the labels (DESIGN 2.1); the unlabelled forms forward to them.
class FamilyMoreFrame: ALinearLayout {
    private let scroll: AScrollView
    private let cue: ALinearLayout
    private let arrow: ATextView
    private var bounce: AObjectAnimator?
    private lazy var layoutListener = AOnGlobalLayoutListener { [weak self] in self?.updateCue() }
    private lazy var scrollListener = AOnScrollChangedListener { [weak self] in self?.updateCue() }
    /// Java `dp(int)`: `Math.round(n * density)`.
    private func dp(_ n: Int) -> Int { return (Float(n) * AResources.displayMetrics.density).roundToInt() }
    convenience init(context: AContext?, source: AScrollView, hebrew: Bool) {
        self.init(context: context, source: source, hebrew: hebrew, light: false)
    }
    convenience init(_ context: AContext?, _ source: AScrollView, _ hebrew: Bool) {
        self.init(context: context, source: source, hebrew: hebrew, light: false)
    }
    convenience init(_ context: AContext?, _ source: AScrollView, _ hebrew: Bool, _ light: Bool) {
        self.init(context: context, source: source, hebrew: hebrew, light: light)
    }
    init(context: AContext?, source: AScrollView, hebrew: Bool, light: Bool) {
        scroll = source; cue = ALinearLayout(); arrow = ATextView()
        super.init(); orientation = ALinearLayout.VERTICAL
        addView(scroll, ALinearLayout.LayoutParams(-1, 0, 1))
        cue.setGravity(AGravity.CENTER); cue.isClickable = true; cue.isFocusable = true
        cue.contentDescription = FamilyMoreFrame.localized(context, hebrew, "More options below. Tap to scroll", "עוד אפשרויות למטה. הקישו לגלילה")
        let label = ATextView(); label.setText(FamilyMoreFrame.localized(context, hebrew, "More below", "עוד למטה")); label.setTextSize(16); label.setTypeface(nil, ATypeface.BOLD)
        label.setTextColor(light ? argbInt(0xff183652) : argbInt(0xfff7fbff)); label.setShadowLayer(Float(dp(1)), 0, Float(dp(1)), light ? argbInt(0xfff7fbff) : argbInt(0xff102039)); label.importantForAccessibility = AView.IMPORTANT_FOR_ACCESSIBILITY_NO
        arrow.setText("\u{2304}"); arrow.setTextSize(30); arrow.setTypeface(nil, ATypeface.BOLD); arrow.setTextColor(light ? argbInt(0xff245477) : argbInt(0xffffdf77)); arrow.setGravity(AGravity.CENTER)
        arrow.setShadowLayer(Float(dp(1)), 0, Float(dp(1)), AColor.BLACK); arrow.importantForAccessibility = AView.IMPORTANT_FOR_ACCESSIBILITY_NO
        cue.addView(label, ALinearLayout.LayoutParams(-2, -2)); cue.addView(arrow, ALinearLayout.LayoutParams(dp(38), dp(44)))
        addView(cue, ALinearLayout.LayoutParams(-1, dp(48)))
        let scroll = self.scroll
        cue.setOnClickListener { _ in scroll.smoothScrollBy(0, (Float(scroll.height) * 0.65).roundToInt()) }
    }
    required init?(coder: NSCoder) { fatalError("FamilyMoreFrame is built in code") }

    /// Java `localized(Context c, boolean he, String en, String hebrew)`: `FamilyMessages.text(activity, en, hebrew)` when
    /// the context is an Activity (always in Triple Shot), else the configuration-language flag.
    private static func localized(_ c: AContext?, _ he: Bool, _ en: String, _ hebrew: String) -> String {
        if let a = c as? AActivity { return FamilyBridge.text(a, en, hebrew) }
        return he ? hebrew : en
    }
    /// Posted: wraps the nearest ancestor ScrollView of `content` once (the first of several calls wins).
    static func installFor(content: AView) {
        content.post {
            var v: AView = content
            while !(v is AScrollView), let up = v.parentGroup { v = up }
            guard let s = v as? AScrollView, !(s.parentGroup is FamilyMoreFrame), let parent = s.parentGroup else { return }
            let index = parent.indexOfChild(s); let lp = s.layoutParams
            // `content.getResources().getConfiguration()`: AndroidKit's resources are the app's (AContextResources).
            let config = AContextResources.shared.configuration
            let language = config.getLocales().get(0).language
            parent.removeView(s)
            let frame = FamilyMoreFrame(context: FamilyBridge.context(content), source: s, hebrew: language == "he" || language == "iw", light: (content.getTag() as? String) == "family-menu-light")
            if let lp = lp { parent.addView(frame, index, lp) } else { parent.addView(frame, index) }
        }
    }
    static func installFor(_ content: AView) { installFor(content: content) }
    private func updateCue() {
        let show = scroll.canScrollVertically(1) && getWindowVisibility() == AView.VISIBLE && isShown
        cue.visibility = show ? AView.VISIBLE : AView.INVISIBLE
        // AccessibilityManager.isTouchExplorationEnabled() (TalkBack's touch exploration) is VoiceOver on iOS.
        let animate = show && !UIAccessibility.isVoiceOverRunning && animationsEnabled()
        if animate && bounce == nil { let b = AObjectAnimator.ofFloat(arrow, AViewProperty.TRANSLATION_Y, 0, Float(dp(4))); bounce = b; b.setDuration(850); b.setRepeatMode(AValueAnimator.REVERSE); b.setRepeatCount(AValueAnimator.INFINITE); b.start() }
        else if !animate { stop() }
    }
    /// API >= 26: `ValueAnimator.areAnimatorsEnabled()`.
    private func animationsEnabled() -> Bool { return AValueAnimator.areAnimatorsEnabled() }
    private func stop() { bounce?.cancel(); bounce = nil; arrow.translationY = 0 }
    override func onAttachedToWindow() { super.onAttachedToWindow(); viewTreeObserver.addOnGlobalLayoutListener(layoutListener); scroll.viewTreeObserver.addOnScrollChangedListener(scrollListener); post { [weak self] in self?.updateCue() } }
    override func onDetachedFromWindow() { viewTreeObserver.removeOnGlobalLayoutListener(layoutListener); scroll.viewTreeObserver.removeOnScrollChangedListener(scrollListener); stop(); super.onDetachedFromWindow() }
    override func onWindowVisibilityChanged(_ visibility: Int) { super.onWindowVisibilityChanged(visibility); if visibility != AView.VISIBLE { stop() } else { post { [weak self] in self?.updateCue() } } }
}
