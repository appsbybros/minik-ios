import SwiftUI

/// Android WriteScreen's word-building page (fragment_drag in Plus) in the rainbow-sky
/// design: the red close X and the lavender speaker, the navy instruction, the clue
/// word, the white answer field, the lavender letter circles, the sunny Next pill
/// after a wrong letter and the statistics at the bottom of the glass panel, with
/// Android's sizes and gaps (BuildBoardMetrics). Below the accessibility
/// text sizes every row has a budgeted height, so the board fits the panel (a tight
/// variant halves the gaps first). When it is still taller, LanguageActivityScreen
/// scrolls it.
struct LanguageBuildPage: View {
    let session: BuildSession
    let clue: LanguageWordBuildClue
    let feedback: BuildAnswerResult?
    let feedbackStartedAt: Date
    let successAsset: String
    let successDirection: Double
    let feedbackBonusRun: Int
    let encouragementEnabled: Bool
    let canSkip: Bool
    let onSelect: (BuildTokenID) -> Void
    let onReplay: () -> Void
    let onSkip: () -> Void
    let onExit: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.interfaceLocaleID) private var interfaceLocaleID
    // How much each text style has grown with Dynamic Type, in percent of the default size.
    @ScaledMetric(relativeTo: .title3) private var instructionPercent: CGFloat = 100
    @ScaledMetric(relativeTo: .title2) private var wideInstructionPercent: CGFloat = 100
    @ScaledMetric(relativeTo: .title) private var cluePercent: CGFloat = 100
    @ScaledMetric(relativeTo: .largeTitle) private var wordPercent: CGFloat = 100
    @ScaledMetric(relativeTo: .body) private var letterPercent: CGFloat = 100
    @ScaledMetric(relativeTo: .headline) private var nextPercent: CGFloat = 100
    @ScaledMetric(relativeTo: .body) private var statsPercent: CGFloat = 100

    var body: some View {
        // fragment_drag's card is bg_glass_panel_strong, like the other WriteScreen pages.
        LanguageActivityScreen(panelStyle: .rounded, minimumContentHeight: minimumHeight) { layout in
            let roomy = metrics(width: layout.width, wide: layout.wide, tight: false)
            let sizes = roomy.accessible || roomy.height + 8 <= layout.height
                ? roomy : metrics(width: layout.width, wide: layout.wide, tight: true)
            // At least the panel's height, so the spacer keeps the statistics at the
            // bottom; taller when the rows need more, and the panel then scrolls.
            let boardLayout = BuildBoardFillLayout(minimumHeight: layout.height)
            boardLayout {
                board(sizes, wide: layout.wide)
            }
            .overlay {
                feedbackLayer(sizes, wide: layout.wide)
            }
        }
        // Android answers a wrong letter with a reject haptic as well as the sound.
        .sensoryFeedback(.error, trigger: feedbackStartedAt, condition: { _, _ in
            feedback == .incorrect
        })
    }

    /// The stars and Minik's reaction over the board (and the Next pill), placed in the
    /// panel the child sees: as the board looks when nothing scrolls, wherever it has
    /// been scrolled to. The stars cover the content area; Android pins the try-again
    /// and success artwork to the card's bottom edge, below the content's inset.
    private func feedbackLayer(_ sizes: BuildBoardMetrics, wide: Bool) -> some View {
        let insetX = LanguagePanelInsets.horizontal(wide: wide)
        let insetY = sizes.feedbackDrop
        return GeometryReader { geometry in
            let panel = geometry.languageVisiblePanel(outset: CGSize(width: insetX, height: insetY))
            ZStack(alignment: .bottom) {
                if feedback == .correct && feedbackBonusRun >= 3 {
                    LanguagePracticeStars(startedAt: feedbackStartedAt, usesFaces: true,
                                          duration: encouragementEnabled ? 4 : 1.2).id(feedbackStartedAt)
                        .padding(.bottom, insetY)
                }
                if let feedback {
                    LanguagePracticeReaction(correct: feedback == .correct, startedAt: feedbackStartedAt,
                                             successAsset: successAsset, direction: successDirection)
                }
            }
            .padding(.horizontal, insetX)
            .padding(.top, insetY)
            .frame(width: panel.width, height: panel.height)
            .position(x: panel.midX, y: panel.midY)
        }
        .allowsHitTesting(false)
    }

    private func board(_ sizes: BuildBoardMetrics, wide: Bool) -> some View {
        VStack(spacing: 0) {
            topBar(sizes)
            instruction(sizes)
                .padding(.top, sizes.instructionGap)
                .padding(.bottom, sizes.sectionGap)
            if let text = clue.text {
                clueText(text, sizes: sizes)
                    .padding(.top, sizes.clueGap)
            }
            if let image = clue.image {
                Image(image.rawValue).resizable().scaledToFit()
                    .frame(height: sizes.clueImageHeight)
                    .padding(.top, sizes.imageGap)
                    .accessibilityLabel(session.currentChallenge.prompt.learningSpeechCue?.text ?? image.rawValue)
            }
            builtWord(sizes)
                .padding(.top, sizes.wordGap)
            letterRows(sizes)
                .padding(.top, sizes.tilesGap)
            nextSlot(sizes)
                .padding(.top, sizes.nextGap)
            Spacer(minLength: sizes.spacerMinimum)
            // Points, current streak and best streak always share one row, enlarged
            // with the board on iPads larger than the iPad mini, as on the choice pages.
            LanguagePracticeStats(wide: wide, scale: sizes.statsScale)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, sizes.statsBottom)
        }
    }

    private func minimumHeight(width: CGFloat, wide: Bool) -> CGFloat {
        metrics(width: width, wide: wide, tight: !dynamicTypeSize.isAccessibilitySize).height
    }

    private func metrics(width: CGFloat, wide: Bool, tight: Bool) -> BuildBoardMetrics {
        let growth = BuildTextGrowth(
            instruction: (wide ? wideInstructionPercent : instructionPercent) / 100,
            clue: cluePercent / 100,
            word: wordPercent / 100,
            letter: letterPercent / 100,
            next: nextPercent / 100,
            stats: statsPercent / 100
        )
        let instructionString = interfaceLocaleID.text("Tap the letters in the right order to form the word")
        return BuildBoardMetrics(
            width: width, wide: wide, tight: tight,
            accessible: dynamicTypeSize.isAccessibilitySize, growth: growth,
            instructionText: instructionString, clueWord: clue.text?.text,
            clueIsHebrew: clue.text?.language == .hebrew,
            hasClueImage: clue.image != nil, tokenCount: session.tokenPresentationOrder.count
        )
    }

    /// Android's top row: the red X at the top end and the speaker (bg_pretty_speaker).
    /// The speaker's start margin, left over from the home button Plus hides, moves it
    /// towards the X.
    private func topBar(_ sizes: BuildBoardMetrics) -> some View {
        ZStack(alignment: .top) {
            // fragment_drag's speaker is the choice pages' button (57 dp, 100 dp on
            // iPad, the same padded icon), so it is drawn by the same view.
            LanguageSpeakerButton(diameter: sizes.speakerDiameter, action: onReplay)
                .padding(.leading, sizes.speakerShift)
                .padding(.top, sizes.speakerTop)
                .frame(maxWidth: .infinity)
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Button(action: onExit) {
                    MinikArtworkImage(name: MinikVisualAsset.close)
                        .frame(width: sizes.closeSide, height: sizes.closeSide)
                        .frame(width: sizes.closeFrame, height: sizes.closeFrame)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close exercise")
            }
            .padding(.top, sizes.closeTop)
            .padding(.trailing, sizes.closeTrailing)
        }
        .frame(height: sizes.topBarHeight, alignment: .top)
    }

    @ViewBuilder
    private func instruction(_ sizes: BuildBoardMetrics) -> some View {
        // The design's navy Fredoka title.
        let label = Text("Tap the letters in the right order to form the word")
            .font(MinikPretty.titleFont(sizes.instructionFontSize))
            .foregroundStyle(LanguagePracticePalette.ink)
            .multilineTextAlignment(.center)
        if sizes.accessible {
            label
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, sizes.instructionInset)
        } else {
            // As on Android (wrap_content) the row is as tall as the lines the text
            // really takes, never more than the budgeted ones: a longer translation
            // shrinks a little instead of pushing the statistics off the panel.
            label
                .lineLimit(sizes.instructionLines)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, sizes.instructionInset)
        }
    }

    private func clueText(_ word: LearningTextRepresentation, sizes: BuildBoardMetrics) -> some View {
        // A single word stays whole: it shrinks rather than wrapping letter by letter.
        Text(word.text)
            .font(Self.displayFont(size: sizes.clueFontSize))
            .foregroundStyle(LanguagePracticePalette.ink)
            .buildWordFakeBold(LanguagePracticePalette.ink, spread: sizes.clueBoldSpread)
            .multilineTextAlignment(.center)
            .lineLimit(sizes.clueLines)
            .minimumScaleFactor(0.55)
            .padding(.horizontal, sizes.clueInset)
            .environment(\.layoutDirection, word.language == .hebrew ? .rightToLeft : .leftToRight)
            .frame(height: sizes.clueHeight)
    }

    /// The answer frame as the design's white field (bg_pretty_field: a lavender rim
    /// on white) keeps one height, so adding letters never moves the board. As on
    /// Android the text rests on the frame's 8 dp bottom padding and has none at the top.
    private func builtWord(_ sizes: BuildBoardMetrics) -> some View {
        let field = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return Text(session.builtDisplayText ?? "")
            .font(Self.displayFont(size: sizes.wordFontSize))
            .foregroundStyle(LanguagePracticePalette.ink)
            .buildWordFakeBold(LanguagePracticePalette.ink, spread: sizes.wordBoldSpread)
            .multilineTextAlignment(.center)
            .lineLimit(targetHasSpace ? 2 : 1)
            .minimumScaleFactor(0.4)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .frame(width: sizes.wordBoxWidth, height: sizes.wordBoxHeight)
            .background {
                field
                    .fill(Color.white)
                    .shadow(color: MinikPretty.navy.opacity(0.08), radius: 4, x: 0, y: 2)
            }
            .overlay {
                field
                    .strokeBorder(LanguageSkyPalette.tileRim, lineWidth: 2)
            }
            .environment(\.layoutDirection, learnedDirection)
            .accessibilityLabel("Your word")
            .accessibilityValue(session.builtDisplayText ?? "")
            .dropDestination(for: String.self) { identifiers, _ in
                guard let raw = identifiers.first,
                      let token = session.currentChallenge.availableTokens.first(where: { $0.id.rawValue == raw }),
                      !session.selectedTokenIDs.contains(token.id),
                      session.answerResult == nil else { return false }
                onSelect(token.id)
                return true
            }
    }

    /// Android's FlexboxLayout: 12 points between the circles, 16 between rows and
    /// every row centred. As flexWrap does, each row takes as many circles as fit
    /// and the last row holds the rest.
    private func letterRows(_ sizes: BuildBoardMetrics) -> some View {
        let order = session.tokenPresentationOrder
        let step = max(1, sizes.perRow)
        let rows: [[BuildTokenID]] = stride(from: 0, to: order.count, by: step).map { start in
            Array(order[start..<min(start + step, order.count)])
        }
        return VStack(spacing: sizes.rowSpacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: sizes.tileSpacing) {
                    ForEach(row, id: \.self) { id in
                        if let token = session.currentChallenge.availableTokens.first(where: { $0.id == id }) {
                            letter(token, sizes: sizes)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .environment(\.layoutDirection, learnedDirection)
    }

    /// Android's sunny Next pill (bg_next_link) as the design's glossy yellow button
    /// with its navy label appears after a wrong letter. Its row is always reserved,
    /// so the board does not move when it appears.
    private func nextSlot(_ sizes: BuildBoardMetrics) -> some View {
        ZStack {
            if canSkip {
                Button(action: onSkip) {
                    Text("Next")
                        .font(MinikPretty.titleFont(sizes.nextFontSize))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .buttonStyle(MinikPrettyButtonStyle(.yellow))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: sizes.nextSlotHeight)
    }

    private var learnedDirection: LayoutDirection {
        session.currentChallenge.languageWordContent?.targetText.direction == .rightToLeft ? .rightToLeft : .leftToRight
    }

    private var targetHasSpace: Bool {
        Self.hasSpace(session.currentChallenge.languageWordContent?.targetText.text ?? "")
    }

    private static func hasSpace(_ text: String) -> Bool {
        text.contains(where: { $0.isWhitespace })
    }

    /// Android draws the clue and the built word in Fredoka Medium, Hebrew included (the
    /// font has the Hebrew letters), with textStyle="bold", which thickens the single
    /// weight synthetically (buildWordFakeBold).
    private static func displayFont(size: CGFloat) -> Font {
        Font.custom("Fredoka-Medium", fixedSize: size)
    }

    /// A letter circle in the design's lavender: white to lavender with a lavender rim
    /// and a navy letter, lifted by a soft shadow.
    private func letter(_ token: BuildToken, sizes: BuildBoardMetrics) -> some View {
        let selected = session.selectedTokenIDs.contains(token.id)
        return Button { onSelect(token.id) } label: {
            tileFace(token.representation, sizes: sizes)
                .foregroundStyle(LanguagePracticePalette.ink)
                .frame(width: sizes.diameter, height: sizes.diameter)
                .background {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.white, MinikPretty.lavender],
                                startPoint: UnitPoint.top,
                                endPoint: UnitPoint.bottom
                            )
                        )
                        .shadow(color: MinikPretty.navy.opacity(0.14), radius: 3, x: 0, y: 2)
                }
                .overlay {
                    Circle()
                        .strokeBorder(LanguageSkyPalette.tileRim, lineWidth: 2)
                }
                .contentShape(Circle())
        }
        .buttonStyle(LanguageSkyPressStyle())
        .draggable(token.id.rawValue)
        .disabled(selected || session.answerResult != nil)
        .opacity(selected ? 0 : 1)
        .animation(reduceMotion ? nil : .linear(duration: 0.12), value: selected)
        .accessibilityHidden(selected)
        .allowsHitTesting(!selected && session.answerResult == nil)
        .accessibilityLabel(token.representation.accessibilityDescription)
        .accessibilityHint("Double tap to choose")
    }

    /// Android's 24 sp letters (55 sp on iPad) in the design's rounded Fredoka. A
    /// letter stays on one line inside its circle at every text size.
    @ViewBuilder
    private func tileFace(_ representation: Representation, sizes: BuildBoardMetrics) -> some View {
        switch representation {
        case .learningText(let value):
            Text(value.text)
                .font(MinikPretty.titleFont(sizes.letterFontSize))
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .padding(4)
                .environment(\.layoutDirection, value.language == .hebrew ? .rightToLeft : .leftToRight)
        default:
            LanguagePracticeRepresentation(representation: representation, fontSize: sizes.letterFontSize)
        }
    }
}

/// Dynamic Type growth of the page's text styles (1 is the default size).
private struct BuildTextGrowth {
    let instruction: CGFloat
    let clue: CGFloat
    let word: CGFloat
    let letter: CGFloat
    let next: CGFloat
    let stats: CGFloat
}

/// Android's board, dp as points: fragment_drag on phones; on iPad layout-sw600dp
/// with the sw700dp dimensions, scaled up by at most 25% on iPads wider than the
/// iPad mini (whose 684-point panel matches Android's 684 dp tablet card). Offsets
/// are measured inside LanguageActivityScreen's content area, which sits 14 x 8
/// points (21 x 12 on iPad, LanguagePanelInsets) inside the panel. Below the
/// accessibility sizes every row has a budgeted height (the instruction takes only
/// the lines it needs within its budget); the tight variant halves the gaps, keeps
/// the answer at its default size and trims the clue and the letter growth, so
/// small phones still show the whole board.
private struct BuildBoardMetrics {
    let accessible: Bool
    let speakerDiameter: CGFloat
    let speakerTop: CGFloat
    let speakerShift: CGFloat
    let closeSide: CGFloat
    let closeFrame: CGFloat
    let closeTop: CGFloat
    let closeTrailing: CGFloat
    let topBarHeight: CGFloat
    let instructionGap: CGFloat
    let instructionFontSize: CGFloat
    let instructionInset: CGFloat
    let instructionLines: Int
    let instructionHeight: CGFloat
    let sectionGap: CGFloat
    let clueGap: CGFloat
    let clueFontSize: CGFloat
    let clueBoldSpread: CGFloat
    let clueInset: CGFloat
    let clueLines: Int
    let clueHeight: CGFloat
    let imageGap: CGFloat
    let clueImageHeight: CGFloat
    let wordGap: CGFloat
    let wordFontSize: CGFloat
    let wordBoldSpread: CGFloat
    let wordBoxWidth: CGFloat
    let wordBoxHeight: CGFloat
    let tilesGap: CGFloat
    let diameter: CGFloat
    let letterFontSize: CGFloat
    let perRow: Int
    let tileSpacing: CGFloat
    let rowSpacing: CGFloat
    let nextGap: CGFloat
    let nextFontSize: CGFloat
    let nextSlotHeight: CGFloat
    let spacerMinimum: CGFloat
    /// LanguagePracticeStats' scale: the board's, so the row grows with it on large iPads.
    let statsScale: CGFloat
    let statsBottom: CGFloat
    /// How far the feedback artwork reaches below the board: the panel's content inset.
    let feedbackDrop: CGFloat
    /// The whole board with its spacer at the minimum length.
    let height: CGFloat

    init(width: CGFloat, wide: Bool, tight: Bool, accessible: Bool, growth: BuildTextGrowth,
         instructionText: String, clueWord: String?, clueIsHebrew: Bool, hasClueImage: Bool,
         tokenCount: Int) {
        let scale: CGFloat = wide ? min(1.25, max(1, width / 642)) : 1
        let gapScale: CGFloat = (tight ? 0.5 : 1) * scale
        let insetX: CGFloat = wide ? 21 : 14
        let insetY: CGFloat = wide ? 12 : 8

        // Close X: a 38 dp button (55 dp on iPad) with 3 dp padding, 17 dp (40 dp) in
        // from the panel's top and end. Speaker: a 57 dp circle (100 dp) 15 dp from
        // the top, centred together with its 25 dp (55 dp) start margin.
        let closeView: CGFloat = (wide ? 55 : 38) * scale
        let closeCentre: CGFloat = (wide ? 40 : 17) * scale + closeView / 2
        let closeFrame: CGFloat = max(44, closeView)
        let closeTop: CGFloat = max(0, closeCentre - insetY - closeFrame / 2)
        let closeTrailing: CGFloat = max(0, closeCentre - insetX - closeFrame / 2)
        let speakerDiameter: CGFloat = (wide ? 100 : 57) * scale
        let speakerTop: CGFloat = max(0, 15 * scale - insetY)
        let speakerShift: CGFloat = (wide ? 55 : 25) * scale
        let topBarHeight: CGFloat = max(speakerTop + speakerDiameter, closeTop + closeFrame)

        // Instruction: bold 22 sp (35 sp on iPad), 40 dp in from the panel's sides; the
        // tight variant gives it the full width.
        let instructionFontSize: CGFloat = (wide ? 35 * scale : 22) * growth.instruction
        let instructionInset: CGFloat = tight ? 12 : max(0, 40 * scale - insetX)
        let neededLines = Self.wrappedLines(instructionText, letterWidth: instructionFontSize * 0.55,
                                            width: width - 2 * instructionInset)
        let instructionLines = accessible ? neededLines : min(4, neededLines)
        let instructionHeight = CGFloat(instructionLines) * instructionFontSize * 1.25

        // Clue: Fredoka 55 sp (70 sp on iPad), 25 dp (20 dp) in from the panel's
        // sides, at most two lines when it has a space. The tight variant trims it a
        // little, so a two-line clue still leaves room for the board on small phones.
        let displayCap: CGFloat = tight ? 0.9 : 1.215
        let clueFontSize: CGFloat = (wide ? 70 * scale : 55) * min(growth.clue, displayCap)
        let clueInset: CGFloat = max(0, (wide ? 20 : 25) * scale - insetX)
        var clueLines = 0
        if let clueWord {
            // Fredoka's Hebrew letters average 0.55 em; its Latin ones are estimated at
            // 0.6 em. A single word keeps one line and shrinks instead.
            let letterWidth = clueFontSize * (clueIsHebrew ? 0.55 : 0.6)
            let wrapped = Self.wrappedLines(clueWord, letterWidth: letterWidth, width: width - 2 * clueInset)
            clueLines = clueWord.contains(where: { $0.isWhitespace }) ? min(2, wrapped) : 1
        }
        let clueHeight = CGFloat(clueLines) * clueFontSize * 1.22
        // The picture clue: drag_word_image_size, 80 dp on phones and on sw600dp and
        // sw700dp tablets (the iPad mini's class).
        let pictureHeight: CGFloat = 80 * scale
        let clueImageHeight: CGFloat = hasClueImage ? pictureHeight * (tight ? 0.75 : 1) : 0

        // Answer frame, 32 dp in from the panel's sides: Fredoka 55 sp on phones. On
        // iPad Android fixes the frame at 83 dp, where its 70 sp autosized text
        // settles at 62 sp. Fredoka's line is 1.21 em; 8 dp bottom padding.
        let wordFontSize: CGFloat = (wide ? 62 * scale : 55) * min(growth.word, tight ? 1 : 1.177)
        let wordBoxHeight: CGFloat = (wordFontSize * 1.21 + 8).rounded(.up)
        let wordInset: CGFloat = max(0, 32 * scale - insetX)
        let wordBoxWidth: CGFloat = max(1, width - 2 * wordInset)

        // Letter circles: 48 dp around 24 sp letters on phones, where they keep 48
        // points below the accessibility sizes. Android tablets size the circle around
        // 55 sp letters (about 84 dp) and grow it with the text; the tight variant
        // grows it less, so more circles share a row.
        let letterCap: CGFloat = accessible ? 1.6 : (tight ? 1.15 : 1.35)
        let letterGrowth: CGFloat = min(max(1, growth.letter), letterCap)
        let phoneDiameter: CGFloat = accessible ? 48 * letterGrowth : 48
        let diameter: CGFloat = wide ? 84 * scale * letterGrowth : phoneDiameter
        let letterFontSize: CGFloat = (wide ? 55 * scale : 24) * letterGrowth
        let tileSpacing: CGFloat = 12
        let rowSpacing: CGFloat = tight ? 10 : 16
        // Android's FlexboxLayout spans the card with 8 dp padding and gives each
        // circle 6 dp margins on both sides, so a phone row holds (card - 16) / 60
        // circles: (width + 12) / 60 here. Rows fill up first and the last one
        // holds the rest.
        let count = max(1, tokenCount)
        let fitting = max(1, Int((width + tileSpacing) / (diameter + tileSpacing)))
        let rowCount = (count + fitting - 1) / fitting
        let perRow = fitting
        let tilesHeight = CGFloat(rowCount) * diameter + CGFloat(rowCount - 1) * rowSpacing

        // Next: 18 sp (40 sp on iPad), 38 dp (43 dp) under the circles, on the design's
        // glossy pill: 9 points above the label and 12 below it, at least 52 points tall.
        // The tight variant keeps at least 20 points (24 on iPad) above the pill and, as
        // the spacer's minimum, 18 (22) under it, like the choice pages.
        let nextGrowth: CGFloat = min(max(1, growth.next), accessible ? 2 : 1.35)
        let nextFontSize: CGFloat = (wide ? 40 * scale : 18) * nextGrowth
        let pillHeight: CGFloat = max(52, (nextFontSize * 1.3).rounded(.up) + 21)
        let nextSlotHeight: CGFloat = max(44, pillHeight)
        let nextDistance: CGFloat = (wide ? 43 : 38) * gapScale
        let nextGapFloor: CGFloat = (wide ? 24 : 20) * scale
        let nextGap: CGFloat = max(nextGapFloor, nextDistance - (nextSlotHeight - pillHeight) / 2)

        // Statistics: LanguagePracticeStats' badge height (LanguageStatsMetrics.height
        // with the board's scale), 15 dp (30 dp) above the panel's bottom edge.
        let statsGrowth: CGFloat = min(max(1, growth.stats), accessible ? 1.6 : 1.15)
        let titleFont: CGFloat = (wide ? 17 : 11) * statsGrowth * scale
        let valueFont: CGFloat = (wide ? 22 : 15) * statsGrowth * scale
        let statsLines: CGFloat = 2 * (titleFont * 1.3).rounded(.up) + (valueFont * 1.3).rounded(.up)
        let statsMinimum: CGFloat = (wide ? 95 : 65) * scale
        let statsHeight: CGFloat = max(statsMinimum, statsLines + 15)
        let statsBottom: CGFloat = max(0, (wide ? 30 : 15) * scale - insetY)
        let spacerMinimum: CGFloat = (wide ? 22 : 18) * scale

        // Android's gaps: 10 dp (20 dp) under the speaker; on phones actionsRow3's
        // 15 dp under the instruction, on iPad the clue's 8 dp margin; the picture's
        // 10 dp (20 dp); 12 dp (10 + 12 dp) above the answer frame and 28 dp from it
        // to the circles.
        let instructionGap: CGFloat = (wide ? 20 : 10) * gapScale
        let sectionGap: CGFloat = (wide ? 0 : 15) * gapScale
        let clueGap: CGFloat = (wide ? 8 : 0) * gapScale
        let imageGap: CGFloat = (wide ? 20 : 10) * gapScale
        let wordGap: CGFloat = (wide ? 22 : 12) * gapScale
        let tilesGap: CGFloat = 28 * gapScale

        var height: CGFloat = topBarHeight + instructionGap + instructionHeight + sectionGap
        if clueWord != nil {
            height += clueGap + clueHeight
        }
        if hasClueImage {
            height += imageGap + clueImageHeight
        }
        height += wordGap + wordBoxHeight + tilesGap + tilesHeight
        height += nextGap + nextSlotHeight + spacerMinimum + statsHeight + statsBottom

        self.accessible = accessible
        self.speakerDiameter = speakerDiameter
        self.speakerTop = speakerTop
        self.speakerShift = speakerShift
        self.closeSide = closeView - 6 * scale
        self.closeFrame = closeFrame
        self.closeTop = closeTop
        self.closeTrailing = closeTrailing
        self.topBarHeight = topBarHeight
        self.instructionGap = instructionGap
        self.instructionFontSize = instructionFontSize
        self.instructionInset = instructionInset
        self.instructionLines = instructionLines
        self.instructionHeight = instructionHeight
        self.sectionGap = sectionGap
        self.clueGap = clueGap
        self.clueFontSize = clueFontSize
        // Android thickens the single-weight Fredoka by about a 32nd of the text size,
        // half on each side.
        self.clueBoldSpread = clueFontSize / 64
        self.clueInset = clueInset
        self.clueLines = max(1, clueLines)
        self.clueHeight = clueHeight
        self.imageGap = imageGap
        self.clueImageHeight = clueImageHeight
        self.wordGap = wordGap
        self.wordFontSize = wordFontSize
        self.wordBoldSpread = wordFontSize / 64
        self.wordBoxWidth = wordBoxWidth
        self.wordBoxHeight = wordBoxHeight
        self.tilesGap = tilesGap
        self.diameter = diameter
        self.letterFontSize = letterFontSize
        self.perRow = perRow
        self.tileSpacing = tileSpacing
        self.rowSpacing = rowSpacing
        self.nextGap = nextGap
        self.nextFontSize = nextFontSize
        self.nextSlotHeight = nextSlotHeight
        self.spacerMinimum = spacerMinimum
        self.statsScale = scale
        self.statsBottom = statsBottom
        self.feedbackDrop = insetY
        self.height = height
    }

    /// Lines a centred label needs when it wraps between words, estimated from an
    /// average letter width (a space is half a letter). A word wider than a line
    /// breaks over as many lines as it needs.
    static func wrappedLines(_ text: String, letterWidth: CGFloat, width: CGFloat) -> Int {
        let available = max(1, width)
        let spaceWidth = letterWidth * 0.5
        var lines = 0
        var lineWidth: CGFloat = 0
        // Typed, so the compiler picks Collection's split (Substring) over Sequence's.
        let words: [Substring] = text.split(whereSeparator: { $0.isWhitespace })
        for word in words {
            let wordWidth = CGFloat(word.count) * letterWidth
            if lines > 0 && lineWidth + spaceWidth + wordWidth <= available {
                lineWidth += spaceWidth + wordWidth
            } else {
                let wordLines = max(1, Int((wordWidth / available).rounded(.up)))
                lines += wordLines
                lineWidth = wordWidth - CGFloat(wordLines - 1) * available
            }
        }
        return max(1, lines)
    }
}

/// Gives the board at least the panel's height, so its spacer can hold the
/// statistics at the bottom inside the panel's scroll view, and its natural
/// height when the rows need more, so the panel scrolls instead of clipping.
private struct BuildBoardFillLayout: Layout {
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

private extension View {
    /// Android's synthetic bold for Fredoka Medium (textStyle="bold" on a font with one
    /// weight): crisp copies offset by `spread` thicken every stroke without changing
    /// the layout, as on the choice pages.
    func buildWordFakeBold(_ color: Color, spread: CGFloat) -> some View {
        shadow(color: color, radius: 0, x: spread, y: 0)
            .shadow(color: color, radius: 0, x: -spread, y: 0)
            .shadow(color: color, radius: 0, x: 0, y: spread)
            .shadow(color: color, radius: 0, x: 0, y: -spread)
    }
}
