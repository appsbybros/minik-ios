import SwiftUI
import UIKit

/// Android `com.appsbybros.family.FamilySkyDrawable` (2026-10-13), the shared raised "sky" surface of the Minik
/// games: a glossy face drawn inside the view's own bounds. A darker edge below the face gives the depth, a light rim
/// and an inner highlight frame it, and controls get a soft shine. Pressed controls sink into their edge. Panels (menu
/// sections, dialogs, white fills) use the pale sky face. Colours keep their roles; only mid-pale fills move to the
/// shared palette. Only the drawing is ported here: Android's version lives in the shared family module, whose iOS
/// port has no surface API.
enum SkyPalette {
    static let white: UInt32 = 0xffffffff

    static func red(_ c: UInt32) -> Int { return Int((c >> 16) & 0xff) }
    static func green(_ c: UInt32) -> Int { return Int((c >> 8) & 0xff) }
    static func blue(_ c: UInt32) -> Int { return Int(c & 0xff) }
    static func alpha(_ c: UInt32) -> Int { return Int((c >> 24) & 0xff) }

    /// Android `FamilySkyDrawable.blend(a, b, t)`: an opaque mix of the two colours.
    static func blend(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
        func mix(_ x: Int, _ y: Int) -> UInt32 {
            let v = (Double(x) * (1 - t) + Double(y) * t).rounded()
            return UInt32(max(0, min(255, v)))
        }
        return 0xff000000 | (mix(red(a), red(b)) << 16) | (mix(green(a), green(b)) << 8) | mix(blue(a), blue(b))
    }

    /// Android `Color.colorToHSV`: hue in degrees and saturation.
    static func hueSaturation(_ c: UInt32) -> (hue: Double, saturation: Double) {
        let r = red(c), g = green(c), b = blue(c)
        let high = max(r, max(g, b))
        let low = min(r, min(g, b))
        let delta = high - low
        if delta == 0 { return (0, 0) }
        let s = Double(delta) / Double(high)
        var h: Double
        if r == high {
            h = Double(g - b) / Double(delta)
        } else if g == high {
            h = 2 + Double(b - r) / Double(delta)
        } else {
            h = 4 + Double(r - g) / Double(delta)
        }
        h *= 60
        if h < 0 { h += 360 }
        return (h, s)
    }

    /// Android `FamilySkyDrawable.palette(color)`: keeps hue roles; only mid-pale fills take the Maze equivalents.
    static func palette(_ color: UInt32) -> UInt32 {
        let hs = hueSaturation(color)
        if hs.saturation < 0.12 { return color }
        if hs.saturation > 0.48 { return color }
        let h = hs.hue
        let mapped: UInt32
        if h >= 265 && h < 325 {
            mapped = 0xffd8bfff
        } else if h >= 175 && h < 265 {
            mapped = 0xffa6dcff
        } else if h >= 65 && h < 175 {
            mapped = 0xffb1eddb
        } else if h >= 30 && h < 65 {
            mapped = 0xffffe59d
        } else {
            mapped = color
        }
        return (color & 0xff000000) | (mapped & 0x00ffffff)
    }

    /// Android `bg(color)` in the Spud activity: white and the two near-white fills are panels.
    static func isPanelFill(_ color: UInt32) -> Bool {
        return color == 0xffffffff || color == 0xfff5f7fd || color == 0xfff6f8ff
    }
}

