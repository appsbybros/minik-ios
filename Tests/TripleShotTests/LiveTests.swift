import Foundation
import XCTest
@testable import MinikTripleShot

// Parity tests for area s-live: ui/TripleShotLiveSetupFragment.kt with res/layout/fragment_triple_shot_live_setup.xml
// (spec 19 §4.3, §4.6.3, §7) and ui/TripleShotLeaderboardFragment.kt + ui/TripleShotLeaderboardAdapter.kt with
// res/layout/fragment_triple_shot_leaderboard.xml and item_triple_shot_leaderboard.xml (spec 25 §4.2, §7.2).
//
// - OVR golden values: spec 19 §7 (Maya 74, Rooza 75, Mia Essence Skies 85, Uni 32 73, Coach 67 74, Comet 81,
//   Gaya 81, Kyra 81, FLARE 82, Ace 23 78, Buddy 23 70; BOB 59), recomputed from the Kotlin ratings of
//   model/TripleShotCharacters.kt.
// - Leaderboard rows: the Kotlin string templates of TripleShotLeaderboardAdapter.onBindViewHolder.
// - Layouts: the XML ids, texts and the attributes the code relies on, read like the Android inflater reads them.
// - Hosted Live setup (no Firebase call happens before Create): the SETUP state of spec 19 §4.3.2 after
//   onViewCreated, the mode / character taps and their styles (TripleShotLiveSetupFragment 155-253), the persisted
//   character, and Back without a room (leaveSetup -> popBackStack), on AndroidKit's fake main thread.
// - iOS-only safe area (spec 19 §4.6.3, spec 25 §8.4): the insets added to the XML padding / margins.

/// An activity whose content view is one FrameLayout with id "container" (TripleShotDemoActivity's layout shape).
private final class LiveTestActivity: AActivity {
    let container = AFrameLayout()

    override func onCreate(_ savedInstanceState: ABundle?) {
        super.onCreate(savedInstanceState)
        container.viewId = "container"
        setContentView(container)
    }
}

/// A plain root fragment under the Live setup on the back stack (the Home screen's place).
private final class LiveRootFragment: AFragment {
    override func onCreateView(_ inflater: ALayoutInflater, _ container: AViewGroup?, _ savedInstanceState: ABundle?) -> AView? {
        return AFrameLayout()
    }
}

final class LiveTests: XCTestCase {

    private func px(_ dp: Float) -> Int {
        return ATypedValue.toDimensionPixelSize(ATypedValue.COMPLEX_UNIT_DIP, dp)
    }

    /// TripleShotLiveSetupFragment.dp: `(value * resources.displayMetrics.density + 0.5f).toInt()` (rounding).
    private func liveDp(_ value: Int) -> Int {
        return (value.toFloat() * AResources.displayMetrics.density + Float(0.5)).toInt()
    }

    private func find<T: AView>(_ root: AView, _ id: String, _ type: T.Type) -> T? {
        let found: T? = root.findViewById(id)
        return found
    }

    /// A created, started and resumed test activity (ActivityThread's launch order).
    private func resumedActivity() -> LiveTestActivity {
        let a = LiveTestActivity()
        a.performCreate()
        a.performStart()
        a.performPostCreate()
        a.performResume()
        return a
    }

    /// Runs `body` with AndroidKit's fake main thread installed and the `triple_shot/player_character` preference
    /// restored afterwards.
    private func withFakeMainThread(_ body: () -> Void) {
        AndroidKitTestLoop.install(startNanos: 1_000_000_000_000)
        let prefs = getSharedPreferences("triple_shot", MODE_PRIVATE)
        let savedCharacter = prefs.getString("player_character", nil)
        defer {
            if let saved = savedCharacter {
                prefs.edit().putString("player_character", saved).commit()
            } else {
                prefs.edit().remove("player_character").commit()
            }
            AndroidKitTestLoop.uninstall()
        }
        body()
    }

    // MARK: - Live setup: pure helpers

