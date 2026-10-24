import Foundation

// Port of `ui/TripleShotOneOnOneFragment.kt` (Android 6c38131), part 2 of 2: lines 1795-3467 (spec 16-one2).
//
// An extension of the class declared in TripleShotOneOnOneFragment.swift (DESIGN 2.9 / 2.10): methods, the static
// companion constants and newInstance only; every stored property and every `override` lives in part 1. Kotlin
// `private` members are internal because the class is split over two files. Members keep the Kotlin order:
// automatic ball-state handling, the sensor listener (TripleShotSensorController.Listener), the human release,
// the ROTATE movement path and control-mode helpers, the bot possession script (settle, attack loop, better-shot
// search, shot), the possession-question race, bidi and gendered-string helpers, HUD and score flashes, the end of
// the match (winner, rematch, exit), the rating helpers and the companion object.
//
// Not ported: `applyHumanShootingRating` (L3271-3301, no caller: spec 16 sections 1.1 / 9.4).
// iOS-only helper (area s-one2): `One2Regex`, the Kotlin `Regex(pattern)` + `replace(input) { }` pair used by
// bidiSafeQuestionPrompt, over NSRegularExpression. Android's java.util.regex is ICU4C-backed (Android SDK
// java/util/regex/Pattern.java: "Starting from Android 2.3 Gingerbread, ICU4C becomes the backend"; `\d` =
// \p{IsDigit}, `\s` = \p{IsWhite_Space}) and NSRegularExpression is ICU too, so the Kotlin pattern is used unchanged
// and matches exactly what the device matches.

extension TripleShotOneOnOneFragment {

    // MARK: - Automatic ball state (L1795-1904)

    func handleAutomaticBallState(state: TripleShotCourtView.OneOnOneBallState) {
        hideShotMeter()
        resetTouchPointerState()
        switch state {
        case .LOOSE:
            humanDribblePickedUp = false
            heldReleaseCommitted = false
            if let r = pendingHeldSingleTap { handler.removeCallbacks(r) }
            pendingHeldSingleTap = nil
            holdPoseGeneration += 1
            courtView.setOneOnOneHumanHeldMotion(high: nil)
            phase = Phase.REBOUND
            reboundActive = true
            humanHasBall = false
            aiming = false
            shotInProgress = false
            stopBotAttack()
            sensor.prepareForMovement()
            statusText.setText(res: R.string.minik_swish_one_on_one_loose_ball)

        case .HUMAN:
            humanDribblePickedUp = false
            heldReleaseCommitted = false
            if let r = pendingHeldSingleTap { handler.removeCallbacks(r) }
            pendingHeldSingleTap = nil
            holdPoseGeneration += 1
            courtView.setOneOnOneHumanHeldMotion(high: nil)
            phase = Phase.LIVE_OFFENSE
            reboundActive = false
            botPossessionSerial += 1
            stopBotAttack()
            humanHasBall = true
            aiming = false
            shotInProgress = false
            sensor.prepareForMovement()
            statusText.setText(res: R.string.minik_swish_one_on_one_rebound_you)

        case .BOT:
            humanDribblePickedUp = false
            heldReleaseCommitted = false
            if let r = pendingHeldSingleTap { handler.removeCallbacks(r) }
            pendingHeldSingleTap = nil
            holdPoseGeneration += 1
            courtView.setOneOnOneHumanHeldMotion(high: nil)
            phase = Phase.LIVE_OFFENSE
            reboundActive = false
            humanHasBall = false
            aiming = false
            shotInProgress = false
            sensor.prepareForMovement()
            statusText.text = getString(
                genderedBotString(
                    maleRes: R.string.minik_swish_one_on_one_rebound_bot_male,
                    femaleRes: R.string.minik_swish_one_on_one_rebound_bot_female,
                    neutralRes: R.string.minik_swish_one_on_one_rebound_bot_neutral
                ),
                botProfile.displayName
            )
            // A real rebound continues from the place where it was caught; do not reset.
            scheduleBotPossession(alreadyHasBall: true, resetCheck: false)

        case .DEAD_HUMAN:
            humanDribblePickedUp = false
            heldReleaseCommitted = false
            if let r = pendingHeldSingleTap { handler.removeCallbacks(r) }
            pendingHeldSingleTap = nil
            holdPoseGeneration += 1
            courtView.setOneOnOneHumanHeldMotion(high: nil)
            phase = Phase.DEAD_BALL
            reboundActive = false
            humanHasBall = false
            aiming = false
            shotInProgress = false
            stopBotAttack()
            statusText.setText(res: R.string.minik_swish_one_on_one_dead_ball)
            updateHud()
            beginPossessionQuestion(
                fallbackHumanGetsBall: true,
                reasonText: questionAfterOutReason()
            )
            return

        case .DEAD_BOT:
            humanDribblePickedUp = false
            heldReleaseCommitted = false
            if let r = pendingHeldSingleTap { handler.removeCallbacks(r) }
            pendingHeldSingleTap = nil
            holdPoseGeneration += 1
            courtView.setOneOnOneHumanHeldMotion(high: nil)
            phase = Phase.DEAD_BALL
            reboundActive = false
            humanHasBall = false
            aiming = false
            shotInProgress = false
            stopBotAttack()
            statusText.setText(res: R.string.minik_swish_one_on_one_dead_ball)
            updateHud()
            beginPossessionQuestion(
                fallbackHumanGetsBall: false,
                reasonText: questionAfterOutReason()
            )
            return
        }
        updateHud()
    }

    // MARK: - TripleShotSensorController.Listener (L1906-1945)

    func onAimChanged(normalizedAim: Float) {
        if !aiming || shotInProgress || ended { return }
        courtView.setFineAim(normalized: normalizedAim)
    }

    func onPullBackChanged(normalizedPullBack: Float, armed: Bool) {
        if !aiming || shotInProgress || ended { return }
        let pull = normalizedPullBack.coerceIn(0, 1.20)
        peakPullBackDuringAim = kmax(peakPullBackDuringAim, pull)
        courtView.setPullBack(normalized: pull)

        let now = ASystem.nanoTime()
        if peakPullBackDuringAim >= Self.PUMP_FAKE_ARM_PULL &&
            pull <= Self.PUMP_FAKE_RETURN_PULL &&
            now - lastPumpFakeNanos >= Self.PUMP_FAKE_MIN_GAP_MS * 1_000_000 {
            courtView.oneOnOnePumpFakeCycle()
            peakPullBackDuringAim = pull
            lastPumpFakeNanos = now
            statusText.setText(res: R.string.minik_swish_one_on_one_fake_success)
        }
    }

    func onShotPhaseChanged(phase: TripleShotSensorController.ShotPhase) {}

    func onShotGesture(skill: ShotSkill, pullBack01: Float) {
        if !aiming || shotInProgress || ended || !humanHasBall { return }

        let releaseMs: Int64 =
            aimStartedAtNanos == 0 ? Self.QUICK_RELEASE_NEUTRAL_MS
            : ((ASystem.nanoTime() - aimStartedAtNanos) / 1_000_000).coerceAtLeast(0)

        releaseHumanShot(
            skill: skill,
            pullBack01: pullBack01,
            releaseMs: releaseMs,
            movingEscape: shotEscapeUsed
        )
    }

    // MARK: - Human release (L1947-2052)

    /// `releaseMs` and `movingEscape` are unused, as in Kotlin (they fed the dead applyHumanShootingRating).
    func releaseHumanShot(
        skill: ShotSkill,
        pullBack01: Float,
        releaseMs: Int64,
        movingEscape: Bool,
        shotChancePercent: Int? = nil,
        finish: TripleShotCourtView.OneOnOneDriveFinish = TripleShotCourtView.OneOnOneDriveFinish.JUMPER
    ) {
        if !aiming || shotInProgress || ended || !humanHasBall { return }

        let zone = courtView.currentHumanShotZone()
        let chance =
            (shotChancePercent ?? calculateHumanShotChance())
                .coerceIn(Self.MIN_SHOT_CHANCE_PERCENT, Self.MAX_SHOT_CHANCE_PERCENT)
        shotSequence += 1
        let sequence = shotSequence
        let tunedSkill = chanceDrivenSkill(
            baseSkill: skill,
            chancePercent: chance,
            sequence: sequence,
            salt: Self.HUMAN_SHOT_ROLL_SALT,
            zone: zone,
            finish: finish
        )

        quickShotGeneration += 1
        quickShotActive = false
        quickShotStartedAtNanos = 0
        quickShotPullOffset = 0
        quickShotFineAim = 0
        quickFinish = TripleShotCourtView.OneOnOneDriveFinish.JUMPER
        humanDribblePickedUp = false
        heldReleaseCommitted = false
        heldFinish = TripleShotCourtView.OneOnOneDriveFinish.JUMPER
        if let r = pendingHeldSingleTap { handler.removeCallbacks(r) }
        pendingHeldSingleTap = nil
        holdPoseGeneration += 1
        courtView.setOneOnOneHumanHeldMotion(high: nil)
        aiming = false
        shotInProgress = true
        reboundActive = false
        phase = Phase.BALL_IN_FLIGHT
        hideShotMeter()

        statusText.setText(res: R.string.minik_swish_one_on_one_ball_up)
        updateControls()

        courtView.animateOneOnOneHumanShot(
            skill: tunedSkill,
            pullBackAtRelease: pullBack01,
            finish: finish
        ) { [weak self] result in
            guard let self = self else { return }
            if !self.isAdded || self.ended { return }
            BasketballSoundscape.effect(context: self.requireContext(),
                                        kind: result.outcome.made ? BasketballSoundscape.Effect.APPLAUSE : BasketballSoundscape.Effect.DISAPPOINT)
            self.shotInProgress = false
            if result.outcome.made {
                self.humanScore += self.pointsFor(zone: zone)
                self.statusText.text = self.getString(
                    self.genderedCharacterString(
                        profile: self.humanProfile,
                        maleRes: R.string.minik_swish_one_on_one_made_male,
                        femaleRes: R.string.minik_swish_one_on_one_made_female,
                        neutralRes: R.string.minik_swish_one_on_one_made_neutral
                    ),
                    self.playerName.kotlinIsBlank ? self.humanProfile.displayName : self.playerName,
                    self.pointsFor(zone: zone)
                )
                self.updateHud()
                self.flashHumanScore()

                if self.checkWinner() { return }

                self.humanHasBall = false
                self.reboundActive = false
                self.phase = Phase.CHECK_BALL
                self.beginPossessionQuestion(
                    fallbackHumanGetsBall: false,
                    reasonText: self.getString(R.string.minik_swish_one_on_one_question_after_score)
                )
            } else {
                self.humanHasBall = false
                self.reboundActive = true
                self.phase = Phase.REBOUND
                if self.courtView.wasLastOneOnOneHumanShotBlockedByBot() {
                    self.statusText.text = self.getString(
                        self.genderedBotString(
                            maleRes: R.string.minik_swish_one_on_one_blocked_by_bot_male,
                            femaleRes: R.string.minik_swish_one_on_one_blocked_by_bot_female,
                            neutralRes: R.string.minik_swish_one_on_one_blocked_by_bot_neutral
                        ),
                        self.botProfile.displayName
                    )
                } else {
                    self.statusText.text = self.getString(
                        self.genderedCharacterString(
                            profile: self.humanProfile,
                            maleRes: R.string.minik_swish_one_on_one_missed_rebound_male,
                            femaleRes: R.string.minik_swish_one_on_one_missed_rebound_female,
                            neutralRes: R.string.minik_swish_one_on_one_missed_rebound_neutral
                        ),
                        self.playerName.kotlinIsBlank ? self.humanProfile.displayName : self.playerName
                    )
                }
                self.updateHud()
            }
        }
    }

