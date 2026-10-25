import SwiftUI

enum MathBuildPresentation: Hashable {
    case standard
    case answerTokenTower
    case word
}

struct BuildView: View {
    @State private var session: BuildSession
    @State private var attemptIndex = 0
    @State private var challengeStartedAt = Date()
    @StateObject private var speechPlayer: LearningSpeechPlayer
    @State private var languageAttemptTracker = LanguageOrderedTokenAttemptTracker()
    @State private var languagePresentationIndex = 1
    @State private var languagePoolTracker: LanguageAutoPoolTracker?
    @Environment(\.layoutDirection) private var interfaceLayoutDirection
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let onComplete: () -> Void
    private let onAdvance: () -> Void
    private let onExit: () -> Void
    private let mathActivityFamily: ActivityFamily?
    private let mathLevelID: MathCurriculumLevelID
    private let progressActivityFamily: ActivityFamily?
    private let presentation: MathBuildPresentation
    private let onAttempt: (ActivityAttemptData) -> Void
    private let onLanguagePoolExhausted: (LanguageAutoPoolBoundary) -> Void
    private let nextLanguageAutoEvaluationLevel: () -> LanguageVocabularyLevel?

    init(
        session: BuildSession,
        mathActivityFamily: ActivityFamily? = nil,
        mathLevelID: MathCurriculumLevelID = .m1,
        progressActivityFamily: ActivityFamily? = nil,
        presentation: MathBuildPresentation = .standard,
        onAttempt: @escaping (ActivityAttemptData) -> Void = { _ in },
        onWordCompleted: @escaping (LanguageWordCompletion) -> Void = { _ in },
        languageAutoEvaluationLevel: LanguageVocabularyLevel? = nil,
        onLanguagePoolExhausted: @escaping (LanguageAutoPoolBoundary) -> Void = { _ in },
        nextLanguageAutoEvaluationLevel: @escaping () -> LanguageVocabularyLevel? = { nil },
        makeNextSession: (() -> BuildSession?)? = nil,
        onComplete: @escaping () -> Void = {},
        onAdvance: @escaping () -> Void = {},
        onExit: @escaping () -> Void = {}
    ) {
        _session = State(initialValue: session)
        _speechPlayer = StateObject(wrappedValue: LearningSpeechPlayer())
        _languagePoolTracker = State(initialValue: Self.makeLanguagePoolTracker(
            session: session,
            evaluatedLevel: languageAutoEvaluationLevel
        ))
        self.mathActivityFamily = mathActivityFamily
        self.mathLevelID = mathLevelID
        self.progressActivityFamily = progressActivityFamily ?? mathActivityFamily
        self.presentation = presentation
        self.onAttempt = onAttempt
        self.onLanguagePoolExhausted = onLanguagePoolExhausted
        self.nextLanguageAutoEvaluationLevel = nextLanguageAutoEvaluationLevel
        self.onWordCompleted = onWordCompleted
        self.makeNextSession = makeNextSession
        self.onComplete = onComplete
        self.onAdvance = onAdvance
        self.onExit = onExit
    }

    private struct AdvanceTaskKey: Hashable {
        let challenge: ChallengeID?
        let active: Bool
    }
    private struct FeedbackTaskKey: Hashable {
        let id: UUID?
        let active: Bool
    }
    @State private var languageFeedback: BuildAnswerResult?
    @State private var languageFeedbackID: UUID?
    @State private var feedbackStartedAt = Date()
    @State private var wordCompletionID = UUID()
    @State private var feedbackBonusRun = 0
    @State private var successAsset = MinikVisualAsset.success
    @State private var successDirection: Double = 1
    @Environment(\.languageWordBonusRun) private var bonusRun
    @StateObject private var feedbackSoundPlayer = LanguageFeedbackSoundPlayer()
    @Environment(\.interfaceLocaleID) private var interfaceLocaleID
    @Environment(\.languageEncouragementEnabled) private var encouragementEnabled
    private let onWordCompleted: (LanguageWordCompletion) -> Void
    private let makeNextSession: (() -> BuildSession?)?

    private var isLanguageBuild: Bool {
        mathActivityFamily == nil && presentation == .word && session.currentChallenge.languageWordContent != nil
    }

