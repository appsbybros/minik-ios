import Foundation

/// Port of `ui/TripleShotLiveSetupFragment.kt` (Android snapshot dd722e5), statement by statement (spec 19 §4.3 and
/// §4.6.3, room calls spec 05 §4.6), plus `res/layout/fragment_triple_shot_live_setup.xml` built in code
/// (`TripleShotLiveSetupLayout`, registered for `R.layout.fragment_triple_shot_live_setup`).
///
/// Image-first LIVE room creation screen. The screen owns the complete host flow: mode selection, character
/// selection, room creation, lobby state and starting the match. Placeholder portraits are deliberately isolated
/// behind stable drawable names so real artwork can be dropped in later without changing this Fragment.
///
/// The flow states of spec 19 §4.3.2 are, exactly as on Android, the fields below (no extra state object):
/// SETUP = `currentRoomCode == nil` with the setup section shown; CREATING = create button disabled while
/// `createRoom` runs; LOBBY = `currentRoomCode` set, lobby card shown, meta + players listeners attached;
/// STARTING = start button disabled while `startRoom` runs; LAUNCHED = `launchingGame`; CLOSING = `deletingRoom`
/// (listeners already stopped).
///
/// Swift notes: argument labels are the Kotlin parameter names (DESIGN 2.1); units are Android pixels (DESIGN 2.5).
/// Closures kept by views, the back dispatcher and Firebase capture `self` weakly and re-check `isAdded` like the
/// Kotlin lambdas (a released fragment behaves as a not-added one). `throwable.message` is the AndroidKit Throwable
/// message (`AFirebaseException.message`, nil for an unconfigured Firebase, which shows `minik_swish_firebase_error`).
/// The Kotlin-private `playerName`, `selectedCategories`, `placeholderDrawable` and `overall` are internal so the
/// parity tests can check them.
///
/// iOS-only (spec 19 §4.6.3: "iOS keeps the safe area"): the layout's ScrollView adds the system-bar and
/// display-cutout insets to its XML padding, so the scrolling content (including the close X that TripleShotControls
/// places at its top) starts below the status bar / Dynamic Island while the court background and its scrim still
/// fill the whole screen. No on-screen control is added: the screen's own back button (the X after
/// TripleShotControls) already runs `leaveSetup()`, which is what the kept OnBackPressedCallback runs.
final class TripleShotLiveSetupFragment: AFragment {

    private lazy var firebase: TripleShotFirebaseRepository = TripleShotFirebaseRepository()
    private lazy var prefs: ASharedPreferences =
        requireContext().getSharedPreferences(TripleShotLiveSetupFragment.PREFS_NAME, MODE_PRIVATE)

    private var shootingModeCard: ACardView!
    private var horseModeCard: ACardView!
    private var characterRow: ALinearLayout!
    private var selectedCharacterInfo: ATextView!
    private var rulesSummary: ATextView!
    private var setupSection: AView!
    private var lobbyCard: ACardView!
    private var roomCodeText: ATextView!
    private var roomPlayersText: ATextView!
    private var createRoomButton: AButton!
    private var startRoomButton: AButton!
    private var closeRoomButton: AButton!

    private var roomMetaHandle: TripleShotFirebaseRepository.ListenerHandle? = nil
    private var roomPlayersHandle: TripleShotFirebaseRepository.ListenerHandle? = nil

    private var selectedGameType: GameType = GameType.SHOOTING_CHALLENGE
    private var selectedCharacterId: String = TripleShotCharacterRoster.ID_WOMAN_DARK
    private var currentRoomCode: String? = nil
    /// Write-only on Android (assigned on create and on every meta event, never read).
    private var currentSeed: Int64 = 0
    private var launchingGame = false
    private var deletingRoom = false

    /// Kotlin `private val playerName: String get() = requireArguments().getString(ARG_PLAYER_NAME).orEmpty()
    /// .ifBlank { getString(R.string.triple_shot_live_setup_player_fallback) }`.
    var playerName: String {
        let name = requireArguments().getString(TripleShotLiveSetupFragment.ARG_PLAYER_NAME) ?? ""
        return name.kotlinIsBlank ? getString(R.string.triple_shot_live_setup_player_fallback) : name
    }

    /// Kotlin `private val selectedCategories: Set<QuestionCategory>`: the argument names parsed with `valueOf`
    /// (invalid names dropped) in argument order, all topics (ordinal order) when empty. Recomputed on every access.
    var selectedCategories: KLinkedSet<QuestionCategory> {
        let names = requireArguments().getStringArrayList(TripleShotLiveSetupFragment.ARG_CATEGORIES) ?? []
        let categories = KLinkedSet(names.compactMap { name in QuestionCategory.named(name) })
        return categories.isEmpty ? KLinkedSet(QuestionCategory.allCases) : categories
    }

    /// Registers the Swift builder of `R.layout.fragment_triple_shot_live_setup` once (ALayoutInflater).
    private static let layoutRegistration: Void = {
        ALayoutInflater.register(R.layout.fragment_triple_shot_live_setup) { _ in
            TripleShotLiveSetupLayout.build()
        }
    }()

    /// Kotlin `TripleShotLiveSetupFragment : Fragment(R.layout.fragment_triple_shot_live_setup)`.
    override init() {
        super.init(contentLayoutId: R.layout.fragment_triple_shot_live_setup)
        _ = TripleShotLiveSetupFragment.layoutRegistration
    }

