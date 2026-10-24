import Foundation
import XCTest
@testable import MinikTripleShot

// Parity tests for area s-game1 (spec 13): ui/TripleShotGameFragment.kt lines 1-1949 (part 1 of the split class)
// and res/layout/fragment_triple_shot_game.xml (TripleShotGameLayout).
//
// - Field initial values are the Kotlin initialisers (L66-209).
// - The language-dependent helpers follow the device's first preferred language, exactly like
//   `ConfigurationCompat.getLocales(resources.configuration)[0].language`: the expectations are computed from the same
//   rule (he/iw -> Hebrew), so the tests pass in any simulator language.
// - The layout test checks the XML ids, child order, params and the attributes the code relies on, read the way the
//   Android inflater reads them (getDimensionPixelSize / getDimension).

final class Game1Tests: XCTestCase {

    /// A fragment whose `requireContext()` / `resources` work without a started activity.
    private func fragmentWithHost() -> TripleShotGameFragment {
        let fragment = TripleShotGameFragment()
        fragment.mHost = AActivity()
        return fragment
    }

    private func configurationIsHebrew() -> Bool {
        let language = TripleShotGameFragment.game1ConfigurationLanguage(AContextResources.shared)
        return language == "he" || language == "iw"
    }

    // MARK: - Fields (Kotlin L66-209)

    func testFieldInitialValuesMatchKotlin() {
        let f = TripleShotGameFragment()
        XCTAssertNil(f.botOpponent)
        XCTAssertEqual(f.botTurnCounter, 0)
        XCTAssertNil(f.horseEngine)
        XCTAssertNil(f.horseQuestion)
        XCTAssertEqual(f.horseQuestionCounter, 0)
        XCTAssertNil(f.horsePendingCategory)
        XCTAssertNil(f.horseSelectedCategory)
        XCTAssertFalse(f.horseTopicPromptShown)
        XCTAssertFalse(f.horseWaitingForSpot)
        XCTAssertEqual(f.horseTurnMessage, "")
        XCTAssertTrue(f.horseRecentQuestionIds.isEmpty)
        XCTAssertFalse(f.horseMoveTouchActive)
        XCTAssertEqual(f.horseMoveLastX, 0)
        XCTAssertEqual(f.horseMoveDownY, 0)
        XCTAssertFalse(f.horseMoveHasDragged)
        XCTAssertEqual(f.questionIndex, 0)
        XCTAssertEqual(f.selectedAnswerIndex, -1)
        XCTAssertFalse(f.knowledgeAnswerRecorded)
        XCTAssertFalse(f.shotInProgress)
        XCTAssertFalse(f.feedbackShowing)
        XCTAssertNil(f.feedbackContinueAction)
        XCTAssertNil(f.feedbackTapOverlay)
        XCTAssertFalse(f.ended)
        XCTAssertEqual(f.secondsLeft, 90)
        XCTAssertFalse(f.fallbackSensors)
        XCTAssertFalse(f.tutorialActive)
        XCTAssertEqual(f.tutorialPage, TripleShotGameFragment.TutorialStep.CHOOSE_ANSWER.ordinal)
        XCTAssertEqual(f.tutorialProgress, 0)
        XCTAssertEqual(f.currentShotPhase, TripleShotSensorController.ShotPhase.WAITING_FOR_ANSWER)
        XCTAssertTrue(f.answerViews.isEmpty)
        XCTAssertEqual(f.pendingStationTap, -1)
        XCTAssertEqual(f.stationTapDownX, 0)
        XCTAssertNil(f.roomPlayersHandle)
        XCTAssertNil(f.roomShotsHandle)
        XCTAssertNil(f.liveHorseHandle)
        XCTAssertTrue(f.seenLiveShotIds.isEmpty)
        XCTAssertTrue(f.latestLivePlayers.isEmpty)
        XCTAssertNil(f.liveHorseState)
        XCTAssertEqual(f.liveHorseLastHandledTurn, -1)
        XCTAssertFalse(f.liveHorseFinishedShown)
    }

