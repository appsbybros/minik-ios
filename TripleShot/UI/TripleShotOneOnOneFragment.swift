import Foundation

// Port of `ui/TripleShotOneOnOneFragment.kt` (Android 6c38131), part 1 of 2: lines 1-1794 (spec 15-one1).
//
// This file declares the class (DESIGN 2.9 / 2.10): every stored property of the whole Kotlin class, the nested
// types of lines 1-1794, the initialiser, every `override` of the whole Kotlin file, and the members of lines 1-1794
// (lifecycle wiring, the touch router, two-finger and press-and-hold gathers, pump fakes, shot escapes, defensive
// taps, the shot-quality meter, the shot-chance model, the seeded make/miss translation, the bot's fake/jump reads,
// the dribble-move detectors). Part 2 (`TripleShotOneOnOneFragment+Part2.swift`, lines 1795-3467) holds the ball-state
// handler, the sensor listener methods, the human release, the bot AI, the possession questions, the HUD, the end of
// the game, the rating helpers and the companion object (all constants, `newInstance`).
//
// The two XML layouts (res/layout and res/layout-land `fragment_triple_shot_one_on_one.xml`) are built in code by
// `TripleShotOneOnOneLayouts` at the end of this file, with the same ids, attributes and layout params; the variant
// follows the configuration orientation at inflation, like Android's `layout-land` qualifier.
//
// Dead code (spec 15 section 3.9) is not ported: beginTapShotFromCurrentPosition, handleQuickShotTouch,
// handleHeldBallTap, setQuickShotBasePull, applyQuickShotPull, handleTapCandidate, startQuickShot,
// quickShotStillValid, convertQuickShotToPumpFake, releaseQuickShot, enterShotAim, performPumpFake and
// handleJumpPadTouch have no production caller (quickShotActive is never set; the held-tap branch is unreachable).
// Their fields and the resets live code performs on them are kept. The DEBUG-only TRIPLE_INPUT log is not ported.

/**
 * V20 local 1v1 gameplay core.
 *
 * Current playable rules: drag to move (bodies cannot pass through one another); offense uses a live shot-quality
 * percentage; a pump fake commits the defender briefly; steals require geometric reach to the live ball; blocks are
 * physical ball-vs-hand collisions; inside/midrange baskets are 2, beyond the three-point line 3; first to 11 wins.
 */
final class TripleShotOneOnOneFragment: AFragment, TripleShotSensorController.Listener {

    /**
     * V20 keeps the high-level 1v1 flow explicit. The older booleans remain as rendering/input
     * details, but possession can no longer silently fall between unrelated callbacks.
     */
    enum Phase: String, KotlinEnum {
        case CHECK_BALL
        case LIVE_OFFENSE
        case SHOT_GATHER
        case BALL_IN_FLIGHT
        case REBOUND
        case DEAD_BALL
        case GAME_OVER
    }

    enum ControlMode: String, KotlinEnum {
        case SWIPE
        case ROTATE
    }

    // MARK: - Stored properties (all of the Kotlin class, L81-241 and L1694)

    let handler = AHandler(ALooper.getMainLooper())
    lazy var firebase = TripleShotFirebaseRepository()

    var courtView: TripleShotCourtView!
    var backgroundView: AImageView!
    var humanScoreText: ATextView!
    var botScoreText: ATextView!
    var possessionText: ATextView!
    var statusText: ATextView!
    var shotMeterCard: ACardView!
    var shotMeter: AProgressBar!
    var shotChanceText: ATextView!
    var controlsCard: ACardView!
    var shootButton: AButton!
    var fakeButton: AButton!
    var blockButton: AButton!
    var jumpButton: AButton!
    var resultOverlay: AView!
    var resultTitle: ATextView!
    var resultScore: ATextView!

    var questionCard: ACardView!
    var questionTitle: ATextView!
    var questionPrompt: ATextView!
    var questionFeedback: ATextView!
    var questionContinueButton: AButton!
    /// Kotlin `lateinit var questionButtons: List<MaterialButton>` (set once in onViewCreated, never checked).
    var questionButtons: [AButton] = []

    var sensor: TripleShotSensorController!
    var sensorRunning = false
    var controlMode = ControlMode.SWIPE
    var sensorMoveLastNanos: Int64 = 0
    var humanProfile: TripleShotCharacterProfile!
    var botProfile: TripleShotCharacterProfile!
    var botBrain: TripleShotBotOpponent!

    var humanScore = 0
    var botScore = 0
    var humanHasBall = true
    var aiming = false
    var shotInProgress = false
    var ended = false
    var moveTouchActive = false
    var lastTouchX: Float = 0
    var lastTouchY: Float = 0
    var botPossessionSerial: Int64 = 0
    var botShotSearchAttempts = 0
    var botConsecutiveMisses = 0
    // Carries the attack's chosen left/right finishing channel into the layup/dunk gather.
    // Without this, an unguarded bot converges on the exact same rim-side spot every possession.
    var botPreferredFinishSideSign: Float = 1
    var reboundActive = false
    var aimStartedAtNanos: Int64 = 0
    var peakPullBackDuringAim: Float = 0
    var lastPumpFakeNanos: Int64 = 0
    var shotSequence: Int64 = 0
    var shotEscapeUsed = false
    var shotMeterRunnable: ARunnable? = nil
    var shotMeterStartedAtNanos: Int64 = 0
    var currentShotChancePercent = 0
    var pendingHeldShotChancePercent = 0
    var lockedShotChancePercent = 0
    var heldFinish = TripleShotCourtView.OneOnOneDriveFinish.JUMPER

    // V20.8 quick-flow controls (dead in production: nothing sets quickShotActive; live code still resets them).
    var quickShotActive = false
    var quickShotGeneration: Int64 = 0
    var quickShotStartedAtNanos: Int64 = 0
    var quickShotBasePull: Float = 0
    var quickShotPullOffset: Float = 0
    var quickShotFineAim: Float = 0
    var quickShotLastTouchX: Float = 0
    var quickShotLastTouchY: Float = 0
    var quickFinish = TripleShotCourtView.OneOnOneDriveFinish.JUMPER
    var tapDownX: Float = 0
    var tapDownY: Float = 0
    var tapDownNanos: Int64 = 0
    var tapMoved = false
    var lastTapUpNanos: Int64 = 0
    var lastTapX: Float = 0
    var lastTapY: Float = 0
    // Pump fake is deliberately discoverable again: two quick taps while live-dribbling.
    // A single tap does nothing on offense, so it can never accidentally become a shot.
    var lastDribbleFakeTapNanos: Int64 = 0
    var recentMoveIntensity01: Float = 0
    var recentMoveAtNanos: Int64 = 0
    var recentMoveDx: Float = 0
    var recentMoveDy: Float = 0
    var lastMoveEventTimeMs: Int64 = 0

    var phase = Phase.CHECK_BALL
    var botAttackRunnable: ARunnable? = nil

    /// Kotlin `Set<QuestionCategory>` (insertion-ordered; passed to the question repository).
    var selectedCategories: KLinkedSet<QuestionCategory> = KLinkedSet([QuestionCategory.GENERAL_KNOWLEDGE])
    /// Kotlin `List<TripleShotQuestion>`: the repository's lazy 4096-entry adaptive list, or the empty list.
    var possessionQuestions: AdaptiveQuestionList = AdaptiveQuestionList.emptyList()
    var possessionQuestionIndex = 0
    var possessionQuestionRound: Int64 = 0
    var possessionQuestionActive = false
    var humanWrongOnCurrentQuestion = false
    var botWrongOnCurrentQuestion = false
    var humanAnsweredCurrentQuestion = false
    var botAnsweredCurrentQuestion = false
    var botCorrectOnCurrentQuestion = false
    var possessionQuestionWinnerHuman: Bool? = nil
    var checkTransitionActive = false
    var botQuestionRunnable: ARunnable? = nil
    var botQuestionShownAtElapsedMs: Int64 = 0
    var botQuestionHardDeadlineMs: Int64 = 0
    var botQuestionAttemptNumber = 0
    /// Kotlin `mutableSetOf<Int>()`: only add / clear / membership (`in`), never iterated (DESIGN 2.3).
    var botQuestionWrongAnswerIndices = Set<Int>()
    var pendingQuestionWinnerHuman: Bool? = nil
    var pendingQuestionNeedsAnother = false

    // A legal picked-up dribble is terminal for that possession: after the first tap the human
    // may aim, fake or shoot, but may not resume moving/dribbling.
    var humanDribblePickedUp = false
    var heldShotFineAim: Float = 0
    var heldShotPull: Float = 0.34
    var heldAimTouched = false
    var heldReleaseCommitted = false
    var pendingHeldSingleTap: ARunnable? = nil
    var lastHeldTapNanos: Int64 = 0
    var holdPoseGeneration: Int64 = 0

    // One continuous gesture can be both movement and shooting: while the finger is moving it is
    // a dribble swipe; when that SAME finger becomes stationary for a short beat, it gathers into
    // the shot meter. Releasing after the gather shoots.
    var pressToAimRunnable: ARunnable? = nil
    var pressTurnedIntoShotHold = false
    var suppressHeldReleaseOnNextUp = false

    // Two-finger offense: the first finger owns movement; while it is still down, a second finger may
    // press-and-hold to gather/aim and RELEASE that second finger to shoot.
    var movementPointerId = AMotionEvent.INVALID_POINTER_ID
    var shotHoldPointerId = AMotionEvent.INVALID_POINTER_ID
    var dualTouchShotActive = false

    // The defender learns the last few shot fakes. True = fake, false = real release.
    var recentHumanShotFakes: [Bool] = []
    var botEvadeCooldownUntilElapsedMs: Int64 = 0

    var moveGestureStartedAtNanos: Int64 = 0
    var lastHorizontalMoveSign = 0
    var horizontalDirectionChanges = 0
    var verticalGestureStartedAtNanos: Int64 = 0
    var lastVerticalMoveSign = 0
    var verticalDirectionChanges = 0
    var jumpTouchDownX: Float = 0

    var playerName = ""
    var humanCharacterId = TripleShotCharacterRoster.ID_WOMAN_DARK
    var botCharacterId = TripleShotCharacterRoster.ID_WOMAN_DARK
    var gameOrientation = TripleShotGameOrientation.PORTRAIT
    var courtId = TripleShotCourtCatalog.DEFAULT_ID
    var seed: Int64 = ASystem.currentTimeMillis()

    // MARK: - Construction

    /// `Fragment(R.layout.fragment_triple_shot_one_on_one)`: the default onCreateView inflates the layout, whose
    /// Swift builders (portrait and layout-land) are registered with ALayoutInflater on first use.
    override init() {
        _ = TripleShotOneOnOneFragment.layoutRegistration
        super.init(contentLayoutId: R.layout.fragment_triple_shot_one_on_one)
    }

    /// Registers the builder of R.layout.fragment_triple_shot_one_on_one (both resource variants) once.
    static let layoutRegistration: Void = {
        ALayoutInflater.register(R.layout.fragment_triple_shot_one_on_one) { inflater in
            TripleShotOneOnOneLayouts.inflate(inflater)
        }
    }()

    // MARK: - Lifecycle (L243-464)

    override func onCreate(_ savedInstanceState: ABundle?) {
        super.onCreate(savedInstanceState)

        TripleShotQuestionRepository.initialize(context: requireContext())

        let args = requireArguments()
        playerName = args.getString(Self.ARG_PLAYER_NAME) ?? ""
        humanCharacterId =
            args.getString(Self.ARG_HUMAN_CHARACTER_ID)
                ?? TripleShotCharacterRoster.ID_WOMAN_DARK
        botCharacterId =
            args.getString(Self.ARG_BOT_CHARACTER_ID)
                ?? TripleShotCharacterRoster.ID_WOMAN_DARK
        // `runCatching { valueOf(arg.orEmpty()) }.getOrDefault(PORTRAIT)`
        gameOrientation =
            TripleShotGameOrientation.named(args.getString(Self.ARG_GAME_ORIENTATION) ?? "")
                ?? TripleShotGameOrientation.PORTRAIT
        courtId = args.getString(Self.ARG_COURT_ID) ?? TripleShotCourtCatalog.DEFAULT_ID
        seed = args.getLong(Self.ARG_SEED, ASystem.currentTimeMillis())

        let categoryNames = args.getStringArrayList(Self.ARG_CATEGORIES) ?? []
        // `mapNotNull { runCatching { QuestionCategory.valueOf(name) }.getOrNull() }.toSet()`
        selectedCategories =
            KLinkedSet(categoryNames.compactMap { name in QuestionCategory.named(name) })
        possessionQuestions =
            selectedCategories.isEmpty
                ? AdaptiveQuestionList.emptyList()
                : TripleShotQuestionRepository.shuffled(
                    seed: seed ^ Self.QUESTION_SEED_SALT,
                    categories: selectedCategories
                )

        humanProfile =
            TripleShotCharacterRoster.find(id: humanCharacterId)
                ?? TripleShotCharacterRoster.womanDark
        botProfile =
            TripleShotCharacterRoster.find(id: botCharacterId)
                ?? TripleShotCharacterRoster.womanDark
    }