    override func onViewCreated(_ view: AView, _ savedInstanceState: ABundle?) {
        super.onViewCreated(view, savedInstanceState)

        shootingModeCard = TripleShotLiveSetupFragment.liveSetupRequireView(view, R.id.shootingModeCard, ACardView.self)
        horseModeCard = TripleShotLiveSetupFragment.liveSetupRequireView(view, R.id.horseModeCard, ACardView.self)
        characterRow = TripleShotLiveSetupFragment.liveSetupRequireView(view, R.id.liveCharacterRow, ALinearLayout.self)
        selectedCharacterInfo =
            TripleShotLiveSetupFragment.liveSetupRequireView(view, R.id.selectedCharacterInfo, ATextView.self)
        rulesSummary = TripleShotLiveSetupFragment.liveSetupRequireView(view, R.id.liveRulesSummary, ATextView.self)
        setupSection = TripleShotLiveSetupFragment.liveSetupRequireView(view, R.id.liveSetupSection, AView.self)
        lobbyCard = TripleShotLiveSetupFragment.liveSetupRequireView(view, R.id.liveLobbyCard, ACardView.self)
        roomCodeText = TripleShotLiveSetupFragment.liveSetupRequireView(view, R.id.liveRoomCodeText, ATextView.self)
        roomPlayersText =
            TripleShotLiveSetupFragment.liveSetupRequireView(view, R.id.liveRoomPlayersText, ATextView.self)
        createRoomButton =
            TripleShotLiveSetupFragment.liveSetupRequireView(view, R.id.createLiveRoomNowButton, AButton.self)
        startRoomButton = TripleShotLiveSetupFragment.liveSetupRequireView(view, R.id.startLiveRoomButton, AButton.self)
        closeRoomButton = TripleShotLiveSetupFragment.liveSetupRequireView(view, R.id.closeLiveRoomButton, AButton.self)

        // requireArguments().getString(ARG_CHARACTER_ID)?.takeIf { id -> hasVisuals(id) } ?: ID_WOMAN_DARK
        let characterArgument = requireArguments().getString(TripleShotLiveSetupFragment.ARG_CHARACTER_ID)
        if let id = characterArgument, TripleShotCharacterVisualCatalog.hasVisuals(characterId: id) {
            selectedCharacterId = id
        } else {
            selectedCharacterId = TripleShotCharacterRoster.ID_WOMAN_DARK
        }

        TripleShotLiveSetupFragment.liveSetupRequireView(view, R.id.backLiveSetupButton, AButton.self)
            .setOnClickListener { [weak self] _ in
                self?.leaveSetup()
            }

        requireActivity().onBackPressedDispatcher.addCallback(
            viewLifecycleOwner,
            AOnBackPressedCallback(true) { [weak self] _ in
                self?.leaveSetup()
            }
        )

        shootingModeCard.setOnClickListener { [weak self] _ in
            guard let self else { return }
            if currentRoomCode == nil {
                selectedGameType = GameType.SHOOTING_CHALLENGE
                renderModeSelection()
            }
        }

        horseModeCard.setOnClickListener { [weak self] _ in
            guard let self else { return }
            if currentRoomCode == nil {
                selectedGameType = GameType.HORSE
                renderModeSelection()
            }
        }

        createRoomButton.setOnClickListener { [weak self] _ in
            self?.createRoom()
        }

        startRoomButton.setOnClickListener { [weak self] _ in
            guard let self else { return }
            guard let code = currentRoomCode else { return }
            startRoomButton.isEnabled = false
            firebase.startRoom(codeRaw: code) { [weak self] result in
                guard let self, self.isAdded else { return }
                if case .failure(let error) = result {
                    startRoomButton.isEnabled = true
                    showError(throwable: error)
                }
            }
        }

        closeRoomButton.setOnClickListener { [weak self] _ in
            self?.closeCurrentRoom(returnHome: false)
        }

        renderModeSelection()
        renderCharacterRow()
        renderRulesSummary()
    }

    private func renderModeSelection() {
        styleModeCard(
            card: shootingModeCard,
            selected: selectedGameType == GameType.SHOOTING_CHALLENGE
        )
        styleModeCard(
            card: horseModeCard,
            selected: selectedGameType == GameType.HORSE
        )
        renderRulesSummary()
    }

    private func styleModeCard(card: ACardView, selected: Bool) {
        card.strokeWidth = dp(value: selected ? 3 : 1)
        card.strokeColor = AColor.parseColor(selected ? "#008B7A" : "#66778B93")
        card.setCardBackgroundColor(
            AColor.parseColor(selected ? "#F4FFFC" : "#F8FFFFFF")
        )
        card.cardElevation = dp(value: selected ? 3 : 0).toFloat()
    }

    private func renderCharacterRow() {
        characterRow.removeAllViews()

        for profile in TripleShotCharacterRoster.humanSelectable() {
            characterRow.addView(createCharacterCard(profile: profile))
        }

        renderSelectedCharacterInfo()
    }

