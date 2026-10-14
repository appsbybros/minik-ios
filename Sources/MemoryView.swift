import Foundation
import SwiftUI

enum MemoryPresentation: Hashable, Sendable {
    case standard
    case languagePicture
}

struct MemoryView: View {
    private struct LanguageMemoryTransition: Hashable {
        let id = UUID()
        let sessionTransition: MemoryAttemptTransition
        let result: MemoryAttemptResult
    }

    private struct LanguageMemoryTaskKey: Hashable {
        let transition: LanguageMemoryTransition?
        let isActive: Bool
    }

    @State private var session: MemorySession
    @State private var attemptIndex = 0
    @State private var attemptStartedAt = Date()
    @State private var pendingLanguageTransition: LanguageMemoryTransition?
    @State private var lastAudibleLanguageTransitionID: UUID?
    @State private var rewardedLanguagePresentationID: UUID?
    @State private var languageCardBackVariant: Int
    @State private var languageCelebration: LanguageMemoryCelebration?
    @State private var languageStatusBlinks = false
    @State private var languageIntroductionSpoken = false
    @StateObject private var speechPlayer: LearningSpeechPlayer
    @StateObject private var feedbackSoundPlayer = LanguageFeedbackSoundPlayer()
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.interfaceLocaleID) private var interfaceLocaleID
    @Environment(\.layoutDirection) private var layoutDirection
    // Android fragment_memory_game type: title, status and pairs rows at
    // 28/20/16 sp on phones, 38/28/28 sp on sw700dp tablets and 42/30/30 sp
    // from sw800dp, with their line heights.
    @ScaledMetric(relativeTo: .largeTitle) private var wideTitleFontSize: CGFloat = 38
    @ScaledMetric(relativeTo: .title) private var wideStatusFontSize: CGFloat = 28
    // The phone sizes of the title, status and pairs rows (the title, title 3 and
    // callout styles), for the design's Fredoka faces.
    @ScaledMetric(relativeTo: .title) private var compactTitleFontSize: CGFloat = 28
    @ScaledMetric(relativeTo: .title3) private var compactStatusFontSize: CGFloat = 20
    @ScaledMetric(relativeTo: .callout) private var compactPairsFontSize: CGFloat = 16
    @ScaledMetric(relativeTo: .title) private var compactTitleLineHeight: CGFloat = 34
    @ScaledMetric(relativeTo: .largeTitle) private var wideTitleLineHeight: CGFloat = 46
    @ScaledMetric(relativeTo: .title3) private var compactStatusLineHeight: CGFloat = 25
    @ScaledMetric(relativeTo: .title) private var wideStatusLineHeight: CGFloat = 34
    @ScaledMetric(relativeTo: .callout) private var compactPairsLineHeight: CGFloat = 21
    private let onComplete: () -> Void
    private let onExit: () -> Void
    private let mathActivityFamily: ActivityFamily?
    private let mathLevelID: MathCurriculumLevelID
    private let progressActivityFamily: ActivityFamily?
    private let presentation: MemoryPresentation
    private let makeNextSession: (() -> MemorySession?)?
    private let onLanguageGameCompleted: (UUID) -> Void
    private let onRoundCompleted: () -> Void
    private let onAttempt: (ActivityAttemptData) -> Void

    init(
        session: MemorySession,
        mathActivityFamily: ActivityFamily? = nil,
        mathLevelID: MathCurriculumLevelID = .m1,
        progressActivityFamily: ActivityFamily? = nil,
        presentation: MemoryPresentation = .standard,
        makeNextSession: (() -> MemorySession?)? = nil,
        onLanguageGameCompleted: @escaping (UUID) -> Void = { _ in },
        onRoundCompleted: @escaping () -> Void = {},
        onAttempt: @escaping (ActivityAttemptData) -> Void = { _ in },
        onComplete: @escaping () -> Void = {},
        onExit: @escaping () -> Void = {}
    ) {
        _session = State(initialValue: session)
        self.mathActivityFamily = mathActivityFamily
        self.mathLevelID = mathLevelID
        self.progressActivityFamily = progressActivityFamily ?? mathActivityFamily
        self.presentation = presentation
        self.makeNextSession = makeNextSession
        self.onLanguageGameCompleted = onLanguageGameCompleted
        self.onRoundCompleted = onRoundCompleted
        self.onAttempt = onAttempt
        _languageCardBackVariant = State(initialValue: Int.random(in: 0 ..< 3))
        _speechPlayer = StateObject(wrappedValue: LearningSpeechPlayer())
        self.onComplete = onComplete
        self.onExit = onExit
    }

    var body: some View {
        Group {
            if presentation == .languagePicture {
                languagePictureBody
            } else {
                standardBody
            }
        }
        .task(id: LanguageMemoryTaskKey(
            transition: pendingLanguageTransition,
            isActive: scenePhase == .active
        )) {
            await performLanguageTransition()
        }
        .onAppear(perform: speakLanguageIntroductionIfNeeded)
        // Android MatchScreen reads the memory instruction when a Math board opens.
        .mathReadAloud(
            instruction: mathActivityFamily == nil
                ? nil
                : String(localized: "Turn over two cards to find a match."),
            exercise: nil,
            id: 0
        )
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                cancelLanguageTransitionForBackground()
                stopAudio()
            }
        }
        .onDisappear {
            pendingLanguageTransition = nil
            stopAudio()
        }
    }

    private var standardBody: some View {
        MinikPracticeScreen(
            progressLabel: "\(session.matchedGroupIndices.count) / \(session.equivalenceSets.count)",
            onExit: exit
        ) { metrics in
            let compact = metrics.compact
            let boardWidth = min(
                metrics.containerWidth - (metrics.horizontalPadding * 2),
                metrics.contentMaxWidth
            )

            MinikPracticeSurface(compact: compact) {
                VStack(spacing: compact ? 18 : 24) {
                    headerSection(compact: compact)

                    memoryBoard(
                        compact: compact,
                        availableWidth: boardWidth
                    )

                    MinikArtworkImage(name: MinikVisualAsset.memoryMascot)
                        .frame(maxWidth: 92)
                        .frame(height: compact ? 86 : 104)

                    if let attemptResult = session.attemptResult {
                        MinikFeedbackBadge(isCorrect: attemptResult == .correct)
                            .accessibilityLabel(
                                attemptResult == .correct
                                    ? String(localized: "Correct match")
                                    : String(localized: "Incorrect match, try again")
                            )

                        continueButton(for: attemptResult)
                    }
                }
            }
        }
    }

    // Android Picture Memory (MemoryGameFragment, single player in Plus) in the
    // rainbow-sky design: the close X in the top end corner, the navy title, the
    // "flip two cards" status, the pairs count and a 3 x 4 board of square cards
    // pinned under them. The lower part of the panel stays free as on Android,
    // which hides the Minik boy in this mode. Larger text shrinks the cards a
    // little instead of pushing the board off the panel; at accessibility sizes
    // the panel scrolls once the cards would get too small. The panel is the glass
    // panel over the sky with the light wash inside it (applyGameBackgrounds).
    private var languagePictureBody: some View {
        LanguageActivityScreen(
            washed: true,
            panelStyle: .rounded,
            minimumContentHeight: { _, wide in wide ? 600 : 540 }
        ) { layout in
            languagePictureContent(layout)
        }
    }

    private func languagePictureContent(_ layout: LanguageActivityLayout) -> some View {
        let metrics = LanguageMemoryBoardMetrics(
            layout: layout,
            cardCount: session.presentedCards.count,
            accessibilityText: dynamicTypeSize.isAccessibilitySize,
            titleLineHeight: layout.wide ? wideTitleLineHeight : compactTitleLineHeight,
            statusLineHeight: layout.wide ? wideStatusLineHeight : compactStatusLineHeight,
            pairsLineHeight: layout.wide ? wideStatusLineHeight : compactPairsLineHeight
        )
        return VStack(spacing: 0) {
            languagePictureTitle(metrics)
                .padding(.top, metrics.titleTop)
            languagePictureStatus(metrics)
                .padding(.top, metrics.statusGap)
            languagePicturePairs(metrics)
                .padding(.top, metrics.pairsGap)
            languageMemoryBoard(metrics)
                .padding(.top, metrics.boardTopGap)
                .padding(.bottom, metrics.boardBottomGap)
        }
        .frame(maxWidth: .infinity, minHeight: layout.height, alignment: .top)
        .overlay {
            languageCelebrationOverlay
        }
        .overlay(alignment: .topTrailing) {
            languageCloseButton(metrics)
        }
    }

    /// The design's navy Fredoka title in place of Android's old gradient one.
    private func languagePictureTitle(_ metrics: LanguageMemoryBoardMetrics) -> some View {
        Text(verbatim: languageTitleText)
            .font(MinikPretty.titleFont(
                metrics.wide ? wideTitleFontSize * metrics.titleScale : compactTitleFontSize
            ))
            .foregroundStyle(MinikPretty.navy)
            .multilineTextAlignment(.center)
            .lineLimit(metrics.accessibilityText ? 2 : 1)
            .minimumScaleFactor(0.5)
            .frame(maxWidth: metrics.titleMaxWidth)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func languagePictureStatus(_ metrics: LanguageMemoryBoardMetrics) -> some View {
        let status = Text(verbatim: languageStatusText)
            .font(MinikPretty.bodyFont(
                metrics.wide ? wideStatusFontSize * metrics.statusScale : compactStatusFontSize
            ))
            .foregroundStyle(MinikPretty.navy)
            .multilineTextAlignment(.center)
        if metrics.accessibilityText {
            languageBlinking(status)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            // Android's fixed 55 dp row: the finished message replaces the
            // instruction without moving the board. Two lines at most.
            languageBlinking(status)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .frame(height: metrics.statusHeight)
        }
    }

    @ViewBuilder
    private func languageBlinking<Content: View>(_ content: Content) -> some View {
        if languageStatusBlinks, !reduceMotion, let celebration = languageCelebration {
            // MemoryGameFragment.endRound blinks the status every 500 ms.
            TimelineView(.periodic(from: celebration.startedAt, by: 0.5)) { timeline in
                let ticks = Int(timeline.date.timeIntervalSince(celebration.startedAt) / 0.5)
                content.opacity(ticks % 2 == 0 ? 1 : 0.35)
            }
        } else {
            content
        }
    }

    @ViewBuilder
    private func languagePicturePairs(_ metrics: LanguageMemoryBoardMetrics) -> some View {
        let pairs = Text(verbatim: languagePairsText)
            .font(MinikPretty.bodyFont(
                metrics.wide ? wideStatusFontSize * metrics.statusScale : compactPairsFontSize
            ))
            .foregroundStyle(MinikPretty.softInk)
            .multilineTextAlignment(.center)
        if metrics.accessibilityText {
            pairs.fixedSize(horizontal: false, vertical: true)
        } else {
            pairs
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    /// Android memory_pictures_one_rrow: "Word Memory" in English, as on the
    /// menu card. Until the shared catalog has that key, other interface
    /// languages keep "Picture Memory", whose translations are Android's.
    private var languageTitleText: String {
        let title = interfaceLocaleID.text("Word Memory")
        if title == "Word Memory", interfaceLocaleID != .english {
            return interfaceLocaleID.text("Picture Memory")
        }
        return title
    }

    /// Android turn_two_cards, also spoken when the game opens: "Flip two
    /// cards" in English. Until the shared catalog has that key, other
    /// interface languages keep the older instruction, whose translations
    /// are Android's.
    private var languageFlipTwoCardsText: String {
        let flip = interfaceLocaleID.text("Flip two cards")
        if flip == "Flip two cards", interfaceLocaleID != .english {
            return interfaceLocaleID.text("Turn over two cards to find a match.")
        }
        return flip
    }

    private var languageStatusText: String {
        guard languageCelebration != nil else {
            return languageFlipTwoCardsText
        }
        // Android finished_with_success. Until the shared catalog translates
        // it, other interface languages show Android's "success" praise.
        let finished = interfaceLocaleID.text("Finished successfully!")
        if finished == "Finished successfully!", interfaceLocaleID != .english {
            return interfaceLocaleID.text("Success!")
        }
        return finished
    }

    /// Android pairs_with_score ("Pairs: 1"). A pair joins the count when its
    /// one-second look ends, as on Android.
    private var languagePairsText: String {
        let matched = session.matchedGroupIndices.count
        let shown = session.attemptResult == .correct ? max(0, matched - 1) : matched
        let count = shown.formatted(.number.locale(interfaceLocaleID.locale))
        return interfaceLocaleID.text("Pairs") + ": " + count
    }

    private func languageCloseButton(_ metrics: LanguageMemoryBoardMetrics) -> some View {
        Button(action: exit) {
            MinikArtworkImage(name: MinikVisualAsset.close)
                .frame(width: metrics.closeSide, height: metrics.closeSide)
                .frame(width: metrics.closeHitSide, height: metrics.closeHitSide)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close exercise")
        .padding(.top, metrics.closeTop)
        .padding(.trailing, metrics.closeTrailing)
    }

    @ViewBuilder
    private var languageCelebrationOverlay: some View {
        if let celebration = languageCelebration {
            ZStack {
                if !reduceMotion {
                    LanguageMemoryConfetti(startedAt: celebration.startedAt)
                }
                LanguageMemorySuccessJump(celebration: celebration)
            }
            .environment(\.layoutDirection, .leftToRight)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func languageMemoryBoard(_ metrics: LanguageMemoryBoardMetrics) -> some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.fixed(metrics.cardSide), spacing: metrics.spacing),
                count: 3
            ),
            spacing: metrics.spacing
        ) {
            ForEach(session.presentedCards, id: \.id) { card in
                languageMemoryCard(card, side: metrics.cardSide)
                    .frame(width: metrics.cardSide, height: metrics.cardSide)
            }
        }
        .frame(width: metrics.boardWidth)
        // A new round lays out fresh face-down cards instead of turning the
        // finished ones back, like Android's newRoundMemory.
        .id(session.presentationID)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func languageMemoryCard(_ card: MemoryCard, side: CGFloat) -> some View {
        let state = session.state(for: card.id) ?? .faceDown
        let button = Button {
            selectCard(card.id)
        } label: {
            LanguageMemoryCardFaces(
                showsFront: state != .faceDown,
                backVariant: languageCardBackVariant,
                front: languageCardPicture(card, side: side)
            )
        }
        .buttonStyle(LanguageMemoryCardStyle(state: state))
        .aspectRatio(1, contentMode: .fit)
        .disabled(state == .matched || pendingLanguageTransition != nil)

        switch state {
        case .faceDown:
            button
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Hidden card")
                .accessibilityValue("Face down")
                .accessibilityHint(accessibilityHint(for: state))
        case .faceUp, .matched:
            button
                .accessibilityElement(children: .combine)
                .accessibilityValue(accessibilityValue(for: state))
                .accessibilityHint(accessibilityHint(for: state))
        }
    }

    /// The revealed face: Android fits the picture into 88% of the card. It is
    /// built for every card so a card turning back still shows its picture
    /// until it is edge-on.
    private func languageCardPicture(_ card: MemoryCard, side: CGFloat) -> some View {
        Group {
            if case .imageAsset(let asset) = card.representation {
                Image(asset.rawValue)
                    .resizable()
                    .scaledToFit()
            } else {
                RepresentationView(
                    representation: card.representation,
                    context: .memoryCard
                )
            }
        }
        .padding(side * 0.06)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func headerSection(compact: Bool) -> some View {
        VStack(spacing: compact ? 10 : 14) {
            Text("Memory")
                .font(.title3.weight(.bold))
                .foregroundStyle(Color(red: 0.15, green: 0.42, blue: 0.54))

            Text("Turn over two cards to find a match.")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color(red: 0.28, green: 0.49, blue: 0.58))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func memoryBoard(
        compact: Bool,
        availableWidth: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: compact ? 12 : 14) {
            Text("Cards")
                .font(.headline.weight(.semibold))
                .foregroundStyle(Color(red: 0.18, green: 0.43, blue: 0.54))

            LazyVGrid(
                columns: cardColumns(for: availableWidth),
                spacing: compact ? 12 : 14
            ) {
                ForEach(session.presentedCards, id: \.id) { card in
                    memoryCard(card, compact: compact)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func cardColumns(for availableWidth: CGFloat) -> [GridItem] {
        let spacing: CGFloat = dynamicTypeSize >= .accessibility1 ? 12 : 14

        if dynamicTypeSize >= .accessibility3 {
            return [GridItem(.flexible(minimum: 0, maximum: 260), spacing: spacing)]
        }

        let minimumWidth: CGFloat
        if dynamicTypeSize >= .accessibility1 {
            minimumWidth = 176
        } else if availableWidth < 430 {
            minimumWidth = 138
        } else if availableWidth < 700 {
            minimumWidth = 156
        } else {
            minimumWidth = 172
        }

        return [GridItem(.adaptive(minimum: minimumWidth, maximum: 220), spacing: spacing)]
    }

    @ViewBuilder
    private func continueButton(for attemptResult: MemoryAttemptResult) -> some View {
        if attemptResult == .correct {
            Button(action: continueAfterAttempt) {
                Label("Continue", systemImage: "arrow.forward")
            }
            .buttonStyle(MinikPrimaryActionStyle())
            .accessibilityHint("Continues after this matching attempt")
        } else {
            Button(action: continueAfterAttempt) {
                Label("Continue", systemImage: "arrow.forward")
            }
            .buttonStyle(MinikUtilityButtonStyle())
            .accessibilityHint("Continues after this matching attempt")
        }
    }

    @ViewBuilder
    private func memoryCard(
        _ card: MemoryCard,
        compact: Bool
    ) -> some View {
        let state = session.state(for: card.id) ?? .faceDown

        let button = Button {
            selectCard(card.id)
        } label: {
            cardContent(card, state: state, compact: compact)
        }
            .buttonStyle(
                MinikMemoryCardStyle(
                    state: cardStyleState(for: state),
                    compact: compact
                )
            )
            .disabled(state == .matched || session.attemptResult != nil)

        switch state {
        case .faceDown:
            button
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Hidden card")
                .accessibilityValue("Face down")
                .accessibilityHint(accessibilityHint(for: state))
        case .faceUp, .matched:
            button
                .accessibilityElement(children: .combine)
                .accessibilityValue(accessibilityValue(for: state))
                .accessibilityHint(accessibilityHint(for: state))
        }
    }

    @ViewBuilder
    private func cardContent(
        _ card: MemoryCard,
        state: MemoryCardState,
        compact: Bool
    ) -> some View {
        switch state {
        case .faceDown:
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityHidden(true)
        case .faceUp, .matched:
            ZStack(alignment: .topTrailing) {
                RepresentationView(
                    representation: card.representation,
                    context: .memoryCard
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if state == .matched {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Color(red: 0.17, green: 0.61, blue: 0.31))
                        .padding(compact ? 4 : 6)
                }
            }
        }
    }

    private func cardStyleState(for state: MemoryCardState) -> MinikMemoryCardStyle.State {
        switch state {
        case .faceDown:
            return .faceDown
        case .faceUp:
            return .faceUp
        case .matched:
            return .matched
        }
    }

    private func accessibilityValue(for state: MemoryCardState) -> String {
        switch state {
        case .faceDown:
            return String(localized: "Face down")
        case .faceUp:
            return String(localized: "Face up")
        case .matched:
            return String(localized: "Matched")
        }
    }

    private func accessibilityHint(for state: MemoryCardState) -> String {
        switch state {
        case .faceDown:
            return session.attemptResult == nil
                ? String(localized: "Double tap to reveal this card")
                : String(localized: "Unavailable until you continue")
        case .faceUp:
            return session.attemptResult == nil
                ? String(localized: "Choose another card to make a pair")
                : String(localized: "Unavailable until you continue")
        case .matched:
            return String(localized: "This card is already matched")
        }
    }

    private func continueAfterAttempt() {
        let wasComplete = session.isComplete
        let matched = session.attemptResult == .correct
        session.continueAfterAttempt()
        if matched { attemptIndex = 0 }
        attemptStartedAt = Date()

        if !wasComplete && session.isComplete {
            speechPlayer.stop()
            onComplete()
        }
    }

    @MainActor
    private func performLanguageTransition() async {
        guard presentation == .languagePicture,
              scenePhase == .active,
              let pending = pendingLanguageTransition else {
            return
        }

        do {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled,
                  pendingLanguageTransition == pending else {
                return
            }

            if lastAudibleLanguageTransitionID != pending.id {
                lastAudibleLanguageTransitionID = pending.id
                feedbackSoundPlayer.play(
                    pending.result == .correct ? .correct : .incorrect
                )
            }

            guard session.continueAfterAttempt(
                matching: pending.sessionTransition
            ) else {
                pendingLanguageTransition = nil
                return
            }
            if pending.result == .correct {
                attemptIndex = 0
            }

            if session.isComplete {
                recordLanguageGameCompletionIfNeeded(
                    presentationID: pending.sessionTransition.presentationID
                )
                // MemoryGameFragment.endRound: Minik jumps, confetti falls,
                // the status blinks and praise is spoken for 5.5 s; then
                // "A new round begins" is spoken and a fresh board starts.
                beginLanguageCelebration()
                try await Task.sleep(nanoseconds: 5_500_000_000)
                guard !Task.isCancelled,
                      pendingLanguageTransition == pending else {
                    return
                }
                languageStatusBlinks = false
                // Android says new_round_starts in the interface language. A
                // language the shared catalog does not translate yet stays
                // silent instead of reading the English words.
                let announcement = interfaceLocaleID.text("A new round begins")
                if interfaceLocaleID == .english || announcement != "A new round begins" {
                    speechPlayer.enqueueInterfaceSpeech(
                        announcement,
                        interfaceLocale: interfaceLocaleID
                    )
                }
                try await Task.sleep(nanoseconds: 1_500_000_000)
                guard !Task.isCancelled,
                      pendingLanguageTransition == pending else {
                    return
                }
                startNextLanguageRound()
            } else {
                if pending.result == .incorrect {
                    try await Task.sleep(nanoseconds: 220_000_000)
                }
                guard !Task.isCancelled,
                      pendingLanguageTransition == pending else {
                    return
                }
                pendingLanguageTransition = nil
                attemptStartedAt = Date()
            }
        } catch {
            // Exit, backgrounding, or a replacement round cancels delayed work.
        }
    }

    private func cancelLanguageTransitionForBackground() {
        guard presentation == .languagePicture,
              let pending = pendingLanguageTransition else {
            return
        }
        pendingLanguageTransition = nil
        let resolved = session.continueAfterAttempt(
            matching: pending.sessionTransition
        )
        if resolved, pending.result == .correct {
            attemptIndex = 0
        }
        if session.isComplete {
            recordLanguageGameCompletionIfNeeded(
                presentationID: pending.sessionTransition.presentationID
            )
            startNextLanguageRound()
        } else if resolved || session.attemptResult == nil {
            attemptStartedAt = Date()
        }
    }

    private func startNextLanguageRound() {
        guard session.isComplete else { return }
        onRoundCompleted()
        pendingLanguageTransition = nil
        languageCelebration = nil
        languageStatusBlinks = false
        attemptIndex = 0
        attemptStartedAt = Date()
        // Android chooses the card back once per visit, not once per round.

        if let nextSession = makeNextSession?() {
            session = nextSession
        } else {
            session.startNewRound()
        }
    }

    private func beginLanguageCelebration() {
        // showMinikPlusAnimation picks one of the three Minik Plus success
        // pictures and a random jump direction.
        let assets = [
            MinikVisualAsset.success,
            LanguagePracticeArtwork.successTwo,
            LanguagePracticeArtwork.successStreak
        ]
        languageCelebration = LanguageMemoryCelebration(
            startedAt: Date(),
            asset: assets.randomElement() ?? MinikVisualAsset.success,
            direction: Bool.random() ? 1 : -1,
            startsAtRight: layoutDirection == .rightToLeft
        )
        languageStatusBlinks = true
        if let phrase = LanguageEncouragementCopy.phrases.randomElement() {
            speechPlayer.enqueueInterfaceSpeech(
                interfaceLocaleID.text(phrase),
                interfaceLocale: interfaceLocaleID
            )
        }
    }

    private func speakLanguageIntroductionIfNeeded() {
        guard presentation == .languagePicture,
              !languageIntroductionSpoken else {
            return
        }
        languageIntroductionSpoken = true
        // MemoryGameFragment speaks speech_turn_two_cards once when the game
        // opens: the status line's words in every interface language except
        // Hebrew, where it asks the child to tap a square to turn it over.
        // That spoken-only Hebrew sentence has no key in the shared catalog,
        // so Android's words are used as they are.
        let introduction: String
        if interfaceLocaleID == .hebrew {
            introduction = "לחצו על משבצת כדי להפוך אותה"
        } else {
            introduction = languageFlipTwoCardsText
        }
        speechPlayer.enqueueInterfaceSpeech(introduction, interfaceLocale: interfaceLocaleID)
    }

    private func recordLanguageGameCompletionIfNeeded(presentationID: UUID) {
        guard presentation == .languagePicture,
              rewardedLanguagePresentationID != presentationID else {
            return
        }
        rewardedLanguagePresentationID = presentationID
        onLanguageGameCompleted(presentationID)
    }

    private func selectCard(_ cardID: MemoryCardID) {
        // Android does not repeat the word when the second card completes
        // its pair; the first card's word keeps playing.
        if let speechCue = session.selectCard(cardID),
           !(presentation == .languagePicture && session.attemptResult == .correct) {
            speechPlayer.speak(speechCue)
        }
        guard let result = session.attemptResult else { return }
        if presentation == .languagePicture,
           let transition = session.pendingTransition {
            pendingLanguageTransition = LanguageMemoryTransition(
                sessionTransition: transition,
                result: result
            )
            if result == .correct,
               session.matchedGroupIndices.count == session.equivalenceSets.count {
                recordLanguageGameCompletionIfNeeded(
                    presentationID: transition.presentationID
                )
            }
        }
        attemptIndex += 1
        let itemNamespace = mathActivityFamily == nil
            ? "language"
            : mathLevelID.rawValue.lowercased()
        guard let family = progressActivityFamily,
              let attempt = ActivityAttemptData(
                  itemID: ActivityItemID(rawValue: "\(itemNamespace).memory.\(cardID.groupIndex)"),
                  attemptIndex: attemptIndex,
                  result: result == .correct ? .correct : .incorrect,
                  responseDurationSeconds: Date().timeIntervalSince(attemptStartedAt),
                  activityFamily: family,
                  mathLevelID: mathActivityFamily == nil ? nil : mathLevelID,
                  skillID: mathActivityFamily == nil ? nil : MathSkillIDs.equivalentValues
              ) else { return }
        onAttempt(attempt)
    }

    private func exit() {
        pendingLanguageTransition = nil
        stopAudio()
        onExit()
    }

    private func stopAudio() {
        speechPlayer.stop()
        feedbackSoundPlayer.stop()
    }
}

private struct LanguageMemoryCardStyle: ButtonStyle {
    let state: MemoryCardState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .scaleEffect(configuration.isPressed && !reduceMotion ? pressedScale : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.1),
                value: configuration.isPressed
            )
    }

    /// Only a card the child can still turn over reacts to a press.
    private var pressedScale: CGFloat {
        guard state == .faceDown else {
            return 1
        }
        return 0.97
    }
}

/// MemoryGameFragment.flipCard: the shown face turns edge-on in 90 ms and the
/// other face turns in during the next 90 ms. Reduce Motion swaps at once.
private struct LanguageMemoryCardFaces<Front: View>: View {
    let showsFront: Bool
    let backVariant: Int
    let front: Front

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if showsFront {
                frontFace
                    .transition(turnTransition)
            } else {
                backFace
                    .transition(turnTransition)
            }
        }
        .animation(reduceMotion ? nil : .linear(duration: 0.18), value: showsFront)
    }

    private var turnTransition: AnyTransition {
        guard !reduceMotion else {
            return .identity
        }
        let turnIn = AnyTransition.modifier(
            active: LanguageMemoryCardTurn(degrees: -90),
            identity: LanguageMemoryCardTurn(degrees: 0)
        )
        let turnOut = AnyTransition.modifier(
            active: LanguageMemoryCardTurn(degrees: 90),
            identity: LanguageMemoryCardTurn(degrees: 0)
        )
        return .asymmetric(
            insertion: turnIn.animation(.linear(duration: 0.09).delay(0.09)),
            removal: turnOut.animation(.linear(duration: 0.09))
        )
    }

    // bg_memory_card_face_pretty: the picture on a white card (15 dp corners)
    // inside a lavender-to-sky rim, 3 dp at the top and sides and 4 dp at the
    // bottom (18 dp corners).
    private var frontFace: some View {
        front
            .background {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(Color.white)
            }
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .padding(EdgeInsets(top: 3, leading: 3, bottom: 4, trailing: 3))
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [LanguageSkyPalette.frameStart, LanguageSkyPalette.frameEnd],
                            startPoint: UnitPoint.leading,
                            endPoint: UnitPoint.trailing
                        )
                    )
                    .shadow(color: MinikPretty.navy.opacity(0.12), radius: 4, x: 0, y: 3)
            }
    }

    // The pretty card back (Android's memory_card_back_pretty, a pastel card
    // with Minik peeking up): a pastel card with a white rim, a soft dashed
    // stitch and a smiling star in the middle.
    private var backFace: some View {
        let card = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return card
            .fill(
                LinearGradient(
                    colors: LanguageMemoryCardPalette.backColors(variant: backVariant),
                    startPoint: UnitPoint.topLeading,
                    endPoint: UnitPoint.bottomTrailing
                )
            )
            .overlay {
                MinikArtworkImage(name: LanguageMemoryCardPalette.backStar(variant: backVariant))
                    .scaleEffect(0.56)
                    .shadow(color: MinikPretty.navy.opacity(0.18), radius: 3, x: 0, y: 2)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        Color.white.opacity(0.7),
                        style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                    )
                    .padding(6)
            }
            .overlay {
                card
                    .strokeBorder(Color.white, lineWidth: 2.5)
            }
            .background {
                card
                    .fill(Color.white)
                    .shadow(color: MinikPretty.navy.opacity(0.14), radius: 4, x: 0, y: 3)
            }
    }
}

