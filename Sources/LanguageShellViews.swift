import SwiftUI
import UIKit

/// Android IntroScreen / fragment_intro_plus.xml in the rainbow-sky design: the sky,
/// the MINIK+plus logo with the score tiles beside it, and a glass panel with the
/// welcome, the child selector with Add, Edit and Delete, Parent Area, Practice
/// and Remove Ads. These are Language routes; Math has its own hub.
struct LanguageIntroView: View {
    let rewards: RewardState
    let variant: ProductVariant
    let childProfiles: ChildProfileStore
    let commerceController: MinikCommerceController
    /// Another child (or the guest) now plays: the hub reloads that learner's values.
    let onLearnerChanged: () -> Void
    let onPractice: () -> Void
    let onParentArea: () -> Void
    @Environment(\.interfaceLocaleID) private var interfaceLocaleID
    // Android's sp text follows the font-size setting; this follows Dynamic Type.
    @ScaledMetric(relativeTo: .title2) private var textPercent: CGFloat = 100
    @State private var childDialog: ChildProfileDialogRequest?
    @State private var removeAdsGateIsPresented = false
    /// A grown-up started a purchase here, so its outcome is shown under the button.
    @State private var removeAdsWasRequested = false

    init(
        rewards: RewardState,
        variant: ProductVariant = .minikPlus,
        childProfiles: ChildProfileStore,
        commerceController: MinikCommerceController,
        onLearnerChanged: @escaping () -> Void,
        onPractice: @escaping () -> Void,
        onParentArea: @escaping () -> Void
    ) {
        self.rewards = rewards
        self.variant = variant
        self.childProfiles = childProfiles
        self.commerceController = commerceController
        self.onLearnerChanged = onLearnerChanged
        self.onPractice = onPractice
        self.onParentArea = onParentArea
    }

