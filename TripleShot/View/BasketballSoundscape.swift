import Foundation

// Port of view/BasketballSoundscape.kt (Android 6c38131), statement by statement.
// Kotlin `object ... : Application.ActivityLifecycleCallbacks` -> an enum with static state (DESIGN 2.1) plus the
// `Callbacks` object registered with AApplication (the Kotlin object registers itself).
// * `WeakHashMap<Activity, Scene>` -> `scenes`, weak keys compared by identity; `WeakReference<Activity>` -> `weak`.
// * MediaPlayer / SoundPool / AudioManager focus -> AMediaPlayer / ASoundPool / AAudioManager (AndroidKit).
//   `Build.VERSION.SDK_INT >= 26` is always true on iOS's AndroidKit, so the AudioFocusRequest branch is ported.
// * Res/raw: the Ogg Vorbis files are CAF/ALAC copies (Scripts/tripleshot-sync-resources.py); the trumpet is the MP3.

/** One soundtrack owner for the app. Menu music cannot continue over a live match. */
enum BasketballSoundscape {
    enum Scene: String, KotlinEnum { case MENU, COURT, SILENT }
    enum Effect: String, KotlinEnum { case WHISTLE, APPLAUSE, DISAPPOINT, CLAPS, WIN, LOSE }

    nonisolated(unsafe) private static var launchTrumpetPlayed = false
    nonisolated(unsafe) private static var trumpetPlayer: AMediaPlayer? = nil
    nonisolated(unsafe) private static var trumpetFinished: ((Bool) -> Void)? = nil

    private static func stopTrumpet(completed: Bool = false) {
        trumpetPlayer?.release(); trumpetPlayer = nil
        let done = trumpetFinished; trumpetFinished = nil; done?(completed)
    }

    /** Called only after the actual home view has been drawn, once per app process. */
    static func mainMenuVisible(activity: AActivity) {
        if launchTrumpetPlayed || active !== activity || scenes[activity] != .MENU || !activity.hasWindowFocus() { return }
        launchTrumpetPlayed = true
        trumpet(activity: activity, reason: "menu")
    }

    /** Completion is cancelled on background/focus loss; callers must never start a game then. */
    @discardableResult
    static func trumpet(activity: AActivity, reason: String, finished: @escaping (Bool) -> Void = { _ in }) -> Bool {
        if !enabled() { finished(true); return false }
        if active !== activity || !activity.hasWindowFocus() || !acquireFocus() { finished(false); return false }
        if trumpetPlayer != nil { if reason == "team-start" { stopTrumpet() } else { finished(false); return false } }
        guard let player = AMediaPlayer.create(activity, R.raw.basket_trumpet) else { finished(true); return false }
        trumpetPlayer = player; trumpetFinished = finished
        player.setVolume(Float(0.62), Float(0.62))
        player.setOnCompletionListener { mp in if trumpetPlayer === mp { stopTrumpet(completed: true) } }
        player.setOnErrorListener { _, _, _ in stopTrumpet(completed: true); return true }
        player.start(); ALog.i("TRIPLE_TRUMPET", "play reason=\(reason) duration=\(player.duration)")
        return true
    }

