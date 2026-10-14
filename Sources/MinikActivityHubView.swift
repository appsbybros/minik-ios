import SwiftUI
import UIKit

struct MinikActivityHubView: View {
    private enum Route {
        case language(LanguageActivityKind, LanguageIdentifier, UUID)
        case math(MathProductionActivityID, MathCurriculumLevelID, UUID)
        case ticTacToe(UUID)
        case pingPong(UUID)
        case parentArea
        case progress
        case records(returnToParentArea: Bool)
        case recordsLeaderboard([RemoteRecordPlacement])
        /// Android Minik Math Plus MathDailyScreen: the daily math journey's page.
        case mathDaily
    }

    let configuration: ProductConfiguration
    @ObservedObject private var interfaceLocaleController: InterfaceLocaleController
    @ObservedObject private var learningReminderController: LearningReminderController
    @ObservedObject private var commerceController: MinikCommerceController
    private let adCoordinator: MinikAdCoordinator

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.interfaceLocaleID) private var interfaceLocaleID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The Math hub's card and level text follow Dynamic Type, within what the cards hold.
    @ScaledMetric(relativeTo: .body) private var hubTextPercent: CGFloat = 100
    @State private var selectedLanguage: LanguageIdentifier
    @State private var mathLevelController: MathLevelController
    @State private var languageActivitySessionID = ActivitySessionID()
    @State private var mathActivitySessionID = ActivitySessionID()
    @State private var route: Route?
    @State private var languageMenuIsPresented = false
    @State private var hasShownLanguageOpening = false
    /// The Top 20 opened by itself over the intro (RecordsAutoShowPolicy).
    @State private var recordsAutoPresented = false
    @State private var languageRewards = RewardState()
    @State private var languageWordBonusRun = 0
    @State private var pingPongCompletedMatchCount = 0
    @State private var languageLevelSettings: LanguageParentLevelSettings
    @State private var languageAutoState: LanguageAutoProgressionState
    @State private var publicAliasPromptIsPresented = false
    @State private var publicAliasChoices: [PublicLeaderboardAlias] = []
    @State private var publicAliasIsSaving = false
    @State private var pendingPublicationNoticeIsPresented = false
    @State private var lastPendingNoticeKey: String?
    /// The playing child's public Top 20 controls; replaced when another child plays.
    @State private var publicLeaderboardController: PublicLeaderboardController
    /// The children on this device and whose progress is in place (Android IntroScreen).
    @StateObject private var childProfiles: ChildProfileStore
    /// Android DailyLearning's toast when today's fifth little win is earned.
    @State private var dailyLearningToast: String?
    /// The daily math journey (Android Math Plus AppState's daily route): the saved journey,
    /// whether its activity is being played now, and whether a stage was just completed
    /// (Android dailyActive and dailyFinished, kept while the app runs).
    @State private var mathDailyJourney = MathDailyJourneyRepository().load()
    @State private var mathDailyIsPlaying = false
    @State private var mathDailyFinished = false
    /// Where the Math hub's board and rows are while it scrolls, for its "More below" cue.
    @State private var hubScrollTracker = MinikHubScrollTracker()
    @State private var mathHubContinuesBelow = false

    private let mathFactory: MathActivitySessionFactory
    private let mathM1Factory: MathM1ActivitySessionFactory?
    private let mathM2Factory: MathM2ActivitySessionFactory?
    private let mathM3Factory: MathM3ActivitySessionFactory?
    private let mathM4Factory: MathM4ActivitySessionFactory?
    private let mathM5Factory: MathM5ActivitySessionFactory?
    private let mathM6Factory: MathM6ActivitySessionFactory?
    private let mathM7Factory: MathM7ActivitySessionFactory?
    private let mathM8Factory: MathM8ActivitySessionFactory?
    private let mathM9Factory: MathM9ActivitySessionFactory?
    private let mathM10Factory: MathM10ActivitySessionFactory?
    private let progressRepository: LocalProgressRepository
    @State private var wordRewardService: LanguageWordPracticeRewardService
    private let rewardRepository: LocalRewardRepository
    private let rewardService: LocalRewardService
    /// The playing child's record submissions, under that child's own public identity.
    @State private var rewardRecordSubmissionService: RewardRecordSubmissionService
    private let injectedRecordsRepository: (any RecordsRepository)?
    /// The online Top 20 is set up in this build (Android's fireBaseInitiated), so
    /// it may open by itself.
    private let publicRecordsConfigured: Bool
    @State private var outcomeDispatcher: ActivityOutcomeDispatcher

    private let learnedLanguageRepository: LearnedLanguageRepository
    private let languageLevelRepository: LanguageParentLevelSettingsRepository
    private let languageAutoRepository: LanguageAutoProgressRepository

    @MainActor
    init(
        configuration: ProductConfiguration,
        interfaceLocaleController: InterfaceLocaleController,
        learningReminderController: LearningReminderController,
        commerceController: MinikCommerceController,
        adCoordinator: MinikAdCoordinator,
        learnedLanguageRepository: LearnedLanguageRepository = LearnedLanguageRepository(),
        languageLevelRepository: LanguageParentLevelSettingsRepository = LanguageParentLevelSettingsRepository(),
        languageAutoRepository: LanguageAutoProgressRepository = LanguageAutoProgressRepository(),
        remoteRecordsRepository: (any RecordsRepository)? = nil
    ) {
        self.configuration = configuration
        self.interfaceLocaleController = interfaceLocaleController
        self.learningReminderController = learningReminderController
        self.commerceController = commerceController
        self.adCoordinator = adCoordinator
        self.learnedLanguageRepository = learnedLanguageRepository
        self.languageLevelRepository = languageLevelRepository
        self.languageAutoRepository = languageAutoRepository
        // Before anything per child is loaded: an exchange of children that a
        // stopped app left half done is completed first.
        let activeLearner = ChildProfileStore.activeLearnerAfterRecovery(for: configuration.variant)
        _childProfiles = StateObject(wrappedValue: ChildProfileStore(product: configuration.variant))
        self.mathFactory = MathActivitySessionFactory(configuration: configuration)
        let progressRepository = LocalProgressRepository()
        self.progressRepository = progressRepository
        let rewardRepository = LocalRewardRepository()
        let rewardService = LocalRewardService(repository: rewardRepository)
        self.rewardRepository = rewardRepository
        self.rewardService = rewardService
        // The playing child's own public identity, alias and pending best (the
        // guest keeps the identity the app had before child profiles).
        let records = ChildProfileRecordsComposition.make(
            product: configuration.variant,
            ownerID: activeLearner.rewardOwnerID,
            injectedRepository: remoteRecordsRepository
        )
        let rewardRecordSubmissionService = records.submission
        _rewardRecordSubmissionService = State(initialValue: rewardRecordSubmissionService)
        self.injectedRecordsRepository = remoteRecordsRepository
        self.publicRecordsConfigured = records.isConfigured
        _publicLeaderboardController = State(initialValue: PublicLeaderboardController(
            service: rewardRecordSubmissionService
        ))
        let wordRewardService = LanguageWordPracticeRewardService(repository: rewardRepository)
        _wordRewardService = State(initialValue: wordRewardService)
        _languageRewards = State(initialValue: ((try? rewardRepository.loadLedger()) ?? RewardLedger()).state(
            for: RewardScope(ownerID: .localDefault, product: configuration.variant)
        ))
        _outcomeDispatcher = State(initialValue: ActivityOutcomeDispatcher(
            progressSink: progressRepository,
            rewardHandler: { event in
                if let rewardEvent = LanguageLetterPairsRewardMapper.rewardEvent(for: event) {
                    _ = try rewardService.process(rewardEvent, policy: .androidLetterPairsReference)
                }
                if let rewardEvent = LanguageTowerRewardMapper.rewardEvent(for: event) {
                    _ = try rewardService.process(rewardEvent, policy: .androidTowerReference)
                }
                if let rewardEvent = LanguagePictureMemoryRewardMapper.rewardEvent(for: event) {
                    _ = try rewardService.process(rewardEvent, policy: .androidPictureMemoryReference)
                }
                try wordRewardService.processAttempt(event)
            }
        ))
        self.mathM1Factory = configuration.variant == .minikMath
            ? MathM1ActivitySessionFactory(configuration: configuration)
            : nil
        self.mathM2Factory = configuration.variant == .minikMath
            ? MathM2ActivitySessionFactory(configuration: configuration)
            : nil
        self.mathM3Factory = configuration.variant == .minikMath
            ? MathM3ActivitySessionFactory(configuration: configuration)
            : nil
        self.mathM4Factory = configuration.variant == .minikMath
            ? MathM4ActivitySessionFactory(configuration: configuration)
            : nil
        self.mathM5Factory = configuration.variant == .minikMath
            ? MathM5ActivitySessionFactory(configuration: configuration)
            : nil
        self.mathM6Factory = configuration.variant == .minikMath
            ? MathM6ActivitySessionFactory(configuration: configuration)
            : nil
        self.mathM7Factory = configuration.variant == .minikMath
            ? MathM7ActivitySessionFactory(configuration: configuration)
            : nil
        self.mathM8Factory = configuration.variant == .minikMath
            ? MathM8ActivitySessionFactory(configuration: configuration)
            : nil
        self.mathM9Factory = configuration.variant == .minikMath
            ? MathM9ActivitySessionFactory(configuration: configuration)
            : nil
        self.mathM10Factory = configuration.variant == .minikMath
            ? MathM10ActivitySessionFactory(configuration: configuration)
            : nil
        _selectedLanguage = State(initialValue:
            learnedLanguageRepository.load(for: configuration)
                ?? Self.defaultLearnedLanguage(for: configuration)
        )
        let initialLanguageSettings = configuration.contentDomain == .language
            ? languageLevelRepository.load(for: configuration.variant)
            : .androidDefault
        _languageLevelSettings = State(initialValue: initialLanguageSettings)
        _languageAutoState = State(initialValue: languageAutoRepository.load(
            scope: LanguageAutoScope(product: configuration.variant),
            currentLevel: initialLanguageSettings.wordLevel
        ))
        let persistedMathState = LocalMathLevelRepository().load()
        let mathController = MathLevelController(state: persistedMathState)
        _mathLevelController = State(initialValue: mathController)
    }

    private var languageFactory: LanguageActivitySessionFactory {
        LanguageActivitySessionFactory(
            configuration: configuration,
            vocabularyLevel: languageLevelSettings.wordLevel,
            vocabularyRamp: languageAutoState.ramp
        )
    }

    private var reloadedLanguageFactory: LanguageActivitySessionFactory {
        let settings = languageLevelRepository.load(for: configuration.variant)
        let state = languageAutoRepository.load(
            scope: LanguageAutoScope(product: configuration.variant),
            currentLevel: settings.wordLevel
        )
        return LanguageActivitySessionFactory(
            configuration: configuration,
            vocabularyLevel: settings.wordLevel,
            vocabularyRamp: state.ramp
        )
    }

    var body: some View {
        ZStack {
            destination
                .environment(\.languageRewardState, languageRewards)
                .environment(\.languageWordBonusRun, languageWordBonusRun)
                .environment(\.languageEncouragementEnabled, EncouragementPreferenceRepository().load(for: configuration.variant))
                .environment(\.mathReadAloudEnabled, MathReadAloudPreferenceRepository().load())
        }
        .overlay {
            if configuration.contentDomain == .language, case .parentArea = route {
                ZStack {
                    Color.black.opacity(0.18).ignoresSafeArea()
                    parentAreaContent
                }
            }
        }
        .overlay {
            if recordsAutoPresented {
                LanguageRecordsDialog(product: configuration.variant, offersAutomaticOptOut: true) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        recordsAutoPresented = false
                    }
                }
                .transition(.opacity)
            }
        }
        .overlay {
            if configuration.contentDomain == .language && !hasShownLanguageOpening {
                LanguageOpeningView(onFinish: { hasShownLanguageOpening = true })
            }
        }
        .overlay {
            if publicAliasPromptIsPresented {
                publicAliasPrompt
            } else if pendingPublicationNoticeIsPresented {
                pendingPublicationNotice
            }
        }
        .overlay(alignment: .bottom) {
            if let dailyLearningToast {
                dailyLearningToastView(dailyLearningToast)
                    .transition(.opacity)
            }
        }
        .sheet(isPresented: parentAreaPresented) {
            parentAreaContent
                // The family card opened from the Parent Area is drawn here, above the sheet (only
                // the FamilyOverlay that appeared last draws it).
                .overlay { FamilyOverlay() }
                .presentationDetents([.fraction(0.82), .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.clear)
                .presentationCornerRadius(34)
                // The hub's light rainbow-sky design: the sheet stays light as well.
                .preferredColorScheme(.light)
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            guard configuration.contentDomain == .language,
                  oldPhase != .background,
                  newPhase == .background else { return }
            languageAutoState.applicationDidStop()
            languageAutoRepository.save(languageAutoState)
        }
        .onChange(of: hasShownLanguageOpening) { _, hasShown in
            if hasShown {
                presentRecordsAutomaticallyIfAllowed()
            }
        }
        // Android retries a pending deletion whenever the app comes to the front
        // (RecordsDetails, onActivityStarted).
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                cleanUpDeletedChildrenPublicRecords()
            }
        }
        .onAppear(perform: applyStoreScreenshotScene)
        // Android's intro selects the last chosen child when it opens (selectUser),
        // which brings back that child's interface language if another is showing.
        .onAppear(perform: followChildInterfaceLanguage)
        // Public records of children deleted earlier whose deletion did not finish.
        .onAppear(perform: cleanUpDeletedChildrenPublicRecords)
    }

    /// Android IntroFragment opens the Top 20 by itself once the opening is over.
    /// It now does so only as RecordsAutoShowPolicy allows: once per launch, with
    /// "show automatically" on and at least 100 points; never over another screen
    /// or in the App Store screenshot scenes.
    private func presentRecordsAutomaticallyIfAllowed() {
        guard configuration.contentDomain == .language,
              StoreScreenshotScene.name == nil,
              route == nil,
              !languageMenuIsPresented,
              publicRecordsConfigured,
              RecordsAutoShowPolicy.claimAutomaticShowing(points: languageRewards.points) else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            recordsAutoPresented = true
        }
    }

    /// App Store screenshot captures open one screen at launch; see StoreScreenshotScene.
    private func applyStoreScreenshotScene() {
        guard let scene = StoreScreenshotScene.name, route == nil else { return }
        hasShownLanguageOpening = scene != "opening"
        if let raw = StoreScreenshotScene.value(after: "language"),
           let activity = LanguageActivityKind(rawValue: raw) {
            launchLanguageActivity(activity)
        } else if let raw = StoreScreenshotScene.value(after: "math"),
                  let activity = MathProductionActivityID(rawValue: raw) {
            route = .math(activity, selectedMathLevelID, UUID())
            mathActivitySessionID = ActivitySessionID()
        } else if scene == "progress" {
            route = .progress
        } else if scene == "parents" {
            route = .parentArea
        } else if scene == "menu" || scene == "menu.games" {
            // The Language activity menu; "menu.games" scrolls it to its end
            // (LanguageMenuView.applyStoreScreenshotScroll).
            languageMenuIsPresented = true
        }
    }

    private var parentAreaContent: some View {
        ParentAreaView(
            configuration: configuration,
            interfaceLocaleController: interfaceLocaleController,
            selectedLanguage: selectedLanguage,
            languageLevelSettings: languageLevelSettings,
            mathLevelState: configuration.contentDomain == .math ? mathLevelController.state : nil,
            learningReminderController: learningReminderController,
            commerceController: commerceController,
            publicLeaderboardController: publicLeaderboardController,
            onSelectLanguage: selectLearnedLanguage,
            onSetLanguageLevels: setLanguageLevels,
            onSetMathMode: setMathLevelMode,
            onSelectMathLevel: selectManualMathLevel,
            onShowProgress: { route = .progress },
            onShowRecords: { route = .records(returnToParentArea: true) },
            onExit: { route = nil }
        )
    }

    @ViewBuilder
    private var destination: some View {
        switch route {
        case .none, .parentArea:
            if configuration.contentDomain == .language {
                languageHome
            } else {
                hubBody
            }
        case .language(let activity, let language, let launchID):
            languageDestination(for: activity, language: language)
                .id(launchID)
        case .math(let activity, let levelID, let launchID):
            mathDestination(for: activity, levelID: levelID)
                .id(launchID)
                // Android MathDailyScreen: the journey's progress line above the day's activity.
                .safeAreaInset(edge: .top, spacing: 0) {
                    if mathDailyIsPlaying {
                        mathDailyProgressLine
                    }
                }
        case .mathDaily:
            MathDailyJourneyView(
                state: mathDailyJourney,
                isFinished: mathDailyFinished,
                onStart: startMathDailyActivity,
                onNext: acknowledgeMathDaily,
                onClose: closeMathDaily
            )
        case .ticTacToe(let launchID):
            TicTacToeView(
                onResolvedRound: recordLanguageTicTacToeCompletion,
                onCompletedRound: { recordLanguageAdOpportunity(.languageTicTacToe) },
                onExit: returnToHub
            )
                .id(launchID)
        case .pingPong(let launchID):
            MathPingPongChooser(
                commerce: commerceController,
                onCompletedMatch: { recordLanguageAdOpportunity(.mathRound) },
                onExit: returnToHub
            )
                .id(launchID)
        case .progress:
            ProgressStatisticsView(
                model: progressReadModel,
                onBack: { route = .parentArea }
            )
        case .records(let returnToParentArea):
            RecordsStreaksView(
                model: recordsReadModel,
                onBack: { route = returnToParentArea ? .parentArea : nil }
            )
        case .recordsLeaderboard(let highlightedPlacements):
            RecordsLeaderboardView(
                product: configuration.variant,
                highlightedPlacements: highlightedPlacements,
                onClose: returnToHub
            )
        }
    }

    private var parentAreaPresented: Binding<Bool> {
        Binding(
            get: {
                if configuration.contentDomain != .language, case .parentArea = route { return true }
                return false
            },
            set: { isPresented in
                if !isPresented, case .parentArea = route {
                    route = nil
                }
            }
        )
    }

    /// The menu's Trophy opens the Top 20 as a dialog over the menu itself, as
    /// Android's RecordsLeaderboardDialogFragment does, so it needs no route.
    @ViewBuilder
    private var languageHome: some View {
        if languageMenuIsPresented {
            LanguageMenuView(
                configuration: configuration,
                learnedLanguage: selectedLanguage,
                onSelect: launchLanguageActivity,
                onHome: { languageMenuIsPresented = false; route = nil }
            )
        } else {
            LanguageIntroView(
                rewards: languageRewards,
                variant: configuration.variant,
                childProfiles: childProfiles,
                commerceController: commerceController,
                onLearnerChanged: learnerDidChange,
                onPractice: { languageMenuIsPresented = true },
                onParentArea: { route = .parentArea }
            )
        }
    }

    /// A child was added, chosen or deleted on the Intro, so every per-child value
    /// in place now belongs to the learner on screen: the app takes that child's
    /// interface language, the hub reloads what it keeps in memory, and the Top 20
    /// follows that learner's own public identity.
    private func learnerDidChange() {
        followChildInterfaceLanguage()
        refreshLanguageRewards()
        languageWordBonusRun = 0
        selectedLanguage = learnedLanguageRepository.load(for: configuration)
            ?? Self.defaultLearnedLanguage(for: configuration)
        if configuration.contentDomain == .language {
            let settings = languageLevelRepository.load(for: configuration.variant)
            languageLevelSettings = settings
            languageAutoState = languageAutoRepository.load(
                scope: LanguageAutoScope(product: configuration.variant),
                currentLevel: settings.wordLevel
            )
        }
        let records = ChildProfileRecordsComposition.make(
            product: configuration.variant,
            ownerID: childProfiles.activeLearner.rewardOwnerID,
            injectedRepository: injectedRecordsRepository
        )
        rewardRecordSubmissionService = records.submission
        publicLeaderboardController = PublicLeaderboardController(service: records.submission)
        lastPendingNoticeKey = nil
        cleanUpDeletedChildrenPublicRecords()
    }

    /// Android IntroScreen.selectUser, which runs for the added child, the chosen
    /// child, and the first child left after a deletion: a child with an
    /// interface language of their own brings it back. When the last child was
    /// deleted, the guest's values return but the language on screen stays, as
    /// setNoUsersExistView changes no language.
    private func followChildInterfaceLanguage() {
        guard case .child(_) = childProfiles.activeLearner else { return }
        interfaceLocaleController.applyLearnerChoice()
    }

    /// Android deletes a removed child's public Top 20 records
    /// (LeaderboardState.removeSlot). Each deleted child's records are deleted
    /// through that child's own identity, right after the deletion and again at
    /// later launches and whenever the app comes back to the front, until it
    /// succeeds, as Android's outbox keeps the deletion pending until then.
    private func cleanUpDeletedChildrenPublicRecords() {
        guard configuration.contentDomain == .language else { return }
        let profiles = childProfiles
        for ownerID in profiles.beginPublicRecordCleanups() {
            let submission = ChildProfileRecordsComposition.make(
                product: configuration.variant,
                ownerID: ownerID
            ).submission
            Task {
                // Deletion is offered only once participation is off, as in the Parent Area.
                _ = await submission.setParticipationEnabled(false)
                let deleted = await submission.deletePublicRecords()
                await MainActor.run {
                    profiles.finishPublicRecordCleanup(for: ownerID, deleted: deleted)
                }
            }
        }
    }

    private func launchLanguageActivity(_ activity: LanguageActivityKind) {
        languageActivitySessionID = ActivitySessionID()
        try? wordRewardService.beginSession(languageActivitySessionID, product: configuration.variant)
        languageWordBonusRun = wordRewardService.cleanWordRun
        if activity == .ticTacToe {
            route = .ticTacToe(UUID())
        } else {
            route = .language(activity, selectedLanguage, UUID())
        }
    }

    /// The Math hub in the rainbow-sky design (Android Minik Math Plus, Rainbow Sky):
    /// the Minik Math logo and Parent Area on the sky, and a glass panel with the
    /// current level and the activity sections as pastel cards under colored section
    /// pills. The cards sit in plain rows rather than a lazy grid, so the board
    /// scrolls without jumps. On iPad the sizes and spacing grow and the cards take
    /// three or four columns, a tablet layout rather than an enlarged phone one.
    private var hubBody: some View {
        GeometryReader { geometry in
            let metrics = MinikHubMetrics(size: geometry.size)
            let panelWidth = max(1, min(metrics.panelMaxWidth, geometry.size.width - 2 * metrics.panelMargin))
            let contentWidth = max(1, panelWidth - 2 * metrics.panelPadding)
            let showsMoreBelowRow = configuration.contentDomain == .math
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    hubHeader(metrics)
                    MinikGlassPanel(padding: 0, cornerRadius: metrics.panelRadius) {
                        ScrollView {
                            hubBoard(metrics: metrics, contentWidth: contentWidth)
                        }
                        .scrollBounceBehavior(.basedOnSize)
                        .scrollIndicators(.hidden)
                        .background {
                            MinikHubPositionProbe { rect in
                                hubScrollTracker.viewport = rect
                                refreshMathHubContinuation()
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: metrics.panelRadius, style: .continuous))
                    }
                    .frame(width: panelWidth)
                    .frame(maxHeight: .infinity)
                    .padding(.top, metrics.panelTopMargin)
                    .padding(.bottom, showsMoreBelowRow ? 0 : metrics.panelBottomMargin)

                    // Android Math Plus HubScreen (menu discovery, 2026-10-13): a row of its own
                    // under the panel, so the cue never covers a card.
                    if showsMoreBelowRow {
                        mathMoreBelowRow(metrics, proxy: proxy)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            }
        }
        // A background never sizes the layout (see MinikHomeScreen).
        .background {
            MinikSkyBackground()
        }
    }

    /// The logo at the start; the Top 20 (only products with a public leaderboard;
    /// like Android Math, iOS Math has none) and Parent Area at the end.
    private func hubHeader(_ metrics: MinikHubMetrics) -> some View {
        HStack(alignment: .center, spacing: metrics.headerGap) {
            MinikArtworkImage(
                name: configuration.contentDomain == .math ? MinikPretty.Art.mathLogo : MinikVisualAsset.logo
            )
            .frame(width: metrics.logoSize, height: metrics.logoSize)
            .shadow(color: MinikPretty.shadowInk.opacity(0.18), radius: 4, x: 0, y: 2)

            Spacer(minLength: 0)

            if RemoteRecordsConfiguration.androidCompatible(for: configuration.variant) != nil {
                Button {
                    route = .recordsLeaderboard([])
                } label: {
                    MinikArtworkImage(name: MinikVisualAsset.trophy)
                        .padding(metrics.trophyPadding)
                        .frame(width: metrics.roundButton, height: metrics.roundButton)
                        .background {
                            MinikPretty.RoundButtonBackground()
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(MinikPretty.PressScaleStyle())
                .accessibilityLabel(String(localized: "Top 20 records"))
            }

            Button {
                route = .parentArea
            } label: {
                Text(interfaceLocaleID.text("Parent Area"))
                    .padding(.horizontal, 4)
            }
            .buttonStyle(MinikPretty.HeroButtonStyle(
                look: MinikPretty.PillLook.purple,
                fontSize: metrics.parentButtonTextSize,
                minHeight: metrics.parentButtonHeight
            ))
            .accessibilityHint(String(localized: "Opens learning settings and progress"))
        }
        .padding(.horizontal, metrics.screenMargin)
        .padding(.top, metrics.topMargin)
    }

    private func hubBoard(metrics: MinikHubMetrics, contentWidth: CGFloat) -> some View {
        let columns = hubColumnCount(metrics, contentWidth: contentWidth)
        let cardWidth = max(1, (contentWidth - metrics.cardGap * CGFloat(columns - 1)) / CGFloat(columns))
        return VStack(spacing: 0) {
            VStack(spacing: 0) {
                if configuration.contentDomain == .math {
                    // Android Math Plus HubScreen (7682b75): the daily math journey first.
                    mathDailyButton(metrics)
                        .padding(.bottom, metrics.sectionGap)
                        .id(MinikHubScrollID.daily)
                        .background { hubScrollTargetProbe(MinikHubScrollID.daily) }
                    mathLevelCard(metrics)
                        .padding(.bottom, metrics.sectionTopGap)
                        .id(MinikHubScrollID.level)
                        .background { hubScrollTargetProbe(MinikHubScrollID.level) }
                }

                ForEach(ActivityCatalog.mathSections(
                    for: configuration,
                    levelID: selectedMathLevelID
                )) { section in
                    VStack(spacing: 0) {
                        hubSectionBanner(id: section.id, title: section.title, metrics: metrics)
                            .padding(.bottom, metrics.sectionGap)
                            .id(MinikHubScrollID.banner(section.id))
                            .background { hubScrollTargetProbe(MinikHubScrollID.banner(section.id)) }
                        mathCardRows(
                            section.activities,
                            sectionID: section.id,
                            columns: columns,
                            cardWidth: cardWidth,
                            metrics: metrics
                        )
                    }
                    .padding(.bottom, metrics.sectionTopGap)
                }

                ForEach(ActivityCatalog.productGameSections(for: configuration)) { section in
                    VStack(spacing: 0) {
                        hubSectionBanner(id: section.id, title: section.title, metrics: metrics)
                            .padding(.bottom, metrics.sectionGap)
                            .id(MinikHubScrollID.banner(section.id))
                            .background { hubScrollTargetProbe(MinikHubScrollID.banner(section.id)) }
                        gameCardRows(
                            section.activities,
                            sectionID: section.id,
                            columns: columns,
                            cardWidth: cardWidth,
                            metrics: metrics
                        )
                    }
                    .padding(.bottom, metrics.sectionTopGap)
                }
            }
            .padding(.horizontal, metrics.panelPadding)
            .padding(.top, metrics.panelPaddingTop)
            .padding(.bottom, max(0, metrics.panelPaddingBottom - metrics.sectionTopGap))

            // The end of the board: once it is in view, "More below" goes away.
            Color.clear
                .frame(height: 1)
                .id(MinikHubScrollID.end)
                .background {
                    MinikHubPositionProbe { rect in
                        hubScrollTracker.endMinY = rect.minY
                        refreshMathHubContinuation()
                    }
                }
        }
    }

    /// Android's daily journey entry in every app: the yellow #FFE082 button with #282D4E ink.
    private func mathDailyButton(_ metrics: MinikHubMetrics) -> some View {
        Button {
            route = .mathDaily
        } label: {
            Text(verbatim: String(localized: "Daily math journey"))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(MinikPretty.HeroButtonStyle(
            look: Self.mathDailyLook,
            fontSize: metrics.levelTitleSize * hubTextScale,
            minHeight: metrics.parentButtonHeight + 4
        ))
    }

    private static let mathDailyLook = MinikPretty.PillLook(
        top: MinikPretty.color(0xFFE082),
        bottom: MinikPretty.color(0xFFE082),
        lip: MinikPretty.color(0xDEC067),
        rim: Color.white,
        ink: MinikPretty.color(0x282D4E),
        inkShadow: Color.clear
    )

    private func hubScrollTargetProbe(_ id: String) -> some View {
        MinikHubPositionProbe { rect in
            hubScrollTracker.targetMinY[id] = rect.minY
        }
    }

    /// Android Math Plus's "More below ⌄" (menu discovery): shown while the board goes on
    /// below the panel; a tap moves the board on by about two thirds of the panel.
    private func mathMoreBelowRow(_ metrics: MinikHubMetrics, proxy: ScrollViewProxy) -> some View {
        ZStack {
            if mathHubContinuesBelow {
                Button {
                    scrollMathHubFurther(using: proxy)
                } label: {
                    Text(verbatim: String(localized: "More below") + "  ⌄")
                        .font(MinikPretty.titleFont((metrics.tablet ? 19 : 16) * hubTextScale))
                        .foregroundStyle(MinikPretty.color(0x233B5C))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: String(localized: "More below")))
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: metrics.tablet ? 52 : 46)
        .padding(.bottom, metrics.tablet ? 6 : 2)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: mathHubContinuesBelow)
    }

    private func refreshMathHubContinuation() {
        let viewport = hubScrollTracker.viewport
        guard configuration.contentDomain == .math, viewport.height > 0 else { return }
        let continues = hubScrollTracker.endMinY > viewport.maxY + 1
        if continues != mathHubContinuesBelow {
            mathHubContinuesBelow = continues
        }
    }

    /// Android scrolls 65% of the board's height per tap. Here the furthest row that starts
    /// within that distance moves to the top, so nothing is skipped (as in the Language menu).
    private func scrollMathHubFurther(using proxy: ScrollViewProxy) {
        let viewport = hubScrollTracker.viewport
        guard viewport.height > 0 else { return }
        let distance = viewport.height * 0.65
        var target: String?
        var anchor = UnitPoint.top
        let ordered = hubScrollTracker.targetMinY.sorted { $0.value < $1.value }
        for entry in ordered {
            let distanceFromTop = entry.value - viewport.minY
            if distanceFromTop <= 1 { continue }
            if distanceFromTop <= distance {
                target = entry.key
                continue
            }
            if target == nil {
                target = entry.key
                anchor = distanceFromTop <= viewport.height ? .top : .bottom
            }
            break
        }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.4)) {
            if let target {
                proxy.scrollTo(target, anchor: anchor)
            } else {
                proxy.scrollTo(MinikHubScrollID.end, anchor: .bottom)
            }
        }
    }

    /// The current level, as Android Math Plus's level card: Minik on the rainbow,
    /// the level and what it practises, on a white tile.
    private func mathLevelCard(_ metrics: MinikHubMetrics) -> some View {
        HStack(spacing: metrics.tablet ? 18 : 12) {
            MinikArtworkImage(name: MinikPretty.Art.welcome)
                .frame(
                    width: metrics.levelArtHeight * MinikPretty.Art.welcomeAspect,
                    height: metrics.levelArtHeight
                )
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedMathLevel.title)
                    .font(MinikPretty.titleFont(metrics.levelTitleSize * hubTextScale))
                    .foregroundStyle(MinikPretty.navy)
                    .fixedSize(horizontal: false, vertical: true)
                Text(selectedMathLevel.subtitle)
                    .font(MinikPretty.bodyFont(metrics.levelSubtitleSize * hubTextScale))
                    .foregroundStyle(MinikPretty.softInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(metrics.tablet ? 8 : 2)
        .minikChoiceTile(selected: false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(
            format: mathLevelController.state.mode == .automatic
                ? String(localized: "Automatic math level: %@")
                : String(localized: "Manual math level: %@"),
            selectedMathLevel.title
        ))
    }

    /// The sections' colored pills, as in the language menu.
    private func hubSectionBanner(id: String, title: String, metrics: MinikHubMetrics) -> some View {
        let look: MinikPretty.PillLook
        let icon: MinikPretty.SectionBanner.Icon
        switch id {
        case "math-learn":
            look = MinikPretty.PillLook.bannerPurple
            icon = MinikPretty.SectionBanner.Icon.art(MinikPretty.Art.iconBook)
        case "math-practice":
            look = MinikPretty.PillLook.bannerBlue
            icon = MinikPretty.SectionBanner.Icon.symbol("plus.forwardslash.minus")
        case "math-games":
            look = MinikPretty.PillLook.bannerWarm
            icon = MinikPretty.SectionBanner.Icon.art(MinikPretty.Art.iconGames)
        default:
            look = MinikPretty.PillLook.bannerPurple
            icon = MinikPretty.SectionBanner.Icon.symbol("sparkles")
        }
        return MinikPretty.SectionBanner(
            title: title,
            look: look,
            icon: icon,
            tablet: metrics.tablet,
            scale: metrics.scale
        )
    }

    private func mathCardRows(
        _ activities: [MathProductionActivityID],
        sectionID: String,
        columns: Int,
        cardWidth: CGFloat,
        metrics: MinikHubMetrics
    ) -> some View {
        let rows = Self.rowsOf(activities, columns: columns)
        return VStack(spacing: metrics.cardGap) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(alignment: .top, spacing: metrics.cardGap) {
                    ForEach(row) { activity in
                        hubCard(
                            title: activity.title,
                            subtitle: activity.subtitle,
                            tint: Self.cardTint(for: activity),
                            visual: Self.cardVisual(for: activity),
                            width: cardWidth,
                            metrics: metrics
                        ) {
                            if activity.launchRoute(for: selectedMathLevelID) == .pingPong {
                                pingPongCompletedMatchCount = 0
                            }
                            route = .math(activity, selectedMathLevelID, UUID())
                            mathActivitySessionID = ActivitySessionID()
                        }
                    }
                }
                // The cards of a row are as tall as the tallest; a short last row is centred.
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .id(MinikHubScrollID.row(sectionID, index))
                .background { hubScrollTargetProbe(MinikHubScrollID.row(sectionID, index)) }
            }
        }
    }

    private func gameCardRows(
        _ games: [ProductGameKind],
        sectionID: String,
        columns: Int,
        cardWidth: CGFloat,
        metrics: MinikHubMetrics
    ) -> some View {
        let rows = Self.rowsOf(games, columns: columns)
        return VStack(spacing: metrics.cardGap) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(alignment: .top, spacing: metrics.cardGap) {
                    ForEach(row) { game in
                        hubCard(
                            title: game.title,
                            subtitle: game.subtitle,
                            tint: MinikPretty.CardTint.blue,
                            visual: MinikHubCardVisual(art: PingPongAssetNames.minikPong),
                            width: cardWidth,
                            metrics: metrics
                        ) {
                            switch game {
                            case .pingPong:
                                pingPongCompletedMatchCount = 0
                                route = .pingPong(UUID())
                            }
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .id(MinikHubScrollID.row(sectionID, index))
                .background { hubScrollTargetProbe(MinikHubScrollID.row(sectionID, index)) }
            }
        }
    }

    /// A pastel card (bg_menu_card_*): its picture on top and a white strip with the
    /// navy name and the soft-ink description under it.
    private func hubCard(
        title: String,
        subtitle: String,
        tint: MinikPretty.CardTint,
        visual: MinikHubCardVisual,
        width: CGFloat,
        metrics: MinikHubMetrics,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: metrics.cardLabelGap) {
                hubCardVisual(visual, metrics: metrics)
                    .frame(maxWidth: .infinity)
                    .frame(height: metrics.cardArtHeight)
                VStack(spacing: 2) {
                    Text(title)
                        .font(MinikPretty.titleFont(metrics.cardTitleSize * hubTextScale))
                        .foregroundStyle(MinikPretty.navy)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.75)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .font(MinikPretty.bodyFont(metrics.cardSubtitleSize * hubTextScale))
                        .foregroundStyle(MinikPretty.softInk)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background {
                    RoundedRectangle(cornerRadius: metrics.cardLabelRadius, style: .continuous)
                        .fill(Color.white.opacity(0.94))
                }
            }
            .padding(.horizontal, metrics.cardPadding)
            .padding(.top, metrics.cardPadding)
            .padding(.bottom, metrics.cardPaddingBottom)
            .frame(width: width)
            .frame(maxHeight: .infinity)
            .background {
                MinikPretty.CardBackground(tint: tint, cornerRadius: metrics.cardRadius)
            }
            .contentShape(RoundedRectangle(cornerRadius: metrics.cardRadius, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(title) + Text(verbatim: ". ") + Text(subtitle))
        }
        .buttonStyle(MinikPretty.PressScaleStyle())
    }

    @ViewBuilder
    private func hubCardVisual(_ visual: MinikHubCardVisual, metrics: MinikHubMetrics) -> some View {
        if let art = visual.art {
            MinikArtworkImage(name: art)
        } else {
            HStack(spacing: 4) {
                if let glyph = visual.leadingGlyph {
                    hubGlyph(glyph, metrics: metrics)
                }
                if let objectName = visual.objectName, visual.objectCount > 0 {
                    HStack(spacing: 2) {
                        ForEach(0..<visual.objectCount, id: \.self) { _ in
                            Image(objectName)
                                .resizable()
                                .scaledToFit()
                                .frame(width: metrics.objectSize, height: metrics.objectSize)
                        }
                    }
                }
                if let glyph = visual.trailingGlyph {
                    hubGlyph(glyph, metrics: metrics)
                }
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                RoundedRectangle(cornerRadius: metrics.cardLabelRadius, style: .continuous)
                    .fill(Color.white.opacity(0.55))
            }
            // Sums read left to right in every language.
            .environment(\.layoutDirection, .leftToRight)
            .accessibilityHidden(true)
        }
    }

    private func hubGlyph(_ text: String, metrics: MinikHubMetrics) -> some View {
        Text(verbatim: text)
            .font(MinikPretty.titleFont(metrics.glyphSize))
            .foregroundStyle(MinikPretty.navy)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }

    private var hubTextScale: CGFloat {
        min(1.6, max(0.9, hubTextPercent / 100))
    }

    /// Two columns on phones, three or four as the width allows (iPad, landscape);
    /// accessibility text sizes get one column on phones and two on iPad.
    private func hubColumnCount(_ metrics: MinikHubMetrics, contentWidth: CGFloat) -> Int {
        if dynamicTypeSize.isAccessibilitySize {
            return metrics.tablet ? 2 : 1
        }
        let fitting = Int((contentWidth + metrics.cardGap) / (metrics.cardMinWidth + metrics.cardGap))
        return min(4, max(2, fitting))
    }

    private static func rowsOf<Item>(_ items: [Item], columns: Int) -> [[Item]] {
        let size = max(1, columns)
        var rows: [[Item]] = []
        var start = 0
        while start < items.count {
            let end = min(start + size, items.count)
            rows.append(Array(items[start..<end]))
            start = end
        }
        return rows
    }

    private static func cardTint(for activity: MathProductionActivityID) -> MinikPretty.CardTint {
        switch activity {
        case .learnMath, .buildMath:
            return .pink
        case .mathCards, .visualToAnswer, .pingPong:
            return .blue
        case .mathPairs, .mathTower:
            return .mint
        case .buildNumber, .mathMixed:
            return .yellow
        case .buildQuantity, .mathSoccer:
            return .peach
        case .answerToRepresentation, .mathMemory:
            return .lavender
        }
    }

    /// The Minik cats where an activity has one (Android Plus menu art), otherwise a
    /// little sum with counting objects, as Android Math Plus's hub cards.
    private static func cardVisual(for activity: MathProductionActivityID) -> MinikHubCardVisual {
        switch activity {
        case .learnMath:
            return MinikHubCardVisual(art: MinikPretty.Art.catStarPaper)
        case .mathCards:
            // The facts table.
            return MinikHubCardVisual(leadingGlyph: "3 × 4 = 12")
        case .mathPairs:
            return MinikHubCardVisual(art: MinikPretty.Art.pairs)
        case .buildNumber:
            return MinikHubCardVisual(leadingGlyph: "10 + 7")
        case .buildQuantity:
            return MinikHubCardVisual(objectName: "math_object_apple", objectCount: 5)
        case .visualToAnswer:
            return MinikHubCardVisual(objectName: "math_object_balloon", objectCount: 3, trailingGlyph: "= ?")
        case .answerToRepresentation:
            return MinikHubCardVisual(leadingGlyph: "4 =", objectName: "math_object_bee", objectCount: 4)
        case .buildMath:
            return MinikHubCardVisual(leadingGlyph: "□ + □")
        case .mathMixed:
            return MinikHubCardVisual(leadingGlyph: "+ − × ÷")
        case .mathSoccer:
            return MinikHubCardVisual(art: MinikPretty.Art.soccer)
        case .mathTower:
            return MinikHubCardVisual(art: MinikPretty.Art.tower)
        case .mathMemory:
            return MinikHubCardVisual(art: MinikPretty.Art.memory)
        case .pingPong:
            return MinikHubCardVisual(art: PingPongAssetNames.minikPong)
        }
    }

    @ViewBuilder
    private func languageDestination(
        for activity: LanguageActivityKind,
        language: LanguageIdentifier
    ) -> some View {
        switch activity {
        case .learn:
            if let session = languageFactory.makeLearnSession(for: language) {
                LearnView(
                    session: session,
                    presentation: .language,
                    onComplete: returnToHub,
                    onExit: returnToHub
                )
            } else {
                unavailableActivityView(title: activity.title)
            }
        case .multipleChoice:
            if let session = languageFactory.makeMultipleChoiceSession(for: language) {
                MultipleChoiceView(
                    session: session,
                    progressActivityFamily: .multipleChoice,
                    onAttempt: { recordLanguageAttempt($0, activity: activity) },
                    onComplete: returnToHub,
                    onExit: returnToHub
                )
            } else {
                unavailableActivityView(title: activity.title)
            }
        case .firstLetterChoices:
            if let session = languageFactory.makeFirstLetterChoicesSession(for: language) {
                MultipleChoiceView(
                    session: session,
                    progressActivityFamily: .multipleChoice,
                    presentation: .firstLetterPictureToLetter,
                    onAttempt: { recordLanguageAttempt($0, activity: activity) },
                    makeNextSession: { languageFactory.makeFirstLetterChoicesSession(for: language) },
                    onComplete: returnToHub,
                    onExit: returnToHub
                )
            } else {
                unavailableActivityView(title: activity.title)
            }
        case .firstLetterPictures:
            if let session = languageFactory.makeFirstLetterPicturesSession(for: language) {
                MultipleChoiceView(
                    session: session,
                    progressActivityFamily: .multipleChoice,
                    presentation: .firstLetterLetterToPicture,
                    onAttempt: { recordLanguageAttempt($0, activity: activity) },
                    makeNextSession: { languageFactory.makeFirstLetterPicturesSession(for: language) },
                    onComplete: returnToHub,
                    onExit: returnToHub
                )
            } else {
                unavailableActivityView(title: activity.title)
            }
        case .build:
            if let session = languageFactory.makeBuildSession(for: language) {
                BuildView(
                    session: session,
                    progressActivityFamily: .buildWord,
                    onAttempt: { recordLanguageAttempt($0, activity: activity) },
                    onComplete: returnToHub,
                    onExit: returnToHub
                )
            } else {
                unavailableActivityView(title: activity.title)
            }
        case .pairs:
            if let session = languageFactory.makePairsSession(for: language) {
                PairsView(
                    session: session,
                    progressActivityFamily: .pairs,
                    languageSkillID: LanguageSkillIDs.letterWordAssociation,
                    onAttempt: { recordLanguageAttempt($0, activity: activity) },
                    onComplete: returnToHub,
                    onExit: returnToHub
                )
            } else {
                unavailableActivityView(title: activity.title)
            }
        case .memory:
            if let session = languageFactory.makeMemorySession(for: language) {
                MemoryView(
                    session: session,
                    progressActivityFamily: .memory,
                    onAttempt: { recordLanguageAttempt($0, activity: activity) },
                    onComplete: returnToHub,
                    onExit: returnToHub
                )
            } else {
                unavailableActivityView(title: activity.title)
            }
        case .wordBuild:
            if let session = languageFactory.makeWordBuildSession(for: language) {
                BuildView(
                    session: session,
                    progressActivityFamily: .buildWord,
                    presentation: .word,
                    onAttempt: { recordLanguageAttempt($0, activity: activity) },
                    onWordCompleted: { recordLanguageWordCompletion($0, activity: activity) },
                    languageAutoEvaluationLevel: languageLevelSettings.wordLevel,
                    onLanguagePoolExhausted: recordLanguagePoolBoundary,
                    nextLanguageAutoEvaluationLevel: {
                        languageLevelRepository.load(for: configuration.variant).wordLevel
                    },
                    makeNextSession: {
                        reloadedLanguageFactory.makeWordBuildSession(for: language)
                    },
                    onComplete: returnToHub,
                    onAdvance: { recordLanguageAdOpportunity(.languageWriteScreen) },
                    onExit: returnToHub
                )
            } else {
                unavailableActivityView(title: activity.title)
            }
        case .letterPairs:
            if let session = languageFactory.makeLetterPairsSession(for: language) {
                PairsView(
                    session: session,
                    progressActivityFamily: .pairs,
                    languageSkillID: LanguageSkillIDs.initialLetterAssociation,
                    makeNextSession: {
                        languageFactory.makeLetterPairsSession(for: language)
                    },
                    onAttempt: { recordLanguageAttempt($0, activity: activity) },
                    onComplete: returnToHub,
                    onExit: returnToHub
                )
            } else {
                unavailableActivityView(title: activity.title)
            }
        case .imageToWord:
            if let session = languageFactory.makeImageToWordSession(for: language) {
                MultipleChoiceView(
                    session: session,
                    progressActivityFamily: .multipleChoice,
                    presentation: .pictureToWord,
                    onAttempt: { recordLanguageAttempt($0, activity: activity) },
                    makeNextSession: { languageFactory.makeImageToWordSession(for: language) },
                    onComplete: returnToHub,
                    onAdvance: { recordLanguageAdOpportunity(.languageWriteScreen) },
                    onExit: returnToHub
                )
            } else {
                unavailableActivityView(title: activity.title)
            }
        case .wordToImage:
            if let session = languageFactory.makeWordToImageSession(for: language) {
                MultipleChoiceView(
                    session: session,
                    progressActivityFamily: .multipleChoice,
                    presentation: .wordToPicture,
                    onAttempt: { recordLanguageAttempt($0, activity: activity) },
                    makeNextSession: { languageFactory.makeWordToImageSession(for: language) },
                    onComplete: returnToHub,
                    onAdvance: { recordLanguageAdOpportunity(.languageWriteScreen) },
                    onExit: returnToHub
                )
            } else {
                unavailableActivityView(title: activity.title)
            }
        case .wordMemory:
            if let session = languageFactory.makeWordMemorySession(for: language) {
                MemoryView(
                    session: session,
                    progressActivityFamily: .memory,
                    presentation: .languagePicture,
                    makeNextSession: {
                        languageFactory.makeWordMemorySession(for: language)
                    },
                    onLanguageGameCompleted: { eventID in
                        recordLanguagePictureMemoryCompletion(eventID: eventID)
                    },
                    onRoundCompleted: {
                        recordLanguageAdOpportunity(.languagePictureMemory)
                    },
                    onAttempt: { recordLanguageAttempt($0, activity: activity) },
                    onComplete: returnToHub,
                    onExit: returnToHub
                )
            } else {
                unavailableActivityView(title: activity.title)
            }
        case .wordCards:
            if let session = languageFactory.makeWordCardsSession(for: language) {
                CardsView(session: session, onExit: returnToHub)
            } else {
                unavailableActivityView(title: activity.title)
            }
        case .mixed:
            if let session = languageFactory.makeMixedPracticeSession(for: language) {
                LanguageMixedPracticeView(
                    session: session,
                    sessionFactory: languageFactory,
                    learnedLanguage: language,
                    onAttempt: { recordLanguageAttempt($0, activity: activity) },
                    onWordCompleted: { recordLanguageWordCompletion($0, activity: activity) },
                    onAdOpportunity: {
                        recordLanguageAdOpportunity(.languageWriteScreen)
                    },
                    onExit: returnToHub
                )
            } else {
                unavailableActivityView(title: activity.title)
            }
        case .soccer:
            if let practiceSession = languageFactory.makeSoccerPracticeSession(for: language) {
                LanguageSoccerView(
                    practiceSession: practiceSession,
                    productionConfiguration: LanguageSoccerProductionConfiguration(
                        parentSoccerLevel: languageLevelSettings.soccerLevel
                    ),
                    onAttempt: { recordLanguageAttempt($0, activity: activity) },
                    onMatchResolved: recordLanguageSoccerCompletion,
                    onWordCompleted: { recordLanguageAdOpportunity(.languageSoccer) },
                    onPoolExhausted: recordLanguagePoolBoundary,
                    makeNextPracticeSession: {
                        reloadedLanguageFactory.makeSoccerPracticeSession(for: language)
                    },
                    onExit: returnToHub
                )
            } else {
                unavailableActivityView(title: activity.title)
            }
        case .tower:
            if let practiceSession = languageFactory.makeTowerPracticeSession(for: language) {
                TowerView(
                    languagePracticeSession: practiceSession,
                    onAttempt: { recordLanguageAttempt($0, activity: activity) },
                    onWordCompleted: {
                        recordLanguageTowerCompletion($0)
                        recordLanguageAdOpportunity(.languageTower)
                    },
                    onPoolExhausted: recordLanguagePoolBoundary,
                    makeNextPracticeSession: {
                        reloadedLanguageFactory.makeTowerPracticeSession(for: language)
                    },
                    onExit: returnToHub
                )
            } else {
                unavailableActivityView(title: activity.title)
            }
        case .ticTacToe:
            // Defensive destination for direct callers. Normal hub routing uses
            // Route.ticTacToe and never passes the learned language into the game.
            TicTacToeView(
                onResolvedRound: recordLanguageTicTacToeCompletion,
                onCompletedRound: { recordLanguageAdOpportunity(.languageTicTacToe) },
                onExit: returnToHub
            )
        }
    }

    @ViewBuilder
    private func mathDestination(
        for activity: MathProductionActivityID,
        levelID: MathCurriculumLevelID
    ) -> some View {
        if activity.launchRoute(for: levelID) == .pingPong {
            MathPingPongChooser(
                commerce: commerceController,
                onCompletedMatch: { recordLanguageAdOpportunity(.mathRound) },
                onExit: returnToHub
            )
        } else if activity.launchRoute(for: levelID) == .m1Production,
                  let mathM1Factory,
                  let session = mathM1Factory.makeSession(for: activity) {
            MathM1SessionView(
                session: session,
                sessionFactory: mathM1Factory,
                onAttempt: { recordMathAttempt($0, activity: activity) },
                onComplete: completeMathRound,
                onExit: returnToHub
            )
        } else if activity.launchRoute(for: levelID) == .m2Production,
                  let mathM2Factory,
                  let session = mathM2Factory.makeSession(for: activity) {
            MathM2SessionView(
                session: session,
                sessionFactory: mathM2Factory,
                onAttempt: { recordMathAttempt($0, activity: activity) },
                onComplete: completeMathRound,
                onExit: returnToHub
            )
        } else if activity.launchRoute(for: levelID) == .m3Production,
                  let mathM3Factory,
                  let session = mathM3Factory.makeSession(for: activity) {
            MathM3SessionView(
                session: session,
                sessionFactory: mathM3Factory,
                onAttempt: { recordMathAttempt($0, activity: activity) },
                onComplete: completeMathRound,
                onExit: returnToHub
            )
        } else if activity.launchRoute(for: levelID) == .m4Production,
                  let mathM4Factory,
                  let session = mathM4Factory.makeSession(for: activity) {
            MathM4SessionView(
                session: session,
                sessionFactory: mathM4Factory,
                onAttempt: { recordMathAttempt($0, activity: activity) },
                onComplete: completeMathRound,
                onExit: returnToHub
            )
        } else if activity.launchRoute(for: levelID) == .m5Production,
                  let mathM5Factory,
                  let session = mathM5Factory.makeSession(for: activity) {
            MathM5SessionView(
                session: session,
                sessionFactory: mathM5Factory,
                onAttempt: { recordMathAttempt($0, activity: activity) },
                onComplete: completeMathRound,
                onExit: returnToHub
            )
        } else if activity.launchRoute(for: levelID) == .m6Production,
                  let mathM6Factory,
                  let session = mathM6Factory.makeSession(for: activity) {
            MathM6SessionView(
                session: session,
                sessionFactory: mathM6Factory,
                onAttempt: { recordMathAttempt($0, activity: activity) },
                onComplete: completeMathRound,
                onExit: returnToHub
            )
        } else if activity.launchRoute(for: levelID) == .m7Production,
                  let mathM7Factory,
                  let session = mathM7Factory.makeSession(for: activity) {
            MathM7SessionView(
                session: session,
                sessionFactory: mathM7Factory,
                onAttempt: { recordMathAttempt($0, activity: activity) },
                onComplete: completeMathRound,
                onExit: returnToHub
            )
        } else if activity.launchRoute(for: levelID) == .m8Production,
                  let mathM8Factory,
                  let session = mathM8Factory.makeSession(for: activity) {
            MathM8SessionView(
                session: session,
                sessionFactory: mathM8Factory,
                onAttempt: { recordMathAttempt($0, activity: activity) },
                onComplete: completeMathRound,
                onExit: returnToHub
            )
        } else if activity.launchRoute(for: levelID) == .m9Production,
                  let mathM9Factory,
                  let session = mathM9Factory.makeSession(for: activity) {
            MathM9SessionView(
                session: session,
                sessionFactory: mathM9Factory,
                onAttempt: { recordMathAttempt($0, activity: activity) },
                onComplete: completeMathRound,
                onExit: returnToHub
            )
        } else if activity.launchRoute(for: levelID) == .m10Production,
                  let mathM10Factory,
                  let session = mathM10Factory.makeSession(for: activity) {
            MathM10SessionView(
                session: session,
                sessionFactory: mathM10Factory,
                onAttempt: { recordMathAttempt($0, activity: activity) },
                onComplete: completeMathRound,
                onExit: returnToHub
            )
        } else if case .curriculumEngine(let engine)? = activity.launchRoute(for: levelID),
                  let session = mathFactory.makeSession(for: engine, levelID: levelID) {
            switch session {
            case .learn(let session):
                LearnView(session: session, onComplete: returnToHub, onExit: returnToHub)
            case .multipleChoice(let session):
                MultipleChoiceView(session: session, onComplete: returnToHub, onExit: returnToHub)
            case .build(let session):
                BuildView(session: session, onComplete: returnToHub, onExit: returnToHub)
            case .tower(let session):
                TowerView(session: session, onComplete: returnToHub, onExit: returnToHub)
            case .pairs(let session):
                PairsView(session: session, onComplete: returnToHub, onExit: returnToHub)
            case .memory(let session):
                MemoryView(session: session, onComplete: returnToHub, onExit: returnToHub)
            case .soccer(let session):
                SoccerView(session: session, onComplete: returnToHub, onExit: returnToHub)
            }
        } else {
            unavailableActivityView(title: activity.title)
        }
    }

    private func unavailableActivityView(title: String) -> some View {
        MinikHomeUnavailableView(
            title: String(
                format: String(localized: "%@ is unavailable right now"),
                title
            ),
            message: "This activity could not be loaded for the current product or content set.",
            onBack: returnToHub
        )
    }

    private func returnToHub() {
        // The stage's celebration page has already replaced the day's activity; a late
        // completion from that activity must not leave it. Only its own Close does.
        if case .mathDaily = route {
            return
        }
        // Android MathDailyScreen: leaving the day's activity, or finishing its round, goes
        // back to the daily page; the answers counted so far stay.
        if mathDailyIsPlaying {
            mathDailyIsPlaying = false
            if case .math = route {
                route = .mathDaily
                return
            }
        }
        if configuration.contentDomain == .language {
            languageMenuIsPresented = true
            switch route {
            case .language, .ticTacToe:
                submitLanguageRewardRecordCandidate()
            default:
                break
            }
        }
        route = nil
    }

    private func submitLanguageRewardRecordCandidate() {
        let state = ((try? rewardRepository.loadLedger()) ?? RewardLedger()).state(
            for: RewardScope(ownerID: .localDefault, product: configuration.variant)
        )
        // The record belongs to the playing child's own public identity; the
        // submission keeps it even if another child is chosen meanwhile.
        let profiles = childProfiles
        let learner = profiles.activeLearner
        let scope = RewardScope(ownerID: learner.rewardOwnerID, product: configuration.variant)
        let noticeKey = "\(state.points)-\(state.bestStreak)"
        let rewardRecordSubmissionService = self.rewardRecordSubmissionService
        Task {
            let result = await rewardRecordSubmissionService.submit(
                state: state,
                scope: scope,
                achievedAt: Date()
            )
            await MainActor.run {
                // An alias prompt or Top 20 for a child no longer playing is not shown.
                guard profiles.activeLearner == learner else { return }
                handleRecordSubmission(result, noticeKey: noticeKey)
            }
        }
    }

    private var publicAliasPrompt: some View {
        ZStack {
            Color.black.opacity(0.38).ignoresSafeArea()
            VStack(spacing: 18) {
                Text("Great score!")
                    .font(.title.bold())
                    .foregroundStyle(Color(red: 0.12, green: 0.37, blue: 0.46))
                Text("Choose a fun public alias for the online leaderboard.")
                    .font(.body.weight(.medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color(red: 0.27, green: 0.45, blue: 0.53))

                VStack(spacing: 10) {
                    ForEach(publicAliasChoices) { alias in
                        Button {
                            selectPublicAlias(alias)
                        } label: {
                            HStack(spacing: 12) {
                                if let avatar = alias.avatar {
                                    Image(systemName: avatar.symbolName)
                                        .frame(width: 24)
                                }
                                Text(verbatim: alias.publicAlias)
                                    .font(.headline)
                                Spacer()
                                Image(systemName: "checkmark.circle")
                                    .accessibilityHidden(true)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(publicAliasIsSaving)
                    }
                }

                Button("Show different aliases") { rerollPublicAliases() }
                    .buttonStyle(.plain)
                    .disabled(publicAliasIsSaving)

                Text("Nothing is shared before you choose a public alias.")
                    .font(.footnote.weight(.medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color(red: 0.35, green: 0.47, blue: 0.52))

                HStack(spacing: 14) {
                    Button("Not now") {
                        publicAliasPromptIsPresented = false
                        Task { await rewardRecordSubmissionService.dismissPublicAliasPrompt() }
                    }
                        .buttonStyle(.bordered)
                        .disabled(publicAliasIsSaving)
                }
                if publicAliasIsSaving {
                    ProgressView()
                        .accessibilityLabel(String(localized: "Choosing alias"))
                }
            }
            .padding(28)
            .frame(maxWidth: 480)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(24)
        }
        .transition(.opacity)
        .accessibilityAddTraits(.isModal)
    }

    private var pendingPublicationNotice: some View {
        ZStack {
            Color.black.opacity(0.38).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color(red: 0.24, green: 0.64, blue: 0.45))
                    .accessibilityHidden(true)
                Text("Saved on this device")
                    .font(.title2.bold())
                    .foregroundStyle(Color(red: 0.12, green: 0.37, blue: 0.46))
                Text("This score is ready to publish when Online leaderboard is on and Firebase is available.")
                    .font(.body.weight(.medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color(red: 0.27, green: 0.45, blue: 0.53))
                Button("Done") { pendingPublicationNoticeIsPresented = false }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            .padding(28)
            .frame(maxWidth: 480)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(24)
        }
        .transition(.opacity)
        .accessibilityAddTraits(.isModal)
    }

    /// `noticeKey` identifies the local best; "Saved on this device" is shown at
    /// most once per best, and never for a parent opt-out or an unconfigured build.
    private func handleRecordSubmission(_ result: RewardRecordSyncResult, noticeKey: String? = nil) {
        switch result {
        case .publicAliasRequired:
            rerollPublicAliases()
            publicAliasPromptIsPresented = true
        case .participationDisabled, .notConfigured:
            publicAliasPromptIsPresented = false
        case .failed:
            publicAliasPromptIsPresented = false
            if noticeKey == nil || noticeKey != lastPendingNoticeKey {
                lastPendingNoticeKey = noticeKey
                pendingPublicationNoticeIsPresented = true
            }
        case .saved(let placements):
            publicAliasPromptIsPresented = false
            if !placements.isEmpty {
                route = .recordsLeaderboard(placements)
            }
        case .noEligibleValue, .noNewRecord:
            break
        }
    }

    private func selectPublicAlias(_ alias: PublicLeaderboardAlias) {
        publicAliasIsSaving = true
        Task {
            let result = await rewardRecordSubmissionService.selectPublicAliasAndRetry(alias)
            await MainActor.run {
                publicAliasIsSaving = false
                publicAliasPromptIsPresented = false
                handleRecordSubmission(result)
            }
        }
    }

    private func rerollPublicAliases() {
        publicAliasChoices = PublicLeaderboardAliasGenerator().choices()
    }

    /// Like Android Math, a finished Math round is an ad opportunity.
    private func completeMathRound() {
        recordLanguageAdOpportunity(.mathRound)
        returnToHub()
    }

    private func recordLanguageAdOpportunity(_ opportunity: MinikAdOpportunity) {
        let removesAds = commerceController.isRemoveAdsActive
        let ownershipResolved = commerceController.ownershipResolved
        Task {
            await adCoordinator.record(opportunity, isRemoveAdsActive: removesAds, ownershipResolved: ownershipResolved)
        }
    }

    private func recordPingPongCompletedMatch() {
        pingPongCompletedMatchCount += 1
        let isOpportunity = PingPongInterstitialPolicy().isOpportunity(
            afterCompletedMatch: pingPongCompletedMatchCount
        )
        guard isOpportunity else { return }
        let removesAds = commerceController.isRemoveAdsActive
        let ownershipResolved = commerceController.ownershipResolved
        Task {
            await adCoordinator.record(.pingPongMatch, isRemoveAdsActive: removesAds, ownershipResolved: ownershipResolved)
        }
    }

    private func selectLearnedLanguage(_ language: LanguageIdentifier) {
        guard configuration.allowsLearnedLanguage(language) else { return }
        selectedLanguage = configuration.fixedLearnedLanguage ?? language
        learnedLanguageRepository.save(selectedLanguage, for: configuration)
    }

    private func setMathLevelMode(_ mode: MathLevelMode) {
        guard configuration.contentDomain == .math else { return }
        switch mode {
        case .automatic:
            mathLevelController.returnToAutomatic()
        case .manual:
            mathLevelController.setManualLevel(mathLevelController.state.activeLevelID)
        }
        LocalMathLevelRepository().save(mathLevelController.state)
    }

    private func selectManualMathLevel(_ levelID: MathCurriculumLevelID) {
        guard configuration.contentDomain == .math,
              mathLevelController.state.mode == .manual else { return }
        mathLevelController.setManualLevel(levelID)
        LocalMathLevelRepository().save(mathLevelController.state)
    }

    private var selectedMathLevel: MathCurriculumLevelDescriptor {
        MathCurriculumPolicy.level(for: selectedMathLevelID)
            ?? MathCurriculumPolicy.defaultRunnableLevel
    }

    private var selectedMathLevelID: MathCurriculumLevelID {
        mathLevelController.state.activeLevelID
    }

    private func recordMathAttempt(
        _ attempt: ActivityAttemptData,
        activity: MathProductionActivityID
    ) {
        let context = ActivityEventContext(
            product: .minikMath,
            activityID: ProgressActivityID(rawValue: "math.\(activity.rawValue)"),
            curriculumStageID: attempt.mathLevelID?.curriculumStageID,
            skillID: attempt.skillID
        )
        if let event = ActivityEvent(
            sessionID: mathActivitySessionID,
            context: context,
            kind: .gradedAttempt,
            occurredAt: Date(),
            attemptData: attempt
        ) {
            try? outcomeDispatcher.dispatch(event)
        }
        mathLevelController.record(attempt)
        LocalMathLevelRepository().save(mathLevelController.state)
        recordMathDailyAnswer(attempt, activity: activity)
    }

    // MARK: - Daily math journey (Android Minik Math Plus MathDailyScreen)

    /// Let's start!: the activity of the day at the learner's current level.
    private func startMathDailyActivity() {
        mathDailyFinished = false
        mathDailyIsPlaying = true
        route = .math(mathDailyJourney.activity, selectedMathLevelID, UUID())
        mathActivitySessionID = ActivitySessionID()
    }

    /// Android MathDailyScreen (64da76d): leaving the stage's celebration ends a round, so it is
    /// an ad opportunity like the end of a practice round; the ad covers the daily page.
    private func acknowledgeMathDaily() {
        recordLanguageAdOpportunity(.mathRound)
        mathDailyFinished = false
    }

    private func closeMathDaily() {
        mathDailyIsPlaying = false
        route = nil
    }

    /// Android AppState.recordDaily: only answers in the day's activity, played from the
    /// daily page, count. The answer that reaches the goal completes the stage and shows the
    /// celebration at once, as Android does.
    private func recordMathDailyAnswer(_ attempt: ActivityAttemptData, activity: MathProductionActivityID) {
        guard mathDailyIsPlaying,
              !mathDailyFinished,
              activity == mathDailyJourney.activity,
              MathDailyJourneyPolicy.counts(attempt) else { return }
        var journey = mathDailyJourney
        let completed = journey.recordCountedAnswer(on: MinikLearningDay.string())
        mathDailyJourney = journey
        MathDailyJourneyRepository().save(journey)
        guard completed else { return }
        mathDailyIsPlaying = false
        mathDailyFinished = true
        route = .mathDaily
    }

    /// Android ActivityFrame's daily line (LocalDailyProgress) under the activity's header.
    private var mathDailyProgressLine: some View {
        Text(verbatim: String(
            format: String(localized: "Correct answers: %lld of %lld"),
            Int64(mathDailyJourney.answers),
            Int64(mathDailyJourney.goal)
        ))
        .font(MinikPretty.titleFont(16))
        .foregroundStyle(MinikPretty.navy)
        .multilineTextAlignment(.center)
        .lineLimit(2)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .background {
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.94))
        }
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(MinikPretty.lavenderRim, lineWidth: 1.5)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity)
        .accessibilityAddTraits(.updatesFrequently)
    }

    // MARK: - Daily learning (Android Minik DailyLearning)

    /// Android AppSharedPreferencesCache.savePoints and DailyLearning.record: a play that
    /// raised the playing child's points is one of today's little wins in the learned
    /// language, and the fifth shows Android's toast. Choosing another child changes the
    /// points shown without play, so learnerDidChange refreshes them without this.
    private func refreshLanguageRewardsAfterPlay() {
        let previousPoints = languageRewards.points
        let updated = ((try? rewardRepository.loadLedger()) ?? RewardLedger()).state(
            for: RewardScope(ownerID: .localDefault, product: configuration.variant)
        )
        languageRewards = updated
        guard configuration.contentDomain == .language else { return }
        let completed = MinikDailyLearningRepository(product: configuration.variant).record(
            language: selectedLanguage,
            previousPoints: previousPoints,
            nextPoints: updated.points
        )
        if completed {
            showDailyLearningToast()
        }
    }

    /// Android Toast.LENGTH_LONG: three and a half seconds, then it fades.
    private func showDailyLearningToast() {
        let message = interfaceLocaleID.text("Five little wins today. Well done!")
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            dailyLearningToast = message
        }
        UIAccessibility.post(notification: .announcement, argument: message)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard dailyLearningToast == message else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) {
                dailyLearningToast = nil
            }
        }
    }

    private func dailyLearningToastView(_ message: String) -> some View {
        Text(verbatim: message)
            .font(MinikPretty.titleFont(17))
            .foregroundStyle(Color.white)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background {
                Capsule(style: .continuous)
                    .fill(MinikPretty.navy.opacity(0.92))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .environment(\.layoutDirection, interfaceLocaleID.layoutDirection)
    }

    private func recordLanguageAttempt(
        _ attempt: ActivityAttemptData,
        activity: LanguageActivityKind
    ) {
        let context = ActivityEventContext(
            product: configuration.variant,
            activityID: ProgressActivityID(rawValue: "language.\(activity.rawValue)"),
            skillID: attempt.skillID
        )
        guard let event = ActivityEvent(
            sessionID: languageActivitySessionID,
            context: context,
            kind: .gradedAttempt,
            occurredAt: Date(),
            attemptData: attempt
        ) else { return }
        try? outcomeDispatcher.dispatch(event)
        if let autoActivity = LanguageAutoEvidenceRouting.attemptActivity(
            for: attempt.activityFamily
        ),
           let contentItemID = attempt.languageContentItemID,
           let vocabularyLevel = attempt.languageVocabularyLevel {
            languageAutoState.record(
                id: event.id,
                evidence: LanguageAutoAttemptEvidence(
                    contentItemID: contentItemID,
                    vocabularyLevel: vocabularyLevel,
                    activity: autoActivity,
                    result: attempt.result
                )
            )
            languageAutoRepository.save(languageAutoState)
        }
        languageWordBonusRun = wordRewardService.cleanWordRun
        refreshLanguageRewardsAfterPlay()
    }

    private func recordLanguageWordCompletion(_ completion: LanguageWordCompletion, activity: LanguageActivityKind) {
        guard configuration.contentDomain == .language, activity == .wordBuild || activity == .mixed else { return }
        let now = Date()
        if let autoActivity = LanguageAutoEvidenceRouting.completionActivity(for: activity),
           let vocabularyLevel = completion.vocabularyLevel {
            languageAutoState.record(
                id: completion.id,
                evidence: LanguageAutoAttemptEvidence(
                    contentItemID: completion.contentItemID,
                    vocabularyLevel: vocabularyLevel,
                    activity: autoActivity,
                    result: .correct
                )
            )
            languageAutoRepository.save(languageAutoState)
        }
        try? wordRewardService.processCompletion(completion, sessionID: languageActivitySessionID,
                                                product: configuration.variant, occurredAt: now)
        if let event = ActivityEvent(id: completion.id, sessionID: languageActivitySessionID,
            context: ActivityEventContext(product: configuration.variant,
                activityID: ProgressActivityID(rawValue: "language.\(activity.rawValue)"), skillID: LanguageSkillIDs.wordConstruction),
            kind: .completed, occurredAt: now) {
            try? outcomeDispatcher.dispatch(event)
        }
        languageWordBonusRun = wordRewardService.cleanWordRun
        refreshLanguageRewardsAfterPlay()
    }

    private func setLanguageLevels(_ settings: LanguageParentLevelSettings) {
        guard configuration.contentDomain == .language else { return }
        languageLevelSettings = settings
        languageLevelRepository.save(settings, for: configuration.variant)
        languageAutoState.synchronizeCurrentLevel(settings.wordLevel)
        languageAutoRepository.save(languageAutoState)
    }

    private func recordLanguagePoolBoundary(_ boundary: LanguageAutoPoolBoundary) {
        guard configuration.contentDomain == .language else { return }
        var updatedSettings = languageLevelSettings
        let evaluation = languageAutoState.evaluate(
            boundary,
            settings: &updatedSettings
        )
        if case .promoted = evaluation {
            languageLevelSettings = updatedSettings
            languageLevelRepository.save(updatedSettings, for: configuration.variant)
        }
        languageAutoRepository.save(languageAutoState)
    }

    private func recordLanguageTowerCompletion(_ completion: LanguageTowerCompletion) {
        guard configuration.contentDomain == .language else { return }
        let event = ActivityEvent(
            id: completion.id,
            sessionID: languageActivitySessionID,
            context: ActivityEventContext(
                product: configuration.variant,
                activityID: ProgressActivityID(rawValue: "language.tower"),
                skillID: LanguageSkillIDs.wordConstruction
            ),
            kind: .completed,
            occurredAt: Date()
        )
        guard let event else { return }
        try? outcomeDispatcher.dispatch(event)
        refreshLanguageRewardsAfterPlay()
    }

    private func recordLanguagePictureMemoryCompletion(eventID: UUID) {
        let event = ActivityEvent(
            id: eventID,
            sessionID: languageActivitySessionID,
            context: ActivityEventContext(
                product: configuration.variant,
                activityID: ProgressActivityID(rawValue: "language.wordMemory"),
                skillID: LanguageSkillIDs.wordImageAssociation
            ),
            kind: .completed,
            occurredAt: Date()
        )
        guard let event else { return }
        try? outcomeDispatcher.dispatch(event)
        refreshLanguageRewardsAfterPlay()
    }

    private func recordLanguageSoccerCompletion(_ outcome: LanguageSoccerMatchOutcome) {
        let eventID = UUID()
        let occurredAt = Date()
        if let reward = LanguageSoccerRewardMapper.rewardEvent(
            sourceEventID: eventID,
            product: configuration.variant,
            outcome: outcome,
            occurredAt: occurredAt
        ) {
            _ = try? rewardService.process(reward, policy: .androidSoccerReference)
        }
        refreshLanguageRewardsAfterPlay()
    }

    private func recordLanguageTicTacToeCompletion(_ outcome: TicTacToeOutcome) {
        let eventID = UUID()
        let occurredAt = Date()
        if let reward = LanguageTicTacToeRewardMapper.rewardEvent(
            sourceEventID: eventID,
            product: configuration.variant,
            outcome: outcome,
            occurredAt: occurredAt
        ) {
            _ = try? rewardService.process(reward, policy: .androidTicTacToeReference)
        }
        refreshLanguageRewardsAfterPlay()
    }

    private func refreshLanguageRewards() {
        languageRewards = ((try? rewardRepository.loadLedger()) ?? RewardLedger()).state(
            for: RewardScope(ownerID: .localDefault, product: configuration.variant)
        )
    }

    private var progressReadModel: EducationalProgressReadModel {
        EducationalProgressReadModelBuilder.make(
            snapshot: (try? progressRepository.loadSnapshot()) ?? ProgressSnapshot(),
            product: configuration.variant,
            mathLevelState: configuration.contentDomain == .math
                ? mathLevelController.state
                : nil
        )
    }

    private var recordsReadModel: LocalRecordsReadModel {
        LocalRecordsReadModelBuilder.make(
            ledger: (try? rewardRepository.loadLedger()) ?? RewardLedger(),
            product: configuration.variant
        )
    }

    private var headerSubtitle: String {
        switch configuration.contentDomain {
        case .language:
            return String(localized: "Jump into playful reading activities.")
        case .math:
            return String(localized: "Pick a math adventure and start playing.")
        case .game:
            return String(localized: "Play with Minik.")
        }
    }

    private static func defaultLearnedLanguage(for configuration: ProductConfiguration) -> LanguageIdentifier {
        configuration.fixedLearnedLanguage ??
            configuration.allowedLearnedLanguages.sorted { $0.rawValue < $1.rawValue }.first ??
            .english
    }
}

