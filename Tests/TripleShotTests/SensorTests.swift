import CoreMotion
import XCTest
@testable import MinikTripleShot

// Sensor-area parity tests (spec 20 §7.4 / §9.8, spec 19 §4.1.3, spec 24 AC-31):
// TripleShotSensorController, AVelocityTracker (LSQ2), ASensorManager (rotation math, CoreMotion mapping, registration
// and dispatch) and AOrientationEventListener.
//
// The golden scripts (SensorGolden) come from running the UNMODIFIED Android sources sensor/TripleShotSensorController.kt
// and game/BasketballTouchShot.kt (snapshot dd722e5) on the JVM against minimal android.* stubs: AOSP's
// SensorManager.getRotationMatrixFromVector/getOrientation copied verbatim, a Java transcription of the native LSQ2
// VelocityTracker (Android 14+), and a same-package `System` object feeding System.currentTimeMillis(). Floats are
// IEEE-754 bit patterns; text after " #" is a readable comment. In a script, "> " lines are inputs, "-- " lines are
// notes and every other line is an expected listener callback (or the Boolean that handleTouchEvent returned).
// Harness: scratchpad/swish/work/kit-sensors/harness (kt/Golden.kt, Frame.java).

final class SensorTests: XCTestCase {

    override func tearDown() {
        AFakeClock.uninstall()
        super.tearDown()
    }

    // MARK: - StoreReadyTest.touchShotMatchesPreviewAndCancelDoesNotFire (androidTest, AC-31)

    func testTouchShotMatchesPreviewAndCancelDoesNotFire() {
        final class Listener: TripleShotSensorController.Listener {
            var shots = 0
            var actual: ShotSkill?
            var aim: Float = 0
            func onAimChanged(normalizedAim: Float) { aim = normalizedAim }
            func onPullBackChanged(normalizedPullBack: Float, armed: Bool) {}
            func onShotPhaseChanged(phase: TripleShotSensorController.ShotPhase) {}
            func onShotGesture(skill: ShotSkill, pullBack01: Float) { shots += 1; actual = skill }
            func onSensorAvailability(hasRotation: Bool, hasGyro: Bool) {}
        }
        let listener = Listener()
        let controller = TripleShotSensorController(context: nil, listener: listener)
        let time = ASystemClock.uptimeMillis()
        func send(_ action: Int, _ x: Float, _ y: Float, _ t: Int64) {
            let e = AMotionEvent.obtain(time, time + t, action, x, y, 0)
            XCTAssertTrue(controller.handleTouchEvent(event: e, viewWidth: 1000, viewHeight: 1000))
            e.recycle()
        }
        controller.prepareForShot()
        send(AMotionEvent.ACTION_DOWN, 400, 300, 0)
        send(AMotionEvent.ACTION_MOVE, 442, 433, 400)
        XCTAssertEqual(0.10, listener.aim, accuracy: 0.005)
        send(AMotionEvent.ACTION_MOVE, 442, 433, 800)
        send(AMotionEvent.ACTION_UP, 442, 433, 1100)
        XCTAssertEqual(1, listener.shots)
        let expected = BasketballTouchShot.skill(aim: 0.10, pull: 0.70)
        XCTAssertEqual(expected.aimError, listener.actual!.aimError, accuracy: 0.005)
        XCTAssertEqual(expected.powerError, listener.actual!.powerError, accuracy: 0.005)
        controller.prepareForShot()
        send(AMotionEvent.ACTION_DOWN, 400, 300, 1400)
        send(AMotionEvent.ACTION_MOVE, 442, 433, 1800)
        send(AMotionEvent.ACTION_CANCEL, 442, 433, 1900)
        XCTAssertEqual(1, listener.shots)
        controller.stop()
    }

    // MARK: - Golden scripts (spec 20 §7.4 vectors, §4.5 callback order, §8 gotchas)

    /// T1 + T2: the StoreReadyTest gesture, every callback in order (T1 = BasketballTouchShot.skill(.10, .70) exactly).
    func testGoldenStoreReadyGestureT1T2() { replay("T1T2") }

    /// T3: a weak touch release; the base power is floored at 2.25 rad/s, the arc clamped at -1.7.
    func testGoldenWeakTouchT3() { replay("T3") }

    /// T4: an upward flick over four MOVE samples (LSQ2 vy ≈ -2371.9 px/s on a 1000 × 2000 court).
    func testGoldenFlickT4() { replay("T4") }

    /// T5: a flick that makes the drag go back up to 0 pull, and the same drag lifted 41 ms after the last MOVE
    /// (the tracker treats the pointer as stopped: no flick, pull floored at 0.10).
    func testGoldenFlickAndStoppedLiftT5() { replay("T5") }

    /// T6: the velocity from two samples (degree-1 least squares) after a pause cleared the tracker.
    func testGoldenTwoSampleVelocityT6() { replay("T6") }

    /// S1 ideal sensor release (clock 10 000 ms) followed by S4: the 550 ms cooldown blocks the next sensor release
    /// and the return below 1.15° disarms instead.
    func testGoldenSensorReleaseS1AndCooldownS4() { replay("S1S4") }

    /// S2: returning to ≤ 1.15° from neutral without release speed disarms.
    func testGoldenDisarmS2() { replay("S2") }

    /// S3: the opposite pitch direction arms (sign +1); the release times out at 650 ms.
    func testGoldenReleaseTimeoutS3() { replay("S3") }

    /// S5 (gotcha 8): a jerk away from neutral starts a release once the load dropped 1.8° below its maximum.
    func testGoldenWrongWayJerkS5() { replay("S5") }

    /// M1: the HORSE joystick (13° full scale, 0.14 dead zone); gyro and touch are inert in movement mode.
    func testGoldenJoystickM1() { replay("M1") }

    /// N1: deltas wrap into -180..180 before scaling.
    func testGoldenWrapN1() { replay("N1") }

    /// §4.5: callback order of start/prepareForAnswer/cancelShot/prepareForShot/prepareForMovement/calibrate/stop, and
    /// gotcha 1: stop() keeps shotEnabled, so touches are refused while tilt still aims.
    func testGoldenCallbackOrderAndStopKeepsShotEnabled() { replay("ORDER") }

    /// A finger freezes the sensor aim; a finger over a sensor-armed shot takes over; other actions return
    /// touchActive; zero-size views refuse; the touch aim offset accumulates across drags and clamps at ±1.30.
    func testGoldenTouchFreezesSensorAndOtherActions() { replay("FREEZE") }

    /// The real rotation-vector path: AOSP getRotationMatrixFromVector + getOrientation + Math.toDegrees. libm's
    /// atan2/asin may differ from the JVM's StrictMath by an ulp, so floats compare within 8 ulps here.
    func testGoldenQuaternionPath() { replay("QUAT", ulps: 8) }

    // MARK: - AVelocityTracker (native LSQ2)

    func testVelocityTrackerMatchesNativeLsq2() {
        let golden = SensorGolden.velocityRows()
        for (name, events) in SensorTests.velocityCases() {
            let tracker = AVelocityTracker.obtain()
            for e in events {
                let me = AMotionEvent.obtain(0, e.t, e.action, e.x, e.y, 0)
                tracker.addMovement(me)
                me.recycle()
            }
            tracker.computeCurrentVelocity(1000)
            let vx = tracker.xVelocity
            let vy = tracker.yVelocity
            tracker.computeCurrentVelocity(1000, 500)
            let got = [sensorHex(vx), sensorHex(vy), sensorHex(tracker.xVelocity), sensorHex(tracker.yVelocity)].joined(separator: " ")
            XCTAssertEqual(got, golden[name], "VelocityTracker case \(name)")
            tracker.recycle()
        }
    }

    /// Batched (historical) samples count exactly like separate MOVE events, as in the native tracker.
    func testVelocityTrackerUsesHistoricalSamples() {
        let separate = AVelocityTracker.obtain()
        let batched = AVelocityTracker.obtain()
        let down = AMotionEvent.obtain(0, 0, AMotionEvent.ACTION_DOWN, 0, 100, 0)
        separate.addMovement(down)
        batched.addMovement(down)
        func px(_ i: Int) -> Float { return Float(i * i) * 0.75 + 3 * Float(i) }
        func py(_ i: Int) -> Float { return 100 - 7.5 * Float(i) }
        for i in 1...12 {
            separate.addMovement(AMotionEvent.obtain(0, Int64(i * 8), AMotionEvent.ACTION_MOVE, px(i), py(i), 0))
        }
        let move = AMotionEvent.obtain(0, 96, AMotionEvent.ACTION_MOVE, px(12), py(12), 0)
        for i in 1...11 {
            move.addHistorySample(eventTimeNanos: Int64(i * 8) * 1_000_000, xs: [px(i)], ys: [py(i)])
        }
        batched.addMovement(move)
        separate.computeCurrentVelocity(1000)
        batched.computeCurrentVelocity(1000)
        XCTAssertEqual(sensorHex(batched.xVelocity), sensorHex(separate.xVelocity))
        XCTAssertEqual(sensorHex(batched.yVelocity), sensorHex(separate.yVelocity))
        XCTAssertEqual(SensorGolden.velocityRows()["curve"]?.split(separator: " ").prefix(2).joined(separator: " "),
                       "\(sensorHex(batched.xVelocity)) \(sensorHex(batched.yVelocity))")
    }

    func testVelocityTrackerPointerQueriesAndClear() {
        let t = AVelocityTracker.obtain()
        t.addMovement(AMotionEvent.obtain(0, 0, AMotionEvent.ACTION_DOWN, 10, 10, 0))
        t.addMovement(AMotionEvent.obtain(0, 10, AMotionEvent.ACTION_MOVE, 20, 30, 0))
        t.addMovement(AMotionEvent.obtain(0, 20, AMotionEvent.ACTION_MOVE, 30, 50, 0))
        t.computeCurrentVelocity(1000)
        XCTAssertEqual(t.getXVelocity(0), 1000, accuracy: 0.05)
        XCTAssertEqual(t.getYVelocity(0), 2000, accuracy: 0.05)
        XCTAssertEqual(t.getXVelocity(1), 0)          // unknown pointer
        XCTAssertEqual(t.xVelocity, t.getXVelocity(0)) // the active pointer is the first one down
        t.clear()
        XCTAssertEqual(t.xVelocity, 0)                 // no active pointer after clear
        XCTAssertTrue(t.isAxisSupported(AVelocityTracker.AXIS_X))
        XCTAssertTrue(t.isAxisSupported(AVelocityTracker.AXIS_Y))
    }

