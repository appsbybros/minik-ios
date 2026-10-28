import AVFoundation
import SwiftUI

struct ParentAreaView: View {
    let configuration: ProductConfiguration
    @ObservedObject var interfaceLocaleController: InterfaceLocaleController
    let selectedLanguage: LanguageIdentifier
    let languageLevelSettings: LanguageParentLevelSettings
    let mathLevelState: MathLevelState?
    @ObservedObject var learningReminderController: LearningReminderController
    @ObservedObject var commerceController: MinikCommerceController
    @ObservedObject var publicLeaderboardController: PublicLeaderboardController
    let onSelectLanguage: (LanguageIdentifier) -> Void
    let onSetLanguageLevels: (LanguageParentLevelSettings) -> Void
    let onSetMathMode: (MathLevelMode) -> Void
    let onSelectMathLevel: (MathCurriculumLevelID) -> Void
    let onShowProgress: () -> Void
    let onShowRecords: () -> Void
    /// Android Minik Math Plus ParentAreaScreen (dc12a5c): "Learning progress", Math only.
    let onShowLearningProgress: (() -> Void)?
    let onExit: () -> Void

    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title) private var titleTextScale: CGFloat = 100
    @ScaledMetric(relativeTo: .body) private var bodyTextScale: CGFloat = 100
    @State private var encouragementEnabled: Bool
    @State private var mathReadAloudEnabled = MathReadAloudPreferenceRepository().load()
    @State private var showsLanguageLevels = false
    @State private var languageExtra: LanguageParentExtra?
    @State private var showsPublicAliasChoices = false
    @State private var publicAliasChoices: [PublicLeaderboardAlias] = []
    @State private var gatedParentAction: GatedParentAction?
    /// Rate, share or feedback, unlocked by the grown-up check and run once the check's
    /// sheet has gone, so the share sheet or the rating prompt can appear.
    @State private var pendingKeepInTouch: MinikKeepInTouchAction?
    @State private var shareRequest: MinikShareText?
    /// Android's "No suitable app is installed" toast, shown under the buttons instead.
    @State private var keepInTouchProblem: String?
    private let encouragementRepository: EncouragementPreferenceRepository
    private let releaseInformation: MinikReleaseInformation

    init(
        configuration: ProductConfiguration,
        interfaceLocaleController: InterfaceLocaleController,
        selectedLanguage: LanguageIdentifier,
        languageLevelSettings: LanguageParentLevelSettings = .androidDefault,
        mathLevelState: MathLevelState?,
        learningReminderController: LearningReminderController,
        commerceController: MinikCommerceController,
        publicLeaderboardController: PublicLeaderboardController,
        encouragementRepository: EncouragementPreferenceRepository = EncouragementPreferenceRepository(),
        releaseInformation: MinikReleaseInformation = MinikReleaseInformation.load(),
        onSelectLanguage: @escaping (LanguageIdentifier) -> Void,
        onSetLanguageLevels: @escaping (LanguageParentLevelSettings) -> Void = { _ in },
        onSetMathMode: @escaping (MathLevelMode) -> Void,
        onSelectMathLevel: @escaping (MathCurriculumLevelID) -> Void,
        onShowProgress: @escaping () -> Void,
        onShowRecords: @escaping () -> Void,
        onShowLearningProgress: (() -> Void)? = nil,
        onExit: @escaping () -> Void
    ) {
        self.configuration = configuration
        self.interfaceLocaleController = interfaceLocaleController
        self.selectedLanguage = selectedLanguage
        self.languageLevelSettings = languageLevelSettings
        self.mathLevelState = mathLevelState
        self.learningReminderController = learningReminderController
        self.commerceController = commerceController
        self.publicLeaderboardController = publicLeaderboardController
        self.encouragementRepository = encouragementRepository
        self.releaseInformation = releaseInformation
        self.onSelectLanguage = onSelectLanguage
        self.onSetLanguageLevels = onSetLanguageLevels
        self.onSetMathMode = onSetMathMode
        self.onSelectMathLevel = onSelectMathLevel
        self.onShowProgress = onShowProgress
        self.onShowRecords = onShowRecords
        self.onShowLearningProgress = onShowLearningProgress
        self.onExit = onExit
        _encouragementEnabled = State(initialValue: encouragementRepository.load(for: configuration.variant))
    }

    var body: some View {
        Group {
            if configuration.contentDomain == .language {
                languageBody
            } else {
                standardBody
            }
        }
        .sheet(item: $gatedParentAction, onDismiss: runPendingKeepInTouch) { action in
            ParentalGateView(
                onCancel: { gatedParentAction = nil },
                onUnlock: {
                    gatedParentAction = nil
                    performGatedAction(action)
                }
            )
        }
        .sheet(item: $shareRequest) { request in
            MinikShareSheet(text: request.text)
        }
    }

    // MARK: - Language: Android LanguagesAndLevelsDialogFragment

    /// Android dialog_languages_and_levels.xml: a compact card, 93% of the screen
    /// width (at most 420/560/640 dp), as tall as its content and centred over the
    /// Intro. The iOS-only grown-up pages are reached from a footer under it, where
    /// Android's Intro has its footer links. Levels and those pages open as dialogs
    /// on top, as Android's Levels dialog does.
    private var languageBody: some View {
        GeometryReader { geometry in
            let metrics = LanguageParentDialogMetrics(
                containerSize: geometry.size,
                safeAreaInsets: geometry.safeAreaInsets,
                interfaceLocale: interfaceLocaleController.selectedLocale,
                titleScale: titleTextScale / 100,
                textScale: bodyTextScale / 100,
                accessibilityLayout: dynamicTypeSize.isAccessibilitySize
            )
            ZStack {
                // Android's dialog dims the Intro by 32%. The hub already draws
                // 18%, so 17% more gives the same 32%. A tap outside closes, as
                // on Android.
                Color.black.opacity(0.17)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onExit)
                    .accessibilityHidden(true)

                languageDialogLayer(metrics: metrics)
                    .accessibilityHidden(showsLanguageLevels || languageExtra != nil)

                if showsLanguageLevels {
                    LanguageParentLevelsView(
                        settings: Binding(
                            get: { languageLevelSettings },
                            set: onSetLanguageLevels
                        ),
                        onClose: { showsLanguageLevels = false }
                    )
                    .transition(.opacity)
                }

                if let extra = languageExtra {
                    languageExtraPanel(extra, metrics: metrics)
                        .transition(.opacity)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: showsLanguageLevels)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: languageExtra)
        }
        .environment(\.locale, interfaceLocaleController.selectedLocale.locale)
        .environment(\.interfaceLocaleID, interfaceLocaleController.selectedLocale)
        .environment(\.layoutDirection, interfaceLocaleController.selectedLocale.layoutDirection)
        .accessibilityAction(.escape) { onExit() }
        .task { await publicLeaderboardController.refresh() }
    }

    /// The card centred in the space above the footer, with the footer at the
    /// bottom, lifted off the screen's bottom edge (iPhone SE has no home
    /// indicator inset). Accessibility text sizes keep the links at the end of
    /// the scrolling card instead.
    private func languageDialogLayer(metrics: LanguageParentDialogMetrics) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 10)

            languageDialogCard(
                width: metrics.dialogWidth,
                closeLabel: "Close Parent Area",
                isModal: false,
                onClose: onExit
            ) {
                languageDialogContent(metrics: metrics)
            }
            // The card takes the height it needs before the spacers share the rest.
            .layoutPriority(1)

            Spacer(minLength: 16)

            if !metrics.usesAccessibilityLayout {
                languageFooter(metrics: metrics)
                    .padding(.bottom, metrics.footerBottomMargin)
            }
        }
        // The card and its footer are one modal for VoiceOver.
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    /// bg_pretty_dialog (the rainbow-sky design's dialog card, as in the Levels
    /// dialog) with the red X at the top end. The card is as tall as its content
    /// and scrolls only when the content is taller than the screen.
    private func languageDialogCard<Content: View>(
        width: CGFloat,
        closeLabel: LocalizedStringKey,
        isModal: Bool = true,
        onClose: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let dialogContent = content()
        let modalTraits: AccessibilityTraits = isModal ? .isModal : []
        return ViewThatFits(in: .vertical) {
            dialogContent
            ScrollView {
                dialogContent
            }
            .scrollIndicators(.visible)
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(width: width)
        // The content is clipped to the card; the card's white face and its shadow
        // are drawn under it, and the lavender rim over it.
        .clipShape(RoundedRectangle(cornerRadius: LanguageParentDialogBackground.cornerRadius, style: .continuous))
        .background { LanguageParentDialogBackground() }
        .overlay {
            RoundedRectangle(cornerRadius: LanguageParentDialogBackground.cornerRadius, style: .continuous)
                .strokeBorder(LanguageParentPalette.dialogStroke, lineWidth: 2)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .topTrailing) {
            // Android: a 34 dp image with 6 dp padding at the padded top end, so
            // the 22 dp X sits 22 dp from the card edges; the hit area is 44 pt.
            Button(action: onClose) {
                MinikArtworkImage(name: MinikVisualAsset.close)
                    .frame(width: 22, height: 22)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 11)
            .padding(.trailing, 11)
            .accessibilityLabel(closeLabel)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(modalTraits)
    }

    /// Android's dialog content only: title, the two language fields, the
    /// encouragement switch and the two pills.
    private func languageDialogContent(metrics: LanguageParentDialogMetrics) -> some View {
        let showsLearnedLanguage = configuration.isLearningLanguageSelectionAvailable
        return VStack(alignment: .leading, spacing: 0) {
            languageDialogTitle("Parent Area", metrics: metrics)

            // English Only fixes the learned language, and Android then hides the
            // whole learningLanguageContainer with its 10/14 dp margins, so App
            // language follows the title after the 12 dp container margin alone.
            if showsLearnedLanguage {
                languageField(caption: learnedLanguageCaption, metrics: metrics) {
                    learnedLanguageControl(metrics: metrics)
                }
                .padding(.top, metrics.titleToCaption)
            }

            languageField(
                caption: interfaceLocaleController.selectedLocale.text("Interface language"),
                metrics: metrics
            ) {
                interfaceLanguageControl(metrics: metrics)
            }
            .padding(.top, showsLearnedLanguage ? metrics.fieldToCaption : metrics.titleToCaption - 10)

            encouragementSwitch(metrics: metrics)
                .padding(.top, metrics.fieldToSwitch)

            // Android LanguagesAndLevelsDialogFragment (a4ea9be): "Daily learning & feedback"
            // is the last row of languagesContainer, under the switch and above the two pills;
            // it opens the daily page (DailyLearningActivity).
            dailyLearningButton(metrics: metrics)
                .padding(.top, 14)

            languageActionButtons(metrics: metrics)
                .padding(.top, metrics.switchToButtons)

            // The family card (Android Minik opens it from the Parent Area), as a quiet link.
            FamilyMenuLink(title: FamilyMessages.text("More Minik apps & games", "עוד אפליקציות ומשחקי מיניק",
                                                      language: interfaceLocaleController.selectedLocale.rawValue)) {
                FamilyMessages.shared.showMoreApps(gate: nil)
            }
            .padding(.top, 14)

            // Accessibility text sizes keep the footer links in the scrolling card.
            if metrics.usesAccessibilityLayout {
                languageExtraLinks(metrics: metrics)
                    .padding(.top, 16)
            }
        }
        .padding(.horizontal, metrics.horizontalPadding)
        .padding(.top, metrics.topPadding)
        .padding(.bottom, metrics.bottomPadding)
    }

    /// The design's navy Fredoka title.
    private func languageDialogTitle(
        _ title: LocalizedStringKey,
        metrics: LanguageParentDialogMetrics
    ) -> some View {
        Text(title)
            .font(MinikPretty.titleFont(metrics.titleSize))
            .foregroundStyle(MinikPretty.navy)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            // Kept clear of the X, so larger text wraps instead of running under it.
            .padding(.horizontal, 30)
            .frame(maxWidth: .infinity)
            .accessibilityAddTraits(.isHeader)
    }

    /// A caption above its field, as in the Android dialog, in the design's navy
    /// Fredoka.
    private func languageField<Field: View>(
        caption: String,
        metrics: LanguageParentDialogMetrics,
        @ViewBuilder field: () -> Field
    ) -> some View {
        VStack(alignment: .leading, spacing: metrics.captionToField) {
            Text(verbatim: caption)
                .font(MinikPretty.titleFont(metrics.captionSize))
                .foregroundStyle(MinikPretty.navy)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                // The field below reads the caption as its own label.
                .accessibilityHidden(true)
            field()
        }
    }

    /// Android's caption ends with a colon in every language ("שפת לימוד:").
    private var learnedLanguageCaption: String {
        let caption = interfaceLocaleController.selectedLocale.text("Learned language")
        if caption.hasSuffix(":") {
            return caption
        }
        return caption + ":"
    }

    private func learnedLanguageTitle(_ language: LanguageIdentifier) -> String {
        if language == .hebrew {
            return interfaceLocaleController.selectedLocale.text("Hebrew")
        }
        return interfaceLocaleController.selectedLocale.text("English")
    }

    /// Shown only where the learned language can be chosen; English Only hides
    /// the whole field, as Android does.
    private func learnedLanguageControl(metrics: LanguageParentDialogMetrics) -> some View {
        Menu {
            ForEach(availableLearnedLanguages, id: \.self) { language in
                Button {
                    onSelectLanguage(language)
                } label: {
                    languageMenuItem(
                        learnedLanguageTitle(language),
                        isSelected: language == selectedLanguage
                    )
                }
            }
        } label: {
            LanguageParentDropdownLabel(
                title: learnedLanguageTitle(selectedLanguage),
                fontSize: metrics.spinnerTextSize,
                minHeight: metrics.dropdownHeight
            )
        }
        .menuOrder(.fixed)
        .accessibilityLabel(Text(verbatim: learnedLanguageCaption))
        .accessibilityValue(Text(verbatim: learnedLanguageTitle(selectedLanguage)))
        .accessibilityHint("Changes the language practiced in learning activities")
    }

    private func interfaceLanguageControl(metrics: LanguageParentDialogMetrics) -> some View {
        let selected = interfaceLocaleController.selectedLocale
        return Menu {
            ForEach(orderedInterfaceLocales) { locale in
                Button {
                    interfaceLocaleController.select(locale)
                } label: {
                    languageMenuItem(
                        interfaceLocaleController.selectedLocale.text(locale.displayNameKey),
                        isSelected: locale == selected
                    )
                }
            }
        } label: {
            LanguageParentDropdownLabel(
                title: selected.text(selected.displayNameKey),
                fontSize: metrics.spinnerTextSize,
                minHeight: metrics.dropdownHeight
            )
        }
        .menuOrder(.fixed)
        .accessibilityLabel(Text(verbatim: selected.text("Interface language")))
        .accessibilityValue(Text(verbatim: selected.text(selected.displayNameKey)))
    }

    /// The Android spinner lists interface languages in this order.
    private var orderedInterfaceLocales: [InterfaceLocaleID] {
        let allowed = interfaceLocaleController.allowedLocales
        let androidOrder: [InterfaceLocaleID] = [
            .english, .spanish, .french, .hebrew, .russian, .arabic,
            .dutch, .german, .portugueseBrazil, .portuguesePortugal, .amharic
        ]
        let ordered = androidOrder.filter { allowed.contains($0) }
        let remaining = allowed.filter { !ordered.contains($0) }
        return ordered + remaining
    }

    @ViewBuilder
    private func languageMenuItem(_ title: String, isSelected: Bool) -> some View {
        if isSelected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(verbatim: title)
        }
    }

    private func encouragementSwitch(metrics: LanguageParentDialogMetrics) -> some View {
        Toggle(isOn: Binding(
            get: { encouragementEnabled },
            set: { value in
                encouragementEnabled = value
                encouragementRepository.save(value, for: configuration.variant)
            }
        )) {
            VStack(alignment: .leading, spacing: metrics.switchTitleToHint) {
                Text("Encouraging messages")
                    .font(MinikPretty.titleFont(metrics.captionSize))
                    .foregroundStyle(MinikPretty.navy)
                Text("Play an encouraging message at the end of each exercise.")
                    .font(.system(size: metrics.hintSize))
                    .foregroundStyle(MinikPretty.softInk)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .toggleStyle(LanguageParentSwitchStyle())
        .accessibilityHint("Controls encouraging practice messages")
    }

    /// Android: two equal glossy pills 25 dp apart, Levels purple and Learning
    /// progress blue, as tall as the two-line "Learning progress" label.
    /// Accessibility text sizes stack them.
    @ViewBuilder
    private func languageActionButtons(metrics: LanguageParentDialogMetrics) -> some View {
        if metrics.usesAccessibilityLayout {
            VStack(spacing: 12) {
                levelsButton(metrics: metrics)
                progressStatisticsButton(metrics: metrics)
            }
            .fixedSize(horizontal: false, vertical: true)
        } else {
            HStack(spacing: 25) {
                levelsButton(metrics: metrics)
                progressStatisticsButton(metrics: metrics)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func levelsButton(metrics: LanguageParentDialogMetrics) -> some View {
        Button {
            showsLanguageLevels = true
        } label: {
            Text("Levels")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(LanguageParentActionButtonStyle(
            fontSize: metrics.buttonTextSize,
            minHeight: metrics.buttonMinHeight,
            look: MinikPretty.PillLook.purple
        ))
    }

    private func progressStatisticsButton(metrics: LanguageParentDialogMetrics) -> some View {
        Button(action: onShowProgress) {
            Text(verbatim: progressButtonTitle)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(LanguageParentActionButtonStyle(
            fontSize: metrics.buttonTextSize,
            minHeight: metrics.buttonMinHeight,
            look: MinikPretty.PillLook.blue
        ))
        .accessibilityLabel(Text("Progress & Statistics"))
        .accessibilityHint("Opens locally stored educational progress")
    }

    /// Android adds a full-width bg_pretty_button_blue button with white text, at least
    /// 52 dp tall, at the end of the languages container, above the two pills.
    private func dailyLearningButton(metrics: LanguageParentDialogMetrics) -> some View {
        Button {
            keepInTouchProblem = nil
            languageExtra = .dailyLearning
        } label: {
            Text(verbatim: interfaceLocaleController.selectedLocale.text("Daily learning & feedback"))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(LanguageParentActionButtonStyle(
            fontSize: metrics.buttonTextSize,
            minHeight: 52,
            look: MinikPretty.PillLook.blue
        ))
    }

    /// Android DailyLearningActivity: today's little wins for the playing child in the
    /// learned language, Back to learning, the family link, and rate, share and feedback.
    /// Those three leave the app, so they open behind the grown-up check, as the Parent
    /// Area's other outside links do.
    private func dailyLearningContent(metrics: LanguageParentDialogMetrics) -> some View {
        let locale = interfaceLocaleController.selectedLocale
        let wins = MinikDailyLearningRepository(product: configuration.variant).count(language: selectedLanguage)
        let reachedGoal = wins >= MinikDailyLearningPolicy.dailyGoal
        return VStack(spacing: 12) {
            Text(verbatim: String(format: locale.text("Today: %lld of 5 little wins"), Int64(wins)))
                .font(MinikPretty.titleFont(metrics.captionSize))
                .foregroundStyle(MinikPretty.navy)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)

            Text(verbatim: reachedGoal
                ? locale.text("Five little wins today. Well done!")
                : locale.text("Choose any learning game. Each play that earns points adds one little win. Progress is saved for this child and learning language. No rush, and no penalty for a day off."))
                .font(MinikPretty.bodyFont(metrics.spinnerTextSize))
                .foregroundStyle(MinikPretty.navy)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)

            dailyLearningAction(locale.text("Back to learning"), metrics: metrics) {
                languageExtra = nil
            }

            FamilyMenuLink(title: FamilyMessages.text("More Minik apps & games", "עוד אפליקציות ומשחקי מיניק",
                                                      language: locale.rawValue)) {
                FamilyMessages.shared.showMoreApps(gate: nil)
            }

            dailyLearningAction(locale.text("Rate this app"), metrics: metrics) {
                requestKeepInTouch(.rate)
            }
            dailyLearningAction(locale.text("Share this app"), metrics: metrics) {
                requestKeepInTouch(.share)
            }
            dailyLearningAction(locale.text("Send feedback"), metrics: metrics) {
                requestKeepInTouch(.feedback)
            }

            if let keepInTouchProblem {
                Text(verbatim: keepInTouchProblem)
                    .font(.system(size: metrics.hintSize, weight: .semibold))
                    .foregroundStyle(MinikPretty.color(0xC2416E))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// The daily page's buttons: bg_pretty_button_blue with white text, at least 56 dp tall.
    private func dailyLearningAction(
        _ title: String,
        metrics: LanguageParentDialogMetrics,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(verbatim: title)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(LanguageParentActionButtonStyle(
            fontSize: metrics.buttonTextSize,
            minHeight: 56,
            look: MinikPretty.PillLook.blue
        ))
    }

    /// Android's label is two lines in every language ("מעקב\nהתקדמות",
    /// "Progreso de\naprendizaje"); the catalog keeps the same words with a space
    /// for the line break, so the last space becomes the break again.
    private var progressButtonTitle: String {
        let title = interfaceLocaleController.selectedLocale.text("Progress & Statistics")
        guard let lineBreak = title.range(of: " ", options: .backwards) else {
            return title
        }
        return title.replacingCharacters(in: lineBreak, with: "\n")
    }

    /// iOS-only grown-up pages. Android's dialog has none: Android keeps Remove
    /// Ads and its two footer links (links_container) on the Intro, while the App
    /// Store keeps purchases and outside links in the Parent Area. So they sit
    /// where Android's footer links are, 28/40 pt from the sides, as its pretty
    /// footer pills: a menu of the other pages where Android has "I have a code"
    /// and "Privacy Policy" where Android has it.
    private func languageFooter(metrics: LanguageParentDialogMetrics) -> some View {
        languageExtraLinks(metrics: metrics)
            .frame(maxWidth: metrics.footerMaxWidth)
            .padding(.horizontal, metrics.footerSideMargin)
    }

    /// The two pills centred together and kept in left-to-right order in every
    /// language, as in Android's links_container; stacked inside the card at
    /// accessibility sizes.
    @ViewBuilder
    private func languageExtraLinks(metrics: LanguageParentDialogMetrics) -> some View {
        if metrics.usesAccessibilityLayout {
            VStack(spacing: 10) {
                extraPagesMenuLink(metrics: metrics)
                privacyFooterLink(metrics: metrics)
            }
            .frame(maxWidth: .infinity)
        } else {
            HStack(spacing: metrics.footerPillGap) {
                extraPagesMenuLink(metrics: metrics)
                privacyFooterLink(metrics: metrics)
            }
            .frame(maxWidth: .infinity)
            .environment(\.layoutDirection, .leftToRight)
        }
    }

    private func extraPagesMenuLink(metrics: LanguageParentDialogMetrics) -> some View {
        let interfaceLocale = interfaceLocaleController.selectedLocale
        return Menu {
            ForEach(LanguageParentExtra.footerMenuPages) { extra in
                Button {
                    openExtra(extra)
                } label: {
                    Text(verbatim: extraTitleText(extra))
                }
            }
        } label: {
            languageFooterLinkLabel(interfaceLocale.text("Menu"), pill: .lavender, metrics: metrics)
        }
        .menuOrder(.fixed)
        // The menu lists its pages in the interface direction.
        .environment(\.layoutDirection, interfaceLocale.layoutDirection)
    }

    private func privacyFooterLink(metrics: LanguageParentDialogMetrics) -> some View {
        Button {
            openExtra(.privacy)
        } label: {
            languageFooterLinkLabel(
                interfaceLocaleController.selectedLocale.text("Privacy Policy"),
                pill: .sky,
                metrics: metrics
            )
        }
        .buttonStyle(.plain)
    }

    /// Android's pretty footer pill (bg_bottom_pill_lavender / _sky): a pale pill
    /// with a white rim over a soft drop, its bold Fredoka text in the pill's purple
    /// or blue, centred and at most two lines.
    private func languageFooterLinkLabel(
        _ title: String,
        pill: LanguageParentFooterPill,
        metrics: LanguageParentDialogMetrics
    ) -> some View {
        let maximumLines: Int? = metrics.usesAccessibilityLayout ? nil : 2
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        return Text(verbatim: title)
            .font(MinikPretty.titleFont(metrics.footerLinkSize))
            .foregroundStyle(pill.ink)
            .multilineTextAlignment(.center)
            .lineLimit(maximumLines)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 18)
            .padding(.top, 4)
            .padding(.bottom, 7)
            .frame(minHeight: metrics.footerHeight)
            .background {
                // The drop shows as a 3-point band under the pill's face.
                ZStack {
                    shape
                        .fill(LanguageParentFooterPill.drop)
                        .padding(.top, 3)
                    shape
                        .fill(pill.fill)
                        .overlay {
                            shape.strokeBorder(Color.white, lineWidth: 2)
                        }
                        .padding(.bottom, 3)
                }
            }
            .contentShape(shape)
    }

    /// A page title in the interface language, for the native menu.
    private func extraTitleText(_ extra: LanguageParentExtra) -> String {
        let interfaceLocale = interfaceLocaleController.selectedLocale
        switch extra {
        case .records: return interfaceLocale.text("Records & Streaks")
        case .reminders: return interfaceLocale.text("Learning reminders")
        case .purchases: return interfaceLocale.text("Purchases")
        case .leaderboard: return interfaceLocale.text("Online leaderboard")
        case .privacy: return interfaceLocale.text("Privacy, support & legal")
        case .dailyLearning: return interfaceLocale.text("Daily learning & feedback")
        }
    }

    private func extraTitle(_ extra: LanguageParentExtra) -> LocalizedStringKey {
        switch extra {
        case .records: return "Records & Streaks"
        case .reminders: return "Learning reminders"
        case .purchases: return "Purchases"
        case .leaderboard: return "Online leaderboard"
        case .privacy: return "Privacy, support & legal"
        case .dailyLearning: return "Daily learning & feedback"
        }
    }

    private func openExtra(_ extra: LanguageParentExtra) {
        switch extra {
        case .records:
            onShowRecords()
        case .reminders, .purchases, .leaderboard, .privacy, .dailyLearning:
            languageExtra = extra
        }
    }

    private func languageExtraPanel(
        _ extra: LanguageParentExtra,
        metrics: LanguageParentDialogMetrics
    ) -> some View {
        ZStack {
            Color.black.opacity(0.32)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { languageExtra = nil }
                .accessibilityHidden(true)

            languageDialogCard(
                width: metrics.dialogWidth,
                closeLabel: "Close",
                onClose: { languageExtra = nil }
            ) {
                VStack(alignment: .leading, spacing: 18) {
                    languageDialogTitle(extraTitle(extra), metrics: metrics)
                    extraContent(extra, metrics: metrics)
                }
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.top, metrics.topPadding)
                .padding(.bottom, 24)
                .toggleStyle(LanguageParentSwitchStyle())
            }
            .padding(.vertical, 16)
        }
        .accessibilityAction(.escape) { languageExtra = nil }
    }

    @ViewBuilder
    private func extraContent(_ extra: LanguageParentExtra, metrics: LanguageParentDialogMetrics) -> some View {
        switch extra {
        case .records:
            EmptyView()
        case .reminders:
            learningReminderSection(compact: true, inDialog: true)
        case .purchases:
            commerceSection(compact: true, inDialog: true)
        case .leaderboard:
            leaderboardSection(compact: true, inDialog: true)
        case .privacy:
            releaseInformationSection(compact: true, inDialog: true)
        case .dailyLearning:
            dailyLearningContent(metrics: metrics)
        }
    }

    // MARK: - Math and shared sections

    private var standardBody: some View {
        GeometryReader { geometry in
            let metrics = MinikHomeLayoutMetrics(containerWidth: geometry.size.width)

            ScrollView {
                MinikHomeSectionCard(compact: metrics.compact) {
                    VStack(alignment: .leading, spacing: metrics.compact ? 14 : 18) {
                        header(compact: metrics.compact)

                        // Android Math Plus ParentAreaScreen (dc12a5c): Learning progress first.
                        if configuration.contentDomain == .math, let onShowLearningProgress {
                            Button(action: onShowLearningProgress) {
                                Text(String(localized: "Learning progress"))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(ParentAreaActionButtonStyle())
                            .accessibilityHint(String(localized: "See recent practice and choose what to explore next."))
                        }

                        if configuration.contentDomain == .math, let mathLevelState {
                            mathLevelSection(state: mathLevelState, compact: metrics.compact)
                        }

                        if configuration.contentDomain == .math {
                            mathReadAloudSection(compact: metrics.compact)
                        }

                        if configuration.contentDomain == .language {
                            learnedLanguageSection(compact: metrics.compact)
                        }

                        interfaceLanguageSection(compact: metrics.compact)
                        // Encouraging messages exist only in the Language activities.
                        if configuration.contentDomain != .math {
                            encouragementSection(compact: metrics.compact)
                        }
                        learningReminderSection(compact: metrics.compact)
                        commerceSection(compact: metrics.compact)
                        if configuration.contentDomain == .math {
                            // Android Math Plus ParentScreens: "More Minik apps & games", before the
                            // feedback links; a quiet link here, never a regular app button.
                            FamilyMenuLink(title: FamilyMessages.text("More Minik apps & games", "עוד אפליקציות ומשחקי מיניק",
                                                                      language: interfaceLocaleController.selectedLocale.rawValue)) {
                                FamilyMessages.shared.showMoreApps(gate: nil)
                            }
                            // Android Math Plus ParentScreens (7682b75): "Keep in touch", after the
                            // family link.
                            keepInTouchSection(compact: metrics.compact)
                        }
                        releaseInformationSection(compact: metrics.compact)
                        progressActionsSection
                    }
                }
                .frame(maxWidth: 620)
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.vertical, metrics.verticalPadding)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
        // The rainbow sky of the hubs behind the glass card; a background never
        // sizes the layout (see MinikHomeScreen).
        .background {
            MinikSkyBackground()
        }
    }

    /// The design's navy Fredoka title with the close button and the logo.
    private func header(compact: Bool) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Text("Parent Area")
                    .font(MinikPretty.titleFont((compact ? 28 : 34) * titleTextScale / 100))
                    .foregroundStyle(MinikPretty.navy)
                    .multilineTextAlignment(.center)
                    // Kept clear of the close button and the logo, so larger
                    // text wraps instead of running underneath them.
                    .padding(.horizontal, compact ? 60 : 70)

                HStack {
                    Button(action: onExit) {
                        MinikArtworkImage(name: MinikVisualAsset.close)
                            .frame(width: compact ? 38 : 44, height: compact ? 38 : 44)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Close Parent Area")
                    .accessibilityHint("Returns to the activity menu")

                    Spacer()

                    MinikArtworkImage(name: MinikVisualAsset.logo)
                        .frame(width: compact ? 54 : 64, height: compact ? 42 : 50)
                }
            }

            Text("Manage learning settings and review local progress.")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(MinikPretty.softInk)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    private func mathLevelSection(state: MathLevelState, compact: Bool) -> some View {
        settingsCard(compact: compact) {
            VStack(alignment: .leading, spacing: 14) {
                settingsHeading("Math level")

                Picker("Math level mode", selection: Binding(
                    get: { state.mode },
                    set: onSetMathMode
                )) {
                    Text("Automatic").tag(MathLevelMode.automatic)
                    Text("Manual").tag(MathLevelMode.manual)
                }
                .pickerStyle(.segmented)
                .accessibilityHint("Automatic adapts from the current level. Manual keeps the selected level.")

                currentLevelRow(levelTitle(state.activeLevelID))

                Picker("Choose Math level", selection: Binding(
                    get: { state.activeLevelID },
                    set: onSelectMathLevel
                )) {
                    ForEach(MathCurriculumPolicy.levels) { level in
                        Text(level.title).tag(level.id)
                    }
                }
                .pickerStyle(.menu)
                .disabled(state.mode == .automatic)
                .accessibilityHint(
                    state.mode == .automatic
                        ? String(localized: "Switch to Manual to choose a level")
                        : String(localized: "Selects the level used for Math activities")
                )
            }
        }
    }

    /// The level beside its label, or under it when larger text leaves no room,
    /// so neither text wraps letter by letter.
    private func currentLevelRow(_ title: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Text("Current level")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(title)
                    .font(.headline.monospacedDigit())
                    .lineLimit(1)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Current level")
                    .font(.subheadline.weight(.semibold))
                Text(title)
                    .font(.headline.monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func learnedLanguageSection(compact: Bool) -> some View {
        settingsCard(compact: compact) {
            VStack(alignment: .leading, spacing: 14) {
                settingsHeading("Learned language")

                if configuration.isLearningLanguageSelectionAvailable {
                    Picker("Learned language", selection: Binding(
                        get: { selectedLanguage },
                        set: onSelectLanguage
                    )) {
                        ForEach(availableLearnedLanguages, id: \.self) { language in
                            Text(language.hubTitle).tag(language)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityHint("Changes the language practiced in learning activities")
                } else {
                    LabeledContent("Learned language", value: selectedLanguage.hubTitle)
                        .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func interfaceLanguageSection(compact: Bool) -> some View {
        settingsCard(compact: compact) {
            VStack(alignment: .leading, spacing: 14) {
                settingsHeading("Interface language")
                Picker("Interface language", selection: Binding(
                    get: { interfaceLocaleController.selectedLocale },
                    set: { interfaceLocaleController.select($0) }
                )) {
                    ForEach(interfaceLocaleController.allowedLocales) { locale in
                        Text(interfaceLocaleController.selectedLocale.text(locale.displayNameKey)).tag(locale)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }

    /// Android Minik Math Plus ParentScreens "Read aloud" (df82abe): one switch for the
    /// automatic reading of the how-to cards, instructions and exercises.
    private func mathReadAloudSection(compact: Bool) -> some View {
        settingsCard(compact: compact) {
            Toggle(isOn: Binding(
                get: { mathReadAloudEnabled },
                set: { value in
                    mathReadAloudEnabled = value
                    MathReadAloudPreferenceRepository().save(value)
                }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Read aloud")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(MinikPretty.navy)
                    Text("Read each instruction and exercise aloud when it appears.")
                        .font(.subheadline)
                        .foregroundStyle(MinikPretty.softInk)
                }
            }
            .tint(Color(red: 0.98, green: 0.78, blue: 0.05))
        }
    }

    private func encouragementSection(compact: Bool) -> some View {
        settingsCard(compact: compact) {
            Toggle(isOn: Binding(
                get: { encouragementEnabled },
                set: { value in
                    encouragementEnabled = value
                    encouragementRepository.save(value, for: configuration.variant)
                }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Encouraging messages")
                        .font(.headline.weight(.bold))
                    Text("Play an encouraging message at the end of each exercise.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(Color(red: 0.98, green: 0.78, blue: 0.05))
            .accessibilityHint("Controls encouraging practice messages")
        }
    }

    /// `inDialog` drops the card frame and repeats no title the Language dialog
    /// already shows above it.
    private func learningReminderSection(compact: Bool, inDialog: Bool = false) -> some View {
        settingsCard(compact: compact, framed: !inDialog) {
            Toggle(isOn: Binding(
                get: { learningReminderController.isEnabled },
                set: { enabled in
                    Task {
                        await learningReminderController.setEnabled(
                            enabled,
                            locale: interfaceLocaleController.selectedLocale
                        )
                    }
                }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    if !inDialog {
                        Text("Learning reminders")
                            .font(.headline.weight(.bold))
                    }
                    Text("Send one gentle reminder each week.")
                        .font(inDialog ? .headline : .subheadline)
                        .foregroundStyle(inDialog ? Color.primary : Color.secondary)
                }
            }
            .tint(LanguagePalette.teal)
            .disabled(learningReminderController.status == .working)
            .accessibilityHint("Notification permission is requested only when a parent turns reminders on")

            if let statusMessage = reminderStatusMessage {
                Text(statusMessage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(learningReminderController.status == .failed ? .red : .secondary)
            }
        }
    }

    private var reminderStatusMessage: String? {
        switch learningReminderController.status {
        case .disabled, .enabled:
            return nil
        case .working:
            return String(localized: "Updating reminder settings…")
        case .denied:
            return String(localized: "Notifications are turned off in Settings.")
        case .failed:
            return String(localized: "The reminder could not be scheduled.")
        }
    }

    private func leaderboardSection(compact: Bool, inDialog: Bool = false) -> some View {
        settingsCard(compact: compact, framed: !inDialog) {
            if !inDialog {
                settingsHeading("Online leaderboard")
            }

            Toggle(isOn: Binding(
                get: { publicLeaderboardController.participationEnabled },
                set: { enabled in
                    gatedParentAction = .leaderboardParticipation(enabled)
                }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Share records using a generated alias.")
                        .font(.headline)
                    Text("Your child’s local name stays on this device.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(LanguagePalette.teal)
            .disabled(publicLeaderboardController.isWorking)
            .accessibilityHint("Turns public leaderboard participation on or off")

            VStack(alignment: .leading, spacing: 5) {
                Text("Only an opaque participant identifier, generated alias or avatar, score or streak, product identifier, and timestamp are sent.")
                Text("Firebase stores the public leaderboard.")
                Text("You can turn participation off later.")
                Text("You can delete this participant’s public leaderboard records.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let alias = publicLeaderboardController.selectedAlias {
                LabeledContent("Public alias") {
                    HStack(spacing: 6) {
                        if let avatar = alias.avatar {
                            Image(systemName: avatar.symbolName)
                                .accessibilityHidden(true)
                        }
                        Text(verbatim: alias.publicAlias)
                    }
                }
                .font(.subheadline.weight(.semibold))

                Button("Show different aliases") {
                    rerollPublicAliasChoices()
                    showsPublicAliasChoices = true
                }
                .buttonStyle(ParentAreaActionButtonStyle(look: MinikPretty.PillLook.white))
                .disabled(publicLeaderboardController.isWorking)

                if showsPublicAliasChoices {
                    VStack(spacing: 8) {
                        ForEach(publicAliasChoices) { choice in
                            Button {
                                showsPublicAliasChoices = false
                                Task { await publicLeaderboardController.selectPublicAlias(choice) }
                            } label: {
                                HStack(spacing: 8) {
                                    if let avatar = choice.avatar {
                                        Image(systemName: avatar.symbolName)
                                            .accessibilityHidden(true)
                                    }
                                    Text(verbatim: choice.publicAlias)
                                    Spacer(minLength: 0)
                                }
                                .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(ParentAreaActionButtonStyle(look: MinikPretty.PillLook.white))
                            .accessibilityLabel(Text(choice.publicAlias))
                        }

                        Button("Show different aliases", action: rerollPublicAliasChoices)
                            .buttonStyle(.plain)
                    }
                }
            } else {
                Text("The child chooses from generated aliases after a qualifying score.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if publicLeaderboardController.hasPendingPublication {
                Label("A best score is waiting to publish.", systemImage: "clock.badge.exclamationmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(red: 0.57, green: 0.39, blue: 0.08))
            }

            if !publicLeaderboardController.participationEnabled {
                Button("Delete public leaderboard records") {
                    gatedParentAction = .deletePublicRecords
                }
                .buttonStyle(ParentAreaActionButtonStyle(look: MinikPretty.PillLook.white))
                .disabled(publicLeaderboardController.isWorking)
                .accessibilityHint("Deletes this participant’s public leaderboard records")
            }

            if publicLeaderboardController.isWorking {
                ProgressView("Updating leaderboard settings…")
            } else if let statusMessage = leaderboardStatusMessage {
                Text(statusMessage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(publicLeaderboardController.status == .failed ? .red : .secondary)
            }
        }
    }

    private var leaderboardStatusMessage: String? {
        switch publicLeaderboardController.status {
        case .idle, .working:
            return nil
        case .enabled:
            return String(localized: "Online leaderboard enabled.")
        case .enabledWaitingForAlias:
            return String(localized: "Online leaderboard is waiting for an alias.")
        case .enabledPendingRetry:
            return String(localized: "Online leaderboard will retry the pending record when Firebase is available.")
        case .disabled:
            return String(localized: "Online leaderboard disabled.")
        case .deleted:
            return String(localized: "Public leaderboard records deleted.")
        case .failed:
            return String(localized: "The leaderboard setting could not be updated.")
        }
    }

    private func rerollPublicAliasChoices() {
        publicAliasChoices = PublicLeaderboardAliasGenerator().choices(count: 4)
    }

    private func commerceSection(compact: Bool, inDialog: Bool = false) -> some View {
        settingsCard(compact: compact, framed: !inDialog) {
            if !inDialog {
                settingsHeading("Purchases")
            }

            if commerceController.isRemoveAdsActive {
                Label("Ads removed", systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(Color(red: 0.10, green: 0.52, blue: 0.32))
                Text("Your Remove Ads purchase is active.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if let product = commerceController.removeAdsProduct {
                Text(String(
                    format: String(localized: "Remove Ads — %@"),
                    product.displayPrice
                ))
                .font(.headline)

                Button("Remove Ads") {
                    gatedParentAction = .purchase
                }
                .buttonStyle(ParentAreaActionButtonStyle())
                .disabled(commerceController.isBusy)
                .accessibilityHint("Opens a grown-up check before contacting the App Store")
            } else if commerceController.status == .unconfigured {
                Text("Purchases are not configured for this build.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if commerceController.configuration.removeAdsProductID != nil {
                Button("Restore Purchases") {
                    gatedParentAction = .restore
                }
                .buttonStyle(ParentAreaActionButtonStyle(look: MinikPretty.PillLook.white))
                .disabled(commerceController.isBusy)
                .accessibilityHint("Opens a grown-up check before restoring App Store purchases")
            }

            if commerceController.isBusy {
                ProgressView(commerceStatusMessage ?? String(localized: "Checking purchases…"))
            } else if let commerceStatusMessage {
                Text(commerceStatusMessage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(commerceController.status == .failed ? .red : .secondary)
            }
        }
    }

    private var commerceStatusMessage: String? {
        switch commerceController.status {
        case .unconfigured, .ready:
            return nil
        case .loading:
            return String(localized: "Checking purchases…")
        case .purchasing:
            return String(localized: "Contacting the App Store…")
        case .pending:
            return String(localized: "Purchase approval is pending.")
        case .cancelled:
            return String(localized: "Purchase cancelled.")
        case .restoring:
            return String(localized: "Restoring purchases…")
        case .failed:
            return String(localized: "The App Store request could not be completed.")
        }
    }

    private func releaseInformationSection(compact: Bool, inDialog: Bool = false) -> some View {
        settingsCard(compact: compact, framed: !inDialog) {
            if !inDialog {
                settingsHeading("Privacy, support & legal")
            }

            // Only the links this build has: a page it does not have (Terms of Use, as these
            // apps use Apple's standard EULA) is left out rather than shown disabled.
            ForEach(MinikExternalDestination.allCases.filter { releaseInformation.url(for: $0) != nil }) { destination in
                Button {
                    gatedParentAction = .external(destination)
                } label: {
                    HStack {
                        Text(externalDestinationTitle(destination))
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(ParentAreaActionButtonStyle(look: MinikPretty.PillLook.white))
                .accessibilityHint(String(localized: "Opens a grown-up check before leaving the app"))
            }

            if !releaseInformation.hasExternalDestinations {
                Text("Links are not configured for this build.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let legalNotice = releaseInformation.legalNotice {
                Text(verbatim: legalNotice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(legalNotice)
            }

            LabeledContent("App version", value: releaseInformation.versionDescription)
                .font(.caption.monospacedDigit())
                .accessibilityElement(children: .combine)
        }
    }

    private func externalDestinationTitle(
        _ destination: MinikExternalDestination
    ) -> LocalizedStringKey {
        switch destination {
        case .privacyPolicy: return "Privacy Policy"
        case .termsOfUse: return "Terms of Use"
        case .support: return "Support"
        }
    }

    private func performGatedAction(_ action: GatedParentAction) {
        switch action {
        case .purchase:
            Task {
                await commerceController.purchaseRemoveAds()
            }
        case .restore:
            Task {
                await commerceController.restorePurchases()
            }
        case .external(let destination):
            if let url = releaseInformation.url(for: destination) {
                openURL(url)
            }
        case .leaderboardParticipation(let enabled):
            Task { await publicLeaderboardController.setParticipationEnabled(enabled) }
        case .deletePublicRecords:
            Task { await publicLeaderboardController.deletePublicRecords() }
        case .keepInTouch(let keepInTouchAction):
            // Run once the grown-up check's sheet has gone (runPendingKeepInTouch).
            pendingKeepInTouch = keepInTouchAction
        }
    }

    // MARK: - Rate, share and feedback (Android DailyLearningActivity, Math Plus "Keep in touch")

    /// Android Math Plus ParentScreens: the "Keep in touch" heading with Rate this app,
    /// Share this app and Send feedback.
    private func keepInTouchSection(compact: Bool) -> some View {
        settingsCard(compact: compact) {
            settingsHeading("Keep in touch")

            Button {
                requestKeepInTouch(.rate)
            } label: {
                Text("Rate this app")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(ParentAreaActionButtonStyle())

            Button {
                requestKeepInTouch(.share)
            } label: {
                Text("Share this app")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(ParentAreaActionButtonStyle(look: MinikPretty.PillLook.white))

            Button {
                requestKeepInTouch(.feedback)
            } label: {
                Text("Send feedback")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(ParentAreaActionButtonStyle())

            if let keepInTouchProblem {
                Text(verbatim: keepInTouchProblem)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.red)
            }
        }
    }

    private static let ratingPromptNoteKey: String.LocalizationValue =
        "No rating window? The App Store shows it only in the published app, and not every time."

    private func requestKeepInTouch(_ action: MinikKeepInTouchAction) {
        keepInTouchProblem = nil
        gatedParentAction = .keepInTouch(action)
    }

    /// The grown-up check's sheet has gone: the unlocked action runs now, so the share sheet
    /// or the App Store's rating prompt can appear.
    private func runPendingKeepInTouch() {
        guard let action = pendingKeepInTouch else { return }
        pendingKeepInTouch = nil
        let product = configuration.variant
        switch action {
        case .rate:
            if let url = MinikAppFeedback.reviewURL() {
                let problem = interfaceLocaleController.selectedLocale.text("No suitable app is installed")
                openURL(url) { accepted in
                    if !accepted {
                        keepInTouchProblem = problem
                    }
                }
            } else {
                MinikAppFeedback.requestReview()
                // The App Store's prompt may not appear (never in TestFlight), and the app
                // cannot tell, so the grown-up is told why nothing may have opened.
                keepInTouchProblem = interfaceLocaleController.selectedLocale.text(Self.ratingPromptNoteKey)
            }
        case .share:
            shareRequest = MinikShareText(text: MinikAppFeedback.shareText(for: product))
        case .feedback:
            guard let url = MinikAppFeedback.feedbackURL(for: product) else { return }
            let problem = interfaceLocaleController.selectedLocale.text("No suitable app is installed")
            openURL(url) { accepted in
                if !accepted {
                    keepInTouchProblem = problem
                }
            }
        }
    }

    private var progressActionsSection: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                progressButton
                recordsButton
            }

            VStack(spacing: 12) {
                progressButton
                recordsButton
            }
        }
    }

    private var progressButton: some View {
        Button(action: onShowProgress) {
            Text("Progress & Statistics")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(ParentAreaActionButtonStyle())
        .accessibilityHint("Opens locally stored educational progress")
    }

    private var recordsButton: some View {
        Button(action: onShowRecords) {
            Text("Records & Streaks")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(ParentAreaActionButtonStyle())
        .accessibilityHint("Opens locally stored streak records")
    }

    /// A section of the glass card in the design's lavender: a pale lavender
    /// fill with a lavender rim.
    private func settingsCard<Content: View>(
        compact: Bool,
        framed: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: compact ? 12 : 14) {
            content()
        }
        .padding(framed ? (compact ? 14 : 16) : 0)
        .background(
            RoundedRectangle(cornerRadius: compact ? 18 : 22, style: .continuous)
                .fill(framed ? MinikPretty.color(0xF8F5FF) : Color.clear)
        )
        .overlay {
            RoundedRectangle(cornerRadius: compact ? 18 : 22, style: .continuous)
                .strokeBorder(
                    LanguageParentPalette.dialogStroke.opacity(framed ? 1 : 0),
                    lineWidth: 1.5
                )
        }
    }

    /// A section's header in the design's navy Fredoka.
    private func settingsHeading(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(MinikPretty.titleFont(17 * bodyTextScale / 100))
            .foregroundStyle(MinikPretty.navy)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var availableLearnedLanguages: [LanguageIdentifier] {
        configuration.allowedLearnedLanguages.sorted { $0.rawValue < $1.rawValue }
    }

    private func levelTitle(_ id: MathCurriculumLevelID) -> String {
        MathCurriculumPolicy.level(for: id)?.title ?? String(localized: "Level 1")
    }
}

/// Grown-up-only actions. The public leaderboard switch and record deletion are
/// gated per the 2026-09-13 public leaderboard privacy decision.
private enum GatedParentAction: Identifiable {
    case purchase
    case restore
    case external(MinikExternalDestination)
    case leaderboardParticipation(Bool)
    case deletePublicRecords
    /// Rate, share and feedback leave the app (Apple's Kids rules).
    case keepInTouch(MinikKeepInTouchAction)

    var id: String {
        switch self {
        case .purchase: return "purchase"
        case .restore: return "restore"
        case .external(let destination): return "external.\(destination.rawValue)"
        case .leaderboardParticipation(let enabled): return "leaderboard.\(enabled)"
        case .deletePublicRecords: return "leaderboard.delete"
        case .keepInTouch(let action): return "keepInTouch.\(action.rawValue)"
        }
    }
}

/// iOS-only Language Parent Area pages, reached from the footer under the
/// Android dialog, and Android's daily learning page (DailyLearningActivity), reached
/// from its button in the dialog.
private enum LanguageParentExtra: String, CaseIterable, Hashable, Identifiable {
    case records
    case reminders
    case purchases
    case leaderboard
    case privacy
    case dailyLearning

    var id: String { rawValue }

    /// The pages in the footer menu; Privacy has its own footer link.
    static let footerMenuPages: [LanguageParentExtra] = [.records, .reminders, .purchases, .leaderboard]
}

/// The design's glossy pill (MinikPretty.PillBackground) with Fredoka text that
/// follows Dynamic Type: blue for the main actions, white for the others.
private struct ParentAreaActionButtonStyle: ButtonStyle {
    let look: MinikPretty.PillLook
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(look: MinikPretty.PillLook = MinikPretty.PillLook.blue) {
        self.look = look
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.custom("Fredoka-Bold", size: 17, relativeTo: .headline))
            .foregroundStyle(look.ink)
            .multilineTextAlignment(.center)
            .shadow(color: look.inkShadow, radius: 1.5, x: 0, y: 1)
            .padding(.horizontal, 16)
            // The face sits 3 points above the pill's lip.
            .padding(.top, 9)
            .padding(.bottom, 12)
            .frame(minHeight: 52)
            .background {
                MinikPretty.PillBackground(look: look, pressed: configuration.isPressed)
            }
            .contentShape(Capsule(style: .continuous))
            .opacity(isEnabled ? 1 : 0.5)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

/// Android's levelsButton / statisticsButton in the rainbow-sky design
/// (bg_pretty_button_purple and _blue): a glossy pill with white Fredoka text
/// centred in it.
private struct LanguageParentActionButtonStyle: ButtonStyle {
    let fontSize: CGFloat
    let minHeight: CGFloat
    let look: MinikPretty.PillLook
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(fontSize: CGFloat, minHeight: CGFloat, look: MinikPretty.PillLook) {
        self.fontSize = fontSize
        self.minHeight = minHeight
        self.look = look
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MinikPretty.titleFont(fontSize))
            .foregroundStyle(look.ink)
            .multilineTextAlignment(.center)
            .shadow(color: look.inkShadow, radius: 1.5, x: 0, y: 1)
            .padding(.horizontal, 10)
            // The face sits 3 points above the pill's lip.
            .padding(.top, 6)
            .padding(.bottom, 9)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .background {
                MinikPretty.PillBackground(look: look, pressed: configuration.isPressed)
            }
            .contentShape(Capsule(style: .continuous))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

/// Android's pretty footer pills (bg_bottom_pill_lavender and _sky) with their
/// pretty_purple_text and pretty_blue_text.
private enum LanguageParentFooterPill {
    case lavender
    case sky

    /// The soft drop under both pills (#26205A3C).
    static let drop = MinikPretty.color(0x205A3C, opacity: 0.15)

    var fill: Color {
        switch self {
        case .lavender: return MinikPretty.color(0xF1EEFF)
        case .sky: return MinikPretty.color(0xECF7FF)
        }
    }

    var ink: Color {
        switch self {
        case .lavender: return MinikPretty.color(0x6A55D6)
        case .sky: return MinikPretty.color(0x2B8FD6)
        }
    }
}

// MARK: - Android dialog look shared by the Language Parent Area and its Levels dialog

/// Colours from dialog_languages_and_levels.xml, dialog_levels_difficulty.xml,
/// bg_pretty_dialog, bg_spinner_arrow, bg_level_progress and the switch tints.
enum LanguageParentPalette {
    static let title = Color(red: 63 / 255, green: 79 / 255, blue: 173 / 255)
    static let action = Color(red: 47 / 255, green: 107 / 255, blue: 255 / 255)
    static let onSurface = Color(red: 29 / 255, green: 27 / 255, blue: 32 / 255)
    /// bg_pretty_dialog: white with a 2 dp #E6DEFF rim.
    static let dialogFill = Color.white
    static let dialogStroke = Color(red: 230 / 255, green: 222 / 255, blue: 255 / 255)
    static let spinnerStroke = Color(red: 204 / 255, green: 204 / 255, blue: 204 / 255)
    static let outline = Color(red: 121 / 255, green: 116 / 255, blue: 126 / 255)
    static let switchThumb = Color(red: 24 / 255, green: 183 / 255, blue: 176 / 255)
    static let switchTrackOn = Color(red: 240 / 255, green: 213 / 255, blue: 0)
    static let switchTrackOff = Color(red: 231 / 255, green: 231 / 255, blue: 234 / 255)
    static let levelBase = Color(red: 215 / 255, green: 236 / 255, blue: 255 / 255)
    static let levelFillStart = Color(red: 30 / 255, green: 136 / 255, blue: 229 / 255)
    static let levelFillEnd = Color(red: 66 / 255, green: 165 / 255, blue: 245 / 255)
    static let levelBorder = Color(red: 185 / 255, green: 199 / 255, blue: 214 / 255)
    static let levelText = Color(red: 38 / 255, green: 50 / 255, blue: 56 / 255)
    /// fragment_intro_plus.xml footer links.
    static let footerLink = Color(red: 34 / 255, green: 34 / 255, blue: 34 / 255)
}

/// Android dialog sizes. Phones use the sw360dp-h*dp values for their screen
/// height; sw600dp and wider use the tablet values (sw700dp/sw800dp where they
/// differ), with Android's French and Russian overrides. Text then follows
/// Dynamic Type from those sizes.
struct LanguageParentDialogMetrics {
    let dialogWidth: CGFloat
    let usesAccessibilityLayout: Bool
    let titleSize: CGFloat
    let captionSize: CGFloat
    let hintSize: CGFloat
    let spinnerTextSize: CGFloat
    let buttonTextSize: CGFloat
    let subtitleSize: CGFloat
    let levelSpinnerTextSize: CGFloat
    let levelChipTextSize: CGFloat
    let levelValueWidth: CGFloat
    let levelValueHeight: CGFloat
    let dropdownHeight: CGFloat
    let buttonMinHeight: CGFloat
    let horizontalPadding: CGFloat
    let topPadding: CGFloat
    let titleToCaption: CGFloat
    let captionToField: CGFloat
    let fieldToCaption: CGFloat
    let fieldToSwitch: CGFloat
    let switchTitleToHint: CGFloat
    let switchToButtons: CGFloat
    let bottomPadding: CGFloat
    let footerLinkSize: CGFloat
    let footerLinkPadding: CGFloat
    let footerSideMargin: CGFloat
    let footerHeight: CGFloat
    let footerMaxWidth: CGFloat
    let footerPillGap: CGFloat
    /// The footer pills' distance from the bottom of the safe area: more where the
    /// screen has no home indicator inset (iPhone SE), so they do not sit on the edge.
    let footerBottomMargin: CGFloat

    init(
        containerSize: CGSize,
        safeAreaInsets: EdgeInsets,
        interfaceLocale: InterfaceLocaleID,
        titleScale: CGFloat,
        textScale: CGFloat,
        accessibilityLayout: Bool
    ) {
        let width = max(1, containerSize.width)
        let screenHeight = max(1, containerSize.height + safeAreaInsets.top + safeAreaInsets.bottom)
        let tablet = width >= 600
        let wideTablet = width >= 700

        let maximumWidth: CGFloat
        if width >= 800 {
            maximumWidth = 640
        } else if tablet {
            maximumWidth = 560
        } else {
            maximumWidth = 420
        }
        dialogWidth = max(1, min(width * 0.93, maximumWidth))
        usesAccessibilityLayout = accessibilityLayout

        let caption: CGFloat
        let levelSpinner: CGFloat
        if tablet {
            caption = 28
            levelSpinner = wideTablet ? 26 : 22
        } else if screenHeight >= 900 {
            caption = 24
            levelSpinner = 16
        } else if screenHeight >= 800 {
            caption = 21
            levelSpinner = 15
        } else {
            caption = 20
            levelSpinner = 14
        }
        let hint: CGFloat = tablet ? 20 : (screenHeight >= 720 ? 14 : 13)
        let spinner: CGFloat = wideTablet ? 30 : (tablet ? 24 : 18)
        let button: CGFloat
        if interfaceLocale == .french {
            button = wideTablet ? 26 : (tablet ? 23 : 14)
        } else {
            button = tablet ? 24 : 16
        }
        let valueWidth: CGFloat
        if interfaceLocale == .russian {
            valueWidth = tablet ? 230 : (screenHeight >= 800 ? 190 : 180)
        } else {
            valueWidth = tablet ? 200 : 165
        }
        let title: CGFloat = tablet ? 38 : 24
        let subtitle: CGFloat = tablet ? 34 : 20

        titleSize = title * titleScale
        captionSize = caption * textScale
        hintSize = hint * textScale
        spinnerTextSize = spinner * textScale
        buttonTextSize = button * textScale
        subtitleSize = subtitle * textScale
        levelSpinnerTextSize = levelSpinner * textScale
        levelChipTextSize = 16 * textScale
        levelValueWidth = valueWidth
        levelValueHeight = max(44, levelSpinner * textScale * 1.33 + 16)
        // An Android spinner is 8 dp padding around one line of its text.
        dropdownHeight = spinner * textScale * 1.33 + 19
        // As tall as Android's two-line "Learning progress" pill.
        buttonMinHeight = button * textScale * 2.38 + 23

        horizontalPadding = 16
        topPadding = tablet ? 33 : 31
        titleToCaption = tablet ? 32 : 29
        captionToField = tablet ? 6 : 5
        fieldToCaption = tablet ? 20 : 18
        fieldToSwitch = tablet ? 20 : 18
        switchTitleToHint = tablet ? 5 : 4
        switchToButtons = tablet ? 36 : 32
        // The pills' 12 dp bottom margin and the dialog's 16 dp padding.
        bottomPadding = 28

        // Android's pretty Intro footer pills (dimens_pretty.xml): bold Fredoka
        // 16 sp in 46 dp pills 20 dp apart on phones, 21 sp in 58 dp pills 32 dp
        // apart on tablets; 28/40 dp from the sides, at most 900 dp wide.
        let footerLink: CGFloat = tablet ? 21 : 16
        footerLinkSize = footerLink * textScale
        footerLinkPadding = tablet ? 12 : 0
        footerSideMargin = tablet ? 40 : 28
        footerHeight = tablet ? 58 : 46
        footerMaxWidth = 900
        footerPillGap = tablet ? 32 : 20
        footerBottomMargin = safeAreaInsets.bottom > 0 ? (tablet ? 12 : 8) : (tablet ? 28 : 22)
    }
}

/// bg_pretty_dialog: white with 28 dp corners on a soft shadow. The dialog draws
/// the 2 dp #E6DEFF rim over its content.
struct LanguageParentDialogBackground: View {
    static let cornerRadius: CGFloat = 28

    var body: some View {
        RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
            .fill(LanguageParentPalette.dialogFill)
            .shadow(color: MinikPretty.navy.opacity(0.2), radius: 12, x: 0, y: 6)
    }
}

/// bg_spinner_arrow: white, 16 dp corners, a 2 dp #CCCCCC edge, black text at the
/// start and the black triangle at the end.
struct LanguageParentDropdownLabel: View {
    let title: String
    let fontSize: CGFloat
    let minHeight: CGFloat
    var showsArrow: Bool = true

    var body: some View {
        HStack(spacing: 8) {
            Text(verbatim: title)
                .font(.system(size: fontSize))
                .foregroundStyle(Color.black)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)
            if showsArrow {
                LanguageParentDropdownArrow()
                    .fill(Color.black)
                    .frame(width: 16, height: 9)
                    .accessibilityHidden(true)
            }
        }
        .padding(.leading, 17)
        .padding(.trailing, showsArrow ? 24 : 17)
        .frame(maxWidth: .infinity, minHeight: minHeight)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(LanguageParentPalette.spinnerStroke, lineWidth: 2)
        }
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }
}

/// ic_arrow_down.
struct LanguageParentDropdownArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Android's MaterialSwitch with switch_track / switch_thumb tints: a yellow
/// track when on, light grey with an outline when off, and a teal thumb that
/// sits at the end when on. VoiceOver gets a standard switch.
struct LanguageParentSwitchStyle: ToggleStyle {
    let alignment: VerticalAlignment

    init(alignment: VerticalAlignment = .center) {
        self.alignment = alignment
    }

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(alignment: alignment, spacing: 12) {
                configuration.label
                    .frame(maxWidth: .infinity, alignment: .leading)
                LanguageParentSwitchTrack(isOn: configuration.isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn: Binding(
                get: { configuration.isOn },
                set: { configuration.isOn = $0 }
            )) {
                configuration.label
            }
            .toggleStyle(.switch)
        }
    }
}

struct LanguageParentSwitchTrack: View {
    let isOn: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(isOn: Bool) {
        self.isOn = isOn
    }

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? LanguageParentPalette.switchTrackOn : LanguageParentPalette.switchTrackOff)
            Capsule()
                .strokeBorder(isOn ? Color.clear : LanguageParentPalette.outline, lineWidth: 2)
            Circle()
                .fill(LanguageParentPalette.switchThumb)
                .frame(width: isOn ? 24 : 16, height: isOn ? 24 : 16)
                .padding(.horizontal, isOn ? 4 : 8)
        }
        .frame(width: 52, height: 32)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isOn)
        .accessibilityHidden(true)
    }
}
