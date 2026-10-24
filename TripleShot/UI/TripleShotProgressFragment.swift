import Foundation

// Port of ui/TripleShotProgressFragment.kt (Android 6c38131), statement by statement (spec 25 sections 4.1,
// 6.1, 7.1, 8.1-8.8). res/layout/fragment_triple_shot_progress.xml is built in code by
// `TripleShotProgressFragment.Layout` (same tree, ids, attributes and layout params) and registered with
// ALayoutInflater, so `Fragment(R.layout.fragment_triple_shot_progress)` inflates it like Android.
//
// The effective look comes from the restylers the hosting activity installs on its decor view (TripleShotDemoActivity:
// FamilySkyUi.watch + FamilyFormStyle, then TripleShotControls.watch), exactly as on Android: the "‹" back button
// becomes the triple_close icon in a new END-aligned row at the top of progressShell (the 44 dp spacer View is
// removed), the tab buttons get FamilySkyDrawable faces (radius 18 dp, recoloured by showTab's tints), and the
// history badges' 20 dp FamilySkyDrawable pills are flattened to 8 dp GradientDrawables (non-clickable TextViews).
//
// Quirks kept (spec 8.6, 4.1.5): the trend week label is the ISO week number with the CALENDAR year ("W01/24" for
// 2024-12-30, merged with January 2024's group; "W53/27" for 2027-01-01); `dashboard` is written and never read; a
// correct attempt whose stored answer texts differ also shows the correct-answer line; an unknown category key is
// shown raw; the history date uses the device time zone and default locale (Gregorian), the trends UTC.
// No iOS-only control: the screen's own X (progressBackButton) does what Android's Back callback does.
// Kotlin-private helpers the parity tests call (weekKey, monthKey, groupAttempts, sumBuckets) are internal.

/**
 * Learning dashboard. It is intentionally read-only: the game remains the place where answers
 * are made; this screen is the calm place where a player can understand progress and revisit work.
 */
final class TripleShotProgressFragment: AFragment {

    private lazy var firebase = TripleShotFirebaseRepository()

    private var progressTab: AButton!
    private var historyTab: AButton!
    private var progressScroll: AScrollView!
    private var historyScroll: AScrollView!
    private var progressContent: ALinearLayout!
    private var historyContent: ALinearLayout!
    private var loading: AProgressBar!
    private var errorText: ATextView!

    private var dashboard: TripleShotFirebaseRepository.KnowledgeDashboard? = nil

    /// `Fragment(R.layout.fragment_triple_shot_progress)`: the default onCreateView inflates the layout, whose Swift
    /// builder is registered with ALayoutInflater on first use.
    override init() {
        _ = TripleShotProgressFragment.layoutRegistration
        super.init(contentLayoutId: R.layout.fragment_triple_shot_progress)
    }

    /// Registers the builder of R.layout.fragment_triple_shot_progress once.
    static let layoutRegistration: Void = {
        ALayoutInflater.register(R.layout.fragment_triple_shot_progress) { inflater in
            TripleShotProgressFragment.Layout.inflate(inflater)
        }
    }()

    override func onViewCreated(_ view: AView, _ savedInstanceState: ABundle?) {
        super.onViewCreated(view, savedInstanceState)
        applyGameplayInsets(root: view, window: requireActivity().window)
        AWindowCompat.getInsetsController(requireActivity().window, view).isAppearanceLightStatusBars = true

        progressTab = view.findViewById(R.id.progressTabButton)
        historyTab = view.findViewById(R.id.historyTabButton)
        progressScroll = view.findViewById(R.id.progressScroll)
        historyScroll = view.findViewById(R.id.historyScroll)
        progressContent = view.findViewById(R.id.progressContent)
        historyContent = view.findViewById(R.id.historyContent)
        loading = view.findViewById(R.id.progressLoading)
        errorText = view.findViewById(R.id.progressError)

        let backButton: AButton = view.findViewById(R.id.progressBackButton)!
        backButton.setOnClickListener { [weak self] _ in
            (self?.parentFragment as? TripleShotHostFragment)?.backToHome()
        }

        requireActivity().onBackPressedDispatcher.addCallback(
            viewLifecycleOwner,
            AOnBackPressedCallback(true) { [weak self] _ in
                (self?.parentFragment as? TripleShotHostFragment)?.backToHome()
            }
        )

        progressTab.setOnClickListener { [weak self] _ in self?.showTab(progress: true) }
        historyTab.setOnClickListener { [weak self] _ in self?.showTab(progress: false) }
        showTab(progress: true)
        load()
    }

