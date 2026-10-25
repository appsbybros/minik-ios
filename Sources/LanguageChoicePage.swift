import SwiftUI

/// Android WriteScreen's four choice compositions (fragment_choose_right_image in the
/// Plus rainbow-sky design): the speaker and close header, the navy instruction, the
/// prompt, the white answer tiles, the sunny Next pill and the statistics on the glass
/// panel, at Android's sizes (its sw600dp tablet layout on iPad). They share
/// mechanics, not an adaptive tile grid. Below the
/// accessibility text sizes every row is sized from the panel, so the whole board fits
/// and labels shrink instead of wrapping. Accessibility sizes keep their preferred text
/// sizes, let rows grow, and LanguageActivityScreen scrolls the board.
struct LanguageChoicePage: View {
    let challenge: Challenge
    let presentation: MultipleChoicePresentation
    /// The current answer's result, which colours the chosen option.
    let result: MultipleChoiceAnswerResult?
    /// Minik's reaction on the board. It can outlast `result`: as on Android, the success
    /// jump and the streak stars play to the end over the next word.
    let reaction: MultipleChoiceAnswerResult?
    let selectedChoiceID: ChoiceID?
    let canSelect: Bool
    let canSkip: Bool
    let feedbackStartedAt: Date
    let successAsset: String
    let successDirection: Double
    let feedbackBonusRun: Int
    let encouragementEnabled: Bool
    let onSelect: (ChoiceID) -> Void
    let onReplay: () -> Void
    let onSkip: () -> Void
    let onExit: () -> Void
    @Environment(\.interfaceLocaleID) private var interfaceLocaleID
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let instruction = interfaceLocaleID.text(presentation.instructionKey)
        let typeSize = dynamicTypeSize
        let choicePresentation = presentation
        let choiceCount = challenge.choices.count
        let promptCount = challenge.prompt.representations.count
        LanguageActivityScreen(panelStyle: .rounded, minimumContentHeight: { width, wide in
            LanguageChoiceMetrics(width: width, height: 0, wide: wide, typeSize: typeSize,
                                  presentation: choicePresentation, choiceCount: choiceCount,
                                  promptCount: promptCount, instruction: instruction).minimumHeight
        }) { layout in
            let sizes = LanguageChoiceMetrics(width: layout.width, height: layout.height, wide: layout.wide,
                                              typeSize: typeSize, presentation: choicePresentation,
                                              choiceCount: choiceCount, promptCount: promptCount,
                                              instruction: instruction)
            // At least the board height, so the spacer keeps the statistics at the bottom; at
            // accessibility sizes taller when the rows need more, and the panel then scrolls.
            let boardLayout = ChoiceBoardFillLayout(minimumHeight: layout.height)
            boardLayout {
                VStack(spacing: 0) {
                    LanguagePanelNavigation(wide: layout.wide, header: .practice, scale: sizes.boardScale,
                                            onReplay: onReplay, onExit: onExit)
                    instructionText(instruction, sizes: sizes)
                        .padding(.top, sizes.instructionGap)
                    // At accessibility sizes every row keeps its natural height, so only the
                    // spacer stretches when the board fills the panel.
                    ForEach(Array(challenge.prompt.representations.enumerated()), id: \.offset) { _, representation in
                        promptView(representation, sizes: sizes)
                            .fixedSize(horizontal: false, vertical: sizes.accessible)
                            .accessibilityLabel(challenge.prompt.learningSpeechCue?.text ?? representation.accessibilityDescription)
                            .padding(.top, sizes.promptGap)
                    }
                    answerBoard(sizes)
                        .fixedSize(horizontal: false, vertical: sizes.accessible)
                        .padding(.top, sizes.answersGap)
                    nextSlot(sizes)
                    Spacer(minLength: 0)
                    LanguagePracticeStats(wide: layout.wide, scale: sizes.boardScale)
                        .padding(.bottom, sizes.statsBottom)
                }
                // Below the accessibility sizes the rows add up exactly, so the board keeps
                // a fixed height: the panel's, or the smallest board when even that is taller.
                .frame(height: sizes.accessible ? nil : max(layout.height, sizes.minimumHeight))
            }
            // The board sizes its overlays, so the reaction covers it inside a scroll view too.
            // Next's slot publishes where the pill goes, and the button is drawn there above
            // the reaction.
            .overlayPreferenceValue(ChoiceNextPillKey.self) { pillAnchor in
                reactionLayer(pillAnchor: pillAnchor, wide: layout.wide, sizes: sizes)
            }
        }
    }

    /// The height of LanguagePracticeReaction's try-again artwork (Android's 165 x 220 dp).
    private static let tryAgainHeight: CGFloat = 220

    /// Minik's reaction and the stars across the whole panel, above the Next button, as
    /// Android draws them: the try-again Minik covers everything while he shows (owner
    /// report, 14 October 2026), and Next is seen once he leaves after 1.5 seconds.
    private func reactionLayer(pillAnchor: Anchor<CGRect>?, wide: Bool, sizes: LanguageChoiceMetrics) -> some View {
        let outset = CGSize(width: LanguagePanelInsets.horizontal(wide: wide),
                            height: LanguagePanelInsets.vertical(wide: wide))
        return GeometryReader { geometry in
            let pill: CGRect? = pillAnchor.map { geometry[$0] }
            // Android's feedback spans the panel itself: the try-again Minik stands on the
            // panel's bottom edge and the success jump crosses the whole panel. When the
            // board scrolls, that is the panel the child sees, not the board's full height.
            let panel = geometry.languageVisiblePanel(outset: outset)
            let pillMiddle: CGFloat? = pill.map { $0.midY - panel.minY }
            ZStack {
                if canSkip, let pill {
                    nextButton(sizes)
                        .frame(width: pill.width, height: pill.height)
                        .position(x: pill.midX, y: pill.midY)
                }
                feedbackLayer(sizes: sizes, pillMiddle: pillMiddle)
                    .frame(width: panel.width, height: panel.height)
                    .position(x: panel.midX, y: panel.midY)
            }
        }
    }

    /// The twinkling stars and Minik's reaction, across the whole panel as on Android. On
    /// iPad they keep the phone's proportions: Android draws Minik at 200 x 265 dp beside
    /// 120 dp pictures and the iPad pictures are 170 points, so the layer is laid out in a
    /// panel reduced by that factor and drawn enlarged from its bottom edge. Minik still
    /// stands on the panel's edge, and the jump and the stars still cross the whole panel.
    /// `pillMiddle` is the middle of the Next pill, measured from the panel's top.
    private func feedbackLayer(sizes: LanguageChoiceMetrics, pillMiddle: CGFloat?) -> some View {
        GeometryReader { geometry in
            let scale = reactionScale(sizes: sizes, panelHeight: geometry.size.height, pillMiddle: pillMiddle)
            ZStack(alignment: .bottom) {
                if let reaction {
                    LanguagePracticeReaction(correct: reaction == .correct, startedAt: feedbackStartedAt,
                                             successAsset: successAsset, direction: successDirection)
                }
                // Android's stars are the screen's last views, so they twinkle over Minik.
                if reaction == .correct && feedbackBonusRun >= 3 {
                    LanguagePracticeStars(startedAt: feedbackStartedAt, usesFaces: false,
                                          duration: encouragementEnabled ? 4 : 1.2).id(feedbackStartedAt)
                }
            }
            .frame(width: geometry.size.width / scale, height: geometry.size.height / scale)
            .scaleEffect(scale, anchor: .bottom)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .bottom)
        }
        .allowsHitTesting(false)
    }

    /// How much the reaction layer is enlarged. On iPad the try-again Minik grows only
    /// until its head reaches the middle of the Next pill, as in Android's screenshot, and
    /// never below Android's own tablet size (165 x 220 dp, with the board's scale).
    private func reactionScale(sizes: LanguageChoiceMetrics, panelHeight: CGFloat, pillMiddle: CGFloat?) -> CGFloat {
        let full = sizes.feedbackScale
        guard reaction == .incorrect, let pillMiddle, full > sizes.boardScale else { return full }
        let reach = (panelHeight - pillMiddle) / Self.tryAgainHeight
        return min(full, max(sizes.boardScale, reach))
    }

    /// The design's navy Fredoka title.
    private func instructionText(_ instruction: String, sizes: LanguageChoiceMetrics) -> some View {
        Text(instruction)
            .font(MinikPretty.titleFont(sizes.instructionFontSize))
            .foregroundStyle(LanguagePracticePalette.ink)
            .multilineTextAlignment(.center)
            .lineLimit(sizes.accessible ? nil : sizes.instructionLines)
            .minimumScaleFactor(sizes.accessible ? 1 : 0.6)
            .fixedSize(horizontal: false, vertical: sizes.accessible)
            // Android keeps the instruction 40 dp from the panel's sides.
            .padding(.horizontal, sizes.instructionInset)
            // Claims its budgeted lines before the spacer takes the slack; otherwise the
            // stack offers it about half and the instruction shrinks onto one line.
            .layoutPriority(1)
    }

    @ViewBuilder
    private func promptView(_ representation: Representation, sizes: LanguageChoiceMetrics) -> some View {
        switch representation {
        case .imageAsset(let asset):
            Image(asset.rawValue).resizable().scaledToFit()
                .padding(sizes.promptImageInset)
                .frame(width: sizes.promptSide, height: sizes.promptSide)
        case .learningText(let value):
            LanguageChoiceText(value: value, font: .custom("Fredoka-Medium", fixedSize: sizes.promptFontSize),
                               grows: sizes.accessible)
                .foregroundStyle(LanguagePracticePalette.ink)
                .languageFakeBold(LanguagePracticePalette.ink, spread: sizes.promptBoldSpread)
                .padding(.horizontal, sizes.promptInset)
                .frame(maxWidth: .infinity, minHeight: sizes.promptSide,
                       maxHeight: sizes.accessible ? nil : sizes.promptSide)
        default:
            LanguagePracticeRepresentation(representation: representation, fontSize: sizes.promptFontSize)
                .foregroundStyle(LanguagePracticePalette.ink)
                .frame(maxWidth: .infinity, minHeight: sizes.promptSide,
                       maxHeight: sizes.accessible ? nil : sizes.promptSide)
        }
    }

    @ViewBuilder
    private func answerBoard(_ sizes: LanguageChoiceMetrics) -> some View {
        let pictures = presentation.usesPictureAnswers
        let gap = sizes.gap
        if pictures {
            // Pictures hold no text, so two per row (2x2 for four answers) fit at every text size.
            VStack(spacing: sizes.rowGap) {
                ForEach(Array(choiceRows(columns: sizes.columns).enumerated()), id: \.offset) { _, row in
                    HStack(spacing: gap) {
                        ForEach(row, id: \.id) { choice in
                            choiceButton(choice, sizes: sizes)
                        }
                    }
                }
            }
        } else {
            // Android's stacked text options, 45 dp from the panel's sides.
            VStack(spacing: gap) {
                ForEach(challenge.choices, id: \.id) { choice in
                    choiceButton(choice, sizes: sizes)
                }
            }
            .frame(maxWidth: sizes.rowWidth)
        }
    }

    private func choiceRows(columns: Int) -> [[Choice]] {
        let choices = challenge.choices
        let step = max(1, columns)
        return stride(from: 0, to: choices.count, by: step).map { start in
            Array(choices[start..<min(start + step, choices.count)])
        }
    }

    /// Android's sunny Next pill (bg_next_link), shown after a wrong attempt without
    /// changing the target on retry. The slot is always reserved, so the answers never
    /// move when Next appears. The slot only holds an invisible copy of the pill and
    /// publishes its bounds: reactionLayer draws the button there, under Minik's
    /// reaction.
    private func nextSlot(_ sizes: LanguageChoiceMetrics) -> some View {
        ZStack(alignment: .top) {
            if canSkip {
                nextPill(sizes, action: {})
                    .opacity(0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .anchorPreference(key: ChoiceNextPillKey.self, value: .bounds) { $0 }
                    .padding(.top, sizes.nextTop)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: sizes.nextSlotHeight, alignment: .top)
    }

    /// The design's glossy yellow pill with its navy Fredoka label, at least 52 points
    /// tall (LanguageChoiceMetrics budgets for it).
    private func nextPill(_ sizes: LanguageChoiceMetrics, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("Next")
                .font(MinikPretty.titleFont(sizes.nextFontSize))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .buttonStyle(MinikPrettyButtonStyle(.yellow))
    }

    private func nextButton(_ sizes: LanguageChoiceMetrics) -> some View {
        nextPill(sizes, action: onSkip)
    }

    private func choiceButton(_ choice: Choice, sizes: LanguageChoiceMetrics) -> some View {
        let feedback: LanguageAnswerStyle.State = selectedChoiceID == choice.id
            ? (result == .correct ? .correct : .incorrect) : .idle
        let pictures = presentation.usesPictureAnswers
        // LanguageAnswerStyle frames the label with 7 more points on each axis.
        let side = max(37, sizes.answerSide - 7)
        return Button { onSelect(choice.id) } label: {
            answerLabel(choice.representation, sizes: sizes)
                // Android pads the picture 8 dp inside its card and the text 6 dp at its sides.
                .padding(.horizontal, pictures ? 8 : 6)
                .padding(.vertical, pictures ? 8 : 2)
                .frame(maxWidth: pictures ? side : .infinity)
                .frame(minHeight: side, maxHeight: sizes.accessible && !pictures ? nil : side)
        }
        .buttonStyle(LanguageAnswerStyle(state: feedback, colorDuration: pictures ? 0.3 : 0.5))
        .disabled(!canSelect)
        .accessibilityLabel(choice.learningSpeechCue?.text ?? choice.representation.accessibilityDescription)
        .accessibilityValue(interfaceLocaleID.text(feedback.accessibilityKey))
        .accessibilityHint("Double tap to choose")
    }

    @ViewBuilder
    private func answerLabel(_ representation: Representation, sizes: LanguageChoiceMetrics) -> some View {
        switch representation {
        case .imageAsset(let asset):
            Image(asset.rawValue).resizable().scaledToFit()
        case .learningText(let value):
            // The design's Fredoka Bold, navy on the white tile.
            LanguageChoiceText(value: value, font: MinikPretty.titleFont(sizes.answerFontSize),
                               grows: sizes.accessible)
        default:
            LanguagePracticeRepresentation(representation: representation, fontSize: sizes.answerFontSize)
        }
    }
}

/// Gives the choice board at least the panel's height, so its spacer can hold the
/// statistics at the bottom inside the panel's scroll view, and its natural height
/// when the rows need more, so the panel scrolls instead of clipping. Below the
/// accessibility sizes the board's fixed height passes straight through.
private struct ChoiceBoardFillLayout: Layout {
    let minimumHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let board = subviews.first else { return .zero }
        let natural = board.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: proposal.width ?? natural.width, height: max(minimumHeight, natural.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center,
                              proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}

/// The Next pill's bounds, published by its slot in the board so that the button can
/// be drawn in the reaction layer, under Minik.
private struct ChoiceNextPillKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

/// Sizes for one choice board, from Android's layout in dp: the phone layout, and on iPad
/// its sw600dp tablet layout (larger speaker, instruction, word, pictures and statistics)
/// with the text answers and picture prompt a quarter to a third larger than on phones, so
/// they keep the phone's proportions. Below the accessibility sizes every row gets a fixed
/// height from the panel: the Next gap gives up its extra room first, then the answers down
/// to a comfortable size, then the prompt, then the answers again, down to sizes that still
/// read and tap well. Accessibility sizes keep the preferred text sizes and let the text
/// rows grow; the screen scrolls what does not fit. On iPads larger than the iPad mini the
/// whole iPad composition is enlarged with the panel (boardScale, at most 25%), so the
/// board keeps the iPad mini's proportions instead of leaving the larger panel empty.
private struct LanguageChoiceMetrics {
    let accessible: Bool
    /// 1 on phones and on the iPad mini; on larger iPads the factor by which the panel
    /// exceeds the iPad mini's 642 x 1001-point content area, at most 1.25.
    let boardScale: CGFloat
    /// How much Minik's reaction layer is enlarged (see LanguageChoicePage.feedbackLayer).
    let feedbackScale: CGFloat
    let instructionGap: CGFloat
    let instructionFontSize: CGFloat
    let instructionLines: Int
    let instructionInset: CGFloat
    let promptGap: CGFloat
    let promptSide: CGFloat
    let promptFontSize: CGFloat
    let promptBoldSpread: CGFloat
    let promptInset: CGFloat
    let promptImageInset: CGFloat
    let answersGap: CGFloat
    let columns: Int
    let gap: CGFloat
    let rowGap: CGFloat
    let rowWidth: CGFloat
    let answerSide: CGFloat
    let answerFontSize: CGFloat
    let nextFontSize: CGFloat
    let nextTop: CGFloat
    let nextHitPadding: CGFloat
    let nextSlotHeight: CGFloat
    let statsBottom: CGFloat
    /// The board with every row at its smallest size; 0 at accessibility sizes, whose rows
    /// grow with their text and simply scroll.
    let minimumHeight: CGFloat

    init(width: CGFloat, height: CGFloat, wide: Bool, typeSize: DynamicTypeSize,
         presentation: MultipleChoicePresentation, choiceCount: Int, promptCount: Int,
         instruction: String) {
        let accessible = typeSize.isAccessibilitySize
        let pictures = presentation.usesPictureAnswers
        let picturePrompt = presentation.usesPicturePrompt
        let count = max(1, choiceCount)
        let prompts = CGFloat(max(1, promptCount))
        let sideInset = LanguagePanelInsets.horizontal(wide: wide)
        // The smallest-board estimate passes no height and gets the iPad mini's sizes.
        let panelGrowth = min(width / 642, height / 1001)
        let boardScale: CGFloat = wide ? min(1.25, max(1, panelGrowth)) : 1

        // The speaker and close header, then the instruction 10 dp below the speaker
        // (20 dp on tablets): 22 sp bold (35 sp), 40 dp from the panel's sides.
        let headerHeight = LanguagePanelHeader.practice.height(wide: wide, scale: boardScale)
        let instructionGap: CGFloat = (wide ? 20 : 10) * boardScale
        let instructionBase: CGFloat = (wide ? 35 : 22) * boardScale
        let instructionFontSize = instructionBase * LanguageTypeRamp.scale(wide ? .title2 : .title3, typeSize)
        let instructionInset = max(0, 40 * boardScale - sideInset)
        let instructionWidth = max(1, width - 2 * instructionInset)
        // Bold Hebrew letters average about 0.62 em (English a little less), spaces 0.28 em.
        let instructionSpaces = instruction.filter { $0 == " " }.count
        let instructionLetters = instruction.count - instructionSpaces
        let instructionEms = CGFloat(instructionLetters) * 0.62 + CGFloat(instructionSpaces) * 0.28
        let instructionTextWidth = instructionEms * instructionFontSize
        let instructionNeed = Int((instructionTextWidth / instructionWidth).rounded(.up))
        let instructionLines = min(accessible ? 6 : 3, max(1, instructionNeed))
        let instructionHeight = CGFloat(instructionLines) * LanguageTypeRamp.lineHeight(instructionFontSize)

        // The prompt: the learned word or letter in Fredoka Medium (50 sp, 100 sp on
        // tablets, one 1.21-em line) 2 dp below the instruction (5 dp), or the picture in
        // Android's 132 dp frame with 10 dp padding, 2 dp below (18 dp, a third larger, on iPad).
        let wordScale = LanguageTypeRamp.scale(.title, typeSize)
        let promptBase: CGFloat = (wide ? 100 : 50) * boardScale
        let preferredPromptFont = promptBase * wordScale
        let promptGap: CGFloat
        let preferredPrompt: CGFloat
        let smallestPrompt: CGFloat
        if picturePrompt {
            promptGap = (wide ? 18 : 2) * boardScale
            preferredPrompt = (wide ? 176 : 132) * boardScale
            smallestPrompt = (wide ? 120 : 92) * boardScale
        } else {
            promptGap = (wide ? 5 : 2) * boardScale
            preferredPrompt = (preferredPromptFont * 1.21).rounded(.up)
            let smallestWord: CGFloat = (wide ? 96 : 54) * boardScale
            smallestPrompt = accessible ? preferredPrompt : min(preferredPrompt, smallestWord)
        }
        // The answers start 6 dp below the prompt (20 dp on tablets, 25 dp under a picture).
        let answersGap: CGFloat = (wide ? (picturePrompt ? 25 : 20) : 6) * boardScale

        // Pictures: Android's 120 dp cards (170 dp on tablets) in the 5 + 2 dp gradient
        // frame, 15 dp apart (20 dp) with 8 dp between the rows. Words and letters: 68 dp
        // and 48 dp frames (a quarter taller on iPad), 14 dp apart (18 dp).
        let columns = pictures ? min(2, count) : 1
        let rows = (count + columns - 1) / columns
        let rowCount = CGFloat(rows)
        let gapBase: CGFloat = pictures ? (wide ? 20 : 15) : (wide ? 18 : 14)
        let gap = gapBase * boardScale
        let rowGap: CGFloat = pictures ? 8 * boardScale : gap
        let rowGaps = rowGap * CGFloat(rows - 1)
        let answerBase: CGFloat = (wide ? 28 : 22) * boardScale
        let preferredAnswerFont = answerBase * wordScale
        let preferredAnswer: CGFloat
        let comfortableAnswer: CGFloat
        let smallestAnswer: CGFloat
        if pictures {
            let widthLimit = (width - gap * CGFloat(columns - 1)) / CGFloat(columns)
            let designPicture: CGFloat = (wide ? 177 : 127) * boardScale
            let comfortablePicture: CGFloat = (wide ? 150 : 112) * boardScale
            let smallestPicture: CGFloat = (wide ? 110 : 84) * boardScale
            preferredAnswer = max(44, min(designPicture, widthLimit))
            comfortableAnswer = min(preferredAnswer, comfortablePicture)
            smallestAnswer = min(preferredAnswer, smallestPicture)
        } else {
            let designRow: CGFloat = presentation == .firstLetterPictureToLetter ? 48 : 68
            let rowScale: CGFloat = (wide ? 1.25 : 1) * boardScale
            let scaledRow = designRow * rowScale
            preferredAnswer = max(scaledRow, LanguageTypeRamp.lineHeight(preferredAnswerFont) + 11)
            smallestAnswer = accessible ? preferredAnswer : 44
            comfortableAnswer = max(smallestAnswer, min(preferredAnswer, scaledRow - 10))
        }

        // Next: 18 sp (40 sp on tablets), up to 35 dp under the answers, on the design's
        // glossy pill: 9 points above the label and 12 below it, at least 52 points tall.
        // Even a squeezed board keeps 20 points (24 on tablets) above the pill and 18 (22)
        // between it and the statistics (owner QA, 25 October 2026: the pill sat tight
        // between the last answer and the statistics on the iPhone SE).
        let nextBase: CGFloat = (wide ? 40 : 18) * boardScale
        let nextLimit: CGFloat = accessible ? 2 : 1.3
        let nextFontSize = nextBase * min(LanguageTypeRamp.scale(.body, typeSize), nextLimit)
        let pillHeight = max(52, LanguageTypeRamp.lineHeight(nextFontSize) + 21)
        let nextHitPadding = max(0, (44 - pillHeight) / 2)
        let nextGapFloor: CGFloat = (wide ? 24 : 20) * boardScale
        let nextGapSmallest = max(nextGapFloor, nextHitPadding)
        let nextGapPreferred = max(nextGapSmallest, 35 * boardScale)
        let nextBelow = max(nextHitPadding, (wide ? 22 : 18) * boardScale)

        // The statistics sit 15 dp above the panel's bottom (25 dp on tablets).
        let statsMargin: CGFloat = (wide ? 25 : 15) * boardScale
        let statsBottom = max(0, statsMargin - LanguagePanelInsets.vertical(wide: wide))
        let statsHeight = LanguageStatsMetrics.height(wide: wide, typeSize: typeSize, scale: boardScale)
        let statisticsHeight = statsHeight + statsBottom

        // Rows that keep their height: header, instruction, the gaps, the Next row at its
        // smallest gap and the statistics with their bottom margin.
        let upperHeight = headerHeight + instructionGap + instructionHeight + promptGap * prompts + answersGap
        let lowerHeight = rowGaps + nextGapSmallest + pillHeight + nextBelow + statisticsHeight
        let fixedHeight = upperHeight + lowerHeight

        let available = height - fixedHeight
        let preferredPrompts = preferredPrompt * prompts
        let spare = max(0, available - preferredPrompts - preferredAnswer * rowCount)
        let nextExtra = accessible ? 0 : min(nextGapPreferred - nextGapSmallest, spare)
        let room = available - nextExtra
        let firstAnswer = min(preferredAnswer,
                              max(comfortableAnswer, (room - preferredPrompts) / rowCount))
        let promptSide = min(preferredPrompt,
                             max(smallestPrompt, (room - firstAnswer * rowCount) / prompts))
        let answerSide = min(firstAnswer,
                             max(smallestAnswer, (room - promptSide * prompts) / rowCount))
        let nextGap = nextGapSmallest + nextExtra

        // A fixed row keeps one line of its text; longer words shrink to fit (minimumScaleFactor).
        let promptFontSize = accessible
            ? preferredPromptFont : min(preferredPromptFont, max(12, promptSide / 1.21))
        let answerFontSize = accessible
            ? preferredAnswerFont : min(preferredAnswerFont, max(12, (answerSide - 11) / 1.3))
        let answerMargin = max(0, 45 - sideInset)
        let fullRowWidth = max(44, width - 2 * answerMargin)

        self.accessible = accessible
        self.boardScale = boardScale
        // On iPad the reaction keeps the phone's proportion to the pictures (177 to 127).
        self.feedbackScale = wide ? 1.39 * boardScale : 1
        self.instructionGap = instructionGap
        self.instructionFontSize = instructionFontSize
        self.instructionLines = instructionLines
        self.instructionInset = instructionInset
        self.promptGap = promptGap
        self.promptSide = promptSide
        self.promptFontSize = promptFontSize
        // Android draws this single-weight word bold by thickening its outline by about a
        // 32nd of the text size, half on each side.
        self.promptBoldSpread = promptFontSize / 64
        self.promptInset = max(0, 20 * boardScale - sideInset)
        self.promptImageInset = promptSide * 10 / 132
        self.answersGap = answersGap
        self.columns = columns
        self.gap = gap
        self.rowGap = rowGap
        // Android's text options are 45 dp from the panel's sides. On iPad the column keeps
        // the phone's proportion to the picture grid (263 of 269 dp): a compact column
        // centred under the prompt instead of 560-point bars across the panel.
        self.rowWidth = wide ? min(366 * boardScale, fullRowWidth) : fullRowWidth
        self.answerSide = answerSide
        self.answerFontSize = answerFontSize
        self.nextFontSize = nextFontSize
        self.nextTop = nextGap - nextHitPadding
        self.nextHitPadding = nextHitPadding
        self.nextSlotHeight = nextGap + pillHeight + nextBelow
        self.statsBottom = statsBottom
        self.minimumHeight = accessible
            ? 0 : fixedHeight + smallestPrompt * prompts + smallestAnswer * rowCount
    }
}

/// Apple's iOS Dynamic Type ramp in points (xSmall ... accessibility5), so boards can size
/// their fixed rows before layout instead of measuring them afterwards.
private enum LanguageTypeRamp {
    enum Style {
        case title, title2, title3, body
    }

    static func pointSize(_ style: Style, _ size: DynamicTypeSize) -> CGFloat {
        let ramp: [CGFloat]
        switch style {
        case .title: ramp = [25, 26, 27, 28, 30, 32, 34, 38, 43, 48, 53, 58]
        case .title2: ramp = [19, 20, 21, 22, 24, 26, 28, 34, 39, 44, 50, 56]
        case .title3: ramp = [17, 18, 19, 20, 22, 24, 26, 31, 37, 43, 49, 55]
        case .body: ramp = [14, 15, 16, 17, 19, 21, 23, 28, 33, 40, 47, 53]
        }
        let index: Int = Array(DynamicTypeSize.allCases).firstIndex(of: size) ?? 3
        return ramp[min(max(0, index), ramp.count - 1)]
    }

    /// How much a style grows from the default (Large) size.
    static func scale(_ style: Style, _ size: DynamicTypeSize) -> CGFloat {
        pointSize(style, size) / pointSize(style, .large)
    }

    /// A conservative single-line height for text of `fontSize` points.
    static func lineHeight(_ fontSize: CGFloat) -> CGFloat {
        (fontSize * 1.3).rounded(.up)
    }
}

/// Learned-language text in a prompt or an answer. In a fixed row it keeps to the row and
/// shrinks long words; when the row may grow (accessibility sizes) it wraps instead.
private struct LanguageChoiceText: View {
    let value: LearningTextRepresentation
    let font: Font
    let grows: Bool

    var body: some View {
        Text(value.text)
            .font(font)
            .multilineTextAlignment(.center)
            .lineLimit(grows ? nil : 2)
            .minimumScaleFactor(0.5)
            .fixedSize(horizontal: false, vertical: grows)
            .environment(\.layoutDirection, value.language == .hebrew ? .rightToLeft : .leftToRight)
    }
}

private extension View {
    /// Android's fake bold for a font without a bold face (textStyle="bold" on Fredoka
    /// Medium): crisp copies offset by `spread` thicken every stroke without changing
    /// the layout.
    func languageFakeBold(_ color: Color, spread: CGFloat) -> some View {
        shadow(color: color, radius: 0, x: spread, y: 0)
            .shadow(color: color, radius: 0, x: -spread, y: 0)
            .shadow(color: color, radius: 0, x: 0, y: spread)
            .shadow(color: color, radius: 0, x: 0, y: -spread)
    }
}

enum LanguagePracticePalette {
    /// The rainbow-sky design's navy: the instructions, prompts, letters and answers.
    static let ink = MinikPretty.navy
}

struct LanguagePracticeRepresentation: View {
    let representation: Representation
    let fontSize: CGFloat
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        switch representation {
        case .imageAsset(let asset):
            Image(asset.rawValue).resizable().scaledToFit()
        case .learningText(let value):
            Text(value.text)
                .font(.custom("Fredoka-Medium", size: fontSize, relativeTo: .title))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.55)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
                .environment(\.layoutDirection, value.language == .hebrew ? .rightToLeft : .leftToRight)
        default:
            RepresentationView(representation: representation, context: .multipleChoicePrompt)
        }
    }
}

