import Foundation

/// Port of `ui/TripleShotHostFragment.kt` (Android 6c38131), statement by statement (spec 18 §3.2, §4.2).
///
/// The navigator: one FrameLayout `tripleShotChildContainer` (its own view, `R.layout.fragment_triple_shot_host`, built
/// in code by `TripleShotHostLayout`) whose child FragmentManager swaps Home, Live setup, the three game screens,
/// League, Progress and Leaderboard, with Android's back stack ("live_setup", "game", "progress", "leaderboard";
/// Home and League are roots). It owns the activity's requested orientation for every screen: menus wait for the
/// portrait configuration (at most 12 retries 35 ms apart) before they are committed, 1v1 waits for its own
/// orientation the same way, team matches rotate with the sensor (SENSOR, `AActivityInfo` maps it to the iOS mask;
/// the iOS rotation lock is honoured, spec 18 §4.2.4).
///
/// Swift API: the Kotlin parameter names are the labels (DESIGN 2.1). The delayed retries capture the fragment
/// strongly for their 35 ms, like the Kotlin lambdas; each one re-checks `isAdded` first, as on Android.
/// `onDeviceConfigurationChanged` keeps its Kotlin role (forwarding in-process rotations to a visible team match).
final class TripleShotHostFragment: AFragment {

    /// Registers the Swift builder of `R.layout.fragment_triple_shot_host` once (ALayoutInflater).
    private static let layoutRegistration: Void = {
        ALayoutInflater.register(R.layout.fragment_triple_shot_host) { _ in
            TripleShotHostLayout.build()
        }
    }()

    /// Kotlin `TripleShotHostFragment : Fragment(R.layout.fragment_triple_shot_host)`.
    override init() {
        super.init(contentLayoutId: R.layout.fragment_triple_shot_host)
        _ = TripleShotHostFragment.layoutRegistration
    }

    override func onViewCreated(_ view: AView, _ savedInstanceState: ABundle?) {
        super.onViewCreated(view, savedInstanceState)
        if savedInstanceState == nil { showHome() }
    }

    func showHome() {
        BasketballSoundscape.scene(activity: requireActivity(), value: .MENU)
        runWhenPortraitReady {
            self.childFragmentManager.beginTransaction()
                .replace(R.id.tripleShotChildContainer, TripleShotHomeFragment())
                .commit()
            _ = self.childFragmentManager.executePendingTransactions()
        }
    }

    func showLiveSetup(
        playerName: String,
        selectedCategories: KLinkedSet<QuestionCategory>,
        playerCharacterId: String
    ) {
        runWhenPortraitReady {
            self.childFragmentManager.beginTransaction()
                .replace(
                    R.id.tripleShotChildContainer,
                    TripleShotLiveSetupFragment.newInstance(
                        playerName: playerName,
                        selectedCategories: selectedCategories,
                        playerCharacterId: playerCharacterId
                    )
                )
                .addToBackStack("live_setup")
                .commit()
        }
    }

