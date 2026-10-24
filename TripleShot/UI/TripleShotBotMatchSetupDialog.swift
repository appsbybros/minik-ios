import Foundation

// Port of ui/TripleShotBotMatchSetupDialog.kt (TripleShotGame dd722e5), spec 19 sections 4.1, 4.5, 4.6.1, 7 and 8.
//
// The single "Play vs bot" surface: one fixed-size custom ADialog (width = FamilyReadingPanel.contentWidth of 94 % of
// the window width, height = 91 % of the window height, transparent window background, dim 0.58, no window animation,
// cancelled by a tap outside) whose views are built in code exactly like the Kotlin (AndroidKit layouts, ATextView,
// AImageView, SkyMaterialCardView, TripleShotButton), decorated by FamilySkyUi.watch (every button becomes an 18 dp
// sky face with the TripleShotButton ink rule) and TripleShotControls.watch (no button text here is in its list).
// The light dialog look is AndroidKit's (DESIGN 4.5): light surfaces and dark text even in iOS Dark Mode.
//
// Structure. Kotlin keeps the dialog state in local `var`s of `show`, captured by its lambdas (shared Ref boxes). Here
// that state lives in one reference object, `SetupState`, together with the local functions that touch only state:
// isAuthoredReady, teamSelectionPool, assignUniqueRoster, randomizeTeams, ensureSlots and selectedIdsExcept (Kotlin
// names), plus five pieces cut out of view code so the parity tests can run them: the `onOrientationChanged` body of
// the OrientationEventListener object, the court rules of refreshPresentation (`normalizeCourt`,
// `courtButtonVisibility`), the choice list of showProfilePicker (`profilePickerChoices`) and the checks + result of
// the Start listener (`startSelection`).
// Every call happens at the Kotlin statement position; view building stays in `show` in Kotlin order.
//
// Kept Android behaviour (spec 19 section 8): the CharacterSections follow only their own taps (stale highlight after
// Game mode, 8.1); 2 x 2 / 3 x 3 re-randomise every slot including your own (8.2); the same character on both sides is
// allowed in Shooting / HORSE (8.3); BOB can fill your own Game slot (8.4); the court survives mode changes and
// normalises to Sunset Pulse (8.5); the physical orientation comes from the raw accelerometer through
// AOrientationEventListener, never from UIDevice.orientation (8.6); the "Choose player" strip is forced LTR and
// scrolled to x = 0 (8.7); names clip without ellipsis (8.9); the dialog height is fixed (8.11).
//
// iOS: Android's Back key cancels this dialog and its "Choose player" popup; both have a Cancel button and close on a
// tap outside (as on Android), so no extra on-screen control is added. `pool.shuffled()` (Kotlin: unseeded
// java.util.Collections.shuffle) draws from KotlinRandom.Default. The lambdas form reference cycles through the
// dialog's views (a size button's listener reaches the map that holds the button), which the JVM collects and ARC does
// not: closures hold the dialogs weakly, and the click listeners of the dismissed dialog's views are dropped on dismiss
// (a dismissed dialog is never shown again, so nothing observable changes).

/// Bot-game setup: Shooting Challenge, HORSE or a basketball Game (1v1 / 2v2 / 3v3).
enum TripleShotBotMatchSetupDialog {

    struct Selection: Equatable {
        var gameType: GameType
        var teamSize: Int
        var human: TripleShotCharacterProfile
        var teammates: [TripleShotCharacterProfile]
        var opponents: [TripleShotCharacterProfile]
        var gameOrientation: TripleShotGameOrientation
        var courtId: String
    }

    /// The local `var`s of Kotlin `show` (lines 105-127 and 328-330) and the local functions that only read and write
    /// them (332-394), in one reference object shared by the dialog's listeners like Kotlin's captured Ref boxes.
    final class SetupState {
        /// Team mode exposes only genuine 1672x941 two-basket courts (refreshPresentation, 232-233).
        static let fullCourtIds: Set<String> = ["sunset_pulse", "sunset_cove", "neon_tide", "neon_falls"]
        static let teamOnlyFullCourtIds: Set<String> = ["sunset_cove", "neon_tide", "neon_falls"]

        let canSelectHuman: (TripleShotCharacterProfile) -> Bool
        let canSelectBot: (TripleShotCharacterProfile) -> Bool
        /// The generator of `pool.shuffled()` in randomizeTeams.
        let random: KotlinRandom

        var selectedMode = GameType.SHOOTING_CHALLENGE
        var selectedTeamSize = 1
        var physicalGameOrientation: TripleShotGameOrientation
        var selectedCourtId = TripleShotCourtCatalog.DEFAULT_ID
        var selectedHuman: TripleShotCharacterProfile
        var selectedPrimaryBot: TripleShotCharacterProfile
        var selectedTeammates: [TripleShotCharacterProfile] = []
        var selectedOpponents: [TripleShotCharacterProfile]

        let allTeamProfiles: [TripleShotCharacterProfile]

        /// `humanProfiles` / `botProfiles` must not be empty (`show` returns before creating the state otherwise).
        init(
            humanProfiles: [TripleShotCharacterProfile],
            botProfiles: [TripleShotCharacterProfile],
            currentHumanId: String,
            currentBotId: String,
            canSelectHuman: @escaping (TripleShotCharacterProfile) -> Bool,
            canSelectBot: @escaping (TripleShotCharacterProfile) -> Bool,
            physicalGameOrientation: TripleShotGameOrientation,
            random: KotlinRandom = KotlinRandom.Default
        ) {
            self.canSelectHuman = canSelectHuman
            self.canSelectBot = canSelectBot
            self.random = random
            self.physicalGameOrientation = physicalGameOrientation
            let human = humanProfiles.first { $0.id == currentHumanId && canSelectHuman($0) }
                ?? humanProfiles.first(where: canSelectHuman) ?? humanProfiles.first!
            let primaryBot = botProfiles.first { $0.id == currentBotId && canSelectBot($0) }
                ?? botProfiles.first(where: canSelectBot) ?? botProfiles.first!
            selectedHuman = human
            selectedPrimaryBot = primaryBot
            selectedOpponents = [primaryBot]
            allTeamProfiles =
                (humanProfiles + botProfiles)
                    .kDistinctBy { $0.id }
        }

        func isAuthoredReady(profile: TripleShotCharacterProfile) -> Bool {
            return canSelectHuman(profile) || canSelectBot(profile)
        }

        /*
         * 3v3 needs six unique identities. We prefer authored runtime packs; if fewer than six are
         * currently ready, fill the last slot from the visible roster rather than duplicating Maya
         * or any other character. TeamCourt has a legacy fallback for that temporary art debt.
         */
        func teamSelectionPool(required: Int) -> [TripleShotCharacterProfile] {
            let ready = allTeamProfiles.filter { isAuthoredReady(profile: $0) }
            if ready.count >= required { return ready }
            return ready + allTeamProfiles.filter { candidate in !ready.contains { $0.id == candidate.id } }
        }

