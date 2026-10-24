import SwiftUI
import UIKit

/// SwiftUI versions of the Android SplashActivity pages (LinearLayout columns in a ScrollView
/// over the lagoon art). Sizes are Android sp/dp as points.
private func tr(_ en: String, _ he: String) -> String { return AppText.t(en, he) }

@MainActor
struct SplashLabel: View {
    let text: String
    var size: CGFloat = 18
    var color: UInt32 = 0xffffffff
    /// Android `gravity = START` (the AI note); every other label is centred.
    var leading = false

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .bold))
            .foregroundColor(SplashPalette.color(color))
            .multilineTextAlignment(leading ? .leading : .center)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: leading ? .leading : .center)
    }
}

/// Android `button(text, color)`: 54 high, bold dark text on the raised sky face (`FamilySkyDrawable`);
/// "Back" is always pink with white text. `top` / `bottom` are the margins (5; room actions use 16 / 8).
@MainActor
struct SplashButton: View {
    let title: String
    var color: UInt32 = 0xffb4f6e7
    var height: CGFloat = 54
    var top: CGFloat = 5
    var bottom: CGFloat = 5
    /// Android `isEnabled` (the house-player Start): disabled lettering is grey 0xff727980.
    var enabled = true
    let action: () -> Void

    var body: some View {
        let back = title == tr("Back", "חזרה")
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(back ? .white : SplashPalette.color(enabled ? 0xff0b2b42 : 0xff727980))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
                .contentShape(Rectangle())
        }
        .buttonStyle(SkyButtonStyle(color: back ? 0xffe91e63 : color, radius: 18, shadow: true))
        .disabled(!enabled)
        .padding(.top, top)
        .padding(.bottom, bottom)
    }
}

/// Android `back(col, action)`: an 18-point space, then the pink Back button.
@MainActor
struct SplashBack: View {
    var top: CGFloat = 5
    var bottom: CGFloat = 5
    let action: () -> Void

    var body: some View {
        Color.clear.frame(height: 18)
        SplashButton(title: tr("Back", "חזרה"), color: 0xffe91e63, top: top, bottom: bottom, action: action)
    }
}

/// Android `page(title)`: dark blue, the lagoon at 43% opacity, a scrolling padded column, centred
/// and narrower in a landscape window (`FamilyReadingPanel`). The home page adds the reserved
/// "More below" cue of its menu sections (`FamilyMoreFrame`).
@MainActor
struct SplashPage<Content: View>: View {
    let title: String
    let moreCue: Bool
    let content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var moreBelow = false
    @State private var scroll = SplashScrollState()

    init(_ title: String, moreCue: Bool = false, @ViewBuilder content: () -> Content) {
        self.title = title
        self.moreCue = moreCue
        self.content = content()
    }

    var body: some View {
        ZStack {
            SplashPalette.color(0xff0b2941)
            GeometryReader { geo in
                if let lagoon = ArtStore.shared.lagoon {
                    Image(uiImage: lagoon)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .opacity(0.43)
                }
            }
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    GeometryReader { geo in
                        ScrollView {
                            VStack(spacing: 0) {
                                SplashLabel(text: title, size: 28)
                                content
                            }
                            .padding(.horizontal, 22)
                            .padding(.top, 10)
                            .padding(.bottom, 24)
                            .frame(width: SplashPageLayout.readingWidth(geo.size))
                            .frame(maxWidth: .infinity)
                            .id(SplashPageLayout.contentID)
                            .background {
                                if moreCue {
                                    SplashFrameProbe { rect in
                                        scroll.content = rect
                                        measured()
                                    }
                                }
                            }
                        }
                        .background {
                            if moreCue {
                                SplashFrameProbe { rect in
                                    scroll.viewport = rect
                                    measured()
                                }
                            }
                        }
                    }
                    if moreCue {
                        SplashMoreCue(visible: moreBelow) { scrollFurther(proxy) }
                    }
                }
            }
        }
        .environment(\.layoutDirection, AppText.rtl ? .rightToLeft : .leftToRight)
    }

    /// Android `canScrollVertically(1)`.
    private func measured() {
        let below = scroll.viewport.height > 0 && scroll.content.maxY > scroll.viewport.maxY + 1
        if below != moreBelow { moreBelow = below }
    }

    /// Android `smoothScrollBy(0, 65% of the height)`: the content's anchor at `offset / travel`
    /// lands at the same point of the visible area.
    private func scrollFurther(_ proxy: ScrollViewProxy) {
        let viewport = scroll.viewport
        let content = scroll.content
        let travel = content.height - viewport.height
        if travel <= 1 { return }
        let target = min(travel, max(0, viewport.minY - content.minY + viewport.height * 0.65))
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
            proxy.scrollTo(SplashPageLayout.contentID, anchor: UnitPoint(x: 0.5, y: target / travel))
        }
    }
}

/// Android Spinner with the "▾" marker at the end.
@MainActor
struct SplashDropdown: View {
    let title: String
    let items: [String]
    let selected: Int
    let change: (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            SplashLabel(text: title, size: 17, color: 0xffb4f6e7, leading: true)
            Menu {
                ForEach(Array(items.enumerated()), id: \.offset) { pair in
                    Button(pair.element) { change(pair.offset) }
                }
            } label: {
                // Android START gravity, with the Spinner's relative padding (12 start, 44 end). Android binds the
                // selected text and the marker to the Spinner's raised face one by one (`FamilyButtonAlignment.bind(view,
                // spinner)`), so each is centred on that face by its own ink; both measure against the whole field.
                Text(selected >= 0 && selected < items.count ? items[selected] : "")
                    .font(.system(size: 17))
                    .foregroundColor(SplashPalette.color(0xff10263c))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 12)
                    .padding(.trailing, 44)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .modifier(FamilyKit.RaisedLettering(cornerRadius: 18))
                    .overlay(alignment: .trailing) {
                        Text("▾")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(SplashPalette.color(0xff10263c))
                            .frame(width: 36)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                            .modifier(FamilyKit.RaisedLettering(cornerRadius: 18))
                    }
                    .background(SkySurface(color: 0xffcaeaff, radius: 18))
            }
            .padding(.bottom, 12)
        }
    }
}

/// Android `FamilyMenu` colours: each home section and its buttons share one colour.
enum MenuColors {
    static let learn: UInt32 = 0xffb8d9ff
    static let play: UInt32 = 0xffb9f4dc
    static let saved: UInt32 = 0xffe8dcff
    static let advanced: UInt32 = 0xffffe082
    static let link: UInt32 = 0xff2869bd
    static let ink: UInt32 = 0xff282d4e

