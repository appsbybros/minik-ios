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

/// Android MenuMusic (2026-10-17): owns the audio session for both the opening announcement
/// (splash_speech, volume 0.85) and the menu loop (volume 0.20), gated by visibility and foreground.
/// The announcement plays once at launch on the opening menu and once when each new match starts
/// (when "Game sounds" is on); a menu visit is not an app launch, and resuming a match is not a new
/// match. Like Android's audio focus it takes the session while playing and releases it after.
@MainActor
final class MenuMusic: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var speech: AVAudioPlayer?
    private var announcementPending: Bool
    private var startup: Bool
    private var foreground = false
    private var menu = false
    private var focused = false
    private var announcedMatches = Set<String>()
    private(set) var announcementStarts = 0
    private var observer: NSObjectProtocol?

    init(announceLaunch: Bool = true) {
        announcementPending = announceLaunch
        startup = announceLaunch
        super.init()
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [])
        observer = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard let music = self else { return }
            let began = raw == AVAudioSession.InterruptionType.began.rawValue
            let ended = raw == AVAudioSession.InterruptionType.ended.rawValue
            Task { @MainActor in
                // Android AUDIOFOCUS_LOSS pauses both players; regaining focus resumes them.
                if began { music.interruptionBegan() } else if ended { music.interruptionEnded() }
            }
        }
    }

    func setForeground(_ value: Bool) {
        foreground = value
        sync()
    }

    func setMenu(_ value: Bool) {
        if (menu != value && !(startup && value)) || (startup && !value) {
            // Leaving the opening menu must not leave a delayed intro behind. Returning
            // from a match cancels any unfinished match announcement, without another intro.
            cancelSpeech()
            startup = false
        }
        menu = value
        sync()
    }

    /// Android `matchStarted(id, enabled)`: once per match id.
    func matchStarted(_ id: String, enabled: Bool) {
        if !announcedMatches.insert(id).inserted { return }
        cancelSpeech()
        startup = false
        if enabled {
            announcementPending = true
            sync()
        }
    }

    var isPlaying: Bool { return player?.isPlaying == true }
    var speechPlaying: Bool { return speech?.isPlaying == true }

    private func interruptionBegan() {
        player?.pause()
        speech?.pause()
    }

    private func interruptionEnded() {
        focused = false
        sync()
    }

    private func cancelSpeech() {
        speech?.stop()
        speech = nil
        announcementPending = false
    }

    private func abandon() {
        if focused {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.ambient, mode: .default, options: [])
            try? session.setActive(false, options: [.notifyOthersOnDeactivation])
            focused = false
        }
    }

    private func sync() {
        if !foreground {
            player?.pause()
            speech?.pause()
            abandon()
            return
        }
        if !menu { player?.pause() }
        if !menu && !announcementPending && speech == nil {
            abandon()
            return
        }
        if !focused {
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.soloAmbient, mode: .default, options: [])
                try session.setActive(true, options: [])
                focused = true
            } catch {
                focused = false
            }
        }
        if !focused { return }
        if announcementPending {
            player?.pause()
            if speech == nil {
                if let url = Bundle.main.url(forResource: "splash_speech", withExtension: "mp3"),
                   let made = try? AVAudioPlayer(contentsOf: url) {
                    made.volume = 0.85
                    made.delegate = self
                    made.prepareToPlay()
                    speech = made
                    announcementStarts += 1
                } else {
                    announcementPending = false
                    startup = false
                }
            }
            if let s = speech {
                if !s.isPlaying { s.play() }
                return
            }
        }
        if menu {
            if player == nil, let url = Bundle.main.url(forResource: "cool_music2", withExtension: "mp3") {
                player = try? AVAudioPlayer(contentsOf: url)
                player?.numberOfLoops = -1
                player?.volume = 0.20
                player?.prepareToPlay()
            }
            if player?.isPlaying == false { player?.play() }
        } else {
            abandon()
        }
    }

    /// Android `finishSpeech`: completion (or a decoding error) of the current announcement only.
    private func finishSpeech(_ completed: ObjectIdentifier) {
        guard let s = speech, ObjectIdentifier(s) == completed else { return }
        cancelSpeech()
        startup = false
        sync()
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let id = ObjectIdentifier(player)
        Task { @MainActor in self.finishSpeech(id) }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let id = ObjectIdentifier(player)
        Task { @MainActor in self.finishSpeech(id) }
    }

    func release() {
        foreground = false
        menu = false
        cancelSpeech()
        player?.stop()
        player = nil
        abandon()
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
