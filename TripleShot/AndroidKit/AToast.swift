import UIKit

// AndroidKit toasts (CORE-API "AToast", DESIGN 4.5): android.widget.Toast for text toasts as Android 11+ shows them
// for an app targeting SDK 36 (Triple Shot). Three Android parts are ported:
//
// * Toast (the app side): makeText / show / cancel / setText / setDuration. A text toast is a token plus text and
//   duration handed to the system; setGravity / setMargin are ignored for text toasts targeting R+ (Android logs a
//   warning), as on the owner's devices.
// * NotificationManagerService (the queue): one queue for every toast, at most 5 queued toasts per app (more are
//   dropped), showing the head; re-showing a queued toast updates its duration and, when it is the head, shows it
//   again; the head stays for SHORT_DELAY 2000 ms / LONG_DELAY 3500 ms + 333 ms for its "in" animation (+ 250 ms for
//   the previous toast's "out" animation when it followed another toast), then the next one is shown. Cancelling a
//   queued toast that is not the head shows the head again (NMS quirk, kept).
// * SystemUI ToastUI / SystemUIToast (the look): text_toast.xml — a horizontal row with the app icon (24 dp, margins
//   10/10/10 dp) and the text (14 sp medium, line height 20 sp, padding 12 dp top/bottom, at most 2 lines, end
//   ellipsis), 16 dp horizontal padding, on toast_frame (colorSurface, 28 dp corners, elevation 2 dp), at most
//   config_prefDialogWidth wide (the WRAP_CONTENT window's first measure), bottom-centred 48 dp (toast_y_offset)
//   above the system bars; ToastDefaultAnimation in (scale 0.9 -> 1 333 ms, alpha 66 ms, text/icon alpha 283 ms after
//   50 ms) and out (scale 1 -> 0.9 250 ms, alpha 100 ms after 150 ms, text/icon alpha 166 ms); the next toast appears
//   after the previous "out" animation. The toast follows the system light/dark theme (AOSP default colours
//   system_surface_container / system_on_surface) and the device locale's direction, like SystemUI.
// The toast layer is AActivityHost.toastLayer: above every activity and dialog, never touchable. A toast shown before
// the host exists waits for it.

/// android.widget.Toast.
final class AToast {
    static let LENGTH_SHORT = 0
    static let LENGTH_LONG = 1

    /// The text the next show() hands to the system.
    private(set) var text: String
    private(set) var duration: Int

    init(_ text: String, _ duration: Int) {
        self.text = text
        self.duration = duration
    }

    /// Toast.makeText(context, text, duration): `text` is literal text, even when it spells a resource name (string
    /// resources use makeText(res:...), the @StringRes int overload).
    static func makeText(_ text: String, _ duration: Int) -> AToast {
        AToast(text, duration)
    }

    /// Toast.makeText(context, text, duration) with the context argument kept.
    static func makeText(_ context: AContext?, _ text: String, _ duration: Int) -> AToast {
        makeText(text, duration)
    }

    /// Toast.makeText(context, resId, duration).
    static func makeText(res: AStringRes, _ duration: Int) -> AToast {
        AToast(AResources.getText(res), duration)
    }

    static func makeText(_ context: AContext?, res: AStringRes, _ duration: Int) -> AToast {
        makeText(res: res, duration)
    }

    /// Toast.show(): enqueues this toast (its current text and duration).
    func show() {
        KitToastManager.shared.enqueueTextToast(self, text, duration)
    }

    /// Toast.cancel(): hides it if showing, removes it if queued.
    func cancel() {
        KitToastManager.shared.cancelToast(self)
    }

    /// Toast.setText(s): used by a later show().
    func setText(_ s: String) {
        text = s
    }

    func setText(res: AStringRes) {
        text = AResources.getText(res)
    }

    func setDuration(_ duration: Int) {
        self.duration = duration
    }

    func getDuration() -> Int { duration }

    /// Toast.setGravity: no effect on a text toast of an app targeting Android 11+ (Toast logs a warning).
    func setGravity(_ gravity: Int, _ xOffset: Int, _ yOffset: Int) {
        ALog.w("Toast", "setGravity() shouldn't be called on text toasts, the values won't be used")
    }