    func testOverallMatchesTheGoldenValuesInRosterOrder() {
        let fragment = TripleShotLiveSetupFragment()
        let profiles = TripleShotCharacterRoster.humanSelectable()
        XCTAssertEqual(profiles.map { $0.id }, [
            "woman_dark", "rooza", "nova", "unicorn_32", "coach_67", "zephyr", "kyra", "kyra_original", "flare",
            "ace_23", "buddy_23",
        ])
        XCTAssertEqual(profiles.map { fragment.overall(profile: $0) }, [74, 75, 85, 73, 74, 81, 81, 81, 82, 78, 70])
        XCTAssertEqual(fragment.overall(profile: TripleShotCharacterRoster.find(id: "bob")!), 59)
    }

    func testPlaceholderDrawablesFollowTheKotlinWhen() {
        let fragment = TripleShotLiveSetupFragment()
        let expected: [(String, ADrawableRes)] = [
            ("woman_dark", R.drawable.live_character_maya),
            ("rooza", R.drawable.live_character_rooza),
            ("nova", R.drawable.live_character_nova),
            ("unicorn_32", R.drawable.live_character_unicorn32),
            ("coach_67", R.drawable.live_character_coach67),
            ("zephyr", R.drawable.live_character_zephyr),
            ("kyra", R.drawable.live_character_kyra),
            // `else` branch: the original Kyra, FLARE and BOB show Maya's placeholder (spec 19 §4.6.3).
            ("kyra_original", R.drawable.live_character_maya),
            ("flare", R.drawable.live_character_maya),
            ("ace_23", R.drawable.live_character_ace23),
            ("buddy_23", R.drawable.live_character_buddy23),
            ("bob", R.drawable.live_character_maya),
            ("", R.drawable.live_character_maya),
        ]
        for (id, drawable) in expected {
            XCTAssertEqual(fragment.placeholderDrawable(characterId: id), drawable, id)
        }
    }

    // MARK: - Live setup: arguments (companion newInstance + the computed argument properties)

    func testNewInstanceWritesTheKotlinBundle() {
        let fragment = TripleShotLiveSetupFragment.newInstance(
            playerName: "Gaya",
            selectedCategories: [QuestionCategory.MATH, QuestionCategory.AI, QuestionCategory.MATH],
            playerCharacterId: "rooza"
        )
        let arguments = fragment.requireArguments()
        XCTAssertEqual(arguments.getString("player_name"), "Gaya")
        // putStringArrayList(ArrayList(selectedCategories.map { it.name })): a Set, in its iteration order.
        XCTAssertEqual(arguments.getStringArrayList("categories"), ["MATH", "AI"])
        XCTAssertEqual(arguments.getString("character_id"), "rooza")
        XCTAssertEqual(fragment.playerName, "Gaya")
        XCTAssertEqual(fragment.selectedCategories.elements, [QuestionCategory.MATH, QuestionCategory.AI])
        XCTAssertEqual(fragment.contentLayoutId, R.layout.fragment_triple_shot_live_setup)
        XCTAssertTrue(ALayoutInflater.isRegistered(R.layout.fragment_triple_shot_live_setup))
    }

    func testArgumentFallbacks() {
        // A blank name falls back to the string resource; invalid or missing topics fall back to all topics.
        let fragment = TripleShotLiveSetupFragment.newInstance(
            playerName: " \t ",
            selectedCategories: [QuestionCategory](),
            playerCharacterId: "nobody"
        )
        fragment.mHost = AActivity()
        XCTAssertEqual(fragment.playerName, AResources.getString(R.string.triple_shot_live_setup_player_fallback))
        XCTAssertEqual(fragment.selectedCategories.elements, QuestionCategory.allCases)

        let invalid = TripleShotLiveSetupFragment()
        let arguments = ABundle()
        arguments.putStringArrayList("categories", ["NOT_A_TOPIC", "HISTORY", "math"])
        invalid.arguments = arguments
        // valueOf is case-sensitive: only HISTORY survives.
        XCTAssertEqual(invalid.selectedCategories.elements, [QuestionCategory.HISTORY])
    }

    // MARK: - Live setup: layout (fragment_triple_shot_live_setup.xml)

