import Foundation

// Port of sensor/TripleShotSensorController.kt (Android snapshot dd722e5), statement by statement (spec 20).
// Android platform pieces map to AndroidKit: SensorManager → ASensorManager.shared (CoreMotion device motion:
// game rotation vector + calibrated gyroscope at SENSOR_DELAY_GAME = 50 Hz, main thread), MotionEvent → AMotionEvent
// (court pixels), VelocityTracker → AVelocityTracker (LSQ2), System.currentTimeMillis() → ASystem.currentTimeMillis()
// (DESIGN 2.4), Math.toDegrees → mathToDegrees.
// Kotlin holds the listener strongly (the fragment and the controller reference each other; the GC copes); under ARC
// the controller holds it weakly to break that cycle (spec 20 §9.2). Both production listeners (TripleShotGameFragment,
// TripleShotOneOnOneFragment) pass themselves and own the controller.

/**
 * Unified shot-input controller.
 *
 * The player can use phone motion, touch gestures, or switch between them naturally:
 *
 * SENSOR
 *  - rotate left/right -> aim
 *  - tilt/pull back -> load arc
 *  - move forward -> release; speed controls power
 *
 * TOUCH (anywhere on the court after an answer was selected)
 *  - horizontal drag -> aim
 *  - vertical drag -> arc + baseline power
 *  - release the finger -> shoot
 *  - optional upward flick -> adds a little extra power for advanced players
 *
 * Unlike V4, touch no longer receives ideal power automatically. The farther the
 * player loads the shot, the stronger it becomes. This keeps release simple while
 * preserving a real sweet spot instead of making every centred swipe an automatic make.
 *
 * Both input methods feed the same ShotSkill, so the renderer/physics does not care
 * how the player chose to control the shot.
 */
final class TripleShotSensorController: ASensorEventListener {

    enum ShotPhase: String, KotlinEnum {
        case WAITING_FOR_ANSWER
        case AIMING
        case ARMED
        case RELEASING
    }

    /// TripleShotSensorController.Listener. All callbacks are synchronous, on the main thread. Argument labels are the
    /// Kotlin parameter names (DESIGN 2.1).
    protocol Listener: AnyObject {
        func onAimChanged(normalizedAim: Float)
        func onPullBackChanged(normalizedPullBack: Float, armed: Bool)
        func onShotPhaseChanged(phase: ShotPhase)
        func onShotGesture(skill: ShotSkill, pullBack01: Float)
        func onSensorAvailability(hasRotation: Bool, hasGyro: Bool)

        /**
         * Optional neutral-pose movement input used by HORSE spot selection.
         * Values are joystick-like normalized directions in roughly -1..1.
         * A default implementation keeps every existing listener source-compatible.
         */
        func onMovementChanged(horizontal: Float, vertical: Float)
    }

    private weak var listener: Listener?

    private let manager: ASensorManager

    private let rotationSensor: ASensor?

    private let gyro: ASensor?

    private var matrix = [Float](repeating: 0, count: 9)
    private var orientation = [Float](repeating: 0, count: 3)

    private var baseRollDeg = Float.nan
    private var basePitchDeg = Float.nan

    private var currentRollDeg: Float = 0
    private var currentPitchDeg: Float = 0

    private var sensorAim: Float = 0
    private var touchAimOffset: Float = 0

    private var shotEnabled = false
    private var movementEnabled = false
    private var phase = ShotPhase.WAITING_FOR_ANSWER

    // Sensor pull-back state.
    private var pullDirectionSign: Float = 0
    private var maxPullBackDeg: Float = 0
    private var currentSignedPullDeg: Float = 0
    private var previousSignedPullDeg: Float = 0

    // Sensor release state.
    private var releaseStartedAtMs: Int64 = 0
    private var releasePeakGyro: Float = 0
    private var lastShotAtMs: Int64 = 0

    // Touch state.
    private var touchActive = false
    private var touchStartX: Float = 0
    private var touchStartY: Float = 0
    private var touchStartAimOffset: Float = 0
    private var touchPullBack: Float = 0
    private var touchMaxPullBack: Float = 0
    private var velocityTracker: AVelocityTracker? = nil

