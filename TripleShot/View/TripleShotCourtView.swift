import Foundation
import UIKit

// Port of view/TripleShotCourtView.kt (TripleShotGame 6c38131), PART 1: Kotlin lines 1-2654 (spec 08-court1).
//
// TripleShotCourtView is split over three files (DESIGN 2.9 / 2.10):
//   - this file (part 1): the class declaration, every nested type declared in lines 1-2654, ALL stored
//     properties of the whole Kotlin class (including `premiumGuides` / `premiumGuidesAt` from line 5578), the
//     frame / timer runnables (lazy vars, so they can capture the view), every `override` of the whole Kotlin
//     file, and every method of lines 1-2654;
//   - TripleShotCourtView+Part2.swift: methods of lines 2655-5352 (extension);
//   - TripleShotCourtView+Part3.swift: methods of lines 5353-7945 and the companion object (static members).
// Overrides whose Kotlin bodies are in part 3 forward to `<name>_impl` (DESIGN 2.10):
//   onSizeChanged -> onSizeChanged_impl(_:_:_:_:), onDraw -> onDraw_impl(_:), onDetachedFromWindow ->
//   onDetachedFromWindow_impl().
// Kotlin `private` members are internal here (split class). Units are Android pixels (DESIGN 2.5): `width`,
// `height`, positions and the physics state are px of this view; source-artwork coordinates are the 1024x1536
// image. *Nanos = ASystem.nanoTime() (since boot; 0 = "expired"); Long time maths wraps.
//
// Dead Android fields that nothing reads are not ported (spec 08 sections 3.2(a), 3.2(c), 8.11):
// `atmosphereRenderer` (weather is drawn by the base overlay), the lazy `hoopStructureDrawable`, and the legacy
// Canvas paints `paint`, `stroke`, `markerTextPaint`. Written-but-never-read fields (`currentBallDrawable`,
// `humanVictorySpotlights`, `LiveRemoteVisual.renderScale/score`, `botLabel`) are kept so the writes stay 1:1.

/**
 * Renderer for the MINIK SWISH court.
 *
 * V3 deliberately separates three responsibilities:
 *  - answer stations / player movement,
 *  - pre-shot feedback (aim + arc),
 *  - real frame-by-frame ball physics.
 *
 * A shot is NOT pre-labelled "made". The ball can hit either side of the rim,
 * rebound several times, bank off the board, air-ball or physically cross the
 * hoop opening. This keeps the mechanic learnable and skill based.
 */
final class TripleShotCourtView: TripleShotWorldHostView {

    enum ShotKind: String, KotlinEnum {
        case SWISH
        case RIM_IN
        case BANK_IN
        case RIM_OUT
        case BACKBOARD_OUT
        case AIRBALL
        case INVALID_BELOW
    }

    /** One visible shared ball is used for local HORSE turn-taking. */
    enum SharedBallOwner: String, KotlinEnum {
        case HUMAN
        case BOT
    }

    struct ShotResult: Hashable {
        var outcome: ShotOutcome
        var kind: ShotKind
        var rimHits: Int
        var backboardHits: Int
        var replaySamples: [ShotReplaySample]

        init(
            outcome: ShotOutcome,
            kind: ShotKind,
            rimHits: Int,
            backboardHits: Int,
            replaySamples: [ShotReplaySample] = []
        ) {
            self.outcome = outcome
            self.kind = kind
            self.rimHits = rimHits
            self.backboardHits = backboardHits
            self.replaySamples = replaySamples
        }

        /// Positional form of the Kotlin constructor (the labelled initialiser is preferred, DESIGN 2.1).
        init(
            _ outcome: ShotOutcome,
            _ kind: ShotKind,
            _ rimHits: Int,
            _ backboardHits: Int,
            _ replaySamples: [ShotReplaySample] = []
        ) {
            self.init(
                outcome: outcome,
                kind: kind,
                rimHits: rimHits,
                backboardHits: backboardHits,
                replaySamples: replaySamples
            )
        }
    }

    /// Kotlin `private data class Station`. Data-class equality is used (`candidate in chosen`), so `==`
    /// follows Kotlin: Float properties compare with `Float.compare(a, b) == 0` (floatToIntBits).
    struct Station: Hashable {
        var id: String
        var sourceX: Float
        var sourceY: Float
        /**
         * 0 = easiest/shortest physical release, 1 = requires the strongest release.
         * Geometry still does most of the work; this value only nudges required power.
         */
        var distanceDifficulty: Float
        var zone: String

        init(
            id: String,
            sourceX: Float,
            sourceY: Float,
            distanceDifficulty: Float,
            zone: String = "court"
        ) {
            self.id = id
            self.sourceX = sourceX
            self.sourceY = sourceY
            self.distanceDifficulty = distanceDifficulty
            self.zone = zone
        }

        /// Positional form of `Station("L01", 220f, 920f, 0.61f, "left_bush")` (catalogs in part 3).
        init(
            _ id: String,
            _ sourceX: Float,
            _ sourceY: Float,
            _ distanceDifficulty: Float,
            _ zone: String = "court"
        ) {
            self.init(
                id: id,
                sourceX: sourceX,
                sourceY: sourceY,
                distanceDifficulty: distanceDifficulty,
                zone: zone
            )
        }

        static func == (lhs: Station, rhs: Station) -> Bool {
            return lhs.id == rhs.id &&
                lhs.sourceX.toBits() == rhs.sourceX.toBits() &&
                lhs.sourceY.toBits() == rhs.sourceY.toBits() &&
                lhs.distanceDifficulty.toBits() == rhs.distanceDifficulty.toBits() &&
                lhs.zone == rhs.zone
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
            hasher.combine(sourceX.toBits())
            hasher.combine(sourceY.toBits())
            hasher.combine(distanceDifficulty.toBits())
            hasher.combine(zone)
        }
    }

    struct BackgroundTransform: Hashable {
        var scaleX: Float
        var scaleY: Float
        var offsetX: Float
        var offsetY: Float

        init(scaleX: Float, scaleY: Float, offsetX: Float, offsetY: Float) {
            self.scaleX = scaleX
            self.scaleY = scaleY
            self.offsetX = offsetX
            self.offsetY = offsetY
        }

        /// Positional form of the Kotlin constructor.
        init(_ scaleX: Float, _ scaleY: Float, _ offsetX: Float, _ offsetY: Float) {
            self.init(scaleX: scaleX, scaleY: scaleY, offsetX: offsetX, offsetY: offsetY)
        }
    }

    var premiumCourtId = TripleShotCourtCatalog.DEFAULT_ID
    let humanShotPresentation = TripleShotShotPresentation()
    let botShotPresentation = TripleShotShotPresentation()
    var remoteShotPresentations = KLinkedMap<String, TripleShotShotPresentation>()
    var lastWorldFlight: CourtPoint? = nil
    var looseWorldFrom: CourtPoint? = nil
    var looseWorldAt: Int64 = 0
    var worldLooseBall: TripleShotLooseBall? = nil
    var freeMoveLastNanos: Int64 = 0
    let humanVisualMotion = BasketballVisualMotion(Float(0.017))
    let botVisualMotion = BasketballVisualMotion(Float(0.017))

    func stableSoloState(raw: TripleShotPlayerRenderer.State, human: Bool) -> TripleShotPlayerRenderer.State {
        let tracker = human ? humanVisualMotion : botVisualMotion
        let t = backgroundTransform()
        let committed = ![TripleShotPlayerRenderer.Motion.IDLE, TripleShotPlayerRenderer.Motion.WALK,
                          TripleShotPlayerRenderer.Motion.DRIBBLE, TripleShotPlayerRenderer.Motion.WAITING].contains(raw.motion)
        tracker.update(now: ASystemClock.uptimeMillis(), nextX: (raw.x - t.offsetX) / t.scaleX,
                       nextY: ((human ? playerFootY : botFootY) - t.offsetY) / t.scaleY, wantedFacing: raw.facing.ordinal,
                       sideFacing: TripleShotPlayerRenderer.Facing.SIDE.ordinal, wantedMirror: raw.mirrorX, committedAction: committed)
        let now = ASystem.nanoTime()
        let fallen = now < (human ? humanFallenUntil : botFallenUntil)
        let spinAge = (now &- (human ? humanSpinAt : botSpinAt)) / 1_000_000
        let turning = spinAge >= 0 && spinAge <= 359
        var state = raw
        state.facing = turning ? raw.facing : TripleShotPlayerRenderer.Facing.allCases[tracker.facing]
        state.mirrorX = tracker.mirror
        state.pose = fallen ? TripleShotPlayerRenderer.Pose.LOSER : raw.pose
        state.crossoverProgress = ((now &- (human ? humanCrossAt : botCrossAt)).toFloat() / Float(420_000_000)).coerceIn(0, 1)
        state.crossoverFrom = human ? humanCrossFrom : botCrossFrom
        state.crossoverBehind = human ? humanCrossBehind : botCrossBehind
        state.moving = tracker.moving && !fallen
        state.locomotionFrameIndex = tracker.frameIndex
        return basketCelebration(raw: state, human: human)
    }

    let humanSpinSeries = BasketballMoves.SpinSeries()
    let botSpinSeries = BasketballMoves.SpinSeries()
    var humanFallenUntil: Int64 = 0; var botFallenUntil: Int64 = 0
    var humanRecoveryUntil: Int64 = 0
    var humanCrossBehind = false; var botCrossBehind = false
    var basketCelebrationAt: Int64 = 0
    var basketCelebrationHuman = true
    var basketCelebrationDance = false
    var lastRenderedTransform: BackgroundTransform? = nil
    var oneOnOneWorldStarted = false
    /// `resources.displayMetrics.density` (UIScreen scale; `dp(v) = v * density` px).
    let density: Float = AResources.displayMetrics.density
    let playerRenderer = TripleShotPlayerRenderer(context: nil)
    var courtAtmosphere = TripleShotCourtAtmosphere.NONE

    // Stable roster ids. Character-specific drawable names live only in the visual catalog.
    var humanCharacterId = TripleShotCharacterRoster.ID_WOMAN_DARK
    var botCharacterId = TripleShotCharacterRoster.ID_BOB

    let courtTheme: CourtTheme = CourtThemes.ENCHANTED_FOREST

    var answerCount = 3
    var selectedStation = -1

    /**
     * Per-question answer locations. They are chosen from a curated source-image catalog,
     * so answers can live on the painted court or in low bushes without ever placing the
     * player in mid-air / on a tree trunk.
     */
    var activeStations: [Station] = []

    // HORSE uses the same curated legal spot catalog, but answer markers are hidden and the
    // setter chooses a physical location directly on the court. These fields are opt-in and
    // therefore do not alter Practice / Shooting Challenge behavior.
    var answerMarkersVisible = true
    var horseSpotPickerVisible = false
    var horseFreeMoveEnabled = false
    var horseHumanStation: Station? = nil
    var horseSelectedSpotId: String? = nil

    // Human-set HORSE locations are no longer restricted to the curated answer catalog.
    // They are stored in source-image coordinates so MINIK can later walk to the exact
    // same physical challenge point, even if the view is resized.
    var horseCustomSpots = KLinkedMap<String, Station>()
    var horseCustomSpotCounter = 0
    var horseFreeMovePhase: Float = 0

    lazy var horseFreeMoveSettleRunnable: ARunnable = ARunnable({ [weak self] in
        guard let self = self else { return }
        if horseFreeMoveEnabled {
            humanWalking = false
            dribbleBouncePx = 0
            humanDribblePhase01 = 0
            humanDribbleHandSign = humanWalkingDribbleHandSign
            resetHumanMovementSpeed()
            scheduleHumanIdleDribble()
            invalidate()
        }
    })

    /**
     * Small anti-repetition memory for Shooting Challenge.
     * Exact answer spots used in the last few questions are temporarily avoided so a
     * 60-second run feels like moving around a real area rather than cycling through
     * the same three coordinates with different labels.
     */
    var recentSpotIds: [String] = []

    /*
     * Bottom edge of the playable court, supplied by the Fragment after the
     * answer row has been laid out. This keeps A/B/C/D station markers above
     * the answer buttons on every screen size instead of relying on a fixed dp guess.
     */
    var gameplayBottomBoundaryPx: Float? = nil

    // Player position is stored in view pixels because the background uses centerCrop.
    var playerX: Float = 0
    var playerFootY: Float = 0
    var hasInitialPlayerPosition = false

    var fineAim: Float = 0
    var pullBack: Float = 0
    var shotGuidesVisible = false
    var horseJumpShot = false
    var horseJumpAt: Int64 = 0
    var horseGathering = false
    var horseRelease: ARunnable? = nil

    func setHorseJumpShot(enabled: Bool) {
        horseJumpShot = enabled
        invalidate()
    }

    func horseJumpLift() -> Float {
        let t = Float(ASystemClock.elapsedRealtime() &- horseJumpAt) / 760
        return horseJumpShot && t >= 0 && t <= 1 ? dp(v: 68) * ksin(t * PI_F) : 0
    }

    // 1v1 quick-shot keeps the shooting keyframes but can hide the HORSE-style guide/arc.
    var oneOnOneSuppressShotGuideDrawing = false

    /*
     * 0 = maximum visual help, 5 = expert/minimum help.
     * This only changes the pre-shot guide; it never changes the physical launch.
     */
    var aimAssistBaseLevel = 0

    var ballVisible = true
    var ballX: Float = 0
    var ballY: Float = 0
    var ballRotationDeg: Float = 0

    var playerMoveAnimator: AValueAnimator? = nil
    var humanWalking = false
    var hotHand = false
    var dribbleBouncePx: Float = 0
    // Moving dribble state. Slow movement uses controlled crossovers; fast movement keeps
    // one hand, matching the natural V9 feel. These are visual-only and never affect physics.
    var humanWalkingDribbleHandSign: Float = 1
    var humanMovingFast = false
    var humanMovementSpeedDpPerSec: Float = 0
    var humanMovementSampleNanos: Int64 = 0
    // Last meaningful lateral travel direction. Used only to mirror fast-dribble art/ball hand.
    var humanMovementHorizontalSign: Float = 0
    var humanWalkingBounceIndex = 0
    var humanWalkingBallPassInFront = true

    // FRONT/BACK is a persistent court-Y state. Horizontal movement must NEVER flip the body.
    // A small Y hysteresis band prevents tiny vertical drift around the divider from flickering.
    var humanCourtFacing = TripleShotPlayerRenderer.Facing.BACK
    var humanCourtFacingInitialized = false

    // Human-only visual choice. Physics stays identical between PRO and GRANNY.
    var humanShotStyle = TripleShotPlayerRenderer.ShotStyle.PRO
    // HORSE: true only while the human has stepped aside for MINIK's turn.
    var humanWaitingForTurn = false
    // Local HORSE turn ownership for the single dynamic ball. This replaces no existing
    // physics; it only decides whether the human or MINIK renders the held ball between shots.
    var sharedHorseBallOwner: SharedBallOwner? = nil

    // A quiet single bounce every so often while the human is choosing a HORSE spot.
    var humanIdleDribbling = false
    var humanIdleDribbleBouncePx: Float = 0
    var humanDribblePhase01: Float = 0
    var humanDribbleHandSign: Float = 1
    var humanIdleDribbleAnimator: AValueAnimator? = nil
    lazy var humanIdleDribbleRunnable: ARunnable = ARunnable({ [weak self] in
        self?.startHumanIdleDribbleIfEligible()
    })

    var humanReleaseStartedAtNanos: Int64 = 0