    override func onViewCreated(_ view: AView, _ savedInstanceState: ABundle?) {
        super.onViewCreated(view, savedInstanceState)
        applyGameplayInsets(root: view, window: requireActivity().window)

        courtView = view.findViewById(R.id.oneOnOneCourtView)
        backgroundView = view.findViewById(R.id.oneOnOneBackground)

        let selectedCourt = TripleShotCourtCatalog.find(id: courtId)
        backgroundView.setImageResource(
            selectedCourt.resolveBackgroundResId(context: requireContext(), orientation: gameOrientation)
        )
        courtView.setCourtStyle(style: selectedCourt)

        humanScoreText = view.findViewById(R.id.oneOnOneHumanScore)
        botScoreText = view.findViewById(R.id.oneOnOneBotScore)
        possessionText = view.findViewById(R.id.oneOnOnePossession)
        statusText = view.findViewById(R.id.oneOnOneStatus)
        shotMeterCard = view.findViewById(R.id.oneOnOneShotMeterCard)
        shotMeter = view.findViewById(R.id.oneOnOneShotMeter)
        shotChanceText = view.findViewById(R.id.oneOnOneShotChanceText)
        controlsCard = view.findViewById(R.id.oneOnOneControls)
        shootButton = view.findViewById(R.id.oneOnOneShootButton)
        fakeButton = view.findViewById(R.id.oneOnOneFakeButton)
        blockButton = view.findViewById(R.id.oneOnOneBlockButton)
        jumpButton = view.findViewById(R.id.oneOnOneJumpButton)
        resultOverlay = view.findViewById(R.id.oneOnOneResultOverlay)
        resultTitle = view.findViewById(R.id.oneOnOneResultTitle)
        resultScore = view.findViewById(R.id.oneOnOneResultScore)
        questionCard = view.findViewById(R.id.oneOnOneQuestionCard)
        questionTitle = view.findViewById(R.id.oneOnOneQuestionTitle)
        questionPrompt = view.findViewById(R.id.oneOnOneQuestionPrompt)
        questionFeedback = view.findViewById(R.id.oneOnOneQuestionFeedback)
        questionContinueButton = view.findViewById(R.id.oneOnOneQuestionContinue)
        questionContinueButton.setOnClickListener { [weak self] _ in self?.continueAfterPossessionQuestion() }
        let questionExitButton: AButton = view.findViewById(R.id.oneOnOneQuestionExit)!
        questionExitButton.setOnClickListener { [weak self] _ in self?.leaveToHome() }
        let answer1: AButton = view.findViewById(R.id.oneOnOneQuestionAnswer1)!
        let answer2: AButton = view.findViewById(R.id.oneOnOneQuestionAnswer2)!
        let answer3: AButton = view.findViewById(R.id.oneOnOneQuestionAnswer3)!
        let answer4: AButton = view.findViewById(R.id.oneOnOneQuestionAnswer4)!
        questionButtons = [answer1, answer2, answer3, answer4]
        for (index, button) in questionButtons.enumerated() {
            button.setOnClickListener { [weak self] _ in self?.submitHumanPossessionAnswer(index: index) }
        }

        requireActivity().onBackPressedDispatcher.addCallback(
            viewLifecycleOwner,
            AOnBackPressedCallback(true) { [weak self] _ in self?.leaveToHome() }
        )
        // iOS has no system Back (DESIGN 2.8 / 12.3, spec 15 section 10.2). The iOS-only exit control of the layout
        // runs the activity's Back dispatch, i.e. the callback above: leaveToHome() at once, without confirmation,
        // exactly what Android's Back key / edge swipe does on this screen.
        let iosExitControl: AView? = view.findViewById(TripleShotOneOnOneLayouts.IOS_EXIT_CONTROL_ID)
        iosExitControl?.setOnClickListener { [weak self] _ in self?.activity?.onBackPressed() }

        let syncBackground: () -> Void = { [weak self] in
            guard let self = self else { return }
            if self.courtView != nil && self.backgroundView != nil {
                self.courtView.applyBackgroundTransformTo(imageView: self.backgroundView)
            }
        }
        courtView.addOnLayoutChangeListener(AOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ in syncBackground() })
        view.post { [weak self] in
            guard let self = self else { return }
            syncBackground()
            let boundary = self.controlsCard.y - self.dp(value: 8)
            if boundary > 0 { self.courtView.setGameplayBottomBoundary(boundaryY: boundary) }
        }

        // Alpha guardrail: if a picker somehow supplies a character whose gameplay pack is not
        // ready yet, the visual catalog already falls back safely.
        courtView.setLocalCharacters(
            humanCharacterId: humanProfile.id,
            botCharacterId: botProfile.id
        )
        courtView.setOneOnOneEnabled(
            enabled: true,
            seed: seed,
            botLabel: botProfile.displayName,
            botBlockRating: effectiveBlock(profile: botProfile),
            humanBlockRating: effectiveBlock(profile: humanProfile),
            botStealRating: botProfile.ratings.stealing,
            humanStealRating: humanProfile.ratings.stealing,
            botStrengthRating: botProfile.ratings.strength,
            humanStrengthRating: humanProfile.ratings.strength,
            botSpeedRating: botProfile.ratings.speed,
            humanSpeedRating: humanProfile.ratings.speed,
            botHeightRating: botProfile.ratings.height,
            humanHeightRating: humanProfile.ratings.height,
            botBallHandlingRating: botProfile.ratings.ballHandling,
            humanBallHandlingRating: humanProfile.ratings.ballHandling,
            botDefenseRating: botProfile.ratings.defense,
            humanDefenseRating: humanProfile.ratings.defense,
            botAgilityRating: botProfile.ratings.agility,
            humanAgilityRating: humanProfile.ratings.agility,
            botOffenseRating: botProfile.ratings.offense,
            humanOffenseRating: humanProfile.ratings.offense,
            botWeightRating: botProfile.ratings.weight,
            humanWeightRating: humanProfile.ratings.weight,
            botJumpRating: botProfile.ratings.jumping,
            humanJumpRating: humanProfile.ratings.jumping
        )

        courtView.setOneOnOneAutomaticBallStateListener { [weak self] state in
            guard let self = self else { return }
            self.handler.post { [weak self] in
                guard let self = self else { return }
                if !self.isAdded || self.ended { return }
                self.handleAutomaticBallState(state: state)
            }
        }

        // `TripleShotBotOpponent(...).also { it.start() }`
        let brain = TripleShotBotOpponent(
            displayName: botProfile.displayName,
            seed: seed ^ Self.BOT_BRAIN_SEED_SALT,
            characterProfile: botProfile,
            onStateChanged: { _ in }
        )
        brain.start()
        botBrain = brain

        sensor = TripleShotSensorController(context: requireContext(), listener: self)
        // Control selection belongs in the future Player/Settings surface, never inside a live
        // basketball possession. Existing preferences are still respected; new installs default
        // quietly to SWIPE until that settings screen is added.
        controlMode = loadControlMode() ?? ControlMode.SWIPE
        sensor.prepareForMovement()

        courtView.setOnTouchListener { [weak self] _, event in self?.handleCourtTouch(event: event) ?? true }

        // Legacy action buttons remain only as compatibility ids. V20.4 is gesture-driven.
        shootButton.setOnClickListener { _ in }
        fakeButton.setOnClickListener { _ in }
        blockButton.setOnClickListener { _ in }
        jumpButton.setOnClickListener { _ in }

        courtView.setOneOnOneBlockEventListener { [weak self] humanBlocked in
            guard let self = self else { return }
            self.handler.post { [weak self] in
                guard let self = self else { return }
                if !self.isAdded || self.ended { return }
                if humanBlocked {
                    self.statusText.setText(res: R.string.minik_swish_one_on_one_block_success)
                    _ = self.courtView.performHapticFeedback(AHapticFeedbackConstants.LONG_PRESS)
                }
            }
        }
        let homeButton: AButton = view.findViewById(R.id.oneOnOneHomeButton)!
        homeButton.setOnClickListener { [weak self] _ in self?.leaveToHome() }
        let againButton: AButton = view.findViewById(R.id.oneOnOneAgainButton)!
        againButton.setOnClickListener { [weak self] _ in self?.restartMatch() }