    nonisolated(unsafe) private static var app: AApplication? = nil
    nonisolated(unsafe) private static var scenes = WeakScenes()
    nonisolated(unsafe) private static weak var active: AActivity? = nil
    nonisolated(unsafe) private static var music: AMediaPlayer? = nil
    nonisolated(unsafe) private static var current: Scene? = nil
    nonisolated(unsafe) private static var pool: ASoundPool? = nil
    nonisolated(unsafe) private static var sounds: [Effect: Int] = [:]
    nonisolated(unsafe) private static var loaded = Set<Int>()
    nonisolated(unsafe) private static var crowd = 0
    nonisolated(unsafe) private static var volume: Float = 0
    nonisolated(unsafe) private static var focusGranted = false
    nonisolated(unsafe) private static var manager: AAudioManager? = nil
    nonisolated(unsafe) private static var focus: AAudioFocusRequest? = nil
    nonisolated(unsafe) private static var duck: Float = 1
    nonisolated(unsafe) private static var lastEffectAt: Int64 = 0
    nonisolated(unsafe) private static var lastEffect: Effect? = nil
    private static let handler = AHandler(ALooper.getMainLooper())
    private static let attributes = AAudioAttributes.Builder().setUsage(AAudioAttributes.USAGE_GAME)
        .setContentType(AAudioAttributes.CONTENT_TYPE_MUSIC).build()
    private static let focusListener: AAudioManager.OnAudioFocusChangeListener = { change in
        switch change {
        case AAudioManager.AUDIOFOCUS_GAIN: focusGranted = true; duck = 1; sync()
        case AAudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK: duck = Float(0.2)
        default: focusGranted = false; music?.pause(); pool?.autoPause(); stopTrumpet()
        }
    }
    /// The Kotlin object as the registered Application.ActivityLifecycleCallbacks.
    private static let callbacks = Callbacks()

    static func scene(activity: AActivity, value: Scene) {
        if app == nil {
            app = activity.application; app!.registerActivityLifecycleCallbacks(callbacks)
            manager = activity.getSystemService(AContextService.AUDIO_SERVICE) as? AAudioManager
            let p = ASoundPool.Builder().setMaxStreams(5).setAudioAttributes(attributes).build()
            p.setOnLoadCompleteListener { _, id, status in if status == 0 { loaded.insert(id) } }
            let effects: [(Effect, ARawRes)] = [(.WHISTLE, R.raw.basket_whistle), (.APPLAUSE, R.raw.basket_applause),
                                                (.DISAPPOINT, R.raw.basket_disappoint), (.CLAPS, R.raw.basket_claps),
                                                (.WIN, R.raw.basket_bonus), (.LOSE, R.raw.basket_lose)]
            for (kind, res) in effects { sounds[kind] = p.load(res, 1) }
            pool = p
        }
        if value == .SILENT || (value == .MENU && scenes[activity] == .COURT) { stopTrumpet() }
        scenes[activity] = value
        if !activity.isFinishing { active = activity; sync() }
    }

    private static func enabled() -> Bool {
        active?.getSharedPreferences("basketball_journey", 0).getBoolean("sound", true) == true
    }

    private static func acquireFocus() -> Bool {
        if focusGranted { return true }
        guard let m = manager else { return false }
        let request: AAudioFocusRequest
        if let existing = focus {
            request = existing
        } else {
            request = AAudioFocusRequest.Builder(AAudioManager.AUDIOFOCUS_GAIN).setAudioAttributes(attributes)
                .setOnAudioFocusChangeListener(focusListener).build()
            focus = request
        }
        let result = m.requestAudioFocus(request)
        focusGranted = result == AAudioManager.AUDIOFOCUS_REQUEST_GRANTED; return focusGranted
    }

    private static func releaseFocus() {
        if let f = focus { manager?.abandonAudioFocusRequest(f) }
        focusGranted = false
    }

    private static func stop() { music?.release(); music = nil; current = nil; volume = 0; handler.removeCallbacks(tick) }

    private static func sync() {
        guard let activity = active else { stop(); return }
        let mode = scenes[activity] ?? .MENU
        if !enabled() { stop(); stopTrumpet(); pool?.autoPause(); return }
        if mode == .SILENT { stop(); return }
        if !acquireFocus() { return }
        pool?.autoResume()
        if mode == current && music != nil {
            if !music!.isPlaying { music!.start() }
            handler.removeCallbacks(tick); handler.post(tick); return
        }
        stop(); current = mode
        let resource = mode == .MENU ? R.raw.basket_menu
            : [R.raw.basket_crowd_0, R.raw.basket_crowd_1, R.raw.basket_crowd_2][crowd % 3]
        music = AMediaPlayer.create(activity, resource)
        if let m = music {
            m.setVolume(0, 0); m.isLooping = mode == .MENU
            m.setOnCompletionListener { _ in if current == .COURT { crowd += 1; current = nil; sync() } }
            m.start()
        }
        handler.post(tick)
    }

