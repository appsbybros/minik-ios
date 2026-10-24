import UIKit

/// Port of `ui/TripleShotHomeFragment.kt` (Android 6c38131), statement by statement (spec 18 §3.3, §4.3-§4.11,
/// spec 22 §4.5 for the menu sections).
///
/// The main menu: private player name, topic selection, launches of every mode (free practice, play vs bot, Live rooms,
/// league), the joiner's Live waiting lobby, information/privacy, entries to the daily journey and its settings page,
/// and the decorative scenery (Maya, the guest Unicorn 32 and a one-shot bouncing basketball). Like Android it inflates
/// the older `fragment_triple_shot_home.xml` (built in code by `TripleShotHomeLayout`, same ids, attributes and params)
/// and re-organizes it at runtime into the four `FamilyMenu.section` panels (Start & learn, Play, Results & standings,
/// Advanced), removing the old card; `FamilyMenu.section` posts the `FamilyMoreFrame` wrap of the scroll view. The
/// window-wide restylers installed by `TripleShotDemoActivity` (`FamilySkyUi.watch`, `TripleShotControls.watch`) and
/// `FamilyFormStyle.watch` then re-skin the same view tree as on the device.
///
/// Swift API: the Kotlin parameter names are the labels (DESIGN 2.1); Kotlin `private` members stay `private` (one
/// file). Closures kept by this fragment's own views, its Firebase listeners, the lobby back callback and the ball's
/// frame runnable hold the fragment (and views) weakly: Android's GC collects those cycles, ARC would not. Each of them
/// re-checks `isAdded` (or the view identity) exactly like the Kotlin code, so the behaviour while the fragment exists
/// is unchanged. One-shot callbacks (dialog buttons, the nickname chooser, `joinRoom`) keep the Kotlin strong capture.
///
/// Additions for the parity tests (no behaviour change): the arithmetic of the ball loop is `TripleShotHomeBallMotion`
/// (the Kotlin locals and frame body, same statements and order), the arithmetic of `placeCharacters()` is
/// `mayaFrame` / `guestFrame`, and the topic button text is `topicButtonText(selectedCategories:language:)`.
///
/// iOS-only additions. (1) DESIGN 2.8 / 12.3, spec 18 §4.2.6 / §10.1: a guest waiting in a joined Live lobby leaves it on
/// Android only with the system Back key (`waitingRoomBackCallback`), which iOS does not have. The room panel therefore
/// gets one extra control, `IOS_LEAVE_ROOM_BUTTON_ID` ("Leave room" / "יציאה מהחדר", 48 dp, below the players line),
/// which runs that callback exactly as Back would while it is enabled. (2) Spec 18 §4.4.3 / §10.4 and §4.4.9: the header
/// and the scroll column (with its "More below" row) keep out of the taller iOS status bar and the home indicator
/// (`TripleShotHomeLayout.applySafeArea`); the scenery and the decorations still cover the whole screen, as on Android.
///
/// Skipped: the debug-only paths (none in this file besides the shell's), Cloud practice's activity (unreachable: its
/// button stays in the removed card and `TripleShotDelivery.enabled` is false in release builds; spec 18 §4.5 / §8.11),
/// and the unused private functions `moveDisclaimerBelowInfoLink`, `directChildUnderRoot`, `chooseBotCharacter` and
/// `chooseLocalMatchCharacters` (no caller, spec 18 §8.11).
final class TripleShotHomeFragment: AFragment {

    private lazy var firebase: TripleShotFirebaseRepository = TripleShotFirebaseRepository()

    private var roomMetaHandle:
        TripleShotFirebaseRepository.ListenerHandle? = nil

    private var roomPlayersHandle:
        TripleShotFirebaseRepository.ListenerHandle? = nil

    private var currentRoomCode: String? = nil
    /// Write-only on Android (spec 18 §8.11); kept as it is.
    private var currentSeed: Int64 = 0
    private var isHost = false
    private var launchedRoomGame = false
    private var waitingRoomBackCallback: AOnBackPressedCallback? = nil

    private var nameInput: AEditText!
    private var topicButton: AButton!
    private var roomPanel: ACardView!
    private var roomStatusText: ATextView!
    private var roomPlayersText: ATextView!
    private var startRoomButton: AButton!
    private var createRoomButton: AButton!
    private var joinRoomButton: AButton!
    private var roomCodeInput: AEditText!

    // Home-only decorative views. They are injected programmatically so the existing
    // home XML and all of its current controls stay untouched.
    private var homeBallView: AImageView? = nil
    private var homeMayaView: AImageView? = nil
    private var homeGuestCharacterView: AImageView? = nil
    private var homeBallFrame: ARunnable? = nil

    private var prefs: ASharedPreferences!

    /// Kotlin `MutableSet<QuestionCategory>` (`mutableSetOf()` / `toMutableSet()`: a LinkedHashSet).
    private var selectedCategories:
        KLinkedSet<QuestionCategory> = KLinkedSet()

    /// View id of the iOS-only "Leave room" control of the room panel (no Android counterpart; see the type comment).
    static let IOS_LEAVE_ROOM_BUTTON_ID = "tripleShotHomeIosLeaveRoomButton"

    /// Registers the Swift builder of `R.layout.fragment_triple_shot_home` once (ALayoutInflater).
    private static let layoutRegistration: Void = {
        ALayoutInflater.register(R.layout.fragment_triple_shot_home) { _ in
            TripleShotHomeLayout.build()
        }
    }()

    /// Kotlin `TripleShotHomeFragment : Fragment(R.layout.fragment_triple_shot_home)`.
    override init() {
        super.init(contentLayoutId: R.layout.fragment_triple_shot_home)
        _ = TripleShotHomeFragment.layoutRegistration
    }