        courtView.whenWorldReady { [weak self] in
            guard let self = self else { return }
            if self.isAdded && !self.ended {
                BasketballSoundscape.effect(context: self.requireContext(), kind: BasketballSoundscape.Effect.WHISTLE)
                self.takeHumanPossession(showMessage: false)
            }
        }
        updateHud()
    }

    override func onResume() {
        super.onResume()
        syncSensorForControlMode()
    }

    override func onPause() {
        stopSensorIfRunning()
        super.onPause()
    }

    override func onDestroyView() {
        stopShotMeterUpdates(hide: true)
        quickShotGeneration += 1
        quickShotActive = false
        stopBotAttack()
        if let r = botQuestionRunnable { handler.removeCallbacks(r) }
        botQuestionRunnable = nil
        if let r = pendingHeldSingleTap { handler.removeCallbacks(r) }
        pendingHeldSingleTap = nil
        resetTouchPointerState()
        handler.removeCallbacksAndMessages(nil)
        if botBrain != nil { botBrain.stop() }
        if courtView != nil {
            courtView.setOnTouchListener(nil)
            courtView.setOneOnOneAutomaticBallStateListener(listener: nil)
            courtView.setOneOnOneBlockEventListener(listener: nil)
            courtView.setOneOnOneEnabled(enabled: false)
        }
        super.onDestroyView()
    }

    // MARK: - Touch router (L466-747)

    /// The court's OnTouchListener (court view coordinates, px). Always consumes the event.
    func handleCourtTouch(event: AMotionEvent) -> Bool {
        // L467-468: the BuildConfig.DEBUG "TRIPLE_INPUT" log is debug-only (DESIGN 3).
        if ended { return true }
        if possessionQuestionActive || checkTransitionActive { return true }

        /*
         * Two-finger offense is the clean no-ambiguity path:
         *   finger A = movement/dribble
         *   finger B down = gather/aim while the run momentum is still fresh
         *   finger B up = release
         */
        if dualTouchShotActive {
            return handleDualTouchShotGesture(event: event)
        }

        if event.actionMasked == AMotionEvent.ACTION_POINTER_DOWN {
            let actionPointerId = event.getPointerId(event.actionIndex)
            if humanHasBall && !reboundActive && !shotInProgress && !aiming &&
                movementPointerId != AMotionEvent.INVALID_POINTER_ID &&
                actionPointerId != movementPointerId {
                beginDualTouchShotHold(pointerId: actionPointerId)
            } else if humanHasBall && humanDribblePickedUp && aiming && !shotInProgress {
                suppressHeldReleaseOnNextUp = true
                performHeldPumpFake()
            } else {
                performContextTapAction()
            }
            return true
        }

        if shotInProgress && humanHasBall { return true }

        if quickShotActive {
            // handleQuickShotTouch(event): dead (quickShotActive is never set, spec 15 section 3.9).
            return true
        }

        if humanDribblePickedUp && aiming {
            handlePickedUpAimTouch(event: event)
            return true
        }

        if aiming { return true }

        switch event.actionMasked {
        case AMotionEvent.ACTION_DOWN:
            movementPointerId = event.getPointerId(event.actionIndex)
            shotHoldPointerId = AMotionEvent.INVALID_POINTER_ID
            dualTouchShotActive = false

            let foundIndex = event.findPointerIndex(movementPointerId)
            let index = foundIndex >= 0 ? foundIndex : 0
            let x = event.getX(index)
            let y = event.getY(index)
            tapDownX = x
            tapDownY = y
            tapDownNanos = ASystem.nanoTime()
            tapMoved = false
            pressTurnedIntoShotHold = false
            suppressHeldReleaseOnNextUp = false
            moveTouchActive = true
            lastTouchX = x
            lastTouchY = y
            lastMoveEventTimeMs = event.eventTime
            let now = tapDownNanos
            verticalGestureStartedAtNanos = now
            lastVerticalMoveSign = 0
            verticalDirectionChanges = 0
            if now - moveGestureStartedAtNanos > Self.CROSSOVER_GESTURE_WINDOW_MS * 1_000_000 {
                moveGestureStartedAtNanos = now
                lastHorizontalMoveSign = 0
                dribbleGesture.reset()
                horizontalDirectionChanges = 0
            }

            // One-finger fallback: stop that same finger briefly and it becomes a shot hold.
            // Continuous movement keeps resetting this timer, so a real swipe cannot fire it.
            schedulePressToAimShot()
            return true

        case AMotionEvent.ACTION_MOVE:
            if !moveTouchActive || movementPointerId == AMotionEvent.INVALID_POINTER_ID { return true }
            let index = event.findPointerIndex(movementPointerId)
            if index < 0 { return true }
            let x = event.getX(index)
            let y = event.getY(index)
            let rawDx = x - lastTouchX
            let rawDy = y - lastTouchY
            lastTouchX = x
            lastTouchY = y

            let totalFromDownX = x - tapDownX
            let totalFromDownY = y - tapDownY
            let totalFromDownDistance =
                ksqrt(totalFromDownX * totalFromDownX + totalFromDownY * totalFromDownY)
            if totalFromDownDistance > dp(value: Self.TAP_MOVE_SLOP_DP) { tapMoved = true }

            if controlMode == ControlMode.ROTATE {
                // In ROTATE mode the screen finger is action-only. The actual movement comes
                // from device tilt, but a moving finger still postpones the one-finger gather.
                schedulePressToAimShot()
                return true
            }

            let eventDtMs =
                (event.eventTime - lastMoveEventTimeMs)
                    .coerceIn(Self.MOVE_MIN_EVENT_DT_MS, Self.MOVE_MAX_EVENT_DT_MS)
            lastMoveEventTimeMs = event.eventTime

            let inputDx = rawDx * Self.MOVE_INPUT_SCALE
            let inputDy = rawDy * Self.MOVE_INPUT_SCALE
            let inputLen = ksqrt(inputDx * inputDx + inputDy * inputDy)
            let maxSpeedDpPerSec =
                Self.MOVE_BASE_SPEED_DP_PER_SEC +
                    humanProfile.ratings.speed.toFloat() * Self.MOVE_SPEED_RATING_DP_PER_SEC
            let maxStepPx =
                dp(value: maxSpeedDpPerSec * (eventDtMs.toFloat() / Float(1000))).coerceAtLeast(dp(value: 1.4))
            let movementScale: Float =
                (inputLen <= maxStepPx || inputLen <= Float(0.001)) ? 1 : maxStepPx / inputLen
            let moveDx = inputDx * movementScale
            let moveDy = inputDy * movementScale
            let actualLen = ksqrt(moveDx * moveDx + moveDy * moveDy)

            recentMoveIntensity01 =
                (actualLen / maxStepPx.coerceAtLeast(1)).coerceIn(0, 1)
            recentMoveAtNanos = ASystem.nanoTime()
            if actualLen > dp(value: 0.4) {
                recentMoveDx = moveDx
                recentMoveDy = moveDy
            }

            _ = courtView.moveOneOnOneHumanByTouch(dx: moveDx, dy: moveDy)
            if humanHasBall && !reboundActive {
                let spin = circularGesture.move(dx: rawDx, dy: rawDy, now: ASystemClock.elapsedRealtime())
                if spin != 0 {
                    _ = courtView.oneOnOneHumanSpin(directionSign: spin.toFloat())
                    statusText.setText(res: R.string.minik_swish_one_on_one_spin)
                } else {
                    detectCrossoverGesture(rawDx: rawDx)
                }
                detectHesitationGesture(rawDy: rawDy)
            }

            schedulePressToAimShot()
            return true

        case AMotionEvent.ACTION_POINTER_UP:
            let pointerId = event.getPointerId(event.actionIndex)
            if pointerId == movementPointerId {
                movementPointerId = AMotionEvent.INVALID_POINTER_ID
                moveTouchActive = false
                cancelPressToAimShot()
            }
            return true

        case AMotionEvent.ACTION_UP, AMotionEvent.ACTION_CANCEL:
            cancelPressToAimShot()
            let wasTap = !tapMoved && event.actionMasked == AMotionEvent.ACTION_UP
            movementPointerId = AMotionEvent.INVALID_POINTER_ID
            shotHoldPointerId = AMotionEvent.INVALID_POINTER_ID
            dualTouchShotActive = false
            moveTouchActive = false
            if wasTap {
                if humanHasBall && !reboundActive && !shotInProgress && !aiming {
                    handleLiveDribbleTapForPumpFake()
                } else if !humanHasBall {
                    performContextTapAction()
                }
            }
            return true

        default:
            break
        }

        return true
    }

    func beginDualTouchShotHold(pointerId: Int) {
        if pointerId == AMotionEvent.INVALID_POINTER_ID || ended || !humanHasBall || reboundActive ||
            shotInProgress || aiming || humanDribblePickedUp { return }

        cancelPressToAimShot()
        shotHoldPointerId = pointerId
        dualTouchShotActive = true

        // recentMoveDx/recentMoveDy were updated by the movement finger immediately before this
        // press. pickUpHumanDribble() therefore converts the live run into the correct moving
        // jumper / layup / dunk candidate instead of requiring the player to stop first.
        pickUpHumanDribble()
        if humanDribblePickedUp && aiming {
            pressTurnedIntoShotHold = true
            moveTouchActive = false
            refreshShotMeterNow()
        } else {
            shotHoldPointerId = AMotionEvent.INVALID_POINTER_ID
            dualTouchShotActive = false
        }
    }

    func handleDualTouchShotGesture(event: AMotionEvent) -> Bool {
        switch event.actionMasked {
        case AMotionEvent.ACTION_MOVE:
            // The shot meter advances on its own. Movement-pointer velocity was captured at the
            // gather; continuing to drag now must not make the shooter skate across the court.
            return true

        case AMotionEvent.ACTION_POINTER_UP, AMotionEvent.ACTION_UP:
            let pointerId = event.getPointerId(event.actionIndex)
            if pointerId == movementPointerId {
                movementPointerId = AMotionEvent.INVALID_POINTER_ID
            }
            if pointerId == shotHoldPointerId {
                shotHoldPointerId = AMotionEvent.INVALID_POINTER_ID
                dualTouchShotActive = false
                pressTurnedIntoShotHold = false
                if !heldReleaseCommitted && humanDribblePickedUp && aiming && !shotInProgress {
                    beginHeldShotRelease(lockedChance: refreshShotMeterNow())
                }
            }
            return true

        case AMotionEvent.ACTION_CANCEL:
            movementPointerId = AMotionEvent.INVALID_POINTER_ID
            shotHoldPointerId = AMotionEvent.INVALID_POINTER_ID
            dualTouchShotActive = false
            moveTouchActive = false
            // ACTION_CANCEL should never leave a gathered possession frozen. Release using the
            // current quality rather than silently swallowing the possession.
            if !heldReleaseCommitted && humanDribblePickedUp && aiming && !shotInProgress {
                beginHeldShotRelease(lockedChance: refreshShotMeterNow())
            }
            return true

        default:
            break
        }
        return true
    }

    func schedulePressToAimShot() {
        cancelPressToAimShot()
        if !humanHasBall || reboundActive || shotInProgress || aiming ||
            possessionQuestionActive || checkTransitionActive { return }

        let action = ARunnable { [weak self] in
            guard let self = self else { return }
            self.pressToAimRunnable = nil
            if !self.isAdded || self.ended || !self.moveTouchActive || !self.humanHasBall ||
                self.reboundActive || self.shotInProgress || self.aiming { return }

            self.pickUpHumanDribble()
            if self.humanDribblePickedUp && self.aiming {
                self.pressTurnedIntoShotHold = true
                self.moveTouchActive = false
            }
        }
        pressToAimRunnable = action
        handler.postDelayed(action, Self.PRESS_TO_AIM_START_MS)
    }

    func cancelPressToAimShot() {
        if let r = pressToAimRunnable { handler.removeCallbacks(r) }
        pressToAimRunnable = nil
    }

    func resetTouchPointerState() {
        cancelPressToAimShot()
        movementPointerId = AMotionEvent.INVALID_POINTER_ID
        shotHoldPointerId = AMotionEvent.INVALID_POINTER_ID
        dualTouchShotActive = false
        moveTouchActive = false
        pressTurnedIntoShotHold = false
        suppressHeldReleaseOnNextUp = false
        lastDribbleFakeTapNanos = 0
    }

    // MARK: - Live-dribble pump fake (L749-810)

    /**
     * Easy-to-remember pump fake: DOUBLE TAP while live-dribbling.
     *
     * Shooting itself remains press/hold/release. A single offensive tap therefore has no
     * basketball side effect; only the second tap inside the short window commits the fake.
     */
    func handleLiveDribbleTapForPumpFake() {
        if ended || !humanHasBall || reboundActive || shotInProgress || aiming { return }

        let now = ASystem.nanoTime()
        let gapMs: Int64 =
            lastDribbleFakeTapNanos == 0 ? Int64.max
            : (now - lastDribbleFakeTapNanos) / 1_000_000

        if gapMs <= Self.HELD_DOUBLE_TAP_MAX_GAP_MS {
            lastDribbleFakeTapNanos = 0
            performLiveDribblePumpFake()
        } else {
            lastDribbleFakeTapNanos = now
        }
    }

    func performLiveDribblePumpFake() {
        if ended || !humanHasBall || reboundActive || shotInProgress || aiming { return }
        if !courtView.prepareOneOnOneHumanShot(showArc: false) { return }

        humanDribblePickedUp = true
        aiming = true
        phase = Phase.SHOT_GATHER
        heldReleaseCommitted = false
        heldFinish = TripleShotCourtView.OneOnOneDriveFinish.JUMPER
        pendingHeldShotChancePercent = 0
        lockedShotChancePercent = 0

        let botBites = shouldBotBiteOnCurrentGather()
        recordHumanShotDecision(fake: true)
        courtView.setOneOnOneBotContestAllowed(allowed: botBites)
        if botBites { _ = courtView.oneOnOneBotBiteOnPumpFake() }
        courtView.setOneOnOneHumanHeldMotion(high: nil)
        courtView.setPullBack(normalized: Self.HOLD_FAKE_SET_PULL)
        statusText.setText(res: R.string.minik_swish_one_on_one_fake_rising)

        handler.postDelayed({ [weak self] in
            guard let self = self else { return }
            if !self.isAdded || self.ended || !self.humanHasBall || self.shotInProgress { return }

            self.courtView.oneOnOnePumpFakeCycle()
            self.courtView.cancelOneOnOneHumanAim(pumpFake: true)
            self.courtView.setOneOnOneBotContestAllowed(allowed: false)
            self.courtView.setOneOnOneHumanHeldMotion(high: nil)

            self.humanDribblePickedUp = false
            self.aiming = false
            self.heldReleaseCommitted = false
            self.heldFinish = TripleShotCourtView.OneOnOneDriveFinish.JUMPER
            self.phase = Phase.LIVE_OFFENSE
            self.statusText.setText(res: R.string.minik_swish_one_on_one_fake_success)
            self.sensor.prepareForMovement()
            self.updateControls()
        }, Self.HOLD_FAKE_UP_MS)
    }

    // L812-818 beginTapShotFromCurrentPosition (no caller) and L825-830 handleQuickShotTouch (dead): not ported.

    // MARK: - Picked-up aim touches (L832-900)

    /**
     * After the dribble is picked up there is no hidden arc to learn. A normal drag does nothing;
     * one clear escape swipe can become a side-step or fadeaway.
     */
    func handlePickedUpAimTouch(event: AMotionEvent) {
        switch event.actionMasked {
        case AMotionEvent.ACTION_DOWN:
            tapDownX = event.x
            tapDownY = event.y
            quickShotLastTouchX = event.x
            quickShotLastTouchY = event.y

        case AMotionEvent.ACTION_MOVE:
            quickShotLastTouchX = event.x
            quickShotLastTouchY = event.y
            if shotEscapeUsed || heldFinish != TripleShotCourtView.OneOnOneDriveFinish.JUMPER { return }

            let totalDx = event.x - tapDownX
            let totalDy = event.y - tapDownY
            let sideReady = abs(totalDx) >= dp(value: Self.SHOT_ESCAPE_DRAG_DP)
            let fadeReady = totalDy >= dp(value: Self.SHOT_FADE_DRAG_DP)
            if !sideReady && !fadeReady { return }

            let move: TripleShotCourtView.OneOnOneShotEscape
            if sideReady && abs(totalDx) >= abs(totalDy) * Float(0.72) {
                if totalDx < 0 {
                    move = TripleShotCourtView.OneOnOneShotEscape.SIDE_LEFT
                } else {
                    move = TripleShotCourtView.OneOnOneShotEscape.SIDE_RIGHT
                }
            } else {
                move = TripleShotCourtView.OneOnOneShotEscape.FADE_AWAY
            }

            if courtView.oneOnOneHumanShotEscape(move: move) {
                shotEscapeUsed = true
                heldAimTouched = true
                holdPoseGeneration += 1
                courtView.setOneOnOneHumanHeldMotion(high: nil)
                statusText.setText(
                    res: move == TripleShotCourtView.OneOnOneShotEscape.FADE_AWAY
                        ? R.string.minik_swish_one_on_one_fadeaway
                        : R.string.minik_swish_one_on_one_side_step
                )
                refreshShotMeterNow()
            }

        case AMotionEvent.ACTION_UP:
            pressTurnedIntoShotHold = false
            if suppressHeldReleaseOnNextUp {
                suppressHeldReleaseOnNextUp = false
                return
            }
            if !heldReleaseCommitted && humanDribblePickedUp && aiming && !shotInProgress {
                beginHeldShotRelease(lockedChance: refreshShotMeterNow())
            }

        case AMotionEvent.ACTION_CANCEL:
            pressTurnedIntoShotHold = false
            suppressHeldReleaseOnNextUp = false

        default:
            break
        }
    }

    // MARK: - Gather (L902-967)

    /**
     * First offensive tap gathers the live dribble. The shot itself is percentage-driven in 1v1:
     * spacing, movement, fakes and the two characters' ratings build the visible chance.
     */
    func pickUpHumanDribble() {
        if ended || !humanHasBall || reboundActive || shotInProgress || aiming ||
            humanDribblePickedUp { return }

        let movement01 = currentRecentMovementIntensity()
        heldFinish = courtView.chooseOneOnOneHumanDriveFinish(
            movementIntensity01: movement01,
            movementDx: recentMoveDx,
            movementDy: recentMoveDy,
            dunkAbility: effectiveDunkAbility(profile: humanProfile)
        )

        if heldFinish == TripleShotCourtView.OneOnOneDriveFinish.JUMPER &&
            movement01 >= Self.MOVING_SHOT_MIN_INTENSITY {
            _ = courtView.oneOnOneHumanMovingShotJump(
                directionX: recentMoveDx,
                directionY: recentMoveDy,
                intensity01: movement01
            )
        }
        if !courtView.beginOneOnOneHumanDriveFinish(finish: heldFinish) {
            heldFinish = TripleShotCourtView.OneOnOneDriveFinish.JUMPER
        }
        if !courtView.prepareOneOnOneHumanShot(showArc: false) { return }

        humanDribblePickedUp = true
        aiming = true
        phase = Phase.SHOT_GATHER
        heldShotFineAim = 0
        heldShotPull = Self.HOLD_VISUAL_LOW_PULL
        quickShotLastTouchX = lastTouchX
        quickShotLastTouchY = lastTouchY
        heldAimTouched = false
        heldReleaseCommitted = false
        shotEscapeUsed = false
        pendingHeldShotChancePercent = 0
        lockedShotChancePercent = 0
        lastHeldTapNanos = 0
        if let r = pendingHeldSingleTap { handler.removeCallbacks(r) }
        pendingHeldSingleTap = nil

        courtView.setFineAim(normalized: 0)
        courtView.setPullBack(normalized: heldShotPull)
        courtView.setOneOnOneBotContestAllowed(allowed: false)
        // During a real hold the LOW -> MID -> SET body sequence follows hold progress directly.
        // Do not pin the body to the dribble/LOW fallback while the percentage meter is moving.
        courtView.setOneOnOneHumanHeldMotion(high: nil)
        startShotMeter()
        let gatherText: AStringRes
        switch heldFinish {
        case .JUMPER: gatherText = R.string.minik_swish_one_on_one_gathered
        case .LAYUP: gatherText = R.string.minik_swish_one_on_one_layup
        case .DUNK: gatherText = R.string.minik_swish_one_on_one_dunk
        }
        statusText.setText(res: gatherText)
        updateControls()
    }

    // L970-998 handleHeldBallTap: unreachable in production (spec 15 section 3.9), not ported.

    // MARK: - Held pump fake and release (L1000-1070)

    func performHeldPumpFake() {
        if !humanDribblePickedUp || !aiming || shotInProgress { return }
        let botBites = shouldBotBiteOnCurrentGather()
        recordHumanShotDecision(fake: true)
        holdPoseGeneration += 1
        heldAimTouched = true
        pendingHeldShotChancePercent = 0

        courtView.setOneOnOneBotContestAllowed(allowed: botBites)
        if botBites { _ = courtView.oneOnOneBotBiteOnPumpFake() }
        courtView.setOneOnOneHumanHeldMotion(high: nil)
        courtView.setPullBack(normalized: Self.HOLD_FAKE_SET_PULL)
        statusText.setText(res: R.string.minik_swish_one_on_one_fake_rising)

        handler.postDelayed({ [weak self] in
            guard let self = self else { return }
            if !self.isAdded || self.ended || !self.humanDribblePickedUp || !self.aiming || self.shotInProgress { return }
            self.courtView.oneOnOnePumpFakeCycle()
            self.heldShotPull = Self.HOLD_VISUAL_LOW_PULL
            self.shotMeterStartedAtNanos = ASystem.nanoTime()
            self.courtView.setPullBack(normalized: self.heldShotPull)
            self.courtView.setOneOnOneHumanHeldMotion(high: nil)
            self.courtView.setOneOnOneBotContestAllowed(allowed: false)
            self.statusText.setText(res: R.string.minik_swish_one_on_one_fake_success_hold)
            self.heldAimTouched = false
            self.refreshShotMeterNow()
        }, Self.HOLD_FAKE_UP_MS)
    }

    func beginHeldShotRelease(lockedChance: Int) {
        if !humanDribblePickedUp || !aiming || shotInProgress || heldReleaseCommitted { return }
        heldReleaseCommitted = true
        lockedShotChancePercent = lockedChance.coerceIn(Self.MIN_SHOT_CHANCE_PERCENT, Self.MAX_SHOT_CHANCE_PERCENT)
        stopShotMeterUpdates(hide: false)
        showLockedShotChance(chancePercent: lockedShotChancePercent)
        holdPoseGeneration += 1
        courtView.setOneOnOneHumanHeldMotion(high: nil)
        courtView.setOneOnOneBotContestAllowed(allowed: shouldBotJumpOnRealShot())
        // A stationary jumper stays grounded when open, but if the defender is right on the
        // shooter the release becomes a real vertical jump-shot. Starting the jump here gives
        // the 290ms gather time to reach the air before the ball actually leaves the hand.
        if heldFinish == TripleShotCourtView.OneOnOneDriveFinish.JUMPER {
            _ = courtView.beginOneOnOneHumanContestedJumperIfNeeded()
        }
        courtView.setPullBack(normalized: kmax(heldShotPull, Self.HOLD_RELEASE_MID_PULL))

        handler.postDelayed({ [weak self] in
            guard let self = self else { return }
            if !self.isAdded || self.ended || !self.humanDribblePickedUp || !self.aiming || self.shotInProgress { return }
            self.heldShotPull = kmax(self.heldShotPull, Self.HOLD_RELEASE_SET_PULL)
            self.courtView.setPullBack(normalized: self.heldShotPull)
        }, Self.HOLD_RELEASE_SET_AT_MS)

        handler.postDelayed({ [weak self] in
            guard let self = self else { return }
            if !self.isAdded || self.ended || !self.humanDribblePickedUp || !self.aiming || self.shotInProgress { return }
            self.recordHumanShotDecision(fake: false)
            let skill = ShotSkill(
                aimError: 0,
                powerError: 0,
                arcError: 0,
                rawPeakGyro: 0,
                rawReleasePitchDeg: 0
            )
            self.releaseHumanShot(
                skill: skill,
                pullBack01: self.heldShotPull.coerceIn(0.22, 1.12),
                releaseMs: Self.HOLD_RELEASE_TOTAL_MS,
                movingEscape: self.shotEscapeUsed,
                shotChancePercent: self.lockedShotChancePercent,
                finish: self.heldFinish
            )
        }, Self.HOLD_RELEASE_TOTAL_MS)
    }

    // MARK: - Shot meter (L1072-1158)

    func startShotMeter() {
        stopShotMeterUpdates(hide: false)
        shotMeterStartedAtNanos = ASystem.nanoTime()
        shotMeterCard.visibility = AView.VISIBLE
        refreshShotMeterNow()

        // `lateinit var tick: Runnable; tick = Runnable { ...; handler.postDelayed(tick, ...) }`
        let tick = ARunnable(withSelf: { [weak self] tick in
            guard let self = self else { return }
            if !self.isAdded || self.ended || !self.aiming || self.shotInProgress || !self.humanHasBall ||
                self.heldReleaseCommitted {
                if self.shotMeterRunnable === tick { self.shotMeterRunnable = nil }
                return
            }
            self.refreshShotMeterNow()
            self.handler.postDelayed(tick, Self.SHOT_METER_TICK_MS)
        })
        shotMeterRunnable = tick
        handler.postDelayed(tick, Self.SHOT_METER_TICK_MS)
    }

    func stopShotMeterUpdates(hide: Bool) {
        if let r = shotMeterRunnable { handler.removeCallbacks(r) }
        shotMeterRunnable = nil
        if hide && shotMeterCard != nil { shotMeterCard.visibility = AView.GONE }
    }

    func hideShotMeter() {
        stopShotMeterUpdates(hide: true)
        shotMeterStartedAtNanos = 0
        currentShotChancePercent = 0
        pendingHeldShotChancePercent = 0
        lockedShotChancePercent = 0
    }

    func showLockedShotChance(chancePercent: Int) {
        if shotMeterCard == nil { return }
        shotMeterCard.visibility = AView.VISIBLE
        shotMeter.progress = chancePercent.coerceIn(0, Self.MAX_SHOT_CHANCE_PERCENT)
        shotChanceText.text = getString(
            R.string.minik_swish_one_on_one_shot_quality_locked,
            chancePercent
        )
    }

    @discardableResult
    func refreshShotMeterNow() -> Int {
        if shotMeterCard == nil || !aiming || !humanHasBall { return currentShotChancePercent }
        courtView.oneOnOneAdvanceBotDefenseDuringGather()

        /*
         * The percentage bar and Maya's body must tell the same story. LOW -> MID -> SET is driven
         * by how long the gather has been held, while the NUMBER can still rise/fall with spacing
         * and defense.
         */
        let elapsedMs: Int64 =
            shotMeterStartedAtNanos == 0 ? 0
            : ((ASystem.nanoTime() - shotMeterStartedAtNanos) / 1_000_000).coerceAtLeast(0)
        let poseSettleMs: Int64 =
            heldFinish == TripleShotCourtView.OneOnOneDriveFinish.JUMPER
                ? Self.SHOT_METER_POSE_TO_SET_MS
                : Self.SHOT_METER_FINISH_POSE_TO_SET_MS
        let pose01 = (elapsedMs.toFloat() / poseSettleMs.toFloat()).coerceIn(0, 1)
        let posePull: Float
        if pose01 < Float(0.24) {
            posePull = Self.HOLD_VISUAL_LOW_PULL
        } else if pose01 < Float(0.72) {
            let midSpan = Self.HOLD_VISUAL_MID_PULL_END - Self.HOLD_VISUAL_MID_PULL_START
            posePull = Self.HOLD_VISUAL_MID_PULL_START + midSpan * ((pose01 - Float(0.24)) / Float(0.48))
        } else {
            let setSpan = Self.HOLD_VISUAL_SET_PULL_END - Self.HOLD_VISUAL_SET_PULL_START
            posePull = Self.HOLD_VISUAL_SET_PULL_START + setSpan * ((pose01 - Float(0.72)) / Float(0.28))
        }
        heldShotPull = posePull.coerceIn(0.02, 0.82)
        courtView.setOneOnOneHumanHeldMotion(high: nil)
        courtView.setPullBack(normalized: heldShotPull)

        let chance = calculateHumanShotChance()
        currentShotChancePercent = chance
        shotMeterCard.visibility = AView.VISIBLE
        shotMeter.progress = chance
        shotChanceText.text = getString(R.string.minik_swish_one_on_one_shot_quality, chance)
        return chance
    }

    // MARK: - Shot-chance model (L1160-1253)

    /**
     * Shot percentage is not a timing minigame. It is a readable summary of basketball quality:
     * shot zone, how settled the gather is, defender position, movement and space created by fakes.
     */
    func calculateHumanShotChance() -> Int {
        let zone = courtView.currentHumanShotZone()
        let base = baseShotChance(profile: humanProfile, zone: zone, finish: heldFinish)
        let elapsedMs: Int64 =
            shotMeterStartedAtNanos == 0 ? 0
            : ((ASystem.nanoTime() - shotMeterStartedAtNanos) / 1_000_000).coerceAtLeast(0)
        let settleMs: Int64 =
            heldFinish == TripleShotCourtView.OneOnOneDriveFinish.JUMPER
                ? Self.SHOT_METER_SETTLE_MS
                : Self.SHOT_METER_FINISH_SETTLE_MS
        let settle01 = (elapsedMs.toFloat() / settleMs.toFloat()).coerceIn(0, 1)
        let readiness = Float(0.67) + settle01 * Float(0.33)

        let contest01 = courtView.oneOnOneHumanShotContest01()
        let offense01 = humanProfile.ratings.offense.toFloat() / Float(100)
        let contestPenalty = contest01 * (Float(41) - offense01 * Float(11))
        let movement01 = currentRecentMovementIntensity()
        let agility01 = humanProfile.ratings.agility.toFloat() / Float(100)
        let movementPenalty: Float =
            heldFinish == TripleShotCourtView.OneOnOneDriveFinish.JUMPER
                ? movement01 * (Float(10) - agility01 * Float(3.5))
                : 0
        let escapePenalty: Float = shotEscapeUsed ? 3.0 : 0

        let quality = base * readiness - contestPenalty - movementPenalty - escapePenalty
        return quality
            .toInt()
            .coerceIn(Self.MIN_SHOT_CHANCE_PERCENT, Self.MAX_SHOT_CHANCE_PERCENT)
    }

    func calculateBotShotChance(
        zone: ShotZone,
        finish: TripleShotCourtView.OneOnOneDriveFinish
    ) -> Int {
        let base = baseShotChance(profile: botProfile, zone: zone, finish: finish)
        let contest01 = courtView.oneOnOneBotShotContest01()
        let offense01 = botProfile.ratings.offense.toFloat() / Float(100)
        let contestPenalty = contest01 * (Float(42) - offense01 * Float(10))
        let jumperPenalty: Float =
            finish == TripleShotCourtView.OneOnOneDriveFinish.JUMPER ? Self.BOT_JUMPER_FLOW_PENALTY : 0
        let raw = (base - contestPenalty - jumperPenalty).toInt()

        // If the defender has genuinely abandoned the rim, a close finish should feel like the
        // punishment it is in basketball. This is not a free score: a real late block can still
        // change the physical ball. Consecutive open misses raise the floor further.
        let openFinishFloor: Int
        if contest01 <= Float(0.10) {
            switch finish {
            case .DUNK:
                openFinishFloor = botConsecutiveMisses >= 2 ? 99 : 98
            case .LAYUP:
                openFinishFloor = botConsecutiveMisses >= 2 ? 98 : 95
            case .JUMPER:
                openFinishFloor = 0
            }
        } else {
            openFinishFloor = 0
        }

        let botMaxChance: Int =
            (contest01 <= Float(0.10) && finish != TripleShotCourtView.OneOnOneDriveFinish.JUMPER)
                ? Self.BOT_OPEN_FINISH_MAX_CHANCE_PERCENT
                : Self.MAX_SHOT_CHANCE_PERCENT

        return max(raw, openFinishFloor)
            .coerceIn(Self.MIN_SHOT_CHANCE_PERCENT, botMaxChance)
    }

    func baseShotChance(
        profile: TripleShotCharacterProfile,
        zone: ShotZone,
        finish: TripleShotCourtView.OneOnOneDriveFinish
    ) -> Float {
        switch finish {
        case .DUNK:
            return Float(70) + profile.ratings.dunking.toFloat() * Float(0.28)
        case .LAYUP:
            return Float(60) + profile.ratings.inside.toFloat() * Float(0.34)
        case .JUMPER:
            switch zone {
            case .INSIDE: return Float(48) + profile.ratings.inside.toFloat() * Float(0.44)
            case .MID_RANGE: return Float(38) + profile.ratings.midRange.toFloat() * Float(0.46)
            case .THREE_POINT: return Float(28) + profile.ratings.threePoint.toFloat() * Float(0.49)
            }
        }
    }

    // MARK: - Seeded make/miss translation (L1255-1330)

    /**
     * The displayed percentage is real. We roll once, then translate that decision back into the
     * existing physical ball engine: makes get a very clean launch; misses get a believable small
     * left/right or long/short error. Physical blocks can still turn a good roll into a miss.
     */
    func chanceDrivenSkill(
        baseSkill: ShotSkill,
        chancePercent: Int,
        sequence: Int64,
        salt: Int64,
        zone: ShotZone,
        finish: TripleShotCourtView.OneOnOneDriveFinish
    ) -> ShotSkill {
        let chance = chancePercent.coerceIn(Self.MIN_SHOT_CHANCE_PERCENT, Self.MAX_SHOT_CHANCE_PERCENT)
        // Kotlin `seed xor (sequence * salt) xor chance.toLong().shl(17)` (Long multiply wraps).
        let random = KotlinRandom(seed: seed ^ (sequence &* salt) ^ (chance.toLong() &<< 17))
        let madeRoll = random.nextInt(100) < chance

        if madeRoll {
            // Once the visible percentage roll says "make", send a true centre-line release.
            // A real defender hand may still block it; otherwise the physical shot should score.
            return baseSkill.copy(
                aimError: 0,
                powerError: 0,
                arcError: 0,
                rawPeakGyro: 0,
                rawReleasePitchDeg: 0
            )
        } else {
            let direction: Float = random.nextBoolean() ? 1 : -1

            /*
             * A miss should LOOK like a miss: inside/mid misses target the physical rim edge on
             * purpose (the rim is ~0.73 aim units from centre); long misses can be rim-outs or clear
             * long/short misses.
             */
            let rimTarget: Float
            switch finish {
            case .DUNK:
                rimTarget = direction * (Float(0.70) + random.nextFloat() * Float(0.05))
            case .LAYUP:
                rimTarget = direction * (Float(0.69) + random.nextFloat() * Float(0.07))
            case .JUMPER:
                switch zone {
                case .INSIDE: rimTarget = direction * (Float(0.70) + random.nextFloat() * Float(0.08))
                case .MID_RANGE: rimTarget = direction * (Float(0.72) + random.nextFloat() * Float(0.11))
                case .THREE_POINT: rimTarget = direction * (Float(0.74) + random.nextFloat() * Float(0.18))
                }
            }

            // Short-circuit: the extra nextFloat() is drawn only for three-point jumpers.
            let useLongShortMiss =
                zone == ShotZone.THREE_POINT &&
                    finish == TripleShotCourtView.OneOnOneDriveFinish.JUMPER &&
                    random.nextFloat() < Float(0.28)
            // Each branch draws nextBoolean() (the sign) before nextFloat() (the magnitude), left to right.
            let powerMiss: Float
            if useLongShortMiss {
                let sign: Float = random.nextBoolean() ? 1 : -1
                powerMiss = sign * (Float(0.050) + random.nextFloat() * Float(0.035))
            } else if finish != TripleShotCourtView.OneOnOneDriveFinish.JUMPER {
                // Close misses should not produce the same canned rebound every time.
                let sign: Float = random.nextBoolean() ? 1 : -1
                powerMiss = sign * (Float(0.010) + random.nextFloat() * Float(0.020))
            } else {
                let sign: Float = random.nextBoolean() ? 1 : -1
                powerMiss = sign * (Float(0.006) + random.nextFloat() * Float(0.012))
            }

            return baseSkill.copy(
                aimError: useLongShortMiss ? direction * Float(0.34) : rimTarget,
                powerError: powerMiss,
                arcError: 0,
                rawPeakGyro: 0,
                rawReleasePitchDeg: 0
            )
        }
    }

    // MARK: - Fake history and bot reads (L1332-1408)

    func recordHumanShotDecision(fake: Bool) {
        recentHumanShotFakes.append(fake)
        while recentHumanShotFakes.count > 3 { recentHumanShotFakes.remove(at: 0) }
    }

    /**
     * The bot learns only the last few gathers, like a defender reading tendencies rather than
     * cheating. Repeated fakes make the next jump less likely; repeated real shots make it more
     * likely. Mixed history stays genuinely uncertain.
     */
    func shouldBotBiteOnCurrentGather() -> Bool {
        let fakeRate: Float =
            recentHumanShotFakes.isEmpty ? 0.34
            : recentHumanShotFakes.filter { $0 }.count.toFloat() / recentHumanShotFakes.count.toFloat()
        let aggression01 = botProfile.tendencies.blockAggression.toFloat() / Float(100)
        let fakeCraft =
            (humanProfile.ratings.offense.toFloat() * Float(0.62) +
                humanProfile.ratings.ballHandling.toFloat() * Float(0.38)) / Float(100)
        let defenderDiscipline =
            (botProfile.ratings.defense.toFloat() * Float(0.68) +
                botProfile.ratings.agility.toFloat() * Float(0.32)) / Float(100)
        let skillEdge = (fakeCraft - defenderDiscipline).coerceIn(-0.65, 0.65)
        let base = Float(0.56) + aggression01 * Float(0.22)
        let learned = base + (Float(0.34) - fakeRate) * Float(0.72) + skillEdge * Float(0.22)
        let chance = learned.coerceIn(0.12, 0.94)
        // Kotlin `seed xor (shotSequence + 1L) * SALT xor recentHumanShotFakes.hashCode().toLong()`.
        let r = KotlinRandom(
            seed: seed ^ ((shotSequence &+ 1) &* Self.BOT_FAKE_READ_SEED_SALT) ^
                recentHumanShotFakes.javaHashCode.toLong()
        )
        return r.nextFloat() < chance
    }

    /**
     * A close defender may contest every shot positionally, but a physical BLOCK requires a real
     * jump decision. Blocking/Agility/Defense and block aggression affect that decision; recent
     * pump fakes make a disciplined defender less eager to leave the floor.
     */
    func shouldBotJumpOnRealShot() -> Bool {
        let pressure01 = courtView.oneOnOneHumanShotContest01()
        if pressure01 < Float(0.16) { return false }

        let block01 = botProfile.ratings.blocking.coerceIn(0, 100).toFloat() / Float(100)
        let agility01 = botProfile.ratings.agility.coerceIn(0, 100).toFloat() / Float(100)
        let defense01 = botProfile.ratings.defense.coerceIn(0, 100).toFloat() / Float(100)
        let aggression01 = botProfile.tendencies.blockAggression.coerceIn(0, 100).toFloat() / Float(100)
        let fakeRate: Float =
            recentHumanShotFakes.isEmpty ? 0.30
            : recentHumanShotFakes.filter { $0 }.count.toFloat() / recentHumanShotFakes.count.toFloat()
        let realRate = Float(1) - fakeRate

        // `0.05f + block01 * 0.25f + ... + realRate * 0.08f - fakeRate * 0.17f`, summed left to right.
        var rawReadChance = Float(0.05) + block01 * Float(0.25)
        rawReadChance = rawReadChance + agility01 * Float(0.08)
        rawReadChance = rawReadChance + defense01 * Float(0.07)
        rawReadChance = rawReadChance + aggression01 * Float(0.15)
        rawReadChance = rawReadChance + pressure01 * Float(0.27)
        rawReadChance = rawReadChance + realRate * Float(0.08)
        rawReadChance = rawReadChance - fakeRate * Float(0.17)

        // Sweet spot: a close defender should visibly challenge some real shots, but "close" must
        // never mean an automatic block. The floor controls jump ATTEMPTS only.
        let pressureFloor: Float
        if pressure01 >= Float(0.72) {
            pressureFloor = 0.54
        } else if pressure01 >= Float(0.48) {
            pressureFloor = 0.38
        } else if pressure01 >= Float(0.28) {
            pressureFloor = 0.23
        } else {
            pressureFloor = 0.07
        }
        let readChance = kmax(rawReadChance, pressureFloor).coerceIn(0.07, 0.74)

        let r = KotlinRandom(
            seed: seed ^ ((shotSequence &+ 1) &* Self.BOT_REAL_SHOT_READ_SEED_SALT) ^
                recentHumanShotFakes.javaHashCode.toLong()
        )
        return r.nextFloat() < readChance
    }

    // L1410-1417 setQuickShotBasePull / applyQuickShotPull and L1425-1458 handleTapCandidate (dead): not ported.

    // MARK: - Defensive taps (L1460-1498)

    /**
     * Context tap is defensive-first. On offense, shooting belongs to the primary press/hold/release
     * gesture; a second finger is only meaningful after the dribble has already been gathered, where
     * it becomes a pump fake.
     */
    func performContextTapAction() {
        if ended || possessionQuestionActive { return }

        if humanHasBall && humanDribblePickedUp && aiming {
            // handleHeldBallTap(): unreachable in production (spec 15 section 3.9), not ported.
        } else if quickShotActive {
            // convertQuickShotToPumpFake(): quickShotActive is never set (spec 15 section 3.9), not ported.
        } else if !humanHasBall && reboundActive {
            if courtView.oneOnOneHumanJumpOrReboundAttempt(allowBlock: false) {
                statusText.setText(res: R.string.minik_swish_one_on_one_rebound_jump)
            }
        } else if !humanHasBall && shotInProgress && courtView.oneOnOneHumanShouldAttemptBlock() {
            if courtView.oneOnOneHumanBlockAttempt() {
                statusText.setText(res: R.string.minik_swish_one_on_one_block_timing)
            }
        } else if !humanHasBall && shotInProgress {
            if courtView.oneOnOneHumanJumpOrReboundAttempt(allowBlock: false) {
                statusText.setText(res: R.string.minik_swish_one_on_one_rebound_jump)
            }
        } else if !humanHasBall {
            if courtView.oneOnOneHumanStealAttempt() {
                statusText.setText(res: R.string.minik_swish_one_on_one_steal_reach)
            }
        }
    }

    // L1500-1682 startQuickShot, quickShotStillValid, convertQuickShotToPumpFake, releaseQuickShot (dead): not ported.

    // MARK: - Momentum and dribble-move detectors (L1684-1728)

    func currentRecentMovementIntensity() -> Float {
        if recentMoveAtNanos == 0 { return 0 }
        let ageMs = (ASystem.nanoTime() - recentMoveAtNanos) / 1_000_000
        if ageMs >= Self.RECENT_MOVE_DECAY_MS { return 0 }
        // Preserve the last drive through the tap/double-tap recognition window.
        let remaining: Float =
            ageMs <= 300 ? 1
            : Float(1) - (ageMs - 300).toFloat() / (Self.RECENT_MOVE_DECAY_MS - 300).toFloat()
        return (recentMoveIntensity01 * remaining).coerceIn(0, 1)
    }

    /// Kotlin `private val circularGesture by lazy { CircularDribbleGesture(dp(14f)) }`.
    lazy var circularGesture = CircularDribbleGesture(minimumRadius: dp(value: 14))
    /// Kotlin `private val dribbleGesture by lazy { DribbleGesture(dp(18f)) }`.
    lazy var dribbleGesture = DribbleGesture(legDistance: dp(value: 18))

    func detectCrossoverGesture(rawDx: Float) {
        let sign = dribbleGesture.move(dx: rawDx, now: ASystemClock.elapsedRealtime())
        if sign == 0 { return }
        courtView.oneOnOneHumanCrossover(directionSign: sign.toFloat())
        statusText.setText(res: R.string.minik_swish_one_on_one_crossover)
    }

    /** Forward burst followed quickly by retreat = hesitation / step-back setup. */
    func detectHesitationGesture(rawDy: Float) {
        if abs(rawDy) < dp(value: Self.HESITATION_MIN_SEGMENT_DP) { return }
        let now = ASystem.nanoTime()
        if verticalGestureStartedAtNanos == 0 ||
            now - verticalGestureStartedAtNanos > Self.HESITATION_GESTURE_WINDOW_MS * 1_000_000 {
            verticalGestureStartedAtNanos = now
            lastVerticalMoveSign = 0
            verticalDirectionChanges = 0
        }

        let sign = rawDy < 0 ? -1 : 1
        if lastVerticalMoveSign != 0 && sign != lastVerticalMoveSign {
            verticalDirectionChanges += 1
        }
        // Only reward a real drive -> retreat change, not ordinary vertical jitter.
        if lastVerticalMoveSign < 0 && sign > 0 && verticalDirectionChanges >= 1 {
            courtView.oneOnOneHumanHesitation()
            statusText.setText(res: R.string.minik_swish_one_on_one_hesitation)
            verticalGestureStartedAtNanos = now
            verticalDirectionChanges = 0
        }
        lastVerticalMoveSign = sign
    }

    // L1730-1742 enterShotAim, L1744-1751 performPumpFake, L1753-1793 handleJumpPadTouch (no caller): not ported.
}

