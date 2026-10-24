import AVFoundation
import Foundation
import os
import UIKit

// AndroidKit audio (DESIGN 4.6): android.media.SoundPool, ToneGenerator, AudioAttributes and the AudioManager
// stream constants, on one shared AVAudioEngine.
//
// What the app plays (spec 07 §4.10 and §6.2, spec 03 L121, spec 21 §4.4, spec 23 §4.6 and §7.4):
// * BasketballAudio's court foley: a SoundPool of 3 streams (USAGE_GAME / CONTENT_TYPE_SONIFICATION) with the three
//   short 22 050 Hz mono WAVs of res/raw, `play(id, v, v, 1, 0, 1f)`.
// * The journey tick: `ToneGenerator(STREAM_MUSIC, 25).startTone(TONE_PROP_ACK, 65)`.
// * BasketballSoundscape (Android 6c38131): a SoundPool of 5 streams for the whistle/applause/... effects, and
//   MediaPlayer for the menu music, the court crowd loops and the trumpet (AMediaPlayer.swift, on this mixer), with
//   AudioManager audio focus (AAudioFocus in AMediaPlayer.swift).
//
// Design:
// * AAudio.Mixer owns the AVAudioEngine and ONE AVAudioSourceNode (48 kHz stereo float) whose render block mixes every
//   SoundPool stream and ToneGenerator of the app, the role of Android's AudioFlinger mixer. Streams play PCM that was
//   decoded once at load time and converted to 48 kHz, so `play()` sounds in the next render cycle, any number of
//   streams overlap, and the audio thread neither allocates nor decodes.
// * The voice table is a fixed raw buffer of plain structs guarded by an os_unfair_lock: the main thread edits it
//   (play/stop/pause/...), the render thread advances it. Finished voices are removed later on the main thread.
// * The session follows the iOS precedent apps (Splash/Game/SplashAudio.swift, Sports/Game/SportsAudio.swift):
//   category .ambient, mode .default, no options. It mixes with other apps' audio and, unlike Android's media stream,
//   follows the Ring/Silent switch (spec 07 §10 item 7).
// * The engine starts on the first sound, restarts after interruptions, route/configuration changes and media-server
//   resets, and pauses after 15 s without any sounding voice (Android's mixer output also goes to standby when idle).

/// The shared audio session and engine host.
enum AAudio {
    /// Mixing rate of the shared engine: Android's primary output (and therefore ToneGenerator) runs at 48 kHz.
    static let SAMPLE_RATE: Double = 48000

    nonisolated(unsafe) private static var sessionConfigured = false