    /// Android `FamilyMenu.readableProfile`: light profile text turns ink on the pale section panel.
    static func readable(_ color: UInt32) -> UInt32 {
        let r = Int((color >> 16) & 0xff)
        let g = Int((color >> 8) & 0xff)
        let b = Int(color & 0xff)
        return (r * 299 + g * 587 + b * 114) / 1000 > 170 ? ink : color
    }
}

/// Android `FamilyMenu.section`: a raised pale panel (`FamilySkyDrawable(true)`) with a 2-point border in
/// the section colour, an ink title and a − / + sign that opens and closes it.
@MainActor
struct MenuSection<Content: View>: View {
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
                        .foregroundColor(SplashPalette.color(MenuColors.ink))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(open ? "−" : "+")
                        .font(.system(size: 26))
                        .foregroundColor(SplashPalette.color(MenuColors.ink))
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
                VStack(spacing: 0) {
                    content
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(SkySurface(color: color, radius: 18, panel: true, strokeWidth: 2, strokeColor: color))
        .padding(.bottom, 14)
    }
}

/// Android `FamilyMenu.style`: a section's button, raised in the section colour, with dark ink and 15 dp corners.
@MainActor
struct SectionButton: View {
    let title: String
    let color: UInt32
    let action: () -> Void

    init(_ title: String, color: UInt32, action: @escaping () -> Void) {
        self.title = title
        self.color = color
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(SplashPalette.color(MenuColors.ink))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 54)
                .contentShape(Rectangle())
        }
        .buttonStyle(SkyButtonStyle(color: color, radius: 15))
        .padding(.top, 4)
        .padding(.bottom, 8)
    }
}

/// Android `FamilyMenu.link`: the quiet underlined footer link (Parent zone).
@MainActor
struct FamilyLink: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .underline()
                .foregroundColor(SplashPalette.color(MenuColors.link))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(RoundedRectangle(cornerRadius: 8).fill(SplashPalette.color(0xeef7fbff)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Android `Switch` on the support page (white text, 52 high).
@MainActor
struct SplashSwitch: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title)
                .font(.system(size: 16))
                .foregroundColor(.white)
        }
        .frame(minHeight: 52)
    }
}

/// Android `Intent.createChooser` for text: the system share sheet.
struct ActivityView: UIViewControllerRepresentable {
    let text: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        return UIActivityViewController(activityItems: [text], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// MARK: Root

struct SplashRootView: View {
    @StateObject private var controller = SplashController()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            SplashPalette.color(SplashPalette.sky).ignoresSafeArea()
            content
            if controller.pausePresented {
                PauseDialog(controller: controller)
            }
            if controller.cupExitPresented {
                CupExitDialog(controller: controller)
            }
            // Under the toasts: a wrong grown-up answer for a card link shows its toast above the card.
            FamilyOverlay()
            ToastOverlay(controller: controller)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            // App Store captures only: opens the requested screen (SplashScreenshot).
            controller.applyStoreScreenshotScene()
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            controller.scenePhaseChanged(active: phase == .active)
        }
        .alert(tr("For a grown-up", "למבוגר אחראי"), isPresented: gateBinding) {
            TextField("", text: $controller.gateAnswer)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
            if let model = controller.gate {
                Button(tr("Continue", "המשך")) { controller.confirmGate(model) }
            }
            Button(tr("Cancel", "ביטול"), role: .cancel) { controller.cancelGate() }
        } message: {
            if let model = controller.gate {
                Text("\u{2066}\(model.a) × \(model.b) = ?\u{2069}")
            }
        }
    }

    @MainActor private var gateBinding: Binding<Bool> {
        Binding(get: { controller.gate != nil }, set: { shown in
            if !shown { controller.gate = nil }
        })
    }

    @MainActor @ViewBuilder private var content: some View {
        switch controller.screen {
        case .game:
            if let arena = controller.gameView {
                ArenaHost(arena: arena)
                    .id(ObjectIdentifier(arena))
                    .defersSystemGestures(on: .all)
            }
        case .home: HomePage(controller: controller)
        case .settings: SettingsPage(controller: controller)
        case .subjects: SubjectsPage(controller: controller)
        case .support: SupportPage(controller: controller)
        case .parentZone: ParentZonePage(controller: controller)
        case .progress: ProgressPage(controller: controller)
        case .ranks: RanksPage(controller: controller)
        case .play: PlayPage(controller: controller)
        case .wallOptions: WallOptionsPage(controller: controller)
        case .journey: JourneyPage(controller: controller)
        case .journeyResult: JourneyResultPage(controller: controller)
        case .join: JoinPage(controller: controller)
        case .house: HousePage(controller: controller)
        case .lobby: LobbyPage(controller: controller)
        case .results: ResultsPage(controller: controller)
        }
    }
}

@MainActor
struct ArenaHost: UIViewRepresentable {
    let arena: SplashArenaView

    func makeUIView(context: Context) -> SplashArenaView { return arena }
    func updateUIView(_ uiView: SplashArenaView, context: Context) {}
}

@MainActor
struct ToastOverlay: View {
    @ObservedObject var controller: SplashController

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
                        try? await Task.sleep(nanoseconds: toast.long ? 3_500_000_000 : 2_000_000_000)
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

/// Android `pauseMenu()`: a GameDialogBuilder list (Continue / Return to menu) on the white sky dialog
/// panel (`FamilySkyUi.dialog`, 24 dp corners); cancelling continues.
@MainActor
struct PauseDialog: View {
    @ObservedObject var controller: SplashController

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { controller.continueFromPause() }
            VStack(alignment: .leading, spacing: 0) {
                Text(tr("Battle paused", "הקרב מושהה"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(SplashPalette.color(0xff17384d))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 8)
                item(tr("Continue", "להמשיך")) { controller.continueFromPause() }
                item(tr("Return to menu", "חזרה לתפריט")) { controller.returnFromPause() }
            }
            .padding(16)
            .background(SkySurface(color: 0xffffffff, radius: 24, panel: true))
            .padding(.horizontal, 22)
        }
        .environment(\.layoutDirection, AppText.rtl ? .rightToLeft : .leftToRight)
    }

    private func item(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17))
                .foregroundColor(SplashPalette.color(0xff17384d))
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: Home

@MainActor
struct HomePage: View {
    @ObservedObject var controller: SplashController