    /*
     * Local bot state is completely opt-in. Solo/practice never enable it, so the original
     * player movement, input and shot simulation remain untouched. The bot owns its own
     * position, movement animator, ball and physics state.
     */
    var botEnabled = false
    var botLabel = "BOT"
    var botX: Float = 0
    var botFootY: Float = 0
    var botFineAim: Float = 0
    var botPullBack: Float = 0
    var botDribbleBouncePx: Float = 0
    var botDribbleHandSign: Float = 1
    var botHotHand = false
    var botCurrentStation: Station? = nil
    var recentBotSpotIds: [String] = []
    var botMoveAnimator: AValueAnimator? = nil
    var botAimAnimator: AValueAnimator? = nil
    var botCourtFacing = TripleShotPlayerRenderer.Facing.BACK

    var botBallVisible = false
    var botBallX: Float = 0
    var botBallY: Float = 0
    var botBallRotationDeg: Float = 0

    // End-of-HORSE celebration is opt-in and never runs in solo/practice/challenge.
    var humanEndPose = TripleShotPlayerRenderer.Pose.NORMAL
    var botEndPose = TripleShotPlayerRenderer.Pose.NORMAL
    var matchCelebrationProgress: Float = 0
    var humanVictorySpotlights = false
    var matchCelebrationAnimator: AValueAnimator? = nil

    var botPhysicsState: TripleShotPhysics.ShotState? = nil
    var botPhysicsGeometry: TripleShotPhysics.Geometry? = nil
    var botShotFrameRunning = false
    var botShotLastFrameNanos: Int64 = 0
    var botShotMadeAtSeconds: Float? = nil
    var botShotOnEnd: ((ShotResult) -> Void)? = nil

    /**
     * Lightweight remote-player visuals for Live Shooting Challenge. The authoritative
     * score still comes from Firebase player state; this map only mirrors a remote release
     * locally so other players can actually watch the shot instead of seeing a text event.
     *
     * Kotlin `private data class` with `var`s that is shared and mutated in place -> final class (DESIGN 2.1).
     */
    final class LiveRemoteVisual {
        let uid: String
        var name: String
        var score: Int
        var sourceX: Float
        var sourceY: Float
        var x: Float
        var footY: Float
        var dribbleBouncePx: Float
        var ballVisible: Bool
        var ballX: Float
        var ballY: Float
        var ballRotationDeg: Float
        var hotHand: Bool
        var pose: TripleShotPlayerRenderer.Pose
        var renderScale: Float
        var replayActive: Bool
        var replayStartX: Float
        var replayStartY: Float
        var replayFlightProgress: Float
        var moveAnimator: AValueAnimator?
        var replayAnimator: AValueAnimator?
        // Fallback for older shot events that do not contain replay samples.
        var physicsState: TripleShotPhysics.ShotState?
        var physicsGeometry: TripleShotPhysics.Geometry?
        var lastFrameNanos: Int64
        var madeAtSeconds: Float?

        init(
            uid: String,
            name: String,
            score: Int = 0,
            sourceX: Float,
            sourceY: Float,
            x: Float = 0,
            footY: Float = 0,
            dribbleBouncePx: Float = 0,
            ballVisible: Bool = true,
            ballX: Float = 0,
            ballY: Float = 0,
            ballRotationDeg: Float = 0,
            hotHand: Bool = false,
            pose: TripleShotPlayerRenderer.Pose = TripleShotPlayerRenderer.Pose.NORMAL,
            renderScale: Float = 0.82,
            replayActive: Bool = false,
            replayStartX: Float = 0,
            replayStartY: Float = 0,
            replayFlightProgress: Float = 0,
            moveAnimator: AValueAnimator? = nil,
            replayAnimator: AValueAnimator? = nil,
            physicsState: TripleShotPhysics.ShotState? = nil,
            physicsGeometry: TripleShotPhysics.Geometry? = nil,
            lastFrameNanos: Int64 = 0,
            madeAtSeconds: Float? = nil
        ) {
            self.uid = uid
            self.name = name
            self.score = score
            self.sourceX = sourceX
            self.sourceY = sourceY
            self.x = x
            self.footY = footY
            self.dribbleBouncePx = dribbleBouncePx
            self.ballVisible = ballVisible
            self.ballX = ballX
            self.ballY = ballY
            self.ballRotationDeg = ballRotationDeg
            self.hotHand = hotHand
            self.pose = pose
            self.renderScale = renderScale
            self.replayActive = replayActive
            self.replayStartX = replayStartX
            self.replayStartY = replayStartY
            self.replayFlightProgress = replayFlightProgress
            self.moveAnimator = moveAnimator
            self.replayAnimator = replayAnimator
            self.physicsState = physicsState
            self.physicsGeometry = physicsGeometry
            self.lastFrameNanos = lastFrameNanos
            self.madeAtSeconds = madeAtSeconds
        }
    }

    /// Insertion order = draw order (Kotlin `linkedMapOf`).
    var liveRemotePlayers = KLinkedMap<String, LiveRemoteVisual>()

    // Live replay capture is opt-in so Solo / Practice / Bot keep their exact old path.
    var liveReplayCaptureEnabled = false
    var liveReplaySamples: [ShotReplaySample] = []
    var liveReplayStartedAtNanos: Int64 = 0
    var liveReplayLastSampleMs: Int64 = -TripleShotCourtView.LIVE_REPLAY_SAMPLE_INTERVAL_MS

    // Real shot simulation state.
    var physicsState: TripleShotPhysics.ShotState? = nil
    var physicsGeometry: TripleShotPhysics.Geometry? = nil
    var shotFrameRunning = false
    var shotLastFrameNanos: Int64 = 0
    var shotMadeAtSeconds: Float? = nil
    var shotOnEnd: ((ShotResult) -> Void)? = nil

    // Small visual feedback when the ball physically touches the rim / net.
    var rimShakeStartedAtNanos: Int64 = 0
    var rimShakeAmplitudePx: Float = 0
    var netKickStartedAtNanos: Int64 = 0
    var netKickAmplitudePx: Float = 0
    var netKickDirection: Float = 1

    let ballResIds: [ADrawableRes] = [
        R.drawable.basketball,
        R.drawable.ball,
        R.drawable.minik_soccer_ball,
        R.drawable.sand_ball,
        R.drawable.volleyball,
        R.drawable.triple_shot_ball_neon_crown,
        R.drawable.triple_shot_ball_neon_bolt,
        R.drawable.triple_shot_ball_neon_splash,
        R.drawable.triple_shot_ball_neon_quiz
    ]
    var currentBallResId: ADrawableRes = R.drawable.basketball
    /// Dead on Android after the GPU migration (only ever reset to null); kept so the writes stay 1:1.
    var currentBallDrawable: ADrawable? = nil
    // HORSE uses one physical shared ball for the whole match; its skin must not change
    // when possession moves between the human and MINIK.
    var horseBallSkinLocked = false

    // V20 local 1v1 state. It intentionally reuses the existing human/bot renderers, the
    // shared single-ball ownership model and TripleShotPhysics instead of creating a parallel
    // mini-engine. Missing 1v1-specific art therefore falls back to the current shot/dribble poses.
    var oneOnOneEnabled = false
    var oneOnOneBotBlockRating = 50
    var oneOnOneHumanBlockRating = 50
    var oneOnOneBotStealRating = 50
    var oneOnOneHumanStealRating = 50
    var oneOnOneBotStrengthRating = 50
    var oneOnOneHumanStrengthRating = 50
    var oneOnOneBotSpeedRating = 50
    var oneOnOneHumanSpeedRating = 50
    var oneOnOneBotHeightRating = 50
    var oneOnOneHumanHeightRating = 50
    var oneOnOneBotBallHandlingRating = 50
    var oneOnOneHumanBallHandlingRating = 50
    var oneOnOneBotDefenseRating = 50
    var oneOnOneHumanDefenseRating = 50
    var oneOnOneBotAgilityRating = 50
    var oneOnOneHumanAgilityRating = 50
    var oneOnOneBotOffenseRating = 50
    var oneOnOneHumanOffenseRating = 50
    var oneOnOneBotWeightRating = 50
    var oneOnOneHumanWeightRating = 50
    var oneOnOneBotJumpRating = 50
    var oneOnOneHumanJumpRating = 50
    var oneOnOneBotContestActive = false
    var oneOnOneBotContestAllowed = true
    var oneOnOneHumanHeldMotionOverride: TripleShotPlayerRenderer.Motion? = nil
    var oneOnOneBotContestRecoveryUntilNanos: Int64 = 0
    var oneOnOneHumanBlockUntilNanos: Int64 = 0
    var oneOnOneHumanShotBlocked = false
    var oneOnOneBotShotBlocked = false
    var oneOnOneBotStealCooldownUntilNanos: Int64 = 0
    var oneOnOneHumanStealCooldownUntilNanos: Int64 = 0
    var oneOnOneHumanStealProtectedUntilNanos: Int64 = 0
    var oneOnOneBotStealProtectedUntilNanos: Int64 = 0

    enum OneOnOneBallState: String, KotlinEnum {
        case HUMAN
        case BOT
        case LOOSE
        /** Dead ball/out of bounds; reset to a normal check position before resuming. */
        case DEAD_HUMAN
        case DEAD_BOT
    }

    enum OneOnOneShotEscape: String, KotlinEnum {
        case FADE_AWAY
        case SIDE_LEFT
        case SIDE_RIGHT
    }

    enum OneOnOneDriveFinish: String, KotlinEnum {
        case JUMPER
        case LAYUP
        case DUNK
    }

    var oneOnOneAutomaticBallStateListener: ((OneOnOneBallState) -> Void)? = nil
    var oneOnOneBlockEventListener: ((_ humanBlocked: Bool) -> Void)? = nil

    // 1v1 visual/action state. These offsets deliberately affect only this mode.
    var oneOnOneHumanJumpStartedAtNanos: Int64 = 0
    var oneOnOneHumanJumpUntilNanos: Int64 = 0
    var oneOnOneHumanJumpHeightMultiplier: Float = 1
    var oneOnOneBotJumpStartedAtNanos: Int64 = 0
    var oneOnOneBotJumpUntilNanos: Int64 = 0
    var oneOnOneBotJumpHeightMultiplier: Float = 1
    var oneOnOneBotStealStartedAtNanos: Int64 = 0
    var oneOnOneBotStealUntilNanos: Int64 = 0
    var oneOnOneBotStealResolvePosted = false
    var oneOnOneHumanStealStartedAtNanos: Int64 = 0
    var oneOnOneHumanStealUntilNanos: Int64 = 0
    var oneOnOneHumanStealResolvePosted = false
    var oneOnOneHumanCrossoverUntilNanos: Int64 = 0
    var humanCrossAt: Int64 = 0
    var humanCrossFrom: Float = 1
    var humanSpinAt: Int64 = 0
    var botSpinAt: Int64 = 0
    var botCrossAt: Int64 = 0
    var botCrossFrom: Float = 1
    var oneOnOneBotReactionLockedUntilNanos: Int64 = 0
    var oneOnOneBotDrivingUntilNanos: Int64 = 0
    var oneOnOneBotDefenseLastUpdateNanos: Int64 = 0
    var oneOnOneLooseEventSerial: Int64 = 0
    // Keep the live finish type through rim contact so a soft layup/dunk miss can lose the
    // right amount of energy instead of inheriting a jumper's rebound speed.
    var oneOnOneHumanActiveFinish = OneOnOneDriveFinish.JUMPER
    var oneOnOneBotActiveFinish = OneOnOneDriveFinish.JUMPER

    // DUNK is a separate close-finish action, not a jump-shot projectile. Until dedicated dunk
    // art exists we temporarily render Maya with the already-authored directional BLOCK pose.
    var oneOnOneBotDunkAnimator: AValueAnimator? = nil
    var oneOnOneBotDunkActive = false
    var oneOnOneBotDunkBlocked = false
    // After the ball reaches the rim, stop holding the same dunk-contact sprite inside the net.
    // The dunk action remains active for scoring/ball depth, but Maya transitions to a clean
    // directional airborne follow-through while the released ball continues through the net.
    var oneOnOneBotDunkReleasedPose = false
    // Visual-only body alignment used by the temporary BLOCK-as-DUNK art. It lets the extended
    // hand actually arrive at the rim while gameplay coordinates stay stable and predictable.
    var oneOnOneBotDunkRenderShiftX: Float = 0
    var oneOnOneBotDunkRenderLiftPx: Float = 0
    var oneOnOneBotDunkFrameIndex = -1
    var oneOnOneBotLastDunkFrameIndex = -1
    var oneOnOneBotDunkFacing = TripleShotPlayerRenderer.Facing.BACK
    var oneOnOneBotDunkMirrorX = false
    var oneOnOneBotRecentAttackIntensity01: Float = 0.82

    // A missed/deflected 1v1 shot becomes a real loose ball instead of teleporting to the
    // other player. The loose ball uses a deliberately lightweight screen-space bounce model;
    // actual shot/rim/backboard flight still stays in TripleShotPhysics.
    var oneOnOneLooseBallActive = false
    var oneOnOneLooseBallVx: Float = 0
    var oneOnOneLooseBallVy: Float = 0
    var oneOnOneLooseBallLastFrameNanos: Int64 = 0
    var oneOnOneLooseBallAgeSeconds: Float = 0
    var oneOnOneLooseBallClaimDelaySeconds: Float = TripleShotCourtView.ONE_ON_ONE_REBOUND_CLAIM_MIN_AGE_SECONDS
    var oneOnOneLooseBallLastOwnerHuman: Bool? = nil
    var oneOnOneLooseBallGravityPxPerSec2: Float = 0
    var oneOnOneHumanLastMoveNanos: Int64 = 0

    // Defense must keep playing even when the human is completely still.
    lazy var oneOnOneDefenseHeartbeatRunnable: ARunnable = ARunnable(withSelf: { [weak self] this in
        guard let self = self else { return }
        if !oneOnOneEnabled { return }
        if !gpuWorld.isWorldReady() || !oneOnOneWorldStarted {
            postDelayed(this, Self.ONE_ON_ONE_DEFENSE_HEARTBEAT_MS)
            return
        }
        if sharedHorseBallOwner == SharedBallOwner.HUMAN &&
            !oneOnOneLooseBallActive &&
            !shotFrameRunning &&
            !shotGuidesVisible {
            updateOneOnOneBotDefensePosition(force: false)
            resolveHumanBotBodyCollision()
            maybeStartOneOnOneBotSteal()
        }
        postDelayed(this, Self.ONE_ON_ONE_DEFENSE_HEARTBEAT_MS)
    })

