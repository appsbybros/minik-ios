import AVFoundation
import Foundation

// AndroidKit audio, part 2 (DESIGN 4.6): android.media.MediaPlayer and AudioManager audio focus, the subset
// BasketballSoundscape (Android 6c38131) uses: MediaPlayer.create(context, R.raw.x), start/pause/isPlaying/
// setVolume/isLooping/duration/release, OnCompletionListener, OnErrorListener; AudioFocusRequest.Builder,
// requestAudioFocus/abandonAudioFocusRequest and the OnAudioFocusChangeListener.
//
// * create() opens the file synchronously (MediaPlayer.create prepares synchronously: an unreadable resource gives
//   null) and decodes the whole file once on AAudio.decodeQueue, off the main thread: Android's prepare only parses
//   the header and the codec streams while playing, whereas a full ALAC decode + resample of the 20-35 s music and
//   crowd files takes long enough on the main thread to drop court frames (the crowd file changes mid-match on every
//   completion). A start() before the decode finished is Started at once and becomes audible when the samples are
//   ready (the soundscape fades music in from volume 0 anyway). The player is one voice of the shared AAudio.Mixer,
//   like the SoundPool streams; pause keeps the position, start resumes there, start after completion plays from the
//   beginning (MediaPlayer's PlaybackCompleted state). The completion listener runs on the
//   main thread, as Android posts it to the creating looper; it never fires while isLooping is true.
// * Audio focus: iOS has none. The app's `.ambient` session mixes with other audio, so a request is always granted.
//   An AVAudioSession interruption (a call, Siri, an alarm) is the closest Android focus change: it reports
//   AUDIOFOCUS_LOSS_TRANSIENT to the holder of the last granted request, and its end reports AUDIOFOCUS_GAIN.

/// android.media.MediaPlayer (the states the app reaches: Prepared, Started, Paused, PlaybackCompleted, End).
final class AMediaPlayer {
    typealias OnCompletionListener = (_ mp: AMediaPlayer) -> Void
    typealias OnErrorListener = (_ mp: AMediaPlayer, _ what: Int, _ extra: Int) -> Bool

    static let TAG = "MediaPlayer"
    /// How often a started player looks for the end of its voice (MediaPlayer's completion is an event; the mixer's
    /// voices finish on the render thread).
    private static let COMPLETION_POLL_MS: Int64 = 20

    /// nil while the background decode runs (or after it failed).
    private var data: AAudio.PCMData?
    private var decodeFailed = false
    /// MediaPlayer.getDuration(), known from the header at create().
    private let durationMs: Int
    private let mixer: AAudio.Mixer
    private var voiceID = 0
    private var started = false
    private var released = false
    private var leftVolume: Float = 1
    private var rightVolume: Float = 1
    private var looping = false
    private var completionListener: OnCompletionListener?
    private var errorListener: OnErrorListener?
    private let handler = AHandler()
    private lazy var completionWatch = ARunnable { [weak self] in self?.checkCompletion() }

    private init(data: AAudio.PCMData?, durationMs: Int, mixer: AAudio.Mixer) {
        self.data = data
        self.durationMs = durationMs
        self.mixer = mixer
        mixer.prepareSession()
    }

    deinit {
        if voiceID != 0 { mixer.stop(voiceID) }
    }

    /// MediaPlayer.create(context, resid): a prepared player, or nil when the resource cannot be opened.
    static func create(_ context: AContext?, _ resid: ARawRes, mixer: AAudio.Mixer = AAudio.Mixer.shared) -> AMediaPlayer? {
        guard let url = AResources.rawURL(resid) else {
            ALog.e(TAG, "create: raw resource \(resid) not found")
            return nil
        }
        // The prepare step: header only (cheap); the samples are decoded in the background.
        guard let file = try? AVAudioFile(forReading: url), file.length > 0,
              file.processingFormat.sampleRate > 0, file.processingFormat.channelCount > 0 else {
            ALog.e(TAG, "create failed for \(resid)")
            return nil
        }
        let durationMs = Int(Double(file.length) * 1000 / file.processingFormat.sampleRate)
        let player = AMediaPlayer(data: nil, durationMs: durationMs, mixer: mixer)
        AAudio.decodeQueue.async { [weak player] in
            // The player is only touched on the main thread (no strong reference is taken here).
            let data = AAudio.decode(url)
            DispatchQueue.main.async { [weak player] in
                player?.decodeFinished(data)
            }
        }
        return player
    }

