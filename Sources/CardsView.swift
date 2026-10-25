import SwiftUI

/// Android RandomWordCardsFragment (fragment_random_word_cards, phone and sw600dp):
/// meadow, X and wordmark, title, the gradient-framed white word card, the
/// once-per-process tap hint and the Minik mascot near the bottom. The whole page,
/// apart from the X, advances to the next word. As on Android there is no visible
/// replay control; VoiceOver keeps replay as a named action on the word.
struct CardsView: View {
    @State private var session: CardsSession
    @StateObject private var speechPlayer: LearningSpeechPlayer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    private let onExit: () -> Void

    init(
        session: CardsSession,
        onExit: @escaping () -> Void = {}
    ) {
        _session = State(initialValue: session)
        _speechPlayer = StateObject(wrappedValue: LearningSpeechPlayer())
        self.onExit = onExit
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var hintVisible = false
    @State private var hintStarted = false
    /// The large-title size at the current text size (34 points at the default size).
    @ScaledMetric(relativeTo: .largeTitle) private var accessibilityTitleSize: CGFloat = 34

    private struct AdvanceTaskKey: Equatable {
        let presentationID: UUID
        let active: Bool
    }

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 700
            // The page fills the screen and scrolls only when it is taller (as at
            // accessibility text sizes), so its bottom is never cut off.
            let pageLayout = CardsPageFillLayout(minimumHeight: geometry.size.height)
            ScrollView {
                pageLayout {
                    cardsPage(wide: wide, height: geometry.size.height)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        // A background never sizes the layout: as a sibling, the aspect-filled
        // meadow could make the page taller than the screen and push it down.
        .background {
            MinikArtworkImage(name: MinikVisualAsset.cardsBackground, contentMode: .fill)
                .ignoresSafeArea()
                .clipped()
        }
        .task(id: AdvanceTaskKey(presentationID: session.presentationID, active: scenePhase == .active)) {
            guard scenePhase == .active else { return }
            let presentationCardID = session.currentCard.id
            let presentationID = session.presentationID
            replayCurrentCard()
            do {
                try await Task.sleep(nanoseconds: displayDurationNanoseconds)
                guard !Task.isCancelled, scenePhase == .active else { return }
                advance(ifCurrentCardID: presentationCardID, presentationID: presentationID)
            } catch {
                // Backgrounding, dismissal or either advance cancels this presentation.
            }
        }
        .task {
            guard !hintStarted else { return }
            hintStarted = true
            hintVisible = LanguageCardsHintState.shared.claimFirstPresentation()
            guard hintVisible else { return }
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.8)) { hintVisible = false }
            } catch { }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { speechPlayer.stop() }
        }
        .onDisappear(perform: speechPlayer.stop)
    }

    /// Only accessibility text sizes (AX1-AX5) switch the fixed Android title and
    /// hint sizes to Dynamic Type; larger standard sizes keep the designed page.
    /// Both stay bold as on Android, and the title never drops below its designed
    /// size. The word keeps its Android size at every text size, since no Dynamic
    /// Type style is larger.
    private var usesAccessibilityTextSize: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    /// Android's 30/55 sp bold title (phone/sw600dp). Accessibility text sizes
    /// enlarge it like the large title, never below the designed size, so turning
    /// text up never shrinks the tablet title.
    private func titleSize(wide: Bool) -> CGFloat {
        let designed: CGFloat = wide ? 55 : 30
        guard usesAccessibilityTextSize else {
            return designed
        }
        return max(designed, accessibilityTitleSize)
    }

    /// Android runs the word change in sequence: the old word fades out over 180 ms
    /// as it shrinks to 90 percent, then the next one fades in from 112 percent over
    /// 280 ms with a slight overshoot (OvershootInterpolator 0.6, which the view's
    /// animator keeps, so later fade-outs decelerate too). The card stays in place.
    private var wordChangeTransition: AnyTransition {
        guard !reduceMotion else {
            return .identity
        }
        let wordIn = AnyTransition.opacity.combined(with: .scale(scale: 1.12))
        let wordOut = AnyTransition.opacity.combined(with: .scale(scale: 0.9))
        return .asymmetric(
            insertion: wordIn.animation(.spring(response: 0.28, dampingFraction: 0.8).delay(0.18)),
            removal: wordOut.animation(.easeOut(duration: 0.18))
        )
    }

    private func cardsPage(wide: Bool, height: CGFloat) -> some View {
        VStack(spacing: 0) {
            cardsHeader(wide: wide)
            VStack(spacing: 0) {
                // Android (phone/sw600dp): card 16/35 below the title, hint 45/85
                // below the card, mascot 33/83 above the bottom (35 on phones here).
                advanceSurface(wide: wide, height: height)
                    .padding(.top, wide ? 35 : 16)
                Text("Tap the word card to keep going.")
                    .font(usesAccessibilityTextSize ? .body.bold() : .system(size: wide ? 28 : 18, weight: .bold))
                    .foregroundStyle(Color(red: 0.024, green: 0.192, blue: 0.416).opacity(0.82))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
                    .padding(.top, wide ? 85 : 45)
                    .opacity(hintVisible ? 1 : 0)
                    .accessibilityHidden(true)
                Spacer(minLength: 24)
                // The mascot takes the free height up to its full size, and gives
                // some of it up on short screens before the page has to scroll.
                MinikArtworkImage(name: MinikVisualAsset.cardsMascot)
                    .frame(width: wide ? 300 : 200)
                    .frame(minHeight: wide ? 200 : 120, idealHeight: wide ? 200 : 120, maxHeight: wide ? 300 : 200)
                    .padding(.bottom, wide ? 83 : 35)
                    .accessibilityHidden(true)
                    .layoutPriority(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture(perform: advance)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default) { advance() }
        }
        .frame(maxWidth: 1000)
        .frame(maxWidth: .infinity)
    }

    /// Android puts the title 56/123 points below the top edge (phone/sw600dp),
    /// level with the lower part of the wordmark, and the X image 28/62 down.
    /// Owner QA (25 October 2026): the X and the wordmark sit half as far from the
    /// top and side edges as before, and the title a little lower, clear of the
    /// wordmark (60/129 points down).
    /// Android has only the X and the wordmark here: no speaker or replay button,
    /// since each word is spoken automatically.
    private func cardsHeader(wide: Bool) -> some View {
        ZStack(alignment: .top) {
            LanguagePanelNavigation(wide: wide, showsLogo: true,
                                    onReplay: nil, onExit: exit)
                .padding(.horizontal, wide ? 23 : 13)
            Text("Cards")
                .font(.system(size: titleSize(wide: wide), weight: .bold))
                .foregroundStyle(wide
                    ? Color(red: 0.875, green: 0.937, blue: 0.969)
                    : Color(red: 0.761, green: 0.937, blue: 0.976))
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, wide ? 105 : 56)
                // Clear of the wordmark and X beside it.
                .padding(.horizontal, wide ? 140 : 94)
                .allowsHitTesting(false)
        }
        .padding(.top, wide ? 24 : 4)
        // As on Android, a tap anywhere outside the X advances; the X keeps its
        // own tap.
        .contentShape(Rectangle())
        .onTapGesture(perform: advance)
    }

    private var speechPlan: LearningSpeechPlan {
        LearningSpeechPlan(card: session.currentCard)
    }

    private var displayDurationNanoseconds: UInt64 {
        let displayedText = session.currentCard.representations.compactMap { representation in
            guard case .learningText(let text) = representation else {
                return nil
            }
            return text.text
        }.first ?? ""
        let normalized = displayedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let visibleCharacterCount = normalized.filter { !$0.isWhitespace }.count
        let wordCount = max(
            1,
            normalized.split(whereSeparator: { $0.isWhitespace }).count
        )
        let milliseconds = min(
            11_000,
            max(4_500, 3_200 + visibleCharacterCount * 170 + (wordCount - 1) * 500)
        )
        return UInt64(milliseconds) * 1_000_000
    }

    private var displayedText: LearningTextRepresentation? {
        session.currentCard.representations.compactMap { representation in
            guard case .learningText(let text) = representation else { return nil }
            return text
        }.first
    }

    private func advanceSurface(wide: Bool, height: CGFloat) -> some View {
        let isSingleWord = !(displayedText?.text.contains(where: { $0.isWhitespace }) ?? false)
        let largeText = usesAccessibilityTextSize
        // Tablets use Android's sw600dp card: the gradient frame is 28 percent of the
        // height inside the 36 + 12 dp top and bottom paddings (156-330 dp) and 83 dp
        // from each side (578 x 278 on an iPad mini); the white card inside it is
        // 11 points shorter. Phones keep the owner's shorter short-word card (QA07:
        // 70 percent of the earlier 220-point card).
        let tabletFrameHeight = min(330, max(156, (height - 96) * 0.28))
        let singleWordCardHeight = wide ? tabletFrameHeight - 11 : min(154, max(104, height * 0.20))
        let cardHeight = isSingleWord ? singleWordCardHeight
            : min(wide ? 330 : 240, max(156, height * 0.30))
        // Android lineSpacingExtra 2/3 dp for phrases; the tablet word sits 5 dp
        // above the card's centre (translationY).
        let wordLineSpacing: CGFloat = wide ? 3 : 2
        let wordOffset: CGFloat = wide ? -5 : 0
        // Only the word changes identity, inside its own stack, so the card stays put.
        return ZStack {
            Group {
                if let text = displayedText {
                    // Words stay whole at every size: a single word shrinks to one line
                    // instead of wrapping letter by letter.
                    Text(verbatim: text.text)
                        .font(.system(size: wide ? 119 : 76))
                        .foregroundStyle(LinearGradient(colors: [
                            Color(red: 0.094, green: 0.467, blue: 0.949),
                            Color(red: 0, green: 0.749, blue: 0.847),
                            Color(red: 0.086, green: 0.651, blue: 0.416)
                        ], startPoint: UnitPoint(x: 0, y: 0.5), endPoint: UnitPoint(x: 1, y: 0.5)))
                        .environment(\.layoutDirection, text.direction == .rightToLeft ? .rightToLeft : .leftToRight)
                        .multilineTextAlignment(.center)
                        .lineSpacing(wordLineSpacing)
                        .lineLimit(isSingleWord ? 1 : 3)
                        .minimumScaleFactor(largeText ? 0.4 : 18.0 / 76)
                        .fixedSize(horizontal: false, vertical: largeText)
                        .offset(y: wordOffset)
                } else {
                    VStack(spacing: 12) {
                        ForEach(Array(session.currentCard.representations.enumerated()), id: \.offset) { _, representation in
                            RepresentationView(representation: representation, context: .cardsHero)
                        }
                    }
                }
            }
            .transition(wordChangeTransition)
            .id(session.presentationID)
        }
        .padding(.horizontal, wide ? 21 : 14)
        .padding(.vertical, wide ? 15 : 10)
        .frame(maxWidth: .infinity, minHeight: cardHeight)
        // Standard sizes keep the card's design height and fit the word inside it;
        // accessibility sizes let the card grow with the text.
        .frame(height: largeText ? nil : cardHeight)
        .fixedSize(horizontal: false, vertical: largeText)
        .background(.white, in: RoundedRectangle(cornerRadius: 14))
        .padding(EdgeInsets(top: wide ? 3 : 2, leading: wide ? 8 : 5,
                            bottom: wide ? 8 : 5, trailing: wide ? 3 : 2))
        // bg_minik_gradient_rounded: 12 dp corners around the 14 dp white card.
        .background(LanguagePalette.border, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, wide ? 83 : 32)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityHint("Double tap to advance to the next word")
        // Android has no replay control here; VoiceOver users can still hear the
        // word again.
        .accessibilityAction(named: "Replay current word") {
            replayCurrentCard()
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: session.presentationID)
    }

    private func replayCurrentCard() {
        speechPlayer.speak(speechPlan)
    }

    private func advance() {
        guard scenePhase == .active else { return }
        speechPlayer.stop()
        session.advance()
    }

    private func advance(ifCurrentCardID expectedCardID: StudyCardID, presentationID: UUID) {
        guard scenePhase == .active, session.currentCard.id == expectedCardID,
              session.presentationID == presentationID else {
            return
        }
        speechPlayer.stop()
        session.advance(ifPresentationID: presentationID)
    }

    private func exit() {
        speechPlayer.stop()
        onExit()
    }
}

@MainActor
private final class LanguageCardsHintState {
    static let shared = LanguageCardsHintState()
    private var alreadyShown = false
    func claimFirstPresentation() -> Bool {
        guard !alreadyShown else { return false }
        alreadyShown = true
        return true
    }
}

/// Gives the Cards page at least the screen's height, so its spacer and mascot
/// stretch to the bottom inside the scroll view, and its natural height when the
/// content needs more, so the page scrolls instead of being cut off.
private struct CardsPageFillLayout: Layout {
    let minimumHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let page = subviews.first else { return .zero }
        let natural = page.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: proposal.width ?? natural.width, height: max(minimumHeight, natural.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center,
                              proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}
