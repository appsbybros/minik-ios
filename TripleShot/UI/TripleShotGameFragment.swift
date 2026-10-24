import Foundation

/// Port of `ui/TripleShotGameFragment.kt` (Android 6c38131), part 1: Kotlin lines 1-1949 (DESIGN 2.9).
///
/// This file declares the class, ALL stored properties of the whole Kotlin class (L66-209), every override of the
/// whole Kotlin file (DESIGN 2.10: `onDestroyView` forwards to `onDestroyView_impl` of part 2) and translates, in
/// Kotlin order, every member of L211-1948: config from the arguments, insets, court / sensor wiring, court touch
/// routing, the question / answer flow, the sensor listener, knowledge recording, `performShot`, the Live HORSE
/// dispatcher and the local HORSE turn loop up to the bot's choices. It also builds the view tree of
/// `res/layout/fragment_triple_shot_game.xml` in code (`TripleShotGameLayout`, registered for
/// `R.layout.fragment_triple_shot_game`), with the same ids, attributes and params as the XML.
///
/// Part 2 (Kotlin L1950-3886, `TripleShotGameFragment+Part2.swift`, owner s-game2) holds the remaining methods, the
/// nested `TutorialStep` (Kotlin L58-64) and the companion constants and `newInstance` as statics.
///
/// Members are `internal` (Kotlin `private` inside a class split over several files, DESIGN 2.1). Argument labels are
/// the Kotlin parameter names (DESIGN 2.1). Units are Android pixels (DESIGN 2.5). Closures kept by views, the
/// Handler, the court, dialogs or Firebase capture `self` weakly (Android's GC collects such cycles, ARC does not);
/// each of them re-checks `isAdded` / `ended` exactly like the Kotlin code, so behaviour is unchanged while the
/// fragment exists.
///
/// iOS-only addition (DESIGN 2.8 / 12.3): Android leaves this screen with the system Back button in every mode and
/// phase (L324-331); iOS has none. The Kotlin OnBackPressedCallback is kept, and the layout gets one small exit
/// control at the top-end of the HUD row (`TripleShotGameFragment.IOS_EXIT_BUTTON_ID`: the app's `triple_close` art,
/// 36 x 36 dp, content description "Exit game" / "יציאה מהמשחק") that runs exactly what Back runs there:
/// `leaveGameToHome()`. The HUD keeps its XML geometry except that its end edge now stops at that control.
final class TripleShotGameFragment: AFragment, TripleShotSensorController.Listener {

    // Kotlin L58-64 `private enum class TutorialStep { CHOOSE_ANSWER, AIM, PULL_BACK, THROW, FREE_PLAY }` is declared
    // by part 2 (`extension TripleShotGameFragment { enum TutorialStep: String, KotlinEnum { ... } }`).

    let handler = AHandler(ALooper.getMainLooper())
    lazy var firebase: TripleShotFirebaseRepository = TripleShotFirebaseRepository()
    let scoring = TripleShotScoringEngine()
    var botOpponent: TripleShotBotOpponent? = nil
    var botTurnCounter = 0

    var horseEngine: HorseGameEngine? = nil
    var horseQuestion: TripleShotQuestion? = nil
    var horseQuestionCounter = 0
    var horsePendingCategory: QuestionCategory? = nil
    var horseSelectedCategory: QuestionCategory? = nil
    var horseTopicPromptShown = false
    var horseWaitingForSpot = false
    var horseTurnMessage = ""
    var horseRecentQuestionIds: [String] = []

    var horseMoveTouchActive = false
    var horseMoveLastX: Float = 0
    var horseMoveLastY: Float = 0
    var horseMoveDownX: Float = 0
    var horseMoveDownY: Float = 0
    var horseMoveHasDragged = false

    lazy var tutorialPreferences: ASharedPreferences =
        requireContext().getSharedPreferences(
            TripleShotGameFragment.TUTORIAL_PREFS,
            MODE_PRIVATE
        )

    /// Kotlin `lateinit var config`.
    var config: TripleShotGameConfig!
    /// Kotlin `lateinit var questions: List<TripleShotQuestion>` (the repository's lazy 4096-entry adaptive list).
    var questions: AdaptiveQuestionList!

    var questionIndex = 0
    var selectedAnswerIndex = -1

    /*
     * Knowledge progress is written as soon as the human locks an answer, not after
     * the basket. This keeps learning stats independent from shooting skill.
     * The guard prevents a double tap / recreated answer view from counting twice.
     */
    var knowledgeAnswerRecorded = false

    var shotInProgress = false
    var feedbackShowing = false
    var feedbackContinueAction: (() -> Void)? = nil
    var feedbackTapOverlay: AView? = nil
    /// Kotlin `private var persistentExit: Button?` (declared before addChallengeExitLink, L2598).
    var persistentExit: AButton? = nil
    var ended = false
    var secondsLeft = 90
    /// Write-only on Android (spec 13 §8.23); kept as it is.
    var fallbackSensors = false


    var tutorialActive = false
    var tutorialPage = TutorialStep.CHOOSE_ANSWER.ordinal
    var tutorialProgress = TutorialStep.CHOOSE_ANSWER.ordinal

    /// Write-only on Android (assigned in showQuestion and onShotPhaseChanged, never read).
    var currentShotPhase =
        TripleShotSensorController.ShotPhase.WAITING_FOR_ANSWER

    var sensor: TripleShotSensorController!
    var courtView: TripleShotCourtView!
    var gameBackground: AImageView!

    var scoreText: ATextView!
    var ballsText: ATextView!
    var timeText: ATextView!
    var botScoreText: ATextView!
    var questionText: ATextView!
    var categoryText: ATextView!
    var feedbackText: ATextView!
    var streakText: ATextView!

    var topHud: AView!
    var questionCard: AView!
    var answerStrip: ALinearLayout!

    var tutorialHelpButton: AButton!
    var tutorialCard: AView!
    var tutorialTitle: ATextView!
    var tutorialBody: ATextView!
    var tutorialPrevButton: AButton!
    var tutorialNextButton: AButton!
    var tutorialDismissButton: AButton!

    var opponentsScroll: AHorizontalScrollView!
    var opponentsContainer: ALinearLayout!

    var resultOverlay: AView!
    var resultScoreText: ATextView!
    var resultStatsText: ATextView!
    var resultRankText: ATextView!

    var answerViews: [ATextView] = []

    // A marker can be tapped as an alternative to the rectangular answer button.
    var pendingStationTap = -1
    var stationTapDownX: Float = 0
    var stationTapDownY: Float = 0

    var roomPlayersHandle:
        TripleShotFirebaseRepository.ListenerHandle? = nil
    var roomShotsHandle:
        TripleShotFirebaseRepository.ListenerHandle? = nil
    var liveHorseHandle:
        TripleShotFirebaseRepository.ListenerHandle? = nil
    /// Kotlin `mutableSetOf<String>()` (LinkedHashSet; part 2 uses its Kotlin `add` / `clear`).
    var seenLiveShotIds = KLinkedSet<String>()
    var latestLivePlayers: [LivePlayerState] = []
    var liveHorseState: LiveHorseState? = nil
    var liveHorseLastHandledTurn = -1
    var liveHorseFinishedShown = false

    /// Kotlin `private val clockRunnable = object : Runnable { ... }` (L177-209): one ARunnable instance, re-posted by
    /// identity. The Kotlin inner object holds the fragment strongly; here the capture is weak so the lazily created
    /// runnable does not keep the fragment alive forever (a posted run of a released fragment is a no-op, as the
    /// `!isAdded` return is on Android).
    lazy var clockRunnable: ARunnable = ARunnable(withSelf: { [weak self] runnable in
        guard let self else { return }
        if !self.isAdded || self.ended { return }

        /*
         * Shooting Challenge is a real wall-clock challenge: aiming, flight and
         * feedback do not pause the 60-second timer. If time expires while a ball
         * is already in flight, that shot is allowed to finish before results show.
         */
        if self.config.limitMode != GameLimitMode.BALLS_ONLY {
            if self.config.isMultiplayer && self.config.roomStartedAtMs > 0 {
                let deadline =
                    self.config.roomStartedAtMs + Int64(self.config.timeLimitSeconds) * 1000
                let remainingMs =
                    (deadline - ASystem.currentTimeMillis()).coerceAtLeast(0)
                self.secondsLeft = ((remainingMs + 999) / 1000).toInt()
            } else {
                self.secondsLeft = (self.secondsLeft - 1).coerceAtLeast(0)
            }
            self.updateHud()

            if self.secondsLeft <= 0 {
                if !self.shotInProgress && !self.feedbackShowing {
                    self.endGame()
                }
                return
            }
        }

        self.handler.postDelayed(runnable, 1000)
    })

    // MARK: - iOS-only exit control (DESIGN 12.3)

    /// View id of the iOS-only exit control the layout adds at the top-end of the HUD row (no Android counterpart).
    static let IOS_EXIT_BUTTON_ID = "tripleShotGameIosExitButton"

    /// Registers the Swift builder of `R.layout.fragment_triple_shot_game` once (ALayoutInflater).
    private static let layoutRegistration: Void = {
        ALayoutInflater.register(R.layout.fragment_triple_shot_game) { _ in
            TripleShotGameLayout.build()
        }
    }()

    /// Kotlin `TripleShotGameFragment : Fragment(R.layout.fragment_triple_shot_game)`.
    override init() {
        super.init(contentLayoutId: R.layout.fragment_triple_shot_game)
        _ = TripleShotGameFragment.layoutRegistration
    }

    // MARK: - Lifecycle (L211-666)

    override func onCreate(_ savedInstanceState: ABundle?) {
        super.onCreate(savedInstanceState)

        TripleShotQuestionRepository.initialize(context: requireContext())

        let mode =
            GameLimitMode.named(
                requireArguments().getString(TripleShotGameFragment.ARG_MODE) ?? ""
            ) ?? GameLimitMode.TIME_ONLY

        // runCatching { GameType.valueOf(...) }.getOrDefault(default): the parse first, then the default argument.
        let parsedGameType =
            GameType.named(
                requireArguments()
                    .getString(TripleShotGameFragment.ARG_GAME_TYPE) ?? ""
            )
        let roomArgument = requireArguments().getString(TripleShotGameFragment.ARG_ROOM)
        let defaultGameType =
            if
                mode == GameLimitMode.BALLS_ONLY &&
                (roomArgument == nil || roomArgument!.kotlinIsBlank)
            {
                GameType.PRACTICE
            } else {
                GameType.SHOOTING_CHALLENGE
            }
        let gameType = parsedGameType ?? defaultGameType

        var selectedCategories =
            KLinkedSet(
                (requireArguments()
                    .getStringArrayList(TripleShotGameFragment.ARG_CATEGORIES) ?? [])
                    .compactMap { name in
                        QuestionCategory.named(name)
                    }
            )
        if selectedCategories.isEmpty {
            selectedCategories = KLinkedSet(QuestionCategory.allCases)
        }

        let playerNameArg = requireArguments().getString(TripleShotGameFragment.ARG_NAME) ?? ""
        let playerCharacterArg = requireArguments().getString(TripleShotGameFragment.ARG_PLAYER_CHARACTER) ?? ""
        let botCharacterArg = requireArguments().getString(TripleShotGameFragment.ARG_BOT_CHARACTER) ?? ""
        config = TripleShotGameConfig(
            playerName:
                playerNameArg.kotlinIsBlank ? "Player" : playerNameArg,
            gameType: gameType,
            limitMode: mode,
            selectedCategories: selectedCategories,
            roomId: requireArguments().getString(TripleShotGameFragment.ARG_ROOM),
            roomStartedAtMs: requireArguments().getLong(TripleShotGameFragment.ARG_ROOM_STARTED_AT, 0),
            botMatch: requireArguments().getBoolean(TripleShotGameFragment.ARG_BOT_MATCH, false),
            playerCharacterId:
                playerCharacterArg.kotlinIsBlank ? TripleShotCharacterRoster.ID_WOMAN_DARK : playerCharacterArg,
            botCharacterId:
                botCharacterArg.kotlinIsBlank ? TripleShotCharacterRoster.ID_BOB : botCharacterArg,
            seed:
                requireArguments().getLong(
                    TripleShotGameFragment.ARG_SEED,
                    ASystem.currentTimeMillis()
                ),
            ballLimit:
                requireArguments().getInt(
                    TripleShotGameFragment.ARG_BALL_LIMIT,
                    20
                ),
            timeLimitSeconds:
                requireArguments().getInt(
                    TripleShotGameFragment.ARG_TIME_LIMIT_SECONDS,
                    gameType ==
                        GameType.SHOOTING_CHALLENGE
                        ? 60
                        : 90
                )
        )

        questions =
            TripleShotQuestionRepository.shuffled(
                seed: config.seed,
                categories: config.selectedCategories
            )

        secondsLeft = config.timeLimitSeconds
    }