    /// `TripleShotSensorController(context, listener)`. The context is only used for
    /// `context.getSystemService(Context.SENSOR_SERVICE) as SensorManager`, which is `ASensorManager.shared`.
    convenience init(context: Any?, listener: Listener) {
        self.init(context: context, listener: listener, sensorManager: ASensorManager.shared)
    }

    /// Kotlin positional call form `TripleShotSensorController(requireContext(), this)`.
    convenience init(_ context: Any?, _ listener: Listener) {
        self.init(context: context, listener: listener)
    }

    /// The same with an explicit sensor service (unit tests pass a hardware-less ASensorManager).
    init(context: Any?, listener: Listener, sensorManager: ASensorManager) {
        self.listener = listener
        manager = sensorManager
        rotationSensor =
            sensorManager.getDefaultSensor(ASensor.TYPE_GAME_ROTATION_VECTOR)
                ?? sensorManager.getDefaultSensor(ASensor.TYPE_ROTATION_VECTOR)
        gyro =
            sensorManager.getDefaultSensor(ASensor.TYPE_GYROSCOPE)
    }

    func start() {
        listener?.onSensorAvailability(
            hasRotation: rotationSensor != nil,
            hasGyro: gyro != nil
        )

        if let it = rotationSensor {
            manager.registerListener(
                self,
                it,
                ASensorManager.SENSOR_DELAY_GAME
            )
        }

        if let it = gyro {
            manager.registerListener(
                self,
                it,
                ASensorManager.SENSOR_DELAY_GAME
            )
        }
    }

    func stop() {
        manager.unregisterListener(self)
        recycleVelocityTracker()
        touchActive = false
        movementEnabled = false
        listener?.onMovementChanged(horizontal: 0, vertical: 0)
        resetGestureState(ShotPhase.WAITING_FOR_ANSWER)
    }

    /** Called when a new question appears, before an answer is chosen. */
    func prepareForAnswer() {
        shotEnabled = false
        movementEnabled = false
        listener?.onMovementChanged(horizontal: 0, vertical: 0)
        touchAimOffset = 0
        sensorAim = 0
        recycleVelocityTracker()
        touchActive = false

        resetGestureState(ShotPhase.WAITING_FOR_ANSWER)
        listener?.onAimChanged(normalizedAim: 0)
        listener?.onPullBackChanged(normalizedPullBack: 0, armed: false)
    }

    /**
     * Called after tapping an answer.
     *
     * The current phone pose becomes neutral, so the user never needs to hold the
     * device at one globally hard-coded angle.
     */
    func prepareForShot() {
        shotEnabled = true
        movementEnabled = false
        listener?.onMovementChanged(horizontal: 0, vertical: 0)
        touchAimOffset = 0
        sensorAim = 0
        recycleVelocityTracker()
        touchActive = false

        calibrateOrientation()
        resetGestureState(ShotPhase.AIMING)

        listener?.onAimChanged(normalizedAim: 0)
        listener?.onPullBackChanged(normalizedPullBack: 0, armed: false)
    }

    func cancelShot() {
        prepareForAnswer()
    }

    /**
     * HORSE free-position mode.
     *
     * The current phone pose becomes neutral. Small roll/pitch changes are emitted as
     * movement directions only; they never arm or release a basketball shot.
     */
    func prepareForMovement() {
        shotEnabled = false
        movementEnabled = true
        touchAimOffset = 0
        sensorAim = 0
        recycleVelocityTracker()
        touchActive = false

        calibrateOrientation()
        resetGestureState(ShotPhase.WAITING_FOR_ANSWER)

        listener?.onAimChanged(normalizedAim: 0)
        listener?.onPullBackChanged(normalizedPullBack: 0, armed: false)
        listener?.onMovementChanged(horizontal: 0, vertical: 0)
    }

    /** Re-centres sensor + touch aim without leaving the current shot. */
    func calibrate() {
        calibrateOrientation()
        touchAimOffset = 0
        sensorAim = 0
        touchPullBack = 0
        touchMaxPullBack = 0

        resetGestureState(
            shotEnabled ? ShotPhase.AIMING
                : ShotPhase.WAITING_FOR_ANSWER
        )

        listener?.onAimChanged(normalizedAim: 0)
        listener?.onPullBackChanged(normalizedPullBack: 0, armed: false)
    }