    /// A player of already decoded samples (tests).
    static func create(decoded data: AAudio.PCMData, mixer: AAudio.Mixer) -> AMediaPlayer {
        let durationMs = data.frameRate > 0 ? Int(Double(data.frameCount) * 1000 / data.frameRate) : 0
        return AMediaPlayer(data: data, durationMs: durationMs, mixer: mixer)
    }

    /// MediaPlayer.getDuration() in milliseconds.
    var duration: Int { durationMs }

    func getDuration() -> Int { duration }

    /// MediaPlayer.isPlaying(): true from start() until pause(), release() or the end of a non-looping playback.
    var isPlaying: Bool {
        if !started || released { return false }
        if voiceID == 0 { return data == nil && !decodeFailed }   // Started, samples still decoding
        return mixer.isActive(voiceID)
    }

    /// MediaPlayer.isLooping / setLooping (applies to the running playback too).
    var isLooping: Bool {
        get { looping }
        set {
            looping = newValue
            if voiceID != 0 { mixer.setLoop(voiceID, newValue ? -1 : 0) }
        }
    }

    func setLooping(_ looping: Bool) { isLooping = looping }

    /// MediaPlayer.setVolume(left, right): linear gains 0...1.
    func setVolume(_ leftVolume: Float, _ rightVolume: Float) {
        if released { return }
        self.leftVolume = leftVolume.coerceIn(0, 1)
        self.rightVolume = rightVolume.coerceIn(0, 1)
        if voiceID != 0 { mixer.setGains(voiceID, self.leftVolume, self.rightVolume) }
    }

    func setOnCompletionListener(_ listener: OnCompletionListener?) { completionListener = listener }

    func setOnErrorListener(_ listener: OnErrorListener?) { errorListener = listener }

    /// MediaPlayer.start(): resumes a paused playback, else starts from the beginning.
    func start() {
        if released {
            ALog.e(AMediaPlayer.TAG, "start called in state End")
            return
        }
        if started && isPlaying { return }
        if voiceID != 0 && mixer.isActive(voiceID) {
            mixer.resume(voiceID)
        } else if data != nil {
            if !addVoice() {
                reportError()
                return
            }
        } else if decodeFailed {
            reportError()
            return
        } else {
            voiceID = 0                                  // decodeFinished adds the voice
        }
        started = true
        if voiceID != 0 { mixer.ensureRunning() }
        handler.removeCallbacks(completionWatch)
        handler.postDelayed(completionWatch, AMediaPlayer.COMPLETION_POLL_MS)
    }

    /// A new voice from the beginning; false when the mixer has no free voice.
    private func addVoice() -> Bool {
        guard let data = data else { return false }
        voiceID = mixer.addPCM(data, leftVolume, rightVolume, looping ? -1 : 0,
                               ASoundPool.step(data.sourceSampleRate, data.frameRate, 1))
        return voiceID != 0
    }

    /// MediaPlayer's error (MEDIA_ERROR_UNKNOWN): the error listener, then completion unless it handled the error.
    private func reportError() {
        started = false
        handler.removeCallbacks(completionWatch)
        let handled = errorListener?(self, 1, 0) ?? false
        if !handled { completionListener?(self) }
    }

    /// Main thread: the background decode of create() ended.
    private func decodeFinished(_ decoded: AAudio.PCMData?) {
        if released { return }
        guard let decoded = decoded else {
            ALog.e(AMediaPlayer.TAG, "decoding failed")
            decodeFailed = true
            if started { reportError() }
            return
        }
        data = decoded
        if started && voiceID == 0 {
            if addVoice() {
                mixer.ensureRunning()
            } else {
                reportError()
            }
        }
    }

    /// MediaPlayer.pause(): keeps the position.
    func pause() {
        if released || !started { return }
        started = false
        handler.removeCallbacks(completionWatch)
        if voiceID != 0 { mixer.pause(voiceID) }
    }

    /// MediaPlayer.stop(): a later start() would need prepare() on Android; here it plays from the beginning.
    func stop() {
        if released { return }
        started = false
        handler.removeCallbacks(completionWatch)
        if voiceID != 0 { mixer.stop(voiceID); voiceID = 0 }
    }

    /// MediaPlayer.release(): stops the sound; no listener runs afterwards.
    func release() {
        if released { return }
        stop()
        released = true
        completionListener = nil
        errorListener = nil
    }

    private func checkCompletion() {
        if released || !started { return }
        if (voiceID != 0 && mixer.isActive(voiceID)) || (voiceID == 0 && data == nil && !decodeFailed) {
            handler.postDelayed(completionWatch, AMediaPlayer.COMPLETION_POLL_MS)
            return
        }
        started = false
        voiceID = 0
        completionListener?(self)
    }
}

