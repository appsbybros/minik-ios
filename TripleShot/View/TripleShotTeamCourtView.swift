import Foundation

// Port of view/TripleShotTeamCourtView.kt (TripleShotGame 6c38131), PART 1: Kotlin lines 1-2327, statement by
// statement (spec 11-team1). DESIGN 2.9 / 2.10: this file declares the class, every stored property of the WHOLE
// Kotlin class (including the ones Kotlin declares after line 2327: leagueLabelColors L3573 and the premium*
// presentation timers L3612-3615), the initialiser, every override of the whole file (onDraw L3583 is a
// forwarding stub to `onDraw_impl` in part 2), the nested types of lines 1-2327 and every method of lines 1-2327
// (including all of updateOpponentOffense, L2015-2326). Part 2 (TripleShotTeamCourtView+Part2.swift: L2328-4096
// incl. the companion object constants, the `Transform` type and helpers such as currentBallHandler, giveBall,
// updateCamera, transform, dp) is an extension.
//
// Conventions (DESIGN 2.1-2.5):
// - Every Kotlin name is kept; Kotlin `private` members are `internal` (the class is split over several files).
//   Argument labels are the Kotlin parameter names, so cross-part calls are e.g. `distanceToHoop(a: actor)`.
// - Units are Android pixels (AndroidKit). Simulation state lives in the 1672 x 941 "source" space; the virtual 2D
//   camera of part 2 (`transform()`) is kept although nothing is drawn with it (spec 11 section 2.5).
// - Numbers: Float/Int/Int64 exactly as Kotlin (`Int * Float` promotes the Int first, `Long / Float` is
//   `toFloat() / x`, `kotlin.math.sin/sqrt/hypot(Float)` go through ksin/ksqrt/khypot). Long expressions are split
//   into sequential Float statements in the Kotlin evaluation order (no reassociation).
// - Random: the single bit-exact KotlinRandom `random`; every roll sits in the same short-circuit position as in
//   Kotlin, so a roll is drawn only when every earlier operand of its condition held.
// - First max/min: kMaxBy / kMinBy (Kotlin maxByOrNull / minByOrNull, first extreme wins); stable descending sort:
//   kSortedByDescending. `defensiveAssignments` and `touchPicks` are insertion-ordered KLinkedMaps (LinkedHashMap).
// - Clocks: gameTime() = SystemClock.elapsedRealtime() minus paused time; the 32 ms AI tick is View.postDelayed;
//   postAction uses a main-looper AHandler (AndroidKit Handler semantics); System.nanoTime() = ASystem.nanoTime().
// - Touch: AndroidKit delivers Android MotionEvents (pointer ids, ACTION_POINTER_DOWN/UP); the AOSP GestureDetector
//   port (AGestureDetector: 300 ms tap confirmation, 40-300 ms double tap, 400 ms long press, 8 dp slop) runs first,
//   then the raw pointer state machine, exactly as Kotlin.
//
// Not ported (dead on Android, spec 11 sections 3.3 and 8.4): `atmosphereRenderer` (L156, the base class draws the
// weather) and the eight legacy Canvas paints (L287-328: ballPaint, ballLinePaint, labelPaint, controlRingFill,
// controlRing, teammateRing, boostBadgePaint, backboardGlassPaint), none of which is ever read.
// Kept although vestigial: currentBallDrawable, TouchPick.ball, the fakeBurst*/lastMoveUpdate actor fields,
// CourtGeometryProfile.nearHoopLayerY, the TRIPLE_INPUT / TRIPLE_PLAY logs (ALog, DEBUG builds only).
// Deliberate type deviation: the `ballSkinResId` Bundle entry is written with putString because iOS drawable ids
// are their Android names (DESIGN 2.7); restoreRuntimeState never reads it (it forces R.drawable.basketball).

/**
 * Local 2v2 / 3v3 court layer.
 *
 * It deliberately lives beside TripleShotCourtView rather than branching the mature 1v1 state
 * machine. The same player renderer, character ratings and photographed court are reused, while
 * team-only concepts (passes, screens, switches, alley-oops and pass interceptions) remain local
 * to this view until the rules are stable enough to share with Live multiplayer.
 */
final class TripleShotTeamCourtView: TripleShotWorldHostView {

    enum Team: String, KotlinEnum {
        case HUMAN
        case OPPONENT
    }

    /**
     * Stable basketball roles for local team play. Roles are chosen once from the selected roster
     * and then guide spacing/decision-making; they are not hard restrictions on what a player can do.
     */
    enum TeamRole: String, KotlinEnum {
        case POINT_GUARD
        case WING
        case INTERIOR
    }

    enum DefenseScheme: String, KotlinEnum {
        case MAN_TO_MAN
        case ZONE
    }

    enum BallFlightKind: String, KotlinEnum {
        case NONE
        case PASS
        case SHOT
        case ALLEY_OOP
    }

    /// Kotlin `data class HumanGuidance` (compared by value in notifyHumanGuidanceIfChanged).
    struct HumanGuidance: Hashable {
        var role: TeamRole
        var matchupName: String?
        var defenseScheme: DefenseScheme

        init(role: TeamRole, matchupName: String?, defenseScheme: DefenseScheme) {
            self.role = role
            self.matchupName = matchupName
            self.defenseScheme = defenseScheme
        }
    }

    /// Kotlin `data class ActorSnapshot`: a read-only snapshot for hosts and tests.
    struct ActorSnapshot: Hashable {
        var id: String
        var team: Team
        var characterId: String
        var sourceX: Float
        var sourceY: Float
        var hasBall: Bool
        var controlled: Bool
        var boost01: Float

        init(id: String, team: Team, characterId: String, sourceX: Float, sourceY: Float, hasBall: Bool,
             controlled: Bool, boost01: Float) {
            self.id = id
            self.team = team
            self.characterId = characterId
            self.sourceX = sourceX
            self.sourceY = sourceY
            self.hasBall = hasBall
            self.controlled = controlled
            self.boost01 = boost01
        }
    }

    /// Kotlin `interface Listener`. Every callback runs synchronously on the main thread; hosts may re-enter the
    /// view from inside them. The three methods with Kotlin default bodies (`= Unit`) have empty defaults in the
    /// protocol extension below; `onStatus(message:)` is the Kotlin `team = null` default-argument form.
    protocol Listener: AnyObject {
        func onHighlight(team: TripleShotTeamCourtView.Team, event: TrumpetCadence.Event)
        func onTeamBasket(team: TripleShotTeamCourtView.Team, points: Int)
        func onPossessionChanged(team: TripleShotTeamCourtView.Team)
        func onStatus(message: String, team: TripleShotTeamCourtView.Team?)
        func onShotQuality(percent: Int, visible: Bool)
        func onDeadBall(defaultNextTeam: TripleShotTeamCourtView.Team)

        /** Short-lived UI hint when the user's defensive responsibility actually changes. */
        func onHumanGuidanceChanged(guidance: TripleShotTeamCourtView.HumanGuidance)
        func onShotClock(seconds: Int)
        func onLiveTime(milliseconds: Int64)
    }

    /// Kotlin `private data class Actor`: one player, a mutable reference shared by all logic (spec 11 section 8.1
    /// item 4). Data-class equality is never needed (ids are unique); `==` / hashing are by identity.
    final class Actor: Hashable {
        let id: String
        let team: Team
        let characterId: String
        let profile: TripleShotCharacterProfile
        var x: Float
        var y: Float
        var vx: Float
        var vy: Float
        var hasBall: Bool
        var controlled: Bool
        var facing: TripleShotPlayerRenderer.Facing
        var motion: TripleShotPlayerRenderer.Motion
        var mirror: Bool
        var dribblePhase: Float
        /** Visual bounce amplitude in dp, intentionally matched to the mature 1v1 rhythm. */
        var dribbleBounce: Float
        var dribbleHandSign: Float
        var crossAt: Int64
        var crossFrom: Float
        var crossBehind: Bool
        var spinAt: Int64
        var spinSign: Int
        var fallenUntil: Int64
        let spinSeries: BasketballMoves.SpinSeries
        var jumpPx: Float
        var jumpStarted: Int64
        var jumpUntil: Int64
        var screenedUntil: Int64
        var screenTargetId: String?
        var boost01: Float
        var cutUntil: Int64
        var lastAiDecision: Int64
        var lastStealAttempt: Int64
        var screenCooldownUntil: Int64
        var role: TeamRole
        var possessionReceivedAt: Int64
        var lastReboundClaimAt: Int64
        var actionLockUntil: Int64
        var fakeBurstUntil: Int64
        var fakeBurstSign: Float
        /** Last physical AI movement update; used to make speed frame-rate independent. */
        var lastMoveUpdate: Int64
        /** Last time this player actually changed floor position by a meaningful amount. */
        var lastMeaningfulMovementAt: Int64
        var targetX: Float
        var targetY: Float
        var travelScale: Float
        var screenPlantedAt: Int64
        var screenHoldUntil: Int64
        var returnPassId: String?
        var returnPassUntil: Int64
        let visual: BasketballVisualMotion

        /// Kotlin primary constructor with its defaults; `targetX`/`targetY` default to `x`/`y` (nil = default).
        init(
            id: String,
            team: Team,
            characterId: String,
            profile: TripleShotCharacterProfile,
            x: Float,
            y: Float,
            vx: Float = 0,
            vy: Float = 0,
            hasBall: Bool = false,
            controlled: Bool = false,
            facing: TripleShotPlayerRenderer.Facing = TripleShotPlayerRenderer.Facing.BACK,
            motion: TripleShotPlayerRenderer.Motion = TripleShotPlayerRenderer.Motion.IDLE,
            mirror: Bool = false,
            dribblePhase: Float = 0,
            dribbleBounce: Float = 0,
            dribbleHandSign: Float = 1,
            crossAt: Int64 = -10000, crossFrom: Float = 1, crossBehind: Bool = false,
            spinAt: Int64 = -10000, spinSign: Int = 1, fallenUntil: Int64 = 0,
            spinSeries: BasketballMoves.SpinSeries = BasketballMoves.SpinSeries(),
            jumpPx: Float = 0,
            jumpStarted: Int64 = 0,
            jumpUntil: Int64 = 0,
            screenedUntil: Int64 = 0,
            screenTargetId: String? = nil,
            boost01: Float = 0,
            cutUntil: Int64 = 0,
            lastAiDecision: Int64 = 0,
            lastStealAttempt: Int64 = 0,
            screenCooldownUntil: Int64 = 0,
            role: TeamRole = TeamRole.WING,
            possessionReceivedAt: Int64 = 0,
            lastReboundClaimAt: Int64 = 0,
            actionLockUntil: Int64 = 0,
            fakeBurstUntil: Int64 = 0,
            fakeBurstSign: Float = 0,
            lastMoveUpdate: Int64 = 0,
            lastMeaningfulMovementAt: Int64 = 0,
            targetX: Float? = nil,
            targetY: Float? = nil,
            travelScale: Float = 0,
            screenPlantedAt: Int64 = 0,
            screenHoldUntil: Int64 = 0,
            returnPassId: String? = nil,
            returnPassUntil: Int64 = 0,
            visual: BasketballVisualMotion = BasketballVisualMotion()
        ) {
            self.id = id
            self.team = team
            self.characterId = characterId
            self.profile = profile
            self.x = x
            self.y = y
            self.vx = vx
            self.vy = vy
            self.hasBall = hasBall
            self.controlled = controlled
            self.facing = facing
            self.motion = motion
            self.mirror = mirror
            self.dribblePhase = dribblePhase
            self.dribbleBounce = dribbleBounce
            self.dribbleHandSign = dribbleHandSign
            self.crossAt = crossAt
            self.crossFrom = crossFrom
            self.crossBehind = crossBehind
            self.spinAt = spinAt
            self.spinSign = spinSign
            self.fallenUntil = fallenUntil
            self.spinSeries = spinSeries
            self.jumpPx = jumpPx
            self.jumpStarted = jumpStarted
            self.jumpUntil = jumpUntil
            self.screenedUntil = screenedUntil
            self.screenTargetId = screenTargetId
            self.boost01 = boost01
            self.cutUntil = cutUntil
            self.lastAiDecision = lastAiDecision
            self.lastStealAttempt = lastStealAttempt
            self.screenCooldownUntil = screenCooldownUntil
            self.role = role
            self.possessionReceivedAt = possessionReceivedAt
            self.lastReboundClaimAt = lastReboundClaimAt
            self.actionLockUntil = actionLockUntil
            self.fakeBurstUntil = fakeBurstUntil
            self.fakeBurstSign = fakeBurstSign
            self.lastMoveUpdate = lastMoveUpdate
            self.lastMeaningfulMovementAt = lastMeaningfulMovementAt
            self.targetX = targetX ?? x
            self.targetY = targetY ?? y
            self.travelScale = travelScale
            self.screenPlantedAt = screenPlantedAt
            self.screenHoldUntil = screenHoldUntil
            self.returnPassId = returnPassId
            self.returnPassUntil = returnPassUntil
            self.visual = visual
        }

        static func == (lhs: Actor, rhs: Actor) -> Bool {
            return lhs === rhs
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(ObjectIdentifier(self))
        }
    }

    struct HoopGeometry: Hashable {
        var rimX: Float
        var rimY: Float
        /** Ground projection used for spacing, drives and defensive positioning. */
        var footX: Float
        var footY: Float

        init(rimX: Float, rimY: Float, footX: Float, footY: Float) {
            self.rimX = rimX
            self.rimY = rimY
            self.footX = footX
            self.footY = footY
        }
    }

    struct CourtGeometryProfile: Hashable {
        var top: HoopGeometry
        var bottom: HoopGeometry
        var nearHoopLayerY: Float

        init(top: HoopGeometry, bottom: HoopGeometry, nearHoopLayerY: Float) {
            self.top = top
            self.bottom = bottom
            self.nearHoopLayerY = nearHoopLayerY
        }
    }

    // L155-159
    let renderer = TripleShotPlayerRenderer()
    // L156 `atmosphereRenderer` is dead on Android (the base class draws the weather): not ported.
    var courtAtmosphere = TripleShotCourtAtmosphere.COLORED_LIGHTS
    var currentBallSkinResId: ADrawableRes = R.drawable.basketball
    var currentBallDrawable: ADrawable? = nil

    /*
     * Team play uses one calibrated full-court source image in BOTH device orientations. Keeping
     * one source coordinate system is what makes passes, hoop physics, AI spacing and camera pans
     * stay identical when the user chooses portrait instead of landscape.
     */
    var cameraCenterX: Float = TripleShotTeamCourtView.FULL_COURT_CENTER_X
    var cameraCenterY: Float = TripleShotTeamCourtView.FULL_COURT_CENTER_Y
    var cameraZoom: Float = 1
    var cameraInitialized = false
    var currentCourtStyleId: String = TripleShotTeamCourtView.FULL_COURT_STYLE_ID
    var actors: [Actor] = []
    var listener: Listener? = nil
    /** Local guided practice only. Existing matches do not install these hooks. */
    var practiceAction: ((BasketballSkill, Double) -> Void)? = nil
    var practiceQuiet = false
    /// Kotlin `mutableSetOf<String>()` (add / remove -> Boolean / clear; never iterated).
    var requestedPracticeScreens = KLinkedSet<String>()