    /**
     * Feed MotionEvents from the court view.
     *
     * Returning false before an answer is selected lets normal UI controls continue
     * to receive touches. After selection the court consumes the gesture.
     */
    func handleTouchEvent(
        event: AMotionEvent,
        viewWidth: Int,
        viewHeight: Int
    ) -> Bool {
        if
            !shotEnabled ||
            phase == ShotPhase.WAITING_FOR_ANSWER ||
            viewWidth <= 0 ||
            viewHeight <= 0
        {
            return false
        }

        switch event.actionMasked {
        case AMotionEvent.ACTION_DOWN:
            touchActive = true
            touchStartX = event.x
            touchStartY = event.y
            touchStartAimOffset = touchAimOffset
            touchPullBack = 0
            touchMaxPullBack = 0

            recycleVelocityTracker()
            let it = AVelocityTracker.obtain()
            it.addMovement(event)
            velocityTracker = it

            return true

        case AMotionEvent.ACTION_MOVE:
            if !touchActive { return false }

            velocityTracker?.addMovement(event)

            let dx = event.x - touchStartX
            let dy = event.y - touchStartY

            touchAimOffset =
                (
                    touchStartAimOffset +
                        dx / (viewWidth.toFloat() * TripleShotSensorController.TOUCH_AIM_FULL_SCALE_SCREEN_FRACTION)
                    )
                    .coerceIn(-TripleShotSensorController.MAX_AIM, TripleShotSensorController.MAX_AIM)

            emitCombinedAim()

            // Drag DOWN to load. Moving back UP visibly reduces the preview again.
            touchPullBack =
                (dy / (viewHeight.toFloat() * TripleShotSensorController.TOUCH_PULL_FULL_SCALE_SCREEN_FRACTION))
                    .coerceIn(0, TripleShotSensorController.MAX_PULL)

            touchMaxPullBack =
                kmax(touchMaxPullBack, touchPullBack)

            let armedNow =
                touchMaxPullBack >= TripleShotSensorController.TOUCH_ARM_THRESHOLD

            if phase == ShotPhase.AIMING && armedNow {
                changePhase(ShotPhase.ARMED)
            }

            listener?.onPullBackChanged(
                normalizedPullBack: touchPullBack,
                armed: phase == ShotPhase.ARMED || phase == ShotPhase.RELEASING
            )

            return true

        case AMotionEvent.ACTION_UP:
            if !touchActive { return false }

            velocityTracker?.addMovement(event)
            velocityTracker?.computeCurrentVelocity(1000)

            let velocityY: Float =
                velocityTracker?.yVelocity ?? 0

            // Negative Y = an optional upward power flick.
            let upwardScreensPerSecond =
                (-velocityY / viewHeight.toFloat()).coerceAtLeast(0)

            let wasArmed =
                phase == ShotPhase.ARMED ||
                    phase == ShotPhase.RELEASING ||
                    touchMaxPullBack >= TripleShotSensorController.TOUCH_ARM_THRESHOLD

            /*
             * Releasing the finger is still enough to shoot, but power is no longer
             * magically perfect. The load amount itself supplies the baseline power:
             * too little pull tends to finish short, too much tends to fly long.
             *
             * An upward flick is optional. It adds power on top of the loaded shot,
             * which gives experienced touch players another layer without forcing
             * beginners to perform a timing-bar style gesture.
             */
            let validRelease =
                wasArmed &&
                    touchMaxPullBack >= TripleShotSensorController.TOUCH_ARM_THRESHOLD

            let hasPowerFlick =
                upwardScreensPerSecond >= TripleShotSensorController.TOUCH_POWER_FLICK_START_SCREENS_PER_SEC

            let chosenPullBack: Float
            if hasPowerFlick {
                // The upward flick changes finger Y, so preserve the loaded arc.
                chosenPullBack = touchMaxPullBack
            } else {
                chosenPullBack = touchPullBack.coerceAtLeast(TripleShotSensorController.MIN_TOUCH_RELEASE_PULL)
            }

            touchActive = false
            recycleVelocityTracker()

            if validRelease {
                changePhase(ShotPhase.RELEASING)

                let baseTouchGyro =
                    (
                        TripleShotSensorController.IDEAL_PEAK_GYRO_RAD_S +
                            BasketballTouchShot.powerError(pull: chosenPullBack) * TripleShotSensorController.POWER_TOLERANCE_RAD_S
                        )
                        .coerceIn(TripleShotSensorController.TOUCH_MIN_EQUIVALENT_GYRO,
                                  TripleShotSensorController.MAX_EQUIVALENT_GYRO)

                let flickBonus: Float
                if hasPowerFlick {
                    flickBonus =
                        (
                            (upwardScreensPerSecond -
                                TripleShotSensorController.TOUCH_POWER_FLICK_START_SCREENS_PER_SEC) *
                                TripleShotSensorController.TOUCH_EXTRA_GYRO_PER_SCREEN_PER_SEC
                            )
                            .coerceIn(0, TripleShotSensorController.TOUCH_MAX_FLICK_GYRO_BONUS)
                } else {
                    flickBonus = 0
                }

                finishShot(
                    peakOverride:
                        (baseTouchGyro + flickBonus)
                            .coerceAtMost(TripleShotSensorController.MAX_EQUIVALENT_GYRO),
                    pullBackDegOverride:
                        chosenPullBack * TripleShotSensorController.PULLBACK_FULL_SCALE_DEG,
                    pullBackNormalizedOverride: chosenPullBack
                )
            } else {
                // Horizontal aiming is kept, but an unfinished load is safely cancelled.
                touchPullBack = 0
                touchMaxPullBack = 0

                if phase == ShotPhase.ARMED || phase == ShotPhase.RELEASING {
                    resetSensorPullOnly()
                    changePhase(ShotPhase.AIMING)
                }

                listener?.onPullBackChanged(normalizedPullBack: 0, armed: false)
            }

            return true

        case AMotionEvent.ACTION_CANCEL:
            touchActive = false
            recycleVelocityTracker()
            touchPullBack = 0
            touchMaxPullBack = 0

            if phase == ShotPhase.ARMED || phase == ShotPhase.RELEASING {
                resetSensorPullOnly()
                changePhase(ShotPhase.AIMING)
            }

            listener?.onPullBackChanged(normalizedPullBack: 0, armed: false)
            return true

        default:
            break
        }

        return touchActive
    }