/// WriteScreen's Plus option in the rainbow-sky design: the white answer tile with a
/// lavender rim and navy text (MinikChoiceTileStyle's look). The chosen option turns
/// mint with a green rim when it is right and pink with a red rim when it is wrong;
/// its text stays dark on the light tint.
struct LanguageAnswerStyle: ButtonStyle {
    enum State: Hashable {
        case idle, correct, incorrect
        var accessibilityKey: String.LocalizationValue {
            switch self {
            case .idle: "Not selected"
            case .correct: "Correct answer selected"
            case .incorrect: "Incorrect answer selected"
            }
        }
    }
    let state: State
    /// How long the chosen option takes to change colour: animateCardColor's 300 ms for
    /// pictures, animateBackgroundColor's 500 ms for words and letters.
    var colorDuration: Double = 0.3
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        // Android eases the chosen option into its colour and resets it at once.
        let colorChange: Animation? = reduceMotion || state == .idle
            ? nil : Animation.easeInOut(duration: colorDuration)
        let tile = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return configuration.label
            .foregroundStyle(inkColor)
            // The tile stays 7 points larger than the label on each axis, as the
            // gradient frame was (LanguageChoicePage sizes the label for it).
            .padding(3.5)
            .background {
                tile
                    .fill(fillColor)
                    .shadow(color: MinikPretty.navy.opacity(0.10), radius: 5, x: 0, y: 3)
            }
            .overlay {
                tile
                    .strokeBorder(rimColor, lineWidth: state == .idle ? 2 : 3.5)
            }
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(colorChange, value: state)
    }

    private var fillColor: Color {
        switch state {
        case .idle: return Color.white
        case .correct: return LanguageSkyPalette.correctFill
        case .incorrect: return LanguageSkyPalette.incorrectFill
        }
    }

    private var rimColor: Color {
        switch state {
        case .idle: return LanguageSkyPalette.tileRim
        case .correct: return LanguageSkyPalette.correctRim
        case .incorrect: return LanguageSkyPalette.incorrectRim
        }
    }

    private var inkColor: Color {
        switch state {
        case .idle: return MinikPretty.navy
        case .correct: return LanguageSkyPalette.correctInk
        case .incorrect: return LanguageSkyPalette.incorrectInk
        }
    }
}

