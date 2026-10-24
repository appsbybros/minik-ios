import Foundation

// Port of `ui/TripleShotTeamMatchFragment.kt` (Android 6c38131), statement by statement (spec 17-teamfrag).
//
// The whole view tree is built in code exactly as the Kotlin builds it (no XML), so the global restylers that the
// activity installs (FamilySkyUi.watch, FamilyFormStyle, FamilyButtonAlignment, TripleShotControls.watch) produce the
// same effective look as on the Android device (sky faces with 18 dp corners, lettering rule of TripleShotButton).
//
// Kept as on Android (spec 17 section 8): the review never auto-advances; the 720 ms dead-ball timer is not
// pause-aware; the tools come back over the result after a winning basket (8.5); the stale status after "Play again"
// (8.9); the league score loses its second line after a rotation (8.3); the result card width is computed once in
// buildUi (8.10); the shot clock text persists between possessions (8.4); questions have no timeout and `elapsed` may
// be negative after a pause (8.11).
//
// Not ported: the debug-only QA isolation (`BuildConfig.DEBUG && intent.qaIsolatedProgress`, DESIGN 3: production
// always records answers). The dead views (tactical tip, possession text, status exit link, footer spacers) are kept
// because live code toggles them; they are GONE/never attached and take no space, exactly as on Android.
//
// Saved instance state (onSaveInstanceState / restoreUiAfterRecreation / restoreQuestionAfterRecreation) is ported,
// but on iOS it never runs: AndroidKit never recreates a fragment and always passes a nil savedInstanceState.
//
// iOS-only control (DESIGN 12.3, spec 17 section 10.1 option (a)): Android pauses or leaves through the system Back key
// (`ended ? leaveToHome() : pauseOrHelp(false)`) whenever the Exit/Pause/Help tools are hidden (the intro, and every
// live possession 2.5 s after it started). iOS has no Back key, so while the tools are hidden a tap in the tools'
// corner (the tools strip extended to the top and end edges) re-shows them for 2.5 s (`showBreakTools()`), instead of
// reaching the court. The Kotlin OnBackPressedCallback is kept unchanged.
//
// iOS-only timing guard (AndroidKit): Android updates resources.displayMetrics before onConfigurationChanged, so during
// a rotation applyOrientationLayout (questionLaneWidth, the hint card width, the intro card size) reads the new
// window's size. AndroidKit delivers the change from viewWillTransition(to:), before UIKit resizes the window, while its
// displayMetrics read the live window. When they still disagree with the new configuration, onDeviceOrientationChanged
// runs applyOrientationLayout once more after the resize (iosReapplyOrientationLayoutAfterResize); when the metrics are
// already current nothing is added.

/** Local 2v2 / 3v3 with bots. 1v1 stays on the mature OneOnOneFragment. */
final class TripleShotTeamMatchFragment: AFragment {

    private let handler = AHandler(ALooper.getMainLooper())
    private lazy var firebase = TripleShotFirebaseRepository()

    private var rootLayout: AFrameLayout!
    private var court: TripleShotTeamCourtView!
    private var hudCard: ACardView!
    private var scoreText: ATextView!
    private var possessionText: ATextView!
    private var statusText: ATextView!
    private var statusExitLink: ATextView!
    private var shotCard: ACardView!
    private var shotPercent: ATextView!
    private var shotBar: AProgressBar!
    private var questionCard: ACardView!
    private var questionScroll: AScrollView!
    private var questionTitleText: ATextView!
    private var questionPrompt: ATextView!
    private var questionFeedback: ATextView!
    private var questionHintCard: ACardView!
    private var questionFooterRow: ALinearLayout!
    private var questionFooterTopSpacer: AView!
    private var questionFooterBottomSpacer: AView!
    private var questionAnswers: ALinearLayout!
    private var resultOverlay: AFrameLayout!
    private var resultTitle: ATextView!
    private var introOverlay: AFrameLayout!
    private var introCard: ACardView!
    private var introRoleText: ATextView!
    private var introOrientationText: ATextView!
    private var introGuardText: ATextView!
    private var tacticalTipCard: ACardView!
    private var tacticalTipText: ATextView!
    private var exitButton: AButton!
    private var tacticalTipHideRunnable: ARunnable? = nil

    private var config: TripleShotGameConfig? = nil
    /// Kotlin `List<TripleShotQuestion>`: the repository's lazy 4096-entry adaptive list, or the empty list.
    private var questions: AdaptiveQuestionList = AdaptiveQuestionList.emptyList()
    private var questionIndex = 0
    private var questionShownAt: Int64 = 0
    private var pendingRace: [RaceAttempt] = []
    private var questionLocked = false
    private var reviewWinner: TripleShotTeamCourtView.Team? = nil
    private var reviewChoice = -1
    /// Kotlin `reviewFeedbackRes = 0` (a string resource id; `""` = none, AStringRes is String-backed, DESIGN 2.7).
    private var reviewFeedbackRes: AStringRes = ""
    private var restoringCourt = false
    private let trumpetCadence = TrumpetCadence()
    private func trumpetEvent(event: TrumpetCadence.Event) {
        if ended || !isResumed || restoringCourt { return }
        let due = trumpetCadence.event(event: event, liveMillis: liveMillis)
        ALog.i("TRIPLE_TRUMPET", "event=\(event.name) total=\(trumpetCadence.total) count=\(trumpetCadence.count)/\(trumpetCadence.target) played=\(trumpetCadence.played) live=\(liveMillis)")
        if due && BasketballSoundscape.trumpet(activity: requireActivity(), reason: "highlight") {
            trumpetCadence.acknowledge(liveMillis: liveMillis)
        }
    }
    private var humanScore = 0
    private var opponentScore = 0
    private var ended = false
    private var liveMillis: Int64 = 0
    private var controlsPaused = false
    private var matchDuration: Int {
        if let it = config { return !it.leagueSeasonId.isEmpty ? it.timeLimitSeconds : 0 }
        return 0
    }
    private var breakTools: ALinearLayout!
    private lazy var hideTools: ARunnable = ARunnable { [weak self] in
        guard let self = self else { return }
        if self.breakTools != nil {
            self.breakTools.animate().alpha(0).setDuration(300).withEndAction { [weak self] in
                self?.breakTools.visibility = AView.INVISIBLE
            }.start()
        }
    }
    private func showBreakTools(persistent: Bool = false) {
        if breakTools == nil { return }
        handler.removeCallbacks(hideTools); breakTools.animate().cancel()
        breakTools.visibility = AView.VISIBLE; breakTools.alpha = 1; breakTools.bringToFront()
        if !persistent { handler.postDelayed(hideTools, 2500) }
    }
    private var clockText: ATextView!
    private var possessionSerial: Int64 = 0
    private var questionsEnabled = false
    private var lastSystemTopInset = 0
    private var lastSystemBottomInset = 0
    private var restoredInstanceState: ABundle? = nil
    private var activeQuestionPosition = -1
    private var pendingQuestionDefaultTeam: TripleShotTeamCourtView.Team? = nil
    private var pendingBaselineRestart = false
    private var pendingDeadBallTeam: TripleShotTeamCourtView.Team? = nil

    private enum StatusTone: String, KotlinEnum { case HUMAN, OPPONENT, NEUTRAL }

    private struct StatusNotice {
        let text: ACharSequence
        let tone: StatusTone
    }

    /// Kotlin `ArrayDeque<StatusNotice>` (addLast / removeFirst / isEmpty).
    private var statusQueue: [StatusNotice] = []
    private var currentStatusNotice: StatusNotice? = nil
    private var statusShownAt: Int64 = 0
    private var statusAdvanceRunnable: ARunnable? = nil
    private var statusHideRunnable: ARunnable? = nil
    private var lastPossessionTeam: TripleShotTeamCourtView.Team? = nil

    /// Kotlin `private data class RaceAttempt` (internal here so the parity tests can check `buildRace`).
    struct RaceAttempt: Hashable {
        var actorId: String
        var team: TripleShotTeamCourtView.Team
        var delayMs: Int64
        var correct: Bool

        init(actorId: String, team: TripleShotTeamCourtView.Team, delayMs: Int64, correct: Bool) {
            self.actorId = actorId
            self.team = team
            self.delayMs = delayMs
            self.correct = correct
        }
    }

    // MARK: - Lifecycle (TM:136-302)

    override func onCreate(_ savedInstanceState: ABundle?) {
        super.onCreate(savedInstanceState)
        restoredInstanceState = savedInstanceState

        TripleShotQuestionRepository.initialize(context: requireContext())

        let a = requireArguments()
        // `getStringArrayList(...).orEmpty().mapNotNull { runCatching { QuestionCategory.valueOf(it) }.getOrNull() }.toSet()`
        let categories = KLinkedSet((a.getStringArrayList(Self.ARG_CATEGORIES) ?? []).compactMap { QuestionCategory.named($0) })
        config = TripleShotGameConfig(
            playerName: a.getString(Self.ARG_NAME) ?? "",
            gameType: GameType.TEAM_MATCH,
            selectedCategories: categories,
            botMatch: true,
            playerCharacterId: a.getString(Self.ARG_PLAYER_ID) ?? TripleShotCharacterRoster.ID_WOMAN_DARK,
            botCharacterId: a.getString(Self.ARG_PRIMARY_OPPONENT) ?? TripleShotCharacterRoster.ID_WOMAN_DARK,
            teamSize: a.getInt(Self.ARG_TEAM_SIZE, 2).coerceIn(2, 3),
            teammateCharacterIds: a.getStringArrayList(Self.ARG_TEAMMATES) ?? [],
            opponentCharacterIds: a.getStringArrayList(Self.ARG_OPPONENTS) ?? [],
            // `runCatching { valueOf(arg.orEmpty()) }.getOrDefault(PORTRAIT)`
            gameOrientation: TripleShotGameOrientation.named(a.getString(Self.ARG_GAME_ORIENTATION) ?? "")
                ?? TripleShotGameOrientation.PORTRAIT,
            courtId: a.getString(Self.ARG_COURT_ID) ?? TripleShotCourtCatalog.DEFAULT_ID,
            seed: a.getLong(Self.ARG_SEED, ASystem.currentTimeMillis()),
            timeLimitSeconds: a.getInt("match_seconds", 0),
            leagueSeasonId: a.getString("league_season", ""),
            leagueFixtureKey: a.getString("league_fixture", ""),
            teamName: a.getString("league_team_name", ""),
            opponentTeamName: a.getString("league_opponent_name", ""),
            teamColor: a.getInt("league_team_color", argbInt(0xff76d8ff)),
            opponentTeamColor: a.getInt("league_opponent_color", argbInt(0xffffb779))
        )
        let c = config!
        questionsEnabled = !c.selectedCategories.isEmpty
        questions =
            questionsEnabled
                ? TripleShotQuestionRepository.shuffled(
                    seed: c.seed ^ 0x5445414D,
                    categories: c.selectedCategories
                )
                : AdaptiveQuestionList.emptyList()
        if let state = savedInstanceState {
            humanScore = state.getInt(Self.STATE_HUMAN_SCORE, 0)
            opponentScore = state.getInt(Self.STATE_OPPONENT_SCORE, 0)
            ended = state.getBoolean(Self.STATE_ENDED, false)
            questionIndex = state.getInt(Self.STATE_QUESTION_INDEX, 0)
            possessionSerial = state.getLong(Self.STATE_POSSESSION_SERIAL, 0)
            activeQuestionPosition = state.getInt(Self.STATE_ACTIVE_QUESTION_POSITION, -1)
            pendingQuestionDefaultTeam = state.getString(Self.STATE_PENDING_QUESTION_TEAM).flatMap {
                TripleShotTeamCourtView.Team.named($0)
            }
            pendingBaselineRestart = state.getBoolean(Self.STATE_PENDING_BASELINE_RESTART, false)
            pendingDeadBallTeam = state.getString(Self.STATE_PENDING_DEAD_BALL_TEAM).flatMap {
                TripleShotTeamCourtView.Team.named($0)
            }
        }
    }

    override func onCreateView(
        _ inflater: ALayoutInflater,
        _ container: AViewGroup?,
        _ savedInstanceState: ABundle?
    ) -> AView? {
        return buildUi()
    }