        func assignUniqueRoster(roster: [TripleShotCharacterProfile]) {
            if roster.isEmpty { return }
            let required = selectedTeamSize * 2
            let pool = teamSelectionPool(required: required)
            let clean = Array(
                (roster + pool)
                    .kDistinctBy { $0.id }
                    .prefix(required)
            )
            if clean.count < required { return }

            selectedHuman = clean[0]
            selectedTeammates.removeAll()
            selectedTeammates += clean[1..<selectedTeamSize]
            selectedOpponents.removeAll()
            selectedOpponents += clean[selectedTeamSize..<required]
            selectedPrimaryBot = selectedOpponents.first!
        }

        func randomizeTeams() {
            let required = selectedTeamSize * 2
            let pool = teamSelectionPool(required: required)
            if pool.count < required { return }
            assignUniqueRoster(roster: Array(pool.kShuffled(random).prefix(required)))
        }

        func ensureSlots() {
            if selectedMode != GameType.ONE_ON_ONE && selectedMode != GameType.TEAM_MATCH { return }
            let required = selectedTeamSize * 2
            var current: [TripleShotCharacterProfile] = []
            current.append(selectedHuman)
            current += selectedTeammates
            current += selectedOpponents
            assignUniqueRoster(roster: current)
            if selectedTeammates.count != selectedTeamSize - 1 ||
                selectedOpponents.count != selectedTeamSize ||
                ([selectedHuman] + selectedTeammates + selectedOpponents).map({ $0.id }).kDistinct().count != required {
                randomizeTeams()
            }
        }

        func selectedIdsExcept(currentId: String) -> Set<String> {
            return Set(
                ([selectedHuman] + selectedTeammates + selectedOpponents)
                    .map { $0.id }
                    .filter { $0 != currentId }
            )
        }

        /// The `onOrientationChanged` override of Kotlin's OrientationEventListener object (112-118): flat
        /// (ORIENTATION_UNKNOWN) keeps the last value; 45..134 and 225..314 degrees are landscape.
        func onOrientationChanged(orientation: Int) {
            if orientation == AOrientationEventListener.ORIENTATION_UNKNOWN { return }
            physicalGameOrientation =
                (45...134).contains(orientation) || (225...314).contains(orientation)
                    ? TripleShotGameOrientation.LANDSCAPE
                    : TripleShotGameOrientation.PORTRAIT
        }

        /// The two court rules of refreshPresentation (234-235). Preserve the user's selected compatible full-court
        /// instead of forcing Sunset every refresh.
        func normalizeCourt() {
            let isTeamFullCourt = selectedMode == GameType.TEAM_MATCH
            if isTeamFullCourt && !SetupState.fullCourtIds.contains(selectedCourtId) { selectedCourtId = "sunset_pulse" }
            if !isTeamFullCourt && SetupState.teamOnlyFullCourtIds.contains(selectedCourtId) { selectedCourtId = "sunset_pulse" }
        }

        /// The `when` of a court button's visibility in refreshPresentation (238-243): team mode shows only the full
        /// courts, every other mode hides the team-only ones.
        static func courtButtonVisibility(id: String, isTeamFullCourt: Bool) -> Int {
            if isTeamFullCourt { return fullCourtIds.contains(id) ? AView.VISIBLE : AView.GONE }
            if teamOnlyFullCourtIds.contains(id) { return AView.GONE }
            return AView.VISIBLE
        }

        /// The choices of showProfilePicker (459-463): the team pool without the other slots' characters (the current
        /// slot's own character included); empty = no popup.
        func profilePickerChoices(current: TripleShotCharacterProfile) -> [TripleShotCharacterProfile] {
            let required = selectedTeamSize * 2
            let used = selectedIdsExcept(currentId: current.id)
            return teamSelectionPool(required: required)
                .filter { !used.contains($0.id) }
        }

        /// The checks and the result of the "Start game" listener (679-705); nil = the "choose ready" toast.
        func startSelection() -> Selection? {
            ensureSlots()
            let gameSelected = selectedMode == GameType.ONE_ON_ONE || selectedMode == GameType.TEAM_MATCH
            let wholeMatch = [selectedHuman] + selectedTeammates + selectedOpponents
            let expectedCount = selectedTeamSize * 2
            let duplicateCharacter =
                gameSelected && wholeMatch.map({ $0.id }).kDistinct().count != expectedCount
            let invalidSinglePlayerArt =
                selectedMode == GameType.ONE_ON_ONE &&
                    (!canSelectHuman(selectedHuman) || selectedOpponents.contains { !canSelectBot($0) })
            let invalidNonGameArt =
                !gameSelected &&
                    (!canSelectHuman(selectedHuman) || !canSelectBot(selectedPrimaryBot))

            if duplicateCharacter || invalidSinglePlayerArt || invalidNonGameArt {
                return nil
            }
            return Selection(
                gameType: selectedMode,
                teamSize: selectedTeamSize,
                human: selectedHuman,
                teammates: selectedMode == GameType.TEAM_MATCH ? selectedTeammates : [],
                opponents: selectedMode == GameType.TEAM_MATCH ? selectedOpponents : [selectedPrimaryBot],
                gameOrientation: physicalGameOrientation,
                courtId: selectedCourtId
            )
        }
    }

