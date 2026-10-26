import SwiftUI

/// Android Minik Math Plus LearningProgressScreen (dc12a5c), opened from the Parent Area: what
/// was practised recently, per activity and level, with recent accuracy and completed rounds,
/// and one suggested next activity with a button that opens it. The records start with this
/// update; existing points stay as they are and no earlier history is made up.
struct MathLearningProgressView: View {
    let records: [MathPracticeRecord]
    let levelID: MathCurriculumLevelID
    let onPractice: (MathProductionActivityID) -> Void
    let onBack: () -> Void

    @State private var showsAll = false
    @State private var showsDetails = false

    init(
        records: [MathPracticeRecord],
        levelID: MathCurriculumLevelID,
        onPractice: @escaping (MathProductionActivityID) -> Void,
        onBack: @escaping () -> Void
    ) {
        self.records = records
        self.levelID = levelID
        self.onPractice = onPractice
        self.onBack = onBack
    }

    /// The newest practice first, without rows that only hold rounds.
    private var shownRecords: [MathPracticeRecord] {
        records.reversed().filter { $0.attempts > 0 }
    }

    private var suggestion: MathProductionActivityID {
        MathPracticeHistory.recommended(shownRecords, levelID: levelID)
    }

    private var levelNumber: Int {
        MathPracticeRecord(activity: suggestion, levelID: levelID).levelNumber
    }

    var body: some View {
        MinikHomeScreen { metrics in
            VStack(alignment: .leading, spacing: metrics.compact ? 16 : 20) {
                header(compact: metrics.compact)
                suggestionCard(compact: metrics.compact)

                ForEach(Array((showsAll ? shownRecords : Array(shownRecords.prefix(6))).enumerated()), id: \.offset) { _, record in
                    recordCard(record, compact: metrics.compact)
                }

                if shownRecords.count > 6 {
                    Button {
                        showsAll.toggle()
                    } label: {
                        Text(showsAll
                            ? String(localized: "Show recent practice only")
                            : String(localized: "Show earlier practice"))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(MinikUtilityButtonStyle())
                }

                Button {
                    showsDetails.toggle()
                } label: {
                    Text(String(localized: "About this summary"))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(MinikUtilityButtonStyle())
                .accessibilityAddTraits(showsDetails ? .isSelected : [])

                if showsDetails {
                    Text(String(localized: "Recorded on this device from this update onward. Accuracy uses the first answer to each question; pairs and memory use matching attempts. Soccer measures the answer, not the aim. Recent accuracy uses up to 20 attempts per activity and level. This is practice information, not a grade."))
                        .font(.body.weight(.medium))
                        .foregroundStyle(MinikPretty.navy)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// The title centred with the close X at the end, as on Progress & Statistics.
    private func header(compact: Bool) -> some View {
        let closeArtwork: CGFloat = compact ? 34 : 48
        let closeTarget: CGFloat = compact ? 48 : 56
        return VStack(spacing: 6) {
            ZStack {
                Text(String(localized: "Learning progress"))
                    .font(compact ? .title.bold() : .largeTitle.bold())
                    .foregroundStyle(MinikPretty.navy)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, closeTarget + 4)
                    .frame(maxWidth: .infinity)
                    .accessibilityAddTraits(.isHeader)

                Button(action: onBack) {
                    MinikArtworkImage(name: MinikVisualAsset.close)
                        .frame(width: closeArtwork, height: closeArtwork)
                        .frame(width: closeTarget, height: closeTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back to Parent Area")
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            Text(String(localized: "See recent practice and choose what to explore next."))
                .font(.body.weight(.medium))
                .foregroundStyle(MinikPretty.softInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
            if shownRecords.isEmpty {
                Text(String(localized: "A little practice will bring this page to life. Existing points stay safe; detailed learning records start with this update."))
                    .font(.body.weight(.medium))
                    .foregroundStyle(MinikPretty.navy)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
        }
    }

    private func suggestionCard(compact: Bool) -> some View {
        let needsPractice = MathPracticeHistory.needsPractice(suggestion, in: shownRecords, levelID: levelID)
        return MinikHomeSectionCard(compact: compact) {
            VStack(alignment: .leading, spacing: 10) {
                Text(String(localized: "Try next"))
                    .font(.headline.weight(.bold))
                    .foregroundStyle(MinikPretty.softInk)
                Text(verbatim: activityAndLevel(suggestion, level: levelNumber))
                    .font(.title3.bold())
                    .foregroundStyle(MinikPretty.navy)
                    .fixedSize(horizontal: false, vertical: true)
                Text(needsPractice
                    ? String(localized: "A little more practice here may help.")
                    : String(localized: "Explore an activity with fewer recorded answers at this level."))
                    .font(.body.weight(.medium))
                    .foregroundStyle(MinikPretty.navy)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    onPractice(suggestion)
                } label: {
                    Text(String(localized: "Practice this activity"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(MinikPrimaryActionStyle())
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func recordCard(_ record: MathPracticeRecord, compact: Bool) -> some View {
        MinikHomeSectionCard(compact: compact) {
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: activityAndLevel(record.activity, level: record.levelNumber))
                    .font(.headline.weight(.bold))
                    .foregroundStyle(MinikPretty.navy)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: accuracyLine(record))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(MinikPretty.navy)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: String(
                    format: String(localized: "Completed rounds / daily stages: %lld"),
                    Int64(record.rounds)
                ))
                .font(.body.weight(.medium))
                .foregroundStyle(MinikPretty.softInk)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    private func activityAndLevel(_ activity: MathProductionActivityID, level: Int) -> String {
        String(format: String(localized: "%@ · Level %lld"), activity.title, Int64(level))
    }

    private func accuracyLine(_ record: MathPracticeRecord) -> String {
        guard let accuracy = record.accuracy else {
            return String(
                format: String(localized: "Attempts so far: %lld · accuracy appears after 5"),
                Int64(record.attempts)
            )
        }
        return String(
            format: String(localized: "%lld%% correct · last %lld attempts"),
            Int64(accuracy),
            Int64(record.recent.count)
        )
    }
}