    // MARK: - ASensorManager rotation math (AOSP goldens)

    func testRotationMatrixAndOrientationMatchAosp() {
        for row in SensorGolden.frameRows(prefix: "ROT") {
            let parts = row.split(separator: "|").map { $0.split(separator: " ").map(String.init) }
            let q = parts[0].dropFirst().map(sensorFloat)
            var r9 = [Float](repeating: 0, count: 9)
            ASensorManager.getRotationMatrixFromVector(&r9, q)
            XCTAssertEqual(r9.map(sensorHex), parts[1], "R9 of \(parts[0])")
            var o9 = [Float](repeating: 0, count: 3)
            let returned = ASensorManager.getOrientation(r9, &o9)
            XCTAssertEqual(returned, o9)
            XCTAssertTrue(sensorFloatsMatch(o9.map(sensorHex), parts[2], ulps: 4), "orientation \(o9.map(sensorHex)) vs \(parts[2])")
            var r16 = [Float](repeating: 7, count: 16)
            ASensorManager.getRotationMatrixFromVector(&r16, q)
            XCTAssertEqual(r16.map(sensorHex), parts[3], "R16 of \(parts[0])")
            var o16 = [Float](repeating: 0, count: 3)
            ASensorManager.getOrientation(r16, &o16)
            XCTAssertTrue(sensorFloatsMatch(o16.map(sensorHex), parts[4], ulps: 4), "orientation16 \(o16.map(sensorHex)) vs \(parts[4])")
        }
        var quaternion = [Float](repeating: 0, count: 4)
        ASensorManager.getQuaternionFromVector(&quaternion, [0.25, -0.4, 0.1, 0.8746428])
        XCTAssertEqual(quaternion, [0.8746428, 0.25, -0.4, 0.1])
    }

    // MARK: - AOrientationEventListener

    func testOrientationEventListenerAnglesMatchAndroid() {
        for row in SensorGolden.frameRows(prefix: "ORI") {
            let f = row.split(separator: " ").map(String.init)
            let values = [sensorFloat(f[1]), sensorFloat(f[2]), sensorFloat(f[3])]
            XCTAssertEqual(AOrientationEventListener.orientation(fromAccelerometer: values), Int(f[4])!, row)
        }
        // Math.round(float), which the angle uses, including the 0.49999997 case a naive floor(x + 0.5) gets wrong.
        for pair in SensorGolden.frameRows(prefix: "ROUND")[0].split(separator: " ").dropFirst() {
            let kv = pair.split(separator: ":")
            XCTAssertEqual(sensorFloat(String(kv[0])).roundToInt(), Int(kv[1])!, String(pair))
        }
    }

    func testOrientationEventListenerReportsOnlyChanges() {
        final class Recording: AOrientationEventListener {
            var got: [Int] = []
            override func onOrientationChanged(_ orientation: Int) { got.append(orientation) }
        }
        let manager = ASensorManager(motionManager: nil, availableTypes: [ASensor.TYPE_ACCELEROMETER])
        let listener = Recording(sensorManager: manager)
        XCTAssertTrue(listener.canDetectOrientation())
        listener.enable()
        XCTAssertTrue(manager.accelerometerRunning)
        XCTAssertEqual(manager.accelerometerPeriodUs, 200_000)          // SENSOR_DELAY_NORMAL
        let g = ASensorManager.STANDARD_GRAVITY
        func feed(_ v: [Float]) { manager.deliverAccelerometer(timestamp: 1, values: v) }
        feed([0, 0, g])          // flat: ORIENTATION_UNKNOWN == the initial value, no callback
        feed([0, g, 0])          // upright portrait
        feed([0, g, 0])
        feed([-g, 0, 0])         // left side at the top
        XCTAssertEqual(listener.got, [0, 90])
        listener.disable()
        XCTAssertFalse(manager.accelerometerRunning)
        feed([0, g, 0])
        XCTAssertEqual(listener.got, [0, 90])
        listener.enable()
        feed([-g, 0, 0])         // the last value survives disable/enable (Java mOrientation is kept)
        feed([0, 0, g])
        XCTAssertEqual(listener.got, [0, 90, -1])
        listener.disable()

        var closureGot: [Int] = []
        let noAccelerometer = ASensorManager(motionManager: nil, availableTypes: [])
        let blind = AOrientationEventListener(sensorManager: noAccelerometer)
        XCTAssertFalse(blind.canDetectOrientation())
        blind.enable()                                            // logs "Cannot detect sensors", like Android
        XCTAssertFalse(noAccelerometer.accelerometerRunning)
        let closure = AOrientationEventListener { closureGot.append($0) }
        closure.onOrientationChanged(270)
        XCTAssertEqual(closureGot, [270])
        XCTAssertEqual(closure.canDetectOrientation(),
                       ASensorManager.shared.getDefaultSensor(ASensor.TYPE_ACCELEROMETER) != nil)
    }

    /// The Kotlin call shapes the screens translate to resolve to the intended initialisers (no ambiguity).
    func testKotlinShapedConstructors() {
        final class Quiet: TripleShotSensorController.Listener {
            func onAimChanged(normalizedAim: Float) {}
            func onPullBackChanged(normalizedPullBack: Float, armed: Bool) {}
            func onShotPhaseChanged(phase: TripleShotSensorController.ShotPhase) {}
            func onShotGesture(skill: ShotSkill, pullBack01: Float) {}
            func onSensorAvailability(hasRotation: Bool, hasGyro: Bool) {}
        }
        let quiet = Quiet()
        let context: AContext = AApplication.shared
        let labelled = TripleShotSensorController(context: context, listener: quiet)      // DESIGN 2.1 call site
        let positional = TripleShotSensorController(context, quiet)                       // Kotlin positional form
        quiet.onMovementChanged(horizontal: 1, vertical: 1)                              // Kotlin default body
        labelled.prepareForAnswer()
        positional.prepareForAnswer()

        var seen: [Int] = []
        let withContext = AOrientationEventListener(context) { seen.append($0) }        // object : ...(context) { }
        let withRate = AOrientationEventListener(context, ASensorManager.SENSOR_DELAY_UI)
        let plain = AOrientationEventListener()
        withContext.onOrientationChanged(90)
        withRate.onOrientationChanged(180)                                              // no closure: no-op
        plain.onOrientationChanged(270)
        XCTAssertEqual(seen, [90])
        let detects = ASensorManager.shared.getDefaultSensor(ASensor.TYPE_ACCELEROMETER) != nil
        XCTAssertEqual(withContext.canDetectOrientation(), detects)
        XCTAssertEqual(withRate.canDetectOrientation(), detects)
        XCTAssertEqual(AOrientationEventListener.ORIENTATION_UNKNOWN, -1)
    }

    // MARK: - CoreMotion → Android conventions (spec 20 §4.3 / §9.3)

