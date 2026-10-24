import XCTest
@testable import MinikTripleShot

/// Audio parity tests.
/// * BasketballAudio (view/BasketballAudio.kt, spec 07 §4.10): which foley plays for consecutive world snapshots —
///   catch 0.55 on every owner change while a ball exists (pick-up, release, first held frame), bounce 0.5 when the
///   dribble phase crosses 0.5 upward (> 300 ms apart), swish 0.65 for |netSway| > 0.005 (> 900 ms apart), all gated by
///   the "sound" preference and by the load-complete listener. The SoundPool is a recording fake.
/// * AndroidKit SoundPool / ToneGenerator (AAudio.swift) rendered offline with an engine-less mixer: stereo gains,
///   loops, stream stealing, pause/autoPause, Android's argument checks, and the AOSP fixed-point TONE_PROP_ACK
///   (expected samples computed from the AOSP WaveGenerator integer arithmetic).
final class AudioTests: XCTestCase {

    // MARK: - Fakes and fixtures

    /// SoundPool stand-in: records loads and plays; the test delivers the load-complete callbacks.
    private final class FakeSoundPool: ASoundPool {
        struct Play: Equatable {
            let soundID: Int
            let left: Float
            let right: Float
            let priority: Int
            let loop: Int
            let rate: Float
        }

        private(set) var loads: [ARawRes] = []
        private(set) var plays: [Play] = []
        private(set) var releases = 0
        private var listener: OnLoadCompleteListener?

        init() {
            super.init(maxStreams: 3, attributes: AAudioAttributes.Builder().build(),
                       mixer: AAudio.Mixer(engineEnabled: false))
        }

        override func setOnLoadCompleteListener(_ listener: OnLoadCompleteListener?) {
            self.listener = listener
        }

        override func load(_ resId: ARawRes, _ priority: Int) -> Int {
            loads.append(resId)
            return loads.count
        }

        override func play(_ soundID: Int, _ leftVolume: Float, _ rightVolume: Float, _ priority: Int, _ loop: Int,
                           _ rate: Float) -> Int {
            plays.append(Play(soundID: soundID, left: leftVolume, right: rightVolume, priority: priority, loop: loop,
                              rate: rate))
            return plays.count
        }

        override func release() {
            releases += 1
        }

        func complete(_ soundID: Int, _ status: Int = 0) {
            listener?(self, soundID, status)
        }
    }

    private final class Clock {
        var now: Int64 = 1_000_000
    }

    /// Sound ids in BasketballAudio's load order.
    private static let BOUNCE = 1
    private static let CATCH = 2
    private static let SWISH = 3

    private var prefs: ASharedPreferences!
    private var pool: FakeSoundPool!
    private var clock: Clock!
    private var audio: BasketballAudio!

    override func setUp() {
        super.setUp()
        prefs = getSharedPreferences("basketball_journey_audio_tests", MODE_PRIVATE)
        prefs.edit().clear().commit()
        pool = FakeSoundPool()
        let clock = Clock()
        self.clock = clock
        audio = BasketballAudio(prefs: prefs, pool: pool, uptimeMillis: { clock.now })
    }

    override func tearDown() {
        prefs.edit().clear().commit()
        audio = nil
        pool = nil
        clock = nil
        prefs = nil
        super.tearDown()
    }

    private func loadAll() {
        pool.complete(AudioTests.BOUNCE)
        pool.complete(AudioTests.CATCH)
        pool.complete(AudioTests.SWISH)
    }

    private func actor(_ id: String, _ motion: TripleShotPlayerRenderer.Motion = .IDLE,
                       _ phase: Float = 0) -> TripleShotWorldActor {
        let state = TripleShotPlayerRenderer.State(x: 0, footY: 0, fineAim: 0, pullBack: 0, dribbleBouncePx: 0,
                                                   hotHand: false, motion: motion, dribblePhase01: phase)
        return TripleShotWorldActor(id: id, position: CourtPoint(x: 0, y: 0, z: 0), state: state)
    }

    private func ball(_ owner: String?) -> TripleShotWorldBall {
        return TripleShotWorldBall(position: CourtPoint(x: 0, y: 1.25, z: 0), resource: R.drawable.basketball,
                                   owner: owner)
    }

