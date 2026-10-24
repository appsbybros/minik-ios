import Foundation

// Port of view/TripleShotPlayerRenderer.kt (Android 6c38131), statement by statement (spec 07 §3.5, §4.2-§4.8).
// Units are Android pixels: `dp(v) = v * density` with the density captured at construction (AResources.density,
// the UIScreen scale), like `context.resources.displayMetrics.density`.
//
// Bit-faithful Float maths: every expression keeps the Kotlin operand order and Float types; `sin` goes through
// AndroidKit `ksin` (computed in Double like kotlin.math on the JVM); `coerceIn/coerceAtLeast/coerceAtMost` and
// `toInt()` have Kotlin semantics.
//
// Sprite sizes: Android reads `drawable.intrinsicWidth/Height` of `ContextCompat.getDrawable(...)`; for these
// drawable-nodpi bitmaps that is the image's pixel size, which AResources serves from the generated size table
// (`drawableIntrinsicSize`), so the gameplay maths (`heldBallPosition`, `visualTopY`) never decodes an image. The
// legacy Canvas sprite paths draw the real ADrawable (`ContextCompat_getDrawable(...)?.mutate()`, cached per resId
// like `spriteCache`).
//
// Production use (spec 07 §8.1): `worldFrame` (GPU world), `heldBallPosition` (gameplay ball socket) and `draw` for
// the vector fallback raster of ids without sprites. The Canvas sprite paths, `visualTopY`,
// `drawBallForegroundOcclusion` and the winner hop/flame have no production caller on Android; they are ported 1:1.

/**
 * Single rendering source for every on-court player character in MINIK SWISH.
 *
 * Human players can now use the real sprite set for the main professional jump-shot.
 * The original vector character is intentionally kept as the GRANNY/fallback renderer,
 * while PRO sprites are referenced directly as Android resources so missing art is caught at build time instead of silently falling back.
 */
final class TripleShotPlayerRenderer {

    enum Style: String, KotlinEnum {
        case HUMAN
        case BOT
    }

    enum Pose: String, KotlinEnum {
        case NORMAL
        case WINNER
        case LOSER
        case SPECTATOR
    }

    enum ShotStyle: String, KotlinEnum {
        /** Main, professional basketball jump-shot. */
        case PRO

        /** Original prototype/granny-style animation, preserved on purpose. */
        case GRANNY
    }

    /// Ordinals BACK = 0, SIDE = 1, FRONT = 2 are used numerically (TeamCourtView / BasketballVisualMotion) and the
    /// names are persisted in TeamCourtView's instance state.
    enum Facing: String, KotlinEnum {
        case BACK
        case SIDE
        case FRONT
    }

    enum Motion: String, KotlinEnum {
        case IDLE
        /** Relaxed front-facing pose used while another player/bot has the turn. */
        case WAITING
        /** Relaxed movement without a ball, used when it is the opponent's turn. */
        case WALK
        /** Human owns the real game ball and bounces it while moving/idle. */
        case DRIBBLE
        /** 1v1 defensive actions with dedicated direction-aware Maya art. */
        case STEAL
        case BLOCK
        case REBOUND
        /** Dedicated close-finish pose chosen from the character's dunk library. */
        case DUNK
        /** Three body-only keyframes for the professional shooting preparation. */
        case SHOT_LOW
        case SHOT_MID
        case SHOT_SET
        case RELEASE
    }

    /// Kotlin `data class State` (copied into every world snapshot). `==` and the hash follow Kotlin data-class
    /// equality: Float fields compare with `Float.compare` (NaN equals NaN, 0.0 differs from -0.0).
    struct State: Hashable {
        var x: Float
        var footY: Float
        var fineAim: Float
        var pullBack: Float
        var dribbleBouncePx: Float
        var hotHand: Bool
        var style: Style
        var pose: Pose
        /** 0..1 progress used only by the winner jump animation. */
        var celebrationProgress: Float
        /** Defaults to the old renderer so untouched call-sites remain backward compatible. */
        var shotStyle: ShotStyle
        var facing: Facing
        var motion: Motion
        /** 0..1 phase of the current human dribble bounce. */
        var dribblePhase01: Float
        /** +1 / -1 lets an idle dribble alternate which hand receives the ball. */
        var dribbleHandSign: Float
        var crossoverProgress: Float
        var crossoverFrom: Float
        var crossoverBehind: Bool
        /** True only while the human sprite is translating across the court. */
        var moving: Bool
        /** Fast movement keeps a one-hand dribble; slow movement crosses hand-to-hand. */
        var movingFast: Bool
        /** Team locomotion advances with physical travel, not the global wall clock. */
        var locomotionFrameIndex: Int
        /** Stable roster id. A missing visual pack intentionally falls back to vector art. */
        var characterId: String?
        /** Horizontal mirror around the feet anchor for left/right hoop geometry. */
        var mirrorX: Bool
        /** Index into CharacterSpriteSet.dunks. Ignored by every non-DUNK motion. */
        var actionFrameIndex: Int
        /** Extra camera-only scale. Defaults to 1 so 1v1 and existing call-sites are unchanged. */
        var visualScale: Float
        var playfulHold: Bool

