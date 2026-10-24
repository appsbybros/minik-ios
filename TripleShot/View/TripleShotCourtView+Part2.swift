// TripleShotCourtView+Part2.swift
//
// Port of android view/TripleShotCourtView.kt lines 2655-5347 (spec 09-court2): the local 1v1 action, AI and
// contact layer (contested jumpers, drive finishes, the scripted bot dunk, pump fakes, crossovers, hesitations,
// spins, shot escapes, defender positioning, body collisions, box-out, steals, blocks, loose ball, rebounds),
// the local-bot / Shooting Challenge turn helpers, and the human and bot shot launchers (animateBotShot,
// setStation, animateShot).
//
// Rules (DESIGN 2.9 / 2.10): this file is an extension only. Every stored property lives in part 1
// (TripleShotCourtView.swift) under its Kotlin name; companion constants are static members declared by the part
// that owns the companion object; nothing here is an `override`. Kotlin `private` members are `internal`.
// Units are Android pixels (DESIGN 2.5); all simulation maths stays in Float with Kotlin's operation order.
// Every `sin` is computed in Double (`sin(t * Math.PI).toFloat()`), every `sqrt` through `ksqrt`.

import Foundation

/// Re-entrancy depth of the 1v1 steal lunge offsets (spec 09 §8.8 / §10.3). Android's
/// humanRendererState -> oneOnOneHumanStealVisualOffset -> heldBotBallPosition -> botRendererState ->
/// oneOnOneBotStealVisualOffset -> heldBallPosition -> humanRendererState chain only terminates because the two steal
/// reaches can never be active at the same time (possession protections outlast the 310 ms reach). While one lunge
/// is being computed, a nested lunge of either side reports no offset, which is exactly what it reports in every
/// state Android can reach; it only turns the unreachable both-reaches-active case from a stack overflow into (0, 0).
@MainActor private var court2StealLungeDepth = 0

extension TripleShotCourtView {

    // MARK: - Contested jump-shots (Kotlin 2650-2703)

    /**
     * An open set-shot may stay grounded. When the defender is genuinely close, start a real
     * vertical jump during the release gather. The ball socket then rises with the body, so the
     * higher release is naturally harder to block without changing the block hitbox by fiat.
     */
    @discardableResult
    func beginOneOnOneHumanContestedJumperIfNeeded() -> Bool {
        if !oneOnOneEnabled || sharedHorseBallOwner != .HUMAN { return false }
        if oneOnOneLooseBallActive || shotFrameRunning || botShotFrameRunning { return false }

        let dx = botX - playerX
        let dy = (botFootY - playerFootY) * Self.ONE_ON_ONE_COLLISION_Y_SCALE
        let distance = ksqrt(dx * dx + dy * dy)
        let closeDistance =
            dp(
                v: Self.ONE_ON_ONE_CONTESTED_JUMPER_BASE_DISTANCE_DP +
                    Self.ONE_ON_ONE_CONTESTED_JUMPER_DEFENSE_BONUS_DP *
                        (Float(oneOnOneBotDefenseRating.coerceIn(0, 100)) / 100)
            )
        if distance > closeDistance { return false }

        let now = ASystem.nanoTime()
        oneOnOneHumanJumpStartedAtNanos = now
        oneOnOneHumanJumpUntilNanos =
            now + Self.ONE_ON_ONE_CONTESTED_JUMPER_JUMP_MS * 1_000_000
        oneOnOneHumanJumpHeightMultiplier = Self.ONE_ON_ONE_CONTESTED_JUMPER_MULTIPLIER
        invalidate()
        return true
    }

    /** Bot equivalent: an open jumper can stay compact, but a defender in her space makes Maya
     * rise into a real jump shot. Jump rating scales the actual vertical reach. */
    @discardableResult
    func beginOneOnOneBotContestedJumperIfNeeded() -> Bool {
        if !oneOnOneEnabled || sharedHorseBallOwner != .BOT { return false }
        if oneOnOneLooseBallActive || shotFrameRunning || botShotFrameRunning || oneOnOneBotDunkActive { return false }

        let dx = playerX - botX
        let dy = (playerFootY - botFootY) * Self.ONE_ON_ONE_COLLISION_Y_SCALE
        let distance = ksqrt(dx * dx + dy * dy)
        let closeDistance =
            dp(
                v: Self.ONE_ON_ONE_CONTESTED_JUMPER_BASE_DISTANCE_DP +
                    Self.ONE_ON_ONE_CONTESTED_JUMPER_DEFENSE_BONUS_DP *
                        (Float(oneOnOneHumanDefenseRating.coerceIn(0, 100)) / 100)
            )
        if distance > closeDistance { return false }

        let now = ASystem.nanoTime()
        oneOnOneBotJumpStartedAtNanos = now
        oneOnOneBotJumpUntilNanos =
            now + Self.ONE_ON_ONE_CONTESTED_JUMPER_JUMP_MS * 1_000_000
        oneOnOneBotJumpHeightMultiplier = Self.ONE_ON_ONE_CONTESTED_JUMPER_MULTIPLIER
        invalidate()
        return true
    }

    // MARK: - Human drive finish (Kotlin 2705-2762)

    /**
     * Starts the first layup/dunk step with the selected character's directional finish frames.
     */
    @discardableResult
    func beginOneOnOneHumanDriveFinish(finish: OneOnOneDriveFinish) -> Bool {
        if finish == .JUMPER { return true }
        if !oneOnOneEnabled || sharedHorseBallOwner != .HUMAN { return false }
        oneOnOneHumanActiveFinish = finish
        ALog.i("TRIPLE_PLAY", "humanFinish=\(finish.name)")

        // The approach already happened in the live drive. Jump from those real feet.
        // The old final-step/side-lane correction teleported the body 1–3 metres here.
        // Safe release coordinates are handled by the shot plane, never by relocating a player.
        let now = ASystem.nanoTime()
        oneOnOneHumanJumpStartedAtNanos = now
        oneOnOneHumanJumpUntilNanos =
            now + (finish == .DUNK ? Self.ONE_ON_ONE_DUNK_JUMP_MS : Self.ONE_ON_ONE_LAYUP_JUMP_MS) * 1_000_000
        oneOnOneHumanJumpHeightMultiplier =
            finish == .DUNK ? Float(1.58) : Float(1.24)
        invalidate()
        return true
    }

    // MARK: - Bot finish choice and open lane (Kotlin 2764-2827)

    func chooseOneOnOneBotDriveFinish(
        movementIntensity01: Float,
        dunkAbility: Int
    ) -> OneOnOneDriveFinish {
        if !oneOnOneEnabled || sharedHorseBallOwner != .BOT {
            return .JUMPER
        }

        let t = backgroundTransform()
        let sourceX = ((botX - t.offsetX) / t.scaleX).coerceIn(0, Self.BACKGROUND_WIDTH)
        let sourceY = ((botFootY - t.offsetY) / t.scaleY).coerceIn(0, Self.BACKGROUND_HEIGHT)
        let dxSrc = Self.SRC_HOOP_CENTER_X - sourceX
        let dySrc = Self.SRC_HOOP_DEPTH_FOOT_Y - sourceY
        let distanceSrc = ksqrt(dxSrc * dxSrc + dySrc * dySrc)
        if distanceSrc > Self.ONE_ON_ONE_LAYUP_MAX_DISTANCE_SRC { return .JUMPER }

        let hoop = sourcePointToView(sourceX: Self.SRC_HOOP_CENTER_X, sourceY: Self.SRC_HOOP_DEPTH_FOOT_Y)
        let hx = hoop.x - botX
        let hy = hoop.y - botFootY
        let hLen = ksqrt(hx * hx + hy * hy).coerceAtLeast(1)
        let ux = hx / hLen
        let uy = hy / hLen
        let defX = playerX - botX
        let defY = playerFootY - botFootY
        let forward = defX * ux + defY * uy
        let lateral = abs(defX * uy - defY * ux)
        let laneHalfWidth = dp(v: oneOnOneBodyRadiusDp(human: true) + 13)
        let immediateLaneDepth = kmin(hLen, dp(v: Self.ONE_ON_ONE_BOT_IMMEDIATE_LANE_DEPTH_DP))
        let defenderOwnsLane =
            (forward >= 0 && forward <= immediateLaneDepth) &&
                lateral < laneHalfWidth
        if defenderOwnsLane { return .JUMPER }

        let speed = movementIntensity01.coerceIn(0, 1)
        let dunk = dunkAbility.coerceIn(0, 100)
        if distanceSrc <= Self.ONE_ON_ONE_DUNK_MAX_DISTANCE_SRC &&
            speed >= Self.ONE_ON_ONE_DUNK_MIN_SPEED &&
            dunk >= Self.ONE_ON_ONE_DUNK_MIN_ABILITY {
            return .DUNK
        }
        if speed >= Self.ONE_ON_ONE_LAYUP_MIN_SPEED { return .LAYUP }
        return .JUMPER
    }

    func oneOnOneBotHasOpenRimLane() -> Bool {
        if !oneOnOneEnabled || sharedHorseBallOwner != .BOT { return false }
        let hoop = sourcePointToView(sourceX: Self.SRC_HOOP_CENTER_X, sourceY: Self.SRC_HOOP_DEPTH_FOOT_Y)
        let hx = hoop.x - botX
        let hy = hoop.y - botFootY
        let hLen = ksqrt(hx * hx + hy * hy).coerceAtLeast(1)
        let ux = hx / hLen
        let uy = hy / hLen
        let defX = playerX - botX
        let defY = playerFootY - botFootY
        let forward = defX * ux + defY * uy
        let lateral = abs(defX * uy - defY * ux)
        let laneHalfWidth = dp(v: oneOnOneBodyRadiusDp(human: true) + 18)

        // "Open lane" means the next part of the drive is open, not that no defender exists
        // anywhere between Maya and the rim. A defender 250dp ahead should make Maya advance,
        // not pull up from the same bad spot forever.
        let immediateLaneDepth = kmin(hLen, dp(v: Self.ONE_ON_ONE_BOT_IMMEDIATE_LANE_DEPTH_DP))
        return !((forward >= 0 && forward <= immediateLaneDepth) && lateral < laneHalfWidth)
    }

    // MARK: - Contest permission, pump-fake bite, held motion, bot pressure (Kotlin 2829-2876)

    /** Current gather decides whether the bot is willing to bite on the shot fake. */
    func setOneOnOneBotContestAllowed(allowed: Bool) {
        oneOnOneBotContestAllowed = allowed
        if !allowed && !shotFrameRunning {
            oneOnOneBotContestActive = false
            botPullBack = 0
        }
        invalidate()
    }

    /**
     * Starts a real visible contest jump for a pump fake when geometry allows it.
     * The Fragment decides whether this defender bites; CourtView only verifies that the defender
     * is actually close/in front enough to make that reaction believable.
     */
    @discardableResult
    func oneOnOneBotBiteOnPumpFake() -> Bool {
        if !oneOnOneEnabled ||
            sharedHorseBallOwner != .HUMAN ||
            !shotGuidesVisible ||
            oneOnOneLooseBallActive {
            return false
        }

        maybeStartOneOnOneBotContest()
        return oneOnOneBotContestActive
    }

    /** Visual-only LOW/MID hold while the human has legally picked up the dribble. */
    func setOneOnOneHumanHeldMotion(high: Bool?) {
        switch high {
        case .some(true):
            oneOnOneHumanHeldMotionOverride = .SHOT_MID
        case .some(false):
            oneOnOneHumanHeldMotionOverride = .SHOT_LOW
        case .none:
            oneOnOneHumanHeldMotionOverride = nil
        }
        invalidate()
    }

    /** 0..1 pressure around the bot's live dribble, used by AI to decide when to protect the ball. */
    func oneOnOneBotPressure01() -> Float {
        if !oneOnOneEnabled || sharedHorseBallOwner != .BOT { return 0 }
        let ball = heldBotBallPosition()
        let dx = ball.x - playerX
        let dy = ball.y - (playerFootY - dp(v: 68))
        let dist = ksqrt(dx * dx + dy * dy)
        return (1 - dist / dp(v: 112)).coerceIn(0, 1)
    }

    // MARK: - Shot-contest metric and gather defense (Kotlin 2878-2949)

    /**
     * Live shot pressure, 0 = clean look and 1 = fully smothered. This is deliberately based on
     * body position first: a defender between the ball and the rim matters even without a block
     * animation. Defense/Agility improve containment; Stealing/Blocking stay separate skills.
     */
    func oneOnOneShotContest01(shooterHuman: Bool) -> Float {
        if !oneOnOneEnabled || !botEnabled || width <= 0 || height <= 0 { return 0 }

        let shooterX = shooterHuman ? playerX : botX
        let shooterY = shooterHuman ? playerFootY : botFootY
        let defenderX = shooterHuman ? botX : playerX
        let defenderY = shooterHuman ? botFootY : playerFootY
        let defense = shooterHuman ? oneOnOneBotDefenseRating : oneOnOneHumanDefenseRating
        let agility = shooterHuman ? oneOnOneBotAgilityRating : oneOnOneHumanAgilityRating

        let hoop = sourcePointToView(sourceX: Self.SRC_HOOP_CENTER_X, sourceY: Self.SRC_HOOP_DEPTH_FOOT_Y)
        let hx = hoop.x - shooterX
        let hy = hoop.y - shooterY
        let hLen = ksqrt(hx * hx + hy * hy).coerceAtLeast(1)
        let ux = hx / hLen
        let uy = hy / hLen

        let dx = defenderX - shooterX
        let dy = defenderY - shooterY
        let distance = ksqrt(dx * dx + dy * dy)
        let forward = dx * ux + dy * uy
        let lateral = abs(dx * uy - dy * ux)

        // A defender behind the shooter may still bother a release, but is not rewarded like
        // somebody who actually stayed between the ball and the basket.
        let frontFactor: Float
        if forward < -dp(v: 10) {
            frontFactor = 0.18
        } else if forward > hLen {
            frontFactor = 0.26
        } else {
            frontFactor = 1
        }
        let proximity = (1 - distance / dp(v: 176)).coerceIn(0, 1)
        let lane = (1 - lateral / dp(v: 96)).coerceIn(0, 1)
        let positioning = (proximity * 0.68 + lane * 0.32) * frontFactor
        let ratingScale: Float = 0.58 + (Float(defense) / 100) * 0.31 + (Float(agility) / 100) * 0.11

        let now = ASystem.nanoTime()
        let activeHandBonus: Float
        if shooterHuman && oneOnOneBotContestActive {
            activeHandBonus = 0.17
        } else if !shooterHuman && now < oneOnOneHumanBlockUntilNanos {
            activeHandBonus = 0.17
        } else {
            activeHandBonus = 0
        }
        let fooledMultiplier: Float =
            (shooterHuman && now < oneOnOneBotReactionLockedUntilNanos) ? 0.10 : 1

        return ((positioning * ratingScale + activeHandBonus) * fooledMultiplier)
            .coerceIn(0, 1)
    }

    func oneOnOneHumanShotContest01() -> Float { return oneOnOneShotContest01(shooterHuman: true) }

    func oneOnOneBotShotContest01() -> Float { return oneOnOneShotContest01(shooterHuman: false) }

    /**
     * While the shooter is holding the ball, a defender who was beaten is allowed to recover once
     * the earned stun window ends. This prevents "create space, wait forever" from becoming the
     * dominant strategy and makes the timing after a fake/crossover genuinely valuable.
     */
    func oneOnOneAdvanceBotDefenseDuringGather() {
        if !oneOnOneEnabled || sharedHorseBallOwner != .HUMAN ||
            !shotGuidesVisible || shotFrameRunning || oneOnOneLooseBallActive {
            return
        }
        updateOneOnOneBotDefensePosition(force: false)
        resolveHumanBotBodyCollision()
    }

    // MARK: - Bot escape side, finish range, bot drive finish (Kotlin 2951-3063)

