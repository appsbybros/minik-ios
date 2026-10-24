import Foundation

// Port of view/TripleShotCourtView.kt (Android 6c38131; split at the dd722e5 lines), lines 5353-7945: part 3 of the split class
// (DESIGN 2.9/2.10; spec 10-court3). Statement by statement, Kotlin names and member order kept.
//
// - Only methods, computed members and the companion object live here; every stored property (including
//   `premiumGuides` / `premiumGuidesAt`, declared at Kotlin 5578-5579) is declared by part 1.
// - The three overrides whose bodies are in this range are `onSizeChanged_impl`, `onDraw_impl` and
//   `onDetachedFromWindow_impl`; part 1 declares the `override` stubs that forward to them (DESIGN 2.10).
// - Kotlin `private` members are internal (split class). Companion constants are `static let` members and are
//   read as `Self.NAME` (Swift has no unqualified access to statics from instance code).
// - Numbers: Kotlin Float maths stays Float with the same operand order; kotlin.math Float functions go through the
//   AndroidKit k-functions (computed in Double like the JVM); expressions that Kotlin computes in Double
//   (`sin(t * Math.PI)`, `DRIBBLE_BOUNCES_DURING_MOVE`) are computed in Double here too. `max/min` on Floats are
//   Java `Math.max/min` (`kmax/kmin`). Long time differences use `&-` (Kotlin wraps, Swift would trap).
// - Animators are AndroidKit `AValueAnimator`s with Android semantics (synchronous first update in `start()`,
//   `cancel()` = onAnimationCancel then onAnimationEnd). As in Kotlin, a new animator is stored only after its
//   `start()` returned (`x = ValueAnimator.ofFloat(...).apply { ...; start() }`).
// - Closures kept by animators / runnables that this view retains capture `self` weakly (no retain cycle; the
//   behaviour is identical while the view exists).
// - Skipped dead code (spec 10 section 8.19): `LocalDepthLayer`, `answerChoiceLabel`, `predictedBackboardContact`,
//   `stationMarkerY`. The unused companion constants are kept (marked) so the companion object stays complete.

extension TripleShotCourtView {

