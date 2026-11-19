import SwiftUI
import UIKit

/// Hosts the model's existing ArenaView (Android `setContentView(outer)` with the AmuduView).
struct ArenaContainer: UIViewRepresentable {
    let view: ArenaView

    func makeUIView(context: Context) -> ArenaView {
        return view
    }

    func updateUIView(_ uiView: ArenaView, context: Context) {}
}

/// Android `present()`: the arena plus its live dialogs (private nickname huddle, players & scores, return vote) and the
/// loading spinner of a practice. The pause, nickname, roster and phrase dialogs are `SpudDialogRequest`s shown by
/// `RootView` above every page.
struct GameScreen: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack {
            Color(argb: 0xff10263c).ignoresSafeArea()
            if let arena = model.gameView {
                ArenaContainer(view: arena)
                    .id(ObjectIdentifier(arena))
            }
            if model.sceneLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .scaleEffect(1.6)
                    .frame(width: 64, height: 64)
            }
            if model.huddle != nil {
                HuddleCard(model: model)
            }
            if let rows = model.statusRows {
                StatusCard(model: model, rows: rows)
            }
            if let vote = model.returnVote {
                ReturnVoteCard(model: model, vote: vote)
            }
        }
    }
}

/// Android `showScores()`: what happened (the arena's outcome explanation), then the players and scores; it closes
/// itself when the next turn starts.
struct StatusCard: View {
    @ObservedObject var model: AppModel
    let rows: [StatusRow]