/// Android `FamilySkyDrawable.draw` for one surface (sizes in points; Android's 1 px and 2 px floors use the screen
/// scale).
struct SkySurface: View {
    let color: UInt32
    var radius: CGFloat = 18
    var panel = false
    var strokeWidth: CGFloat = 0
    var strokeColor: UInt32 = 0
    var pressed = false
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let fill = color
        let corner = radius
        let isPanel = panel
        let lineWidth = strokeWidth
        let lineColor = strokeColor
        let down = pressed
        let px = 1 / max(displayScale, 1)
        let opacity = Double(SkyPalette.alpha(SkyPalette.palette(fill))) / 255
        return Canvas { context, size in
            SkyPainter.draw(&context, size, color: fill, radius: corner, panel: isPanel, strokeWidth: lineWidth,
                            strokeColor: lineColor, pressed: down, px: px)
        }
        // Android draws the whole surface in one layer at the colour's alpha.
        .opacity(opacity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The drawing of `SkySurface` (kept outside the view so the canvas renderer calls no view code).
enum SkyPainter {
    private static func rounded(_ rect: CGRect, _ radius: CGFloat) -> Path {
        let r = max(0, min(radius, rect.width / 2, rect.height / 2))
        return Path(roundedRect: rect, cornerRadius: r, style: .circular)
    }

    private static func usable(_ rect: CGRect) -> Bool {
        return !rect.isNull && !rect.isEmpty && rect.width > 0 && rect.height > 0
    }

    static func draw(_ context: inout GraphicsContext, _ size: CGSize, color: UInt32, radius: CGFloat, panel: Bool,
                     strokeWidth: CGFloat, strokeColor: UInt32, pressed: Bool, px: CGFloat) {
        let box = CGRect(origin: .zero, size: size)
        guard usable(box) else { return }
        let base = SkyPalette.palette(color)
        if SkyPalette.alpha(base) == 0 { return }
        let r = SkyPalette.red(base), g = SkyPalette.green(base), b = SkyPalette.blue(base)
        let shortSide = min(box.width, box.height)
        let depth = min(shortSide * 0.075, max(2 * px, radius * 0.28))
        let rim = max(px, min(shortSide * 0.026, radius * 0.08))
        let pale = max(r, max(g, b)) - min(r, min(g, b)) < 132
        // Dark HUD/selection surfaces carry white text; they are not washed into pale grey.
        let dark = (r * 299 + g * 587 + b * 114) / 1000 < 130
        let upper = SkyPalette.blend(base, SkyPalette.white, dark ? 0.08 : pale ? 0.75 : 0.22)
        let lower = SkyPalette.blend(base, SkyPalette.white, dark ? 0.015 : pale ? 0.32 : 0.02)
        let edge = SkyPalette.blend(base, 0xff204878, 0.28)
        let sinks = pressed && !panel
        let inset = box.insetBy(dx: rim, dy: rim)
        guard usable(inset) else { return }
        let top = inset.minY + (sinks ? depth * 0.65 : 0)
        let bottom = inset.maxY - (sinks ? depth * 0.3 : depth)
        let face = CGRect(x: inset.minX, y: top, width: inset.width, height: max(0, bottom - top))

        // The edge (seen below the face as its depth).
        context.fill(rounded(inset, radius), with: .color(Color(argb: edge)))
        guard usable(face) else { return }

        // The face.
        let shading: GraphicsContext.Shading
        if panel || (r > 238 && g > 238 && b > 238) {
            let colors = [SkyPalette.blend(0xffdff5ff, base, 0.1), 0xfffffef2, 0xfff4fbff, SkyPalette.blend(0xffffdeeb, base, 0.08)]
            shading = .linearGradient(Gradient(colors: colors.map { Color(argb: $0) }),
                                      startPoint: CGPoint(x: face.minX, y: face.minY), endPoint: CGPoint(x: face.maxX, y: face.maxY))
        } else {
            let stops = [Gradient.Stop(color: Color(argb: upper), location: 0),
                         Gradient.Stop(color: Color(argb: lower), location: 0.48),
                         Gradient.Stop(color: Color(argb: lower), location: 1)]
            shading = .linearGradient(Gradient(stops: stops), startPoint: CGPoint(x: 0, y: face.minY), endPoint: CGPoint(x: 0, y: face.maxY))
        }
        context.fill(rounded(face, radius), with: shading)

        // The rim (or the host's own stroke).
        let rimColor = strokeWidth > 0 ? strokeColor : SkyPalette.blend(base, SkyPalette.white, 0.22)
        context.stroke(rounded(face, radius), with: .color(Color(argb: rimColor)), lineWidth: strokeWidth > 0 ? strokeWidth : rim)

        // The inner highlight.
        let inner = face.insetBy(dx: rim * 2, dy: rim * 2)
        if usable(inner) {
            context.stroke(rounded(inner, max(px, radius - rim * 2)), with: .color(Color(argb: 0xb8ffffff)), lineWidth: rim)
        }

        // The shine of a control.
        if !panel {
            let shine = face.insetBy(dx: min(radius * 0.8, face.width * 0.12), dy: rim * 3)
            if usable(shine) {
                let band = CGRect(x: shine.minX, y: shine.minY, width: shine.width, height: min(shine.height, face.height * 0.25))
                if usable(band) {
                    let glow = Gradient(colors: [Color(argb: 0xbbffffff), Color(argb: 0x00ffffff)])
                    context.fill(rounded(band, band.height / 2),
                                 with: .linearGradient(glow, startPoint: CGPoint(x: 0, y: face.minY),
                                                       endPoint: CGPoint(x: 0, y: face.minY + min(face.height * 0.40, radius))))
                }
            }
        }
    }
}

/// A button on a sky surface (Android buttons with a `FamilySkyDrawable` background): the face sinks while pressed.
/// Android binds every such Button to `FamilyButtonAlignment` (the drawable's `bindButtonOwner`), so its lettering is
/// centred on the raised face below the gloss and lowered 3 points (`FamilyKit.RaisedLettering`, Spud keeps the default
/// face: it never calls `useFullRaisedFace`). Panels are never aligned; `raisedLettering` false is for a surface that is
/// not an Android Button (the picture cards are LinearLayouts).
struct SkyButtonStyle: ButtonStyle {
    let color: UInt32
    var radius: CGFloat = 18
    var panel = false
    var strokeWidth: CGFloat = 0
    var strokeColor: UInt32 = 0
    /// Android `clipToOutline` (the picture cards).
    var clips = false
    var raisedLettering = true

    func makeBody(configuration: Configuration) -> some View {
        let surface = configuration.label
            .modifier(SkyLettering(active: raisedLettering && !panel, radius: radius, pressed: configuration.isPressed))
            .background(SkySurface(color: color, radius: radius, panel: panel, strokeWidth: strokeWidth,
                                   strokeColor: strokeColor, pressed: configuration.isPressed))
        return surface.clipShape(RoundedRectangle(cornerRadius: clips ? radius : 0))
    }
}

/// `FamilyKit.RaisedLettering` where Android aligns the label; the label unchanged elsewhere.
private struct SkyLettering: ViewModifier {
    let active: Bool
    let radius: CGFloat
    let pressed: Bool

    func body(content: Content) -> some View {
        if active {
            content.modifier(FamilyKit.RaisedLettering(cornerRadius: radius, pressed: pressed))
        } else {
            content
        }
    }
}

/// Android `FamilyFormStyle` input face: a white field with modest 8 dp corners and a 1 dp border (blue while
/// focused).
struct InputFace: View {
    var focused = false

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.white)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(argb: focused ? 0xff2587d6 : 0xff879baa), lineWidth: 1))
    }
}