    var body: some View {
        let c = controller
        let learn = tr("Learn & progress", "לומדים ומתקדמים")
        let play = tr("Play", "משחקים")
        let saved = tr("Saved games", "משחקים שמורים")
        let advanced = tr("Advanced", "מתקדם")
        let room = c.savedRoom
        SplashPage("MINIK SPLASH", moreCue: true) {
            if let logo = ArtStore.shared.logo {
                Image(uiImage: logo)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 96)
                    .frame(maxWidth: .infinity)
            }
            SplashLabel(text: tr("Questions and answers were created with AI. AI can make mistakes.", "השאלות והתשובות נוצרו בעזרת בינה מלאכותית, שעלולה לטעות."),
                        size: 14, leading: true)
            // Android FamilyMenu.organize: the learning actions and colour ranks, then the avatar.
            MenuSection(learn, color: MenuColors.learn, open: c.sectionOpen(learn, 0), toggle: { c.toggleSection(learn, 0) }) {
                SectionButton(SplashLaunch.proEdition ? tr("Learn to play with Mia", "ללמוד לשחק עם מיה") : tr("Learn to play with Minik", "ללמוד לשחק עם מיניק"),
                              color: MenuColors.learn) { c.startGame(true) }
                SectionButton(tr("Daily paint journey", "אתגר יומי"), color: MenuColors.learn) { c.challengePage() }
                SectionButton(tr("Your colour ranks", "דרגות הצבע שלכם"), color: MenuColors.learn) { c.openRanks() }
                SplashLabel(text: tr("Your avatar", "הדמות שלכם"), size: 18, color: MenuColors.readable(0xff9cfff1))
                AvatarPicker(controller: c)
            }
            MenuSection(play, color: MenuColors.play, open: c.sectionOpen(play, 1), toggle: { c.toggleSection(play, 1) }) {
                SectionButton(tr("Play", "לשחק"), color: MenuColors.play) { c.playMenu() }
            }
            // Saved games appear only when there is something to continue.
            if c.hasSavedBattle || c.hasSavedCup || room != nil {
                MenuSection(saved, color: MenuColors.saved, open: c.sectionOpen(saved, 2), toggle: { c.toggleSection(saved, 2) }) {
                    if c.hasSavedBattle {
                        SectionButton(tr("Continue your battle", "להמשיך בקרב"), color: MenuColors.saved) { c.continueBattle() }
                    } else if c.hasSavedCup {
                        SectionButton(tr("Continue your cup", "להמשיך בגביע"), color: MenuColors.saved) { c.continueCup() }
                    }
                    if let code = room {
                        SectionButton(tr("Resume online room", "חזרה לחדר מקוון"), color: MenuColors.saved) { c.returnToRoom(code) }
                    }
                }
            }
            MenuSection(advanced, color: MenuColors.advanced, open: c.sectionOpen(advanced, 3), toggle: { c.toggleSection(advanced, 3) }) {
                SectionButton(tr("Settings", "הגדרות"), color: MenuColors.advanced) { c.openSettings() }
                SectionButton(tr("Subjects", "נושאים"), color: MenuColors.advanced) { c.openSubjects() }
                SectionButton(tr("Parent zone", "אזור הורים"), color: MenuColors.advanced) {
                    c.requestParentGate { [weak c] in c?.openParentZone() }
                }
            }
            // Android FamilyMenu.link: two quiet links under the sections.
            FamilyLink(title: tr("Share, rate or send feedback", "שיתוף, דירוג ומשוב")) {
                c.requestParentGate { [weak c] in c?.openSupport() }
            }
            .padding(.vertical, 5)
            FamilyLink(title: FamilyMessages.text("More Minik apps & games", "עוד אפליקציות ומשחקי מיניק")) { c.moreApps() }
                .padding(.vertical, 5)
        }
    }
}

private struct ChevronShape: Shape {
    let right: Bool

    func path(in rect: CGRect) -> Path {
        let sign: CGFloat = right ? 1 : -1
        let cx = rect.midX
        let cy = rect.midY
        var outline = Path()
        outline.move(to: CGPoint(x: cx - sign * 10, y: cy - 19))
        outline.addLine(to: CGPoint(x: cx + sign * 10, y: cy))
        outline.addLine(to: CGPoint(x: cx - sign * 10, y: cy + 19))
        return outline
    }
}

/// Android `AvatarArrow`: a thick rounded teal chevron with a darker shadow 2 points below and a thin
/// light highlight 1 point above, in a 64x72 touch target.
@MainActor
struct AvatarArrow: View {
    let right: Bool
    let action: () -> Void

    var body: some View {
        let thick = StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)
        Button(action: action) {
            ZStack {
                ChevronShape(right: right)
                    .stroke(SplashPalette.color(0xff1d6d64), style: thick)
                    .offset(y: 2)
                ChevronShape(right: right)
                    .stroke(SplashPalette.color(0xff3ab5a0), style: thick)
                ChevronShape(right: right)
                    .stroke(SplashPalette.color(0xffb1eddb), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                    .offset(y: -1)
            }
            .frame(width: 64, height: 72)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppText.t(right ? "Next avatar" : "Previous avatar"))
    }
}

/// Android `avatarPicker`: arrows (always left to right), the normalised portrait (swipe to change)
/// and the name in the colour of the player's rank (ink when that colour is too light for the panel).
@MainActor
struct AvatarPicker: View {
    @ObservedObject var controller: SplashController
    @State private var offset: CGFloat = 0
    @State private var fade: Double = 1
    @State private var token = 0

    var body: some View {
        let name = Characters.get(controller.selected).name(controller.hebrew)
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                AvatarArrow(right: false) { shift(-1) }
                    .padding(.leading, 6)
                    .padding(.trailing, 10)
                Group {
                    if let portrait = ArtStore.shared.portrait(controller.selected) {
                        Image(uiImage: portrait)
                            .resizable()
                            .scaledToFit()
                    } else {
                        Color.clear
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 144)
                .offset(x: offset)
                .opacity(fade)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 10).onEnded { value in
                    let dx = value.translation.width
                    let dy = value.translation.height
                    if abs(dx) > 35 && abs(dx) > abs(dy) { shift(dx < 0 ? 1 : -1) }
                })
                .accessibilityElement()
                .accessibilityLabel(name)
                AvatarArrow(right: true) { shift(1) }
                    .padding(.leading, 10)
                    .padding(.trailing, 6)
            }
            .environment(\.layoutDirection, .leftToRight)
            Text(name)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(SplashPalette.color(MenuColors.readable(SplashRanks.at(controller.rankPoints()).color)))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
                .frame(maxWidth: .infinity)
            SplashLabel(text: abilities, size: 14, color: MenuColors.readable(0xffffe5a4))
                .padding(.bottom, 14)
        }
    }

    /// Android: "Speed 3/5  ·  Precision 4/5" over "Reflexes 3/5  ·  Power 5/5".
    private var abilities: String {
        let q = Characters.get(controller.selected).qualities
        let ratings = [(tr("Speed", "מהירות"), q.speed), (tr("Precision", "דיוק"), q.precision),
                       (tr("Reflexes", "זריזות תגובה"), q.reflexes), (tr("Power", "עוצמה"), q.power)]
        return stride(from: 0, to: ratings.count, by: 2).map { start in
            ratings[start..<min(start + 2, ratings.count)].map { "\($0.0) \($0.1)/5" }.joined(separator: "  ·  ")
        }.joined(separator: "\n")
    }

    /// Android: slide 28 dp out at 25% opacity (90 ms), switch, then slide back in (130 ms).
    /// A new shift cancels the previous one before it switches, as Android's animator does.
    private func shift(_ delta: Int) {
        token += 1
        let mine = token
        offset = 0
        withAnimation(.linear(duration: 0.09)) {
            offset = CGFloat(-28 * delta)
            fade = 0.25
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 90_000_000)
            guard mine == token else { return }
            controller.shiftCharacter(delta)
            offset = CGFloat(28 * delta)
            withAnimation(.linear(duration: 0.13)) {
                offset = 0
                fade = 1
            }
        }
    }
}

