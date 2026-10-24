import SwiftUI

/// The shared look of the Android MinikFamilyServices UI classes (FamilySkyDrawable, FamilySkyUi,
/// FamilyMenu, FamilyMoreFrame, FamilyTournamentUi, FamilyFormStyle, FamilyLandscapeHint and
/// FamilyReadingPanel), for every iPhone app that compiles Family/. Colours are Android ARGB values
/// (0xAARRGGBB), as the apps keep them. Everything is nested here so no app type can clash with it.
enum FamilyKit {
    /// An Android ARGB colour.
    static func color(_ argb: UInt32) -> Color {
        return Color(.sRGB,
                     red: Double((argb >> 16) & 0xff) / 255,
                     green: Double((argb >> 8) & 0xff) / 255,
                     blue: Double(argb & 0xff) / 255,
                     opacity: Double((argb >> 24) & 0xff) / 255)
    }
}

// MARK: Sky surfaces (Android FamilySkyDrawable, FamilySkyUi)

extension FamilyKit {
    /// Android `FamilySkyDrawable` colours and rules.
    enum Sky {
        /// The light face of a panel or a near-white surface, drawn from the top-leading to the
        /// bottom-trailing corner (each end is tinted slightly toward the surface colour).
        static let panelFace: [UInt32] = [0xffdff5ff, 0xfffffef2, 0xfff4fbff, 0xffffdeeb]
        /// `FamilySkyUi.dialog`: positive and neutral dialog buttons.
        static let positive: UInt32 = 0xffa6dcff
        /// `FamilySkyUi.dialog`: the negative dialog button.
        static let negative: UInt32 = 0xffffd4e6
        /// The dialog window panel (`FamilySkyUi.dialog`) and the corner radius of every sky dialog.
        static let dialogPanel: UInt32 = 0xffffffff
        static let dialogCornerRadius: CGFloat = 24

        /// The hosts' `bg(color)` rule (Squash/Volley, Splash, Spud): these colours are drawn as panels.
        static func isPanelColor(_ argb: UInt32) -> Bool {
            return argb == 0xffffffff || argb == 0xfff5f7fd || argb == 0xfff6f8ff
        }

        /// Android `FamilySkyDrawable.palette`: pale fills take the Maze equivalent of their hue
        /// (purple, blue, green or yellow); grey, strong and other colours stay as they are.
        static func palette(_ argb: UInt32) -> UInt32 {
            let r = Int((argb >> 16) & 0xff), g = Int((argb >> 8) & 0xff), b = Int(argb & 0xff)
            let high = max(r, g, b), low = min(r, g, b)
            let delta = Double(high - low)
            let saturation = high == 0 ? 0 : delta / Double(high)
            if saturation < 0.12 || saturation > 0.48 || delta == 0 { return argb }
            var hue: Double
            if r == high {
                hue = Double(g - b) / delta
            } else if g == high {
                hue = 2 + Double(b - r) / delta
            } else {
                hue = 4 + Double(r - g) / delta
            }
            hue *= 60
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
                return argb
            }
            return (argb & 0xff000000) | (mapped & 0x00ffffff)
        }

