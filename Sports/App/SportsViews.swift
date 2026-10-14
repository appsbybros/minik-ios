import SwiftUI
import UIKit
import WebKit

/// SwiftUI versions of the Android SportsActivity pages (a 64 dp title bar with the pink back arrow,
/// then a centred, scrolling column at most 520 dp wide). Sizes are Android sp/dp as points.
private let ink: UInt32 = 0xff163d50

// MARK: Building blocks

/// Android `backButton`: a raised pink arrow pointing to the start side.
private struct BackArrow: Shape {
    let rtl: Bool

    func path(in rect: CGRect) -> Path {
        let cx = rect.midX
        let cy = rect.midY
        let d: CGFloat = 10
        let sign: CGFloat = rtl ? -1 : 1
        var p = Path()
        p.move(to: CGPoint(x: cx - sign * d, y: cy))
        p.addLine(to: CGPoint(x: cx + sign * d, y: cy))
        p.move(to: CGPoint(x: cx - sign * d, y: cy))
        p.addLine(to: CGPoint(x: cx, y: cy - d))
        p.move(to: CGPoint(x: cx - sign * d, y: cy))
        p.addLine(to: CGPoint(x: cx, y: cy + d))
        return p
    }
}

@MainActor
struct BackButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // Android draws the arrow three times: a dark edge 2 dp lower, the pink face, and a thin
            // highlight 1 dp higher.
            ZStack {
                BackArrow(rtl: AppText.rtl)
                    .stroke(SportsPalette.color(0xff9d225a), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .offset(y: 2)
                BackArrow(rtl: AppText.rtl)
                    .stroke(SportsPalette.color(0xffe63f89), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                BackArrow(rtl: AppText.rtl)
                    .stroke(SportsPalette.color(0xffffadd1), style: StrokeStyle(lineWidth: 1, lineCap: .round))
                    .offset(y: -1)
            }
            .frame(width: 56, height: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

/// Android `label(text, size, color)`.
@MainActor
struct SLabel: View {
    let text: String
    var size: CGFloat = 17
    var color: UInt32 = ink
    var bold = false

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: bold ? .bold : .regular))
            .foregroundColor(SportsPalette.color(color))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
    }
}

/// Android `button(text, color)`: 54 high, bold 17 (shrinking to 12), on a raised sky surface with
/// 18 dp corners (FamilySkyDrawable); a disabled button has the gray face.
@MainActor
struct SButton: View {
    let title: String
    var color: UInt32 = 0xffc6ecdd
    var textColor: UInt32 = ink
    var enabled = true
    var top: CGFloat = 10
    let action: () -> Void

    var body: some View {
        Button(action: { if enabled { action() } }) {
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(SportsPalette.color(textColor))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(12.0 / 17.0)
                .padding(.horizontal, 12)
                .frame(maxWidth: 520, minHeight: 54, maxHeight: 54)
        }
        .buttonStyle(SportsSkyButtonStyle(color: color, enabled: enabled))
        .padding(.top, top)
    }
}

/// Android `page(title, back)`: the title bar, then the centred column (FamilyReadingPanel: the whole
/// width in portrait, about half of a landscape window). The home menu reserves the "More below" row
/// under the scrolling column (Android FamilyMoreFrame).
@MainActor
struct SPage<Content: View>: View {
    let title: String
    let back: (() -> Void)?
    let moreCue: Bool
    let content: Content
    @StateObject private var cue = SportsScrollCue()

    init(_ title: String, back: (() -> Void)?, moreCue: Bool = false, @ViewBuilder content: () -> Content) {
        self.title = title
        self.back = back
        self.moreCue = moreCue
        self.content = content()
    }

    var body: some View {
        GeometryReader { geo in
            let column = SportsSky.column(geo)
            VStack(spacing: 0) {
                ZStack(alignment: .leading) {
                    Text(title)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(SportsPalette.color(ink))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(16.0 / 24.0)
                        .padding(.horizontal, 58)
                        .frame(maxWidth: .infinity, minHeight: 64)
                    if let back = back {
                        BackButton(title: AppText.t("Back", "חזרה")) { back() }
                    }
                }
                .frame(minHeight: 64)
                ScrollView {
                    VStack(spacing: 0) {
                        content
                    }
                    .frame(maxWidth: column)
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity)
                    .background {
                        if moreCue { SportsScrollProbe(cue: cue) }
                    }
                }
                if moreCue {
                    MoreBelowCue(cue: cue)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(SportsPalette.color(SportsPalette.page).ignoresSafeArea())
        .environment(\.layoutDirection, AppText.rtl ? .rightToLeft : .leftToRight)
    }
}

/// Android `FamilyMoreFrame` on the light menu: a 48 point row under the menu with "More below" and a
/// gently bouncing chevron while more actions lie below; a tap scrolls about two thirds of a screen.
/// The row keeps its place when hidden, so it never covers an action.
@MainActor
struct MoreBelowCue: View {
    @ObservedObject var cue: SportsScrollCue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    var body: some View {
        let shown = cue.more
        let animate = shown && !reduceMotion && !voiceOver
        Button(action: { cue.scrollDown() }) {
            HStack(spacing: 0) {
                Text(FamilyMessages.text("More below", "עוד למטה"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(SportsPalette.color(0xff183652))
                    .shadow(color: SportsPalette.color(0xfff7fbff), radius: 1, x: 0, y: 1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                TimelineView(.animation(minimumInterval: nil, paused: !animate)) { timeline in
                    ChevronDown()
                        .stroke(SportsPalette.color(0xff245477), style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                        .shadow(color: Color.black.opacity(0.6), radius: 1, x: 0, y: 1)
                        .frame(width: 38, height: 44)
                        .offset(y: animate ? MoreBelowCue.bounce(timeline.date) : 0)
                }
                .frame(width: 38, height: 44)
            }
            .frame(maxWidth: .infinity, minHeight: 48, maxHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(shown ? 1 : 0)
        .allowsHitTesting(shown)
        .accessibilityHidden(!shown)
        .accessibilityLabel(FamilyMessages.text("More options below. Tap to scroll", "עוד אפשרויות למטה. הקישו לגלילה"))
    }

    /// Android's ObjectAnimator: 0 to 4 dp in 850 ms and back, accelerating and decelerating.
    nonisolated static func bounce(_ date: Date) -> CGFloat {
        let cycle = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.7) / 0.85
        let t = cycle > 1 ? 2 - cycle : cycle
        return CGFloat(4 * (0.5 - 0.5 * cos(Double.pi * t)))
    }
}

/// Android `choose(title, items, current, name, enabled)`: a Spinner with the chevron at the end.
@MainActor
struct SChoose: View {
    let title: String
    let items: [String]
    let selected: Int
    var enabled = true
    let change: (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(SportsPalette.color(ink))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
                .padding(.bottom, 7)
            Menu {
                ForEach(Array(items.enumerated()), id: \.offset) { pair in
                    Button(pair.element) { if pair.offset != selected { change(pair.offset) } }
                }
            } label: {
                HStack(spacing: 0) {
                    Text(selected >= 0 && selected < items.count ? items[selected] : "")
                        .font(.system(size: 17))
                        .foregroundColor(SportsPalette.color(ink))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                    ChevronDown()
                        .stroke(SportsPalette.color(ink), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 44, height: 56)
                }
                .frame(maxWidth: 520, minHeight: 56, maxHeight: 56)
                .background(SportsSkySurface(color: 0xffdfedf6, enabled: enabled))
            }
            .disabled(!enabled)
        }
        .opacity(enabled ? 1 : 0.5)
    }
}

private struct ChevronDown: Shape {
    func path(in rect: CGRect) -> Path {
        let x = rect.midX
        let y = rect.midY
        let d: CGFloat = 6
        var p = Path()
        p.move(to: CGPoint(x: x - d, y: y - d / 2))
        p.addLine(to: CGPoint(x: x, y: y + d / 2))
        p.addLine(to: CGPoint(x: x + d, y: y - d / 2))
        return p
    }
}

/// Android `Switch` rows (text at the start, the switch at the end).
@MainActor
struct SSwitch: View {
    let title: String
    var size: CGFloat = 17
    let isOn: Bool
    let change: (Bool) -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { isOn }, set: { change($0) })) {
            Text(title)
                .font(.system(size: size))
                .foregroundColor(SportsPalette.color(ink))
        }
        .frame(minHeight: 56)
    }
}

/// Android `FamilyMenu` colours.
enum FamilyMenuColors {
    static let learn: UInt32 = 0xffb8d9ff
    static let play: UInt32 = 0xffb9f4dc
    static let saved: UInt32 = 0xffe8dcff
    static let advanced: UInt32 = 0xffffe082
    static let link: UInt32 = 0xff2869bd
    static let ink: UInt32 = 0xff282d4e
}

/// Android `FamilyMenu.section` on a light page ("family-menu-light"): a raised pale panel
/// (FamilySkyDrawable panel) outlined in the section colour, ink title, − / + sign.
@MainActor
struct FamilySection<Content: View>: View {
    let title: String
    let color: UInt32
    let open: Bool
    let toggle: () -> Void
    let content: Content

    init(_ title: String, color: UInt32, open: Bool, toggle: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.title = title
        self.color = color
        self.open = open
        self.toggle = toggle
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 0) {
                    Text(title)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundColor(SportsPalette.color(FamilyMenuColors.ink))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(open ? "−" : "+")
                        .font(.system(size: 26))
                        .foregroundColor(SportsPalette.color(FamilyMenuColors.ink))
                        .frame(width: 42, height: 48)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .frame(minHeight: 54)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title + (open ? ", −" : ", +"))
            if open {
                VStack(spacing: 0) { content }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(SportsSkySurface(color: color, panel: true, strokeWidth: 2, strokeColor: color))
        .padding(.bottom, 14)
    }
}

/// Android `FamilyMenu.style`: a raised section button in the section colour with ink text, 15 dp corners.
@MainActor
struct FamilyButton: View {
    let title: String
    let color: UInt32
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(SportsPalette.color(FamilyMenuColors.ink))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(12.0 / 17.0)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 54, maxHeight: 54)
        }
        .buttonStyle(SportsSkyButtonStyle(color: color, radius: 15))
        .padding(.top, 4)
        .padding(.bottom, 8)
    }
}