    override func onViewCreated(
        _ view: AView,
        _ savedInstanceState: ABundle?
    ) {
        super.onViewCreated(view, savedInstanceState)

        // Once the menu has been drawn, the launch trumpet (BasketballSoundscape.mainMenuVisible) is offered when the
        // fragment is resumed, shown and focused; otherwise retried every 80 ms, at most 30 attempts. The listener and
        // the runnable drop their self-references when done (Kotlin's GC collects them).
        let preDraw = KRef<AOnPreDrawListener?>(nil)
        preDraw.value = AOnPreDrawListener { [weak self, weak view] in
            guard let view = view else { return true }
            if let listener = preDraw.value { view.viewTreeObserver.removeOnPreDrawListener(listener) }
            preDraw.value = nil
            var attempts = 0
            let retry = KRef<ARunnable?>(nil)
            retry.value = ARunnable { [weak self, weak view] in
                guard let self = self, let view = view, self.isAdded, self.view === view else { retry.value = nil; return }
                if self.isResumed && view.isShown && view.hasWindowFocus() {
                    BasketballSoundscape.mainMenuVisible(activity: self.requireActivity()); retry.value = nil
                } else {
                    attempts += 1
                    if attempts < 30, let again = retry.value { view.postDelayed(again, 80) } else { retry.value = nil }
                }
            }
            view.post(retry.value!)
            return true
        }
        view.viewTreeObserver.addOnPreDrawListener(preDraw.value!)
        configureNavigationBar()

        nameInput = homeRequireView(view, R.id.playerNameInput, AEditText.self)
        topicButton = homeRequireView(view, R.id.topicButton, AButton.self)
        roomPanel = homeRequireView(view, R.id.roomPanel, ACardView.self)
        roomStatusText = homeRequireView(view, R.id.roomStatusText, ATextView.self)
        roomPlayersText = homeRequireView(view, R.id.roomPlayersText, ATextView.self)
        startRoomButton = homeRequireView(view, R.id.startRoomButton, AButton.self)

        // Kotlin `object : OnBackPressedCallback(false) { override fun handleOnBackPressed() { leaveCurrentWaitingRoom() } }`.
        let callback = AOnBackPressedCallback(false) { [weak self] _ in
            self?.leaveCurrentWaitingRoom()
        }
        requireActivity().onBackPressedDispatcher
            .addCallback(viewLifecycleOwner, callback)
        waitingRoomBackCallback = callback

        prefs =
            requireContext().getSharedPreferences(
                TripleShotHomeFragment.PREFS_NAME,
                MODE_PRIVATE
            )

        homeSetText(
            nameInput,
            prefs.getString(TripleShotHomeFragment.KEY_PLAYER_NAME, "")
        )

        selectedCategories =
            loadSelectedCategories()

        updateTopicButton()

        topicButton.setOnClickListener { [weak self] _ in
            self?.showTopicPicker()
        }

        homeRequireView(view, R.id.statsButton, AButton.self).setOnClickListener { [weak self] _ in
            guard let self else { return }
            self.prefs.edit().putString(TripleShotHomeFragment.KEY_PLAYER_NAME, self.nameInput.text.ktrim()).apply()
            (self.parentFragment as? TripleShotHostFragment)?.showProgress()
        }

        homeRequireView(
            view, R.id.practiceButton, AButton.self
        ).setOnClickListener { [weak self] _ in
            self?.launchSolo(
                gameType: GameType.PRACTICE,
                limitMode: GameLimitMode.BALLS_ONLY,
                timeLimitSeconds: 0
            )
        }

        // `visibility = if (TripleShotDelivery.enabled) VISIBLE else GONE` + a listener that opens CloudPracticeActivity.
        // The QE cloud practice is not ported (DESIGN 3) and the button is never shown: it stays in the old card, which
        // is removed below, and `enabled` is false in release builds. The listener is therefore omitted.
        homeRequireView(view, R.id.cloudPracticeButton, AButton.self).visibility =
            TripleShotDelivery.enabled ? AView.VISIBLE : AView.GONE

        homeRequireView(
            view, R.id.botButton, AButton.self
        ).setOnClickListener { [weak self] _ in
            self?.showBotMatchSetup()
        }

        createRoomButton =
            homeRequireView(
                view, R.id.createRoomButton, AButton.self
            )

        roomCodeInput =
            homeRequireView(view, R.id.roomCodeInput, AEditText.self)

        joinRoomButton =
            homeRequireView(
                view, R.id.joinRoomButton, AButton.self
            )

        createRoomButton.setOnClickListener { [weak self] _ in
            guard let self else { return }
            if self.currentRoomCode != nil && self.isHost {
                self.confirmCloseWaitingRoom()
            } else if self.currentRoomCode == nil {
                self.openLiveSetup()
            }
        }

        joinRoomButton.setOnClickListener { [weak self] _ in
            guard let self else { return }
            if self.currentRoomCode == nil {
                self.joinRoom(
                    button: self.joinRoomButton,
                    codeInput: self.roomCodeInput
                )
            }
        }

        updateRoomControls()

        startRoomButton.setOnClickListener { [weak self] button in
            guard let self else { return }
            guard let code =
                self.currentRoomCode
            else { return }

            button.isEnabled = false

            self.firebase.startRoom(codeRaw: code) { result in
                if !self.isAdded { return }

                button.isEnabled = true

                if case .failure(let error) = result {
                    self.showError(throwable: error)
                }
            }
        }

        homeRequireView(
            view, R.id.leaderboardButton, AButton.self
        ).setOnClickListener { [weak self] _ in
            (self?.parentFragment as? TripleShotHostFragment)?
                .showLeaderboard()
        }

        homeRequireView(
            view, R.id.infoPrivacyButton, AView.self
        ).setOnClickListener { [weak self] _ in
            self?.showInformationAndPrivacy()
        }

        // iOS-only (see the type comment): the on-screen stand-in for system Back in the joined lobby. Android's Back
        // runs the newest enabled callback; on Home that is `waitingRoomBackCallback` while a lobby is waiting.
        homeRequireView(view, TripleShotHomeFragment.IOS_LEAVE_ROOM_BUTTON_ID, AButton.self)
            .setOnClickListener { [weak self] _ in
                guard let self, let callback = self.waitingRoomBackCallback, callback.isEnabled else { return }
                callback.handleOnBackPressed()
            }

        let daily = TripleShotButton()
        daily.text = getString(R.string.daily_court_journey)
        daily.backgroundTintList = AColorStateList.valueOf(argbInt(0xffffe082))
        daily.setTextColor(argbInt(0xff282d4e))
        daily.isAllCaps = false
        daily.minHeight = (Float(56) * daily.resources.displayMetrics.density).toInt()
        daily.setOnClickListener { [weak self] _ in
            guard let self else { return }
            try! self.startActivity(AIntent(self.requireContext(), BasketballJourneyActivity.self))
        }
        homeRequireView(view, R.id.practiceButton, AView.self).parentGroup!.addView(daily, 0)
        let settings = TripleShotButton()
        settings.text = getString(R.string.daily_settings)
        settings.isAllCaps = false
        settings.minHeight = (Float(52) * settings.resources.displayMetrics.density).toInt()
        settings.setOnClickListener { [weak self] _ in
            guard let self else { return }
            try! self.startActivity(AIntent(self.requireContext(), BasketballJourneyActivity.self).putExtra("page", "settings"))
        }
        homeRequireView(view, R.id.homeContent, AViewGroup.self).addView(settings)
        let league = TripleShotButton()
        league.text = ["he", "iw"].contains(league.resources.configuration.locales[0].language) ? "ליגת כוכבי המגרש" : "Court Stars League"
        league.isAllCaps = false
        league.minHeight = (Float(56) * league.resources.displayMetrics.density).toInt()
        league.setOnClickListener { [weak self] _ in
            (self?.parentFragment as? TripleShotHostFragment)?.showLeague()
        }
        homeRequireView(view, R.id.practiceButton, AView.self).parentGroup!.addView(league, 1)
        installHomePolish(rootView: view)
        let home = homeRequireView(view, R.id.homeContent, ALinearLayout.self)
        home.setTag("family-menu-light")
        let he = ["he", "iw"].contains(resources.configuration.locales[0].language)
        func section(en: String, heb: String, expanded: Bool, color: Int) -> ALinearLayout {
            // Each freshly opened menu starts with secondary groups folded; no stale stored expansion.
            if !expanded { requireContext().getSharedPreferences("family_menu_sections", 0).edit().remove(he ? heb : en).apply() }
            let body = FamilyMenu.section(parent: home, title: he ? heb : en, expanded: expanded, color: color)
            (body.parentGroup!.background as? FamilySkyDrawable)?
                .setFaceGradient([argbInt(0xffd4e7f1), argbInt(0xffe5e8e5), argbInt(0xffdce5ef)])
            return body
        }
        let oldActionCard = homeRequireView(view, R.id.practiceButton, AView.self).parentGroup!.parentGroup!
        func tintActions(v: AView, color: Int) {
            if let b = v as? AButton {
                FamilyMenu.style(v: b, color: color)
                ATextViewCompat.setAutoSizeTextTypeWithDefaults(b, 0)
                b.textSize = 18; b.minHeight = dp(value: 56); b.isAllCaps = false
                b.gravity = AGravity.CENTER
            }
            else if let g = v as? AViewGroup { for i in kuntil(0, g.childCount) { tintActions(v: g.getChildAt(i)!, color: color) } }
        }
        func move(v: AView, to: ALinearLayout, color: Int) {
            v.parentGroup?.removeView(v)
            let lp = ALinearLayout.LayoutParams(-1, -2); lp.bottomMargin = (Float(10) * resources.displayMetrics.density).toInt()
            to.addView(v, lp)
            tintActions(v: v, color: color)
        }
        let learn = section(en: "Start & learn", heb: "מתחילים ולומדים", expanded: true, color: FamilyMenu.LEARN)
        move(v: homeRequireView(view, R.id.practiceButton, AView.self), to: learn, color: FamilyMenu.LEARN)
        move(v: daily, to: learn, color: FamilyMenu.LEARN)
        let nameCaption = ATextView()
        nameCaption.text = he ? "שם:" : "Name:"; nameCaption.textSize = 17; nameCaption.setTextColor(argbInt(0xff24364d))
        nameCaption.setTypeface(nameCaption.typeface, ATypeface.BOLD)
        nameCaption.gravity = AGravity.START; nameCaption.setPadding(dp(value: 8), dp(value: 6), dp(value: 8), dp(value: 8))
        nameCaption.labelFor = R.id.playerNameInput
        learn.addView(nameCaption)
        move(v: homeRequireView(view, R.id.playerNameInput, AView.self).parentGroup!.parentGroup!, to: learn, color: FamilyMenu.LEARN)
        move(v: homeRequireView(view, R.id.statsButton, AView.self), to: learn, color: FamilyMenu.LEARN)
        move(v: homeRequireView(view, R.id.topicButton, AView.self), to: learn, color: FamilyMenu.LEARN)
        let onlineAlias = TripleShotButton()
        onlineAlias.text = he ? "כינוי למשחק ברשת" : "Online nickname"; onlineAlias.isAllCaps = false; onlineAlias.textSize = 18
        onlineAlias.setOnClickListener { [weak self] _ in
            guard let self else { return }
            TripleShotOnlineIdentity.choose(c: self.requireContext(), always: true) { _ in }
        }
        move(v: onlineAlias, to: learn, color: FamilyMenu.LEARN)
        let play = section(en: "Play", heb: "משחקים", expanded: true, color: FamilyMenu.PLAY)
        for id in [R.id.botButton, R.id.createRoomButton] { move(v: homeRequireView(view, id, AView.self), to: play, color: FamilyMenu.PLAY) }
        move(v: league, to: play, color: FamilyMenu.PLAY)
        move(v: homeRequireView(view, R.id.joinRoomButton, AView.self).parentGroup!, to: play, color: FamilyMenu.PLAY)
        let saved = section(en: "Results & standings", heb: "תוצאות ודירוגים", expanded: false, color: argbInt(0xffe91e63))
        move(v: homeRequireView(view, R.id.leaderboardButton, AView.self), to: saved, color: argbInt(0xffff5b67))
        let leaderboardButton = homeRequireView(view, R.id.leaderboardButton, TripleShotButton.self)
        leaderboardButton.inkOverride = AColor.BLACK; leaderboardButton.labelOffsetDp = Float(-0.5)
        homeRequireView(view, R.id.statsButton, AButton.self).text = he ? "ההתקדמות שלי" : "My progress"
        let advanced = section(en: "Advanced", heb: "מתקדם", expanded: false, color: FamilyMenu.ADVANCED)
        move(v: settings, to: advanced, color: FamilyMenu.ADVANCED)
        let info = homeRequireView(view, R.id.infoPrivacyButton, ATextView.self)
        move(v: info, to: advanced, color: FamilyMenu.ADVANCED); FamilyMenu.link(t: info)
        oldActionCard.parentGroup?.removeView(oldActionCard)
    }

    /**
     * Adds a subtle character layer, a one-shot physics-ish bouncing ball and stronger footer
     * contrast without changing the existing home layout hierarchy or intercepting touches.
     */
    private func installHomePolish(rootView: AView) {
        guard let root = rootView as? AViewGroup else { return }

        applyHomeCardTransparency(root: root)
        strengthenHomeFooter(root: root)
        if let notice = root.findViewById(R.id.aiDisclaimerText) as ATextView? {
            notice.parentGroup?.removeView(notice)
            homeRequireView(root, R.id.homeContent, ALinearLayout.self).addView(notice, 0)
            notice.gravity = AGravity.START | AGravity.CENTER_VERTICAL
            notice.textAlignment = AView.TEXT_ALIGNMENT_VIEW_START; notice.textSize = 16
            notice.setPadding(0, dp(value: 6), 0, dp(value: 16))
        }
        installHomeCharacter(root: root)

        // Wait until the root has real dimensions before placing / animating the ball.
        root.post { [weak self, weak root] in
            guard let self, let root else { return }
            if !self.isAdded || self.view !== root { return }
            self.installAndStartHomeBall(root: root)
        }
    }

    /**
     * Two decorative players sit in front of the main home card. Maya stays on the lower-right,
     * while the smaller guest character sits on the lower-left where the bouncing ball can
     * naturally overlap him. Both are presentation-only and never intercept touches.
     */
    private func installHomeCharacter(root: AViewGroup) {
        if let old = homeMayaView {
            old.parentGroup?.removeView(old)
        }
        if let old = homeGuestCharacterView {
            old.parentGroup?.removeView(old)
        }

        let maya = AImageView()
        maya.setImageResource(R.drawable.triple_shot_home_maya)
        maya.scaleType = AImageView.ScaleType.FIT_CENTER
        maya.setAlpha(1)
        maya.elevation = Float(dp(value: 12))
        maya.isClickable = false
        maya.isFocusable = false
        maya.importantForAccessibility = AView.IMPORTANT_FOR_ACCESSIBILITY_NO

        let guest = AImageView()
        guest.setImageResource(R.drawable.triple_shot_home_unicorn32)
        guest.scaleType = AImageView.ScaleType.FIT_CENTER
        guest.setAlpha(1)
        guest.elevation = Float(dp(value: 12))
        guest.isClickable = false
        guest.isFocusable = false
        guest.importantForAccessibility = AView.IMPORTANT_FOR_ACCESSIBILITY_NO

        // Foreground decoration as requested; neither view consumes menu taps.
        root.addView(guest, AViewGroup.LayoutParams(dp(value: 86), dp(value: 150)))
        root.addView(maya, AViewGroup.LayoutParams(dp(value: 130), dp(value: 220)))

        homeMayaView = maya
        homeGuestCharacterView = guest

        // Kotlin local `fun placeCharacters()`; a closure here because the root's layout listener keeps it (weak refs).
        let placeCharacters: () -> Void = { [weak self, weak root, weak maya, weak guest] in
            // The Home fragment can be replaced while this layout callback is still queued
            // (for example when leaving 1v1 and immediately navigating again). Never call
            // Fragment.resources from a delayed callback after detach.
            guard let self, let root, let maya, let guest else { return }
            if !self.isAdded || self.view == nil || maya.parentGroup !== root || guest.parentGroup !== root {
                return
            }
            let density = self.resources.displayMetrics.density

            let mayaPlacement = TripleShotHomeFragment.mayaFrame(
                rootWidth: root.width, rootHeight: root.height, drawable: maya.drawable, density: density
            )
            let mayaParams = maya.layoutParams!
            mayaParams.width = mayaPlacement.width
            mayaParams.height = mayaPlacement.height
            maya.layoutParams = mayaParams
            maya.x = mayaPlacement.x
            maya.y = mayaPlacement.y

            // Smaller mascot on the opposite side. Its lower body deliberately sits behind the
            // ball's usual resting area, so the ball can partially obscure it as requested.
            let guestPlacement = TripleShotHomeFragment.guestFrame(
                rootWidth: root.width, rootHeight: root.height, drawable: guest.drawable, density: density
            )
            let guestParams = guest.layoutParams!
            guestParams.width = guestPlacement.width
            guestParams.height = guestPlacement.height
            guest.layoutParams = guestParams
            guest.x = guestPlacement.x
            guest.y = guestPlacement.y
        }
        root.post { placeCharacters() }
        root.addOnLayoutChangeListener(AOnLayoutChangeListener { _, left, top, right, bottom, oldLeft, oldTop, oldRight, oldBottom in
            if right - left != oldRight - oldLeft || bottom - top != oldBottom - oldTop { placeCharacters() }
        })
    }