    static func show(
        fragment: AFragment,
        humanProfiles: [TripleShotCharacterProfile],
        botProfiles: [TripleShotCharacterProfile],
        currentHumanId: String,
        currentBotId: String,
        canSelectHuman: @escaping (TripleShotCharacterProfile) -> Bool,
        canSelectBot: @escaping (TripleShotCharacterProfile) -> Bool,
        onStart: @escaping (Selection) -> Void
    ) {
        if !fragment.isAdded || humanProfiles.isEmpty || botProfiles.isEmpty { return }

        let context = fragment.requireContext()
        let density = context.resources.displayMetrics.density
        func dp(v: Int) -> Int { return (v.toFloat() * density).toInt() }

        let dialog = ADialog(context)
        dialog.requestWindowFeature(AWindow.FEATURE_NO_TITLE)
        let dm = context.resources.displayMetrics
        let dialogWidth = FamilyReadingPanel.contentWidth(context: context, available: (dm.widthPixels.toFloat() * Float(0.94)).toInt())
        let dialogHeight = (dm.heightPixels.toFloat() * Float(0.91)).toInt()

        let rootCard = SkyMaterialCardView()
        rootCard.radius = dp(v: 26).toFloat()
        rootCard.cardElevation = dp(v: 10).toFloat()
        rootCard.setCardBackgroundColor(AColor.parseColor("#FFFDF8"))
        rootCard.strokeColor = AColor.parseColor("#E4DED0")
        rootCard.strokeWidth = dp(v: 1)
        rootCard.layoutParams = AViewGroup.LayoutParams(dialogWidth, dialogHeight)
        FamilySkyUi.watch(root: rootCard)
        TripleShotControls.watch(root: rootCard)
        let scroll = AScrollView()
        scroll.isFillViewport = true
        scroll.overScrollMode = AView.OVER_SCROLL_NEVER
        let shell = ALinearLayout()
        shell.orientation = ALinearLayout.VERTICAL
        rootCard.addView(shell, AViewGroup.LayoutParams(-1, -1))
        shell.addView(scroll, ALinearLayout.LayoutParams(-1, 0, 1))
        let content = ALinearLayout()
        content.orientation = ALinearLayout.VERTICAL
        content.setPadding(dp(v: 16), dp(v: 14), dp(v: 16), dp(v: 16))
        scroll.addView(content, AViewGroup.LayoutParams(AViewGroup.LayoutParams.MATCH_PARENT, AViewGroup.LayoutParams.WRAP_CONTENT))

        let titleText = ATextView()
        titleText.text = fragment.getString(R.string.minik_swish_bot_setup_title)
        titleText.textSize = 23
        titleText.setTypeface(titleText.typeface, ATypeface.BOLD)
        titleText.setTextColor(AColor.parseColor("#13242D"))
        titleText.gravity = AGravity.CENTER_HORIZONTAL
        content.addView(titleText)
        let subtitleText = ATextView()
        subtitleText.text = fragment.getString(R.string.minik_swish_bot_setup_subtitle)
        subtitleText.textSize = 16
        subtitleText.setTextColor(AColor.parseColor("#63717A"))
        subtitleText.gravity = AGravity.CENTER_HORIZONTAL
        subtitleText.setPadding(dp(v: 8), dp(v: 2), dp(v: 8), dp(v: 12))
        content.addView(subtitleText)

        // selectedMode, selectedTeamSize, physicalGameOrientation, selectedCourtId, selectedHuman, selectedPrimaryBot,
        // selectedTeammates, selectedOpponents (and allTeamProfiles).
        let state = SetupState(
            humanProfiles: humanProfiles,
            botProfiles: botProfiles,
            currentHumanId: currentHumanId,
            currentBotId: currentBotId,
            canSelectHuman: canSelectHuman,
            canSelectBot: canSelectBot,
            physicalGameOrientation:
                context.resources.configuration.orientation == AConfiguration.ORIENTATION_LANDSCAPE
                    ? TripleShotGameOrientation.LANDSCAPE
                    : TripleShotGameOrientation.PORTRAIT
        )
        let physicalOrientationListener = AOrientationEventListener(context) { orientation in
            state.onOrientationChanged(orientation: orientation)
        }
        if physicalOrientationListener.canDetectOrientation() { physicalOrientationListener.enable() }

        let modeRow = ALinearLayout()
        modeRow.orientation = ALinearLayout.HORIZONTAL
        modeRow.gravity = AGravity.CENTER
        let modeRowParams = ALinearLayout.LayoutParams(AViewGroup.LayoutParams.MATCH_PARENT, AViewGroup.LayoutParams.WRAP_CONTENT)
        modeRowParams.bottomMargin = dp(v: 10)
        content.addView(modeRow, modeRowParams)
        let shootingMode = modeCard(fragment: fragment, icon: "\u{1F3C0}", titleRes: R.string.minik_swish_bot_mode_shooting, subtitleRes: R.string.minik_swish_bot_mode_shooting_desc, accent: AColor.parseColor("#0B8B78"), selectedBackground: AColor.parseColor("#F1FBF8"))
        let horseMode = modeCard(fragment: fragment, icon: "\u{1F3AF}", titleRes: R.string.minik_swish_bot_mode_horse, subtitleRes: R.string.minik_swish_bot_mode_horse_desc, accent: AColor.parseColor("#D17A16"), selectedBackground: AColor.parseColor("#FFF7EB"))
        let gameMode = modeCard(fragment: fragment, icon: "\u{2694}\u{FE0F}", titleRes: R.string.minik_swish_bot_mode_game, subtitleRes: R.string.minik_swish_bot_mode_game_desc, accent: AColor.parseColor("#176AC0"), selectedBackground: AColor.parseColor("#E5F1FF"))
        let shootingParams = ALinearLayout.LayoutParams(0, AViewGroup.LayoutParams.WRAP_CONTENT, 1)
        shootingParams.marginEnd = dp(v: 4)
        modeRow.addView(shootingMode.card, shootingParams)
        let horseParams = ALinearLayout.LayoutParams(0, AViewGroup.LayoutParams.WRAP_CONTENT, 1)
        horseParams.marginStart = dp(v: 4)
        horseParams.marginEnd = dp(v: 4)
        modeRow.addView(horseMode.card, horseParams)
        let gameParams = ALinearLayout.LayoutParams(0, AViewGroup.LayoutParams.WRAP_CONTENT, 1)
        gameParams.marginStart = dp(v: 4)
        modeRow.addView(gameMode.card, gameParams)

        let teamOptions = SkyMaterialCardView()
        teamOptions.radius = dp(v: 18).toFloat()
        teamOptions.cardElevation = 0
        teamOptions.setCardBackgroundColor(AColor.parseColor("#F8F5FC"))
        teamOptions.strokeColor = AColor.parseColor("#33176AC0")
        teamOptions.strokeWidth = dp(v: 1)
        teamOptions.visibility = AView.GONE
        let teamOptionsBody = ALinearLayout()
        teamOptionsBody.orientation = ALinearLayout.VERTICAL
        teamOptionsBody.setPadding(dp(v: 10), dp(v: 9), dp(v: 10), dp(v: 9))
        teamOptions.addView(teamOptionsBody)
        let teamSizeTitle = ATextView()
        teamSizeTitle.text = fragment.getString(R.string.minik_swish_team_size_title)
        teamSizeTitle.textSize = 12
        teamSizeTitle.setTypeface(teamSizeTitle.typeface, ATypeface.BOLD)
        teamSizeTitle.setTextColor(AColor.parseColor("#4B3A64"))
        teamSizeTitle.gravity = AGravity.CENTER
        teamOptionsBody.addView(teamSizeTitle)
        let sizeRow = ALinearLayout()
        sizeRow.orientation = ALinearLayout.HORIZONTAL
        sizeRow.gravity = AGravity.CENTER
        sizeRow.setPadding(0, dp(v: 6), 0, 0)
        teamOptionsBody.addView(sizeRow)
        // `listOf(1 to "1 × 1", 2 to "2 × 2", 3 to "3 × 3").associate { ... }`: a LinkedHashMap in size order.
        var sizeButtons = KLinkedMap<Int, TripleShotButton>()
        for (size, label) in [(1, "1 \u{00D7} 1"), (2, "2 \u{00D7} 2"), (3, "3 \u{00D7} 3")] {
            let button = TripleShotButton()
            button.text = label
            button.isAllCaps = false
            button.cornerRadius = dp(v: 14)
            button.textSize = 16
            let sizeParams = ALinearLayout.LayoutParams(0, dp(v: 42), 1)
            sizeParams.marginStart = dp(v: 3)
            sizeParams.marginEnd = dp(v: 3)
            sizeRow.addView(button, sizeParams)
            sizeButtons[size] = button
        }
        let teamOptionsParams = ALinearLayout.LayoutParams(AViewGroup.LayoutParams.MATCH_PARENT, AViewGroup.LayoutParams.WRAP_CONTENT)
        teamOptionsParams.bottomMargin = dp(v: 10)
        content.addView(teamOptions, teamOptionsParams)

        // Basketball presentation choices live in the same Play-vs-Bot setup. They are hidden for
        // Shooting Challenge / HORSE so those mature portrait modes stay untouched.
        let presentationCard = SkyMaterialCardView()
        presentationCard.radius = dp(v: 18).toFloat()
        presentationCard.cardElevation = 0
        presentationCard.setCardBackgroundColor(AColor.parseColor("#F5FBFA"))
        presentationCard.strokeColor = AColor.parseColor("#330B8B78")
        presentationCard.strokeWidth = dp(v: 1)
        presentationCard.visibility = AView.GONE
        let presentationBody = ALinearLayout()
        presentationBody.orientation = ALinearLayout.VERTICAL
        presentationBody.setPadding(dp(v: 12), dp(v: 10), dp(v: 12), dp(v: 12))
        presentationCard.addView(presentationBody)
        let courtTitle = ATextView()
        courtTitle.text = fragment.getString(R.string.minik_swish_court_title)
        courtTitle.textSize = 16
        courtTitle.setTypeface(courtTitle.typeface, ATypeface.BOLD)
        courtTitle.setTextColor(AColor.parseColor("#23444B"))
        courtTitle.setPadding(0, dp(v: 2), 0, dp(v: 5))
        presentationBody.addView(courtTitle)
        let courtScroll = AHorizontalScrollView()
        courtScroll.isHorizontalScrollBarEnabled = false
        courtScroll.overScrollMode = AView.OVER_SCROLL_NEVER
        let courtRow = ALinearLayout()
        courtRow.orientation = ALinearLayout.HORIZONTAL
        courtRow.gravity = AGravity.CENTER_VERTICAL
        courtScroll.addView(courtRow, AViewGroup.LayoutParams(AViewGroup.LayoutParams.WRAP_CONTENT, AViewGroup.LayoutParams.WRAP_CONTENT))
        presentationBody.addView(courtScroll, ALinearLayout.LayoutParams(AViewGroup.LayoutParams.MATCH_PARENT, dp(v: 58)))
        var courtButtons = KLinkedMap<String, AButton>()
        for style in TripleShotCourtCatalog.all {
            let button = TripleShotButton()
            button.text = fragment.getString(style.titleRes)
            button.isAllCaps = false
            button.textSize = 16
            button.cornerRadius = dp(v: 14)
            button.minWidth = dp(v: 128)
            button.setOnClickListener { _ in
                state.selectedCourtId = style.id
                for (id, b) in courtButtons {
                    let selected = id == state.selectedCourtId
                    b.backgroundTintList = AColorStateList.valueOf(
                        AColor.parseColor(selected ? "#176AC0" : "#E8F1EF")
                    )
                    b.setTextColor(AColor.parseColor(selected ? "#FFFFFF" : "#29434A"))
                }
            }
            courtButtons[style.id] = button
            let courtParams = ALinearLayout.LayoutParams(AViewGroup.LayoutParams.WRAP_CONTENT, dp(v: 44))
            courtParams.marginStart = dp(v: 3)
            courtParams.marginEnd = dp(v: 3)
            courtRow.addView(button, courtParams)
        }
        let courtHint = ATextView()
        courtHint.text = fragment.getString(R.string.minik_swish_court_missing_art_hint)
        courtHint.textSize = 9.5
        courtHint.setTextColor(AColor.parseColor("#68777C"))
        courtHint.setPadding(0, dp(v: 4), 0, 0)
        presentationBody.addView(courtHint)
        let presentationParams = ALinearLayout.LayoutParams(AViewGroup.LayoutParams.MATCH_PARENT, AViewGroup.LayoutParams.WRAP_CONTENT)
        presentationParams.bottomMargin = dp(v: 10)
        content.addView(presentationCard, presentationParams)

        func refreshPresentation() {
            let isBasketball = state.selectedMode == GameType.ONE_ON_ONE || state.selectedMode == GameType.TEAM_MATCH
            let isTeamFullCourt = state.selectedMode == GameType.TEAM_MATCH
            presentationCard.visibility = isBasketball ? AView.VISIBLE : AView.GONE

            // Team mode exposes only genuine 1672x941 two-basket courts. Preserve the user's
            // selected compatible full-court instead of forcing Sunset every refresh.
            // (fullCourtIds / teamOnlyFullCourtIds: SetupState.)
            state.normalizeCourt()

            for (id, button) in courtButtons {
                button.visibility = SetupState.courtButtonVisibility(id: id, isTeamFullCourt: isTeamFullCourt)
                let selected = id == state.selectedCourtId
                button.backgroundTintList = AColorStateList.valueOf(
                    AColor.parseColor(selected ? "#176AC0" : "#E8F1EF")
                )
                button.setTextColor(AColor.parseColor(selected ? "#FFFFFF" : "#29434A"))
            }
        }
        let humanSection = CharacterSection(
            fragment: fragment,
            title: fragment.getString(R.string.minik_swish_bot_setup_you),
            profiles: humanProfiles,
            initial: state.selectedHuman,
            canSelect: canSelectHuman,
            accent: AColor.parseColor("#0B8B78"),
            onChanged: { state.selectedHuman = $0 }
        )
        content.addView(humanSection.root)

        let teamSlotsCard = SkyMaterialCardView()
        teamSlotsCard.radius = dp(v: 18).toFloat()
        teamSlotsCard.cardElevation = 0
        teamSlotsCard.setCardBackgroundColor(AColor.WHITE)
        teamSlotsCard.strokeColor = AColor.parseColor("#D6E7E2")
        teamSlotsCard.strokeWidth = dp(v: 1)
        teamSlotsCard.visibility = AView.GONE
        let teamSlotsBody = ALinearLayout()
        teamSlotsBody.orientation = ALinearLayout.VERTICAL
        teamSlotsBody.setPadding(dp(v: 12), dp(v: 10), dp(v: 12), dp(v: 10))
        teamSlotsCard.addView(teamSlotsBody)
        let teamSlotsParams = ALinearLayout.LayoutParams(
            AViewGroup.LayoutParams.MATCH_PARENT,
            AViewGroup.LayoutParams.WRAP_CONTENT
        )
        teamSlotsParams.topMargin = dp(v: 8)
        content.addView(teamSlotsCard, teamSlotsParams)

        let versus = ATextView()
        versus.text = fragment.getString(R.string.minik_swish_bot_setup_vs)
        versus.textSize = 14
        versus.setTypeface(versus.typeface, ATypeface.BOLD)
        versus.setTextColor(AColor.parseColor("#8D6C28"))
        versus.gravity = AGravity.CENTER
        versus.setPadding(0, dp(v: 7), 0, dp(v: 7))
        content.addView(versus)

        let botSection = CharacterSection(
            fragment: fragment,
            title: fragment.getString(R.string.minik_swish_bot_setup_opponent),
            profiles: botProfiles,
            initial: state.selectedPrimaryBot,
            canSelect: canSelectBot,
            accent: AColor.parseColor("#176AC0"),
            onChanged: { profile in
                state.selectedPrimaryBot = profile
                if state.selectedOpponents.isEmpty { state.selectedOpponents.append(profile) } else { state.selectedOpponents[0] = profile }
            }
        )
        content.addView(botSection.root)

        let opponentSlotsCard = SkyMaterialCardView()
        opponentSlotsCard.radius = dp(v: 18).toFloat()
        opponentSlotsCard.cardElevation = 0
        opponentSlotsCard.setCardBackgroundColor(AColor.WHITE)
        opponentSlotsCard.strokeColor = AColor.parseColor("#E1D8F1")
        opponentSlotsCard.strokeWidth = dp(v: 1)
        opponentSlotsCard.visibility = AView.GONE
        let opponentSlotsBody = ALinearLayout()
        opponentSlotsBody.orientation = ALinearLayout.VERTICAL
        opponentSlotsBody.setPadding(dp(v: 12), dp(v: 10), dp(v: 12), dp(v: 10))
        opponentSlotsCard.addView(opponentSlotsBody)
        let opponentSlotsParams = ALinearLayout.LayoutParams(
            AViewGroup.LayoutParams.MATCH_PARENT,
            AViewGroup.LayoutParams.WRAP_CONTENT
        )
        opponentSlotsParams.topMargin = dp(v: 8)
        content.addView(opponentSlotsCard, opponentSlotsParams)

        // allTeamProfiles, isAuthoredReady, teamSelectionPool, assignUniqueRoster, randomizeTeams, ensureSlots and
        // selectedIdsExcept (328-394): SetupState.

        let pickerScreenWidthDp = context.resources.configuration.screenWidthDp
        let playerSlotWidthDp: Int
        if pickerScreenWidthDp < 330 {
            playerSlotWidthDp = 76
        } else if pickerScreenWidthDp < 390 {
            playerSlotWidthDp = 84
        } else {
            playerSlotWidthDp = 96
        }
        let playerSlotHeightDp = playerSlotWidthDp <= 76 ? 116 : 124

        // Kotlin defaults `slotWidthDp = playerSlotWidthDp, slotHeightDp = playerSlotHeightDp`: the roster call passes
        // them. `slotHeightDp` is unused inside (as in Kotlin).
        func playerSlot(
            profile: TripleShotCharacterProfile,
            accent: Int,
            slotWidthDp: Int,
            slotHeightDp: Int,
            onClick: @escaping () -> Void
        ) -> ACardView {
            let card = SkyMaterialCardView()
            card.radius = dp(v: 15).toFloat()
            card.cardElevation = 0
            card.strokeColor = accent
            card.strokeWidth = dp(v: 2)
            card.setCardBackgroundColor(AColor.parseColor("#FFFDF9"))
            card.isClickable = true
            card.isFocusable = true
            card.setAlpha(state.isAuthoredReady(profile: profile) ? 1 : 0.82)
            card.setOnClickListener { _ in onClick() }
            let body = ALinearLayout()
            body.orientation = ALinearLayout.VERTICAL
            body.gravity = AGravity.CENTER
            body.setPadding(dp(v: 5), dp(v: 5), dp(v: 5), dp(v: 6))
            card.addView(body)
            let portrait = AImageView()
            portrait.scaleType = AImageView.ScaleType.CENTER_INSIDE
            portrait.adjustViewBounds = true
            if let res = TripleShotCharacterVisualCatalog.previewResId(characterId: profile.id) { portrait.setImageResource(res) }
            body.addView(
                portrait,
                ALinearLayout.LayoutParams(
                    dp(v: slotWidthDp - 10),
                    dp(v: slotWidthDp <= 72 ? 60 : slotWidthDp <= 82 ? 68 : 76)
                )
            )
            let name = ATextView()
            name.text = profile.displayName
            name.textSize = 10.5
            name.setTypeface(name.typeface, ATypeface.BOLD)
            name.setTextColor(AColor.parseColor("#233840"))
            name.gravity = AGravity.CENTER
            name.maxLines = 2
            name.textDirection = AView.TEXT_DIRECTION_LOCALE
            body.addView(
                name,
                ALinearLayout.LayoutParams(dp(v: slotWidthDp - 8), AViewGroup.LayoutParams.WRAP_CONTENT)
            )
            return card
        }

        func showProfilePicker(
            title: String,
            current: TripleShotCharacterProfile,
            onPick: @escaping (TripleShotCharacterProfile) -> Void
        ) {
            let selectable = state.profilePickerChoices(current: current)
            if selectable.isEmpty { return }

            // The popup is often opened on a narrow portrait phone and Hebrew makes a
            // HorizontalScrollView start from the RTL edge. In the previous picker that combination
            // left the first/last card visibly clipped. Keep the card strip LTR (names still use the
            // locale), add real edge padding, and use a slightly more compact card only inside this
            // popup. The selected team cards themselves keep their larger size.
            let pickerChoiceWidthDp: Int
            if pickerScreenWidthDp < 350 {
                pickerChoiceWidthDp = 68
            } else if pickerScreenWidthDp < 410 {
                pickerChoiceWidthDp = 74
            } else {
                pickerChoiceWidthDp = 82
            }
            let pickerChoiceHeightDp = pickerChoiceWidthDp <= 68 ? 106 : 114
            let pickerScroll = AHorizontalScrollView()
            pickerScroll.isHorizontalScrollBarEnabled = false
            pickerScroll.overScrollMode = AView.OVER_SCROLL_NEVER
            pickerScroll.clipToPadding = false
            pickerScroll.isFillViewport = false
            pickerScroll.layoutDirection = AView.LAYOUT_DIRECTION_LTR
            pickerScroll.setPadding(dp(v: 16), dp(v: 2), dp(v: 16), dp(v: 2))
            let pickerRow = ALinearLayout()
            pickerRow.orientation = ALinearLayout.HORIZONTAL
            pickerRow.gravity = AGravity.CENTER_VERTICAL
            pickerRow.layoutDirection = AView.LAYOUT_DIRECTION_LTR
            pickerRow.setPadding(dp(v: 2), dp(v: 6), dp(v: 2), dp(v: 6))
            pickerScroll.addView(
                pickerRow,
                AViewGroup.LayoutParams(AViewGroup.LayoutParams.WRAP_CONTENT, AViewGroup.LayoutParams.WRAP_CONTENT)
            )

            let picker =
                AMaterialAlertDialogBuilder(context)
                    .setTitle(title)
                    .setView(pickerScroll)
                    .setNegativeButton(res: android.R.string.cancel, nil)
                    .create()

            for profile in selectable {
                let choice = playerSlot(
                    profile: profile,
                    accent: AColor.parseColor("#7A5AB5"),
                    slotWidthDp: pickerChoiceWidthDp,
                    slotHeightDp: pickerChoiceHeightDp,
                    onClick: { [weak picker] in
                        onPick(profile)
                        picker?.dismiss()
                    }
                )
                let choiceParams = ALinearLayout.LayoutParams(dp(v: pickerChoiceWidthDp), dp(v: pickerChoiceHeightDp))
                choiceParams.marginStart = dp(v: 4)
                choiceParams.marginEnd = dp(v: 4)
                pickerRow.addView(choice, choiceParams)
            }
            picker.show()
            let pickerWindow: AWindow? = picker.window
            if let window = pickerWindow {
                let maxWidth = dp(v: 520)
                let desired = (context.resources.displayMetrics.widthPixels.toFloat() * Float(0.98)).toInt()
                window.setLayout(min(desired, maxWidth), AViewGroup.LayoutParams.WRAP_CONTENT)
            }
            // Explicitly start at a clean card boundary instead of the RTL end-position Android may
            // restore for a newly created HorizontalScrollView.
            pickerScroll.post { pickerScroll.scrollTo(0, 0) }
        }

        func addTeamRoster(
            body: ALinearLayout,
            title: String,
            accent: Int,
            profiles: [TripleShotCharacterProfile],
            onReplace: @escaping (Int, TripleShotCharacterProfile) -> Void
        ) {
            let rosterTitle = ATextView()
            rosterTitle.text = title
            rosterTitle.textSize = 14.5
            rosterTitle.setTypeface(rosterTitle.typeface, ATypeface.BOLD)
            rosterTitle.setTextColor(accent)
            rosterTitle.gravity = AGravity.CENTER_HORIZONTAL
            body.addView(rosterTitle)
            let rosterHint = ATextView()
            rosterHint.text = fragment.getString(R.string.minik_swish_team_tap_player_to_change)
            rosterHint.textSize = 10.5
            rosterHint.setTextColor(AColor.parseColor("#67777D"))
            rosterHint.gravity = AGravity.CENTER_HORIZONTAL
            rosterHint.setPadding(0, dp(v: 2), 0, dp(v: 7))
            body.addView(rosterHint)

            let rowScroll = AHorizontalScrollView()
            rowScroll.isHorizontalScrollBarEnabled = false
            rowScroll.overScrollMode = AView.OVER_SCROLL_NEVER
            let row = ALinearLayout()
            row.orientation = ALinearLayout.HORIZONTAL
            row.gravity = AGravity.CENTER
            rowScroll.addView(
                row,
                AViewGroup.LayoutParams(AViewGroup.LayoutParams.WRAP_CONTENT, AViewGroup.LayoutParams.WRAP_CONTENT)
            )
            body.addView(
                rowScroll,
                ALinearLayout.LayoutParams(AViewGroup.LayoutParams.MATCH_PARENT, dp(v: playerSlotHeightDp + 6))
            )

            for (index, profile) in profiles.enumerated() {
                let slot = playerSlot(
                    profile: profile,
                    accent: accent,
                    slotWidthDp: playerSlotWidthDp,
                    slotHeightDp: playerSlotHeightDp,
                    onClick: {
                        showProfilePicker(
                            title: fragment.getString(R.string.minik_swish_team_pick_player),
                            current: profile,
                            onPick: { replacement in
                                onReplace(index, replacement)
                            }
                        )
                    }
                )
                let slotParams = ALinearLayout.LayoutParams(dp(v: playerSlotWidthDp), dp(v: playerSlotHeightDp))
                slotParams.marginStart = dp(v: 4)
                slotParams.marginEnd = dp(v: 4)
                row.addView(slot, slotParams)
            }
        }

        func rebuildSlotCards() {
            state.ensureSlots()
            let gameSelected = state.selectedMode == GameType.ONE_ON_ONE || state.selectedMode == GameType.TEAM_MATCH

            humanSection.root.visibility = gameSelected ? AView.GONE : AView.VISIBLE
            botSection.root.visibility = gameSelected ? AView.GONE : AView.VISIBLE
            teamSlotsCard.visibility = gameSelected ? AView.VISIBLE : AView.GONE
            opponentSlotsCard.visibility = gameSelected ? AView.VISIBLE : AView.GONE

            if !gameSelected { return }

            teamSlotsBody.removeAllViews()
            opponentSlotsBody.removeAllViews()

            let humanRoster = [state.selectedHuman] + state.selectedTeammates
            addTeamRoster(
                body: teamSlotsBody,
                title: fragment.getString(R.string.minik_swish_team_you),
                accent: AColor.parseColor("#0B8B78"),
                profiles: humanRoster,
                onReplace: { index, replacement in
                    if index == 0 {
                        state.selectedHuman = replacement
                    } else {
                        state.selectedTeammates[index - 1] = replacement
                    }
                    rebuildSlotCards()
                }
            )

            addTeamRoster(
                body: opponentSlotsBody,
                title: fragment.getString(R.string.minik_swish_team_opponents),
                accent: AColor.parseColor("#176AC0"),
                profiles: state.selectedOpponents,
                onReplace: { index, replacement in
                    state.selectedOpponents[index] = replacement
                    state.selectedPrimaryBot = state.selectedOpponents.first!
                    rebuildSlotCards()
                }
            )
        }

        func refreshModes() {
            shootingMode.setSelected(selected: state.selectedMode == GameType.SHOOTING_CHALLENGE)
            horseMode.setSelected(selected: state.selectedMode == GameType.HORSE)
            gameMode.setSelected(selected: state.selectedMode == GameType.ONE_ON_ONE || state.selectedMode == GameType.TEAM_MATCH)
            teamOptions.visibility = gameMode.card.isSelected ? AView.VISIBLE : AView.GONE
            for (size, button) in sizeButtons {
                let selected = size == state.selectedTeamSize
                button.backgroundTintList = AColorStateList.valueOf(AColor.parseColor(selected ? "#176AC0" : "#E5F1FF"))
                button.setTextColor(AColor.parseColor(selected ? "#FFFFFF" : "#463A53"))
            }
            rebuildSlotCards()
            refreshPresentation()
        }

        shootingMode.card.setOnClickListener { _ in state.selectedMode = GameType.SHOOTING_CHALLENGE; refreshModes() }
        horseMode.card.setOnClickListener { _ in state.selectedMode = GameType.HORSE; refreshModes() }
        gameMode.card.setOnClickListener { _ in
            state.selectedMode = state.selectedTeamSize == 1 ? GameType.ONE_ON_ONE : GameType.TEAM_MATCH
            refreshModes()
        }
        for (size, button) in sizeButtons {
            button.setOnClickListener { _ in
                let changed = state.selectedTeamSize != size
                state.selectedTeamSize = size
                state.selectedMode = size == 1 ? GameType.ONE_ON_ONE : GameType.TEAM_MATCH
                if changed && size >= 2 { state.randomizeTeams() } else { state.ensureSlots() }
                refreshModes()
            }
        }
        refreshModes()

        let buttonRow = ALinearLayout()
        buttonRow.orientation = ALinearLayout.HORIZONTAL
        buttonRow.gravity = AGravity.CENTER_VERTICAL
        buttonRow.setPadding(0, dp(v: 14), 0, 0)
        buttonRow.setPadding(dp(v: 16), dp(v: 12), dp(v: 16), dp(v: 16))
        shell.addView(buttonRow, ALinearLayout.LayoutParams(-1, -2))
        let cancelButton = TripleShotButton()
        cancelButton.text = fragment.getString(android.R.string.cancel)
        cancelButton.isAllCaps = false
        cancelButton.cornerRadius = dp(v: 16)
        let startButton = TripleShotButton()
        startButton.text = fragment.getString(R.string.minik_swish_bot_setup_start)
        startButton.isAllCaps = false
        startButton.textSize = 16
        startButton.setTypeface(startButton.typeface, ATypeface.BOLD)
        startButton.cornerRadius = dp(v: 16)
        startButton.backgroundTintList = AColorStateList.valueOf(AColor.parseColor("#087E69"))
        startButton.setTextColor(AColor.WHITE)
        let cancelParams = ALinearLayout.LayoutParams(0, dp(v: 56), 0.38)
        cancelParams.marginEnd = dp(v: 7)
        buttonRow.addView(cancelButton, cancelParams)
        let startParams = ALinearLayout.LayoutParams(0, dp(v: 56), 0.62)
        startParams.marginStart = dp(v: 7)
        buttonRow.addView(startButton, startParams)

        cancelButton.setOnClickListener { [weak dialog] _ in dialog?.dismiss() }
        startButton.setOnClickListener { [weak dialog] _ in
            // ensureSlots, the duplicate / art checks and the Selection (679-705).
            guard let selection = state.startSelection() else {
                AToast.makeText(context, res: R.string.minik_swish_bot_setup_choose_ready, AToast.LENGTH_SHORT).show()
                return
            }
            onStart(selection)
            dialog?.dismiss()
        }

        // Kotlin `dialog.setContentView(rootCard)`: PhoneWindow.setContentView(view) adds the view with MATCH_PARENT x
        // MATCH_PARENT params (replacing the card's own dialogWidth x dialogHeight), so the card fills the window even
        // where the window is clamped to the screen minus the system bars. AndroidKit's AWindow.setContentView(view)
        // keeps the view's params, hence the explicit form here.
        dialog.setContentView(
            rootCard,
            AViewGroup.LayoutParams(AViewGroup.LayoutParams.MATCH_PARENT, AViewGroup.LayoutParams.MATCH_PARENT)
        )
        dialog.setCanceledOnTouchOutside(true)
        let lifecycle = fragment.viewLifecycleOwner.lifecycle
        let cleanup = DismissOnDestroy(dialog: dialog)
        lifecycle.addObserver(cleanup)
        dialog.setOnDismissListener { _ in
            physicalOrientationListener.disable()
            lifecycle.removeObserver(cleanup)
            // iOS memory (see the file header): break the listener cycles of the dismissed dialog's views.
            releaseClickListeners(view: rootCard)
        }
        // Establish the final size before the first visible frame (no show-then-resize jump).
        let dialogWindow: AWindow? = dialog.window
        if let window = dialogWindow {
            window.setBackgroundDrawable(AColorDrawable(AColor.TRANSPARENT))
            window.setDimAmount(0.58)
            let attributes = window.attributes
            attributes.width = dialogWidth
            attributes.height = dialogHeight
            attributes.windowAnimations = 0
            window.attributes = attributes
        }
        dialog.setOnShowListener { [weak dialog] _ in
            let shownWindow: AWindow? = dialog?.window
            if let window = shownWindow {
                window.setBackgroundDrawable(AColorDrawable(AColor.TRANSPARENT))
                window.setDimAmount(0.58)
                window.addFlags(AWindowManager.LayoutParams.FLAG_DIM_BEHIND)
                window.setLayout(dialogWidth, dialogHeight)
            }
        }
        dialog.show()
    }

