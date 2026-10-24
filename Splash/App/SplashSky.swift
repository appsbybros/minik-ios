import SwiftUI
import UIKit

/// Android `com.appsbybros.family.FamilySkyDrawable` (Maze's glossy, raised surfaces), used by the
/// Splash menus for buttons, dropdowns, cards, section panels and dialogs. All depth is drawn inside
/// the view's bounds: an edge lip along the bottom, a gradient face, a light rim and, on controls,
/// a soft shine. Pressing a control pushes its face down.
enum SkyPalette {
    /// Android `FamilySkyDrawable.palette`: pale fills move to the Maze equivalents (purple, blue,
    /// green, yellow); grey, strong and pink-red colours keep theirs. The alpha is kept.
    static func map(_ color: UInt32) -> UInt32 {
        let r = Double((color >> 16) & 0xff) / 255
        let g = Double((color >> 8) & 0xff) / 255
        let b = Double(color & 0xff) / 255
        let high = max(r, max(g, b))
        let low = min(r, min(g, b))
        let delta = high - low
        let saturation = high == 0 ? 0 : delta / high
        if saturation < 0.12 || saturation > 0.48 { return color }
        // Android `Color.colorToHSV` hue.
        var hue = 0.0
        if delta > 0 {
            if r == high {
                hue = (g - b) / delta
            } else if g == high {
                hue = 2 + (b - r) / delta
            } else {
                hue = 4 + (r - g) / delta
            }
            hue *= 60
            if hue < 0 { hue += 360 }
        }
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
            let x = Double((a >> shift) & 0xff)
            let y = Double((b >> shift) & 0xff)
            return UInt32(max(0, min(255, (x * (1 - t) + y * t).rounded())))
        }
        return 0xff000000 | (channel(16) << 16) | (channel(8) << 8) | channel(0)
    }

    private static func color(_ argb: UInt32) -> Color {
        return Color(red: Double((argb >> 16) & 0xff) / 255, green: Double((argb >> 8) & 0xff) / 255,
                     blue: Double(argb & 0xff) / 255, opacity: Double((argb >> 24) & 0xff) / 255)
    }

    /// Android `FamilySkyDrawable.prepare` + `draw`, in points. `base` is the mapped colour; its alpha
    /// is applied by the caller to the whole surface (Android `saveLayerAlpha`).
    static func draw(_ context: inout GraphicsContext, _ size: CGSize, base: UInt32, radius: CGFloat, panel: Bool, pressed: Bool,
                     strokeWidth: CGFloat, strokeColor: UInt32) {
        let box = CGRect(origin: .zero, size: size)
        if box.width <= 0 || box.height <= 0 || (base >> 24) == 0 { return }
        let shortSide = min(box.width, box.height)
        let depth = min(shortSide * 0.075, max(2, radius * 0.28))
        let rim = max(1, min(shortSide * 0.026, radius * 0.08))
        let r = Int((base >> 16) & 0xff)
        let g = Int((base >> 8) & 0xff)
        let b = Int(base & 0xff)
        let pale = max(r, max(g, b)) - min(r, min(g, b)) < 132
        // Dark HUD/selection surfaces carry white text; they are not washed into pale grey.
        let dark = (r * 299 + g * 587 + b * 114) / 1000 < 130
        let upper = blend(base, 0xffffffff, dark ? 0.08 : (pale ? 0.75 : 0.22))
        let lower = blend(base, 0xffffffff, dark ? 0.015 : (pale ? 0.32 : 0.02))
        let edge = blend(base, 0xff204878, 0.28)
        let pushed = pressed && !panel
        let top = rim + (pushed ? depth * 0.65 : 0)
        let bottom = box.height - rim - (pushed ? depth * 0.3 : depth)
        let face = CGRect(x: rim, y: top, width: max(box.width - rim * 2, 0), height: max(bottom - top, 0))
        let lip = box.insetBy(dx: rim, dy: rim)
        if lip.width > 0 && lip.height > 0 {
            context.fill(Path(roundedRect: lip, cornerRadius: radius), with: .color(color(edge)))
        }
        if face.width <= 0 || face.height <= 0 { return }
        let facePath = Path(roundedRect: face, cornerRadius: radius)
        if panel || (r > 238 && g > 238 && b > 238) {
            let stops = [blend(0xffdff5ff, base, 0.1), 0xfffffef2, 0xfff4fbff, blend(0xffffdeeb, base, 0.08)]
            context.fill(facePath, with: .linearGradient(Gradient(colors: stops.map { color($0) }),
                                                         startPoint: CGPoint(x: face.minX, y: face.minY),
                                                         endPoint: CGPoint(x: face.maxX, y: face.maxY)))
        } else {
            let gradient = Gradient(stops: [Gradient.Stop(color: color(upper), location: 0),
                                            Gradient.Stop(color: color(lower), location: 0.48),
                                            Gradient.Stop(color: color(lower), location: 1)])
            context.fill(facePath, with: .linearGradient(gradient, startPoint: CGPoint(x: 0, y: face.minY),
                                                         endPoint: CGPoint(x: 0, y: face.maxY)))
        }
        context.stroke(facePath, with: .color(color(strokeWidth > 0 ? strokeColor : blend(base, 0xffffffff, 0.22))),
                       lineWidth: strokeWidth > 0 ? strokeWidth : rim)
        let inner = face.insetBy(dx: rim * 2, dy: rim * 2)
        if !inner.isNull && inner.width > 0 && inner.height > 0 {
            context.stroke(Path(roundedRect: inner, cornerRadius: max(1, radius - rim * 2)), with: .color(color(0xb8ffffff)), lineWidth: rim)
        }
        if !panel {
            var shine = face.insetBy(dx: min(radius * 0.8, face.width * 0.12), dy: rim * 3)
            if !shine.isNull && shine.width > 0 && shine.height > 0 {
                shine.size.height = min(shine.height, face.height * 0.25)
                let end = face.minY + min(face.height * 0.40, radius)
                context.fill(Path(roundedRect: shine, cornerRadius: shine.height / 2),
                             with: .linearGradient(Gradient(colors: [color(0xbbffffff), color(0x00ffffff)]),
                                                   startPoint: CGPoint(x: 0, y: face.minY), endPoint: CGPoint(x: 0, y: end)))
            }
        }
    }
}