    private func installAndStartHomeBall(root: AViewGroup) {
        stopHomeBallAnimation()
        if let old = homeBallView {
            old.parentGroup?.removeView(old)
        }

        let size = dp(value: 54)
        let ball = AImageView()
        ball.setImageResource(R.drawable.triple_shot_home_basketball)
        ball.scaleType = AImageView.ScaleType.FIT_CENTER
        ball.setAlpha(0.96)
        ball.isClickable = false
        ball.isFocusable = false
        ball.importantForAccessibility = AView.IMPORTANT_FOR_ACCESSIBILITY_NO
        ball.elevation = Float(dp(value: 14))

        // The ball intentionally sits above the controls while it falls. It does not consume
        // touch events, and after a few seconds it settles near the bottom and stops animating.
        root.addView(ball, AViewGroup.LayoutParams(size, size))
        homeBallView = ball

        let density = resources.displayMetrics.density
        // floorY, maxX, x, y, vx, vy, bounceCount, lastNs = System.nanoTime(), startedNs = lastNs (Kotlin L410-419).
        var motion = TripleShotHomeBallMotion(
            rootWidth: root.width, rootHeight: root.height, size: size, density: density, nowNs: ASystem.nanoTime()
        )

        ball.x = motion.x
        ball.y = motion.y
        ball.rotation = -12

        // Kotlin `object : Runnable { override fun run() { ...; root.postOnAnimation(this) } }`.
        let frame = ARunnable(withSelf: { [weak self, weak root, weak ball] runnable in
            guard let self, let root, let ball else { return }
            if !self.isAdded || ball.parentGroup !== root { return }

            let now = ASystem.nanoTime()
            let step = motion.frame(now: now)

            ball.x = step.x
            ball.y = step.y
            if let rotationDelta = step.rotationDelta {
                ball.rotation += rotationDelta
            }

            self.homeMayaView?.setAlpha(step.mayaAlpha)

            if step.postAgain {
                root.postOnAnimation(runnable)
            }
        })

        homeBallFrame = frame
        root.postDelayed(frame, 180)
    }

    private func stopHomeBallAnimation() {
        guard let frame = homeBallFrame else { return }
        homeBallView?.parentGroup?.removeCallbacks(frame)
        homeBallFrame = nil
    }

    /**
     * Keeps the existing white home card, but makes only its background about 15% transparent.
     * Child controls/text stay fully opaque because we tint the card surface instead of setting
     * alpha on the whole card.
     */
    private func applyHomeCardTransparency(root: AViewGroup) {
        guard let practice = root.findViewById(R.id.practiceButton) as AView? else { return }
        var current: AView? = practice.parentGroup
        var fallback: AView? = nil

        while let node = current, node !== root {
            if node.background != nil && fallback == nil {
                fallback = node
            }

            if let card = node as? ACardView {
                card.setCardBackgroundColor(AColor.argb(217, 255, 255, 255))
                card.radius = Float(dp(value: 24))
                return
            }
            current = node.parentGroup
        }

        // Fallback for older home XMLs that used a rounded drawable on a regular container.
        if let fallback {
            homeSetBackgroundTintList(fallback, AColorStateList.valueOf(AColor.argb(217, 255, 255, 255)))
        }
    }

    /**
     * The existing footer was intentionally subtle, but on the illustrated court background it
     * became too faint. We only strengthen known disclaimer/privacy/source text and leave the
     * rest of the home typography untouched.
     */
    private func strengthenHomeFooter(root: AView) {
        if let text = root as? ATextView {
            let normalized = text.text.ktrim().lowercased()

            let isDisclaimer =
                homeContains(normalized, "התוכן נוצר") ||
                homeContains(normalized, "נוצר ונערך") ||
                homeContains(normalized, "content created") ||
                homeContains(normalized, "content was created") ||
                homeContains(normalized, "ai-generated")

            let isFooterLink =
                homeContains(normalized, "פרטיות") ||
                homeContains(normalized, "מקורות") ||
                homeContains(normalized, "privacy") ||
                homeContains(normalized, "sources")

            if isDisclaimer {
                text.setAlpha(1)
                text.setTextColor(AColor.parseColor("#2F2825"))
                text.setShadowLayer(1.2, 0, 0.7, AColor.argb(150, 255, 255, 255))
                text.paint.isFakeBoldText = true
            } else if isFooterLink {
                text.setAlpha(1)
                text.setTextColor(AColor.parseColor("#3F8CFF"))
                text.paint.isFakeBoldText = true
            }
        }

        if let group = root as? AViewGroup {
            for i in kuntil(0, group.childCount) {
                strengthenHomeFooter(root: group.getChildAt(i)!)
            }
        }
    }

    private func dp(value: Int) -> Int {
        return (Float(value) * resources.displayMetrics.density + Float(0.5)).toInt()
    }

    /**
     * Starts either unlimited practice or the 60-second ranked Shooting Challenge.
     * The selected topic set is saved with the config so the game screen can filter
     * its local question bank.
     */
    private func launchSolo(
        gameType: GameType,
        limitMode: GameLimitMode,
        timeLimitSeconds: Int
    ) {
        guard let name =
            validatedName()
        else { return }

        if selectedCategories.isEmpty {
            AToast.makeText(
                requireContext(),
                res: R.string.minik_swish_choose_at_least_one_topic,
                AToast.LENGTH_SHORT
            ).show()

            showTopicPicker()
            return
        }

        prefs.edit()
            .putString(TripleShotHomeFragment.KEY_PLAYER_NAME, name)
            .apply()

        chooseHumanCharacter { playerCharacterId in
            (self.parentFragment as? TripleShotHostFragment)?
                .startGame(
                    config: TripleShotGameConfig(
                        playerName: name,
                        gameType: gameType,
                        limitMode: limitMode,
                        selectedCategories:
                            self.selectedCategories,
                        playerCharacterId: playerCharacterId,
                        seed: ASystem.currentTimeMillis(),
                        ballLimit: Int(Int32.max),
                        timeLimitSeconds:
                            timeLimitSeconds
                    )
                )
        }
    }

    /**
     * Local bot play opens one image-first setup surface. Mode, human character and opponent
     * are chosen together, so there is no legacy list/radio dialog before the roster appears.
     */
    private func showBotMatchSetup() {
        guard let name = validatedName() else { return }

        prefs.edit()
            .putString(TripleShotHomeFragment.KEY_PLAYER_NAME, name)
            .apply()

        TripleShotBotMatchSetupDialog.show(
            fragment: self,
            humanProfiles: TripleShotCharacterRoster.humanSelectable(),
            botProfiles: TripleShotCharacterRoster.botSelectable(),
            currentHumanId: loadPlayerCharacterId(),
            currentBotId: loadBotCharacterId(),
            // Keep the real-art guard for future roster additions; all current characters have packs.
            canSelectHuman: { TripleShotCharacterVisualCatalog.hasVisuals(characterId: $0.id) },
            canSelectBot: { TripleShotCharacterVisualCatalog.hasVisuals(characterId: $0.id) },
            onStart: { selection in
                let gameType = selection.gameType
                if gameType != GameType.ONE_ON_ONE && gameType != GameType.TEAM_MATCH && self.selectedCategories.isEmpty {
                    AToast.makeText(
                        self.requireContext(),
                        res: R.string.minik_swish_choose_at_least_one_topic,
                        AToast.LENGTH_SHORT
                    ).show()
                    self.showTopicPicker()
                    return
                }

                // Preserve the identity of every authored character; guard future incomplete additions.
                let resolvedHumanId =
                    gameType == GameType.ONE_ON_ONE &&
                        !TripleShotCharacterVisualCatalog.hasVisuals(characterId: selection.human.id)
                    ? TripleShotCharacterRoster.ID_WOMAN_DARK : selection.human.id
                let primaryOpponent = selection.opponents.first ?? TripleShotCharacterRoster.womanDark
                let resolvedBotId =
                    gameType == GameType.ONE_ON_ONE &&
                        !TripleShotCharacterVisualCatalog.hasVisuals(characterId: primaryOpponent.id)
                    ? TripleShotCharacterRoster.ID_WOMAN_DARK : primaryOpponent.id

                self.savePlayerCharacterId(id: resolvedHumanId)
                self.saveBotCharacterId(id: resolvedBotId)

                (self.parentFragment as? TripleShotHostFragment)?
                    .startGame(
                        config: TripleShotGameConfig(
                            playerName: name,
                            gameType: gameType,
                            limitMode:
                                gameType == GameType.HORSE || gameType == GameType.ONE_ON_ONE || gameType == GameType.TEAM_MATCH
                                ? GameLimitMode.BALLS_ONLY
                                : GameLimitMode.TIME_ONLY,
                            selectedCategories: self.selectedCategories,
                            botMatch: true,
                            playerCharacterId: resolvedHumanId,
                            botCharacterId: resolvedBotId,
                            teamSize: selection.teamSize,
                            teammateCharacterIds: selection.teammates.map { $0.id },
                            opponentCharacterIds: selection.opponents.map { $0.id },
                            gameOrientation: selection.gameOrientation,
                            courtId: selection.courtId,
                            seed: ASystem.currentTimeMillis(),
                            ballLimit: Int(Int32.max),
                            timeLimitSeconds:
                                gameType == GameType.HORSE || gameType == GameType.ONE_ON_ONE || gameType == GameType.TEAM_MATCH ? 0
                                : TripleShotHomeFragment.SHOOTING_CHALLENGE_SECONDS
                        )
                    )
            }
        )
    }