    /**
     * HORSE human shot from the setter/challenge location. The existing animateShot() path is
     * intentionally left unchanged for Practice and Shooting Challenge.
     */
    func animateHorseShot(
        skill: ShotSkill,
        pullBackAtRelease: Float,
        hot: Bool,
        oneOnOneFinish: OneOnOneDriveFinish = OneOnOneDriveFinish.JUMPER,
        onEnd: @escaping (ShotResult) -> Void
    ) {
        if horseJumpShot && !oneOnOneEnabled && !horseGathering && width > 0 && height > 0 {
            if let pending = horseRelease { removeCallbacks(pending) }
            horseGathering = true
            horseJumpAt = ASystemClock.elapsedRealtime()
            shotGuidesVisible = false
            horseRelease = ARunnable { [weak self] in
                guard let self = self else { return }
                self.horseRelease = nil
                self.animateHorseShot(
                    skill: skill,
                    pullBackAtRelease: pullBackAtRelease,
                    hot: hot,
                    oneOnOneFinish: oneOnOneFinish,
                    onEnd: onEnd
                )
                // Cleared only after the nested call returned: that is what keeps the nested call out of this branch.
                self.horseGathering = false
            }
            postDelayed(horseRelease!, 290)
            invalidate()
            return
        }
        cancelShotSimulation(callEnd: false)

        if width <= 0 || height <= 0 {
            post { [weak self] in
                self?.animateHorseShot(
                    skill: skill,
                    pullBackAtRelease: pullBackAtRelease,
                    hot: hot,
                    oneOnOneFinish: oneOnOneFinish,
                    onEnd: onEnd
                )
            }
            return
        }

        // Silent no-op without a HORSE / 1v1 station: onEnd is never called (Android behaviour).
        guard let station = horseHumanStation else { return }

        oneOnOneHumanActiveFinish =
            oneOnOneEnabled ? oneOnOneFinish : OneOnOneDriveFinish.JUMPER
        hotHand = hot
        ballVisible = true
        let releaseMotion: TripleShotPlayerRenderer.Motion =
            oneOnOneEnabled && oneOnOneFinish == OneOnOneDriveFinish.DUNK
                ? TripleShotPlayerRenderer.Motion.DUNK
                : preReleaseHumanMotionForPull(pull: pullBackAtRelease)
        let rawStart = heldBallPosition(motionOverride: releaseMotion)
        shotGuidesVisible = false
        humanReleaseStartedAtNanos = ASystem.nanoTime()
        shotOnEnd = onEnd
        shotMadeAtSeconds = nil

        let socket: CourtPoint? = oneOnOneEnabled ? releaseSocket(human: true, motion: releaseMotion) : nil
        let base = buildPhysicsGeometry()
        let geometry = socket != nil
            ? TripleShotRadialShot.geometry(base: base, release: socket!, hoop: worldHoop(), scale: worldVerticalScale())
            : base
        let start: APointF
        if let socket = socket {
            humanShotPresentation.prepareWorldRelease(point: socket, scale: worldVerticalScale())
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
            pullBack01: pullBackAtRelease.coerceIn(0.22, 1.20),
            geometry: geometry,
            distanceDifficulty: station.distanceDifficulty,
            neutralPowerHitsTarget: oneOnOneEnabled,
            compactOneOnOneArc: oneOnOneEnabled || horseJumpShot,
            rejectUpwardBasketEntry:
                oneOnOneEnabled && oneOnOneFinish != OneOnOneDriveFinish.JUMPER
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

    /// Body of `override fun onSizeChanged(w, h, oldw, oldh)` (part 1 holds the override stub).
    func onSizeChanged_impl(_ w: Int, _ h: Int, _ oldw: Int, _ oldh: Int) {
        let previous = lastRenderedTransform
        let humanSource = previous.map { APointF((playerX - $0.offsetX) / $0.scaleX, (playerFootY - $0.offsetY) / $0.scaleY) }
        let botSource = previous.map { APointF((botX - $0.offsetX) / $0.scaleX, (botFootY - $0.offsetY) / $0.scaleY) }
        super.onSizeChanged(w, h, oldw, oldh)

        if !hasInitialPlayerPosition && w > 0 && h > 0 {
            let p = horseHumanStation.map { botStationScreenPoint(station: $0) }
                ?? defaultPlayerScreenPoint()
            playerX = p.x
            playerFootY = p.y
            hasInitialPlayerPosition = true
            let held = heldBallPosition()
            ballX = held.x
            ballY = held.y
        } else if horseHumanStation != nil && w > 0 && h > 0 {
            let p = botStationScreenPoint(station: horseHumanStation!)
            playerX = p.x
            playerFootY = p.y
        }

        if botEnabled && w > 0 && h > 0 {
            if let station = botCurrentStation {
                let p = botStationScreenPoint(station: station)
                botX = p.x
                botFootY = p.y
                let held = heldBotBallPosition()
                botBallX = held.x
                botBallY = held.y
            }
        }

        if w > 0 && h > 0 {
            for remote in liveRemotePlayers.values {
                let p = sourcePointToView(sourceX: remote.sourceX, sourceY: remote.sourceY)
                remote.x = p.x
                remote.footY = p.y
                if remote.physicsState == nil && !remote.replayActive {
                    let held = liveRemoteHeldBall(remote: remote)
                    remote.ballX = held.x
                    remote.ballY = held.y
                }
            }
        }
        if oldw > 0 && oldh > 0, let humanSource = humanSource, let botSource = botSource {
            playerMoveAnimator?.cancel(); botMoveAnimator?.cancel()
            let hPoint = sourcePointToView(sourceX: humanSource.x, sourceY: humanSource.y)
            let bPoint = sourcePointToView(sourceX: botSource.x, sourceY: botSource.y)
            playerX = hPoint.x; playerFootY = hPoint.y; botX = bPoint.x; botFootY = bPoint.y
        }
    }

    /// Body of `override fun onDraw(canvas)` (part 1 holds the override stub). It never paints: it builds the
    /// per-frame world snapshot (human, bot, live remotes, markers, guides, rim/net flex) and presents it.
    /// `present` re-posts the next invalidate, so this runs once per frame while the view is attached and shown.
    func onDraw_impl(_ canvas: ACanvas) {
        super.onDraw(canvas)
        if width <= 0 || height <= 0 { return }
        let t = backgroundTransform()
        lastRenderedTransform = t
        func ground(_ x: Float, _ foot: Float, _ lift: Float) -> CourtPoint {
            return TripleShotWorldCoordinates.solo(
                sourceX: (x - t.offsetX) / t.scaleX, sourceY: (foot - t.offsetY) / t.scaleY, lift: lift)
        }
        let hoop = TripleShotWorldCoordinates.solo(
            sourceX: Self.SRC_HOOP_CENTER_X, sourceY: Self.SRC_HOOP_DEPTH_FOOT_Y, lift: TripleShotWorldCoordinates.RIM_HEIGHT)
        let humanState = humanRendererState()
        let human = TripleShotWorldActor(
            id: "human",
            position: ground(humanState.x, playerFootY, (playerFootY - humanState.footY) / density * 0.012),
            state: humanState,
            controlled: true,
            team: 1
        )
        var worldActors: [TripleShotWorldActor] = []
        worldActors.reserveCapacity(2 + liveRemotePlayers.count)
        var worldBalls: [TripleShotWorldBall] = []
        worldBalls.reserveCapacity(2 + liveRemotePlayers.count)
        worldActors.append(human)
        if !shotFrameRunning && !oneOnOneLooseBallActive {
            let held = heldBallPosition(); ballX = held.x; ballY = held.y
            humanShotPresentation.held = gpuWorld.actorSocket(actor: human, inFront: shouldDrawHumanProBallInFrontOfBody())
        }
        if ballVisible && humanEndPose == TripleShotPlayerRenderer.Pose.NORMAL &&
            (humanOwnsVisibleBall() || shotFrameRunning || oneOnOneLooseBallActive) {
            let state = physicsState; let geometry = physicsGeometry
            let position: CourtPoint
            if shotFrameRunning, let state = state, let geometry = geometry {
                position = humanShotPresentation.sample(
                    state: state, geometry: geometry, hoop: hoop, verticalScale: Float(3.35) / (608 * t.scaleY))
            } else if oneOnOneLooseBallActive {
                position = worldLooseBall?.position ?? humanShotPresentation.held
            } else {
                position = humanShotPresentation.held
            }
            worldBalls.append(TripleShotWorldBall(
                position: position,
                resource: currentBallResId,
                owner: !shotFrameRunning && !oneOnOneLooseBallActive ? "human" : nil,
                rotation: ballRotationDeg,
                inFront: shouldDrawHumanProBallInFrontOfBody()
            ))
        }
        if botEnabled {
            let regular = botRendererState()
            // A short, occasional trick while waiting with the ball; never a human shot pose.
            let playfulClock = (ASystem.nanoTime() / 1_000_000) % 19000
            let playful = botCharacterId == "coach_67" && sharedHorseBallOwner == SharedBallOwner.BOT &&
                regular.motion == TripleShotPlayerRenderer.Motion.IDLE && regular.facing == TripleShotPlayerRenderer.Facing.BACK &&
                playfulClock >= 0 && playfulClock <= 1100
            var bs = regular
            bs.playfulHold = playful
            let bot = TripleShotWorldActor(
                id: "bot",
                position: ground(bs.x, botFootY, (botFootY - bs.footY) / density * 0.012),
                state: bs,
                team: 2
            )
            worldActors.append(bot)
            if !botShotFrameRunning && !oneOnOneBotDunkActive {
                let held = heldBotBallPosition(); botBallX = held.x; botBallY = held.y
                botShotPresentation.held = gpuWorld.actorSocket(
                    actor: bot, inFront: bs.facing != TripleShotPlayerRenderer.Facing.BACK)
            }
            if botBallVisible {
                let state = botPhysicsState; let geometry = botPhysicsGeometry
                let position: CourtPoint
                if botShotFrameRunning, let state = state, let geometry = geometry {
                    position = botShotPresentation.sample(
                        state: state, geometry: geometry, hoop: hoop, verticalScale: Float(3.35) / (608 * t.scaleY))
                } else if oneOnOneBotDunkActive {
                    position = CourtPoint(
                        x: hoop.x + (botBallX - sourcePointToView(sourceX: Self.SRC_HOOP_CENTER_X, sourceY: Self.SRC_HOOP_PLANE_Y).x)
                            * 1.1 / (190 * t.scaleX),
                        y: (hoop.y + (sourcePointToView(sourceX: Self.SRC_HOOP_CENTER_X, sourceY: Self.SRC_HOOP_PLANE_Y).y - botBallY)
                            * 3.35 / (608 * t.scaleY)).coerceAtLeast(0.16),
                        z: hoop.z
                    )
                } else {
                    position = botShotPresentation.held
                }
                worldBalls.append(TripleShotWorldBall(
                    position: position,
                    resource: currentBallResId,
                    owner: !botShotFrameRunning && !oneOnOneBotDunkActive ? "bot" : nil,
                    rotation: botBallRotationDeg,
                    inFront: bs.facing != TripleShotPlayerRenderer.Facing.BACK
                ))
            }
        }
        for remote in liveRemotePlayers.values {
            let state = TripleShotPlayerRenderer.State(
                x: remote.x, footY: remote.footY, fineAim: 0, pullBack: 0, dribbleBouncePx: remote.dribbleBouncePx,
                hotHand: remote.hotHand, style: TripleShotPlayerRenderer.Style.BOT, pose: remote.pose,
                celebrationProgress: matchCelebrationProgress)
            let actor = TripleShotWorldActor(
                id: remote.uid, position: ground(remote.x, remote.footY, 0), state: state, label: remote.name.ktake(9))
            worldActors.append(actor)
            // Kotlin `getOrPut`: one presentation bridge per remote uid, never pruned.
            let bridge: TripleShotShotPresentation
            if let existing = remoteShotPresentations[remote.uid] {
                bridge = existing
            } else {
                let created = TripleShotShotPresentation()
                remoteShotPresentations[remote.uid] = created
                bridge = created
            }
            if remote.physicsState == nil && !remote.replayActive { bridge.held = gpuWorld.actorSocket(actor: actor) }
            if remote.ballVisible {
                let physics = remote.physicsState; let geometry = remote.physicsGeometry
                let point: CourtPoint
                if let physics = physics, let geometry = geometry {
                    point = bridge.sample(state: physics, geometry: geometry, hoop: hoop, verticalScale: Float(3.35) / (608 * t.scaleY))
                } else if remote.replayActive {
                    let sourceHoop = sourcePointToView(sourceX: Self.SRC_HOOP_CENTER_X, sourceY: Self.SRC_HOOP_PLANE_Y)
                    point = bridge.sampleRecorded(
                        x: remote.ballX, y: remote.ballY, startX: remote.replayStartX, startY: remote.replayStartY,
                        flightProgress: remote.replayFlightProgress, hoop: hoop, sourceHoopX: sourceHoop.x,
                        sourceHoopY: sourceHoop.y, rimSpan: 190 * t.scaleX, verticalScale: Float(3.35) / (608 * t.scaleY))
                } else {
                    point = bridge.held
                }
                worldBalls.append(TripleShotWorldBall(
                    position: point,
                    resource: currentBallResId,
                    owner: physics == nil && !remote.replayActive ? remote.uid : nil
                ))
            }
        }
        var markers: [TripleShotWorldMarker] = []
        if answerMarkersVisible {
            for index in kuntil(0, answerCount) {
                let p = stationScreenPoint(index: index, count: answerCount)
                // Hebrew letters from U+05D0 (alef), A B C D otherwise; the device locale decides, as on Android.
                let base = ["he", "iw"].contains(resources.configuration.locales[0].language) ? 0x05D0 : 0x41
                let letter = String(Character(UnicodeScalar(UInt32(base + index))!))
                markers.append(TripleShotWorldMarker(position: ground(p.x, p.y, 0.03), text: letter, selected: index == selectedStation))
            }
        }
        if horseSpotPickerVisible {
            for station in Self.HORSE_SELECTABLE_SPOTS {
                markers.append(TripleShotWorldMarker(
                    position: TripleShotWorldCoordinates.solo(sourceX: station.sourceX, sourceY: station.sourceY, lift: 0.03),
                    text: "\u{2022}",
                    selected: station.id == horseSelectedSpotId
                ))
            }
        }
        if !oneOnOneLooseBallActive, let flight = worldBalls.first(where: { $0.owner == nil }) {
            lastWorldFlight = flight.position
        }
        let guides = premiumGuidePoints(human: human, hoop: hoop)
        present(scene: TripleShotWorldSnapshot(
            timeNanos: ASystem.nanoTime(),
            courtId: premiumCourtId,
            teamSize: 1,
            actors: worldActors,
            balls: worldBalls,
            hoops: [hoop],
            atmosphere: courtAtmosphere,
            markers: markers,
            guides: guides,
            rimShake: currentRimShakeOffset() / density * 0.012,
            netSway: currentNetKickOffset().x / density * 0.012
        ))
    }

    func premiumGuidePoints(human: TripleShotWorldActor, hoop: CourtPoint) -> [CourtPoint] {
        if horseJumpShot || !shotGuidesVisible || oneOnOneSuppressShotGuideDrawing || shotFrameRunning ||
            (selectedStation < 0 && horseHumanStation == nil) { return [] }
        let now = ASystem.nanoTime(); if now &- premiumGuidesAt < 50_000_000 { return premiumGuides }
        premiumGuidesAt = now
        guard let station = currentGuideStation() else { return [] }
        let geometry = buildPhysicsGeometry(); let preview = buildGuidePreview(geometry: geometry, station: station)
        let bridge = TripleShotShotPresentation(); bridge.held = gpuWorld.actorSocket(actor: human)
        var points: [CourtPoint] = []
        if effectiveAimAssistLevel(station: station) < Self.AIM_TARGET_MARKER_HIDE_LEVEL {
            points.append(CourtPoint(
                x: hoop.x, y: hoop.y,
                z: hoop.z - fineAim * aimRangePx() * 1.1 / (geometry.rightRimX - geometry.leftRimX)))
        }
        if pullBack > 0.015 {
            let total = preview.expectedFlightSeconds *
                arcPreviewFlightFraction(effectiveLevel: effectiveAimAssistLevel(station: station), pathMode: preview.pathMode)
            var bankTime: Float? = nil
            while preview.elapsedSeconds < total {
                let result = TripleShotPhysics.step(
                    state: preview, geometry: geometry, dtSeconds: kmin(0.04, total - preview.elapsedSeconds))
                points.append(bridge.sample(
                    state: preview, geometry: geometry, hoop: hoop, verticalScale: Float(3.35) / (608 * backgroundTransform().scaleY)))
                if result.backboardImpactSpeed > 0 && bankTime == nil { bankTime = preview.elapsedSeconds }
                if result.rimImpactSpeed > 0 || preview.enteredBasketFromBelow ||
                    (bankTime != nil && preview.elapsedSeconds - bankTime! >= Self.BANK_PREVIEW_AFTER_HIT_SECONDS) { break }
            }
        }
        premiumGuides = points; return points
    }

    func liveRemoteHeldBall(remote: LiveRemoteVisual) -> APointF {
        let raw =
            playerRenderer.heldBallPosition(
                state: TripleShotPlayerRenderer.State(
                    x: remote.x,
                    footY: remote.footY,
                    fineAim: 0,
                    pullBack: 0,
                    dribbleBouncePx: remote.dribbleBouncePx,
                    hotHand: remote.hotHand,
                    style: TripleShotPlayerRenderer.Style.BOT
                )
            )
        let scale: Float = 0.82
        return APointF(
            remote.x + (raw.x - remote.x) * scale,
            remote.footY + (raw.y - remote.footY) * scale
        )
    }

    func liveDistanceDifficulty(sourceX: Float, sourceY: Float) -> Float {
        let hoop = APointF(Self.SRC_HOOP_CENTER_X, Self.SRC_HOOP_PLANE_Y)
        let dx = sourceX - hoop.x
        let dy = sourceY - hoop.y
        let distance = ksqrt(dx * dx + dy * dy)
        return ((distance - 250) / 900).coerceIn(0, 1)
    }

    /**
     * Current logical shooting location used for guide difficulty. The guide is intentionally
     * the only adaptive part: the real ball still receives the exact same physical inputs.
     */
    func currentGuideStation() -> Station? {
        return horseHumanStation
            ?? (selectedStation >= 0 ? stationForAnswer(index: selectedStation, count: answerCount) : nil)
    }

    /**
     * Hard positions remove some assistance relative to the player's current learned level.
     * A beginner still gets help behind the board; an expert who is already on level 4/5 gets
     * almost none. This is additive rather than a fixed per-location difficulty preset.
     */
    func effectiveAimAssistLevel(station: Station) -> Float {
        let distancePenalty =
            ((station.distanceDifficulty - 0.35) / 0.60)
                .coerceIn(0, 1) * 0.85

        let behindBoardPenalty: Float =
            station.sourceX > Self.SRC_BACKBOARD_COLLISION_X + 18 ? 1.15 : 0

        return (aimAssistBaseLevel.toFloat() + distancePenalty + behindBoardPenalty)
            .coerceIn(0, Self.AIM_ASSIST_MAX_LEVEL.toFloat())
    }

    /**
     * Level 0: current full guide + target marker.
     * Level 1: same arc, but the target marker disappears first.
     * Levels 2..5: progressively less of the trajectory is revealed.
     */
    func arcPreviewFlightFraction(
        effectiveLevel: Float,
        pathMode: TripleShotPhysics.ShotPathMode
    ) -> Float {
        let fractions: [Float]
        if pathMode == TripleShotPhysics.ShotPathMode.HIGH_LOB {
            // A trick lob needs more visible context or the short first segment looks
            // misleadingly straight. It still shrinks aggressively for expert players.
            fractions = [1.04, 0.90, 0.72, 0.58, 0.42, 0.32]
        } else {
            fractions = [1.04, 0.88, 0.66, 0.46, 0.30, 0.18]
        }

        let low = effectiveLevel.toInt().coerceIn(0, Self.AIM_ASSIST_MAX_LEVEL)
        let high = (low + 1).coerceAtMost(Self.AIM_ASSIST_MAX_LEVEL)
        let t = (effectiveLevel - low.toFloat()).coerceIn(0, 1)
        return lerp(fractions[low], fractions[high], t)
    }

    func buildGuidePreview(
        geometry: TripleShotPhysics.Geometry,
        station: Station
    ) -> TripleShotPhysics.ShotState {
        let start = heldBallPosition()
        let previewSkill = BasketballTouchShot.skill(aim: fineAim, pull: pullBack)

        return TripleShotPhysics.createLaunch(
            skill: previewSkill,
            startX: start.x,
            startY: start.y,
            targetX: geometry.hoopCenterX + fineAim * aimRangePx(),
            targetY: geometry.hoopY,
            pullBack01: pullBack.coerceAtLeast(0.08),
            geometry: geometry,
            distanceDifficulty: station.distanceDifficulty
        )
    }

    /** Gameplay ownership only; sprite artwork is never consulted for ball ownership. */
    func humanOwnsVisibleBall() -> Bool {
        if oneOnOneEnabled {
            return sharedHorseBallOwner == SharedBallOwner.HUMAN
        } else {
            return sharedHorseBallOwner != SharedBallOwner.BOT
        }
    }

    func giveSharedHorseBallToHuman() {
        sharedHorseBallOwner = SharedBallOwner.HUMAN
        ballVisible = true
        botBallVisible = false

        let held = heldBallPosition(motionOverride: TripleShotPlayerRenderer.Motion.IDLE)
        ballX = held.x
        ballY = held.y
        ballRotationDeg = 0
        scheduleHumanIdleDribble()
        invalidate()
    }

    func giveSharedHorseBallToBot() {
        sharedHorseBallOwner = SharedBallOwner.BOT
        cancelHumanIdleDribble()
        ballVisible = false
        botBallVisible = botEnabled

        if botEnabled {
            let held = heldBotBallPosition()
            botBallX = held.x
            botBallY = held.y
            botBallRotationDeg = 0
        }
        invalidate()
    }

    func canHumanIdleDribble() -> Bool {
        return sharedHorseBallOwner == SharedBallOwner.HUMAN &&
            humanOwnsVisibleBall() &&
            !humanWalking &&
            !humanWaitingForTurn &&
            !shotGuidesVisible &&
            !shotFrameRunning &&
            humanEndPose == TripleShotPlayerRenderer.Pose.NORMAL
    }

    func scheduleHumanIdleDribble() {
        removeCallbacks(humanIdleDribbleRunnable)
        if !canHumanIdleDribble() || humanIdleDribbling { return }
        postDelayed(
            humanIdleDribbleRunnable,
            oneOnOneEnabled ? Self.ONE_ON_ONE_IDLE_DRIBBLE_DELAY_MS : Self.HUMAN_IDLE_DRIBBLE_DELAY_MS
        )
    }

    func startHumanIdleDribbleIfEligible() {
        if !canHumanIdleDribble() { return }

        humanIdleDribbleAnimator?.cancel()
        humanIdleDribbling = true
        humanIdleDribbleBouncePx = 0
        humanDribblePhase01 = 0

        let animator = AValueAnimator.ofFloat(0, 1)
        animator.duration =
            oneOnOneEnabled ? Self.ONE_ON_ONE_IDLE_DRIBBLE_DURATION_MS
                : Self.HUMAN_IDLE_DRIBBLE_DURATION_MS
        animator.interpolator = ALinearInterpolator()
        animator.addUpdateListener { [weak self] animator in
            guard let self = self else { return }
            let t = animator.animatedValueFloat
            self.humanDribblePhase01 = t.coerceIn(0, 1)
            // Kotlin `abs(sin(t * Math.PI)).toFloat()`: Float * Double is a Double operation.
            self.humanIdleDribbleBouncePx =
                Float(abs(sin(Double(t) * Double.pi))) * self.dp(Self.HUMAN_IDLE_DRIBBLE_AMPLITUDE_DP)
            self.ballRotationDeg = (t * 180).truncatingRemainder(dividingBy: 360)
            self.invalidate()
        }
        animator.addListener(AAnimatorListenerAdapter(
            onEnd: { [weak self] _ in
                guard let self = self else { return }
                self.humanIdleDribbleAnimator = nil
                self.humanIdleDribbling = false
                self.humanIdleDribbleBouncePx = 0
                self.humanDribblePhase01 = 0
                self.humanDribbleHandSign *= -1
                self.invalidate()
                self.scheduleHumanIdleDribble()
            },
            onCancel: { [weak self] _ in
                guard let self = self else { return }
                self.humanIdleDribbleAnimator = nil
                self.humanIdleDribbling = false
                self.humanIdleDribbleBouncePx = 0
                self.humanDribblePhase01 = 0
                self.invalidate()
            }
        ))
        animator.start()
        humanIdleDribbleAnimator = animator
    }

    func cancelHumanIdleDribble() {
        removeCallbacks(humanIdleDribbleRunnable)
        humanIdleDribbleAnimator?.cancel()
        humanIdleDribbleAnimator = nil
        humanIdleDribbling = false
        humanIdleDribbleBouncePx = 0
        humanDribblePhase01 = 0
    }

    /**
     * Converts a physical "in front of / behind the player" dribble pass into canvas layering.
     *
     * - Standing: every bounce is physically in FRONT of the player and crosses hand-to-hand.
     *   FRONT-facing art therefore gets the ball after the body; BACK-facing art gets it before.
     * - Slow movement: crossovers alternate physically in front / behind on successive bounces.
     * - Fast movement: one-hand dribble stays physically in front on the same side.
     */
    func shouldDrawHumanProBallInFrontOfBody() -> Bool {
        let motion = currentHumanMotion()

        // During the new professional shooting preparation, SIDE/FRONT art faces the camera
        // enough that the separate dynamic ball must be drawn above the body. BACK preparation
        // keeps the ball physically in front of the player, therefore behind the rear-view body.
        if isHumanShotMotion(motion: motion) {
            return currentHumanFacing(motion: motion) != TripleShotPlayerRenderer.Facing.BACK
        }

        if motion != TripleShotPlayerRenderer.Motion.IDLE &&
            motion != TripleShotPlayerRenderer.Motion.DRIBBLE {
            return false
        }

        let crossAge = ASystem.nanoTime() &- humanCrossAt
        let physicalPassInFront: Bool
        if crossAge >= 0 && crossAge <= 420_000_000 {
            physicalPassInFront = !humanCrossBehind
        } else if humanWalking {
            physicalPassInFront = humanMovingFast ? true : humanWalkingBallPassInFront
        } else {
            physicalPassInFront = true
        }

        let facing = currentHumanFacing(motion: motion)
        if physicalPassInFront {
            return facing == TripleShotPlayerRenderer.Facing.FRONT
        } else {
            return facing == TripleShotPlayerRenderer.Facing.BACK
        }
    }

    func humanRendererState(
        motionOverride: TripleShotPlayerRenderer.Motion? = nil
    ) -> TripleShotPlayerRenderer.State {
        let motion = motionOverride
            ?? (horseGathering ? TripleShotPlayerRenderer.Motion.SHOT_SET : currentHumanMotion())
        let physicalJumpOffset = oneOnOneEnabled ? oneOnOneHumanJumpOffsetPx() : horseJumpLift()
        // Blocking success is already tuned well. Raise only the VISUAL block jump here so the
        // action reads like a real high contest without silently making every block easier.
        let jumpOffset: Float
        if oneOnOneEnabled && motion == TripleShotPlayerRenderer.Motion.BLOCK {
            jumpOffset = physicalJumpOffset * Self.ONE_ON_ONE_BLOCK_RENDER_EXTRA_MULTIPLIER
        } else if oneOnOneEnabled && motion == TripleShotPlayerRenderer.Motion.REBOUND {
            jumpOffset = physicalJumpOffset * Self.ONE_ON_ONE_REBOUND_RENDER_EXTRA_MULTIPLIER
        } else {
            jumpOffset = physicalJumpOffset
        }
        let stealOffset = oneOnOneEnabled ? oneOnOneHumanStealVisualOffset() : APointF(0, 0)
        // Arguments with side effects are evaluated in the Kotlin argument order (facing, then mirrorX, then the
        // dunk frame lookup, which calls currentHumanFacing again); `visualScale` is pure and passed last.
        let facing = currentHumanFacing(motion: motion)
        let visualScale = oneOnOneVisualScale(motion: motion)
        let mirrorX = currentHumanMirrorX(motion: motion)
        let actionFrameIndex: Int
        if motion == TripleShotPlayerRenderer.Motion.DUNK {
            actionFrameIndex = TripleShotCharacterVisualCatalog.find(characterId: humanCharacterId)?.dunks
                .firstIndex { $0.facing == currentHumanFacing(motion: motion) } ?? -1
        } else {
            actionFrameIndex = -1
        }
        return stableSoloState(raw: TripleShotPlayerRenderer.State(
            x: playerX + stealOffset.x,
            footY: playerFootY - jumpOffset + stealOffset.y,
            fineAim: fineAim,
            pullBack: pullBack,
            dribbleBouncePx:
                humanIdleDribbling && !humanWalking ? humanIdleDribbleBouncePx : dribbleBouncePx,
            hotHand: hotHand,
            pose: humanEndPose,
            celebrationProgress: matchCelebrationProgress,
            shotStyle: humanShotStyle,
            facing: facing,
            motion: motion,
            dribblePhase01: humanDribblePhase01,
            dribbleHandSign:
                humanWalking ? humanWalkingDribbleHandSign : humanDribbleHandSign,
            moving: humanWalking,
            movingFast: humanMovingFast,
            characterId: humanCharacterId,
            mirrorX: mirrorX,
            actionFrameIndex: actionFrameIndex,
            visualScale: visualScale
        ), human: true)
    }

    /// Facing priority chain. Side effect: the court-Y rule updates `humanCourtFacing` (hysteresis).
    func currentHumanFacing(
        motion: TripleShotPlayerRenderer.Motion
    ) -> TripleShotPlayerRenderer.Facing {
        if !oneOnOneEnabled { return currentHumanShotFacing() }
        let spinAge = ASystem.nanoTime() &- humanSpinAt
        if oneOnOneEnabled && humanOwnsVisibleBall() && spinAge >= 0 && spinAge <= 360_000_000 {
            let phase = ((ASystem.nanoTime() &- humanSpinAt) / 90_000_000).toInt()
            switch phase {
            case 0, 2: return TripleShotPlayerRenderer.Facing.SIDE
            case 1: return TripleShotPlayerRenderer.Facing.FRONT
            default: return TripleShotPlayerRenderer.Facing.BACK
            }
        }
        if oneOnOneEnabled && isOneOnOneActionMotion(motion: motion) {
            let targetX = oneOnOneLooseBallActive ? ballX : botX
            let targetY = oneOnOneLooseBallActive ? ballY : botFootY
            return oneOnOneActionFacing(actorX: playerX, actorFootY: playerFootY, targetX: targetX, targetY: targetY)
        }

        if oneOnOneEnabled && sharedHorseBallOwner == SharedBallOwner.BOT {
            // While Maya has the ball, the defender faces MAYA. The instant the shot is truly
            // released, attention switches to the hoop/rebound instead of continuing to stare at
            // the shooter. This intentionally ignores small lane/Y jitter.
            if botShotFrameRunning {
                let now = ASystem.nanoTime()
                if now < oneOnOneHumanBlockUntilNanos {
                    return oneOnOneDefenderFacing(
                        defenderX: playerX,
                        defenderFootY: playerFootY,
                        ballHandlerX: botX,
                        ballHandlerFootY: botFootY
                    )
                }
                return oneOnOneHoopFacingFor(footY: playerFootY)
            }
            return oneOnOneDefenderFacing(
                defenderX: playerX,
                defenderFootY: playerFootY,
                ballHandlerX: botX,
                ballHandlerFootY: botFootY
            )
        }

        if oneOnOneEnabled && oneOnOneLooseBallActive {
            return oneOnOneHoopFacingFor(footY: playerFootY)
        }

        if isHumanShotMotion(motion: motion) {
            return currentHumanShotFacing()
        }

        if width <= 0 || height <= 0 { return humanCourtFacing }

        /*
         * Court-facing for idle/walk/dribble stays exactly on the approved V14 Y-only rule.
         * Shooting orientation is deliberately separate and uses the real player -> hoop vector.
         */
        let t = backgroundTransform()
        if t.scaleY <= 0 { return humanCourtFacing }
        let sourceY =
            ((playerFootY - t.offsetY) / t.scaleY)
                .coerceIn(0, Self.BACKGROUND_HEIGHT)

        if !humanCourtFacingInitialized {
            humanCourtFacing =
                sourceY <= Self.SRC_FACING_DIVIDER_Y
                    ? TripleShotPlayerRenderer.Facing.FRONT
                    : TripleShotPlayerRenderer.Facing.BACK
            humanCourtFacingInitialized = true
            return humanCourtFacing
        }

        switch humanCourtFacing {
        case TripleShotPlayerRenderer.Facing.FRONT:
            humanCourtFacing =
                sourceY >= Self.SRC_FACING_BACK_ENTER_Y
                    ? TripleShotPlayerRenderer.Facing.BACK
                    : TripleShotPlayerRenderer.Facing.FRONT

        case TripleShotPlayerRenderer.Facing.BACK:
            humanCourtFacing =
                sourceY <= Self.SRC_FACING_FRONT_ENTER_Y
                    ? TripleShotPlayerRenderer.Facing.FRONT
                    : TripleShotPlayerRenderer.Facing.BACK

        // SIDE exists only during shooting; court-facing never stores it (Kotlin `SIDE -> humanCourtFacing`).
        case TripleShotPlayerRenderer.Facing.SIDE:
            break
        }

        return humanCourtFacing
    }

    // 1v1 deliberately uses the exact same authored BACK/SIDE/FRONT selector as HORSE and
    // Shooting Challenge. The sprite families were tuned against these court corridors, so sharing
    // one selector prevents 1v1 from visually disagreeing with the already-approved game modes.
    func currentHumanShotFacing() -> TripleShotPlayerRenderer.Facing {
        if oneOnOneEnabled {
            return oneOnOneShotFacingFor(actorX: playerX, actorFootY: playerFootY, fallback: humanCourtFacing)
        } else {
            return shotFacingFor(actorX: playerX, actorFootY: playerFootY, fallback: humanCourtFacing)
        }
    }

    func currentBotShotFacing() -> TripleShotPlayerRenderer.Facing {
        if oneOnOneEnabled {
            return oneOnOneShotFacingFor(actorX: botX, actorFootY: botFootY, fallback: botCourtFacing)
        } else {
            return shotFacingFor(actorX: botX, actorFootY: botFootY, fallback: botCourtFacing)
        }
    }

    /**
     * 1v1 can shoot from arbitrary live positions, so fixed left/right corridors are too coarse.
     * Use the real feet -> hoop-ground vector instead. The original HORSE/challenge selector is
     * left untouched below, which prevents this tuning from regressing the approved game modes.
     */
    func hoopScreenDirection(actorX: Float, actorFootY: Float) -> APointF {
        let t = backgroundTransform()
        let x = (actorX - t.offsetX) / t.scaleX.coerceAtLeast(0.001)
        let y = (actorFootY - t.offsetY) / t.scaleY.coerceAtLeast(0.001)
        let dx = (Self.SRC_HOOP_CENTER_X - x) * Float(0.014)
        let dz = (Self.SRC_HOOP_DEPTH_FOOT_Y - y) * Float(0.017)
        return APointF(dx * TripleShotWorldMath.RIGHT_X + dz * TripleShotWorldMath.RIGHT_Z,
                       -dx * TripleShotWorldMath.RIGHT_Z + dz * TripleShotWorldMath.RIGHT_X)
    }

    func oneOnOneShotFacingFor(actorX: Float, actorFootY: Float, fallback: TripleShotPlayerRenderer.Facing) -> TripleShotPlayerRenderer.Facing {
        return shotFacingFor(actorX: actorX, actorFootY: actorFootY, fallback: fallback)
    }

    func shotFacingFor(actorX: Float, actorFootY: Float, fallback: TripleShotPlayerRenderer.Facing) -> TripleShotPlayerRenderer.Facing {
        if width <= 0 || height <= 0 { return fallback }
        let direction = hoopScreenDirection(actorX: actorX, actorFootY: actorFootY)
        return abs(direction.x) > abs(direction.y) * Float(0.9) ? TripleShotPlayerRenderer.Facing.SIDE
            : direction.y > 0 ? TripleShotPlayerRenderer.Facing.FRONT : TripleShotPlayerRenderer.Facing.BACK
    }

    func isHumanShotMotion(
        motion: TripleShotPlayerRenderer.Motion
    ) -> Bool {
        return motion == TripleShotPlayerRenderer.Motion.DUNK ||
            motion == TripleShotPlayerRenderer.Motion.SHOT_LOW ||
            motion == TripleShotPlayerRenderer.Motion.SHOT_MID ||
            motion == TripleShotPlayerRenderer.Motion.SHOT_SET ||
            motion == TripleShotPlayerRenderer.Motion.RELEASE
    }

    func currentHumanMirrorX(
        motion: TripleShotPlayerRenderer.Motion
    ) -> Bool {
        if !oneOnOneEnabled {
            return currentHumanShotFacing() == TripleShotPlayerRenderer.Facing.SIDE &&
                hoopScreenDirection(actorX: playerX, actorFootY: playerFootY).x < 0
        }

        if currentHumanFacing(motion: motion) != TripleShotPlayerRenderer.Facing.SIDE { return false }
        if oneOnOneEnabled && motion == TripleShotPlayerRenderer.Motion.STEAL {
            let facing = currentHumanFacing(motion: motion)
            if facing != TripleShotPlayerRenderer.Facing.SIDE {
                // STEAL FRONT/BACK art reaches to screen-left by default. Mirror it only when the
                // live dribble is actually on the defender's screen-right side. This makes the
                // visible hand agree with which hand the ball-handler is using.
                let liveBall = oneOnOneLooseBallActive ? APointF(ballX, ballY) : heldBotBallPosition()
                return liveBall.x > playerX
            }
        }

        if oneOnOneEnabled &&
            isOneOnOneActionMotion(motion: motion) &&
            currentHumanFacing(motion: motion) == TripleShotPlayerRenderer.Facing.SIDE {
            let targetX = oneOnOneLooseBallActive ? ballX : botX
            return targetX < playerX
        }

        if motion == TripleShotPlayerRenderer.Motion.DRIBBLE {
            // We still need dedicated left/right running sprites, but mirroring the existing body
            // and keeping the ball on the movement-side hand makes hard cuts readable today.
            return oneOnOneEnabled && humanMovingFast && humanMovementHorizontalSign < 0
        }
        if width <= 0 || height <= 0 { return false }

        let hoop = sourcePointToView(sourceX: Self.SRC_HOOP_CENTER_X, sourceY: Self.SRC_HOOP_PLANE_Y)
        let dx = hoop.x - playerX

        // SIDE_RIGHT is the only authored side family. When the hoop is on the left, mirror the
        // whole sprite and its ball socket. BACK/FRONT shot families are symmetric enough to
        // remain unmirrored so they do not visibly flip during the shooting motion.
        if isHumanShotMotion(motion: motion) {
            return currentHumanFacing(motion: motion) == TripleShotPlayerRenderer.Facing.SIDE &&
                dx < -dp(Self.FACING_HORIZONTAL_DEAD_ZONE_DP)
        }

        return dx < -dp(Self.FACING_HORIZONTAL_DEAD_ZONE_DP)
    }

    func beginHumanMovementDribble() {
        humanWalking = true
        humanWalkingDribbleHandSign = humanDribbleHandSign
        humanWalkingBounceIndex = 0
        humanWalkingBallPassInFront = true
        humanMovingFast = false
        humanMovementSpeedDpPerSec = 0
        humanMovementSampleNanos = ASystem.nanoTime()
    }

    func updateHumanMovementSpeed(distancePx: Float, nowNanos: Int64 = ASystem.nanoTime()) {
        if distancePx <= 0 { return }

        let previous = humanMovementSampleNanos
        let dtSeconds: Float
        if previous == 0 {
            dtSeconds = Float(1) / Float(60)
        } else {
            dtSeconds = ((nowNanos &- previous).toFloat() / 1_000_000_000).coerceIn(0.008, 0.080)
        }
        humanMovementSampleNanos = nowNanos

        let instantDpPerSec =
            (distancePx / density.coerceAtLeast(0.1)) / dtSeconds.coerceAtLeast(0.001)
        if humanMovementSpeedDpPerSec <= 0 {
            humanMovementSpeedDpPerSec = instantDpPerSec
        } else {
            humanMovementSpeedDpPerSec = lerp(humanMovementSpeedDpPerSec, instantDpPerSec, 0.34)
        }

        if humanMovingFast {
            humanMovingFast = humanMovementSpeedDpPerSec >= Self.HUMAN_FAST_DRIBBLE_EXIT_DP_PER_SEC
        } else {
            humanMovingFast = humanMovementSpeedDpPerSec >= Self.HUMAN_FAST_DRIBBLE_ENTER_DP_PER_SEC
        }
    }

    func resetHumanMovementSpeed() {
        humanMovingFast = false
        humanMovementSpeedDpPerSec = 0
        humanMovementSampleNanos = 0
        humanWalkingBounceIndex = 0
        humanWalkingBallPassInFront = true
    }

    /**
     * Called when a new walking bounce begins. Slow movement crosses to the other hand and
     * alternates front/behind-body passes; fast movement intentionally stays on one hand.
     */
    func updateMovingDribbleBounceIndex(newIndex: Int) {
        if newIndex == humanWalkingBounceIndex { return }

        // Crossovers are explicit actions, not a body/hand flip on every bounce.
        humanWalkingBallPassInFront = true
        humanWalkingBounceIndex = newIndex
    }

    func currentHumanMotion() -> TripleShotPlayerRenderer.Motion {
        if humanEndPose != TripleShotPlayerRenderer.Pose.NORMAL {
            return TripleShotPlayerRenderer.Motion.IDLE
        }

        if oneOnOneEnabled && ASystem.nanoTime() < oneOnOneHumanStealUntilNanos {
            return TripleShotPlayerRenderer.Motion.STEAL
        }

        if oneOnOneEnabled && ASystem.nanoTime() < oneOnOneHumanBlockUntilNanos {
            return TripleShotPlayerRenderer.Motion.BLOCK
        }

        if oneOnOneEnabled &&
            sharedHorseBallOwner != SharedBallOwner.HUMAN &&
            ASystem.nanoTime() < oneOnOneHumanJumpUntilNanos {
            return oneOnOneLooseBallActive
                ? TripleShotPlayerRenderer.Motion.REBOUND
                : TripleShotPlayerRenderer.Motion.BLOCK
        }

        if oneOnOneEnabled && oneOnOneHumanActiveFinish == OneOnOneDriveFinish.DUNK &&
            ASystem.nanoTime() < oneOnOneHumanJumpUntilNanos { return TripleShotPlayerRenderer.Motion.DUNK }

        if shotFrameRunning {
            let elapsedMs: Int64 =
                humanReleaseStartedAtNanos == 0 ? Int64.max
                    : (ASystem.nanoTime() &- humanReleaseStartedAtNanos) / 1_000_000
            return elapsedMs <= Self.PRO_RELEASE_POSE_MS
                ? TripleShotPlayerRenderer.Motion.RELEASE
                : TripleShotPlayerRenderer.Motion.IDLE
        }

        // A live 1v1 gather must visually own the body immediately. Before this branch was below
        // humanWalking, so a player who started HOLD straight out of a swipe could keep showing the
        // DRIBBLE frame while the percentage bar advanced. LOW -> MID -> SET now always wins while
        // the shot is being gathered, matching HORSE / Shooting Challenge.
        if shotGuidesVisible &&
            (oneOnOneEnabled || selectedStation >= 0 || horseHumanStation != nil) {
            if oneOnOneEnabled {
                if let heldOverride = oneOnOneHumanHeldMotionOverride { return heldOverride }
            }
            return preReleaseHumanMotionForPull(pull: pullBack)
        }

        if humanWalking {
            return humanOwnsVisibleBall()
                ? TripleShotPlayerRenderer.Motion.DRIBBLE
                : TripleShotPlayerRenderer.Motion.WALK
        }

        if humanWaitingForTurn {
            return TripleShotPlayerRenderer.Motion.WAITING
        }

        if humanIdleDribbling && humanOwnsVisibleBall() {
            return TripleShotPlayerRenderer.Motion.DRIBBLE
        }

        return TripleShotPlayerRenderer.Motion.IDLE
    }

    func preReleaseHumanMotionForPull(
        pull: Float
    ) -> TripleShotPlayerRenderer.Motion {
        let p = pull.coerceIn(0, 1.20)
        if p < Self.PRO_SHOT_LOW_TO_MID_PULL { return TripleShotPlayerRenderer.Motion.SHOT_LOW }
        if p < Self.PRO_SHOT_MID_TO_SET_PULL { return TripleShotPlayerRenderer.Motion.SHOT_MID }
        return TripleShotPlayerRenderer.Motion.SHOT_SET
    }

    func heldBallPosition(
        motionOverride: TripleShotPlayerRenderer.Motion? = nil
    ) -> APointF {
        // Body and ball always use the same facing. V11 still kept an old Y-based dribble
        // anchor rule here, which made the ball stay on the wrong side after the body flipped.
        let normal = playerRenderer.heldBallPosition(state: humanRendererState(motionOverride: motionOverride))
        let cross = (ASystem.nanoTime() &- humanCrossAt).toFloat() / 420_000_000
        if oneOnOneEnabled && humanOwnsVisibleBall() && !shotGuidesVisible && !shotFrameRunning && cross >= 0 && cross <= 1 {
            let side = humanCrossFrom + (humanDribbleHandSign - humanCrossFrom) * cross
            return APointF(
                playerX + dp(33) * side,
                playerFootY - dp(56) + dp(18) * Float(sin(Double(cross) * Double.pi))
            )
        }
        return normal
    }

    func botRendererState() -> TripleShotPlayerRenderer.State {
        let motion = currentBotMotion()
        let usesSpriteCharacter = TripleShotCharacterVisualCatalog.hasVisuals(characterId: botCharacterId)

        let physicalJumpOffset: Float = oneOnOneEnabled ? oneOnOneBotJumpOffsetPx() : 0
        let jumpOffset: Float
        if oneOnOneEnabled && oneOnOneBotDunkActive {
            jumpOffset = physicalJumpOffset * Self.ONE_ON_ONE_DUNK_RENDER_EXTRA_MULTIPLIER
        } else if oneOnOneEnabled && motion == TripleShotPlayerRenderer.Motion.BLOCK {
            jumpOffset = physicalJumpOffset * Self.ONE_ON_ONE_BLOCK_RENDER_EXTRA_MULTIPLIER
        } else if oneOnOneEnabled && motion == TripleShotPlayerRenderer.Motion.REBOUND {
            jumpOffset = physicalJumpOffset * Self.ONE_ON_ONE_REBOUND_RENDER_EXTRA_MULTIPLIER
        } else {
            jumpOffset = physicalJumpOffset
        }
        let stealOffset = oneOnOneEnabled ? oneOnOneBotStealVisualOffset() : APointF(0, 0)
        let dunkShiftX: Float = oneOnOneBotDunkActive ? oneOnOneBotDunkRenderShiftX : 0
        let dunkLift: Float = oneOnOneBotDunkActive ? oneOnOneBotDunkRenderLiftPx : 0
        // Kotlin argument order for the members with side effects or clock reads.
        let facing = currentBotFacing(motion: motion)
        let moving = botMoveAnimator?.isRunning == true || ASystem.nanoTime() < oneOnOneBotDrivingUntilNanos
        let movingFast = oneOnOneEnabled && ASystem.nanoTime() < oneOnOneBotDrivingUntilNanos
        let visualScale: Float =
            oneOnOneEnabled && oneOnOneBotDunkActive ? 1
                : oneOnOneVisualScale(motion: motion)
        let mirrorX = currentBotMirrorX(motion: motion)
        // `dribblePhase01` is deliberately not set (stays 0), as on Android: the bot ball does not bounce in 3D.
        return stableSoloState(raw: TripleShotPlayerRenderer.State(
            x: botX + dunkShiftX + stealOffset.x,
            footY: botFootY - jumpOffset - dunkLift + stealOffset.y,
            fineAim: botFineAim,
            pullBack: botPullBack,
            dribbleBouncePx: botDribbleBouncePx,
            hotHand: botHotHand,
            style: TripleShotPlayerRenderer.Style.BOT,
            pose: botEndPose,
            celebrationProgress: matchCelebrationProgress,
            shotStyle:
                usesSpriteCharacter
                    ? TripleShotPlayerRenderer.ShotStyle.PRO
                    : TripleShotPlayerRenderer.ShotStyle.GRANNY,
            facing: facing,
            motion: motion,
            dribbleHandSign: botDribbleHandSign,
            moving: moving,
            movingFast: movingFast,
            characterId: botCharacterId,
            mirrorX: mirrorX,
            actionFrameIndex: motion == TripleShotPlayerRenderer.Motion.DUNK ? oneOnOneBotDunkFrameIndex : -1,
            visualScale: visualScale
        ), human: false)
    }

    /**
     * 1v1 sprites were reading about 10% smaller than their court/world proportions in normal play.
     * Keep the existing dunk scale untouched for the intended "wow" moment; enlarge only the normal
     * 1v1 body/action states. HORSE and Shooting Challenge are deliberately unaffected.
     */
    func oneOnOneVisualScale(motion: TripleShotPlayerRenderer.Motion) -> Float {
        return !oneOnOneEnabled || motion == TripleShotPlayerRenderer.Motion.DUNK ? 1 : 1.10
    }

    func currentBotMotion() -> TripleShotPlayerRenderer.Motion {
        if botEndPose != TripleShotPlayerRenderer.Pose.NORMAL {
            return TripleShotPlayerRenderer.Motion.IDLE
        }

        if oneOnOneEnabled && ASystem.nanoTime() < oneOnOneBotStealUntilNanos {
            return TripleShotPlayerRenderer.Motion.STEAL
        }

        if oneOnOneEnabled && oneOnOneBotDunkActive {
            return oneOnOneBotDunkReleasedPose
                ? TripleShotPlayerRenderer.Motion.BLOCK
                : TripleShotPlayerRenderer.Motion.DUNK
        }

        if oneOnOneEnabled &&
            sharedHorseBallOwner != SharedBallOwner.BOT &&
            ASystem.nanoTime() < oneOnOneBotJumpUntilNanos {
            return oneOnOneLooseBallActive
                ? TripleShotPlayerRenderer.Motion.REBOUND
                : TripleShotPlayerRenderer.Motion.BLOCK
        }

        if botShotFrameRunning {
            return TripleShotPlayerRenderer.Motion.RELEASE
        }

        if botPullBack > 0.015 {
            return preReleaseHumanMotionForPull(pull: botPullBack)
        }

        if (botMoveAnimator?.isRunning == true || ASystem.nanoTime() < oneOnOneBotDrivingUntilNanos) && botBallVisible {
            return TripleShotPlayerRenderer.Motion.DRIBBLE
        }

        return TripleShotPlayerRenderer.Motion.IDLE
    }

    func isBotShotMotion(motion: TripleShotPlayerRenderer.Motion) -> Bool {
        return motion == TripleShotPlayerRenderer.Motion.SHOT_LOW ||
            motion == TripleShotPlayerRenderer.Motion.SHOT_MID ||
            motion == TripleShotPlayerRenderer.Motion.SHOT_SET ||
            motion == TripleShotPlayerRenderer.Motion.RELEASE
    }

    /// Bot facing chain. Side effect: the court-Y rule sets `botCourtFacing` (no hysteresis).
    func currentBotFacing(
        motion: TripleShotPlayerRenderer.Motion
    ) -> TripleShotPlayerRenderer.Facing {
        if !oneOnOneEnabled { return currentBotShotFacing() }
        let spinAge = ASystem.nanoTime() &- botSpinAt
        if oneOnOneEnabled && sharedHorseBallOwner == SharedBallOwner.BOT && spinAge >= 0 && spinAge <= 360_000_000 {
            switch ((ASystem.nanoTime() &- botSpinAt) / 90_000_000).toInt() {
            case 0, 2: return TripleShotPlayerRenderer.Facing.SIDE
            case 1: return TripleShotPlayerRenderer.Facing.BACK
            default: return TripleShotPlayerRenderer.Facing.FRONT
            }
        }

        if oneOnOneEnabled && oneOnOneBotDunkActive {
            return oneOnOneBotDunkFacing
        }

        if oneOnOneEnabled && isOneOnOneActionMotion(motion: motion) {
            let targetX = oneOnOneLooseBallActive ? ballX : playerX
            let targetY = oneOnOneLooseBallActive ? ballY : playerFootY
            return oneOnOneActionFacing(actorX: botX, actorFootY: botFootY, targetX: targetX, targetY: targetY)
        }

        if oneOnOneEnabled && sharedHorseBallOwner == SharedBallOwner.HUMAN {
            if shotFrameRunning {
                let elapsed = physicsState?.elapsedSeconds ?? 0
                let stillBlocking =
                    oneOnOneBotContestActive &&
                        (ASystem.nanoTime() < oneOnOneBotJumpUntilNanos ||
                            elapsed <= Self.ONE_ON_ONE_DEFENSE_BLOCK_EARLY_FLIGHT_SECONDS)
                if stillBlocking {
                    return oneOnOneDefenderFacing(
                        defenderX: botX,
                        defenderFootY: botFootY,
                        ballHandlerX: playerX,
                        ballHandlerFootY: playerFootY
                    )
                }
                return oneOnOneHoopFacingFor(footY: botFootY)
            }
            return oneOnOneDefenderFacing(
                defenderX: botX,
                defenderFootY: botFootY,
                ballHandlerX: playerX,
                ballHandlerFootY: playerFootY
            )
        }

        if oneOnOneEnabled && oneOnOneLooseBallActive {
            return oneOnOneHoopFacingFor(footY: botFootY)
        }

        if isBotShotMotion(motion: motion) {
            return currentBotShotFacing()
        }

        if width <= 0 || height <= 0 { return botCourtFacing }
        let t = backgroundTransform()
        if t.scaleY <= 0 { return botCourtFacing }

        let sourceY =
            ((botFootY - t.offsetY) / t.scaleY)
                .coerceIn(0, Self.BACKGROUND_HEIGHT)

        botCourtFacing =
            sourceY <= Self.SRC_FACING_DIVIDER_Y
                ? TripleShotPlayerRenderer.Facing.FRONT
                : TripleShotPlayerRenderer.Facing.BACK

        return botCourtFacing
    }

    func isOneOnOneActionMotion(
        motion: TripleShotPlayerRenderer.Motion
    ) -> Bool {
        return motion == TripleShotPlayerRenderer.Motion.STEAL ||
            motion == TripleShotPlayerRenderer.Motion.BLOCK ||
            motion == TripleShotPlayerRenderer.Motion.REBOUND ||
            motion == TripleShotPlayerRenderer.Motion.DUNK
    }

    /**
     * Action art has BACK / FRONT / SIDE. Unlike the idle defender, an active reach/jump should
     * visibly point toward the ball/opponent. SIDE is selected only when the horizontal target
     * component is strong enough to read clearly; the renderer mirrors that one authored side.
     */
    func oneOnOneActionFacing(
        actorX: Float,
        actorFootY: Float,
        targetX: Float,
        targetY: Float
    ) -> TripleShotPlayerRenderer.Facing {
        let dx = targetX - actorX
        let dy = targetY - actorFootY

        /*
         * Depth has priority over SIDE for steal/block/rebound. If the defender is closer to the
         * camera than the attacker (larger screen Y), we must see the defender's BACK as they reach
         * up-court toward the ball-handler. Likewise an actor above the target shows FRONT.
         *
         * SIDE is reserved for roughly level actors. The previous SIDE-first test could select the
         * front/side crop even when the defender was clearly between attacker and camera.
         */
        if dy <= -dp(Self.ONE_ON_ONE_ACTION_DEPTH_PRIORITY_DP) {
            return TripleShotPlayerRenderer.Facing.BACK
        }
        if dy >= dp(Self.ONE_ON_ONE_ACTION_DEPTH_PRIORITY_DP) {
            return TripleShotPlayerRenderer.Facing.FRONT
        }
        if abs(dx) >= dp(Self.ONE_ON_ONE_ACTION_SIDE_MIN_DX_DP) {
            return TripleShotPlayerRenderer.Facing.SIDE
        }
        return dy >= 0
            ? TripleShotPlayerRenderer.Facing.FRONT
            : TripleShotPlayerRenderer.Facing.BACK
    }

    /**
     * With the current art pack defenders only have FRONT/BACK idle families. When the ball handler
     * is roughly level with the defender, FRONT is the least surprising defensive stance; BACK is
     * reserved for the clear case where the handler is farther up-court. This prevents a defender
     * standing beside the attacker from inexplicably turning toward the scenery.
     */
    func oneOnOneDefenderFacing(
        defenderX: Float,
        defenderFootY: Float,
        ballHandlerX: Float,
        ballHandlerFootY: Float
    ) -> TripleShotPlayerRenderer.Facing {
        if width <= 0 || height <= 0 { return TripleShotPlayerRenderer.Facing.FRONT }

        // With only FRONT/BACK defensive artwork, the reliable question is not where the hoop is;
        // it is where the ball-handler is relative to the defender on the screen. While the
        // opponent owns the ball the defender must visually face THEM, even when standing between
        // them and the basket. Horizontal position never flips FRONT/BACK here.
        return ballHandlerFootY >= defenderFootY
            ? TripleShotPlayerRenderer.Facing.FRONT
            : TripleShotPlayerRenderer.Facing.BACK
    }

    func oneOnOneHoopFacingFor(footY: Float) -> TripleShotPlayerRenderer.Facing {
        if width <= 0 || height <= 0 { return TripleShotPlayerRenderer.Facing.BACK }
        let hoop = sourcePointToView(sourceX: Self.SRC_HOOP_CENTER_X, sourceY: Self.SRC_HOOP_DEPTH_FOOT_Y)
        return footY > hoop.y + dp(Self.ONE_ON_ONE_HOOP_FACING_TOLERANCE_DP)
            ? TripleShotPlayerRenderer.Facing.BACK
            : TripleShotPlayerRenderer.Facing.FRONT
    }

    func currentBotMirrorX(
        motion: TripleShotPlayerRenderer.Motion
    ) -> Bool {
        if !oneOnOneEnabled {
            return currentBotShotFacing() == TripleShotPlayerRenderer.Facing.SIDE &&
                hoopScreenDirection(actorX: botX, actorFootY: botFootY).x < 0
        }

        if oneOnOneEnabled && oneOnOneBotDunkActive {
            return oneOnOneBotDunkMirrorX
        }

        if currentBotFacing(motion: motion) != TripleShotPlayerRenderer.Facing.SIDE { return false }
        if oneOnOneEnabled && motion == TripleShotPlayerRenderer.Motion.STEAL {
            let facing = currentBotFacing(motion: motion)
            if facing != TripleShotPlayerRenderer.Facing.SIDE {
                let liveBall = oneOnOneLooseBallActive ? APointF(ballX, ballY) : heldBallPosition()
                return liveBall.x > botX
            }
        }

        if oneOnOneEnabled &&
            isOneOnOneActionMotion(motion: motion) &&
            currentBotFacing(motion: motion) == TripleShotPlayerRenderer.Facing.SIDE {
            let targetX = oneOnOneLooseBallActive ? ballX : playerX
            return targetX < botX
        }

        if motion == TripleShotPlayerRenderer.Motion.DRIBBLE && oneOnOneEnabled {
            return botDribbleHandSign < 0
        }
        if !isBotShotMotion(motion: motion) || width <= 0 || height <= 0 { return false }

        let hoop = sourcePointToView(sourceX: Self.SRC_HOOP_CENTER_X, sourceY: Self.SRC_HOOP_PLANE_Y)
        let dx = hoop.x - botX
        return currentBotFacing(motion: motion) == TripleShotPlayerRenderer.Facing.SIDE &&
            dx < -dp(Self.FACING_HORIZONTAL_DEAD_ZONE_DP)
    }

    func heldBotBallPosition() -> APointF {
        let normal = playerRenderer.heldBallPosition(state: botRendererState())
        let t = (ASystem.nanoTime() &- botCrossAt).toFloat() / 420_000_000
        if oneOnOneEnabled && sharedHorseBallOwner == SharedBallOwner.BOT && !botShotFrameRunning && botPullBack == 0 &&
            t >= 0 && t <= 1 {
            return APointF(
                botX + dp(33) * (botCrossFrom + (botDribbleHandSign - botCrossFrom) * t),
                botFootY - dp(56) + dp(18) * Float(sin(Double(t) * Double.pi))
            )
        }
        return normal
    }

    func setPlayerPosition(
        x: Float,
        y: Float,
        animate: Bool,
        onEnd: (() -> Void)? = nil
    ) {
        playerMoveAnimator?.cancel()
        cancelHumanIdleDribble()

        if !animate || width == 0 {
            humanWalking = false
            resetHumanMovementSpeed()
            playerX = x
            playerFootY = y
            invalidate()
            onEnd?()
            return
        }

        let startX = playerX
        let startY = playerFootY

        beginHumanMovementDribble()
        let animator = AValueAnimator.ofFloat(0, 1)
        // V9: slowed a little further so the move and dribble are readable,
        // while remaining short enough for a timed shooting challenge.
        animator.duration = walkingDuration(x: startX, y: startY, tx: x, ty: y)
        animator.interpolator = ALinearInterpolator()

        animator.addUpdateListener { [weak self] it in
            guard let self = self else { return }
            let fraction = it.animatedValueFloat
            let oldFrameX = self.playerX
            let oldFrameY = self.playerFootY
            self.playerX = self.lerp(startX, x, fraction)
            self.playerFootY = self.lerp(startY, y, fraction)

            let frameDx = self.playerX - oldFrameX
            let frameDy = self.playerFootY - oldFrameY
            self.updateHumanMovementSpeed(distancePx: ksqrt(frameDx * frameDx + frameDy * frameDy))

            // Two complete dribbles during the move. Slow travel crosses hand-to-hand;
            // fast travel keeps one hand and the same-side shoe path.
            let bounceCycles = fraction * Self.DRIBBLE_BOUNCES_DURING_MOVE.toFloat()
            let bounceIndex =
                floor(bounceCycles)
                    .toInt()
                    .coerceAtMost(Self.DRIBBLE_BOUNCES_DURING_MOVE.toInt() - 1)
            self.updateMovingDribbleBounceIndex(newIndex: bounceIndex)
            self.humanDribblePhase01 = (bounceCycles - floor(bounceCycles))
                .coerceIn(0, 1)
            // Kotlin `fraction * Math.PI * DRIBBLE_BOUNCES_DURING_MOVE` is a Double expression.
            self.dribbleBouncePx =
                Float(abs(sin(Double(fraction) * Double.pi * Self.DRIBBLE_BOUNCES_DURING_MOVE))) *
                    self.dp(Self.DRIBBLE_BOUNCE_AMPLITUDE_DP)
            if self.humanOwnsVisibleBall() {
                self.ballRotationDeg = (fraction * 720).truncatingRemainder(dividingBy: 360)
            }

            self.invalidate()
        }

        // The Kotlin listener object's `private var cancelled`; both closures share this variable.
        var cancelled = false
        animator.addListener(AAnimatorListenerAdapter(
            onEnd: { [weak self] _ in
                guard let self = self else { return }
                self.humanWalking = false
                self.dribbleBouncePx = 0
                self.humanDribblePhase01 = 0
                // Stay on the hand used by the final walking bounce; do not snap sides.
                self.humanDribbleHandSign = self.humanWalkingDribbleHandSign
                self.resetHumanMovementSpeed()
                if self.sharedHorseBallOwner == SharedBallOwner.HUMAN { self.scheduleHumanIdleDribble() }
                self.invalidate()
                if !cancelled {
                    onEnd?()
                }
            },
            onCancel: { [weak self] _ in
                cancelled = true
                guard let self = self else { return }
                self.humanWalking = false
                self.dribbleBouncePx = 0
                self.humanDribblePhase01 = 0
                self.resetHumanMovementSpeed()
            }
        ))

        animator.start()
        playerMoveAnimator = animator
    }

    func setBotPosition(
        x: Float,
        y: Float,
        animate: Bool,
        onEnd: (() -> Void)? = nil
    ) {
        botMoveAnimator?.cancel()

        if !animate || width == 0 {
            botX = x
            botFootY = y
            botDribbleBouncePx = 0
            invalidate()
            onEnd?()
            return
        }

        let startX = botX
        let startY = botFootY

        let animator = AValueAnimator.ofFloat(0, 1)
        animator.duration = walkingDuration(x: startX, y: startY, tx: x, ty: y)
        animator.interpolator = ALinearInterpolator()

        animator.addUpdateListener { [weak self] it in
            guard let self = self else { return }
            let fraction = it.animatedValueFloat
            self.botX = self.lerp(startX, x, fraction)
            self.botFootY = self.lerp(startY, y, fraction)
            if self.oneOnOneEnabled {
                self.resolveBotHumanBodyCollision()
            }
            self.botDribbleBouncePx =
                Float(abs(sin(Double(fraction) * Double.pi * Self.DRIBBLE_BOUNCES_DURING_MOVE))) *
                    self.dp(Self.DRIBBLE_BOUNCE_AMPLITUDE_DP)
            self.invalidate()
        }

        var cancelled = false
        animator.addListener(AAnimatorListenerAdapter(
            onEnd: { [weak self] _ in
                guard let self = self else { return }
                self.botDribbleBouncePx = 0
                self.invalidate()
                if !cancelled {
                    onEnd?()
                }
            },
            onCancel: { [weak self] _ in
                cancelled = true
                guard let self = self else { return }
                self.botDribbleBouncePx = 0
                self.invalidate()
            }
        ))

        animator.start()
        botMoveAnimator = animator
    }

    func horseStationById(id: String) -> Station? {
        return horseCustomSpots[id]
            ?? Self.SHOT_SPOT_CATALOG.first { $0.id == id }
    }

    func chooseHorseWaitingStation(
        avoidSpotId: String,
        seed: Int64,
        preferLeft: Bool
    ) -> Station {
        let avoid = horseStationById(id: avoidSpotId)
        let random = KotlinRandom(seed: seed ^ Self.HORSE_WAIT_SEED_SALT)

        let candidates = Self.BOT_SPOT_CATALOG
            .filter { candidate in
                avoid == nil || sourceDistanceSquared(a: candidate, b: avoid!) >= Self.HORSE_WAIT_MIN_DISTANCE_SQ
            }
            .filter { candidate in
                preferLeft ? candidate.sourceX < Self.SRC_CENTER_X : candidate.sourceX > Self.SRC_CENTER_X
            }
            .kShuffled(random)

        // The fallback shuffle continues the same generator (it runs only when the first list is empty).
        return candidates.first
            ?? Self.BOT_SPOT_CATALOG
                .filter { candidate in
                    avoid == nil || sourceDistanceSquared(a: candidate, b: avoid!) >= Self.HORSE_WAIT_MIN_DISTANCE_SQ
                }
                .kShuffled(random)
                .first
            ?? Self.BOT_SPOT_CATALOG.first!
    }

    func chooseChallengeWaitingStation(avoid: Station, seed: Int64) -> Station {
        let random = KotlinRandom(seed: seed ^ Self.CHALLENGE_WAIT_SEED_SALT)
        let preferLeft = avoid.sourceX >= Self.SRC_CENTER_X
        let candidates =
            Self.BOT_SPOT_CATALOG
                .filter { sourceDistanceSquared(a: $0, b: avoid) >= Self.HORSE_WAIT_MIN_DISTANCE_SQ }
                .filter { preferLeft ? $0.sourceX < Self.SRC_CENTER_X : $0.sourceX > Self.SRC_CENTER_X }
                .kShuffled(random)

        return candidates.first
            ?? Self.BOT_SPOT_CATALOG
                .filter { sourceDistanceSquared(a: $0, b: avoid) >= Self.HORSE_WAIT_MIN_DISTANCE_SQ }
                .kShuffled(random)
                .first
            ?? Self.BOT_SPOT_CATALOG.first!
    }

    func chooseBotStation(seed: Int64) -> Station {
        let random = KotlinRandom(seed: seed ^ Self.BOT_SPOT_SEED_SALT)
        let candidates = Self.BOT_SPOT_CATALOG.kShuffled(random)

        func isFarEnoughFromHuman(station: Station) -> Bool {
            let p = botStationScreenPoint(station: station)
            let minDistance = dp(Self.BOT_HUMAN_MIN_DISTANCE_DP)
            let minDistanceSq = minDistance * minDistance

            let currentDx = p.x - playerX
            let currentDy = p.y - playerFootY
            if currentDx * currentDx + currentDy * currentDy < minDistanceSq {
                return false
            }

            // The human snaps back to this neutral reading position when the next question
            // appears, so keep the bot away from it as well to prevent character overlap.
            let defaultPoint = defaultPlayerScreenPoint()
            let defaultDx = p.x - defaultPoint.x
            let defaultDy = p.y - defaultPoint.y
            return defaultDx * defaultDx + defaultDy * defaultDy >= minDistanceSq
        }

        return candidates.first {
            !recentBotSpotIds.contains($0.id) && isFarEnoughFromHuman(station: $0)
        } ?? candidates.first {
            isFarEnoughFromHuman(station: $0)
        } ?? candidates.first!
    }

    func rememberBotSpot(id: String) {
        if let index = recentBotSpotIds.firstIndex(of: id) { recentBotSpotIds.remove(at: index) }
        recentBotSpotIds.append(id)
        while recentBotSpotIds.count > Self.BOT_RECENT_SPOT_MEMORY {
            recentBotSpotIds.remove(at: 0)
        }
    }

    /**
     * Logical answer index -> visual court station.
     *
     * (The Kotlin KDoc claims Hebrew mirrors the stations; the code does not, and neither does this port.)
     */
    func stationForAnswer(index: Int, count: Int) -> Station {
        let safeCount = count.coerceIn(2, 4)
        let logical = index.coerceIn(0, safeCount - 1)

        if activeStations.count >= safeCount {
            return activeStations[logical]
        }

        /*
         * Safe fallback used only before prepareAnswerSpots() has run.
         * Once the Fragment prepares the current question, logical A/B/C/D is mapped
         * directly to the curated 2D spot chosen for that answer.
         */
        switch safeCount {
        case 2:
            switch logical {
            case 0: return Station(id: "fallback_2a", sourceX: 315, sourceY: 1135, distanceDifficulty: 0.44, zone: "court")
            default: return Station(id: "fallback_2b", sourceX: 650, sourceY: 1085, distanceDifficulty: 0.58, zone: "court")
            }

        case 3:
            switch logical {
            case 0: return Station(id: "fallback_3a", sourceX: 240, sourceY: 1110, distanceDifficulty: 0.34, zone: "court")
            case 1: return Station(id: "fallback_3b", sourceX: 505, sourceY: 1190, distanceDifficulty: 0.78, zone: "court")
            default: return Station(id: "fallback_3c", sourceX: 710, sourceY: 1045, distanceDifficulty: 0.56, zone: "court_edge")
            }

        default:
            switch logical {
            case 0: return Station(id: "fallback_4a", sourceX: 205, sourceY: 1045, distanceDifficulty: 0.32, zone: "left_edge")
            case 1: return Station(id: "fallback_4b", sourceX: 380, sourceY: 1180, distanceDifficulty: 0.64, zone: "court")
            case 2: return Station(id: "fallback_4c", sourceX: 560, sourceY: 1110, distanceDifficulty: 0.72, zone: "court")
            default: return Station(id: "fallback_4d", sourceX: 760, sourceY: 1005, distanceDifficulty: 0.58, zone: "right_edge")
            }
        }
    }

    func stationScreenPoint(index: Int, count: Int) -> APointF {
        let station = stationForAnswer(index: index, count: count)
        let p = sourcePointToView(sourceX: station.sourceX, sourceY: station.sourceY)

        let safeX = p.x.coerceIn(dp(28), width.toFloat() - dp(28))

        /*
         * The old fixed "height - 205dp" limit worked only for one bottom-UI arrangement.
         * V7 receives the real answerStrip.top from the Fragment, so markers remain visibly
         * above the answer buttons even when the question is 1, 2 or 3 lines or on a tablet.
         */
        let maxFootY =
            gameplayBottomBoundaryPx
                .map { $0 - dp(Self.PLAYER_TO_ANSWER_GAP_DP) }
                ?? (height.toFloat() - dp(46))

        let minFootY = height.toFloat() * 0.48
        let safeMax = kmax(minFootY + dp(1), maxFootY)
        let safeY = p.y.coerceIn(minFootY, safeMax)

        return APointF(safeX, safeY)
    }

    func botStationScreenPoint(station: Station) -> APointF {
        let p = sourcePointToView(sourceX: station.sourceX, sourceY: station.sourceY)

        // A human-created HORSE spot is already guaranteed to be inside the lower-60%
        // free-move area. Preserve that exact location for both players instead of applying
        // the older answer-marker clamp (which starts lower at 48% of the screen).
        if station.zone == "horse_free" {
            let safeX = p.x.coerceIn(horseFreeMinX(), horseFreeMaxX())
            return APointF(
                safeX,
                clampHorseFreeY(x: safeX, y: p.y)
            )
        }

        let safeX = p.x.coerceIn(dp(28), width.toFloat() - dp(28))

        let maxFootY =
            gameplayBottomBoundaryPx
                .map { $0 - dp(Self.PLAYER_TO_ANSWER_GAP_DP) }
                ?? (height.toFloat() - dp(46))

        let minFootY = height.toFloat() * 0.48
        let safeMax = kmax(minFootY + dp(1), maxFootY)
        let safeY = p.y.coerceIn(minFootY, safeMax)

        return APointF(safeX, safeY)
    }

    func defaultPlayerScreenPoint() -> APointF {
        let p = sourcePointToView(sourceX: Self.SRC_CENTER_X, sourceY: Self.SRC_DEFAULT_PLAYER_Y)

        let maxFootY =
            gameplayBottomBoundaryPx
                .map { $0 - dp(Self.PLAYER_TO_ANSWER_GAP_DP) }
                ?? (height.toFloat() - dp(46))

        let minFootY = height.toFloat() * 0.48
        let safeMax = kmax(minFootY + dp(1), maxFootY)

        return APointF(
            p.x.coerceIn(dp(28), kmax(dp(29), width.toFloat() - dp(28))),
            p.y.coerceIn(minFootY, safeMax)
        )
    }

    func buildPhysicsGeometry() -> TripleShotPhysics.Geometry {
        let t = backgroundTransform()

        let hoopCenter = sourcePointToView(sourceX: Self.SRC_HOOP_CENTER_X, sourceY: Self.SRC_HOOP_PLANE_Y, transform: t)
        let leftRim = sourcePointToView(sourceX: Self.SRC_RIM_LEFT_X, sourceY: Self.SRC_HOOP_PLANE_Y, transform: t)
        let rightRim = sourcePointToView(sourceX: Self.SRC_RIM_RIGHT_X, sourceY: Self.SRC_HOOP_PLANE_Y, transform: t)

        return TripleShotPhysics.Geometry(
            gravityPxPerSec2: height.toFloat() * 1.52,
            hoopCenterX: hoopCenter.x,
            hoopY: hoopCenter.y,
            leftRimX: leftRim.x,
            rightRimX: rightRim.x,
            rimColliderRadius: kmax(dp(2.5), kmin(t.scaleX, t.scaleY) * 5.5),
            backboardX: sourceXToView(x: Self.SRC_BACKBOARD_COLLISION_X, transform: t),
            backboardTopY: sourceYToView(y: Self.SRC_BACKBOARD_TOP_Y, transform: t),
            backboardBottomY: sourceYToView(y: Self.SRC_BACKBOARD_BOTTOM_Y, transform: t),
            netBottomY: sourceYToView(y: Self.SRC_NET_BOTTOM_Y, transform: t),
            netBottomLeftX: sourceXToView(x: Self.SRC_NET_BOTTOM_LEFT_X, transform: t),
            netBottomRightX: sourceXToView(x: Self.SRC_NET_BOTTOM_RIGHT_X, transform: t),
            ballRadius: dp(Self.BALL_PHYSICS_RADIUS_DP)
        )
    }

    func aimRangePx() -> Float {
        return backgroundTransform().scaleX * Self.SRC_AIM_RANGE_X
    }

    /**
     * Shared photo/physics transform.
     *
     * A 1024x1536 image is wider than a modern 9:20 portrait screen. Plain CENTER_CROP
     * therefore throws away a lot of the left/right court. We keep full-height coverage,
     * squeeze X by only 8% (visually subtle) and intentionally anchor the crop to the
     * RIGHT edge of the artwork. The left forest is less gameplay-critical; the complete
     * backboard / pole area is not.
     *
     * Crucially, applyBackgroundTransformTo() uses this same transform for the ImageView,
     * so the rim/backboard physics never drift away from the visible photo.
     */
    func backgroundTransform() -> BackgroundTransform {
        if width <= 0 || height <= 0 {
            return BackgroundTransform(
                scaleX: 1,
                scaleY: 1,
                offsetX: 0,
                offsetY: 0
            )
        }

        /*
         * LANDSCAPE uses the full logical court instead of CENTER_CROP. X and Y are deliberately
         * scaled independently so the established 1024x1536 basketball geometry can fill a wide
         * 16:9 court. New landscape artwork must follow the same normalized landmark positions;
         * that gives substantially more lateral room without rewriting 1v1 physics in this pass.
         */
        if resources.configuration.orientation == AConfiguration.ORIENTATION_LANDSCAPE {
            return BackgroundTransform(
                scaleX: width.toFloat() / Self.BACKGROUND_WIDTH,
                scaleY: height.toFloat() / Self.BACKGROUND_HEIGHT,
                offsetX: 0,
                offsetY: 0
            )
        }

        let baseScale =
            kmax(
                height.toFloat() / Self.BACKGROUND_HEIGHT,
                width.toFloat() / (Self.BACKGROUND_WIDTH * Self.BACKGROUND_HORIZONTAL_SCALE)
            )

        let scaleY = baseScale
        let scaleX = baseScale * Self.BACKGROUND_HORIZONTAL_SCALE

        let scaledWidth = Self.BACKGROUND_WIDTH * scaleX
        let scaledHeight = Self.BACKGROUND_HEIGHT * scaleY

        let overflowX = (scaledWidth - width.toFloat()).coerceAtLeast(0)
        let overflowY = (scaledHeight - height.toFloat()).coerceAtLeast(0)

        return BackgroundTransform(
            scaleX: scaleX,
            scaleY: scaleY,
            offsetX: -overflowX * Self.BACKGROUND_HORIZONTAL_FOCUS,
            offsetY: -overflowY * 0.5
        )
    }

    func sourcePointToView(
        sourceX: Float,
        sourceY: Float,
        transform: BackgroundTransform
    ) -> APointF {
        return APointF(
            sourceXToView(x: sourceX, transform: transform),
            sourceYToView(y: sourceY, transform: transform)
        )
    }

    /// Kotlin default argument `transform: BackgroundTransform = backgroundTransform()`.
    func sourcePointToView(sourceX: Float, sourceY: Float) -> APointF {
        return sourcePointToView(sourceX: sourceX, sourceY: sourceY, transform: backgroundTransform())
    }

    func sourceXToView(
        x: Float,
        transform: BackgroundTransform
    ) -> Float {
        return transform.offsetX + x * transform.scaleX
    }

    func sourceYToView(
        y: Float,
        transform: BackgroundTransform
    ) -> Float {
        return transform.offsetY + y * transform.scaleY
    }

    /// `impactSpeed` is a physics impact speed in view px/s (the callers' thresholds are px/s too).
    func triggerRimShake(impactSpeed: Float) {
        rimShakeStartedAtNanos = ASystem.nanoTime()
        rimShakeAmplitudePx =
            (impactSpeed / 520 * dp(3.5))
                .coerceIn(dp(1.1), dp(5.5))
    }

    func currentRimShakeOffset() -> Float {
        if rimShakeStartedAtNanos == 0 { return 0 }

        let age =
            ((ASystem.nanoTime() &- rimShakeStartedAtNanos).toDouble() / 1_000_000_000.0).toFloat()

        if age >= Self.RIM_SHAKE_SECONDS { return 0 }

        return (
            ksin(age * 47) *
                kexp(-age * 7.5) *
                rimShakeAmplitudePx
        )
    }

    func triggerNetKick(
        impactSpeed: Float,
        directionHint: Float
    ) {
        netKickStartedAtNanos = ASystem.nanoTime()
        netKickAmplitudePx =
            (impactSpeed / 420 * dp(8))
                .coerceIn(dp(2.2), dp(12))
        if directionHint > 0.5 {
            netKickDirection = 1
        } else if directionHint < -0.5 {
            netKickDirection = -1
        } else {
            netKickDirection = 1
        }
    }

    /// Damped sway in px; only `.x` is exported to the snapshot.
    func currentNetKickOffset() -> APointF {
        if netKickStartedAtNanos == 0 { return APointF(0, 0) }

        let age =
            ((ASystem.nanoTime() &- netKickStartedAtNanos).toDouble() / 1_000_000_000.0).toFloat()

        if age >= Self.NET_KICK_SECONDS { return APointF(0, 0) }

        let decay = kexp(-age * 5.3)
        return APointF(
            ksin(age * 24) * netKickAmplitudePx * 0.80 * decay * netKickDirection,
            ksin(age * 15).coerceAtLeast(0) * netKickAmplitudePx * decay
        )
    }

    /// Arms the Live replay capture. Only `animateShot` calls it; `animateHorseShot` (the only Live HORSE path)
    /// does not, so Live HORSE shot events carry no samples (Android behaviour, spec 10 section 8.7).
    func beginLiveReplayCapture() {
        liveReplaySamples.removeAll()
        liveReplayStartedAtNanos = liveReplayCaptureEnabled ? ASystem.nanoTime() : 0
        liveReplayLastSampleMs = -Self.LIVE_REPLAY_SAMPLE_INTERVAL_MS
        if liveReplayCaptureEnabled {
            captureLiveReplaySample(force: true)
        }
    }

    func captureLiveReplaySample(force: Bool) {
        if !liveReplayCaptureEnabled || liveReplayStartedAtNanos == 0 || width <= 0 || height <= 0 {
            return
        }
        let elapsedMs =
            ((ASystem.nanoTime() &- liveReplayStartedAtNanos) / 1_000_000).coerceAtLeast(0)
        if !force && elapsedMs &- liveReplayLastSampleMs < Self.LIVE_REPLAY_SAMPLE_INTERVAL_MS {
            return
        }

        let t = backgroundTransform()
        let sourceX = (ballX - t.offsetX) / t.scaleX
        let sourceY = (ballY - t.offsetY) / t.scaleY
        let sample = ShotReplaySample(
            tMs: elapsedMs,
            x: sourceX,
            y: sourceY,
            depth: 0
        )

        if liveReplaySamples.count >= Self.LIVE_MAX_REPLAY_SAMPLES {
            if force {
                liveReplaySamples[liveReplaySamples.count - 1] = sample
                liveReplayLastSampleMs = elapsedMs
            }
            return
        }

        liveReplaySamples.append(sample)
        liveReplayLastSampleMs = elapsedMs
    }

    /**
     * TripleShotPhysics already performs the real rim/backboard collision. 1v1 applies only a
     * small post-impact energy loss before handing the ball to the rebound phase. This is not a
     * screen-edge patch: direction still comes entirely from the physical collision normal.
     */
    func dampOneOnOneShotImpact(
        state: TripleShotPhysics.ShotState,
        result: TripleShotPhysics.StepResult,
        finish: OneOnOneDriveFinish
    ) {
        let closeFinish = finish != OneOnOneDriveFinish.JUMPER
        if result.rimImpactSpeed > 0 {
            let damping =
                closeFinish ? Self.ONE_ON_ONE_CLOSE_FINISH_RIM_DAMPING
                    : Self.ONE_ON_ONE_RIM_POST_IMPACT_DAMPING
            state.vx *= damping
            state.vy *= damping
        } else if result.backboardImpactSpeed > 0 {
            let xDamping =
                closeFinish ? Self.ONE_ON_ONE_CLOSE_FINISH_BOARD_X_DAMPING
                    : Self.ONE_ON_ONE_BOARD_POST_IMPACT_X_DAMPING
            let yDamping =
                closeFinish ? Self.ONE_ON_ONE_CLOSE_FINISH_BOARD_Y_DAMPING
                    : Self.ONE_ON_ONE_BOARD_POST_IMPACT_Y_DAMPING
            state.vx *= xDamping
            state.vy *= yDamping
        }
    }

    /**
     * Transition a miss to the loose-ball/rebound simulation soon after its REAL contact with the
     * rim/backboard. Waiting until the ball was 105dp below the net let it keep full shot velocity
     * for too long and was a major reason rebounds crossed the screen. Airballs get a later handoff.
     */
    func oneOnOneShotReadyForLooseBall(
        state: TripleShotPhysics.ShotState,
        geometry: TripleShotPhysics.Geometry
    ) -> Bool {
        if !oneOnOneEnabled || state.made || state.vy <= 0 { return false }

        let touchedBasket = state.rimHits > 0 || state.backboardHits > 0
        if touchedBasket {
            return state.elapsedSeconds >= Self.ONE_ON_ONE_IMPACT_REBOUND_MIN_SECONDS &&
                state.y >= geometry.hoopY + geometry.ballRadius * 2.2
        } else {
            return state.elapsedSeconds >= Self.ONE_ON_ONE_AIRBALL_REBOUND_MIN_SECONDS &&
                state.y >= geometry.netBottomY + dp(Self.ONE_ON_ONE_AIRBALL_RELEASE_BELOW_NET_DP)
        }
    }

    /**
     * The strict shared physics make test is intentionally conservative. In free 1v1 camera angles
     * a ball can visually pass through the centre of the rim/net while missing that test by a few
     * pixels. This 1v1-only fallback is still geometric: it requires a downward rim-plane crossing
     * with the ball centre genuinely inside the opening. It never turns a side-net graze into a make.
     * Mutates `state.made`.
     */
    func maybeMarkOneOnOneRelaxedMake(
        state: TripleShotPhysics.ShotState,
        geometry: TripleShotPhysics.Geometry
    ) -> Bool {
        if !oneOnOneEnabled || state.made || state.vy <= 0 { return false }

        func crossingX(planeY: Float) -> Float? {
            if !(state.previousY < planeY && state.y >= planeY) { return nil }
            let dy = state.y - state.previousY
            if abs(dy) < 0.0001 { return state.x }
            let t = ((planeY - state.previousY) / dy).coerceIn(0, 1)
            return lerp(state.previousX, state.x, t)
        }

        let rimCrossX = crossingX(planeY: geometry.hoopY)

        /*
         * A second visual-truth plane sits inside the upper net. A 2D game cannot ask the player
         * to distinguish a hidden depth miss from a made basket when the ball centre visibly falls
         * through the photographed throat of the net. If it was clearly above the rim first and
         * crosses that throat downward, the 1v1 scoreboard must agree with what the screen shows.
         */
        let netConfirmY =
            geometry.hoopY +
                (geometry.netBottomY - geometry.hoopY) * Self.ONE_ON_ONE_NET_MAKE_CONFIRM_T
        let netCrossX = crossingX(planeY: netConfirmY)

        let roseClearlyAbove =
            state.maxHeightReachedY <= geometry.hoopY - geometry.ballRadius * 1.10
        if !roseClearlyAbove { return false }

        // In 1v1 an upward entry through the cylinder is physically rejected by the physics layer.
        // Never turn that invalid projection into a score on the way back down.
        if state.enteredBasketFromBelow && state.rejectUpwardBasketEntry { return false }

        var throughRimOpening = false
        if let x = rimCrossX {
            let relaxedPadding = (geometry.rimColliderRadius * 0.55).coerceAtLeast(0)
            throughRimOpening =
                x > geometry.leftRimX + relaxedPadding &&
                    x < geometry.rightRimX - relaxedPadding
        }

        var throughVisibleNetThroat = false
        if let x = netCrossX {
            let t = Self.ONE_ON_ONE_NET_MAKE_CONFIRM_T
            let left =
                lerp(
                    geometry.leftRimX + geometry.ballRadius * 0.20,
                    geometry.netBottomLeftX + geometry.ballRadius * 0.35,
                    t
                )
            let right =
                lerp(
                    geometry.rightRimX - geometry.ballRadius * 0.20,
                    geometry.netBottomRightX - geometry.ballRadius * 0.35,
                    t
                )
            throughVisibleNetThroat = left <= x && x <= right
        }

        if !throughRimOpening && !throughVisibleNetThroat { return false }

        state.made = true
        return true
    }

    func oneOnOnePlayableReboundVelocity(
        state: TripleShotPhysics.ShotState,
        finish: OneOnOneDriveFinish
    ) -> APointF {
        // Direction still comes ONLY from the real rim/backboard collision. We merely remove some
        // energy at the handoff to the floor/rebound phase so ordinary misses can drop near the rim,
        // bounce a few times and roll instead of every contact becoming a full-court ricochet.
        let closeFinish = finish != OneOnOneDriveFinish.JUMPER
        let xScale: Float
        let yScale: Float
        if state.rimHits > 0 && closeFinish {
            xScale = 0.55; yScale = 0.62
        } else if state.rimHits > 0 {
            xScale = 0.68; yScale = 0.72
        } else if state.backboardHits > 0 && closeFinish {
            xScale = 0.62; yScale = 0.66
        } else if state.backboardHits > 0 {
            xScale = 0.72; yScale = 0.76
        } else {
            xScale = 0.90; yScale = 0.90
        }

        let touchedBasket = state.rimHits > 0 || state.backboardHits > 0
        let maxX = touchedBasket ? dp(210) : dp(300)
        let maxY = touchedBasket ? dp(260) : dp(360)
        return APointF(
            (state.vx * xScale).coerceIn(-maxX, maxX),
            (state.vy * yScale).coerceIn(-maxY, maxY)
        )
    }

    func finishPhysicsShot() {
        if !shotFrameRunning { return }

        guard let state = physicsState else { return }
        guard let geometry = physicsGeometry else { return }
        ALog.i("TRIPLE_PLAY", "soloShot actor=human made=\(state.made) rimHits=\(state.rimHits) backboardHits=\(state.backboardHits) net=\(state.touchingNet) elapsed=\(javaString(state.elapsedSeconds))")
        let callback = shotOnEnd

        shotFrameRunning = false
        removeCallbacks(physicsFrameRunnable)

        captureLiveReplaySample(force: true)
        let replaySamples = liveReplaySamples
        let outcome = TripleShotPhysics.toOutcome(state: state, geometry: geometry)
        let kind: ShotKind
        if outcome.made && state.backboardHits > 0 {
            kind = ShotKind.BANK_IN
        } else if outcome.made && state.rimHits > 0 {
            kind = ShotKind.RIM_IN
        } else if outcome.made {
            kind = ShotKind.SWISH
        } else if state.enteredBasketFromBelow {
            kind = ShotKind.INVALID_BELOW
        } else if state.rimHits > 0 {
            kind = ShotKind.RIM_OUT
        } else if state.backboardHits > 0 {
            kind = ShotKind.BACKBOARD_OUT
        } else {
            kind = ShotKind.AIRBALL
        }

        physicsState = nil
        physicsGeometry = nil
        shotOnEnd = nil
        shotMadeAtSeconds = nil

        pullBack = 0
        fineAim = 0
        humanReleaseStartedAtNanos = 0
        let completedFinish = oneOnOneHumanActiveFinish
        oneOnOneHumanActiveFinish = OneOnOneDriveFinish.JUMPER

        if oneOnOneEnabled && !outcome.made {
            // 1v1 misses stay physically alive. Keep the real collision direction, but hand a
            // calmer amount of its remaining energy into the floor/rebound phase.
            // (startOneOnOneLooseBall fires the LOOSE ball-state listener before the shot callback below.)
            let rebound = oneOnOnePlayableReboundVelocity(
                state: state,
                finish: completedFinish
            )
            startOneOnOneLooseBall(
                x: state.x,
                y: state.y,
                vx: rebound.x,
                vy: rebound.y,
                gravityPxPerSec2: geometry.gravityPxPerSec2,
                worldStart: humanShotPresentation.sample(state: state, geometry: geometry, hoop: worldHoop(), verticalScale: worldVerticalScale()),
                worldVelocity: humanShotPresentation.velocity(state: state, geometry: geometry, hoop: worldHoop(), verticalScale: worldVerticalScale())
            )
        } else if sharedHorseBallOwner != nil || horseHumanStation != nil {
            // HORSE possession changes only when the next shooter actually starts moving.
            // Hiding the dead ball here avoids the one-frame hand-to-hand teleport after a miss.
            ballVisible = false
        } else {
            ballVisible = true
            let held = heldBallPosition()
            ballX = held.x
            ballY = held.y
            ballRotationDeg = 0
        }

        invalidate()

        callback?(
            ShotResult(
                outcome: outcome,
                kind: kind,
                rimHits: state.rimHits,
                backboardHits: state.backboardHits,
                replaySamples: replaySamples
            )
        )
    }

    func finishBotPhysicsShot() {
        if !botShotFrameRunning { return }

        guard let state = botPhysicsState else { return }
        guard let geometry = botPhysicsGeometry else { return }
        ALog.i("TRIPLE_PLAY", "soloShot actor=bot made=\(state.made) rimHits=\(state.rimHits) backboardHits=\(state.backboardHits) net=\(state.touchingNet) elapsed=\(javaString(state.elapsedSeconds))")
        let callback = botShotOnEnd

        botShotFrameRunning = false
        removeCallbacks(botPhysicsFrameRunnable)

        let outcome = TripleShotPhysics.toOutcome(state: state, geometry: geometry)
        let kind: ShotKind
        if outcome.made && state.backboardHits > 0 {
            kind = ShotKind.BANK_IN
        } else if outcome.made && state.rimHits > 0 {
            kind = ShotKind.RIM_IN
        } else if outcome.made {
            kind = ShotKind.SWISH
        } else if state.enteredBasketFromBelow {
            kind = ShotKind.INVALID_BELOW
        } else if state.rimHits > 0 {
            kind = ShotKind.RIM_OUT
        } else if state.backboardHits > 0 {
            kind = ShotKind.BACKBOARD_OUT
        } else {
            kind = ShotKind.AIRBALL
        }

        botPhysicsState = nil
        botPhysicsGeometry = nil
        botShotOnEnd = nil
        botShotMadeAtSeconds = nil
        botShotLastFrameNanos = 0

        botPullBack = 0
        botFineAim = 0
        botBallRotationDeg = 0
        let completedFinish = oneOnOneBotActiveFinish
        oneOnOneBotActiveFinish = OneOnOneDriveFinish.JUMPER

        if oneOnOneEnabled && !outcome.made {
            let rebound = oneOnOnePlayableReboundVelocity(
                state: state,
                finish: completedFinish
            )
            startOneOnOneLooseBall(
                x: state.x,
                y: state.y,
                vx: rebound.x,
                vy: rebound.y,
                gravityPxPerSec2: geometry.gravityPxPerSec2,
                worldStart: botShotPresentation.sample(state: state, geometry: geometry, hoop: worldHoop(), verticalScale: worldVerticalScale()),
                worldVelocity: botShotPresentation.velocity(state: state, geometry: geometry, hoop: worldHoop(), verticalScale: worldVerticalScale())
            )
            botBallVisible = false
        } else if sharedHorseBallOwner != nil || horseHumanStation != nil {
            // Same dead-ball treatment as the human HORSE shot: wait for the next possession
            // handoff instead of flashing the ball back into the bot's hand for one frame.
            // (It tests the human's HORSE station, as Android does.)
            botBallVisible = false
        } else {
            botBallVisible = botEnabled
            if botEnabled {
                let held = heldBotBallPosition()
                botBallX = held.x
                botBallY = held.y
            }
        }

        invalidate()

        callback?(
            ShotResult(
                outcome: outcome,
                kind: kind,
                rimHits: state.rimHits,
                backboardHits: state.backboardHits
            )
        )
    }

    /// Every production caller passes `callEnd = false`: a running bot shot is dropped and its callback is never called.
    func cancelBotShotSimulation(callEnd: Bool) {
        removeCallbacks(botPhysicsFrameRunnable)
        if oneOnOneBotDunkActive || oneOnOneBotDunkAnimator != nil {
            cancelOneOnOneBotDunk()
        }
        botAimAnimator?.cancel()
        botAimAnimator = nil
        botPullBack = 0

        if callEnd && botShotFrameRunning {
            finishBotPhysicsShot()
            return
        }

        botShotFrameRunning = false
        botPhysicsState = nil
        botPhysicsGeometry = nil
        botShotOnEnd = nil
        botShotMadeAtSeconds = nil
        botShotLastFrameNanos = 0
    }

    /// Every production caller passes `callEnd = false`: a running human shot is dropped and its callback is never called.
    func cancelShotSimulation(callEnd: Bool) {
        removeCallbacks(physicsFrameRunnable)

        if callEnd && shotFrameRunning {
            finishPhysicsShot()
            return
        }

        shotFrameRunning = false
        physicsState = nil
        physicsGeometry = nil
        shotOnEnd = nil
        shotMadeAtSeconds = nil
        shotLastFrameNanos = 0
        humanReleaseStartedAtNanos = 0
        liveReplaySamples.removeAll()
        liveReplayStartedAtNanos = 0
        liveReplayLastSampleMs = -Self.LIVE_REPLAY_SAMPLE_INTERVAL_MS
    }

    /// Body of `override fun onDetachedFromWindow()` (part 1 holds the override stub). Pending shot callbacks
    /// and the HORSE jump-shot release are dropped, as on Android.
    func onDetachedFromWindow_impl() {
        if let pending = horseRelease { removeCallbacks(pending) }; horseRelease = nil; horseGathering = false
        playerMoveAnimator?.cancel()
        botMoveAnimator?.cancel()
        botAimAnimator?.cancel()
        botAimAnimator = nil
        matchCelebrationAnimator?.cancel()
        matchCelebrationAnimator = nil
        cancelHumanIdleDribble()
        removeCallbacks(horseFreeMoveSettleRunnable)
        cancelShotSimulation(callEnd: false)
        cancelBotShotSimulation(callEnd: false)
        stopOneOnOneLooseBall()
        oneOnOneAutomaticBallStateListener = nil
        clearLiveOpponents()
        super.onDetachedFromWindow()
    }

    /// Kotlin `private fun dp(v: Float): Float = v * density` (the unlabelled form is the one the code uses).
    func dp(_ v: Float) -> Float {
        return v * density
    }

    func dp(v: Float) -> Float {
        return v * density
    }

    /// Clamps `t` (do not substitute an unclamped lerp).
    func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float {
        return a + (b - a) * t.coerceIn(0, 1)
    }

    func lerp(a: Float, b: Float, t: Float) -> Float {
        return lerp(a, b, t)
    }

    // MARK: - companion object (Kotlin 7573-7944). Units: `_DP` x density, `_SRC`/`SRC_*` source-art px
    // (1024x1536), `_MS` milliseconds (Kotlin Long -> Int64), `_SECONDS` seconds. "(unused)" = no Kotlin reference;
    // "(dead-only)" = only referenced by skipped dead code.

    static let PREVIEW_STEP_SECONDS: Float = 1 / 180                        // (dead-only)
    static let BANK_PREVIEW_AFTER_HIT_SECONDS: Float = 0.18

    static let AIM_ASSIST_MAX_LEVEL: Int = 5
    static let AIM_TARGET_MARKER_HIDE_LEVEL: Float = 0.75

    static let LIVE_REPLAY_SAMPLE_INTERVAL_MS: Int64 = 55
    static let LIVE_MAX_REPLAY_SAMPLES: Int = 60
    static let LIVE_REMOTE_WALK_MS: Int64 = 330
    static let LIVE_REMOTE_LOAD_MS: Int64 = 140
    static let LIVE_REMOTE_DRIBBLE_DP: Float = 28
    // Source image supplied for the game background.
    static let LIVE_REMOTE_IDLE_SPOTS: [APointF] = [
        APointF(155, 1180),
        APointF(520, 1260),
        APointF(805, 1115)
    ]

    static let BACKGROUND_WIDTH: Float = 1024
    static let BACKGROUND_HEIGHT: Float = 1536

    // Show more of the original wide artwork on tall phones without letterboxing.
    static let BACKGROUND_HORIZONTAL_SCALE: Float = 0.92
    static let BACKGROUND_HORIZONTAL_FOCUS: Float = 1.00

    // Movement / station placement tuning.
    static let PLAYER_MOVE_DURATION_MS: Int64 = 455
    static let DRIBBLE_BOUNCES_DURING_MOVE: Double = 2.0
    static let DRIBBLE_BOUNCE_AMPLITUDE_DP: Float = 49
    static let HUMAN_IDLE_DRIBBLE_DELAY_MS: Int64 = 2300
    static let HUMAN_IDLE_DRIBBLE_DURATION_MS: Int64 = 520
    // 1v1 needs a continuous basketball rhythm. The old 2.3s generic idle delay made the
    // handler look frozen and also starved the defender's steal logic of exposed bounces.
    static let ONE_ON_ONE_IDLE_DRIBBLE_DELAY_MS: Int64 = 80
    static let ONE_ON_ONE_IDLE_DRIBBLE_DURATION_MS: Int64 = 520
    static let ONE_ON_ONE_BOT_DRIBBLE_PERIOD_MS: Int64 = 650
    static let HUMAN_IDLE_DRIBBLE_AMPLITUDE_DP: Float = 46
    static let PLAYER_TO_ANSWER_GAP_DP: Float = 28
    static let MARKER_TO_ANSWER_GAP_DP: Float = 10                           // (dead-only)

    // Free HORSE movement follows the actual terrain rather than one flat ceiling.
    // Center: lower 50%. Outer left/right corridors: 0.46 (the Kotlin comment says "lower 58%"; the value wins).
    static let HORSE_CENTER_TOP_FRACTION: Float = 0.50
    static let HORSE_SIDE_TOP_FRACTION: Float = 0.46
    static let HORSE_LEFT_HIGH_ZONE_END: Float = 0.10
    static let HORSE_LEFT_TRANSITION_END: Float = 0.14
    static let HORSE_RIGHT_TRANSITION_START: Float = 0.76
    static let HORSE_RIGHT_HIGH_ZONE_START: Float = 0.80
    static let HORSE_DEVICE_MOVE_STEP_DP: Float = 5.2
    // Temporary source-artwork distance bands for character shooting ratings.
    // 1v1 can later replace these with the painted three-point line geometry.
    static let HUMAN_INSIDE_DISTANCE_SRC: Float = 250
    static let HUMAN_MID_DISTANCE_SRC: Float = 520

    // Local 1v1 alpha tuning. Ratings modify reach, while actual contact geometry decides
    // steals/blocks. These values are deliberately conservative so defense requires position.
    static let ONE_ON_ONE_COLLISION_Y_SCALE: Float = 0.72
    static let ONE_ON_ONE_DEFENDER_ANCHOR_BONUS: Float = 18
    static let ONE_ON_ONE_BASE_DEFENDER_DISPLACEMENT_SHARE: Float = 0.12
    static let ONE_ON_ONE_CONTEST_TRIGGER_PULL: Float = 0.42
    static let ONE_ON_ONE_CONTEST_FAKE_HOLD_MS: Int64 = 240
    static let ONE_ON_ONE_CONTEST_RECOVERY_MS: Int64 = 680
    static let ONE_ON_ONE_HUMAN_BLOCK_WINDOW_MS: Int64 = 280
    static let ONE_ON_ONE_STEAL_COOLDOWN_MS: Int64 = 820
    static let ONE_ON_ONE_POSSESSION_PROTECTION_MS: Int64 = 360
    static let ONE_ON_ONE_STEAL_AFTER_PICKUP_PROTECTION_MS: Int64 = 620
    static let ONE_ON_ONE_AUTO_STEAL_MIN_TOWARD_DOT: Float = 0.36
    static let ONE_ON_ONE_BLOCK_COLLISION_MAX_SECONDS: Float = 0.42
    static let ONE_ON_ONE_ATTACK_SEED_SALT: Int64 = 0x314F4E314F4E454C          // "1ON1ONEL"
    static let ONE_ON_ONE_DEFENSE_HEARTBEAT_MS: Int64 = 82
    static let ONE_ON_ONE_IDLE_DEFENSE_WAIT_MS: Int64 = 560
    static let ONE_ON_ONE_IDLE_DEFENSE_CLOSE_MS: Int64 = 900
    static let ONE_ON_ONE_IDLE_DEFENSE_EXTRA_CLOSE_DP: Float = 34

    static let ONE_ON_ONE_PUMP_FAKE_STUN_MS: Int64 = 620
    static let ONE_ON_ONE_CROSSOVER_WINDOW_MS: Int64 = 430                    // (unused)
    static let ONE_ON_ONE_CROSSOVER_BOT_STUN_MS: Int64 = 520                  // (unused)
    static let ONE_ON_ONE_CROSSOVER_BURST_DP: Float = 18                      // (unused)
    static let ONE_ON_ONE_CROSSOVER_COLLISION_SCALE: Float = 0.62
    static let ONE_ON_ONE_SPIN_LATERAL_DP: Float = 44
    static let ONE_ON_ONE_SPIN_FORWARD_DP: Float = 15
    static let ONE_ON_ONE_SPIN_WINDOW_MS: Int64 = 520
    static let ONE_ON_ONE_SPIN_BOT_STUN_MS: Int64 = 610
    static let ONE_ON_ONE_BOT_CROSSOVER_BURST_DP: Float = 17
    static let ONE_ON_ONE_BOT_IMMEDIATE_LANE_DEPTH_DP: Float = 118
    static let ONE_ON_ONE_BOT_EDGE_TURN_DP: Float = 46
    static let ONE_ON_ONE_BOT_REATTACK_LANE_DP: Float = 92

    static let ONE_ON_ONE_STEAL_REACH_MS: Int64 = 310
    static let ONE_ON_ONE_STEAL_CONTACT_DELAY_MS: Int64 = 150

    static let ONE_ON_ONE_JUMP_MS: Int64 = 470
    static let ONE_ON_ONE_ESCAPE_JUMP_MS: Int64 = 430
    static let ONE_ON_ONE_JUMP_HEIGHT_DP: Float = 27
    // Rebound jumps are deliberately theatrical in 1v1: the race for a high ball should read
    // instantly. This is both physical reach and visual lift; a dedicated Jump/Vertical rating
    // can scale this baseline per character once that rating is added to the roster model.
    static let ONE_ON_ONE_REBOUND_JUMP_MULTIPLIER: Float = 5.20
    static let ONE_ON_ONE_REBOUND_RENDER_EXTRA_MULTIPLIER: Float = 1.08
    static let ONE_ON_ONE_BLOCK_JUMP_MULTIPLIER: Float = 1.48
    static let ONE_ON_ONE_BOT_BLOCK_JUMP_MULTIPLIER: Float = 1.42
    static let ONE_ON_ONE_BLOCK_RENDER_EXTRA_MULTIPLIER: Float = 1.78
    static let ONE_ON_ONE_ACTION_SIDE_MIN_DX_DP: Float = 34
    static let ONE_ON_ONE_ACTION_SIDE_VECTOR_RATIO: Float = 0.58              // (unused)
    static let ONE_ON_ONE_ACTION_DEPTH_PRIORITY_DP: Float = 22
    static let ONE_ON_ONE_ESCAPE_DISTANCE_DP: Float = 31
    static let ONE_ON_ONE_FADE_BASE_DISTANCE_DP: Float = 12
    static let ONE_ON_ONE_FADE_EXTRA_DISTANCE_DP: Float = 19
    static let ONE_ON_ONE_FADE_SPEED_REFERENCE_DP_PER_SEC: Float = 330
    static let ONE_ON_ONE_FADE_MIN_JUMP_MULTIPLIER: Float = 1.42
    static let ONE_ON_ONE_FADE_EXTRA_JUMP_MULTIPLIER: Float = 0.42
    static let ONE_ON_ONE_SIDE_STEP_JUMP_MULTIPLIER: Float = 1.34
    static let ONE_ON_ONE_ESCAPE_DEFENDER_DELAY_MS: Int64 = 260
    static let ONE_ON_ONE_LAYUP_MAX_DISTANCE_SRC: Float = 390
    static let ONE_ON_ONE_DUNK_MAX_DISTANCE_SRC: Float = 235
    static let ONE_ON_ONE_LAYUP_MIN_SPEED: Float = 0.38
    static let ONE_ON_ONE_DUNK_MIN_SPEED: Float = 0.70
    static let ONE_ON_ONE_DUNK_MIN_ABILITY: Int = 68
    static let ONE_ON_ONE_LAYUP_STEP_DP: Float = 26
    static let ONE_ON_ONE_DUNK_STEP_DP: Float = 39
    static let ONE_ON_ONE_LAYUP_JUMP_MS: Int64 = 620
    static let ONE_ON_ONE_DUNK_JUMP_MS: Int64 = 680
    static let ONE_ON_ONE_DUNK_ACTION_MS: Int64 = 690
    static let ONE_ON_ONE_DUNK_RIM_CONTACT_T: Float = 0.70
    static let ONE_ON_ONE_DUNK_BLOCK_CUTOFF_T: Float = 0.80
    static let ONE_ON_ONE_DUNK_CHASE_BLOCK_BASE_DISTANCE_DP: Float = 92
    static let ONE_ON_ONE_DUNK_CHASE_BLOCK_JUMP_BONUS_DP: Float = 34
    static let ONE_ON_ONE_DUNK_CHASE_BLOCK_RATING_BONUS_DP: Float = 22
    static let ONE_ON_ONE_DUNK_RENDER_EXTRA_MULTIPLIER: Float = 1.42
    static let ONE_ON_ONE_DUNK_BALL_ATTACH_T: Float = 0.16
    static let ONE_ON_ONE_DUNK_POSE_RELEASE_T: Float = 0.76
    static let ONE_ON_ONE_DUNK_HANG_FRACTION: Float = 0.14
    // Temporary BLOCK-frame hand socket. Dedicated dunk frames should replace these values
    // with authored ball anchors, not change the scoring path. (All six unused.)
    static let ONE_ON_ONE_DUNK_HAND_ABOVE_FEET_DP: Float = 174
    static let ONE_ON_ONE_DUNK_HAND_SIDE_BACK_DP: Float = 32
    static let ONE_ON_ONE_DUNK_HAND_SIDE_SIDE_DP: Float = 42
    static let ONE_ON_ONE_DUNK_HAND_SIDE_FRONT_DP: Float = 43
    static let ONE_ON_ONE_DUNK_BALL_BELOW_HAND_DP: Float = 16
    static let ONE_ON_ONE_DUNK_HAND_OUTSIDE_BALL_DP: Float = 5
    static let ONE_ON_ONE_HUMAN_FINISH_RIM_STOP_DP: Float = 34
    static let ONE_ON_ONE_BOT_GROUNDED_RIM_STOP_DP: Float = 78
    // Grounded takeoff points. 34dp put Maya almost on the projected rim-depth point,
    // producing the repeated under-the-basket launch seen in testing. A real layup/dunk
    // gathers before the stanchion, from a side channel.
    static let ONE_ON_ONE_BOT_LAYUP_RIM_STOP_DP: Float = 70
    static let ONE_ON_ONE_BOT_DUNK_RIM_STOP_DP: Float = 58
    static let ONE_ON_ONE_HUMAN_LAYUP_FINISH_LANE_OFFSET_DP: Float = 42
    static let ONE_ON_ONE_HUMAN_DUNK_FINISH_LANE_OFFSET_DP: Float = 30
    static let ONE_ON_ONE_BOT_LAYUP_FINISH_LANE_OFFSET_DP: Float = 54
    static let ONE_ON_ONE_BOT_DUNK_FINISH_LANE_OFFSET_DP: Float = 44

    static let ONE_ON_ONE_IMPACT_REBOUND_MIN_SECONDS: Float = 0.48
    static let ONE_ON_ONE_AIRBALL_REBOUND_MIN_SECONDS: Float = 0.82
    static let ONE_ON_ONE_AIRBALL_RELEASE_BELOW_NET_DP: Float = 48
    static let ONE_ON_ONE_RIM_POST_IMPACT_DAMPING: Float = 0.80
    static let ONE_ON_ONE_BOARD_POST_IMPACT_X_DAMPING: Float = 0.80
    static let ONE_ON_ONE_BOARD_POST_IMPACT_Y_DAMPING: Float = 0.88
    static let ONE_ON_ONE_CLOSE_FINISH_RIM_DAMPING: Float = 0.54
    static let ONE_ON_ONE_CLOSE_FINISH_BOARD_X_DAMPING: Float = 0.58
    static let ONE_ON_ONE_CLOSE_FINISH_BOARD_Y_DAMPING: Float = 0.66
    static let ONE_ON_ONE_NET_MAKE_CONFIRM_T: Float = 0.30

    static let ONE_ON_ONE_DEFENDER_BACK_DEAD_ZONE_DP: Float = 30              // (unused)
    static let ONE_ON_ONE_DEFENDER_LANE_FACING_HALF_WIDTH_DP: Float = 82      // (unused)
    static let ONE_ON_ONE_DEFENDER_LANE_BEHIND_TOLERANCE_DP: Float = 8        // (unused)

    static let ONE_ON_ONE_GROUND_PICKUP_MAX_HEIGHT_DP: Float = 54
    static let ONE_ON_ONE_GROUND_PICKUP_X_REACH_DP: Float = 44
    static let ONE_ON_ONE_GROUND_PICKUP_Y_REACH_DP: Float = 54
    static let ONE_ON_ONE_GROUND_PICKUP_CENTER_ABOVE_FEET_DP: Float = 12
    static let ONE_ON_ONE_GROUND_PICKUP_MIN_AGE_SECONDS: Float = 0.12
    static let ONE_ON_ONE_REBOUND_CLAIM_MIN_AGE_SECONDS: Float = 0.18
    static let ONE_ON_ONE_STEAL_LOOSE_CLAIM_DELAY_SECONDS: Float = 0.28
    static let ONE_ON_ONE_BOT_REBOUND_REACTION_SECONDS: Float = 0.16          // (unused)
    static let ONE_ON_ONE_REBOUND_HAND_HEIGHT_DP: Float = 86
    static let ONE_ON_ONE_REBOUND_JUMP_REACH_DP: Float = 58
    static let ONE_ON_ONE_REBOUND_JUMP_SCORE_BONUS: Float = 0.18
    static let ONE_ON_ONE_DEFENDER_FACE_TOLERANCE_DP: Float = 9               // (unused)
    static let ONE_ON_ONE_HOOP_FACING_TOLERANCE_DP: Float = 18

    static let ONE_ON_ONE_FRONT_HALF_WIDTH_SRC: Float = 350
    static let ONE_ON_ONE_SIDE_MIN_DX_SRC: Float = 108
    static let ONE_ON_ONE_SIDE_VECTOR_RATIO: Float = 0.31

    static let ONE_ON_ONE_DRIVE_FINISH_MIN_FORWARD_DOT: Float = 0.36
    static let ONE_ON_ONE_MOVING_SHOT_MIN_DRIFT_DP: Float = 8
    static let ONE_ON_ONE_MOVING_SHOT_EXTRA_DRIFT_DP: Float = 18
    static let ONE_ON_ONE_MOVING_SHOT_DRIFT_MS: Int64 = 175
    static let ONE_ON_ONE_MOVING_SHOT_JUMP_MS: Int64 = 430
    static let ONE_ON_ONE_CONTESTED_JUMPER_JUMP_MS: Int64 = 590
    static let ONE_ON_ONE_CONTESTED_JUMPER_MULTIPLIER: Float = 2.34
    static let ONE_ON_ONE_CONTESTED_JUMPER_BASE_DISTANCE_DP: Float = 82
    static let ONE_ON_ONE_CONTESTED_JUMPER_DEFENSE_BONUS_DP: Float = 12
    static let ONE_ON_ONE_MOVING_SHOT_MIN_JUMP_MULTIPLIER: Float = 0.78
    static let ONE_ON_ONE_MOVING_SHOT_EXTRA_JUMP_MULTIPLIER: Float = 0.34
    static let ONE_ON_ONE_MOVING_SHOT_DEFENDER_DELAY_MIN_MS: Int64 = 55
    static let ONE_ON_ONE_MOVING_SHOT_DEFENDER_DELAY_EXTRA_MS: Int64 = 105
    static let ONE_ON_ONE_DEFENSE_BLOCK_GATHER_PULL: Float = 0.17
    static let ONE_ON_ONE_DEFENSE_BLOCK_EARLY_FLIGHT_SECONDS: Float = 0.27
    static let HORSE_TAP_WALK_MIN_DURATION_MS: Int64 = 260
    static let HORSE_TAP_WALK_MAX_DURATION_MS: Int64 = 620
    static let MATCH_CELEBRATION_DURATION_MS: Int64 = 2800

    // V14: FRONT/BACK is controlled ONLY by source-artwork Y. This is a horizontal
    // divider: left/right movement never turns the body. The 50px hysteresis band keeps
    // small vertical jitter from flickering near the line.
    static let SRC_FACING_DIVIDER_Y: Float = 1000
    static let SRC_FACING_FRONT_ENTER_Y: Float = 975
    static let SRC_FACING_BACK_ENTER_Y: Float = 1025
    static let FACING_HORIZONTAL_DEAD_ZONE_DP: Float = 10

    // Free-drag movement speed changes only the dribble style, never movement physics.
    // Hysteresis avoids rapid switching if the finger hovers around the threshold.
    static let HUMAN_FAST_DRIBBLE_ENTER_DP_PER_SEC: Float = 185
    static let HUMAN_FAST_DRIBBLE_EXIT_DP_PER_SEC: Float = 145
    // V17 shooting keyframes. LOW disappears almost immediately once the player starts
    // moving the arc; MID carries most of the rise, then SET owns the high aiming phase.
    static let PRO_SHOT_LOW_TO_MID_PULL: Float = 0.04
    static let PRO_SHOT_MID_TO_SET_PULL: Float = 0.46
    static let PRO_RELEASE_POSE_MS: Int64 = 360

    // Professional shot orientation is separate from idle/dribble court-facing.
    // These values are source-artwork coordinates (1024x1536), so device crop/scale does not
    // move the visual zones. SIDE_RIGHT is mirrored automatically when the hoop is to the left.
    static let SRC_SHOT_SIDE_LEFT_MAX_X: Float = 360
    static let SRC_SHOT_SIDE_RIGHT_MIN_X: Float = 900
    static let SRC_SHOT_FRONT_MAX_Y: Float = 930
    static let SRC_SHOT_FRONT_HALF_WIDTH_X: Float = 300

    static let HEBREW_ANSWER_LABELS: [String] = ["\u{05D0}", "\u{05D1}", "\u{05D2}", "\u{05D3}"]   // (dead-only)

    // Hoop geometry measured in source-image pixels.
    static let SRC_HOOP_CENTER_X: Float = 750
    static let SRC_HOOP_PLANE_Y: Float = 340
    // Ground-depth of the basket support. Players with feet below this are closer to
    // the camera and must be drawn over the re-painted hoop/support foreground.
    static let SRC_HOOP_DEPTH_FOOT_Y: Float = 948
    static let SRC_RIM_LEFT_X: Float = 655
    static let SRC_RIM_RIGHT_X: Float = 845
    // Foreground-only rim overlay. These are deliberately tighter than the collision
    // geometry so the drawn front half sits on the photographed rim instead of looking
    // like a second lower ring.
    static let SRC_RIM_ELLIPSE_TOP_Y: Float = 320                             // (unused)
    static let SRC_RIM_ELLIPSE_BOTTOM_Y: Float = 349                          // (unused)

    static let SRC_BACKBOARD_COLLISION_X: Float = 860
    static let SRC_BACKBOARD_TOP_Y: Float = 215
    static let SRC_BACKBOARD_BOTTOM_Y: Float = 397

    static let SRC_NET_TOP_LEFT_X: Float = 666                                // (unused)
    static let SRC_NET_TOP_RIGHT_X: Float = 835                               // (unused)
    static let SRC_NET_TOP_Y: Float = 347                                     // (unused)
    static let SRC_NET_BOTTOM_LEFT_X: Float = 704
    static let SRC_NET_BOTTOM_RIGHT_X: Float = 792
    static let SRC_NET_BOTTOM_Y: Float = 505

    static let SRC_AIM_RANGE_X: Float = 130

    // Keep these aligned with TripleShotSensorController touch-power tuning.
    static let TOUCH_PREVIEW_IDEAL_PULL: Float = 0.70                         // (unused)
    static let TOUCH_PREVIEW_PULL_TO_POWER_ERROR: Float = 1.26                // (unused)

    static let SRC_CENTER_X: Float = 512
    static let SRC_DEFAULT_PLAYER_Y: Float = 1175

    /*
     * Curated legal feet positions in the ORIGINAL 1024x1536 artwork.
     * Some are on the painted court; several intentionally sit in low vegetation at the
     * sides because those "weird" shots are fun and will later be excellent HORSE spots.
     * We avoid the stream, tree trunks, the basket pole and high foliage where the player
     * would visibly float.
     */
    static let PRACTICE_SPOTS: [Station] = [
        Station(id: "practice_left", sourceX: 300, sourceY: 1125, distanceDifficulty: 0.34, zone: "court_left"),
        Station(id: "practice_deep", sourceX: 505, sourceY: 1190, distanceDifficulty: 0.78, zone: "court_deep"),
        Station(id: "practice_right", sourceX: 690, sourceY: 1085, distanceDifficulty: 0.54, zone: "court_right"),
        Station(id: "practice_bush", sourceX: 275, sourceY: 955, distanceDifficulty: 0.50, zone: "left_bush")
    ]

    /*
     * Curated legal feet positions in the ORIGINAL 1024x1536 artwork.
     * The catalog is intentionally much larger than the answer count. Some positions
     * are on the painted court, some on low vegetation, and a few are intentionally
     * nasty HORSE-style angles near the basket. No point is on the stream, a tree trunk
     * or high foliage where the player would visibly float.
     * The order feeds seeded shuffles: keep it.
     */
    static let SHOT_SPOT_CATALOG: [Station] = [
        // Left / lower-left vegetation and painted edge.
        Station(id: "L01", sourceX: 220, sourceY: 920, distanceDifficulty: 0.61, zone: "left_bush"),
        Station(id: "L02", sourceX: 245, sourceY: 1005, distanceDifficulty: 0.50, zone: "left_bush"),
        Station(id: "L03", sourceX: 270, sourceY: 1095, distanceDifficulty: 0.42, zone: "left_edge"),
        Station(id: "L04", sourceX: 305, sourceY: 1175, distanceDifficulty: 0.48, zone: "court_left"),
        Station(id: "L05", sourceX: 340, sourceY: 1025, distanceDifficulty: 0.50, zone: "left_edge"),
        Station(id: "L06", sourceX: 365, sourceY: 1125, distanceDifficulty: 0.55, zone: "court_left"),

        // Center / deep court.
        Station(id: "C01", sourceX: 420, sourceY: 930, distanceDifficulty: 0.66, zone: "upper_court"),
        Station(id: "C02", sourceX: 455, sourceY: 1010, distanceDifficulty: 0.60, zone: "upper_court"),
        Station(id: "C03", sourceX: 470, sourceY: 1100, distanceDifficulty: 0.63, zone: "court_center"),
        Station(id: "C04", sourceX: 500, sourceY: 1195, distanceDifficulty: 0.82, zone: "court_deep"),
        Station(id: "C05", sourceX: 555, sourceY: 970, distanceDifficulty: 0.65, zone: "upper_court"),
        Station(id: "C06", sourceX: 565, sourceY: 1070, distanceDifficulty: 0.64, zone: "court_center"),
        Station(id: "C07", sourceX: 590, sourceY: 1165, distanceDifficulty: 0.77, zone: "court_deep"),

        // Right court / low vegetation.
        Station(id: "R01", sourceX: 635, sourceY: 920, distanceDifficulty: 0.69, zone: "right_upper"),
        Station(id: "R02", sourceX: 645, sourceY: 1015, distanceDifficulty: 0.59, zone: "court_right"),
        Station(id: "R03", sourceX: 670, sourceY: 1105, distanceDifficulty: 0.61, zone: "court_right"),
        Station(id: "R04", sourceX: 700, sourceY: 1180, distanceDifficulty: 0.70, zone: "right_edge"),
        Station(id: "R05", sourceX: 735, sourceY: 970, distanceDifficulty: 0.66, zone: "right_bush"),
        Station(id: "R06", sourceX: 755, sourceY: 1065, distanceDifficulty: 0.64, zone: "right_edge"),
        Station(id: "R07", sourceX: 785, sourceY: 1140, distanceDifficulty: 0.70, zone: "right_edge"),

        // Hard / weird but still grounded spots. These are rare in Challenge and ideal
        // for future HORSE. The physics now has automatic board-clearance support.
        Station(id: "H01", sourceX: 790, sourceY: 880, distanceDifficulty: 0.76, zone: "right_bush_hard"),
        Station(id: "H02", sourceX: 825, sourceY: 945, distanceDifficulty: 0.80, zone: "near_pole_hard"),
        Station(id: "H03", sourceX: 845, sourceY: 1015, distanceDifficulty: 0.82, zone: "behind_board_hard"),
        Station(id: "H04", sourceX: 860, sourceY: 1090, distanceDifficulty: 0.84, zone: "behind_board_hard"),
        Station(id: "H05", sourceX: 885, sourceY: 1140, distanceDifficulty: 0.88, zone: "behind_board_extreme"),

        // A few extra diagonals to prevent visually repetitive triplets.
        Station(id: "X01", sourceX: 330, sourceY: 950, distanceDifficulty: 0.58, zone: "left_bush"),
        Station(id: "X02", sourceX: 405, sourceY: 1060, distanceDifficulty: 0.58, zone: "court_diag"),
        Station(id: "X03", sourceX: 535, sourceY: 1030, distanceDifficulty: 0.61, zone: "court_diag"),
        Station(id: "X04", sourceX: 620, sourceY: 1125, distanceDifficulty: 0.70, zone: "court_diag"),
        Station(id: "X05", sourceX: 720, sourceY: 1010, distanceDifficulty: 0.64, zone: "right_diag")
    ]

    /*
     * HORSE exposes the bushes and difficult pole-side locations, but temporarily skips
     * the three deepest behind-board points until the special-angle shot model is revisited.
     * This keeps every selectable first-pass challenge physically believable.
     */
    static let HORSE_SELECTABLE_SPOTS: [Station] = SHOT_SPOT_CATALOG.filter {
        // The three deepest behind-board positions stay disabled until the special-angle
        // shot model is revisited. Bushes, pole-side shots and H01/H02 are still available.
        !($0.id == "H03" || $0.id == "H04" || $0.id == "H05")
    }

    static let BOT_SPOT_CATALOG: [Station] = HORSE_SELECTABLE_SPOTS

    static let MIN_SOURCE_SPOT_DISTANCE_SQ: Float = 135 * 135
    static let RELAXED_SOURCE_SPOT_DISTANCE_SQ: Float = 90 * 90
    static let PREVIOUS_QUESTION_AVOID_DISTANCE_SQ: Float = 92 * 92
    static let RECENT_SPOT_MEMORY: Int = 10

    static let BOT_ANSWER_AVOID_DISTANCE_SQ: Float = 105 * 105
    static let BOT_HUMAN_MIN_DISTANCE_DP: Float = 82
    static let BOT_RECENT_SPOT_MEMORY: Int = 5
    static let BOT_SPOT_SEED_SALT: Int64 = 0x424F5453504F54                    // "BOTSPOT"
    static let BOT_VISIBLE_AIM_MS: Int64 = 580
    static let CHALLENGE_WAIT_SEED_SALT: Int64 = 0x4348414C57414954             // "CHALWAIT"
    static let HORSE_SPOT_SEED_SALT: Int64 = 0x484F52534553504F                 // "HORSESPO"
    static let HORSE_WAIT_SEED_SALT: Int64 = 0x57414954484F5253                 // "WAITHORS"
    static let HORSE_WAIT_MIN_DISTANCE_SQ: Float = 240 * 240

    static let BALL_VISUAL_RADIUS_DP: Float = 15                               // (unused)
    static let BALL_PHYSICS_RADIUS_DP: Float = 12.5

    static let MAX_PHYSICS_SUBSTEP_SECONDS: Float = 1 / 180
    static let MAX_SHOT_SECONDS: Float = 4.2
    static let MIN_POST_MAKE_SECONDS: Float = 0.24
    static let MAX_POST_MAKE_SECONDS: Float = 0.95
    static let MIN_VISIBLE_RIM_IMPACT: Float = 45                               // view px/s
    static let MIN_VISIBLE_NET_IMPACT: Float = 32                               // view px/s

    static let RIM_SHAKE_SECONDS: Float = 0.48
    static let NET_KICK_SECONDS: Float = 0.62
}

// MARK: - Kotlin positional call forms
// The Kotlin callers in parts 1 and 2 use both positional and named arguments; these forward to the labelled
// members above (DESIGN 2.1 prefers the labelled form).
extension TripleShotCourtView {
    func heldBallPosition(_ motionOverride: TripleShotPlayerRenderer.Motion?) -> APointF {
        return heldBallPosition(motionOverride: motionOverride)
    }

    func humanRendererState(_ motionOverride: TripleShotPlayerRenderer.Motion?) -> TripleShotPlayerRenderer.State {
        return humanRendererState(motionOverride: motionOverride)
    }

    func preReleaseHumanMotionForPull(_ pull: Float) -> TripleShotPlayerRenderer.Motion {
        return preReleaseHumanMotionForPull(pull: pull)
    }

    func liveRemoteHeldBall(_ remote: LiveRemoteVisual) -> APointF {
        return liveRemoteHeldBall(remote: remote)
    }

    func liveDistanceDifficulty(_ sourceX: Float, _ sourceY: Float) -> Float {
        return liveDistanceDifficulty(sourceX: sourceX, sourceY: sourceY)
    }

    func updateHumanMovementSpeed(_ distancePx: Float, _ nowNanos: Int64 = ASystem.nanoTime()) {
        updateHumanMovementSpeed(distancePx: distancePx, nowNanos: nowNanos)
    }

    func updateMovingDribbleBounceIndex(_ newIndex: Int) {
        updateMovingDribbleBounceIndex(newIndex: newIndex)
    }

    func oneOnOneActionFacing(_ actorX: Float, _ actorFootY: Float, _ targetX: Float, _ targetY: Float) -> TripleShotPlayerRenderer.Facing {
        return oneOnOneActionFacing(actorX: actorX, actorFootY: actorFootY, targetX: targetX, targetY: targetY)
    }

    func setPlayerPosition(_ x: Float, _ y: Float, _ animate: Bool, _ onEnd: (() -> Void)? = nil) {
        setPlayerPosition(x: x, y: y, animate: animate, onEnd: onEnd)
    }

    func setBotPosition(_ x: Float, _ y: Float, _ animate: Bool, _ onEnd: (() -> Void)? = nil) {
        setBotPosition(x: x, y: y, animate: animate, onEnd: onEnd)
    }

    func horseStationById(_ id: String) -> Station? {
        return horseStationById(id: id)
    }

    func chooseHorseWaitingStation(_ avoidSpotId: String, _ seed: Int64, _ preferLeft: Bool) -> Station {
        return chooseHorseWaitingStation(avoidSpotId: avoidSpotId, seed: seed, preferLeft: preferLeft)
    }

    func chooseChallengeWaitingStation(_ avoid: Station, _ seed: Int64) -> Station {
        return chooseChallengeWaitingStation(avoid: avoid, seed: seed)
    }

    func chooseBotStation(_ seed: Int64) -> Station {
        return chooseBotStation(seed: seed)
    }

    func rememberBotSpot(_ id: String) {
        rememberBotSpot(id: id)
    }

    func stationForAnswer(_ index: Int, _ count: Int) -> Station {
        return stationForAnswer(index: index, count: count)
    }

    func stationScreenPoint(_ index: Int, _ count: Int) -> APointF {
        return stationScreenPoint(index: index, count: count)
    }

    func botStationScreenPoint(_ station: Station) -> APointF {
        return botStationScreenPoint(station: station)
    }

    func sourcePointToView(_ sourceX: Float, _ sourceY: Float) -> APointF {
        return sourcePointToView(sourceX: sourceX, sourceY: sourceY)
    }

    func sourcePointToView(_ sourceX: Float, _ sourceY: Float, _ transform: BackgroundTransform) -> APointF {
        return sourcePointToView(sourceX: sourceX, sourceY: sourceY, transform: transform)
    }

    func sourceXToView(_ x: Float, _ transform: BackgroundTransform) -> Float {
        return sourceXToView(x: x, transform: transform)
    }

    func sourceYToView(_ y: Float, _ transform: BackgroundTransform) -> Float {
        return sourceYToView(y: y, transform: transform)
    }

    func triggerRimShake(_ impactSpeed: Float) {
        triggerRimShake(impactSpeed: impactSpeed)
    }

    func triggerNetKick(_ impactSpeed: Float, _ directionHint: Float) {
        triggerNetKick(impactSpeed: impactSpeed, directionHint: directionHint)
    }

    func dampOneOnOneShotImpact(_ state: TripleShotPhysics.ShotState, _ result: TripleShotPhysics.StepResult,
                                _ finish: OneOnOneDriveFinish) {
        dampOneOnOneShotImpact(state: state, result: result, finish: finish)
    }

    func oneOnOneShotReadyForLooseBall(_ state: TripleShotPhysics.ShotState, _ geometry: TripleShotPhysics.Geometry) -> Bool {
        return oneOnOneShotReadyForLooseBall(state: state, geometry: geometry)
    }

    func maybeMarkOneOnOneRelaxedMake(_ state: TripleShotPhysics.ShotState, _ geometry: TripleShotPhysics.Geometry) -> Bool {
        return maybeMarkOneOnOneRelaxedMake(state: state, geometry: geometry)
    }
}
