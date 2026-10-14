import SwiftUI
import UIKit

// MARK: - Palette and fonts

/// The rainbow-sky ("pretty") design of Android Minik Plus (colors_pretty.xml,
/// dimens_pretty.xml, bg_pretty_*.xml, PrettyDesign.kt) and of Android Minik Math
/// Plus's Rainbow Sky theme: the colors, the Fredoka fonts and the shared pieces
/// below (sky background, glass panel, glossy pill buttons, section pills and
/// answer tiles). Text is always dark (navy or soft ink) on the light surfaces.
enum MinikPretty {
    /// #2D2A6E: titles and text on light surfaces.
    static let navy = Color(red: 45 / 255, green: 42 / 255, blue: 110 / 255)
    /// #5B4F72: secondary text on light surfaces.
    static let softInk = Color(red: 91 / 255, green: 79 / 255, blue: 114 / 255)
    /// #F1ECFF: the light lavender fill.
    static let lavender = Color(red: 241 / 255, green: 236 / 255, blue: 255 / 255)
    /// #7C5CF2: the purple accent.
    static let purple = Color(red: 124 / 255, green: 92 / 255, blue: 242 / 255)
    /// The glass panel's white.
    static let panelFill = Color.white.opacity(0.96)

    /// Fredoka Bold when the app bundles it (Resources/Fonts), otherwise the
    /// rounded system font. A fixed size: callers scale it where they need to.
    static func titleFont(_ size: CGFloat) -> Font {
        if hasFredokaBold {
            return Font.custom("Fredoka-Bold", fixedSize: size)
        }
        return Font.system(size: size, weight: .bold, design: .rounded)
    }

    /// Fredoka Medium when the app bundles it, otherwise the rounded system font.
    static func bodyFont(_ size: CGFloat) -> Font {
        if hasFredokaMedium {
            return Font.custom("Fredoka-Medium", fixedSize: size)
        }
        return Font.system(size: size, weight: .semibold, design: .rounded)
    }

    private static let hasFredokaBold: Bool = UIFont(name: "Fredoka-Bold", size: 12) != nil
    private static let hasFredokaMedium: Bool = UIFont(name: "Fredoka-Medium", size: 12) != nil
}

extension MinikPretty {
    /// #9FDDFD: the sky behind the background art (pretty_sky).
    static let sky = Color(red: 159 / 255, green: 221 / 255, blue: 253 / 255)
    /// #CDBDFB: the lavender rim of white tiles and fields.
    static let lavenderRim = Color(red: 205 / 255, green: 189 / 255, blue: 251 / 255)
    /// #3A2C7A: the ink of the soft drop shadows and lips.
    static let shadowInk = Color(red: 58 / 255, green: 44 / 255, blue: 122 / 255)
    /// The shadow under white text on the colored pills (#55241A66).
    static let textShadow = Color(red: 36 / 255, green: 26 / 255, blue: 102 / 255).opacity(0.33)