    override func onViewCreated(_ view: AView, _ savedInstanceState: ABundle?) {
        super.onViewCreated(view, savedInstanceState)
        configureTeamEdgeToEdge()
        let c = config!
        court.setCourtStyle(style: TripleShotCourtCatalog.find(id: c.courtId))
        court.configure(
            teamSize: c.teamSize,
            humanCharacterId: c.playerCharacterId,
            teammateCharacterIds: c.teammateCharacterIds,
            opponentCharacterIds: c.opponentCharacterIds,
            seed: c.seed
        )
        if !c.leagueSeasonId.isEmpty { court.setLeagueLabels(ownColor: c.teamColor, rivalColor: c.opponentTeamColor) }
        // Kotlin `object : TripleShotTeamCourtView.Listener { ... }`: this fragment conforms (extension below).
        court.setListener(listener: self)

        requireActivity().onBackPressedDispatcher.addCallback(
            viewLifecycleOwner,
            AOnBackPressedCallback(true) { [weak self] _ in
                guard let self = self else { return }
                if self.ended { self.leaveToHome() } else { self.pauseOrHelp(help: false) }
            }
        )

        updateScore()
        let saved = restoredInstanceState
        liveMillis = saved?.getLong("liveMillis", 0) ?? 0
        trumpetCadence.restore(s: saved?.getLongArray("trumpetCadence"))
        let restoredCourt =
            saved?.getBundle(Self.STATE_COURT_RUNTIME).map { state -> Bool in
                restoringCourt = true
                defer { restoringCourt = false }
                return court.restoreRuntimeState(state: state)
            } == true
        if let saved = saved, restoredCourt {
            restoreUiAfterRecreation(state: saved)
        } else {
            showTeamIntro()
        }
        restoredInstanceState = nil
    }

    override func onSaveInstanceState(_ outState: ABundle) {
        super.onSaveInstanceState(outState)
        outState.putLongArray("trumpetCadence", trumpetCadence.snapshot())
        outState.putLong("liveMillis", liveMillis)
        outState.putString("answerReviewWinner", reviewWinner?.name)
        outState.putInt("answerReviewChoice", reviewChoice)
        // Kotlin putInt(resource id): the String-backed AStringRes is stored under the same key.
        outState.putString("answerReviewFeedback", reviewFeedbackRes)
        outState.putInt(Self.STATE_HUMAN_SCORE, humanScore)
        outState.putInt(Self.STATE_OPPONENT_SCORE, opponentScore)
        outState.putBoolean(Self.STATE_ENDED, ended)
        outState.putInt(Self.STATE_QUESTION_INDEX, questionIndex)
        outState.putLong(Self.STATE_POSSESSION_SERIAL, possessionSerial)
        outState.putInt(Self.STATE_ACTIVE_QUESTION_POSITION, activeQuestionPosition)
        outState.putString(Self.STATE_PENDING_QUESTION_TEAM, pendingQuestionDefaultTeam?.name)
        outState.putBoolean(Self.STATE_PENDING_BASELINE_RESTART, pendingBaselineRestart)
        outState.putString(Self.STATE_PENDING_DEAD_BALL_TEAM, pendingDeadBallTeam?.name)
        outState.putBoolean(
            Self.STATE_INTRO_VISIBLE,
            introOverlay != nil && introOverlay.visibility == AView.VISIBLE
        )
        outState.putBoolean(
            Self.STATE_QUESTION_VISIBLE,
            questionCard != nil && questionCard.visibility == AView.VISIBLE
        )
        outState.putBoolean(
            Self.STATE_RESULT_VISIBLE,
            resultOverlay != nil && resultOverlay.visibility == AView.VISIBLE
        )
        if court != nil {
            outState.putBundle(Self.STATE_COURT_RUNTIME, court.saveRuntimeState())
        }
    }

    override func onDestroyView() {
        if court != nil { court.setListener(listener: nil) }
        if let r = tacticalTipHideRunnable { handler.removeCallbacks(r) }
        tacticalTipHideRunnable = nil
        handler.removeCallbacksAndMessages(nil)
        restoreSystemBars()
        super.onDestroyView()
    }

    // MARK: - Restore after recreation (TM:345-444; never reached on iOS, see the file header)

    private func restoreUiAfterRecreation(state: ABundle) {
        introOverlay.visibility = AView.GONE
        resultOverlay.visibility = AView.GONE
        shotCard.visibility = AView.GONE
        tacticalTipCard.visibility = AView.GONE
        questionCard.visibility = AView.GONE
        questionHintCard.visibility = AView.GONE
        questionFooterRow.visibility = AView.GONE

        if ended || state.getBoolean(Self.STATE_RESULT_VISIBLE, false) {
            hudCard.visibility = AView.GONE
            resultTitle.setText(
                res: humanScore > opponentScore ? R.string.minik_swish_team_you_win
                    : R.string.minik_swish_team_you_lose
            )
            handler.removeCallbacks(hideTools); breakTools.visibility = AView.INVISIBLE
            resultOverlay.visibility = AView.VISIBLE
        } else if state.getBoolean(Self.STATE_QUESTION_VISIBLE, false) &&
            questionsEnabled &&
            questions.indices.contains(activeQuestionPosition) {
            restoreQuestionAfterRecreation(position: activeQuestionPosition)
            if let winner = state.getString("answerReviewWinner") {
                reviewWinner = TripleShotTeamCourtView.Team.named(winner)!
                reviewChoice = state.getInt("answerReviewChoice", -1)
                reviewFeedbackRes = state.getString("answerReviewFeedback") ?? R.string.minik_swish_team_question_wrong
                showAnswerReview(q: questions[activeQuestionPosition])
            }
        } else if state.getBoolean(Self.STATE_INTRO_VISIBLE, false) {
            showTeamIntro()
        } else if pendingDeadBallTeam != nil {
            // Handler callbacks belong to the old view. Recreate the saved transition,
            // without scoring the basket again or resetting the live season.
            let next = pendingDeadBallTeam!
            pendingDeadBallTeam = nil
            beginPossessionFlow(defaultTeam: next, restartFromOwnBaseline: pendingBaselineRestart)
        } else {
            // A live possession survives rotation as-is. Do not call startPossession() or show
            // the intro again; the court snapshot already owns ball, actors and camera.
            hudCard.visibility = AView.VISIBLE
            questionFooterRow.visibility = AView.GONE
            questionHintCard.visibility = AView.GONE
            exitButton.visibility = AView.GONE
        }
        rootLayout.post { [weak self] in self?.positionQuestionFooter() }
    }

    private func restoreQuestionAfterRecreation(position: Int) {
        guard let q = questions.getOrNull(position) else { return }
        hudCard.visibility = AView.VISIBLE
        showBreakTools(persistent: true)
        questionCard.visibility = AView.VISIBLE
        questionFooterRow.visibility = AView.VISIBLE
        questionHintCard.visibility = AView.VISIBLE
        exitButton.visibility = AView.GONE
        questionLocked = false
        reviewWinner = nil; reviewChoice = -1; reviewFeedbackRes = ""
        questionPrompt.text = q.prompt
        questionFeedback.setText(res: R.string.minik_swish_team_question_hint)
        questionScroll.scrollTo(0, 0)
        questionAnswers.removeAllViews()
        questionShownAt = ASystemClock.elapsedRealtime()

        let defaultTeam = pendingQuestionDefaultTeam ?? TripleShotTeamCourtView.Team.HUMAN
        pendingRace = buildRace(q: q, defaultTeam: defaultTeam, serial: possessionSerial)

        for (index, answer) in q.answers.enumerated() {
            let button = TripleShotButton()
            button.text = answer.text
            button.isAllCaps = false
            button.textSize =
                resources.configuration.orientation == AConfiguration.ORIENTATION_LANDSCAPE ? 13 : 14
            button.minHeight = dp(v: 42)
            button.cornerRadius = dp(v: 14)
            button.backgroundTintList = AColorStateList.valueOf(AColor.parseColor("#F9FFFFFF"))
            button.setTextColor(AColor.parseColor("#172B33"))
            button.strokeColor = AColorStateList.valueOf(AColor.parseColor("#774FA99C"))
            button.strokeWidth = dp(v: 1)
            button.setOnClickListener { [weak self] _ in self?.submitAnswer(q: q, index: index) }
            let lp = ALinearLayout.LayoutParams(
                AViewGroup.LayoutParams.MATCH_PARENT,
                AViewGroup.LayoutParams.WRAP_CONTENT
            )
            lp.topMargin = dp(v: index == 0 ? 4 : 5)
            questionAnswers.addView(button, lp)
        }
        rootLayout.post { [weak self] in self?.positionQuestionFooter() }
    }

    override func onPause() {
        if court != nil { court.setMatchPaused(paused: true) }
        super.onPause()
    }
    override func onResume() {
        super.onResume()
        if court != nil { court.setMatchPaused(paused: controlsPaused) }
    }
    private func pauseOrHelp(help: Bool) {
        if ended { return }
        controlsPaused = true
        let pauseStarted = ASystemClock.elapsedRealtime()
        court.setMatchPaused(paused: true)
        let dialog = AAlertDialog.AppCompatBuilder(requireContext())
            .setTitle(help ? (isRtlLocale() ? "איך משחקים" : "How to play") : (isRtlLocale() ? "המשחק מושהה" : "Game paused"))
            .setMessage(help ? getString(R.string.minik_swish_team_intro_how_to) : isRtlLocale() ? "המשחק והשעון מחכים לכם." : "The game and clock are waiting for you.")
            .setPositiveButton(isRtlLocale() ? "ממשיכים" : "Resume", nil)
            .setNegativeButton(isRtlLocale() ? "יציאה" : "Exit") { [weak self] _, _ in self?.leaveToHome() }.create()
        dialog.setOnDismissListener { [weak self] _ in
            guard let self = self else { return }
            if self.questionCard.visibility == AView.VISIBLE { self.questionShownAt += ASystemClock.elapsedRealtime() - pauseStarted }
            self.controlsPaused = false; if self.isResumed { self.court.setMatchPaused(paused: false) }
        }
        dialog.show()
    }

    // MARK: - View tree (TM:471-953)

