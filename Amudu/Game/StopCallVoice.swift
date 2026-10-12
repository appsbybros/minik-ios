import AVFoundation

/// Android `StopCallVoice`: this selects the caller's avatar, including remote humans, not the local player's avatar.
enum StopCallVoice {
    case funny
    case regular

    static func forCaller(_ language: String, _ character: String?) -> StopCallVoice? {
        var base = language.lowercased()
        if let dash = base.firstIndex(of: "-") { base = String(base[..<dash]) }
        if let underscore = base.firstIndex(of: "_") { base = String(base[..<underscore]) }
        if base != "he" && base != "iw" { return nil }
        return (character == "minik" || character == "miniko") ? .funny : .regular
    }
}

private final class StopCallBundleToken {}

/// Android `HebrewStopCalls`: preloaded short recordings, one at a time (a SoundPool with one stream). The players load
/// before the first call, so the Android wait for a sample that is still loading is not needed.
@MainActor final class HebrewStopCalls {
    private var samples: [StopCallVoice: AVAudioPlayer] = [:]
    private var playing: AVAudioPlayer?
    private var released = false

    init() {
        let bundle = Bundle(for: StopCallBundleToken.self)
        let files: [(StopCallVoice, String)] = [(.funny, "amodu_call_funny"), (.regular, "amodu_call_standard")]
        for (voice, name) in files {
            guard let url = bundle.url(forResource: name, withExtension: "mp3") ?? Bundle.main.url(forResource: name, withExtension: "mp3"),
                  let player = try? AVAudioPlayer(contentsOf: url) else {
                print("HebrewStopCalls", "Voice sample failed to load: \(name)")
                continue
            }
            player.volume = 1
            player.prepareToPlay()
            samples[voice] = player
        }
    }

    func isReady(_ voice: StopCallVoice) -> Bool {
        return !released && samples[voice] != nil
    }

    func play(_ voice: StopCallVoice) {
        if released { return }
        stop()
        guard let sample = samples[voice] else { return }
        sample.currentTime = 0
        if !sample.play() { print("HebrewStopCalls", "Voice stream did not start") }
        playing = sample
    }

    func stop() {
        playing?.stop()
        playing = nil
    }

    func release() {
        if released { return }
        stop()
        released = true
        samples.removeAll()
    }
}
