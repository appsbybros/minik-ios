import Foundation

/// Port of `ui/TripleShotLeaderboardFragment.kt` (Android 6c38131), statement by statement (spec 25 §4.2,
/// §7.2; repository spec 05 §4.11), plus `res/layout/fragment_triple_shot_leaderboard.xml` built in code
/// (`TripleShotLeaderboardLayout`, registered for `R.layout.fragment_triple_shot_leaderboard`).
///
/// The global top 20 by best score (tab 0) or by best shooting streak (tab 1). The tab labels, the empty text and the
/// connection toast follow the device language (Hebrew for he/iw, else English), as on Android; the back text and the
/// load-error fallback stay hard-coded Hebrew. A response is used only while the view that asked for it is still the
/// fragment's view; otherwise, as on Android, the last response to arrive wins with its own captured mode, and a
/// failed load keeps the old rows under the "no results" text.
///
/// Swift notes: argument labels are the Kotlin parameter names (DESIGN 2.1); units are Android pixels (DESIGN 2.5).
/// The tab listener, the back button and the Firebase callbacks capture `self` weakly and re-check the fragment's view
/// like the Kotlin lambdas. `error.message` is the AndroidKit Throwable message (`AFirebaseException.message`).
///
/// Back: Android registers no OnBackPressedCallback here (system Back sends the app to the background, spec 25 §8.5,
/// a quirk the spec says not to port); iOS has no system Back, so the screen's own X (`leaderboardBackButton`,
/// converted by TripleShotControls) is the exit, as on Android. No iOS-only control is added.
///
/// Insets: as on Android, `applyGameplayInsets` pads the whole layout root by the system-bar and display-cutout insets
/// (white status-bar icons, then light ones: the Kotlin sets isAppearanceLightStatusBars = true right after).
final class TripleShotLeaderboardFragment: AFragment {

    private lazy var firebase: TripleShotFirebaseRepository = TripleShotFirebaseRepository()
    private let adapter = TripleShotLeaderboardAdapter()
    private var progress: AProgressBar!
    private var empty: ATextView!

    /// Registers the Swift builder of `R.layout.fragment_triple_shot_leaderboard` once (ALayoutInflater).
    private static let layoutRegistration: Void = {
        ALayoutInflater.register(R.layout.fragment_triple_shot_leaderboard) { _ in
            TripleShotLeaderboardLayout.build()
        }
    }()

    /// Kotlin `TripleShotLeaderboardFragment : Fragment(R.layout.fragment_triple_shot_leaderboard)`.
    override init() {
        super.init(contentLayoutId: R.layout.fragment_triple_shot_leaderboard)
        _ = TripleShotLeaderboardFragment.layoutRegistration
    }