    /// Toast.setMargin: no effect on a text toast of an app targeting Android 11+.
    func setMargin(_ horizontalMargin: Float, _ verticalMargin: Float) {
        ALog.w("Toast", "setMargin() shouldn't be called on text toasts, the values won't be used")
    }

    /// The activity host installed its window: toasts that waited for it appear.
    static func hostDidInstall() {
        KitToastManager.shared.hostDidInstall()
    }
}

// MARK: - NotificationManagerService (queue and timing)

/// The system toast queue (NotificationManagerService.mToastQueue for text toasts) and the SystemUI presenter.
final class KitToastManager {
    static let shared = KitToastManager()

    /// NotificationManagerService.SHORT_DELAY / LONG_DELAY.
    static let SHORT_DELAY: Int64 = 2000
    static let LONG_DELAY: Int64 = 3500
    /// MAX_PACKAGE_TOASTS.
    static let MAX_PACKAGE_TOASTS = 5
    /// scheduleDurationReachedLocked: the previous toast's "out" animation and this toast's "in" animation.
    static let OUT_ANIMATION_DELAY: Int64 = 250
    static let IN_ANIMATION_DELAY: Int64 = 333

    /// One queued text toast (TextToastRecord): the token is the AToast object.
    final class Record {
        let token: AToast
        let text: String
        private(set) var duration: Int

        init(_ token: AToast, _ text: String, _ duration: Int) {
            self.token = token
            self.text = text
            self.duration = duration
        }

        func update(_ duration: Int) { self.duration = duration }
    }

    private(set) var queue: [Record] = []
    private let handler = AHandler(ALooper.getMainLooper())
    private var durationRunnable: ARunnable?
    /// Test hook: the presenter (nil = the UIKit presenter on the activity host's toast layer).
    var presenter: KitToastPresenting?
    private lazy var uiPresenter = KitToastPresenter()

    private var activePresenter: KitToastPresenting { presenter ?? uiPresenter }

    private func indexOfToast(_ token: AToast) -> Int? {
        queue.firstIndex { $0.token === token }
    }

    /// NotificationManagerService.enqueueTextToast (one app: every queued toast is this package's).
    func enqueueTextToast(_ token: AToast, _ text: String, _ duration: Int) {
        let index: Int
        if let existing = indexOfToast(token) {
            // If it's already in the queue, we update it in place, we don't move it to the end of the queue.
            queue[existing].update(duration)
            index = existing
        } else {
            // Limit the number of toasts that any given package can enqueue.
            if queue.count >= KitToastManager.MAX_PACKAGE_TOASTS {
                ALog.e("NotificationService", "Package has already queued \(queue.count) toasts. Not showing more.")
                return
            }
            queue.append(Record(token, text, duration))
            index = queue.count - 1
        }
        // If it's at index 0, it's the current toast. It doesn't matter if it's new or just been updated, show it.
        if index == 0 {
            showNextToast(false)
        }
    }

    /// NotificationManagerService.cancelToast.
    func cancelToast(_ token: AToast) {
        if let index = indexOfToast(token) {
            cancelToast(at: index)
        }
    }

    /// showNextToastLocked: shows the head and schedules its end.
    private func showNextToast(_ lastToastWasTextRecord: Bool) {
        guard let record = queue.first else { return }
        activePresenter.showToast(record)
        scheduleDurationReached(record, lastToastWasTextRecord)
    }

    /// scheduleDurationReachedLocked.
    private func scheduleDurationReached(_ record: Record, _ lastToastWasTextRecord: Bool) {
        if let r = durationRunnable {
            handler.removeCallbacks(r)
        }
        var delay = record.duration == AToast.LENGTH_LONG ? KitToastManager.LONG_DELAY : KitToastManager.SHORT_DELAY
        if lastToastWasTextRecord {
            delay += KitToastManager.OUT_ANIMATION_DELAY
        }
        delay += KitToastManager.IN_ANIMATION_DELAY
        let runnable = ARunnable { [weak self, weak record] in
            guard let self = self, let record = record else { return }
            self.handleDurationReached(record)
        }
        durationRunnable = runnable
        handler.postDelayed(runnable, delay)
    }

    /// handleDurationReached: the record (if still queued) is cancelled.
    private func handleDurationReached(_ record: Record) {
        durationRunnable = nil
        if let index = queue.firstIndex(where: { $0 === record }) {
            cancelToast(at: index)
        }
    }