    /**
     * Side-step direction for the bot. It still protects the ball from the defender, but the
     * sideline is part of the decision: a smart escape should create one step of space, not run
     * forever until the attacker is trapped at the edge of the screen.
     */
    func oneOnOneBotEscapeSideSign() -> Float {
        if !oneOnOneEnabled || width <= 0 { return playerX <= botX ? 1 : -1 }

        let minX = horseFreeMinX()
        let maxX = horseFreeMaxX()
        let edgeBand = dp(v: Self.ONE_ON_ONE_BOT_EDGE_TURN_DP)
        if botX <= minX + edgeBand { return 1 }
        if botX >= maxX - edgeBand { return -1 }

        // Protecting the ball should not mean fleeing to the sideline forever. Once Maya has
        // drifted meaningfully outside the hoop lane, her next protection/crossover bends back
        // toward the basket unless the defender is literally occupying that side.
        let hoopX = sourcePointToView(sourceX: Self.SRC_HOOP_CENTER_X, sourceY: Self.SRC_HOOP_DEPTH_FOOT_Y).x
        let inwardSign: Float = hoopX >= botX ? 1 : -1
        let farFromLane = abs(botX - hoopX) >= dp(v: Self.ONE_ON_ONE_BOT_REATTACK_LANE_DP)
        let defenderBlocksInward: Bool
        if inwardSign > 0 {
            defenderBlocksInward = playerX > botX && playerX - botX < dp(v: 52)
        } else {
            defenderBlocksInward = playerX < botX && botX - playerX < dp(v: 52)
        }
        if farFromLane && !defenderBlocksInward { return inwardSign }

        return playerX <= botX ? 1 : -1
    }

    func oneOnOneBotIsAtFinishRange() -> Bool {
        if !oneOnOneEnabled || width <= 0 || height <= 0 { return false }
        let t = backgroundTransform()
        let sourceX = ((botX - t.offsetX) / t.scaleX).coerceIn(0, Self.BACKGROUND_WIDTH)
        let sourceY = ((botFootY - t.offsetY) / t.scaleY).coerceIn(0, Self.BACKGROUND_HEIGHT)
        let dx = Self.SRC_HOOP_CENTER_X - sourceX
        let dy = Self.SRC_HOOP_DEPTH_FOOT_Y - sourceY
        let distance = ksqrt(dx * dx + dy * dy)
        return distance <= Self.ONE_ON_ONE_LAYUP_MAX_DISTANCE_SRC * 0.88
    }

    @discardableResult
    func beginOneOnOneBotDriveFinish(
        finish: OneOnOneDriveFinish,
        preferredSideSign: Float = 0
    ) -> Bool {
        if finish == .JUMPER { return true }
        if !oneOnOneEnabled || sharedHorseBallOwner != .BOT { return false }

        // The approach already happened in the live drive. Jump from those real feet.
        // The old final-step/side-lane correction teleported the body 1–3 metres here.
        // Safe release coordinates are handled by the shot plane, never by relocating a player.
        let now = ASystem.nanoTime() + (finish == .DUNK ? 0 : Self.BOT_VISIBLE_AIM_MS - Self.ONE_ON_ONE_LAYUP_JUMP_MS / 2) * 1_000_000
        oneOnOneBotJumpStartedAtNanos = now
        oneOnOneBotJumpUntilNanos =
            now + (finish == .DUNK ? Self.ONE_ON_ONE_DUNK_JUMP_MS : Self.ONE_ON_ONE_LAYUP_JUMP_MS) * 1_000_000
        oneOnOneBotJumpHeightMultiplier = finish == .DUNK ? Float(1.58) : Float(1.24)
        invalidate()
        return true
    }

    // MARK: - Bot dunk (Kotlin 3065-3370)

    /**
     * Picks a dunk that fits the live approach angle and speed, but keeps a real lottery inside
     * that bucket so the player eventually sees the whole Maya dunk library. The previous dunk is
     * down-weighted to avoid obvious repetition.
     */
    func chooseOneOnOneBotDunkFrame() -> Int {
        guard let set = TripleShotCharacterVisualCatalog.find(characterId: botCharacterId) else { return -1 }
        if set.dunks.isEmpty { return -1 }

        let hoop = sourcePointToView(sourceX: Self.SRC_HOOP_CENTER_X, sourceY: Self.SRC_HOOP_PLANE_Y)
        let naturalFacing = oneOnOneActionFacing(actorX: botX, actorFootY: botFootY, targetX: hoop.x, targetY: hoop.y)
        let speed = oneOnOneBotRecentAttackIntensity01.coerceIn(0, 1)
        let random =
            KotlinRandom(seed: ASystem.nanoTime() ^ (oneOnOneLooseEventSerial &* 0x4D41594144554E4B))
        // Most finishes respect the camera/approach. Occasionally Maya intentionally turns in the
        // air (reverse/180/flash finish), which is how FRONT/SIDE wow frames can still appear from
        // an ordinary BACK drive instead of becoming dead art.
        let showboat = random.nextFloat() < 0.22

        var weights: [(index: Int, score: Float)] = []
        for (index, sprite) in set.dunks.enumerated() {
            let speedFit = (1 - abs(speed - sprite.preferredSpeed01) / 0.55).coerceIn(0, 1)
            let angleFit: Float
            if showboat {
                angleFit = sprite.facing == naturalFacing ? 0.86 : 0.68
            } else if sprite.facing == naturalFacing {
                angleFit = 1
            } else if sprite.facing == .SIDE {
                angleFit = 0.28
            } else {
                angleFit = 0.16
            }
            let antiRepeat: Float = index == oneOnOneBotLastDunkFrameIndex ? 0.18 : 1
            // Keep a uniform floor: angle/speed choose the BEST-looking dunk, never ban the rest.
            let score =
                sprite.weight *
                    (0.34 + 0.66 * speedFit) *
                    angleFit *
                    antiRepeat
            weights.append((index: index, score: score.coerceAtLeast(0.018)))
        }
        // Kotlin `sumOf { it.second.toDouble() }` accumulates in Double, in list order.
        var sum: Double = 0
        for weight in weights { sum += Double(weight.score) }
        let total = Float(sum).coerceAtLeast(0.001)
        var pick = random.nextFloat() * total
        for weight in weights {
            pick -= weight.score
            if pick <= 0 { return weight.index }
        }
        return weights[weights.count - 1].index
    }

    /** Unused in Android too (no callers); kept for API parity. */
    func currentOneOnOneBotDunkSprite() -> CharacterDunkSprite? {
        return TripleShotCharacterVisualCatalog.find(characterId: botCharacterId)?.dunks.getOrNull(oneOnOneBotDunkFrameIndex)
    }

    /** Dynamic-ball socket authored directly into the selected dunk frame. */
    func oneOnOneBotDunkBallSocket() -> APointF {
        return playerRenderer.heldBallPosition(state: botRendererState())
    }

    /**
     * Real 1v1 dunk path.
     *
     * DUNK is not a projectile. The ball is visually attached to Maya's extended hand while her
     * body rises to the rim, then that same hand pushes the ball down through the cylinder. The
     * defender can still stop it only with a real block-window hand overlap before rim contact.
     */
    func animateOneOnOneBotDunk(onEnd: @escaping (ShotResult) -> Void) {
        if !oneOnOneEnabled || !botEnabled || sharedHorseBallOwner != .BOT { return }

        if width <= 0 || height <= 0 {
            post { [weak self] in self?.animateOneOnOneBotDunk(onEnd: onEnd) }
            return
        }

        cancelBotShotSimulation(callEnd: false)
        cancelOneOnOneBotDunk()

        let geometry = buildPhysicsGeometry()
        let startBall = heldBotBallPosition()
        oneOnOneBotDunkFrameIndex = chooseOneOnOneBotDunkFrame()
        let selectedDunk =
            TripleShotCharacterVisualCatalog.find(characterId: botCharacterId)?.dunks.getOrNull(oneOnOneBotDunkFrameIndex)
        let naturalFacing =
            oneOnOneActionFacing(actorX: botX, actorFootY: botFootY, targetX: geometry.hoopCenterX, targetY: geometry.hoopY)
        oneOnOneBotDunkFacing = selectedDunk?.facing ?? naturalFacing
        oneOnOneBotDunkMirrorX = geometry.hoopCenterX < botX
        if oneOnOneBotDunkFrameIndex >= 0 {
            oneOnOneBotLastDunkFrameIndex = oneOnOneBotDunkFrameIndex
        }
        let sideSign: Float = botX < geometry.hoopCenterX ? -1 : 1
        let poseLiftPx = dp(v: selectedDunk?.contactLiftDp ?? 0)
        let poseOutwardPx = dp(v: selectedDunk?.contactOutwardDp ?? 0)
        let rimTopX =
            geometry.hoopCenterX +
                sideSign * (geometry.ballRadius * 0.18 + poseOutwardPx)
        let rimTopY = geometry.hoopY - geometry.ballRadius * 0.70 - poseLiftPx
        // Every dedicated dunk frame owns a dynamic-ball socket in/under the hands. Pose-specific
        // contact polish lets reverse/side dunks clear the rim instead of visually sitting inside it.
        let contactBallX = rimTopX
        let contactBallY = rimTopY
        let throughY = geometry.netBottomY + geometry.ballRadius * 0.82

        oneOnOneBotActiveFinish = .DUNK
        oneOnOneBotDunkActive = true
        oneOnOneBotDunkBlocked = false
        oneOnOneBotDunkReleasedPose = false
        oneOnOneBotShotBlocked = false
        oneOnOneBotDunkRenderShiftX = 0
        oneOnOneBotDunkRenderLiftPx = 0
        botShotOnEnd = onEnd
        botPullBack = 0
        botFineAim = 0
        botBallVisible = true
        botBallX = startBall.x
        botBallY = startBall.y
        botBallRotationDeg = 0

        var finished = false
        var netKicked = false
        var contactShiftX: Float = 0
        var contactLiftPx: Float = 0

        // Kotlin local `fun finishDunk(made: Boolean)`; the captured locals are shared by reference.
        let finishDunk: (Bool) -> Void = { [weak self] made in
            guard let self = self else { return }
            if finished { return }
            finished = true

            let callback = botShotOnEnd
            botShotOnEnd = nil
            oneOnOneBotDunkAnimator = nil
            oneOnOneBotDunkActive = false
            oneOnOneBotDunkReleasedPose = false
            oneOnOneBotDunkRenderShiftX = 0
            oneOnOneBotDunkRenderLiftPx = 0
            oneOnOneBotActiveFinish = .JUMPER

            if made {
                botBallVisible = false
                botBallX = geometry.hoopCenterX
                botBallY = throughY
                callback?(
                    ShotResult(
                        outcome: ShotOutcome(
                            made: true,
                            targetOffsetX: 0,
                            targetOffsetY: 0,
                            quality: 1
                        ),
                        kind: .SWISH,
                        rimHits: 0,
                        backboardHits: 0
                    )
                )
            } else {
                // A blocked dunk becomes a short live scramble, not a full-power shot rebound.
                let dx = botBallX - playerX
                let dy = botBallY - (playerFootY - dp(v: 84))
                let len = ksqrt(dx * dx + dy * dy).coerceAtLeast(1)
                let vx = dx / len * dp(v: 118)
                let vy = dy / len * dp(v: 72) - dp(v: 82)
                startOneOnOneLooseBall(
                    x: botBallX,
                    y: botBallY,
                    vx: vx,
                    vy: vy,
                    claimDelaySeconds: Self.ONE_ON_ONE_REBOUND_CLAIM_MIN_AGE_SECONDS,
                    gravityPxPerSec2: geometry.gravityPxPerSec2
                )
                callback?(
                    ShotResult(
                        outcome: ShotOutcome(
                            made: false,
                            targetOffsetX: 0,
                            targetOffsetY: 0,
                            quality: 0
                        ),
                        kind: .AIRBALL,
                        rimHits: 0,
                        backboardHits: 0
                    )
                )
            }
            invalidate()
        }

        let dunkAnimator = AValueAnimator.ofFloat(0, 1)
        dunkAnimator.duration = Self.ONE_ON_ONE_DUNK_ACTION_MS
        dunkAnimator.interpolator = ALinearInterpolator()
        dunkAnimator.addUpdateListener { [weak self] animator in
            guard let self = self else { return }
            let t = animator.animatedValueFloat.coerceIn(0, 1)

            if t < Self.ONE_ON_ONE_DUNK_RIM_CONTACT_T {
                let rise01 = (t / Self.ONE_ON_ONE_DUNK_RIM_CONTACT_T).coerceIn(0, 1)
                let eased = 1 - (1 - rise01) * (1 - rise01)

                /*
                 * Align the authored extended hand with the actual rim. Recompute against the
                 * current sine jump every frame, then ease only the EXTRA shift/lift. At contact
                 * the hand, ball and rim therefore meet at the same visible point.
                 */
                oneOnOneBotDunkRenderShiftX = 0
                oneOnOneBotDunkRenderLiftPx = 0
                let baseSocket = oneOnOneBotDunkBallSocket()
                oneOnOneBotDunkRenderShiftX = (contactBallX - baseSocket.x) * eased
                oneOnOneBotDunkRenderLiftPx =
                    ((baseSocket.y - contactBallY).coerceAtLeast(0)) * eased
                contactShiftX = oneOnOneBotDunkRenderShiftX
                contactLiftPx = oneOnOneBotDunkRenderLiftPx

                let attachedBall = oneOnOneBotDunkBallSocket()
                let attach01 =
                    (t / Self.ONE_ON_ONE_DUNK_BALL_ATTACH_T)
                        .coerceIn(0, 1)
                botBallX = lerp(a: startBall.x, b: attachedBall.x, t: attach01)
                botBallY = lerp(a: startBall.y, b: attachedBall.y, t: attach01)
            } else {
                let down01 =
                    ((t - Self.ONE_ON_ONE_DUNK_RIM_CONTACT_T) /
                        (1 - Self.ONE_ON_ONE_DUNK_RIM_CONTACT_T))
                        .coerceIn(0, 1)

                // Hang at full extension while the hand visibly powers the ball through.
                let hang: Float
                if down01 <= Self.ONE_ON_ONE_DUNK_HANG_FRACTION {
                    hang = 1
                } else {
                    hang = (1 -
                        (down01 - Self.ONE_ON_ONE_DUNK_HANG_FRACTION) /
                            (1 - Self.ONE_ON_ONE_DUNK_HANG_FRACTION))
                        .coerceIn(0, 1)
                }
                oneOnOneBotDunkRenderShiftX = contactShiftX * hang
                oneOnOneBotDunkRenderLiftPx = contactLiftPx * hang

                botBallX = lerp(a: contactBallX, b: geometry.hoopCenterX, t: down01)
                botBallY = lerp(a: contactBallY, b: throughY, t: down01)
            }

            // The human block button still creates the existing real raised-hand window.
            // Only a physical hand/ball overlap before the cylinder can stop the dunk.
            if !oneOnOneBotDunkBlocked &&
                t <= Self.ONE_ON_ONE_DUNK_BLOCK_CUTOFF_T &&
                ASystem.nanoTime() < oneOnOneHumanBlockUntilNanos {
                let hand = oneOnOneHumanBlockHandPoint(ballX: botBallX, ballY: botBallY)
                let reach =
                    geometry.ballRadius +
                        dp(v: 7 + 8 * (Float(oneOnOneHumanBlockRating) / 100))
                let dx = botBallX - hand.x
                let dy = botBallY - hand.y
                if dx * dx + dy * dy <= reach * reach {
                    oneOnOneBotDunkBlocked = true
                    oneOnOneBotShotBlocked = true
                    oneOnOneBlockEventListener?(true)
                    animator.cancel()
                    return
                }
            }

            if !netKicked && t >= Self.ONE_ON_ONE_DUNK_RIM_CONTACT_T {
                netKicked = true
                triggerNetKick(
                    impactSpeed: dp(v: 250),
                    directionHint: sideSign
                )
            }

            // Once the ball has clearly left the hands, do not keep the contact sprite buried
            // in the rim/net while the ball falls. The body stays on the same airborne dunk
            // trajectory but swaps to the directional block/follow-through art.
            if !oneOnOneBotDunkReleasedPose && t >= Self.ONE_ON_ONE_DUNK_POSE_RELEASE_T {
                oneOnOneBotDunkReleasedPose = true
            }
            invalidate()
        }
        dunkAnimator.addListener(AAnimatorListenerAdapter(
            onEnd: { [weak self] _ in
                guard let self = self else { return }
                if !finished && oneOnOneBotDunkActive {
                    finishDunk(!oneOnOneBotDunkBlocked)
                }
            },
            onCancel: { [weak self] _ in
                guard let self = self else { return }
                if oneOnOneBotDunkBlocked {
                    finishDunk(false)
                }
            }
        ))
        dunkAnimator.start()
        // Kotlin assigns the field after `apply { ...; start() }` returns, i.e. after the synchronous
        // first update (which may already have blocked and finished the dunk).
        oneOnOneBotDunkAnimator = dunkAnimator
    }

