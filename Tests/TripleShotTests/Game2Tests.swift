import Foundation
import XCTest
@testable import MinikTripleShot

// Parity tests for area s-game2 (spec 14-game2): ui/TripleShotGameFragment.kt lines 1950-3886, part 2 of the split
// class (TripleShotGameFragment+Part2.swift).
//
// - Expected values come from the Kotlin source and the spec tables (sections 4.4, 4.7, 4.8, 4.9, 4.10, 4.13, 6, 7).
// - The HORSE question seeds are the Kotlin Long arithmetic of L2140-2143 evaluated outside Swift
//   (`seed xor (counter * 0x9E3779B9L) xor category.ordinal`).
// - "Attached" fragments get a bare host activity (`mHost` / `mAdded`), which is all `isAdded`, `resources` and
//   `getString` need. The device language of the inline he/en pairs is `AConfiguration.current`, the string table
//   is `AResources.languageOverride`; both are restored after each test.

final class Game2Tests: XCTestCase {

    private static let QUESTION_PREFS = "triple_shot_question_difficulty_v2"

    private var savedConfiguration: AConfiguration!
    private var savedLanguageOverride: String?

    override func setUp() {
        super.setUp()
        savedConfiguration = AConfiguration.current
        savedLanguageOverride = AResources.languageOverride
    }