    func testCoreMotionMappingFollowsAndroidConventions() {
        func rollPitchDegrees(_ v: [Float]) -> (roll: Double, pitch: Double, azimuth: Double) {
            var r = [Float](repeating: 0, count: 9)
            ASensorManager.getRotationMatrixFromVector(&r, v)
            var o = [Float](repeating: 0, count: 3)
            ASensorManager.getOrientation(r, &o)
            return (Double(o[2]) * 180 / Double.pi, Double(o[1]) * 180 / Double.pi, Double(o[0]) * 180 / Double.pi)
        }
        let identity = CMQuaternion(x: 0, y: 0, z: 0, w: 1)
        let mapping = ASensorManager.Mapping.self

        // Flat, face up: roll 0, pitch 0, the identity quaternion (w >= 0).
        var v = mapping.gameRotationVector(attitude: identity, gravity: CMAcceleration(x: 0, y: 0, z: -1))
        XCTAssertEqual(v.count, 4)
        XCTAssertEqual(v[0], 0, accuracy: 1e-6); XCTAssertEqual(v[1], 0, accuracy: 1e-6)
        XCTAssertEqual(v[2], 0, accuracy: 1e-6); XCTAssertEqual(v[3], 1, accuracy: 1e-6)
        var a = rollPitchDegrees(v)
        XCTAssertEqual(a.roll, 0, accuracy: 1e-4); XCTAssertEqual(a.pitch, 0, accuracy: 1e-4)

        // Upright portrait (top edge up): CoreMotion +90° about X, gravity (0, -1, 0) → Android pitch -90°.
        let s45 = (0.5 as Double).squareRoot()
        v = mapping.gameRotationVector(attitude: CMQuaternion(x: s45, y: 0, z: 0, w: s45),
                                       gravity: CMAcceleration(x: 0, y: -1, z: 0))
        XCTAssertEqual(rollPitchDegrees(v).pitch, -90, accuracy: 0.1)

        // Right edge down by 20° from flat → roll +20° (and gravity.x > 0).
        let r20 = 20.0 * Double.pi / 180
        v = mapping.gameRotationVector(attitude: CMQuaternion(x: 0, y: sin(r20 / 2), z: 0, w: cos(r20 / 2)),
                                       gravity: CMAcceleration(x: sin(r20), y: 0, z: -cos(r20)))
        a = rollPitchDegrees(v)
        XCTAssertEqual(a.roll, 20, accuracy: 1e-3); XCTAssertEqual(a.pitch, 0, accuracy: 1e-3)

        // Spec §4.13: screen tilted β = 45° from flat and steered φ = 20° (right edge down):
        // roll = atan(tan β · sin φ), pitch = -asin(sin β · cos φ). The attitude is left at identity on purpose: the
        // vertical axis follows the gravity vector, so pitch and roll come out right regardless of the heading part.
        let beta = 45.0 * Double.pi / 180, phi = 20.0 * Double.pi / 180
        v = mapping.gameRotationVector(attitude: identity,
                                       gravity: CMAcceleration(x: sin(phi) * sin(beta), y: -cos(phi) * sin(beta),
                                                               z: -cos(beta)))
        a = rollPitchDegrees(v)
        XCTAssertEqual(a.roll, atan(tan(beta) * sin(phi)) * 180 / Double.pi, accuracy: 1e-3)
        XCTAssertEqual(a.pitch, -asin(sin(beta) * cos(phi)) * 180 / Double.pi, accuracy: 1e-3)

        // A consistent sample (gravity = the attitude's vertical) round-trips the attitude quaternion.
        let q = sensorNormalized(CMQuaternion(x: 0.21, y: -0.33, z: 0.12, w: 0.91))
        let up = (2 * (q.x * q.z - q.y * q.w), 2 * (q.y * q.z + q.x * q.w), 1 - 2 * (q.x * q.x + q.y * q.y))
        v = mapping.gameRotationVector(attitude: q, gravity: CMAcceleration(x: -up.0, y: -up.1, z: -up.2))
        XCTAssertEqual(Double(v[0]), q.x, accuracy: 1e-6); XCTAssertEqual(Double(v[1]), q.y, accuracy: 1e-6)
        XCTAssertEqual(Double(v[2]), q.z, accuracy: 1e-6); XCTAssertEqual(Double(v[3]), q.w, accuracy: 1e-6)

        // TYPE_ROTATION_VECTOR: CoreMotion's north frame (X north, Y west) → Android ENU; 5 values, heading accuracy -1.
        v = mapping.rotationVector(attitude: identity, gravity: CMAcceleration(x: 0, y: 0, z: -1))
        XCTAssertEqual(v.count, 5)
        XCTAssertEqual(v[4], -1)
        XCTAssertEqual(rollPitchDegrees(v).azimuth, -90, accuracy: 1e-3)   // device Y points west
        let r90 = -45.0 * Double.pi / 180
        v = mapping.rotationVector(attitude: CMQuaternion(x: 0, y: 0, z: sin(r90), w: cos(r90)),
                                   gravity: CMAcceleration(x: 0, y: 0, z: -1))
        XCTAssertEqual(rollPitchDegrees(v).azimuth, 0, accuracy: 1e-3)     // device Y points north

        // Accelerometer, gravity and linear acceleration in m/s² with Android's sign (flat face up → z = +g).
        let g = ASensorManager.STANDARD_GRAVITY
        XCTAssertEqual(mapping.accelerometer(CMAcceleration(x: 0, y: 0, z: -1)), [-0.0, -0.0, g])
        XCTAssertEqual(mapping.accelerometer(CMAcceleration(x: 0, y: -1, z: 0)), [-0.0, g, -0.0])
        XCTAssertEqual(mapping.gravity(CMAcceleration(x: 0.5, y: 0, z: 0)), [-0.5 * g, -0.0, -0.0])
        XCTAssertEqual(mapping.linearAcceleration(CMAcceleration(x: 0, y: 0, z: -0.5))[2], 0.5 * g)
        XCTAssertEqual(AOrientationEventListener.orientation(fromAccelerometer: mapping.accelerometer(
            CMAcceleration(x: 0, y: -1, z: 0))), 0)
        XCTAssertEqual(mapping.gyroscope(CMRotationRate(x: 1.5, y: -2, z: 0.25)), [1.5, -2, 0.25])

        XCTAssertEqual(mapping.accuracy(.high), ASensorManager.SENSOR_STATUS_ACCURACY_HIGH)
        XCTAssertEqual(mapping.accuracy(.medium), ASensorManager.SENSOR_STATUS_ACCURACY_MEDIUM)
        XCTAssertEqual(mapping.accuracy(.low), ASensorManager.SENSOR_STATUS_ACCURACY_LOW)
        XCTAssertEqual(mapping.accuracy(.uncalibrated), ASensorManager.SENSOR_STATUS_UNRELIABLE)
    }

    // MARK: - ASensorManager registration, rates and dispatch

    func testGetDelay() {
        XCTAssertEqual(ASensorManager.getDelay(ASensorManager.SENSOR_DELAY_FASTEST), 0)
        XCTAssertEqual(ASensorManager.getDelay(ASensorManager.SENSOR_DELAY_GAME), 20_000)
        XCTAssertEqual(ASensorManager.getDelay(ASensorManager.SENSOR_DELAY_UI), 66_667)
        XCTAssertEqual(ASensorManager.getDelay(ASensorManager.SENSOR_DELAY_NORMAL), 200_000)
        XCTAssertEqual(ASensorManager.getDelay(5_000), 5_000)
    }

    func testSensorManagerRegistrationRatesAndDispatch() {
        let manager = ASensorManager(motionManager: nil, availableTypes: [
            ASensor.TYPE_GAME_ROTATION_VECTOR, ASensor.TYPE_GYROSCOPE, ASensor.TYPE_ACCELEROMETER,
        ])
        XCTAssertNil(manager.getDefaultSensor(ASensor.TYPE_ROTATION_VECTOR))   // absent = Android's null sensor
        XCTAssertEqual(manager.getSensorList(ASensor.TYPE_ALL).map { $0.type }, [1, 4, 15])
        let rotation = manager.getDefaultSensor(ASensor.TYPE_GAME_ROTATION_VECTOR)!
        let gyro = manager.getDefaultSensor(ASensor.TYPE_GYROSCOPE)!
        XCTAssertTrue(rotation === manager.getDefaultSensor(ASensor.TYPE_GAME_ROTATION_VECTOR))
        let listener = SensorEventRecorder()

        XCTAssertFalse(manager.registerListener(listener, nil, ASensorManager.SENSOR_DELAY_GAME))
        XCTAssertFalse(manager.registerListener(listener, ASensor(type: ASensor.TYPE_GAME_ROTATION_VECTOR),
                                                ASensorManager.SENSOR_DELAY_GAME))   // not one of this device's
        XCTAssertFalse(manager.deviceMotionRunning)
        XCTAssertTrue(manager.registerListener(listener, rotation, ASensorManager.SENSOR_DELAY_GAME))
        XCTAssertFalse(manager.registerListener(listener, rotation, ASensorManager.SENSOR_DELAY_FASTEST))  // no-op
        XCTAssertTrue(manager.deviceMotionRunning)
        XCTAssertEqual(manager.deviceMotionPeriodUs, 20_000)
        XCTAssertEqual(manager.deviceMotionFrame, .xArbitraryZVertical)
        XCTAssertTrue(manager.registerListener(listener, gyro, ASensorManager.SENSOR_DELAY_NORMAL))
        XCTAssertEqual(manager.deviceMotionPeriodUs, 20_000)

        // One second of 50 Hz samples: the rotation vector gets every sample, the 200 ms gyroscope every tenth,
        // rotation before gyroscope within a sample; onAccuracyChanged once per sensor, before its first event.
        let base = ProcessInfo.processInfo.systemUptime - 2
        for k in 0..<50 {
            manager.deliverDeviceMotion(timestamp: base + Double(k) * 0.02, magneticAccuracy: 0) { type in
                type == ASensor.TYPE_GAME_ROTATION_VECTOR ? [0.1, 0.2, 0.3, 0.9, 42] : [Float(k), 0, 0]
            }
        }
        let rotationEvents = listener.events.filter { $0.type == ASensor.TYPE_GAME_ROTATION_VECTOR }
        XCTAssertEqual(rotationEvents.count, 50)
        XCTAssertEqual(listener.events.filter { $0.type == ASensor.TYPE_GYROSCOPE }.map { $0.values[0] },
                       [0, 10, 20, 30, 40])
        XCTAssertEqual(Array(listener.log.prefix(4)), ["accuracy 15 3", "changed 15", "accuracy 4 3", "changed 4"])
        XCTAssertEqual(listener.log.filter { $0.hasPrefix("accuracy") }.count, 2)
        XCTAssertEqual(rotationEvents[0].values, [0.1, 0.2, 0.3, 0.9])          // 4 values for the game vector
        XCTAssertEqual(Set(rotationEvents.map { $0.object }).count, 1)          // one reused SensorEvent per sensor
        let dt = rotationEvents[1].timestamp - rotationEvents[0].timestamp
        XCTAssertEqual(Double(dt), 20_000_000, accuracy: 2_000_000)             // nanoseconds

        manager.unregisterListener(listener, gyro)
        listener.events.removeAll()
        manager.deliverDeviceMotion(timestamp: base + 1.2, magneticAccuracy: 0) { _ in [1, 1, 1, 1] }
        XCTAssertEqual(listener.events.map { $0.type }, [ASensor.TYPE_GAME_ROTATION_VECTOR])
        manager.unregisterListener(listener)
        XCTAssertFalse(manager.deviceMotionRunning)
        listener.events.removeAll()
        manager.deliverDeviceMotion(timestamp: base + 1.3, magneticAccuracy: 0) { _ in [1, 1, 1, 1] }
        XCTAssertTrue(listener.events.isEmpty)

        // A new registration is a new queue: the accuracy is reported again.
        listener.log.removeAll()
        XCTAssertTrue(manager.registerListener(listener, rotation, ASensorManager.SENSOR_DELAY_UI))
        XCTAssertEqual(manager.deviceMotionPeriodUs, 66_667)
        manager.deliverDeviceMotion(timestamp: base + 1.4, magneticAccuracy: 0) { _ in [1, 1, 1, 1] }
        XCTAssertEqual(listener.log, ["accuracy 15 3", "changed 15"])

        // A listener that unregisters inside its callback gets nothing more from the same sample.
        XCTAssertTrue(manager.registerListener(listener, gyro, ASensorManager.SENSOR_DELAY_UI))
        listener.events.removeAll()
        listener.onEvent = { [unowned manager, unowned listener] _ in manager.unregisterListener(listener) }
        manager.deliverDeviceMotion(timestamp: base + 1.6, magneticAccuracy: 0) { _ in [1, 1, 1, 1] }
        XCTAssertEqual(listener.events.map { $0.type }, [ASensor.TYPE_GAME_ROTATION_VECTOR])
        listener.onEvent = nil

        // The accelerometer is its own stream; FASTEST is capped at 100 Hz.
        let accelerometer = manager.getDefaultSensor(ASensor.TYPE_ACCELEROMETER)!
        XCTAssertTrue(manager.registerListener(listener, accelerometer, ASensorManager.SENSOR_DELAY_FASTEST))
        XCTAssertTrue(manager.accelerometerRunning)
        XCTAssertEqual(manager.accelerometerPeriodUs, ASensorManager.MIN_SAMPLING_PERIOD_US)
        listener.events.removeAll()
        manager.deliverAccelerometer(timestamp: base + 1.7, values: [0, 0, 9.80665])
        XCTAssertEqual(listener.events.map { $0.values }, [[0, 0, 9.80665]])
        manager.unregisterListener(listener)
        XCTAssertFalse(manager.accelerometerRunning)
    }