    // MARK: - ROTATE movement (L2054-2083) and control mode (L2085-2116)

    func onMovementChanged(horizontal: Float, vertical: Float) {
        if controlMode != ControlMode.ROTATE || !isAdded || ended { return }
        if possessionQuestionActive || checkTransitionActive || aiming || shotInProgress { return }

        let now = ASystem.nanoTime()
        let previous = sensorMoveLastNanos
        sensorMoveLastNanos = now
        if previous == 0 { return }
        let dt = ((now - previous).toFloat() / Float(1_000_000_000)).coerceIn(0.008, 0.050)
        let magnitude = ksqrt(horizontal * horizontal + vertical * vertical).coerceIn(0, 1)
        if magnitude < Self.ROTATE_MOVE_DEAD_ZONE { return }

        let maxSpeedDpPerSec =
            Self.MOVE_BASE_SPEED_DP_PER_SEC + humanProfile.ratings.speed.toFloat() * Self.MOVE_SPEED_RATING_DP_PER_SEC
        let dx = dp(value: horizontal * maxSpeedDpPerSec * dt * Self.ROTATE_MOVE_SCALE)
        let dy = dp(value: vertical * maxSpeedDpPerSec * dt * Self.ROTATE_MOVE_SCALE)
        let len = ksqrt(dx * dx + dy * dy)
        if len <= dp(value: 0.15) { return }

        recentMoveIntensity01 = magnitude
        recentMoveAtNanos = now
        recentMoveDx = dx
        recentMoveDy = dy
        courtView.moveOneOnOneHumanByTouch(dx: dx, dy: dy)

        if humanHasBall && !reboundActive {
            detectCrossoverGesture(rawDx: horizontal * dp(value: 12))
            detectHesitationGesture(rawDy: vertical * dp(value: 12))
        }
    }

    func loadControlMode() -> ControlMode? {
        guard let raw = requireContext()
            .getSharedPreferences(Self.CONTROL_PREFS, MODE_PRIVATE)
            .getString(Self.CONTROL_MODE_KEY, nil) else { return nil }
        // `runCatching { ControlMode.valueOf(raw) }.getOrNull()`
        return ControlMode.named(raw)
    }

    func syncSensorForControlMode() {
        if sensor == nil || ended || !isResumed { return }
        if controlMode == ControlMode.ROTATE {
            if !sensorRunning {
                sensor.start()
                sensorRunning = true
            }
            sensor.prepareForMovement()
        } else {
            stopSensorIfRunning()
        }
    }

    func stopSensorIfRunning() {
        if sensor != nil && sensorRunning {
            sensor.stop()
            sensorRunning = false
        }
        sensorMoveLastNanos = 0
    }

    func onSensorAvailability(hasRotation: Bool, hasGyro: Bool) {
        // The existing controller already provides its touch fallback, so 1v1 remains playable
        // on devices without the full sensor set.
    }

    // MARK: - Bot possession (L2118-2397)

    func scheduleBotPossession(
        alreadyHasBall: Bool,
        resetCheck: Bool = false
    ) {
        hideShotMeter()
        if ended { return }
        stopBotAttack()
        botPossessionSerial += 1
        let serial = botPossessionSerial
        botShotSearchAttempts = 0
        humanHasBall = false
        reboundActive = false
        aiming = false
        phase = Phase.LIVE_OFFENSE
        sensor.prepareForMovement()
        if !alreadyHasBall { courtView.oneOnOneGiveBallToBot() }
        if resetCheck {
            courtView.resetOneOnOneCheckPositions(humanOffense: false, animate: true)
        }
        updateHud()

        // A possession is now basketball, not "walk to a random station and instantly shoot".
        // Maya jabs, drives, can cross over and only then decides to pull up. Human movement stays
        // live the whole time, so getting into the lane genuinely changes what happens.
        handler.postDelayed({ [weak self] in
            guard let self = self else { return }
            if !self.isAdded || self.ended || serial != self.botPossessionSerial || self.humanHasBall { return }
            self.startBotAttack(serial: serial)
        }, Self.BOT_POSSESSION_SETTLE_MS)
    }

    func startBotAttack(serial: Int64) {
        if ended || serial != botPossessionSerial || humanHasBall || reboundActive { return }
        stopBotAttack()

        // Kotlin `Random(seed xor serial * BOT_ATTACK_SEED_SALT)`: `*` binds tighter than infix `xor`; Long wraps.
        let random = KotlinRandom(seed: seed ^ (serial &* Self.BOT_ATTACK_SEED_SALT))
        let aggression01 = botProfile.tendencies.attackAggression.toFloat() / Float(100)
        let handling01 = botProfile.ratings.ballHandling.toFloat() / Float(100)
        let offense01 = botProfile.ratings.offense.toFloat() / Float(100)
        let speed01 = botProfile.ratings.speed.toFloat() / Float(100)
        let risk01 = botProfile.tendencies.riskTaking.toFloat() / Float(100)
        let creator01 = handling01 * Float(0.58) + offense01 * Float(0.42)
        let missUrgency01 = (botConsecutiveMisses.toFloat() / Float(3)).coerceIn(0, 1)

        // One possession gets a personality-level intention. A sharpshooter may create space,
        // but she does not run away forever: after one escape she re-attacks. Repeated misses and
        // aggressive/risky profiles make a downhill drive more likely.
        // (Draw #1 happens before the threshold, which has no side effects; the sum is left to right.)
        let takeOnRoll = random.nextFloat()
        var takeOnThreshold = Float(0.30) + aggression01 * Float(0.20)
        takeOnThreshold = takeOnThreshold + risk01 * Float(0.16)
        takeOnThreshold = takeOnThreshold + offense01 * Float(0.12)
        takeOnThreshold = takeOnThreshold + missUrgency01 * Float(0.18)
        let takeOnDefender = takeOnRoll < takeOnThreshold.coerceIn(0.28, 0.82)

        var side: Float = random.nextBoolean() ? 1 : -1
        botPreferredFinishSideSign = side
        let useCrossover = random.nextFloat() < (Float(0.20) + creator01 * Float(0.58)).coerceAtMost(0.84)
        let attackDurationMs: Int64 =
            (Int64(2580) - (aggression01 * Float(700)).toLong() - (speed01 * Float(220)).toLong() -
                (offense01 * Float(190)).toLong())
                .coerceIn(1420, 2480)
        // Kotlin `Long * Float` is a Float product, truncated by toLong().
        let crossoverAtMs = (attackDurationMs.toFloat() * (Float(0.38) + random.nextFloat() * Float(0.12))).toLong()
        let tickMs = Self.BOT_ATTACK_TICK_MS
        var elapsed: Int64 = 0
        var crossed = false
        var evasionCount = 0
        var driveCommitUntilMs: Int64 = 0
        var lastEvasionAtMs: Int64 = Int64.min / 4

        // `lateinit var attack: Runnable; attack = object : Runnable { ... handler.postDelayed(this, tickMs) }`
        let attack = ARunnable(withSelf: { [weak self] attack in
            guard let self = self else { return }
            if !self.isAdded || self.ended || serial != self.botPossessionSerial || self.humanHasBall ||
                self.reboundActive || self.shotInProgress {
                if self.botAttackRunnable === attack { self.botAttackRunnable = nil }
                return
            }

            elapsed += tickMs
            let p = (elapsed.toFloat() / attackDurationMs.toFloat()).coerceIn(0, 1)
            let pressure01 = self.courtView.oneOnOneBotPressure01()
            let openLane = self.courtView.oneOnOneBotHasOpenRimLane()

            // Once Maya has used a protection move, force a short downhill re-attack instead
            // of chaining sidesteps all the way to the sideline.
            if elapsed < driveCommitUntilMs {
                self.courtView.moveOneOnOneBotAttackStep(
                    forwardDp: Float(1.70) + speed01 * Float(1.00) + aggression01 * Float(0.42),
                    lateralDp: side * (Float(0.16) + risk01 * Float(0.20))
                )
            } else {
                // Short-circuit: the nextFloat() draw happens only when the first three conditions hold.
                let evasionReady =
                    evasionCount < Self.BOT_MAX_EVASIONS_PER_ATTACK &&
                        elapsed - lastEvasionAtMs >= Self.BOT_EVASION_COOLDOWN_MS &&
                        pressure01 >= Self.BOT_EVASION_PRESSURE_THRESHOLD &&
                        random.nextFloat() <
                            (Self.BOT_EVASION_BASE_CHANCE + creator01 * Self.BOT_EVASION_HANDLING_CHANCE)
                                .coerceIn(0, 0.90)

                if evasionReady {
                    lastEvasionAtMs = elapsed
                    evasionCount += 1
                    side = self.courtView.oneOnOneBotEscapeSideSign()
                    self.botPreferredFinishSideSign = side
                    self.courtView.oneOnOneBotCrossover(directionSign: side)

                    if takeOnDefender || missUrgency01 >= Float(0.50) {
                        // Attack THROUGH/around the pressure: crossover, protect the ball,
                        // then keep going to the rim rather than retreating to the corner.
                        self.courtView.moveOneOnOneBotAttackStep(
                            forwardDp: Float(1.55) + speed01 * Float(0.95) + aggression01 * Float(0.45),
                            lateralDp: side * (Float(0.62) + handling01 * Float(0.55))
                        )
                        driveCommitUntilMs = elapsed + Self.BOT_REATTACK_COMMIT_MS
                    } else {
                        // A perimeter creator may take ONE clear escape step, then she must
                        // either shoot if it created a real look or re-attack.
                        self.courtView.moveOneOnOneBotAttackStep(
                            forwardDp: Float(0.62) + aggression01 * Float(0.30),
                            lateralDp: side * (Float(1.35) + handling01 * Float(0.90))
                        )
                        driveCommitUntilMs = elapsed + Self.BOT_ESCAPE_THEN_REATTACK_MS
                    }
                } else if p < Float(0.20) {
                    self.courtView.moveOneOnOneBotAttackStep(
                        forwardDp: Float(0.35) + aggression01 * Float(0.30),
                        lateralDp: side * (Float(0.90) + handling01 * Float(0.45))
                    )
                } else if useCrossover && !crossed && elapsed >= crossoverAtMs {
                    crossed = true
                    side *= -1
                    self.botPreferredFinishSideSign = side
                    self.courtView.oneOnOneBotCrossover(directionSign: side)
                    self.courtView.moveOneOnOneBotAttackStep(
                        forwardDp: Float(1.45) + speed01 * Float(0.75),
                        lateralDp: side * (Float(1.05) + handling01 * Float(0.60))
                    )
                } else if p < Float(0.76) {
                    self.courtView.moveOneOnOneBotAttackStep(
                        forwardDp: Float(1.20) + speed01 * Float(1.15) + aggression01 * Float(0.55),
                        lateralDp: side * (Float(0.24) + risk01 * Float(0.56))
                    )
                } else if openLane && !self.courtView.oneOnOneBotIsAtFinishRange() {
                    self.courtView.moveOneOnOneBotAttackStep(
                        forwardDp: Float(2.10) + speed01 * Float(1.18) + missUrgency01 * Float(0.55),
                        lateralDp: side * Float(0.10)
                    )
                } else if takeOnDefender && pressure01 < Self.BOT_HARD_CUTOFF_PRESSURE {
                    // Defender is nearby but not squarely stopping the lane: challenge the
                    // hip and try to get past, instead of automatically bailing out.
                    self.courtView.moveOneOnOneBotAttackStep(
                        forwardDp: Float(1.25) + speed01 * Float(0.95) + aggression01 * Float(0.40),
                        lateralDp: side * (Float(0.42) + risk01 * Float(0.35))
                    )
                } else {
                    // Genuine cutoff: settle for a possible pull-up instead of tunnelling
                    // through the body. botShoot() may still decide the look is too poor.
                    self.courtView.moveOneOnOneBotAttackStep(
                        forwardDp: Float(0.24),
                        lateralDp: side * Float(0.14)
                    )
                }
            }

            let extendOpenDrive =
                elapsed >= attackDurationMs &&
                    elapsed < Self.BOT_OPEN_LANE_MAX_ATTACK_MS &&
                    self.courtView.oneOnOneBotHasOpenRimLane() &&
                    !self.courtView.oneOnOneBotIsAtFinishRange()
            if elapsed >= attackDurationMs && !extendOpenDrive {
                self.botAttackRunnable = nil
                self.botShoot(serial: serial)
            } else {
                self.handler.postDelayed(attack, tickMs)
            }
        })

        botAttackRunnable = attack
        handler.post(attack)
    }