    func cancelOneOnOneBotDunk() {
        if !oneOnOneBotDunkActive && oneOnOneBotDunkAnimator == nil { return }
        oneOnOneBotDunkActive = false
        oneOnOneBotDunkBlocked = false
        oneOnOneBotDunkReleasedPose = false
        oneOnOneBotDunkRenderShiftX = 0
        oneOnOneBotDunkRenderLiftPx = 0
        oneOnOneBotDunkFrameIndex = -1
        oneOnOneBotDunkAnimator?.cancel()
        oneOnOneBotDunkAnimator = nil
        botShotOnEnd = nil
        oneOnOneBotActiveFinish = .JUMPER
    }

    // MARK: - Human aim prepare / cancel, pump fake (Kotlin 3372-3452)

    /** Freezes the current grounded position as the real shooting origin and shows the full arc. */
    @discardableResult
    func prepareOneOnOneHumanShot(showArc: Bool = true) -> Bool {
        if !oneOnOneEnabled ||
            sharedHorseBallOwner != .HUMAN ||
            shotFrameRunning ||
            botShotFrameRunning ||
            width <= 0 ||
            height <= 0 {
            return false
        }

        clampHumanToHorseFreeBounds()
        let source = currentPlayerSourcePosition()
        let dx = source.x - Self.SRC_HOOP_CENTER_X
        let dy = source.y - Self.SRC_HOOP_PLANE_Y
        let distance = ksqrt(dx * dx + dy * dy)
        let difficulty = ((distance - 280) / 820).coerceIn(0.12, 0.96)

        horseHumanStation = Station(
            id: "ONE_ON_ONE",
            sourceX: source.x,
            sourceY: source.y,
            distanceDifficulty: difficulty,
            zone: "one_on_one"
        )
        horseFreeMoveEnabled = false
        fineAim = 0
        pullBack = 0
        shotGuidesVisible = true
        oneOnOneSuppressShotGuideDrawing = !showArc
        cancelHumanIdleDribble()
        invalidate()
        return true
    }

    /** Cancels aiming. If it was a fake, the defender stays committed briefly before recovering. */
    func cancelOneOnOneHumanAim(pumpFake: Bool) {
        if !oneOnOneEnabled { return }
        shotGuidesVisible = false
        oneOnOneSuppressShotGuideDrawing = false
        horseHumanStation = nil
        horseFreeMoveEnabled = true
        fineAim = 0
        pullBack = 0

        if pumpFake && oneOnOneBotContestActive {
            let recoveryDelay = Self.ONE_ON_ONE_CONTEST_FAKE_HOLD_MS
            postDelayed({ [weak self] in
                guard let self = self else { return }
                if !oneOnOneEnabled || shotFrameRunning { return }
                oneOnOneBotContestActive = false
                botPullBack = 0
                oneOnOneBotContestRecoveryUntilNanos =
                    ASystem.nanoTime() + Self.ONE_ON_ONE_CONTEST_RECOVERY_MS * 1_000_000
                invalidate()
            }, recoveryDelay)
        } else if !shotFrameRunning {
            oneOnOneBotContestActive = false
            botPullBack = 0
        }

        scheduleHumanIdleDribble()
        invalidate()
    }

    /**
     * Gesture pump-fake: keep the shooter in aim mode, drop the ball back to LOW and make the
     * defender pay for biting. Unlike cancelOneOnOneHumanAim(), this does not hide the arc or
     * leave the shooting state, so LOW -> MID -> SET can be repeated several times naturally.
     */
    func oneOnOnePumpFakeCycle() {
        if !oneOnOneEnabled || sharedHorseBallOwner != .HUMAN || !shotGuidesVisible { return }
        pullBack = 0.02
        if oneOnOneBotContestActive {
            oneOnOneBotContestActive = false
            botPullBack = 0
            oneOnOneBotReactionLockedUntilNanos =
                ASystem.nanoTime() + Self.ONE_ON_ONE_PUMP_FAKE_STUN_MS * 1_000_000
            oneOnOneBotContestRecoveryUntilNanos = oneOnOneBotReactionLockedUntilNanos
        }
        invalidate()
    }

    // MARK: - Human crossover, hesitation, contact spin (Kotlin 3454-3563)

    /**
     * Fast left-right-left movement gives the ball-handler a real separation window. The directional
     * body frames and a continuous behind-back ball path present the move.
     */
    func oneOnOneHumanCrossover(directionSign: Float) {
        if !oneOnOneEnabled || sharedHorseBallOwner != .HUMAN || shotGuidesVisible { return }
        let now = ASystem.nanoTime()
        let handling01 = Float(oneOnOneHumanBallHandlingRating) / 100
        let offense01 = Float(oneOnOneHumanOffenseRating) / 100
        let defenderRecovery01 =
            (Float(oneOnOneBotAgilityRating) * 0.62 + Float(oneOnOneBotDefenseRating) * 0.38) / 100
        let creator01 = (handling01 * 0.62 + offense01 * 0.38).coerceIn(0, 1)
        let edge = (creator01 - defenderRecovery01).coerceIn(-0.75, 0.75)
        let windowMs =
            (Int64(300) + (creator01 * 230).toLong() + (edge * 70).toLong())
                .coerceIn(260, 560)
        let stunMs =
            (Int64(230) + (creator01 * 390).toLong() + (edge * 180).toLong())
                .coerceIn(180, 720)
        oneOnOneHumanCrossoverUntilNanos = now + windowMs * 1_000_000
        oneOnOneBotReactionLockedUntilNanos = now + stunMs * 1_000_000
        humanCrossBehind = now &- humanCrossAt < 2_200_000_000 && !humanCrossBehind
        humanCrossAt = now
        humanCrossFrom = humanDribbleHandSign
        humanDribbleHandSign = -humanDribbleHandSign
        humanWalkingDribbleHandSign = humanDribbleHandSign
        // The move is easy to trigger, but elite creation comes from ratings + timing against the
        // specific defender rather than from a hidden button combo.
        humanWalkingBallPassInFront = !humanCrossBehind
        ALog.i("TRIPLE_PLAY", humanCrossBehind ? "humanMove=behindBack" : "humanMove=crossover")
        // The swipe supplies translation; do not teleport the body when changing hands.
        clampHumanToHorseFreeBounds()
        invalidate()
    }

    /** A quick drive-then-retreat hesitation buys a short reaction gap without moving the defender. */
    func oneOnOneHumanHesitation() {
        if !oneOnOneEnabled || sharedHorseBallOwner != .HUMAN || shotGuidesVisible { return }
        let now = ASystem.nanoTime()
        let handling01 = Float(oneOnOneHumanBallHandlingRating) / 100
        let stunMs = (Int64(190) + (handling01 * 250).toLong()).coerceIn(190, 440)
        oneOnOneBotReactionLockedUntilNanos = max(
            oneOnOneBotReactionLockedUntilNanos,
            now + stunMs * 1_000_000
        )
        invalidate()
    }

    /**
     * Contact spin: used only when the handler is already on the defender's body. It rotates the
     * drive around the defender instead of phasing through them. The direction sequence follows a
     * continuous turn around the defender.
     */
    @discardableResult
    func oneOnOneHumanSpin(directionSign: Float) -> Bool {
        if !oneOnOneEnabled ||
            sharedHorseBallOwner != .HUMAN ||
            shotGuidesVisible ||
            !isOneOnOneHumanInBodyContact() {
            return false
        }

        let now = ASystem.nanoTime()
        let hoop = sourcePointToView(sourceX: Self.SRC_HOOP_CENTER_X, sourceY: Self.SRC_HOOP_DEPTH_FOOT_Y)
        let fx = hoop.x - botX
        let fy = hoop.y - botFootY
        let fl = ksqrt(fx * fx + fy * fy).coerceAtLeast(1)
        let forwardX = fx / fl
        let forwardY = fy / fl
        let sideSign: Float = directionSign < 0 ? -1 : 1
        let lateralX = -forwardY * sideSign
        let lateralY = forwardX * sideSign

        let handling01 = Float(oneOnOneHumanBallHandlingRating) / 100
        let offense01 = Float(oneOnOneHumanOffenseRating) / 100
        let defenderRecovery01 =
            (Float(oneOnOneBotAgilityRating) * 0.62 + Float(oneOnOneBotDefenseRating) * 0.38) / 100
        let creator01 = handling01 * 0.58 + offense01 * 0.42
        let edge = (creator01 - defenderRecovery01).coerceIn(-0.65, 0.65)
        let lateralDp = Self.ONE_ON_ONE_SPIN_LATERAL_DP * (0.68 + creator01 * 0.44 + edge * 0.10)
        let forwardDp = Self.ONE_ON_ONE_SPIN_FORWARD_DP * (0.68 + creator01 * 0.42 + edge * 0.12)
        let startX = playerX
        let startY = playerFootY
        humanSpinAt = now
        humanCrossAt = now
        humanCrossFrom = humanDribbleHandSign
        playerMoveAnimator?.cancel()
        let spinAnimator = AValueAnimator.ofFloat(0, 1)
        spinAnimator.duration = 360
        spinAnimator.interpolator = ADecelerateInterpolator()
        spinAnimator.addUpdateListener { [weak self] animator in
            guard let self = self else { return }
            let t = animator.animatedValueFloat
            let side = Float(sin(Double(t) * Double.pi * 0.5))
            playerX = startX + lateralX * dp(v: lateralDp) * side + forwardX * dp(v: forwardDp) * t
            playerFootY = startY + lateralY * dp(v: lateralDp) * side + forwardY * dp(v: forwardDp) * t
            clampHumanToHorseFreeBounds()
            resolveHumanBotBodyCollision()
            invalidate()
        }
        spinAnimator.start()
        playerMoveAnimator = spinAnimator
        ALog.i("TRIPLE_PLAY", "humanMove=spin")

        let spinWindowMs =
            (Self.ONE_ON_ONE_SPIN_WINDOW_MS + (edge * 120).toLong()).coerceIn(380, 640)
        let result = humanSpinSeries.attempt(now: now / 1_000_000, defense: oneOnOneBotDefenseRating,
                                             random: { KotlinRandom.Default.nextFloat() })
        oneOnOneHumanCrossoverUntilNanos = result.success ? now + spinWindowMs * 1_000_000 : now
        if result.success {
            oneOnOneBotReactionLockedUntilNanos = now + result.recoveryMs * 1_000_000
            if result.fall { botFallenUntil = oneOnOneBotReactionLockedUntilNanos }
        }
        ALog.i("TRIPLE_PLAY", "spin human success=\(result.success) fall=\(result.fall) chance=\(javaString(result.chance))")
        humanDribbleHandSign = sideSign
        humanWalkingDribbleHandSign = sideSign
        invalidate()
        return true
    }

    // MARK: - Bot attack step, bot crossover / contact spin (Kotlin 3565-3647)

    /**
     * Continuous bot drive step used by the Fragment's possession script. `forwardDp` is toward
     * the hoop; `lateralDp` is a perpendicular cut. Body collision is resolved every step, so the
     * human can genuinely contain a drive instead of watching an animator pass through them.
     */
    func moveOneOnOneBotAttackStep(forwardDp: Float, lateralDp: Float) {
        if !oneOnOneEnabled ||
            sharedHorseBallOwner != .BOT ||
            oneOnOneLooseBallActive ||
            botShotFrameRunning {
            return
        }

        let hoop = sourcePointToView(sourceX: Self.SRC_HOOP_CENTER_X, sourceY: Self.SRC_HOOP_DEPTH_FOOT_Y)
        let fx = hoop.x - botX
        let fy = hoop.y - botFootY
        let fl = ksqrt(fx * fx + fy * fy).coerceAtLeast(1)
        let ux = fx / fl
        let uy = fy / fl
        let lx = -uy
        let ly = ux

        let requestedForwardPx = dp(v: forwardDp)
        let forwardPx: Float
        if requestedForwardPx > 0 {
            // Normal dribbling stops before the rim. Layup/dunk gets its own final step in
            // beginOneOnOneBotDriveFinish(), so the bot cannot accidentally stand under the
            // cylinder and shoot upward through it.
            forwardPx = kmin(
                requestedForwardPx,
                (fl - dp(v: Self.ONE_ON_ONE_BOT_GROUNDED_RIM_STOP_DP)).coerceAtLeast(0)
            )
        } else {
            forwardPx = requestedForwardPx
        }
        botX += ux * forwardPx + lx * dp(v: lateralDp)
        botFootY += uy * forwardPx + ly * dp(v: lateralDp)
        let liveStepMagnitudeDp =
            ksqrt(forwardDp * forwardDp + lateralDp * lateralDp)
        let stepIntensity = (liveStepMagnitudeDp / 3.85).coerceIn(0.28, 1)
        let athleticScale: Float = 0.82 + 0.18 * (Float(oneOnOneBotSpeedRating.coerceIn(0, 100)) / 100)
        oneOnOneBotRecentAttackIntensity01 =
            (oneOnOneBotRecentAttackIntensity01 * 0.58 + stepIntensity * athleticScale * 0.42)
                .coerceIn(0.28, 1)
        botX = botX.coerceIn(horseFreeMinX(), horseFreeMaxX())
        botFootY = clampHorseFreeY(x: botX, y: botFootY)
        resolveBotHumanBodyCollision()
        let now = ASystem.nanoTime()
        oneOnOneBotDrivingUntilNanos = now + 150 * 1_000_000
        let bouncePhase = Float((now / 1_000_000) % Self.ONE_ON_ONE_BOT_DRIBBLE_PERIOD_MS) /
            Float(Self.ONE_ON_ONE_BOT_DRIBBLE_PERIOD_MS)
        botDribbleBouncePx = abs(Float(sin(Double(bouncePhase) * Double.pi * 2.0))) * dp(v: 34)
        invalidate()
    }

    /** Lateral burst for a bot crossover. No hidden human stun: the separation is physical. */
    func oneOnOneBotCrossover(directionSign: Float) {
        if !oneOnOneEnabled || sharedHorseBallOwner != .BOT || botShotFrameRunning { return }
        let sign: Float = directionSign < 0 ? -1 : 1
        botCrossBehind = ASystem.nanoTime() &- botCrossAt < 2_200_000_000 && !botCrossBehind
        botCrossAt = ASystem.nanoTime()
        botCrossFrom = botDribbleHandSign
        botDribbleHandSign = -botDribbleHandSign
        let startX = botX
        let startY = botFootY
        let contact = isOneOnOneHumanInBodyContact()
        let dx: Float = dp(v: Self.ONE_ON_ONE_BOT_CROSSOVER_BURST_DP) * (contact ? Float(1.7) : Float(1)) * sign
        let hoop = sourcePointToView(sourceX: Self.SRC_HOOP_CENTER_X, sourceY: Self.SRC_HOOP_DEPTH_FOOT_Y)
        let dy: Float = contact ? dp(v: 18) * (hoop.y < botFootY ? Float(-1) : Float(1)) : 0
        if contact {
            botSpinAt = ASystem.nanoTime()
            let result = botSpinSeries.attempt(now: botSpinAt / 1_000_000, defense: oneOnOneHumanDefenseRating,
                                               random: { KotlinRandom.Default.nextFloat() })
            if result.success {
                humanRecoveryUntil = botSpinAt + result.recoveryMs * 1_000_000
                if result.fall { humanFallenUntil = humanRecoveryUntil }
            }
            ALog.i("TRIPLE_PLAY", "spin bot success=\(result.success) fall=\(result.fall) chance=\(javaString(result.chance))")
        }
        botMoveAnimator?.cancel()
        let crossAnimator = AValueAnimator.ofFloat(0, 1)
        crossAnimator.duration = contact ? 360 : 230
        crossAnimator.interpolator = ADecelerateInterpolator()
        crossAnimator.addUpdateListener { [weak self] animator in
            guard let self = self else { return }
            let t = animator.animatedValueFloat
            botX = (startX + dx * t).coerceIn(horseFreeMinX(), horseFreeMaxX())
            botFootY = clampHorseFreeY(x: botX, y: startY + dy * t)
            resolveBotHumanBodyCollision()
            invalidate()
        }
        crossAnimator.start()
        botMoveAnimator = crossAnimator
        ALog.i("TRIPLE_PLAY", contact ? "botMove=spin" : "botMove=behindBack")
        invalidate()
    }