    /// Sets the app's AVAudioSession once: `.ambient`, mode `.default`, no options (Splash/Sports precedent). Safe to
    /// call any number of times; the app may call it at start, and every SoundPool / ToneGenerator calls it lazily.
    static func configureSession() {
        if sessionConfigured { return }
        sessionConfigured = true
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [])
        } catch {
            ALog.w("AAudio", "setCategory(.ambient) failed", error)
        }
    }

    /// Android SoundPool decodes on its own worker thread, in load order.
    static let decodeQueue = DispatchQueue(label: "com.appsbybros.minik.swish.soundpool.decode", qos: .userInitiated)

    // MARK: - Decoded samples

    /// One loaded SoundPool sample: deinterleaved Float32 channels (one or two), normally converted to SAMPLE_RATE.
    final class PCMData {
        let channelCount: Int
        let frameCount: Int
        /// The file's own rate: SoundPool's rate quantisation (`round(sampleRate * rate)`) works against it.
        let sourceSampleRate: Double
        /// The rate of the stored frames (SAMPLE_RATE after conversion, the source rate if conversion failed).
        let frameRate: Double
        let channel0: UnsafeMutablePointer<Float>
        /// Equal to `channel0` for a mono sample.
        let channel1: UnsafeMutablePointer<Float>

        init(channel0 samples0: [Float], channel1 samples1: [Float]?, sourceSampleRate: Double, frameRate: Double) {
            let count = samples1.map { min($0.count, samples0.count) } ?? samples0.count
            frameCount = count
            channelCount = samples1 == nil ? 1 : 2
            self.sourceSampleRate = sourceSampleRate
            self.frameRate = frameRate
            let first = PCMData.copy(samples0, count)
            channel0 = first
            channel1 = samples1.map { PCMData.copy($0, count) } ?? first
        }

        private static func copy(_ samples: [Float], _ count: Int) -> UnsafeMutablePointer<Float> {
            let p = UnsafeMutablePointer<Float>.allocate(capacity: max(count, 1))
            p.initialize(repeating: 0, count: max(count, 1))
            if count > 0 {
                samples.withUnsafeBufferPointer { p.update(from: $0.baseAddress!, count: count) }
            }
            return p
        }

        deinit {
            if channel1 != channel0 { channel1.deallocate() }
            channel0.deallocate()
        }
    }

    /// Decodes a sound file (WAV, MP3, ... — whatever AVAudioFile reads) and converts it to SAMPLE_RATE.
    /// Background thread (decodeQueue). nil = Android's load failure (status != 0).
    static func decode(_ url: URL) -> PCMData? {
        do {
            let file = try AVAudioFile(forReading: url)
            let format = file.processingFormat
            let length = file.length
            guard length > 0, length < Int64(Int32.max),
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(length)) else {
                return nil
            }
            try file.read(into: buffer)
            guard format.channelCount > 0, buffer.frameLength > 0, let input = buffer.floatChannelData else { return nil }
            let stereo = format.channelCount >= 2
            if format.sampleRate != SAMPLE_RATE, let converted = resample(buffer, SAMPLE_RATE) {
                return PCMData(channel0: converted.0, channel1: stereo ? converted.1 : nil,
                               sourceSampleRate: format.sampleRate, frameRate: SAMPLE_RATE)
            }
            let frames = Int(buffer.frameLength)
            let c0 = Array(UnsafeBufferPointer(start: input[0], count: frames))
            let c1: [Float]? = stereo ? Array(UnsafeBufferPointer(start: input[1], count: frames)) : nil
            return PCMData(channel0: c0, channel1: c1, sourceSampleRate: format.sampleRate, frameRate: format.sampleRate)
        } catch {
            return nil
        }
    }

    /// Box for the converter's one-shot input block.
    private final class InputOnce {
        var delivered = false
    }

    /// High-quality sample-rate conversion of a whole buffer (first two channels). nil when AVAudioConverter fails.
    private static func resample(_ input: AVAudioPCMBuffer, _ rate: Double) -> ([Float], [Float])? {
        let channels = min(input.format.channelCount, 2)
        guard let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: channels,
                                            interleaved: false),
              let converter = AVAudioConverter(from: input.format, to: outFormat),
              let chunk = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: 4096) else {
            return nil
        }
        if input.format.channelCount > 2 { converter.channelMap = [0, 1] }
        converter.sampleRateConverterQuality = AVAudioQuality.max.rawValue
        var out0: [Float] = []
        var out1: [Float] = []
        out0.reserveCapacity(Int(Double(input.frameLength) * rate / input.format.sampleRate) + 64)
        let once = InputOnce()
        while true {
            chunk.frameLength = 0
            var error: NSError?
            let status = converter.convert(to: chunk, error: &error) { _, outStatus in
                if once.delivered {
                    outStatus.pointee = .endOfStream
                    return nil
                }
                once.delivered = true
                outStatus.pointee = .haveData
                return input
            }
            if status == .error { return nil }
            if chunk.frameLength > 0, let data = chunk.floatChannelData {
                let n = Int(chunk.frameLength)
                out0.append(contentsOf: UnsafeBufferPointer(start: data[0], count: n))
                if channels > 1 { out1.append(contentsOf: UnsafeBufferPointer(start: data[1], count: n)) }
            }
            if status != .haveData { break }
        }
        if out0.isEmpty { return nil }
        return (out0, channels > 1 ? out1 : out0)
    }

    // MARK: - Voices

    enum VoiceState {
        case playing
        /// Fading out to `paused` (AudioFlinger ramps the volume down on pause).
        case pausing
        case paused
        /// Fading out to `finished` (SoundPool stop/steal: volume to 0, then the track stops).
        case stopping
        case finished
    }

    /// One sounding stream in the mixer: a SoundPool stream (PCM) or a ToneGenerator (tone). Plain data only, so the
    /// render thread copies and edits it without reference counting.
    struct Voice {
        var id: Int
        var pcm: Unmanaged<PCMData>?
        var tone: Unmanaged<ToneRenderer>?
        var channel0: UnsafeMutablePointer<Float>?
        var channel1: UnsafeMutablePointer<Float>?
        var frameCount: Int
        /// Read position in stored frames.
        var position: Double
        /// Stored frames per output frame.
        var step: Double
        /// SoundPool loop: -1 forever, 0 play once, n = n more times.
        var loopsLeft: Int
        var gainLeft: Float
        var gainRight: Float
        /// Click-free start/stop ramp, 0...1.
        var fade: Float
        var state: VoiceState
    }

    // MARK: - Mixer (the AudioFlinger of the app)

    final class Mixer {
        /// The app's mixer, hosting the AVAudioEngine.
        nonisolated(unsafe) static let shared = Mixer(engineEnabled: true)

        static let MAX_VOICES = 64
        /// Fade length for stop / steal / pause / resume: 5 ms at 48 kHz.
        static let RAMP_FRAMES = 240
        static let IDLE_SECONDS: Double = 15
        private static let SCRATCH_FRAMES = 1024

        /// false: an offline mixer for tests (rendered with `render(frames:)`, never touches AVFoundation).
        let engineEnabled: Bool
        private let lock: UnsafeMutablePointer<os_unfair_lock>
        private let voices: UnsafeMutablePointer<Voice>
        private var voiceCount = 0
        private var nextVoiceID = 0
        private let scratch: UnsafeMutablePointer<Float>
        private let rampStep: Float = 1 / Float(Mixer.RAMP_FRAMES)

        private var engine: AVAudioEngine?
        private var sourceNode: AVAudioSourceNode?
        private var engineObserver: NSObjectProtocol?
        private var observers: [NSObjectProtocol] = []
        private var idleCheckScheduled = false
        private var idleSince: Double?

        init(engineEnabled: Bool) {
            self.engineEnabled = engineEnabled
            lock = .allocate(capacity: 1)
            lock.initialize(to: os_unfair_lock())
            voices = .allocate(capacity: Mixer.MAX_VOICES)
            scratch = .allocate(capacity: Mixer.SCRATCH_FRAMES)
            scratch.initialize(repeating: 0, count: Mixer.SCRATCH_FRAMES)
            if engineEnabled { installObservers() }
        }

        deinit {
            for o in observers { NotificationCenter.default.removeObserver(o) }
            if let o = engineObserver { NotificationCenter.default.removeObserver(o) }
            for i in 0..<voiceCount {
                voices[i].pcm?.release()
                voices[i].tone?.release()
            }
            voices.deallocate()
            scratch.deallocate()
            lock.deinitialize(count: 1)
            lock.deallocate()
        }

        /// Runs `body` while holding the mixer lock (main thread; ToneGenerator state changes).
        func locked<T>(_ body: () -> T) -> T {
            os_unfair_lock_lock(lock)
            defer { os_unfair_lock_unlock(lock) }
            return body()
        }

        /// The session is configured on first use (not for the offline test mixer).
        func prepareSession() {
            if engineEnabled { AAudio.configureSession() }
        }

        // MARK: Main-thread voice control

        /// Adds a SoundPool stream; 0 when the table is full.
        func addPCM(_ data: PCMData, _ left: Float, _ right: Float, _ loop: Int, _ step: Double) -> Int {
            sweep()
            return locked {
                guard voiceCount < Mixer.MAX_VOICES else { return 0 }
                nextVoiceID += 1
                let voice = Voice(id: nextVoiceID, pcm: Unmanaged.passRetained(data), tone: nil,
                                  channel0: data.channel0, channel1: data.channel1, frameCount: data.frameCount,
                                  position: 0, step: step, loopsLeft: loop, gainLeft: left, gainRight: right,
                                  fade: 1, state: .playing)
                (voices + voiceCount).initialize(to: voice)
                voiceCount += 1
                return nextVoiceID
            }
        }

        /// Adds a ToneGenerator's renderer; it stays until the generator is released and silent.
        func addTone(_ renderer: ToneRenderer) -> Int {
            sweep()
            return locked {
                guard voiceCount < Mixer.MAX_VOICES else { return 0 }
                nextVoiceID += 1
                let voice = Voice(id: nextVoiceID, pcm: nil, tone: Unmanaged.passRetained(renderer), channel0: nil,
                                  channel1: nil, frameCount: 0, position: 0, step: 1, loopsLeft: 0, gainLeft: 1,
                                  gainRight: 1, fade: 1, state: .playing)
                (voices + voiceCount).initialize(to: voice)
                voiceCount += 1
                return nextVoiceID
            }
        }

        /// Lock held.
        private func index(_ id: Int) -> Int? {
            var i = 0
            while i < voiceCount {
                if voices[i].id == id { return i }
                i += 1
            }
            return nil
        }

        private func edit(_ id: Int, _ body: (inout Voice) -> Void) {
            locked {
                if let i = index(id) { body(&voices[i]) }
            }
        }

        /// The voice exists and has not finished (a paused voice is still active, like a paused SoundPool stream).
        func isActive(_ id: Int) -> Bool {
            return locked {
                guard let i = index(id) else { return false }
                return voices[i].state != .finished
            }
        }

        func stop(_ id: Int) {
            edit(id) { v in
                switch v.state {
                case .playing, .pausing: v.state = .stopping
                case .paused: v.state = .finished
                case .stopping, .finished: break
                }
            }
        }

        func pause(_ id: Int) {
            edit(id) { v in
                if v.state == .playing { v.state = .pausing }
            }
        }

        func resume(_ id: Int) {
            edit(id) { v in
                if v.state == .paused || v.state == .pausing { v.state = .playing }
            }
        }

        func setGains(_ id: Int, _ left: Float, _ right: Float) {
            edit(id) { v in
                v.gainLeft = left
                v.gainRight = right
            }
        }

        func setLoop(_ id: Int, _ loop: Int) {
            edit(id) { v in v.loopsLeft = loop }
        }

        func setStep(_ id: Int, _ step: Double) {
            edit(id) { v in v.step = step }
        }

        /// Removes finished voices (and tone voices of released, silent generators) and frees their data. While the
        /// engine does not render (start failed, interrupted, idle), fades cannot progress: stopping voices and
        /// released tones are dropped at once.
        func sweep() {
            var released: [Voice] = []
            let rendering = !engineEnabled || (engine?.isRunning ?? false)
            locked {
                var write = 0
                var read = 0
                while read < voiceCount {
                    let v = voices[read]
                    var remove = v.state == .finished || (v.state == .stopping && !rendering)
                    if let tone = v.tone?.takeUnretainedValue(), tone.released, !tone.trackActive || !rendering {
                        remove = true
                    }
                    if remove {
                        released.append(v)
                    } else {
                        if write != read { voices[write] = v }
                        write += 1
                    }
                    read += 1
                }
                voiceCount = write
            }
            for v in released {
                v.pcm?.release()
                v.tone?.release()
            }
        }

        /// Something is (or is about to be) audible: the engine must run.
        var hasSoundingVoices: Bool {
            return locked {
                var i = 0
                while i < voiceCount {
                    let v = voices[i]
                    if let tone = v.tone?.takeUnretainedValue() {
                        if tone.trackActive { return true }
                    } else if v.state == .playing || v.state == .pausing || v.state == .stopping {
                        return true
                    }
                    i += 1
                }
                return false
            }
        }

        // MARK: Render thread

        /// Mixes every voice into `outL` / `outR` (zeroed by the caller). false = nothing sounded (silence).
        func render(_ frames: Int, _ outL: UnsafeMutablePointer<Float>, _ outR: UnsafeMutablePointer<Float>) -> Bool {
            os_unfair_lock_lock(lock)
            defer { os_unfair_lock_unlock(lock) }
            var audible = false
            var i = 0
            while i < voiceCount {
                if voices[i].tone != nil {
                    if mixTone(&voices[i], frames, outL, outR) { audible = true }
                } else if mixPCM(&voices[i], frames, outL, outR) {
                    audible = true
                }
                i += 1
            }
            return audible
        }

        /// Offline rendering (tests): `frames` frames of the current mix.
        func render(frames: Int) -> (left: [Float], right: [Float]) {
            var left = [Float](repeating: 0, count: frames)
            var right = [Float](repeating: 0, count: frames)
            left.withUnsafeMutableBufferPointer { l in
                right.withUnsafeMutableBufferPointer { r in
                    _ = render(frames, l.baseAddress!, r.baseAddress!)
                }
            }
            return (left, right)
        }

        private func mixPCM(_ v: inout Voice, _ frames: Int, _ outL: UnsafeMutablePointer<Float>,
                            _ outR: UnsafeMutablePointer<Float>) -> Bool {
            if v.state == .finished || v.state == .paused { return false }
            guard let c0 = v.channel0, let c1 = v.channel1, v.frameCount > 0 else {
                v.state = .finished
                return false
            }
            let n = v.frameCount
            let end = Double(n)
            var f = 0
            while f < frames {
                switch v.state {
                case .playing:
                    if v.fade < 1 { v.fade = min(1, v.fade + rampStep) }
                case .pausing, .stopping:
                    v.fade -= rampStep
                    if v.fade <= 0 {
                        v.fade = 0
                        v.state = v.state == .pausing ? .paused : .finished
                        return true
                    }
                case .paused, .finished:
                    return true
                }
                while v.position >= end {
                    if v.loopsLeft == 0 {
                        v.state = .finished
                        return true
                    }
                    v.position -= end
                    if v.loopsLeft > 0 { v.loopsLeft -= 1 }
                }
                let ip = Int(v.position)
                let frac = Float(v.position - Double(ip))
                let next = ip + 1 < n ? ip + 1 : (v.loopsLeft != 0 ? 0 : ip)
                let a0 = c0[ip]
                let s0 = a0 + (c0[next] - a0) * frac
                let s1: Float
                if c1 == c0 {
                    s1 = s0
                } else {
                    let a1 = c1[ip]
                    s1 = a1 + (c1[next] - a1) * frac
                }
                outL[f] += s0 * v.gainLeft * v.fade
                outR[f] += s1 * v.gainRight * v.fade
                v.position += v.step
                f += 1
            }
            return true
        }

        private func mixTone(_ v: inout Voice, _ frames: Int, _ outL: UnsafeMutablePointer<Float>,
                             _ outR: UnsafeMutablePointer<Float>) -> Bool {
            if v.state == .finished { return false }
            guard let renderer = v.tone?.takeUnretainedValue() else {
                v.state = .finished
                return false
            }
            var audible = false
            var done = 0
            while done < frames {
                let chunk = min(frames - done, Mixer.SCRATCH_FRAMES)
                if renderer.render(scratch, chunk) {
                    audible = true
                    var k = 0
                    while k < chunk {
                        let s = scratch[k]
                        outL[done + k] += s
                        outR[done + k] += s
                        k += 1
                    }
                }
                done += chunk
            }
            return audible
        }

        // MARK: Engine (main thread)

        /// Starts (or restarts) the engine; called whenever something starts sounding.
        func ensureRunning() {
            guard engineEnabled else { return }
            AAudio.configureSession()
            if engine == nil { buildEngine() }
            guard let engine = engine else { return }
            if !engine.isRunning {
                do {
                    try AVAudioSession.sharedInstance().setActive(true, options: [])
                } catch {
                    ALog.w("AAudio", "setActive(true) failed", error)
                }
                do {
                    try engine.start()
                } catch {
                    ALog.w("AAudio", "AVAudioEngine.start failed", error)
                }
            }
            idleSince = nil
            scheduleIdleCheck()
        }

        private func buildEngine() {
            guard let format = AVAudioFormat(standardFormatWithSampleRate: AAudio.SAMPLE_RATE, channels: 2) else { return }
            let engine = AVAudioEngine()
            let node = AVAudioSourceNode(format: format) { [unowned self] isSilence, _, frameCount, bufferList in
                let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
                let n = Int(frameCount)
                guard buffers.count > 0, let raw0 = buffers[0].mData else { return noErr }
                let left = raw0.assumingMemoryBound(to: Float.self)
                left.update(repeating: 0, count: n)
                var right = left
                if buffers.count > 1, let raw1 = buffers[1].mData {
                    right = raw1.assumingMemoryBound(to: Float.self)
                    right.update(repeating: 0, count: n)
                }
                if !self.render(n, left, right) { isSilence.pointee = true }
                return noErr
            }
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            engine.prepare()
            if let o = engineObserver { NotificationCenter.default.removeObserver(o) }
            engineObserver = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
                    // The engine stopped itself (route or hardware format change); nodes stay connected.
                    self?.resumeIfNeeded()
                }
            self.engine = engine
            sourceNode = node
        }

        private func installObservers() {
            let center = NotificationCenter.default
            observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil,
                                                queue: .main) { [weak self] note in
                let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                guard raw == AVAudioSession.InterruptionType.ended.rawValue else { return }
                self?.resumeIfNeeded()
            })
            observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil,
                                                queue: .main) { [weak self] _ in
                self?.rebuildAfterReset()
            })
            observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil,
                                                queue: .main) { [weak self] _ in
                self?.resumeIfNeeded()
            })
        }

        private func resumeIfNeeded() {
            if hasSoundingVoices { ensureRunning() }
        }

        /// The media server restarted: every AVAudioEngine is invalid; build a new one (the voice table survives).
        private func rebuildAfterReset() {
            if let o = engineObserver { NotificationCenter.default.removeObserver(o) }
            engineObserver = nil
            engine = nil
            sourceNode = nil
            resumeIfNeeded()
        }

        private func scheduleIdleCheck() {
            if idleCheckScheduled { return }
            idleCheckScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.idleCheck()
            }
        }

        /// Once a second while the engine runs: drop finished voices; pause the engine after IDLE_SECONDS of silence.
        private func idleCheck() {
            idleCheckScheduled = false
            guard let engine = engine, engine.isRunning else {
                idleSince = nil
                return
            }
            sweep()
            if hasSoundingVoices {
                idleSince = nil
            } else {
                let now = ProcessInfo.processInfo.systemUptime
                if let since = idleSince {
                    if now - since >= Mixer.IDLE_SECONDS {
                        engine.pause()
                        idleSince = nil
                        return
                    }
                } else {
                    idleSince = now
                }
            }
            scheduleIdleCheck()
        }
    }
}