    private func load() {
        loading.visibility = AView.VISIBLE
        errorText.visibility = AView.GONE
        firebase.loadKnowledgeDashboard(attemptLimit: 500) { [weak self] result in
            guard let self = self else { return }
            if !self.isAdded { return }
            self.loading.visibility = AView.GONE
            switch result {
            case .success(let it):
                self.dashboard = it
                self.renderProgress(data: it)
                self.renderHistory(data: it)
            case .failure:
                self.errorText.setText(res: R.string.minik_swish_progress_load_error)
                self.errorText.visibility = AView.VISIBLE
            }
        }
    }

    private func showTab(progress: Bool) {
        progressScroll.visibility = progress ? AView.VISIBLE : AView.GONE
        historyScroll.visibility = progress ? AView.GONE : AView.VISIBLE

        let selected = AColor.parseColor("#0B8B78")
        let unselected = AColor.TRANSPARENT
        let selectedText = AColor.WHITE
        let unselectedText = AColor.parseColor("#36515B")
        progressTab.backgroundTintList = AColorStateList.valueOf(progress ? selected : unselected)
        historyTab.backgroundTintList = AColorStateList.valueOf(!progress ? selected : unselected)
        progressTab.setTextColor(progress ? selectedText : unselectedText)
        historyTab.setTextColor(!progress ? selectedText : unselectedText)
    }

    private func renderProgress(data: TripleShotFirebaseRepository.KnowledgeDashboard) {
        progressContent.removeAllViews()

        let all = sumBuckets(values: data.allTime.values)
        let week = sumBuckets(values: data.currentWeek.values)
        let month = sumBuckets(values: data.currentMonth.values)

        let hero = ACardView()
        hero.radius = dp(value: 24).toFloat()
        hero.cardElevation = dp(value: 3).toFloat()
        hero.setCardBackgroundColor(AColor.parseColor("#F8FFFFFF"))
        hero.strokeColor = AColor.parseColor("#445FA99C")
        hero.strokeWidth = dp(value: 1)
        let heroBody = ALinearLayout()
        heroBody.orientation = ALinearLayout.VERTICAL
        heroBody.gravity = AGravity.CENTER
        heroBody.setPadding(dp(value: 18), dp(value: 18), dp(value: 18), dp(value: 18))
        hero.addView(heroBody)
        let allTimeText = ATextView()
        allTimeText.text = getString(R.string.minik_swish_progress_all_time)
        allTimeText.textSize = 15
        allTimeText.setTextColor(AColor.parseColor("#5A6A70"))
        allTimeText.gravity = AGravity.CENTER
        heroBody.addView(allTimeText)
        let allPercentText = ATextView()
        allPercentText.text = "\(all.accuracyPercent)%"
        allPercentText.textSize = 42
        allPercentText.setTypeface(allPercentText.typeface, ATypeface.BOLD)
        allPercentText.setTextColor(AColor.parseColor("#0B8B78"))
        allPercentText.gravity = AGravity.CENTER
        heroBody.addView(allPercentText)
        let allCountsText = ATextView()
        allCountsText.text = getString(R.string.minik_swish_progress_answers_format, all.total) +
            "  \u{2022}  " + getString(R.string.minik_swish_progress_correct_format, all.correct)
        allCountsText.textSize = 15
        allCountsText.setTextColor(AColor.parseColor("#42545C"))
        allCountsText.gravity = AGravity.CENTER
        heroBody.addView(allCountsText)
        progressContent.addView(hero, matchWrap(top: 2))

        let periodRow = ALinearLayout()
        periodRow.orientation = ALinearLayout.HORIZONTAL
        periodRow.gravity = AGravity.CENTER
        periodRow.addView(periodCard(title: getString(R.string.minik_swish_progress_this_week), bucket: week), weighted(end: 5))
        periodRow.addView(periodCard(title: getString(R.string.minik_swish_progress_this_month), bucket: month), weighted(start: 5))
        progressContent.addView(periodRow, matchWrap(top: 10))

        addSectionTitle(parent: progressContent, title: getString(R.string.minik_swish_progress_weekly_trend))
        addTrendRows(parent: progressContent, groups: groupAttempts(attempts: data.attempts, weekly: true), maxRows: 8)

        addSectionTitle(parent: progressContent, title: getString(R.string.minik_swish_progress_monthly_trend))
        addTrendRows(parent: progressContent, groups: groupAttempts(attempts: data.attempts, weekly: false), maxRows: 6)

        addSectionTitle(parent: progressContent, title: getString(R.string.minik_swish_progress_categories))
        let language = currentLanguageCode()
        // QuestionCategory.values() (declaration order) -> filter -> STABLE sortedByDescending (ties keep enum order).
        let categories = QuestionCategory.allCases
            .map { category -> (first: QuestionCategory, second: TripleShotFirebaseRepository.KnowledgeBucket) in
                (first: category, second: data.allTime[category.name] ?? TripleShotFirebaseRepository.KnowledgeBucket())
            }
            .filter { $0.second.total > 0 }
            .kSortedByDescending { $0.second.total }

        if categories.isEmpty {
            addEmptyText(parent: progressContent, textValue: getString(R.string.minik_swish_progress_no_data))
        } else {
            for (category, bucket) in categories {
                progressContent.addView(categoryCard(title: category.labelFor(languageCode: language), bucket: bucket), matchWrap(top: 7))
            }
        }
    }