    /// Kotlin `object : DefaultLifecycleObserver { override fun onDestroy(owner) { dialog.dismiss() } }` (713-715):
    /// the Home view going away closes the dialog. The dialog is held weakly (its activity holds it while shown).
    private final class DismissOnDestroy: ADefaultLifecycleObserver {
        private weak var dialog: ADialog?

        init(dialog: ADialog) {
            self.dialog = dialog
        }

        func onDestroy(_ owner: ALifecycleOwner) {
            dialog?.dismiss()
        }
    }

    /// iOS memory only: drops the click listeners of a dismissed dialog's view tree (see the file header).
    private static func releaseClickListeners(view: AView) {
        view.setOnClickListener(nil)
        if let group = view as? AViewGroup {
            for child in group.children {
                releaseClickListeners(view: child)
            }
        }
    }

    private struct ModeCard {
        var card: ACardView
        var title: ATextView
        var subtitle: ATextView
        var accent: Int
        var selectedBackground: Int

        func setSelected(selected: Bool) {
            card.isSelected = selected
            card.strokeWidth = ((selected ? 3 : 1).toFloat() * card.resources.displayMetrics.density).toInt()
            card.strokeColor = selected ? accent : AColor.parseColor("#DED9CD")
            card.setCardBackgroundColor(selected ? selectedBackground : AColor.WHITE)
            title.setTextColor(selected ? accent : AColor.parseColor("#263840"))
            subtitle.setTextColor(AColor.parseColor("#63717A"))
        }
    }