// MARK: - android.media.AudioManager (stream types)

/// android.media.AudioManager: the stream-type constants and (AMediaPlayer.swift) audio focus. On iOS every stream plays
/// through the one `.ambient` session and follows the device volume, as Android's STREAM_MUSIC follows the media volume.
/// `context.getSystemService(Context.AUDIO_SERVICE) as AudioManager` is `AAudioManager.shared`.
final class AAudioManager {
    static let STREAM_VOICE_CALL = 0
    static let STREAM_SYSTEM = 1
    static let STREAM_RING = 2
    static let STREAM_MUSIC = 3
    static let STREAM_ALARM = 4
    static let STREAM_NOTIFICATION = 5
    static let STREAM_DTMF = 8
    static let STREAM_ACCESSIBILITY = 10
    static let USE_DEFAULT_STREAM_TYPE = Int(Int32.min)
}

// MARK: - android.media.AudioAttributes

/// android.media.AudioAttributes (usage, content type, flags). Kept for API parity: on iOS all audio shares the
/// `.ambient` session, so the attributes do not change routing or volume.
final class AAudioAttributes {
    static let CONTENT_TYPE_UNKNOWN = 0
    static let CONTENT_TYPE_SPEECH = 1
    static let CONTENT_TYPE_MUSIC = 2
    static let CONTENT_TYPE_MOVIE = 3
    static let CONTENT_TYPE_SONIFICATION = 4

    static let USAGE_UNKNOWN = 0
    static let USAGE_MEDIA = 1
    static let USAGE_VOICE_COMMUNICATION = 2
    static let USAGE_VOICE_COMMUNICATION_SIGNALLING = 3
    static let USAGE_ALARM = 4
    static let USAGE_NOTIFICATION = 5
    static let USAGE_NOTIFICATION_RINGTONE = 6
    static let USAGE_NOTIFICATION_COMMUNICATION_REQUEST = 7
    static let USAGE_NOTIFICATION_COMMUNICATION_INSTANT = 8
    static let USAGE_NOTIFICATION_COMMUNICATION_DELAYED = 9
    static let USAGE_NOTIFICATION_EVENT = 10
    static let USAGE_ASSISTANCE_ACCESSIBILITY = 11
    static let USAGE_ASSISTANCE_NAVIGATION_GUIDANCE = 12
    static let USAGE_ASSISTANCE_SONIFICATION = 13
    static let USAGE_GAME = 14
    static let USAGE_VIRTUAL_SOURCE = 15
    static let USAGE_ASSISTANT = 16

    static let FLAG_AUDIBILITY_ENFORCED = 0x1 << 0
    static let FLAG_HW_AV_SYNC = 0x1 << 4
    static let FLAG_LOW_LATENCY = 0x1 << 8

    // Hidden framework values used by the legacy stream-type mapping and the Builder flag mask.
    private static let FLAG_SCO = 0x1 << 2
    private static let FLAG_BEACON = 0x1 << 3
    private static let FLAG_BYPASS_INTERRUPTION_POLICY = 0x1 << 6
    private static let FLAG_BYPASS_MUTE = 0x1 << 7
    private static let FLAG_ALL_API_SET = FLAG_AUDIBILITY_ENFORCED | FLAG_HW_AV_SYNC | FLAG_LOW_LATENCY
        | FLAG_BYPASS_INTERRUPTION_POLICY | FLAG_BYPASS_MUTE
    private static let USAGE_INVALID = -1
    // AudioSystem stream types that AudioManager does not expose.
    private static let STREAM_BLUETOOTH_SCO = 6
    private static let STREAM_SYSTEM_ENFORCED = 7
    private static let STREAM_TTS = 9
    private static let STREAM_ASSISTANT = 11

    let usage: Int
    let contentType: Int
    let flags: Int

    private init(usage: Int, contentType: Int, flags: Int) {
        self.usage = usage
        self.contentType = contentType
        self.flags = flags
    }

    func getUsage() -> Int { usage }
    func getContentType() -> Int { contentType }
    func getFlags() -> Int { flags }

    /// AudioAttributes.usageForStreamType.
    fileprivate static func usageForStreamType(_ streamType: Int) -> Int {
        switch streamType {
        case AAudioManager.STREAM_VOICE_CALL: return USAGE_VOICE_COMMUNICATION
        case STREAM_SYSTEM_ENFORCED, AAudioManager.STREAM_SYSTEM: return USAGE_ASSISTANCE_SONIFICATION
        case AAudioManager.STREAM_RING: return USAGE_NOTIFICATION_RINGTONE
        case AAudioManager.STREAM_MUSIC: return USAGE_MEDIA
        case AAudioManager.STREAM_ALARM: return USAGE_ALARM
        case AAudioManager.STREAM_NOTIFICATION: return USAGE_NOTIFICATION
        case STREAM_BLUETOOTH_SCO: return USAGE_VOICE_COMMUNICATION
        case AAudioManager.STREAM_DTMF: return USAGE_VOICE_COMMUNICATION_SIGNALLING
        case AAudioManager.STREAM_ACCESSIBILITY: return USAGE_ASSISTANCE_ACCESSIBILITY
        case STREAM_ASSISTANT: return USAGE_ASSISTANT
        default: return USAGE_UNKNOWN
        }
    }

    /// android.media.AudioAttributes.Builder.
    final class Builder {
        private var mUsage = AAudioAttributes.USAGE_INVALID
        private var mContentType = AAudioAttributes.CONTENT_TYPE_UNKNOWN
        private var mFlags = 0

        init() {}

        init(_ aa: AAudioAttributes) {
            mUsage = aa.usage
            mContentType = aa.contentType
            mFlags = aa.flags
        }

        /// Throws IllegalArgumentException("Invalid usage") on Android for an unknown value.
        @discardableResult
        func setUsage(_ usage: Int) -> Builder {
            precondition(usage >= AAudioAttributes.USAGE_UNKNOWN && usage <= AAudioAttributes.USAGE_ASSISTANT,
                         "Invalid usage \(usage)")
            mUsage = usage
            return self
        }