    override func onViewCreated(_ view: AView, _ savedInstanceState: ABundle?) {
        super.onViewCreated(view, savedInstanceState)

        applyGameplayInsets(root: view, window: requireActivity().window)
        AWindowCompat.getInsetsController(requireActivity().window, view).isAppearanceLightStatusBars = true
        let he = ["he", "iw"].contains(resources.configuration.locales[0].language)
        progress = TripleShotLeaderboardFragment.leaderboardRequireView(view, R.id.leaderboardProgress, AProgressBar.self)
        empty = TripleShotLeaderboardFragment.leaderboardRequireView(view, R.id.leaderboardEmpty, ATextView.self)
        empty.text = he ? "אין עדיין תוצאות" : "No scores yet"

        let list = TripleShotLeaderboardFragment.leaderboardRequireView(view, R.id.leaderboardList, ARecyclerView.self)
        list.layoutManager = ALinearLayoutManager(requireContext())
        list.adapter = adapter

        let tabs = TripleShotLeaderboardFragment.leaderboardRequireView(view, R.id.leaderboardTabs, ATabLayout.self)
        tabs.setBackgroundColor(AColor.TRANSPARENT)
        tabs.setTabTextColors(argbInt(0xffff5b67), argbInt(0xffff5b67))
        tabs.setSelectedTabIndicatorColor(argbInt(0xffff5b67))
        tabs.addTab(tabs.newTab().setText(he ? "קליעות" : "Scores"))
        tabs.addTab(tabs.newTab().setText(he ? "רצף" : "Streak"))
        for i in kuntil(0, tabs.tabCount) {
            let custom = ATextView()
            custom.text = tabs.getTabAt(i)?.text ?? ""; custom.textSize = 18; custom.setTextColor(argbInt(0xffff5b67))
            custom.gravity = AGravity.CENTER
            custom.setTypeface(custom.typeface, ATypeface.BOLD); custom.minHeight = (48 * resources.displayMetrics.density).toInt()
            tabs.getTabAt(i)?.customView = custom
        }
        tabs.addOnTabSelectedListener(
            ASimpleOnTabSelectedListener(
                onTabSelected: { [weak self] tab in
                    self?.load(
                        mode: tab.position == 0
                            ? TripleShotLeaderboardAdapter.SortMode.SCORE
                            : TripleShotLeaderboardAdapter.SortMode.SHOOTING_STREAK
                    )
                },
                onTabUnselected: { _ in },
                onTabReselected: { _ in }
            )
        )

        TripleShotLeaderboardFragment.leaderboardRequireView(view, R.id.leaderboardBackButton, AButton.self)
            .setOnClickListener { [weak self] _ in
                (self?.parentFragment as? TripleShotHostFragment)?.backToHome()
            }

        firebase.ensureAnonymousAuth { [weak self] result in
            guard let self, self.view === view else { return }
            switch result {
            case .success:
                load(mode: TripleShotLeaderboardAdapter.SortMode.SCORE)
            case .failure:
                progress.visibility = AView.GONE
                empty.visibility = AView.VISIBLE
                AToast.makeText(requireContext(), he ? "לא ניתן להתחבר כרגע. נסו שוב מאוחר יותר." : "Could not connect. Please try again later.", AToast.LENGTH_LONG).show()
            }
        }
    }

    private func load(mode: TripleShotLeaderboardAdapter.SortMode) {
        progress.visibility = AView.VISIBLE
        empty.visibility = AView.GONE
        let activeView = view
        let consume: (Result<[LeaderboardEntry], Error>) -> Void = { [weak self] result in
            guard let self else { return }
            if isAdded && view === activeView {
                progress.visibility = AView.GONE
                switch result {
                case .success(let items):
                    adapter.submit(newItems: items, mode: mode)
                    empty.visibility = items.isEmpty ? AView.VISIBLE : AView.GONE
                case .failure(let error):
                    empty.visibility = AView.VISIBLE
                    AToast.makeText(
                        requireContext(),
                        leaderboardThrowableMessage(error) ?? "שגיאת טעינה",
                        AToast.LENGTH_LONG
                    ).show()
                }
            }
        }

        switch mode {
        case TripleShotLeaderboardAdapter.SortMode.SCORE:
            firebase.loadTopByScore(callback: consume)
        case TripleShotLeaderboardAdapter.SortMode.SHOOTING_STREAK:
            firebase.loadTopByShootingStreak(callback: consume)
        }
    }

    /// `view.findViewById(id)` used as a non-null value (crashes when missing, like Kotlin's check).
    private static func leaderboardRequireView<T: AView>(_ root: AView, _ id: String, _ type: T.Type) -> T {
        let found: T? = root.findViewById(id)
        return found!
    }
}

/// Kotlin `error.message` of a repository / Firebase failure: AndroidKit's Throwable is AFirebaseException (nil
/// message only for an unconfigured Firebase); any other error gives its LocalizedError description, like
/// TripleShotHomeFragment's helper.
private func leaderboardThrowableMessage(_ error: Error) -> String? {
    if let exception = error as? AFirebaseException { return exception.message }
    return (error as? LocalizedError)?.errorDescription
}

