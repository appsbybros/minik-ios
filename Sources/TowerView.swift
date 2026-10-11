import Foundation
import SwiftUI

private enum TowerActivityState: Sendable {
    case valueOrdering(TowerSession)
    case languagePractice(LanguageTowerPracticeSession)

    var currentSession: TowerSession {
        switch self {
        case .valueOrdering(let session):
            return session
        case .languagePractice(let practice):
            return practice.currentSession
        }
    }

    var languageChallengePresentationIndex: Int? {
        guard case .languagePractice(let practice) = self else {
            return nil
        }
        return practice.roundNumber
    }

    mutating func selectComparableItem(_ itemID: ComparableItemID) {
        guard case .valueOrdering(var session) = self else {
            return
        }
        session.selectItem(itemID)
        self = .valueOrdering(session)
    }

    mutating func undoComparableItem() {
        guard case .valueOrdering(var session) = self else {
            return
        }
        session.undoLastItem()
        self = .valueOrdering(session)
    }

    mutating func submitComparableOrder() {
        guard case .valueOrdering(var session) = self else {
            return
        }
        session.submit()
        self = .valueOrdering(session)
    }

    mutating func advanceComparableRound() {
        guard case .valueOrdering(var session) = self else {
            return
        }
        session.nextRound()
        self = .valueOrdering(session)
    }

    @discardableResult
    mutating func placeOrderedBlock(_ blockID: TowerBlockID) -> TowerAnswerResult? {
        guard case .languagePractice(var practice) = self else {
            return nil
        }
        let result = practice.placeBlock(blockID)
        self = .languagePractice(practice)
        return result
    }

    mutating func clearOrderedFeedback() {
        guard case .languagePractice(var practice) = self else {
            return
        }
        practice.clearPlacementFeedback()
        self = .languagePractice(practice)
    }

    var languagePresentationID: UUID? {
        guard case .languagePractice(let practice) = self else {
            return nil
        }
        return practice.presentationID
    }

    var languageLastAdvanceBoundary: LanguageAutoPoolBoundary? {
        guard case .languagePractice(let practice) = self else { return nil }
        return practice.lastAdvanceBoundary
    }

    mutating func takeLanguageCompletion() -> LanguageTowerCompletion? {
        guard case .languagePractice(var practice) = self else {
            return nil
        }
        let completion = practice.takeCompletion()
        self = .languagePractice(practice)
        return completion
    }

    @discardableResult
    mutating func advanceLanguageRound(
        expectedPresentationID: UUID? = nil
    ) -> Bool {
        guard case .languagePractice(var practice) = self,
              practice.advanceToNextRound(
                  expectedPresentationID: expectedPresentationID
              ) else {
            return false
        }
        self = .languagePractice(practice)
        return true
    }
}

struct TowerView: View {
    private enum LanguageStackSlot: Hashable {
        case block(TowerBlock, isBase: Bool)
        case spacer(Int)

        var id: String {
            switch self {
            case .block(let block, _):
                return block.id.rawValue
            case .spacer(let index):
                return "languageTower.spacer.\(index)"
            }
        }
    }

    /// The wait after a finished word before the next one (endRoundRunnable).
    private struct LanguageTowerTransition: Hashable {
        let id = UUID()
        let presentationID: UUID
    }

    /// A wrong letter dropped on the tower, outlined in red for a moment. Each drop
    /// is a new value, so dropping it again restarts the outline.
    private struct LanguageTowerRejection: Equatable {
        let id = UUID()
        let blockID: TowerBlockID
    }

    private struct LanguageTowerTaskKey: Hashable {
        let transition: LanguageTowerTransition?
        let isActive: Bool
    }