    /**
     * If Maya is about to take another poor jumper, she first tries to improve the possession.
     * Open lane -> attack the rim. Closed lane -> create a lateral angle/crossover and advance.
     * This is deliberately a short live sequence, not a teleport to a canned station.
     */
    func searchForBetterBotShot(serial: Int64) {
        if ended || serial != botPossessionSerial || humanHasBall || reboundActive { return }
        stopBotAttack()
        botShotSearchAttempts += 1

        let handling01 = botProfile.ratings.ballHandling.toFloat() / Float(100)
        let offense01 = botProfile.ratings.offense.toFloat() / Float(100)
        let speed01 = botProfile.ratings.speed.toFloat() / Float(100)
        var side = courtView.oneOnOneBotEscapeSideSign()
        botPreferredFinishSideSign = side
        var stepIndex = 0

        statusText.text = getString(
            R.string.minik_swish_one_on_one_bot_searching_better_shot,
            botProfile.displayName
        )

        // `lateinit var improve: Runnable; improve = object : Runnable { ... }`
        let improve = ARunnable(withSelf: { [weak self] improve in
            guard let self = self else { return }
            if !self.isAdded || self.ended || serial != self.botPossessionSerial || self.humanHasBall ||
                self.reboundActive || self.shotInProgress {
                if self.botAttackRunnable === improve { self.botAttackRunnable = nil }
                return
            }

            stepIndex += 1
            let openImmediateLane = self.courtView.oneOnOneBotHasOpenRimLane()
            if openImmediateLane {
                self.courtView.moveOneOnOneBotAttackStep(
                    forwardDp: Float(2.75) + speed01 * Float(1.55) + offense01 * Float(0.55),
                    lateralDp: side * Float(0.10)
                )
            } else {
                if stepIndex == 1 || stepIndex % 6 == 0 {
                    side = self.courtView.oneOnOneBotEscapeSideSign()
                    self.botPreferredFinishSideSign = side
                    self.courtView.oneOnOneBotCrossover(directionSign: side)
                }
                self.courtView.moveOneOnOneBotAttackStep(
                    forwardDp: Float(0.95) + offense01 * Float(0.85),
                    lateralDp: side * (Float(1.45) + handling01 * Float(1.10))
                )
            }

            let atFinish = self.courtView.oneOnOneBotIsAtFinishRange()
            let hardStop = stepIndex >= Self.BOT_BETTER_SHOT_HARD_MAX_STEPS
            let softStop = stepIndex >= Self.BOT_BETTER_SHOT_SEARCH_STEPS

            if atFinish || hardStop {
                if self.botAttackRunnable === improve { self.botAttackRunnable = nil }
                self.botShoot(serial: serial)
            } else if openImmediateLane {
                // If the lane is still genuinely open, keep attacking instead of taking the
                // same low-quality pull-up just because one short search chunk elapsed.
                self.handler.postDelayed(improve, Self.BOT_BETTER_SHOT_SEARCH_TICK_MS)
            } else if softStop {
                if self.botAttackRunnable === improve { self.botAttackRunnable = nil }
                self.botShoot(serial: serial)
            } else {
                self.handler.postDelayed(improve, Self.BOT_BETTER_SHOT_SEARCH_TICK_MS)
            }
        })

        botAttackRunnable = improve
        handler.post(improve)
    }

    func stopBotAttack() {
        if let r = botAttackRunnable { handler.removeCallbacks(r) }
        botAttackRunnable = nil
    }

    // MARK: - Bot shot (L2399-2567)

    func botShoot(serial: Int64) {
        if ended || serial != botPossessionSerial || humanHasBall { return }

        var zone = courtView.currentBotShotZone()
        let botFinish = courtView.chooseOneOnOneBotDriveFinish(
            movementIntensity01: 0.82,
            dunkAbility: effectiveDunkAbility(profile: botProfile)
        )

        // Do not repeat the same bad pull-up forever. A low-quality jumper gets one or more live
        // attempts to improve position, and after a miss Maya becomes more willing to attack the
        // rim if the defender is not immediately stopping the lane.
        let previewChance = calculateBotShotChance(zone: zone, finish: botFinish)
        let openLane = courtView.oneOnOneBotHasOpenRimLane()
        let shouldSearchBetter =
            botFinish == TripleShotCourtView.OneOnOneDriveFinish.JUMPER &&
                !courtView.oneOnOneBotIsAtFinishRange() &&
                (
                    openLane ||
                        (
                            botShotSearchAttempts < Self.BOT_MAX_BETTER_SHOT_SEARCHES &&
                                (previewChance < Self.BOT_MIN_ACCEPTABLE_JUMPER_CHANCE || botConsecutiveMisses >= 2)
                        )
                )

        if shouldSearchBetter {
            searchForBetterBotShot(serial: serial)
            return
        }

        let finishSide: Float
        if botFinish != TripleShotCourtView.OneOnOneDriveFinish.JUMPER &&
            botConsecutiveMisses > 0 &&
            botConsecutiveMisses % 2 == 1 {
            finishSide = -botPreferredFinishSideSign
        } else {
            finishSide = botPreferredFinishSideSign
        }
        botPreferredFinishSideSign = finishSide
        courtView.beginOneOnOneBotDriveFinish(
            finish: botFinish,
            preferredSideSign: finishSide
        )
        zone = courtView.currentBotShotZone()
        shotInProgress = true
        phase = Phase.BALL_IN_FLIGHT
        switch botFinish {
        case .JUMPER:
            statusText.text = getString(
                genderedBotString(
                    maleRes: R.string.minik_swish_one_on_one_bot_aiming_male,
                    femaleRes: R.string.minik_swish_one_on_one_bot_aiming_female,
                    neutralRes: R.string.minik_swish_one_on_one_bot_aiming_neutral
                ),
                botProfile.displayName
            )
        case .LAYUP:
            statusText.text = getString(
                genderedBotString(
                    maleRes: R.string.minik_swish_one_on_one_bot_layup_male,
                    femaleRes: R.string.minik_swish_one_on_one_bot_layup_female,
                    neutralRes: R.string.minik_swish_one_on_one_bot_layup_neutral
                ),
                botProfile.displayName
            )
        case .DUNK:
            statusText.text = getString(R.string.minik_swish_one_on_one_bot_dunk, botProfile.displayName)
        }
        updateControls()

        /*
         * DUNK is not a jump-shot with a different label. It has its own close-finish animation:
         * the ball stays with Maya's hand on the rise and is placed down through the rim. The only
         * way an open dunk fails is a real timed human block before the ball reaches the cylinder.
         *
         * Until dedicated dunk art lands, CourtView deliberately reuses Maya's directional BLOCK
         * sprite as the temporary high-arm dunk pose.
         */
        if botFinish == TripleShotCourtView.OneOnOneDriveFinish.DUNK {
            courtView.animateOneOnOneBotDunk { [weak self] result in
                self?.handleBotAttemptFinished(serial: serial, zone: zone, result: result)
            }
            return
        }

        if botFinish == TripleShotCourtView.OneOnOneDriveFinish.JUMPER {
            courtView.beginOneOnOneBotContestedJumperIfNeeded()
        }

        let plan = botBrain.prepareTurn(
            question: Self.BOT_DUMMY_QUESTION,
            shotZone: zone,
            answerPlan: TripleShotBotOpponent.AnswerPlan(selectedAnswerIndex: 0, answerQualityPercent: 100)
        )
        let botChance = calculateBotShotChance(zone: zone, finish: botFinish)
        let botSkill = chanceDrivenSkill(
            baseSkill: plan.skill,
            chancePercent: botChance,
            sequence: serial,
            salt: Self.BOT_SHOT_ROLL_SALT,
            zone: zone,
            finish: botFinish
        )

        courtView.animateBotShot(
            skill: botSkill,
            pullBackAtRelease: plan.pullBack,
            hot: false,
            oneOnOneFinish: botFinish
        ) { [weak self] result in
            self?.handleBotAttemptFinished(serial: serial, zone: zone, result: result)
        }
    }

