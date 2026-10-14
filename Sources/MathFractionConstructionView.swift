import SwiftUI

struct MathFractionConstructionView: View {
    @State private var session: MathFractionConstructionSession
    @State private var roundStartedAt = Date()
    @StateObject private var speechPlayer = InterfaceSpeechPlayer()
    @Environment(\.interfaceLocaleID) private var interfaceLocaleID
    private let onAttempt: (ActivityAttemptData) -> Void
    private let onComplete: () -> Void
    private let onExit: () -> Void

    init(
        session: MathFractionConstructionSession,
        onAttempt: @escaping (ActivityAttemptData) -> Void = { _ in },
        onComplete: @escaping () -> Void = {},
        onExit: @escaping () -> Void = {}
    ) {
        _session = State(initialValue: session)
        self.onAttempt = onAttempt
        self.onComplete = onComplete
        self.onExit = onExit
    }

    var body: some View {
        MinikPracticeScreen(
            progressLabel: "\(session.currentRoundIndex + 1) / \(session.roundCount)",
            onExit: exit
        ) { metrics in
            MinikPracticeSurface(compact: metrics.compact) {
                VStack(spacing: metrics.compact ? 16 : 24) {
                    prompt
                    fractionBar
                    controls
                }
            }
        }
        .mathReadAloud(
            instruction: session.isComplete ? nil : String(localized: "Build this quantity"),
            exercise: session.isComplete ? nil : session.currentRound.spokenPrompt,
            id: session.currentRoundIndex,
            player: speechPlayer
        )
        .onDisappear(perform: speechPlayer.stop)
    }

    private var prompt: some View {
        VStack(spacing: 10) {
            Text("Build this quantity")
                .font(.headline.weight(.semibold))
                .foregroundStyle(Color(red: 0.17, green: 0.45, blue: 0.57))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(String(localized: "Color the parts of the bar with Add and Undo."))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MathInk.softInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 14) {
                RepresentationView(representation: session.currentRound.prompt, context: .buildPrompt)
                Button(action: speakPrompt) {
                    MinikArtworkImage(name: MinikVisualAsset.speaker)
                        .frame(width: 42, height: 42)
                }
                    .buttonStyle(MinikUtilityButtonStyle())
                    .accessibilityLabel(String(localized: "Hear the target number"))
            }
        }
    }

    private var fractionBar: some View {
        HStack(spacing: 4) {
            ForEach(0..<session.currentRound.target.denominator, id: \.self) { index in
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(index < session.selectedPartCount
                        ? Color(red: 0.20, green: 0.72, blue: 0.78)
                        : Color.white.opacity(0.94))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color(red: 0.17, green: 0.45, blue: 0.57), lineWidth: 3)
                    )
            }
        }
        .frame(maxWidth: 480, minHeight: 110, maxHeight: 150)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(
            format: String(localized: "Fraction %lld over %lld"),
            Int64(session.selectedPartCount),
            Int64(session.currentRound.target.denominator)
        ))
    }

    @ViewBuilder
    private var controls: some View {
        if session.answerResult == .correct {
            MinikFeedbackBadge(isCorrect: true)
            Button(action: advance) { Label("Next", systemImage: "arrow.forward") }
                .buttonStyle(MinikPrimaryActionStyle())
        } else {
            if session.answerResult == .incorrect {
                MinikFeedbackBadge(isCorrect: false)
                Text("Change the amount and check again.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MathInk.warning)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 22) {
                Button(action: { session.removePart() }) {
                    Label("Undo", systemImage: "minus.circle.fill")
                }
                .buttonStyle(MinikUtilityButtonStyle())
                .disabled(session.selectedPartCount == 0)
                Button(action: { session.addPart() }) {
                    Label("Add", systemImage: "plus.circle.fill")
                }
                .buttonStyle(MinikUtilityButtonStyle())
                .disabled(session.selectedPartCount == session.currentRound.target.denominator)
                MathSubmitBuzzer(action: submit)
            }
        }
    }

    private func submit() {
        let round = session.currentRound
        guard let result = session.submit(),
              let attempt = ActivityAttemptData(
                  itemID: ActivityItemID(rawValue: round.id.rawValue),
                  attemptIndex: session.submissionCount,
                  result: result == .correct ? .correct : .incorrect,
                  responseDurationSeconds: Date().timeIntervalSince(roundStartedAt),
                  activityFamily: .buildQuantity,
                  mathLevelID: round.mathLevelID,
                  skillID: round.skillID
              ) else { return }
        onAttempt(attempt)
        if result == .incorrect { roundStartedAt = Date() }
    }

    private func advance() {
        let wasComplete = session.isComplete
        session.nextRound()
        if !wasComplete && session.isComplete { onComplete() }
        else { roundStartedAt = Date() }
    }

    private func speakPrompt() {
        MathReadAloud.say(
            MathReadAloud.text(instruction: nil, exercise: session.currentRound.spokenPrompt),
            with: speechPlayer,
            fallback: interfaceLocaleID
        )
    }

    private func exit() { speechPlayer.stop(); onExit() }
}