/// Android `FamilyMenu.link`: the quiet underlined footer link.
@MainActor
struct FamilyLink: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .underline()
                .foregroundColor(SportsPalette.color(FamilyMenuColors.link))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(RoundedRectangle(cornerRadius: 8).fill(SportsPalette.color(0xeef7fbff)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Android `Intent.createChooser` for text: the system share sheet.
struct SportsActivityView: UIViewControllerRepresentable {
    let text: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        return UIActivityViewController(activityItems: [text], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Android `JourneyCelebration`: a finite celebration; with Reduce Motion it is the same still badge.
@MainActor
struct JourneyCelebration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @State private var born = Date()
    @State private var done = false

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: done || reduceMotion)) { timeline in
            Canvas { context, size in
                draw(&context, size, timeline.date.timeIntervalSince(born))
            }
        }
        .accessibilityHidden(true)
        .task {
            try? await Task.sleep(nanoseconds: 1_900_000_000)
            done = true
        }
    }

    private func draw(_ context: inout GraphicsContext, _ size: CGSize, _ elapsed: Double) {
        let motion = !reduceMotion
        let t = motion ? min(elapsed, 1.8) : 1.8
        let cx = size.width / 2
        let cy = size.height / 2
        let r = size.height * 0.29
        let colors: [UInt32] = [0xffffd769, 0xff93f2d2, 0xffc4b2ff, 0xffffb8c9]
        // Android draws the confetti in pixels: 8 x 14 with 2 px corners.
        let px = 1 / max(displayScale, 1)
        for i in 0..<20 {
            let angle = Double(i) * 2 * Double.pi / 20
            let radius = r * (1.5 + CGFloat(min(t, 1)) * 0.85)
            let x = cx + CGFloat(cos(angle)) * radius
            let y = cy + CGFloat(sin(angle)) * radius * 0.63
            var piece = context
            piece.translateBy(x: x, y: y)
            piece.rotate(by: .degrees(Double(i) * 31 + t * 75))
            let alpha: Double = (elapsed < 1.8 && motion) ? 1 : 190.0 / 255.0
            let shape = Path(roundedRect: CGRect(x: -4 * px, y: -7 * px, width: 8 * px, height: 14 * px), cornerRadius: 2 * px)
            piece.fill(shape, with: .color(SportsPalette.color(colors[i % 4]).opacity(alpha)))
        }
        context.fill(Path(ellipseIn: CGRect(x: cx - r * 1.12, y: cy - r * 1.12, width: r * 2.24, height: r * 2.24)), with: .color(SportsPalette.color(0xff173f55)))
        context.fill(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)), with: .color(SportsPalette.color(colors[0])))
        var check = Path()
        check.move(to: CGPoint(x: cx - r * 0.43, y: cy))
        check.addLine(to: CGPoint(x: cx - r * 0.08, y: cy + r * 0.29))
        check.addLine(to: CGPoint(x: cx + r * 0.47, y: cy - r * 0.3))
        context.stroke(check, with: .color(SportsPalette.color(0xff173f55)), style: StrokeStyle(lineWidth: r * 0.14, lineCap: .round))
    }
}

/// A portrait image (Android ImageView, FIT_CENTER).
@MainActor
struct Portrait: View {
    let id: String
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Group {
            if let image = SportsArt.shared.portrait(id) {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Color.clear
            }
        }
        .frame(width: width, height: height)
    }
}

/// Android `carousel(title, initial, compact)`: ❮ portrait ❯ (swipe to change), the name and, for
/// volleyball, the six skill ratings.
@MainActor
struct Carousel: View {
    let controller: SportsController
    let title: String
    let current: String
    var compact = false
    let changed: (String) -> Void
    @State private var offset: CGFloat = 0
    @State private var fade: Double = 1
    @State private var token = 0