    var body: some View {
        Group {
            if isLanguageBuild {
                LanguageBuildPage(
                    session: session,
                    clue: LanguageWordBuildClue.make(for: session.currentChallenge, interfaceLocale: interfaceLocaleID),
                    feedback: languageFeedback, feedbackStartedAt: feedbackStartedAt,
                    successAsset: successAsset, successDirection: successDirection,
                    feedbackBonusRun: feedbackBonusRun, encouragementEnabled: encouragementEnabled,
                    canSkip: session.hasIncorrectAttempt && session.answerResult == nil,
                    onSelect: { id in
                        if let token = session.currentChallenge.availableTokens.first(where: { $0.id == id }) {
                            selectToken(token)
                        }
                    },
                    onReplay: replayLanguagePrompt, onSkip: advance, onExit: exitActivity
                )
            } else { standardBody }
        }
        .task(id: AdvanceTaskKey(challenge: automaticAdvanceChallengeID, active: scenePhase == .active)) {
            guard scenePhase == .active, let challengeID = automaticAdvanceChallengeID else { return }
            do {
                try await Task.sleep(nanoseconds: 800_000_000)
                if isLanguageBuild { await speechPlayer.waitUntilFinished() }
                guard !Task.isCancelled, scenePhase == .active,
                      session.currentChallenge.id == challengeID else { return }
                advance()
            } catch { }
        }
        .task(id: FeedbackTaskKey(id: languageFeedbackID, active: scenePhase == .active)) {
            guard scenePhase == .active, languageFeedback != nil, let id = languageFeedbackID else { return }
            let seconds = languageFeedbackSeconds
            do {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                guard !Task.isCancelled, languageFeedbackID == id else { return }
                languageFeedback = nil
            } catch { }
        }
        .task(id: session.currentChallenge.id) { speakCurrentPrompt() }
        // App Store screenshot staging: the word half built.
        .task { await stageStoreScreenshotWord() }
        .mathReadAloud(
            instruction: mathInstruction,
            exercise: isMath ? MathReadAloud.exercise(session.currentChallenge.prompt.representations) : nil,
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

                    constructedSequenceSection(compact: compact)

                    availableTokenSection(compact: compact)

                    feedbackSection(compact: compact)
                }
            }
        }
    }

    private var selectedTokens: [BuildToken] {
        let tokensByID = Dictionary(
            uniqueKeysWithValues: session.currentChallenge.availableTokens.map { ($0.id, $0) }
        )
        return session.selectedTokenIDs.compactMap { tokensByID[$0] }
    }

    private var remainingTokens: [BuildToken] {
        let selectedIDs = Set(session.selectedTokenIDs)
        let tokensByID = Dictionary(
            uniqueKeysWithValues: session.currentChallenge.availableTokens.map { ($0.id, $0) }
        )
        return session.tokenPresentationOrder.compactMap { tokenID in
            guard !selectedIDs.contains(tokenID) else {
                return nil
            }
            return tokensByID[tokenID]
        }
    }

    private var canSubmit: Bool {
        session.selectedTokenIDs.count == session.currentChallenge.expectedTokenSequence.count
    }

    private var automaticAdvanceChallengeID: ChallengeID? {
        guard session.currentChallenge.validationMode == .immediatePrefix,
              session.answerResult == .correct else {
            return nil
        }
        return session.currentChallenge.id
    }

    private var tokenLayoutDirection: LayoutDirection {
        let directions = session.currentChallenge.availableTokens.compactMap {
            explicitDirection(for: $0.representation)
        }
        guard directions.count == session.currentChallenge.availableTokens.count,
              let direction = directions.first,
              directions.allSatisfy({ $0 == direction }) else {
            return interfaceLayoutDirection
        }
        return direction.layoutDirection
    }

    private func explicitDirection(for representation: Representation) -> ContentDirection? {
        switch representation {
        case .learningText(let text):
            text.direction
        case .mathExpression, .math:
            .leftToRight
        default:
            nil
        }
    }

    private var tokenColumns: [GridItem] {
        if dynamicTypeSize >= .accessibility1 {
            return [GridItem(.flexible(minimum: 0, maximum: 280), spacing: 12)]
        }

        return [GridItem(.adaptive(minimum: 88, maximum: 168), spacing: 12)]
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
                    .accessibilityLabel("Replay current word")
                    .accessibilityHint("Speaks the current word again")
                }
            }

            Text(presentation == .word
                ? String(localized: "Build the word")
                : presentation == .answerTokenTower
                ? String(localized: "Build the answer")
                : mathActivityFamily == .buildMath
                ? mathLevelID == .m1
                    ? String(localized: "Build the count")
                    : String(localized: "Build the answer")
                : mathActivityFamily == .buildNumber
                    ? String(localized: "Build the number")
                    : String(localized: "Build the answer"))
                .font(.headline.weight(.semibold))
                .foregroundStyle(Color(red: 0.17, green: 0.45, blue: 0.57))
                .accessibilityHidden(true)

            if let mathInstruction {
                Text(mathInstruction)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MathInk.softInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
            }

            ForEach(
                Array(session.currentChallenge.prompt.representations.enumerated()),
                id: \.offset
            ) { _, representation in
                RepresentationView(
                    representation: representation,
                    context: .buildPrompt
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, compact ? 4 : 8)
                .accessibilityLabel(promptAccessibilityLabel(for: representation))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func constructedSequenceSection(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 12 : 14) {
            Text(isMath
                ? String(localized: "Your answer")
                : presentation == .word
                ? String(localized: "Your word")
                : String(localized: "Your build"))
                .font(.headline.weight(.semibold))
                .foregroundStyle(Color(red: 0.18, green: 0.43, blue: 0.54))
                .fixedSize(horizontal: false, vertical: true)

            if presentation == .word,
               let builtDisplayText = session.builtDisplayText,
               !builtDisplayText.isEmpty {
                Text(builtDisplayText)
                    .font(.system(size: compact ? 30 : 38, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .environment(\.layoutDirection, tokenLayoutDirection)
                    .accessibilityHidden(true)
            }

            VStack(spacing: 0) {
                if isMath && selectedTokens.isEmpty {
                    // A full-width, wrapping hint; inside a grid cell it was cut off after a word.
                    mathAnswerPlaceholder(compact: compact)
                } else {
                    LazyVGrid(columns: tokenColumns, alignment: .center, spacing: 12) {
                        if selectedTokens.isEmpty {
                            placeholderToken(compact: compact)
                        } else {
                            ForEach(selectedTokens, id: \.id) { token in
                                if isMath {
                                    // Not disabled after the check, so the answer keeps full
                                    // contrast; removeConstructedToken ignores taps then.
                                    Button {
                                        removeConstructedToken(token.id)
                                    } label: {
                                        tokenChip(token, context: .buildConstructedToken, compact: compact)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityHint(session.answerResult == nil
                                        ? String(localized: "Takes this piece back out of your answer")
                                        : String(localized: "Unavailable after answer is checked"))
                                } else {
                                    tokenChip(token, context: .buildConstructedToken, compact: compact)
                                }
                            }
                        }
                    }
                    .environment(\.layoutDirection, tokenLayoutDirection)
                }
            }
            .frame(maxWidth: .infinity, minHeight: compact ? 78 : 92, alignment: .topLeading)
            .padding(compact ? 14 : 18)
            .background(
                RoundedRectangle(cornerRadius: compact ? 24 : 28, style: .continuous)
                    .fill(Color(red: 0.93, green: 0.98, blue: 1.0).opacity(0.9))
            )
            .overlay {
                RoundedRectangle(cornerRadius: compact ? 24 : 28, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.92), lineWidth: 1.2)
            }
            .dropDestination(for: String.self) { identifiers, _ in
                guard let identifier = identifiers.first,
                      let token = remainingTokens.first(where: {
                          $0.id.rawValue == identifier
                      }) else { return false }
                selectToken(token)
                return true
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(presentation == .word
            ? String(localized: "Your word")
            : String(localized: "Constructed answer"))
        .accessibilityValue(session.builtDisplayText ?? "")
    }

    private func availableTokenSection(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 12 : 14) {
            Text(availableTokensTitle)
                .font(.headline.weight(.semibold))
                .foregroundStyle(Color(red: 0.18, green: 0.43, blue: 0.54))
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(columns: tokenColumns, spacing: 12) {
                ForEach(remainingTokens, id: \.id) { token in
                    // Every piece is a visible card that a tap adds and that can also
                    // be dragged into the answer box. Build Number's digits used to be
                    // drag-only text without a tile, which Dark Mode turned invisible.
                    Button {
                        selectToken(token)
                    } label: {
                        RepresentationView(
                            representation: token.representation,
                            context: .buildToken
                        )
                        .frame(maxWidth: .infinity, minHeight: compact ? 40 : 44)
                    }
                    .buttonStyle(MinikTokenButtonStyle(compact: compact))
                    .draggable(token.id.rawValue)
                    .disabled(session.answerResult != nil)
                    .accessibilityHint(session.answerResult == nil
                        ? String(localized: "Adds this token to the answer")
                        : String(localized: "Unavailable after answer is checked"))
                }
            }
            .environment(\.layoutDirection, tokenLayoutDirection)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func feedbackSection(compact: Bool) -> some View {
        if let answerResult = session.answerResult {
            MinikFeedbackBadge(isCorrect: answerResult == .correct)
                .accessibilityLabel(answerResult == .correct
                    ? String(localized: "Correct")
                    : String(localized: "Incorrect"))

            if session.currentChallenge.validationMode == .submitSequence {
                Button(action: answerResultAction) {
                    Label(
                        answerResult == .incorrect && mathActivityFamily != nil
                            ? String(localized: "Try again")
                            : String(localized: "Next"),
                        systemImage: answerResult == .incorrect && mathActivityFamily != nil
                            ? "arrow.counterclockwise"
                            : "arrow.forward"
                    )
                }
                .buttonStyle(MinikPrimaryActionStyle())
                .accessibilityHint("Moves to the next challenge")
            }
        } else if session.currentChallenge.validationMode == .submitSequence {
            if isMath && hasTooManyPieces {
                // Check only appears when the answer has as many pieces as it needs,
                // so a child who added one too many is told how to fix it.
                Text(String(localized: "That's too many. Tap one in your answer to take it back."))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MathInk.warning)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
            }

            HStack(spacing: 12) {
                Button(action: { session.undoLastToken() }) {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(MinikUtilityButtonStyle())
                .disabled(session.selectedTokenIDs.isEmpty)
                .accessibilityHint("Removes the last token you added")

                if canSubmit {
                    if presentation == .answerTokenTower {
                        MathSubmitBuzzer(action: submit)
                    } else {
                        Button(action: submit) {
                            Label(
                                isMath ? String(localized: "Check answer") : String(localized: "Submit"),
                                systemImage: "checkmark"
                            )
                        }
                        .buttonStyle(MinikPrimaryActionStyle())
                        .accessibilityHint("Checks the answer you built")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        } else if session.lastSelectionResult == .incorrect {
            VStack(spacing: compact ? 12 : 14) {
                MinikFeedbackBadge(isCorrect: false)
                    .accessibilityLabel("Incorrect, try again")

                Button(action: advance) {
                    Label("Next", systemImage: "arrow.forward")
                }
                .buttonStyle(MinikUtilityButtonStyle())
                .accessibilityHint("Skips to the next challenge")
            }
        }
    }

    private func tokenChip(
        _ token: BuildToken,
        context: RepresentationView.Context,
        compact: Bool
    ) -> some View {
        RepresentationView(
            representation: token.representation,
            context: context
        )
        .frame(maxWidth: .infinity, minHeight: compact ? 40 : 44)
        .padding(.horizontal, compact ? 10 : 14)
        .padding(.vertical, compact ? 10 : 12)
        .background(
            RoundedRectangle(cornerRadius: compact ? 20 : 24, style: .continuous)
                .fill(Color.white.opacity(0.96))
        )
        .overlay {
            RoundedRectangle(cornerRadius: compact ? 20 : 24, style: .continuous)
                .strokeBorder(Color(red: 0.76, green: 0.88, blue: 0.97), lineWidth: 1.1)
        }
    }

    private func placeholderToken(compact: Bool) -> some View {
        RoundedRectangle(cornerRadius: compact ? 20 : 24, style: .continuous)
            .fill(Color.white.opacity(0.55))
            .frame(minHeight: compact ? 60 : 72)
            .overlay {
                Text("Choose tokens to build your answer")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(red: 0.33, green: 0.56, blue: 0.66))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
    }

    private var isMath: Bool {
        mathActivityFamily != nil
    }

    private var hasTooManyPieces: Bool {
        session.selectedTokenIDs.count > session.currentChallenge.expectedTokenSequence.count
    }

    /// The always-visible "what to do" line of the Math build screens.
    private var mathInstruction: String? {
        guard let family = mathActivityFamily else { return nil }
        if presentation == .answerTokenTower {
            return String(localized: "Tap the blocks in order to build the answer.")
        }
        switch family {
        case .buildNumber:
            if mathLevelID == .m1 {
                return String(localized: "Count the pictures, then tap or drag the matching number into the answer box.")
            }
            if mathLevelID == .m2 {
                return String(localized: "Solve the exercise, then tap or drag the answer into the answer box.")
            }
            return String(localized: "Find the answer, then tap or drag its digits into the answer box, in order.")
        case .buildMath:
            if mathLevelID == .m1 {
                return String(localized: "Count the pictures: tap the numbers in order, 1, 2, 3…, until every picture is counted.")
            }
            return String(localized: "Build the whole exercise: tap the pieces in the right order. One piece is extra.")
        default:
            return nil
        }
    }

    private var availableTokensTitle: String {
        if presentation == .answerTokenTower {
            return isMath ? String(localized: "Blocks to use") : String(localized: "Available blocks")
        }
        if mathActivityFamily == .buildNumber {
            return String(localized: "Tap or drag a number")
        }
        if mathActivityFamily == .buildMath {
            return mathLevelID == .m1
                ? String(localized: "Tap the numbers in order")
                : String(localized: "Tap the pieces in order")
        }
        return session.currentChallenge.validationMode == .submitSequence
            ? String(localized: "Pick tokens")
            : String(localized: "Tap the next token")
    }

    private func mathAnswerPlaceholder(compact: Bool) -> some View {
        Text(mathActivityFamily == .buildNumber
            ? String(localized: "Put the number here")
            : String(localized: "Your answer will appear here"))
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(MathInk.softInk)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: compact ? 60 : 72)
            .background(
                RoundedRectangle(cornerRadius: compact ? 20 : 24, style: .continuous)
                    .fill(Color.white.opacity(0.7))
            )
            .overlay {
                RoundedRectangle(cornerRadius: compact ? 20 : 24, style: .continuous)
                    .strokeBorder(MathInk.rim, style: StrokeStyle(lineWidth: 2, dash: [7, 6]))
            }
    }

    /// Takes one piece back out of a Math answer and keeps the pieces after it in
    /// order. BuildSession can only undo the last piece, so the later pieces are
    /// undone and then added again.
    private func removeConstructedToken(_ tokenID: BuildTokenID) {
        guard session.answerResult == nil,
              session.currentChallenge.validationMode == .submitSequence,
              let index = session.selectedTokenIDs.firstIndex(of: tokenID) else { return }
        let laterTokenIDs = Array(session.selectedTokenIDs.suffix(from: index + 1))
        for _ in index..<session.selectedTokenIDs.count {
            session.undoLastToken()
        }
        for laterTokenID in laterTokenIDs {
            session.selectToken(laterTokenID)
        }
    }

    private func advance() {
        let previousIndex = session.currentChallengeIndex
        let wasComplete = session.isComplete
        session.nextChallenge()
        let didAdvance = session.currentChallengeIndex != previousIndex
            || (!wasComplete && session.isComplete)

        if didAdvance {
            languagePresentationIndex = languagePresentationIndex == .max ? .max : languagePresentationIndex + 1
            // Android's success jump and streak stars keep playing over the next word;
            // the feedback task removes them when they finish. With Reduce Motion the
            // success artwork stands still at the bottom of the board, so it leaves with
            // the finished word instead of covering the new word's letters.
            if languageFeedback != .correct || reduceMotion {
                languageFeedback = nil
                languageFeedbackID = nil
            }
            wordCompletionID = UUID()
            attemptIndex = 0
            challengeStartedAt = Date()
            onAdvance()
        }
        if !wasComplete && session.isComplete {
            if var tracker = languagePoolTracker,
               let boundary = tracker.takeBoundary(isExhausted: true) {
                languagePoolTracker = tracker
                onLanguagePoolExhausted(boundary)
            }
            if let nextSession = makeNextSession?() {
                session = nextSession
                languagePoolTracker = Self.makeLanguagePoolTracker(
                    session: nextSession,
                    evaluatedLevel: nextLanguageAutoEvaluationLevel()
                        ?? languagePoolTracker?.evaluatedLevel
                )
                return
            }
            onComplete()
        }
    }

    private func submit() {
        let challenge = session.currentChallenge
        attemptIndex += 1
        session.submit()
        guard let family = progressActivityFamily,
              let result = session.answerResult,
              let attempt = ActivityAttemptData(
                  itemID: ActivityItemID(rawValue: challenge.id.rawValue),
                  attemptIndex: attemptIndex,
                  result: result == .correct ? .correct : .incorrect,
                  responseDurationSeconds: Date().timeIntervalSince(challengeStartedAt),
                  activityFamily: family,
                  mathLevelID: mathActivityFamily == nil ? nil : mathLevelID,
                  skillID: challenge.primarySkill
              ) else { return }
        onAttempt(attempt)
    }

    private func answerResultAction() {
        if session.answerResult == .incorrect, mathActivityFamily != nil {
            session.retryCurrentChallenge()
            challengeStartedAt = Date()
        } else {
            advance()
        }
    }

    private var hasPromptSpeech: Bool {
        mathActivityFamily == nil && session.currentChallenge.prompt.learningSpeechCue != nil
    }

    private func speakCurrentPrompt() {
        guard mathActivityFamily == nil,
              let cue = session.currentChallenge.prompt.learningSpeechCue else {
            return
        }
        speechPlayer.speak(cue)
    }

    /// How long Language feedback stays on the board: Android's try-again artwork for
    /// 1.4 seconds; Minik's success jump, and the streak stars when they twinkle,
    /// until they finish, even after the next word has appeared.
    private var languageFeedbackSeconds: TimeInterval {
        guard languageFeedback == .correct else { return 1.4 }
        let stars: TimeInterval = feedbackBonusRun >= 3 ? (encouragementEnabled ? 4 : 1.2) : 0
        return max(LanguageSuccessJump.duration, stars)
    }

    /// Android's speaker does nothing while the finished word's success speech
    /// plays (WriteScreen's talkingThusCantPlayWord), so a tap cannot cut it off.
    private func replayLanguagePrompt() {
        guard session.answerResult != .correct else { return }
        speakCurrentPrompt()
    }

    /// The "language.wordBuild" screenshot (see StoreScreenshotScene) shows the first
    /// half of the word's letters placed, short of finishing it, with no feedback.
    @MainActor
    private func stageStoreScreenshotWord() async {
        guard StoreScreenshotScene.name == "language.wordBuild", isLanguageBuild else { return }
        try? await Task.sleep(nanoseconds: 800_000_000)
        let expected = session.currentChallenge.expectedTokenSequence
        guard !Task.isCancelled,
              session.currentChallenge.validationMode == .immediatePrefix,
              session.selectedTokenIDs.isEmpty,
              expected.count > 1 else { return }
        for tokenID in expected.prefix(min(max(2, expected.count / 2), expected.count - 1)) {
            session.selectToken(tokenID)
        }
    }

    private func selectToken(_ token: BuildToken) {
        let challenge = session.currentChallenge
        let tokenIndex = session.selectedTokenIDs.count
        let responseDurationSeconds = Date().timeIntervalSince(challengeStartedAt)
        let shouldRecordLanguageAttempt = challenge.validationMode == .immediatePrefix
            && challenge.languageWordContent != nil
            && session.answerResult == nil
            && !session.selectedTokenIDs.contains(token.id)
            && challenge.availableTokens.contains(where: { $0.id == token.id })
        if isLanguageBuild && !shouldRecordLanguageAttempt { return }
        session.selectToken(token.id)
        if isLanguageBuild {
            if session.lastSelectionResult == .incorrect {
                languageFeedback = .incorrect
                languageFeedbackID = UUID()
                feedbackStartedAt = Date()
                feedbackSoundPlayer.play(.incorrect)
            } else if session.answerResult == .correct {
                languageFeedback = .correct
                languageFeedbackID = UUID()
                feedbackStartedAt = Date()
                feedbackBonusRun = session.hasIncorrectAttempt ? 0 : (bonusRun == .max ? .max : bonusRun + 1)
                successAsset = feedbackBonusRun >= 5 ? LanguagePracticeArtwork.successStreak
                    : (Bool.random() ? MinikVisualAsset.success : LanguagePracticeArtwork.successTwo)
                successDirection = Bool.random() ? 1 : -1
                feedbackSoundPlayer.play(feedbackBonusRun >= 3 ? .streak : .correct)
            }
            // A correct letter leaves the try-again artwork (and the previous word's
            // success jump) on the board until its time is up, as Android does.
        }

        if shouldRecordLanguageAttempt,
           let contentItemID = challenge.languageWordContent?.contentItemID,
           let result = session.lastSelectionResult,
           let family = progressActivityFamily,
           let attempt = languageAttemptTracker.makeAttempt(
               presentationIndex: languagePresentationIndex,
               contentItemID: contentItemID,
               tokenIndex: tokenIndex,
               result: result == .correct ? .correct : .incorrect,
               responseDurationSeconds: responseDurationSeconds,
               activityFamily: family,
               skillID: challenge.primarySkill,
               languageVocabularyLevel: LanguageVocabularyLevel(
                   curriculumStageID: challenge.curriculumStage
               )
           ) {
            onAttempt(attempt)
            challengeStartedAt = Date()
        }

        if isLanguageBuild, shouldRecordLanguageAttempt, session.answerResult == .correct,
           let content = challenge.languageWordContent {
            onWordCompleted(LanguageWordCompletion(
                id: wordCompletionID,
                contentItemID: content.contentItemID,
                hadIncorrectLetter: session.hasIncorrectAttempt,
                vocabularyLevel: LanguageVocabularyLevel(
                    curriculumStageID: challenge.curriculumStage
                )
            ))
        }
        if isLanguageBuild {
            // Android's WriteScreen says nothing for a letter tap: a right letter only
            // fades and a wrong one gets the reject haptic and the failure sound. A
            // finished word speaks the app-language clue when it differs from the
            // learned language (the Hebrew word in the Hebrew app, nothing in the
            // English one), then the encouragement.
            if session.answerResult == .correct {
                var cues: [LearningSpeechUtterance] = []
                let clue = LanguageWordBuildClue.make(for: challenge, interfaceLocale: interfaceLocaleID)
                if let hostCue = clue.text?.learningSpeechCue {
                    cues.append(hostCue)
                }
                speechPlayer.speak(cues)
                if encouragementEnabled {
                    speechPlayer.enqueuePracticeEncouragement(cleanRun: feedbackBonusRun, interfaceLocale: interfaceLocaleID)
                }
            }
            return
        }
        guard mathActivityFamily == nil,
              let cue = token.representation.learningSpeechCue else {
            return
        }
        if session.answerResult == .correct,
           let wordCue = challenge.prompt.learningSpeechCue {
            speechPlayer.speak([cue, wordCue])
        } else {
            speechPlayer.speak(cue)
        }
    }

    private func promptAccessibilityLabel(for representation: Representation) -> String {
        if presentation == .word,
           case .imageAsset = representation,
           let speechCue = session.currentChallenge.prompt.learningSpeechCue {
            return speechCue.text
        }

        return representation.accessibilityDescription
    }

    private func stopAudio() {
        speechPlayer.stop()
        feedbackSoundPlayer.stop()
    }

    private func exitActivity() {
        stopAudio()
        onExit()
    }

    private static func makeLanguagePoolTracker(
        session: BuildSession,
        evaluatedLevel: LanguageVocabularyLevel?
    ) -> LanguageAutoPoolTracker? {
        guard let evaluatedLevel else { return nil }
        let items = session.challenges.compactMap { challenge -> LanguageAutoPoolItem? in
            guard let contentItemID = challenge.languageWordContent?.contentItemID,
                  let level = LanguageVocabularyLevel(
                      curriculumStageID: challenge.curriculumStage
                  ) else { return nil }
            return LanguageAutoPoolItem(
                contentItemID: contentItemID,
                vocabularyLevel: level
            )
        }
        guard items.count == session.challengeCount else { return nil }
        return LanguageAutoPoolTracker(
            activity: .write,
            evaluatedLevel: evaluatedLevel,
            items: items
        )
    }
}