/// Points, Current streak and Best streak, always side by side in one row, in Android's
/// colours. Below the accessibility sizes the row has a fixed height (65 points on phones,
/// 95 on iPad, a little more at the largest sizes) and long titles shrink; at
/// accessibility sizes the three badges grow taller together but never stack.
struct LanguagePracticeStats: View {
    let wide: Bool
    /// No longer used: the badges never stack. Kept so existing call sites still compile.
    var stacked = false
    /// Enlarges the badges with the board on iPads larger than the iPad mini.
    var scale: CGFloat = 1
    @Environment(\.languageRewardState) private var rewards
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let fonts = LanguageStatsMetrics.fontSizes(wide: wide, typeSize: dynamicTypeSize, scale: scale)
        let iconSide = LanguageStatsMetrics.iconSide(wide: wide, typeSize: dynamicTypeSize, scale: scale)
        let badgeHeight = LanguageStatsMetrics.height(wide: wide, typeSize: dynamicTypeSize, scale: scale)
        let grows = dynamicTypeSize.isAccessibilitySize
        let pointsWidth: CGFloat = (wide ? 140 : 92) * scale
        let streakWidth: CGFloat = (wide ? 140 : 105) * scale
        let firstGap: CGFloat = (wide ? 30 : 10) * scale
        let secondGap: CGFloat = (wide ? 20 : 10) * scale
        // Android's cards keep their own widths, centred: Points 92 dp and the two streaks
        // 105 dp, 10 dp apart (three 140 dp cards 30 and 20 dp apart on tablets). A
        // narrower row shares its width out among them, Points still the narrowest.
        HStack(spacing: 0) {
            badge(title: "Points", value: rewards.points, symbol: nil, colors: .points,
                  fonts: fonts, iconSide: iconSide, badgeHeight: badgeHeight, grows: grows)
                .frame(maxWidth: pointsWidth)
            badge(title: "Current streak", value: Int64(rewards.currentStreak), symbol: "language_stat_star",
                  colors: .currentStreak, fonts: fonts, iconSide: iconSide, badgeHeight: badgeHeight, grows: grows)
                .frame(maxWidth: streakWidth)
                .padding(.leading, firstGap)
            badge(title: "Best streak", value: Int64(rewards.bestStreak), symbol: MinikVisualAsset.trophy,
                  colors: .bestStreak, fonts: fonts, iconSide: iconSide, badgeHeight: badgeHeight, grows: grows)
                .frame(maxWidth: streakWidth)
                .padding(.leading, secondGap)
        }
        // Growing badges all take the tallest badge's height.
        .fixedSize(horizontal: false, vertical: grows)
    }

    private func badge(title: LocalizedStringKey, value: Int64, symbol: String?, colors: LanguageStatsColors,
                       fonts: (title: CGFloat, value: CGFloat), iconSide: CGFloat, badgeHeight: CGFloat,
                       grows: Bool) -> some View {
        VStack(spacing: 1) {
            HStack(spacing: 2) {
                if let symbol { MinikArtworkImage(name: symbol).frame(width: iconSide, height: iconSide) }
                Text(title)
                    .font(MinikPretty.titleFont(fonts.title))
                    .foregroundStyle(colors.title)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                    .fixedSize(horizontal: false, vertical: grows)
            }
            Text(value, format: .number)
                .font(MinikPretty.titleFont(fonts.value))
                .monospacedDigit()
                .foregroundStyle(colors.value)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .padding(.horizontal, 4).padding(.vertical, 3)
        .frame(maxWidth: .infinity, minHeight: badgeHeight, maxHeight: grows ? .infinity : badgeHeight)
        // The design's score tiles: Android's pastel cards with Fredoka text, lifted
        // off the glass panel by a soft shadow.
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(colors.fill)
                .shadow(color: MinikPretty.navy.opacity(0.08), radius: 3, x: 0, y: 2)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(colors.stroke, lineWidth: 1.5)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The statistics cards' Android colours: card fill, 1 dp stroke, title and value.
private struct LanguageStatsColors {
    let fill: Color
    let stroke: Color
    let title: Color
    let value: Color

    /// #F7F5FF, #8B7CF6, #6253C5, #4938B5.
    static let points = LanguageStatsColors(
        fill: Color(red: 0.969, green: 0.961, blue: 1), stroke: Color(red: 0.545, green: 0.486, blue: 0.965),
        title: Color(red: 0.384, green: 0.325, blue: 0.773), value: Color(red: 0.286, green: 0.22, blue: 0.71)
    )
    /// #F2FFFC, #32BFA8, #087E70, #009688.
    static let currentStreak = LanguageStatsColors(
        fill: Color(red: 0.949, green: 1, blue: 0.988), stroke: Color(red: 0.196, green: 0.749, blue: 0.659),
        title: Color(red: 0.031, green: 0.494, blue: 0.439), value: Color(red: 0, green: 0.588, blue: 0.533)
    )
    /// #FFFDF8, #E2B43B, #6B5A30, #B77900.
    static let bestStreak = LanguageStatsColors(
        fill: Color(red: 1, green: 0.992, blue: 0.973), stroke: Color(red: 0.886, green: 0.706, blue: 0.231),
        title: Color(red: 0.42, green: 0.353, blue: 0.188), value: Color(red: 0.718, green: 0.475, blue: 0)
    )
}

extension LanguagePracticeStats {
    /// The statistics row's height, so a board can budget for it: exact below the
    /// accessibility sizes, the smallest height at accessibility sizes.
    static func height(wide: Bool, typeSize: DynamicTypeSize, scale: CGFloat = 1) -> CGFloat {
        LanguageStatsMetrics.height(wide: wide, typeSize: typeSize, scale: scale)
    }
}

/// LanguagePracticeStats sizes, kept outside the view so boards can budget for the row.
/// Below the accessibility sizes the text grows at most 15%, keeping the row short.
/// `scale` enlarges the whole row with the board on iPads larger than the iPad mini.
private enum LanguageStatsMetrics {
    static func textGrowth(_ typeSize: DynamicTypeSize) -> CGFloat {
        let limit: CGFloat = typeSize.isAccessibilitySize ? 1.6 : 1.15
        return min(max(1, LanguageTypeRamp.scale(.body, typeSize)), limit)
    }

    /// Android's card text: 11 sp titles and 15 sp values (22 sp and 28 sp on tablets).
    static func fontSizes(wide: Bool, typeSize: DynamicTypeSize,
                          scale: CGFloat = 1) -> (title: CGFloat, value: CGFloat) {
        let growth = textGrowth(typeSize) * scale
        return wide ? (title: 22 * growth, value: 28 * growth) : (title: 11 * growth, value: 15 * growth)
    }

    /// Android's 15 dp star and trophy (30 dp on tablets).
    static func iconSide(wide: Bool, typeSize: DynamicTypeSize, scale: CGFloat = 1) -> CGFloat {
        let side: CGFloat = wide ? 30 : 15
        return side * textGrowth(typeSize) * scale
    }

    /// Android's 65 dp cards (95 dp on tablets), or two title lines, the value and the
    /// padding at larger sizes. LanguageBuildPage budgets with this same formula (17 and
    /// 22 point lines on iPad); Android's 3 dp padding lets the tablet text fit it.
    static func height(wide: Bool, typeSize: DynamicTypeSize, scale: CGFloat = 1) -> CGFloat {
        let growth = textGrowth(typeSize) * scale
        let titleLine: CGFloat = wide ? 17 : 11
        let valueLine: CGFloat = wide ? 22 : 15
        let lines = 2 * LanguageTypeRamp.lineHeight(titleLine * growth)
            + LanguageTypeRamp.lineHeight(valueLine * growth)
        let designHeight: CGFloat = (wide ? 95 : 65) * scale
        return max(designHeight, lines + 15)
    }
}