    func startGame(config: TripleShotGameConfig) {
        BasketballSoundscape.scene(activity: requireActivity(), value: .COURT)
        let destination: AFragment
        switch config.gameType {
        case GameType.ONE_ON_ONE: destination = TripleShotOneOnOneFragment.newInstance(config: config)
        case GameType.TEAM_MATCH: destination = TripleShotTeamMatchFragment.newInstance(config: config)
        default: destination = TripleShotGameFragment.newInstance(config: config)
        }

        func commitDestination() {
            if !isAdded { return }
            childFragmentManager.beginTransaction()
                .replace(R.id.tripleShotChildContainer, destination)
                .addToBackStack("game")
                .commit()
            _ = childFragmentManager.executePendingTransactions()
        }

        switch config.gameType {
        case GameType.TEAM_MATCH:
            // Team mode owns a source-space state model and can reflow the same live match when
            // the sensor rotates. No Activity/Fragment recreation is needed.
            if requireActivity().requestedOrientation != AActivityInfo.SCREEN_ORIENTATION_SENSOR {
                requireActivity().requestedOrientation = AActivityInfo.SCREEN_ORIENTATION_SENSOR
            }
            commitDestination()

        case GameType.ONE_ON_ONE:
            /*
             * 1v1 deliberately keeps its mature orientation-specific XML during this milestone.
             * There is no setup choice anymore: we detect how the device is physically held,
             * rotate FIRST, and only then create the Fragment so Android inflates the correct
             * layout/layout-land resource. Keeping it locked during that match prevents a
             * mid-possession reset of the mature 1v1 state machine.
             */
            let targetLandscape = config.gameOrientation == TripleShotGameOrientation.LANDSCAPE
            let requested =
                targetLandscape ? AActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
                : AActivityInfo.SCREEN_ORIENTATION_PORTRAIT
            if requireActivity().requestedOrientation != requested {
                requireActivity().requestedOrientation = requested
            }

            func commitWhenConfigurationMatches(attempt: Int = 0) {
                if !isAdded { return }
                let isLandscape =
                    resources.configuration.orientation == AConfiguration.ORIENTATION_LANDSCAPE
                if isLandscape == targetLandscape || attempt >= 12 {
                    commitDestination()
                } else {
                    requireActivity().window.decorView.postDelayed(
                        { commitWhenConfigurationMatches(attempt: attempt + 1) },
                        35
                    )
                }
            }
            commitWhenConfigurationMatches()

        default:
            if requireActivity().requestedOrientation != AActivityInfo.SCREEN_ORIENTATION_PORTRAIT {
                requireActivity().requestedOrientation = AActivityInfo.SCREEN_ORIENTATION_PORTRAIT
            }
            commitDestination()
        }
    }

    func onDeviceConfigurationChanged(newConfig: AConfiguration) {
        let active = childFragmentManager.findFragmentById(R.id.tripleShotChildContainer)
        if let active = active as? TripleShotTeamMatchFragment {
            active.onDeviceOrientationChanged(orientation: newConfig.orientation)
        }
    }

    func showLeague() {
        BasketballSoundscape.scene(activity: requireActivity(), value: .MENU)
        childFragmentManager.popBackStack(nil, AFragmentManager.POP_BACK_STACK_INCLUSIVE)
        runWhenPortraitReady {
            self.childFragmentManager.beginTransaction()
                .replace(R.id.tripleShotChildContainer, TripleShotLeagueFragment())
                .commit()
        }
    }

    func showProgress() {
        BasketballSoundscape.scene(activity: requireActivity(), value: .MENU)
        runWhenPortraitReady {
            self.childFragmentManager.beginTransaction()
                .replace(R.id.tripleShotChildContainer, TripleShotProgressFragment())
                .addToBackStack("progress")
                .commit()
        }
    }

    func showLeaderboard() {
        BasketballSoundscape.scene(activity: requireActivity(), value: .MENU)
        runWhenPortraitReady {
            self.childFragmentManager.beginTransaction()
                .replace(R.id.tripleShotChildContainer, TripleShotLeaderboardFragment())
                .addToBackStack("leaderboard")
                .commit()
        }
    }

    private func runWhenPortraitReady(attempt: Int = 0, action: @escaping () -> Void) {
        if !isAdded { return }
        restorePortraitShell()
        let portrait = resources.configuration.orientation != AConfiguration.ORIENTATION_LANDSCAPE
        if portrait || attempt >= 12 {
            action()
        } else {
            requireActivity().window.decorView.postDelayed(
                { self.runWhenPortraitReady(attempt: attempt + 1, action: action) },
                35
            )
        }
    }

    private func restorePortraitShell() {
        if !isAdded { return }
        if requireActivity().requestedOrientation != AActivityInfo.SCREEN_ORIENTATION_PORTRAIT {
            requireActivity().requestedOrientation = AActivityInfo.SCREEN_ORIENTATION_PORTRAIT
        }
    }

    func backToHome() {
        childFragmentManager.popBackStack(
            nil,
            AFragmentManager.POP_BACK_STACK_INCLUSIVE
        )
        showHome()
    }
}

/// `res/layout/fragment_triple_shot_host.xml` built in code (same id, attributes and params as the XML).
enum TripleShotHostLayout {
    static func build() -> AView {
        // <FrameLayout @+id/tripleShotChildContainer match_parent x match_parent />
        let container = AFrameLayout()
        container.viewId = R.id.tripleShotChildContainer
        container.layoutParams = AViewGroup.LayoutParams(
            AViewGroup.LayoutParams.MATCH_PARENT,
            AViewGroup.LayoutParams.MATCH_PARENT
        )
        return container
    }
}