    private static func modeCard(
        fragment: AFragment,
        icon: String,
        titleRes: AStringRes,
        subtitleRes: AStringRes,
        accent: Int,
        selectedBackground: Int
    ) -> ModeCard {
        let context = fragment.requireContext()
        let density = context.resources.displayMetrics.density
        func dp(v: Int) -> Int { return (v.toFloat() * density).toInt() }
        let card = SkyMaterialCardView()
        card.minimumHeight = dp(v: 132)
        card.radius = dp(v: 18).toFloat()
        card.cardElevation = 0
        card.isClickable = true
        card.isFocusable = true
        let body = ALinearLayout()
        body.orientation = ALinearLayout.VERTICAL
        body.gravity = AGravity.CENTER
        body.setPadding(dp(v: 6), dp(v: 7), dp(v: 6), dp(v: 7))
        card.addView(body)
        let iconText = ATextView()
        iconText.text = icon
        iconText.textSize = 22
        iconText.gravity = AGravity.CENTER
        body.addView(iconText)
        let title = ATextView()
        title.text = fragment.getString(titleRes)
        title.textSize = 16
        title.gravity = AGravity.CENTER
        title.setTypeface(title.typeface, ATypeface.BOLD)
        let subtitle = ATextView()
        subtitle.text = fragment.getString(subtitleRes)
        subtitle.textSize = 9.7
        subtitle.gravity = AGravity.CENTER
        body.addView(title)
        body.addView(subtitle)
        return ModeCard(card: card, title: title, subtitle: subtitle, accent: accent, selectedBackground: selectedBackground)
    }