    private func renderHistory(data: TripleShotFirebaseRepository.KnowledgeDashboard) {
        historyContent.removeAllViews()
        if data.attempts.isEmpty {
            addEmptyText(parent: historyContent, textValue: getString(R.string.minik_swish_progress_history_empty))
            return
        }
        let language = currentLanguageCode()
        for attempt in data.attempts {
            // `runCatching { QuestionCategory.valueOf(attempt.category) }.getOrNull()`
            let category = QuestionCategory.named(attempt.category)
            let categoryLabel = category?.labelFor(languageCode: language) ?? attempt.category
            historyContent.addView(historyCard(attempt: attempt, categoryLabel: categoryLabel), matchWrap(top: 7))
        }
    }

    private func periodCard(title: String, bucket: TripleShotFirebaseRepository.KnowledgeBucket) -> AView {
        let card = ACardView()
        card.radius = dp(value: 20).toFloat()
        card.cardElevation = 0
        card.setCardBackgroundColor(AColor.parseColor("#F3FFFFFF"))
        card.strokeColor = AColor.parseColor("#335B7B83")
        card.strokeWidth = dp(value: 1)
        let body = ALinearLayout()
        body.orientation = ALinearLayout.VERTICAL
        body.gravity = AGravity.CENTER
        body.setPadding(dp(value: 10), dp(value: 14), dp(value: 10), dp(value: 14))
        card.addView(body)
        let titleText = ATextView()
        titleText.text = title
        titleText.textSize = 14
        titleText.setTextColor(AColor.parseColor("#5D6B71"))
        titleText.gravity = AGravity.CENTER
        body.addView(titleText)
        let percentText = ATextView()
        percentText.text = "\(bucket.accuracyPercent)%"
        percentText.textSize = 27
        percentText.setTypeface(percentText.typeface, ATypeface.BOLD)
        percentText.setTextColor(AColor.parseColor("#7042B8"))
        percentText.gravity = AGravity.CENTER
        body.addView(percentText)
        let answersText = ATextView()
        answersText.text = getString(R.string.minik_swish_progress_answers_format, bucket.total)
        answersText.textSize = 11
        answersText.setTextColor(AColor.parseColor("#65747A"))
        answersText.gravity = AGravity.CENTER
        body.addView(answersText)
        return card
    }

