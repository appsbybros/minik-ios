import SwiftUI

@MainActor
final class RecordsLeaderboardViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case loaded(RemoteRecordsSnapshot)
        case notConfigured
        case failed
    }

    @Published private(set) var state: State = .idle
    private let repository: (any RecordsRepository)?

    init(repository: (any RecordsRepository)?) {
        self.repository = repository
    }

    func load() async {
        guard let repository else {
            state = .notConfigured
            return
        }
        state = .loading
        do {
            state = .loaded(try await repository.loadTopRecords())
        } catch {
            state = .failed
        }
    }
}

/// Android's RecordsLeaderboardDialogFragment in the rainbow-sky design: a white card
/// with a lavender-to-sky header (the navy Fredoka title, a soft-ink subtitle and the
/// red X), the boards' rows as white cards with lavender rims and gold, silver and
/// bronze rank badges, and the opt-out link at the bottom. Phones switch between the
/// two boards with Android's tabs; an iPad shows them side by side, as Android's
/// tablet dialog does. LanguageRecordsDialog rounds and frames the card over the
/// menu; after a new record it fills the screen.
struct RecordsLeaderboardView: View {
    let onClose: () -> Void
    private let highlightedPlacements: [RemoteRecordPlacement]
    /// True when the Top 20 opened by itself (RecordsAutoShowPolicy): it then offers
    /// "Don't show automatically", as Android's RecordsLeaderboardDialogFragment does.
    private let offersAutomaticOptOut: Bool
    @StateObject private var model: RecordsLeaderboardViewModel
    @State private var automaticShowingTurnedOff = false
    /// The board the tabs show. Like Android, a new streak record alone opens on
    /// the streaks; otherwise the scores come first.
    @State private var selectedBoard: RemoteRecordType

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.interfaceLocaleID) private var interfaceLocaleID
    /// The rank badge (Android's 38 dp) grows with the text so two-digit ranks
    /// (10-20) stay on one line.
    @ScaledMetric(relativeTo: .headline) private var rankColumnWidth: CGFloat = 38
    // Android's sp sizes on phones; like sp they follow the reader's text size.
    @ScaledMetric(relativeTo: .title) private var titleFontSize: CGFloat = 25
    @ScaledMetric(relativeTo: .subheadline) private var subtitleFontSize: CGFloat = 15
    @ScaledMetric(relativeTo: .headline) private var tabFontSize: CGFloat = 17
    @ScaledMetric(relativeTo: .headline) private var rankFontSize: CGFloat = 16
    @ScaledMetric(relativeTo: .body) private var nameFontSize: CGFloat = 16
    @ScaledMetric(relativeTo: .headline) private var valueFontSize: CGFloat = 18

    @MainActor
    init(
        product: ProductVariant,
        repository: (any RecordsRepository)? = nil,
        highlightedPlacements: [RemoteRecordPlacement] = [],
        offersAutomaticOptOut: Bool = false,
        onClose: @escaping () -> Void
    ) {
        self.onClose = onClose
        self.highlightedPlacements = highlightedPlacements
        self.offersAutomaticOptOut = offersAutomaticOptOut
        let highlightedTypes = Set(highlightedPlacements.map(\.type))
        let initialBoard: RemoteRecordType = highlightedTypes == [.correctAnswersStreak]
            ? .correctAnswersStreak
            : .score
        _selectedBoard = State(initialValue: initialBoard)
        let resolvedRepository = repository ?? ProductionRecordsRepositoryFactory.make(for: product)
        _model = StateObject(wrappedValue: RecordsLeaderboardViewModel(repository: resolvedRepository))
    }

    var body: some View {
        // The header stays on top with the X; the boards scroll under the tabs, and
        // a reader around the scroll view lets the row holding a new record be
        // scrolled into view.
        GeometryReader { geometry in
            let metrics = MinikHomeLayoutMetrics(containerWidth: geometry.size.width)

            VStack(spacing: 0) {
                header(compact: metrics.compact)

                ScrollViewReader { proxy in
                    VStack(spacing: 0) {
                        if showsBoardTabs(metrics) {
                            boardTabs
                                .frame(maxWidth: metrics.contentMaxWidth)
                                .padding(.horizontal, metrics.horizontalPadding)
                                .padding(.top, 12)
                        }

                        ScrollView {
                            VStack(spacing: metrics.compact ? 12 : 16) {
                                content(metrics: metrics)
                            }
                            .frame(maxWidth: metrics.contentMaxWidth)
                            .padding(.horizontal, metrics.horizontalPadding)
                            .padding(.top, 10)
                            .padding(.bottom, 12)
                            .frame(maxWidth: .infinity)
                        }
                        .scrollIndicators(.hidden)
                        .scrollBounceBehavior(.basedOnSize)
                    }
                    .onChange(of: model.state) { _, newState in
                        showStreaksWhenOnlyTheyExist(in: newState)
                        scrollToHighlightedRow(in: newState, using: proxy)
                    }
                }

                if offersAutomaticOptOut {
                    automaticShowingOptOut
                        .padding(.bottom, 4)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        // A fill background never sizes the layout (see MinikHomeScreen).
        .background {
            Color.white
                .ignoresSafeArea()
        }
        .task { await model.load() }
    }

    /// Android's records_dont_show_automatically link in soft ink at the card's
    /// bottom: once tapped, the Top 20 no longer opens by itself, and the link says so.
    private var automaticShowingOptOut: some View {
        Button {
            guard !automaticShowingTurnedOff else { return }
            RecordsAutoShowPolicy.setShowsAutomatically(false)
            automaticShowingTurnedOff = true
        } label: {
            Text(automaticShowingTurnedOff
                ? interfaceLocaleID.text("Won’t be shown automatically again")
                : interfaceLocaleID.text("Don’t show automatically"))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(MinikPretty.softInk)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    /// bg_records_dialog_header: lavender to a hint of pink to sky, under the navy
    /// Fredoka title and the soft-ink subtitle, with the red X at the top end.
    private func header(compact: Bool) -> some View {
        // Android's 25 sp and 15 sp (34 sp and 20 sp on tablets), held within
        // what the fixed header can show.
        let titleSize = min(titleFontSize, 34) * (compact ? 1 : 1.36)
        let subtitleSize = min(subtitleFontSize, 22) * (compact ? 1 : 1.33)
        return VStack(spacing: 8) {
            Text(headerTitle)
                .font(MinikPretty.titleFont(titleSize))
                .foregroundStyle(MinikPretty.navy)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                // Kept clear of the X on both sides, so the title stays centred.
                .padding(.horizontal, compact ? 32 : 44)
                .accessibilityAddTraits(.isHeader)

            Text(headerSubtitle)
                .font(.system(size: subtitleSize))
                .foregroundStyle(MinikPretty.softInk)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, compact ? 26 : 32)
        .padding(.bottom, compact ? 16 : 20)
        .background {
            LinearGradient(
                colors: [Self.headerLavender, Self.headerPink, Self.headerSky],
                startPoint: UnitPoint.leading,
                endPoint: UnitPoint.trailing
            )
            .ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                MinikArtworkImage(name: MinikVisualAsset.close)
                    .frame(width: compact ? 28 : 34, height: compact ? 28 : 34)
                    .frame(width: compact ? 46 : 56, height: compact ? 46 : 56)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Done"))
            .padding(.top, compact ? 8 : 10)
            .padding(.trailing, compact ? 8 : 10)
        }
    }

    /// Android's phone tabs: a lavender track with a white rim; the chosen board's
    /// name is navy with a purple underline, the other's soft ink.
    private var boardTabs: some View {
        HStack(spacing: 0) {
            boardTab(.score)
            boardTab(.correctAnswersStreak)
        }
        .padding(.horizontal, 6)
        .frame(minHeight: 52)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(MinikPretty.lavender)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white, lineWidth: 2)
        }
        .accessibilityElement(children: .contain)
    }

    private func boardTab(_ type: RemoteRecordType) -> some View {
        let selected = selectedBoard == type
        return Button {
            selectedBoard = type
        } label: {
            Text(boardTitle(type))
                .font(MinikPretty.titleFont(min(tabFontSize, 24)))
                .foregroundStyle(selected ? MinikPretty.navy : MinikPretty.softInk)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) {
                    if selected {
                        Capsule(style: .continuous)
                            .fill(MinikPretty.purple)
                            .frame(height: 3)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 46)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// The tabs show once the boards have records and do not fit side by side.
    private func showsBoardTabs(_ metrics: MinikHomeLayoutMetrics) -> Bool {
        guard case .loaded(let snapshot) = model.state, !snapshot.isEmpty else { return false }
        return !showsBoardsSideBySide(metrics)
    }

    @ViewBuilder
    private func content(metrics: MinikHomeLayoutMetrics) -> some View {
        switch model.state {
        case .idle, .loading:
            ProgressView()
                .controlSize(.large)
                .tint(MinikPretty.purple)
                .frame(maxWidth: .infinity, minHeight: 160)
                .accessibilityLabel(String(localized: "Loading records"))
        case .notConfigured:
            unavailableMessage(
                String(localized: "Remote records are not configured for this build."),
                compact: metrics.compact,
                canRetry: false
            )
        case .failed:
            unavailableMessage(
                String(localized: "The records could not be loaded."),
                compact: metrics.compact,
                canRetry: true
            )
        case .loaded(let snapshot):
            if snapshot.isFromCache {
                Label("Showing saved records while offline.", systemImage: "wifi.slash")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MinikPretty.softInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if snapshot.isEmpty {
                emptyBoard(compact: metrics.compact)
            } else if showsBoardsSideBySide(metrics) {
                // On an iPad the two boards fit beside each other, as in Android's
                // tablet dialog, so both Top 20 lists show without tabs.
                HStack(alignment: .top, spacing: 16) {
                    board(.score, rows: scoreRows(in: snapshot), compact: metrics.compact, titled: true)
                    board(.correctAnswersStreak, rows: streakRows(in: snapshot), compact: metrics.compact, titled: true)
                }
            } else {
                board(selectedBoard, rows: rows(of: selectedBoard, in: snapshot), compact: metrics.compact, titled: false)
            }
        }
    }

    /// Side by side only where each board keeps a comfortable width (iPad), and
    /// not at accessibility text sizes, whose rows need the full width.
    private func showsBoardsSideBySide(_ metrics: MinikHomeLayoutMetrics) -> Bool {
        !metrics.compact && !dynamicTypeSize.isAccessibilitySize && metrics.contentMaxWidth >= 680
    }

    /// One board's rows. Side by side each board is named by its section pill; on
    /// phones the tabs name it.
    private func board(
        _ type: RemoteRecordType,
        rows: [RecordRow],
        compact: Bool,
        titled: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            if titled {
                MinikSectionPill(title: boardTitle(type), systemImage: boardSymbol(type))
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 4)
            }
            if rows.isEmpty {
                emptyBoard(compact: compact)
            } else {
                ForEach(rows) { row in
                    recordRow(row, type: type)
                        .id(rowScrollID(type: type, row: row))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Android's records_tab_score and records_tab_streak, in the interface language
    /// like the rest of the card.
    private func boardTitle(_ type: RemoteRecordType) -> String {
        switch type {
        case .score: return interfaceLocaleID.text("Scores")
        case .correctAnswersStreak: return interfaceLocaleID.text("Best streaks")
        }
    }

    private func boardSymbol(_ type: RemoteRecordType) -> String {
        switch type {
        case .score: return "star.fill"
        case .correctAnswersStreak: return "flame.fill"
        }
    }

    private func rows(of type: RemoteRecordType, in snapshot: RemoteRecordsSnapshot) -> [RecordRow] {
        switch type {
        case .score: return scoreRows(in: snapshot)
        case .correctAnswersStreak: return streakRows(in: snapshot)
        }
    }

    private func scoreRows(in snapshot: RemoteRecordsSnapshot) -> [RecordRow] {
        recordRows(
            type: .score,
            entries: snapshot.scoreRecords.map {
                (publicAlias: $0.publicAlias, avatarID: $0.avatarID, value: $0.score)
            }
        )
    }

    private func streakRows(in snapshot: RemoteRecordsSnapshot) -> [RecordRow] {
        recordRows(
            type: .correctAnswersStreak,
            entries: snapshot.streakRecords.map {
                (publicAlias: $0.publicAlias, avatarID: $0.avatarID, value: $0.correctAnswersInRow)
            }
        )
    }

    /// As on Android, a Top 20 without a new record opens on the streaks when only
    /// they have records.
    private func showStreaksWhenOnlyTheyExist(in state: RecordsLeaderboardViewModel.State) {
        guard highlightedPlacements.isEmpty,
              case .loaded(let snapshot) = state,
              snapshot.scoreRecords.isEmpty,
              !snapshot.streakRecords.isEmpty else { return }
        selectedBoard = .correctAnswersStreak
    }

    /// A new record often ranks below the first screenful (with larger text an
    /// iPad mini shows little more than the first dozen ranks), so its
    /// highlighted row is scrolled into view once the boards load.
    private func scrollToHighlightedRow(
        in state: RecordsLeaderboardViewModel.State,
        using proxy: ScrollViewProxy
    ) {
        guard case .loaded(let snapshot) = state,
              let target = highlightedRowScrollID(in: snapshot) else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.4)) {
            proxy.scrollTo(target, anchor: .center)
        }
    }

    private func highlightedRowScrollID(in snapshot: RemoteRecordsSnapshot) -> String? {
        if let row = scoreRows(in: snapshot).first(where: { $0.isHighlighted }) {
            return rowScrollID(type: .score, row: row)
        }
        if let row = streakRows(in: snapshot).first(where: { $0.isHighlighted }) {
            return rowScrollID(type: .correctAnswersStreak, row: row)
        }
        return nil
    }

    private func rowScrollID(type: RemoteRecordType, row: RecordRow) -> String {
        "\(type.rawValue).\(row.position)"
    }

    /// Android's empty board: no records yet, in the card's navy and soft ink.
    private func emptyBoard(compact: Bool) -> some View {
        VStack(spacing: 8) {
            MinikArtworkImage(name: MinikVisualAsset.trophy)
                .frame(width: compact ? 52 : 64, height: compact ? 52 : 64)
            Text("No records yet")
                .font(MinikPretty.titleFont(min(tabFontSize, 24)))
                .foregroundStyle(MinikPretty.navy)
            Text("New records will appear here.")
                .font(.subheadline)
                .foregroundStyle(MinikPretty.softInk)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, minHeight: 160)
        .accessibilityElement(children: .combine)
    }

    private func unavailableMessage(_ message: String, compact: Bool, canRetry: Bool) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.icloud.fill")
                .font(.system(size: compact ? 38 : 46, weight: .bold))
                .foregroundStyle(MinikPretty.purple)
                .accessibilityHidden(true)
            Text(message)
                .font(.body.weight(.medium))
                .foregroundStyle(MinikPretty.navy)
                .multilineTextAlignment(.center)
            if canRetry {
                Button("Try again") {
                    Task { await model.load() }
                }
                .buttonStyle(MinikPrettyButtonStyle(.white))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }

    /// item_leaderboard_record: a white card with a lavender rim, the rank badge at
    /// the start, the navy name and the value at the end. A new record's row is
    /// gold-rimmed on a warm white with Android's "New" badge.
    private func recordRow(_ row: RecordRow, type: RemoteRecordType) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // At accessibility sizes the value moves under the name, so the
                // rank, the name and the value each keep a readable width.
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .center, spacing: 10) {
                        rankBadge(row)
                        nameLabel(row, maximumLines: 2)
                    }
                    valueText(row, type: type)
                        .padding(.leading, rankColumnWidth + 10)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 10) {
                    rankBadge(row)
                    nameLabel(row, maximumLines: 2)
                    Spacer(minLength: 8)
                    valueText(row, type: type)
                }
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 58)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(row.isHighlighted ? Self.newRowFill : Color.white)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    row.isHighlighted ? Self.newRowRim : Self.rowRim,
                    lineWidth: row.isHighlighted ? 2 : 1.5
                )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: row))
        .accessibilityValue(row.isHighlighted ? interfaceLocaleID.text("New") : "")
    }

    /// Gold, silver and bronze for the first three places; the design's lavender
    /// with a purple rim for the others.
    private func rankBadge(_ row: RecordRow) -> some View {
        let colors = RecordRankBadgeColors.forRank(row.rank)
        return Text(row.rank.formatted())
            .font(MinikPretty.titleFont(rankFontSize))
            .monospacedDigit()
            .foregroundStyle(colors.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(.horizontal, 3)
            .frame(width: rankColumnWidth, height: rankColumnWidth)
            .background(colors.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(colors.rim, lineWidth: 1.5)
            }
    }

    /// The name wraps onto a second line rather than being cut, and the "New"
    /// badge sits under it, so a new record's name keeps the row's full width on
    /// a 375-point iPhone (the owner's QA, 25 October 2026).
    private func nameLabel(_ row: RecordRow, maximumLines: Int) -> some View {
        HStack(spacing: 7) {
            if let avatar = row.avatar {
                Image(systemName: avatar.symbolName)
                    .font(.system(size: nameFontSize, weight: .semibold))
                    .foregroundStyle(MinikPretty.purple)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(displayName(for: row))
                    .font(MinikPretty.bodyFont(nameFontSize))
                    .foregroundStyle(MinikPretty.navy)
                    .multilineTextAlignment(.leading)
                    .lineLimit(maximumLines)
                    .minimumScaleFactor(0.7)
                if row.isHighlighted {
                    newRecordBadge
                }
            }
            .layoutPriority(1)
        }
    }

    /// records_new_badge: "New" on gold under the new record's name.
    private var newRecordBadge: some View {
        Text(interfaceLocaleID.text("New"))
            .font(.caption2.weight(.bold))
            .foregroundStyle(RecordRankBadgeColors.gold.ink)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(RecordRankBadgeColors.gold.fill, in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(RecordRankBadgeColors.gold.rim, lineWidth: 1)
            }
            .accessibilityHidden(true)
    }

    /// The value is never wrapped or cut; the name gives way instead. Scores are
    /// purple and streaks teal, as on Android.
    private func valueText(_ row: RecordRow, type: RemoteRecordType) -> some View {
        Text(row.value.formatted())
            .font(MinikPretty.titleFont(valueFontSize))
            .monospacedDigit()
            .foregroundStyle(type == .score ? Self.scoreInk : Self.streakInk)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    /// Android's records_dialog_subtitle, or its congratulation when the table
    /// holds the child's new record.
    private var headerSubtitle: String {
        if highlightedPlacements.isEmpty {
            return interfaceLocaleID.text("The highest scores and longest correct-answer streaks")
        }
        return interfaceLocaleID.text("Great job! Your result is highlighted in the table.")
    }

    /// bg_records_dialog_header: #EDE6FF, #F9E8F4 and #E2F4FF.
    private static let headerLavender = MinikPretty.color(0xEDE6FF)
    private static let headerPink = MinikPretty.color(0xF9E8F4)
    private static let headerSky = MinikPretty.color(0xE2F4FF)
    /// The rows' lavender rim; a new record's row is gold-rimmed on #FFFBED.
    private static let rowRim = MinikPretty.color(0xE6DEFF)
    private static let newRowFill = MinikPretty.color(0xFFFBED)
    private static let newRowRim = MinikPretty.color(0xE2B43B)
    /// records_score_text #4938B5 and records_streak_text #009688.
    private static let scoreInk = MinikPretty.color(0x4938B5)
    private static let streakInk = MinikPretty.color(0x009688)

    /// Public names arrive as published by either platform (PublicLeaderboardAlias.validatedRemoteAlias);
    /// only an empty or unsafe name shows as "Player".
    private func displayName(for row: RecordRow) -> String {
        row.publicAlias.isEmpty ? String(localized: "Player") : row.publicAlias
    }

    /// In the interface language, like the subtitle under it.
    private var headerTitle: String {
        let types = Set(highlightedPlacements.map(\.type))
        if types == [.score, .correctAnswersStreak] {
            return interfaceLocaleID.text("Two new records!")
        }
        if types == [.score] {
            return interfaceLocaleID.text("New score record!")
        }
        if types == [.correctAnswersStreak] {
            return interfaceLocaleID.text("New streak record!")
        }
        return interfaceLocaleID.text("Top 20 records")
    }

    /// Equal values share a rank, the same way a new placement's position is
    /// computed, so the highlight lands on the row that holds the new record.
    private func recordRows(
        type: RemoteRecordType,
        entries: [(publicAlias: String, avatarID: String?, value: Int64)]
    ) -> [RecordRow] {
        entries.enumerated().map { index, entry in
            let rank = entries.filter { $0.value > entry.value }.count + 1
            return RecordRow(
                position: index,
                rank: rank,
                publicAlias: entry.publicAlias,
                avatarID: entry.avatarID,
                value: entry.value,
                isHighlighted: highlightedPlacements.contains {
                    $0.type == type && $0.position == rank && $0.value == entry.value
                }
            )
        }
    }

    private func accessibilityLabel(for row: RecordRow) -> String {
        String(
            format: String(localized: "Rank %lld: %@, %lld"),
            Int64(row.rank),
            displayName(for: row),
            row.value
        )
    }
}

private struct RecordRow: Identifiable {
    let position: Int
    let rank: Int
    let publicAlias: String
    let avatarID: String?
    let value: Int64
    let isHighlighted: Bool

    var id: Int { position }
    var avatar: PublicLeaderboardAvatar? {
        avatarID.flatMap(PublicLeaderboardAvatar.init(rawValue:))
    }
}

/// Android's rank badge colours (records_rank_* and records_score_*): fill, rim
/// and number.
private struct RecordRankBadgeColors {
    let fill: Color
    let rim: Color
    let ink: Color

    static func forRank(_ rank: Int) -> RecordRankBadgeColors {
        switch rank {
        case 1: return gold
        case 2: return silver
        case 3: return bronze
        default: return lavender
        }
    }

    /// #FFF3C4, #E2B43B, #7A5700.
    static let gold = RecordRankBadgeColors(
        fill: MinikPretty.color(0xFFF3C4),
        rim: MinikPretty.color(0xE2B43B),
        ink: MinikPretty.color(0x7A5700)
    )
    /// #F1F3F5, #C7CDD4, #56606B.
    static let silver = RecordRankBadgeColors(
        fill: MinikPretty.color(0xF1F3F5),
        rim: MinikPretty.color(0xC7CDD4),
        ink: MinikPretty.color(0x56606B)
    )
    /// #FCE7D7, #D89A6A, #8D4619.
    static let bronze = RecordRankBadgeColors(
        fill: MinikPretty.color(0xFCE7D7),
        rim: MinikPretty.color(0xD89A6A),
        ink: MinikPretty.color(0x8D4619)
    )
    /// The design's lavender with a purple rim: #F7F5FF, #8B7CF6, #6253C5.
    static let lavender = RecordRankBadgeColors(
        fill: MinikPretty.color(0xF7F5FF),
        rim: MinikPretty.color(0x8B7CF6),
        ink: MinikPretty.color(0x6253C5)
    )
}

/// When the Top 20 may open by itself (Android IntroFragment.recordsAutoShowAllowed):
/// at most once per launch, after the opening, and only while "show automatically"
/// is on (the default) and the child has at least 100 points. Right after the
/// opening song, before the child had played, it put too much weight on the high
/// scores. A new record a practice earned still opens it, as before.
enum RecordsAutoShowPolicy {
    static let minimumPoints: Int64 = 100
    private static let showsAutomaticallyKey = "minik.records.showAutomatically.v1"
    private static var hasShownThisLaunch = false

    static func showsAutomatically(userDefaults: UserDefaults = .standard) -> Bool {
        (userDefaults.object(forKey: showsAutomaticallyKey) as? Bool) ?? true
    }

    static func setShowsAutomatically(_ showsAutomatically: Bool, userDefaults: UserDefaults = .standard) {
        userDefaults.set(showsAutomatically, forKey: showsAutomaticallyKey)
    }

    /// True, once per launch, when the Top 20 should open by itself now; the
    /// caller then shows it.
    static func claimAutomaticShowing(points: Int64, userDefaults: UserDefaults = .standard) -> Bool {
        guard !hasShownThisLaunch,
              points >= minimumPoints,
              showsAutomatically(userDefaults: userDefaults) else {
            return false
        }
        hasShownThisLaunch = true
        return true
    }
}