    func testFragmentInflatesTheGameLayout() {
        let f = TripleShotGameFragment()
        XCTAssertEqual(f.contentLayoutId, R.layout.fragment_triple_shot_game)
        XCTAssertTrue(ALayoutInflater.isRegistered(R.layout.fragment_triple_shot_game))
    }

    func testClockRunnableIsOneStableInstance() {
        // removeCallbacks(clockRunnable) (showLiveHorseFinished) matches by identity, like the Kotlin object.
        let f = TripleShotGameFragment()
        XCTAssertTrue(f.clockRunnable === f.clockRunnable)
    }

    // MARK: - Guards (the Kotlin early returns run before anything touches a view)

    func testCallbacksOfADetachedFragmentDoNothing() {
        let f = TripleShotGameFragment()
        XCTAssertFalse(f.isAdded)
        // onShotGesture / onMovementChanged / onSensorAvailability return on !isAdded; onAimChanged and
        // onPullBackChanged return while the court view is not initialised; onShotPhaseChanged stores the phase first.
        f.selectedAnswerIndex = 0
        f.onShotGesture(skill: ShotSkill(aimError: 0, powerError: 0, arcError: 0, rawPeakGyro: 0, rawReleasePitchDeg: 0),
                        pullBack01: 0.5)
        f.onMovementChanged(horizontal: 1, vertical: 1)
        f.onSensorAvailability(hasRotation: false, hasGyro: false)
        XCTAssertFalse(f.fallbackSensors, "the !isAdded return comes before fallbackSensors is written")
        f.onAimChanged(normalizedAim: 0.5)
        f.onPullBackChanged(normalizedPullBack: 0.5, armed: true)
        f.onShotPhaseChanged(phase: TripleShotSensorController.ShotPhase.ARMED)
        XCTAssertEqual(f.currentShotPhase, TripleShotSensorController.ShotPhase.ARMED)
        XCTAssertFalse(f.shotInProgress)

        // advanceHorseTurn / promptHumanHorseTopic / beginHumanHorseSpotSelection / handleLiveHorseState: !isAdded.
        f.advanceHorseTurn()
        f.promptHumanHorseTopic()
        f.beginHumanHorseSpotSelection(category: QuestionCategory.MATH)
        f.handleLiveHorseState(state: LiveHorseState(phase: LiveHorseState.PHASE_ATTEMPT, turnNumber: 3))
        XCTAssertFalse(f.horseWaitingForSpot)
        XCTAssertEqual(f.liveHorseLastHandledTurn, -1)
    }

    func testSelectAnswerIsIgnoredWhileAShotOrFeedbackIsRunningOrTheGameEnded() {
        let f = TripleShotGameFragment()
        f.shotInProgress = true
        f.selectAnswer(index: 0)
        XCTAssertEqual(f.selectedAnswerIndex, -1)
        f.shotInProgress = false
        f.feedbackShowing = true
        f.selectAnswer(index: 0)
        XCTAssertEqual(f.selectedAnswerIndex, -1)
        f.feedbackShowing = false
        f.ended = true
        f.selectAnswer(index: 0)
        XCTAssertEqual(f.selectedAnswerIndex, -1)
    }

    func testFreeSpotConfirmationsNeedTheSpotSelection() {
        let f = TripleShotGameFragment()
        XCTAssertFalse(f.horseWaitingForSpot)
        f.confirmHumanHorseFreeSpot()
        f.confirmLiveHorseFreeSpot()
        XCTAssertFalse(f.horseWaitingForSpot)
        XCTAssertNil(f.horseEngine)
    }

    func testKnowledgeAnswerIsRecordedOncePerQuestion() {
        let f = TripleShotGameFragment()
        f.knowledgeAnswerRecorded = true
        let question = TripleShotQuestion(
            id: "q", category: QuestionCategory.MATH, prompt: "1+1",
            answers: [AnswerOption(text: "2", qualityPercent: 100), AnswerOption(text: "3", qualityPercent: 0)],
            explanation: ""
        )
        f.recordHumanKnowledgeAnswer(question: question, answerIndex: 0)   // returns at the guard
        XCTAssertTrue(f.knowledgeAnswerRecorded)
        f.knowledgeAnswerRecorded = false
        f.recordHumanKnowledgeAnswer(question: question, answerIndex: 7)   // getOrNull(7) == null: returns
        XCTAssertFalse(f.knowledgeAnswerRecorded)
    }

