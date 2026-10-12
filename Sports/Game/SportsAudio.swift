import AVFoundation
import Foundation

/// Android SoundPool (four streams) at volume 0.55: the court and room sounds.
final class SportsSounds {
    private var players: [String: [AVAudioPlayer]] = [:]
    private var paused = false
    /// Android `prefs.getBoolean("sounds", true)`.
    var enabled = true

    init() {
        let names = ["minik_kick", "minik_kick2", "ball_hit", "success_sound", "failure_sound", "success_in_a_raw_sound", "connected", "player_ready"]
        for name in names {
            guard let url = Bundle.main.url(forResource: name, withExtension: "mp3") else { continue }
            var list: [AVAudioPlayer] = []
            for _ in 0..<2 {
                guard let player = try? AVAudioPlayer(contentsOf: url) else { continue }
                player.volume = 0.55
                player.prepareToPlay()
                list.append(player)
            }
            players[name] = list
        }
    }

    func play(_ name: String) {
        guard enabled, !paused, let list = players[name], !list.isEmpty else { return }
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

/// Android `menuMusic()`: `cool_music2` looping at volume 0.17 on the menu pages. Android plays it
/// without requesting audio focus, so on iOS it uses the mixable ambient session and never stops
/// other apps' audio.
@MainActor
final class SportsMusic {
    private var player: AVAudioPlayer?
    private var foreground = true
    private var menu = false

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [])
    }

    func setForeground(_ value: Bool) {
        foreground = value
        sync()
    }

    func setMenu(_ value: Bool) {
        menu = value
        sync()
    }

    private func sync() {
        if !foreground || !menu {
            player?.pause()
            return
        }
        if player == nil, let url = Bundle.main.url(forResource: "cool_music2", withExtension: "mp3") {
            player = try? AVAudioPlayer(contentsOf: url)
            player?.numberOfLoops = -1
            player?.volume = 0.17
            player?.prepareToPlay()
        }
        try? AVAudioSession.sharedInstance().setActive(true, options: [])
        if player?.isPlaying == false { player?.play() }
    }
}
