import SwiftUI

struct LanguageActivityLayout {
    let width: CGFloat
    let height: CGFloat
    let wide: Bool
    let accessibility: Bool
    /// The content height the panel shows without scrolling. `height` can be larger
    /// (the board's minimum, or the small-viewport board), and the panel then scrolls.
    let viewportHeight: CGFloat
}

/// The space between a Language panel's edges and its content.
enum LanguagePanelInsets {
    static func horizontal(wide: Bool) -> CGFloat { wide ? 21 : 14 }
    static func vertical(wide: Bool) -> CGFloat { wide ? 12 : 8 }
}

/// Android draws two Language panels, both in the rainbow-sky design's frosted
/// glass over the sky (pretty_glass_strong and bg_glass_panel_strong: white with a
/// 2 dp white rim). Letter Pairs' card (28 dp corners, 36 dp on tablets, 18 dp from
/// the screen's edges) is the default. WriteScreen's practice screens keep their
/// 20 dp side and 22 dp top and bottom margins (30 dp and 32 dp on tablets) with
/// the glass panel's 28 dp corners.
enum LanguagePanelStyle {
    case card
    case rounded

    func horizontalMargin(wide: Bool) -> CGFloat {
        switch self {
        case .card: return wide ? 40 : 18
        case .rounded: return wide ? 30 : 20
        }
    }

    func verticalMargin(wide: Bool) -> CGFloat {
        switch self {
        case .card: return wide ? 30 : 18
        case .rounded: return wide ? 32 : 22
        }
    }

    func cornerRadius(wide: Bool) -> CGFloat {
        switch self {
        case .card: return wide ? 36 : 28
        case .rounded: return 28
        }
    }
}

/// Android's framed Language activity surface in the rainbow-sky design: the sky
/// around a frosted glass panel. The board is laid out for the space the panel
/// really has; whenever it is still taller (accessibility text, small viewports)
/// the panel scrolls, and it neither scrolls nor bounces when it fits. Only
/// accessibility text sizes (AX1-AX5) select accessibility layouts. A game's panel
/// (`washed`, Android's applyGameBackgrounds) lays the light sky-to-lavender wash
/// under its board where the old artwork was.
struct LanguageActivityScreen<Content: View>: View {
    private let washed: Bool
    private let panelStyle: LanguagePanelStyle
    private let minimumContentHeight: (CGFloat, Bool) -> CGFloat
    private let content: (LanguageActivityLayout) -> Content
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(washed: Bool = false,
         panelStyle: LanguagePanelStyle = .card,
         minimumContentHeight: @escaping (CGFloat, Bool) -> CGFloat = { _, _ in 0 },
         @ViewBuilder content: @escaping (LanguageActivityLayout) -> Content) {
        self.washed = washed
        self.panelStyle = panelStyle
        self.minimumContentHeight = minimumContentHeight
        self.content = content
    }

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 700
            let horizontalMargin = panelStyle.horizontalMargin(wide: wide)
            let verticalMargin = panelStyle.verticalMargin(wide: wide)
            let panelWidth = max(1, min(900, geometry.size.width - 2 * horizontalMargin))
            let panelHeight = max(1, geometry.size.height - 2 * verticalMargin)
            let horizontalInset = LanguagePanelInsets.horizontal(wide: wide)
            let verticalInset = LanguagePanelInsets.vertical(wide: wide)
            let contentWidth = max(1, panelWidth - 2 * horizontalInset)
            let viewportHeight = max(1, panelHeight - 2 * verticalInset)
            // A genuinely small viewport lays the board out at a usable height and
            // scrolls instead of squeezing it.
            let boardHeight: CGFloat = panelHeight < 560 ? 700 : viewportHeight
            let layout = LanguageActivityLayout(
                width: contentWidth,
                height: max(minimumContentHeight(contentWidth, wide), boardHeight),
                wide: wide, accessibility: dynamicTypeSize.isAccessibilitySize,
                viewportHeight: viewportHeight
            )
            LanguageSkyPanel(
                width: panelWidth,
                height: panelHeight,
                cornerRadius: panelStyle.cornerRadius(wide: wide),
                washed: washed
            ) {
                ScrollView {
                    content(layout)
                        .frame(width: contentWidth)
                        .frame(minHeight: viewportHeight)
                        .padding(.horizontal, horizontalInset)
                        .padding(.vertical, verticalInset)
                }
                .scrollBounceBehavior(.basedOnSize)
                // Feedback layers find the panel's visible area through this space.
                .coordinateSpace(.named(LanguagePanelViewport.coordinateSpace))
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        // The sky stays a background so it never sizes the layout. As a ZStack
        // sibling a portrait artwork made the stack taller than the screen, and
        // GeometryReader pinned that stack at the top: the panel slid down, in
        // landscape completely off-screen.
        .background {
            MinikSkyBackground()
        }
    }
}