        init(
            x: Float,
            footY: Float,
            fineAim: Float,
            pullBack: Float,
            dribbleBouncePx: Float,
            hotHand: Bool,
            style: Style = Style.HUMAN,
            pose: Pose = Pose.NORMAL,
            celebrationProgress: Float = 0,
            shotStyle: ShotStyle = ShotStyle.GRANNY,
            facing: Facing = Facing.BACK,
            motion: Motion = Motion.IDLE,
            dribblePhase01: Float = 0,
            dribbleHandSign: Float = 1,
            crossoverProgress: Float = 1,
            crossoverFrom: Float = 1,
            crossoverBehind: Bool = false,
            moving: Bool = false,
            movingFast: Bool = false,
            locomotionFrameIndex: Int = -1,
            characterId: String? = nil,
            mirrorX: Bool = false,
            actionFrameIndex: Int = -1,
            visualScale: Float = 1,
            playfulHold: Bool = false
        ) {
            self.x = x
            self.footY = footY
            self.fineAim = fineAim
            self.pullBack = pullBack
            self.dribbleBouncePx = dribbleBouncePx
            self.hotHand = hotHand
            self.style = style
            self.pose = pose
            self.celebrationProgress = celebrationProgress
            self.shotStyle = shotStyle
            self.facing = facing
            self.motion = motion
            self.dribblePhase01 = dribblePhase01
            self.dribbleHandSign = dribbleHandSign
            self.crossoverProgress = crossoverProgress
            self.crossoverFrom = crossoverFrom
            self.crossoverBehind = crossoverBehind
            self.moving = moving
            self.movingFast = movingFast
            self.locomotionFrameIndex = locomotionFrameIndex
            self.characterId = characterId
            self.mirrorX = mirrorX
            self.actionFrameIndex = actionFrameIndex
            self.visualScale = visualScale
            self.playfulHold = playfulHold
        }

        /// Kotlin call form with the first six arguments positional (`State(x, footY, 0f, 0f, 0f, false, characterId = id)`).
        init(
            _ x: Float,
            _ footY: Float,
            _ fineAim: Float,
            _ pullBack: Float,
            _ dribbleBouncePx: Float,
            _ hotHand: Bool,
            style: Style = Style.HUMAN,
            pose: Pose = Pose.NORMAL,
            celebrationProgress: Float = 0,
            shotStyle: ShotStyle = ShotStyle.GRANNY,
            facing: Facing = Facing.BACK,
            motion: Motion = Motion.IDLE,
            dribblePhase01: Float = 0,
            dribbleHandSign: Float = 1,
            crossoverProgress: Float = 1,
            crossoverFrom: Float = 1,
            crossoverBehind: Bool = false,
            moving: Bool = false,
            movingFast: Bool = false,
            locomotionFrameIndex: Int = -1,
            characterId: String? = nil,
            mirrorX: Bool = false,
            actionFrameIndex: Int = -1,
            visualScale: Float = 1,
            playfulHold: Bool = false
        ) {
            self.init(x: x, footY: footY, fineAim: fineAim, pullBack: pullBack, dribbleBouncePx: dribbleBouncePx,
                      hotHand: hotHand, style: style, pose: pose, celebrationProgress: celebrationProgress,
                      shotStyle: shotStyle, facing: facing, motion: motion, dribblePhase01: dribblePhase01,
                      dribbleHandSign: dribbleHandSign, crossoverProgress: crossoverProgress,
                      crossoverFrom: crossoverFrom, crossoverBehind: crossoverBehind, moving: moving,
                      movingFast: movingFast, locomotionFrameIndex: locomotionFrameIndex, characterId: characterId,
                      mirrorX: mirrorX, actionFrameIndex: actionFrameIndex, visualScale: visualScale,
                      playfulHold: playfulHold)
        }

        static func == (a: State, b: State) -> Bool {
            return a.x.toBits() == b.x.toBits() &&
                a.footY.toBits() == b.footY.toBits() &&
                a.fineAim.toBits() == b.fineAim.toBits() &&
                a.pullBack.toBits() == b.pullBack.toBits() &&
                a.dribbleBouncePx.toBits() == b.dribbleBouncePx.toBits() &&
                a.hotHand == b.hotHand &&
                a.style == b.style &&
                a.pose == b.pose &&
                a.celebrationProgress.toBits() == b.celebrationProgress.toBits() &&
                a.shotStyle == b.shotStyle &&
                a.facing == b.facing &&
                a.motion == b.motion &&
                a.dribblePhase01.toBits() == b.dribblePhase01.toBits() &&
                a.dribbleHandSign.toBits() == b.dribbleHandSign.toBits() &&
                a.crossoverProgress.toBits() == b.crossoverProgress.toBits() &&
                a.crossoverFrom.toBits() == b.crossoverFrom.toBits() &&
                a.crossoverBehind == b.crossoverBehind &&
                a.moving == b.moving &&
                a.movingFast == b.movingFast &&
                a.locomotionFrameIndex == b.locomotionFrameIndex &&
                a.characterId == b.characterId &&
                a.mirrorX == b.mirrorX &&
                a.actionFrameIndex == b.actionFrameIndex &&
                a.visualScale.toBits() == b.visualScale.toBits() &&
                a.playfulHold == b.playfulHold
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(x.toBits())
            hasher.combine(footY.toBits())
            hasher.combine(fineAim.toBits())
            hasher.combine(pullBack.toBits())
            hasher.combine(dribbleBouncePx.toBits())
            hasher.combine(hotHand)
            hasher.combine(style)
            hasher.combine(pose)
            hasher.combine(celebrationProgress.toBits())
            hasher.combine(shotStyle)
            hasher.combine(facing)
            hasher.combine(motion)
            hasher.combine(dribblePhase01.toBits())
            hasher.combine(dribbleHandSign.toBits())
            hasher.combine(crossoverProgress.toBits())
            hasher.combine(crossoverFrom.toBits())
            hasher.combine(crossoverBehind)
            hasher.combine(moving)
            hasher.combine(movingFast)
            hasher.combine(locomotionFrameIndex)
            hasher.combine(characterId)
            hasher.combine(mirrorX)
            hasher.combine(actionFrameIndex)
            hasher.combine(visualScale.toBits())
            hasher.combine(playfulHold)
        }
    }