    func handleBotAttemptFinished(
        serial: Int64,
        zone: ShotZone,
        result: TripleShotCourtView.ShotResult
    ) {
        if !isAdded || ended || serial != botPossessionSerial { return }
        shotInProgress = false

        if result.outcome.made {
            botConsecutiveMisses = 0
            botScore += pointsFor(zone: zone)
            reboundActive = false
            statusText.text = getString(
                genderedBotString(
                    maleRes: R.string.minik_swish_one_on_one_made_male,
                    femaleRes: R.string.minik_swish_one_on_one_made_female,
                    neutralRes: R.string.minik_swish_one_on_one_made_neutral
                ),
                botProfile.displayName,
                pointsFor(zone: zone)
            )
            updateHud()
            flashBotScore()

            if checkWinner() { return }
            phase = Phase.CHECK_BALL
            beginPossessionQuestion(
                fallbackHumanGetsBall: true,
                reasonText: getString(R.string.minik_swish_one_on_one_question_after_score)
            )
            return
        }

        botConsecutiveMisses += 1
        humanHasBall = false
        reboundActive = true
        phase = Phase.REBOUND
        if courtView.wasLastOneOnOneBotShotBlockedByHuman() {
            statusText.text = getString(R.string.minik_swish_one_on_one_block_success)
        } else {
            statusText.text = getString(
                genderedBotString(
                    maleRes: R.string.minik_swish_one_on_one_missed_rebound_male,
                    femaleRes: R.string.minik_swish_one_on_one_missed_rebound_female,
                    neutralRes: R.string.minik_swish_one_on_one_missed_rebound_neutral
                ),
                botProfile.displayName
            )
        }
        updateHud()
    }

    // MARK: - Human possession (L2569-2602)

    func takeHumanPossession(
        showMessage: Bool,
        resetCheck: Bool = false
    ) {
        hideShotMeter()
        resetTouchPointerState()
        if ended { return }
        botPossessionSerial += 1
        stopBotAttack()
        if resetCheck {
            courtView.resetOneOnOneCheckPositions(humanOffense: true, animate: true)
        }
        humanHasBall = true
        reboundActive = false
        humanDribblePickedUp = false
        heldReleaseCommitted = false
        heldFinish = TripleShotCourtView.OneOnOneDriveFinish.JUMPER
        if let r = pendingHeldSingleTap { handler.removeCallbacks(r) }
        pendingHeldSingleTap = nil
        holdPoseGeneration += 1
        courtView.setOneOnOneHumanHeldMotion(high: nil)
        courtView.setOneOnOneBotContestAllowed(allowed: true)
        aiming = false
        quickShotActive = false
        quickShotGeneration += 1
        quickShotStartedAtNanos = 0
        quickFinish = TripleShotCourtView.OneOnOneDriveFinish.JUMPER
        shotInProgress = false
        phase = Phase.LIVE_OFFENSE
        sensor.prepareForMovement()
        courtView.oneOnOneGiveBallToHuman()
        if showMessage { statusText.setText(res: R.string.minik_swish_one_on_one_your_ball) }
        updateHud()
    }

    // MARK: - Possession-question race (L2604-3027)

    func beginPossessionQuestion(
        fallbackHumanGetsBall: Bool,
        reasonText: String
    ) {
        resetTouchPointerState()
        hideShotMeter()
        stopBotAttack()
        if let r = botQuestionRunnable { handler.removeCallbacks(r) }
        botQuestionRunnable = nil
        courtView.oneOnOneClearPossessionForQuestion()
        humanHasBall = false
        reboundActive = false
        humanDribblePickedUp = false
        heldReleaseCommitted = false
        heldFinish = TripleShotCourtView.OneOnOneDriveFinish.JUMPER
        if let r = pendingHeldSingleTap { handler.removeCallbacks(r) }
        pendingHeldSingleTap = nil
        holdPoseGeneration += 1
        courtView.setOneOnOneHumanHeldMotion(high: nil)
        aiming = false
        shotInProgress = false
        checkTransitionActive = false
        phase = Phase.CHECK_BALL

        if possessionQuestions.isEmpty {
            resolvePossessionQuestionWinner(humanWins: fallbackHumanGetsBall)
            return
        }

        possessionQuestionActive = true
        possessionQuestionRound += 1
        questionTitle.text = reasonText
        questionCard.visibility = AView.VISIBLE
        showNextPossessionQuestion()
        updateHud()
    }

    func currentPossessionQuestion() -> TripleShotQuestion? {
        if possessionQuestions.isEmpty || possessionQuestionIndex <= 0 { return nil }
        return possessionQuestions[(possessionQuestionIndex - 1) % possessionQuestions.size]
    }

    func showNextPossessionQuestion() {
        if !possessionQuestionActive || possessionQuestions.isEmpty { return }

        let question = possessionQuestions[possessionQuestionIndex % possessionQuestions.size]
        possessionQuestionIndex += 1
        humanWrongOnCurrentQuestion = false
        botWrongOnCurrentQuestion = false
        humanAnsweredCurrentQuestion = false
        botAnsweredCurrentQuestion = false
        botCorrectOnCurrentQuestion = false
        possessionQuestionWinnerHuman = nil
        pendingQuestionWinnerHuman = nil
        pendingQuestionNeedsAnother = false
        questionContinueButton.visibility = AView.GONE
        questionPrompt.text = bidiSafeQuestionPrompt(raw: question.prompt)
        questionFeedback.setText(res: R.string.minik_swish_one_on_one_question_first_correct)
        resetQuestionAnswerStyles(question: question)

        if let r = botQuestionRunnable { handler.removeCallbacks(r) }
        botQuestionRunnable = nil
        botQuestionAttemptNumber = 0
        botQuestionWrongAnswerIndices.removeAll()
        botQuestionShownAtElapsedMs = ASystemClock.elapsedRealtime()

        /*
         * The bot gets a believable private thinking window, not an all-or-nothing single roll.
         * A weak/guessy bot may submit a wrong answer first and think again. A hard upper deadline
         * guarantees that walking away for minutes can never come back as "I still answered first".
         * None of these private attempts are shown before the human commits.
         */
        // Kotlin `Random(seed xor round * SALT xor id.hashCode().toLong())` (Java String hash, sign-extended).
        let deadlineRandom =
            KotlinRandom(
                seed: seed ^ (possessionQuestionRound &* Self.QUESTION_RESPONSE_SEED_SALT) ^
                    question.id.javaHashCode.toLong()
            )
        botQuestionHardDeadlineMs = botQuestionCorrectDeadlineMs(random: deadlineRandom)
        scheduleBotQuestionAttempt(question: question, token: possessionQuestionRound)
    }

    func scheduleBotQuestionAttempt(
        question: TripleShotQuestion,
        token: Int64
    ) {
        if !possessionQuestionActive || token != possessionQuestionRound { return }

        if let r = botQuestionRunnable { handler.removeCallbacks(r) }
        let attempt = botQuestionAttemptNumber
        // Kotlin `seed xor token * SALT xor id.hashCode().toLong() xor (attempt + 1L) * ATTEMPT_SALT`.
        let responseRandom =
            KotlinRandom(
                seed: seed ^
                    (token &* Self.QUESTION_RESPONSE_SEED_SALT) ^
                    question.id.javaHashCode.toLong() ^
                    ((attempt.toLong() &+ 1) &* Self.BOT_QUESTION_ATTEMPT_SEED_SALT)
            )
        let botAnswerIndex =
            chooseBotQuizAnswerIndex(
                question: question,
                random: responseRandom,
                excludedIndices: botQuestionWrongAnswerIndices
            )
        let delayMs: Int64 =
            attempt == 0 ? botQuizDelayMs(random: responseRandom)
            : botQuizRetryDelayMs(random: responseRandom, attempt: attempt)

        let runnable = ARunnable { [weak self] in
            guard let self = self else { return }
            if !self.isAdded || self.ended || !self.possessionQuestionActive || token != self.possessionQuestionRound {
                return
            }
            self.botQuestionRunnable = nil
            self.botQuestionAttemptNumber += 1
            self.botAnsweredCurrentQuestion = true

            let answer = question.answers.getOrNull(botAnswerIndex)
            let best = question.answers.kMaxOf { $0.qualityPercent }
            let correct = answer != nil && answer!.qualityPercent == best

            if correct {
                self.botCorrectOnCurrentQuestion = true
                self.botWrongOnCurrentQuestion = false
                if self.possessionQuestionWinnerHuman == nil { self.possessionQuestionWinnerHuman = false }

                // Hidden race: Maya's result is revealed only after the human answers.
                if !self.humanAnsweredCurrentQuestion { return }

                self.questionFeedback.text = self.getString(
                    self.genderedBotString(
                        maleRes: R.string.minik_swish_one_on_one_question_you_wrong_bot_wins_male,
                        femaleRes: R.string.minik_swish_one_on_one_question_you_wrong_bot_wins_female,
                        neutralRes: R.string.minik_swish_one_on_one_question_you_wrong_bot_wins_neutral
                    ),
                    self.bidiSafeName(raw: self.botProfile.displayName)
                )
                self.revealQuestionAnswer(question: question)
                self.finishQuestionAfterLearningPause(humanWins: false, token: token)
                return
            }

            self.botWrongOnCurrentQuestion = true
            self.botQuestionWrongAnswerIndices.insert(botAnswerIndex)

            if !self.humanAnsweredCurrentQuestion {
                // Do not freeze forever after one bad guess. Maya thinks again privately. Excluding
                // already-tried wrong options keeps retries believable and bounds the race naturally.
                self.scheduleBotQuestionAttempt(question: question, token: token)
                return
            }

            // The human has also committed and both are currently wrong: move to another question.
            self.questionFeedback.setText(res: R.string.minik_swish_one_on_one_question_both_wrong)
            self.revealQuestionAnswer(question: question)
            self.offerAnotherQuestion(token: token)
        }

        botQuestionRunnable = runnable
        handler.postDelayed(runnable, delayMs)
    }