    private final class CharacterSection {
        private let canSelect: (TripleShotCharacterProfile) -> Bool
        private let onChanged: (TripleShotCharacterProfile) -> Void
        private let context: AContext
        private let density: Float
        private func dp(v: Int) -> Int { return (v.toFloat() * density).toInt() }
        let root: SkyMaterialCardView
        private var selected: TripleShotCharacterProfile
        private let heroImage = AImageView()
        private let nameText = ATextView()
        private let archetypeText = ATextView()
        private let availabilityText = ATextView()
        private let statsOne = ATextView()
        private let statsTwo = ATextView()
        private let statsThree = ATextView()
        private let statsFour = ATextView()
        private var rosterCards = KLinkedMap<String, ACardView>()

        init(
            fragment: AFragment,
            title: String,
            profiles: [TripleShotCharacterProfile],
            initial: TripleShotCharacterProfile,
            canSelect: @escaping (TripleShotCharacterProfile) -> Bool,
            accent: Int,
            onChanged: @escaping (TripleShotCharacterProfile) -> Void
        ) {
            self.canSelect = canSelect
            self.onChanged = onChanged
            context = fragment.requireContext()
            density = context.resources.displayMetrics.density
            root = SkyMaterialCardView()
            selected = initial
            root.radius = dp(v: 20).toFloat()
            root.cardElevation = 0
            root.strokeColor = AColor.parseColor("#E0DBD0")
            root.strokeWidth = dp(v: 1)
            root.setCardBackgroundColor(AColor.WHITE)

            let body = ALinearLayout()
            body.orientation = ALinearLayout.VERTICAL
            body.setPadding(dp(v: 12), dp(v: 10), dp(v: 12), dp(v: 10))
            root.addView(body)
            let sectionTitle = ATextView()
            sectionTitle.text = title
            sectionTitle.textSize = 16
            sectionTitle.setTypeface(sectionTitle.typeface, ATypeface.BOLD)
            sectionTitle.setTextColor(accent)
            sectionTitle.setPadding(0, 0, 0, dp(v: 7))
            body.addView(sectionTitle)
            let heroRow = ALinearLayout()
            heroRow.orientation = ALinearLayout.HORIZONTAL
            heroRow.gravity = AGravity.CENTER_VERTICAL
            body.addView(heroRow)
            heroImage.scaleType = AImageView.ScaleType.CENTER_INSIDE
            heroImage.adjustViewBounds = true
            let heroImageParams = ALinearLayout.LayoutParams(dp(v: 96), dp(v: 116))
            heroImageParams.marginEnd = dp(v: 10)
            heroRow.addView(heroImage, heroImageParams)
            let textColumn = ALinearLayout()
            textColumn.orientation = ALinearLayout.VERTICAL
            textColumn.gravity = AGravity.CENTER_VERTICAL
            heroRow.addView(textColumn, ALinearLayout.LayoutParams(0, AViewGroup.LayoutParams.WRAP_CONTENT, 1))
            nameText.textSize = 19
            nameText.setTypeface(nameText.typeface, ATypeface.BOLD)
            nameText.setTextColor(AColor.parseColor("#162932"))
            archetypeText.textSize = 12
            archetypeText.setTextColor(AColor.parseColor("#56666F"))
            archetypeText.setPadding(0, dp(v: 2), 0, dp(v: 4))
            availabilityText.textSize = 11
            availabilityText.setTypeface(availabilityText.typeface, ATypeface.BOLD)
            for tv in [statsOne, statsTwo, statsThree, statsFour] {
                tv.textSize = 11
                tv.setTextColor(AColor.parseColor("#34464F"))
                tv.setPadding(0, dp(v: 1), 0, 0)
            }
            nameText.textAlignment = AView.TEXT_ALIGNMENT_VIEW_START
            textColumn.addView(nameText)
            textColumn.addView(archetypeText)
            textColumn.addView(availabilityText)
            textColumn.addView(statsOne)
            textColumn.addView(statsTwo)
            textColumn.addView(statsThree)
            textColumn.addView(statsFour)

            let rosterScroll = AHorizontalScrollView()
            rosterScroll.isHorizontalScrollBarEnabled = false
            rosterScroll.overScrollMode = AView.OVER_SCROLL_NEVER
            let rosterRow = ALinearLayout()
            rosterRow.orientation = ALinearLayout.HORIZONTAL
            rosterRow.setPadding(0, dp(v: 8), 0, 0)
            rosterScroll.addView(rosterRow)
            body.addView(rosterScroll, ALinearLayout.LayoutParams(AViewGroup.LayoutParams.MATCH_PARENT, dp(v: 100)))
            for profile in profiles {
                let enabled = canSelect(profile)
                let card = SkyMaterialCardView()
                card.radius = dp(v: 13).toFloat()
                card.cardElevation = 0
                card.strokeWidth = dp(v: 1)
                card.strokeColor = AColor.parseColor("#DEDAD1")
                card.setCardBackgroundColor(AColor.parseColor(enabled ? "#FFFFFF" : "#F0EEE9"))
                card.setAlpha(enabled ? 1 : 0.62)
                card.isClickable = true
                rosterCards[profile.id] = card
                let item = ALinearLayout()
                item.orientation = ALinearLayout.VERTICAL
                item.gravity = AGravity.CENTER
                item.setPadding(dp(v: 4), dp(v: 3), dp(v: 4), dp(v: 3))
                card.addView(item)
                let portrait = AImageView()
                portrait.scaleType = AImageView.ScaleType.CENTER_INSIDE
                if let res = TripleShotCharacterVisualCatalog.previewResId(characterId: profile.id) { portrait.setImageResource(res) }
                item.addView(portrait, ALinearLayout.LayoutParams(dp(v: 64), dp(v: 68)))
                let name = ATextView()
                name.text = profile.displayName
                name.textSize = 10
                name.gravity = AGravity.CENTER
                name.maxLines = 1
                name.setTypeface(name.typeface, ATypeface.BOLD)
                name.setTextColor(AColor.parseColor("#24353D"))
                item.addView(name)
                let cardParams = ALinearLayout.LayoutParams(dp(v: 78), dp(v: 92))
                cardParams.marginEnd = dp(v: 6)
                rosterRow.addView(card, cardParams)
                card.setOnClickListener { [weak self] _ in
                    guard let self = self else { return }
                    self.selected = profile
                    self.onChanged(profile)
                    self.refresh(fragment: fragment, accent: accent)
                }
            }
            refresh(fragment: fragment, accent: accent)
        }