    private struct Palette {
        let pants: Int
        let jersey: Int
        let skin: Int
    }

    private struct ResolvedSpriteFrame {
        let set: CharacterSpriteSet
        let frame: CharacterSpriteFrame
    }

    /// `drawable.intrinsicWidth/intrinsicHeight` of a sprite drawable (see the file header).
    private struct SpriteSize {
        let intrinsicWidth: Int
        let intrinsicHeight: Int

        init(intrinsicWidth: Int, intrinsicHeight: Int) {
            self.intrinsicWidth = intrinsicWidth
            self.intrinsicHeight = intrinsicHeight
        }

        init(_ drawable: ADrawable) {
            self.init(intrinsicWidth: drawable.intrinsicWidth, intrinsicHeight: drawable.intrinsicHeight)
        }
    }

    /** Asset selection only; shared by GPU actors and the calibrated gameplay hand sockets. */
    func worldFrame(state: State) -> (first: CharacterSpriteSet, second: CharacterSpriteFrame)? {
        guard let set = TripleShotCharacterVisualCatalog.find(characterId: state.characterId) else { return nil }
        let frame: CharacterSpriteFrame
        switch state.pose {
        case .WINNER: frame = set.winner
        case .LOSER: frame = set.loser
        case .SPECTATOR: frame = set.spectator
        case .NORMAL: frame = proAssetFor(state: state)?.frame ?? set.idleBack
        }
        return (first: set, second: frame)
    }

    private let density: Float
    private let fill = APaint(APaint.ANTI_ALIAS_FLAG)
    private let stroke: APaint = {
        let paint = APaint(APaint.ANTI_ALIAS_FLAG)
        paint.style = APaint.Style.STROKE
        paint.strokeCap = APaint.Cap.ROUND
        paint.strokeJoin = APaint.Join.ROUND
        return paint
    }()
    private var spriteCache: [ADrawableRes: ADrawable] = [:]

    /// `android.os.SystemClock.uptimeMillis()` used by the wall-clock locomotion cadence (a test seam).
    var uptimeMillis: () -> Int64 = { ASystemClock.uptimeMillis() }

    /// Kotlin `TripleShotPlayerRenderer(context)`; the density is the display density (AResources.density).
    convenience init(context: Any? = nil) {
        self.init(density: AResources.density)
    }

    /// Kotlin positional call form `TripleShotPlayerRenderer(context)`.
    convenience init(_ context: Any?) {
        self.init(density: AResources.density)
    }

    /// `displayMetrics.density` given explicitly (tests and offscreen rasters).
    init(density: Float) {
        self.density = density
    }

    func draw(canvas: ACanvas, state: State) {
        let spriteSet = TripleShotCharacterVisualCatalog.find(characterId: state.characterId)

        if let spriteSet = spriteSet {
            switch state.pose {
            case .WINNER:
                if drawOutcomeSprite(canvas: canvas, state: state, set: spriteSet, frame: spriteSet.winner, winner: true) { return }
            case .LOSER:
                if drawOutcomeSprite(canvas: canvas, state: state, set: spriteSet, frame: spriteSet.loser, winner: false) { return }
            case .SPECTATOR:
                if drawOutcomeSprite(canvas: canvas, state: state, set: spriteSet, frame: spriteSet.spectator, winner: false) { return }
            case .NORMAL:
                if state.shotStyle == ShotStyle.PRO && drawProSprite(canvas: canvas, state: state) { return }
            }
        }

        // Safe fallback and the intentionally preserved classic/granny renderer.
        switch state.pose {
        case .NORMAL: drawLegacyNormal(canvas: canvas, state: state)
        case .WINNER: drawLegacyWinner(canvas: canvas, state: state)
        case .LOSER: drawLegacyLoser(canvas: canvas, state: state)
        case .SPECTATOR: drawLegacySpectator(canvas: canvas, state: state)
        }
    }