    private func buildUi() -> AView {
        let landscape = resources.configuration.orientation == AConfiguration.ORIENTATION_LANDSCAPE
        // `FrameLayout(context)`; the subclass only adds the iOS-only tools reveal (see the file header).
        let rootView = TeamMatchRootLayout()
        rootView.fragment = self
        rootLayout = rootView
        rootLayout.setBackgroundColor(AColor.BLACK)
        let root: AFrameLayout = rootLayout

        court = TripleShotTeamCourtView()
        root.addView(court, AFrameLayout.LayoutParams(AViewGroup.LayoutParams.MATCH_PARENT, AViewGroup.LayoutParams.MATCH_PARENT))

        let localeGravity = isRtlLocale() ? AGravity.END : AGravity.START
        let statusSideGravity =
            AGravity.BOTTOM | (isRtlLocale() ? AGravity.END : AGravity.START)

        hudCard = ACardView()
        hudCard.radius = Float(dp(v: 18))
        // 20% transparency: readable over the court without becoming a large opaque banner.
        hudCard.setCardBackgroundColor(AColor.parseColor("#CCFFFDF8"))
        hudCard.strokeColor = AColor.parseColor("#334FA99C")
        hudCard.strokeWidth = dp(v: 1)
        hudCard.cardElevation = Float(dp(v: 3))
        hudCard.minimumWidth = dp(v: landscape ? 118 : 145)
        let hudBody = ALinearLayout()
        hudBody.orientation = ALinearLayout.VERTICAL
        hudBody.gravity = localeGravity
        hudBody.setPadding(dp(v: 12), dp(v: 8), dp(v: 12), dp(v: 7))
        hudCard.addView(hudBody)
        scoreText = ATextView()
        scoreText.textSize = 15.5
        scoreText.setTypeface(scoreText.typeface, ATypeface.BOLD)
        scoreText.setTextColor(AColor.parseColor("#172B33"))
        scoreText.gravity = localeGravity
        scoreText.textDirection = AView.TEXT_DIRECTION_LOCALE
        scoreText.maxWidth = dp(v: landscape ? 185 : 215)
        scoreText.maxLines = 2
        hudBody.addView(scoreText, ALinearLayout.LayoutParams(AViewGroup.LayoutParams.WRAP_CONTENT, AViewGroup.LayoutParams.WRAP_CONTENT))

        // Kept only as a compatibility field for older saved-state code. Possession is conveyed by
        // the current status notice instead of a second redundant line.
        possessionText = ATextView()
        possessionText.visibility = AView.GONE
        hudBody.addView(possessionText, ALinearLayout.LayoutParams(1, 1))

        statusText = ATextView()
        statusText.textSize = 11.5
        statusText.setTextColor(AColor.parseColor("#52656C"))
        statusText.gravity = localeGravity
        statusText.maxLines = 3
        statusText.textDirection = AView.TEXT_DIRECTION_LOCALE
        statusText.visibility = AView.GONE
        statusText.maxWidth = dp(v: landscape ? 190 : 215)
        statusText.setPadding(0, dp(v: 3), 0, 0)
        clockText = ATextView()
        clockText.textSize = 15; clockText.setTypeface(clockText.typeface, ATypeface.BOLD); clockText.setTextColor(AColor.parseColor("#173751"))
        clockText.gravity = AGravity.CENTER; clockText.textAlignment = AView.TEXT_ALIGNMENT_CENTER
        clockText.setPadding(0, dp(v: 4), 0, 0); clockText.visibility = AView.GONE; clockText.setTag("shot-clock")
        hudBody.addView(clockText, ALinearLayout.LayoutParams(-1, -2))
        hudBody.addView(statusText, ALinearLayout.LayoutParams(AViewGroup.LayoutParams.WRAP_CONTENT, AViewGroup.LayoutParams.WRAP_CONTENT))

        statusExitLink = ATextView()
        statusExitLink.visibility = AView.GONE
        let tools = ALinearLayout(); tools.gravity = AGravity.CENTER; tools.setTag("game-controls"); breakTools = tools
        for kind in ["close", "pause", "help"] {
            let label: String
            switch kind {
            case "close": label = isRtlLocale() ? "יציאה" : "Exit"
            case "pause": label = isRtlLocale() ? "השהיה" : "Pause"
            default: label = isRtlLocale() ? "עזרה" : "Help"
            }
            let toolButton = TripleShotButton()
            toolButton.layoutParams = ALinearLayout.LayoutParams(dp(v: 48), dp(v: 48))
            toolButton.setTag("team-tool-\(kind)")
            TripleShotControls.icon(button: toolButton, kind: kind, label: label)
            toolButton.setOnClickListener { [weak self] _ in
                guard let self = self else { return }
                if kind == "close" { self.leaveToHome() } else { self.pauseOrHelp(help: kind == "help") }
            }
            tools.addView(toolButton)
        }
        let toolsLp = AFrameLayout.LayoutParams(-2, -2, AGravity.TOP | AGravity.CENTER_HORIZONTAL)
        toolsLp.topMargin = dp(v: 8)
        root.addView(tools, toolsLp)

        let hudLp = AFrameLayout.LayoutParams(
            AViewGroup.LayoutParams.WRAP_CONTENT,
            AViewGroup.LayoutParams.WRAP_CONTENT,
            statusSideGravity
        )
        hudLp.marginStart = dp(v: 10)
        hudLp.marginEnd = dp(v: 10)
        hudLp.bottomMargin = dp(v: 12)
        root.addView(hudCard, hudLp)
        hudCard.addOnLayoutChangeListener(AOnLayoutChangeListener { [weak self] _, _, _, _, _, _, _, _, _ in
            guard let self = self else { return }
            if self.questionCard != nil && self.questionCard.visibility == AView.VISIBLE {
                self.rootLayout.post { [weak self] in self?.positionQuestionFooter() }
            }
        })

        tacticalTipCard = ACardView()
        tacticalTipCard.radius = Float(dp(v: 16))
        tacticalTipCard.setCardBackgroundColor(AColor.parseColor("#F4FFFDF8"))
        tacticalTipCard.strokeColor = AColor.parseColor("#554FA99C")
        tacticalTipCard.strokeWidth = dp(v: 1)
        tacticalTipCard.cardElevation = Float(dp(v: 3))
        tacticalTipCard.alpha = 0
        tacticalTipCard.visibility = AView.GONE
        tacticalTipText = ATextView()
        tacticalTipText.textSize = 11.5
        tacticalTipText.setTypeface(tacticalTipText.typeface, ATypeface.BOLD)
        tacticalTipText.setTextColor(AColor.parseColor("#23434A"))
        tacticalTipText.gravity = AGravity.CENTER
        tacticalTipText.setPadding(dp(v: 12), dp(v: 8), dp(v: 12), dp(v: 8))
        tacticalTipText.maxLines = 3
        tacticalTipText.textDirection = AView.TEXT_DIRECTION_LOCALE
        tacticalTipCard.addView(tacticalTipText)
        let tipLp = AFrameLayout.LayoutParams(
            landscape ? dp(v: 420) : AViewGroup.LayoutParams.MATCH_PARENT,
            AViewGroup.LayoutParams.WRAP_CONTENT,
            AGravity.TOP | AGravity.CENTER_HORIZONTAL
        )
        tipLp.marginStart = dp(v: 24)
        tipLp.marginEnd = dp(v: 24)
        tipLp.topMargin = dp(v: landscape ? 64 : 80)
        root.addView(tacticalTipCard, tipLp)

        shotCard = ACardView()
        shotCard.radius = Float(dp(v: 18))
        shotCard.setCardBackgroundColor(AColor.parseColor("#F5FFFFFF"))
        shotCard.visibility = AView.GONE
        let shotBody = ALinearLayout()
        shotBody.orientation = ALinearLayout.VERTICAL
        shotBody.gravity = AGravity.CENTER
        shotBody.setPadding(dp(v: 14), dp(v: 8), dp(v: 14), dp(v: 8))
        shotCard.addView(shotBody)
        shotPercent = ATextView()
        shotPercent.textSize = 16
        shotPercent.setTypeface(shotPercent.typeface, ATypeface.BOLD)
        shotPercent.setTextColor(AColor.parseColor("#172A32"))
        shotPercent.gravity = AGravity.CENTER
        // `ProgressBar(context, null, android.R.attr.progressBarStyleHorizontal)`
        shotBar = AProgressBar(style: .HORIZONTAL)
        shotBar.max = 100
        shotBar.progressTintList = AColorStateList.valueOf(AColor.parseColor("#0B8B78"))
        shotBar.progressBackgroundTintList = AColorStateList.valueOf(AColor.parseColor("#D9E8E4"))
        shotBody.addView(shotPercent)
        let shotBarLp = ALinearLayout.LayoutParams(dp(v: 180), dp(v: 8))
        shotBarLp.topMargin = dp(v: 4)
        shotBody.addView(shotBar, shotBarLp)
        let shotLp = AFrameLayout.LayoutParams(AViewGroup.LayoutParams.WRAP_CONTENT, AViewGroup.LayoutParams.WRAP_CONTENT, AGravity.TOP | AGravity.CENTER_HORIZONTAL)
        shotLp.topMargin = dp(v: landscape ? 94 : 126)
        root.addView(shotCard, shotLp)

        questionCard = buildQuestionCard()
        let questionLp = AFrameLayout.LayoutParams(
            landscape ? dp(v: 560) : AViewGroup.LayoutParams.MATCH_PARENT,
            AViewGroup.LayoutParams.WRAP_CONTENT,
            AGravity.CENTER
        )
        questionLp.marginStart = dp(v: 14)
        questionLp.marginEnd = dp(v: 14)
        root.addView(questionCard, questionLp)
        // Keep orientation tuning independent. Landscape needs only a small lift; portrait needs
        // more room for the separate bottom helper/exit cards.
        questionCard.translationY = -Float(dp(v: landscape ? 14 : 34))

        questionFooterRow = ALinearLayout()
        questionFooterRow.orientation = ALinearLayout.HORIZONTAL
        questionFooterRow.gravity = AGravity.CENTER
        questionFooterRow.layoutDirection = AView.LAYOUT_DIRECTION_LOCALE
        questionFooterRow.visibility = questionsEnabled ? AView.GONE : AView.VISIBLE

        questionHintCard = ACardView()
        questionHintCard.radius = Float(dp(v: 14))
        questionHintCard.cardElevation = Float(dp(v: 3))
        questionHintCard.setCardBackgroundColor(AColor.parseColor("#D9FFFDF8"))
        questionHintCard.strokeColor = AColor.parseColor("#554FA99C")
        questionHintCard.strokeWidth = dp(v: 1)
        questionHintCard.visibility = AView.GONE
        questionFeedback = ATextView()
        questionFeedback.text = getString(R.string.minik_swish_team_question_hint)
        questionFeedback.textSize = landscape ? 12 : 13.8
        questionFeedback.setTextColor(AColor.parseColor("#52656C"))
        questionFeedback.gravity = AGravity.CENTER
        questionFeedback.maxLines = landscape ? 1 : 2
        questionFeedback.setPadding(dp(v: 12), dp(v: 7), dp(v: 12), dp(v: 7))
        questionHintCard.addView(questionFeedback)

        let continueButton = TripleShotButton()
        continueButton.text = isRtlLocale() ? "ממשיכים" : "Continue"
        continueButton.setTag("answer-continue")
        continueButton.isAllCaps = false
        continueButton.textSize = landscape ? 11.8 : 14.2
        continueButton.minWidth = 0
        continueButton.backgroundTintList = AColorStateList.valueOf(AColor.parseColor("#D9FFFFFF"))
        continueButton.setTextColor(AColor.parseColor("#36515B"))
        continueButton.cornerRadius = dp(v: 14)
        continueButton.setPadding(dp(v: 12), 0, dp(v: 12), 0)
        continueButton.setOnClickListener { [weak self] _ in self?.continueAfterAnswer() }
        continueButton.visibility = questionsEnabled ? AView.GONE : AView.VISIBLE
        exitButton = continueButton

        questionFooterTopSpacer = AView()
        questionFooterTopSpacer.visibility = AView.GONE
        questionFooterBottomSpacer = AView()
        questionFooterBottomSpacer.visibility = AView.GONE

        let hintLp = ALinearLayout.LayoutParams(0, AViewGroup.LayoutParams.WRAP_CONTENT, 1)
        hintLp.marginEnd = dp(v: 8)
        questionFooterRow.addView(questionHintCard, hintLp)
        questionFooterRow.addView(questionFooterTopSpacer)
        let continueLp = ALinearLayout.LayoutParams(AViewGroup.LayoutParams.WRAP_CONTENT, dp(v: landscape ? 38 : 42))
        continueLp.marginStart = dp(v: 8)
        questionFooterRow.addView(exitButton, continueLp)
        questionFooterRow.addView(questionFooterBottomSpacer)
        root.addView(
            questionFooterRow,
            AFrameLayout.LayoutParams(
                AViewGroup.LayoutParams.WRAP_CONTENT,
                AViewGroup.LayoutParams.WRAP_CONTENT,
                AGravity.TOP | AGravity.CENTER_HORIZONTAL
            )
        )

        questionCard.addOnLayoutChangeListener(AOnLayoutChangeListener { [weak self] _, _, _, _, _, _, _, _, _ in
            guard let self = self else { return }
            if self.questionCard.visibility == AView.VISIBLE {
                self.positionQuestionFooter()
            }
        })

        introOverlay = AFrameLayout()
        introOverlay.setBackgroundColor(AColor.parseColor("#99000000"))
        introOverlay.visibility = AView.GONE
        introOverlay.isClickable = true
        introOverlay.isFocusable = true
        introCard = ACardView()
        introCard.radius = Float(dp(v: 24))
        introCard.setCardBackgroundColor(AColor.parseColor("#FFFDF8"))
        introCard.strokeColor = AColor.parseColor("#554FA99C")
        introCard.strokeWidth = dp(v: 1)
        introCard.cardElevation = Float(dp(v: 6))
        let introBody = ALinearLayout()
        introBody.orientation = ALinearLayout.VERTICAL
        introBody.gravity = AGravity.CENTER
        introBody.setPadding(dp(v: 20), dp(v: 20), dp(v: 20), dp(v: 18))
        let introScroll = AScrollView(); introScroll.isFillViewport = false; introScroll.addView(introBody)
        let introShell = ALinearLayout(); introShell.orientation = ALinearLayout.VERTICAL
        introCard.addView(introShell)
        introShell.addView(introScroll, ALinearLayout.LayoutParams(-1, 0, 1))
        let introTitle = ATextView()
        introTitle.text = getString(R.string.minik_swish_team_intro_title)
        introTitle.textSize = 26
        introTitle.setTypeface(introTitle.typeface, ATypeface.BOLD)
        introTitle.setTextColor(AColor.parseColor("#172B33"))
        introTitle.gravity = AGravity.CENTER
        introBody.addView(introTitle)
        introRoleText = ATextView()
        introRoleText.textSize = 19
        introRoleText.setTypeface(introRoleText.typeface, ATypeface.BOLD)
        introRoleText.setTextColor(AColor.parseColor("#0B8B78"))
        introRoleText.gravity = AGravity.CENTER
        introRoleText.setPadding(0, dp(v: 10), 0, 0)
        introRoleText.textDirection = AView.TEXT_DIRECTION_LOCALE
        introBody.addView(introRoleText)
        introGuardText = ATextView()
        introGuardText.textSize = 18
        introGuardText.setTextColor(AColor.parseColor("#5D6870"))
        introGuardText.gravity = AGravity.CENTER
        introGuardText.setPadding(0, dp(v: 5), 0, 0)
        introGuardText.textDirection = AView.TEXT_DIRECTION_LOCALE
        introBody.addView(introGuardText)
        let introHowTo = ATextView()
        introHowTo.text = getString(R.string.minik_swish_team_intro_how_to)
        introHowTo.textSize = 18
        introHowTo.setTextColor(AColor.parseColor("#34484F"))
        introHowTo.gravity = AGravity.CENTER
        introHowTo.setPadding(0, dp(v: 14), 0, 0)
        introHowTo.textDirection = AView.TEXT_DIRECTION_LOCALE
        introHowTo.setLineSpacing(0, 1.08)
        introBody.addView(introHowTo)
        introOrientationText = ATextView()
        introOrientationText.text = getString(R.string.minik_swish_basketball_portrait_tip)
        introOrientationText.textSize = 17
        introOrientationText.setTypeface(introOrientationText.typeface, ATypeface.BOLD)
        introOrientationText.setTextColor(AColor.parseColor("#6A4A86"))
        introOrientationText.gravity = AGravity.CENTER
        introOrientationText.setPadding(dp(v: 8), dp(v: 9), dp(v: 8), 0)
        introOrientationText.visibility = landscape ? AView.GONE : AView.VISIBLE
        introBody.addView(introOrientationText)
        let startButton = TripleShotButton()
        startButton.text = getString(R.string.minik_swish_team_intro_start)
        startButton.isAllCaps = false
        startButton.cornerRadius = dp(v: 16)
        startButton.backgroundTintList = AColorStateList.valueOf(AColor.parseColor("#087E69")); startButton.setTextColor(AColor.WHITE)
        startButton.textSize = 19
        startButton.setOnClickListener { [weak self, weak startButton] _ in
            guard let self = self else { return }
            BasketballSoundscape.scene(activity: self.requireActivity(), value: BasketballSoundscape.Scene.COURT)
            startButton?.isEnabled = false
            BasketballSoundscape.trumpet(activity: self.requireActivity(), reason: "team-start") { [weak self] completed in
                startButton?.isEnabled = true
                guard let self = self else { return }
                if completed && self.isAdded && self.isResumed && self.view != nil {
                    BasketballSoundscape.effect(context: self.requireContext(), kind: BasketballSoundscape.Effect.WHISTLE)
                    self.introOverlay.visibility = AView.GONE
                    self.beginPossessionFlow(defaultTeam: TripleShotTeamCourtView.Team.HUMAN)
                }
            }
        }
        let startLp = ALinearLayout.LayoutParams(AViewGroup.LayoutParams.MATCH_PARENT, dp(v: 56))
        startLp.topMargin = dp(v: 12); startLp.bottomMargin = dp(v: 16); startLp.marginStart = dp(v: 20); startLp.marginEnd = dp(v: 20)
        introShell.addView(startButton, startLp)
        let introCardLp = AFrameLayout.LayoutParams(
            landscape ? dp(v: 520) : AViewGroup.LayoutParams.MATCH_PARENT,
            min(dp(v: 650), resources.displayMetrics.heightPixels - dp(v: 90)),
            AGravity.CENTER
        )
        introCardLp.marginStart = dp(v: 22)
        introCardLp.marginEnd = dp(v: 22)
        introOverlay.addView(introCard, introCardLp)
        root.addView(
            introOverlay,
            AFrameLayout.LayoutParams(
                AViewGroup.LayoutParams.MATCH_PARENT,
                AViewGroup.LayoutParams.MATCH_PARENT
            )
        )

        resultOverlay = AFrameLayout()
        resultOverlay.setBackgroundColor(AColor.parseColor("#AA000000"))
        resultOverlay.visibility = AView.GONE
        let resultCard = ACardView()
        resultCard.radius = Float(dp(v: 24))
        resultCard.setCardBackgroundColor(AColor.parseColor("#FFFDF8"))
        let resultBody = ALinearLayout()
        resultBody.orientation = ALinearLayout.VERTICAL
        resultBody.gravity = AGravity.CENTER
        resultBody.setPadding(dp(v: 22), dp(v: 22), dp(v: 22), dp(v: 22))
        resultCard.addView(resultBody)
        resultTitle = ATextView()
        resultTitle.textSize = 24
        resultTitle.setTypeface(resultTitle.typeface, ATypeface.BOLD)
        resultTitle.setTextColor(AColor.parseColor("#172B33"))
        resultTitle.gravity = AGravity.CENTER
        resultBody.addView(resultTitle)
        let againButton = TripleShotButton()
        if config?.leagueSeasonId.isEmpty == false {
            againButton.text = ["he", "iw"].contains(resources.configuration.locales[0].language) ? "לטבלת הליגה" : "League table"
        } else {
            againButton.text = getString(R.string.minik_swish_team_play_again)
        }
        againButton.isAllCaps = false
        againButton.cornerRadius = dp(v: 16)
        againButton.minWidth = dp(v: 168)
        againButton.setPadding(dp(v: 24), 0, dp(v: 24), 0)
        againButton.setOnClickListener { [weak self] _ in self?.restart() }
        let againLp = ALinearLayout.LayoutParams(AViewGroup.LayoutParams.WRAP_CONTENT, dp(v: 48))
        againLp.gravity = AGravity.CENTER_HORIZONTAL
        againLp.topMargin = dp(v: 18)
        resultBody.addView(againButton, againLp)
        let homeButton = TripleShotButton()
        homeButton.text = getString(R.string.minik_swish_team_home)
        homeButton.backgroundTintList = AColorStateList.valueOf(AColor.parseColor("#E91E63")); homeButton.setTextColor(AColor.WHITE)
        homeButton.isAllCaps = false
        homeButton.cornerRadius = dp(v: 16)
        homeButton.minWidth = dp(v: 168)
        homeButton.setPadding(dp(v: 24), 0, dp(v: 24), 0)
        homeButton.setOnClickListener { [weak self] _ in
            guard let self = self else { return }
            if self.persistLeagueResult() { (self.parentFragment as? TripleShotHostFragment)?.backToHome() }
        }
        let homeLp = ALinearLayout.LayoutParams(AViewGroup.LayoutParams.WRAP_CONTENT, dp(v: 48))
        homeLp.gravity = AGravity.CENTER_HORIZONTAL
        homeLp.topMargin = dp(v: 8)
        resultBody.addView(homeButton, homeLp)
        let resultCardLp = AFrameLayout.LayoutParams(
            min(dp(v: landscape ? 500 : 340), resources.displayMetrics.widthPixels - dp(v: landscape ? 40 : 72)),
            AViewGroup.LayoutParams.WRAP_CONTENT,
            AGravity.CENTER
        )
        resultCardLp.marginStart = dp(v: 28); resultCardLp.marginEnd = dp(v: 28)
        resultOverlay.addView(resultCard, resultCardLp)
        root.addView(resultOverlay, AFrameLayout.LayoutParams(AViewGroup.LayoutParams.MATCH_PARENT, AViewGroup.LayoutParams.MATCH_PARENT))

        // Edge-to-edge: the COURT paints behind Android system bars, while readable controls keep
        // safe insets. Values are resolved from the CURRENT orientation so a live rotation does not
        // reuse stale portrait/landscape margins.
        AViewCompat.setOnApplyWindowInsetsListener(root) { [weak self] _, insets in
            guard let self = self else { return insets }
            let bars = insets.getInsets(AWindowInsetsCompat.systemBars())
            let nowLandscape = self.resources.configuration.orientation == AConfiguration.ORIENTATION_LANDSCAPE
            let tipBaseTop = self.dp(v: nowLandscape ? 64 : 80)
            let shotBaseTop = self.dp(v: nowLandscape ? 94 : 126)
            self.lastSystemTopInset = bars.top
            self.lastSystemBottomInset = bars.bottom
            let toolsParams = self.breakTools.layoutParams as! AFrameLayout.LayoutParams
            toolsParams.topMargin = bars.top + self.dp(v: 8)
            toolsParams.marginEnd = max(bars.left, bars.right) + self.dp(v: 8)
            self.breakTools.layoutParams = toolsParams
            if nowLandscape && self.questionCard != nil {
                if let lp = self.questionCard.layoutParams as? AFrameLayout.LayoutParams {
                    lp.topMargin = bars.top + self.dp(v: 20)
                    self.questionCard.layoutParams = lp
                }
            }
            if let lp = self.hudCard.layoutParams as? AFrameLayout.LayoutParams {
                lp.bottomMargin = bars.bottom + self.dp(v: nowLandscape ? 12 : 14)
                self.hudCard.layoutParams = lp
            }
            if let lp = self.tacticalTipCard.layoutParams as? AFrameLayout.LayoutParams {
                lp.topMargin = tipBaseTop + bars.top
                self.tacticalTipCard.layoutParams = lp
            }
            if let lp = self.shotCard.layoutParams as? AFrameLayout.LayoutParams {
                lp.topMargin = shotBaseTop + bars.top
                self.shotCard.layoutParams = lp
            }
            self.rootLayout.post { [weak self] in self?.positionQuestionFooter() }
            return insets
        }
        applyOrientationLayout(landscape: landscape, requestInsets: false)
        AViewCompat.requestApplyInsets(root)

        return root
    }

