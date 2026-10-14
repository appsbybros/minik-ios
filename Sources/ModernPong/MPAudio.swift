import AVFoundation

@MainActor final class MPAudio {
    private var players: [String: AVAudioPlayer] = [:]
    private var music: AVAudioPlayer?
    /// Android PongMenuMusic: the menu-only remix at 22 % volume (bundled with the standalone app only).
    private var menu: AVAudioPlayer?
    var enabled = true
    init() {
        for name in ["minik_kick", "minik_kick2", "splash", "failure_sound", "success_in_a_raw_sound", "success_pictures_screen_sound", "minik_claps", "connected", "player_ready"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "mp3"), let player = try? AVAudioPlayer(contentsOf: url) { player.prepareToPlay(); players[name] = player }
        }
    }
    func guideMusic(_ active: Bool) {
        guard enabled && active else { music?.pause(); return }
        if music == nil, let url = Bundle.main.url(forResource: "cool_music2", withExtension: "mp3"), let player = try? AVAudioPlayer(contentsOf: url) { music = player; player.numberOfLoops = -1; player.prepareToPlay() }
        if music?.isPlaying == false { music?.play() }
    }
    func menuMusic(_ on: Bool) {
        guard on else { menu?.pause(); return }
        if menu == nil, let url = Bundle.main.url(forResource: "pong_menu_remix", withExtension: "mp3", subdirectory: "ModernPongArt"), let player = try? AVAudioPlayer(contentsOf: url) {
            player.numberOfLoops = -1; player.volume = 0.22; player.prepareToPlay(); menu = player
        }
        if menu?.isPlaying == false { menu?.play() }
    }
    func play(_ name: String) {
        guard enabled else { return }
        if players[name] == nil {
            let url = ["mp3", "wav", "ogg"].compactMap { Bundle.main.url(forResource: name, withExtension: $0, subdirectory: "ModernPongAudio") ?? Bundle.main.url(forResource: name, withExtension: $0) }.first
            if let url, let player = try? AVAudioPlayer(contentsOf: url) { player.prepareToPlay(); players[name] = player }
        }
        players[name]?.stop(); players[name]?.currentTime = 0; players[name]?.play()
    }
    func events(_ events: [MPEvent]) {
        for event in events {
            switch event {
            case .swing: play("minik_kick2")
            case .contact: play("minik_kick")
            case .net: play("splash")
            case let .point(resolution, striker, streak):
                if resolution.winner == .child { play(streak == 3 ? "success_in_a_raw_sound" : "success_pictures_screen_sound") }
                else if striker == .child && Self.audibleFault(resolution.fault) { play("failure_sound") }
            case .victory(.child): play("minik_claps")
            default: break
            }
        }
    }
    func stop() { players.values.forEach { $0.stop() }; music?.stop(); music = nil }
    /// Android ModernSoundPolicy: only the player's net and out shots play the failure sound.
    /// Missed receives, second bounces and illegal gestures have no failure cue.
    nonisolated static func audibleFault(_ fault: MPFault) -> Bool { [MPFault.net, .leftTable, .firstBounceOut].contains(fault) }
}
