import AVFoundation

@MainActor final class MPAudio {
    private var players: [String: AVAudioPlayer] = [:]
    private var music: AVAudioPlayer?
    var enabled = true
    /// Android 47ad0c9 ModernAudio / LobbyAudio (`cross_skill_journey/sound`): with "Game sounds" off no cue plays, and asking
    /// for one stops the cue still playing. The guide music is not a game sound.
    var soundsEnabled: () -> Bool = { true }
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
    func play(_ name: String) {
        guard enabled else { return }
        guard soundsEnabled() else { stopEffects(); return }
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
    /// Android 47ad0c9: turning "Game sounds" off stops the swing, contact, net and celebration cues at once.
    func stopEffects() { players.values.forEach { $0.stop() } }
    /// Android ModernSoundPolicy: only the player's net and out shots play the failure sound.
    /// Missed receives, second bounces and illegal gestures have no failure cue.
    nonisolated static func audibleFault(_ fault: MPFault) -> Bool { [MPFault.net, .leftTable, .firstBounceOut].contains(fault) }
}
