import SwiftUI

struct ParentalGateChallenge: Equatable, Sendable {
    let left: Int
    let right: Int

    var answer: Int { left + right }

    /// Accepts Western and other Unicode decimal digits, such as Arabic-Indic
    /// digits typed on an Arabic keyboard.
    func accepts(_ response: String) -> Bool {
        let digits = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !digits.isEmpty, digits.count <= 4 else { return false }
        var value = 0
        for character in digits {
            guard let digit = character.wholeNumberValue, (0...9).contains(digit) else { return false }
            value = value * 10 + digit
        }
        return value == answer
    }

    static func random() -> ParentalGateChallenge {
        ParentalGateChallenge(
            left: Int.random(in: 24...59),
            right: Int.random(in: 16...47)
        )
    }
}

struct ParentalGateView: View {
    let challenge: ParentalGateChallenge
    let onCancel: () -> Void
    let onUnlock: () -> Void

    @State private var response = ""
    @State private var showsError = false
    @FocusState private var answerFocused: Bool

    init(
        challenge: ParentalGateChallenge = .random(),
        onCancel: @escaping () -> Void,
        onUnlock: @escaping () -> Void
    ) {
        self.challenge = challenge
        self.onCancel = onCancel
        self.onUnlock = onUnlock
    }

    /// The app's interface language (Minik's own language setting, or the device's).
    @Environment(\.locale) private var locale

    /// A sheet does not take the app's right-to-left direction from the screen under it,
    /// and the system navigation bar and Form follow the device language, not Minik's.
    /// On the owner's iPhone (1 November 2026), with Minik in Hebrew, the gate showed
    /// Cancel on the left, its text aligned left and the title cut to "למבוגרים...".
    /// So the gate draws its own title and buttons, in the interface language's direction.
    private var interfaceDirection: LayoutDirection {
        locale.language.characterDirection == .rightToLeft ? .rightToLeft : .leftToRight
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button("Cancel", action: cancel)
                Spacer(minLength: 12)
                Button("Continue", action: validate)
                    .fontWeight(.semibold)
                    .disabled(response.isEmpty)
            }
            .font(.body)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Grown-ups only")
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("This action is for a grown-up.")
                            .font(.headline)
                        Text("Solve this to continue.")
                            .foregroundStyle(.secondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)

                    // The answer is typed beside the exercise, in the same large digits. As a
                    // row of its own under a half-height sheet it was cut off behind the
                    // number pad on the owner's iPad (14 October 2026), so nothing typed showed.
                    // With larger text on a small iPhone the exercise broke over two lines
                    // ("42 +" above "20 ="), so it never wraps: the answer box goes under it
                    // when the row does not fit, and the digits shrink only past that.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            exercise
                            answerField
                        }
                        VStack(spacing: 10) {
                            exercise
                            answerField
                        }
                    }
                    .font(.largeTitle.monospacedDigit().bold())
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
                    // An exercise reads left to right in Hebrew and Arabic too.
                    .environment(\.layoutDirection, .leftToRight)

                    if showsError {
                        Text("Not quite. Try again.")
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(
                    Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .environment(\.layoutDirection, interfaceDirection)
        .onAppear { answerFocused = true }
        // Full height, so the exercise and the answer stay above the keyboard on iPhone too.
        .presentationDetents([.large])
        .interactiveDismissDisabled()
    }

    private var exercise: some View {
        Text(String(
            format: String(localized: "%lld + %lld"),
            Int64(challenge.left),
            Int64(challenge.right)
        ) + " =")
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .accessibilityLabel(String(
            format: String(localized: "%lld plus %lld"),
            Int64(challenge.left),
            Int64(challenge.right)
        ))
    }

    private var answerField: some View {
        TextField(text: $response, prompt: Text(verbatim: "?")) {
            Text("Answer")
        }
        .keyboardType(.numberPad)
        .multilineTextAlignment(.center)
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .frame(width: 120)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: 2)
        )
        .focused($answerFocused)
        .onSubmit(validate)
    }

    private func validate() {
        guard challenge.accepts(response) else {
            showsError = true
            response = ""
            answerFocused = true
            return
        }
        // Android Math Plus ParentGateScreen (dc12a5c): the keyboard goes away before the
        // next screen opens.
        answerFocused = false
        onUnlock()
    }

    private func cancel() {
        answerFocused = false
        onCancel()
    }
}