    lazy var physicsFrameRunnable: ARunnable = ARunnable(withSelf: { [weak self] this in
        guard let self = self else { return }
        if !shotFrameRunning || width <= 0 || height <= 0 { return }

        guard let state = physicsState else { return }
        guard let geometry = physicsGeometry else { return }

        let now = ASystem.nanoTime()
        let rawDt: Float =
            shotLastFrameNanos == 0 ? 1 / 60
            : (Double(now &- shotLastFrameNanos) / 1_000_000_000.0).toFloat()
        shotLastFrameNanos = now

        // Clamp display hiccups, then sub-step so a fast ball cannot tunnel through the rim.
        var remaining = rawDt.coerceIn(0.001, 0.045)
        while remaining > 0 {
            let step = kmin(remaining, Self.MAX_PHYSICS_SUBSTEP_SECONDS)
            let result = TripleShotPhysics.step(state: state, geometry: geometry, dtSeconds: step)
            if oneOnOneEnabled {
                dampOneOnOneShotImpact(state: state, result: result, finish: oneOnOneHumanActiveFinish)
            }
            applyOneOnOneBotBlockToHumanShot(state: state, geometry: geometry)
            let relaxedMadeNow = maybeMarkOneOnOneRelaxedMake(state: state, geometry: geometry)

            if result.rimImpactSpeed >= Self.MIN_VISIBLE_RIM_IMPACT {
                triggerRimShake(impactSpeed: result.rimImpactSpeed)
            }

            if result.netImpactSpeed >= Self.MIN_VISIBLE_NET_IMPACT {
                // A side-net graze should not look identical to a basket. Non-makes get only
                // a subtle net twitch; a real make below receives the full visual kick.
                let visualImpact: Float = state.made ? result.netImpactSpeed : result.netImpactSpeed * 0.22
                if visualImpact >= Self.MIN_VISIBLE_NET_IMPACT * 0.55 {
                    triggerNetKick(
                        impactSpeed: visualImpact,
                        directionHint: state.x - geometry.hoopCenterX
                    )
                }
            }

            if result.madeNow || relaxedMadeNow {
                shotMadeAtSeconds = state.elapsedSeconds
                triggerNetKick(
                    impactSpeed: kmax(abs(state.vy) * 0.42, Self.MIN_VISIBLE_NET_IMPACT),
                    directionHint: state.vx
                )
            }

            remaining -= step
        }

        ballX = state.x
        ballY = state.y
        captureLiveReplaySample(force: false)

        let ballRadius = geometry.ballRadius.coerceAtLeast(1)
        ballRotationDeg +=
            mathToDegrees(Double(state.vx * rawDt / ballRadius)).toFloat() * 0.22

        invalidate()

        let madeAge: Float? = shotMadeAtSeconds.map { state.elapsedSeconds - $0 }

        let madeExitedNet =
            state.made &&
            state.y >= geometry.netBottomY + geometry.ballRadius * 1.25 &&
            (madeAge ?? 0) >= Self.MIN_POST_MAKE_SECONDS

        let madeSafetyTimeout =
            state.made &&
            (madeAge ?? 0) >= Self.MAX_POST_MAKE_SECONDS

        let outside =
            state.y > height.toFloat() + geometry.ballRadius * 4 ||
            state.x < (-width).toFloat() * 0.35 ||
            state.x > width.toFloat() * 1.35

        let timedOut = state.elapsedSeconds >= Self.MAX_SHOT_SECONDS
        let oneOnOneReboundReady = oneOnOneShotReadyForLooseBall(state: state, geometry: geometry)

        if madeExitedNet || madeSafetyTimeout || outside || timedOut || oneOnOneReboundReady {
            finishPhysicsShot()
        } else {
            postOnAnimation(this)
        }
    })

    lazy var botPhysicsFrameRunnable: ARunnable = ARunnable(withSelf: { [weak self] this in
        guard let self = self else { return }
        if !botEnabled || !botShotFrameRunning || width <= 0 || height <= 0 { return }

        guard let state = botPhysicsState else { return }
        guard let geometry = botPhysicsGeometry else { return }

        let now = ASystem.nanoTime()
        let rawDt: Float =
            botShotLastFrameNanos == 0 ? 1 / 60
            : (Double(now &- botShotLastFrameNanos) / 1_000_000_000.0).toFloat()
        botShotLastFrameNanos = now

        var remaining = rawDt.coerceIn(0.001, 0.045)
        while remaining > 0 {
            let step = kmin(remaining, Self.MAX_PHYSICS_SUBSTEP_SECONDS)
            let result = TripleShotPhysics.step(state: state, geometry: geometry, dtSeconds: step)
            if oneOnOneEnabled {
                dampOneOnOneShotImpact(state: state, result: result, finish: oneOnOneBotActiveFinish)
            }
            applyOneOnOneHumanBlockToBotShot(state: state, geometry: geometry)
            let relaxedMadeNow = maybeMarkOneOnOneRelaxedMake(state: state, geometry: geometry)

            if result.rimImpactSpeed >= Self.MIN_VISIBLE_RIM_IMPACT {
                triggerRimShake(impactSpeed: result.rimImpactSpeed)
            }

            if result.netImpactSpeed >= Self.MIN_VISIBLE_NET_IMPACT {
                let visualImpact: Float = state.made ? result.netImpactSpeed : result.netImpactSpeed * 0.22
                if visualImpact >= Self.MIN_VISIBLE_NET_IMPACT * 0.55 {
                    triggerNetKick(
                        impactSpeed: visualImpact,
                        directionHint: state.x - geometry.hoopCenterX
                    )
                }
            }

            if result.madeNow || relaxedMadeNow {
                botShotMadeAtSeconds = state.elapsedSeconds
                triggerNetKick(
                    impactSpeed: kmax(abs(state.vy) * 0.42, Self.MIN_VISIBLE_NET_IMPACT),
                    directionHint: state.vx
                )
            }

            remaining -= step
        }

        botBallX = state.x
        botBallY = state.y

        let ballRadius = geometry.ballRadius.coerceAtLeast(1)
        botBallRotationDeg +=
            mathToDegrees(Double(state.vx * rawDt / ballRadius)).toFloat() * 0.22

        invalidate()

        let madeAge: Float? = botShotMadeAtSeconds.map { state.elapsedSeconds - $0 }

        let madeExitedNet =
            state.made &&
            state.y >= geometry.netBottomY + geometry.ballRadius * 1.25 &&
            (madeAge ?? 0) >= Self.MIN_POST_MAKE_SECONDS

        let madeSafetyTimeout =
            state.made &&
            (madeAge ?? 0) >= Self.MAX_POST_MAKE_SECONDS

        let outside =
            state.y > height.toFloat() + geometry.ballRadius * 4 ||
            state.x < (-width).toFloat() * 0.35 ||
            state.x > width.toFloat() * 1.35

        let timedOut = state.elapsedSeconds >= Self.MAX_SHOT_SECONDS
        let oneOnOneReboundReady = oneOnOneShotReadyForLooseBall(state: state, geometry: geometry)

        if madeExitedNet || madeSafetyTimeout || outside || timedOut || oneOnOneReboundReady {
            finishBotPhysicsShot()
        } else {
            postOnAnimation(this)
        }
    })

    lazy var oneOnOneLooseBallFrameRunnable: ARunnable = ARunnable(withSelf: { [weak self] this in
        guard let self = self else { return }
        if !oneOnOneEnabled || !oneOnOneLooseBallActive || width <= 0 || height <= 0 { return }

        let now = ASystem.nanoTime()
        let dt: Float =
            oneOnOneLooseBallLastFrameNanos == 0 ? 1 / 60
            : (Double(now &- oneOnOneLooseBallLastFrameNanos) / 1_000_000_000.0).toFloat()
                .coerceIn(0.001, 0.040)
        oneOnOneLooseBallLastFrameNanos = now
        oneOnOneLooseBallAgeSeconds += dt

        guard let loose = worldLooseBall else { return }
        loose.advance(seconds: dt)
        let logical = logicalGround(p: loose.position)
        ballX = logical.x; ballY = logical.y
        ballRotationDeg += (loose.velocity.x + loose.velocity.z) * dt * 130
        if loose.outOfBounds { resolveOneOnOneDeadBall(); return }

        // Both players race to the same live ball. Grounded pickups use foot proximity; high
        // rebounds use the raised hand during a jump. Resolve both candidates together so the
        // human does not receive hidden first-frame priority simply because their check ran first.
        updateOneOnOneBotLooseBallChase(dt: dt, now: now)
        if oneOnOneLooseBallActive {
            resolveOneOnOneLooseBallPossession(now: now)
        }

        invalidate()
        if oneOnOneLooseBallActive {
            postOnAnimation(this)
        }
    })

    lazy var liveRemoteFrameRunnable: ARunnable = ARunnable(withSelf: { [weak self] this in
        guard let self = self else { return }
        if width <= 0 || height <= 0 || liveRemotePlayers.isEmpty { return }

        let now = ASystem.nanoTime()
        var anyRunning = false

        for remote in liveRemotePlayers.values {
            guard let state = remote.physicsState else { continue }
            guard let geometry = remote.physicsGeometry else { continue }
            anyRunning = true

            let rawDt: Float =
                remote.lastFrameNanos == 0 ? 1 / 60
                : (Double(now &- remote.lastFrameNanos) / 1_000_000_000.0).toFloat()
            remote.lastFrameNanos = now

            var remaining = rawDt.coerceIn(0.001, 0.045)
            while remaining > 0 {
                let step = kmin(remaining, Self.MAX_PHYSICS_SUBSTEP_SECONDS)
                let result = TripleShotPhysics.step(state: state, geometry: geometry, dtSeconds: step)

                if result.rimImpactSpeed >= Self.MIN_VISIBLE_RIM_IMPACT {
                    triggerRimShake(impactSpeed: result.rimImpactSpeed)
                }
                if result.netImpactSpeed >= Self.MIN_VISIBLE_NET_IMPACT {
                    triggerNetKick(impactSpeed: result.netImpactSpeed, directionHint: state.x - geometry.hoopCenterX)
                }
                if result.madeNow {
                    remote.madeAtSeconds = state.elapsedSeconds
                    triggerNetKick(
                        impactSpeed: kmax(abs(state.vy) * 0.42, Self.MIN_VISIBLE_NET_IMPACT),
                        directionHint: state.vx
                    )
                }
                remaining -= step
            }

            remote.ballX = state.x
            remote.ballY = state.y
            let radius = geometry.ballRadius.coerceAtLeast(1)
            remote.ballRotationDeg +=
                mathToDegrees(Double(state.vx * rawDt / radius)).toFloat() * 0.22

            let madeAge: Float? = remote.madeAtSeconds.map { state.elapsedSeconds - $0 }
            let madeExited =
                state.made &&
                state.y >= geometry.netBottomY + geometry.ballRadius * 1.25 &&
                (madeAge ?? 0) >= Self.MIN_POST_MAKE_SECONDS
            let madeTimeout =
                state.made && (madeAge ?? 0) >= Self.MAX_POST_MAKE_SECONDS
            let outside =
                state.y > height.toFloat() + geometry.ballRadius * 4 ||
                state.x < (-width).toFloat() * 0.35 ||
                state.x > width.toFloat() * 1.35
            let timedOut = state.elapsedSeconds >= Self.MAX_SHOT_SECONDS

            if madeExited || madeTimeout || outside || timedOut {
                remote.physicsState = nil
                remote.physicsGeometry = nil
                remote.lastFrameNanos = 0
                remote.madeAtSeconds = nil
                remote.ballVisible = true
                let held = liveRemoteHeldBall(remote: remote)
                remote.ballX = held.x
                remote.ballY = held.y
            }
        }

        invalidate()
        if anyRunning && liveRemotePlayers.values.contains(where: { $0.physicsState != nil }) {
            postOnAnimation(this)
        }
    })

    // Aim-guide cache (Kotlin lines 5578-5579; used by premiumGuidePoints in part 3).
    var premiumGuides: [CourtPoint] = []
    var premiumGuidesAt: Int64 = 0

    // MARK: - Overrides of the whole Kotlin class (DESIGN 2.10)

    /// iOS/AndroidKit only: the court's onDraw builds and presents the world snapshot and draws nothing, so it
    /// runs in the Choreographer traversal with a no-op canvas (VIEW-API `drawsInTraversal`), once per vsync
    /// while `present()` keeps calling postInvalidateOnAnimation(), exactly like Android's draw pass.
    override var drawsInTraversal: Bool { true }

    /// Kotlin body at lines 5444-5490 (part 3).
    override func onSizeChanged(_ w: Int, _ h: Int, _ oldw: Int, _ oldh: Int) {
        onSizeChanged_impl(w, h, oldw, oldh)
    }

    /// Kotlin body at lines 5492-5576 (part 3).
    override func onDraw(_ canvas: ACanvas) {
        onDraw_impl(canvas)
    }

    /// Kotlin body at lines 7550-7566 (part 3; it ends with super.onDetachedFromWindow()).
    override func onDetachedFromWindow() {
        onDetachedFromWindow_impl()
    }

    // MARK: - Answer stations, transform, hit testing (Kotlin 826-1029)

    func setAnswerCount(count: Int) {
        answerCount = count.coerceIn(2, 4)
        if activeStations.count != answerCount {
            activeStations = []
        }
        clearStationSelection(animate: false)
    }

    /**
     * Chooses the A/B/C/D shooting locations for the current question.
     *
     * Shooting Challenge uses a seeded shuffle so each question can send the player to a
     * genuinely different 2D location (court, edge, low bushes). Practice uses a stable
     * beginner-friendly set so the tutorial remains easy to understand.
     */
    func prepareAnswerSpots(
        count: Int,
        seed: Int64,
        randomize: Bool
    ) {
        answerCount = count.coerceIn(2, 4)

        let random = KotlinRandom(seed: seed)
        let sourcePool = randomize ? Self.SHOT_SPOT_CATALOG : Self.PRACTICE_SPOTS
        let previous = activeStations

        /*
         * Prefer spots that were not used recently and are not almost on top of a spot
         * from the immediately previous question. Exact repeat protection is deliberately
         * stronger than the distance rule: seeing A/B/C jump back to the same trio two
         * questions later feels much less random than it mathematically is.
         */
        // compareBy<Station> { recentSpotIds.contains(it.id) }   (false before true)
        //     .thenByDescending { previous.minOfOrNull { dist2(it, old) } ?: Float.MAX_VALUE }
        // `sortedWith` is stable; the Float key compares with Float.compareTo (Java Float.compare).
        func nearestPreviousDistance(_ candidate: Station) -> Float {
            if previous.isEmpty { return Float.greatestFiniteMagnitude }
            return previous.kMinOf { old in sourceDistanceSquared(a: candidate, b: old) }
        }
        let pool = sourcePool
            .kShuffled(random)
            .stableSorted(by: { a, b in
                let recentA = recentSpotIds.contains(a.id)
                let recentB = recentSpotIds.contains(b.id)
                if recentA != recentB { return !recentA }
                return KMath.compare(nearestPreviousDistance(b), nearestPreviousDistance(a)) < 0
            })

        var chosen: [Station] = []

        func canUse(candidate: Station, strict: Bool) -> Bool {
            if chosen.contains(candidate) { return false }

            // In bot matches, never place an answer marker directly under the waiting bot.
            // This branch is inactive in solo/practice because botEnabled remains false.
            let botStation = botCurrentStation
            if botEnabled, let botStation = botStation,
               sourceDistanceSquared(a: candidate, b: botStation) < Self.BOT_ANSWER_AVOID_DISTANCE_SQ {
                return false
            }

            let farFromChosen = chosen.allSatisfy { existing in
                sourceDistanceSquared(a: candidate, b: existing) >=
                    (strict ? Self.MIN_SOURCE_SPOT_DISTANCE_SQ : Self.RELAXED_SOURCE_SPOT_DISTANCE_SQ)
            }
            if !farFromChosen { return false }

            if !randomize || !strict { return true }

            // Avoid reusing the exact same physical neighborhood from the previous question.
            let farFromPrevious = previous.allSatisfy { old in
                sourceDistanceSquared(a: candidate, b: old) >= Self.PREVIOUS_QUESTION_AVOID_DISTANCE_SQ
            }
            return farFromPrevious
        }

        // Pass 1: new + well-spaced positions.
        for candidate in pool {
            if chosen.count < answerCount &&
                !recentSpotIds.contains(candidate.id) &&
                canUse(candidate: candidate, strict: true) {
                chosen.append(candidate)
            }
        }

        // Pass 2: keep spatial diversity, but allow a recent spot if necessary.
        for candidate in pool {
            if chosen.count < answerCount && canUse(candidate: candidate, strict: true) {
                chosen.append(candidate)
            }
        }

        // Pass 3: relax only the spacing requirement. This should be rare with the larger catalog.
        for candidate in pool {
            if chosen.count < answerCount && canUse(candidate: candidate, strict: false) {
                chosen.append(candidate)
            }
        }

        activeStations =
            randomize ? chosen.kShuffled(KotlinRandom(seed: seed ^ 0x5A17C3))
            : chosen

        if randomize {
            for station in activeStations {
                if let index = recentSpotIds.firstIndex(of: station.id) {
                    recentSpotIds.remove(at: index)
                }
                recentSpotIds.append(station.id)
            }
            while recentSpotIds.count > Self.RECENT_SPOT_MEMORY {
                recentSpotIds.remove(at: 0)
            }
        }

        selectedStation = -1
        clearStationSelection(animate: false)
        invalidate()
    }