    var body: some View {
        let c = controller
        let choices = Characters.forSport(c.sport)
        let index = max(choices.firstIndex { $0.id == current } ?? 0, 0)
        let character = choices[index]
        VStack(spacing: 0) {
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(SportsPalette.color(ink))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            HStack(spacing: 0) {
                arrow("❮") { step(AppText.rtl ? 1 : -1, choices, index) }
                Portrait(id: character.id, width: compact ? 118 : 145, height: compact ? 120 : 160)
                    .offset(x: offset)
                    .opacity(fade)
                    .padding(.horizontal, 16)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 12).onEnded { value in
                        let dx = value.translation.width
                        if abs(dx) > 28 && abs(dx) > abs(value.translation.height) { shift(dx < 0 ? 1 : -1, choices, index) }
                    })
                    .accessibilityLabel(character.name(c.hebrew))
                arrow("❯") { step(AppText.rtl ? -1 : 1, choices, index) }
            }
            .environment(\.layoutDirection, .leftToRight)
            Text(character.name(c.hebrew))
                .font(.system(size: 18))
                .foregroundColor(SportsPalette.color(ink))
                .padding(.top, 14)
                .padding(.bottom, 18)
            if c.sport == .volley {
                Text(ratings(character.id))
                    .font(.system(size: 14))
                    .foregroundColor(SportsPalette.color(ink))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 18)
            }
        }
    }

    private func ratings(_ id: String) -> String {
        let c = controller
        let q = VolleySkills.of(id)
        let names = [c.tr("Speed", "מהירות"), c.tr("Precision", "דיוק"), c.tr("Power", "עוצמה"), c.tr("Hitting", "חבטה"),
                     c.tr("Blocking", "חסימה"), c.tr("Serve", "הגשה")]
        let pairs = Array(zip(names, q.values()))
        var rows: [String] = []
        var i = 0
        while i < pairs.count {
            let row = pairs[i..<min(i + 2, pairs.count)].map { n, v in n + " " + String(repeating: "★", count: v) + String(repeating: "☆", count: 5 - v) }
            rows.append(row.joined(separator: "   ·   "))
            i += 2
        }
        return rows.joined(separator: "\n")
    }

    private func arrow(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(symbol)
                .font(.system(size: 29))
                .foregroundColor(SportsPalette.color(ink))
                .frame(width: 52, height: 52)
        }
        .buttonStyle(SportsSkyButtonStyle(color: 0xffdfedf6))
    }

    /// Android's arrow buttons change the player at once, without animation.
    private func step(_ step: Int, _ choices: [SportsCharacter], _ index: Int) {
        token += 1
        offset = 0
        fade = 1
        changed(choices[(index + step + choices.count) % choices.count].id)
    }

    /// Android: a swipe slides 42 dp out (110 ms), switches, then slides back in (150 ms).
    private func shift(_ step: Int, _ choices: [SportsCharacter], _ index: Int) {
        let next = choices[(index + step + choices.count) % choices.count].id
        token += 1
        let mine = token
        withAnimation(.linear(duration: 0.11)) {
            offset = CGFloat(-42 * step)
            fade = 0
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 110_000_000)
            guard mine == token else { return }
            changed(next)
            offset = CGFloat(42 * step)
            withAnimation(.linear(duration: 0.15)) {
                offset = 0
                fade = 1
            }
        }
    }
}

// MARK: Root

struct SportsRootView: View {
    @StateObject private var controller = SportsController()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            SportsPalette.color(SportsPalette.page).ignoresSafeArea()
            content
            if controller.pausePresented {
                PauseDialog(controller: controller)
            }
            if controller.saveCupPresented {
                SaveCupDialog(controller: controller)
            }
            // Under the app's own grown-up gate and toasts, which the card's links open above it.
            FamilyOverlay()
            if controller.gatePresented {
                ParentGate(controller: controller)
            }
            SportsToastOverlay(controller: controller)
        }
        .preferredColorScheme(.light)
        .onChange(of: scenePhase, initial: true) { _, phase in
            controller.scenePhaseChanged(active: phase == .active)
        }
        .sheet(item: $controller.shareSheet) { item in
            SportsActivityView(text: item.text)
        }
    }

    @MainActor @ViewBuilder private var content: some View {
        let c = controller
        switch c.screen {
        case .game: GamePage(controller: c)
        case .home: HomePage(controller: c)
        case .journey: JourneyPage(controller: c)
        case .journeyList: JourneyListPage(controller: c)
        case .journeyResult: JourneyResultPage(controller: c)
        case .setup: SetupPage(controller: c)
        case .avatars: AvatarsPage(controller: c)
        case .settings: SettingsPage(controller: c)
        case .support: SupportPage(controller: c)
        case .tutorial: TutorialPage(controller: c)
        case .tournament: TournamentPage(controller: c)
        case .online: OnlinePage(controller: c)
        case .roomOptions: RoomOptionsPage(controller: c)
        case .publicTournaments: PublicTournamentsPage(controller: c)
        case .lobby: LobbyPage(controller: c)
        case .result: ResultPage(controller: c)
        case .parentZone: ParentZonePage(controller: c)
        case .privacy: PrivacyPage(controller: c)
        }
    }
}

@MainActor
struct SportsToastOverlay: View {
    @ObservedObject var controller: SportsController

    var body: some View {
        VStack {
            Spacer()
            if let toast = controller.toast {
                Text(toast.text)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color(white: 0.2).opacity(0.92)))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 64)
                    .transition(.opacity)
                    .task(id: toast.id) {
                        try? await Task.sleep(nanoseconds: 3_500_000_000)
                        await MainActor.run {
                            if controller.toast?.id == toast.id { controller.toast = nil }
                        }
                    }
            }
        }
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.2), value: controller.toast)
    }
}

/// Android `dialog(title, body, actions)`: a rounded card with right-aligned text buttons.
@MainActor
private struct DialogCard<Content: View>: View {
    let title: String
    let vertical: Bool
    let actions: [(String, () -> Void)]
    let cancel: () -> Void
    let bodyView: Content

    init(_ title: String, vertical: Bool = false, actions: [(String, () -> Void)], cancel: @escaping () -> Void, @ViewBuilder body: () -> Content) {
        self.title = title
        self.vertical = vertical
        self.actions = actions
        self.cancel = cancel
        self.bodyView = body()
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { cancel() }
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(SportsPalette.color(ink))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 16)
                bodyView
                if vertical {
                    VStack(alignment: .trailing, spacing: 0) { buttons }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                } else {
                    HStack(spacing: 0) {
                        Spacer()
                        buttons
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 14)
            .background(SportsSkySurface(color: 0xfff6fbff))
            .padding(.horizontal, 28)
            .frame(maxWidth: 520)
        }
        .environment(\.layoutDirection, AppText.rtl ? .rightToLeft : .leftToRight)
    }

    @ViewBuilder private var buttons: some View {
        ForEach(Array(actions.enumerated()), id: \.offset) { pair in
            let back = pair.element.0 == AppText.t("Back", "חזרה")
            Button(action: pair.element.1) {
                Text(pair.element.0)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(SportsPalette.color(back ? SportsPalette.pink : ink))
                    .padding(.horizontal, 12)
                    .frame(minHeight: 48)
            }
            .buttonStyle(.plain)
        }
    }
}

/// Android `pauseMenu()`: "Take a break" with Continue, Save for later and Finish; cancelling continues.
@MainActor
struct PauseDialog: View {
    @ObservedObject var controller: SportsController

    var body: some View {
        let c = controller
        DialogCard(c.tr("Take a break", "לוקחים הפסקה"), vertical: true,
                   actions: [(c.tr("Continue", "המשך"), { c.resumeFromPause() }),
                             (c.tr("Save for later", "שמירה להמשך"), { c.saveForLater() }),
                             (c.tr("Finish", "סיום"), { c.finishFromPause() })],
                   cancel: { c.resumeFromPause() }) {
            EmptyView()
        }
    }
}

/// Android `FamilyTournamentUi.confirmSave`: "Save this tournament?" on a raised pale panel, with
/// three tall buttons (Save, a pink Don't save, Cancel). A tap outside does not close it.
@MainActor
struct SaveCupDialog: View {
    @ObservedObject var controller: SportsController