    var body: some View {
        DialogCard(RuleText["status"], onClose: { model.closeScores() }) {
            ScrollView {
                VStack(spacing: 0) {
                    if !model.statusExplanation.isEmpty {
                        AmuduParagraph(model.statusExplanation, size: 18, color: 0xff173047)
                    }
                    ForEach(rows) { row in
                        HStack(spacing: 0) {
                            Image(uiImage: model.art.portrait(row.character))
                                .resizable()
                                .scaledToFit()
                                .frame(width: 45, height: 54)
                            AmuduLabel(row.name, size: 17, color: 0xff173047)
                            AmuduLabel(row.score, size: 20, color: 0xff173047)
                                .fixedSize()
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 360)
            DialogTextButton(title: model.tr("Continue", "המשך")) { model.closeScores() }
        }
    }
}

/// Android `showReturnVote()`: cannot be dismissed; it closes when the vote ends.
struct ReturnVoteCard: View {
    @ObservedObject var model: AppModel
    let vote: ReturnVoteState

    var body: some View {
        DialogCard(vote.title, allowClose: false) {
            VStack(spacing: 0) {
                AmuduParagraph(RuleText["pausedVote"], size: 17, color: 0xff173047)
                AmuduLabel(RuleText.format(RuleText["seconds"], vote.seconds), size: 21, color: 0xff173047)
                if vote.canVote {
                    if vote.voted {
                        AmuduLabel(RuleText["voted"], size: 17, color: 0xff173047)
                    } else {
                        AmuduButton(RuleText["yes"]) { model.castReturnVote(true) }
                        AmuduButton(RuleText["no"]) { model.castReturnVote(false) }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}

/// Android nickname huddle dialog (2026-11): never shown to the target; who is being named and their current nickname,
/// how it works (portrait), a word field with the resulting nickname previewed, Suggest (only for a new valid word), the
/// funny-word list, the countdown and the proposals with their votes (" ✓" on the player's vote). In landscape the form
/// and the proposals sit side by side (the proposals in two columns) in a dialog up to 760 dp wide. The × closes it for
/// this huddle.
struct HuddleCard: View {
    @ObservedObject var model: AppModel
    @FocusState private var inputFocused: Bool

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            SpudDialogPanel(title: model.tr("Choose a funny nickname", "בחרו כינוי מצחיק"), allowClose: true,
                            maxWidth: landscape ? 760 : 460, onClose: { model.closeHuddle() }) {
                ScrollView {
                    VStack(spacing: 0) {
                        if let h = model.huddle {
                            AmuduParagraph(model.tr("Naming: ", "בוחרים כינוי עבור: ") + h.naming, size: 19, color: 0xff163650)
                            if let current = h.current {
                                AmuduParagraph(model.tr("Current nickname: ", "הכינוי הנוכחי: ") + current, size: 17, color: 0xff163650)
                            }
                            if !landscape {
                                AmuduParagraph(model.tr("Suggest a word and vote. You may change your vote. Play continues when everyone has voted or time runs out.",
                                                        "מציעים מילה ומצביעים. אפשר לשנות את ההצבעה. המשחק ממשיך כשכולם הצביעו או כשהזמן נגמר."), size: 16, color: 0xff163650)
                            }
                            if landscape {
                                HStack(alignment: .top, spacing: 12) {
                                    form(compact: true)
                                        .frame(maxWidth: .infinity)
                                    choices(h, columns: 2)
                                        .frame(maxWidth: .infinity)
                                }
                            } else {
                                form(compact: false)
                                choices(h, columns: 1)
                            }
                        }
                    }
                    .padding(EdgeInsets(top: 4, leading: 8, bottom: 8, trailing: 8))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private func form(compact: Bool) -> some View {
        VStack(spacing: 0) {
            TextField("", text: $model.huddleInput, prompt: Text(model.tr("One new word", "מילה חדשה אחת")).foregroundColor(Color(argb: SkyInk.hint)))
                .font(.system(size: 18))
                .foregroundColor(Color(argb: SkyInk.input))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($inputFocused)
                .padding(12)
                .frame(minHeight: 56)
                .background(InputFace(focused: inputFocused))
                .onChange(of: model.huddleInput) { _, value in model.limitHuddleInput(value) }
            if let preview = model.huddlePreview {
                AmuduParagraph(preview, size: 17, color: 0xff163650)
            }
            huddleButton(model.tr("Suggest this nickname", "הצעת הכינוי"), color: 0xffb8f3dc, compact: compact, enabled: model.canSuggestNickname) {
                model.suggestNickname()
            }
            huddleButton(model.tr("Funny-word list", "רשימת מילים מצחיקות"), color: 0xffdfd3ff, compact: compact, enabled: true) {
                model.showFunnyWords()
            }
        }
    }

    private func choices(_ h: HuddleState, columns: Int) -> some View {
        VStack(spacing: 0) {
            AmuduLabel(model.tr("\(h.seconds) seconds left", "נותרו \(h.seconds) שניות"), size: 17, color: 0xff163650)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 0) {
                ForEach(h.proposals) { p in
                    AmuduButton(p.name + " · " + String(p.votes) + (p.mine ? " ✓" : ""), color: 0xffc4e4ff) { model.voteFor(p.id) }
                        .padding(.vertical, -2)
                }
            }
        }
    }

    /// Android landscape: the form's buttons shrink to 46 dp with 5/12 dp padding and 3 dp margins.
    @ViewBuilder private func huddleButton(_ title: String, color: UInt32, compact: Bool, enabled: Bool, action: @escaping () -> Void) -> some View {
        if compact {
            Button(action: action) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color(argb: 0xff12324a))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .contentShape(Rectangle())
            }
            .buttonStyle(SkyButtonStyle(color: color))
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.45)
            .padding(.vertical, 3)
        } else {
            AmuduButton(title, color: color, enabled: enabled, action: action)
        }
    }
}

/// Switches between the Android pages and shows the SPUD dialogs, the grown-up gate and toasts.
struct RootView: View {
    @ObservedObject var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack(alignment: .bottom) {
            screen
            // iOS payment model (CLAUDE.md): the unlock screen covers the page it was opened from.
            if model.spud.unlockVisible {
                SpudUnlockScreen(model: model, store: model.spud)
            }
            ForEach(model.dialogs) { request in
                SpudDialogView(model: model, request: request)
            }
            if model.gateVisible {
                AdultGateCard(model: model)
            }
            // Under the toasts: a wrong grown-up answer for a card link shows its toast above the card.
            FamilyOverlay()
            if let message = model.toast {
                ToastView(text: message)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.toast)
        .environment(\.layoutDirection, AppText.rtl ? .rightToLeft : .leftToRight)
        .preferredColorScheme(.dark)
        .onChange(of: scenePhase) { _, phase in model.scenePhaseChanged(phase) }
        .onAppear {
            // Android FLAG_KEEP_SCREEN_ON.
            UIApplication.shared.isIdleTimerDisabled = true
            // App Store captures only: opens the requested screen (SpudScreenshot).
            model.applyStoreScreenshotScene()
        }
    }

    @ViewBuilder private var screen: some View {
        switch model.screen {
        case .home: HomeScreen(model: model)
        case .setup: SetupScreen(model: model)
        case .help: HelpScreen(model: model)
        case .connecting: ConnectingScreen(model: model)
        case .lobby: LobbyScreen(model: model)
        case .game: GameScreen(model: model)
        case .result: ResultScreen(model: model)
        case .journey: JourneyScreen(model: model)
        case .journeyResult: JourneyResultScreen(model: model)
        case .lessonHub: LessonHubScreen(model: model)
        case .lesson: LessonScreen(model: model)
        case .lessonResult: LessonResultScreen(model: model)
        case .support: SupportScreen(model: model)
        case .rank: RankScreen(model: model)
        case .privacy: PrivacyScreen(model: model)
        case .league:
            if let league = model.league {
                FamilyLeagueScreen(model: model, league: league)
            } else {
                HomeScreen(model: model)
            }
        }
    }
}