/// Android `FamilyReadingPanel`: a centred page column whose width follows the window, never a device name.
enum ReadingPanel {
    /// Android `contentWidth`: the full width while the window is portrait; in landscape at most 520 dp, at least
    /// 300 dp and otherwise 52% of the available width.
    static func width(available: CGFloat, window: CGSize) -> CGFloat {
        if window.width <= window.height { return available }
        return min(available, min(520, max(300, (available * 0.52).rounded())))
    }
}

/// Android `FamilyMenu.INK` and the `FamilyFormStyle` input colours.
enum SkyInk {
    static let menu: UInt32 = 0xff282d4e
    /// `FamilyFormStyle` text and hint of an input.
    static let input: UInt32 = 0xff17384d
    static let hint: UInt32 = 0xff536b7b
}

/// Finds the UIKit scroll view behind a SwiftUI `ScrollView`, so the scroll cue can scroll by a share of the page
/// (Android `smoothScrollBy`).
final class ScrollHandle {
    weak var scrollView: UIScrollView?
    /// The page's latest measures (content bottom in the scroll view's space, and its visible height).
    var contentBottom: CGFloat = 0
    var viewportHeight: CGFloat = 0

    /// Scrolls down by `fraction` of the visible height; false when the scroll view is unknown.
    @MainActor func scrollDown(_ fraction: CGFloat) -> Bool {
        guard let s = scrollView else { return false }
        let inset = s.adjustedContentInset
        let maxY = max(-inset.top, s.contentSize.height + inset.bottom - s.bounds.height)
        let target = min(maxY, s.contentOffset.y + s.bounds.height * fraction)
        s.setContentOffset(CGPoint(x: s.contentOffset.x, y: target), animated: true)
        return true
    }
}

private final class ScrollFinderView: UIView {
    weak var handle: ScrollHandle?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        var next = superview
        while let view = next {
            if let scroll = view as? UIScrollView {
                handle?.scrollView = scroll
                return
            }
            next = view.superview
        }
    }
}

/// Placed inside the scroll content: hands its enclosing `UIScrollView` to the handle.
struct ScrollFinder: UIViewRepresentable {
    let handle: ScrollHandle

    func makeUIView(context: Context) -> UIView {
        let view = ScrollFinderView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.handle = handle
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