    override func onViewCreated(
        _ view: AView,
        _ savedInstanceState: ABundle?
    ) {
        super.onViewCreated(view, savedInstanceState)
        applyGameplayInsets(root: view, window: requireActivity().window)

        configureNavigationBar()

        /*
         * This screen is hosted inside TripleShotHostFragment rather than being pushed
         * onto the Activity back stack. Without an explicit callback Android therefore
         * treats Back as "leave/minimize the app". In every game mode Back now means
         * exactly what the result-screen Home button means: leave the current game and
         * return to MinikSwish home.
         */
        requireActivity().onBackPressedDispatcher.addCallback(
            viewLifecycleOwner,
            AOnBackPressedCallback(true) { [weak self] _ in
                self?.leaveGameToHome()
            }
        )
        // iOS-only (DESIGN 12.3): the on-screen stand-in for system Back, which on this screen always runs
        // leaveGameToHome() (the callback above).
        TripleShotGameFragment.game1RequireView(view, TripleShotGameFragment.IOS_EXIT_BUTTON_ID, AView.self)
            .setOnClickListener { [weak self] _ in
                self?.leaveGameToHome()
            }

        courtView = TripleShotGameFragment.game1RequireView(view, R.id.courtView, TripleShotCourtView.self)
        gameBackground = TripleShotGameFragment.game1RequireView(view, R.id.gameBackground, AImageView.self)

        courtView.setLocalCharacters(
            humanCharacterId: config.playerCharacterId,
            botCharacterId: config.botCharacterId
        )

        /*
         * CourtView physics and the visible background must use the exact same source-image
         * transform. This is especially important now that answer spots can live in bushes
         * and near the edges of the artwork, and also keeps tablets aligned.
         */
        let syncBackgroundTransform = { [weak self] in
            guard let self else { return }
            if self.courtView != nil && self.gameBackground != nil {
                self.courtView.applyBackgroundTransformTo(imageView: self.gameBackground)
            }
        }

        courtView.addOnLayoutChangeListener(AOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ in
            syncBackgroundTransform()
        })
        view.post { syncBackgroundTransform() }

        scoreText = TripleShotGameFragment.game1RequireView(view, R.id.scoreText, ATextView.self)
        ballsText = TripleShotGameFragment.game1RequireView(view, R.id.ballsText, ATextView.self)
        timeText = TripleShotGameFragment.game1RequireView(view, R.id.timeText, ATextView.self)
        botScoreText = TripleShotGameFragment.game1RequireView(view, R.id.botScoreText, ATextView.self)
        for label in [scoreText!, botScoreText!] {
            label.addOnLayoutChangeListener(AOnLayoutChangeListener { [weak self] _, left, _, right, _, oldLeft, _, oldRight, _ in
                guard let self else { return }
                if right > left && right - left != oldRight - oldLeft && self.isBotHorseMode() {
                    let state = self.horseEngine?.snapshot()
                    self.scoreText.setText(self.horseScoreLabel(label: self.scoreText, name: self.liveHorseText(hebrew: "אני", english: "You"), count: state?.humanPenalties ?? 0))
                    self.botScoreText.setText(self.horseScoreLabel(label: self.botScoreText, name: self.currentBotDisplayName(), count: state?.botPenalties ?? 0))
                }
            })
        }

        questionText = TripleShotGameFragment.game1RequireView(view, R.id.questionText, ATextView.self)
        let hebrewUi = ["he", "iw"].contains(resources.configuration.locales[0].language)
        questionText.textDirection = hebrewUi ? AView.TEXT_DIRECTION_RTL : AView.TEXT_DIRECTION_LTR
        questionText.layoutDirection = hebrewUi ? AView.LAYOUT_DIRECTION_RTL : AView.LAYOUT_DIRECTION_LTR
        categoryText = TripleShotGameFragment.game1RequireView(view, R.id.categoryText, ATextView.self)
        feedbackText = TripleShotGameFragment.game1RequireView(view, R.id.feedbackText, ATextView.self)
        streakText = TripleShotGameFragment.game1RequireView(view, R.id.streakText, ATextView.self)

        topHud = TripleShotGameFragment.game1RequireView(view, R.id.topHud, AView.self)
        questionCard = TripleShotGameFragment.game1RequireView(view, R.id.questionCard, AView.self)
        answerStrip = TripleShotGameFragment.game1RequireView(view, R.id.answerStrip, ALinearLayout.self)

        configureCenteredQuestionLayout()
        installTapToContinueOverlay(root: view)

        tutorialHelpButton =
            TripleShotGameFragment.game1RequireView(view, R.id.tutorialHelpButton, AButton.self)
        tutorialCard =
            TripleShotGameFragment.game1RequireView(view, R.id.tutorialCard, AView.self)
        tutorialTitle =
            TripleShotGameFragment.game1RequireView(view, R.id.tutorialTitle, ATextView.self)
        tutorialBody =
            TripleShotGameFragment.game1RequireView(view, R.id.tutorialBody, ATextView.self)
        tutorialPrevButton =
            TripleShotGameFragment.game1RequireView(view, R.id.tutorialPrevButton, AButton.self)
        tutorialNextButton =
            TripleShotGameFragment.game1RequireView(view, R.id.tutorialNextButton, AButton.self)
        tutorialDismissButton =
            TripleShotGameFragment.game1RequireView(view, R.id.tutorialDismissButton, AButton.self)

        opponentsScroll =
            TripleShotGameFragment.game1RequireView(view, R.id.opponentsScroll, AHorizontalScrollView.self)
        opponentsContainer =
            TripleShotGameFragment.game1RequireView(view, R.id.opponentsContainer, ALinearLayout.self)

        resultOverlay =
            TripleShotGameFragment.game1RequireView(view, R.id.resultOverlay, AView.self)
        resultScoreText =
            TripleShotGameFragment.game1RequireView(view, R.id.resultScoreText, ATextView.self)
        resultStatsText =
            TripleShotGameFragment.game1RequireView(view, R.id.resultStatsText, ATextView.self)
        resultOverlay.addOnLayoutChangeListener(AOnLayoutChangeListener { [weak self, weak view] _, _, _, _, _, _, _, _, _ in
            guard let self, let view else { return }
            let panel = TripleShotGameFragment.game1RequireView(view, R.id.basketballResultScroll, AView.self)
            let lp = panel.layoutParams as! AFrameLayout.LayoutParams
            let density = self.resources.displayMetrics.density
            let wanted = min((500 * density).toInt(), self.resultOverlay.width - (32 * density).toInt()).coerceAtLeast(1)
            if lp.width != wanted { lp.width = wanted; panel.layoutParams = lp }
            let maxHeight = (Float(self.resultOverlay.height) - 32 * density).toInt().coerceAtLeast(1)
            if panel.height > maxHeight || (lp.height > 0 && panel.height < maxHeight) { lp.height = maxHeight; panel.layoutParams = lp }
        })
        resultRankText =
            TripleShotGameFragment.game1RequireView(view, R.id.resultRankText, ATextView.self)

        sensor =
            TripleShotSensorController(
                context: requireContext(),
                listener: self
            )

        /*
         * Touch and sensors are intentionally active together.
         *
         * A tap on an A/B/C/D court marker selects that answer. Everywhere else,
         * once an answer is selected, the same court surface controls aim/arc/release.
         */
        courtView.setOnTouchListener { [weak self] _, event in
            guard let self else { return false }
            if feedbackShowing {
                return true
            }
            if shotInProgress || ended {
                return false
            }

            if isAnyHorseMode() && horseWaitingForSpot {
                /*
                 * HORSE setter movement is deliberately different from shooting input.
                 * Dragging still walks continuously, but a simple tap now means "walk here".
                 * Neither gesture confirms the location or launches a shot; the compact
                 * ready button is still the explicit confirmation step.
                 */
                switch event.actionMasked {
                case AMotionEvent.ACTION_DOWN:
                    horseMoveTouchActive = true
                    horseMoveLastX = event.x
                    horseMoveLastY = event.y
                    horseMoveDownX = event.x
                    horseMoveDownY = event.y
                    horseMoveHasDragged = false
                    return true

                case AMotionEvent.ACTION_MOVE:
                    if !horseMoveTouchActive { return true }

                    let totalDx = event.x - horseMoveDownX
                    let totalDy = event.y - horseMoveDownY
                    if abs(totalDx) > Float(dp(v: TripleShotGameFragment.HORSE_MOVE_TAP_SLOP_DP)) ||
                        abs(totalDy) > Float(dp(v: TripleShotGameFragment.HORSE_MOVE_TAP_SLOP_DP))
                    {
                        horseMoveHasDragged = true
                    }

                    let dx = event.x - horseMoveLastX
                    let dy = event.y - horseMoveLastY
                    horseMoveLastX = event.x
                    horseMoveLastY = event.y
                    courtView.moveHorseHumanByTouch(dx: dx, dy: dy)
                    return true

                case AMotionEvent.ACTION_UP:
                    if horseMoveTouchActive && !horseMoveHasDragged {
                        courtView.moveHorseHumanTo(x: event.x, y: event.y)
                    }
                    horseMoveTouchActive = false
                    horseMoveHasDragged = false
                    return true

                case AMotionEvent.ACTION_CANCEL:
                    horseMoveTouchActive = false
                    horseMoveHasDragged = false
                    return true

                default:
                    return false
                }
            } else {
                switch event.actionMasked {
                case AMotionEvent.ACTION_DOWN:
                    let station = courtView.findStationAt(x: event.x, y: event.y)
                    if let station {
                        pendingStationTap = station
                        stationTapDownX = event.x
                        stationTapDownY = event.y
                        return true
                    } else if selectedAnswerIndex >= 0 {
                        return sensor.handleTouchEvent(
                            event: event,
                            viewWidth: courtView.width,
                            viewHeight: courtView.height
                        )
                    } else {
                        return false
                    }

                case AMotionEvent.ACTION_MOVE:
                    if pendingStationTap >= 0 {
                        let movedTooFar =
                            abs(event.x - stationTapDownX) > Float(dp(v: TripleShotGameFragment.STATION_TAP_SLOP_DP)) ||
                                abs(event.y - stationTapDownY) > Float(dp(v: TripleShotGameFragment.STATION_TAP_SLOP_DP))

                        if movedTooFar {
                            pendingStationTap = -1
                        }
                        return true
                    } else if selectedAnswerIndex >= 0 {
                        return sensor.handleTouchEvent(
                            event: event,
                            viewWidth: courtView.width,
                            viewHeight: courtView.height
                        )
                    } else {
                        return false
                    }

                case AMotionEvent.ACTION_UP:
                    if pendingStationTap >= 0 {
                        let station = pendingStationTap
                        pendingStationTap = -1
                        selectAnswer(index: station)
                        return true
                    } else if selectedAnswerIndex >= 0 {
                        return sensor.handleTouchEvent(
                            event: event,
                            viewWidth: courtView.width,
                            viewHeight: courtView.height
                        )
                    } else {
                        return false
                    }

                case AMotionEvent.ACTION_CANCEL:
                    pendingStationTap = -1
                    if selectedAnswerIndex >= 0 {
                        return sensor.handleTouchEvent(
                            event: event,
                            viewWidth: courtView.width,
                            viewHeight: courtView.height
                        )
                    } else {
                        return false
                    }

                default:
                    return false
                }
            }
        }

        tutorialHelpButton.setOnClickListener { [weak self] _ in
            guard let self else { return }
            if isAnyHorseMode() { showHorseShotChoice() } else { startTutorial(replay: true) }
        }
        if isAnyHorseMode() {
            let jump = requireContext().getSharedPreferences("basketball_controls", 0).getBoolean("horseJump", false)
            courtView.setHorseJumpShot(enabled: jump)
            if savedInstanceState == nil {
                view.post { [weak self] in
                    guard let self else { return }
                    if isAdded && !ended { showHorseShotChoice() }
                }
            }
        }

        tutorialPrevButton.setOnClickListener { [weak self] _ in
            guard let self else { return }
            if tutorialPage > TutorialStep.CHOOSE_ANSWER.ordinal {
                tutorialPage -= 1
                updateTutorialUi()
            }
        }

        tutorialNextButton.setOnClickListener { [weak self] _ in
            guard let self else { return }
            if tutorialPage < tutorialProgress {
                tutorialPage += 1
                updateTutorialUi()
            }
        }

        tutorialDismissButton.setOnClickListener { [weak self] _ in
            self?.finishTutorialPermanently()
        }

        TripleShotGameFragment.game1RequireView(
            view, R.id.resultAgainButton, AButton.self
        ).setOnClickListener { [weak self] _ in
            guard let self else { return }
            // Kotlin `config.copy(seed = ..., roomId = null)`: the seed argument is evaluated first.
            let seed =
                if config.isMultiplayer {
                    config.seed
                } else {
                    ASystem.currentTimeMillis()
                }
            (parentFragment as? TripleShotHostFragment)?.startGame(
                config: config.copy(
                    roomId: nil,
                    seed: seed
                )
            )
        }