    func sourceDistanceSquared(a: Station, b: Station) -> Float {
        let dx = a.sourceX - b.sourceX
        let dy = a.sourceY - b.sourceY
        return dx * dx + dy * dy
    }

    /// Positional form for the part-2/3 call sites written as `sourceDistanceSquared(candidate, avoid)`.
    func sourceDistanceSquared(_ a: Station, _ b: Station) -> Float {
        return sourceDistanceSquared(a: a, b: b)
    }

    /**
     * Keeps the player feet and station markers above the live UI.
     *
     * The coordinate is in this view's coordinate system. CourtView fills the same
     * root as the answerStrip, so the Fragment can pass answerStrip.top directly.
     */
    func setGameplayBottomBoundary(boundaryY: Float) {
        gameplayBottomBoundaryPx = boundaryY > 0 ? boundaryY : nil

        if selectedStation >= 0 {
            let p = stationScreenPoint(index: selectedStation, count: answerCount)
            setPlayerPosition(x: p.x, y: p.y, animate: false)
        } else if hasInitialPlayerPosition {
            let p = defaultPlayerScreenPoint()
            setPlayerPosition(x: p.x, y: p.y, animate: false)
        }

        if botEnabled {
            if let station = botCurrentStation {
                let p = botStationScreenPoint(station: station)
                setBotPosition(x: p.x, y: p.y, animate: false)
            }
        }

        invalidate()
    }

    /**
     * Applies the exact same transform used by the court physics to the background ImageView.
     *
     * V7 uses a very small horizontal squeeze (8%) plus a right-biased crop. On tall phones
     * this reveals noticeably more of the original court and more of the backboard/hoop,
     * while keeping every physics coordinate aligned with the picture.
     *
     * There is no "move the physics by hand" here: both renderer and photo use one transform.
     * (Production effect: the 2D background is hidden; the GPU draws the court.)
     */
    func applyBackgroundTransformTo(imageView: AImageView) {
        imageView.visibility = AView.INVISIBLE
        if width <= 0 || height <= 0 { return }

        guard let drawable = imageView.drawable else { return }
        let intrinsicWidth = drawable.intrinsicWidth
        let drawableWidth: Float =
            intrinsicWidth > 0 ? intrinsicWidth.toFloat() : Self.BACKGROUND_WIDTH
        let intrinsicHeight = drawable.intrinsicHeight
        let drawableHeight: Float =
            intrinsicHeight > 0 ? intrinsicHeight.toFloat() : Self.BACKGROUND_HEIGHT

        let t = backgroundTransform()

        let matrix = AMatrix()
        matrix.setScale(
            t.scaleX * Self.BACKGROUND_WIDTH / drawableWidth,
            t.scaleY * Self.BACKGROUND_HEIGHT / drawableHeight
        )
        matrix.postTranslate(t.offsetX, t.offsetY)

        imageView.scaleType = AImageView.ScaleType.MATRIX
        imageView.imageMatrix = matrix
    }

    /**
     * Returns the logical A/B/C/D index when the user taps a court marker.
     * The generous hit radius is intentional: the drawn dot can stay small while
     * still being easy to select with a thumb.
     */
    func findStationAt(x: Float, y: Float) -> Int? {
        if !answerMarkersVisible { return nil }

        for logicalIndex in kuntil(0, answerCount) {
            let point = stationScreenPoint(index: logicalIndex, count: answerCount)
            let t = backgroundTransform()
            guard let projected = gpuWorld.project(
                p: TripleShotWorldCoordinates.solo(
                    sourceX: (point.x - t.offsetX) / t.scaleX,
                    sourceY: (point.y - t.offsetY) / t.scaleY,
                    lift: 0.03
                )
            ) else { continue }
            let dx = x - projected.first
            let dy = y - projected.second
            let radius = dp(v: 36)
            if dx * dx + dy * dy <= radius * radius {
                return logicalIndex
            }
        }
        return nil
    }

    // MARK: - HORSE (Kotlin 1031-1659)

    /**
     * HORSE location picker. While visible, small legal-ground targets are drawn over the
     * artwork. A tap anywhere on the ground snaps to the closest curated legal point.
     */
    func setHorseSpotPickerVisible(visible: Bool) {
        horseSpotPickerVisible = visible
        horseFreeMoveEnabled = false
        answerMarkersVisible = !visible
        if !visible {
            horseSelectedSpotId = nil
        }
        removeCallbacks(horseFreeMoveSettleRunnable)
        dribbleBouncePx = 0
        invalidate()
    }

    func findHorseSpotAt(x: Float, y: Float) -> String? {
        if !horseSpotPickerVisible || width <= 0 || height <= 0 { return nil }

        return Self.HORSE_SELECTABLE_SPOTS.kMinBy { (station: Station) -> Float in
            let point = gpuWorld.project(
                p: TripleShotWorldCoordinates.solo(sourceX: station.sourceX, sourceY: station.sourceY)
            )
            let dx = x - (point?.first ?? x)
            let dy = y - (point?.second ?? y)
            return dx * dx + dy * dy
        }?.id
    }

    /**
     * Free HORSE positioning for the human setter. The feet may move anywhere in the
     * lower playable part of the visible court, including bushes and painted areas.
     * The side corridors reach higher than the center so the player can attempt strange
     * behind-the-hoop shots without ever walking into the tree canopy. Locking the spot
     * converts it back to the
     * source artwork coordinates used by physics and by MINIK's later response.
     */
    func setHorseFreeMoveEnabled(enabled: Bool) {
        horseFreeMoveEnabled = enabled
        humanWalking = false
        if enabled {
            humanWaitingForTurn = false
            if botEnabled { giveSharedHorseBallToHuman() }
        } else {
            cancelHumanIdleDribble()
        }
        horseSpotPickerVisible = false
        answerMarkersVisible = false
        selectedStation = -1
        shotGuidesVisible = false
        horseSelectedSpotId = nil

        removeCallbacks(horseFreeMoveSettleRunnable)
        dribbleBouncePx = 0

        if enabled {
            horseHumanStation = nil
            clampHumanToHorseFreeBounds()
            scheduleHumanIdleDribble()
        }

        invalidate()
    }

    func moveHorseHumanByTouch(dx: Float, dy: Float) {
        if !horseFreeMoveEnabled || width <= 0 || height <= 0 { return }
        moveHumanFreeBy(dx: dx, dy: dy)
    }

    /**
     * Tap-to-walk for HORSE. A tap does not lock the challenge spot; it only walks the
     * setter there. The ready button remains the explicit confirmation, which prevents
     * accidental spot selection while exploring the court.
     * (Quirk kept, spec 08 section 8.1: the raw screen tap is used as a legacy view-space point.)
     */
    func moveHorseHumanTo(x: Float, y: Float) {
        if !horseFreeMoveEnabled || width <= 0 || height <= 0 { return }

        playerMoveAnimator?.cancel()
        removeCallbacks(horseFreeMoveSettleRunnable)
        cancelHumanIdleDribble()

        guard let target = gpuWorld.screenGround(x: x, y: y).map({ logicalGround(p: $0) }) else { return }
        let targetX = target.x.coerceIn(horseFreeMinX(), horseFreeMaxX())
        let targetY = clampHorseFreeY(x: targetX, y: target.y)
        let startX = playerX
        let startY = playerFootY
        let distance = ksqrt(
            (targetX - startX) * (targetX - startX) +
                (targetY - startY) * (targetY - startY)
        )

        if distance < dp(v: 2) {
            humanWalking = false
            playerX = targetX
            playerFootY = targetY
            dribbleBouncePx = 0
            invalidate()
            return
        }

        let durationMs = walkingDuration(x: startX, y: startY, tx: targetX, ty: targetY)

        beginHumanMovementDribble()
        let animator = AValueAnimator.ofFloat(0, 1)
        animator.duration = durationMs
        animator.interpolator = ALinearInterpolator()

        animator.addUpdateListener { [weak self] animator in
            guard let self = self else { return }
            let fraction = animator.animatedValueFloat
            let nextX = lerp(a: startX, b: targetX, t: fraction)
            let rawY = lerp(a: startY, b: targetY, t: fraction)

            let oldFrameX = playerX
            let oldFrameY = playerFootY
            playerX = nextX.coerceIn(horseFreeMinX(), horseFreeMaxX())
            playerFootY = clampHorseFreeY(x: playerX, y: rawY)

            let frameDx = playerX - oldFrameX
            let frameDy = playerFootY - oldFrameY
            updateHumanMovementSpeed(distancePx: ksqrt(frameDx * frameDx + frameDy * frameDy))

            let bounceCycles = fraction * Self.DRIBBLE_BOUNCES_DURING_MOVE.toFloat()
            let bounceIndex =
                bounceCycles.rounded(.down)
                    .toInt()
                    .coerceAtMost(Self.DRIBBLE_BOUNCES_DURING_MOVE.toInt() - 1)
            updateMovingDribbleBounceIndex(newIndex: bounceIndex)
            humanDribblePhase01 =
                (bounceCycles - bounceCycles.rounded(.down)).coerceIn(0, 1)
            dribbleBouncePx =
                abs(sin(Double(fraction) * Double.pi * Self.DRIBBLE_BOUNCES_DURING_MOVE)).toFloat() *
                dp(v: Self.DRIBBLE_BOUNCE_AMPLITUDE_DP)
            if humanOwnsVisibleBall() {
                ballRotationDeg = (fraction * 720).truncatingRemainder(dividingBy: 360)
            }
            invalidate()
        }

        animator.addListener(AAnimatorListenerAdapter(
            onEnd: { [weak self] _ in
                guard let self = self else { return }
                humanWalking = false
                dribbleBouncePx = 0
                humanDribblePhase01 = 0
                humanDribbleHandSign = humanWalkingDribbleHandSign
                resetHumanMovementSpeed()
                clampHumanToHorseFreeBounds()
                scheduleHumanIdleDribble()
                invalidate()
            },
            onCancel: { [weak self] _ in
                guard let self = self else { return }
                humanWalking = false
                dribbleBouncePx = 0
                humanDribblePhase01 = 0
                resetHumanMovementSpeed()
                invalidate()
            }
        ))

        animator.start()
        playerMoveAnimator = animator
    }

    func moveHorseHumanByDevice(horizontal: Float, vertical: Float) {
        if !horseFreeMoveEnabled || width <= 0 || height <= 0 { return }

        let x = horizontal.coerceIn(-1, 1)
        let y = vertical.coerceIn(-1, 1)
        if abs(x) < 0.01 && abs(y) < 0.01 { return }

        moveHumanFreeBy(
            dx: x * dp(v: Self.HORSE_DEVICE_MOVE_STEP_DP),
            dy: y * dp(v: Self.HORSE_DEVICE_MOVE_STEP_DP)
        )
    }

    /** Freezes the current feet position as the exact challenge spot. */
    @discardableResult
    func lockCurrentHorseFreeSpot() -> String? {
        if !horseFreeMoveEnabled || width <= 0 || height <= 0 { return nil }

        clampHumanToHorseFreeBounds()
        let t = backgroundTransform()
        if t.scaleX <= 0 || t.scaleY <= 0 { return nil }

        let sourceX =
            ((playerX - t.offsetX) / t.scaleX)
                .coerceIn(0, Self.BACKGROUND_WIDTH)
        let sourceY =
            ((playerFootY - t.offsetY) / t.scaleY)
                .coerceIn(0, Self.BACKGROUND_HEIGHT)

        let dx = sourceX - Self.SRC_HOOP_CENTER_X
        let dy = sourceY - Self.SRC_HOOP_PLANE_Y
        let distance = ksqrt(dx * dx + dy * dy)
        let difficulty =
            ((distance - 330) / 720)
                .coerceIn(0.18, 0.95)

        horseCustomSpotCounter += 1
        let id = "FREE_\(horseCustomSpotCounter)"
        let station = Station(
            id: id,
            sourceX: sourceX,
            sourceY: sourceY,
            distanceDifficulty: difficulty,
            zone: "horse_free"
        )

        horseCustomSpots[id] = station
        horseHumanStation = station
        horseSelectedSpotId = id
        horseFreeMoveEnabled = false
        removeCallbacks(horseFreeMoveSettleRunnable)
        dribbleBouncePx = 0
        invalidate()
        return id
    }

    /** Moves MINIK away before the human starts walking around to choose a challenge. */
    func moveBotToOpenWaitingSpot(
        seed: Int64,
        animate: Bool = true,
        onEnd: (() -> Void)? = nil
    ) {
        if !botEnabled {
            onEnd?()
            return
        }

        let station = chooseBotStation(seed: seed)
        botCurrentStation = station
        let point = botStationScreenPoint(station: station)
        setBotPosition(x: point.x, y: point.y, animate: animate, onEnd: onEnd)
    }

    func worldGround(x: Float, y: Float) -> CourtPoint {
        let t = backgroundTransform()
        return TripleShotWorldCoordinates.solo(sourceX: (x - t.offsetX) / t.scaleX, sourceY: (y - t.offsetY) / t.scaleY)
    }

    func logicalGround(p: CourtPoint) -> APointF {
        let t = backgroundTransform()
        return APointF((p.x / Float(0.014) + 512) * t.scaleX + t.offsetX, (p.z / Float(0.017) + 948) * t.scaleY + t.offsetY)
    }

    func worldHoop() -> CourtPoint {
        TripleShotWorldCoordinates.solo(sourceX: Self.SRC_HOOP_CENTER_X, sourceY: Self.SRC_HOOP_DEPTH_FOOT_Y,
                                        lift: TripleShotWorldCoordinates.RIM_HEIGHT)
    }

    func worldVerticalScale() -> Float { Float(3.35) / (Float(608) * backgroundTransform().scaleY) }

    func releaseSocket(human: Bool, motion: TripleShotPlayerRenderer.Motion? = nil) -> CourtPoint {
        let raw = human ? humanRendererState() : botRendererState()
        var state = raw
        if let motion = motion { state.motion = motion }
        let foot = human ? playerFootY : botFootY
        let ground = worldGround(x: state.x, y: foot)
        var lifted = ground
        lifted.y = (foot - state.footY) / density * Float(0.012)
        let actor = TripleShotWorldActor(id: human ? "human" : "bot", position: lifted, state: state)
        return gpuWorld.actorSocket(actor: actor, inFront: state.facing != TripleShotPlayerRenderer.Facing.BACK)
    }

