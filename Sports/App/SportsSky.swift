import SwiftUI
import UIKit

/// The shared Android presentation the sports pages use since 13 October 2026 (MinikFamilyServices
/// FamilySkyDrawable, FamilyReadingPanel, FamilyFormStyle and FamilyTournamentUi.divider), drawn in
/// this app's own code: raised, glossy surfaces whose depth stays inside the view's bounds, the
/// narrower centred column of a landscape window, the white form field and the dashed divider.
enum SportsSky {
    /// Android `FamilySkyDrawable.palette`: a pale, mid-saturation fill becomes Maze's equivalent of
    /// its hue (purple, blue, green or yellow); gray-ish and strong colours keep their value.
    static func palette(_ color: UInt32) -> UInt32 {
        let r = Double((color >> 16) & 0xff)
        let g = Double((color >> 8) & 0xff)
        let b = Double(color & 0xff)
        let high = max(r, g, b)
        let low = min(r, g, b)
        let saturation = high == 0 ? 0 : (high - low) / high
        if saturation < 0.12 || saturation > 0.48 { return color }
        let delta = high - low
        var hue: Double
        if delta == 0 {
            hue = 0
        } else if high == r {
            hue = 60 * ((g - b) / delta)
        } else if high == g {
            hue = 60 * ((b - r) / delta) + 120
        } else {
            hue = 60 * ((r - g) / delta) + 240
        }
        if hue < 0 { hue += 360 }
        let mapped: UInt32
        if hue >= 265 && hue < 325 {
            mapped = 0xffd8bfff
        } else if hue >= 175 && hue < 265 {
            mapped = 0xffa6dcff
        } else if hue >= 65 && hue < 175 {
            mapped = 0xffb1eddb
        } else if hue >= 30 && hue < 65 {
            mapped = 0xffffe59d
        } else {
            mapped = color
        }
        return (color & 0xff000000) | (mapped & 0x00ffffff)
    }

    /// Android `FamilySkyDrawable.blend`: an opaque mix of two colours.
    static func blend(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
        func channel(_ shift: UInt32) -> UInt32 {
            let x = Double((a >> shift) & 0xff) * (1 - t) + Double((b >> shift) & 0xff) * t
            return UInt32(max(0, min(255, x.rounded())))
        }
        return 0xff000000 | (channel(16) << 16) | (channel(8) << 8) | channel(0)
    }

    private static func rounded(_ rect: CGRect, _ radius: CGFloat) -> Path {
        let r = max(0, min(radius, rect.width / 2, rect.height / 2))
        return Path(roundedRect: rect, cornerRadius: r, style: .circular)
    }