    /**
     * Top edge of the currently selected sprite in canvas coordinates.
     * TeamCourt uses this for name labels so labels follow the actual artwork instead of
     * assuming every character has Maya's height/proportions.
     */
    func visualTopY(state: State) -> Float {
        if state.pose == Pose.NORMAL &&
            state.shotStyle == ShotStyle.PRO &&
            TripleShotCharacterVisualCatalog.hasVisuals(characterId: state.characterId) {
            let resolved = proAssetFor(state: state)
            let drawable = resolved.flatMap { spriteSize(resId: $0.frame.resId) }
            if let resolved = resolved, let drawable = drawable {
                let sourceHeight = drawable.intrinsicHeight.coerceAtLeast(1).toFloat()
                let scale = spritePixelScale(drawable: drawable, resolved: resolved, visualScale: state.visualScale)
                return state.footY - sourceHeight * resolved.frame.anchorY01 * scale
            }
        }
        return state.footY - dp(112) * state.visualScale.coerceIn(0.85, 1.25)
    }

    /**
     * Position used by the real game ball and by the trajectory preview.
     * Every sprite is treated as BODY-ONLY artwork: these anchors only say where the
     * separate dynamic game ball belongs for the active pose. If a source image still
     * contains a basketball, that is an art-cleanup issue, never gameplay state.
     */
    func heldBallPosition(state: State) -> APointF {
        if state.pose == Pose.NORMAL &&
            state.shotStyle == ShotStyle.PRO &&
            TripleShotCharacterVisualCatalog.hasVisuals(characterId: state.characterId) {
            let resolved = proAssetFor(state: state)
            let frame = resolved?.frame
            let drawable = frame.flatMap { spriteSize(resId: $0.resId) }
            if let resolved = resolved, let frame = frame, let drawable = drawable, frame.hasBallAnchor {
                var anchored = spriteSourcePointToCanvas(
                    state: state,
                    drawable: drawable,
                    resolved: resolved,
                    sourceX: frame.ballSourceX!,
                    sourceY: frame.ballSourceY!
                )

                // Ball and body share the same facing. If a pose is mirrored, the socket mirrors
                // with it; the dribble side itself still alternates independently via handSign.
                if state.mirrorX {
                    anchored.x = state.x - (anchored.x - state.x)
                }

                // The selected game ball is always separate from the sprite. During a
                // dribble it leaves the hand diagonally toward the FRONT of the body, reaches
                // the floor near the player's centre line, then returns to the hand. This is
                // important for the depth cue: CourtView draws held/dribbled PRO balls before
                // the body, so a front leg can naturally occlude part of the ball at the low point.
                let handSign: Float = state.dribbleHandSign < 0 ? -1 : 1

                // When standing between bounces, keep the ball in whichever hand received
                // the previous bounce instead of snapping back to one fixed sprite anchor.
                if state.motion == Motion.IDLE && handSign < 0 {
                    anchored.x = state.x - (anchored.x - state.x)
                }

                if state.motion == Motion.DRIBBLE {
                    let bounce = state.dribbleBouncePx.coerceAtLeast(0)
                    let bounce01 =
                        (bounce / dp(TripleShotPlayerRenderer.DRIBBLE_BOUNCE_REFERENCE_DP).coerceAtLeast(1))
                            .coerceIn(0, 1)
                    let phase = state.dribblePhase01.coerceIn(0, 1)
                    let handDistance = abs(anchored.x - state.x).coerceAtLeast(dp(12))
                    let startHandX = state.x + handDistance * handSign

                    if state.moving && state.movingFast {
                        // Fast movement: one-hand dribble near the same-side shoe.
                        let shoeSideX = state.x + dp(TripleShotPlayerRenderer.DRIBBLE_WALK_LOW_X_DP) * handSign
                        anchored.x = startHandX + (shoeSideX - startHandX) * bounce01
                    } else {
                        // Standing OR slow movement: hand -> centre floor -> opposite hand.
                        // CourtView decides whether each slow-moving pass is physically
                        // in front of or behind the body by changing canvas depth.
                        let endHandX = state.x - handDistance * handSign
                        if phase <= 0.5 {
                            anchored.x = startHandX + (state.x - startHandX) * (phase * 2)
                        } else {
                            anchored.x = state.x + (endHandX - state.x) * ((phase - 0.5) * 2)
                        }
                    }
                    anchored.y += bounce
                }
                return anchored
            }
        }

        var legacy = legacyHeldBallPosition(state: state)
        if state.shotStyle == ShotStyle.PRO &&
            TripleShotCharacterVisualCatalog.hasVisuals(characterId: state.characterId) &&
            state.mirrorX {
            legacy.x = state.x - (legacy.x - state.x)
        }
        return legacy
    }

    /**
     * Sprites never own the ball. CourtView decides visibility from gameplay turn/physics,
     * while this renderer supplies only the correct ball anchor for the current pose.
     */