    func practiceEvent(skill: BasketballSkill, amount: Double = 1.0) {
        if possession != nil { practiceAction?(skill, amount) }
    }

    func practiceActorPoint(id: String) -> APointF? {
        guard let actor = actors.first(where: { $0.id == id }) else { return nil }
        guard let bounds = gpuWorld.actorBounds(actor: worldActor(actor: actor)) else { return nil }
        return APointF(bounds.centerX(), bounds.centerY())
    }

    func practiceBallPoint() -> APointF? {
        guard let ball = worldScene?.balls.first else { return nil }
        let owner = worldScene?.actors.first(where: { $0.id == ball.owner })
        let position = owner != nil ? gpuWorld.actorSocket(actor: owner!, inFront: ball.inFront) : ball.position
        guard let projected = gpuWorld.project(p: position) else { return nil }
        return APointF(projected.first, projected.second)
    }

    var teamSize = 2
    var seed: Int64 = ASystem.currentTimeMillis()
    var random: KotlinRandom
    var possession: Team? = nil
    var activeHumanActorId = "H0"
    var movementAt: Int64 = 0
    var humanMoveAt: Int64 = 0
    lazy var dribbleGesture: DribbleGesture = DribbleGesture(dp(v: 18))
    lazy var circularGesture: CircularDribbleGesture = CircularDribbleGesture(dp(v: 14))
    var lastClockSeconds = -1
    var lastLiveTick: Int64 = 0
    var pauseAt: Int64 = 0
    var pausedDuration: Int64 = 0

    func gameTime() -> Int64 {
        return (pauseAt > 0 ? pauseAt : ASystemClock.elapsedRealtime()) - pausedDuration
    }

    func setMatchPaused(paused: Bool) {
        if paused && pauseAt == 0 {
            pauseAt = ASystemClock.elapsedRealtime()
            resetTouchInteractionState()
            ballAnimator?.pause()
        } else if !paused && pauseAt > 0 {
            pausedDuration += ASystemClock.elapsedRealtime() - pauseAt
            pauseAt = 0
            lastLiveTick = 0
            looseLastNanos = 0
            ballAnimator?.resume()
        }
    }

    /// Kotlin positional call form `setMatchPaused(paused)`.
    func setMatchPaused(_ paused: Bool) {
        setMatchPaused(paused: paused)
    }

    // Action poses and possession transfers use the same paused clock as the match.
    func postAction(action: @escaping () -> Void, delay: Int64) {
        let due = gameTime() + delay
        actionHandler.postDelayed(ARunnable(withSelf: { [self] runnable in
            let remaining = due - gameTime()
            if pauseAt > 0 || remaining > 0 {
                actionHandler.postDelayed(runnable, pauseAt > 0 ? 100 : remaining)
            } else {
                action()
            }
        }), delay)
    }

    var pendingShotActor: String? = nil
    var passReceiverId: String? = nil

    var possessionStartedAt: Int64 = 0
    var trackedHandlerId: String? = nil
    var trackedHandlerSince: Int64 = 0

    /** Persistent matchups stop defenders from re-picking the nearest player every frame. */
    var defensiveAssignments = KLinkedMap<String, String>()
    var activeDefenseScheme = DefenseScheme.MAN_TO_MAN
    var defendingTeam: Team? = nil
    var lastGuidance: HumanGuidance? = nil

    var ballVisible = false
    /** Current screen-space ball position used only for drawing / touch proximity. */
    var ballX: Float = 0
    var ballY: Float = 0
    /** In-flight and loose balls live in full-court coordinates so the camera can move underneath them. */
    var ballSourceX: Float = TripleShotTeamCourtView.FULL_COURT_CENTER_X
    var ballSourceY: Float = TripleShotTeamCourtView.FULL_COURT_CENTER_Y
    // Camera follows the ball's GROUND-PROJECTED travel, not the vertical arc itself. Otherwise a
    // jump shot makes the whole court bob up/down even though the landing point is predictable.
    var ballCameraFocusX: Float = TripleShotTeamCourtView.FULL_COURT_CENTER_X
    var ballCameraFocusY: Float = TripleShotTeamCourtView.FULL_COURT_CENTER_Y
    var premiumFlightBall = CourtPoint(x: 0, y: 1.4, z: 0)
    var premiumFlightStart = CourtPoint(x: 0, y: 1.4, z: 0)
    var premiumFlightEnd = CourtPoint(x: 0, y: 1.4, z: 0)
    var ballInFlight = false
    var ballFlightKind = BallFlightKind.NONE
    var ballAnimator: AValueAnimator? = nil
    var looseBall = false
    var looseVxSource: Float = 0
    var looseVySource: Float = 0
    var looseLastNanos: Int64 = 0

    /*
     * Touch priority for team play:
     * 1) SWIPE is movement and must never silently turn into a shot.
     * 2) A real tap can still be used for teammate pass / defensive switch.
     * 3) A stationary hold can gather a shot.
     *
     * We keep both the ACTION_DOWN origin and the latest point. The origin decides whether the
     * gesture has become a swipe; the latest point supplies the incremental movement delta.
     */
    var dragPointerId = -1
    var dragDownX: Float = 0
    var dragDownY: Float = 0
    var lastTouchX: Float = 0
    var lastTouchY: Float = 0
    var dragMoved = false

    // Android's device-specific touch slop is more reliable than a hard-coded dp threshold.
    let movementTouchSlopPx: Float = AViewConfiguration.get().scaledTouchSlop.toFloat()

    var shotPointerId = -1
    var shotHoldStarted: Int64 = 0
    var shotHoldActive = false
    var pendingShotRunnable: ARunnable? = nil

    // L287-328: the legacy Canvas paints are dead since the GPU migration (never read): not ported.

    // Single taps wait for Android's double-tap decision. Keep the intended player/ball
    // from touch-down: a moving teammate must not become unselectable during that delay.
    // A changed possession invalidates the old choice; normal pass/reach rules still apply.
    struct TouchPick: Hashable {
        var actorId: String?
        var ball: Bool
        var team: Team?
        var possessionAt: Int64

        init(actorId: String?, ball: Bool, team: Team?, possessionAt: Int64) {
            self.actorId = actorId
            self.ball = ball
            self.team = team
            self.possessionAt = possessionAt
        }
    }

    var touchPicks = KLinkedMap<Int64, TouchPick>()

    func touchPick(e: AMotionEvent) -> TouchPick? {
        guard let pick = touchPicks[e.downTime] else { return nil }
        return (pick.team == possession && pick.possessionAt == possessionStartedAt) ? pick : nil
    }

    func pickedActor(e: AMotionEvent) -> Actor? {
        guard let id = touchPick(e: e)?.actorId else { return nil }
        return actors.first(where: { $0.id == id })
    }

    /// Kotlin `GestureDetector(context, object : GestureDetector.SimpleOnGestureListener() { ... })`; the anonymous
    /// listener is `TeamGestureListener` (weak back-reference, no retain cycle). Created on first use (no side
    /// effects at construction).
    lazy var gestureDetector: AGestureDetector = AGestureDetector(TeamGestureListener(view: self))

    /// The anonymous `GestureDetector.SimpleOnGestureListener` of L336-407.
    final class TeamGestureListener: ASimpleOnGestureListener {
        weak var view: TripleShotTeamCourtView?

        init(view: TripleShotTeamCourtView) {
            self.view = view
            super.init()
        }

        override func onDown(_ e: AMotionEvent) -> Bool {
            guard let v = view else { return true }
            let actor = v.actorAt(x: e.x, y: e.y)
            // The expanded steal target must not swallow a teammate's body. A direct
            // tap on the visible ball still wins; nearby empty space keeps its generous radius.
            let ball = v.tapHitsLiveBall(x: e.x, y: e.y, radiusDp: actor?.team == Team.HUMAN ? 14 : 38)
            v.touchPicks[e.downTime] = TouchPick(actorId: actor?.id, ball: ball, team: v.possession,
                                                 possessionAt: v.possessionStartedAt)
            while v.touchPicks.count > 4 {
                let oldest = v.touchPicks.keys.first!
                v.touchPicks.remove(oldest)
            }
            return true
        }

        override func onSingleTapUp(_ e: AMotionEvent) -> Bool {
            guard let v = view else { return false }
            // Defense does not need to wait for a possible alley-oop double tap.
            // Reach while the player is in range at release, not 300ms later.
            if v.possession == Team.OPPONENT && v.touchPick(e: e) != nil &&
                (v.pickedActor(e: e)?.team != Team.HUMAN || v.pickedActor(e: e)?.controlled == true) {
                v.attemptHumanDefensiveAction()
                return true
            }
            return false
        }

        override func onSingleTapConfirmed(_ e: AMotionEvent) -> Bool {
            guard let v = view else { return true }
            /*
             * Defense has one unambiguous priority:
             *   tap court space / opponent / controlled player -> nearby steal or block
             *   tap a HUMAN teammate -> switch control
             */
            if v.possession == Team.OPPONENT && v.touchPick(e: e) != nil &&
                (v.pickedActor(e: e)?.team != Team.HUMAN || v.pickedActor(e: e)?.controlled == true) {
                return true
            }

            let actor = v.pickedActor(e: e)
            if let actor = actor {
                v.handleActorTap(actor: actor)
            }
            return true
        }

        // Double tap remains reserved for alley-oop. Using onSingleTapConfirmed above is important:
        // onSingleTapUp fires before Android knows whether a second tap is coming and could pass the
        // ball away before the alley-oop callback gets a chance to run.
        override func onDoubleTap(_ e: AMotionEvent) -> Bool {
            guard let v = view else { return true }
            // A defensive double-tap should not swallow a valid steal just because Android suppresses
            // onSingleTapConfirmed when it recognizes the second tap.
            if v.possession == Team.OPPONENT && v.touchPick(e: e) != nil &&
                (v.pickedActor(e: e)?.team != Team.HUMAN || v.pickedActor(e: e)?.controlled == true) {
                v.attemptHumanDefensiveAction()
                return true
            }

            let actor = v.pickedActor(e: e)
            if let actor = actor, actor.team == Team.HUMAN {
                let handler = v.currentBallHandler()
                if let handler = handler, handler.team == Team.HUMAN && actor.id != handler.id {
                    v.startAlleyOop(from: handler, receiver: actor)
                }
            }
            return true
        }

        override func onLongPress(_ e: AMotionEvent) {
            guard let v = view else { return }
            guard let actor = v.pickedActor(e: e) else { return }
            guard let handler = v.currentBallHandler() else { return }
            if actor.team == Team.HUMAN && handler.team == Team.HUMAN && actor.id != handler.id {
                if v.practiceAction != nil && handler.controlled { v.requestedPracticeScreens.add(actor.id) }
                v.commandScreen(screener: actor, ballHandler: handler)
            }
        }
    }

    /// L409-419: the 32 ms AI tick (`object : Runnable`, re-posted with View.postDelayed after its work).
    lazy var aiRunnable: ARunnable = ARunnable(withSelf: { [weak self] runnable in
        guard let self = self else { return }
        if self.pauseAt > 0 {
            self.postDelayed(runnable, TripleShotTeamCourtView.TEAM_FRAME_MS)
            return
        }
        let now = self.gameTime()
        self.updateActors(now: now)
        if self.looseBall { self.updateLooseBall(now: now) }
        self.refreshLiveFacing(now: now)
        self.invalidate()
        self.postDelayed(runnable, TripleShotTeamCourtView.TEAM_FRAME_MS)
    })

    // L446 (Kotlin declares it after the init block; it is created before any use either way).
    let actionHandler = AHandler(ALooper.getMainLooper())

    // L3573 (part 2 range): `Pair<Int, Int>?` of the league label colours (own, rival).
    var leagueLabelColors: (first: Int, second: Int)? = nil

    // L3612-3615 (part 2 range): presentation-only timers and points (System.nanoTime based).
    var premiumScoredAt: Int64 = 0
    var premiumScoredPosition = CourtPoint(x: 0, y: 3.35, z: 0)
    var premiumLooseAt: Int64 = 0
    var premiumLooseOrigin = CourtPoint(x: 0, y: 0.21, z: 0)

    /// `TripleShotTeamCourtView(context, attrs)` (programmatic only).
    override init() {
        random = KotlinRandom(seed: seed)
        super.init()
        // L421-425
        isClickable = true
        isFocusable = true
        post(aiRunnable)
    }

    required convenience init?(coder: NSCoder) {
        self.init()
    }

    // `drawsInTraversal` (onDraw from the Choreographer traversal with a no-op canvas) is already `true` in
    // TripleShotWorldHostView, so the snapshot-building onDraw below runs once per vsync like Android's.

    override func onSizeChanged(_ w: Int, _ h: Int, _ oldw: Int, _ oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        if w <= 0 || h <= 0 || actors.isEmpty { return }
        if possession == nil {
            // configure() can run before layout, when the visible center-crop corridor is unknown.
            // Recompute the role formation once real dimensions exist instead of clamping two
            // different role homes onto the same screen edge.
            placeInitialRoleFormation(team: Team.HUMAN, attacking: true)
            placeInitialRoleFormation(team: Team.OPPONENT, attacking: false)
        } else {
            for actor in actors { clampActorToPlayableArea(actor: actor) }
        }
        // Rotation / window resize must not reset the live camera to a fresh snap. Preserve the
        // current source-space focus and let the normal easing adapt it to the new aspect ratio.
        let hadCamera = cameraInitialized
        updateCamera(force: !hadCamera)
        if !ballInFlight && !looseBall { updateHeldBall() }
    }

    /// L3583 `override fun onDraw(canvas)`: the body (snapshot build + present) is `onDraw_impl` in part 2.
    override func onDraw(_ canvas: ACanvas) {
        onDraw_impl(canvas)
    }

    func setListener(listener: Listener?) {
        self.listener = listener
    }

    /// Kotlin positional call form `setListener(listener)`.
    func setListener(_ listener: Listener?) {
        setListener(listener: listener)
    }

    /**
     * Team mode is calibrated against the real two-basket Sunset source. Until another court has
     * matching full-court geometry we deliberately keep team physics on this artwork instead of
     * pretending differently-oriented images share the same hoop coordinates.
     */
    func setCourtStyle(style: TripleShotCourtStyle) {
        let chosen: TripleShotCourtStyle
        if Self.TEAM_FULL_COURT_STYLE_IDS.contains(style.id) {
            chosen = style
        } else {
            chosen = TripleShotCourtCatalog.find(Self.FULL_COURT_STYLE_ID)
        }
        currentCourtStyleId = chosen.id
        courtAtmosphere = chosen.atmosphere
        invalidate()
    }

    /// Kotlin positional call form `setCourtStyle(style)`.
    func setCourtStyle(_ style: TripleShotCourtStyle) {
        setCourtStyle(style: style)
    }

    func geometryProfile() -> CourtGeometryProfile {
        switch currentCourtStyleId {
        case "neon_falls": return Self.NEON_FALLS_GEOMETRY
        default: return Self.SUNSET_GEOMETRY
        }
    }

    func topHoop() -> HoopGeometry { return geometryProfile().top }
    func bottomHoop() -> HoopGeometry { return geometryProfile().bottom }