// MARK: Settings

@MainActor
struct SettingsPage: View {
    @ObservedObject var controller: SplashController

    var body: some View {
        let c = controller
        let s = c.settings
        SplashPage(tr("Settings", "הגדרות")) {
            SplashLabel(text: tr("Choose what feels right. Your choices are saved.", "בחרו מה מתאים לכם. הבחירות נשמרות."), size: 16)
            SplashDropdown(title: tr("Difficulty", "רמת קושי"),
                           items: [tr("Easy · time to learn", "קלה · זמן ללמוד"), tr("Standard", "רגילה"), tr("Pro", "מקצועית")],
                           selected: s.difficulty.ordinal) { c.setDifficulty($0) }
            SplashDropdown(title: tr("Walking", "הליכה"),
                           items: [tr("Easy · tap a balloon to walk and collect", "קלה · געו בבלון להליכה ולאיסוף"),
                                   tr("Standard · move, then tap to collect", "רגילה · התקרבו ואז געו לאיסוף")],
                           selected: s.walk.ordinal) { c.setWalk($0) }
            SplashDropdown(title: tr("Throwing", "זריקה"),
                           items: [tr("Standard · tap anywhere to throw", "רגילה · געו בכל מקום כדי לזרוק"),
                                   tr("Hard · aim the arc; swipe for power", "קשה · כוונו בקשת; החליקו לעוצמה")],
                           selected: s.throwing.ordinal) { c.setThrowing($0) }
            SplashDropdown(title: tr("Answer balloons", "בלוני תשובות"),
                           items: [tr("One place", "במקום אחד"), tr("All over", "בכל הזירה")],
                           selected: s.balloons.ordinal) { c.setBalloons($0) }
            SplashSwitch(title: tr("Game sounds", "צלילי המשחק"), isOn: $controller.gameSounds)
            Color.clear.frame(height: 18)
            SplashBack { c.home() }
        }
    }
}

/// Android `subjectsPage()`: the available subjects (with the instruction), then the chosen ones; tap a
/// subject or drag it between the lists, keeping at least one.
@MainActor
struct SubjectsPage: View {
    @ObservedObject var controller: SplashController

    private func title(_ t: Topic) -> String {
        switch t {
        case .math: return tr("Math", "חשבון")
        case .english: return tr("English", "אנגלית")
        case .world, .mixed: return tr("World knowledge", "ידע כללי")
        }
    }

    var body: some View {
        SplashPage(tr("Subjects", "נושאים")) {
            subjectList(chosen: false)
            subjectList(chosen: true)
            Color.clear.frame(height: 18)
            SplashBack { controller.home() }
        }
    }