    func forceBotRaceResolutionIfDeadlinePassed() {
        if botCorrectOnCurrentQuestion || possessionQuestionWinnerHuman != nil ||
            botQuestionShownAtElapsedMs == 0 || botQuestionHardDeadlineMs <= 0 { return }

        let elapsedMs = ASystemClock.elapsedRealtime() - botQuestionShownAtElapsedMs
        if elapsedMs < botQuestionHardDeadlineMs { return }

        // This is intentionally silent. It only resolves who was first before the human's answer
        // is evaluated. The UI still reveals nothing about Maya until the user commits.
        if let r = botQuestionRunnable { handler.removeCallbacks(r) }
        botQuestionRunnable = nil
        botAnsweredCurrentQuestion = true
        botCorrectOnCurrentQuestion = true
        botWrongOnCurrentQuestion = false
        possessionQuestionWinnerHuman = false
    }

    func submitHumanPossessionAnswer(index: Int) {
        if !possessionQuestionActive || possessionQuestions.isEmpty || humanAnsweredCurrentQuestion { return }
        guard let question = currentPossessionQuestion() else { return }
        // If the app was backgrounded/suspended, delayed Handler callbacks may not have had a
        // chance to run. Resolve the private race from elapsed real time before judging the tap.
        forceBotRaceResolutionIfDeadlinePassed()
        guard let answer = question.answers.getOrNull(index) else { return }
        let best = question.answers.kMaxOf { $0.qualityPercent }
        let humanCorrect = answer.qualityPercent == best
        let correctAnswer = question.answers.kMaxBy { $0.qualityPercent }?.text ?? ""

        // Kotlin skips the two records only for `BuildConfig.DEBUG && intent "qaIsolatedProgress"` (debug QA isolation,
        // not ported, DESIGN 3): a release build always records.
        TripleShotQuestionRepository.recordAnswer(
            questionId: question.id,
            selectedAnswerIndex: index,
            responseTimeMs: ASystemClock.elapsedRealtime() - botQuestionShownAtElapsedMs
        )

        firebase.recordKnowledgeAnswer(
            playerName: playerName,
            category: question.category,
            correct: humanCorrect,
            questionId: question.id,
            prompt: question.prompt,
            selectedAnswer: answer.text,
            correctAnswer: correctAnswer,
            qualityPercent: answer.qualityPercent,
            gameType: GameType.ONE_ON_ONE.name
        ) { _ in /* Learning history must never interrupt the match. */ }
        humanAnsweredCurrentQuestion = true
        humanWrongOnCurrentQuestion = !humanCorrect
        questionButtons.forEach { $0.isEnabled = true; $0.isClickable = false }
        revealQuestionAnswer(question: question, selectedIndex: index)

        let token = possessionQuestionRound
        if humanCorrect && possessionQuestionWinnerHuman == nil {
            possessionQuestionWinnerHuman = true
            if let r = botQuestionRunnable { handler.removeCallbacks(r) }
            botQuestionRunnable = nil
            questionFeedback.setText(res: R.string.minik_swish_one_on_one_question_you_first)
            finishQuestionAfterLearningPause(humanWins: true, token: token)
        } else if humanCorrect && possessionQuestionWinnerHuman == false {
            questionFeedback.text = getString(
                genderedBotString(
                    maleRes: R.string.minik_swish_one_on_one_question_you_correct_bot_faster_male,
                    femaleRes: R.string.minik_swish_one_on_one_question_you_correct_bot_faster_female,
                    neutralRes: R.string.minik_swish_one_on_one_question_you_correct_bot_faster_neutral
                ),
                bidiSafeName(raw: botProfile.displayName)
            )
            finishQuestionAfterLearningPause(humanWins: false, token: token)
        } else if !humanCorrect && botCorrectOnCurrentQuestion {
            questionFeedback.text = getString(
                genderedBotString(
                    maleRes: R.string.minik_swish_one_on_one_question_you_wrong_bot_wins_male,
                    femaleRes: R.string.minik_swish_one_on_one_question_you_wrong_bot_wins_female,
                    neutralRes: R.string.minik_swish_one_on_one_question_you_wrong_bot_wins_neutral
                ),
                bidiSafeName(raw: botProfile.displayName)
            )
            finishQuestionAfterLearningPause(humanWins: false, token: token)
        } else if !humanCorrect && botWrongOnCurrentQuestion {
            questionFeedback.setText(res: R.string.minik_swish_one_on_one_question_both_wrong)
            offerAnotherQuestion(token: token)
        } else {
            // Human was wrong but the bot has not answered yet. Keep the correct answer visible
            // and wait for the bot result instead of abruptly replacing the learning card.
            questionFeedback.setText(res: R.string.minik_swish_one_on_one_question_you_wrong_wait_bot)
        }
    }

    func resetQuestionAnswerStyles(question: TripleShotQuestion) {
        for (index, button) in questionButtons.enumerated() {
            let answer = question.answers.getOrNull(index)
            button.visibility = answer == nil ? AView.GONE : AView.VISIBLE
            button.isEnabled = answer != nil
            button.isClickable = answer != nil
            button.isFocusable = false
            button.isSelected = false
            button.isActivated = false
            button.isPressed = false
            button.setAlpha(1)
            button.backgroundTintList = AColorStateList.valueOf(AColor.argb(238, 255, 255, 255))
            button.strokeColor = AColorStateList.valueOf(AColor.rgb(104, 178, 170))
            button.setTextColor(AColor.rgb(26, 45, 49))
            if let answer = answer { button.text = answer.text }
        }
    }

    func revealQuestionAnswer(question: TripleShotQuestion, selectedIndex: Int? = nil) {
        // `question.answers.maxOfOrNull { it.qualityPercent } ?: return`
        if question.answers.isEmpty { return }
        let best = question.answers.kMaxOf { $0.qualityPercent }
        for (index, button) in questionButtons.enumerated() {
            guard let answer = question.answers.getOrNull(index) else { continue }
            let correct = answer.qualityPercent == best
            if correct {
                button.backgroundTintList = AColorStateList.valueOf(AColor.rgb(107, 220, 145))
                button.strokeColor = AColorStateList.valueOf(AColor.rgb(32, 153, 82))
                button.setTextColor(AColor.rgb(20, 92, 48))
                // Kotlin `startsWith("✓ ")` compares UTF-16 units.
                if !button.text.utf16.starts(with: Self.ONE2_CHECK_MARK_PREFIX.utf16) {
                    button.text = Self.ONE2_CHECK_MARK_PREFIX + button.text
                }
            } else if selectedIndex == index {
                button.backgroundTintList = AColorStateList.valueOf(AColor.rgb(255, 145, 159))
                button.strokeColor = AColorStateList.valueOf(AColor.rgb(190, 70, 70))
                button.setTextColor(AColor.rgb(135, 42, 42))
            } else {
                button.setAlpha(Float(0.62))
            }
        }
    }

    func finishQuestionAfterLearningPause(humanWins: Bool, token: Int64) {
        if !isAdded || ended || !possessionQuestionActive || token != possessionQuestionRound { return }
        if let r = botQuestionRunnable { handler.removeCallbacks(r) }
        botQuestionRunnable = nil
        pendingQuestionWinnerHuman = humanWins
        pendingQuestionNeedsAnother = false
        questionContinueButton.setText(res: R.string.minik_swish_one_on_one_question_continue)
        questionContinueButton.visibility = AView.VISIBLE
    }

    func offerAnotherQuestion(token: Int64) {
        if !isAdded || ended || !possessionQuestionActive || token != possessionQuestionRound { return }
        pendingQuestionWinnerHuman = nil
        pendingQuestionNeedsAnother = true
        questionContinueButton.setText(res: R.string.minik_swish_one_on_one_question_next)
        questionContinueButton.visibility = AView.VISIBLE
    }

    func continueAfterPossessionQuestion() {
        if !possessionQuestionActive { return }
        questionContinueButton.visibility = AView.GONE
        if pendingQuestionNeedsAnother {
            pendingQuestionNeedsAnother = false
            possessionQuestionRound += 1
            showNextPossessionQuestion()
            return
        }
        guard let winner = pendingQuestionWinnerHuman else { return }
        pendingQuestionWinnerHuman = nil
        resolvePossessionQuestionWinner(humanWins: winner)
    }