    func attackingHoop(team: Team) -> HoopGeometry {
        return team == Team.HUMAN ? topHoop() : bottomHoop()
    }

    func defendingHoop(team: Team) -> HoopGeometry {
        return team == Team.HUMAN ? bottomHoop() : topHoop()
    }

    /** +1 means movement from the hoop toward mid-court goes down in source Y; -1 means up. */
    func towardCenterSign(hoop: HoopGeometry) -> Float {
        return hoop.footY < Self.FULL_COURT_CENTER_Y ? 1 : -1
    }

    func configure(
        teamSize: Int,
        humanCharacterId: String,
        teammateCharacterIds: [String],
        opponentCharacterIds: [String],
        seed: Int64
    ) {
        self.teamSize = teamSize.coerceIn(2, 3)
        self.seed = seed
        self.random = KotlinRandom(seed: seed)
        movementAt = 0
        // A consistent orange ball stays legible against patterned uniforms and neon scenery.
        currentBallSkinResId = R.drawable.basketball
        currentBallDrawable = nil
        actors.removeAll()

        var builtIds: [String] = []
        builtIds.append(humanCharacterId)
        builtIds.append(contentsOf: teammateCharacterIds)
        let humanIds: [String]
        if builtIds.count >= self.teamSize {
            humanIds = Array(builtIds.prefix(self.teamSize))
        } else {
            humanIds = builtIds + [String](repeating: TripleShotCharacterRoster.ID_WOMAN_DARK,
                                           count: self.teamSize - builtIds.count)
        }
        let opponentIds: [String]
        if opponentCharacterIds.count >= self.teamSize {
            opponentIds = Array(opponentCharacterIds.prefix(self.teamSize))
        } else {
            opponentIds = opponentCharacterIds + [String](repeating: TripleShotCharacterRoster.ID_WOMAN_DARK,
                                                          count: self.teamSize - opponentCharacterIds.count)
        }

        let humanSpots: [APointF]
        if self.teamSize == 2 {
            humanSpots = [APointF(834, 590), APointF(560, 510)]
        } else {
            humanSpots = [APointF(834, 590), APointF(560, 510), APointF(1050, 425)]
        }
        let opponentSpots: [APointF]
        if self.teamSize == 2 {
            opponentSpots = [APointF(834, 420), APointF(1110, 500)]
        } else {
            opponentSpots = [APointF(834, 420), APointF(1110, 500), APointF(620, 585)]
        }

        for (index, id) in humanIds.enumerated() {
            actors.append(Actor(
                id: "H\(index)",
                team: Team.HUMAN,
                characterId: id,
                profile: TripleShotCharacterRoster.find(id: id) ?? TripleShotCharacterRoster.womanDark,
                x: humanSpots[index].x,
                y: humanSpots[index].y,
                controlled: index == 0
            ))
        }
        for (index, id) in opponentIds.enumerated() {
            actors.append(Actor(
                id: "O\(index)",
                team: Team.OPPONENT,
                characterId: id,
                profile: TripleShotCharacterRoster.find(id: id) ?? TripleShotCharacterRoster.womanDark,
                x: opponentSpots[index].x,
                y: opponentSpots[index].y
            ))
        }

        assignTeamRoles(team: Team.HUMAN)
        assignTeamRoles(team: Team.OPPONENT)
        placeInitialRoleFormation(team: Team.HUMAN, attacking: true)
        placeInitialRoleFormation(team: Team.OPPONENT, attacking: false)

        activeHumanActorId = "H0"
        possession = nil
        possessionStartedAt = 0
        trackedHandlerId = nil
        trackedHandlerSince = 0
        defendingTeam = nil
        activeDefenseScheme = DefenseScheme.MAN_TO_MAN
        defensiveAssignments.clear()
        lastGuidance = nil
        ballVisible = false
        ballInFlight = false
        ballFlightKind = BallFlightKind.NONE
        looseBall = false
        resetTouchInteractionState(restoreActorMotion: false)
        cameraInitialized = false
        updateCamera(force: true)
        invalidate()
    }

    /// Kotlin positional call form `configure(teamSize, human, teammates, opponents, seed)`.
    func configure(_ teamSize: Int, _ humanCharacterId: String, _ teammateCharacterIds: [String],
                   _ opponentCharacterIds: [String], _ seed: Int64) {
        configure(teamSize: teamSize, humanCharacterId: humanCharacterId, teammateCharacterIds: teammateCharacterIds,
                  opponentCharacterIds: opponentCharacterIds, seed: seed)
    }

    /** Current role + defensive responsibility for the player the user is controlling now. */
    func humanGuidance() -> HumanGuidance {
        let human = actors.first(where: { $0.id == activeHumanActorId })
            ?? actors.first(where: { $0.id == "H0" })
        var matchup: Actor? = nil
        if let id = defensiveAssignments["H0"] {
            matchup = actors.first(where: { $0.id == id })
        }
        if matchup == nil, let human = human {
            matchup = previewMatchupFor(defender: human)
        }
        return HumanGuidance(
            role: human?.role ?? TeamRole.POINT_GUARD,
            matchupName: matchup?.profile.displayName,
            defenseScheme: defendingTeam == Team.HUMAN ? activeDefenseScheme : DefenseScheme.MAN_TO_MAN
        )
    }

    /**
     * Role selection is rating-driven, not roster-order-driven. We intentionally keep it soft:
     * every roster can still fill every slot, but a strong handler becomes PG, a versatile scorer
     * tends to become the wing, and size/strength/jump/inside play push a player toward INTERIOR.
     */
    func assignTeamRoles(team: Team) {
        let teamActors = actors.filter { $0.team == team }
        if teamActors.isEmpty { return }

        guard let pointGuard = teamActors.kMaxBy({ pointGuardRoleScore(actor: $0) }) else { return }
        pointGuard.role = TeamRole.POINT_GUARD

        let remaining = teamActors.filter { $0.id != pointGuard.id }
        if remaining.isEmpty { return }

        if teamActors.count == 2 {
            let other = remaining.first!
            if interiorRoleScore(actor: other) > wingRoleScore(actor: other) + 4 {
                other.role = TeamRole.INTERIOR
            } else {
                other.role = TeamRole.WING
            }
            return
        }

        let interior = remaining.kMaxBy({ interiorRoleScore(actor: $0) }) ?? remaining.last!
        interior.role = TeamRole.INTERIOR
        for wing in remaining.filter({ $0.id != interior.id }) { wing.role = TeamRole.WING }
    }

    func pointGuardRoleScore(actor: Actor) -> Float {
        let r = actor.profile.ratings
        var score: Float = r.ballHandling.toFloat() * 0.31
        score = score + passingSkillProxy(actor: actor) * 100 * 0.23
        score = score + r.agility.toFloat() * 0.18
        score = score + r.speed.toFloat() * 0.12
        score = score + r.offense.toFloat() * 0.10
        score = score + r.threePoint.toFloat() * 0.06
        score = score - r.height.toFloat() * 0.03
        return score
    }

    func wingRoleScore(actor: Actor) -> Float {
        let r = actor.profile.ratings
        var score: Float = r.threePoint.toFloat() * 0.22
        score = score + r.midRange.toFloat() * 0.19
        score = score + r.offense.toFloat() * 0.18
        score = score + r.agility.toFloat() * 0.14
        score = score + r.speed.toFloat() * 0.10
        score = score + r.height.toFloat() * 0.10
        score = score + r.ballHandling.toFloat() * 0.07
        return score
    }

    func interiorRoleScore(actor: Actor) -> Float {
        let r = actor.profile.ratings
        var score: Float = r.height.toFloat() * 0.24
        score = score + r.strength.toFloat() * 0.18
        score = score + r.inside.toFloat() * 0.20
        score = score + r.jumping.toFloat() * 0.16
        score = score + r.blocking.toFloat() * 0.10
        score = score + r.dunking.toFloat() * 0.08
        score = score + r.defense.toFloat() * 0.04
        return score
    }

    func reboundSkillProxy(actor: Actor) -> Float {
        let r = actor.profile.ratings
        var sum: Float = r.jumping.toFloat() * 0.33
        sum = sum + r.height.toFloat() * 0.25
        sum = sum + r.strength.toFloat() * 0.18
        sum = sum + r.inside.toFloat() * 0.10
        sum = sum + r.defense.toFloat() * 0.08
        sum = sum + r.agility.toFloat() * 0.06
        return sum / 100
    }

    /**
     * Full-court half-court spacing. Homes are derived from the basket a team is currently
     * attacking/defending, so the same AI works at both ends instead of walking everybody toward
     * the old portrait coordinates.
     */
    func roleHomeSpot(team: Team, role: TeamRole, attacking: Bool) -> APointF {
        let hoop = attacking ? attackingHoop(team: team) : defendingHoop(team: team)
        let towardCenter = towardCenterSign(hoop: hoop)
        let mirror: Float = team == Team.HUMAN ? 1 : -1
        let lateral: Float
        switch role {
        case .POINT_GUARD: lateral = 0
        // 3v3 needs real width, but the old 285/215 source offsets pushed teammates completely
        // outside the action camera once the far-hoop zoom became useful. Keep a compact
        // half-court triangle so the passer can still SEE both options without bunching them.
        case .WING: lateral = -205 * mirror
        case .INTERIOR: lateral = 165 * mirror
        }
        let depth: Float
        if attacking {
            switch role {
            case .POINT_GUARD: depth = 285
            case .WING: depth = 205
            case .INTERIOR: depth = 120
            }
        } else {
            switch role {
            case .POINT_GUARD: depth = 220
            case .WING: depth = 165
            case .INTERIOR: depth = 98
            }
        }
        return clampPointToPlayable(point: APointF(hoop.footX + lateral, hoop.footY + towardCenter * depth))
    }

    func placeInitialRoleFormation(team: Team, attacking: Bool) {
        for actor in actors.filter({ $0.team == team }) {
            let home = roleHomeSpot(team: team, role: actor.role, attacking: attacking)
            actor.x = home.x
            actor.y = home.y
            clampActorToPlayableArea(actor: actor)
        }
    }

    /**
     * A made basket is a dead-ball restart, not a continuation under the rim where the last play
     * ended. Whoever earns the next possession starts from THEIR own basket and must bring the ball
     * through the court again. This also applies when a knowledge question awards the ball back to
     * the team that just scored.
     */
    func placeDeadBallRestartFormation(team: Team, handler: Actor) {
        let ownHoop = defendingHoop(team: team)
        let towardCenter = towardCenterSign(hoop: ownHoop)

        // Ball-handler starts just inside the court beneath their own basket.
        handler.x = ownHoop.footX
        handler.y = ownHoop.footY + towardCenter * 72
        handler.vx = 0
        handler.vy = 0
        handler.motion = TripleShotPlayerRenderer.Motion.DRIBBLE
        clampActorToPlayableArea(actor: handler)

        let offenseMates = actors.filter { $0.team == team && $0.id != handler.id }
        for (index, mate) in offenseMates.enumerated() {
            let side: Float = index % 2 == 0 ? -1 : 1
            let lane: Float = 150 + index.toFloat() * 58
            mate.x = ownHoop.footX + side * (155 + index.toFloat() * 44)
            mate.y = ownHoop.footY + towardCenter * lane
            mate.vx = 0
            mate.vy = 0
            mate.motion = TripleShotPlayerRenderer.Motion.IDLE
            clampActorToPlayableArea(actor: mate)
        }

        // The defense resets to its half-court shell instead of remaining under the previous rim.
        for defender in actors.filter({ $0.team != team }) {
            let home = roleHomeSpot(team: defender.team, role: defender.role, attacking: false)
            defender.x = home.x
            defender.y = home.y
            defender.vx = 0
            defender.vy = 0
            defender.motion = TripleShotPlayerRenderer.Motion.IDLE
            clampActorToPlayableArea(actor: defender)
        }

        for mate in offenseMates {
            mate.facing = stableIdleFacingTowardPoint(actor: mate, targetX: handler.x, targetY: handler.y)
        }
    }

    func previewMatchupFor(defender: Actor) -> Actor? {
        let opponents = actors.filter { $0.team != defender.team }
        return opponents.first(where: { $0.role == defender.role })
            ?? opponents.kMinBy({ distance(a: defender, b: $0) })
    }

    /**
     * Build a stable defensive plan once per possession. Man-to-man is the default. A 3v3 team can
     * occasionally pack the paint when the opponent selected two genuine interior threats.
     */
    func prepareDefenseForPossession(offenseTeam: Team, now: Int64) {
        defendingTeam = offenseTeam == Team.HUMAN ? Team.OPPONENT : Team.HUMAN
        activeDefenseScheme = chooseDefenseScheme(defenseTeam: defendingTeam ?? Team.OPPONENT, offenseTeam: offenseTeam)
        rebuildDefensiveAssignments(offenseTeam: offenseTeam)
        for defender in actors.filter({ $0.team == defendingTeam }) {
            defender.screenedUntil = 0
            defender.lastStealAttempt = now - Self.TEAM_STEAL_RETRY_MS
        }
        if defendingTeam == Team.HUMAN { notifyHumanGuidanceIfChanged() }
    }

    func chooseDefenseScheme(defenseTeam: Team, offenseTeam: Team) -> DefenseScheme {
        if teamSize < 3 { return DefenseScheme.MAN_TO_MAN }

        /*
         * A zone is useful only when it owns real floor responsibilities. The current 2-1 shell keeps
         * three DISTINCT anchors and always promotes the closest zone defender to the live ball. Use it
         * selectively rather than every possession. (The comment's "human team zones less often" is not
         * implemented on Android: both teams use the same chance.)
         */
        let offense = actors.filter { $0.team == offenseTeam }
        let paintThreats = offense.filter { interiorThreatScore(actor: $0) >= 0.64 }.count
        let perimeterThreats = offense.filter {
            max($0.profile.ratings.midRange, $0.profile.ratings.threePoint) >= 80
        }.count
        let zoneChance: Float
        if paintThreats >= 2 && perimeterThreats <= 1 {
            zoneChance = 0.42
        } else if paintThreats >= 1 {
            zoneChance = 0.24
        } else {
            zoneChance = 0.14
        }
        return random.nextFloat() < zoneChance ? DefenseScheme.ZONE : DefenseScheme.MAN_TO_MAN
    }

    func interiorThreatScore(actor: Actor) -> Float {
        let r = actor.profile.ratings
        var sum: Float = r.height.toFloat() * 0.21
        sum = sum + r.strength.toFloat() * 0.19
        sum = sum + r.inside.toFloat() * 0.22
        sum = sum + r.dunking.toFloat() * 0.14
        sum = sum + r.jumping.toFloat() * 0.14
        sum = sum + r.offense.toFloat() * 0.10
        return sum / 100
    }