    private func subjectList(chosen: Bool) -> some View {
        let topics = Topic.allCases.filter { $0 != .mixed && controller.settings.subjects.contains($0) == chosen }
        return VStack(spacing: 0) {
            SplashLabel(text: chosen ? tr("Chosen subjects", "נושאים שנבחרו") : tr("Available subjects", "נושאים זמינים"), size: 17)
            if !chosen {
                SplashLabel(text: tr("Tap a subject or drag it between lists. Keep at least one.", "געו בנושא או גררו בין הרשימות. יש להשאיר לפחות נושא אחד."),
                            size: 14, leading: true)
                    .padding(.top, 8)
                    .padding(.bottom, 9)
            }
            ForEach(topics, id: \.self) { t in
                SplashButton(title: title(t), color: chosen ? 0xffb4f6e7 : 0xffd6e8ff) { controller.tapSubject(t, chosen: chosen) }
                    .padding(.horizontal, 6)
                    .draggable(t.rawValue)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(SkySurface(color: chosen ? 0xff214f60 : 0xff233e59, radius: 18))
        .dropDestination(for: String.self) { items, _ in
            for raw in items {
                if let topic = Topic(rawValue: raw) { controller.dropSubject(topic, intoChosen: chosen) }
            }
            return true
        }
        .padding(.bottom, 14)
    }
}

/// Android `supportPage()` (behind the parent gate).
@MainActor
struct SupportPage: View {
    @ObservedObject var controller: SplashController

    var body: some View {
        let c = controller
        SplashPage(tr("Share, rate or send feedback", "שיתוף, דירוג ומשוב")) {
            SplashLabel(text: tr("Enjoying the game? Your feedback helps shape the next update.", "נהנים מהמשחק? המשוב שלכם עוזר לשפר את העדכון הבא."),
                        size: 18, leading: true)
            Color.clear.frame(height: 18)
            SplashButton(title: tr("Rate the app", "דירוג האפליקציה"), color: 0xffd1c4ff) { c.rateApp() }
            SplashButton(title: tr("Share the game", "שיתוף המשחק"), color: 0xffafdbff) { c.openShare() }
            SplashButton(title: tr("Send feedback", "שליחת משוב"), color: 0xffffe082) { c.openFeedback() }
            Color.clear.frame(height: 18)
            SplashBack { c.home() }
        }
        .alert(tr("Your message", "ההודעה שלכם"), isPresented: $controller.shareVisible) {
            TextField("", text: $controller.shareInput, axis: .vertical)
            Button(tr("Choose an app", "בחירת אפליקציה")) { c.shareMessage() }
            Button(tr("Cancel", "ביטול"), role: .cancel) {}
        }
        .alert(tr("Your feedback", "המשוב שלכם"), isPresented: $controller.feedbackVisible) {
            TextField(tr("What went well? What should we improve?", "מה היה טוב? מה כדאי לשפר?"), text: $controller.feedbackInput, axis: .vertical)
            Button(tr("Choose an app", "בחירת אפליקציה")) { c.sendFeedback() }
            Button(tr("Cancel", "ביטול"), role: .cancel) {}
        }
        .sheet(item: $controller.shareSheet) { item in
            ActivityView(text: item.text)
        }
    }
}

// MARK: Parent zone, progress and ranks

@MainActor
struct ParentZonePage: View {
    @ObservedObject var controller: SplashController

    var body: some View {
        SplashPage(tr("Parent zone", "אזור הורים")) {
            SplashLabel(text: tr("Learning and purchases, in one place.", "למידה ורכישות, במקום אחד."), size: 17)
            Color.clear.frame(height: 18)
            SplashButton(title: tr("My learning progress", "התקדמות בלמידה")) { controller.openProgress() }
            // "Ads & purchases" (remove ads, restore, codes) is not offered on iOS.
            Color.clear.frame(height: 18)
            SplashButton(title: tr("Back", "חזרה")) { controller.home() }
        }
    }
}

@MainActor
struct ProgressPage: View {
    @ObservedObject var controller: SplashController

    var body: some View {
        let profile = controller.learningProfile()
        let names = controller.hebrew
            ? ["חיבור", "חיסור", "כפל", "חילוק", "סדר פעולות", "שברים", "אנגלית", "ידע כללי"]
            : ["Addition", "Subtraction", "Multiplication", "Division", "Order of operations", "Fractions", "English", "World"]
        SplashPage(tr("Growing skills", "מיומנויות מתפתחות")) {
            ForEach(Skill.allCases, id: \.self) { skill in
                let s = profile.state(skill)
                let first = AppText.t(names[skill.ordinal]) + " · \(s.level + 1)\n"
                let second = tr("Independent: \(s.independent) · With help: \(s.assisted)", "עצמאיות: \(s.independent) · עם עזרה: \(s.assisted)")
                SplashLabel(text: first + second, size: 15)
            }
            SplashButton(title: tr("Back", "חזרה")) { controller.openParentZone() }
        }
    }
}

/// Android `ranksPage()`: the total and every colour rank with its threshold.
@MainActor
struct RanksPage: View {
    @ObservedObject var controller: SplashController

    var body: some View {
        let total = controller.rankPoints()
        SplashPage(tr("Your colour ranks", "דרגות הצבע שלכם")) {
            SplashLabel(text: tr("Total points: \(total)", "ניקוד מצטבר: \(total)"), size: 23, color: SplashRanks.at(total).color)
            SplashLabel(text: tr("Earn 2 points for a correct answer and 5 for a hit. Your colour stays with you between games.",
                                 "מרוויחים 2 נקודות על תשובה נכונה ו־5 על פגיעה. הצבע נשמר בין המשחקים."), size: 16)
            ForEach(SplashRanks.all, id: \.threshold) { rank in
                Text((total >= rank.threshold ? "✓ " : "") + (controller.hebrew ? rank.he : rank.en) + " · \(rank.threshold)")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundColor(SplashPalette.color(rank.ink))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: 48, maxHeight: 48)
                    // FamilyFormStyle: a coloured label stays flat, with 8 dp corners.
                    .background(RoundedRectangle(cornerRadius: 8).fill(SplashPalette.color(rank.color)))
                    .padding(.bottom, 8)
            }
            SplashBack { controller.home() }
        }
    }
}

// MARK: Play

/// Android `playMenu()`: the arena, the game mode (Paint walls adds its hit rule) and the number of rounds,
/// saved for the next visit; then Create room, Join room or House players only. Every action has 16 dp
/// above and 8 below (`spaceRoomActions`).
@MainActor
struct PlayPage: View {
    @ObservedObject var controller: SplashController

    var body: some View {
        let c = controller
        SplashPage(tr("Play", "לשחק")) {
            SplashDropdown(title: tr("Arena", "זירה"),
                           items: Arena.allCases.map { arena in
                               switch arena.name {
                               case "BEACH": return tr("Beach", "חוף")
                               case "PARK": return tr("Park", "פארק")
                               case "ANDROMEDA": return tr("Andromeda · low gravity", "אנדרומדה · כבידה נמוכה")
                               case "PARKING": return tr("Parking plaza", "רחבת חניה")
                               default: return tr("Five-floor tower", "מגדל בן חמש קומות")
                               }
                           },
                           selected: (c.upcomingArena ?? c.settings.arena).ordinal) { c.setUpcomingArena($0) }
            SplashDropdown(title: tr("Game mode", "סוג המשחק"),
                           items: [tr("Single · everyone for themselves", "יחיד · כולם מול כולם"), "2 × 2", "3 × 3",
                                   tr("Paint walls · teams · 2 × 2", "צביעת קירות · קבוצות · 2 × 2"),
                                   tr("Paint walls · teams · 3 × 3", "צביעת קירות · קבוצות · 3 × 3")],
                           selected: c.playMode) { c.setPlayMode($0) }
            if c.hitOptionsVisible {
                SplashDropdown(title: tr("When a player is hit in Paint walls", "כששחקן נפגע בצביעת קירות"),
                               items: [tr("Just paint · no penalty", "רק צבע · ללא השפעה"), tr("3 hits · 8-second rest", "3 פגיעות · מנוחה של 8 שניות"),
                                       tr("Slow down · each hit lasts 30 seconds", "האטה · כל פגיעה נמשכת 30 שניות")],
                               selected: c.hitEffect.ordinal) { c.setHitEffect($0) }
            }
            SplashDropdown(title: tr("Number of rounds", "מספר קרבות"),
                           items: [tr("Single battle", "קרב יחיד"), tr("3-battle cup", "גביע של 3 קרבות"),
                                   tr("5-battle cup · house players only", "גביע של 5 קרבות · שחקני הבית בלבד")],
                           selected: max([1, 3, 5].firstIndex(of: c.upcomingRounds) ?? 0, 0)) { c.setRounds($0) }
            Color.clear.frame(height: 16)
            SplashButton(title: tr("Create room", "יצירת חדר"), top: 16, bottom: 8) { c.createRoom() }
            SplashButton(title: tr("Join room", "הצטרפות לחדר"), color: 0xffffe082, top: 16, bottom: 8) { c.joinPage(false) }
            SplashButton(title: tr("House players only", "שחקני הבית בלבד"), color: 0xffffbb73, top: 16, bottom: 8) { c.houseGame(c.upcomingRounds > 1) }
            SplashBack(top: 16, bottom: 8) { c.home() }
        }
    }
}

@MainActor
struct WallOptionsPage: View {
    @ObservedObject var controller: SplashController