    func testLiveSetupLayoutHasTheXmlTree() {
        let root = TripleShotLiveSetupLayout.build()
        XCTAssertTrue(root is AFrameLayout)
        let group = root as! AViewGroup
        XCTAssertEqual(group.childCount, 3)
        XCTAssertTrue(group.getChildAt(0) is AImageView)
        XCTAssertTrue(group.getChildAt(2) is AScrollView)

        let back = find(root, R.id.backLiveSetupButton, AButton.self)
        XCTAssertNotNil(back)
        XCTAssertEqual(back?.text, "\u{2039}")
        XCTAssertEqual(back?.contentDescription, AResources.getString(R.string.triple_shot_live_setup_back))
        XCTAssertEqual(back?.layoutParams?.width, px(48))

        for id in [R.id.liveSetupCard, R.id.liveSetupSection, R.id.shootingModeCard, R.id.horseModeCard,
                   R.id.liveCharacterRow, R.id.selectedCharacterInfo, R.id.liveRulesSummary,
                   R.id.createLiveRoomNowButton, R.id.liveLobbyCard, R.id.liveRoomCodeText, R.id.liveRoomPlayersText,
                   R.id.startLiveRoomButton, R.id.closeLiveRoomButton] {
            XCTAssertNotNil(find(root, id, AView.self), id)
        }
        XCTAssertEqual(find(root, R.id.liveLobbyCard, ACardView.self)?.visibility, AView.GONE)
        XCTAssertEqual(find(root, R.id.startLiveRoomButton, AButton.self)?.isEnabled, false)
        XCTAssertEqual(find(root, R.id.liveRoomPlayersText, ATextView.self)?.text,
                       AResources.getString(R.string.triple_shot_live_setup_waiting))
        XCTAssertEqual(find(root, R.id.createLiveRoomNowButton, AButton.self)?.layoutParams?.height, px(54))
        XCTAssertEqual(find(root, R.id.shootingModeCard, ACardView.self)?.layoutParams?.height, px(130))
        XCTAssertEqual(find(root, R.id.shootingModeCard, ACardView.self)?.isClickable, true)
        XCTAssertEqual(find(root, R.id.liveCharacterRow, ALinearLayout.self)?.paddingEnd, px(8))
        XCTAssertEqual(find(root, R.id.liveRoomCodeText, ATextView.self)?.letterSpacing, Float(0.12))
    }

    func testLiveSetupScrollAddsTheSafeAreaToTheXmlPadding() {
        let root = TripleShotLiveSetupLayout.build()
        let scroll = (root as! AViewGroup).getChildAt(2) as! AScrollView
        XCTAssertEqual(scroll.paddingStart, px(14))
        XCTAssertEqual(scroll.paddingTop, px(18))
        XCTAssertEqual(scroll.paddingEnd, px(14))
        XCTAssertEqual(scroll.paddingBottom, px(20))

        // Portrait: status bar on top, home indicator at the bottom.
        root.dispatchApplyWindowInsets(AWindowInsetsCompat.fromSafeArea(
            left: 0, top: 177, right: 0, bottom: 102, statusBarVisible: true, imeBottom: 0))
        XCTAssertEqual(scroll.paddingLeft, px(14))
        XCTAssertEqual(scroll.paddingTop, px(18) + 177)
        XCTAssertEqual(scroll.paddingRight, px(14))
        XCTAssertEqual(scroll.paddingBottom, px(20) + 102)

        // A landscape notch: the cutout sides are added to the XML padding, never accumulated.
        root.dispatchApplyWindowInsets(AWindowInsetsCompat.fromSafeArea(
            left: 141, top: 0, right: 141, bottom: 63, statusBarVisible: false, imeBottom: 0))
        XCTAssertEqual(scroll.paddingLeft, px(14) + 141)
        XCTAssertEqual(scroll.paddingTop, px(18))
        XCTAssertEqual(scroll.paddingRight, px(14) + 141)
        XCTAssertEqual(scroll.paddingBottom, px(20) + 63)
    }

    // MARK: - Live setup: hosted fragment (SETUP state, taps, Back without a room)