    func testRotationVectorUsesTheMagneticNorthFrame() {
        let manager = ASensorManager(motionManager: nil, availableTypes: [ASensor.TYPE_ROTATION_VECTOR])
        let listener = SensorEventRecorder()
        XCTAssertTrue(manager.registerListener(listener, manager.getDefaultSensor(ASensor.TYPE_ROTATION_VECTOR),
                                               ASensorManager.SENSOR_DELAY_GAME))
        XCTAssertEqual(manager.deviceMotionFrame, .xMagneticNorthZVertical)
        manager.deliverDeviceMotion(timestamp: 1, magneticAccuracy: ASensorManager.SENSOR_STATUS_ACCURACY_MEDIUM) { _ in
            [0, 0, 0, 1, -1]
        }
        XCTAssertEqual(listener.log, ["accuracy 11 2", "changed 11"])
        XCTAssertEqual(listener.events.first?.values, [0, 0, 0, 1, -1])
        manager.unregisterListener(listener)
    }

    // MARK: - Controller on the sensor service (device-motion samples end to end)

    func testDeviceMotionSamplesDriveTheControllerRotationBeforeGyroscope() {
        let start: Int64 = 9_000_000_000_000
        AFakeClock.install(nanos: start)                 // wall clock ≈ 2025, like System.currentTimeMillis()
        let manager = ASensorManager(motionManager: nil, availableTypes: [
            ASensor.TYPE_GAME_ROTATION_VECTOR, ASensor.TYPE_GYROSCOPE,
        ])
        let recorder = SensorGoldenRecorder()
        let controller = TripleShotSensorController(context: nil, listener: recorder, sensorManager: manager)
        controller.start()
        XCTAssertEqual(recorder.lines, ["avail true true"])
        XCTAssertTrue(manager.deviceMotionRunning)
        XCTAssertEqual(manager.deviceMotionPeriodUs, 20_000)               // SENSOR_DELAY_GAME
        controller.prepareForShot()
        recorder.lines.removeAll()

        let base = ProcessInfo.processInfo.systemUptime - 5
        func sample(_ k: Int, roll: Double, pitch: Double, gyroX: Float) {
            AFakeClock.nanos = start + Int64(k) * 20_000_000
            let r = roll * Double.pi / 180, p = pitch * Double.pi / 180
            // Android: pitch = asin(-up.y), roll = atan2(-up.x, up.z); CoreMotion gravity = -up.
            let gravity = CMAcceleration(x: sin(r) * cos(p), y: sin(p), z: -cos(r) * cos(p))
            manager.deliverDeviceMotion(timestamp: base + Double(k) * 0.02, magneticAccuracy: 0) { type in
                type == ASensor.TYPE_GAME_ROTATION_VECTOR
                    ? ASensorManager.Mapping.gameRotationVector(attitude: CMQuaternion(x: 0, y: 0, z: 0, w: 1),
                                                                gravity: gravity)
                    : [gyroX, 0, 0]
            }
        }
        sample(0, roll: 2, pitch: -40, gyroX: 0)       // neutral pose
        sample(1, roll: 2, pitch: -46, gyroX: 0.2)     // 6° → ARMED (sign -1)
        sample(2, roll: 2, pitch: -55, gyroX: 0.3)     // 15° maximum
        sample(3, roll: 2, pitch: -51, gyroX: 2.5)     // moving back + fast: RELEASING (needs rotation first)
        XCTAssertEqual(recorder.lines.filter { $0.hasPrefix("phase") }, ["phase ARMED", "phase RELEASING"])
        sample(4, roll: 2, pitch: -44, gyroX: 3.2)     // peak 3.2, too early to finish
        sample(5, roll: 2, pitch: -41, gyroX: 1.0)
        sample(6, roll: 3.15, pitch: -39, gyroX: 0.9)
        sample(7, roll: 3.15, pitch: -40, gyroX: 0.5)  // 80 ms, slowed down, returned → finishShot
        let shots = recorder.shots
        XCTAssertEqual(shots.count, 1)
        if let shot = shots.first {
            XCTAssertEqual(shot.skill.aimError, 0.1, accuracy: 1e-3)                // 1.15° / 11.5°
            XCTAssertEqual(shot.skill.powerError, (3.2 - 3.05) / 1.35, accuracy: 1e-4)
            XCTAssertEqual(shot.skill.arcError, 0, accuracy: 1e-3)
            XCTAssertEqual(shot.skill.rawPeakGyro, 3.2)
            XCTAssertEqual(shot.skill.rawReleasePitchDeg, 15, accuracy: 1e-3)
            XCTAssertEqual(shot.pullBack01, 0.75, accuracy: 1e-4)
        }
        XCTAssertEqual(recorder.lines.last, "phase WAITING_FOR_ANSWER")
        controller.stop()
        XCTAssertFalse(manager.deviceMotionRunning)
    }

    func testControllerWithoutSensorsRegistersNothing() {
        let manager = ASensorManager(motionManager: nil, availableTypes: [])
        let recorder = SensorGoldenRecorder()
        let controller = TripleShotSensorController(context: nil, listener: recorder, sensorManager: manager)
        controller.start()
        XCTAssertEqual(recorder.lines, ["avail false false"])
        XCTAssertFalse(manager.deviceMotionRunning)
        controller.stop()
    }

    func testControllerFallsBackToTheRotationVector() {
        let manager = ASensorManager(motionManager: nil, availableTypes: [ASensor.TYPE_ROTATION_VECTOR])
        let recorder = SensorGoldenRecorder()
        let controller = TripleShotSensorController(context: nil, listener: recorder, sensorManager: manager)
        controller.start()
        XCTAssertEqual(recorder.lines, ["avail true false"])
        XCTAssertEqual(manager.deviceMotionFrame, .xMagneticNorthZVertical)
        controller.stop()
        XCTAssertFalse(manager.deviceMotionRunning)
    }

    // MARK: - Replay machinery

    private func replay(_ name: String, ulps: UInt32 = 0, file: StaticString = #filePath, line: UInt = #line) {
        guard let script = SensorGolden.scripts()[name] else {
            XCTFail("no golden script \(name)", file: file, line: line)
            return
        }
        let start: Int64 = 5_000_000_000_000
        AFakeClock.install(nanos: start, wallMillis: 0)   // the harness clock: System.currentTimeMillis() = t
        defer { AFakeClock.uninstall() }
        let recorder = SensorGoldenRecorder()
        let controller = TripleShotSensorController(context: nil, listener: recorder)
        let rotationSensor = ASensor(type: ASensor.TYPE_GAME_ROTATION_VECTOR)
        let gyroSensor = ASensor(type: ASensor.TYPE_GYROSCOPE)
        var expected: [String] = []
        for raw in script.split(separator: "\n") {
            var text = String(raw)
            if let comment = text.range(of: " #") { text = String(text[..<comment.lowerBound]) }
            text = text.trimmingCharacters(in: .whitespaces)
            if text.isEmpty || text.hasPrefix("--") { continue }
            if text.hasPrefix("expected-skill ") {
                // Kotlin BasketballTouchShot.skill(.10f, .70f), which StoreReadyTest compares the release with.
                let s = BasketballTouchShot.skill(aim: 0.10, pull: 0.70)
                XCTAssertEqual("expected-skill " + [s.aimError, s.powerError, s.arcError, s.rawPeakGyro,
                                                    s.rawReleasePitchDeg].map(sensorHex).joined(separator: " "),
                               text, "\(name): BasketballTouchShot.skill(.10, .70)", file: file, line: line)
                continue
            }
            guard text.hasPrefix("> ") else {
                expected.append(text)
                continue
            }
            let f = text.dropFirst(2).split(separator: " ").map(String.init)
            switch f[0] {
            case "call":
                switch f[1] {
                case "start": controller.start()
                case "stop": controller.stop()
                case "prepareForAnswer": controller.prepareForAnswer()
                case "prepareForShot": controller.prepareForShot()
                case "cancelShot": controller.cancelShot()
                case "prepareForMovement": controller.prepareForMovement()
                case "calibrate": controller.calibrate()
                default: XCTFail("unknown call \(f[1])", file: file, line: line)
                }
            case "rot":
                controller.handleRotation(rollDeg: sensorFloat(f[1]), pitchDeg: sensorFloat(f[2]))
            case "quat":
                controller.onSensorChanged(ASensorEvent(rotationSensor, ASensorManager.SENSOR_STATUS_ACCURACY_HIGH, 0,
                                                        [sensorFloat(f[1]), sensorFloat(f[2]), sensorFloat(f[3]), sensorFloat(f[4])]))
            case "gyro":
                AFakeClock.nanos = start + Int64(f[2])! * 1_000_000
                controller.onSensorChanged(ASensorEvent(gyroSensor, ASensorManager.SENSOR_STATUS_ACCURACY_HIGH, 0,
                                                        [sensorFloat(f[1]), 0, 0]))
            case "touch":
                let action = Int(f[1])!
                let e = AMotionEvent.obtain(0, Int64(f[4])!, action, sensorFloat(f[2]), sensorFloat(f[3]), 0)
                let consumed = controller.handleTouchEvent(event: e, viewWidth: Int(f[5])!, viewHeight: Int(f[6])!)
                recorder.lines.append("touch \(action) -> \(consumed)")
                e.recycle()
            default:
                XCTFail("unknown input \(text)", file: file, line: line)
            }
        }
        controller.stop()   // unregister (start() may have registered real sensors on a device)
        recorder.lines.removeLast(2)   // stop(): move 0 0, phase WAITING_FOR_ANSWER (not part of the script)
        // The JVM run had no sensors; on a device start() reports the real hardware.
        let manager = ASensorManager.shared
        let hasRotation = (manager.getDefaultSensor(ASensor.TYPE_GAME_ROTATION_VECTOR)
            ?? manager.getDefaultSensor(ASensor.TYPE_ROTATION_VECTOR)) != nil
        let hasGyro = manager.getDefaultSensor(ASensor.TYPE_GYROSCOPE) != nil
        expected = expected.map { $0.hasPrefix("avail ") ? "avail \(hasRotation) \(hasGyro)" : $0 }

        XCTAssertEqual(recorder.lines.count, expected.count, "\(name): callback count", file: file, line: line)
        for (index, pair) in zip(recorder.lines, expected).enumerated() where !sensorLineMatches(pair.0, pair.1, ulps) {
            XCTFail("\(name) line \(index + 1): got '\(pair.0)', expected '\(pair.1)'", file: file, line: line)
            break
        }
    }

