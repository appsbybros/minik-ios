import AVFoundation
import Combine
import Foundation

enum TicTacToeFeedbackCopy {
    static let title = String(localized: "Tic-Tac-Toe")
    static let introduction = String(localized: "Tic Tac Toe — Just for Fun!")
    static let firstInstruction = String(localized: "Pick X or O, or just tap a square to start!")
    static let chooseMark = String(localized: "Choose X or O")
    static let tapSquare = String(localized: "Tap a square")
    static let childWinStatus = String(localized: "You won!")
    static let minikWinStatus = String(localized: "Minik won!")
    static let drawStatus = String(localized: "Draw")
    static let nextRound = String(localized: "A new round begins")

    static let positivePhrases = [
        String(localized: "You won!"),
        String(localized: "Great job!"),
        String(localized: "Nice!"),
        String(localized: "Fun game"),
        String(localized: "Awesome!"),
        String(localized: "Excellent!"),
        String(localized: "Fantastic!"),
        String(localized: "Great game!")
    ]

    static let drawPhrases = [
        String(localized: "It’s a tie!"),
        String(localized: "Tie game!"),
        String(localized: "Draw")
    ]

    // Intentional Android-production compatibility copy. Although Minik won,
    // the shipped Android feedback says "we lost". Keep the contradiction in
    // this one seam until product copy explicitly supersedes it.
    static let androidCompatibleMinikWinPhrase = String(localized: "We lost this time. Hope it was fun!")
}

@MainActor
final class TicTacToeFeedbackPlayer: NSObject, ObservableObject {
    private let speaker = MinikSpeaker()
    private var audioPlayers: [AVAudioPlayer?] = [nil, nil]
    private var remainingUtterances = 0
    private var speechCompletion: (() -> Void)?

    override init() {
        super.init()
        speaker.onUtteranceEnd = { [weak self] _ in self?.finishOneUtterance() }
        audioPlayers = [
            makeAudioPlayer(named: "minik_kick"),
            makeAudioPlayer(named: "minik_kick2")
        ]
    }

    func speak(
        _ messages: [String],
        interfaceLocale: InterfaceLocaleID,
        completion: @escaping () -> Void = {}
    ) {
        stopSpeech()

        let nonemptyMessages = messages.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !nonemptyMessages.isEmpty else {
            completion()
            return
        }

        remainingUtterances = nonemptyMessages.count
        speechCompletion = completion
        for message in nonemptyMessages {
            let utterance = AVSpeechUtterance(string: message)
            utterance.voice = hostingVoice(for: interfaceLocale)
            speaker.speak(utterance, languageTag: interfaceLocale.rawValue)
        }
    }

    func playChildMoveSound(index: Int) {
        guard audioPlayers.indices.contains(index),
              let player = audioPlayers[index] else {
            return
        }
        player.currentTime = 0
        player.play()
    }

    func stop() {
        stopSpeech()
        for player in audioPlayers {
            player?.stop()
        }
    }

    private func hostingVoice(for interfaceLocale: InterfaceLocaleID) -> AVSpeechSynthesisVoice? {
        let preferredIdentifier = interfaceLocale.rawValue
        return MinikSpeechVoice.voice(for: preferredIdentifier)
            ?? interfaceLocale.locale.language.languageCode.flatMap { MinikSpeechVoice.voice(for: $0.identifier) }
    }

    private func makeAudioPlayer(named name: String) -> AVAudioPlayer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "mp3") else {
            return nil
        }
        let player = try? AVAudioPlayer(contentsOf: url)
        player?.prepareToPlay()
        return player
    }

    private func stopSpeech() {
        speechCompletion = nil
        remainingUtterances = 0
        speaker.stopSpeaking()
    }

    private func finishOneUtterance() {
        guard remainingUtterances > 0 else {
            return
        }
        remainingUtterances -= 1
        guard remainingUtterances == 0 else {
            return
        }
        let completion = speechCompletion
        speechCompletion = nil
        completion?()
    }
}
