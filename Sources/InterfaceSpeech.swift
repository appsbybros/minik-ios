import AVFoundation
import Combine
import Foundation

@MainActor
final class InterfaceSpeechPlayer: ObservableObject {
    private let speaker = MinikSpeaker()

    func speak(_ text: String, interfaceLocale: InterfaceLocaleID) {
        stop()
        guard !text.isEmpty else { return }
        let utterance = AVSpeechUtterance(string: text)
        let localeIdentifier = interfaceLocale.rawValue
        let languageCode = Locale(identifier: localeIdentifier).language.languageCode?.identifier
        utterance.voice = MinikSpeechVoice.voice(for: localeIdentifier)
            ?? languageCode.flatMap { MinikSpeechVoice.voice(for: $0) }
        speaker.speak(utterance, languageTag: localeIdentifier)
    }

    func stop() {
        speaker.stopSpeaking()
    }
}