    private static func velocityCases() -> [(String, [(action: Int, t: Int64, x: Float, y: Float)])] {
        let D = AMotionEvent.ACTION_DOWN, M = AMotionEvent.ACTION_MOVE
        let U = AMotionEvent.ACTION_UP, C = AMotionEvent.ACTION_CANCEL
        typealias E = (action: Int, t: Int64, x: Float, y: Float)
        var cases: [(String, [E])] = []
        cases.append(("one", [(D, 0, 1, 2)]))
        cases.append(("two", [(D, 0, 0, 0), (M, 10, 3, -7)]))
        cases.append(("three", [(D, 0, 0, 0), (M, 8, 5, 2), (M, 16, 13, 3)]))
        var curve: [E] = []
        for i in 0...12 {
            let action: Int = i == 0 ? D : M
            let t: Int64 = Int64(i) * 8
            let square: Float = Float(i * i)
            let x: Float = square * 0.75 + 3 * Float(i)   // Kotlin i * i * 0.75f + 3f * i
            let y: Float = 100 - 7.5 * Float(i)           // Kotlin 100f - 7.5f * i
            curve.append((action, t, x, y))
        }
        cases.append(("curve", curve))
        var long: [E] = []
        for i in 0...30 {
            let action: Int = i == 0 ? D : M
            let t: Int64 = Int64(i) * 4
            let x: Float = Float(i) * 11                  // Kotlin i * 11f
            let y: Float = Float(i * i) * 0.5             // Kotlin i * i * 0.5f
            long.append((action, t, x, y))
        }
        cases.append(("long", long))
        cases.append(("gap", [(D, 0, 0, 0), (M, 10, 50, 50), (M, 51, 60, 40), (M, 60, 70, 30)]))
        cases.append(("gap40", [(D, 0, 0, 0), (M, 40, 50, 50), (M, 50, 60, 40)]))
        cases.append(("horizon", [(D, 0, 0, 0), (M, 30, 10, 10), (M, 60, 20, 25), (M, 90, 30, 45), (M, 120, 40, 70),
                                  (M, 131, 41, 80)]))
        cases.append(("upLate", [(D, 0, 0, 0), (M, 10, 10, 10), (M, 20, 20, 30), (U, 61, 20, 30)]))
        cases.append(("upOnTime", [(D, 0, 0, 0), (M, 10, 10, 10), (M, 20, 20, 30), (U, 60, 20, 30)]))
        cases.append(("cancel", [(D, 0, 0, 0), (M, 10, 10, 10), (M, 20, 20, 30), (C, 25, 20, 30)]))
        cases.append(("sameTime", [(D, 0, 0, 0), (M, 10, 10, 10), (M, 10, 30, 10), (M, 20, 40, 20)]))
        return cases
    }
}

// MARK: - Helpers

private func sensorHex(_ f: Float) -> String {
    return String(format: "%08x", f.bitPattern)
}

private func sensorFloat(_ hexBits: String) -> Float {
    return Float(bitPattern: UInt32(hexBits, radix: 16)!)
}

private func sensorNormalized(_ q: CMQuaternion) -> CMQuaternion {
    let n = (q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w).squareRoot()
    return CMQuaternion(x: q.x / n, y: q.y / n, z: q.z / n, w: q.w / n)
}

/// Distance in ulps between two Float bit patterns (+0 and -0 are 0 apart).
private func sensorUlpDistance(_ a: UInt32, _ b: UInt32) -> Int64 {
    func ordered(_ v: UInt32) -> Int64 {
        let magnitude = Int64(v & 0x7FFF_FFFF)
        return (v & 0x8000_0000) != 0 ? -magnitude : magnitude
    }
    return abs(ordered(a) - ordered(b))
}

private func sensorFloatsMatch(_ got: [String], _ expected: [String], ulps: UInt32) -> Bool {
    guard got.count == expected.count else { return false }
    for (g, e) in zip(got, expected) where g != e {
        guard let gb = UInt32(g, radix: 16), let eb = UInt32(e, radix: 16), sensorUlpDistance(gb, eb) <= Int64(ulps) else {
            return false
        }
    }
    return true
}

/// Exact text match, or (with ulps > 0) the same tokens where 8-digit hex tokens may differ by `ulps`.
private func sensorLineMatches(_ got: String, _ expected: String, _ ulps: UInt32) -> Bool {
    if got == expected { return true }
    if ulps == 0 { return false }
    let g = got.split(separator: " ").map(String.init)
    let e = expected.split(separator: " ").map(String.init)
    guard g.count == e.count else { return false }
    for (a, b) in zip(g, e) where a != b {
        guard a.count == 8, b.count == 8, sensorFloatsMatch([a], [b], ulps: ulps) else { return false }
    }
    return true
}

/// Formats every listener callback exactly like the JVM harness (kt/Golden.kt, class Recorder).
private final class SensorGoldenRecorder: TripleShotSensorController.Listener {
    var lines: [String] = []
    var shots: [(skill: ShotSkill, pullBack01: Float)] = []

    func onAimChanged(normalizedAim: Float) {
        lines.append("aim \(sensorHex(normalizedAim))")
    }

    func onPullBackChanged(normalizedPullBack: Float, armed: Bool) {
        lines.append("pull \(sensorHex(normalizedPullBack)) \(armed)")
    }

    func onShotPhaseChanged(phase: TripleShotSensorController.ShotPhase) {
        lines.append("phase \(phase.rawValue)")
    }

    func onShotGesture(skill: ShotSkill, pullBack01: Float) {
        shots.append((skill, pullBack01))
        lines.append("shot \(sensorHex(skill.aimError)) \(sensorHex(skill.powerError)) \(sensorHex(skill.arcError)) "
            + "\(sensorHex(skill.rawPeakGyro)) \(sensorHex(skill.rawReleasePitchDeg)) \(sensorHex(pullBack01))")
    }

    func onSensorAvailability(hasRotation: Bool, hasGyro: Bool) {
        lines.append("avail \(hasRotation) \(hasGyro)")
    }

    func onMovementChanged(horizontal: Float, vertical: Float) {
        lines.append("move \(sensorHex(horizontal)) \(sensorHex(vertical))")
    }
}

private final class SensorEventRecorder: ASensorEventListener {
    var log: [String] = []
    var events: [(type: Int, values: [Float], timestamp: Int64, object: ObjectIdentifier)] = []
    var onEvent: ((ASensorEvent) -> Void)?

    func onSensorChanged(_ event: ASensorEvent) {
        log.append("changed \(event.sensor.type)")
        events.append((event.sensor.type, event.values, event.timestamp, ObjectIdentifier(event)))
        onEvent?(event)
    }

    func onAccuracyChanged(_ sensor: ASensor?, _ accuracy: Int) {
        log.append("accuracy \(sensor?.type ?? -1) \(accuracy)")
    }
}

// MARK: - Golden data (generated on the JVM; do not edit by hand)

private enum SensorGolden {
    /// Scenario name → script (the "== NAME" blocks of `controller`, without the VT block).
    static func scripts() -> [String: String] {
        var result: [String: String] = [:]
        var name: String?
        var body: [Substring] = []
        func flush() {
            if let n = name { result[n] = body.joined(separator: "\n") }
        }
        for line in controller.split(separator: "\n") {
            if line.hasPrefix("== ") {
                flush()
                name = String(line.dropFirst(3))
                body = []
            } else {
                body.append(line)
            }
        }
        flush()
        return result
    }

    /// VelocityTracker case name → "vx vy vxClamped500 vyClamped500" (bit patterns).
    static func velocityRows() -> [String: String] {
        var rows: [String: String] = [:]
        for line in (scripts()["VT"] ?? "").split(separator: "\n") {
            var text = String(line)
            if let comment = text.range(of: " #") { text = String(text[..<comment.lowerBound]) }
            let f = text.split(separator: " ").map(String.init)
            guard f.count == 5 else { continue }
            rows[f[0]] = f[1...4].joined(separator: " ")
        }
        return rows
    }

    static func frameRows(prefix: String) -> [String] {
        return frame.split(separator: "\n").map(String.init).filter { $0.hasPrefix(prefix + " ") }.map { row in
            if let comment = row.range(of: " #") { return String(row[..<comment.lowerBound]) }
            return row
        }
    }