private struct LanguageMemoryCardTurn: ViewModifier {
    let degrees: Double

    func body(content: Content) -> some View {
        content.rotation3DEffect(.degrees(degrees), axis: (x: 0, y: 1, z: 0))
    }
}

/// The three pastel card backs, one chosen per visit as Android chooses its card
/// back: lavender with a yellow star, pink with a purple star and sky blue with a
/// pink star.
private enum LanguageMemoryCardPalette {
    static func backColors(variant: Int) -> [Color] {
        switch variant {
        case 1:
            return [
                Color(red: 255 / 255, green: 230 / 255, blue: 242 / 255),
                Color(red: 251 / 255, green: 207 / 255, blue: 228 / 255)
            ]
        case 2:
            return [
                Color(red: 227 / 255, green: 244 / 255, blue: 255 / 255),
                Color(red: 195 / 255, green: 227 / 255, blue: 251 / 255)
            ]
        default:
            return [
                Color(red: 241 / 255, green: 232 / 255, blue: 255 / 255),
                Color(red: 220 / 255, green: 203 / 255, blue: 255 / 255)
            ]
        }
    }

    static func backStar(variant: Int) -> String {
        switch variant {
        case 1:
            return LanguagePracticeArtwork.starFacePrefix + "1"
        case 2:
            return LanguagePracticeArtwork.starFacePrefix + "5"
        default:
            return LanguagePracticeArtwork.starFacePrefix + "6"
        }
    }
}

