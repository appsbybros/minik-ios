import SwiftUI

/// Android Minik Math Plus Speech (df82abe): every instruction and exercise is read aloud
/// when it appears, and the how-to card when it opens, so children who cannot read yet know
/// what to do. The Parent Area's one "Read aloud" switch (Android AppState.speakAloud, on
/// until a grown-up turns it off) stops the automatic reading; the speaker and Listen buttons
/// still answer a tap.
enum MathReadAloud {
    /// Math's texts come from String(localized:), which follows the app's own language, so
    /// the voice does too, as the how-to card's Listen button already did.
    static func voiceLocale(fallback: InterfaceLocaleID) -> InterfaceLocaleID {
        Bundle.main.preferredLocalizations.first
            .flatMap { InterfaceLocaleID(languageTag: $0) } ?? fallback
    }

    /// Says `text` in Math's voice, with the locale's pronunciation fixes.
    @MainActor
    static func say(_ text: String, with player: InterfaceSpeechPlayer, fallback: InterfaceLocaleID) {
        guard !text.isEmpty else { return }
        let locale = voiceLocale(fallback: fallback)
        player.speak(locale.spokenText(for: text), interfaceLocale: locale)
    }

    /// Android Speech.speak(hint, exercise): the instruction, then the exercise with its
    /// symbols said as words ("3 + □ = 7" is read "3 plus what equals 7").
    static func text(instruction: String?, exercise: String?) -> String {
        [instruction, exercise.map(spokenExercise)]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { part in
                guard let last = part.last, !".!?…:؟።".contains(last) else { return part }
                return part + "."
            }
            .joined(separator: " ")
    }

    /// The exercise as the screen writes it. A picture to count (objects, blocks, bars, a
    /// number line) is never read, so the reading cannot give the answer away.
    static func exercise(_ representations: [Representation]) -> String? {
        let texts = representations.compactMap { representation -> String? in
            switch representation {
            case .mathExpression(let value):
                return value.expression
            case .math(let value):
                return value.isDrawnAsText ? value.displayText : nil
            case .learningText, .imageAsset, .audioAsset, .visualQuantity:
                return nil
            }
        }
        return texts.isEmpty ? nil : texts.joined(separator: ", ")
    }

    /// Android Speech.spoken: the symbols of an exercise become the words the app already
    /// uses for them, and the box of the missing number becomes "what".
    static func spokenExercise(_ text: String) -> String {
        let what = String(localized: "what", comment: "Read aloud in place of the missing number of a Math exercise: 3 + □ = 7 is read \"3 plus what equals 7\".")
        let words: [(symbol: String, word: String)] = [
            ("+", MathOperation.addition.accessibilityName),
            ("−", MathOperation.subtraction.accessibilityName),
            (" - ", MathOperation.subtraction.accessibilityName),
            ("×", MathOperation.multiplication.accessibilityName),
            ("÷", MathOperation.division.accessibilityName),
            ("<", MathComparisonRelation.lessThan.accessibilityName),
            ("=", MathComparisonRelation.equal.accessibilityName),
            (">", MathComparisonRelation.greaterThan.accessibilityName),
            ("→", ","),
            ("□", what),
            ("?", what),
        ]
        var spoken = text
        for entry in words {
            spoken = spoken.replacingOccurrences(of: entry.symbol, with: " \(entry.word) ")
        }
        return spoken
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

private extension MathRepresentation {
    /// RepresentationView writes these as text; it draws the others as pictures.
    var isDrawnAsText: Bool {
        switch self {
        case .numeral, .arithmeticExpression, .missingValueExpression, .decimal, .power,
             .orderOfOperations, .oneStepEquation, .twoStepEquation, .linearRelationship,
             .proportion, .comparison:
            return true
        case .quantity, .groupedQuantity, .placeValue, .equalGroups, .fraction, .numberLine,
             .percent, .ratio, .probability, .geometry:
            return false
        }
    }
}

/// The Parent Area's "Read aloud" switch (Android AppState.speakAloud, "speak_aloud").
struct MathReadAloudPreferenceRepository {
    private let userDefaults: UserDefaults
    private let storageKey: String

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = "minik.math.read-aloud.v1"
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
    }

    func load() -> Bool {
        guard userDefaults.object(forKey: storageKey) != nil else { return true }
        return userDefaults.bool(forKey: storageKey)
    }

    func save(_ isEnabled: Bool) {
        userDefaults.set(isEnabled, forKey: storageKey)
    }
}

private struct MathReadAloudEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

private struct MathHowToIsShowingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// The Parent Area's "Read aloud" switch, set by the activity hub.
    var mathReadAloudEnabled: Bool {
        get { self[MathReadAloudEnabledKey.self] }
        set { self[MathReadAloudEnabledKey.self] = newValue }
    }

    /// The how-to card covers the activity (Android shows it instead of the activity), so the
    /// activity's first exercise is read once the card is gone, never over the card.
    var mathHowToIsShowing: Bool {
        get { self[MathHowToIsShowingKey.self] }
        set { self[MathHowToIsShowingKey.self] = newValue }
    }
}

extension View {
    /// Android LaunchedEffect(question) { Speech.speak(hint, exercise) }: reads the instruction
    /// and the exercise each time `id` changes, unless Read aloud is off, and once the how-to
    /// card is gone. Nothing is read when both are nil, so Language screens carry it unchanged.
    /// A screen with a speaker button passes its own player, so a tap and the reading never
    /// talk over each other.
    func mathReadAloud<ID: Hashable>(
        instruction: String?,
        exercise: String?,
        id: ID,
        player: InterfaceSpeechPlayer? = nil
    ) -> some View {
        modifier(MathReadAloudModifier(
            instruction: instruction,
            exercise: exercise,
            id: id,
            player: player
        ))
    }
}

private struct MathReadAloudModifier<ID: Hashable>: ViewModifier {
    let instruction: String?
    let exercise: String?
    let id: ID
    let player: InterfaceSpeechPlayer?
    @StateObject private var ownPlayer = InterfaceSpeechPlayer()
    @Environment(\.mathReadAloudEnabled) private var isEnabled
    @Environment(\.mathHowToIsShowing) private var howToIsShowing
    @Environment(\.interfaceLocaleID) private var interfaceLocaleID
    @Environment(\.scenePhase) private var scenePhase

    private struct ReadingKey: Hashable {
        let id: ID
        let canRead: Bool
    }

    func body(content: Content) -> some View {
        content
            .task(id: ReadingKey(id: id, canRead: isEnabled && !howToIsShowing)) {
                read()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { speaker.stop() }
            }
            .onDisappear { speaker.stop() }
    }

    private var speaker: InterfaceSpeechPlayer {
        player ?? ownPlayer
    }

    private func read() {
        guard isEnabled, !howToIsShowing, scenePhase == .active else { return }
        MathReadAloud.say(
            MathReadAloud.text(instruction: instruction, exercise: exercise),
            with: speaker,
            fallback: interfaceLocaleID
        )
    }
}