// MARK: - Layouts (res/layout and res/layout-land fragment_triple_shot_one_on_one.xml)

/// The two XML layouts of the 1v1 screen, built in code exactly like LayoutInflater builds them: every view with the
/// same class, id, attributes (in px / sp, rounded like Resources.getDimension / getDimensionPixelSize) and layout
/// params, children added before their parent is added to its own parent. Android picks `layout-land` when the
/// configuration orientation is landscape at inflation (the host locks the orientation before committing the
/// fragment); `inflate` does the same.
///
/// iOS-only addition: one exit control (`IOS_EXIT_CONTROL_ID`, see `iosExitControl`), because Android exits this
/// screen during live play only through the system Back key / edge swipe; the root (TripleShotOneOnOneRootLayout)
/// hides it while the question card or the result overlay is up.
enum TripleShotOneOnOneLayouts {
    static let PARENT = AConstraintLayout.LayoutParams.PARENT_ID
    static let MATCH = AViewGroup.LayoutParams.MATCH_PARENT
    static let WRAP = AViewGroup.LayoutParams.WRAP_CONTENT
    /// Id of the iOS-only exit control (not an Android id).
    static let IOS_EXIT_CONTROL_ID = "oneOnOneIosExitControl"

    /// The layout builder registered for R.layout.fragment_triple_shot_one_on_one.
    static func inflate(_ inflater: ALayoutInflater) -> AView {
        let configuration = AContextResources.shared.configuration
        if configuration.orientation == AConfiguration.ORIENTATION_LANDSCAPE {
            return buildLandscape()
        }
        return buildPortrait()
    }