    // MARK: - Human jump/rebound, shot escape, human 1v1 shot (Kotlin 3649-3795)

    /**
     * Off-ball jump/rebound. The body gets a real vertical offset and the loose-ball simulation
     * checks the raised hand every frame during the jump window.
     */
    @discardableResult
    func oneOnOneHumanJumpOrReboundAttempt(allowBlock: Bool = true) -> Bool {
        if !oneOnOneEnabled { return false }
        let now = ASystem.nanoTime()
        oneOnOneHumanJumpStartedAtNanos = now
        oneOnOneHumanJumpUntilNanos = now + Self.ONE_ON_ONE_JUMP_MS * 1_000_000
        oneOnOneHumanJumpHeightMultiplier =
            allowBlock ? Self.ONE_ON_ONE_BLOCK_JUMP_MULTIPLIER : Self.ONE_ON_ONE_REBOUND_JUMP_MULTIPLIER
        if allowBlock &&
            sharedHorseBallOwner == .BOT &&
            botShotFrameRunning {
            oneOnOneHumanBlockUntilNanos = now + Self.ONE_ON_ONE_HUMAN_BLOCK_WINDOW_MS * 1_000_000
        }
        if oneOnOneLooseBallActive {
            resolveOneOnOneLooseBallPossession(now: now)
        }
        invalidate()
        postDelayed({ [weak self] in self?.invalidate() }, Self.ONE_ON_ONE_JUMP_MS + 30)
        return true
    }

    /**
     * A tap on the jump/escape pad while aiming performs a fadeaway; dragging that pad left/right
     * performs a side-step. The shooting station is rebuilt from the new feet position so the
     * physical release really starts from the escaped location.
     */
    @discardableResult
    func oneOnOneHumanShotEscape(move: OneOnOneShotEscape) -> Bool {
        if !oneOnOneEnabled || sharedHorseBallOwner != .HUMAN || !shotGuidesVisible { return false }

        let hoop = sourcePointToView(sourceX: Self.SRC_HOOP_CENTER_X, sourceY: Self.SRC_HOOP_DEPTH_FOOT_Y)
        let toHoopX = hoop.x - playerX
        let toHoopY = hoop.y - playerFootY
        let len = ksqrt(toHoopX * toHoopX + toHoopY * toHoopY).coerceAtLeast(1)
        let ux = toHoopX / len
        let uy = toHoopY / len
        let lateralX = -uy
        let lateralY = ux

        // Fade distance must reflect the momentum that actually existed before the gather. A tiny
        // retreat should create a compact Kobe-style hop, not slide half a court. A full-speed
        // drive can still produce the larger escape. Side-steps keep their authored distance.
        let moveSpeed01 =
            (humanMovementSpeedDpPerSec / Self.ONE_ON_ONE_FADE_SPEED_REFERENCE_DP_PER_SEC)
                .coerceIn(0, 1)
        let distance =
            dp(
                v: move == .FADE_AWAY
                    ? Self.ONE_ON_ONE_FADE_BASE_DISTANCE_DP +
                        Self.ONE_ON_ONE_FADE_EXTRA_DISTANCE_DP * moveSpeed01
                    : Self.ONE_ON_ONE_ESCAPE_DISTANCE_DP
            )

        switch move {
        case .FADE_AWAY:
            playerX -= ux * distance
            playerFootY -= uy * distance
        case .SIDE_LEFT:
            playerX -= lateralX * distance
            playerFootY -= lateralY * distance
        case .SIDE_RIGHT:
            playerX += lateralX * distance
            playerFootY += lateralY * distance
        }

        clampHumanToHorseFreeBounds()
        oneOnOneHumanJumpStartedAtNanos = ASystem.nanoTime()
        oneOnOneHumanJumpUntilNanos = oneOnOneHumanJumpStartedAtNanos + Self.ONE_ON_ONE_ESCAPE_JUMP_MS * 1_000_000
        oneOnOneHumanJumpHeightMultiplier =
            move == .FADE_AWAY
                ? Self.ONE_ON_ONE_FADE_MIN_JUMP_MULTIPLIER +
                    Self.ONE_ON_ONE_FADE_EXTRA_JUMP_MULTIPLIER * moveSpeed01
                : Self.ONE_ON_ONE_SIDE_STEP_JUMP_MULTIPLIER
        let escapeCreation01 =
            (Float(oneOnOneHumanOffenseRating) * 0.62 + Float(oneOnOneHumanAgilityRating) * 0.38) / 100
        let defenderRecovery01 =
            (Float(oneOnOneBotDefenseRating) * 0.42 + Float(oneOnOneBotAgilityRating) * 0.58) / 100
        let escapeEdge = (escapeCreation01 - defenderRecovery01).coerceIn(-0.65, 0.65)
        let defenderDelayMs =
            (Self.ONE_ON_ONE_ESCAPE_DEFENDER_DELAY_MS + (escapeEdge * 190).toLong())
                .coerceIn(140, 390)
        oneOnOneBotReactionLockedUntilNanos =
            ASystem.nanoTime() + defenderDelayMs * 1_000_000
        oneOnOneBotContestActive = false
        botPullBack = 0

        let source = currentPlayerSourcePosition()
        let dx = source.x - Self.SRC_HOOP_CENTER_X
        let dy = source.y - Self.SRC_HOOP_PLANE_Y
        let distanceSrc = ksqrt(dx * dx + dy * dy)
        horseHumanStation = Station(
            id: "ONE_ON_ONE_ESCAPE",
            sourceX: source.x,
            sourceY: source.y,
            distanceDifficulty: ((distanceSrc - 280) / 820).coerceIn(0.12, 0.96),
            zone: "one_on_one"
        )
        invalidate()
        return true
    }

    func animateOneOnOneHumanShot(
        skill: ShotSkill,
        pullBackAtRelease: Float,
        finish: OneOnOneDriveFinish = .JUMPER,
        onEnd: @escaping (ShotResult) -> Void
    ) {
        if !oneOnOneEnabled || sharedHorseBallOwner != .HUMAN { return }
        oneOnOneHumanShotBlocked = false
        // A quick shooter can release before the pre-shot pull threshold lingered long enough.
        // Re-check real geometry at release so a close defender can still jump after the ball is up.
        maybeStartOneOnOneBotContest()
        if oneOnOneBotContestActive {
            let now = ASystem.nanoTime()
            oneOnOneBotJumpStartedAtNanos = now
            oneOnOneBotJumpUntilNanos = now + Self.ONE_ON_ONE_JUMP_MS * 1_000_000
            oneOnOneBotJumpHeightMultiplier = Self.ONE_ON_ONE_BOT_BLOCK_JUMP_MULTIPLIER
        }
        animateHorseShot(
            skill: skill,
            pullBackAtRelease: pullBackAtRelease,
            hot: false,
            oneOnOneFinish: finish
        ) { [weak self] result in
            guard let self = self else { return }
            postDelayed({ [weak self] in
                guard let self = self else { return }
                oneOnOneBotContestActive = false
                botPullBack = 0
                invalidate()
            }, 60)
            horseHumanStation = nil
            shotGuidesVisible = false
            oneOnOneSuppressShotGuideDrawing = false
            horseFreeMoveEnabled = true
            onEnd(result)
        }
    }

    // MARK: - Block lane, chase-down, block attempt, steals (Kotlin 3797-3991)

    /**
     * Used by the gesture-only defender control. During the opponent gather / very early flight a
     * double tap means BLOCK. Once the ball is clearly beyond the normal hand-contact window, the
     * same gesture becomes a pure rebound jump instead.
     */
    func oneOnOneHumanInBlockLane() -> Bool {
        if !oneOnOneEnabled || sharedHorseBallOwner != .BOT || width <= 0 || height <= 0 {
            return false
        }
        let hoop = sourcePointToView(sourceX: Self.SRC_HOOP_CENTER_X, sourceY: Self.SRC_HOOP_PLANE_Y)
        let shotDx = hoop.x - botX
        let shotDy = hoop.y - botFootY
        let shotLen = ksqrt(shotDx * shotDx + shotDy * shotDy).coerceAtLeast(1)
        let ux = shotDx / shotLen
        let uy = shotDy / shotLen
        let defDx = playerX - botX
        let defDy = playerFootY - botFootY
        let forward = defDx * ux + defDy * uy
        let lateral = abs(defDx * uy - defDy * ux)
        let maxForward = dp(v: 106 + 30 * (Float(oneOnOneHumanBlockRating) / 100))
        let maxLateral = dp(v: 36 + 18 * (Float(oneOnOneHumanBlockRating) / 100))
        return (forward >= -dp(v: 5) && forward <= maxForward) && lateral <= maxLateral
    }

    /**
     * A dunk can still be chased down from the side/behind. Ordinary jump-shots keep the tighter
     * lane test, but once Maya has committed to a dunk the defender only needs to get physically
     * close enough to the live finish to TRY a block. The actual result is still decided later by
     * the real raised-hand vs ball overlap, so this does not grant a magnetic chase-down block.
     */
    func oneOnOneHumanCanChaseDunkBlock() -> Bool {
        if !oneOnOneBotDunkActive || width <= 0 || height <= 0 { return false }

        let dx = botX - playerX
        let dy = (botFootY - playerFootY) * Self.ONE_ON_ONE_COLLISION_Y_SCALE
        let bodyDistance = ksqrt(dx * dx + dy * dy)

        // Give a defender who reacts quickly enough a real chase-down chance, but do not let a
        // player jump from the opposite side of the court and magically reach the dunking hand.
        let jumpRating01 = Float(oneOnOneHumanJumpRating.coerceIn(0, 100)) / 100
        let blockRating01 = Float(oneOnOneHumanBlockRating.coerceIn(0, 100)) / 100
        let maxDistance =
            dp(
                v: Self.ONE_ON_ONE_DUNK_CHASE_BLOCK_BASE_DISTANCE_DP +
                    Self.ONE_ON_ONE_DUNK_CHASE_BLOCK_JUMP_BONUS_DP * jumpRating01 +
                    Self.ONE_ON_ONE_DUNK_CHASE_BLOCK_RATING_BONUS_DP * blockRating01
            )
        return bodyDistance <= maxDistance
    }

    func oneOnOneHumanShouldAttemptBlock() -> Bool {
        if !oneOnOneEnabled ||
            sharedHorseBallOwner != .BOT ||
            oneOnOneLooseBallActive {
            return false
        }

        // Important for the "I thought I was beaten, sprinted back and got it" moment: during a
        // dunk, do not require the defender to already occupy the normal shot lane before the jump
        // input is accepted. They may close the distance while Maya is rising and then jump.
        if oneOnOneBotDunkActive { return oneOnOneHumanCanChaseDunkBlock() }

        if !oneOnOneHumanInBlockLane() { return false }

        if !botShotFrameRunning {
            return botPullBack >= Self.ONE_ON_ONE_DEFENSE_BLOCK_GATHER_PULL
        }

        let elapsed = botPhysicsState?.elapsedSeconds ?? 0
        return elapsed <= Self.ONE_ON_ONE_DEFENSE_BLOCK_EARLY_FLIGHT_SECONDS
    }

    /** Timed defensive jump/contest window. The actual block is a ball-vs-hand collision. */
    @discardableResult
    func oneOnOneHumanBlockAttempt() -> Bool {
        let validGeometry =
            oneOnOneBotDunkActive ? oneOnOneHumanCanChaseDunkBlock()
            : oneOnOneHumanInBlockLane()
        if !oneOnOneEnabled ||
            sharedHorseBallOwner != .BOT ||
            !validGeometry ||
            oneOnOneHumanBlockUntilNanos > ASystem.nanoTime() {
            return false
        }

        let now = ASystem.nanoTime()
        oneOnOneHumanBlockUntilNanos =
            now + Self.ONE_ON_ONE_HUMAN_BLOCK_WINDOW_MS * 1_000_000
        oneOnOneHumanJumpStartedAtNanos = now
        oneOnOneHumanJumpUntilNanos = now + Self.ONE_ON_ONE_JUMP_MS * 1_000_000
        oneOnOneHumanJumpHeightMultiplier = Self.ONE_ON_ONE_BLOCK_JUMP_MULTIPLIER
        invalidate()
        postDelayed({ [weak self] in self?.invalidate() }, Self.ONE_ON_ONE_HUMAN_BLOCK_WINDOW_MS + 20)
        return true
    }

    /**
     * 1v1 steal is movement-driven. If the human deliberately closes toward the live ball, Maya
     * automatically reaches once the hand is genuinely close enough. Moving away never triggers
     * a steal, so the gesture remains intuitive instead of becoming a hidden proximity lottery.
     *
     * Unused in Android too (no callers); kept for API parity.
     */
    func maybeStartOneOnOneHumanAutoSteal(moveDx: Float, moveDy: Float) {
        if !oneOnOneEnabled ||
            sharedHorseBallOwner != .BOT ||
            botShotFrameRunning ||
            oneOnOneLooseBallActive ||
            oneOnOneHumanStealResolvePosted {
            return
        }

        let now = ASystem.nanoTime()
        if now < oneOnOneHumanStealCooldownUntilNanos ||
            now < oneOnOneHumanStealUntilNanos {
            return
        }

        let liveBall = heldBotBallPosition()
        let toBallX = liveBall.x - playerX
        let toBallY = liveBall.y - (playerFootY - dp(v: 68))
        let moveLen = ksqrt(moveDx * moveDx + moveDy * moveDy)
        let ballLen = ksqrt(toBallX * toBallX + toBallY * toBallY)
        if moveLen < dp(v: 1.5) || ballLen < 1 { return }

        let towardBall = (moveDx * toBallX + moveDy * toBallY) / (moveLen * ballLen)
        if towardBall < Self.ONE_ON_ONE_AUTO_STEAL_MIN_TOWARD_DOT { return }

        let effectiveSteal =
            ((Float(oneOnOneHumanStealRating) * 0.80 + Float(oneOnOneHumanAgilityRating) * 0.20) -
                Float(oneOnOneBotBallHandlingRating - 50) * 0.34)
                .coerceIn(8, 100)
        let nearSide =
            oneOnOneBallOnDefenderSide(defenderX: playerX, handlerX: botX, ballX: liveBall.x)
        let sideScale: Float = nearSide ? 1 : 0.55
        let triggerReach = dp(v: (28 + 18 * (effectiveSteal / 100)) * sideScale)
        if ballLen > triggerReach { return }

        oneOnOneHumanStealAttempt()
    }

    /**
     * Starts a visible steal reach. The actual contact is resolved a moment later against the
     * live held-ball position; ratings only change reach, while the handler's Ball Handling
     * resists that reach. A touch knocks the ball loose instead of teleporting possession.
     */
    @discardableResult
    func oneOnOneHumanStealAttempt() -> Bool {
        if !oneOnOneEnabled ||
            sharedHorseBallOwner != .BOT ||
            botShotFrameRunning ||
            oneOnOneLooseBallActive ||
            oneOnOneHumanStealResolvePosted {
            return false
        }

        let now = ASystem.nanoTime()
        if now < oneOnOneHumanStealCooldownUntilNanos {
            return false
        }
        oneOnOneHumanStealCooldownUntilNanos =
            now + Self.ONE_ON_ONE_STEAL_COOLDOWN_MS * 1_000_000
        oneOnOneHumanStealStartedAtNanos = now
        oneOnOneHumanStealUntilNanos = now + Self.ONE_ON_ONE_STEAL_REACH_MS * 1_000_000
        oneOnOneHumanStealResolvePosted = true
        invalidate()

        postDelayed({ [weak self] in
            guard let self = self else { return }
            if !oneOnOneEnabled || !oneOnOneHumanStealResolvePosted { return }
            oneOnOneHumanStealResolvePosted = false
            if sharedHorseBallOwner != .BOT || oneOnOneLooseBallActive ||
                ASystem.nanoTime() < oneOnOneBotStealProtectedUntilNanos { return }

            let liveBall = heldBotBallPosition()
            let reachHand = oneOnOneHumanStealHandPoint()
            let effectiveSteal =
                ((Float(oneOnOneHumanStealRating) * 0.80 + Float(oneOnOneHumanAgilityRating) * 0.20) -
                    Float(oneOnOneBotBallHandlingRating - 50) * 0.34)
                    .coerceIn(8, 100)
            let nearSide =
                oneOnOneBallOnDefenderSide(defenderX: playerX, handlerX: botX, ballX: liveBall.x)
            let sideScale: Float = nearSide ? 1 : 0.64
            let reach = dp(v: (17 + 18 * (effectiveSteal / 100)) * sideScale)
            let dx = liveBall.x - reachHand.x
            let dy = liveBall.y - reachHand.y
            if dx * dx + dy * dy <= reach * reach {
                botMoveAnimator?.cancel()
                startOneOnOneStealDeflection(
                    liveBall: liveBall,
                    stealerHuman: true
                )
            }
            invalidate()
        }, Self.ONE_ON_ONE_STEAL_CONTACT_DELAY_MS)
        return true
    }