    static let controller = """
== T1T2
> call prepareForShot
move 00000000 00000000 # 0.0 0.0
phase AIMING
aim 00000000 # 0.0
pull 00000000 false # 0.0
> touch 0 43c80000 43960000 0 1000 1000 # 400.0 300.0
touch 0 -> true
> touch 2 43dd0000 43d88000 400 1000 1000 # 442.0 433.0
aim 3dcccccd # 0.1
phase ARMED
pull 3f333333 true # 0.7
touch 2 -> true
> touch 2 43dd0000 43d88000 800 1000 1000 # 442.0 433.0
aim 3dcccccd # 0.1
pull 3f333333 true # 0.7
touch 2 -> true
> touch 1 43dd0000 43d88000 1100 1000 1000 # 442.0 433.0
phase RELEASING
shot 3dcccccd 00000000 be124925 40433333 41600000 3f333333 # 0.1 0.0 -0.14285715 3.05 14.0 0.7
phase WAITING_FOR_ANSWER
touch 1 -> true
-- second gesture
> call prepareForShot
move 00000000 00000000 # 0.0 0.0
phase AIMING
aim 00000000 # 0.0
pull 00000000 false # 0.0
> touch 0 43c80000 43960000 1400 1000 1000 # 400.0 300.0
touch 0 -> true
> touch 2 43dd0000 43d88000 1800 1000 1000 # 442.0 433.0
aim 3dcccccd # 0.1
phase ARMED
pull 3f333333 true # 0.7
touch 2 -> true
> touch 3 43dd0000 43d88000 1900 1000 1000 # 442.0 433.0
phase AIMING
pull 00000000 false # 0.0
touch 3 -> true
-- stop
> call stop
move 00000000 00000000 # 0.0 0.0
phase WAITING_FOR_ANSWER
expected-skill 3dcccccd 00000000 be124925 40433333 41600000
== T3
> call prepareForShot
move 00000000 00000000 # 0.0 0.0
phase AIMING
aim 00000000 # 0.0
pull 00000000 false # 0.0
> touch 0 43fa0000 43fa0000 0 1000 1000 # 500.0 500.0
touch 0 -> true
> touch 2 43fa0000 44032ccd 16 1000 1000 # 500.0 524.7
aim 00000000 # 0.0
phase ARMED
pull 3e051ebd true # 0.13000007
touch 2 -> true
> touch 1 43fa0000 44032ccd 116 1000 1000 # 500.0 524.7
phase RELEASING
shot 00000000 bf17b425 bfd9999a 40100000 4026666c 3e051ebd # 0.0 -0.59259254 -1.7 2.25 2.6000013 0.13000007
phase WAITING_FOR_ANSWER
touch 1 -> true
== T4
> call prepareForShot
move 00000000 00000000 # 0.0 0.0
phase AIMING
aim 00000000 # 0.0
pull 00000000 false # 0.0
> touch 0 43fa0000 43c80000 0 1000 2000 # 500.0 400.0
touch 0 -> true
> touch 2 43fa0000 44300000 300 1000 2000 # 500.0 704.0
aim 00000000 # 0.0
phase ARMED
pull 3f4ccccd true # 0.8
touch 2 -> true
> touch 2 43fa0000 442a0000 316 1000 2000 # 500.0 680.0
aim 00000000 # 0.0
pull 3f3ca1af true # 0.7368421
touch 2 -> true
> touch 2 43fa0000 44228000 332 1000 2000 # 500.0 650.0
aim 00000000 # 0.0
pull 3f286bca true # 0.65789473
touch 2 -> true
> touch 2 43fa0000 4419c000 348 1000 2000 # 500.0 615.0
aim 00000000 # 0.0
pull 3f10d794 true # 0.56578946
touch 2 -> true
> touch 1 43fa0000 4419c000 352 1000 2000 # 500.0 615.0
phase RELEASING
shot 00000000 3ed5e83b 3e124925 40674bfd 41800000 3f4ccccd # 0.0 0.4177874 0.14285715 3.614013 16.0 0.8
phase WAITING_FOR_ANSWER
touch 1 -> true
== T5
> call prepareForShot
move 00000000 00000000 # 0.0 0.0
phase AIMING
aim 00000000 # 0.0
pull 00000000 false # 0.0
> touch 0 43fa0000 43960000 0 1000 1000 # 500.0 300.0
touch 0 -> true
> touch 2 43fa0000 43e10000 10 1000 1000 # 500.0 450.0
aim 00000000 # 0.0
phase ARMED
pull 3f4a1af3 true # 0.7894737
touch 2 -> true
> touch 2 43fa0000 43c80000 20 1000 1000 # 500.0 400.0
aim 00000000 # 0.0
pull 3f06bca2 true # 0.5263158
touch 2 -> true
> touch 2 43fa0000 43960000 30 1000 1000 # 500.0 300.0
aim 00000000 # 0.0
pull 00000000 true # 0.0
touch 2 -> true
> touch 2 43fa0000 43160000 40 1000 1000 # 500.0 150.0
aim 00000000 # 0.0
pull 00000000 true # 0.0
touch 2 -> true
> touch 1 43fa0000 43160000 45 1000 1000 # 500.0 150.0
phase RELEASING
shot 00000000 3f14121f 3de6fa49 40752c84 417ca1b0 3f4a1af3 # 0.0 0.5784015 0.11278207 3.830842 15.7894745 0.7894737
phase WAITING_FOR_ANSWER
touch 1 -> true
-- again, lift after a pause
> call prepareForShot
move 00000000 00000000 # 0.0 0.0
phase AIMING
aim 00000000 # 0.0
pull 00000000 false # 0.0
> touch 0 43fa0000 43960000 100 1000 1000 # 500.0 300.0
touch 0 -> true
> touch 2 43fa0000 43e10000 110 1000 1000 # 500.0 450.0
aim 00000000 # 0.0
phase ARMED
pull 3f4a1af3 true # 0.7894737
touch 2 -> true
> touch 2 43fa0000 43c80000 120 1000 1000 # 500.0 400.0
aim 00000000 # 0.0
pull 3f06bca2 true # 0.5263158
touch 2 -> true
> touch 2 43fa0000 43960000 130 1000 1000 # 500.0 300.0
aim 00000000 # 0.0
pull 00000000 true # 0.0
touch 2 -> true
> touch 1 43fa0000 43960000 171 1000 1000 # 500.0 300.0
phase RELEASING
shot 00000000 bf17b425 bfd9999a 40100000 40000000 3dcccccd # 0.0 -0.59259254 -1.7 2.25 2.0 0.1
phase WAITING_FOR_ANSWER
touch 1 -> true
== T6
> call prepareForShot
move 00000000 00000000 # 0.0 0.0
phase AIMING
aim 00000000 # 0.0
pull 00000000 false # 0.0
> touch 0 43fa0000 43fa0000 0 1000 1000 # 500.0 500.0
touch 0 -> true
> touch 2 43fa0000 442f0000 1000 1000 1000 # 500.0 700.0
aim 00000000 # 0.0
phase ARMED
pull 3f86bca2 true # 1.0526316
touch 2 -> true
> touch 2 43fa0000 44160000 1016 1000 1000 # 500.0 600.0
aim 00000000 # 0.0
pull 3f06bca2 true # 0.5263158
touch 2 -> true
> touch 1 43fa0000 44160000 1020 1000 1000 # 500.0 600.0
phase RELEASING
shot 00000000 3f630030 3f5d5a77 4087e808 41a86bca 3f86bca2 # 0.0 0.8867216 0.86466163 4.247074 21.052631 1.0526316
phase WAITING_FOR_ANSWER
touch 1 -> true
== S1S4
> call prepareForShot
move 00000000 00000000 # 0.0 0.0
phase AIMING
aim 00000000 # 0.0
pull 00000000 false # 0.0
> rot 40000000 c2200000 # 2.0 -40.0
aim 00000000 # 0.0
> rot 40000000 c22c0000 # 2.0 -43.0
aim 00000000 # 0.0
pull 3e19999a false # 0.15
phase ARMED
pull 3e19999a true # 0.15
> rot 40000000 c2480000 # 2.0 -50.0
aim 00000000 # 0.0
pull 3f000000 true # 0.5
> rot 40000000 c25c0000 # 2.0 -55.0
aim 00000000 # 0.0
pull 3f400000 true # 0.75
> gyro 3e99999a 10000 # 0.3
> rot 40000000 c2500000 # 2.0 -52.0
aim 00000000 # 0.0
pull 3f19999a true # 0.6
> gyro 40000000 10020 # 2.0
phase RELEASING
> rot 40000000 c2380000 # 2.0 -46.0
aim 00000000 # 0.0
pull 3e99999a true # 0.3
> gyro 4059999a 10040 # 3.4
> rot 40000000 c2240000 # 2.0 -41.0
aim 00000000 # 0.0
pull 3d4ccccd true # 0.05
> gyro 40200000 10060 # 2.5
> rot 40200000 c21c0000 # 2.5 -39.0
aim 3d321643 # 0.04347826
pull 00000000 true # 0.0
> gyro 3f000000 10100 # 0.5
shot 3d321643 3e84bda5 00000000 4059999a 41700000 3f400000 # 0.04347826 0.25925937 0.0 3.4 15.0 0.75
phase WAITING_FOR_ANSWER
-- S4 cooldown
> call prepareForShot
move 00000000 00000000 # 0.0 0.0
phase AIMING
aim 00000000 # 0.0
pull 00000000 false # 0.0
> rot 40000000 c2200000 # 2.0 -40.0
aim 00000000 # 0.0
> rot 40000000 c22c0000 # 2.0 -43.0
aim 00000000 # 0.0
pull 3e19999a false # 0.15
phase ARMED
pull 3e19999a true # 0.15
> rot 40000000 c25c0000 # 2.0 -55.0
aim 00000000 # 0.0
pull 3f400000 true # 0.75
> rot 40000000 c2480000 # 2.0 -50.0
aim 00000000 # 0.0
pull 3f000000 true # 0.5
> gyro 40400000 10500 # 3.0
> rot 40000000 c2240000 # 2.0 -41.0
aim 00000000 # 0.0
pull 3d4ccccd true # 0.05
phase AIMING
pull 00000000 false # 0.0
== S2
> call prepareForShot
move 00000000 00000000 # 0.0 0.0
phase AIMING
aim 00000000 # 0.0
pull 00000000 false # 0.0
> rot 40000000 c2200000 # 2.0 -40.0
aim 00000000 # 0.0
> rot 40000000 c22c0000 # 2.0 -43.0
aim 00000000 # 0.0
pull 3e19999a false # 0.15
phase ARMED
pull 3e19999a true # 0.15
> rot 40000000 c2240000 # 2.0 -41.0
aim 00000000 # 0.0
pull 3d4ccccd true # 0.05
phase AIMING
pull 00000000 false # 0.0
== S3
> call prepareForShot
move 00000000 00000000 # 0.0 0.0
phase AIMING
aim 00000000 # 0.0
pull 00000000 false # 0.0
> rot 00000000 c2200000 # 0.0 -40.0
aim 00000000 # 0.0
> rot 00000000 c2100000 # 0.0 -36.0
aim 00000000 # 0.0
pull 3e4ccccd false # 0.2
phase ARMED
pull 3e4ccccd true # 0.2
> rot 00000000 c1c80000 # 0.0 -25.0
aim 00000000 # 0.0
pull 3f400000 true # 0.75
> rot 00000000 c1e00000 # 0.0 -28.0
aim 00000000 # 0.0
pull 3f19999a true # 0.6
> gyro 40000000 5000 # 2.0
phase RELEASING
> rot 00000000 c1f00000 # 0.0 -30.0
aim 00000000 # 0.0
pull 3f000000 true # 0.5
> gyro 3f800000 5100 # 1.0
> gyro 3f800000 5200 # 1.0
> gyro 3f800000 5300 # 1.0
> gyro 3f800000 5400 # 1.0
> gyro 3f800000 5500 # 1.0
> gyro 3f800000 5600 # 1.0
> gyro 3f800000 5649 # 1.0
> gyro 3f800000 5650 # 1.0
shot 00000000 bf471c71 00000000 40000000 41700000 3f400000 # 0.0 -0.77777773 0.0 2.0 15.0 0.75
phase WAITING_FOR_ANSWER
== S5
> call prepareForShot
move 00000000 00000000 # 0.0 0.0
phase AIMING
aim 00000000 # 0.0
pull 00000000 false # 0.0
> rot c0400000 c1f00000 # -3.0 -30.0
aim 00000000 # 0.0
> rot c0400000 c2300000 # -3.0 -44.0
aim 00000000 # 0.0
pull 3f333333 false # 0.7
phase ARMED
pull 3f333333 true # 0.7
> rot c0400000 c2280000 # -3.0 -42.0
aim 00000000 # 0.0
pull 3f19999a true # 0.6
> gyro bfcccccd 20000 # -1.6
phase RELEASING
> rot c0800000 c2080000 # -4.0 -34.0
aim bdb21643 # -0.08695652
pull 3e4ccccd true # 0.2
> gyro 3f666666 20050 # 0.9
> rot c0900000 c1f7ffff # -4.5 -30.999998
aim be0590b2 # -0.13043478
pull 3d4cccb3 true # 0.049999904
> gyro 3f19999a 20069 # 0.6
> gyro 3f19999a 20070 # 0.6
shot be0590b2 bf897b42 be124925 3fcccccd 41600000 3f333333 # -0.13043478 -1.074074 -0.14285715 1.6 14.0 0.7
phase WAITING_FOR_ANSWER
== M1
> call prepareForMovement
phase WAITING_FOR_ANSWER
aim 00000000 # 0.0
pull 00000000 false # 0.0
move 00000000 00000000 # 0.0 0.0
> rot 41200000 c2200000 # 10.0 -40.0
move 00000000 00000000 # 0.0 0.0
> rot 41840000 c2200000 # 16.5 -40.0
move 3ed6535a 00000000 # 0.41860467 0.0
> rot 41200000 c2540000 # 10.0 -53.0
move 00000000 bf800000 # 0.0 -1.0
> rot 41380000 c2260000 # 11.5 -41.5
move 00000000 00000000 # 0.0 0.0
> rot 41f00000 c2200000 # 30.0 -40.0
move 3f800000 00000000 # 1.0 0.0
> rot c0400000 c1e00000 # -3.0 -28.0
move bf800000 3f691a1b # -1.0 0.9105546
> gyro 40a00000 100 # 5.0
-- touch refused in movement mode
> touch 0 3f800000 3f800000 0 1000 1000 # 1.0 1.0
touch 0 -> false
== N1
> call prepareForShot
move 00000000 00000000 # 0.0 0.0
phase AIMING
aim 00000000 # 0.0
pull 00000000 false # 0.0
> rot 432a0000 c2200000 # 170.0 -40.0
aim 00000000 # 0.0
> rot c32f0000 c2200000 # -175.0 -40.0
aim 3fa66666 # 1.3
pull 00000000 false # 0.0
> rot c32a0000 432f0000 # -170.0 175.0
aim 3fa66666 # 1.3
pull 3f99999a false # 1.2
phase ARMED
pull 3f99999a true # 1.2
== ORDER
-- start, no sensors
> call start
avail false false
-- prepareForAnswer
> call prepareForAnswer
move 00000000 00000000 # 0.0 0.0
phase WAITING_FOR_ANSWER
aim 00000000 # 0.0
pull 00000000 false # 0.0
-- cancelShot
> call cancelShot
move 00000000 00000000 # 0.0 0.0
phase WAITING_FOR_ANSWER
aim 00000000 # 0.0
pull 00000000 false # 0.0
-- prepareForShot
> call prepareForShot
move 00000000 00000000 # 0.0 0.0
phase AIMING
aim 00000000 # 0.0
pull 00000000 false # 0.0
-- prepareForMovement
> call prepareForMovement
phase WAITING_FOR_ANSWER
aim 00000000 # 0.0
pull 00000000 false # 0.0
move 00000000 00000000 # 0.0 0.0
-- calibrate (movement mode)
> call calibrate
phase WAITING_FOR_ANSWER
aim 00000000 # 0.0
pull 00000000 false # 0.0
-- prepareForShot + calibrate
> call prepareForShot
move 00000000 00000000 # 0.0 0.0
phase AIMING
aim 00000000 # 0.0
pull 00000000 false # 0.0
> call calibrate
phase AIMING
aim 00000000 # 0.0
pull 00000000 false # 0.0
-- stop
> call stop
move 00000000 00000000 # 0.0 0.0
phase WAITING_FOR_ANSWER
-- after stop: touch refused, tilt still aims, gyro inert
> touch 0 41200000 41200000 0 1000 1000 # 10.0 10.0
touch 0 -> false
> rot 00000000 c2200000 # 0.0 -40.0
aim 00000000 # 0.0
> rot 40b80000 c2700000 # 5.75 -60.0
aim 3f000000 # 0.5
> gyro 40800000 1000 # 4.0
== FREEZE
> call prepareForShot
move 00000000 00000000 # 0.0 0.0
phase AIMING
aim 00000000 # 0.0
pull 00000000 false # 0.0
> rot 00000000 c2200000 # 0.0 -40.0
aim 00000000 # 0.0
> rot 40933333 c2200000 # 4.6 -40.0
aim 3ecccccd # 0.4
pull 00000000 false # 0.0
> touch 0 42c80000 42c80000 0 1000 1000 # 100.0 100.0
touch 0 -> true
> rot 41133333 c2340000 # 9.2 -45.0
> touch 2 43380000 42dc0000 16 1000 1000 # 184.0 110.0
aim 3f19999a # 0.6
pull 3d579436 false # 0.05263158
touch 2 -> true
> touch 1 43380000 42dc0000 32 1000 1000 # 184.0 110.0
pull 00000000 false # 0.0
touch 1 -> true
> rot 41133333 c2340000 # 9.2 -45.0
aim 3f800000 # 1.0
pull 3e800000 false # 0.25
phase ARMED
pull 3e800000 true # 0.25
-- finger over sensor ARMED
> rot 41133333 c2440000 # 9.2 -49.0
aim 3f800000 # 1.0
pull 3ee66666 true # 0.45
> touch 0 43960000 43960000 100 1000 1000 # 300.0 300.0
touch 0 -> true
> touch 2 43960000 43988000 116 1000 1000 # 300.0 305.0
aim 3f800000 # 1.0
pull 3cd79436 true # 0.02631579
touch 2 -> true
> touch 1 43960000 43988000 132 1000 1000 # 300.0 305.0
phase AIMING
pull 00000000 false # 0.0
touch 1 -> true
> rot 41133333 c2440000 # 9.2 -49.0
aim 3f800000 # 1.0
pull 3ee66666 false # 0.45
phase ARMED
pull 3ee66666 true # 0.45
-- other action while active / inactive
> touch 0 43960000 43960000 200 1000 1000 # 300.0 300.0
touch 0 -> true
> touch 5 43960000 43960000 210 1000 1000 # 300.0 300.0
touch 5 -> true
> touch 3 00000000 00000000 220 1000 1000 # 0.0 0.0
phase AIMING
pull 00000000 false # 0.0
touch 3 -> true
> touch 5 43960000 43960000 230 1000 1000 # 300.0 300.0
touch 5 -> false
> touch 2 3f800000 3f800000 240 1000 1000 # 1.0 1.0
touch 2 -> false
> touch 1 3f800000 3f800000 250 1000 1000 # 1.0 1.0
touch 1 -> false
> touch 3 00000000 00000000 260 1000 1000 # 0.0 0.0
pull 00000000 false # 0.0
touch 3 -> true
-- zero-size view
> touch 0 3f800000 3f800000 300 0 1000 # 1.0 1.0
touch 0 -> false
> touch 0 3f800000 3f800000 310 1000 -1 # 1.0 1.0
touch 0 -> false
-- touch aim accumulates and clamps
> touch 0 00000000 00000000 400 1000 1000 # 0.0 0.0
touch 0 -> true
> touch 2 43960000 00000000 416 1000 1000 # 300.0 0.0
aim 3fa66666 # 1.3
pull 00000000 false # 0.0
touch 2 -> true
> touch 1 43960000 00000000 432 1000 1000 # 300.0 0.0
pull 00000000 false # 0.0
touch 1 -> true
> touch 0 00000000 00000000 500 1000 1000 # 0.0 0.0
touch 0 -> true
> touch 2 43960000 00000000 516 1000 1000 # 300.0 0.0
aim 3fa66666 # 1.3
pull 00000000 false # 0.0
touch 2 -> true
> touch 3 43960000 00000000 532 1000 1000 # 300.0 0.0
pull 00000000 false # 0.0
touch 3 -> true
> touch 0 00000000 00000000 600 1000 1000 # 0.0 0.0
touch 0 -> true
> touch 2 c4fa0000 c2480000 616 1000 1000 # -2000.0 -50.0
aim befffffe # -0.49999994
pull 00000000 false # 0.0
touch 2 -> true
> touch 1 c4fa0000 c2480000 632 1000 1000 # -2000.0 -50.0
pull 00000000 false # 0.0
touch 1 -> true
== QUAT
> call prepareForShot
move 00000000 00000000 # 0.0 0.0
phase AIMING
aim 00000000 # 0.0
pull 00000000 false # 0.0
> quat 3ec3ef15 00000000 00000000 3f6c835e
aim 00000000 # 0.0
> quat 3ec13b46 3d81568e bcd64a64 3f6c6d8b
aim 3f730604 # 0.94931054
pull 3d5ad033 false # 0.05342121
> quat 3edc652a bd917f92 3cf11206 3f663391
aim bf9a8e86 # -1.2074745
pull 3e890220 false # 0.26759434
phase ARMED
pull 3e890220 true # 0.26759434
> quat 3e8483ee 00000000 00000000 3f7746ea
aim 00000000 # 0.0
pull 00000000 true # 0.0
phase AIMING
pull 00000000 false # 0.0
> quat 00000000 00000000 00000000 3f800000
aim 00000000 # 0.0
pull 3f99999a false # 1.2
phase ARMED
pull 3f99999a true # 1.2
> quat 3f000000 3f000000 3f000000 3f000000
aim 00000000 # 0.0
pull 00000000 true # 0.0
phase AIMING
pull 00000000 false # 0.0
== VT
one 00000000 00000000 00000000 00000000 # 0.0 0.0 0.0 0.0
two 43960000 c42f0001 43960000 c3fa0000 # 300.0 -700.00006 300.0 -500.0
three 44947006 4279ffa1 43fa0000 4279ffa1 # 1187.5007 62.499638 500.0 62.499638
curve 45240f68 c46a5f4a 43fa0000 c3fa0000 # 2624.963 -937.4889 500.0 -500.0
long 452bdfe8 45ea6072 43fa0000 43fa0000 # 2749.9941 7500.0557 500.0 500.0
gap 448ae383 c48ae392 43fa0000 c3fa0000 # 1111.1097 -1111.1116 500.0 -500.0
gap40 446d7f26 c4b53fe6 43fa0000 c3fa0000 # 949.9867 -1449.9968 500.0 -500.0
horizon 435cd6db 447004ec 435cd6db 43fa0000 # 220.83928 960.0769 220.83928 500.0
upLate 00000000 00000000 00000000 00000000 # 0.0 0.0 0.0 0.0
upOnTime 447a0047 451c4032 43fa0000 43fa0000 # 1000.00433 2500.0122 500.0 500.0
cancel 00000000 00000000 00000000 00000000 # 0.0 0.0 0.0 0.0
sameTime bbae9fcb 447a0047 bbae9fcb 43fa0000 # -0.0053291074 1000.00433 -0.0053291074 500.0
"""