    var body: some View {
        let c = controller
        let titleInk: UInt32 = 0xff282d4e
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
            GeometryReader { geo in
                ScrollView {
                    card(c, titleInk)
                        .frame(maxWidth: .infinity, minHeight: geo.size.height)
                }
            }
        }
        .environment(\.layoutDirection, AppText.rtl ? .rightToLeft : .leftToRight)
    }

    private func card(_ c: SportsController, _ titleInk: UInt32) -> some View {
        VStack(spacing: 0) {
            Text(c.tr("Save this tournament?", "לשמור את הטורניר?"))
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(SportsPalette.color(titleInk))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            Text(c.tr("Save to continue later. Don't save removes the saved cup on this device; other players can continue.",
                      "שמרו כדי להמשיך מאוחר יותר. ללא שמירה, הגביע השמור יוסר מהמכשיר הזה; שחקנים אחרים יוכלו להמשיך."))
                .font(.system(size: 17))
                .foregroundColor(SportsPalette.color(titleInk))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 16)
                .padding(.bottom, 12)
            choice(c.tr("Save", "שמירה"), 0xffb8d9ff, titleInk) { c.saveCupAndLeave() }
            choice(c.tr("Don't save", "לא לשמור"), 0xffe91e63, 0xffffffff) { c.discardCupAndLeave() }
            choice(c.tr("Cancel", "ביטול"), 0xffe8e0ff, titleInk) { c.cancelSaveCup() }
        }
        .padding(24)
        .background(SportsSkySurface(color: 0xfff6f8ff, radius: 24, panel: true))
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .frame(maxWidth: 520)
    }

    private func choice(_ title: String, _ color: UInt32, _ text: UInt32, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(SportsPalette.color(text))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: 64, maxHeight: 64)
        }
        .buttonStyle(SportsSkyButtonStyle(color: color, radius: 16))
        .padding(.top, 18)
    }
}

/// Android `parentGate(action)`: "For a grown-up: 8 × 7 = ?" with a number field.
@MainActor
struct ParentGate: View {
    @ObservedObject var controller: SportsController

    var body: some View {
        let c = controller
        let raw = c.tr("For a grown-up: 8 × 7 = ?", "למבוגר: 8 × 7 = ?")
        DialogCard(ParentGate.isolate(raw), actions: [(c.tr("Back", "חזרה"), { c.cancelGate() }), (c.tr("Continue", "המשך"), { c.confirmGate() })],
                   cancel: { c.cancelGate() }) {
            TextField(c.tr("Your answer", "התשובה שלכם"), text: $controller.gateAnswer)
                .keyboardType(.numberPad)
                .font(.system(size: 18))
                .foregroundColor(SportsPalette.color(ink))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(minHeight: 48)
                .background(RoundedRectangle(cornerRadius: 10).stroke(SportsPalette.color(0xff567780), lineWidth: 1))
                .padding(.bottom, 12)
        }
    }

    /// Android wraps "8 × 7 = ?" (or "؟") in LRI…PDI so it reads left to right in every language.
    nonisolated static func isolate(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "8 × 7 = [؟?]") else { return text }
        let ns = text as NSString
        var output = text
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {
            let found = ns.substring(with: match.range)
            output = (output as NSString).replacingCharacters(in: match.range, with: "\u{2066}" + found + "\u{2069}")
        }
        return output
    }
}

// MARK: Game

@MainActor
struct SportsGameHost: UIViewRepresentable {
    let view: SportsView

    func makeUIView(context: Context) -> SportsView { return view }
    func updateUIView(_ uiView: SportsView, context: Context) {}
}

/// Android `present(e, id, link)`: the court with the back (pause) button and the tutorial controls.
@MainActor
struct GamePage: View {
    @ObservedObject var controller: SportsController

    var body: some View {
        let c = controller
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            ZStack(alignment: .topLeading) {
                if let v = c.view {
                    SportsGameHost(view: v)
                        .id(ObjectIdentifier(v))
                }
                BackButton(title: c.tr("Back", "חזרה")) { c.pauseMenu() }
                    .frame(width: 54, height: 54)
                if let e = c.engine, e.config.tutorial {
                    let volley = c.sport == .volley
                    let width: CGFloat = landscape ? (volley ? 120 : 166) : 220
                    let size: CGFloat = landscape && volley ? 12 : 14
                    HStack(spacing: 8) {
                        tutorialButton(c.tr("Previous", "הקודם"), 0xffdfedf6, bold: false, size) { c.tutorialPrevious() }
                        tutorialButton(c.tutorialLast ? c.tr("Finish", "סיום") : c.tr("Next", "הבא"), 0xffb7e6fb, bold: true, size) { c.tutorialNext() }
                    }
                    .frame(width: width, height: 44)
                    .padding(.top, landscape ? 106 : 82)
                    .padding(.horizontal, landscape ? 10 : 0)
                    .frame(maxWidth: .infinity, alignment: landscape ? .leading : .center)
                }
            }
        }
        .background(SportsPalette.color(0xffc8eaf1).ignoresSafeArea())
        .environment(\.layoutDirection, AppText.rtl ? .rightToLeft : .leftToRight)
    }

    private func tutorialButton(_ title: String, _ color: UInt32, bold: Bool, _ size: CGFloat, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: size, weight: bold ? .bold : .regular))
                .foregroundColor(SportsPalette.color(ink))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)
        }
        .buttonStyle(SportsSkyButtonStyle(color: color))
    }
}

// MARK: Home

@MainActor
struct HomePage: View {
    @ObservedObject var controller: SportsController

    var body: some View {
        let c = controller
        let _ = c.revision
        let learn = c.tr("Start & learn", "מתחילים ולומדים")
        let play = c.tr("Play", "משחקים")
        let saved = c.tr("Saved games", "משחקים שמורים")
        let advanced = c.tr("Advanced", "מתקדם")
        let points = c.points()
        let rank = ProgressRanks.at(points)
        SPage(c.appName, back: nil, moreCue: true) {
            // Android `squash_menu_clean` / `volley_menu_clean`: the whole picture across the column,
            // without a frame or cropping.
            Image(c.sport == .squash ? "squash_menu_clean" : "volley_menu_clean")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .padding(.bottom, 12)
                .accessibilityHidden(true)
            // Android FamilyMenu.organize: the tutorial and daily actions, then the avatar row, in "Start & learn".
            FamilySection(learn, color: FamilyMenuColors.learn, open: c.sectionOpen(learn, 0), toggle: { c.toggleSection(learn, 0) }) {
                FamilyButton(title: c.tr("Learn to play with Minik", "לומדים לשחק עם מיניק"), color: FamilyMenuColors.learn) { c.tutorialIntro() }
                FamilyButton(title: c.tr("Daily skill journey", "אתגר יומי"), color: FamilyMenuColors.learn) { c.journeyPage() }
                FamilyButton(title: c.tr("Your avatar & colors", "הדמות והצבעים שלכם"), color: FamilyMenuColors.learn) { c.avatars() }
                HStack(spacing: 0) {
                    Portrait(id: c.avatar, width: 70, height: 82)
                    Text(Characters.get(c.avatar).name(c.hebrew) + "  •  \(points)")
                        .font(.system(size: 18))
                        .foregroundColor(SportsPalette.color(rank.ink))
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 6)
                        .frame(width: 210, height: 52)
                        // Android FamilyFormStyle flattens this label. Its rank ink is kept: Android's
                        // FamilyMenu.readableProfile also turns the white ink of the Blue and Brown
                        // ranks dark, which leaves dark text on a dark rank colour.
                        .background(SportsFlatLabel(color: rank.color))
                }
                .frame(maxWidth: .infinity)
            }
            FamilySection(play, color: FamilyMenuColors.play, open: c.sectionOpen(play, 1), toggle: { c.toggleSection(play, 1) }) {
                FamilyButton(title: c.tr("Play", "משחק חדש"), color: FamilyMenuColors.play) { c.setup() }
                FamilyButton(title: c.tr("Tournament", "טורניר"), color: FamilyMenuColors.play) { c.tournament() }
                FamilyButton(title: c.tr("Public tournaments", "טורנירים פתוחים"), color: FamilyMenuColors.play) { c.connect("PUBLIC") }
                FamilyButton(title: c.tr("Create or join a room", "יצירה או הצטרפות לחדר"), color: FamilyMenuColors.play) { c.onlinePage() }
            }
            if c.hasSaved {
                FamilySection(saved, color: FamilyMenuColors.saved, open: c.sectionOpen(saved, 2), toggle: { c.toggleSection(saved, 2) }) {
                    FamilyButton(title: c.tr("Continue saved match", "המשך משחק שמור"), color: FamilyMenuColors.saved) { c.continueSaved() }
                }
            }
            FamilySection(advanced, color: FamilyMenuColors.advanced, open: c.sectionOpen(advanced, 3), toggle: { c.toggleSection(advanced, 3) }) {
                FamilyButton(title: c.tr("Settings", "הגדרות"), color: FamilyMenuColors.advanced) { c.settings() }
                // Android FamilyMenu.organize moves "More Minik apps & games" here as a link.
                FamilyLink(title: FamilyMessages.text("More Minik apps & games", "עוד אפליקציות ומשחקי מיניק")) { c.moreApps() }
            }
            FamilyLink(title: c.tr("Parent zone", "אזור הורים")) { c.parentGate { [weak c] in c?.parentZone() } }
        }
    }
}