    // MARK: - Mode predicates (L1171-1178)

    func testModePredicates() {
        let f = TripleShotGameFragment()

        f.config = TripleShotGameConfig(playerName: "P", gameType: .HORSE, limitMode: .BALLS_ONLY, botMatch: true)
        XCTAssertTrue(f.isBotHorseMode())
        XCTAssertFalse(f.isLiveHorseMode())
        XCTAssertTrue(f.isAnyHorseMode())

        f.config = TripleShotGameConfig(playerName: "P", gameType: .HORSE, limitMode: .BALLS_ONLY, roomId: "ABC123",
                                        botMatch: true)
        XCTAssertFalse(f.isBotHorseMode(), "a room wins over botMatch (isBotMatch = botMatch && !multiplayer)")
        XCTAssertTrue(f.isLiveHorseMode())
        XCTAssertTrue(f.isAnyHorseMode())

        // The degenerate "HORSE without bot or room" after Live HORSE "Play again" (spec 13 §2.2, §8.17).
        f.config = TripleShotGameConfig(playerName: "P", gameType: .HORSE, limitMode: .BALLS_ONLY, roomId: nil)
        XCTAssertFalse(f.isAnyHorseMode())

        f.config = TripleShotGameConfig(playerName: "P", gameType: .SHOOTING_CHALLENGE, roomId: "  ")
        XCTAssertFalse(f.isAnyHorseMode())
    }

    func testHorseAvailableCategoriesAreTheSelectionSortedByOrdinal() {
        let f = TripleShotGameFragment()
        f.config = TripleShotGameConfig(
            playerName: "P",
            selectedCategories: KLinkedSet([QuestionCategory.MATH, QuestionCategory.SCIENCE, QuestionCategory.AI])
        )
        XCTAssertEqual(f.horseAvailableCategories(), [QuestionCategory.SCIENCE, QuestionCategory.AI, QuestionCategory.MATH])

        f.config = TripleShotGameConfig(playerName: "P", selectedCategories: KLinkedSet<QuestionCategory>())
        XCTAssertEqual(f.horseAvailableCategories(), Array(QuestionCategory.allCases))
    }

    // MARK: - Texts (L675-695, L1541-1549)

    func testHorsePenaltyDisplay() {
        let f = TripleShotGameFragment()
        XCTAssertEqual(f.horsePenaltyDisplay(count: -3), "\u{2014}")
        XCTAssertEqual(f.horsePenaltyDisplay(count: 0), "\u{2014}")
        XCTAssertEqual(f.horsePenaltyDisplay(count: 1), "H")
        XCTAssertEqual(f.horsePenaltyDisplay(count: 2), "HO")
        XCTAssertEqual(f.horsePenaltyDisplay(count: 3), "HOR")
        XCTAssertEqual(f.horsePenaltyDisplay(count: 4), "HORS")
        XCTAssertEqual(f.horsePenaltyDisplay(count: 5), "HORSE")
        XCTAssertEqual(f.horsePenaltyDisplay(count: 9), "HORSE")
    }

    func testLiveHorseTextFollowsTheConfigurationLanguage() {
        let f = fragmentWithHost()
        let hebrew = configurationIsHebrew()
        XCTAssertEqual(f.liveHorseText(hebrew: "\u{5E2}", english: "E"), hebrew ? "\u{5E2}" : "E")
    }