    private func chooseHumanCharacter(
        onSelected: @escaping (String) -> Void
    ) {
        let profiles = TripleShotCharacterRoster.humanSelectable()
        if profiles.isEmpty {
            onSelected(TripleShotCharacterRoster.ID_WOMAN_DARK)
            return
        }

        TripleShotCharacterPickerDialog.show(
            fragment: self,
            mode: TripleShotCharacterPickerDialog.Mode.HUMAN,
            profiles: profiles,
            currentId: loadPlayerCharacterId(),
            canSelect: { profile in
                TripleShotCharacterVisualCatalog.hasVisuals(characterId: profile.id)
            },
            onSelected: { profile in
                self.savePlayerCharacterId(id: profile.id)
                onSelected(profile.id)
            }
        )
    }

    // chooseBotCharacter / chooseLocalMatchCharacters (Kotlin L774-806): unused on Android (they only call each
    // other), not ported (spec 18 §8.11).

    private func loadPlayerCharacterId() -> String {
        let saved =
            prefs.getString(
                TripleShotHomeFragment.KEY_PLAYER_CHARACTER,
                TripleShotCharacterRoster.ID_WOMAN_DARK
            )

        if let saved,
           TripleShotCharacterVisualCatalog.hasVisuals(characterId: saved) {
            return saved
        } else {
            return TripleShotCharacterRoster.ID_WOMAN_DARK
        }
    }

    private func savePlayerCharacterId(id: String) {
        prefs.edit()
            .putString(TripleShotHomeFragment.KEY_PLAYER_CHARACTER, id)
            .apply()
    }

    private func loadBotCharacterId() -> String {
        let saved =
            prefs.getString(
                TripleShotHomeFragment.KEY_BOT_CHARACTER,
                TripleShotCharacterRoster.ID_BOB
            )

        return TripleShotCharacterRoster.find(id: saved)?.id
            ?? TripleShotCharacterRoster.ID_BOB
    }

    private func saveBotCharacterId(id: String) {
        prefs.edit()
            .putString(TripleShotHomeFragment.KEY_BOT_CHARACTER, id)
            .apply()
    }

    private func showTopicPicker() {
        TripleShotTopicsDialog.show(c: requireContext(), title: getString(R.string.minik_swish_choose_topics), selected: selectedCategories) { pending in
            self.selectedCategories = pending; self.saveSelectedCategories(); self.updateTopicButton()
        }
    }

    private func updateTopicButton() {
        let language =
            currentLanguageCode()

        topicButton.text =
            TripleShotHomeFragment.topicButtonText(
                selectedCategories: selectedCategories,
                language: language
            )
    }

    /// The `when` of updateTopicButton (Kotlin L939-963) for a selection and a language code: all topics ->
    /// "Topics: all"; one or two -> the prefix, a space and their labels in ordinal order joined by " • "; more -> the
    /// `minik_swish_topics_count` plural. (`getString` / `resources.getQuantityString` of the fragment are the app's
    /// string tables.)
    static func topicButtonText(selectedCategories: KLinkedSet<QuestionCategory>, language: String) -> String {
        let all =
            KLinkedSet(QuestionCategory.allCases)

        if selectedCategories == all {
            return AResources.getString(
                R.string.minik_swish_topics_all
            )
        } else if selectedCategories.count <= 2 {
            return AResources.getString(
                R.string.minik_swish_topics_prefix
            ) +
                " " +
                selectedCategories.elements
                    .kSortedBy { $0.ordinal }
                    .map {
                        $0.labelFor(languageCode: language)
                    }
                    .joined(separator: " \u{2022} ")
        } else {
            return AContextResources.shared.getQuantityString(
                R.plurals.minik_swish_topics_count,
                selectedCategories.count,
                selectedCategories.count
            )
        }
    }

    private func loadSelectedCategories() ->
        KLinkedSet<QuestionCategory> {

        let saved =
            prefs.getStringSet(
                TripleShotHomeFragment.KEY_SELECTED_CATEGORIES,
                nil
            )

        guard let saved, !saved.isEmpty else {
            return KLinkedSet(QuestionCategory.allCases)
        }

        // `runCatching { QuestionCategory.valueOf(name) }.getOrNull()`: unknown names are dropped.
        let parsed =
            KLinkedSet(saved.compactMap { name in
                QuestionCategory.named(name)
            })

        return parsed.isEmpty ? KLinkedSet(QuestionCategory.allCases) : parsed
    }

    private func saveSelectedCategories() {
        prefs.edit()
            .putStringSet(
                TripleShotHomeFragment.KEY_SELECTED_CATEGORIES,
                selectedCategories
                    .map { $0.name }
            )
            .apply()
    }

    /**
     * Opens a real LIVE setup Fragment instead of the old two-item mode dialog.
     * Name/topics stay owned by Home; the new screen owns mode/character selection and hosting.
     */
    private func openLiveSetup() {
        TripleShotOnlineIdentity.choose(c: requireContext()) { name in self.openLiveSetupWithNickname(name: name) }
    }
    private func openLiveSetupWithNickname(name: String) {

        if selectedCategories.isEmpty {
            AToast.makeText(
                requireContext(),
                res: R.string.minik_swish_choose_at_least_one_topic,
                AToast.LENGTH_SHORT
            ).show()
            showTopicPicker()
            return
        }

        (parentFragment as? TripleShotHostFragment)?.showLiveSetup(
            playerName: name,
            selectedCategories: selectedCategories,
            playerCharacterId: loadPlayerCharacterId()
        )
    }

    private func joinRoom(
        button: AButton,
        codeInput: AEditText
    ) {
        let code =
            codeInput.text
                .ktrim()
                .uppercased()

        if code.length != 6 {
            AToast.makeText(
                requireContext(),
                res: R.string.minik_swish_room_code_error,
                AToast.LENGTH_SHORT
            ).show()

            return
        }

        TripleShotOnlineIdentity.choose(c: requireContext()) { name in
        button.isEnabled = false

        self.firebase.joinRoom(
            codeRaw: code,
            playerName: name
        ) { result in
            if !self.isAdded { return }

            button.isEnabled = true

            switch result {
            case .success(let seed):
                self.currentRoomCode = code
                self.currentSeed = seed
                self.isHost = false
                self.launchedRoomGame = false

                self.showRoomPanel(code: code)
                self.listenToRoom(code: code)
            case .failure(let error):
                self.showError(throwable: error)
            }
        }
        }
    }

    private func validatedName() -> String? {
        let name =
            nameInput.text
                .ktrim()

        if name.length < 2 {
            nameInput.error =
                getString(
                    R.string.minik_swish_name_error
                )

            return nil
        }

        return name.ktake(18)
    }

    private func showRoomPanel(code: String) {
        roomPanel.visibility = AView.VISIBLE
        waitingRoomBackCallback?.isEnabled = true

        roomStatusText.text =
            isHost
            ? getString(
                R.string.minik_swish_room_created,
                code
            )
            : getString(
                R.string.minik_swish_room_joined,
                code
            )

        startRoomButton.visibility =
            isHost
            ? AView.VISIBLE
            : AView.GONE

        updateRoomControls()
    }

    /**
     * The host owns the room rules. Joiners do not reuse their local topic picker; they
     * receive the exact same topic set, timer and seed from Firebase before launch.
     */
    private func listenToRoom(code: String) {
        roomMetaHandle?.remove()
        roomPlayersHandle?.remove()

        roomMetaHandle =
            firebase.listenRoomMeta(codeRaw: code) { [weak self] meta in
                guard let self, self.isAdded else {
                    return
                }

                guard let meta else {
                    if self.currentRoomCode == code {
                        self.stopRoomListeners()
                        self.clearRoomLobbyState()
                    }
                    return
                }

                self.currentSeed = meta.seed

                if
                    meta.status == "PLAYING" &&
                    !self.launchedRoomGame
                {
                    self.launchedRoomGame = true
                    self.waitingRoomBackCallback?.isEnabled = false

                    let name =
                        self.validatedName()
                            ?? self.getString(R.string.triple_shot_live_setup_player_fallback)

                    let parsedCategories =
                        KLinkedSet(
                            meta.categories
                                .compactMap { categoryName in
                                    QuestionCategory.named(categoryName)
                                }
                        )

                    (self.parentFragment as? TripleShotHostFragment)?
                        .startGame(
                            config: TripleShotGameConfig(
                                playerName: name,
                                gameType:
                                    GameType.named(meta.gameType)
                                        ?? GameType.SHOOTING_CHALLENGE,
                                limitMode:
                                    (GameType.named(meta.gameType)
                                        ?? GameType.SHOOTING_CHALLENGE) == GameType.HORSE
                                    ? GameLimitMode.BALLS_ONLY
                                    : GameLimitMode.TIME_ONLY,
                                selectedCategories:
                                    parsedCategories.isEmpty ? KLinkedSet(QuestionCategory.allCases) : parsedCategories,
                                roomId: code,
                                roomStartedAtMs: meta.startedAt,
                                playerCharacterId: self.loadPlayerCharacterId(),
                                seed: meta.seed,
                                ballLimit: Int(Int32.max),
                                timeLimitSeconds:
                                    meta.timeLimitSeconds.coerceAtLeast(10)
                            )
                        )
                }
            }

        roomPlayersHandle =
            firebase.listenRoomPlayers(codeRaw: code) { [weak self] players in
                guard let self, self.isAdded else {
                    return
                }

                self.renderPlayers(players: players)
            }
    }

    /**
     * While a host owns a WAITING room the same button becomes "Close room".
     * This prevents accidentally creating several lobbies from one client.
     */
    private func updateRoomControls() {
        if createRoomButton == nil { return }

        let inRoom = currentRoomCode != nil

        createRoomButton.text =
            inRoom && isHost
            ? getString(R.string.minik_swish_live_close_room)
            : getString(R.string.triple_shot_create_room)

        createRoomButton.isEnabled =
            !inRoom || isHost

        if joinRoomButton != nil {
            joinRoomButton.isEnabled = !inRoom
        }

        if roomCodeInput != nil {
            roomCodeInput.isEnabled = !inRoom
        }
    }

    /// Host only: dead in Home (`isHost` is never true; hosting lives in Live setup, spec 18 §8.9). Ported as it is.
    private func confirmCloseWaitingRoom() {
        guard let code = currentRoomCode else { return }
        if !isHost { return }

        AMaterialAlertDialogBuilder(requireContext())
            .setTitle(res: R.string.minik_swish_live_close_room_title)
            .setMessage(res: R.string.minik_swish_live_close_room_message)
            .setPositiveButton(res: R.string.minik_swish_live_close_room) { _, _ in
                self.closeHostedWaitingRoom(code: code)
            }
            .setNegativeButton(res: android.R.string.cancel, nil)
            .show()
    }

    private func closeHostedWaitingRoom(code: String) {
        stopRoomListeners()
        createRoomButton.isEnabled = false

        firebase.deleteWaitingRoom(roomCodeRaw: code) { result in
            if !self.isAdded { return }

            switch result {
            case .success:
                self.clearRoomLobbyState()
            case .failure(let error):
                self.createRoomButton.isEnabled = true
                self.showError(throwable: error)
            }
        }
    }