        private func refresh(fragment: AFragment, accent: Int) {
            if let res = TripleShotCharacterVisualCatalog.previewResId(characterId: selected.id) { heroImage.setImageResource(res) }
            nameText.text = selected.displayName
            archetypeText.text = TripleShotBotMatchSetupDialog.archetypeLabel(fragment: fragment, archetype: selected.archetype)
            let selectable = canSelect(selected)
            availabilityText.text = fragment.getString(selectable ? R.string.minik_swish_character_ready : R.string.minik_swish_character_art_pending)
            availabilityText.setTextColor(AColor.parseColor(selectable ? "#0B7B68" : "#9B5C12"))
            let r = selected.ratings
            statsOne.text = fragment.getString(R.string.minik_swish_character_stats_compact_shooting, r.inside, r.midRange, r.threePoint)
            statsTwo.text = fragment.getString(R.string.minik_swish_character_stats_v207_physical, r.speed, r.strength, r.height, r.weight, r.jumping)
            statsThree.text = fragment.getString(R.string.minik_swish_character_stats_v207_creation, r.ballHandling, r.offense, r.agility)
            statsFour.text = fragment.getString(R.string.minik_swish_character_stats_v207_defense, r.defense, r.stealing, r.blocking)
            for (id, card) in rosterCards {
                let chosen = id == selected.id
                card.strokeColor = chosen ? accent : AColor.parseColor("#DEDAD1")
                card.strokeWidth = ((chosen ? 3 : 1).toFloat() * density).toInt()
            }
        }
    }

    private static func archetypeLabel(fragment: AFragment, archetype: BotArchetype) -> String {
        let res: AStringRes
        switch archetype {
        case .ADAPTIVE_TRAINER: res = R.string.minik_swish_archetype_adaptive
        case .BALANCED: res = R.string.minik_swish_archetype_balanced
        case .SHARPSHOOTER: res = R.string.minik_swish_archetype_sharpshooter
        case .SLASHER: res = R.string.minik_swish_archetype_slasher
        case .DEFENDER: res = R.string.minik_swish_archetype_defender
        case .BIG: res = R.string.minik_swish_archetype_big
        }
        return fragment.getString(res)
    }
}