    /// A color from a 0xRRGGBB value.
    static func color(_ hex: UInt32, opacity: Double = 1) -> Color {
        Color(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    /// The design's art in MinikVisuals.xcassets (Android res/drawable-nodpi).
    enum Art {
        /// minik_sky_background: the phone sky (1080 x 2340).
        static let sky = "minik_pretty_sky"
        /// drawable-sw600dp-nodpi/minik_sky_background: the wider tablet sky (1600 x 2240).
        static let skyTablet = "minik_pretty_sky_tablet"
        /// minik_logo_pretty_plus: the MINIK+plus badge of the rainbow branding (Android 8b1b1d6,
        /// 1254 x 1254, kept here at 600 x 600).
        static let plusLogo = "minik_pretty_logo_plus"
        /// minik_logo_pretty: the former MINIK+plus logo, which English Only keeps (749 x 520).
        static let englishOnlyLogo = "minik_pretty_logo_english"
        /// The logo of the Intro, the menu and the activity screens: Android IntroScreen and
        /// ButtonsMenuFragment show minik_logo_pretty in English Only, minik_logo_pretty_plus otherwise.
        static let languageLogo: String = {
            #if MINIK_PLUS_ENGLISH
            return Art.englishOnlyLogo
            #else
            return Art.plusLogo
            #endif
        }()
        static let languageLogoAspect: CGFloat = {
            #if MINIK_PLUS_ENGLISH
            return 749.0 / 520.0
            #else
            return 1
            #endif
        }()
        /// Android Minik Math Plus math_plus_logo: the Minik Math icon (404 x 405).
        static let mathLogo = "minik_pretty_logo_math"
        /// minik_plus_welcome_sky: Minik on a cloud in front of a rainbow (899 x 430).
        static let welcome = "minik_pretty_welcome"
        static let welcomeAspect: CGFloat = 899.0 / 430.0

        static let catAbcBook = "minik_pretty_menu_cat_abc_book"
        static let catHebrewBook = "minik_pretty_menu_cat_hebrew_book"
        static let catBlocks = "minik_pretty_menu_cat_blocks"
        static let catPencil = "minik_pretty_menu_cat_pencil"
        static let catStarPaper = "minik_pretty_menu_cat_star_paper"
        static let firstLetterChoicesEnglish = "minik_pretty_menu_first_letter_choices_en"
        static let firstLetterChoicesHebrew = "minik_pretty_menu_first_letter_choices_he"
        static let firstLetterPicturesEnglish = "minik_pretty_menu_first_letter_pictures_en"
        static let firstLetterPicturesHebrew = "minik_pretty_menu_first_letter_pictures_he"
        static let flashCards = "minik_pretty_menu_flash_cards"
        static let memory = "minik_pretty_menu_memory"
        static let pairs = "minik_pretty_menu_pairs"
        static let pictureAnswers = "minik_pretty_menu_picture_answers"
        static let soccer = "minik_pretty_menu_soccer"
        static let ticTacToe = "minik_pretty_menu_tic_tac_toe"
        static let tower = "minik_pretty_menu_tower"
        static let iconAbc = "minik_pretty_menu_icon_abc"
        static let iconAlefBet = "minik_pretty_menu_icon_alef_bet"
        static let iconBook = "minik_pretty_menu_icon_book"
        static let iconGames = "minik_pretty_menu_icon_games"
    }
}

// MARK: - Sky background and glass panel

/// The full-screen rainbow sky (PrettyDesign.skyBackground): aspect-filled and
/// cropped, never stretched, edge to edge under the safe areas. Wide screens
/// (iPad, landscape) use Android's tablet sky. It never sizes the layout, so it
/// works as a background or as a ZStack layer.
struct MinikSkyBackground: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                MinikPretty.sky
                Image(proxy.size.width > proxy.size.height * 0.6 ? MinikPretty.Art.skyTablet : MinikPretty.Art.sky)
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The frosted white panel of the pretty design (pretty_glass card): rounded 28,
/// a white rim and a soft lavender shadow. It fills the offered width.
struct MinikGlassPanel<Content: View>: View {
    private let padding: CGFloat
    private let cornerRadius: CGFloat
    private let content: Content

    init(padding: CGFloat = 16, cornerRadius: CGFloat = 28, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(MinikPretty.panelFill)
                    .shadow(color: MinikPretty.shadowInk.opacity(0.16), radius: 16, x: 0, y: 8)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white, lineWidth: 2)
                    .allowsHitTesting(false)
            }
    }
}

// MARK: - Glossy pill buttons

enum MinikPrettyButtonStyleKind {
    /// Sunny yellow with navy text (bg_pretty_button_yellow).
    case yellow
    /// Purple gradient with white text (bg_pretty_button_purple).
    case purple
    /// Blue gradient with white text (bg_pretty_button_blue).
    case blue
    /// White with a lavender lip and navy text (bg_pretty_button_white).
    case white
}

/// The glossy pill button of the pretty design: a gradient face with a white rim,
/// a darker lip under it and a soft shine, Fredoka text. Give the label
/// `.frame(maxWidth: .infinity)` for a full-width button.
struct MinikPrettyButtonStyle: ButtonStyle {
    private let kind: MinikPrettyButtonStyleKind

    init(_ kind: MinikPrettyButtonStyleKind) {
        self.kind = kind
    }

    func makeBody(configuration: Configuration) -> some View {
        MinikPretty.GlossyFace(
            label: configuration.label,
            look: MinikPretty.PillLook.forKind(kind),
            fontSize: 20,
            minHeight: 52,
            horizontalPadding: 22,
            pressed: configuration.isPressed
        )
    }
}

extension MinikPretty {
    /// The colors of a glossy pill: the gradient face, the lip under it, the rim and the text.
    struct PillLook {
        let top: Color
        let bottom: Color
        let lip: Color
        let rim: Color
        let ink: Color
        let inkShadow: Color
        /// Android's section pills and warm button run their gradient from start to end.
        let horizontal: Bool

        init(top: Color, bottom: Color, lip: Color, rim: Color, ink: Color, inkShadow: Color, horizontal: Bool = false) {
            self.top = top
            self.bottom = bottom
            self.lip = lip
            self.rim = rim
            self.ink = ink
            self.inkShadow = inkShadow
            self.horizontal = horizontal
        }

