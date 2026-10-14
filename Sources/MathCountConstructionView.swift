import SwiftUI

enum MathCountConstructionPresentation: Hashable {
    case quantity
    case tower

    var activityFamily: ActivityFamily {
        switch self {
        case .quantity: return .buildQuantity
        case .tower: return .tower
        }
    }
}

struct MathCountConstructionView: View {
    @State private var session: MathCountConstructionSession
    @State private var roundStartedAt = Date()
    @StateObject private var speechPlayer = InterfaceSpeechPlayer()
    @Environment(\.interfaceLocaleID) private var interfaceLocaleID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let presentation: MathCountConstructionPresentation
    private let onAttempt: (ActivityAttemptData) -> Void
    private let onComplete: () -> Void
    private let onExit: () -> Void

    private var quantityTheme: MathObjectTheme? {
        MathObjectCatalog.production?.theme(forStableKey: session.currentRound.id.rawValue)
    }

    init(
        session: MathCountConstructionSession,
        presentation: MathCountConstructionPresentation,
        onAttempt: @escaping (ActivityAttemptData) -> Void = { _ in },
        onComplete: @escaping () -> Void = {},
        onExit: @escaping () -> Void = {}
    ) {
        _session = State(initialValue: session)
        self.presentation = presentation
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
                    targetSection(compact: metrics.compact)
                    availableTokens(compact: metrics.compact)
                    controls
                }
            }
        }
        .mathReadAloud(
            instruction: session.isComplete ? nil : instruction,
            exercise: session.isComplete ? nil : session.currentRound.spokenPrompt,
            id: session.currentRoundIndex,
            player: speechPlayer
        )
        .onDisappear(perform: speechPlayer.stop)
    }

    private var instruction: String {
        presentation == .tower
            ? String(localized: "Build this many blocks")
            : String(localized: "Build this quantity")
    }

    private var prompt: some View {
        VStack(spacing: 10) {
            Text(instruction)
                .font(.headline.weight(.semibold))
                .foregroundStyle(Color(red: 0.17, green: 0.45, blue: 0.57))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 14) {
                // The target is always on screen, in dark ink on a lavender card, so a
                // child with the sound off still sees the number (it was spoken only:
                // the system text colour drew it white in Dark Mode).
                RepresentationView(
                    representation: session.currentRound.prompt,
                    context: .towerPrompt
                )
                .padding(.horizontal, 22)
                .padding(.vertical, 8)
                .frame(minWidth: 96, minHeight: 84)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(MathInk.lavender)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(MathInk.rim, lineWidth: 2)
                }
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

    private func targetSection(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(presentation == .tower
                ? String(localized: "Your tower")
                : String(localized: "Your group"))
                .font(.headline.weight(.semibold))
                .foregroundStyle(Color(red: 0.18, green: 0.43, blue: 0.54))
                .fixedSize(horizontal: false, vertical: true)

            constructionTarget(compact: compact)

            if !session.selectedTokenIDs.isEmpty && session.answerResult != .correct {
                Text(presentation == .tower
                    ? String(localized: "Tap a block in your tower to take it off.")
                    : String(localized: "Tap an item in your group to take it out."))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(MathInk.softInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func constructionTarget(compact: Bool) -> some View {
        Group {
            if presentation == .tower {
                VStack(spacing: 7) {
                    ForEach(Array(session.selectedTokenIDs.reversed()), id: \.self) { tokenID in
                        selectedToken(tokenID, compact: compact)
                    }
                    if session.selectedTokenIDs.isEmpty {
                        emptyTarget(text: String(localized: "No blocks yet"))
                    }
                }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 58, maximum: 76))], spacing: 10) {
                    ForEach(session.selectedTokenIDs, id: \.self) { tokenID in
                        selectedToken(tokenID, compact: compact)
                    }
                    if session.selectedTokenIDs.isEmpty {
                        emptyTarget(text: String(localized: "Empty container"))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: compact ? 130 : 170, alignment: .bottom)
        .padding(compact ? 14 : 18)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(red: 0.93, green: 0.98, blue: 1).opacity(0.92))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.95), lineWidth: 2)
        }
        .dropDestination(for: String.self) { identifiers, _ in
            guard let identifier = identifiers.first,
                  let tokenID = session.availableTokenIDs.first(where: {
                      $0.rawValue == identifier
                  }) else { return false }
            session.add(tokenID)
            return true
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            String(
                format: String(localized: "Built amount: %lld"),
                Int64(session.currentCount)
            )
        )
    }

    private func availableTokens(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // "Available objects" did not tell a child what to do with them.
            Text(presentation == .tower
                ? String(localized: "Tap a block to add it")
                : String(localized: "Tap an item to add it"))
                .font(.headline.weight(.semibold))
                .foregroundStyle(Color(red: 0.18, green: 0.43, blue: 0.54))
                .fixedSize(horizontal: false, vertical: true)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 58, maximum: 78))], spacing: 10) {
                ForEach(session.availableTokenIDs, id: \.self) { tokenID in
                    availableToken(tokenID, compact: compact)
                        .draggable(tokenID.rawValue)
                        .accessibilityAction(named: Text("Add")) { session.add(tokenID) }
                }
            }
        }
    }

    @ViewBuilder
    private var controls: some View {
        if session.answerResult == .correct {
            MinikFeedbackBadge(isCorrect: true)
            Button(action: advance) {
                Label("Next", systemImage: "arrow.forward")
            }
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

    private func availableToken(_ tokenID: MathCountTokenID, compact: Bool) -> some View {
        Button { session.add(tokenID) } label: {
            tokenFace(compact: compact)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(presentation == .tower
            ? String(localized: "Block")
            : String(localized: "Object"))
        .accessibilityHint(String(localized: "Adds one to the built amount"))
    }

    private func selectedToken(_ tokenID: MathCountTokenID, compact: Bool) -> some View {
        Button { session.remove(tokenID) } label: {
            tokenFace(compact: compact)
        }
        .buttonStyle(.plain)
        .accessibilityHint(String(localized: "Removes this item"))
    }

    @ViewBuilder
    private func tokenFace(compact: Bool) -> some View {
        if presentation == .tower {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.27, green: 0.74, blue: 0.82))
                .frame(maxWidth: 240, minHeight: compact ? 42 : 50)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(0.9), lineWidth: 2)
                }
        } else if let asset = quantityTheme?.object(forItemAt: 0) {
            Image(asset.assetName)
                .resizable()
                .scaledToFit()
                .frame(width: compact ? 48 : 58, height: compact ? 48 : 58)
                .accessibilityHidden(true)
        } else {
            // Missing-resource/debug fallback; MinikMath ships the approved object catalog.
            Circle()
                .fill(Color(red: 0.98, green: 0.62, blue: 0.28))
                .frame(width: compact ? 48 : 58, height: compact ? 48 : 58)
        }
    }

    @ViewBuilder
    private func emptyTarget(text: String) -> some View {
        if presentation == .quantity, let empty = quantityTheme?.emptyStateAsset {
            Image(empty.assetName)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 160, minHeight: 70, maxHeight: 110)
                .accessibilityLabel(String(localized: "Empty quantity"))
        } else {
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 70)
        }
    }

    private func submit() {
        let round = session.currentRound
        let duration = Date().timeIntervalSince(roundStartedAt)
        guard let result = session.submit(),
              let attempt = ActivityAttemptData(
                  itemID: ActivityItemID(rawValue: round.id.rawValue),
                  attemptIndex: session.submissionCount,
                  result: result == .correct ? .correct : .incorrect,
                  responseDurationSeconds: duration,
                  activityFamily: presentation.activityFamily,
                  mathLevelID: round.mathLevelID,
                  skillID: round.skillID
              ) else { return }
        onAttempt(attempt)
        if result == .incorrect {
            roundStartedAt = Date()
        }
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