    /**
     * Repaints only the authored near-hand region above the separate dynamic ball.
     * Used for SIDE shooting poses so the ball sits between the hands instead of over both.
     */
    func drawBallForegroundOcclusion(canvas: ACanvas, state: State) {
        if state.pose != Pose.NORMAL ||
            state.shotStyle != ShotStyle.PRO ||
            !TripleShotCharacterVisualCatalog.hasVisuals(characterId: state.characterId) {
            return
        }

        guard let resolved = proAssetFor(state: state) else { return }
        let frame = resolved.frame
        guard let sourceRect01 = frame.ballForegroundRect01 else { return }
        guard let drawable = spriteDrawable(resId: frame.resId) else { return }

        let sourceWidth = drawable.intrinsicWidth.coerceAtLeast(1).toFloat()
        let sourceHeight = drawable.intrinsicHeight.coerceAtLeast(1).toFloat()
        let scale = spritePixelScale(drawable: SpriteSize(drawable), resolved: resolved, visualScale: state.visualScale)
        let left = state.x - sourceWidth * frame.anchorX01 * scale
        let top = state.footY - sourceHeight * frame.anchorY01 * scale

        var clipLeft = left + sourceWidth * sourceRect01.left * scale
        var clipRight = left + sourceWidth * sourceRect01.right * scale
        let clipTop = top + sourceHeight * sourceRect01.top * scale
        let clipBottom = top + sourceHeight * sourceRect01.bottom * scale

        if state.mirrorX {
            let mirroredLeft = state.x - (clipRight - state.x)
            let mirroredRight = state.x - (clipLeft - state.x)
            clipLeft = mirroredLeft
            clipRight = mirroredRight
        }

        let save = canvas.save()
        canvas.clipRect(clipLeft, clipTop, clipRight, clipBottom)
        drawSpriteDrawable(canvas: canvas, state: state, drawable: drawable, resolved: resolved, spriteFootY: state.footY)
        canvas.restoreToCount(save)
    }

    /** Vertical offset of the winner's feet/head while jumping. Useful for labels in CourtView. */
    func winnerJumpOffsetPx(progress: Float) -> Float {
        return abs(ksin(progress.coerceIn(0, 1) * PI_F * 4)) * dp(20)
    }

    private func drawProSprite(canvas: ACanvas, state: State) -> Bool {
        guard let resolved = proAssetFor(state: state) else { return false }
        guard let drawable = spriteDrawable(resId: resolved.frame.resId) else { return false }

        drawShadow(canvas: canvas, x: state.x, footY: state.footY, halfWidth: dp(29), alpha: 66)

        let movementBob: Float
        switch state.motion {
        case .WALK: movementBob = (state.dribbleBouncePx * 0.045).coerceAtMost(dp(2.2))
        case .DRIBBLE: movementBob = (state.dribbleBouncePx * 0.025).coerceAtMost(dp(1.4))
        default: movementBob = 0
        }
        drawSpriteDrawable(canvas: canvas, state: state, drawable: drawable, resolved: resolved, spriteFootY: state.footY - movementBob)

        if state.hotHand {
            drawFlame(canvas: canvas, x: state.x - dp(31), y: state.footY - dp(87), size: dp(18))
        }
        return true
    }

    private func drawOutcomeSprite(
        canvas: ACanvas,
        state: State,
        set: CharacterSpriteSet,
        frame: CharacterSpriteFrame,
        winner: Bool
    ) -> Bool {
        guard let drawable = spriteDrawable(resId: frame.resId) else { return false }
        let jump: Float = winner ? winnerJumpOffsetPx(progress: state.celebrationProgress) : 0
        let spriteFootY = state.footY - jump

        let shadowScale: Float =
            winner ? 1 - (jump / dp(20)).coerceIn(0, 1) * 0.35
            : 1
        drawShadow(canvas: canvas, x: state.x, footY: state.footY, halfWidth: dp(31) * shadowScale, alpha: 68)
        drawSpriteDrawable(
            canvas: canvas,
            state: state,
            drawable: drawable,
            resolved: ResolvedSpriteFrame(set: set, frame: frame),
            spriteFootY: spriteFootY
        )
        return true
    }

