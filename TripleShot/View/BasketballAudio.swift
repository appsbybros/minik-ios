import Foundation

// Port of view/BasketballAudio.kt (Android snapshot dd722e5), statement by statement (spec 07 §3.7, §4.10, §8 item 15).
// Kotlin Long arithmetic never traps, so the debounce differences use wrapping `&-`.
// Android quirks kept: catch also plays on release (owner -> null while the ball is still in the scene) and on the
// first presented frame that shows a held ball; the owner change resets the phase, so a catch and a bounce can share a
// frame; only the owner of the FIRST ball counts; the debounce timestamps advance even when the "sound" preference
// mutes the play; a failed load is never played. The SoundPool load listener runs on the main thread (Android: the
// main looper), so `ready` needs no lock.

/** Quiet real-time court foley; follows the media-volume setting and the app sound preference. */
final class BasketballAudio {
    private let prefs: ASharedPreferences
    private let pool: ASoundPool
    private var ready = Set<Int>()
    private var bounce = 0
    private var `catch` = 0
    private var swish = 0
    private var owner: String? = nil
    private var previousPhase: Float = 0
    private var lastBounce: Int64 = 0
    private var lastSwish: Int64 = 0
    /// `SystemClock.uptimeMillis()` (injectable for tests).
    private let uptimeMillis: () -> Int64

    /// Kotlin `BasketballAudio(context)`; the arguments are test seams, evaluated in the Kotlin property order
    /// (prefs, then the pool).
    init(prefs: ASharedPreferences = getSharedPreferences("basketball_journey", 0),
         pool: ASoundPool = ASoundPool.Builder().setMaxStreams(3).setAudioAttributes(
            AAudioAttributes.Builder().setUsage(AAudioAttributes.USAGE_GAME)
                .setContentType(AAudioAttributes.CONTENT_TYPE_SONIFICATION).build()).build(),
         uptimeMillis: @escaping () -> Int64 = ASystemClock.uptimeMillis) {
        self.prefs = prefs
        self.pool = pool
        self.uptimeMillis = uptimeMillis
        pool.setOnLoadCompleteListener { [weak self] _, id, status in if status == 0 { self?.ready.insert(id) } }
        bounce = pool.load(R.raw.basket_bounce, 1)
        `catch` = pool.load(R.raw.basket_catch, 1)
        swish = pool.load(R.raw.basket_swish, 1)
    }

    private func play(_ id: Int, _ volume: Float) {
        if prefs.getBoolean("sound", true) && ready.contains(id) { pool.play(id, volume, volume, 1, 0, 1) }
    }

    func frame(_ scene: TripleShotWorldSnapshot) {
        let ball = scene.balls.first; let now = uptimeMillis()
        let actor = scene.actors.first { $0.id == ball?.owner }
        if ball?.owner != owner { if ball != nil { play(`catch`, 0.55) }; owner = ball?.owner; previousPhase = 0 }
        if let actor = actor, actor.state.motion == TripleShotPlayerRenderer.Motion.DRIBBLE {
            let phase = actor.state.dribblePhase01
            if previousPhase < 0.5 && phase >= 0.5 && now &- lastBounce > 300 { play(bounce, 0.5); lastBounce = now }
            previousPhase = phase
        }
        if abs(scene.netSway) > 0.005 && now &- lastSwish > 900 { play(swish, 0.65); lastSwish = now }
    }

    func close() { pool.release() }
}