    var body: some View {
        let c = controller
        SplashPage(tr("Paint walls · teams", "צביעת קירות · קבוצות")) {
            SplashLabel(text: tr("Answer, collect and paint the OTHER team's wall. Fill it to win, or paint more in five minutes. Play with house players.",
                                 "ענו, אספו וצבעו את הקיר של הקבוצה השנייה. מלאו אותו לניצחון, או צבעו יותר בחמש דקות. משחק עם שחקני הבית."), size: 18)
            SplashDropdown(title: tr("Players", "שחקנים"), items: ["2 × 2", "3 × 3"], selected: c.seats() == 6 ? 1 : 0) { c.setWallPlayers($0) }
            SplashDropdown(title: tr("When a player is hit", "כששחקן נפגע"),
                           items: [tr("Just paint · no penalty", "רק צבע · ללא השפעה"), tr("3 hits · 8-second rest", "3 פגיעות · מנוחה של 8 שניות"),
                                   tr("Slow down · each hit lasts 30 seconds", "האטה · כל פגיעה נמשכת 30 שניות")],
                           selected: c.hitEffect.ordinal) { c.setHitEffect($0) }
            SplashLabel(text: tr("Slowdown stacks up to five hits. Each hit has its own timer. Questions and balloon controls stay the same.",
                                 "ההאטה מצטברת עד חמש פגיעות. לכל פגיעה שעון נפרד. השאלות והשליטה בבלונים נשארות כרגיל."), size: 16)
            SplashButton(title: tr("Choose players", "בחירת שחקנים")) { c.houseGame(false) }
            SplashButton(title: tr("Back", "חזרה"), color: 0xffe91e63) { c.playMenu() }
        }
    }
}

/// Android `joinPage`: the room code in the shared form field (`FamilyFormStyle`: white, 8 dp corners,
/// a grey border that turns blue while typing, dark text).
@MainActor
struct JoinPage: View {
    @ObservedObject var controller: SplashController
    @FocusState private var typing: Bool

    var body: some View {
        let c = controller
        SplashPage(tr("Join room", "הצטרפות לחדר")) {
            TextField("", text: $controller.roomCode, prompt: Text(tr("Room code", "קוד חדר")).foregroundColor(SplashPalette.color(0xff536b7b)))
                .font(.system(size: 18))
                .foregroundColor(SplashPalette.color(0xff17384d))
                .tint(SplashPalette.color(0xff2587d6))
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled(true)
                .focused($typing)
                .padding(.horizontal, 12)
                .frame(height: 58)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(SplashPalette.color(typing ? 0xff2587d6 : 0xff879baa), lineWidth: 1))
                .onChange(of: controller.roomCode) { _, value in
                    // Android LengthFilter(6).
                    if value.count > 6 { controller.roomCode = String(value.prefix(6)) }
                }
            SplashButton(title: tr("Join room", "הצטרפות לחדר")) { c.joinRoom() }
            SplashBack { c.joinBack() }
        }
    }
}

// MARK: House players

private struct StarShape: Shape {
    let index: Int

    func path(in rect: CGRect) -> Path {
        let step = rect.width / 5
        let r = min(step * 0.44, rect.height * 0.43)
        let x = step * (CGFloat(index) + 0.5)
        let y = rect.height / 2
        var outline = Path()
        for j in 0..<10 {
            let a = -Double.pi / 2 + Double(j) * Double.pi / 5
            let radius = j % 2 == 0 ? r : r * 0.44
            let point = CGPoint(x: x + CGFloat(cos(a)) * radius, y: y + CGFloat(sin(a)) * radius)
            if j == 0 { outline.move(to: point) } else { outline.addLine(to: point) }
        }
        outline.closeSubpath()
        return outline
    }
}

/// Android `SkillStars`: five stars, filled gold up to the rating, thin grey outlines after it.
@MainActor
struct SkillStars: View {
    let value: Int

    var body: some View {
        ZStack {
            ForEach(0..<5, id: \.self) { i in
                if i < value {
                    StarShape(index: i).fill(SplashPalette.color(0xffffdd63))
                } else {
                    StarShape(index: i).stroke(SplashPalette.color(0xffb7bdc8), lineWidth: 1)
                }
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement()
        .accessibilityLabel("\(value) / 5")
    }
}

/// Android CheckBox tinted #B4F6E7.
private struct CheckMark: View {
    let checked: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .stroke(SplashPalette.color(0xffb4f6e7), lineWidth: 2)
                .frame(width: 20, height: 20)
            if checked {
                RoundedRectangle(cornerRadius: 3)
                    .fill(SplashPalette.color(0xffb4f6e7))
                    .frame(width: 20, height: 20)
                Path { p in
                    p.move(to: CGPoint(x: 5, y: 10.5))
                    p.addLine(to: CGPoint(x: 8.5, y: 14))
                    p.addLine(to: CGPoint(x: 15, y: 6.5))
                }
                .stroke(SplashPalette.color(0xff0b2941), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                .frame(width: 20, height: 20)
            }
        }
        .frame(width: 32, height: 32)
    }
}

/// Android `houseChoices`: a card per character (sprite, a check box with the name, five star
/// ratings); a full roster disables the unchecked choices.
@MainActor
struct HouseChoices: View {
    let excluded: Set<String>
    let selected: [String]
    let capacity: Int
    let change: ([String]) -> Void

    private var knowledgeLabel: String {
        switch AppText.language {
        case "he": return "ידע"
        case "es": return "Conocimientos"
        case "ar": return "المعرفة"
        case "hi": return "ज्ञान"
        case "nl": return "Kennis"
        default: return "Knowledge"
        }
    }