    func limitedGroundMove(x: Float, y: Float, tx: Float, ty: Float, limit: Float) -> APointF {
        let from = worldGround(x: x, y: y); let to = worldGround(x: tx, y: ty)
        let distance = khypot(to.x - from.x, to.z - from.z)
        let fraction: Float = distance > limit && distance > 0 ? limit / distance : 1
        return APointF(x + (tx - x) * fraction, y + (ty - y) * fraction)
    }

    func walkingDuration(x: Float, y: Float, tx: Float, ty: Float) -> Int64 {
        let from = worldGround(x: x, y: y); let to = worldGround(x: tx, y: ty)
        return (khypot(to.x - from.x, to.z - from.z) / Float(4.3) * Float(1000)).toLong().coerceAtLeast(120)
    }

    /// GPU-aware drag (spec 08 section 7.5). No guard: the callers guard.
    func moveHumanFreeBy(dx: Float, dy: Float) {
        if oneOnOneEnabled && ASystem.nanoTime() < humanRecoveryUntil { return }
        playerMoveAnimator?.cancel()
        cancelHumanIdleDribble()

        let oldX = playerX
        let oldY = playerFootY
        let t = backgroundTransform()
        let foot = gpuWorld.project(
            p: TripleShotWorldCoordinates.solo(
                sourceX: (playerX - t.offsetX) / t.scaleX,
                sourceY: (playerFootY - t.offsetY) / t.scaleY
            )
        )
        let from = foot.flatMap { gpuWorld.screenGround(x: $0.first, y: $0.second) }
        let to = foot.flatMap { gpuWorld.screenGround(x: $0.first + dx, y: $0.second + dy) }
        let logicalDx: Float
        let logicalDy: Float
        if let from = from, let to = to {
            logicalDx = (to.x - from.x) / 0.014 * t.scaleX
        } else {
            logicalDx = dx
        }
        if let from = from, let to = to {
            logicalDy = (to.z - from.z) / 0.017 * t.scaleY
        } else {
            logicalDy = dy
        }
        let now = ASystem.nanoTime()
        let dt: Float = freeMoveLastNanos == 0 ? Float(1) / Float(60)
            : ((now &- freeMoveLastNanos).toFloat() / Float(1_000_000_000)).coerceIn(0, 0.045)
        freeMoveLastNanos = now
        let tx = (playerX + logicalDx).coerceIn(horseFreeMinX(), horseFreeMaxX())
        let ty = clampHorseFreeY(x: tx, y: playerFootY + logicalDy)
        let bounded = limitedGroundMove(x: playerX, y: playerFootY, tx: tx, ty: ty,
                                        limit: (Float(3.5) + oneOnOneHumanSpeedRating.toFloat() * Float(0.018)) * dt)
        playerX = bounded.x; playerFootY = bounded.y

        let movedX = playerX - oldX
        let movedY = playerFootY - oldY
        let distance = ksqrt(movedX * movedX + movedY * movedY)
        if distance > 0.1 {
            if abs(movedX) > dp(v: 0.35) {
                humanMovementHorizontalSign = movedX < 0 ? -1 : 1
            }
            if !humanWalking {
                beginHumanMovementDribble()
                humanWalkingBounceIndex = horseFreeMovePhase.rounded(.down).toInt()
            }
            updateHumanMovementSpeed(distancePx: distance)
            if oneOnOneEnabled &&
                humanMovingFast &&
                abs(movedX) > abs(movedY) * 0.42 &&
                abs(movedX) > dp(v: 0.6) {
                // At speed, keep the live ball on the movement-side hand instead of visually
                // running left while the dribble keeps bouncing on the right.
                humanWalkingDribbleHandSign = humanMovementHorizontalSign
                humanDribbleHandSign = humanMovementHorizontalSign
            }

            let dribbleTravelDp: Float = oneOnOneEnabled ? 30 : 22
            horseFreeMovePhase += distance / dp(v: dribbleTravelDp).coerceAtLeast(1)
            let bounceIndex = horseFreeMovePhase.rounded(.down).toInt()
            updateMovingDribbleBounceIndex(newIndex: bounceIndex)

            humanDribblePhase01 =
                (horseFreeMovePhase - horseFreeMovePhase.rounded(.down))
                    .coerceIn(0, 1)
            dribbleBouncePx =
                abs(sin(Double(horseFreeMovePhase) * Double.pi)).toFloat() *
                dp(v: Self.DRIBBLE_BOUNCE_AMPLITUDE_DP)
            if humanOwnsVisibleBall() {
                ballRotationDeg = (horseFreeMovePhase * 145).truncatingRemainder(dividingBy: 360)
            }

            removeCallbacks(horseFreeMoveSettleRunnable)
            postDelayed(horseFreeMoveSettleRunnable, 105)
        }

        invalidate()
    }

    func clampHumanToHorseFreeBounds() {
        if width <= 0 || height <= 0 { return }
        playerX = playerX.coerceIn(horseFreeMinX(), horseFreeMaxX())
        playerFootY = clampHorseFreeY(x: playerX, y: playerFootY)
    }

    func horseFreeMinX() -> Float {
        return oneOnOneEnabled ? logicalGround(p: CourtPoint(x: worldHoop().x - Float(7.8), y: 0, z: 0)).x : dp(v: 24)
    }
    func horseFreeMaxX() -> Float {
        return oneOnOneEnabled ? logicalGround(p: CourtPoint(x: worldHoop().x + Float(7.8), y: 0, z: 0)).x
            : kmax(horseFreeMinX() + 1, width.toFloat() - dp(v: 24))
    }

    /**
     * The middle of the artwork has water/forest that reads as airborne when the feet go
     * too high, so it is limited to the lower 50%. The outer 10% on the left and 20% on
     * the hoop side can reach a little higher than center without floating into the trees.
     * Narrow transition bands make crossing those boundaries feel like walking over terrain
     * instead of teleporting vertically.
     * (The code constant 0.46 is what Android uses, whatever the comment says; spec 08 section 7.6.)
     */
    func horseFreeMinYForX(x: Float) -> Float {
        // The old painted-court bounds stopped both players short of real 3D rebounds.
        if oneOnOneEnabled { return logicalGround(p: CourtPoint(x: 0, y: 0, z: worldHoop().z - Float(1.8))).y }
        if width <= 0 || height <= 0 { return 0 }

        let ratio = (x / width.toFloat()).coerceIn(0, 1)
        let topFraction: Float
        if ratio <= Self.HORSE_LEFT_HIGH_ZONE_END {
            topFraction = Self.HORSE_SIDE_TOP_FRACTION
        } else if ratio < Self.HORSE_LEFT_TRANSITION_END {
            let t =
                (ratio - Self.HORSE_LEFT_HIGH_ZONE_END) /
                (Self.HORSE_LEFT_TRANSITION_END - Self.HORSE_LEFT_HIGH_ZONE_END)
            topFraction = lerp(a: Self.HORSE_SIDE_TOP_FRACTION, b: Self.HORSE_CENTER_TOP_FRACTION, t: t)
        } else if ratio <= Self.HORSE_RIGHT_TRANSITION_START {
            topFraction = Self.HORSE_CENTER_TOP_FRACTION
        } else if ratio < Self.HORSE_RIGHT_HIGH_ZONE_START {
            let t =
                (ratio - Self.HORSE_RIGHT_TRANSITION_START) /
                (Self.HORSE_RIGHT_HIGH_ZONE_START - Self.HORSE_RIGHT_TRANSITION_START)
            topFraction = lerp(a: Self.HORSE_CENTER_TOP_FRACTION, b: Self.HORSE_SIDE_TOP_FRACTION, t: t)
        } else {
            topFraction = Self.HORSE_SIDE_TOP_FRACTION
        }

        return height.toFloat() * topFraction
    }

    /// Positional form of `horseFreeMinYForX(x)`.
    func horseFreeMinYForX(_ x: Float) -> Float {
        return horseFreeMinYForX(x: x)
    }

    func clampHorseFreeY(x: Float, y: Float) -> Float {
        let minY = horseFreeMinYForX(x: x)
        return y.coerceIn(minY, horseFreeMaxY(minY: minY))
    }

    /// Positional form for the part-2/3 call sites written as `clampHorseFreeY(botX, botFootY)`.
    func clampHorseFreeY(_ x: Float, _ y: Float) -> Float {
        return clampHorseFreeY(x: x, y: y)
    }

    /// Kotlin default `minY = height * HORSE_CENTER_TOP_FRACTION` (a Swift default cannot read `height`, so nil
    /// stands for "not passed").
    func horseFreeMaxY(minY: Float? = nil) -> Float {
        let minY = minY ?? height.toFloat() * Self.HORSE_CENTER_TOP_FRACTION
        return oneOnOneEnabled ? logicalGround(p: CourtPoint(x: 0, y: 0, z: 11.8)).y : kmax(minY + 1, height.toFloat() - dp(v: 24))
    }

    func randomHorseSpotIdForBot(seed: Int64) -> String {
        let random = KotlinRandom(seed: seed ^ Self.HORSE_SPOT_SEED_SALT)
        let candidates = Self.BOT_SPOT_CATALOG.kShuffled(random)
        let chosen = candidates.first(where: { !recentBotSpotIds.contains($0.id) })
            ?? candidates.first!
        rememberBotSpot(id: chosen.id)
        return chosen.id
    }

    /**
     * Used only to decide whether the non-shooter really needs to clear a newly chosen
     * HORSE location. Source-artwork coordinates keep the decision stable on every device.
     */
    func isHumanNearHorseSpot(spotId: String, radiusSourcePx: Float = 175) -> Bool {
        guard let station = horseStationById(id: spotId) else { return false }
        let source = currentPlayerSourcePosition()
        let dx = source.x - station.sourceX
        let dy = source.y - station.sourceY
        return dx * dx + dy * dy <= radiusSourcePx * radiusSourcePx
    }

    func moveHumanToHorseSpot(
        spotId: String,
        animate: Bool = true,
        onEnd: (() -> Void)? = nil
    ) {
        humanWaitingForTurn = false
        if botEnabled { giveSharedHorseBallToHuman() }
        guard let station = horseStationById(id: spotId) else {
            onEnd?()
            return
        }

        horseHumanStation = station
        horseSelectedSpotId = spotId
        selectedStation = -1
        answerMarkersVisible = false
        horseSpotPickerVisible = false
        horseFreeMoveEnabled = false
        removeCallbacks(horseFreeMoveSettleRunnable)
        dribbleBouncePx = 0

        let point = botStationScreenPoint(station: station)
        setPlayerPosition(x: point.x, y: point.y, animate: animate, onEnd: onEnd)
        invalidate()
    }

    func moveBotToHorseSpot(
        spotId: String,
        animate: Bool = true,
        onEnd: (() -> Void)? = nil
    ) {
        if !botEnabled {
            onEnd?()
            return
        }

        // The shooter owns the shared HORSE ball. This also lets a new bot setter walk
        // directly to its chosen spot without first forcing the human to a random wait spot.
        humanWaitingForTurn = true
        giveSharedHorseBallToBot()

        guard let station = horseStationById(id: spotId) else {
            onEnd?()
            return
        }

        botCurrentStation = station
        let point = botStationScreenPoint(station: station)
        setBotPosition(x: point.x, y: point.y, animate: animate, onEnd: onEnd)
    }

    func moveHumanToHorseWaitingSpot(
        avoidSpotId: String,
        seed: Int64,
        animate: Bool = true,
        onEnd: (() -> Void)? = nil
    ) {
        humanWaitingForTurn = true
        if botEnabled { giveSharedHorseBallToBot() }
        let station = chooseHorseWaitingStation(avoidSpotId: avoidSpotId, seed: seed, preferLeft: true)
        horseHumanStation = station
        selectedStation = -1
        shotGuidesVisible = false
        let point = botStationScreenPoint(station: station)
        setPlayerPosition(x: point.x, y: point.y, animate: animate, onEnd: onEnd)
        invalidate()
    }

    func moveBotToHorseWaitingSpot(
        avoidSpotId: String,
        seed: Int64,
        animate: Bool = true,
        onEnd: (() -> Void)? = nil
    ) {
        if !botEnabled {
            onEnd?()
            return
        }

        let station = chooseHorseWaitingStation(avoidSpotId: avoidSpotId, seed: seed, preferLeft: false)
        botCurrentStation = station
        let point = botStationScreenPoint(station: station)
        setBotPosition(x: point.x, y: point.y, animate: animate, onEnd: onEnd)
    }

    func setHorseAnswerMode() {
        /*
         * Answer/topic UI must NOT destroy local HORSE possession.
         *
         * In local HUMAN-vs-MINIK HORSE (botEnabled == true), keep exactly ONE owner visible.
         * If ownership has not been established yet, infer it from the currently visible ball;
         * when an old state accidentally has both visible, prefer MINIK until the normal
         * setHorseFreeMoveEnabled()/moveHumanToHorseSpot() handoff explicitly gives it to the
         * human setter. This preserves continuity without re-introducing duplicate balls.
         *
         * Live HORSE has no local MINIK actor and uses remote-player possession separately, so
         * its neutral answer mode keeps the old hide-local-ball behaviour.
         */
        cancelHumanIdleDribble()

        if botEnabled {
            let owner: SharedBallOwner
            if let existing = sharedHorseBallOwner {
                owner = existing
            } else if ballVisible && !botBallVisible {
                owner = SharedBallOwner.HUMAN
            } else if botBallVisible && !ballVisible {
                owner = SharedBallOwner.BOT
            } else if botBallVisible {
                owner = SharedBallOwner.BOT
            } else {
                owner = SharedBallOwner.HUMAN
            }

            sharedHorseBallOwner = owner
            ballVisible = owner == SharedBallOwner.HUMAN
            botBallVisible = owner == SharedBallOwner.BOT
        } else {
            sharedHorseBallOwner = nil
            ballVisible = false
            botBallVisible = false
        }

        if !horseBallSkinLocked {
            // IntArray.random() uses the unseeded Random.Default.
            currentBallResId = ballResIds.kRandom(KotlinRandom.Default)
            currentBallDrawable = nil
            horseBallSkinLocked = true
        }
        horseSpotPickerVisible = false
        horseFreeMoveEnabled = false
        answerMarkersVisible = false
        selectedStation = -1
        removeCallbacks(horseFreeMoveSettleRunnable)
        dribbleBouncePx = 0
        invalidate()
    }

    func clearHorseModeVisuals() {
        horseBallSkinLocked = false
        humanWaitingForTurn = false
        cancelHumanIdleDribble()
        sharedHorseBallOwner = botEnabled ? SharedBallOwner.HUMAN : nil
        if botEnabled {
            ballVisible = true
            botBallVisible = false
        }
        horseSpotPickerVisible = false
        horseFreeMoveEnabled = false
        horseHumanStation = nil
        horseSelectedSpotId = nil
        horseCustomSpots.clear()
        horseCustomSpotCounter = 0
        answerMarkersVisible = true
        selectedStation = -1
        shotGuidesVisible = false
        removeCallbacks(horseFreeMoveSettleRunnable)
        dribbleBouncePx = 0
        clearMatchCelebration()
        invalidate()
    }

    /**
     * Starts the local HORSE end pose. The loser sits; the winner jumps with both hands up.
     * Colored moving spotlights are intentionally reserved for a human victory.
     * (Kotlin places this KDoc above the basket-celebration fields below; it documents startHorseMatchCelebration.)
     */
    func celebrateHorseBasket(human: Bool, dance: Bool) {
        basketCelebrationAt = ASystemClock.uptimeMillis(); basketCelebrationHuman = human; basketCelebrationDance = dance
        invalidate()
    }

