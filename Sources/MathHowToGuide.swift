import SwiftUI

/// Text and tile colours for the Math activity screens: dark ink on light tiles
/// whatever the device's appearance. The tester's iPad ran in Dark Mode, which
/// turned every answer, digit and number card white on the white tiles.
enum MathInk {
    /// #2D2A6E, the navy text of the new Minik design.
    static let navy = Color(red: 0.176, green: 0.165, blue: 0.431)
    /// #5B4F72, secondary text.
    static let softInk = Color(red: 0.357, green: 0.310, blue: 0.447)
    /// #F1ECFF, the pale lavender fill.
    static let lavender = Color(red: 0.945, green: 0.925, blue: 1.0)
    /// #7C5CF2, the purple accent.
    static let purple = Color(red: 0.486, green: 0.361, blue: 0.949)
    /// The lavender rim around white tiles.
    static let rim = Color(red: 0.792, green: 0.745, blue: 0.976)
    /// Warm red-brown for "try again" hints.
    static let warning = Color(red: 0.73, green: 0.34, blue: 0.22)
}

/// One "How to play" explanation. Most follow the hub activity; Build Quantity
/// and the tower have one per mechanic, because each level builds them differently.
enum MathHowToTopic: String, CaseIterable, Sendable {
    case learnMath
    case mathCards
    case mathPairs
    case buildNumber
    case buildQuantity
    case buildQuantityGroups
    case buildQuantityFraction
    case buildQuantityNumberLine
    case visualToAnswer
    case answerToRepresentation
    case buildCount
    case buildMath
    case mathSoccer
    case mathTowerCount
    case mathTowerBlocks
    case mathMemory

    var activity: MathProductionActivityID {
        switch self {
        case .learnMath: return .learnMath
        case .mathCards: return .mathCards
        case .mathPairs: return .mathPairs
        case .buildNumber: return .buildNumber
        case .buildQuantity, .buildQuantityGroups, .buildQuantityFraction, .buildQuantityNumberLine:
            return .buildQuantity
        case .visualToAnswer: return .visualToAnswer
        case .answerToRepresentation: return .answerToRepresentation
        case .buildCount, .buildMath: return .buildMath
        case .mathSoccer: return .mathSoccer
        case .mathTowerCount, .mathTowerBlocks: return .mathTower
        case .mathMemory: return .mathMemory
        }
    }

    var explanationKey: String.LocalizationValue {
        switch self {
        case .learnMath:
            return "Each card teaches one math fact with a picture. Look at it, listen, and say it out loud. Then tap Next to see the next card."
        case .mathCards:
            // Android Math Plus ab3e427: sixteen rules with examples instead of the facts table.
            return "Tap a fact to hear the rule and its example. More facts shows another set of useful ideas."
        case .mathPairs:
            return "Every card has a partner that is worth the same. Tap a card on one side, then tap its partner on the other side. Tap a card again to unselect it."
        case .buildNumber:
            return "Look at the picture or the exercise at the top and find the answer. Tap a number card, or drag it, to put it in the answer box. For a bigger number, put its digits in order. Tap a number in the answer box to take it back. Then tap Check answer."
        case .buildQuantity:
            return "Look at the number or the exercise at the top. Tap the items below to add them to your group, one at a time, until your group has exactly that many. Tap an item in your group to take it out. Then press the green ✓ button."
        case .buildQuantityGroups:
            return "Build the amount shown at the top with the pieces below. Tap a piece to add it to your build, and tap a piece in your build to take it out. Then press the green ✓ button."
        case .buildQuantityFraction:
            return "Color the bar to show the amount at the top. Tap Add to color one more part and Undo to remove one. Then press the green ✓ button."
        case .buildQuantityNumberLine:
            return "Move the red dot along the number line with the arrow buttons until it stands on the number at the top. Then press the green ✓ button."
        case .visualToAnswer:
            // Android Math Plus ab3e427: a picture to count at every level.
            return "Count all the objects in the picture, then tap the matching number."
        case .answerToRepresentation:
            return "Look at the number at the top. Then tap the picture or the exercise that is worth exactly the same."
        case .buildCount:
            return "Count the pictures at the top. Tap the numbers in order, 1, 2, 3…, until every picture is counted. Tap a number in your answer to take it back. Then tap Check answer."
        case .buildMath:
            return "Build the whole exercise from the pieces: tap them in the right order. One piece is extra. Tap a piece in your answer to take it back. Then tap Check answer."
        case .mathSoccer:
            // Android Math Plus ab3e427: a tap chooses the ball, a swipe kicks it.
            return "Solve the question, then swipe the ball with the right answer toward the goal. The swipe aims the kick; a quicker swipe kicks faster. A tap only selects the ball. Wrong answers can be saved by Minik, and a kick aimed outside the goal misses."
        case .mathTowerCount:
            return "Build a tower with exactly as many blocks as the number at the top, or as the answer to the exercise at the top. Tap a block to add it, and tap a block in your tower to take it off. Then press the green ✓ button."
        case .mathTowerBlocks:
            return "Each block has a piece of the answer. Tap the blocks in the right order to build the answer. Tap a block in your answer to take it back. Then press the green ✓ button."
        case .mathMemory:
            return "All the cards are face down. Tap two cards to turn them over. If they are worth the same, they stay open. Find all the pairs!"
        }
    }
}