        /// Android `FamilySkyDrawable.blend`: an opaque mix, `t` of the way from `a` to `b`.
        static func blend(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
            func channel(_ shift: UInt32) -> UInt32 {
                let x = Double((a >> shift) & 0xff), y = Double((b >> shift) & 0xff)
                return UInt32(min(255, max(0, (x * (1 - t) + y * t).rounded())))
            }
            return 0xff000000 | (channel(16) << 16) | (channel(8) << 8) | channel(0)
        }
    }

    /// The geometry and colours `FamilySkyDrawable.prepare` computes for one surface size.
    struct SkyLook {
        let alpha: Double
        let radius: CGFloat
        let edge: Color
        let edgeRect: CGRect
        let face: CGRect
        let faceGradient: LinearGradient
        let stroke: Color
        let strokeWidth: CGFloat
        let highlight: CGRect
        let highlightRadius: CGFloat
        let highlightWidth: CGFloat
        let shine: CGRect?
        let shineGradient: LinearGradient

        init(color: UInt32, size: CGSize, radius: CGFloat, panel: Bool, pressed: Bool, enabled: Bool,
             strokeWidth: CGFloat, strokeColor: UInt32, faceColors: [UInt32]?, pixel: CGFloat) {
            let base = Sky.palette(color)
            alpha = Double((base >> 24) & 0xff) / 255
            self.radius = radius
            let box = CGRect(origin: .zero, size: size)
            let rim = SkyLook.rim(size: size, radius: radius, pixel: pixel)
            let r = Int((base >> 16) & 0xff), g = Int((base >> 8) & 0xff), b = Int(base & 0xff)
            let pale = max(r, g, b) - min(r, g, b) < 132
            // Dark HUD/selection surfaces carry white text; they are not washed into pale grey.
            let dark = (r * 299 + g * 587 + b * 114) / 1000 < 130
            var upper = Sky.blend(base, 0xffffffff, dark ? 0.08 : pale ? 0.75 : 0.22)
            var lower = Sky.blend(base, 0xffffffff, dark ? 0.015 : pale ? 0.32 : 0.02)
            var edgeColor = Sky.blend(base, 0xff204878, 0.28)
            if !enabled && !panel {
                upper = 0xffeef3f7
                lower = 0xffdce7ef
                edgeColor = 0xffb4cadb
            }
            edge = FamilyKit.color(edgeColor)
            edgeRect = SkyLook.inset(box, rim, rim)
            let faceRect = SkyLook.faceRect(size: size, radius: radius, panel: panel, pressed: pressed, pixel: pixel)
            face = faceRect

            let stops: [Gradient.Stop]
            var diagonal = false
            if let custom = faceColors, custom.count > 1 {
                stops = custom.enumerated().map { index, value in
                    Gradient.Stop(color: FamilyKit.color(value), location: CGFloat(index) / CGFloat(custom.count - 1))
                }
            } else if panel || (r > 238 && g > 238 && b > 238) {
                diagonal = true
                let colors = [Sky.blend(Sky.panelFace[0], base, 0.1), Sky.panelFace[1], Sky.panelFace[2],
                              Sky.blend(Sky.panelFace[3], base, 0.08)]
                stops = colors.enumerated().map { index, value in
                    Gradient.Stop(color: FamilyKit.color(value), location: CGFloat(index) / 3)
                }
            } else {
                stops = [Gradient.Stop(color: FamilyKit.color(upper), location: 0),
                         Gradient.Stop(color: FamilyKit.color(lower), location: 0.48),
                         Gradient.Stop(color: FamilyKit.color(lower), location: 1)]
            }
            faceGradient = LinearGradient(gradient: Gradient(stops: stops),
                                          startPoint: diagonal ? .topLeading : .top,
                                          endPoint: diagonal ? .bottomTrailing : .bottom)

            stroke = FamilyKit.color(strokeWidth > 0 ? strokeColor : Sky.blend(base, 0xffffffff, 0.22))
            self.strokeWidth = strokeWidth > 0 ? strokeWidth : rim
            highlight = SkyLook.inset(faceRect, rim * 2, rim * 2)
            highlightRadius = max(pixel, radius - rim * 2)
            highlightWidth = rim

            // The gloss across the top quarter of a button face (not on panels).
            var gloss: CGRect? = nil
            var glossStart = UnitPoint.top
            var glossEnd = UnitPoint.bottom
            if !panel {
                var inner = SkyLook.inset(faceRect, min(radius * 0.8, faceRect.width * 0.12), rim * 3)
                inner.size.height = min(inner.height, faceRect.height * 0.25)
                if inner.width > 0 && inner.height > 0 {
                    gloss = inner
                    let reach = min(faceRect.height * 0.40, radius)
                    glossStart = UnitPoint(x: 0.5, y: (faceRect.minY - inner.minY) / inner.height)
                    glossEnd = UnitPoint(x: 0.5, y: (faceRect.minY + reach - inner.minY) / inner.height)
                }
            }
            shine = gloss
            shineGradient = LinearGradient(gradient: Gradient(colors: [FamilyKit.color(0xbbffffff), FamilyKit.color(0x00ffffff)]),
                                           startPoint: glossStart, endPoint: glossEnd)
        }

        /// The fine rim around the face.
        static func rim(size: CGSize, radius: CGFloat, pixel: CGFloat) -> CGFloat {
            return max(pixel, min(min(size.width, size.height) * 0.026, radius * 0.08))
        }

        /// Android `copyFaceBounds`: the raised face `draw()` paints, above the darker lower edge (the
        /// face sinks while a button is pressed; a panel never does).
        static func faceRect(size: CGSize, radius: CGFloat, panel: Bool, pressed: Bool, pixel: CGFloat) -> CGRect {
            let depth = min(min(size.width, size.height) * 0.075, max(2 * pixel, radius * 0.28))
            let rim = SkyLook.rim(size: size, radius: radius, pixel: pixel)
            let sinks = pressed && !panel
            let top = rim + (sinks ? depth * 0.65 : 0)
            let bottom = rim + (sinks ? depth * 0.3 : depth)
            return CGRect(x: rim, y: top, width: max(0, size.width - 2 * rim), height: max(0, size.height - top - bottom))
        }

        /// Android `copyTextFaceBounds`: the face below the bright upper gloss (and above the lower edge),
        /// where a button's lettering belongs. A panel keeps its whole face.
        static func textFaceRect(size: CGSize, radius: CGFloat, panel: Bool, pressed: Bool, pixel: CGFloat) -> CGRect {
            var face = faceRect(size: size, radius: radius, panel: panel, pressed: pressed, pixel: pixel)
            if !panel {
                let gloss = min(face.height * 0.20, radius * 0.65)
                face.origin.y += gloss
                face.size.height = max(0, face.height - gloss)
            }
            return face
        }

        /// `RectF.inset`, never smaller than empty (CGRect.insetBy would return the null rectangle).
        static func inset(_ rect: CGRect, _ dx: CGFloat, _ dy: CGFloat) -> CGRect {
            return CGRect(x: rect.minX + dx, y: rect.minY + dy,
                          width: max(0, rect.width - 2 * dx), height: max(0, rect.height - 2 * dy))
        }
    }

    /// Android `FamilySkyDrawable`: Maze's glossy, raised surface, drawn entirely inside the view's
    /// bounds (a darker lower edge, a light face, a fine rim and highlight, and a gloss on buttons).
    /// Use it as a `.background`. A panel (`panel: true`) has the light diagonal face and never sinks;
    /// a button face sinks while `pressed`. Disabled buttons (`.disabled`) turn grey-blue.
    struct SkySurface: View {
        let color: UInt32
        let cornerRadius: CGFloat
        let panel: Bool
        let pressed: Bool
        let strokeWidth: CGFloat
        let strokeColor: UInt32
        let faceColors: [UInt32]?
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.displayScale) private var displayScale

        /// `faceColors` is Android `setFaceGradient`: a top-to-bottom face instead of the computed one.
        /// `strokeWidth`/`strokeColor` is Android `setStroke` (0 keeps the light rim).
        init(color: UInt32, cornerRadius: CGFloat = 18, panel: Bool = false, pressed: Bool = false,
             strokeWidth: CGFloat = 0, strokeColor: UInt32 = 0, faceColors: [UInt32]? = nil) {
            self.color = color
            self.cornerRadius = cornerRadius
            self.panel = panel
            self.pressed = pressed
            self.strokeWidth = strokeWidth
            self.strokeColor = strokeColor
            self.faceColors = faceColors
        }

        var body: some View {
            GeometryReader { geo in
                let look = SkyLook(color: color, size: geo.size, radius: cornerRadius, panel: panel, pressed: pressed,
                                   enabled: isEnabled, strokeWidth: strokeWidth, strokeColor: strokeColor,
                                   faceColors: faceColors, pixel: 1 / max(displayScale, 1))
                if look.alpha > 0 && geo.size.width > 0 && geo.size.height > 0 {
                    ZStack(alignment: .topLeading) {
                        place(RoundedRectangle(cornerRadius: look.radius, style: .circular).fill(look.edge), look.edgeRect)
                        place(RoundedRectangle(cornerRadius: look.radius, style: .circular).fill(look.faceGradient), look.face)
                        place(RoundedRectangle(cornerRadius: look.radius, style: .circular).stroke(look.stroke, lineWidth: look.strokeWidth), look.face)
                        place(RoundedRectangle(cornerRadius: look.highlightRadius, style: .circular)
                            .stroke(FamilyKit.color(0xb8ffffff), lineWidth: look.highlightWidth), look.highlight)
                        if let shine = look.shine {
                            place(Capsule(style: .circular).fill(look.shineGradient), shine)
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                    .compositingGroup()
                    .opacity(look.alpha)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }

        private func place<V: View>(_ view: V, _ rect: CGRect) -> some View {
            return view
                .frame(width: max(0, rect.width), height: max(0, rect.height))
                .offset(x: rect.minX, y: rect.minY)
        }
    }

    /// Android `FamilySkyUi.button`: a button on a raised sky face that sinks while pressed. The label
    /// keeps its own font, colour, padding and size; its lettering is centred on the raised face
    /// (`RaisedLettering`, Android `FamilyButtonAlignment.bind`), except on a panel.
    struct SkyButtonStyle: ButtonStyle {
        let color: UInt32
        let cornerRadius: CGFloat
        let panel: Bool

        init(color: UInt32, cornerRadius: CGFloat = 18, panel: Bool = false) {
            self.color = color
            self.cornerRadius = cornerRadius
            self.panel = panel
        }

        func makeBody(configuration: Configuration) -> some View {
            Group {
                if panel {
                    configuration.label
                } else {
                    configuration.label
                        .modifier(RaisedLettering(cornerRadius: cornerRadius, pressed: configuration.isPressed))
                }
            }
            .background(SkySurface(color: color, cornerRadius: cornerRadius, panel: panel, pressed: configuration.isPressed))
            .contentShape(Rectangle())
        }
    }

    /// Android `FamilySkyUi.dialog`: a dimmed backdrop and a light sky panel with 24-point corners,
    /// at most `maxWidth` wide. Put it last in a full-screen `ZStack`. `onBackdropTap` is the
    /// dialog's tap-outside (nil: a tap outside does nothing). Always light, also in Dark Mode.
    struct SkyDialog<Content: View>: View {
        let panelColor: UInt32
        let maxWidth: CGFloat
        let margin: CGFloat
        let onBackdropTap: (() -> Void)?
        let content: Content

        init(panelColor: UInt32 = Sky.dialogPanel, maxWidth: CGFloat = 420, margin: CGFloat = 24,
             onBackdropTap: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
            self.panelColor = panelColor
            self.maxWidth = maxWidth
            self.margin = margin
            self.onBackdropTap = onBackdropTap
            self.content = content()
        }

        var body: some View {
            ZStack {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { onBackdropTap?() }
                    .accessibilityHidden(true)
                content
                    .frame(maxWidth: .infinity)
                    .background(SkySurface(color: panelColor, cornerRadius: Sky.dialogCornerRadius, panel: true))
                    .frame(maxWidth: maxWidth)
                    .padding(.horizontal, margin)
                    .padding(.vertical, 24)
                    .accessibilityAddTraits(.isModal)
            }
            .environment(\.colorScheme, .light)
        }
    }

    /// A dialog button after `FamilySkyUi.dialog`: 14-point medium text on a raised sky face at least
    /// 64 x 48 points; positive and neutral buttons are blue, a negative one is pink.
    struct SkyDialogButton: View {
        enum Role {
            case positive, negative, neutral
        }

        let title: String
        let role: Role
        let textColor: UInt32
        let uppercase: Bool
        let action: () -> Void

        init(_ title: String, role: Role = .positive, textColor: UInt32 = 0xff244e85, uppercase: Bool = false,
             action: @escaping () -> Void) {
            self.title = title
            self.role = role
            self.textColor = textColor
            self.uppercase = uppercase
            self.action = action
        }

        var body: some View {
            Button(action: action) {
                Text(verbatim: title)
                    .font(.system(size: 14, weight: .medium))
                    .textCase(uppercase ? .uppercase : nil)
                    .foregroundColor(FamilyKit.color(textColor))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .frame(minWidth: 64, minHeight: 48)
            }
            .buttonStyle(SkyButtonStyle(color: role == .negative ? Sky.negative : Sky.positive))
        }
    }

    /// An Android Toast: white text on a dark rounded backing near the bottom; it ignores touches.
    struct Toast: View {
        let text: String

        init(_ text: String) {
            self.text = text
        }

        var body: some View {
            VStack {
                Spacer()
                Text(verbatim: text)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(white: 0.2).opacity(0.92)))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 64)
            }
            .frame(maxWidth: .infinity)
            .allowsHitTesting(false)
        }
    }
}