    func basketCelebration(raw: TripleShotPlayerRenderer.State, human: Bool) -> TripleShotPlayerRenderer.State {
        let elapsed = ASystemClock.uptimeMillis() &- basketCelebrationAt
        if oneOnOneEnabled || basketCelebrationAt == 0 || !(elapsed >= 0 && elapsed <= 1400) || human != basketCelebrationHuman ||
            raw.pose != TripleShotPlayerRenderer.Pose.NORMAL { return raw }
        let t = elapsed.toFloat() / Float(1400)
        let hop = abs(ksin(t * PI_F * (basketCelebrationDance ? 3 : 1).toFloat()))
        let sway: Float = basketCelebrationDance ? ksin(t * PI_F * 4) * dp(v: 9) : 0
        postInvalidateOnAnimation()
        var state = raw
        state.x = raw.x + sway
        state.footY = raw.footY - dp(v: basketCelebrationDance ? 19 : 44) * hop
        state.pose = TripleShotPlayerRenderer.Pose.WINNER
        state.celebrationProgress = t
        return state
    }

    func startHorseMatchCelebration(humanWon: Bool) {
        matchCelebrationAnimator?.cancel()
        playerMoveAnimator?.cancel()
        botMoveAnimator?.cancel()

        humanEndPose = humanWon ? TripleShotPlayerRenderer.Pose.WINNER : TripleShotPlayerRenderer.Pose.LOSER
        botEndPose = humanWon ? TripleShotPlayerRenderer.Pose.LOSER : TripleShotPlayerRenderer.Pose.WINNER

        humanVictorySpotlights = humanWon
        matchCelebrationProgress = 0
        humanWalking = false
        humanWaitingForTurn = false
        dribbleBouncePx = 0
        botDribbleBouncePx = 0
        ballVisible = false
        botBallVisible = false
        shotGuidesVisible = false
        answerMarkersVisible = false

        let animator = AValueAnimator.ofFloat(0, 1)
        animator.duration = Self.MATCH_CELEBRATION_DURATION_MS
        animator.interpolator = ALinearInterpolator()
        animator.addUpdateListener { [weak self] animator in
            guard let self = self else { return }
            matchCelebrationProgress = animator.animatedValueFloat
            invalidate()
        }
        animator.start()
        matchCelebrationAnimator = animator
        invalidate()
    }

    /**
     * Live HORSE finish animation. Poses themselves come from [applyLiveHorseState];
     * this method only drives the jump phase and optional local-winner spotlights.
     */
    func startLiveHorseCelebration(humanWon: Bool) {
        matchCelebrationAnimator?.cancel()
        playerMoveAnimator?.cancel()

        humanVictorySpotlights = humanWon
        matchCelebrationProgress = 0
        humanWalking = false
        humanWaitingForTurn = false
        dribbleBouncePx = 0
        ballVisible = false
        shotGuidesVisible = false
        answerMarkersVisible = false

        for remote in liveRemotePlayers.values {
            remote.moveAnimator?.cancel()
            remote.dribbleBouncePx = 0
            remote.ballVisible = false
        }

        let animator = AValueAnimator.ofFloat(0, 1)
        animator.duration = Self.MATCH_CELEBRATION_DURATION_MS
        animator.interpolator = ALinearInterpolator()
        animator.addUpdateListener { [weak self] animator in
            guard let self = self else { return }
            matchCelebrationProgress = animator.animatedValueFloat
            invalidate()
        }
        animator.start()
        matchCelebrationAnimator = animator
        invalidate()
    }

    func clearMatchCelebration() {
        matchCelebrationAnimator?.cancel()
        matchCelebrationAnimator = nil
        matchCelebrationProgress = 0
        humanVictorySpotlights = false
        humanEndPose = TripleShotPlayerRenderer.Pose.NORMAL
        botEndPose = TripleShotPlayerRenderer.Pose.NORMAL
        ballVisible = sharedHorseBallOwner != SharedBallOwner.BOT
        botBallVisible =
            botEnabled && sharedHorseBallOwner != SharedBallOwner.HUMAN
        invalidate()
    }

    func randomizeBallSkin() {
        // Solo / challenge may still get a fresh cosmetic ball per question. HORSE keeps
        // one shared ball skin for the entire match, even when possession changes.
        if horseBallSkinLocked { return }
        currentBallResId = ballResIds.kRandom(KotlinRandom.Default)
        currentBallDrawable = nil
        invalidate()
    }

    // MARK: - Aim, guide and cosmetic setters (Kotlin 1661-1741)

    func clearStationSelection(animate: Bool = true) {
        humanWaitingForTurn = false
        selectedStation = -1
        let defaultPoint = defaultPlayerScreenPoint()
        setPlayerPosition(x: defaultPoint.x, y: defaultPoint.y, animate: animate)
        fineAim = 0
        pullBack = 0
        shotGuidesVisible = false
        invalidate()
    }

    func setFineAim(normalized: Float) {
        fineAim = normalized.coerceIn(-1.30, 1.30)
        invalidate()
    }

    func setPullBack(normalized: Float) {
        pullBack = normalized.coerceIn(0, 1.20)
        if oneOnOneEnabled && pullBack >= Self.ONE_ON_ONE_CONTEST_TRIGGER_PULL {
            maybeStartOneOnOneBotContest()
        }
        invalidate()
    }

    func setShotGuidesVisible(visible: Bool) {

        shotGuidesVisible = visible
        if visible {
            cancelHumanIdleDribble()
        } else {
            scheduleHumanIdleDribble()
        }
        invalidate()
    }

    /**
     * Sets the player's learned guide level. Hard court locations can temporarily add
     * extra difficulty on top of this base level, but never alter the actual physics.
     */
    func setAimAssistLevel(level: Int) {
        aimAssistBaseLevel = level.coerceIn(0, Self.AIM_ASSIST_MAX_LEVEL)
        invalidate()
    }

    func setHotHand(active: Bool) {
        hotHand = active
        invalidate()
    }

    /**
     * Changes only the human shooting animation. Both styles keep the exact same input and
     * TripleShotPhysics path, so this cannot change scoring or shot difficulty.
     */
    func setHumanShotStyle(style: TripleShotPlayerRenderer.ShotStyle) {
        humanShotStyle = style
        invalidate()
    }

    /** Enables compact path capture only while a Live local shot is in flight. */
    func setLiveReplayCaptureEnabled(enabled: Bool) {
        liveReplayCaptureEnabled = enabled
        if !enabled {
            liveReplaySamples.removeAll()
            liveReplayStartedAtNanos = 0
            liveReplayLastSampleMs = -Self.LIVE_REPLAY_SAMPLE_INTERVAL_MS
        }
    }

    /** Current human foot position in source-artwork coordinates for network replay. */
    func currentPlayerSourcePosition() -> APointF {
        if width <= 0 || height <= 0 { return APointF(0, 0) }
        let t = backgroundTransform()
        return APointF(
            ((playerX - t.offsetX) / t.scaleX).coerceIn(0, Self.BACKGROUND_WIDTH),
            ((playerFootY - t.offsetY) / t.scaleY).coerceIn(0, Self.BACKGROUND_HEIGHT)
        )
    }

    // MARK: - Live multiplayer visuals (Kotlin 1743-2183)

    /**
     * Keeps up to three remote avatars on court. Their score is rendered by the Fragment;
     * this method is purely the visual player layer.
     */
    func setLiveOpponents(players: [LivePlayerState]) {
        let wanted = Set(players.prefix(3).map { $0.uid })
        for uid in liveRemotePlayers.keys.filter({ !wanted.contains($0) }) {
            _ = liveRemotePlayers.remove(uid)
        }

        for (index, player) in players.prefix(3).enumerated() {
            let idle = Self.LIVE_REMOTE_IDLE_SPOTS[index % Self.LIVE_REMOTE_IDLE_SPOTS.count]
            if let remote = liveRemotePlayers[player.uid] {
                remote.name = player.name.kotlinIsBlank ? remote.name : player.name
                remote.score = player.score
            } else {
                let p = sourcePointToView(sourceX: idle.x, sourceY: idle.y)
                let created = LiveRemoteVisual(
                    uid: player.uid,
                    name: player.name.kotlinIsBlank ? "Player" : player.name,
                    score: player.score,
                    sourceX: idle.x,
                    sourceY: idle.y,
                    x: p.x,
                    footY: p.y
                )
                let held = liveRemoteHeldBall(remote: created)
                created.ballX = held.x
                created.ballY = held.y
                liveRemotePlayers[player.uid] = created
            }
        }
        invalidate()
    }

    /** Applies visual court atmosphere. Background artwork itself is owned by the GPU world. */
    func setCourtStyle(style: TripleShotCourtStyle) {
        premiumCourtId = style.id
        courtAtmosphere = style.atmosphere
        invalidate()
    }

    /** Current theme id, kept outside Fragment/Firebase logic. */
    func currentCourtThemeId() -> String { return courtTheme.id }

    /** Theme-owned seating points for Live HORSE spectators. */
    func spectatorSpots() -> [SpectatorSpot] {
        return Array(courtTheme.spectatorArea.spots)
    }

    /**
     * Applies spectator/winner poses for Live HORSE. Eliminated players remain connected
     * and visible, but walk to a theme-specific spectator point and sit down.
     */
    func applyLiveHorseState(
        state: LiveHorseState,
        myUid: String
    ) {
        if width <= 0 || height <= 0 {
            post { [weak self] in self?.applyLiveHorseState(state: state, myUid: myUid) }
            return
        }

        let mySlot = state.spectatorSlots[myUid]
        if state.winnerUid == myUid {
            humanEndPose = TripleShotPlayerRenderer.Pose.WINNER
            horseFreeMoveEnabled = false
            shotGuidesVisible = false
        } else if let mySlot = mySlot {
            horseFreeMoveEnabled = false
            shotGuidesVisible = false
            moveHumanToSpectatorSlot(slot: mySlot, animate: true)
        } else {
            humanEndPose = TripleShotPlayerRenderer.Pose.NORMAL
        }

        for remote in liveRemotePlayers.values {
            let slot = state.spectatorSlots[remote.uid]
            if state.winnerUid == remote.uid {
                remote.pose = TripleShotPlayerRenderer.Pose.WINNER
                remote.renderScale = 0.82
                remote.ballVisible = false
            } else if let slot = slot {
                let spectator =
                    courtTheme.spectatorArea.spots.getOrNull(slot)
                        ?? courtTheme.spectatorArea.spots.last
                if let spectator = spectator {
                    remote.renderScale = spectator.scale
                    if remote.pose != TripleShotPlayerRenderer.Pose.SPECTATOR {
                        remote.pose = TripleShotPlayerRenderer.Pose.NORMAL
                        moveLiveRemoteToSource(
                            remote: remote,
                            sourceX: spectator.sourceX,
                            sourceY: spectator.sourceY,
                            animate: true,
                            onEnd: { [weak self] in
                                remote.pose = TripleShotPlayerRenderer.Pose.SPECTATOR
                                remote.ballVisible = false
                                self?.invalidate()
                            }
                        )
                    }
                }
            } else {
                remote.pose = TripleShotPlayerRenderer.Pose.NORMAL
                remote.renderScale = 0.82
            }
        }
        invalidate()
    }

    /**
     * Moves the local player to an exact free-set HORSE spot received from Firebase.
     */
    func moveHumanToHorseSourceSpot(
        sourceX: Float,
        sourceY: Float,
        spotId: String,
        animate: Bool = true,
        onEnd: (() -> Void)? = nil
    ) {
        humanWaitingForTurn = false
        if width <= 0 || height <= 0 {
            post { [weak self] in
                self?.moveHumanToHorseSourceSpot(
                    sourceX: sourceX,
                    sourceY: sourceY,
                    spotId: spotId,
                    animate: animate,
                    onEnd: onEnd
                )
            }
            return
        }

        let safeX = sourceX.coerceIn(0, Self.BACKGROUND_WIDTH)
        let safeY = sourceY.coerceIn(0, Self.BACKGROUND_HEIGHT)
        let dx = safeX - Self.SRC_HOOP_CENTER_X
        let dy = safeY - Self.SRC_HOOP_PLANE_Y
        let distance = ksqrt(dx * dx + dy * dy)
        let difficulty = ((distance - 330) / 720).coerceIn(0.18, 0.95)

        let station = Station(
            id: spotId,
            sourceX: safeX,
            sourceY: safeY,
            distanceDifficulty: difficulty,
            zone: "live_horse"
        )
        horseCustomSpots[spotId] = station
        horseHumanStation = station
        horseSelectedSpotId = spotId
        selectedStation = -1
        answerMarkersVisible = false
        horseSpotPickerVisible = false
        horseFreeMoveEnabled = false
        dribbleBouncePx = 0

        let point = sourcePointToView(sourceX: safeX, sourceY: safeY)
        setPlayerPosition(x: point.x, y: point.y, animate: animate, onEnd: onEnd)
        invalidate()
    }

    func moveHumanToSpectatorSlot(slot: Int, animate: Bool) {
        guard let spectator =
            courtTheme.spectatorArea.spots.getOrNull(slot)
                ?? courtTheme.spectatorArea.spots.last
        else { return }
        let point = sourcePointToView(sourceX: spectator.sourceX, sourceY: spectator.sourceY)
        let farEnough =
            abs(playerX - point.x) > dp(v: 3) ||
            abs(playerFootY - point.y) > dp(v: 3)
        if farEnough {
            humanEndPose = TripleShotPlayerRenderer.Pose.NORMAL
            setPlayerPosition(x: point.x, y: point.y, animate: animate, onEnd: { [weak self] in
                guard let self = self else { return }
                humanEndPose = TripleShotPlayerRenderer.Pose.SPECTATOR
                ballVisible = false
                invalidate()
            })
        } else {
            humanEndPose = TripleShotPlayerRenderer.Pose.SPECTATOR
            ballVisible = false
        }
    }

    /// Quirk kept (spec 08 section 8.3): the end handler (and so `onEnd`) also runs after a cancel.
    func moveLiveRemoteToSource(
        remote: LiveRemoteVisual,
        sourceX: Float,
        sourceY: Float,
        animate: Bool,
        onEnd: (() -> Void)? = nil
    ) {
        let targetX = sourceX.coerceIn(0, Self.BACKGROUND_WIDTH)
        let targetY = sourceY.coerceIn(0, Self.BACKGROUND_HEIGHT)

        if abs(remote.sourceX - targetX) < 3 &&
            abs(remote.sourceY - targetY) < 3 {
            onEnd?()
            return
        }

        remote.moveAnimator?.cancel()

        if !animate {
            remote.sourceX = targetX
            remote.sourceY = targetY
            let p = sourcePointToView(sourceX: targetX, sourceY: targetY)
            remote.x = p.x
            remote.footY = p.y
            remote.dribbleBouncePx = 0
            remote.ballVisible = remote.pose == TripleShotPlayerRenderer.Pose.NORMAL
            invalidate()
            onEnd?()
            return
        }

        let fromX = remote.sourceX
        let fromY = remote.sourceY
        remote.ballVisible = true
        let animator = AValueAnimator.ofFloat(0, 1)
        animator.duration = Self.LIVE_REMOTE_WALK_MS
        animator.interpolator = ADecelerateInterpolator()
        animator.addUpdateListener { [weak self] animator in
            guard let self = self else { return }
            let t = animator.animatedValueFloat
            remote.sourceX = lerp(a: fromX, b: targetX, t: t)
            remote.sourceY = lerp(a: fromY, b: targetY, t: t)
            let p = sourcePointToView(sourceX: remote.sourceX, sourceY: remote.sourceY)
            remote.x = p.x
            remote.footY = p.y
            remote.dribbleBouncePx =
                abs(ksin(t * PI_F * 4)) * dp(v: Self.LIVE_REMOTE_DRIBBLE_DP)
            invalidate()
        }
        animator.addListener(AAnimatorListenerAdapter(onEnd: { [weak self] _ in
            remote.moveAnimator = nil
            remote.dribbleBouncePx = 0
            remote.ballVisible = remote.pose == TripleShotPlayerRenderer.Pose.NORMAL
            self?.invalidate()
            onEnd?()
        }))
        animator.start()
        remote.moveAnimator = animator
    }