    static let frame = """
ROT 00000000 00000000 00000000 3f800000 | 3f800000 00000000 00000000 00000000 3f800000 00000000 00000000 00000000 3f800000 | 00000000 80000000 80000000 | 3f800000 00000000 00000000 00000000 00000000 3f800000 00000000 00000000 00000000 00000000 3f800000 00000000 00000000 00000000 00000000 3f800000 | 00000000 80000000 80000000
ROT 3ec3ef15 00000000 00000000 3f6c835e | 3f800000 00000000 00000000 00000000 3f3504f4 bf3504f3 00000000 3f3504f3 3f3504f4 | 00000000 bf490fda 80000000 | 3f800000 00000000 00000000 00000000 00000000 3f3504f4 bf3504f3 00000000 00000000 3f3504f3 3f3504f4 00000000 00000000 00000000 00000000 3f800000 | 00000000 bf490fda 80000000
ROT 3f3504f3 00000000 00000000 3f3504f3 | 3f800000 00000000 00000000 00000000 33800000 bf7fffff 00000000 3f7fffff 33800000 | 00000000 bfc9048a 80000000 | 3f800000 00000000 00000000 00000000 00000000 33800000 bf7fffff 00000000 00000000 3f7fffff 33800000 00000000 00000000 00000000 00000000 3f800000 | 00000000 bfc9048a 80000000
ROT 00000000 3e31d0d4 00000000 3f7c1c5c | 3f708fb2 00000000 3eaf1d43 00000000 3f800000 00000000 beaf1d43 00000000 3f708fb2 | 00000000 80000000 3eb2b8c2 | 3f708fb2 00000000 3eaf1d43 00000000 00000000 3f800000 00000000 00000000 beaf1d43 00000000 3f708fb2 00000000 00000000 00000000 00000000 3f800000 | 00000000 80000000 3eb2b8c2
ROT 3ec13b46 3d81568e bcd64a64 3f6c6d8b | 3f7d9b8d 3dc49456 3dc67659 ba29f7c0 3f36b91a bf334ddc be0bab19 3f319ccc 3f350807 | 3e08e2a7 bf4449c4 3e431c9d | 3f7d9b8d 3dc49456 3dc67659 00000000 ba29f7c0 3f36b91a bf334ddc 00000000 be0bab19 3f319ccc 3f350807 00000000 00000000 00000000 00000000 3f800000 | 3e08e2a7 bf4449c4 3e431c9d
ROT 3f000000 3f000000 3f000000 3f000000 | 00000000 00000000 3f800000 3f800000 00000000 00000000 00000000 3f800000 00000000 | 00000000 bfc90fdb 80000000 | 00000000 00000000 3f800000 00000000 3f800000 00000000 00000000 00000000 00000000 3f800000 00000000 00000000 00000000 00000000 00000000 3f800000 | 00000000 bfc90fdb 80000000
ROT bdcccccd 3e4ccccd 3e99999a | 3f3d70a4 bf18aecb 3e9f3426 3f0433e9 3f4ccccd 3e9c66e0 bedca4ca bd861660 3f666667 | bf24003d 3d862ef2 3ee4a460 | 3f3d70a4 bf18aecb 3e9f3426 00000000 3f0433e9 3f4ccccd 3e9c66e0 00000000 bedca4ca bd861660 3f666667 00000000 00000000 00000000 00000000 3f800000 | bf24003d 3d862ef2 3ee4a460
ROT 3f19999a 3f333333 3f000000 | bef5c28e 3f570a3e 3f19999a 3f570a3e be6147b0 3f333333 3f19999a 3f333333 bf333333 | 3fe9d96c bf468073 c01bb5b9 | bef5c28e 3f570a3e 3f19999a 00000000 3f570a3e be6147b0 3f333333 00000000 3f19999a 3f333333 bf333333 00000000 00000000 00000000 00000000 3f800000 | 3fe9d96c bf468073 c01bb5b9
ROT 3e800000 becccccd 3dcccccd 3f5fe897 bf800000 | 3f28f5c2 bebff6a3 bf2653ac bccd62a0 3f5ae148 bf046f2d 3f3fed46 3eb6f2d4 3f0e147a | bed396db bebb157e bf6efcba | 3f28f5c2 bebff6a3 bf2653ac 00000000 bccd62a0 3f5ae148 bf046f2d 00000000 3f3fed46 3eb6f2d4 3f0e147a 00000000 00000000 00000000 00000000 3f800000 | bed396db bebb157e bf6efcba
ORI 00000000 00000000 411ce80a -1 # 0.0 0.0 9.80665
ORI 00000000 411ce80a 00000000 0 # 0.0 9.80665 0.0
ORI 411ce80a 00000000 00000000 270 # 9.80665 0.0 0.0
ORI c11ce80a 00000000 00000000 90 # -9.80665 0.0 0.0
ORI 00000000 c11ce80a 00000000 180 # 0.0 -9.80665 0.0
ORI 3f000000 411b3333 3f99999a 357 # 0.5 9.7 1.2
ORI c0ddc28f 40ddc28f 3f000000 45 # -6.93 6.93 0.5
ORI 40ddc28f 40de147b 3e4ccccd 315 # 6.93 6.94 0.2
ORI 40de147b 40ddc28f 3e4ccccd 315 # 6.94 6.93 0.2
ORI 40000000 3f800000 408f0a3d 297 # 2.0 1.0 4.47
ORI 40000000 3f800000 408f5c29 -1 # 2.0 1.0 4.48
ORI c0533333 c101999a 40000000 158 # -3.3 -8.1 2.0
ORI 40e00000 c0e00000 3f800000 225 # 7.0 -7.0 1.0
ORI 00000000 00000000 c11ce80a -1 # 0.0 0.0 -9.80665
ORI 3a83126f 00000000 00000000 270 # 0.001 0.0 0.0
ORI 80000000 40a00000 00000000 0 # -0.0 5.0 0.0
ORI 4045c558 41182b46 00000000 342 # 3.09017 9.510565 0.0
ORI 411a8c52 4025a4ea 00000000 285 # 9.659258 2.5881906 0.0
ORI c11a8c52 c025a4ea 40400000 105 # -9.659258 -2.5881906 3.0
ORI 3db27eb5 3f7f069e 00000000 355 # 0.08715574 0.9961947 0.0
ROUND 3f000000:1 bf000000:0 3fc00000:2 bfc00000:-1 40200000:3 c0200000:-2 3effffff:0 beffffff:0 42320000:45 43068000:135 80000000:0 4333ffff:180 501502f9:2147483647 7fc00000:0
"""
}