    /** Stable one-to-one responsibilities are retained even while a zone is used as the shell. */
    func rebuildDefensiveAssignments(offenseTeam: Team) {
        defensiveAssignments.clear()
        var offense = actors.filter { $0.team == offenseTeam }
        let defenders = actors.filter { $0.team != offenseTeam }
        if offense.isEmpty || defenders.isEmpty { return }

        func matchupCost(defender: Actor, candidate: Actor) -> Float {
            let rolePenalty: Float
            if defender.role == candidate.role {
                rolePenalty = 0
            } else if defender.role == TeamRole.WING || candidate.role == TeamRole.WING {
                rolePenalty = 46
            } else {
                rolePenalty = 78
            }
            let d = defender.profile.ratings
            let c = candidate.profile.ratings
            let sizePenalty: Float
            if candidate.role == TeamRole.INTERIOR {
                let heightGap: Float = abs(d.height - c.height).toFloat() * 0.75
                sizePenalty = heightGap + abs(d.strength - c.strength).toFloat() * 0.35
            } else {
                let agilityGap: Float = abs(d.agility - c.agility).toFloat() * 0.32
                sizePenalty = agilityGap + abs(d.speed - c.speed).toFloat() * 0.24
            }
            let fixed: Float = rolePenalty + sizePenalty
            return fixed + distance(a: defender, b: candidate) * 0.11
        }

        // The controlled human receives the most intuitive role-matched assignment first.
        if let controlled = defenders.first(where: { $0.controlled }) {
            let target = offense.kMinBy({ matchupCost(defender: controlled, candidate: $0) })
            if let target = target {
                defensiveAssignments[controlled.id] = target.id
                if let index = offense.firstIndex(where: { $0 === target }) { offense.remove(at: index) }
            }
        }

        let ordered = defenders
            .filter { !$0.controlled }
            .kSortedByDescending { $0.profile.ratings.defense * 2 + $0.profile.ratings.agility }
        for defender in ordered {
            guard let target = offense.kMinBy({ matchupCost(defender: defender, candidate: $0) }) else { continue }
            defensiveAssignments[defender.id] = target.id
            if let index = offense.firstIndex(where: { $0 === target }) { offense.remove(at: index) }
        }
    }

    /// Kotlin `Map<String, Actor>` built with `toMap()` (a LinkedHashMap): defenderId -> offense actor, in the
    /// insertion order of `defensiveAssignments` (part 2 iterates it).
    func assignmentActors() -> KLinkedMap<String, Actor> {
        var result = KLinkedMap<String, Actor>()
        for (defenderId, offenseId) in defensiveAssignments {
            if let actor = actors.first(where: { $0.id == offenseId }) {
                result[defenderId] = actor
            }
        }
        return result
    }

    func notifyHumanGuidanceIfChanged(force: Bool = false) {
        let guidance = humanGuidance()
        if !force && guidance == lastGuidance { return }
        lastGuidance = guidance
        listener?.onHumanGuidanceChanged(guidance: guidance)
    }

    /**
     * A screen can trigger a normal basketball switch. The team with the local human deliberately
     * switches less often, unless the screened defender is badly beaten, so controls stay learnable.
     */
    func maybeSwitchAssignmentsForScreen(
        screener: Actor,
        ballHandler: Actor,
        screenedDefender: Actor,
        now: Int64
    ) {
        if activeDefenseScheme == DefenseScheme.ZONE { return }
        let defense = screenedDefender.team
        if defense != defendingTeam { return }

        guard let screenerDefenderEntry = defensiveAssignments.entries.first(where: { $0.value == screener.id })
        else { return }
        guard let screenerDefender = actors.first(where: { $0.id == screenerDefenderEntry.key }) else { return }
        if screenerDefender.id == screenedDefender.id { return }

        let handlerEntry = defensiveAssignments.entries.first(where: { $0.value == ballHandler.id })
        if handlerEntry?.key != screenedDefender.id { return }

        let probability = BasketballMoves.switchChance(defense: screenerDefender.profile.ratings.defense)
        if random.nextFloat() >= probability {
            screenerDefender.screenedUntil = now + 1000 + random.nextInt(1001).toLong()
            return
        }

        defensiveAssignments[screenedDefender.id] = screener.id
        defensiveAssignments[screenerDefender.id] = ballHandler.id
        if defense == Team.HUMAN { notifyHumanGuidanceIfChanged() }
    }

    func actorSnapshots() -> [ActorSnapshot] {
        return actors.map {
            ActorSnapshot(
                id: $0.id,
                team: $0.team,
                characterId: $0.characterId,
                sourceX: $0.x,
                sourceY: $0.y,
                hasBall: $0.hasBall,
                controlled: $0.controlled,
                boost01: $0.boost01
            )
        }
    }

    /**
     * Lightweight source-space snapshot used only as a safety net when an integrating Activity
     * recreates us during a portrait/landscape change. The normal path uses configChanges and never
     * needs this, but a host app is allowed to have different manifest flags.
     */
    func saveRuntimeState() -> ABundle {
        let b = ABundle()
        b.putString("possession", possession?.name)
        b.putString("activeHumanActorId", activeHumanActorId)
        b.putLong("possessionStartedAt", possessionStartedAt)
        b.putString("trackedHandlerId", trackedHandlerId)
        b.putLong("trackedHandlerSince", trackedHandlerSince)
        b.putString("defendingTeam", defendingTeam?.name)
        b.putString("defenseScheme", activeDefenseScheme.name)

        b.putBoolean("ballVisible", ballVisible)
        b.putBoolean("ballInFlight", ballInFlight)
        b.putBoolean("looseBall", looseBall)
        b.putFloat("ballSourceX", ballSourceX)
        b.putFloat("ballSourceY", ballSourceY)
        b.putFloat("ballCameraFocusX", ballCameraFocusX)
        b.putFloat("ballCameraFocusY", ballCameraFocusY)
        b.putFloat("looseVxSource", looseVxSource)
        b.putFloat("looseVySource", looseVySource)
        // Android stores the Int resource id; iOS drawable ids are names (never read back, see the header).
        b.putString("ballSkinResId", currentBallSkinResId)

        b.putFloat("cameraCenterX", cameraCenterX)
        b.putFloat("cameraCenterY", cameraCenterY)
        b.putFloat("cameraZoom", cameraZoom)
        b.putBoolean("cameraInitialized", cameraInitialized)

        b.putStringArrayList("assignmentKeys", defensiveAssignments.keys)
        b.putStringArrayList("assignmentValues", defensiveAssignments.keys.compactMap { defensiveAssignments[$0] })

        b.putInt("actorCount", actors.count)
        for (index, actor) in actors.enumerated() {
            let k = "a\(index)_"
            b.putString(k + "id", actor.id)
            b.putFloat(k + "x", actor.x)
            b.putFloat(k + "y", actor.y)
            b.putFloat(k + "vx", actor.vx)
            b.putFloat(k + "vy", actor.vy)
            b.putBoolean(k + "hasBall", actor.hasBall)
            b.putBoolean(k + "controlled", actor.controlled)
            b.putString(k + "facing", actor.facing.name)
            b.putString(k + "motion", actor.motion.name)
            b.putBoolean(k + "mirror", actor.mirror)
            b.putFloat(k + "dribblePhase", actor.dribblePhase)
            b.putFloat(k + "dribbleBounce", actor.dribbleBounce)
            b.putFloat(k + "dribbleHandSign", actor.dribbleHandSign)
            b.putFloat(k + "jumpPx", actor.jumpPx)
            b.putLong(k + "jumpStarted", actor.jumpStarted)
            b.putLong(k + "jumpUntil", actor.jumpUntil)
            b.putLong(k + "screenedUntil", actor.screenedUntil)
            b.putString(k + "screenTargetId", actor.screenTargetId)
            b.putFloat(k + "boost01", actor.boost01)
            b.putLong(k + "cutUntil", actor.cutUntil)
            b.putLong(k + "lastAiDecision", actor.lastAiDecision)
            b.putLong(k + "lastStealAttempt", actor.lastStealAttempt)
            b.putLong(k + "screenCooldownUntil", actor.screenCooldownUntil)
            b.putString(k + "role", actor.role.name)
            b.putLong(k + "possessionReceivedAt", actor.possessionReceivedAt)
            b.putLong(k + "lastReboundClaimAt", actor.lastReboundClaimAt)
            b.putLong(k + "actionLockUntil", actor.actionLockUntil)
            b.putLong(k + "fakeBurstUntil", actor.fakeBurstUntil)
            b.putFloat(k + "fakeBurstSign", actor.fakeBurstSign)
            b.putLong(k + "lastMoveUpdate", actor.lastMoveUpdate)
            b.putLong(k + "lastMeaningfulMovementAt", actor.lastMeaningfulMovementAt)
        }
        return b
    }

    func restoreRuntimeState(state: ABundle) -> Bool {
        if actors.isEmpty { return false }
        cancelBallAnimator()
        resetTouchInteractionState(restoreActorMotion: false)

        let savedCount = state.getInt("actorCount", -1)
        if savedCount != actors.count { return false }

        for index in kuntil(0, savedCount) {
            let k = "a\(index)_"
            guard let id = state.getString(k + "id") else { return false }
            guard let actor = actors.first(where: { $0.id == id }) else { return false }
            actor.x = state.getFloat(k + "x", actor.x)
            actor.y = state.getFloat(k + "y", actor.y)
            actor.vx = state.getFloat(k + "vx", 0)
            actor.vy = state.getFloat(k + "vy", 0)
            actor.hasBall = state.getBoolean(k + "hasBall", false)
            actor.controlled = state.getBoolean(k + "controlled", false)
            actor.facing = TripleShotPlayerRenderer.Facing.named(state.getString(k + "facing") ?? "") ?? actor.facing
            actor.motion = TripleShotPlayerRenderer.Motion.named(state.getString(k + "motion") ?? "") ?? actor.motion
            actor.mirror = state.getBoolean(k + "mirror", actor.mirror)
            actor.dribblePhase = state.getFloat(k + "dribblePhase", 0)
            actor.dribbleBounce = state.getFloat(k + "dribbleBounce", 0)
            actor.dribbleHandSign = state.getFloat(k + "dribbleHandSign", 1)
            actor.jumpPx = state.getFloat(k + "jumpPx", 0)
            actor.jumpStarted = state.getLong(k + "jumpStarted", 0)
            actor.jumpUntil = state.getLong(k + "jumpUntil", 0)
            actor.screenedUntil = state.getLong(k + "screenedUntil", 0)
            actor.screenTargetId = state.getString(k + "screenTargetId")
            actor.boost01 = state.getFloat(k + "boost01", 0)
            actor.cutUntil = state.getLong(k + "cutUntil", 0)
            actor.lastAiDecision = state.getLong(k + "lastAiDecision", 0)
            actor.lastStealAttempt = state.getLong(k + "lastStealAttempt", 0)
            actor.screenCooldownUntil = state.getLong(k + "screenCooldownUntil", 0)
            actor.role = TeamRole.named(state.getString(k + "role") ?? "") ?? actor.role
            actor.possessionReceivedAt = state.getLong(k + "possessionReceivedAt", 0)
            actor.lastReboundClaimAt = state.getLong(k + "lastReboundClaimAt", 0)
            actor.actionLockUntil = state.getLong(k + "actionLockUntil", 0)
            actor.fakeBurstUntil = state.getLong(k + "fakeBurstUntil", 0)
            actor.fakeBurstSign = state.getFloat(k + "fakeBurstSign", 0)
            actor.lastMoveUpdate = state.getLong(k + "lastMoveUpdate", 0)
            actor.lastMeaningfulMovementAt = state.getLong(k + "lastMeaningfulMovementAt", actor.possessionReceivedAt)
            clampActorToPlayableArea(actor: actor)
        }

        possession = state.getString("possession").flatMap { Team.named($0) }
        activeHumanActorId = state.getString("activeHumanActorId") ?? activeHumanActorId
        possessionStartedAt = state.getLong("possessionStartedAt", 0)
        trackedHandlerId = state.getString("trackedHandlerId")
        trackedHandlerSince = state.getLong("trackedHandlerSince", 0)
        defendingTeam = state.getString("defendingTeam").flatMap { Team.named($0) }
        activeDefenseScheme = DefenseScheme.named(state.getString("defenseScheme") ?? "") ?? DefenseScheme.MAN_TO_MAN

        defensiveAssignments.clear()
        let keys = state.getStringArrayList("assignmentKeys") ?? []
        let values = state.getStringArrayList("assignmentValues") ?? []
        for (key, value) in zip(keys, values) { defensiveAssignments[key] = value }

        ballVisible = state.getBoolean("ballVisible", false)
        ballSourceX = state.getFloat("ballSourceX", Self.FULL_COURT_CENTER_X)
        ballSourceY = state.getFloat("ballSourceY", Self.FULL_COURT_CENTER_Y)
        ballCameraFocusX = state.getFloat("ballCameraFocusX", ballSourceX)
        ballCameraFocusY = state.getFloat("ballCameraFocusY", ballSourceY)
        looseVxSource = state.getFloat("looseVxSource", 0)
        looseVySource = state.getFloat("looseVySource", 0)
        currentBallSkinResId = R.drawable.basketball
        currentBallDrawable = nil

        // A ValueAnimator itself cannot survive Activity recreation. If rotation happened during a
        // pass/shot, continue from that exact ball position as a loose ball instead of restarting
        // the entire match or freezing an orphaned airborne ball forever.
        let wasInFlight = state.getBoolean("ballInFlight", false)
        looseBall = state.getBoolean("looseBall", false) || wasInFlight
        ballInFlight = false
        ballFlightKind = BallFlightKind.NONE
        if wasInFlight && abs(looseVxSource) < 0.01 && abs(looseVySource) < 0.01 {
            looseVySource = 45
        }
        looseLastNanos = ASystem.nanoTime()

        cameraCenterX = state.getFloat("cameraCenterX", Self.FULL_COURT_CENTER_X)
        cameraCenterY = state.getFloat("cameraCenterY", Self.FULL_COURT_CENTER_Y)
        cameraZoom = state.getFloat("cameraZoom", Self.QUESTION_CAMERA_ZOOM)
        cameraInitialized = state.getBoolean("cameraInitialized", true)

        for human in actors.filter({ $0.team == Team.HUMAN }) {
            human.controlled = human.id == activeHumanActorId
        }

        if ballVisible {
            if looseBall { syncBallViewFromSource() } else { updateHeldBall() }
        }
        refreshLiveFacing(now: gameTime())
        if let possession = possession { listener?.onPossessionChanged(team: possession) }
        invalidate()
        return true
    }

    /// Kotlin positional call form `restoreRuntimeState(state)`.
    func restoreRuntimeState(_ state: ABundle) -> Bool {
        return restoreRuntimeState(state: state)
    }

    func setActorBoost(actorId: String, boost01: Float) {
        actors.first(where: { $0.id == actorId })?.boost01 = boost01.coerceIn(0, 0.35)
    }

    /// Kotlin positional call form `setActorBoost(id, boost)`.
    func setActorBoost(_ actorId: String, _ boost01: Float) {
        setActorBoost(actorId: actorId, boost01: boost01)
    }

    func humanActorIds() -> [String] { return actors.filter { $0.team == Team.HUMAN }.map { $0.id } }
    func opponentActorIds() -> [String] { return actors.filter { $0.team == Team.OPPONENT }.map { $0.id } }