    private func createCharacterCard(profile: TripleShotCharacterProfile) -> AView {
        let selectable = TripleShotCharacterVisualCatalog.hasVisuals(characterId: profile.id)
        let selected = profile.id == selectedCharacterId

        // MaterialCardView(requireContext()).apply { ... }
        let card = ACardView()
        card.radius = dp(value: 18).toFloat()
        card.cardElevation = dp(value: selected ? 4 : 1).toFloat()
        card.strokeWidth = dp(value: selected ? 3 : 1)
        card.strokeColor = AColor.parseColor(selected ? "#008B7A" : "#55778B93")
        card.setCardBackgroundColor(AColor.parseColor(selected ? "#F2FFFC" : "#F4FFFFFF"))
        card.isClickable = selectable
        card.isFocusable = selectable
        card.setAlpha(selectable ? Float(1) : Float(0.58))
        let cardParams = ALinearLayout.LayoutParams(dp(value: 104), dp(value: 154))
        cardParams.marginEnd = dp(value: 9)
        card.layoutParams = cardParams

        let content = ALinearLayout()
        content.orientation = ALinearLayout.VERTICAL
        content.gravity = AGravity.CENTER
        content.setPadding(dp(value: 7))

        let image = AImageView()
        image.setImageResource(placeholderDrawable(characterId: profile.id))
        image.scaleType = AImageView.ScaleType.CENTER_CROP
        image.layoutParams = ALinearLayout.LayoutParams(dp(value: 82), dp(value: 82))

        let name = ATextView()
        name.text = profile.displayName
        name.gravity = AGravity.CENTER
        name.setTextColor(AColor.parseColor("#17252C"))
        name.textSize = Float(12.5)
        name.paint.isFakeBoldText = true
        let nameParams = ALinearLayout.LayoutParams(
            AViewGroup.LayoutParams.MATCH_PARENT,
            AViewGroup.LayoutParams.WRAP_CONTENT
        )
        nameParams.topMargin = dp(value: 4)
        name.layoutParams = nameParams

        let rating = ATextView()
        rating.text = selectable
            ? getString(R.string.triple_shot_live_setup_ovr, overall(profile: profile))
            : getString(R.string.triple_shot_live_setup_coming_soon)
        rating.gravity = AGravity.CENTER
        rating.setTextColor(AColor.parseColor(selectable ? "#008B7A" : "#8A7770"))
        rating.textSize = Float(10.5)

        content.addView(image)
        content.addView(name)
        content.addView(rating)
        card.addView(content)

        if selectable {
            card.setOnClickListener { [weak self] _ in
                guard let self else { return }
                selectedCharacterId = profile.id
                prefs.edit().putString(TripleShotLiveSetupFragment.KEY_PLAYER_CHARACTER, profile.id).apply()
                renderCharacterRow()
            }
        }

        return card
    }

    private func renderSelectedCharacterInfo() {
        let profile = TripleShotCharacterRoster.find(id: selectedCharacterId)
            ?? TripleShotCharacterRoster.womanDark

        selectedCharacterInfo.text = getString(
            R.string.triple_shot_live_setup_character_stats,
            profile.displayName,
            profile.ratings.inside,
            profile.ratings.midRange,
            profile.ratings.threePoint,
            profile.ratings.speed
        )
    }

    private func renderRulesSummary() {
        // `if (!::rulesSummary.isInitialized) return`
        if rulesSummary == nil { return }

        let modeName = getString(
            selectedGameType == GameType.HORSE
                ? R.string.triple_shot_live_setup_horse_title
                : R.string.triple_shot_live_setup_shooting_title
        )

        rulesSummary.text = getString(
            R.string.triple_shot_live_setup_rules,
            modeName,
            selectedCategories.count
        )
    }

    private func createRoom() {
        if currentRoomCode != nil { return }

        createRoomButton.isEnabled = false

        firebase.createRoom(
            playerName: playerName,
            selectedCategories: selectedCategories,
            gameType: selectedGameType,
            // HORSE ignores the timer in-game. Keeping 60 preserves one stable Firebase shape.
            timeLimitSeconds: TripleShotLiveSetupFragment.SHOOTING_CHALLENGE_SECONDS
        ) { [weak self] result in
            guard let self, self.isAdded else { return }

            createRoomButton.isEnabled = true

            switch result {
            case .success(let pair):
                let code = pair.first
                let seed = pair.second
                currentRoomCode = code
                currentSeed = seed
                setupSection.visibility = AView.GONE
                lobbyCard.visibility = AView.VISIBLE
                roomCodeText.text = getString(R.string.triple_shot_live_setup_room_code, code)
                roomPlayersText.text = getString(R.string.triple_shot_live_setup_waiting)
                listenToRoom(code: code)
            case .failure(let error):
                showError(throwable: error)
            }
        }
    }

    private func listenToRoom(code: String) {
        roomMetaHandle?.remove()
        roomPlayersHandle?.remove()

        roomMetaHandle = firebase.listenRoomMeta(codeRaw: code) { [weak self] meta in
            guard let self, self.isAdded else { return }

            guard let meta = meta else {
                if !launchingGame {
                    currentRoomCode = nil
                    setupSection.visibility = AView.VISIBLE
                    lobbyCard.visibility = AView.GONE
                }
                return
            }

            currentSeed = meta.seed

            if meta.status == "PLAYING" && !launchingGame {
                launchingGame = true
                // runCatching { GameType.valueOf(meta.gameType) }.getOrDefault(selectedGameType)
                let gameType = GameType.named(meta.gameType) ?? selectedGameType

                // meta.categories.mapNotNull { valueOf }.toSet().ifEmpty { selectedCategories }
                let metaCategories = KLinkedSet(meta.categories.compactMap { name in QuestionCategory.named(name) })

                (parentFragment as? TripleShotHostFragment)?.startGame(
                    config: TripleShotGameConfig(
                        playerName: playerName,
                        gameType: gameType,
                        limitMode: gameType == GameType.HORSE
                            ? GameLimitMode.BALLS_ONLY
                            : GameLimitMode.TIME_ONLY,
                        selectedCategories: metaCategories.isEmpty ? selectedCategories : metaCategories,
                        roomId: code,
                        roomStartedAtMs: meta.startedAt,
                        playerCharacterId: selectedCharacterId,
                        seed: meta.seed,
                        ballLimit: Int(Int32.max),
                        timeLimitSeconds: gameType == GameType.HORSE
                            ? 0
                            : meta.timeLimitSeconds.coerceAtLeast(10)
                    )
                )
            }
        }

        roomPlayersHandle = firebase.listenRoomPlayers(codeRaw: code) { [weak self] players in
            guard let self, self.isAdded else { return }
            renderPlayers(players: players)
        }
    }

