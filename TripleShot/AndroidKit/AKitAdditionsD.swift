import Foundation
import ObjectiveC
import UIKit

// AndroidKit additions used by the Android 6c38131 menus (TripleShotTopicsDialog, TripleShotLeaderboardFragment):
// android.widget.CheckBox with `buttonTintList`, and Material TabLayout.Tab.setCustomView.

// MARK: - android.widget.CheckBox

/// android.widget.CheckBox built in code (`CheckBox(context)`, Widget.Material.CompoundButton.CheckBox): the
/// `?android:listChoiceIndicatorMultiple` button (btn_check_material_anim, 32 x 32 dp) at the start, before the text
/// (CompoundButton.getCompoundPaddingLeft / Right add its width on the start side; onDraw places it by the vertical
/// gravity). The vector is drawn as Material draws its frames: an 18 dp box with 2 dp corners, outlined with a 2 dp
/// stroke when unchecked, filled with the check mark cut out when checked; both in the button tint for the state
/// (default colorControlActivated / the unchecked control colour). Approximation: the cut-out check shows the
/// dialog surface colour under it on Android; here it is painted in the box's darkest neighbour (#132841, the
/// Topics dialog's gradient end), the only place the app uses a CheckBox.
class ACheckBox: ACompoundButton {
    /// CompoundButton.setButtonTintList / getButtonTintList.
    var buttonTintList: AColorStateList? {
        didSet { invalidate() }
    }

    private let boxPaint = APaint(APaint.ANTI_ALIAS_FLAG)
    private let markPaint = APaint(APaint.ANTI_ALIAS_FLAG)
    private let markPath = APath()

    override init() {
        super.init()
        isClickable = true
        isFocusable = true
    }

    override init(style: Style) {
        super.init(style: style)
        isClickable = true
        isFocusable = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setButtonTintList(_ tint: AColorStateList?) { buttonTintList = tint }

    /// The button drawable's intrinsic size (32 dp).
    private var buttonSize: Int { ATypedValue.toDimensionPixelSize(ATypedValue.COMPLEX_UNIT_DIP, 32) }

    override var compoundPaddingLeft: Int {
        if isLayoutRtl { return super.compoundPaddingLeft }
        return super.compoundPaddingLeft + buttonSize
    }

    override var compoundPaddingRight: Int {
        if !isLayoutRtl { return super.compoundPaddingRight }
        return super.compoundPaddingRight + buttonSize
    }

    override func onDraw(_ canvas: ACanvas) {
        let size = buttonSize
        let verticalGravity = gravity & AGravity.VERTICAL_GRAVITY_MASK
        let top: Int
        switch verticalGravity {
        case AGravity.BOTTOM: top = height - size
        case AGravity.CENTER_VERTICAL: top = (height - size) / 2
        default: top = 0
        }
        let left = isLayoutRtl ? width - size : 0
        let unit = Float(size) / 32
        let fallback = isChecked ? AWMaterialColors.colorControlActivated : AColor.argb(0x8A, 0, 0, 0)
        let color = buttonTintList?.getColorForState(drawableState, fallback) ?? fallback
        let box = ARectF(Float(left) + 7 * unit, Float(top) + 7 * unit, Float(left) + 25 * unit, Float(top) + 25 * unit)
        boxPaint.color = color
        if isChecked {
            boxPaint.style = .FILL
            canvas.drawRoundRect(box, 2 * unit, 2 * unit, boxPaint)
            markPaint.color = argbInt(0xff132841)
            markPaint.style = .STROKE
            markPaint.strokeWidth = 2 * unit
            markPaint.strokeCap = .SQUARE
            markPaint.strokeJoin = .MITER
            markPath.reset()
            markPath.moveTo(box.left + 3.5 * unit, box.top + 9 * unit)
            markPath.lineTo(box.left + 7 * unit, box.top + 12.5 * unit)
            markPath.lineTo(box.left + 14.5 * unit, box.top + 5 * unit)
            canvas.drawPath(markPath, markPaint)
        } else {
            boxPaint.style = .STROKE
            boxPaint.strokeWidth = 2 * unit
            let inset = ARectF(box.left + unit, box.top + unit, box.right - unit, box.bottom - unit)
            canvas.drawRoundRect(inset, unit, unit, boxPaint)
        }
        super.onDraw(canvas)
    }
}

// MARK: - TabLayout.Tab.setCustomView

private var kitTabCustomViewKey: UInt8 = 0

extension ATabLayout.Tab {
    /// Material TabLayout.Tab.setCustomView / getCustomView. TabView.update then hosts the custom view instead of its
    /// own label: the custom view is added to the tab's view and the default label is taken out of it (Material sets
    /// it GONE; AndroidKit's TabView re-shows its label on every update, so it is removed from the tab view instead,
    /// which keeps it out of measure, layout and drawing in the same way).
    var customView: AView? {
        get { return objc_getAssociatedObject(self, &kitTabCustomViewKey) as? AView }
        set {
            objc_setAssociatedObject(self, &kitTabCustomViewKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            installCustomView(newValue)
        }
    }

    @discardableResult
    func setCustomView(_ view: AView?) -> ATabLayout.Tab {
        customView = view
        return self
    }

    func getCustomView() -> AView? { return customView }

    /// The tab's AWTabView: child `position` of the sliding strip (the TabLayout's first child).
    private var tabView: AWTabView? {
        guard let layout = parent, let strip = layout.getChildAt(0) as? AViewGroup else { return nil }
        return strip.getChildAt(getPosition()) as? AWTabView
    }

    private func installCustomView(_ custom: AView?) {
        guard let host = tabView else { return }
        if let custom = custom {
            if let old = custom.parentGroup, old !== host { old.removeView(custom) }
            // The default label is the TabView's first ATextView child that is not the custom view.
            for i in stride(from: host.childCount - 1, through: 0, by: -1) {
                if let child = host.getChildAt(i), child !== custom, child is ATextView { host.removeView(child) }
            }
            if custom.parentGroup == nil { host.addView(custom) }
            custom.setSelected(isSelected)
        }
        host.requestLayout()
    }
}

// MARK: - View.setClipToOutline with ViewOutlineProvider.BACKGROUND

/// android.widget.FrameLayout with `clipToOutline = true` and `outlineProvider = ViewOutlineProvider.BACKGROUND`
/// (the only outline the app clips to): the view and its children are clipped to the background drawable's outline
/// (Drawable.getOutline of an ADrawableOutlineProvider such as FamilySkyDrawable: a rounded rectangle). AView has no
/// clipToOutline property yet, so this frame applies the clip as a layer mask after every layout (outline in px,
/// mask in points). A background without an outline clips nothing, as on Android.
class AOutlineClippedFrameLayout: AFrameLayout {
    var clipToOutline = true {
        didSet { updateOutlineClip() }
    }