    func startPossession(team: Team, restartFromOwnBaseline: Bool = false) {
        cancelBallAnimator()
        resetTouchInteractionState()
        looseBall = false
        ballInFlight = false
        ballFlightKind = BallFlightKind.NONE
        for actor in actors {
            actor.hasBall = false
            actor.screenTargetId = nil
            actor.cutUntil = 0
            actor.actionLockUntil = 0
            actor.fakeBurstUntil = 0
            actor.travelScale = 0
            actor.returnPassId = nil
            actor.screenPlantedAt = 0
            actor.screenHoldUntil = 0
        }
        possession = team
        requestedPracticeScreens.clear()
        let now = gameTime()
        possessionStartedAt = now

        let handler: Actor
        if team == Team.HUMAN {
            // Local play deliberately starts with the real player whenever their team wins the
            // question. That keeps the human involved even if their basketball role is not PG.
            handler = actors.first(where: { $0.id == "H0" })
                ?? actors.first(where: { $0.id == activeHumanActorId && $0.team == Team.HUMAN })
                ?? actors.first(where: { $0.team == Team.HUMAN })!
        } else {
            // Structured possessions start through the assigned point guard instead of handing the
            // ball to whichever bot happened to stand nearest the rim.
            handler = actors.first(where: { $0.team == Team.OPPONENT && $0.role == TeamRole.POINT_GUARD })
                ?? actors.first(where: { $0.team == Team.OPPONENT })!
        }
        if restartFromOwnBaseline {
            placeDeadBallRestartFormation(team: team, handler: handler)
        }

        handler.hasBall = true
        handler.possessionReceivedAt = now
        handler.lastMeaningfulMovementAt = now
        // A new ball-handler must face the basket they are ACTUALLY attacking immediately.
        handler.facing = facingTowardAttackingHoop(actor: handler)
        trackedHandlerId = handler.id
        trackedHandlerSince = now
        if team == Team.HUMAN { setControlled(id: handler.id) }

        prepareDefenseForPossession(offenseTeam: team, now: now)
        ballVisible = true
        updateCamera(force: !cameraInitialized)
        updateHeldBall()
        listener?.onPossessionChanged(team: team)
        invalidate()
    }

    /// Kotlin positional call form `startPossession(team, restartFromOwnBaseline = ...)`.
    func startPossession(_ team: Team, restartFromOwnBaseline: Bool = false) {
        startPossession(team: team, restartFromOwnBaseline: restartFromOwnBaseline)
    }

    func clearForQuestion() {
        cancelBallAnimator()
        resetTouchInteractionState()
        pendingShotActor = nil
        possessionStartedAt = 0
        lastLiveTick = 0
        possession = nil
        looseBall = false
        ballInFlight = false
        ballFlightKind = BallFlightKind.NONE
        ballVisible = false
        for actor in actors {
            actor.hasBall = false
            actor.motion = TripleShotPlayerRenderer.Motion.IDLE
        }
        // Keep the last live camera framing while the question is on screen. Resetting to 1x here
        // made every dead-ball question suddenly reveal the whole court and hid the sense of travel.
        if !cameraInitialized {
            cameraCenterX = Self.FULL_COURT_CENTER_X
            cameraCenterY = Self.FULL_COURT_CENTER_Y
            cameraZoom = Self.QUESTION_CAMERA_ZOOM
            cameraInitialized = true
        }
        listener?.onShotQuality(percent: 0, visible: false)
        invalidate()
    }

    override func onAttachedToWindow() {
        super.onAttachedToWindow()
        removeCallbacks(aiRunnable)
        post(aiRunnable)
    }

    override func onDetachedFromWindow() {
        actionHandler.removeCallbacksAndMessages(nil)
        removeCallbacks(aiRunnable)
        resetTouchInteractionState()
        cancelBallAnimator()
        super.onDetachedFromWindow()
    }

    /**
     * Team-game input contract.
     *
     * SWIPE has first priority and moves the currently controlled human on offense, defense,
     * during a pass/shot flight, and while chasing a loose ball. A gesture is classified as a
     * swipe by its TOTAL distance from ACTION_DOWN, not by one tiny MOVE-event delta.
     *
     * Existing team interactions remain intact:
     * - tap teammate -> pass (or defensive switch),
     * - double tap teammate -> alley-oop,
     * - long press teammate -> screen,
     * - stationary hold on empty court while owning the ball -> shot gather/release.
     *
     * Two-finger shooting is also preserved: the primary finger may keep moving while a second
     * finger holds the shot. Only a same-finger hold is cancelled when that finger turns into
     * a swipe.
     */
    override func onTouchEvent(_ event: AMotionEvent) -> Bool {
        if pauseAt > 0 { return true }
        _ = gestureDetector.onTouchEvent(event)

        // Questions/dead transitions deliberately freeze court control. Ball flight and loose-ball
        // phases do NOT freeze movement: those are exactly the moments when rebounding/rotation
        // movement matters.
        if possession == nil {
            if event.actionMasked == AMotionEvent.ACTION_UP || event.actionMasked == AMotionEvent.ACTION_CANCEL {
                resetTouchInteractionState()
            }
            return true
        }

        switch event.actionMasked {
        case AMotionEvent.ACTION_DOWN:
            ALog.d("TRIPLE_INPUT", "team down x=\(javaString(event.x)) y=\(javaString(event.y)) possession=\(possession?.name ?? "null")")
            cancelPendingShotHold()

            dragPointerId = event.getPointerId(event.actionIndex)
            dragDownX = event.x
            dragDownY = event.y
            lastTouchX = event.x
            lastTouchY = event.y
            dragMoved = false
            humanMoveAt = gameTime()

            scheduleShotHold(pointerId: dragPointerId, x: event.x, y: event.y)
            return true

        case AMotionEvent.ACTION_POINTER_DOWN:
            /*
             * Preserve the existing two-finger gather: finger A can keep the player moving,
             * finger B can hold/release the shot. This path is intentionally disabled while
             * the ball is already travelling or loose.
             */
            if shotPointerId < 0 &&
                !shotHoldActive &&
                !ballInFlight &&
                !looseBall &&
                possession == Team.HUMAN &&
                currentBallHandler()?.team == Team.HUMAN {
                let index = event.actionIndex
                startShotHold(pointerId: event.getPointerId(index))
            }
            return true

        case AMotionEvent.ACTION_MOVE:
            let idx = event.findPointerIndex(dragPointerId)
            if idx >= 0 {
                let x = event.getX(idx)
                let y = event.getY(idx)
                let dx = x - lastTouchX
                let dy = y - lastTouchY

                let totalDx = x - dragDownX
                let totalDy = y - dragDownY
                let totalDistanceSq = totalDx * totalDx + totalDy * totalDy
                let movementSlopSq = movementTouchSlopPx * movementTouchSlopPx

                if !dragMoved && totalDistanceSq > movementSlopSq {
                    dragMoved = true
                    cancelPendingShotHold()

                    /*
                     * If the primary finger itself had become a stationary shot hold, movement
                     * wins immediately. A second-finger hold is NOT cancelled, so running shots
                     * remain possible.
                     */
                    if shotHoldActive && shotPointerId == dragPointerId {
                        cancelShotHoldForMovement()
                    }
                }

                if dragMoved {
                    let actor = actors.first(where: { $0.controlled })
                    if actor?.hasBall == true && !ballInFlight && !looseBall {
                        let spin = circularGesture.move(dx: dx, dy: dy, now: gameTime())
                        if spin != 0 { trySpin(actor: actor!, direction: spin, now: gameTime()); dribbleGesture.reset() }
                        else if dribbleGesture.move(dx: dx, now: gameTime()) != 0 { crossHands(actor: actor!, now: gameTime()) }
                    }
                    moveControlledBy(dxPx: dx, dyPx: dy)
                }

                lastTouchX = x
                lastTouchY = y
            }

            if shotHoldActive {
                updateShotMeter()
            }
            return true

        case AMotionEvent.ACTION_POINTER_UP:
            let pointerId = event.getPointerId(event.actionIndex)

            if pointerId == shotPointerId && shotHoldActive {
                releaseShot()
            }

            if pointerId == dragPointerId {
                dragPointerId = -1
            }
            return true

        case AMotionEvent.ACTION_UP:
            cancelPendingShotHold()
            let pointerId = event.getPointerId(event.actionIndex)

            /*
             * If the shot hold is still active here, it is valid to release. A same-finger
             * swipe would already have cancelled the hold inside ACTION_MOVE. This also keeps
             * the two-finger path correct if the movement finger was lifted before the shot
             * finger.
             */
            if shotHoldActive && pointerId == shotPointerId {
                releaseShot()
            }

            dragPointerId = -1
            dragMoved = false
            humanMoveAt = gameTime()
            stopControlledMovement()

            if !shotHoldActive {
                listener?.onShotQuality(percent: 0, visible: false)
            }
            return true

        case AMotionEvent.ACTION_CANCEL:
            stopControlledMovement()
            resetTouchInteractionState()
            return true

        default:
            break
        }

        return true
    }

    func scheduleShotHold(pointerId: Int, x: Float, y: Float) {
        cancelPendingShotHold()

        if possession != Team.HUMAN { return }
        if ballInFlight || looseBall || shotHoldActive { return }

        guard let handler = currentBallHandler() else { return }
        if handler.team != Team.HUMAN || handler.id != activeHumanActorId { return }

        // A teammate owns tap/pass/screen semantics. Holding on the CONTROLLED player itself is
        // still a valid shot gather, matching the freedom of the 1v1 control scheme.
        let touchedActor = actorAt(x: x, y: y)
        if let touchedActor = touchedActor, touchedActor.id != activeHumanActorId { return }

        let runnable = ARunnable { [weak self] in
            guard let self = self else { return }
            self.pendingShotRunnable = nil
            if !self.dragMoved &&
                self.dragPointerId == pointerId &&
                self.possession == Team.HUMAN &&
                !self.ballInFlight &&
                !self.looseBall {
                self.startShotHold(pointerId: pointerId)
            }
        }

        pendingShotRunnable = runnable
        postDelayed(runnable, Self.SHOT_HOLD_DELAY_MS)
    }

    func cancelPendingShotHold() {
        if let runnable = pendingShotRunnable { removeCallbacks(runnable) }
        pendingShotRunnable = nil
    }

    func startShotHold(pointerId: Int) {
        guard let handler = currentBallHandler() else { return }
        if handler.team != Team.HUMAN ||
            handler.id != activeHumanActorId ||
            ballInFlight ||
            looseBall { return }

        cancelPendingShotHold()
        shotPointerId = pointerId
        shotHoldActive = true
        shotHoldStarted = gameTime()
        handler.motion = TripleShotPlayerRenderer.Motion.SHOT_LOW
        // Gather first; the visible jump starts on release. Starting the jump at HOLD-begin made
        // long gathers land before the ball was actually released.
        updateShotMeter()
    }

    /**
     * A swipe must always beat a same-finger shot hold. This does NOT affect a second-finger
     * gather, because that is the intentional "run with one finger, shoot with the other" path.
     */
    func cancelShotHoldForMovement() {
        if !shotHoldActive { return }

        shotHoldActive = false
        shotPointerId = -1
        shotHoldStarted = 0

        if let handler = currentBallHandler(), handler.id == activeHumanActorId && handler.team == Team.HUMAN {
            handler.motion = handler.hasBall ? TripleShotPlayerRenderer.Motion.DRIBBLE
                : TripleShotPlayerRenderer.Motion.WALK
        }

        listener?.onShotQuality(percent: 0, visible: false)
        invalidate()
    }

    /**
     * Clears stale gesture/shot state at possession boundaries, question transitions and detach.
     * Keeping this centralized prevents an old hold from freezing the next possession.
     */
    func resetTouchInteractionState(restoreActorMotion: Bool = true) {
        cancelPendingShotHold()

        dragPointerId = -1
        dragDownX = 0
        dragDownY = 0
        lastTouchX = 0
        lastTouchY = 0
        dragMoved = false

        if shotHoldActive && restoreActorMotion {
            if let handler = currentBallHandler(), handler.id == activeHumanActorId && handler.team == Team.HUMAN {
                handler.motion = handler.hasBall ? TripleShotPlayerRenderer.Motion.DRIBBLE
                    : TripleShotPlayerRenderer.Motion.WALK
            }
        }

        shotPointerId = -1
        shotHoldStarted = 0
        shotHoldActive = false
        listener?.onShotQuality(percent: 0, visible: false)
    }

    func updateShotMeter() {
        if !shotHoldActive { return }
        guard let handler = currentBallHandler() else { return }
        let heldMs = (gameTime() - shotHoldStarted).coerceAtLeast(0)
        if heldMs < 280 {
            handler.motion = TripleShotPlayerRenderer.Motion.SHOT_LOW
        } else if heldMs < 620 {
            handler.motion = TripleShotPlayerRenderer.Motion.SHOT_MID
        } else {
            handler.motion = TripleShotPlayerRenderer.Motion.SHOT_SET
        }
        listener?.onShotQuality(percent: shotChance(actor: handler, heldMs: heldMs), visible: true)
    }

    func releaseShot() {
        if !shotHoldActive { return }

        let handler = currentBallHandler()
        let heldMs = (gameTime() - shotHoldStarted).coerceAtLeast(0)

        shotHoldActive = false
        shotPointerId = -1
        shotHoldStarted = 0
        listener?.onShotQuality(percent: 0, visible: false)

        // The handler can disappear only during an external possession transition; in that case
        // there is no valid shot to release, but the input state still needs to be clean.
        // (Android defect kept, spec 11 section 8.2 item 1: the handler is not re-checked to be the human.)
        if let handler = handler {
            let hoop = attackingHoop(team: handler.team)
            let nearRim = khypot((handler.x - hoop.footX) * 0.014, (handler.y - hoop.footY) * 0.034) < 2.65
            let movingRecently = gameTime() - handler.lastMeaningfulMovementAt < heldMs + 1100
            let finish: TripleShotPlayerRenderer.Motion?
            if nearRim && movingRecently && handler.profile.ratings.dunking >= 62 && contest01(shooter: handler) < 0.65 {
                finish = TripleShotPlayerRenderer.Motion.DUNK
            } else {
                finish = nil
            }
            shoot(actor: handler, chance: shotChance(actor: handler, heldMs: heldMs), finishMotion: finish)
        }
    }

    func shotChance(actor: Actor, heldMs: Int64) -> Int {
        let dist = distanceToHoop(a: actor)
        let rating: Int
        if dist < 165 {
            rating = actor.profile.ratings.inside
        } else if dist < 335 {
            rating = actor.profile.ratings.midRange
        } else {
            rating = actor.profile.ratings.threePoint
        }
        let readiness = (heldMs.toFloat() / 1000).coerceIn(0.45, 1)
        let contest = contest01(shooter: actor)
        let boost: Float = actor.boost01 * 8
        let base: Float = 25 + rating.toFloat() * 0.67
        let raw: Float = base * readiness - contest * 38 + boost
        return raw.toInt().coerceIn(8, 95)
    }

