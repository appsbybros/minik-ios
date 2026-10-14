import SwiftUI

enum MultipleChoicePresentation: Hashable, Sendable {
    case standard
    case firstLetterPictureToLetter
    case firstLetterLetterToPicture
    case pictureToWord
    case wordToPicture

    var instructionKey: String.LocalizationValue {
        switch self {
        case .standard: "Choose the answer"
        case .firstLetterPictureToLetter: "Choose the starting letter"
        case .firstLetterLetterToPicture: "Match the first sound to a picture"
        case .pictureToWord: "Find the word for the picture"
        case .wordToPicture: "Find the picture for the word"
        }
    }

    var instruction: String { String(localized: instructionKey) }

    var usesPictureAnswers: Bool {
        self == .firstLetterLetterToPicture || self == .wordToPicture
    }

    var usesPicturePrompt: Bool {
        self == .firstLetterPictureToLetter || self == .pictureToWord
    }

    var usesExpectedSemanticProgressIdentity: Bool {
        switch self {
        case .firstLetterPictureToLetter, .firstLetterLetterToPicture, .pictureToWord,
             .wordToPicture:
            return true
        case .standard:
            return false
        }
    }
}

enum MultipleChoiceAttemptIdentity {
    static func itemID(
        for challenge: Challenge,
        usesExpectedSemanticIdentity: Bool
    ) -> ActivityItemID {
        if usesExpectedSemanticIdentity,
           case .semanticValue(.contentItem(let contentItemID)) = challenge.expectedAnswer {
            return ActivityItemID(rawValue: contentItemID.rawValue)
        }

        return ActivityItemID(rawValue: challenge.id.rawValue)
    }
}

struct MultipleChoiceView: View {
    private static let practiceIncorrectResetDelay: Duration = .milliseconds(1500)
    private static let practiceCorrectAdvanceDelay: Duration = .milliseconds(800)

    @State private var session: MultipleChoiceSession
    @State private var attemptIndex = 0
    @State private var challengeStartedAt = Date()
    @StateObject private var speechPlayer: LearningSpeechPlayer
    private let onComplete: () -> Void
    private let onAdvance: () -> Void
    private let onExit: () -> Void
    private let mathActivityFamily: ActivityFamily?
    private let mathLevelID: MathCurriculumLevelID
    private let progressActivityFamily: ActivityFamily?
    private let presentation: MultipleChoicePresentation
    private let onAttempt: (ActivityAttemptData) -> Void
    private let makeNextSession: (() -> MultipleChoiceSession?)?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase

    init(
        session: MultipleChoiceSession,
        mathActivityFamily: ActivityFamily? = nil,
        mathLevelID: MathCurriculumLevelID = .m1,
        progressActivityFamily: ActivityFamily? = nil,
        presentation: MultipleChoicePresentation = .standard,
        onAttempt: @escaping (ActivityAttemptData) -> Void = { _ in },
        makeNextSession: (() -> MultipleChoiceSession?)? = nil,
        onComplete: @escaping () -> Void = {},
        onAdvance: @escaping () -> Void = {},
        onExit: @escaping () -> Void = {}
    ) {
        _session = State(initialValue: session)
        _speechPlayer = StateObject(wrappedValue: LearningSpeechPlayer())
        self.mathActivityFamily = mathActivityFamily
        self.mathLevelID = mathLevelID
        self.progressActivityFamily = progressActivityFamily ?? mathActivityFamily
        self.presentation = presentation
        self.onAttempt = onAttempt
        self.makeNextSession = makeNextSession
        self.onComplete = onComplete
        self.onAdvance = onAdvance
        self.onExit = onExit
    }

    private struct PendingTaskKey: Hashable {
        let action: MultipleChoicePendingAction?
        let active: Bool
    }
    @StateObject private var feedbackSoundPlayer = LanguageFeedbackSoundPlayer()
    @State private var feedbackStartedAt = Date()
    /// Minik's reaction on a Language choice page. Unlike the answer's result it can
    /// outlast the word: Android's success jump and streak stars play to the end over
    /// the next word.
    @State private var reaction: MultipleChoiceAnswerResult?
    @State private var successAsset = MinikVisualAsset.success
    @State private var successDirection: Double = 1
    @Environment(\.languageWordBonusRun) private var bonusRun
    @State private var feedbackBonusRun = 0
    @Environment(\.interfaceLocaleID) private var interfaceLocaleID
    @Environment(\.languageEncouragementEnabled) private var encouragementEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isLanguageChoice: Bool {
        mathActivityFamily == nil && presentation != .standard
    }