        /// Throws IllegalArgumentException("Invalid content type") on Android for an unknown value.
        @discardableResult
        func setContentType(_ contentType: Int) -> Builder {
            precondition(contentType >= AAudioAttributes.CONTENT_TYPE_UNKNOWN
                            && contentType <= AAudioAttributes.CONTENT_TYPE_SONIFICATION,
                         "Invalid content type \(contentType)")
            mContentType = contentType
            return self
        }

        @discardableResult
        func setFlags(_ flags: Int) -> Builder {
            mFlags |= flags & AAudioAttributes.FLAG_ALL_API_SET
            return self
        }

        @discardableResult
        func setLegacyStreamType(_ streamType: Int) -> Builder {
            precondition(streamType != AAudioManager.STREAM_ACCESSIBILITY,
                         "STREAM_ACCESSIBILITY is not a legacy stream type that was used for audio playback")
            return setInternalLegacyStreamType(streamType)
        }

        /// The legacy mapping without the device's audio product strategies (usage from usageForStreamType).
        @discardableResult
        func setInternalLegacyStreamType(_ streamType: Int) -> Builder {
            mContentType = AAudioAttributes.CONTENT_TYPE_UNKNOWN
            mUsage = AAudioAttributes.USAGE_UNKNOWN
            switch streamType {
            case AAudioManager.STREAM_VOICE_CALL:
                mContentType = AAudioAttributes.CONTENT_TYPE_SPEECH
            case AAudioAttributes.STREAM_SYSTEM_ENFORCED:
                mFlags |= AAudioAttributes.FLAG_AUDIBILITY_ENFORCED
                mContentType = AAudioAttributes.CONTENT_TYPE_SONIFICATION
            case AAudioManager.STREAM_SYSTEM, AAudioManager.STREAM_RING, AAudioManager.STREAM_ALARM,
                 AAudioManager.STREAM_NOTIFICATION, AAudioManager.STREAM_DTMF:
                mContentType = AAudioAttributes.CONTENT_TYPE_SONIFICATION
            case AAudioAttributes.STREAM_BLUETOOTH_SCO:
                mFlags |= AAudioAttributes.FLAG_SCO
                mContentType = AAudioAttributes.CONTENT_TYPE_SPEECH
            case AAudioAttributes.STREAM_TTS:
                mContentType = AAudioAttributes.CONTENT_TYPE_SONIFICATION
                mFlags |= AAudioAttributes.FLAG_BEACON
            case AAudioManager.STREAM_ACCESSIBILITY, AAudioAttributes.STREAM_ASSISTANT:
                mContentType = AAudioAttributes.CONTENT_TYPE_SPEECH
            case AAudioManager.STREAM_MUSIC:
                break   // leaving as CONTENT_TYPE_UNKNOWN
            default:
                ALog.e("AudioAttributes", "Invalid stream type \(streamType) for AudioAttributes")
            }
            if mUsage == AAudioAttributes.USAGE_UNKNOWN {
                mUsage = AAudioAttributes.usageForStreamType(streamType)
            }
            return self
        }

        func build() -> AAudioAttributes {
            var usage = mUsage == AAudioAttributes.USAGE_INVALID ? AAudioAttributes.USAGE_UNKNOWN : mUsage
            // Deprecated notification usages are remapped to USAGE_NOTIFICATION.
            switch usage {
            case AAudioAttributes.USAGE_NOTIFICATION_COMMUNICATION_REQUEST,
                 AAudioAttributes.USAGE_NOTIFICATION_COMMUNICATION_INSTANT,
                 AAudioAttributes.USAGE_NOTIFICATION_COMMUNICATION_DELAYED:
                usage = AAudioAttributes.USAGE_NOTIFICATION
            default:
                break
            }
            return AAudioAttributes(usage: usage, contentType: mContentType, flags: mFlags)
        }
    }
}

// MARK: - android.media.SoundPool

/// android.media.SoundPool on the shared AAudio mixer, with the native (Android 11+) SoundPool semantics:
/// * `load` returns sound ids 1, 2, 3, ... at once and decodes in the background, in order; the load-complete listener
///   then runs on the main thread with status 0 (or non-zero on failure). Only a READY sound plays.
/// * `play` returns stream ids 1, 2, 3, ... (0 = failure). At most `maxStreams` streams are active (playing or
///   paused); when all are busy, the oldest stream with the lowest priority <= the new priority is stolen (stopped
///   with a short fade); if every active stream has a higher priority, play returns 0.
/// * Argument checks: volumes outside 0...1 play at 1.0 on both sides, the rate is clamped to 0.125...8, loop < -1 is
///   -1; the rate is quantised like Android (`round(sampleRate * rate)`).
/// * `pause`/`resume`/`stop`/`setVolume`/`setPriority`/`setLoop`/`setRate` act on a live stream id and do nothing
///   otherwise; `autoPause` pauses every playing stream and marks it, `autoResume` resumes the marked ones.
/// * After `release()` every call is a no-op (play/load return 0).
/// Not final: tests substitute a recording pool (BasketballAudio's seam).
class ASoundPool {
    /// SoundPool.OnLoadCompleteListener: (soundPool, sampleId, status), status 0 = success.
    typealias OnLoadCompleteListener = (_ soundPool: ASoundPool, _ sampleId: Int, _ status: Int) -> Void

    static let TAG = "SoundPool"
    /// Status passed to the listener when a sound could not be decoded.
    static let STATUS_LOAD_FAILED = -1
    /// StreamMap kMaxStreams: maxStreams is clamped to 1...32.
    private static let kMaxStreams = 32

    /// android.media.SoundPool.Builder.
    final class Builder {
        private var mMaxStreams = 1
        private var mAudioAttributes: AAudioAttributes?

        init() {}

        /// Android throws IllegalArgumentException for a value <= 0.
        @discardableResult
        func setMaxStreams(_ maxStreams: Int) -> Builder {
            precondition(maxStreams > 0, "Strictly positive value required for the maximum number of streams")
            mMaxStreams = maxStreams
            return self
        }

        @discardableResult
        func setAudioAttributes(_ attributes: AAudioAttributes) -> Builder {
            mAudioAttributes = attributes
            return self
        }

        func build() -> ASoundPool {
            let attributes = mAudioAttributes
                ?? AAudioAttributes.Builder().setUsage(AAudioAttributes.USAGE_MEDIA).build()
            return ASoundPool(maxStreams: mMaxStreams, attributes: attributes)
        }
    }

    private enum SoundState {
        case loading
        case ready(AAudio.PCMData)
        case failed
    }

    private struct StreamEntry {
        let streamID: Int
        let soundID: Int
        let voiceID: Int
        var priority: Int
        var paused = false
        var autoPaused = false
        let sourceSampleRate: Double
        let frameRate: Double
    }

    let maxStreams: Int
    let attributes: AAudioAttributes
    private let mixer: AAudio.Mixer
    private var released = false
    private var nextSoundID = 0
    private var nextStreamIDValue = 0
    private var sounds: [Int: SoundState] = [:]
    /// Active streams, oldest first (StreamManager kStealActiveStream_OldestFirst).
    private var streams: [StreamEntry] = []
    private var listener: OnLoadCompleteListener?

    init(maxStreams: Int, attributes: AAudioAttributes, mixer: AAudio.Mixer = AAudio.Mixer.shared) {
        self.maxStreams = min(max(maxStreams, 1), ASoundPool.kMaxStreams)
        self.attributes = attributes
        self.mixer = mixer
        mixer.prepareSession()
    }

    /// Deprecated `SoundPool(maxStreams, streamType, srcQuality)`.
    convenience init(_ maxStreams: Int, _ streamType: Int, _ srcQuality: Int) {
        self.init(maxStreams: maxStreams,
                  attributes: AAudioAttributes.Builder().setInternalLegacyStreamType(streamType).build())
    }

    deinit {
        releaseStreams()
    }

    // MARK: Loading

    /// `load(context, R.raw.x, priority)`. The priority has no effect (Android: "use a value of 1").
    func load(_ resId: ARawRes, _ priority: Int) -> Int {
        if released { return 0 }
        guard let url = AResources.rawURL(resId) else {
            ALog.e(ASoundPool.TAG, "load: raw resource \(resId) not found")
            return 0
        }
        return load(url, priority)
    }

    /// `load(path, priority)` for a file URL.
    func load(_ url: URL, _ priority: Int) -> Int {
        if released { return 0 }
        let soundID = allocateSoundID()
        sounds[soundID] = .loading
        AAudio.decodeQueue.async { [weak self] in
            let data = AAudio.decode(url)
            DispatchQueue.main.async { [weak self] in
                self?.loadFinished(soundID, data)
            }
        }
        return soundID
    }

    /// Registers an already decoded sample as READY at once, without a listener callback (tests, generated sounds).
    func loadDecoded(_ data: AAudio.PCMData) -> Int {
        if released { return 0 }
        let soundID = allocateSoundID()
        sounds[soundID] = .ready(data)
        return soundID
    }

    private func allocateSoundID() -> Int {
        nextSoundID += 1
        if nextSoundID > Int(Int32.max) { nextSoundID = 1 }
        return nextSoundID
    }

    private func loadFinished(_ soundID: Int, _ data: AAudio.PCMData?) {
        guard !released, sounds[soundID] != nil else { return }   // released or unloaded meanwhile
        if let data = data {
            sounds[soundID] = .ready(data)
        } else {
            ALog.e(ASoundPool.TAG, "Unable to load sample \(soundID)")
            sounds[soundID] = .failed
        }
        listener?(self, soundID, data != nil ? 0 : ASoundPool.STATUS_LOAD_FAILED)
    }