    /// Kotlin positional call form `handleTouchEvent(event, courtView.width, courtView.height)`.
    func handleTouchEvent(_ event: AMotionEvent, _ viewWidth: Int, _ viewHeight: Int) -> Bool {
        return handleTouchEvent(event: event, viewWidth: viewWidth, viewHeight: viewHeight)
    }

    func onSensorChanged(_ event: ASensorEvent) {
        switch event.sensor.type {
        case ASensor.TYPE_GAME_ROTATION_VECTOR,
             ASensor.TYPE_ROTATION_VECTOR:
            handleRotation(event)

        case ASensor.TYPE_GYROSCOPE:
            handleGyroscope(event)

        default:
            break
        }
    }

    private func handleRotation(_ event: ASensorEvent) {
        ASensorManager.getRotationMatrixFromVector(&matrix, event.values)
        ASensorManager.getOrientation(matrix, &orientation)

        let roll =
            mathToDegrees(orientation[2].toDouble()).toFloat()
        let pitch =
            mathToDegrees(orientation[1].toDouble()).toFloat()

        handleRotation(rollDeg: roll, pitchDeg: pitch)
    }

    /// The rest of Kotlin handleRotation (L429-537), from the device roll and pitch in degrees. Internal so tests can
    /// feed exact angles.
    func handleRotation(rollDeg roll: Float, pitchDeg pitch: Float) {
        if baseRollDeg.isNaN || basePitchDeg.isNaN {
            baseRollDeg = roll
            basePitchDeg = pitch
            currentRollDeg = 0
            currentPitchDeg = 0
            sensorAim = 0
            if movementEnabled {
                listener?.onMovementChanged(horizontal: 0, vertical: 0)
            } else {
                emitCombinedAim()
            }
            return
        }

        currentRollDeg = normalizeDeg(roll - baseRollDeg)
        currentPitchDeg = normalizeDeg(pitch - basePitchDeg)

        if movementEnabled {
            listener?.onMovementChanged(
                horizontal: movementAxis(currentRollDeg / TripleShotSensorController.MOVE_FULL_SCALE_DEG),
                vertical: movementAxis(currentPitchDeg / TripleShotSensorController.MOVE_FULL_SCALE_DEG)
            )
            return
        }

        // Phone wobble must not steer a deliberate finger gesture off its visible arc.
        if touchActive { return }

        sensorAim =
            (currentRollDeg / TripleShotSensorController.AIM_FULL_SCALE_DEG)
                .coerceIn(-TripleShotSensorController.MAX_AIM, TripleShotSensorController.MAX_AIM)

        emitCombinedAim()

        if
            !shotEnabled ||
            phase == ShotPhase.WAITING_FOR_ANSWER ||
            touchActive
        {
            return
        }

        switch phase {
        case ShotPhase.AIMING:
            let pullMagnitude = abs(currentPitchDeg)
            let normalized =
                (pullMagnitude / TripleShotSensorController.PULLBACK_FULL_SCALE_DEG)
                    .coerceIn(0, TripleShotSensorController.MAX_PULL)

            listener?.onPullBackChanged(normalizedPullBack: normalized, armed: false)

            if pullMagnitude >= TripleShotSensorController.ARM_PITCH_DEG {
                let s = currentPitchDeg.ksign
                pullDirectionSign =
                    s != 0 ? s : 1
                currentSignedPullDeg = pullMagnitude
                previousSignedPullDeg = pullMagnitude
                maxPullBackDeg = pullMagnitude

                changePhase(ShotPhase.ARMED)
                listener?.onPullBackChanged(normalizedPullBack: normalized, armed: true)
            }

        case ShotPhase.ARMED:
            let signedPull =
                (currentPitchDeg * pullDirectionSign)
                    .coerceAtLeast(0)

            previousSignedPullDeg = currentSignedPullDeg
            currentSignedPullDeg = signedPull
            maxPullBackDeg = kmax(maxPullBackDeg, signedPull)

            listener?.onPullBackChanged(
                normalizedPullBack: (signedPull / TripleShotSensorController.PULLBACK_FULL_SCALE_DEG)
                    .coerceIn(0, TripleShotSensorController.MAX_PULL),
                armed: true
            )

            /*
             * If the player gently returns without enough release speed, safely
             * disarm instead of launching an accidental weak shot.
             */
            if
                signedPull <= TripleShotSensorController.DISARM_NEAR_NEUTRAL_DEG &&
                releasePeakGyro == 0
            {
                resetSensorPullOnly()
                changePhase(ShotPhase.AIMING)
                listener?.onPullBackChanged(normalizedPullBack: 0, armed: false)
            }

        case ShotPhase.RELEASING:
            let signedPull =
                (currentPitchDeg * pullDirectionSign)
                    .coerceAtLeast(0)

            previousSignedPullDeg = currentSignedPullDeg
            currentSignedPullDeg = signedPull

            listener?.onPullBackChanged(
                normalizedPullBack: (signedPull / TripleShotSensorController.PULLBACK_FULL_SCALE_DEG)
                    .coerceIn(0, TripleShotSensorController.MAX_PULL),
                armed: true
            )

        case ShotPhase.WAITING_FOR_ANSWER:
            break
        }
    }