/// The hub's sizes: the phone values, and on iPad (both sides at least 600 points)
/// larger ones, a little larger still on the bigger iPads, as Android's sw600dp
/// dimensions are.
private struct MinikHubMetrics {
    let tablet: Bool
    let scale: CGFloat

    init(size: CGSize) {
        let shortSide = min(size.width, size.height)
        let isTablet = shortSide >= 600
        tablet = isTablet
        scale = isTablet ? min(1.3, max(1, shortSide / 744)) : 1
    }

    private func value(_ phone: CGFloat, _ tabletValue: CGFloat) -> CGFloat {
        tablet ? tabletValue * scale : phone
    }

    // The logo row on the sky.
    var logoSize: CGFloat { value(64, 104) }
    var headerGap: CGFloat { value(10, 18) }
    var roundButton: CGFloat { value(52, 76) }
    var trophyPadding: CGFloat { value(11, 15) }
    var parentButtonTextSize: CGFloat { value(17, 23) }
    var parentButtonHeight: CGFloat { value(48, 60) }
    var screenMargin: CGFloat { value(14, 32) }
    var topMargin: CGFloat { value(6, 16) }

    // The glass panel.
    var panelMargin: CGFloat { value(12, 32) }
    var panelTopMargin: CGFloat { value(8, 14) }
    var panelBottomMargin: CGFloat { value(10, 18) }
    var panelRadius: CGFloat { value(28, 36) }
    var panelMaxWidth: CGFloat { value(720, 900) }
    var panelPadding: CGFloat { value(12, 22) }
    var panelPaddingTop: CGFloat { value(14, 22) }
    var panelPaddingBottom: CGFloat { value(24, 34) }

