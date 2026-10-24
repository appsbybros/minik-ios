import Foundation
import XCTest
@testable import MinikTripleShot

// Parity tests for area s-one2 (spec 16-one2): TripleShotOneOnOneFragment.kt lines 1795-3467, part 2 of the split
// class (TripleShotOneOnOneFragment+Part2.swift). Pure helpers only: nothing here needs the court, the views or a
// running looper.
//
// Golden vectors come from the snapshot's own Kotlin (dd722e5) run on the JVM with kotlin-stdlib 2.3.21: the model
// files compiled unchanged plus verbatim copies of the fragment's helper bodies and companion constants
// (work/s-one2/harness/src/OneOnOne2Harness.kt + Consts.kt, output golden.txt). They reproduce every number of
// spec 16 section 7.6 (XorWow draws, Java String hashes, salt decimals, the startBotAttack and question-race
// worked examples) and section 7.5 (effective dunk / block ratings of the roster).
// Covered: every companion constant (bit-exact Floats), BOT_DUMMY_QUESTION, newInstance arguments,
// effectiveDunkAbility, effectiveBlock, pointsFor, chooseBotQuizAnswerIndex (every roster bot, answer shapes,
// exclusion sets, draw counts), botQuizDelayMs, botQuizRetryDelayMs, botQuestionCorrectDeadlineMs, the race
// schedule as scheduleBotQuestionAttempt drives those helpers (choice before delay from one generator, wrong picks
// excluded), forceBotRaceResolutionIfDeadlinePassed (fake clock), the gendered string choice, isRtlUi,
// bidiSafeName, formatBotScoreText and bidiSafeQuestionPrompt (ICU regex semantics, as Android's ICU-backed
// java.util.regex).
// Not covered here (they need the court and the views): the ball-state handler, the bot attack / search loops,
// botShoot, the HUD, the result overlay and the rematch.

final class OneOnOneTests: XCTestCase {

    private typealias F = TripleShotOneOnOneFragment

    private static let SPEC_SEED: Int64 = 1_700_000_000_123
    private static let LRI = "\u{2066}"
    private static let PDI = "\u{2069}"

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
        AFakeClock.uninstall()
        super.tearDown()
    }

    // MARK: - Helpers

    /// A detached fragment (no host, no views): enough for the helpers that read only `seed` and the profiles.
    private func makeFragment(seed: Int64 = OneOnOneTests.SPEC_SEED,
                              bot: String = TripleShotCharacterRoster.ID_WOMAN_DARK) -> TripleShotOneOnOneFragment {
        let fragment = TripleShotOneOnOneFragment()
        fragment.seed = seed
        fragment.humanProfile = TripleShotCharacterRoster.womanDark
        fragment.botProfile = TripleShotCharacterRoster.find(id: bot)!
        return fragment
    }

    /// A fragment with a bare host, so `isAdded` and `resources` (the configuration locale) work like on Android.
    private func makeAttachedFragment(bot: String = TripleShotCharacterRoster.ID_WOMAN_DARK) -> TripleShotOneOnOneFragment {
        let fragment = makeFragment(bot: bot)
        fragment.mHost = AActivity()
        fragment.mAdded = true
        return fragment
    }

    /// `configuration.locales[0]` (isRtlUi) and the values/ or values-en/ string table.
    private func setLanguage(_ language: String) {
        let base = AConfiguration.current
        AConfiguration.current = AConfiguration(
            orientation: base.orientation, screenWidthDp: base.screenWidthDp, screenHeightDp: base.screenHeightDp,
            smallestScreenWidthDp: base.smallestScreenWidthDp, densityDpi: base.densityDpi, fontScale: base.fontScale,
            uiMode: base.uiMode, locales: ALocaleList([ALocale(language)]))
        AResources.languageOverride = language == "en" ? "en" : "he"
    }

    /// The harness's question shape: answers "a0", "a1", ... with the given qualities.
    private func question(_ id: String, _ qualities: [Int]) -> TripleShotQuestion {
        return TripleShotQuestion(
            id: id,
            category: QuestionCategory.GENERAL_KNOWLEDGE,
            prompt: "",
            answers: qualities.enumerated().map { AnswerOption(text: "a" + String($0.offset), qualityPercent: $0.element) },
            explanation: ""
        )
    }

    private func rows(_ data: String) -> [[String]] {
        return data.split(whereSeparator: { $0.isNewline }).map { $0.split(separator: " ").map(String.init) }
    }

    private func ints(_ s: String) -> [Int] {
        if s == "-" { return [] }
        return s.split(separator: ",").map { Int($0)! }
    }

    private func bits(_ hex: String) -> UInt32 {
        return UInt32(hex.dropFirst(2), radix: 16)!
    }

    // MARK: - Kotlin Random and Java hashes (spec 16 section 7.6)

    func testKotlinRandomGoldenVectorsOfSpec16() {
        // seed: nextBits(24) x3 | nextFloat x3 (bits) | nextBoolean x6 | nextLong() x2   (fresh generator per group)
        let rows: [(Int64, [Int32], [UInt32], String, [Int64])] = [
            (0, [9221314, 5504686, 14241431], [0x3f0cb4c2, 0x3ea7fd5c, 0x3f594e97], "TFTTTF",
             [-8307801916948173232, -2788124325695296738]),
            (1_700_000_000_123, [989136, 13327263, 3713536], [0x3d717d00, 0x3f4b5b9f, 0x3e62a800], "FTFTFF",
             [1087567181108715433, 4083076968669792109]),
        ]
        for (seed, expectedBits, expectedFloats, expectedBools, expectedLongs) in rows {
            var r = KotlinRandom(seed: seed)
            XCTAssertEqual((0..<3).map { _ in r.nextBits(24) }, expectedBits, "seed \(seed)")
            r = KotlinRandom(seed: seed)
            XCTAssertEqual((0..<3).map { _ in r.nextFloat().bitPattern }, expectedFloats, "seed \(seed)")
            r = KotlinRandom(seed: seed)
            XCTAssertEqual((0..<6).map { _ in r.nextBoolean() ? "T" : "F" }.joined(), expectedBools, "seed \(seed)")
            r = KotlinRandom(seed: seed)
            XCTAssertEqual((0..<2).map { _ in r.nextLong() }, expectedLongs, "seed \(seed)")
        }
        // The spec's decimal floats are these bit patterns.
        XCTAssertEqual(Float(0.54963315).bitPattern, 0x3f0cb4c2)
        XCTAssertEqual(Float(0.0589571).bitPattern, 0x3d717d00)
    }

    func testKotlinRandomJitterRangesOfSpec16() {
        // seed: nextLong(-420, 421) x3 | nextLong(-260, 261) x3 | nextLong(-900, 901) x3 | nextInt(100) x4
        let rows: [(Int64, [Int64], [Int64], [Int64], [Int])] = [
            (0, [-19, 383, 396], [-42, -51, -41], [-133, 277, 773], [14, 48, 57, 67]),
            (1_700_000_000_123, [313, -30, -49], [-37, 253, -103], [-460, 438, 601], [83, 48, 19, 30]),
        ]
        for (seed, j420, j260, j900, i100) in rows {
            var r = KotlinRandom(seed: seed)
            XCTAssertEqual((0..<3).map { _ in r.nextLong(-420, 421) }, j420, "seed \(seed)")
            r = KotlinRandom(seed: seed)
            XCTAssertEqual((0..<3).map { _ in r.nextLong(-260, 261) }, j260, "seed \(seed)")
            r = KotlinRandom(seed: seed)
            XCTAssertEqual((0..<3).map { _ in r.nextLong(-900, 901) }, j900, "seed \(seed)")
            r = KotlinRandom(seed: seed)
            XCTAssertEqual((0..<4).map { _ in r.nextInt(100) }, i100, "seed \(seed)")
        }
    }

    func testJavaStringHashCodesUsedByTheRaceSeeds() {
        XCTAssertEqual("q-1".javaHashCode, 110037)
        XCTAssertEqual("one_on_one".javaHashCode, 36393983)
        XCTAssertEqual("".javaHashCode, 0)
        XCTAssertEqual("general_knowledge_easy_017".javaHashCode, 371357681)
        // A Hebrew id: the hash runs over UTF-16 units.
        XCTAssertEqual("\u{05E9}\u{05D0}\u{05DC}\u{05D4}-7".javaHashCode, 1786553513)
        // `.toLong()` sign-extends.
        XCTAssertEqual(Int32(-5).toLong(), Int64(-5))
    }

    // MARK: - Companion object (L3305-3466)

    func testSaltDecimalsOfSpec16() {
        XCTAssertEqual(F.BOT_BRAIN_SEED_SALT, 3553144604491469900)
        XCTAssertEqual(F.BOT_ATTACK_SEED_SALT, 3553144604475020363)
        XCTAssertEqual(F.HUMAN_SHOT_ROLL_SALT, 6001133726880582977)
        XCTAssertEqual(F.BOT_SHOT_ROLL_SALT, 6001133726779528275)
        XCTAssertEqual(F.BOT_QUESTION_ATTEMPT_SEED_SALT, 5860671142084498509)
        XCTAssertEqual(F.BOT_FAKE_READ_SEED_SALT, 5062410217246245188)
        XCTAssertEqual(F.BOT_REAL_SHOT_READ_SEED_SALT, 5928216280573693780)
        XCTAssertEqual(F.QUESTION_SEED_SALT, 3555083181248303956)
        XCTAssertEqual(F.QUESTION_RESPONSE_SEED_SALT, 5928236088896148293)
    }

    /// Every `private const val` of the companion object, with the JVM's values (Float bit patterns).
    func testCompanionConstantsMatchKotlin() {
        XCTAssertEqual(F.ARG_PLAYER_NAME as String, "one_on_one_player_name")
        XCTAssertEqual(F.ARG_HUMAN_CHARACTER_ID as String, "one_on_one_human_character")
        XCTAssertEqual(F.ARG_BOT_CHARACTER_ID as String, "one_on_one_bot_character")
        XCTAssertEqual(F.ARG_GAME_ORIENTATION as String, "one_on_one_game_orientation")
        XCTAssertEqual(F.ARG_COURT_ID as String, "one_on_one_court_id")
        XCTAssertEqual(F.ARG_SEED as String, "one_on_one_seed")
        XCTAssertEqual(F.ARG_CATEGORIES as String, "one_on_one_categories")
        XCTAssertEqual(F.SCORE_TO_WIN as Int, 11)
        XCTAssertEqual(F.POSSESSION_HANDOFF_MS as Int64, 560)
        XCTAssertEqual(F.BOT_POSSESSION_SETTLE_MS as Int64, 520)
        XCTAssertEqual(F.BOT_DECISION_PAUSE_MS as Int64, 330)
        XCTAssertEqual(F.BOT_ATTACK_TICK_MS as Int64, 48)
        XCTAssertEqual(F.BOT_OPEN_LANE_MAX_ATTACK_MS as Int64, 4200)
        XCTAssertEqual(F.DEAD_BALL_RESET_MS as Int64, 620)
        XCTAssertEqual(F.BOT_BRAIN_SEED_SALT as Int64, 3553144604491469900)
        XCTAssertEqual(F.BOT_ATTACK_SEED_SALT as Int64, 3553144604475020363)
        XCTAssertEqual(F.CROSSOVER_GESTURE_WINDOW_MS as Int64, 620)
        XCTAssertEqual((F.CROSSOVER_MIN_SEGMENT_DP as Float).bitPattern, 0x40e00000)   // 7.0f
        XCTAssertEqual(F.CROSSOVER_REQUIRED_CHANGES as Int, 2)
        XCTAssertEqual(F.HESITATION_GESTURE_WINDOW_MS as Int64, 620)
        XCTAssertEqual((F.HESITATION_MIN_SEGMENT_DP as Float).bitPattern, 0x40e00000)   // 7.0f
        XCTAssertEqual((F.PUMP_FAKE_ARM_PULL as Float).bitPattern, 0x3eb851ec)   // 0.36f
        XCTAssertEqual((F.PUMP_FAKE_RETURN_PULL as Float).bitPattern, 0x3e051eb8)   // 0.13f
        XCTAssertEqual(F.PUMP_FAKE_MIN_GAP_MS as Int64, 280)
        XCTAssertEqual((F.HOLD_VISUAL_LOW_PULL as Float).bitPattern, 0x3ca3d70a)   // 0.02f
        XCTAssertEqual((F.HOLD_VISUAL_MID_PULL_START as Float).bitPattern, 0x3dcccccd)   // 0.1f
        XCTAssertEqual((F.HOLD_VISUAL_MID_PULL_END as Float).bitPattern, 0x3edc28f6)   // 0.43f
        XCTAssertEqual((F.HOLD_VISUAL_SET_PULL_START as Float).bitPattern, 0x3f051eb8)   // 0.52f
        XCTAssertEqual((F.HOLD_VISUAL_SET_PULL_END as Float).bitPattern, 0x3f3851ec)   // 0.72f
        XCTAssertEqual(F.HELD_DOUBLE_TAP_MAX_GAP_MS as Int64, 280)
        XCTAssertEqual(F.HELD_SINGLE_TAP_DELAY_MS as Int64, 245)
        XCTAssertEqual((F.HOLD_FAKE_SET_PULL as Float).bitPattern, 0x3f3851ec)   // 0.72f
        XCTAssertEqual(F.HOLD_FAKE_UP_MS as Int64, 145)
        XCTAssertEqual((F.HOLD_RELEASE_MID_PULL as Float).bitPattern, 0x3ef5c28f)   // 0.48f
        XCTAssertEqual((F.HOLD_RELEASE_SET_PULL as Float).bitPattern, 0x3f428f5c)   // 0.76f
        XCTAssertEqual(F.HOLD_RELEASE_SET_AT_MS as Int64, 130)
        XCTAssertEqual(F.HOLD_RELEASE_TOTAL_MS as Int64, 290)
        XCTAssertEqual((F.HOLD_SHOT_BASE_VARIANCE as Float).bitPattern, 0x3c03126f)   // 0.008f
        XCTAssertEqual((F.HOLD_SHOT_RATING_VARIANCE as Float).bitPattern, 0x3cd4fdf4)   // 0.026f
        XCTAssertEqual(F.SHOT_METER_TICK_MS as Int64, 48)
        XCTAssertEqual(F.SHOT_METER_SETTLE_MS as Int64, 520)
        XCTAssertEqual(F.SHOT_METER_FINISH_SETTLE_MS as Int64, 330)
        XCTAssertEqual(F.SHOT_METER_POSE_TO_SET_MS as Int64, 520)
        XCTAssertEqual(F.SHOT_METER_FINISH_POSE_TO_SET_MS as Int64, 360)
        XCTAssertEqual(F.MIN_SHOT_CHANCE_PERCENT as Int, 8)
        XCTAssertEqual(F.MAX_SHOT_CHANCE_PERCENT as Int, 95)
        XCTAssertEqual(F.BOT_OPEN_FINISH_MAX_CHANCE_PERCENT as Int, 99)
        XCTAssertEqual((F.BOT_JUMPER_FLOW_PENALTY as Float).bitPattern, 0x40400000)   // 3.0f
        XCTAssertEqual(F.BOT_MIN_ACCEPTABLE_JUMPER_CHANCE as Int, 57)
        XCTAssertEqual(F.BOT_MAX_BETTER_SHOT_SEARCHES as Int, 3)
        XCTAssertEqual(F.BOT_BETTER_SHOT_SEARCH_STEPS as Int, 14)
        XCTAssertEqual(F.BOT_BETTER_SHOT_HARD_MAX_STEPS as Int, 54)
        XCTAssertEqual(F.BOT_BETTER_SHOT_SEARCH_TICK_MS as Int64, 46)
        XCTAssertEqual((F.SHOT_ESCAPE_DRAG_DP as Float).bitPattern, 0x41f00000)   // 30.0f
        XCTAssertEqual((F.SHOT_FADE_DRAG_DP as Float).bitPattern, 0x42080000)   // 34.0f
        XCTAssertEqual(F.HUMAN_SHOT_ROLL_SALT as Int64, 6001133726880582977)
        XCTAssertEqual(F.BOT_SHOT_ROLL_SALT as Int64, 6001133726779528275)
        XCTAssertEqual(F.BOT_EVASION_COOLDOWN_MS as Int64, 360)
        XCTAssertEqual((F.BOT_EVASION_PRESSURE_THRESHOLD as Float).bitPattern, 0x3eae147b)   // 0.34f
        XCTAssertEqual((F.BOT_EVASION_BASE_CHANCE as Float).bitPattern, 0x3dcccccd)   // 0.1f
        XCTAssertEqual((F.BOT_EVASION_HANDLING_CHANCE as Float).bitPattern, 0x3f0f5c29)   // 0.56f
        XCTAssertEqual(F.BOT_MAX_EVASIONS_PER_ATTACK as Int, 1)
        XCTAssertEqual(F.BOT_REATTACK_COMMIT_MS as Int64, 560)
        XCTAssertEqual(F.BOT_ESCAPE_THEN_REATTACK_MS as Int64, 440)
        XCTAssertEqual((F.BOT_HARD_CUTOFF_PRESSURE as Float).bitPattern, 0x3f47ae14)   // 0.78f
        XCTAssertEqual(F.BOT_QUESTION_FAST_MS as Int64, 1050)
        XCTAssertEqual(F.BOT_QUESTION_SLOW_MS as Int64, 4200)
        XCTAssertEqual(F.BOT_QUESTION_JITTER_MS as Int64, 420)
        XCTAssertEqual(F.BOT_QUESTION_MIN_ABSOLUTE_MS as Int64, 720)
        XCTAssertEqual(F.BOT_QUESTION_MAX_ABSOLUTE_MS as Int64, 4700)
        XCTAssertEqual(F.BOT_QUESTION_RETRY_FAST_MS as Int64, 900)
        XCTAssertEqual(F.BOT_QUESTION_RETRY_SLOW_MS as Int64, 2500)
        XCTAssertEqual(F.BOT_QUESTION_RETRY_JITTER_MS as Int64, 260)
        XCTAssertEqual(F.BOT_QUESTION_RETRY_MIN_MS as Int64, 720)
        XCTAssertEqual(F.BOT_QUESTION_RETRY_MAX_MS as Int64, 3100)
        XCTAssertEqual(F.BOT_QUESTION_DEADLINE_FAST_MS as Int64, 7600)
        XCTAssertEqual(F.BOT_QUESTION_DEADLINE_SLOW_MS as Int64, 12500)
        XCTAssertEqual(F.BOT_QUESTION_DEADLINE_KNOWLEDGE_BONUS_MS as Int64, 1800)
        XCTAssertEqual(F.BOT_QUESTION_DEADLINE_JITTER_MS as Int64, 900)
        XCTAssertEqual(F.BOT_QUESTION_DEADLINE_MIN_MS as Int64, 5200)
        XCTAssertEqual(F.BOT_QUESTION_DEADLINE_MAX_MS as Int64, 13500)
        XCTAssertEqual(F.BOT_QUESTION_ATTEMPT_SEED_SALT as Int64, 5860671142084498509)
        XCTAssertEqual(F.BOT_FAKE_READ_SEED_SALT as Int64, 5062410217246245188)
        XCTAssertEqual(F.BOT_REAL_SHOT_READ_SEED_SALT as Int64, 5928216280573693780)
        XCTAssertEqual((F.QUICK_AIM_HORIZONTAL_DP as Float).bitPattern, 0x43160000)   // 150.0f
        XCTAssertEqual((F.QUICK_AIM_VERTICAL_DP as Float).bitPattern, 0x43820000)   // 260.0f
        XCTAssertEqual((F.QUICK_AIM_PULL_RANGE as Float).bitPattern, 0x3e3851ec)   // 0.18f
        XCTAssertEqual(F.QUICK_RELEASE_NEUTRAL_MS as Int64, 560)
        XCTAssertEqual((F.QUICK_RELEASE_MAX_ERROR as Float).bitPattern, 0x3d851eb8)   // 0.065f
        XCTAssertEqual(F.TAP_MAX_DURATION_MS as Int64, 190)
        XCTAssertEqual((F.TAP_MOVE_SLOP_DP as Float).bitPattern, 0x41100000)   // 9.0f
        XCTAssertEqual((F.PRESS_TO_AIM_CANCEL_SLOP_DP as Float).bitPattern, 0x41500000)   // 13.0f
        XCTAssertEqual(F.PRESS_TO_AIM_START_MS as Int64, 210)
        XCTAssertEqual(F.DOUBLE_TAP_MAX_GAP_MS as Int64, 285)
        XCTAssertEqual((F.DOUBLE_TAP_MAX_DISTANCE_DP as Float).bitPattern, 0x42180000)   // 38.0f
        XCTAssertEqual(F.QUICK_SHOT_MID_AT_MS as Int64, 120)
        XCTAssertEqual(F.QUICK_SHOT_SET_AT_MS as Int64, 305)
        XCTAssertEqual(F.QUICK_SHOT_RELEASE_AT_MS as Int64, 520)
        XCTAssertEqual(F.QUICK_SHOT_FAKE_CUTOFF_MS as Int64, 440)
        XCTAssertEqual(F.QUICK_SHOT_FAKE_RETURN_MS as Int64, 90)
        XCTAssertEqual((F.QUICK_SHOT_LOW_PULL as Float).bitPattern, 0x3ccccccd)   // 0.025f
        XCTAssertEqual((F.QUICK_SHOT_MID_PULL as Float).bitPattern, 0x3e8f5c29)   // 0.28f
        XCTAssertEqual((F.QUICK_SHOT_SET_PULL as Float).bitPattern, 0x3f3d70a4)   // 0.74f
        XCTAssertEqual((F.QUICK_SHOT_BASE_VARIANCE as Float).bitPattern, 0x3c23d70a)   // 0.01f
        XCTAssertEqual((F.QUICK_SHOT_RATING_VARIANCE as Float).bitPattern, 0x3d1374bc)   // 0.036f
        XCTAssertEqual((F.QUICK_SHOT_MOVEMENT_VARIANCE as Float).bitPattern, 0x3d03126f)   // 0.032f
        XCTAssertEqual(F.RECENT_MOVE_DECAY_MS as Int64, 620)
        XCTAssertEqual((F.MOVE_INPUT_SCALE as Float).bitPattern, 0x3f2b851f)   // 0.67f
        XCTAssertEqual((F.MOVE_BASE_SPEED_DP_PER_SEC as Float).bitPattern, 0x436b0000)   // 235.0f
        XCTAssertEqual((F.MOVE_SPEED_RATING_DP_PER_SEC as Float).bitPattern, 0x40000000)   // 2.0f
        XCTAssertEqual(F.MOVE_MIN_EVENT_DT_MS as Int64, 8)
        XCTAssertEqual(F.MOVE_MAX_EVENT_DT_MS as Int64, 42)
        XCTAssertEqual((F.MOVING_SHOT_MIN_INTENSITY as Float).bitPattern, 0x3e3851ec)   // 0.18f
        XCTAssertEqual((F.ROTATE_MOVE_DEAD_ZONE as Float).bitPattern, 0x3da3d70a)   // 0.08f
        XCTAssertEqual((F.ROTATE_MOVE_SCALE as Float).bitPattern, 0x3f6147ae)   // 0.88f
        XCTAssertEqual(F.CONTROL_PREFS as String, "triple_shot_one_on_one_controls")
        XCTAssertEqual(F.CONTROL_MODE_KEY as String, "control_mode")
        XCTAssertEqual(F.QUESTION_SEED_SALT as Int64, 3555083181248303956)
        XCTAssertEqual(F.QUESTION_RESPONSE_SEED_SALT as Int64, 5928236088896148293)
    }

    func testBotDummyQuestion() {
        let q = F.BOT_DUMMY_QUESTION
        XCTAssertEqual(q.id, "one_on_one")
        XCTAssertEqual(q.category, QuestionCategory.GENERAL_KNOWLEDGE)
        XCTAssertEqual(q.prompt, "")
        XCTAssertEqual(q.answers, [AnswerOption(text: "", qualityPercent: 100)])
        XCTAssertEqual(q.explanation, "")
    }

    func testNewInstancePutsTheKotlinArguments() {
        var categories = KLinkedSet<QuestionCategory>()
        categories.add(QuestionCategory.MATH)
        categories.add(QuestionCategory.GENERAL_KNOWLEDGE)
        categories.add(QuestionCategory.SCIENCE)
        let config = TripleShotGameConfig(
            playerName: "Noa",
            gameType: GameType.ONE_ON_ONE,
            selectedCategories: categories,
            botMatch: true,
            playerCharacterId: TripleShotCharacterRoster.ID_ROOZA,
            botCharacterId: TripleShotCharacterRoster.ID_NOVA,
            gameOrientation: TripleShotGameOrientation.LANDSCAPE,
            courtId: "frostline",
            seed: -42
        )
        let fragment = F.newInstance(config: config)
        let args = fragment.requireArguments()
        XCTAssertEqual(args.size(), 7)
        XCTAssertEqual(args.getString("one_on_one_player_name"), "Noa")
        XCTAssertEqual(args.getString("one_on_one_human_character"), "rooza")
        XCTAssertEqual(args.getString("one_on_one_bot_character"), "nova")
        XCTAssertEqual(args.getString("one_on_one_game_orientation"), "LANDSCAPE")
        XCTAssertEqual(args.getString("one_on_one_court_id"), "frostline")
        XCTAssertEqual(args.getLong("one_on_one_seed", 0), -42)
        // `ArrayList(config.selectedCategories.map { it.name })`: the set's insertion order, not the enum order.
        XCTAssertEqual(args.getStringArrayList("one_on_one_categories"), ["MATH", "GENERAL_KNOWLEDGE", "SCIENCE"])
    }

    // MARK: - Rating helpers (L3250-3269, spec 16 section 7.5)

    func testRatingHelpersOverTheRoster() {
        let fragment = makeFragment()
        var checked = 0
        for f in rows(OneOnOneTests.ratingData) {
            // RATING id effectiveDunkAbility effectiveBlock
            let profile = TripleShotCharacterRoster.find(id: f[1])!
            XCTAssertEqual(fragment.effectiveDunkAbility(profile: profile), Int(f[2])!, f[1])
            XCTAssertEqual(fragment.effectiveBlock(profile: profile), Int(f[3])!, f[1])
            checked += 1
        }
        XCTAssertEqual(checked, TripleShotCharacterRoster.all.count)
        XCTAssertEqual(fragment.pointsFor(zone: ShotZone.INSIDE), 2)
        XCTAssertEqual(fragment.pointsFor(zone: ShotZone.MID_RANGE), 2)
        XCTAssertEqual(fragment.pointsFor(zone: ShotZone.THREE_POINT), 3)
    }

    // MARK: - Bot attack plan seed (L2151-2180)

    /// `Random(seed xor serial * BOT_ATTACK_SEED_SALT)` and its first four draws (nextFloat, nextBoolean, nextFloat,
    /// nextFloat), as startBotAttack consumes them; the JVM's plan values are listed for reference.
    func testAttackPlanSeedAndDrawsMatchJvm() {
        // Spec 16 section 7.6 worked example: Maya, serial 1, seed 1700000000123.
        XCTAssertEqual(OneOnOneTests.SPEC_SEED ^ (Int64(1) &* F.BOT_ATTACK_SEED_SALT), 3553146293695102000)
        var checked = 0
        for f in rows(OneOnOneTests.attackData) {
            // ATTACK id seed serial misses genSeed r1 takeOnThreshold takeOn side r3 crossThreshold useCrossover
            //        durationMs r4 crossoverAtMs evasionChance
            let seed = Int64(f[2])!
            let serial = Int64(f[3])!
            let genSeed = seed ^ (serial &* F.BOT_ATTACK_SEED_SALT)
            let label = f.joined(separator: " ")
            XCTAssertEqual(genSeed, Int64(f[5])!, label)
            let random = KotlinRandom(seed: genSeed)
            XCTAssertEqual(random.nextFloat().bitPattern, bits(f[6]), label)
            XCTAssertEqual(random.nextBoolean() ? 1 : -1, Int(f[9])!, label)
            XCTAssertEqual(random.nextFloat().bitPattern, bits(f[10]), label)
            XCTAssertEqual(random.nextFloat().bitPattern, bits(f[14]), label)
            checked += 1
        }
        XCTAssertGreaterThan(checked, 100)
    }

    // MARK: - Bot quiz choice and timings (L2934-3003)

    func testChooseBotQuizAnswerIndexMatchesJvm() {
        var fragments: [String: TripleShotOneOnOneFragment] = [:]
        var checked = 0
        for f in rows(OneOnOneTests.chooseData) {
            // CHOOSE botId generatorSeed qualities excluded expectedIndex nextRawIntAfterwards
            let fragment = fragments[f[1]] ?? makeFragment(bot: f[1])
            fragments[f[1]] = fragment
            let random = KotlinRandom(seed: Int64(f[2])!)
            let index = fragment.chooseBotQuizAnswerIndex(
                question: question("q", ints(f[3])),
                random: random,
                excludedIndices: Set(ints(f[4]))
            )
            let label = f.joined(separator: " ")
            XCTAssertEqual(index, Int(f[5])!, label)
            // Same number of draws as Kotlin (List.random -> nextInt(size); nextInt(1) still draws).
            XCTAssertEqual(random.nextInt(), Int32(f[6])!, label)
            checked += 1
        }
        XCTAssertGreaterThan(checked, 1000)
    }

    func testChooseBotQuizAnswerIndexEdgeCases() {
        let fragment = makeFragment(bot: TripleShotCharacterRoster.ID_BUDDY_23)
        let fresh = KotlinRandom(seed: 99).nextInt()

        // No answers: 0 without a draw.
        var random = KotlinRandom(seed: 99)
        XCTAssertEqual(fragment.chooseBotQuizAnswerIndex(question: question("q", []), random: random), 0)
        XCTAssertEqual(random.nextInt(), fresh)

        // Every option excluded: the first index, without a draw.
        random = KotlinRandom(seed: 99)
        XCTAssertEqual(
            fragment.chooseBotQuizAnswerIndex(question: question("q", [0, 100]), random: random, excludedIndices: [0, 1]), 0)
        XCTAssertEqual(random.nextInt(), fresh)

        // Every wrong option already tried: the (only) correct one, after exactly one nextInt(1).
        random = KotlinRandom(seed: 99)
        XCTAssertEqual(
            fragment.chooseBotQuizAnswerIndex(question: question("q", [0, 0, 100, 0]), random: random,
                                              excludedIndices: [0, 1, 3]), 2)
        let oneDraw = KotlinRandom(seed: 99)
        _ = oneDraw.nextInt(1)
        XCTAssertEqual(random.nextInt(), oneDraw.nextInt())
    }

    func testBotQuizDelaysMatchJvm() {
        var fragments: [String: TripleShotOneOnOneFragment] = [:]
        var checked = 0
        for f in rows(OneOnOneTests.delayData) {
            // DELAY botId generatorSeed firstDelay retryDelay(attempt 1..5) deadline   (fresh generator per value)
            let fragment = fragments[f[1]] ?? makeFragment(bot: f[1])
            fragments[f[1]] = fragment
            let genSeed = Int64(f[2])!
            let label = f.joined(separator: " ")
            XCTAssertEqual(fragment.botQuizDelayMs(random: KotlinRandom(seed: genSeed)), Int64(f[3])!, label)
            let retries = (1...5).map { attempt in
                fragment.botQuizRetryDelayMs(random: KotlinRandom(seed: genSeed), attempt: attempt)
            }
            XCTAssertEqual(retries, f[4].split(separator: ",").map { Int64($0)! }, label)
            XCTAssertEqual(fragment.botQuestionCorrectDeadlineMs(random: KotlinRandom(seed: genSeed)), Int64(f[5])!, label)
            checked += 1
        }
        XCTAssertGreaterThan(checked, 400)
    }

    // MARK: - The private question race (L2646-2758)

    /// The race as showNextPossessionQuestion and scheduleBotQuestionAttempt drive the helpers: the hard deadline from
    /// `Random(seed xor round * RESPONSE_SALT xor id.hashCode())`, then for attempt a = 0, 1, ...
    /// `Random(... xor (a + 1) * ATTEMPT_SALT)` decides the choice first and the delay second; a wrong pick is
    /// excluded from the next attempt; the race ends at the first correct pick.
    private func race(_ fragment: TripleShotOneOnOneFragment, round: Int64, question: TripleShotQuestion)
        -> (deadline: Int64, steps: [(index: Int, delay: Int64)]) {
        let hash = question.id.javaHashCode.toLong()
        let deadline = fragment.botQuestionCorrectDeadlineMs(
            random: KotlinRandom(seed: fragment.seed ^ (round &* F.QUESTION_RESPONSE_SEED_SALT) ^ hash))
        let best = question.answers.kMaxOf { $0.qualityPercent }
        var excluded = Set<Int>()
        var steps: [(index: Int, delay: Int64)] = []
        var attempt = 0
        while attempt < 8 {
            let random = KotlinRandom(
                seed: fragment.seed ^ (round &* F.QUESTION_RESPONSE_SEED_SALT) ^ hash ^
                    ((attempt.toLong() &+ 1) &* F.BOT_QUESTION_ATTEMPT_SEED_SALT))
            let index = fragment.chooseBotQuizAnswerIndex(question: question, random: random, excludedIndices: excluded)
            let delay = attempt == 0
                ? fragment.botQuizDelayMs(random: random)
                : fragment.botQuizRetryDelayMs(random: random, attempt: attempt)
            steps.append((index, delay))
            if question.answers.getOrNull(index)?.qualityPercent == best { break }
            excluded.insert(index)
            attempt += 1
        }
        return (deadline, steps)
    }

    func testSpecWorkedQuestionRace() {
        // Spec 16 section 7.6: Maya, round 1, id "q-1", qualities [0, 0, 100, 0], seed 1700000000123.
        let result = race(makeFragment(), round: 1, question: question("q-1", [0, 0, 100, 0]))
        XCTAssertEqual(result.deadline, 8925)
        XCTAssertEqual(result.steps.count, 2)
        XCTAssertEqual(result.steps[0].index, 3)
        XCTAssertEqual(result.steps[0].delay, 1867)
        XCTAssertEqual(result.steps[1].index, 2)
        XCTAssertEqual(result.steps[1].delay, 1685)
    }

    func testPossessionRaceScheduleMatchesJvm() {
        var fragments: [String: TripleShotOneOnOneFragment] = [:]
        var checked = 0
        for f in rows(OneOnOneTests.raceData) {
            // RACE botId seed round questionId qualities deadline index:delay;index:delay...
            let key = f[1] + " " + f[2]
            let fragment = fragments[key] ?? makeFragment(seed: Int64(f[2])!, bot: f[1])
            fragments[key] = fragment
            let result = race(fragment, round: Int64(f[3])!, question: question(f[4], ints(f[5])))
            let label = f.joined(separator: " ")
            XCTAssertEqual(result.deadline, Int64(f[6])!, label)
            let steps = result.steps.map { String($0.index) + ":" + String($0.delay) }.joined(separator: ";")
            XCTAssertEqual(steps, f[7], label)
            checked += 1
        }
        XCTAssertGreaterThan(checked, 1000)
    }

    /// The lazy hard deadline: applied only when the human answers, silently making the bot the first correct one.
    func testForceBotRaceResolutionIfDeadlinePassed() {
        AFakeClock.install(nanos: 5_000_000_000_000)
        let now = ASystemClock.elapsedRealtime()

        func armed() -> TripleShotOneOnOneFragment {
            let fragment = makeFragment()
            fragment.botQuestionShownAtElapsedMs = now - 8925
            fragment.botQuestionHardDeadlineMs = 8925
            fragment.botQuestionRunnable = ARunnable {}
            return fragment
        }

        let passed = armed()
        passed.forceBotRaceResolutionIfDeadlinePassed()
        XCTAssertNil(passed.botQuestionRunnable)
        XCTAssertTrue(passed.botAnsweredCurrentQuestion)
        XCTAssertTrue(passed.botCorrectOnCurrentQuestion)
        XCTAssertFalse(passed.botWrongOnCurrentQuestion)
        XCTAssertEqual(passed.possessionQuestionWinnerHuman, false)

        let early = armed()
        early.botQuestionShownAtElapsedMs = now - 8924
        early.forceBotRaceResolutionIfDeadlinePassed()
        XCTAssertNotNil(early.botQuestionRunnable)
        XCTAssertFalse(early.botCorrectOnCurrentQuestion)
        XCTAssertNil(early.possessionQuestionWinnerHuman)

        let humanFirst = armed()
        humanFirst.possessionQuestionWinnerHuman = true
        humanFirst.forceBotRaceResolutionIfDeadlinePassed()
        XCTAssertEqual(humanFirst.possessionQuestionWinnerHuman, true)
        XCTAssertFalse(humanFirst.botCorrectOnCurrentQuestion)
        XCTAssertNotNil(humanFirst.botQuestionRunnable)

        let unset = armed()
        unset.botQuestionShownAtElapsedMs = 0
        unset.forceBotRaceResolutionIfDeadlinePassed()
        XCTAssertFalse(unset.botCorrectOnCurrentQuestion)

        let noDeadline = armed()
        noDeadline.botQuestionHardDeadlineMs = 0
        noDeadline.forceBotRaceResolutionIfDeadlinePassed()
        XCTAssertFalse(noDeadline.botCorrectOnCurrentQuestion)

        let botAlreadyRight = armed()
        botAlreadyRight.botCorrectOnCurrentQuestion = true
        botAlreadyRight.forceBotRaceResolutionIfDeadlinePassed()
        XCTAssertNil(botAlreadyRight.possessionQuestionWinnerHuman)
        XCTAssertNotNil(botAlreadyRight.botQuestionRunnable)
    }

    // MARK: - Gendered strings (L3062-3078)

    func testGenderedStringSelection() {
        let fragment = makeFragment(bot: TripleShotCharacterRoster.ID_BOB)
        let male = R.string.minik_swish_one_on_one_made_male
        let female = R.string.minik_swish_one_on_one_made_female
        let neutral = R.string.minik_swish_one_on_one_made_neutral
        let maya = TripleShotCharacterRoster.womanDark
        XCTAssertEqual(maya.gender, CharacterGender.FEMALE)
        XCTAssertEqual(fragment.genderedCharacterString(profile: maya, maleRes: male, femaleRes: female, neutralRes: neutral), female)
        let neutralProfile = maya.copy(gender: CharacterGender.NEUTRAL)
        XCTAssertEqual(
            fragment.genderedCharacterString(profile: neutralProfile, maleRes: male, femaleRes: female, neutralRes: neutral),
            neutral)
        // Kotlin default `neutralRes = maleRes`.
        XCTAssertEqual(fragment.genderedCharacterString(profile: neutralProfile, maleRes: male, femaleRes: female), male)
        // The bot variant uses botProfile (BOB is male).
        XCTAssertEqual(fragment.genderedBotString(maleRes: male, femaleRes: female, neutralRes: neutral), male)
        fragment.botProfile = neutralProfile
        XCTAssertEqual(fragment.genderedBotString(maleRes: male, femaleRes: female), male)
        XCTAssertEqual(fragment.genderedBotString(maleRes: male, femaleRes: female, neutralRes: neutral), neutral)
    }

    // MARK: - Bidi helpers (L3029-3060)

    func testIsRtlUiFollowsTheFirstConfigurationLocale() {
        let fragment = makeAttachedFragment()
        for (language, rtl) in [("he", true), ("iw", true), ("ar", true), ("en", false), ("fr", false), ("ru", false)] {
            setLanguage(language)
            XCTAssertEqual(fragment.isRtlUi(), rtl, language)
        }
    }

    func testBidiSafeNameAndBotScoreLine() {
        let fragment = makeAttachedFragment()
        let lri = OneOnOneTests.LRI
        let pdi = OneOnOneTests.PDI
        let hebrewName = "\u{05DE}\u{05D0}\u{05D9}\u{05D4}"

        setLanguage("he")
        XCTAssertEqual(fragment.bidiSafeName(raw: "Maya"), lri + "Maya" + pdi)
        XCTAssertEqual(fragment.bidiSafeName(raw: "Buddy 23"), lri + "Buddy 23" + pdi)
        // Only an ASCII letter triggers the isolate.
        XCTAssertEqual(fragment.bidiSafeName(raw: hebrewName), hebrewName)
        XCTAssertEqual(fragment.bidiSafeName(raw: "23"), "23")
        XCTAssertEqual(fragment.bidiSafeName(raw: "\u{00C9}lan"), lri + "\u{00C9}lan" + pdi)
        XCTAssertEqual(fragment.bidiSafeName(raw: "\u{00C9}\u{00E9}"), "\u{00C9}\u{00E9}")
        // The bot score line is isolated as a whole in RTL, without a letter check (U+00B7 middle dot).
        XCTAssertEqual(fragment.formatBotScoreText(name: "Mia Essence Skies", score: 0), lri + "Mia Essence Skies \u{00B7} 0" + pdi)
        XCTAssertEqual(fragment.formatBotScoreText(name: hebrewName, score: 11), lri + hebrewName + " \u{00B7} 11" + pdi)

        setLanguage("en")
        XCTAssertEqual(fragment.bidiSafeName(raw: "Maya"), "Maya")
        XCTAssertEqual(fragment.formatBotScoreText(name: "Mia Essence Skies", score: 7), "Mia Essence Skies \u{00B7} 7")

        // A non-he/en device: Hebrew strings (values/) but LTR rules, no isolation (spec 16 section 8.11).
        setLanguage("fr")
        XCTAssertEqual(fragment.bidiSafeName(raw: "Maya"), "Maya")
        XCTAssertEqual(fragment.formatBotScoreText(name: "Maya", score: 3), "Maya \u{00B7} 3")
    }

    func testBidiSafeQuestionPromptIsolatesArithmeticRuns() {
        let fragment = makeAttachedFragment()
        let lri = OneOnOneTests.LRI
        let pdi = OneOnOneTests.PDI
        let howMuch = "\u{05DB}\u{05DE}\u{05D4} \u{05D6}\u{05D4} "   // Hebrew "how much is "

        setLanguage("en")
        XCTAssertEqual(fragment.bidiSafeQuestionPrompt(raw: "15 - 8"), "15 - 8")

        setLanguage("he")
        XCTAssertEqual(fragment.bidiSafeQuestionPrompt(raw: "15 - 8"), lri + "15 - 8" + pdi)
        // Matches are left to right and non-overlapping: only "3 + 4" in "3 + 4 + 5".
        XCTAssertEqual(fragment.bidiSafeQuestionPrompt(raw: "3 + 4 + 5"), lri + "3 + 4" + pdi + " + 5")
        XCTAssertEqual(fragment.bidiSafeQuestionPrompt(raw: "2,5 \u{00D7} 4"), lri + "2,5 \u{00D7} 4" + pdi)
        XCTAssertEqual(fragment.bidiSafeQuestionPrompt(raw: howMuch + "6\u{00F7}2?"), howMuch + lri + "6\u{00F7}2" + pdi + "?")
        XCTAssertEqual(fragment.bidiSafeQuestionPrompt(raw: "1.5*2 = ?"), lri + "1.5*2" + pdi + " = ?")
        XCTAssertEqual(fragment.bidiSafeQuestionPrompt(raw: "7 / 7 / 7"), lri + "7 / 7" + pdi + " / 7")
        // U+2212 MINUS SIGN and U+2013 EN DASH are not operators.
        XCTAssertEqual(fragment.bidiSafeQuestionPrompt(raw: "10\u{2212}3"), "10\u{2212}3")
        XCTAssertEqual(fragment.bidiSafeQuestionPrompt(raw: "10 \u{2013} 3"), "10 \u{2013} 3")
        XCTAssertEqual(fragment.bidiSafeQuestionPrompt(raw: howMuch), howMuch)
        // ICU semantics, as on Android (java.util.regex is ICU4C-backed there): `\s` includes NO-BREAK SPACE and
        // `\d` any decimal digit (Arabic-Indic digits here).
        XCTAssertEqual(fragment.bidiSafeQuestionPrompt(raw: "15\u{00A0}-\u{00A0}8"), lri + "15\u{00A0}-\u{00A0}8" + pdi)
        XCTAssertEqual(fragment.bidiSafeQuestionPrompt(raw: "\u{0661}\u{0665} - \u{0668}"),
                       lri + "\u{0661}\u{0665} - \u{0668}" + pdi)
    }

    func testOne2RegexReplaceIsKotlinRegexReplace() {
        let regex = F.One2Regex(F.ONE2_ARITHMETIC_PATTERN)
        XCTAssertEqual(regex.replace("no arithmetic") { "[" + $0 + "]" }, "no arithmetic")
        XCTAssertEqual(regex.replace("1+1 and 2-2") { "[" + $0 + "]" }, "[1+1] and [2-2]")
        XCTAssertEqual(regex.replace("x 12.5 / 0,5 y") { "<" + $0 + ">" }, "x <12.5 / 0,5> y")
        // UTF-16 offsets around a supplementary character before the match.
        XCTAssertEqual(regex.replace("\u{1F3C0} 3*3") { "(" + $0 + ")" }, "\u{1F3C0} (3*3)")
    }

    // MARK: - Golden data (golden.txt of the JVM harness)

    private static let ratingData = """
RATING bob 49 54
RATING woman_dark 73 58
RATING rooza 79 56
RATING nova 88 83
RATING unicorn_32 84 88
RATING coach_67 78 83
RATING zephyr 90 79
RATING kyra 90 79
RATING kyra_original 90 79
RATING flare 92 79
RATING ace_23 82 62
RATING buddy_23 65 47
"""

    private static let attackData = """
ATTACK bob 0 1 0 3553144604475020363 0x3f2ff5a6 0x3f0b4396 false 1 0x3ec2da92 0x3f0fbb94 true 1967 0x3f7b9cf5 979 0x3ee5e247
ATTACK bob 0 2 0 7106289208950040726 0x3f03b0cd 0x3f0b4396 true -1 0x3f529a1c 0x3f0fbb94 false 1967 0x3e9205d2 814 0x3ee5e247
ATTACK bob 0 7 0 6425268157615590925 0x3f18c8bd 0x3f0b4396 false -1 0x3e658fa4 0x3f0fbb94 true 1967 0x3dd882d0 772 0x3ee5e247
ATTACK bob 0 123456789 0 -5662605129663907545 0x3e959eb8 0x3f0b4396 true -1 0x3e9226ec 0x3f0fbb94 true 1967 0x3f0aa669 875 0x3ee5e247
ATTACK bob 1700000000123 1 0 3553146293695102000 0x3ef0ae48 0x3f0b4396 true 1 0x3e8aa844 0x3f0fbb94 true 1967 0x3f665f63 959 0x3ee5e247
ATTACK bob 1700000000123 2 0 7106290887387103469 0x3ec320b0 0x3f0b4396 true -1 0x3f0d6f47 0x3f0fbb94 true 1967 0x3e958b48 816 0x3ee5e247
ATTACK bob 1700000000123 7 0 6425267583119468150 0x3ea8d0fe 0x3f0b4396 true -1 0x3e5e3530 0x3f0fbb94 true 1967 0x3d85aa60 762 0x3ee5e247
ATTACK bob 1700000000123 123456789 0 -5662604553032920740 0x3f49f1da 0x3f0b4396 false -1 0x3e8f5b1e 0x3f0fbb94 true 1967 0x3f51abf5 940 0x3ee5e247
ATTACK bob -987654321 1 0 -3553144605451631868 0x3ed69eaa 0x3f0b4396 true -1 0x3da57b00 0x3f0fbb94 true 1967 0x3f5a680e 948 0x3ee5e247
ATTACK bob -987654321 2 0 -7106289209852739623 0x3e7a1884 0x3f0b4396 true 1 0x3e8a2d68 0x3f0fbb94 true 1967 0x3e1b2928 783 0x3ee5e247
ATTACK bob -987654321 7 0 -6425268158324549310 0x3e7db7a8 0x3f0b4396 true 1 0x3ef0449e 0x3f0fbb94 true 1967 0x3e72ea08 803 0x3ee5e247
ATTACK bob -987654321 123456789 0 5662605129819516520 0x3f24f5af 0x3f0b4396 false 1 0x3ce26d60 0x3f0fbb94 true 1967 0x3f6db4fb 966 0x3ee5e247
ATTACK bob 9223372036854775807 1 0 5670227432379755444 0x3f2e2f43 0x3f0b4396 false -1 0x3d731f10 0x3f0fbb94 true 1967 0x3cba3ae0 752 0x3ee5e247
ATTACK bob 9223372036854775807 2 0 2117082827904735081 0x3f616743 0x3f0b4396 false -1 0x3f2054c3 0x3f0fbb94 false 1967 0x3f3d3783 921 0x3ee5e247
ATTACK bob 9223372036854775807 7 0 2798103879239184882 0x3f4a9104 0x3f0b4396 false 1 0x3eb7517c 0x3f0fbb94 true 1967 0x3f6743ba 960 0x3ee5e247
ATTACK bob 9223372036854775807 123456789 0 -3560766907190868264 0x3dc8ae28 0x3f0b4396 true 1 0x3e2b2270 0x3f0fbb94 true 1967 0x3ef0b686 858 0x3ee5e247
ATTACK bob -9223372036854775808 1 0 -5670227432379755445 0x3f4fd5a8 0x3f0b4396 false 1 0x3f005a7a 0x3f0fbb94 true 1967 0x3f7863db 976 0x3ee5e247
ATTACK bob -9223372036854775808 2 0 -2117082827904735082 0x3f23d0cc 0x3f0b4396 false 1 0x3f338b57 0x3f0fbb94 false 1967 0x3e8f1336 813 0x3ee5e247
ATTACK bob -9223372036854775808 7 0 -2798103879239184883 0x3f28e8bb 0x3f0b4396 false 1 0x3d06d330 0x3f0fbb94 true 1967 0x3dedcea0 774 0x3ee5e247
ATTACK bob -9223372036854775808 123456789 0 3560766907190868263 0x3ef4debe 0x3f0b4396 true 1 0x3ef43a1e 0x3f0fbb94 true 1967 0x3f4db12a 937 0x3ee5e247
ATTACK bob 31337 1 0 3553144604475010594 0x3dc0cbe0 0x3f0b4396 true -1 0x3e4355e4 0x3f0fbb94 true 1967 0x3f618c3c 955 0x3ee5e247
ATTACK bob 31337 2 0 7106289208950051583 0x3f69b9ff 0x3f0b4396 false 1 0x3f216e14 0x3f0fbb94 false 1967 0x3e4086ac 791 0x3ee5e247
ATTACK bob 31337 7 0 6425268157615584356 0x3c94c0e0 0x3f0b4396 true 1 0x3ed7f3f0 0x3f0fbb94 true 1967 0x3e58424c 797 0x3ee5e247
ATTACK bob 31337 123456789 0 -5662605129663937714 0x3f61bb92 0x3f0b4396 false -1 0x3dd9d270 0x3f0fbb94 true 1967 0x3f36186a 915 0x3ee5e247
ATTACK woman_dark 0 1 0 3553144604475020363 0x3f2ff5a6 0x3f1f559c false 1 0x3ec2da92 0x3f35dcc6 true 1795 0x3f7b9cf5 893 0x3f17c1be
ATTACK woman_dark 0 2 0 7106289208950040726 0x3f03b0cd 0x3f1f559c true -1 0x3f529a1c 0x3f35dcc6 false 1795 0x3e9205d2 743 0x3f17c1be
ATTACK woman_dark 0 7 0 6425268157615590925 0x3f18c8bd 0x3f1f559c true -1 0x3e658fa4 0x3f35dcc6 true 1795 0x3dd882d0 704 0x3f17c1be
ATTACK woman_dark 0 123456789 0 -5662605129663907545 0x3e959eb8 0x3f1f559c true -1 0x3e9226ec 0x3f35dcc6 true 1795 0x3f0aa669 798 0x3f17c1be
ATTACK woman_dark 1700000000123 1 0 3553146293695102000 0x3ef0ae48 0x3f1f559c true 1 0x3e8aa844 0x3f35dcc6 true 1795 0x3f665f63 875 0x3f17c1be
ATTACK woman_dark 1700000000123 2 0 7106290887387103469 0x3ec320b0 0x3f1f559c true -1 0x3f0d6f47 0x3f35dcc6 true 1795 0x3e958b48 745 0x3f17c1be
ATTACK woman_dark 1700000000123 7 0 6425267583119468150 0x3ea8d0fe 0x3f1f559c true -1 0x3e5e3530 0x3f35dcc6 true 1795 0x3d85aa60 696 0x3f17c1be
ATTACK woman_dark 1700000000123 123456789 0 -5662604553032920740 0x3f49f1da 0x3f1f559c false -1 0x3e8f5b1e 0x3f35dcc6 true 1795 0x3f51abf5 858 0x3f17c1be
ATTACK woman_dark -987654321 1 0 -3553144605451631868 0x3ed69eaa 0x3f1f559c true -1 0x3da57b00 0x3f35dcc6 true 1795 0x3f5a680e 865 0x3f17c1be
ATTACK woman_dark -987654321 2 0 -7106289209852739623 0x3e7a1884 0x3f1f559c true 1 0x3e8a2d68 0x3f35dcc6 true 1795 0x3e1b2928 714 0x3f17c1be
ATTACK woman_dark -987654321 7 0 -6425268158324549310 0x3e7db7a8 0x3f1f559c true 1 0x3ef0449e 0x3f35dcc6 true 1795 0x3e72ea08 733 0x3f17c1be
ATTACK woman_dark -987654321 123456789 0 5662605129819516520 0x3f24f5af 0x3f1f559c false 1 0x3ce26d60 0x3f35dcc6 true 1795 0x3f6db4fb 882 0x3f17c1be
ATTACK woman_dark 9223372036854775807 1 0 5670227432379755444 0x3f2e2f43 0x3f1f559c false -1 0x3d731f10 0x3f35dcc6 true 1795 0x3cba3ae0 686 0x3f17c1be
ATTACK woman_dark 9223372036854775807 2 0 2117082827904735081 0x3f616743 0x3f1f559c false -1 0x3f2054c3 0x3f35dcc6 true 1795 0x3f3d3783 841 0x3f17c1be
ATTACK woman_dark 9223372036854775807 7 0 2798103879239184882 0x3f4a9104 0x3f1f559c false 1 0x3eb7517c 0x3f35dcc6 true 1795 0x3f6743ba 876 0x3f17c1be
ATTACK woman_dark 9223372036854775807 123456789 0 -3560766907190868264 0x3dc8ae28 0x3f1f559c true 1 0x3e2b2270 0x3f35dcc6 true 1795 0x3ef0b686 783 0x3f17c1be
ATTACK woman_dark -9223372036854775808 1 0 -5670227432379755445 0x3f4fd5a8 0x3f1f559c false 1 0x3f005a7a 0x3f35dcc6 true 1795 0x3f7863db 891 0x3f17c1be
ATTACK woman_dark -9223372036854775808 2 0 -2117082827904735082 0x3f23d0cc 0x3f1f559c false 1 0x3f338b57 0x3f35dcc6 true 1795 0x3e8f1336 742 0x3f17c1be
ATTACK woman_dark -9223372036854775808 7 0 -2798103879239184883 0x3f28e8bb 0x3f1f559c false 1 0x3d06d330 0x3f35dcc6 true 1795 0x3dedcea0 707 0x3f17c1be
ATTACK woman_dark -9223372036854775808 123456789 0 3560766907190868263 0x3ef4debe 0x3f1f559c true 1 0x3ef43a1e 0x3f35dcc6 true 1795 0x3f4db12a 855 0x3f17c1be
ATTACK woman_dark 31337 1 0 3553144604475010594 0x3dc0cbe0 0x3f1f559c true -1 0x3e4355e4 0x3f35dcc6 true 1795 0x3f618c3c 871 0x3f17c1be
ATTACK woman_dark 31337 2 0 7106289208950051583 0x3f69b9ff 0x3f1f559c false 1 0x3f216e14 0x3f35dcc6 true 1795 0x3e4086ac 722 0x3f17c1be
ATTACK woman_dark 31337 7 0 6425268157615584356 0x3c94c0e0 0x3f1f559c true 1 0x3ed7f3f0 0x3f35dcc6 true 1795 0x3e58424c 727 0x3f17c1be
ATTACK woman_dark 31337 123456789 0 -5662605129663937714 0x3f61bb92 0x3f1f559c false -1 0x3dd9d270 0x3f35dcc6 true 1795 0x3f36186a 835 0x3f17c1be
ATTACK rooza 0 1 0 3553144604475020363 0x3f2ff5a6 0x3f35c28f true 1 0x3ec2da92 0x3f3ce67d true 1583 0x3f7b9cf5 788 0x3f1e8d54
ATTACK rooza 0 2 0 7106289208950040726 0x3f03b0cd 0x3f35c28f true -1 0x3f529a1c 0x3f3ce67d false 1583 0x3e9205d2 655 0x3f1e8d54
ATTACK rooza 0 7 0 6425268157615590925 0x3f18c8bd 0x3f35c28f true -1 0x3e658fa4 0x3f3ce67d true 1583 0x3dd882d0 621 0x3f1e8d54
ATTACK rooza 0 123456789 0 -5662605129663907545 0x3e959eb8 0x3f35c28f true -1 0x3e9226ec 0x3f3ce67d true 1583 0x3f0aa669 704 0x3f1e8d54
ATTACK rooza 1700000000123 1 0 3553146293695102000 0x3ef0ae48 0x3f35c28f true 1 0x3e8aa844 0x3f3ce67d true 1583 0x3f665f63 772 0x3f1e8d54
ATTACK rooza 1700000000123 2 0 7106290887387103469 0x3ec320b0 0x3f35c28f true -1 0x3f0d6f47 0x3f3ce67d true 1583 0x3e958b48 657 0x3f1e8d54
ATTACK rooza 1700000000123 7 0 6425267583119468150 0x3ea8d0fe 0x3f35c28f true -1 0x3e5e3530 0x3f3ce67d true 1583 0x3d85aa60 613 0x3f1e8d54
ATTACK rooza 1700000000123 123456789 0 -5662604553032920740 0x3f49f1da 0x3f35c28f false -1 0x3e8f5b1e 0x3f3ce67d true 1583 0x3f51abf5 757 0x3f1e8d54
ATTACK rooza -987654321 1 0 -3553144605451631868 0x3ed69eaa 0x3f35c28f true -1 0x3da57b00 0x3f3ce67d true 1583 0x3f5a680e 763 0x3f1e8d54
ATTACK rooza -987654321 2 0 -7106289209852739623 0x3e7a1884 0x3f35c28f true 1 0x3e8a2d68 0x3f3ce67d true 1583 0x3e1b2928 630 0x3f1e8d54
ATTACK rooza -987654321 7 0 -6425268158324549310 0x3e7db7a8 0x3f35c28f true 1 0x3ef0449e 0x3f3ce67d true 1583 0x3e72ea08 646 0x3f1e8d54
ATTACK rooza -987654321 123456789 0 5662605129819516520 0x3f24f5af 0x3f35c28f true 1 0x3ce26d60 0x3f3ce67d true 1583 0x3f6db4fb 777 0x3f1e8d54
ATTACK rooza 9223372036854775807 1 0 5670227432379755444 0x3f2e2f43 0x3f35c28f true -1 0x3d731f10 0x3f3ce67d true 1583 0x3cba3ae0 605 0x3f1e8d54
ATTACK rooza 9223372036854775807 2 0 2117082827904735081 0x3f616743 0x3f35c28f false -1 0x3f2054c3 0x3f3ce67d true 1583 0x3f3d3783 741 0x3f1e8d54
ATTACK rooza 9223372036854775807 7 0 2798103879239184882 0x3f4a9104 0x3f35c28f false 1 0x3eb7517c 0x3f3ce67d true 1583 0x3f6743ba 773 0x3f1e8d54
ATTACK rooza 9223372036854775807 123456789 0 -3560766907190868264 0x3dc8ae28 0x3f35c28f true 1 0x3e2b2270 0x3f3ce67d true 1583 0x3ef0b686 690 0x3f1e8d54
ATTACK rooza -9223372036854775808 1 0 -5670227432379755445 0x3f4fd5a8 0x3f35c28f false 1 0x3f005a7a 0x3f3ce67d true 1583 0x3f7863db 785 0x3f1e8d54
ATTACK rooza -9223372036854775808 2 0 -2117082827904735082 0x3f23d0cc 0x3f35c28f true 1 0x3f338b57 0x3f3ce67d true 1583 0x3e8f1336 654 0x3f1e8d54
ATTACK rooza -9223372036854775808 7 0 -2798103879239184883 0x3f28e8bb 0x3f35c28f true 1 0x3d06d330 0x3f3ce67d true 1583 0x3dedcea0 623 0x3f1e8d54
ATTACK rooza -9223372036854775808 123456789 0 3560766907190868263 0x3ef4debe 0x3f35c28f true 1 0x3ef43a1e 0x3f3ce67d true 1583 0x3f4db12a 754 0x3f1e8d54
ATTACK rooza 31337 1 0 3553144604475010594 0x3dc0cbe0 0x3f35c28f true -1 0x3e4355e4 0x3f3ce67d true 1583 0x3f618c3c 768 0x3f1e8d54
ATTACK rooza 31337 2 0 7106289208950051583 0x3f69b9ff 0x3f35c28f false 1 0x3f216e14 0x3f3ce67d true 1583 0x3e4086ac 637 0x3f1e8d54
ATTACK rooza 31337 7 0 6425268157615584356 0x3c94c0e0 0x3f35c28f true 1 0x3ed7f3f0 0x3f3ce67d true 1583 0x3e58424c 641 0x3f1e8d54
ATTACK rooza 31337 123456789 0 -5662605129663937714 0x3f61bb92 0x3f35c28f false -1 0x3dd9d270 0x3f3ce67d true 1583 0x3f36186a 736 0x3f1e8d54
ATTACK nova 0 1 0 3553144604475020363 0x3f2ff5a6 0x3f290ffa false 1 0x3ec2da92 0x3f367c6b true 1693 0x3f7b9cf5 843 0x3f185be2
ATTACK nova 0 2 0 7106289208950040726 0x3f03b0cd 0x3f290ffa true -1 0x3f529a1c 0x3f367c6b false 1693 0x3e9205d2 701 0x3f185be2
ATTACK nova 0 7 0 6425268157615590925 0x3f18c8bd 0x3f290ffa true -1 0x3e658fa4 0x3f367c6b true 1693 0x3dd882d0 664 0x3f185be2
ATTACK nova 0 123456789 0 -5662605129663907545 0x3e959eb8 0x3f290ffa true -1 0x3e9226ec 0x3f367c6b true 1693 0x3f0aa669 753 0x3f185be2
ATTACK nova 1700000000123 1 0 3553146293695102000 0x3ef0ae48 0x3f290ffa true 1 0x3e8aa844 0x3f367c6b true 1693 0x3f665f63 826 0x3f185be2
ATTACK nova 1700000000123 2 0 7106290887387103469 0x3ec320b0 0x3f290ffa true -1 0x3f0d6f47 0x3f367c6b true 1693 0x3e958b48 702 0x3f185be2
ATTACK nova 1700000000123 7 0 6425267583119468150 0x3ea8d0fe 0x3f290ffa true -1 0x3e5e3530 0x3f367c6b true 1693 0x3d85aa60 656 0x3f185be2
ATTACK nova 1700000000123 123456789 0 -5662604553032920740 0x3f49f1da 0x3f290ffa false -1 0x3e8f5b1e 0x3f367c6b true 1693 0x3f51abf5 809 0x3f185be2
ATTACK nova -987654321 1 0 -3553144605451631868 0x3ed69eaa 0x3f290ffa true -1 0x3da57b00 0x3f367c6b true 1693 0x3f5a680e 816 0x3f185be2
ATTACK nova -987654321 2 0 -7106289209852739623 0x3e7a1884 0x3f290ffa true 1 0x3e8a2d68 0x3f367c6b true 1693 0x3e1b2928 674 0x3f185be2
ATTACK nova -987654321 7 0 -6425268158324549310 0x3e7db7a8 0x3f290ffa true 1 0x3ef0449e 0x3f367c6b true 1693 0x3e72ea08 691 0x3f185be2
ATTACK nova -987654321 123456789 0 5662605129819516520 0x3f24f5af 0x3f290ffa true 1 0x3ce26d60 0x3f367c6b true 1693 0x3f6db4fb 831 0x3f185be2
ATTACK nova 9223372036854775807 1 0 5670227432379755444 0x3f2e2f43 0x3f290ffa false -1 0x3d731f10 0x3f367c6b true 1693 0x3cba3ae0 647 0x3f185be2
ATTACK nova 9223372036854775807 2 0 2117082827904735081 0x3f616743 0x3f290ffa false -1 0x3f2054c3 0x3f367c6b true 1693 0x3f3d3783 793 0x3f185be2
ATTACK nova 9223372036854775807 7 0 2798103879239184882 0x3f4a9104 0x3f290ffa false 1 0x3eb7517c 0x3f367c6b true 1693 0x3f6743ba 826 0x3f185be2
ATTACK nova 9223372036854775807 123456789 0 -3560766907190868264 0x3dc8ae28 0x3f290ffa true 1 0x3e2b2270 0x3f367c6b true 1693 0x3ef0b686 738 0x3f185be2
ATTACK nova -9223372036854775808 1 0 -5670227432379755445 0x3f4fd5a8 0x3f290ffa false 1 0x3f005a7a 0x3f367c6b true 1693 0x3f7863db 840 0x3f185be2
ATTACK nova -9223372036854775808 2 0 -2117082827904735082 0x3f23d0cc 0x3f290ffa true 1 0x3f338b57 0x3f367c6b true 1693 0x3e8f1336 700 0x3f185be2
ATTACK nova -9223372036854775808 7 0 -2798103879239184883 0x3f28e8bb 0x3f290ffa true 1 0x3d06d330 0x3f367c6b true 1693 0x3dedcea0 666 0x3f185be2
ATTACK nova -9223372036854775808 123456789 0 3560766907190868263 0x3ef4debe 0x3f290ffa true 1 0x3ef43a1e 0x3f367c6b true 1693 0x3f4db12a 806 0x3f185be2
ATTACK nova 31337 1 0 3553144604475010594 0x3dc0cbe0 0x3f290ffa true -1 0x3e4355e4 0x3f367c6b true 1693 0x3f618c3c 822 0x3f185be2
ATTACK nova 31337 2 0 7106289208950051583 0x3f69b9ff 0x3f290ffa false 1 0x3f216e14 0x3f367c6b true 1693 0x3e4086ac 681 0x3f185be2
ATTACK nova 31337 7 0 6425268157615584356 0x3c94c0e0 0x3f290ffa true 1 0x3ed7f3f0 0x3f367c6b true 1693 0x3e58424c 686 0x3f185be2
ATTACK nova 31337 123456789 0 -5662605129663937714 0x3f61bb92 0x3f290ffa false -1 0x3dd9d270 0x3f367c6b true 1693 0x3f36186a 787 0x3f185be2
ATTACK unicorn_32 0 1 0 3553144604475020363 0x3f2ff5a6 0x3f22339c false 1 0x3ec2da92 0x3f134bd7 true 1716 0x3f7b9cf5 854 0x3eecc3e3
ATTACK unicorn_32 0 2 0 7106289208950040726 0x3f03b0cd 0x3f22339c true -1 0x3f529a1c 0x3f134bd7 false 1716 0x3e9205d2 710 0x3eecc3e3
ATTACK unicorn_32 0 7 0 6425268157615590925 0x3f18c8bd 0x3f22339c true -1 0x3e658fa4 0x3f134bd7 true 1716 0x3dd882d0 673 0x3eecc3e3
ATTACK unicorn_32 0 123456789 0 -5662605129663907545 0x3e959eb8 0x3f22339c true -1 0x3e9226ec 0x3f134bd7 true 1716 0x3f0aa669 763 0x3eecc3e3
ATTACK unicorn_32 1700000000123 1 0 3553146293695102000 0x3ef0ae48 0x3f22339c true 1 0x3e8aa844 0x3f134bd7 true 1716 0x3f665f63 837 0x3eecc3e3
ATTACK unicorn_32 1700000000123 2 0 7106290887387103469 0x3ec320b0 0x3f22339c true -1 0x3f0d6f47 0x3f134bd7 true 1716 0x3e958b48 712 0x3eecc3e3
ATTACK unicorn_32 1700000000123 7 0 6425267583119468150 0x3ea8d0fe 0x3f22339c true -1 0x3e5e3530 0x3f134bd7 true 1716 0x3d85aa60 665 0x3eecc3e3
ATTACK unicorn_32 1700000000123 123456789 0 -5662604553032920740 0x3f49f1da 0x3f22339c false -1 0x3e8f5b1e 0x3f134bd7 true 1716 0x3f51abf5 820 0x3eecc3e3
ATTACK unicorn_32 -987654321 1 0 -3553144605451631868 0x3ed69eaa 0x3f22339c true -1 0x3da57b00 0x3f134bd7 true 1716 0x3f5a680e 827 0x3eecc3e3
ATTACK unicorn_32 -987654321 2 0 -7106289209852739623 0x3e7a1884 0x3f22339c true 1 0x3e8a2d68 0x3f134bd7 true 1716 0x3e1b2928 683 0x3eecc3e3
ATTACK unicorn_32 -987654321 7 0 -6425268158324549310 0x3e7db7a8 0x3f22339c true 1 0x3ef0449e 0x3f134bd7 true 1716 0x3e72ea08 700 0x3eecc3e3
ATTACK unicorn_32 -987654321 123456789 0 5662605129819516520 0x3f24f5af 0x3f22339c false 1 0x3ce26d60 0x3f134bd7 true 1716 0x3f6db4fb 843 0x3eecc3e3
ATTACK unicorn_32 9223372036854775807 1 0 5670227432379755444 0x3f2e2f43 0x3f22339c false -1 0x3d731f10 0x3f134bd7 true 1716 0x3cba3ae0 656 0x3eecc3e3
ATTACK unicorn_32 9223372036854775807 2 0 2117082827904735081 0x3f616743 0x3f22339c false -1 0x3f2054c3 0x3f134bd7 false 1716 0x3f3d3783 804 0x3eecc3e3
ATTACK unicorn_32 9223372036854775807 7 0 2798103879239184882 0x3f4a9104 0x3f22339c false 1 0x3eb7517c 0x3f134bd7 true 1716 0x3f6743ba 838 0x3eecc3e3
ATTACK unicorn_32 9223372036854775807 123456789 0 -3560766907190868264 0x3dc8ae28 0x3f22339c true 1 0x3e2b2270 0x3f134bd7 true 1716 0x3ef0b686 748 0x3eecc3e3
ATTACK unicorn_32 -9223372036854775808 1 0 -5670227432379755445 0x3f4fd5a8 0x3f22339c false 1 0x3f005a7a 0x3f134bd7 true 1716 0x3f7863db 851 0x3eecc3e3
ATTACK unicorn_32 -9223372036854775808 2 0 -2117082827904735082 0x3f23d0cc 0x3f22339c false 1 0x3f338b57 0x3f134bd7 false 1716 0x3e8f1336 709 0x3eecc3e3
ATTACK unicorn_32 -9223372036854775808 7 0 -2798103879239184883 0x3f28e8bb 0x3f22339c false 1 0x3d06d330 0x3f134bd7 true 1716 0x3dedcea0 675 0x3eecc3e3
ATTACK unicorn_32 -9223372036854775808 123456789 0 3560766907190868263 0x3ef4debe 0x3f22339c true 1 0x3ef43a1e 0x3f134bd7 true 1716 0x3f4db12a 817 0x3eecc3e3
ATTACK unicorn_32 31337 1 0 3553144604475010594 0x3dc0cbe0 0x3f22339c true -1 0x3e4355e4 0x3f134bd7 true 1716 0x3f618c3c 833 0x3eecc3e3
ATTACK unicorn_32 31337 2 0 7106289208950051583 0x3f69b9ff 0x3f22339c false 1 0x3f216e14 0x3f134bd7 false 1716 0x3e4086ac 690 0x3eecc3e3
ATTACK unicorn_32 31337 7 0 6425268157615584356 0x3c94c0e0 0x3f22339c true 1 0x3ed7f3f0 0x3f134bd7 true 1716 0x3e58424c 695 0x3eecc3e3
ATTACK unicorn_32 31337 123456789 0 -5662605129663937714 0x3f61bb92 0x3f22339c false -1 0x3dd9d270 0x3f134bd7 true 1716 0x3f36186a 798 0x3eecc3e3
ATTACK coach_67 0 1 0 3553144604475020363 0x3f2ff5a6 0x3f1c91d2 false 1 0x3ec2da92 0x3f173754 true 1770 0x3f7b9cf5 881 0x3ef455a7
ATTACK coach_67 0 2 0 7106289208950040726 0x3f03b0cd 0x3f1c91d2 true -1 0x3f529a1c 0x3f173754 false 1770 0x3e9205d2 733 0x3ef455a7
ATTACK coach_67 0 7 0 6425268157615590925 0x3f18c8bd 0x3f1c91d2 true -1 0x3e658fa4 0x3f173754 true 1770 0x3dd882d0 695 0x3ef455a7
ATTACK coach_67 0 123456789 0 -5662605129663907545 0x3e959eb8 0x3f1c91d2 true -1 0x3e9226ec 0x3f173754 true 1770 0x3f0aa669 787 0x3ef455a7
ATTACK coach_67 1700000000123 1 0 3553146293695102000 0x3ef0ae48 0x3f1c91d2 true 1 0x3e8aa844 0x3f173754 true 1770 0x3f665f63 863 0x3ef455a7
ATTACK coach_67 1700000000123 2 0 7106290887387103469 0x3ec320b0 0x3f1c91d2 true -1 0x3f0d6f47 0x3f173754 true 1770 0x3e958b48 734 0x3ef455a7
ATTACK coach_67 1700000000123 7 0 6425267583119468150 0x3ea8d0fe 0x3f1c91d2 true -1 0x3e5e3530 0x3f173754 true 1770 0x3d85aa60 686 0x3ef455a7
ATTACK coach_67 1700000000123 123456789 0 -5662604553032920740 0x3f49f1da 0x3f1c91d2 false -1 0x3e8f5b1e 0x3f173754 true 1770 0x3f51abf5 846 0x3ef455a7
ATTACK coach_67 -987654321 1 0 -3553144605451631868 0x3ed69eaa 0x3f1c91d2 true -1 0x3da57b00 0x3f173754 true 1770 0x3f5a680e 853 0x3ef455a7
ATTACK coach_67 -987654321 2 0 -7106289209852739623 0x3e7a1884 0x3f1c91d2 true 1 0x3e8a2d68 0x3f173754 true 1770 0x3e1b2928 704 0x3ef455a7
ATTACK coach_67 -987654321 7 0 -6425268158324549310 0x3e7db7a8 0x3f1c91d2 true 1 0x3ef0449e 0x3f173754 true 1770 0x3e72ea08 722 0x3ef455a7
ATTACK coach_67 -987654321 123456789 0 5662605129819516520 0x3f24f5af 0x3f1c91d2 false 1 0x3ce26d60 0x3f173754 true 1770 0x3f6db4fb 869 0x3ef455a7
ATTACK coach_67 9223372036854775807 1 0 5670227432379755444 0x3f2e2f43 0x3f1c91d2 false -1 0x3d731f10 0x3f173754 true 1770 0x3cba3ae0 677 0x3ef455a7
ATTACK coach_67 9223372036854775807 2 0 2117082827904735081 0x3f616743 0x3f1c91d2 false -1 0x3f2054c3 0x3f173754 false 1770 0x3f3d3783 829 0x3ef455a7
ATTACK coach_67 9223372036854775807 7 0 2798103879239184882 0x3f4a9104 0x3f1c91d2 false 1 0x3eb7517c 0x3f173754 true 1770 0x3f6743ba 864 0x3ef455a7
ATTACK coach_67 9223372036854775807 123456789 0 -3560766907190868264 0x3dc8ae28 0x3f1c91d2 true 1 0x3e2b2270 0x3f173754 true 1770 0x3ef0b686 772 0x3ef455a7
ATTACK coach_67 -9223372036854775808 1 0 -5670227432379755445 0x3f4fd5a8 0x3f1c91d2 false 1 0x3f005a7a 0x3f173754 true 1770 0x3f7863db 878 0x3ef455a7
ATTACK coach_67 -9223372036854775808 2 0 -2117082827904735082 0x3f23d0cc 0x3f1c91d2 false 1 0x3f338b57 0x3f173754 false 1770 0x3e8f1336 731 0x3ef455a7
ATTACK coach_67 -9223372036854775808 7 0 -2798103879239184883 0x3f28e8bb 0x3f1c91d2 false 1 0x3d06d330 0x3f173754 true 1770 0x3dedcea0 697 0x3ef455a7
ATTACK coach_67 -9223372036854775808 123456789 0 3560766907190868263 0x3ef4debe 0x3f1c91d2 true 1 0x3ef43a1e 0x3f173754 true 1770 0x3f4db12a 843 0x3ef455a7
ATTACK coach_67 31337 1 0 3553144604475010594 0x3dc0cbe0 0x3f1c91d2 true -1 0x3e4355e4 0x3f173754 true 1770 0x3f618c3c 859 0x3ef455a7
ATTACK coach_67 31337 2 0 7106289208950051583 0x3f69b9ff 0x3f1c91d2 false 1 0x3f216e14 0x3f173754 false 1770 0x3e4086ac 712 0x3ef455a7
ATTACK coach_67 31337 7 0 6425268157615584356 0x3c94c0e0 0x3f1c91d2 true 1 0x3ed7f3f0 0x3f173754 true 1770 0x3e58424c 717 0x3ef455a7
ATTACK coach_67 31337 123456789 0 -5662605129663937714 0x3f61bb92 0x3f1c91d2 false -1 0x3dd9d270 0x3f173754 true 1770 0x3f36186a 823 0x3ef455a7
ATTACK zephyr 0 1 0 3553144604475020363 0x3f2ff5a6 0x3f2c710d false 1 0x3ec2da92 0x3f30c8cd true 1652 0x3f7b9cf5 822 0x3f12da98
ATTACK zephyr 0 2 0 7106289208950040726 0x3f03b0cd 0x3f2c710d true -1 0x3f529a1c 0x3f30c8cd false 1652 0x3e9205d2 684 0x3f12da98
ATTACK zephyr 0 7 0 6425268157615590925 0x3f18c8bd 0x3f2c710d true -1 0x3e658fa4 0x3f30c8cd true 1652 0x3dd882d0 648 0x3f12da98
ATTACK zephyr 0 123456789 0 -5662605129663907545 0x3e959eb8 0x3f2c710d true -1 0x3e9226ec 0x3f30c8cd true 1652 0x3f0aa669 735 0x3f12da98
ATTACK zephyr 1700000000123 1 0 3553146293695102000 0x3ef0ae48 0x3f2c710d true 1 0x3e8aa844 0x3f30c8cd true 1652 0x3f665f63 806 0x3f12da98
ATTACK zephyr 1700000000123 2 0 7106290887387103469 0x3ec320b0 0x3f2c710d true -1 0x3f0d6f47 0x3f30c8cd true 1652 0x3e958b48 685 0x3f12da98
ATTACK zephyr 1700000000123 7 0 6425267583119468150 0x3ea8d0fe 0x3f2c710d true -1 0x3e5e3530 0x3f30c8cd true 1652 0x3d85aa60 640 0x3f12da98
ATTACK zephyr 1700000000123 123456789 0 -5662604553032920740 0x3f49f1da 0x3f2c710d false -1 0x3e8f5b1e 0x3f30c8cd true 1652 0x3f51abf5 790 0x3f12da98
ATTACK zephyr -987654321 1 0 -3553144605451631868 0x3ed69eaa 0x3f2c710d true -1 0x3da57b00 0x3f30c8cd true 1652 0x3f5a680e 796 0x3f12da98
ATTACK zephyr -987654321 2 0 -7106289209852739623 0x3e7a1884 0x3f2c710d true 1 0x3e8a2d68 0x3f30c8cd true 1652 0x3e1b2928 657 0x3f12da98
ATTACK zephyr -987654321 7 0 -6425268158324549310 0x3e7db7a8 0x3f2c710d true 1 0x3ef0449e 0x3f30c8cd true 1652 0x3e72ea08 674 0x3f12da98
ATTACK zephyr -987654321 123456789 0 5662605129819516520 0x3f24f5af 0x3f2c710d true 1 0x3ce26d60 0x3f30c8cd true 1652 0x3f6db4fb 811 0x3f12da98
ATTACK zephyr 9223372036854775807 1 0 5670227432379755444 0x3f2e2f43 0x3f2c710d false -1 0x3d731f10 0x3f30c8cd true 1652 0x3cba3ae0 632 0x3f12da98
ATTACK zephyr 9223372036854775807 2 0 2117082827904735081 0x3f616743 0x3f2c710d false -1 0x3f2054c3 0x3f30c8cd true 1652 0x3f3d3783 774 0x3f12da98
ATTACK zephyr 9223372036854775807 7 0 2798103879239184882 0x3f4a9104 0x3f2c710d false 1 0x3eb7517c 0x3f30c8cd true 1652 0x3f6743ba 806 0x3f12da98
ATTACK zephyr 9223372036854775807 123456789 0 -3560766907190868264 0x3dc8ae28 0x3f2c710d true 1 0x3e2b2270 0x3f30c8cd true 1652 0x3ef0b686 720 0x3f12da98
ATTACK zephyr -9223372036854775808 1 0 -5670227432379755445 0x3f4fd5a8 0x3f2c710d false 1 0x3f005a7a 0x3f30c8cd true 1652 0x3f7863db 820 0x3f12da98
ATTACK zephyr -9223372036854775808 2 0 -2117082827904735082 0x3f23d0cc 0x3f2c710d true 1 0x3f338b57 0x3f30c8cd false 1652 0x3e8f1336 683 0x3f12da98
ATTACK zephyr -9223372036854775808 7 0 -2798103879239184883 0x3f28e8bb 0x3f2c710d true 1 0x3d06d330 0x3f30c8cd true 1652 0x3dedcea0 650 0x3f12da98
ATTACK zephyr -9223372036854775808 123456789 0 3560766907190868263 0x3ef4debe 0x3f2c710d true 1 0x3ef43a1e 0x3f30c8cd true 1652 0x3f4db12a 787 0x3f12da98
ATTACK zephyr 31337 1 0 3553144604475010594 0x3dc0cbe0 0x3f2c710d true -1 0x3e4355e4 0x3f30c8cd true 1652 0x3f618c3c 802 0x3f12da98
ATTACK zephyr 31337 2 0 7106289208950051583 0x3f69b9ff 0x3f2c710d false 1 0x3f216e14 0x3f30c8cd true 1652 0x3e4086ac 665 0x3f12da98
ATTACK zephyr 31337 7 0 6425268157615584356 0x3c94c0e0 0x3f2c710d true 1 0x3ed7f3f0 0x3f30c8cd true 1652 0x3e58424c 669 0x3f12da98
ATTACK zephyr 31337 123456789 0 -5662605129663937714 0x3f61bb92 0x3f2c710d false -1 0x3dd9d270 0x3f30c8cd true 1652 0x3f36186a 768 0x3f12da98
ATTACK kyra 0 1 0 3553144604475020363 0x3f2ff5a6 0x3f2c710d false 1 0x3ec2da92 0x3f30c8cd true 1652 0x3f7b9cf5 822 0x3f12da98
ATTACK kyra 0 2 0 7106289208950040726 0x3f03b0cd 0x3f2c710d true -1 0x3f529a1c 0x3f30c8cd false 1652 0x3e9205d2 684 0x3f12da98
ATTACK kyra 0 7 0 6425268157615590925 0x3f18c8bd 0x3f2c710d true -1 0x3e658fa4 0x3f30c8cd true 1652 0x3dd882d0 648 0x3f12da98
ATTACK kyra 0 123456789 0 -5662605129663907545 0x3e959eb8 0x3f2c710d true -1 0x3e9226ec 0x3f30c8cd true 1652 0x3f0aa669 735 0x3f12da98
ATTACK kyra 1700000000123 1 0 3553146293695102000 0x3ef0ae48 0x3f2c710d true 1 0x3e8aa844 0x3f30c8cd true 1652 0x3f665f63 806 0x3f12da98
ATTACK kyra 1700000000123 2 0 7106290887387103469 0x3ec320b0 0x3f2c710d true -1 0x3f0d6f47 0x3f30c8cd true 1652 0x3e958b48 685 0x3f12da98
ATTACK kyra 1700000000123 7 0 6425267583119468150 0x3ea8d0fe 0x3f2c710d true -1 0x3e5e3530 0x3f30c8cd true 1652 0x3d85aa60 640 0x3f12da98
ATTACK kyra 1700000000123 123456789 0 -5662604553032920740 0x3f49f1da 0x3f2c710d false -1 0x3e8f5b1e 0x3f30c8cd true 1652 0x3f51abf5 790 0x3f12da98
ATTACK kyra -987654321 1 0 -3553144605451631868 0x3ed69eaa 0x3f2c710d true -1 0x3da57b00 0x3f30c8cd true 1652 0x3f5a680e 796 0x3f12da98
ATTACK kyra -987654321 2 0 -7106289209852739623 0x3e7a1884 0x3f2c710d true 1 0x3e8a2d68 0x3f30c8cd true 1652 0x3e1b2928 657 0x3f12da98
ATTACK kyra -987654321 7 0 -6425268158324549310 0x3e7db7a8 0x3f2c710d true 1 0x3ef0449e 0x3f30c8cd true 1652 0x3e72ea08 674 0x3f12da98
ATTACK kyra -987654321 123456789 0 5662605129819516520 0x3f24f5af 0x3f2c710d true 1 0x3ce26d60 0x3f30c8cd true 1652 0x3f6db4fb 811 0x3f12da98
ATTACK kyra 9223372036854775807 1 0 5670227432379755444 0x3f2e2f43 0x3f2c710d false -1 0x3d731f10 0x3f30c8cd true 1652 0x3cba3ae0 632 0x3f12da98
ATTACK kyra 9223372036854775807 2 0 2117082827904735081 0x3f616743 0x3f2c710d false -1 0x3f2054c3 0x3f30c8cd true 1652 0x3f3d3783 774 0x3f12da98
ATTACK kyra 9223372036854775807 7 0 2798103879239184882 0x3f4a9104 0x3f2c710d false 1 0x3eb7517c 0x3f30c8cd true 1652 0x3f6743ba 806 0x3f12da98
ATTACK kyra 9223372036854775807 123456789 0 -3560766907190868264 0x3dc8ae28 0x3f2c710d true 1 0x3e2b2270 0x3f30c8cd true 1652 0x3ef0b686 720 0x3f12da98
ATTACK kyra -9223372036854775808 1 0 -5670227432379755445 0x3f4fd5a8 0x3f2c710d false 1 0x3f005a7a 0x3f30c8cd true 1652 0x3f7863db 820 0x3f12da98
ATTACK kyra -9223372036854775808 2 0 -2117082827904735082 0x3f23d0cc 0x3f2c710d true 1 0x3f338b57 0x3f30c8cd false 1652 0x3e8f1336 683 0x3f12da98
ATTACK kyra -9223372036854775808 7 0 -2798103879239184883 0x3f28e8bb 0x3f2c710d true 1 0x3d06d330 0x3f30c8cd true 1652 0x3dedcea0 650 0x3f12da98
ATTACK kyra -9223372036854775808 123456789 0 3560766907190868263 0x3ef4debe 0x3f2c710d true 1 0x3ef43a1e 0x3f30c8cd true 1652 0x3f4db12a 787 0x3f12da98
ATTACK kyra 31337 1 0 3553144604475010594 0x3dc0cbe0 0x3f2c710d true -1 0x3e4355e4 0x3f30c8cd true 1652 0x3f618c3c 802 0x3f12da98
ATTACK kyra 31337 2 0 7106289208950051583 0x3f69b9ff 0x3f2c710d false 1 0x3f216e14 0x3f30c8cd true 1652 0x3e4086ac 665 0x3f12da98
ATTACK kyra 31337 7 0 6425268157615584356 0x3c94c0e0 0x3f2c710d true 1 0x3ed7f3f0 0x3f30c8cd true 1652 0x3e58424c 669 0x3f12da98
ATTACK kyra 31337 123456789 0 -5662605129663937714 0x3f61bb92 0x3f2c710d false -1 0x3dd9d270 0x3f30c8cd true 1652 0x3f36186a 768 0x3f12da98
ATTACK kyra_original 0 1 0 3553144604475020363 0x3f2ff5a6 0x3f2c710d false 1 0x3ec2da92 0x3f30c8cd true 1652 0x3f7b9cf5 822 0x3f12da98
ATTACK kyra_original 0 2 0 7106289208950040726 0x3f03b0cd 0x3f2c710d true -1 0x3f529a1c 0x3f30c8cd false 1652 0x3e9205d2 684 0x3f12da98
ATTACK kyra_original 0 7 0 6425268157615590925 0x3f18c8bd 0x3f2c710d true -1 0x3e658fa4 0x3f30c8cd true 1652 0x3dd882d0 648 0x3f12da98
ATTACK kyra_original 0 123456789 0 -5662605129663907545 0x3e959eb8 0x3f2c710d true -1 0x3e9226ec 0x3f30c8cd true 1652 0x3f0aa669 735 0x3f12da98
ATTACK kyra_original 1700000000123 1 0 3553146293695102000 0x3ef0ae48 0x3f2c710d true 1 0x3e8aa844 0x3f30c8cd true 1652 0x3f665f63 806 0x3f12da98
ATTACK kyra_original 1700000000123 2 0 7106290887387103469 0x3ec320b0 0x3f2c710d true -1 0x3f0d6f47 0x3f30c8cd true 1652 0x3e958b48 685 0x3f12da98
ATTACK kyra_original 1700000000123 7 0 6425267583119468150 0x3ea8d0fe 0x3f2c710d true -1 0x3e5e3530 0x3f30c8cd true 1652 0x3d85aa60 640 0x3f12da98
ATTACK kyra_original 1700000000123 123456789 0 -5662604553032920740 0x3f49f1da 0x3f2c710d false -1 0x3e8f5b1e 0x3f30c8cd true 1652 0x3f51abf5 790 0x3f12da98
ATTACK kyra_original -987654321 1 0 -3553144605451631868 0x3ed69eaa 0x3f2c710d true -1 0x3da57b00 0x3f30c8cd true 1652 0x3f5a680e 796 0x3f12da98
ATTACK kyra_original -987654321 2 0 -7106289209852739623 0x3e7a1884 0x3f2c710d true 1 0x3e8a2d68 0x3f30c8cd true 1652 0x3e1b2928 657 0x3f12da98
ATTACK kyra_original -987654321 7 0 -6425268158324549310 0x3e7db7a8 0x3f2c710d true 1 0x3ef0449e 0x3f30c8cd true 1652 0x3e72ea08 674 0x3f12da98
ATTACK kyra_original -987654321 123456789 0 5662605129819516520 0x3f24f5af 0x3f2c710d true 1 0x3ce26d60 0x3f30c8cd true 1652 0x3f6db4fb 811 0x3f12da98
ATTACK kyra_original 9223372036854775807 1 0 5670227432379755444 0x3f2e2f43 0x3f2c710d false -1 0x3d731f10 0x3f30c8cd true 1652 0x3cba3ae0 632 0x3f12da98
ATTACK kyra_original 9223372036854775807 2 0 2117082827904735081 0x3f616743 0x3f2c710d false -1 0x3f2054c3 0x3f30c8cd true 1652 0x3f3d3783 774 0x3f12da98
ATTACK kyra_original 9223372036854775807 7 0 2798103879239184882 0x3f4a9104 0x3f2c710d false 1 0x3eb7517c 0x3f30c8cd true 1652 0x3f6743ba 806 0x3f12da98
ATTACK kyra_original 9223372036854775807 123456789 0 -3560766907190868264 0x3dc8ae28 0x3f2c710d true 1 0x3e2b2270 0x3f30c8cd true 1652 0x3ef0b686 720 0x3f12da98
ATTACK kyra_original -9223372036854775808 1 0 -5670227432379755445 0x3f4fd5a8 0x3f2c710d false 1 0x3f005a7a 0x3f30c8cd true 1652 0x3f7863db 820 0x3f12da98
ATTACK kyra_original -9223372036854775808 2 0 -2117082827904735082 0x3f23d0cc 0x3f2c710d true 1 0x3f338b57 0x3f30c8cd false 1652 0x3e8f1336 683 0x3f12da98
ATTACK kyra_original -9223372036854775808 7 0 -2798103879239184883 0x3f28e8bb 0x3f2c710d true 1 0x3d06d330 0x3f30c8cd true 1652 0x3dedcea0 650 0x3f12da98
ATTACK kyra_original -9223372036854775808 123456789 0 3560766907190868263 0x3ef4debe 0x3f2c710d true 1 0x3ef43a1e 0x3f30c8cd true 1652 0x3f4db12a 787 0x3f12da98
ATTACK kyra_original 31337 1 0 3553144604475010594 0x3dc0cbe0 0x3f2c710d true -1 0x3e4355e4 0x3f30c8cd true 1652 0x3f618c3c 802 0x3f12da98
ATTACK kyra_original 31337 2 0 7106289208950051583 0x3f69b9ff 0x3f2c710d false 1 0x3f216e14 0x3f30c8cd true 1652 0x3e4086ac 665 0x3f12da98
ATTACK kyra_original 31337 7 0 6425268157615584356 0x3c94c0e0 0x3f2c710d true 1 0x3ed7f3f0 0x3f30c8cd true 1652 0x3e58424c 669 0x3f12da98
ATTACK kyra_original 31337 123456789 0 -5662605129663937714 0x3f61bb92 0x3f2c710d false -1 0x3dd9d270 0x3f30c8cd true 1652 0x3f36186a 768 0x3f12da98
ATTACK flare 0 1 0 3553144604475020363 0x3f2ff5a6 0x3f32fec5 true 1 0x3ec2da92 0x3f356323 true 1602 0x3f7b9cf5 797 0x3f174c4d
ATTACK flare 0 2 0 7106289208950040726 0x3f03b0cd 0x3f32fec5 true -1 0x3f529a1c 0x3f356323 false 1602 0x3e9205d2 663 0x3f174c4d
ATTACK flare 0 7 0 6425268157615590925 0x3f18c8bd 0x3f32fec5 true -1 0x3e658fa4 0x3f356323 true 1602 0x3dd882d0 629 0x3f174c4d
ATTACK flare 0 123456789 0 -5662605129663907545 0x3e959eb8 0x3f32fec5 true -1 0x3e9226ec 0x3f356323 true 1602 0x3f0aa669 712 0x3f174c4d
ATTACK flare 1700000000123 1 0 3553146293695102000 0x3ef0ae48 0x3f32fec5 true 1 0x3e8aa844 0x3f356323 true 1602 0x3f665f63 781 0x3f174c4d
ATTACK flare 1700000000123 2 0 7106290887387103469 0x3ec320b0 0x3f32fec5 true -1 0x3f0d6f47 0x3f356323 true 1602 0x3e958b48 664 0x3f174c4d
ATTACK flare 1700000000123 7 0 6425267583119468150 0x3ea8d0fe 0x3f32fec5 true -1 0x3e5e3530 0x3f356323 true 1602 0x3d85aa60 621 0x3f174c4d
ATTACK flare 1700000000123 123456789 0 -5662604553032920740 0x3f49f1da 0x3f32fec5 false -1 0x3e8f5b1e 0x3f356323 true 1602 0x3f51abf5 766 0x3f174c4d
ATTACK flare -987654321 1 0 -3553144605451631868 0x3ed69eaa 0x3f32fec5 true -1 0x3da57b00 0x3f356323 true 1602 0x3f5a680e 772 0x3f174c4d
ATTACK flare -987654321 2 0 -7106289209852739623 0x3e7a1884 0x3f32fec5 true 1 0x3e8a2d68 0x3f356323 true 1602 0x3e1b2928 637 0x3f174c4d
ATTACK flare -987654321 7 0 -6425268158324549310 0x3e7db7a8 0x3f32fec5 true 1 0x3ef0449e 0x3f356323 true 1602 0x3e72ea08 654 0x3f174c4d
ATTACK flare -987654321 123456789 0 5662605129819516520 0x3f24f5af 0x3f32fec5 true 1 0x3ce26d60 0x3f356323 true 1602 0x3f6db4fb 787 0x3f174c4d
ATTACK flare 9223372036854775807 1 0 5670227432379755444 0x3f2e2f43 0x3f32fec5 true -1 0x3d731f10 0x3f356323 true 1602 0x3cba3ae0 613 0x3f174c4d
ATTACK flare 9223372036854775807 2 0 2117082827904735081 0x3f616743 0x3f32fec5 false -1 0x3f2054c3 0x3f356323 true 1602 0x3f3d3783 750 0x3f174c4d
ATTACK flare 9223372036854775807 7 0 2798103879239184882 0x3f4a9104 0x3f32fec5 false 1 0x3eb7517c 0x3f356323 true 1602 0x3f6743ba 782 0x3f174c4d
ATTACK flare 9223372036854775807 123456789 0 -3560766907190868264 0x3dc8ae28 0x3f32fec5 true 1 0x3e2b2270 0x3f356323 true 1602 0x3ef0b686 699 0x3f174c4d
ATTACK flare -9223372036854775808 1 0 -5670227432379755445 0x3f4fd5a8 0x3f32fec5 false 1 0x3f005a7a 0x3f356323 true 1602 0x3f7863db 795 0x3f174c4d
ATTACK flare -9223372036854775808 2 0 -2117082827904735082 0x3f23d0cc 0x3f32fec5 true 1 0x3f338b57 0x3f356323 true 1602 0x3e8f1336 662 0x3f174c4d
ATTACK flare -9223372036854775808 7 0 -2798103879239184883 0x3f28e8bb 0x3f32fec5 true 1 0x3d06d330 0x3f356323 true 1602 0x3dedcea0 631 0x3f174c4d
ATTACK flare -9223372036854775808 123456789 0 3560766907190868263 0x3ef4debe 0x3f32fec5 true 1 0x3ef43a1e 0x3f356323 true 1602 0x3f4db12a 763 0x3f174c4d
ATTACK flare 31337 1 0 3553144604475010594 0x3dc0cbe0 0x3f32fec5 true -1 0x3e4355e4 0x3f356323 true 1602 0x3f618c3c 778 0x3f174c4d
ATTACK flare 31337 2 0 7106289208950051583 0x3f69b9ff 0x3f32fec5 false 1 0x3f216e14 0x3f356323 true 1602 0x3e4086ac 644 0x3f174c4d
ATTACK flare 31337 7 0 6425268157615584356 0x3c94c0e0 0x3f32fec5 true 1 0x3ed7f3f0 0x3f356323 true 1602 0x3e58424c 649 0x3f174c4d
ATTACK flare 31337 123456789 0 -5662605129663937714 0x3f61bb92 0x3f32fec5 false -1 0x3dd9d270 0x3f356323 true 1602 0x3f36186a 745 0x3f174c4d
ATTACK ace_23 0 1 0 3553144604475020363 0x3f2ff5a6 0x3f2ae7d5 false 1 0x3ec2da92 0x3f3c6cda true 1702 0x3f7b9cf5 847 0x3f1e17e3
ATTACK ace_23 0 2 0 7106289208950040726 0x3f03b0cd 0x3f2ae7d5 true -1 0x3f529a1c 0x3f3c6cda false 1702 0x3e9205d2 705 0x3f1e17e3
ATTACK ace_23 0 7 0 6425268157615590925 0x3f18c8bd 0x3f2ae7d5 true -1 0x3e658fa4 0x3f3c6cda true 1702 0x3dd882d0 668 0x3f1e17e3
ATTACK ace_23 0 123456789 0 -5662605129663907545 0x3e959eb8 0x3f2ae7d5 true -1 0x3e9226ec 0x3f3c6cda true 1702 0x3f0aa669 757 0x3f1e17e3
ATTACK ace_23 1700000000123 1 0 3553146293695102000 0x3ef0ae48 0x3f2ae7d5 true 1 0x3e8aa844 0x3f3c6cda true 1702 0x3f665f63 830 0x3f1e17e3
ATTACK ace_23 1700000000123 2 0 7106290887387103469 0x3ec320b0 0x3f2ae7d5 true -1 0x3f0d6f47 0x3f3c6cda true 1702 0x3e958b48 706 0x3f1e17e3
ATTACK ace_23 1700000000123 7 0 6425267583119468150 0x3ea8d0fe 0x3f2ae7d5 true -1 0x3e5e3530 0x3f3c6cda true 1702 0x3d85aa60 660 0x3f1e17e3
ATTACK ace_23 1700000000123 123456789 0 -5662604553032920740 0x3f49f1da 0x3f2ae7d5 false -1 0x3e8f5b1e 0x3f3c6cda true 1702 0x3f51abf5 814 0x3f1e17e3
ATTACK ace_23 -987654321 1 0 -3553144605451631868 0x3ed69eaa 0x3f2ae7d5 true -1 0x3da57b00 0x3f3c6cda true 1702 0x3f5a680e 821 0x3f1e17e3
ATTACK ace_23 -987654321 2 0 -7106289209852739623 0x3e7a1884 0x3f2ae7d5 true 1 0x3e8a2d68 0x3f3c6cda true 1702 0x3e1b2928 677 0x3f1e17e3
ATTACK ace_23 -987654321 7 0 -6425268158324549310 0x3e7db7a8 0x3f2ae7d5 true 1 0x3ef0449e 0x3f3c6cda true 1702 0x3e72ea08 695 0x3f1e17e3
ATTACK ace_23 -987654321 123456789 0 5662605129819516520 0x3f24f5af 0x3f2ae7d5 true 1 0x3ce26d60 0x3f3c6cda true 1702 0x3f6db4fb 836 0x3f1e17e3
ATTACK ace_23 9223372036854775807 1 0 5670227432379755444 0x3f2e2f43 0x3f2ae7d5 false -1 0x3d731f10 0x3f3c6cda true 1702 0x3cba3ae0 651 0x3f1e17e3
ATTACK ace_23 9223372036854775807 2 0 2117082827904735081 0x3f616743 0x3f2ae7d5 false -1 0x3f2054c3 0x3f3c6cda true 1702 0x3f3d3783 797 0x3f1e17e3
ATTACK ace_23 9223372036854775807 7 0 2798103879239184882 0x3f4a9104 0x3f2ae7d5 false 1 0x3eb7517c 0x3f3c6cda true 1702 0x3f6743ba 831 0x3f1e17e3
ATTACK ace_23 9223372036854775807 123456789 0 -3560766907190868264 0x3dc8ae28 0x3f2ae7d5 true 1 0x3e2b2270 0x3f3c6cda true 1702 0x3ef0b686 742 0x3f1e17e3
ATTACK ace_23 -9223372036854775808 1 0 -5670227432379755445 0x3f4fd5a8 0x3f2ae7d5 false 1 0x3f005a7a 0x3f3c6cda true 1702 0x3f7863db 844 0x3f1e17e3
ATTACK ace_23 -9223372036854775808 2 0 -2117082827904735082 0x3f23d0cc 0x3f2ae7d5 true 1 0x3f338b57 0x3f3c6cda true 1702 0x3e8f1336 703 0x3f1e17e3
ATTACK ace_23 -9223372036854775808 7 0 -2798103879239184883 0x3f28e8bb 0x3f2ae7d5 true 1 0x3d06d330 0x3f3c6cda true 1702 0x3dedcea0 670 0x3f1e17e3
ATTACK ace_23 -9223372036854775808 123456789 0 3560766907190868263 0x3ef4debe 0x3f2ae7d5 true 1 0x3ef43a1e 0x3f3c6cda true 1702 0x3f4db12a 810 0x3f1e17e3
ATTACK ace_23 31337 1 0 3553144604475010594 0x3dc0cbe0 0x3f2ae7d5 true -1 0x3e4355e4 0x3f3c6cda true 1702 0x3f618c3c 826 0x3f1e17e3
ATTACK ace_23 31337 2 0 7106289208950051583 0x3f69b9ff 0x3f2ae7d5 false 1 0x3f216e14 0x3f3c6cda true 1702 0x3e4086ac 685 0x3f1e17e3
ATTACK ace_23 31337 7 0 6425268157615584356 0x3c94c0e0 0x3f2ae7d5 true 1 0x3ed7f3f0 0x3f3c6cda true 1702 0x3e58424c 689 0x3f1e17e3
ATTACK ace_23 31337 123456789 0 -5662605129663937714 0x3f61bb92 0x3f2ae7d5 false -1 0x3dd9d270 0x3f3c6cda true 1702 0x3f36186a 792 0x3f1e17e3
ATTACK buddy_23 0 1 0 3553144604475020363 0x3f2ff5a6 0x3f3851ec true 1 0x3ec2da92 0x3f3ba732 true 1563 0x3f7b9cf5 778 0x3f1d590c
ATTACK buddy_23 0 2 0 7106289208950040726 0x3f03b0cd 0x3f3851ec true -1 0x3f529a1c 0x3f3ba732 false 1563 0x3e9205d2 647 0x3f1d590c
ATTACK buddy_23 0 7 0 6425268157615590925 0x3f18c8bd 0x3f3851ec true -1 0x3e658fa4 0x3f3ba732 true 1563 0x3dd882d0 613 0x3f1d590c
ATTACK buddy_23 0 123456789 0 -5662605129663907545 0x3e959eb8 0x3f3851ec true -1 0x3e9226ec 0x3f3ba732 true 1563 0x3f0aa669 695 0x3f1d590c
ATTACK buddy_23 1700000000123 1 0 3553146293695102000 0x3ef0ae48 0x3f3851ec true 1 0x3e8aa844 0x3f3ba732 true 1563 0x3f665f63 762 0x3f1d590c
ATTACK buddy_23 1700000000123 2 0 7106290887387103469 0x3ec320b0 0x3f3851ec true -1 0x3f0d6f47 0x3f3ba732 true 1563 0x3e958b48 648 0x3f1d590c
ATTACK buddy_23 1700000000123 7 0 6425267583119468150 0x3ea8d0fe 0x3f3851ec true -1 0x3e5e3530 0x3f3ba732 true 1563 0x3d85aa60 606 0x3f1d590c
ATTACK buddy_23 1700000000123 123456789 0 -5662604553032920740 0x3f49f1da 0x3f3851ec false -1 0x3e8f5b1e 0x3f3ba732 true 1563 0x3f51abf5 747 0x3f1d590c
ATTACK buddy_23 -987654321 1 0 -3553144605451631868 0x3ed69eaa 0x3f3851ec true -1 0x3da57b00 0x3f3ba732 true 1563 0x3f5a680e 753 0x3f1d590c
ATTACK buddy_23 -987654321 2 0 -7106289209852739623 0x3e7a1884 0x3f3851ec true 1 0x3e8a2d68 0x3f3ba732 true 1563 0x3e1b2928 622 0x3f1d590c
ATTACK buddy_23 -987654321 7 0 -6425268158324549310 0x3e7db7a8 0x3f3851ec true 1 0x3ef0449e 0x3f3ba732 true 1563 0x3e72ea08 638 0x3f1d590c
ATTACK buddy_23 -987654321 123456789 0 5662605129819516520 0x3f24f5af 0x3f3851ec true 1 0x3ce26d60 0x3f3ba732 true 1563 0x3f6db4fb 768 0x3f1d590c
ATTACK buddy_23 9223372036854775807 1 0 5670227432379755444 0x3f2e2f43 0x3f3851ec true -1 0x3d731f10 0x3f3ba732 true 1563 0x3cba3ae0 598 0x3f1d590c
ATTACK buddy_23 9223372036854775807 2 0 2117082827904735081 0x3f616743 0x3f3851ec false -1 0x3f2054c3 0x3f3ba732 true 1563 0x3f3d3783 732 0x3f1d590c
ATTACK buddy_23 9223372036854775807 7 0 2798103879239184882 0x3f4a9104 0x3f3851ec false 1 0x3eb7517c 0x3f3ba732 true 1563 0x3f6743ba 763 0x3f1d590c
ATTACK buddy_23 9223372036854775807 123456789 0 -3560766907190868264 0x3dc8ae28 0x3f3851ec true 1 0x3e2b2270 0x3f3ba732 true 1563 0x3ef0b686 682 0x3f1d590c
ATTACK buddy_23 -9223372036854775808 1 0 -5670227432379755445 0x3f4fd5a8 0x3f3851ec false 1 0x3f005a7a 0x3f3ba732 true 1563 0x3f7863db 775 0x3f1d590c
ATTACK buddy_23 -9223372036854775808 2 0 -2117082827904735082 0x3f23d0cc 0x3f3851ec true 1 0x3f338b57 0x3f3ba732 true 1563 0x3e8f1336 646 0x3f1d590c
ATTACK buddy_23 -9223372036854775808 7 0 -2798103879239184883 0x3f28e8bb 0x3f3851ec true 1 0x3d06d330 0x3f3ba732 true 1563 0x3dedcea0 615 0x3f1d590c
ATTACK buddy_23 -9223372036854775808 123456789 0 3560766907190868263 0x3ef4debe 0x3f3851ec true 1 0x3ef43a1e 0x3f3ba732 true 1563 0x3f4db12a 744 0x3f1d590c
ATTACK buddy_23 31337 1 0 3553144604475010594 0x3dc0cbe0 0x3f3851ec true -1 0x3e4355e4 0x3f3ba732 true 1563 0x3f618c3c 759 0x3f1d590c
ATTACK buddy_23 31337 2 0 7106289208950051583 0x3f69b9ff 0x3f3851ec false 1 0x3f216e14 0x3f3ba732 true 1563 0x3e4086ac 629 0x3f1d590c
ATTACK buddy_23 31337 7 0 6425268157615584356 0x3c94c0e0 0x3f3851ec true 1 0x3ed7f3f0 0x3f3ba732 true 1563 0x3e58424c 633 0x3f1d590c
ATTACK buddy_23 31337 123456789 0 -5662605129663937714 0x3f61bb92 0x3f3851ec false -1 0x3dd9d270 0x3f3ba732 true 1563 0x3f36186a 727 0x3f1d590c
"""

    private static let chooseData = """
CHOOSE bob 0 0,0,100,0 - 1 -649160781
CHOOSE bob 3 0,0,100,0 3 0 -256771609
CHOOSE bob 4 0,0,100,0 0,1,3 2 483757236
CHOOSE bob 2 0,0,100,0 2 3 15345335
CHOOSE bob -7046029254386353131 100,0,0,0 0 2 -1365818593
CHOOSE bob -7046029254386353132 100,0,0,0 0,1 2 -680557870
CHOOSE bob -7046029254386353133 100,0,0,0 0,1,2,3 0 -1155246353
CHOOSE bob 4354685564936845354 0,100,100,0 - 3 8227251
CHOOSE bob 4354685564936845353 0,100,100,0 3 2 540114653
CHOOSE bob 4354685564936845358 0,100,100,0 0,1,3 2 375527510
CHOOSE bob 4354685564936845352 0,100,100,0 2 1 1209648652
CHOOSE bob -2691343689449507777 50,100,0 0 1 -1617943258
CHOOSE bob -2691343689449507778 50,100,0 0,1 2 -2023231751
CHOOSE bob -2691343689449507783 50,100,0 0,1,2,3 0 -1924535523
CHOOSE bob 8709371129873690708 100 - 0 1062544041
CHOOSE bob 8709371129873690711 100 3 0 460658659
CHOOSE bob 8709371129873690704 100 0,1,3 0 289460337
CHOOSE bob 8709371129873690710 100 2 0 707248387
CHOOSE bob 1663341875487337577 0,0,0,0 0 3 1006811077
CHOOSE bob 1663341875487337576 0,0,0,0 0,1 3 1781489765
CHOOSE bob 1663341875487337583 0,0,0,0 0,1,2,3 0 935005358
CHOOSE bob -5382687378899015554 0,100 - 0 1510711423
CHOOSE bob -5382687378899015555 0,100 3 1 -96496139
CHOOSE bob -5382687378899015558 0,100 0,1,3 0 620622350
CHOOSE bob -5382687378899015556 0,100 2 0 833051688
CHOOSE bob 6018027440424182931 - 0 0 -317119438
CHOOSE bob 6018027440424182930 - 0,1 0 -2077701084
CHOOSE bob 6018027440424182933 - 0,1,2,3 0 1022496012
CHOOSE bob 1700000000123 0,0,100,0 - 2 -1272690835
CHOOSE bob 1700000000120 0,0,100,0 3 0 341854951
CHOOSE bob 1700000000127 0,0,100,0 0,1,3 2 348414349
CHOOSE bob 1700000000121 0,0,100,0 2 3 681492313
CHOOSE bob -7046030932889889682 100,0,0,0 0 1 -285540654
CHOOSE bob -7046030932889889681 100,0,0,0 0,1 3 697157702
CHOOSE bob -7046030932889889688 100,0,0,0 0,1,2,3 0 570740890
CHOOSE bob 4354685041804152913 0,100,100,0 - 2 -620568730
CHOOSE bob 4354685041804152914 0,100,100,0 3 2 995027484
CHOOSE bob 4354685041804152917 0,100,100,0 0,1,3 2 1762171661
CHOOSE bob 4354685041804152915 0,100,100,0 2 1 329722573
CHOOSE bob -2691344259801801660 50,100,0 0 2 2123690729
CHOOSE bob -2691344259801801659 50,100,0 0,1 2 -1761824458
CHOOSE bob -2691344259801801662 50,100,0 0,1,2,3 0 -815287062
CHOOSE bob 8709371714889095215 100 - 0 849407856
CHOOSE bob 8709371714889095212 100 3 0 1455487786
CHOOSE bob 8709371714889095211 100 0,1,3 0 -735803874
CHOOSE bob 8709371714889095213 100 2 0 638423498
CHOOSE bob 1663342378923131922 0,0,0,0 0 2 1440217742
CHOOSE bob 1663342378923131923 0,0,0,0 0,1 2 1168806318
CHOOSE bob 1663342378923131924 0,0,0,0 0,1,2,3 0 -577107181
CHOOSE bob -5382685754451591163 0,100 - 1 1141847390
CHOOSE bob -5382685754451591162 0,100 3 1 601571400
CHOOSE bob -5382685754451591167 0,100 0,1,3 0 681489403
CHOOSE bob -5382685754451591161 0,100 2 0 -323812875
CHOOSE bob 6018029120727551208 - 0 0 -289938929
CHOOSE bob 6018029120727551209 - 0,1 0 1204273633
CHOOSE bob 6018029120727551214 - 0,1,2,3 0 -1609099527
CHOOSE bob -987654321 0,0,100,0 - 3 2018681017
CHOOSE bob -987654324 0,0,100,0 3 0 677938306
CHOOSE bob -987654325 0,0,100,0 0,1,3 2 -1227801630
CHOOSE bob -987654323 0,0,100,0 2 1 817937999
CHOOSE bob 7046029255354608474 100,0,0,0 0 3 -2096770713
CHOOSE bob 7046029255354608475 100,0,0,0 0,1 3 -1705141708
CHOOSE bob 7046029255354608476 100,0,0,0 0,1,2,3 0 -151344836
CHOOSE bob -4354685563958890651 0,100,100,0 - 1 -821726509
CHOOSE bob -4354685563958890650 0,100,100,0 3 0 1866556905
CHOOSE bob -4354685563958890655 0,100,100,0 0,1,3 2 -816221640
CHOOSE bob -4354685563958890649 0,100,100,0 2 1 862717469
CHOOSE bob 2691343690370048880 50,100,0 0 1 1922760480
CHOOSE bob 2691343690370048881 50,100,0 0,1 2 1257455053
CHOOSE bob 2691343690370048886 50,100,0 0,1,2,3 0 -999344884
CHOOSE bob -8709371128981199077 100 - 0 -661791267
CHOOSE bob -8709371128981199080 100 3 0 1953352371
CHOOSE bob -8709371128981199073 100 0,1,3 0 -384171016
CHOOSE bob -8709371128981199079 100 2 0 -467506285
CHOOSE bob -1663341874584880346 0,0,0,0 0 1 -1270019391
CHOOSE bob -1663341874584880345 0,0,0,0 0,1 2 58174497
CHOOSE bob -1663341874584880352 0,0,0,0 0,1,2,3 0 312729399
CHOOSE bob 5382687379878281009 0,100 - 0 -1206273081
CHOOSE bob 5382687379878281010 0,100 3 1 -673861871
CHOOSE bob 5382687379878281013 0,100 0,1,3 0 1537812055
CHOOSE bob 5382687379878281011 0,100 2 1 879289766
CHOOSE bob -6018027439464582180 - 0 0 -1010862029
CHOOSE bob -6018027439464582179 - 0,1 0 1523587077
CHOOSE bob -6018027439464582182 - 0,1,2,3 0 1930978077
CHOOSE bob 9223372036854775807 0,0,100,0 - 2 1402130883
CHOOSE bob 9223372036854775804 0,0,100,0 3 2 869190749
CHOOSE bob 9223372036854775803 0,0,100,0 0,1,3 2 660863589
CHOOSE bob 9223372036854775805 0,0,100,0 2 1 -63502804
CHOOSE bob -2177342782468422678 100,0,0,0 0 1 1246501186
CHOOSE bob -2177342782468422677 100,0,0,0 0,1 2 565436945
CHOOSE bob -2177342782468422676 100,0,0,0 0,1,2,3 0 -1596273871
CHOOSE bob 4868686471917930453 0,100,100,0 - 1 -438309674
CHOOSE bob 4868686471917930454 0,100,100,0 3 0 -587325948
CHOOSE bob 4868686471917930449 0,100,100,0 0,1,3 2 -1679576139
CHOOSE bob 4868686471917930455 0,100,100,0 2 1 -1252663721
CHOOSE bob -6532028347405268032 50,100,0 0 2 1514424123
CHOOSE bob -6532028347405268031 50,100,0 0,1 2 1923909098
CHOOSE bob -6532028347405268026 50,100,0 0,1,2,3 0 -812626189
CHOOSE bob 514000906981085099 100 - 0 79600482
CHOOSE bob 514000906981085096 100 3 0 -1461809864
CHOOSE bob 514000906981085103 100 0,1,3 0 -1963386353
CHOOSE bob 514000906981085097 100 2 0 413806104
CHOOSE bob 7560030161367438230 0,0,0,0 0 3 -1988604604
CHOOSE bob 7560030161367438231 0,0,0,0 0,1 2 -657592668
CHOOSE bob 7560030161367438224 0,0,0,0 0,1,2,3 0 1703114018
CHOOSE bob -3840684657955760255 0,100 - 1 -1530919958
CHOOSE bob -3840684657955760254 0,100 3 1 -273244575
CHOOSE bob -3840684657955760251 0,100 0,1,3 0 1992656962
CHOOSE bob -3840684657955760253 0,100 2 0 -849070013
CHOOSE bob 3205344596430592876 - 0 0 1876925998
CHOOSE bob 3205344596430592877 - 0,1 0 384861724
CHOOSE bob 3205344596430592874 - 0,1,2,3 0 507168004
CHOOSE bob -9223372036854775808 0,0,100,0 - 2 -1507543906
CHOOSE bob -9223372036854775805 0,0,100,0 3 2 106484100
CHOOSE bob -9223372036854775804 0,0,100,0 0,1,3 2 -1126855500
CHOOSE bob -9223372036854775806 0,0,100,0 2 0 -847181513
CHOOSE bob 2177342782468422677 100,0,0,0 0 1 1330735456
CHOOSE bob 2177342782468422676 100,0,0,0 0,1 2 -1205212078
CHOOSE bob 2177342782468422675 100,0,0,0 0,1,2,3 0 -616278705
CHOOSE bob -4868686471917930454 0,100,100,0 - 2 -280746957
CHOOSE bob -4868686471917930455 0,100,100,0 3 2 -1659325027
CHOOSE bob -4868686471917930450 0,100,100,0 0,1,3 2 -966649770
CHOOSE bob -4868686471917930456 0,100,100,0 2 1 648017804
CHOOSE bob 6532028347405268031 50,100,0 0 2 -272402636
CHOOSE bob 6532028347405268030 50,100,0 0,1 2 -1476235143
CHOOSE bob 6532028347405268025 50,100,0 0,1,2,3 0 -1393956483
CHOOSE bob -514000906981085100 100 - 0 -548068695
CHOOSE bob -514000906981085097 100 3 0 2071271395
CHOOSE bob -514000906981085104 100 0,1,3 0 -241118831
CHOOSE bob -514000906981085098 100 2 0 -903364349
CHOOSE bob -7560030161367438231 0,0,0,0 0 2 -1677543483
CHOOSE bob -7560030161367438232 0,0,0,0 0,1 2 170877029
CHOOSE bob -7560030161367438225 0,0,0,0 0,1,2,3 0 672861774
CHOOSE bob 3840684657955760254 0,100 - 1 1464986111
CHOOSE bob 3840684657955760253 0,100 3 0 -1661136416
CHOOSE bob 3840684657955760250 0,100 0,1,3 0 354283566
CHOOSE bob 3840684657955760252 0,100 2 1 -22135128
CHOOSE bob -3205344596430592877 - 0 0 226043218
CHOOSE bob -3205344596430592878 - 0,1 0 1955122564
CHOOSE bob -3205344596430592875 - 0,1,2,3 0 1553074796
CHOOSE bob 31337 0,0,100,0 - 2 -1882149745
CHOOSE bob 31338 0,0,100,0 3 1 1016734110
CHOOSE bob 31341 0,0,100,0 0,1,3 2 -2003822653
CHOOSE bob 31339 0,0,100,0 2 3 -668178202
CHOOSE bob -7046029254386383236 100,0,0,0 0 3 -903395920
CHOOSE bob -7046029254386383235 100,0,0,0 0,1 3 -1043366911
CHOOSE bob -7046029254386383238 100,0,0,0 0,1,2,3 0 709265643
CHOOSE bob 4354685564936815171 0,100,100,0 - 2 -659585948
CHOOSE bob 4354685564936815168 0,100,100,0 3 1 263062318
CHOOSE bob 4354685564936815175 0,100,100,0 0,1,3 2 -1378038457
CHOOSE bob 4354685564936815169 0,100,100,0 2 0 822853627
CHOOSE bob -2691343689449533866 50,100,0 0 1 2033264663
CHOOSE bob -2691343689449533865 50,100,0 0,1 2 -1311184824
CHOOSE bob -2691343689449533872 50,100,0 0,1,2,3 0 -148579047
CHOOSE bob 8709371129873664573 100 - 0 -1495485030
CHOOSE bob 8709371129873664574 100 3 0 -1963150096
CHOOSE bob 8709371129873664569 100 0,1,3 0 -1815208339
CHOOSE bob 8709371129873664575 100 2 0 -1185856496
CHOOSE bob 1663341875487315456 0,0,0,0 0 3 -904121164
CHOOSE bob 1663341875487315457 0,0,0,0 0,1 2 -655965356
CHOOSE bob 1663341875487315462 0,0,0,0 0,1,2,3 0 -848280910
CHOOSE bob -5382687378899037673 0,100 - 1 1052482160
CHOOSE bob -5382687378899037676 0,100 3 1 520066822
CHOOSE bob -5382687378899037677 0,100 0,1,3 0 -1603240950
CHOOSE bob -5382687378899037675 0,100 2 1 118970071
CHOOSE bob 6018027440424165114 - 0 0 1995807278
CHOOSE bob 6018027440424165115 - 0,1 0 537246240
CHOOSE bob 6018027440424165116 - 0,1,2,3 0 -1470595320
CHOOSE woman_dark 0 0,0,100,0 - 2 -1454478562
CHOOSE woman_dark 3 0,0,100,0 3 0 -256771609
CHOOSE woman_dark 4 0,0,100,0 0,1,3 2 483757236
CHOOSE woman_dark 2 0,0,100,0 2 3 15345335
CHOOSE woman_dark -7046029254386353131 100,0,0,0 0 2 -1365818593
CHOOSE woman_dark -7046029254386353132 100,0,0,0 0,1 2 -680557870
CHOOSE woman_dark -7046029254386353133 100,0,0,0 0,1,2,3 0 -1155246353
CHOOSE woman_dark 4354685564936845354 0,100,100,0 - 2 8227251
CHOOSE woman_dark 4354685564936845353 0,100,100,0 3 2 540114653
CHOOSE woman_dark 4354685564936845358 0,100,100,0 0,1,3 2 375527510
CHOOSE woman_dark 4354685564936845352 0,100,100,0 2 1 1209648652
CHOOSE woman_dark -2691343689449507777 50,100,0 0 1 -1617943258
CHOOSE woman_dark -2691343689449507778 50,100,0 0,1 2 -2023231751
CHOOSE woman_dark -2691343689449507783 50,100,0 0,1,2,3 0 -1924535523
CHOOSE woman_dark 8709371129873690708 100 - 0 1062544041
CHOOSE woman_dark 8709371129873690711 100 3 0 460658659
CHOOSE woman_dark 8709371129873690704 100 0,1,3 0 289460337
CHOOSE woman_dark 8709371129873690710 100 2 0 707248387
CHOOSE woman_dark 1663341875487337577 0,0,0,0 0 3 1006811077
CHOOSE woman_dark 1663341875487337576 0,0,0,0 0,1 3 1781489765
CHOOSE woman_dark 1663341875487337583 0,0,0,0 0,1,2,3 0 935005358
CHOOSE woman_dark -5382687378899015554 0,100 - 0 1510711423
CHOOSE woman_dark -5382687378899015555 0,100 3 1 -96496139
CHOOSE woman_dark -5382687378899015558 0,100 0,1,3 0 620622350
CHOOSE woman_dark -5382687378899015556 0,100 2 0 833051688
CHOOSE woman_dark 6018027440424182931 - 0 0 -317119438
CHOOSE woman_dark 6018027440424182930 - 0,1 0 -2077701084
CHOOSE woman_dark 6018027440424182933 - 0,1,2,3 0 1022496012
CHOOSE woman_dark 1700000000123 0,0,100,0 - 2 -1272690835
CHOOSE woman_dark 1700000000120 0,0,100,0 3 0 341854951
CHOOSE woman_dark 1700000000127 0,0,100,0 0,1,3 2 348414349
CHOOSE woman_dark 1700000000121 0,0,100,0 2 0 -590867436
CHOOSE woman_dark -7046030932889889682 100,0,0,0 0 1 -285540654
CHOOSE woman_dark -7046030932889889681 100,0,0,0 0,1 3 697157702
CHOOSE woman_dark -7046030932889889688 100,0,0,0 0,1,2,3 0 570740890
CHOOSE woman_dark 4354685041804152913 0,100,100,0 - 2 -620568730
CHOOSE woman_dark 4354685041804152914 0,100,100,0 3 2 995027484
CHOOSE woman_dark 4354685041804152917 0,100,100,0 0,1,3 2 1762171661
CHOOSE woman_dark 4354685041804152915 0,100,100,0 2 1 329722573
CHOOSE woman_dark -2691344259801801660 50,100,0 0 2 2123690729
CHOOSE woman_dark -2691344259801801659 50,100,0 0,1 2 -1761824458
CHOOSE woman_dark -2691344259801801662 50,100,0 0,1,2,3 0 -815287062
CHOOSE woman_dark 8709371714889095215 100 - 0 849407856
CHOOSE woman_dark 8709371714889095212 100 3 0 1455487786
CHOOSE woman_dark 8709371714889095211 100 0,1,3 0 -735803874
CHOOSE woman_dark 8709371714889095213 100 2 0 638423498
CHOOSE woman_dark 1663342378923131922 0,0,0,0 0 2 1440217742
CHOOSE woman_dark 1663342378923131923 0,0,0,0 0,1 2 1168806318
CHOOSE woman_dark 1663342378923131924 0,0,0,0 0,1,2,3 0 -577107181
CHOOSE woman_dark -5382685754451591163 0,100 - 1 1141847390
CHOOSE woman_dark -5382685754451591162 0,100 3 1 601571400
CHOOSE woman_dark -5382685754451591167 0,100 0,1,3 0 681489403
CHOOSE woman_dark -5382685754451591161 0,100 2 0 -323812875
CHOOSE woman_dark 6018029120727551208 - 0 0 -289938929
CHOOSE woman_dark 6018029120727551209 - 0,1 0 1204273633
CHOOSE woman_dark 6018029120727551214 - 0,1,2,3 0 -1609099527
CHOOSE woman_dark -987654321 0,0,100,0 - 3 2018681017
CHOOSE woman_dark -987654324 0,0,100,0 3 0 677938306
CHOOSE woman_dark -987654325 0,0,100,0 0,1,3 2 -1227801630
CHOOSE woman_dark -987654323 0,0,100,0 2 1 817937999
CHOOSE woman_dark 7046029255354608474 100,0,0,0 0 3 -2096770713
CHOOSE woman_dark 7046029255354608475 100,0,0,0 0,1 3 -1705141708
CHOOSE woman_dark 7046029255354608476 100,0,0,0 0,1,2,3 0 -151344836
CHOOSE woman_dark -4354685563958890651 0,100,100,0 - 1 -821726509
CHOOSE woman_dark -4354685563958890650 0,100,100,0 3 0 1866556905
CHOOSE woman_dark -4354685563958890655 0,100,100,0 0,1,3 2 -816221640
CHOOSE woman_dark -4354685563958890649 0,100,100,0 2 1 -2018957766
CHOOSE woman_dark 2691343690370048880 50,100,0 0 1 1922760480
CHOOSE woman_dark 2691343690370048881 50,100,0 0,1 2 1257455053
CHOOSE woman_dark 2691343690370048886 50,100,0 0,1,2,3 0 -999344884
CHOOSE woman_dark -8709371128981199077 100 - 0 -661791267
CHOOSE woman_dark -8709371128981199080 100 3 0 1953352371
CHOOSE woman_dark -8709371128981199073 100 0,1,3 0 -384171016
CHOOSE woman_dark -8709371128981199079 100 2 0 -467506285
CHOOSE woman_dark -1663341874584880346 0,0,0,0 0 1 -1270019391
CHOOSE woman_dark -1663341874584880345 0,0,0,0 0,1 2 58174497
CHOOSE woman_dark -1663341874584880352 0,0,0,0 0,1,2,3 0 312729399
CHOOSE woman_dark 5382687379878281009 0,100 - 0 -1206273081
CHOOSE woman_dark 5382687379878281010 0,100 3 1 -673861871
CHOOSE woman_dark 5382687379878281013 0,100 0,1,3 0 1537812055
CHOOSE woman_dark 5382687379878281011 0,100 2 1 879289766
CHOOSE woman_dark -6018027439464582180 - 0 0 -1010862029
CHOOSE woman_dark -6018027439464582179 - 0,1 0 1523587077
CHOOSE woman_dark -6018027439464582182 - 0,1,2,3 0 1930978077
CHOOSE woman_dark 9223372036854775807 0,0,100,0 - 2 1402130883
CHOOSE woman_dark 9223372036854775804 0,0,100,0 3 2 869190749
CHOOSE woman_dark 9223372036854775803 0,0,100,0 0,1,3 2 660863589
CHOOSE woman_dark 9223372036854775805 0,0,100,0 2 1 -63502804
CHOOSE woman_dark -2177342782468422678 100,0,0,0 0 1 1246501186
CHOOSE woman_dark -2177342782468422677 100,0,0,0 0,1 2 565436945
CHOOSE woman_dark -2177342782468422676 100,0,0,0 0,1,2,3 0 -1596273871
CHOOSE woman_dark 4868686471917930453 0,100,100,0 - 1 -438309674
CHOOSE woman_dark 4868686471917930454 0,100,100,0 3 2 -587325948
CHOOSE woman_dark 4868686471917930449 0,100,100,0 0,1,3 2 -1679576139
CHOOSE woman_dark 4868686471917930455 0,100,100,0 2 1 -1252663721
CHOOSE woman_dark -6532028347405268032 50,100,0 0 2 1514424123
CHOOSE woman_dark -6532028347405268031 50,100,0 0,1 2 1923909098
CHOOSE woman_dark -6532028347405268026 50,100,0 0,1,2,3 0 -812626189
CHOOSE woman_dark 514000906981085099 100 - 0 79600482
CHOOSE woman_dark 514000906981085096 100 3 0 -1461809864
CHOOSE woman_dark 514000906981085103 100 0,1,3 0 -1963386353
CHOOSE woman_dark 514000906981085097 100 2 0 413806104
CHOOSE woman_dark 7560030161367438230 0,0,0,0 0 3 -1988604604
CHOOSE woman_dark 7560030161367438231 0,0,0,0 0,1 2 -657592668
CHOOSE woman_dark 7560030161367438224 0,0,0,0 0,1,2,3 0 1703114018
CHOOSE woman_dark -3840684657955760255 0,100 - 1 -1530919958
CHOOSE woman_dark -3840684657955760254 0,100 3 1 -273244575
CHOOSE woman_dark -3840684657955760251 0,100 0,1,3 0 1992656962
CHOOSE woman_dark -3840684657955760253 0,100 2 0 -849070013
CHOOSE woman_dark 3205344596430592876 - 0 0 1876925998
CHOOSE woman_dark 3205344596430592877 - 0,1 0 384861724
CHOOSE woman_dark 3205344596430592874 - 0,1,2,3 0 507168004
CHOOSE woman_dark -9223372036854775808 0,0,100,0 - 2 -1507543906
CHOOSE woman_dark -9223372036854775805 0,0,100,0 3 2 106484100
CHOOSE woman_dark -9223372036854775804 0,0,100,0 0,1,3 2 -1126855500
CHOOSE woman_dark -9223372036854775806 0,0,100,0 2 0 -847181513
CHOOSE woman_dark 2177342782468422677 100,0,0,0 0 1 1330735456
CHOOSE woman_dark 2177342782468422676 100,0,0,0 0,1 2 -1205212078
CHOOSE woman_dark 2177342782468422675 100,0,0,0 0,1,2,3 0 -616278705
CHOOSE woman_dark -4868686471917930454 0,100,100,0 - 2 -280746957
CHOOSE woman_dark -4868686471917930455 0,100,100,0 3 0 1334327645
CHOOSE woman_dark -4868686471917930450 0,100,100,0 0,1,3 2 -966649770
CHOOSE woman_dark -4868686471917930456 0,100,100,0 2 1 648017804
CHOOSE woman_dark 6532028347405268031 50,100,0 0 2 -272402636
CHOOSE woman_dark 6532028347405268030 50,100,0 0,1 2 -1476235143
CHOOSE woman_dark 6532028347405268025 50,100,0 0,1,2,3 0 -1393956483
CHOOSE woman_dark -514000906981085100 100 - 0 -548068695
CHOOSE woman_dark -514000906981085097 100 3 0 2071271395
CHOOSE woman_dark -514000906981085104 100 0,1,3 0 -241118831
CHOOSE woman_dark -514000906981085098 100 2 0 -903364349
CHOOSE woman_dark -7560030161367438231 0,0,0,0 0 2 -1677543483
CHOOSE woman_dark -7560030161367438232 0,0,0,0 0,1 2 170877029
CHOOSE woman_dark -7560030161367438225 0,0,0,0 0,1,2,3 0 672861774
CHOOSE woman_dark 3840684657955760254 0,100 - 1 1464986111
CHOOSE woman_dark 3840684657955760253 0,100 3 0 -1661136416
CHOOSE woman_dark 3840684657955760250 0,100 0,1,3 0 354283566
CHOOSE woman_dark 3840684657955760252 0,100 2 1 -22135128
CHOOSE woman_dark -3205344596430592877 - 0 0 226043218
CHOOSE woman_dark -3205344596430592878 - 0,1 0 1955122564
CHOOSE woman_dark -3205344596430592875 - 0,1,2,3 0 1553074796
CHOOSE woman_dark 31337 0,0,100,0 - 2 -1882149745
CHOOSE woman_dark 31338 0,0,100,0 3 1 1016734110
CHOOSE woman_dark 31341 0,0,100,0 0,1,3 2 -2003822653
CHOOSE woman_dark 31339 0,0,100,0 2 3 -668178202
CHOOSE woman_dark -7046029254386383236 100,0,0,0 0 3 -903395920
CHOOSE woman_dark -7046029254386383235 100,0,0,0 0,1 3 -1043366911
CHOOSE woman_dark -7046029254386383238 100,0,0,0 0,1,2,3 0 709265643
CHOOSE woman_dark 4354685564936815171 0,100,100,0 - 2 -659585948
CHOOSE woman_dark 4354685564936815168 0,100,100,0 3 1 263062318
CHOOSE woman_dark 4354685564936815175 0,100,100,0 0,1,3 2 -1378038457
CHOOSE woman_dark 4354685564936815169 0,100,100,0 2 0 822853627
CHOOSE woman_dark -2691343689449533866 50,100,0 0 1 2033264663
CHOOSE woman_dark -2691343689449533865 50,100,0 0,1 2 -1311184824
CHOOSE woman_dark -2691343689449533872 50,100,0 0,1,2,3 0 -148579047
CHOOSE woman_dark 8709371129873664573 100 - 0 -1495485030
CHOOSE woman_dark 8709371129873664574 100 3 0 -1963150096
CHOOSE woman_dark 8709371129873664569 100 0,1,3 0 -1815208339
CHOOSE woman_dark 8709371129873664575 100 2 0 -1185856496
CHOOSE woman_dark 1663341875487315456 0,0,0,0 0 3 -904121164
CHOOSE woman_dark 1663341875487315457 0,0,0,0 0,1 2 -655965356
CHOOSE woman_dark 1663341875487315462 0,0,0,0 0,1,2,3 0 -848280910
CHOOSE woman_dark -5382687378899037673 0,100 - 1 1052482160
CHOOSE woman_dark -5382687378899037676 0,100 3 1 520066822
CHOOSE woman_dark -5382687378899037677 0,100 0,1,3 0 -1603240950
CHOOSE woman_dark -5382687378899037675 0,100 2 1 118970071
CHOOSE woman_dark 6018027440424165114 - 0 0 1995807278
CHOOSE woman_dark 6018027440424165115 - 0,1 0 537246240
CHOOSE woman_dark 6018027440424165116 - 0,1,2,3 0 -1470595320
CHOOSE rooza 0 0,0,100,0 - 1 -649160781
CHOOSE rooza 3 0,0,100,0 3 0 -256771609
CHOOSE rooza 4 0,0,100,0 0,1,3 2 483757236
CHOOSE rooza 2 0,0,100,0 2 0 -382311875
CHOOSE rooza -7046029254386353131 100,0,0,0 0 1 778235912
CHOOSE rooza -7046029254386353132 100,0,0,0 0,1 3 631744338
CHOOSE rooza -7046029254386353133 100,0,0,0 0,1,2,3 0 -1155246353
CHOOSE rooza 4354685564936845354 0,100,100,0 - 3 -1541192439
CHOOSE rooza 4354685564936845353 0,100,100,0 3 1 -1140722939
CHOOSE rooza 4354685564936845358 0,100,100,0 0,1,3 2 375527510
CHOOSE rooza 4354685564936845352 0,100,100,0 2 1 1209648652
CHOOSE rooza -2691343689449507777 50,100,0 0 1 -827469668
CHOOSE rooza -2691343689449507778 50,100,0 0,1 2 -2023231751
CHOOSE rooza -2691343689449507783 50,100,0 0,1,2,3 0 -1924535523
CHOOSE rooza 8709371129873690708 100 - 0 1062544041
CHOOSE rooza 8709371129873690711 100 3 0 460658659
CHOOSE rooza 8709371129873690704 100 0,1,3 0 289460337
CHOOSE rooza 8709371129873690710 100 2 0 707248387
CHOOSE rooza 1663341875487337577 0,0,0,0 0 3 1006811077
CHOOSE rooza 1663341875487337576 0,0,0,0 0,1 3 1781489765
CHOOSE rooza 1663341875487337583 0,0,0,0 0,1,2,3 0 935005358
CHOOSE rooza -5382687378899015554 0,100 - 0 -1513580180
CHOOSE rooza -5382687378899015555 0,100 3 1 -96496139
CHOOSE rooza -5382687378899015558 0,100 0,1,3 0 620622350
CHOOSE rooza -5382687378899015556 0,100 2 0 833051688
CHOOSE rooza 6018027440424182931 - 0 0 -317119438
CHOOSE rooza 6018027440424182930 - 0,1 0 -2077701084
CHOOSE rooza 6018027440424182933 - 0,1,2,3 0 1022496012
CHOOSE rooza 1700000000123 0,0,100,0 - 2 -1272690835
CHOOSE rooza 1700000000120 0,0,100,0 3 1 814436075
CHOOSE rooza 1700000000127 0,0,100,0 0,1,3 2 348414349
CHOOSE rooza 1700000000121 0,0,100,0 2 3 681492313
CHOOSE rooza -7046030932889889682 100,0,0,0 0 2 834279636
CHOOSE rooza -7046030932889889681 100,0,0,0 0,1 3 697157702
CHOOSE rooza -7046030932889889688 100,0,0,0 0,1,2,3 0 570740890
CHOOSE rooza 4354685041804152913 0,100,100,0 - 2 -339858915
CHOOSE rooza 4354685041804152914 0,100,100,0 3 2 995027484
CHOOSE rooza 4354685041804152917 0,100,100,0 0,1,3 2 1762171661
CHOOSE rooza 4354685041804152915 0,100,100,0 2 0 -606710637
CHOOSE rooza -2691344259801801660 50,100,0 0 2 2123690729
CHOOSE rooza -2691344259801801659 50,100,0 0,1 2 163812906
CHOOSE rooza -2691344259801801662 50,100,0 0,1,2,3 0 -815287062
CHOOSE rooza 8709371714889095215 100 - 0 849407856
CHOOSE rooza 8709371714889095212 100 3 0 1455487786
CHOOSE rooza 8709371714889095211 100 0,1,3 0 -735803874
CHOOSE rooza 8709371714889095213 100 2 0 638423498
CHOOSE rooza 1663342378923131922 0,0,0,0 0 2 1440217742
CHOOSE rooza 1663342378923131923 0,0,0,0 0,1 2 1168806318
CHOOSE rooza 1663342378923131924 0,0,0,0 0,1,2,3 0 -577107181
CHOOSE rooza -5382685754451591163 0,100 - 1 737196656
CHOOSE rooza -5382685754451591162 0,100 3 0 1687261348
CHOOSE rooza -5382685754451591167 0,100 0,1,3 0 681489403
CHOOSE rooza -5382685754451591161 0,100 2 1 1543364858
CHOOSE rooza 6018029120727551208 - 0 0 -289938929
CHOOSE rooza 6018029120727551209 - 0,1 0 1204273633
CHOOSE rooza 6018029120727551214 - 0,1,2,3 0 -1609099527
CHOOSE rooza -987654321 0,0,100,0 - 3 2018681017
CHOOSE rooza -987654324 0,0,100,0 3 0 677938306
CHOOSE rooza -987654325 0,0,100,0 0,1,3 2 -1227801630
CHOOSE rooza -987654323 0,0,100,0 2 1 817937999
CHOOSE rooza 7046029255354608474 100,0,0,0 0 3 -2096770713
CHOOSE rooza 7046029255354608475 100,0,0,0 0,1 2 -370861798
CHOOSE rooza 7046029255354608476 100,0,0,0 0,1,2,3 0 -151344836
CHOOSE rooza -4354685563958890651 0,100,100,0 - 2 1130511267
CHOOSE rooza -4354685563958890650 0,100,100,0 3 0 1866556905
CHOOSE rooza -4354685563958890655 0,100,100,0 0,1,3 2 -816221640
CHOOSE rooza -4354685563958890649 0,100,100,0 2 1 862717469
CHOOSE rooza 2691343690370048880 50,100,0 0 2 1634523120
CHOOSE rooza 2691343690370048881 50,100,0 0,1 2 1781016702
CHOOSE rooza 2691343690370048886 50,100,0 0,1,2,3 0 -999344884
CHOOSE rooza -8709371128981199077 100 - 0 -661791267
CHOOSE rooza -8709371128981199080 100 3 0 1953352371
CHOOSE rooza -8709371128981199073 100 0,1,3 0 -384171016
CHOOSE rooza -8709371128981199079 100 2 0 -467506285
CHOOSE rooza -1663341874584880346 0,0,0,0 0 1 -1270019391
CHOOSE rooza -1663341874584880345 0,0,0,0 0,1 2 58174497
CHOOSE rooza -1663341874584880352 0,0,0,0 0,1,2,3 0 312729399
CHOOSE rooza 5382687379878281009 0,100 - 0 -1206273081
CHOOSE rooza 5382687379878281010 0,100 3 1 -673861871
CHOOSE rooza 5382687379878281013 0,100 0,1,3 0 1537812055
CHOOSE rooza 5382687379878281011 0,100 2 1 879289766
CHOOSE rooza -6018027439464582180 - 0 0 -1010862029
CHOOSE rooza -6018027439464582179 - 0,1 0 1523587077
CHOOSE rooza -6018027439464582182 - 0,1,2,3 0 1930978077
CHOOSE rooza 9223372036854775807 0,0,100,0 - 2 1402130883
CHOOSE rooza 9223372036854775804 0,0,100,0 3 1 2070194162
CHOOSE rooza 9223372036854775803 0,0,100,0 0,1,3 2 660863589
CHOOSE rooza 9223372036854775805 0,0,100,0 2 3 -2105454560
CHOOSE rooza -2177342782468422678 100,0,0,0 0 1 1246501186
CHOOSE rooza -2177342782468422677 100,0,0,0 0,1 3 1148340743
CHOOSE rooza -2177342782468422676 100,0,0,0 0,1,2,3 0 -1596273871
CHOOSE rooza 4868686471917930453 0,100,100,0 - 1 -438309674
CHOOSE rooza 4868686471917930454 0,100,100,0 3 2 -1371716006
CHOOSE rooza 4868686471917930449 0,100,100,0 0,1,3 2 -1679576139
CHOOSE rooza 4868686471917930455 0,100,100,0 2 1 -1242458292
CHOOSE rooza -6532028347405268032 50,100,0 0 1 -1141184317
CHOOSE rooza -6532028347405268031 50,100,0 0,1 2 1923909098
CHOOSE rooza -6532028347405268026 50,100,0 0,1,2,3 0 -812626189
CHOOSE rooza 514000906981085099 100 - 0 79600482
CHOOSE rooza 514000906981085096 100 3 0 -1461809864
CHOOSE rooza 514000906981085103 100 0,1,3 0 -1963386353
CHOOSE rooza 514000906981085097 100 2 0 413806104
CHOOSE rooza 7560030161367438230 0,0,0,0 0 3 -1988604604
CHOOSE rooza 7560030161367438231 0,0,0,0 0,1 2 -657592668
CHOOSE rooza 7560030161367438224 0,0,0,0 0,1,2,3 0 1703114018
CHOOSE rooza -3840684657955760255 0,100 - 0 -401248275
CHOOSE rooza -3840684657955760254 0,100 3 1 -273244575
CHOOSE rooza -3840684657955760251 0,100 0,1,3 0 1992656962
CHOOSE rooza -3840684657955760253 0,100 2 1 -132499849
CHOOSE rooza 3205344596430592876 - 0 0 1876925998
CHOOSE rooza 3205344596430592877 - 0,1 0 384861724
CHOOSE rooza 3205344596430592874 - 0,1,2,3 0 507168004
CHOOSE rooza -9223372036854775808 0,0,100,0 - 0 138246747
CHOOSE rooza -9223372036854775805 0,0,100,0 3 0 -811847617
CHOOSE rooza -9223372036854775804 0,0,100,0 0,1,3 2 -1126855500
CHOOSE rooza -9223372036854775806 0,0,100,0 2 1 -666386475
CHOOSE rooza 2177342782468422677 100,0,0,0 0 1 1330735456
CHOOSE rooza 2177342782468422676 100,0,0,0 0,1 2 -1205212078
CHOOSE rooza 2177342782468422675 100,0,0,0 0,1,2,3 0 -616278705
CHOOSE rooza -4868686471917930454 0,100,100,0 - 1 -717923471
CHOOSE rooza -4868686471917930455 0,100,100,0 3 2 -1659325027
CHOOSE rooza -4868686471917930450 0,100,100,0 0,1,3 2 -966649770
CHOOSE rooza -4868686471917930456 0,100,100,0 2 3 648017804
CHOOSE rooza 6532028347405268031 50,100,0 0 2 -272402636
CHOOSE rooza 6532028347405268030 50,100,0 0,1 2 -1476235143
CHOOSE rooza 6532028347405268025 50,100,0 0,1,2,3 0 -1393956483
CHOOSE rooza -514000906981085100 100 - 0 -548068695
CHOOSE rooza -514000906981085097 100 3 0 2071271395
CHOOSE rooza -514000906981085104 100 0,1,3 0 -241118831
CHOOSE rooza -514000906981085098 100 2 0 -903364349
CHOOSE rooza -7560030161367438231 0,0,0,0 0 2 -1677543483
CHOOSE rooza -7560030161367438232 0,0,0,0 0,1 2 170877029
CHOOSE rooza -7560030161367438225 0,0,0,0 0,1,2,3 0 672861774
CHOOSE rooza 3840684657955760254 0,100 - 1 -1797397500
CHOOSE rooza 3840684657955760253 0,100 3 0 -1661136416
CHOOSE rooza 3840684657955760250 0,100 0,1,3 0 354283566
CHOOSE rooza 3840684657955760252 0,100 2 0 -22135128
CHOOSE rooza -3205344596430592877 - 0 0 226043218
CHOOSE rooza -3205344596430592878 - 0,1 0 1955122564
CHOOSE rooza -3205344596430592875 - 0,1,2,3 0 1553074796
CHOOSE rooza 31337 0,0,100,0 - 3 -1882149745
CHOOSE rooza 31338 0,0,100,0 3 1 1016734110
CHOOSE rooza 31341 0,0,100,0 0,1,3 2 -2003822653
CHOOSE rooza 31339 0,0,100,0 2 1 891124360
CHOOSE rooza -7046029254386383236 100,0,0,0 0 1 -28514381
CHOOSE rooza -7046029254386383235 100,0,0,0 0,1 3 -1043366911
CHOOSE rooza -7046029254386383238 100,0,0,0 0,1,2,3 0 709265643
CHOOSE rooza 4354685564936815171 0,100,100,0 - 3 -659585948
CHOOSE rooza 4354685564936815168 0,100,100,0 3 1 263062318
CHOOSE rooza 4354685564936815175 0,100,100,0 0,1,3 2 -1378038457
CHOOSE rooza 4354685564936815169 0,100,100,0 2 3 131707748
CHOOSE rooza -2691343689449533866 50,100,0 0 2 -37224243
CHOOSE rooza -2691343689449533865 50,100,0 0,1 2 -1311184824
CHOOSE rooza -2691343689449533872 50,100,0 0,1,2,3 0 -148579047
CHOOSE rooza 8709371129873664573 100 - 0 -1495485030
CHOOSE rooza 8709371129873664574 100 3 0 -1963150096
CHOOSE rooza 8709371129873664569 100 0,1,3 0 -1815208339
CHOOSE rooza 8709371129873664575 100 2 0 -1185856496
CHOOSE rooza 1663341875487315456 0,0,0,0 0 3 -904121164
CHOOSE rooza 1663341875487315457 0,0,0,0 0,1 2 -655965356
CHOOSE rooza 1663341875487315462 0,0,0,0 0,1,2,3 0 -848280910
CHOOSE rooza -5382687378899037673 0,100 - 1 1475439011
CHOOSE rooza -5382687378899037676 0,100 3 0 1343245127
CHOOSE rooza -5382687378899037677 0,100 0,1,3 0 -1603240950
CHOOSE rooza -5382687378899037675 0,100 2 0 118970071
CHOOSE rooza 6018027440424165114 - 0 0 1995807278
CHOOSE rooza 6018027440424165115 - 0,1 0 537246240
CHOOSE rooza 6018027440424165116 - 0,1,2,3 0 -1470595320
CHOOSE nova 0 0,0,100,0 - 2 -1454478562
CHOOSE nova 3 0,0,100,0 3 0 -256771609
CHOOSE nova 4 0,0,100,0 0,1,3 2 483757236
CHOOSE nova 2 0,0,100,0 2 3 15345335
CHOOSE nova -7046029254386353131 100,0,0,0 0 2 -1365818593
CHOOSE nova -7046029254386353132 100,0,0,0 0,1 2 -680557870
CHOOSE nova -7046029254386353133 100,0,0,0 0,1,2,3 0 -1155246353
CHOOSE nova 4354685564936845354 0,100,100,0 - 2 8227251
CHOOSE nova 4354685564936845353 0,100,100,0 3 2 540114653
CHOOSE nova 4354685564936845358 0,100,100,0 0,1,3 2 375527510
CHOOSE nova 4354685564936845352 0,100,100,0 2 1 1209648652
CHOOSE nova -2691343689449507777 50,100,0 0 1 -1617943258
CHOOSE nova -2691343689449507778 50,100,0 0,1 2 -2023231751
CHOOSE nova -2691343689449507783 50,100,0 0,1,2,3 0 -1924535523
CHOOSE nova 8709371129873690708 100 - 0 1062544041
CHOOSE nova 8709371129873690711 100 3 0 460658659
CHOOSE nova 8709371129873690704 100 0,1,3 0 289460337
CHOOSE nova 8709371129873690710 100 2 0 707248387
CHOOSE nova 1663341875487337577 0,0,0,0 0 3 1006811077
CHOOSE nova 1663341875487337576 0,0,0,0 0,1 3 1781489765
CHOOSE nova 1663341875487337583 0,0,0,0 0,1,2,3 0 935005358
CHOOSE nova -5382687378899015554 0,100 - 1 1510711423
CHOOSE nova -5382687378899015555 0,100 3 1 -96496139
CHOOSE nova -5382687378899015558 0,100 0,1,3 0 620622350
CHOOSE nova -5382687378899015556 0,100 2 1 833051688
CHOOSE nova 6018027440424182931 - 0 0 -317119438
CHOOSE nova 6018027440424182930 - 0,1 0 -2077701084
CHOOSE nova 6018027440424182933 - 0,1,2,3 0 1022496012
CHOOSE nova 1700000000123 0,0,100,0 - 2 -1272690835
CHOOSE nova 1700000000120 0,0,100,0 3 2 341854951
CHOOSE nova 1700000000127 0,0,100,0 0,1,3 2 348414349
CHOOSE nova 1700000000121 0,0,100,0 2 0 -590867436
CHOOSE nova -7046030932889889682 100,0,0,0 0 1 -285540654
CHOOSE nova -7046030932889889681 100,0,0,0 0,1 2 -966576385
CHOOSE nova -7046030932889889688 100,0,0,0 0,1,2,3 0 570740890
CHOOSE nova 4354685041804152913 0,100,100,0 - 2 -620568730
CHOOSE nova 4354685041804152914 0,100,100,0 3 2 995027484
CHOOSE nova 4354685041804152917 0,100,100,0 0,1,3 2 1762171661
CHOOSE nova 4354685041804152915 0,100,100,0 2 1 329722573
CHOOSE nova -2691344259801801660 50,100,0 0 2 2123690729
CHOOSE nova -2691344259801801659 50,100,0 0,1 2 -1761824458
CHOOSE nova -2691344259801801662 50,100,0 0,1,2,3 0 -815287062
CHOOSE nova 8709371714889095215 100 - 0 849407856
CHOOSE nova 8709371714889095212 100 3 0 1455487786
CHOOSE nova 8709371714889095211 100 0,1,3 0 -735803874
CHOOSE nova 8709371714889095213 100 2 0 638423498
CHOOSE nova 1663342378923131922 0,0,0,0 0 2 1440217742
CHOOSE nova 1663342378923131923 0,0,0,0 0,1 2 1168806318
CHOOSE nova 1663342378923131924 0,0,0,0 0,1,2,3 0 -577107181
CHOOSE nova -5382685754451591163 0,100 - 1 1141847390
CHOOSE nova -5382685754451591162 0,100 3 1 601571400
CHOOSE nova -5382685754451591167 0,100 0,1,3 0 681489403
CHOOSE nova -5382685754451591161 0,100 2 1 -323812875
CHOOSE nova 6018029120727551208 - 0 0 -289938929
CHOOSE nova 6018029120727551209 - 0,1 0 1204273633
CHOOSE nova 6018029120727551214 - 0,1,2,3 0 -1609099527
CHOOSE nova -987654321 0,0,100,0 - 2 -2011395672
CHOOSE nova -987654324 0,0,100,0 3 0 677938306
CHOOSE nova -987654325 0,0,100,0 0,1,3 2 -1227801630
CHOOSE nova -987654323 0,0,100,0 2 1 817937999
CHOOSE nova 7046029255354608474 100,0,0,0 0 3 -2096770713
CHOOSE nova 7046029255354608475 100,0,0,0 0,1 3 -1705141708
CHOOSE nova 7046029255354608476 100,0,0,0 0,1,2,3 0 -151344836
CHOOSE nova -4354685563958890651 0,100,100,0 - 1 -821726509
CHOOSE nova -4354685563958890650 0,100,100,0 3 0 1866556905
CHOOSE nova -4354685563958890655 0,100,100,0 0,1,3 2 -816221640
CHOOSE nova -4354685563958890649 0,100,100,0 2 1 -2018957766
CHOOSE nova 2691343690370048880 50,100,0 0 1 1922760480
CHOOSE nova 2691343690370048881 50,100,0 0,1 2 1257455053
CHOOSE nova 2691343690370048886 50,100,0 0,1,2,3 0 -999344884
CHOOSE nova -8709371128981199077 100 - 0 -661791267
CHOOSE nova -8709371128981199080 100 3 0 1953352371
CHOOSE nova -8709371128981199073 100 0,1,3 0 -384171016
CHOOSE nova -8709371128981199079 100 2 0 -467506285
CHOOSE nova -1663341874584880346 0,0,0,0 0 1 -1270019391
CHOOSE nova -1663341874584880345 0,0,0,0 0,1 2 58174497
CHOOSE nova -1663341874584880352 0,0,0,0 0,1,2,3 0 312729399
CHOOSE nova 5382687379878281009 0,100 - 1 -1206273081
CHOOSE nova 5382687379878281010 0,100 3 1 -673861871
CHOOSE nova 5382687379878281013 0,100 0,1,3 0 1537812055
CHOOSE nova 5382687379878281011 0,100 2 1 879289766
CHOOSE nova -6018027439464582180 - 0 0 -1010862029
CHOOSE nova -6018027439464582179 - 0,1 0 1523587077
CHOOSE nova -6018027439464582182 - 0,1,2,3 0 1930978077
CHOOSE nova 9223372036854775807 0,0,100,0 - 2 1402130883
CHOOSE nova 9223372036854775804 0,0,100,0 3 2 869190749
CHOOSE nova 9223372036854775803 0,0,100,0 0,1,3 2 660863589
CHOOSE nova 9223372036854775805 0,0,100,0 2 1 -63502804
CHOOSE nova -2177342782468422678 100,0,0,0 0 1 1246501186
CHOOSE nova -2177342782468422677 100,0,0,0 0,1 2 565436945
CHOOSE nova -2177342782468422676 100,0,0,0 0,1,2,3 0 -1596273871
CHOOSE nova 4868686471917930453 0,100,100,0 - 1 -438309674
CHOOSE nova 4868686471917930454 0,100,100,0 3 2 -587325948
CHOOSE nova 4868686471917930449 0,100,100,0 0,1,3 2 -1679576139
CHOOSE nova 4868686471917930455 0,100,100,0 2 1 -1252663721
CHOOSE nova -6532028347405268032 50,100,0 0 1 1514424123
CHOOSE nova -6532028347405268031 50,100,0 0,1 2 1923909098
CHOOSE nova -6532028347405268026 50,100,0 0,1,2,3 0 -812626189
CHOOSE nova 514000906981085099 100 - 0 79600482
CHOOSE nova 514000906981085096 100 3 0 -1461809864
CHOOSE nova 514000906981085103 100 0,1,3 0 -1963386353
CHOOSE nova 514000906981085097 100 2 0 413806104
CHOOSE nova 7560030161367438230 0,0,0,0 0 3 -1988604604
CHOOSE nova 7560030161367438231 0,0,0,0 0,1 2 -657592668
CHOOSE nova 7560030161367438224 0,0,0,0 0,1,2,3 0 1703114018
CHOOSE nova -3840684657955760255 0,100 - 1 -1530919958
CHOOSE nova -3840684657955760254 0,100 3 1 76281588
CHOOSE nova -3840684657955760251 0,100 0,1,3 0 1992656962
CHOOSE nova -3840684657955760253 0,100 2 1 -849070013
CHOOSE nova 3205344596430592876 - 0 0 1876925998
CHOOSE nova 3205344596430592877 - 0,1 0 384861724
CHOOSE nova 3205344596430592874 - 0,1,2,3 0 507168004
CHOOSE nova -9223372036854775808 0,0,100,0 - 2 -1507543906
CHOOSE nova -9223372036854775805 0,0,100,0 3 2 106484100
CHOOSE nova -9223372036854775804 0,0,100,0 0,1,3 2 -1126855500
CHOOSE nova -9223372036854775806 0,0,100,0 2 0 -847181513
CHOOSE nova 2177342782468422677 100,0,0,0 0 1 1330735456
CHOOSE nova 2177342782468422676 100,0,0,0 0,1 2 -1205212078
CHOOSE nova 2177342782468422675 100,0,0,0 0,1,2,3 0 -616278705
CHOOSE nova -4868686471917930454 0,100,100,0 - 2 -280746957
CHOOSE nova -4868686471917930455 0,100,100,0 3 2 1334327645
CHOOSE nova -4868686471917930450 0,100,100,0 0,1,3 2 -966649770
CHOOSE nova -4868686471917930456 0,100,100,0 2 1 648017804
CHOOSE nova 6532028347405268031 50,100,0 0 2 -272402636
CHOOSE nova 6532028347405268030 50,100,0 0,1 2 -1476235143
CHOOSE nova 6532028347405268025 50,100,0 0,1,2,3 0 -1393956483
CHOOSE nova -514000906981085100 100 - 0 -548068695
CHOOSE nova -514000906981085097 100 3 0 2071271395
CHOOSE nova -514000906981085104 100 0,1,3 0 -241118831
CHOOSE nova -514000906981085098 100 2 0 -903364349
CHOOSE nova -7560030161367438231 0,0,0,0 0 2 -1677543483
CHOOSE nova -7560030161367438232 0,0,0,0 0,1 2 170877029
CHOOSE nova -7560030161367438225 0,0,0,0 0,1,2,3 0 672861774
CHOOSE nova 3840684657955760254 0,100 - 1 1464986111
CHOOSE nova 3840684657955760253 0,100 3 1 924188533
CHOOSE nova 3840684657955760250 0,100 0,1,3 0 354283566
CHOOSE nova 3840684657955760252 0,100 2 1 -22135128
CHOOSE nova -3205344596430592877 - 0 0 226043218
CHOOSE nova -3205344596430592878 - 0,1 0 1955122564
CHOOSE nova -3205344596430592875 - 0,1,2,3 0 1553074796
CHOOSE nova 31337 0,0,100,0 - 2 -1882149745
CHOOSE nova 31338 0,0,100,0 3 2 -276520555
CHOOSE nova 31341 0,0,100,0 0,1,3 2 -2003822653
CHOOSE nova 31339 0,0,100,0 2 3 -668178202
CHOOSE nova -7046029254386383236 100,0,0,0 0 3 -903395920
CHOOSE nova -7046029254386383235 100,0,0,0 0,1 3 -1043366911
CHOOSE nova -7046029254386383238 100,0,0,0 0,1,2,3 0 709265643
CHOOSE nova 4354685564936815171 0,100,100,0 - 2 -659585948
CHOOSE nova 4354685564936815168 0,100,100,0 3 0 947093806
CHOOSE nova 4354685564936815175 0,100,100,0 0,1,3 2 -1378038457
CHOOSE nova 4354685564936815169 0,100,100,0 2 1 822853627
CHOOSE nova -2691343689449533866 50,100,0 0 1 2033264663
CHOOSE nova -2691343689449533865 50,100,0 0,1 2 -1311184824
CHOOSE nova -2691343689449533872 50,100,0 0,1,2,3 0 -148579047
CHOOSE nova 8709371129873664573 100 - 0 -1495485030
CHOOSE nova 8709371129873664574 100 3 0 -1963150096
CHOOSE nova 8709371129873664569 100 0,1,3 0 -1815208339
CHOOSE nova 8709371129873664575 100 2 0 -1185856496
CHOOSE nova 1663341875487315456 0,0,0,0 0 3 -904121164
CHOOSE nova 1663341875487315457 0,0,0,0 0,1 2 -655965356
CHOOSE nova 1663341875487315462 0,0,0,0 0,1,2,3 0 -848280910
CHOOSE nova -5382687378899037673 0,100 - 1 1052482160
CHOOSE nova -5382687378899037676 0,100 3 1 520066822
CHOOSE nova -5382687378899037677 0,100 0,1,3 0 -1603240950
CHOOSE nova -5382687378899037675 0,100 2 1 118970071
CHOOSE nova 6018027440424165114 - 0 0 1995807278
CHOOSE nova 6018027440424165115 - 0,1 0 537246240
CHOOSE nova 6018027440424165116 - 0,1,2,3 0 -1470595320
CHOOSE unicorn_32 0 0,0,100,0 - 2 -1454478562
CHOOSE unicorn_32 3 0,0,100,0 3 0 -256771609
CHOOSE unicorn_32 4 0,0,100,0 0,1,3 2 483757236
CHOOSE unicorn_32 2 0,0,100,0 2 3 15345335
CHOOSE unicorn_32 -7046029254386353131 100,0,0,0 0 2 -1365818593
CHOOSE unicorn_32 -7046029254386353132 100,0,0,0 0,1 2 -680557870
CHOOSE unicorn_32 -7046029254386353133 100,0,0,0 0,1,2,3 0 -1155246353
CHOOSE unicorn_32 4354685564936845354 0,100,100,0 - 2 8227251
CHOOSE unicorn_32 4354685564936845353 0,100,100,0 3 2 540114653
CHOOSE unicorn_32 4354685564936845358 0,100,100,0 0,1,3 2 375527510
CHOOSE unicorn_32 4354685564936845352 0,100,100,0 2 1 1209648652
CHOOSE unicorn_32 -2691343689449507777 50,100,0 0 1 -1617943258
CHOOSE unicorn_32 -2691343689449507778 50,100,0 0,1 2 -2023231751
CHOOSE unicorn_32 -2691343689449507783 50,100,0 0,1,2,3 0 -1924535523
CHOOSE unicorn_32 8709371129873690708 100 - 0 1062544041
CHOOSE unicorn_32 8709371129873690711 100 3 0 460658659
CHOOSE unicorn_32 8709371129873690704 100 0,1,3 0 289460337
CHOOSE unicorn_32 8709371129873690710 100 2 0 707248387
CHOOSE unicorn_32 1663341875487337577 0,0,0,0 0 3 1006811077
CHOOSE unicorn_32 1663341875487337576 0,0,0,0 0,1 3 1781489765
CHOOSE unicorn_32 1663341875487337583 0,0,0,0 0,1,2,3 0 935005358
CHOOSE unicorn_32 -5382687378899015554 0,100 - 0 1510711423
CHOOSE unicorn_32 -5382687378899015555 0,100 3 1 -96496139
CHOOSE unicorn_32 -5382687378899015558 0,100 0,1,3 0 620622350
CHOOSE unicorn_32 -5382687378899015556 0,100 2 1 833051688
CHOOSE unicorn_32 6018027440424182931 - 0 0 -317119438
CHOOSE unicorn_32 6018027440424182930 - 0,1 0 -2077701084
CHOOSE unicorn_32 6018027440424182933 - 0,1,2,3 0 1022496012
CHOOSE unicorn_32 1700000000123 0,0,100,0 - 2 -1272690835
CHOOSE unicorn_32 1700000000120 0,0,100,0 3 0 341854951
CHOOSE unicorn_32 1700000000127 0,0,100,0 0,1,3 2 348414349
CHOOSE unicorn_32 1700000000121 0,0,100,0 2 0 -590867436
CHOOSE unicorn_32 -7046030932889889682 100,0,0,0 0 1 -285540654
CHOOSE unicorn_32 -7046030932889889681 100,0,0,0 0,1 2 -966576385
CHOOSE unicorn_32 -7046030932889889688 100,0,0,0 0,1,2,3 0 570740890
CHOOSE unicorn_32 4354685041804152913 0,100,100,0 - 2 -620568730
CHOOSE unicorn_32 4354685041804152914 0,100,100,0 3 2 995027484
CHOOSE unicorn_32 4354685041804152917 0,100,100,0 0,1,3 2 1762171661
CHOOSE unicorn_32 4354685041804152915 0,100,100,0 2 1 329722573
CHOOSE unicorn_32 -2691344259801801660 50,100,0 0 2 2123690729
CHOOSE unicorn_32 -2691344259801801659 50,100,0 0,1 2 -1761824458
CHOOSE unicorn_32 -2691344259801801662 50,100,0 0,1,2,3 0 -815287062
CHOOSE unicorn_32 8709371714889095215 100 - 0 849407856
CHOOSE unicorn_32 8709371714889095212 100 3 0 1455487786
CHOOSE unicorn_32 8709371714889095211 100 0,1,3 0 -735803874
CHOOSE unicorn_32 8709371714889095213 100 2 0 638423498
CHOOSE unicorn_32 1663342378923131922 0,0,0,0 0 2 1440217742
CHOOSE unicorn_32 1663342378923131923 0,0,0,0 0,1 2 1168806318
CHOOSE unicorn_32 1663342378923131924 0,0,0,0 0,1,2,3 0 -577107181
CHOOSE unicorn_32 -5382685754451591163 0,100 - 1 1141847390
CHOOSE unicorn_32 -5382685754451591162 0,100 3 1 601571400
CHOOSE unicorn_32 -5382685754451591167 0,100 0,1,3 0 681489403
CHOOSE unicorn_32 -5382685754451591161 0,100 2 1 -323812875
CHOOSE unicorn_32 6018029120727551208 - 0 0 -289938929
CHOOSE unicorn_32 6018029120727551209 - 0,1 0 1204273633
CHOOSE unicorn_32 6018029120727551214 - 0,1,2,3 0 -1609099527
CHOOSE unicorn_32 -987654321 0,0,100,0 - 3 2018681017
CHOOSE unicorn_32 -987654324 0,0,100,0 3 0 677938306
CHOOSE unicorn_32 -987654325 0,0,100,0 0,1,3 2 -1227801630
CHOOSE unicorn_32 -987654323 0,0,100,0 2 1 817937999
CHOOSE unicorn_32 7046029255354608474 100,0,0,0 0 3 -2096770713
CHOOSE unicorn_32 7046029255354608475 100,0,0,0 0,1 3 -1705141708
CHOOSE unicorn_32 7046029255354608476 100,0,0,0 0,1,2,3 0 -151344836
CHOOSE unicorn_32 -4354685563958890651 0,100,100,0 - 1 -821726509
CHOOSE unicorn_32 -4354685563958890650 0,100,100,0 3 0 1866556905
CHOOSE unicorn_32 -4354685563958890655 0,100,100,0 0,1,3 2 -816221640
CHOOSE unicorn_32 -4354685563958890649 0,100,100,0 2 1 -2018957766
CHOOSE unicorn_32 2691343690370048880 50,100,0 0 1 1922760480
CHOOSE unicorn_32 2691343690370048881 50,100,0 0,1 2 1257455053
CHOOSE unicorn_32 2691343690370048886 50,100,0 0,1,2,3 0 -999344884
CHOOSE unicorn_32 -8709371128981199077 100 - 0 -661791267
CHOOSE unicorn_32 -8709371128981199080 100 3 0 1953352371
CHOOSE unicorn_32 -8709371128981199073 100 0,1,3 0 -384171016
CHOOSE unicorn_32 -8709371128981199079 100 2 0 -467506285
CHOOSE unicorn_32 -1663341874584880346 0,0,0,0 0 1 -1270019391
CHOOSE unicorn_32 -1663341874584880345 0,0,0,0 0,1 2 58174497
CHOOSE unicorn_32 -1663341874584880352 0,0,0,0 0,1,2,3 0 312729399
CHOOSE unicorn_32 5382687379878281009 0,100 - 0 -1206273081
CHOOSE unicorn_32 5382687379878281010 0,100 3 1 -673861871
CHOOSE unicorn_32 5382687379878281013 0,100 0,1,3 0 1537812055
CHOOSE unicorn_32 5382687379878281011 0,100 2 1 879289766
CHOOSE unicorn_32 -6018027439464582180 - 0 0 -1010862029
CHOOSE unicorn_32 -6018027439464582179 - 0,1 0 1523587077
CHOOSE unicorn_32 -6018027439464582182 - 0,1,2,3 0 1930978077
CHOOSE unicorn_32 9223372036854775807 0,0,100,0 - 2 1402130883
CHOOSE unicorn_32 9223372036854775804 0,0,100,0 3 2 869190749
CHOOSE unicorn_32 9223372036854775803 0,0,100,0 0,1,3 2 660863589
CHOOSE unicorn_32 9223372036854775805 0,0,100,0 2 1 -63502804
CHOOSE unicorn_32 -2177342782468422678 100,0,0,0 0 1 1246501186
CHOOSE unicorn_32 -2177342782468422677 100,0,0,0 0,1 2 565436945
CHOOSE unicorn_32 -2177342782468422676 100,0,0,0 0,1,2,3 0 -1596273871
CHOOSE unicorn_32 4868686471917930453 0,100,100,0 - 1 -438309674
CHOOSE unicorn_32 4868686471917930454 0,100,100,0 3 2 -587325948
CHOOSE unicorn_32 4868686471917930449 0,100,100,0 0,1,3 2 -1679576139
CHOOSE unicorn_32 4868686471917930455 0,100,100,0 2 1 -1252663721
CHOOSE unicorn_32 -6532028347405268032 50,100,0 0 1 1514424123
CHOOSE unicorn_32 -6532028347405268031 50,100,0 0,1 2 1923909098
CHOOSE unicorn_32 -6532028347405268026 50,100,0 0,1,2,3 0 -812626189
CHOOSE unicorn_32 514000906981085099 100 - 0 79600482
CHOOSE unicorn_32 514000906981085096 100 3 0 -1461809864
CHOOSE unicorn_32 514000906981085103 100 0,1,3 0 -1963386353
CHOOSE unicorn_32 514000906981085097 100 2 0 413806104
CHOOSE unicorn_32 7560030161367438230 0,0,0,0 0 3 -1988604604
CHOOSE unicorn_32 7560030161367438231 0,0,0,0 0,1 2 -657592668
CHOOSE unicorn_32 7560030161367438224 0,0,0,0 0,1,2,3 0 1703114018
CHOOSE unicorn_32 -3840684657955760255 0,100 - 1 -1530919958
CHOOSE unicorn_32 -3840684657955760254 0,100 3 0 76281588
CHOOSE unicorn_32 -3840684657955760251 0,100 0,1,3 0 1992656962
CHOOSE unicorn_32 -3840684657955760253 0,100 2 1 -849070013
CHOOSE unicorn_32 3205344596430592876 - 0 0 1876925998
CHOOSE unicorn_32 3205344596430592877 - 0,1 0 384861724
CHOOSE unicorn_32 3205344596430592874 - 0,1,2,3 0 507168004
CHOOSE unicorn_32 -9223372036854775808 0,0,100,0 - 2 -1507543906
CHOOSE unicorn_32 -9223372036854775805 0,0,100,0 3 2 106484100
CHOOSE unicorn_32 -9223372036854775804 0,0,100,0 0,1,3 2 -1126855500
CHOOSE unicorn_32 -9223372036854775806 0,0,100,0 2 0 -847181513
CHOOSE unicorn_32 2177342782468422677 100,0,0,0 0 1 1330735456
CHOOSE unicorn_32 2177342782468422676 100,0,0,0 0,1 2 -1205212078
CHOOSE unicorn_32 2177342782468422675 100,0,0,0 0,1,2,3 0 -616278705
CHOOSE unicorn_32 -4868686471917930454 0,100,100,0 - 2 -280746957
CHOOSE unicorn_32 -4868686471917930455 0,100,100,0 3 0 1334327645
CHOOSE unicorn_32 -4868686471917930450 0,100,100,0 0,1,3 2 -966649770
CHOOSE unicorn_32 -4868686471917930456 0,100,100,0 2 1 648017804
CHOOSE unicorn_32 6532028347405268031 50,100,0 0 2 -272402636
CHOOSE unicorn_32 6532028347405268030 50,100,0 0,1 2 -1476235143
CHOOSE unicorn_32 6532028347405268025 50,100,0 0,1,2,3 0 -1393956483
CHOOSE unicorn_32 -514000906981085100 100 - 0 -548068695
CHOOSE unicorn_32 -514000906981085097 100 3 0 2071271395
CHOOSE unicorn_32 -514000906981085104 100 0,1,3 0 -241118831
CHOOSE unicorn_32 -514000906981085098 100 2 0 -903364349
CHOOSE unicorn_32 -7560030161367438231 0,0,0,0 0 2 -1677543483
CHOOSE unicorn_32 -7560030161367438232 0,0,0,0 0,1 2 170877029
CHOOSE unicorn_32 -7560030161367438225 0,0,0,0 0,1,2,3 0 672861774
CHOOSE unicorn_32 3840684657955760254 0,100 - 1 1464986111
CHOOSE unicorn_32 3840684657955760253 0,100 3 1 924188533
CHOOSE unicorn_32 3840684657955760250 0,100 0,1,3 0 354283566
CHOOSE unicorn_32 3840684657955760252 0,100 2 1 -22135128
CHOOSE unicorn_32 -3205344596430592877 - 0 0 226043218
CHOOSE unicorn_32 -3205344596430592878 - 0,1 0 1955122564
CHOOSE unicorn_32 -3205344596430592875 - 0,1,2,3 0 1553074796
CHOOSE unicorn_32 31337 0,0,100,0 - 2 -1882149745
CHOOSE unicorn_32 31338 0,0,100,0 3 1 1016734110
CHOOSE unicorn_32 31341 0,0,100,0 0,1,3 2 -2003822653
CHOOSE unicorn_32 31339 0,0,100,0 2 3 -668178202
CHOOSE unicorn_32 -7046029254386383236 100,0,0,0 0 3 -903395920
CHOOSE unicorn_32 -7046029254386383235 100,0,0,0 0,1 3 -1043366911
CHOOSE unicorn_32 -7046029254386383238 100,0,0,0 0,1,2,3 0 709265643
CHOOSE unicorn_32 4354685564936815171 0,100,100,0 - 2 -659585948
CHOOSE unicorn_32 4354685564936815168 0,100,100,0 3 0 947093806
CHOOSE unicorn_32 4354685564936815175 0,100,100,0 0,1,3 2 -1378038457
CHOOSE unicorn_32 4354685564936815169 0,100,100,0 2 0 822853627
CHOOSE unicorn_32 -2691343689449533866 50,100,0 0 1 2033264663
CHOOSE unicorn_32 -2691343689449533865 50,100,0 0,1 2 -1311184824
CHOOSE unicorn_32 -2691343689449533872 50,100,0 0,1,2,3 0 -148579047
CHOOSE unicorn_32 8709371129873664573 100 - 0 -1495485030
CHOOSE unicorn_32 8709371129873664574 100 3 0 -1963150096
CHOOSE unicorn_32 8709371129873664569 100 0,1,3 0 -1815208339
CHOOSE unicorn_32 8709371129873664575 100 2 0 -1185856496
CHOOSE unicorn_32 1663341875487315456 0,0,0,0 0 3 -904121164
CHOOSE unicorn_32 1663341875487315457 0,0,0,0 0,1 2 -655965356
CHOOSE unicorn_32 1663341875487315462 0,0,0,0 0,1,2,3 0 -848280910
CHOOSE unicorn_32 -5382687378899037673 0,100 - 1 1052482160
CHOOSE unicorn_32 -5382687378899037676 0,100 3 1 520066822
CHOOSE unicorn_32 -5382687378899037677 0,100 0,1,3 0 -1603240950
CHOOSE unicorn_32 -5382687378899037675 0,100 2 1 118970071
CHOOSE unicorn_32 6018027440424165114 - 0 0 1995807278
CHOOSE unicorn_32 6018027440424165115 - 0,1 0 537246240
CHOOSE unicorn_32 6018027440424165116 - 0,1,2,3 0 -1470595320
CHOOSE coach_67 0 0,0,100,0 - 2 -1454478562
CHOOSE coach_67 3 0,0,100,0 3 0 -256771609
CHOOSE coach_67 4 0,0,100,0 0,1,3 2 483757236
CHOOSE coach_67 2 0,0,100,0 2 3 15345335
CHOOSE coach_67 -7046029254386353131 100,0,0,0 0 2 -1365818593
CHOOSE coach_67 -7046029254386353132 100,0,0,0 0,1 2 -680557870
CHOOSE coach_67 -7046029254386353133 100,0,0,0 0,1,2,3 0 -1155246353
CHOOSE coach_67 4354685564936845354 0,100,100,0 - 2 8227251
CHOOSE coach_67 4354685564936845353 0,100,100,0 3 2 540114653
CHOOSE coach_67 4354685564936845358 0,100,100,0 0,1,3 2 375527510
CHOOSE coach_67 4354685564936845352 0,100,100,0 2 1 1209648652
CHOOSE coach_67 -2691343689449507777 50,100,0 0 1 -1617943258
CHOOSE coach_67 -2691343689449507778 50,100,0 0,1 2 -2023231751
CHOOSE coach_67 -2691343689449507783 50,100,0 0,1,2,3 0 -1924535523
CHOOSE coach_67 8709371129873690708 100 - 0 1062544041
CHOOSE coach_67 8709371129873690711 100 3 0 460658659
CHOOSE coach_67 8709371129873690704 100 0,1,3 0 289460337
CHOOSE coach_67 8709371129873690710 100 2 0 707248387
CHOOSE coach_67 1663341875487337577 0,0,0,0 0 3 1006811077
CHOOSE coach_67 1663341875487337576 0,0,0,0 0,1 3 1781489765
CHOOSE coach_67 1663341875487337583 0,0,0,0 0,1,2,3 0 935005358
CHOOSE coach_67 -5382687378899015554 0,100 - 0 1510711423
CHOOSE coach_67 -5382687378899015555 0,100 3 1 -96496139
CHOOSE coach_67 -5382687378899015558 0,100 0,1,3 0 620622350
CHOOSE coach_67 -5382687378899015556 0,100 2 0 833051688
CHOOSE coach_67 6018027440424182931 - 0 0 -317119438
CHOOSE coach_67 6018027440424182930 - 0,1 0 -2077701084
CHOOSE coach_67 6018027440424182933 - 0,1,2,3 0 1022496012
CHOOSE coach_67 1700000000123 0,0,100,0 - 2 -1272690835
CHOOSE coach_67 1700000000120 0,0,100,0 3 0 341854951
CHOOSE coach_67 1700000000127 0,0,100,0 0,1,3 2 348414349
CHOOSE coach_67 1700000000121 0,0,100,0 2 0 -590867436
CHOOSE coach_67 -7046030932889889682 100,0,0,0 0 1 -285540654
CHOOSE coach_67 -7046030932889889681 100,0,0,0 0,1 2 -966576385
CHOOSE coach_67 -7046030932889889688 100,0,0,0 0,1,2,3 0 570740890
CHOOSE coach_67 4354685041804152913 0,100,100,0 - 2 -620568730
CHOOSE coach_67 4354685041804152914 0,100,100,0 3 2 995027484
CHOOSE coach_67 4354685041804152917 0,100,100,0 0,1,3 2 1762171661
CHOOSE coach_67 4354685041804152915 0,100,100,0 2 1 329722573
CHOOSE coach_67 -2691344259801801660 50,100,0 0 2 2123690729
CHOOSE coach_67 -2691344259801801659 50,100,0 0,1 2 -1761824458
CHOOSE coach_67 -2691344259801801662 50,100,0 0,1,2,3 0 -815287062
CHOOSE coach_67 8709371714889095215 100 - 0 849407856
CHOOSE coach_67 8709371714889095212 100 3 0 1455487786
CHOOSE coach_67 8709371714889095211 100 0,1,3 0 -735803874
CHOOSE coach_67 8709371714889095213 100 2 0 638423498
CHOOSE coach_67 1663342378923131922 0,0,0,0 0 2 1440217742
CHOOSE coach_67 1663342378923131923 0,0,0,0 0,1 2 1168806318
CHOOSE coach_67 1663342378923131924 0,0,0,0 0,1,2,3 0 -577107181
CHOOSE coach_67 -5382685754451591163 0,100 - 1 1141847390
CHOOSE coach_67 -5382685754451591162 0,100 3 1 601571400
CHOOSE coach_67 -5382685754451591167 0,100 0,1,3 0 681489403
CHOOSE coach_67 -5382685754451591161 0,100 2 1 -323812875
CHOOSE coach_67 6018029120727551208 - 0 0 -289938929
CHOOSE coach_67 6018029120727551209 - 0,1 0 1204273633
CHOOSE coach_67 6018029120727551214 - 0,1,2,3 0 -1609099527
CHOOSE coach_67 -987654321 0,0,100,0 - 3 2018681017
CHOOSE coach_67 -987654324 0,0,100,0 3 0 677938306
CHOOSE coach_67 -987654325 0,0,100,0 0,1,3 2 -1227801630
CHOOSE coach_67 -987654323 0,0,100,0 2 1 817937999
CHOOSE coach_67 7046029255354608474 100,0,0,0 0 3 -2096770713
CHOOSE coach_67 7046029255354608475 100,0,0,0 0,1 3 -1705141708
CHOOSE coach_67 7046029255354608476 100,0,0,0 0,1,2,3 0 -151344836
CHOOSE coach_67 -4354685563958890651 0,100,100,0 - 1 -821726509
CHOOSE coach_67 -4354685563958890650 0,100,100,0 3 0 1866556905
CHOOSE coach_67 -4354685563958890655 0,100,100,0 0,1,3 2 -816221640
CHOOSE coach_67 -4354685563958890649 0,100,100,0 2 1 -2018957766
CHOOSE coach_67 2691343690370048880 50,100,0 0 1 1922760480
CHOOSE coach_67 2691343690370048881 50,100,0 0,1 2 1257455053
CHOOSE coach_67 2691343690370048886 50,100,0 0,1,2,3 0 -999344884
CHOOSE coach_67 -8709371128981199077 100 - 0 -661791267
CHOOSE coach_67 -8709371128981199080 100 3 0 1953352371
CHOOSE coach_67 -8709371128981199073 100 0,1,3 0 -384171016
CHOOSE coach_67 -8709371128981199079 100 2 0 -467506285
CHOOSE coach_67 -1663341874584880346 0,0,0,0 0 1 -1270019391
CHOOSE coach_67 -1663341874584880345 0,0,0,0 0,1 2 58174497
CHOOSE coach_67 -1663341874584880352 0,0,0,0 0,1,2,3 0 312729399
CHOOSE coach_67 5382687379878281009 0,100 - 0 -1206273081
CHOOSE coach_67 5382687379878281010 0,100 3 1 -673861871
CHOOSE coach_67 5382687379878281013 0,100 0,1,3 0 1537812055
CHOOSE coach_67 5382687379878281011 0,100 2 1 879289766
CHOOSE coach_67 -6018027439464582180 - 0 0 -1010862029
CHOOSE coach_67 -6018027439464582179 - 0,1 0 1523587077
CHOOSE coach_67 -6018027439464582182 - 0,1,2,3 0 1930978077
CHOOSE coach_67 9223372036854775807 0,0,100,0 - 2 1402130883
CHOOSE coach_67 9223372036854775804 0,0,100,0 3 2 869190749
CHOOSE coach_67 9223372036854775803 0,0,100,0 0,1,3 2 660863589
CHOOSE coach_67 9223372036854775805 0,0,100,0 2 1 -63502804
CHOOSE coach_67 -2177342782468422678 100,0,0,0 0 1 1246501186
CHOOSE coach_67 -2177342782468422677 100,0,0,0 0,1 2 565436945
CHOOSE coach_67 -2177342782468422676 100,0,0,0 0,1,2,3 0 -1596273871
CHOOSE coach_67 4868686471917930453 0,100,100,0 - 1 -438309674
CHOOSE coach_67 4868686471917930454 0,100,100,0 3 2 -587325948
CHOOSE coach_67 4868686471917930449 0,100,100,0 0,1,3 2 -1679576139
CHOOSE coach_67 4868686471917930455 0,100,100,0 2 1 -1252663721
CHOOSE coach_67 -6532028347405268032 50,100,0 0 1 1514424123
CHOOSE coach_67 -6532028347405268031 50,100,0 0,1 2 1923909098
CHOOSE coach_67 -6532028347405268026 50,100,0 0,1,2,3 0 -812626189
CHOOSE coach_67 514000906981085099 100 - 0 79600482
CHOOSE coach_67 514000906981085096 100 3 0 -1461809864
CHOOSE coach_67 514000906981085103 100 0,1,3 0 -1963386353
CHOOSE coach_67 514000906981085097 100 2 0 413806104
CHOOSE coach_67 7560030161367438230 0,0,0,0 0 3 -1988604604
CHOOSE coach_67 7560030161367438231 0,0,0,0 0,1 2 -657592668
CHOOSE coach_67 7560030161367438224 0,0,0,0 0,1,2,3 0 1703114018
CHOOSE coach_67 -3840684657955760255 0,100 - 1 -1530919958
CHOOSE coach_67 -3840684657955760254 0,100 3 1 -273244575
CHOOSE coach_67 -3840684657955760251 0,100 0,1,3 0 1992656962
CHOOSE coach_67 -3840684657955760253 0,100 2 1 -849070013
CHOOSE coach_67 3205344596430592876 - 0 0 1876925998
CHOOSE coach_67 3205344596430592877 - 0,1 0 384861724
CHOOSE coach_67 3205344596430592874 - 0,1,2,3 0 507168004
CHOOSE coach_67 -9223372036854775808 0,0,100,0 - 2 -1507543906
CHOOSE coach_67 -9223372036854775805 0,0,100,0 3 2 106484100
CHOOSE coach_67 -9223372036854775804 0,0,100,0 0,1,3 2 -1126855500
CHOOSE coach_67 -9223372036854775806 0,0,100,0 2 0 -847181513
CHOOSE coach_67 2177342782468422677 100,0,0,0 0 1 1330735456
CHOOSE coach_67 2177342782468422676 100,0,0,0 0,1 2 -1205212078
CHOOSE coach_67 2177342782468422675 100,0,0,0 0,1,2,3 0 -616278705
CHOOSE coach_67 -4868686471917930454 0,100,100,0 - 2 -280746957
CHOOSE coach_67 -4868686471917930455 0,100,100,0 3 0 1334327645
CHOOSE coach_67 -4868686471917930450 0,100,100,0 0,1,3 2 -966649770
CHOOSE coach_67 -4868686471917930456 0,100,100,0 2 1 648017804
CHOOSE coach_67 6532028347405268031 50,100,0 0 2 -272402636
CHOOSE coach_67 6532028347405268030 50,100,0 0,1 2 -1476235143
CHOOSE coach_67 6532028347405268025 50,100,0 0,1,2,3 0 -1393956483
CHOOSE coach_67 -514000906981085100 100 - 0 -548068695
CHOOSE coach_67 -514000906981085097 100 3 0 2071271395
CHOOSE coach_67 -514000906981085104 100 0,1,3 0 -241118831
CHOOSE coach_67 -514000906981085098 100 2 0 -903364349
CHOOSE coach_67 -7560030161367438231 0,0,0,0 0 2 -1677543483
CHOOSE coach_67 -7560030161367438232 0,0,0,0 0,1 2 170877029
CHOOSE coach_67 -7560030161367438225 0,0,0,0 0,1,2,3 0 672861774
CHOOSE coach_67 3840684657955760254 0,100 - 1 1464986111
CHOOSE coach_67 3840684657955760253 0,100 3 1 924188533
CHOOSE coach_67 3840684657955760250 0,100 0,1,3 0 354283566
CHOOSE coach_67 3840684657955760252 0,100 2 1 -22135128
CHOOSE coach_67 -3205344596430592877 - 0 0 226043218
CHOOSE coach_67 -3205344596430592878 - 0,1 0 1955122564
CHOOSE coach_67 -3205344596430592875 - 0,1,2,3 0 1553074796
CHOOSE coach_67 31337 0,0,100,0 - 2 -1882149745
CHOOSE coach_67 31338 0,0,100,0 3 1 1016734110
CHOOSE coach_67 31341 0,0,100,0 0,1,3 2 -2003822653
CHOOSE coach_67 31339 0,0,100,0 2 3 -668178202
CHOOSE coach_67 -7046029254386383236 100,0,0,0 0 3 -903395920
CHOOSE coach_67 -7046029254386383235 100,0,0,0 0,1 3 -1043366911
CHOOSE coach_67 -7046029254386383238 100,0,0,0 0,1,2,3 0 709265643
CHOOSE coach_67 4354685564936815171 0,100,100,0 - 2 -659585948
CHOOSE coach_67 4354685564936815168 0,100,100,0 3 0 947093806
CHOOSE coach_67 4354685564936815175 0,100,100,0 0,1,3 2 -1378038457
CHOOSE coach_67 4354685564936815169 0,100,100,0 2 0 822853627
CHOOSE coach_67 -2691343689449533866 50,100,0 0 1 2033264663
CHOOSE coach_67 -2691343689449533865 50,100,0 0,1 2 -1311184824
CHOOSE coach_67 -2691343689449533872 50,100,0 0,1,2,3 0 -148579047
CHOOSE coach_67 8709371129873664573 100 - 0 -1495485030
CHOOSE coach_67 8709371129873664574 100 3 0 -1963150096
CHOOSE coach_67 8709371129873664569 100 0,1,3 0 -1815208339
CHOOSE coach_67 8709371129873664575 100 2 0 -1185856496
CHOOSE coach_67 1663341875487315456 0,0,0,0 0 3 -904121164
CHOOSE coach_67 1663341875487315457 0,0,0,0 0,1 2 -655965356
CHOOSE coach_67 1663341875487315462 0,0,0,0 0,1,2,3 0 -848280910
CHOOSE coach_67 -5382687378899037673 0,100 - 1 1052482160
CHOOSE coach_67 -5382687378899037676 0,100 3 1 520066822
CHOOSE coach_67 -5382687378899037677 0,100 0,1,3 0 -1603240950
CHOOSE coach_67 -5382687378899037675 0,100 2 1 118970071
CHOOSE coach_67 6018027440424165114 - 0 0 1995807278
CHOOSE coach_67 6018027440424165115 - 0,1 0 537246240
CHOOSE coach_67 6018027440424165116 - 0,1,2,3 0 -1470595320
CHOOSE zephyr 0 0,0,100,0 - 1 -649160781
CHOOSE zephyr 3 0,0,100,0 3 0 -256771609
CHOOSE zephyr 4 0,0,100,0 0,1,3 2 483757236
CHOOSE zephyr 2 0,0,100,0 2 3 15345335
CHOOSE zephyr -7046029254386353131 100,0,0,0 0 2 -1365818593
CHOOSE zephyr -7046029254386353132 100,0,0,0 0,1 2 -680557870
CHOOSE zephyr -7046029254386353133 100,0,0,0 0,1,2,3 0 -1155246353
CHOOSE zephyr 4354685564936845354 0,100,100,0 - 3 8227251
CHOOSE zephyr 4354685564936845353 0,100,100,0 3 2 540114653
CHOOSE zephyr 4354685564936845358 0,100,100,0 0,1,3 2 375527510
CHOOSE zephyr 4354685564936845352 0,100,100,0 2 1 1209648652
CHOOSE zephyr -2691343689449507777 50,100,0 0 1 -1617943258
CHOOSE zephyr -2691343689449507778 50,100,0 0,1 2 -2023231751
CHOOSE zephyr -2691343689449507783 50,100,0 0,1,2,3 0 -1924535523
CHOOSE zephyr 8709371129873690708 100 - 0 1062544041
CHOOSE zephyr 8709371129873690711 100 3 0 460658659
CHOOSE zephyr 8709371129873690704 100 0,1,3 0 289460337
CHOOSE zephyr 8709371129873690710 100 2 0 707248387
CHOOSE zephyr 1663341875487337577 0,0,0,0 0 3 1006811077
CHOOSE zephyr 1663341875487337576 0,0,0,0 0,1 3 1781489765
CHOOSE zephyr 1663341875487337583 0,0,0,0 0,1,2,3 0 935005358
CHOOSE zephyr -5382687378899015554 0,100 - 0 1510711423
CHOOSE zephyr -5382687378899015555 0,100 3 1 -96496139
CHOOSE zephyr -5382687378899015558 0,100 0,1,3 0 620622350
CHOOSE zephyr -5382687378899015556 0,100 2 0 833051688
CHOOSE zephyr 6018027440424182931 - 0 0 -317119438
CHOOSE zephyr 6018027440424182930 - 0,1 0 -2077701084
CHOOSE zephyr 6018027440424182933 - 0,1,2,3 0 1022496012
CHOOSE zephyr 1700000000123 0,0,100,0 - 2 -1272690835
CHOOSE zephyr 1700000000120 0,0,100,0 3 0 341854951
CHOOSE zephyr 1700000000127 0,0,100,0 0,1,3 2 348414349
CHOOSE zephyr 1700000000121 0,0,100,0 2 3 681492313
CHOOSE zephyr -7046030932889889682 100,0,0,0 0 1 -285540654
CHOOSE zephyr -7046030932889889681 100,0,0,0 0,1 3 697157702
CHOOSE zephyr -7046030932889889688 100,0,0,0 0,1,2,3 0 570740890
CHOOSE zephyr 4354685041804152913 0,100,100,0 - 2 -620568730
CHOOSE zephyr 4354685041804152914 0,100,100,0 3 2 995027484
CHOOSE zephyr 4354685041804152917 0,100,100,0 0,1,3 2 1762171661
CHOOSE zephyr 4354685041804152915 0,100,100,0 2 1 329722573
CHOOSE zephyr -2691344259801801660 50,100,0 0 2 2123690729
CHOOSE zephyr -2691344259801801659 50,100,0 0,1 2 -1761824458
CHOOSE zephyr -2691344259801801662 50,100,0 0,1,2,3 0 -815287062
CHOOSE zephyr 8709371714889095215 100 - 0 849407856
CHOOSE zephyr 8709371714889095212 100 3 0 1455487786
CHOOSE zephyr 8709371714889095211 100 0,1,3 0 -735803874
CHOOSE zephyr 8709371714889095213 100 2 0 638423498
CHOOSE zephyr 1663342378923131922 0,0,0,0 0 2 1440217742
CHOOSE zephyr 1663342378923131923 0,0,0,0 0,1 2 1168806318
CHOOSE zephyr 1663342378923131924 0,0,0,0 0,1,2,3 0 -577107181
CHOOSE zephyr -5382685754451591163 0,100 - 1 1141847390
CHOOSE zephyr -5382685754451591162 0,100 3 1 601571400
CHOOSE zephyr -5382685754451591167 0,100 0,1,3 0 681489403
CHOOSE zephyr -5382685754451591161 0,100 2 0 -323812875
CHOOSE zephyr 6018029120727551208 - 0 0 -289938929
CHOOSE zephyr 6018029120727551209 - 0,1 0 1204273633
CHOOSE zephyr 6018029120727551214 - 0,1,2,3 0 -1609099527
CHOOSE zephyr -987654321 0,0,100,0 - 3 2018681017
CHOOSE zephyr -987654324 0,0,100,0 3 0 677938306
CHOOSE zephyr -987654325 0,0,100,0 0,1,3 2 -1227801630
CHOOSE zephyr -987654323 0,0,100,0 2 1 817937999
CHOOSE zephyr 7046029255354608474 100,0,0,0 0 3 -2096770713
CHOOSE zephyr 7046029255354608475 100,0,0,0 0,1 3 -1705141708
CHOOSE zephyr 7046029255354608476 100,0,0,0 0,1,2,3 0 -151344836
CHOOSE zephyr -4354685563958890651 0,100,100,0 - 1 -821726509
CHOOSE zephyr -4354685563958890650 0,100,100,0 3 0 1866556905
CHOOSE zephyr -4354685563958890655 0,100,100,0 0,1,3 2 -816221640
CHOOSE zephyr -4354685563958890649 0,100,100,0 2 1 862717469
CHOOSE zephyr 2691343690370048880 50,100,0 0 1 1922760480
CHOOSE zephyr 2691343690370048881 50,100,0 0,1 2 1257455053
CHOOSE zephyr 2691343690370048886 50,100,0 0,1,2,3 0 -999344884
CHOOSE zephyr -8709371128981199077 100 - 0 -661791267
CHOOSE zephyr -8709371128981199080 100 3 0 1953352371
CHOOSE zephyr -8709371128981199073 100 0,1,3 0 -384171016
CHOOSE zephyr -8709371128981199079 100 2 0 -467506285
CHOOSE zephyr -1663341874584880346 0,0,0,0 0 1 -1270019391
CHOOSE zephyr -1663341874584880345 0,0,0,0 0,1 2 58174497
CHOOSE zephyr -1663341874584880352 0,0,0,0 0,1,2,3 0 312729399
CHOOSE zephyr 5382687379878281009 0,100 - 0 -1206273081
CHOOSE zephyr 5382687379878281010 0,100 3 1 -673861871
CHOOSE zephyr 5382687379878281013 0,100 0,1,3 0 1537812055
CHOOSE zephyr 5382687379878281011 0,100 2 1 879289766
CHOOSE zephyr -6018027439464582180 - 0 0 -1010862029
CHOOSE zephyr -6018027439464582179 - 0,1 0 1523587077
CHOOSE zephyr -6018027439464582182 - 0,1,2,3 0 1930978077
CHOOSE zephyr 9223372036854775807 0,0,100,0 - 2 1402130883
CHOOSE zephyr 9223372036854775804 0,0,100,0 3 2 869190749
CHOOSE zephyr 9223372036854775803 0,0,100,0 0,1,3 2 660863589
CHOOSE zephyr 9223372036854775805 0,0,100,0 2 1 -63502804
CHOOSE zephyr -2177342782468422678 100,0,0,0 0 1 1246501186
CHOOSE zephyr -2177342782468422677 100,0,0,0 0,1 2 565436945
CHOOSE zephyr -2177342782468422676 100,0,0,0 0,1,2,3 0 -1596273871
CHOOSE zephyr 4868686471917930453 0,100,100,0 - 1 -438309674
CHOOSE zephyr 4868686471917930454 0,100,100,0 3 0 -587325948
CHOOSE zephyr 4868686471917930449 0,100,100,0 0,1,3 2 -1679576139
CHOOSE zephyr 4868686471917930455 0,100,100,0 2 1 -1252663721
CHOOSE zephyr -6532028347405268032 50,100,0 0 2 1514424123
CHOOSE zephyr -6532028347405268031 50,100,0 0,1 2 1923909098
CHOOSE zephyr -6532028347405268026 50,100,0 0,1,2,3 0 -812626189
CHOOSE zephyr 514000906981085099 100 - 0 79600482
CHOOSE zephyr 514000906981085096 100 3 0 -1461809864
CHOOSE zephyr 514000906981085103 100 0,1,3 0 -1963386353
CHOOSE zephyr 514000906981085097 100 2 0 413806104
CHOOSE zephyr 7560030161367438230 0,0,0,0 0 3 -1988604604
CHOOSE zephyr 7560030161367438231 0,0,0,0 0,1 2 -657592668
CHOOSE zephyr 7560030161367438224 0,0,0,0 0,1,2,3 0 1703114018
CHOOSE zephyr -3840684657955760255 0,100 - 1 -1530919958
CHOOSE zephyr -3840684657955760254 0,100 3 1 -273244575
CHOOSE zephyr -3840684657955760251 0,100 0,1,3 0 1992656962
CHOOSE zephyr -3840684657955760253 0,100 2 0 -849070013
CHOOSE zephyr 3205344596430592876 - 0 0 1876925998
CHOOSE zephyr 3205344596430592877 - 0,1 0 384861724
CHOOSE zephyr 3205344596430592874 - 0,1,2,3 0 507168004
CHOOSE zephyr -9223372036854775808 0,0,100,0 - 2 -1507543906
CHOOSE zephyr -9223372036854775805 0,0,100,0 3 2 106484100
CHOOSE zephyr -9223372036854775804 0,0,100,0 0,1,3 2 -1126855500
CHOOSE zephyr -9223372036854775806 0,0,100,0 2 0 -847181513
CHOOSE zephyr 2177342782468422677 100,0,0,0 0 1 1330735456
CHOOSE zephyr 2177342782468422676 100,0,0,0 0,1 2 -1205212078
CHOOSE zephyr 2177342782468422675 100,0,0,0 0,1,2,3 0 -616278705
CHOOSE zephyr -4868686471917930454 0,100,100,0 - 2 -280746957
CHOOSE zephyr -4868686471917930455 0,100,100,0 3 2 -1659325027
CHOOSE zephyr -4868686471917930450 0,100,100,0 0,1,3 2 -966649770
CHOOSE zephyr -4868686471917930456 0,100,100,0 2 1 648017804
CHOOSE zephyr 6532028347405268031 50,100,0 0 2 -272402636
CHOOSE zephyr 6532028347405268030 50,100,0 0,1 2 -1476235143
CHOOSE zephyr 6532028347405268025 50,100,0 0,1,2,3 0 -1393956483
CHOOSE zephyr -514000906981085100 100 - 0 -548068695
CHOOSE zephyr -514000906981085097 100 3 0 2071271395
CHOOSE zephyr -514000906981085104 100 0,1,3 0 -241118831
CHOOSE zephyr -514000906981085098 100 2 0 -903364349
CHOOSE zephyr -7560030161367438231 0,0,0,0 0 2 -1677543483
CHOOSE zephyr -7560030161367438232 0,0,0,0 0,1 2 170877029
CHOOSE zephyr -7560030161367438225 0,0,0,0 0,1,2,3 0 672861774
CHOOSE zephyr 3840684657955760254 0,100 - 1 1464986111
CHOOSE zephyr 3840684657955760253 0,100 3 0 -1661136416
CHOOSE zephyr 3840684657955760250 0,100 0,1,3 0 354283566
CHOOSE zephyr 3840684657955760252 0,100 2 1 -22135128
CHOOSE zephyr -3205344596430592877 - 0 0 226043218
CHOOSE zephyr -3205344596430592878 - 0,1 0 1955122564
CHOOSE zephyr -3205344596430592875 - 0,1,2,3 0 1553074796
CHOOSE zephyr 31337 0,0,100,0 - 2 -1882149745
CHOOSE zephyr 31338 0,0,100,0 3 1 1016734110
CHOOSE zephyr 31341 0,0,100,0 0,1,3 2 -2003822653
CHOOSE zephyr 31339 0,0,100,0 2 3 -668178202
CHOOSE zephyr -7046029254386383236 100,0,0,0 0 3 -903395920
CHOOSE zephyr -7046029254386383235 100,0,0,0 0,1 3 -1043366911
CHOOSE zephyr -7046029254386383238 100,0,0,0 0,1,2,3 0 709265643
CHOOSE zephyr 4354685564936815171 0,100,100,0 - 2 -659585948
CHOOSE zephyr 4354685564936815168 0,100,100,0 3 1 263062318
CHOOSE zephyr 4354685564936815175 0,100,100,0 0,1,3 2 -1378038457
CHOOSE zephyr 4354685564936815169 0,100,100,0 2 0 822853627
CHOOSE zephyr -2691343689449533866 50,100,0 0 1 2033264663
CHOOSE zephyr -2691343689449533865 50,100,0 0,1 2 -1311184824
CHOOSE zephyr -2691343689449533872 50,100,0 0,1,2,3 0 -148579047
CHOOSE zephyr 8709371129873664573 100 - 0 -1495485030
CHOOSE zephyr 8709371129873664574 100 3 0 -1963150096
CHOOSE zephyr 8709371129873664569 100 0,1,3 0 -1815208339
CHOOSE zephyr 8709371129873664575 100 2 0 -1185856496
CHOOSE zephyr 1663341875487315456 0,0,0,0 0 3 -904121164
CHOOSE zephyr 1663341875487315457 0,0,0,0 0,1 2 -655965356
CHOOSE zephyr 1663341875487315462 0,0,0,0 0,1,2,3 0 -848280910
CHOOSE zephyr -5382687378899037673 0,100 - 1 1052482160
CHOOSE zephyr -5382687378899037676 0,100 3 1 520066822
CHOOSE zephyr -5382687378899037677 0,100 0,1,3 0 -1603240950
CHOOSE zephyr -5382687378899037675 0,100 2 1 118970071
CHOOSE zephyr 6018027440424165114 - 0 0 1995807278
CHOOSE zephyr 6018027440424165115 - 0,1 0 537246240
CHOOSE zephyr 6018027440424165116 - 0,1,2,3 0 -1470595320
CHOOSE kyra 0 0,0,100,0 - 1 -649160781
CHOOSE kyra 3 0,0,100,0 3 0 -256771609
CHOOSE kyra 4 0,0,100,0 0,1,3 2 483757236
CHOOSE kyra 2 0,0,100,0 2 3 15345335
CHOOSE kyra -7046029254386353131 100,0,0,0 0 2 -1365818593
CHOOSE kyra -7046029254386353132 100,0,0,0 0,1 2 -680557870
CHOOSE kyra -7046029254386353133 100,0,0,0 0,1,2,3 0 -1155246353
CHOOSE kyra 4354685564936845354 0,100,100,0 - 3 8227251
CHOOSE kyra 4354685564936845353 0,100,100,0 3 2 540114653
CHOOSE kyra 4354685564936845358 0,100,100,0 0,1,3 2 375527510
CHOOSE kyra 4354685564936845352 0,100,100,0 2 1 1209648652
CHOOSE kyra -2691343689449507777 50,100,0 0 1 -1617943258
CHOOSE kyra -2691343689449507778 50,100,0 0,1 2 -2023231751
CHOOSE kyra -2691343689449507783 50,100,0 0,1,2,3 0 -1924535523
CHOOSE kyra 8709371129873690708 100 - 0 1062544041
CHOOSE kyra 8709371129873690711 100 3 0 460658659
CHOOSE kyra 8709371129873690704 100 0,1,3 0 289460337
CHOOSE kyra 8709371129873690710 100 2 0 707248387
CHOOSE kyra 1663341875487337577 0,0,0,0 0 3 1006811077
CHOOSE kyra 1663341875487337576 0,0,0,0 0,1 3 1781489765
CHOOSE kyra 1663341875487337583 0,0,0,0 0,1,2,3 0 935005358
CHOOSE kyra -5382687378899015554 0,100 - 0 1510711423
CHOOSE kyra -5382687378899015555 0,100 3 1 -96496139
CHOOSE kyra -5382687378899015558 0,100 0,1,3 0 620622350
CHOOSE kyra -5382687378899015556 0,100 2 0 833051688
CHOOSE kyra 6018027440424182931 - 0 0 -317119438
CHOOSE kyra 6018027440424182930 - 0,1 0 -2077701084
CHOOSE kyra 6018027440424182933 - 0,1,2,3 0 1022496012
CHOOSE kyra 1700000000123 0,0,100,0 - 2 -1272690835
CHOOSE kyra 1700000000120 0,0,100,0 3 0 341854951
CHOOSE kyra 1700000000127 0,0,100,0 0,1,3 2 348414349
CHOOSE kyra 1700000000121 0,0,100,0 2 3 681492313
CHOOSE kyra -7046030932889889682 100,0,0,0 0 1 -285540654
CHOOSE kyra -7046030932889889681 100,0,0,0 0,1 3 697157702
CHOOSE kyra -7046030932889889688 100,0,0,0 0,1,2,3 0 570740890
CHOOSE kyra 4354685041804152913 0,100,100,0 - 2 -620568730
CHOOSE kyra 4354685041804152914 0,100,100,0 3 2 995027484
CHOOSE kyra 4354685041804152917 0,100,100,0 0,1,3 2 1762171661
CHOOSE kyra 4354685041804152915 0,100,100,0 2 1 329722573
CHOOSE kyra -2691344259801801660 50,100,0 0 2 2123690729
CHOOSE kyra -2691344259801801659 50,100,0 0,1 2 -1761824458
CHOOSE kyra -2691344259801801662 50,100,0 0,1,2,3 0 -815287062
CHOOSE kyra 8709371714889095215 100 - 0 849407856
CHOOSE kyra 8709371714889095212 100 3 0 1455487786
CHOOSE kyra 8709371714889095211 100 0,1,3 0 -735803874
CHOOSE kyra 8709371714889095213 100 2 0 638423498
CHOOSE kyra 1663342378923131922 0,0,0,0 0 2 1440217742
CHOOSE kyra 1663342378923131923 0,0,0,0 0,1 2 1168806318
CHOOSE kyra 1663342378923131924 0,0,0,0 0,1,2,3 0 -577107181
CHOOSE kyra -5382685754451591163 0,100 - 1 1141847390
CHOOSE kyra -5382685754451591162 0,100 3 1 601571400
CHOOSE kyra -5382685754451591167 0,100 0,1,3 0 681489403
CHOOSE kyra -5382685754451591161 0,100 2 0 -323812875
CHOOSE kyra 6018029120727551208 - 0 0 -289938929
CHOOSE kyra 6018029120727551209 - 0,1 0 1204273633
CHOOSE kyra 6018029120727551214 - 0,1,2,3 0 -1609099527
CHOOSE kyra -987654321 0,0,100,0 - 3 2018681017
CHOOSE kyra -987654324 0,0,100,0 3 0 677938306
CHOOSE kyra -987654325 0,0,100,0 0,1,3 2 -1227801630
CHOOSE kyra -987654323 0,0,100,0 2 1 817937999
CHOOSE kyra 7046029255354608474 100,0,0,0 0 3 -2096770713
CHOOSE kyra 7046029255354608475 100,0,0,0 0,1 3 -1705141708
CHOOSE kyra 7046029255354608476 100,0,0,0 0,1,2,3 0 -151344836
CHOOSE kyra -4354685563958890651 0,100,100,0 - 1 -821726509
CHOOSE kyra -4354685563958890650 0,100,100,0 3 0 1866556905
CHOOSE kyra -4354685563958890655 0,100,100,0 0,1,3 2 -816221640
CHOOSE kyra -4354685563958890649 0,100,100,0 2 1 862717469
CHOOSE kyra 2691343690370048880 50,100,0 0 1 1922760480
CHOOSE kyra 2691343690370048881 50,100,0 0,1 2 1257455053
CHOOSE kyra 2691343690370048886 50,100,0 0,1,2,3 0 -999344884
CHOOSE kyra -8709371128981199077 100 - 0 -661791267
CHOOSE kyra -8709371128981199080 100 3 0 1953352371
CHOOSE kyra -8709371128981199073 100 0,1,3 0 -384171016
CHOOSE kyra -8709371128981199079 100 2 0 -467506285
CHOOSE kyra -1663341874584880346 0,0,0,0 0 1 -1270019391
CHOOSE kyra -1663341874584880345 0,0,0,0 0,1 2 58174497
CHOOSE kyra -1663341874584880352 0,0,0,0 0,1,2,3 0 312729399
CHOOSE kyra 5382687379878281009 0,100 - 0 -1206273081
CHOOSE kyra 5382687379878281010 0,100 3 1 -673861871
CHOOSE kyra 5382687379878281013 0,100 0,1,3 0 1537812055
CHOOSE kyra 5382687379878281011 0,100 2 1 879289766
CHOOSE kyra -6018027439464582180 - 0 0 -1010862029
CHOOSE kyra -6018027439464582179 - 0,1 0 1523587077
CHOOSE kyra -6018027439464582182 - 0,1,2,3 0 1930978077
CHOOSE kyra 9223372036854775807 0,0,100,0 - 2 1402130883
CHOOSE kyra 9223372036854775804 0,0,100,0 3 2 869190749
CHOOSE kyra 9223372036854775803 0,0,100,0 0,1,3 2 660863589
CHOOSE kyra 9223372036854775805 0,0,100,0 2 1 -63502804
CHOOSE kyra -2177342782468422678 100,0,0,0 0 1 1246501186
CHOOSE kyra -2177342782468422677 100,0,0,0 0,1 2 565436945
CHOOSE kyra -2177342782468422676 100,0,0,0 0,1,2,3 0 -1596273871
CHOOSE kyra 4868686471917930453 0,100,100,0 - 1 -438309674
CHOOSE kyra 4868686471917930454 0,100,100,0 3 0 -587325948
CHOOSE kyra 4868686471917930449 0,100,100,0 0,1,3 2 -1679576139
CHOOSE kyra 4868686471917930455 0,100,100,0 2 1 -1252663721
CHOOSE kyra -6532028347405268032 50,100,0 0 2 1514424123
CHOOSE kyra -6532028347405268031 50,100,0 0,1 2 1923909098
CHOOSE kyra -6532028347405268026 50,100,0 0,1,2,3 0 -812626189
CHOOSE kyra 514000906981085099 100 - 0 79600482
CHOOSE kyra 514000906981085096 100 3 0 -1461809864
CHOOSE kyra 514000906981085103 100 0,1,3 0 -1963386353
CHOOSE kyra 514000906981085097 100 2 0 413806104
CHOOSE kyra 7560030161367438230 0,0,0,0 0 3 -1988604604
CHOOSE kyra 7560030161367438231 0,0,0,0 0,1 2 -657592668
CHOOSE kyra 7560030161367438224 0,0,0,0 0,1,2,3 0 1703114018
CHOOSE kyra -3840684657955760255 0,100 - 1 -1530919958
CHOOSE kyra -3840684657955760254 0,100 3 1 -273244575
CHOOSE kyra -3840684657955760251 0,100 0,1,3 0 1992656962
CHOOSE kyra -3840684657955760253 0,100 2 0 -849070013
CHOOSE kyra 3205344596430592876 - 0 0 1876925998
CHOOSE kyra 3205344596430592877 - 0,1 0 384861724
CHOOSE kyra 3205344596430592874 - 0,1,2,3 0 507168004
CHOOSE kyra -9223372036854775808 0,0,100,0 - 2 -1507543906
CHOOSE kyra -9223372036854775805 0,0,100,0 3 2 106484100
CHOOSE kyra -9223372036854775804 0,0,100,0 0,1,3 2 -1126855500
CHOOSE kyra -9223372036854775806 0,0,100,0 2 0 -847181513
CHOOSE kyra 2177342782468422677 100,0,0,0 0 1 1330735456
CHOOSE kyra 2177342782468422676 100,0,0,0 0,1 2 -1205212078
CHOOSE kyra 2177342782468422675 100,0,0,0 0,1,2,3 0 -616278705
CHOOSE kyra -4868686471917930454 0,100,100,0 - 2 -280746957
CHOOSE kyra -4868686471917930455 0,100,100,0 3 2 -1659325027
CHOOSE kyra -4868686471917930450 0,100,100,0 0,1,3 2 -966649770
CHOOSE kyra -4868686471917930456 0,100,100,0 2 1 648017804
CHOOSE kyra 6532028347405268031 50,100,0 0 2 -272402636
CHOOSE kyra 6532028347405268030 50,100,0 0,1 2 -1476235143
CHOOSE kyra 6532028347405268025 50,100,0 0,1,2,3 0 -1393956483
CHOOSE kyra -514000906981085100 100 - 0 -548068695
CHOOSE kyra -514000906981085097 100 3 0 2071271395
CHOOSE kyra -514000906981085104 100 0,1,3 0 -241118831
CHOOSE kyra -514000906981085098 100 2 0 -903364349
CHOOSE kyra -7560030161367438231 0,0,0,0 0 2 -1677543483
CHOOSE kyra -7560030161367438232 0,0,0,0 0,1 2 170877029
CHOOSE kyra -7560030161367438225 0,0,0,0 0,1,2,3 0 672861774
CHOOSE kyra 3840684657955760254 0,100 - 1 1464986111
CHOOSE kyra 3840684657955760253 0,100 3 0 -1661136416
CHOOSE kyra 3840684657955760250 0,100 0,1,3 0 354283566
CHOOSE kyra 3840684657955760252 0,100 2 1 -22135128
CHOOSE kyra -3205344596430592877 - 0 0 226043218
CHOOSE kyra -3205344596430592878 - 0,1 0 1955122564
CHOOSE kyra -3205344596430592875 - 0,1,2,3 0 1553074796
CHOOSE kyra 31337 0,0,100,0 - 2 -1882149745
CHOOSE kyra 31338 0,0,100,0 3 1 1016734110
CHOOSE kyra 31341 0,0,100,0 0,1,3 2 -2003822653
CHOOSE kyra 31339 0,0,100,0 2 3 -668178202
CHOOSE kyra -7046029254386383236 100,0,0,0 0 3 -903395920
CHOOSE kyra -7046029254386383235 100,0,0,0 0,1 3 -1043366911
CHOOSE kyra -7046029254386383238 100,0,0,0 0,1,2,3 0 709265643
CHOOSE kyra 4354685564936815171 0,100,100,0 - 2 -659585948
CHOOSE kyra 4354685564936815168 0,100,100,0 3 1 263062318
CHOOSE kyra 4354685564936815175 0,100,100,0 0,1,3 2 -1378038457
CHOOSE kyra 4354685564936815169 0,100,100,0 2 0 822853627
CHOOSE kyra -2691343689449533866 50,100,0 0 1 2033264663
CHOOSE kyra -2691343689449533865 50,100,0 0,1 2 -1311184824
CHOOSE kyra -2691343689449533872 50,100,0 0,1,2,3 0 -148579047
CHOOSE kyra 8709371129873664573 100 - 0 -1495485030
CHOOSE kyra 8709371129873664574 100 3 0 -1963150096
CHOOSE kyra 8709371129873664569 100 0,1,3 0 -1815208339
CHOOSE kyra 8709371129873664575 100 2 0 -1185856496
CHOOSE kyra 1663341875487315456 0,0,0,0 0 3 -904121164
CHOOSE kyra 1663341875487315457 0,0,0,0 0,1 2 -655965356
CHOOSE kyra 1663341875487315462 0,0,0,0 0,1,2,3 0 -848280910
CHOOSE kyra -5382687378899037673 0,100 - 1 1052482160
CHOOSE kyra -5382687378899037676 0,100 3 1 520066822
CHOOSE kyra -5382687378899037677 0,100 0,1,3 0 -1603240950
CHOOSE kyra -5382687378899037675 0,100 2 1 118970071
CHOOSE kyra 6018027440424165114 - 0 0 1995807278
CHOOSE kyra 6018027440424165115 - 0,1 0 537246240
CHOOSE kyra 6018027440424165116 - 0,1,2,3 0 -1470595320
CHOOSE kyra_original 0 0,0,100,0 - 1 -649160781
CHOOSE kyra_original 3 0,0,100,0 3 0 -256771609
CHOOSE kyra_original 4 0,0,100,0 0,1,3 2 483757236
CHOOSE kyra_original 2 0,0,100,0 2 3 15345335
CHOOSE kyra_original -7046029254386353131 100,0,0,0 0 2 -1365818593
CHOOSE kyra_original -7046029254386353132 100,0,0,0 0,1 2 -680557870
CHOOSE kyra_original -7046029254386353133 100,0,0,0 0,1,2,3 0 -1155246353
CHOOSE kyra_original 4354685564936845354 0,100,100,0 - 3 8227251
CHOOSE kyra_original 4354685564936845353 0,100,100,0 3 2 540114653
CHOOSE kyra_original 4354685564936845358 0,100,100,0 0,1,3 2 375527510
CHOOSE kyra_original 4354685564936845352 0,100,100,0 2 1 1209648652
CHOOSE kyra_original -2691343689449507777 50,100,0 0 1 -1617943258
CHOOSE kyra_original -2691343689449507778 50,100,0 0,1 2 -2023231751
CHOOSE kyra_original -2691343689449507783 50,100,0 0,1,2,3 0 -1924535523
CHOOSE kyra_original 8709371129873690708 100 - 0 1062544041
CHOOSE kyra_original 8709371129873690711 100 3 0 460658659
CHOOSE kyra_original 8709371129873690704 100 0,1,3 0 289460337
CHOOSE kyra_original 8709371129873690710 100 2 0 707248387
CHOOSE kyra_original 1663341875487337577 0,0,0,0 0 3 1006811077
CHOOSE kyra_original 1663341875487337576 0,0,0,0 0,1 3 1781489765
CHOOSE kyra_original 1663341875487337583 0,0,0,0 0,1,2,3 0 935005358
CHOOSE kyra_original -5382687378899015554 0,100 - 0 1510711423
CHOOSE kyra_original -5382687378899015555 0,100 3 1 -96496139
CHOOSE kyra_original -5382687378899015558 0,100 0,1,3 0 620622350
CHOOSE kyra_original -5382687378899015556 0,100 2 0 833051688
CHOOSE kyra_original 6018027440424182931 - 0 0 -317119438
CHOOSE kyra_original 6018027440424182930 - 0,1 0 -2077701084
CHOOSE kyra_original 6018027440424182933 - 0,1,2,3 0 1022496012
CHOOSE kyra_original 1700000000123 0,0,100,0 - 2 -1272690835
CHOOSE kyra_original 1700000000120 0,0,100,0 3 0 341854951
CHOOSE kyra_original 1700000000127 0,0,100,0 0,1,3 2 348414349
CHOOSE kyra_original 1700000000121 0,0,100,0 2 3 681492313
CHOOSE kyra_original -7046030932889889682 100,0,0,0 0 1 -285540654
CHOOSE kyra_original -7046030932889889681 100,0,0,0 0,1 3 697157702
CHOOSE kyra_original -7046030932889889688 100,0,0,0 0,1,2,3 0 570740890
CHOOSE kyra_original 4354685041804152913 0,100,100,0 - 2 -620568730
CHOOSE kyra_original 4354685041804152914 0,100,100,0 3 2 995027484
CHOOSE kyra_original 4354685041804152917 0,100,100,0 0,1,3 2 1762171661
CHOOSE kyra_original 4354685041804152915 0,100,100,0 2 1 329722573
CHOOSE kyra_original -2691344259801801660 50,100,0 0 2 2123690729
CHOOSE kyra_original -2691344259801801659 50,100,0 0,1 2 -1761824458
CHOOSE kyra_original -2691344259801801662 50,100,0 0,1,2,3 0 -815287062
CHOOSE kyra_original 8709371714889095215 100 - 0 849407856
CHOOSE kyra_original 8709371714889095212 100 3 0 1455487786
CHOOSE kyra_original 8709371714889095211 100 0,1,3 0 -735803874
CHOOSE kyra_original 8709371714889095213 100 2 0 638423498
CHOOSE kyra_original 1663342378923131922 0,0,0,0 0 2 1440217742
CHOOSE kyra_original 1663342378923131923 0,0,0,0 0,1 2 1168806318
CHOOSE kyra_original 1663342378923131924 0,0,0,0 0,1,2,3 0 -577107181
CHOOSE kyra_original -5382685754451591163 0,100 - 1 1141847390
CHOOSE kyra_original -5382685754451591162 0,100 3 1 601571400
CHOOSE kyra_original -5382685754451591167 0,100 0,1,3 0 681489403
CHOOSE kyra_original -5382685754451591161 0,100 2 0 -323812875
CHOOSE kyra_original 6018029120727551208 - 0 0 -289938929
CHOOSE kyra_original 6018029120727551209 - 0,1 0 1204273633
CHOOSE kyra_original 6018029120727551214 - 0,1,2,3 0 -1609099527
CHOOSE kyra_original -987654321 0,0,100,0 - 3 2018681017
CHOOSE kyra_original -987654324 0,0,100,0 3 0 677938306
CHOOSE kyra_original -987654325 0,0,100,0 0,1,3 2 -1227801630
CHOOSE kyra_original -987654323 0,0,100,0 2 1 817937999
CHOOSE kyra_original 7046029255354608474 100,0,0,0 0 3 -2096770713
CHOOSE kyra_original 7046029255354608475 100,0,0,0 0,1 3 -1705141708
CHOOSE kyra_original 7046029255354608476 100,0,0,0 0,1,2,3 0 -151344836
CHOOSE kyra_original -4354685563958890651 0,100,100,0 - 1 -821726509
CHOOSE kyra_original -4354685563958890650 0,100,100,0 3 0 1866556905
CHOOSE kyra_original -4354685563958890655 0,100,100,0 0,1,3 2 -816221640
CHOOSE kyra_original -4354685563958890649 0,100,100,0 2 1 862717469
CHOOSE kyra_original 2691343690370048880 50,100,0 0 1 1922760480
CHOOSE kyra_original 2691343690370048881 50,100,0 0,1 2 1257455053
CHOOSE kyra_original 2691343690370048886 50,100,0 0,1,2,3 0 -999344884
CHOOSE kyra_original -8709371128981199077 100 - 0 -661791267
CHOOSE kyra_original -8709371128981199080 100 3 0 1953352371
CHOOSE kyra_original -8709371128981199073 100 0,1,3 0 -384171016
CHOOSE kyra_original -8709371128981199079 100 2 0 -467506285
CHOOSE kyra_original -1663341874584880346 0,0,0,0 0 1 -1270019391
CHOOSE kyra_original -1663341874584880345 0,0,0,0 0,1 2 58174497
CHOOSE kyra_original -1663341874584880352 0,0,0,0 0,1,2,3 0 312729399
CHOOSE kyra_original 5382687379878281009 0,100 - 0 -1206273081
CHOOSE kyra_original 5382687379878281010 0,100 3 1 -673861871
CHOOSE kyra_original 5382687379878281013 0,100 0,1,3 0 1537812055
CHOOSE kyra_original 5382687379878281011 0,100 2 1 879289766
CHOOSE kyra_original -6018027439464582180 - 0 0 -1010862029
CHOOSE kyra_original -6018027439464582179 - 0,1 0 1523587077
CHOOSE kyra_original -6018027439464582182 - 0,1,2,3 0 1930978077
CHOOSE kyra_original 9223372036854775807 0,0,100,0 - 2 1402130883
CHOOSE kyra_original 9223372036854775804 0,0,100,0 3 2 869190749
CHOOSE kyra_original 9223372036854775803 0,0,100,0 0,1,3 2 660863589
CHOOSE kyra_original 9223372036854775805 0,0,100,0 2 1 -63502804
CHOOSE kyra_original -2177342782468422678 100,0,0,0 0 1 1246501186
CHOOSE kyra_original -2177342782468422677 100,0,0,0 0,1 2 565436945
CHOOSE kyra_original -2177342782468422676 100,0,0,0 0,1,2,3 0 -1596273871
CHOOSE kyra_original 4868686471917930453 0,100,100,0 - 1 -438309674
CHOOSE kyra_original 4868686471917930454 0,100,100,0 3 0 -587325948
CHOOSE kyra_original 4868686471917930449 0,100,100,0 0,1,3 2 -1679576139
CHOOSE kyra_original 4868686471917930455 0,100,100,0 2 1 -1252663721
CHOOSE kyra_original -6532028347405268032 50,100,0 0 2 1514424123
CHOOSE kyra_original -6532028347405268031 50,100,0 0,1 2 1923909098
CHOOSE kyra_original -6532028347405268026 50,100,0 0,1,2,3 0 -812626189
CHOOSE kyra_original 514000906981085099 100 - 0 79600482
CHOOSE kyra_original 514000906981085096 100 3 0 -1461809864
CHOOSE kyra_original 514000906981085103 100 0,1,3 0 -1963386353
CHOOSE kyra_original 514000906981085097 100 2 0 413806104
CHOOSE kyra_original 7560030161367438230 0,0,0,0 0 3 -1988604604
CHOOSE kyra_original 7560030161367438231 0,0,0,0 0,1 2 -657592668
CHOOSE kyra_original 7560030161367438224 0,0,0,0 0,1,2,3 0 1703114018
CHOOSE kyra_original -3840684657955760255 0,100 - 1 -1530919958
CHOOSE kyra_original -3840684657955760254 0,100 3 1 -273244575
CHOOSE kyra_original -3840684657955760251 0,100 0,1,3 0 1992656962
CHOOSE kyra_original -3840684657955760253 0,100 2 0 -849070013
CHOOSE kyra_original 3205344596430592876 - 0 0 1876925998
CHOOSE kyra_original 3205344596430592877 - 0,1 0 384861724
CHOOSE kyra_original 3205344596430592874 - 0,1,2,3 0 507168004
CHOOSE kyra_original -9223372036854775808 0,0,100,0 - 2 -1507543906
CHOOSE kyra_original -9223372036854775805 0,0,100,0 3 2 106484100
CHOOSE kyra_original -9223372036854775804 0,0,100,0 0,1,3 2 -1126855500
CHOOSE kyra_original -9223372036854775806 0,0,100,0 2 0 -847181513
CHOOSE kyra_original 2177342782468422677 100,0,0,0 0 1 1330735456
CHOOSE kyra_original 2177342782468422676 100,0,0,0 0,1 2 -1205212078
CHOOSE kyra_original 2177342782468422675 100,0,0,0 0,1,2,3 0 -616278705
CHOOSE kyra_original -4868686471917930454 0,100,100,0 - 2 -280746957
CHOOSE kyra_original -4868686471917930455 0,100,100,0 3 2 -1659325027
CHOOSE kyra_original -4868686471917930450 0,100,100,0 0,1,3 2 -966649770
CHOOSE kyra_original -4868686471917930456 0,100,100,0 2 1 648017804
CHOOSE kyra_original 6532028347405268031 50,100,0 0 2 -272402636
CHOOSE kyra_original 6532028347405268030 50,100,0 0,1 2 -1476235143
CHOOSE kyra_original 6532028347405268025 50,100,0 0,1,2,3 0 -1393956483
CHOOSE kyra_original -514000906981085100 100 - 0 -548068695
CHOOSE kyra_original -514000906981085097 100 3 0 2071271395
CHOOSE kyra_original -514000906981085104 100 0,1,3 0 -241118831
CHOOSE kyra_original -514000906981085098 100 2 0 -903364349
CHOOSE kyra_original -7560030161367438231 0,0,0,0 0 2 -1677543483
CHOOSE kyra_original -7560030161367438232 0,0,0,0 0,1 2 170877029
CHOOSE kyra_original -7560030161367438225 0,0,0,0 0,1,2,3 0 672861774
CHOOSE kyra_original 3840684657955760254 0,100 - 1 1464986111
CHOOSE kyra_original 3840684657955760253 0,100 3 0 -1661136416
CHOOSE kyra_original 3840684657955760250 0,100 0,1,3 0 354283566
CHOOSE kyra_original 3840684657955760252 0,100 2 1 -22135128
CHOOSE kyra_original -3205344596430592877 - 0 0 226043218
CHOOSE kyra_original -3205344596430592878 - 0,1 0 1955122564
CHOOSE kyra_original -3205344596430592875 - 0,1,2,3 0 1553074796
CHOOSE kyra_original 31337 0,0,100,0 - 2 -1882149745
CHOOSE kyra_original 31338 0,0,100,0 3 1 1016734110
CHOOSE kyra_original 31341 0,0,100,0 0,1,3 2 -2003822653
CHOOSE kyra_original 31339 0,0,100,0 2 3 -668178202
CHOOSE kyra_original -7046029254386383236 100,0,0,0 0 3 -903395920
CHOOSE kyra_original -7046029254386383235 100,0,0,0 0,1 3 -1043366911
CHOOSE kyra_original -7046029254386383238 100,0,0,0 0,1,2,3 0 709265643
CHOOSE kyra_original 4354685564936815171 0,100,100,0 - 2 -659585948
CHOOSE kyra_original 4354685564936815168 0,100,100,0 3 1 263062318
CHOOSE kyra_original 4354685564936815175 0,100,100,0 0,1,3 2 -1378038457
CHOOSE kyra_original 4354685564936815169 0,100,100,0 2 0 822853627
CHOOSE kyra_original -2691343689449533866 50,100,0 0 1 2033264663
CHOOSE kyra_original -2691343689449533865 50,100,0 0,1 2 -1311184824
CHOOSE kyra_original -2691343689449533872 50,100,0 0,1,2,3 0 -148579047
CHOOSE kyra_original 8709371129873664573 100 - 0 -1495485030
CHOOSE kyra_original 8709371129873664574 100 3 0 -1963150096
CHOOSE kyra_original 8709371129873664569 100 0,1,3 0 -1815208339
CHOOSE kyra_original 8709371129873664575 100 2 0 -1185856496
CHOOSE kyra_original 1663341875487315456 0,0,0,0 0 3 -904121164
CHOOSE kyra_original 1663341875487315457 0,0,0,0 0,1 2 -655965356
CHOOSE kyra_original 1663341875487315462 0,0,0,0 0,1,2,3 0 -848280910
CHOOSE kyra_original -5382687378899037673 0,100 - 1 1052482160
CHOOSE kyra_original -5382687378899037676 0,100 3 1 520066822
CHOOSE kyra_original -5382687378899037677 0,100 0,1,3 0 -1603240950
CHOOSE kyra_original -5382687378899037675 0,100 2 1 118970071
CHOOSE kyra_original 6018027440424165114 - 0 0 1995807278
CHOOSE kyra_original 6018027440424165115 - 0,1 0 537246240
CHOOSE kyra_original 6018027440424165116 - 0,1,2,3 0 -1470595320
CHOOSE flare 0 0,0,100,0 - 1 -649160781
CHOOSE flare 3 0,0,100,0 3 0 -256771609
CHOOSE flare 4 0,0,100,0 0,1,3 2 483757236
CHOOSE flare 2 0,0,100,0 2 3 15345335
CHOOSE flare -7046029254386353131 100,0,0,0 0 2 -1365818593
CHOOSE flare -7046029254386353132 100,0,0,0 0,1 2 -680557870
CHOOSE flare -7046029254386353133 100,0,0,0 0,1,2,3 0 -1155246353
CHOOSE flare 4354685564936845354 0,100,100,0 - 3 8227251
CHOOSE flare 4354685564936845353 0,100,100,0 3 0 540114653
CHOOSE flare 4354685564936845358 0,100,100,0 0,1,3 2 375527510
CHOOSE flare 4354685564936845352 0,100,100,0 2 1 1209648652
CHOOSE flare -2691343689449507777 50,100,0 0 1 -1617943258
CHOOSE flare -2691343689449507778 50,100,0 0,1 2 -2023231751
CHOOSE flare -2691343689449507783 50,100,0 0,1,2,3 0 -1924535523
CHOOSE flare 8709371129873690708 100 - 0 1062544041
CHOOSE flare 8709371129873690711 100 3 0 460658659
CHOOSE flare 8709371129873690704 100 0,1,3 0 289460337
CHOOSE flare 8709371129873690710 100 2 0 707248387
CHOOSE flare 1663341875487337577 0,0,0,0 0 3 1006811077
CHOOSE flare 1663341875487337576 0,0,0,0 0,1 3 1781489765
CHOOSE flare 1663341875487337583 0,0,0,0 0,1,2,3 0 935005358
CHOOSE flare -5382687378899015554 0,100 - 0 1510711423
CHOOSE flare -5382687378899015555 0,100 3 1 -96496139
CHOOSE flare -5382687378899015558 0,100 0,1,3 0 620622350
CHOOSE flare -5382687378899015556 0,100 2 0 833051688
CHOOSE flare 6018027440424182931 - 0 0 -317119438
CHOOSE flare 6018027440424182930 - 0,1 0 -2077701084
CHOOSE flare 6018027440424182933 - 0,1,2,3 0 1022496012
CHOOSE flare 1700000000123 0,0,100,0 - 2 -1272690835
CHOOSE flare 1700000000120 0,0,100,0 3 0 341854951
CHOOSE flare 1700000000127 0,0,100,0 0,1,3 2 348414349
CHOOSE flare 1700000000121 0,0,100,0 2 3 681492313
CHOOSE flare -7046030932889889682 100,0,0,0 0 1 -285540654
CHOOSE flare -7046030932889889681 100,0,0,0 0,1 3 697157702
CHOOSE flare -7046030932889889688 100,0,0,0 0,1,2,3 0 570740890
CHOOSE flare 4354685041804152913 0,100,100,0 - 2 -620568730
CHOOSE flare 4354685041804152914 0,100,100,0 3 2 995027484
CHOOSE flare 4354685041804152917 0,100,100,0 0,1,3 2 1762171661
CHOOSE flare 4354685041804152915 0,100,100,0 2 1 329722573
CHOOSE flare -2691344259801801660 50,100,0 0 2 2123690729
CHOOSE flare -2691344259801801659 50,100,0 0,1 2 -1761824458
CHOOSE flare -2691344259801801662 50,100,0 0,1,2,3 0 -815287062
CHOOSE flare 8709371714889095215 100 - 0 849407856
CHOOSE flare 8709371714889095212 100 3 0 1455487786
CHOOSE flare 8709371714889095211 100 0,1,3 0 -735803874
CHOOSE flare 8709371714889095213 100 2 0 638423498
CHOOSE flare 1663342378923131922 0,0,0,0 0 2 1440217742
CHOOSE flare 1663342378923131923 0,0,0,0 0,1 2 1168806318
CHOOSE flare 1663342378923131924 0,0,0,0 0,1,2,3 0 -577107181
CHOOSE flare -5382685754451591163 0,100 - 1 1141847390
CHOOSE flare -5382685754451591162 0,100 3 1 601571400
CHOOSE flare -5382685754451591167 0,100 0,1,3 0 681489403
CHOOSE flare -5382685754451591161 0,100 2 0 -323812875
CHOOSE flare 6018029120727551208 - 0 0 -289938929
CHOOSE flare 6018029120727551209 - 0,1 0 1204273633
CHOOSE flare 6018029120727551214 - 0,1,2,3 0 -1609099527
CHOOSE flare -987654321 0,0,100,0 - 3 2018681017
CHOOSE flare -987654324 0,0,100,0 3 0 677938306
CHOOSE flare -987654325 0,0,100,0 0,1,3 2 -1227801630
CHOOSE flare -987654323 0,0,100,0 2 1 817937999
CHOOSE flare 7046029255354608474 100,0,0,0 0 3 -2096770713
CHOOSE flare 7046029255354608475 100,0,0,0 0,1 3 -1705141708
CHOOSE flare 7046029255354608476 100,0,0,0 0,1,2,3 0 -151344836
CHOOSE flare -4354685563958890651 0,100,100,0 - 2 1130511267
CHOOSE flare -4354685563958890650 0,100,100,0 3 0 1866556905
CHOOSE flare -4354685563958890655 0,100,100,0 0,1,3 2 -816221640
CHOOSE flare -4354685563958890649 0,100,100,0 2 1 862717469
CHOOSE flare 2691343690370048880 50,100,0 0 1 1922760480
CHOOSE flare 2691343690370048881 50,100,0 0,1 2 1257455053
CHOOSE flare 2691343690370048886 50,100,0 0,1,2,3 0 -999344884
CHOOSE flare -8709371128981199077 100 - 0 -661791267
CHOOSE flare -8709371128981199080 100 3 0 1953352371
CHOOSE flare -8709371128981199073 100 0,1,3 0 -384171016
CHOOSE flare -8709371128981199079 100 2 0 -467506285
CHOOSE flare -1663341874584880346 0,0,0,0 0 1 -1270019391
CHOOSE flare -1663341874584880345 0,0,0,0 0,1 2 58174497
CHOOSE flare -1663341874584880352 0,0,0,0 0,1,2,3 0 312729399
CHOOSE flare 5382687379878281009 0,100 - 0 -1206273081
CHOOSE flare 5382687379878281010 0,100 3 1 -673861871
CHOOSE flare 5382687379878281013 0,100 0,1,3 0 1537812055
CHOOSE flare 5382687379878281011 0,100 2 1 879289766
CHOOSE flare -6018027439464582180 - 0 0 -1010862029
CHOOSE flare -6018027439464582179 - 0,1 0 1523587077
CHOOSE flare -6018027439464582182 - 0,1,2,3 0 1930978077
CHOOSE flare 9223372036854775807 0,0,100,0 - 2 1402130883
CHOOSE flare 9223372036854775804 0,0,100,0 3 2 869190749
CHOOSE flare 9223372036854775803 0,0,100,0 0,1,3 2 660863589
CHOOSE flare 9223372036854775805 0,0,100,0 2 1 -63502804
CHOOSE flare -2177342782468422678 100,0,0,0 0 1 1246501186
CHOOSE flare -2177342782468422677 100,0,0,0 0,1 2 565436945
CHOOSE flare -2177342782468422676 100,0,0,0 0,1,2,3 0 -1596273871
CHOOSE flare 4868686471917930453 0,100,100,0 - 1 -438309674
CHOOSE flare 4868686471917930454 0,100,100,0 3 0 -587325948
CHOOSE flare 4868686471917930449 0,100,100,0 0,1,3 2 -1679576139
CHOOSE flare 4868686471917930455 0,100,100,0 2 1 -1252663721
CHOOSE flare -6532028347405268032 50,100,0 0 2 1514424123
CHOOSE flare -6532028347405268031 50,100,0 0,1 2 1923909098
CHOOSE flare -6532028347405268026 50,100,0 0,1,2,3 0 -812626189
CHOOSE flare 514000906981085099 100 - 0 79600482
CHOOSE flare 514000906981085096 100 3 0 -1461809864
CHOOSE flare 514000906981085103 100 0,1,3 0 -1963386353
CHOOSE flare 514000906981085097 100 2 0 413806104
CHOOSE flare 7560030161367438230 0,0,0,0 0 3 -1988604604
CHOOSE flare 7560030161367438231 0,0,0,0 0,1 2 -657592668
CHOOSE flare 7560030161367438224 0,0,0,0 0,1,2,3 0 1703114018
CHOOSE flare -3840684657955760255 0,100 - 0 -401248275
CHOOSE flare -3840684657955760254 0,100 3 1 -273244575
CHOOSE flare -3840684657955760251 0,100 0,1,3 0 1992656962
CHOOSE flare -3840684657955760253 0,100 2 0 -849070013
CHOOSE flare 3205344596430592876 - 0 0 1876925998
CHOOSE flare 3205344596430592877 - 0,1 0 384861724
CHOOSE flare 3205344596430592874 - 0,1,2,3 0 507168004
CHOOSE flare -9223372036854775808 0,0,100,0 - 2 -1507543906
CHOOSE flare -9223372036854775805 0,0,100,0 3 2 106484100
CHOOSE flare -9223372036854775804 0,0,100,0 0,1,3 2 -1126855500
CHOOSE flare -9223372036854775806 0,0,100,0 2 0 -847181513
CHOOSE flare 2177342782468422677 100,0,0,0 0 1 1330735456
CHOOSE flare 2177342782468422676 100,0,0,0 0,1 2 -1205212078
CHOOSE flare 2177342782468422675 100,0,0,0 0,1,2,3 0 -616278705
CHOOSE flare -4868686471917930454 0,100,100,0 - 2 -280746957
CHOOSE flare -4868686471917930455 0,100,100,0 3 2 -1659325027
CHOOSE flare -4868686471917930450 0,100,100,0 0,1,3 2 -966649770
CHOOSE flare -4868686471917930456 0,100,100,0 2 1 648017804
CHOOSE flare 6532028347405268031 50,100,0 0 2 -272402636
CHOOSE flare 6532028347405268030 50,100,0 0,1 2 -1476235143
CHOOSE flare 6532028347405268025 50,100,0 0,1,2,3 0 -1393956483
CHOOSE flare -514000906981085100 100 - 0 -548068695
CHOOSE flare -514000906981085097 100 3 0 2071271395
CHOOSE flare -514000906981085104 100 0,1,3 0 -241118831
CHOOSE flare -514000906981085098 100 2 0 -903364349
CHOOSE flare -7560030161367438231 0,0,0,0 0 2 -1677543483
CHOOSE flare -7560030161367438232 0,0,0,0 0,1 2 170877029
CHOOSE flare -7560030161367438225 0,0,0,0 0,1,2,3 0 672861774
CHOOSE flare 3840684657955760254 0,100 - 1 -1797397500
CHOOSE flare 3840684657955760253 0,100 3 0 -1661136416
CHOOSE flare 3840684657955760250 0,100 0,1,3 0 354283566
CHOOSE flare 3840684657955760252 0,100 2 1 -22135128
CHOOSE flare -3205344596430592877 - 0 0 226043218
CHOOSE flare -3205344596430592878 - 0,1 0 1955122564
CHOOSE flare -3205344596430592875 - 0,1,2,3 0 1553074796
CHOOSE flare 31337 0,0,100,0 - 3 -1882149745
CHOOSE flare 31338 0,0,100,0 3 1 1016734110
CHOOSE flare 31341 0,0,100,0 0,1,3 2 -2003822653
CHOOSE flare 31339 0,0,100,0 2 3 -668178202
CHOOSE flare -7046029254386383236 100,0,0,0 0 1 -28514381
CHOOSE flare -7046029254386383235 100,0,0,0 0,1 3 -1043366911
CHOOSE flare -7046029254386383238 100,0,0,0 0,1,2,3 0 709265643
CHOOSE flare 4354685564936815171 0,100,100,0 - 2 -659585948
CHOOSE flare 4354685564936815168 0,100,100,0 3 1 263062318
CHOOSE flare 4354685564936815175 0,100,100,0 0,1,3 2 -1378038457
CHOOSE flare 4354685564936815169 0,100,100,0 2 0 822853627
CHOOSE flare -2691343689449533866 50,100,0 0 1 2033264663
CHOOSE flare -2691343689449533865 50,100,0 0,1 2 -1311184824
CHOOSE flare -2691343689449533872 50,100,0 0,1,2,3 0 -148579047
CHOOSE flare 8709371129873664573 100 - 0 -1495485030
CHOOSE flare 8709371129873664574 100 3 0 -1963150096
CHOOSE flare 8709371129873664569 100 0,1,3 0 -1815208339
CHOOSE flare 8709371129873664575 100 2 0 -1185856496
CHOOSE flare 1663341875487315456 0,0,0,0 0 3 -904121164
CHOOSE flare 1663341875487315457 0,0,0,0 0,1 2 -655965356
CHOOSE flare 1663341875487315462 0,0,0,0 0,1,2,3 0 -848280910
CHOOSE flare -5382687378899037673 0,100 - 1 1052482160
CHOOSE flare -5382687378899037676 0,100 3 1 520066822
CHOOSE flare -5382687378899037677 0,100 0,1,3 0 -1603240950
CHOOSE flare -5382687378899037675 0,100 2 1 118970071
CHOOSE flare 6018027440424165114 - 0 0 1995807278
CHOOSE flare 6018027440424165115 - 0,1 0 537246240
CHOOSE flare 6018027440424165116 - 0,1,2,3 0 -1470595320
CHOOSE ace_23 0 0,0,100,0 - 1 -649160781
CHOOSE ace_23 3 0,0,100,0 3 0 -256771609
CHOOSE ace_23 4 0,0,100,0 0,1,3 2 483757236
CHOOSE ace_23 2 0,0,100,0 2 0 -382311875
CHOOSE ace_23 -7046029254386353131 100,0,0,0 0 1 778235912
CHOOSE ace_23 -7046029254386353132 100,0,0,0 0,1 3 631744338
CHOOSE ace_23 -7046029254386353133 100,0,0,0 0,1,2,3 0 -1155246353
CHOOSE ace_23 4354685564936845354 0,100,100,0 - 3 -1541192439
CHOOSE ace_23 4354685564936845353 0,100,100,0 3 1 -1140722939
CHOOSE ace_23 4354685564936845358 0,100,100,0 0,1,3 2 375527510
CHOOSE ace_23 4354685564936845352 0,100,100,0 2 1 1209648652
CHOOSE ace_23 -2691343689449507777 50,100,0 0 1 -827469668
CHOOSE ace_23 -2691343689449507778 50,100,0 0,1 2 -970374866
CHOOSE ace_23 -2691343689449507783 50,100,0 0,1,2,3 0 -1924535523
CHOOSE ace_23 8709371129873690708 100 - 0 1062544041
CHOOSE ace_23 8709371129873690711 100 3 0 460658659
CHOOSE ace_23 8709371129873690704 100 0,1,3 0 289460337
CHOOSE ace_23 8709371129873690710 100 2 0 707248387
CHOOSE ace_23 1663341875487337577 0,0,0,0 0 3 1006811077
CHOOSE ace_23 1663341875487337576 0,0,0,0 0,1 3 1781489765
CHOOSE ace_23 1663341875487337583 0,0,0,0 0,1,2,3 0 935005358
CHOOSE ace_23 -5382687378899015554 0,100 - 0 -1513580180
CHOOSE ace_23 -5382687378899015555 0,100 3 1 2112582520
CHOOSE ace_23 -5382687378899015558 0,100 0,1,3 0 620622350
CHOOSE ace_23 -5382687378899015556 0,100 2 0 1978059750
CHOOSE ace_23 6018027440424182931 - 0 0 -317119438
CHOOSE ace_23 6018027440424182930 - 0,1 0 -2077701084
CHOOSE ace_23 6018027440424182933 - 0,1,2,3 0 1022496012
CHOOSE ace_23 1700000000123 0,0,100,0 - 3 950665439
CHOOSE ace_23 1700000000120 0,0,100,0 3 1 814436075
CHOOSE ace_23 1700000000127 0,0,100,0 0,1,3 2 348414349
CHOOSE ace_23 1700000000121 0,0,100,0 2 3 681492313
CHOOSE ace_23 -7046030932889889682 100,0,0,0 0 2 834279636
CHOOSE ace_23 -7046030932889889681 100,0,0,0 0,1 3 697157702
CHOOSE ace_23 -7046030932889889688 100,0,0,0 0,1,2,3 0 570740890
CHOOSE ace_23 4354685041804152913 0,100,100,0 - 2 -339858915
CHOOSE ace_23 4354685041804152914 0,100,100,0 3 1 -484783135
CHOOSE ace_23 4354685041804152917 0,100,100,0 0,1,3 2 1762171661
CHOOSE ace_23 4354685041804152915 0,100,100,0 2 0 -606710637
CHOOSE ace_23 -2691344259801801660 50,100,0 0 2 2123690729
CHOOSE ace_23 -2691344259801801659 50,100,0 0,1 2 163812906
CHOOSE ace_23 -2691344259801801662 50,100,0 0,1,2,3 0 -815287062
CHOOSE ace_23 8709371714889095215 100 - 0 849407856
CHOOSE ace_23 8709371714889095212 100 3 0 1455487786
CHOOSE ace_23 8709371714889095211 100 0,1,3 0 -735803874
CHOOSE ace_23 8709371714889095213 100 2 0 638423498
CHOOSE ace_23 1663342378923131922 0,0,0,0 0 2 1440217742
CHOOSE ace_23 1663342378923131923 0,0,0,0 0,1 2 1168806318
CHOOSE ace_23 1663342378923131924 0,0,0,0 0,1,2,3 0 -577107181
CHOOSE ace_23 -5382685754451591163 0,100 - 1 737196656
CHOOSE ace_23 -5382685754451591162 0,100 3 0 1687261348
CHOOSE ace_23 -5382685754451591167 0,100 0,1,3 0 681489403
CHOOSE ace_23 -5382685754451591161 0,100 2 1 1543364858
CHOOSE ace_23 6018029120727551208 - 0 0 -289938929
CHOOSE ace_23 6018029120727551209 - 0,1 0 1204273633
CHOOSE ace_23 6018029120727551214 - 0,1,2,3 0 -1609099527
CHOOSE ace_23 -987654321 0,0,100,0 - 3 2018681017
CHOOSE ace_23 -987654324 0,0,100,0 3 0 677938306
CHOOSE ace_23 -987654325 0,0,100,0 0,1,3 2 -1227801630
CHOOSE ace_23 -987654323 0,0,100,0 2 1 817937999
CHOOSE ace_23 7046029255354608474 100,0,0,0 0 3 -2096770713
CHOOSE ace_23 7046029255354608475 100,0,0,0 0,1 2 -370861798
CHOOSE ace_23 7046029255354608476 100,0,0,0 0,1,2,3 0 -151344836
CHOOSE ace_23 -4354685563958890651 0,100,100,0 - 2 1130511267
CHOOSE ace_23 -4354685563958890650 0,100,100,0 3 1 729765255
CHOOSE ace_23 -4354685563958890655 0,100,100,0 0,1,3 2 -816221640
CHOOSE ace_23 -4354685563958890649 0,100,100,0 2 1 862717469
CHOOSE ace_23 2691343690370048880 50,100,0 0 2 1634523120
CHOOSE ace_23 2691343690370048881 50,100,0 0,1 2 1781016702
CHOOSE ace_23 2691343690370048886 50,100,0 0,1,2,3 0 -999344884
CHOOSE ace_23 -8709371128981199077 100 - 0 -661791267
CHOOSE ace_23 -8709371128981199080 100 3 0 1953352371
CHOOSE ace_23 -8709371128981199073 100 0,1,3 0 -384171016
CHOOSE ace_23 -8709371128981199079 100 2 0 -467506285
CHOOSE ace_23 -1663341874584880346 0,0,0,0 0 1 -1270019391
CHOOSE ace_23 -1663341874584880345 0,0,0,0 0,1 2 58174497
CHOOSE ace_23 -1663341874584880352 0,0,0,0 0,1,2,3 0 312729399
CHOOSE ace_23 5382687379878281009 0,100 - 0 -1206273081
CHOOSE ace_23 5382687379878281010 0,100 3 0 741174580
CHOOSE ace_23 5382687379878281013 0,100 0,1,3 0 1537812055
CHOOSE ace_23 5382687379878281011 0,100 2 1 879289766
CHOOSE ace_23 -6018027439464582180 - 0 0 -1010862029
CHOOSE ace_23 -6018027439464582179 - 0,1 0 1523587077
CHOOSE ace_23 -6018027439464582182 - 0,1,2,3 0 1930978077
CHOOSE ace_23 9223372036854775807 0,0,100,0 - 1 1402130883
CHOOSE ace_23 9223372036854775804 0,0,100,0 3 1 2070194162
CHOOSE ace_23 9223372036854775803 0,0,100,0 0,1,3 2 660863589
CHOOSE ace_23 9223372036854775805 0,0,100,0 2 3 -2105454560
CHOOSE ace_23 -2177342782468422678 100,0,0,0 0 1 999674581
CHOOSE ace_23 -2177342782468422677 100,0,0,0 0,1 3 1148340743
CHOOSE ace_23 -2177342782468422676 100,0,0,0 0,1,2,3 0 -1596273871
CHOOSE ace_23 4868686471917930453 0,100,100,0 - 1 -438309674
CHOOSE ace_23 4868686471917930454 0,100,100,0 3 2 -1371716006
CHOOSE ace_23 4868686471917930449 0,100,100,0 0,1,3 2 -1679576139
CHOOSE ace_23 4868686471917930455 0,100,100,0 2 1 -1242458292
CHOOSE ace_23 -6532028347405268032 50,100,0 0 1 -1141184317
CHOOSE ace_23 -6532028347405268031 50,100,0 0,1 2 -992044627
CHOOSE ace_23 -6532028347405268026 50,100,0 0,1,2,3 0 -812626189
CHOOSE ace_23 514000906981085099 100 - 0 79600482
CHOOSE ace_23 514000906981085096 100 3 0 -1461809864
CHOOSE ace_23 514000906981085103 100 0,1,3 0 -1963386353
CHOOSE ace_23 514000906981085097 100 2 0 413806104
CHOOSE ace_23 7560030161367438230 0,0,0,0 0 3 -1988604604
CHOOSE ace_23 7560030161367438231 0,0,0,0 0,1 2 -657592668
CHOOSE ace_23 7560030161367438224 0,0,0,0 0,1,2,3 0 1703114018
CHOOSE ace_23 -3840684657955760255 0,100 - 0 -401248275
CHOOSE ace_23 -3840684657955760254 0,100 3 1 -273244575
CHOOSE ace_23 -3840684657955760251 0,100 0,1,3 0 1992656962
CHOOSE ace_23 -3840684657955760253 0,100 2 1 -132499849
CHOOSE ace_23 3205344596430592876 - 0 0 1876925998
CHOOSE ace_23 3205344596430592877 - 0,1 0 384861724
CHOOSE ace_23 3205344596430592874 - 0,1,2,3 0 507168004
CHOOSE ace_23 -9223372036854775808 0,0,100,0 - 0 138246747
CHOOSE ace_23 -9223372036854775805 0,0,100,0 3 0 -811847617
CHOOSE ace_23 -9223372036854775804 0,0,100,0 0,1,3 2 -1126855500
CHOOSE ace_23 -9223372036854775806 0,0,100,0 2 1 -666386475
CHOOSE ace_23 2177342782468422677 100,0,0,0 0 1 1330735456
CHOOSE ace_23 2177342782468422676 100,0,0,0 0,1 2 1455208938
CHOOSE ace_23 2177342782468422675 100,0,0,0 0,1,2,3 0 -616278705
CHOOSE ace_23 -4868686471917930454 0,100,100,0 - 1 -717923471
CHOOSE ace_23 -4868686471917930455 0,100,100,0 3 2 -1659325027
CHOOSE ace_23 -4868686471917930450 0,100,100,0 0,1,3 2 -966649770
CHOOSE ace_23 -4868686471917930456 0,100,100,0 2 1 -1524880153
CHOOSE ace_23 6532028347405268031 50,100,0 0 2 -272402636
CHOOSE ace_23 6532028347405268030 50,100,0 0,1 2 -149418362
CHOOSE ace_23 6532028347405268025 50,100,0 0,1,2,3 0 -1393956483
CHOOSE ace_23 -514000906981085100 100 - 0 -548068695
CHOOSE ace_23 -514000906981085097 100 3 0 2071271395
CHOOSE ace_23 -514000906981085104 100 0,1,3 0 -241118831
CHOOSE ace_23 -514000906981085098 100 2 0 -903364349
CHOOSE ace_23 -7560030161367438231 0,0,0,0 0 2 -1677543483
CHOOSE ace_23 -7560030161367438232 0,0,0,0 0,1 2 170877029
CHOOSE ace_23 -7560030161367438225 0,0,0,0 0,1,2,3 0 672861774
CHOOSE ace_23 3840684657955760254 0,100 - 1 -1797397500
CHOOSE ace_23 3840684657955760253 0,100 3 0 -1661136416
CHOOSE ace_23 3840684657955760250 0,100 0,1,3 0 354283566
CHOOSE ace_23 3840684657955760252 0,100 2 1 -1529757298
CHOOSE ace_23 -3205344596430592877 - 0 0 226043218
CHOOSE ace_23 -3205344596430592878 - 0,1 0 1955122564
CHOOSE ace_23 -3205344596430592875 - 0,1,2,3 0 1553074796
CHOOSE ace_23 31337 0,0,100,0 - 3 87738370
CHOOSE ace_23 31338 0,0,100,0 3 1 1016734110
CHOOSE ace_23 31341 0,0,100,0 0,1,3 2 -2003822653
CHOOSE ace_23 31339 0,0,100,0 2 1 891124360
CHOOSE ace_23 -7046029254386383236 100,0,0,0 0 1 -28514381
CHOOSE ace_23 -7046029254386383235 100,0,0,0 0,1 2 -175083607
CHOOSE ace_23 -7046029254386383238 100,0,0,0 0,1,2,3 0 709265643
CHOOSE ace_23 4354685564936815171 0,100,100,0 - 1 -674542374
CHOOSE ace_23 4354685564936815168 0,100,100,0 3 1 263062318
CHOOSE ace_23 4354685564936815175 0,100,100,0 0,1,3 2 -1378038457
CHOOSE ace_23 4354685564936815169 0,100,100,0 2 3 131707748
CHOOSE ace_23 -2691343689449533866 50,100,0 0 2 -37224243
CHOOSE ace_23 -2691343689449533865 50,100,0 0,1 2 -180072197
CHOOSE ace_23 -2691343689449533872 50,100,0 0,1,2,3 0 -148579047
CHOOSE ace_23 8709371129873664573 100 - 0 -1495485030
CHOOSE ace_23 8709371129873664574 100 3 0 -1963150096
CHOOSE ace_23 8709371129873664569 100 0,1,3 0 -1815208339
CHOOSE ace_23 8709371129873664575 100 2 0 -1185856496
CHOOSE ace_23 1663341875487315456 0,0,0,0 0 3 -904121164
CHOOSE ace_23 1663341875487315457 0,0,0,0 0,1 2 -655965356
CHOOSE ace_23 1663341875487315462 0,0,0,0 0,1,2,3 0 -848280910
CHOOSE ace_23 -5382687378899037673 0,100 - 1 1475439011
CHOOSE ace_23 -5382687378899037676 0,100 3 0 1343245127
CHOOSE ace_23 -5382687378899037677 0,100 0,1,3 0 -1603240950
CHOOSE ace_23 -5382687378899037675 0,100 2 1 1208792089
CHOOSE ace_23 6018027440424165114 - 0 0 1995807278
CHOOSE ace_23 6018027440424165115 - 0,1 0 537246240
CHOOSE ace_23 6018027440424165116 - 0,1,2,3 0 -1470595320
CHOOSE buddy_23 0 0,0,100,0 - 1 -649160781
CHOOSE buddy_23 3 0,0,100,0 3 0 -256771609
CHOOSE buddy_23 4 0,0,100,0 0,1,3 2 483757236
CHOOSE buddy_23 2 0,0,100,0 2 0 -382311875
CHOOSE buddy_23 -7046029254386353131 100,0,0,0 0 1 778235912
CHOOSE buddy_23 -7046029254386353132 100,0,0,0 0,1 3 631744338
CHOOSE buddy_23 -7046029254386353133 100,0,0,0 0,1,2,3 0 -1155246353
CHOOSE buddy_23 4354685564936845354 0,100,100,0 - 3 -1541192439
CHOOSE buddy_23 4354685564936845353 0,100,100,0 3 1 -1140722939
CHOOSE buddy_23 4354685564936845358 0,100,100,0 0,1,3 2 375527510
CHOOSE buddy_23 4354685564936845352 0,100,100,0 2 1 -1272020081
CHOOSE buddy_23 -2691343689449507777 50,100,0 0 1 -827469668
CHOOSE buddy_23 -2691343689449507778 50,100,0 0,1 2 -970374866
CHOOSE buddy_23 -2691343689449507783 50,100,0 0,1,2,3 0 -1924535523
CHOOSE buddy_23 8709371129873690708 100 - 0 1062544041
CHOOSE buddy_23 8709371129873690711 100 3 0 460658659
CHOOSE buddy_23 8709371129873690704 100 0,1,3 0 289460337
CHOOSE buddy_23 8709371129873690710 100 2 0 707248387
CHOOSE buddy_23 1663341875487337577 0,0,0,0 0 3 1006811077
CHOOSE buddy_23 1663341875487337576 0,0,0,0 0,1 3 1781489765
CHOOSE buddy_23 1663341875487337583 0,0,0,0 0,1,2,3 0 935005358
CHOOSE buddy_23 -5382687378899015554 0,100 - 0 -1513580180
CHOOSE buddy_23 -5382687378899015555 0,100 3 1 2112582520
CHOOSE buddy_23 -5382687378899015558 0,100 0,1,3 0 620622350
CHOOSE buddy_23 -5382687378899015556 0,100 2 0 1978059750
CHOOSE buddy_23 6018027440424182931 - 0 0 -317119438
CHOOSE buddy_23 6018027440424182930 - 0,1 0 -2077701084
CHOOSE buddy_23 6018027440424182933 - 0,1,2,3 0 1022496012
CHOOSE buddy_23 1700000000123 0,0,100,0 - 3 950665439
CHOOSE buddy_23 1700000000120 0,0,100,0 3 1 814436075
CHOOSE buddy_23 1700000000127 0,0,100,0 0,1,3 2 348414349
CHOOSE buddy_23 1700000000121 0,0,100,0 2 3 681492313
CHOOSE buddy_23 -7046030932889889682 100,0,0,0 0 2 834279636
CHOOSE buddy_23 -7046030932889889681 100,0,0,0 0,1 3 697157702
CHOOSE buddy_23 -7046030932889889688 100,0,0,0 0,1,2,3 0 570740890
CHOOSE buddy_23 4354685041804152913 0,100,100,0 - 2 -339858915
CHOOSE buddy_23 4354685041804152914 0,100,100,0 3 1 -484783135
CHOOSE buddy_23 4354685041804152917 0,100,100,0 0,1,3 2 1762171661
CHOOSE buddy_23 4354685041804152915 0,100,100,0 2 0 -606710637
CHOOSE buddy_23 -2691344259801801660 50,100,0 0 1 299314560
CHOOSE buddy_23 -2691344259801801659 50,100,0 0,1 2 163812906
CHOOSE buddy_23 -2691344259801801662 50,100,0 0,1,2,3 0 -815287062
CHOOSE buddy_23 8709371714889095215 100 - 0 849407856
CHOOSE buddy_23 8709371714889095212 100 3 0 1455487786
CHOOSE buddy_23 8709371714889095211 100 0,1,3 0 -735803874
CHOOSE buddy_23 8709371714889095213 100 2 0 638423498
CHOOSE buddy_23 1663342378923131922 0,0,0,0 0 2 1440217742
CHOOSE buddy_23 1663342378923131923 0,0,0,0 0,1 2 1168806318
CHOOSE buddy_23 1663342378923131924 0,0,0,0 0,1,2,3 0 -577107181
CHOOSE buddy_23 -5382685754451591163 0,100 - 1 737196656
CHOOSE buddy_23 -5382685754451591162 0,100 3 0 1687261348
CHOOSE buddy_23 -5382685754451591167 0,100 0,1,3 0 681489403
CHOOSE buddy_23 -5382685754451591161 0,100 2 1 1543364858
CHOOSE buddy_23 6018029120727551208 - 0 0 -289938929
CHOOSE buddy_23 6018029120727551209 - 0,1 0 1204273633
CHOOSE buddy_23 6018029120727551214 - 0,1,2,3 0 -1609099527
CHOOSE buddy_23 -987654321 0,0,100,0 - 3 2018681017
CHOOSE buddy_23 -987654324 0,0,100,0 3 0 677938306
CHOOSE buddy_23 -987654325 0,0,100,0 0,1,3 2 -1227801630
CHOOSE buddy_23 -987654323 0,0,100,0 2 0 1748492079
CHOOSE buddy_23 7046029255354608474 100,0,0,0 0 1 -513769020
CHOOSE buddy_23 7046029255354608475 100,0,0,0 0,1 2 -370861798
CHOOSE buddy_23 7046029255354608476 100,0,0,0 0,1,2,3 0 -151344836
CHOOSE buddy_23 -4354685563958890651 0,100,100,0 - 2 1130511267
CHOOSE buddy_23 -4354685563958890650 0,100,100,0 3 1 729765255
CHOOSE buddy_23 -4354685563958890655 0,100,100,0 0,1,3 2 -816221640
CHOOSE buddy_23 -4354685563958890649 0,100,100,0 2 1 862717469
CHOOSE buddy_23 2691343690370048880 50,100,0 0 2 1634523120
CHOOSE buddy_23 2691343690370048881 50,100,0 0,1 2 1781016702
CHOOSE buddy_23 2691343690370048886 50,100,0 0,1,2,3 0 -999344884
CHOOSE buddy_23 -8709371128981199077 100 - 0 -661791267
CHOOSE buddy_23 -8709371128981199080 100 3 0 1953352371
CHOOSE buddy_23 -8709371128981199073 100 0,1,3 0 -384171016
CHOOSE buddy_23 -8709371128981199079 100 2 0 -467506285
CHOOSE buddy_23 -1663341874584880346 0,0,0,0 0 1 -1270019391
CHOOSE buddy_23 -1663341874584880345 0,0,0,0 0,1 2 58174497
CHOOSE buddy_23 -1663341874584880352 0,0,0,0 0,1,2,3 0 312729399
CHOOSE buddy_23 5382687379878281009 0,100 - 1 72089376
CHOOSE buddy_23 5382687379878281010 0,100 3 0 741174580
CHOOSE buddy_23 5382687379878281013 0,100 0,1,3 0 1537812055
CHOOSE buddy_23 5382687379878281011 0,100 2 1 879289766
CHOOSE buddy_23 -6018027439464582180 - 0 0 -1010862029
CHOOSE buddy_23 -6018027439464582179 - 0,1 0 1523587077
CHOOSE buddy_23 -6018027439464582182 - 0,1,2,3 0 1930978077
CHOOSE buddy_23 9223372036854775807 0,0,100,0 - 1 -1299975770
CHOOSE buddy_23 9223372036854775804 0,0,100,0 3 1 2070194162
CHOOSE buddy_23 9223372036854775803 0,0,100,0 0,1,3 2 660863589
CHOOSE buddy_23 9223372036854775805 0,0,100,0 2 3 -2105454560
CHOOSE buddy_23 -2177342782468422678 100,0,0,0 0 1 999674581
CHOOSE buddy_23 -2177342782468422677 100,0,0,0 0,1 3 1148340743
CHOOSE buddy_23 -2177342782468422676 100,0,0,0 0,1,2,3 0 -1596273871
CHOOSE buddy_23 4868686471917930453 0,100,100,0 - 1 -438309674
CHOOSE buddy_23 4868686471917930454 0,100,100,0 3 2 -1371716006
CHOOSE buddy_23 4868686471917930449 0,100,100,0 0,1,3 2 -1679576139
CHOOSE buddy_23 4868686471917930455 0,100,100,0 2 1 -1242458292
CHOOSE buddy_23 -6532028347405268032 50,100,0 0 1 -1141184317
CHOOSE buddy_23 -6532028347405268031 50,100,0 0,1 2 -992044627
CHOOSE buddy_23 -6532028347405268026 50,100,0 0,1,2,3 0 -812626189
CHOOSE buddy_23 514000906981085099 100 - 0 79600482
CHOOSE buddy_23 514000906981085096 100 3 0 -1461809864
CHOOSE buddy_23 514000906981085103 100 0,1,3 0 -1963386353
CHOOSE buddy_23 514000906981085097 100 2 0 413806104
CHOOSE buddy_23 7560030161367438230 0,0,0,0 0 3 -1988604604
CHOOSE buddy_23 7560030161367438231 0,0,0,0 0,1 2 -657592668
CHOOSE buddy_23 7560030161367438224 0,0,0,0 0,1,2,3 0 1703114018
CHOOSE buddy_23 -3840684657955760255 0,100 - 0 -401248275
CHOOSE buddy_23 -3840684657955760254 0,100 3 1 -273244575
CHOOSE buddy_23 -3840684657955760251 0,100 0,1,3 0 1992656962
CHOOSE buddy_23 -3840684657955760253 0,100 2 1 -132499849
CHOOSE buddy_23 3205344596430592876 - 0 0 1876925998
CHOOSE buddy_23 3205344596430592877 - 0,1 0 384861724
CHOOSE buddy_23 3205344596430592874 - 0,1,2,3 0 507168004
CHOOSE buddy_23 -9223372036854775808 0,0,100,0 - 0 138246747
CHOOSE buddy_23 -9223372036854775805 0,0,100,0 3 0 -811847617
CHOOSE buddy_23 -9223372036854775804 0,0,100,0 0,1,3 2 -1126855500
CHOOSE buddy_23 -9223372036854775806 0,0,100,0 2 1 -666386475
CHOOSE buddy_23 2177342782468422677 100,0,0,0 0 1 1330735456
CHOOSE buddy_23 2177342782468422676 100,0,0,0 0,1 2 1455208938
CHOOSE buddy_23 2177342782468422675 100,0,0,0 0,1,2,3 0 -616278705
CHOOSE buddy_23 -4868686471917930454 0,100,100,0 - 1 -717923471
CHOOSE buddy_23 -4868686471917930455 0,100,100,0 3 2 -1659325027
CHOOSE buddy_23 -4868686471917930450 0,100,100,0 0,1,3 2 -966649770
CHOOSE buddy_23 -4868686471917930456 0,100,100,0 2 1 -1524880153
CHOOSE buddy_23 6532028347405268031 50,100,0 0 2 -272402636
CHOOSE buddy_23 6532028347405268030 50,100,0 0,1 2 -149418362
CHOOSE buddy_23 6532028347405268025 50,100,0 0,1,2,3 0 -1393956483
CHOOSE buddy_23 -514000906981085100 100 - 0 -548068695
CHOOSE buddy_23 -514000906981085097 100 3 0 2071271395
CHOOSE buddy_23 -514000906981085104 100 0,1,3 0 -241118831
CHOOSE buddy_23 -514000906981085098 100 2 0 -903364349
CHOOSE buddy_23 -7560030161367438231 0,0,0,0 0 2 -1677543483
CHOOSE buddy_23 -7560030161367438232 0,0,0,0 0,1 2 170877029
CHOOSE buddy_23 -7560030161367438225 0,0,0,0 0,1,2,3 0 672861774
CHOOSE buddy_23 3840684657955760254 0,100 - 1 -1797397500
CHOOSE buddy_23 3840684657955760253 0,100 3 0 -1661136416
CHOOSE buddy_23 3840684657955760250 0,100 0,1,3 0 354283566
CHOOSE buddy_23 3840684657955760252 0,100 2 1 -1529757298
CHOOSE buddy_23 -3205344596430592877 - 0 0 226043218
CHOOSE buddy_23 -3205344596430592878 - 0,1 0 1955122564
CHOOSE buddy_23 -3205344596430592875 - 0,1,2,3 0 1553074796
CHOOSE buddy_23 31337 0,0,100,0 - 3 87738370
CHOOSE buddy_23 31338 0,0,100,0 3 1 1016734110
CHOOSE buddy_23 31341 0,0,100,0 0,1,3 2 -2003822653
CHOOSE buddy_23 31339 0,0,100,0 2 1 891124360
CHOOSE buddy_23 -7046029254386383236 100,0,0,0 0 1 -28514381
CHOOSE buddy_23 -7046029254386383235 100,0,0,0 0,1 2 -175083607
CHOOSE buddy_23 -7046029254386383238 100,0,0,0 0,1,2,3 0 709265643
CHOOSE buddy_23 4354685564936815171 0,100,100,0 - 1 -674542374
CHOOSE buddy_23 4354685564936815168 0,100,100,0 3 1 263062318
CHOOSE buddy_23 4354685564936815175 0,100,100,0 0,1,3 2 -1378038457
CHOOSE buddy_23 4354685564936815169 0,100,100,0 2 3 131707748
CHOOSE buddy_23 -2691343689449533866 50,100,0 0 2 -37224243
CHOOSE buddy_23 -2691343689449533865 50,100,0 0,1 2 -180072197
CHOOSE buddy_23 -2691343689449533872 50,100,0 0,1,2,3 0 -148579047
CHOOSE buddy_23 8709371129873664573 100 - 0 -1495485030
CHOOSE buddy_23 8709371129873664574 100 3 0 -1963150096
CHOOSE buddy_23 8709371129873664569 100 0,1,3 0 -1815208339
CHOOSE buddy_23 8709371129873664575 100 2 0 -1185856496
CHOOSE buddy_23 1663341875487315456 0,0,0,0 0 3 -904121164
CHOOSE buddy_23 1663341875487315457 0,0,0,0 0,1 2 -655965356
CHOOSE buddy_23 1663341875487315462 0,0,0,0 0,1,2,3 0 -848280910
CHOOSE buddy_23 -5382687378899037673 0,100 - 1 1475439011
CHOOSE buddy_23 -5382687378899037676 0,100 3 0 1343245127
CHOOSE buddy_23 -5382687378899037677 0,100 0,1,3 0 -1603240950
CHOOSE buddy_23 -5382687378899037675 0,100 2 1 1208792089
CHOOSE buddy_23 6018027440424165114 - 0 0 1995807278
CHOOSE buddy_23 6018027440424165115 - 0,1 0 537246240
CHOOSE buddy_23 6018027440424165116 - 0,1,2,3 0 -1470595320
"""

    private static let delayData = """
DELAY bob 0 2354 1670,1810,1950,1950,1950 8301
DELAY bob 1 2305 1885,2025,2165,2165,2165 8983
DELAY bob 2 1982 1872,2012,2152,2152,2152 8858
DELAY bob 3 2368 1553,1693,1833,1833,1833 9246
DELAY bob 4 2122 1550,1690,1830,1830,1830 7808
DELAY bob 5 2101 1959,2099,2239,2239,2239 8423
DELAY bob 1700000000123 2686 1675,1815,1955,1955,1955 7974
DELAY bob 1700000000124 2382 1871,2011,2151,2151,2151 8885
DELAY bob 1700000000125 2711 1593,1733,1873,1873,1873 9015
DELAY bob 1700000000126 2090 1657,1797,1937,1937,1937 8775
DELAY bob 1700000000127 2497 1729,1869,2009,2009,2009 9327
DELAY bob 1700000000128 2020 1929,2069,2209,2209,2209 9045
DELAY bob -987654321 2326 1581,1721,1861,1861,1861 8276
DELAY bob -987654320 2163 1933,2073,2213,2213,2213 7789
DELAY bob -987654319 2052 1574,1714,1854,1854,1854 8086
DELAY bob -987654318 1985 1839,1979,2119,2119,2119 8010
DELAY bob -987654317 2449 1673,1813,1953,1953,1953 7804
DELAY bob -987654316 2778 1785,1925,2065,2065,2065 9237
DELAY bob 9223372036854775807 2044 1616,1756,1896,1896,1896 8762
DELAY bob -9223372036854775808 2344 1811,1951,2091,2091,2091 9085
DELAY bob -9223372036854775807 2122 1779,1919,2059,2059,2059 8773
DELAY bob -9223372036854775806 2534 1705,1845,1985,1985,1985 8283
DELAY bob -9223372036854775805 2627 1690,1830,1970,1970,1970 7641
DELAY bob -9223372036854775804 2128 1780,1920,2060,2060,2060 7634
DELAY bob -9223372036854775808 2344 1811,1951,2091,2091,2091 9085
DELAY bob -9223372036854775807 2122 1779,1919,2059,2059,2059 8773
DELAY bob -9223372036854775806 2534 1705,1845,1985,1985,1985 8283
DELAY bob -9223372036854775805 2627 1690,1830,1970,1970,1970 7641
DELAY bob -9223372036854775804 2128 1780,1920,2060,2060,2060 7634
DELAY bob -9223372036854775803 2228 1967,2107,2247,2247,2247 8845
DELAY bob 31337 2419 1790,1930,2070,2070,2070 8262
DELAY bob 31338 2656 1580,1720,1860,1860,1860 8713
DELAY bob 31339 2115 1906,2046,2186,2186,2186 8777
DELAY bob 31340 2365 1844,1984,2124,2124,2124 8028
DELAY bob 31341 2128 1800,1940,2080,2080,2080 9203
DELAY bob 31342 2750 1954,2094,2234,2234,2234 9112
DELAY woman_dark 0 2197 1590,1730,1870,1870,1870 7948
DELAY woman_dark 1 2148 1805,1945,2085,2085,2085 8630
DELAY woman_dark 2 1825 1792,1932,2072,2072,2072 8505
DELAY woman_dark 3 2211 1473,1613,1753,1753,1753 8893
DELAY woman_dark 4 1965 1470,1610,1750,1750,1750 7455
DELAY woman_dark 5 1944 1879,2019,2159,2159,2159 8070
DELAY woman_dark 1700000000123 2529 1595,1735,1875,1875,1875 7621
DELAY woman_dark 1700000000124 2225 1791,1931,2071,2071,2071 8532
DELAY woman_dark 1700000000125 2554 1513,1653,1793,1793,1793 8662
DELAY woman_dark 1700000000126 1933 1577,1717,1857,1857,1857 8422
DELAY woman_dark 1700000000127 2340 1649,1789,1929,1929,1929 8974
DELAY woman_dark 1700000000128 1863 1849,1989,2129,2129,2129 8692
DELAY woman_dark -987654321 2169 1501,1641,1781,1781,1781 7923
DELAY woman_dark -987654320 2006 1853,1993,2133,2133,2133 7436
DELAY woman_dark -987654319 1895 1494,1634,1774,1774,1774 7733
DELAY woman_dark -987654318 1828 1759,1899,2039,2039,2039 7657
DELAY woman_dark -987654317 2292 1593,1733,1873,1873,1873 7451
DELAY woman_dark -987654316 2621 1705,1845,1985,1985,1985 8884
DELAY woman_dark 9223372036854775807 1887 1536,1676,1816,1816,1816 8409
DELAY woman_dark -9223372036854775808 2187 1731,1871,2011,2011,2011 8732
DELAY woman_dark -9223372036854775807 1965 1699,1839,1979,1979,1979 8420
DELAY woman_dark -9223372036854775806 2377 1625,1765,1905,1905,1905 7930
DELAY woman_dark -9223372036854775805 2470 1610,1750,1890,1890,1890 7288
DELAY woman_dark -9223372036854775804 1971 1700,1840,1980,1980,1980 7281
DELAY woman_dark -9223372036854775808 2187 1731,1871,2011,2011,2011 8732
DELAY woman_dark -9223372036854775807 1965 1699,1839,1979,1979,1979 8420
DELAY woman_dark -9223372036854775806 2377 1625,1765,1905,1905,1905 7930
DELAY woman_dark -9223372036854775805 2470 1610,1750,1890,1890,1890 7288
DELAY woman_dark -9223372036854775804 1971 1700,1840,1980,1980,1980 7281
DELAY woman_dark -9223372036854775803 2071 1887,2027,2167,2167,2167 8492
DELAY woman_dark 31337 2262 1710,1850,1990,1990,1990 7909
DELAY woman_dark 31338 2499 1500,1640,1780,1780,1780 8360
DELAY woman_dark 31339 1958 1826,1966,2106,2106,2106 8424
DELAY woman_dark 31340 2208 1764,1904,2044,2044,2044 7675
DELAY woman_dark 31341 1971 1720,1860,2000,2000,2000 8850
DELAY woman_dark 31342 2593 1874,2014,2154,2154,2154 8759
DELAY rooza 0 1220 1094,1234,1374,1374,1374 6826
DELAY rooza 1 1171 1309,1449,1589,1589,1589 7508
DELAY rooza 2 848 1296,1436,1576,1576,1576 7383
DELAY rooza 3 1234 977,1117,1257,1257,1257 7771
DELAY rooza 4 988 974,1114,1254,1254,1254 6333
DELAY rooza 5 967 1383,1523,1663,1663,1663 6948
DELAY rooza 1700000000123 1552 1099,1239,1379,1379,1379 6499
DELAY rooza 1700000000124 1248 1295,1435,1575,1575,1575 7410
DELAY rooza 1700000000125 1577 1017,1157,1297,1297,1297 7540
DELAY rooza 1700000000126 956 1081,1221,1361,1361,1361 7300
DELAY rooza 1700000000127 1363 1153,1293,1433,1433,1433 7852
DELAY rooza 1700000000128 886 1353,1493,1633,1633,1633 7570
DELAY rooza -987654321 1192 1005,1145,1285,1285,1285 6801
DELAY rooza -987654320 1029 1357,1497,1637,1637,1637 6314
DELAY rooza -987654319 918 998,1138,1278,1278,1278 6611
DELAY rooza -987654318 851 1263,1403,1543,1543,1543 6535
DELAY rooza -987654317 1315 1097,1237,1377,1377,1377 6329
DELAY rooza -987654316 1644 1209,1349,1489,1489,1489 7762
DELAY rooza 9223372036854775807 910 1040,1180,1320,1320,1320 7287
DELAY rooza -9223372036854775808 1210 1235,1375,1515,1515,1515 7610
DELAY rooza -9223372036854775807 988 1203,1343,1483,1483,1483 7298
DELAY rooza -9223372036854775806 1400 1129,1269,1409,1409,1409 6808
DELAY rooza -9223372036854775805 1493 1114,1254,1394,1394,1394 6166
DELAY rooza -9223372036854775804 994 1204,1344,1484,1484,1484 6159
DELAY rooza -9223372036854775808 1210 1235,1375,1515,1515,1515 7610
DELAY rooza -9223372036854775807 988 1203,1343,1483,1483,1483 7298
DELAY rooza -9223372036854775806 1400 1129,1269,1409,1409,1409 6808
DELAY rooza -9223372036854775805 1493 1114,1254,1394,1394,1394 6166
DELAY rooza -9223372036854775804 994 1204,1344,1484,1484,1484 6159
DELAY rooza -9223372036854775803 1094 1391,1531,1671,1671,1671 7370
DELAY rooza 31337 1285 1214,1354,1494,1494,1494 6787
DELAY rooza 31338 1522 1004,1144,1284,1284,1284 7238
DELAY rooza 31339 981 1330,1470,1610,1610,1610 7302
DELAY rooza 31340 1231 1268,1408,1548,1548,1548 6553
DELAY rooza 31341 994 1224,1364,1504,1504,1504 7728
DELAY rooza 31342 1616 1378,1518,1658,1658,1658 7637
DELAY nova 0 1409 1190,1330,1470,1470,1470 6417
DELAY nova 1 1360 1405,1545,1685,1685,1685 7099
DELAY nova 2 1037 1392,1532,1672,1672,1672 6974
DELAY nova 3 1423 1073,1213,1353,1353,1353 7362
DELAY nova 4 1177 1070,1210,1350,1350,1350 5924
DELAY nova 5 1156 1479,1619,1759,1759,1759 6539
DELAY nova 1700000000123 1741 1195,1335,1475,1475,1475 6090
DELAY nova 1700000000124 1437 1391,1531,1671,1671,1671 7001
DELAY nova 1700000000125 1766 1113,1253,1393,1393,1393 7131
DELAY nova 1700000000126 1145 1177,1317,1457,1457,1457 6891
DELAY nova 1700000000127 1552 1249,1389,1529,1529,1529 7443
DELAY nova 1700000000128 1075 1449,1589,1729,1729,1729 7161
DELAY nova -987654321 1381 1101,1241,1381,1381,1381 6392
DELAY nova -987654320 1218 1453,1593,1733,1733,1733 5905
DELAY nova -987654319 1107 1094,1234,1374,1374,1374 6202
DELAY nova -987654318 1040 1359,1499,1639,1639,1639 6126
DELAY nova -987654317 1504 1193,1333,1473,1473,1473 5920
DELAY nova -987654316 1833 1305,1445,1585,1585,1585 7353
DELAY nova 9223372036854775807 1099 1136,1276,1416,1416,1416 6878
DELAY nova -9223372036854775808 1399 1331,1471,1611,1611,1611 7201
DELAY nova -9223372036854775807 1177 1299,1439,1579,1579,1579 6889
DELAY nova -9223372036854775806 1589 1225,1365,1505,1505,1505 6399
DELAY nova -9223372036854775805 1682 1210,1350,1490,1490,1490 5757
DELAY nova -9223372036854775804 1183 1300,1440,1580,1580,1580 5750
DELAY nova -9223372036854775808 1399 1331,1471,1611,1611,1611 7201
DELAY nova -9223372036854775807 1177 1299,1439,1579,1579,1579 6889
DELAY nova -9223372036854775806 1589 1225,1365,1505,1505,1505 6399
DELAY nova -9223372036854775805 1682 1210,1350,1490,1490,1490 5757
DELAY nova -9223372036854775804 1183 1300,1440,1580,1580,1580 5750
DELAY nova -9223372036854775803 1283 1487,1627,1767,1767,1767 6961
DELAY nova 31337 1474 1310,1450,1590,1590,1590 6378
DELAY nova 31338 1711 1100,1240,1380,1380,1380 6829
DELAY nova 31339 1170 1426,1566,1706,1706,1706 6893
DELAY nova 31340 1420 1364,1504,1644,1644,1644 6144
DELAY nova 31341 1183 1320,1460,1600,1600,1600 7319
DELAY nova 31342 1805 1474,1614,1754,1754,1754 7228
DELAY unicorn_32 0 3110 2054,2194,2334,2334,2334 9189
DELAY unicorn_32 1 3061 2269,2409,2549,2549,2549 9871
DELAY unicorn_32 2 2738 2256,2396,2536,2536,2536 9746
DELAY unicorn_32 3 3124 1937,2077,2217,2217,2217 10134
DELAY unicorn_32 4 2878 1934,2074,2214,2214,2214 8696
DELAY unicorn_32 5 2857 2343,2483,2623,2623,2623 9311
DELAY unicorn_32 1700000000123 3442 2059,2199,2339,2339,2339 8862
DELAY unicorn_32 1700000000124 3138 2255,2395,2535,2535,2535 9773
DELAY unicorn_32 1700000000125 3467 1977,2117,2257,2257,2257 9903
DELAY unicorn_32 1700000000126 2846 2041,2181,2321,2321,2321 9663
DELAY unicorn_32 1700000000127 3253 2113,2253,2393,2393,2393 10215
DELAY unicorn_32 1700000000128 2776 2313,2453,2593,2593,2593 9933
DELAY unicorn_32 -987654321 3082 1965,2105,2245,2245,2245 9164
DELAY unicorn_32 -987654320 2919 2317,2457,2597,2597,2597 8677
DELAY unicorn_32 -987654319 2808 1958,2098,2238,2238,2238 8974
DELAY unicorn_32 -987654318 2741 2223,2363,2503,2503,2503 8898
DELAY unicorn_32 -987654317 3205 2057,2197,2337,2337,2337 8692
DELAY unicorn_32 -987654316 3534 2169,2309,2449,2449,2449 10125
DELAY unicorn_32 9223372036854775807 2800 2000,2140,2280,2280,2280 9650
DELAY unicorn_32 -9223372036854775808 3100 2195,2335,2475,2475,2475 9973
DELAY unicorn_32 -9223372036854775807 2878 2163,2303,2443,2443,2443 9661
DELAY unicorn_32 -9223372036854775806 3290 2089,2229,2369,2369,2369 9171
DELAY unicorn_32 -9223372036854775805 3383 2074,2214,2354,2354,2354 8529
DELAY unicorn_32 -9223372036854775804 2884 2164,2304,2444,2444,2444 8522
DELAY unicorn_32 -9223372036854775808 3100 2195,2335,2475,2475,2475 9973
DELAY unicorn_32 -9223372036854775807 2878 2163,2303,2443,2443,2443 9661
DELAY unicorn_32 -9223372036854775806 3290 2089,2229,2369,2369,2369 9171
DELAY unicorn_32 -9223372036854775805 3383 2074,2214,2354,2354,2354 8529
DELAY unicorn_32 -9223372036854775804 2884 2164,2304,2444,2444,2444 8522
DELAY unicorn_32 -9223372036854775803 2984 2351,2491,2631,2631,2631 9733
DELAY unicorn_32 31337 3175 2174,2314,2454,2454,2454 9150
DELAY unicorn_32 31338 3412 1964,2104,2244,2244,2244 9601
DELAY unicorn_32 31339 2871 2290,2430,2570,2570,2570 9665
DELAY unicorn_32 31340 3121 2228,2368,2508,2508,2508 8916
DELAY unicorn_32 31341 2884 2184,2324,2464,2464,2464 10091
DELAY unicorn_32 31342 3506 2338,2478,2618,2618,2618 10000
DELAY coach_67 0 2701 1846,1986,2126,2126,2126 8660
DELAY coach_67 1 2652 2061,2201,2341,2341,2341 9342
DELAY coach_67 2 2329 2048,2188,2328,2328,2328 9217
DELAY coach_67 3 2715 1729,1869,2009,2009,2009 9605
DELAY coach_67 4 2469 1726,1866,2006,2006,2006 8167
DELAY coach_67 5 2448 2135,2275,2415,2415,2415 8782
DELAY coach_67 1700000000123 3033 1851,1991,2131,2131,2131 8333
DELAY coach_67 1700000000124 2729 2047,2187,2327,2327,2327 9244
DELAY coach_67 1700000000125 3058 1769,1909,2049,2049,2049 9374
DELAY coach_67 1700000000126 2437 1833,1973,2113,2113,2113 9134
DELAY coach_67 1700000000127 2844 1905,2045,2185,2185,2185 9686
DELAY coach_67 1700000000128 2367 2105,2245,2385,2385,2385 9404
DELAY coach_67 -987654321 2673 1757,1897,2037,2037,2037 8635
DELAY coach_67 -987654320 2510 2109,2249,2389,2389,2389 8148
DELAY coach_67 -987654319 2399 1750,1890,2030,2030,2030 8445
DELAY coach_67 -987654318 2332 2015,2155,2295,2295,2295 8369
DELAY coach_67 -987654317 2796 1849,1989,2129,2129,2129 8163
DELAY coach_67 -987654316 3125 1961,2101,2241,2241,2241 9596
DELAY coach_67 9223372036854775807 2391 1792,1932,2072,2072,2072 9121
DELAY coach_67 -9223372036854775808 2691 1987,2127,2267,2267,2267 9444
DELAY coach_67 -9223372036854775807 2469 1955,2095,2235,2235,2235 9132
DELAY coach_67 -9223372036854775806 2881 1881,2021,2161,2161,2161 8642
DELAY coach_67 -9223372036854775805 2974 1866,2006,2146,2146,2146 8000
DELAY coach_67 -9223372036854775804 2475 1956,2096,2236,2236,2236 7993
DELAY coach_67 -9223372036854775808 2691 1987,2127,2267,2267,2267 9444
DELAY coach_67 -9223372036854775807 2469 1955,2095,2235,2235,2235 9132
DELAY coach_67 -9223372036854775806 2881 1881,2021,2161,2161,2161 8642
DELAY coach_67 -9223372036854775805 2974 1866,2006,2146,2146,2146 8000
DELAY coach_67 -9223372036854775804 2475 1956,2096,2236,2236,2236 7993
DELAY coach_67 -9223372036854775803 2575 2143,2283,2423,2423,2423 9204
DELAY coach_67 31337 2766 1966,2106,2246,2246,2246 8621
DELAY coach_67 31338 3003 1756,1896,2036,2036,2036 9072
DELAY coach_67 31339 2462 2082,2222,2362,2362,2362 9136
DELAY coach_67 31340 2712 2020,2160,2300,2300,2300 8387
DELAY coach_67 31341 2475 1976,2116,2256,2256,2256 9562
DELAY coach_67 31342 3097 2130,2270,2410,2410,2410 9471
DELAY zephyr 0 1472 1222,1362,1502,1502,1502 6893
DELAY zephyr 1 1423 1437,1577,1717,1717,1717 7575
DELAY zephyr 2 1100 1424,1564,1704,1704,1704 7450
DELAY zephyr 3 1486 1105,1245,1385,1385,1385 7838
DELAY zephyr 4 1240 1102,1242,1382,1382,1382 6400
DELAY zephyr 5 1219 1511,1651,1791,1791,1791 7015
DELAY zephyr 1700000000123 1804 1227,1367,1507,1507,1507 6566
DELAY zephyr 1700000000124 1500 1423,1563,1703,1703,1703 7477
DELAY zephyr 1700000000125 1829 1145,1285,1425,1425,1425 7607
DELAY zephyr 1700000000126 1208 1209,1349,1489,1489,1489 7367
DELAY zephyr 1700000000127 1615 1281,1421,1561,1561,1561 7919
DELAY zephyr 1700000000128 1138 1481,1621,1761,1761,1761 7637
DELAY zephyr -987654321 1444 1133,1273,1413,1413,1413 6868
DELAY zephyr -987654320 1281 1485,1625,1765,1765,1765 6381
DELAY zephyr -987654319 1170 1126,1266,1406,1406,1406 6678
DELAY zephyr -987654318 1103 1391,1531,1671,1671,1671 6602
DELAY zephyr -987654317 1567 1225,1365,1505,1505,1505 6396
DELAY zephyr -987654316 1896 1337,1477,1617,1617,1617 7829
DELAY zephyr 9223372036854775807 1162 1168,1308,1448,1448,1448 7354
DELAY zephyr -9223372036854775808 1462 1363,1503,1643,1643,1643 7677
DELAY zephyr -9223372036854775807 1240 1331,1471,1611,1611,1611 7365
DELAY zephyr -9223372036854775806 1652 1257,1397,1537,1537,1537 6875
DELAY zephyr -9223372036854775805 1745 1242,1382,1522,1522,1522 6233
DELAY zephyr -9223372036854775804 1246 1332,1472,1612,1612,1612 6226
DELAY zephyr -9223372036854775808 1462 1363,1503,1643,1643,1643 7677
DELAY zephyr -9223372036854775807 1240 1331,1471,1611,1611,1611 7365
DELAY zephyr -9223372036854775806 1652 1257,1397,1537,1537,1537 6875
DELAY zephyr -9223372036854775805 1745 1242,1382,1522,1522,1522 6233
DELAY zephyr -9223372036854775804 1246 1332,1472,1612,1612,1612 6226
DELAY zephyr -9223372036854775803 1346 1519,1659,1799,1799,1799 7437
DELAY zephyr 31337 1537 1342,1482,1622,1622,1622 6854
DELAY zephyr 31338 1774 1132,1272,1412,1412,1412 7305
DELAY zephyr 31339 1233 1458,1598,1738,1738,1738 7369
DELAY zephyr 31340 1483 1396,1536,1676,1676,1676 6620
DELAY zephyr 31341 1246 1352,1492,1632,1632,1632 7795
DELAY zephyr 31342 1868 1506,1646,1786,1786,1786 7704
DELAY kyra 0 1472 1222,1362,1502,1502,1502 6893
DELAY kyra 1 1423 1437,1577,1717,1717,1717 7575
DELAY kyra 2 1100 1424,1564,1704,1704,1704 7450
DELAY kyra 3 1486 1105,1245,1385,1385,1385 7838
DELAY kyra 4 1240 1102,1242,1382,1382,1382 6400
DELAY kyra 5 1219 1511,1651,1791,1791,1791 7015
DELAY kyra 1700000000123 1804 1227,1367,1507,1507,1507 6566
DELAY kyra 1700000000124 1500 1423,1563,1703,1703,1703 7477
DELAY kyra 1700000000125 1829 1145,1285,1425,1425,1425 7607
DELAY kyra 1700000000126 1208 1209,1349,1489,1489,1489 7367
DELAY kyra 1700000000127 1615 1281,1421,1561,1561,1561 7919
DELAY kyra 1700000000128 1138 1481,1621,1761,1761,1761 7637
DELAY kyra -987654321 1444 1133,1273,1413,1413,1413 6868
DELAY kyra -987654320 1281 1485,1625,1765,1765,1765 6381
DELAY kyra -987654319 1170 1126,1266,1406,1406,1406 6678
DELAY kyra -987654318 1103 1391,1531,1671,1671,1671 6602
DELAY kyra -987654317 1567 1225,1365,1505,1505,1505 6396
DELAY kyra -987654316 1896 1337,1477,1617,1617,1617 7829
DELAY kyra 9223372036854775807 1162 1168,1308,1448,1448,1448 7354
DELAY kyra -9223372036854775808 1462 1363,1503,1643,1643,1643 7677
DELAY kyra -9223372036854775807 1240 1331,1471,1611,1611,1611 7365
DELAY kyra -9223372036854775806 1652 1257,1397,1537,1537,1537 6875
DELAY kyra -9223372036854775805 1745 1242,1382,1522,1522,1522 6233
DELAY kyra -9223372036854775804 1246 1332,1472,1612,1612,1612 6226
DELAY kyra -9223372036854775808 1462 1363,1503,1643,1643,1643 7677
DELAY kyra -9223372036854775807 1240 1331,1471,1611,1611,1611 7365
DELAY kyra -9223372036854775806 1652 1257,1397,1537,1537,1537 6875
DELAY kyra -9223372036854775805 1745 1242,1382,1522,1522,1522 6233
DELAY kyra -9223372036854775804 1246 1332,1472,1612,1612,1612 6226
DELAY kyra -9223372036854775803 1346 1519,1659,1799,1799,1799 7437
DELAY kyra 31337 1537 1342,1482,1622,1622,1622 6854
DELAY kyra 31338 1774 1132,1272,1412,1412,1412 7305
DELAY kyra 31339 1233 1458,1598,1738,1738,1738 7369
DELAY kyra 31340 1483 1396,1536,1676,1676,1676 6620
DELAY kyra 31341 1246 1352,1492,1632,1632,1632 7795
DELAY kyra 31342 1868 1506,1646,1786,1786,1786 7704
DELAY kyra_original 0 1472 1222,1362,1502,1502,1502 6893
DELAY kyra_original 1 1423 1437,1577,1717,1717,1717 7575
DELAY kyra_original 2 1100 1424,1564,1704,1704,1704 7450
DELAY kyra_original 3 1486 1105,1245,1385,1385,1385 7838
DELAY kyra_original 4 1240 1102,1242,1382,1382,1382 6400
DELAY kyra_original 5 1219 1511,1651,1791,1791,1791 7015
DELAY kyra_original 1700000000123 1804 1227,1367,1507,1507,1507 6566
DELAY kyra_original 1700000000124 1500 1423,1563,1703,1703,1703 7477
DELAY kyra_original 1700000000125 1829 1145,1285,1425,1425,1425 7607
DELAY kyra_original 1700000000126 1208 1209,1349,1489,1489,1489 7367
DELAY kyra_original 1700000000127 1615 1281,1421,1561,1561,1561 7919
DELAY kyra_original 1700000000128 1138 1481,1621,1761,1761,1761 7637
DELAY kyra_original -987654321 1444 1133,1273,1413,1413,1413 6868
DELAY kyra_original -987654320 1281 1485,1625,1765,1765,1765 6381
DELAY kyra_original -987654319 1170 1126,1266,1406,1406,1406 6678
DELAY kyra_original -987654318 1103 1391,1531,1671,1671,1671 6602
DELAY kyra_original -987654317 1567 1225,1365,1505,1505,1505 6396
DELAY kyra_original -987654316 1896 1337,1477,1617,1617,1617 7829
DELAY kyra_original 9223372036854775807 1162 1168,1308,1448,1448,1448 7354
DELAY kyra_original -9223372036854775808 1462 1363,1503,1643,1643,1643 7677
DELAY kyra_original -9223372036854775807 1240 1331,1471,1611,1611,1611 7365
DELAY kyra_original -9223372036854775806 1652 1257,1397,1537,1537,1537 6875
DELAY kyra_original -9223372036854775805 1745 1242,1382,1522,1522,1522 6233
DELAY kyra_original -9223372036854775804 1246 1332,1472,1612,1612,1612 6226
DELAY kyra_original -9223372036854775808 1462 1363,1503,1643,1643,1643 7677
DELAY kyra_original -9223372036854775807 1240 1331,1471,1611,1611,1611 7365
DELAY kyra_original -9223372036854775806 1652 1257,1397,1537,1537,1537 6875
DELAY kyra_original -9223372036854775805 1745 1242,1382,1522,1522,1522 6233
DELAY kyra_original -9223372036854775804 1246 1332,1472,1612,1612,1612 6226
DELAY kyra_original -9223372036854775803 1346 1519,1659,1799,1799,1799 7437
DELAY kyra_original 31337 1537 1342,1482,1622,1622,1622 6854
DELAY kyra_original 31338 1774 1132,1272,1412,1412,1412 7305
DELAY kyra_original 31339 1233 1458,1598,1738,1738,1738 7369
DELAY kyra_original 31340 1483 1396,1536,1676,1676,1676 6620
DELAY kyra_original 31341 1246 1352,1492,1632,1632,1632 7795
DELAY kyra_original 31342 1868 1506,1646,1786,1786,1786 7704
DELAY flare 0 1598 1286,1426,1566,1566,1566 7197
DELAY flare 1 1549 1501,1641,1781,1781,1781 7879
DELAY flare 2 1226 1488,1628,1768,1768,1768 7754
DELAY flare 3 1612 1169,1309,1449,1449,1449 8142
DELAY flare 4 1366 1166,1306,1446,1446,1446 6704
DELAY flare 5 1345 1575,1715,1855,1855,1855 7319
DELAY flare 1700000000123 1930 1291,1431,1571,1571,1571 6870
DELAY flare 1700000000124 1626 1487,1627,1767,1767,1767 7781
DELAY flare 1700000000125 1955 1209,1349,1489,1489,1489 7911
DELAY flare 1700000000126 1334 1273,1413,1553,1553,1553 7671
DELAY flare 1700000000127 1741 1345,1485,1625,1625,1625 8223
DELAY flare 1700000000128 1264 1545,1685,1825,1825,1825 7941
DELAY flare -987654321 1570 1197,1337,1477,1477,1477 7172
DELAY flare -987654320 1407 1549,1689,1829,1829,1829 6685
DELAY flare -987654319 1296 1190,1330,1470,1470,1470 6982
DELAY flare -987654318 1229 1455,1595,1735,1735,1735 6906
DELAY flare -987654317 1693 1289,1429,1569,1569,1569 6700
DELAY flare -987654316 2022 1401,1541,1681,1681,1681 8133
DELAY flare 9223372036854775807 1288 1232,1372,1512,1512,1512 7658
DELAY flare -9223372036854775808 1588 1427,1567,1707,1707,1707 7981
DELAY flare -9223372036854775807 1366 1395,1535,1675,1675,1675 7669
DELAY flare -9223372036854775806 1778 1321,1461,1601,1601,1601 7179
DELAY flare -9223372036854775805 1871 1306,1446,1586,1586,1586 6537
DELAY flare -9223372036854775804 1372 1396,1536,1676,1676,1676 6530
DELAY flare -9223372036854775808 1588 1427,1567,1707,1707,1707 7981
DELAY flare -9223372036854775807 1366 1395,1535,1675,1675,1675 7669
DELAY flare -9223372036854775806 1778 1321,1461,1601,1601,1601 7179
DELAY flare -9223372036854775805 1871 1306,1446,1586,1586,1586 6537
DELAY flare -9223372036854775804 1372 1396,1536,1676,1676,1676 6530
DELAY flare -9223372036854775803 1472 1583,1723,1863,1863,1863 7741
DELAY flare 31337 1663 1406,1546,1686,1686,1686 7158
DELAY flare 31338 1900 1196,1336,1476,1476,1476 7609
DELAY flare 31339 1359 1522,1662,1802,1802,1802 7673
DELAY flare 31340 1609 1460,1600,1740,1740,1740 6924
DELAY flare 31341 1372 1416,1556,1696,1696,1696 8099
DELAY flare 31342 1994 1570,1710,1850,1850,1850 8008
DELAY ace_23 0 1126 1046,1186,1326,1326,1326 6966
DELAY ace_23 1 1077 1261,1401,1541,1541,1541 7648
DELAY ace_23 2 754 1248,1388,1528,1528,1528 7523
DELAY ace_23 3 1140 929,1069,1209,1209,1209 7911
DELAY ace_23 4 894 926,1066,1206,1206,1206 6473
DELAY ace_23 5 873 1335,1475,1615,1615,1615 7088
DELAY ace_23 1700000000123 1458 1051,1191,1331,1331,1331 6639
DELAY ace_23 1700000000124 1154 1247,1387,1527,1527,1527 7550
DELAY ace_23 1700000000125 1483 969,1109,1249,1249,1249 7680
DELAY ace_23 1700000000126 862 1033,1173,1313,1313,1313 7440
DELAY ace_23 1700000000127 1269 1105,1245,1385,1385,1385 7992
DELAY ace_23 1700000000128 792 1305,1445,1585,1585,1585 7710
DELAY ace_23 -987654321 1098 957,1097,1237,1237,1237 6941
DELAY ace_23 -987654320 935 1309,1449,1589,1589,1589 6454
DELAY ace_23 -987654319 824 950,1090,1230,1230,1230 6751
DELAY ace_23 -987654318 757 1215,1355,1495,1495,1495 6675
DELAY ace_23 -987654317 1221 1049,1189,1329,1329,1329 6469
DELAY ace_23 -987654316 1550 1161,1301,1441,1441,1441 7902
DELAY ace_23 9223372036854775807 816 992,1132,1272,1272,1272 7427
DELAY ace_23 -9223372036854775808 1116 1187,1327,1467,1467,1467 7750
DELAY ace_23 -9223372036854775807 894 1155,1295,1435,1435,1435 7438
DELAY ace_23 -9223372036854775806 1306 1081,1221,1361,1361,1361 6948
DELAY ace_23 -9223372036854775805 1399 1066,1206,1346,1346,1346 6306
DELAY ace_23 -9223372036854775804 900 1156,1296,1436,1436,1436 6299
DELAY ace_23 -9223372036854775808 1116 1187,1327,1467,1467,1467 7750
DELAY ace_23 -9223372036854775807 894 1155,1295,1435,1435,1435 7438
DELAY ace_23 -9223372036854775806 1306 1081,1221,1361,1361,1361 6948
DELAY ace_23 -9223372036854775805 1399 1066,1206,1346,1346,1346 6306
DELAY ace_23 -9223372036854775804 900 1156,1296,1436,1436,1436 6299
DELAY ace_23 -9223372036854775803 1000 1343,1483,1623,1623,1623 7510
DELAY ace_23 31337 1191 1166,1306,1446,1446,1446 6927
DELAY ace_23 31338 1428 956,1096,1236,1236,1236 7378
DELAY ace_23 31339 887 1282,1422,1562,1562,1562 7442
DELAY ace_23 31340 1137 1220,1360,1500,1500,1500 6693
DELAY ace_23 31341 900 1176,1316,1456,1456,1456 7868
DELAY ace_23 31342 1522 1330,1470,1610,1610,1610 7777
DELAY buddy_23 0 1913 1446,1586,1726,1726,1726 8407
DELAY buddy_23 1 1864 1661,1801,1941,1941,1941 9089
DELAY buddy_23 2 1541 1648,1788,1928,1928,1928 8964
DELAY buddy_23 3 1927 1329,1469,1609,1609,1609 9352
DELAY buddy_23 4 1681 1326,1466,1606,1606,1606 7914
DELAY buddy_23 5 1660 1735,1875,2015,2015,2015 8529
DELAY buddy_23 1700000000123 2245 1451,1591,1731,1731,1731 8080
DELAY buddy_23 1700000000124 1941 1647,1787,1927,1927,1927 8991
DELAY buddy_23 1700000000125 2270 1369,1509,1649,1649,1649 9121
DELAY buddy_23 1700000000126 1649 1433,1573,1713,1713,1713 8881
DELAY buddy_23 1700000000127 2056 1505,1645,1785,1785,1785 9433
DELAY buddy_23 1700000000128 1579 1705,1845,1985,1985,1985 9151
DELAY buddy_23 -987654321 1885 1357,1497,1637,1637,1637 8382
DELAY buddy_23 -987654320 1722 1709,1849,1989,1989,1989 7895
DELAY buddy_23 -987654319 1611 1350,1490,1630,1630,1630 8192
DELAY buddy_23 -987654318 1544 1615,1755,1895,1895,1895 8116
DELAY buddy_23 -987654317 2008 1449,1589,1729,1729,1729 7910
DELAY buddy_23 -987654316 2337 1561,1701,1841,1841,1841 9343
DELAY buddy_23 9223372036854775807 1603 1392,1532,1672,1672,1672 8868
DELAY buddy_23 -9223372036854775808 1903 1587,1727,1867,1867,1867 9191
DELAY buddy_23 -9223372036854775807 1681 1555,1695,1835,1835,1835 8879
DELAY buddy_23 -9223372036854775806 2093 1481,1621,1761,1761,1761 8389
DELAY buddy_23 -9223372036854775805 2186 1466,1606,1746,1746,1746 7747
DELAY buddy_23 -9223372036854775804 1687 1556,1696,1836,1836,1836 7740
DELAY buddy_23 -9223372036854775808 1903 1587,1727,1867,1867,1867 9191
DELAY buddy_23 -9223372036854775807 1681 1555,1695,1835,1835,1835 8879
DELAY buddy_23 -9223372036854775806 2093 1481,1621,1761,1761,1761 8389
DELAY buddy_23 -9223372036854775805 2186 1466,1606,1746,1746,1746 7747
DELAY buddy_23 -9223372036854775804 1687 1556,1696,1836,1836,1836 7740
DELAY buddy_23 -9223372036854775803 1787 1743,1883,2023,2023,2023 8951
DELAY buddy_23 31337 1978 1566,1706,1846,1846,1846 8368
DELAY buddy_23 31338 2215 1356,1496,1636,1636,1636 8819
DELAY buddy_23 31339 1674 1682,1822,1962,1962,1962 8883
DELAY buddy_23 31340 1924 1620,1760,1900,1900,1900 8134
DELAY buddy_23 31341 1687 1576,1716,1856,1856,1856 9309
DELAY buddy_23 31342 2309 1730,1870,2010,2010,2010 9218
"""

    private static let raceData = """
RACE bob 0 1 q-1 0,0,100,0 8096 2:2550
RACE bob 0 1 q-1 100,0,0,0 8096 0:2550
RACE bob 0 1 q-1 0,100,100,0 8096 2:2550
RACE bob 0 1 q-1 50,100,0 8096 1:2550
RACE bob 0 1 one_on_one 0,0,100,0 8990 2:2020
RACE bob 0 1 one_on_one 100,0,0,0 8990 0:2020
RACE bob 0 1 one_on_one 0,100,100,0 8990 1:2020
RACE bob 0 1 one_on_one 50,100,0 8990 1:2020
RACE bob 0 1 general_knowledge_easy_017 0,0,100,0 7741 3:2724;2:1881
RACE bob 0 1 general_knowledge_easy_017 100,0,0,0 7741 3:2724;0:1881
RACE bob 0 1 general_knowledge_easy_017 0,100,100,0 7741 0:2724;1:1881
RACE bob 0 1 general_knowledge_easy_017 50,100,0 7741 0:2724;1:1881
RACE bob 0 1 kids_arithmetic_9 0,0,100,0 8471 2:2017
RACE bob 0 1 kids_arithmetic_9 100,0,0,0 8471 0:2017
RACE bob 0 1 kids_arithmetic_9 0,100,100,0 8471 1:2017
RACE bob 0 1 kids_arithmetic_9 50,100,0 8471 1:2017
RACE bob 0 41 q-1 0,0,100,0 7563 2:2096
RACE bob 0 41 q-1 100,0,0,0 7563 0:2096
RACE bob 0 41 q-1 0,100,100,0 7563 1:2096
RACE bob 0 41 q-1 50,100,0 7563 1:2096
RACE bob 0 41 one_on_one 0,0,100,0 8284 2:2531
RACE bob 0 41 one_on_one 100,0,0,0 8284 0:2531
RACE bob 0 41 one_on_one 0,100,100,0 8284 2:2531
RACE bob 0 41 one_on_one 50,100,0 8284 1:2531
RACE bob 0 41 general_knowledge_easy_017 0,0,100,0 8673 1:2238;2:1582
RACE bob 0 41 general_knowledge_easy_017 100,0,0,0 8673 2:2238;0:1582
RACE bob 0 41 general_knowledge_easy_017 0,100,100,0 8673 3:2238;1:1582
RACE bob 0 41 general_knowledge_easy_017 50,100,0 8673 2:2238;1:1582
RACE bob 0 41 kids_arithmetic_9 0,0,100,0 8196 2:2633
RACE bob 0 41 kids_arithmetic_9 100,0,0,0 8196 0:2633
RACE bob 0 41 kids_arithmetic_9 0,100,100,0 8196 1:2633
RACE bob 0 41 kids_arithmetic_9 50,100,0 8196 1:2633
RACE bob 1700000000123 1 q-1 0,0,100,0 9278 3:2024;2:1765
RACE bob 1700000000123 1 q-1 100,0,0,0 9278 3:2024;0:1765
RACE bob 1700000000123 1 q-1 0,100,100,0 9278 0:2024;1:1765
RACE bob 1700000000123 1 q-1 50,100,0 9278 0:2024;1:1765
RACE bob 1700000000123 1 one_on_one 0,0,100,0 8964 2:2789
RACE bob 1700000000123 1 one_on_one 100,0,0,0 8964 0:2789
RACE bob 1700000000123 1 one_on_one 0,100,100,0 8964 2:2789
RACE bob 1700000000123 1 one_on_one 50,100,0 8964 1:2789
RACE bob 1700000000123 1 general_knowledge_easy_017 0,0,100,0 8782 2:2587
RACE bob 1700000000123 1 general_knowledge_easy_017 100,0,0,0 8782 0:2587
RACE bob 1700000000123 1 general_knowledge_easy_017 0,100,100,0 8782 2:2587
RACE bob 1700000000123 1 general_knowledge_easy_017 50,100,0 8782 1:2587
RACE bob 1700000000123 1 kids_arithmetic_9 0,0,100,0 8039 3:2225;2:1658
RACE bob 1700000000123 1 kids_arithmetic_9 100,0,0,0 8039 3:2225;0:1658
RACE bob 1700000000123 1 kids_arithmetic_9 0,100,100,0 8039 0:2225;2:1658
RACE bob 1700000000123 1 kids_arithmetic_9 50,100,0 8039 0:2225;1:1658
RACE bob 1700000000123 41 q-1 0,0,100,0 8152 2:2162
RACE bob 1700000000123 41 q-1 100,0,0,0 8152 0:2162
RACE bob 1700000000123 41 q-1 0,100,100,0 8152 2:2162
RACE bob 1700000000123 41 q-1 50,100,0 8152 1:2162
RACE bob 1700000000123 41 one_on_one 0,0,100,0 8536 2:2421
RACE bob 1700000000123 41 one_on_one 100,0,0,0 8536 0:2421
RACE bob 1700000000123 41 one_on_one 0,100,100,0 8536 1:2421
RACE bob 1700000000123 41 one_on_one 50,100,0 8536 1:2421
RACE bob 1700000000123 41 general_knowledge_easy_017 0,0,100,0 8680 3:2413;2:1851
RACE bob 1700000000123 41 general_knowledge_easy_017 100,0,0,0 8680 3:2413;2:1851;0:1651
RACE bob 1700000000123 41 general_knowledge_easy_017 0,100,100,0 8680 0:2413;3:1851;2:1741
RACE bob 1700000000123 41 general_knowledge_easy_017 50,100,0 8680 0:2413;2:1851;1:1741
RACE bob 1700000000123 41 kids_arithmetic_9 0,0,100,0 8122 2:2376
RACE bob 1700000000123 41 kids_arithmetic_9 100,0,0,0 8122 0:2376
RACE bob 1700000000123 41 kids_arithmetic_9 0,100,100,0 8122 1:2376
RACE bob 1700000000123 41 kids_arithmetic_9 50,100,0 8122 1:2376
RACE bob 9223372036854775807 1 q-1 0,0,100,0 8720 2:2054
RACE bob 9223372036854775807 1 q-1 100,0,0,0 8720 0:2054
RACE bob 9223372036854775807 1 q-1 0,100,100,0 8720 2:2054
RACE bob 9223372036854775807 1 q-1 50,100,0 8720 1:2054
RACE bob 9223372036854775807 1 one_on_one 0,0,100,0 8593 0:2096;1:1963;2:2031
RACE bob 9223372036854775807 1 one_on_one 100,0,0,0 8593 0:2096
RACE bob 9223372036854775807 1 one_on_one 0,100,100,0 8593 0:2096;3:1963;1:1683
RACE bob 9223372036854775807 1 one_on_one 50,100,0 8593 0:2096;2:1963;1:1683
RACE bob 9223372036854775807 1 general_knowledge_easy_017 0,0,100,0 8743 2:2236
RACE bob 9223372036854775807 1 general_knowledge_easy_017 100,0,0,0 8743 0:2236
RACE bob 9223372036854775807 1 general_knowledge_easy_017 0,100,100,0 8743 1:2236
RACE bob 9223372036854775807 1 general_knowledge_easy_017 50,100,0 8743 1:2236
RACE bob 9223372036854775807 1 kids_arithmetic_9 0,0,100,0 7679 2:2279
RACE bob 9223372036854775807 1 kids_arithmetic_9 100,0,0,0 7679 0:2279
RACE bob 9223372036854775807 1 kids_arithmetic_9 0,100,100,0 7679 1:2279
RACE bob 9223372036854775807 1 kids_arithmetic_9 50,100,0 7679 1:2279
RACE bob 9223372036854775807 41 q-1 0,0,100,0 8133 2:2279
RACE bob 9223372036854775807 41 q-1 100,0,0,0 8133 0:2279
RACE bob 9223372036854775807 41 q-1 0,100,100,0 8133 1:2279
RACE bob 9223372036854775807 41 q-1 50,100,0 8133 1:2279
RACE bob 9223372036854775807 41 one_on_one 0,0,100,0 9167 1:2557;2:1881
RACE bob 9223372036854775807 41 one_on_one 100,0,0,0 9167 1:2557;0:1881
RACE bob 9223372036854775807 41 one_on_one 0,100,100,0 9167 1:2557
RACE bob 9223372036854775807 41 one_on_one 50,100,0 9167 0:2557;1:1881
RACE bob 9223372036854775807 41 general_knowledge_easy_017 0,0,100,0 9227 0:2397;2:1956
RACE bob 9223372036854775807 41 general_knowledge_easy_017 100,0,0,0 9227 0:2397
RACE bob 9223372036854775807 41 general_knowledge_easy_017 0,100,100,0 9227 0:2397;1:1956
RACE bob 9223372036854775807 41 general_knowledge_easy_017 50,100,0 9227 2:2397;1:1956
RACE bob 9223372036854775807 41 kids_arithmetic_9 0,0,100,0 8351 3:2035;1:1747;2:1656
RACE bob 9223372036854775807 41 kids_arithmetic_9 100,0,0,0 8351 3:2035;1:1747;0:1656
RACE bob 9223372036854775807 41 kids_arithmetic_9 0,100,100,0 8351 3:2035;1:1747
RACE bob 9223372036854775807 41 kids_arithmetic_9 50,100,0 8351 0:2035;2:1747;1:2068
RACE bob -9223372036854775808 1 q-1 0,0,100,0 9216 2:2033
RACE bob -9223372036854775808 1 q-1 100,0,0,0 9216 0:2033
RACE bob -9223372036854775808 1 q-1 0,100,100,0 9216 1:2033
RACE bob -9223372036854775808 1 q-1 50,100,0 9216 1:2033
RACE bob -9223372036854775808 1 one_on_one 0,0,100,0 9085 2:1993
RACE bob -9223372036854775808 1 one_on_one 100,0,0,0 9085 0:1993
RACE bob -9223372036854775808 1 one_on_one 0,100,100,0 9085 1:1993
RACE bob -9223372036854775808 1 one_on_one 50,100,0 9085 1:1993
RACE bob -9223372036854775808 1 general_knowledge_easy_017 0,0,100,0 7764 1:2091;3:1888;0:1757;2:2155
RACE bob -9223372036854775808 1 general_knowledge_easy_017 100,0,0,0 7764 1:2091;3:1888;2:1757;0:2155
RACE bob -9223372036854775808 1 general_knowledge_easy_017 0,100,100,0 7764 1:2091
RACE bob -9223372036854775808 1 general_knowledge_easy_017 50,100,0 7764 0:2091;2:1888;1:1908
RACE bob -9223372036854775808 1 kids_arithmetic_9 0,0,100,0 7777 2:2221
RACE bob -9223372036854775808 1 kids_arithmetic_9 100,0,0,0 7777 2:2221;1:1970;3:2106;0:1838
RACE bob -9223372036854775808 1 kids_arithmetic_9 0,100,100,0 7777 2:2221
RACE bob -9223372036854775808 1 kids_arithmetic_9 50,100,0 7777 0:2221;2:1970;1:1662
RACE bob -9223372036854775808 41 q-1 0,0,100,0 8080 2:2336
RACE bob -9223372036854775808 41 q-1 100,0,0,0 8080 0:2336
RACE bob -9223372036854775808 41 q-1 0,100,100,0 8080 1:2336
RACE bob -9223372036854775808 41 q-1 50,100,0 8080 1:2336
RACE bob -9223372036854775808 41 one_on_one 0,0,100,0 8113 1:2056;2:1568
RACE bob -9223372036854775808 41 one_on_one 100,0,0,0 8113 2:2056;0:1568
RACE bob -9223372036854775808 41 one_on_one 0,100,100,0 8113 0:2056;1:1568
RACE bob -9223372036854775808 41 one_on_one 50,100,0 8113 0:2056;1:1568
RACE bob -9223372036854775808 41 general_knowledge_easy_017 0,0,100,0 8494 2:2658
RACE bob -9223372036854775808 41 general_knowledge_easy_017 100,0,0,0 8494 0:2658
RACE bob -9223372036854775808 41 general_knowledge_easy_017 0,100,100,0 8494 2:2658
RACE bob -9223372036854775808 41 general_knowledge_easy_017 50,100,0 8494 1:2658
RACE bob -9223372036854775808 41 kids_arithmetic_9 0,0,100,0 8288 2:2697
RACE bob -9223372036854775808 41 kids_arithmetic_9 100,0,0,0 8288 0:2697
RACE bob -9223372036854775808 41 kids_arithmetic_9 0,100,100,0 8288 1:2697
RACE bob -9223372036854775808 41 kids_arithmetic_9 50,100,0 8288 1:2697
RACE woman_dark 0 1 q-1 0,0,100,0 7743 2:2393
RACE woman_dark 0 1 q-1 100,0,0,0 7743 0:2393
RACE woman_dark 0 1 q-1 0,100,100,0 7743 2:2393
RACE woman_dark 0 1 q-1 50,100,0 7743 1:2393
RACE woman_dark 0 1 one_on_one 0,0,100,0 8637 2:1863
RACE woman_dark 0 1 one_on_one 100,0,0,0 8637 0:1863
RACE woman_dark 0 1 one_on_one 0,100,100,0 8637 1:1863
RACE woman_dark 0 1 one_on_one 50,100,0 8637 1:1863
RACE woman_dark 0 1 general_knowledge_easy_017 0,0,100,0 7388 3:2567;2:1801
RACE woman_dark 0 1 general_knowledge_easy_017 100,0,0,0 7388 3:2567;0:1801
RACE woman_dark 0 1 general_knowledge_easy_017 0,100,100,0 7388 0:2567;1:1801
RACE woman_dark 0 1 general_knowledge_easy_017 50,100,0 7388 0:2567;1:1801
RACE woman_dark 0 1 kids_arithmetic_9 0,0,100,0 8118 2:1860
RACE woman_dark 0 1 kids_arithmetic_9 100,0,0,0 8118 0:1860
RACE woman_dark 0 1 kids_arithmetic_9 0,100,100,0 8118 1:1860
RACE woman_dark 0 1 kids_arithmetic_9 50,100,0 8118 1:1860
RACE woman_dark 0 41 q-1 0,0,100,0 7210 2:1939
RACE woman_dark 0 41 q-1 100,0,0,0 7210 0:1939
RACE woman_dark 0 41 q-1 0,100,100,0 7210 1:1939
RACE woman_dark 0 41 q-1 50,100,0 7210 1:1939
RACE woman_dark 0 41 one_on_one 0,0,100,0 7931 2:2374
RACE woman_dark 0 41 one_on_one 100,0,0,0 7931 0:2374
RACE woman_dark 0 41 one_on_one 0,100,100,0 7931 2:2374
RACE woman_dark 0 41 one_on_one 50,100,0 7931 1:2374
RACE woman_dark 0 41 general_knowledge_easy_017 0,0,100,0 8320 1:2081;2:1502
RACE woman_dark 0 41 general_knowledge_easy_017 100,0,0,0 8320 2:2081;0:1502
RACE woman_dark 0 41 general_knowledge_easy_017 0,100,100,0 8320 3:2081;1:1502
RACE woman_dark 0 41 general_knowledge_easy_017 50,100,0 8320 2:2081;1:1502
RACE woman_dark 0 41 kids_arithmetic_9 0,0,100,0 7843 2:2476
RACE woman_dark 0 41 kids_arithmetic_9 100,0,0,0 7843 0:2476
RACE woman_dark 0 41 kids_arithmetic_9 0,100,100,0 7843 1:2476
RACE woman_dark 0 41 kids_arithmetic_9 50,100,0 7843 1:2476
RACE woman_dark 1700000000123 1 q-1 0,0,100,0 8925 3:1867;2:1685
RACE woman_dark 1700000000123 1 q-1 100,0,0,0 8925 3:1867;0:1685
RACE woman_dark 1700000000123 1 q-1 0,100,100,0 8925 0:1867;1:1685
RACE woman_dark 1700000000123 1 q-1 50,100,0 8925 0:1867;1:1685
RACE woman_dark 1700000000123 1 one_on_one 0,0,100,0 8611 2:2632
RACE woman_dark 1700000000123 1 one_on_one 100,0,0,0 8611 0:2632
RACE woman_dark 1700000000123 1 one_on_one 0,100,100,0 8611 2:2632
RACE woman_dark 1700000000123 1 one_on_one 50,100,0 8611 1:2632
RACE woman_dark 1700000000123 1 general_knowledge_easy_017 0,0,100,0 8429 2:2430
RACE woman_dark 1700000000123 1 general_knowledge_easy_017 100,0,0,0 8429 0:2430
RACE woman_dark 1700000000123 1 general_knowledge_easy_017 0,100,100,0 8429 2:2430
RACE woman_dark 1700000000123 1 general_knowledge_easy_017 50,100,0 8429 1:2430
RACE woman_dark 1700000000123 1 kids_arithmetic_9 0,0,100,0 7686 3:2068;2:1578
RACE woman_dark 1700000000123 1 kids_arithmetic_9 100,0,0,0 7686 3:2068;0:1578
RACE woman_dark 1700000000123 1 kids_arithmetic_9 0,100,100,0 7686 0:2068;2:1578
RACE woman_dark 1700000000123 1 kids_arithmetic_9 50,100,0 7686 0:2068;1:1578
RACE woman_dark 1700000000123 41 q-1 0,0,100,0 7799 2:2005
RACE woman_dark 1700000000123 41 q-1 100,0,0,0 7799 0:2005
RACE woman_dark 1700000000123 41 q-1 0,100,100,0 7799 2:2005
RACE woman_dark 1700000000123 41 q-1 50,100,0 7799 1:2005
RACE woman_dark 1700000000123 41 one_on_one 0,0,100,0 8183 2:2264
RACE woman_dark 1700000000123 41 one_on_one 100,0,0,0 8183 0:2264
RACE woman_dark 1700000000123 41 one_on_one 0,100,100,0 8183 1:2264
RACE woman_dark 1700000000123 41 one_on_one 50,100,0 8183 1:2264
RACE woman_dark 1700000000123 41 general_knowledge_easy_017 0,0,100,0 8327 2:2256
RACE woman_dark 1700000000123 41 general_knowledge_easy_017 100,0,0,0 8327 0:2256
RACE woman_dark 1700000000123 41 general_knowledge_easy_017 0,100,100,0 8327 1:2256
RACE woman_dark 1700000000123 41 general_knowledge_easy_017 50,100,0 8327 1:2256
RACE woman_dark 1700000000123 41 kids_arithmetic_9 0,0,100,0 7769 2:2219
RACE woman_dark 1700000000123 41 kids_arithmetic_9 100,0,0,0 7769 0:2219
RACE woman_dark 1700000000123 41 kids_arithmetic_9 0,100,100,0 7769 1:2219
RACE woman_dark 1700000000123 41 kids_arithmetic_9 50,100,0 7769 1:2219
RACE woman_dark 9223372036854775807 1 q-1 0,0,100,0 8367 2:1897
RACE woman_dark 9223372036854775807 1 q-1 100,0,0,0 8367 0:1897
RACE woman_dark 9223372036854775807 1 q-1 0,100,100,0 8367 2:1897
RACE woman_dark 9223372036854775807 1 q-1 50,100,0 8367 1:1897
RACE woman_dark 9223372036854775807 1 one_on_one 0,0,100,0 8240 0:1939;1:1883;2:1951
RACE woman_dark 9223372036854775807 1 one_on_one 100,0,0,0 8240 0:1939
RACE woman_dark 9223372036854775807 1 one_on_one 0,100,100,0 8240 0:1939;3:1883;1:1603
RACE woman_dark 9223372036854775807 1 one_on_one 50,100,0 8240 0:1939;2:1883;1:1603
RACE woman_dark 9223372036854775807 1 general_knowledge_easy_017 0,0,100,0 8390 2:2079
RACE woman_dark 9223372036854775807 1 general_knowledge_easy_017 100,0,0,0 8390 0:2079
RACE woman_dark 9223372036854775807 1 general_knowledge_easy_017 0,100,100,0 8390 1:2079
RACE woman_dark 9223372036854775807 1 general_knowledge_easy_017 50,100,0 8390 1:2079
RACE woman_dark 9223372036854775807 1 kids_arithmetic_9 0,0,100,0 7326 2:2122
RACE woman_dark 9223372036854775807 1 kids_arithmetic_9 100,0,0,0 7326 0:2122
RACE woman_dark 9223372036854775807 1 kids_arithmetic_9 0,100,100,0 7326 1:2122
RACE woman_dark 9223372036854775807 1 kids_arithmetic_9 50,100,0 7326 1:2122
RACE woman_dark 9223372036854775807 41 q-1 0,0,100,0 7780 2:2122
RACE woman_dark 9223372036854775807 41 q-1 100,0,0,0 7780 0:2122
RACE woman_dark 9223372036854775807 41 q-1 0,100,100,0 7780 1:2122
RACE woman_dark 9223372036854775807 41 q-1 50,100,0 7780 1:2122
RACE woman_dark 9223372036854775807 41 one_on_one 0,0,100,0 8814 1:2400;2:1801
RACE woman_dark 9223372036854775807 41 one_on_one 100,0,0,0 8814 1:2400;0:1801
RACE woman_dark 9223372036854775807 41 one_on_one 0,100,100,0 8814 1:2400
RACE woman_dark 9223372036854775807 41 one_on_one 50,100,0 8814 0:2400;1:1801
RACE woman_dark 9223372036854775807 41 general_knowledge_easy_017 0,0,100,0 8874 0:2240;2:1876
RACE woman_dark 9223372036854775807 41 general_knowledge_easy_017 100,0,0,0 8874 0:2240
RACE woman_dark 9223372036854775807 41 general_knowledge_easy_017 0,100,100,0 8874 0:2240;1:1876
RACE woman_dark 9223372036854775807 41 general_knowledge_easy_017 50,100,0 8874 2:2240;1:1876
RACE woman_dark 9223372036854775807 41 kids_arithmetic_9 0,0,100,0 7998 3:1878;1:1667;2:1576
RACE woman_dark 9223372036854775807 41 kids_arithmetic_9 100,0,0,0 7998 3:1878;1:1667;0:1576
RACE woman_dark 9223372036854775807 41 kids_arithmetic_9 0,100,100,0 7998 3:1878;1:1667
RACE woman_dark 9223372036854775807 41 kids_arithmetic_9 50,100,0 7998 0:1878;2:1667;1:1988
RACE woman_dark -9223372036854775808 1 q-1 0,0,100,0 8863 2:1876
RACE woman_dark -9223372036854775808 1 q-1 100,0,0,0 8863 0:1876
RACE woman_dark -9223372036854775808 1 q-1 0,100,100,0 8863 1:1876
RACE woman_dark -9223372036854775808 1 q-1 50,100,0 8863 1:1876
RACE woman_dark -9223372036854775808 1 one_on_one 0,0,100,0 8732 2:1836
RACE woman_dark -9223372036854775808 1 one_on_one 100,0,0,0 8732 0:1836
RACE woman_dark -9223372036854775808 1 one_on_one 0,100,100,0 8732 1:1836
RACE woman_dark -9223372036854775808 1 one_on_one 50,100,0 8732 1:1836
RACE woman_dark -9223372036854775808 1 general_knowledge_easy_017 0,0,100,0 7411 1:1934;2:1808
RACE woman_dark -9223372036854775808 1 general_knowledge_easy_017 100,0,0,0 7411 1:1934;0:1808
RACE woman_dark -9223372036854775808 1 general_knowledge_easy_017 0,100,100,0 7411 1:1934
RACE woman_dark -9223372036854775808 1 general_knowledge_easy_017 50,100,0 7411 0:1934;1:1808
RACE woman_dark -9223372036854775808 1 kids_arithmetic_9 0,0,100,0 7424 2:2064
RACE woman_dark -9223372036854775808 1 kids_arithmetic_9 100,0,0,0 7424 2:2064;1:1890;3:2026;0:1758
RACE woman_dark -9223372036854775808 1 kids_arithmetic_9 0,100,100,0 7424 2:2064
RACE woman_dark -9223372036854775808 1 kids_arithmetic_9 50,100,0 7424 0:2064;2:1890;1:1582
RACE woman_dark -9223372036854775808 41 q-1 0,0,100,0 7727 2:2179
RACE woman_dark -9223372036854775808 41 q-1 100,0,0,0 7727 0:2179
RACE woman_dark -9223372036854775808 41 q-1 0,100,100,0 7727 1:2179
RACE woman_dark -9223372036854775808 41 q-1 50,100,0 7727 1:2179
RACE woman_dark -9223372036854775808 41 one_on_one 0,0,100,0 7760 1:1899;2:1488
RACE woman_dark -9223372036854775808 41 one_on_one 100,0,0,0 7760 2:1899;0:1488
RACE woman_dark -9223372036854775808 41 one_on_one 0,100,100,0 7760 0:1899;1:1488
RACE woman_dark -9223372036854775808 41 one_on_one 50,100,0 7760 0:1899;1:1488
RACE woman_dark -9223372036854775808 41 general_knowledge_easy_017 0,0,100,0 8141 2:2501
RACE woman_dark -9223372036854775808 41 general_knowledge_easy_017 100,0,0,0 8141 0:2501
RACE woman_dark -9223372036854775808 41 general_knowledge_easy_017 0,100,100,0 8141 2:2501
RACE woman_dark -9223372036854775808 41 general_knowledge_easy_017 50,100,0 8141 1:2501
RACE woman_dark -9223372036854775808 41 kids_arithmetic_9 0,0,100,0 7935 2:2540
RACE woman_dark -9223372036854775808 41 kids_arithmetic_9 100,0,0,0 7935 0:2540
RACE woman_dark -9223372036854775808 41 kids_arithmetic_9 0,100,100,0 7935 1:2540
RACE woman_dark -9223372036854775808 41 kids_arithmetic_9 50,100,0 7935 1:2540
RACE rooza 0 1 q-1 0,0,100,0 6621 2:1237
RACE rooza 0 1 q-1 100,0,0,0 6621 2:1237;3:951;0:1445
RACE rooza 0 1 q-1 0,100,100,0 6621 2:1237
RACE rooza 0 1 q-1 50,100,0 6621 2:1237;1:951
RACE rooza 0 1 one_on_one 0,0,100,0 7515 2:886
RACE rooza 0 1 one_on_one 100,0,0,0 7515 0:886
RACE rooza 0 1 one_on_one 0,100,100,0 7515 1:886
RACE rooza 0 1 one_on_one 50,100,0 7515 1:886
RACE rooza 0 1 general_knowledge_easy_017 0,0,100,0 6266 3:1590;2:882
RACE rooza 0 1 general_knowledge_easy_017 100,0,0,0 6266 3:1590;2:882;0:1214
RACE rooza 0 1 general_knowledge_easy_017 0,100,100,0 6266 0:1590;3:882;1:1336
RACE rooza 0 1 general_knowledge_easy_017 50,100,0 6266 0:1590;2:882;1:1336
RACE rooza 0 1 kids_arithmetic_9 0,0,100,0 6996 0:905;1:994;3:1273;2:1166
RACE rooza 0 1 kids_arithmetic_9 100,0,0,0 6996 0:905
RACE rooza 0 1 kids_arithmetic_9 0,100,100,0 6996 0:905;3:994;1:1298
RACE rooza 0 1 kids_arithmetic_9 50,100,0 6996 0:905;2:994;1:1298
RACE rooza 0 41 q-1 0,0,100,0 6088 0:1080;1:1288;2:1464
RACE rooza 0 41 q-1 100,0,0,0 6088 0:1080
RACE rooza 0 41 q-1 0,100,100,0 6088 0:1080;1:1288
RACE rooza 0 41 q-1 50,100,0 6088 0:1080;1:1288
RACE rooza 0 41 one_on_one 0,0,100,0 6809 3:1445;0:1274;2:1465
RACE rooza 0 41 one_on_one 100,0,0,0 6809 3:1445;1:1274;0:1465
RACE rooza 0 41 one_on_one 0,100,100,0 6809 3:1445;0:1274;2:1364
RACE rooza 0 41 one_on_one 50,100,0 6809 2:1445;0:1274;1:1364
RACE rooza 0 41 general_knowledge_easy_017 0,0,100,0 7198 1:1104;2:1006
RACE rooza 0 41 general_knowledge_easy_017 100,0,0,0 7198 2:1104;0:1006
RACE rooza 0 41 general_knowledge_easy_017 0,100,100,0 7198 3:1104;1:1006
RACE rooza 0 41 general_knowledge_easy_017 50,100,0 7198 2:1104;1:1006
RACE rooza 0 41 kids_arithmetic_9 0,0,100,0 6721 0:1499;3:1008;1:1341;2:1327
RACE rooza 0 41 kids_arithmetic_9 100,0,0,0 6721 1:1499;3:1008;2:1341;0:1327
RACE rooza 0 41 kids_arithmetic_9 0,100,100,0 6721 0:1499;3:1008;2:1064
RACE rooza 0 41 kids_arithmetic_9 50,100,0 6721 0:1499;2:1008;1:1064
RACE rooza 1700000000123 1 q-1 0,0,100,0 7803 0:910;2:1189
RACE rooza 1700000000123 1 q-1 100,0,0,0 7803 0:910
RACE rooza 1700000000123 1 q-1 0,100,100,0 7803 0:910;1:1189
RACE rooza 1700000000123 1 q-1 50,100,0 7803 1:910
RACE rooza 1700000000123 1 one_on_one 0,0,100,0 7489 2:1655
RACE rooza 1700000000123 1 one_on_one 100,0,0,0 7489 0:1655
RACE rooza 1700000000123 1 one_on_one 0,100,100,0 7489 2:1655
RACE rooza 1700000000123 1 one_on_one 50,100,0 7489 1:1655
RACE rooza 1700000000123 1 general_knowledge_easy_017 0,0,100,0 7307 2:1453
RACE rooza 1700000000123 1 general_knowledge_easy_017 100,0,0,0 7307 0:1453
RACE rooza 1700000000123 1 general_knowledge_easy_017 0,100,100,0 7307 2:1453
RACE rooza 1700000000123 1 general_knowledge_easy_017 50,100,0 7307 1:1453
RACE rooza 1700000000123 1 kids_arithmetic_9 0,0,100,0 6564 3:1629;2:1203
RACE rooza 1700000000123 1 kids_arithmetic_9 100,0,0,0 6564 3:1629;2:1203;0:1312
RACE rooza 1700000000123 1 kids_arithmetic_9 0,100,100,0 6564 3:1629;2:1203
RACE rooza 1700000000123 1 kids_arithmetic_9 50,100,0 6564 1:1629
RACE rooza 1700000000123 41 q-1 0,0,100,0 6677 0:1028;1:1287;2:1221
RACE rooza 1700000000123 41 q-1 100,0,0,0 6677 1:1028;2:1287;0:1221
RACE rooza 1700000000123 41 q-1 0,100,100,0 6677 3:1028;0:1287;1:1160
RACE rooza 1700000000123 41 q-1 50,100,0 6677 2:1028;0:1287;1:1160
RACE rooza 1700000000123 41 one_on_one 0,0,100,0 7061 2:1317
RACE rooza 1700000000123 41 one_on_one 100,0,0,0 7061 2:1317;0:906
RACE rooza 1700000000123 41 one_on_one 0,100,100,0 7061 2:1317
RACE rooza 1700000000123 41 one_on_one 50,100,0 7061 2:1317;1:906
RACE rooza 1700000000123 41 general_knowledge_easy_017 0,0,100,0 7205 3:1279;2:1275
RACE rooza 1700000000123 41 general_knowledge_easy_017 100,0,0,0 7205 3:1279;2:1275;0:1075
RACE rooza 1700000000123 41 general_knowledge_easy_017 0,100,100,0 7205 0:1279;3:1275;2:1165
RACE rooza 1700000000123 41 general_knowledge_easy_017 50,100,0 7205 0:1279;2:1275;1:1165
RACE rooza 1700000000123 41 kids_arithmetic_9 0,0,100,0 6647 3:945;2:1079
RACE rooza 1700000000123 41 kids_arithmetic_9 100,0,0,0 6647 3:945;2:1079;0:1200
RACE rooza 1700000000123 41 kids_arithmetic_9 0,100,100,0 6647 3:945;2:1079
RACE rooza 1700000000123 41 kids_arithmetic_9 50,100,0 6647 0:945;2:1079;1:1147
RACE rooza 9223372036854775807 1 q-1 0,0,100,0 7245 0:1513;3:1185;2:1329
RACE rooza 9223372036854775807 1 q-1 100,0,0,0 7245 0:1513
RACE rooza 9223372036854775807 1 q-1 0,100,100,0 7245 0:1513;3:1185;2:1167
RACE rooza 9223372036854775807 1 q-1 50,100,0 7245 2:1513;0:1185;1:1167
RACE rooza 9223372036854775807 1 one_on_one 0,0,100,0 7118 0:962;2:1016
RACE rooza 9223372036854775807 1 one_on_one 100,0,0,0 7118 0:962
RACE rooza 9223372036854775807 1 one_on_one 0,100,100,0 7118 0:962;2:1016
RACE rooza 9223372036854775807 1 one_on_one 50,100,0 7118 0:962;1:1016
RACE rooza 9223372036854775807 1 general_knowledge_easy_017 0,0,100,0 7268 2:1102
RACE rooza 9223372036854775807 1 general_knowledge_easy_017 100,0,0,0 7268 0:1102
RACE rooza 9223372036854775807 1 general_knowledge_easy_017 0,100,100,0 7268 1:1102
RACE rooza 9223372036854775807 1 general_knowledge_easy_017 50,100,0 7268 1:1102
RACE rooza 9223372036854775807 1 kids_arithmetic_9 0,0,100,0 6204 2:1145
RACE rooza 9223372036854775807 1 kids_arithmetic_9 100,0,0,0 6204 0:1145
RACE rooza 9223372036854775807 1 kids_arithmetic_9 0,100,100,0 6204 1:1145
RACE rooza 9223372036854775807 1 kids_arithmetic_9 50,100,0 6204 1:1145
RACE rooza 9223372036854775807 41 q-1 0,0,100,0 6658 0:1173;3:1128;2:1186
RACE rooza 9223372036854775807 41 q-1 100,0,0,0 6658 0:1173
RACE rooza 9223372036854775807 41 q-1 0,100,100,0 6658 0:1173;3:1128;2:1228
RACE rooza 9223372036854775807 41 q-1 50,100,0 6658 0:1173;1:1128
RACE rooza 9223372036854775807 41 one_on_one 0,0,100,0 7692 1:1423;0:1305;3:1318;2:1171
RACE rooza 9223372036854775807 41 one_on_one 100,0,0,0 7692 1:1423;2:1305;3:1318;0:1171
RACE rooza 9223372036854775807 41 one_on_one 0,100,100,0 7692 1:1423
RACE rooza 9223372036854775807 41 one_on_one 50,100,0 7692 0:1423;2:1305;1:1030
RACE rooza 9223372036854775807 41 general_knowledge_easy_017 0,0,100,0 7752 0:1263;1:920;2:1159
RACE rooza 9223372036854775807 41 general_knowledge_easy_017 100,0,0,0 7752 0:1263
RACE rooza 9223372036854775807 41 general_knowledge_easy_017 0,100,100,0 7752 0:1263;1:920
RACE rooza 9223372036854775807 41 general_knowledge_easy_017 50,100,0 7752 2:1263;0:920;1:1208
RACE rooza 9223372036854775807 41 kids_arithmetic_9 0,0,100,0 6876 3:901;1:1171;2:1080
RACE rooza 9223372036854775807 41 kids_arithmetic_9 100,0,0,0 6876 3:901;1:1171;0:1080
RACE rooza 9223372036854775807 41 kids_arithmetic_9 0,100,100,0 6876 3:901;1:1171
RACE rooza 9223372036854775807 41 kids_arithmetic_9 50,100,0 6876 0:901;2:1171;1:1492
RACE rooza -9223372036854775808 1 q-1 0,0,100,0 7741 1:1278;0:1086;3:1191;2:1545
RACE rooza -9223372036854775808 1 q-1 100,0,0,0 7741 1:1278;2:1086;3:1191;0:1545
RACE rooza -9223372036854775808 1 q-1 0,100,100,0 7741 1:1278
RACE rooza -9223372036854775808 1 q-1 50,100,0 7741 0:1278;2:1086;1:1439
RACE rooza -9223372036854775808 1 one_on_one 0,0,100,0 7610 0:1496;2:1178
RACE rooza -9223372036854775808 1 one_on_one 100,0,0,0 7610 0:1496
RACE rooza -9223372036854775808 1 one_on_one 0,100,100,0 7610 0:1496;1:1178
RACE rooza -9223372036854775808 1 one_on_one 50,100,0 7610 2:1496;1:1178
RACE rooza -9223372036854775808 1 general_knowledge_easy_017 0,0,100,0 6289 1:957;3:1312;0:1181;2:1579
RACE rooza -9223372036854775808 1 general_knowledge_easy_017 100,0,0,0 6289 1:957;3:1312;2:1181;0:1579
RACE rooza -9223372036854775808 1 general_knowledge_easy_017 0,100,100,0 6289 1:957
RACE rooza -9223372036854775808 1 general_knowledge_easy_017 50,100,0 6289 0:957;2:1312;1:1332
RACE rooza -9223372036854775808 1 kids_arithmetic_9 0,0,100,0 6302 2:1087
RACE rooza -9223372036854775808 1 kids_arithmetic_9 100,0,0,0 6302 2:1087;1:1394;3:1530;0:1262
RACE rooza -9223372036854775808 1 kids_arithmetic_9 0,100,100,0 6302 2:1087
RACE rooza -9223372036854775808 1 kids_arithmetic_9 50,100,0 6302 0:1087;2:1394;1:1086
RACE rooza -9223372036854775808 41 q-1 0,0,100,0 6605 2:1202
RACE rooza -9223372036854775808 41 q-1 100,0,0,0 6605 0:1202
RACE rooza -9223372036854775808 41 q-1 0,100,100,0 6605 1:1202
RACE rooza -9223372036854775808 41 q-1 50,100,0 6605 1:1202
RACE rooza -9223372036854775808 41 one_on_one 0,0,100,0 6638 1:922;2:992
RACE rooza -9223372036854775808 41 one_on_one 100,0,0,0 6638 2:922;0:992
RACE rooza -9223372036854775808 41 one_on_one 0,100,100,0 6638 0:922;1:992
RACE rooza -9223372036854775808 41 one_on_one 50,100,0 6638 0:922;1:992
RACE rooza -9223372036854775808 41 general_knowledge_easy_017 0,0,100,0 7019 1:1524;2:1334
RACE rooza -9223372036854775808 41 general_knowledge_easy_017 100,0,0,0 7019 2:1524;1:1334;0:1442
RACE rooza -9223372036854775808 41 general_knowledge_easy_017 0,100,100,0 7019 3:1524;1:1334
RACE rooza -9223372036854775808 41 general_knowledge_easy_017 50,100,0 7019 2:1524;1:1334
RACE rooza -9223372036854775808 41 kids_arithmetic_9 0,0,100,0 6813 1:919;0:1316;3:1517;2:1219
RACE rooza -9223372036854775808 41 kids_arithmetic_9 100,0,0,0 6813 1:919;2:1316;3:1517;0:1219
RACE rooza -9223372036854775808 41 kids_arithmetic_9 0,100,100,0 6813 1:919
RACE rooza -9223372036854775808 41 kids_arithmetic_9 50,100,0 6813 0:919;2:1316;1:1339
RACE nova 0 1 q-1 0,0,100,0 6212 2:1605
RACE nova 0 1 q-1 100,0,0,0 6212 0:1605
RACE nova 0 1 q-1 0,100,100,0 6212 2:1605
RACE nova 0 1 q-1 50,100,0 6212 1:1605
RACE nova 0 1 one_on_one 0,0,100,0 7106 2:1075
RACE nova 0 1 one_on_one 100,0,0,0 7106 0:1075
RACE nova 0 1 one_on_one 0,100,100,0 7106 1:1075
RACE nova 0 1 one_on_one 50,100,0 7106 1:1075
RACE nova 0 1 general_knowledge_easy_017 0,0,100,0 5857 3:1779;2:1401
RACE nova 0 1 general_knowledge_easy_017 100,0,0,0 5857 3:1779;0:1401
RACE nova 0 1 general_knowledge_easy_017 0,100,100,0 5857 0:1779;1:1401
RACE nova 0 1 general_knowledge_easy_017 50,100,0 5857 0:1779;1:1401
RACE nova 0 1 kids_arithmetic_9 0,0,100,0 6587 2:1072
RACE nova 0 1 kids_arithmetic_9 100,0,0,0 6587 0:1072
RACE nova 0 1 kids_arithmetic_9 0,100,100,0 6587 1:1072
RACE nova 0 1 kids_arithmetic_9 50,100,0 6587 1:1072
RACE nova 0 41 q-1 0,0,100,0 5679 2:1151
RACE nova 0 41 q-1 100,0,0,0 5679 0:1151
RACE nova 0 41 q-1 0,100,100,0 5679 1:1151
RACE nova 0 41 q-1 50,100,0 5679 1:1151
RACE nova 0 41 one_on_one 0,0,100,0 6400 2:1586
RACE nova 0 41 one_on_one 100,0,0,0 6400 0:1586
RACE nova 0 41 one_on_one 0,100,100,0 6400 2:1586
RACE nova 0 41 one_on_one 50,100,0 6400 1:1586
RACE nova 0 41 general_knowledge_easy_017 0,0,100,0 6789 1:1293;2:1102
RACE nova 0 41 general_knowledge_easy_017 100,0,0,0 6789 2:1293;0:1102
RACE nova 0 41 general_knowledge_easy_017 0,100,100,0 6789 3:1293;1:1102
RACE nova 0 41 general_knowledge_easy_017 50,100,0 6789 2:1293;1:1102
RACE nova 0 41 kids_arithmetic_9 0,0,100,0 6312 2:1688
RACE nova 0 41 kids_arithmetic_9 100,0,0,0 6312 0:1688
RACE nova 0 41 kids_arithmetic_9 0,100,100,0 6312 1:1688
RACE nova 0 41 kids_arithmetic_9 50,100,0 6312 1:1688
RACE nova 1700000000123 1 q-1 0,0,100,0 7394 2:1079
RACE nova 1700000000123 1 q-1 100,0,0,0 7394 0:1079
RACE nova 1700000000123 1 q-1 0,100,100,0 7394 1:1079
RACE nova 1700000000123 1 q-1 50,100,0 7394 1:1079
RACE nova 1700000000123 1 one_on_one 0,0,100,0 7080 2:1844
RACE nova 1700000000123 1 one_on_one 100,0,0,0 7080 0:1844
RACE nova 1700000000123 1 one_on_one 0,100,100,0 7080 2:1844
RACE nova 1700000000123 1 one_on_one 50,100,0 7080 1:1844
RACE nova 1700000000123 1 general_knowledge_easy_017 0,0,100,0 6898 2:1642
RACE nova 1700000000123 1 general_knowledge_easy_017 100,0,0,0 6898 0:1642
RACE nova 1700000000123 1 general_knowledge_easy_017 0,100,100,0 6898 2:1642
RACE nova 1700000000123 1 general_knowledge_easy_017 50,100,0 6898 1:1642
RACE nova 1700000000123 1 kids_arithmetic_9 0,0,100,0 6155 2:1280
RACE nova 1700000000123 1 kids_arithmetic_9 100,0,0,0 6155 0:1280
RACE nova 1700000000123 1 kids_arithmetic_9 0,100,100,0 6155 1:1280
RACE nova 1700000000123 1 kids_arithmetic_9 50,100,0 6155 1:1280
RACE nova 1700000000123 41 q-1 0,0,100,0 6268 2:1217
RACE nova 1700000000123 41 q-1 100,0,0,0 6268 0:1217
RACE nova 1700000000123 41 q-1 0,100,100,0 6268 2:1217
RACE nova 1700000000123 41 q-1 50,100,0 6268 1:1217
RACE nova 1700000000123 41 one_on_one 0,0,100,0 6652 2:1476
RACE nova 1700000000123 41 one_on_one 100,0,0,0 6652 0:1476
RACE nova 1700000000123 41 one_on_one 0,100,100,0 6652 1:1476
RACE nova 1700000000123 41 one_on_one 50,100,0 6652 1:1476
RACE nova 1700000000123 41 general_knowledge_easy_017 0,0,100,0 6796 2:1468
RACE nova 1700000000123 41 general_knowledge_easy_017 100,0,0,0 6796 0:1468
RACE nova 1700000000123 41 general_knowledge_easy_017 0,100,100,0 6796 1:1468
RACE nova 1700000000123 41 general_knowledge_easy_017 50,100,0 6796 1:1468
RACE nova 1700000000123 41 kids_arithmetic_9 0,0,100,0 6238 2:1431
RACE nova 1700000000123 41 kids_arithmetic_9 100,0,0,0 6238 0:1431
RACE nova 1700000000123 41 kids_arithmetic_9 0,100,100,0 6238 1:1431
RACE nova 1700000000123 41 kids_arithmetic_9 50,100,0 6238 1:1431
RACE nova 9223372036854775807 1 q-1 0,0,100,0 6836 2:1109
RACE nova 9223372036854775807 1 q-1 100,0,0,0 6836 0:1109
RACE nova 9223372036854775807 1 q-1 0,100,100,0 6836 2:1109
RACE nova 9223372036854775807 1 q-1 50,100,0 6836 1:1109
RACE nova 9223372036854775807 1 one_on_one 0,0,100,0 6709 2:1542
RACE nova 9223372036854775807 1 one_on_one 100,0,0,0 6709 0:1542
RACE nova 9223372036854775807 1 one_on_one 0,100,100,0 6709 1:1542
RACE nova 9223372036854775807 1 one_on_one 50,100,0 6709 1:1542
RACE nova 9223372036854775807 1 general_knowledge_easy_017 0,0,100,0 6859 2:1291
RACE nova 9223372036854775807 1 general_knowledge_easy_017 100,0,0,0 6859 0:1291
RACE nova 9223372036854775807 1 general_knowledge_easy_017 0,100,100,0 6859 1:1291
RACE nova 9223372036854775807 1 general_knowledge_easy_017 50,100,0 6859 1:1291
RACE nova 9223372036854775807 1 kids_arithmetic_9 0,0,100,0 5795 2:1334
RACE nova 9223372036854775807 1 kids_arithmetic_9 100,0,0,0 5795 0:1334
RACE nova 9223372036854775807 1 kids_arithmetic_9 0,100,100,0 5795 1:1334
RACE nova 9223372036854775807 1 kids_arithmetic_9 50,100,0 5795 1:1334
RACE nova 9223372036854775807 41 q-1 0,0,100,0 6249 2:1334
RACE nova 9223372036854775807 41 q-1 100,0,0,0 6249 0:1334
RACE nova 9223372036854775807 41 q-1 0,100,100,0 6249 1:1334
RACE nova 9223372036854775807 41 q-1 50,100,0 6249 1:1334
RACE nova 9223372036854775807 41 one_on_one 0,0,100,0 7283 2:1752
RACE nova 9223372036854775807 41 one_on_one 100,0,0,0 7283 0:1752
RACE nova 9223372036854775807 41 one_on_one 0,100,100,0 7283 1:1752
RACE nova 9223372036854775807 41 one_on_one 50,100,0 7283 1:1752
RACE nova 9223372036854775807 41 general_knowledge_easy_017 0,0,100,0 7343 2:1462
RACE nova 9223372036854775807 41 general_knowledge_easy_017 100,0,0,0 7343 0:1462
RACE nova 9223372036854775807 41 general_knowledge_easy_017 0,100,100,0 7343 2:1462
RACE nova 9223372036854775807 41 general_knowledge_easy_017 50,100,0 7343 1:1462
RACE nova 9223372036854775807 41 kids_arithmetic_9 0,0,100,0 6467 3:1090;2:1130
RACE nova 9223372036854775807 41 kids_arithmetic_9 100,0,0,0 6467 3:1090;0:1130
RACE nova 9223372036854775807 41 kids_arithmetic_9 0,100,100,0 6467 3:1090;2:1130
RACE nova 9223372036854775807 41 kids_arithmetic_9 50,100,0 6467 0:1090;1:1130
RACE nova -9223372036854775808 1 q-1 0,0,100,0 7332 2:1088
RACE nova -9223372036854775808 1 q-1 100,0,0,0 7332 0:1088
RACE nova -9223372036854775808 1 q-1 0,100,100,0 7332 1:1088
RACE nova -9223372036854775808 1 q-1 50,100,0 7332 1:1088
RACE nova -9223372036854775808 1 one_on_one 0,0,100,0 7201 2:1048
RACE nova -9223372036854775808 1 one_on_one 100,0,0,0 7201 0:1048
RACE nova -9223372036854775808 1 one_on_one 0,100,100,0 7201 1:1048
RACE nova -9223372036854775808 1 one_on_one 50,100,0 7201 1:1048
RACE nova -9223372036854775808 1 general_knowledge_easy_017 0,0,100,0 5880 1:1146;2:1408
RACE nova -9223372036854775808 1 general_knowledge_easy_017 100,0,0,0 5880 1:1146;0:1408
RACE nova -9223372036854775808 1 general_knowledge_easy_017 0,100,100,0 5880 1:1146
RACE nova -9223372036854775808 1 general_knowledge_easy_017 50,100,0 5880 0:1146;1:1408
RACE nova -9223372036854775808 1 kids_arithmetic_9 0,0,100,0 5893 2:1276
RACE nova -9223372036854775808 1 kids_arithmetic_9 100,0,0,0 5893 2:1276;1:1490;0:1123
RACE nova -9223372036854775808 1 kids_arithmetic_9 0,100,100,0 5893 2:1276
RACE nova -9223372036854775808 1 kids_arithmetic_9 50,100,0 5893 0:1276;2:1490;1:1182
RACE nova -9223372036854775808 41 q-1 0,0,100,0 6196 2:1391
RACE nova -9223372036854775808 41 q-1 100,0,0,0 6196 0:1391
RACE nova -9223372036854775808 41 q-1 0,100,100,0 6196 1:1391
RACE nova -9223372036854775808 41 q-1 50,100,0 6196 1:1391
RACE nova -9223372036854775808 41 one_on_one 0,0,100,0 6229 1:1111;2:1088
RACE nova -9223372036854775808 41 one_on_one 100,0,0,0 6229 2:1111;0:1088
RACE nova -9223372036854775808 41 one_on_one 0,100,100,0 6229 0:1111;1:1088
RACE nova -9223372036854775808 41 one_on_one 50,100,0 6229 0:1111;1:1088
RACE nova -9223372036854775808 41 general_knowledge_easy_017 0,0,100,0 6610 2:1713
RACE nova -9223372036854775808 41 general_knowledge_easy_017 100,0,0,0 6610 0:1713
RACE nova -9223372036854775808 41 general_knowledge_easy_017 0,100,100,0 6610 2:1713
RACE nova -9223372036854775808 41 general_knowledge_easy_017 50,100,0 6610 1:1713
RACE nova -9223372036854775808 41 kids_arithmetic_9 0,0,100,0 6404 2:1752
RACE nova -9223372036854775808 41 kids_arithmetic_9 100,0,0,0 6404 0:1752
RACE nova -9223372036854775808 41 kids_arithmetic_9 0,100,100,0 6404 1:1752
RACE nova -9223372036854775808 41 kids_arithmetic_9 50,100,0 6404 1:1752
RACE unicorn_32 0 1 q-1 0,0,100,0 8984 2:3306
RACE unicorn_32 0 1 q-1 100,0,0,0 8984 0:3306
RACE unicorn_32 0 1 q-1 0,100,100,0 8984 2:3306
RACE unicorn_32 0 1 q-1 50,100,0 8984 1:3306
RACE unicorn_32 0 1 one_on_one 0,0,100,0 9878 2:2776
RACE unicorn_32 0 1 one_on_one 100,0,0,0 9878 0:2776
RACE unicorn_32 0 1 one_on_one 0,100,100,0 9878 1:2776
RACE unicorn_32 0 1 one_on_one 50,100,0 9878 1:2776
RACE unicorn_32 0 1 general_knowledge_easy_017 0,0,100,0 8629 3:3480;2:2265
RACE unicorn_32 0 1 general_knowledge_easy_017 100,0,0,0 8629 3:3480;0:2265
RACE unicorn_32 0 1 general_knowledge_easy_017 0,100,100,0 8629 0:3480;1:2265
RACE unicorn_32 0 1 general_knowledge_easy_017 50,100,0 8629 0:3480;1:2265
RACE unicorn_32 0 1 kids_arithmetic_9 0,0,100,0 9359 2:2773
RACE unicorn_32 0 1 kids_arithmetic_9 100,0,0,0 9359 0:2773
RACE unicorn_32 0 1 kids_arithmetic_9 0,100,100,0 9359 1:2773
RACE unicorn_32 0 1 kids_arithmetic_9 50,100,0 9359 1:2773
RACE unicorn_32 0 41 q-1 0,0,100,0 8451 2:2852
RACE unicorn_32 0 41 q-1 100,0,0,0 8451 0:2852
RACE unicorn_32 0 41 q-1 0,100,100,0 8451 1:2852
RACE unicorn_32 0 41 q-1 50,100,0 8451 1:2852
RACE unicorn_32 0 41 one_on_one 0,0,100,0 9172 2:3287
RACE unicorn_32 0 41 one_on_one 100,0,0,0 9172 0:3287
RACE unicorn_32 0 41 one_on_one 0,100,100,0 9172 2:3287
RACE unicorn_32 0 41 one_on_one 50,100,0 9172 1:3287
RACE unicorn_32 0 41 general_knowledge_easy_017 0,0,100,0 9561 1:2994;2:1966
RACE unicorn_32 0 41 general_knowledge_easy_017 100,0,0,0 9561 2:2994;0:1966
RACE unicorn_32 0 41 general_knowledge_easy_017 0,100,100,0 9561 3:2994;1:1966
RACE unicorn_32 0 41 general_knowledge_easy_017 50,100,0 9561 2:2994;1:1966
RACE unicorn_32 0 41 kids_arithmetic_9 0,0,100,0 9084 2:3389
RACE unicorn_32 0 41 kids_arithmetic_9 100,0,0,0 9084 0:3389
RACE unicorn_32 0 41 kids_arithmetic_9 0,100,100,0 9084 1:3389
RACE unicorn_32 0 41 kids_arithmetic_9 50,100,0 9084 1:3389
RACE unicorn_32 1700000000123 1 q-1 0,0,100,0 10166 3:2780;2:2149
RACE unicorn_32 1700000000123 1 q-1 100,0,0,0 10166 3:2780;0:2149
RACE unicorn_32 1700000000123 1 q-1 0,100,100,0 10166 0:2780;1:2149
RACE unicorn_32 1700000000123 1 q-1 50,100,0 10166 0:2780;1:2149
RACE unicorn_32 1700000000123 1 one_on_one 0,0,100,0 9852 2:3545
RACE unicorn_32 1700000000123 1 one_on_one 100,0,0,0 9852 0:3545
RACE unicorn_32 1700000000123 1 one_on_one 0,100,100,0 9852 2:3545
RACE unicorn_32 1700000000123 1 one_on_one 50,100,0 9852 1:3545
RACE unicorn_32 1700000000123 1 general_knowledge_easy_017 0,0,100,0 9670 2:3343
RACE unicorn_32 1700000000123 1 general_knowledge_easy_017 100,0,0,0 9670 0:3343
RACE unicorn_32 1700000000123 1 general_knowledge_easy_017 0,100,100,0 9670 2:3343
RACE unicorn_32 1700000000123 1 general_knowledge_easy_017 50,100,0 9670 1:3343
RACE unicorn_32 1700000000123 1 kids_arithmetic_9 0,0,100,0 8927 3:2981;2:2042
RACE unicorn_32 1700000000123 1 kids_arithmetic_9 100,0,0,0 8927 3:2981;0:2042
RACE unicorn_32 1700000000123 1 kids_arithmetic_9 0,100,100,0 8927 0:2981;2:2042
RACE unicorn_32 1700000000123 1 kids_arithmetic_9 50,100,0 8927 0:2981;1:2042
RACE unicorn_32 1700000000123 41 q-1 0,0,100,0 9040 2:2918
RACE unicorn_32 1700000000123 41 q-1 100,0,0,0 9040 0:2918
RACE unicorn_32 1700000000123 41 q-1 0,100,100,0 9040 2:2918
RACE unicorn_32 1700000000123 41 q-1 50,100,0 9040 1:2918
RACE unicorn_32 1700000000123 41 one_on_one 0,0,100,0 9424 2:3177
RACE unicorn_32 1700000000123 41 one_on_one 100,0,0,0 9424 0:3177
RACE unicorn_32 1700000000123 41 one_on_one 0,100,100,0 9424 1:3177
RACE unicorn_32 1700000000123 41 one_on_one 50,100,0 9424 1:3177
RACE unicorn_32 1700000000123 41 general_knowledge_easy_017 0,0,100,0 9568 2:3169
RACE unicorn_32 1700000000123 41 general_knowledge_easy_017 100,0,0,0 9568 0:3169
RACE unicorn_32 1700000000123 41 general_knowledge_easy_017 0,100,100,0 9568 1:3169
RACE unicorn_32 1700000000123 41 general_knowledge_easy_017 50,100,0 9568 1:3169
RACE unicorn_32 1700000000123 41 kids_arithmetic_9 0,0,100,0 9010 2:3132
RACE unicorn_32 1700000000123 41 kids_arithmetic_9 100,0,0,0 9010 0:3132
RACE unicorn_32 1700000000123 41 kids_arithmetic_9 0,100,100,0 9010 1:3132
RACE unicorn_32 1700000000123 41 kids_arithmetic_9 50,100,0 9010 1:3132
RACE unicorn_32 9223372036854775807 1 q-1 0,0,100,0 9608 2:2810
RACE unicorn_32 9223372036854775807 1 q-1 100,0,0,0 9608 0:2810
RACE unicorn_32 9223372036854775807 1 q-1 0,100,100,0 9608 2:2810
RACE unicorn_32 9223372036854775807 1 q-1 50,100,0 9608 1:2810
RACE unicorn_32 9223372036854775807 1 one_on_one 0,0,100,0 9481 2:3243
RACE unicorn_32 9223372036854775807 1 one_on_one 100,0,0,0 9481 0:3243
RACE unicorn_32 9223372036854775807 1 one_on_one 0,100,100,0 9481 1:3243
RACE unicorn_32 9223372036854775807 1 one_on_one 50,100,0 9481 1:3243
RACE unicorn_32 9223372036854775807 1 general_knowledge_easy_017 0,0,100,0 9631 2:2992
RACE unicorn_32 9223372036854775807 1 general_knowledge_easy_017 100,0,0,0 9631 0:2992
RACE unicorn_32 9223372036854775807 1 general_knowledge_easy_017 0,100,100,0 9631 1:2992
RACE unicorn_32 9223372036854775807 1 general_knowledge_easy_017 50,100,0 9631 1:2992
RACE unicorn_32 9223372036854775807 1 kids_arithmetic_9 0,0,100,0 8567 2:3035
RACE unicorn_32 9223372036854775807 1 kids_arithmetic_9 100,0,0,0 8567 0:3035
RACE unicorn_32 9223372036854775807 1 kids_arithmetic_9 0,100,100,0 8567 1:3035
RACE unicorn_32 9223372036854775807 1 kids_arithmetic_9 50,100,0 8567 1:3035
RACE unicorn_32 9223372036854775807 41 q-1 0,0,100,0 9021 2:3035
RACE unicorn_32 9223372036854775807 41 q-1 100,0,0,0 9021 0:3035
RACE unicorn_32 9223372036854775807 41 q-1 0,100,100,0 9021 1:3035
RACE unicorn_32 9223372036854775807 41 q-1 50,100,0 9021 1:3035
RACE unicorn_32 9223372036854775807 41 one_on_one 0,0,100,0 10055 2:3453
RACE unicorn_32 9223372036854775807 41 one_on_one 100,0,0,0 10055 0:3453
RACE unicorn_32 9223372036854775807 41 one_on_one 0,100,100,0 10055 1:3453
RACE unicorn_32 9223372036854775807 41 one_on_one 50,100,0 10055 1:3453
RACE unicorn_32 9223372036854775807 41 general_knowledge_easy_017 0,0,100,0 10115 2:3163
RACE unicorn_32 9223372036854775807 41 general_knowledge_easy_017 100,0,0,0 10115 0:3163
RACE unicorn_32 9223372036854775807 41 general_knowledge_easy_017 0,100,100,0 10115 2:3163
RACE unicorn_32 9223372036854775807 41 general_knowledge_easy_017 50,100,0 10115 1:3163
RACE unicorn_32 9223372036854775807 41 kids_arithmetic_9 0,0,100,0 9239 3:2791;2:1994
RACE unicorn_32 9223372036854775807 41 kids_arithmetic_9 100,0,0,0 9239 3:2791;0:1994
RACE unicorn_32 9223372036854775807 41 kids_arithmetic_9 0,100,100,0 9239 3:2791;2:1994
RACE unicorn_32 9223372036854775807 41 kids_arithmetic_9 50,100,0 9239 0:2791;1:1994
RACE unicorn_32 -9223372036854775808 1 q-1 0,0,100,0 10104 2:2789
RACE unicorn_32 -9223372036854775808 1 q-1 100,0,0,0 10104 0:2789
RACE unicorn_32 -9223372036854775808 1 q-1 0,100,100,0 10104 1:2789
RACE unicorn_32 -9223372036854775808 1 q-1 50,100,0 10104 1:2789
RACE unicorn_32 -9223372036854775808 1 one_on_one 0,0,100,0 9973 2:2749
RACE unicorn_32 -9223372036854775808 1 one_on_one 100,0,0,0 9973 0:2749
RACE unicorn_32 -9223372036854775808 1 one_on_one 0,100,100,0 9973 1:2749
RACE unicorn_32 -9223372036854775808 1 one_on_one 50,100,0 9973 1:2749
RACE unicorn_32 -9223372036854775808 1 general_knowledge_easy_017 0,0,100,0 8652 1:2847;2:2272
RACE unicorn_32 -9223372036854775808 1 general_knowledge_easy_017 100,0,0,0 8652 1:2847;0:2272
RACE unicorn_32 -9223372036854775808 1 general_knowledge_easy_017 0,100,100,0 8652 1:2847
RACE unicorn_32 -9223372036854775808 1 general_knowledge_easy_017 50,100,0 8652 0:2847;1:2272
RACE unicorn_32 -9223372036854775808 1 kids_arithmetic_9 0,0,100,0 8665 2:2977
RACE unicorn_32 -9223372036854775808 1 kids_arithmetic_9 100,0,0,0 8665 2:2977;1:2354;0:1987
RACE unicorn_32 -9223372036854775808 1 kids_arithmetic_9 0,100,100,0 8665 2:2977
RACE unicorn_32 -9223372036854775808 1 kids_arithmetic_9 50,100,0 8665 0:2977;2:2354;1:2046
RACE unicorn_32 -9223372036854775808 41 q-1 0,0,100,0 8968 2:3092
RACE unicorn_32 -9223372036854775808 41 q-1 100,0,0,0 8968 0:3092
RACE unicorn_32 -9223372036854775808 41 q-1 0,100,100,0 8968 1:3092
RACE unicorn_32 -9223372036854775808 41 q-1 50,100,0 8968 1:3092
RACE unicorn_32 -9223372036854775808 41 one_on_one 0,0,100,0 9001 1:2812;2:1952
RACE unicorn_32 -9223372036854775808 41 one_on_one 100,0,0,0 9001 2:2812;0:1952
RACE unicorn_32 -9223372036854775808 41 one_on_one 0,100,100,0 9001 0:2812;1:1952
RACE unicorn_32 -9223372036854775808 41 one_on_one 50,100,0 9001 0:2812;1:1952
RACE unicorn_32 -9223372036854775808 41 general_knowledge_easy_017 0,0,100,0 9382 2:3414
RACE unicorn_32 -9223372036854775808 41 general_knowledge_easy_017 100,0,0,0 9382 0:3414
RACE unicorn_32 -9223372036854775808 41 general_knowledge_easy_017 0,100,100,0 9382 2:3414
RACE unicorn_32 -9223372036854775808 41 general_knowledge_easy_017 50,100,0 9382 1:3414
RACE unicorn_32 -9223372036854775808 41 kids_arithmetic_9 0,0,100,0 9176 2:3453
RACE unicorn_32 -9223372036854775808 41 kids_arithmetic_9 100,0,0,0 9176 0:3453
RACE unicorn_32 -9223372036854775808 41 kids_arithmetic_9 0,100,100,0 9176 1:3453
RACE unicorn_32 -9223372036854775808 41 kids_arithmetic_9 50,100,0 9176 1:3453
RACE coach_67 0 1 q-1 0,0,100,0 8455 2:2897
RACE coach_67 0 1 q-1 100,0,0,0 8455 0:2897
RACE coach_67 0 1 q-1 0,100,100,0 8455 2:2897
RACE coach_67 0 1 q-1 50,100,0 8455 1:2897
RACE coach_67 0 1 one_on_one 0,0,100,0 9349 2:2367
RACE coach_67 0 1 one_on_one 100,0,0,0 9349 0:2367
RACE coach_67 0 1 one_on_one 0,100,100,0 9349 1:2367
RACE coach_67 0 1 one_on_one 50,100,0 9349 1:2367
RACE coach_67 0 1 general_knowledge_easy_017 0,0,100,0 8100 3:3071;2:2057
RACE coach_67 0 1 general_knowledge_easy_017 100,0,0,0 8100 3:3071;0:2057
RACE coach_67 0 1 general_knowledge_easy_017 0,100,100,0 8100 0:3071;1:2057
RACE coach_67 0 1 general_knowledge_easy_017 50,100,0 8100 0:3071;1:2057
RACE coach_67 0 1 kids_arithmetic_9 0,0,100,0 8830 2:2364
RACE coach_67 0 1 kids_arithmetic_9 100,0,0,0 8830 0:2364
RACE coach_67 0 1 kids_arithmetic_9 0,100,100,0 8830 1:2364
RACE coach_67 0 1 kids_arithmetic_9 50,100,0 8830 1:2364
RACE coach_67 0 41 q-1 0,0,100,0 7922 2:2443
RACE coach_67 0 41 q-1 100,0,0,0 7922 0:2443
RACE coach_67 0 41 q-1 0,100,100,0 7922 1:2443
RACE coach_67 0 41 q-1 50,100,0 7922 1:2443
RACE coach_67 0 41 one_on_one 0,0,100,0 8643 2:2878
RACE coach_67 0 41 one_on_one 100,0,0,0 8643 0:2878
RACE coach_67 0 41 one_on_one 0,100,100,0 8643 2:2878
RACE coach_67 0 41 one_on_one 50,100,0 8643 1:2878
RACE coach_67 0 41 general_knowledge_easy_017 0,0,100,0 9032 1:2585;2:1758
RACE coach_67 0 41 general_knowledge_easy_017 100,0,0,0 9032 2:2585;0:1758
RACE coach_67 0 41 general_knowledge_easy_017 0,100,100,0 9032 3:2585;1:1758
RACE coach_67 0 41 general_knowledge_easy_017 50,100,0 9032 2:2585;1:1758
RACE coach_67 0 41 kids_arithmetic_9 0,0,100,0 8555 2:2980
RACE coach_67 0 41 kids_arithmetic_9 100,0,0,0 8555 0:2980
RACE coach_67 0 41 kids_arithmetic_9 0,100,100,0 8555 1:2980
RACE coach_67 0 41 kids_arithmetic_9 50,100,0 8555 1:2980
RACE coach_67 1700000000123 1 q-1 0,0,100,0 9637 3:2371;2:1941
RACE coach_67 1700000000123 1 q-1 100,0,0,0 9637 3:2371;0:1941
RACE coach_67 1700000000123 1 q-1 0,100,100,0 9637 0:2371;1:1941
RACE coach_67 1700000000123 1 q-1 50,100,0 9637 0:2371;1:1941
RACE coach_67 1700000000123 1 one_on_one 0,0,100,0 9323 2:3136
RACE coach_67 1700000000123 1 one_on_one 100,0,0,0 9323 0:3136
RACE coach_67 1700000000123 1 one_on_one 0,100,100,0 9323 2:3136
RACE coach_67 1700000000123 1 one_on_one 50,100,0 9323 1:3136
RACE coach_67 1700000000123 1 general_knowledge_easy_017 0,0,100,0 9141 2:2934
RACE coach_67 1700000000123 1 general_knowledge_easy_017 100,0,0,0 9141 0:2934
RACE coach_67 1700000000123 1 general_knowledge_easy_017 0,100,100,0 9141 2:2934
RACE coach_67 1700000000123 1 general_knowledge_easy_017 50,100,0 9141 1:2934
RACE coach_67 1700000000123 1 kids_arithmetic_9 0,0,100,0 8398 3:2572;2:1834
RACE coach_67 1700000000123 1 kids_arithmetic_9 100,0,0,0 8398 3:2572;0:1834
RACE coach_67 1700000000123 1 kids_arithmetic_9 0,100,100,0 8398 0:2572;2:1834
RACE coach_67 1700000000123 1 kids_arithmetic_9 50,100,0 8398 0:2572;1:1834
RACE coach_67 1700000000123 41 q-1 0,0,100,0 8511 2:2509
RACE coach_67 1700000000123 41 q-1 100,0,0,0 8511 0:2509
RACE coach_67 1700000000123 41 q-1 0,100,100,0 8511 2:2509
RACE coach_67 1700000000123 41 q-1 50,100,0 8511 1:2509
RACE coach_67 1700000000123 41 one_on_one 0,0,100,0 8895 2:2768
RACE coach_67 1700000000123 41 one_on_one 100,0,0,0 8895 0:2768
RACE coach_67 1700000000123 41 one_on_one 0,100,100,0 8895 1:2768
RACE coach_67 1700000000123 41 one_on_one 50,100,0 8895 1:2768
RACE coach_67 1700000000123 41 general_knowledge_easy_017 0,0,100,0 9039 2:2760
RACE coach_67 1700000000123 41 general_knowledge_easy_017 100,0,0,0 9039 0:2760
RACE coach_67 1700000000123 41 general_knowledge_easy_017 0,100,100,0 9039 1:2760
RACE coach_67 1700000000123 41 general_knowledge_easy_017 50,100,0 9039 1:2760
RACE coach_67 1700000000123 41 kids_arithmetic_9 0,0,100,0 8481 2:2723
RACE coach_67 1700000000123 41 kids_arithmetic_9 100,0,0,0 8481 0:2723
RACE coach_67 1700000000123 41 kids_arithmetic_9 0,100,100,0 8481 1:2723
RACE coach_67 1700000000123 41 kids_arithmetic_9 50,100,0 8481 1:2723
RACE coach_67 9223372036854775807 1 q-1 0,0,100,0 9079 2:2401
RACE coach_67 9223372036854775807 1 q-1 100,0,0,0 9079 0:2401
RACE coach_67 9223372036854775807 1 q-1 0,100,100,0 9079 2:2401
RACE coach_67 9223372036854775807 1 q-1 50,100,0 9079 1:2401
RACE coach_67 9223372036854775807 1 one_on_one 0,0,100,0 8952 2:2834
RACE coach_67 9223372036854775807 1 one_on_one 100,0,0,0 8952 0:2834
RACE coach_67 9223372036854775807 1 one_on_one 0,100,100,0 8952 1:2834
RACE coach_67 9223372036854775807 1 one_on_one 50,100,0 8952 1:2834
RACE coach_67 9223372036854775807 1 general_knowledge_easy_017 0,0,100,0 9102 2:2583
RACE coach_67 9223372036854775807 1 general_knowledge_easy_017 100,0,0,0 9102 0:2583
RACE coach_67 9223372036854775807 1 general_knowledge_easy_017 0,100,100,0 9102 1:2583
RACE coach_67 9223372036854775807 1 general_knowledge_easy_017 50,100,0 9102 1:2583
RACE coach_67 9223372036854775807 1 kids_arithmetic_9 0,0,100,0 8038 2:2626
RACE coach_67 9223372036854775807 1 kids_arithmetic_9 100,0,0,0 8038 0:2626
RACE coach_67 9223372036854775807 1 kids_arithmetic_9 0,100,100,0 8038 1:2626
RACE coach_67 9223372036854775807 1 kids_arithmetic_9 50,100,0 8038 1:2626
RACE coach_67 9223372036854775807 41 q-1 0,0,100,0 8492 2:2626
RACE coach_67 9223372036854775807 41 q-1 100,0,0,0 8492 0:2626
RACE coach_67 9223372036854775807 41 q-1 0,100,100,0 8492 1:2626
RACE coach_67 9223372036854775807 41 q-1 50,100,0 8492 1:2626
RACE coach_67 9223372036854775807 41 one_on_one 0,0,100,0 9526 2:3044
RACE coach_67 9223372036854775807 41 one_on_one 100,0,0,0 9526 0:3044
RACE coach_67 9223372036854775807 41 one_on_one 0,100,100,0 9526 1:3044
RACE coach_67 9223372036854775807 41 one_on_one 50,100,0 9526 1:3044
RACE coach_67 9223372036854775807 41 general_knowledge_easy_017 0,0,100,0 9586 0:2744;2:2132
RACE coach_67 9223372036854775807 41 general_knowledge_easy_017 100,0,0,0 9586 0:2744
RACE coach_67 9223372036854775807 41 general_knowledge_easy_017 0,100,100,0 9586 0:2744;1:2132
RACE coach_67 9223372036854775807 41 general_knowledge_easy_017 50,100,0 9586 2:2744;1:2132
RACE coach_67 9223372036854775807 41 kids_arithmetic_9 0,0,100,0 8710 3:2382;2:1786
RACE coach_67 9223372036854775807 41 kids_arithmetic_9 100,0,0,0 8710 3:2382;0:1786
RACE coach_67 9223372036854775807 41 kids_arithmetic_9 0,100,100,0 8710 3:2382;2:1786
RACE coach_67 9223372036854775807 41 kids_arithmetic_9 50,100,0 8710 0:2382;1:1786
RACE coach_67 -9223372036854775808 1 q-1 0,0,100,0 9575 2:2380
RACE coach_67 -9223372036854775808 1 q-1 100,0,0,0 9575 0:2380
RACE coach_67 -9223372036854775808 1 q-1 0,100,100,0 9575 1:2380
RACE coach_67 -9223372036854775808 1 q-1 50,100,0 9575 1:2380
RACE coach_67 -9223372036854775808 1 one_on_one 0,0,100,0 9444 2:2340
RACE coach_67 -9223372036854775808 1 one_on_one 100,0,0,0 9444 0:2340
RACE coach_67 -9223372036854775808 1 one_on_one 0,100,100,0 9444 1:2340
RACE coach_67 -9223372036854775808 1 one_on_one 50,100,0 9444 1:2340
RACE coach_67 -9223372036854775808 1 general_knowledge_easy_017 0,0,100,0 8123 1:2438;2:2064
RACE coach_67 -9223372036854775808 1 general_knowledge_easy_017 100,0,0,0 8123 1:2438;0:2064
RACE coach_67 -9223372036854775808 1 general_knowledge_easy_017 0,100,100,0 8123 1:2438
RACE coach_67 -9223372036854775808 1 general_knowledge_easy_017 50,100,0 8123 0:2438;1:2064
RACE coach_67 -9223372036854775808 1 kids_arithmetic_9 0,0,100,0 8136 2:2568
RACE coach_67 -9223372036854775808 1 kids_arithmetic_9 100,0,0,0 8136 2:2568;1:2146;0:1779
RACE coach_67 -9223372036854775808 1 kids_arithmetic_9 0,100,100,0 8136 2:2568
RACE coach_67 -9223372036854775808 1 kids_arithmetic_9 50,100,0 8136 0:2568;2:2146;1:1838
RACE coach_67 -9223372036854775808 41 q-1 0,0,100,0 8439 2:2683
RACE coach_67 -9223372036854775808 41 q-1 100,0,0,0 8439 0:2683
RACE coach_67 -9223372036854775808 41 q-1 0,100,100,0 8439 1:2683
RACE coach_67 -9223372036854775808 41 q-1 50,100,0 8439 1:2683
RACE coach_67 -9223372036854775808 41 one_on_one 0,0,100,0 8472 1:2403;2:1744
RACE coach_67 -9223372036854775808 41 one_on_one 100,0,0,0 8472 2:2403;0:1744
RACE coach_67 -9223372036854775808 41 one_on_one 0,100,100,0 8472 0:2403;1:1744
RACE coach_67 -9223372036854775808 41 one_on_one 50,100,0 8472 0:2403;1:1744
RACE coach_67 -9223372036854775808 41 general_knowledge_easy_017 0,0,100,0 8853 2:3005
RACE coach_67 -9223372036854775808 41 general_knowledge_easy_017 100,0,0,0 8853 0:3005
RACE coach_67 -9223372036854775808 41 general_knowledge_easy_017 0,100,100,0 8853 2:3005
RACE coach_67 -9223372036854775808 41 general_knowledge_easy_017 50,100,0 8853 1:3005
RACE coach_67 -9223372036854775808 41 kids_arithmetic_9 0,0,100,0 8647 2:3044
RACE coach_67 -9223372036854775808 41 kids_arithmetic_9 100,0,0,0 8647 0:3044
RACE coach_67 -9223372036854775808 41 kids_arithmetic_9 0,100,100,0 8647 1:3044
RACE coach_67 -9223372036854775808 41 kids_arithmetic_9 50,100,0 8647 1:3044
RACE zephyr 0 1 q-1 0,0,100,0 6688 2:1668
RACE zephyr 0 1 q-1 100,0,0,0 6688 0:1668
RACE zephyr 0 1 q-1 0,100,100,0 6688 2:1668
RACE zephyr 0 1 q-1 50,100,0 6688 1:1668
RACE zephyr 0 1 one_on_one 0,0,100,0 7582 2:1138
RACE zephyr 0 1 one_on_one 100,0,0,0 7582 0:1138
RACE zephyr 0 1 one_on_one 0,100,100,0 7582 1:1138
RACE zephyr 0 1 one_on_one 50,100,0 7582 1:1138
RACE zephyr 0 1 general_knowledge_easy_017 0,0,100,0 6333 3:1842;2:1433
RACE zephyr 0 1 general_knowledge_easy_017 100,0,0,0 6333 3:1842;0:1433
RACE zephyr 0 1 general_knowledge_easy_017 0,100,100,0 6333 0:1842;1:1433
RACE zephyr 0 1 general_knowledge_easy_017 50,100,0 6333 0:1842;1:1433
RACE zephyr 0 1 kids_arithmetic_9 0,0,100,0 7063 2:1135
RACE zephyr 0 1 kids_arithmetic_9 100,0,0,0 7063 0:1135
RACE zephyr 0 1 kids_arithmetic_9 0,100,100,0 7063 1:1135
RACE zephyr 0 1 kids_arithmetic_9 50,100,0 7063 1:1135
RACE zephyr 0 41 q-1 0,0,100,0 6155 2:1214
RACE zephyr 0 41 q-1 100,0,0,0 6155 0:1214
RACE zephyr 0 41 q-1 0,100,100,0 6155 1:1214
RACE zephyr 0 41 q-1 50,100,0 6155 1:1214
RACE zephyr 0 41 one_on_one 0,0,100,0 6876 2:1649
RACE zephyr 0 41 one_on_one 100,0,0,0 6876 0:1649
RACE zephyr 0 41 one_on_one 0,100,100,0 6876 2:1649
RACE zephyr 0 41 one_on_one 50,100,0 6876 1:1649
RACE zephyr 0 41 general_knowledge_easy_017 0,0,100,0 7265 1:1356;2:1134
RACE zephyr 0 41 general_knowledge_easy_017 100,0,0,0 7265 2:1356;0:1134
RACE zephyr 0 41 general_knowledge_easy_017 0,100,100,0 7265 3:1356;1:1134
RACE zephyr 0 41 general_knowledge_easy_017 50,100,0 7265 2:1356;1:1134
RACE zephyr 0 41 kids_arithmetic_9 0,0,100,0 6788 2:1751
RACE zephyr 0 41 kids_arithmetic_9 100,0,0,0 6788 0:1751
RACE zephyr 0 41 kids_arithmetic_9 0,100,100,0 6788 1:1751
RACE zephyr 0 41 kids_arithmetic_9 50,100,0 6788 1:1751
RACE zephyr 1700000000123 1 q-1 0,0,100,0 7870 3:1142;2:1317
RACE zephyr 1700000000123 1 q-1 100,0,0,0 7870 3:1142;0:1317
RACE zephyr 1700000000123 1 q-1 0,100,100,0 7870 0:1142;1:1317
RACE zephyr 1700000000123 1 q-1 50,100,0 7870 0:1142;1:1317
RACE zephyr 1700000000123 1 one_on_one 0,0,100,0 7556 2:1907
RACE zephyr 1700000000123 1 one_on_one 100,0,0,0 7556 0:1907
RACE zephyr 1700000000123 1 one_on_one 0,100,100,0 7556 2:1907
RACE zephyr 1700000000123 1 one_on_one 50,100,0 7556 1:1907
RACE zephyr 1700000000123 1 general_knowledge_easy_017 0,0,100,0 7374 2:1705
RACE zephyr 1700000000123 1 general_knowledge_easy_017 100,0,0,0 7374 0:1705
RACE zephyr 1700000000123 1 general_knowledge_easy_017 0,100,100,0 7374 2:1705
RACE zephyr 1700000000123 1 general_knowledge_easy_017 50,100,0 7374 1:1705
RACE zephyr 1700000000123 1 kids_arithmetic_9 0,0,100,0 6631 3:1343;2:1210
RACE zephyr 1700000000123 1 kids_arithmetic_9 100,0,0,0 6631 3:1343;0:1210
RACE zephyr 1700000000123 1 kids_arithmetic_9 0,100,100,0 6631 0:1343;2:1210
RACE zephyr 1700000000123 1 kids_arithmetic_9 50,100,0 6631 0:1343;1:1210
RACE zephyr 1700000000123 41 q-1 0,0,100,0 6744 2:1280
RACE zephyr 1700000000123 41 q-1 100,0,0,0 6744 0:1280
RACE zephyr 1700000000123 41 q-1 0,100,100,0 6744 2:1280
RACE zephyr 1700000000123 41 q-1 50,100,0 6744 1:1280
RACE zephyr 1700000000123 41 one_on_one 0,0,100,0 7128 2:1539
RACE zephyr 1700000000123 41 one_on_one 100,0,0,0 7128 0:1539
RACE zephyr 1700000000123 41 one_on_one 0,100,100,0 7128 1:1539
RACE zephyr 1700000000123 41 one_on_one 50,100,0 7128 1:1539
RACE zephyr 1700000000123 41 general_knowledge_easy_017 0,0,100,0 7272 3:1531;2:1403
RACE zephyr 1700000000123 41 general_knowledge_easy_017 100,0,0,0 7272 3:1531;2:1403;0:1203
RACE zephyr 1700000000123 41 general_knowledge_easy_017 0,100,100,0 7272 0:1531;3:1403;2:1293
RACE zephyr 1700000000123 41 general_knowledge_easy_017 50,100,0 7272 0:1531;2:1403;1:1293
RACE zephyr 1700000000123 41 kids_arithmetic_9 0,0,100,0 6714 2:1494
RACE zephyr 1700000000123 41 kids_arithmetic_9 100,0,0,0 6714 0:1494
RACE zephyr 1700000000123 41 kids_arithmetic_9 0,100,100,0 6714 1:1494
RACE zephyr 1700000000123 41 kids_arithmetic_9 50,100,0 6714 1:1494
RACE zephyr 9223372036854775807 1 q-1 0,0,100,0 7312 2:1172
RACE zephyr 9223372036854775807 1 q-1 100,0,0,0 7312 0:1172
RACE zephyr 9223372036854775807 1 q-1 0,100,100,0 7312 2:1172
RACE zephyr 9223372036854775807 1 q-1 50,100,0 7312 1:1172
RACE zephyr 9223372036854775807 1 one_on_one 0,0,100,0 7185 0:1214;1:1515;2:1583
RACE zephyr 9223372036854775807 1 one_on_one 100,0,0,0 7185 0:1214
RACE zephyr 9223372036854775807 1 one_on_one 0,100,100,0 7185 0:1214;3:1515;1:1235
RACE zephyr 9223372036854775807 1 one_on_one 50,100,0 7185 0:1214;2:1515;1:1235
RACE zephyr 9223372036854775807 1 general_knowledge_easy_017 0,0,100,0 7335 2:1354
RACE zephyr 9223372036854775807 1 general_knowledge_easy_017 100,0,0,0 7335 0:1354
RACE zephyr 9223372036854775807 1 general_knowledge_easy_017 0,100,100,0 7335 1:1354
RACE zephyr 9223372036854775807 1 general_knowledge_easy_017 50,100,0 7335 1:1354
RACE zephyr 9223372036854775807 1 kids_arithmetic_9 0,0,100,0 6271 2:1397
RACE zephyr 9223372036854775807 1 kids_arithmetic_9 100,0,0,0 6271 0:1397
RACE zephyr 9223372036854775807 1 kids_arithmetic_9 0,100,100,0 6271 1:1397
RACE zephyr 9223372036854775807 1 kids_arithmetic_9 50,100,0 6271 1:1397
RACE zephyr 9223372036854775807 41 q-1 0,0,100,0 6725 2:1397
RACE zephyr 9223372036854775807 41 q-1 100,0,0,0 6725 0:1397
RACE zephyr 9223372036854775807 41 q-1 0,100,100,0 6725 1:1397
RACE zephyr 9223372036854775807 41 q-1 50,100,0 6725 1:1397
RACE zephyr 9223372036854775807 41 one_on_one 0,0,100,0 7759 1:1675;2:1433
RACE zephyr 9223372036854775807 41 one_on_one 100,0,0,0 7759 1:1675;0:1433
RACE zephyr 9223372036854775807 41 one_on_one 0,100,100,0 7759 1:1675
RACE zephyr 9223372036854775807 41 one_on_one 50,100,0 7759 0:1675;1:1433
RACE zephyr 9223372036854775807 41 general_knowledge_easy_017 0,0,100,0 7819 0:1515;2:1508
RACE zephyr 9223372036854775807 41 general_knowledge_easy_017 100,0,0,0 7819 0:1515
RACE zephyr 9223372036854775807 41 general_knowledge_easy_017 0,100,100,0 7819 0:1515;1:1508
RACE zephyr 9223372036854775807 41 general_knowledge_easy_017 50,100,0 7819 2:1515;1:1508
RACE zephyr 9223372036854775807 41 kids_arithmetic_9 0,0,100,0 6943 3:1153;1:1299;2:1208
RACE zephyr 9223372036854775807 41 kids_arithmetic_9 100,0,0,0 6943 3:1153;1:1299;0:1208
RACE zephyr 9223372036854775807 41 kids_arithmetic_9 0,100,100,0 6943 3:1153;1:1299
RACE zephyr 9223372036854775807 41 kids_arithmetic_9 50,100,0 6943 0:1153;2:1299;1:1620
RACE zephyr -9223372036854775808 1 q-1 0,0,100,0 7808 2:1151
RACE zephyr -9223372036854775808 1 q-1 100,0,0,0 7808 0:1151
RACE zephyr -9223372036854775808 1 q-1 0,100,100,0 7808 1:1151
RACE zephyr -9223372036854775808 1 q-1 50,100,0 7808 1:1151
RACE zephyr -9223372036854775808 1 one_on_one 0,0,100,0 7677 2:1111
RACE zephyr -9223372036854775808 1 one_on_one 100,0,0,0 7677 0:1111
RACE zephyr -9223372036854775808 1 one_on_one 0,100,100,0 7677 1:1111
RACE zephyr -9223372036854775808 1 one_on_one 50,100,0 7677 1:1111
RACE zephyr -9223372036854775808 1 general_knowledge_easy_017 0,0,100,0 6356 1:1209;2:1440
RACE zephyr -9223372036854775808 1 general_knowledge_easy_017 100,0,0,0 6356 1:1209;0:1440
RACE zephyr -9223372036854775808 1 general_knowledge_easy_017 0,100,100,0 6356 1:1209
RACE zephyr -9223372036854775808 1 general_knowledge_easy_017 50,100,0 6356 0:1209;1:1440
RACE zephyr -9223372036854775808 1 kids_arithmetic_9 0,0,100,0 6369 2:1339
RACE zephyr -9223372036854775808 1 kids_arithmetic_9 100,0,0,0 6369 2:1339;1:1522;3:1658;0:1390
RACE zephyr -9223372036854775808 1 kids_arithmetic_9 0,100,100,0 6369 2:1339
RACE zephyr -9223372036854775808 1 kids_arithmetic_9 50,100,0 6369 0:1339;2:1522;1:1214
RACE zephyr -9223372036854775808 41 q-1 0,0,100,0 6672 2:1454
RACE zephyr -9223372036854775808 41 q-1 100,0,0,0 6672 0:1454
RACE zephyr -9223372036854775808 41 q-1 0,100,100,0 6672 1:1454
RACE zephyr -9223372036854775808 41 q-1 50,100,0 6672 1:1454
RACE zephyr -9223372036854775808 41 one_on_one 0,0,100,0 6705 1:1174;2:1120
RACE zephyr -9223372036854775808 41 one_on_one 100,0,0,0 6705 2:1174;0:1120
RACE zephyr -9223372036854775808 41 one_on_one 0,100,100,0 6705 0:1174;1:1120
RACE zephyr -9223372036854775808 41 one_on_one 50,100,0 6705 0:1174;1:1120
RACE zephyr -9223372036854775808 41 general_knowledge_easy_017 0,0,100,0 7086 2:1776
RACE zephyr -9223372036854775808 41 general_knowledge_easy_017 100,0,0,0 7086 0:1776
RACE zephyr -9223372036854775808 41 general_knowledge_easy_017 0,100,100,0 7086 2:1776
RACE zephyr -9223372036854775808 41 general_knowledge_easy_017 50,100,0 7086 1:1776
RACE zephyr -9223372036854775808 41 kids_arithmetic_9 0,0,100,0 6880 2:1815
RACE zephyr -9223372036854775808 41 kids_arithmetic_9 100,0,0,0 6880 0:1815
RACE zephyr -9223372036854775808 41 kids_arithmetic_9 0,100,100,0 6880 1:1815
RACE zephyr -9223372036854775808 41 kids_arithmetic_9 50,100,0 6880 1:1815
RACE kyra 0 1 q-1 0,0,100,0 6688 2:1668
RACE kyra 0 1 q-1 100,0,0,0 6688 0:1668
RACE kyra 0 1 q-1 0,100,100,0 6688 2:1668
RACE kyra 0 1 q-1 50,100,0 6688 1:1668
RACE kyra 0 1 one_on_one 0,0,100,0 7582 2:1138
RACE kyra 0 1 one_on_one 100,0,0,0 7582 0:1138
RACE kyra 0 1 one_on_one 0,100,100,0 7582 1:1138
RACE kyra 0 1 one_on_one 50,100,0 7582 1:1138
RACE kyra 0 1 general_knowledge_easy_017 0,0,100,0 6333 3:1842;2:1433
RACE kyra 0 1 general_knowledge_easy_017 100,0,0,0 6333 3:1842;0:1433
RACE kyra 0 1 general_knowledge_easy_017 0,100,100,0 6333 0:1842;1:1433
RACE kyra 0 1 general_knowledge_easy_017 50,100,0 6333 0:1842;1:1433
RACE kyra 0 1 kids_arithmetic_9 0,0,100,0 7063 2:1135
RACE kyra 0 1 kids_arithmetic_9 100,0,0,0 7063 0:1135
RACE kyra 0 1 kids_arithmetic_9 0,100,100,0 7063 1:1135
RACE kyra 0 1 kids_arithmetic_9 50,100,0 7063 1:1135
RACE kyra 0 41 q-1 0,0,100,0 6155 2:1214
RACE kyra 0 41 q-1 100,0,0,0 6155 0:1214
RACE kyra 0 41 q-1 0,100,100,0 6155 1:1214
RACE kyra 0 41 q-1 50,100,0 6155 1:1214
RACE kyra 0 41 one_on_one 0,0,100,0 6876 2:1649
RACE kyra 0 41 one_on_one 100,0,0,0 6876 0:1649
RACE kyra 0 41 one_on_one 0,100,100,0 6876 2:1649
RACE kyra 0 41 one_on_one 50,100,0 6876 1:1649
RACE kyra 0 41 general_knowledge_easy_017 0,0,100,0 7265 1:1356;2:1134
RACE kyra 0 41 general_knowledge_easy_017 100,0,0,0 7265 2:1356;0:1134
RACE kyra 0 41 general_knowledge_easy_017 0,100,100,0 7265 3:1356;1:1134
RACE kyra 0 41 general_knowledge_easy_017 50,100,0 7265 2:1356;1:1134
RACE kyra 0 41 kids_arithmetic_9 0,0,100,0 6788 2:1751
RACE kyra 0 41 kids_arithmetic_9 100,0,0,0 6788 0:1751
RACE kyra 0 41 kids_arithmetic_9 0,100,100,0 6788 1:1751
RACE kyra 0 41 kids_arithmetic_9 50,100,0 6788 1:1751
RACE kyra 1700000000123 1 q-1 0,0,100,0 7870 3:1142;2:1317
RACE kyra 1700000000123 1 q-1 100,0,0,0 7870 3:1142;0:1317
RACE kyra 1700000000123 1 q-1 0,100,100,0 7870 0:1142;1:1317
RACE kyra 1700000000123 1 q-1 50,100,0 7870 0:1142;1:1317
RACE kyra 1700000000123 1 one_on_one 0,0,100,0 7556 2:1907
RACE kyra 1700000000123 1 one_on_one 100,0,0,0 7556 0:1907
RACE kyra 1700000000123 1 one_on_one 0,100,100,0 7556 2:1907
RACE kyra 1700000000123 1 one_on_one 50,100,0 7556 1:1907
RACE kyra 1700000000123 1 general_knowledge_easy_017 0,0,100,0 7374 2:1705
RACE kyra 1700000000123 1 general_knowledge_easy_017 100,0,0,0 7374 0:1705
RACE kyra 1700000000123 1 general_knowledge_easy_017 0,100,100,0 7374 2:1705
RACE kyra 1700000000123 1 general_knowledge_easy_017 50,100,0 7374 1:1705
RACE kyra 1700000000123 1 kids_arithmetic_9 0,0,100,0 6631 3:1343;2:1210
RACE kyra 1700000000123 1 kids_arithmetic_9 100,0,0,0 6631 3:1343;0:1210
RACE kyra 1700000000123 1 kids_arithmetic_9 0,100,100,0 6631 0:1343;2:1210
RACE kyra 1700000000123 1 kids_arithmetic_9 50,100,0 6631 0:1343;1:1210
RACE kyra 1700000000123 41 q-1 0,0,100,0 6744 2:1280
RACE kyra 1700000000123 41 q-1 100,0,0,0 6744 0:1280
RACE kyra 1700000000123 41 q-1 0,100,100,0 6744 2:1280
RACE kyra 1700000000123 41 q-1 50,100,0 6744 1:1280
RACE kyra 1700000000123 41 one_on_one 0,0,100,0 7128 2:1539
RACE kyra 1700000000123 41 one_on_one 100,0,0,0 7128 0:1539
RACE kyra 1700000000123 41 one_on_one 0,100,100,0 7128 1:1539
RACE kyra 1700000000123 41 one_on_one 50,100,0 7128 1:1539
RACE kyra 1700000000123 41 general_knowledge_easy_017 0,0,100,0 7272 3:1531;2:1403
RACE kyra 1700000000123 41 general_knowledge_easy_017 100,0,0,0 7272 3:1531;2:1403;0:1203
RACE kyra 1700000000123 41 general_knowledge_easy_017 0,100,100,0 7272 0:1531;3:1403;2:1293
RACE kyra 1700000000123 41 general_knowledge_easy_017 50,100,0 7272 0:1531;2:1403;1:1293
RACE kyra 1700000000123 41 kids_arithmetic_9 0,0,100,0 6714 2:1494
RACE kyra 1700000000123 41 kids_arithmetic_9 100,0,0,0 6714 0:1494
RACE kyra 1700000000123 41 kids_arithmetic_9 0,100,100,0 6714 1:1494
RACE kyra 1700000000123 41 kids_arithmetic_9 50,100,0 6714 1:1494
RACE kyra 9223372036854775807 1 q-1 0,0,100,0 7312 2:1172
RACE kyra 9223372036854775807 1 q-1 100,0,0,0 7312 0:1172
RACE kyra 9223372036854775807 1 q-1 0,100,100,0 7312 2:1172
RACE kyra 9223372036854775807 1 q-1 50,100,0 7312 1:1172
RACE kyra 9223372036854775807 1 one_on_one 0,0,100,0 7185 0:1214;1:1515;2:1583
RACE kyra 9223372036854775807 1 one_on_one 100,0,0,0 7185 0:1214
RACE kyra 9223372036854775807 1 one_on_one 0,100,100,0 7185 0:1214;3:1515;1:1235
RACE kyra 9223372036854775807 1 one_on_one 50,100,0 7185 0:1214;2:1515;1:1235
RACE kyra 9223372036854775807 1 general_knowledge_easy_017 0,0,100,0 7335 2:1354
RACE kyra 9223372036854775807 1 general_knowledge_easy_017 100,0,0,0 7335 0:1354
RACE kyra 9223372036854775807 1 general_knowledge_easy_017 0,100,100,0 7335 1:1354
RACE kyra 9223372036854775807 1 general_knowledge_easy_017 50,100,0 7335 1:1354
RACE kyra 9223372036854775807 1 kids_arithmetic_9 0,0,100,0 6271 2:1397
RACE kyra 9223372036854775807 1 kids_arithmetic_9 100,0,0,0 6271 0:1397
RACE kyra 9223372036854775807 1 kids_arithmetic_9 0,100,100,0 6271 1:1397
RACE kyra 9223372036854775807 1 kids_arithmetic_9 50,100,0 6271 1:1397
RACE kyra 9223372036854775807 41 q-1 0,0,100,0 6725 2:1397
RACE kyra 9223372036854775807 41 q-1 100,0,0,0 6725 0:1397
RACE kyra 9223372036854775807 41 q-1 0,100,100,0 6725 1:1397
RACE kyra 9223372036854775807 41 q-1 50,100,0 6725 1:1397
RACE kyra 9223372036854775807 41 one_on_one 0,0,100,0 7759 1:1675;2:1433
RACE kyra 9223372036854775807 41 one_on_one 100,0,0,0 7759 1:1675;0:1433
RACE kyra 9223372036854775807 41 one_on_one 0,100,100,0 7759 1:1675
RACE kyra 9223372036854775807 41 one_on_one 50,100,0 7759 0:1675;1:1433
RACE kyra 9223372036854775807 41 general_knowledge_easy_017 0,0,100,0 7819 0:1515;2:1508
RACE kyra 9223372036854775807 41 general_knowledge_easy_017 100,0,0,0 7819 0:1515
RACE kyra 9223372036854775807 41 general_knowledge_easy_017 0,100,100,0 7819 0:1515;1:1508
RACE kyra 9223372036854775807 41 general_knowledge_easy_017 50,100,0 7819 2:1515;1:1508
RACE kyra 9223372036854775807 41 kids_arithmetic_9 0,0,100,0 6943 3:1153;1:1299;2:1208
RACE kyra 9223372036854775807 41 kids_arithmetic_9 100,0,0,0 6943 3:1153;1:1299;0:1208
RACE kyra 9223372036854775807 41 kids_arithmetic_9 0,100,100,0 6943 3:1153;1:1299
RACE kyra 9223372036854775807 41 kids_arithmetic_9 50,100,0 6943 0:1153;2:1299;1:1620
RACE kyra -9223372036854775808 1 q-1 0,0,100,0 7808 2:1151
RACE kyra -9223372036854775808 1 q-1 100,0,0,0 7808 0:1151
RACE kyra -9223372036854775808 1 q-1 0,100,100,0 7808 1:1151
RACE kyra -9223372036854775808 1 q-1 50,100,0 7808 1:1151
RACE kyra -9223372036854775808 1 one_on_one 0,0,100,0 7677 2:1111
RACE kyra -9223372036854775808 1 one_on_one 100,0,0,0 7677 0:1111
RACE kyra -9223372036854775808 1 one_on_one 0,100,100,0 7677 1:1111
RACE kyra -9223372036854775808 1 one_on_one 50,100,0 7677 1:1111
RACE kyra -9223372036854775808 1 general_knowledge_easy_017 0,0,100,0 6356 1:1209;2:1440
RACE kyra -9223372036854775808 1 general_knowledge_easy_017 100,0,0,0 6356 1:1209;0:1440
RACE kyra -9223372036854775808 1 general_knowledge_easy_017 0,100,100,0 6356 1:1209
RACE kyra -9223372036854775808 1 general_knowledge_easy_017 50,100,0 6356 0:1209;1:1440
RACE kyra -9223372036854775808 1 kids_arithmetic_9 0,0,100,0 6369 2:1339
RACE kyra -9223372036854775808 1 kids_arithmetic_9 100,0,0,0 6369 2:1339;1:1522;3:1658;0:1390
RACE kyra -9223372036854775808 1 kids_arithmetic_9 0,100,100,0 6369 2:1339
RACE kyra -9223372036854775808 1 kids_arithmetic_9 50,100,0 6369 0:1339;2:1522;1:1214
RACE kyra -9223372036854775808 41 q-1 0,0,100,0 6672 2:1454
RACE kyra -9223372036854775808 41 q-1 100,0,0,0 6672 0:1454
RACE kyra -9223372036854775808 41 q-1 0,100,100,0 6672 1:1454
RACE kyra -9223372036854775808 41 q-1 50,100,0 6672 1:1454
RACE kyra -9223372036854775808 41 one_on_one 0,0,100,0 6705 1:1174;2:1120
RACE kyra -9223372036854775808 41 one_on_one 100,0,0,0 6705 2:1174;0:1120
RACE kyra -9223372036854775808 41 one_on_one 0,100,100,0 6705 0:1174;1:1120
RACE kyra -9223372036854775808 41 one_on_one 50,100,0 6705 0:1174;1:1120
RACE kyra -9223372036854775808 41 general_knowledge_easy_017 0,0,100,0 7086 2:1776
RACE kyra -9223372036854775808 41 general_knowledge_easy_017 100,0,0,0 7086 0:1776
RACE kyra -9223372036854775808 41 general_knowledge_easy_017 0,100,100,0 7086 2:1776
RACE kyra -9223372036854775808 41 general_knowledge_easy_017 50,100,0 7086 1:1776
RACE kyra -9223372036854775808 41 kids_arithmetic_9 0,0,100,0 6880 2:1815
RACE kyra -9223372036854775808 41 kids_arithmetic_9 100,0,0,0 6880 0:1815
RACE kyra -9223372036854775808 41 kids_arithmetic_9 0,100,100,0 6880 1:1815
RACE kyra -9223372036854775808 41 kids_arithmetic_9 50,100,0 6880 1:1815
RACE kyra_original 0 1 q-1 0,0,100,0 6688 2:1668
RACE kyra_original 0 1 q-1 100,0,0,0 6688 0:1668
RACE kyra_original 0 1 q-1 0,100,100,0 6688 2:1668
RACE kyra_original 0 1 q-1 50,100,0 6688 1:1668
RACE kyra_original 0 1 one_on_one 0,0,100,0 7582 2:1138
RACE kyra_original 0 1 one_on_one 100,0,0,0 7582 0:1138
RACE kyra_original 0 1 one_on_one 0,100,100,0 7582 1:1138
RACE kyra_original 0 1 one_on_one 50,100,0 7582 1:1138
RACE kyra_original 0 1 general_knowledge_easy_017 0,0,100,0 6333 3:1842;2:1433
RACE kyra_original 0 1 general_knowledge_easy_017 100,0,0,0 6333 3:1842;0:1433
RACE kyra_original 0 1 general_knowledge_easy_017 0,100,100,0 6333 0:1842;1:1433
RACE kyra_original 0 1 general_knowledge_easy_017 50,100,0 6333 0:1842;1:1433
RACE kyra_original 0 1 kids_arithmetic_9 0,0,100,0 7063 2:1135
RACE kyra_original 0 1 kids_arithmetic_9 100,0,0,0 7063 0:1135
RACE kyra_original 0 1 kids_arithmetic_9 0,100,100,0 7063 1:1135
RACE kyra_original 0 1 kids_arithmetic_9 50,100,0 7063 1:1135
RACE kyra_original 0 41 q-1 0,0,100,0 6155 2:1214
RACE kyra_original 0 41 q-1 100,0,0,0 6155 0:1214
RACE kyra_original 0 41 q-1 0,100,100,0 6155 1:1214
RACE kyra_original 0 41 q-1 50,100,0 6155 1:1214
RACE kyra_original 0 41 one_on_one 0,0,100,0 6876 2:1649
RACE kyra_original 0 41 one_on_one 100,0,0,0 6876 0:1649
RACE kyra_original 0 41 one_on_one 0,100,100,0 6876 2:1649
RACE kyra_original 0 41 one_on_one 50,100,0 6876 1:1649
RACE kyra_original 0 41 general_knowledge_easy_017 0,0,100,0 7265 1:1356;2:1134
RACE kyra_original 0 41 general_knowledge_easy_017 100,0,0,0 7265 2:1356;0:1134
RACE kyra_original 0 41 general_knowledge_easy_017 0,100,100,0 7265 3:1356;1:1134
RACE kyra_original 0 41 general_knowledge_easy_017 50,100,0 7265 2:1356;1:1134
RACE kyra_original 0 41 kids_arithmetic_9 0,0,100,0 6788 2:1751
RACE kyra_original 0 41 kids_arithmetic_9 100,0,0,0 6788 0:1751
RACE kyra_original 0 41 kids_arithmetic_9 0,100,100,0 6788 1:1751
RACE kyra_original 0 41 kids_arithmetic_9 50,100,0 6788 1:1751
RACE kyra_original 1700000000123 1 q-1 0,0,100,0 7870 3:1142;2:1317
RACE kyra_original 1700000000123 1 q-1 100,0,0,0 7870 3:1142;0:1317
RACE kyra_original 1700000000123 1 q-1 0,100,100,0 7870 0:1142;1:1317
RACE kyra_original 1700000000123 1 q-1 50,100,0 7870 0:1142;1:1317
RACE kyra_original 1700000000123 1 one_on_one 0,0,100,0 7556 2:1907
RACE kyra_original 1700000000123 1 one_on_one 100,0,0,0 7556 0:1907
RACE kyra_original 1700000000123 1 one_on_one 0,100,100,0 7556 2:1907
RACE kyra_original 1700000000123 1 one_on_one 50,100,0 7556 1:1907
RACE kyra_original 1700000000123 1 general_knowledge_easy_017 0,0,100,0 7374 2:1705
RACE kyra_original 1700000000123 1 general_knowledge_easy_017 100,0,0,0 7374 0:1705
RACE kyra_original 1700000000123 1 general_knowledge_easy_017 0,100,100,0 7374 2:1705
RACE kyra_original 1700000000123 1 general_knowledge_easy_017 50,100,0 7374 1:1705
RACE kyra_original 1700000000123 1 kids_arithmetic_9 0,0,100,0 6631 3:1343;2:1210
RACE kyra_original 1700000000123 1 kids_arithmetic_9 100,0,0,0 6631 3:1343;0:1210
RACE kyra_original 1700000000123 1 kids_arithmetic_9 0,100,100,0 6631 0:1343;2:1210
RACE kyra_original 1700000000123 1 kids_arithmetic_9 50,100,0 6631 0:1343;1:1210
RACE kyra_original 1700000000123 41 q-1 0,0,100,0 6744 2:1280
RACE kyra_original 1700000000123 41 q-1 100,0,0,0 6744 0:1280
RACE kyra_original 1700000000123 41 q-1 0,100,100,0 6744 2:1280
RACE kyra_original 1700000000123 41 q-1 50,100,0 6744 1:1280
RACE kyra_original 1700000000123 41 one_on_one 0,0,100,0 7128 2:1539
RACE kyra_original 1700000000123 41 one_on_one 100,0,0,0 7128 0:1539
RACE kyra_original 1700000000123 41 one_on_one 0,100,100,0 7128 1:1539
RACE kyra_original 1700000000123 41 one_on_one 50,100,0 7128 1:1539
RACE kyra_original 1700000000123 41 general_knowledge_easy_017 0,0,100,0 7272 3:1531;2:1403
RACE kyra_original 1700000000123 41 general_knowledge_easy_017 100,0,0,0 7272 3:1531;2:1403;0:1203
RACE kyra_original 1700000000123 41 general_knowledge_easy_017 0,100,100,0 7272 0:1531;3:1403;2:1293
RACE kyra_original 1700000000123 41 general_knowledge_easy_017 50,100,0 7272 0:1531;2:1403;1:1293
RACE kyra_original 1700000000123 41 kids_arithmetic_9 0,0,100,0 6714 2:1494
RACE kyra_original 1700000000123 41 kids_arithmetic_9 100,0,0,0 6714 0:1494
RACE kyra_original 1700000000123 41 kids_arithmetic_9 0,100,100,0 6714 1:1494
RACE kyra_original 1700000000123 41 kids_arithmetic_9 50,100,0 6714 1:1494
RACE kyra_original 9223372036854775807 1 q-1 0,0,100,0 7312 2:1172
RACE kyra_original 9223372036854775807 1 q-1 100,0,0,0 7312 0:1172
RACE kyra_original 9223372036854775807 1 q-1 0,100,100,0 7312 2:1172
RACE kyra_original 9223372036854775807 1 q-1 50,100,0 7312 1:1172
RACE kyra_original 9223372036854775807 1 one_on_one 0,0,100,0 7185 0:1214;1:1515;2:1583
RACE kyra_original 9223372036854775807 1 one_on_one 100,0,0,0 7185 0:1214
RACE kyra_original 9223372036854775807 1 one_on_one 0,100,100,0 7185 0:1214;3:1515;1:1235
RACE kyra_original 9223372036854775807 1 one_on_one 50,100,0 7185 0:1214;2:1515;1:1235
RACE kyra_original 9223372036854775807 1 general_knowledge_easy_017 0,0,100,0 7335 2:1354
RACE kyra_original 9223372036854775807 1 general_knowledge_easy_017 100,0,0,0 7335 0:1354
RACE kyra_original 9223372036854775807 1 general_knowledge_easy_017 0,100,100,0 7335 1:1354
RACE kyra_original 9223372036854775807 1 general_knowledge_easy_017 50,100,0 7335 1:1354
RACE kyra_original 9223372036854775807 1 kids_arithmetic_9 0,0,100,0 6271 2:1397
RACE kyra_original 9223372036854775807 1 kids_arithmetic_9 100,0,0,0 6271 0:1397
RACE kyra_original 9223372036854775807 1 kids_arithmetic_9 0,100,100,0 6271 1:1397
RACE kyra_original 9223372036854775807 1 kids_arithmetic_9 50,100,0 6271 1:1397
RACE kyra_original 9223372036854775807 41 q-1 0,0,100,0 6725 2:1397
RACE kyra_original 9223372036854775807 41 q-1 100,0,0,0 6725 0:1397
RACE kyra_original 9223372036854775807 41 q-1 0,100,100,0 6725 1:1397
RACE kyra_original 9223372036854775807 41 q-1 50,100,0 6725 1:1397
RACE kyra_original 9223372036854775807 41 one_on_one 0,0,100,0 7759 1:1675;2:1433
RACE kyra_original 9223372036854775807 41 one_on_one 100,0,0,0 7759 1:1675;0:1433
RACE kyra_original 9223372036854775807 41 one_on_one 0,100,100,0 7759 1:1675
RACE kyra_original 9223372036854775807 41 one_on_one 50,100,0 7759 0:1675;1:1433
RACE kyra_original 9223372036854775807 41 general_knowledge_easy_017 0,0,100,0 7819 0:1515;2:1508
RACE kyra_original 9223372036854775807 41 general_knowledge_easy_017 100,0,0,0 7819 0:1515
RACE kyra_original 9223372036854775807 41 general_knowledge_easy_017 0,100,100,0 7819 0:1515;1:1508
RACE kyra_original 9223372036854775807 41 general_knowledge_easy_017 50,100,0 7819 2:1515;1:1508
RACE kyra_original 9223372036854775807 41 kids_arithmetic_9 0,0,100,0 6943 3:1153;1:1299;2:1208
RACE kyra_original 9223372036854775807 41 kids_arithmetic_9 100,0,0,0 6943 3:1153;1:1299;0:1208
RACE kyra_original 9223372036854775807 41 kids_arithmetic_9 0,100,100,0 6943 3:1153;1:1299
RACE kyra_original 9223372036854775807 41 kids_arithmetic_9 50,100,0 6943 0:1153;2:1299;1:1620
RACE kyra_original -9223372036854775808 1 q-1 0,0,100,0 7808 2:1151
RACE kyra_original -9223372036854775808 1 q-1 100,0,0,0 7808 0:1151
RACE kyra_original -9223372036854775808 1 q-1 0,100,100,0 7808 1:1151
RACE kyra_original -9223372036854775808 1 q-1 50,100,0 7808 1:1151
RACE kyra_original -9223372036854775808 1 one_on_one 0,0,100,0 7677 2:1111
RACE kyra_original -9223372036854775808 1 one_on_one 100,0,0,0 7677 0:1111
RACE kyra_original -9223372036854775808 1 one_on_one 0,100,100,0 7677 1:1111
RACE kyra_original -9223372036854775808 1 one_on_one 50,100,0 7677 1:1111
RACE kyra_original -9223372036854775808 1 general_knowledge_easy_017 0,0,100,0 6356 1:1209;2:1440
RACE kyra_original -9223372036854775808 1 general_knowledge_easy_017 100,0,0,0 6356 1:1209;0:1440
RACE kyra_original -9223372036854775808 1 general_knowledge_easy_017 0,100,100,0 6356 1:1209
RACE kyra_original -9223372036854775808 1 general_knowledge_easy_017 50,100,0 6356 0:1209;1:1440
RACE kyra_original -9223372036854775808 1 kids_arithmetic_9 0,0,100,0 6369 2:1339
RACE kyra_original -9223372036854775808 1 kids_arithmetic_9 100,0,0,0 6369 2:1339;1:1522;3:1658;0:1390
RACE kyra_original -9223372036854775808 1 kids_arithmetic_9 0,100,100,0 6369 2:1339
RACE kyra_original -9223372036854775808 1 kids_arithmetic_9 50,100,0 6369 0:1339;2:1522;1:1214
RACE kyra_original -9223372036854775808 41 q-1 0,0,100,0 6672 2:1454
RACE kyra_original -9223372036854775808 41 q-1 100,0,0,0 6672 0:1454
RACE kyra_original -9223372036854775808 41 q-1 0,100,100,0 6672 1:1454
RACE kyra_original -9223372036854775808 41 q-1 50,100,0 6672 1:1454
RACE kyra_original -9223372036854775808 41 one_on_one 0,0,100,0 6705 1:1174;2:1120
RACE kyra_original -9223372036854775808 41 one_on_one 100,0,0,0 6705 2:1174;0:1120
RACE kyra_original -9223372036854775808 41 one_on_one 0,100,100,0 6705 0:1174;1:1120
RACE kyra_original -9223372036854775808 41 one_on_one 50,100,0 6705 0:1174;1:1120
RACE kyra_original -9223372036854775808 41 general_knowledge_easy_017 0,0,100,0 7086 2:1776
RACE kyra_original -9223372036854775808 41 general_knowledge_easy_017 100,0,0,0 7086 0:1776
RACE kyra_original -9223372036854775808 41 general_knowledge_easy_017 0,100,100,0 7086 2:1776
RACE kyra_original -9223372036854775808 41 general_knowledge_easy_017 50,100,0 7086 1:1776
RACE kyra_original -9223372036854775808 41 kids_arithmetic_9 0,0,100,0 6880 2:1815
RACE kyra_original -9223372036854775808 41 kids_arithmetic_9 100,0,0,0 6880 0:1815
RACE kyra_original -9223372036854775808 41 kids_arithmetic_9 0,100,100,0 6880 1:1815
RACE kyra_original -9223372036854775808 41 kids_arithmetic_9 50,100,0 6880 1:1815
RACE flare 0 1 q-1 0,0,100,0 6992 2:1794
RACE flare 0 1 q-1 100,0,0,0 6992 0:1794
RACE flare 0 1 q-1 0,100,100,0 6992 2:1794
RACE flare 0 1 q-1 50,100,0 6992 1:1794
RACE flare 0 1 one_on_one 0,0,100,0 7886 2:1264
RACE flare 0 1 one_on_one 100,0,0,0 7886 0:1264
RACE flare 0 1 one_on_one 0,100,100,0 7886 1:1264
RACE flare 0 1 one_on_one 50,100,0 7886 1:1264
RACE flare 0 1 general_knowledge_easy_017 0,0,100,0 6637 3:1968;2:1074
RACE flare 0 1 general_knowledge_easy_017 100,0,0,0 6637 3:1968;2:1074;0:1406
RACE flare 0 1 general_knowledge_easy_017 0,100,100,0 6637 0:1968;3:1074;1:1528
RACE flare 0 1 general_knowledge_easy_017 50,100,0 6637 0:1968;2:1074;1:1528
RACE flare 0 1 kids_arithmetic_9 0,0,100,0 7367 2:1261
RACE flare 0 1 kids_arithmetic_9 100,0,0,0 7367 0:1261
RACE flare 0 1 kids_arithmetic_9 0,100,100,0 7367 1:1261
RACE flare 0 1 kids_arithmetic_9 50,100,0 7367 1:1261
RACE flare 0 41 q-1 0,0,100,0 6459 2:1340
RACE flare 0 41 q-1 100,0,0,0 6459 0:1340
RACE flare 0 41 q-1 0,100,100,0 6459 1:1340
RACE flare 0 41 q-1 50,100,0 6459 1:1340
RACE flare 0 41 one_on_one 0,0,100,0 7180 2:1775
RACE flare 0 41 one_on_one 100,0,0,0 7180 0:1775
RACE flare 0 41 one_on_one 0,100,100,0 7180 2:1775
RACE flare 0 41 one_on_one 50,100,0 7180 1:1775
RACE flare 0 41 general_knowledge_easy_017 0,0,100,0 7569 1:1482;2:1198
RACE flare 0 41 general_knowledge_easy_017 100,0,0,0 7569 2:1482;0:1198
RACE flare 0 41 general_knowledge_easy_017 0,100,100,0 7569 3:1482;1:1198
RACE flare 0 41 general_knowledge_easy_017 50,100,0 7569 2:1482;1:1198
RACE flare 0 41 kids_arithmetic_9 0,0,100,0 7092 2:1877
RACE flare 0 41 kids_arithmetic_9 100,0,0,0 7092 0:1877
RACE flare 0 41 kids_arithmetic_9 0,100,100,0 7092 1:1877
RACE flare 0 41 kids_arithmetic_9 50,100,0 7092 1:1877
RACE flare 1700000000123 1 q-1 0,0,100,0 8174 3:1268;2:1381
RACE flare 1700000000123 1 q-1 100,0,0,0 8174 3:1268;0:1381
RACE flare 1700000000123 1 q-1 0,100,100,0 8174 0:1268;1:1381
RACE flare 1700000000123 1 q-1 50,100,0 8174 0:1268;1:1381
RACE flare 1700000000123 1 one_on_one 0,0,100,0 7860 2:2033
RACE flare 1700000000123 1 one_on_one 100,0,0,0 7860 0:2033
RACE flare 1700000000123 1 one_on_one 0,100,100,0 7860 2:2033
RACE flare 1700000000123 1 one_on_one 50,100,0 7860 1:2033
RACE flare 1700000000123 1 general_knowledge_easy_017 0,0,100,0 7678 2:1831
RACE flare 1700000000123 1 general_knowledge_easy_017 100,0,0,0 7678 0:1831
RACE flare 1700000000123 1 general_knowledge_easy_017 0,100,100,0 7678 2:1831
RACE flare 1700000000123 1 general_knowledge_easy_017 50,100,0 7678 1:1831
RACE flare 1700000000123 1 kids_arithmetic_9 0,0,100,0 6935 3:1469;2:1274
RACE flare 1700000000123 1 kids_arithmetic_9 100,0,0,0 6935 3:1469;0:1274
RACE flare 1700000000123 1 kids_arithmetic_9 0,100,100,0 6935 0:1469;2:1274
RACE flare 1700000000123 1 kids_arithmetic_9 50,100,0 6935 0:1469;1:1274
RACE flare 1700000000123 41 q-1 0,0,100,0 7048 2:1406
RACE flare 1700000000123 41 q-1 100,0,0,0 7048 0:1406
RACE flare 1700000000123 41 q-1 0,100,100,0 7048 2:1406
RACE flare 1700000000123 41 q-1 50,100,0 7048 1:1406
RACE flare 1700000000123 41 one_on_one 0,0,100,0 7432 2:1695
RACE flare 1700000000123 41 one_on_one 100,0,0,0 7432 2:1695;0:1098
RACE flare 1700000000123 41 one_on_one 0,100,100,0 7432 2:1695
RACE flare 1700000000123 41 one_on_one 50,100,0 7432 2:1695;1:1098
RACE flare 1700000000123 41 general_knowledge_easy_017 0,0,100,0 7576 3:1657;2:1467
RACE flare 1700000000123 41 general_knowledge_easy_017 100,0,0,0 7576 3:1657;2:1467;0:1267
RACE flare 1700000000123 41 general_knowledge_easy_017 0,100,100,0 7576 0:1657;3:1467;2:1357
RACE flare 1700000000123 41 general_knowledge_easy_017 50,100,0 7576 0:1657;2:1467;1:1357
RACE flare 1700000000123 41 kids_arithmetic_9 0,0,100,0 7018 3:1323;2:1271
RACE flare 1700000000123 41 kids_arithmetic_9 100,0,0,0 7018 3:1323;2:1271;0:1392
RACE flare 1700000000123 41 kids_arithmetic_9 0,100,100,0 7018 3:1323;2:1271
RACE flare 1700000000123 41 kids_arithmetic_9 50,100,0 7018 0:1323;2:1271;1:1339
RACE flare 9223372036854775807 1 q-1 0,0,100,0 7616 2:1298
RACE flare 9223372036854775807 1 q-1 100,0,0,0 7616 0:1298
RACE flare 9223372036854775807 1 q-1 0,100,100,0 7616 2:1298
RACE flare 9223372036854775807 1 q-1 50,100,0 7616 1:1298
RACE flare 9223372036854775807 1 one_on_one 0,0,100,0 7489 0:1340;1:1579;2:1647
RACE flare 9223372036854775807 1 one_on_one 100,0,0,0 7489 0:1340
RACE flare 9223372036854775807 1 one_on_one 0,100,100,0 7489 0:1340;3:1579;1:1299
RACE flare 9223372036854775807 1 one_on_one 50,100,0 7489 0:1340;2:1579;1:1299
RACE flare 9223372036854775807 1 general_knowledge_easy_017 0,0,100,0 7639 2:1480
RACE flare 9223372036854775807 1 general_knowledge_easy_017 100,0,0,0 7639 0:1480
RACE flare 9223372036854775807 1 general_knowledge_easy_017 0,100,100,0 7639 1:1480
RACE flare 9223372036854775807 1 general_knowledge_easy_017 50,100,0 7639 1:1480
RACE flare 9223372036854775807 1 kids_arithmetic_9 0,0,100,0 6575 2:1523
RACE flare 9223372036854775807 1 kids_arithmetic_9 100,0,0,0 6575 0:1523
RACE flare 9223372036854775807 1 kids_arithmetic_9 0,100,100,0 6575 1:1523
RACE flare 9223372036854775807 1 kids_arithmetic_9 50,100,0 6575 1:1523
RACE flare 9223372036854775807 41 q-1 0,0,100,0 7029 3:1523;2:1134
RACE flare 9223372036854775807 41 q-1 100,0,0,0 7029 3:1523;0:1134
RACE flare 9223372036854775807 41 q-1 0,100,100,0 7029 0:1523;2:1134
RACE flare 9223372036854775807 41 q-1 50,100,0 7029 0:1523;1:1134
RACE flare 9223372036854775807 41 one_on_one 0,0,100,0 8063 1:1801;0:1497;3:1510;2:1363
RACE flare 9223372036854775807 41 one_on_one 100,0,0,0 8063 1:1801;2:1497;3:1510;0:1363
RACE flare 9223372036854775807 41 one_on_one 0,100,100,0 8063 1:1801
RACE flare 9223372036854775807 41 one_on_one 50,100,0 8063 0:1801;2:1497;1:1222
RACE flare 9223372036854775807 41 general_knowledge_easy_017 0,0,100,0 8123 0:1641;2:1572
RACE flare 9223372036854775807 41 general_knowledge_easy_017 100,0,0,0 8123 0:1641
RACE flare 9223372036854775807 41 general_knowledge_easy_017 0,100,100,0 8123 0:1641;1:1572
RACE flare 9223372036854775807 41 general_knowledge_easy_017 50,100,0 8123 2:1641;1:1572
RACE flare 9223372036854775807 41 kids_arithmetic_9 0,0,100,0 7247 3:1279;1:1363;2:1272
RACE flare 9223372036854775807 41 kids_arithmetic_9 100,0,0,0 7247 3:1279;1:1363;0:1272
RACE flare 9223372036854775807 41 kids_arithmetic_9 0,100,100,0 7247 3:1279;1:1363
RACE flare 9223372036854775807 41 kids_arithmetic_9 50,100,0 7247 0:1279;2:1363;1:1684
RACE flare -9223372036854775808 1 q-1 0,0,100,0 8112 2:1277
RACE flare -9223372036854775808 1 q-1 100,0,0,0 8112 0:1277
RACE flare -9223372036854775808 1 q-1 0,100,100,0 8112 1:1277
RACE flare -9223372036854775808 1 q-1 50,100,0 8112 1:1277
RACE flare -9223372036854775808 1 one_on_one 0,0,100,0 7981 2:1237
RACE flare -9223372036854775808 1 one_on_one 100,0,0,0 7981 0:1237
RACE flare -9223372036854775808 1 one_on_one 0,100,100,0 7981 1:1237
RACE flare -9223372036854775808 1 one_on_one 50,100,0 7981 1:1237
RACE flare -9223372036854775808 1 general_knowledge_easy_017 0,0,100,0 6660 1:1335;3:1504;0:1373;2:1771
RACE flare -9223372036854775808 1 general_knowledge_easy_017 100,0,0,0 6660 1:1335;3:1504;2:1373;0:1771
RACE flare -9223372036854775808 1 general_knowledge_easy_017 0,100,100,0 6660 1:1335
RACE flare -9223372036854775808 1 general_knowledge_easy_017 50,100,0 6660 0:1335;2:1504;1:1524
RACE flare -9223372036854775808 1 kids_arithmetic_9 0,0,100,0 6673 2:1465
RACE flare -9223372036854775808 1 kids_arithmetic_9 100,0,0,0 6673 2:1465;1:1586;3:1722;0:1454
RACE flare -9223372036854775808 1 kids_arithmetic_9 0,100,100,0 6673 2:1465
RACE flare -9223372036854775808 1 kids_arithmetic_9 50,100,0 6673 0:1465;2:1586;1:1278
RACE flare -9223372036854775808 41 q-1 0,0,100,0 6976 2:1580
RACE flare -9223372036854775808 41 q-1 100,0,0,0 6976 0:1580
RACE flare -9223372036854775808 41 q-1 0,100,100,0 6976 1:1580
RACE flare -9223372036854775808 41 q-1 50,100,0 6976 1:1580
RACE flare -9223372036854775808 41 one_on_one 0,0,100,0 7009 1:1300;2:1184
RACE flare -9223372036854775808 41 one_on_one 100,0,0,0 7009 2:1300;0:1184
RACE flare -9223372036854775808 41 one_on_one 0,100,100,0 7009 0:1300;1:1184
RACE flare -9223372036854775808 41 one_on_one 50,100,0 7009 0:1300;1:1184
RACE flare -9223372036854775808 41 general_knowledge_easy_017 0,0,100,0 7390 2:1902
RACE flare -9223372036854775808 41 general_knowledge_easy_017 100,0,0,0 7390 0:1902
RACE flare -9223372036854775808 41 general_knowledge_easy_017 0,100,100,0 7390 2:1902
RACE flare -9223372036854775808 41 general_knowledge_easy_017 50,100,0 7390 1:1902
RACE flare -9223372036854775808 41 kids_arithmetic_9 0,0,100,0 7184 2:1941
RACE flare -9223372036854775808 41 kids_arithmetic_9 100,0,0,0 7184 0:1941
RACE flare -9223372036854775808 41 kids_arithmetic_9 0,100,100,0 7184 1:1941
RACE flare -9223372036854775808 41 kids_arithmetic_9 50,100,0 7184 1:1941
RACE ace_23 0 1 q-1 0,0,100,0 6761 2:1143
RACE ace_23 0 1 q-1 100,0,0,0 6761 2:1143;3:903;0:1397
RACE ace_23 0 1 q-1 0,100,100,0 6761 2:1143
RACE ace_23 0 1 q-1 50,100,0 6761 2:1143;1:903
RACE ace_23 0 1 one_on_one 0,0,100,0 7655 2:1089
RACE ace_23 0 1 one_on_one 100,0,0,0 7655 2:1089;3:1043;0:1046
RACE ace_23 0 1 one_on_one 0,100,100,0 7655 2:1089
RACE ace_23 0 1 one_on_one 50,100,0 7655 2:1089;1:1043
RACE ace_23 0 1 general_knowledge_easy_017 0,0,100,0 6406 3:1496;2:834
RACE ace_23 0 1 general_knowledge_easy_017 100,0,0,0 6406 3:1496;2:834;0:1244
RACE ace_23 0 1 general_knowledge_easy_017 0,100,100,0 6406 0:1496;3:834;1:1288
RACE ace_23 0 1 general_knowledge_easy_017 50,100,0 6406 0:1496;2:834;1:1288
RACE ace_23 0 1 kids_arithmetic_9 0,0,100,0 7136 0:811;1:946;2:1232
RACE ace_23 0 1 kids_arithmetic_9 100,0,0,0 7136 0:811
RACE ace_23 0 1 kids_arithmetic_9 0,100,100,0 7136 0:811;3:946;1:1250
RACE ace_23 0 1 kids_arithmetic_9 50,100,0 7136 0:811;2:946;1:1250
RACE ace_23 0 41 q-1 0,0,100,0 6228 0:986;1:1240;2:1416
RACE ace_23 0 41 q-1 100,0,0,0 6228 0:986
RACE ace_23 0 41 q-1 0,100,100,0 6228 0:986;1:1240
RACE ace_23 0 41 q-1 50,100,0 6228 0:986;1:1240
RACE ace_23 0 41 one_on_one 0,0,100,0 6949 3:1351;0:1226;2:1440
RACE ace_23 0 41 one_on_one 100,0,0,0 6949 3:1351;1:1226;2:1440;0:1226
RACE ace_23 0 41 one_on_one 0,100,100,0 6949 3:1351;0:1226;2:1316
RACE ace_23 0 41 one_on_one 50,100,0 6949 2:1351;0:1226;1:1316
RACE ace_23 0 41 general_knowledge_easy_017 0,0,100,0 7338 3:1522;2:958
RACE ace_23 0 41 general_knowledge_easy_017 100,0,0,0 7338 3:1522;0:958
RACE ace_23 0 41 general_knowledge_easy_017 0,100,100,0 7338 3:1522;1:958
RACE ace_23 0 41 general_knowledge_easy_017 50,100,0 7338 2:1522;1:958
RACE ace_23 0 41 kids_arithmetic_9 0,0,100,0 6861 3:810;2:960
RACE ace_23 0 41 kids_arithmetic_9 100,0,0,0 6861 3:810;2:960;1:1293;0:1279
RACE ace_23 0 41 kids_arithmetic_9 0,100,100,0 6861 3:810;2:960
RACE ace_23 0 41 kids_arithmetic_9 50,100,0 6861 0:810;2:960;1:1016
RACE ace_23 1700000000123 1 q-1 0,0,100,0 7943 0:816;2:988
RACE ace_23 1700000000123 1 q-1 100,0,0,0 7943 0:816
RACE ace_23 1700000000123 1 q-1 0,100,100,0 7943 0:816;2:988
RACE ace_23 1700000000123 1 q-1 50,100,0 7943 1:816
RACE ace_23 1700000000123 1 one_on_one 0,0,100,0 7629 0:1561;1:959;3:1406;2:1344
RACE ace_23 1700000000123 1 one_on_one 100,0,0,0 7629 1:1561;0:959
RACE ace_23 1700000000123 1 one_on_one 0,100,100,0 7629 3:1561;0:959;1:1276
RACE ace_23 1700000000123 1 one_on_one 50,100,0 7629 2:1561;1:959
RACE ace_23 1700000000123 1 general_knowledge_easy_017 0,0,100,0 7447 2:1359
RACE ace_23 1700000000123 1 general_knowledge_easy_017 100,0,0,0 7447 0:1359
RACE ace_23 1700000000123 1 general_knowledge_easy_017 0,100,100,0 7447 2:1359
RACE ace_23 1700000000123 1 general_knowledge_easy_017 50,100,0 7447 1:1359
RACE ace_23 1700000000123 1 kids_arithmetic_9 0,0,100,0 6704 3:1535;2:1155
RACE ace_23 1700000000123 1 kids_arithmetic_9 100,0,0,0 6704 3:1535;2:1155;0:1264
RACE ace_23 1700000000123 1 kids_arithmetic_9 0,100,100,0 6704 3:1535;2:1155
RACE ace_23 1700000000123 1 kids_arithmetic_9 50,100,0 6704 1:1535
RACE ace_23 1700000000123 41 q-1 0,0,100,0 6817 3:1502;2:1017
RACE ace_23 1700000000123 41 q-1 100,0,0,0 6817 3:1502;2:1017;0:1173
RACE ace_23 1700000000123 41 q-1 0,100,100,0 6817 3:1502;2:1017
RACE ace_23 1700000000123 41 q-1 50,100,0 6817 1:1502
RACE ace_23 1700000000123 41 one_on_one 0,0,100,0 7201 2:1223
RACE ace_23 1700000000123 41 one_on_one 100,0,0,0 7201 2:1223;0:858
RACE ace_23 1700000000123 41 one_on_one 0,100,100,0 7201 2:1223
RACE ace_23 1700000000123 41 one_on_one 50,100,0 7201 2:1223;1:858
RACE ace_23 1700000000123 41 general_knowledge_easy_017 0,0,100,0 7345 3:743;2:1227
RACE ace_23 1700000000123 41 general_knowledge_easy_017 100,0,0,0 7345 3:743;2:1227;0:1207
RACE ace_23 1700000000123 41 general_knowledge_easy_017 0,100,100,0 7345 3:743;2:1227
RACE ace_23 1700000000123 41 general_knowledge_easy_017 50,100,0 7345 1:743
RACE ace_23 1700000000123 41 kids_arithmetic_9 0,0,100,0 6787 3:851;2:1031
RACE ace_23 1700000000123 41 kids_arithmetic_9 100,0,0,0 6787 3:851;2:1031;0:1152
RACE ace_23 1700000000123 41 kids_arithmetic_9 0,100,100,0 6787 3:851;2:1031
RACE ace_23 1700000000123 41 kids_arithmetic_9 50,100,0 6787 0:851;2:1031;1:1099
RACE ace_23 9223372036854775807 1 q-1 0,0,100,0 7385 0:1419;3:1137;1:1281;2:1270
RACE ace_23 9223372036854775807 1 q-1 100,0,0,0 7385 0:1419
RACE ace_23 9223372036854775807 1 q-1 0,100,100,0 7385 0:1419;3:1137;2:1119
RACE ace_23 9223372036854775807 1 q-1 50,100,0 7385 2:1419;0:1137;1:1119
RACE ace_23 9223372036854775807 1 one_on_one 0,0,100,0 7258 0:868;2:968
RACE ace_23 9223372036854775807 1 one_on_one 100,0,0,0 7258 0:868
RACE ace_23 9223372036854775807 1 one_on_one 0,100,100,0 7258 0:868;2:968
RACE ace_23 9223372036854775807 1 one_on_one 50,100,0 7258 0:868;1:968
RACE ace_23 9223372036854775807 1 general_knowledge_easy_017 0,0,100,0 7408 0:934;3:1198;2:1487
RACE ace_23 9223372036854775807 1 general_knowledge_easy_017 100,0,0,0 7408 0:934
RACE ace_23 9223372036854775807 1 general_knowledge_easy_017 0,100,100,0 7408 0:934;3:1198;1:1064
RACE ace_23 9223372036854775807 1 general_knowledge_easy_017 50,100,0 7408 0:934;1:1198
RACE ace_23 9223372036854775807 1 kids_arithmetic_9 0,0,100,0 6344 0:828;2:1311
RACE ace_23 9223372036854775807 1 kids_arithmetic_9 100,0,0,0 6344 0:828
RACE ace_23 9223372036854775807 1 kids_arithmetic_9 0,100,100,0 6344 0:828;2:1311
RACE ace_23 9223372036854775807 1 kids_arithmetic_9 50,100,0 6344 2:828;0:1311;1:1057
RACE ace_23 9223372036854775807 41 q-1 0,0,100,0 6798 0:1079;3:1080;2:1138
RACE ace_23 9223372036854775807 41 q-1 100,0,0,0 6798 0:1079
RACE ace_23 9223372036854775807 41 q-1 0,100,100,0 6798 0:1079;3:1080;2:1180
RACE ace_23 9223372036854775807 41 q-1 50,100,0 6798 0:1079;1:1080
RACE ace_23 9223372036854775807 41 one_on_one 0,0,100,0 7832 1:1329;2:1236
RACE ace_23 9223372036854775807 41 one_on_one 100,0,0,0 7832 1:1329;2:1236;3:1270;0:1123
RACE ace_23 9223372036854775807 41 one_on_one 0,100,100,0 7832 1:1329
RACE ace_23 9223372036854775807 41 one_on_one 50,100,0 7832 0:1329;1:1236
RACE ace_23 9223372036854775807 41 general_knowledge_easy_017 0,0,100,0 7892 0:1169;1:872;3:1072;2:1627
RACE ace_23 9223372036854775807 41 general_knowledge_easy_017 100,0,0,0 7892 0:1169
RACE ace_23 9223372036854775807 41 general_knowledge_easy_017 0,100,100,0 7892 0:1169;1:872
RACE ace_23 9223372036854775807 41 general_knowledge_easy_017 50,100,0 7892 2:1169;0:872;1:1160
RACE ace_23 9223372036854775807 41 kids_arithmetic_9 0,0,100,0 7016 3:807;1:1123;0:1454;2:1503
RACE ace_23 9223372036854775807 41 kids_arithmetic_9 100,0,0,0 7016 3:807;1:1123;0:1454
RACE ace_23 9223372036854775807 41 kids_arithmetic_9 0,100,100,0 7016 3:807;1:1123
RACE ace_23 9223372036854775807 41 kids_arithmetic_9 50,100,0 7016 0:807;2:1123;1:1444
RACE ace_23 -9223372036854775808 1 q-1 0,0,100,0 7881 1:1184;3:967;2:1143
RACE ace_23 -9223372036854775808 1 q-1 100,0,0,0 7881 1:1184;3:967;2:1143;0:1497
RACE ace_23 -9223372036854775808 1 q-1 0,100,100,0 7881 1:1184
RACE ace_23 -9223372036854775808 1 q-1 50,100,0 7881 0:1184;1:967
RACE ace_23 -9223372036854775808 1 one_on_one 0,0,100,0 7750 0:1402;1:830;3:1440;2:1619
RACE ace_23 -9223372036854775808 1 one_on_one 100,0,0,0 7750 0:1402
RACE ace_23 -9223372036854775808 1 one_on_one 0,100,100,0 7750 0:1402;1:830
RACE ace_23 -9223372036854775808 1 one_on_one 50,100,0 7750 2:1402;0:830;1:1280
RACE ace_23 -9223372036854775808 1 general_knowledge_easy_017 0,0,100,0 6429 1:863;3:1264;2:1093
RACE ace_23 -9223372036854775808 1 general_knowledge_easy_017 100,0,0,0 6429 1:863;3:1264;2:1093;0:1531
RACE ace_23 -9223372036854775808 1 general_knowledge_easy_017 0,100,100,0 6429 1:863
RACE ace_23 -9223372036854775808 1 general_knowledge_easy_017 50,100,0 6429 0:863;2:1264;1:1284
RACE ace_23 -9223372036854775808 1 kids_arithmetic_9 0,0,100,0 6442 2:993
RACE ace_23 -9223372036854775808 1 kids_arithmetic_9 100,0,0,0 6442 2:993;1:1346;3:1482;0:1214
RACE ace_23 -9223372036854775808 1 kids_arithmetic_9 0,100,100,0 6442 2:993
RACE ace_23 -9223372036854775808 1 kids_arithmetic_9 50,100,0 6442 0:993;2:1346;1:1038
RACE ace_23 -9223372036854775808 41 q-1 0,0,100,0 6745 2:1347
RACE ace_23 -9223372036854775808 41 q-1 100,0,0,0 6745 2:1347;0:924
RACE ace_23 -9223372036854775808 41 q-1 0,100,100,0 6745 2:1347
RACE ace_23 -9223372036854775808 41 q-1 50,100,0 6745 2:1347;1:924
RACE ace_23 -9223372036854775808 41 one_on_one 0,0,100,0 6778 1:828;3:1308;0:1192;2:1534
RACE ace_23 -9223372036854775808 41 one_on_one 100,0,0,0 6778 2:828;3:1308;0:1192
RACE ace_23 -9223372036854775808 41 one_on_one 0,100,100,0 6778 0:828;3:1308;2:1192
RACE ace_23 -9223372036854775808 41 one_on_one 50,100,0 6778 0:828;2:1308;1:1192
RACE ace_23 -9223372036854775808 41 general_knowledge_easy_017 0,0,100,0 7159 2:781
RACE ace_23 -9223372036854775808 41 general_knowledge_easy_017 100,0,0,0 7159 2:781;1:1286;0:1394
RACE ace_23 -9223372036854775808 41 general_knowledge_easy_017 0,100,100,0 7159 2:781
RACE ace_23 -9223372036854775808 41 general_knowledge_easy_017 50,100,0 7159 1:781
RACE ace_23 -9223372036854775808 41 kids_arithmetic_9 0,0,100,0 6953 1:825;0:1268;3:1469;2:1171
RACE ace_23 -9223372036854775808 41 kids_arithmetic_9 100,0,0,0 6953 1:825;2:1268;3:1469;0:1171
RACE ace_23 -9223372036854775808 41 kids_arithmetic_9 0,100,100,0 6953 1:825
RACE ace_23 -9223372036854775808 41 kids_arithmetic_9 50,100,0 6953 0:825;2:1268;1:1291
RACE buddy_23 0 1 q-1 0,0,100,0 8202 2:1930
RACE buddy_23 0 1 q-1 100,0,0,0 8202 2:1930;3:1303;0:1797
RACE buddy_23 0 1 q-1 0,100,100,0 8202 2:1930
RACE buddy_23 0 1 q-1 50,100,0 8202 2:1930;1:1303
RACE buddy_23 0 1 one_on_one 0,0,100,0 9096 2:1876
RACE buddy_23 0 1 one_on_one 100,0,0,0 9096 2:1876;3:1443;0:1446
RACE buddy_23 0 1 one_on_one 0,100,100,0 9096 2:1876
RACE buddy_23 0 1 one_on_one 50,100,0 9096 2:1876;1:1443
RACE buddy_23 0 1 general_knowledge_easy_017 0,0,100,0 7847 2:1656
RACE buddy_23 0 1 general_knowledge_easy_017 100,0,0,0 7847 2:1656;3:1234;0:1644
RACE buddy_23 0 1 general_knowledge_easy_017 0,100,100,0 7847 2:1656
RACE buddy_23 0 1 general_knowledge_easy_017 50,100,0 7847 0:1656;2:1234;1:1688
RACE buddy_23 0 1 kids_arithmetic_9 0,0,100,0 8577 0:1598;1:1322;2:1632
RACE buddy_23 0 1 kids_arithmetic_9 100,0,0,0 8577 0:1598
RACE buddy_23 0 1 kids_arithmetic_9 0,100,100,0 8577 0:1598;1:1322
RACE buddy_23 0 1 kids_arithmetic_9 50,100,0 8577 0:1598;1:1322
RACE buddy_23 0 41 q-1 0,0,100,0 7669 0:1773;1:1640;2:1816
RACE buddy_23 0 41 q-1 100,0,0,0 7669 0:1773
RACE buddy_23 0 41 q-1 0,100,100,0 7669 0:1773;1:1640
RACE buddy_23 0 41 q-1 50,100,0 7669 0:1773;1:1640
RACE buddy_23 0 41 one_on_one 0,0,100,0 8390 3:2138;1:1442;2:1840
RACE buddy_23 0 41 one_on_one 100,0,0,0 8390 3:2138;1:1442;2:1840;0:1626
RACE buddy_23 0 41 one_on_one 0,100,100,0 8390 3:2138;1:1442
RACE buddy_23 0 41 one_on_one 50,100,0 8390 2:2138;1:1442
RACE buddy_23 0 41 general_knowledge_easy_017 0,0,100,0 8779 3:2309;0:1419;1:1572;2:1986
RACE buddy_23 0 41 general_knowledge_easy_017 100,0,0,0 8779 3:2309;0:1419
RACE buddy_23 0 41 general_knowledge_easy_017 0,100,100,0 8779 3:2309;0:1419;1:1809
RACE buddy_23 0 41 general_knowledge_easy_017 50,100,0 8779 2:2309;1:1419
RACE buddy_23 0 41 kids_arithmetic_9 0,0,100,0 8302 3:1597;2:1360
RACE buddy_23 0 41 kids_arithmetic_9 100,0,0,0 8302 3:1597;2:1360;0:1772
RACE buddy_23 0 41 kids_arithmetic_9 0,100,100,0 8302 3:1597;2:1360
RACE buddy_23 0 41 kids_arithmetic_9 50,100,0 8302 0:1597;2:1360;1:1416
RACE buddy_23 1700000000123 1 q-1 0,0,100,0 9384 0:1603;2:1388
RACE buddy_23 1700000000123 1 q-1 100,0,0,0 9384 0:1603
RACE buddy_23 1700000000123 1 q-1 0,100,100,0 9384 0:1603;2:1388
RACE buddy_23 1700000000123 1 q-1 50,100,0 9384 1:1603
RACE buddy_23 1700000000123 1 one_on_one 0,0,100,0 9070 0:2037;1:1359;3:1806;2:1744
RACE buddy_23 1700000000123 1 one_on_one 100,0,0,0 9070 0:2037
RACE buddy_23 1700000000123 1 one_on_one 0,100,100,0 9070 0:2037;1:1359
RACE buddy_23 1700000000123 1 one_on_one 50,100,0 9070 2:2037;1:1359
RACE buddy_23 1700000000123 1 general_knowledge_easy_017 0,0,100,0 8888 0:1679;3:1450;1:1418;2:1855
RACE buddy_23 1700000000123 1 general_knowledge_easy_017 100,0,0,0 8888 0:1679
RACE buddy_23 1700000000123 1 general_knowledge_easy_017 0,100,100,0 8888 0:1679;3:1450;1:1398
RACE buddy_23 1700000000123 1 general_knowledge_easy_017 50,100,0 8888 1:1679
RACE buddy_23 1700000000123 1 kids_arithmetic_9 0,0,100,0 8145 3:2322;2:1555
RACE buddy_23 1700000000123 1 kids_arithmetic_9 100,0,0,0 8145 3:2322;2:1555;0:1664
RACE buddy_23 1700000000123 1 kids_arithmetic_9 0,100,100,0 8145 3:2322;2:1555
RACE buddy_23 1700000000123 1 kids_arithmetic_9 50,100,0 8145 1:2322
RACE buddy_23 1700000000123 41 q-1 0,0,100,0 8258 3:2289;2:1417
RACE buddy_23 1700000000123 41 q-1 100,0,0,0 8258 3:2289;2:1417;0:1573
RACE buddy_23 1700000000123 41 q-1 0,100,100,0 8258 3:2289;2:1417
RACE buddy_23 1700000000123 41 q-1 50,100,0 8258 1:2289
RACE buddy_23 1700000000123 41 one_on_one 0,0,100,0 8642 2:2010
RACE buddy_23 1700000000123 41 one_on_one 100,0,0,0 8642 2:2010;0:1258
RACE buddy_23 1700000000123 41 one_on_one 0,100,100,0 8642 2:2010
RACE buddy_23 1700000000123 41 one_on_one 50,100,0 8642 2:2010;1:1258
RACE buddy_23 1700000000123 41 general_knowledge_easy_017 0,0,100,0 8786 3:1530;2:1627
RACE buddy_23 1700000000123 41 general_knowledge_easy_017 100,0,0,0 8786 3:1530;2:1627;0:1607
RACE buddy_23 1700000000123 41 general_knowledge_easy_017 0,100,100,0 8786 3:1530;2:1627
RACE buddy_23 1700000000123 41 general_knowledge_easy_017 50,100,0 8786 1:1530
RACE buddy_23 1700000000123 41 kids_arithmetic_9 0,0,100,0 8228 3:1638;2:1431
RACE buddy_23 1700000000123 41 kids_arithmetic_9 100,0,0,0 8228 3:1638;2:1431;0:1552
RACE buddy_23 1700000000123 41 kids_arithmetic_9 0,100,100,0 8228 3:1638;2:1431
RACE buddy_23 1700000000123 41 kids_arithmetic_9 50,100,0 8228 0:1638;2:1431;1:1499
RACE buddy_23 9223372036854775807 1 q-1 0,0,100,0 8826 0:2206;3:1537;2:1680
RACE buddy_23 9223372036854775807 1 q-1 100,0,0,0 8826 0:2206
RACE buddy_23 9223372036854775807 1 q-1 0,100,100,0 8826 0:2206;3:1537;2:1519
RACE buddy_23 9223372036854775807 1 q-1 50,100,0 8826 2:2206;0:1537;1:1519
RACE buddy_23 9223372036854775807 1 one_on_one 0,0,100,0 8699 0:1655;2:1368
RACE buddy_23 9223372036854775807 1 one_on_one 100,0,0,0 8699 0:1655
RACE buddy_23 9223372036854775807 1 one_on_one 0,100,100,0 8699 0:1655;2:1368
RACE buddy_23 9223372036854775807 1 one_on_one 50,100,0 8699 0:1655;1:1368
RACE buddy_23 9223372036854775807 1 general_knowledge_easy_017 0,0,100,0 8849 0:1721;3:1598;2:1887
RACE buddy_23 9223372036854775807 1 general_knowledge_easy_017 100,0,0,0 8849 0:1721
RACE buddy_23 9223372036854775807 1 general_knowledge_easy_017 0,100,100,0 8849 0:1721;3:1598;1:1464
RACE buddy_23 9223372036854775807 1 general_knowledge_easy_017 50,100,0 8849 0:1721;1:1598
RACE buddy_23 9223372036854775807 1 kids_arithmetic_9 0,0,100,0 7785 0:1615;2:1711
RACE buddy_23 9223372036854775807 1 kids_arithmetic_9 100,0,0,0 7785 0:1615
RACE buddy_23 9223372036854775807 1 kids_arithmetic_9 0,100,100,0 7785 0:1615;2:1711
RACE buddy_23 9223372036854775807 1 kids_arithmetic_9 50,100,0 7785 2:1615;0:1711;1:1457
RACE buddy_23 9223372036854775807 41 q-1 0,0,100,0 8239 0:1866;3:1480;2:1538
RACE buddy_23 9223372036854775807 41 q-1 100,0,0,0 8239 0:1866
RACE buddy_23 9223372036854775807 41 q-1 0,100,100,0 8239 0:1866;3:1480;2:1580
RACE buddy_23 9223372036854775807 41 q-1 50,100,0 8239 0:1866;1:1480
RACE buddy_23 9223372036854775807 41 one_on_one 0,0,100,0 9273 1:2116;2:1636
RACE buddy_23 9223372036854775807 41 one_on_one 100,0,0,0 9273 1:2116;2:1636;3:1670;0:1523
RACE buddy_23 9223372036854775807 41 one_on_one 0,100,100,0 9273 1:2116
RACE buddy_23 9223372036854775807 41 one_on_one 50,100,0 9273 0:2116;1:1636
RACE buddy_23 9223372036854775807 41 general_knowledge_easy_017 0,0,100,0 9333 0:1956;1:1272;3:1472;2:2027
RACE buddy_23 9223372036854775807 41 general_knowledge_easy_017 100,0,0,0 9333 0:1956
RACE buddy_23 9223372036854775807 41 general_knowledge_easy_017 0,100,100,0 9333 0:1956;1:1272
RACE buddy_23 9223372036854775807 41 general_knowledge_easy_017 50,100,0 9333 2:1956;0:1272;1:1560
RACE buddy_23 9223372036854775807 41 kids_arithmetic_9 0,0,100,0 8457 3:1594;1:1523;0:1854;2:1903
RACE buddy_23 9223372036854775807 41 kids_arithmetic_9 100,0,0,0 8457 3:1594;1:1523;0:1854
RACE buddy_23 9223372036854775807 41 kids_arithmetic_9 0,100,100,0 8457 3:1594;1:1523
RACE buddy_23 9223372036854775807 41 kids_arithmetic_9 50,100,0 8457 0:1594;2:1523;1:1844
RACE buddy_23 -9223372036854775808 1 q-1 0,0,100,0 9322 1:1971;3:1367;2:1543
RACE buddy_23 -9223372036854775808 1 q-1 100,0,0,0 9322 1:1971;3:1367;2:1543;0:1897
RACE buddy_23 -9223372036854775808 1 q-1 0,100,100,0 9322 1:1971
RACE buddy_23 -9223372036854775808 1 q-1 50,100,0 9322 0:1971;1:1367
RACE buddy_23 -9223372036854775808 1 one_on_one 0,0,100,0 9191 0:2189;1:1230;3:1840;2:2019
RACE buddy_23 -9223372036854775808 1 one_on_one 100,0,0,0 9191 0:2189
RACE buddy_23 -9223372036854775808 1 one_on_one 0,100,100,0 9191 0:2189;1:1230
RACE buddy_23 -9223372036854775808 1 one_on_one 50,100,0 9191 2:2189;0:1230;1:1680
RACE buddy_23 -9223372036854775808 1 general_knowledge_easy_017 0,0,100,0 7870 1:1650;0:1585;3:1493;2:1931
RACE buddy_23 -9223372036854775808 1 general_knowledge_easy_017 100,0,0,0 7870 1:1650;0:1585
RACE buddy_23 -9223372036854775808 1 general_knowledge_easy_017 0,100,100,0 7870 1:1650
RACE buddy_23 -9223372036854775808 1 general_knowledge_easy_017 50,100,0 7870 0:1650;1:1585
RACE buddy_23 -9223372036854775808 1 kids_arithmetic_9 0,0,100,0 7883 2:1780
RACE buddy_23 -9223372036854775808 1 kids_arithmetic_9 100,0,0,0 7883 2:1780;1:1746;3:1882;0:1614
RACE buddy_23 -9223372036854775808 1 kids_arithmetic_9 0,100,100,0 7883 2:1780
RACE buddy_23 -9223372036854775808 1 kids_arithmetic_9 50,100,0 7883 0:1780;2:1746;1:1438
RACE buddy_23 -9223372036854775808 41 q-1 0,0,100,0 8186 2:2134
RACE buddy_23 -9223372036854775808 41 q-1 100,0,0,0 8186 2:2134;0:1324
RACE buddy_23 -9223372036854775808 41 q-1 0,100,100,0 8186 2:2134
RACE buddy_23 -9223372036854775808 41 q-1 50,100,0 8186 2:2134;1:1324
RACE buddy_23 -9223372036854775808 41 one_on_one 0,0,100,0 8219 2:1858
RACE buddy_23 -9223372036854775808 41 one_on_one 100,0,0,0 8219 2:1858;3:1708;0:1592
RACE buddy_23 -9223372036854775808 41 one_on_one 0,100,100,0 8219 2:1858
RACE buddy_23 -9223372036854775808 41 one_on_one 50,100,0 8219 1:1858
RACE buddy_23 -9223372036854775808 41 general_knowledge_easy_017 0,0,100,0 8600 2:1568
RACE buddy_23 -9223372036854775808 41 general_knowledge_easy_017 100,0,0,0 8600 2:1568;1:1686;0:1794
RACE buddy_23 -9223372036854775808 41 general_knowledge_easy_017 0,100,100,0 8600 2:1568
RACE buddy_23 -9223372036854775808 41 general_knowledge_easy_017 50,100,0 8600 1:1568
RACE buddy_23 -9223372036854775808 41 kids_arithmetic_9 0,0,100,0 8394 1:1612;0:1504;3:1869;2:1571
RACE buddy_23 -9223372036854775808 41 kids_arithmetic_9 100,0,0,0 8394 1:1612;0:1504
RACE buddy_23 -9223372036854775808 41 kids_arithmetic_9 0,100,100,0 8394 1:1612
RACE buddy_23 -9223372036854775808 41 kids_arithmetic_9 50,100,0 8394 0:1612;1:1504
"""
}
