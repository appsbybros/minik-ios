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

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("This action is for a grown-up.")
                        .font(.headline)
                    Text("Solve this to continue.")
                        .foregroundStyle(.secondary)
                    // The answer is typed beside the exercise, in the same large digits. As a
                    // row of its own under a half-height sheet it was cut off behind the
                    // number pad on the owner's iPad (14 October 2026), so nothing typed showed.
                    HStack(spacing: 12) {
                        Text(String(
                            format: String(localized: "%lld + %lld"),
                            Int64(challenge.left),
                            Int64(challenge.right)
                        ) + " =")
                        .accessibilityLabel(String(
                            format: String(localized: "%lld plus %lld"),
                            Int64(challenge.left),
                            Int64(challenge.right)
                        ))

                        TextField(text: $response, prompt: Text(verbatim: "?")) {
                            Text("Answer")
                        }
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .frame(width: 120)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.accentColor, lineWidth: 2)
                        )
                        .focused($answerFocused)
                        .onSubmit(validate)
                    }
                    .font(.largeTitle.monospacedDigit().bold())
                    .frame(maxWidth: .infinity, alignment: .center)
                    // An exercise reads left to right in Hebrew and Arabic too.
                    .environment(\.layoutDirection, .leftToRight)

                    if showsError {
                        Text("Not quite. Try again.")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Grown-ups only")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue", action: validate)
                        .disabled(response.isEmpty)
                }
            }
            .onAppear { answerFocused = true }
        }
        // Full height, so the exercise and the answer stay above the keyboard on iPhone too.
        .presentationDetents([.large])
        .interactiveDismissDisabled()
    }

    private func validate() {
        guard challenge.accepts(response) else {
            showsError = true
            response = ""
            answerFocused = true
            return
        }
        onUnlock()
    }
}