    private func proAssetFor(state: State) -> ResolvedSpriteFrame? {
        guard let set = TripleShotCharacterVisualCatalog.find(characterId: state.characterId) else { return nil }

        if state.style == Style.BOT && state.playfulHold, let playfulHold = set.playfulHold {
            return ResolvedSpriteFrame(set: set, frame: playfulHold)
        }
        let frame: CharacterSpriteFrame
        switch state.motion {
        case .IDLE, .WAITING, .WALK, .DRIBBLE:
            let walking = state.moving && !set.locomotion.isEmpty
            if walking {
                let frameIndex = state.locomotionFrameIndex >= 0 ? state.locomotionFrameIndex % set.locomotion.count
                    : ((uptimeMillis() / (state.movingFast ? 205 : 250)) % Int64(set.locomotion.count)).toInt()
                frame = directionalActionFrame(action: set.locomotion[frameIndex], facing: state.facing)!
            } else if state.motion == Motion.DRIBBLE && BasketballFeedbackArt.dribble(id: state.characterId, facing: state.facing) != nil {
                frame = BasketballFeedbackArt.dribble(id: state.characterId, facing: state.facing)!
            } else {
                switch state.facing {
                case .FRONT: frame = set.idleFront
                case .BACK: frame = set.idleBack
                case .SIDE: frame = set.idleSide ?? set.idleBack
                }
            }

        case .STEAL:
            if let action = directionalActionFrame(action: set.steal, facing: state.facing) {
                frame = action
            } else {
                switch state.facing {
                case .BACK: frame = set.shotBack.low
                case .SIDE: frame = set.shotSide.low
                case .FRONT: frame = set.shotFront.low
                }
            }

        case .BLOCK:
            if let action = directionalActionFrame(action: set.block, facing: state.facing) {
                frame = action
            } else {
                switch state.facing {
                case .BACK: frame = set.shotBack.set
                case .SIDE: frame = set.shotSide.set
                case .FRONT: frame = set.shotFront.set
                }
            }

        case .REBOUND:
            if let action = directionalActionFrame(action: set.rebound, facing: state.facing) ??
                directionalActionFrame(action: set.block, facing: state.facing) {
                frame = action
            } else {
                switch state.facing {
                case .BACK: frame = set.shotBack.set
                case .SIDE: frame = set.shotSide.set
                case .FRONT: frame = set.shotFront.set
                }
            }

        case .DUNK:
            if let dunk = set.dunks.getOrNull(state.actionFrameIndex)?.frame ??
                set.dunks.first(where: { $0.facing == state.facing })?.frame ??
                directionalActionFrame(action: set.block, facing: state.facing) {
                frame = dunk
            } else {
                switch state.facing {
                case .BACK: frame = set.shotBack.set
                case .SIDE: frame = set.shotSide.set
                case .FRONT: frame = set.shotFront.set
                }
            }

        case .SHOT_LOW:
            switch state.facing {
            case .BACK: frame = set.shotBack.low
            case .SIDE: frame = set.shotSide.low
            case .FRONT: frame = set.shotFront.low
            }

        case .SHOT_MID:
            switch state.facing {
            case .BACK: frame = set.shotBack.mid
            case .SIDE: frame = set.shotSide.mid
            case .FRONT: frame = set.shotFront.mid
            }

        case .SHOT_SET:
            switch state.facing {
            case .BACK: frame = set.shotBack.set
            case .SIDE: frame = set.shotSide.set
            case .FRONT: frame = set.shotFront.set
            }

        case .RELEASE:
            switch state.facing {
            case .BACK: frame = set.shotBack.release ?? set.shotBack.set
            case .SIDE: frame = set.shotSide.release ?? set.shotSide.set
            case .FRONT: frame = set.shotFront.release ?? set.shotFront.set
            }
        }

        return ResolvedSpriteFrame(set: set, frame: frame)
    }

    private func directionalActionFrame(
        action: CharacterDirectionalActionSprites?,
        facing: Facing
    ) -> CharacterSpriteFrame? {
        guard let it = action else { return nil }
        switch facing {
        case .BACK: return it.back
        case .SIDE: return it.side
        case .FRONT: return it.front
        }
    }

    private func drawSpriteDrawable(
        canvas: ACanvas,
        state: State,
        drawable: ADrawable,
        resolved: ResolvedSpriteFrame,
        spriteFootY: Float
    ) {
        let frame = resolved.frame
        let sourceWidth = drawable.intrinsicWidth.coerceAtLeast(1).toFloat()
        let sourceHeight = drawable.intrinsicHeight.coerceAtLeast(1).toFloat()
        let scale = spritePixelScale(drawable: SpriteSize(drawable), resolved: resolved, visualScale: state.visualScale)

        let left = state.x - sourceWidth * frame.anchorX01 * scale
        let top = spriteFootY - sourceHeight * frame.anchorY01 * scale
        let right = left + sourceWidth * scale
        let bottom = top + sourceHeight * scale

        drawable.setBounds(
            left.toInt(),
            top.toInt(),
            right.toInt(),
            bottom.toInt()
        )

        if state.mirrorX {
            canvas.save()
            canvas.scale(-1, 1, state.x, spriteFootY)
            drawable.draw(canvas)
            canvas.restore()
        } else {
            drawable.draw(canvas)
        }
    }

    private func spriteSourcePointToCanvas(
        state: State,
        drawable: SpriteSize,
        resolved: ResolvedSpriteFrame,
        sourceX: Float,
        sourceY: Float
    ) -> APointF {
        let frame = resolved.frame
        let sourceWidth = drawable.intrinsicWidth.coerceAtLeast(1).toFloat()
        let sourceHeight = drawable.intrinsicHeight.coerceAtLeast(1).toFloat()
        let scale = spritePixelScale(drawable: drawable, resolved: resolved, visualScale: state.visualScale)
        let left = state.x - sourceWidth * frame.anchorX01 * scale
        let top = state.footY - sourceHeight * frame.anchorY01 * scale

        return APointF(
            left + sourceX * scale,
            top + sourceY * scale
        )
    }

    private func spritePixelScale(
        drawable: SpriteSize,
        resolved: ResolvedSpriteFrame,
        visualScale: Float
    ) -> Float {
        let targetHeightDp = resolved.frame.targetHeightDp
        let authoredScale: Float
        if let targetHeightDp = targetHeightDp {
            authoredScale = dp(targetHeightDp) / drawable.intrinsicHeight.coerceAtLeast(1).toFloat()
        } else {
            authoredScale = dp(resolved.set.referenceHeightDp) /
                resolved.set.referenceHeightPx.coerceAtLeast(1)
        }
        return authoredScale * visualScale.coerceIn(0.85, 1.25)
    }

    /// Kotlin `spriteCache.getOrPut(resId) { ContextCompat.getDrawable(appContext, resId)?.mutate() }`
    /// (a null result is not kept, so it is looked up again next time, like `getOrPut`).
    private func spriteDrawable(resId: ADrawableRes) -> ADrawable? {
        if let cached = spriteCache[resId] {
            return cached
        }
        let answer = ContextCompat_getDrawable(resId)?.mutate()
        spriteCache[resId] = answer
        return answer
    }