        static func forKind(_ kind: MinikPrettyButtonStyleKind) -> PillLook {
            switch kind {
            case .yellow: return PillLook.yellow
            case .purple: return PillLook.purple
            case .blue: return PillLook.blue
            case .white: return PillLook.white
            }
        }

        static let yellow = PillLook(
            top: MinikPretty.color(0xFFE45C),
            bottom: MinikPretty.color(0xFFC93C),
            lip: MinikPretty.color(0xE09A1A),
            rim: Color.white,
            ink: MinikPretty.navy,
            inkShadow: Color.clear
        )

        // Slightly deeper than Android's #7A5FE6-#A08CF8 so the white text stays clear.
        static let purple = PillLook(
            top: MinikPretty.color(0x9A80F6),
            bottom: MinikPretty.color(0x6A4ADB),
            lip: MinikPretty.color(0x4E31B0),
            rim: Color.white,
            ink: Color.white,
            inkShadow: MinikPretty.textShadow
        )

        static let blue = PillLook(
            top: MinikPretty.color(0x4FB0F2),
            bottom: MinikPretty.color(0x1C79D3),
            lip: MinikPretty.color(0x145FA6),
            rim: Color.white,
            ink: Color.white,
            inkShadow: MinikPretty.textShadow
        )

        static let white = PillLook(
            top: Color.white,
            bottom: MinikPretty.color(0xF6F2FF),
            lip: MinikPretty.lavenderRim,
            rim: MinikPretty.color(0xE6DEFF),
            ink: MinikPretty.navy,
            inkShadow: Color.clear
        )

        /// bg_pretty_button_warm: the pink-to-orange Practice button.
        static let warm = PillLook(
            top: MinikPretty.color(0xF85A90),
            bottom: MinikPretty.color(0xF6873F),
            lip: MinikPretty.color(0xC2416E),
            rim: Color.white,
            ink: Color.white,
            inkShadow: MinikPretty.textShadow,
            horizontal: true
        )

        /// bg_section_pill_letters.
        static let bannerPurple = PillLook(
            top: MinikPretty.color(0x6A4FE0),
            bottom: MinikPretty.color(0x8E78F2),
            lip: MinikPretty.shadowInk.opacity(0.18),
            rim: Color.clear,
            ink: Color.white,
            inkShadow: MinikPretty.textShadow,
            horizontal: true
        )

        /// bg_section_pill_words.
        static let bannerBlue = PillLook(
            top: MinikPretty.color(0x1A78D6),
            bottom: MinikPretty.color(0x2A9BE6),
            lip: MinikPretty.shadowInk.opacity(0.18),
            rim: Color.clear,
            ink: Color.white,
            inkShadow: MinikPretty.textShadow,
            horizontal: true
        )

        /// bg_section_pill_games.
        static let bannerWarm = PillLook(
            top: MinikPretty.color(0xEC4F86),
            bottom: MinikPretty.color(0xEF7F3A),
            lip: MinikPretty.shadowInk.opacity(0.18),
            rim: Color.clear,
            ink: Color.white,
            inkShadow: MinikPretty.textShadow,
            horizontal: true
        )
    }

    /// The pill's face: the lip shows 3 points under the gradient face, which has a
    /// soft shine at its top and a rim.
    struct PillBackground: View {
        let look: PillLook
        let pressed: Bool

        init(look: PillLook, pressed: Bool) {
            self.look = look
            self.pressed = pressed
        }