    /**
     * Knowledge, speed and guessiness are deliberately separate. A fast guesser may beat the
     * player to an answer but be wrong often; a careful expert may answer correctly but slowly.
     */
    func chooseBotQuizAnswerIndex(
        question: TripleShotQuestion,
        random: KotlinRandom,
        excludedIndices: Set<Int> = []
    ) -> Int {
        if question.answers.isEmpty { return 0 }
        let best = question.answers.kMaxOf { $0.qualityPercent }
        let correctIndices =
            question.answers.indices.filter {
                question.answers[$0].qualityPercent == best && !excludedIndices.contains($0)
            }
        let incorrectIndices =
            question.answers.indices.filter {
                question.answers[$0].qualityPercent != best && !excludedIndices.contains($0)
            }
        let available = question.answers.indices.filter { !excludedIndices.contains($0) }

        // If every wrong option has already been privately tried, Maya eventually resolves the
        // question instead of freezing the possession forever.
        if incorrectIndices.isEmpty && !correctIndices.isEmpty {
            return correctIndices.kRandom(random)
        }
        if available.isEmpty { return question.answers.indices.first! }

        let quiz = botProfile.quiz
        let guessing = random.nextInt(100) < quiz.guessiness
        if guessing { return available.kRandom(random) }

        let knows = random.nextInt(100) < quiz.knowledge
        if knows && !correctIndices.isEmpty {
            return correctIndices.kRandom(random)
        } else if !incorrectIndices.isEmpty {
            return incorrectIndices.kRandom(random)
        } else {
            return available.kRandom(random)
        }
    }

    func botQuizDelayMs(random: KotlinRandom) -> Int64 {
        let speed01 = botProfile.quiz.responseSpeed.coerceIn(0, 100).toFloat() / Float(100)
        let center =
            Self.BOT_QUESTION_SLOW_MS -
                ((Self.BOT_QUESTION_SLOW_MS - Self.BOT_QUESTION_FAST_MS).toFloat() * speed01).toLong()
        let jitter = random.nextLong(-Self.BOT_QUESTION_JITTER_MS, Self.BOT_QUESTION_JITTER_MS + 1)
        return (center + jitter).coerceIn(Self.BOT_QUESTION_MIN_ABSOLUTE_MS, Self.BOT_QUESTION_MAX_ABSOLUTE_MS)
    }

    func botQuizRetryDelayMs(random: KotlinRandom, attempt: Int) -> Int64 {
        let speed01 = botProfile.quiz.responseSpeed.coerceIn(0, 100).toFloat() / Float(100)
        let base =
            Self.BOT_QUESTION_RETRY_SLOW_MS -
                ((Self.BOT_QUESTION_RETRY_SLOW_MS - Self.BOT_QUESTION_RETRY_FAST_MS).toFloat() * speed01).toLong()
        let thinkingPenalty = attempt.coerceAtMost(3).toLong() * 140
        let jitter = random.nextLong(-Self.BOT_QUESTION_RETRY_JITTER_MS, Self.BOT_QUESTION_RETRY_JITTER_MS + 1)
        return (base + thinkingPenalty + jitter)
            .coerceIn(Self.BOT_QUESTION_RETRY_MIN_MS, Self.BOT_QUESTION_RETRY_MAX_MS)
    }

    func botQuestionCorrectDeadlineMs(random: KotlinRandom) -> Int64 {
        let speed01 = botProfile.quiz.responseSpeed.coerceIn(0, 100).toFloat() / Float(100)
        let knowledge01 = botProfile.quiz.knowledge.coerceIn(0, 100).toFloat() / Float(100)
        // Kotlin `Long * Float` and `Float * Long` are Float products, truncated by toLong().
        let center =
            Self.BOT_QUESTION_DEADLINE_SLOW_MS -
                ((Self.BOT_QUESTION_DEADLINE_SLOW_MS - Self.BOT_QUESTION_DEADLINE_FAST_MS).toFloat() * speed01)
                    .toLong() -
                (knowledge01 * Self.BOT_QUESTION_DEADLINE_KNOWLEDGE_BONUS_MS.toFloat()).toLong()
        let jitter =
            random.nextLong(-Self.BOT_QUESTION_DEADLINE_JITTER_MS, Self.BOT_QUESTION_DEADLINE_JITTER_MS + 1)
        return (center + jitter)
            .coerceIn(Self.BOT_QUESTION_DEADLINE_MIN_MS, Self.BOT_QUESTION_DEADLINE_MAX_MS)
    }

    func resolvePossessionQuestionWinner(humanWins: Bool) {
        if let r = botQuestionRunnable { handler.removeCallbacks(r) }
        botQuestionRunnable = nil
        questionCard.visibility = AView.GONE
        possessionQuestionActive = false
        checkTransitionActive = true
        phase = Phase.CHECK_BALL
        updateHud()

        // Do not give the winner a free first step while the defender is still travelling from the
        // question overlay. Play resumes only after both characters are back at a normal check.
        courtView.resetOneOnOneCheckPositions(humanOffense: humanWins, animate: true) { [weak self] in
            guard let self = self else { return }
            if !self.isAdded || self.ended { return }
            self.checkTransitionActive = false
            if humanWins {
                self.takeHumanPossession(showMessage: true, resetCheck: false)
            } else {
                self.courtView.oneOnOneGiveBallToBot()
                self.scheduleBotPossession(alreadyHasBall: true, resetCheck: false)
            }
            self.updateHud()
        }
    }

    // MARK: - Bidi and gendered strings (L3029-3078)

    func isRtlUi() -> Bool {
        // `(ConfigurationCompat.getLocales(resources.configuration)[0] ?: Locale.getDefault()).language.orEmpty()`
        let language =
            (AConfigurationCompat.getLocales(resources.configuration)[0] ?? ALocale.getDefault()).language
        return language == "he" || language == "iw" || language == "ar"
    }

    /**
     * Keep an English/Latin character name stable inside an RTL sentence without renaming the
     * actual roster identity. LRI/PDI are invisible Unicode direction isolates.
     */
    func bidiSafeName(raw: String) -> String {
        // `raw.any { it in 'A'..'Z' || it in 'a'..'z' }` over UTF-16 units.
        if isRtlUi() && raw.utf16.contains(where: { ($0 >= 0x41 && $0 <= 0x5A) || ($0 >= 0x61 && $0 <= 0x7A) }) {
            return Self.ONE2_LRI + raw + Self.ONE2_PDI
        } else {
            return raw
        }
    }

    /**
     * Android's bidi algorithm can visually reverse "15 - 8" inside a Hebrew sentence even when
     * the repository string is correct. Isolate arithmetic runs as LTR while leaving Hebrew RTL.
     */
    func bidiSafeQuestionPrompt(raw: String) -> String {
        if !isRtlUi() { return raw }
        let arithmetic = One2Regex(Self.ONE2_ARITHMETIC_PATTERN)
        return arithmetic.replace(raw) { match in Self.ONE2_LRI + match + Self.ONE2_PDI }
    }

    func formatBotScoreText(name: String, score: Int) -> String {
        if isRtlUi() {
            return Self.ONE2_LRI + name + " \u{00B7} " + String(score) + Self.ONE2_PDI
        } else {
            return name + " \u{00B7} " + String(score)
        }
    }

    /// Kotlin `neutralRes: Int = maleRes`: nil stands for "not passed" (a Swift default cannot read another parameter).
    func genderedCharacterString(
        profile: TripleShotCharacterProfile,
        maleRes: AStringRes,
        femaleRes: AStringRes,
        neutralRes: AStringRes? = nil
    ) -> AStringRes {
        switch profile.gender {
        case .MALE: return maleRes
        case .FEMALE: return femaleRes
        case .NEUTRAL: return neutralRes ?? maleRes
        }
    }

    func genderedBotString(
        maleRes: AStringRes,
        femaleRes: AStringRes,
        neutralRes: AStringRes? = nil
    ) -> AStringRes {
        return genderedCharacterString(
            profile: botProfile,
            maleRes: maleRes,
            femaleRes: femaleRes,
            neutralRes: neutralRes ?? maleRes
        )
    }

    // MARK: - HUD (L3080-3152)

    func updateHud() {
        humanScoreText.text = getString(
            R.string.minik_swish_one_on_one_score_you,
            humanScore
        )
        botScoreText.text = formatBotScoreText(name: botProfile.displayName, score: botScore)
        if possessionQuestionActive {
            possessionText.text = getString(R.string.minik_swish_one_on_one_possession_question)
        } else if checkTransitionActive {
            possessionText.text = getString(R.string.minik_swish_one_on_one_possession_check)
        } else if phase == Phase.DEAD_BALL {
            possessionText.text = getString(R.string.minik_swish_one_on_one_possession_dead)
        } else if reboundActive {
            possessionText.text = getString(R.string.minik_swish_one_on_one_possession_loose)
        } else if humanHasBall {
            possessionText.text = getString(R.string.minik_swish_one_on_one_possession_you)
        } else {
            possessionText.text = getString(
                R.string.minik_swish_one_on_one_possession_bot,
                bidiSafeName(raw: botProfile.displayName)
            )
        }
        updateControls()
    }

    func updateControls() {
        if ended { return }

        /*
         * V20.3 is fully gesture-driven on court:
         * - offense: drag + tap; a second tap during gather = pump fake
         * - defense: tap = steal / block / rebound depending on the live ball state
         *
         * Keep the legacy views only as harmless compatibility ids; they never occupy screen space.
         */
        shootButton.visibility = AView.GONE
        fakeButton.visibility = AView.GONE
        blockButton.visibility = AView.GONE
        jumpButton.visibility = AView.GONE
        controlsCard.visibility = AView.GONE
    }

    func flashHumanScore() {
        if humanScoreText == nil { return }
        humanScoreText.animate().cancel()
        humanScoreText.setTextColor(AColor.rgb(20, 154, 83))
        humanScoreText.scaleX = Float(1.12)
        humanScoreText.scaleY = Float(1.12)
        humanScoreText.animate()
            .scaleX(1)
            .scaleY(1)
            .setDuration(360)
            .withEndAction { [weak self] in
                guard let self = self else { return }
                if self.isAdded && self.humanScoreText != nil {
                    self.humanScoreText.setTextColor(AColor.rgb(20, 33, 41))
                }
            }
            .start()
    }

    func flashBotScore() {
        if botScoreText == nil { return }
        botScoreText.animate().cancel()
        botScoreText.setTextColor(AColor.rgb(20, 154, 83))
        botScoreText.scaleX = Float(1.12)
        botScoreText.scaleY = Float(1.12)
        botScoreText.animate()
            .scaleX(1)
            .scaleY(1)
            .setDuration(360)
            .withEndAction { [weak self] in
                guard let self = self else { return }
                if self.isAdded && self.botScoreText != nil {
                    self.botScoreText.setTextColor(AColor.rgb(20, 33, 41))
                }
            }
            .start()
    }