    var body: some View {
        ZStack {
            introScreen
                // The name dialog's keyboard does not reflow the intro behind it.
                .ignoresSafeArea(.keyboard)
            if let request = childDialog {
                ChildProfileDialog(request: request, store: childProfiles) { learnerChanged in
                    closeChildDialog()
                    if learnerChanged {
                        onLearnerChanged()
                    }
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
        // Apple's Kids rules: a grown-up check comes before any purchase.
        .sheet(isPresented: $removeAdsGateIsPresented) {
            ParentalGateView(
                onCancel: { removeAdsGateIsPresented = false },
                onUnlock: {
                    removeAdsGateIsPresented = false
                    removeAdsWasRequested = true
                    Task { await commerceController.purchaseRemoveAds() }
                }
            )
        }
    }

    private var introScreen: some View {
        GeometryReader { geometry in
            let metrics = LanguagePrettyMetrics(size: geometry.size)
            let panelWidth = max(1, min(metrics.panelMaxWidth, geometry.size.width - 2 * metrics.panelMargin))
            let artWidth = max(1, min(metrics.welcomeMaxWidth, panelWidth - 2 * metrics.welcomeMargin))
            VStack(spacing: 0) {
                header(metrics)
                MinikGlassPanel(padding: 0, cornerRadius: metrics.panelRadius) {
                    // The panel fits the screen at ordinary sizes, its buttons at the
                    // bottom. On shorter screens Minik's picture gets smaller first, as
                    // Android's fitWelcomeImageToCard does; when the content still does
                    // not fit (larger text), the panel scrolls.
                    ViewThatFits(in: .vertical) {
                        panelContent(metrics, artWidth: artWidth, fillsHeight: true)
                        panelContent(metrics, artWidth: artWidth * 0.78, fillsHeight: true)
                        panelContent(metrics, artWidth: artWidth * 0.6, fillsHeight: true)
                        ScrollView {
                            panelContent(metrics, artWidth: artWidth * 0.6, fillsHeight: false)
                        }
                        .scrollBounceBehavior(.basedOnSize)
                        .scrollIndicators(.hidden)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: metrics.panelRadius, style: .continuous))
                }
                .frame(width: panelWidth)
                .frame(maxHeight: .infinity)
                .padding(.top, metrics.panelTopMargin)
                .padding(.bottom, metrics.panelBottomMargin)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
        // A background never sizes the layout (see LanguageActivityScreen).
        .background {
            MinikSkyBackground()
        }
    }

    /// The logo at the start and the Points and Best Streak tiles at the end, on the sky.
    private func header(_ metrics: LanguagePrettyMetrics) -> some View {
        HStack(alignment: .center, spacing: metrics.statGap) {
            MinikLanguageLogo()
                .frame(width: metrics.logoWidth, height: metrics.logoHeight)
            Spacer(minLength: 0)
            LanguagePrettyStatTile(
                kind: .points,
                title: interfaceLocaleID.text("Points"),
                value: rewards.points,
                metrics: metrics
            )
            LanguagePrettyStatTile(
                kind: .streak,
                title: interfaceLocaleID.text("Best streak"),
                value: Int64(rewards.bestStreak),
                metrics: metrics
            )
        }
        .padding(.horizontal, metrics.screenMargin)
        .padding(.top, metrics.topMargin)
    }

    /// The navy welcome title, Minik on the rainbow, the child section, and the big
    /// pill buttons: Parent Area (purple) and Practice (warm), with the white
    /// Remove Ads under them, as on Android; centred in the panel when it has room
    /// to spare (tall phones, iPad).
    private func panelContent(_ metrics: LanguagePrettyMetrics, artWidth: CGFloat, fillsHeight: Bool) -> some View {
        VStack(spacing: 0) {
            if fillsHeight {
                Spacer(minLength: 0)
            }
            Text(interfaceLocaleID.text("Welcome"))
                .font(MinikPretty.titleFont(metrics.introTitleSize * textScale))
                .foregroundStyle(MinikPretty.navy)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, metrics.introContentMargin)
                .accessibilityAddTraits(.isHeader)
            MinikArtworkImage(name: MinikPretty.Art.welcome)
                .frame(width: artWidth, height: artWidth / MinikPretty.Art.welcomeAspect)
                .padding(.top, 2)
                .padding(.bottom, metrics.introSectionGap)
            ChildProfileSection(
                store: childProfiles,
                metrics: ChildProfileSectionMetrics(
                    tablet: metrics.tablet,
                    scale: metrics.scale,
                    textScale: textScale
                ),
                onSelect: selectChild,
                onAdd: { presentChildDialog(.add) },
                onEdit: { child in presentChildDialog(.rename(child)) },
                onDelete: { child in presentChildDialog(.delete(child)) }
            )
            .frame(maxWidth: metrics.introColumnMaxWidth)
            .padding(.horizontal, metrics.introContentMargin)
            .padding(.bottom, metrics.introSectionGap)
            VStack(spacing: metrics.buttonGap) {
                Button(action: onParentArea) {
                    Text(interfaceLocaleID.text("Parent Area"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(MinikPretty.HeroButtonStyle(
                    look: MinikPretty.PillLook.purple,
                    fontSize: metrics.buttonTextSize * textScale,
                    minHeight: metrics.buttonHeight
                ))
                Button(action: onPractice) {
                    Text(interfaceLocaleID.text("Practice"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(MinikPretty.HeroButtonStyle(
                    look: MinikPretty.PillLook.warm,
                    fontSize: metrics.buttonTextSize * textScale,
                    minHeight: metrics.buttonHeight
                ))
                LanguageIntroRemoveAdsButton(
                    commerce: commerceController,
                    fontSize: metrics.removeAdsTextSize * textScale,
                    minHeight: metrics.removeAdsHeight,
                    showsPurchaseOutcome: removeAdsWasRequested,
                    onRemoveAds: { removeAdsGateIsPresented = true }
                )
            }
            .frame(maxWidth: metrics.introColumnMaxWidth)
            .padding(.horizontal, metrics.introContentMargin)
            if fillsHeight {
                Spacer(minLength: 0)
            }
        }
        .padding(.top, metrics.introTitleTop)
        .padding(.bottom, metrics.introContentBottom)
        .frame(maxWidth: .infinity)
    }

    /// Dynamic Type for the intro's text, within what its fixed layout holds.
    private var textScale: CGFloat {
        min(1.3, max(0.9, textPercent / 100))
    }

    /// Android's child spinner: the chosen child's points and progress replace
    /// the previous child's.
    private func selectChild(_ id: UUID) {
        guard id != childProfiles.selectedChildID else { return }
        childProfiles.selectChild(id)
        onLearnerChanged()
    }

    private func presentChildDialog(_ request: ChildProfileDialogRequest) {
        withAnimation(.easeOut(duration: 0.2)) {
            childDialog = request
        }
    }

    private func closeChildDialog() {
        withAnimation(.easeOut(duration: 0.2)) {
            childDialog = nil
        }
    }
}

/// Android's removeAdsButton under Practice: a white pill with a lavender rim and
/// pretty_purple_text (bg_pretty_button_white). Here it opens the grown-up check
/// and then the App Store purchase the Parent Area offers. It is hidden once ads
/// are removed, or where this build sells no Remove Ads; after a purchase made
/// here it shows the outcome instead of Android's toast.
private struct LanguageIntroRemoveAdsButton: View {
    @ObservedObject var commerce: MinikCommerceController
    let fontSize: CGFloat
    let minHeight: CGFloat
    let showsPurchaseOutcome: Bool
    let onRemoveAds: () -> Void
    @Environment(\.interfaceLocaleID) private var interfaceLocaleID

    /// bg_pretty_button_white: a white face, the #CDBDFB rim and a soft #223A2C7A lip.
    private static let look = MinikPretty.PillLook(
        top: Color.white,
        bottom: MinikPretty.color(0xFBF9FF),
        lip: MinikPretty.shadowInk.opacity(0.13),
        rim: MinikPretty.lavenderRim,
        ink: MinikPretty.color(0x6A55D6),
        inkShadow: Color.clear
    )

    init(
        commerce: MinikCommerceController,
        fontSize: CGFloat,
        minHeight: CGFloat,
        showsPurchaseOutcome: Bool,
        onRemoveAds: @escaping () -> Void
    ) {
        self.commerce = commerce
        self.fontSize = fontSize
        self.minHeight = minHeight
        self.showsPurchaseOutcome = showsPurchaseOutcome
        self.onRemoveAds = onRemoveAds
    }

    var body: some View {
        if commerce.isRemoveAdsActive {
            if showsPurchaseOutcome {
                Label {
                    Text(verbatim: interfaceLocaleID.text("Ads removed"))
                } icon: {
                    Image(systemName: "checkmark.seal.fill")
                }
                .font(MinikPretty.titleFont(fontSize))
                .foregroundStyle(MinikPretty.color(0x1F8A5B))
                .frame(maxWidth: .infinity, minHeight: minHeight)
                .accessibilityElement(children: .combine)
            }
        } else if commerce.configuration.removeAdsProductID != nil {
            VStack(spacing: 6) {
                Button(action: onRemoveAds) {
                    Text(verbatim: interfaceLocaleID.text("Remove Ads"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(MinikPretty.HeroButtonStyle(
                    look: Self.look,
                    fontSize: fontSize,
                    minHeight: minHeight
                ))
                .disabled(isPurchasing)
                .accessibilityHint(Text(verbatim: interfaceLocaleID.text("Opens a grown-up check before contacting the App Store")))
                if showsPurchaseOutcome, let outcome = purchaseOutcome {
                    Text(verbatim: outcome)
                        .font(MinikPretty.bodyFont(max(13, fontSize * 0.75)))
                        .foregroundStyle(commerce.status == .failed ? MinikPretty.color(0xC2416E) : MinikPretty.softInk)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var isPurchasing: Bool {
        commerce.status == .purchasing || commerce.status == .restoring
    }

    /// The Parent Area's purchase messages, in the interface language.
    private var purchaseOutcome: String? {
        switch commerce.status {
        case .purchasing:
            return interfaceLocaleID.text("Contacting the App Store…")
        case .pending:
            return interfaceLocaleID.text("Purchase approval is pending.")
        case .cancelled:
            return interfaceLocaleID.text("Purchase cancelled.")
        case .failed:
            return interfaceLocaleID.text("The App Store request could not be completed.")
        case .unconfigured, .loading, .ready, .restoring:
            return nil
        }
    }
}

/// IntroScreen's score tiles on the sky: Points on lavender, Best Streak on soft
/// yellow with the trophy, both with a white rim.
private struct LanguagePrettyStatTile: View {
    enum Kind {
        case points
        case streak
    }

    let kind: Kind
    let title: String
    let value: Int64
    let metrics: LanguagePrettyMetrics

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 3) {
                if kind == .streak {
                    MinikArtworkImage(name: MinikVisualAsset.trophy)
                        .frame(width: metrics.statTrophy, height: metrics.statTrophy)
                }
                Text(title)
                    .font(MinikPretty.titleFont(metrics.statTitleSize))
                    .foregroundStyle(kind == .points ? MinikPretty.color(0x6A55D6) : MinikPretty.color(0x8A6418))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
            }
            Text(value, format: .number)
                .font(MinikPretty.titleFont(metrics.statValueSize))
                .foregroundStyle(kind == .points ? MinikPretty.color(0x4A36C8) : MinikPretty.color(0xA86400))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .frame(width: kind == .points ? metrics.statWidth : metrics.statStreakWidth, height: metrics.statHeight)
        .background(
            kind == .points ? MinikPretty.lavender : MinikPretty.color(0xFFF4CF),
            in: RoundedRectangle(cornerRadius: metrics.statRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: metrics.statRadius, style: .continuous)
                .strokeBorder(Color.white, lineWidth: 2)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Android's Plus activity menu (fragment_select_screen_plus.xml and
/// ButtonsMenuFragment) in the rainbow-sky design: the logo with the round Home and
/// Trophy buttons on the sky, and below them a glass panel whose board scrolls
/// through Letters, Words and Games: a colored section pill each, then pastel cards
/// in pairs, each with a Minik cat and a white name strip, Flash Cards alone and
/// centred under the Words. The Trophy opens the Top 20 as a dialog over the menu,
/// as Android does.
struct LanguageMenuView: View {
    let configuration: ProductConfiguration
    let learnedLanguage: LanguageIdentifier
    let onSelect: (LanguageActivityKind) -> Void
    let onHome: () -> Void
    @Environment(\.interfaceLocaleID) private var interfaceLocaleID
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Android's sp text follows the font-size setting; these follow Dynamic Type.
    @ScaledMetric(relativeTo: .headline) private var captionPercent: CGFloat = 100
    @ScaledMetric(relativeTo: .callout) private var hintPercent: CGFloat = 100
    @StateObject private var speechPlayer = InterfaceSpeechPlayer()
    @State private var scrollTracker = LanguageMenuScrollTracker()
    @State private var didRegisterPresentation = false
    @State private var scrollHintEligible = false
    @State private var contentContinuesBelow = false
    @State private var scrollHintOffset: CGFloat = 0
    @State private var skipsNextHintDip = false
    @State private var recordsArePresented = false

    init(
        configuration: ProductConfiguration,
        learnedLanguage: LanguageIdentifier,
        onSelect: @escaping (LanguageActivityKind) -> Void,
        onHome: @escaping () -> Void
    ) {
        self.configuration = configuration
        self.learnedLanguage = learnedLanguage
        self.onSelect = onSelect
        self.onHome = onHome
    }

    var body: some View {
        GeometryReader { geometry in
            let metrics = LanguagePrettyMetrics(size: geometry.size)
            let panelWidth = max(1, min(metrics.panelMaxWidth, geometry.size.width - 2 * metrics.panelMargin))
            let contentWidth = max(1, panelWidth - 2 * metrics.panelPadding)
            // Accessibility text on a phone gets one column, so captions wrap
            // between words rather than letter by letter.
            let sections = menuSections(singleColumn: dynamicTypeSize.isAccessibilitySize && !metrics.tablet)
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    header(metrics)
                    MinikGlassPanel(padding: 0, cornerRadius: metrics.panelRadius) {
                        board(metrics: metrics, contentWidth: contentWidth, sections: sections, proxy: proxy)
                            .clipShape(RoundedRectangle(cornerRadius: metrics.panelRadius, style: .continuous))
                    }
                    .frame(width: panelWidth)
                    .frame(maxHeight: .infinity)
                    .padding(.top, metrics.panelTopMargin)
                    .padding(.bottom, metrics.panelBottomMargin)
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                .onAppear {
                    registerPresentation(using: proxy)
                }
                .onChange(of: contentContinuesBelow) { _, continues in
                    applyStoreScreenshotScroll(continues: continues, using: proxy)
                }
            }
        }
        // A background never sizes the layout (see LanguageActivityScreen).
        .background {
            MinikSkyBackground()
        }
        .overlay {
            if recordsArePresented {
                LanguageRecordsDialog(product: configuration.variant) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        recordsArePresented = false
                    }
                }
                .transition(.opacity)
            }
        }
        .onDisappear {
            speechPlayer.stop()
            rememberPlace()
        }
        .task(id: showsScrollHint) {
            guard showsScrollHint else { return }
            // Back from a dialog the hint is still the one that was showing; on
            // Android it dips only when it appears.
            if skipsNextHintDip {
                skipsNextHintDip = false
                return
            }
            guard !reduceMotion else { return }
            // startScrollHintAnimation: three dips of 7 dp, 650 ms each.
            do {
                for _ in 0..<3 {
                    withAnimation(.easeInOut(duration: 0.325)) { scrollHintOffset = 7 }
                    try await Task.sleep(nanoseconds: 325_000_000)
                    withAnimation(.easeInOut(duration: 0.325)) { scrollHintOffset = 0 }
                    try await Task.sleep(nanoseconds: 325_000_000)
                }
            } catch {
                scrollHintOffset = 0
            }
        }
    }

    private var showsScrollHint: Bool {
        scrollHintEligible && contentContinuesBelow
    }

    /// The logo at the start; Home and Trophy as white round buttons centred in the
    /// space beside it (plusMenuTopButtons).
    private func header(_ metrics: LanguagePrettyMetrics) -> some View {
        HStack(alignment: .center, spacing: 0) {
            MinikLanguageLogo()
                .frame(width: metrics.logoWidth, height: metrics.logoHeight)
            Spacer(minLength: metrics.roundButtonGap)
            HStack(spacing: metrics.roundButtonGap) {
                roundButton(
                    imageName: MinikVisualAsset.home,
                    padding: metrics.homePadding,
                    label: interfaceLocaleID.text("Home"),
                    metrics: metrics
                ) {
                    // Home goes to the Intro, whose Practice opens a new menu.
                    scrollTracker.leavesForNewMenu = true
                    onHome()
                }
                roundButton(
                    imageName: MinikVisualAsset.trophy,
                    padding: metrics.trophyPadding,
                    label: interfaceLocaleID.text("Top 20 records"),
                    metrics: metrics
                ) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        recordsArePresented = true
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, metrics.screenMargin)
        .padding(.top, metrics.topMargin)
    }

    /// bg_round_button_white with the art inside it.
    private func roundButton(
        imageName: String,
        padding: CGFloat,
        label: String,
        metrics: LanguagePrettyMetrics,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            MinikArtworkImage(name: imageName)
                .padding(padding)
                .frame(width: metrics.roundButton, height: metrics.roundButton)
                .background {
                    MinikPretty.RoundButtonBackground()
                }
                .contentShape(Circle())
        }
        .buttonStyle(MinikPretty.PressScaleStyle())
        .accessibilityLabel(Text(label))
    }

    private func board(
        metrics: LanguagePrettyMetrics,
        contentWidth: CGFloat,
        sections: [LanguageMenuSection],
        proxy: ScrollViewProxy
    ) -> some View {
        VStack(spacing: 0) {
            // The board scrolls below the logo row, which stays in place.
            ScrollView {
                menuContent(metrics: metrics, contentWidth: contentWidth, sections: sections)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            .background {
                LanguageMenuPositionProbe { rect in
                    scrollTracker.viewport = rect
                    returnToPlace(using: proxy)
                    refreshScrollContinuation()
                }
            }
            // Like Android's scrollDownHint, the hint takes its own space at the
            // bottom of the panel rather than covering the board.
            if showsScrollHint {
                scrollHint(metrics) {
                    scrollFurther(sections: sections, using: proxy)
                }
                .padding(.horizontal, metrics.hintSideMargin)
                .padding(.top, 6)
                .padding(.bottom, metrics.hintBottomMargin)
            }
        }
    }

    private func menuContent(
        metrics: LanguagePrettyMetrics,
        contentWidth: CGFloat,
        sections: [LanguageMenuSection]
    ) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                ForEach(sections) { section in
                    sectionView(section, metrics: metrics, contentWidth: contentWidth)
                        .padding(.top, section.isFirst ? 0 : metrics.sectionTopGap)
                }
            }
            .padding(.horizontal, metrics.panelPadding)
            .padding(.top, metrics.panelPaddingTop)
            .padding(.bottom, metrics.panelPaddingBottom)
            // The end of the board: once it is in view, Android's
            // canScrollVertically(1) is false and the hint goes away.
            Color.clear
                .frame(height: 1)
                .id(LanguageMenuScrollID.end)
                .background {
                    LanguageMenuPositionProbe { rect in
                        scrollTracker.endMinY = rect.minY
                        refreshScrollContinuation()
                    }
                }
        }
    }

    private func sectionView(
        _ section: LanguageMenuSection,
        metrics: LanguagePrettyMetrics,
        contentWidth: CGFloat
    ) -> some View {
        VStack(spacing: 0) {
            MinikPretty.SectionBanner(
                title: section.title,
                look: sectionLook(section.id),
                icon: MinikPretty.SectionBanner.Icon.art(sectionIconName(section.id)),
                tablet: metrics.tablet,
                scale: metrics.scale
            )
            .padding(.bottom, metrics.sectionGap)
            .id(section.titleScrollID)
            .background { scrollTargetProbe(section.titleScrollID) }
            ForEach(section.rows) { row in
                rowView(row, metrics: metrics, contentWidth: contentWidth)
                    .padding(.top, row.isFirst ? 0 : metrics.cardRowGap)
                    .id(row.id)
                    .background { scrollTargetProbe(row.id) }
            }
        }
    }

    private func scrollTargetProbe(_ id: String) -> some View {
        LanguageMenuPositionProbe { rect in
            scrollTracker.targetMinY[id] = rect.minY
            scrollTracker.targetHeight[id] = rect.height
        }
    }

    @ViewBuilder
    private func rowView(
        _ row: LanguageMenuRow,
        metrics: LanguagePrettyMetrics,
        contentWidth: CGFloat
    ) -> some View {
        if row.activities.count > 1 {
            // Two weighted cards 12 dp (18 dp) apart, as tall as the taller of them.
            HStack(alignment: .top, spacing: metrics.cardGap) {
                ForEach(row.activities) { activity in
                    tile(activity, metrics: metrics)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        } else if let activity = row.activities.first {
            // Flash Cards alone, a column wide and centred; accessibility text on a
            // phone gives every card the whole width.
            tile(activity, metrics: metrics)
                .frame(width: row.fullWidth ? contentWidth : columnWidth(metrics, contentWidth: contentWidth))
                .frame(maxWidth: .infinity)
        }
    }

    /// One menu card: the pastel card with the cat art and the white name strip,
    /// the whole card tappable as Android's transparent MaterialButton over it.
    private func tile(_ activity: LanguageActivityKind, metrics: LanguagePrettyMetrics) -> some View {
        let title = menuCaption(for: activity)
        return Button {
            scrollTracker.leavesForNewMenu = !Self.opensOverMenu(activity)
            onSelect(activity)
        } label: {
            VStack(spacing: metrics.cardLabelGap) {
                tileArtwork(activity, metrics: metrics)
                Text(title)
                    .font(MinikPretty.titleFont(captionFontSize(metrics)))
                    .foregroundStyle(MinikPretty.navy)
                    .multilineTextAlignment(.center)
                    .lineSpacing(1)
                    .minimumScaleFactor(0.75)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, minHeight: metrics.cardLabelMinHeight, maxHeight: .infinity)
                    .background {
                        RoundedRectangle(cornerRadius: metrics.cardLabelRadius, style: .continuous)
                            .fill(Color.white.opacity(0.94))
                    }
            }
            .padding(.horizontal, metrics.cardPadding)
            .padding(.top, metrics.cardPadding)
            .padding(.bottom, metrics.cardPaddingBottom)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                MinikPretty.CardBackground(tint: cardTint(for: activity), cornerRadius: metrics.cardRadius)
            }
            .contentShape(RoundedRectangle(cornerRadius: metrics.cardRadius, style: .continuous))
        }
        .buttonStyle(MinikPretty.PressScaleStyle())
        .accessibilityLabel(Text(title.replacingOccurrences(of: "\n", with: " ")))
    }

    @ViewBuilder
    private func tileArtwork(_ activity: LanguageActivityKind, metrics: LanguagePrettyMetrics) -> some View {
        if let name = menuArtworkName(for: activity) {
            MinikArtworkImage(name: name)
                .frame(maxWidth: .infinity)
                .frame(height: metrics.cardArtHeight)
        } else {
            Color.clear
                .frame(height: metrics.cardArtHeight)
        }
    }

    /// ButtonsMenuFragment (pretty design): the pastel Minik cats; the Letters art
    /// follows the learned language.
    private func menuArtworkName(for activity: LanguageActivityKind) -> String? {
        let english = learnedLanguage == .english
        switch activity {
        case .learn:
            return english ? MinikPretty.Art.catAbcBook : MinikPretty.Art.catHebrewBook
        case .letterPairs:
            return MinikPretty.Art.pairs
        case .firstLetterChoices:
            return english ? MinikPretty.Art.firstLetterChoicesEnglish : MinikPretty.Art.firstLetterChoicesHebrew
        case .firstLetterPictures:
            return english ? MinikPretty.Art.firstLetterPicturesEnglish : MinikPretty.Art.firstLetterPicturesHebrew
        case .imageToWord:
            return MinikPretty.Art.catPencil
        case .wordToImage:
            return MinikPretty.Art.pictureAnswers
        case .wordBuild:
            return MinikPretty.Art.catBlocks
        case .mixed:
            return MinikPretty.Art.catStarPaper
        case .wordCards:
            return MinikPretty.Art.flashCards
        case .soccer:
            return MinikPretty.Art.soccer
        case .tower:
            return MinikPretty.Art.tower
        case .wordMemory:
            return MinikPretty.Art.memory
        case .ticTacToe:
            return MinikPretty.Art.ticTacToe
        case .multipleChoice, .build, .pairs, .memory:
            return MinikVisualAsset.activityArtwork(for: activity, language: learnedLanguage)
        }
    }

    /// fragment_select_screen_plus.xml's card colors (bg_menu_card_*).
    private func cardTint(for activity: LanguageActivityKind) -> MinikPretty.CardTint {
        switch activity {
        case .learn, .wordToImage:
            return .pink
        case .letterPairs, .wordBuild, .tower:
            return .mint
        case .firstLetterChoices, .mixed:
            return .yellow
        case .firstLetterPictures, .wordCards, .ticTacToe:
            return .blue
        case .imageToWord, .wordMemory:
            return .lavender
        case .soccer:
            return .peach
        case .multipleChoice, .build, .pairs, .memory:
            return .lavender
        }
    }

    /// bg_section_pill_letters, _words and _games.
    private func sectionLook(_ id: String) -> MinikPretty.PillLook {
        switch id {
        case "letters": return MinikPretty.PillLook.bannerPurple
        case "words": return MinikPretty.PillLook.bannerBlue
        default: return MinikPretty.PillLook.bannerWarm
        }
    }

    /// lettersSectionIcon follows the learned language (ABC or alef-bet).
    private func sectionIconName(_ id: String) -> String {
        switch id {
        case "letters":
            return learnedLanguage == .english ? MinikPretty.Art.iconAbc : MinikPretty.Art.iconAlefBet
        case "words":
            return MinikPretty.Art.iconBook
        default:
            return MinikPretty.Art.iconGames
        }
    }

    private func menuCaption(for activity: LanguageActivityKind) -> String {
        LanguageMenuAndroidText.caption(activity, locale: interfaceLocaleID)
            ?? interfaceLocaleID.text(activity.titleKey)
    }

    private func columnWidth(_ metrics: LanguagePrettyMetrics, contentWidth: CGFloat) -> CGFloat {
        max(1, (contentWidth - metrics.cardGap) / 2)
    }

    private func captionFontSize(_ metrics: LanguagePrettyMetrics) -> CGFloat {
        metrics.cardLabelTextSize * captionPercent / 100
    }

    private func hintFontSize(_ metrics: LanguagePrettyMetrics) -> CGFloat {
        metrics.hintTextSize * hintPercent / 100
    }

    /// Android's scrollDownHint in the pretty design: a purple pill with a white rim,
    /// white Fredoka text and a down chevron after it, shown the first three times
    /// the menu opens while more of the board lies below.
    private func scrollHint(_ metrics: LanguagePrettyMetrics, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: metrics.hintIconGap) {
                Text(LanguageMenuAndroidText.scrollHint(interfaceLocaleID))
                    .font(MinikPretty.titleFont(hintFontSize(metrics)))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                LanguageMenuChevron()
                    .fill(Color.white)
                    .frame(width: metrics.hintIconSize, height: metrics.hintIconSize)
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, metrics.hintHorizontalPadding)
            .frame(minHeight: metrics.hintHeight)
            .background(MinikPretty.purple, in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(Color.white, lineWidth: 2)
            }
            .shadow(color: MinikPretty.shadowInk.opacity(0.25), radius: 3, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .offset(y: scrollHintOffset)
        .accessibilityLabel(Text(LanguageMenuAndroidText.scrollHintAccessibility(interfaceLocaleID)))
    }

    /// Android scrolls 72% of the board's height per tap. Here the furthest row
    /// that starts within that distance moves to the top, so nothing is skipped.
    private func scrollFurther(sections: [LanguageMenuSection], using proxy: ScrollViewProxy) {
        let viewport = scrollTracker.viewport
        let distance = viewport.height * 0.72
        var target: String?
        var anchor = UnitPoint.top
        for id in sections.flatMap(\.scrollTargetIDs) {
            guard let minY = scrollTracker.targetMinY[id] else { continue }
            let distanceFromTop = minY - viewport.minY
            if distanceFromTop <= 1 { continue }
            if distanceFromTop <= distance {
                target = id
                continue
            }
            if target == nil {
                target = id
                anchor = distanceFromTop <= viewport.height ? .top : .bottom
            }
            break
        }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.4)) {
            if let target {
                proxy.scrollTo(target, anchor: anchor)
            } else {
                proxy.scrollTo(LanguageMenuScrollID.end, anchor: .bottom)
            }
        }
    }

    private func refreshScrollContinuation() {
        let viewport = scrollTracker.viewport
        guard viewport.height > 0 else { return }
        let continues = scrollTracker.endMinY > viewport.maxY + 1
        if continues != contentContinuesBelow {
            contentContinuesBelow = continues
        }
    }

    /// The parity capture scene "menu.games" opens the menu scrolled to its end,
    /// as Android's second menu reference shows it.
    private func applyStoreScreenshotScroll(continues: Bool, using proxy: ScrollViewProxy) {
        guard continues,
              !scrollTracker.didApplyStoreScreenshotScroll,
              StoreScreenshotScene.name == "menu.games" else { return }
        scrollTracker.didApplyStoreScreenshotScroll = true
        proxy.scrollTo(LanguageMenuScrollID.end, anchor: .bottom)
    }

    private func registerPresentation(using proxy: ScrollViewProxy) {
        guard !didRegisterPresentation else { return }
        didRegisterPresentation = true
        // App Store and parity captures show the menu as Android's references do.
        guard StoreScreenshotScene.name == nil else { return }
        if let place = LanguageMenuSession.returnPlace {
            // Back from an activity Android shows as a dialog over the menu: the
            // board is where it was, and the hint keeps its state rather than
            // counting another showing (setupScrollDownHint does not run again).
            LanguageMenuSession.returnPlace = nil
            scrollHintEligible = place.hintEligible
            skipsNextHintDip = place.hintShowing
            scrollTracker.pendingPlace = place
            returnToPlace(using: proxy)
            return
        }
        scrollHintEligible = LanguageMenuScrollHintRepository().registerPresentationIfNeeded()
        // ButtonsMenuFragment says select_screen_voice the first time the menu
        // appears while the app runs.
        if !LanguageMenuSession.hasSpokenPrompt {
            LanguageMenuSession.hasSpokenPrompt = true
            let prompt = LanguageMenuAndroidText.selectScreenVoice(interfaceLocaleID)
            speechPlayer.speak(interfaceLocaleID.spokenText(for: prompt), interfaceLocale: interfaceLocaleID)
        }
    }

    /// Android opens Pairs, Flash Cards and the four games as dialogs over the
    /// menu (ButtonsMenuFragment), so closing one shows the menu as it was. Here
    /// they replace the menu, so where it was is kept for the menu that comes
    /// back. Home, Learn and the WriteScreen activities come back to a new menu
    /// at the top, as Android's do.
    private func rememberPlace() {
        if scrollTracker.leavesForNewMenu {
            LanguageMenuSession.returnPlace = nil
        } else {
            // A place not yet restored is still the one to return to.
            LanguageMenuSession.returnPlace = scrollTracker.pendingPlace ?? currentPlace()
        }
    }

    /// The first target wholly in view and its distance below the board's top.
    private func currentPlace() -> LanguageMenuPlace {
        let viewport = scrollTracker.viewport
        var firstID: String?
        var firstMinY = CGFloat.greatestFiniteMagnitude
        for (id, minY) in scrollTracker.targetMinY where minY >= viewport.minY - 0.5 && minY < firstMinY {
            firstID = id
            firstMinY = minY
        }
        var offset: CGFloat = 0
        var firstHeight: CGFloat = 0
        if let firstID {
            offset = firstMinY - viewport.minY
            firstHeight = scrollTracker.targetHeight[firstID] ?? 0
        }
        return LanguageMenuPlace(
            targetID: viewport.height > 0 ? firstID : nil,
            offset: offset,
            targetHeight: firstHeight,
            hintEligible: scrollHintEligible,
            hintShowing: showsScrollHint
        )
    }

    /// Scrolls the remembered target back to the same distance below the
    /// board's top, once the board has been measured.
    private func returnToPlace(using proxy: ScrollViewProxy) {
        guard let place = scrollTracker.pendingPlace, scrollTracker.viewport.height > 0 else { return }
        scrollTracker.pendingPlace = nil
        guard let targetID = place.targetID else { return }
        let travel = scrollTracker.viewport.height - place.targetHeight
        let fraction: CGFloat = travel > 1 ? min(1, max(0, place.offset / travel)) : 0
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            proxy.scrollTo(targetID, anchor: UnitPoint(x: 0.5, y: fraction))
        }
    }

    /// ButtonsMenuFragment shows these as DialogFragments over the menu; the
    /// others replace it with LearnScreen or WriteScreen.
    private static func opensOverMenu(_ activity: LanguageActivityKind) -> Bool {
        switch activity {
        case .letterPairs, .wordCards, .soccer, .tower, .wordMemory, .ticTacToe:
            return true
        case .learn, .firstLetterChoices, .firstLetterPictures, .imageToWord, .wordToImage,
             .wordBuild, .mixed, .multipleChoice, .build, .pairs, .memory:
            return false
        }
    }

    private func menuSections(singleColumn: Bool) -> [LanguageMenuSection] {
        var sections: [LanguageMenuSection] = []
        for section in ActivityCatalog.languageSections(for: configuration) {
            sections.append(menuSection(section, isFirst: sections.isEmpty, singleColumn: singleColumn))
        }
        return sections
    }

    /// Android's rows: start-to-end pairs in the Plus layout's order, Flash Cards
    /// alone after the Words pairs.
    private func menuSection(
        _ section: ActivitySection<LanguageActivityKind>,
        isFirst: Bool,
        singleColumn: Bool
    ) -> LanguageMenuSection {
        let ordered = section.activities.sorted { Self.androidMenuOrder($0) < Self.androidMenuOrder($1) }
        let paired = ordered.filter { $0 != .wordCards }
        let perRow = singleColumn ? 1 : 2
        var rows: [LanguageMenuRow] = []
        var start = 0
        while start < paired.count {
            let end = min(start + perRow, paired.count)
            rows.append(LanguageMenuRow(
                id: section.id + "-" + String(rows.count),
                activities: Array(paired[start..<end]),
                isFirst: rows.isEmpty,
                fullWidth: singleColumn
            ))
            start = end
        }
        if ordered.contains(.wordCards) {
            rows.append(LanguageMenuRow(
                id: section.id + "-" + String(rows.count),
                activities: [.wordCards],
                isFirst: rows.isEmpty,
                fullWidth: singleColumn
            ))
        }
        return LanguageMenuSection(
            id: section.id,
            title: interfaceLocaleID.text(sectionTitleKey(section.id)),
            isFirst: isFirst,
            rows: rows
        )
    }

    private func sectionTitleKey(_ id: String) -> String.LocalizationValue {
        switch id {
        case "letters": return "Letters"
        case "words": return "Words"
        default: return "Games"
        }
    }

    /// fragment_select_screen_plus.xml from start to end, row by row.
    private static func androidMenuOrder(_ activity: LanguageActivityKind) -> Int {
        switch activity {
        case .learn: return 0
        case .letterPairs: return 1
        case .firstLetterChoices: return 2
        case .firstLetterPictures: return 3
        case .imageToWord: return 4
        case .wordToImage: return 5
        case .wordBuild: return 6
        case .mixed: return 7
        case .wordCards: return 8
        case .soccer: return 9
        case .tower: return 10
        case .wordMemory: return 11
        case .ticTacToe: return 12
        case .multipleChoice, .build, .pairs, .memory: return 13
        }
    }
}

/// dimens_pretty.xml in points: the phone values, and the values-sw600dp ones on
/// iPad (both sides at least 600 points). The iPad mini (744 points wide) uses the
/// tablet values as they are; larger iPads scale them up a little so the screens
/// keep their proportions instead of stretching.
private struct LanguagePrettyMetrics {
    let tablet: Bool
    let scale: CGFloat

    init(size: CGSize) {
        let isTablet = min(size.width, size.height) >= 600
        tablet = isTablet
        scale = isTablet ? min(1.3, max(1, size.width / 744)) : 1
    }

    private func value(_ phone: CGFloat, _ tabletValue: CGFloat) -> CGFloat {
        tablet ? tabletValue * scale : phone
    }

    // The logo row on the sky.
    var logoHeight: CGFloat { value(82, 120) }
    var logoWidth: CGFloat { logoHeight * MinikPretty.Art.languageLogoAspect }
    var screenMargin: CGFloat { value(14, 32) }
    var topMargin: CGFloat { value(6, 16) }
    var roundButton: CGFloat { value(58, 84) }
    var roundButtonGap: CGFloat { value(14, 22) }
    var homePadding: CGFloat { value(3, 4) }
    var trophyPadding: CGFloat { value(12, 17) }

    // The glass panel.
    var panelMargin: CGFloat { value(12, 32) }
    var panelTopMargin: CGFloat { value(6, 12) }
    var panelBottomMargin: CGFloat { value(10, 16) }
    var panelRadius: CGFloat { value(28, 36) }
    var panelMaxWidth: CGFloat { value(640, 820) }
    var panelPadding: CGFloat { value(12, 22) }
    var panelPaddingTop: CGFloat { value(14, 22) }
    var panelPaddingBottom: CGFloat { value(26, 34) }

    // The menu's sections and cards.
    var sectionGap: CGFloat { value(10, 14) }
    var sectionTopGap: CGFloat { value(20, 28) }
    var cardPadding: CGFloat { value(6, 10) }
    var cardPaddingBottom: CGFloat { value(9, 13) }
    var cardArtHeight: CGFloat { value(98, 160) }
    var cardLabelGap: CGFloat { value(4, 6) }
    var cardLabelMinHeight: CGFloat { value(44, 58) }
    var cardLabelTextSize: CGFloat { value(15, 20) }
    var cardLabelRadius: CGFloat { value(16, 18) }
    var cardRowGap: CGFloat { value(12, 18) }
    var cardGap: CGFloat { value(12, 18) }
    var cardRadius: CGFloat { value(22, 26) }

    // The "more below" hint (scrollDownHint).
    var hintHeight: CGFloat { value(50, 60) }
    var hintSideMargin: CGFloat { value(16, 24) }
    var hintBottomMargin: CGFloat { value(12, 16) }
    var hintHorizontalPadding: CGFloat { value(20, 24) }
    var hintTextSize: CGFloat { value(16, 20) }
    var hintIconSize: CGFloat { value(26, 30) }
    var hintIconGap: CGFloat { value(8, 10) }

    // The intro's score tiles.
    var statWidth: CGFloat { value(88, 128) }
    var statStreakWidth: CGFloat { value(100, 140) }
    var statHeight: CGFloat { value(62, 86) }
    var statGap: CGFloat { value(10, 20) }
    var statRadius: CGFloat { value(20, 22) }
    var statTitleSize: CGFloat { value(12, 18) }
    var statValueSize: CGFloat { value(18, 26) }
    var statTrophy: CGFloat { value(15, 24) }

    // The intro's panel.
    var introTitleTop: CGFloat { value(16, 30) }
    var introTitleSize: CGFloat { value(25, 36) }
    var welcomeMargin: CGFloat { value(12, 30) }
    var welcomeMaxWidth: CGFloat { value(460, 600) }
    var introContentMargin: CGFloat { value(22, 40) }
    var introColumnMaxWidth: CGFloat { value(520, 600) }
    var introSectionGap: CGFloat { value(12, 20) }
    var introContentBottom: CGFloat { value(22, 30) }
    var buttonHeight: CGFloat { value(68, 84) }
    var buttonGap: CGFloat { value(12, 20) }
    var buttonTextSize: CGFloat { value(28, 36) }
    // pretty_intro_remove_ads_height and pretty_intro_remove_ads_text.
    var removeAdsHeight: CGFloat { value(50, 60) }
    var removeAdsTextSize: CGFloat { value(18, 24) }
}

private struct LanguageMenuRow: Identifiable {
    let id: String
    let activities: [LanguageActivityKind]
    let isFirst: Bool
    /// Accessibility text on a phone: one tile per row across the board.
    let fullWidth: Bool
}

private struct LanguageMenuSection: Identifiable {
    let id: String
    let title: String
    let isFirst: Bool
    let rows: [LanguageMenuRow]

    var titleScrollID: String { "title-" + id }
    var scrollTargetIDs: [String] { [titleScrollID] + rows.map(\.id) }
}

private enum LanguageMenuScrollID {
    static let end = "language-menu-end"
}

private enum LanguageMenuSession {
    /// DeviceStatusManager.alreadySpokeSelectScreen: once while the app runs.
    static var hasSpokenPrompt = false
    /// Where the menu was when an activity Android shows over it replaced it.
    static var returnPlace: LanguageMenuPlace?
}

/// Where the board was: a section title or row, how far below the board's top
/// it was, and the "more below" hint's state.
private struct LanguageMenuPlace {
    let targetID: String?
    let offset: CGFloat
    let targetHeight: CGFloat
    let hintEligible: Bool
    let hintShowing: Bool
}

/// Where the menu's rows and its end are while it scrolls. A plain class, so
/// recording positions as the board moves does not redraw the menu.
private final class LanguageMenuScrollTracker {
    var viewport: CGRect = .zero
    var endMinY: CGFloat = 0
    var targetMinY: [String: CGFloat] = [:]
    var targetHeight: [String: CGFloat] = [:]
    var didApplyStoreScreenshotScroll = false
    /// Set when Home, Learn or a WriteScreen activity takes the child away:
    /// the menu that comes back is a new one, at the top.
    var leavesForNewMenu = false
    /// A place to return to, waiting for the board to be measured.
    var pendingPlace: LanguageMenuPlace?
}

/// Reports a view's frame in global coordinates when it appears and whenever
/// it moves, as scrolling does.
private struct LanguageMenuPositionProbe: View {
    let report: (CGRect) -> Void

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { report(proxy.frame(in: .global)) }
                .onChange(of: proxy.frame(in: .global)) { _, rect in
                    report(rect)
                }
        }
    }
}

/// Android's ic_arrow_down_rounded_24 (a filled down chevron) on its 24-unit grid.
private struct LanguageMenuChevron: Shape {
    func path(in rect: CGRect) -> Path {
        let unitX = rect.width / 24
        let unitY = rect.height / 24
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 7.41 * unitX, y: rect.minY + 8.59 * unitY))
        path.addLine(to: CGPoint(x: rect.minX + 12 * unitX, y: rect.minY + 13.17 * unitY))
        path.addLine(to: CGPoint(x: rect.minX + 16.59 * unitX, y: rect.minY + 8.59 * unitY))
        path.addLine(to: CGPoint(x: rect.minX + 18 * unitX, y: rect.minY + 10 * unitY))
        path.addLine(to: CGPoint(x: rect.minX + 12 * unitX, y: rect.minY + 16 * unitY))
        path.addLine(to: CGPoint(x: rect.minX + 6 * unitX, y: rect.minY + 10 * unitY))
        path.closeSubpath()
        return path
    }
}

/// ButtonsMenuFragment.setupScrollDownHint: the hint is offered the first three
/// times the menu opens.
struct LanguageMenuScrollHintRepository {
    static let maximumPresentationCount = 3

    private let userDefaults: UserDefaults
    private let storageKey: String

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = "minik.languageMenu.scrollHintPresentationCount.v1"
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
    }

    @discardableResult
    func registerPresentationIfNeeded() -> Bool {
        let presentationCount = max(0, userDefaults.integer(forKey: storageKey))
        guard presentationCount < Self.maximumPresentationCount else {
            return false
        }

        userDefaults.set(presentationCount + 1, forKey: storageKey)
        return true
    }
}

/// Android's Plus menu text (values*/strings.xml) in every interface language,
/// with Android's line breaks. The String Catalog's activity titles keep serving
/// the other screens; these strings have no catalog entries.
enum LanguageMenuAndroidText {
    static func caption(_ activity: LanguageActivityKind, locale: InterfaceLocaleID) -> String? {
        captions(locale)[activity]
    }

    static func scrollHint(_ locale: InterfaceLocaleID) -> String {
        switch locale {
        case .english: return "There’s more below — scroll down"
        case .amharic: return "ከታች ተጨማሪ አለ — ወደ ታች ያሸብልሉ"
        case .arabic: return "هناك المزيد في الأسفل — مرّر إلى الأسفل"
        case .german: return "Unten gibt es noch mehr — scrolle nach unten"
        case .spanish: return "Hay más abajo — baja para ver más"
        case .french: return "Il y en a d'autres plus bas — fais défiler vers le bas"
        case .hebrew: return "יש עוד למטה — גללו מטה"
        case .dutch: return "Hieronder staat nog meer — scrol omlaag"
        case .portugueseBrazil: return "Tem mais lá embaixo — role para baixo"
        case .portuguesePortugal: return "Há mais em baixo — desce para ver mais"
        case .russian: return "Ниже есть ещё — прокрути вниз"
        }
    }

    static func scrollHintAccessibility(_ locale: InterfaceLocaleID) -> String {
        switch locale {
        case .english: return "There are more below. Tap to continue."
        case .amharic: return "ከታች ተጨማሪ አለ። ለመቀጠል ይንኩ።"
        case .arabic: return "هناك المزيد في الأسفل. اضغط للمتابعة."
        case .german: return "Unten gibt es noch mehr. Tippe, um weiterzumachen."
        case .spanish: return "Hay más abajo. Toca para continuar."
        case .french: return "Il y en a d'autres plus bas. Appuie pour continuer."
        case .hebrew: return "יש עוד למטה. הקישו כדי להמשיך."
        case .dutch: return "Hieronder staat nog meer. Tik om verder te gaan."
        case .portugueseBrazil: return "Tem mais lá embaixo. Toque para continuar."
        case .portuguesePortugal: return "Há mais em baixo. Toca para continuar."
        case .russian: return "Ниже есть ещё. Нажми, чтобы продолжить."
        }
    }

    static func selectScreenVoice(_ locale: InterfaceLocaleID) -> String {
        switch locale {
        case .english: return "Choose an activity to start"
        case .amharic: return "ለመጀመር እንቅስቃሴ ይምረጡ"
        case .arabic: return "اختر نشاطًا للبدء"
        case .german: return "Wählt eine Aktivität, um zu starten"
        case .spanish: return "Elige una actividad para empezar"
        case .french: return "Choisis une activité pour commencer"
        case .hebrew: return "בחרו תרגול כדי להתחיל"
        case .dutch: return "Kies een activiteit om te beginnen"
        case .portugueseBrazil: return "Escolha uma atividade para começar"
        case .portuguesePortugal: return "Escolhe uma atividade para começar"
        case .russian: return "Выбери занятие, чтобы начать"
        }
    }

    private static func captions(_ locale: InterfaceLocaleID) -> [LanguageActivityKind: String] {
        switch locale {
        case .english: return englishCaptions
        case .amharic: return amharicCaptions
        case .arabic: return arabicCaptions
        case .german: return germanCaptions
        case .spanish: return spanishCaptions
        case .french: return frenchCaptions
        case .hebrew: return hebrewCaptions
        case .dutch: return dutchCaptions
        case .portugueseBrazil: return portugueseBrazilCaptions
        case .portuguesePortugal: return portuguesePortugalCaptions
        case .russian: return russianCaptions
        }
    }

    private static let englishCaptions: [LanguageActivityKind: String] = [
        .learn: "Practice",
        .letterPairs: "Pairs",
        .firstLetterChoices: "First Letter\nChoices",
        .firstLetterPictures: "First Letter\nPictures",
        .imageToWord: "Answers\nwith Words",
        .wordToImage: "Answers\nwith Pictures",
        .wordBuild: "Build\nwith Letters",
        .mixed: "Mixed\npractice",
        .wordCards: "Flash\nCards",
        .soccer: "Letter\nSoccer",
        .tower: "Letter\nTower",
        .wordMemory: "Word\nMemory",
        .ticTacToe: "Tic\nTac Toe"
    ]

    private static let amharicCaptions: [LanguageActivityKind: String] = [
        .learn: "ልምምድ",
        .letterPairs: "ጥንዶች",
        .firstLetterChoices: "የመጀመሪያ ፊደል\nምርጫዎች",
        .firstLetterPictures: "የመጀመሪያ ፊደል\nምስሎች",
        .imageToWord: "መልሶች\nበቃል",
        .wordToImage: "መልሶች\nበምስል",
        .wordBuild: "ቃል\nበፊደላት ይገንቡ",
        .mixed: "የተቀላቀለ ልምምድ",
        .wordCards: "የመማሪያ ካርዶች",
        .soccer: "ፊደል\nእግር ኳስ",
        .tower: "የፊደል\nማማ",
        .wordMemory: "የቃል\nማስታወሻ",
        .ticTacToe: "ቲክ\nታክ ቶ"
    ]

    private static let arabicCaptions: [LanguageActivityKind: String] = [
        .learn: "تدرّب",
        .letterPairs: "الأزواج",
        .firstLetterChoices: "الحرف الأول\nخيارات",
        .firstLetterPictures: "الحرف الأول\nصور",
        .imageToWord: "إجابات\nبالكلمات",
        .wordToImage: "إجابات\nبالصور",
        .wordBuild: "بناء\nبالحروف",
        .mixed: "تدريب\nمتنوع",
        .wordCards: "بطاقات تعليمية",
        .soccer: "كرة قدم\nالحروف",
        .tower: "برج\nالحروف",
        .wordMemory: "ذاكرة\nالكلمات",
        .ticTacToe: "إكس\nدائرة"
    ]

    private static let germanCaptions: [LanguageActivityKind: String] = [
        .learn: "Üben",
        .letterPairs: "Paare",
        .firstLetterChoices: "Anfangsbuchstabe\nAuswahl",
        .firstLetterPictures: "Anfangsbuchstabe\nBilder",
        .imageToWord: "Antworten\nmit Wörtern",
        .wordToImage: "Antworten\nmit Bildern",
        .wordBuild: "Bauen\nmit Buchstaben",
        .mixed: "Gemischte Übungen",
        .wordCards: "Lernkarten",
        .soccer: "Buchstaben\nFußball",
        .tower: "Buchstaben\nTurm",
        .wordMemory: "Wort-\nMemory",
        .ticTacToe: "Drei\ngewinnt"
    ]

    private static let spanishCaptions: [LanguageActivityKind: String] = [
        .learn: "Practicar",
        .letterPairs: "Parejas",
        .firstLetterChoices: "Primera letra\nOpciones",
        .firstLetterPictures: "Primera letra\nImágenes",
        .imageToWord: "Respuestas\ncon palabras",
        .wordToImage: "Respuestas\ncon imágenes",
        .wordBuild: "Construir\ncon letras",
        .mixed: "Práctica\nmixta",
        .wordCards: "Tarjetas didácticas",
        .soccer: "Fútbol\nde letras",
        .tower: "Torre\nde letras",
        .wordMemory: "Memoria\nde palabras",
        .ticTacToe: "Tres\nen raya"
    ]

    private static let frenchCaptions: [LanguageActivityKind: String] = [
        .learn: "S'entraîner",
        .letterPairs: "Paires",
        .firstLetterChoices: "Première lettre\nChoix",
        .firstLetterPictures: "Première lettre\nImages",
        .imageToWord: "Réponses\navec mots",
        .wordToImage: "Réponses\navec images",
        .wordBuild: "Construire\navec lettres",
        .mixed: "Exercices mixtes",
        .wordCards: "Cartes mémo",
        .soccer: "Football\ndes lettres",
        .tower: "Tour\nde lettres",
        .wordMemory: "Mémoire\nde mots",
        .ticTacToe: "Morpion"
    ]

    private static let hebrewCaptions: [LanguageActivityKind: String] = [
        .learn: "חזרה",
        .letterPairs: "זוגות",
        .firstLetterChoices: "אות ראשונה\nאפשרויות",
        .firstLetterPictures: "אות ראשונה\nתמונות",
        .imageToWord: "תשובות\nבמילים",
        .wordToImage: "תשובות\nבתמונות",
        .wordBuild: "תשובות בהרכבת\nאותיות",
        .mixed: "תרגול משולב\nלפי רמה",
        .wordCards: "כרטיסיות",
        .soccer: "כדורגל\nאותיות",
        .tower: "מגדל\nאותיות",
        .wordMemory: "זיכרון\nמילים",
        .ticTacToe: "איקס\nעיגול"
    ]

    private static let dutchCaptions: [LanguageActivityKind: String] = [
        .learn: "Oefenen",
        .letterPairs: "Paren",
        .firstLetterChoices: "Eerste letter\nKeuzes",
        .firstLetterPictures: "Eerste letter\nAfbeeldingen",
        .imageToWord: "Antwoorden\nmet woorden",
        .wordToImage: "Antwoorden\nmet afbeeldingen",
        .wordBuild: "Bouwen\nmet letters",
        .mixed: "Gemengde oefening",
        .wordCards: "Oefenkaartjes",
        .soccer: "Letter\nvoetbal",
        .tower: "Letter\ntoren",
        .wordMemory: "Woorden\nMemory",
        .ticTacToe: "Boter\nkaas"
    ]

    private static let portugueseBrazilCaptions: [LanguageActivityKind: String] = [
        .learn: "Praticar",
        .letterPairs: "Pares",
        .firstLetterChoices: "Primeira letra\nOpções",
        .firstLetterPictures: "Primeira letra\nImagens",
        .imageToWord: "Respostas\ncom palavras",
        .wordToImage: "Respostas\ncom imagens",
        .wordBuild: "Montar\ncom letras",
        .mixed: "Prática\nmista",
        .wordCards: "Cartões de estudo",
        .soccer: "Futebol\nde letras",
        .tower: "Torre\nde letras",
        .wordMemory: "Memória\nde palavras",
        .ticTacToe: "Jogo\nda velha"
    ]

    private static let portuguesePortugalCaptions: [LanguageActivityKind: String] = [
        .learn: "Praticar",
        .letterPairs: "Pares",
        .firstLetterChoices: "Primeira letra\nOpções",
        .firstLetterPictures: "Primeira letra\nImagens",
        .imageToWord: "Respostas\ncom Palavras",
        .wordToImage: "Respostas\ncom Imagens",
        .wordBuild: "Construir\ncom letras",
        .mixed: "Prática\nmista",
        .wordCards: "Cartões de estudo",
        .soccer: "Futebol\nde letras",
        .tower: "Torre\nde letras",
        .wordMemory: "Memória\nde palavras",
        .ticTacToe: "Jogo\ndo galo"
    ]

    private static let russianCaptions: [LanguageActivityKind: String] = [
        .learn: "Тренировка",
        .letterPairs: "Пары",
        .firstLetterChoices: "Первая буква\nВарианты",
        .firstLetterPictures: "Первая буква\nКартинки",
        .imageToWord: "Ответы\nсловами",
        .wordToImage: "Ответы\nс картинками",
        .wordBuild: "Составление\nиз букв",
        .mixed: "Смешанные задания",
        .wordCards: "Карточки",
        .soccer: "Футбол\nс буквами",
        .tower: "Башня\nбукв",
        .wordMemory: "Слова\nна память",
        .ticTacToe: "Крестики\nнолики"
    ]
}

enum LanguagePalette {
    static let title = Color(red: 0.48, green: 0.25, blue: 0.72)
    static let teal = Color(red: 0.13, green: 0.72, blue: 0.75)
    /// Android's #203745: the menu's section titles, captions and hint.
    static let menuText = Color(red: 32 / 255, green: 55 / 255, blue: 69 / 255)
    /// Android's #FFF3C4 "more below" hint.
    static let scrollHintFill = Color(red: 1, green: 243 / 255, blue: 196 / 255)
    static let border = LinearGradient(
        colors: [Color(red: 0.52, green: 0.31, blue: 0.71),
                 Color(red: 0.94, green: 0.70, blue: 0.72),
                 Color(red: 0.24, green: 0.79, blue: 0.84)],
        startPoint: UnitPoint(x: 0, y: 0.5), endPoint: UnitPoint(x: 1, y: 0.5)
    )
}

/// The logo of the Intro, the menu and the activity screens: the MINIK+plus badge
/// (Android minik_logo_pretty_plus), and in English Only the former logo with its white
/// sticker outline (Android minik_logo_pretty). It fits whatever box it is given.
struct MinikLanguageLogo: View {
    var body: some View {
        MinikArtworkImage(name: MinikPretty.Art.languageLogo)
            .accessibilityHidden(true)
    }
}

/// Android's minik_plus_english_only, the "MINIK" wordmark English Only shows on
/// the Intro and the menu in place of minik_plus_logo (IntroScreen and
/// ButtonsMenuFragment). Until the shared catalog has the image, English Only
/// keeps the Plus wordmark.
enum LanguageEnglishOnlyLogoAsset {
    static let name = "minik_language_logo_english_only"
    /// logo_plus_english_margin_start, which replaces the Plus logo's margin.
    static let startMargin: CGFloat = -8
    static let isAvailable: Bool = UIImage(named: name) != nil

    static func isShown(for variant: ProductVariant) -> Bool {
        variant == .minikPlusEnglish && isAvailable
    }

    /// logo_plus_english_width x logo_plus_english_height, which the image fits
    /// centred: values-sw360dp-h640dp/h720dp/h800dp/h900dp-port on phones, by
    /// the height between the system bars, and values-sw700dp on tablets.
    static func box(screenHeight: CGFloat, tablet: Bool) -> CGSize {
        if tablet {
            return CGSize(width: 133, height: 90)
        }
        if screenHeight >= 900 {
            return CGSize(width: 103, height: 67)
        }
        if screenHeight >= 800 {
            return CGSize(width: 95, height: 61)
        }
        if screenHeight >= 720 {
            return CGSize(width: 87, height: 56)
        }
        return CGSize(width: 80, height: 48)
    }
}

struct LanguageEnglishOnlyLogo: View {
    var body: some View {
        MinikArtworkImage(name: LanguageEnglishOnlyLogoAsset.name)
            .accessibilityHidden(true)
    }
}

/// RecordsLeaderboardDialogFragment over the menu, which stays where it was
/// behind a 58% dim: 94% x 90% of the screen on phones (at most 560 x 760 dp)
/// and 92% x 88% on tablets (at most 1120 x 860 dp), the card 6 dp inside that
/// (10 dp on tablets) in the rainbow-sky design's bg_pretty_dialog: 28 dp continuous
/// corners and a 2 dp #E6DEFF rim, as the Levels and Parent dialogs.
/// A tap outside closes it. When the Top 20 opened by itself (RecordsAutoShowPolicy)
/// it offers "Don't show automatically", as Android's dialog does.
struct LanguageRecordsDialog: View {
    let product: ProductVariant
    let offersAutomaticOptOut: Bool
    let onClose: () -> Void

    init(product: ProductVariant, offersAutomaticOptOut: Bool = false, onClose: @escaping () -> Void) {
        self.product = product
        self.offersAutomaticOptOut = offersAutomaticOptOut
        self.onClose = onClose
    }

    private static let rim = Color(red: 230 / 255, green: 222 / 255, blue: 255 / 255)

    var body: some View {
        GeometryReader { geometry in
            let tablet = geometry.size.width >= 600
            let width = min(geometry.size.width * (tablet ? 0.92 : 0.94), tablet ? 1120 : 560)
            let height = min(geometry.size.height * (tablet ? 0.88 : 0.90), tablet ? 860 : 760)
            let card = RoundedRectangle(cornerRadius: 28, style: .continuous)
            ZStack {
                Color.black.opacity(0.58)
                    .ignoresSafeArea()
                    .onTapGesture(perform: onClose)
                    .accessibilityHidden(true)
                RecordsLeaderboardView(
                    product: product,
                    offersAutomaticOptOut: offersAutomaticOptOut,
                    onClose: onClose
                )
                    .clipShape(card)
                    .overlay {
                        card.strokeBorder(Self.rim, lineWidth: 2)
                    }
                    .padding(tablet ? 10 : 6)
                    .frame(width: width, height: height)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onClose)
    }
}

struct LanguageStatistic: View {
    let title: LocalizedStringKey
    let value: Int64

    var body: some View {
        VStack(spacing: 5) {
            Text(title).font(.caption.weight(.semibold))
            Text(value, format: .number).font(.title3.bold().monospacedDigit())
        }
        // Two badges share one row beside the logo: larger text shrinks onto
        // one line instead of wrapping letter by letter.
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .foregroundStyle(LanguagePalette.title)
        .frame(maxWidth: .infinity, minHeight: 62)
        .padding(.horizontal, 8)
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(LanguagePalette.border, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

struct LanguageOutlineActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title2.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .foregroundStyle(Color(red: 0.067, green: 0.067, blue: 0.067))
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(minHeight: 56)
            .background(.white, in: RoundedRectangle(cornerRadius: 13))
            .overlay {
                RoundedRectangle(cornerRadius: 13)
                    .strokeBorder(LanguagePalette.border, lineWidth: 2)
            }
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