/// The panel as the child sees it, for the layers drawn over a scrolling board.
enum LanguagePanelViewport {
    /// LanguageActivityScreen's scroll view: its bounds are the visible panel.
    static let coordinateSpace = "languagePanelViewport"
}

extension GeometryProxy {
    /// The whole panel as it looks when nothing scrolls, in this proxy's coordinates,
    /// wherever the board has been scrolled to: Minik's success jump, the try-again
    /// Minik and the stars are placed in it, so they never depend on scrolling (owner
    /// QA, 25 October 2026: on a small phone the jumping Minik stood too low). Outside
    /// a LanguageActivityScreen it is this view's bounds widened by `outset`.
    func languageVisiblePanel(outset: CGSize) -> CGRect {
        bounds(of: .named(LanguagePanelViewport.coordinateSpace))
            ?? CGRect(origin: .zero, size: size).insetBy(dx: -outset.width, dy: -outset.height)
    }
}

// MARK: - The rainbow-sky design on the activity screens

/// Colours the Language activity screens add to MinikPretty's (Android's
/// bg_pretty_* drawables). Text on these light surfaces is always dark.
enum LanguageSkyPalette {
    /// bg_pretty_inner_panel: #E6F5FF at the top, white in the middle, #F3ECFF at the bottom.
    static let washTop = Color(red: 230 / 255, green: 245 / 255, blue: 255 / 255)
    static let washBottom = Color(red: 243 / 255, green: 236 / 255, blue: 255 / 255)
    /// bg_pretty_speaker: #F4F1FF with a 2 dp #9D86F5 ring.
    static let speakerFill = Color(red: 244 / 255, green: 241 / 255, blue: 255 / 255)
    static let speakerRing = Color(red: 157 / 255, green: 134 / 255, blue: 245 / 255)
    /// #CDBDFB: the lavender rim of the white tiles and fields (bg_pretty_field).
    static let tileRim = Color(red: 205 / 255, green: 189 / 255, blue: 251 / 255)
    /// bg_pretty_ttt_cell: the #C9B6FF rim, the #D9CCFF lip and the #F4EFFF foot.
    static let cellRim = Color(red: 201 / 255, green: 182 / 255, blue: 255 / 255)
    static let cellLip = Color(red: 217 / 255, green: 204 / 255, blue: 255 / 255)
    static let cellFoot = Color(red: 244 / 255, green: 239 / 255, blue: 255 / 255)
    /// bg_pretty_option_frame and bg_memory_card_face_pretty: #A086F7 to #62C6FA.
    static let frameStart = Color(red: 160 / 255, green: 134 / 255, blue: 247 / 255)
    static let frameEnd = Color(red: 98 / 255, green: 198 / 255, blue: 250 / 255)
    /// A chosen answer: a light tint, a strong rim and dark text, never white text.
    static let correctFill = Color(red: 214 / 255, green: 245 / 255, blue: 226 / 255)
    static let correctRim = Color(red: 34 / 255, green: 160 / 255, blue: 107 / 255)
    static let correctInk = Color(red: 17 / 255, green: 102 / 255, blue: 63 / 255)
    static let incorrectFill = Color(red: 255 / 255, green: 222 / 255, blue: 228 / 255)
    static let incorrectRim = Color(red: 229 / 255, green: 72 / 255, blue: 77 / 255)
    static let incorrectInk = Color(red: 163 / 255, green: 19 / 255, blue: 47 / 255)
}

/// bg_pretty_inner_panel: the soft sky-to-lavender wash inside the game panels,
/// light enough that every text and board stays clearly readable.
struct LanguageSkyWash: View {
    var body: some View {
        LinearGradient(
            colors: [LanguageSkyPalette.washTop, Color.white, LanguageSkyPalette.washBottom],
            startPoint: UnitPoint.top,
            endPoint: UnitPoint.bottom
        )
        .accessibilityHidden(true)
    }
}

/// MinikGlassPanel at a fixed size, its content clipped to the rounded corners. A
/// `washed` panel (the games) has the light wash under its content.
struct LanguageSkyPanel<Content: View>: View {
    private let width: CGFloat
    private let height: CGFloat
    private let cornerRadius: CGFloat
    private let washed: Bool
    private let content: Content