    /// Kotlin `getString(R.string.minik_swish_one_on_one_question_after_out).also { BasketballSoundscape.effect(..., WHISTLE) }`:
    /// the text is read first, then the whistle plays, before beginPossessionQuestion runs.
    func questionAfterOutReason() -> String {
        let text = getString(R.string.minik_swish_one_on_one_question_after_out)
        BasketballSoundscape.effect(context: requireContext(), kind: BasketballSoundscape.Effect.WHISTLE)
        return text
    }

    // MARK: - Match end (L3154-3248)

    func checkWinner() -> Bool {
        let winnerOrNull: TripleShotCharacterProfile?
        if humanScore >= Self.SCORE_TO_WIN {
            winnerOrNull = humanProfile
        } else if botScore >= Self.SCORE_TO_WIN {
            winnerOrNull = botProfile
        } else {
            winnerOrNull = nil
        }
        guard let winner = winnerOrNull else { return false }

        hideShotMeter()
        BasketballSoundscape.result(activity: requireActivity(), won: humanScore >= Self.SCORE_TO_WIN, gap: abs(humanScore - botScore))
        ended = true
        phase = Phase.GAME_OVER
        aiming = false
        shotInProgress = false
        stopBotAttack()
        handler.removeCallbacksAndMessages(nil)
        sensor.cancelShot()
        stopSensorIfRunning()
        if humanScore >= Self.SCORE_TO_WIN {
            resultTitle.text = getString(R.string.minik_swish_one_on_one_you_win)
        } else {
            resultTitle.text = getString(
                genderedBotString(
                    maleRes: R.string.minik_swish_one_on_one_bot_wins_male,
                    femaleRes: R.string.minik_swish_one_on_one_bot_wins_female,
                    neutralRes: R.string.minik_swish_one_on_one_bot_wins_neutral
                ),
                winner.displayName
            )
        }
        resultScore.text = getString(
            R.string.minik_swish_one_on_one_final_score,
            humanScore,
            botScore
        )
        if let card = (resultOverlay as? AViewGroup)?.getChildAt(0) {
            if let card = card as? ACardView {
                card.strokeWidth = dp(value: 2).toInt()
                card.strokeColor = AColor.parseColor(humanScore >= Self.SCORE_TO_WIN ? "#3F8CFF" : "#E91E63")
                let wide = resources.configuration.orientation == AConfiguration.ORIENTATION_LANDSCAPE
                let lp = card.layoutParams!
                lp.width = min(dp(value: wide ? 500 : 340).toInt(),
                               resources.displayMetrics.widthPixels - dp(value: wide ? 52 : 72).toInt())
                card.layoutParams = lp
            }
        }
        // Kotlin `findViewById<TripleShotButton>(...)?.apply { ... }`: the landscape layout's home button is a plain
        // MaterialButton, where Android's implied cast throws ClassCastException; here the typed lookup yields nil
        // and the button keeps its layout style.
        if let home: TripleShotButton = view?.findViewById(R.id.oneOnOneHomeButton) {
            home.backgroundTintList = AColorStateList.valueOf(AColor.parseColor("#E91E63")); home.setTextColor(AColor.WHITE)
        }
        resultOverlay.visibility = AView.VISIBLE
        return true
    }

    func restartMatch() {
        BasketballSoundscape.scene(activity: requireActivity(), value: BasketballSoundscape.Scene.COURT)
        BasketballSoundscape.effect(context: requireContext(), kind: BasketballSoundscape.Effect.WHISTLE)
        hideShotMeter()
        humanScore = 0
        botScore = 0
        botShotSearchAttempts = 0
        botConsecutiveMisses = 0
        ended = false
        phase = Phase.CHECK_BALL
        aiming = false
        shotInProgress = false
        reboundActive = false
        stopBotAttack()
        if let r = botQuestionRunnable { handler.removeCallbacks(r) }
        botQuestionRunnable = nil
        possessionQuestionActive = false
        checkTransitionActive = false
        if questionCard != nil { questionCard.visibility = AView.GONE }
        resultOverlay.visibility = AView.GONE
        seed = ASystem.currentTimeMillis()
        courtView.setOneOnOneEnabled(
            enabled: true,
            seed: seed,
            botLabel: botProfile.displayName,
            botBlockRating: effectiveBlock(profile: botProfile),
            humanBlockRating: effectiveBlock(profile: humanProfile),
            botStealRating: botProfile.ratings.stealing,
            humanStealRating: humanProfile.ratings.stealing,
            botStrengthRating: botProfile.ratings.strength,
            humanStrengthRating: humanProfile.ratings.strength,
            botSpeedRating: botProfile.ratings.speed,
            humanSpeedRating: humanProfile.ratings.speed,
            botHeightRating: botProfile.ratings.height,
            humanHeightRating: humanProfile.ratings.height,
            botBallHandlingRating: botProfile.ratings.ballHandling,
            humanBallHandlingRating: humanProfile.ratings.ballHandling,
            botDefenseRating: botProfile.ratings.defense,
            humanDefenseRating: humanProfile.ratings.defense,
            botAgilityRating: botProfile.ratings.agility,
            humanAgilityRating: humanProfile.ratings.agility,
            botOffenseRating: botProfile.ratings.offense,
            humanOffenseRating: humanProfile.ratings.offense,
            botWeightRating: botProfile.ratings.weight,
            humanWeightRating: humanProfile.ratings.weight,
            botJumpRating: botProfile.ratings.jumping,
            humanJumpRating: humanProfile.ratings.jumping
        )
        syncSensorForControlMode()
        takeHumanPossession(showMessage: true)
    }

    func leaveToHome() {
        ended = true
        phase = Phase.GAME_OVER
        stopBotAttack()
        handler.removeCallbacksAndMessages(nil)
        (parentFragment as? TripleShotHostFragment)?.backToHome()
    }

    // MARK: - Rating helpers (L3250-3303)

    func pointsFor(zone: ShotZone) -> Int {
        return zone == ShotZone.THREE_POINT ? 3 : 2
    }

    func effectiveDunkAbility(profile: TripleShotCharacterProfile) -> Int {
        // `(dunking * 0.70f + jumping * 0.20f + height * 0.10f).toInt().coerceIn(0, 100)`, Float, left to right.
        var ability = profile.ratings.dunking.toFloat() * Float(0.70)
        ability = ability + profile.ratings.jumping.toFloat() * Float(0.20)
        ability = ability + profile.ratings.height.toFloat() * Float(0.10)
        return ability
            .toInt()
            .coerceIn(0, 100)
    }

    func effectiveBlock(profile: TripleShotCharacterProfile) -> Int {
        // `(blocking * 0.60f + height * 0.22f + jumping * 0.18f).toInt().coerceIn(0, 100)`, Float, left to right.
        var block = profile.ratings.blocking.toFloat() * Float(0.60)
        block = block + profile.ratings.height.toFloat() * Float(0.22)
        block = block + profile.ratings.jumping.toFloat() * Float(0.18)
        return block
            .toInt()
            .coerceIn(0, 100)
    }

    // L3271-3301 applyHumanShootingRating: no caller (the old rating-scaled error model), not ported.

    func dp(value: Float) -> Float {
        return value * resources.displayMetrics.density
    }

    // MARK: - Companion object (L3305-3466)

    static let ARG_PLAYER_NAME = "one_on_one_player_name"
    static let ARG_HUMAN_CHARACTER_ID = "one_on_one_human_character"
    static let ARG_BOT_CHARACTER_ID = "one_on_one_bot_character"
    static let ARG_GAME_ORIENTATION = "one_on_one_game_orientation"
    static let ARG_COURT_ID = "one_on_one_court_id"
    static let ARG_SEED = "one_on_one_seed"
    static let ARG_CATEGORIES = "one_on_one_categories"

    static let SCORE_TO_WIN = 11
    static let POSSESSION_HANDOFF_MS: Int64 = 560
    static let BOT_POSSESSION_SETTLE_MS: Int64 = 520
    static let BOT_DECISION_PAUSE_MS: Int64 = 330
    static let BOT_ATTACK_TICK_MS: Int64 = 48
    static let BOT_OPEN_LANE_MAX_ATTACK_MS: Int64 = 4200
    static let DEAD_BALL_RESET_MS: Int64 = 620
    static let BOT_BRAIN_SEED_SALT: Int64 = 0x314F4E31424F544C
    static let BOT_ATTACK_SEED_SALT: Int64 = 0x314F4E314154544B

    static let CROSSOVER_GESTURE_WINDOW_MS: Int64 = 620
    static let CROSSOVER_MIN_SEGMENT_DP: Float = 7
    static let CROSSOVER_REQUIRED_CHANGES = 2
    static let HESITATION_GESTURE_WINDOW_MS: Int64 = 620
    static let HESITATION_MIN_SEGMENT_DP: Float = 7

    static let PUMP_FAKE_ARM_PULL: Float = 0.36
    static let PUMP_FAKE_RETURN_PULL: Float = 0.13
    static let PUMP_FAKE_MIN_GAP_MS: Int64 = 280

    static let HOLD_VISUAL_LOW_PULL: Float = 0.02
    static let HOLD_VISUAL_MID_PULL_START: Float = 0.10
    static let HOLD_VISUAL_MID_PULL_END: Float = 0.43
    static let HOLD_VISUAL_SET_PULL_START: Float = 0.52
    static let HOLD_VISUAL_SET_PULL_END: Float = 0.72
    static let HELD_DOUBLE_TAP_MAX_GAP_MS: Int64 = 280
    static let HELD_SINGLE_TAP_DELAY_MS: Int64 = 245
    static let HOLD_FAKE_SET_PULL: Float = 0.72
    static let HOLD_FAKE_UP_MS: Int64 = 145
    static let HOLD_RELEASE_MID_PULL: Float = 0.48
    static let HOLD_RELEASE_SET_PULL: Float = 0.76
    static let HOLD_RELEASE_SET_AT_MS: Int64 = 130
    static let HOLD_RELEASE_TOTAL_MS: Int64 = 290
    static let HOLD_SHOT_BASE_VARIANCE: Float = 0.008
    static let HOLD_SHOT_RATING_VARIANCE: Float = 0.026