    private func renderPlayers(players: [LivePlayerState]) {
        let names = players
            .prefix(4)
            .map { player in
                player.name.kotlinIsBlank ? getString(R.string.triple_shot_live_setup_player_fallback) : player.name
            }

        roomPlayersText.text = names.isEmpty
            ? getString(R.string.triple_shot_live_setup_waiting)
            : getString(
                R.string.triple_shot_live_setup_players,
                names.joined(separator: "  \u{2022}  ")
            )

        let enoughPlayers = players.count >= 2 && players.count <= 4
        startRoomButton.isEnabled = enoughPlayers
        startRoomButton.setAlpha(enoughPlayers ? Float(1) : Float(0.55))
        startRoomButton.contentDescription = enoughPlayers
            ? startRoomButton.text
            : getString(R.string.triple_shot_live_setup_need_players)
    }

    private func leaveSetup() {
        if currentRoomCode == nil {
            parentFragmentManager.popBackStack()
        } else {
            closeCurrentRoom(returnHome: true)
        }
    }

    private func closeCurrentRoom(returnHome: Bool) {
        guard let code = currentRoomCode else {
            if returnHome { parentFragmentManager.popBackStack() }
            return
        }
        if deletingRoom { return }

        deletingRoom = true
        startRoomButton.isEnabled = false
        closeRoomButton.isEnabled = false

        stopRoomListeners()
        firebase.deleteWaitingRoom(roomCodeRaw: code) { [weak self] result in
            guard let self, self.isAdded else { return }

            deletingRoom = false
            switch result {
            case .success:
                currentRoomCode = nil
                if returnHome {
                    parentFragmentManager.popBackStack()
                } else {
                    setupSection.visibility = AView.VISIBLE
                    lobbyCard.visibility = AView.GONE
                    createRoomButton.isEnabled = true
                    closeRoomButton.isEnabled = true
                }
            case .failure(let error):
                closeRoomButton.isEnabled = true
                showError(throwable: error)
            }
        }
    }

    private func stopRoomListeners() {
        roomMetaHandle?.remove()
        roomPlayersHandle?.remove()
        roomMetaHandle = nil
        roomPlayersHandle = nil
    }

    /// Kotlin `private fun placeholderDrawable(characterId: String): Int` (internal for the parity tests).
    func placeholderDrawable(characterId: String) -> ADrawableRes {
        switch characterId {
        case TripleShotCharacterRoster.ID_ROOZA: return R.drawable.live_character_rooza
        case TripleShotCharacterRoster.ID_NOVA: return R.drawable.live_character_nova
        case TripleShotCharacterRoster.ID_UNICORN_32: return R.drawable.live_character_unicorn32
        case TripleShotCharacterRoster.ID_COACH_67: return R.drawable.live_character_coach67
        case TripleShotCharacterRoster.ID_KYRA: return R.drawable.live_character_kyra
        case TripleShotCharacterRoster.ID_ZEPHYR: return R.drawable.live_character_zephyr
        case TripleShotCharacterRoster.ID_ACE_23: return R.drawable.live_character_ace23
        case TripleShotCharacterRoster.ID_BUDDY_23: return R.drawable.live_character_buddy23
        default: return R.drawable.live_character_maya
        }
    }

    /// Kotlin `private fun overall(profile)`: the integer mean of the nine visible ratings (internal for the tests).
    func overall(profile: TripleShotCharacterProfile) -> Int {
        let r = profile.ratings
        let sum: Int = r.inside + r.midRange + r.threePoint + r.speed + r.strength +
            r.height + r.blocking + r.stealing + r.ballHandling
        return sum / 9
    }

    private func showError(throwable: Error) {
        AToast.makeText(
            requireContext(),
            liveSetupThrowableMessage(throwable) ?? getString(R.string.minik_swish_firebase_error),
            AToast.LENGTH_LONG
        ).show()
    }

    /// `(value * resources.displayMetrics.density + 0.5f).toInt()`: rounding (unlike the setup dialogs).
    private func dp(value: Int) -> Int {
        return (value.toFloat() * resources.displayMetrics.density + Float(0.5)).toInt()
    }

    override func onDestroyView() {
        stopRoomListeners()
        super.onDestroyView()
    }

    /// `view.findViewById(id)` assigned to a non-null Kotlin property (crashes when missing, like Kotlin's check).
    private static func liveSetupRequireView<T: AView>(_ root: AView, _ id: String, _ type: T.Type) -> T {
        let found: T? = root.findViewById(id)
        return found!
    }

    // MARK: - companion object

    private static let ARG_PLAYER_NAME = "player_name"
    private static let ARG_CATEGORIES = "categories"
    private static let ARG_CHARACTER_ID = "character_id"
    private static let SHOOTING_CHALLENGE_SECONDS = 60
    private static let PREFS_NAME = "triple_shot"
    private static let KEY_PLAYER_CHARACTER = "player_character"

    /// Kotlin `newInstance(playerName, selectedCategories: Set<QuestionCategory>, playerCharacterId)`. Any ordered
    /// sequence of topics is accepted and keeps Kotlin Set semantics (first occurrence wins, iteration order kept).
    static func newInstance<S: Sequence>(
        playerName: String,
        selectedCategories: S,
        playerCharacterId: String
    ) -> TripleShotLiveSetupFragment where S.Element == QuestionCategory {
        let categories = KLinkedSet(selectedCategories)
        let fragment = TripleShotLiveSetupFragment()
        let arguments = ABundle()
        arguments.putString(ARG_PLAYER_NAME, playerName)
        arguments.putStringArrayList(
            ARG_CATEGORIES,
            categories.elements.map { category in category.name }
        )
        arguments.putString(ARG_CHARACTER_ID, playerCharacterId)
        fragment.arguments = arguments
        return fragment
    }
}