/// Counts how often each activity opened, in UserDefaults under
/// "minik.math.howto.<topic>". The first three openings show the fuller
/// "How to play" explanation; later ones go straight to the activity.
enum MathHowToProgress {
    static let keyPrefix = "minik.math.howto."
    static let guidedOpenings = 3

    static func storageKey(for topic: MathHowToTopic) -> String {
        keyPrefix + topic.rawValue
    }

    /// Whether the coming opening is still one of the first three. App Store
    /// screenshot captures never show the explanation.
    static func nextOpeningIsGuided(
        _ topic: MathHowToTopic?,
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard let topic, StoreScreenshotScene.name == nil else { return false }
        return defaults.integer(forKey: storageKey(for: topic)) < guidedOpenings
    }

    static func recordOpening(
        _ topic: MathHowToTopic?,
        defaults: UserDefaults = .standard
    ) {
        guard let topic, StoreScreenshotScene.name == nil else { return }
        let key = storageKey(for: topic)
        defaults.set(defaults.integer(forKey: key) + 1, forKey: key)
    }
}

extension View {
    /// Every Math activity screen: the light appearance whatever the device
    /// setting (dark text on light tiles), and the fuller "How to play" card the
    /// first three times the activity opens.
    func mathActivityChrome(howTo topic: MathHowToTopic?) -> some View {
        modifier(MathActivityChromeModifier(topic: topic))
    }
}

private struct MathActivityChromeModifier: ViewModifier {
    let topic: MathHowToTopic?
    @State private var showsHowTo: Bool
    @State private var openingRecorded = false

    init(topic: MathHowToTopic?) {
        self.topic = topic
        _showsHowTo = State(initialValue: MathHowToProgress.nextOpeningIsGuided(topic))
    }

    func body(content: Content) -> some View {
        content
            .environment(\.mathHowToIsShowing, showsHowTo && topic != nil)
            .overlay {
                if showsHowTo, let topic {
                    MathHowToCard(topic: topic, onStart: dismissHowTo)
                        .transition(.opacity)
                }
            }
            .environment(\.colorScheme, .light)
            .onAppear(perform: recordOpening)
    }

    private func recordOpening() {
        guard !openingRecorded else { return }
        openingRecorded = true
        MathHowToProgress.recordOpening(topic)
    }

    private func dismissHowTo() {
        withAnimation(.easeOut(duration: 0.2)) {
            showsHowTo = false
        }
    }
}

/// The "How to play" card over a dimmed activity: what the activity is, what to
/// do, a Listen button for children who do not read yet, and "Let's start!". With
/// Read aloud on, the card reads itself when it opens (Android HowToScreen).
private struct MathHowToCard: View {
    let topic: MathHowToTopic
    let onStart: () -> Void
    @StateObject private var speechPlayer = InterfaceSpeechPlayer()
    @Environment(\.interfaceLocaleID) private var interfaceLocaleID
    @Environment(\.mathReadAloudEnabled) private var readAloudEnabled
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var wide: Bool {
        horizontalSizeClass == .regular
    }

    private var explanation: String {
        String(localized: topic.explanationKey)
    }

    /// String(localized:) follows the app's own language, so the voice does too.
    private var speechLocale: InterfaceLocaleID {
        MathReadAloud.voiceLocale(fallback: interfaceLocaleID)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.34)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {}
                .accessibilityHidden(true)

            ViewThatFits(in: .vertical) {
                card
                ScrollView {
                    card
                        .padding(.vertical, 8)
                }
                .scrollIndicators(.hidden)
            }
            .padding(.horizontal, wide ? 40 : 16)
            .padding(.vertical, 20)
        }
        .onAppear {
            if readAloudEnabled { speak() }
        }
        .onDisappear {
            speechPlayer.stop()
        }
    }

    private var card: some View {
        VStack(spacing: wide ? 20 : 16) {
            ZStack {
                Circle()
                    .fill(MathInk.lavender)
                    .frame(width: wide ? 84 : 68, height: wide ? 84 : 68)
                Image(systemName: topic.activity.symbolName)
                    .font(.system(size: wide ? 36 : 29, weight: .bold))
                    .foregroundStyle(MathInk.purple)
            }
            .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text(String(localized: "How to play"))
                    .font(.system(size: wide ? 32 : 26, weight: .bold, design: .rounded))
                    .foregroundStyle(MathInk.navy)
                Text(topic.activity.title)
                    .font(.system(size: wide ? 21 : 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(MathInk.softInk)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            Text(explanation)
                .font(.system(size: wide ? 23 : 19, weight: .medium, design: .rounded))
                .foregroundStyle(MathInk.navy)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)

            Button(action: speak) {
                HStack(spacing: 8) {
                    MinikArtworkImage(name: MinikVisualAsset.speaker)
                        .frame(width: 30, height: 30)
                    Text(String(localized: "Listen"))
                }
            }
            .buttonStyle(MinikUtilityButtonStyle())

            Button(action: start) {
                Text(String(localized: "Let's start!"))
            }
            .buttonStyle(MinikPrimaryActionStyle())
        }
        .padding(wide ? 34 : 22)
        .frame(maxWidth: wide ? 600 : 460)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(MathInk.rim, lineWidth: 2)
        }
        .shadow(color: MathInk.navy.opacity(0.22), radius: 24, y: 12)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private func speak() {
        speechPlayer.speak(explanation, interfaceLocale: speechLocale)
    }

    private func start() {
        speechPlayer.stop()
        onStart()
    }
}