// MARK: Daily skill journey

@MainActor
struct JourneyPage: View {
    @ObservedObject var controller: SportsController

    var body: some View {
        let c = controller
        let step = c.journeyStep
        let d = SportsJourney.stage(c.sport, step)
        let cycle = step / 30
        let guide = d.bot(cycle, c.sport, [c.avatar])
        SPage(c.tr("Daily skill journey", "אתגר יומי"), back: { c.home() }) {
            SLabel(text: c.tr("A little practice each day. Your first completed stage today earns a bonus. Play more whenever you like; missing a day never takes progress away.",
                              "קצת תרגול בכל יום. השלב הראשון שמסיימים היום מעניק בונוס. אפשר לשחק עוד מתי שרוצים; דילוג על יום אינו מוחק התקדמות."))
            SLabel(text: "\(step % 30 + 1) / 30  ·  " + c.tr("Cycle", "מסלול") + " \(cycle + 1)", size: 20)
            SLabel(text: c.tr(d.en, d.he), size: 26)
            Portrait(id: guide.id, width: 125, height: 142)
                .accessibilityLabel(guide.name(c.hebrew))
            SLabel(text: guide.name(c.hebrew), size: 20)
            SLabel(text: c.tr(d.role(false), d.role(true)))
            SLabel(text: c.tr(d.brief(c.sport, false), d.brief(c.sport, true)), size: 19)
            SLabel(text: c.tr("Goal", "המטרה") + ": \(d.goal(cycle))  ·  ♥ 3" + (d.streak ? "  ·  " + c.tr("In a row", "ברצף") : ""), size: 20)
            SButton(title: c.tr("Start challenge", "מתחילים באתגר"), color: 0xffffdf85) { c.startJourney(step) }
            if c.hasPracticeSaved {
                SButton(title: c.tr("Continue practice", "ממשיכים בתרגול")) { c.continuePractice() }
            }
            SButton(title: c.tr("Your journey", "המסע שלכם")) { c.journeyList() }
        }
    }
}

@MainActor
struct JourneyListPage: View {
    @ObservedObject var controller: SportsController

    var body: some View {
        let c = controller
        let completed = c.journeyCompleted
        let stages = SportsJourney.stages(c.sport)
        SPage(c.tr("Your journey", "המסע שלכם"), back: { c.journeyPage() }) {
            ForEach(stages.indices, id: \.self) { i in
                let at = completed / 30 * 30 + i
                let mark = at < completed ? "✓ " : (at == completed ? "★ " : "○ ")
                SButton(title: mark + "\(i + 1). " + c.tr(stages[i].en, stages[i].he), enabled: at <= completed) { c.journeyPage(at) }
            }
        }
    }
}

@MainActor
struct JourneyResultPage: View {
    @ObservedObject var controller: SportsController

    var body: some View {
        let c = controller
        if let r = c.journeyResultModel {
            SPage(r.title, back: { c.home() }) {
                if r.won {
                    JourneyCelebration()
                        .frame(maxWidth: .infinity)
                        .frame(height: 155)
                }
                SLabel(text: r.stage, size: 26)
                SLabel(text: r.progress, size: 34)
                SLabel(text: r.message)
                if r.earned > 0 { SLabel(text: "+\(r.earned) " + c.tr("Points", "נקודות"), size: 24) }
                SButton(title: r.won ? c.tr("Next challenge", "האתגר הבא") : c.tr("Try again", "ניסיון נוסף")) { c.journeyPage(r.won ? nil : r.step) }
                SButton(title: c.tr("Main menu", "תפריט ראשי")) { c.home() }
            }
        }
    }
}

// MARK: Play, avatars, settings

@MainActor
struct VolleyOptions: View {
    @ObservedObject var controller: SportsController

    var body: some View {
        let c = controller
        let controls = Control.allCases
        SChoose(title: c.tr("Serve control", "שליטה בהגשה"), items: controls.map { c.controlName($0) }, selected: controls.firstIndex(of: c.serveMode) ?? 0) {
            c.setServeMode(controls[$0])
        }
        SLabel(text: c.tr("Changing Control also resets Serve control. You can then choose a different serve style.", "שינוי השליטה מעדכן גם את ההגשה. לאחר מכן אפשר לבחור הגשה אחרת."), size: 14)
        SChoose(title: c.tr("Teams", "קבוצות"), items: ["2 × 2", "3 × 3"], selected: c.teamSize - 2) { c.setTeamSize($0 + 2) }
        SChoose(title: c.tr("Arena", "זירה"), items: [c.tr("Beach", "חוף"), c.tr("Park", "פארק")], selected: c.arena == "park" ? 1 : 0) {
            c.setArena($0 == 1 ? "park" : "beach")
        }
        SChoose(title: c.tr("Ball", "כדור"), items: VolleyPalette.ballIds.map { c.ballName($0) }, selected: VolleyPalette.ballIds.firstIndex(of: c.ballStyle) ?? 0) {
            c.setBallStyle(VolleyPalette.ballIds[$0])
        }
        SChoose(title: c.tr("Your team", "הקבוצה שלכם"), items: VolleyPalette.teamIds.map { c.teamName($0) }, selected: VolleyPalette.teamIds.firstIndex(of: c.ownColor) ?? 0) {
            c.setOwnColor(VolleyPalette.teamIds[$0])
        }
        let others = VolleyPalette.teamIds.filter { $0 != c.ownColor }
        SChoose(title: c.tr("Other team", "הקבוצה היריבה"), items: others.map { c.teamName($0) }, selected: max(others.firstIndex(of: c.rivalColor) ?? 0, 0)) {
            c.setRivalColor(others[$0])
        }
    }
}

@MainActor
struct SetupPage: View {
    @ObservedObject var controller: SportsController