    private func buildQuestionCard() -> ACardView {
        let card = ACardView()
        card.radius = Float(dp(v: 22))
        card.cardElevation = Float(dp(v: 5))
        card.setCardBackgroundColor(AColor.parseColor("#C8FFFDF8"))
        card.strokeColor = AColor.parseColor("#554FA99C")
        card.strokeWidth = dp(v: 1)
        let body = ALinearLayout()
        body.orientation = ALinearLayout.VERTICAL
        body.setPadding(dp(v: 14), dp(v: 12), dp(v: 14), dp(v: 12))
        // Kotlin `object : ScrollView(context) { override fun onMeasure(...) }`: the height-capped question scroll.
        let scroll = TeamQuestionScrollView()
        scroll.fragment = self
        scroll.isFillViewport = false; scroll.addView(body)
        questionScroll = scroll
        questionScroll.addOnLayoutChangeListener(AOnLayoutChangeListener { [weak self] _, l, t, r, b, ol, ot, or, ob in
            if l != ol || t != ot || r != or || b != ob { self?.revealCorrectAnswer() }
        })
        card.addView(questionScroll)
        questionTitleText = ATextView()
        questionTitleText.text = getString(R.string.minik_swish_team_question_title)
        questionTitleText.textSize = resources.configuration.orientation == AConfiguration.ORIENTATION_LANDSCAPE ? 12 : 13
        questionTitleText.setTypeface(questionTitleText.typeface, ATypeface.BOLD)
        questionTitleText.setTextColor(AColor.parseColor("#7042B8"))
        questionTitleText.gravity = AGravity.CENTER
        body.addView(questionTitleText)
        questionPrompt = ATextView()
        questionPrompt.textSize = resources.configuration.orientation == AConfiguration.ORIENTATION_LANDSCAPE ? 18 : 19
        questionPrompt.setTypeface(questionPrompt.typeface, ATypeface.BOLD)
        questionPrompt.setTextColor(AColor.parseColor("#17272E"))
        questionPrompt.gravity = AGravity.CENTER
        questionPrompt.textDirection = AView.TEXT_DIRECTION_LOCALE
        questionPrompt.setPadding(0, dp(v: 5), 0, dp(v: 4))
        body.addView(questionPrompt)
        questionAnswers = ALinearLayout(); questionAnswers.orientation = ALinearLayout.VERTICAL
        body.addView(questionAnswers)
        return card
    }

    /// The anonymous `ScrollView` of `buildQuestionCard`: every measure pass caps its height at
    /// `max(145 dp, screen - top inset - bottom inset - (landscape 165 : portrait 240) dp)`.
    private final class TeamQuestionScrollView: AScrollView {
        weak var fragment: TripleShotTeamMatchFragment?

        override func onMeasure(_ widthMeasureSpec: Int, _ heightMeasureSpec: Int) {
            guard let f = fragment else {
                super.onMeasure(widthMeasureSpec, heightMeasureSpec)
                return
            }
            // `resources` here is the ScrollView's own (View.getResources()); rootLayout, the insets and dp() are the
            // fragment's.
            let landscape = resources.configuration.orientation == AConfiguration.ORIENTATION_LANDSCAPE
            let screen = f.rootLayout.height > 0 ? f.rootLayout.height : resources.displayMetrics.heightPixels
            let cap = (screen - f.lastSystemTopInset - f.lastSystemBottomInset - f.dp(v: landscape ? 165 : 240)).coerceAtLeast(f.dp(v: 145))
            let limit = min(cap, AMeasureSpec.getSize(heightMeasureSpec))
            super.onMeasure(widthMeasureSpec, AMeasureSpec.makeMeasureSpec(limit, AMeasureSpec.AT_MOST))
        }
    }

