import SwiftUI

/// Android LevelUpDialogFragment (dialog_level_up.xml), shown when the automatic word
/// level moves up at the end of a word list: confetti (WriteScreen.showConfetti, the
/// three seconds of ConfettiRectView.start(3f)), the success_in_a_raw_sound, and a
/// rounded card with the magenta-to-blue bg_level_up_gradient, the "Level up!" title,
/// the accuracy and new level message, the hopping picture and the close button. A tap
/// outside the card also closes it, as the Android dialog is cancelable.
struct LanguageLevelUpView: View {
    let announcement: LanguageLevelUpAnnouncement
    let onClose: () -> Void

    @Environment(\.interfaceLocaleID) private var interfaceLocaleID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title2) private var titleSize: CGFloat = 24
    @ScaledMetric(relativeTo: .body) private var messageSize: CGFloat = 16
    @StateObject private var soundPlayer = LanguageFeedbackSoundPlayer()
    @State private var confettiStart: Date?
    @State private var hopping = false
    @State private var didAppear = false

    init(announcement: LanguageLevelUpAnnouncement, onClose: @escaping () -> Void) {
        self.announcement = announcement
        self.onClose = onClose
    }

    /// bg_level_up_gradient: #FF00C6, #7C4DFF and #00E5FF at 45 degrees (from the
    /// bottom start corner to the top end corner).
    private static let gradient = LinearGradient(
        colors: [
            Color(red: 1.0, green: 0.0, blue: 198 / 255),
            Color(red: 124 / 255, green: 77 / 255, blue: 1.0),
            Color(red: 0.0, green: 229 / 255, blue: 1.0)
        ],
        startPoint: .bottomLeading,
        endPoint: .topTrailing
    )

    var body: some View {
        GeometryReader { geometry in
            let cardWidth = max(1, min(geometry.size.width - 36, 520))
            ZStack {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .onTapGesture(perform: close)
                    .accessibilityHidden(true)

                if let confettiStart {
                    LanguageTowerConfettiView(reduceMotion: reduceMotion, startedAt: confettiStart)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .task(id: confettiStart) {
                            await endConfetti(startedAt: confettiStart)
                        }
                }

                ViewThatFits(in: .vertical) {
                    card
                    ScrollView {
                        card
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
                .frame(width: cardWidth)
                .frame(maxHeight: max(1, geometry.size.height - 24))
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, close)
        .onAppear {
            guard !didAppear else { return }
            didAppear = true
            confettiStart = Date()
            soundPlayer.play(.streak)
            if !reduceMotion {
                hopping = true
            }
        }
    }

    private var card: some View {
        VStack(spacing: 0) {
            Text(verbatim: interfaceLocaleID.text(LanguageLevelUpAnnouncement.titleKey))
                .font(MinikPretty.titleFont(titleSize))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 3, y: 2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 35)
                .accessibilityAddTraits(.isHeader)

            Text(verbatim: message)
                .font(MinikPretty.bodyFont(messageSize))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 3, y: 2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 15)
                .padding(.horizontal, 10)

            MinikArtworkImage(name: MinikVisualAsset.success)
                .frame(width: 102, height: 102)
                .offset(y: hopping ? -25 : 0)
                // Android animateImageJump: the picture hops for as long as the window
                // is open; with Reduce Motion it stands still.
                .animation(
                    hopping
                        ? Animation.easeInOut(duration: 0.28).repeatForever(autoreverses: true)
                        : Animation.default,
                    value: hopping
                )
                .padding(.top, 34)
                .padding(.bottom, 16)
            // Android's window has no Continue button (btnContinue is commented out in
            // dialog_level_up.xml): the close X or a tap outside closes it.
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(Self.gradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        .overlay(alignment: .topLeading) {
            // Android: the 40 dp close image at the card's top start.
            Button(action: close) {
                MinikArtworkImage(name: MinikVisualAsset.close)
                    .frame(width: 28, height: 28)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
            .padding(.leading, 6)
            .accessibilityLabel(Text(verbatim: interfaceLocaleID.text("Close")))
        }
        .accessibilityElement(children: .contain)
    }

    private var message: String {
        announcement.message(
            format: interfaceLocaleID.text(LanguageLevelUpAnnouncement.messageKey),
            levelName: interfaceLocaleID.text(
                LanguageLevelUpAnnouncement.levelNameKey(for: announcement.level)
            )
        )
    }

    private func close() {
        soundPlayer.stop()
        onClose()
    }

    /// The confetti goes once its last pieces have fallen; with Reduce Motion it is a
    /// still picture for three seconds, as in the Tower.
    @MainActor
    private func endConfetti(startedAt start: Date) async {
        let lifetime: TimeInterval = reduceMotion ? 3 : LanguageTowerConfettiView.visibleDuration
        let remaining = lifetime - Date().timeIntervalSince(start)
        if remaining > 0 {
            try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
        }
        guard !Task.isCancelled, confettiStart == start else { return }
        confettiStart = nil
    }
}