        TripleShotGameFragment.game1RequireView(
            view, R.id.resultHomeButton, AButton.self
        ).setOnClickListener { [weak self] _ in
            self?.leaveGameToHome()
        }

        TripleShotGameFragment.game1RequireView(
            view, R.id.resultLeaderboardButton, AButton.self
        ).setOnClickListener { [weak self] _ in
            (self?.parentFragment as? TripleShotHostFragment)?
                .showLeaderboard()
        }

        if config.isMultiplayer {
            subscribeOpponents()
        } else if config.isBotMatch {
            startBotOpponent()
        }

        if isLiveHorseMode() {
            tutorialHelpButton.visibility = AView.GONE
            hideTutorialCard()
            startLiveHorseMatch()
            updateHud()
            restoreUiLayering()
        } else if isBotHorseMode() {
            tutorialHelpButton.visibility = AView.GONE
            hideTutorialCard()
            startHorseMatch()
            updateHud()
            restoreUiLayering()
        } else {
            showQuestion()
            updateHud()

            if
                isPracticeMode() &&
                !tutorialPreferences.getBoolean(
                    TripleShotGameFragment.TUTORIAL_DONE_KEY,
                    false
                )
            {
                startTutorial(replay: false)
            } else {
                hideTutorialCard()
            }

            restoreUiLayering()
            handler.postDelayed(clockRunnable, 1000)
        }
    }

    override func onResume() {
        super.onResume()
        sensor.start()
        if isAnyHorseMode() && horseWaitingForSpot {
            sensor.prepareForMovement()
        }
    }

    override func onPause() {
        sensor.stop()
        super.onPause()
    }

    /// Kotlin `override fun onDestroyView()` (L3763-3786): its body is in part 2 (DESIGN 2.10).
    override func onDestroyView() {
        onDestroyView_impl()
    }

    func currentQuestion() -> TripleShotQuestion {
        questions.get(questionIndex % questions.size)
    }

    /**
     * Hebrew answer labels stay inside the Hebrew BiDi run (א/ב/ג/ד) instead of mixing
     * Latin A/B/C/D into RTL text. English keeps the familiar A/B/C/D convention.
     */
    func answerChoiceLabel(index: Int) -> String {
        let language = TripleShotGameFragment.game1ConfigurationLanguage(resources)
        if language == "he" || language == "iw" {
            return TripleShotGameFragment.HEBREW_ANSWER_LABELS.getOrNull(index) ?? String(index + 1)
        } else {
            // ('A'.code + index).toChar().toString(): one UTF-16 code unit.
            return String(utf16CodeUnits: [UInt16(truncatingIfNeeded: 65 + index)], count: 1)
        }
    }

    func answerDisplayText(
        index: Int,
        text: String,
        statusMark: String? = nil
    ) -> String {
        let label = answerChoiceLabel(index: index)
        if statusMark == nil || statusMark!.kotlinIsBlank {
            return "\(label). \(text)"
        } else {
            return "\(label). \(statusMark!) \(text)"
        }
    }

    // MARK: - Question flow (L697-1165)

    func showQuestion() {
        if ended { return }

        let q = currentQuestion()

        categoryText.text =
            q.category.labelFor(
                TripleShotGameFragment.game1ConfigurationLanguage(resources)
            )
        questionText.text = readableQuestion(prompt: q.prompt)
        questionText.textSize = questionTextSizeFor(length: q.prompt.length)
        questionText.background = questionReadableBackground()
        if let outlined = questionText as? OutlinedTextView {
            outlined.setOutlineColor(color: AColor.rgb(18, 35, 48))
            outlined.setOutlineWidthDp(dp: 0.45)
        }
        feedbackText.visibility = AView.GONE
        feedbackShowing = false

        selectedAnswerIndex = -1
        knowledgeAnswerRecorded = false

        currentShotPhase =
            TripleShotSensorController.ShotPhase.WAITING_FOR_ANSWER

        answerStrip.removeAllViews()
        answerViews.removeAll()

        for (index, option) in q.answers.enumerated() {
            let accent = answerAccentColor(index: index)

            let tv = OutlinedTextView()
            let params =
                ALinearLayout.LayoutParams(
                    ALinearLayout.LayoutParams.MATCH_PARENT,
                    ALinearLayout.LayoutParams.WRAP_CONTENT
                )
            params.topMargin = dp(v: 1)
            params.bottomMargin = dp(v: 1)
            tv.layoutParams = params

            tv.minHeight = dp(v: q.answers.count >= 4 ? 36 : 39)
            tv.gravity = AGravity.CENTER
            tv.setPadding(
                dp(v: 7),
                dp(v: 4),
                dp(v: 7),
                dp(v: 4)
            )

            // Narrow tree-side cards intentionally wrap into compact 2-3 line answers.
            tv.maxLines = 3
            tv.ellipsize = ATextUtils.TruncateAt.END
            tv.text = answerDisplayText(index: index, text: option.text)
            tv.textSize = answerTextSizeFor(length: option.text.length, answerCount: q.answers.count)
            tv.textDirection = AView.TEXT_DIRECTION_LOCALE

            // A translucent warm card does the heavy readability work. A very thin
            // navy outline keeps glyphs crisp without the washed-out white halo from V12.
            tv.setTextColor(AColor.rgb(18, 35, 48))
            tv.setOutlineColor(color: AColor.rgb(18, 35, 48))
            tv.setOutlineWidthDp(dp: 0.55)

            tv.setTypeface(
                tv.typeface,
                ATypeface.BOLD
            )

            tv.background = answerOutlineBackground(
                accentColor: accent,
                selected: false
            )

            tv.isClickable = true
            tv.isFocusable = true

            tv.setOnClickListener { [weak self] _ in
                self?.selectAnswer(index: index)
            }

            answerStrip.addView(tv)
            answerViews.append(tv)
        }

        // Keep the Android Back button, but also expose a small in-card exit affordance in the
        // timed Shooting Challenge. It is intentionally subtle so it never competes with answers.
        if config.gameType == GameType.SHOOTING_CHALLENGE || config.gameType == GameType.HORSE {
            addChallengeExitLink()
        }

        /*
         * The court owns the physical mapping. Shooting Challenge gets a new seeded 2D
         * arrangement for every question; practice stays on a stable beginner-friendly set.
         * Coordinates are based on the original artwork, so spots can safely include low
         * bushes instead of being restricted to one horizontal row.
         */
        courtView.prepareAnswerSpots(
            count: q.answers.count,
            // Kotlin `config.seed xor q.id.hashCode().toLong() xor questionIndex.toLong() * 97L` (`*` binds
            // tighter than the infix `xor`; hashCode is Java's String.hashCode, sign-extended).
            seed: config.seed ^ Int64(q.id.javaHashCode) ^ (Int64(questionIndex) &* 97),
            randomize: config.gameType == GameType.SHOOTING_CHALLENGE
        )
        courtView.clearStationSelection(animate: false)
        if config.isBotMatch && config.gameType == GameType.SHOOTING_CHALLENGE {
            courtView.prepareHumanChallengeTurn()
        }
        courtView.randomizeBallSkin()

        sensor.prepareForAnswer()

        updateAnswerSelection()
        showQuestionUi()
    }

    /**
     * Answer selection stays intentionally simple: tap an answer.
     *
     * After the tap, the physical/touch skill begins. This keeps the learning task
     * obvious while still making the actual shot fully skill based.
     */
    func selectAnswer(index: Int) {
        if shotInProgress || feedbackShowing || ended { return }

        let q: TripleShotQuestion
        if isAnyHorseMode() {
            guard let horse = horseQuestion else { return }
            q = horse
        } else {
            q = currentQuestion()
        }
        if !q.answers.indices.contains(index) { return }

        selectedAnswerIndex = index

        recordHumanKnowledgeAnswer(
            question: q,
            answerIndex: index
        )

        if isAnyHorseMode() {
            // In HORSE, A/B/C/D are knowledge choices only. The physical shot location was
            // already chosen by the setter and must remain identical for every obligated turn.
            courtView.setHorseAnswerMode()
            courtView.setFineAim(normalized: 0)
            courtView.setPullBack(normalized: 0)
            courtView.setShotGuidesVisible(visible: true)
        } else {
            courtView.setStation(
                index: index,
                animate: true
            )
            courtView.setFineAim(normalized: 0)
            courtView.setPullBack(normalized: 0)
            courtView.setShotGuidesVisible(visible: true)
        }

        updateAnswerSelection()

        // The current way the phone is held becomes the neutral pose for this shot.
        sensor.prepareForShot()

        fadeQuestionUiForAiming()

        view?.performHapticFeedback(
            AHapticFeedbackConstants.CLOCK_TICK
        )

        if !isAnyHorseMode() {
            unlockTutorialStep(step: TutorialStep.AIM)
        }
    }

    func updateAnswerSelection() {
        for (index, textView) in answerViews.enumerated() {
            let selected = index == selectedAnswerIndex
            let accent = answerAccentColor(index: index)

            textView.background = answerOutlineBackground(
                accentColor: accent,
                selected: selected
            )

            textView.setAlpha(selected ? 1 : 0.94)

            if let outlined = textView as? OutlinedTextView {
                outlined.setOutlineColor(color: AColor.rgb(18, 35, 48))
                outlined.setOutlineWidthDp(dp: selected ? 0.85 : 0.55)
            }
        }
    }

    // MARK: - TripleShotSensorController.Listener (L884-983)

    func onAimChanged(normalizedAim: Float) {
        if courtView == nil || shotInProgress { return }

        courtView.setFineAim(normalized: normalizedAim)

        if
            selectedAnswerIndex >= 0 &&
            abs(normalizedAim) >= TripleShotGameFragment.TUTORIAL_AIM_MOVEMENT
        {
            unlockTutorialStep(step: TutorialStep.PULL_BACK)
        }
    }

    func onPullBackChanged(
        normalizedPullBack: Float,
        armed: Bool
    ) {
        if courtView == nil || shotInProgress { return }

        courtView.setPullBack(normalized: normalizedPullBack)


        if armed {
            unlockTutorialStep(step: TutorialStep.THROW)
        }
    }

    func onShotPhaseChanged(
        phase: TripleShotSensorController.ShotPhase
    ) {
        currentShotPhase = phase

        if !isAdded { return }

        if
            phase == TripleShotSensorController.ShotPhase.ARMED
        {
            unlockTutorialStep(step: TutorialStep.THROW)
        }

    }

    func onShotGesture(
        skill: ShotSkill,
        pullBack01: Float
    ) {
        if
            !isAdded ||
            shotInProgress ||
            ended ||
            selectedAnswerIndex < 0
        {
            return
        }

        performShot(
            skill: skill,
            pullBackAtRelease: pullBack01
        )
    }

    func onSensorAvailability(
        hasRotation: Bool,
        hasGyro: Bool
    ) {
        if !isAdded { return }

        fallbackSensors =
            !hasRotation || !hasGyro

        if fallbackSensors {
            var missingParts: [String] = []
            if !hasRotation { missingParts.append("rotation") }
            if !hasGyro { missingParts.append("gyroscope") }
            let missing = missingParts.joined(separator: " + ")

            AToast.makeText(
                requireContext(),
                "חסר חיישן \(missing) \u{2014} אפשר לשחק באופן מלא עם גרירה ו-Swipe על המגרש.",
                AToast.LENGTH_LONG
            ).show()
        }

    }

    func onMovementChanged(horizontal: Float, vertical: Float) {
        if
            !isAdded ||
            courtView == nil ||
            !isAnyHorseMode() ||
            !horseWaitingForSpot ||
            shotInProgress ||
            feedbackShowing ||
            ended
        {
            return
        }

        courtView.moveHorseHumanByDevice(horizontal: horizontal, vertical: vertical)
    }

    func recordHumanKnowledgeAnswer(
        question: TripleShotQuestion,
        answerIndex: Int
    ) {
        if knowledgeAnswerRecorded { return }

        guard let chosen = question.answers.getOrNull(answerIndex) else { return }
        knowledgeAnswerRecorded = true

        /*
         * Every human knowledge attempt contributes to long-term learning progress,
         * regardless of whether the current mode is Practice, Challenge, Bot or HORSE.
         * Bot answers are never routed through this method.
         */
        let correctAnswer =
            question.answers.kMaxBy { $0.qualityPercent }?.text ?? ""

        TripleShotQuestionRepository.recordAnswer(questionId: question.id, selectedAnswerIndex: answerIndex)

        firebase.recordKnowledgeAnswer(
            playerName: config.playerName,
            category: question.category,
            correct: chosen.qualityPercent == question.answers.map { $0.qualityPercent }.max()!,
            questionId: question.id,
            prompt: question.prompt,
            selectedAnswer: chosen.text,
            correctAnswer: correctAnswer,
            qualityPercent: chosen.qualityPercent,
            gameType: config.gameType.name
        ) { _ in
            // Progress tracking must never interrupt gameplay if the network is offline.
            // Realtime Database will report a failure here, but the game continues normally.
        }
    }

    /**
     * No outcome is calculated here.
     *
     * CourtView launches the ball into TripleShotPhysics and returns only after the
     * actual flight / collisions have completed.
     */
    func performShot(
        skill: ShotSkill,
        pullBackAtRelease: Float
    ) {
        if selectedAnswerIndex < 0 { return }

        if isLiveHorseMode() {
            performLiveHorseHumanShot(
                skill: skill,
                pullBackAtRelease: pullBackAtRelease
            )
            return
        }

        if isBotHorseMode() {
            performHorseHumanShot(
                skill: skill,
                pullBackAtRelease: pullBackAtRelease
            )
            return
        }

        shotInProgress = true
        feedbackText.visibility = AView.GONE
        hideQuestionUiForShot()

        let q = currentQuestion()
        let chosen = q.answers[selectedAnswerIndex]

        // HOT HAND is already active while attempting the next shot after a 3+ streak.
        let hotDuringFlight =
            scoring.shootingStreak >= 3

        /*
         * CourtView normally sits below the UI so buttons/questions stay readable.
         * The GPU camera frames flight inside the gameplay world. Android HUD controls
         * retain their normal layer above the opaque GL surface throughout the shot.
         */
        restoreUiLayering()

        if config.isMultiplayer {
            publishLiveShotGesture(
                skill: skill,
                pullBackAtRelease: pullBackAtRelease,
                hotDuringFlight: hotDuringFlight
            )
        }

        courtView.animateShot(
            skill: skill,
            stationIndex: selectedAnswerIndex,
            answerCount: q.answers.count,
            pullBackAtRelease:
                pullBackAtRelease.coerceAtLeast(TripleShotGameFragment.MIN_SHOT_PULLBACK),
            hot: hotDuringFlight
        ) { [weak self] shotResult in
            guard let self else { return }
            if !isAdded || ended {
                return
            }

            let outcome = shotResult.outcome

            /*
             * Knowledge remains the main source of points.
             * Basketball skill still matters because a real make adds basket points.
             */
            let delta =
                scoring.score(
                    answerQualityPercent: chosen.qualityPercent,
                    made: outcome.made
                )

            courtView.setHotHand(
                active: delta.shootingStreak >= 3
            )

            view?.performHapticFeedback(
                outcome.made
                    ? AHapticFeedbackConstants.LONG_PRESS
                    : AHapticFeedbackConstants.CLOCK_TICK
            )

            restoreUiLayering()
            if !config.isBotMatch {
                showQuestionUi()
            }
            updateHud()

            feedbackShowing = true
            feedbackText.visibility = AView.VISIBLE
            feedbackText.maxLines = 8

            feedbackText.text =
                buildFeedback(
                    q: q,
                    quality: chosen.qualityPercent,
                    shotResult: shotResult,
                    points: delta.totalPoints,
                    multiplier: delta.knowledgeMultiplier
                )

            showAnswerReview(
                question: q,
                selectedIndex: selectedAnswerIndex
            )

            publishLiveState(
                quality: chosen.qualityPercent,
                made: outcome.made
            )

            unlockTutorialStep(
                step: TutorialStep.FREE_PLAY
            )

            if config.isBotMatch {
                // The visible bot reacts to the player's completed flight, then takes its own
                // real physics shot before the next question begins. Solo stays on the exact
                // same 1.25-second feedback path it used before bot rendering was added.
                handler.postDelayed({ [weak self] in
                    guard let self else { return }
                    if !isAdded || ended {
                        return
                    }
                    runBotResponse(question: q)
                }, TripleShotGameFragment.BOT_RESPONSE_DELAY_MS)
            } else {
                shotInProgress = false
                waitForTapToContinue { [weak self] in
                    guard let self else { return }
                    if shouldEndNow() {
                        endGame()
                    } else {
                        questionIndex += 1
                        showQuestion()
                    }
                }
            }
        }
    }

    // -------------------------------------------------------------------------
    // Local HORSE / חיובים vs MINIK
    // -------------------------------------------------------------------------

    func isBotHorseMode() -> Bool {
        config.isBotMatch && config.gameType == GameType.HORSE
    }

    func isLiveHorseMode() -> Bool {
        config.isMultiplayer && config.gameType == GameType.HORSE
    }

    func isAnyHorseMode() -> Bool {
        isBotHorseMode() || isLiveHorseMode()
    }

    // MARK: - Live HORSE (L1180-1549)

    func startLiveHorseMatch() {
        horseQuestion = nil
        horseQuestionCounter = 0
        horsePendingCategory = nil
        horseSelectedCategory = horseAvailableCategories().first
        horseTopicPromptShown = false
        horseWaitingForSpot = false
        horseMoveTouchActive = false
        horseRecentQuestionIds.removeAll()
        liveHorseLastHandledTurn = -1
        liveHorseFinishedShown = false
        courtView.clearHorseModeVisuals()

        answerStrip.removeAllViews()
        answerViews.removeAll()
        feedbackText.visibility = AView.GONE
        questionCard.visibility = AView.VISIBLE
        courtView.setHorseAnswerMode()
        sensor.prepareForAnswer()

        guard let room = config.roomId else { return }
        liveHorseHandle?.remove()
        liveHorseHandle =
            firebase.listenLiveHorseState(codeRaw: room) { [weak self] state in
                guard let self else { return }
                guard isAdded, !ended, let state else {
                    return
                }
                liveHorseState = state
                courtView.applyLiveHorseState(
                    state: state,
                    myUid: firebase.currentUid() ?? ""
                )
                handleLiveHorseState(state: state)
            }
    }

    func handleLiveHorseState(state: LiveHorseState) {
        if !isAdded || ended { return }

        let myUid = firebase.currentUid() ?? ""
        let mySpectatorSlot = state.spectatorSlots[myUid]

        if state.isFinished {
            showLiveHorseFinished(state: state)
            return
        }

        if mySpectatorSlot != nil {
            horseWaitingForSpot = false
            selectedAnswerIndex = -1
            sensor.prepareForAnswer()
            courtView.setShotGuidesVisible(visible: false)
            categoryText.text = ""
            questionText.text =
                liveHorseText(
                    hebrew: "הודחתם מהחיובים \u{2014} אתם עדיין צופים במשחק",
                    english: "You are out of HORSE \u{2014} keep watching the match"
                )
            questionText.background = questionReadableBackground()
            answerStrip.removeAllViews()
            answerViews.removeAll()
            showQuestionUi()
            updateHud()
            return
        }

        if feedbackShowing { return }
        if state.turnNumber == liveHorseLastHandledTurn { return }
        liveHorseLastHandledTurn = state.turnNumber

        let currentName =
            latestLivePlayers
                .first { $0.uid == state.currentPlayerUid }
                .map { $0.name.kotlinIsBlank ? "Player" : $0.name }
                ?? "Player"

        if state.currentPlayerUid != myUid {
            horseWaitingForSpot = false
            selectedAnswerIndex = -1
            horseQuestion = nil
            sensor.prepareForAnswer()
            courtView.setHorseAnswerMode()
            courtView.setShotGuidesVisible(visible: false)

            categoryText.text = ""
            questionText.text =
                if state.phase == LiveHorseState.PHASE_SETTING {
                    liveHorseText(
                        hebrew: "\(currentName) בוחר נושא ומיקום לחיוב\u{2026}",
                        english: "\(currentName) is choosing a topic and shot location\u{2026}"
                    )
                } else {
                    liveHorseText(
                        hebrew: "\(currentName) בתור \u{2014} צפו בזריקה",
                        english: "\(currentName) is up \u{2014} watch the shot"
                    )
                }
            questionText.background = questionReadableBackground()
            answerStrip.removeAllViews()
            answerViews.removeAll()
            showQuestionUi()
            updateHud()
            return
        }

        switch state.phase {
        case LiveHorseState.PHASE_SETTING:
            horseTurnMessage =
                liveHorseText(
                    hebrew: "התור שלכם לקבוע חיוב",
                    english: "Your turn to set a challenge"
                )
            updateHud()
            promptHumanHorseTopic()

        case LiveHorseState.PHASE_ATTEMPT:
            let category: QuestionCategory
            if let named = QuestionCategory.named(state.challengeCategory) {
                category = named
            } else if let first = horseAvailableCategories().first {
                category = first
            } else {
                return
            }

            horseWaitingForSpot = false
            horseMoveTouchActive = false
            sensor.prepareForAnswer()

            courtView.moveHumanToHorseSourceSpot(
                sourceX: state.challengeSpotX,
                sourceY: state.challengeSpotY,
                spotId: state.challengeSpotId.kotlinIsBlank ? "LIVE_\(state.turnNumber)" : state.challengeSpotId,
                animate: true
            ) { [weak self] in
                guard let self else { return }
                if isAdded && !ended && liveHorseState?.turnNumber == state.turnNumber {
                    showHorseQuestionForHuman(category: category)
                }
            }

        default:
            break
        }
    }

    func confirmLiveHorseFreeSpot() {
        if !horseWaitingForSpot || ended { return }

        guard let room = config.roomId else { return }
        guard let category = horsePendingCategory ?? horseSelectedCategory else { return }
        guard let spotId = courtView.lockCurrentHorseFreeSpot() else { return }
        let source = courtView.currentPlayerSourcePosition()

        horseWaitingForSpot = false
        horseMoveTouchActive = false
        horsePendingCategory = nil
        sensor.prepareForAnswer()

        firebase.configureLiveHorseChallenge(
            roomCodeRaw: room,
            category: category,
            spotId: spotId,
            spotX: source.x,
            spotY: source.y
        ) { [weak self] result in
            guard let self else { return }
            if !isAdded { return }
            if case .failure = result {
                AToast.makeText(
                    requireContext(),
                    liveHorseText(
                        hebrew: "לא ניתן היה לקבוע את החיוב. נסו שוב.",
                        english: "Could not set the challenge. Try again."
                    ),
                    AToast.LENGTH_SHORT
                ).show()
                liveHorseLastHandledTurn = -1
                if let latest = liveHorseState { handleLiveHorseState(state: latest) }
            }
        }
    }

    func performLiveHorseHumanShot(
        skill: ShotSkill,
        pullBackAtRelease: Float
    ) {
        guard let room = config.roomId else { return }
        guard let q = horseQuestion else { return }
        guard let chosen = q.answers.getOrNull(selectedAnswerIndex) else { return }
        guard let stateAtRelease = liveHorseState else { return }
        let myUid = firebase.currentUid() ?? ""

        if
            stateAtRelease.currentPlayerUid != myUid ||
            stateAtRelease.phase != LiveHorseState.PHASE_ATTEMPT
        {
            return
        }

        shotInProgress = true
        hideQuestionUiForShot()
        feedbackText.visibility = AView.GONE
        restoreUiLayering()
        courtView.setLiveReplayCaptureEnabled(enabled: true)

        courtView.animateHorseShot(
            skill: skill,
            pullBackAtRelease: pullBackAtRelease.coerceAtLeast(TripleShotGameFragment.MIN_SHOT_PULLBACK),
            hot: false
        ) { [weak self] shotResult in
            guard let self else { return }
            if !isAdded || ended { return }

            courtView.setLiveReplayCaptureEnabled(enabled: false)
            let answerCorrect = chosen.qualityPercent >= 100
            let made = shotResult.outcome.made
            let source = courtView.currentPlayerSourcePosition()

            firebase.publishLiveShot(
                roomCodeRaw: room,
                event: LiveShotEvent(
                    playerUid: myUid,
                    playerName: config.playerName,
                    shotSpotX: source.x,
                    shotSpotY: source.y,
                    aimError: skill.aimError,
                    powerError: skill.powerError,
                    arcError: skill.arcError,
                    rawPeakGyro: skill.rawPeakGyro,
                    rawReleasePitchDeg: skill.rawReleasePitchDeg,
                    pullBack: pullBackAtRelease.coerceAtLeast(TripleShotGameFragment.MIN_SHOT_PULLBACK),
                    hotHand: false,
                    releasedAt: ASystem.currentTimeMillis(),
                    made: made,
                    samples: shotResult.replaySamples
                )
            )

            restoreUiLayering()
            shotInProgress = false
            feedbackShowing = true
            courtView.setShotGuidesVisible(visible: false)
            showQuestionUi()
            showHorseAnswerReview(
                question: q,
                actor: HorseGameEngine.Player.HUMAN,
                answerCorrect: answerCorrect
            )

            let correctAnswer =
                q.answers.first { $0.qualityPercent >= 100 }?.text ?? ""

            feedbackText.visibility = AView.VISIBLE
            feedbackText.maxLines = 8
            var feedback = ""
            if answerCorrect {
                feedback += getString(R.string.minik_swish_horse_feedback_you_correct)
            } else {
                feedback +=
                    getString(
                        R.string.minik_swish_horse_feedback_you_wrong,
                        correctAnswer.kotlinIsBlank
                            ? getString(R.string.minik_swish_horse_answer_unknown)
                            : correctAnswer
                    )
            }
            feedback += "\n"
            feedback +=
                made
                    ? getString(R.string.minik_swish_horse_feedback_you_made)
                    : getString(R.string.minik_swish_horse_feedback_you_missed)
            feedback += "\n\n"
            feedback += tapToContinueHint()
            feedbackText.text = feedback

            firebase.resolveLiveHorseAttempt(
                roomCodeRaw: room,
                answerCorrect: answerCorrect,
                made: made
            ) { [weak self] result in
                guard let self else { return }
                if !isAdded { return }

                if case .failure = result {
                    AToast.makeText(
                        requireContext(),
                        liveHorseText(
                            hebrew: "לא ניתן היה לסנכרן את התור. בדקו את החיבור.",
                            english: "Could not sync the turn. Check your connection."
                        ),
                        AToast.LENGTH_SHORT
                    ).show()
                }

                waitForTapToContinue { [weak self] in
                    guard let self else { return }
                    if let latest = liveHorseState { handleLiveHorseState(state: latest) }
                }
            }
        }
    }

    func showLiveHorseFinished(state: LiveHorseState) {
        if liveHorseFinishedShown { return }
        liveHorseFinishedShown = true
        ended = true
        shotInProgress = false
        feedbackShowing = false
        sensor.cancelShot()
        handler.removeCallbacks(clockRunnable)

        let myUid = firebase.currentUid() ?? ""
        let winnerName =
            latestLivePlayers
                .first { $0.uid == state.winnerUid }
                .map { $0.name.kotlinIsBlank ? "Player" : $0.name }
                ?? "Player"

        resultOverlay.visibility = AView.GONE
        resultScoreText.text =
            if state.winnerUid == myUid {
                liveHorseText(hebrew: "ניצחתם! \u{1F3C6}", english: "You won! \u{1F3C6}")
            } else {
                liveHorseText(hebrew: "ניצחון של \(winnerName)", english: "\(winnerName) won")
            }

        let ordered: [(name: String, penalties: Int)] =
            state.playerOrder.compactMap { (uid: String) -> (name: String, penalties: Int)? in
                guard let player = latestLivePlayers.first(where: { $0.uid == uid }) else { return nil }
                let penalties = state.penalties[uid] ?? 0
                return (name: player.name.kotlinIsBlank ? "Player" : player.name, penalties: penalties)
            }

        resultStatsText.text =
            ordered.map { entry in
                "\(entry.name) \u{2014} \(horsePenaltyDisplay(count: entry.penalties))"
            }.joined(separator: "\n")

        resultRankText.text =
            liveHorseText(
                hebrew: "כל המודחים נשארים בצד המגרש עד סוף המשחק.",
                english: "Eliminated players remain courtside as spectators."
            )

        questionCard.visibility = AView.GONE
        answerStrip.visibility = AView.GONE
        feedbackText.visibility = AView.GONE
        courtView.startLiveHorseCelebration(humanWon: state.winnerUid == myUid)
        restoreUiLayering()
        topHud.bringToFront()

        handler.postDelayed({ [weak self] in
            guard let self else { return }
            if !isAdded { return }
            restoreUiLayering()
            resultOverlay.visibility = AView.VISIBLE
            resultOverlay.bringToFront()
        }, TripleShotGameFragment.HORSE_END_CELEBRATION_MS)

        if let room = config.roomId {
            firebase.armFinishedRoomCleanupIfLast(roomCodeRaw: room)
        }
    }

    func horsePenaltyDisplay(count: Int) -> String {
        let letters = "HORSE"
        return count <= 0 ? "\u{2014}" : letters.ktake(count.coerceIn(0, letters.length))
    }

    func liveHorseText(hebrew: String, english: String) -> String {
        let language = TripleShotGameFragment.game1ConfigurationLanguage(resources)
        return language == "he" || language == "iw" ? hebrew : english
    }

    // MARK: - Local HORSE (L1551-1948)

    func startHorseMatch() {
        horseEngine = HorseGameEngine(firstSetter: HorseGameEngine.Player.HUMAN)
        horseQuestion = nil
        horseQuestionCounter = 0
        horsePendingCategory = nil
        horseSelectedCategory = horseAvailableCategories().first
        horseTopicPromptShown = false
        horseWaitingForSpot = false
        horseMoveTouchActive = false
        horseTurnMessage = getString(R.string.minik_swish_horse_human_setting)
        horseRecentQuestionIds.removeAll()
        courtView.clearHorseModeVisuals()

        answerStrip.removeAllViews()
        answerViews.removeAll()
        feedbackText.visibility = AView.GONE
        questionCard.visibility = AView.VISIBLE
        courtView.setHorseAnswerMode()
        sensor.prepareForAnswer()

        // Start with the human setter so the first test immediately exposes the complete
        // topic -> location -> question -> physical shot flow.
        handler.postDelayed({ [weak self] in
            guard let self else { return }
            if isAdded && !ended {
                advanceHorseTurn()
            }
        }, 220)
    }

    func advanceHorseTurn() {
        if !isAdded || ended { return }

        guard let engine = horseEngine else { return }
        let state = engine.snapshot()

        if state.isGameOver {
            endHorseGame(winner: state.winner)
            return
        }

        selectedAnswerIndex = -1
        horseQuestion = nil
        horseWaitingForSpot = false
        horseMoveTouchActive = false
        feedbackShowing = false
        shotInProgress = false
        feedbackText.visibility = AView.GONE
        courtView.setFineAim(normalized: 0)
        courtView.setPullBack(normalized: 0)
        courtView.setShotGuidesVisible(visible: false)
        sensor.prepareForAnswer()

        if state.needsNewChallenge {
            if state.currentPlayer == HorseGameEngine.Player.HUMAN {
                horseTurnMessage = getString(R.string.minik_swish_horse_human_setting)
                updateHud()
                promptHumanHorseTopic()
            } else {
                horseTurnMessage = getString(
                    currentBotGenderedString(
                        maleRes: R.string.minik_swish_horse_bot_setting_male,
                        femaleRes: R.string.minik_swish_horse_bot_setting_female,
                        neutralRes: R.string.minik_swish_horse_bot_setting_neutral
                    ),
                    currentBotDisplayName()
                )
                updateHud()
                configureBotHorseChallenge()
            }
            return
        }

        guard let challenge = state.challenge else { return }

        if state.currentPlayer == HorseGameEngine.Player.HUMAN {
            horseTurnMessage =
                if challenge.established {
                    getString(R.string.minik_swish_horse_your_turn)
                } else {
                    getString(R.string.minik_swish_horse_human_setting)
                }
            updateHud()

            // Whoever is not shooting steps away so the two prototype characters do not
            // occupy the same physical challenge location.
            // Move one character at a time. Their dribble animation belongs to their own
            // walk, so the two characters no longer bounce the ball in sync.
            courtView.moveBotToHorseWaitingSpot(
                avoidSpotId: challenge.spotId,
                seed: horseVisualSeed(salt: 11),
                animate: true
            ) { [weak self] in
                guard let self else { return }
                if !isAdded || ended { return }

                courtView.moveHumanToHorseSpot(
                    spotId: challenge.spotId,
                    animate: true
                ) { [weak self] in
                    guard let self else { return }
                    if isAdded && !ended {
                        showHorseQuestionForHuman(category: challenge.category)
                    }
                }
            }
        } else {
            horseTurnMessage =
                if challenge.established {
                    getString(
                        currentBotGenderedString(
                            maleRes: R.string.minik_swish_horse_bot_turn_male,
                            femaleRes: R.string.minik_swish_horse_bot_turn_female,
                            neutralRes: R.string.minik_swish_horse_bot_turn_neutral
                        ),
                        currentBotDisplayName()
                    )
                } else {
                    getString(
                    currentBotGenderedString(
                        maleRes: R.string.minik_swish_horse_bot_setting_male,
                        femaleRes: R.string.minik_swish_horse_bot_setting_female,
                        neutralRes: R.string.minik_swish_horse_bot_setting_neutral
                    ),
                    currentBotDisplayName()
                )
                }
            updateHud()

            courtView.moveHumanToHorseWaitingSpot(
                avoidSpotId: challenge.spotId,
                seed: horseVisualSeed(salt: 23),
                animate: true
            ) { [weak self] in
                guard let self else { return }
                if !isAdded || ended { return }

                courtView.moveBotToHorseSpot(
                    spotId: challenge.spotId,
                    animate: true
                ) { [weak self] in
                    guard let self else { return }
                    if isAdded && !ended {
                        runBotHorseAttempt(category: challenge.category)
                    }
                }
            }
        }
    }

    func horseAvailableCategories() -> [QuestionCategory] {
        (config.selectedCategories.isEmpty
            ? Array(QuestionCategory.allCases)
            : config.selectedCategories.elements)
            .kSortedBy { $0.ordinal }
    }

    func promptHumanHorseTopic() {
        if !isAdded || ended { return }
        let categories = horseAvailableCategories()
        guard let current = horseSelectedCategory.flatMap({ categories.contains($0) ? $0 : nil }) ?? categories.first else { return }
        horseSelectedCategory = current
        beginHumanHorseSpotSelection(category: current)
    }

    func beginHumanHorseSpotSelection(category: QuestionCategory) {
        if !isAdded || ended { return }

        horseSelectedCategory = category
        horsePendingCategory = category
        horseWaitingForSpot = true
        horseMoveTouchActive = false
        selectedAnswerIndex = -1

        categoryText.text = ""
        questionText.text = getString(R.string.minik_swish_horse_free_move_instructions) + "\n" + (["he", "iw"].contains(resources.configuration.locales[0].language) ? "אחרי בחירת התשובה: לחצו ומשכו כדי לכוון, ואז שחררו לזריקה." : "After choosing an answer: hold and pull to aim, then release to shoot.")
        questionText.textSize = questionTextSizeFor(length: questionText.text.length)
        questionText.background = questionReadableBackground()

        answerStrip.removeAllViews()
        answerViews.removeAll()
        addHorseSetupControls(currentCategory: category)

        feedbackText.visibility = AView.GONE
        showQuestionUi()

        courtView.setHorseFreeMoveEnabled(enabled: true)
        courtView.moveBotToOpenWaitingSpot(
            seed: horseVisualSeed(salt: 17),
            animate: false
        )
        sensor.prepareForMovement()
    }

    func addHorseSetupControls(currentCategory: QuestionCategory) {
        let categories = horseAvailableCategories()
        if categories.isEmpty { return }

        let language =
            TripleShotGameFragment.game1ConfigurationLanguage(resources)
        let labels = categories.map { $0.labelFor(language) }
        let spinnerLabels = labels.map { "\($0)   \u{25BE}" }

        let spinner = ASpinner(ASpinner.MODE_DROPDOWN)
        let spinnerParams =
            ALinearLayout.LayoutParams(
                ALinearLayout.LayoutParams.MATCH_PARENT,
                dp(v: 52)
            )
        spinnerParams.topMargin = dp(v: 8)
        spinnerParams.bottomMargin = dp(v: 6)
        spinner.layoutParams = spinnerParams
        spinner.minimumHeight = dp(v: 52)
        spinner.textDirection = AView.TEXT_DIRECTION_LOCALE
        let spinnerFace = AGradientDrawable()
        spinnerFace.setColor(FamilyMenu.LEARN); spinnerFace.cornerRadius = dp(v: 14).toFloat()
        spinner.background = spinnerFace
        spinner.setPadding(dp(v: 8), 0, dp(v: 8), 0)
        let popup = AGradientDrawable()
        popup.setColor(AColor.WHITE); popup.cornerRadius = dp(v: 18).toFloat(); popup.setStroke(dp(v: 1), argbInt(0xffb8cde3))
        spinner.setPopupBackgroundDrawable(popup)

        let adapter = HorseTopicAdapter(
            requireContext(),
            android.R.layout.simple_spinner_item,
            spinnerLabels,
            language: language,
            dp: { [unowned self] in self.dp(v: $0) }
        )
        adapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
        spinner.adapter = adapter

        let selectedIndex =
            categories.firstIndex(of: currentCategory) ?? 0
        spinner.setSelection(selectedIndex, false)
        spinner.onItemSelectedListener = ASimpleOnItemSelectedListener(
            onItemSelected: { [weak self] _, _, position, _ in
                guard let self else { return }
                guard let selected = categories.getOrNull(position) else { return }
                horseSelectedCategory = selected
                horsePendingCategory = selected
            },
            onNothingSelected: { _ in }
        )

        let readyButton = TripleShotButton()
        let readyParams =
            ALinearLayout.LayoutParams(
                ALinearLayout.LayoutParams.MATCH_PARENT,
                dp(v: 52)
            )
        readyParams.topMargin = dp(v: 8)
        readyButton.layoutParams = readyParams
        readyButton.minHeight = 0
        readyButton.minWidth = 0
        readyButton.setInsetTop(0)
        readyButton.setInsetBottom(0)
        readyButton.setAllCaps(false)
        readyButton.text = getString(R.string.minik_swish_horse_ready_to_aim)
        readyButton.textSize = 17
        readyButton.setTextColor(AColor.WHITE)
        readyButton.setBackgroundTintList(
            AColorStateList.valueOf(AColor.rgb(20, 129, 111))
        )
        readyButton.setOnClickListener { [weak self] _ in
            guard let self else { return }
            if isLiveHorseMode() { confirmLiveHorseFreeSpot() }
            else { confirmHumanHorseFreeSpot() }
        }

        answerStrip.addView(spinner)
        answerStrip.addView(readyButton)
        addChallengeExitLink()
    }

    func confirmHumanHorseFreeSpot() {
        if !horseWaitingForSpot || ended { return }

        guard let category = horsePendingCategory ?? horseSelectedCategory else { return }
        guard let engine = horseEngine else { return }
        guard let spotId = courtView.lockCurrentHorseFreeSpot() else { return }

        horseWaitingForSpot = false
        horseMoveTouchActive = false
        horsePendingCategory = nil
        sensor.prepareForAnswer()

        do {
            try engine.configureChallenge(
                player: HorseGameEngine.Player.HUMAN,
                category: category,
                spotId: spotId
            )
        } catch {
            return
        }

        advanceHorseTurn()
    }

    func configureBotHorseChallenge() {
        guard let engine = horseEngine else { return }
        let categories = horseAvailableCategories()

        if categories.isEmpty { return }

        let random = KotlinRandom(seed: horseVisualSeed(salt: 31))
        let category = categories[random.nextInt(categories.count)]
        let spotId = courtView.randomHorseSpotIdForBot(seed: horseVisualSeed(salt: 37))

        // Kotlin calls this without a catch: a rule violation crashes, as it does here.
        try! engine.configureChallenge(
            player: HorseGameEngine.Player.BOT,
            category: category,
            spotId: spotId
        )

        categoryText.text = getString(
                    currentBotGenderedString(
                        maleRes: R.string.minik_swish_horse_bot_setting_male,
                        femaleRes: R.string.minik_swish_horse_bot_setting_female,
                        neutralRes: R.string.minik_swish_horse_bot_setting_neutral
                    ),
                    currentBotDisplayName()
                )
        questionText.text =
            getString(
                currentBotGenderedString(
                    maleRes: R.string.minik_swish_horse_bot_chose_male,
                    femaleRes: R.string.minik_swish_horse_bot_chose_female,
                    neutralRes: R.string.minik_swish_horse_bot_chose_neutral
                ),
                currentBotDisplayName(),
                category.labelFor(
                    TripleShotGameFragment.game1ConfigurationLanguage(resources)
                )
            )
        questionText.textSize = 14.5
        questionText.background = questionReadableBackground()
        answerStrip.removeAllViews()
        answerViews.removeAll()
        showQuestionUi()

        handler.postDelayed({ [weak self] in
            guard let self else { return }
            if isAdded && !ended {
                advanceHorseTurn()
            }
        }, 520)
    }

    // MARK: - Part 1 helpers (iOS)

    /// `(ConfigurationCompat.getLocales(resources.configuration)[0] ?: Locale.getDefault()).language.orEmpty()`, the
    /// expression the Kotlin repeats at every language check; each call site keeps its own rule (he/iw, en, ...).
    static func game1ConfigurationLanguage(_ resources: AContextResources) -> String {
        (AConfigurationCompat.getLocales(resources.configuration).get(0) ?? ALocale.getDefault()).language
    }

    /// Kotlin `view.findViewById(R.id.x)` assigned to a non-null (lateinit) property: a missing view or a view of
    /// another class crashes at the assignment, as the Kotlin null check / cast does.
    static func game1RequireView<T: AView>(_ root: AView, _ id: String, _ type: T.Type) -> T {
        let found: T? = root.findViewById(id)
        return found!
    }
}