    var body: some View {
        Group {
            if isLanguageChoice {
                LanguageChoicePage(
                    challenge: session.currentChallenge, presentation: presentation,
                    result: session.answerResult, reaction: reaction,
                    selectedChoiceID: session.selectedChoiceID,
                    canSelect: session.canSelectChoices,
                    canSkip: session.canAdvanceManually,
                    feedbackStartedAt: feedbackStartedAt,
                    successAsset: successAsset, successDirection: successDirection,
                    feedbackBonusRun: feedbackBonusRun, encouragementEnabled: encouragementEnabled,
                    onSelect: selectChoice, onReplay: replayLanguagePrompt,
                    onSkip: advance, onExit: exitActivity
                )
            } else {
                standardBody
            }
        }
        .task(id: PendingTaskKey(action: session.pendingAction, active: scenePhase == .active)) {
            await handlePendingAction()
        }
        .task(id: feedbackStartedAt) { await clearReactionWhenPlayed() }
        .task(id: session.currentChallenge.id) { speakCurrentPrompt() }
        .mathReadAloud(
            instruction: mathActivityFamily == nil ? nil : mathChoiceInstruction,
            exercise: mathActivityFamily == nil
                ? nil
                : MathReadAloud.exercise(session.currentChallenge.prompt.representations),
            id: session.currentChallenge.id
        )
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { stopAudio() }
        }
        .onDisappear(perform: stopAudio)
    }

    private var standardBody: some View {
        MinikPracticeScreen(
            progressLabel: "\(session.currentChallengeIndex + 1) / \(session.challengeCount)",
            onExit: exitActivity
        ) { metrics in
            let compact = metrics.compact

            MinikPracticeSurface(compact: compact) {
                VStack(spacing: compact ? 18 : 24) {
                    promptSection(compact: compact)

                    choiceGrid(availableWidth: metrics.contentMaxWidth, compact: compact)

                    if let answerResult = session.answerResult {
                        MinikFeedbackBadge(isCorrect: answerResult == .correct)
                            .accessibilityLabel(answerResult == .correct
                                ? String(localized: "Correct")
                                : String(localized: "Incorrect, try again"))
                    }

                    if session.canAdvanceManually {
                        Button(action: advance) {
                            Label(session.answerResult == .incorrect
                                ? String(localized: "Skip")
                                : String(localized: "Next"), systemImage: "arrow.forward")
                        }
                        .buttonStyle(MinikPrimaryActionStyle())
                        .accessibilityHint("Moves to the next challenge")
                    }
                }
            }
        }
    }

    private func promptSection(compact: Bool) -> some View {
        VStack(spacing: compact ? 14 : 18) {
            if hasPromptSpeech {
                HStack {
                    Spacer()

                    Button(action: speakCurrentPrompt) {
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

            Text(mathActivityFamily == nil ? presentation.instruction : mathChoiceInstruction)
                .font(.headline.weight(.semibold))
                .foregroundStyle(Color(red: 0.17, green: 0.45, blue: 0.57))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)

            ForEach(
                Array(session.currentChallenge.prompt.representations.enumerated()),
                id: \.offset
            ) { _, representation in
                RepresentationView(
                    representation: representation,
                    context: .multipleChoicePrompt
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, compact ? 4 : 8)
                .accessibilityLabel(promptAccessibilityLabel(for: representation))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func choiceGrid(availableWidth: CGFloat, compact: Bool) -> some View {
        LazyVGrid(
            columns: choiceColumns(for: availableWidth, compact: compact),
            spacing: compact ? 14 : 18
        ) {
            ForEach(session.currentChallenge.choices, id: \.id) { choice in
                Button {
                    selectChoice(choice.id)
                } label: {
                    VStack(spacing: 10) {
                        RepresentationView(
                            representation: choice.representation,
                            context: .multipleChoiceChoice
                        )

                        if choiceFeedbackState(choice) == .correct {
                            Label("Correct", systemImage: "checkmark.circle.fill")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color(red: 0.17, green: 0.61, blue: 0.31))
                        } else if choiceFeedbackState(choice) == .incorrect {
                            Label("Try again", systemImage: "arrow.counterclockwise.circle.fill")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color(red: 0.82, green: 0.38, blue: 0.26))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(RoundedRectangle(cornerRadius: compact ? 24 : 28, style: .continuous))
                }
                .buttonStyle(
                    MinikChoiceButtonStyle(
                        feedbackState: choiceFeedbackState(choice),
                        compact: compact
                    )
                )
                .disabled(!session.canSelectChoices)
                .accessibilityLabel(choiceAccessibilityLabel(for: choice))
                .accessibilityHint(accessibilityHint(for: choice))
            }
        }
    }

    private func choiceColumns(for availableWidth: CGFloat, compact: Bool) -> [GridItem] {
        if dynamicTypeSize >= .accessibility1 {
            return [GridItem(.flexible(minimum: 0, maximum: 320), spacing: compact ? 14 : 18)]
        }

        let minimumWidth: CGFloat = compact ? 132 : 190
        return [GridItem(.adaptive(minimum: minimumWidth, maximum: 320), spacing: compact ? 14 : 18)]
    }

    /// The Math question in words, from what the challenge shows: a picture to
    /// count, a number to match with a picture, or an exercise to solve. A plain
    /// "Choose the answer" did not say what to look for.
    private var mathChoiceInstruction: String {
        let challenge = session.currentChallenge
        let choicesArePictures = !challenge.choices.isEmpty
            && challenge.choices.allSatisfy { Self.isPictureLike($0.representation) }
        if choicesArePictures {
            return String(localized: "Which picture shows the same amount? Tap it.")
        }
        if challenge.prompt.representations.contains(where: { Self.isPictureLike($0) }) {
            return String(localized: "How many are there? Tap the right number.")
        }
        if challenge.prompt.representations.allSatisfy({ Self.isNumeral($0) }) {
            return String(localized: "Which card is worth the same as this number? Tap it.")
        }
        return String(localized: "Solve it, then tap the right answer.")
    }

    private static func isPictureLike(_ representation: Representation) -> Bool {
        switch representation {
        case .imageAsset, .visualQuantity:
            return true
        case .math(let math):
            switch math {
            case .quantity, .groupedQuantity, .equalGroups, .placeValue:
                return true
            default:
                return false
            }
        default:
            return false
        }
    }

    private static func isNumeral(_ representation: Representation) -> Bool {
        if case .math(let math) = representation, case .numeral = math {
            return true
        }
        return false
    }

    private func choiceFeedbackState(_ choice: Choice) -> MinikChoiceButtonStyle.FeedbackState {
        guard let selectedChoiceID = session.selectedChoiceID,
              selectedChoiceID == choice.id else {
            return .idle
        }

        switch session.answerResult {
        case .correct?:
            return .correct
        case .incorrect?:
            return .incorrect
        case nil:
            return .selected
        }
    }

    private func accessibilityHint(for choice: Choice) -> String {
        switch choiceFeedbackState(choice) {
        case .correct:
            return String(localized: "Correct answer selected")
        case .incorrect:
            return String(localized: "Incorrect answer selected")
        case .selected:
            return String(localized: "Selected")
        case .idle:
            return String(localized: "Double tap to choose")
        }
    }

    @MainActor
    private func advance() {
        advance(challengeID: session.currentChallenge.id)
    }

    @MainActor
    private func advance(challengeID: ChallengeID) {
        let previousIndex = session.currentChallengeIndex
        let wasComplete = session.isComplete
        let didComplete = session.advanceIfCurrentChallengeMatches(challengeID)
        let didAdvance = session.currentChallengeIndex != previousIndex
            || (!wasComplete && session.isComplete)

        if didAdvance {
            // Android's nextWord hides the try-again artwork but lets the success jump
            // and the streak stars finish over the next word (clearReactionWhenPlayed
            // removes them). With Reduce Motion the success artwork stands still at the
            // bottom of the board, so it leaves with the finished word instead of
            // covering the new word's answers.
            if reaction != .correct || reduceMotion {
                reaction = nil
            }
            attemptIndex = 0
            challengeStartedAt = Date()
            onAdvance()
        }
        if didComplete {
            if let nextSession = makeNextSession?() { session = nextSession; return }
            onComplete()
        }
    }

    @MainActor
    private func handlePendingAction() async {
        guard scenePhase == .active, let pendingAction = session.pendingAction else {
            return
        }

        switch pendingAction {
        case .resetAfterIncorrect(let challengeID):
            try? await Task.sleep(for: Self.practiceIncorrectResetDelay)
            guard !Task.isCancelled else {
                return
            }
            session.resetTransientIncorrectAttempt(for: challengeID)
            challengeStartedAt = Date()

        case .advanceAfterCorrect(let challengeID):
            try? await Task.sleep(for: Self.practiceCorrectAdvanceDelay)
            guard !Task.isCancelled else {
                return
            }

            if isLanguageChoice {
                await speechPlayer.waitUntilFinished()
                guard !Task.isCancelled, scenePhase == .active else { return }
            }
            advance(challengeID: challengeID)
        }
    }

    private func selectChoice(_ choiceID: ChoiceID) {
        let challenge = session.currentChallenge
        guard session.canSelectChoices,
              let selectedChoice = challenge.choices.first(where: { $0.id == choiceID }) else {
            return
        }
        session.selectChoice(choiceID)
        if mathActivityFamily == nil,
           let cue = selectedChoice.learningSpeechCue {
            speechPlayer.speak(cue)
        }
        guard let result = session.answerResult else { return }
        if isLanguageChoice {
            feedbackStartedAt = Date()
            reaction = result
            if result == .correct {
                feedbackBonusRun = bonusRun == .max ? .max : bonusRun + 1
                successAsset = feedbackBonusRun >= 5 ? LanguagePracticeArtwork.successStreak
                    : (Bool.random() ? MinikVisualAsset.success : LanguagePracticeArtwork.successTwo)
                successDirection = Bool.random() ? 1 : -1
            }
            let sound: LanguageFeedbackSound = result == .correct
                ? (feedbackBonusRun >= 3 ? .streak : (presentation.usesPictureAnswers ? .correctPicture : .correct)) : .incorrect
            feedbackSoundPlayer.play(sound)
            if result == .correct, encouragementEnabled {
                speechPlayer.enqueuePracticeEncouragement(cleanRun: feedbackBonusRun, interfaceLocale: interfaceLocaleID)
            }
        }
        attemptIndex += 1
        guard let family = progressActivityFamily,
              let attempt = ActivityAttemptData(
                  itemID: MultipleChoiceAttemptIdentity.itemID(
                      for: challenge,
                      usesExpectedSemanticIdentity: presentation.usesExpectedSemanticProgressIdentity
                  ),
                  attemptIndex: attemptIndex,
                  result: result == .correct ? .correct : .incorrect,
                  responseDurationSeconds: Date().timeIntervalSince(challengeStartedAt),
                  activityFamily: family,
                  mathLevelID: mathActivityFamily == nil ? nil : mathLevelID,
                  skillID: challenge.primarySkill
              ) else { return }
        onAttempt(attempt)
    }

    private var hasPromptSpeech: Bool {
        mathActivityFamily == nil && session.currentChallenge.prompt.learningSpeechCue != nil
    }

    private func promptAccessibilityLabel(for representation: Representation) -> String {
        if presentation == .firstLetterPictureToLetter || presentation == .pictureToWord,
           case .imageAsset = representation,
           let speechCue = session.currentChallenge.prompt.learningSpeechCue {
            return speechCue.text
        }

        return representation.accessibilityDescription
    }

    private func choiceAccessibilityLabel(for choice: Choice) -> String {
        if presentation == .firstLetterLetterToPicture || presentation == .wordToPicture,
           case .imageAsset = choice.representation,
           let speechCue = choice.learningSpeechCue {
            return speechCue.text
        }

        return choice.representation.accessibilityDescription
    }

    private func speakCurrentPrompt() {
        guard mathActivityFamily == nil,
              let cue = session.currentChallenge.prompt.learningSpeechCue else {
            return
        }
        speechPlayer.speak(cue)
    }

    /// Android's speaker does nothing while the finished word's success speech plays
    /// (WriteScreen's talkingThusCantPlayWord), so a tap can neither cut the
    /// encouragement off nor hurry the next word.
    private func replayLanguagePrompt() {
        guard session.answerResult != .correct else { return }
        speakCurrentPrompt()
    }

    /// Removes Minik's reaction once it has played: Android's try-again artwork after
    /// 1.5 seconds; the success jump, and the streak stars when they twinkle, when they
    /// finish, even after the next word has appeared.
    @MainActor
    private func clearReactionWhenPlayed() async {
        guard let shown = reaction else { return }
        try? await Task.sleep(for: .seconds(reactionSeconds(for: shown)))
        guard !Task.isCancelled else { return }
        reaction = nil
    }

    private func reactionSeconds(for shown: MultipleChoiceAnswerResult) -> Double {
        guard shown == .correct else { return 1.5 }
        let stars: Double = feedbackBonusRun >= 3 ? (encouragementEnabled ? 4 : 1.2) : 0
        return max(LanguageSuccessJump.duration, stars)
    }

    private func stopAudio() {
        speechPlayer.stop()
        feedbackSoundPlayer.stop()
    }

    private func exitActivity() {
        stopAudio()
        onExit()
    }
}