    /// The Kotlin `object : Runnable` (one instance, removed by identity).
    private static let tick = ARunnable { runTick() }

    private static func runTick() {
        if active == nil || !enabled() { stop(); return }
        let wave = Float(0.5) + Float(0.5) * sin(Double(ASystemClock.uptimeMillis()) / 5300.0).toFloat()
        let desired = (current == .MENU ? Float(0.32) : Float(0.15) + Float(0.09) * wave) * duck
            * (trumpetPlayer != nil ? Float(0.3) : 1)
        volume += (desired - volume) * Float(0.12)
        music?.setVolume(volume, volume); handler.postDelayed(tick, 120)
    }

    static func refresh() { sync() }

    static func effect(context: AContext, kind: Effect) {
        if !enabled() || active == nil || !acquireFocus() { return }
        let now = ASystemClock.uptimeMillis(); if lastEffect == kind && now &- lastEffectAt < 500 { return }
        lastEffect = kind; lastEffectAt = now
        guard let sound = sounds[kind] else { return }
        if loaded.contains(sound) {
            pool?.play(sound, Float(0.65), Float(0.65), 1, 0, 1); ALog.i("TRIPLE_AUDIO", "effect=\(kind.name)")
        } else if kind == .WHISTLE {
            handler.postDelayed({
                if loaded.contains(sound) && active != nil && enabled() { pool?.play(sound, Float(0.65), Float(0.65), 1, 0, 1) }
            }, 350)
        }
    }

    static func result(activity: AActivity, won: Bool, gap: Int = 0, challenge: Bool = false) {
        scene(activity: activity, value: .SILENT)
        effect(context: activity, kind: challenge ? (won ? .WIN : .LOSE) : won ? .APPLAUSE : gap >= 4 ? .DISAPPOINT : .CLAPS)
    }

    static func onActivityResumed(_ a: AActivity) { if scenes.contains(a) { active = a; sync() } }

    static func onActivityPaused(_ a: AActivity) {
        if active === a {
            active = nil; stopTrumpet(); music?.pause(); pool?.autoPause(); handler.removeCallbacks(tick); releaseFocus()
        }
    }

    static func onActivityDestroyed(_ a: AActivity) {
        scenes.remove(a)
        if active === a { active = nil; stopTrumpet(); stop() }
    }

    private final class Callbacks: AActivityLifecycleCallbacks {
        func onActivityResumed(_ activity: AActivity) { BasketballSoundscape.onActivityResumed(activity) }
        func onActivityPaused(_ activity: AActivity) { BasketballSoundscape.onActivityPaused(activity) }
        func onActivityDestroyed(_ activity: AActivity) { BasketballSoundscape.onActivityDestroyed(activity) }
    }

    /// `WeakHashMap<Activity, Scene>`: activities are compared by identity and dropped once deallocated.
    struct WeakScenes {
        private final class Entry {
            weak var activity: AActivity?
            var scene: Scene
            init(_ activity: AActivity, _ scene: Scene) { self.activity = activity; self.scene = scene }
        }
        private var entries: [Entry] = []

        subscript(activity: AActivity) -> Scene? {
            get { entries.first { $0.activity === activity }?.scene }
            set {
                entries.removeAll { $0.activity == nil }
                if let entry = entries.first(where: { $0.activity === activity }) {
                    if let value = newValue { entry.scene = value } else { entries.removeAll { $0 === entry } }
                } else if let value = newValue {
                    entries.append(Entry(activity, value))
                }
            }
        }

        func contains(_ activity: AActivity) -> Bool { entries.contains { $0.activity === activity } }

        mutating func remove(_ activity: AActivity) { self[activity] = nil }
    }
}