    // MARK: - Rotation and per-orientation layout (TM:955-1166)

    /**
     * Reflows the SAME live match when Android rotates the device. TeamCourtView stores all
     * gameplay in source coordinates, so only the overlay geometry needs to change here.
     * No Fragment recreation means score, possession, AI state and the current question survive.
     */
    func onDeviceOrientationChanged(orientation: Int) {
        if !isAdded || rootLayout == nil { return }
        let landscape = orientation == AConfiguration.ORIENTATION_LANDSCAPE
        // iOS-only (see the file header): does the layout below read the previous window's display metrics?
        let iosMetricsLag = iosDisplayMetricsLagConfiguration()
        applyOrientationLayout(landscape: landscape, requestInsets: true)
        configureTeamEdgeToEdge()
        rootLayout.post { [weak self] in
            guard let self = self else { return }
            if self.court != nil {
                self.court.requestLayout()
                self.court.invalidate()
            }
        }
        if iosMetricsLag { iosReapplyOrientationLayoutAfterResize(orientation: orientation, attemptsLeft: 60) }
    }

    /// iOS-only (AndroidKit timing; see the file header). Android updates `resources.displayMetrics` before it calls
    /// onConfigurationChanged. AndroidKit delivers the change from `viewWillTransition(to:)`, before UIKit resizes the
    /// window, and its display metrics read the live window, so they can still describe the previous window while the
    /// configuration already describes the new one. True while the two disagree (the configuration holds whole dp,
    /// hence the 1 dp tolerance).
    private func iosDisplayMetricsLagConfiguration() -> Bool {
        let metrics = resources.displayMetrics
        let configuration = resources.configuration
        let widthDp = Float(metrics.widthPixels) / metrics.density
        let heightDp = Float(metrics.heightPixels) / metrics.density
        return abs(widthDp - Float(configuration.screenWidthDp)) >= 1 || abs(heightDp - Float(configuration.screenHeightDp)) >= 1
    }

    /// iOS-only: runs applyOrientationLayout again once the display metrics describe the new window (checked every
    /// 16 ms, at most `attemptsLeft` more times, then it runs regardless). Every value applyOrientationLayout sets is
    /// absolute, so the second run only replaces the values computed from the previous window's size. A newer change to
    /// another orientation supersedes it (that change applies its own layout).
    private func iosReapplyOrientationLayoutAfterResize(orientation: Int, attemptsLeft: Int) {
        rootLayout.postDelayed({ [weak self] in
            guard let self = self, self.isAdded, self.rootLayout != nil else { return }
            if self.resources.configuration.orientation != orientation { return }
            if self.iosDisplayMetricsLagConfiguration() && attemptsLeft > 0 {
                self.iosReapplyOrientationLayoutAfterResize(orientation: orientation, attemptsLeft: attemptsLeft - 1)
                return
            }
            self.applyOrientationLayout(landscape: orientation == AConfiguration.ORIENTATION_LANDSCAPE, requestInsets: true)
        }, 16)
    }

    /// Positional form (Kotlin `active.onDeviceOrientationChanged(newConfig.orientation)`).
    func onDeviceOrientationChanged(_ orientation: Int) { onDeviceOrientationChanged(orientation: orientation) }

    private func applyOrientationLayout(landscape: Bool, requestInsets: Bool) {
        if rootLayout == nil { return }

        if let lp = hudCard.layoutParams as? AFrameLayout.LayoutParams {
            lp.width = dp(v: landscape ? 205 : 220)
            lp.gravity =
                landscape
                    ? AGravity.BOTTOM | (isRtlLocale() ? AGravity.END : AGravity.START)
                    // Portrait has little useful corner width; center the compact scoreboard as a
                    // single unit instead of leaving the score/link visually stuck to one side.
                    : AGravity.BOTTOM | AGravity.CENTER_HORIZONTAL
            lp.marginStart = dp(v: 10)
            lp.marginEnd = dp(v: 10)
            lp.topMargin = 0
            lp.bottomMargin = lastSystemBottomInset + dp(v: landscape ? 12 : 14)
            hudCard.layoutParams = lp
        }
        let localeGravity = isRtlLocale() ? AGravity.END : AGravity.START
        let portraitHudGravity = landscape ? localeGravity : AGravity.CENTER
        scoreText.gravity = portraitHudGravity
        statusText.gravity = landscape ? localeGravity : AGravity.CENTER
        statusExitLink.gravity = AGravity.CENTER
        hudCard.minimumWidth = dp(v: landscape ? 118 : 145)
        scoreText.maxWidth = dp(v: landscape ? 185 : 215)
        scoreText.maxLines = landscape ? 2 : 1
        statusText.maxWidth = dp(v: landscape ? 190 : 215)
        statusText.maxLines = landscape ? 4 : 3
        if let lp = scoreText.layoutParams as? ALinearLayout.LayoutParams {
            lp.gravity = landscape ? localeGravity : AGravity.CENTER_HORIZONTAL
            scoreText.layoutParams = lp
        }
        if let lp = statusText.layoutParams as? ALinearLayout.LayoutParams {
            lp.gravity = landscape ? localeGravity : AGravity.CENTER_HORIZONTAL
            statusText.layoutParams = lp
        }
        // (statusExitLink is never attached: its layoutParams are null, so Kotlin's `as?` branch is skipped.)
        if let lp = statusExitLink.layoutParams as? ALinearLayout.LayoutParams {
            lp.gravity = AGravity.CENTER_HORIZONTAL
            statusExitLink.layoutParams = lp
        }

        if let lp = tacticalTipCard.layoutParams as? AFrameLayout.LayoutParams {
            lp.width = landscape ? dp(v: 420) : AViewGroup.LayoutParams.MATCH_PARENT
            lp.gravity = AGravity.TOP | AGravity.CENTER_HORIZONTAL
            lp.marginStart = dp(v: 24)
            lp.marginEnd = dp(v: 24)
            tacticalTipCard.layoutParams = lp
        }

        if let lp = shotCard.layoutParams as? AFrameLayout.LayoutParams {
            lp.gravity = AGravity.TOP | AGravity.CENTER_HORIZONTAL
            shotCard.layoutParams = lp
        }

        if let lp = questionCard.layoutParams as? AFrameLayout.LayoutParams {
            lp.width = landscape ? questionLaneWidth() : AViewGroup.LayoutParams.MATCH_PARENT
            lp.gravity = landscape ? AGravity.TOP | AGravity.START : AGravity.CENTER
            lp.marginStart = dp(v: 14)
            lp.marginEnd = dp(v: 14)
            lp.topMargin = landscape ? lastSystemTopInset + dp(v: 17) : 0
            questionCard.layoutParams = lp
        }
        questionCard.translationY = landscape ? 0 : -Float(dp(v: 44))
        questionTitleText.textSize = landscape ? 12 : 13
        questionPrompt.textSize = landscape ? 18 : 19

        configureQuestionFooterForOrientation(landscape: landscape)
        exitButton.textSize = 16
        questionFeedback.textSize = landscape ? 12 : 14.4
        questionFeedback.maxLines = 4
        for i in kuntil(0, questionAnswers.childCount) {
            // Kotlin `as? MaterialButton`
            if let b = questionAnswers.getChildAt(i) as? AButton, b.isMaterialButton { b.textSize = landscape ? 13 : 14 }
        }

        if let lp = introCard.layoutParams as? AFrameLayout.LayoutParams {
            lp.width = min(dp(v: 600), resources.displayMetrics.widthPixels - dp(v: 44))
            lp.height = min(dp(v: 650), resources.displayMetrics.heightPixels - dp(v: 90))
            lp.marginStart = dp(v: 22)
            lp.marginEnd = dp(v: 22)
            lp.gravity = AGravity.CENTER
            introCard.layoutParams = lp
        }
        introOrientationText.visibility = landscape ? AView.GONE : AView.VISIBLE

        if requestInsets { AViewCompat.requestApplyInsets(rootLayout) }
        rootLayout.requestLayout()
        rootLayout.post { [weak self] in self?.positionQuestionFooter() }
    }

    // In landscape, the question and acknowledgement share a lane beside the safe toolbar.
    // In portrait they span the usable width. Continue always stays outside the scroll area.
    private func questionLaneWidth() -> Int {
        return min(dp(v: 540), resources.displayMetrics.widthPixels - dp(v: 220)).coerceAtLeast(dp(v: 280))
    }

    private func configureQuestionFooterForOrientation(landscape: Bool) {
        if questionFooterRow == nil { return }

        // Keep Continue outside the scrolling question; X stays in the safe top toolbar.
        exitButton.visibility = reviewWinner != nil ? AView.VISIBLE : AView.GONE
        questionFooterTopSpacer.visibility = AView.GONE
        questionFooterBottomSpacer.visibility = AView.GONE
        questionFooterRow.orientation = ALinearLayout.HORIZONTAL
        questionFooterRow.gravity = AGravity.CENTER
        questionFooterRow.layoutDirection = isRtlLocale() ? AView.LAYOUT_DIRECTION_RTL : AView.LAYOUT_DIRECTION_LTR

        let rtl = isRtlLocale()
        let localeGravity = rtl ? AGravity.END : AGravity.START
        _ = localeGravity // (unused in Kotlin too)
        questionFeedback.gravity = AGravity.START | AGravity.CENTER_VERTICAL
        questionFeedback.textDirection = rtl ? AView.TEXT_DIRECTION_RTL : AView.TEXT_DIRECTION_LTR
        questionFeedback.textAlignment = AView.TEXT_ALIGNMENT_VIEW_START
        questionHintCard.layoutDirection = rtl ? AView.LAYOUT_DIRECTION_RTL : AView.LAYOUT_DIRECTION_LTR

        if let lp = questionHintCard.layoutParams as? ALinearLayout.LayoutParams {
            let available = landscape ? questionLaneWidth() : resources.displayMetrics.widthPixels - dp(v: 28)
            lp.width = (available - dp(v: reviewWinner != nil ? 120 : 0)).coerceAtLeast(dp(v: 100))
            lp.height = AViewGroup.LayoutParams.WRAP_CONTENT
            lp.weight = 0
            lp.marginEnd = 0
            lp.gravity = AGravity.CENTER_VERTICAL
            questionHintCard.layoutParams = lp
        }
        if let lp = exitButton.layoutParams as? ALinearLayout.LayoutParams {
            lp.width = dp(v: 110)
            lp.height = dp(v: 48)
            lp.weight = 0
            lp.marginStart = dp(v: 10)
            exitButton.layoutParams = lp
        }
    }

    private func positionQuestionFooter() {
        if rootLayout == nil || questionFooterRow == nil { return }
        if questionFooterRow.visibility != AView.VISIBLE { return }
        if !questionsEnabled || questionCard.visibility != AView.VISIBLE {
            questionFooterRow.visibility = AView.GONE
            return
        }

        let landscape =
            resources.configuration.orientation == AConfiguration.ORIENTATION_LANDSCAPE
        guard questionFooterRow.layoutParams is AFrameLayout.LayoutParams else { return }
        let screenBottom = rootLayout.height - lastSystemBottomInset - dp(v: landscape ? 8 : 12)
        let statusTop =
            hudCard.visibility == AView.VISIBLE && hudCard.height > 0 && hudCard.top > 0
                ? hudCard.top - dp(v: 10)
                : screenBottom

        /*
         * Question + hint must form one upper stack and never be covered by the compact status card.
         * Start from the normal orientation-specific lift, then move the WHOLE question upward only
         * when the live status card needs the space.
         */
        let baseTranslation: Float = landscape ? 0 : -Float(dp(v: 44))
        questionCard.translationY = baseTranslation

        questionFooterRow.post { [weak self] in
            guard let self = self else { return }
            let rowHeight = self.questionFooterRow.height.coerceAtLeast(self.dp(v: landscape ? 36 : 44))
            let visualCardBottom = self.questionCard.bottom + self.questionCard.translationY.toInt()
            guard let updated = self.questionFooterRow.layoutParams as? AFrameLayout.LayoutParams else { return }

            if landscape {
                // Landscape has enough horizontal room. Keep the question comfortably below the
                // status bar, put the explanatory line directly below it, and let the compact HUD
                // live independently in the bottom language-side corner. Never shove the question
                // into the device ceiling just because the HUD grew temporarily.
                updated.width = AViewGroup.LayoutParams.WRAP_CONTENT
                updated.height = AViewGroup.LayoutParams.WRAP_CONTENT
                updated.gravity = AGravity.TOP | AGravity.START
                updated.marginStart = self.dp(v: 14)
                updated.marginEnd = self.dp(v: 14)
                updated.bottomMargin = 0
                updated.topMargin = visualCardBottom + self.dp(v: 12)

                // In the rare case of an exceptionally tall question, keep at least a small gap
                // above the HUD. We prefer trimming the footer gap before moving the question up.
                // (A mathematical no-op, as in Kotlin: coerceAtLeast restores the same value.)
                let footerBottom = updated.topMargin + rowHeight
                let maxFooterBottom = statusTop - self.dp(v: 8)
                if footerBottom > maxFooterBottom {
                    updated.topMargin = (maxFooterBottom - rowHeight).coerceAtLeast(visualCardBottom + self.dp(v: 12))
                }
            } else {
                updated.width = AViewGroup.LayoutParams.MATCH_PARENT
                updated.height = AViewGroup.LayoutParams.WRAP_CONTENT
                updated.gravity = AGravity.TOP | AGravity.CENTER_HORIZONTAL
                updated.topMargin = visualCardBottom + self.dp(v: 36)
                updated.bottomMargin = 0
                updated.marginStart = self.dp(v: 14)
                updated.marginEnd = self.dp(v: 14)
            }
            self.questionFooterRow.layoutParams = updated
        }
    }

