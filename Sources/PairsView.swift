import SwiftUI

struct PairsView: View {
    private struct LanguagePairTransition: Hashable {
        let id = UUID()
        let presentation: Int
        let result: PairsAttemptResult
    }

    private struct LanguagePairTaskKey: Hashable {
        let transition: LanguagePairTransition?
        let active: Bool
    }

    @State private var lastAudibleLanguagePairID: UUID?
    @State private var pendingLanguagePair: LanguagePairTransition?
    @State private var hiddenLanguageGroups: Set<Int> = []
    @State private var languagePairFeedbackVisible = false
    @State private var languageShakeOffset: CGFloat = 0
    @StateObject private var feedbackSoundPlayer = LanguageFeedbackSoundPlayer()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.interfaceLocaleID) private var interfaceLocaleID
    @Environment(\.languageEncouragementEnabled) private var encouragementEnabled

    @State private var session: PairsSession
    @State private var mathAttemptIndex = 0
    @State private var presentationIndex = 1
    @State private var languageAttemptTracker = LanguagePairsAttemptTracker()
    @State private var attemptStartedAt = Date()
    @StateObject private var speechPlayer: LearningSpeechPlayer
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    // Android Letter Pairs text sizes (fragment_letter_pairs.xml on phones,
    // its sw600dp variant on iPad). Like Android sp they grow with the
    // reader's text size.
    @ScaledMetric(relativeTo: .title2) private var compactTitleSize: CGFloat = 25
    @ScaledMetric(relativeTo: .largeTitle) private var wideTitleSize: CGFloat = 39
    @ScaledMetric(relativeTo: .subheadline) private var compactInstructionSize: CGFloat = 14
    @ScaledMetric(relativeTo: .title3) private var wideInstructionSize: CGFloat = 22
    @ScaledMetric(relativeTo: .subheadline) private var compactPointsTitleSize: CGFloat = 14
    @ScaledMetric(relativeTo: .title3) private var compactPointsValueSize: CGFloat = 20
    @ScaledMetric(relativeTo: .title2) private var widePointsTitleSize: CGFloat = 25
    @ScaledMetric(relativeTo: .title2) private var widePointsValueSize: CGFloat = 26
    private let onComplete: () -> Void
    private let onExit: () -> Void
    private let makeNextSession: (() -> PairsSession?)?
    private let mathActivityFamily: ActivityFamily?
    private let mathLevelID: MathCurriculumLevelID
    private let progressActivityFamily: ActivityFamily?
    private let languageSkillID: SkillID?
    private let onAttempt: (ActivityAttemptData) -> Void

    init(
        session: PairsSession,
        mathActivityFamily: ActivityFamily? = nil,
        mathLevelID: MathCurriculumLevelID = .m1,
        progressActivityFamily: ActivityFamily? = nil,
        languageSkillID: SkillID? = nil,
        makeNextSession: (() -> PairsSession?)? = nil,
        onAttempt: @escaping (ActivityAttemptData) -> Void = { _ in },
        onComplete: @escaping () -> Void = {},
        onExit: @escaping () -> Void = {}
    ) {
        _session = State(initialValue: session)
        self.mathActivityFamily = mathActivityFamily
        self.mathLevelID = mathLevelID
        self.progressActivityFamily = progressActivityFamily ?? mathActivityFamily
        self.languageSkillID = languageSkillID
        self.makeNextSession = makeNextSession
        self.onAttempt = onAttempt
        _speechPlayer = StateObject(wrappedValue: LearningSpeechPlayer())
        self.onComplete = onComplete
        self.onExit = onExit
    }

    var body: some View {
        Group {
            if isLanguagePairs { languageBody } else { standardBody }
        }
        .task(id: LanguagePairTaskKey(transition: pendingLanguagePair, active: scenePhase == .active)) {
            await performLanguagePairTransition()
        }
        .mathReadAloud(instruction: mathReadAloudInstruction, exercise: nil, id: 0)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                languagePairFeedbackVisible = false
                languageShakeOffset = 0
                stopPairAudio()
            }
        }
        .onDisappear {
            pendingLanguagePair = nil
            stopPairAudio()
        }
    }

    private var isLanguagePairs: Bool {
        mathActivityFamily == nil && session.selectionStyle == .anyTwoTiles
    }

    // Android Letter Pairs (fragment_letter_pairs.xml, and its sw600dp variant
    // on iPad): the Minik logo at the start and the red X at the end, a
    // centred title with the instruction under it, the eight pictures two per
    // row in four equal rows, then the pairs mascot with the Points card at
    // its start. The pictures take the height the other rows leave, so larger
    // text shrinks them a little; the panel scrolls only when they would get
    // smaller than the board minimum.
    private var languageBody: some View {
        LanguageActivityScreen(minimumContentHeight: { _, wide in wide ? 600 : 530 }) { layout in
            languagePairsContent(layout)
        }
    }

    private func languagePairsContent(_ layout: LanguageActivityLayout) -> some View {
        let metrics = LanguagePairsMetrics(wide: layout.wide)
        let rows = LanguagePairsMetrics.rows(itemCount: session.mixedBoardItems.count)
        let minimumHeight = languagePairsMinimumHeight(layout, metrics: metrics, rows: rows)
        return VStack(spacing: 0) {
            languagePairsHeader(layout, metrics: metrics)
            GeometryReader { proxy in
                languagePairsBoard(size: proxy.size, metrics: metrics, rows: rows)
            }
            languagePairsFooter(layout, metrics: metrics)
        }
        .frame(height: max(layout.height, minimumHeight))
    }

    /// The page height with the pictures at their smallest. Below the
    /// accessibility sizes the header holds at most a one-line title and a
    /// two-line instruction; at accessibility sizes the instruction wraps
    /// freely, so its lines are estimated from its length, and on phones the
    /// title moves to its own row under the logo.
    private func languagePairsMinimumHeight(
        _ layout: LanguageActivityLayout,
        metrics: LanguagePairsMetrics,
        rows: Int
    ) -> CGFloat {
        let titleSize = layout.wide ? wideTitleSize : compactTitleSize
        let instructionSize = layout.wide ? wideInstructionSize : compactInstructionSize
        let lineRatio = LanguagePairsMetrics.lineHeightRatio
        let underLogo = LanguagePairsMetrics.titleUnderLogo(layout)
        let titleTop = underLogo ? metrics.accessibleTitleTop : metrics.titleTop
        var instructionLines: CGFloat = 2
        if layout.accessibility {
            let instruction = interfaceLocaleID.text("Choose 2 pictures that start with the same letter")
            let textWidth = CGFloat(instruction.count) * instructionSize * 0.56
            let lineWidth = max(1, layout.width - 2 * metrics.instructionSide)
            instructionLines = max(1, (textWidth / lineWidth).rounded(.up))
        }
        let titleRow = titleTop + titleSize * lineRatio + metrics.instructionGap
        let header = titleRow + instructionSize * lineRatio * instructionLines
        let tiles = metrics.minimumTile * CGFloat(rows) + metrics.tileGap * CGFloat(rows - 1)
        let board = metrics.boardTop + tiles + metrics.boardBottom
        return header + board + metrics.mascotSide + metrics.mascotBottom
    }

    private func languagePairsHeader(_ layout: LanguageActivityLayout, metrics: LanguagePairsMetrics) -> some View {
        // On phones at accessibility sizes the title gets its own row under
        // the logo; on iPad it keeps Android's place between the logo and the X.
        let underLogo = LanguagePairsMetrics.titleUnderLogo(layout)
        let titleTop = underLogo ? metrics.accessibleTitleTop : metrics.titleTop
        return ZStack(alignment: .top) {
            HStack(alignment: .top, spacing: 0) {
                MinikLanguageLogo()
                    .frame(width: metrics.logoWidth, height: metrics.logoHeight)
                    .padding(.leading, metrics.logoLeading)
                    .padding(.top, metrics.logoTop)
                Spacer(minLength: 0)
                languagePairsCloseButton(metrics)
            }
            VStack(spacing: metrics.instructionGap) {
                languagePairsTitle(layout, metrics: metrics)
                languagePairsInstruction(layout)
                    .padding(.horizontal, metrics.instructionSide)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, titleTop)
        }
    }

    /// Android's 38 dp X (55 dp on tablets) with 3 dp padding, 17 dp (28 and
    /// 20 dp) in from the panel's top and end. The touch area grows to 44
    /// points around the same centre.
    private func languagePairsCloseButton(_ metrics: LanguagePairsMetrics) -> some View {
        let target = max(44, metrics.closeBox)
        let outset = (target - metrics.closeBox) / 2
        return Button(action: exit) {
            MinikArtworkImage(name: MinikVisualAsset.close)
                .padding(LanguagePairsMetrics.closeImageInset)
                .frame(width: metrics.closeBox, height: metrics.closeBox)
                .frame(width: target, height: target)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close exercise")
        .padding(.top, metrics.closeTop - outset)
        .padding(.trailing, metrics.closeTrailing - outset)
    }

    /// The design's navy Fredoka title, as on the other Language screens.
    private func languagePairsTitle(_ layout: LanguageActivityLayout, metrics: LanguagePairsMetrics) -> some View {
        // Beside the logo and the X the title keeps clear of both on one line.
        let underLogo = LanguagePairsMetrics.titleUnderLogo(layout)
        let width = underLogo ? layout.width : max(1, layout.width - 2 * metrics.titleClearance)
        return Text("Pairs")
            .font(MinikPretty.titleFont(layout.wide ? wideTitleSize : compactTitleSize))
            .foregroundStyle(MinikPretty.navy)
            .multilineTextAlignment(.center)
            .lineLimit(underLogo ? nil : 1)
            .minimumScaleFactor(underLogo ? 1 : 0.5)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: width)
            .accessibilityAddTraits(.isHeader)
    }

    /// The navy Fredoka instruction of the design's game screens (Tower, Picture Memory).
    private func languagePairsInstruction(_ layout: LanguageActivityLayout) -> some View {
        Text("Choose 2 pictures that start with the same letter")
            .font(MinikPretty.bodyFont(layout.wide ? wideInstructionSize : compactInstructionSize))
            .foregroundStyle(MinikPretty.navy)
            .multilineTextAlignment(.center)
            // Android shows two lines at most; accessibility sizes wrap freely
            // and the panel scrolls when it has to.
            .lineLimit(layout.accessibility ? nil : 2)
            .minimumScaleFactor(layout.accessibility ? 1 : 0.8)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
    }

    /// Android's 4 x 2 GridLayout: every row the same height, the tiles inset
    /// by the scroll view's padding plus each tile's own margin.
    private func languagePairsBoard(size: CGSize, metrics: LanguagePairsMetrics, rows: Int) -> some View {
        let gaps = metrics.tileGap * CGFloat(rows - 1)
        let tileArea = size.height - metrics.boardTop - metrics.boardBottom - gaps
        let tileHeight = max(1, tileArea / CGFloat(rows))
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: metrics.tileGap),
            count: LanguagePairsMetrics.columns
        )
        return LazyVGrid(columns: columns, spacing: metrics.tileGap) {
            ForEach(session.mixedBoardItems, id: \.id) { item in
                languagePairTile(item, height: tileHeight)
            }
        }
        .padding(.horizontal, metrics.boardSide)
        .padding(.top, metrics.boardTop)
        .frame(width: size.width, height: size.height, alignment: .top)
        .accessibilityElement(children: .contain)
    }

    private func languagePairsFooter(_ layout: LanguageActivityLayout, metrics: LanguagePairsMetrics) -> some View {
        MinikArtworkImage(name: MinikVisualAsset.cardsMascot)
            .frame(width: metrics.mascotSide, height: metrics.mascotSide)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .leading) {
                languagePairsPoints(layout, metrics: metrics)
                    .padding(.leading, metrics.pointsLeading)
            }
            .padding(.bottom, metrics.mascotBottom)
    }

    private func languagePairsPoints(_ layout: LanguageActivityLayout, metrics: LanguagePairsMetrics) -> some View {
        // Android's sp sizes, growing at most 15% (60% at accessibility sizes)
        // so the fixed-width card keeps one line per row.
        let growthLimit: CGFloat = layout.accessibility ? 1.6 : 1.15
        let baseTitle: CGFloat = layout.wide ? 25 : 14
        let baseValue: CGFloat = layout.wide ? 26 : 20
        let scaledTitle = layout.wide ? widePointsTitleSize : compactPointsTitleSize
        let scaledValue = layout.wide ? widePointsValueSize : compactPointsValueSize
        return LanguagePairsPointsCard(
            titleSize: min(scaledTitle, baseTitle * growthLimit),
            valueSize: min(scaledValue, baseValue * growthLimit),
            width: metrics.pointsWidth,
            minimumHeight: metrics.pointsHeight,
            strokeWidth: metrics.pointsStroke
        )
    }

    private func languagePairTile(_ item: PairsItem, height: CGFloat) -> some View {
        let hidden = hiddenLanguageGroups.contains(item.id.groupIndex)
        let shaking = languagePairFeedbackVisible && session.attemptResult == .incorrect && session.isSelected(item.id)
        return Button { selectItem(item.id) } label: {
            Group {
                if case .imageAsset(let asset) = item.representation {
                    Image(asset.rawValue).resizable().scaledToFit()
                } else {
                    RepresentationView(representation: item.representation, context: .pairsTile)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(LanguagePairTileStyle(selected: session.isSelected(item.id)))
        .frame(height: height)
        .opacity(hidden ? 0 : 1)
        .scaleEffect(hidden && !reduceMotion ? 0.72 : 1)
        .offset(x: shaking && !reduceMotion ? languageShakeOffset : 0)
        .disabled(hidden || session.attemptResult != nil)
        .accessibilityHidden(hidden)
        .accessibilityLabel(item.details.accessibilityLabel ?? item.representation.accessibilityDescription)
        .accessibilityValue(accessibilityValue(for: item))
        .accessibilityHint(accessibilityHint(for: item))
    }

    @MainActor
    private func performLanguagePairTransition() async {
        guard scenePhase == .active, isLanguagePairs, let pending = pendingLanguagePair else { return }
        do {
            try await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled, pendingLanguagePair == pending,
                  presentationIndex == pending.presentation else { return }
            languagePairFeedbackVisible = true
            if lastAudibleLanguagePairID != pending.id {
                lastAudibleLanguagePairID = pending.id
                feedbackSoundPlayer.play(pending.result == .correct ? .correct : .incorrect)
                if pending.result == .correct, encouragementEnabled {
                    // The last pair finishes the board and earns the game-level
                    // praise; every other pair gets a single-match phrase.
                    let completesBoard = session.matchedGroupIndices.count == session.equivalenceSets.count
                    let phrase = completesBoard
                        ? LanguageEncouragementCopy.gameCompleted
                        : LanguageEncouragementCopy.singleMatch.randomElement() ?? "Great job!"
                    speechPlayer.enqueueInterfaceSpeech(interfaceLocaleID.text(phrase), interfaceLocale: interfaceLocaleID)
                }
            }
            if pending.result == .correct {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.33)) {
                    hiddenLanguageGroups.formUnion(session.matchedGroupIndices)
                }
                try await Task.sleep(nanoseconds: 330_000_000)
                if session.matchedGroupIndices.count == session.equivalenceSets.count {
                    try await Task.sleep(nanoseconds: 1_300_000_000)
                }
            } else {
                if reduceMotion {
                    try await Task.sleep(nanoseconds: 430_000_000)
                } else {
                    // Android shake: 0, -7, 7, -4.55, 4.55, 0 over 430 ms.
                    for offset in [-7.0, 7.0, -4.55, 4.55, 0.0] {
                        guard !Task.isCancelled, pendingLanguagePair == pending else { return }
                        withAnimation(.linear(duration: 0.086)) {
                            languageShakeOffset = CGFloat(offset)
                        }
                        try await Task.sleep(nanoseconds: 86_000_000)
                    }
                }
            }
            guard !Task.isCancelled, pendingLanguagePair == pending,
                  presentationIndex == pending.presentation else { return }
            languagePairFeedbackVisible = false
            pendingLanguagePair = nil
            continueAfterAttempt()
        } catch {
            // Exit, backgrounding or a new presentation cancels delayed work.
        }
    }

    private func stopPairAudio() {
        speechPlayer.stop()
        feedbackSoundPlayer.stop()
    }

    private var standardBody: some View {
        MinikPracticeScreen(
            progressLabel: "\(session.matchedGroupIndices.count) / \(session.equivalenceSets.count)",
            onExit: exit
        ) { metrics in
            let compact = metrics.compact

            MinikPracticeSurface(compact: compact) {
                VStack(spacing: compact ? 18 : 24) {
                    headerSection(compact: compact)

                    boardSection(
                        compact: compact,
                        availableWidth: metrics.containerWidth
                    )

                    if session.selectionStyle == .anyTwoTiles {
                        MinikArtworkImage(name: "minik_activity_pairs")
                            .frame(maxWidth: 150)
                            .frame(height: compact ? 82 : 100)
                    }

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

    private func headerSection(compact: Bool) -> some View {
        VStack(spacing: compact ? 10 : 14) {
            Text("Match the pairs")
                .font(.title3.weight(.bold))
                .foregroundStyle(Color(red: 0.15, green: 0.42, blue: 0.54))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(headerInstruction)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color(red: 0.28, green: 0.49, blue: 0.58))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(String(localized: "Tap a selected card again to unselect it."))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color(red: 0.36, green: 0.31, blue: 0.45))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    /// headerInstruction, read aloud when a Math board opens (Android MatchScreen).
    private var mathReadAloudInstruction: String? {
        guard mathActivityFamily != nil else { return nil }
        switch session.selectionStyle {
        case .opposingColumns:
            return String(localized: "Choose one tile from each side that belongs together.")
        case .anyTwoTiles:
            return String(localized: "Match words with their starters")
        }
    }

    private var headerInstruction: LocalizedStringKey {
        switch session.selectionStyle {
        case .opposingColumns:
            "Choose one tile from each side that belongs together."
        case .anyTwoTiles:
            "Match words with their starters"
        }
    }

    @ViewBuilder
    private func boardSection(compact: Bool, availableWidth: CGFloat) -> some View {
        // Each column is named by what it holds. The old "Left side" and "Right
        // side" were never translated and were mirrored in right-to-left layouts.
        let titles = columnTitles
        if session.selectionStyle == .anyTwoTiles {
            mixedBoard(compact: compact, availableWidth: availableWidth)
        } else if shouldStackColumns(for: availableWidth) {
            VStack(spacing: compact ? 14 : 18) {
                boardColumn(
                    title: titles.left,
                    items: session.activeLeftItems,
                    compact: compact
                )
                boardColumn(
                    title: titles.right,
                    items: session.activeRightItems,
                    compact: compact
                )
            }
        } else {
            HStack(alignment: .top, spacing: compact ? 14 : 18) {
                boardColumn(
                    title: titles.left,
                    items: session.activeLeftItems,
                    compact: compact
                )
                boardColumn(
                    title: titles.right,
                    items: session.activeRightItems,
                    compact: compact
                )
            }
        }
    }

    /// "Numbers", "Pictures" or "Exercises" for each column, from all of its cards
    /// (matched ones too, so a title never changes mid-round). When a column mixes
    /// kinds, neither column gets a title rather than a wrong one.
    private var columnTitles: (left: String?, right: String?) {
        guard let left = Self.columnTitle(for: session.leftItems),
              let right = Self.columnTitle(for: session.rightItems) else {
            return (left: nil, right: nil)
        }
        return (left: left, right: right)
    }

    private static func columnTitle(for items: [PairsItem]) -> String? {
        guard let first = items.first,
              let kind = PairsColumnKind(first.representation),
              items.allSatisfy({ PairsColumnKind($0.representation) == kind }) else {
            return nil
        }
        return kind.title
    }

    private func mixedBoard(compact: Bool, availableWidth: CGFloat) -> some View {
        let columnCount = dynamicTypeSize >= .accessibility1 || availableWidth < 360 ? 1 : 2
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: compact ? 10 : 14),
            count: columnCount
        )

        return LazyVGrid(
            columns: columns,
            spacing: compact ? 10 : 14
        ) {
            ForEach(session.activeMixedItems, id: \.id) { item in
                pairTile(item: item, compact: compact)
            }
        }
        .padding(compact ? 10 : 14)
        .background(
            RoundedRectangle(cornerRadius: compact ? 24 : 28, style: .continuous)
                .fill(Color(red: 0.94, green: 0.98, blue: 1.0).opacity(0.86))
        )
        .overlay {
            RoundedRectangle(cornerRadius: compact ? 24 : 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.9), lineWidth: 1.1)
        }
        .accessibilityElement(children: .contain)
    }

    private func shouldStackColumns(for availableWidth: CGFloat) -> Bool {
        dynamicTypeSize >= .accessibility1 || availableWidth < 560
    }

    private func boardColumn(
        title: String?,
        items: [PairsItem],
        compact: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: compact ? 12 : 14) {
            if let title {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color(red: 0.18, green: 0.43, blue: 0.54))
            }

            ForEach(items, id: \.id) { item in
                pairTile(item: item, compact: compact)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(compact ? 14 : 18)
        .background(
            RoundedRectangle(cornerRadius: compact ? 24 : 28, style: .continuous)
                .fill(Color(red: 0.94, green: 0.98, blue: 1.0).opacity(0.86))
        )
        .overlay {
            RoundedRectangle(cornerRadius: compact ? 24 : 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.9), lineWidth: 1.1)
        }
    }

    private func pairTile(
        item: PairsItem,
        compact: Bool
    ) -> some View {
        Button {
            selectItem(item.id)
        } label: {
            VStack(spacing: 10) {
                RepresentationView(
                    representation: item.representation,
                    context: .pairsTile
                )

                if session.attemptResult == .incorrect,
                   isPartOfIncorrectAttempt(item.id) {
                    Label("Try a different match", systemImage: "arrow.counterclockwise.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color(red: 0.82, green: 0.38, blue: 0.26))
                } else if session.isSelected(item.id) {
                    Label("Selected", systemImage: "checkmark.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color(red: 0.18, green: 0.56, blue: 0.76))
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: compact ? 24 : 28, style: .continuous))
        }
        .buttonStyle(
            MinikMatchTileStyle(
                state: tileState(for: item),
                compact: compact
            )
        )
        .disabled(session.attemptResult != nil)
        .accessibilityLabel(item.details.accessibilityLabel ?? item.representation.accessibilityDescription)
        .accessibilityValue(accessibilityValue(for: item))
        .accessibilityHint(accessibilityHint(for: item))
    }

    private func tileState(
        for item: PairsItem
    ) -> MinikMatchTileStyle.State {
        if session.attemptResult == .incorrect,
           isPartOfIncorrectAttempt(item.id) {
            return .incorrect
        }

        if session.isSelected(item.id) {
            return .selected
        }

        return .idle
    }

    private func isPartOfIncorrectAttempt(_ itemID: PairsItemID) -> Bool {
        guard session.attemptResult == .incorrect else {
            return false
        }

        return session.isSelected(itemID)
    }

    private func accessibilityValue(for item: PairsItem) -> String {
        if session.attemptResult == .incorrect,
           isPartOfIncorrectAttempt(item.id) {
            return interfaceLocaleID.text("Incorrect match selected")
        }
        if session.isSelected(item.id) {
            return interfaceLocaleID.text("Selected")
        }
        return interfaceLocaleID.text("Not selected")
    }

    private func accessibilityHint(
        for item: PairsItem
    ) -> String {
        if session.attemptResult == .incorrect,
           isPartOfIncorrectAttempt(item.id) {
            return interfaceLocaleID.text("Incorrect match selected")
        }

        if session.isSelected(item.id) {
            return interfaceLocaleID.text("Selected")
        }

        return interfaceLocaleID.text("Double tap to choose this tile")
    }

    @ViewBuilder
    private func continueButton(for attemptResult: PairsAttemptResult) -> some View {
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

    private func continueAfterAttempt() {
        let wasComplete = session.isComplete
        let matched = session.attemptResult == .correct
        session.continueAfterAttempt()
        if matched { mathAttemptIndex = 0 }
        attemptStartedAt = Date()

        if !wasComplete && session.isComplete {
            if !isLanguagePairs { speechPlayer.stop() }
            if let nextSession = makeNextSession?() {
                session = nextSession
                hiddenLanguageGroups = []
                languagePairFeedbackVisible = false
                presentationIndex += 1
                attemptStartedAt = Date()
                return
            }
            onComplete()
        }
    }

    private func selectItem(_ itemID: PairsItemID) {
        // Two columns: a tap on another card of a side that already has a choice
        // moves the choice there. A tap on the chosen card itself unselects it
        // (PairsSession.selectItem).
        if session.selectionStyle == .opposingColumns, session.attemptResult == nil {
            let chosenOnSide = itemID.side == .left
                ? session.selectedLeftItemID
                : session.selectedRightItemID
            if let chosenOnSide, chosenOnSide != itemID {
                session.selectItem(chosenOnSide)
            }
        }
        let previousResult = session.attemptResult
        if let utterance = session.selectItem(itemID) {
            speechPlayer.speak(utterance)
        }
        guard previousResult == nil,
              let result = session.attemptResult else {
            return
        }
        if isLanguagePairs {
            pendingLanguagePair = LanguagePairTransition(presentation: presentationIndex, result: result)
        }
        let gradedResult: GradedAttemptResult = result == .correct ? .correct : .incorrect
        let duration = Date().timeIntervalSince(attemptStartedAt)

        if mathActivityFamily == nil {
            guard progressActivityFamily == .pairs,
                  let languageSkillID,
                  case .contentItem(let contentItemID) = session.attemptedSemanticValue,
                  let attempt = languageAttemptTracker.makeAttempt(
                      presentationIndex: presentationIndex,
                      contentItemID: contentItemID,
                      result: gradedResult,
                      responseDurationSeconds: duration,
                      skillID: languageSkillID
                  ) else {
                return
            }
            onAttempt(attempt)
            return
        }

        mathAttemptIndex += 1
        guard let family = progressActivityFamily,
              let attempt = ActivityAttemptData(
                  itemID: ActivityItemID(
                      rawValue: "\(mathLevelID.rawValue.lowercased()).pairs.\(itemID.groupIndex)"
                  ),
                  attemptIndex: mathAttemptIndex,
                  result: gradedResult,
                  responseDurationSeconds: duration,
                  activityFamily: family,
                  mathLevelID: mathLevelID,
                  skillID: MathSkillIDs.equivalentValues
              ) else {
            return
        }
        onAttempt(attempt)
    }

    private func exit() {
        pendingLanguagePair = nil
        stopPairAudio()
        onExit()
    }
}

/// What a two-column Pairs board column holds, for its title.
private enum PairsColumnKind: Equatable {
    case numbers
    case pictures
    case exercises

    init?(_ representation: Representation) {
        switch representation {
        case .imageAsset, .visualQuantity:
            self = .pictures
        case .mathExpression:
            self = .exercises
        case .math(let math):
            switch math {
            case .numeral, .decimal:
                self = .numbers
            case .quantity, .groupedQuantity, .equalGroups, .placeValue:
                self = .pictures
            case .arithmeticExpression, .missingValueExpression:
                self = .exercises
            default:
                return nil
            }
        default:
            return nil
        }
    }

    var title: String {
        switch self {
        case .numbers: return String(localized: "Numbers")
        case .pictures: return String(localized: "Pictures")
        case .exercises: return String(localized: "Exercises")
        }
    }
}

/// Android Letter Pairs geometry in points: fragment_letter_pairs.xml on
/// phones and its layout-sw600dp variant on iPad. Picture tiles do not grow
/// with Dynamic Type; only the text rows do, and the tiles take the height
/// the panel has left.
private struct LanguagePairsMetrics {
    static let columns = 2
    static let androidRows = 4
    static let closeImageInset: CGFloat = 3
    /// Line height per point of text size, used to estimate the header.
    static let lineHeightRatio: CGFloat = 1.25

    let logoHeight: CGFloat
    let logoLeading: CGFloat
    let logoTop: CGFloat
    let closeBox: CGFloat
    let closeTop: CGFloat
    let closeTrailing: CGFloat
    let titleTop: CGFloat
    let titleClearance: CGFloat
    let instructionGap: CGFloat
    let instructionSide: CGFloat
    let boardTop: CGFloat
    let boardSide: CGFloat
    let boardBottom: CGFloat
    let tileGap: CGFloat
    let minimumTile: CGFloat
    let mascotSide: CGFloat
    let mascotBottom: CGFloat
    let pointsLeading: CGFloat
    let pointsWidth: CGFloat
    let pointsHeight: CGFloat
    let pointsStroke: CGFloat

    init(wide: Bool) {
        logoHeight = wide ? 95 : 70
        logoLeading = wide ? 8 : 0
        logoTop = wide ? 12 : 0
        closeBox = wide ? 55 : 38
        closeTop = wide ? 28 : 17
        closeTrailing = wide ? 20 : 17
        titleTop = wide ? 75 : 48
        // The logo's width, or the X with its end margin, plus a little air.
        titleClearance = wide ? 104 : 72
        instructionGap = wide ? 18 : 6
        instructionSide = wide ? 12 : 8
        // Scroll view padding 12 dp (8 dp on phones) plus the tile margin.
        boardTop = wide ? 20 : 13
        // Scroll view padding 18 dp (12 dp) plus the tile margin.
        boardSide = wide ? 26 : 17
        // Tile margin, scroll view padding and the gap above the mascot.
        boardBottom = wide ? 26 : 17
        // Two tile margins of 8 dp (5 dp).
        tileGap = wide ? 16 : 10
        // The board's minHeight, 456 dp (304 dp on phones), less the tile
        // margins of its four rows.
        minimumTile = wide ? 98 : 66
        mascotSide = wide ? 180 : 120
        mascotBottom = wide ? 18 : 12
        pointsLeading = wide ? 20 : 10
        pointsWidth = wide ? 155 : 85
        pointsHeight = wide ? 100 : 52
        // The choice screens' score tiles (LanguagePracticeStats) keep a 1.5-point rim.
        pointsStroke = 1.5
    }

    /// The minik_plus_logo artwork is 121 x 131 pixels.
    var logoWidth: CGFloat {
        logoHeight * 121 / 131
    }

    /// The title's own row under the logo, used by titleUnderLogo layouts.
    var accessibleTitleTop: CGFloat {
        logoTop + logoHeight + instructionGap
    }

    /// Phones at accessibility sizes have no room for the title between the
    /// logo and the X, so it moves under the logo. On iPad every localized
    /// title still fits there on one line, where Android keeps it.
    static func titleUnderLogo(_ layout: LanguageActivityLayout) -> Bool {
        layout.accessibility && !layout.wide
    }

    /// Android's fixed four rows of two; a larger board adds rows.
    static func rows(itemCount: Int) -> Int {
        max(androidRows, (itemCount + columns - 1) / columns)
    }
}

/// Android's totalScoreCard: "Points" over the running total in a pale violet
/// card, 85 x 52 dp on phones and 155 x 100 dp on tablets, in the style of the
/// choice screens' score tiles (LanguagePracticeStats): Fredoka text and a soft
/// shadow that lifts it off the glass panel.
private struct LanguagePairsPointsCard: View {
    let titleSize: CGFloat
    let valueSize: CGFloat
    let width: CGFloat
    let minimumHeight: CGFloat
    let strokeWidth: CGFloat
    @Environment(\.languageRewardState) private var rewards

    var body: some View {
        VStack(spacing: 1) {
            Text("Points")
                .font(MinikPretty.titleFont(titleSize))
                .foregroundStyle(Color(red: 0.384, green: 0.325, blue: 0.773))
            Text(rewards.points, format: .number)
                .font(MinikPretty.titleFont(valueSize))
                .monospacedDigit()
                .foregroundStyle(Color(red: 0.286, green: 0.220, blue: 0.710))
        }
        // A fixed width as on Android: larger text shrinks onto one line.
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .frame(width: width)
        .frame(minHeight: minimumHeight)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 0.969, green: 0.961, blue: 1))
                .shadow(color: MinikPretty.navy.opacity(0.08), radius: 3, x: 0, y: 2)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(red: 0.545, green: 0.486, blue: 0.965), lineWidth: strokeWidth)
        }
        .accessibilityElement(children: .combine)
    }
}