private struct LanguageMemoryCelebration: Equatable {
    let startedAt: Date
    let asset: String
    let direction: Double
    /// Android's picture box rests at the panel's start edge: the right edge
    /// in right-to-left interfaces.
    let startsAtRight: Bool
}

/// MemoryGameFragment.playSuccessJumpAnimation: the 200 x 265 Minik Plus
/// picture rises from below the panel, arcs high over the board in 1.55 s and
/// leaves on the far side. Reduce Motion shows it standing at the bottom for
/// those 1.55 s.
private struct LanguageMemorySuccessJump: View {
    let celebration: LanguageMemoryCelebration

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private static let duration: TimeInterval = 1.55

    private struct Sample {
        let center: CGPoint
        let scale: Double
        let rotation: Double
        let opacity: Double
    }

    var body: some View {
        GeometryReader { geometry in
            if reduceMotion {
                // Android shows the picture only while it jumps; afterwards
                // the finished board is uncovered again. The timeline updates
                // when the celebration starts and again at 1.55 s.
                TimelineView(.periodic(from: celebration.startedAt, by: Self.duration)) { timeline in
                    let elapsed = timeline.date.timeIntervalSince(celebration.startedAt)
                    artwork
                        .opacity(elapsed < Self.duration - 0.05 ? 1 : 0)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 60, paused: scenePhase != .active)) { timeline in
                    let pose = Self.sample(
                        elapsed: timeline.date.timeIntervalSince(celebration.startedAt),
                        size: geometry.size,
                        direction: celebration.direction,
                        startsAtRight: celebration.startsAtRight
                    )
                    artwork
                        .scaleEffect(CGFloat(pose.scale), anchor: .bottom)
                        .rotationEffect(.degrees(pose.rotation), anchor: .bottom)
                        .opacity(pose.opacity)
                        .position(pose.center)
                }
            }
        }
    }

    private var artwork: some View {
        MinikArtworkImage(name: celebration.asset)
            .padding(8)
            .scaleEffect(x: celebration.direction < 0 ? -1 : 1, y: 1)
            .frame(width: 200, height: 265)
    }

    private static func sample(
        elapsed: TimeInterval,
        size: CGSize,
        direction: Double,
        startsAtRight: Bool
    ) -> Sample {
        let t = min(1, max(0, elapsed / duration))
        let width = Double(size.width)
        let height = Double(size.height)
        // Android moves the 200 dp picture box from its resting place at the
        // start edge by -0.42 to +0.65 panel widths in the jump direction and
        // lifts it 0.9 panel heights at the top of a parabola.
        let restingCenterX = startsAtRight ? width - 100 : 100
        let centerX = restingCenterX + direction * width * (-0.42 + 1.07 * t)
        let sink = 198.75 * t
        let lift = 3.6 * height * t * (1 - t)
        let top = height + 12 + sink - lift

        let scale: Double
        if t < 0.16 {
            scale = 0.84 + 0.22 * (t / 0.16)
        } else if t < 0.48 {
            scale = 1.06 - 0.06 * ((t - 0.16) / 0.32)
        } else {
            scale = 1 - 0.09 * ((t - 0.48) / 0.52)
        }

        let rotation: Double
        if t < 0.48 {
            rotation = direction * (-7 + 10 * (t / 0.48))
        } else {
            rotation = direction * (3 - 8 * ((t - 0.48) / 0.52))
        }

        let opacity: Double
        if t < 0.08 {
            opacity = t / 0.08
        } else if t > 0.82 {
            opacity = max(0, (1 - t) / 0.18)
        } else {
            opacity = 1
        }

        return Sample(
            center: CGPoint(x: centerX, y: top + 132.5),
            scale: scale,
            rotation: rotation,
            opacity: opacity
        )
    }
}