    // MARK: - Intro and status line (TM:1168-1352)

    private func showTeamIntro() {
        clockText.visibility = AView.GONE
        let guidance = court.humanGuidance()
        introRoleText.text = getString(
            R.string.minik_swish_team_intro_role,
            roleLabel(role: guidance.role)
        )
        let matchup = guidance.matchupName.flatMap { !$0.kotlinIsBlank ? $0 : nil }
        if let matchup = matchup {
            introGuardText.text = getString(
                R.string.minik_swish_team_intro_guard,
                bidiSafeName(raw: matchup)
            )
        } else {
            introGuardText.text = getString(R.string.minik_swish_team_intro_guard_unknown)
        }
        handler.removeCallbacksAndMessages(nil)
        hudCard.visibility = AView.GONE
        tacticalTipCard.visibility = AView.GONE
        introOverlay.visibility = AView.GONE
        questionCard.visibility = AView.GONE
        questionHintCard.visibility = AView.GONE
        if questionsEnabled { exitButton.visibility = AView.GONE }
        questionFooterRow.visibility = AView.GONE
        shotCard.visibility = AView.GONE
        tacticalTipCard.visibility = AView.GONE
        introOverlay.alpha = 1
        introOverlay.visibility = AView.VISIBLE
        introOverlay.bringToFront()
        handler.removeCallbacks(hideTools); breakTools.visibility = AView.INVISIBLE
    }

    private func enqueueGuidanceStatus(guidance: TripleShotTeamCourtView.HumanGuidance) {
        let text: String
        switch guidance.defenseScheme {
        case .ZONE:
            text = getString(R.string.minik_swish_team_tip_zone)
        case .MAN_TO_MAN:
            let matchup = guidance.matchupName.flatMap { !$0.kotlinIsBlank ? $0 : nil }
            if let matchup = matchup {
                text = getString(R.string.minik_swish_team_tip_man, bidiSafeName(raw: matchup))
            } else {
                text = getString(R.string.minik_swish_team_tip_man_generic)
            }
        }
        enqueueStatus(text: text, tone: StatusTone.NEUTRAL)
    }

