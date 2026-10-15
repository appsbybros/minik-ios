import AVFoundation
import Combine
import Foundation
import UIKit

/// Audition player. Saving a choice is handled explicitly by the parent view.
@MainActor
final class SpeechVoiceTestPlayer: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    enum PlaybackState: Equatable { case ready, speaking, finished, stopped, unavailable }

    @Published private(set) var voices: [AVSpeechSynthesisVoice] = []
    @Published private(set) var state: PlaybackState = .ready
    @Published private(set) var lastTest = ""
    @Published private(set) var currentAppVoice: AVSpeechSynthesisVoice?
    private let synthesizer = AVSpeechSynthesizer()
    private var activeUtterance: ObjectIdentifier?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func refresh(locale: InterfaceLocaleID) {
        stop()
        voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { SpeechVoiceTestSamples.matches(voiceLanguage: $0.language, locale: locale) }
            .sorted {
                if $0.quality != $1.quality { return $0.quality.rawValue > $1.quality.rawValue }
                if $0.name != $1.name { return $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                return $0.identifier < $1.identifier
            }
        // Offer the app's automatic choice (MinikSpeechVoice) separately from named voices.
        // Never audition Hebrew in English: canPlay rejects a voice of another language.
        currentAppVoice = MinikSpeechVoice.automaticVoice(for: locale.rawValue)
        state = .ready
    }

    func voice(id: String) -> AVSpeechSynthesisVoice? {
        id.isEmpty ? currentAppVoice : voices.first { $0.identifier == id }
    }

    func canPlay(id: String, locale: InterfaceLocaleID) -> Bool {
        guard let voice = voice(id: id) else { return false }
        return SpeechVoiceTestSamples.matches(voiceLanguage: voice.language, locale: locale)
    }

    func play(_ text: String, voiceID: String, locale: InterfaceLocaleID, rate: Float) {
        stop()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let voice = voice(id: voiceID), canPlay(id: voiceID, locale: locale) else {
            state = .unavailable
            return
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate, max(AVSpeechUtteranceMinimumSpeechRate, rate))
        utterance.pitchMultiplier = 1
        utterance.volume = 1
        activeUtterance = ObjectIdentifier(utterance)
        lastTest = [
            "Minik voice test",
            "iOS: \(UIDevice.current.systemVersion)",
            "Voice: \(voice.name)",
            "ID: \(voice.identifier)",
            "Language: \(voice.language)",
            "Quality: \(voice.quality.rawValue) (1=default, 2=enhanced, 3=premium)",
            "Rate: \(utterance.rate)",
            "Text: \(text)"
        ].joined(separator: "\n")
        state = .speaking
        synthesizer.speak(utterance)
    }

    func stop() {
        // Ignore late delegate callbacks from a superseded audition.
        activeUtterance = nil
        synthesizer.stopSpeaking(at: .immediate)
        state = .stopped
    }

    private func finished(_ id: ObjectIdentifier, cancelled: Bool) {
        guard activeUtterance == id else { return }
        activeUtterance = nil
        state = cancelled ? .stopped : .finished
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.finished(id, cancelled: false) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.finished(id, cancelled: true) }
    }
}