    private func scene(_ balls: [TripleShotWorldBall], _ actors: [TripleShotWorldActor] = [],
                       netSway: Float = 0) -> TripleShotWorldSnapshot {
        return TripleShotWorldSnapshot(timeNanos: 0, courtId: "sunset_pulse", teamSize: 1, actors: actors, balls: balls,
                                       hoops: [], atmosphere: .NONE, netSway: netSway)
    }

    /// One frame in which `id` holds the only ball.
    private func held(_ id: String, _ motion: TripleShotPlayerRenderer.Motion = .IDLE, _ phase: Float = 0) {
        audio.frame(scene([ball(id)], [actor(id, motion, phase)]))
    }

    private var played: [Int] {
        return pool.plays.map { $0.soundID }
    }

    // MARK: - BasketballAudio

    func testLoadsTheThreeFoleySoundsInKotlinOrder() {
        XCTAssertEqual(pool.loads, [R.raw.basket_bounce, R.raw.basket_catch, R.raw.basket_swish])
        XCTAssertTrue(pool.plays.isEmpty)
    }

    func testNothingPlaysBeforeItsLoadCompleted() {
        held("a")                                    // catch not loaded yet: silent, the owner is still tracked
        audio.frame(scene([], netSway: 0.02))        // swish not loaded: silent
        XCTAssertTrue(pool.plays.isEmpty)
        pool.complete(AudioTests.CATCH)
        held("b")
        XCTAssertEqual(played, [AudioTests.CATCH])
    }

    func testCatchPlaysOnPickUpOnReleaseAndOnTheFirstHeldFrame() {
        loadAll()
        held("a")                                            // the first presented frame with a held ball
        held("a")                                            // same owner: silent
        audio.frame(scene([ball(nil)], [actor("a")]))        // released, the ball is still in the scene: catch
        audio.frame(scene([], [actor("a")]))                 // the ball disappears: silent
        held("b")
        XCTAssertEqual(played, [AudioTests.CATCH, AudioTests.CATCH, AudioTests.CATCH])
        XCTAssertEqual(pool.plays.first,
                       FakeSoundPool.Play(soundID: AudioTests.CATCH, left: 0.55, right: 0.55, priority: 1, loop: 0,
                                          rate: 1))
    }

    func testBounceWhenTheDribblePhaseCrossesHalfUpwardMoreThan300msApart() {
        loadAll()
        held("a", .DRIBBLE, 0.2)       // catch; the reset phase 0 -> 0.2 does not cross
        held("a", .DRIBBLE, 0.6)       // crosses: bounce
        held("a", .DRIBBLE, 0.9)
        held("a", .DRIBBLE, 0.1)
        clock.now += 300
        held("a", .DRIBBLE, 0.7)       // crosses exactly 300 ms later: silent (needs more than 300)
        held("a", .DRIBBLE, 0.2)
        clock.now += 1
        held("a", .DRIBBLE, 0.5)       // 0.5 counts as crossed, 301 ms: bounce
        XCTAssertEqual(played, [AudioTests.CATCH, AudioTests.BOUNCE, AudioTests.BOUNCE])
        XCTAssertEqual(pool.plays[1],
                       FakeSoundPool.Play(soundID: AudioTests.BOUNCE, left: 0.5, right: 0.5, priority: 1, loop: 0,
                                          rate: 1))
    }

    func testAnOwnerChangeResetsThePhaseSoCatchAndBounceShareAFrame() {
        loadAll()
        held("a", .DRIBBLE, 0.8)       // catch, then 0 -> 0.8 crosses: bounce in the same frame
        clock.now += 1000
        held("b", .DRIBBLE, 0.6)       // new owner: catch, phase reset to 0 -> 0.6: bounce again
        XCTAssertEqual(played, [AudioTests.CATCH, AudioTests.BOUNCE, AudioTests.CATCH, AudioTests.BOUNCE])
    }

    func testFramesWithoutDribbleKeepThePreviousPhase() {
        loadAll()
        held("a", .DRIBBLE, 0.3)
        held("a", .IDLE, 0.9)          // not dribbling: previousPhase stays 0.3
        held("a", .DRIBBLE, 0.6)       // 0.3 -> 0.6: bounce
        XCTAssertEqual(played, [AudioTests.CATCH, AudioTests.BOUNCE])
    }