    var body: some View {
        let c = controller
        let controls = Control.allCases
        SPage(c.tr("Play", "משחק חדש"), back: { c.home() }) {
            SLabel(text: c.sport == .squash ? c.tr("Solve it. Aim it. Own the rally.", "פותרים, מכוונים, מנצחים.")
                   : c.tr("One team. Three touches. A brilliant rally.", "קבוצה אחת. שלוש נגיעות. מהלך מנצח."))
            SChoose(title: c.tr("Control", "שליטה"), items: controls.map { c.controlName($0) }, selected: controls.firstIndex(of: c.mode) ?? 0) {
                c.setMode(controls[$0])
            }
            if c.sport == .volley {
                VolleyOptions(controller: c)
                SLabel(text: c.tr("Choose every player", "בוחרים את כל השחקנים"), size: 23, bold: true)
                ForEach(0..<(c.teamSize - 1), id: \.self) { i in
                    Carousel(controller: c, title: c.tr("Teammate", "חבר קבוצה") + " \(i + 1)", current: c.teamMates[i], compact: true) { c.setTeamMate(i, $0) }
                }
                ForEach(0..<c.teamSize, id: \.self) { i in
                    Carousel(controller: c, title: c.tr("Opponent", "יריב") + " \(i + 1)", current: c.opponents[i], compact: true) { c.setOpponentAt(i, $0) }
                }
            } else {
                Carousel(controller: c, title: c.tr("Opponent", "היריב"), current: c.opponent) { c.setOpponent($0) }
            }
            SButton(title: c.tr("Start", "התחלה"), color: 0xffb7e6fb) { c.startLocal() }
        }
    }
}

@MainActor
struct AvatarsPage: View {
    @ObservedObject var controller: SportsController

    var body: some View {
        let c = controller
        SPage(c.tr("Your avatar & colors", "הדמות והצבעים שלכם"), back: { c.home() }) {
            Carousel(controller: c, title: c.tr("Avatar", "הדמות שלכם"), current: c.avatar) { c.setAvatar($0) }
            SLabel(text: c.sport == .volley
                   ? c.tr("Earn points for good contacts and match wins. Saved matches never award the same points twice.", "צוברים נקודות על חבטות וניצחונות. משחק שמור אינו מעניק אותן נקודות פעמיים.")
                   : c.tr("Earn points for good contacts, answers and match wins. Saved matches never award the same points twice.", "צוברים נקודות על חבטות, תשובות וניצחונות. משחק שמור אינו מעניק אותן נקודות פעמיים."),
                   size: 16)
            ForEach(ProgressRanks.all, id: \.threshold) { r in
                Text(c.tr(r.en, r.he) + "  •  \(r.threshold)")
                    .font(.system(size: 18))
                    .foregroundColor(SportsPalette.color(r.ink))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(SportsFlatLabel(color: r.color))
                    .padding(.top, 7)
            }
        }
    }
}

@MainActor
struct SettingsPage: View {
    @ObservedObject var controller: SportsController

    var body: some View {
        let c = controller
        let _ = c.revision
        let controls = Control.allCases
        SPage(c.tr("Settings", "הגדרות"), back: { c.home() }) {
            SChoose(title: c.tr("Control", "שליטה"), items: controls.map { c.controlName($0) }, selected: controls.firstIndex(of: c.mode) ?? 0) {
                c.setMode(controls[$0])
            }
            SLabel(text: c.controlHelp())
            if c.sport == .squash {
                SLabel(text: c.tr("Questions & answer time", "שאלות וזמן לתשובה"), size: 22, bold: true)
                if !c.questionsEnabled { SLabel(text: c.tr("Questions are turned off in the parent zone.", "השאלות כבויות באזור ההורים.")) }
                let modes = AnswerMode.allCases
                SChoose(title: c.tr("Answer mode", "מתי עונים"),
                        items: modes.map { $0 == .serves ? c.tr("Serves only", "רק בהגשות") : c.tr("Every hit · slow motion", "בכל חבטה · הילוך איטי") },
                        selected: modes.firstIndex(of: c.answerMode) ?? 0, enabled: c.questionsEnabled) { c.setAnswerMode(modes[$0]) }
                let serves = ServeQuestions.allCases
                SChoose(title: c.tr("Serve questions", "שאלות בהגשה"), items: serves.map { q -> String in
                    switch q {
                    case .own: return c.tr("Only on my serve", "רק בהגשה שלי")
                    case .fullTime: return c.tr("Every serve · full answer time", "בכל הגשה · זמן מלא לתשובה")
                    case .untilServe: return c.tr("Every serve · until the serve", "בכל הגשה · עד ההגשה")
                    }
                }, selected: serves.firstIndex(of: c.serveQuestions) ?? 0, enabled: c.questionsEnabled) { c.setServeQuestions(serves[$0]) }
                let times = [5, 10, 15, 30]
                SChoose(title: c.tr("Time to answer", "זמן לתשובה"), items: times.map { "\($0) " + c.tr("seconds", "שניות") },
                        selected: times.firstIndex(of: c.answerSeconds) ?? 2, enabled: c.questionsEnabled) { c.setAnswerSeconds(times[$0]) }
                SLabel(text: c.tr("Correct answers earn learning points. Match points are awarded only when a rally ends in a fault. With full answer time, a server's early shot waits until everyone has had the whole window.",
                                  "תשובות נכונות מעניקות נקודות למידה. נקודות משחק מתקבלות רק כשמהלך מסתיים בעבירה. בזמן מלא לתשובה, הגשה מוקדמת ממתינה עד שלכולם ניתן כל הזמן."), size: 16)
            } else {
                VolleyOptions(controller: c)
            }
            SButton(title: c.tr("How to play", "איך משחקים")) { c.tutorialIntro() }
            SButton(title: c.tr("Rate, share & feedback", "דירוג, שיתוף ומשוב")) { c.parentGate { [weak c] in c?.openSupport() } }
            SButton(title: c.tr("Ball reception assistance ▾", "עזרה בקבלת הכדור ▾")) { c.receptionOpen.toggle() }
            if c.receptionOpen {
                SSwitch(title: c.tr("Zoom as the ball approaches me", "מיקוד המצלמה כשהכדור מתקרב אליי"), isOn: c.receptionValue("receptionZoom")) { c.setReception("receptionZoom", $0) }
                SSwitch(title: c.tr("Slow motion for my reception", "הילוך איטי בקבלת הכדור שלי"), isOn: c.receptionValue("receptionSlow")) { c.setReception("receptionSlow", $0) }
                SSwitch(title: c.tr("Follow another human's reception", "מיקוד המצלמה כששחקן אחר מקבל את הכדור"), isOn: c.receptionValue("receptionFollow")) { c.setReception("receptionFollow", $0) }
                SLabel(text: c.tr("Online, everyone shares the same slow motion. This setting controls your turns; other players choose for theirs. Bots never trigger the camera.",
                                  "ברשת כולם משחקים באותו הילוך איטי. ההגדרה קובעת לגבי התור שלכם; כל שחקן בוחר לגבי שלו. בוטים אינם מפעילים את הקירוב."), size: 16)
            }
            SSwitch(title: c.tr("Game sounds", "צלילי המשחק"), size: 18, isOn: c.soundsOn) { c.setSounds($0) }
        }
    }
}

@MainActor
struct SupportPage: View {
    @ObservedObject var controller: SportsController

    var body: some View {
        let c = controller
        SPage(c.tr("Rate, share & feedback", "דירוג, שיתוף ומשוב"), back: { c.settings() }) {
            SButton(title: c.tr("Rate this app", "דירוג האפליקציה")) { c.rateApp() }
            SButton(title: c.tr("Share this app", "שיתוף האפליקציה")) { c.shareApp() }
            SButton(title: c.tr("Send feedback", "שליחת משוב")) { c.sendFeedback() }
        }
    }
}

@MainActor
struct TutorialPage: View {
    @ObservedObject var controller: SportsController