    /// cancelToastLocked: hide (SystemUI ignores a token that is not showing), remove, show the head (again).
    private func cancelToast(at index: Int) {
        let record = queue[index]
        activePresenter.hideToast(record)
        queue.remove(at: index)
        if index == 0, let r = durationRunnable {
            handler.removeCallbacks(r)
            durationRunnable = nil
        }
        if !queue.isEmpty {
            // Show the next one. If the callback fails, this will remove it from the list, so don't assume that the
            // list hasn't changed after this point.
            showNextToast(true)
        }
    }

    func hostDidInstall() {
        uiPresenter.hostDidInstall()
    }

    /// Tests: empties the queue and the presenter without animations.
    func resetForTesting() {
        if let r = durationRunnable {
            handler.removeCallbacks(r)
        }
        durationRunnable = nil
        queue.removeAll()
        uiPresenter.removeAllImmediately()
    }
}

/// SystemUI's toast presentation (ToastUI.showToast / hideToast).
protocol KitToastPresenting: AnyObject {
    func showToast(_ record: KitToastManager.Record)
    func hideToast(_ record: KitToastManager.Record)
}

// MARK: - SystemUI ToastUI (presentation)

/// ToastUI: one toast view at a time; a new toast replaces the shown one after its "out" animation.
final class KitToastPresenter: KitToastPresenting {
    private var current: (record: KitToastManager.Record, view: KitToastView)?
    /// The view playing its "out" animation, and the toast to show when it ends (ToastOutAnimatorListener).
    private var outAnimating: KitToastView?
    private var showNextAfterOut: (() -> Void)?
    /// A toast that waits for the activity host's window.
    private var waitingForHost: KitToastManager.Record?

    func showToast(_ record: KitToastManager.Record) {
        let show: () -> Void = { [weak self] in
            self?.present(record)
        }
        if outAnimating != nil {
            // If we're currently animating out a toast, show the new toast after the previous one is hidden.
            showNextAfterOut = show
        } else if current != nil {
            hideCurrent(then: show)
        } else {
            show()
        }
    }

    func hideToast(_ record: KitToastManager.Record) {
        if waitingForHost === record {
            waitingForHost = nil
        }
        guard let c = current, c.record === record else { return }
        hideCurrent(then: nil)
    }

    func hostDidInstall() {
        if let record = waitingForHost {
            waitingForHost = nil
            present(record)
        }
    }

    func removeAllImmediately() {
        current?.view.removeFromSuperview()
        current = nil
        outAnimating?.removeFromSuperview()
        outAnimating = nil
        showNextAfterOut = nil
        waitingForHost = nil
    }

    private func present(_ record: KitToastManager.Record) {
        guard let layer = AActivityHost.shared?.toastLayer else {
            waitingForHost = record
            return
        }
        let view = KitToastView(text: record.text)
        current = (record, view)
        layer.addSubview(view)
        view.layoutIn(layer)
        // The toast window stays bottom-centred when the screen rotates.
        view.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin, .flexibleTopMargin]
        view.animateIn()
    }

    /// ToastUI.hideCurrentToast: the "out" animation, then the view goes and the next toast (if any) shows.
    private func hideCurrent(then next: (() -> Void)?) {
        guard let c = current else {
            next?()
            return
        }
        current = nil
        outAnimating = c.view
        showNextAfterOut = next
        c.view.animateOut { [weak self] in
            guard let self = self else { return }
            c.view.removeFromSuperview()
            if self.outAnimating === c.view {
                self.outAnimating = nil
            }
            let pending = self.showNextAfterOut
            self.showNextAfterOut = nil
            pending?()
        }
    }
}

// MARK: - The toast view (text_toast.xml)

/// SystemUI text_toast.xml in UIKit points (1 dp = 1 pt).
final class KitToastView: UIView {
    /// toast_width is not applied to the LinearLayout (android:maxWidth is a TextView attribute); the WRAP_CONTENT
    /// toast window is first measured at config_prefDialogWidth, which is what bounds it.
    static var maxWidth: CGFloat {
        let config = AConfiguration.current
        if config.smallestScreenWidthDp >= 600 { return 580 }
        if (config.screenLayout & AConfiguration.SCREENLAYOUT_SIZE_MASK) >= AConfiguration.SCREENLAYOUT_SIZE_LARGE {
            return 440
        }
        return 320
    }