    func testHostedLiveSetupRendersTheInitialSetupState() {
        withFakeMainThread {
            let a = resumedActivity()
            defer { a.performDestroy() }
            let fragment = TripleShotLiveSetupFragment.newInstance(
                playerName: "Gaya",
                selectedCategories: [QuestionCategory.MATH, QuestionCategory.AI],
                playerCharacterId: "rooza"
            )
            a.supportFragmentManager.beginTransaction().replace("container", fragment).commitNow()
            XCTAssertTrue(fragment.isResumed)
            let root = fragment.requireView()

            // SETUP: the setup section is shown, the lobby card is gone, Create is enabled, Start is disabled.
            XCTAssertEqual(find(root, R.id.liveSetupSection, AView.self)?.visibility, AView.VISIBLE)
            XCTAssertEqual(find(root, R.id.liveLobbyCard, ACardView.self)?.visibility, AView.GONE)
            XCTAssertEqual(find(root, R.id.createLiveRoomNowButton, AButton.self)?.isEnabled, true)
            XCTAssertEqual(find(root, R.id.startLiveRoomButton, AButton.self)?.isEnabled, false)

            // renderModeSelection: Shooting Challenge is selected (styleModeCard).
            let shooting = find(root, R.id.shootingModeCard, ACardView.self)!
            let horse = find(root, R.id.horseModeCard, ACardView.self)!
            XCTAssertEqual(shooting.strokeWidth, liveDp(3))
            XCTAssertEqual(shooting.strokeColor, AColor.parseColor("#008B7A"))
            XCTAssertEqual(shooting.cardBackgroundColor.defaultColor, AColor.parseColor("#F4FFFC"))
            XCTAssertEqual(shooting.cardElevation, Float(liveDp(3)))
            XCTAssertEqual(horse.strokeWidth, liveDp(1))
            XCTAssertEqual(horse.strokeColor, AColor.parseColor("#66778B93"))
            XCTAssertEqual(horse.cardBackgroundColor.defaultColor, AColor.parseColor("#F8FFFFFF"))
            XCTAssertEqual(horse.cardElevation, Float(0))

            // renderRulesSummary: "<mode>  •  <n> topics" with the two argument topics.
            let rules = find(root, R.id.liveRulesSummary, ATextView.self)!
            XCTAssertEqual(rules.text, AFormat.format(
                ALocale.getDefault(), AResources.getString(R.string.triple_shot_live_setup_rules),
                [AResources.getString(R.string.triple_shot_live_setup_shooting_title), 2]))

            // renderCharacterRow: one card per human-selectable profile, in roster order.
            let selectedId = TripleShotCharacterVisualCatalog.hasVisuals(characterId: "rooza")
                ? "rooza" : TripleShotCharacterRoster.ID_WOMAN_DARK
            let profiles = TripleShotCharacterRoster.humanSelectable()
            let row = find(root, R.id.liveCharacterRow, ALinearLayout.self)!
            XCTAssertEqual(row.childCount, profiles.count)
            for (index, profile) in profiles.enumerated() {
                guard let card = row.getChildAt(index) as? ACardView else {
                    XCTFail("card \(index) is not a MaterialCardView")
                    continue
                }
                let selectable = TripleShotCharacterVisualCatalog.hasVisuals(characterId: profile.id)
                let selected = profile.id == selectedId
                XCTAssertEqual(card.radius, Float(liveDp(18)), profile.id)
                XCTAssertEqual(card.cardElevation, Float(liveDp(selected ? 4 : 1)), profile.id)
                XCTAssertEqual(card.strokeWidth, liveDp(selected ? 3 : 1), profile.id)
                XCTAssertEqual(card.strokeColor, AColor.parseColor(selected ? "#008B7A" : "#55778B93"), profile.id)
                XCTAssertEqual(card.cardBackgroundColor.defaultColor,
                               AColor.parseColor(selected ? "#F2FFFC" : "#F4FFFFFF"), profile.id)
                XCTAssertEqual(card.isClickable, selectable, profile.id)
                XCTAssertEqual(card.hasOnClickListeners(), selectable, profile.id)
                XCTAssertEqual(card.getAlpha(), selectable ? Float(1) : Float(0.58), profile.id)
                let params = card.layoutParams as? ALinearLayout.LayoutParams
                XCTAssertEqual(params?.width, liveDp(104), profile.id)
                XCTAssertEqual(params?.height, liveDp(154), profile.id)
                XCTAssertEqual(params?.marginEnd, liveDp(9), profile.id)

                // content: image 82 x 82 centre-crop, name (fake bold 12.5 sp), "OVR n" / "Coming soon".
                guard let content = card.getChildAt(0) as? ALinearLayout, content.childCount == 3 else {
                    XCTFail("card \(index) content")
                    continue
                }
                XCTAssertEqual(content.orientation, ALinearLayout.VERTICAL)
                XCTAssertEqual(content.paddingTop, liveDp(7))
                let image = content.getChildAt(0) as? AImageView
                XCTAssertEqual(image?.scaleType, AImageView.ScaleType.CENTER_CROP)
                XCTAssertEqual(image?.layoutParams?.width, liveDp(82))
                let name = content.getChildAt(1) as? ATextView
                XCTAssertEqual(name?.text, profile.displayName)
                XCTAssertEqual(name?.paint.isFakeBoldText, true)
                XCTAssertEqual(name?.textSize, ATypedValue.applyDimension(ATypedValue.COMPLEX_UNIT_SP, Float(12.5)))
                XCTAssertEqual((name?.layoutParams as? ALinearLayout.LayoutParams)?.topMargin, liveDp(4))
                let rating = content.getChildAt(2) as? ATextView
                XCTAssertEqual(rating?.text, selectable
                    ? AFormat.format(ALocale.getDefault(), AResources.getString(R.string.triple_shot_live_setup_ovr),
                                     [fragment.overall(profile: profile)])
                    : AResources.getString(R.string.triple_shot_live_setup_coming_soon))
            }

            // renderSelectedCharacterInfo: name, inside, mid-range, three-point, speed.
            let selectedProfile = TripleShotCharacterRoster.find(id: selectedId)!
            XCTAssertEqual(find(root, R.id.selectedCharacterInfo, ATextView.self)?.text, AFormat.format(
                ALocale.getDefault(), AResources.getString(R.string.triple_shot_live_setup_character_stats),
                [selectedProfile.displayName, selectedProfile.ratings.inside, selectedProfile.ratings.midRange,
                 selectedProfile.ratings.threePoint, selectedProfile.ratings.speed]))
        }
    }