    // MARK: Attribute helpers

    /// A dp dimension read with getDimensionPixelSize (sizes, margins, paddings, button radii, stroke widths).
    static func px(_ dp: Float) -> Int {
        return ATypedValue.toDimensionPixelSize(ATypedValue.COMPLEX_UNIT_DIP, dp)
    }

    /// A dp dimension read with getDimension (MaterialCardView cardCornerRadius / cardElevation).
    static func pxF(_ dp: Float) -> Float {
        return ATypedValue.applyDimension(ATypedValue.COMPLEX_UNIT_DIP, dp)
    }

    /// `android:textStyle="bold"` under the theme's android:fontFamily "sans": setTypeface(create("sans"), BOLD).
    static func bold(_ view: ATextView) {
        view.setTypeface(ATypeface.create("sans", ATypeface.NORMAL), ATypeface.BOLD)
    }

    /// A <TextView> with gravity, textColor, textSize (sp) and optional bold textStyle.
    static func text(_ id: String?, gravity: Int, color: Int, sizeSp: Float, bold isBold: Bool) -> ATextView {
        let view = ATextView()
        if let id = id { view.viewId = id }
        view.setGravity(gravity)
        view.setTextColor(color)
        view.applyXmlTextSize(sizeSp)
        if isBold { bold(view) }
        return view
    }

