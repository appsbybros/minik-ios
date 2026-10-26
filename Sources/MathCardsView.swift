import SwiftUI

/// Android Minik Math Plus FactsTableScreen (ab3e427): Math Cards gives sixteen useful rules,
/// each with an example, four to a page, where it used to show the level's facts. More facts
/// turns to the next four. A tap marks the card and reads the rule and its example aloud in
/// the interface language. Learn Math still teaches the level's own facts, one per screen.
struct MathCardsView: View {
    @State private var page = 0
    @State private var chosenCard: MathRuleCard?
    @StateObject private var speechPlayer = InterfaceSpeechPlayer()
    @Environment(\.interfaceLocaleID) private var interfaceLocaleID
    private let onExit: () -> Void

    /// The level's study cards are no longer shown; the session stays in the signature so the
    /// level screens keep building this activity the same way.
    init(session: CardsSession, onExit: @escaping () -> Void = {}) {
        _ = session
        self.onExit = onExit
    }

    var body: some View {
        MinikPracticeScreen(
            progressLabel: "\(page + 1) / \(MathRuleCard.pageCount)",
            onExit: exit
        ) { metrics in
            MinikPracticeSurface(compact: metrics.compact) {
                VStack(spacing: metrics.compact ? 12 : 16) {
                    header(compact: metrics.compact)

                    ForEach(MathRuleCard.page(page), id: \.self) { card in
                        ruleCard(card, compact: metrics.compact)
                    }

                    Button(action: showMoreFacts) {
                        Label(String(localized: "More facts"), systemImage: "arrow.forward")
                    }
                    .buttonStyle(MinikPrimaryActionStyle())
                    .padding(.top, 4)
                }
            }
        }
        .onDisappear(perform: speechPlayer.stop)
    }

    private func header(compact: Bool) -> some View {
        VStack(spacing: 6) {
            Text(MathProductionActivityID.mathCards.title)
                .font(.system(size: compact ? 22 : 27, weight: .bold, design: .rounded))
                .foregroundStyle(MathInk.navy)
            Text(String(localized: "Tap a fact to hear it and its example."))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MathInk.softInk)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// The rule at the start of the line (the right in Hebrew), its example under it, read
    /// left to right as every exercise is.
    private func ruleCard(_ card: MathRuleCard, compact: Bool) -> some View {
        let chosen = chosenCard == card
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return Button {
            play(card)
        } label: {
            VStack(spacing: compact ? 8 : 10) {
                Text(card.rule)
                    .font(.system(size: compact ? 18 : 21, weight: .semibold, design: .rounded))
                    .foregroundStyle(MathInk.navy)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(verbatim: card.example)
                    .font(.system(size: compact ? 24 : 29, weight: .bold, design: .rounded))
                    .foregroundStyle(MathInk.navy)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity)
                    .environment(\.layoutDirection, .leftToRight)
            }
            .padding(.horizontal, compact ? 14 : 18)
            .padding(.vertical, compact ? 12 : 16)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(shape.fill(chosen ? MathInk.lavender : Color.white))
            .overlay {
                shape.strokeBorder(chosen ? MathInk.purple : MathInk.rim, lineWidth: chosen ? 3 : 1.5)
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: "\(card.rule) \(MathReadAloud.spokenExercise(card.example))"))
        .accessibilityHint(String(localized: "Plays this fact aloud"))
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    private func play(_ card: MathRuleCard) {
        chosenCard = card
        MathReadAloud.say(
            MathReadAloud.text(instruction: card.rule, exercise: card.example),
            with: speechPlayer,
            fallback: interfaceLocaleID
        )
    }

    private func showMoreFacts() {
        speechPlayer.stop()
        chosenCard = nil
        page = (page + 1) % MathRuleCard.pageCount
    }

    private func exit() {
        speechPlayer.stop()
        onExit()
    }
}