    // MARK: - Bot attack spot (dead), bot defensive positioning (Kotlin 3993-4104)

    /**
     * Bot drive target for the current possession. Human movement remains enabled while it runs.
     *
     * Unused in Android too (no callers); kept for API parity.
     */
    func moveOneOnOneBotToAttackSpot(
        seed: Int64,
        animate: Bool = true,
        onEnd: (() -> Void)? = nil
    ) {
        if !oneOnOneEnabled || sharedHorseBallOwner != .BOT {
            onEnd?()
            return
        }
        if width <= 0 || height <= 0 {
            post { [weak self] in self?.moveOneOnOneBotToAttackSpot(seed: seed, animate: animate, onEnd: onEnd) }
            return
        }

        let random = KotlinRandom(seed: seed ^ Self.ONE_ON_ONE_ATTACK_SEED_SALT)
        let candidates = [
            Station(id: "1V1_L", sourceX: 360, sourceY: 1120, distanceDifficulty: 0.52, zone: "one_on_one"),
            Station(id: "1V1_M", sourceX: 585, sourceY: 1135, distanceDifficulty: 0.40, zone: "one_on_one"),
            Station(id: "1V1_R", sourceX: 815, sourceY: 1090, distanceDifficulty: 0.58, zone: "one_on_one"),
            Station(id: "1V1_DEEP", sourceX: 475, sourceY: 1260, distanceDifficulty: 0.76, zone: "one_on_one")
        ]
        let station = candidates.kShuffled(random).first(where: { candidate in
            let p = sourcePointToView(sourceX: candidate.sourceX, sourceY: candidate.sourceY)
            let dx = p.x - playerX
            let dy = p.y - playerFootY
            return dx * dx + dy * dy >= dp(v: 72) * dp(v: 72)
        }) ?? candidates.kRandom(random)

        botCurrentStation = station
        botBallVisible = true
        let point = sourcePointToView(sourceX: station.sourceX, sourceY: station.sourceY)
        setBotPosition(x: point.x, y: point.y, animate: animate, onEnd: onEnd)
    }

    func updateOneOnOneBotDefensePosition(force: Bool) {
        if !oneOnOneEnabled ||
            sharedHorseBallOwner != .HUMAN ||
            botShotFrameRunning ||
            botMoveAnimator?.isRunning == true ||
            ASystem.nanoTime() < oneOnOneBotStealUntilNanos {
            return
        }

        let now = ASystem.nanoTime()
        if !force && (now < oneOnOneBotContestRecoveryUntilNanos || now < oneOnOneBotReactionLockedUntilNanos) {
            oneOnOneBotDefenseLastUpdateNanos = now
            return
        }

        let hoop = sourcePointToView(sourceX: Self.SRC_HOOP_CENTER_X, sourceY: Self.SRC_HOOP_DEPTH_FOOT_Y)
        let dx = hoop.x - playerX
        let dy = hoop.y - playerFootY
        let length = ksqrt(dx * dx + dy * dy).coerceAtLeast(1)
        let defense01 = Float(oneOnOneBotDefenseRating) / 100
        let agility01 = Float(oneOnOneBotAgilityRating) / 100
        let speed01 = Float(oneOnOneBotSpeedRating) / 100

        let idleAgeMs: Int64 =
            oneOnOneHumanLastMoveNanos == 0 ? 0
            : ((now - oneOnOneHumanLastMoveNanos) / 1_000_000).coerceAtLeast(0)
        let idlePressure01 =
            (Float(idleAgeMs - Self.ONE_ON_ONE_IDLE_DEFENSE_WAIT_MS) /
                Float(Self.ONE_ON_ONE_IDLE_DEFENSE_CLOSE_MS)).coerceIn(0, 1)

        // Standing still invites pressure. Close the gap gradually and shade toward the hand that
        // actually owns the live ball, rather than waiting for another MOVE event.
        let spacingDp =
            (82 - defense01 * 17 - idlePressure01 * Self.ONE_ON_ONE_IDLE_DEFENSE_EXTRA_CLOSE_DP)
                .coerceAtLeast(39)
        let spacing = dp(v: spacingDp)
        let liveBall = heldBallPosition()
        let ballSideBiasX = (liveBall.x - playerX) * (0.30 * idlePressure01)
        let targetX = playerX + dx / length * spacing + ballSideBiasX
        let targetY = playerFootY + dy / length * spacing * 0.78

        let previous = oneOnOneBotDefenseLastUpdateNanos
        let dt: Float = previous == 0 ? Float(1) / Float(60)
            : ((now &- previous).toFloat() / Float(1_000_000_000)).coerceIn(0, 0.06)
        oneOnOneBotDefenseLastUpdateNanos = now
        let bounded = limitedGroundMove(x: botX, y: botFootY, tx: targetX, ty: targetY,
                                        limit: (Float(2.3) + speed01 * Float(2.2) + agility01 * Float(0.7)) * dt)
        botX = bounded.x; botFootY = bounded.y
        botX = botX.coerceIn(horseFreeMinX(), horseFreeMaxX())
        botFootY = clampHorseFreeY(x: botX, y: botFootY)
        botDribbleBouncePx = 0
        invalidate()
    }

    // MARK: - Bodies, collisions, box-out (Kotlin 4106-4326)

    func oneOnOneBodyRadiusDp(human: Bool) -> Float {
        let height = human ? oneOnOneHumanHeightRating : oneOnOneBotHeightRating
        let strength = human ? oneOnOneHumanStrengthRating : oneOnOneBotStrengthRating
        let weight = human ? oneOnOneHumanWeightRating : oneOnOneBotWeightRating
        let size01 = (Float(height) * 0.46 + Float(strength) * 0.20 + Float(weight) * 0.34) / 100
        return Float(22.0) + size01.coerceIn(0, 1) * 8.5
    }

    /**
     * 1v1 body contact is asymmetric on purpose: the defender has an anchoring advantage, so
     * repeatedly dragging straight through a same-strength defender does not bulldoze them to
     * the rim. Strength/height can still move a smaller defender a little, while a quick smaller
     * player pays for that lack of mass with much better movement elsewhere.
     */
    func resolveHumanBotBodyCollision() {
        if !oneOnOneEnabled || !botEnabled { return }
        let dx = playerX - botX
        let dyScaled = (playerFootY - botFootY) * Self.ONE_ON_ONE_COLLISION_Y_SCALE
        let crossoverScale: Float =
            ASystem.nanoTime() < oneOnOneHumanCrossoverUntilNanos
                ? Self.ONE_ON_ONE_CROSSOVER_COLLISION_SCALE
                : 1
        let minDistance =
            dp(v: (oneOnOneBodyRadiusDp(human: true) + oneOnOneBodyRadiusDp(human: false)) * crossoverScale)
        let distSq = dx * dx + dyScaled * dyScaled
        if distSq >= minDistance * minDistance { return }

        let dist = ksqrt(distSq).coerceAtLeast(0.01)
        let nx: Float = dist > 0.02 ? dx / dist : -1
        let nyScaled: Float = dist > 0.02 ? dyScaled / dist : 0
        let overlap = (minDistance - dist).coerceAtLeast(0)

        let attackerPower =
            Float(oneOnOneHumanStrengthRating) * 0.48 +
                Float(oneOnOneHumanWeightRating) * 0.30 +
                Float(oneOnOneHumanSpeedRating) * 0.10 +
                Float(oneOnOneHumanHeightRating) * 0.12
        let defenderPower =
            Float(oneOnOneBotStrengthRating) * 0.36 +
                Float(oneOnOneBotWeightRating) * 0.28 +
                Float(oneOnOneBotDefenseRating) * 0.22 +
                Float(oneOnOneBotHeightRating) * 0.14 +
                Self.ONE_ON_ONE_DEFENDER_ANCHOR_BONUS
        let advantage = ((attackerPower - defenderPower) / 100).coerceIn(-0.75, 0.75)
        let defenderMoveShare =
            (Self.ONE_ON_ONE_BASE_DEFENDER_DISPLACEMENT_SHARE + advantage * 0.22)
                .coerceIn(0.035, 0.34)
        let attackerCorrectionShare = 1 - defenderMoveShare

        // Move both bodies away from the overlap instead of teleporting the defender. With equal
        // Maya ratings the defender gives only a small amount and the attacker has to go around.
        playerX += nx * overlap * attackerCorrectionShare
        playerFootY +=
            (nyScaled * overlap * attackerCorrectionShare) / Self.ONE_ON_ONE_COLLISION_Y_SCALE
        botX -= nx * overlap * defenderMoveShare
        botFootY -=
            (nyScaled * overlap * defenderMoveShare) / Self.ONE_ON_ONE_COLLISION_Y_SCALE

        clampHumanToHorseFreeBounds()
        botX = botX.coerceIn(horseFreeMinX(), horseFreeMaxX())
        botFootY = clampHorseFreeY(x: botX, y: botFootY)
    }

    /** Same contact rule with BOT as the attacker and the human as the planted defender. */
    func resolveBotHumanBodyCollision() {
        if !oneOnOneEnabled || !botEnabled { return }
        let dx = botX - playerX
        let dyScaled = (botFootY - playerFootY) * Self.ONE_ON_ONE_COLLISION_Y_SCALE
        let minDistance = dp(v: oneOnOneBodyRadiusDp(human: true) + oneOnOneBodyRadiusDp(human: false))
        let distSq = dx * dx + dyScaled * dyScaled
        if distSq >= minDistance * minDistance { return }

        let dist = ksqrt(distSq).coerceAtLeast(0.01)
        let nx: Float = dist > 0.02 ? dx / dist : 1
        let nyScaled: Float = dist > 0.02 ? dyScaled / dist : 0
        let overlap = (minDistance - dist).coerceAtLeast(0)

        let attackerPower =
            Float(oneOnOneBotStrengthRating) * 0.48 +
                Float(oneOnOneBotWeightRating) * 0.30 +
                Float(oneOnOneBotSpeedRating) * 0.10 +
                Float(oneOnOneBotHeightRating) * 0.12
        let defenderPower =
            Float(oneOnOneHumanStrengthRating) * 0.36 +
                Float(oneOnOneHumanWeightRating) * 0.28 +
                Float(oneOnOneHumanDefenseRating) * 0.22 +
                Float(oneOnOneHumanHeightRating) * 0.14 +
                Self.ONE_ON_ONE_DEFENDER_ANCHOR_BONUS
        let advantage = ((attackerPower - defenderPower) / 100).coerceIn(-0.75, 0.75)
        let defenderMoveShare =
            (Self.ONE_ON_ONE_BASE_DEFENDER_DISPLACEMENT_SHARE + advantage * 0.22)
                .coerceIn(0.035, 0.34)
        let attackerCorrectionShare = 1 - defenderMoveShare

        botX += nx * overlap * attackerCorrectionShare
        botFootY +=
            (nyScaled * overlap * attackerCorrectionShare) / Self.ONE_ON_ONE_COLLISION_Y_SCALE
        playerX -= nx * overlap * defenderMoveShare
        playerFootY -=
            (nyScaled * overlap * defenderMoveShare) / Self.ONE_ON_ONE_COLLISION_Y_SCALE

        botX = botX.coerceIn(horseFreeMinX(), horseFreeMaxX())
        botFootY = clampHorseFreeY(x: botX, y: botFootY)
        clampHumanToHorseFreeBounds()
    }

    /**
     * Returns true when the human has established inside rebounding position, false when the bot
     * has it, and null when neither player is meaningfully boxing the other out. The important
     * nuance is spatial, not button-based: simply staying between the opponent and the basket can
     * make the next rebound harder for them.
     */
    func oneOnOneBoxOutOwner() -> Bool? {
        if !oneOnOneEnabled || !oneOnOneLooseBallActive || width <= 0 || height <= 0 { return nil }
        let hoop = sourcePointToView(sourceX: Self.SRC_HOOP_CENTER_X, sourceY: Self.SRC_HOOP_DEPTH_FOOT_Y)

        func blocks(
            blockerX: Float,
            blockerY: Float,
            blockerWeight: Int,
            runnerX: Float,
            runnerY: Float
        ) -> Bool {
            let vx = hoop.x - runnerX
            let vy = hoop.y - runnerY
            let lenSq = vx * vx + vy * vy
            if lenSq < 1 { return false }
            let wx = blockerX - runnerX
            let wy = blockerY - runnerY
            let t = ((wx * vx + wy * vy) / lenSq).coerceIn(-1, 2)
            if !(t >= 0.08 && t <= 0.88) { return false }
            let closestX = runnerX + vx * t
            let closestY = runnerY + vy * t
            let lateral = ksqrt(
                (blockerX - closestX) * (blockerX - closestX) +
                    (blockerY - closestY) * (blockerY - closestY)
            )
            let bodyDistance = ksqrt(wx * wx + wy * wy)
            let corridor = dp(v: 32 + Float(blockerWeight) * 0.10)
            return lateral <= corridor && bodyDistance <= dp(v: 118)
        }

        let humanBlocks = blocks(
            blockerX: playerX,
            blockerY: playerFootY,
            blockerWeight: oneOnOneHumanWeightRating,
            runnerX: botX,
            runnerY: botFootY
        )
        let botBlocks = blocks(
            blockerX: botX,
            blockerY: botFootY,
            blockerWeight: oneOnOneBotWeightRating,
            runnerX: playerX,
            runnerY: playerFootY
        )
        if humanBlocks && !botBlocks { return true }
        if botBlocks && !humanBlocks { return false }
        return nil
    }

    /** Loose-ball contact becomes asymmetric when somebody has earned inside box-out position. */
    func resolveNeutralHumanBotBodyCollision() {
        if !oneOnOneEnabled || !botEnabled { return }
        let dx = playerX - botX
        let dyScaled = (playerFootY - botFootY) * Self.ONE_ON_ONE_COLLISION_Y_SCALE
        let minDistance =
            dp(v: (oneOnOneBodyRadiusDp(human: true) + oneOnOneBodyRadiusDp(human: false)) * 0.90)
        let distSq = dx * dx + dyScaled * dyScaled
        if distSq >= minDistance * minDistance { return }
        let dist = ksqrt(distSq).coerceAtLeast(0.01)
        let nx: Float = dist > 0.02 ? dx / dist : -1
        let ny: Float = dist > 0.02 ? dyScaled / dist : 0
        let overlap = (minDistance - dist).coerceAtLeast(0)

        let boxOutOwner = oneOnOneBoxOutOwner()
        let humanBoxPower =
            Float(oneOnOneHumanWeightRating) * 0.44 +
                Float(oneOnOneHumanStrengthRating) * 0.31 +
                Float(oneOnOneHumanDefenseRating) * 0.25
        let botBoxPower =
            Float(oneOnOneBotWeightRating) * 0.44 +
                Float(oneOnOneBotStrengthRating) * 0.31 +
                Float(oneOnOneBotDefenseRating) * 0.25
        let powerEdge = ((humanBoxPower - botBoxPower) / 100).coerceIn(-0.65, 0.65)
        let humanMoveShare: Float
        switch boxOutOwner {
        case .some(true):
            humanMoveShare = (0.22 - powerEdge * 0.10).coerceIn(0.10, 0.30)
        case .some(false):
            humanMoveShare = (0.78 - powerEdge * 0.10).coerceIn(0.70, 0.90)
        case .none:
            humanMoveShare = 0.50
        }
        let botMoveShare = 1 - humanMoveShare

        playerX += nx * overlap * humanMoveShare
        playerFootY += (ny * overlap * humanMoveShare) / Self.ONE_ON_ONE_COLLISION_Y_SCALE
        botX -= nx * overlap * botMoveShare
        botFootY -= (ny * overlap * botMoveShare) / Self.ONE_ON_ONE_COLLISION_Y_SCALE
        clampHumanToHorseFreeBounds()
        botX = botX.coerceIn(horseFreeMinX(), horseFreeMaxX())
        botFootY = clampHorseFreeY(x: botX, y: botFootY)
    }