    /**
     * Back while a lobby is still WAITING means "leave this lobby", not "minimize app".
     * Hosts remove the entire waiting room immediately; joiners remove only themselves.
     * A host crash/force-close is covered separately by Firebase onDisconnect().
     */
    private func leaveCurrentWaitingRoom() {
        guard let code = currentRoomCode else { return }

        stopRoomListeners()

        if isHost {
            firebase.deleteWaitingRoom(roomCodeRaw: code) { result in
                if !self.isAdded { return }
                if case .failure(let error) = result { self.showError(throwable: error) }
            }
        } else {
            firebase.leaveRoom(roomCodeRaw: code)
        }

        clearRoomLobbyState()
    }

    private func stopRoomListeners() {
        roomMetaHandle?.remove()
        roomPlayersHandle?.remove()
        roomMetaHandle = nil
        roomPlayersHandle = nil
    }

    private func clearRoomLobbyState() {
        currentRoomCode = nil
        currentSeed = 0
        isHost = false
        launchedRoomGame = false
        waitingRoomBackCallback?.isEnabled = false

        if roomPanel != nil {
            roomPanel.visibility = AView.GONE
        }

        updateRoomControls()
    }

    private func renderPlayers(
        players: [LivePlayerState]
    ) {
        // Kotlin `roomPlayersText.text = ...` is setText(CharSequence): the names come from Firebase, so the plain-text
        // setter is used below (a lone name is never resolved as a string-resource name).
        let playersLine: String =
            players.isEmpty
            ? getString(
                R.string.minik_swish_no_players
            )
            : players
                .prefix(4)
                .map {
                    $0.name.kotlinIsBlank ? getString(R.string.triple_shot_live_setup_player_fallback) : $0.name
                }
                .joined(separator: "  \u{2022}  ")

        homeSetText(roomPlayersText, playersLine)

        if isHost {
            startRoomButton.isEnabled =
                players.count >= 2 && players.count <= 4

            startRoomButton.text =
                getString(
                    R.string.minik_swish_start_players,
                    players.count.coerceAtMost(4)
                )
        }
    }

    /**
     * AI-content notice and an in-app privacy summary live together so users can
     * always find them from the home screen.
     *
     * Before Play release, put the real public privacy-policy URL in
     * `minik_swish_privacy_policy_url`. Until then the in-app text still works,
     * but the Play Console itself will also require a public URL.
     */
    private func showInformationAndPrivacy() {
        let url =
            getString(
                R.string.minik_swish_privacy_policy_url
            ).ktrim()

        let builder =
            AMaterialAlertDialogBuilder(requireContext())
                .setTitle(
                    res: R.string.minik_swish_info_privacy_title
                )
                .setMessage(
                    res: R.string.minik_swish_info_privacy_body
                )
                .setNegativeButton(
                    res: R.string.minik_swish_close,
                    nil
                )

        if !url.kotlinIsBlank {
            builder.setPositiveButton(
                res: R.string.minik_swish_open_privacy_policy
            ) { _, _ in
                do {
                    try self.startActivity(
                        AIntent(
                            AIntent.ACTION_VIEW,
                            AUri.parse(url)
                        )
                    )
                } catch {
                    AToast.makeText(
                        self.requireContext(),
                        res: R.string.minik_swish_cannot_open_link,
                        AToast.LENGTH_SHORT
                    ).show()
                }
            }
        }

        builder.show()
    }

    private func currentLanguageCode() -> String {
        return (AConfigurationCompat.getLocales(resources.configuration)[0] ?? ALocale.getDefault())
            .language
    }

    private func showError(
        throwable: Error
    ) {
        AToast.makeText(
            requireContext(),
            homeThrowableMessage(throwable)
                ?? getString(
                    R.string.minik_swish_firebase_error
                ),
            AToast.LENGTH_LONG
        ).show()
    }

    /**
     * Same navigation-bar fix used on the game screen. This keeps the Android
     * triangle/circle/square visible on devices whose default theme produced
     * white navigation icons on a white navigation background.
     */
    private func configureNavigationBar() {
        let window =
            requireActivity().window

        window.navigationBarColor =
            AColor.parseColor("#101820")

        AWindowCompat.getInsetsController(
            window,
            window.decorView
        ).isAppearanceLightNavigationBars = false

        // `Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q`: always true (AndroidKit models a current Android).
        window.isNavigationBarContrastEnforced =
            false
    }

    override func onDestroyView() {
        // androidx saves the view hierarchy state just before the view is torn down (see homeSavedViewState).
        homeSavedViewState = homeSaveViewState()
        stopHomeBallAnimation()
        homeBallView = nil
        homeMayaView = nil
        homeGuestCharacterView = nil
        stopRoomListeners()
        waitingRoomBackCallback = nil
        super.onDestroyView()
    }

    override func onViewStateRestored(_ savedInstanceState: ABundle?) {
        // Fragment.restoreViewState: `mView.restoreHierarchyState(mSavedViewState)`, then onViewStateRestored.
        if let state = homeSavedViewState, let root = view {
            homeSavedViewState = nil
            homeRestoreViewState(state, root)
        }
        super.onViewStateRestored(savedInstanceState)
    }

    // MARK: - Fragment view state (androidx FragmentStateManager.saveViewState / Fragment.restoreViewState)

    /// The saved view hierarchy state of this fragment's last view, AndroidKit emulation (area s-home). On Android a
    /// fragment whose view is destroyed while it stays in the FragmentManager (Home under Live setup, "live_setup" on
    /// the back stack) saves the state of its views with ids, and the next view gets it back right after onViewCreated:
    /// returning from Live setup (its `popBackStack()`) shows the typed, possibly unsaved, name and room code and the
    /// same scroll position (spec 18 §4.2.2). AndroidKit's AFragment does not save view state, so Home keeps the parts
    /// of `SparseArray<Parcelable>` its views produce: the two EditTexts (TextView.SavedState: text, selection, error;
    /// EditText freezes its text) and the ScrollView (scrollPosition). Nothing else in the home tree saves state.
    private var homeSavedViewState: HomeViewState? = nil

    private struct HomeTextState {
        var text: String
        var selectionStart: Int
        var selectionEnd: Int
        var error: String?
    }

    private struct HomeViewState {
        var playerName: HomeTextState?
        var roomCode: HomeTextState?
        var scrollY: Int?
    }

    private func homeSaveViewState() -> HomeViewState? {
        guard let root = view else { return nil }
        func save(_ id: String) -> HomeTextState? {
            guard let edit = root.findViewById(id) as AEditText? else { return nil }
            return HomeTextState(text: edit.text, selectionStart: edit.selectionStart, selectionEnd: edit.selectionEnd,
                                 error: edit.error)
        }
        let scroll = root.findViewById(R.id.homeScroll) as AScrollView?
        return HomeViewState(playerName: save(R.id.playerNameInput), roomCode: save(R.id.roomCodeInput),
                             scrollY: scroll?.getScrollY())
    }

    private func homeRestoreViewState(_ state: HomeViewState, _ root: AView) {
        func restore(_ id: String, _ saved: HomeTextState?) {
            guard let saved, let edit = root.findViewById(id) as AEditText? else { return }
            // TextView.onRestoreInstanceState: setText(ss.text), the selection when it fits, the error posted.
            homeSetText(edit, saved.text)
            let length = edit.length()
            if saved.selectionStart >= 0 && saved.selectionEnd >= 0
                && saved.selectionStart <= length && saved.selectionEnd <= length {
                edit.setSelection(saved.selectionStart, saved.selectionEnd)
            }
            if let error = saved.error {
                edit.post { [weak edit] in edit?.setError(error) }
            }
        }
        restore(R.id.playerNameInput, state.playerName)
        restore(R.id.roomCodeInput, state.roomCode)
        // ScrollView.onRestoreInstanceState keeps the position for its first layout (onLayout: mScrollY, then the
        // clamp and scrollTo): applied once, right after that layout.
        if let scrollY = state.scrollY, scrollY > 0, let scroll = root.findViewById(R.id.homeScroll) as AScrollView? {
            let pending = KRef<AOnLayoutChangeListener?>(nil)
            let listener = AOnLayoutChangeListener { v, _, _, _, _, _, _, _, _ in
                if let l = pending.value { v.removeOnLayoutChangeListener(l) }
                pending.value = nil
                v.scrollTo(v.getScrollX(), scrollY)
            }
            pending.value = listener
            scroll.addOnLayoutChangeListener(listener)
        }
    }

    // MARK: - companion object

    private static let PREFS_NAME =
        "triple_shot"

    private static let KEY_PLAYER_NAME =
        "player_name"

    private static let KEY_SELECTED_CATEGORIES =
        "selected_categories"

    private static let KEY_PLAYER_CHARACTER =
        "player_character"

    private static let KEY_BOT_CHARACTER =
        "bot_character"

    private static let SHOOTING_CHALLENGE_SECONDS =
        60

    // MARK: - placeCharacters() arithmetic (Kotlin L337-379)

    /// The layout size and position one decoration gets from placeCharacters(): `width` / `height` go into its layout
    /// params, `x` / `y` into View.setX / setY (px).
    struct CharacterFrame: Equatable {
        var width: Int
        var height: Int
        var x: Float
        var y: Float
    }

    /// Maya (`triple_shot_home_maya`), Kotlin L337-356: height `clamp(0.225·H, dp(135), dp(180))`, the drawable's
    /// intrinsic aspect (0.58 without one), width `max(trunc(h·aspect), dp(96))`, 30 % of her width off the right
    /// edge, 1 dp above the bottom. `dp` is the fragment's rounded `dp()` at `density`.
    static func mayaFrame(rootWidth: Int, rootHeight: Int, drawable: ADrawable?, density: Float) -> CharacterFrame {
        func dp(_ value: Int) -> Int { return (Float(value) * density + Float(0.5)).toInt() }
        let mayaHeight = (Float(rootHeight) * Float(0.225))
            .coerceIn(Float(dp(135)), Float(dp(180)))
        let mayaRatio: Float
        if let mayaDrawable = drawable,
           mayaDrawable.intrinsicWidth > 0,
           mayaDrawable.intrinsicHeight > 0 {
            mayaRatio = Float(mayaDrawable.intrinsicWidth) / Float(mayaDrawable.intrinsicHeight)
        } else {
            mayaRatio = Float(0.58)
        }
        let mayaWidth = mayaHeight * mayaRatio

        let width = mayaWidth.toInt().coerceAtLeast(dp(96))
        let height = mayaHeight.toInt()
        let x = (Float(rootWidth) - Float(width) * Float(0.70)).coerceAtLeast(0)
        let y = (Float(rootHeight) - mayaHeight - Float(dp(1))).coerceAtLeast(0)
        return CharacterFrame(width: width, height: height, x: x, y: y)
    }