    var body: some View {
        let hebrew = AppText.language == "he"
        let shown = Characters.all.filter { !excluded.contains($0.id) || selected.contains($0.id) }
        ForEach(shown, id: \.id) { character in
            let checked = selected.contains(character.id)
            let enabled = checked || selected.count < capacity
            let q = character.qualities
            let rows: [(String, Int)] = [(tr("Speed", "מהירות"), q.speed), (tr("Precision", "דיוק"), q.precision),
                                         (tr("Reflexes", "זריזות תגובה"), q.reflexes), (tr("Power", "עוצמה"), q.power),
                                         (knowledgeLabel, q.knowledge)]
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Group {
                        if let sprite = ArtStore.shared.readyCell(character.id) {
                            Image(uiImage: sprite).resizable().scaledToFit()
                        } else {
                            Color.clear
                        }
                    }
                    .frame(width: 60, height: 76)
                    Button {
                        toggle(character.id, !checked)
                    } label: {
                        HStack(spacing: 4) {
                            CheckMark(checked: checked)
                            Text(character.name(hebrew))
                                .font(.system(size: 21, weight: .bold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!enabled)
                    .opacity(enabled ? 1 : 0.4)
                    .accessibilityAddTraits(checked ? .isSelected : [])
                }
                ForEach(rows.indices, id: \.self) { i in
                    HStack(spacing: 0) {
                        Text(rows[i].0)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .frame(maxWidth: .infinity, minHeight: 38, maxHeight: 38, alignment: .leading)
                        SkillStars(value: rows[i].1)
                            .frame(width: 145, height: 34)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .background(SkySurface(color: 0xe622405a, radius: 18))
            // The check box handles its own tap; all otherwise non-clickable content
            // (portrait, qualifier labels, stars and whitespace) toggles the same choice.
            .contentShape(Rectangle())
            .onTapGesture { if enabled { toggle(character.id, !checked) } }
            .padding(.vertical, 7)
        }
    }

    private func toggle(_ id: String, _ checked: Bool) {
        if checked && selected.count >= capacity { return }
        var chosen = selected
        if checked {
            if !chosen.contains(id) { chosen.append(id) }
        } else {
            chosen.removeAll { $0 == id }
        }
        change(chosen)
    }
}

/// Android `houseGame`: "Choose players" with the count, the scrolling cards, and Start (enabled once
/// the roster is valid) and Back fixed below them.
@MainActor
struct HousePage: View {
    @ObservedObject var controller: SplashController

    var body: some View {
        let c = controller
        ZStack {
            SplashPalette.color(0xff0b2941)
            GeometryReader { geo in
                if let lagoon = ArtStore.shared.lagoon {
                    Image(uiImage: lagoon)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .opacity(0.43)
                }
            }
            GeometryReader { geo in
                VStack(spacing: 0) {
                    SplashLabel(text: tr("Choose players", "בחירת שחקנים"), size: 28)
                    SplashLabel(text: c.selectionMessage(1, c.selectedHouse.count, c.seats()), size: 18)
                    ScrollView {
                        VStack(spacing: 0) {
                            HouseChoices(excluded: [c.selected], selected: c.selectedHouse, capacity: c.seats() - 1) { c.houseChanged($0) }
                        }
                    }
                    .frame(maxHeight: .infinity)
                    SplashButton(title: tr("Start", "התחלה"), color: 0xffafdbff, enabled: c.houseStartEnabled) { c.houseStart() }
                    SplashButton(title: tr("Back", "חזרה"), color: 0xffe91e63) { c.houseBack() }
                }
                .padding(.horizontal, 22)
                .padding(.top, 10)
                .padding(.bottom, 14)
                .frame(width: SplashPageLayout.readingWidth(geo.size))
                .frame(maxWidth: .infinity)
            }
        }
        .environment(\.layoutDirection, AppText.rtl ? .rightToLeft : .leftToRight)
    }
}

// MARK: Daily paint journey

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
            piece.fill(shape, with: .color(SplashPalette.color(colors[i % 4]).opacity(alpha)))
        }
        context.fill(Path(ellipseIn: CGRect(x: cx - r * 1.12, y: cy - r * 1.12, width: r * 2.24, height: r * 2.24)), with: .color(SplashPalette.color(0xff173f55)))
        context.fill(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)), with: .color(SplashPalette.color(colors[0])))
        var check = Path()
        check.move(to: CGPoint(x: cx - r * 0.43, y: cy))
        check.addLine(to: CGPoint(x: cx - r * 0.08, y: cy + r * 0.29))
        check.addLine(to: CGPoint(x: cx + r * 0.47, y: cy - r * 0.3))
        context.stroke(check, with: .color(SplashPalette.color(0xff173f55)), style: StrokeStyle(lineWidth: r * 0.14, lineCap: .round))
    }
}

/// Android `challengePage(step)`.
@MainActor
struct JourneyPage: View {
    @ObservedObject var controller: SplashController

    var body: some View {
        let c = controller
        SplashPage(tr("Daily paint journey", "אתגר יומי")) {
            if let j = c.journey {
                Group {
                    if let portrait = ArtStore.shared.portrait(j.opponent) {
                        Image(uiImage: portrait).resizable().scaledToFit()
                    } else {
                        Color.clear
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 140)
                SplashLabel(text: j.header, size: 24)
                SplashLabel(text: j.stageLine, size: 18, color: j.stageColor)
                SplashLabel(text: j.bonusLine, size: 16)
                SplashLabel(text: j.title, size: 23, color: 0xffffe5a4)
                SplashLabel(text: j.goal, size: 18)
                if let drillGoal = j.drillGoal { SplashLabel(text: drillGoal, size: 17) }
                Text(j.introduction)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                    // FamilyFormStyle: a coloured label stays flat, with 8 dp corners.
                    .background(RoundedRectangle(cornerRadius: 8).fill(SplashPalette.color(0xee173f55)))
                SplashLabel(text: j.qualities, size: 15, color: 0xffffe5a4)
                SplashButton(title: tr("Start challenge", "התחלת אתגר")) { c.startChallenge(j.step) }
                ForEach(j.steps.indices, id: \.self) { i in
                    SplashLabel(text: j.steps[i], size: 16, color: i == j.stage ? 0xffa9fff0 : 0xffffffff)
                }
                SplashLabel(text: tr("Complete the whole cycle to meet new characters. No progress is lost on a retry.",
                                     "השלימו את כל המסלול כדי לפגוש דמויות חדשות. ניסיון חוזר לא מוחק התקדמות."), size: 15)
            }
            SplashBack { c.home() }
        }
    }
}

/// Android `challengeResults(e, r)`.
@MainActor
struct JourneyResultPage: View {
    @ObservedObject var controller: SplashController

    var body: some View {
        let c = controller
        if let r = c.journeyResult {
            SplashPage(r.title) {
                if r.won {
                    JourneyCelebration()
                        .frame(maxWidth: .infinity)
                        .frame(height: 160)
                }
                SplashLabel(text: r.kind, size: 24, color: 0xffffe5a4)
                SplashLabel(text: r.progress, size: 18)
                if let score = r.score { SplashLabel(text: score, size: 18) }
                SplashButton(title: r.button) { c.challengePage(r.nextStep) }
                SplashBack { c.challengePage() }
            }
        } else {
            SplashPage("") {
                SplashButton(title: tr("Back", "חזרה"), color: 0xffe91e63) { c.challengePage() }
            }
        }
    }
}

// MARK: Online lobby

@MainActor
struct LobbyPage: View {
    @ObservedObject var controller: SplashController