    /// The intrinsic size `spriteDrawable(resId:)` would report, read from the size table (no decoding). Android's
    /// `ContextCompat.getDrawable` gives a drawable for every existing resource; nil stands for a missing one.
    private func spriteSize(resId: ADrawableRes) -> SpriteSize? {
        guard AResources.drawableExists(resId) else { return nil }
        let size = AResources.drawableIntrinsicSize(resId)
        return SpriteSize(intrinsicWidth: size.width, intrinsicHeight: size.height)
    }

    private func legacyHeldBallPosition(state: State) -> APointF {
        return APointF(
            state.x + dp(18) + state.fineAim * dp(6),
            state.footY - dp(64) +
                state.pullBack.coerceIn(0, 1) * dp(18) +
                state.dribbleBouncePx
        )
    }

    private func drawLegacyNormal(canvas: ACanvas, state: State) {
        let palette = self.palette(style: state.style)
        let x = state.x
        let footY = state.footY
        let lean = state.fineAim * dp(9)
        let load = state.pullBack.coerceIn(0, 1)
        let kneeDrop = load * dp(6)

        drawShadow(canvas: canvas, x: x, footY: footY, halfWidth: dp(25), alpha: 70)

        stroke.strokeWidth = dp(7)
        stroke.color = palette.pants
        canvas.drawLine(
            x - dp(7),
            footY - dp(36) + kneeDrop,
            x - dp(13),
            footY,
            stroke
        )
        canvas.drawLine(
            x + dp(7),
            footY - dp(36) + kneeDrop,
            x + dp(14),
            footY,
            stroke
        )

        fill.style = APaint.Style.FILL
        fill.color = palette.jersey
        canvas.drawRoundRect(
            ARectF(
                x - dp(18) + lean * 0.2,
                footY - dp(86) + kneeDrop,
                x + dp(18) + lean * 0.2,
                footY - dp(34) + kneeDrop
            ),
            dp(10),
            dp(10),
            fill
        )

        fill.color = palette.skin
        canvas.drawCircle(
            x + lean * 0.35,
            footY - dp(102) + kneeDrop,
            dp(15),
            fill
        )

        stroke.strokeWidth = dp(6)
        stroke.color = palette.skin
        let handX = x + dp(19) + lean
        let handY = footY - dp(64) + load * dp(18)

        canvas.drawLine(
            x - dp(12),
            footY - dp(73) + kneeDrop,
            handX - dp(6),
            handY,
            stroke
        )
        canvas.drawLine(
            x + dp(12),
            footY - dp(73) + kneeDrop,
            handX + dp(4),
            handY,
            stroke
        )

        if state.hotHand {
            drawFlame(canvas: canvas, x: x - dp(24), y: footY - dp(78), size: dp(18))
        }
    }

    private func drawLegacyWinner(canvas: ACanvas, state: State) {
        let palette = self.palette(style: state.style)
        let x = state.x
        let groundY = state.footY
        let jump = winnerJumpOffsetPx(progress: state.celebrationProgress)
        let footY = groundY - jump

        let shadowScale = 1 - (jump / dp(20)).coerceIn(0, 1) * 0.35
        drawShadow(canvas: canvas, x: x, footY: groundY, halfWidth: dp(25) * shadowScale, alpha: 62)

        stroke.strokeWidth = dp(7)
        stroke.color = palette.pants
        canvas.drawLine(x - dp(6), footY - dp(35), x - dp(13), footY, stroke)
        canvas.drawLine(x + dp(6), footY - dp(35), x + dp(13), footY, stroke)

        fill.style = APaint.Style.FILL
        fill.color = palette.jersey
        canvas.drawRoundRect(
            ARectF(x - dp(18), footY - dp(88), x + dp(18), footY - dp(34)),
            dp(10),
            dp(10),
            fill
        )

        fill.color = palette.skin
        canvas.drawCircle(x, footY - dp(104), dp(15), fill)

        stroke.strokeWidth = dp(6)
        stroke.color = palette.skin
        canvas.drawLine(
            x - dp(12), footY - dp(76),
            x - dp(28), footY - dp(121),
            stroke
        )
        canvas.drawLine(
            x + dp(12), footY - dp(76),
            x + dp(28), footY - dp(121),
            stroke
        )

        fill.color = palette.skin
        canvas.drawCircle(x - dp(29), footY - dp(124), dp(4.5), fill)
        canvas.drawCircle(x + dp(29), footY - dp(124), dp(4.5), fill)
    }