    /// true if the sound was unloaded now, false if it was already unloaded. Streams playing it continue.
    @discardableResult
    func unload(_ soundID: Int) -> Bool {
        if released { return false }
        return sounds.removeValue(forKey: soundID) != nil
    }

    /// The listener runs on the main thread for every finished load, with status 0 on success.
    func setOnLoadCompleteListener(_ listener: OnLoadCompleteListener?) {
        self.listener = listener
    }

    // MARK: Playback

    @discardableResult
    func play(_ soundID: Int, _ leftVolume: Float, _ rightVolume: Float, _ priority: Int, _ loop: Int,
              _ rate: Float) -> Int {
        if released { return 0 }
        var leftVolume = leftVolume
        var rightVolume = rightVolume
        var loop = loop
        var rate = rate
        ASoundPool.checkVolume(&leftVolume, &rightVolume)
        ASoundPool.checkLoop(&loop)
        ASoundPool.checkRate(&rate)
        guard case .ready(let data)? = sounds[soundID] else {
            ALog.w(ASoundPool.TAG, "play soundID \(soundID) not READY")
            return 0
        }
        sweepStreams()
        if streams.count >= maxStreams {
            guard let victim = ASoundPool.streamToSteal(streams.map { $0.priority }, priority) else {
                ALog.d(ASoundPool.TAG, "play: unable to find stream, returning 0")
                return 0
            }
            mixer.stop(streams[victim].voiceID)
            streams.remove(at: victim)
        }
        let voiceID = mixer.addPCM(data, leftVolume, rightVolume, loop,
                                   ASoundPool.step(data.sourceSampleRate, data.frameRate, rate))
        if voiceID == 0 { return 0 }
        let streamID = allocateStreamID()
        streams.append(StreamEntry(streamID: streamID, soundID: soundID, voiceID: voiceID, priority: priority,
                                   sourceSampleRate: data.sourceSampleRate, frameRate: data.frameRate))
        mixer.ensureRunning()
        return streamID
    }

    func pause(_ streamID: Int) {
        guard let i = liveStream(streamID) else { return }
        if !streams[i].paused {
            streams[i].paused = true
            mixer.pause(streams[i].voiceID)
        }
    }

    func resume(_ streamID: Int) {
        guard let i = liveStream(streamID) else { return }
        if streams[i].paused {
            streams[i].paused = false
            mixer.resume(streams[i].voiceID)
            mixer.ensureRunning()
        }
    }

    func autoPause() {
        if released { return }
        sweepStreams()
        for i in streams.indices where !streams[i].paused {
            streams[i].paused = true
            streams[i].autoPaused = true
            mixer.pause(streams[i].voiceID)
        }
    }

    func autoResume() {
        if released { return }
        sweepStreams()
        var resumed = false
        for i in streams.indices where streams[i].autoPaused {
            if streams[i].paused {
                streams[i].paused = false
                mixer.resume(streams[i].voiceID)
                resumed = true
            }
            streams[i].autoPaused = false
        }
        if resumed { mixer.ensureRunning() }
    }

    func stop(_ streamID: Int) {
        guard let i = liveStream(streamID) else { return }
        mixer.stop(streams[i].voiceID)
        streams.remove(at: i)
    }

    func setVolume(_ streamID: Int, _ leftVolume: Float, _ rightVolume: Float) {
        var leftVolume = leftVolume
        var rightVolume = rightVolume
        ASoundPool.checkVolume(&leftVolume, &rightVolume)
        guard let i = liveStream(streamID) else { return }
        mixer.setGains(streams[i].voiceID, leftVolume, rightVolume)
    }

    func setVolume(_ streamID: Int, _ volume: Float) {
        setVolume(streamID, volume, volume)
    }

    func setPriority(_ streamID: Int, _ priority: Int) {
        guard let i = liveStream(streamID) else { return }
        streams[i].priority = priority
    }

    func setLoop(_ streamID: Int, _ loop: Int) {
        var loop = loop
        ASoundPool.checkLoop(&loop)
        guard let i = liveStream(streamID) else { return }
        mixer.setLoop(streams[i].voiceID, loop)
    }

    func setRate(_ streamID: Int, _ rate: Float) {
        var rate = rate
        ASoundPool.checkRate(&rate)
        guard let i = liveStream(streamID) else { return }
        mixer.setStep(streams[i].voiceID, ASoundPool.step(streams[i].sourceSampleRate, streams[i].frameRate, rate))
    }

    /// Stops every stream and unloads every sound; the pool is unusable afterwards.
    func release() {
        releaseStreams()
    }

    private func releaseStreams() {
        if released { return }
        released = true
        for s in streams { mixer.stop(s.voiceID) }
        streams.removeAll()
        sounds.removeAll()
        listener = nil
    }

    /// The live streams' ids, oldest first.
    var activeStreamIDs: [Int] {
        sweepStreams()
        return streams.map { $0.streamID }
    }

    private func liveStream(_ streamID: Int) -> Int? {
        if released { return nil }
        sweepStreams()
        return streams.firstIndex { $0.streamID == streamID }
    }

    /// A stream whose sound ended is available again.
    private func sweepStreams() {
        mixer.sweep()
        streams.removeAll { !mixer.isActive($0.voiceID) }
    }

    private func allocateStreamID() -> Int {
        nextStreamIDValue += 1
        if nextStreamIDValue > Int(Int32.max) { nextStreamIDValue = 1 }
        return nextStreamIDValue
    }

    // MARK: Native SoundPool rules

    /// StreamManager::queueForPlay steal rule: among the active streams (oldest first), the first one with the
    /// lowest priority, provided that priority is <= the new stream's priority. nil = no stream can be stolen.
    static func streamToSteal(_ priorities: [Int], _ priority: Int) -> Int? {
        var found: Int?
        for (i, p) in priorities.enumerated() where p <= priority {
            if let f = found {
                if priorities[f] > p { found = i }
            } else {
                found = i
            }
        }
        return found
    }

    /// std::clamp.
    private static func clamp(_ v: Float, _ lo: Float, _ hi: Float) -> Float {
        return v < lo ? lo : (hi < v ? hi : v)
    }

    /// SoundPool checkVolume: a volume outside 0...1 (or NaN) plays both sides at 1.0 "for backward compatibility".
    static func checkVolume(_ leftVolume: inout Float, _ rightVolume: inout Float) {
        if leftVolume != clamp(leftVolume, 0, 1) || rightVolume != clamp(rightVolume, 0, 1) {
            ALog.i(TAG, "volume l=\(leftVolume) r=\(rightVolume) out of (0.f, 1.f) bounds, using 1.f")
            leftVolume = 1
            rightVolume = 1
        }
    }

    /// SoundPool checkRate: clamped to 0.125...8. (A NaN rate, undefined on Android, plays at 1.)
    static func checkRate(_ rate: inout Float) {
        if rate.isNaN {
            rate = 1
        } else if rate != clamp(rate, 0.125, 8) {
            ALog.i(TAG, "rate \(rate) out of (0.125f, 8.f) bounds, clamping")
            rate = clamp(rate, 0.125, 8)
        }
    }

    /// SoundPool checkLoop: below -1 means forever.
    static func checkLoop(_ loop: inout Int) {
        if loop < -1 {
            ALog.i(TAG, "loop \(loop), should be >= -1")
            loop = -1
        }
    }

    /// Stored frames per output frame. Android plays the sample at `uint32_t(sampleRate * rate + 0.5)` Hz.
    static func step(_ sourceSampleRate: Double, _ frameRate: Double, _ rate: Float) -> Double {
        let hz = Float(sourceSampleRate) * rate + 0.5
        guard sourceSampleRate > 0, frameRate > 0, hz.isFinite, hz >= 1, hz < Float(UInt32.max) else { return 1 }
        let trackRate = Double(UInt32(hz))
        return trackRate / sourceSampleRate * frameRate / AAudio.SAMPLE_RATE
    }
}

// MARK: - android.media.ToneGenerator

/// android.media.ToneGenerator: the AOSP tone sequencer and WaveGenerator (frameworks/av ToneGenerator.cpp) ported
/// sample for sample at Android's 48 kHz output rate, played through the shared mixer.
/// * Volume: the constructor's 0...100 goes through AudioSystem::linearToLog (0.5 dB per step below 100), so
///   volume 25 = −37.5 dB (gain 0.01334); each sine of an N-frequency segment has amplitude 0.9 / (N + 1) of full
///   scale (AOSP numWaves counts one more than the frequencies).
/// * Timing: like Android the sequencer runs in AudioTrack callback buffers (here one 4 ms HAL period, 192 frames);
///   a duration limit stops the tone at the first buffer past it with a linear fade over that buffer, so
///   `startTone(TONE_PROP_ACK, 65)` is one 1200 Hz beep of 64 ms + a 4 ms fade (TONE_PROP_ACK = 1200 Hz, 100 ms on,
///   100 ms off, two bursts).
/// * Tones: DTMF 0–15, the CEPT supervisory tones 16–23 and the proprietary tones 24–28. The CDMA / IS-95 tones
///   (29–98) are not ported (unused); startTone returns false for them.
/// * startTone while a tone plays fades the old one out and starts the new one; stopTone and release fade out.
///   Android blocks the caller until the audio thread has started/stopped the tone; here the calls return at once.
final class AToneGenerator {
    static let TONE_UNKNOWN = -1
    static let TONE_DTMF_0 = 0
    static let TONE_DTMF_1 = 1
    static let TONE_DTMF_2 = 2
    static let TONE_DTMF_3 = 3
    static let TONE_DTMF_4 = 4
    static let TONE_DTMF_5 = 5
    static let TONE_DTMF_6 = 6
    static let TONE_DTMF_7 = 7
    static let TONE_DTMF_8 = 8
    static let TONE_DTMF_9 = 9
    static let TONE_DTMF_S = 10
    static let TONE_DTMF_P = 11
    static let TONE_DTMF_A = 12
    static let TONE_DTMF_B = 13
    static let TONE_DTMF_C = 14
    static let TONE_DTMF_D = 15
    static let TONE_SUP_DIAL = 16
    static let TONE_SUP_BUSY = 17
    static let TONE_SUP_CONGESTION = 18
    static let TONE_SUP_RADIO_ACK = 19
    static let TONE_SUP_RADIO_NOTAVAIL = 20
    static let TONE_SUP_ERROR = 21
    static let TONE_SUP_CALL_WAITING = 22
    static let TONE_SUP_RINGTONE = 23
    static let TONE_PROP_BEEP = 24
    static let TONE_PROP_ACK = 25
    static let TONE_PROP_NACK = 26
    static let TONE_PROP_PROMPT = 27
    static let TONE_PROP_BEEP2 = 28
    static let MAX_VOLUME = 100
    static let MIN_VOLUME = 0