// MARK: - res/layout/fragment_triple_shot_game.xml

/// The view tree of `res/layout/fragment_triple_shot_game.xml`, built in code with the XML's ids, attributes and
/// layout params (DESIGN 2.8), in XML order. Dimensions are read like the Android inflater reads them: sizes,
/// margins, paddings, text sizes, corner radii of buttons and stroke widths as pixel sizes (`getDimensionPixelSize`,
/// rounded), elevations and card corner radii as exact dimensions (`getDimension`). Styles are the AndroidKit widget
/// styles (`Widget.MaterialComponents.Button.OutlinedButton` -> `.OUTLINED`, `...TextButton` -> `.TEXT`). The
/// app-wide restylers (FamilySkyUi / FamilyFormStyle / TripleShotControls) run on this tree from the activity's decor
/// view, as on Android.
///
/// One iOS-only element is added (DESIGN 12.3): the exit control `TripleShotGameFragment.IOS_EXIT_BUTTON_ID` at the
/// top-end of the HUD row; the HUD's end edge is constrained to it instead of to the parent.
enum TripleShotGameLayout {

    /// `getDimensionPixelSize` of an XML `Ndp`.
    static func px(_ dp: Float) -> Int {
        ATypedValue.toDimensionPixelSize(ATypedValue.COMPLEX_UNIT_DIP, dp)
    }