/// ConfettiRectView.start(3f) over the finished board: small yellow and
/// orange rectangles fall from just above the panel for three seconds,
/// growing a little toward the bottom and fading out.
private struct LanguageMemoryConfetti: View {
    let startedAt: Date

    @Environment(\.scenePhase) private var scenePhase

    private static let palette: [Color] = [
        Color(red: 1.0, green: 0.757, blue: 0.027),
        Color(red: 1.0, green: 0.627, blue: 0.0),
        Color(red: 1.0, green: 0.718, blue: 0.302),
        Color(red: 1.0, green: 0.596, blue: 0.0),
        Color(red: 1.0, green: 0.439, blue: 0.263),
        Color(red: 1.0, green: 0.878, blue: 0.510)
    ]
    // 120 pieces a second for three seconds.
    private static let particleCount = 360
    private static let emittedPerSecond = 120.0
    // Android's 900 px/s² and 90-210 px/s at about 2.7 px per point.
    private static let gravity = 334.0

    var body: some View {
        let seed = UInt64(truncatingIfNeeded: Int64(startedAt.timeIntervalSinceReferenceDate * 1000))
        return TimelineView(.animation(minimumInterval: 1.0 / 60, paused: scenePhase != .active)) { timeline in
            Canvas { context, size in
                Self.drawParticles(
                    in: &context,
                    size: size,
                    elapsed: timeline.date.timeIntervalSince(startedAt),
                    seed: seed
                )
            }
        }
    }