    func testOnlyTheFirstBallAndTheFirstActorWithItsOwnerCount() {
        loadAll()
        let balls = [ball("a"), ball("b")]
        audio.frame(scene(balls, [actor("a"), actor("b", .DRIBBLE, 0.2)]))
        audio.frame(scene(balls, [actor("a"), actor("b", .DRIBBLE, 0.7)]))    // b dribbles the second ball: silent
        audio.frame(scene([ball("a")], [actor("a", .DRIBBLE, 0.2), actor("a", .DRIBBLE, 0.1)]))
        audio.frame(scene([ball("a")], [actor("a", .DRIBBLE, 0.7), actor("a", .DRIBBLE, 0.1)]))   // first "a" crosses
        XCTAssertEqual(played, [AudioTests.CATCH, AudioTests.BOUNCE])
    }

    func testSwishNeedsNetSwayAboveTheThresholdMoreThan900msApart() {
        loadAll()
        audio.frame(scene([], netSway: 0.005))       // not above 0.005
        audio.frame(scene([], netSway: 0.0051))      // swish
        clock.now += 900
        audio.frame(scene([], netSway: -0.02))       // |sway| counts, but only 900 ms later
        clock.now += 1
        audio.frame(scene([], netSway: -0.02))       // swish
        XCTAssertEqual(played, [AudioTests.SWISH, AudioTests.SWISH])
        XCTAssertEqual(pool.plays[0],
                       FakeSoundPool.Play(soundID: AudioTests.SWISH, left: 0.65, right: 0.65, priority: 1, loop: 0,
                                          rate: 1))
    }

    func testTheSoundPreferenceMutesEveryPlayButTheDebounceStillAdvances() {
        loadAll()
        prefs.edit().putBoolean("sound", false).commit()
        held("a", .DRIBBLE, 0.8)                                                      // muted catch and bounce
        audio.frame(scene([ball("a")], [actor("a", .DRIBBLE, 0.8)], netSway: 0.02))   // muted swish
        XCTAssertTrue(pool.plays.isEmpty)
        prefs.edit().putBoolean("sound", true).commit()
        clock.now += 500
        audio.frame(scene([ball("a")], [actor("a", .DRIBBLE, 0.1)], netSway: 0.02))   // 500 ms after the muted swish
        audio.frame(scene([ball("a")], [actor("a", .DRIBBLE, 0.6)]))                  // 500 ms after the muted bounce
        clock.now += 401
        audio.frame(scene([ball("a")], [actor("a", .DRIBBLE, 0.6)], netSway: 0.02))   // 901 ms: swish
        XCTAssertEqual(played, [AudioTests.BOUNCE, AudioTests.SWISH])
    }

    func testAFailedLoadIsNeverPlayed() {
        pool.complete(AudioTests.BOUNCE)
        pool.complete(AudioTests.CATCH, -1)
        pool.complete(AudioTests.SWISH)
        held("a")
        audio.frame(scene([ball("a")], [actor("a")], netSway: 0.02))
        XCTAssertEqual(played, [AudioTests.SWISH])
    }

    func testCloseReleasesThePool() {
        audio.close()
        XCTAssertEqual(pool.releases, 1)
    }

    // MARK: - SoundPool on the offline mixer

    private func makePool(_ maxStreams: Int) -> (ASoundPool, AAudio.Mixer) {
        let mixer = AAudio.Mixer(engineEnabled: false)
        return (ASoundPool(maxStreams: maxStreams, attributes: AAudioAttributes.Builder().build(), mixer: mixer), mixer)
    }

    private func constant(_ value: Float, frames: Int) -> AAudio.PCMData {
        return AAudio.PCMData(channel0: [Float](repeating: value, count: frames), channel1: nil,
                              sourceSampleRate: AAudio.SAMPLE_RATE, frameRate: AAudio.SAMPLE_RATE)
    }