    // Sections and cards.
    var sectionTopGap: CGFloat { value(20, 28) }
    var sectionGap: CGFloat { value(10, 14) }
    var cardGap: CGFloat { value(12, 18) }
    var cardMinWidth: CGFloat { value(140, 200) }
    var cardPadding: CGFloat { value(6, 10) }
    var cardPaddingBottom: CGFloat { value(9, 13) }
    var cardRadius: CGFloat { value(22, 26) }
    var cardArtHeight: CGFloat { value(84, 128) }
    var cardLabelGap: CGFloat { value(4, 6) }
    var cardLabelRadius: CGFloat { value(16, 18) }
    var cardTitleSize: CGFloat { value(15, 20) }
    var cardSubtitleSize: CGFloat { value(12, 15) }
    var glyphSize: CGFloat { value(26, 36) }
    var objectSize: CGFloat { value(20, 28) }

    // The level card.
    var levelArtHeight: CGFloat { value(58, 92) }
    var levelTitleSize: CGFloat { value(19, 26) }
    var levelSubtitleSize: CGFloat { value(14, 18) }
}

/// What a hub card shows above its name: a Minik picture, or a little sum with
/// counting objects.
private struct MinikHubCardVisual {
    var art: String? = nil
    var leadingGlyph: String? = nil
    var objectName: String? = nil
    var objectCount: Int = 0
    var trailingGlyph: String? = nil
}

/// Where the Math hub's board, its rows and its end are while it scrolls. A plain class, so
/// recording positions as the board moves does not redraw the hub.
private final class MinikHubScrollTracker {
    var viewport: CGRect = .zero
    var endMinY: CGFloat = 0
    var targetMinY: [String: CGFloat] = [:]
}

/// The scroll targets of the Math hub's board.
private enum MinikHubScrollID {
    static let daily = "math-hub.daily"
    static let level = "math-hub.level"
    static let end = "math-hub.end"

    static func banner(_ sectionID: String) -> String {
        "math-hub.banner." + sectionID
    }

    static func row(_ sectionID: String, _ index: Int) -> String {
        "math-hub.row.\(sectionID).\(index)"
    }
}

/// Reports a view's frame in global coordinates when it appears and whenever it moves, as
/// scrolling does (as LanguageMenuPositionProbe does for the Language menu).
private struct MinikHubPositionProbe: View {
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