    /**
     * A steal is much easier when the live dribble is on the defender-facing side of the handler.
     * Cross-body steals remain possible only at very close range; there is no invisible RNG miss.
     */
    func oneOnOneBallOnDefenderSide(
        defenderX: Float,
        handlerX: Float,
        ballX: Float
    ) -> Bool {
        let defenderDelta = defenderX - handlerX
        let ballDelta = ballX - handlerX
        if abs(defenderDelta) < dp(v: 2) || abs(ballDelta) < dp(v: 4) { return true }
        return (defenderDelta < 0 && ballDelta < 0) ||
            (defenderDelta > 0 && ballDelta > 0)
    }

    // MARK: - Steal deflection, bot steal (Kotlin 4328-4453)

    /**
     * Steals should usually create a short scramble, not a missile to the sideline.
     * About two thirds of contacts stay weak and biased toward the stealer; the rest can pop
     * farther, but are still capped to playable 1v1 distances.
     */
    func startOneOnOneStealDeflection(
        liveBall: APointF,
        stealerHuman: Bool
    ) {
        oneOnOneLooseEventSerial &+= 1
        let stealerX = stealerHuman ? playerX : botX
        let stealerY = stealerHuman ? playerFootY : botFootY
        // Kotlin Long arithmetic (wrapping): serial * 1103515245L + x.toBits().toLong() * 31L + y.toBits().toLong()
        let seedBits: Int64 =
            oneOnOneLooseEventSerial &* 1103515245 &+
                Int64(liveBall.x.toBits()) &* 31 &+
                Int64(liveBall.y.toBits())
        let random = KotlinRandom(seed: seedBits.toInt())

        let toStealerX = stealerX - liveBall.x
        let toStealerY = (stealerY - dp(v: 20)) - liveBall.y
        let len = ksqrt(toStealerX * toStealerX + toStealerY * toStealerY)
            .coerceAtLeast(1)
        let ux = toStealerX / len
        let uy = toStealerY / len
        let side: Float = random.nextBoolean() ? 1 : -1
        let bucket = random.nextFloat()

        let speedDp: Float
        if bucket < 0.34 {
            speedDp = 58 + random.nextFloat() * 22
        } else if bucket < 0.68 {
            speedDp = 64 + random.nextFloat() * 24
        } else if bucket < 0.83 {
            speedDp = 108 + random.nextFloat() * 34
        } else {
            speedDp = 88 + random.nextFloat() * 42
        }
        let towardWeight: Float = bucket < 0.68 ? 0.86 : (bucket < 0.83 ? 0.58 : 0.32)
        let lateralWeight = (1 - towardWeight) * side
        let vx =
            dp(v: speedDp) * (ux * towardWeight + (-uy) * lateralWeight)
        let vy =
            dp(v: speedDp) * (uy * towardWeight + ux * lateralWeight) * 0.34 +
                dp(v: 30 + random.nextFloat() * 28)

        startOneOnOneLooseBall(
            x: liveBall.x,
            y: liveBall.y,
            vx: vx.coerceIn(-dp(v: 155), dp(v: 155)),
            vy: vy.coerceIn(-dp(v: 70), dp(v: 165)),
            claimDelaySeconds: Self.ONE_ON_ONE_STEAL_LOOSE_CLAIM_DELAY_SECONDS
        )
    }

    func maybeStartOneOnOneBotSteal() {
        if !oneOnOneEnabled ||
            sharedHorseBallOwner != .HUMAN ||
            shotGuidesVisible ||
            oneOnOneLooseBallActive ||
            ASystem.nanoTime() < oneOnOneHumanStealProtectedUntilNanos {
            return
        }

        let now = ASystem.nanoTime()
        if now < oneOnOneBotStealCooldownUntilNanos ||
            now < oneOnOneBotReactionLockedUntilNanos ||
            now < oneOnOneBotStealUntilNanos {
            return
        }

        let ball = heldBallPosition()
        let direction: Float = playerX >= botX ? 1 : -1
        let handX = botX + dp(v: 22) * direction
        let handY = botFootY - dp(v: 72)
        let effectiveSteal =
            ((Float(oneOnOneBotStealRating) * 0.80 + Float(oneOnOneBotAgilityRating) * 0.20) -
                Float(oneOnOneHumanBallHandlingRating - 50) * 0.34)
                .coerceIn(8, 100)
        let nearSide =
            oneOnOneBallOnDefenderSide(defenderX: botX, handlerX: playerX, ballX: ball.x)
        // Threat range is intentionally wider than contact range: Maya should visibly TRY
        // to steal when the dribble is exposed, while actual possession changes still require
        // the animated hand to meet the live ball a moment later.
        let sideScale: Float = nearSide ? 1 : 0.68
        let idleAgeMs: Int64 =
            oneOnOneHumanLastMoveNanos == 0 ? 0
            : ((now - oneOnOneHumanLastMoveNanos) / 1_000_000).coerceAtLeast(0)
        let idleReachBonusDp =
            ((Float(idleAgeMs - 650) / 900).coerceIn(0, 1)) * 18
        // Standing still does not grant immunity. After Maya has had time to read the dribble,
        // widen only the ATTEMPT envelope so she visibly reaches again about once per cooldown.
        // The later hand-vs-ball contact test is unchanged, so failed reaches remain failed.
        let triggerReach =
            dp(v: (34 + 20 * (effectiveSteal / 100)) * sideScale + idleReachBonusDp)
        let dx = ball.x - handX
        let dy = ball.y - handY
        if dx * dx + dy * dy > triggerReach * triggerReach { return }

        oneOnOneBotStealStartedAtNanos = now
        oneOnOneBotStealUntilNanos = now + Self.ONE_ON_ONE_STEAL_REACH_MS * 1_000_000
        oneOnOneBotStealResolvePosted = true
        oneOnOneBotStealCooldownUntilNanos = now + Self.ONE_ON_ONE_STEAL_COOLDOWN_MS * 1_000_000
        invalidate()

        postDelayed({ [weak self] in
            guard let self = self else { return }
            if !oneOnOneEnabled || !oneOnOneBotStealResolvePosted { return }
            oneOnOneBotStealResolvePosted = false
            if sharedHorseBallOwner != .HUMAN || oneOnOneLooseBallActive { return }

            let liveBall = heldBallPosition()
            let reachHand = oneOnOneBotStealHandPoint()
            let effectiveSteal =
                ((Float(oneOnOneBotStealRating) * 0.80 + Float(oneOnOneBotAgilityRating) * 0.20) -
                    Float(oneOnOneHumanBallHandlingRating - 50) * 0.34)
                    .coerceIn(8, 100)
            let nearSide =
                oneOnOneBallOnDefenderSide(defenderX: botX, handlerX: playerX, ballX: liveBall.x)
            let sideScale: Float = nearSide ? 1 : 0.62
            let reach = dp(v: (16 + 18 * (effectiveSteal / 100)) * sideScale)
            let rdx = liveBall.x - reachHand.x
            let rdy = liveBall.y - reachHand.y
            if rdx * rdx + rdy * rdy <= reach * reach {
                playerMoveAnimator?.cancel()
                startOneOnOneStealDeflection(
                    liveBall: liveBall,
                    stealerHuman: false
                )
            }
            invalidate()
        }, Self.ONE_ON_ONE_STEAL_CONTACT_DELAY_MS)
    }

    // MARK: - Loose ball start/stop/claim/dead, rebounds, bot chase (Kotlin 4455-4676)

    func startOneOnOneLooseBall(
        x: Float,
        y: Float,
        vx: Float,
        vy: Float,
        claimDelaySeconds: Float = TripleShotCourtView.ONE_ON_ONE_REBOUND_CLAIM_MIN_AGE_SECONDS,
        gravityPxPerSec2: Float? = nil,
        worldStart: CourtPoint? = nil,
        worldVelocity: CourtPoint? = nil
    ) {
        if !oneOnOneEnabled { return }
        removeCallbacks(oneOnOneLooseBallFrameRunnable)
        cancelHumanIdleDribble()
        botMoveAnimator?.cancel()
        switch sharedHorseBallOwner {
        case .some(.HUMAN):
            oneOnOneLooseBallLastOwnerHuman = true
        case .some(.BOT):
            oneOnOneLooseBallLastOwnerHuman = false
        case .none:
            break // keeps oneOnOneLooseBallLastOwnerHuman
        }
        let ownerWasBot = sharedHorseBallOwner == .BOT
        let t = backgroundTransform()
        let start = worldStart ?? (ownerWasBot ? botShotPresentation.held : humanShotPresentation.held)
        worldLooseBall = TripleShotLooseBall(
            start: start,
            velocity: worldVelocity ?? CourtPoint(x: vx / t.scaleX * Float(0.014), y: Float(-1.4), z: vy / t.scaleY * Float(0.017)),
            gravity: Float(9.8), centerX: worldHoop().x, back: worldHoop().z - Float(2.4))
        sharedHorseBallOwner = nil
        ballVisible = true
        botBallVisible = false
        oneOnOneLooseBallActive = true

        // Preserve the physical direction that came from the rim/backboard/hand. Do not bend it
        // toward screen centre and do not clamp the starting point to the phone rectangle.
        oneOnOneLooseBallVx = vx
        oneOnOneLooseBallVy = vy
        if let gravity = gravityPxPerSec2, gravity > 0 {
            oneOnOneLooseBallGravityPxPerSec2 = gravity
        } else {
            oneOnOneLooseBallGravityPxPerSec2 = Float(height) * 1.52
        }
        oneOnOneLooseBallLastFrameNanos = 0
        oneOnOneLooseBallAgeSeconds = 0
        oneOnOneLooseBallClaimDelaySeconds = claimDelaySeconds.coerceAtLeast(0)
        ballX = x
        ballY = y
        oneOnOneAutomaticBallStateListener?(.LOOSE)
        postOnAnimation(oneOnOneLooseBallFrameRunnable)
        invalidate()
    }

    func stopOneOnOneLooseBall() {
        removeCallbacks(oneOnOneLooseBallFrameRunnable)
        oneOnOneLooseBallActive = false
        worldLooseBall = nil
        oneOnOneLooseBallVx = 0
        oneOnOneLooseBallVy = 0
        oneOnOneLooseBallGravityPxPerSec2 = 0
        oneOnOneLooseBallLastFrameNanos = 0
        oneOnOneLooseBallAgeSeconds = 0
        oneOnOneLooseBallClaimDelaySeconds = Self.ONE_ON_ONE_REBOUND_CLAIM_MIN_AGE_SECONDS
    }

    func claimOneOnOneLooseBall(human: Bool) {
        if !oneOnOneEnabled || !oneOnOneLooseBallActive { return }
        stopOneOnOneLooseBall()
        let now = ASystem.nanoTime()
        if human {
            giveSharedHorseBallToHuman()
            oneOnOneHumanStealProtectedUntilNanos =
                now + Self.ONE_ON_ONE_STEAL_AFTER_PICKUP_PROTECTION_MS * 1_000_000
            oneOnOneHumanLastMoveNanos = now
            updateOneOnOneBotDefensePosition(force: true)

            // oneOnOneGiveBallToBot() removes the defensive heartbeat. When the human later
            // recovered a rebound/loose ball, this path changed ownership back to HUMAN but never
            // restarted that heartbeat. That is why Maya sometimes kept reaching normally and,
            // after a different rebound sequence, could stand in front of an idle dribbler forever.
            removeCallbacks(oneOnOneDefenseHeartbeatRunnable)
            postDelayed(oneOnOneDefenseHeartbeatRunnable, Self.ONE_ON_ONE_DEFENSE_HEARTBEAT_MS)

            oneOnOneAutomaticBallStateListener?(.HUMAN)
        } else {
            giveSharedHorseBallToBot()
            oneOnOneBotStealProtectedUntilNanos =
                now + Self.ONE_ON_ONE_STEAL_AFTER_PICKUP_PROTECTION_MS * 1_000_000
            oneOnOneAutomaticBallStateListener?(.BOT)
        }
    }

    /**
     * A ball that genuinely leaves the side of the court becomes dead instead of bouncing off an
     * invisible wall. For the current alpha the next possession goes to the team that did not own
     * the ball before it became loose; the Fragment then performs a normal check-ball reset.
     */
    func resolveOneOnOneDeadBall() {
        if !oneOnOneEnabled || !oneOnOneLooseBallActive { return }
        let previousHuman = oneOnOneLooseBallLastOwnerHuman
        stopOneOnOneLooseBall()
        sharedHorseBallOwner = nil
        ballVisible = false
        botBallVisible = false
        switch previousHuman {
        case .some(true):
            oneOnOneAutomaticBallStateListener?(.DEAD_BOT)
        case .some(false):
            oneOnOneAutomaticBallStateListener?(.DEAD_HUMAN)
        case .none:
            oneOnOneAutomaticBallStateListener?(.DEAD_HUMAN)
        }
        invalidate()
    }

    /** Kotlin `private data class OneOnOneReboundCandidate(val human: Boolean, val score: Float)`. */
    struct OneOnOneReboundCandidate: Hashable {
        var human: Bool
        var score: Float
    }

    /**
     * Resolves a live rebound from geometry, not from a dedicated REBOUND button or an RNG roll.
     * A low ball can be scooped by getting the feet close enough. A ball above shoulder height
     * requires an active jump and is tested against the raised hand. If both can reach on the same
     * frame, the lower normalised distance wins, with a small advantage for the higher jump.
     */
    func resolveOneOnOneLooseBallPossession(now: Int64) {
        if !oneOnOneLooseBallActive { return }
        if oneOnOneLooseBallAgeSeconds < oneOnOneLooseBallClaimDelaySeconds { return }

        let human = oneOnOneReboundCandidate(human: true, now: now)
        let bot = oneOnOneReboundCandidate(human: false, now: now)

        let winner: OneOnOneReboundCandidate?
        if human == nil && bot == nil {
            winner = nil
        } else if human != nil && bot == nil {
            winner = human
        } else if human == nil && bot != nil {
            winner = bot
        } else {
            winner = human!.score <= bot!.score ? human : bot
        }

        if let winner = winner {
            claimOneOnOneLooseBall(human: winner.human)
            return
        }

        // No timer-based teleport. If nobody reaches a stopped ball it simply stays on the floor
        // until somebody gets there; if it leaves the sideline, resolveOneOnOneDeadBall() resets
        // the next possession from a normal check position.
    }

    func oneOnOneReboundCandidate(
        human: Bool,
        now: Int64
    ) -> OneOnOneReboundCandidate? {
        guard let ball = worldLooseBall?.position else { return nil }
        let foot = worldGround(x: human ? playerX : botX, y: human ? playerFootY : botFootY)
        let horizontal = khypot(ball.x - foot.x, ball.z - foot.z)
        let jumping = now < (human ? oneOnOneHumanJumpUntilNanos : oneOnOneBotJumpUntilNanos)
        let jump = (human ? oneOnOneHumanJumpOffsetPx(now: now) : oneOnOneBotJumpOffsetPx(now: now)) / density * Float(0.012)
        let reachHeight: Float = jumping ? Float(2.1) + jump : Float(1.45)
        if ball.y > reachHeight || horizontal > 0.85 { return nil }
        if oneOnOneLooseBallAgeSeconds < Self.ONE_ON_ONE_GROUND_PICKUP_MIN_AGE_SECONDS { return nil }
        return OneOnOneReboundCandidate(human: human, score: horizontal / Float(0.85) - (jumping ? Float(0.04) : Float(0)))
    }