    func shoot(
        actor: Actor,
        chance: Int,
        finishMotion: TripleShotPlayerRenderer.Motion? = nil
    ) {
        if !actor.hasBall || pendingShotActor != nil || ballInFlight { return }
        pendingShotActor = actor.id
        actor.travelScale = 0
        actor.vx = 0; actor.vy = 0
        let now = gameTime()
        actor.actionLockUntil = now + 1100
        actor.motion = TripleShotPlayerRenderer.Motion.SHOT_LOW
        let hoop = attackingHoop(team: actor.team)
        let driving = khypot((actor.x - hoop.footX) * 0.014, (actor.y - hoop.footY) * 0.034) < 2.65 &&
            now - actor.lastMeaningfulMovementAt < 2200
        func gatherStep() {
            if !driving || !actor.hasBall || pendingShotActor != actor.id { return }
            let step = BasketballMovement.step(dx: hoop.footX - actor.x, dy: hoop.footY - actor.y,
                                               speed: actor.profile.ratings.speed,
                                               agility: actor.profile.ratings.agility, scale: 1, dtSeconds: 0.08)
            actor.x += step.x; actor.y += step.y; clampActorToPlayableArea(actor: actor); resolveActorCollisions(moved: actor)
        }
        gatherStep()
        postAction(action: { [self] in
            if pendingShotActor == actor.id && actor.hasBall {
                gatherStep(); actor.motion = TripleShotPlayerRenderer.Motion.SHOT_MID
            }
        }, delay: 110)
        postAction(action: { [self] in
            if pendingShotActor == actor.id && actor.hasBall {
                actor.motion = TripleShotPlayerRenderer.Motion.SHOT_SET
                beginActorJump(actor: actor, contested: contest01(shooter: actor) > 0.28)
            }
        }, delay: 230)
        postAction(action: { [self] in
            if pendingShotActor == actor.id && actor.hasBall && possession == actor.team {
                pendingShotActor = nil
                releaseCommittedShot(actor: actor, chance: chance, finishMotion: finishMotion)
            } else if pendingShotActor == actor.id {
                pendingShotActor = nil
            }
        }, delay: 470)
    }

    func releaseCommittedShot(actor: Actor, chance: Int, finishMotion: TripleShotPlayerRenderer.Motion?) {
        let humanRelease = actor.controlled && practiceAction != nil
        if humanRelease && chance >= 65 { practiceEvent(skill: BasketballSkill.RELEASE) }
        actor.hasBall = false
        actor.travelScale = 0
        actor.actionLockUntil = gameTime() + 900
        actor.motion = finishMotion ?? TripleShotPlayerRenderer.Motion.RELEASE
        possession = actor.team
        let shooterWorld = TripleShotWorldCoordinates.team(sourceX: actor.x, sourceY: actor.y)
        let hoopWorld = TripleShotWorldCoordinates.team(sourceX: attackingHoop(team: actor.team).footX,
                                                         sourceY: attackingHoop(team: actor.team).footY)
        let shotMeters = khypot(shooterWorld.x - hoopWorld.x, shooterWorld.z - hoopWorld.z)
        let isDunk = finishMotion == TripleShotPlayerRenderer.Motion.DUNK
        let made = random.nextInt(100) < chance
        ALog.i("TRIPLE_PLAY", "teamShot actor=\(actor.id) chance=\(chance) made=\(made)")
        let startSource = heldBallSourceFor(actor: actor)
        let targetHoop = attackingHoop(team: actor.team)
        ballVisible = true
        ballInFlight = true
        ballFlightKind = BallFlightKind.SHOT
        setBallSource(sourceX: startSource.x, sourceY: startSource.y)
        let isThree = distanceToHoop(a: actor) > Self.THREE_POINT_DISTANCE_SOURCE
        let points = isThree ? 3 : 2
        let duration: Int64
        if finishMotion == TripleShotPlayerRenderer.Motion.DUNK {
            duration = 220
        } else {
            let half: Int64 = distanceToHoop(a: actor).toLong().coerceAtMost(700) / 2
            duration = (520 + half).coerceIn(520, 850)
        }
        let missSign: Float = random.nextBoolean() ? 1 : -1
        let missOffsetSource: Float = 44 + random.nextFloat() * 26
        // The far/top rim is much smaller in the photographed perspective. Its calibrated visual
        // rim center sits higher than the old generic target; keep a shallow through-rim offset at the
        // top basket, while retaining the proven near-basket target.
        let targetsTopHoop = actor.team == Team.HUMAN
        let madeTargetOffsetY: Float = targetsTopHoop ? 4 : 10
        let missTargetBaseY: Float = targetsTopHoop ? 0 : 3
        let targetSourceX: Float = targetHoop.rimX + (made ? 0 : missOffsetSource * missSign)
        let targetSourceY: Float = targetHoop.rimY + (made ? madeTargetOffsetY : missTargetBaseY + random.nextFloat() * 9)
        let targetSource = APointF(targetSourceX, targetSourceY)
        let apex: Float = finishMotion == TripleShotPlayerRenderer.Motion.DUNK ? 20 : (isThree ? 150 : 106)
        animateBallArcSource(
            start: startSource,
            end: targetSource,
            durationMs: duration,
            apexSource: apex,
            cameraArcFollow01: isThree ? 0.74 : 0.68,
            onEnd: { [self] in
                ballInFlight = false
                ballFlightKind = BallFlightKind.NONE
                if made {
                    premiumScoredAt = ASystem.nanoTime()
                    premiumScoredPosition = TripleShotWorldCoordinates.team(sourceX: targetHoop.footX,
                                                                            sourceY: targetHoop.footY,
                                                                            lift: TripleShotWorldCoordinates.RIM_HEIGHT)
                    ballVisible = false
                    actor.motion = TripleShotPlayerRenderer.Motion.IDLE
                    actor.boost01 = 0
                    if humanRelease { practiceEvent(skill: BasketballSkill.BASKET) }
                    listener?.onTeamBasket(team: actor.team, points: points)
                    if isDunk || shotMeters >= 2 {
                        listener?.onHighlight(team: actor.team,
                                              event: isDunk ? TrumpetCadence.Event.DUNK : TrumpetCadence.Event.DISTANCE_BASKET)
                    }
                    listener?.onDeadBall(defaultNextTeam: actor.team == Team.HUMAN ? Team.OPPONENT : Team.HUMAN)
                } else {
                    if actor.team == Team.HUMAN {
                        BasketballSoundscape.effect(context: self.context, kind: BasketballSoundscape.Effect.DISAPPOINT)
                    }
                    actor.motion = TripleShotPlayerRenderer.Motion.IDLE
                    startLooseBallSource(
                        sourceX: targetSource.x,
                        sourceY: targetSource.y + 12,
                        vxSource: (70 + random.nextFloat() * 105) * missSign,
                        vySource: 70 + random.nextFloat() * 105
                    )
                }
            }
        )
    }

    func startAlleyOop(from: Actor, receiver: Actor) {
        if !from.hasBall || receiver.team != from.team || ballInFlight { return }
        let humanLob = from.controlled && practiceAction != nil
        from.hasBall = false
        receiver.cutUntil = gameTime() + 950
        listener?.onStatus(message: context.getString(R.string.minik_swish_team_alley_oop), team: from.team)
        let startSource = heldBallSourceFor(actor: from)
        let targetHoop = attackingHoop(team: receiver.team)
        let towardCourt = towardCenterSign(hoop: targetHoop)
        let sideSign: Float = receiver.x < targetHoop.footX ? 1 : -1
        let receiverTargetSource = APointF(
            targetHoop.rimX - 48 * sideSign,
            targetHoop.rimY + 82 * towardCourt
        )
        ballVisible = true
        ballInFlight = true
        ballFlightKind = BallFlightKind.ALLEY_OOP
        setBallSource(sourceX: startSource.x, sourceY: startSource.y)
        animateBallArcSource(
            start: startSource,
            end: receiverTargetSource,
            durationMs: 560,
            apexSource: 164,
            cameraArcFollow01: 0.22,
            onFrame: { [self] progress, sourcePoint in
                // Defenders can still take the lob before the catch point. Source-space testing
                // remains stable while the camera pans under the ball. (Rolled on every animation frame.)
                if progress >= 0.20 && progress <= 0.82 {
                    let interceptor = nearestDefenderToSourcePoint(attackingTeam: from.team, point: sourcePoint, maxSource: 58)
                    if let interceptor = interceptor, random.nextFloat() < interceptionChance(actor: interceptor) * 0.035 {
                        cancelBallAnimator()
                        ballInFlight = false
                        ballFlightKind = BallFlightKind.NONE
                        giveBall(actor: interceptor)
                        listener?.onStatus(message: context.getString(R.string.minik_swish_team_pass_intercepted),
                                           team: interceptor.team)
                    }
                }
            },
            onEnd: { [self] in
                if !ballInFlight { return }
                ballInFlight = false
                ballFlightKind = BallFlightKind.NONE
                let defender = nearestDefender(actor: receiver, maxSource: 130)
                let blocked = defender.map {
                    $0.profile.ratings.blocking + $0.profile.ratings.jumping > 125 &&
                        random.nextInt(100) < 28
                } == true
                if blocked, let defender = defender {
                    beginDefensiveJump(actor: defender, motion: TripleShotPlayerRenderer.Motion.BLOCK)
                    startLooseBallSource(
                        sourceX: receiverTargetSource.x,
                        sourceY: receiverTargetSource.y,
                        vxSource: -150,
                        vySource: 145
                    )
                    listener?.onStatus(message: context.getString(R.string.minik_swish_team_ball_loose), team: nil)
                } else {
                    receiver.motion = TripleShotPlayerRenderer.Motion.DUNK
                    beginActorJump(actor: receiver, contested: true)
                    receiver.boost01 = 0
                    ballVisible = false
                    if humanLob { practiceEvent(skill: BasketballSkill.ALLEY) }
                    listener?.onTeamBasket(team: receiver.team, points: 2)
                    listener?.onHighlight(team: receiver.team, event: TrumpetCadence.Event.DUNK)
                    listener?.onDeadBall(defaultNextTeam: receiver.team == Team.HUMAN ? Team.OPPONENT : Team.HUMAN)
                }
            }
        )
    }

    func passBall(from: Actor, to: Actor) {
        if !from.hasBall || to.team != from.team || ballInFlight { return }
        let humanPass = from.controlled && practiceAction != nil
        let gatherStart = heldBallSourceFor(actor: from)
        let gatherWorldStart = gpuWorld.actorSocket(actor: worldActor(actor: from),
                                                    inFront: from.facing != TripleShotPlayerRenderer.Facing.BACK)
        from.hasBall = false
        from.travelScale = 0
        from.facing = facingTowardActor(actor: from, target: to)
        from.motion = TripleShotPlayerRenderer.Motion.SHOT_MID
        from.actionLockUntil = gameTime() + 600
        passReceiverId = to.id
        ALog.i("TRIPLE_PLAY", "pass from=\(from.id) to=\(to.id)")
        let startSource = heldBallSourceFor(actor: from)
        let targetSource = heldBallSourceFor(actor: to)
        ballVisible = true
        ballInFlight = true
        ballFlightKind = BallFlightKind.PASS
        setBallSource(sourceX: startSource.x, sourceY: startSource.y)

        let candidates = actors.filter { $0.team != from.team && !practiceQuiet }
        let interceptor = candidates
            .map { (first: $0, second: distancePointToSegment(p: APointF($0.x, $0.y), a: startSource, b: targetSource)) }
            .filter { $0.second < 76 }
            .kMinBy { $0.second }?
            .first
        let passerSkill = passingSkillProxy(actor: from)
        let interceptionScale = (0.68 - passerSkill * 0.28).coerceIn(0.34, 0.62)
        let intercepted =
            interceptor != nil &&
            random.nextFloat() < interceptionChance(actor: interceptor!) * interceptionScale
        let dx = targetSource.x - startSource.x
        let dy = targetSource.y - startSource.y
        let passDistanceSource = ksqrt(dx * dx + dy * dy)
        let duration = (245 + passDistanceSource * 0.21).toLong().coerceIn(245, 430)
        animateBallArcSource(start: gatherStart, end: startSource, durationMs: 110, apexSource: 0, cameraArcFollow01: 0,
                             worldStartOverride: gatherWorldStart, onEnd: { [self] in
            animateBallArcSource(start: startSource, end: targetSource, durationMs: duration, apexSource: 38,
                                 cameraArcFollow01: 0.04, onEnd: { [self] in
                ballInFlight = false
                ballFlightKind = BallFlightKind.NONE
                if intercepted, let interceptor = interceptor {
                    giveBall(actor: interceptor)
                    listener?.onStatus(message: context.getString(R.string.minik_swish_team_pass_intercepted),
                                       team: interceptor.team)
                } else {
                    giveBall(actor: to)
                    if humanPass { practiceEvent(skill: BasketballSkill.PASS) }
                    passReceiverId = nil
                    // Pass-and-cut creates an actual return lane; it is not an automatic basket.
                    let now = gameTime()
                    if distanceToHoop(a: from) > 130 && random.nextFloat() < 0.65 {
                        beginCut(actor: from, now: now)
                        to.returnPassId = from.id
                        to.returnPassUntil = from.cutUntil + 700
                        ALog.i("TRIPLE_PLAY", "giveAndGo cutter=\(from.id) receiver=\(to.id)")
                    }
                    if to.team == Team.HUMAN { setControlled(id: to.id) }
                }
            })
        })
    }

    func commandScreen(screener: Actor, ballHandler: Actor) {
        if screener.team != ballHandler.team || screener.id == ballHandler.id { return }

        // One active screen on the ball handler is enough. Without this guard a human long-press
        // could stack a second screener on top of an AI-planned screen and recreate the same
        // bunching/collision problem we are removing from team spacing.
        let screenAlreadyComing = actors.contains(where: {
            $0.id != screener.id &&
                $0.team == ballHandler.team &&
                $0.screenTargetId == ballHandler.id
        })
        if screenAlreadyComing { return }

        screener.screenTargetId = ballHandler.id
        listener?.onStatus(message: context.getString(R.string.minik_swish_team_screen_set), team: screener.team)
    }

    func tapHitsLiveBall(x: Float, y: Float, radiusDp: Float = 38) -> Bool {
        if !ballVisible { return false }
        if let ball = worldScene?.balls.first {
            let actor = worldScene?.actors.first(where: { $0.id == ball.owner })
            let position = actor != nil ? gpuWorld.actorSocket(actor: actor!, inFront: ball.inFront) : ball.position
            if let projected = gpuWorld.project(p: position) {
                let dx = x - projected.first; let dy = y - projected.second
                return dx * dx + dy * dy <= dp(v: radiusDp) * dp(v: radiusDp)
            }
        }
        let point: APointF
        if ballInFlight || looseBall {
            point = APointF(ballX, ballY)
        } else {
            guard let handler = currentBallHandler() else { return false }
            point = heldBallFor(actor: handler)
        }
        let dx = x - point.x
        let dy = y - point.y
        let radius = dp(v: radiusDp)
        return dx * dx + dy * dy <= radius * radius
    }

    func handleActorTap(actor: Actor) {
        let handler = currentBallHandler()
        if actor.team == Team.HUMAN {
            if let handler = handler, handler.team == Team.HUMAN && actor.id != handler.id {
                passBall(from: handler, to: actor)
            } else if possession == Team.OPPONENT {
                if actor.id != activeHumanActorId { practiceEvent(skill: BasketballSkill.SWITCH) }
                setControlled(id: actor.id)
                listener?.onStatus(message: context.getString(R.string.minik_swish_team_switch), team: Team.HUMAN)
            }
        }
    }