    private func enqueueBasketStatus(team: TripleShotTeamCourtView.Team) {
        let humanGreen = AColor.parseColor("#0B9E7C")
        let opponentPink = AColor.parseColor("#E91E63")
        let scoredText =
            getString(
                team == TripleShotTeamCourtView.Team.HUMAN
                    ? R.string.minik_swish_team_status_you_scored
                    : R.string.minik_swish_team_status_opponent_scored
            )

        if questionsEnabled {
            enqueueStatus(
                text: scoredText,
                tone: team == TripleShotTeamCourtView.Team.HUMAN ? StatusTone.HUMAN : StatusTone.OPPONENT
            )
            return
        }

        let nextTeam =
            team == TripleShotTeamCourtView.Team.HUMAN
                ? TripleShotTeamCourtView.Team.OPPONENT
                : TripleShotTeamCourtView.Team.HUMAN
        let possessionText =
            getString(
                nextTeam == TripleShotTeamCourtView.Team.HUMAN
                    ? R.string.minik_swish_team_possession_yours
                    : R.string.minik_swish_team_possession_theirs
            )
        let combined = "\(scoredText) \u{2022} \(possessionText)"
        let spannable = ASpannableString(combined)
        let divider = Self.utf16IndexOf(combined, " \u{2022} ")
        let scoredColor = team == TripleShotTeamCourtView.Team.HUMAN ? humanGreen : opponentPink
        let possessionColor = nextTeam == TripleShotTeamCourtView.Team.HUMAN ? humanGreen : opponentPink
        spannable.setSpan(AForegroundColorSpan(scoredColor), 0, divider, ASpanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        spannable.setSpan(
            AForegroundColorSpan(possessionColor),
            divider + 3,
            combined.length,
            ASpanned.SPAN_EXCLUSIVE_EXCLUSIVE
        )
        enqueueStatus(text: spannable, tone: StatusTone.NEUTRAL)
    }

    /// Kotlin `String.indexOf(String)`: the UTF-16 offset of the first occurrence, -1 when absent.
    private static func utf16IndexOf(_ haystack: String, _ needle: String) -> Int {
        let h = Array(haystack.utf16), n = Array(needle.utf16)
        if n.isEmpty { return 0 }
        if n.count > h.count { return -1 }
        for start in krange(0, h.count - n.count) where Array(h[start..<(start + n.count)]) == n { return start }
        return -1
    }

    private func enqueueStatus(text: ACharSequence, tone: StatusTone) {
        if statusText == nil || ended { return }
        let notice = StatusNotice(text: text, tone: tone)
        let now = ASystemClock.elapsedRealtime()
        let current = currentStatusNotice

        guard let shown = current else {
            showStatusNotice(notice: notice)
            return
        }

        // Identical messages do not create a queue echo; they simply refresh the current notice.
        if shown.text.toString() == notice.text.toString() && shown.tone == notice.tone {
            statusShownAt = now
            scheduleStatusHide()
            return
        }

        statusQueue.append(notice)
        let elapsed = now - statusShownAt
        if elapsed >= Self.STATUS_NOTICE_MIN_MS {
            advanceStatusQueue()
        } else {
            if let r = statusAdvanceRunnable { handler.removeCallbacks(r) }
            let runnable = ARunnable { [weak self] in self?.advanceStatusQueue() }
            statusAdvanceRunnable = runnable
            handler.postDelayed(runnable, Self.STATUS_NOTICE_MIN_MS - elapsed)
        }
    }

    private func showStatusNotice(notice: StatusNotice) {
        if let r = statusAdvanceRunnable { handler.removeCallbacks(r) }
        statusAdvanceRunnable = nil
        currentStatusNotice = notice
        statusShownAt = ASystemClock.elapsedRealtime()
        statusText.setTextColor(AColor.parseColor("#52656C"))
        statusText.setText(notice.text)
        statusText.visibility = AView.VISIBLE
        if !(notice.text is ASpannableString) {
            switch notice.tone {
            case .HUMAN: statusText.setTextColor(AColor.parseColor("#0B9E7C"))
            case .OPPONENT: statusText.setTextColor(AColor.parseColor("#E91E63"))
            case .NEUTRAL: statusText.setTextColor(AColor.parseColor("#52656C"))
            }
        }
        scheduleStatusHide()
    }

    private func advanceStatusQueue() {
        if let r = statusAdvanceRunnable { handler.removeCallbacks(r) }
        statusAdvanceRunnable = nil
        let next = statusQueue.isEmpty ? nil : statusQueue.removeFirst()
        if let next = next {
            showStatusNotice(notice: next)
        }
    }

    private func scheduleStatusHide() {
        if let r = statusHideRunnable { handler.removeCallbacks(r) }
        let runnable = ARunnable { [weak self] in
            guard let self = self else { return }
            if !self.statusQueue.isEmpty {
                self.advanceStatusQueue()
            } else {
                self.currentStatusNotice = nil
                self.statusText.visibility = AView.GONE
            }
        }
        statusHideRunnable = runnable
        handler.postDelayed(runnable, Self.STATUS_NOTICE_VISIBLE_MS)
    }

    private func isRtlLocale() -> Bool {
        let language = (AConfigurationCompat.getLocales(resources.configuration)[0] ?? ALocale.getDefault()).language
        return language == "he" || language == "iw" || language == "ar"
    }

    private func roleLabel(role: TripleShotTeamCourtView.TeamRole) -> String {
        let res: AStringRes
        switch role {
        case .POINT_GUARD: res = R.string.minik_swish_team_role_point_guard
        case .WING: res = R.string.minik_swish_team_role_wing
        case .INTERIOR: res = R.string.minik_swish_team_role_interior
        }
        return getString(res)
    }

    private func bidiSafeName(raw: String) -> String {
        let language = (AConfigurationCompat.getLocales(resources.configuration)[0] ?? ALocale.getDefault()).language
        let rtl = language == "he" || language == "iw" || language == "ar"
        // `raw.any { it in 'A'..'Z' || it in 'a'..'z' }` over UTF-16 chars.
        let latin = raw.utf16.contains { ($0 >= 0x41 && $0 <= 0x5A) || ($0 >= 0x61 && $0 <= 0x7A) }
        return rtl && latin ? "\u{2066}\(raw)\u{2069}" : raw
    }

    // MARK: - Possession flow, race and answers (TM:1354-1571)

    private func beginPossessionFlow(
        defaultTeam: TripleShotTeamCourtView.Team,
        restartFromOwnBaseline: Bool = false
    ) {
        if ended { return }
        pendingBaselineRestart = restartFromOwnBaseline
        if !questionsEnabled || questions.isEmpty {
            hudCard.visibility = AView.VISIBLE
            questionCard.visibility = AView.GONE
            questionFooterRow.visibility = AView.GONE
            exitButton.visibility = AView.GONE
            questionHintCard.visibility = AView.GONE
            activeQuestionPosition = -1
            pendingQuestionDefaultTeam = nil
            showBreakTools()
            court.startPossession(team: defaultTeam, restartFromOwnBaseline: pendingBaselineRestart)
            pendingBaselineRestart = false
        } else {
            showPossessionQuestion(defaultTeam: defaultTeam)
        }
    }

    private func showPossessionQuestion(defaultTeam: TripleShotTeamCourtView.Team) {
        if ended { return }
        if !questionsEnabled || questions.isEmpty {
            showBreakTools()
            court.startPossession(team: defaultTeam, restartFromOwnBaseline: pendingBaselineRestart)
            pendingBaselineRestart = false
            return
        }
        court.clearForQuestion()
        hudCard.visibility = AView.VISIBLE
        showBreakTools(persistent: true)
        questionCard.visibility = AView.VISIBLE
        questionFooterRow.visibility = AView.VISIBLE
        questionHintCard.visibility = AView.VISIBLE
        exitButton.visibility = AView.GONE
        questionLocked = false
        reviewWinner = nil; reviewChoice = -1; reviewFeedbackRes = ""
        pendingQuestionDefaultTeam = defaultTeam
        let q = nextQuestion()
        activeQuestionPosition = ((questionIndex - 1) % questions.count + questions.count) % questions.count
        questionPrompt.text = q.prompt
        questionFeedback.setText(res: R.string.minik_swish_team_question_hint)
        questionScroll.scrollTo(0, 0)
        questionAnswers.removeAllViews()
        questionShownAt = ASystemClock.elapsedRealtime()
        possessionSerial += 1
        pendingRace = buildRace(q: q, defaultTeam: defaultTeam, serial: possessionSerial)

        for (index, answer) in q.answers.enumerated() {
            let button = TripleShotButton()
            button.text = answer.text
            button.isAllCaps = false
            button.textSize = resources.configuration.orientation == AConfiguration.ORIENTATION_LANDSCAPE ? 13 : 14
            button.minHeight = dp(v: 42)
            button.cornerRadius = dp(v: 14)
            button.backgroundTintList = AColorStateList.valueOf(AColor.parseColor("#F9FFFFFF"))
            button.setTextColor(AColor.parseColor("#172B33"))
            button.strokeColor = AColorStateList.valueOf(AColor.parseColor("#774FA99C"))
            button.strokeWidth = dp(v: 1)
            button.setOnClickListener { [weak self] _ in self?.submitAnswer(q: q, index: index) }
            let lp = ALinearLayout.LayoutParams(AViewGroup.LayoutParams.MATCH_PARENT, AViewGroup.LayoutParams.WRAP_CONTENT)
            lp.topMargin = dp(v: index == 0 ? 4 : 5)
            questionAnswers.addView(button, lp)
        }
        rootLayout.post { [weak self] in self?.positionQuestionFooter() }
    }

    private func buildRace(
        q: TripleShotQuestion,
        defaultTeam: TripleShotTeamCourtView.Team,
        serial: Int64
    ) -> [RaceAttempt] {
        let c = config!
        let snapshots = court.actorSnapshots()
        return Self.buildRace(seed: c.seed, snapshots: snapshots, q: q, defaultTeam: defaultTeam, serial: serial)
    }

    /// The body of Kotlin `buildRace` with `config.seed` and `court.actorSnapshots()` passed in (pure, so the parity
    /// tests can run the JVM golden vectors of spec 17 section 7.3). Float arithmetic, Java string hashes, one
    /// generator per actor (`nextLong(0, 1700)` then `nextFloat()`), snapshot order, first-minimum fallback appended
    /// at the END: all as Kotlin.
    static func buildRace(
        seed: Int64,
        snapshots: [TripleShotTeamCourtView.ActorSnapshot],
        q: TripleShotQuestion,
        defaultTeam: TripleShotTeamCourtView.Team,
        serial: Int64
    ) -> [RaceAttempt] {
        var result: [RaceAttempt] = []
        for actor in snapshots.filter({ $0.id != "H0" }) {
            let profile = TripleShotCharacterRoster.find(id: actor.characterId) ?? TripleShotCharacterRoster.womanDark
            // `seed xor serial * 811L xor id.hashCode().toLong() xor q.id.hashCode().toLong()` (`*` binds tighter).
            let r = KotlinRandom(seed: seed ^ (serial &* 811) ^ Int64(actor.id.javaHashCode) ^ Int64(q.id.javaHashCode))
            let speed01: Float = profile.quiz.responseSpeed.toFloat() / 100
            let delay = (1500 + ((1 - speed01) * 4300).toLong() + r.nextLong(0, 1700)).coerceIn(1000, 7200)
            let knowledgeChance: Float = (profile.quiz.knowledge.toFloat() - profile.quiz.guessiness.toFloat() * Float(0.22)).coerceIn(20, 96)
            result.append(RaceAttempt(actorId: actor.id, team: actor.team, delayMs: delay, correct: r.nextFloat() * 100 < knowledgeChance))
        }
        if !result.contains(where: { $0.correct }) {
            // A possession question cannot hang forever. The fallback keeps the race hidden but finite.
            let fallback = result.kMinBy { $0.delayMs }
            if let fallback = fallback {
                if let i = result.firstIndex(of: fallback) { result.remove(at: i) }
                var moved = fallback
                moved.correct = true
                moved.delayMs = max(fallback.delayMs, 5200)
                result.append(moved)
            } else {
                let fallbackId = defaultTeam == TripleShotTeamCourtView.Team.HUMAN ? "H1" : "O0"
                result.append(RaceAttempt(actorId: fallbackId, team: defaultTeam, delayMs: 5400, correct: true))
            }
        }
        return result
    }

    private func submitAnswer(q: TripleShotQuestion, index: Int) {
        if questionLocked { return }
        guard let chosen = q.answers.getOrNull(index) else { return }
        questionLocked = true
        let correctValue = q.answers.kMaxOf { $0.qualityPercent }
        let humanCorrect = chosen.qualityPercent == correctValue
        let elapsed = ASystemClock.elapsedRealtime() - questionShownAt
        let botWinner = pendingRace.filter { $0.correct }.kMinBy { $0.delayMs }
        let humanWinsRace = humanCorrect && (botWinner == nil || elapsed < botWinner!.delayMs)
        let winningTeam: TripleShotTeamCourtView.Team =
            humanWinsRace
                ? TripleShotTeamCourtView.Team.HUMAN
                : botWinner?.team ?? TripleShotTeamCourtView.Team.OPPONENT
        let winnerTime = humanWinsRace ? elapsed : botWinner?.delayMs ?? elapsed

        let correctAnswer = q.answers.kMaxBy { $0.qualityPercent }?.text ?? ""

        // (Kotlin skips the next two writes only for the debug QA activity's qaIsolatedProgress extra: production
        // always records, DESIGN 3.)
        TripleShotQuestionRepository.recordAnswer(questionId: q.id, selectedAnswerIndex: index, responseTimeMs: elapsed)

        firebase.recordKnowledgeAnswer(
            playerName: config!.playerName,
            category: q.category,
            correct: humanCorrect,
            questionId: q.id,
            prompt: q.prompt,
            selectedAnswer: chosen.text,
            correctAnswer: correctAnswer,
            qualityPercent: chosen.qualityPercent,
            gameType: GameType.TEAM_MATCH.name
        ) { _ in }

        // Correct answers that did not win the race earn the promised temporary athletic boost.
        if humanCorrect && !humanWinsRace {
            court.setActorBoost(actorId: "H0", boost01: 0.14)
            questionFeedback.setText(res: R.string.minik_swish_team_question_opponent_first)
        } else if humanWinsRace {
            questionFeedback.setText(res: R.string.minik_swish_team_question_correct)
        } else {
            questionFeedback.setText(res: R.string.minik_swish_team_question_wrong)
        }
        for attempt in pendingRace.filter({ $0.correct && $0.delayMs > winnerTime }) {
            court.setActorBoost(actorId: attempt.actorId, boost01: 0.10)
        }
        if !humanWinsRace && botWinner?.team == TripleShotTeamCourtView.Team.HUMAN {
            questionFeedback.setText(res: R.string.minik_swish_team_question_teammate_first)
        }

        reviewWinner = winningTeam
        reviewChoice = index
        if !humanWinsRace && botWinner?.team == TripleShotTeamCourtView.Team.HUMAN {
            reviewFeedbackRes = R.string.minik_swish_team_question_teammate_first
        } else if humanWinsRace {
            reviewFeedbackRes = R.string.minik_swish_team_question_correct
        } else if humanCorrect {
            reviewFeedbackRes = R.string.minik_swish_team_question_opponent_first
        } else {
            reviewFeedbackRes = R.string.minik_swish_team_question_wrong
        }
        showAnswerReview(q: q)
    }

    private func revealCorrectAnswer() {
        if reviewWinner == nil || questionAnswers == nil { return }
        let children = kuntil(0, questionAnswers.childCount).map { questionAnswers.getChildAt($0)! }
        guard let correct = children.first(where: { ($0.getTag() as? String) == "answer-correct" }) else { return }
        correct.post { [weak self] in
            guard let self = self else { return }
            if self.reviewWinner != nil && correct.isAttachedToWindow {
                correct.requestRectangleOnScreen(ARect(0, 0, correct.width, correct.height), false)
            }
        }
    }

    private func showAnswerReview(q: TripleShotQuestion) {
        questionLocked = true
        let correctValue = q.answers.kMaxOf { $0.qualityPercent }
        for i in kuntil(0, questionAnswers.childCount) {
            // Kotlin `getChildAt(i) as? MaterialButton ?: continue`
            guard let b = questionAnswers.getChildAt(i) as? AButton, b.isMaterialButton else { continue }
            let correct = q.answers[i].qualityPercent == correctValue
            // Disabled FamilySkyDrawable deliberately paints gray. Lock input without disabling
            // the semantic green/red answer colors; submitAnswer also guards double submissions.
            b.isEnabled = true; b.isClickable = false
            b.setTag(correct ? "answer-correct" : i == reviewChoice ? "answer-wrong" : "answer-unselected")
            b.backgroundTintList = AColorStateList.valueOf(
                correct ? argbInt(0xff16824a) : i == reviewChoice ? argbInt(0xffb43b42) : argbInt(0xffedf2f5)
            )
            b.text = (correct ? "\u{2713}  " : i == reviewChoice ? "\u{00D7}  " : "") + q.answers[i].text
        }
        revealCorrectAnswer()
        questionFeedback.setText(res: reviewFeedbackRes)
        exitButton.visibility = AView.VISIBLE
        exitButton.backgroundTintList = AColorStateList.valueOf(argbInt(0xff176ac0))
        configureQuestionFooterForOrientation(landscape: resources.configuration.orientation == AConfiguration.ORIENTATION_LANDSCAPE)
        showBreakTools(persistent: true)
        rootLayout.post { [weak self] in self?.positionQuestionFooter() }
    }

    private func continueAfterAnswer() {
        guard let winner = reviewWinner else { return }
        if ended || controlsPaused || !isResumed { return }
        reviewWinner = nil; reviewChoice = -1; reviewFeedbackRes = ""
        questionCard.visibility = AView.GONE; questionHintCard.visibility = AView.GONE
        questionFooterRow.visibility = AView.GONE; exitButton.visibility = AView.GONE
        hudCard.visibility = AView.VISIBLE
        activeQuestionPosition = -1; pendingQuestionDefaultTeam = nil
        showBreakTools()
        court.startPossession(team: winner, restartFromOwnBaseline: pendingBaselineRestart)
        pendingBaselineRestart = false
    }

    private func nextQuestion() -> TripleShotQuestion {
        precondition(!questions.isEmpty, "Question flow requested while questions are disabled")
        let q = questions[questionIndex % questions.count]
        questionIndex += 1
        return q
    }

    // MARK: - Score, result, league persistence, navigation (TM:1573-1663)

    private func updateScore() {
        let c = config
        if let c = c, !c.leagueSeasonId.isEmpty {
            scoreText.text = "\(c.teamName)  \(humanScore)\n\(c.opponentTeamName)  \(opponentScore)"
        } else {
            scoreText.text = getString(R.string.minik_swish_team_score_format, humanScore, opponentScore)
        }
        if c?.leagueSeasonId.isEmpty == false { scoreText.maxLines = 4; scoreText.maxWidth = dp(v: 215) }
    }

    private func showResult() {
        BasketballSoundscape.result(activity: requireActivity(), won: humanScore > opponentScore, gap: abs(humanScore - opponentScore))
        ended = true
        persistLeagueResult()
        court.clearForQuestion()
        handler.removeCallbacksAndMessages(nil)
        hudCard.visibility = AView.GONE
        tacticalTipCard.visibility = AView.GONE
        introOverlay.visibility = AView.GONE
        questionCard.visibility = AView.GONE
        questionHintCard.visibility = AView.GONE
        if questionsEnabled { exitButton.visibility = AView.GONE }
        questionFooterRow.visibility = AView.GONE
        shotCard.visibility = AView.GONE
        resultTitle.text = getString(humanScore > opponentScore ? R.string.minik_swish_team_you_win : R.string.minik_swish_team_you_lose) + "\n\u{2066}\(humanScore) \u{2013} \(opponentScore)\u{2069}"
        handler.removeCallbacks(hideTools); breakTools.visibility = AView.INVISIBLE
        if let card = resultOverlay.getChildAt(0) as? ACardView {
            card.strokeWidth = dp(v: 2); card.strokeColor = AColor.parseColor(humanScore > opponentScore ? "#3F8CFF" : "#E91E63")
            card.cardElevation = dp(v: 10).toFloat()
        }
        resultOverlay.visibility = AView.VISIBLE
    }

    @discardableResult
    private func persistLeagueResult() -> Bool {
        guard let c = config, !c.leagueSeasonId.isEmpty else { return true }
        if !ended { return true }
        // `runCatching { complete(...); check(saved?.id == seasonId && saved.results.any { it.fixture.key == key }) }`
        var success = false
        do {
            let saved = try TripleShotLeagueStore(context: requireContext()).complete(seasonId: c.leagueSeasonId, fixtureKey: c.leagueFixtureKey, own: humanScore, rival: opponentScore)
            if let saved = saved, saved.id == c.leagueSeasonId, saved.results.contains(where: { $0.fixture.key == c.leagueFixtureKey }) {
                success = true
            }
        } catch {
            success = false
        }
        if !success {
            AToast.makeText(requireContext(), ["he", "iw"].contains(resources.configuration.locales[0].language) ? "לא ניתן לשמור את התוצאה. הישארו במסך ונסו שוב." : "Could not save the result. Stay on this screen and try again.", AToast.LENGTH_LONG).show()
        }
        return success
    }

    private func restart() {
        if config?.leagueSeasonId.isEmpty == false { if persistLeagueResult() { (parentFragment as? TripleShotHostFragment)?.showLeague() }; return }
        ended = false
        humanScore = 0
        opponentScore = 0
        liveMillis = 0
        trumpetCadence.reset()
        hudCard.visibility = AView.VISIBLE
        resultOverlay.visibility = AView.GONE
        updateScore()
        let c = config!
        court.configure(teamSize: c.teamSize, humanCharacterId: c.playerCharacterId, teammateCharacterIds: c.teammateCharacterIds, opponentCharacterIds: c.opponentCharacterIds, seed: c.seed ^ ASystem.currentTimeMillis())
        showTeamIntro()
    }

    private func configureTeamEdgeToEdge() {
        let window = requireActivity().window
        AWindowCompat.setDecorFitsSystemWindows(window, false)
        window.statusBarColor = AColor.TRANSPARENT
        window.navigationBarColor = AColor.TRANSPARENT
        let controller = AWindowCompat.getInsetsController(window, window.decorView)
        controller.isAppearanceLightStatusBars = false
        controller.isAppearanceLightNavigationBars = false
        controller.systemBarsBehavior =
            AWindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        // Team mode draws edge-to-edge in BOTH orientations. Keeping Android's triangle/circle/
        // square bar visible only in landscape wasted court space and contradicted portrait.
        controller.hide(AWindowInsetsCompat.navigationBars())
        // `Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q`: always true (AndroidKit models a current Android).
        window.isNavigationBarContrastEnforced = false
    }

    private func restoreSystemBars() {
        if !isAdded { return }
        let window = requireActivity().window
        AWindowCompat.setDecorFitsSystemWindows(window, true)
        window.navigationBarColor = AColor.parseColor("#101820")
        let controller = AWindowCompat.getInsetsController(window, window.decorView)
        controller.isAppearanceLightStatusBars = false
        controller.isAppearanceLightNavigationBars = false
        controller.show(AWindowInsetsCompat.navigationBars())
        // `Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q`: always true.
        window.isNavigationBarContrastEnforced = false
    }

    private func leaveToHome() {
        if !persistLeagueResult() { return }
        if config?.leagueSeasonId.isEmpty == false { (parentFragment as? TripleShotHostFragment)?.showLeague() }
        else { (parentFragment as? TripleShotHostFragment)?.backToHome() }
    }

    private func dp(v: Int) -> Int { return (v.toFloat() * resources.displayMetrics.density).toInt() }

    // MARK: - iOS-only tools reveal (DESIGN 12.3; spec 17 section 10.1 option (a))

    /// True when a DOWN at (x, y) in rootLayout px starts a reveal tap: the tools are hidden (not VISIBLE), the match
    /// has not ended, and the point lies in the tools' corner (the strip's bounds extended to the top edge and to the
    /// end edge it is anchored to; that edge follows the layout direction like the strip's TOP|END gravity).
    fileprivate func iosToolsRevealHit(x: Float, y: Float) -> Bool {
        if ended || breakTools == nil || rootLayout == nil { return false }
        if breakTools.visibility == AView.VISIBLE { return false }
        if breakTools.width <= 0 || breakTools.height <= 0 { return false }
        let anchoredRight = breakTools.left + breakTools.width / 2 >= rootLayout.width / 2
        let left = anchoredRight ? breakTools.left : 0
        let right = anchoredRight ? rootLayout.width : breakTools.right
        let bottom = breakTools.bottom + dp(v: 8)
        return x >= Float(left) && x < Float(right) && y >= 0 && y < Float(bottom)
    }

    /// The reveal tap: the tools come back for 2.5 s exactly as at the start of a possession.
    fileprivate func iosRevealBreakTools() {
        if ended || breakTools == nil || breakTools.visibility == AView.VISIBLE { return }
        showBreakTools()
    }

    /// `FrameLayout(context)` of buildUi plus the iOS-only reveal: while the tools are hidden, a tap that starts in
    /// their corner is intercepted (so it never reaches the court) and re-shows them on UP.
    private final class TeamMatchRootLayout: AFrameLayout {
        weak var fragment: TripleShotTeamMatchFragment?
        private var revealTap = false

        override func onInterceptTouchEvent(_ ev: AMotionEvent) -> Bool {
            if ev.actionMasked == AMotionEvent.ACTION_DOWN {
                revealTap = fragment?.iosToolsRevealHit(x: ev.x, y: ev.y) ?? false
            }
            return revealTap
        }

        override func onTouchEvent(_ event: AMotionEvent) -> Bool {
            if !revealTap { return super.onTouchEvent(event) }
            switch event.actionMasked {
            case AMotionEvent.ACTION_UP:
                revealTap = false
                fragment?.iosRevealBreakTools()
            case AMotionEvent.ACTION_CANCEL:
                revealTap = false
            default:
                break
            }
            return true
        }
    }

    // MARK: - Companion (TM:1665-1717)

    private static let WIN_SCORE = 11
    private static let STATUS_NOTICE_MIN_MS: Int64 = 3000
    private static let STATUS_NOTICE_VISIBLE_MS: Int64 = 8000
    private static let TACTICAL_TIP_VISIBLE_MS: Int64 = 2700
    private static let ARG_NAME = "team_name"
    private static let ARG_CATEGORIES = "team_categories"
    private static let ARG_PLAYER_ID = "team_player_id"
    private static let ARG_PRIMARY_OPPONENT = "team_primary_opponent"
    private static let ARG_TEAM_SIZE = "team_size"
    private static let ARG_TEAMMATES = "team_teammates"
    private static let ARG_OPPONENTS = "team_opponents"
    private static let ARG_GAME_ORIENTATION = "team_game_orientation"
    private static let ARG_COURT_ID = "team_court_id"
    private static let ARG_SEED = "team_seed"

    private static let STATE_COURT_RUNTIME = "team_state_court_runtime"
    private static let STATE_HUMAN_SCORE = "team_state_human_score"
    private static let STATE_OPPONENT_SCORE = "team_state_opponent_score"
    private static let STATE_ENDED = "team_state_ended"
    private static let STATE_QUESTION_INDEX = "team_state_question_index"
    private static let STATE_POSSESSION_SERIAL = "team_state_possession_serial"
    private static let STATE_ACTIVE_QUESTION_POSITION = "team_state_active_question_position"
    private static let STATE_PENDING_QUESTION_TEAM = "team_state_pending_question_team"
    private static let STATE_PENDING_DEAD_BALL_TEAM = "team_state_pending_dead_ball_team"
    private static let STATE_PENDING_BASELINE_RESTART = "team_state_pending_baseline_restart"
    private static let STATE_INTRO_VISIBLE = "team_state_intro_visible"
    private static let STATE_QUESTION_VISIBLE = "team_state_question_visible"
    private static let STATE_RESULT_VISIBLE = "team_state_result_visible"

    static func newInstance(config: TripleShotGameConfig) -> TripleShotTeamMatchFragment {
        let fragment = TripleShotTeamMatchFragment()
        let arguments = ABundle()
        arguments.putString(ARG_NAME, config.playerName)
        arguments.putStringArrayList(ARG_CATEGORIES, config.selectedCategories.map { $0.name })
        arguments.putString(ARG_PLAYER_ID, config.playerCharacterId)
        arguments.putString(ARG_PRIMARY_OPPONENT, config.opponentCharacterIds.first ?? config.botCharacterId)
        arguments.putInt(ARG_TEAM_SIZE, config.teamSize)
        arguments.putStringArrayList(ARG_TEAMMATES, config.teammateCharacterIds)
        arguments.putStringArrayList(ARG_OPPONENTS, config.opponentCharacterIds)
        arguments.putString(ARG_GAME_ORIENTATION, config.gameOrientation.name)
        arguments.putString(ARG_COURT_ID, config.courtId)
        arguments.putLong(ARG_SEED, config.seed)
        arguments.putInt("match_seconds", config.timeLimitSeconds)
        arguments.putString("league_season", config.leagueSeasonId)
        arguments.putString("league_fixture", config.leagueFixtureKey)
        arguments.putString("league_team_name", config.teamName)
        arguments.putString("league_opponent_name", config.opponentTeamName)
        arguments.putInt("league_team_color", config.teamColor)
        arguments.putInt("league_opponent_color", config.opponentTeamColor)
        fragment.arguments = arguments
        return fragment
    }

    /// Positional form (Kotlin `TripleShotTeamMatchFragment.newInstance(config)`).
    static func newInstance(_ config: TripleShotGameConfig) -> TripleShotTeamMatchFragment {
        return newInstance(config: config)
    }
}

// MARK: - Court listener (Kotlin `court.setListener(object : TripleShotTeamCourtView.Listener { ... })`, TM:214-282)

extension TripleShotTeamMatchFragment: TripleShotTeamCourtView.Listener {
    func onLiveTime(milliseconds: Int64) {
        if ended || !isResumed { return }
        liveMillis += milliseconds
        if matchDuration > 0 && liveMillis >= Int64(matchDuration) * 1000 && humanScore != opponentScore { showResult() }
    }
    func onShotClock(seconds: Int) {
        let he = ["he", "iw"].contains(resources.configuration.locales[0].language)
        let remaining = (Int64(matchDuration) - liveMillis / 1000).coerceAtLeast(0)
        clockText.visibility = AView.VISIBLE
        clockText.text = (he ? "שעון התקפה: \(seconds)" : "Shot clock: \(seconds)") +
            (matchDuration > 0 ? "  \u{2022}  \(remaining / 60):\(String(remaining % 60).kpadStart(2, "0"))" : "")
    }
    func onHighlight(team: TripleShotTeamCourtView.Team, event: TrumpetCadence.Event) {
        if team == TripleShotTeamCourtView.Team.HUMAN { trumpetEvent(event: event) }
    }
    func onTeamBasket(team: TripleShotTeamCourtView.Team, points: Int) {
        if ended { return }
        if team == TripleShotTeamCourtView.Team.HUMAN {
            humanScore += points; BasketballSoundscape.effect(context: requireContext(), kind: BasketballSoundscape.Effect.APPLAUSE)
        } else { opponentScore += points }
        // A made basket always creates a baseline restart. The next possession may be awarded
        // by a question to either team, but whoever gets it must start under THEIR own hoop.
        pendingBaselineRestart = true
        updateScore()
        enqueueBasketStatus(team: team)
        if (matchDuration == 0 && (humanScore >= Self.WIN_SCORE || opponentScore >= Self.WIN_SCORE)) || (matchDuration > 0 && liveMillis >= Int64(matchDuration) * 1000 && humanScore != opponentScore) {
            showResult()
        }
    }