        var body: some View {
            ZStack {
                Capsule(style: .continuous)
                    .fill(look.lip)
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [look.top, look.bottom],
                            startPoint: look.horizontal ? UnitPoint.leading : UnitPoint.top,
                            endPoint: look.horizontal ? UnitPoint.trailing : UnitPoint.bottom
                        )
                    )
                    .overlay {
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    stops: [
                                        Gradient.Stop(color: Color.white.opacity(0.30), location: 0),
                                        Gradient.Stop(color: Color.white.opacity(0), location: 0.55)
                                    ],
                                    startPoint: UnitPoint.top,
                                    endPoint: UnitPoint.bottom
                                )
                            )
                            .padding(.horizontal, 6)
                            .padding(.top, 2)
                    }
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(look.rim, lineWidth: 2)
                    }
                    .overlay {
                        if pressed {
                            Capsule(style: .continuous)
                                .fill(Color.black.opacity(0.08))
                        }
                    }
                    .padding(.bottom, 3)
            }
            .allowsHitTesting(false)
        }
    }

    /// The body shared by the glossy pill buttons.
    struct GlossyFace<Label: View>: View {
        let label: Label
        let look: PillLook
        let fontSize: CGFloat
        let minHeight: CGFloat
        let horizontalPadding: CGFloat
        let pressed: Bool
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        init(
            label: Label,
            look: PillLook,
            fontSize: CGFloat,
            minHeight: CGFloat,
            horizontalPadding: CGFloat,
            pressed: Bool
        ) {
            self.label = label
            self.look = look
            self.fontSize = fontSize
            self.minHeight = minHeight
            self.horizontalPadding = horizontalPadding
            self.pressed = pressed
        }

        var body: some View {
            label
                .font(MinikPretty.titleFont(fontSize))
                .foregroundStyle(look.ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .shadow(color: look.inkShadow, radius: 1.5, x: 0, y: 1)
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 9)
                .padding(.bottom, 12)
                .frame(minHeight: minHeight)
                .background {
                    MinikPretty.PillBackground(look: look, pressed: pressed)
                }
                .contentShape(Capsule(style: .continuous))
                .opacity(isEnabled ? 1 : 0.5)
                .scaleEffect(pressed && !reduceMotion ? 0.97 : 1)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: pressed)
        }
    }

    /// A big glossy pill with its own look and size, such as the intro's Parent
    /// Area and Practice buttons.
    struct HeroButtonStyle: ButtonStyle {
        let look: PillLook
        let fontSize: CGFloat
        let minHeight: CGFloat

        init(look: PillLook, fontSize: CGFloat = 26, minHeight: CGFloat = 64) {
            self.look = look
            self.fontSize = fontSize
            self.minHeight = minHeight
        }

        func makeBody(configuration: Configuration) -> some View {
            MinikPretty.GlossyFace(
                label: configuration.label,
                look: look,
                fontSize: fontSize,
                minHeight: minHeight,
                horizontalPadding: 18,
                pressed: configuration.isPressed
            )
        }
    }

    /// Cards and round buttons: a little smaller while pressed.
    struct PressScaleStyle: ButtonStyle {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        init() {}

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
                .brightness(configuration.isPressed ? -0.03 : 0)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
        }
    }
}

// MARK: - Section pills, menu cards and round buttons

/// A light section pill: a lavender gradient with a white rim and navy Fredoka text,
/// with an optional SF Symbol in purple.
struct MinikSectionPill: View {
    private let title: String
    private let systemImage: String?

    init(title: String, systemImage: String? = nil) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(MinikPretty.purple)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(MinikPretty.titleFont(19))
                .foregroundStyle(MinikPretty.navy)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .frame(minHeight: 42)
        .background {
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white, MinikPretty.lavender, MinikPretty.color(0xE4DAFF)],
                        startPoint: UnitPoint.top,
                        endPoint: UnitPoint.bottom
                    )
                )
                .shadow(color: MinikPretty.shadowInk.opacity(0.12), radius: 4, x: 0, y: 2)
        }
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(Color.white, lineWidth: 2)
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

extension MinikPretty {
    /// The pastel colors of the menu cards (bg_menu_card_*).
    enum CardTint: CaseIterable {
        case pink
        case mint
        case yellow
        case blue
        case lavender
        case peach

        var top: Color {
            switch self {
            case .pink: return MinikPretty.color(0xF9CDE4)
            case .mint: return MinikPretty.color(0xC1F0D9)
            case .yellow: return MinikPretty.color(0xFCEDAA)
            case .blue: return MinikPretty.color(0xC8E6FC)
            case .lavender: return MinikPretty.color(0xDCCDFA)
            case .peach: return MinikPretty.color(0xFFD5BE)
            }
        }

        var bottom: Color {
            switch self {
            case .pink: return MinikPretty.color(0xFDE8F2)
            case .mint: return MinikPretty.color(0xE5FAF0)
            case .yellow: return MinikPretty.color(0xFFF8D8)
            case .blue: return MinikPretty.color(0xE8F5FF)
            case .lavender: return MinikPretty.color(0xF1EBFF)
            case .peach: return MinikPretty.color(0xFFEFE5)
            }
        }
    }

    /// A menu card's face: the pastel gradient with a white rim over a soft drop edge.
    struct CardBackground: View {
        let tint: CardTint
        let cornerRadius: CGFloat

        init(tint: CardTint, cornerRadius: CGFloat = 22) {
            self.tint = tint
            self.cornerRadius = cornerRadius
        }

