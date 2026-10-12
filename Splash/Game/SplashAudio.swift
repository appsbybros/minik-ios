import AVFoundation
import Foundation

/// Android SoundPool: the five battle sounds at volume 0.35, a few overlapping streams each.
final class SplashSounds {
    private var players: [String: [AVAudioPlayer]] = [:]
    private var paused = false
    /// Android `prefs.getBoolean("gameSounds", true)`: the grown-ups page's "Game sounds" switch.
    var enabled = true

    init() {
        let files = ["hit": "sfx_hit", "throw": "minik_kick2", "wrong": "sfx_wrong", "finish": "sfx_finish", "pickup": "sfx_pickup"]
        for (key, file) in files {
            guard let url = Bundle.main.url(forResource: file, withExtension: "mp3") else { continue }
            var list: [AVAudioPlayer] = []
            for _ in 0..<3 {
                guard let player = try? AVAudioPlayer(contentsOf: url) else { continue }
                player.volume = 0.35
                player.prepareToPlay()
                list.append(player)
            }
            players[key] = list
        }
    }

    /// Android `sounds(type)`: unknown event types (jump, crouch) are silent.
    func play(_ type: String) {
        guard enabled, !paused, let list = players[type], !list.isEmpty else { return }
        let player = list.first(where: { !$0.isPlaying }) ?? list[0]
        player.currentTime = 0
        player.play()
    }

    /// Android `SoundPool.autoPause()` / `autoResume()`.
    func setPaused(_ value: Bool) {
        paused = value
        if value {
            for list in players.values {
                for player in list where player.isPlaying { player.stop() }
            }
        }
    }
}

/// Android MenuMusic: one menu loop at volume 0.20, gated by visibility and foreground. Like
/// Android's audio focus it takes the audio session while playing and releases it after.
@MainActor
final class MenuMusic {
    private var player: AVAudioPlayer?
    private var foreground = false
    private var menu = false
    private var focused = false
    private var observer: NSObjectProtocol?

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [])
        observer = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard raw == AVAudioSession.InterruptionType.ended.rawValue, let music = self else { return }
            Task { @MainActor in music.interruptionEnded() }
        }
    }

    func setForeground(_ value: Bool) {
        foreground = value
        sync()
    }

    func setMenu(_ value: Bool) {
        menu = value
        sync()
    }

    var isPlaying: Bool { return player?.isPlaying == true }

    private func interruptionEnded() {
        focused = false
        sync()
    }

    private func sync() {
        let session = AVAudioSession.sharedInstance()
        if !foreground || !menu {
            player?.pause()
            if focused {
                try? session.setCategory(.ambient, mode: .default, options: [])
                try? session.setActive(false, options: [.notifyOthersOnDeactivation])
                focused = false
            }
            return
        }
        if !focused {
            do {
                try session.setCategory(.soloAmbient, mode: .default, options: [])
                try session.setActive(true, options: [])
                focused = true
            } catch {
                focused = false
            }
        }
        if !focused { return }
        if player == nil, let url = Bundle.main.url(forResource: "cool_music2", withExtension: "mp3") {
            player = try? AVAudioPlayer(contentsOf: url)
            player?.numberOfLoops = -1
            player?.volume = 0.20
            player?.prepareToPlay()
        }
        if player?.isPlaying == false { player?.play() }
    }

    func release() {
        foreground = false
        menu = false
        player?.stop()
        player = nil
        if focused {
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
            focused = false
        }
    }
}

/// Android TextToSpeech for the question "♫" button, in the device language.
@MainActor
final class SplashSpeech {
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String) {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: AppText.language)
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    }
}