    var body: some View {
        let c = controller
        SPage(c.tr("Learn to play with Minik", "לומדים לשחק עם מיניק"), back: { c.home() }) {
            Portrait(id: "minik", width: 140, height: 165)
            if c.sport == .squash {
                SLabel(text: c.tr("Take turns hitting the front wall before the second bounce. A miss, tin, out ball or floor-first shot gives the opponent one match point. Correct answers give separate learning points even if you lose the rally. On serve, tap your wall target; you have time to solve first. In full-time mode, answer while the other player prepares their serve. Settings also offer slow-motion questions on every return. ",
                                  "חובטים בתורכם בקיר הקדמי לפני הקפיצה השנייה. החטאה, פגיעה מתחת לקו, חוץ או רצפה לפני הקיר מעניקים ליריב נקודת משחק. תשובה נכונה נותנת נקודת למידה נפרדת גם אם הפסדתם במהלך. בהגשה מקישים על היעד בקיר ויש זמן לפתור לפני כן. בזמן מלא עונים גם כשהיריב מתכונן להגיש. בהגדרות ניתן לבחור שאלות בהילוך איטי בכל חבטה. ") + c.controlHelp(),
                       size: 18)
            } else {
                SLabel(text: c.tr("Move toward the landing ring. Receive the ball, let your teammate set, then attack an open space. Each team has at most three touches. A ball on the ground wins a point for the other side. Aim inside the lines and over the net. 2-on-2 follows beach-volleyball principles; 3-on-3 is our recreational team format.",
                                  "התקדמו לסימן הנחיתה. קבלו את הכדור, תנו לחבר הקבוצה להרים והנחיתו לשטח פנוי. לכל קבוצה עד שלוש נגיעות. כדור שפוגע בקרקע מזכה את הצד השני בנקודה. כוונו מעל הרשת ובתוך הקווים. 2 על 2 מבוסס על כדורעף חופים; 3 על 3 הוא המצב הקבוצתי שלנו."),
                       size: 18)
                SLabel(text: c.controlHelp(), size: 18)
            }
            SButton(title: c.tr("Try it with Minik", "מנסים עם מיניק")) { c.startLocal(tutorial: true) }
            SButton(title: c.tr("Practice every skill", "מתאמנים בכל המיומנויות")) { c.journeyPage(0) }
        }
    }
}

// MARK: Local cup

@MainActor
struct TournamentPage: View {
    @ObservedObject var controller: SportsController

    var body: some View {
        let c = controller
        SPage(c.tr("Tournament", "טורניר"), back: { c.leaveCupScreen() }) {
            if let cup = c.cupState {
                let round = cup.optInt("round")
                let results = ((cup["results"] as? [Any]) ?? []).map { NodeValue.text($0) }
                SLabel(text: c.tr("Your cup", "הגביע שלכם"), size: 24)
                SLabel(text: c.tr("Wins", "ניצחונות") + ": \(cup.optInt("wins"))    " + c.tr("Losses", "הפסדים") + ": \(cup.optInt("losses"))", size: 23)
                ForEach(SportsController.cupOpponents.indices, id: \.self) { i in
                    let name = Characters.get(SportsController.cupOpponents[i]).name(c.hebrew)
                    SLabel(text: "\(i + 1). \(name) • " + (i < round ? (i < results.count ? results[i] : "") : c.tr("Upcoming", "בהמשך")), size: 19)
                }
                if round < 3 {
                    SButton(title: c.tr("Play next match", "המשחק הבא")) { c.playCupMatch() }
                } else {
                    SLabel(text: c.tr("Cup complete!", "הגביע הושלם!"), size: 26)
                }
                SButton(title: c.tr("Delete tournament", "מחיקת הטורניר"), color: SportsPalette.pink, textColor: 0xffffffff, top: 24) { c.finishCup() }
            } else {
                SLabel(text: c.tr("A three-match cup against three different house players. Scores and completed fixtures are saved.", "גביע של שלושה משחקים מול שלושה שחקני בית שונים. הניקוד והמשחקים שהסתיימו נשמרים."))
                SButton(title: c.tr("Start tournament", "תחילת טורניר")) { c.startCup() }
            }
        }
    }
}

// MARK: Online

@MainActor
struct OnlinePage: View {
    @ObservedObject var controller: SportsController

    var body: some View {
        let c = controller
        SPage(c.tr("Play with friends", "משחק עם חברים"), back: { c.home() }) {
            SLabel(text: c.tr("Create a private room, share its code, and get ready together. Empty volleyball places can be filled by house players.", "צרו חדר פרטי, שתפו את הקוד והתכוננו יחד. שחקני בית יכולים למלא מקומות פנויים בכדורעף."))
            SButton(title: c.tr("Create room", "יצירת חדר")) { c.roomOptions(false) }
            SportsDashedDivider()
            SportsField(placeholder: c.tr("Room code", "קוד חדר"), text: Binding(get: { c.roomCode }, set: { value in
                c.roomCode = String(value.uppercased().prefix(6))
            }))
            SButton(title: c.tr("Join room", "הצטרפות לחדר")) { c.connect(c.roomCode.trimmingCharacters(in: .whitespaces)) }
            if let saved = c.savedRoom {
                SButton(title: c.tr("Return to room", "חזרה לחדר") + " (\(saved))") { c.connect(saved) }
            }
        }
    }
}

/// Android `roomOptions(publicCup)`: the host chooses a single match or a cup before creating the
/// room (a public tournament is always a cup); Back and Cancel return to where the host came from.
@MainActor
struct RoomOptionsPage: View {
    @ObservedObject var controller: SportsController

    var body: some View {
        let c = controller
        let publicCup = c.roomOptionsPublic
        let formats = publicCup ? [3, 5] : [1, 3, 5]
        let current = publicCup ? max(c.onlineRounds, 3) : c.onlineRounds
        SPage(publicCup ? c.tr("Create public tournament", "יצירת טורניר פתוח") : c.tr("Create room", "יצירת חדר"),
              back: { c.leaveRoomOptions() }) {
            SChoose(title: c.tr("Match format", "סוג המשחק"), items: formats.map { $0 == 1 ? c.tr("Single match", "משחק יחיד") : "\($0) " + c.tr("match cup", "משחקי גביע") },
                    selected: formats.firstIndex(of: current) ?? 0) { c.onlineRounds = formats[$0] }
            SButton(title: c.tr("Create room", "יצירת חדר")) { c.connect(nil, publicCup: publicCup) }
            SButton(title: c.tr("Cancel", "ביטול"), color: SportsPalette.pink, textColor: 0xffffffff) { c.leaveRoomOptions() }
        }
    }
}

@MainActor
struct PublicTournamentsPage: View {
    @ObservedObject var controller: SportsController

    var body: some View {
        let c = controller
        SPage(c.tr("Public tournaments", "טורנירים פתוחים"), back: { c.home() }) {
            SLabel(text: c.tr("Public listings show room codes and free places only. There is no chat.", "ברשימה הציבורית מופיעים רק קודי חדרים ומקומות פנויים. אין צ׳אט."))
            SButton(title: c.tr("Create public tournament", "יצירת טורניר פתוח")) { c.roomOptions(true) }
            if c.publicEntries.isEmpty {
                SLabel(text: c.tr("No open tournaments yet. You can create one.", "אין עדיין טורנירים פתוחים. אפשר ליצור טורניר."))
            }
            ForEach(c.publicEntries, id: \.code) { entry in
                SButton(title: "\(entry.code)  ·  \(entry.count)  ·  \(entry.rounds) " + c.tr("match cup", "משחקי גביע")) { c.connect(entry.code) }
            }
        }
    }
}

@MainActor
struct LobbyPage: View {
    @ObservedObject var controller: SportsController