    private func handleGyroscope(_ event: ASensorEvent) {
        if
            !shotEnabled ||
            phase == ShotPhase.WAITING_FOR_ANSWER ||
            touchActive
        {
            return
        }

        let now = ASystem.currentTimeMillis()

        // Rotation around the device X axis corresponds to the forward/back shooting motion.
        let pitchRate = abs(event.values[0])

        switch phase {
        case ShotPhase.ARMED:
            let movingBackTowardNeutral =
                maxPullBackDeg - currentSignedPullDeg >= TripleShotSensorController.RETURN_BEFORE_RELEASE_DEG ||
                    previousSignedPullDeg - currentSignedPullDeg >= TripleShotSensorController.RETURN_FRAME_DELTA_DEG

            if
                movingBackTowardNeutral &&
                pitchRate >= TripleShotSensorController.RELEASE_START_RAD_S &&
                now - lastShotAtMs >= TripleShotSensorController.SHOT_COOLDOWN_MS
            {
                releaseStartedAtMs = now
                releasePeakGyro = pitchRate
                changePhase(ShotPhase.RELEASING)
            }

        case ShotPhase.RELEASING:
            releasePeakGyro =
                kmax(releasePeakGyro, pitchRate)

            let age = now - releaseStartedAtMs
            let returnedEnough =
                currentSignedPullDeg <= TripleShotSensorController.RELEASE_FINISH_PULL_DEG
            let slowedDown =
                age >= TripleShotSensorController.MIN_RELEASE_MS &&
                    pitchRate <= TripleShotSensorController.RELEASE_END_RAD_S
            let timedOut =
                age >= TripleShotSensorController.MAX_RELEASE_MS

            if (returnedEnough && slowedDown) || timedOut {
                finishShot()
            }

        case ShotPhase.AIMING,
             ShotPhase.WAITING_FOR_ANSWER:
            break
        }
    }