    static let TAG = "ToneGenerator"

    let streamType: Int
    private let mixer: AAudio.Mixer
    private let renderer: AAudio.ToneRenderer
    private var voiceID = 0
    private var released = false

    /// `ToneGenerator(streamType, volume)`, volume in percent of the maximum (0–100).
    init(_ streamType: Int, _ volume: Int, mixer: AAudio.Mixer = AAudio.Mixer.shared) {
        self.streamType = streamType
        self.mixer = mixer
        renderer = AAudio.ToneRenderer(UInt32(AAudio.SAMPLE_RATE), AToneGenerator.linearToLog(volume))
        mixer.prepareSession()
    }

    deinit {
        releaseTone()
    }

    /// AudioSystem::linearToLog: `volume ? exp((100 - volume) * -0.5 dB) : 0`, then AudioTrack::setVolume (which
    /// rejects values above 1 and keeps its default 1).
    static func linearToLog(_ volume: Int) -> Float {
        let kdbConvert: Float = -0.5 * 2.302585093 / 20
        let gain: Float = volume != 0 ? Float(exp(Double(Float(100 - volume) * kdbConvert))) : 0
        return gain >= 0 && gain <= 1 ? gain : 1
    }

    /// `startTone(toneType)` = `startTone(toneType, -1)`: the tone's own length (forever for continuous tones).
    @discardableResult
    func startTone(_ toneType: Int) -> Bool {
        return startTone(toneType, -1)
    }

    /// Plays `toneType`, limited to `durationMs` when the tone is longer (a negative duration does not limit it).
    @discardableResult
    func startTone(_ toneType: Int, _ durationMs: Int) -> Bool {
        if released {
            // Android: RuntimeException("Method called after release()").
            ALog.e(AToneGenerator.TAG, "startTone: method called after release()")
            return false
        }
        guard let descriptor = AAudio.ToneRenderer.descriptor(toneType) else { return false }
        if voiceID == 0 {
            voiceID = mixer.addTone(renderer)
            if voiceID == 0 { return false }
        }
        let renderer = self.renderer
        let started = mixer.locked { renderer.startTone(descriptor, Int32(truncatingIfNeeded: durationMs)) }
        mixer.ensureRunning()
        return started
    }

    func stopTone() {
        if released { return }
        let renderer = self.renderer
        mixer.locked { renderer.stopTone() }
    }

    /// Stops the tone (with its fade) and frees the generator.
    func release() {
        releaseTone()
    }

    private func releaseTone() {
        if released { return }
        released = true
        let renderer = self.renderer
        mixer.locked {
            renderer.stopTone()
            renderer.released = true
        }
    }
}

extension AAudio {
    /// The AOSP ToneGenerator state machine (ToneGenerator::onMoreData / prepareWave / startTone / stopTone) and its
    /// WaveGenerator. Every field is guarded by the mixer lock: the main thread calls startTone/stopTone, the render
    /// thread calls render. Renders 16-bit samples exactly like AOSP and hands them out as floats scaled by the
    /// AudioTrack volume.
    final class ToneRenderer {
        enum ToneState {
            case TONE_IDLE, TONE_INIT, TONE_STARTING, TONE_PLAYING, TONE_STOPPING, TONE_STOPPED, TONE_RESTARTING
        }

        static let TONEGEN_MAX_WAVES = 3
        static let TONEGEN_MAX_SEGMENTS = 12
        static let TONEGEN_INF: UInt32 = 0xFFFF_FFFF
        static let TONEGEN_GAIN: Float = 0.9
        static let WAVEGEN_START = 0
        static let WAVEGEN_CONT = 1
        static let WAVEGEN_STOP = 2
        private static let SEGMENT_SLOTS = TONEGEN_MAX_SEGMENTS + 1
        private static let MAX_WAVE_GENERATORS = TONEGEN_MAX_WAVES * TONEGEN_MAX_SEGMENTS

        /// ToneGenerator::ToneSegment: duration in ms (0 ends the sequence), up to 3 frequencies (0-terminated).
        struct ToneSegment {
            var duration: UInt32
            var waveFreq0: UInt16
            var waveFreq1: UInt16
            var waveFreq2: UInt16
            var waveFreq3: UInt16
            var loopCnt: UInt16
            var loopIndx: UInt16

            func waveFreq(_ i: Int) -> UInt16 {
                switch i {
                case 0: return waveFreq0
                case 1: return waveFreq1
                case 2: return waveFreq2
                case 3: return waveFreq3
                default: return 0
                }
            }
        }

        /// ToneGenerator::ToneDescriptor.
        struct ToneDescriptor {
            let segments: [ToneSegment]
            let repeatCnt: UInt
            let repeatSegment: UInt
        }

        private static func seg(_ duration: UInt32, _ freqs: UInt16...) -> ToneSegment {
            return ToneSegment(duration: duration, waveFreq0: freqs.count > 0 ? freqs[0] : 0,
                               waveFreq1: freqs.count > 1 ? freqs[1] : 0, waveFreq2: freqs.count > 2 ? freqs[2] : 0,
                               waveFreq3: 0, loopCnt: 0, loopIndx: 0)
        }

        private static func dtmf(_ high: UInt16, _ low: UInt16) -> ToneDescriptor {
            return ToneDescriptor(segments: [seg(TONEGEN_INF, high, low), seg(0)], repeatCnt: UInt(TONEGEN_INF),
                                  repeatSegment: 0)
        }

        /// ToneGenerator::sToneDescriptors[0...28] (DTMF, CEPT supervisory, proprietary).
        static let sToneDescriptors: [ToneDescriptor] = {
            let inf = UInt(TONEGEN_INF)
            return [
                dtmf(1336, 941),   // TONE_DTMF_0
                dtmf(1209, 697),   // TONE_DTMF_1
                dtmf(1336, 697),   // TONE_DTMF_2
                dtmf(1477, 697),   // TONE_DTMF_3
                dtmf(1209, 770),   // TONE_DTMF_4
                dtmf(1336, 770),   // TONE_DTMF_5
                dtmf(1477, 770),   // TONE_DTMF_6
                dtmf(1209, 852),   // TONE_DTMF_7
                dtmf(1336, 852),   // TONE_DTMF_8
                dtmf(1477, 852),   // TONE_DTMF_9
                dtmf(1209, 941),   // TONE_DTMF_S
                dtmf(1477, 941),   // TONE_DTMF_P
                dtmf(1633, 697),   // TONE_DTMF_A
                dtmf(1633, 770),   // TONE_DTMF_B
                dtmf(1633, 852),   // TONE_DTMF_C
                dtmf(1633, 941),   // TONE_DTMF_D
                ToneDescriptor(segments: [seg(TONEGEN_INF, 425), seg(0)], repeatCnt: inf, repeatSegment: 0),
                // TONE_SUP_DIAL
                ToneDescriptor(segments: [seg(500, 425), seg(500), seg(0)], repeatCnt: inf, repeatSegment: 0),
                // TONE_SUP_BUSY
                ToneDescriptor(segments: [seg(200, 425), seg(200), seg(0)], repeatCnt: inf, repeatSegment: 0),
                // TONE_SUP_CONGESTION
                ToneDescriptor(segments: [seg(200, 425), seg(0)], repeatCnt: 0, repeatSegment: 0),
                // TONE_SUP_RADIO_ACK
                ToneDescriptor(segments: [seg(200, 425), seg(200), seg(0)], repeatCnt: 2, repeatSegment: 0),
                // TONE_SUP_RADIO_NOTAVAIL
                ToneDescriptor(segments: [seg(330, 950, 1400, 1800), seg(1000), seg(0)], repeatCnt: inf,
                               repeatSegment: 0),
                // TONE_SUP_ERROR
                ToneDescriptor(segments: [seg(200, 425), seg(600), seg(200, 425), seg(3000), seg(0)], repeatCnt: inf,
                               repeatSegment: 0),
                // TONE_SUP_CALL_WAITING
                ToneDescriptor(segments: [seg(1000, 425), seg(4000), seg(0)], repeatCnt: inf, repeatSegment: 0),
                // TONE_SUP_RINGTONE
                ToneDescriptor(segments: [seg(40, 400, 1200), seg(0)], repeatCnt: 0, repeatSegment: 0),
                // TONE_PROP_BEEP
                ToneDescriptor(segments: [seg(100, 1200), seg(100), seg(0)], repeatCnt: 1, repeatSegment: 0),
                // TONE_PROP_ACK
                ToneDescriptor(segments: [seg(400, 300, 400, 500), seg(0)], repeatCnt: 0, repeatSegment: 0),
                // TONE_PROP_NACK
                ToneDescriptor(segments: [seg(200, 400, 1200), seg(0)], repeatCnt: 0, repeatSegment: 0),
                // TONE_PROP_PROMPT
                ToneDescriptor(segments: [seg(40, 400, 1200), seg(200), seg(40, 400, 1200), seg(0)], repeatCnt: 0,
                               repeatSegment: 0),
                // TONE_PROP_BEEP2
            ]
        }()

