import AVFoundation
import Foundation

/// Minik Plus ships recorded clips of the Hebrew it says (words, letter names, praise and
/// instructions), all read by one neural voice, so Hebrew sounds the same on every device.
/// A clip is found by its text (`key`); a sentence with no clip of its own is put together
/// from clips of its words when every word has one (Math's "3 ועוד 4 שווה כמה"). Other Hebrew,
/// and every other language, is still read by the device voice. Minik Plus and Minik Math Plus
/// bundle them (Resources/HebrewSpeech, recorded by tools/hebrew-speech); the other apps
/// find none.
enum HebrewRecordedSpeech {
    static let folder = "HebrewSpeech"

    struct Manifest: Decodable {
        /// The recording voice ("Hila"), never shown in the app.
        let voice: String
        /// Clip file by `key`.
        let clips: [String: String]
    }

    /// The recorded clips that say `text` in `languageTag`, if it has them.
    static func clipURLs(for text: String, languageTag: String) -> [URL]? {
        guard MinikSpeechVoice.languageCode(languageTag) == "he",
              let manifest = bundledManifest,
              let files = clipFiles(for: text, in: manifest.clips) else {
            return nil
        }
        let urls = files.compactMap { Bundle.main.url(forResource: $0, withExtension: nil, subdirectory: folder) }
        return urls.count == files.count ? urls : nil
    }

    /// The text's own clip, or else clips for runs of its words, the longest run first
    /// ("3 ועוד 4 שווה כמה" from 3, ועוד, 4, שווה, כמה). Nil when a word has no clip, so a
    /// sentence is never said in two voices.
    static func clipFiles(for text: String, in manifest: [String: String]) -> [String]? {
        let whole = key(text)
        if let file = manifest[whole] { return [file] }
        let words = whole.split(separator: " ").map(String.init)
        guard words.count > 1 else { return nil }
        var files: [String] = []
        var start = 0
        while start < words.count {
            var end = words.count
            var found: String?
            while end > start, found == nil {
                found = manifest[words[start..<end].joined(separator: " ")]
                if found == nil { end -= 1 }
            }
            guard let file = found else { return nil }
            files.append(file)
            start = end
        }
        return files
    }

    /// The text a clip is filed under. Points (niqqud), punctuation and letter case are
    /// dropped and spaces collapsed, so the pronunciation fix "בְּרֶצֶף" and "ברצף!" both
    /// find the clip recorded for "ברצף". A geresh stays: it changes the letter (ג'ירפה), and
    /// so does a point or comma inside a number ("2.5", "1,000").
    /// tools/hebrew-speech/hebrew_speech.py files the clips by the same rule.
    static func key(_ text: String) -> String {
        let input = Array(text.lowercased().precomposedStringWithCanonicalMapping.unicodeScalars)
        var scalars = String.UnicodeScalarView()
        var pendingSpace = false
        for (index, scalar) in input.enumerated() {
            if (0x0591...0x05C7).contains(scalar.value),
               scalar.properties.generalCategory == .nonspacingMark {
                continue
            }
            let insideNumber = (scalar == "." || scalar == ",") && !pendingSpace
                && scalars.last.map(isDigit) == true
                && index + 1 < input.count && isDigit(input[index + 1])
            if !insideNumber, scalar.properties.isWhitespace || separators.contains(scalar) {
                pendingSpace = !scalars.isEmpty
                continue
            }
            if pendingSpace {
                scalars.append(" ")
                pendingSpace = false
            }
            scalars.append(apostrophes.contains(scalar) ? "'" : scalar)
        }
        return String(scalars)
    }

    private static func isDigit(_ scalar: Unicode.Scalar) -> Bool {
        (0x30...0x39).contains(scalar.value)
    }

    private static let separators = Set(".,!?…:;\"״“”„()[]-–—־/".unicodeScalars)
    private static let apostrophes = Set("׳‘’`´".unicodeScalars)

    private static let bundledManifest: Manifest? = {
        guard let url = Bundle.main.url(forResource: "manifest", withExtension: "json", subdirectory: folder),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(Manifest.self, from: data)
    }()
}

/// What the speech players used AVSpeechSynthesizer for, with recorded Hebrew: utterances
/// are said one after another, each from its recorded clips when it has them (one after
/// another), otherwise by the device voice.
@MainActor
final class MinikSpeaker: NSObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    /// Called once for each utterance that finishes or is cut off, as the synthesizer's
    /// didFinish and didCancel were.
    var onUtteranceEnd: (@MainActor (ObjectIdentifier) -> Void)?

    private let synthesizer = AVSpeechSynthesizer()
    private var waiting: [(utterance: AVSpeechUtterance, clips: [URL])] = []
    private var current: AVSpeechUtterance?
    private var clipPlayer: AVAudioPlayer?
    /// The current utterance's clips still to play after `clipPlayer`'s.
    private var nextClips: [URL] = []
    /// Stopped synthesizer utterances, kept until their didCancel arrives so a new
    /// utterance can never reuse their identity.
    private var stopping: [AVSpeechUtterance] = []

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ utterance: AVSpeechUtterance, languageTag: String) {
        let clips = HebrewRecordedSpeech.clipURLs(for: utterance.speechString, languageTag: languageTag) ?? []
        waiting.append((utterance, clips))
        playNext()
    }

    func stopSpeaking() {
        waiting.removeAll()
        nextClips.removeAll()
        guard let utterance = current else { return }
        current = nil
        if let player = clipPlayer {
            player.stop()
            clipPlayer = nil
            onUtteranceEnd?(ObjectIdentifier(utterance))
        } else {
            // The synthesizer's didCancel reports it.
            stopping.append(utterance)
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    private func playNext() {
        guard current == nil, !waiting.isEmpty else { return }
        let next = waiting.removeFirst()
        current = next.utterance
        if let first = next.clips.first, play(first, rate: next.utterance.rate) {
            nextClips = Array(next.clips.dropFirst())
            return
        }
        synthesizer.speak(next.utterance)
    }

    private func play(_ clip: URL, rate: Float) -> Bool {
        guard let player = try? AVAudioPlayer(contentsOf: clip) else { return false }
        player.delegate = self
        player.enableRate = true
        player.rate = rate / AVSpeechUtteranceDefaultSpeechRate
        clipPlayer = player
        if player.play() { return true }
        clipPlayer = nil
        return false
    }

    private func ended(_ id: ObjectIdentifier) {
        if let current, ObjectIdentifier(current) == id {
            self.current = nil
            clipPlayer = nil
            nextClips.removeAll()
            onUtteranceEnd?(id)
            playNext()
        } else if let index = stopping.firstIndex(where: { ObjectIdentifier($0) == id }) {
            stopping.remove(at: index)
            onUtteranceEnd?(id)
        }
    }

    private func clipEnded(_ id: ObjectIdentifier) {
        guard let clipPlayer, ObjectIdentifier(clipPlayer) == id, let current else { return }
        // A clip that fails to play mid-sentence ends the sentence there.
        while !nextClips.isEmpty {
            if play(nextClips.removeFirst(), rate: current.rate) { return }
        }
        ended(ObjectIdentifier(current))
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.ended(id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.ended(id) }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let id = ObjectIdentifier(player)
        Task { @MainActor [weak self] in self?.clipEnded(id) }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let id = ObjectIdentifier(player)
        Task { @MainActor [weak self] in self?.clipEnded(id) }
    }
}