    private func categoryCard(title: String, bucket: TripleShotFirebaseRepository.KnowledgeBucket) -> AView {
        let card = ACardView()
        card.radius = dp(value: 18).toFloat()
        card.cardElevation = 0
        card.setCardBackgroundColor(AColor.parseColor("#F5FFFFFF"))
        let body = ALinearLayout()
        body.orientation = ALinearLayout.VERTICAL
        body.setPadding(dp(value: 14), dp(value: 12), dp(value: 14), dp(value: 12))
        card.addView(body)
        let row = ALinearLayout()
        row.orientation = ALinearLayout.HORIZONTAL
        row.gravity = AGravity.CENTER_VERTICAL
        let titleText = ATextView()
        titleText.text = title
        titleText.textSize = 16
        titleText.setTypeface(titleText.typeface, ATypeface.BOLD)
        titleText.setTextColor(AColor.parseColor("#24353D"))
        row.addView(titleText, ALinearLayout.LayoutParams(0, AViewGroup.LayoutParams.WRAP_CONTENT, 1))
        let accuracyText = ATextView()
        accuracyText.text = getString(R.string.minik_swish_progress_accuracy_format, bucket.accuracyPercent)
        accuracyText.textSize = 15
        accuracyText.setTypeface(accuracyText.typeface, ATypeface.BOLD)
        accuracyText.setTextColor(AColor.parseColor("#0B8B78"))
        row.addView(accuracyText)
        body.addView(row)
        let bar = AProgressBar(nil, android.R.attr.progressBarStyleHorizontal)
        bar.max = 100
        bar.progress = bucket.accuracyPercent
        bar.progressTintList = AColorStateList.valueOf(AColor.parseColor("#0B8B78"))
        bar.progressBackgroundTintList = AColorStateList.valueOf(AColor.parseColor("#DCE9E6"))
        let barParams = ALinearLayout.LayoutParams(AViewGroup.LayoutParams.MATCH_PARENT, dp(value: 8))
        barParams.topMargin = dp(value: 8)
        body.addView(bar, barParams)
        let countsText = ATextView()
        countsText.text = getString(R.string.minik_swish_progress_correct_format, bucket.correct) +
            " / " + getString(R.string.minik_swish_progress_answers_format, bucket.total)
        countsText.textSize = 11
        countsText.setTextColor(AColor.parseColor("#68777D"))
        countsText.setPadding(0, dp(value: 5), 0, 0)
        body.addView(countsText)
        return card
    }

    private func historyCard(
        attempt: TripleShotFirebaseRepository.KnowledgeAttemptRecord,
        categoryLabel: String
    ) -> AView {
        let card = ACardView()
        card.radius = dp(value: 18).toFloat()
        card.cardElevation = dp(value: 1).toFloat()
        card.setCardBackgroundColor(AColor.parseColor("#F8FFFFFF"))
        card.strokeColor = AColor.parseColor(attempt.correct ? "#334FAE85" : "#33C56A64")
        card.strokeWidth = dp(value: 1)
        let body = ALinearLayout()
        body.orientation = ALinearLayout.VERTICAL
        body.setPadding(dp(value: 14), dp(value: 12), dp(value: 14), dp(value: 13))
        card.addView(body)

        let top = ALinearLayout()
        top.orientation = ALinearLayout.HORIZONTAL
        top.gravity = AGravity.CENTER_VERTICAL
        let categoryText = ATextView()
        categoryText.text = categoryLabel
        categoryText.textSize = 11
        categoryText.setTypeface(categoryText.typeface, ATypeface.BOLD)
        categoryText.setTextColor(AColor.parseColor("#7042B8"))
        top.addView(categoryText, ALinearLayout.LayoutParams(0, AViewGroup.LayoutParams.WRAP_CONTENT, 1))
        let badge = ATextView()
        badge.text = getString(attempt.correct ? R.string.minik_swish_progress_correct_badge : R.string.minik_swish_progress_wrong_badge)
        badge.textSize = 11
        badge.setTypeface(badge.typeface, ATypeface.BOLD)
        badge.setTextColor(AColor.WHITE)
        badge.background = pill(color: attempt.correct ? "#0B8B78" : "#B9534D")
        badge.setPadding(dp(value: 9), dp(value: 4), dp(value: 9), dp(value: 4))
        top.addView(badge)
        body.addView(top)

        let promptText = ATextView()
        // `attempt.prompt.ifBlank { attempt.questionId }`
        promptText.text = attempt.prompt.kotlinIsBlank ? attempt.questionId : attempt.prompt
        promptText.textSize = 17
        promptText.setTypeface(promptText.typeface, ATypeface.BOLD)
        promptText.setTextColor(AColor.parseColor("#1B2B32"))
        promptText.setPadding(0, dp(value: 8), 0, 0)
        promptText.textDirection = AView.TEXT_DIRECTION_LOCALE
        body.addView(promptText)

        addAnswerLine(parent: body, label: getString(R.string.minik_swish_progress_your_answer), value: attempt.selectedAnswer, positive: attempt.correct)
        if !attempt.correct || attempt.correctAnswer != attempt.selectedAnswer {
            addAnswerLine(parent: body, label: getString(R.string.minik_swish_progress_correct_answer), value: attempt.correctAnswer, positive: true)
        }

        let date: String
        if attempt.answeredAt > 0 {
            date = ASimpleDateFormat("dd/MM/yyyy HH:mm", ALocale.getDefault()).format(ADate(attempt.answeredAt))
        } else {
            date = ""
        }
        let footer = ATextView()
        // `listOf(date, gameType.replace('_', ' ')).filter { it.isNotBlank() }.joinToString(" • ")`
        footer.text = [date, attempt.gameType.replacingOccurrences(of: "_", with: " ")]
            .filter { !$0.kotlinIsBlank }
            .joined(separator: " \u{2022} ")
        footer.textSize = 10
        footer.setTextColor(AColor.parseColor("#7B888D"))
        footer.setPadding(0, dp(value: 8), 0, 0)
        body.addView(footer)
        return card
    }