    /// The guest (`triple_shot_home_unicorn32`), Kotlin L360-379: height `clamp(0.155·H, dp(92), dp(125))`, aspect
    /// (0.82 without a drawable), width `max(trunc(h·aspect), dp(70))`, x `max(-0.22·h·aspect, -dp(24))`, 1 dp above
    /// the bottom.
    static func guestFrame(rootWidth: Int, rootHeight: Int, drawable: ADrawable?, density: Float) -> CharacterFrame {
        func dp(_ value: Int) -> Int { return (Float(value) * density + Float(0.5)).toInt() }
        let guestHeight = (Float(rootHeight) * Float(0.155))
            .coerceIn(Float(dp(92)), Float(dp(125)))
        let guestRatio: Float
        if let guestDrawable = drawable,
           guestDrawable.intrinsicWidth > 0,
           guestDrawable.intrinsicHeight > 0 {
            guestRatio = Float(guestDrawable.intrinsicWidth) / Float(guestDrawable.intrinsicHeight)
        } else {
            guestRatio = Float(0.82)
        }
        let guestWidth = guestHeight * guestRatio

        let width = guestWidth.toInt().coerceAtLeast(dp(70))
        let height = guestHeight.toInt()
        let x = (-guestWidth * Float(0.22)).coerceAtLeast(-Float(dp(24)))
        let y = (Float(rootHeight) - guestHeight - Float(dp(1))).coerceAtLeast(0)
        return CharacterFrame(width: width, height: height, x: x, y: y)
    }
}

// MARK: - The one-shot home ball (Kotlin L409-475)

/// The state of installAndStartHomeBall: the Kotlin locals (`floorY`, `maxX`, `x`, `y`, `vx`, `vy`, `bounceCount`,
/// `lastNs`, `startedNs`, L410-419) and the body of its frame Runnable (L428-475), with the same Float statements in the
/// same order, as a value type so the parity tests can drive it with a fixed clock (JVM golden vectors in HomeTests;
/// spec 18 §4.4.10). Units are Android px: the speeds and thresholds are multiplied by the density as on Android.
struct TripleShotHomeBallMotion {
    let size: Int
    let density: Float
    let floorY: Float
    let maxX: Float
    var x: Float
    var y: Float
    var vx: Float
    var vy: Float
    var bounceCount: Int
    var lastNs: Int64
    let startedNs: Int64

    /// What one frame writes to the views (Kotlin L463-475).
    struct Step: Equatable {
        /// `ball.x = x`, `ball.y = y`.
        var x: Float
        var y: Float
        /// `ball.rotation += (vx * dt / size) * 105f` (degrees), nil when `size <= 0` (Kotlin `if (size > 0)`).
        var rotationDelta: Float?
        /// `homeMayaView?.alpha = 1f - .75f * (elapsedSec / 5f).coerceIn(0f, 1f)`.
        var mayaAlpha: Float
        /// `(!settled || elapsedSec < 5f) && elapsedSec < 7.0f`: `root.postOnAnimation(this)`.
        var postAgain: Bool
    }

    /// Kotlin L410-419 for a root of `rootWidth` x `rootHeight` px, a ball of `size` px and `nowNs` =
    /// `System.nanoTime()` at install (taken before the 180 ms delay).
    init(rootWidth: Int, rootHeight: Int, size: Int, density: Float, nowNs: Int64) {
        self.size = size
        self.density = density
        let floorY = (rootHeight - size).coerceAtLeast(0).toFloat()
        let maxX = (rootWidth - size).coerceAtLeast(0).toFloat()
        self.floorY = floorY
        self.maxX = maxX

        x = (Float(rootWidth) * Float(0.76) - Float(size) * Float(0.5)).coerceIn(0, maxX)
        y = Float(-size) * Float(1.15)
        vx = Float(-82) * density
        vy = 0
        bounceCount = 0
        lastNs = nowNs
        startedNs = nowNs
    }

    /// The frame Runnable's body after its `isAdded` / parent guard (Kotlin L429-475).
    mutating func frame(now: Int64) -> Step {
        let dt = ((now - lastNs).toFloat() / Float(1_000_000_000))
            .coerceIn(0.001, 0.032)
        lastNs = now

        // Approximate real-world gravity in screen space. The restitution slowly drops,
        // so each bounce is visibly lower than the previous one.
        vy += Float(2350) * density * dt
        x += vx * dt
        y += vy * dt

        if x < 0 {
            x = 0
            vx = abs(vx) * Float(0.72)
        } else if x > maxX {
            x = maxX
            vx = -abs(vx) * Float(0.72)
        }

        if y >= floorY {
            y = floorY
            let restitution = (Float(0.66) - Float(bounceCount) * Float(0.055)).coerceAtLeast(0.42)
            let impactSpeed = abs(vy)

            if impactSpeed < Float(145) * density || bounceCount >= 5 {
                vy = 0
                vx *= Float(0.82)
            } else {
                vy = -impactSpeed * restitution
                vx *= Float(0.92)
                bounceCount += 1
            }
        }

        let rotationDelta: Float? = size > 0 ? (vx * dt / Float(size)) * Float(105) : nil

        let elapsedSec = (now - startedNs).toFloat() / Float(1_000_000_000)
        let mayaAlpha = Float(1) - Float(0.75) * (elapsedSec / Float(5)).coerceIn(0, 1)
        let settled = y >= floorY - Float(0.5) && vy == 0 && abs(vx) < Float(18) * density

        return Step(
            x: x,
            y: y,
            rotationDelta: rotationDelta,
            mayaAlpha: mayaAlpha,
            postAgain: (!settled || elapsedSec < 5) && elapsedSec < Float(7.0)
        )
    }
}

// MARK: - Private helpers (area s-home)

/// `view.findViewById<T>(id)` assigned to a non-null Kotlin type: a missing view or another class crashes, like Kotlin.
private func homeRequireView<T: AView>(_ root: AView, _ id: String, _ type: T.Type) -> T {
    guard let found = root.findViewById(id) as AView? else {
        preconditionFailure("TripleShotHomeFragment: no view with id \(id)")
    }
    return found as! T
}

/// `TextView.setText(CharSequence)` of user text (the saved player name, restored field text, the lobby's player names):
/// the plain text, filters applied, without AndroidKit's resolution of strings that look like a string-resource name
/// (`setText(String)`), which Android's `setText(CharSequence)` never does.
private func homeSetText(_ view: ATextView, _ text: String?) {
    view.aw_setText(text ?? "", notifyBefore: true)
}

/// Kotlin `String.contains(other)` (UTF-16 code units, no Unicode normalisation).
private func homeContains(_ s: String, _ other: String) -> Bool {
    return s.range(of: other, options: .literal) != nil
}

/// `View.setBackgroundTintList(tint)` on any view: TextViews keep the tint (ATextView), other views tint their current
/// background like View.applyBackgroundTint (`mutate()` + `setTintList`). (The Kotlin fallback branch that uses it is not
/// reached: the home card is a MaterialCardView.)
private func homeSetBackgroundTintList(_ view: AView, _ tint: AColorStateList?) {
    if let text = view as? ATextView {
        text.setBackgroundTintList(tint)
    } else if let background = view.background {
        background.mutate()
        background.setTintList(tint)
        if background.isStateful { background.setState(view.drawableState) }
        view.invalidate()
    }
}

/// `Throwable.message` of a repository / Firebase failure (nil when the exception has no message).
private func homeThrowableMessage(_ error: Error) -> String? {
    if let exception = error as? AFirebaseException { return exception.message }
    return (error as? LocalizedError)?.errorDescription
}

// MARK: - res/layout/fragment_triple_shot_home.xml

/// `res/layout/fragment_triple_shot_home.xml` built in code, in XML order, with the same ids, attributes and layout
/// params, read the way the Android inflater reads them (getDimensionPixelSize for sizes / margins / paddings / text
/// sizes, getDimension for radii and elevations). Each view is configured before it is added to its parent, like the
/// inflater (`rInflateChildren` before `parent.addView`). `TripleShotHomeFragment.onViewCreated` then re-organizes the
/// tree exactly like Android.
///
/// iOS-only additions: the "Leave room" control in the room panel (`TripleShotHomeFragment.IOS_LEAVE_ROOM_BUTTON_ID`) and
/// the safe-area listener of the root (`applySafeArea`).
enum TripleShotHomeLayout {

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

        // <androidx.constraintlayout.widget.ConstraintLayout match_parent x match_parent background="#FFFDF5">
        let root = AConstraintLayout()
        root.layoutParams = AViewGroup.LayoutParams(MATCH, MATCH)
        root.setBackgroundColor(AColor.parseColor("#FFFDF5"))

        // <ImageView @+id/homeBackground 0dp x 0dp alpha 0.42 contentDescription @null scaleType centerCrop
        //  src @drawable/triple_shot_court_background, four parent edges>
        let homeBackground = AImageView()
        homeBackground.viewId = R.id.homeBackground
        homeBackground.setAlpha(0.42)
        homeBackground.contentDescription = nil
        homeBackground.scaleType = AImageView.ScaleType.CENTER_CROP
        homeBackground.setImageResource(R.drawable.triple_shot_court_background)
        let homeBackgroundParams = AConstraintLayout.LayoutParams(0, 0)
        homeBackgroundParams.bottomToBottom = PARENT
        homeBackgroundParams.endToEnd = PARENT
        homeBackgroundParams.startToStart = PARENT
        homeBackgroundParams.topToTop = PARENT
        root.addView(homeBackground, homeBackgroundParams)

        // <LinearLayout @+id/homeFixedHeader 0dp x wrap vertical gravity center_horizontal paddingTop 34dp
        //  paddingBottom 8dp paddingStart 20dp paddingEnd 20dp, top / start / end to parent>
        let header = ALinearLayout()
        header.viewId = R.id.homeFixedHeader
        header.orientation = ALinearLayout.VERTICAL
        header.gravity = AGravity.CENTER_HORIZONTAL
        header.setPaddingRelative(px(20), px(34), px(20), px(8))

        //   <com.appsbybros.minik.swish.ui.OutlinedTitleView @+id/homeTitle wrap x wrap @string/triple_shot_title
        //    textColor @color/triple_shot_ink 32sp bold>
        let title = OutlinedTitleView()
        title.viewId = R.id.homeTitle
        title.setText(res: R.string.triple_shot_title)
        title.setTextColor(R.color.triple_shot_ink)
        title.applyXmlTextSize(32)
        bold(title)
        header.addView(title, ALinearLayout.LayoutParams(WRAP, WRAP))

        //   <TextView @+id/homeSubtitle wrap x wrap marginTop 2dp @string/triple_shot_subtitle
        //    textColor @color/triple_shot_green 17sp bold>
        let subtitle = ATextView()
        subtitle.viewId = R.id.homeSubtitle
        subtitle.setText(res: R.string.triple_shot_subtitle)
        subtitle.setTextColor(R.color.triple_shot_green)
        subtitle.applyXmlTextSize(17)
        bold(subtitle)
        let subtitleParams = ALinearLayout.LayoutParams(WRAP, WRAP)
        subtitleParams.topMargin = px(2)
        header.addView(subtitle, subtitleParams)

        let headerParams = AConstraintLayout.LayoutParams(0, WRAP)
        headerParams.topToTop = PARENT
        headerParams.startToStart = PARENT
        headerParams.endToEnd = PARENT
        root.addView(header, headerParams)

