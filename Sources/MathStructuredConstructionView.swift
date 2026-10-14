import SwiftUI

struct MathStructuredConstructionView: View {
    @State private var session: MathStructuredConstructionSession
    @State private var roundStartedAt = Date()
    @StateObject private var speechPlayer = InterfaceSpeechPlayer()
    @Environment(\.interfaceLocaleID) private var interfaceLocaleID
    private let onAttempt: (ActivityAttemptData) -> Void
    private let onComplete: () -> Void
    private let onExit: () -> Void

    init(
        session: MathStructuredConstructionSession,
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
                VStack(spacing: metrics.compact ? 16 : 22) {
                    prompt
                    tokenGrid(tokens: session.selectedTokens, isBuild: true, compact: metrics.compact)
                    tokenGrid(tokens: session.availableTokens, isBuild: false, compact: metrics.compact)
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
        .frame(maxWidth: .infinity)
    }

    private func tokenGrid(
        tokens: [MathStructuredConstructionToken],
        isBuild: Bool,
        compact: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // "Available objects" did not tell a child what to do with the pieces.
            Text(isBuild ? String(localized: "Your build") : String(localized: "Tap a piece to add it"))
                .font(.headline.weight(.semibold))
                .foregroundStyle(Color(red: 0.18, green: 0.43, blue: 0.54))
                .fixedSize(horizontal: false, vertical: true)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 82, maximum: 124), spacing: 10)],
                spacing: 10
            ) {
                ForEach(tokens, id: \.id) { token in
                    tokenButton(token, selected: isBuild, compact: compact)
                }
                if isBuild && tokens.isEmpty {
                    Text("Empty container")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 72)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: isBuild ? 120 : nil)
        .padding(isBuild ? 14 : 0)
        .background(
            Group {
                if isBuild {
                    RoundedRectangle(cornerRadius: 26)
                        .fill(Color(red: 0.93, green: 0.98, blue: 1).opacity(0.92))
                }
            }
        )
        .dropDestination(for: String.self) { identifiers, _ in
            guard isBuild,
                  let identifier = identifiers.first,
                  let token = session.availableTokens.first(where: { $0.id.rawValue == identifier }) else {
                return false
            }
            session.add(token.id)
            return true
        }
    }

    private func tokenButton(
        _ token: MathStructuredConstructionToken,
        selected: Bool,
        compact: Bool
    ) -> some View {
        Button {
            if selected { session.remove(token.id) } else { session.add(token.id) }
        } label: {
            RepresentationView(representation: representation(for: token), context: .buildToken)
                .frame(maxWidth: .infinity, minHeight: compact ? 62 : 76)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.94)))
        }
        .buttonStyle(.plain)
        .draggable(token.id.rawValue)
        .accessibilityHint(selected
            ? String(localized: "Removes this item")
            : String(localized: "Adds one to the built amount"))
    }

    private func representation(for token: MathStructuredConstructionToken) -> Representation {
        switch token.unit {
        case .placeValue(let placeValue):
            return .math(.placeValue(MathPlaceValueRepresentation(
                components: [MathPlaceValueComponent(placeValue: placeValue, digit: 1)!],
                structureID: RepresentationStructureID(rawValue: token.id.rawValue)
            )!))
        case .equalGroup(let itemsPerGroup):
            return .math(.equalGroups(MathEqualGroupsRepresentation(
                groupCount: 1,
                itemsPerGroup: itemsPerGroup,
                structureID: RepresentationStructureID(rawValue: token.id.rawValue)
            )!))
        }
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
                Button(action: { session.undo() }) {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(MinikUtilityButtonStyle())
                .disabled(session.selectedTokenIDs.isEmpty)
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
        if !wasComplete && session.isComplete {
            onComplete()
        } else {
            roundStartedAt = Date()
        }
    }

    private func speakPrompt() {
        MathReadAloud.say(
            MathReadAloud.text(instruction: nil, exercise: session.currentRound.spokenPrompt),
            with: speechPlayer,
            fallback: interfaceLocaleID
        )
    }

    private func exit() {
        speechPlayer.stop()
        onExit()
    }
}