    func updateOneOnOneBotLooseBallChase(dt: Float, now: Int64) {
        if !oneOnOneLooseBallActive || !botEnabled { return }
        let reactionSeconds =
            (Float(0.38) - (Float(oneOnOneBotAgilityRating) / 100) * 0.15).coerceIn(0.22, 0.38)
        if oneOnOneLooseBallAgeSeconds < reactionSeconds { return }

        guard let worldBall = worldLooseBall?.position else { return }
        let logical = logicalGround(p: worldBall)
        let targetFootX = logical.x
        let targetFootY = logical.y

        let dx = targetFootX - botX
        let dy = targetFootY - botFootY
        let dist = ksqrt(dx * dx + dy * dy).coerceAtLeast(1)
        let bounded = limitedGroundMove(x: botX, y: botFootY, tx: targetFootX, ty: targetFootY,
                                        limit: (Float(3.2) + oneOnOneBotSpeedRating.toFloat() * Float(0.018)) * dt)
        botX = bounded.x; botFootY = bounded.y
        botX = botX.coerceIn(horseFreeMinX(), horseFreeMaxX())
        botFootY = clampHorseFreeY(x: botX, y: botFootY)
        resolveNeutralHumanBotBodyCollision()

        let ballAboveHand = worldBall.y > 1.45
        let jumpTrigger = dp(v: 70 + Float(oneOnOneBotHeightRating) * 0.16)
        if ballAboveHand && dist < jumpTrigger && now >= oneOnOneBotJumpUntilNanos {
            oneOnOneBotJumpStartedAtNanos = now
            oneOnOneBotJumpUntilNanos = now + Self.ONE_ON_ONE_JUMP_MS * 1_000_000
            oneOnOneBotJumpHeightMultiplier = Self.ONE_ON_ONE_REBOUND_JUMP_MULTIPLIER
        }
    }

    // MARK: - Steal hands, lunges, jump offsets, bot contest, block hands (Kotlin 4678-4809)

    func oneOnOneBotStealHandPoint() -> APointF {
        let now = ASystem.nanoTime()
        let total = (oneOnOneBotStealUntilNanos - oneOnOneBotStealStartedAtNanos).coerceAtLeast(1)
        let elapsed = (now - oneOnOneBotStealStartedAtNanos).coerceAtLeast(0)
        let t = (Float(elapsed) / Float(total)).coerceIn(0, 1)
        let reachT = Float(sin(Double(t) * Double.pi)).coerceAtLeast(0)
        let ball = heldBallPosition()
        let baseDirection: Float = playerX >= botX ? 1 : -1
        return APointF(
            botX + dp(v: 20) * baseDirection + (ball.x - botX) * 0.30 * reachT,
            botFootY - dp(v: 72) + (ball.y - (botFootY - dp(v: 72))) * 0.40 * reachT
        )
    }

    func oneOnOneHumanStealHandPoint() -> APointF {
        let now = ASystem.nanoTime()
        let total = (oneOnOneHumanStealUntilNanos - oneOnOneHumanStealStartedAtNanos).coerceAtLeast(1)
        let elapsed = (now - oneOnOneHumanStealStartedAtNanos).coerceAtLeast(0)
        let t = (Float(elapsed) / Float(total)).coerceIn(0, 1)
        let reachT = Float(sin(Double(t) * Double.pi)).coerceAtLeast(0)
        let ball = heldBotBallPosition()
        let baseDirection: Float = botX >= playerX ? 1 : -1
        return APointF(
            playerX + dp(v: 20) * baseDirection + (ball.x - playerX) * 0.36 * reachT,
            playerFootY - dp(v: 72) + (ball.y - (playerFootY - dp(v: 72))) * 0.43 * reachT
        )
    }

    func oneOnOneHumanStealVisualOffset() -> APointF {
        let now = ASystem.nanoTime()
        if now >= oneOnOneHumanStealUntilNanos || oneOnOneHumanStealStartedAtNanos <= 0 {
            return APointF(0, 0)
        }
        // Re-entrancy guard, see court2StealLungeDepth (never triggers in a state Android can reach).
        if court2StealLungeDepth > 0 { return APointF(0, 0) }
        court2StealLungeDepth += 1
        defer { court2StealLungeDepth -= 1 }
        let total = (oneOnOneHumanStealUntilNanos - oneOnOneHumanStealStartedAtNanos).coerceAtLeast(1)
        let p = (Float(now - oneOnOneHumanStealStartedAtNanos) / Float(total)).coerceIn(0, 1)
        let reachT = Float(sin(Double(p) * Double.pi)).coerceAtLeast(0)
        let ball = heldBotBallPosition()
        return APointF(
            (ball.x - playerX) * 0.13 * reachT,
            (ball.y - (playerFootY - dp(v: 72))) * 0.05 * reachT
        )
    }

    func oneOnOneHumanJumpOffsetPx(now: Int64 = ASystem.nanoTime()) -> Float {
        return oneOnOneJumpOffsetPx(now: now, started: oneOnOneHumanJumpStartedAtNanos, until: oneOnOneHumanJumpUntilNanos) *
            oneOnOneHumanJumpHeightMultiplier * oneOnOneJumpRatingScale(rating: oneOnOneHumanJumpRating)
    }

    func oneOnOneBotJumpOffsetPx(now: Int64 = ASystem.nanoTime()) -> Float {
        return oneOnOneJumpOffsetPx(now: now, started: oneOnOneBotJumpStartedAtNanos, until: oneOnOneBotJumpUntilNanos) *
            oneOnOneBotJumpHeightMultiplier * oneOnOneJumpRatingScale(rating: oneOnOneBotJumpRating)
    }

    /** 50 = neutral. Jump is real reach/vertical, not just animation scale. */
    func oneOnOneJumpRatingScale(rating: Int) -> Float {
        let delta = Float(rating.coerceIn(0, 100) - 50) / 50
        return delta >= 0 ? 1 + delta * 0.30 : 1 + delta * 0.22
    }

    func oneOnOneJumpOffsetPx(now: Int64, started: Int64, until: Int64) -> Float {
        if started <= 0 || until <= started || now >= until { return 0 }
        let p = (Float(now - started) / Float(until - started)).coerceIn(0, 1)
        return Float(sin(Double(p) * Double.pi)).coerceAtLeast(0) * dp(v: Self.ONE_ON_ONE_JUMP_HEIGHT_DP)
    }

    func oneOnOneBotStealVisualOffset() -> APointF {
        let now = ASystem.nanoTime()
        if now >= oneOnOneBotStealUntilNanos || oneOnOneBotStealStartedAtNanos <= 0 {
            return APointF(0, 0)
        }
        // Re-entrancy guard, see court2StealLungeDepth (never triggers in a state Android can reach).
        if court2StealLungeDepth > 0 { return APointF(0, 0) }
        court2StealLungeDepth += 1
        defer { court2StealLungeDepth -= 1 }
        let total = (oneOnOneBotStealUntilNanos - oneOnOneBotStealStartedAtNanos).coerceAtLeast(1)
        let p = (Float(now - oneOnOneBotStealStartedAtNanos) / Float(total)).coerceIn(0, 1)
        let reachT = Float(sin(Double(p) * Double.pi)).coerceAtLeast(0)
        let ball = heldBallPosition()
        return APointF(
            (ball.x - botX) * 0.13 * reachT,
            (ball.y - (botFootY - dp(v: 72))) * 0.05 * reachT
        )
    }

    func maybeStartOneOnOneBotContest() {
        if !oneOnOneEnabled ||
            sharedHorseBallOwner != .HUMAN ||
            !oneOnOneBotContestAllowed ||
            oneOnOneBotContestActive ||
            ASystem.nanoTime() < oneOnOneBotContestRecoveryUntilNanos ||
            ASystem.nanoTime() < oneOnOneBotReactionLockedUntilNanos {
            return
        }

        let hoop = sourcePointToView(sourceX: Self.SRC_HOOP_CENTER_X, sourceY: Self.SRC_HOOP_PLANE_Y)
        let shotDx = hoop.x - playerX
        let shotDy = hoop.y - playerFootY
        let shotLen = ksqrt(shotDx * shotDx + shotDy * shotDy).coerceAtLeast(1)
        let ux = shotDx / shotLen
        let uy = shotDy / shotLen
        let defDx = botX - playerX
        let defDy = botFootY - playerFootY
        let forward = defDx * ux + defDy * uy
        let lateral = abs(defDx * uy - defDy * ux)
        let maxForward = dp(v: 116 + 34 * (Float(oneOnOneBotBlockRating) / 100))
        let maxLateral = dp(v: 43 + 22 * (Float(oneOnOneBotBlockRating) / 100))

        if (forward >= 0 && forward <= maxForward) && lateral <= maxLateral {
            oneOnOneBotContestActive = true
            botPullBack = 0.62
            botBallVisible = false
            let jumpNow = ASystem.nanoTime()
            oneOnOneBotJumpStartedAtNanos = jumpNow
            oneOnOneBotJumpUntilNanos = jumpNow + Self.ONE_ON_ONE_JUMP_MS * 1_000_000
            oneOnOneBotJumpHeightMultiplier = Self.ONE_ON_ONE_BOT_BLOCK_JUMP_MULTIPLIER
            invalidate()
        }
    }

    func oneOnOneHumanBlockHandPoint(ballX: Float, ballY: Float) -> APointF {
        let jump = oneOnOneHumanJumpOffsetPx()
        let shoulderY = playerFootY - dp(v: 92) - jump
        let dx = ballX - playerX
        let dy = ballY - shoulderY
        let len = ksqrt(dx * dx + dy * dy).coerceAtLeast(1)
        let reach = dp(v: 28 + Float(oneOnOneHumanHeightRating) * 0.085)
        return APointF(playerX + dx / len * reach, shoulderY + dy / len * reach)
    }

    func oneOnOneBotBlockHandPoint(ballX: Float, ballY: Float) -> APointF {
        let jump = oneOnOneBotJumpOffsetPx()
        let shoulderY = botFootY - dp(v: 92) - jump
        let dx = ballX - botX
        let dy = ballY - shoulderY
        let len = ksqrt(dx * dx + dy * dy).coerceAtLeast(1)
        let reach = dp(v: 28 + Float(oneOnOneBotHeightRating) * 0.085)
        return APointF(botX + dx / len * reach, shoulderY + dy / len * reach)
    }

    // MARK: - Shot-block physics hooks (Kotlin 4811-4901), called per physics sub-step

    func applyOneOnOneBotBlockToHumanShot(
        state: TripleShotPhysics.ShotState,
        geometry: TripleShotPhysics.Geometry
    ) {
        if !oneOnOneEnabled ||
            oneOnOneHumanShotBlocked ||
            !oneOnOneBotContestActive ||
            state.elapsedSeconds > Self.ONE_ON_ONE_BLOCK_COLLISION_MAX_SECONDS {
            return
        }

        let ball = humanShotPresentation.sample(state: state, geometry: geometry, hoop: worldHoop(), verticalScale: worldVerticalScale())
        let handWorld = releaseSocket(human: false, motion: TripleShotPlayerRenderer.Motion.BLOCK)
        let reachMetres = Float(0.38) + Float(0.12) * (oneOnOneBotBlockRating.toFloat() / Float(100))
        let distance = ksqrt((ball.x - handWorld.x) * (ball.x - handWorld.x) + (ball.y - handWorld.y) * (ball.y - handWorld.y) +
                             (ball.z - handWorld.z) * (ball.z - handWorld.z))
        if distance > reachMetres { return }
        let hand = humanShotPresentation.planePoint(point: handWorld, geometry: geometry, hoop: worldHoop(), scale: worldVerticalScale())
        if reflectBallFromDefenderHand(state: state, handX: hand.0, handY: hand.1,
                                       collisionRadius: reachMetres * geometry.ballRadius / Float(0.21)) {
            oneOnOneHumanShotBlocked = true
            oneOnOneBotContestActive = false
            botPullBack = 0
            kickBlockedBallAwayFromHoop(state: state, geometry: geometry, strength: 0.72)
            oneOnOneBlockEventListener?(false)
            triggerRimShake(impactSpeed: 0)
            invalidate()
        }
    }

    func applyOneOnOneHumanBlockToBotShot(
        state: TripleShotPhysics.ShotState,
        geometry: TripleShotPhysics.Geometry
    ) {
        if !oneOnOneEnabled ||
            oneOnOneBotShotBlocked ||
            ASystem.nanoTime() > oneOnOneHumanBlockUntilNanos ||
            state.elapsedSeconds > Self.ONE_ON_ONE_BLOCK_COLLISION_MAX_SECONDS {
            return
        }

        let ball = botShotPresentation.sample(state: state, geometry: geometry, hoop: worldHoop(), verticalScale: worldVerticalScale())
        let handWorld = releaseSocket(human: true, motion: TripleShotPlayerRenderer.Motion.BLOCK)
        let reachMetres = Float(0.38) + Float(0.12) * (oneOnOneHumanBlockRating.toFloat() / Float(100))
        let distance = ksqrt((ball.x - handWorld.x) * (ball.x - handWorld.x) + (ball.y - handWorld.y) * (ball.y - handWorld.y) +
                             (ball.z - handWorld.z) * (ball.z - handWorld.z))
        if distance > reachMetres { return }
        let hand = botShotPresentation.planePoint(point: handWorld, geometry: geometry, hoop: worldHoop(), scale: worldVerticalScale())
        if reflectBallFromDefenderHand(state: state, handX: hand.0, handY: hand.1,
                                       collisionRadius: reachMetres * geometry.ballRadius / Float(0.21)) {
            oneOnOneBotShotBlocked = true
            oneOnOneHumanBlockUntilNanos = 0
            kickBlockedBallAwayFromHoop(state: state, geometry: geometry, strength: 0.82)
            oneOnOneBlockEventListener?(true)
            invalidate()
        }
    }

    func kickBlockedBallAwayFromHoop(
        state: TripleShotPhysics.ShotState,
        geometry: TripleShotPhysics.Geometry,
        strength: Float
    ) {
        let dx = state.x - geometry.hoopCenterX
        let dy = state.y - geometry.hoopY
        let len = ksqrt(dx * dx + dy * dy).coerceAtLeast(1)
        let ux = dx / len
        let uy = dy / len
        let kick = dp(v: 78) * strength.coerceIn(0.25, 1)
        state.vx += ux * kick
        state.vy += uy * kick - dp(v: 18)
        state.previousX = state.x
        state.previousY = state.y
    }

    /** Elastic-ish hand collision. Direction comes from the actual contact normal. */
    func reflectBallFromDefenderHand(
        state: TripleShotPhysics.ShotState,
        handX: Float,
        handY: Float,
        collisionRadius: Float
    ) -> Bool {
        let dx = state.x - handX
        let dy = state.y - handY
        let distSq = dx * dx + dy * dy
        if distSq > collisionRadius * collisionRadius { return false }

        let dist = ksqrt(distSq).coerceAtLeast(0.5)
        let nx = dx / dist
        let ny = dy / dist
        let dot = state.vx * nx + state.vy * ny
        let impact: Float = dot < -1 ? dot : -ksqrt(state.vx * state.vx + state.vy * state.vy) * 0.42
        let restitution: Float = 0.50
        state.vx -= (1 + restitution) * impact * nx
        state.vy -= (1 + restitution) * impact * ny
        state.vx += nx * dp(v: 28)
        state.vy += ny * dp(v: 20)
        // Blocks should create recoverable scrambles far more often than sideline rockets.
        state.vx += nx >= 0 ? dp(v: 14) : -dp(v: 14)
        state.previousX = state.x
        state.previousY = state.y
        return true
    }

    // MARK: - "Last shot blocked" flags, shot zones (Kotlin 4903-4946)

    func wasLastOneOnOneBotShotBlockedByHuman() -> Bool {
        return oneOnOneEnabled && oneOnOneBotShotBlocked
    }

    func wasLastOneOnOneHumanShotBlockedByBot() -> Bool {
        return oneOnOneEnabled && oneOnOneHumanShotBlocked
    }