    private static func drawParticles(
        in context: inout GraphicsContext,
        size: CGSize,
        elapsed: TimeInterval,
        seed: UInt64
    ) {
        let width = Double(size.width)
        let height = max(1, Double(size.height))
        for index in 0 ..< particleCount {
            let age = elapsed - Double(index) / emittedPerSecond
            if age < 0 {
                break
            }
            let lifetime = 2.8 + 1.4 * unit(seed, index, 0)
            if age > lifetime {
                continue
            }
            let horizontalSpeed = (unit(seed, index, 1) - 0.5) * 44
            let verticalSpeed = 33 + 45 * unit(seed, index, 2)
            let x = width * unit(seed, index, 3) + horizontalSpeed * age
            let startY = -height * 0.15 * unit(seed, index, 4)
            let fallen = verticalSpeed * age + 0.5 * gravity * age * age
            let y = startY + fallen
            let base = 3 + 4 * unit(seed, index, 5)
            let stretch: Double
            if unit(seed, index, 6) < 0.35 {
                stretch = 1.8 + 1.4 * unit(seed, index, 7)
            } else {
                stretch = 0.9 + 0.7 * unit(seed, index, 7)
            }
            let depth = 0.6 + 0.7 * (y / height)
            let particleWidth = base * depth
            let particleHeight = base * stretch * depth
            if y - particleHeight > height {
                continue
            }
            let progress = age / lifetime
            let spin = (unit(seed, index, 9) - 0.5) * 540 * age
            let rotation = 360 * unit(seed, index, 8) + spin
            let colorIndex = Int(unit(seed, index, 10) * Double(palette.count)) % palette.count

            var particle = context
            particle.opacity = max(0, min(1, 1 - progress * progress))
            particle.translateBy(x: CGFloat(x), y: CGFloat(y))
            particle.rotate(by: .degrees(rotation))
            let rectangle = CGRect(
                x: -particleWidth / 2,
                y: -particleHeight / 2,
                width: particleWidth,
                height: particleHeight
            )
            particle.fill(
                Path(roundedRect: rectangle, cornerRadius: 2),
                with: .color(palette[colorIndex])
            )
        }
    }