    func testHostedLiveSetupModeAndCharacterTaps() {
        withFakeMainThread {
            let a = resumedActivity()
            defer { a.performDestroy() }
            let fragment = TripleShotLiveSetupFragment.newInstance(
                playerName: "Gaya",
                selectedCategories: QuestionCategory.allCases,
                playerCharacterId: "bob"
            )
            a.supportFragmentManager.beginTransaction().replace("container", fragment).commitNow()
            let root = fragment.requireView()
            let shooting = find(root, R.id.shootingModeCard, ACardView.self)!
            let horse = find(root, R.id.horseModeCard, ACardView.self)!
            let rules = find(root, R.id.liveRulesSummary, ATextView.self)!

            // HORSE tap (no room yet): the HORSE card takes the selected style, the summary names HORSE.
            horse.performClick()
            XCTAssertEqual(horse.strokeWidth, liveDp(3))
            XCTAssertEqual(horse.strokeColor, AColor.parseColor("#008B7A"))
            XCTAssertEqual(shooting.strokeWidth, liveDp(1))
            XCTAssertEqual(shooting.strokeColor, AColor.parseColor("#66778B93"))
            XCTAssertEqual(rules.text, AFormat.format(
                ALocale.getDefault(), AResources.getString(R.string.triple_shot_live_setup_rules),
                [AResources.getString(R.string.triple_shot_live_setup_horse_title), QuestionCategory.allCases.count]))
            shooting.performClick()
            XCTAssertEqual(shooting.strokeWidth, liveDp(3))
            XCTAssertEqual(horse.strokeWidth, liveDp(1))

            // "bob" has visuals but is not human-selectable: no card is highlighted, BOB's stats are shown.
            let profiles = TripleShotCharacterRoster.humanSelectable()
            let row = find(root, R.id.liveCharacterRow, ALinearLayout.self)!
            let info = find(root, R.id.selectedCharacterInfo, ATextView.self)!
            if TripleShotCharacterVisualCatalog.hasVisuals(characterId: "bob") {
                for index in 0..<row.childCount {
                    XCTAssertEqual((row.getChildAt(index) as? ACardView)?.strokeWidth, liveDp(1), profiles[index].id)
                }
                let bob = TripleShotCharacterRoster.find(id: "bob")!
                XCTAssertEqual(info.text, AFormat.format(
                    ALocale.getDefault(), AResources.getString(R.string.triple_shot_live_setup_character_stats),
                    [bob.displayName, bob.ratings.inside, bob.ratings.midRange, bob.ratings.threePoint,
                     bob.ratings.speed]))
            }

            // A tap on a ready card selects and persists it, and rebuilds the whole row.
            guard let index = profiles.firstIndex(where: {
                $0.id == "nova" && TripleShotCharacterVisualCatalog.hasVisuals(characterId: $0.id)
            }) else { return }
            let oldCard = row.getChildAt(index)!
            XCTAssertTrue(oldCard.performClick())
            XCTAssertEqual(getSharedPreferences("triple_shot", MODE_PRIVATE).getString("player_character", nil), "nova")
            XCTAssertEqual(row.childCount, profiles.count)
            let newCard = row.getChildAt(index) as! ACardView
            XCTAssertFalse(newCard === oldCard)
            XCTAssertEqual(newCard.strokeWidth, liveDp(3))
            XCTAssertEqual(newCard.cardBackgroundColor.defaultColor, AColor.parseColor("#F2FFFC"))
            let nova = profiles[index]
            XCTAssertEqual(info.text, AFormat.format(
                ALocale.getDefault(), AResources.getString(R.string.triple_shot_live_setup_character_stats),
                [nova.displayName, nova.ratings.inside, nova.ratings.midRange, nova.ratings.threePoint,
                 nova.ratings.speed]))
        }
    }