/// Kotlin `throwable.message` of a repository / Firebase failure: AndroidKit's Throwable is AFirebaseException (nil
/// message only for an unconfigured Firebase); any other error gives its LocalizedError description, like
/// TripleShotHomeFragment's helper.
private func liveSetupThrowableMessage(_ throwable: Error) -> String? {
    if let exception = throwable as? AFirebaseException { return exception.message }
    return (throwable as? LocalizedError)?.errorDescription
}

// MARK: - res/layout/fragment_triple_shot_live_setup.xml

/// The view tree of `res/layout/fragment_triple_shot_live_setup.xml`, built in code with the XML's ids, attributes and
/// layout params in XML order (DESIGN 2.8). Dimensions are read like the Android inflater reads them: sizes, margins,
/// paddings, text sizes, button corner radii and card stroke widths as pixel sizes (`getDimensionPixelSize`, rounded),
/// card corner radii and elevations as exact dimensions (`getDimension`). Button styles are the AndroidKit widget
/// styles (`Widget.MaterialComponents.Button.TextButton` -> `.TEXT`, `...OutlinedButton` -> `.OUTLINED`). The
/// app-wide restylers (FamilySkyUi / TripleShotControls) run on this tree from the activity's decor view, as on
/// Android: the "‹" back button becomes the red close X in a new top-end row, every tinted button a sky face.
///
/// `android:foreground="?attr/selectableItemBackground"` of the two mode cards has no effect on Android
/// (MaterialCardViewHelper installs its own ripple + stroke foreground over it) and is not set here.
///
/// iOS-only (spec 19 §4.6.3): the ScrollView adds the system-bar + display-cutout insets to its XML padding.
enum TripleShotLiveSetupLayout {

    /// `getDimensionPixelSize` of an XML `Ndp`.
    static func px(_ dp: Float) -> Int {
        ATypedValue.toDimensionPixelSize(ATypedValue.COMPLEX_UNIT_DIP, dp)
    }

    /// `getDimension` of an XML `Ndp`.
    static func dimen(_ dp: Float) -> Float {
        ATypedValue.applyDimension(ATypedValue.COMPLEX_UNIT_DIP, dp)
    }

    /// `android:textStyle="bold"` (TextView.setTypefaceFromAttrs: the family's face, then setTypeface(tf, BOLD)).
    static func bold(_ textView: ATextView) {
        textView.setTypeface(textView.typeface, ATypeface.BOLD)
    }