    /// A <MaterialCardView> with cardBackgroundColor, cardCornerRadius, cardElevation and optional stroke.
    static func card(_ id: String?, background: Int, radiusDp: Float, elevationDp: Float,
                     strokeColor: Int?, strokeWidthDp: Float) -> ACardView {
        let card = ACardView()
        if let id = id { card.viewId = id }
        card.setCardBackgroundColor(background)
        card.radius = pxF(radiusDp)
        card.cardElevation = pxF(elevationDp)
        if let strokeColor = strokeColor { card.strokeColor = strokeColor }
        if strokeWidthDp > 0 { card.strokeWidth = px(strokeWidthDp) }
        return card
    }

    /// A vertical <LinearLayout> with paddingHorizontal / paddingVertical.
    static func column(horizontalPaddingDp: Float, verticalPaddingDp: Float) -> ALinearLayout {
        let column = ALinearLayout()
        column.orientation = ALinearLayout.VERTICAL
        column.setPadding(px(horizontalPaddingDp), px(verticalPaddingDp), px(horizontalPaddingDp), px(verticalPaddingDp))
        return column
    }

    /// LinearLayout.LayoutParams with an optional weight and layout_marginTop.
    static func linear(_ width: Int, _ height: Int, weight: Float = 0, topDp: Float = 0) -> ALinearLayout.LayoutParams {
        let lp = weight != 0 ? ALinearLayout.LayoutParams(width, height, weight) : ALinearLayout.LayoutParams(width, height)
        if topDp != 0 { lp.topMargin = px(topDp) }
        return lp
    }

    /// ConstraintLayout.LayoutParams constrained to the parent on the given sides.
    static func constrained(_ width: Int, _ height: Int, top: Bool = false, bottom: Bool = false,
                            start: Bool = false, end: Bool = false) -> AConstraintLayout.LayoutParams {
        let lp = AConstraintLayout.LayoutParams(width, height)
        if top { lp.topToTop = PARENT }
        if bottom { lp.bottomToBottom = PARENT }
        if start { lp.startToStart = PARENT }
        if end { lp.endToEnd = PARENT }
        return lp
    }

    /// 0dp x 0dp constrained to all four parent edges (fills the padded root).
    static func fillParent() -> AConstraintLayout.LayoutParams {
        return constrained(0, 0, top: true, bottom: true, start: true, end: true)
    }

    /// MaterialButton XML insets: android:insetLeft/Right/Top/Bottom (the padding keeps its distance to the face).
    static func insets(_ button: AButton, left: Int, top: Int, right: Int, bottom: Int) {
        button.applyXmlHorizontalInsets(left, right)
        button.setInsetTop(top)
        button.setInsetBottom(bottom)
    }

    /// android:minWidth / android:minHeight on a TextView: both View's minimum and TextView's minimum.
    static func minSize(_ view: ATextView, widthDp: Float?, heightDp: Float?) {
        if let w = widthDp {
            view.minimumWidth = px(w)
            view.minWidth = px(w)
        }
        if let h = heightDp {
            view.minimumHeight = px(h)
            view.minHeight = px(h)
        }
    }

    // MARK: Shared parts

    /// <ConstraintLayout> root: match_parent, background #101820, layoutDirection locale (see
    /// TripleShotOneOnOneRootLayout for its one iOS-only rule).
    static func root() -> AConstraintLayout {
        let root = TripleShotOneOnOneRootLayout()
        root.layoutParams = AViewGroup.LayoutParams(MATCH, MATCH)
        root.setBackgroundColor(argbInt(0xFF101820))
        root.layoutDirection = AView.LAYOUT_DIRECTION_LOCALE
        return root
    }

    /// <ImageView oneOnOneBackground> (scaleType matrix, src triple_shot_court_background) and
    /// <TripleShotCourtView oneOnOneCourtView>, both 0dp x 0dp to all parent edges.
    static func addBackgroundAndCourt(_ root: AConstraintLayout) {
        let background = AImageView()
        background.viewId = R.id.oneOnOneBackground
        background.scaleType = AImageView.ScaleType.MATRIX
        background.setImageResource(R.drawable.triple_shot_court_background)
        root.addView(background, fillParent())

        let court = TripleShotCourtView()
        court.viewId = R.id.oneOnOneCourtView
        root.addView(court, fillParent())
    }

    /// The HUD row and status inside the HUD card.
    static func hudContent(verticalPaddingDp: Float, scoreSp: Float, possessionSp: Float, statusSp: Float,
                           statusTopDp: Float, statusEllipsize: Bool) -> ALinearLayout {
        let content = column(horizontalPaddingDp: 10, verticalPaddingDp: verticalPaddingDp)

        let row = ALinearLayout()
        row.orientation = ALinearLayout.HORIZONTAL
        row.setGravity(AGravity.CENTER_VERTICAL)

        let human = text(R.id.oneOnOneHumanScore, gravity: AGravity.START, color: argbInt(0xFF142129),
                         sizeSp: scoreSp, bold: true)
        row.addView(human, linear(0, WRAP, weight: 1))

        let possession = text(R.id.oneOnOnePossession, gravity: AGravity.CENTER, color: argbInt(0xFF087E70),
                              sizeSp: possessionSp, bold: true)
        possession.setPadding(px(7), possession.paddingTop, px(7), possession.paddingBottom)
        row.addView(possession, linear(WRAP, WRAP))

        let bot = text(R.id.oneOnOneBotScore, gravity: AGravity.END, color: argbInt(0xFF6B3EB4),
                       sizeSp: scoreSp, bold: true)
        row.addView(bot, linear(0, WRAP, weight: 1))

        content.addView(row, linear(MATCH, WRAP))

        let status = text(R.id.oneOnOneStatus, gravity: AGravity.CENTER, color: argbInt(0xFF46545B),
                          sizeSp: statusSp, bold: false)
        status.maxLines = 2
        if statusEllipsize { status.ellipsize = ATextUtils.TruncateAt.END }
        status.setText(res: R.string.minik_swish_one_on_one_start_hint)
        content.addView(status, linear(MATCH, WRAP, topDp: statusTopDp))
        return content
    }

    /// <ProgressBar oneOnOneShotMeter> style ?android:attr/progressBarStyleHorizontal, max 95, progress 0,
    /// progressBackgroundTint #D8E5E1, progressTint #087E70.
    static func shotMeter() -> AProgressBar {
        let meter = AProgressBar(style: AProgressBar.Style.HORIZONTAL)
        meter.viewId = R.id.oneOnOneShotMeter
        meter.max = 95
        meter.progress = 0
        meter.progressTintList = AColorStateList.valueOf(argbInt(0xFF087E70))
        meter.progressBackgroundTintList = AColorStateList.valueOf(argbInt(0xFFD8E5E1))
        return meter
    }

    /// <FrameLayout oneOnOneResultOverlay>: 0dp x 0dp to all edges, #B8000000, clickable, focusable, gone.
    static func resultOverlay(card: ACardView, cardParams: AFrameLayout.LayoutParams) -> AFrameLayout {
        let overlay = AFrameLayout()
        overlay.viewId = R.id.oneOnOneResultOverlay
        overlay.setBackgroundColor(argbInt(0xB8000000))
        overlay.isClickable = true
        overlay.isFocusable = true
        overlay.visibility = AView.GONE
        overlay.addView(card, cardParams)
        return overlay
    }

    /// iOS-only exit control (DESIGN 2.8 / 12.3, spec 15 section 10.2): the app's own close icon (triple_close, the
    /// icon TripleShotControls gives "Exit" buttons) in a 44 dp touch target at the end edge, below the HUD card in
    /// portrait and beside the centred HUD card in landscape. Z 0 and added before the result overlay, so the overlay
    /// and the question card (elevation 10) are drawn above it; the root hides it while either of them is visible
    /// (both have their own exit button). VoiceOver label: the question card's "Exit game" string.
    static func iosExitControl(_ root: AConstraintLayout, landscape: Bool) {
        let control = AImageView()
        control.viewId = IOS_EXIT_CONTROL_ID
        control.scaleType = AImageView.ScaleType.FIT_CENTER
        control.setImageResource(R.drawable.triple_close)
        control.setPadding(px(8), px(8), px(8), px(8))
        control.isClickable = true
        control.isFocusable = true
        control.contentDescription = AResources.getString(R.string.minik_swish_one_on_one_question_exit)
        let lp = AConstraintLayout.LayoutParams(px(44), px(44))
        lp.marginEnd = px(8)
        lp.endToEnd = PARENT
        if landscape {
            lp.topMargin = px(5)
            lp.topToTop = PARENT
        } else {
            lp.topMargin = px(8)
            lp.topToBottom = R.id.oneOnOneHudCard
        }
        root.addView(control, lp)
    }

    // MARK: Portrait (res/layout)