    func testHostedLiveSetupBackWithoutARoomPopsTheBackStack() {
        withFakeMainThread {
            let a = resumedActivity()
            defer { a.performDestroy() }
            let fm = a.supportFragmentManager
            fm.beginTransaction().replace("container", LiveRootFragment()).commitNow()

            // The screen's own back button (the X after TripleShotControls): leaveSetup -> popBackStack().
            let first = TripleShotLiveSetupFragment.newInstance(
                playerName: "Gaya", selectedCategories: [QuestionCategory.MATH], playerCharacterId: "rooza")
            fm.beginTransaction().replace("container", first).addToBackStack("live_setup").commit()
            _ = fm.executePendingTransactions()
            XCTAssertEqual(fm.backStackEntryCount, 1)
            XCTAssertTrue(find(first.requireView(), R.id.backLiveSetupButton, AButton.self)!.performClick())
            AndroidKitTestLoop.runDueMessages()
            XCTAssertEqual(fm.backStackEntryCount, 0)
            XCTAssertFalse(first.isAdded)

            // The kept OnBackPressedCallback (view lifecycle) runs the same leaveSetup.
            let second = TripleShotLiveSetupFragment.newInstance(
                playerName: "Gaya", selectedCategories: [QuestionCategory.MATH], playerCharacterId: "rooza")
            fm.beginTransaction().replace("container", second).addToBackStack("live_setup").commit()
            _ = fm.executePendingTransactions()
            XCTAssertEqual(fm.backStackEntryCount, 1)
            a.onBackPressed()
            AndroidKitTestLoop.runDueMessages()
            XCTAssertEqual(fm.backStackEntryCount, 0)
            XCTAssertFalse(second.isAdded)
        }
    }

    // MARK: - Leaderboard adapter (item_triple_shot_leaderboard.xml + onBindViewHolder)

    /// Android 6c38131: the blank-name fallback and the points unit follow `configuration.locales[0]` (he/iw ->
    /// "שחקן" / "נק׳", else "Player" / "pts"); the name starts at the view start in the locale's direction.
    private func withDeviceLanguage(_ language: String, _ body: () -> Void) {
        let base = AConfiguration.current
        AConfiguration.current = AConfiguration(
            orientation: base.orientation, screenWidthDp: base.screenWidthDp, screenHeightDp: base.screenHeightDp,
            smallestScreenWidthDp: base.smallestScreenWidthDp, densityDpi: base.densityDpi, fontScale: base.fontScale,
            uiMode: base.uiMode, locales: ALocaleList([ALocale(language)]))
        defer { AConfiguration.current = base }
        body()
    }

    func testLeaderboardRowsUseTheKotlinTemplates() {
        withDeviceLanguage("he") { leaderboardRows(player: "\u{05E9}\u{05D7}\u{05E7}\u{05DF}", points: "\u{05E0}\u{05E7}\u{05F3}") }
        withDeviceLanguage("en") { leaderboardRows(player: "Player", points: "pts") }
    }

