import SwiftUI

struct ProgressStatisticsView: View {
    let model: EducationalProgressReadModel
    let onBack: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale

    var body: some View {
        MinikHomeScreen { metrics in
            VStack(alignment: .leading, spacing: metrics.compact ? 18 : 24) {
                header(compact: metrics.compact)

                if model.product == .minikMath {
                    mathStatus(compact: metrics.compact)
                }

                if model.isEmpty {
                    emptyState(compact: metrics.compact)
                } else {
                    overview(compact: metrics.compact, width: metrics.contentMaxWidth)
                    activityProgress(compact: metrics.compact)
                }
            }
        }
    }

    /// The title centred on the screen with the red close X at the end (the left in
    /// Hebrew), as on the other screens; the subtitle below says where this is kept.
    private func header(compact: Bool) -> some View {
        let closeArtwork: CGFloat = compact ? 34 : 48
        let closeTarget: CGFloat = compact ? 44 : 56
        return VStack(spacing: 6) {
            ZStack {
                // The same inset on both sides keeps the title centred on the screen
                // and clear of the close button.
                Text("Progress & Statistics")
                    .font(compact ? .title.bold() : .largeTitle.bold())
                    .foregroundStyle(Color(red: 0.11, green: 0.36, blue: 0.45))
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
                .accessibilityHint("Returns to learning settings")
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            Text("A clear view of practice completed on this device. This information is saved only on this device, not online.")
                .font(.body.weight(.medium))
                .foregroundStyle(Color(red: 0.31, green: 0.49, blue: 0.57))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
        }
    }

    private func emptyState(compact: Bool) -> some View {
        MinikHomeSectionCard(compact: compact) {
            ContentUnavailableView {
                Label("No practice yet", systemImage: "chart.bar.xaxis")
            } description: {
                Text("Completed educational attempts will appear here after practice.")
            }
        }
    }

    private func mathStatus(compact: Bool) -> some View {
        MinikHomeSectionCard(compact: compact) {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeading("Math progress", symbol: "function")
                LabeledContent("Current level", value: mathLevelTitle)
                LabeledContent("Level mode", value: mathModeTitle)
            }
        }
    }

    private func overview(compact: Bool, width: CGFloat) -> some View {
        MinikHomeSectionCard(compact: compact) {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeading("Overview", symbol: "chart.pie")
                LazyVGrid(columns: metricColumns(width: width), spacing: 12) {
                    metricCard("Practice attempts", value: model.totalAttempts.formatted())
                    metricCard("First-attempt correct", value: model.firstAttemptCorrectCount.formatted())
                    metricCard("First-attempt accuracy", value: accuracyText(model.firstAttemptAccuracy))
                    metricCard("Practice time", value: durationText(model.practiceDurationSeconds))
                }
            }
        }
    }

    private func activityProgress(compact: Bool) -> some View {
        MinikHomeSectionCard(compact: compact) {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeading("By activity", symbol: "square.grid.2x2")
                ForEach(model.activityRows) { row in
                    VStack(alignment: .leading, spacing: 7) {
                        Text(row.title).font(.headline)
                        // One line of three figures, or one figure per line when
                        // larger text would otherwise wrap them mid-word.
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 14) {
                                activityFigures(row)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                activityFigures(row)
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)

                    if row.id != model.activityRows.last?.id { Divider() }
                }
            }
        }
    }

    @ViewBuilder
    private func activityFigures(_ row: EducationalActivityProgressRow) -> some View {
        Label(
            String(format: String(localized: "%lld attempts"), Int64(row.totalAttempts)),
            systemImage: "checklist"
        )
        Label(accuracyText(row.firstAttemptAccuracy), systemImage: "target")
        Label(durationText(row.practiceDurationSeconds), systemImage: "timer")
    }

    private func metricCard(_ title: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            // A figure stays on one line and shrinks rather than wrapping.
            Text(value)
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(Color(red: 0.11, green: 0.36, blue: 0.45))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .padding(12)
        .background(.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func sectionHeading(_ title: LocalizedStringKey, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.headline.weight(.bold))
            .foregroundStyle(Color(red: 0.14, green: 0.39, blue: 0.49))
    }

    private func metricColumns(width: CGFloat) -> [GridItem] {
        if dynamicTypeSize.isAccessibilitySize || width < 420 {
            return [GridItem(.flexible())]
        }
        return [GridItem(.flexible()), GridItem(.flexible())]
    }

    private var mathLevelTitle: String {
        guard let id = model.mathLevelID else { return String(localized: "Not available") }
        return MathCurriculumPolicy.level(for: id)?.title ?? String(localized: "Not available")
    }

    private var mathModeTitle: String {
        switch model.mathLevelMode {
        case .automatic: return String(localized: "Automatic")
        case .manual: return String(localized: "Manual")
        case .none: return String(localized: "Not available")
        }
    }

    private func accuracyText(_ accuracy: Double?) -> String {
        guard let accuracy else { return String(localized: "Not available") }
        return accuracy.formatted(.percent.precision(.fractionLength(0)))
    }

    private func durationText(_ seconds: Double) -> String {
        let formatter = DateComponentsFormatter()
        var calendar = Calendar.current
        calendar.locale = locale
        formatter.calendar = calendar
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter.string(from: max(0, seconds)) ?? String(localized: "Not available")
    }
}
