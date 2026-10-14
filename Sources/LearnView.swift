import SwiftUI

enum LearnPresentation: Hashable {
    case standard
    case language
}

struct LearnView: View {
    @State private var session: LearnSession
    @StateObject private var speechPlayer: LearningSpeechPlayer
    @StateObject private var interfaceSpeechPlayer: InterfaceSpeechPlayer
    @Environment(\.interfaceLocaleID) private var interfaceLocaleID
    @Environment(\.scenePhase) private var scenePhase
    private let presentation: LearnPresentation
    private let onComplete: () -> Void
    private let onExit: () -> Void

    /// Android LearnScreen's delay(300) before it speaks the first letter.
    private static let languageOpeningSpeechDelay: Duration = .milliseconds(300)

    init(
        session: LearnSession,
        presentation: LearnPresentation = .standard,
        onComplete: @escaping () -> Void = {},
        onExit: @escaping () -> Void = {}
    ) {
        _session = State(initialValue: session)
        _speechPlayer = StateObject(wrappedValue: LearningSpeechPlayer())
        _interfaceSpeechPlayer = StateObject(wrappedValue: InterfaceSpeechPlayer())
        self.presentation = presentation
        self.onComplete = onComplete
        self.onExit = onExit
    }

    var body: some View {
        Group {
            if presentation == .language {
                languageBody
            } else {
                standardBody
            }
        }
        .task { await speakOpeningCard() }
        .mathReadAloud(
            instruction: nil,
            exercise: mathSpeechText,
            id: session.currentCardIndex,
            player: interfaceSpeechPlayer
        )
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                stopSpeech()
            }
        }
        .onDisappear(perform: stopSpeech)
    }

    private var standardBody: some View {
        MinikPracticeScreen(
            progressLabel: "\(session.currentCardIndex + 1) / \(session.cardCount)",
            onExit: exit
        ) { metrics in
            let compact = metrics.compact

            MinikPracticeSurface(compact: compact) {
                VStack(spacing: compact ? 18 : 24) {
                    if presentation == .standard {
                        stepByStepHeader(compact: compact)
                    }

                    if hasSpeech {
                        HStack {
                            Spacer()

                            Button(action: replayCurrentCard) {
                                HStack(spacing: 8) {
                                    MinikArtworkImage(name: MinikVisualAsset.speaker)
                                        .frame(width: 30, height: 30)
                                    Text("Listen")
                                }
                            }
                            .buttonStyle(MinikUtilityButtonStyle())
                            .accessibilityLabel("Replay current card")
                            .accessibilityHint("Speaks the current card again")
                        }
                    }

                    cardContent(compact: compact)

                    Button(action: advance) {
                        Label(
                            session.nextCardStartsOver
                                ? String(localized: "Start over")
                                : String(localized: "Next"),
                            systemImage: session.nextCardStartsOver
                                ? "arrow.counterclockwise"
                                : "arrow.forward"
                        )
                    }
                    .buttonStyle(MinikPrimaryActionStyle())
                    .disabled(session.isComplete)
                }
            }
        }
    }

    /// Learn Math teaches one fact at a time with its picture; the Facts Table
    /// (MathCardsView) shows them all at once. The header says which this is.
    private func stepByStepHeader(compact: Bool) -> some View {
        VStack(spacing: 6) {
            Text(String(localized: "Learn step by step"))
                .font(.system(size: compact ? 22 : 27, weight: .bold, design: .rounded))
                .foregroundStyle(MathInk.navy)
            Text(String(localized: "Look, listen and say it out loud. Then tap Next."))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MathInk.softInk)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var languageBody: some View {
        if let card = LanguageLearnContentProvider.presentation(for: session.currentCard) {
            LanguageLearnPage(
                card: card,
                nextStartsOver: session.nextCardStartsOver,
                isComplete: session.isComplete,
                hasSpeech: hasSpeech,
                onHome: exit,
                onReplay: replayCurrentCard,
                onNext: advance
            )
        } else {
            standardBody
        }
    }

    private func advance() {
        stopSpeech()
        let wasComplete = session.isComplete
        session.nextCard()

        if !wasComplete && session.isComplete {
            onComplete()
        } else if !session.isComplete, mathSpeechText == nil {
            replayCurrentCard()
        }
    }

    private var speechPlan: LearningSpeechPlan {
        LearningSpeechPlan(card: session.currentCard)
    }

    private var hasSpeech: Bool {
        !speechPlan.utterances.isEmpty || mathSpeechText != nil
    }

    @ViewBuilder
    private func cardContent(compact: Bool) -> some View {
        let representations = session.currentCard.representations
        let leadingTexts = representations.prefix { representation in
            if case .learningText = representation { return true }
            return false
        }
        let trailingRepresentations = representations.dropFirst(leadingTexts.count)

        VStack(spacing: compact ? 18 : 24) {
            if !leadingTexts.isEmpty {
                HStack(spacing: compact ? 18 : 26) {
                    ForEach(Array(leadingTexts.enumerated()), id: \.offset) { _, representation in
                        RepresentationView(
                            representation: representation,
                            context: presentation == .language
                                ? .languageLearnHero
                                : .learnHero
                        )
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, compact ? 2 : 6)

                Rectangle()
                    .fill(Color(red: 0.30, green: 0.68, blue: 0.81).opacity(0.42))
                    .frame(maxWidth: 260, minHeight: 2, maxHeight: 2)
                    .accessibilityHidden(true)
            }

            if !trailingRepresentations.isEmpty {
                VStack(spacing: compact ? 16 : 20) {
                    ForEach(Array(trailingRepresentations.enumerated()), id: \.offset) { _, representation in
                        RepresentationView(
                            representation: representation,
                            context: illustrationContext(for: representation)
                        )
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func illustrationContext(
        for representation: Representation
    ) -> RepresentationView.Context {
        switch representation {
        case .imageAsset:
            return .learnIllustration
        case .mathExpression, .visualQuantity, .math:
            return .learnHero
        default:
            return .learnSupporting
        }
    }

    /// Language waits as Android LearnScreen does before the first letter. A Next
    /// tap during the pause has already spoken its own card, and leaving the page
    /// cancels the pause, so neither is followed by this speech. A Math fact is read
    /// by mathReadAloud instead, which follows the Parent Area's Read aloud switch.
    @MainActor
    private func speakOpeningCard() async {
        guard presentation == .language else {
            if mathSpeechText == nil { replayCurrentCard() }
            return
        }
        let openingCardIndex = session.currentCardIndex
        try? await Task.sleep(for: Self.languageOpeningSpeechDelay)
        guard !Task.isCancelled, session.currentCardIndex == openingCardIndex else {
            return
        }
        replayCurrentCard()
    }

    private func replayCurrentCard() {
        if let mathSpeechText {
            MathReadAloud.say(
                MathReadAloud.text(instruction: nil, exercise: mathSpeechText),
                with: interfaceSpeechPlayer,
                fallback: interfaceLocaleID
            )
        } else {
            speechPlayer.speak(speechPlan)
        }
    }

    private func exit() {
        stopSpeech()
        onExit()
    }

    private var mathSpeechText: String? {
        let mathRepresentations = session.currentCard.representations.compactMap { representation -> MathRepresentation? in
            guard case .math(let math) = representation else { return nil }
            return math
        }
        if let expression = mathRepresentations.first(where: {
            if case .missingValueExpression = $0 { return true }
            return false
        }) ?? mathRepresentations.first(where: {
            if case .arithmeticExpression = $0 { return true }
            return false
        }) {
            return expression.displayText
        }
        return mathRepresentations.compactMap { representation -> String? in
            guard case .numeral(let numeral) = representation else { return nil }
            return String(numeral.value)
        }.first
    }

    private func stopSpeech() {
        speechPlayer.stop()
        interfaceSpeechPlayer.stop()
    }
}