/// A `FamilySkyDrawable` behind a view. `panel` is Android's `FamilySkyDrawable(true)` (section panels
/// and dialogs: the pale sky face, no shine); a stroke replaces the light outline of the face.
struct SkySurface: View {
    let color: UInt32
    var radius: CGFloat = 18
    var panel = false
    var pressed = false
    var strokeWidth: CGFloat = 0
    var strokeColor: UInt32 = 0

    var body: some View {
        let base = SkyPalette.map(color)
        let radius = self.radius
        let panel = self.panel
        let pressed = self.pressed
        let strokeWidth = self.strokeWidth
        let strokeColor = self.strokeColor
        Canvas { context, size in
            SkyPalette.draw(&context, size, base: base, radius: radius, panel: panel, pressed: pressed,
                            strokeWidth: strokeWidth, strokeColor: strokeColor)
        }
        .opacity(Double((base >> 24) & 0xff) / 255)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Android buttons with a `FamilySkyDrawable` background: the raised face, pushed down while pressed.
/// `shadow` keeps the Splash buttons' soft elevation shadow. Android binds every such Button to
/// `FamilyButtonAlignment` (the drawable's `bindButtonOwner`), so the label's lettering is centred on
/// the raised face and lowered 3 points (`FamilyKit.RaisedLettering`; Splash uses the whole raised
/// face, `FamilyKit.Lettering.fullRaisedFace`, set in `SplashApp`). Every Splash use is a button, never
/// a panel.
struct SkyButtonStyle: ButtonStyle {
    let color: UInt32
    var radius: CGFloat = 18
    var shadow = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(FamilyKit.RaisedLettering(cornerRadius: radius, pressed: configuration.isPressed))
            .background(
                SkySurface(color: color, radius: radius, pressed: configuration.isPressed)
                    .shadow(color: Color.black.opacity(shadow ? 0.22 : 0), radius: shadow ? 2 : 0, x: 0, y: shadow ? 1 : 0)
            )
    }
}

/// Android `FamilyTournamentUi.divider`: a dashed line that separates creating a room from joining one.
@MainActor
struct RoomDivider: View {
    var body: some View {
        GeometryReader { geo in
            Path { p in
                p.move(to: CGPoint(x: 0, y: geo.size.height / 2))
                p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height / 2))
            }
            .stroke(SplashPalette.color(0xff7892ad), style: StrokeStyle(lineWidth: 2, dash: [7, 6]))
        }
        .frame(height: 2)
        .padding(.horizontal, 8)
        .padding(.vertical, 24)
        .accessibilityHidden(true)
    }
}

/// Android `FamilyMoreFrame`: the reserved "More below" cue under the home menu. It shows while the
/// menu can scroll further down; tapping it scrolls on by 65% of the visible height.
@MainActor
struct SplashMoreCue: View {
    let visible: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bounce = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Text(FamilyMessages.text("More below", "עוד למטה"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(SplashPalette.color(0xfff7fbff))
                    .shadow(color: SplashPalette.color(0xff102039), radius: 1, x: 0, y: 1)
                Text("⌄")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(SplashPalette.color(0xffffdf77))
                    .shadow(color: .black, radius: 1, x: 0, y: 1)
                    .frame(width: 38, height: 44)
                    .offset(y: bounce ? 4 : 0)
            }
            .frame(maxWidth: .infinity, minHeight: 48, maxHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(visible)
        .accessibilityHidden(!visible)
        .accessibilityLabel(FamilyMessages.text("More options below. Tap to scroll", "עוד אפשרויות למטה. הקישו לגלילה"))
        .onAppear {
            // Android: an 850 ms bounce, off with touch exploration or with animations disabled.
            if reduceMotion || UIAccessibility.isVoiceOverRunning { return }
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) { bounce = true }
        }
    }
}

/// Reports a view's frame in global coordinates when it appears and whenever it moves (scrolling).
struct SplashFrameProbe: View {
    let report: (CGRect) -> Void

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { report(proxy.frame(in: .global)) }
                .onChange(of: proxy.frame(in: .global)) { _, rect in
                    report(rect)
                }
        }
    }
}

/// The measured scroll view and content of a page (kept out of view state: scrolling must not
/// re-render the page).
final class SplashScrollState {
    var viewport: CGRect = .zero
    var content: CGRect = .zero
}

enum SplashPageLayout {
    static let contentID = "splash-page-content"

    /// Android `FamilyReadingPanel.contentWidth`: the whole width in portrait; in a landscape window a
    /// centred column of 52% of the width, at least 300 and at most 520 points.
    /// Splash (Android 2026-10-15) first narrows a tablet's page (smallest width 600 or more) to at most
    /// 720 points, 12 from each edge.
    static func readingWidth(_ size: CGSize) -> CGFloat {
        let available = min(size.width, size.height) >= 600 ? min(720, size.width - 24) : size.width
        if size.width <= size.height { return available }
        return min(available, min(520, max(300, (available * 0.52).rounded())))
    }
}
