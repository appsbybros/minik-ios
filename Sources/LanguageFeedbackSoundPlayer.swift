import AVFoundation
import Combine
import Foundation

enum LanguageFeedbackSound: String, Hashable, Sendable {
    case correct = "success_sound"
    case correctPicture = "success_pictures_screen_sound"
    case streak = "success_in_a_raw_sound"
    case incorrect = "failure_pictures_screen_sound"
}

@MainActor
final class LanguageFeedbackSoundPlayer: ObservableObject {
    private var players: [LanguageFeedbackSound: AVAudioPlayer] = [:]

    func play(_ sound: LanguageFeedbackSound) {
        if players[sound] == nil,
           let url = Bundle.main.url(forResource: sound.rawValue, withExtension: "mp3"),
           let player = try? AVAudioPlayer(contentsOf: url) {
            player.prepareToPlay()
            players[sound] = player
        }
        guard let player = players[sound] else { return }
        player.currentTime = 0
        player.play()
    }

    func stop() {
        for player in players.values { player.stop() }
    }
}

enum LanguageEncouragementCopy {
    // LetterPairsFragment.speakRandomEncouragement: all eight original choices.
    static let phrases: [String.LocalizationValue] = [
        "Great game!", "Success!", "Great job!", "Nice!",
        "Fun game", "Awesome!", "Excellent!", "Fantastic!"
    ]
    // Owner QA: game-level praise belongs only at the end of a practice, so a
    // single pair is praised without "Great game!" or "Fun game".
    static let singleMatch: [String.LocalizationValue] = [
        "Success!", "Great job!", "Nice!", "Awesome!", "Excellent!", "Fantastic!"
    ]
    static let gameCompleted: String.LocalizationValue = "Great game!"
}

enum LanguageWordEncouragement {
    static let ordinary: [String.LocalizationValue] = [
        "Good!", "Excellent!", "Great job!", "Fantastic!", "Very nice!",
        "Awesome!", "Correct", "Amazing!", "Keep up the good work!", "Correct answer!", "Success!"
    ]
    static let laterRun: [String.LocalizationValue] = [
        "Good!", "Nice!", "Great job!", "Awesome!", "Very nice!", "Amazing!",
        "Success!", "Fantastic!", "Brilliant!", "You are on a streak!", "You are learning fast!", "Magnificent!"
    ]

    static func suffix(for run: Int) -> String.LocalizationValue {
        switch run {
        case 3: "You are learning fast!"
        case 4: "Keep up the good work!"
        case 5: "You are on a streak!"
        case 6: "Amazing!"
        case 7: "Awesome!"
        case 8: "Brilliant!"
        case 9: "Very nice!"
        default: laterRun.randomElement() ?? "Excellent!"
        }
    }
}