    var body: some View {
        let c = controller
        SPage(c.tr("Friends room", "חדר חברים"), back: { c.leaveCupScreen() }) {
            if let l = c.lobbyModel {
                let alone = l.members.count == 1
                SLabel(text: l.code, size: 32)
                SButton(title: c.tr("Copy code", "העתקת קוד")) { c.copyCode(l.code) }
                ForEach(l.members, id: \.id) { m in
                    let name = m.id == l.uid ? c.tr("You", "אתם") : Characters.get(m.character).name(c.hebrew)
                    let ready = l.ready.contains(m.id) ? c.tr("Ready", "מוכן") : c.tr("Getting ready", "מתכוננים")
                    // Android: a host alone in the room has "Not started" (house players fill the rest).
                    SLabel(text: name + " • " + (alone ? c.tr("Not started", "טרם התחיל") : ready), size: 20)
                }
                if !alone {
                    SButton(title: c.tr("Ready", "מוכנים")) { c.lobbyReady() }
                }
                if l.host { SButton(title: c.tr("Start", "התחלה")) { c.lobbyStart() } }
            }
        }
    }
}

// MARK: Results

@MainActor
struct ResultPage: View {
    @ObservedObject var controller: SportsController

    var body: some View {
        let c = controller
        let _ = c.revision
        if let e = c.resultWorld {
            let id = c.resultId
            let won = e.winner == e.player(id)?.member.team
            SPage(c.tr("Match result", "תוצאת המשחק"), back: { c.home() }) {
                if c.sport == .squash {
                    let winnerName = e.players.first { $0.member.team == e.winner }?.character.name(c.hebrew) ?? ""
                    SLabel(text: won ? c.tr("You win!", "ניצחתם!") : c.tr("Winner", "המנצח") + ": " + winnerName, size: 26)
                } else {
                    SLabel(text: won ? c.tr("Your side wins!", "הצד שלכם ניצח!") : c.tr("A great match!", "משחק נהדר!"), size: 26)
                }
                SLabel(text: "\(e.scores[0]) : \(e.scores[1])", size: 40)
                    .environment(\.layoutDirection, .leftToRight)
                if c.sport == .squash {
                    HStack(spacing: 12) {
                        ForEach(e.players.indices, id: \.self) { index in
                            let p = e.players[index]
                            VStack(spacing: 0) {
                                Portrait(id: p.member.character, width: 62, height: 70)
                                SLabel(text: (p.member.id == id ? c.tr("You", "אתם") + " · " : "") + p.character.name(c.hebrew), size: 18, bold: true)
                                SLabel(text: c.tr("Match points", "נקודות משחק") + "\n\(e.scores[p.member.team])", size: 18)
                                SLabel(text: c.tr("Learning points", "נקודות למידה") + "\n\(p.correct)")
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 14)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .background(SportsSkySurface(color: p.member.id == id ? 0xffd4effa : 0xfff8e0ec))
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .environment(\.layoutDirection, .leftToRight)
                    .padding(.vertical, 18)
                } else {
                    ForEach(0..<2, id: \.self) { t in
                        let colorId = e.config.teamColors[t]
                        Text(c.teamName(colorId) + " · \(e.scores[t])")
                            .font(.system(size: 22))
                            .foregroundColor(SportsPalette.color(colorId == "berry" ? 0xffffffff : ink))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .background(SportsFlatLabel(color: VolleyPalette.color(colorId)))
                            .padding(.top, 24)
                            .padding(.bottom, 12)
                        ForEach(e.players.filter { $0.member.team == t }, id: \.member.id) { p in
                            SLabel(text: (p.member.id == id ? c.tr("You", "אתם") : p.character.name(c.hebrew)) + " • \(p.contacts) " + c.tr("Successful returns", "החזרות מוצלחות"), size: 18)
                        }
                    }
                }
                Color.clear.frame(height: 20)
                if c.cupState != nil && c.playingCup {
                    SButton(title: c.tr("Tournament table", "טבלת הטורניר")) { c.tournament() }
                }
                if let link = c.online, link.totalRounds > 1 {
                    SLabel(text: c.tr("Cup score", "ניקוד הגביע") + "  \(link.cupWins(0)) : \(link.cupWins(1))", size: 23)
                    if link.round < link.totalRounds {
                        if link.authority {
                            SButton(title: c.tr("Play next match", "המשחק הבא")) { link.nextRound() }
                        } else {
                            SLabel(text: c.tr("Waiting for the host to start the next match.", "ממתינים ליוצר החדר שיתחיל את המשחק הבא."))
                        }
                    }
                } else if c.online == nil {
                    SButton(title: c.tr("Play again", "משחק נוסף")) { c.startLocal() }
                }
                SButton(title: c.tr("Main menu", "תפריט ראשי"), color: 0x00000000, textColor: SportsPalette.pink) { c.home() }
            }
        }
    }
}

// MARK: Parent zone

@MainActor
struct ParentZonePage: View {
    @ObservedObject var controller: SportsController

    var body: some View {
        let c = controller
        let _ = c.revision
        SPage(c.tr("Parent zone", "אזור הורים"), back: { c.home() }) {
            SButton(title: c.tr("Privacy policy", "מדיניות פרטיות")) { c.privacyPage() }
            if c.sport == .squash {
                SSwitch(title: c.tr("Play without questions", "משחק בלי שאלות"), size: 18, isOn: !c.questionsEnabled) { c.setPlayWithoutQuestions($0) }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 18)
                SLabel(text: c.tr("Only a grown-up can change this. Question settings are disabled while this switch is on.", "רק מבוגר יכול לשנות זאת. הגדרות השאלות מושבתות כשהאפשרות פעילה."), size: 16)
                SLabel(text: c.tr("My learning progress", "ההתקדמות שלי בלמידה"), size: 23)
                let profile = c.learningProfile()
                ForEach(Skill.allCases.filter { $0 != .english && $0 != .world }, id: \.self) { skill in
                    let value = profile.state(skill)
                    SLabel(text: skillTitle(skill) + "  •  \(value.independent) ✓  /  \(value.wrong) ↻")
                }
            }
            // Android's ads note and remove-ads purchases are not part of the iOS app.
        }
    }

    private func skillTitle(_ skill: Skill) -> String {
        let c = controller
        switch skill {
        case .add: return c.tr("Addition", "חיבור")
        case .subtract: return c.tr("Subtraction", "חיסור")
        case .multiply: return c.tr("Multiplication", "כפל")
        case .divide: return c.tr("Division", "חילוק")
        case .order: return c.tr("Order of operations", "סדר פעולות")
        default: return c.tr("Fractions", "שברים")
        }
    }
}

/// Android `privacyPage()`: the bundled policy in the device language (JavaScript off).
@MainActor
struct PrivacyWeb: UIViewRepresentable {
    let language: String

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.isOpaque = false
        web.backgroundColor = SportsPalette.ui(SportsPalette.page)
        if let url = Bundle.main.url(forResource: "privacy-" + language, withExtension: "html")
            ?? Bundle.main.url(forResource: "privacy-en", withExtension: "html") {
            web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

@MainActor
struct PrivacyPage: View {
    @ObservedObject var controller: SportsController

    var body: some View {
        let c = controller
        VStack(spacing: 0) {
            ZStack(alignment: .leading) {
                Text(c.tr("Privacy policy", "מדיניות פרטיות"))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(SportsPalette.color(ink))
                    .frame(maxWidth: .infinity, minHeight: 64)
                BackButton(title: c.tr("Back", "חזרה")) { c.parentZone() }
            }
            GeometryReader { geo in
                PrivacyWeb(language: AppText.language)
                    .frame(maxWidth: SportsSky.textColumn(geo))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(SportsPalette.color(SportsPalette.page).ignoresSafeArea())
        .environment(\.layoutDirection, AppText.rtl ? .rightToLeft : .leftToRight)
    }
}