    func onPossessionChanged(team: TripleShotTeamCourtView.Team) {
        if team == TripleShotTeamCourtView.Team.HUMAN { trumpetEvent(event: TrumpetCadence.Event.OFFENSE) }
        lastPossessionTeam = team
        // Do not overwrite a meaningful event such as "Steal!" with a second redundant
        // "your ball" line. The compact status card owns one message at a time.
    }

    func onStatus(message: String, team: TripleShotTeamCourtView.Team?) {
        let tone: StatusTone
        switch team {
        case .HUMAN?: tone = StatusTone.HUMAN
        case .OPPONENT?: tone = StatusTone.OPPONENT
        case nil: tone = StatusTone.NEUTRAL
        }
        enqueueStatus(text: message, tone: tone)
    }

    func onShotQuality(percent: Int, visible: Bool) {
        shotCard.visibility = visible ? AView.VISIBLE : AView.GONE
        if visible {
            shotPercent.text = ["he", "iw"].contains(resources.configuration.locales[0].language) ? "סיכוי לקליעה: \(percent)%" : "Shot chance: \(percent)%"
            shotBar.progress = percent
        }
    }

    func onDeadBall(defaultNextTeam: TripleShotTeamCourtView.Team) {
        showBreakTools(persistent: questionsEnabled)
        if !ended {
            pendingDeadBallTeam = defaultNextTeam
            handler.postDelayed({ [weak self] in
                guard let self = self else { return }
                guard let next = self.pendingDeadBallTeam else { return }
                self.pendingDeadBallTeam = nil
                self.beginPossessionFlow(defaultTeam: next, restartFromOwnBaseline: self.pendingBaselineRestart)
            }, 720)
        }
    }

    func onHumanGuidanceChanged(guidance: TripleShotTeamCourtView.HumanGuidance) {
        if !ended && introOverlay != nil && introOverlay.visibility != AView.VISIBLE {
            enqueueGuidanceStatus(guidance: guidance)
        }
    }
}