    func clearLiveOpponents() {
        removeCallbacks(liveRemoteFrameRunnable)
        for remote in liveRemotePlayers.values {
            remote.moveAnimator?.cancel()
            remote.replayAnimator?.cancel()
        }
        liveRemotePlayers.clear()
        invalidate()
    }

    /**
     * Replays a remote release. New Live clients send source-coordinate path samples after the
     * real local flight finishes, so every device sees the same rim/backboard bounce. Older
     * gesture-only events still fall back to the deterministic local physics mirror.
     * (Quirk kept: a cancelled walk still schedules its beginShot() 140 ms later.)
     */
    func playLiveRemoteShot(event: LiveShotEvent) {
        if event.playerUid.kotlinIsBlank { return }
        if width <= 0 || height <= 0 {
            post { [weak self] in self?.playLiveRemoteShot(event: event) }
            return
        }

        let remote: LiveRemoteVisual
        if let existing = liveRemotePlayers[event.playerUid] {
            remote = existing
        } else {
            let p = sourcePointToView(sourceX: event.shotSpotX, sourceY: event.shotSpotY)
            let created = LiveRemoteVisual(
                uid: event.playerUid,
                name: event.playerName.kotlinIsBlank ? "Player" : event.playerName,
                sourceX: event.shotSpotX,
                sourceY: event.shotSpotY,
                x: p.x,
                footY: p.y
            )
            liveRemotePlayers[event.playerUid] = created
            remote = created
        }

        remote.name = event.playerName.kotlinIsBlank ? remote.name : event.playerName
        remote.hotHand = event.hotHand
        remote.moveAnimator?.cancel()
        remote.replayAnimator?.cancel()
        remote.physicsState = nil
        remote.physicsGeometry = nil
        remote.replayActive = false
        remote.ballVisible = true
        remote.ballRotationDeg = 0
        remote.dribbleBouncePx = 0

        let targetSourceX = event.shotSpotX.coerceIn(0, Self.BACKGROUND_WIDTH)
        let targetSourceY = event.shotSpotY.coerceIn(0, Self.BACKGROUND_HEIGHT)
        let fromX = remote.sourceX
        let fromY = remote.sourceY

        let beginShot: () -> Void = { [weak self] in
            guard let self = self else { return }
            remote.sourceX = targetSourceX
            remote.sourceY = targetSourceY
            let mapped = sourcePointToView(sourceX: remote.sourceX, sourceY: remote.sourceY)
            remote.x = mapped.x
            remote.footY = mapped.y
            remote.dribbleBouncePx = 0

            if event.samples.count >= 2 {
                startLiveSampleReplay(remote: remote, samplesRaw: event.samples)
            } else {
                startLivePhysicsFallback(remote: remote, event: event)
            }
        }

        let distance = ksqrt(
            (targetSourceX - fromX) * (targetSourceX - fromX) +
                (targetSourceY - fromY) * (targetSourceY - fromY)
        )

        if distance < 12 {
            beginShot()
            return
        }

        let animator = AValueAnimator.ofFloat(0, 1)
        animator.duration = Self.LIVE_REMOTE_WALK_MS
        animator.interpolator = ADecelerateInterpolator()
        animator.addUpdateListener { [weak self] animator in
            guard let self = self else { return }
            let t = animator.animatedValueFloat
            remote.sourceX = lerp(a: fromX, b: targetSourceX, t: t)
            remote.sourceY = lerp(a: fromY, b: targetSourceY, t: t)
            let p = sourcePointToView(sourceX: remote.sourceX, sourceY: remote.sourceY)
            remote.x = p.x
            remote.footY = p.y
            remote.dribbleBouncePx =
                abs(ksin(t * PI_F * 4)) * dp(v: Self.LIVE_REMOTE_DRIBBLE_DP)
            let held = liveRemoteHeldBall(remote: remote)
            remote.ballX = held.x
            remote.ballY = held.y
            invalidate()
        }
        animator.addListener(AAnimatorListenerAdapter(onEnd: { [weak self] _ in
            remote.moveAnimator = nil
            remote.dribbleBouncePx = 0
            guard let self = self else { return }
            postDelayed({ beginShot() }, Self.LIVE_REMOTE_LOAD_MS)
        }))
        animator.start()
        remote.moveAnimator = animator
    }

    /// Supported but dormant on Android today: every published event carries 0 samples (spec 08 section 4.10).
    func startLiveSampleReplay(
        remote: LiveRemoteVisual,
        samplesRaw: [ShotReplaySample]
    ) {
        let samples = Array(samplesRaw.kSortedBy { $0.tMs }.prefix(Self.LIVE_MAX_REPLAY_SAMPLES))
        if samples.count < 2 { return }

        let durationMs = samples[samples.count - 1].tMs.coerceIn(180, 6000)
        let start = sourcePointToView(sourceX: samples[0].x, sourceY: samples[0].y)
        remote.replayStartX = start.x
        remote.replayStartY = start.y
        remote.replayFlightProgress = 0
        // Only estimates when the hand-anchor correction ends; the recorded path/timing
        // and Firebase result remain authoritative, including misses and rebounds.
        let basketTimeMs: Int64 =
            Array(samples.dropFirst()).kMinBy { (sample: ShotReplaySample) -> Float in
                let dx = sample.x - Self.SRC_HOOP_CENTER_X
                let dy = sample.y - Self.SRC_HOOP_PLANE_Y
                return dx * dx + dy * dy
            }.map { $0.tMs.coerceAtLeast(100) } ?? durationMs
        remote.replayActive = true
        remote.ballVisible = true

        let lastIndex = samples.count - 1
        let animator = AValueAnimator.ofFloat(0, durationMs.toFloat())
        animator.duration = durationMs
        animator.interpolator = ALinearInterpolator()
        animator.addUpdateListener { [weak self] animator in
            guard let self = self else { return }
            let timeMs = animator.animatedValueFloat
            remote.replayFlightProgress = timeMs / basketTimeMs.toFloat()
            let pairIndex =
                (samples.lastIndex(where: { $0.tMs.toFloat() <= timeMs }) ?? -1).coerceIn(0, lastIndex - 1)
            let a = samples[pairIndex]
            let b = samples[pairIndex + 1]
            let span = (b.tMs &- a.tMs).coerceAtLeast(1).toFloat()
            let t = ((timeMs - a.tMs.toFloat()) / span).coerceIn(0, 1)
            let sourceX = lerp(a: a.x, b: b.x, t: t)
            let sourceY = lerp(a: a.y, b: b.y, t: t)
            let p = sourcePointToView(sourceX: sourceX, sourceY: sourceY)
            remote.ballX = p.x
            remote.ballY = p.y
            remote.ballRotationDeg += 5.5
            invalidate()
        }
        animator.addListener(AAnimatorListenerAdapter(onEnd: { [weak self] _ in
            remote.replayAnimator = nil
            remote.replayActive = false
            remote.ballRotationDeg = 0
            guard let self = self else { return }
            let held = liveRemoteHeldBall(remote: remote)
            remote.ballX = held.x
            remote.ballY = held.y
            invalidate()
        }))
        animator.start()
        remote.replayAnimator = animator
    }

    /// Deterministic local mirror of a gesture-only remote release (the path every Android event takes).
    func startLivePhysicsFallback(remote: LiveRemoteVisual, event: LiveShotEvent) {
        let start = liveRemoteHeldBall(remote: remote)
        let geometry = buildPhysicsGeometry()
        let skill = ShotSkill(
            aimError: event.aimError,
            powerError: event.powerError,
            arcError: event.arcError,
            rawPeakGyro: event.rawPeakGyro,
            rawReleasePitchDeg: event.rawReleasePitchDeg
        )
        let targetX =
            geometry.hoopCenterX + event.aimError.coerceIn(-1.30, 1.30) * aimRangePx()
        let difficulty = liveDistanceDifficulty(sourceX: remote.sourceX, sourceY: remote.sourceY)
        let state = TripleShotPhysics.createLaunch(
            skill: skill,
            startX: start.x,
            startY: start.y,
            targetX: targetX,
            targetY: geometry.hoopY,
            pullBack01: event.pullBack.coerceIn(0.22, 1.20),
            geometry: geometry,
            distanceDifficulty: difficulty
        )
        remote.physicsState = state
        remote.physicsGeometry = geometry
        remote.ballX = state.x
        remote.ballY = state.y
        remote.lastFrameNanos = 0
        removeCallbacks(liveRemoteFrameRunnable)
        postOnAnimation(liveRemoteFrameRunnable)
        invalidate()
    }

    // MARK: - Characters (Kotlin 2185-2197)

    /**
     * Selects local visual characters without changing physics or game rules.
     * Unknown / not-yet-authored ids safely fall back to the legacy vector renderer.
     */
    func setLocalCharacters(
        humanCharacterId: String,
        botCharacterId: String
    ) {
        self.humanCharacterId = humanCharacterId
        self.botCharacterId = botCharacterId
        humanCourtFacingInitialized = false
        invalidate()
    }

    // MARK: - 1v1, part 1 (Kotlin 2199-2648)

    /**
     * Enables the first playable local 1v1 vertical slice.
     *
     * The regular question/HORSE modes never enter this branch. 1v1 keeps one shared physical
     * ball, lets the human drag freely around the grounded court, prevents body overlap, and
     * exposes timed steal/block windows to the dedicated 1v1 Fragment.
     *
     * `botLabel`: the Kotlin default is `this.botLabel` (read at call time); a Swift default cannot read
     * `self`, so nil stands for "not passed".
     */
    func setOneOnOneEnabled(
        enabled: Bool,
        seed: Int64 = ASystem.currentTimeMillis(),
        botLabel: String? = nil,
        botBlockRating: Int = 50,
        humanBlockRating: Int = 50,
        botStealRating: Int = 50,
        humanStealRating: Int = 50,
        botStrengthRating: Int = 50,
        humanStrengthRating: Int = 50,
        botSpeedRating: Int = 50,
        humanSpeedRating: Int = 50,
        botHeightRating: Int = 50,
        humanHeightRating: Int = 50,
        botBallHandlingRating: Int = 50,
        humanBallHandlingRating: Int = 50,
        botDefenseRating: Int = 50,
        humanDefenseRating: Int = 50,
        botAgilityRating: Int = 50,
        humanAgilityRating: Int = 50,
        botOffenseRating: Int = 50,
        humanOffenseRating: Int = 50,
        botWeightRating: Int = 50,
        humanWeightRating: Int = 50,
        botJumpRating: Int = 50,
        humanJumpRating: Int = 50
    ) {
        let botLabel = botLabel ?? self.botLabel
        oneOnOneEnabled = enabled
        oneOnOneWorldStarted = false
        oneOnOneBotBlockRating = botBlockRating.coerceIn(0, 100)
        oneOnOneHumanBlockRating = humanBlockRating.coerceIn(0, 100)
        oneOnOneBotStealRating = botStealRating.coerceIn(0, 100)
        oneOnOneHumanStealRating = humanStealRating.coerceIn(0, 100)
        oneOnOneBotStrengthRating = botStrengthRating.coerceIn(0, 100)
        oneOnOneHumanStrengthRating = humanStrengthRating.coerceIn(0, 100)
        oneOnOneBotSpeedRating = botSpeedRating.coerceIn(0, 100)
        oneOnOneHumanSpeedRating = humanSpeedRating.coerceIn(0, 100)
        oneOnOneBotHeightRating = botHeightRating.coerceIn(0, 100)
        oneOnOneHumanHeightRating = humanHeightRating.coerceIn(0, 100)
        oneOnOneBotBallHandlingRating = botBallHandlingRating.coerceIn(0, 100)
        oneOnOneHumanBallHandlingRating = humanBallHandlingRating.coerceIn(0, 100)
        oneOnOneBotDefenseRating = botDefenseRating.coerceIn(0, 100)
        oneOnOneHumanDefenseRating = humanDefenseRating.coerceIn(0, 100)
        oneOnOneBotAgilityRating = botAgilityRating.coerceIn(0, 100)
        oneOnOneHumanAgilityRating = humanAgilityRating.coerceIn(0, 100)
        oneOnOneBotOffenseRating = botOffenseRating.coerceIn(0, 100)
        oneOnOneHumanOffenseRating = humanOffenseRating.coerceIn(0, 100)
        oneOnOneBotWeightRating = botWeightRating.coerceIn(0, 100)
        oneOnOneHumanWeightRating = humanWeightRating.coerceIn(0, 100)
        oneOnOneBotJumpRating = botJumpRating.coerceIn(0, 100)
        oneOnOneHumanJumpRating = humanJumpRating.coerceIn(0, 100)
        oneOnOneBotContestActive = false
        oneOnOneBotContestAllowed = true
        oneOnOneHumanHeldMotionOverride = nil
        botDribbleHandSign = 1
        oneOnOneBotContestRecoveryUntilNanos = 0
        oneOnOneHumanBlockUntilNanos = 0
        oneOnOneHumanShotBlocked = false
        oneOnOneBotShotBlocked = false
        oneOnOneBotStealCooldownUntilNanos = 0
        oneOnOneHumanStealCooldownUntilNanos = 0
        oneOnOneHumanStealProtectedUntilNanos = 0
        oneOnOneBotStealProtectedUntilNanos = 0
        oneOnOneHumanJumpStartedAtNanos = 0
        oneOnOneHumanJumpUntilNanos = 0
        oneOnOneHumanJumpHeightMultiplier = 1
        oneOnOneBotJumpStartedAtNanos = 0
        oneOnOneBotJumpUntilNanos = 0
        oneOnOneBotJumpHeightMultiplier = 1
        oneOnOneBotStealStartedAtNanos = 0
        oneOnOneBotStealUntilNanos = 0
        oneOnOneBotStealResolvePosted = false
        oneOnOneHumanStealStartedAtNanos = 0
        oneOnOneHumanStealUntilNanos = 0
        oneOnOneHumanStealResolvePosted = false
        oneOnOneHumanCrossoverUntilNanos = 0
        oneOnOneBotReactionLockedUntilNanos = 0
        oneOnOneBotDrivingUntilNanos = 0
        oneOnOneBotDunkFrameIndex = -1
        oneOnOneBotDunkFacing = TripleShotPlayerRenderer.Facing.BACK
        oneOnOneBotDunkMirrorX = false
        oneOnOneBotRecentAttackIntensity01 = 0.82
        cancelOneOnOneBotDunk()
        oneOnOneBotDefenseLastUpdateNanos = 0
        oneOnOneHumanLastMoveNanos = ASystem.nanoTime()
        oneOnOneLooseEventSerial = 0
        humanMovementHorizontalSign = 0
        removeCallbacks(oneOnOneDefenseHeartbeatRunnable)
        oneOnOneLooseBallLastOwnerHuman = nil
        stopOneOnOneLooseBall()

        if !enabled {
            horseFreeMoveEnabled = false
            horseHumanStation = nil
            shotGuidesVisible = false
            sharedHorseBallOwner = nil
            horseBallSkinLocked = false
            botPullBack = 0
            setBotOpponentEnabled(enabled: false)
            oneOnOneAutomaticBallStateListener = nil
            oneOnOneBlockEventListener = nil
            return
        }

        if width <= 0 || height <= 0 {
            post { [weak self] in
                guard let self = self else { return }
                if oneOnOneEnabled {
                    setOneOnOneEnabled(
                        enabled: true,
                        seed: seed,
                        botLabel: botLabel,
                        botBlockRating: botBlockRating,
                        humanBlockRating: humanBlockRating,
                        botStealRating: botStealRating,
                        humanStealRating: humanStealRating,
                        botStrengthRating: botStrengthRating,
                        humanStrengthRating: humanStrengthRating,
                        botSpeedRating: botSpeedRating,
                        humanSpeedRating: humanSpeedRating,
                        botHeightRating: botHeightRating,
                        humanHeightRating: humanHeightRating,
                        botBallHandlingRating: botBallHandlingRating,
                        humanBallHandlingRating: humanBallHandlingRating,
                        botDefenseRating: botDefenseRating,
                        humanDefenseRating: humanDefenseRating,
                        botAgilityRating: botAgilityRating,
                        humanAgilityRating: humanAgilityRating,
                        botOffenseRating: botOffenseRating,
                        humanOffenseRating: humanOffenseRating,
                        botWeightRating: botWeightRating,
                        humanWeightRating: humanWeightRating,
                        botJumpRating: botJumpRating,
                        humanJumpRating: humanJumpRating
                    )
                }
            }
            return
        }

        setBotOpponentEnabled(enabled: true, seed: seed, label: botLabel)
        horseBallSkinLocked = true
        horseFreeMoveEnabled = true
        horseHumanStation = nil
        horseSelectedSpotId = nil
        selectedStation = -1
        answerMarkersVisible = false
        horseSpotPickerVisible = false
        shotGuidesVisible = false
        humanWaitingForTurn = false
        botHotHand = false
        botPullBack = 0
        botFineAim = 0

        // Every checked possession starts in the lower half of the court rather than under
        // the rim. Rebounds remain live where they happen and therefore do not use this reset.
        resetOneOnOneCheckPositions(humanOffense: true, animate: false)
        oneOnOneGiveBallToHuman()
        invalidate()
    }