    static let yOffset: CGFloat = 48           // toast_y_offset
    static let cornerRadius: CGFloat = 28      // toast_frame
    static let paddingHorizontal: CGFloat = 16
    static let iconSize: CGFloat = 24
    static let iconMarginVertical: CGFloat = 10
    static let iconMarginEnd: CGFloat = 10
    static let textPaddingVertical: CGFloat = 12
    static let textSize: CGFloat = 14
    static let lineHeight: CGFloat = 20
    static let elevation: CGFloat = 2

    let face = UIView()
    let iconView = UIImageView()
    let label = UILabel()
    private let text: String
    private let rtl: Bool

    init(text: String) {
        self.text = text
        rtl = AConfiguration.isRtl(ALocale.getDefault())
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        accessibilityElementsHidden = false

        let dark = KitToastView.isDarkSystemTheme
        // AOSP defaults of the dynamic colours the toast uses (system_surface_container_*, system_on_surface_*).
        let surface = dark ? AColor.uiColor(argbInt(0xFF17191F)) : AColor.uiColor(argbInt(0xFFEDEDF6))
        let onSurface = dark ? AColor.uiColor(argbInt(0xFFE4E5F0)) : AColor.uiColor(argbInt(0xFF30323A))

        face.backgroundColor = surface
        face.layer.cornerRadius = KitToastView.cornerRadius
        face.layer.cornerCurve = .circular
        face.layer.shadowColor = UIColor.black.cgColor
        face.layer.shadowOpacity = 0.26
        face.layer.shadowRadius = 0.666920 * KitToastView.elevation - 0.001648
        face.layer.shadowOffset = CGSize(width: 0, height: 1.23118 * KitToastView.elevation - 0.03933)
        addSubview(face)

        iconView.image = KitToastView.appIcon
        iconView.contentMode = .scaleAspectFit
        iconView.isHidden = iconView.image == nil
        face.addSubview(iconView)

        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = KitToastView.lineHeight
        paragraph.maximumLineHeight = KitToastView.lineHeight
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.alignment = .natural
        paragraph.baseWritingDirection = rtl ? .rightToLeft : .natural
        let font = UIFont.systemFont(ofSize: KitToastView.textSize, weight: .medium)
        label.attributedText = NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: onSurface, .paragraphStyle: paragraph,
            .baselineOffset: (KitToastView.lineHeight - font.lineHeight) / 4,
        ])
        label.numberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
        face.addSubview(label)

        isAccessibilityElement = true
        accessibilityLabel = text
        accessibilityTraits = .staticText
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { preconditionFailure("KitToastView is created in code") }

    static var isDarkSystemTheme: Bool {
        if let host = AActivityHost.shared, host.isViewLoaded {
            return host.view.traitCollection.userInterfaceStyle == .dark
        }
        return UIScreen.main.traitCollection.userInterfaceStyle == .dark
    }

    /// The launcher icon as IconDrawableFactory badges it: the adaptive icon (background #03122D, foreground
    /// tripleshot_launcher_art inset 16 of 108 dp) drawn at 1.5x and masked to the device's circle.
    static let appIcon: UIImage? = {
        guard let art = AResources.cgImage("tripleshot_launcher_art") else { return nil }
        let size: CGFloat = 96
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            cg.addEllipse(in: CGRect(x: 0, y: 0, width: size, height: size))
            cg.clip()
            // 108 dp layers drawn so that the 72 dp safe zone fills the icon.
            let layer = size * 108 / 72
            let origin = (size - layer) / 2
            cg.setFillColor(AColor.cgColor(argbInt(0xFF03122D)))
            cg.fill(CGRect(x: origin, y: origin, width: layer, height: layer))
            let inset = layer * 16 / 108
            let artRect = CGRect(x: origin + inset, y: origin + inset, width: layer - 2 * inset, height: layer - 2 * inset)
            // CGContext draws images upside down in UIKit coordinates.
            cg.saveGState()
            cg.translateBy(x: 0, y: size)
            cg.scaleBy(x: 1, y: -1)
            cg.draw(art, in: CGRect(x: artRect.minX, y: size - artRect.maxY, width: artRect.width, height: artRect.height))
            cg.restoreGState()
        }
    }()

    /// Measures and places the toast: bottom | center_horizontal, 48 dp above the system bars (fitInsetsIgnoringVisibility).
    func layoutIn(_ container: UIView) {
        let bounds = container.bounds
        let safe = container.safeAreaInsets
        let available = bounds.width - safe.left - safe.right
        let outerMax = min(KitToastView.maxWidth, available)
        let hasIcon = !iconView.isHidden
        let iconBlock = hasIcon ? KitToastView.iconSize + KitToastView.iconMarginEnd : 0
        let textMax = max(0, outerMax - 2 * KitToastView.paddingHorizontal - iconBlock)
        let fitted = label.sizeThatFits(CGSize(width: textMax, height: CGFloat.greatestFiniteMagnitude))
        let lines = max(1, min(2, Int((fitted.height / KitToastView.lineHeight).rounded())))
        let textWidth = min(ceil(fitted.width), textMax)
        let textHeight = CGFloat(lines) * KitToastView.lineHeight
        let width = 2 * KitToastView.paddingHorizontal + iconBlock + textWidth
        let height = max(hasIcon ? KitToastView.iconSize + 2 * KitToastView.iconMarginVertical : 0,
                         textHeight + 2 * KitToastView.textPaddingVertical)
        let x = safe.left + ((available - width) / 2).rounded(.down)
        let y = bounds.height - safe.bottom - KitToastView.yOffset - height
        frame = CGRect(x: x, y: y, width: width, height: height)
        face.frame = CGRect(x: 0, y: 0, width: width, height: height)
        face.layer.shadowPath = UIBezierPath(roundedRect: face.bounds,
                                             cornerRadius: min(KitToastView.cornerRadius, height / 2)).cgPath
        var cursor = KitToastView.paddingHorizontal
        let iconY = (height - KitToastView.iconSize) / 2
        let textY = (height - textHeight) / 2
        if rtl {
            cursor = width - KitToastView.paddingHorizontal
            if hasIcon {
                iconView.frame = CGRect(x: cursor - KitToastView.iconSize, y: iconY, width: KitToastView.iconSize,
                                        height: KitToastView.iconSize)
                cursor -= iconBlock
            }
            label.frame = CGRect(x: cursor - textWidth, y: textY, width: textWidth, height: textHeight)
        } else {
            if hasIcon {
                iconView.frame = CGRect(x: cursor, y: iconY, width: KitToastView.iconSize, height: KitToastView.iconSize)
                cursor += iconBlock
            }
            label.frame = CGRect(x: cursor, y: textY, width: textWidth, height: textHeight)
        }
    }

    /// ToastDefaultAnimation.toastIn.
    func animateIn() {
        transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        alpha = 0
        label.alpha = 0
        iconView.alpha = 0
        let scale = UIViewPropertyAnimator(duration: 0.333, timingParameters:
            UICubicTimingParameters(controlPoint1: CGPoint(x: 0, y: 0), controlPoint2: CGPoint(x: 0, y: 1)))
        scale.addAnimations { self.transform = .identity }
        scale.startAnimation()
        UIView.animate(withDuration: 0.066, delay: 0, options: [.curveLinear], animations: { self.alpha = 1 })
        UIView.animate(withDuration: 0.283, delay: 0.05, options: [.curveLinear], animations: {
            self.label.alpha = 1
            self.iconView.alpha = 1
        })
    }

    /// ToastDefaultAnimation.toastOut; `done` runs when the 250 ms set ends.
    func animateOut(_ done: @escaping () -> Void) {
        let scale = UIViewPropertyAnimator(duration: 0.25, timingParameters:
            UICubicTimingParameters(controlPoint1: CGPoint(x: 0.3, y: 0), controlPoint2: CGPoint(x: 1, y: 1)))
        scale.addAnimations { self.transform = CGAffineTransform(scaleX: 0.9, y: 0.9) }
        scale.addCompletion { _ in done() }
        scale.startAnimation()
        UIView.animate(withDuration: 0.166, delay: 0, options: [.curveLinear], animations: {
            self.label.alpha = 0
            self.iconView.alpha = 0
        })
        UIView.animate(withDuration: 0.1, delay: 0.15, options: [.curveLinear], animations: { self.alpha = 0 })
        UIView.animate(withDuration: 0.04, delay: 0.15, options: [.curveLinear], animations: {
            self.face.layer.shadowOpacity = 0
        })
    }
}