    @State private var activityState: TowerActivityState
    @State private var pendingLanguageTransition: LanguageTowerTransition?
    @State private var isDropTargeted = false
    @State private var targetStartedAt = Date()
    @State private var languageAttemptTracker = LanguageOrderedTokenAttemptTracker()
    // The Language Tower board: whether the word's first letter is gliding to the
    // sand (languageBaseLanded drives the glide) and whether it has arrived there,
    // where loose blocks were left, the letter a wrong drop outlines, the tower's
    // flash, the shimmer passes, the confetti and this visit's title colour order.
    @State private var languageBaseLanded = false
    @State private var languageBaseReady = false
    @State private var languageLooseOffsets: [TowerBlockID: CGSize] = [:]
    @State private var languageRejection: LanguageTowerRejection? = nil
    @State private var languageTowerFlash = false
    @State private var languageRuntimeShimmerStart: Date? = nil
    @State private var languageHostWordShimmerStart: Date? = nil
    @State private var languageConfettiStart: Date? = nil
    @State private var languageTitleColorOrder: [Int] = Array(0 ..< 6).shuffled()
    @GestureState private var languageDrag: LanguageTowerDrag? = nil
    // How much body text has grown with Dynamic Type, in percent of the default size.
    @ScaledMetric(relativeTo: .body) private var languageTextPercent: CGFloat = 100
    @StateObject private var speechPlayer: LearningSpeechPlayer
    @StateObject private var feedbackSoundPlayer = LanguageFeedbackSoundPlayer()
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.interfaceLocaleID) private var interfaceLocaleID
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.languageEncouragementEnabled) private var encouragementEnabled
    private let onComplete: () -> Void
    private let onExit: () -> Void
    private let onAttempt: (ActivityAttemptData) -> Void
    private let onLanguageWordCompleted: (LanguageTowerCompletion) -> Void
    private let onLanguagePoolExhausted: (LanguageAutoPoolBoundary) -> Void
    private let makeNextLanguagePracticeSession: (() -> LanguageTowerPracticeSession?)?

    init(
        session: TowerSession,
        onComplete: @escaping () -> Void = {},
        onExit: @escaping () -> Void = {}
    ) {
        _activityState = State(initialValue: .valueOrdering(session))
        _speechPlayer = StateObject(wrappedValue: LearningSpeechPlayer())
        self.onAttempt = { _ in }
        self.onLanguageWordCompleted = { _ in }
        self.onLanguagePoolExhausted = { _ in }
        self.makeNextLanguagePracticeSession = nil
        self.onComplete = onComplete
        self.onExit = onExit
    }

    init(
        languagePracticeSession: LanguageTowerPracticeSession,
        onAttempt: @escaping (ActivityAttemptData) -> Void = { _ in },
        onWordCompleted: @escaping (LanguageTowerCompletion) -> Void = { _ in },
        onPoolExhausted: @escaping (LanguageAutoPoolBoundary) -> Void = { _ in },
        makeNextPracticeSession: (() -> LanguageTowerPracticeSession?)? = nil,
        onExit: @escaping () -> Void = {}
    ) {
        _activityState = State(initialValue: .languagePractice(languagePracticeSession))
        _speechPlayer = StateObject(wrappedValue: LearningSpeechPlayer())
        self.onAttempt = onAttempt
        self.onLanguageWordCompleted = onWordCompleted
        self.onLanguagePoolExhausted = onPoolExhausted
        self.makeNextLanguagePracticeSession = makeNextPracticeSession
        self.onComplete = {}
        self.onExit = onExit
    }

    private var session: TowerSession {
        activityState.currentSession
    }

    var body: some View {
        Group {
            if session.orderedTokenContent != nil {
                languageTowerBody
            } else {
                standardBody
            }
        }
        .task(id: LanguageTowerTaskKey(
            transition: pendingLanguageTransition,
            isActive: scenePhase == .active
        )) {
            await performLanguageTransition()
        }
        .onAppear(perform: speakRoundCue)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                speakRoundCue()
            } else {
                resolveLanguageTransitionForBackground()
                stopActivityAudioAndMotion()
            }
        }
        .onDisappear(perform: stopActivityAudioAndMotion)
    }

    private var standardBody: some View {
        MinikPracticeScreen(
            progressLabel: progressLabel,
            onExit: exitActivity
        ) { metrics in
            let compact = metrics.compact
            let availableWidth = min(
                metrics.containerWidth - (metrics.horizontalPadding * 2),
                metrics.contentMaxWidth
            )

            MinikPracticeSurface(compact: compact) {
                VStack(spacing: compact ? 18 : 24) {
                    promptSection(compact: compact)

                    towerSection(
                        compact: compact,
                        availableWidth: availableWidth
                    )

                    availableBlocksSection(
                        compact: compact,
                        availableWidth: availableWidth
                    )

                    feedbackSection()
                }
            }
        }
    }

    // MARK: - Language Tower (Android LettersTowerFragment)

    /// Android's Letter Tower card (fragment_letters_tower) in the rainbow-sky design:
    /// the speaker and the red X, the title in coloured letter chips, the navy
    /// instruction, the word as it is built, the loose letter blocks, and the tower on
    /// the sand between Minik and the sand pile, on the glass card over the sky.
    /// LanguageTowerMetrics holds Android's sizes and positions.
    @ViewBuilder
    private var languageTowerBody: some View {
        if let content = session.orderedTokenContent {
            LanguageTowerPanel(
                scrolls: dynamicTypeSize.isAccessibilitySize
            ) { panel in
                let plan = languageTowerPromptPlan(content)
                let metrics = languageTowerMetrics(content, plan: plan, panel: panel)
                languageTowerBoard(content, plan: plan, metrics: metrics)
            }
            .task(id: languageRoundKey) {
                await beginLanguageRoundPresentation()
            }
            .task(id: languageRejection) {
                await endLanguageRejection()
            }
        }
    }

    private func languageTowerBoard(
        _ content: TowerOrderedTokenContent,
        plan: LanguageTowerPromptPlan,
        metrics: LanguageTowerMetrics
    ) -> some View {
        ZStack(alignment: .topLeading) {
            languageTowerGround(metrics)

            languageTowerColumn(content, plan: plan, metrics: metrics)
                .accessibilitySortPriority(2)

            languageTowerSpacers(metrics)

            languageTowerLetterBlocks(metrics)
                .accessibilitySortPriority(1)

            // The confetti outlives the finished word: at the next word Android only
            // stops emitting, so the pieces still in the air fall away.
            if let confettiStart = languageConfettiStart {
                LanguageTowerConfettiView(reduceMotion: reduceMotion, startedAt: confettiStart)
                    .id(confettiStart)
                    .frame(width: metrics.width, height: metrics.height)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .task(id: confettiStart) {
                        await endLanguageConfetti(startedAt: confettiStart)
                    }
            }

            languageTowerNavigation(metrics)
                .accessibilitySortPriority(3)
        }
        .frame(width: metrics.width, height: metrics.height, alignment: .topLeading)
        // Every position is worked out left to right; the texts get the interface's
        // direction back in languageTowerColumn.
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .contain)
    }

    /// sand2 across the bottom, Minik sitting with his blocks on the left and the
    /// sand pile on the right: the Plus composition of the reference screenshot.
    private func languageTowerGround(_ metrics: LanguageTowerMetrics) -> some View {
        ZStack(alignment: .topLeading) {
            MinikArtworkImage(name: MinikVisualAsset.towerSand)
                .frame(width: metrics.sandSize.width, height: metrics.sandSize.height)
                .position(metrics.sandCenter)

            MinikArtworkImage(name: MinikVisualAsset.towerMascot)
                .frame(width: metrics.mascotSize.width, height: metrics.mascotSize.height)
                .position(metrics.mascotCenter)

            MinikArtworkImage(name: MinikVisualAsset.towerSandPile)
                .frame(width: metrics.pileSize.width, height: metrics.pileSize.height)
                .position(metrics.pileCenter)
        }
        .frame(width: metrics.width, height: metrics.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// titlesContainer: the title chips, the instruction, the hosting word when
    /// Android shows it, the word built so far and the picture when Android shows it.
    private func languageTowerColumn(
        _ content: TowerOrderedTokenContent,
        plan: LanguageTowerPromptPlan,
        metrics: LanguageTowerMetrics
    ) -> some View {
        let builtText = session.builtDisplayText ?? ""
        let fixedStatusHeight = metrics.fixedStatusHeight
        return VStack(spacing: 0) {
            languageTowerTitle(metrics)
                .padding(.top, metrics.titleTop)

            Text("Drag the letters in the correct order")
                .font(MinikPretty.bodyFont(metrics.instructionFontSize))
                .foregroundStyle(MinikPretty.navy)
                .multilineTextAlignment(.center)
                .lineLimit(fixedStatusHeight == nil ? nil : 2)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: fixedStatusHeight == nil)
                .frame(width: metrics.instructionWidth)
                .frame(height: fixedStatusHeight)
                .padding(.top, metrics.chipGap + metrics.statusMargin)

            if let hostWord = plan.hostWord {
                LanguageTowerShimmerText(
                    text: hostWord,
                    fontSize: metrics.wordFontSize,
                    color: languageTowerHostWordColor,
                    shimmerStart: languageHostWordShimmerStart,
                    castsShadow: true
                )
                .frame(width: metrics.instructionWidth, height: metrics.wordRowHeight)
                .padding(.top, metrics.hostWordMargin)
            }

            LanguageTowerShimmerText(
                text: builtText,
                fontSize: metrics.wordFontSize,
                color: languageTowerRuntimeColor,
                shimmerStart: languageRuntimeShimmerStart,
                castsShadow: false
            )
            .environment(\.layoutDirection, orderedContentLayoutDirection)
            .frame(width: metrics.instructionWidth, height: metrics.wordRowHeight)
            .padding(.top, metrics.runtimeMargin)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(
                format: interfaceLocaleID.text("Built word, %@"),
                builtText
            ))

            if plan.showsImage, let image = content.image {
                RepresentationView(
                    representation: .imageAsset(image),
                    context: .towerPrompt
                )
                .frame(height: metrics.imageHeight)
                .padding(.top, metrics.imageMargin)
            }
        }
        .frame(width: metrics.width)
        .environment(\.layoutDirection, layoutDirection)
    }

    private func languageTowerTitle(_ metrics: LanguageTowerMetrics) -> some View {
        let rows = languageTowerTitleRows(chipsPerRow: metrics.chipsPerRow)
        return VStack(spacing: 0) {
            ForEach(rows) { row in
                HStack(spacing: metrics.chipGap * 2) {
                    ForEach(row.chips) { chip in
                        languageTowerTitleChip(chip, metrics: metrics)
                    }
                }
                .padding(.top, languageTowerTitleRowGap(row, metrics: metrics))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(interfaceLocaleID.text("Letter Tower"))
    }

    /// renderTitleBlocks: one chip per letter and a new line for every word (with a
    /// wrap when a word is wider than the card); the colours start again each word.
    private func languageTowerTitleRows(chipsPerRow: Int) -> [LanguageTowerTitleRow] {
        // Typed, so the compiler picks Collection's split (Substring) over Sequence's.
        let titleWords: [Substring] = interfaceLocaleID.text("Letter Tower")
            .split(whereSeparator: { $0.isWhitespace })
        let words = titleWords.map { Array($0) }
        let perRow = max(1, chipsPerRow)
        var rows: [LanguageTowerTitleRow] = []
        var chipID = 0
        for letters in words {
            var start = 0
            while start < letters.count {
                let end = min(letters.count, start + perRow)
                var chips: [LanguageTowerTitleChip] = []
                for letterIndex in start ..< end {
                    chips.append(LanguageTowerTitleChip(
                        id: chipID,
                        letter: String(letters[letterIndex]),
                        colorIndex: letterIndex
                    ))
                    chipID += 1
                }
                rows.append(LanguageTowerTitleRow(
                    id: rows.count,
                    startsWord: start == 0,
                    chips: chips
                ))
                start = end
            }
        }
        return rows
    }

    private func languageTowerTitleRowGap(
        _ row: LanguageTowerTitleRow,
        metrics: LanguageTowerMetrics
    ) -> CGFloat {
        guard row.id > 0 else {
            return 0
        }
        // The chips' margins, plus the spacer line FlexboxLayout gets between words.
        return metrics.chipGap * (row.startsWord ? 4 : 2)
    }

    /// createTitleBlock: a bold black letter on a coloured chip with 14 dp corners.
    private func languageTowerTitleChip(
        _ chip: LanguageTowerTitleChip,
        metrics: LanguageTowerMetrics
    ) -> some View {
        Text(chip.letter)
            .font(.system(size: metrics.chipFontSize, weight: .bold))
            .foregroundStyle(Color.black)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .offset(y: LanguageTowerGlyph.lift(
                for: chip.letter,
                fontSize: metrics.chipFontSize,
                includesArabic: true
            ))
            .frame(width: metrics.chipSize, height: metrics.chipSize)
            .background(
                RoundedRectangle(cornerRadius: metrics.chipCornerRadius, style: .circular)
                    .fill(languageTowerTitleColor(chip.colorIndex))
            )
            .shadow(
                color: Color.black.opacity(0.22),
                radius: 2.5 * metrics.scale,
                x: 0,
                y: 2 * metrics.scale
            )
            .accessibilityHidden(true)
    }

    /// The speaker (the design's bg_pretty_speaker) at the top start and the red X at
    /// the top end, each with a full-size tap target.
    private func languageTowerNavigation(_ metrics: LanguageTowerMetrics) -> some View {
        let speakerTarget = max(44, metrics.speakerSize)
        let closeTarget = max(44, metrics.closeSize)
        return ZStack(alignment: .topLeading) {
            Button(action: speakRoundCue) {
                // Android's padded ic_lock_silent_mode_off, drawn as on the choice pages:
                // the one-wave glyph in a square of 45% of this 40 dp (60 dp) circle.
                LanguageSkySpeakerFace(diameter: metrics.speakerSize, glyphRatio: 0.45)
                    .frame(width: speakerTarget, height: speakerTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(LanguageSkyPressStyle())
            .accessibilityLabel("Hear the target word")
            .position(metrics.speakerCenter)

            Button(action: exitActivity) {
                MinikArtworkImage(name: MinikVisualAsset.close)
                    .frame(width: metrics.closeSize, height: metrics.closeSize)
                    .frame(width: closeTarget, height: closeTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close exercise")
            .position(metrics.closeCenter)
        }
        .frame(width: metrics.width, height: metrics.height, alignment: .topLeading)
    }

    private func languageTowerSpacers(_ metrics: LanguageTowerMetrics) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(languageStackSlots.enumerated()), id: \.element.id) { slotIndex, slot in
                switch slot {
                case .block:
                    EmptyView()
                case .spacer:
                    // createSpacerLikeNormalBlock: a #F5F5F5 block stands in for a space.
                    RoundedRectangle(cornerRadius: metrics.blockCornerRadius, style: .circular)
                        .fill(Color(white: 0.96))
                        .frame(width: metrics.blockSize, height: metrics.blockSize)
                        .shadow(color: Color.black.opacity(0.14), radius: 2.5, x: 0, y: 2)
                        .position(metrics.towerSlotCenter(slotIndex))
                }
            }
        }
        .frame(width: metrics.width, height: metrics.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func languageTowerLetterBlocks(_ metrics: LanguageTowerMetrics) -> some View {
        let allBlocks = session.orderedTokenRound?.blocks ?? []
        let stackIndices = languageStackIndexByBlockID
        let topStackIndex = languageStackSlots.count - 1
        return ZStack(alignment: .topLeading) {
            ForEach(allBlocks, id: \.id) { block in
                let index = allBlocks.firstIndex(where: { $0.id == block.id }) ?? 0
                languageTowerLetterBlock(
                    block,
                    index: index,
                    stackIndex: stackIndices[block.id],
                    topStackIndex: topStackIndex,
                    metrics: metrics
                )
            }
        }
        .frame(width: metrics.width, height: metrics.height, alignment: .topLeading)
    }

    /// createLetterBlock: a solid colour block with 16 dp corners and a bold black
    /// letter. A loose block follows the finger and rests where it is let go, in
    /// full view (finishLanguageDrag); a placed block sits in its tower slot. One
    /// view per block, so placing it glides it onto the tower.
    ///
    /// No loose letter can end up hidden or out of reach: the letter under the
    /// finger is drawn over everything, the loose letters over the tower (only the
    /// tower's newest block, gliding into place, passes over them, as Android's
    /// bringToFront), and placed blocks let touches through to whatever is under
    /// them, as Android's snapped cards (no touch listener, not clickable) do.
    private func languageTowerLetterBlock(
        _ block: TowerBlock,
        index: Int,
        stackIndex: Int?,
        topStackIndex: Int,
        metrics: LanguageTowerMetrics
    ) -> some View {
        let isPlaced = stackIndex != nil
        let isDragged = languageDrag?.blockID == block.id
        let rejected = languageRejection?.blockID == block.id
        let flashes = isPlaced && languageTowerFlash
        let bumps = flashes && stackIndex == topStackIndex && !reduceMotion
        let corner = metrics.blockCornerRadius
        let letter = block.orderedToken.text
        let center = languageTowerBlockCenter(
            block.id,
            index: index,
            stackIndex: stackIndex,
            metrics: metrics
        )
        let flashDelay = Double(stackIndex ?? 0) * 0.06
        let flashAnimation: Animation? = reduceMotion
            ? nil
            : Animation.easeInOut(duration: 0.18).delay(flashDelay)
        let labelFormat: String
        if let stackIndex {
            labelFormat = stackIndex == 0
                ? interfaceLocaleID.text("Locked base letter %@")
                : interfaceLocaleID.text("Placed letter %@")
        } else {
            labelFormat = interfaceLocaleID.text("Available letter %@")
        }
        let layer: Double
        if isDragged {
            layer = 3
        } else if isPlaced {
            layer = session.acceptedBlockIDs.last == block.id ? 2 : 0
        } else {
            layer = 1
        }

        return Text(letter)
            .font(.system(size: metrics.blockFontSize, weight: .bold))
            .foregroundStyle(Color.black)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .offset(y: LanguageTowerGlyph.lift(
                for: letter,
                fontSize: metrics.blockFontSize,
                includesArabic: false
            ))
            .frame(width: metrics.blockSize, height: metrics.blockSize)
            .background {
                RoundedRectangle(cornerRadius: corner, style: .circular)
                    .fill(languageTowerBlockColor(index: index))
                    .overlay {
                        // flashSnappedLetters: the tower's blocks brighten in turn.
                        RoundedRectangle(cornerRadius: corner, style: .circular)
                            .fill(Color.white.opacity(flashes ? 0.55 : 0))
                            .animation(flashAnimation, value: languageTowerFlash)
                    }
            }
            .overlay {
                if rejected {
                    RoundedRectangle(cornerRadius: corner, style: .circular)
                        .strokeBorder(Color.red, lineWidth: 3)
                }
            }
            .shadow(
                color: Color.black.opacity(isDragged ? 0.3 : 0.24),
                radius: isDragged ? 9 : 4,
                x: 0,
                y: isDragged ? 8 : 3
            )
            .rotationEffect(.degrees(rejected && !reduceMotion ? -4 : 0))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.13), value: rejected)
            .scaleEffect(bumps ? 1.06 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: bumps)
            .position(center)
            .zIndex(layer)
            .gesture(
                languageTowerDrag(block, index: index, metrics: metrics),
                including: isPlaced ? GestureMask.subviews : GestureMask.all
            )
            .allowsHitTesting(!isPlaced)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(format: labelFormat, letter))
            .accessibilityHint(isPlaced ? Text(verbatim: "") : Text("Drag this letter to the tower"))
            .accessibilityAddTraits(isPlaced ? AccessibilityTraits() : AccessibilityTraits.isButton)
            .accessibilityAction {
                _ = placeLanguageBlock(block.id)
            }
            .accessibilityAction(named: "Place in tower") {
                _ = placeLanguageBlock(block.id)
            }
    }

    private func languageTowerBlockCenter(
        _ blockID: TowerBlockID,
        index: Int,
        stackIndex: Int?,
        metrics: LanguageTowerMetrics
    ) -> CGPoint {
        if let stackIndex, stackIndex > 0 || languageBaseLanded || reduceMotion {
            return metrics.towerSlotCenter(stackIndex)
        }
        guard stackIndex == nil else {
            // animateFirstLetterToGroundAndLock: the first letter starts among the
            // loose letters and glides down onto the sand.
            return metrics.looseSlotCenter(index: index, seed: languageRoundSeed)
        }
        let resting = languageLooseRestingCenter(blockID, index: index, metrics: metrics)
        guard let drag = languageDrag, drag.blockID == blockID else {
            return resting
        }
        return metrics.clampedBlockCenter(CGPoint(
            x: resting.x + drag.translation.width,
            y: resting.y + drag.translation.height
        ))
    }

    /// Where a loose letter rests: its own spot, moved by where it was last left.
    /// A place the board no longer allows (the card changed size after the drop)
    /// gives the letter its own spot back, so it is never left under the tower.
    private func languageLooseRestingCenter(
        _ blockID: TowerBlockID,
        index: Int,
        metrics: LanguageTowerMetrics
    ) -> CGPoint {
        let home = metrics.looseSlotCenter(index: index, seed: languageRoundSeed)
        guard let offset = languageLooseOffsets[blockID] else {
            return home
        }
        let resting = metrics.clampedBlockCenter(CGPoint(
            x: home.x + offset.width,
            y: home.y + offset.height
        ))
        return metrics.keepsTowerAndButtonsClear(resting) ? resting : home
    }

    /// Where the other loose letters rest now, so a letter let go never covers one.
    private func languageOtherLooseCenters(
        excluding blockID: TowerBlockID,
        metrics: LanguageTowerMetrics
    ) -> [CGPoint] {
        let allBlocks = session.orderedTokenRound?.blocks ?? []
        let looseIDs = Set(session.availableOrderedBlocks.map(\.id))
        var centers: [CGPoint] = []
        for (index, block) in allBlocks.enumerated() where block.id != blockID && looseIDs.contains(block.id) {
            centers.append(languageLooseRestingCenter(block.id, index: index, metrics: metrics))
        }
        return centers
    }

    private func languageTowerDrag(
        _ block: TowerBlock,
        index: Int,
        metrics: LanguageTowerMetrics
    ) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($languageDrag) { value, state, _ in
                state = LanguageTowerDrag(blockID: block.id, translation: value.translation)
            }
            .onEnded { value in
                finishLanguageDrag(
                    block,
                    index: index,
                    translation: value.translation,
                    metrics: metrics
                )
            }
    }

    /// handleDropSequential: a block let go within 140 dp (200 dp on tablets) of the
    /// next tower slot is tried there. A wrong letter glides back to its own spot
    /// instead of staying on the tower, where the next blocks would bury it. A
    /// letter let go anywhere else stays there, moved just enough to sit clear of
    /// the tower, the speaker, the X and the other loose letters, so every letter
    /// stays in view and can always be picked up again.
    private func finishLanguageDrag(
        _ block: TowerBlock,
        index: Int,
        translation: CGSize,
        metrics: LanguageTowerMetrics
    ) {
        guard session.availableOrderedBlocks.contains(where: { $0.id == block.id }) else {
            return
        }
        let home = metrics.looseSlotCenter(index: index, seed: languageRoundSeed)
        let start = languageLooseRestingCenter(block.id, index: index, metrics: metrics)
        let dropped = metrics.clampedBlockCenter(CGPoint(
            x: start.x + translation.width,
            y: start.y + translation.height
        ))
        // The letter is where the finger left it; any glide starts from there.
        languageLooseOffsets[block.id] = CGSize(
            width: dropped.x - home.x,
            height: dropped.y - home.y
        )
        let others = languageOtherLooseCenters(excluding: block.id, metrics: metrics)
        // Nothing snaps before the first letter has landed as the base: Android's
        // towerStack stays empty until the glide's onAnimationEnd.
        let target = metrics.towerSlotCenter(languageStackSlots.count)
        let triesTower = (languageBaseReady || reduceMotion)
            && abs(dropped.x - target.x) <= metrics.snapThreshold
            && abs(dropped.y - target.y) <= metrics.snapThreshold
        if triesTower {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                _ = placeLanguageBlock(block.id)
            }
            guard session.availableOrderedBlocks.contains(where: { $0.id == block.id }) else {
                return
            }
            // Not the next letter: back to its own spot, or the nearest free place
            // when another letter has been left there. (Neighbouring spots may
            // touch by their few points of jitter; that does not count.)
            let back = metrics.isTaken(home, by: others, room: -3 * metrics.scale)
                ? metrics.restingCenter(near: home, avoiding: others)
                : home
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                languageLooseOffsets[block.id] = CGSize(
                    width: back.x - home.x,
                    height: back.y - home.y
                )
            }
            return
        }
        let resting = metrics.restingCenter(near: dropped, avoiding: others)
        guard resting != dropped else {
            return
        }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            languageLooseOffsets[block.id] = CGSize(
                width: resting.x - home.x,
                height: resting.y - home.y
            )
        }
    }

    private func languageTowerMetrics(
        _ content: TowerOrderedTokenContent,
        plan: LanguageTowerPromptPlan,
        panel: LanguageTowerPanelLayout
    ) -> LanguageTowerMetrics {
        // Typed, so the compiler picks Collection's split (Substring) over Sequence's.
        let titleWords: [Substring] = interfaceLocaleID.text("Letter Tower")
            .split(whereSeparator: { $0.isWhitespace })
        let titleWordLengths = titleWords.map { $0.count }
        let instructionLength = interfaceLocaleID.text("Drag the letters in the correct order").count
        return LanguageTowerMetrics(
            panelWidth: panel.width,
            panelHeight: panel.height,
            wide: panel.wide,
            rightToLeft: layoutDirection == .rightToLeft,
            accessible: dynamicTypeSize.isAccessibilitySize,
            textGrowth: languageTextPercent / 100,
            titleWordLengths: titleWordLengths,
            titleMarginTop: languageTowerTitleMargin(wide: panel.wide),
            instructionLength: instructionLength,
            showsHostWord: plan.hostWord != nil,
            reservesHostWordRow: plan.reservesHostWordRow,
            showsImage: plan.showsImage && content.image != nil,
            wordLength: content.targetText.text.count,
            blockCount: session.orderedTokenRound?.blocks.count ?? 0
        )
    }

    /// tower_letters_blocks_title_margin_top for the interface language (values-iw,
    /// values-ar, values-es, values-pt, values-de, values-nl and their sw600dp files).
    private func languageTowerTitleMargin(wide: Bool) -> CGFloat {
        switch interfaceLocaleID {
        case .hebrew, .spanish:
            return -20
        case .arabic, .portugueseBrazil, .portuguesePortugal:
            return -15
        case .german:
            return wide ? 30 : 5
        case .dutch:
            return wide ? 30 : 0
        case .english, .amharic, .french, .russian:
            return wide ? 0 : -5
        }
    }

    /// createNewRound's prompt rows. Plus reads fluently, so letters of the hosting
    /// word come with neither a picture nor a hosting word; letters of another
    /// language use the picture mode: a Hebrew or English host sees the picture with
    /// the hosting word, any other host the English word.
    private func languageTowerPromptPlan(_ content: TowerOrderedTokenContent) -> LanguageTowerPromptPlan {
        let hostCode = interfaceLocaleID.locale.language.languageCode?.identifier
            ?? interfaceLocaleID.rawValue
        let hostIsHebrewOrEnglish = hostCode == "he" || hostCode == "en"
        // WordItemLoader: the hosting word is Hebrew for a Hebrew host, else English.
        let hostWordLanguage: LanguageIdentifier = hostCode == "he" ? .hebrew : .english
        let learnedCode = content.speechCue.language.rawValue
        // onViewCreated shows the shimmer row unless host and learned languages match.
        let reservesHostWordRow = hostIsHebrewOrEnglish ? hostCode != learnedCode : true
        if hostIsHebrewOrEnglish && content.targetText.language == hostWordLanguage {
            return LanguageTowerPromptPlan(
                hostWord: nil,
                showsImage: false,
                reservesHostWordRow: reservesHostWordRow
            )
        }
        let showsImage = content.image != nil
        let showsHostWord = hostIsHebrewOrEnglish ? showsImage && hostCode != learnedCode : true
        return LanguageTowerPromptPlan(
            hostWord: showsHostWord
                ? languageTowerHostingWord(content, language: hostWordLanguage)
                : nil,
            showsImage: showsImage,
            reservesHostWordRow: reservesHostWordRow
        )
    }

    private func languageTowerHostingWord(
        _ content: TowerOrderedTokenContent,
        language: LanguageIdentifier
    ) -> String? {
        guard let item = LanguageTowerCatalog.itemsByID[content.contentItemID],
              let text = LanguageWordContentProvider.learnedText(for: item, language: language)?.text,
              !text.isEmpty else {
            return nil
        }
        return text.uppercased()
    }

    /// initRound gives the word built so far one of Plus's seven colours.
    private var languageTowerRuntimeColor: Color {
        let colors = LanguageTowerColors.runtime
        return colors[languageRoundSeed % colors.count]
    }

    /// pickKidColor for the hosting word.
    private var languageTowerHostWordColor: Color {
        let colors = LanguageTowerColors.kid
        return colors[(languageRoundSeed / 7) % colors.count]
    }

    /// placeBlocks deals the seven block colours in a new order every word, so no
    /// two letters share a colour while the palette lasts.
    private func languageTowerBlockColor(index: Int) -> Color {
        let palette = languageTowerPalette
        let seed = languageRoundSeed
        let step = 1 + (seed / palette.count) % (palette.count - 1)
        return palette[(seed + index * step) % palette.count]
    }

    private func languageTowerTitleColor(_ colorIndex: Int) -> Color {
        let palette = LanguageTowerColors.title
        let slot = colorIndex % palette.count
        let order = languageTitleColorOrder
        let paletteIndex = order.indices.contains(slot) ? order[slot] : slot
        return palette[paletteIndex % palette.count]
    }

    private var languageRoundKey: String {
        session.orderedTokenRound?.id.rawValue ?? ""
    }

    /// One seed per word, so colours and loose positions hold while it is played.
    private var languageRoundSeed: Int {
        var hash = 5381
        for scalar in languageRoundKey.unicodeScalars {
            hash = (hash &* 33) &+ Int(scalar.value)
        }
        return hash & 0x3FFF_FFFF
    }

    private var languageStackIndexByBlockID: [TowerBlockID: Int] {
        var indices: [TowerBlockID: Int] = [:]
        for (slotIndex, slot) in languageStackSlots.enumerated() {
            if case .block(let block, _) = slot {
                indices[block.id] = slotIndex
            }
        }
        return indices
    }

    private var languageStackSlots: [LanguageStackSlot] {
        guard let content = session.orderedTokenContent else {
            return []
        }
        let acceptedBlocks = session.acceptedOrderedBlocks
        var slots: [LanguageStackSlot] = []
        var acceptedIndex = 0

        for (characterIndex, character) in content.targetText.text.enumerated() {
            if character.isWhitespace {
                if acceptedIndex > 0, acceptedIndex <= acceptedBlocks.count {
                    slots.append(.spacer(characterIndex))
                }
                continue
            }
            guard acceptedBlocks.indices.contains(acceptedIndex) else {
                break
            }
            slots.append(.block(
                acceptedBlocks[acceptedIndex],
                isBase: acceptedIndex == 0
            ))
            acceptedIndex += 1
        }
        return slots
    }

    private var languageTowerPalette: [Color] {
        [
            Color(red: 1.00, green: 0.059, blue: 0.529),
            Color(red: 1.00, green: 0.737, blue: 0.00),
            Color(red: 0.608, green: 0.471, blue: 0.941),
            Color(red: 1.00, green: 0.541, blue: 0.00),
            Color(red: 0.400, green: 0.663, blue: 0.910),
            Color(red: 0.00, green: 0.902, blue: 0.463),
            Color(red: 0.341, green: 0.831, blue: 0.757)
        ]
    }

    /// A new word: the first letter glides from among the loose letters down to the
    /// sand (2.2 s, as animateFirstLetterToGroundAndLock) and the hosting word
    /// shimmers 0.4 s in, as shimmerTitle. Letters snap onto the tower only once the
    /// glide has ended, when Android adds the base to towerStack.
    @MainActor
    private func beginLanguageRoundPresentation() async {
        guard !reduceMotion else {
            languageBaseLanded = true
            languageBaseReady = true
            return
        }
        try? await Task.sleep(nanoseconds: 80_000_000)
        guard !Task.isCancelled else {
            return
        }
        withAnimation(.easeInOut(duration: 2.2)) {
            languageBaseLanded = true
        }
        languageHostWordShimmerStart = Date().addingTimeInterval(0.32)
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        guard !Task.isCancelled else {
            return
        }
        languageHostWordShimmerStart = nil
        try? await Task.sleep(nanoseconds: 200_000_000)
        guard !Task.isCancelled else {
            return
        }
        languageBaseReady = true
    }

    /// The confetti is left out on purpose: it keeps falling into the next word.
    private func resetLanguageRoundPresentation() {
        languageBaseLanded = false
        languageBaseReady = false
        languageLooseOffsets = [:]
        languageRejection = nil
        languageTowerFlash = false
        languageRuntimeShimmerStart = nil
        languageHostWordShimmerStart = nil
    }

    /// A wrong drop's red outline lasts 0.9 s; it never holds up the next drop.
    @MainActor
    private func endLanguageRejection() async {
        guard let rejection = languageRejection else {
            return
        }
        try? await Task.sleep(nanoseconds: 900_000_000)
        guard !Task.isCancelled,
              languageRejection == rejection else {
            return
        }
        languageRejection = nil
    }

    /// The confetti goes once its last pieces have fallen out of the card. With
    /// Reduce Motion it is a still picture, gone when the next word starts.
    @MainActor
    private func endLanguageConfetti(startedAt start: Date) async {
        let lifetime: TimeInterval = reduceMotion
            ? 3
            : LanguageTowerConfettiView.visibleDuration
        let remaining = lifetime - Date().timeIntervalSince(start)
        if remaining > 0 {
            try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
        }
        guard !Task.isCancelled,
              languageConfettiStart == start else {
            return
        }
        languageConfettiStart = nil
    }

    private func flashLanguageTower() {
        guard !reduceMotion else {
            return
        }
        languageTowerFlash = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            languageTowerFlash = false
        }
    }

    private func speakLanguageTowerPraise(_ phrases: [String.LocalizationValue]) {
        guard let phrase = phrases.randomElement() else {
            return
        }
        speechPlayer.enqueueInterfaceSpeech(
            interfaceLocaleID.text(phrase),
            interfaceLocale: interfaceLocaleID
        )
    }

    /// Android announces "A new round begins" before it says the next word.
    private func speakNewRoundCue() {
        guard let cue = session.orderedTokenContent?.speechCue else {
            return
        }
        let announcement = interfaceLocaleID.text("A new round begins")
        speechPlayer.speak([
            LearningSpeechUtterance(
                text: interfaceLocaleID.spokenText(for: announcement),
                language: LanguageIdentifier(rawValue: interfaceLocaleID.rawValue)
            ),
            cue
        ])
    }

    private var progressLabel: String {
        switch session.mechanic {
        case .valueOrdering:
            return "\(session.currentRoundIndex + 1) / \(session.roundCount)"
        case .orderedTokens:
            return "\(session.orderedProgressCount) / \(session.orderedTargetCount)"
        }
    }

    @ViewBuilder
    private func promptSection(compact: Bool) -> some View {
        switch session.mechanic {
        case .valueOrdering:
            VStack(spacing: compact ? 12 : 16) {
                Text("Build the tower")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color(red: 0.17, green: 0.45, blue: 0.57))
                    .accessibilityHidden(true)

                Text("Order from smallest to largest")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color(red: 0.28, green: 0.49, blue: 0.58))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        case .orderedTokens(let content):
            VStack(spacing: compact ? 12 : 16) {
                HStack(alignment: .center, spacing: 14) {
                    Button(action: speakRoundCue) {
                        MinikArtworkImage(name: MinikVisualAsset.speaker)
                            .frame(width: compact ? 42 : 48, height: compact ? 42 : 48)
                    }
                    .buttonStyle(MinikUtilityButtonStyle())
                    .accessibilityLabel("Hear the target word")

                    Text("Build the word tower")
                        .font(compact ? .headline.weight(.bold) : .title3.weight(.bold))
                        .foregroundStyle(Color(red: 0.17, green: 0.45, blue: 0.57))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                    Color.clear
                        .frame(width: compact ? 42 : 48, height: compact ? 42 : 48)
                        .accessibilityHidden(true)
                }

                if let image = content.image {
                    RepresentationView(
                        representation: .imageAsset(image),
                        context: .towerPrompt
                    )
                    .frame(maxWidth: .infinity, minHeight: compact ? 72 : 92)
                }

                RepresentationView(
                    representation: .learningText(content.targetText),
                    context: .towerPrompt
                )
                .font(compact ? .title2.weight(.bold) : .largeTitle.weight(.bold))
                .environment(\.layoutDirection, orderedContentLayoutDirection)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func languageTowerSection(
        compact: Bool,
        availableWidth: CGFloat
    ) -> some View {
        let acceptedBlocks = Array(session.acceptedOrderedBlocks.reversed())
        let lockedBaseID = session.acceptedOrderedBlocks.first?.id
        let sceneHeight: CGFloat = compact ? 360 : 480
        let blockSize = languageTowerBlockSize(
            acceptedCount: acceptedBlocks.count,
            compact: compact
        )

        return VStack(alignment: .leading, spacing: compact ? 10 : 12) {
            Text("Your tower")
                .font(.headline.weight(.semibold))
                .foregroundStyle(Color(red: 0.18, green: 0.43, blue: 0.54))

            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: compact ? 24 : 30, style: .continuous)
                    .fill(Color(red: 0.89, green: 0.95, blue: 1.0))

                MinikArtworkImage(name: MinikVisualAsset.towerSand, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: compact ? 52 : 72)
                    .clipped()

                HStack(alignment: .bottom, spacing: 0) {
                    MinikArtworkImage(name: MinikVisualAsset.towerMascot)
                        .frame(
                            width: compact ? 92 : 142,
                            height: compact ? 142 : 220
                        )

                    Spacer(minLength: compact ? 76 : 112)

                    MinikArtworkImage(name: MinikVisualAsset.towerSandPile)
                        .frame(
                            width: compact ? 86 : 126,
                            height: compact ? 58 : 86
                        )
                }
                .padding(.horizontal, compact ? 8 : 18)
                .padding(.bottom, compact ? 14 : 20)

                VStack(spacing: compact ? 3 : 5) {
                    ForEach(acceptedBlocks, id: \.id) { block in
                        languageTowerBlock(
                            block,
                            size: blockSize,
                            isLockedBase: block.id == lockedBaseID,
                            compact: compact
                        )
                    }
                }
                .frame(maxWidth: min(availableWidth * 0.38, compact ? 126 : 170))
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, compact ? 35 : 50)

                if let builtText = session.builtDisplayText {
                    Text(builtText)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Color(red: 0.18, green: 0.43, blue: 0.54))
                        .environment(\.layoutDirection, orderedContentLayoutDirection)
                        .padding(.top, compact ? 12 : 16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .accessibilityLabel(String(
                            format: String(localized: "Built word, %@"),
                            builtText
                        ))
                }
            }
            .frame(maxWidth: .infinity, minHeight: sceneHeight, maxHeight: sceneHeight)
            .overlay {
                RoundedRectangle(cornerRadius: compact ? 24 : 30, style: .continuous)
                    .strokeBorder(
                        isDropTargeted
                            ? Color(red: 0.23, green: 0.67, blue: 0.45)
                            : Color.white.opacity(0.92),
                        lineWidth: isDropTargeted ? 3 : 1.2
                    )
            }
            .dropDestination(for: String.self) { blockIDs, _ in
                guard let rawValue = blockIDs.first else {
                    return false
                }
                return placeLanguageBlock(rawValue: rawValue)
            } isTargeted: { targeted in
                isDropTargeted = targeted
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: isDropTargeted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Constructed tower")
    }

    private func towerSection(
        compact: Bool,
        availableWidth: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: compact ? 12 : 14) {
            Text("Your tower")
                .font(.headline.weight(.semibold))
                .foregroundStyle(Color(red: 0.18, green: 0.43, blue: 0.54))

            VStack(spacing: 10) {
                switch session.mechanic {
                case .valueOrdering:
                    if selectedItems.isEmpty {
                        RoundedRectangle(cornerRadius: compact ? 20 : 24, style: .continuous)
                            .fill(Color.white.opacity(0.58))
                            .frame(minHeight: compact ? 84 : 96)
                            .overlay {
                                Text("Tap blocks below to stack them in order")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color(red: 0.33, green: 0.56, blue: 0.66))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 16)
                            }
                    } else {
                        ForEach(Array(selectedItems.enumerated()), id: \.element.id) { index, item in
                            towerBlock(
                                item,
                                availableWidth: availableWidth,
                                widthFraction: towerWidthFraction(
                                    for: index,
                                    total: selectedItems.count
                                ),
                                compact: compact
                            )
                        }
                    }
                case .orderedTokens:
                    let blocks = Array(session.acceptedOrderedBlocks.reversed())
                    ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                        towerBlock(
                            representation: block.representation,
                            availableWidth: availableWidth,
                            widthFraction: towerWidthFraction(
                                for: index,
                                total: blocks.count
                            ),
                            compact: compact
                        )
                    }

                    if let builtText = session.builtDisplayText {
                        Text(builtText)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(Color(red: 0.18, green: 0.43, blue: 0.54))
                            .environment(\.layoutDirection, orderedContentLayoutDirection)
                            .accessibilityLabel(String(
                                format: String(localized: "Built word, %@"),
                                builtText
                            ))
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: compact ? 120 : 140, alignment: .bottom)
            .padding(compact ? 14 : 18)
            .background(
                RoundedRectangle(cornerRadius: compact ? 24 : 28, style: .continuous)
                    .fill(Color(red: 0.93, green: 0.98, blue: 1.0).opacity(0.9))
            )
            .overlay {
                RoundedRectangle(cornerRadius: compact ? 24 : 28, style: .continuous)
                    .strokeBorder(
                        isDropTargeted
                            ? Color(red: 0.23, green: 0.67, blue: 0.45)
                            : Color.white.opacity(0.92),
                        lineWidth: isDropTargeted ? 3 : 1.2
                    )
            }
            .dropDestination(for: String.self) { blockIDs, _ in
                guard let rawValue = blockIDs.first else {
                    return false
                }
                return placeLanguageBlock(rawValue: rawValue)
            } isTargeted: { targeted in
                guard session.orderedTokenContent != nil else {
                    return
                }
                isDropTargeted = targeted
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: isDropTargeted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Constructed tower")
    }

    private func availableBlocksSection(
        compact: Bool,
        availableWidth: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: compact ? 12 : 14) {
            Text("Available blocks")
                .font(.headline.weight(.semibold))
                .foregroundStyle(Color(red: 0.18, green: 0.43, blue: 0.54))

            LazyVGrid(
                columns: itemColumns(for: availableWidth),
                spacing: compact ? 12 : 14
            ) {
                switch session.mechanic {
                case .valueOrdering:
                    ForEach(remainingItems, id: \.id) { item in
                        Button {
                            activityState.selectComparableItem(item.id)
                        } label: {
                            RepresentationView(
                                representation: item.representation,
                                context: .towerBlock
                            )
                            .frame(maxWidth: .infinity, minHeight: compact ? 44 : 48)
                        }
                        .buttonStyle(MinikTowerBlockStyle(compact: compact))
                        .disabled(session.answerResult != nil)
                        .accessibilityHint(
                            session.answerResult == nil
                                ? String(localized: "Adds this block to your tower")
                                : String(localized: "Unavailable until you move to the next round")
                        )
                    }
                case .orderedTokens:
                    ForEach(session.availableOrderedBlocks, id: \.id) { block in
                        availableLetterBlock(block, compact: compact)
                            .draggable(block.id.rawValue) {
                                availableLetterBlock(block, compact: compact)
                                    .frame(width: compact ? 92 : 108)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(String(
                                format: String(localized: "Letter %@"),
                                block.orderedToken.text
                            ))
                            .accessibilityHint("Drag this letter to the tower")
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction(named: "Place in tower") {
                                _ = placeLanguageBlock(block.id)
                            }
                            .allowsHitTesting(session.answerResult == nil)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func feedbackSection() -> some View {
        switch session.mechanic {
        case .valueOrdering:
            if let answerResult = session.answerResult {
                MinikFeedbackBadge(isCorrect: answerResult == .correct)
                    .accessibilityLabel(answerResult == .correct
                        ? String(localized: "Correct order")
                        : String(localized: "Incorrect order, try again"))

                Button(action: advance) {
                    Label("Next", systemImage: "arrow.forward")
                }
                .buttonStyle(MinikPrimaryActionStyle())
                .accessibilityHint("Moves to the next round")
            } else {
                HStack(spacing: 12) {
                    Button(action: { activityState.undoComparableItem() }) {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(MinikUtilityButtonStyle())
                    .disabled(session.selectedItemIDs.isEmpty)
                    .accessibilityHint("Removes the last block you added")

                    if canSubmit {
                        Button(action: { activityState.submitComparableOrder() }) {
                            Label("Submit", systemImage: "checkmark")
                        }
                        .buttonStyle(MinikPrimaryActionStyle())
                        .accessibilityHint("Checks the tower order")
                    }
                }
                .frame(maxWidth: .infinity)
            }
        case .orderedTokens:
            if let answerResult = session.answerResult {
                MinikFeedbackBadge(isCorrect: answerResult == .correct)
                    .accessibilityLabel(
                        answerResult == .correct
                            ? String(localized: "Correct letter")
                            : String(localized: "Incorrect letter, try again")
                    )

                Text(session.isComplete
                    ? String(localized: "Tower complete! A new word is coming next.")
                    : answerResult == .correct
                        ? String(localized: "Great block! Get ready for the next letter.")
                        : String(localized: "That block stays available. Try the next required letter."))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(red: 0.28, green: 0.49, blue: 0.58))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            } else {
                Text("Drag the next letter onto the tower.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color(red: 0.28, green: 0.49, blue: 0.58))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var selectedItems: [ComparableItem] {
        let itemsByID = Dictionary(
            uniqueKeysWithValues: session.currentRound.items.map { ($0.id, $0) }
        )
        return session.selectedItemIDs.compactMap { itemsByID[$0] }
    }

    private var remainingItems: [ComparableItem] {
        let selectedIDs = Set(session.selectedItemIDs)
        let itemsByID = Dictionary(
            uniqueKeysWithValues: session.currentRound.items.map { ($0.id, $0) }
        )
        return session.itemPresentationOrder.compactMap { itemID in
            guard !selectedIDs.contains(itemID) else {
                return nil
            }
            return itemsByID[itemID]
        }
    }

    private var canSubmit: Bool {
        session.selectedItemIDs.count == session.currentRound.items.count
    }

    private func itemColumns(for availableWidth: CGFloat) -> [GridItem] {
        let spacing: CGFloat = dynamicTypeSize >= .accessibility1 ? 12 : 14

        if dynamicTypeSize >= .accessibility2 {
            return [GridItem(.flexible(minimum: 0, maximum: 280), spacing: spacing)]
        }

        let minimumWidth: CGFloat
        if availableWidth < 430 {
            minimumWidth = 118
        } else if availableWidth < 700 {
            minimumWidth = 140
        } else {
            minimumWidth = 164
        }

        return [GridItem(.adaptive(minimum: minimumWidth, maximum: 220), spacing: spacing)]
    }

    private func towerWidthFraction(for index: Int, total: Int) -> CGFloat {
        guard total > 1 else {
            return 0.82
        }

        let clampedIndex = min(max(index, 0), total - 1)
        return min(0.82, 0.58 + (CGFloat(clampedIndex) * 0.08))
    }

    private func towerBlock(
        _ item: ComparableItem,
        availableWidth: CGFloat,
        widthFraction: CGFloat,
        compact: Bool
    ) -> some View {
        towerBlock(
            representation: item.representation,
            availableWidth: availableWidth,
            widthFraction: widthFraction,
            compact: compact
        )
    }

    private func towerBlock(
        representation: Representation,
        availableWidth: CGFloat,
        widthFraction: CGFloat,
        compact: Bool
    ) -> some View {
        RepresentationView(
            representation: representation,
            context: .towerBlock
        )
        .frame(maxWidth: .infinity, minHeight: compact ? 44 : 48)
        .padding(.horizontal, compact ? 12 : 16)
        .padding(.vertical, compact ? 12 : 14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: compact ? 20 : 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.98),
                            Color(red: 0.94, green: 0.98, blue: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay {
            RoundedRectangle(cornerRadius: compact ? 20 : 24, style: .continuous)
                .strokeBorder(Color(red: 0.72, green: 0.86, blue: 0.97), lineWidth: 1.2)
        }
        .shadow(color: Color(red: 0.18, green: 0.56, blue: 0.76).opacity(0.12), radius: compact ? 8 : 12, y: compact ? 5 : 7)
        .frame(width: availableWidth * widthFraction)
    }

    private func availableLetterBlock(
        _ block: TowerBlock,
        compact: Bool
    ) -> some View {
        RepresentationView(
            representation: block.representation,
            context: .towerBlock
        )
        .frame(maxWidth: .infinity, minHeight: compact ? 56 : 64)
        .padding(.horizontal, compact ? 12 : 16)
        .padding(.vertical, compact ? 10 : 12)
        .background(
            RoundedRectangle(cornerRadius: compact ? 18 : 22, style: .continuous)
                .fill(languageTowerBlockGradient(for: block))
        )
        .overlay {
            RoundedRectangle(cornerRadius: compact ? 18 : 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.94), lineWidth: 1.2)
        }
        .shadow(color: Color.orange.opacity(0.2), radius: compact ? 6 : 9, y: 5)
        .contentShape(RoundedRectangle(cornerRadius: compact ? 18 : 22, style: .continuous))
    }

    private func languageTowerBlock(
        _ block: TowerBlock,
        size: CGFloat,
        isLockedBase: Bool,
        compact: Bool
    ) -> some View {
        RepresentationView(
            representation: block.representation,
            context: .towerBlock
        )
        .font(.headline.weight(.bold))
        .frame(width: size, height: size)
        .background(
            RoundedRectangle(cornerRadius: compact ? 12 : 16, style: .continuous)
                .fill(languageTowerBlockGradient(for: block))
        )
        .overlay {
            RoundedRectangle(cornerRadius: compact ? 12 : 16, style: .continuous)
                .strokeBorder(
                    isLockedBase
                        ? Color(red: 0.22, green: 0.18, blue: 0.52)
                        : Color.white.opacity(0.92),
                    lineWidth: isLockedBase ? 4 : 1.5
                )
        }
        .overlay(alignment: .topTrailing) {
            if isLockedBase {
                Image(systemName: "lock.fill")
                    .font(.system(size: compact ? 9 : 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(compact ? 5 : 6)
                    .background(Color(red: 0.22, green: 0.18, blue: 0.52), in: Circle())
                    .offset(x: compact ? 5 : 7, y: compact ? -5 : -7)
                    .accessibilityHidden(true)
            }
        }
        .shadow(color: Color.black.opacity(0.16), radius: compact ? 4 : 6, y: 4)
    }

    private func languageTowerBlockSize(
        acceptedCount: Int,
        compact: Bool
    ) -> CGFloat {
        let count = CGFloat(max(acceptedCount, 1))
        let spacing: CGFloat = compact ? 3 : 5
        let availableHeight: CGFloat = compact ? 290 : 390
        let fittedSize = (availableHeight - (spacing * (count - 1))) / count
        return min(compact ? 44 : 52, fittedSize)
    }

    private func languageTowerBlockGradient(for block: TowerBlock) -> LinearGradient {
        let palettes: [[Color]] = [
            [Color(red: 1.0, green: 0.25, blue: 0.57), Color(red: 0.93, green: 0.11, blue: 0.43)],
            [Color(red: 1.0, green: 0.78, blue: 0.20), Color(red: 1.0, green: 0.57, blue: 0.12)],
            [Color(red: 0.67, green: 0.47, blue: 0.94), Color(red: 0.49, green: 0.31, blue: 0.82)],
            [Color(red: 0.40, green: 0.74, blue: 0.95), Color(red: 0.18, green: 0.56, blue: 0.85)],
            [Color(red: 0.35, green: 0.87, blue: 0.77), Color(red: 0.16, green: 0.70, blue: 0.62)]
        ]
        let colorSeed = block.id.rawValue.unicodeScalars.reduce(0) {
            $0 + Int($1.value)
        }
        return LinearGradient(
            colors: palettes[colorSeed % palettes.count],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func placeLanguageBlock(rawValue: String) -> Bool {
        guard let blockID = session.availableOrderedBlocks.first(where: {
            $0.id.rawValue == rawValue
        })?.id else {
            return false
        }
        return placeLanguageBlock(blockID)
    }

    @discardableResult
    private func placeLanguageBlock(_ blockID: TowerBlockID) -> Bool {
        guard pendingLanguageTransition == nil,
              let presentationID = activityState.languagePresentationID else {
            return false
        }
        let contentItemID = session.orderedTokenContent?.contentItemID
        let tokenIndex = session.orderedProgressCount
        let responseDurationSeconds = Date().timeIntervalSince(targetStartedAt)
        guard let result = activityState.placeOrderedBlock(blockID) else {
            return false
        }

        if let contentItemID,
           let presentationIndex = activityState.languageChallengePresentationIndex,
           let attempt = languageAttemptTracker.makeAttempt(
               presentationIndex: presentationIndex,
               contentItemID: contentItemID,
               tokenIndex: tokenIndex,
               result: result == .correct ? .correct : .incorrect,
               responseDurationSeconds: responseDurationSeconds,
               activityFamily: .tower,
               languageVocabularyLevel: session.orderedTokenContent?.vocabularyLevel
           ) {
            onAttempt(attempt)
        }

        let completedRound = session.isComplete
        if result == .incorrect {
            feedbackSoundPlayer.play(.incorrect)
            languageRejection = LanguageTowerRejection(blockID: blockID)
        }
        if result == .correct,
           let letterCue = session.lastAcceptedBlockSpeechCue {
            // Android says the word that was built, in the language of its letters.
            if completedRound,
               let wordCue = session.orderedTokenContent?.targetText.learningSpeechCue
                   ?? session.orderedTokenContent?.speechCue {
                speechPlayer.speak([letterCue, wordCue])
                // The completed tower is always praised.
                speakLanguageTowerPraise(LanguageTowerPraise.completion(for: interfaceLocaleID))
            } else {
                speechPlayer.speak(letterCue)
                // A letter is praised only when encouragement is on (gestures).
                if encouragementEnabled {
                    speakLanguageTowerPraise(LanguageTowerPraise.letter)
                }
            }
        }
        if result == .correct {
            flashLanguageTower()
        }
        if completedRound {
            languageRuntimeShimmerStart = Date()
            languageConfettiStart = Date()
        }

        if completedRound,
           let completion = activityState.takeLanguageCompletion() {
            onLanguageWordCompleted(completion)
        }
        if completedRound {
            pendingLanguageTransition = LanguageTowerTransition(presentationID: presentationID)
        } else {
            // handleDropSequential checks the next drop straight away, after a right
            // letter and after a wrong one alike.
            activityState.clearOrderedFeedback()
            targetStartedAt = Date()
        }
        return true
    }

    /// endRoundRunnable: the next word comes 3 s after the last letter.
    @MainActor
    private func performLanguageTransition() async {
        guard scenePhase == .active,
              let transition = pendingLanguageTransition else {
            return
        }
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        guard !Task.isCancelled,
              pendingLanguageTransition == transition else {
            return
        }
        resolveLanguageTransition(transition, speaksNextRound: true)
    }

    private func resolveLanguageTransitionForBackground() {
        guard let transition = pendingLanguageTransition else {
            return
        }
        resolveLanguageTransition(transition, speaksNextRound: false)
    }

    private func resolveLanguageTransition(
        _ transition: LanguageTowerTransition,
        speaksNextRound: Bool
    ) {
        guard pendingLanguageTransition == transition,
              activityState.languagePresentationID == transition.presentationID else {
            return
        }
        pendingLanguageTransition = nil
        guard activityState.advanceLanguageRound(
            expectedPresentationID: transition.presentationID
        ) else {
            return
        }
        // The next word starts with its first letter among the loose ones.
        resetLanguageRoundPresentation()
        if let boundary = activityState.languageLastAdvanceBoundary {
            onLanguagePoolExhausted(boundary)
            if let replacement = makeNextLanguagePracticeSession?() {
                activityState = .languagePractice(replacement)
            }
        }
        targetStartedAt = Date()
        if speaksNextRound {
            speakNewRoundCue()
        }
    }

    private var orderedContentLayoutDirection: LayoutDirection {
        switch session.orderedTokenContent?.targetText.direction {
        case .rightToLeft:
            return .rightToLeft
        case .leftToRight, nil:
            return .leftToRight
        }
    }

    private func speakRoundCue() {
        guard let cue = session.orderedTokenContent?.speechCue else {
            return
        }
        speechPlayer.speak(cue)
    }

    private func exitActivity() {
        stopActivityAudioAndMotion()
        onExit()
    }

    private func stopActivityAudioAndMotion() {
        pendingLanguageTransition = nil
        languageConfettiStart = nil
        speechPlayer.stop()
        feedbackSoundPlayer.stop()
    }

    private func advance() {
        let wasComplete = session.isComplete
        activityState.advanceComparableRound()

        if !wasComplete && session.isComplete {
            onComplete()
        }
    }
}

/// ConfettiRectView.start(3f): about 120 small amber rectangles a second for three
/// seconds from just above the card, each spinning, drifting and falling under
/// gravity, growing a little toward the bottom and fading out.
private struct LanguageTowerConfettiView: View {
    /// The last pieces fall out of the card about 2.2 s after the three seconds of
    /// emitting.
    static let visibleDuration: TimeInterval = 5.5

    let reduceMotion: Bool
    let startedAt: Date
    @State private var seed = Int.random(in: 1 ... 1_000_000)
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

    var body: some View {
        if reduceMotion {
            Canvas { context, size in
                Self.drawParticles(in: &context, size: size, elapsed: 1.4, seed: seed)
            }
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 60, paused: scenePhase != .active)) { timeline in
                let elapsed = timeline.date.timeIntervalSince(startedAt)
                Canvas { context, size in
                    Self.drawParticles(in: &context, size: size, elapsed: elapsed, seed: seed)
                }
            }
        }
    }

    private static func drawParticles(
        in context: inout GraphicsContext,
        size: CGSize,
        elapsed: TimeInterval,
        seed: Int
    ) {
        let width = Double(size.width)
        let height = max(1, Double(size.height))
        // Android's 900 px per second squared and 90 to 210 px per second, on a card
        // about 2,000 px tall.
        let gravity = 0.44 * height
        for index in 0 ..< particleCount {
            let age = elapsed - Double(index) / emittedPerSecond
            if age < 0 {
                break
            }
            let lifetime = 2.8 + 1.4 * LanguageTowerNoise.unit(seed, index, 0)
            if age > lifetime {
                continue
            }
            let horizontalSpeed = (LanguageTowerNoise.unit(seed, index, 1) - 0.5) * 0.11 * width
            let verticalSpeed = (0.045 + 0.057 * LanguageTowerNoise.unit(seed, index, 2)) * height
            let phase = 6.283 * LanguageTowerNoise.unit(seed, index, 3)
            let sway = sin(age * 2.6 + phase) * 5
            let x = width * LanguageTowerNoise.unit(seed, index, 4) + horizontalSpeed * age + sway
            let startY = -height * 0.15 * LanguageTowerNoise.unit(seed, index, 5)
            let y = startY + verticalSpeed * age + 0.5 * gravity * age * age
            let base = 3 + 4 * LanguageTowerNoise.unit(seed, index, 6)
            let stretch: Double
            if LanguageTowerNoise.unit(seed, index, 7) < 0.35 {
                stretch = 1.8 + 1.4 * LanguageTowerNoise.unit(seed, index, 8)
            } else {
                stretch = 0.9 + 0.7 * LanguageTowerNoise.unit(seed, index, 8)
            }
            let depth = 0.6 + 0.7 * min(1, max(0, y / height))
            let particleWidth = base * depth
            let particleHeight = base * stretch * depth
            if y - particleHeight > height {
                continue
            }
            let progress = age / lifetime
            let spin = (LanguageTowerNoise.unit(seed, index, 9) - 0.5) * 540 * age
            let rotation = 360 * LanguageTowerNoise.unit(seed, index, 10) + spin
            let colorIndex = Int(LanguageTowerNoise.unit(seed, index, 11) * Double(palette.count)) % palette.count

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
}

/// LettersTowerFragment's card in the rainbow-sky design (applyGameBackgrounds): the
/// glass card with a white rim and the light wash inside it, over the sky, inset by
/// the root's padding and the card's compatibility padding (18 dp at the sides and
/// 22 dp above and below; 20 dp and 24 dp on tablets). The board fills the card
/// edge to edge; it scrolls only at accessibility text sizes, where it can be
/// taller than the card.
private struct LanguageTowerPanel<Content: View>: View {
    private let scrolls: Bool
    private let content: (LanguageTowerPanelLayout) -> Content

    init(
        scrolls: Bool,
        @ViewBuilder content: @escaping (LanguageTowerPanelLayout) -> Content
    ) {
        self.scrolls = scrolls
        self.content = content
    }

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 700
            let panelWidth = max(1, geometry.size.width - (wide ? 40 : 36))
            let panelHeight = max(1, geometry.size.height - (wide ? 48 : 44))
            let layout = LanguageTowerPanelLayout(
                width: panelWidth,
                height: panelHeight,
                wide: wide
            )
            LanguageSkyPanel(
                width: panelWidth,
                height: panelHeight,
                cornerRadius: wide ? 36 : 28,
                washed: true
            ) {
                Group {
                    if scrolls {
                        ScrollView {
                            content(layout)
                        }
                        .scrollBounceBehavior(.basedOnSize)
                    } else {
                        content(layout)
                    }
                }
                .frame(width: panelWidth, height: panelHeight, alignment: .top)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        // The sky stays a background so it never sizes the layout.
        .background {
            MinikSkyBackground()
        }
    }
}

private struct LanguageTowerPanelLayout {
    let width: CGFloat
    let height: CGFloat
    let wide: Bool
}

private struct LanguageTowerPromptPlan {
    /// towerWord: the word in the hosting language, when Android shows it.
    let hostWord: String?
    /// towerWordImage, 80 dp under the word being built.
    let showsImage: Bool
    /// Whether the shimmer row counts in titlesContainer's first measured height.
    let reservesHostWordRow: Bool
}

private struct LanguageTowerTitleChip: Identifiable {
    let id: Int
    let letter: String
    let colorIndex: Int
}

private struct LanguageTowerTitleRow: Identifiable {
    let id: Int
    let startsWord: Bool
    let chips: [LanguageTowerTitleChip]
}

private struct LanguageTowerDrag: Equatable {
    let blockID: TowerBlockID
    let translation: CGSize
}

/// LettersTowerFragment's geometry in dp: fragment_letters_tower.xml with the
/// reference phone's dimensions on its 357 x 745 dp card, and layout-sw600dp with
/// the sw700dp dimensions on a 704 x 1041 dp card for iPad, then the fragment's own
/// placement code. Everything scales with the panel, so a bigger screen keeps
/// Android's proportions instead of spreading out.
private struct LanguageTowerMetrics {
    let width: CGFloat
    let height: CGFloat
    let scale: CGFloat
    let rightToLeft: Bool

    let closeSize: CGFloat
    let closeCenter: CGPoint
    let speakerSize: CGFloat
    let speakerCenter: CGPoint

    let titleTop: CGFloat
    let chipSize: CGFloat
    let chipGap: CGFloat
    let chipCornerRadius: CGFloat
    let chipFontSize: CGFloat
    let chipsPerRow: Int
    let statusMargin: CGFloat
    /// The phone's 55 dp status row; nil where the text wraps freely (tablets and
    /// accessibility text sizes).
    let fixedStatusHeight: CGFloat?
    let instructionFontSize: CGFloat
    let instructionWidth: CGFloat
    let wordFontSize: CGFloat
    let wordRowHeight: CGFloat
    let hostWordMargin: CGFloat
    let runtimeMargin: CGFloat
    let imageMargin: CGFloat
    let imageHeight: CGFloat

    let blockSize: CGFloat
    let blockFontSize: CGFloat
    let blockCornerRadius: CGFloat
    let looseColumns: Int
    let looseStart: CGFloat
    let looseGap: CGFloat
    let looseRowGap: CGFloat
    let looseGridTop: CGFloat
    let towerX: CGFloat
    let towerBaseBottom: CGFloat
    let snapThreshold: CGFloat
    /// The finished tower's slots (the word's characters, spaces included) and the
    /// loose letters dealt for it.
    let towerSlotCount: Int
    let looseBlockCount: Int

    let sandSize: CGSize
    let sandCenter: CGPoint
    let mascotSize: CGSize
    let mascotCenter: CGPoint
    let pileSize: CGSize
    let pileCenter: CGPoint

    init(
        panelWidth: CGFloat,
        panelHeight: CGFloat,
        wide: Bool,
        rightToLeft: Bool,
        accessible: Bool,
        textGrowth: CGFloat,
        titleWordLengths: [Int],
        titleMarginTop: CGFloat,
        instructionLength: Int,
        showsHostWord: Bool,
        reservesHostWordRow: Bool,
        showsImage: Bool,
        wordLength: Int,
        blockCount: Int
    ) {
        let widthScale = panelWidth / (wide ? 704 : 357)
        let heightScale = panelHeight / (wide ? 1041 : 660)
        let s = max(0.5, min(widthScale, heightScale))
        width = panelWidth
        scale = s
        self.rightToLeft = rightToLeft

        // The close X 15 dp from the top and 20 dp from the end (25 dp and 30 dp on
        // tablets); the 40 dp speaker mirrors it at the start.
        let close: CGFloat = (wide ? 45 : 27) * s
        let buttonTop: CGFloat = (wide ? 25 : 15) * s
        let buttonInset: CGFloat = (wide ? 30 : 20) * s
        let speaker: CGFloat = (wide ? 60 : 40) * s
        closeSize = close
        speakerSize = speaker
        closeCenter = CGPoint(
            x: rightToLeft ? buttonInset + close / 2 : panelWidth - buttonInset - close / 2,
            y: buttonTop + close / 2
        )
        speakerCenter = CGPoint(
            x: rightToLeft ? panelWidth - buttonInset - speaker / 2 : buttonInset + speaker / 2,
            y: buttonTop + speaker / 2
        )

        // titlesContainer sits under the X on phones and at the top on tablets,
        // padded 10 dp (55 dp); its chips are 32 dp (52 dp) with 2 dp (4 dp) margins.
        let containerTop: CGFloat = wide
            ? titleMarginTop * s
            : buttonTop + close + titleMarginTop * s
        let containerPadding: CGFloat = (wide ? 55 : 10) * s
        let chip: CGFloat = (wide ? 52 : 32) * s
        let gap: CGFloat = (wide ? 4 : 2) * s
        let perRow = max(1, Int((panelWidth - 36 * s) / (chip + 2 * gap)))
        var rowCount = 0
        for length in titleWordLengths {
            rowCount += max(1, (length + perRow - 1) / perRow)
        }
        rowCount = max(1, rowCount)
        let wordBreaks = max(0, titleWordLengths.count - 1)
        let flexHeight = CGFloat(rowCount) * (chip + 2 * gap) + CGFloat(wordBreaks) * 2 * gap
        titleTop = containerTop + containerPadding + gap
        chipSize = chip
        chipGap = gap
        chipCornerRadius = min(14 * s, chip / 2)
        chipFontSize = (wide ? 30 : 22) * s
        chipsPerRow = perRow

        // The status line: 18 sp in a 55 dp row 10 dp under the chips on phones,
        // 28 sp wrapping 20 dp under them on tablets.
        let instructionGrowth = min(textGrowth, accessible ? 2.2 : 1.4)
        let instructionFont: CGFloat = (wide ? 28 : 18) * s * instructionGrowth
        let textWidth: CGFloat = panelWidth - (wide ? 20 : 60) * s
        let charactersPerLine = max(1, Int(textWidth / (instructionFont * 0.5)))
        let estimatedLines = max(1, (instructionLength + charactersPerLine - 1) / charactersPerLine)
        let lineHeight = instructionFont * 1.3
        let statusGap: CGFloat = (wide ? 20 : 10) * s
        let status: CGFloat
        if wide || accessible {
            status = CGFloat(accessible ? estimatedLines : min(2, estimatedLines)) * lineHeight
            fixedStatusHeight = nil
        } else {
            status = max(55 * s, 2 * lineHeight)
            fixedStatusHeight = status
        }
        instructionFontSize = instructionFont
        instructionWidth = textWidth
        statusMargin = statusGap

        // towerWord and towerWordBuildInRunTime: 32 sp (50 sp) bold rows.
        let wordGrowth = min(textGrowth, accessible ? 1.8 : 1.3)
        let wordFont: CGFloat = (wide ? 50 : 32) * s * wordGrowth
        let wordRow = wordFont * 1.34
        let hostGap: CGFloat = (wide ? 12 : 3) * s
        let runtimeGap: CGFloat = (wide ? 2 : 0) * s
        let pictureGap: CGFloat = 10 * s
        let picture: CGFloat = 80 * s
        wordFontSize = wordFont
        wordRowHeight = wordRow
        hostWordMargin = hostGap
        runtimeMargin = runtimeGap
        imageMargin = pictureGap
        imageHeight = picture

        var columnBottom = containerTop + containerPadding + flexHeight + statusGap + status
        if showsHostWord {
            columnBottom += hostGap + wordRow
        }
        columnBottom += runtimeGap + wordRow
        if showsImage {
            columnBottom += pictureGap + picture
        }
        columnBottom += containerPadding

        // The letters are placed from titlesContainer's height at the first layout:
        // the shimmer row counts when it starts visible, the picture never does.
        var reserved = containerPadding + flexHeight + statusGap + status
        if reservesHostWordRow {
            reserved += hostGap + wordRow
        }
        reserved += runtimeGap + wordRow + containerPadding

        // Accessibility text can push the column down; the board then grows and the
        // panel scrolls. Otherwise the board is exactly the card.
        let boardHeight = accessible
            ? max(panelHeight, columnBottom + (wide ? 640 : 420) * s)
            : panelHeight
        height = boardHeight

        // 64 dp blocks (90 dp on tablets) while the word has up to five (seven)
        // characters; longer words shrink them to fit above the ground, to 36 dp.
        let defaultBlock: CGFloat = (wide ? 90 : 64) * s
        let groundTop: CGFloat = boardHeight - (wide ? 210 : 80) * s
        var block = defaultBlock
        if wordLength > (wide ? 7 : 5) {
            let available = max(0, groundTop - reserved - 24 * s)
            block = max(36 * s, min(defaultBlock, available / CGFloat(max(1, wordLength))))
        }
        blockSize = block
        blockFontSize = (wide ? 50 : 38) * s * min(1, max(0.55, block / defaultBlock))
        blockCornerRadius = min(16 * s, block / 2)

        // minik_plus_tower_sitting fitted into 120 x 200 dp (300 x 500 dp), 10 dp
        // from the left and the bottom.
        let mascotWidth: CGFloat = (wide ? 300 : 120) * s
        let mascotHeight = mascotWidth * 594 / 365
        let mascotBox: CGFloat = (wide ? 500 : 200) * s
        let mascotBottom = boardHeight - 10 * s - max(0, mascotBox - mascotHeight) / 2
        let mascotTop = mascotBottom - mascotHeight
        mascotSize = CGSize(width: mascotWidth, height: mascotHeight)
        mascotCenter = CGPoint(x: 10 * s + mascotWidth / 2, y: mascotBottom - mascotHeight / 2)

        // The loose letters: rows from the start edge, 10 dp (25 dp) apart, centred
        // on 6/14 (4/14) of the space under the titles. Where the card is shorter than
        // the reference phone's (and on tablets, whose Minik is much bigger) that row
        // would cover Minik, so it rises until it clears him, never into the titles.
        let looseSpacing: CGFloat = (wide ? 25 : 10) * s
        let rowSpacing: CGFloat = 12 * s
        let fittingColumns = max(1, Int(panelWidth / (block + looseSpacing)))
        let columns = max(1, min(fittingColumns, blockCount))
        let rows = max(1, (blockCount + columns - 1) / columns)
        let gridHeight = CGFloat(rows) * block + CGFloat(rows - 1) * rowSpacing
        let playHeight = max(0, boardHeight - reserved)
        let playFraction: CGFloat = wide ? 4.0 / 14.0 : 6.0 / 14.0
        let playOffset: CGFloat = (wide ? -17.5 : 3.6) * s
        let playCenter = reserved + playHeight * playFraction + playOffset
        let centredTop = playCenter - gridHeight / 2
        let clearOfMinikTop = mascotTop - gridHeight - 6 * s
        let lowestTitleEdge = max(reserved, columnBottom)
        looseColumns = columns
        looseStart = (wide ? 25 : 18) * s
        looseGap = looseSpacing
        looseRowGap = rowSpacing
        looseGridTop = max(lowestTitleEdge, min(centredTop, clearOfMinikTop))

        // The first letter lands 52 dp (150 dp) into the ground's frame and the
        // others stack straight on top; a drop within 140 dp (200 dp) snaps.
        towerX = panelWidth / 2
        towerBaseBottom = min(boardHeight, groundTop + (wide ? 150 : 52) * s)
        snapThreshold = (wide ? 200 : 140) * s
        towerSlotCount = max(0, wordLength)
        looseBlockCount = max(0, blockCount)

        // sand2 fills the width, centred 30 dp (60 dp) above the bottom edge.
        sandSize = CGSize(width: panelWidth, height: panelWidth * 189 / 864)
        sandCenter = CGPoint(x: panelWidth / 2, y: boardHeight - (wide ? 60 : 30) * s)

        // send_pile fitted into 100 x 80 dp, 2 dp past the right edge (210 x 130 dp,
        // 12 dp in), 10 dp above the bottom.
        let pileWidth: CGFloat = (wide ? 196.5 : 100) * s
        let pileBoxWidth: CGFloat = (wide ? 210 : 100) * s
        let pileBoxHeight: CGFloat = (wide ? 130 : 80) * s
        let pileRight: CGFloat = (wide ? 12 : -2) * s
        pileSize = CGSize(width: pileWidth, height: pileWidth * 217 / 328)
        pileCenter = CGPoint(
            x: panelWidth - pileRight - pileBoxWidth / 2,
            y: boardHeight - 10 * s - pileBoxHeight / 2
        )
    }

    func towerSlotCenter(_ slot: Int) -> CGPoint {
        CGPoint(x: towerX, y: towerBaseBottom - blockSize / 2 - CGFloat(slot) * blockSize)
    }

    /// The tower's column from the sand up through its first `slots` slots.
    func towerColumn(slots: Int) -> CGRect {
        let columnHeight = CGFloat(max(0, slots)) * blockSize
        return CGRect(
            x: towerX - blockSize / 2,
            y: towerBaseBottom - columnHeight,
            width: blockSize,
            height: columnHeight
        )
    }

    /// The speaker's and the X's tap targets, as languageTowerNavigation sizes them.
    var buttonAreas: [CGRect] {
        let speakerTarget = max(44, speakerSize)
        let closeTarget = max(44, closeSize)
        return [
            CGRect(
                x: speakerCenter.x - speakerTarget / 2,
                y: speakerCenter.y - speakerTarget / 2,
                width: speakerTarget,
                height: speakerTarget
            ),
            CGRect(
                x: closeCenter.x - closeTarget / 2,
                y: closeCenter.y - closeTarget / 2,
                width: closeTarget,
                height: closeTarget
            )
        ]
    }

    func blockFrame(at center: CGPoint) -> CGRect {
        CGRect(
            x: center.x - blockSize / 2,
            y: center.y - blockSize / 2,
            width: blockSize,
            height: blockSize
        )
    }

    /// placeBlocks' grid slot for a block. A grid cell the tower grows over before
    /// its last letter (or one under the speaker or the X) is passed over, and the
    /// letters after it move on a cell, into another row when they need one, so no
    /// letter ever starts where a placed block would cover it.
    func looseSlotCenter(index: Int, seed: Int) -> CGPoint {
        let centers = looseSlotCenters(seed: seed)
        return centers.indices.contains(index)
            ? centers[index]
            : looseGridCellCenter(index, seed: seed)
    }

    func looseSlotCenters(seed: Int) -> [CGPoint] {
        let count = looseBlockCount
        // The tower before its last letter: every block that sits on it while a
        // letter is still loose.
        let covered = towerColumn(slots: towerSlotCount - 1)
        let buttons = buttonAreas
        var centers: [CGPoint] = []
        centers.reserveCapacity(count)
        let lastCell = count + 4 * looseColumns + 8
        var cell = 0
        while centers.count < count, cell < lastCell {
            let center = looseGridCellCenter(cell, seed: seed)
            let frame = blockFrame(at: center)
            let isFree = !Self.overlaps(frame, covered)
                && !buttons.contains(where: { Self.overlaps(frame, $0) })
                && !centers.contains(where: { taken in
                    abs(taken.x - center.x) < blockSize / 2 && abs(taken.y - center.y) < blockSize / 2
                })
            if isFree {
                centers.append(center)
            }
            cell += 1
        }
        // A board too small for that keeps the plain grid for the rest.
        while centers.count < count {
            centers.append(looseGridCellCenter(centers.count, seed: seed))
        }
        return centers
    }

    /// One cell of placeBlocks' grid, with its small fixed jitter, counted from the
    /// right edge in right-to-left interfaces (marginStart).
    private func looseGridCellCenter(_ cell: Int, seed: Int) -> CGPoint {
        let column = cell % looseColumns
        let row = cell / looseColumns
        let jitterX = (CGFloat(LanguageTowerNoise.unit(seed, cell, 1)) - 0.5) * 12 * scale
        let jitterY = (CGFloat(LanguageTowerNoise.unit(seed, cell, 2)) - 0.5) * 8 * scale
        let fromStart = looseStart + CGFloat(column) * (blockSize + looseGap) + jitterX
        let leading = min(max(0, fromStart), max(0, width - blockSize))
        let rawTop = looseGridTop + CGFloat(row) * (blockSize + looseRowGap) + jitterY
        let top = min(max(0, rawTop), max(0, height - blockSize))
        let x = rightToLeft ? width - leading - blockSize / 2 : leading + blockSize / 2
        return CGPoint(x: x, y: top + blockSize / 2)
    }

    /// Android keeps a dragged block inside the board.
    func clampedBlockCenter(_ point: CGPoint) -> CGPoint {
        let half = blockSize / 2
        return CGPoint(
            x: min(max(half, point.x), max(half, width - half)),
            y: min(max(half, point.y), max(half, height - half))
        )
    }

    /// The gap a loose letter keeps from the tower and from the other letters.
    var restingRoom: CGFloat {
        max(2 * scale, blockSize * 0.15)
    }

    /// Whether a loose letter here is in full view: off the finished tower's
    /// column (with `room` to spare) and out from under the speaker and the X.
    func keepsTowerAndButtonsClear(_ center: CGPoint, room: CGFloat = 0) -> Bool {
        let frame = blockFrame(at: center)
        let tower = towerColumn(slots: towerSlotCount).insetBy(dx: -room, dy: -room)
        return !Self.overlaps(frame, tower)
            && !buttonAreas.contains(where: { Self.overlaps(frame, $0) })
    }

    /// Whether one of the other loose letters rests where this one would.
    func isTaken(_ center: CGPoint, by others: [CGPoint], room: CGFloat = 0) -> Bool {
        let spacing = blockSize + room
        return others.contains { other in
            abs(other.x - center.x) < spacing && abs(other.y - center.y) < spacing
        }
    }

    /// The nearest place to `point` where a loose letter rests in full view and in
    /// reach: clear of the tower, the speaker, the X and the other loose letters.
    /// A letter let go in a free place stays exactly where it is.
    func restingCenter(near point: CGPoint, avoiding others: [CGPoint]) -> CGPoint {
        let room = restingRoom
        let start = clampedBlockCenter(point)
        func isFree(_ center: CGPoint) -> Bool {
            keepsTowerAndButtonsClear(center, room: room) && !isTaken(center, by: others, room: room)
        }
        if isFree(start) {
            return start
        }
        // Rings around the drop, a quarter block apart, out to the first ring with
        // a free place; the closest place on that ring wins.
        let step = max(4, blockSize / 4)
        let reach = max(width, height)
        var radius = step
        while radius <= reach {
            let count = max(8, Int((2 * Double.pi * Double(radius / step)).rounded(.up)))
            var best: CGPoint?
            var bestDistance = CGFloat.greatestFiniteMagnitude
            for spoke in 0 ..< count {
                let angle = 2 * Double.pi * Double(spoke) / Double(count)
                let candidate = clampedBlockCenter(CGPoint(
                    x: start.x + radius * CGFloat(cos(angle)),
                    y: start.y + radius * CGFloat(sin(angle))
                ))
                guard isFree(candidate) else {
                    continue
                }
                let dx = candidate.x - start.x
                let dy = candidate.y - start.y
                let distance = dx * dx + dy * dy
                if distance < bestDistance {
                    best = candidate
                    bestDistance = distance
                }
            }
            if let best {
                return best
            }
            radius += step
        }
        return start
    }

    /// Overlap with some area in common; blocks that only touch do not overlap.
    private static func overlaps(_ first: CGRect, _ second: CGRect) -> Bool {
        first.minX < second.maxX && second.minX < first.maxX
            && first.minY < second.maxY && second.minY < first.maxY
    }
}

/// ShimmerFrameLayout's pass over a tower word: gold (#C9A227) with a pale
/// (#FFF7D8) highlight sweeping left to right for 1.5 s, then the word's colour.
private struct LanguageTowerShimmerText: View {
    let text: String
    let fontSize: CGFloat
    let color: Color
    let shimmerStart: Date?
    let castsShadow: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let shimmerStart, !reduceMotion {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                label(progress: timeline.date.timeIntervalSince(shimmerStart) / 1.5)
            }
        } else {
            label(progress: nil)
        }
    }

    @ViewBuilder
    private func label(progress: Double?) -> some View {
        if let progress, progress >= 0, progress <= 1 {
            styledText
                .foregroundStyle(Self.sweep(at: progress))
        } else {
            styledText
                .foregroundStyle(color)
                .shadow(
                    color: castsShadow ? Color.black.opacity(0.2) : Color.clear,
                    radius: 1.5,
                    x: 0,
                    y: 1
                )
        }
    }

    private var styledText: some View {
        Text(text)
            .font(.system(size: fontSize, weight: .bold))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }

    private static func sweep(at progress: Double) -> LinearGradient {
        let gold = Color(red: 0.788, green: 0.635, blue: 0.153)
        let highlight = Color(red: 1.0, green: 0.969, blue: 0.847)
        let center: CGFloat = -0.25 + 1.5 * CGFloat(progress)
        let lower = min(1, max(0, center - 0.22))
        let middle = min(1, max(0, center))
        let upper = min(1, max(0, center + 0.22))
        return LinearGradient(
            stops: [
                Gradient.Stop(color: gold, location: 0),
                Gradient.Stop(color: gold, location: lower),
                Gradient.Stop(color: highlight, location: middle),
                Gradient.Stop(color: gold, location: upper),
                Gradient.Stop(color: gold, location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

/// A stable pseudo-random value in 0..<1 for one property of one item, so a redraw
/// never reshuffles the board or the confetti.
private enum LanguageTowerNoise {
    static func unit(_ seed: Int, _ index: Int, _ channel: Int) -> Double {
        var value = UInt64(truncatingIfNeeded: seed)
        value = value &+ UInt64(truncatingIfNeeded: index) &* 0x9E37_79B9_7F4A_7C15
        value = value &+ UInt64(truncatingIfNeeded: channel) &* 0xD1B5_4A32_D192_ED03
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        value = value ^ (value >> 31)
        return Double(value >> 11) / 9_007_199_254_740_992
    }
}

/// createLetterBlock and createTitleBlock lift Hebrew letters (and Arabic ones in the
/// title) by 8% of the text size so they sit in the middle of their block; lamed
/// (and feh), which already reach up, stay where they are.
private enum LanguageTowerGlyph {
    private static let hebrew: ClosedRange<UInt32> = 0x0590 ... 0x05FF
    private static let arabic: ClosedRange<UInt32> = 0x0600 ... 0x06FF

    static func lift(for letter: String, fontSize: CGFloat, includesArabic: Bool) -> CGFloat {
        guard let value = letter.unicodeScalars.first?.value else {
            return 0
        }
        let isHebrew = hebrew.contains(value)
        let isArabic = includesArabic && arabic.contains(value)
        guard isHebrew || isArabic,
              letter != "\u{05DC}",
              letter != "\u{0641}" else {
            return 0
        }
        return -0.08 * fontSize
    }
}

/// Android's spoken praise in the interface language: after a letter that does not
/// finish the word (good, correct, success) and when the tower is complete
/// (way_to_go, tower_completed, finished_with_success). Its other phrases (accurate,
/// you_are_right, everything_is_in_place) have no catalog translations yet.
private enum LanguageTowerPraise {
    static let letter: [String.LocalizationValue] = ["Good!", "Correct", "Success!"]

    /// tower_completed's catalog key translates to just "Tower completed!" in every
    /// other language, but its English value is the whole key sentence, so English
    /// leaves it out until the catalogs have Android's "Tower completed!".
    static func completion(for locale: InterfaceLocaleID) -> [String.LocalizationValue] {
        guard locale != .english else {
            return ["Great job!", "Success!"]
        }
        return ["Great job!", "Tower complete! A new word is coming next.", "Success!"]
    }
}

/// The vocabulary catalog by item, for the word in the hosting language.
private enum LanguageTowerCatalog {
    static let itemsByID: [ContentItemID: LanguageWordCatalogItem] = Dictionary(
        LanguageWordCatalog.allItems.map { ($0.id, $0) },
        uniquingKeysWith: { first, _ in first }
    )
}

private enum LanguageTowerColors {
    /// titlePalette: pink, yellow, purple, blue, mint and orange.
    static let title: [Color] = [
        Color(red: 1.00, green: 0.059, blue: 0.529),
        Color(red: 1.00, green: 0.737, blue: 0.00),
        Color(red: 0.608, green: 0.471, blue: 0.941),
        Color(red: 0.400, green: 0.663, blue: 0.910),
        Color(red: 0.341, green: 0.831, blue: 0.757),
        Color(red: 1.00, green: 0.541, blue: 0.00)
    ]

    /// initRound's Plus colours for the word being built in the rainbow-sky design:
    /// strong tones only (#E65100, #D81B60, #7B1FA2, #00796B, #E91E63, #3F51B5 and
    /// #9C27B0), since the old light orange, pink and lavender were hard to see on
    /// the light panel.
    static let runtime: [Color] = [
        Color(red: 0.902, green: 0.318, blue: 0.00),
        Color(red: 0.847, green: 0.106, blue: 0.376),
        Color(red: 0.482, green: 0.122, blue: 0.635),
        Color(red: 0.00, green: 0.475, blue: 0.420),
        Color(red: 0.914, green: 0.118, blue: 0.388),
        Color(red: 0.247, green: 0.318, blue: 0.710),
        Color(red: 0.612, green: 0.153, blue: 0.690)
    ]

    /// pickKidColor's Plus colours for the hosting word (plusReadableColorIds:
    /// kid_red, kid_pink, kid_purple, kid_deep_purple, kid_indigo and kid_blue),
    /// readable on the light panel.
    static let kid: [Color] = [
        Color(red: 1.00, green: 0.090, blue: 0.267),
        Color(red: 0.961, green: 0.00, blue: 0.341),
        Color(red: 0.835, green: 0.00, blue: 0.976),
        Color(red: 0.396, green: 0.122, blue: 1.00),
        Color(red: 0.239, green: 0.353, blue: 0.996),
        Color(red: 0.161, green: 0.475, blue: 1.00)
    ]
}