    private func addAnswerLine(parent: ALinearLayout, label: String, value: String, positive: Bool) {
        let line = ATextView()
        // `"$label: ${value.ifBlank { "—" }}"`
        line.text = "\(label): \(value.kotlinIsBlank ? "\u{2014}" : value)"
        line.textSize = 14
        line.setTextColor(AColor.parseColor(positive ? "#246B59" : "#9C4B47"))
        line.setPadding(0, dp(value: 7), 0, 0)
        line.textDirection = AView.TEXT_DIRECTION_LOCALE
        parent.addView(line)
    }

    private func addSectionTitle(parent: ALinearLayout, title: String) {
        let section = ATextView()
        section.text = title
        section.textSize = 17
        section.setTypeface(section.typeface, ATypeface.BOLD)
        section.setTextColor(AColor.parseColor("#1B3038"))
        section.setPadding(dp(value: 3), dp(value: 18), dp(value: 3), dp(value: 5))
        parent.addView(section)
    }

    private func addTrendRows(
        parent: ALinearLayout,
        groups: [(first: String, second: TripleShotFirebaseRepository.KnowledgeBucket)],
        maxRows: Int
    ) {
        if groups.isEmpty {
            addEmptyText(parent: parent, textValue: getString(R.string.minik_swish_progress_no_data))
            return
        }
        // `groups.takeLast(maxRows)`
        for (label, bucket) in groups.suffix(maxRows) {
            let row = ALinearLayout()
            row.orientation = ALinearLayout.HORIZONTAL
            row.gravity = AGravity.CENTER_VERTICAL
            row.setPadding(dp(value: 4), dp(value: 5), dp(value: 4), dp(value: 5))
            let labelText = ATextView()
            labelText.text = label
            labelText.textSize = 11
            labelText.setTextColor(AColor.parseColor("#607179"))
            row.addView(labelText, ALinearLayout.LayoutParams(dp(value: 66), AViewGroup.LayoutParams.WRAP_CONTENT))
            let bar = AProgressBar(nil, android.R.attr.progressBarStyleHorizontal)
            bar.max = 100
            bar.progress = bucket.accuracyPercent
            bar.progressTintList = AColorStateList.valueOf(AColor.parseColor("#7042B8"))
            bar.progressBackgroundTintList = AColorStateList.valueOf(AColor.parseColor("#E9E4F1"))
            let barParams = ALinearLayout.LayoutParams(0, dp(value: 9), 1)
            barParams.marginEnd = dp(value: 9)
            row.addView(bar, barParams)
            let valueText = ATextView()
            valueText.text = "\(bucket.accuracyPercent)%  (\(bucket.total))"
            valueText.textSize = 11
            valueText.setTypeface(valueText.typeface, ATypeface.BOLD)
            valueText.setTextColor(AColor.parseColor("#3B4C54"))
            valueText.gravity = AGravity.END
            row.addView(valueText, ALinearLayout.LayoutParams(dp(value: 72), AViewGroup.LayoutParams.WRAP_CONTENT))
            parent.addView(row)
        }
    }

    /// Groups the attempts by UTC week or month label, oldest group first (private in Kotlin).
    func groupAttempts(
        attempts: [TripleShotFirebaseRepository.KnowledgeAttemptRecord],
        weekly: Bool
    ) -> [(first: String, second: TripleShotFirebaseRepository.KnowledgeBucket)] {
        let tz = ATimeZone.getTimeZone("UTC")
        // `linkedMapOf<String, MutableList<KnowledgeAttemptRecord>>()`: insertion-ordered.
        var grouped = KLinkedMap<String, [TripleShotFirebaseRepository.KnowledgeAttemptRecord]>()
        for attempt in attempts.filter({ $0.answeredAt > 0 }).kSortedBy({ $0.answeredAt }) {
            let key = weekly ? weekKey(ms: attempt.answeredAt, tz: tz) : monthKey(ms: attempt.answeredAt, tz: tz)
            // `grouped.getOrPut(key) { mutableListOf() }.add(attempt)`: a new key goes to the end, an existing one stays.
            grouped[key, default: []].append(attempt)
        }
        return grouped.map { entry in
            (first: entry.key, second: TripleShotFirebaseRepository.KnowledgeBucket(
                total: entry.value.count,
                correct: entry.value.filter { $0.correct }.count
            ))
        }
    }