// MARK: - res/layout/fragment_triple_shot_leaderboard.xml

/// The view tree of `res/layout/fragment_triple_shot_leaderboard.xml`, built in code with the XML's ids, attributes
/// and constraints in XML order (DESIGN 2.8). Sizes, margins, paddings, text sizes and the button corner radius are
/// pixel sizes (`getDimensionPixelSize`, rounded). The back button is a `Widget.MaterialComponents.Button.OutlinedButton`
/// TripleShotButton with the text "חזרה"; the app-wide TripleShotControls turns it into the red close X (its parent is a
/// ConstraintLayout, so it stays at its constraints, top 19 dp / end 16 dp) with "חזרה" as its accessibility label.
///
enum TripleShotLeaderboardLayout {

    /// `getDimensionPixelSize` of an XML `Ndp`.
    static func px(_ dp: Float) -> Int {
        ATypedValue.toDimensionPixelSize(ATypedValue.COMPLEX_UNIT_DIP, dp)
    }

    /// `android:textStyle="bold"` (TextView.setTypefaceFromAttrs: the family's face, then setTypeface(tf, BOLD)).
    static func bold(_ textView: ATextView) {
        textView.setTypeface(textView.typeface, ATypeface.BOLD)
    }

    static func build() -> AView {
        let MATCH = AViewGroup.LayoutParams.MATCH_PARENT
        let WRAP = AViewGroup.LayoutParams.WRAP_CONTENT
        let PARENT = AConstraintLayout.LayoutParams.PARENT_ID

        // <androidx.constraintlayout.widget.ConstraintLayout match_parent x match_parent background #FFFDF5>
        let root = AConstraintLayout()
        root.layoutParams = AViewGroup.LayoutParams(MATCH, MATCH)
        root.setBackgroundColor(AColor.parseColor("#FFFDF5"))

        // <ImageView 0dp x 0dp alpha 0.24 scaleType centerCrop src @drawable/triple_shot_court_background,
        //  constrained to the four parent edges>
        let background = AImageView()
        background.setAlpha(Float(0.24))
        background.scaleType = AImageView.ScaleType.CENTER_CROP
        background.setImageResource(R.drawable.triple_shot_court_background)
        let backgroundParams = AConstraintLayout.LayoutParams(0, 0)
        backgroundParams.bottomToBottom = PARENT
        backgroundParams.endToEnd = PARENT
        backgroundParams.startToStart = PARENT
        backgroundParams.topToTop = PARENT
        root.addView(background, backgroundParams)

        // <TextView @+id/leaderboardTitle 0dp x wrap marginStart 18dp marginTop 12dp marginEnd 18dp gravity center
        //  text @string/triple_shot_leaderboard @color/triple_shot_ink 28sp bold, start/end to parent, top to bottom of
        //  leaderboardBackButton>
        let title = ATextView()
        title.viewId = R.id.leaderboardTitle
        title.gravity = AGravity.CENTER
        title.setText(res: R.string.triple_shot_leaderboard)
        title.setTextColor(R.color.triple_shot_ink)
        title.applyXmlTextSize(28)
        bold(title)
        let titleParams = AConstraintLayout.LayoutParams(0, WRAP)
        titleParams.marginStart = px(18)
        titleParams.topMargin = px(12)
        titleParams.marginEnd = px(18)
        titleParams.endToEnd = PARENT
        titleParams.startToStart = PARENT
        titleParams.topToBottom = R.id.leaderboardBackButton
        root.addView(title, titleParams)

        // <com.google.android.material.tabs.TabLayout @+id/leaderboardTabs 0dp x wrap marginStart 16dp marginTop 12dp
        //  marginEnd 16dp, start/end to parent, top to bottom of leaderboardTitle, background @android:color/transparent,
        //  tabIndicatorColor #FF5B67, tabSelectedTextColor @color/triple_shot_green, tabTextColor @color/triple_shot_ink>
        let tabs = ATabLayout()
        tabs.viewId = R.id.leaderboardTabs
        tabs.setBackgroundColor(AColor.TRANSPARENT)
        tabs.setSelectedTabIndicatorColor(AColor.parseColor("#FF5B67"))
        // TabLayout(context, attrs): tabTextColor, then tabSelectedTextColor merged into it.
        tabs.setTabTextColors(R.color.triple_shot_ink, R.color.triple_shot_green)
        let tabsParams = AConstraintLayout.LayoutParams(0, WRAP)
        tabsParams.marginStart = px(16)
        tabsParams.topMargin = px(12)
        tabsParams.marginEnd = px(16)
        tabsParams.endToEnd = PARENT
        tabsParams.startToStart = PARENT
        tabsParams.topToBottom = R.id.leaderboardTitle
        root.addView(tabs, tabsParams)

        // <androidx.recyclerview.widget.RecyclerView @+id/leaderboardList 0dp x 0dp marginStart 12dp marginTop 8dp
        //  marginEnd 12dp clipToPadding false paddingBottom 12dp, bottom/start/end to parent, top to bottom of
        //  leaderboardTabs>
        let list = ARecyclerView()
        list.viewId = R.id.leaderboardList
        list.clipToPadding = false
        list.setPadding(0, 0, 0, px(12))
        let listParams = AConstraintLayout.LayoutParams(0, 0)
        listParams.marginStart = px(12)
        listParams.topMargin = px(8)
        listParams.marginEnd = px(12)
        listParams.bottomToBottom = PARENT
        listParams.endToEnd = PARENT
        listParams.startToStart = PARENT
        listParams.topToBottom = R.id.leaderboardTabs
        root.addView(list, listParams)

        // <ProgressBar @+id/leaderboardProgress wrap x wrap, constrained to the four parent edges>
        let progress = AProgressBar()
        progress.viewId = R.id.leaderboardProgress
        let progressParams = AConstraintLayout.LayoutParams(WRAP, WRAP)
        progressParams.bottomToBottom = PARENT
        progressParams.endToEnd = PARENT
        progressParams.startToStart = PARENT
        progressParams.topToTop = PARENT
        root.addView(progress, progressParams)

        // <TextView @+id/leaderboardEmpty wrap x wrap text "אין עדיין תוצאות" @color/triple_shot_ink 18sp gone,
        //  constrained to the four parent edges>
        let empty = ATextView()
        empty.viewId = R.id.leaderboardEmpty
        empty.setText("אין עדיין תוצאות")
        empty.setTextColor(R.color.triple_shot_ink)
        empty.applyXmlTextSize(18)
        empty.visibility = AView.GONE
        let emptyParams = AConstraintLayout.LayoutParams(WRAP, WRAP)
        emptyParams.bottomToBottom = PARENT
        emptyParams.endToEnd = PARENT
        emptyParams.startToStart = PARENT
        emptyParams.topToTop = PARENT
        root.addView(empty, emptyParams)

        // <TripleShotButton @+id/leaderboardBackButton style OutlinedButton 52dp x 52dp marginStart 16dp marginEnd 16dp
        //  marginTop 19dp text "חזרה" textAllCaps false cornerRadius 17dp, top to parent, end to parent,
        //  strokeColor @color/triple_shot_green>
        let back = TripleShotButton(style: .OUTLINED)
        back.viewId = R.id.leaderboardBackButton
        back.setText("חזרה")
        back.setAllCaps(false)
        back.setCornerRadius(px(17))
        back.setStrokeColor(AColorStateList.valueOf(R.color.triple_shot_green))
        let backParams = AConstraintLayout.LayoutParams(px(52), px(52))
        backParams.marginStart = px(16)
        backParams.marginEnd = px(16)
        backParams.topMargin = px(19)
        backParams.topToTop = PARENT
        backParams.endToEnd = PARENT
        root.addView(back, backParams)

        return root
    }
}