    func testAnswerLabelsAndDisplayText() {
        let f = fragmentWithHost()
        let hebrew = configurationIsHebrew()
        XCTAssertEqual(f.answerChoiceLabel(index: 0), hebrew ? "\u{5D0}" : "A")
        XCTAssertEqual(f.answerChoiceLabel(index: 1), hebrew ? "\u{5D1}" : "B")
        XCTAssertEqual(f.answerChoiceLabel(index: 2), hebrew ? "\u{5D2}" : "C")
        XCTAssertEqual(f.answerChoiceLabel(index: 3), hebrew ? "\u{5D3}" : "D")
        // Beyond the four Hebrew letters Kotlin falls back to (index + 1).toString(); Latin keeps counting letters.
        XCTAssertEqual(f.answerChoiceLabel(index: 4), hebrew ? "5" : "E")

        let b = hebrew ? "\u{5D1}" : "B"
        XCTAssertEqual(f.answerDisplayText(index: 1, text: "Paris"), b + ". Paris")
        XCTAssertEqual(f.answerDisplayText(index: 1, text: "Paris", statusMark: "\u{2713}"), b + ". \u{2713} Paris")
        // isNullOrBlank(): a blank mark is no mark.
        XCTAssertEqual(f.answerDisplayText(index: 1, text: "Paris", statusMark: " \t"), b + ". Paris")
        XCTAssertEqual(f.answerDisplayText(index: 1, text: "Paris", statusMark: nil), b + ". Paris")
    }

    // MARK: - fragment_triple_shot_game.xml