    private func leaderboardRows(player: String, points: String) {
        let adapter = TripleShotLeaderboardAdapter()
        XCTAssertTrue(ALayoutInflater.isRegistered(R.layout.item_triple_shot_leaderboard))
        let parent = AFrameLayout()
        let holder = adapter.onCreateViewHolder(parent, 0)

        var first = LeaderboardEntry()
        first.name = "Gaya"
        first.bestScore = 120
        first.bestShootingStreak = 5
        first.bestKnowledgeStreak = 3
        var second = LeaderboardEntry()
        second.name = "  "
        second.bestScore = 7
        second.bestShootingStreak = 12
        second.bestKnowledgeStreak = 0

        adapter.submit(newItems: [first, second], mode: TripleShotLeaderboardAdapter.SortMode.SCORE)
        XCTAssertEqual(adapter.getItemCount(), 2)
        adapter.onBindViewHolder(holder, 0)
        XCTAssertEqual(holder.rank.text, "#1")
        XCTAssertEqual(holder.name.text, "Gaya")
        XCTAssertEqual(holder.stats.text, "120 \(points)\n\u{1F3C0} 5  \u{2022}  \u{1F9E0} 3")
        XCTAssertEqual(holder.name.gravity, AGravity.START | AGravity.CENTER_VERTICAL)
        XCTAssertEqual(holder.name.textAlignment, AView.TEXT_ALIGNMENT_VIEW_START)
        XCTAssertEqual(holder.name.textDirection, AView.TEXT_DIRECTION_LOCALE)
        adapter.onBindViewHolder(holder, 1)
        XCTAssertEqual(holder.rank.text, "#2")
        XCTAssertEqual(holder.name.text, player)

        adapter.submit(newItems: [first, second], mode: TripleShotLeaderboardAdapter.SortMode.SHOOTING_STREAK)
        adapter.onBindViewHolder(holder, 1)
        XCTAssertEqual(holder.stats.text, "\u{1F3C0} 12\n7 \(points)")
    }

    func testLeaderboardItemLayoutHasTheXmlTree() {
        let card = TripleShotLeaderboardItemLayout.build()
        XCTAssertTrue(card is ACardView)
        let params = card.layoutParams as? AViewGroup.MarginLayoutParams
        XCTAssertEqual(params?.width, AViewGroup.LayoutParams.MATCH_PARENT)
        XCTAssertEqual(params?.height, AViewGroup.LayoutParams.WRAP_CONTENT)
        XCTAssertEqual(params?.topMargin, px(5))
        XCTAssertEqual(params?.bottomMargin, px(5))
        XCTAssertEqual((card as? ACardView)?.strokeWidth, px(1))
        XCTAssertEqual(find(card, R.id.rankText, ATextView.self)?.layoutParams?.width, px(38))
        XCTAssertEqual(find(card, R.id.nameText, ATextView.self)?.maxLines, 1)
        XCTAssertEqual(find(card, R.id.statsText, ATextView.self)?.gravity, AGravity.END)
    }

    func testRecyclerViewBindsEverySubmittedRow() {
        let adapter = TripleShotLeaderboardAdapter()
        let list = ARecyclerView()
        list.layoutManager = ALinearLayoutManager(nil)
        list.adapter = adapter
        XCTAssertEqual(list.itemViews.count, 0)
        var entry = LeaderboardEntry()
        entry.name = "Comet"
        adapter.submit(newItems: [entry, entry, entry], mode: TripleShotLeaderboardAdapter.SortMode.SCORE)
        XCTAssertEqual(list.itemViews.count, 3)
        let third = list.findViewHolderForAdapterPosition(2) as? TripleShotLeaderboardAdapter.Holder
        XCTAssertEqual(third?.rank.text, "#3")
        // The inflated row keeps the XML root's vertical margins inside the list.
        let rowParams = list.itemViews.first?.layoutParams as? AViewGroup.MarginLayoutParams
        XCTAssertEqual(rowParams?.topMargin, px(5))
        XCTAssertEqual(rowParams?.bottomMargin, px(5))
    }

