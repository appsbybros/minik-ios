import AVFoundation
import SwiftUI

/// Native Apple speech audition, reachable from the Language and Math Parent Areas.
struct SpeechVoiceTestView: View {
    let allowedLocales: [InterfaceLocaleID]
    let onSave: () -> Void
    @StateObject private var player = SpeechVoiceTestPlayer()
    @State private var testLocale: InterfaceLocaleID
    @State private var selectedVoiceID = ""
    @State private var rate = AVSpeechUtteranceDefaultSpeechRate
    @State private var customText = "1 + 2"
    @State private var saved = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.interfaceLocaleID) private var interfaceLocale

    init(allowedLocales: [InterfaceLocaleID], onSave: @escaping () -> Void = {}) {
        self.allowedLocales = allowedLocales
        self.onSave = onSave
        _testLocale = State(initialValue: SpeechVoiceTestSamples.initialLocale(allowed: allowedLocales))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Listen to voices, then save the one you like for this language.")
                        .font(.subheadline)
                    Picker("Test language", selection: $testLocale) {
                        ForEach(allowedLocales) { locale in
                            Text(verbatim: interfaceLocale.text(locale.displayNameKey)).tag(locale)
                        }
                    }
                    Picker("Test voice", selection: $selectedVoiceID) {
                        Text("System voice").tag("")
                        ForEach(player.voices, id: \.identifier) { voice in
                            Text(verbatim: voiceLabel(voice)).tag(voice.identifier)
                        }
                    }
                    .pickerStyle(.menu)
                    if let voice = player.voice(id: selectedVoiceID) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(verbatim: voiceLabel(voice)).font(.headline)
                            Text(verbatim: voice.identifier)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .environment(\.layoutDirection, .leftToRight)
                        }
                    }
                    if let onlyVoiceName = SpeechVoiceTestSamples.onlyVoiceName(among: player.voices) {
                        Text(verbatim: String(format: interfaceLocale.text(SpeechVoiceTestSamples.singleVoiceNoteKey), onlyVoiceName))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if !player.canPlay(id: selectedVoiceID, locale: testLocale) {
                        Text("No matching voice is available. Choose a downloaded voice or refresh the list.")
                            .foregroundStyle(.red)
                    }
                    Button("Refresh voices") { refresh() }
                    Button("Use this voice in the app") {
                        SpeechVoicePreference.save(id: selectedVoiceID, rate: rate, for: testLocale.rawValue)
                        saved = true
                        player.stop()
                        onSave()
                    }
                    .disabled(!player.canPlay(id: selectedVoiceID, locale: testLocale))
                    if saved {
                        Text("Voice and speed saved for this language.")
                            .foregroundStyle(.green)
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Speaking speed")
                        Slider(value: $rate, in: 0.35...0.60, step: 0.025) {
                            Text("Speaking speed")
                        } minimumValueLabel: {
                            Text("Slower")
                        } maximumValueLabel: {
                            Text("Faster")
                        }
                        Button("Normal speed") { rate = AVSpeechUtteranceDefaultSpeechRate }
                    }
                }

                Section {
                    ForEach(SpeechVoiceTestSamples.samples(for: testLocale), id: \.self) { sample in
                        Button {
                            play(sample)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "speaker.wave.2.fill")
                                    .accessibilityHidden(true)
                                Text(verbatim: sample)
                                    .font(.title3)
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .environment(\.layoutDirection, sample.contains("+") ? .leftToRight : testLocale.layoutDirection)
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .disabled(!player.canPlay(id: selectedVoiceID, locale: testLocale))
                        .accessibilityHint("Listen with the selected voice")
                    }
                } header: {
                    Text("Tap a phrase to listen")
                }

                Section {
                    TextField("Text to read", text: $customText, axis: .vertical)
                        .lineLimit(2...6)
                        .environment(\.layoutDirection, testLocale.layoutDirection)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button("Read my text") { play(customText) }
                        .disabled(customText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || !player.canPlay(id: selectedVoiceID, locale: testLocale))
                } header: {
                    Text("Try your own words")
                }

                Section {
                    Text("For more voices, open Settings > Accessibility > Read & Speak (or Spoken Content) > Voices. Download a voice for the test language, then return here and refresh.")
                        .font(.subheadline)
                    Text("If there is no sound, check the device volume and Silent Mode.")
                        .font(.subheadline)
                }

                if !player.lastTest.isEmpty {
                    Section {
                        Text(verbatim: player.lastTest)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .environment(\.layoutDirection, .leftToRight)
                    } header: {
                        Text("Last test details")
                    } footer: {
                        Text("You can copy these details to report which voice and words you tested.")
                    }
                }
            }
            .navigationTitle("Voice & speech")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { player.stop(); dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 16) {
                    Text(verbatim: statusText)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.updatesFrequently)
                    Button("Stop") { player.stop() }
                        .buttonStyle(.borderedProminent)
                        .disabled(player.state != .speaking)
                }
                .padding()
                .background(.regularMaterial)
            }
        }
        .onAppear { loadSelection() }
        .onChange(of: testLocale) { _, _ in
            loadSelection()
        }
        .onChange(of: selectedVoiceID) { _, _ in player.stop(); saved = false }
        .onChange(of: rate) { _, _ in player.stop(); saved = false }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refresh() } else { player.stop() }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVSpeechSynthesizer.availableVoicesDidChangeNotification)) { _ in
            refresh()
        }
        .onDisappear { player.stop() }
    }

    private func refresh() {
        player.refresh(locale: testLocale)
        if !selectedVoiceID.isEmpty, !player.voices.contains(where: { $0.identifier == selectedVoiceID }) {
            selectedVoiceID = ""
        }
    }

    private func loadSelection() {
        selectedVoiceID = SpeechVoicePreference.selectedID(for: testLocale.rawValue)
        rate = SpeechVoicePreference.selectedRate(for: testLocale.rawValue)
        saved = false
        refresh()
    }

    private func play(_ text: String) {
        player.play(text, voiceID: selectedVoiceID, locale: testLocale, rate: rate)
    }

    private func voiceLabel(_ voice: AVSpeechSynthesisVoice) -> String {
        let quality: String
        switch voice.quality {
        case .default: quality = interfaceLocale.text("Standard voice")
        case .enhanced: quality = interfaceLocale.text("Enhanced voice")
        case .premium: quality = interfaceLocale.text("Premium voice")
        @unknown default: quality = interfaceLocale.text("Other voice")
        }
        return "\(voice.name) · \(voice.language) · \(quality)"
    }

    private var statusText: String {
        switch player.state {
        case .ready: return interfaceLocale.text("Ready to listen")
        case .speaking: return interfaceLocale.text("Speaking…")
        case .finished: return interfaceLocale.text("Finished speaking")
        case .stopped: return interfaceLocale.text("Stopped")
        case .unavailable: return interfaceLocale.text("Voice unavailable")
        }
    }
}