        var body: some View {
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(MinikPretty.shadowInk.opacity(0.12))
                    .offset(y: 3)
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tint.top, tint.bottom],
                            startPoint: UnitPoint.top,
                            endPoint: UnitPoint.bottom
                        )
                    )
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white, lineWidth: 2)
            }
            .allowsHitTesting(false)
        }
    }

    /// bg_round_button_white: the white circle behind Home and Trophy.
    struct RoundButtonBackground: View {
        init() {}

        var body: some View {
            ZStack {
                Circle()
                    .fill(MinikPretty.shadowInk.opacity(0.16))
                    .offset(y: 3)
                Circle()
                    .fill(Color.white)
            }
            .allowsHitTesting(false)
        }
    }

    /// A section header of the menus (bg_section_pill_*): a colored gradient pill
    /// with white Fredoka text, two soft stars at its end and, at its start, an art
    /// icon that stands a little taller than the pill (or an SF Symbol).
    struct SectionBanner: View {
        enum Icon {
            case art(String)
            case symbol(String)
            case none
        }

        let title: String
        let look: PillLook
        let icon: Icon
        let tablet: Bool
        let scale: CGFloat

        init(title: String, look: PillLook, icon: Icon, tablet: Bool, scale: CGFloat = 1) {
            self.title = title
            self.look = look
            self.icon = icon
            self.tablet = tablet
            self.scale = scale
        }

        /// dimens_pretty.xml: the phone value, or the sw600dp value on iPad.
        private func value(_ phone: CGFloat, _ pad: CGFloat) -> CGFloat {
            tablet ? pad * scale : phone
        }

        private var textStart: CGFloat {
            switch icon {
            case .art: return value(96, 128)
            case .symbol: return value(56, 74)
            case .none: return value(22, 30)
            }
        }

        var body: some View {
            ZStack(alignment: .leading) {
                pill
                iconView
            }
            .frame(height: value(58, 76))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(title))
            .accessibilityAddTraits(.isHeader)
        }

        private var pill: some View {
            HStack(spacing: 0) {
                Text(title)
                    .font(MinikPretty.titleFont(value(23, 30)))
                    .foregroundStyle(look.ink)
                    .shadow(color: look.inkShadow, radius: 1.5, x: 0, y: 1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.leading, textStart)
                Spacer(minLength: value(8, 12))
                stars
                    .padding(.trailing, value(18, 24))
            }
            .padding(.bottom, 3)
            .frame(height: value(46, 60))
            .frame(maxWidth: .infinity)
            .background {
                MinikPretty.PillBackground(look: look, pressed: false)
            }
        }

        private var stars: some View {
            HStack(spacing: value(5, 6)) {
                Image(systemName: "star.fill")
                    .font(.system(size: value(19, 26), weight: .bold))
                Image(systemName: "star.fill")
                    .font(.system(size: value(13, 17), weight: .bold))
            }
            .foregroundStyle(MinikPretty.color(0xFFC83A))
            .shadow(color: MinikPretty.color(0xF2A516), radius: 0.5, x: 0, y: 0.5)
            .accessibilityHidden(true)
        }

        @ViewBuilder
        private var iconView: some View {
            switch icon {
            case .art(let name):
                MinikArtworkImage(name: name)
                    .frame(width: value(86, 116), height: value(58, 76))
                    .padding(.leading, value(4, 6))
            case .symbol(let name):
                Image(systemName: name)
                    .font(.system(size: value(22, 28), weight: .bold))
                    .foregroundStyle(look.ink)
                    .shadow(color: look.inkShadow, radius: 1.5, x: 0, y: 1)
                    .frame(width: value(40, 52), height: value(43, 57))
                    .padding(.leading, value(10, 14))
                    .accessibilityHidden(true)
            case .none:
                EmptyView()
            }
        }
    }
}

// MARK: - Answer tiles

/// A white answer tile of the pretty design: rounded, a lavender rim (purple and a
/// lavender fill when selected), navy text and a soft shadow.
struct MinikChoiceTileStyle: ViewModifier {
    let selected: Bool

    init(selected: Bool) {
        self.selected = selected
    }

    func body(content: Content) -> some View {
        content
            .foregroundStyle(MinikPretty.navy)
            .padding(10)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(selected ? MinikPretty.lavender : Color.white)
                    .shadow(
                        color: MinikPretty.shadowInk.opacity(selected ? 0.18 : 0.10),
                        radius: selected ? 8 : 5,
                        x: 0,
                        y: selected ? 4 : 3
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(selected ? MinikPretty.purple : MinikPretty.lavenderRim, lineWidth: selected ? 3 : 2)
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    /// See MinikChoiceTileStyle.
    func minikChoiceTile(selected: Bool) -> some View {
        modifier(MinikChoiceTileStyle(selected: selected))
    }
}