    func attemptHumanDefensiveAction() {
        guard let defender = actors.first(where: { $0.id == activeHumanActorId }) else { return }
        if defender.team != Team.HUMAN || possession == nil { return }
        if gameTime() - defender.lastStealAttempt < 650 { return }

        if ballInFlight && ballVisible && possession == Team.OPPONENT {
            let ground = TripleShotWorldCoordinates.team(sourceX: defender.x, sourceY: defender.y)
            let d = khypot(ground.x - premiumFlightBall.x, ground.z - premiumFlightBall.z)
            let p = viewPoint(actor: defender)
            defender.lastStealAttempt = gameTime()
            defender.facing = facingTowardPoint(actor: defender, targetX: ballSourceX, targetY: ballSourceY)
            beginDefensiveJump(actor: defender, motion: TripleShotPlayerRenderer.Motion.BLOCK)
            if d < 1.65 && premiumFlightBall.y < 3.8 {
                cancelBallAnimator()
                ballInFlight = false
                let vxDp: Float = ballX < p.x ? -95 : 95
                startLooseBall(x: ballX, y: ballY, vx: dp(v: vxDp), vy: dp(v: 90))
                listener?.onStatus(message: context.getString(R.string.minik_swish_team_ball_loose), team: nil)
            }
            return
        }

        guard let handler = currentBallHandler() else { return }
        if handler.team != Team.OPPONENT { return }
        if floorDistance(a: defender, b: handler) > 1.55 {
            listener?.onStatus(message: context.getString(R.string.minik_swish_team_steal_get_closer), team: Team.HUMAN)
            return
        }

        // Lock the steal pose toward the ACTUAL ball handler before the committed action starts.
        // That prevents a front-facing steal sprite when the live ball is behind the defender.
        defender.facing = facingTowardActor(actor: defender, target: handler)
        defender.lastStealAttempt = gameTime()
        defender.motion = TripleShotPlayerRenderer.Motion.STEAL
        defender.actionLockUntil = gameTime() + 360
        listener?.onStatus(message: context.getString(R.string.minik_swish_team_steal_attempt), team: Team.HUMAN)

        let steal: Float = defender.profile.ratings.stealing.toFloat() * 0.48 + defender.profile.ratings.agility.toFloat() * 0.25
        let protect: Float = handler.profile.ratings.ballHandling.toFloat() * 0.48 + handler.profile.ratings.agility.toFloat() * 0.12
        let chance = ((steal - protect + 30) / 100).coerceIn(0.08, 0.58)
        let success = random.nextFloat() < chance
        if success {
            // Let the reach frame actually appear before ownership changes. Instant giveBall()
            // made a successful steal look like teleportation.
            handler.actionLockUntil = max(handler.actionLockUntil, gameTime() + 190)
            postAction(action: { [self] in
                if handler.hasBall && possession == Team.OPPONENT {
                    handler.hasBall = false
                    giveBall(actor: defender)
                    practiceEvent(skill: BasketballSkill.STEAL)
                    listener?.onStatus(message: context.getString(R.string.minik_swish_team_steal_success), team: defender.team)
                }
            }, delay: Self.STEAL_TRANSFER_DELAY_MS)
        }
        postAction(action: {
            if defender.motion == TripleShotPlayerRenderer.Motion.STEAL {
                defender.motion = defender.hasBall ? TripleShotPlayerRenderer.Motion.DRIBBLE
                    : TripleShotPlayerRenderer.Motion.IDLE
                defender.actionLockUntil = 0
            }
        }, delay: 380)
    }

    func setControlled(id: String) {
        activeHumanActorId = id
        for human in actors.filter({ $0.team == Team.HUMAN }) { human.controlled = human.id == id }
        if possession == Team.OPPONENT { notifyHumanGuidanceIfChanged(force: true) }
    }

    func crossHands(actor: Actor, now: Int64) {
        actor.crossBehind = now &- actor.crossAt < 2200 && !actor.crossBehind
        actor.crossFrom = actor.dribbleHandSign; actor.dribbleHandSign = -actor.dribbleHandSign; actor.crossAt = now
        if actor.controlled {
            practiceEvent(skill: actor.crossBehind ? BasketballSkill.BEHIND_BACK : BasketballSkill.CROSSOVER)
        }
        ALog.i("TRIPLE_PLAY", "cross actor=\(actor.id) behind=\(actor.crossBehind)")
    }

    func trySpin(actor: Actor, direction: Int, now: Int64) {
        if now &- actor.spinAt < 400 || !actor.hasBall { return }
        actor.spinAt = now; actor.spinSign = direction
        let defender = primaryDefenderFor(offense: actor) ?? nearestDefender(actor: actor, maxSource: 1000)
        if actor.controlled { practiceEvent(skill: BasketballSkill.SPIN) }
        guard let defender = defender, !(floorDistance(a: actor, b: defender) > 2) else { return }
        let result = actor.spinSeries.attempt(now: now, defense: defender.profile.ratings.defense) { random.nextFloat() }
        if result.success {
            defender.screenedUntil = now + result.recoveryMs
            if result.fall { defender.fallenUntil = defender.screenedUntil }
        }
        ALog.i("TRIPLE_PLAY", "spin actor=\(actor.id) success=\(result.success) fall=\(result.fall) chance=\(javaString(result.chance))")
    }

    func moveControlledBy(dxPx: Float, dyPx: Float) {
        if actors.first(where: { $0.controlled }).map({ $0.screenedUntil > gameTime() }) == true { return }
        guard let actor = actors.first(where: { $0.id == activeHumanActorId }) else { return }
        let t = transform()

        /*
         * Human touch follows SCREEN distance first, then converts back to logical court space.
         * That matters in landscape because X/Y use different scales; capping a source-space vector
         * made vertical dribbles feel heavy while horizontal movement felt fast.
         */
        let now = gameTime()
        if now < actor.actionLockUntil { return }
        let dt = ((now - humanMoveAt).toFloat() / 1000).coerceIn(0, 0.05)
        humanMoveAt = now
        let foot = gpuWorld.project(p: TripleShotWorldCoordinates.team(sourceX: actor.x, sourceY: actor.y))
        let from = foot.flatMap { gpuWorld.screenGround(x: $0.first, y: $0.second) }
        let to = foot.flatMap { gpuWorld.screenGround(x: $0.first + dxPx, y: $0.second + dyPx) }
        let dx: Float
        let dy: Float
        if let from = from, let to = to {
            dx = (to.x - from.x) / 0.014
        } else {
            dx = dxPx / t.scaleX.coerceAtLeast(0.001)
        }
        if let from = from, let to = to {
            dy = (to.z - from.z) / 0.034
        } else {
            dy = dyPx / t.scaleY.coerceAtLeast(0.001)
        }
        let step = BasketballMovement.step(dx: dx, dy: dy, speed: actor.profile.ratings.speed,
                                           agility: actor.profile.ratings.agility, scale: 1 + actor.boost01 * 0.25,
                                           dtSeconds: dt)
        let beforeX = actor.x; let beforeY = actor.y
        actor.x += step.x
        actor.y += step.y
        actor.vx = step.x
        actor.vy = step.y
        let insideX = actor.x >= Self.SOURCE_PLAY_MIN_X && actor.x <= Self.SOURCE_PLAY_MAX_X
        let insideY = actor.y >= Self.SOURCE_PLAY_MIN_Y && actor.y <= Self.SOURCE_PLAY_MAX_Y
        if actor.hasBall && (!insideX || !insideY) {
            clampActorToPlayableArea(actor: actor)
            // Kotlin L1896: the English text and the Hebrew "out of the court" text (written as escapes).
            turnover(team: actor.team, english: "Out of bounds",
                     hebrew: "\u{05DE}\u{05D7}\u{05D5}\u{05E5} \u{05DC}\u{05DE}\u{05D2}\u{05E8}\u{05E9}")
            return
        }
        if khypot(step.x * 0.014, step.y * 0.034) > 0.025 { actor.lastMeaningfulMovementAt = now }
        actor.motion = actor.hasBall ? TripleShotPlayerRenderer.Motion.DRIBBLE : TripleShotPlayerRenderer.Motion.WALK
        actor.facing = basketballFacing(actor: actor, moveDx: actor.vx, moveDy: actor.vy)
        clampActorToPlayableArea(actor: actor)
        resolveActorCollisions(moved: actor)
        clampActorToPlayableArea(actor: actor)
        if actor.hasBall {
            // Kotlin `(dx * .014).toDouble()` with a Double literal: a Double multiplication, then Math.hypot.
            practiceEvent(skill: BasketballSkill.MOVE,
                          amount: hypot(Double(actor.x - beforeX) * 0.014, Double(actor.y - beforeY) * 0.034))
        }
        updateCamera()
        updateHeldBall()
        invalidate()
    }

    func stopControlledMovement() {
        guard let actor = actors.first(where: { $0.id == activeHumanActorId }) else { return }
        actor.vx = 0
        actor.vy = 0
        actor.facing = basketballFacing(actor: actor, moveDx: 0, moveDy: 0)
        if !shotHoldActive && !ballInFlight {
            actor.motion = actor.hasBall ? TripleShotPlayerRenderer.Motion.DRIBBLE : TripleShotPlayerRenderer.Motion.IDLE
        }
    }

    func updateActors(now: Int64) {
        if actors.isEmpty { return }

        for actor in actors {
            updateJump(actor: actor, now: now)
            updateDribbleRhythm(actor: actor, now: now)
        }

        guard let liveTeam = possession else { return }
        if !ballInFlight && !looseBall {
            let handler = currentBallHandler()
            if let handler = handler, !handler.controlled, now &- handler.spinAt > 1900,
               now &- handler.possessionReceivedAt > 700 {
                let defender = primaryDefenderFor(offense: handler)
                if let defender = defender, floorDistance(a: handler, b: defender) < Float(1.75),
                   random.nextFloat() < Float(0.015) {
                    trySpin(actor: handler, direction: random.nextBoolean() ? 1 : -1, now: now)
                }
            }
        }
        if practiceAction == nil && possessionStartedAt > 0 {
            let delta: Int64 = lastLiveTick == 0 ? 0 : (now - lastLiveTick).coerceIn(0, 80)
            lastLiveTick = now
            listener?.onLiveTime(milliseconds: delta)
            if possession == nil { return }
            let remainingMs: Int64 = 24_000 - (now - possessionStartedAt) + 999
            let seconds = (remainingMs / 1000).toInt().coerceAtLeast(0)
            if seconds != lastClockSeconds { lastClockSeconds = seconds; listener?.onShotClock(seconds: seconds) }
            if seconds == 0 && ballFlightKind != BallFlightKind.SHOT {
                // Kotlin L1939: "24 seconds - other team's ball" (U+2014 em dash) and its Hebrew text (escapes).
                turnover(team: liveTeam, english: "24 seconds \u{2014} other team's ball",
                         hebrew: "24 \u{05E9}\u{05E0}\u{05D9}\u{05D5}\u{05EA} \u{2014} \u{05D4}\u{05DB}\u{05D3}\u{05D5}\u{05E8} \u{05DC}\u{05E7}\u{05D1}\u{05D5}\u{05E6}\u{05D4} \u{05D4}\u{05E9}\u{05E0}\u{05D9}\u{05D9}\u{05D4}")
                return
            }
        }
        if shotHoldActive { updateShotMeter() }

        if looseBall {
            updateAiLooseBallChase(now: now)
            advancePlannedMovement(now: now)
            return
        }

        if !ballInFlight {
            updateHandlerTracking(now: now)
            if liveTeam == Team.OPPONENT { updateOpponentOffense(now: now) }

            // A decision above can immediately start a pass/shot. Do not run a second ground step
            // after the ball has already left the handler.
            if !ballInFlight && !looseBall {
                updateOffBallAndDefense(now: now)
                updateCamera()
                updateHeldBall()
            }
        } else if ballFlightKind == BallFlightKind.SHOT {
            // Players should react to a shot while it is in the air rather than freezing until the
            // rebound is already loose.
            updateShotReboundAnticipation(now: now)
        }
        // Movement has its own clock. A 360ms tactical decision must not yield one 80ms step.
        // Existing cuts/defensive rotations continue while a pass is in flight.
        advancePlannedMovement(now: now)
        updateCamera()
        if !ballInFlight && !looseBall { updateHeldBall() }
    }

    func updateHandlerTracking(now: Int64) {
        guard let handler = currentBallHandler() else {
            trackedHandlerId = nil
            trackedHandlerSince = 0
            return
        }
        if trackedHandlerId != handler.id {
            trackedHandlerId = handler.id
            trackedHandlerSince = now
            handler.possessionReceivedAt = now
        }
    }

    /**
     * Team mode intentionally matches the mature 1v1 dribble rhythm (the Kotlin KDoc's "520ms" is stale:
     * the period constant is 740 ms) with a 46dp travel distance. The phase is actor-specific so six
     * players do not bounce in mechanical lockstep.
     */
    func updateDribbleRhythm(actor: Actor, now: Int64) {
        if !actor.hasBall {
            actor.dribbleBounce = 0
            return
        }

        let phaseOffset: Int64 = abs(Int64(actor.id.javaHashCode)) % Self.TEAM_DRIBBLE_PERIOD_MS
        let shifted = now + phaseOffset
        let cycle = shifted / Self.TEAM_DRIBBLE_PERIOD_MS
        _ = cycle
        actor.dribblePhase =
            (shifted % Self.TEAM_DRIBBLE_PERIOD_MS).toFloat() / Self.TEAM_DRIBBLE_PERIOD_MS.toFloat()
        actor.dribbleBounce =
            abs(ksin(actor.dribblePhase * PI_F)) * Self.TEAM_DRIBBLE_AMPLITUDE_DP
        // Keep the chosen hand until a deliberate crossover; facing must not swap it every frame.
    }