    /// `"W%02d/%02d"` of WEEK_OF_YEAR (Monday first, 4 minimal days: the ISO week) and the CALENDAR year % 100
    /// (spec 8.6: kept as on Android; private in Kotlin).
    func weekKey(ms: Int64, tz: ATimeZone) -> String {
        let cal = ACalendar.getInstance(tz, ALocale.US)
        cal.timeInMillis = ms
        cal.firstDayOfWeek = ACalendar.MONDAY
        cal.minimalDaysInFirstWeek = 4
        return AFormat.format(ALocale.US, "W%02d/%02d", cal.get(ACalendar.WEEK_OF_YEAR), cal.get(ACalendar.YEAR) % 100)
    }

    /// `SimpleDateFormat("MM/yy", Locale.US)` in `tz` (private in Kotlin).
    func monthKey(ms: Int64, tz: ATimeZone) -> String {
        let format = ASimpleDateFormat("MM/yy", ALocale.US)
        format.timeZone = tz
        return format.format(ADate(ms))
    }

    /// Sums totals and corrects (private in Kotlin).
    func sumBuckets(values: [TripleShotFirebaseRepository.KnowledgeBucket]) -> TripleShotFirebaseRepository.KnowledgeBucket {
        return TripleShotFirebaseRepository.KnowledgeBucket(
            total: values.reduce(0) { $0 + $1.total },
            correct: values.reduce(0) { $0 + $1.correct }
        )
    }

    private func addEmptyText(parent: ALinearLayout, textValue: String) {
        let empty = ATextView()
        empty.text = textValue
        empty.textSize = 15
        empty.setTextColor(AColor.parseColor("#65757B"))
        empty.gravity = AGravity.CENTER
        empty.setPadding(dp(value: 18), dp(value: 18), dp(value: 18), dp(value: 18))
        parent.addView(empty)
    }

    private func pill(color: String) -> FamilySkyDrawable {
        let face = FamilySkyDrawable()
        face.shape = AGradientDrawable.RECTANGLE
        face.cornerRadius = dp(value: 20).toFloat()
        face.setColor(AColor.parseColor(color))
        return face
    }

    /// `(ConfigurationCompat.getLocales(configuration)[0] ?: Locale.getDefault())?.language`.
    private func currentLanguageCode() -> String {
        return (AConfigurationCompat.getLocales(resources.configuration)[0] ?? ALocale.getDefault()).language
    }

    private func dp(value: Int) -> Int { return (value.toFloat() * resources.displayMetrics.density).toInt() }

    private func matchWrap(top: Int = 0) -> ALinearLayout.LayoutParams {
        let params = ALinearLayout.LayoutParams(AViewGroup.LayoutParams.MATCH_PARENT, AViewGroup.LayoutParams.WRAP_CONTENT)
        params.topMargin = dp(value: top)
        return params
    }

    private func weighted(start: Int = 0, end: Int = 0) -> ALinearLayout.LayoutParams {
        let params = ALinearLayout.LayoutParams(0, AViewGroup.LayoutParams.WRAP_CONTENT, 1)
        params.marginStart = dp(value: start)
        params.marginEnd = dp(value: end)
        return params
    }
}

// MARK: - res/layout/fragment_triple_shot_progress.xml

extension TripleShotProgressFragment {
    /// The XML layout as Android inflates it: ConstraintLayout (#FFFDF5) > [ImageView progressBackground (court art,
    /// centerCrop, alpha 0.22, all four edges), LinearLayout progressShell (vertical, ≤ 520 dp wide, centred, padding
    /// 16/18/16/12) > header row (back button, title column, 44 dp spacer), tab card, spinner, error text, two
    /// ScrollViews with their content columns]. XML dimensions are read like Android: layout sizes, margins, paddings,
    /// text sizes, button corner radii and stroke widths as whole pixels (getDimensionPixelSize), card corner radius
    /// and elevation as float pixels (getDimension).
    enum Layout {
        static let PARENT = AConstraintLayout.LayoutParams.PARENT_ID
        static let MATCH = AViewGroup.LayoutParams.MATCH_PARENT
        static let WRAP = AViewGroup.LayoutParams.WRAP_CONTENT

