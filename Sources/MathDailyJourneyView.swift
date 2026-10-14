import SwiftUI

/// Android Minik Math Plus MathDailyScreen (7682b75): the daily math journey's page, in the
/// rainbow-sky design of the Math hub. Before a stage it names the activity of the day and
/// what it asks for, the correct answers so far out of the goal, how the challenge works and
/// the practice stars, with Let's start!. After a stage it celebrates, with Next skill. The
/// activity opens as from the hub, with the progress line above it (MinikActivityHubView).
///
/// Android shows the activity's full "how to play" text here; the iOS Math activities explain
/// themselves per level in their own How to play card, so this page gives the activity's short
/// description instead.
struct MathDailyJourneyView: View {
    let state: MathDailyJourneyState
    let isFinished: Bool
    let onStart: () -> Void
    let onNext: () -> Void
    let onClose: () -> Void

    @ScaledMetric(relativeTo: .body) private var textPercent: CGFloat = 100

    init(
        state: MathDailyJourneyState,
        isFinished: Bool,
        onStart: @escaping () -> Void,
        onNext: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.state = state
        self.isFinished = isFinished
        self.onStart = onStart
        self.onNext = onNext
        self.onClose = onClose
    }

    var body: some View {
        GeometryReader { geometry in
            let tablet = min(geometry.size.width, geometry.size.height) >= 600
            let margin: CGFloat = tablet ? 32 : 12
            let panelWidth = max(1, min(tablet ? 760 : 620, geometry.size.width - 2 * margin))
            let radius: CGFloat = tablet ? 36 : 28
            VStack(spacing: 0) {
                header(tablet: tablet)
                MinikGlassPanel(padding: 0, cornerRadius: radius) {
                    VStack(spacing: 0) {
                        ScrollView {
                            pageContent(tablet: tablet)
                                .padding(.horizontal, tablet ? 28 : 18)
                                .padding(.top, tablet ? 22 : 14)
                                .padding(.bottom, 10)
                        }
                        .scrollBounceBehavior(.basedOnSize)
                        .scrollIndicators(.hidden)

                        actionButton(tablet: tablet)
                            .padding(.horizontal, tablet ? 28 : 18)
                            .padding(.top, 8)
                            .padding(.bottom, tablet ? 24 : 16)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                }
                .frame(width: panelWidth)
                .frame(maxHeight: .infinity)
                .padding(.top, tablet ? 14 : 8)
                .padding(.bottom, tablet ? 18 : 10)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
        // A background never sizes the layout (see MinikHomeScreen).
        .background {
            MinikSkyBackground()
        }
    }

    /// The close button at the start and the navy title, on the sky.
    private func header(tablet: Bool) -> some View {
        ZStack {
            Text(verbatim: String(localized: "Daily math journey"))
                .font(MinikPretty.titleFont((tablet ? 34 : 26) * textScale))
                .foregroundStyle(MinikPretty.navy)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, tablet ? 76 : 56)
                .accessibilityAddTraits(.isHeader)

            HStack {
                Button(action: onClose) {
                    MinikArtworkImage(name: MinikVisualAsset.close)
                        .frame(width: tablet ? 44 : 38, height: tablet ? 44 : 38)
                        .frame(width: 48, height: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: String(localized: "Close")))
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, tablet ? 32 : 12)
        .padding(.top, tablet ? 14 : 6)
    }

    private func pageContent(tablet: Bool) -> some View {
        VStack(spacing: tablet ? 14 : 10) {
            MinikArtworkImage(name: MinikPretty.Art.welcome)
                .frame(height: tablet ? 190 : 150)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)

            if isFinished {
                largeLine(String(localized: "A skill worth celebrating!"), size: 28, tablet: tablet)
                hintLine(
                    String(localized: "Your progress is saved. Come back for another small step, or try the next skill now."),
                    tablet: tablet
                )
            } else {
                largeLine(state.activity.title, size: 26, tablet: tablet)
                hintLine(
                    String(localized: "A small challenge, using the games you know. Each correct first answer moves you forward. Mistakes are a chance to learn; they never erase your progress."),
                    tablet: tablet
                )
                largeLine(
                    String(
                        format: String(localized: "Correct answers: %lld of %lld"),
                        Int64(state.answers),
                        Int64(state.goal)
                    ),
                    size: 24,
                    tablet: tablet
                )
                hintLine(
                    String(localized: "The challenge follows your chosen learning level. Your first completed stage each day earns a bonus. You can keep playing, and taking a day off is fine."),
                    tablet: tablet
                )
                Text(verbatim: state.activity.subtitle)
                    .font(MinikPretty.bodyFont((tablet ? 22 : 18) * textScale))
                    .foregroundStyle(MinikPretty.navy)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(tablet ? 14 : 10)
                    .background {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(MinikPretty.lavender)
                    }
            }

            hintLine(
                String(format: String(localized: "Practice stars: %lld"), Int64(state.stars)),
                tablet: tablet
            )
        }
        .frame(maxWidth: .infinity)
    }

    private func largeLine(_ text: String, size: CGFloat, tablet: Bool) -> some View {
        Text(verbatim: text)
            .font(MinikPretty.titleFont(size * (tablet ? 1.25 : 1) * textScale))
            .foregroundStyle(MinikPretty.navy)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
    }

    private func hintLine(_ text: String, tablet: Bool) -> some View {
        Text(verbatim: text)
            .font(MinikPretty.bodyFont((tablet ? 20 : 16) * textScale))
            .foregroundStyle(MinikPretty.softInk)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
    }

    /// Let's start! opens the activity of the day; after a stage, Next skill shows the next one.
    private func actionButton(tablet: Bool) -> some View {
        Button(action: isFinished ? onNext : onStart) {
            Text(verbatim: isFinished ? String(localized: "Next skill") : String(localized: "Let's start!"))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(MinikPretty.HeroButtonStyle(
            look: MinikPretty.PillLook.blue,
            fontSize: (tablet ? 26 : 21) * textScale,
            minHeight: tablet ? 66 : 56
        ))
    }

    /// Dynamic Type for the page's text, within what its layout holds.
    private var textScale: CGFloat {
        min(1.3, max(0.9, textPercent / 100))
    }
}