    private let outlineMask = CAShapeLayer()

    override func onLayout(_ changed: Bool, _ left: Int, _ top: Int, _ right: Int, _ bottom: Int) {
        super.onLayout(changed, left, top, right, bottom)
        updateOutlineClip()
    }

    private func updateOutlineClip() {
        guard clipToOutline, width > 0, height > 0, let drawable = background,
              let provider = drawable as? ADrawableOutlineProvider else {
            if layer.mask != nil { layer.mask = nil }
            return
        }
        drawable.setBounds(0, 0, width, height)
        let outline = AOutline()
        provider.getOutline(outline)
        guard let rect = outline.rect else {
            if layer.mask != nil { layer.mask = nil }
            return
        }
        let d = AView.densityScale
        let box = CGRect(x: CGFloat(rect.left) / d, y: CGFloat(rect.top) / d,
                         width: CGFloat(rect.right - rect.left) / d, height: CGFloat(rect.bottom - rect.top) / d)
        let path = outline.isOval ? UIBezierPath(ovalIn: box) : UIBezierPath(roundedRect: box, cornerRadius: CGFloat(outline.radius) / d)
        outlineMask.frame = CGRect(origin: .zero, size: bounds.size)
        outlineMask.path = path.cgPath
        if layer.mask !== outlineMask { layer.mask = outlineMask }
    }
}

// MARK: - View.setLabelFor

private var kitLabelForKey: UInt8 = 0

extension AView {
    /// View.setLabelFor / getLabelFor (android:labelFor): the id of the view this one labels. Android uses it only for
    /// accessibility (TalkBack reads the label with the field); it is kept as data here, the field keeps its own hint.
    var labelFor: String? {
        get { return objc_getAssociatedObject(self, &kitLabelForKey) as? String }
        set { objc_setAssociatedObject(self, &kitLabelForKey, newValue, .OBJC_ASSOCIATION_COPY_NONATOMIC) }
    }
}