    /// `getDimension` of an XML `Ndp`.
    static func dimen(_ dp: Float) -> Float {
        ATypedValue.applyDimension(ATypedValue.COMPLEX_UNIT_DIP, dp)
    }

    /// `android:textStyle="bold"` (TextView.setTypefaceFromAttrs: the family's normal face, then setTypeface(tf, BOLD)).
    static func bold(_ textView: ATextView) {
        textView.setTypeface(textView.typeface, ATypeface.BOLD)
    }

    static func build() -> AView {
        let MATCH = AViewGroup.LayoutParams.MATCH_PARENT
        let WRAP = AViewGroup.LayoutParams.WRAP_CONTENT
        let PARENT = AConstraintLayout.LayoutParams.PARENT_ID

        // <androidx.constraintlayout.widget.ConstraintLayout match_parent x match_parent layoutDirection="locale"
        //  background="#101820">
        let root = AConstraintLayout()
        root.layoutParams = AViewGroup.LayoutParams(MATCH, MATCH)
        root.layoutDirection = AView.LAYOUT_DIRECTION_LOCALE
        root.setBackgroundColor(AColor.parseColor("#101820"))

        // <ImageView @+id/gameBackground 0dp x 0dp scaleType="matrix" src="@drawable/triple_shot_court_background"
        //  constrained to the four parent edges>
        let gameBackground = AImageView()
        gameBackground.viewId = R.id.gameBackground
        gameBackground.scaleType = AImageView.ScaleType.MATRIX
        gameBackground.setImageResource(R.drawable.triple_shot_court_background)
        let gameBackgroundParams = AConstraintLayout.LayoutParams(0, 0)
        gameBackgroundParams.bottomToBottom = PARENT
        gameBackgroundParams.endToEnd = PARENT
        gameBackgroundParams.startToStart = PARENT
        gameBackgroundParams.topToTop = PARENT
        root.addView(gameBackground, gameBackgroundParams)

        // <com.appsbybros.minik.swish.view.TripleShotCourtView @+id/courtView 0dp x 0dp, four parent edges>
        let courtView = TripleShotCourtView()
        courtView.viewId = R.id.courtView
        let courtParams = AConstraintLayout.LayoutParams(0, 0)
        courtParams.bottomToBottom = PARENT
        courtParams.endToEnd = PARENT
        courtParams.startToStart = PARENT
        courtParams.topToTop = PARENT
        root.addView(courtView, courtParams)

        // V18: one thin HUD row for the whole match. Keeping each value in a separate
        // TextView prevents RTL/BiDi from scrambling Hebrew, numbers and emoji.
        // <LinearLayout @+id/topHud 0dp x 38dp marginStart 6 marginTop 5 marginEnd 6 background triple_shot_panel
        //  elevation 5dp gravity center_vertical horizontal paddingStart/End 5dp, start/end/top to parent>
        let topHud = ALinearLayout()
        topHud.viewId = R.id.topHud
        topHud.setBackgroundResource(R.drawable.triple_shot_panel)
        topHud.elevation = dimen(5)
        topHud.gravity = AGravity.CENTER_VERTICAL
        topHud.orientation = ALinearLayout.HORIZONTAL
        topHud.setPaddingRelative(px(5), 0, px(5), 0)
        let topHudParams = AConstraintLayout.LayoutParams(0, px(38))
        topHudParams.marginStart = px(6)
        topHudParams.topMargin = px(5)
        // iOS-only (DESIGN 12.3): the end edge stops at the exit control (XML: endToEnd parent, marginEnd 6dp).
        topHudParams.marginEnd = px(3)
        topHudParams.endToStart = TripleShotGameFragment.IOS_EXIT_BUTTON_ID
        topHudParams.startToStart = PARENT
        topHudParams.topToTop = PARENT

        func hudCell(_ id: String, _ weight: Float, _ color: String, _ sp: Float) -> ATextView {
            let cell = ATextView()
            cell.viewId = id
            cell.gravity = AGravity.CENTER
            cell.maxLines = 1
            cell.setTextColor(AColor.parseColor(color))
            cell.textDirection = AView.TEXT_DIRECTION_LOCALE
            cell.applyXmlTextSize(sp)
            bold(cell)
            cell.layoutParams = ALinearLayout.LayoutParams(0, MATCH, weight)
            return cell
        }
        // <TextView @+id/timeText 0dp x match weight 0.82 center maxLines 1 #142129 locale 12.5sp bold>
        topHud.addView(hudCell(R.id.timeText, 0.82, "#142129", 12.5))
        // <TextView @+id/scoreText weight 0.95 ... #142129 12.5sp bold>
        topHud.addView(hudCell(R.id.scoreText, 0.95, "#142129", 12.5))
        // <TextView @+id/botScoreText weight 1.0 singleLine ellipsize="middle" #6B3EB4 12.5sp bold gone>
        let botScoreText = hudCell(R.id.botScoreText, 1.0, "#6B3EB4", 12.5)
        botScoreText.applyXmlSingleLine(true, hasXmlEllipsize: true)
        botScoreText.ellipsize = ATextUtils.TruncateAt.MIDDLE
        botScoreText.visibility = AView.GONE
        topHud.addView(botScoreText)
        // <TextView @+id/ballsText weight 1.0 #142129 12.5sp bold gone>
        let ballsText = hudCell(R.id.ballsText, 1.0, "#142129", 12.5)
        ballsText.visibility = AView.GONE
        topHud.addView(ballsText)
        // <TextView @+id/streakText weight 1.25 #6B3EB4 12.5sp bold>
        topHud.addView(hudCell(R.id.streakText, 1.25, "#6B3EB4", 12.5))
        root.addView(topHud, topHudParams)

        // Question / answers / score live over the LEFT forest (obsolete XML comment: the runtime
        // configureCenteredQuestionLayout() centres the card at 90 %).
        // <LinearLayout @+id/questionCard 0dp x wrap marginLeft 7 marginTop 3 gravity center_horizontal vertical
        //  paddingStart/End 3dp elevation 6dp horizontal_bias 0 left/right to parent, top to bottom of topHud,
        //  width_percent 0.58>
        let questionCard = ALinearLayout()
        questionCard.viewId = R.id.questionCard
        questionCard.gravity = AGravity.CENTER_HORIZONTAL
        questionCard.orientation = ALinearLayout.VERTICAL
        questionCard.setPaddingRelative(px(3), 0, px(3), 0)
        questionCard.elevation = dimen(6)
        let questionCardParams = AConstraintLayout.LayoutParams(0, WRAP)
        questionCardParams.leftMargin = px(7)
        questionCardParams.topMargin = px(3)
        questionCardParams.horizontalBias = 0
        questionCardParams.leftToLeft = PARENT
        questionCardParams.rightToRight = PARENT
        questionCardParams.topToBottom = R.id.topHud
        questionCardParams.matchConstraintPercentWidth = 0.58
        questionCardParams.matchConstraintDefaultWidth = AConstraintLayout.LayoutParams.MATCH_CONSTRAINT_PERCENT

        //   <LinearLayout match x 34dp gravity center_vertical horizontal>
        let header = ALinearLayout()
        header.gravity = AGravity.CENTER_VERTICAL
        header.orientation = ALinearLayout.HORIZONTAL
        header.layoutParams = ALinearLayout.LayoutParams(MATCH, px(34))

        //     <TripleShotButton @+id/tutorialHelpButton style OutlinedButton 32dp x 32dp insetTop/Bottom 0 minWidth 0
        //      minHeight 0 padding 0 text "?" contentDescription allCaps false #087E70 16sp bold backgroundTint
        //      #28FFFFFF cornerRadius 11dp strokeColor #DFFFFFFF strokeWidth 1dp>
        let help = TripleShotButton(style: .OUTLINED)
        help.viewId = R.id.tutorialHelpButton
        help.layoutParams = ALinearLayout.LayoutParams(px(32), px(32))
        help.setText(res: R.string.minik_swish_tutorial_help_symbol)
        help.contentDescription = getString(R.string.minik_swish_tutorial_help_description)
        help.setAllCaps(false)
        help.setTextColor(AColor.parseColor("#087E70"))
        help.applyXmlTextSize(16)
        bold(help)
        help.minWidth = 0
        help.minimumWidth = 0
        help.minHeight = 0
        help.minimumHeight = 0
        help.setInsetTop(0)
        help.setInsetBottom(0)
        help.setCornerRadius(px(11))
        help.setStrokeColor(AColorStateList.valueOf(AColor.parseColor("#DFFFFFFF")))
        help.setStrokeWidth(px(1))
        help.setBackgroundTintList(AColorStateList.valueOf(AColor.parseColor("#28FFFFFF")))
        help.applyXmlPadding(0, 0, 0, 0)
        header.addView(help)

        //     <OutlinedTextView @+id/categoryText 0dp x wrap marginStart 5dp weight 1 gravity center_vertical
        //      maxLines 1 #7042B8 locale 11sp bold>
        let categoryText = OutlinedTextView()
        categoryText.viewId = R.id.categoryText
        categoryText.gravity = AGravity.CENTER_VERTICAL
        categoryText.maxLines = 1
        categoryText.setTextColor(AColor.parseColor("#7042B8"))
        categoryText.textDirection = AView.TEXT_DIRECTION_LOCALE
        categoryText.applyXmlTextSize(11)
        bold(categoryText)
        let categoryParams = ALinearLayout.LayoutParams(0, WRAP, 1)
        categoryParams.marginStart = px(5)
        categoryText.layoutParams = categoryParams
        header.addView(categoryText)
        questionCard.addView(header)

        //   <OutlinedTextView @+id/questionText match x wrap ellipsize end gravity center includeFontPadding false
        //    lineSpacingExtra 1dp maxLines 4 paddingHorizontal 7dp paddingVertical 5dp #142129 locale 15.5sp bold>
        let questionText = OutlinedTextView()
        questionText.viewId = R.id.questionText
        questionText.ellipsize = ATextUtils.TruncateAt.END
        questionText.gravity = AGravity.CENTER
        questionText.includeFontPadding = false
        questionText.setLineSpacing(Float(px(1)), 1)
        questionText.maxLines = 4
        questionText.setPadding(px(7), px(5), px(7), px(5))
        questionText.setTextColor(AColor.parseColor("#142129"))
        questionText.textDirection = AView.TEXT_DIRECTION_LOCALE
        questionText.applyXmlTextSize(15.5)
        bold(questionText)
        questionText.layoutParams = ALinearLayout.LayoutParams(MATCH, WRAP)
        questionCard.addView(questionText)

        //   <TextView @+id/horseMoveHelpDismissText wrap x 32dp layout_gravity center_horizontal gravity center
        //    minWidth 64dp paddingHorizontal 8dp text minik_swish_horse_move_help_dismiss #1769AA locale 12.5sp bold
        //    gone> (never referenced in code)
        let horseMoveHelpDismissText = ATextView()
        horseMoveHelpDismissText.viewId = R.id.horseMoveHelpDismissText
        horseMoveHelpDismissText.gravity = AGravity.CENTER
        horseMoveHelpDismissText.minWidth = px(64)
        horseMoveHelpDismissText.minimumWidth = px(64)
        horseMoveHelpDismissText.setPadding(px(8), 0, px(8), 0)
        horseMoveHelpDismissText.setText(res: R.string.minik_swish_horse_move_help_dismiss)
        horseMoveHelpDismissText.setTextColor(AColor.parseColor("#1769AA"))
        horseMoveHelpDismissText.textDirection = AView.TEXT_DIRECTION_LOCALE
        horseMoveHelpDismissText.applyXmlTextSize(12.5)
        bold(horseMoveHelpDismissText)
        horseMoveHelpDismissText.visibility = AView.GONE
        let horseMoveHelpParams = ALinearLayout.LayoutParams(WRAP, px(32))
        horseMoveHelpParams.gravity = AGravity.CENTER_HORIZONTAL
        horseMoveHelpDismissText.layoutParams = horseMoveHelpParams
        questionCard.addView(horseMoveHelpDismissText)

        //   Answers are created dynamically as thin transparent outlined capsules.
        //   <LinearLayout @+id/answerStrip match x wrap marginTop 3dp gravity center vertical>
        let answerStrip = ALinearLayout()
        answerStrip.viewId = R.id.answerStrip
        answerStrip.gravity = AGravity.CENTER
        answerStrip.orientation = ALinearLayout.VERTICAL
        let answerStripParams = ALinearLayout.LayoutParams(MATCH, WRAP)
        answerStripParams.topMargin = px(3)
        answerStrip.layoutParams = answerStripParams
        questionCard.addView(answerStrip)

        //   <OutlinedTextView @+id/feedbackText match x wrap marginTop 4dp background triple_shot_feedback_panel
        //    gravity center includeFontPadding false lineSpacingExtra 1dp maxLines 8 paddingHorizontal 8dp
        //    paddingVertical 6dp #142129 locale 16sp bold gone>
        let feedbackText = OutlinedTextView()
        feedbackText.viewId = R.id.feedbackText
        feedbackText.setBackgroundResource(R.drawable.triple_shot_feedback_panel)
        feedbackText.gravity = AGravity.CENTER
        feedbackText.includeFontPadding = false
        feedbackText.setLineSpacing(Float(px(1)), 1)
        feedbackText.maxLines = 8
        feedbackText.setPadding(px(8), px(6), px(8), px(6))
        feedbackText.setTextColor(AColor.parseColor("#142129"))
        feedbackText.textDirection = AView.TEXT_DIRECTION_LOCALE
        feedbackText.applyXmlTextSize(16)
        bold(feedbackText)
        feedbackText.visibility = AView.GONE
        let feedbackParams = ALinearLayout.LayoutParams(MATCH, WRAP)
        feedbackParams.topMargin = px(4)
        feedbackText.layoutParams = feedbackParams
        questionCard.addView(feedbackText)
        root.addView(questionCard, questionCardParams)

        // Small per-shot animation selector. Hidden until an answer is locked. (Never referenced in code.)
        // <TripleShotButton @+id/shotStyleButton style OutlinedButton wrap x 34dp marginTop 4dp marginEnd 7dp
        //  insetTop/Bottom 0 minWidth/minHeight 0 paddingStart/End 8dp text minik_swish_shot_style_pro
        //  contentDescription minik_swish_shot_style_change allCaps false #142129 10.5sp bold gone backgroundTint
        //  #E6FFFDF5 cornerRadius 11dp end to parent, top to bottom of topHud, strokeColor #A0087E70 strokeWidth 1dp>
        let shotStyleButton = TripleShotButton(style: .OUTLINED)
        shotStyleButton.viewId = R.id.shotStyleButton
        shotStyleButton.setText(res: R.string.minik_swish_shot_style_pro)
        shotStyleButton.contentDescription = getString(R.string.minik_swish_shot_style_change)
        shotStyleButton.setAllCaps(false)
        shotStyleButton.setTextColor(AColor.parseColor("#142129"))
        shotStyleButton.applyXmlTextSize(10.5)
        bold(shotStyleButton)
        shotStyleButton.minWidth = 0
        shotStyleButton.minimumWidth = 0
        shotStyleButton.minHeight = 0
        shotStyleButton.minimumHeight = 0
        shotStyleButton.visibility = AView.GONE
        shotStyleButton.setInsetTop(0)
        shotStyleButton.setInsetBottom(0)
        shotStyleButton.setCornerRadius(px(11))
        shotStyleButton.setStrokeColor(AColorStateList.valueOf(AColor.parseColor("#A0087E70")))
        shotStyleButton.setStrokeWidth(px(1))
        shotStyleButton.setBackgroundTintList(AColorStateList.valueOf(AColor.parseColor("#E6FFFDF5")))
        // android:paddingStart / paddingEnd only: the style's top / bottom padding stays (insets are 0 here).
        shotStyleButton.applyXmlPaddingRelative(px(8), shotStyleButton.paddingTop, px(8), shotStyleButton.paddingBottom)
        let shotStyleParams = AConstraintLayout.LayoutParams(WRAP, px(34))
        shotStyleParams.topMargin = px(4)
        shotStyleParams.marginEnd = px(7)
        shotStyleParams.endToEnd = PARENT
        shotStyleParams.topToBottom = R.id.topHud
        root.addView(shotStyleButton, shotStyleParams)

        // <HorizontalScrollView @+id/opponentsScroll 0dp x wrap marginStart/End/Bottom 8dp fillViewport
        //  scrollbars none gone, bottom/end/start to parent>
        let opponentsScroll = AHorizontalScrollView()
        opponentsScroll.viewId = R.id.opponentsScroll
        opponentsScroll.isFillViewport = true
        opponentsScroll.isHorizontalScrollBarEnabled = false
        opponentsScroll.isVerticalScrollBarEnabled = false
        opponentsScroll.visibility = AView.GONE
        let opponentsScrollParams = AConstraintLayout.LayoutParams(0, WRAP)
        opponentsScrollParams.marginStart = px(8)
        opponentsScrollParams.marginEnd = px(8)
        opponentsScrollParams.bottomMargin = px(8)
        opponentsScrollParams.bottomToBottom = PARENT
        opponentsScrollParams.endToEnd = PARENT
        opponentsScrollParams.startToStart = PARENT
        //   <LinearLayout @+id/opponentsContainer wrap x wrap horizontal>
        let opponentsContainer = ALinearLayout()
        opponentsContainer.viewId = R.id.opponentsContainer
        opponentsContainer.orientation = ALinearLayout.HORIZONTAL
        opponentsScroll.addView(opponentsContainer, AFrameLayout.LayoutParams(WRAP, WRAP))
        root.addView(opponentsScroll, opponentsScrollParams)

        // Tutorial intentionally remains a real translucent card: it is temporary teaching UI.
        // <MaterialCardView @+id/tutorialCard 0dp x wrap marginStart/End 14dp gone cardBackgroundColor #CCFFFFFF
        //  cardCornerRadius 18dp cardElevation 4dp four parent edges vertical_bias 0.43 width_max 620dp
        //  strokeColor #AA32BFA8 strokeWidth 2dp>
        let tutorialCard = ACardView()
        tutorialCard.viewId = R.id.tutorialCard
        tutorialCard.visibility = AView.GONE
        tutorialCard.setCardBackgroundColor(AColor.parseColor("#CCFFFFFF"))
        tutorialCard.radius = dimen(18)
        tutorialCard.cardElevation = dimen(4)
        tutorialCard.setStrokeColor(AColorStateList.valueOf(AColor.parseColor("#AA32BFA8")))
        tutorialCard.strokeWidth = px(2)
        let tutorialCardParams = AConstraintLayout.LayoutParams(0, WRAP)
        tutorialCardParams.marginStart = px(14)
        tutorialCardParams.marginEnd = px(14)
        tutorialCardParams.bottomToBottom = PARENT
        tutorialCardParams.endToEnd = PARENT
        tutorialCardParams.startToStart = PARENT
        tutorialCardParams.topToTop = PARENT
        tutorialCardParams.verticalBias = 0.43
        tutorialCardParams.matchConstraintMaxWidth = px(620)

        //   <LinearLayout match x wrap vertical paddingStart 14 paddingTop 9 paddingEnd 14 paddingBottom 8>
        let tutorialColumn = ALinearLayout()
        tutorialColumn.orientation = ALinearLayout.VERTICAL
        tutorialColumn.setPaddingRelative(px(14), px(9), px(14), px(8))

        //     <TextView @+id/tutorialTitle match x wrap gravity center @color/triple_shot_green 16sp bold>
        let tutorialTitle = ATextView()
        tutorialTitle.viewId = R.id.tutorialTitle
        tutorialTitle.gravity = AGravity.CENTER
        tutorialTitle.setTextColor(R.color.triple_shot_green)
        tutorialTitle.applyXmlTextSize(16)
        bold(tutorialTitle)
        tutorialTitle.layoutParams = ALinearLayout.LayoutParams(MATCH, WRAP)
        tutorialColumn.addView(tutorialTitle)

        //     <TextView @+id/tutorialBody match x wrap marginTop 4dp gravity center lineSpacingExtra 2dp
        //      @color/triple_shot_ink 14sp>
        let tutorialBody = ATextView()
        tutorialBody.viewId = R.id.tutorialBody
        tutorialBody.gravity = AGravity.CENTER
        tutorialBody.setLineSpacing(Float(px(2)), 1)
        tutorialBody.setTextColor(R.color.triple_shot_ink)
        tutorialBody.applyXmlTextSize(14)
        let tutorialBodyParams = ALinearLayout.LayoutParams(MATCH, WRAP)
        tutorialBodyParams.topMargin = px(4)
        tutorialBody.layoutParams = tutorialBodyParams
        tutorialColumn.addView(tutorialBody)

        //     <LinearLayout match x 40dp marginTop 4dp gravity center horizontal>
        let tutorialButtons = ALinearLayout()
        tutorialButtons.gravity = AGravity.CENTER
        tutorialButtons.orientation = ALinearLayout.HORIZONTAL
        let tutorialButtonsParams = ALinearLayout.LayoutParams(MATCH, px(40))
        tutorialButtonsParams.topMargin = px(4)
        tutorialButtons.layoutParams = tutorialButtonsParams

        //       <TripleShotButton @+id/tutorialPrevButton / @+id/tutorialNextButton style TextButton 0dp x 40dp
        //        weight 1 insetTop/Bottom 0 minWidth/minHeight 0 allCaps false @color/triple_shot_green>
        func tutorialTextButton(_ id: String, _ text: AStringRes) -> TripleShotButton {
            let button = TripleShotButton(style: .TEXT)
            button.viewId = id
            button.layoutParams = ALinearLayout.LayoutParams(0, px(40), 1)
            button.setText(res: text)
            button.setAllCaps(false)
            button.setTextColor(R.color.triple_shot_green)
            button.minWidth = 0
            button.minimumWidth = 0
            button.minHeight = 0
            button.minimumHeight = 0
            button.setInsetTop(0)
            button.setInsetBottom(0)
            return button
        }
        tutorialButtons.addView(tutorialTextButton(R.id.tutorialPrevButton, R.string.minik_swish_tutorial_previous))
        tutorialButtons.addView(tutorialTextButton(R.id.tutorialNextButton, R.string.minik_swish_tutorial_next))
        tutorialColumn.addView(tutorialButtons)

        //     <TripleShotButton @+id/tutorialDismissButton style TextButton wrap x 36dp layout_gravity
        //      center_horizontal insetTop/Bottom 0 minHeight 0 allCaps false @color/triple_shot_purple>
        let tutorialDismissButton = TripleShotButton(style: .TEXT)
        tutorialDismissButton.viewId = R.id.tutorialDismissButton
        let dismissParams = ALinearLayout.LayoutParams(WRAP, px(36))
        dismissParams.gravity = AGravity.CENTER_HORIZONTAL
        tutorialDismissButton.layoutParams = dismissParams
        tutorialDismissButton.setText(res: R.string.minik_swish_tutorial_dismiss)
        tutorialDismissButton.setAllCaps(false)
        tutorialDismissButton.setTextColor(R.color.triple_shot_purple)
        tutorialDismissButton.minHeight = 0
        tutorialDismissButton.minimumHeight = 0
        tutorialDismissButton.setInsetTop(0)
        tutorialDismissButton.setInsetBottom(0)
        tutorialColumn.addView(tutorialDismissButton)
        tutorialCard.addView(tutorialColumn, AFrameLayout.LayoutParams(MATCH, WRAP))
        root.addView(tutorialCard, tutorialCardParams)

        // <FrameLayout @+id/resultOverlay 0dp x 0dp background #990B1D21 clickable focusable gone, four parent edges>
        let resultOverlay = AFrameLayout()
        resultOverlay.viewId = R.id.resultOverlay
        resultOverlay.setBackgroundColor(AColor.parseColor("#990B1D21"))
        resultOverlay.isClickable = true
        resultOverlay.isFocusable = true
        resultOverlay.visibility = AView.GONE
        let resultOverlayParams = AConstraintLayout.LayoutParams(0, 0)
        resultOverlayParams.bottomToBottom = PARENT
        resultOverlayParams.endToEnd = PARENT
        resultOverlayParams.startToStart = PARENT
        resultOverlayParams.topToTop = PARENT

        //   <ScrollView @+id/basketballResultScroll match x wrap layout_gravity center layout_margin 16dp
        //    fillViewport false>
        let resultScroll = AScrollView()
        resultScroll.viewId = R.id.basketballResultScroll
        resultScroll.isFillViewport = false
        let resultScrollParams = AFrameLayout.LayoutParams(MATCH, WRAP, AGravity.CENTER)
        resultScrollParams.setMargins(px(16), px(16), px(16), px(16))

        //     <MaterialCardView match x wrap layout_gravity center layout_margin 0dp cardBackgroundColor #FFFDF5
        //      cardCornerRadius 24dp cardElevation 8dp>
        let resultCard = ACardView()
        resultCard.setCardBackgroundColor(AColor.parseColor("#FFFDF5"))
        resultCard.radius = dimen(24)
        resultCard.cardElevation = dimen(8)
        let resultCardParams = AFrameLayout.LayoutParams(MATCH, WRAP, AGravity.CENTER)
        resultCardParams.setMargins(0, 0, 0, 0)

        //       <LinearLayout match x wrap gravity center_horizontal vertical padding 22dp>
        let resultColumn = ALinearLayout()
        resultColumn.gravity = AGravity.CENTER_HORIZONTAL
        resultColumn.orientation = ALinearLayout.VERTICAL
        resultColumn.setPadding(px(22), px(22), px(22), px(22))

        //         <TextView wrap x wrap text triple_shot_results @color/triple_shot_ink 28sp bold>
        let resultTitle = ATextView()
        resultTitle.setText(res: R.string.triple_shot_results)
        resultTitle.setTextColor(R.color.triple_shot_ink)
        resultTitle.applyXmlTextSize(28)
        bold(resultTitle)
        resultTitle.layoutParams = ALinearLayout.LayoutParams(WRAP, WRAP)
        resultColumn.addView(resultTitle)

        //         <TextView @+id/resultScoreText match x wrap marginTop 10dp gravity center triple_shot_green 42sp bold>
        let resultScoreText = ATextView()
        resultScoreText.viewId = R.id.resultScoreText
        resultScoreText.gravity = AGravity.CENTER
        resultScoreText.setTextColor(R.color.triple_shot_green)
        resultScoreText.applyXmlTextSize(42)
        bold(resultScoreText)
        let resultScoreParams = ALinearLayout.LayoutParams(MATCH, WRAP)
        resultScoreParams.topMargin = px(10)
        resultScoreText.layoutParams = resultScoreParams
        resultColumn.addView(resultScoreText)

        //         <TextView @+id/resultStatsText match x wrap marginTop 8dp gravity center lineSpacingExtra 3dp
        //          triple_shot_ink 16sp>
        let resultStatsText = ATextView()
        resultStatsText.viewId = R.id.resultStatsText
        resultStatsText.gravity = AGravity.CENTER
        resultStatsText.setLineSpacing(Float(px(3)), 1)
        resultStatsText.setTextColor(R.color.triple_shot_ink)
        resultStatsText.applyXmlTextSize(16)
        let resultStatsParams = ALinearLayout.LayoutParams(MATCH, WRAP)
        resultStatsParams.topMargin = px(8)
        resultStatsText.layoutParams = resultStatsParams
        resultColumn.addView(resultStatsText)

        //         <TextView @+id/resultRankText match x wrap marginTop 8dp gravity center triple_shot_purple 18sp bold>
        let resultRankText = ATextView()
        resultRankText.viewId = R.id.resultRankText
        resultRankText.gravity = AGravity.CENTER
        resultRankText.setTextColor(R.color.triple_shot_purple)
        resultRankText.applyXmlTextSize(18)
        bold(resultRankText)
        let resultRankParams = ALinearLayout.LayoutParams(MATCH, WRAP)
        resultRankParams.topMargin = px(8)
        resultRankText.layoutParams = resultRankParams
        resultColumn.addView(resultRankText)

        //         <TripleShotButton @+id/resultLeaderboardButton match x 52dp marginTop 16dp text
        //          triple_shot_leaderboard allCaps false backgroundTint triple_shot_purple cornerRadius 17dp>
        let leaderboardButton = TripleShotButton()
        leaderboardButton.viewId = R.id.resultLeaderboardButton
        leaderboardButton.setText(res: R.string.triple_shot_leaderboard)
        leaderboardButton.setAllCaps(false)
        leaderboardButton.setCornerRadius(px(17))
        leaderboardButton.setBackgroundTintList(AColorStateList.valueOf(R.color.triple_shot_purple))
        let leaderboardParams = ALinearLayout.LayoutParams(MATCH, px(52))
        leaderboardParams.topMargin = px(16)
        leaderboardButton.layoutParams = leaderboardParams
        resultColumn.addView(leaderboardButton)

        //         <LinearLayout match x wrap marginTop 8dp horizontal>
        let resultButtons = ALinearLayout()
        resultButtons.orientation = ALinearLayout.HORIZONTAL
        let resultButtonsParams = ALinearLayout.LayoutParams(MATCH, WRAP)
        resultButtonsParams.topMargin = px(8)
        resultButtons.layoutParams = resultButtonsParams

        //           <TripleShotButton @+id/resultAgainButton 0dp x 50dp weight 1 text triple_shot_play_again
        //            allCaps false backgroundTint triple_shot_green cornerRadius 17dp>
        let againButton = TripleShotButton()
        againButton.viewId = R.id.resultAgainButton
        againButton.setText(res: R.string.triple_shot_play_again)
        againButton.setAllCaps(false)
        againButton.setCornerRadius(px(17))
        againButton.setBackgroundTintList(AColorStateList.valueOf(R.color.triple_shot_green))
        againButton.layoutParams = ALinearLayout.LayoutParams(0, px(50), 1)
        resultButtons.addView(againButton)

        //           <TripleShotButton @+id/resultHomeButton style OutlinedButton 0dp x 50dp marginStart 8dp weight 1
        //            text triple_shot_home allCaps false cornerRadius 17dp strokeColor triple_shot_green>
        let homeButton = TripleShotButton(style: .OUTLINED)
        homeButton.viewId = R.id.resultHomeButton
        homeButton.setText(res: R.string.triple_shot_home)
        homeButton.setAllCaps(false)
        homeButton.setCornerRadius(px(17))
        homeButton.setStrokeColor(AColorStateList.valueOf(R.color.triple_shot_green))
        let homeParams = ALinearLayout.LayoutParams(0, px(50), 1)
        homeParams.marginStart = px(8)
        homeButton.layoutParams = homeParams
        resultButtons.addView(homeButton)
        resultColumn.addView(resultButtons)

        resultCard.addView(resultColumn, AFrameLayout.LayoutParams(MATCH, WRAP))
        resultScroll.addView(resultCard, resultCardParams)
        resultOverlay.addView(resultScroll, resultScrollParams)
        root.addView(resultOverlay, resultOverlayParams)

        // iOS-only (DESIGN 12.3): the exit control that stands in for system Back (no XML counterpart). 36 x 36 dp at
        // the top-end (left in RTL), vertically centred on the 30 dp HUD row, above every elevation-0 layer (court,
        // result overlay, tap-to-continue overlay) like the HUD; the app's red `triple_close` art fitted in 24 dp.
        let exitButton = AImageView()
        exitButton.viewId = TripleShotGameFragment.IOS_EXIT_BUTTON_ID
        exitButton.scaleType = AImageView.ScaleType.FIT_CENTER
        exitButton.setImageResource(R.drawable.triple_close)
        exitButton.setPadding(px(6), px(6), px(6), px(6))
        exitButton.elevation = dimen(5)
        exitButton.isClickable = true
        exitButton.isFocusable = true
        exitButton.contentDescription = getString(R.string.minik_swish_one_on_one_exit_game)
        let exitParams = AConstraintLayout.LayoutParams(px(36), px(36))
        exitParams.topMargin = px(2)
        exitParams.marginEnd = px(3)
        exitParams.endToEnd = PARENT
        exitParams.topToTop = PARENT
        root.addView(exitButton, exitParams)

        return root
    }
}