        // <ScrollView @+id/homeScroll 0dp x 0dp clipToPadding false fillViewport true overScrollMode never,
        //  bottom / end / start to parent, top to bottom of homeFixedHeader>
        let scroll = AScrollView()
        scroll.viewId = R.id.homeScroll
        scroll.clipToPadding = false
        scroll.isFillViewport = true
        scroll.overScrollMode = AView.OVER_SCROLL_NEVER

        //   <ConstraintLayout match_parent x wrap minHeight 640dp paddingBottom 30dp>
        //   (ConstraintLayout lets us cap the content width on tablets while still filling a phone naturally.)
        let column = AConstraintLayout()
        column.minimumHeight = px(640)
        column.setPadding(0, 0, 0, px(30))

        //     <LinearLayout @+id/homeContent 0dp x wrap marginStart 20dp marginTop 6dp marginEnd 20dp
        //      gravity center_horizontal vertical, end / start / top to parent, constraintWidth_max 520dp>
        let homeContent = ALinearLayout()
        homeContent.viewId = R.id.homeContent
        homeContent.gravity = AGravity.CENTER_HORIZONTAL
        homeContent.orientation = ALinearLayout.VERTICAL

        homeContent.addView(buildActionCard(), {
            let params = ALinearLayout.LayoutParams(MATCH, WRAP)
            params.topMargin = px(20)
            return params
        }())
        homeContent.addView(buildRoomPanel(), {
            let params = ALinearLayout.LayoutParams(MATCH, WRAP)
            params.topMargin = px(12)
            return params
        }())

        //       <TextView @+id/aiDisclaimerText match x wrap marginTop 14dp gravity start|center_vertical
        //        textAlignment viewStart @string/minik_swish_ai_disclaimer_short textColor #222222 16sp>
        let disclaimer = ATextView()
        disclaimer.viewId = R.id.aiDisclaimerText
        disclaimer.setGravity(AGravity.START | AGravity.CENTER_VERTICAL)
        disclaimer.textAlignment = AView.TEXT_ALIGNMENT_VIEW_START
        disclaimer.setText(res: R.string.minik_swish_ai_disclaimer_short)
        disclaimer.setTextColor(AColor.parseColor("#222222"))
        disclaimer.applyXmlTextSize(16)
        let disclaimerParams = ALinearLayout.LayoutParams(MATCH, WRAP)
        disclaimerParams.topMargin = px(14)
        homeContent.addView(disclaimer, disclaimerParams)

        //       <TripleShotButton @+id/infoPrivacyButton style TextButton wrap x 44dp
        //        @string/minik_swish_info_privacy_button textAllCaps false textColor @color/triple_shot_purple>
        let info = TripleShotButton(style: .TEXT)
        info.viewId = R.id.infoPrivacyButton
        info.setText(res: R.string.minik_swish_info_privacy_button)
        info.setAllCaps(false)
        info.setTextColor(R.color.triple_shot_purple)
        homeContent.addView(info, ALinearLayout.LayoutParams(WRAP, px(44)))

        let homeContentParams = AConstraintLayout.LayoutParams(0, WRAP)
        homeContentParams.marginStart = px(20)
        homeContentParams.topMargin = px(6)
        homeContentParams.marginEnd = px(20)
        homeContentParams.endToEnd = PARENT
        homeContentParams.startToStart = PARENT
        homeContentParams.topToTop = PARENT
        homeContentParams.matchConstraintMaxWidth = px(520)
        column.addView(homeContent, homeContentParams)

        scroll.addView(column, AFrameLayout.LayoutParams(MATCH, WRAP))

        let scrollParams = AConstraintLayout.LayoutParams(0, 0)
        scrollParams.bottomToBottom = PARENT
        scrollParams.endToEnd = PARENT
        scrollParams.startToStart = PARENT
        scrollParams.topToBottom = R.id.homeFixedHeader
        root.addView(scroll, scrollParams)

        applySafeArea(root: root, header: header, scrollParams: scrollParams)