    init(
        width: CGFloat,
        height: CGFloat,
        cornerRadius: CGFloat,
        washed: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
        self.washed = washed
        self.content = content()
    }

    var body: some View {
        MinikGlassPanel(padding: 0, cornerRadius: cornerRadius) {
            content
                .frame(width: width, height: height)
                .background {
                    if washed {
                        LanguageSkyWash()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        // MinikGlassPanel fills the width it is offered: this keeps it the panel's.
        .frame(width: width, height: height)
    }
}

/// bg_pretty_speaker: a pale lavender circle with a lavender ring and the speaker
/// in the design's purple, on a soft shadow.
struct LanguageSkySpeakerFace: View {
    let diameter: CGFloat
    /// The glyph's share of the circle.
    var glyphRatio: CGFloat = 0.54

    var body: some View {
        Image(systemName: "speaker.wave.1.fill")
            .resizable()
            .scaledToFit()
            .frame(width: diameter * glyphRatio, height: diameter * glyphRatio)
            .foregroundStyle(MinikPretty.purple)
            // Android's speaker icon is not mirrored in right-to-left layouts.
            .environment(\.layoutDirection, .leftToRight)
            .frame(width: diameter, height: diameter)
            .background {
                Circle()
                    .fill(LanguageSkyPalette.speakerFill)
                    .shadow(color: MinikPretty.navy.opacity(0.14), radius: 4, x: 0, y: 2)
            }
            .overlay {
                Circle()
                    .strokeBorder(LanguageSkyPalette.speakerRing, lineWidth: 2)
            }
    }
}

/// Round buttons and tiles of the design shrink a little while they are pressed.
struct LanguageSkyPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.95 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// The close and replay row at the top of a Language panel.
enum LanguagePanelHeader {
    /// A compact 48-point bar (56 on iPad; 80 and 110 with the logo), which the
    /// other Language boards budget for.
    case compact
    /// WriteScreen's practice header (fragment_choose_right_image), measured from
    /// the panel: the 57 dp speaker 15 dp below its top (100 dp and 20 dp on
    /// tablets) and the close artwork 20 dp from its top and end edges (a 38 dp
    /// view with 3 dp padding 17 dp from the corner; 55 dp and 32 dp on tablets).
    /// `scale` enlarges it with the board on iPads larger than the iPad mini.
    case practice

    func height(wide: Bool, showsLogo: Bool = false, scale: CGFloat = 1) -> CGFloat {
        switch self {
        case .compact:
            return showsLogo ? (wide ? 110 : 80) : (wide ? 56 : 48)
        case .practice:
            return speakerTop(wide: wide, scale: scale) + speakerDiameter(wide: wide, scale: scale)
        }
    }

    func speakerDiameter(wide: Bool, scale: CGFloat = 1) -> CGFloat {
        switch self {
        case .compact: return wide ? 56 : 48
        case .practice: return (wide ? 100 : 57) * scale
        }
    }

    func speakerTop(wide: Bool, scale: CGFloat = 1) -> CGFloat {
        switch self {
        case .compact:
            return 0
        case .practice:
            let margin: CGFloat = (wide ? 20 : 15) * scale
            return max(0, margin - LanguagePanelInsets.vertical(wide: wide))
        }
    }
}

struct LanguagePanelNavigation: View {
    let wide: Bool
    var showsLogo = false
    var header = LanguagePanelHeader.compact
    /// Enlarges the practice header with the board on iPads larger than the iPad mini.
    var scale: CGFloat = 1
    var onReplay: (() -> Void)?
    let onExit: () -> Void

    var body: some View {
        switch header {
        case .compact:
            compactBar
        case .practice:
            practiceBar
        }
    }

    private var compactBar: some View {
        ZStack(alignment: .top) {
            HStack(alignment: .top) {
                if showsLogo {
                    MinikLanguageLogo().frame(width: wide ? 88 : 64, height: wide ? 95 : 70)
                }
                Spacer(minLength: 0)
                Button(action: onExit) {
                    MinikArtworkImage(name: MinikVisualAsset.close)
                        .frame(width: wide ? 48 : 34, height: wide ? 48 : 34)
                        .frame(width: wide ? 56 : 44, height: wide ? 56 : 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close exercise")
                // Level with the wordmark's upper part; 5 points since the owner's
                // QA of the Cards header (25 October 2026) halved its margins.
                .padding(.top, showsLogo ? 5 : 0)
            }
            if let onReplay {
                LanguageReplayButton(action: onReplay)
            }
        }
        .frame(height: header.height(wide: wide, showsLogo: showsLogo))
    }

    /// Android's practice header: the speaker centred, the close artwork at the
    /// end (the left in Hebrew), its tap target centred on the artwork.
    private var practiceBar: some View {
        let artwork: CGFloat = (wide ? 49 : 32) * scale
        let target: CGFloat = max(wide ? 56 : 44, artwork)
        let artworkMargin: CGFloat = (wide ? 35 : 20) * scale
        let centring = (artwork - target) / 2
        let closeTop = max(0, artworkMargin - LanguagePanelInsets.vertical(wide: wide) + centring)
        let closeEnd = max(0, artworkMargin - LanguagePanelInsets.horizontal(wide: wide) + centring)
        return ZStack(alignment: .topTrailing) {
            if let onReplay {
                // Centred as in the phone screenshots. Android's tablet layout leaves it 27 dp
                // off centre only because Plus hides the home button whose 55 dp start margin
                // the speaker keeps.
                LanguageSpeakerButton(diameter: header.speakerDiameter(wide: wide, scale: scale), action: onReplay)
                    .padding(.top, header.speakerTop(wide: wide, scale: scale))
                    .frame(maxWidth: .infinity, alignment: .top)
            }
            Button(action: onExit) {
                MinikArtworkImage(name: MinikVisualAsset.close)
                    .frame(width: artwork, height: artwork)
                    .frame(width: target, height: target)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close exercise")
            .padding(.top, closeTop)
            .padding(.trailing, closeEnd)
        }
        .frame(maxWidth: .infinity, alignment: .topTrailing)
        .frame(height: header.height(wide: wide, scale: scale), alignment: .top)
    }
}

/// Android's speaker button in the rainbow-sky design (bg_pretty_speaker around
/// ic_lock_silent_mode_off): the lavender circle with the speaker inside. Android's
/// glyph is a tall cone with short waves, about half the circle wide and a little
/// more than half tall, so the one-wave symbol fills a square of about half the
/// circle; the two-wave symbol came out wider and flatter.
struct LanguageSpeakerButton: View {
    let diameter: CGFloat
    var label: LocalizedStringKey = "Replay current word"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            LanguageSkySpeakerFace(diameter: diameter)
                .contentShape(Circle())
        }
        .buttonStyle(LanguageSkyPressStyle())
        .accessibilityLabel(label)
    }
}

private struct LanguageRewardStateKey: EnvironmentKey {
    static let defaultValue = RewardState()
}

extension EnvironmentValues {
    var languageRewardState: RewardState {
        get { self[LanguageRewardStateKey.self] }
        set { self[LanguageRewardStateKey.self] = newValue }
    }
}

struct LanguagePointsBadge: View {
    @Environment(\.languageRewardState) private var rewards

    var body: some View {
        VStack(spacing: 3) {
            Text("Points").font(.subheadline.bold())
            Text(rewards.points, format: .number).font(.title3.bold().monospacedDigit())
        }
        // The badge has a fixed width: larger text shrinks onto one line instead
        // of wrapping letter by letter.
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .padding(.horizontal, 4)
        .foregroundStyle(Color(red: 0.29, green: 0.22, blue: 0.71))
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(Color(red: 0.97, green: 0.96, blue: 1), in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color(red: 0.55, green: 0.49, blue: 0.96), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Letter Pairs' picture tile in the rainbow-sky design: the white answer tile with
/// its lavender rim (MinikChoiceTileStyle). The chosen picture takes the purple rim
/// and the lavender fill and grows a little, as Android's chosen tile does.
struct LanguagePairTileStyle: ButtonStyle {
    let selected: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .minikChoiceTile(selected: selected)
            .scaleEffect(selected && !reduceMotion ? 1.045 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.11), value: selected)
            .opacity(configuration.isPressed ? 0.9 : 1)
    }
}

private struct LanguageEncouragementEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var languageEncouragementEnabled: Bool {
        get { self[LanguageEncouragementEnabledKey.self] }
        set { self[LanguageEncouragementEnabledKey.self] = newValue }
    }
}

private struct LanguageWordBonusRunKey: EnvironmentKey { static let defaultValue = 0 }
extension EnvironmentValues {
    var languageWordBonusRun: Int {
        get { self[LanguageWordBonusRunKey.self] }
        set { self[LanguageWordBonusRunKey.self] = newValue }
    }
}