/// Kotlin `object : ArrayAdapter<String>(requireContext(), simple_spinner_item, spinnerLabels)` of
/// addHorseSetupControls: every row and the selected view in the readable HORSE topic style.
private final class HorseTopicAdapter: AArrayAdapter<String> {
    private let language: String
    private let dp: (Int) -> Int

    init(_ context: AContext, _ resource: String, _ objects: [String], language: String, dp: @escaping (Int) -> Int) {
        self.language = language
        self.dp = dp
        super.init(context, resource, objects)
    }

    private func readable(_ view: AView) -> AView {
        if let text = view as? ATextView {
            text.setTextColor(argbInt(0xff17243b)); text.textSize = 17
            text.layoutDirection = ["he", "iw"].contains(language) ? AView.LAYOUT_DIRECTION_RTL : AView.LAYOUT_DIRECTION_LTR
            text.textDirection = AView.TEXT_DIRECTION_LOCALE; text.gravity = AGravity.START | AGravity.CENTER_VERTICAL
            text.minHeight = dp(48); text.setPadding(dp(12), dp(8), dp(12), dp(8))
        }
        return view
    }

    override func getView(_ position: Int, _ convertView: AView?, _ parent: AViewGroup) -> AView {
        readable(super.getView(position, convertView, parent))
    }

    override func getDropDownView(_ position: Int, _ convertView: AView?, _ parent: AViewGroup) -> AView {
        readable(super.getDropDownView(position, convertView, parent))
    }
}