        return root
    }

    /// iOS-only (spec 18 §4.4.3 / §10.4 and §4.4.9; the other screens of the port keep the safe area the same way).
    /// Android 15+ draws this Home edge-to-edge and handles no insets: the title box starts 34 dp below the physical top,
    /// just under a 24-32 dp status bar, and the "More below" row ends at the physical bottom. An iPhone's status bar is
    /// 44-62 pt tall around the notch or the Dynamic Island (which would cover the top of the centred title) and its home
    /// indicator takes 34 pt, so the root's insets listener sets the header's top padding to
    /// `max(34 dp, status bar + 8 dp)` (Android's 34 dp wherever the status bar is at most 26 dp: iPhone SE, iPads) and
    /// ends the column above the home indicator: the bottom margin goes into the scroll view's ConstraintLayout params,
    /// which the FamilyMoreFrame that `FamilyMenu.section` wraps around the scroll view takes over (the same params
    /// object), so it applies before and after the wrap. The side insets (zero in the portrait Home) are kept clear on
    /// both sides. Unchanged, as on Android: the scenery, the decorations and the ball (the whole screen) and the
    /// keyboard, which is not avoided (Android 15+ edge-to-edge does not resize the Home for the IME either).
    private static func applySafeArea(root: AConstraintLayout, header: ALinearLayout,
                                      scrollParams: AConstraintLayout.LayoutParams) {
        let headerSide = px(20)
        let headerTop = px(34)
        let headerBottom = px(8)
        let statusGap = px(8)
        AViewCompat.setOnApplyWindowInsetsListener(root) { [weak header] v, insets in
            let safe = insets.getInsets(AWindowInsetsCompat.systemBars() | AWindowInsetsCompat.displayCutout())
            let side = max(safe.left, safe.right)
            header?.setPaddingRelative(headerSide + side, max(headerTop, safe.top + statusGap), headerSide + side,
                                       headerBottom)
            if scrollParams.leftMargin != side || scrollParams.rightMargin != side
                || scrollParams.bottomMargin != safe.bottom {
                scrollParams.leftMargin = side
                scrollParams.rightMargin = side
                scrollParams.bottomMargin = safe.bottom
                v.requestLayout()
            }
            return insets
        }
    }

    /// The old main card (removed by onViewCreated after its controls moved into the sections).
    private static func buildActionCard() -> AView {
        let MATCH = AViewGroup.LayoutParams.MATCH_PARENT
        let WRAP = AViewGroup.LayoutParams.WRAP_CONTENT

        // <com.google.android.material.card.MaterialCardView match x wrap marginTop 20dp cardBackgroundColor #EEFFFFFF
        //  cardCornerRadius 22dp cardElevation 0dp strokeColor #5532BFA8 strokeWidth 2dp>
        let card = ACardView()
        card.setCardBackgroundColor(AColor.parseColor("#EEFFFFFF"))
        card.radius = dimen(22)
        card.cardElevation = dimen(0)
        card.setStrokeColor(AColor.parseColor("#5532BFA8"))
        card.setStrokeWidth(px(2))

        //   <LinearLayout match x wrap vertical padding 16dp>
        let body = ALinearLayout()
        body.orientation = ALinearLayout.VERTICAL
        body.setPadding(px(16), px(16), px(16), px(16))

        //     <TextInputLayout match x wrap hint @string/triple_shot_name_hint>
        //       <TextInputEditText @+id/playerNameInput match x wrap imeOptions actionDone maxLength 18 singleLine>
        let nameLayout = ATextInputLayout()
        nameLayout.setHint(res: R.string.triple_shot_name_hint)
        let nameInput = ATextInputEditText()
        nameInput.viewId = R.id.playerNameInput
        nameInput.setImeOptions(AEditorInfo.IME_ACTION_DONE)
        nameInput.applyXmlSingleLine(true)
        nameInput.setFilters([ALengthFilter(18)])
        nameLayout.addView(nameInput, ALinearLayout.LayoutParams(MATCH, WRAP))
        body.addView(nameLayout, ALinearLayout.LayoutParams(MATCH, WRAP))

        //     <LinearLayout match x wrap marginTop 12dp horizontal>
        let statsTopicsRow = ALinearLayout()
        statsTopicsRow.orientation = ALinearLayout.HORIZONTAL

        //       <TripleShotButton @+id/statsButton style OutlinedButton 0dp x 52dp weight 0.38 marginEnd 5dp
        //        @string/minik_swish_stats_button textAllCaps false 14sp cornerRadius 16dp strokeColor purple>
        let stats = TripleShotButton(style: .OUTLINED)
        stats.viewId = R.id.statsButton
        stats.setText(res: R.string.minik_swish_stats_button)
        stats.setAllCaps(false)
        stats.applyXmlTextSize(14)
        stats.setCornerRadius(px(16))
        stats.setStrokeColor(AColorStateList.valueOf(R.color.triple_shot_purple))
        let statsParams = ALinearLayout.LayoutParams(0, px(52), 0.38)
        statsParams.marginEnd = px(5)
        statsTopicsRow.addView(stats, statsParams)

        //       <TripleShotButton @+id/topicButton style OutlinedButton 0dp x 52dp weight 0.62 marginStart 5dp
        //        maxLines 2 @string/minik_swish_topics_all textAllCaps false 14sp cornerRadius 16dp
        //        icon @android:drawable/ic_menu_manage iconGravity textStart strokeColor green>
        let topic = TripleShotButton(style: .OUTLINED)
        topic.viewId = R.id.topicButton
        topic.setMaxLines(2)
        topic.setText(res: R.string.minik_swish_topics_all)
        topic.setAllCaps(false)
        topic.applyXmlTextSize(14)
        topic.setCornerRadius(px(16))
        topic.setIcon(icMenuManage())
        topic.setIconGravity(AButton.ICON_GRAVITY_TEXT_START)
        topic.setStrokeColor(AColorStateList.valueOf(R.color.triple_shot_green))
        let topicParams = ALinearLayout.LayoutParams(0, px(52), 0.62)
        topicParams.marginStart = px(5)
        statsTopicsRow.addView(topic, topicParams)

        let rowParams = ALinearLayout.LayoutParams(MATCH, WRAP)
        rowParams.topMargin = px(12)
        body.addView(statsTopicsRow, rowParams)

        //     <TripleShotButton @+id/practiceButton match x 54dp marginTop 12dp @string/minik_swish_practice
        //      textAllCaps false 18sp backgroundTint green cornerRadius 18dp>
        let practice = TripleShotButton()
        practice.viewId = R.id.practiceButton
        practice.setText(res: R.string.minik_swish_practice)
        practice.setAllCaps(false)
        practice.applyXmlTextSize(18)
        practice.setBackgroundTintList(AColorStateList.valueOf(R.color.triple_shot_green))
        practice.setCornerRadius(px(18))
        let practiceParams = ALinearLayout.LayoutParams(MATCH, px(54))
        practiceParams.topMargin = px(12)
        body.addView(practice, practiceParams)

        //     <TripleShotButton @+id/cloudPracticeButton style OutlinedButton match x 54dp marginTop 10dp
        //      @string/qe_cloud_practice textAllCaps false 18sp visibility gone cornerRadius 18dp strokeColor green>
        let cloudPractice = TripleShotButton(style: .OUTLINED)
        cloudPractice.viewId = R.id.cloudPracticeButton
        cloudPractice.setText(res: R.string.qe_cloud_practice)
        cloudPractice.setAllCaps(false)
        cloudPractice.applyXmlTextSize(18)
        cloudPractice.visibility = AView.GONE
        cloudPractice.setCornerRadius(px(18))
        cloudPractice.setStrokeColor(AColorStateList.valueOf(R.color.triple_shot_green))
        let cloudPracticeParams = ALinearLayout.LayoutParams(MATCH, px(54))
        cloudPracticeParams.topMargin = px(10)
        body.addView(cloudPractice, cloudPracticeParams)

        //     <TripleShotButton @+id/botButton style OutlinedButton match x 50dp marginTop 10dp
        //      @string/minik_swish_bot_title textAllCaps false cornerRadius 18dp strokeColor gold>
        let bot = TripleShotButton(style: .OUTLINED)
        bot.viewId = R.id.botButton
        bot.setText(res: R.string.minik_swish_bot_title)
        bot.setAllCaps(false)
        bot.setCornerRadius(px(18))
        bot.setStrokeColor(AColorStateList.valueOf(R.color.triple_shot_gold))
        let botParams = ALinearLayout.LayoutParams(MATCH, px(50))
        botParams.topMargin = px(10)
        body.addView(bot, botParams)

        //     <View match x 1dp marginTop 14dp marginBottom 12dp background #22324552>
        let divider = AView()
        divider.setBackgroundColor(AColor.parseColor("#22324552"))
        let dividerParams = ALinearLayout.LayoutParams(MATCH, px(1))
        dividerParams.topMargin = px(14)
        dividerParams.bottomMargin = px(12)
        body.addView(divider, dividerParams)

        //     <TripleShotButton @+id/createRoomButton style OutlinedButton match x 50dp @string/triple_shot_create_room
        //      textAllCaps false cornerRadius 18dp strokeColor green>
        let createRoom = TripleShotButton(style: .OUTLINED)
        createRoom.viewId = R.id.createRoomButton
        createRoom.setText(res: R.string.triple_shot_create_room)
        createRoom.setAllCaps(false)
        createRoom.setCornerRadius(px(18))
        createRoom.setStrokeColor(AColorStateList.valueOf(R.color.triple_shot_green))
        body.addView(createRoom, ALinearLayout.LayoutParams(MATCH, px(50)))

        //     <LinearLayout match x wrap marginTop 8dp gravity center_vertical horizontal>
        let joinRow = ALinearLayout()
        joinRow.gravity = AGravity.CENTER_VERTICAL
        joinRow.orientation = ALinearLayout.HORIZONTAL

        //       <TextInputLayout 0dp x wrap weight 1 hint @string/triple_shot_room_code_hint>
        //         <TextInputEditText @+id/roomCodeInput match x wrap inputType textCapCharacters maxLength 6 singleLine>
        let codeLayout = ATextInputLayout()
        codeLayout.setHint(res: R.string.triple_shot_room_code_hint)
        let codeInput = ATextInputEditText()
        codeInput.viewId = R.id.roomCodeInput
        codeInput.setInputType(AInputType.TYPE_CLASS_TEXT | AInputType.TYPE_TEXT_FLAG_CAP_CHARACTERS)
        codeInput.applyXmlSingleLine(true)
        codeInput.setFilters([ALengthFilter(6)])
        codeLayout.addView(codeInput, ALinearLayout.LayoutParams(MATCH, WRAP))
        joinRow.addView(codeLayout, ALinearLayout.LayoutParams(0, WRAP, 1))

        //       <TripleShotButton @+id/joinRoomButton wrap x 52dp marginStart 8dp @string/triple_shot_join_room
        //        textAllCaps false backgroundTint blue cornerRadius 16dp>
        let join = TripleShotButton()
        join.viewId = R.id.joinRoomButton
        join.setText(res: R.string.triple_shot_join_room)
        join.setAllCaps(false)
        join.setBackgroundTintList(AColorStateList.valueOf(R.color.triple_shot_blue))
        join.setCornerRadius(px(16))
        let joinParams = ALinearLayout.LayoutParams(WRAP, px(52))
        joinParams.marginStart = px(8)
        joinRow.addView(join, joinParams)

        let joinRowParams = ALinearLayout.LayoutParams(MATCH, WRAP)
        joinRowParams.topMargin = px(8)
        body.addView(joinRow, joinRowParams)

        //     <TripleShotButton @+id/leaderboardButton style OutlinedButton match x 50dp marginTop 10dp
        //      @string/triple_shot_leaderboard textAllCaps false cornerRadius 18dp strokeColor purple>
        let leaderboard = TripleShotButton(style: .OUTLINED)
        leaderboard.viewId = R.id.leaderboardButton
        leaderboard.setText(res: R.string.triple_shot_leaderboard)
        leaderboard.setAllCaps(false)
        leaderboard.setCornerRadius(px(18))
        leaderboard.setStrokeColor(AColorStateList.valueOf(R.color.triple_shot_purple))
        let leaderboardParams = ALinearLayout.LayoutParams(MATCH, px(50))
        leaderboardParams.topMargin = px(10)
        body.addView(leaderboard, leaderboardParams)

        card.addView(body, AFrameLayout.LayoutParams(MATCH, WRAP))
        return card
    }

    /// The joiner's lobby panel (GONE until a room is joined).
    private static func buildRoomPanel() -> AView {
        let MATCH = AViewGroup.LayoutParams.MATCH_PARENT
        let WRAP = AViewGroup.LayoutParams.WRAP_CONTENT

        // <com.google.android.material.card.MaterialCardView @+id/roomPanel match x wrap marginTop 12dp visibility gone
        //  cardBackgroundColor #F4FFFFFF cardCornerRadius 20dp cardElevation 0dp strokeColor gold strokeWidth 2dp>
        let panel = ACardView()
        panel.viewId = R.id.roomPanel
        panel.visibility = AView.GONE
        panel.setCardBackgroundColor(AColor.parseColor("#F4FFFFFF"))
        panel.radius = dimen(20)
        panel.cardElevation = dimen(0)
        panel.setStrokeColor(R.color.triple_shot_gold)
        panel.setStrokeWidth(px(2))

        //   <LinearLayout match x wrap gravity center vertical padding 14dp>
        let body = ALinearLayout()
        body.gravity = AGravity.CENTER
        body.orientation = ALinearLayout.VERTICAL
        body.setPadding(px(14), px(14), px(14), px(14))

        //     <TextView @+id/roomStatusText match x wrap gravity center textColor ink 17sp bold>
        let status = ATextView()
        status.viewId = R.id.roomStatusText
        status.setGravity(AGravity.CENTER)
        status.setTextColor(R.color.triple_shot_ink)
        status.applyXmlTextSize(17)
        bold(status)
        body.addView(status, ALinearLayout.LayoutParams(MATCH, WRAP))

        //     <TextView @+id/roomPlayersText match x wrap marginTop 8dp gravity center textColor green 14sp>
        let players = ATextView()
        players.viewId = R.id.roomPlayersText
        players.setGravity(AGravity.CENTER)
        players.setTextColor(R.color.triple_shot_green)
        players.applyXmlTextSize(14)
        let playersParams = ALinearLayout.LayoutParams(MATCH, WRAP)
        playersParams.topMargin = px(8)
        body.addView(players, playersParams)

        //     <TripleShotButton @+id/startRoomButton match x 48dp marginTop 10dp @string/triple_shot_start_room
        //      textAllCaps false visibility gone backgroundTint gold cornerRadius 16dp>
        let start = TripleShotButton()
        start.viewId = R.id.startRoomButton
        start.setText(res: R.string.triple_shot_start_room)
        start.setAllCaps(false)
        start.visibility = AView.GONE
        start.setBackgroundTintList(AColorStateList.valueOf(R.color.triple_shot_gold))
        start.setCornerRadius(px(16))
        let startParams = ALinearLayout.LayoutParams(MATCH, px(48))
        startParams.topMargin = px(10)
        body.addView(start, startParams)

        // iOS-only (DESIGN 2.8 / 12.3, spec 18 §10.1): "Leave room", the on-screen stand-in for Android's system Back in a
        // joined lobby. Same geometry as the start button above (48 dp, 10 dp below), the family's pale pink "cancel"
        // face (#FFD4E6, FamilySkyUi converts it like any tinted button; TripleShotButton gives it #23384D lettering).
        // Its text follows the Home's own rule for hard-coded copy (Hebrew only for he/iw).
        let language = AContextResources.shared.configuration.locales[0].language
        let leave = TripleShotButton()
        leave.viewId = TripleShotHomeFragment.IOS_LEAVE_ROOM_BUTTON_ID
        leave.text = language == "he" || language == "iw" ? "יציאה מהחדר" : "Leave room"
        leave.setAllCaps(false)
        leave.setBackgroundTintList(AColorStateList.valueOf(argbInt(0xffffd4e6)))
        leave.setCornerRadius(px(16))
        let leaveParams = ALinearLayout.LayoutParams(MATCH, px(48))
        leaveParams.topMargin = px(10)
        body.addView(leave, leaveParams)

        panel.addView(body, AFrameLayout.LayoutParams(MATCH, WRAP))
        return panel
    }

    /// `@android:drawable/ic_menu_manage`, the XML `app:icon` of topicButton. It is a framework asset that the app
    /// does not ship and whose look differs per device (spec 18 §10.7); iOS draws the SF Symbol "wrench.fill" (the
    /// spec's suggested stand-in) into a bitmap of the framework icon's size (32 dp) with the asset's 60 % alpha.
    /// MaterialButton tints it (SRC_IN) with the OutlinedButton icon tint (colorPrimary #087E70), which gives the
    /// measured #087E70 at 60 % over the face. nil when the symbol is unavailable (no icon, like a missing resource).
    static func icMenuManage() -> ADrawable? {
        let side = px(32)
        guard side > 0 else { return nil }
        let configuration = UIImage.SymbolConfiguration(pointSize: CGFloat(side) * 0.6, weight: .regular)
        guard let symbol = UIImage(systemName: "wrench.fill", withConfiguration: configuration)?
            .withTintColor(.black, renderingMode: .alwaysOriginal)
        else { return nil }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        let image = renderer.image { _ in
            let box = CGFloat(side) * 0.75
            let symbolSize = symbol.size
            guard symbolSize.width > 0, symbolSize.height > 0 else { return }
            let k = min(box / symbolSize.width, box / symbolSize.height)
            let w = symbolSize.width * k
            let h = symbolSize.height * k
            symbol.draw(in: CGRect(x: (CGFloat(side) - w) / 2, y: (CGFloat(side) - h) / 2, width: w, height: h),
                        blendMode: .normal, alpha: 0.6)
        }
        guard let cgImage = image.cgImage else { return nil }
        return ABitmapDrawable(ABitmap(cgImage: cgImage))
    }
}