    private func drawLegacyLoser(canvas: ACanvas, state: State) {
        let palette = self.palette(style: state.style)
        let x = state.x
        let footY = state.footY
        let hipY = footY - dp(22)
        let shoulderY = hipY - dp(43)

        drawShadow(canvas: canvas, x: x, footY: footY, halfWidth: dp(31), alpha: 78)

        stroke.strokeWidth = dp(7)
        stroke.color = palette.pants
        canvas.drawLine(x - dp(7), hipY, x - dp(18), footY - dp(12), stroke)
        canvas.drawLine(x - dp(18), footY - dp(12), x - dp(31), footY, stroke)
        canvas.drawLine(x + dp(7), hipY, x + dp(18), footY - dp(12), stroke)
        canvas.drawLine(x + dp(18), footY - dp(12), x + dp(31), footY, stroke)

        fill.style = APaint.Style.FILL
        fill.color = palette.jersey
        canvas.drawRoundRect(
            ARectF(x - dp(19), shoulderY - dp(9), x + dp(19), hipY + dp(4)),
            dp(10),
            dp(10),
            fill
        )

        fill.color = palette.skin
        canvas.drawCircle(x + dp(3), shoulderY - dp(23), dp(15), fill)

        stroke.strokeWidth = dp(6)
        stroke.color = palette.skin
        canvas.drawLine(
            x - dp(12), shoulderY + dp(4),
            x - dp(24), hipY + dp(5),
            stroke
        )
        canvas.drawLine(
            x + dp(12), shoulderY + dp(4),
            x + dp(24), hipY + dp(5),
            stroke
        )
    }

    private func drawLegacySpectator(canvas: ACanvas, state: State) {
        let palette = self.palette(style: state.style)
        let x = state.x
        let footY = state.footY
        let hipY = footY - dp(23)
        let shoulderY = hipY - dp(45)

        drawShadow(canvas: canvas, x: x, footY: footY, halfWidth: dp(30), alpha: 66)

        stroke.strokeWidth = dp(7)
        stroke.color = palette.pants
        canvas.drawLine(x - dp(7), hipY, x - dp(20), footY - dp(11), stroke)
        canvas.drawLine(x - dp(20), footY - dp(11), x - dp(30), footY, stroke)
        canvas.drawLine(x + dp(7), hipY, x + dp(20), footY - dp(11), stroke)
        canvas.drawLine(x + dp(20), footY - dp(11), x + dp(30), footY, stroke)

        fill.style = APaint.Style.FILL
        fill.color = palette.jersey
        canvas.drawRoundRect(
            ARectF(x - dp(19), shoulderY - dp(10), x + dp(19), hipY + dp(4)),
            dp(10),
            dp(10),
            fill
        )

        fill.color = palette.skin
        canvas.drawCircle(x, shoulderY - dp(24), dp(15), fill)

        stroke.strokeWidth = dp(6)
        stroke.color = palette.skin
        canvas.drawLine(x - dp(11), shoulderY + dp(2), x - dp(20), hipY + dp(2), stroke)
        canvas.drawLine(x + dp(11), shoulderY + dp(2), x + dp(20), hipY + dp(2), stroke)
    }

    private func palette(style: Style) -> Palette {
        switch style {
        case .HUMAN:
            return Palette(
                pants: AColor.rgb(32, 55, 71),
                jersey: AColor.rgb(8, 126, 112),
                skin: AColor.rgb(242, 190, 145)
            )
        case .BOT:
            return Palette(
                pants: AColor.rgb(53, 43, 92),
                jersey: AColor.rgb(118, 73, 167),
                skin: AColor.rgb(242, 190, 145)
            )
        }
    }

    private func drawShadow(
        canvas: ACanvas,
        x: Float,
        footY: Float,
        halfWidth: Float,
        alpha: Int
    ) {
        fill.style = APaint.Style.FILL
        fill.color = AColor.argb(alpha, 0, 0, 0)
        canvas.drawOval(
            ARectF(x - halfWidth, footY - dp(3), x + halfWidth, footY + dp(8)),
            fill
        )
    }

    private func drawFlame(
        canvas: ACanvas,
        x: Float,
        y: Float,
        size: Float
    ) {
        let path = APath()
        path.moveTo(x, y - size)
        path.cubicTo(
            x + size * 0.65,
            y - size * 0.45,
            x + size * 0.55,
            y + size * 0.35,
            x,
            y + size * 0.75
        )
        path.cubicTo(
            x - size * 0.65,
            y + size * 0.25,
            x - size * 0.45,
            y - size * 0.35,
            x,
            y - size
        )

        fill.color = AColor.argb(175, 255, 90, 20)
        canvas.drawPath(path, fill)

        fill.color = AColor.argb(190, 255, 205, 45)
        canvas.drawCircle(x, y + size * 0.08, size * 0.28, fill)
    }

    private func dp(_ v: Float) -> Float {
        return v * density
    }

    private static let DRIBBLE_BOUNCE_REFERENCE_DP: Float = 49
    private static let DRIBBLE_WALK_LOW_X_DP: Float = 13

    // Kotlin positional call forms.
    func worldFrame(_ state: State) -> (first: CharacterSpriteSet, second: CharacterSpriteFrame)? { return worldFrame(state: state) }
    func draw(_ canvas: ACanvas, _ state: State) { draw(canvas: canvas, state: state) }
    func visualTopY(_ state: State) -> Float { return visualTopY(state: state) }
    func heldBallPosition(_ state: State) -> APointF { return heldBallPosition(state: state) }
    func drawBallForegroundOcclusion(_ canvas: ACanvas, _ state: State) { drawBallForegroundOcclusion(canvas: canvas, state: state) }
    func winnerJumpOffsetPx(_ progress: Float) -> Float { return winnerJumpOffsetPx(progress: progress) }
}