    func testSortModeIsTheKotlinEnum() {
        XCTAssertEqual(TripleShotLeaderboardAdapter.SortMode.allCases.map { $0.name }, ["SCORE", "SHOOTING_STREAK"])
        XCTAssertEqual(TripleShotLeaderboardAdapter.SortMode.SHOOTING_STREAK.ordinal, 1)
    }

    // MARK: - Leaderboard layout (fragment_triple_shot_leaderboard.xml)

    func testLeaderboardLayoutHasTheXmlTree() {
        let fragment = TripleShotLeaderboardFragment()
        XCTAssertEqual(fragment.contentLayoutId, R.layout.fragment_triple_shot_leaderboard)
        XCTAssertTrue(ALayoutInflater.isRegistered(R.layout.fragment_triple_shot_leaderboard))

        let root = TripleShotLeaderboardLayout.build()
        XCTAssertTrue(root is AConstraintLayout)
        XCTAssertEqual(find(root, R.id.leaderboardTitle, ATextView.self)?.text,
                       AResources.getString(R.string.triple_shot_leaderboard))
        XCTAssertNotNil(find(root, R.id.leaderboardTabs, ATabLayout.self))
        XCTAssertNotNil(find(root, R.id.leaderboardList, ARecyclerView.self))
        XCTAssertEqual(find(root, R.id.leaderboardProgress, AProgressBar.self)?.visibility, AView.VISIBLE)
        let empty = find(root, R.id.leaderboardEmpty, ATextView.self)
        XCTAssertEqual(empty?.text, "\u{05D0}\u{05D9}\u{05DF} \u{05E2}\u{05D3}\u{05D9}\u{05D9}\u{05DF} \u{05EA}\u{05D5}\u{05E6}\u{05D0}\u{05D5}\u{05EA}")
        XCTAssertEqual(empty?.visibility, AView.GONE)
        let back = find(root, R.id.leaderboardBackButton, AButton.self)
        XCTAssertEqual(back?.text, "\u{05D7}\u{05D6}\u{05E8}\u{05D4}")
        XCTAssertEqual(back?.layoutParams?.width, px(52))
        XCTAssertEqual((back?.layoutParams as? AConstraintLayout.LayoutParams)?.topMargin, px(19))
        XCTAssertEqual(find(root, R.id.leaderboardList, ARecyclerView.self)?.paddingBottom, px(12))
    }

    /// Android 6c38131: TripleShotLeaderboardFragment calls `applyGameplayInsets(view, window)`, which pads the whole
    /// layout root by the system-bar and display-cutout insets (the layout keeps its XML margins).
    func testLeaderboardInsetsPadTheWholeRootLikeApplyGameplayInsets() {
        let activity = AActivity()
        let root = TripleShotLeaderboardLayout.build()
        let back = find(root, R.id.leaderboardBackButton, AButton.self)!
        let list = find(root, R.id.leaderboardList, ARecyclerView.self)!
        let base = (root.paddingLeft, root.paddingTop, root.paddingRight, root.paddingBottom)
        applyGameplayInsets(root: root, window: activity.window)

        root.dispatchApplyWindowInsets(AWindowInsetsCompat.fromSafeArea(
            left: 0, top: 177, right: 0, bottom: 102, statusBarVisible: true, imeBottom: 0))
        XCTAssertEqual(root.paddingTop, base.1 + 177)
        XCTAssertEqual(root.paddingBottom, base.3 + 102)
        XCTAssertEqual(root.paddingLeft, base.0)
        XCTAssertEqual(root.paddingRight, base.2)
        XCTAssertEqual((back.layoutParams as! AConstraintLayout.LayoutParams).topMargin, px(19))
        XCTAssertEqual(list.paddingBottom, px(12))

        root.dispatchApplyWindowInsets(AWindowInsetsCompat.fromSafeArea(
            left: 141, top: 0, right: 141, bottom: 63, statusBarVisible: false, imeBottom: 0))
        XCTAssertEqual(root.paddingLeft, base.0 + 141)
        XCTAssertEqual(root.paddingRight, base.2 + 141)
        XCTAssertEqual(root.paddingBottom, base.3 + 63)
        XCTAssertEqual((back.layoutParams as! AConstraintLayout.LayoutParams).marginEnd, px(16))
    }
}