    private func finishShot(
        peakOverride: Float? = nil,
        pullBackDegOverride: Float? = nil,
        pullBackNormalizedOverride: Float? = nil
    ) {
        if !shotEnabled { return }

        let peak =
            (peakOverride ?? releasePeakGyro)
                .coerceAtLeast(0)

        let shotPullBackDeg =
            (pullBackDegOverride ?? maxPullBackDeg)
                .coerceAtLeast(0)

        /*
         * Negative = weak, positive = strong.
         * The real ball engine uses this continuously; it is not converted to a
         * boolean "make chance".
         */
        let powerError =
            ((peak - TripleShotSensorController.IDEAL_PEAK_GYRO_RAD_S) / TripleShotSensorController.POWER_TOLERANCE_RAD_S)
                .coerceIn(-1.7, 1.7)

        let arcError =
            ((shotPullBackDeg - TripleShotSensorController.IDEAL_PULLBACK_DEG) / TripleShotSensorController.ARC_TOLERANCE_DEG)
                .coerceIn(-1.7, 1.7)

        let aimError =
            combinedAim()
                .coerceIn(-TripleShotSensorController.MAX_AIM, TripleShotSensorController.MAX_AIM)

        shotEnabled = false
        lastShotAtMs = ASystem.currentTimeMillis()

        let normalizedPullBack =
            (pullBackNormalizedOverride
                ?? (shotPullBackDeg / TripleShotSensorController.PULLBACK_FULL_SCALE_DEG))
                .coerceIn(0, TripleShotSensorController.MAX_PULL)

        listener?.onShotGesture(
            skill: ShotSkill(
                aimError: aimError,
                powerError: powerError,
                arcError: arcError,
                rawPeakGyro: peak,
                rawReleasePitchDeg: shotPullBackDeg
            ),
            pullBack01: normalizedPullBack
        )

        touchPullBack = 0
        touchMaxPullBack = 0
        resetGestureState(ShotPhase.WAITING_FOR_ANSWER)
    }

    private func combinedAim() -> Float {
        return (sensorAim + touchAimOffset)
            .coerceIn(-TripleShotSensorController.MAX_AIM, TripleShotSensorController.MAX_AIM)
    }

    private func emitCombinedAim() {
        listener?.onAimChanged(normalizedAim: combinedAim())
    }

    private func changePhase(_ newPhase: ShotPhase) {
        if phase == newPhase { return }
        phase = newPhase
        listener?.onShotPhaseChanged(phase: newPhase)
    }

    private func resetSensorPullOnly() {
        pullDirectionSign = 0
        maxPullBackDeg = 0
        currentSignedPullDeg = 0
        previousSignedPullDeg = 0
        releaseStartedAtMs = 0
        releasePeakGyro = 0
    }

    private func resetGestureState(_ newPhase: ShotPhase) {
        resetSensorPullOnly()
        touchPullBack = 0
        touchMaxPullBack = 0
        phase = newPhase
        listener?.onShotPhaseChanged(phase: newPhase)
    }

    private func calibrateOrientation() {
        baseRollDeg = Float.nan
        basePitchDeg = Float.nan
        currentRollDeg = 0
        currentPitchDeg = 0
        sensorAim = 0
    }

    private func recycleVelocityTracker() {
        velocityTracker?.recycle()
        velocityTracker = nil
    }

    func onAccuracyChanged(
        _ sensor: ASensor?,
        _ accuracy: Int
    ) {}