    func isOneOnOneHumanPossession() -> Bool {
        return oneOnOneEnabled && sharedHorseBallOwner == SharedBallOwner.HUMAN
    }

    func setOneOnOneAutomaticBallStateListener(
        listener: ((OneOnOneBallState) -> Void)?
    ) {
        oneOnOneAutomaticBallStateListener = listener
    }

    func setOneOnOneBlockEventListener(
        listener: ((_ humanBlocked: Bool) -> Void)?
    ) {
        oneOnOneBlockEventListener = listener
    }

    /** Pauses possession cleanly while the post-score / out-of-bounds knowledge question is up. */
    func oneOnOneClearPossessionForQuestion() {
        if !oneOnOneEnabled { return }
        stopOneOnOneLooseBall()
        removeCallbacks(oneOnOneDefenseHeartbeatRunnable)
        cancelHumanIdleDribble()
        cancelOneOnOneBotDunk()
        botMoveAnimator?.cancel()
        playerMoveAnimator?.cancel()
        sharedHorseBallOwner = nil
        ballVisible = false
        botBallVisible = false
        pullBack = 0
        fineAim = 0
        botPullBack = 0
        botFineAim = 0
        oneOnOneBotContestActive = false
        oneOnOneHumanBlockUntilNanos = 0
        invalidate()
    }

    func isOneOnOneLooseBall() -> Bool {
        return oneOnOneEnabled && oneOnOneLooseBallActive
    }

    /**
     * Resets a dead-ball / made-basket possession to a normal 1v1 check position.
     * Rebounds never call this: a live miss stays live exactly where the physics sent it.
     * (Returns WITHOUT calling onEnd when not in 1v1 or not laid out, as on Android.)
     */
    func resetOneOnOneCheckPositions(
        humanOffense: Bool,
        animate: Bool = false,
        onEnd: (() -> Void)? = nil
    ) {
        if !oneOnOneEnabled || width <= 0 || height <= 0 { return }

        let humanSource =
            humanOffense ? APointF(430, 1240) : APointF(505, 1085)
        let botSource =
            humanOffense ? APointF(555, 1085) : APointF(600, 1240)
        let humanPoint = sourcePointToView(sourceX: humanSource.x, sourceY: humanSource.y)
        let botPoint = sourcePointToView(sourceX: botSource.x, sourceY: botSource.y)
        setPlayerPosition(x: humanPoint.x, y: humanPoint.y, animate: animate)
        setBotPosition(x: botPoint.x, y: botPoint.y, animate: animate, onEnd: { [weak self] in
            guard let self = self else { return }
            // If the human won the check-ball question, finish the transition with the bot
            // already in a real defensive spot instead of waiting for the first human swipe.
            if humanOffense && sharedHorseBallOwner == SharedBallOwner.HUMAN {
                updateOneOnOneBotDefensePosition(force: true)
            }
            onEnd?()
        })
        horseHumanStation = nil
        botCurrentStation = nil
        invalidate()
    }

    /** True while the two body ellipses are actually in contact. */
    func isOneOnOneHumanInBodyContact() -> Bool {
        if !oneOnOneEnabled || !botEnabled { return false }
        let dx = playerX - botX
        let dy = (playerFootY - botFootY) * Self.ONE_ON_ONE_COLLISION_Y_SCALE
        let minDistance = dp(v: oneOnOneBodyRadiusDp(human: true) + oneOnOneBodyRadiusDp(human: false))
        return dx * dx + dy * dy <= minDistance * minDistance * 1.08
    }

    func oneOnOneGiveBallToHuman() {
        if !oneOnOneEnabled { return }
        if gpuWorld.isWorldReady() { oneOnOneWorldStarted = true }
        stopOneOnOneLooseBall()
        cancelOneOnOneBotDunk()
        botMoveAnimator?.cancel()
        botPullBack = 0
        oneOnOneBotContestActive = false
        oneOnOneHumanBlockUntilNanos = 0
        horseHumanStation = nil
        horseFreeMoveEnabled = true
        shotGuidesVisible = false
        giveSharedHorseBallToHuman()
        let now = ASystem.nanoTime()
        oneOnOneHumanStealProtectedUntilNanos =
            now &+ Self.ONE_ON_ONE_POSSESSION_PROTECTION_MS &* 1_000_000
        oneOnOneHumanLastMoveNanos = now
        updateOneOnOneBotDefensePosition(force: true)
        removeCallbacks(oneOnOneDefenseHeartbeatRunnable)
        postDelayed(oneOnOneDefenseHeartbeatRunnable, Self.ONE_ON_ONE_DEFENSE_HEARTBEAT_MS)
    }

    func oneOnOneGiveBallToBot() {
        if !oneOnOneEnabled { return }
        removeCallbacks(oneOnOneDefenseHeartbeatRunnable)
        stopOneOnOneLooseBall()
        cancelHumanIdleDribble()
        horseHumanStation = nil
        horseFreeMoveEnabled = true
        shotGuidesVisible = false
        pullBack = 0
        fineAim = 0
        oneOnOneBotContestActive = false
        giveSharedHorseBallToBot()
        oneOnOneBotStealProtectedUntilNanos =
            ASystem.nanoTime() &+ Self.ONE_ON_ONE_POSSESSION_PROTECTION_MS &* 1_000_000
    }

    /**
     * Human movement for 1v1. Automatic steals now resolve through a short visible reach/lunge,
     * so this method keeps its Boolean return only for backward compatibility and normally false.
     * (Like Android it does not check horseFreeMoveEnabled.)
     */
    @discardableResult
    func moveOneOnOneHumanByTouch(dx: Float, dy: Float) -> Bool {
        if !oneOnOneEnabled || width <= 0 || height <= 0 || shotFrameRunning { return false }

        moveHumanFreeBy(dx: dx, dy: dy)
        if abs(dx) + abs(dy) > dp(v: 0.35) {
            oneOnOneHumanLastMoveNanos = ASystem.nanoTime()
        }

        if oneOnOneLooseBallActive {
            resolveNeutralHumanBotBodyCollision()
            resolveOneOnOneLooseBallPossession(now: ASystem.nanoTime())
            return false
        }

        if sharedHorseBallOwner == SharedBallOwner.HUMAN {
            resolveHumanBotBodyCollision()
        } else {
            // While defending, the human is the planted body and the bot is the attacker.
            resolveBotHumanBodyCollision()
            // Human steals are explicit tap actions in V20.4. Movement still changes the
            // geometry/reach, but simply running near the ball no longer steals automatically.
        }

        if sharedHorseBallOwner == SharedBallOwner.HUMAN {
            if ASystem.nanoTime() >= oneOnOneBotReactionLockedUntilNanos {
                updateOneOnOneBotDefensePosition(force: false)
            }
            resolveHumanBotBodyCollision()
            maybeStartOneOnOneBotSteal()
        }

        return false
    }

    /**
     * Chooses a natural drive finish from live geometry. A straight-line defender in the lane
     * cancels the automatic finish: the attacker must first create a real angle/separation.
     */
    func chooseOneOnOneHumanDriveFinish(
        movementIntensity01: Float,
        movementDx: Float,
        movementDy: Float,
        dunkAbility: Int
    ) -> OneOnOneDriveFinish {
        if !oneOnOneEnabled || sharedHorseBallOwner != SharedBallOwner.HUMAN {
            return OneOnOneDriveFinish.JUMPER
        }

        let source = currentPlayerSourcePosition()
        let dxSrc = Self.SRC_HOOP_CENTER_X - source.x
        let dySrc = Self.SRC_HOOP_DEPTH_FOOT_Y - source.y
        let distanceSrc = ksqrt(dxSrc * dxSrc + dySrc * dySrc)
        if distanceSrc > Self.ONE_ON_ONE_LAYUP_MAX_DISTANCE_SRC {
            return OneOnOneDriveFinish.JUMPER
        }

        let hoop = sourcePointToView(sourceX: Self.SRC_HOOP_CENTER_X, sourceY: Self.SRC_HOOP_DEPTH_FOOT_Y)
        let hx = hoop.x - playerX
        let hy = hoop.y - playerFootY
        let hLen = ksqrt(hx * hx + hy * hy).coerceAtLeast(1)
        let ux = hx / hLen
        let uy = hy / hLen
        let defX = botX - playerX
        let defY = botFootY - playerFootY
        let forward = defX * ux + defY * uy
        let lateral = abs(defX * uy - defY * ux)
        let laneHalfWidth = dp(v: oneOnOneBodyRadiusDp(human: false) + 13)
        let defenderOwnsLane = forward >= 0 && forward <= hLen && lateral < laneHalfWidth
        if defenderOwnsLane && ASystem.nanoTime() >= oneOnOneBotReactionLockedUntilNanos {
            return OneOnOneDriveFinish.JUMPER
        }

        // A layup/dunk is a moving finish, not a stationary close shot. The most recent swipe must
        // actually point toward the hoop; sideways/backward motion remains a moving jumper.
        let moveLen =
            ksqrt(movementDx * movementDx + movementDy * movementDy)
                .coerceAtLeast(0.001)
        let towardHoop =
            (movementDx * ux + movementDy * uy) / moveLen
        if towardHoop < Self.ONE_ON_ONE_DRIVE_FINISH_MIN_FORWARD_DOT {
            return OneOnOneDriveFinish.JUMPER
        }

        let speed = movementIntensity01.coerceIn(0, 1)
        let dunk = dunkAbility.coerceIn(0, 100)
        if distanceSrc <= Self.ONE_ON_ONE_DUNK_MAX_DISTANCE_SRC &&
            speed >= Self.ONE_ON_ONE_DUNK_MIN_SPEED &&
            dunk >= Self.ONE_ON_ONE_DUNK_MIN_ABILITY {
            return OneOnOneDriveFinish.DUNK
        } else if speed >= Self.ONE_ON_ONE_LAYUP_MIN_SPEED {
            return OneOnOneDriveFinish.LAYUP
        } else {
            return OneOnOneDriveFinish.JUMPER
        }
    }

    /**
     * Carries live dribble momentum into a jumper. This is intentionally small: the user still has
     * to create real separation, but double-tapping while moving no longer freezes the body in place.
     * The same move becomes a natural side-step/fade/forward hop depending on the last swipe vector.
     */
    @discardableResult
    func oneOnOneHumanMovingShotJump(
        directionX: Float,
        directionY: Float,
        intensity01: Float
    ) -> Bool {
        if !oneOnOneEnabled ||
            sharedHorseBallOwner != SharedBallOwner.HUMAN ||
            shotFrameRunning ||
            oneOnOneLooseBallActive {
            return false
        }

        let len =
            ksqrt(directionX * directionX + directionY * directionY)
                .coerceAtLeast(0.001)
        let ux = directionX / len
        let uy = directionY / len
        let intensity = intensity01.coerceIn(0, 1)
        let distance = dp(
            v: Self.ONE_ON_ONE_MOVING_SHOT_MIN_DRIFT_DP +
                Self.ONE_ON_ONE_MOVING_SHOT_EXTRA_DRIFT_DP * intensity
        )

        let startX = playerX
        let startY = playerFootY
        let targetX = (startX + ux * distance).coerceIn(horseFreeMinX(), horseFreeMaxX())
        let targetY = clampHorseFreeY(x: targetX, y: startY + uy * distance)

        playerMoveAnimator?.cancel()
        let animator = AValueAnimator.ofFloat(0, 1)
        animator.duration = Self.ONE_ON_ONE_MOVING_SHOT_DRIFT_MS
        animator.interpolator = ADecelerateInterpolator()
        animator.addUpdateListener { [weak self] it in
            guard let self = self else { return }
            let p = it.animatedValueFloat
            playerX = startX + (targetX - startX) * p
            playerFootY = startY + (targetY - startY) * p
            resolveHumanBotBodyCollision()
            invalidate()
        }
        animator.start()
        playerMoveAnimator = animator

        let now = ASystem.nanoTime()
        oneOnOneHumanJumpStartedAtNanos = now
        oneOnOneHumanJumpUntilNanos =
            now &+ Self.ONE_ON_ONE_MOVING_SHOT_JUMP_MS &* 1_000_000
        oneOnOneHumanJumpHeightMultiplier =
            Self.ONE_ON_ONE_MOVING_SHOT_MIN_JUMP_MULTIPLIER +
            Self.ONE_ON_ONE_MOVING_SHOT_EXTRA_JUMP_MULTIPLIER * intensity

        // A hard lateral/fade jump creates a small, deterministic contest delay.
        // (Long * Float is Float arithmetic in Kotlin, then toLong().)
        oneOnOneBotReactionLockedUntilNanos =
            max(
                oneOnOneBotReactionLockedUntilNanos,
                now &+
                    (Self.ONE_ON_ONE_MOVING_SHOT_DEFENDER_DELAY_MIN_MS &+
                        (Self.ONE_ON_ONE_MOVING_SHOT_DEFENDER_DELAY_EXTRA_MS.toFloat() * intensity).toLong()) &*
                    1_000_000
            )

        invalidate()
        return true
    }
}