    // 1v1 shot meter: a readable basketball-quality estimate, not a stop-the-bar minigame.
    static let SHOT_METER_TICK_MS: Int64 = 48
    static let SHOT_METER_SETTLE_MS: Int64 = 520
    static let SHOT_METER_FINISH_SETTLE_MS: Int64 = 330
    static let SHOT_METER_POSE_TO_SET_MS: Int64 = 520
    static let SHOT_METER_FINISH_POSE_TO_SET_MS: Int64 = 360
    static let MIN_SHOT_CHANCE_PERCENT = 8
    static let MAX_SHOT_CHANCE_PERCENT = 95
    // The visible human meter still caps at 95. An uncontested AI layup/dunk can be closer
    // to automatic so abandoning the rim is punished like real basketball.
    static let BOT_OPEN_FINISH_MAX_CHANCE_PERCENT = 99
    static let BOT_JUMPER_FLOW_PENALTY: Float = 3.0
    static let BOT_MIN_ACCEPTABLE_JUMPER_CHANCE = 57
    static let BOT_MAX_BETTER_SHOT_SEARCHES = 3
    static let BOT_BETTER_SHOT_SEARCH_STEPS = 14
    static let BOT_BETTER_SHOT_HARD_MAX_STEPS = 54
    static let BOT_BETTER_SHOT_SEARCH_TICK_MS: Int64 = 46
    static let SHOT_ESCAPE_DRAG_DP: Float = 30
    static let SHOT_FADE_DRAG_DP: Float = 34
    static let HUMAN_SHOT_ROLL_SALT: Int64 = 0x53484F5448554D41
    static let BOT_SHOT_ROLL_SALT: Int64 = 0x53484F54424F5453

    static let BOT_EVASION_COOLDOWN_MS: Int64 = 360
    static let BOT_EVASION_PRESSURE_THRESHOLD: Float = 0.34
    static let BOT_EVASION_BASE_CHANCE: Float = 0.10
    static let BOT_EVASION_HANDLING_CHANCE: Float = 0.56
    static let BOT_MAX_EVASIONS_PER_ATTACK = 1
    static let BOT_REATTACK_COMMIT_MS: Int64 = 560
    static let BOT_ESCAPE_THEN_REATTACK_MS: Int64 = 440
    static let BOT_HARD_CUTOFF_PRESSURE: Float = 0.78

    static let BOT_QUESTION_FAST_MS: Int64 = 1050
    static let BOT_QUESTION_SLOW_MS: Int64 = 4200
    static let BOT_QUESTION_JITTER_MS: Int64 = 420
    static let BOT_QUESTION_MIN_ABSOLUTE_MS: Int64 = 720
    static let BOT_QUESTION_MAX_ABSOLUTE_MS: Int64 = 4700
    static let BOT_QUESTION_RETRY_FAST_MS: Int64 = 900
    static let BOT_QUESTION_RETRY_SLOW_MS: Int64 = 2500
    static let BOT_QUESTION_RETRY_JITTER_MS: Int64 = 260
    static let BOT_QUESTION_RETRY_MIN_MS: Int64 = 720
    static let BOT_QUESTION_RETRY_MAX_MS: Int64 = 3100
    static let BOT_QUESTION_DEADLINE_FAST_MS: Int64 = 7600
    static let BOT_QUESTION_DEADLINE_SLOW_MS: Int64 = 12500
    static let BOT_QUESTION_DEADLINE_KNOWLEDGE_BONUS_MS: Int64 = 1800
    static let BOT_QUESTION_DEADLINE_JITTER_MS: Int64 = 900
    static let BOT_QUESTION_DEADLINE_MIN_MS: Int64 = 5200
    static let BOT_QUESTION_DEADLINE_MAX_MS: Int64 = 13500
    static let BOT_QUESTION_ATTEMPT_SEED_SALT: Int64 = 0x5155495A4154544D
    static let BOT_FAKE_READ_SEED_SALT: Int64 = 0x46414B4552454144
    static let BOT_REAL_SHOT_READ_SEED_SALT: Int64 = 0x5245414C53484F54

    static let QUICK_AIM_HORIZONTAL_DP: Float = 150
    static let QUICK_AIM_VERTICAL_DP: Float = 260
    static let QUICK_AIM_PULL_RANGE: Float = 0.18

    static let QUICK_RELEASE_NEUTRAL_MS: Int64 = 560
    static let QUICK_RELEASE_MAX_ERROR: Float = 0.065

    static let TAP_MAX_DURATION_MS: Int64 = 190
    static let TAP_MOVE_SLOP_DP: Float = 9
    static let PRESS_TO_AIM_CANCEL_SLOP_DP: Float = 13
    static let PRESS_TO_AIM_START_MS: Int64 = 210
    static let DOUBLE_TAP_MAX_GAP_MS: Int64 = 285
    static let DOUBLE_TAP_MAX_DISTANCE_DP: Float = 38

    static let QUICK_SHOT_MID_AT_MS: Int64 = 120
    static let QUICK_SHOT_SET_AT_MS: Int64 = 305
    static let QUICK_SHOT_RELEASE_AT_MS: Int64 = 520
    static let QUICK_SHOT_FAKE_CUTOFF_MS: Int64 = 440
    static let QUICK_SHOT_FAKE_RETURN_MS: Int64 = 90
    static let QUICK_SHOT_LOW_PULL: Float = 0.025
    static let QUICK_SHOT_MID_PULL: Float = 0.28
    static let QUICK_SHOT_SET_PULL: Float = 0.74
    static let QUICK_SHOT_BASE_VARIANCE: Float = 0.010
    static let QUICK_SHOT_RATING_VARIANCE: Float = 0.036
    static let QUICK_SHOT_MOVEMENT_VARIANCE: Float = 0.032
    static let RECENT_MOVE_DECAY_MS: Int64 = 620

    // Touch -> world movement. A full-screen fling is capped by the character's Speed rating.
    static let MOVE_INPUT_SCALE: Float = 0.67
    static let MOVE_BASE_SPEED_DP_PER_SEC: Float = 235
    static let MOVE_SPEED_RATING_DP_PER_SEC: Float = 2.0
    static let MOVE_MIN_EVENT_DT_MS: Int64 = 8
    static let MOVE_MAX_EVENT_DT_MS: Int64 = 42
    static let MOVING_SHOT_MIN_INTENSITY: Float = 0.18
    static let ROTATE_MOVE_DEAD_ZONE: Float = 0.08
    static let ROTATE_MOVE_SCALE: Float = 0.88
    static let CONTROL_PREFS = "triple_shot_one_on_one_controls"
    static let CONTROL_MODE_KEY = "control_mode"

    static let QUESTION_SEED_SALT: Int64 = 0x3156315155455354
    static let QUESTION_RESPONSE_SEED_SALT: Int64 = 0x524553504F4E5345

    static let BOT_DUMMY_QUESTION = TripleShotQuestion(
        id: "one_on_one",
        category: QuestionCategory.GENERAL_KNOWLEDGE,
        prompt: "",
        answers: [AnswerOption(text: "", qualityPercent: 100)],
        explanation: ""
    )

    static func newInstance(config: TripleShotGameConfig) -> TripleShotOneOnOneFragment {
        // `TripleShotOneOnOneFragment().apply { arguments = Bundle().apply { ... } }`
        let fragment = TripleShotOneOnOneFragment()
        let arguments = ABundle()
        arguments.putString(ARG_PLAYER_NAME, config.playerName)
        arguments.putString(ARG_HUMAN_CHARACTER_ID, config.playerCharacterId)
        arguments.putString(ARG_BOT_CHARACTER_ID, config.botCharacterId)
        arguments.putString(ARG_GAME_ORIENTATION, config.gameOrientation.name)
        arguments.putString(ARG_COURT_ID, config.courtId)
        arguments.putLong(ARG_SEED, config.seed)
        // `ArrayList(config.selectedCategories.map { it.name })`: the set's own iteration order.
        arguments.putStringArrayList(
            ARG_CATEGORIES,
            config.selectedCategories.elements.map { $0.name }
        )
        fragment.arguments = arguments
        return fragment
    }

    // MARK: - iOS helpers of this part (area s-one2)

    /// U+2066 LEFT-TO-RIGHT ISOLATE and U+2069 POP DIRECTIONAL ISOLATE of the Kotlin string templates.
    static let ONE2_LRI = "\u{2066}"
    static let ONE2_PDI = "\u{2069}"
    /// The "✓ " prefix of revealQuestionAnswer (U+2713 CHECK MARK + space).
    static let ONE2_CHECK_MARK_PREFIX = "\u{2713} "
    /// The Kotlin pattern of bidiSafeQuestionPrompt, unchanged (`\d`, `\s` as ICU defines them, like Android);
    /// `\x{00D7}` / `\x{00F7}` are the source's literal multiplication and division signs.
    static let ONE2_ARITHMETIC_PATTERN = #"\d+(?:[.,]\d+)?\s*[-+\x{00D7}\x{00F7}*/]\s*\d+(?:[.,]\d+)?"#

    /// Kotlin `Regex(pattern)` (java.util.regex, ICU4C-backed on Android) as NSRegularExpression (ICU), with
    /// `replace(input) { match -> ... }`: every non-overlapping match, left to right, replaced by the transform of its
    /// value; UTF-16 offsets like java.lang.String.
    struct One2Regex {
        let regex: NSRegularExpression

        init(_ pattern: String) {
            // Kotlin's Regex(pattern) throws PatternSyntaxException on a bad pattern; the pattern here is constant.
            regex = try! NSRegularExpression(pattern: pattern, options: [])
        }

        func replace(_ input: String, _ transform: (String) -> String) -> String {
            let text = input as NSString
            let matches = regex.matches(in: input, options: [], range: NSRange(location: 0, length: text.length))
            if matches.isEmpty { return input }
            var out = ""
            var lastStart = 0
            for match in matches {
                out += text.substring(with: NSRange(location: lastStart, length: match.range.location - lastStart))
                out += transform(text.substring(with: match.range))
                lastStart = match.range.location + match.range.length
            }
            if lastStart < text.length { out += text.substring(from: lastStart) }
            return out
        }
    }
}