    static func buildPortrait() -> AView {
        let root = self.root()
        addBackgroundAndCourt(root)

        // oneOnOneHudCard: 0dp x wrap, marginStart/End 8dp, marginTop 6dp, #EFFFFDF7, radius 18, elevation 5,
        // stroke #D9FFFFFF 1dp; top/start/end to parent.
        let hud = card(R.id.oneOnOneHudCard, background: argbInt(0xEFFFFDF7), radiusDp: 18, elevationDp: 5,
                       strokeColor: argbInt(0xD9FFFFFF), strokeWidthDp: 1)
        hud.addView(hudContent(verticalPaddingDp: 7, scoreSp: 15, possessionSp: 11, statusSp: 11,
                               statusTopDp: 2, statusEllipsize: false),
                    AFrameLayout.LayoutParams(MATCH, WRAP))
        let hudParams = constrained(0, WRAP, top: true, start: true, end: true)
        hudParams.marginStart = px(8)
        hudParams.topMargin = px(6)
        hudParams.marginEnd = px(8)
        root.addView(hud, hudParams)

        // oneOnOneShotMeterCard: 220dp x wrap, marginTop 8dp, gone, #F2FFFDF8, radius 18, elevation 5,
        // stroke #B0087E70 1dp; below the HUD, start/end to parent.
        let meterCard = card(R.id.oneOnOneShotMeterCard, background: argbInt(0xF2FFFDF8), radiusDp: 18, elevationDp: 5,
                             strokeColor: argbInt(0xB0087E70), strokeWidthDp: 1)
        meterCard.visibility = AView.GONE
        let meterContent = column(horizontalPaddingDp: 12, verticalPaddingDp: 8)
        let chance = text(R.id.oneOnOneShotChanceText, gravity: AGravity.CENTER, color: argbInt(0xFF142129),
                          sizeSp: 13, bold: true)
        chance.setText(res: R.string.minik_swish_one_on_one_shot_quality_default)
        meterContent.addView(chance, linear(MATCH, WRAP))
        meterContent.addView(shotMeter(), linear(MATCH, px(8), topDp: 5))
        let hint = text(nil, gravity: AGravity.CENTER, color: argbInt(0xFF5C696F), sizeSp: 9.5, bold: false)
        hint.setText(res: R.string.minik_swish_one_on_one_shot_control_hint)
        meterContent.addView(hint, linear(MATCH, WRAP, topDp: 4))
        meterCard.addView(meterContent, AFrameLayout.LayoutParams(MATCH, WRAP))
        let meterParams = constrained(px(220), WRAP, start: true, end: true)
        meterParams.topMargin = px(8)
        meterParams.topToBottom = R.id.oneOnOneHudCard
        root.addView(meterCard, meterParams)

        // oneOnOneQuestionCard: 0dp x wrap, marginStart/End 14dp, marginTop 10dp, clickable, focusable, gone,
        // #E6FFFDF8, radius 22, elevation 10, stroke #B0087E70 1dp; below the HUD, start/end to parent.
        let questionCard = card(R.id.oneOnOneQuestionCard, background: argbInt(0xE6FFFDF8), radiusDp: 22,
                                elevationDp: 10, strokeColor: argbInt(0xB0087E70), strokeWidthDp: 1)
        questionCard.isClickable = true
        questionCard.isFocusable = true
        questionCard.visibility = AView.GONE
        let questionContent = column(horizontalPaddingDp: 12, verticalPaddingDp: 12)
        let title = text(R.id.oneOnOneQuestionTitle, gravity: AGravity.CENTER, color: argbInt(0xFF7042B8),
                         sizeSp: 12, bold: true)
        questionContent.addView(title, linear(MATCH, WRAP))
        let prompt = text(R.id.oneOnOneQuestionPrompt, gravity: AGravity.CENTER, color: argbInt(0xFF142129),
                          sizeSp: 17, bold: true)
        prompt.textDirection = AView.TEXT_DIRECTION_LOCALE
        questionContent.addView(prompt, linear(MATCH, WRAP, topDp: 5))
        let answerIds = [R.id.oneOnOneQuestionAnswer1, R.id.oneOnOneQuestionAnswer2,
                         R.id.oneOnOneQuestionAnswer3, R.id.oneOnOneQuestionAnswer4]
        for (index, answerId) in answerIds.enumerated() {
            // TripleShotButton, style Widget.MaterialComponents.Button.OutlinedButton.
            let answer = TripleShotButton(style: AButton.Style.OUTLINED)
            answer.viewId = answerId
            minSize(answer, widthDp: nil, heightDp: 42)
            answer.setAllCaps(false)
            answer.setTextColor(argbInt(0xFF142129))
            answer.textDirection = AView.TEXT_DIRECTION_LOCALE
            answer.applyXmlTextSize(14)
            answer.cornerRadius = px(14)
            answer.strokeColor = AColorStateList.valueOf(argbInt(0x80087E70))
            questionContent.addView(answer, linear(MATCH, WRAP, topDp: index == 0 ? 8 : 5))
        }
        let feedback = text(R.id.oneOnOneQuestionFeedback, gravity: AGravity.CENTER, color: argbInt(0xFF46545B),
                            sizeSp: 11, bold: true)
        questionContent.addView(feedback, linear(MATCH, WRAP, topDp: 6))
        let continueButton = TripleShotButton()
        continueButton.viewId = R.id.oneOnOneQuestionContinue
        continueButton.setText(res: R.string.minik_swish_one_on_one_question_continue)
        continueButton.setAllCaps(false)
        continueButton.setTextColor(argbInt(0xFFFFFFFF))
        continueButton.applyXmlTextSize(14)
        bold(continueButton)
        continueButton.visibility = AView.GONE
        continueButton.setBackgroundTintList(AColorStateList.valueOf(argbInt(0xFF087E70)))
        continueButton.cornerRadius = px(15)
        questionContent.addView(continueButton, linear(MATCH, px(44), topDp: 9))
        // TripleShotButton, style Widget.MaterialComponents.Button.TextButton: wrap x 48dp, centre_horizontal,
        // marginTop 10dp, minHeight/minWidth 0, paddingHorizontal 10dp, insetTop/insetBottom 0, backgroundTint #E91E63.
        let exitButton = TripleShotButton(style: AButton.Style.TEXT)
        exitButton.viewId = R.id.oneOnOneQuestionExit
        minSize(exitButton, widthDp: 0, heightDp: 0)
        exitButton.setInsetBottom(0)
        exitButton.setInsetTop(0)
        // paddingHorizontal replaces the style's 8dp sides; the style's 4dp top/bottom stay (+ the 0 insets).
        exitButton.setPadding(px(10), exitButton.paddingTop, px(10), exitButton.paddingBottom)
        exitButton.setText(res: R.string.minik_swish_one_on_one_question_exit)
        exitButton.setAllCaps(false)
        exitButton.setTextColor(argbInt(0xFFFFFFFF))
        exitButton.applyXmlTextSize(17)
        exitButton.setBackgroundTintList(AColorStateList.valueOf(argbInt(0xFFE91E63)))
        let exitParams = linear(WRAP, px(48), topDp: 10)
        exitParams.gravity = AGravity.CENTER_HORIZONTAL
        questionContent.addView(exitButton, exitParams)
        questionCard.addView(questionContent, AFrameLayout.LayoutParams(MATCH, WRAP))
        let questionParams = constrained(0, WRAP, start: true, end: true)
        questionParams.marginStart = px(14)
        questionParams.topMargin = px(10)
        questionParams.marginEnd = px(14)
        questionParams.topToBottom = R.id.oneOnOneHudCard
        root.addView(questionCard, questionParams)

        // oneOnOneControls (legacy, always GONE at runtime): wrap x wrap, invisible, marginBottom 10dp, #C91A2631,
        // radius 30, elevation 8, stroke #B076E6DC 1dp; bottom/start/end to parent.
        let controls = card(R.id.oneOnOneControls, background: argbInt(0xC91A2631), radiusDp: 30, elevationDp: 8,
                            strokeColor: argbInt(0xB076E6DC), strokeWidthDp: 1)
        controls.visibility = AView.INVISIBLE
        let controlsRow = ALinearLayout()
        controlsRow.setGravity(AGravity.CENTER)
        controlsRow.orientation = ALinearLayout.HORIZONTAL
        controlsRow.setPadding(px(8), px(7), px(8), px(7))
        controlsRow.addView(
            portraitRoundControl(R.id.oneOnOneShootButton, style: AButton.Style.FILLED, sizeDp: 70,
                                 textRes: R.string.minik_swish_one_on_one_shoot, textColor: argbInt(0xFFFFFFFF),
                                 textSp: 12, tint: argbInt(0xD7087E70), radiusDp: 35, stroke: argbInt(0xFF82FFF0)),
            roundControlParams(sizeDp: 70))
        controlsRow.addView(
            portraitRoundControl(R.id.oneOnOneBlockButton, style: AButton.Style.FILLED, sizeDp: 70,
                                 textRes: R.string.minik_swish_one_on_one_block, textColor: argbInt(0xFFFFFFFF),
                                 textSp: 12, tint: argbInt(0xD77042B8), radiusDp: 35, stroke: argbInt(0xFFD7BCFF)),
            roundControlParams(sizeDp: 70))
        controlsRow.addView(
            portraitRoundControl(R.id.oneOnOneJumpButton, style: AButton.Style.OUTLINED, sizeDp: 64,
                                 textRes: R.string.minik_swish_one_on_one_jump, textColor: argbInt(0xFFAEEBFF),
                                 textSp: 11, tint: argbInt(0xBE202C3B), radiusDp: 32, stroke: argbInt(0xFF71D7FF)),
            roundControlParams(sizeDp: 64))
        // Pump fake is gesture-driven; the old id stays as a zero-size compatibility fallback.
        let fake = TripleShotButton()
        fake.viewId = R.id.oneOnOneFakeButton
        fake.visibility = AView.GONE
        fake.setText(res: R.string.minik_swish_one_on_one_fake)
        controlsRow.addView(fake, linear(px(1), px(1)))
        controls.addView(controlsRow, AFrameLayout.LayoutParams(WRAP, WRAP))
        let controlsParams = constrained(WRAP, WRAP, bottom: true, start: true, end: true)
        controlsParams.bottomMargin = px(10)
        root.addView(controls, controlsParams)

        iosExitControl(root, landscape: false)

        // oneOnOneResultOverlay: the card is match x wrap, layout_gravity center, layout_margin 26dp, #FFFDF8,
        // radius 26, elevation 12; padding 22dp, gravity center.
        let resultCard = card(nil, background: argbInt(0xFFFFFDF8), radiusDp: 26, elevationDp: 12,
                              strokeColor: nil, strokeWidthDp: 0)
        let resultContent = column(horizontalPaddingDp: 22, verticalPaddingDp: 22)
        resultContent.setGravity(AGravity.CENTER)
        let resultTitle = text(R.id.oneOnOneResultTitle, gravity: AGravity.CENTER, color: argbInt(0xFF142129),
                               sizeSp: 26, bold: true)
        resultContent.addView(resultTitle, linear(MATCH, WRAP))
        let resultScore = text(R.id.oneOnOneResultScore, gravity: AGravity.CENTER, color: argbInt(0xFF7042B8),
                               sizeSp: 18, bold: true)
        resultContent.addView(resultScore, linear(MATCH, WRAP, topDp: 7))
        let buttons = ALinearLayout()
        buttons.orientation = ALinearLayout.HORIZONTAL
        let home = TripleShotButton(style: AButton.Style.OUTLINED)
        home.viewId = R.id.oneOnOneHomeButton
        home.setText(res: R.string.minik_swish_one_on_one_home)
        home.setAllCaps(false)
        home.cornerRadius = px(16)
        let homeParams = linear(0, px(48), weight: 1)
        homeParams.marginEnd = px(6)
        buttons.addView(home, homeParams)
        let again = TripleShotButton()
        again.viewId = R.id.oneOnOneAgainButton
        again.setText(res: R.string.minik_swish_one_on_one_again)
        again.setAllCaps(false)
        again.setBackgroundTintList(AColorStateList.valueOf(argbInt(0xFF087E70)))
        again.cornerRadius = px(16)
        let againParams = linear(0, px(48), weight: 1)
        againParams.marginStart = px(6)
        buttons.addView(again, againParams)
        resultContent.addView(buttons, linear(MATCH, WRAP, topDp: 18))
        resultCard.addView(resultContent, AFrameLayout.LayoutParams(MATCH, WRAP))
        let resultCardParams = AFrameLayout.LayoutParams(MATCH, WRAP, AGravity.CENTER)
        resultCardParams.setMargins(px(26), px(26), px(26), px(26))
        root.addView(resultOverlay(card: resultCard, cardParams: resultCardParams), fillParent())

        return root
    }