    /**
     * Current bot distance band. Character bots use this only to choose which fixed shooting
     * rating (inside / mid / three) controls release precision.
     */
    func currentBotShotZone() -> ShotZone {
        if width <= 0 || height <= 0 {
            return zoneForDifficulty(difficulty: botCurrentStation?.distanceDifficulty ?? 0.50)
        }
        let t = backgroundTransform()
        let sourceX = ((botX - t.offsetX) / t.scaleX).coerceIn(0, Self.BACKGROUND_WIDTH)
        let sourceY = ((botFootY - t.offsetY) / t.scaleY).coerceIn(0, Self.BACKGROUND_HEIGHT)
        let dx = sourceX - Self.SRC_HOOP_CENTER_X
        let dy = sourceY - Self.SRC_HOOP_DEPTH_FOOT_Y
        let distance = ksqrt(dx * dx + dy * dy)
        if distance <= Self.HUMAN_INSIDE_DISTANCE_SRC { return .INSIDE }
        if distance <= Self.HUMAN_MID_DISTANCE_SRC { return .MID_RANGE }
        return .THREE_POINT
    }

    func currentHumanShotZone() -> ShotZone {
        let source = currentPlayerSourcePosition()
        let dx = source.x - Self.SRC_HOOP_CENTER_X
        let dy = source.y - Self.SRC_HOOP_DEPTH_FOOT_Y
        let distance = ksqrt(dx * dx + dy * dy)

        if distance <= Self.HUMAN_INSIDE_DISTANCE_SRC { return .INSIDE }
        if distance <= Self.HUMAN_MID_DISTANCE_SRC { return .MID_RANGE }
        return .THREE_POINT
    }

    /** Shooting Challenge uses the same answer -> court mapping for human and bot. */
    func shotZoneForAnswer(index: Int, answerCount: Int) -> ShotZone {
        return zoneForDifficulty(difficulty: stationForAnswer(index: index, count: answerCount).distanceDifficulty)
    }

    // MARK: - Shooting Challenge turn helpers (Kotlin 4948-5029)

    /**
     * At the beginning of every local-bot challenge question the human owns the one visible
     * ball. The bot waits empty-handed until its response turn.
     */
    func prepareHumanChallengeTurn() {
        if !botEnabled { return }
        humanWaitingForTurn = false
        botAimAnimator?.cancel()
        botPullBack = 0
        botFineAim = 0
        botBallVisible = false
        ballVisible = true
        let held = heldBallPosition(motionOverride: .IDLE)
        ballX = held.x
        ballY = held.y
        ballRotationDeg = 0
        invalidate()
    }

    /** Moves the bot to the exact station represented by its chosen answer. */
    func moveBotToAnswerStation(
        index: Int,
        answerCount: Int,
        animate: Bool = true,
        onEnd: (() -> Void)? = nil
    ) {
        if !botEnabled {
            onEnd?()
            return
        }
        if width <= 0 || height <= 0 {
            post { [weak self] in
                self?.moveBotToAnswerStation(index: index, answerCount: answerCount, animate: animate, onEnd: onEnd)
            }
            return
        }

        let station = stationForAnswer(index: index, count: answerCount)
        botCurrentStation = station
        let point = stationScreenPoint(index: index, count: answerCount)
        botBallVisible = true
        setBotPosition(x: point.x, y: point.y, animate: animate, onEnd: onEnd)
    }

    /**
     * Clears the answer station before the bot walks into it. This is Challenge-only; HORSE
     * keeps its separate single-possession/waiting-spot machinery.
     */
    func moveHumanToChallengeWaitingSpot(
        avoidAnswerIndex: Int,
        answerCount: Int,
        seed: Int64,
        animate: Bool = true,
        onEnd: (() -> Void)? = nil
    ) {
        if width <= 0 || height <= 0 {
            post { [weak self] in
                self?.moveHumanToChallengeWaitingSpot(
                    avoidAnswerIndex: avoidAnswerIndex,
                    answerCount: answerCount,
                    seed: seed,
                    animate: animate,
                    onEnd: onEnd
                )
            }
            return
        }

        humanWaitingForTurn = true
        cancelHumanIdleDribble()
        ballVisible = false
        botBallVisible = botEnabled
        selectedStation = -1
        shotGuidesVisible = false

        let avoid = stationForAnswer(index: avoidAnswerIndex, count: answerCount)
        let station = chooseChallengeWaitingStation(avoid: avoid, seed: seed)
        let point = botStationScreenPoint(station: station)
        setPlayerPosition(x: point.x, y: point.y, animate: animate, onEnd: onEnd)
        invalidate()
    }

    func zoneForDifficulty(difficulty: Float) -> ShotZone {
        if difficulty < 0.34 { return .INSIDE }
        if difficulty < 0.68 { return .MID_RANGE }
        return .THREE_POINT
    }

    // MARK: - Bot enable/disable, hot hand, random spot (Kotlin 5031-5109)

    /// Kotlin `label: String = botLabel`: a Swift default cannot read an instance property, so `nil` stands for
    /// "the current botLabel", resolved first thing (where Kotlin evaluates the default).
    func setBotOpponentEnabled(
        enabled: Bool,
        seed: Int64 = ASystem.currentTimeMillis(),
        label: String? = nil
    ) {
        let label = label ?? botLabel
        if !enabled {
            botEnabled = false
            sharedHorseBallOwner = nil
            cancelHumanIdleDribble()
            botMoveAnimator?.cancel()
            botMoveAnimator = nil
            cancelBotShotSimulation(callEnd: false)
            botCurrentStation = nil
            recentBotSpotIds.removeAll()
            botBallVisible = false
            botHotHand = false
            invalidate()
            return
        }

        botEnabled = true
        botLabel = label

        if width <= 0 || height <= 0 {
            post { [weak self] in
                guard let self = self else { return }
                if botEnabled {
                    setBotOpponentEnabled(enabled: true, seed: seed, label: label)
                }
            }
            return
        }

        let station = chooseBotStation(seed: seed)
        botCurrentStation = station
        rememberBotSpot(id: station.id)

        let p = botStationScreenPoint(station: station)
        setBotPosition(x: p.x, y: p.y, animate: false)

        botFineAim = 0
        botPullBack = 0
        botBallVisible = true
        let held = heldBotBallPosition()
        botBallX = held.x
        botBallY = held.y
        botBallRotationDeg = 0
        invalidate()
    }

    func setBotHotHand(active: Bool) {
        botHotHand = active
        invalidate()
    }

    /**
     * After each bot attempt it walks/dribbles to a new legal grounded location.
     * The new spot avoids the human's current feet position and the bot's own recent spots.
     *
     * Unused in Android too (no callers); kept for API parity.
     */
    func moveBotToRandomSpot(
        seed: Int64,
        animate: Bool = true,
        onEnd: (() -> Void)? = nil
    ) {
        if !botEnabled {
            onEnd?()
            return
        }

        if width <= 0 || height <= 0 {
            post { [weak self] in self?.moveBotToRandomSpot(seed: seed, animate: animate, onEnd: onEnd) }
            return
        }

        let station = chooseBotStation(seed: seed)
        botCurrentStation = station
        rememberBotSpot(id: station.id)
        let p = botStationScreenPoint(station: station)
        setBotPosition(x: p.x, y: p.y, animate: animate, onEnd: onEnd)
    }

    // MARK: - Bot shot launcher (Kotlin 5111-5260)

    /**
     * Launches the visible bot ball through the very same TripleShotPhysics engine used by
     * the human. Only the bot state is touched; the human player's shot state is not reused.
     */
    func animateBotShot(
        skill: ShotSkill,
        pullBackAtRelease: Float,
        hot: Bool,
        oneOnOneFinish: OneOnOneDriveFinish = .JUMPER,
        onEnd: @escaping (ShotResult) -> Void
    ) {
        if !botEnabled { return }

        cancelBotShotSimulation(callEnd: false)
        if oneOnOneEnabled {
            oneOnOneBotShotBlocked = false
        }

        if width <= 0 || height <= 0 {
            post { [weak self] in
                self?.animateBotShot(
                    skill: skill,
                    pullBackAtRelease: pullBackAtRelease,
                    hot: hot,
                    oneOnOneFinish: oneOnOneFinish,
                    onEnd: onEnd
                )
            }
            return
        }

        let station: Station
        if oneOnOneEnabled {
            // 1v1 shoots from the body's actual live location. Never teleport the attacker to
            // one of the trivia/HORSE bot stations when the possession reaches release.
            let t = backgroundTransform()
            let sourceX = ((botX - t.offsetX) / t.scaleX).coerceIn(0, Self.BACKGROUND_WIDTH)
            let sourceY = ((botFootY - t.offsetY) / t.scaleY).coerceIn(0, Self.BACKGROUND_HEIGHT)
            let dx = sourceX - Self.SRC_HOOP_CENTER_X
            let dy = sourceY - Self.SRC_HOOP_DEPTH_FOOT_Y
            let distance = ksqrt(dx * dx + dy * dy)
            let liveStation = Station(
                id: "ONE_ON_ONE_BOT",
                sourceX: sourceX,
                sourceY: sourceY,
                distanceDifficulty: ((distance - 280) / 820).coerceIn(0.12, 0.96),
                zone: "one_on_one"
            )
            botCurrentStation = liveStation
            station = liveStation
        } else if let current = botCurrentStation {
            station = current
        } else {
            let chosen = chooseBotStation(seed: ASystem.nanoTime())
            botCurrentStation = chosen
            rememberBotSpot(id: chosen.id)
            let p = botStationScreenPoint(station: chosen)
            setBotPosition(x: p.x, y: p.y, animate: false)
            station = chosen
        }

        botHotHand = hot
        botFineAim = skill.aimError.coerceIn(-1.30, 1.30)
        botBallVisible = true
        botShotOnEnd = onEnd
        botShotMadeAtSeconds = nil

        let releasePull = pullBackAtRelease.coerceIn(0.22, 1.20)
        oneOnOneBotActiveFinish = oneOnOneEnabled ? oneOnOneFinish : .JUMPER
        botAimAnimator?.cancel()

        /*
         * Give a visible character time to build the shot. V18 jumped directly to SET/RELEASE,
         * so Maya looked like a still image. Over ~0.55s the renderer now naturally visits
         * LOW -> MID -> SET while the same dynamic ball follows each authored hand socket.
         * No interpolator is set: Android's default AccelerateDecelerate applies.
         */
        let aimAnimator = AValueAnimator.ofFloat(0, 1)
        aimAnimator.duration = Self.BOT_VISIBLE_AIM_MS
        aimAnimator.addUpdateListener { [weak self] animator in
            guard let self = self else { return }
            let t = animator.animatedValueFloat
            if t < 0.27 {
                // Hold LOW long enough to read as an intentional load, not one frame.
                botPullBack = 0.03
            } else if t < 0.68 {
                // MID owns the largest part of the aiming beat.
                botPullBack = lerp(a: 0.08, b: 0.42, t: (t - 0.27) / 0.41)
            } else {
                // Finish visibly in SET before the physical release begins.
                botPullBack = kmax(0.50, releasePull)
            }
            let held = heldBotBallPosition()
            botBallX = held.x
            botBallY = held.y
            invalidate()
        }
        // Kotlin `object : AnimatorListenerAdapter() { private var cancelled = false ... }`.
        var cancelled = false
        aimAnimator.addListener(AAnimatorListenerAdapter(
            onEnd: { [weak self] _ in
                guard let self = self else { return }
                if cancelled || !botEnabled { return }

                botPullBack = releasePull
                let rawStart = heldBotBallPosition()
                let socket: CourtPoint? = oneOnOneEnabled ? releaseSocket(human: false) : nil
                let base = buildPhysicsGeometry()
                let geometry = socket != nil
                    ? TripleShotRadialShot.geometry(base: base, release: socket!, hoop: worldHoop(), scale: worldVerticalScale())
                    : base
                let start: APointF
                if let socket = socket {
                    botShotPresentation.prepareWorldRelease(point: socket, scale: worldVerticalScale())
                    let point = TripleShotRadialShot.start(release: socket, hoop: worldHoop(), geometry: geometry, scale: worldVerticalScale())
                    start = APointF(point.0, point.1)
                } else {
                    start = rawStart
                }
                let targetX =
                    geometry.hoopCenterX +
                        skill.aimError.coerceIn(-1.30, 1.30) * aimRangePx()

                let state = TripleShotPhysics.createLaunch(
                    skill: skill,
                    startX: start.x,
                    startY: start.y,
                    targetX: targetX,
                    targetY: geometry.hoopY,
                    pullBack01: releasePull,
                    geometry: geometry,
                    distanceDifficulty: station.distanceDifficulty,
                    neutralPowerHitsTarget: oneOnOneEnabled,
                    compactOneOnOneArc: oneOnOneEnabled || horseJumpShot,
                    rejectUpwardBasketEntry:
                        oneOnOneEnabled && oneOnOneFinish != .JUMPER
                )

                botAimAnimator = nil
                botPullBack = 0
                botPhysicsState = state
                botPhysicsGeometry = geometry
                botBallX = state.x
                botBallY = state.y
                botShotLastFrameNanos = 0
                botShotFrameRunning = true

                removeCallbacks(botPhysicsFrameRunnable)
                postOnAnimation(botPhysicsFrameRunnable)
                invalidate()
            },
            onCancel: { _ in
                cancelled = true
            }
        ))
        aimAnimator.start()
        botAimAnimator = aimAnimator
    }

    // MARK: - Solo, Practice and Challenge human (Kotlin 5262-5347)

    /**
     * index is the logical answer index (A=0, B=1...). The Kotlin doc comment says stationForAnswer()
     * mirrors the stations in RTL; the code does not (spec 09 §8.13), and neither does this port.
     */
    func setStation(index: Int, animate: Bool = true) {
        humanWaitingForTurn = false
        let safe = index.coerceIn(0, answerCount - 1)
        selectedStation = safe
        let point = stationScreenPoint(index: safe, count: answerCount)
        setPlayerPosition(x: point.x, y: point.y, animate: animate)
        shotGuidesVisible = true
        invalidate()
    }

    /**
     * Starts a real physics shot.
     *
     * pullBackAtRelease is the MAXIMUM pull-back reached during the gesture, not the
     * current phone angle after the hand has already returned forward.
     */
    func animateShot(
        skill: ShotSkill,
        stationIndex: Int,
        answerCount: Int,
        pullBackAtRelease: Float,
        hot: Bool,
        onEnd: @escaping (ShotResult) -> Void
    ) {
        cancelShotSimulation(callEnd: false)

        if width <= 0 || height <= 0 {
            post { [weak self] in
                self?.animateShot(
                    skill: skill,
                    stationIndex: stationIndex,
                    answerCount: answerCount,
                    pullBackAtRelease: pullBackAtRelease,
                    hot: hot,
                    onEnd: onEnd
                )
            }
            return
        }

        hotHand = hot
        ballVisible = true
        let releaseMotion = preReleaseHumanMotionForPull(pull: pullBackAtRelease)
        let start = heldBallPosition(motionOverride: releaseMotion)
        shotGuidesVisible = false
        humanReleaseStartedAtNanos = ASystem.nanoTime()
        shotOnEnd = onEnd
        shotMadeAtSeconds = nil
        beginLiveReplayCapture()

        let geometry = buildPhysicsGeometry()
        let station = stationForAnswer(index: stationIndex, count: answerCount)

        // Aim can travel well outside the rim. The user sees the same target before release.
        let targetX =
            geometry.hoopCenterX +
                skill.aimError.coerceIn(-1.30, 1.30) * aimRangePx()
        let targetY = geometry.hoopY

        // Physics automatically chooses NORMAL / SIDE_ARC / HIGH_LOB from this spot.
        // The player keeps the exact same controls; no extra "hook" gesture is required.
        let state = TripleShotPhysics.createLaunch(
            skill: skill,
            startX: start.x,
            startY: start.y,
            targetX: targetX,
            targetY: targetY,
            pullBack01: pullBackAtRelease.coerceIn(0.22, 1.20),
            geometry: geometry,
            distanceDifficulty: station.distanceDifficulty
        )

        physicsState = state
        physicsGeometry = geometry
        ballX = state.x
        ballY = state.y
        shotLastFrameNanos = 0
        shotFrameRunning = true

        removeCallbacks(physicsFrameRunnable)
        postOnAnimation(physicsFrameRunnable)
    }
}
