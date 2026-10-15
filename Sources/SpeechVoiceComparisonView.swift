import AVFoundation
import SwiftUI

/// A literal speech test. The sample text bypasses the app's pronunciation substitutions so a
/// parent can hear whether a different voice or Hebrew vowel marks solve a particular word.
struct SpeechVoiceComparisonView: View {
    let languageTags: [String]
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.interfaceLocaleID) private var interfaceLocale
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var player = SpeechVoiceComparisonPlayer()
    @State private var languageTag: String
    @State private var voiceID = ""
    @State private var customText: String
    @State private var saved = false
    @State private var voiceListRevision = 0

    init(languageTags: [String], onSave: @escaping () -> Void) {
        self.languageTags = languageTags
        self.onSave = onSave
        let initialTag = languageTags.first(where: {
            MinikSpeechVoice.languageCode($0) == "he"
        }) ?? languageTags.first ?? InterfaceLocaleID.hebrew.rawValue
        _languageTag = State(initialValue: initialTag)
        _customText = State(initialValue: MinikSpeechVoice.languageCode(initialTag) == "he" ? "שתיים" : "1 + 2")
    }

    private var languageCode: String { MinikSpeechVoice.languageCode(languageTag) ?? "he" }
    private var voices: [AVSpeechSynthesisVoice] {
        _ = voiceListRevision
        return MinikSpeechVoice.choices(forLanguageCode: languageCode)
    }
    private var selectedVoice: AVSpeechSynthesisVoice? {
        voiceID.isEmpty
            ? MinikSpeechVoice.automaticVoice(for: languageTag)
            : voices.first(where: { $0.identifier == voiceID })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(verbatim: interfaceLocale.text("Compare the exact words and voices below. Nothing changes in the app until you save a voice."))
                        .font(.subheadline)
                    if languageTags.count > 1 {
                        Picker(selection: $languageTag) {
                            ForEach(languageTags, id: \.self) { tag in
                                Text(verbatim: languageName(tag)).tag(tag)
                            }
                        } label: {
                            Text(verbatim: interfaceLocale.text("Test language"))
                        }
                    }
                    Picker(selection: $voiceID) {
                        Text(verbatim: interfaceLocale.text("Automatic")).tag("")
                        ForEach(voices, id: \.identifier) { voice in
                            Text(verbatim: voiceLabel(voice)).tag(voice.identifier)
                        }
                    } label: {
                        Text(verbatim: interfaceLocale.text("Test voice"))
                    }
                    .pickerStyle(.menu)
                    if let selectedVoice {
                        Text(verbatim: voiceLabel(selectedVoice))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(verbatim: interfaceLocale.text("No voice on this device"))
                            .foregroundStyle(.red)
                    }
                    Button {
                        player.stop()
                        MinikSpeechVoicePreferences().save(
                            voiceID.isEmpty ? nil : voiceID,
                            forLanguageCode: languageCode
                        )
                        saved = true
                        onSave()
                    } label: {
                        Text(verbatim: interfaceLocale.text("Use this voice in the app"))
                    }
                    .disabled(selectedVoice == nil)
                    if saved {
                        Text(verbatim: interfaceLocale.text("Voice saved for this language."))
                            .foregroundStyle(.green)
                    }
                } header: {
                    Text(verbatim: interfaceLocale.text("Compare voices"))
                }

                Section {
                    ForEach(samples, id: \.text) { sample in
                        Button {
                            play(sample.text)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "speaker.wave.2.fill")
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(verbatim: interfaceLocale.text(sample.label))
                                        .font(.subheadline)
                                    Text(verbatim: sample.text)
                                        .font(.title3)
                                        .environment(\.layoutDirection, sample.text.contains("+") ? .leftToRight : sample.direction)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(minHeight: 44)
                        }
                        .disabled(selectedVoice == nil)
                    }
                } header: {
                    Text(verbatim: interfaceLocale.text("Tap each phrase to listen"))
                } footer: {
                    Text(verbatim: interfaceLocale.text("The vocalized words are only a test. They are not yet used throughout the app."))
                }

                Section {
                    TextField(
                        String(localized: LocalizedStringResource("Your own words", locale: interfaceLocale.locale)),
                        text: $customText,
                        axis: .vertical
                    )
                    .lineLimit(2...4)
                    .autocorrectionDisabled()
                    .environment(\.layoutDirection, languageCode == "he" || languageCode == "ar" ? .rightToLeft : .leftToRight)
                    Button {
                        play(customText)
                    } label: {
                        Text(verbatim: interfaceLocale.text("Read my words"))
                    }
                    .disabled(selectedVoice == nil || customText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Section {
                    Button {
                        voiceListRevision += 1
                        if !voiceID.isEmpty && !voices.contains(where: { $0.identifier == voiceID }) {
                            voiceID = ""
                        }
                    } label: {
                        Text(verbatim: interfaceLocale.text("Refresh voices"))
                    }
                    Text(verbatim: interfaceLocale.text("To try more voices, download them in iPhone or iPad Settings, then refresh this list."))
                        .font(.subheadline)
                }
            }
            .navigationTitle(Text(verbatim: interfaceLocale.text("Voice pronunciation test")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        player.stop()
                        dismiss()
                    } label: {
                        Text(verbatim: interfaceLocale.text("Done"))
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if player.isSpeaking {
                    Button {
                        player.stop()
                    } label: {
                        Text(verbatim: interfaceLocale.text("Stop"))
                    }
                    .buttonStyle(.borderedProminent)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.regularMaterial)
                }
            }
        }
        .onAppear(perform: loadSavedVoice)
        .onChange(of: languageTag) { _, _ in
            player.stop()
            customText = languageCode == "he" ? "שתיים" : "1 + 2"
            loadSavedVoice()
        }
        .onChange(of: voiceID) { _, _ in player.stop(); saved = false }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { player.stop() }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVSpeechSynthesizer.availableVoicesDidChangeNotification)) { _ in
            voiceListRevision += 1
        }
        .onDisappear { player.stop() }
    }

    private var samples: [Sample] {
        if languageCode == "he" {
            return [
                Sample(label: "Plain word", text: "שתיים", direction: .rightToLeft),
                Sample(label: "With vowel marks", text: "שְׁתַּיִם", direction: .rightToLeft),
                Sample(label: "Plain word", text: "מגדל", direction: .rightToLeft),
                Sample(label: "With vowel marks", text: "מִגְדָּל", direction: .rightToLeft),
                Sample(label: "Plain word", text: "ניצחתם", direction: .rightToLeft),
                Sample(label: "With vowel marks", text: "נִצַּחְתֶּם", direction: .rightToLeft),
                Sample(label: "Plain sentence", text: "אחת ועוד שתיים", direction: .rightToLeft),
                Sample(label: "Sentence with vowel marks", text: "אַחַת וְעוֹד שְׁתַּיִם", direction: .rightToLeft),
                Sample(label: "Numbers as written", text: "1 + 2", direction: .leftToRight)
            ]
        }
        return [Sample(label: "Numbers as written", text: "1 + 2", direction: .leftToRight)]
    }

    private func play(_ text: String) {
        guard let selectedVoice else { return }
        player.speak(text, voice: selectedVoice)
    }

    private func loadSavedVoice() {
        let savedID = MinikSpeechVoicePreferences().identifier(forLanguageCode: languageCode)
        voiceID = voices.contains(where: { $0.identifier == savedID }) ? savedID ?? "" : ""
        saved = false
    }

    private func languageName(_ tag: String) -> String {
        guard let locale = InterfaceLocaleID(languageTag: tag) else { return tag }
        return interfaceLocale.text(locale.displayNameKey)
    }

    private func voiceLabel(_ voice: AVSpeechSynthesisVoice) -> String {
        let quality: String.LocalizationValue
        switch voice.quality {
        case .premium: quality = "Premium voice"
        case .enhanced: quality = "Enhanced voice"
        default: quality = "Standard voice"
        }
        return "\(voice.name) · \(voice.language) · \(interfaceLocale.text(quality))"
    }

    private struct Sample {
        let label: String.LocalizationValue
        let text: String
        let direction: LayoutDirection
    }
}

@MainActor
private final class SpeechVoiceComparisonPlayer: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var isSpeaking = false
    private let synthesizer = AVSpeechSynthesizer()
    private var activeUtterance: ObjectIdentifier?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, voice: AVSpeechSynthesisVoice) {
        stop()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        activeUtterance = ObjectIdentifier(utterance)
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stop() {
        activeUtterance = nil
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.finish(id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.finish(id) }
    }

    private func finish(_ id: ObjectIdentifier) {
        guard activeUtterance == id else { return }
        activeUtterance = nil
        isSpeaking = false
    }
}