    static func build() -> AView {
        let MATCH = AViewGroup.LayoutParams.MATCH_PARENT
        let WRAP = AViewGroup.LayoutParams.WRAP_CONTENT

        // <FrameLayout match_parent x match_parent>
        let root = AFrameLayout()
        root.layoutParams = AViewGroup.LayoutParams(MATCH, MATCH)

        // <ImageView match x match contentDescription @null scaleType centerCrop src @drawable/triple_shot_court_background>
        let background = AImageView()
        background.scaleType = AImageView.ScaleType.CENTER_CROP
        background.setImageResource(R.drawable.triple_shot_court_background)
        root.addView(background, AFrameLayout.LayoutParams(MATCH, MATCH))

        // <View match x match background #4D0B1820>
        let scrim = AView()
        scrim.setBackgroundColor(AColor.parseColor("#4D0B1820"))
        root.addView(scrim, AFrameLayout.LayoutParams(MATCH, MATCH))

        // <ScrollView match x match clipToPadding false fillViewport true paddingStart 14dp paddingTop 18dp
        //  paddingEnd 14dp paddingBottom 20dp>
        let scroll = AScrollView()
        scroll.clipToPadding = false
        scroll.isFillViewport = true
        scroll.setPaddingRelative(px(14), px(18), px(14), px(20))
        // iOS-only (spec 19 §4.6.3, "iOS keeps the safe area"): the XML padding plus the safe-area insets. The XML
        // start and end paddings are equal, so the physical form is the same in both layout directions.
        let paddingSide = px(14)
        let paddingTop = px(18)
        let paddingBottom = px(20)
        AViewCompat.setOnApplyWindowInsetsListener(scroll) { v, insets in
            let safe = insets.getInsets(AWindowInsetsCompat.systemBars() | AWindowInsetsCompat.displayCutout())
            v.setPadding(
                paddingSide + safe.left,
                paddingTop + safe.top,
                paddingSide + safe.right,
                paddingBottom + safe.bottom
            )
            return insets
        }

        //   <LinearLayout match x wrap gravity center_horizontal vertical>
        let column = ALinearLayout()
        column.gravity = AGravity.CENTER_HORIZONTAL
        column.orientation = ALinearLayout.VERTICAL

        //     <LinearLayout match x wrap gravity center_vertical horizontal>
        let header = ALinearLayout()
        header.gravity = AGravity.CENTER_VERTICAL
        header.orientation = ALinearLayout.HORIZONTAL

        //       <TripleShotButton @+id/backLiveSetupButton style TextButton 48dp x 48dp contentDescription
        //        @string/triple_shot_live_setup_back minWidth 0dp text @string/triple_shot_live_setup_back_glyph
        //        textSize 30sp cornerRadius 24dp>
        let back = TripleShotButton(style: .TEXT)
        back.viewId = R.id.backLiveSetupButton
        back.contentDescription = getString(R.string.triple_shot_live_setup_back)
        back.minWidth = 0
        back.minimumWidth = 0
        back.setText(res: R.string.triple_shot_live_setup_back_glyph)
        back.applyXmlTextSize(30)
        back.setCornerRadius(px(24))
        header.addView(back, ALinearLayout.LayoutParams(px(48), px(48)))

        //       <LinearLayout 0dp x wrap weight 1 gravity center vertical>
        let titles = ALinearLayout()
        titles.gravity = AGravity.CENTER
        titles.orientation = ALinearLayout.VERTICAL

        //         <TextView wrap x wrap text @string/triple_shot_live_setup_title #FFFFFF 25sp bold>
        let title = ATextView()
        title.setText(res: R.string.triple_shot_live_setup_title)
        title.setTextColor(AColor.parseColor("#FFFFFF"))
        title.applyXmlTextSize(25)
        bold(title)
        titles.addView(title, ALinearLayout.LayoutParams(WRAP, WRAP))

        //         <TextView wrap x wrap marginTop 2dp gravity center text @string/triple_shot_live_setup_subtitle
        //          #E8FFFFFF 13sp>
        let subtitle = ATextView()
        subtitle.gravity = AGravity.CENTER
        subtitle.setText(res: R.string.triple_shot_live_setup_subtitle)
        subtitle.setTextColor(AColor.parseColor("#E8FFFFFF"))
        subtitle.applyXmlTextSize(13)
        let subtitleParams = ALinearLayout.LayoutParams(WRAP, WRAP)
        subtitleParams.topMargin = px(2)
        titles.addView(subtitle, subtitleParams)
        header.addView(titles, ALinearLayout.LayoutParams(0, WRAP, 1))

        //       <Space 48dp x 1dp>
        header.addView(ASpace(), ALinearLayout.LayoutParams(px(48), px(1)))
        column.addView(header, ALinearLayout.LayoutParams(MATCH, WRAP))

        //     <MaterialCardView @+id/liveSetupCard match x wrap marginTop 14dp cardBackgroundColor #F2FFFFFF
        //      cardCornerRadius 28dp cardElevation 7dp strokeColor #66FFFFFF strokeWidth 1dp>
        let setupCard = ACardView()
        setupCard.viewId = R.id.liveSetupCard
        setupCard.setCardBackgroundColor(AColor.parseColor("#F2FFFFFF"))
        setupCard.radius = dimen(28)
        setupCard.cardElevation = dimen(7)
        setupCard.setStrokeColor(AColorStateList.valueOf(AColor.parseColor("#66FFFFFF")))
        setupCard.strokeWidth = px(1)
        let setupCardParams = ALinearLayout.LayoutParams(MATCH, WRAP)
        setupCardParams.topMargin = px(14)

        //       <LinearLayout @+id/liveSetupSection match x wrap vertical padding 16dp>
        let section = ALinearLayout()
        section.viewId = R.id.liveSetupSection
        section.orientation = ALinearLayout.VERTICAL
        section.setPadding(px(16), px(16), px(16), px(16))

        //         <TextView wrap x wrap text @string/triple_shot_live_setup_mode_title #17252C 17sp bold>
        let modeTitle = ATextView()
        modeTitle.setText(res: R.string.triple_shot_live_setup_mode_title)
        modeTitle.setTextColor(AColor.parseColor("#17252C"))
        modeTitle.applyXmlTextSize(17)
        bold(modeTitle)
        section.addView(modeTitle, ALinearLayout.LayoutParams(WRAP, WRAP))

        //         <LinearLayout match x wrap marginTop 10dp horizontal>
        let modeRow = ALinearLayout()
        modeRow.orientation = ALinearLayout.HORIZONTAL
        let modeRowParams = ALinearLayout.LayoutParams(MATCH, WRAP)
        modeRowParams.topMargin = px(10)

        //           <MaterialCardView 0dp x 130dp weight 1 clickable focusable foreground ?attr/selectableItemBackground
        //            cardBackgroundColor #F8FFFFFF cardCornerRadius 20dp cardElevation 0dp strokeColor #60778B93
        //            strokeWidth 1dp>
        //             <LinearLayout match x match gravity center vertical padding 10dp>
        //               <TextView wrap x wrap text icon 31sp>
        //               <TextView wrap x wrap marginTop 4dp gravity center text title #17252C 15sp bold>
        //               <TextView wrap x wrap marginTop 3dp gravity center text description #6A747A 11sp>
        func modeCard(_ id: String, _ icon: AStringRes, _ titleRes: AStringRes, _ descriptionRes: AStringRes) -> ACardView {
            let card = ACardView()
            card.viewId = id
            card.isClickable = true
            card.isFocusable = true
            card.setCardBackgroundColor(AColor.parseColor("#F8FFFFFF"))
            card.radius = dimen(20)
            card.cardElevation = dimen(0)
            card.setStrokeColor(AColorStateList.valueOf(AColor.parseColor("#60778B93")))
            card.strokeWidth = px(1)

            let body = ALinearLayout()
            body.gravity = AGravity.CENTER
            body.orientation = ALinearLayout.VERTICAL
            body.setPadding(px(10), px(10), px(10), px(10))

            let iconText = ATextView()
            iconText.setText(res: icon)
            iconText.applyXmlTextSize(31)
            body.addView(iconText, ALinearLayout.LayoutParams(WRAP, WRAP))

            let titleText = ATextView()
            titleText.gravity = AGravity.CENTER
            titleText.setText(res: titleRes)
            titleText.setTextColor(AColor.parseColor("#17252C"))
            titleText.applyXmlTextSize(15)
            bold(titleText)
            let titleParams = ALinearLayout.LayoutParams(WRAP, WRAP)
            titleParams.topMargin = px(4)
            body.addView(titleText, titleParams)

            let descriptionText = ATextView()
            descriptionText.gravity = AGravity.CENTER
            descriptionText.setText(res: descriptionRes)
            descriptionText.setTextColor(AColor.parseColor("#6A747A"))
            descriptionText.applyXmlTextSize(11)
            let descriptionParams = ALinearLayout.LayoutParams(WRAP, WRAP)
            descriptionParams.topMargin = px(3)
            body.addView(descriptionText, descriptionParams)

            card.addView(body, AFrameLayout.LayoutParams(MATCH, MATCH))
            return card
        }

        //           <MaterialCardView @+id/shootingModeCard ... marginEnd 6dp>
        let shootingModeCard = modeCard(
            R.id.shootingModeCard,
            R.string.triple_shot_live_setup_icon_shooting,
            R.string.triple_shot_live_setup_shooting_title,
            R.string.triple_shot_live_setup_shooting_desc
        )
        let shootingParams = ALinearLayout.LayoutParams(0, px(130), 1)
        shootingParams.marginEnd = px(6)
        modeRow.addView(shootingModeCard, shootingParams)

        //           <MaterialCardView @+id/horseModeCard ... marginStart 6dp>
        let horseModeCard = modeCard(
            R.id.horseModeCard,
            R.string.triple_shot_live_setup_icon_horse,
            R.string.triple_shot_live_setup_horse_title,
            R.string.triple_shot_live_setup_horse_desc
        )
        let horseParams = ALinearLayout.LayoutParams(0, px(130), 1)
        horseParams.marginStart = px(6)
        modeRow.addView(horseModeCard, horseParams)
        section.addView(modeRow, modeRowParams)

        //         <TextView wrap x wrap marginTop 18dp text @string/triple_shot_live_setup_character_title #17252C 17sp bold>
        let characterTitle = ATextView()
        characterTitle.setText(res: R.string.triple_shot_live_setup_character_title)
        characterTitle.setTextColor(AColor.parseColor("#17252C"))
        characterTitle.applyXmlTextSize(17)
        bold(characterTitle)
        let characterTitleParams = ALinearLayout.LayoutParams(WRAP, WRAP)
        characterTitleParams.topMargin = px(18)
        section.addView(characterTitle, characterTitleParams)

        //         <HorizontalScrollView match x wrap marginTop 9dp clipToPadding false fillViewport false
        //          overScrollMode never scrollbars none>
        let strip = AHorizontalScrollView()
        strip.clipToPadding = false
        strip.isFillViewport = false
        strip.overScrollMode = AView.OVER_SCROLL_NEVER
        strip.isHorizontalScrollBarEnabled = false
        strip.isVerticalScrollBarEnabled = false
        let stripParams = ALinearLayout.LayoutParams(MATCH, WRAP)
        stripParams.topMargin = px(9)

        //           <LinearLayout @+id/liveCharacterRow wrap x wrap horizontal paddingEnd 8dp>
        let characterRow = ALinearLayout()
        characterRow.viewId = R.id.liveCharacterRow
        characterRow.orientation = ALinearLayout.HORIZONTAL
        characterRow.setPaddingRelative(0, 0, px(8), 0)
        strip.addView(characterRow, AFrameLayout.LayoutParams(WRAP, WRAP))
        section.addView(strip, stripParams)

        //         <TextView @+id/selectedCharacterInfo match x wrap marginTop 10dp background #1300877A gravity center
        //          padding 10dp #27414A 12sp>
        let selectedCharacterInfo = ATextView()
        selectedCharacterInfo.viewId = R.id.selectedCharacterInfo
        selectedCharacterInfo.setBackgroundColor(AColor.parseColor("#1300877A"))
        selectedCharacterInfo.gravity = AGravity.CENTER
        selectedCharacterInfo.setPadding(px(10), px(10), px(10), px(10))
        selectedCharacterInfo.setTextColor(AColor.parseColor("#27414A"))
        selectedCharacterInfo.applyXmlTextSize(12)
        let selectedCharacterInfoParams = ALinearLayout.LayoutParams(MATCH, WRAP)
        selectedCharacterInfoParams.topMargin = px(10)
        section.addView(selectedCharacterInfo, selectedCharacterInfoParams)

        //         <TextView @+id/liveRulesSummary match x wrap marginTop 12dp gravity center #5B666C 12sp>
        let rulesSummary = ATextView()
        rulesSummary.viewId = R.id.liveRulesSummary
        rulesSummary.gravity = AGravity.CENTER
        rulesSummary.setTextColor(AColor.parseColor("#5B666C"))
        rulesSummary.applyXmlTextSize(12)
        let rulesSummaryParams = ALinearLayout.LayoutParams(MATCH, WRAP)
        rulesSummaryParams.topMargin = px(12)
        section.addView(rulesSummary, rulesSummaryParams)

        //         <TripleShotButton @+id/createLiveRoomNowButton match x 54dp marginTop 14dp text
        //          @string/triple_shot_live_setup_create textAllCaps false 16sp bold backgroundTint #008B7A
        //          cornerRadius 20dp>
        let createButton = TripleShotButton()
        createButton.viewId = R.id.createLiveRoomNowButton
        createButton.setText(res: R.string.triple_shot_live_setup_create)
        createButton.setAllCaps(false)
        createButton.applyXmlTextSize(16)
        bold(createButton)
        createButton.setCornerRadius(px(20))
        createButton.setBackgroundTintList(AColorStateList.valueOf(AColor.parseColor("#008B7A")))
        let createParams = ALinearLayout.LayoutParams(MATCH, px(54))
        createParams.topMargin = px(14)
        section.addView(createButton, createParams)
        setupCard.addView(section, AFrameLayout.LayoutParams(MATCH, WRAP))
        column.addView(setupCard, setupCardParams)

        //     <MaterialCardView @+id/liveLobbyCard match x wrap marginTop 14dp visibility gone cardBackgroundColor
        //      #F5FFFFFF cardCornerRadius 28dp cardElevation 7dp strokeColor #66FFFFFF strokeWidth 1dp>
        let lobbyCard = ACardView()
        lobbyCard.viewId = R.id.liveLobbyCard
        lobbyCard.visibility = AView.GONE
        lobbyCard.setCardBackgroundColor(AColor.parseColor("#F5FFFFFF"))
        lobbyCard.radius = dimen(28)
        lobbyCard.cardElevation = dimen(7)
        lobbyCard.setStrokeColor(AColorStateList.valueOf(AColor.parseColor("#66FFFFFF")))
        lobbyCard.strokeWidth = px(1)
        let lobbyCardParams = ALinearLayout.LayoutParams(MATCH, WRAP)
        lobbyCardParams.topMargin = px(14)

        //       <LinearLayout match x wrap gravity center_horizontal vertical padding 18dp>
        let lobby = ALinearLayout()
        lobby.gravity = AGravity.CENTER_HORIZONTAL
        lobby.orientation = ALinearLayout.VERTICAL
        lobby.setPadding(px(18), px(18), px(18), px(18))

        //         <TextView wrap x wrap text @string/triple_shot_live_setup_room_ready #17252C 20sp bold>
        let roomReady = ATextView()
        roomReady.setText(res: R.string.triple_shot_live_setup_room_ready)
        roomReady.setTextColor(AColor.parseColor("#17252C"))
        roomReady.applyXmlTextSize(20)
        bold(roomReady)
        lobby.addView(roomReady, ALinearLayout.LayoutParams(WRAP, WRAP))

        //         <TextView @+id/liveRoomCodeText wrap x wrap marginTop 8dp letterSpacing 0.12 #008B7A 26sp bold>
        let roomCodeText = ATextView()
        roomCodeText.viewId = R.id.liveRoomCodeText
        roomCodeText.setLetterSpacing(Float(0.12))
        roomCodeText.setTextColor(AColor.parseColor("#008B7A"))
        roomCodeText.applyXmlTextSize(26)
        bold(roomCodeText)
        let roomCodeParams = ALinearLayout.LayoutParams(WRAP, WRAP)
        roomCodeParams.topMargin = px(8)
        lobby.addView(roomCodeText, roomCodeParams)

        //         <TextView @+id/liveRoomPlayersText match x wrap marginTop 12dp gravity center text
        //          @string/triple_shot_live_setup_waiting #526169 13sp>
        let roomPlayersText = ATextView()
        roomPlayersText.viewId = R.id.liveRoomPlayersText
        roomPlayersText.gravity = AGravity.CENTER
        roomPlayersText.setText(res: R.string.triple_shot_live_setup_waiting)
        roomPlayersText.setTextColor(AColor.parseColor("#526169"))
        roomPlayersText.applyXmlTextSize(13)
        let roomPlayersParams = ALinearLayout.LayoutParams(MATCH, WRAP)
        roomPlayersParams.topMargin = px(12)
        lobby.addView(roomPlayersText, roomPlayersParams)

        //         <TripleShotButton @+id/startLiveRoomButton match x 52dp marginTop 16dp enabled false text
        //          @string/triple_shot_live_setup_start textAllCaps false bold backgroundTint #008B7A cornerRadius 18dp>
        let startButton = TripleShotButton()
        startButton.viewId = R.id.startLiveRoomButton
        startButton.isEnabled = false
        startButton.setText(res: R.string.triple_shot_live_setup_start)
        startButton.setAllCaps(false)
        bold(startButton)
        startButton.setCornerRadius(px(18))
        startButton.setBackgroundTintList(AColorStateList.valueOf(AColor.parseColor("#008B7A")))
        let startParams = ALinearLayout.LayoutParams(MATCH, px(52))
        startParams.topMargin = px(16)
        lobby.addView(startButton, startParams)

        //         <TripleShotButton @+id/closeLiveRoomButton style OutlinedButton match x 48dp marginTop 8dp text
        //          @string/triple_shot_live_setup_close textAllCaps false #7B3A32 cornerRadius 18dp strokeColor #B86A5C>
        let closeButton = TripleShotButton(style: .OUTLINED)
        closeButton.viewId = R.id.closeLiveRoomButton
        closeButton.setText(res: R.string.triple_shot_live_setup_close)
        closeButton.setAllCaps(false)
        closeButton.setTextColor(AColor.parseColor("#7B3A32"))
        closeButton.setCornerRadius(px(18))
        closeButton.setStrokeColor(AColorStateList.valueOf(AColor.parseColor("#B86A5C")))
        let closeParams = ALinearLayout.LayoutParams(MATCH, px(48))
        closeParams.topMargin = px(8)
        lobby.addView(closeButton, closeParams)
        lobbyCard.addView(lobby, AFrameLayout.LayoutParams(MATCH, WRAP))
        column.addView(lobbyCard, lobbyCardParams)

        scroll.addView(column, AFrameLayout.LayoutParams(MATCH, WRAP))
        root.addView(scroll, AFrameLayout.LayoutParams(MATCH, MATCH))

        return root
    }
}