        static func descriptor(_ toneType: Int) -> ToneDescriptor? {
            return toneType >= 0 && toneType < sToneDescriptors.count ? sToneDescriptors[toneType] : nil
        }

        /// ToneGenerator::WaveGenerator: a fixed-point sine resonator (Q14 coefficient, Q15 amplitude).
        struct WaveGenerator {
            static let GEN_AMP = 32000
            static let S_Q14 = 14
            static let S_Q15 = 15

            var frequency: UInt16
            var mA1_Q14: Int16
            var mS2_0: Int16
            var mAmplitude_Q15: Int16
            var mS1: Int
            var mS2: Int

            init(_ samplingRate: UInt32, _ frequency: UInt16, _ volume: Float) {
                self.frequency = frequency
                let F_div_Fs = Double(frequency) / Double(samplingRate)
                var d0 = -Double(Float(WaveGenerator.GEN_AMP)) * sin(2 * Double.pi * F_div_Fs)
                mS2_0 = Int16(d0)
                mS1 = 0
                mS2 = Int(mS2_0)
                let amplitude = 32767.0 * 32767.0 * Double(volume) / Double(WaveGenerator.GEN_AMP)
                // (short) cast; take some margin for amplitude fluctuation
                mAmplitude_Q15 = amplitude > 32500 ? 32500 : Int16(amplitude)
                d0 = 32768.0 * cos(2 * Double.pi * F_div_Fs)   // Q14*2*cos()
                if d0 > 32767 { d0 = 32767 }
                mA1_Q14 = Int16(d0)
            }

            /// Adds `count` samples to `outBuffer`; WAVEGEN_START restarts at phase 0, WAVEGEN_STOP ramps the
            /// amplitude linearly down to 0 over the block.
            mutating func getSamples(_ outBuffer: UnsafeMutablePointer<Int16>, _ count: UInt32, _ command: Int) {
                var lS1: Int
                var lS2: Int
                if command == ToneRenderer.WAVEGEN_START {
                    lS1 = 0
                    lS2 = Int(mS2_0)
                } else {
                    lS1 = mS1
                    lS2 = mS2
                }
                let lA1 = Int(mA1_Q14)
                var lAmplitude = Int(mAmplitude_Q15)
                var out = outBuffer
                var count = count
                if command == ToneRenderer.WAVEGEN_STOP {
                    lAmplitude <<= 16
                    if count == 0 { return }
                    let dec = lAmplitude / Int(count)
                    while count != 0 {
                        count -= 1
                        var sample = ((lA1 * lS1) >> WaveGenerator.S_Q14) - lS2
                        lS2 = lS1
                        lS1 = sample
                        sample = ((lAmplitude >> 16) * sample) >> WaveGenerator.S_Q15
                        out.pointee = out.pointee &+ Int16(truncatingIfNeeded: sample)
                        out += 1
                        lAmplitude -= dec
                    }
                } else {
                    while count != 0 {
                        count -= 1
                        var sample = ((lA1 * lS1) >> WaveGenerator.S_Q14) - lS2
                        lS2 = lS1
                        lS1 = sample
                        sample = (lAmplitude * sample) >> WaveGenerator.S_Q15
                        out.pointee = out.pointee &+ Int16(truncatingIfNeeded: sample)
                        out += 1
                    }
                }
                mS1 = lS1
                mS2 = lS2
            }
        }

        let mSamplingRate: UInt32
        /// 20 ms: the sequencer's largest processing step.
        let mProcessSize: UInt32
        /// Emulated AudioTrack callback size: one 4 ms HAL period (AUDIO_OUTPUT_FLAG_FAST track).
        let callbackFrames: Int
        /// AudioTrack volume (linearToLog of the constructor volume).
        let gain: Float
        private let scale: Float

        private(set) var mState: ToneState = .TONE_INIT
        /// The AudioTrack is started (between startTone and the callback that stops it).
        private(set) var trackActive = false
        /// The owning ToneGenerator was released; the mixer drops this renderer once it is silent.
        var released = false

        private let desc: UnsafeMutablePointer<ToneSegment>
        private var descRepeatCnt: UInt = 0
        private var descRepeatSegment: UInt = 0
        private let newDesc: UnsafeMutablePointer<ToneSegment>
        private var newRepeatCnt: UInt = 0
        private var newRepeatSegment: UInt = 0
        private var hasNewDesc = false
        private var mDurationMs: Int32 = -1
        private var mTotalSmp: UInt32 = 0
        private var mMaxSmp: UInt32 = 0
        private var mNextSegSmp: UInt32 = 0
        private var mCurSegment = 0
        private var mCurCount = 0
        private var mLoopCounter: UInt16 = 0
        private var mStartTimeNs: UInt64 = 0
        private let waves: UnsafeMutablePointer<WaveGenerator>
        private var waveCount = 0
        private let block: UnsafeMutablePointer<Int16>
        private var blockLength = 0
        private var blockRead = 0

        init(_ samplingRate: UInt32, _ gain: Float) {
            mSamplingRate = samplingRate
            mProcessSize = (samplingRate * 20) / 1000
            callbackFrames = max(Int(samplingRate) * 4 / 1000, 1)
            self.gain = gain
            scale = gain / 32768
            let empty = ToneSegment(duration: 0, waveFreq0: 0, waveFreq1: 0, waveFreq2: 0, waveFreq3: 0, loopCnt: 0,
                                    loopIndx: 0)
            desc = .allocate(capacity: ToneRenderer.SEGMENT_SLOTS)
            desc.initialize(repeating: empty, count: ToneRenderer.SEGMENT_SLOTS)
            newDesc = .allocate(capacity: ToneRenderer.SEGMENT_SLOTS)
            newDesc.initialize(repeating: empty, count: ToneRenderer.SEGMENT_SLOTS)
            waves = .allocate(capacity: ToneRenderer.MAX_WAVE_GENERATORS)
            block = .allocate(capacity: callbackFrames)
            block.initialize(repeating: 0, count: callbackFrames)
        }

        deinit {
            desc.deallocate()
            newDesc.deallocate()
            waves.deallocate()
            block.deallocate()
        }

        private static func nowNs() -> UInt64 {
            return DispatchTime.now().uptimeNanoseconds
        }

        // MARK: Main thread (mixer lock held)

        /// ToneGenerator::startTone without the blocking waits: an idle generator starts at once, a playing or
        /// stopping one is marked TONE_RESTARTING and the audio thread fades it out and starts the new tone.
        func startTone(_ descriptor: ToneDescriptor, _ durationMs: Int32) -> Bool {
            if mState == .TONE_IDLE { mState = .TONE_INIT }   // initAudioTrack() never fails here
            let empty = ToneSegment(duration: 0, waveFreq0: 0, waveFreq1: 0, waveFreq2: 0, waveFreq3: 0, loopCnt: 0,
                                    loopIndx: 0)
            for s in 0..<ToneRenderer.SEGMENT_SLOTS {
                newDesc[s] = s < descriptor.segments.count && s < ToneRenderer.SEGMENT_SLOTS - 1
                    ? descriptor.segments[s] : empty
            }
            newRepeatCnt = descriptor.repeatCnt
            newRepeatSegment = descriptor.repeatSegment
            hasNewDesc = true
            mDurationMs = durationMs
            if mState == .TONE_STOPPED {
                // Android waits here until the callback has stopped the previous tone (STOPPED -> INIT).
                mState = .TONE_INIT
                trackActive = false
            }
            if mState == .TONE_INIT {
                if prepareWave() {
                    mState = .TONE_STARTING
                    mStartTimeNs = ToneRenderer.nowNs()
                    trackActive = true   // mpAudioTrack->start(): a fresh buffer
                    blockLength = 0
                    blockRead = 0
                    return true
                }
                mState = .TONE_IDLE
                return false
            }
            mState = .TONE_RESTARTING
            mStartTimeNs = 0
            return true
        }

        /// ToneGenerator::stopTone without the wait: the tone ends at the next callback buffer (but plays at least
        /// as long as the time since it started, as on Android after a cold output start).
        func stopTone() {
            guard mState != .TONE_IDLE && mState != .TONE_INIT else { return }
            if mState == .TONE_PLAYING || mState == .TONE_STARTING || mState == .TONE_RESTARTING {
                if mStartTimeNs != 0 {
                    let elapsed = ToneRenderer.nowNs() &- mStartTimeNs
                    let sec = Int64(elapsed / 1_000_000_000)
                    let nsec = Int64(elapsed % 1_000_000_000)
                    if sec + 1 > Int64(Int32.max) / Int64(mSamplingRate) {
                        mMaxSmp = UInt32(truncatingIfNeeded: sec * Int64(mSamplingRate))
                    } else {
                        let ms = sec * 1000 + nsec / 1_000_000
                        mMaxSmp = UInt32(truncatingIfNeeded: (ms * Int64(mSamplingRate)) / 1000)
                    }
                } else {
                    mState = .TONE_STOPPING
                }
            }
        }