    /// A stable pseudo-random value in 0..<1 for one particle property, so a
    /// redraw never reshuffles the confetti.
    private static func unit(_ seed: UInt64, _ index: Int, _ channel: UInt64) -> Double {
        var value = seed
        value = value &+ UInt64(truncatingIfNeeded: index) &* 0x9E37_79B9_7F4A_7C15
        value = value &+ channel &* 0xD1B5_4A32_D192_ED03
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        value = value ^ (value >> 31)
        return Double(value >> 11) / 9_007_199_254_740_992.0
    }
}

/// fragment_memory_game geometry in points. Phones place the cards 28 pt
/// inside the panel (12 + 10 dp padding and 6 dp card margins) with 12 pt
/// gaps; sw600dp centres a board three quarters of the panel wide. The square
/// cards stay in Android's three columns and shrink only when the text rows
/// leave too little height.
private struct LanguageMemoryBoardMetrics {
    let wide: Bool
    let accessibilityText: Bool
    /// Multipliers for the iPad title and status sizes: 1 for Android's
    /// sw700dp 38 / 28 sp, and 42 / 38 and 30 / 28 for its sw800dp 42 / 30 sp.
    let titleScale: CGFloat
    let statusScale: CGFloat
    let titleTop: CGFloat
    let titleMaxWidth: CGFloat
    let statusGap: CGFloat
    let statusHeight: CGFloat
    let pairsGap: CGFloat
    let boardTopGap: CGFloat
    let boardBottomGap: CGFloat
    let closeSide: CGFloat
    let closeHitSide: CGFloat
    let closeTop: CGFloat
    let closeTrailing: CGFloat
    let columns: Int
    let spacing: CGFloat
    let cardSide: CGFloat

