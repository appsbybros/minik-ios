import SwiftUI

/// Android Minik Math Plus ActivityScreen's demo branch and DemoPrompt (dc12a5c): the first
/// time Number Building or Math Soccer opens, one hands-on example comes first. It reports no
/// answers, so it earns no points and never changes the level, the daily journey or the
/// practice records. Finishing it, or Skip example, opens the activity itself; the close
/// button leaves as the activity's own does.
struct MathActivityDemoView: View {
    let activity: MathProductionActivityID
    let onFinish: () -> Void
    let onExit: () -> Void

    var body: some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                MathDemoPrompt(instruction: instruction, onSkip: onFinish)
            }
            // As every Math activity screen (mathActivityChrome): dark text on light tiles.
            .environment(\.colorScheme, .light)
    }

    @ViewBuilder
    private var content: some View {
        if activity == .mathSoccer, let round = MathActivityDemoContent.soccerRound() {
            SoccerView(
                session: SoccerSession(round: round),
                mathActivityFamily: .soccer,
                mathLevelID: .m1,
                isDemo: true,
                onComplete: onFinish,
                onExit: onExit
            )
        } else if activity == .buildNumber, let session = MathActivityDemoContent.buildNumberSession() {
            BuildView(
                session: session,
                mathActivityFamily: .buildNumber,
                mathLevelID: .m3,
                onComplete: onFinish,
                onExit: onExit
            )
        } else {
            // No example for this activity: go straight on to it.
            Color.clear
                .onAppear(perform: onFinish)
        }
    }

    private var instruction: String {
        activity == .mathSoccer
            ? String(localized: "Swipe the ball marked 2 up toward the goal. Follow the moving dot!")
            : String(localized: "Make 12: one ten and two ones. Tap 1, then 2, then tap Check answer.")
    }
}

/// Android DemoPrompt: "Try one together", what to do, and Skip example.
private struct MathDemoPrompt: View {
    let instruction: String
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "Try one together"))
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(MathInk.navy)
                .accessibilityAddTraits(.isHeader)
            Text(instruction)
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundStyle(MathInk.navy)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onSkip) {
                Text(String(localized: "Skip example"))
            }
            .buttonStyle(MinikUtilityButtonStyle())
            .frame(minHeight: 48)
        }
        .padding(14)
        .frame(maxWidth: 620, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(MathInk.rim, lineWidth: 2)
        }
        .shadow(color: MathInk.navy.opacity(0.16), radius: 12, y: 4)
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }
}