    /// The portrait legacy round controls (TripleShotButton, 70/64 dp, gone, minWidth/minHeight 0, all insets 0,
    /// padding 4dp, textAllCaps false, bold, backgroundTint, cornerRadius, strokeColor, strokeWidth 1dp).
    static func portraitRoundControl(_ id: String, style: AButton.Style, sizeDp: Float, textRes: AStringRes,
                                     textColor: Int, textSp: Float, tint: Int, radiusDp: Float,
                                     stroke: Int) -> AButton {
        let button = TripleShotButton(style: style)
        button.viewId = id
        button.visibility = AView.GONE
        minSize(button, widthDp: 0, heightDp: 0)
        insets(button, left: 0, top: 0, right: 0, bottom: 0)
        button.applyXmlPadding(px(4), px(4), px(4), px(4))
        button.setText(res: textRes)
        button.setAllCaps(false)
        button.setTextColor(textColor)
        button.applyXmlTextSize(textSp)
        bold(button)
        button.setBackgroundTintList(AColorStateList.valueOf(tint))
        button.cornerRadius = px(radiusDp)
        button.strokeColor = AColorStateList.valueOf(stroke)
        button.strokeWidth = px(1)
        return button
    }

    /// width = height = size, layout_marginHorizontal 3dp.
    static func roundControlParams(sizeDp: Float) -> ALinearLayout.LayoutParams {
        let lp = linear(px(sizeDp), px(sizeDp))
        lp.leftMargin = px(3)
        lp.rightMargin = px(3)
        return lp
    }

    // MARK: Landscape (res/layout-land)

    static func buildLandscape() -> AView {
        let root = self.root()
        addBackgroundAndCourt(root)

        // Compact landscape HUD: 440dp x wrap, marginTop 5dp, #EFFFFDF7, radius 16, elevation 4,
        // stroke #D9FFFFFF 1dp; top/start/end to parent (centred).
        let hud = card(R.id.oneOnOneHudCard, background: argbInt(0xEFFFFDF7), radiusDp: 16, elevationDp: 4,
                       strokeColor: argbInt(0xD9FFFFFF), strokeWidthDp: 1)
        hud.addView(hudContent(verticalPaddingDp: 5, scoreSp: 14, possessionSp: 10.5, statusSp: 9.5,
                               statusTopDp: 1, statusEllipsize: true),
                    AFrameLayout.LayoutParams(MATCH, WRAP))
        let hudParams = constrained(px(440), WRAP, top: true, start: true, end: true)
        hudParams.topMargin = px(5)
        root.addView(hud, hudParams)

        // oneOnOneShotMeterCard: 205dp x wrap, marginStart 8dp, marginTop 6dp, gone, #F2FFFDF8, radius 16,
        // elevation 4, stroke #B0087E70 1dp; below the HUD, start to parent. No hint line.
        let meterCard = card(R.id.oneOnOneShotMeterCard, background: argbInt(0xF2FFFDF8), radiusDp: 16, elevationDp: 4,
                             strokeColor: argbInt(0xB0087E70), strokeWidthDp: 1)
        meterCard.visibility = AView.GONE
        let meterContent = column(horizontalPaddingDp: 10, verticalPaddingDp: 5)
        let chance = text(R.id.oneOnOneShotChanceText, gravity: AGravity.CENTER, color: argbInt(0xFF142129),
                          sizeSp: 11.5, bold: true)
        chance.setText(res: R.string.minik_swish_one_on_one_shot_quality_default)
        meterContent.addView(chance, linear(MATCH, WRAP))
        meterContent.addView(shotMeter(), linear(MATCH, px(7), topDp: 3))
        meterCard.addView(meterContent, AFrameLayout.LayoutParams(MATCH, WRAP))
        let meterParams = constrained(px(205), WRAP, start: true)
        meterParams.marginStart = px(8)
        meterParams.topMargin = px(6)
        meterParams.topToBottom = R.id.oneOnOneHudCard
        root.addView(meterCard, meterParams)

        // Questions are a compact 2x2 overlay in landscape: 560dp x wrap, clickable, focusable, gone, #F4FFFDF8,
        // radius 20, elevation 10, stroke #B0087E70 1dp; centred (all four parent edges).
        let questionCard = card(R.id.oneOnOneQuestionCard, background: argbInt(0xF4FFFDF8), radiusDp: 20,
                                elevationDp: 10, strokeColor: argbInt(0xB0087E70), strokeWidthDp: 1)
        questionCard.isClickable = true
        questionCard.isFocusable = true
        questionCard.visibility = AView.GONE
        let questionContent = column(horizontalPaddingDp: 10, verticalPaddingDp: 10)
        let title = text(R.id.oneOnOneQuestionTitle, gravity: AGravity.CENTER, color: argbInt(0xFF7042B8),
                         sizeSp: 10.5, bold: true)
        questionContent.addView(title, linear(MATCH, WRAP))
        let prompt = text(R.id.oneOnOneQuestionPrompt, gravity: AGravity.CENTER, color: argbInt(0xFF142129),
                          sizeSp: 15, bold: true)
        prompt.maxLines = 3
        prompt.textDirection = AView.TEXT_DIRECTION_LOCALE
        questionContent.addView(prompt, linear(MATCH, WRAP, topDp: 3))
        questionContent.addView(
            landscapeAnswerRow(R.id.oneOnOneQuestionAnswer1, R.id.oneOnOneQuestionAnswer2),
            linear(MATCH, WRAP, topDp: 6))
        questionContent.addView(
            landscapeAnswerRow(R.id.oneOnOneQuestionAnswer3, R.id.oneOnOneQuestionAnswer4),
            linear(MATCH, WRAP, topDp: 3))
        let feedback = text(R.id.oneOnOneQuestionFeedback, gravity: AGravity.CENTER, color: argbInt(0xFF46545B),
                            sizeSp: 9.5, bold: true)
        questionContent.addView(feedback, linear(MATCH, WRAP, topDp: 3))
        let actions = ALinearLayout()
        actions.setGravity(AGravity.CENTER)
        actions.orientation = ALinearLayout.HORIZONTAL
        let continueButton = AButton()
        continueButton.viewId = R.id.oneOnOneQuestionContinue
        continueButton.setText(res: R.string.minik_swish_one_on_one_question_continue)
        continueButton.setAllCaps(false)
        continueButton.setTextColor(argbInt(0xFFFFFFFF))
        continueButton.applyXmlTextSize(12)
        bold(continueButton)
        continueButton.visibility = AView.GONE
        continueButton.setBackgroundTintList(AColorStateList.valueOf(argbInt(0xFF087E70)))
        continueButton.cornerRadius = px(13)
        actions.addView(continueButton, linear(px(210), px(38), topDp: 4))
        // TripleShotButton, style Widget.MaterialComponents.Button.TextButton: wrap x 48dp, marginStart 5dp,
        // marginTop 10dp, minHeight/minWidth 0 (default insets), backgroundTint #E91E63.
        let exitButton = TripleShotButton(style: AButton.Style.TEXT)
        exitButton.viewId = R.id.oneOnOneQuestionExit
        minSize(exitButton, widthDp: 0, heightDp: 0)
        exitButton.setText(res: R.string.minik_swish_one_on_one_question_exit)
        exitButton.setAllCaps(false)
        exitButton.setTextColor(argbInt(0xFFFFFFFF))
        exitButton.applyXmlTextSize(17)
        exitButton.setBackgroundTintList(AColorStateList.valueOf(argbInt(0xFFE91E63)))
        let exitParams = linear(WRAP, px(48), topDp: 10)
        exitParams.marginStart = px(5)
        actions.addView(exitButton, exitParams)
        questionContent.addView(actions, linear(MATCH, WRAP))
        questionCard.addView(questionContent, AFrameLayout.LayoutParams(MATCH, WRAP))
        root.addView(questionCard, constrained(px(560), WRAP, top: true, bottom: true, start: true, end: true))

        // Kept as compatibility ids; gameplay is gesture driven: a 1dp x 1dp invisible card at bottom-start with
        // four 1dp gone MaterialButtons.
        let controls = ACardView()
        controls.viewId = R.id.oneOnOneControls
        controls.visibility = AView.INVISIBLE
        let controlsRow = ALinearLayout()
        controlsRow.orientation = ALinearLayout.HORIZONTAL
        for id in [R.id.oneOnOneShootButton, R.id.oneOnOneFakeButton, R.id.oneOnOneBlockButton, R.id.oneOnOneJumpButton] {
            let button = AButton()
            button.viewId = id
            button.visibility = AView.GONE
            controlsRow.addView(button, linear(px(1), px(1)))
        }
        controls.addView(controlsRow, AFrameLayout.LayoutParams(px(1), px(1)))
        root.addView(controls, constrained(px(1), px(1), bottom: true, start: true))

        iosExitControl(root, landscape: true)

        // oneOnOneResultOverlay: the card is 520dp x wrap, layout_gravity center, #FFFDF8, radius 22,
        // elevation 12; padding 16dp, gravity center.
        let resultCard = card(nil, background: argbInt(0xFFFFFDF8), radiusDp: 22, elevationDp: 12,
                              strokeColor: nil, strokeWidthDp: 0)
        let resultContent = column(horizontalPaddingDp: 16, verticalPaddingDp: 16)
        resultContent.setGravity(AGravity.CENTER)
        let resultTitle = text(R.id.oneOnOneResultTitle, gravity: AGravity.CENTER, color: argbInt(0xFF142129),
                               sizeSp: 22, bold: true)
        resultContent.addView(resultTitle, linear(MATCH, WRAP))
        let resultScore = text(R.id.oneOnOneResultScore, gravity: AGravity.CENTER, color: argbInt(0xFF7042B8),
                               sizeSp: 16, bold: true)
        resultContent.addView(resultScore, linear(MATCH, WRAP, topDp: 4))
        let buttons = ALinearLayout()
        buttons.orientation = ALinearLayout.HORIZONTAL
        let home = AButton(style: AButton.Style.OUTLINED)
        home.viewId = R.id.oneOnOneHomeButton
        home.setText(res: R.string.minik_swish_one_on_one_home)
        home.setAllCaps(false)
        home.cornerRadius = px(14)
        let homeParams = linear(0, px(42), weight: 1)
        homeParams.marginEnd = px(5)
        buttons.addView(home, homeParams)
        let again = AButton()
        again.viewId = R.id.oneOnOneAgainButton
        again.setText(res: R.string.minik_swish_one_on_one_again)
        again.setAllCaps(false)
        again.setBackgroundTintList(AColorStateList.valueOf(argbInt(0xFF087E70)))
        again.cornerRadius = px(14)
        let againParams = linear(0, px(42), weight: 1)
        againParams.marginStart = px(5)
        buttons.addView(again, againParams)
        resultContent.addView(buttons, linear(MATCH, WRAP, topDp: 10))
        resultCard.addView(resultContent, AFrameLayout.LayoutParams(MATCH, WRAP))
        let resultCardParams = AFrameLayout.LayoutParams(px(520), WRAP, AGravity.CENTER)
        root.addView(resultOverlay(card: resultCard, cardParams: resultCardParams), fillParent())

        return root
    }

    /// One landscape answer row: two MaterialButtons (OutlinedButton), width 0 weight 1, wrap height,
    /// marginEnd 3dp / marginStart 3dp, minHeight 38dp, textAllCaps false, #142129, textDirection locale, 12sp,
    /// cornerRadius 12dp, strokeColor #80087E70.
    static func landscapeAnswerRow(_ firstId: String, _ secondId: String) -> ALinearLayout {
        let row = ALinearLayout()
        row.orientation = ALinearLayout.HORIZONTAL
        for (index, answerId) in [firstId, secondId].enumerated() {
            let answer = AButton(style: AButton.Style.OUTLINED)
            answer.viewId = answerId
            minSize(answer, widthDp: nil, heightDp: 38)
            answer.setAllCaps(false)
            answer.setTextColor(argbInt(0xFF142129))
            answer.textDirection = AView.TEXT_DIRECTION_LOCALE
            answer.applyXmlTextSize(12)
            answer.cornerRadius = px(12)
            answer.strokeColor = AColorStateList.valueOf(argbInt(0x80087E70))
            let lp = linear(0, WRAP, weight: 1)
            if index == 0 { lp.marginEnd = px(3) } else { lp.marginStart = px(3) }
            row.addView(answer, lp)
        }
        return row
    }
}

/// The layout root of both variants: Android's <ConstraintLayout> plus one iOS-only rule. The iOS exit control yields
/// to the question card and the result overlay (each carries its own exit button: "Exit game" / "Home"), so the screen
/// looks like Android's while one of them is up (the translucent card and the dim scrim would otherwise show it
/// through). Their GONE <-> VISIBLE changes always request a layout, so the rule runs at the start of onLayout.
final class TripleShotOneOnOneRootLayout: AConstraintLayout {
    override func onLayout(_ changed: Bool, _ left: Int, _ top: Int, _ right: Int, _ bottom: Int) {
        syncIosExitControl()
        super.onLayout(changed, left, top, right, bottom)
    }

    func syncIosExitControl() {
        guard let control: AView = findViewById(TripleShotOneOnOneLayouts.IOS_EXIT_CONTROL_ID) else { return }
        let question: AView? = findViewById(R.id.oneOnOneQuestionCard)
        let overlay: AView? = findViewById(R.id.oneOnOneResultOverlay)
        let covered = question?.visibility == AView.VISIBLE || overlay?.visibility == AView.VISIBLE
        let wanted = covered ? AView.INVISIBLE : AView.VISIBLE
        if control.visibility != wanted { control.visibility = wanted }
    }
}