    var boardWidth: CGFloat {
        cardSide * CGFloat(columns) + spacing * CGFloat(columns - 1)
    }

    init(
        layout: LanguageActivityLayout,
        cardCount: Int,
        accessibilityText: Bool,
        titleLineHeight: CGFloat,
        statusLineHeight: CGFloat,
        pairsLineHeight: CGFloat
    ) {
        let wide = layout.wide
        // iPads at least 800 pt wide (a content width of about 700 pt) take
        // Android's sw800dp text sizes; the iPad mini keeps sw700dp's.
        let largeTablet = wide && layout.width >= 680
        let titleScale: CGFloat = largeTablet ? 42.0 / 38.0 : 1
        let statusScale: CGFloat = largeTablet ? 30.0 / 28.0 : 1
        let scaledTitleLineHeight = titleLineHeight * titleScale
        let scaledStatusLineHeight = statusLineHeight * statusScale
        let scaledPairsLineHeight = pairsLineHeight * (wide ? statusScale : 1)
        // The content starts 14 x 8 pt (iPad 21 x 12 pt) inside the panel, so
        // Android's offsets from the card edge are reduced by those insets.
        let titleTop: CGFloat = wide ? 23 : 29
        let statusGap: CGFloat = wide ? 8 : 3
        let pairsGap: CGFloat = 4
        let boardTopGap: CGFloat = wide ? 31 : 22
        let boardBottomGap: CGFloat = 18
        // The red X: 27 dp at 20 dp from the top and end of the phone card
        // (gamesCloseButtonSize is 23 dp on phones under h720dp, which leave
        // less than about 660 pt of panel content here: the iPhone SE and Plus
        // sizes), 45 dp at 25 / 37 dp on sw600dp; the touch area is at least
        // 44 pt. On phones that area reaches a few points past the content
        // edge into the panel's inset, so the X itself keeps Android's 20 dp.
        let phoneCloseSide: CGFloat = layout.height < 660 ? 23 : 27
        let closeSide: CGFloat = wide ? 45 : phoneCloseSide
        let closeHitSide = max(44, closeSide)
        let closeInset = (closeHitSide - closeSide) / 2
        let closeImageTop: CGFloat = wide ? 13 : 12
        let closeImageTrailing: CGFloat = wide ? 16 : 6
        let closeTop = max(0, closeImageTop - closeInset)
        let closeTrailing = closeImageTrailing - closeInset
        let spacing: CGFloat = 12
        let columns = 3

        let statusHeight: CGFloat
        if accessibilityText {
            // The status wraps freely at these sizes; this estimate only
            // decides how far the cards shrink before the panel scrolls.
            statusHeight = scaledStatusLineHeight * 2
        } else {
            let statusLines: CGFloat = wide ? 1 : 2
            statusHeight = max(55, scaledStatusLineHeight * statusLines + 4)
        }
        let textHeight = titleTop + scaledTitleLineHeight + statusGap + statusHeight
            + pairsGap + scaledPairsLineHeight
        let boardMargins = boardTopGap + boardBottomGap + 8
        let availableHeight = max(0, layout.height - textHeight - boardMargins)
        let boardTarget: CGFloat
        if wide {
            boardTarget = min((layout.width + 42) * 0.75, layout.width - 28)
        } else {
            boardTarget = layout.width - 28
        }
        let gaps = spacing * CGFloat(columns - 1)
        let widthLimitedSide = max(0, (boardTarget - gaps) / CGFloat(columns))
        let rows = (max(1, cardCount) + columns - 1) / columns
        let rowGaps = spacing * CGFloat(rows - 1)
        let heightLimitedSide = max(0, (availableHeight - rowGaps) / CGFloat(rows))
        var side = min(widthLimitedSide, heightLimitedSide)
        if accessibilityText {
            // The panel scrolls at these sizes, so the text rows may not
            // squeeze the cards far below their width-limited size.
            side = max(side, widthLimitedSide * 0.75)
        }

        self.wide = wide
        self.accessibilityText = accessibilityText
        self.titleScale = titleScale
        self.statusScale = statusScale
        self.titleTop = titleTop
        self.titleMaxWidth = max(120, layout.width - 2 * (max(0, closeTrailing) + closeHitSide + 4))
        self.statusGap = statusGap
        self.statusHeight = statusHeight
        self.pairsGap = pairsGap
        self.boardTopGap = boardTopGap
        self.boardBottomGap = boardBottomGap
        self.closeSide = closeSide
        self.closeHitSide = closeHitSide
        self.closeTop = closeTop
        self.closeTrailing = closeTrailing
        self.columns = columns
        self.spacing = spacing
        self.cardSide = max(1, side.rounded(.down))
    }
}