    func testSoundPoolMixesLeftAndRightVolumesLoopsAndFreesFinishedStreams() {
        let (pool, mixer) = makePool(1)
        let sound = pool.loadDecoded(constant(1, frames: 4))
        XCTAssertEqual(pool.play(sound, 0.5, 0.25, 1, 0, 1), 1)
        let once = mixer.render(frames: 6)
        XCTAssertEqual(once.left, [0.5, 0.5, 0.5, 0.5, 0, 0])
        XCTAssertEqual(once.right, [0.25, 0.25, 0.25, 0.25, 0, 0])
        XCTAssertEqual(pool.activeStreamIDs, [])                 // the stream ended: available again
        XCTAssertEqual(pool.play(sound, 1, 1, 0, 1, 1), 2)       // loop 1 = played twice
        XCTAssertEqual(mixer.render(frames: 9).left, [1, 1, 1, 1, 1, 1, 1, 1, 0])
        XCTAssertEqual(pool.play(99, 1, 1, 1, 0, 1), 0)          // unknown sound id
    }

    func testSoundPoolStealsTheOldestStreamWithTheLowestPriority() {
        let (pool, _) = makePool(2)
        let sound = pool.loadDecoded(constant(0.1, frames: 48000))
        XCTAssertEqual(pool.play(sound, 1, 1, 1, 0, 1), 1)
        XCTAssertEqual(pool.play(sound, 1, 1, 0, 0, 1), 2)
        XCTAssertEqual(pool.play(sound, 1, 1, 1, 0, 1), 3)       // full: stream 2 (priority 0) is stolen
        XCTAssertEqual(pool.activeStreamIDs, [1, 3])
        XCTAssertEqual(pool.play(sound, 1, 1, 0, 0, 1), 0)       // every active stream has a higher priority
        XCTAssertEqual(pool.play(sound, 1, 1, 1, 0, 1), 4)       // equal priorities: the oldest (1) goes
        XCTAssertEqual(pool.activeStreamIDs, [3, 4])
        pool.stop(3)
        XCTAssertEqual(pool.activeStreamIDs, [4])
        pool.release()
        XCTAssertEqual(pool.play(sound, 1, 1, 1, 0, 1), 0)
    }

    func testSoundPoolPauseResumeAndAutoPause() {
        let (pool, mixer) = makePool(2)
        let sound = pool.loadDecoded(constant(1, frames: 48000))
        let a = pool.play(sound, 1, 1, 1, 0, 1)
        let b = pool.play(sound, 1, 1, 1, 0, 1)
        pool.pause(a)
        var out = mixer.render(frames: 480)
        XCTAssertEqual(out.left[0], 2 - 1 / Float(AAudio.Mixer.RAMP_FRAMES), accuracy: 1e-5)   // a starts fading out
        XCTAssertEqual(out.left[479], 1)
        pool.autoPause()                                         // pauses b; a was paused by hand
        out = mixer.render(frames: 480)
        XCTAssertEqual(out.left[479], 0)
        pool.autoResume()                                        // resumes b only
        out = mixer.render(frames: 480)
        XCTAssertEqual(out.left[479], 1)
        pool.resume(a)
        out = mixer.render(frames: 480)
        XCTAssertEqual(out.left[479], 2)
        XCTAssertEqual(pool.activeStreamIDs, [a, b])
    }

    func testSoundPoolStealRule() {
        XCTAssertEqual(ASoundPool.streamToSteal([1, 1, 1], 1), 0)
        XCTAssertEqual(ASoundPool.streamToSteal([2, 1, 1], 1), 1)
        XCTAssertEqual(ASoundPool.streamToSteal([0, 1, 0], 1), 0)
        XCTAssertNil(ASoundPool.streamToSteal([2, 2], 1))
    }

    func testSoundPoolArgumentChecks() {
        var left: Float = 1.5
        var right: Float = 0.5
        ASoundPool.checkVolume(&left, &right)
        XCTAssertEqual([left, right], [1, 1])
        left = 0.3
        right = 0.7
        ASoundPool.checkVolume(&left, &right)
        XCTAssertEqual([left, right], [0.3, 0.7])
        left = -0.1
        right = 0.2
        ASoundPool.checkVolume(&left, &right)
        XCTAssertEqual([left, right], [1, 1])
        var rate: Float = 0.1
        ASoundPool.checkRate(&rate)
        XCTAssertEqual(rate, 0.125)
        rate = 9
        ASoundPool.checkRate(&rate)
        XCTAssertEqual(rate, 8)
        var loop = -5
        ASoundPool.checkLoop(&loop)
        XCTAssertEqual(loop, -1)
        // A 22 050 Hz sample converted to 48 kHz advances one stored frame per output frame at rate 1.
        XCTAssertEqual(ASoundPool.step(22050, AAudio.SAMPLE_RATE, 1), 1)
        XCTAssertEqual(ASoundPool.step(22050, 22050, 1), 22050.0 / 48000.0)
    }