    /// Android `FamilySkyDrawable.draw`: the darker edge, the gradient face (lowered while pressed),
    /// the rim, the inner highlight and, on controls, the shine. `pixel` is one device pixel.
    static func draw(_ context: inout GraphicsContext, _ size: CGSize, color: UInt32, radius: CGFloat, panel: Bool,
                     pressed: Bool, enabled: Bool, strokeWidth: CGFloat, strokeColor: UInt32, pixel: CGFloat) {
        let base = palette(color)
        let alpha = Double((base >> 24) & 0xff) / 255
        if alpha <= 0 || size.width <= 0 || size.height <= 0 { return }
        let box = CGRect(origin: .zero, size: size)
        let shortSide = min(size.width, size.height)
        let depth = min(shortSide * 0.075, max(2 * pixel, radius * 0.28))
        let rim = max(pixel, min(shortSide * 0.026, radius * 0.08))
        let r = Int((base >> 16) & 0xff)
        let g = Int((base >> 8) & 0xff)
        let b = Int(base & 0xff)
        let pale = max(r, g, b) - min(r, g, b) < 132
        // Dark HUD/selection surfaces carry white text; they are not washed into pale gray.
        let dark = (r * 299 + g * 587 + b * 114) / 1000 < 130
        var upper = blend(base, 0xffffffff, dark ? 0.08 : (pale ? 0.75 : 0.22))
        var lower = blend(base, 0xffffffff, dark ? 0.015 : (pale ? 0.32 : 0.02))
        var edge = blend(base, 0xff204878, 0.28)
        if !enabled && !panel {
            upper = 0xffeef3f7
            lower = 0xffdce7ef
            edge = 0xffb4cadb
        }
        let sunk = pressed && !panel
        let top = sunk ? depth * 0.65 : 0
        let bottom = sunk ? depth * 0.3 : depth
        let face = CGRect(x: rim, y: rim + top, width: size.width - 2 * rim, height: size.height - 2 * rim - top - bottom)
        if face.width <= 0 || face.height <= 0 { return }
        var layered = context
        layered.opacity = alpha
        layered.drawLayer { layer in
            layer.fill(rounded(box.insetBy(dx: rim, dy: rim), radius), with: .color(SportsPalette.color(edge)))
            let facePath = rounded(face, radius)
            if panel || (r > 238 && g > 238 && b > 238) {
                let colors = [blend(0xffdff5ff, base, 0.1), 0xfffffef2, 0xfff4fbff, blend(0xffffdeeb, base, 0.08)].map { SportsPalette.color($0) }
                layer.fill(facePath, with: .linearGradient(Gradient(colors: colors), startPoint: CGPoint(x: face.minX, y: face.minY),
                                                           endPoint: CGPoint(x: face.maxX, y: face.maxY)))
            } else {
                let stops = [Gradient.Stop(color: SportsPalette.color(upper), location: 0),
                             Gradient.Stop(color: SportsPalette.color(lower), location: 0.48),
                             Gradient.Stop(color: SportsPalette.color(lower), location: 1)]
                layer.fill(facePath, with: .linearGradient(Gradient(stops: stops), startPoint: CGPoint(x: 0, y: face.minY),
                                                           endPoint: CGPoint(x: 0, y: face.maxY)))
            }
            let outline = strokeWidth > 0 ? strokeColor : blend(base, 0xffffffff, 0.22)
            layer.stroke(facePath, with: .color(SportsPalette.color(outline)), lineWidth: strokeWidth > 0 ? strokeWidth : rim)
            let inner = face.insetBy(dx: rim * 2, dy: rim * 2)
            if inner.width > 0 && inner.height > 0 {
                layer.stroke(rounded(inner, max(pixel, radius - rim * 2)), with: .color(SportsPalette.color(0xb8ffffff)), lineWidth: rim)
            }
            if !panel {
                let dx = min(radius * 0.8, face.width * 0.12)
                let width = face.width - 2 * dx
                let height = min(face.height - 6 * rim, face.height * 0.25)
                if width > 0 && height > 0 {
                    let shine = CGRect(x: face.minX + dx, y: face.minY + rim * 3, width: width, height: height)
                    let end = face.minY + min(face.height * 0.40, radius)
                    layer.fill(rounded(shine, height / 2),
                               with: .linearGradient(Gradient(colors: [SportsPalette.color(0xbbffffff), SportsPalette.color(0x00ffffff)]),
                                                     startPoint: CGPoint(x: 0, y: face.minY), endPoint: CGPoint(x: 0, y: end)))
                }
            }
        }
    }

    /// Android `FamilyReadingPanel.contentWidth`: a portrait window uses its whole width; a landscape
    /// window centres a column of about half its width (300 to 520 points).
    static func contentWidth(_ available: CGFloat, landscape: Bool) -> CGFloat {
        if !landscape { return available }
        return min(available, min(520, max(300, (available * 0.52).rounded())))
    }

    /// The reading column inside Android's 20 dp side padding.
    @MainActor static func textColumn(_ geo: GeometryProxy) -> CGFloat {
        let insets = geo.safeAreaInsets
        let landscape = geo.size.width + insets.leading + insets.trailing > geo.size.height + insets.top + insets.bottom
        return max(0, contentWidth(geo.size.width, landscape: landscape) - 40)
    }

    /// The page column: the reading column, at most 520 points (Android's button width).
    @MainActor static func column(_ geo: GeometryProxy) -> CGFloat {
        return min(520, textColumn(geo))
    }
}

/// Android `FamilySkyDrawable` as a background. `panel` is the quieter surface of section boxes and
/// dialogs (no shine, never pressed); a transparent colour draws nothing.
struct SportsSkySurface: View {
    let color: UInt32
    var radius: CGFloat = 18
    var panel = false
    var pressed = false
    var enabled = true
    var strokeWidth: CGFloat = 0
    var strokeColor: UInt32 = 0
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let pixel = 1 / max(displayScale, 1)
        let color = self.color
        let radius = self.radius
        let panel = self.panel
        let pressed = self.pressed
        let enabled = self.enabled
        let strokeWidth = self.strokeWidth
        let strokeColor = self.strokeColor
        Canvas { context, size in
            SportsSky.draw(&context, size, color: color, radius: radius, panel: panel, pressed: pressed, enabled: enabled,
                           strokeWidth: strokeWidth, strokeColor: strokeColor, pixel: pixel)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A button on a raised sky surface whose face sinks while it is pressed (Android's pressed state).
struct SportsSkyButtonStyle: ButtonStyle {
    let color: UInt32
    var radius: CGFloat = 18
    var enabled = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(SportsSkySurface(color: color, radius: radius, pressed: configuration.isPressed && enabled, enabled: enabled))
            .contentShape(Rectangle())
    }
}

/// Android `FamilyFormStyle`: an informational colour label is flat, with 8 point corners.
struct SportsFlatLabel: View {
    let color: UInt32

    var body: some View {
        RoundedRectangle(cornerRadius: 8).fill(SportsPalette.color(color))
    }
}

/// Android `FamilyTournamentUi.divider`: the dashed line between creating and joining a room.
struct SportsDashedDivider: View {
    var body: some View {
        SportsDashLine()
            .stroke(SportsPalette.color(0xff7892ad), style: StrokeStyle(lineWidth: 2, dash: [7, 6]))
            .frame(height: 2)
            .padding(.horizontal, 8)
            .padding(.vertical, 24)
            .accessibilityHidden(true)
    }
}

private struct SportsDashLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

/// Android `FamilyFormStyle` for an EditText on a page: a white field with 8 point corners and a
/// one point outline that turns blue while it has focus.
struct SportsField: View {
    let placeholder: String
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text, prompt: Text(placeholder).foregroundColor(SportsPalette.color(0xff536b7b)))
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled(true)
            .multilineTextAlignment(.center)
            .font(.system(size: 18))
            .foregroundColor(SportsPalette.color(0xff17384d))
            .focused($focused)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 56, maxHeight: 56)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(SportsPalette.color(focused ? 0xff2587d6 : 0xff879baa), lineWidth: 1))
    }
}