    func testLayoutTreeMatchesTheXml() throws {
        let px = { (dp: Float) -> Int in ATypedValue.toDimensionPixelSize(ATypedValue.COMPLEX_UNIT_DIP, dp) }
        let spPx = { (sp: Float) -> Float in Float(ATypedValue.toDimensionPixelSize(ATypedValue.COMPLEX_UNIT_SP, sp)) }
        let dimen = { (dp: Float) -> Float in ATypedValue.applyDimension(ATypedValue.COMPLEX_UNIT_DIP, dp) }

        let root = try XCTUnwrap(TripleShotGameLayout.build() as? AConstraintLayout)
        XCTAssertEqual(root.rawLayoutDirection, AView.LAYOUT_DIRECTION_LOCALE)
        XCTAssertEqual(root.layoutParams?.width, AViewGroup.LayoutParams.MATCH_PARENT)
        XCTAssertEqual(root.layoutParams?.height, AViewGroup.LayoutParams.MATCH_PARENT)
        XCTAssertEqual((root.background as? AColorDrawable)?.color, AColor.parseColor("#101820"))

        // XML child order, plus the iOS-only exit control appended last.
        XCTAssertEqual(root.children.map { $0.viewId ?? "" }, [
            R.id.gameBackground, R.id.courtView, R.id.topHud, R.id.questionCard, R.id.shotStyleButton,
            R.id.opponentsScroll, R.id.tutorialCard, R.id.resultOverlay, TripleShotGameFragment.IOS_EXIT_BUTTON_ID,
        ])

        let gameBackground: AImageView = try XCTUnwrap(root.findViewById(R.id.gameBackground))
        XCTAssertEqual(gameBackground.scaleType, AImageView.ScaleType.MATRIX)
        XCTAssertNotNil(root.findViewById(R.id.courtView) as TripleShotCourtView?)

        // HUD row.
        let topHud: ALinearLayout = try XCTUnwrap(root.findViewById(R.id.topHud))
        let hudParams = try XCTUnwrap(topHud.layoutParams as? AConstraintLayout.LayoutParams)
        XCTAssertEqual(hudParams.width, 0)
        XCTAssertEqual(hudParams.height, px(38))   // 6c38131 (1ddda77): 30 -> 38 dp
        XCTAssertEqual(hudParams.marginStart, px(6))
        XCTAssertEqual(hudParams.topMargin, px(5))
        XCTAssertEqual(hudParams.startToStart, AConstraintLayout.LayoutParams.PARENT_ID)
        XCTAssertEqual(hudParams.topToTop, AConstraintLayout.LayoutParams.PARENT_ID)
        XCTAssertEqual(hudParams.endToStart, TripleShotGameFragment.IOS_EXIT_BUTTON_ID)
        XCTAssertEqual(topHud.elevation, dimen(5))
        XCTAssertEqual(topHud.orientation, ALinearLayout.HORIZONTAL)
        XCTAssertEqual(topHud.children.map { $0.viewId ?? "" },
                       [R.id.timeText, R.id.scoreText, R.id.botScoreText, R.id.ballsText, R.id.streakText])
        let weights = topHud.children.map { ($0.layoutParams as? ALinearLayout.LayoutParams)?.weight ?? -1 }
        XCTAssertEqual(weights, [0.82, 0.95, 1.0, 1.0, 1.25])
        let timeText: ATextView = try XCTUnwrap(root.findViewById(R.id.timeText))
        XCTAssertEqual(timeText.textSize, spPx(12.5))   // 6c38131: every HUD cell is 12.5 sp
        XCTAssertEqual(timeText.currentTextColor, AColor.parseColor("#142129"))
        let botScoreText: ATextView = try XCTUnwrap(root.findViewById(R.id.botScoreText))
        XCTAssertEqual(botScoreText.visibility, AView.GONE)
        XCTAssertEqual(botScoreText.ellipsize, ATextUtils.TruncateAt.MIDDLE)
        XCTAssertEqual(botScoreText.currentTextColor, AColor.parseColor("#6B3EB4"))
        let ballsText: ATextView = try XCTUnwrap(root.findViewById(R.id.ballsText))
        XCTAssertEqual(ballsText.visibility, AView.GONE)
        XCTAssertEqual(ballsText.textSize, spPx(12.5))
        let streakText: ATextView = try XCTUnwrap(root.findViewById(R.id.streakText))
        XCTAssertEqual(streakText.textSize, spPx(12.5))

        // Question card (XML geometry; configureCenteredQuestionLayout() replaces it at runtime).
        let questionCard: ALinearLayout = try XCTUnwrap(root.findViewById(R.id.questionCard))
        let cardParams = try XCTUnwrap(questionCard.layoutParams as? AConstraintLayout.LayoutParams)
        XCTAssertEqual(cardParams.width, 0)
        XCTAssertEqual(cardParams.matchConstraintPercentWidth, 0.58)
        XCTAssertEqual(cardParams.matchConstraintDefaultWidth, AConstraintLayout.LayoutParams.MATCH_CONSTRAINT_PERCENT)
        XCTAssertEqual(cardParams.horizontalBias, 0)
        XCTAssertEqual(cardParams.leftMargin, px(7))
        XCTAssertEqual(cardParams.topMargin, px(3))
        XCTAssertEqual(cardParams.topToBottom, R.id.topHud)
        XCTAssertEqual(questionCard.elevation, dimen(6))
        XCTAssertEqual(questionCard.children.count, 5)
        XCTAssertEqual(questionCard.children.dropFirst().map { $0.viewId ?? "" },
                       [R.id.questionText, R.id.horseMoveHelpDismissText, R.id.answerStrip, R.id.feedbackText])
        let help: AButton = try XCTUnwrap(root.findViewById(R.id.tutorialHelpButton))
        XCTAssertEqual(help.layoutParams?.width, px(32))
        XCTAssertEqual(help.layoutParams?.height, px(32))
        XCTAssertEqual(help.paddingTop, 0)
        XCTAssertEqual(help.paddingLeft, 0)
        XCTAssertEqual(help.text, getString(R.string.minik_swish_tutorial_help_symbol))
        XCTAssertEqual(help.contentDescription, getString(R.string.minik_swish_tutorial_help_description))
        XCTAssertTrue((root.findViewById(R.id.categoryText) as AView?) is OutlinedTextView)
        let questionText: ATextView = try XCTUnwrap(root.findViewById(R.id.questionText))
        XCTAssertTrue(questionText is OutlinedTextView)
        XCTAssertEqual(questionText.maxLines, 4)
        XCTAssertEqual(questionText.textSize, spPx(15.5))
        XCTAssertFalse(questionText.includeFontPadding)
        XCTAssertEqual(questionText.lineSpacingExtra, Float(px(1)))
        let dismissHelp: ATextView = try XCTUnwrap(root.findViewById(R.id.horseMoveHelpDismissText))
        XCTAssertEqual(dismissHelp.visibility, AView.GONE)
        let feedbackText: ATextView = try XCTUnwrap(root.findViewById(R.id.feedbackText))
        XCTAssertTrue(feedbackText is OutlinedTextView)
        XCTAssertEqual(feedbackText.visibility, AView.GONE)
        XCTAssertEqual(feedbackText.maxLines, 8)
        XCTAssertEqual(feedbackText.textSize, spPx(16))
        XCTAssertEqual((feedbackText.layoutParams as? ALinearLayout.LayoutParams)?.topMargin, px(4))

        // Dead / hidden views.
        let shotStyle: AButton = try XCTUnwrap(root.findViewById(R.id.shotStyleButton))
        XCTAssertEqual(shotStyle.visibility, AView.GONE)
        let opponentsScroll: AHorizontalScrollView = try XCTUnwrap(root.findViewById(R.id.opponentsScroll))
        XCTAssertEqual(opponentsScroll.visibility, AView.GONE)
        XCTAssertTrue(opponentsScroll.isFillViewport)
        XCTAssertNotNil(root.findViewById(R.id.opponentsContainer) as ALinearLayout?)

        // Tutorial card.
        let tutorialCard: ACardView = try XCTUnwrap(root.findViewById(R.id.tutorialCard))
        XCTAssertEqual(tutorialCard.visibility, AView.GONE)
        let tutorialParams = try XCTUnwrap(tutorialCard.layoutParams as? AConstraintLayout.LayoutParams)
        XCTAssertEqual(tutorialParams.verticalBias, 0.43)
        XCTAssertEqual(tutorialParams.matchConstraintMaxWidth, px(620))
        XCTAssertEqual(tutorialParams.marginStart, px(14))
        XCTAssertEqual(tutorialCard.radius, dimen(18))
        XCTAssertEqual(tutorialCard.cardElevation, dimen(4))
        XCTAssertEqual(tutorialCard.strokeWidth, px(2))
        for id in [R.id.tutorialTitle, R.id.tutorialBody] {
            XCTAssertNotNil(root.findViewById(id) as ATextView?, id)
        }
        for id in [R.id.tutorialPrevButton, R.id.tutorialNextButton, R.id.tutorialDismissButton] {
            XCTAssertTrue((root.findViewById(id) as AView?) is TripleShotButton, id)
        }

        // Result overlay.
        let resultOverlay: AFrameLayout = try XCTUnwrap(root.findViewById(R.id.resultOverlay))
        XCTAssertEqual(resultOverlay.visibility, AView.GONE)
        XCTAssertTrue(resultOverlay.isClickable)
        let resultScroll: AScrollView = try XCTUnwrap(root.findViewById(R.id.basketballResultScroll))
        let scrollParams = try XCTUnwrap(resultScroll.layoutParams as? AFrameLayout.LayoutParams)
        XCTAssertEqual(scrollParams.gravity, AGravity.CENTER)
        XCTAssertEqual(scrollParams.leftMargin, px(16))
        XCTAssertEqual(scrollParams.bottomMargin, px(16))
        for id in [R.id.resultScoreText, R.id.resultStatsText, R.id.resultRankText] {
            XCTAssertNotNil(root.findViewById(id) as ATextView?, id)
        }
        for id in [R.id.resultLeaderboardButton, R.id.resultAgainButton, R.id.resultHomeButton] {
            XCTAssertTrue((root.findViewById(id) as AView?) is TripleShotButton, id)
        }
        let leaderboard: AButton = try XCTUnwrap(root.findViewById(R.id.resultLeaderboardButton))
        XCTAssertEqual(leaderboard.layoutParams?.height, px(52))

        // iOS-only exit control (DESIGN 12.3).
        let exit: AImageView = try XCTUnwrap(root.findViewById(TripleShotGameFragment.IOS_EXIT_BUTTON_ID))
        let exitParams = try XCTUnwrap(exit.layoutParams as? AConstraintLayout.LayoutParams)
        XCTAssertEqual(exitParams.width, px(36))
        XCTAssertEqual(exitParams.height, px(36))
        XCTAssertEqual(exitParams.endToEnd, AConstraintLayout.LayoutParams.PARENT_ID)
        XCTAssertEqual(exitParams.topToTop, AConstraintLayout.LayoutParams.PARENT_ID)
        XCTAssertEqual(exit.elevation, topHud.elevation)
        XCTAssertTrue(exit.isClickable)
        XCTAssertEqual(exit.contentDescription, getString(R.string.minik_swish_one_on_one_exit_game))
    }
}
