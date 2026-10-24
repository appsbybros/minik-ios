import Foundation

/// Port of `ui/TripleShotLeaderboardAdapter.kt` (Android 6c38131), statement by statement (spec 25 §4.2.2),
/// on AndroidKit's RecyclerView-lite (`ARecyclerView.Adapter` / `ViewHolder`), plus
/// `res/layout/item_triple_shot_leaderboard.xml` built in code (`TripleShotLeaderboardItemLayout`, registered for
/// `R.layout.item_triple_shot_leaderboard` when the adapter is created).
///
/// Row texts are the Kotlin string templates: `"#N"`, the name or "Player" / Hebrew "שחקן" for a blank name, and the
/// two-line stats with the points suffix "pts" / Hebrew "נק׳" (U+05E0 U+05E7 U+05F3) by the device language, the
/// basketball U+1F3C0, the brain U+1F9E0 and U+2022 bullets with two spaces on each side. Kotlin string templates print Ints with ASCII digits, like
/// Swift interpolation.
final class TripleShotLeaderboardAdapter: ARecyclerView.Adapter<TripleShotLeaderboardAdapter.Holder> {

    enum SortMode: String, KotlinEnum {
        case SCORE
        case SHOOTING_STREAK
    }

    private var items: [LeaderboardEntry] = []
    private var sortMode: SortMode = SortMode.SCORE

    /// Registers the Swift builder of `R.layout.item_triple_shot_leaderboard` once (ALayoutInflater).
    private static let itemLayoutRegistration: Void = {
        ALayoutInflater.register(R.layout.item_triple_shot_leaderboard) { _ in
            TripleShotLeaderboardItemLayout.build()
        }
    }()

    override init() {
        super.init()
        _ = TripleShotLeaderboardAdapter.itemLayoutRegistration
    }

    func submit(newItems: [LeaderboardEntry], mode: SortMode) {
        items = newItems
        sortMode = mode
        notifyDataSetChanged()
    }

    override func onCreateViewHolder(_ parent: AViewGroup, _ viewType: Int) -> Holder {
        let view = ALayoutInflater.from(parent.context)
            .inflate(R.layout.item_triple_shot_leaderboard, parent, false)
        return Holder(view: view)
    }

    override func getItemCount() -> Int {
        return items.count
    }

    override func onBindViewHolder(_ holder: Holder, _ position: Int) {
        let item = items[position]
        holder.rank.text = "#\(position + 1)"
        let he = ["he", "iw"].contains(holder.itemView.resources.configuration.locales[0].language)
        holder.name.gravity = AGravity.START | AGravity.CENTER_VERTICAL
        holder.name.textAlignment = AView.TEXT_ALIGNMENT_VIEW_START
        holder.name.textDirection = AView.TEXT_DIRECTION_LOCALE
        holder.name.text = item.name.kotlinIsBlank ? (he ? "שחקן" : "Player") : item.name
        let points = he ? "נק׳" : "pts"
        switch sortMode {
        case SortMode.SCORE:
            holder.stats.text =
                "\(item.bestScore) \(points)\n\u{1F3C0} \(item.bestShootingStreak)  \u{2022}  \u{1F9E0} \(item.bestKnowledgeStreak)"
        case SortMode.SHOOTING_STREAK:
            holder.stats.text = "\u{1F3C0} \(item.bestShootingStreak)\n\(item.bestScore) \(points)"
        }
    }

    final class Holder: ARecyclerView.ViewHolder {
        let rank: ATextView
        let name: ATextView
        let stats: ATextView

        init(view: AView) {
            let rank: ATextView? = view.findViewById(R.id.rankText)
            let name: ATextView? = view.findViewById(R.id.nameText)
            let stats: ATextView? = view.findViewById(R.id.statsText)
            self.rank = rank!
            self.name = name!
            self.stats = stats!
            super.init(view)
        }
    }
}

// MARK: - res/layout/item_triple_shot_leaderboard.xml

/// The view tree of `res/layout/item_triple_shot_leaderboard.xml`, built in code with the XML's ids, attributes and
/// layout params (DESIGN 2.8). Sizes, margins, paddings, text sizes and the stroke width are pixel sizes
/// (`getDimensionPixelSize`, rounded); the card corner radius and elevation are exact dimensions (`getDimension`).
/// The XML root's layout params (match x wrap, layout_marginVertical 5dp) are set on the card; the inflater converts
/// them for the RecyclerView, as Android does.
enum TripleShotLeaderboardItemLayout {

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

        // <com.google.android.material.card.MaterialCardView match x wrap layout_marginVertical 5dp
        //  cardBackgroundColor #F2FFFFFF cardCornerRadius 17dp cardElevation 0dp strokeColor #4432BFA8 strokeWidth 1dp>
        let card = ACardView()
        let cardParams = AViewGroup.MarginLayoutParams(MATCH, WRAP)
        cardParams.topMargin = px(5)
        cardParams.bottomMargin = px(5)
        card.layoutParams = cardParams
        card.setCardBackgroundColor(AColor.parseColor("#F2FFFFFF"))
        card.radius = dimen(17)
        card.cardElevation = dimen(0)
        card.setStrokeColor(AColorStateList.valueOf(AColor.parseColor("#4432BFA8")))
        card.strokeWidth = px(1)

        //   <LinearLayout match x wrap gravity center_vertical horizontal padding 12dp>
        let row = ALinearLayout()
        row.gravity = AGravity.CENTER_VERTICAL
        row.orientation = ALinearLayout.HORIZONTAL
        row.setPadding(px(12), px(12), px(12), px(12))

        //     <TextView @+id/rankText 38dp x wrap gravity center @color/triple_shot_purple 20sp bold>
        let rank = ATextView()
        rank.viewId = R.id.rankText
        rank.gravity = AGravity.CENTER
        rank.setTextColor(R.color.triple_shot_purple)
        rank.applyXmlTextSize(20)
        bold(rank)
        row.addView(rank, ALinearLayout.LayoutParams(px(38), WRAP))

        //     <TextView @+id/nameText 0dp x wrap weight 1 ellipsize end maxLines 1 @color/triple_shot_ink 17sp bold>
        let name = ATextView()
        name.viewId = R.id.nameText
        name.ellipsize = ATextUtils.TruncateAt.END
        name.maxLines = 1
        name.setTextColor(R.color.triple_shot_ink)
        name.applyXmlTextSize(17)
        bold(name)
        row.addView(name, ALinearLayout.LayoutParams(0, WRAP, 1))

        //     <TextView @+id/statsText wrap x wrap gravity end @color/triple_shot_green 14sp bold>
        let stats = ATextView()
        stats.viewId = R.id.statsText
        stats.gravity = AGravity.END
        stats.setTextColor(R.color.triple_shot_green)
        stats.applyXmlTextSize(14)
        bold(stats)
        row.addView(stats, ALinearLayout.LayoutParams(WRAP, WRAP))

        card.addView(row, AFrameLayout.LayoutParams(MATCH, WRAP))
        return card
    }
}