        // MARK: Render thread (mixer lock held)

        /// Writes `count` samples (floats at the AudioTrack volume). false = the track is stopped (nothing written).
        func render(_ out: UnsafeMutablePointer<Float>, _ count: Int) -> Bool {
            if !trackActive { return false }
            var i = 0
            while i < count {
                if blockRead >= blockLength {
                    if !trackActive { break }
                    blockLength = onMoreData(block, callbackFrames)
                    blockRead = 0
                    if blockLength == 0 {
                        trackActive = false   // the callback stopped the AudioTrack
                        break
                    }
                }
                let take = min(count - i, blockLength - blockRead)
                var k = 0
                while k < take {
                    out[i + k] = Float(block[blockRead + k]) * scale
                    k += 1
                }
                i += take
                blockRead += take
            }
            while i < count {
                out[i] = 0
                i += 1
            }
            return true
        }

        /// ToneGenerator::onMoreData for one AudioTrack buffer of `frames` samples; returns the frames delivered
        /// (0 = the track stops).
        private func onMoreData(_ buffer: UnsafeMutablePointer<Int16>, _ frames: Int) -> Int {
            if frames == 0 { return 0 }
            var lpOut = buffer
            var lNumSmp = UInt32(frames)
            var delivered = frames
            buffer.update(repeating: 0, count: frames)   // WaveGenerator accumulates into the buffer

            while lNumSmp != 0 {
                let lReqSmp: UInt32 = lNumSmp < mProcessSize &* 2 ? lNumSmp : mProcessSize
                var lGenSmp: UInt32 = 0
                var lWaveCmd = ToneRenderer.WAVEGEN_CONT
                var endLoop = false

                // Update pcm frame count and end time (current time at the end of this process)
                mTotalSmp = mTotalSmp &+ lReqSmp

                // Update tone gen state machine and select wave gen command
                switch mState {
                case .TONE_PLAYING:
                    lWaveCmd = ToneRenderer.WAVEGEN_CONT
                case .TONE_STARTING:
                    lWaveCmd = ToneRenderer.WAVEGEN_START
                case .TONE_STOPPING, .TONE_RESTARTING:
                    lWaveCmd = ToneRenderer.WAVEGEN_STOP
                    mNextSegSmp = ToneRenderer.TONEGEN_INF   // forced to skip state machine management below
                default:
                    endLoop = true   // TONE_STOPPED (and extra callbacks): goto audioCallback_EndLoop
                }

                // Exit if tone sequence is over
                if !endLoop && (desc[mCurSegment].duration == 0 || mTotalSmp > mMaxSmp) {
                    if mState == .TONE_PLAYING { mState = .TONE_STOPPING }
                    if desc[mCurSegment].duration == 0 {
                        endLoop = true
                    } else {
                        // fade out before stopping if maximum duration reached
                        lWaveCmd = ToneRenderer.WAVEGEN_STOP
                        mNextSegSmp = ToneRenderer.TONEGEN_INF
                    }
                }

                if !endLoop {
                    if mTotalSmp > mNextSegSmp {
                        // Time to go to next sequence segment
                        lGenSmp = lReqSmp
                        // If segment, ON -> OFF transition : ramp volume down
                        if desc[mCurSegment].waveFreq(0) != 0 {
                            lWaveCmd = ToneRenderer.WAVEGEN_STOP
                            generate(mCurSegment, lpOut, lGenSmp, lWaveCmd)
                        }
                        // check if we need to loop and loop for the reqd times
                        if desc[mCurSegment].loopCnt != 0 {
                            if mLoopCounter < desc[mCurSegment].loopCnt {
                                mCurSegment = Int(desc[mCurSegment].loopIndx)
                                mLoopCounter &+= 1
                            } else {
                                // completed loop. go to next segment
                                mLoopCounter = 0
                                mCurSegment += 1
                            }
                        } else {
                            mCurSegment += 1
                        }
                        // Handle loop if last segment reached
                        if desc[mCurSegment].duration == 0 {
                            // Pre increment loop count and restart if total count not reached. Stop sequence otherwise
                            mCurCount += 1
                            if UInt(mCurCount) <= descRepeatCnt {
                                mCurSegment = Int(descRepeatSegment)
                                if desc[Int(descRepeatSegment)].waveFreq(0) != 0 {
                                    lWaveCmd = ToneRenderer.WAVEGEN_START
                                }
                            } else {
                                lGenSmp = 0
                            }
                        } else if desc[mCurSegment].waveFreq(0) != 0 {
                            // If next segment is not silent, OFF -> ON transition : reset wave generator
                            lWaveCmd = ToneRenderer.WAVEGEN_START
                        } else {
                            lGenSmp = 0
                        }
                        // Update next segment transition position.
                        mNextSegSmp = mNextSegSmp &+ (desc[mCurSegment].duration &* mSamplingRate) / 1000
                    } else {
                        // Inside a segment keep tone ON or OFF
                        lGenSmp = desc[mCurSegment].waveFreq(0) == 0 ? 0 : lReqSmp
                    }

                    if lGenSmp != 0 {
                        // If samples must be generated, call all active wave generators
                        generate(mCurSegment, lpOut, lGenSmp, lWaveCmd)
                    }

                    lNumSmp -= lReqSmp
                    lpOut += Int(lReqSmp)
                }

                // audioCallback_EndLoop:
                switch mState {
                case .TONE_RESTARTING:
                    if prepareWave() {
                        mState = .TONE_STARTING
                        mStartTimeNs = ToneRenderer.nowNs()
                    } else {
                        mState = .TONE_IDLE
                        trackActive = false   // mpAudioTrack->stop()
                        lNumSmp = 0
                    }
                case .TONE_STOPPING:
                    mState = .TONE_STOPPED
                    lNumSmp = 0   // Force loop exit
                case .TONE_STOPPED:
                    mState = .TONE_INIT
                    lNumSmp = 0   // mpAudioTrack->stop()
                    delivered = 0
                case .TONE_STARTING:
                    mState = .TONE_PLAYING
                case .TONE_PLAYING:
                    break
                default:
                    lNumSmp = 0
                    delivered = 0
                }
            }
            return delivered
        }

        private func waveIndex(_ frequency: UInt16) -> Int? {
            var i = 0
            while i < waveCount {
                if waves[i].frequency == frequency { return i }
                i += 1
            }
            return nil
        }

        /// Runs every wave generator of `segment` over `count` samples (mWaveGens.valueFor(frequency)).
        private func generate(_ segment: Int, _ out: UnsafeMutablePointer<Int16>, _ count: UInt32, _ command: Int) {
            var lFreqIdx = 0
            var lFrequency = desc[segment].waveFreq(lFreqIdx)
            while lFrequency != 0 {
                if let w = waveIndex(lFrequency) { waves[w].getSamples(out, count, command) }
                lFreqIdx += 1
                lFrequency = desc[segment].waveFreq(lFreqIdx)
            }
        }

        /// ToneGenerator::numWaves — note the extra `lCnt++`: one more than the segment's frequencies.
        private func numWaves(_ segmentIdx: Int) -> UInt32 {
            var lCnt: UInt32 = 0
            if desc[segmentIdx].duration != 0 {
                while desc[segmentIdx].waveFreq(Int(lCnt)) != 0 { lCnt += 1 }
                lCnt += 1
            }
            return lCnt
        }

        /// ToneGenerator::prepareWave: takes the new descriptor, applies the duration limit, creates one wave
        /// generator per frequency and resets the sequencer.
        private func prepareWave() -> Bool {
            if !hasNewDesc { return false }
            // Remove existing wave generators if any
            waveCount = 0
            for s in 0..<ToneRenderer.SEGMENT_SLOTS { desc[s] = newDesc[s] }
            descRepeatCnt = newRepeatCnt
            descRepeatSegment = newRepeatSegment

            if mDurationMs == -1 {
                mMaxSmp = ToneRenderer.TONEGEN_INF
            } else if mDurationMs > Int32(truncatingIfNeeded: ToneRenderer.TONEGEN_INF / mSamplingRate) {
                mMaxSmp = UInt32(truncatingIfNeeded: mDurationMs / 1000) &* mSamplingRate
            } else {
                mMaxSmp = (UInt32(truncatingIfNeeded: mDurationMs) &* mSamplingRate) / 1000
            }

            var segmentIdx = 0
            while segmentIdx < ToneRenderer.SEGMENT_SLOTS && desc[segmentIdx].duration != 0 {
                // Get total number of sine waves: needed to adapt sine wave gain.
                let lNumWaves = numWaves(segmentIdx)
                var freqIdx = 0
                var frequency = desc[segmentIdx].waveFreq(freqIdx)
                while frequency != 0 {
                    // Instantiate a wave generator if not already done for this frequency
                    if waveIndex(frequency) == nil && waveCount < ToneRenderer.MAX_WAVE_GENERATORS {
                        (waves + waveCount).initialize(
                            to: WaveGenerator(mSamplingRate, frequency, ToneRenderer.TONEGEN_GAIN / Float(lNumWaves)))
                        waveCount += 1
                    }
                    freqIdx += 1
                    frequency = desc[segmentIdx].waveFreq(freqIdx)
                }
                segmentIdx += 1
            }

            // Initialize tone sequencer
            mTotalSmp = 0
            mCurSegment = 0
            mCurCount = 0
            mLoopCounter = 0
            if desc[0].duration == ToneRenderer.TONEGEN_INF {
                mNextSegSmp = ToneRenderer.TONEGEN_INF
            } else {
                mNextSegSmp = (desc[0].duration &* mSamplingRate) / 1000
            }
            return true
        }
    }
}