    func testAudioAttributes() {
        let game = AAudioAttributes.Builder().setUsage(AAudioAttributes.USAGE_GAME)
            .setContentType(AAudioAttributes.CONTENT_TYPE_SONIFICATION).build()
        XCTAssertEqual(game.usage, 14)
        XCTAssertEqual(game.contentType, 4)
        XCTAssertEqual(game.flags, 0)
        let music = AAudioAttributes.Builder().setLegacyStreamType(AAudioManager.STREAM_MUSIC).build()
        XCTAssertEqual(music.usage, AAudioAttributes.USAGE_MEDIA)
        XCTAssertEqual(music.contentType, AAudioAttributes.CONTENT_TYPE_UNKNOWN)
        XCTAssertEqual(AAudioAttributes.Builder().build().usage, AAudioAttributes.USAGE_UNKNOWN)
        XCTAssertEqual(AAudioAttributes.Builder().setUsage(AAudioAttributes.USAGE_NOTIFICATION_COMMUNICATION_INSTANT)
                        .build().usage, AAudioAttributes.USAGE_NOTIFICATION)
    }

    // MARK: - ToneGenerator

    func testToneVolumeIsAndroidLinearToLog() {
        XCTAssertEqual(AToneGenerator.linearToLog(100), 1)
        XCTAssertEqual(AToneGenerator.linearToLog(0), 0)
        XCTAssertEqual(AToneGenerator.linearToLog(25), 0.0133352, accuracy: 0.000002)   // -37.5 dB (the journey tick)
        XCTAssertEqual(AToneGenerator.linearToLog(50), 0.0562341, accuracy: 0.000002)   // -25 dB
    }

    func testPropAckFor65msIsOne1200HzBeepOf64msWithA4msFade() {
        let tone = AAudio.ToneRenderer(48000, AToneGenerator.linearToLog(100))
        let descriptor = AAudio.ToneRenderer.descriptor(AToneGenerator.TONE_PROP_ACK)!
        XCTAssertTrue(tone.startTone(descriptor, 65))
        var out = [Float](repeating: 1, count: 4800)
        let active = out.withUnsafeMutableBufferPointer { tone.render($0.baseAddress!, 4800) }
        XCTAssertTrue(active)
        // AOSP WaveGenerator, 1200 Hz at 48 kHz, gain 0.9 / numWaves (2): A1_Q14 32364, S2_0 -5005, amplitude 15098.
        XCTAssertEqual(Array(out[0..<4]), [2306, 4555, 6691, 8662].map { Float($0) / 32768 })
        // 17 callback buffers of 192 frames: 16 at full amplitude, the 17th fades out linearly, then silence.
        XCTAssertEqual(out[0..<3072].map { abs($0) }.max(), 14756 / 32768)
        XCTAssertEqual(out[3072..<3264].map { abs($0) }.max(), 13568 / 32768)
        XCTAssertEqual(out[3263], -64 / 32768)
        XCTAssertTrue(out[3264...].allSatisfy { $0 == 0 })
        XCTAssertFalse(tone.trackActive)
        XCTAssertNil(AAudio.ToneRenderer.descriptor(AToneGenerator.TONE_UNKNOWN))
    }

    func testToneGeneratorPlaysThroughTheMixerAndStopsAfterRelease() {
        let mixer = AAudio.Mixer(engineEnabled: false)
        let generator = AToneGenerator(AAudioManager.STREAM_MUSIC, 25, mixer: mixer)
        XCTAssertTrue(generator.startTone(AToneGenerator.TONE_PROP_ACK, 65))
        let out = mixer.render(frames: 4800)
        XCTAssertEqual(out.left[0], 2306 / 32768 * AToneGenerator.linearToLog(25), accuracy: 1e-9)
        XCTAssertEqual(out.left, out.right)
        XCTAssertTrue(out.left[3264...].allSatisfy { $0 == 0 })
        generator.release()
        XCTAssertFalse(generator.startTone(AToneGenerator.TONE_PROP_ACK, 65))
        XCTAssertFalse(mixer.hasSoundingVoices)
    }
}