    var body: some View {
        let c = controller
        SplashPage(tr("Splash room", "חדר Splash")) {
            if let model = c.lobbyModel {
                SplashLabel(text: model.code, size: 28, color: 0xffb4f6e7)
                SplashButton(title: tr("Copy code", "העתקת קוד"), color: 0xfff9e59e) { c.copyCode(model.code) }
                SplashLabel(text: tr("Waiting for friends to join. Share the code, and add house players while you wait.",
                                     "ממתינים לחברים שיצטרפו. שתפו את הקוד והוסיפו שחקני בית בינתיים."), size: 17)
                ForEach(model.humans) { m in
                    HStack(spacing: 0) {
                        SplashLabel(text: m.name + (m.id == model.selfId ? tr(" · You", " · אתם") : "") + (model.readyIds.contains(m.id) ? " ✓" : ""), size: 18)
                        if model.hosted && m.id != model.selfId {
                            SplashButton(title: tr("Remove", "הסרה"), color: 0xfff6c5d5, height: 48) { c.lobbyRemovePlayer(m.id) }
                                .frame(width: 88)
                        }
                    }
                }
                SplashLabel(text: c.selectionMessage(model.humans.count, model.house.count, model.limit), size: 18)
                // The only real player (the owner) starts without "Ready"; house players never need it.
                if model.humans.count > 1 {
                    SplashButton(title: model.readyIds.contains(model.selfId) ? tr("Ready ✓", "מוכנים ✓") : tr("Ready", "מוכנים")) { c.lobbyMarkReady() }
                }
                if model.hosted {
                    SplashButton(title: tr("Start", "התחלה"), color: 0xffafdbff) { c.lobbyStartGame() }
                }
                SplashBack { c.leaveCupScreen() }
                if model.hosted {
                    HouseChoices(excluded: Set(model.humans.map { $0.character }), selected: model.house,
                                 capacity: max(model.limit - model.humans.count, 0)) { c.lobbyChangeHouse($0) }
                } else {
                    ForEach(model.house, id: \.self) { id in
                        SplashLabel(text: Characters.get(id).name(c.hebrew), size: 18)
                    }
                }
            } else {
                SplashButton(title: tr("Back", "חזרה"), color: 0xffe91e63) { c.home() }
            }
        }
    }
}

// MARK: Results

@MainActor
struct ResultsPage: View {
    @ObservedObject var controller: SplashController

    var body: some View {
        if let model = controller.results {
            SplashPage(model.title) {
                SplashLabel(text: tr("Final scores", "תוצאות סופיות"), size: 20, color: 0xff91fff0)
                ForEach(model.teams) { panel in
                    VStack(spacing: 0) {
                        SplashLabel(text: panel.name, size: 23, color: panel.ink)
                        SplashLabel(text: panel.subtitle, size: 20, color: panel.ink)
                        ForEach(panel.rows) { row in PlayerRow(row: row) }
                    }
                    .padding(12)
                    .background(SkySurface(color: panel.color, radius: 18))
                    .padding(.vertical, 8)
                }
                ForEach(model.rows) { row in PlayerRow(row: row) }
                if let note = model.note { SplashLabel(text: note, size: 14, leading: true) }
                SplashLabel(text: model.correctLine, size: 15)
                if let counts = model.countsLine { SplashLabel(text: counts, size: 13) }
                if model.onlineCup { SplashLabel(text: controller.standings, size: 16) }
                // Every results action has 18 dp above and 10 below.
                if model.nextRound {
                    SplashButton(title: tr("Next round", "הסיבוב הבא"), top: 18, bottom: 10) { controller.resultsNextRound() }
                }
                if let cupLine = model.cupLine { SplashLabel(text: cupLine) }
                if let standings = model.cupStandings { SplashLabel(text: standings, size: 15) }
                if model.nextBattle {
                    SplashButton(title: tr("Next battle", "הקרב הבא"), top: 18, bottom: 10) { controller.resultsNextBattle() }
                }
                if model.playAgain {
                    SplashButton(title: tr("Play again", "לשחק שוב"), top: 18, bottom: 10) { controller.resultsPlayAgain() }
                }
                // A cup (local or online) asks whether to keep it before leaving.
                SplashButton(title: tr("Main menu", "תפריט ראשי"), color: 0xffc6dfff, top: 18, bottom: 10) { controller.leaveCupScreen() }
            }
        } else {
            SplashPage("") {
                SplashButton(title: tr("Main menu", "תפריט ראשי"), color: 0xffc6dfff) { controller.home() }
            }
        }
    }
}

@MainActor
struct PlayerRow: View {
    let row: ResultPlayerRow

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if let portrait = ArtStore.shared.portrait(row.character) {
                    Image(uiImage: portrait).resizable().scaledToFit()
                } else {
                    Color.clear
                }
            }
            .frame(width: 46, height: 58)
            // Solo results: the winner's name in gold; the top three scores on gold, silver and bronze.
            let medal: UInt32? = row.rank == 0 ? 0xffffd760 : (row.rank == 1 ? 0xffcbd9e5 : (row.rank == 2 ? 0xffd89c67 : nil))
            SplashLabel(text: row.name, size: 17, color: row.rank == 0 ? (medal ?? row.ink) : row.ink)
            Text("\(row.score)")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(SplashPalette.color(medal == nil ? row.ink : 0xff163148))
                .lineLimit(1)
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
                .frame(width: 68)
                .background {
                    if let medal = medal { SkySurface(color: medal, radius: 12) }
                }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(SkySurface(color: 0x44214760, radius: 18))
        .padding(.vertical, 3)
    }
}

/// Android `leaveCupScreen()` with `FamilyTournamentUi.confirmSave`: leaving a cup's results or room
/// offers Save, Don't save and Cancel on a pale sky panel; a tap outside does not close it.
@MainActor
struct CupExitDialog: View {
    @ObservedObject var controller: SplashController

    var body: some View {
        let ink: UInt32 = 0xff282d4e
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                Text(tr("Save this tournament?", "לשמור את הטורניר?"))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(SplashPalette.color(ink))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                Text(tr("Save to continue later. Don't save removes this cup from saved games on this device; other players can continue.",
                        "שמרו כדי להמשיך מאוחר יותר. ללא שמירה, הגביע יוסר מהמשחקים השמורים במכשיר הזה; שחקנים אחרים יוכלו להמשיך."))
                    .font(.system(size: 17))
                    .foregroundColor(SplashPalette.color(ink))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 16)
                    .padding(.bottom, 12)
                choice(tr("Save", "שמירה"), fill: 0xffb8d9ff, text: ink) { controller.cupExitSave() }
                choice(tr("Don't save", "לא לשמור"), fill: 0xffe91e63, text: 0xffffffff) { controller.cupExitDiscard() }
                choice(tr("Cancel", "ביטול"), fill: 0xffe8e0ff, text: ink) { controller.cupExitCancel() }
            }
            .padding(24)
            .background(SkySurface(color: 0xfff6f8ff, radius: 24, panel: true))
            .frame(maxWidth: 560)
            .padding(.horizontal, 22)
        }
        .environment(\.layoutDirection, AppText.rtl ? .rightToLeft : .leftToRight)
    }

    private func choice(_ title: String, fill: UInt32, text: UInt32, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(SplashPalette.color(text))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: 64, maxHeight: 64)
                .contentShape(Rectangle())
        }
        .buttonStyle(SkyButtonStyle(color: fill, radius: 16))
        .padding(.top, 18)
    }
}