        /// A dp dimension read with getDimensionPixelSize.
        static func px(_ dp: Float) -> Int {
            return ATypedValue.toDimensionPixelSize(ATypedValue.COMPLEX_UNIT_DIP, dp)
        }

        /// A dp dimension read with getDimension (MaterialCardView cardCornerRadius / cardElevation).
        static func pxF(_ dp: Float) -> Float {
            return ATypedValue.applyDimension(ATypedValue.COMPLEX_UNIT_DIP, dp)
        }

        /// `android:textStyle="bold"` under the theme's android:fontFamily "sans".
        static func bold(_ view: ATextView) {
            view.setTypeface(ATypeface.create("sans", ATypeface.NORMAL), ATypeface.BOLD)
        }

        /// 0dp x 0dp constrained to the four parent edges.
        static func fillParent() -> AConstraintLayout.LayoutParams {
            let params = AConstraintLayout.LayoutParams(0, 0)
            params.topToTop = PARENT
            params.bottomToBottom = PARENT
            params.startToStart = PARENT
            params.endToEnd = PARENT
            return params
        }

        /// The builder registered for R.layout.fragment_triple_shot_progress.
        static func inflate(_ inflater: ALayoutInflater) -> AView {
            let root = AConstraintLayout()
            root.layoutParams = AViewGroup.LayoutParams(MATCH, MATCH)
            root.setBackgroundColor(argbInt(0xFFFFFDF5))

            // <ImageView progressBackground>: 0dp x 0dp, alpha 0.22, centerCrop, triple_shot_court_background,
            // contentDescription @null.
            let background = AImageView()
            background.viewId = R.id.progressBackground
            background.setAlpha(0.22)
            background.scaleType = AImageView.ScaleType.CENTER_CROP
            background.setImageResource(R.drawable.triple_shot_court_background)
            root.addView(background, fillParent())

            // <LinearLayout progressShell>: 0dp x 0dp, vertical, paddingStart/End 16dp, paddingTop 18dp,
            // paddingBottom 12dp, constraintWidth_max 520dp.
            let shell = ALinearLayout()
            shell.viewId = R.id.progressShell
            shell.orientation = ALinearLayout.VERTICAL
            shell.setPaddingRelative(px(16), px(18), px(16), px(12))

            // Header row: match x wrap, gravity center_vertical, horizontal.
            let header = ALinearLayout()
            header.gravity = AGravity.CENTER_VERTICAL
            header.orientation = ALinearLayout.HORIZONTAL

            // <TripleShotButton progressBackButton> style TextButton: 44dp x 44dp, minWidth 0dp, text "‹", 28sp,
            // #17343E, contentDescription @string/minik_swish_progress_back.
            let back = TripleShotButton(style: AButton.Style.TEXT)
            back.viewId = R.id.progressBackButton
            back.minimumWidth = 0
            back.minWidth = 0
            back.text = "\u{2039}"
            back.applyXmlTextSize(28)
            back.setTextColor(argbInt(0xFF17343E))
            back.contentDescription = AResources.getString(R.string.minik_swish_progress_back)
            header.addView(back, ALinearLayout.LayoutParams(px(44), px(44)))

            // Title column: 0dp x wrap, weight 1, vertical, gravity center.
            let titles = ALinearLayout()
            titles.orientation = ALinearLayout.VERTICAL
            titles.gravity = AGravity.CENTER
            let title = ATextView()
            title.setText(res: R.string.minik_swish_progress_title)
            title.setTextColor(argbInt(0xFF142129))
            title.applyXmlTextSize(25)
            bold(title)
            titles.addView(title, ALinearLayout.LayoutParams(WRAP, WRAP))
            let subtitle = ATextView()
            subtitle.setText(res: R.string.minik_swish_progress_subtitle)
            subtitle.setTextColor(argbInt(0xFF5F6F76))
            subtitle.applyXmlTextSize(15)
            titles.addView(subtitle, ALinearLayout.LayoutParams(WRAP, WRAP))
            header.addView(titles, ALinearLayout.LayoutParams(0, WRAP, 1))

            // A plain <View> 44dp x 44dp (TripleShotControls removes it when it moves the back button).
            let spacer = AView()
            header.addView(spacer, ALinearLayout.LayoutParams(px(44), px(44)))
            shell.addView(header, ALinearLayout.LayoutParams(MATCH, WRAP))

            // <MaterialCardView>: match x 52dp, marginTop 12dp, #F4FFFFFF, radius 18dp, elevation 0dp,
            // stroke #334F7C86 1dp.
            let tabCard = ACardView()
            tabCard.setCardBackgroundColor(argbInt(0xF4FFFFFF))
            tabCard.radius = pxF(18)
            tabCard.cardElevation = pxF(0)
            tabCard.strokeColor = argbInt(0x334F7C86)
            tabCard.strokeWidth = px(1)
            let tabs = ALinearLayout()
            tabs.orientation = ALinearLayout.HORIZONTAL
            tabs.setPadding(px(4), px(4), px(4), px(4))

            // <TripleShotButton progressTabButton>: 0dp x match, weight 1, textAllCaps false, bold, cornerRadius 14dp.
            let progressTab = TripleShotButton()
            progressTab.viewId = R.id.progressTabButton
            progressTab.setText(res: R.string.minik_swish_progress_tab_progress)
            progressTab.setAllCaps(false)
            bold(progressTab)
            progressTab.cornerRadius = px(14)
            tabs.addView(progressTab, ALinearLayout.LayoutParams(0, MATCH, 1))

            // <TripleShotButton historyTabButton> style TextButton: 0dp x match, weight 1, textAllCaps false,
            // cornerRadius 14dp.
            let historyTab = TripleShotButton(style: AButton.Style.TEXT)
            historyTab.viewId = R.id.historyTabButton
            historyTab.setText(res: R.string.minik_swish_progress_tab_questions)
            historyTab.setAllCaps(false)
            historyTab.cornerRadius = px(14)
            tabs.addView(historyTab, ALinearLayout.LayoutParams(0, MATCH, 1))
            tabCard.addView(tabs, AFrameLayout.LayoutParams(MATCH, MATCH))
            let tabCardParams = ALinearLayout.LayoutParams(MATCH, px(52))
            tabCardParams.topMargin = px(12)
            shell.addView(tabCard, tabCardParams)

            // <ProgressBar progressLoading>: 36dp x 36dp, layout_gravity center, marginTop 28dp.
            let loading = AProgressBar()
            loading.viewId = R.id.progressLoading
            let loadingParams = ALinearLayout.LayoutParams(px(36), px(36))
            loadingParams.gravity = AGravity.CENTER
            loadingParams.topMargin = px(28)
            shell.addView(loading, loadingParams)

            // <TextView progressError>: match x wrap, marginTop 16dp, gravity center, #8C3B3B, 15sp, gone.
            let error = ATextView()
            error.viewId = R.id.progressError
            error.gravity = AGravity.CENTER
            error.setTextColor(argbInt(0xFF8C3B3B))
            error.applyXmlTextSize(15)
            error.visibility = AView.GONE
            let errorParams = ALinearLayout.LayoutParams(MATCH, WRAP)
            errorParams.topMargin = px(16)
            shell.addView(error, errorParams)

            // <ScrollView progressScroll / historyScroll>: match x 0dp, weight 1, marginTop 10dp, clipToPadding false,
            // overScrollMode never, gone; each holds a vertical match x wrap column with paddingBottom 28dp.
            for (scrollId, contentId) in [(R.id.progressScroll, R.id.progressContent), (R.id.historyScroll, R.id.historyContent)] {
                let scroll = AScrollView()
                scroll.viewId = scrollId
                scroll.clipToPadding = false
                scroll.overScrollMode = AView.OVER_SCROLL_NEVER
                scroll.visibility = AView.GONE
                let content = ALinearLayout()
                content.viewId = contentId
                content.orientation = ALinearLayout.VERTICAL
                content.setPadding(0, 0, 0, px(28))
                scroll.addView(content, AFrameLayout.LayoutParams(MATCH, WRAP))
                let scrollParams = ALinearLayout.LayoutParams(MATCH, 0, 1)
                scrollParams.topMargin = px(10)
                shell.addView(scroll, scrollParams)
            }

            let shellParams = fillParent()
            shellParams.matchConstraintMaxWidth = px(520)
            root.addView(shell, shellParams)
            return root
        }
    }
}