// MARK: - MediaPlayer and the soundscape sounds (Android 6c38131)

final class MediaPlayerTests: XCTestCase {
    private func constant(_ value: Float, frames: Int) -> AAudio.PCMData {
        return AAudio.PCMData(channel0: [Float](repeating: value, count: frames), channel1: nil,
                              sourceSampleRate: AAudio.SAMPLE_RATE, frameRate: AAudio.SAMPLE_RATE)
    }

    func testMediaPlayerPlaysPausesResumesLoopsAndReportsDuration() {
        let mixer = AAudio.Mixer(engineEnabled: false)
        let player = AMediaPlayer.create(decoded: constant(1, frames: 4800), mixer: mixer)
        XCTAssertEqual(player.duration, 100)
        XCTAssertFalse(player.isPlaying)
        player.setVolume(0.5, 0.25)
        player.start()
        XCTAssertTrue(player.isPlaying)
        var out = mixer.render(frames: 10)
        XCTAssertEqual(out.left[9], 0.5)
        XCTAssertEqual(out.right[9], 0.25)
        player.pause()
        XCTAssertFalse(player.isPlaying)
        _ = mixer.render(frames: 480)                            // the pause ramp ends
        XCTAssertEqual(mixer.render(frames: 10).left[9], 0)
        player.start()                                           // resumes where it paused
        XCTAssertTrue(player.isPlaying)
        player.isLooping = true
        out = mixer.render(frames: 9600)                         // past the end: looping keeps playing
        XCTAssertEqual(out.left[9599], 0.5)
        XCTAssertTrue(player.isPlaying)
        player.isLooping = false
        _ = mixer.render(frames: 9600)
        XCTAssertFalse(player.isPlaying)                         // completed
        player.release()
        player.start()                                           // End state: ignored
        XCTAssertFalse(player.isPlaying)
    }

    /// Every sound BasketballSoundscape plays decodes with AVAudioFile: the Ogg Vorbis files of Android are bundled as
    /// CAF/ALAC (Scripts/tripleshot-sync-resources.py), the trumpet as Android's MP3.
    func testSoundscapeSoundsDecode() throws {
        for res in [R.raw.basket_menu, R.raw.basket_crowd_0, R.raw.basket_crowd_1, R.raw.basket_crowd_2,
                    R.raw.basket_trumpet, R.raw.basket_whistle, R.raw.basket_applause, R.raw.basket_disappoint,
                    R.raw.basket_claps, R.raw.basket_bonus, R.raw.basket_lose] {
            let url = try XCTUnwrap(AResources.rawURL(res), res)
            let data = try XCTUnwrap(AAudio.decode(url), res)
            XCTAssertGreaterThan(data.frameCount, 0, res)
            XCTAssertNotNil(AMediaPlayer.create(nil, res, mixer: AAudio.Mixer(engineEnabled: false)), res)
        }
        XCTAssertEqual(AResources.rawURL(R.raw.basket_menu)?.pathExtension, "caf")
        XCTAssertEqual(AResources.rawURL(R.raw.basket_trumpet)?.pathExtension, "mp3")
    }

    func testActivityLifecycleCallbacksAreRegisteredAndRemoved() {
        final class Recorder: AActivityLifecycleCallbacks {
            var events: [String] = []
            func onActivityResumed(_ activity: AActivity) { events.append("resumed") }
        }
        let recorder = Recorder()
        AApplication.shared.registerActivityLifecycleCallbacks(recorder)
        let activity = AActivity()
        AApplication.shared.dispatchActivityResumed(activity)
        AApplication.shared.dispatchActivityPaused(activity)      // default: no-op
        AApplication.shared.unregisterActivityLifecycleCallbacks(recorder)
        AApplication.shared.dispatchActivityResumed(activity)
        XCTAssertEqual(recorder.events, ["resumed"])
    }
}