    private func movementAxis(_ raw: Float) -> Float {
        let clamped = raw.coerceIn(-1, 1)
        let magnitude = abs(clamped)
        if magnitude <= TripleShotSensorController.MOVE_DEAD_ZONE { return 0 }

        let scaled =
            ((magnitude - TripleShotSensorController.MOVE_DEAD_ZONE) / (1 - TripleShotSensorController.MOVE_DEAD_ZONE))
                .coerceIn(0, 1)

        return scaled * clamped.ksign
    }

    private func normalizeDeg(_ value: Float) -> Float {
        var v = value
        while v > 180 { v -= 360 }
        while v < -180 { v += 360 }
        return v
    }

    // companion object
    private static let MAX_AIM: Float = 1.30
    private static let MAX_PULL: Float = 1.20

    // HORSE movement behaves like a gentle two-axis joystick around the neutral pose.
    private static let MOVE_FULL_SCALE_DEG: Float = 13
    private static let MOVE_DEAD_ZONE: Float = 0.14

    // Sensor aim: a modest hand rotation now covers a visibly wide target range.
    private static let AIM_FULL_SCALE_DEG: Float = 11.5

    // Sensor pull-back / arc tuning.
    // A shallow load is intentionally legal: HORSE must let the player take a bad/flat
    // shot and miss. Release speed still prevents a tiny accidental tilt from firing.
    private static let ARM_PITCH_DEG: Float = 3.0
    private static let PULLBACK_FULL_SCALE_DEG: Float = 20
    private static let IDEAL_PULLBACK_DEG: Float = 15
    private static let ARC_TOLERANCE_DEG: Float = 7
    private static let DISARM_NEAR_NEUTRAL_DEG: Float = 1.15

    // Sensor forward-release / power tuning.
    private static let RELEASE_START_RAD_S: Float = 1.55
    private static let RELEASE_END_RAD_S: Float = 0.68
    private static let IDEAL_PEAK_GYRO_RAD_S: Float = 3.05
    private static let POWER_TOLERANCE_RAD_S: Float = 1.35
    private static let RETURN_BEFORE_RELEASE_DEG: Float = 1.8
    private static let RETURN_FRAME_DELTA_DEG: Float = 0.55
    private static let RELEASE_FINISH_PULL_DEG: Float = 5.0
    private static let MIN_RELEASE_MS: Int64 = 70
    private static let MAX_RELEASE_MS: Int64 = 650
    private static let SHOT_COOLDOWN_MS: Int64 = 550

    // Touch tuning. A drag can be performed anywhere on the court.
    // The low arm threshold is deliberate: a visibly shallow guide must still be shootable.
    private static let TOUCH_AIM_FULL_SCALE_SCREEN_FRACTION: Float = 0.42
    private static let TOUCH_PULL_FULL_SCALE_SCREEN_FRACTION: Float = 0.19
    private static let TOUCH_ARM_THRESHOLD: Float = 0.12
    private static let MIN_TOUCH_RELEASE_PULL: Float = 0.10

    /*
     * Touch power tuning.
     *
     * Simple release remains the default interaction, but pull-back now affects both
     * trajectory shape and strength. Around 0.70 is the natural sweet spot.
     * Lower loads are intentionally a little short; very high loads run long.
     */
    private static let TOUCH_IDEAL_PULL_FOR_POWER: Float = 0.70   // unused (dead in Kotlin too)
    private static let TOUCH_PULL_TO_GYRO: Float = 1.70           // unused (dead in Kotlin too)
    private static let TOUCH_MIN_EQUIVALENT_GYRO: Float = 2.25

    // A flick is an optional advanced modifier rather than a requirement.
    private static let TOUCH_POWER_FLICK_START_SCREENS_PER_SEC: Float = 0.55
    private static let TOUCH_EXTRA_GYRO_PER_SCREEN_PER_SEC: Float = 0.78
    private static let TOUCH_MAX_FLICK_GYRO_BONUS: Float = 0.72
    private static let MAX_EQUIVALENT_GYRO: Float = 5.8
}

extension TripleShotSensorController.Listener {
    /// Kotlin default body `fun onMovementChanged(horizontal: Float, vertical: Float) = Unit`.
    func onMovementChanged(horizontal: Float, vertical: Float) {}
}