// MARK: - Audio focus

extension AAudioManager {
    static let AUDIOFOCUS_NONE = 0
    static let AUDIOFOCUS_GAIN = 1
    static let AUDIOFOCUS_GAIN_TRANSIENT = 2
    static let AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK = 3
    static let AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE = 4
    static let AUDIOFOCUS_LOSS = -1
    static let AUDIOFOCUS_LOSS_TRANSIENT = -2
    static let AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK = -3
    static let AUDIOFOCUS_REQUEST_FAILED = 0
    static let AUDIOFOCUS_REQUEST_GRANTED = 1
    static let AUDIOFOCUS_REQUEST_DELAYED = 2

    /// AudioManager.OnAudioFocusChangeListener.
    typealias OnAudioFocusChangeListener = (_ focusChange: Int) -> Void

    /// `context.getSystemService(Context.AUDIO_SERVICE) as AudioManager`.
    static let shared = AAudioManager()

    /// AudioManager.requestAudioFocus(AudioFocusRequest): always granted (see the file comment).
    func requestAudioFocus(_ request: AAudioFocusRequest) -> Int {
        AAudioFocus.shared.request(request)
        return AAudioManager.AUDIOFOCUS_REQUEST_GRANTED
    }

    /// AudioManager.abandonAudioFocusRequest(AudioFocusRequest).
    @discardableResult
    func abandonAudioFocusRequest(_ request: AAudioFocusRequest) -> Int {
        AAudioFocus.shared.abandon(request)
        return AAudioManager.AUDIOFOCUS_REQUEST_GRANTED
    }
}

/// android.media.AudioFocusRequest (built with AudioFocusRequest.Builder(focusGain)).
final class AAudioFocusRequest {
    let focusGain: Int
    let audioAttributes: AAudioAttributes
    let onAudioFocusChangeListener: AAudioManager.OnAudioFocusChangeListener?

    private init(focusGain: Int, audioAttributes: AAudioAttributes,
                 listener: AAudioManager.OnAudioFocusChangeListener?) {
        self.focusGain = focusGain
        self.audioAttributes = audioAttributes
        self.onAudioFocusChangeListener = listener
    }

    final class Builder {
        private let focusGain: Int
        private var attributes = AAudioAttributes.Builder().setUsage(AAudioAttributes.USAGE_MEDIA).build()
        private var listener: AAudioManager.OnAudioFocusChangeListener?

        init(_ focusGain: Int) { self.focusGain = focusGain }

        @discardableResult
        func setAudioAttributes(_ attributes: AAudioAttributes) -> Builder {
            self.attributes = attributes
            return self
        }

        @discardableResult
        func setOnAudioFocusChangeListener(_ listener: @escaping AAudioManager.OnAudioFocusChangeListener) -> Builder {
            self.listener = listener
            return self
        }

        func build() -> AAudioFocusRequest {
            AAudioFocusRequest(focusGain: focusGain, audioAttributes: attributes, listener: listener)
        }
    }
}

/// The focus stack of the app: only the last granted request hears focus changes (Android's focus owner).
private final class AAudioFocus {
    static let shared = AAudioFocus()

    private var holder: AAudioFocusRequest?
    private var observer: NSObjectProtocol?
    private var interrupted = false

    func request(_ request: AAudioFocusRequest) {
        holder = request
        if observer == nil {
            observer = NotificationCenter.default.addObserver(
                forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
                self?.interruption(note)
            }
        }
    }

    func abandon(_ request: AAudioFocusRequest) {
        if holder === request { holder = nil }
    }

    private func interruption(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            interrupted = true
            holder?.onAudioFocusChangeListener?(AAudioManager.AUDIOFOCUS_LOSS_TRANSIENT)
        case .ended:
            if !interrupted { return }
            interrupted = false
            holder?.onAudioFocusChangeListener?(AAudioManager.AUDIOFOCUS_GAIN)
        @unknown default:
            break
        }
    }
}

// MARK: - Context.getSystemService

/// Context's service names (the ones the app asks for).
enum AContextService {
    static let AUDIO_SERVICE = "audio"
    static let SENSOR_SERVICE = "sensor"
}

extension AContext {
    /// Context.getSystemService(name) for the services the app uses (nil for any other, like an unknown name).
    func getSystemService(_ name: String) -> AnyObject? {
        switch name {
        case AContextService.AUDIO_SERVICE: return AAudioManager.shared
        case AContextService.SENSOR_SERVICE: return ASensorManager.shared
        default: return nil
        }
    }
}