    override func tearDown() {
        AConfiguration.current = savedConfiguration
        AResources.languageOverride = savedLanguageOverride
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeConfig(
        playerName: String = "Me",
        gameType: GameType = .SHOOTING_CHALLENGE,
        limitMode: GameLimitMode = .TIME_ONLY,
        roomId: String? = nil,
        botMatch: Bool = false,
        botCharacterId: String = TripleShotCharacterRoster.ID_BOB,
        seed: Int64 = 1,
        ballLimit: Int = 20,
        timeLimitSeconds: Int = 60
    ) -> TripleShotGameConfig {
        return TripleShotGameConfig(
            playerName: playerName,
            gameType: gameType,
            limitMode: limitMode,
            selectedCategories: KLinkedSet(QuestionCategory.allCases),
            roomId: roomId,
            botMatch: botMatch,
            botCharacterId: botCharacterId,
            seed: seed,
            ballLimit: ballLimit,
            timeLimitSeconds: timeLimitSeconds
        )
    }

    /// A detached fragment with a config (no host, no views): enough for the members that touch neither.
    private func makeFragment(_ config: TripleShotGameConfig) -> TripleShotGameFragment {
        let fragment = TripleShotGameFragment()
        fragment.config = config
        return fragment
    }

    /// A fragment with a bare host, so `isAdded`, `resources` and `getString` work like an attached Fragment.
    private func makeAttachedFragment(_ config: TripleShotGameConfig) -> TripleShotGameFragment {
        let fragment = makeFragment(config)
        fragment.mHost = AActivity()
        fragment.mAdded = true
        return fragment
    }

    /// `configuration.locales[0]` for the inline he/en pairs and the values/ or values-en/ string table.
    private func setLanguage(_ language: String) {
        let base = AConfiguration.current
        AConfiguration.current = AConfiguration(
            orientation: base.orientation, screenWidthDp: base.screenWidthDp, screenHeightDp: base.screenHeightDp,
            smallestScreenWidthDp: base.smallestScreenWidthDp, densityDpi: base.densityDpi, fontScale: base.fontScale,
            uiMode: base.uiMode, locales: ALocaleList([ALocale(language)]))
        AResources.languageOverride = language == "en" ? "en" : "he"
    }

    private func installHud(_ fragment: TripleShotGameFragment) {
        fragment.timeText = ATextView()
        fragment.scoreText = ATextView()
        fragment.botScoreText = ATextView()
        fragment.ballsText = ATextView()
        fragment.streakText = ATextView()
    }

    private func reviewQuestion() -> TripleShotQuestion {
        return TripleShotQuestion(
            id: "q-review",
            category: .SCIENCE,
            prompt: "What is H2O?",
            answers: [
                AnswerOption(text: "Ice", qualityPercent: 0),
                AnswerOption(text: "Water", qualityPercent: 100),
                AnswerOption(text: "Steam", qualityPercent: 100)
            ],
            explanation: "Water is H2O."
        )
    }

    private func shot(_ kind: TripleShotCourtView.ShotKind, made: Bool) -> TripleShotCourtView.ShotResult {
        return TripleShotCourtView.ShotResult(
            outcome: ShotOutcome(made: made, targetOffsetX: 0, targetOffsetY: 0, quality: 1),
            kind: kind,
            rimHits: 0,
            backboardHits: 0,
            replaySamples: []
        )
    }

    private func fill(_ drawable: ADrawable?) -> Int? {
        return (drawable as? FamilySkyDrawable)?.sourceColors().defaultColor
    }

    /// Runs `body` with the question-difficulty preferences saved and restored (the repository reads them).
    private func withQuestionPrefs(_ body: () -> Void) {
        let defaults = UserDefaults.standard
        let prefix = Game2Tests.QUESTION_PREFS + "."
        let saved = defaults.dictionaryRepresentation().filter { $0.key.hasPrefix(prefix) }
        body()
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
        for (key, value) in saved { defaults.set(value, forKey: key) }
    }

    // MARK: - TutorialStep (L58-64) and the companion object (L3788-3885)

    func testTutorialStepOrdinalsAreThePageNumbers() {
        XCTAssertEqual(TripleShotGameFragment.TutorialStep.allCases.map { $0.name },
                       ["CHOOSE_ANSWER", "AIM", "PULL_BACK", "THROW", "FREE_PLAY"])
        XCTAssertEqual(TripleShotGameFragment.TutorialStep.allCases.map { $0.ordinal }, [0, 1, 2, 3, 4])
    }

    func testCompanionConstantsMatchTheKotlinCompanionObject() {
        typealias F = TripleShotGameFragment
        XCTAssertEqual(F.STATION_TAP_SLOP_DP, 18)
        XCTAssertEqual(F.HORSE_MOVE_TAP_SLOP_DP, 10)
        XCTAssertEqual([F.ARG_NAME, F.ARG_GAME_TYPE, F.ARG_MODE, F.ARG_CATEGORIES, F.ARG_ROOM, F.ARG_ROOM_STARTED_AT,
                        F.ARG_BOT_MATCH, F.ARG_PLAYER_CHARACTER, F.ARG_BOT_CHARACTER, F.ARG_SEED, F.ARG_BALL_LIMIT,
                        F.ARG_TIME_LIMIT_SECONDS],
                       ["name", "game_type", "mode", "categories", "room", "room_started_at", "bot_match",
                        "player_character", "bot_character", "seed", "ball_limit", "time_limit_seconds"])
        XCTAssertEqual(F.TUTORIAL_PREFS, "minik_swish_tutorial")
        XCTAssertEqual(F.TUTORIAL_DONE_KEY, "shooting_tutorial_completed")
        XCTAssertEqual(F.TUTORIAL_AIM_MOVEMENT, Float(0.18))
        XCTAssertEqual(F.MIN_SHOT_PULLBACK, Float(0.24))
        XCTAssertEqual(F.AIMING_UI_ALPHA, Float(0))
        XCTAssertEqual(F.UI_FADE_AIM_MS, 170)
        XCTAssertEqual(F.UI_FADE_SHOT_MS, 110)
        XCTAssertEqual(F.UI_FADE_IN_MS, 170)
        XCTAssertEqual(F.BOT_RESPONSE_DELAY_MS, 260)
        XCTAssertEqual(F.HORSE_BOT_THINK_DELAY_MS, 620)
        XCTAssertEqual(F.QUESTION_CARD_WIDTH_PERCENT, Float(0.90))
        XCTAssertEqual(F.HORSE_END_CELEBRATION_MS, 2800)
        XCTAssertEqual(F.HEBREW_ANSWER_LABELS, ["\u{5D0}", "\u{5D1}", "\u{5D2}", "\u{5D3}"])
        XCTAssertEqual(F.HORSE_RECENT_QUESTION_MEMORY, 8)
        // 0x424F54434F555254L ("BOTCOURT").
        XCTAssertEqual(F.BOT_COURT_SEED_SALT, 4_778_130_377_733_919_316)
    }

    func testNewInstanceBundlesTheTwelveArgumentsWithCategoriesInOrdinalOrder() {
        let config = TripleShotGameConfig(
            playerName: "Noa",
            gameType: .HORSE,
            limitMode: .BALLS_ONLY,
            selectedCategories: KLinkedSet([QuestionCategory.MATH, .AI, .GENERAL_KNOWLEDGE]),
            roomId: nil,
            roomStartedAtMs: 1234,
            botMatch: true,
            playerCharacterId: TripleShotCharacterRoster.ID_ROOZA,
            botCharacterId: TripleShotCharacterRoster.ID_KYRA,
            teamSize: 3,
            courtId: "not_bundled",
            seed: -42,
            ballLimit: 7,
            timeLimitSeconds: 0
        )
        let fragment = TripleShotGameFragment.newInstance(config: config)
        guard let args = fragment.arguments else { return XCTFail("no arguments") }
        XCTAssertEqual(args.keySet(), ["name", "game_type", "mode", "categories", "room", "room_started_at", "bot_match",
                                       "player_character", "bot_character", "seed", "ball_limit", "time_limit_seconds"])
        XCTAssertEqual(args.getString("name"), "Noa")
        XCTAssertEqual(args.getString("game_type"), "HORSE")
        XCTAssertEqual(args.getString("mode"), "BALLS_ONLY")
        XCTAssertEqual(args.getStringArrayList("categories") ?? [], ["GENERAL_KNOWLEDGE", "AI", "MATH"])
        XCTAssertTrue(args.containsKey("room"))
        XCTAssertNil(args.getString("room"))
        XCTAssertEqual(args.getLong("room_started_at"), 1234)
        XCTAssertTrue(args.getBoolean("bot_match"))
        XCTAssertEqual(args.getString("player_character"), "rooza")
        XCTAssertEqual(args.getString("bot_character"), "kyra")
        XCTAssertEqual(args.getLong("seed"), -42)
        XCTAssertEqual(args.getInt("ball_limit"), 7)
        XCTAssertEqual(args.getInt("time_limit_seconds"), 0)
    }

    // MARK: - Style tables (L2993-3025)

    func testQuestionAndAnswerTextSizeTables() {
        let fragment = makeFragment(makeConfig())
        XCTAssertEqual([0, 58, 59, 92, 93, 130, 131, 400].map { fragment.questionTextSizeFor(length: $0) },
                       [Float(18.2), 18.2, 17.2, 17.2, 16.2, 16.2, 15.2, 15.2])
        // base 13.4 / 14.0 / 14.5, then -0.5 above 56 and -1.0 above 82 UTF-16 units (Float arithmetic).
        XCTAssertEqual([56, 57, 82, 83].map { fragment.answerTextSizeFor(length: $0, answerCount: 4) },
                       [Float(13.4), Float(13.4) - 0.5, Float(13.4) - 0.5, Float(13.4) - 1.0])
        XCTAssertEqual([56, 57, 83].map { fragment.answerTextSizeFor(length: $0, answerCount: 3) },
                       [Float(14.0), Float(14.0) - 0.5, Float(14.0) - 1.0])
        XCTAssertEqual([2, 5].map { fragment.answerTextSizeFor(length: 10, answerCount: $0) }, [Float(14.5), 14.5])
    }

    func testAnswerAccentColorsCycleEveryFourAnswers() {
        let fragment = makeFragment(makeConfig())
        let orange = AColor.rgb(232, 137, 31), blue = AColor.rgb(43, 119, 196)
        let magenta = AColor.rgb(181, 66, 146), green = AColor.rgb(35, 145, 94)
        XCTAssertEqual((0..<8).map { fragment.answerAccentColor(index: $0) },
                       [orange, blue, magenta, green, orange, blue, magenta, green])
        // Kotlin `index % 4` of a negative index is negative: the `else` (green) branch.
        XCTAssertEqual(fragment.answerAccentColor(index: -1), green)
    }

    // MARK: - End rules (L3150-3162)

    func testShouldEndNowMatrix() {
        let practice = makeFragment(makeConfig(gameType: .PRACTICE, limitMode: .BALLS_ONLY, ballLimit: 0, timeLimitSeconds: 0))
        practice.secondsLeft = 0
        XCTAssertFalse(practice.shouldEndNow())

        let horse = makeFragment(makeConfig(gameType: .HORSE, limitMode: .BALLS_ONLY, botMatch: true, ballLimit: 0))
        horse.secondsLeft = 0
        XCTAssertFalse(horse.shouldEndNow())

        let timed = makeFragment(makeConfig(limitMode: .TIME_ONLY, ballLimit: 1))
        timed.secondsLeft = 1
        timed.scoring.score(answerQualityPercent: 0, made: false)
        XCTAssertFalse(timed.shouldEndNow())   // TIME_ONLY never ends on balls
        timed.secondsLeft = 0
        XCTAssertTrue(timed.shouldEndNow())

        let balls = makeFragment(makeConfig(gameType: .HORSE, limitMode: .BALLS_ONLY, ballLimit: 2))
        balls.secondsLeft = 0                  // BALLS_ONLY never ends on time
        balls.scoring.score(answerQualityPercent: 100, made: true)
        XCTAssertFalse(balls.shouldEndNow())
        balls.scoring.score(answerQualityPercent: 100, made: true)
        XCTAssertTrue(balls.shouldEndNow())

        let both = makeFragment(makeConfig(limitMode: .RANKED_BOTH, ballLimit: 5))
        both.secondsLeft = 3
        XCTAssertFalse(both.shouldEndNow())
        both.secondsLeft = -1
        XCTAssertTrue(both.shouldEndNow())
    }

    // MARK: - Bot identity (L3387-3407)

    func testCurrentBotProfileNameAndGenderedStrings() {
        let kyra = makeFragment(makeConfig(botMatch: true, botCharacterId: TripleShotCharacterRoster.ID_KYRA))
        XCTAssertEqual(kyra.currentBotDisplayName(), "Gaya")
        XCTAssertEqual(kyra.currentBotGenderedString(maleRes: "m", femaleRes: "f", neutralRes: "n"), "f")

        let bob = makeFragment(makeConfig(botMatch: true, botCharacterId: TripleShotCharacterRoster.ID_BOB))
        XCTAssertEqual(bob.currentBotDisplayName(), "BOB")
        XCTAssertEqual(bob.currentBotGenderedString(maleRes: "m", femaleRes: "f", neutralRes: "n"), "m")

        // An unknown id falls back to BOB (male); `neutralRes` defaults to `maleRes`.
        let unknown = makeFragment(makeConfig(botMatch: true, botCharacterId: "nobody"))
        XCTAssertEqual(unknown.currentBotProfile().id, TripleShotCharacterRoster.ID_BOB)
        XCTAssertEqual(unknown.currentBotGenderedString(maleRes: "m", femaleRes: "f"), "m")
    }

    // MARK: - Tutorial (L3605-3754)

    func testUnlockTutorialStepFollowsOnlyAReaderOnTheLastUnlockedPage() {
        let fragment = makeFragment(makeConfig(gameType: .PRACTICE, limitMode: .BALLS_ONLY))

        fragment.unlockTutorialStep(step: .AIM)                 // inactive: nothing
        XCTAssertEqual(fragment.tutorialProgress, 0)

        fragment.tutorialActive = true
        fragment.unlockTutorialStep(step: .AIM)
        XCTAssertEqual(fragment.tutorialProgress, 1)
        XCTAssertEqual(fragment.tutorialPage, 1)                // was on the last unlocked page: follows

        fragment.tutorialPage = 0                               // the reader went back
        fragment.unlockTutorialStep(step: .THROW)
        XCTAssertEqual(fragment.tutorialProgress, 3)
        XCTAssertEqual(fragment.tutorialPage, 0)                // not yanked forward

        fragment.unlockTutorialStep(step: .PULL_BACK)           // lower than the progress: ignored
        XCTAssertEqual(fragment.tutorialProgress, 3)

        fragment.tutorialPage = 3
        fragment.unlockTutorialStep(step: .FREE_PLAY)
        XCTAssertEqual(fragment.tutorialPage, 4)
    }

    func testTutorialPagesAreHebrewWithTheirButtonStates() {
        setLanguage("en")
        let fragment = makeAttachedFragment(makeConfig(gameType: .PRACTICE, limitMode: .BALLS_ONLY))
        fragment.tutorialCard = AView()
        fragment.tutorialTitle = ATextView()
        fragment.tutorialBody = ATextView()
        fragment.tutorialPrevButton = AButton()
        fragment.tutorialNextButton = AButton()
        fragment.tutorialCard.visibility = AView.GONE

        fragment.startTutorial(replay: false)
        XCTAssertTrue(fragment.tutorialActive)
        XCTAssertEqual(fragment.tutorialCard.visibility, AView.VISIBLE)
        XCTAssertEqual(fragment.tutorialTitle.text, "1/4 \u{2022} בחר תשובה")
        XCTAssertEqual(fragment.tutorialBody.text, "לחץ על התשובה שאתה חושב שנכונה. השחקן יכדרר אוטומטית לעמדת הזריקה שלה.")
        XCTAssertFalse(fragment.tutorialPrevButton.isEnabled)
        XCTAssertEqual(fragment.tutorialPrevButton.getAlpha(), Float(0.35))
        XCTAssertFalse(fragment.tutorialNextButton.isEnabled)
        XCTAssertEqual(fragment.tutorialNextButton.text, "הבא \u{203A}")   // Hebrew even on an English device

        fragment.unlockTutorialStep(step: .AIM)
        XCTAssertEqual(fragment.tutorialTitle.text, "2/4 \u{2022} כוון")
        XCTAssertTrue(fragment.tutorialPrevButton.isEnabled)
        XCTAssertEqual(fragment.tutorialPrevButton.getAlpha(), Float(1))
        XCTAssertFalse(fragment.tutorialNextButton.isEnabled)

        fragment.startTutorial(replay: true)                    // replay unlocks every page, from page 0
        XCTAssertEqual(fragment.tutorialPage, 0)
        XCTAssertEqual(fragment.tutorialProgress, 4)
        XCTAssertTrue(fragment.tutorialNextButton.isEnabled)
        fragment.tutorialPage = 4
        fragment.updateTutorialUi()
        XCTAssertEqual(fragment.tutorialTitle.text, "מעולה \u{1F3AF}")
        XCTAssertEqual(fragment.tutorialNextButton.text, "הבא")
        XCTAssertFalse(fragment.tutorialNextButton.isEnabled)

        fragment.shotInProgress = true                          // no tutorial during a shot
        fragment.tutorialActive = false
        fragment.startTutorial(replay: true)
        XCTAssertFalse(fragment.tutorialActive)
    }

    // MARK: - Tap to continue (L2835-2901)

    func testTapToContinueRunsTheLatestActionOnceAndNeverAfterTheEnd() {
        let fragment = makeFragment(makeConfig())
        fragment.feedbackText = ATextView()
        var runs: [String] = []

        fragment.waitForTapToContinue { runs.append("first") }
        XCTAssertTrue(fragment.feedbackShowing)
        fragment.waitForTapToContinue { runs.append("second") }   // a second wait overwrites the action
        fragment.feedbackText.visibility = AView.VISIBLE
        fragment.continueAfterFeedback()
        XCTAssertEqual(runs, ["second"])
        XCTAssertFalse(fragment.feedbackShowing)
        XCTAssertNil(fragment.feedbackContinueAction)
        XCTAssertEqual(fragment.feedbackText.visibility, AView.GONE)

        fragment.continueAfterFeedback()                          // nothing armed
        XCTAssertEqual(runs, ["second"])

        fragment.waitForTapToContinue { runs.append("third") }
        fragment.ended = true
        fragment.continueAfterFeedback()                          // ignored once the game has ended
        XCTAssertEqual(runs, ["second"])
    }

    func testTapOverlayIsInstalledOnceAsTheLastFullScreenChildWithAnExitLink() {
        setLanguage("en")
        let fragment = makeAttachedFragment(makeConfig())
        fragment.feedbackText = ATextView()
        let root = AConstraintLayout()
        root.addView(AView())

        fragment.installTapToContinueOverlay(root: root)
        guard let overlay = fragment.feedbackTapOverlay as? AFrameLayout else { return XCTFail("no overlay") }
        XCTAssertEqual(root.childCount, 2)
        XCTAssertTrue(root.getChildAt(1) === overlay)
        XCTAssertEqual(overlay.visibility, AView.GONE)
        XCTAssertTrue(overlay.isClickable)
        let params = overlay.layoutParams as? AConstraintLayout.LayoutParams
        XCTAssertEqual(params?.width, 0)
        XCTAssertEqual(params?.height, 0)
        XCTAssertEqual(params?.startToStart, AConstraintLayout.LayoutParams.PARENT_ID)
        XCTAssertEqual(params?.endToEnd, AConstraintLayout.LayoutParams.PARENT_ID)
        XCTAssertEqual(params?.topToTop, AConstraintLayout.LayoutParams.PARENT_ID)
        XCTAssertEqual(params?.bottomToBottom, AConstraintLayout.LayoutParams.PARENT_ID)

        let exit = overlay.getChildAt(0) as? ATextView
        XCTAssertEqual(exit?.text, "Exit game")
        XCTAssertEqual(exit?.paint.isUnderlineText, true)
        XCTAssertEqual(exit?.currentTextColor, AColor.WHITE)
        let exitParams = exit?.layoutParams as? AFrameLayout.LayoutParams
        XCTAssertEqual(exitParams?.gravity, AGravity.TOP | AGravity.END)
        XCTAssertEqual(exitParams?.topMargin, fragment.dp(v: 28))
        XCTAssertEqual(exitParams?.marginEnd, fragment.dp(v: 12))

        fragment.installTapToContinueOverlay(root: root)        // installed once
        XCTAssertEqual(root.childCount, 2)

        var continued = 0
        fragment.waitForTapToContinue { continued += 1 }
        XCTAssertEqual(overlay.visibility, AView.VISIBLE)
        overlay.performClick()
        XCTAssertEqual(continued, 1)
        XCTAssertEqual(overlay.visibility, AView.GONE)

        exit?.performClick()                                    // the overlay's own exit link: leaveGameToHome()
        XCTAssertTrue(fragment.ended)
    }

    // MARK: - HORSE texts (L2292-2461)

    func testHorseResolutionShortTextsInBothLanguages() {
        let resolution = { (type: HorseGameEngine.ResultType) -> HorseGameEngine.Resolution in
            HorseGameEngine.Resolution(
                type: type, actor: .HUMAN, answerCorrect: true, made: true, penaltyAdded: false,
                state: HorseGameEngine(firstSetter: .HUMAN).snapshot()
            )
        }
        setLanguage("en")
        let fragment = makeAttachedFragment(makeConfig(gameType: .HORSE, limitMode: .BALLS_ONLY, botMatch: true))
        XCTAssertEqual(HorseGameEngine.ResultType.allCases.map { fragment.horseResolutionShortText(resolution: resolution($0)) },
                       ["Challenge!", "Not set", "Continue", "+1 \u{2022} continue", "Challenge ended", "+1 \u{2022} ended",
                        "Game over"])
        setLanguage("he")
        XCTAssertEqual(fragment.horseResolutionShortText(resolution: resolution(.CHALLENGE_ESTABLISHED)), "חיוב!")
        XCTAssertEqual(fragment.horseResolutionShortText(resolution: resolution(.CONTINUE_WITH_PENALTY)), "+1 \u{2022} ממשיכים")
        XCTAssertEqual(fragment.horseResolutionShortText(resolution: resolution(.GAME_OVER)), "סיום")
    }

    /// Android 6c38131: five rows (answer, the correct answer, the shot, the resolution, the tap hint), the first,
    /// third and fifth centred by AlignmentSpan.Standard, the others ALIGN_NORMAL.
    func testHorseReadableAttemptFeedbackComposesFiveAlignedRows() throws {
        setLanguage("he")
        let fragment = makeAttachedFragment(
            makeConfig(gameType: .HORSE, limitMode: .BALLS_ONLY, botMatch: true, botCharacterId: TripleShotCharacterRoster.ID_KYRA)
        )
        let state = HorseGameEngine(firstSetter: .HUMAN).snapshot()

        // Human, wrong + missed: the correct-answer text is used as given (no blank fallback any more).
        let human = HorseGameEngine.Resolution(type: .CHALLENGE_ENDED_WITH_PENALTY, actor: .HUMAN, answerCorrect: false,
                                               made: false, penaltyAdded: true, state: state)
        let humanText = fragment.horseReadableAttemptFeedback(actor: .HUMAN, answerCorrect: false, made: false,
                                                              correctAnswerText: " ", resolution: human)
        XCTAssertEqual(
            humanText.aw_plain,
            "\u{2717} תשובה שגויה\n" +
                "התשובה הנכונה:  \n" +
                "\u{2717} החטאה\n" +
                "טעיתם והחטאתם \u{2014} קיבלתם סימון והחיוב נגמר.\n" +
                "לחצו בכל מקום כדי להמשיך"
        )
        let spans = try XCTUnwrap(humanText as? ASpannableString).spans
        XCTAssertEqual(spans.count, 5)
        XCTAssertEqual(spans.map { ($0.span as? AAlignmentSpan.Standard)?.getAlignment() },
                       [.ALIGN_CENTER, .ALIGN_NORMAL, .ALIGN_CENTER, .ALIGN_NORMAL, .ALIGN_CENTER])
        let rows = humanText.aw_plain.components(separatedBy: "\n")
        var offset = 0
        for (row, span) in zip(rows, spans) {
            XCTAssertEqual(span.start, offset)
            XCTAssertEqual(span.end, offset + row.utf16.count)
            XCTAssertEqual(span.flags, ASpanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            offset += row.utf16.count + 1
        }

        // Bot (Gaya, female), correct + made, setter: the female strings with the bot's name.
        let bot = HorseGameEngine.Resolution(type: .CHALLENGE_ESTABLISHED, actor: .BOT, answerCorrect: true, made: true,
                                             penaltyAdded: false, state: state)
        XCTAssertEqual(
            fragment.horseReadableAttemptFeedback(actor: .BOT, answerCorrect: true, made: true, correctAnswerText: "x",
                                                  resolution: bot).aw_plain,
            "\u{2713} תשובה נכונה\nהתשובה הנכונה: x\n\u{2713} סל!\nGaya קבעה חיוב. עכשיו אתה צריך לעמוד בו.\n"
                + "לחצו בכל מקום כדי להמשיך"
        )

        // GAME_OVER follows the winner, not the actor.
        var humanWins = state
        humanWins.winner = .HUMAN
        let over = HorseGameEngine.Resolution(type: .GAME_OVER, actor: .BOT, answerCorrect: false, made: true,
                                              penaltyAdded: true, state: humanWins)
        XCTAssertEqual(fragment.horseResolutionLongText(actor: .BOT, resolution: over), "ניצחת את Gaya בחיובים! \u{1F3C6}")
        var botWins = state
        botWins.winner = .BOT
        let lost = HorseGameEngine.Resolution(type: .GAME_OVER, actor: .HUMAN, answerCorrect: false, made: false,
                                              penaltyAdded: true, state: botWins)
        XCTAssertEqual(fragment.horseResolutionLongText(actor: .HUMAN, resolution: lost), "Gaya ניצחה")
    }

    // MARK: - Practice / Challenge feedback (L2697-2746)

    func testBuildFeedbackJoinsThePartsWithThreeSpacesAndTheHint() {
        setLanguage("en")
        let fragment = makeAttachedFragment(makeConfig())
        let q = reviewQuestion()
        XCTAssertEqual(
            fragment.buildFeedback(q: q, quality: 100, shotResult: shot(.RIM_IN, made: true), points: 9, multiplier: 2),
            "\u{2705} Correct \u{2022} \u{1F9E0} x2   \u{1F3C0} Rim and in!   +9\nWater is H2O.\n\nTap anywhere to continue"
        )
        XCTAssertEqual(
            fragment.buildFeedback(q: q, quality: 50, shotResult: shot(.SWISH, made: true), points: 3, multiplier: 1),
            "\u{1F7E1} Partially correct (50%)   \u{1F3C0} SWISH!   +3\nWater is H2O.\n\nTap anywhere to continue"
        )
        // Wrong: the first answer with the highest quality ("Water", not "Steam").
        XCTAssertEqual(
            fragment.buildFeedback(q: q, quality: 0, shotResult: shot(.INVALID_BELOW, made: false), points: 0, multiplier: 1),
            "\u{274C} Incorrect \u{2022} Correct: Water   \u{1F3C0} No basket \u{2014} the ball entered from below   +0\n" +
                "Water is H2O.\n\nTap anywhere to continue"
        )
        setLanguage("he")
        XCTAssertEqual(fragment.tapToContinueHint(), "לחצו בכל מקום כדי להמשיך")
    }

    // MARK: - Answer review (L2020-2136)

    func testShowAnswerReviewMarksTheCorrectAnswerAndAWrongPick() {
        setLanguage("en")
        let fragment = makeAttachedFragment(makeConfig())
        fragment.answerStrip = ALinearLayout()
        let q = reviewQuestion()

        fragment.showAnswerReview(question: q, selectedIndex: 2)   // builds the rows (none existed)
        XCTAssertEqual(fragment.answerViews.map { $0.text }, ["A. Ice", "B. \u{2713} Water", "C. \u{2717} Steam"])
        XCTAssertEqual(fragment.answerViews.map { $0.getAlpha() }, [Float(0.82), 1, 1])
        XCTAssertEqual(fragment.answerViews.map { $0.isClickable }, [false, false, false])
        XCTAssertEqual(fill(fragment.answerViews[1].background), AColor.argb(238, 232, 250, 238))
        XCTAssertEqual(fill(fragment.answerViews[2].background), AColor.argb(236, 255, 236, 232))
        XCTAssertEqual(fill(fragment.answerViews[0].background), AColor.argb(214, 255, 252, 242))

        // A graded question (no 100 % answer): no review at all.
        let graded = TripleShotQuestion(id: "g", category: .PROGRAMMING, prompt: "?",
                                        answers: [AnswerOption(text: "x", qualityPercent: 60),
                                                  AnswerOption(text: "y", qualityPercent: 90)],
                                        explanation: "")
        fragment.showAnswerReview(question: graded, selectedIndex: 0)
        XCTAssertEqual(fragment.answerViews.count, 3)
    }

    func testShowHorseAnswerReviewNeverRevealsTheBotsPick() {
        setLanguage("en")
        let fragment = makeAttachedFragment(makeConfig(gameType: .HORSE, limitMode: .BALLS_ONLY, botMatch: true))
        fragment.answerStrip = ALinearLayout()
        let q = reviewQuestion()
        fragment.selectedAnswerIndex = 2

        fragment.showHorseAnswerReview(question: q, actor: .BOT, answerCorrect: false)
        XCTAssertEqual(fragment.answerViews.map { $0.text }, ["A. Ice", "B. \u{2713} Water", "C. Steam"])

        fragment.showHorseAnswerReview(question: q, actor: .HUMAN, answerCorrect: false)
        XCTAssertEqual(fragment.answerViews.map { $0.text }, ["A. Ice", "B. \u{2713} Water", "C. \u{2717} Steam"])

        fragment.showHorseAnswerReview(question: q, actor: .HUMAN, answerCorrect: true)
        XCTAssertEqual(fragment.answerViews.map { $0.text }, ["A. Ice", "B. \u{2713} Water", "C. Steam"])
    }

    // MARK: - HUD (L3062-3147)

    func testUpdateHudTextsPerMode() {
        setLanguage("en")

        let practice = makeAttachedFragment(makeConfig(gameType: .PRACTICE, limitMode: .BALLS_ONLY,
                                                       ballLimit: Int(Int32.max), timeLimitSeconds: 0))
        installHud(practice)
        practice.scoring.score(answerQualityPercent: 100, made: true)
        practice.updateHud()
        XCTAssertEqual(practice.timeText.text, "Practice")
        XCTAssertEqual(practice.scoreText.text, "Score 9")
        XCTAssertEqual(practice.botScoreText.visibility, AView.GONE)
        XCTAssertEqual(practice.ballsText.visibility, AView.VISIBLE)
        XCTAssertEqual(practice.ballsText.text, "זריקות 1")            // Hebrew in every locale
        XCTAssertEqual(practice.streakText.text, "\u{1F9E0} 1    \u{1F3C0} 1")

        let challenge = makeAttachedFragment(makeConfig(botMatch: true, botCharacterId: TripleShotCharacterRoster.ID_KYRA))
        installHud(challenge)
        challenge.secondsLeft = -3
        challenge.updateHud()
        XCTAssertEqual(challenge.timeText.text, "\u{23F1} 0")
        XCTAssertEqual(challenge.scoreText.text, "You 0")
        XCTAssertEqual(challenge.botScoreText.visibility, AView.VISIBLE)
        XCTAssertEqual(challenge.botScoreText.text, "Gaya 0")
        XCTAssertEqual(challenge.ballsText.visibility, AView.GONE)

        let quirk = makeAttachedFragment(makeConfig(gameType: .HORSE, limitMode: .BALLS_ONLY, ballLimit: Int(Int32.max)))
        installHud(quirk)
        quirk.updateHud()
        XCTAssertEqual(quirk.timeText.text, "\u{23F1} --")
        XCTAssertEqual(quirk.scoreText.text, "Score 0")
        XCTAssertEqual(quirk.ballsText.text, "\u{1F3C0} 0/2147483647")

        let horse = makeAttachedFragment(makeConfig(gameType: .HORSE, limitMode: .BALLS_ONLY, botMatch: true,
                                                    botCharacterId: TripleShotCharacterRoster.ID_KYRA))
        installHud(horse)
        horse.horseEngine = HorseGameEngine(firstSetter: .HUMAN)
        horse.horseTurnMessage = "turn"
        horse.updateHud()
        XCTAssertEqual(horse.timeText.text, "HORSE")
        XCTAssertEqual(horse.scoreText.text, "You 0/5")
        XCTAssertEqual(horse.botScoreText.visibility, AView.VISIBLE)
        XCTAssertEqual(horse.botScoreText.text, "Gaya 0/5")
        XCTAssertEqual(horse.streakText.text, "turn")
        XCTAssertEqual(horse.ballsText.visibility, AView.GONE)
        setLanguage("he")
        horse.updateHud()
        XCTAssertEqual(horse.timeText.text, "חיובים")
        XCTAssertEqual(horse.scoreText.text, "אני 0/5")

        setLanguage("en")
        let live = makeAttachedFragment(makeConfig(gameType: .HORSE, limitMode: .BALLS_ONLY, roomId: "ROOM42"))
        installHud(live)
        live.updateHud()
        XCTAssertEqual(live.streakText.text, "Connecting\u{2026}")
        live.latestLivePlayers = [LivePlayerState(uid: "other-player", name: " ")]
        live.liveHorseState = LiveHorseState(currentPlayerUid: "other-player")
        live.updateHud()
        XCTAssertEqual(live.streakText.text, "Player's turn")
        XCTAssertEqual(live.scoreText.text, "You 0/5")
        live.liveHorseState = LiveHorseState(currentPlayerUid: "other-player", winnerUid: "other-player")
        live.updateHud()
        XCTAssertEqual(live.streakText.text, "Match finished")
    }

    // MARK: - End of game and Live result (L3190-3380)

    func testEndGameRoundsHalfUpAndShowsThePracticeRankText() {
        setLanguage("en")
        let fragment = makeAttachedFragment(makeConfig(gameType: .PRACTICE, limitMode: .BALLS_ONLY))
        fragment.sensor = TripleShotSensorController(context: nil, listener: fragment)
        fragment.questionCard = AView()
        fragment.answerStrip = ALinearLayout()
        fragment.feedbackText = ATextView()
        fragment.tutorialCard = AView()
        fragment.resultOverlay = AView()
        fragment.resultScoreText = ATextView()
        fragment.resultStatsText = ATextView()
        fragment.resultRankText = ATextView()
        fragment.resultOverlay.visibility = AView.GONE
        fragment.tutorialActive = true
        fragment.feedbackContinueAction = {}

        fragment.scoring.score(answerQualityPercent: 100, made: false)
        for _ in 0..<7 { fragment.scoring.score(answerQualityPercent: 0, made: false) }   // 1/8 = 12.5 % -> 13 %

        fragment.endGame()
        XCTAssertTrue(fragment.ended)
        XCTAssertNil(fragment.feedbackContinueAction)
        XCTAssertFalse(fragment.tutorialActive)
        XCTAssertEqual(fragment.questionCard.visibility, AView.GONE)
        XCTAssertEqual(fragment.tutorialCard.visibility, AView.GONE)
        XCTAssertEqual(fragment.resultOverlay.visibility, AView.VISIBLE)
        XCTAssertEqual(fragment.resultScoreText.text, "6")
        XCTAssertEqual(fragment.resultStatsText.text,
                       "\u{1F9E0} Answers: 13% (1/8)\n\u{1F3C0} Baskets: 0% (0/8)\n\u{1F525} Best answer streak: 1 \u{2022} Basket streak: 0")
        XCTAssertEqual(fragment.resultRankText.text, "מצב אימון \u{2014} לא נכנס לדירוג")   // Hebrew in every locale

        fragment.resultRankText.text = "unchanged"
        fragment.endGame()                                                       // only once
        XCTAssertEqual(fragment.resultRankText.text, "unchanged")
    }

    func testRenderLiveResultSortsStablyAndKeepsTheTopFour() {
        let fragment = makeFragment(makeConfig(playerName: "Me", roomId: "ROOM42"))
        fragment.resultRankText = ATextView()
        fragment.scoring.score(answerQualityPercent: 100, made: true)            // 3 x 2 + 3 = 9 points
        XCTAssertEqual(fragment.scoring.totalScore, 9)
        fragment.latestLivePlayers = [
            LivePlayerState(uid: "a", name: "Ada", score: 5),
            LivePlayerState(uid: "b", name: "", score: 9),
            LivePlayerState(uid: "c", name: "Cy", score: 12),
            LivePlayerState(uid: "d", name: "Dov", score: 5),
            LivePlayerState(uid: "e", name: "Eli", score: 1)
        ]
        fragment.renderLiveResult()
        // Equal scores keep the listener order, with me (appended last) after the others.
        XCTAssertEqual(fragment.resultRankText.text,
                       "1. Cy \u{2014} 12   \u{2022}   2. Player \u{2014} 9   \u{2022}   3. Me \u{2014} 9   \u{2022}   4. Ada \u{2014} 5")

        let solo = makeFragment(makeConfig(roomId: nil))
        solo.resultRankText = ATextView()
        solo.resultRankText.text = "kept"
        solo.renderLiveResult()                                                  // not Live: untouched
        XCTAssertEqual(solo.resultRankText.text, "kept")
    }

    // MARK: - HORSE questions (L2138-2161)

    func testNextHorseQuestionSeedsEveryTurnAndRemembersTheLastEightIds() {
        withQuestionPrefs {
            setLanguage("he")
            getSharedPreferences(Game2Tests.QUESTION_PREFS, MODE_PRIVATE).edit().putBoolean("adaptive_intro_shown", true).commit()
            TripleShotQuestionRepository.initialize(context: AApplication.shared)

            let fragment = makeFragment(makeConfig(gameType: .HORSE, limitMode: .BALLS_ONLY, botMatch: true,
                                                   seed: 1_700_000_000_000))
            let english = KLinkedSet([QuestionCategory.ENGLISH])

            // counter 1: 1700000000000 xor 0x9E3779B9 xor 7 = 1697884803518
            let first = fragment.nextHorseQuestion(category: .ENGLISH)
            XCTAssertEqual(fragment.horseQuestionCounter, 1)
            XCTAssertEqual(first.id, TripleShotQuestionRepository.shuffled(seed: 1_697_884_803_518, categories: english).first().id)
            XCTAssertEqual(fragment.horseRecentQuestionIds, [first.id])

            // counter 2: 1700000000000 xor (2 * 0x9E3779B9) xor 7 = 1696303127413; the first id is skipped.
            let second = fragment.nextHorseQuestion(category: .ENGLISH)
            let expectedSecond = TripleShotQuestionRepository.shuffled(seed: 1_696_303_127_413, categories: english)
                .firstOrNull { $0.id != first.id }
            XCTAssertEqual(second.id, expectedSecond?.id)

            var chosen = [first.id, second.id]
            for _ in 0..<10 { chosen.append(fragment.nextHorseQuestion(category: .ENGLISH).id) }
            XCTAssertEqual(fragment.horseQuestionCounter, 12)
            XCTAssertEqual(fragment.horseRecentQuestionIds, Array(chosen.suffix(8)))
            for i in 1..<chosen.count {
                XCTAssertFalse(chosen[max(0, i - 8)..<i].contains(chosen[i]), "repeat within the last 8 at \(i)")
            }

            // A negative room seed (Kotlin Long xor keeps the sign): counter 1, KIDS_ARITHMETIC (ordinal 8).
            let negative = makeFragment(makeConfig(gameType: .HORSE, limitMode: .BALLS_ONLY, botMatch: true,
                                                   seed: -5_000_000_000_000))
            XCTAssertEqual(
                negative.nextHorseQuestion(category: .KIDS_ARITHMETIC).id,
                TripleShotQuestionRepository.shuffled(seed: -5_002_446_648_911,
                                                      categories: KLinkedSet([QuestionCategory.KIDS_ARITHMETIC])).first().id
            )
        }
    }
}
