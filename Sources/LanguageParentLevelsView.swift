import SwiftUI

/// Android LevelsDifficultyDialogFragment / dialog_levels_difficulty.xml in the
/// rainbow-sky design: a white card with 28 dp corners and a 2 dp #E6DEFF rim, 14 dp
/// narrower on each side than the Parent Area dialog, shown over it with its own
/// dim, under a navy Fredoka title. Word, Soccer and Tic-Tac-Toe levels sit in
/// outlined rows with an Android spinner (or the Auto level chip) at the end.
struct LanguageParentLevelsView: View {
    /// dialog_levels_difficulty's #E6DEFF rim.
    private static let cardRim = Color(red: 230 / 255, green: 222 / 255, blue: 255 / 255)

    @Binding var settings: LanguageParentLevelSettings
    let onClose: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.interfaceLocaleID) private var interfaceLocaleID
    @ScaledMetric(relativeTo: .title) private var titleTextScale: CGFloat = 100
    @ScaledMetric(relativeTo: .body) private var bodyTextScale: CGFloat = 100

    init(settings: Binding<LanguageParentLevelSettings>, onClose: @escaping () -> Void) {
        _settings = settings
        self.onClose = onClose
    }

    var body: some View {
        GeometryReader { geometry in
            let metrics = LanguageParentDialogMetrics(
                containerSize: geometry.size,
                safeAreaInsets: geometry.safeAreaInsets,
                interfaceLocale: interfaceLocaleID,
                titleScale: titleTextScale / 100,
                textScale: bodyTextScale / 100,
                accessibilityLayout: dynamicTypeSize.isAccessibilitySize
            )
            ZStack {
                // A second Android dialog dims what is under it again; a tap
                // outside closes it.
                Color.black.opacity(0.32)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onClose)
                    .accessibilityHidden(true)

                levelsCard(metrics: metrics)
                    .padding(.top, 10)
                    .padding(.bottom, 16)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .accessibilityAction(.escape) { onClose() }
    }

    /// As tall as its content; scrolls only when the content is taller than
    /// the screen.
    private func levelsCard(metrics: LanguageParentDialogMetrics) -> some View {
        let cardContent = levelsContent(metrics: metrics)
        return ViewThatFits(in: .vertical) {
            cardContent
            ScrollView {
                cardContent
            }
            .scrollIndicators(.visible)
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(width: max(1, metrics.dialogWidth - 28))
        .background(Color.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Self.cardRim, lineWidth: 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: MinikPretty.navy.opacity(0.2), radius: 12, y: 6)
        .overlay(alignment: .topTrailing) {
            // Android: a 34 dp image with 6 dp padding at the padded top end.
            Button(action: onClose) {
                MinikArtworkImage(name: MinikVisualAsset.close)
                    .frame(width: 22, height: 22)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 9)
            .padding(.trailing, 11)
            .accessibilityLabel("Close Levels")
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private func levelsContent(metrics: LanguageParentDialogMetrics) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Levels")
                .font(MinikPretty.titleFont(metrics.titleSize))
                .foregroundStyle(MinikPretty.navy)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 30)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)

            sectionTitle("Word Level", metrics: metrics)
                .padding(.top, 15)

            Text("Use Auto mode or choose a level manually.")
                .font(.system(size: metrics.hintSize))
                .foregroundStyle(Color.black)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)

            outlinedCard {
                Toggle(isOn: modeBinding) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Auto mode")
                            .font(.system(size: metrics.captionSize, weight: .bold))
                        Text("The app adjusts levels based on progress.")
                            .font(.system(size: metrics.hintSize))
                    }
                    .foregroundStyle(Color.black)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .toggleStyle(LanguageParentSwitchStyle(alignment: .top))
            }
            .padding(.top, 14)

            levelRow(
                description: "Affects which words are used",
                selection: wordLevelBinding,
                options: LanguageVocabularyLevel.allCases.map { ($0.rawValue, wordLevelTitle($0)) },
                isEnabled: settings.mode == .manual,
                metrics: metrics
            )
            .padding(.top, 12)

            sectionTitle("Soccer Level", metrics: metrics)
                .padding(.top, 20)

            levelRow(
                description: "Affects goalie size and movement",
                selection: soccerLevelBinding,
                options: LanguageSoccerLevel.allCases.map { ($0.rawValue, soccerLevelTitle($0)) },
                metrics: metrics
            )
            .padding(.top, 12)

            sectionTitle("Tic-Tac-Toe Level", metrics: metrics)
                .padding(.top, 20)

            levelRow(
                description: "Affects the game difficulty",
                selection: ticTacToeLevelBinding,
                options: TicTacToeLevel.allCases.map { ($0.rawValue, ticTacToeLevelTitle($0)) },
                metrics: metrics
            )
            .padding(.top, 12)
        }
        .padding(.horizontal, 16)
        .padding(.top, 28)
        .padding(.bottom, 16)
    }

    private func sectionTitle(
        _ title: LocalizedStringKey,
        metrics: LanguageParentDialogMetrics
    ) -> some View {
        Text(title)
            .font(MinikPretty.titleFont(metrics.subtitleSize))
            .foregroundStyle(MinikPretty.navy)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .accessibilityAddTraits(.isHeader)
    }

    /// item_level_row / autoCard: white, 18 dp corners, a 1 dp outline, 14 dp padding.
    private func outlinedCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(LanguageParentPalette.outline, lineWidth: 1)
            }
    }

    /// "Level" and its description at the start, the value box (165/200 dp wide)
    /// at the end. Where that leaves the text too narrow a column (phones, where
    /// Hebrew wrapped a few letters a line) and at accessibility text sizes, the
    /// box goes under the text.
    private func levelRow(
        description: LocalizedStringKey,
        selection: Binding<String>,
        options: [(value: String, title: String)],
        isEnabled: Bool = true,
        metrics: LanguageParentDialogMetrics
    ) -> some View {
        outlinedCard {
            if metrics.usesAccessibilityLayout || levelTextWidth(metrics) < Self.minimumLevelTextWidth {
                VStack(alignment: .leading, spacing: 10) {
                    levelTexts(description: description, metrics: metrics)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    levelValue(selection: selection, options: options, isEnabled: isEnabled, metrics: metrics)
                        .frame(maxWidth: .infinity)
                }
            } else {
                HStack(alignment: .center, spacing: 10) {
                    levelTexts(description: description, metrics: metrics)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    levelValue(selection: selection, options: options, isEnabled: isEnabled, metrics: metrics)
                        .frame(width: metrics.levelValueWidth)
                }
            }
        }
    }

    /// The narrowest text column beside the value box that still reads well.
    private static let minimumLevelTextWidth: CGFloat = 170

    /// The text column beside the value box: the card (the dialog less 14 a side)
    /// less its 16 padding a side, the row's 14 padding a side and the 10 gap.
    private func levelTextWidth(_ metrics: LanguageParentDialogMetrics) -> CGFloat {
        metrics.dialogWidth - 28 - 32 - 28 - 10 - metrics.levelValueWidth
    }

    private func levelTexts(
        description: LocalizedStringKey,
        metrics: LanguageParentDialogMetrics
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Level")
                .font(.system(size: metrics.captionSize, weight: .bold))
            Text(description)
                .font(.system(size: metrics.hintSize))
        }
        .foregroundStyle(Color.black)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Manual: the Android spinner. Auto: the read-only level chip that fills
    /// from the start in proportion to the level (A empty ... E full).
    @ViewBuilder
    private func levelValue(
        selection: Binding<String>,
        options: [(value: String, title: String)],
        isEnabled: Bool,
        metrics: LanguageParentDialogMetrics
    ) -> some View {
        let selectedTitle = options.first(where: { $0.value == selection.wrappedValue })?.title
            ?? selection.wrappedValue
        if isEnabled {
            Menu {
                ForEach(options, id: \.value) { option in
                    Button {
                        selection.wrappedValue = option.value
                    } label: {
                        if option.value == selection.wrappedValue {
                            Label(option.title, systemImage: "checkmark")
                        } else {
                            Text(verbatim: option.title)
                        }
                    }
                }
            } label: {
                LanguageParentDropdownLabel(
                    title: selectedTitle,
                    fontSize: metrics.levelSpinnerTextSize,
                    minHeight: metrics.levelValueHeight
                )
            }
            .menuOrder(.fixed)
            .accessibilityLabel(Text("Level"))
            .accessibilityValue(Text(verbatim: selectedTitle))
        } else {
            LanguageParentLevelChip(
                title: selectedTitle,
                fillFraction: levelFillFraction(selection.wrappedValue),
                fontSize: metrics.levelChipTextSize,
                minHeight: metrics.levelValueHeight
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Level"))
            .accessibilityValue(Text(verbatim: selectedTitle))
        }
    }

    /// Android bg_level_progress clip levels: A 0, B 2500, C 5000, D 7500, E 10000.
    private func levelFillFraction(_ value: String) -> CGFloat {
        switch value {
        case "A": return 0
        case "B": return 0.25
        case "C": return 0.5
        case "D": return 0.75
        default: return 1
        }
    }

    private var modeBinding: Binding<Bool> {
        Binding(
            get: { settings.mode == .automatic },
            set: { isAutomatic in
                settings.mode = isAutomatic ? .automatic : .manual
            }
        )
    }

    private var wordLevelBinding: Binding<String> {
        Binding(
            get: { settings.wordLevel.rawValue },
            set: { value in
                guard let level = LanguageVocabularyLevel(rawValue: value) else { return }
                settings.wordLevel = level
            }
        )
    }

    private var soccerLevelBinding: Binding<String> {
        Binding(
            get: { settings.soccerLevel.rawValue },
            set: { value in
                guard let level = LanguageSoccerLevel(rawValue: value) else { return }
                settings.soccerLevel = level
            }
        )
    }

    private var ticTacToeLevelBinding: Binding<String> {
        Binding(
            get: { settings.ticTacToeLevel.rawValue },
            set: { value in
                guard let level = TicTacToeLevel(rawValue: value) else { return }
                settings.ticTacToeLevel = level
            }
        )
    }

    private func wordLevelTitle(_ level: LanguageVocabularyLevel) -> String {
        let name: String
        switch level {
        case .a: name = interfaceLocaleID.text("Beginner")
        case .b: name = interfaceLocaleID.text("Easy")
        case .c: name = interfaceLocaleID.text("Medium")
        case .d: name = interfaceLocaleID.text("Hard")
        case .e: name = interfaceLocaleID.text("Very Hard")
        }
        return "\(name) (\(level.rawValue))"
    }

    private func soccerLevelTitle(_ level: LanguageSoccerLevel) -> String {
        switch level {
        case .a: interfaceLocaleID.text("Beginner")
        case .b: interfaceLocaleID.text("Medium")
        case .c: interfaceLocaleID.text("Very Hard")
        }
    }

    private func ticTacToeLevelTitle(_ level: TicTacToeLevel) -> String {
        switch level {
        case .a: interfaceLocaleID.text("Beginner")
        case .b: interfaceLocaleID.text("Easy")
        case .c: interfaceLocaleID.text("Medium")
        case .d: interfaceLocaleID.text("Hard")
        case .e: interfaceLocaleID.text("Very Hard")
        case .random: interfaceLocaleID.text("Random")
        case .adaptive: interfaceLocaleID.text("Adaptive")
        }
    }
}

/// bg_level_progress: #D7ECFF with a blue gradient filled from the start, a faint
/// dashed inner line and a 2 dp #B9C7D6 edge; bold 16 sp #263238 text.
private struct LanguageParentLevelChip: View {
    let title: String
    let fillFraction: CGFloat
    let fontSize: CGFloat
    let minHeight: CGFloat

    init(title: String, fillFraction: CGFloat, fontSize: CGFloat, minHeight: CGFloat) {
        self.title = title
        self.fillFraction = fillFraction
        self.fontSize = fontSize
        self.minHeight = minHeight
    }

    var body: some View {
        Text(verbatim: title)
            .font(.system(size: fontSize, weight: .bold))
            .foregroundStyle(LanguageParentPalette.levelText)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .background {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        LanguageParentPalette.levelBase
                        LinearGradient(
                            colors: [LanguageParentPalette.levelFillStart, LanguageParentPalette.levelFillEnd],
                            startPoint: UnitPoint(x: 0, y: 0.5),
                            endPoint: UnitPoint(x: 1, y: 0.5)
                        )
                        .frame(width: proxy.size.width * fillFraction)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.125), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .padding(2)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(LanguageParentPalette.levelBorder, lineWidth: 2)
            }
    }
}