// MARK: Orientation (Squash)

/// Android `requestedOrientation`: Minik Squash shows its pages in portrait and lets a match follow
/// the device (FULL_SENSOR); Beach Volleyball always follows the device (the root view controller
/// still leaves out upside-down portrait on iPhone).
@MainActor final class SportsAppDelegate: NSObject, UIApplicationDelegate {
    static var orientations: UIInterfaceOrientationMask = SportsLaunch.sport == .squash ? .portrait : .all

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return SportsAppDelegate.orientations
    }
}

@MainActor enum SportsOrientation {
    /// Android FULL_SENSOR within the Info.plist orientations (iPhone: no upside-down portrait).
    static var full: UIInterfaceOrientationMask {
        return UIDevice.current.userInterfaceIdiom == .pad ? .all : .allButUpsideDown
    }

    static func apply(_ mask: UIInterfaceOrientationMask) {
        if SportsAppDelegate.orientations == mask { return }
        SportsAppDelegate.orientations = mask
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
        }
    }
}

// MARK: "More below" (Android FamilyMoreFrame)

/// Follows the UIScrollView behind a page's SwiftUI ScrollView: whether more of the menu lies below,
/// and scrolling it by about two thirds of its height, as Android's "More below" cue does.
@MainActor
final class SportsScrollCue: ObservableObject {
    @Published private(set) var more = false
    private weak var scrollView: UIScrollView?
    private var observations: [NSKeyValueObservation] = []

    func attach(_ view: UIScrollView) {
        if scrollView === view {
            scheduleRefresh()
            return
        }
        scrollView = view
        observations = [
            view.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
                let cue = self
                Task { @MainActor in cue?.refresh() }
            },
            view.observe(\.contentSize, options: [.new]) { [weak self] _, _ in
                let cue = self
                Task { @MainActor in cue?.refresh() }
            },
            view.observe(\.bounds, options: [.new]) { [weak self] _, _ in
                let cue = self
                Task { @MainActor in cue?.refresh() }
            }
        ]
        scheduleRefresh()
    }

    private func scheduleRefresh() {
        Task { @MainActor [weak self] in self?.refresh() }
    }

    /// Android `scroll.canScrollVertically(1)`.
    func refresh() {
        guard let s = scrollView, s.window != nil else {
            if more { more = false }
            return
        }
        let next = s.contentOffset.y + s.bounds.height - s.adjustedContentInset.bottom < s.contentSize.height - 1
        if next != more { more = next }
    }

    /// Android `scroll.smoothScrollBy(0, round(height * 0.65))`.
    func scrollDown() {
        guard let s = scrollView else { return }
        let bottom = max(-s.adjustedContentInset.top, s.contentSize.height + s.adjustedContentInset.bottom - s.bounds.height)
        let y = min(s.contentOffset.y + (s.bounds.height * 0.65).rounded(), bottom)
        s.setContentOffset(CGPoint(x: s.contentOffset.x, y: y), animated: true)
    }
}

/// A transparent view inside the scrolled content that finds its UIScrollView for the cue.
final class SportsScrollProbeView: UIView {
    weak var cue: SportsScrollCue?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        attach()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        attach()
    }

    private func attach() {
        guard window != nil else { return }
        var next = superview
        while let view = next {
            if let scroll = view as? UIScrollView {
                cue?.attach(scroll)
                return
            }
            next = view.superview
        }
    }
}

@MainActor
struct SportsScrollProbe: UIViewRepresentable {
    let cue: SportsScrollCue

    func makeUIView(context: Context) -> SportsScrollProbeView {
        let view = SportsScrollProbeView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.cue = cue
        return view
    }

    func updateUIView(_ view: SportsScrollProbeView, context: Context) {
        view.cue = cue
    }
}