    /**
     * Structured opponent offense. The important rule is patience: a bot does not need to finish a
     * possession at the first legal opportunity. It can hold, probe, use a screen, fake, pass and
     * reset. Exceptional open layups remain fast because real basketball should punish an empty rim.
     */
    func updateOpponentOffense(now: Int64) {
        if practiceQuiet { return }
        guard let handler = currentBallHandler() else { return }
        if handler.team != Team.OPPONENT { return }
        if now < handler.actionLockUntil { return }
        if now - handler.lastAiDecision < Self.TEAM_BALL_HANDLER_DECISION_MS { return }
        handler.lastAiDecision = now

        let possessionAge = (now - possessionStartedAt).coerceAtLeast(0)
        let handlerAge = (now - trackedHandlerSince).coerceAtLeast(0)
        let defender = primaryDefenderFor(offense: handler) ?? nearestDefender(actor: handler, maxSource: 1000)
        let defenderDistance: Float = defender.map { distance(a: handler, b: $0) } ?? 999
        let ownShotQuality = aiShotQuality(actor: handler)
        let distHoop = distanceToHoop(a: handler)
        let passSkill = passingSkillProxy(actor: handler)
        let baseDriveEdge = driveAdvantage(attacker: handler, defender: defender)
        let screenedBonus: Float = (defender.map { $0.screenedUntil > now } == true) ? 0.22 : 0
        let driveEdge = (baseDriveEdge + screenedBonus).coerceIn(-0.35, 0.48)

        let mates = actors.filter { $0.team == handler.team && $0.id != handler.id }
        let bestPass: (first: Actor, second: Float)? =
            mates
                .map { mate -> (first: Actor, second: Float) in
                    let cutBonus: Float = mate.cutUntil > now ? 0.20 : 0
                    let movementBonus: Float =
                        (mate.screenTargetId == nil && distanceToHoop(a: mate) + 45 < distHoop) ? 0.055 : 0
                    let score: Float = aiPassScore(from: handler, to: mate) + cutBonus + movementBonus
                    return (first: mate, second: score.coerceAtMost(1.15))
                }
                .kMaxBy { $0.second }

        let returnRunner = mates.first(where: { $0.id == handler.returnPassId })
        if let returnRunner = returnRunner, now < handler.returnPassUntil && returnRunner.cutUntil > now {
            let runnerDistance = distanceToHoop(a: returnRunner)
            // A called give-and-go allows a contested but usable return lane; passBall still
            // applies interception. Requiring a completely unguarded lane prevented every return.
            if handlerAge >= 320 && passLaneSafety(from: handler, to: returnRunner) > 0.42 &&
                runnerDistance + 10 < distHoop {
                handler.returnPassId = nil
                ALog.i("TRIPLE_PLAY", "giveAndGoReturn from=\(handler.id) to=\(returnRunner.id)")
                passBall(from: handler, to: returnRunner)
                return
            }
            // Briefly probe sideways while the cutter runs. Never delay an open close finish,
            // freeze a pressured handler, or keep waiting after this play's short setup window.
            if handlerAge < 1700 && distHoop > 165 && defenderDistance > 85 {
                let side: Float = handler.x < returnRunner.x ? -1 : 1
                moveAiToward(actor: handler, tx: handler.x + side * 30, ty: handler.y, speedScale: 0.40)
                return
            }
        }
        let pressured = defenderDistance < 128
        let screenedDefender = defender.map { $0.screenedUntil > now } == true

        // If the ball-handler has been stationary under pressure, actively call for one screen.
        // Earlier versions left this entirely to a low-probability off-ball RNG branch, so many
        // possessions never developed beyond a stationary dribble.
        if handlerAge >= Self.TEAM_SCREEN_REQUEST_HOLD_MS &&
            (pressured || distHoop > 275 || ownShotQuality < 0.58) &&
            !screenedDefender &&
            !actors.contains(where: {
                $0.team == handler.team &&
                    $0.id != handler.id &&
                    $0.screenTargetId == handler.id
            }) {
            let screener = mates
                .filter { now >= $0.screenCooldownUntil && $0.cutUntil <= now }
                .kMaxBy { mate -> Float in
                    var score: Float = mate.profile.ratings.strength.toFloat() * 0.42
                    score = score + mate.profile.ratings.height.toFloat() * 0.24
                    score = score + mate.profile.ratings.offense.toFloat() * 0.22
                    score = score + mate.profile.ratings.inside.toFloat() * 0.12
                    return score
                }
            if let screener = screener, handlerAge >= Self.TEAM_FORCE_SCREEN_HOLD_MS || random.nextFloat() < 0.68 {
                screener.screenTargetId = handler.id
                screener.actionLockUntil = now + 1050
            }
        }

        /*
         * Continuous possession flow. EVERY receiver gets the same clock from giveBall(), so a wing
         * or interior cannot become a terminal state after the PG's first pass. By ~2 seconds a
         * guarded/distant handler must move the possession toward a better option; by the absolute
         * stall deadline it must pass OR make a decisive drive.
         */
        if let bestPass = bestPass, handlerAge >= Self.TEAM_FORCED_BALL_MOVEMENT_MS {
            let mate = bestPass.first
            let passScore = bestPass.second
            let laneSafety = passLaneSafety(from: handler, to: mate)
            let mateDefenderDistance: Float = nearestDefender(actor: mate, maxSource: 1000).map { distance(a: mate, b: $0) } ?? 999
            let clearlyMoreOpen = mateDefenderDistance > defenderDistance + 28
            let meaningfullyCloser = distanceToHoop(a: mate) + 55 < distHoop
            let activeCutter = mate.cutUntil > now
            let poorOrDistantLook = distHoop > 250 || pressured || ownShotQuality < 0.67
            if laneSafety > 0.24 &&
                poorOrDistantLook &&
                (activeCutter || clearlyMoreOpen || meaningfullyCloser || passScore >= ownShotQuality - 0.08) {
                passBall(from: handler, to: mate)
                return
            }
        }

        if handlerAge >= Self.TEAM_ABSOLUTE_STALL_MS {
            let safestReceiver =
                mates
                    .map { mate -> (first: Actor, second: Float, third: Float) in
                        let safety = passLaneSafety(from: handler, to: mate)
                        let cutBonus: Float = mate.cutUntil > now ? 0.22 : 0
                        let value: Float = aiPassScore(from: handler, to: mate) + cutBonus + safety * 0.24
                        return (first: mate, second: safety, third: value)
                    }
                    .filter { $0.second > 0.14 }
                    .kMaxBy { $0.third }

            if let safestReceiver = safestReceiver {
                passBall(from: handler, to: safestReceiver.first)
                return
            }

            // Both lanes are genuinely crowded: do not stand still. Attack a shoulder and force the
            // defense to move, which will open the next pass/shot decision on the following ticks.
            if distHoop > 135 {
                let hoop = attackingHoop(team: handler.team)
                let dx = hoop.footX - handler.x
                let dy = hoop.footY - handler.y
                let len = ksqrt(dx * dx + dy * dy).coerceAtLeast(1)
                let side: Float = (defender == nil || handler.x <= defender!.x) ? -1 : 1
                let driveX: Float = handler.x + dx / len * 145 + side * 42
                let driveY: Float = handler.y + dy / len * 155
                let driveTarget = applyTeammateSpacing(actor: handler, target: APointF(driveX, driveY))
                moveAiToward(actor: handler, tx: driveTarget.x, ty: driveTarget.y, speedScale: 1.03)
                return
            }
        }

        // A live cutter with real finishing tools can receive an alley-oop, but only when the lane is
        // clean enough that it reads as a basketball decision rather than a random animation.
        let lobCandidate =
            mates
                .filter { $0.cutUntil > now && distanceToHoop(a: $0) < 260 }
                .filter { $0.profile.ratings.dunking + $0.profile.ratings.jumping >= 138 }
                .kMaxBy { aiPassScore(from: handler, to: $0) }
        if let lobCandidate = lobCandidate,
           possessionAge >= Self.TEAM_EARLY_ACTION_GRACE_MS &&
            passLaneSafety(from: handler, to: lobCandidate) > 0.64 &&
            random.nextFloat() < 0.24 + passSkill * 0.18 {
            startAlleyOop(from: handler, receiver: lobCandidate)
            return
        }

        let ratings = handler.profile.ratings
        var insideSum: Float = ratings.inside.toFloat() * 0.38
        insideSum = insideSum + ratings.dunking.toFloat() * 0.18
        insideSum = insideSum + ratings.jumping.toFloat() * 0.12
        insideSum = insideSum + ratings.strength.toFloat() * 0.12
        insideSum = insideSum + ratings.height.toFloat() * 0.08
        insideSum = insideSum + ratings.offense.toFloat() * 0.12
        let insidePower: Float = insideSum / 100

        let recentRebound = now - handler.lastReboundClaimAt <= Self.TEAM_REBOUND_PUTBACK_WINDOW_MS
        let openCloseFinish =
            distHoop < 165 &&
            (defenderDistance > 94 || driveEdge > 0.18) &&
            insidePower > 0.48
        if openCloseFinish &&
            (recentRebound || possessionAge >= Self.TEAM_MIN_FAST_FINISH_MS || handlerAge >= 900) {
            let finishRaw: Float = 63 + insidePower * 29 + (1 - contest01(shooter: handler)) * 9
            let chance = finishRaw.toInt().coerceIn(48, 96)
            shoot(actor: handler, chance: chance, finishMotion: TripleShotPlayerRenderer.Motion.DUNK)
            return
        }

        // Offensive rebound with no real put-back: get the ball back out and rebuild the shape.
        // This is what stops all three attackers from living under the rim after one miss.
        if recentRebound && !openCloseFinish && handlerAge >= 620 && handler.role != TeamRole.POINT_GUARD {
            let pg = mates.first(where: { $0.role == TeamRole.POINT_GUARD })
            if let pg = pg, passLaneSafety(from: handler, to: pg) > 0.38 {
                passBall(from: handler, to: pg)
                return
            }
        }

        // A wing/interior who has held the ball too long normally resets to the PG instead of
        // forcing a bad shot. High passing skill reaches this reset earlier.
        if handler.role != TeamRole.POINT_GUARD && handlerAge >= Self.TEAM_STUCK_HANDLER_MS {
            let pg = mates.first(where: { $0.role == TeamRole.POINT_GUARD })
            if let pg = pg, passLaneSafety(from: handler, to: pg) > 0.46 {
                passBall(from: handler, to: pg)
                return
            }
        }

        // Passes are allowed before shots. A gifted passer processes the floor faster; a scorer with
        // weaker passing can hold the dribble and work for a better look.
        if let bestPass = bestPass, handlerAge >= Self.TEAM_MIN_PASS_HOLD_MS {
            let mate = bestPass.first
            let passScore = bestPass.second
            let laneSafety = passLaneSafety(from: handler, to: mate)
            let requiredEdge: Float = 0.13 - passSkill * 0.07
            let quickPassBoost = ((passSkill - 0.62) * 0.32).coerceAtLeast(0)
            let passChance: Float = 0.24 + passScore * 0.34 + quickPassBoost
            if laneSafety > 0.43 &&
                passScore > ownShotQuality + requiredEdge &&
                random.nextFloat() < passChance.coerceIn(0.20, 0.74) {
                passBall(from: handler, to: mate)
                return
            }
        }

        // A visible pump fake is useful only when a defender is close enough to react. This is not a
        // hidden RNG make/miss modifier: the fake simply buys a brief movement/reaction window.
        if handlerAge >= 1500 &&
            defender != nil &&
            (defenderDistance >= 78 && defenderDistance <= 148) &&
            ownShotQuality >= 0.48 &&
            random.nextFloat() < 0.10 + handler.profile.ratings.offense.toFloat() / 100 * 0.10 {
            startAiPumpFake(handler: handler, defender: defender!, now: now)
            return
        }

        let zoneRating: Int
        if distHoop < 165 {
            zoneRating = handler.profile.ratings.inside
        } else if distHoop < Self.THREE_POINT_DISTANCE_SOURCE {
            zoneRating = handler.profile.ratings.midRange
        } else {
            zoneRating = handler.profile.ratings.threePoint
        }
        let roleShotAdjustment: Float
        switch handler.role {
        case .POINT_GUARD: roleShotAdjustment = distHoop > 350 ? -0.025 : 0.015
        case .WING: roleShotAdjustment = distHoop > 315 ? -0.045 : 0
        case .INTERIOR: roleShotAdjustment = (distHoop > 365 && zoneRating < 76) ? 0.12 : -0.015
        }
        let thresholdBase: Float
        if distHoop > Self.THREE_POINT_DISTANCE_SOURCE {
            thresholdBase = 0.68
        } else if distHoop > 170 {
            thresholdBase = 0.63
        } else {
            thresholdBase = 0.59
        }
        let shotThreshold = thresholdBase + roleShotAdjustment
        let eliteImmediateLook = ownShotQuality >= 0.88 && defenderDistance > 150 && handlerAge >= 1700
        let normalShotClockReached = possessionAge >= Self.TEAM_MIN_NORMAL_SHOT_MS && handlerAge >= 1250
        let shotRollLimit: Float = (0.18 + ownShotQuality * 0.40).coerceAtMost(0.62)
        if (distHoop < 390 || possessionAge > 21_000) &&
            (normalShotClockReached || eliteImmediateLook) &&
            ownShotQuality >= shotThreshold &&
            defenderDistance > 105 &&
            random.nextFloat() < shotRollLimit {
            shoot(actor: handler, chance: (ownShotQuality * 100).toInt().coerceIn(20, 94))
            return
        }

        // Before the attack matures, keep the shape: PG probes outside, wing works from the corner,
        // interior oscillates between weak-side spacing and a short seal. Later, a real driving edge
        // can override that structure.
        let home = roleHomeSpot(team: handler.team, role: handler.role, attacking: true)
        let canAttackGap =
            handlerAge >= Self.TEAM_MIN_DRIVE_HOLD_MS &&
            (driveEdge > 0.04 || defenderDistance > 150) &&
            handler.profile.ratings.offense + handler.profile.ratings.agility >= 105

        if !canAttackGap || possessionAge < Self.TEAM_EARLY_ACTION_GRACE_MS {
            let probeSign: Float = ((now / 1300 &+ Int64(handler.id.javaHashCode)) % 2 == 0) ? -1 : 1
            let probeX: Float = home.x + probeSign * (18 + handler.profile.ratings.agility.toFloat() * 0.12)
            let probeY: Float = home.y - (handler.role == TeamRole.INTERIOR ? 28 : 8)
            let target = applyTeammateSpacing(actor: handler, target: APointF(probeX, probeY))
            moveAiToward(actor: handler, tx: target.x, ty: target.y, speedScale: 0.66)
            return
        }

        let driveHoop = attackingHoop(team: handler.team)
        let dx = driveHoop.footX - handler.x
        let dy = driveHoop.footY - handler.y
        let len = ksqrt(dx * dx + dy * dy).coerceAtLeast(1)
        let lateAggression = ((possessionAge - 8000).toFloat() / 9000).coerceIn(0, 0.28)
        let attackBiasRaw: Float = 0.70 + driveEdge * 0.30 + lateAggression
        let attackBias = attackBiasRaw.coerceIn(0.58, 1.12)
        let lateralSign: Float
        if defender == nil {
            lateralSign = handler.x < driveHoop.footX ? -1 : 1
        } else if handler.x < defender!.x {
            lateralSign = -1
        } else {
            lateralSign = 1
        }
        let lateralStrength: Float =
            defenderDistance < 175 ? 0.24 + handler.profile.ratings.agility.toFloat() / 100 * 0.50 : 0.08
        let roleDrive: Float
        switch handler.role {
        case .POINT_GUARD: roleDrive = 0.88
        case .WING: roleDrive = 0.96
        case .INTERIOR: roleDrive = 1.08
        }
        let forwardX: Float = dx / len * 105 * attackBias * roleDrive
        let targetX: Float = handler.x + forwardX + lateralSign * 80 * lateralStrength
        let targetY: Float = handler.y + dy / len * 115 * attackBias * roleDrive
        let target = applyTeammateSpacing(actor: handler, target: APointF(targetX, targetY))
        moveAiToward(actor: handler, tx: target.x, ty: target.y, speedScale: 0.82 + driveEdge * 0.16)
    }
}

/// Kotlin `Listener` default bodies (`= Unit`) and the `onStatus(message, team = null)` default argument.
extension TripleShotTeamCourtView.Listener {
    func onHighlight(team: TripleShotTeamCourtView.Team, event: TrumpetCadence.Event) {}

    func onStatus(message: String) {
        onStatus(message: message, team: nil)
    }

    func onHumanGuidanceChanged(guidance: TripleShotTeamCourtView.HumanGuidance) {}
    func onShotClock(seconds: Int) {}
    func onLiveTime(milliseconds: Int64) {}
}
