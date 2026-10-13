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

/// Android `present()`: the arena plus its dialogs (pause, typed nickname, roster, preset phrases, private nickname
/// huddle, players & scores, return vote) and the loading spinner of a practice.
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
        .alert(model.tr("Take a break", "זמן להפסקה"), isPresented: $model.pauseVisible) {
            Button(model.tr("Continue", "המשך")) { model.resumeFromPause() }
            Button(model.tr("Finish game", "סיום המשחק")) { model.finishFromPause() }
            Button(model.tr("Main menu", "תפריט ראשי")) { model.home() }
        } message: {
            Text(model.pauseMessage)
        }
        .alert(model.tr("Type the nickname", "כתבו את הכינוי"), isPresented: $model.nicknameVisible) {
            TextField(model.tr("Type the nickname", "כתבו את הכינוי"), text: $model.nicknameInput)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button(model.tr("Call", "קריאה")) { model.callWithNickname() }
            Button(model.tr("Cancel", "ביטול"), role: .cancel) {}
        } message: {
            Text(model.tr("An incorrect nickname adds one penalty.", "כינוי שגוי מוסיף נקודת חובה אחת."))
        }
        .confirmationDialog(model.tr("Choose a player", "בחירת שחקן"), isPresented: $model.rosterVisible, titleVisibility: .visible) {
            ForEach(model.rosterCandidates) { candidate in
                Button(candidate.name) { model.choose(candidate.id) }
            }
            Button(model.tr("Back", "חזרה"), role: .cancel) {}
        }
        .confirmationDialog(model.tr("Say something", "אומרים משהו"), isPresented: $model.sayVisible, titleVisibility: .visible) {
            ForEach(0..<model.sayPhrases.count, id: \.self) { i in
                Button(model.sayPhrases[i]) { model.say(i) }
            }
        }
    }
}

/// Android `showScores()`: players and scores after a penalty; it closes itself when the next turn starts.
struct StatusCard: View {
    @ObservedObject var model: AppModel
    let rows: [StatusRow]

    var body: some View {
        DialogCard(RuleText["status"]) {
            ScrollView {
                VStack(spacing: 0) {
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
        DialogCard(vote.title) {
            VStack(spacing: 0) {
                AmuduLabel(RuleText["pausedVote"], size: 17, color: 0xff173047)
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

/// Android nickname huddle dialog: never shown to the target; the countdown refreshes every 350 ms.
struct HuddleCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                Text(model.tr("Choose a funny nickname", "בחרו כינוי מצחיק"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Color(argb: 0xff163650))
                    .padding(.bottom, 4)
                AmuduLabel(model.tr("Choose one word, then vote. At three penalties it replaces the name; later words are added.", "בוחרים מילה אחת ומצביעים. בשלוש נקודות היא מחליפה את השם; בהמשך מוסיפים מילה."), size: 16, color: 0xff163650)
                TextField("", text: $model.huddleInput)
                    .font(.system(size: 18))
                    .foregroundColor(Color(argb: 0xff163650))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(.vertical, 8)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Color(argb: 0xff00a5b8)).frame(height: 2)
                    }
                    .onChange(of: model.huddleInput) { _, value in model.limitHuddleInput(value) }
                AmuduLabel(model.tr("\(model.huddle?.seconds ?? 0) seconds left", "נותרו \(model.huddle?.seconds ?? 0) שניות"), size: 19, color: 0xff163650)
                AmuduButton(model.tr("Suggest this nickname", "הצעת הכינוי")) { model.suggestNickname() }
                AmuduButton(model.tr("Funny-word list", "רשימת מילים מצחיקות"), color: 0xffdfd3ff) { model.wordListVisible = true }
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(model.huddle?.proposals ?? []) { p in
                            AmuduButton(p.name + " · " + String(p.votes), color: 0xffc4e4ff) { model.voteFor(p.id) }
                        }
                    }
                }
                .frame(height: 200)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
            .padding(.horizontal, 22)
            .confirmationDialog(model.tr("Funny-word list", "רשימת מילים מצחיקות"), isPresented: $model.wordListVisible, titleVisibility: .hidden) {
                ForEach(0..<model.funnyWords.count, id: \.self) { i in
                    Button(model.funnyWords[i]) { model.huddleInput = model.funnyWords[i] }
                }
            }
        }
    }
}

/// Switches between the Android pages and shows toasts.
struct RootView: View {
    @ObservedObject var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack(alignment: .bottom) {
            screen
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
        case .support: SupportScreen(model: model)
        case .rank: RankScreen(model: model)
        }
    }
}
