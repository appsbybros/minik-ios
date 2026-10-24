import CoreMotion
import Foundation

// android.hardware sensors (SensorManager, Sensor, SensorEvent, SensorEventListener) and
// android.view.OrientationEventListener, over ONE shared CMMotionManager (DESIGN 4.6, spec 20 §5/§9.3, spec 19 §4.1.3).
//
// Android conventions are kept exactly: the device frame is X to the right edge, Y to the top edge, Z out of the
// screen (natural portrait orientation, never remapped for the display rotation, like Android); units are m/s²,
// rad/s and unit quaternions; event timestamps are nanoseconds in the SystemClock.elapsedRealtimeNanos() domain; events
// are delivered on the main thread (Android: the main Looper when registerListener gets no Handler).
//
// | Android sensor              | iOS source                                                   | values                                    |
// |-----------------------------|--------------------------------------------------------------|-------------------------------------------|
// | TYPE_ACCELEROMETER          | CMAccelerometerData.acceleration (raw, gravity included)     | -a · 9.80665 (flat face up → z ≈ +9.81)   |
// | TYPE_GYROSCOPE              | CMDeviceMotion.rotationRate (bias removed = calibrated gyro) | rad/s, same axes, right-hand rule         |
// | TYPE_GRAVITY                | CMDeviceMotion.gravity                                       | -g · 9.80665                              |
// | TYPE_LINEAR_ACCELERATION    | CMDeviceMotion.userAcceleration                              | -u · 9.80665                              |
// | TYPE_GAME_ROTATION_VECTOR   | CMDeviceMotion attitude, .xArbitraryZVertical (no compass)   | (x, y, z, w) device → reference rotation  |
// | TYPE_ROTATION_VECTOR        | CMDeviceMotion attitude, .xMagneticNorthZVertical            | (x, y, z, w, -1) in Android's ENU frame   |
//
// The rotation vectors are built from CMAttitude.quaternion with the vertical axis pinned to CMDeviceMotion.gravity
// (the documented device-frame gravity vector), so pitch and roll (SensorManager.getOrientation) always follow gravity
// exactly as Android's do (spec 20 §4.3/§9.3).
//
// Rates (SensorManager.getDelay): SENSOR_DELAY_FASTEST 0 µs → 10 ms (CoreMotion's 100 Hz cap), GAME 20 000 µs (50 Hz),
// UI 66 667 µs, NORMAL 200 000 µs, any other value is a period in µs (at least 10 ms). The device-motion stream runs at
// the fastest period requested by any of its sensors; each sensor type is delivered at its own requested rate, as
// Android runs every sensor at the fastest rate its own clients asked for.
//
// A sensor the device lacks (Simulator, "Designed for iPad" on a Mac) is absent: getDefaultSensor returns nil, exactly
// like Android's null sensor, and registering a nil sensor returns false.

// MARK: - Sensor

/// android.hardware.Sensor.
final class ASensor {
    static let TYPE_ACCELEROMETER = 1
    static let TYPE_MAGNETIC_FIELD = 2
    static let TYPE_ORIENTATION = 3
    static let TYPE_GYROSCOPE = 4
    static let TYPE_LIGHT = 5
    static let TYPE_PRESSURE = 6
    static let TYPE_TEMPERATURE = 7
    static let TYPE_PROXIMITY = 8
    static let TYPE_GRAVITY = 9
    static let TYPE_LINEAR_ACCELERATION = 10
    static let TYPE_ROTATION_VECTOR = 11
    static let TYPE_RELATIVE_HUMIDITY = 12
    static let TYPE_AMBIENT_TEMPERATURE = 13
    static let TYPE_MAGNETIC_FIELD_UNCALIBRATED = 14
    static let TYPE_GAME_ROTATION_VECTOR = 15
    static let TYPE_GYROSCOPE_UNCALIBRATED = 16
    static let TYPE_SIGNIFICANT_MOTION = 17
    static let TYPE_STEP_DETECTOR = 18
    static let TYPE_STEP_COUNTER = 19
    static let TYPE_GEOMAGNETIC_ROTATION_VECTOR = 20
    static let TYPE_ALL = -1

    static let STRING_TYPE_ACCELEROMETER = "android.sensor.accelerometer"
    static let STRING_TYPE_GYROSCOPE = "android.sensor.gyroscope"
    static let STRING_TYPE_GRAVITY = "android.sensor.gravity"
    static let STRING_TYPE_LINEAR_ACCELERATION = "android.sensor.linear_acceleration"
    static let STRING_TYPE_ROTATION_VECTOR = "android.sensor.rotation_vector"
    static let STRING_TYPE_GAME_ROTATION_VECTOR = "android.sensor.game_rotation_vector"

    static let REPORTING_MODE_CONTINUOUS = 0
    static let REPORTING_MODE_ON_CHANGE = 1
    static let REPORTING_MODE_ONE_SHOT = 2
    static let REPORTING_MODE_SPECIAL_TRIGGER = 3

    let type: Int
    let name: String
    let vendor: String
    let version: Int
    let maximumRange: Float
    let resolution: Float
    let power: Float
    /// Minimum period in µs (0 would mean "on change"); CoreMotion delivers at most 100 Hz.
    let minDelay: Int
    /// Maximum period in µs.
    let maxDelay: Int
    let stringType: String
    let reportingMode: Int
    let isWakeUpSensor: Bool

    init(type: Int, name: String = "", vendor: String = "Apple", version: Int = 1, maximumRange: Float = 0,
         resolution: Float = 0, power: Float = 0, minDelay: Int = ASensorManager.MIN_SAMPLING_PERIOD_US,
         maxDelay: Int = 1_000_000, stringType: String = "",
         reportingMode: Int = ASensor.REPORTING_MODE_CONTINUOUS, isWakeUpSensor: Bool = false) {
        self.type = type
        self.name = name
        self.vendor = vendor
        self.version = version
        self.maximumRange = maximumRange
        self.resolution = resolution
        self.power = power
        self.minDelay = minDelay
        self.maxDelay = maxDelay
        self.stringType = stringType
        self.reportingMode = reportingMode
        self.isWakeUpSensor = isWakeUpSensor
    }

    func getType() -> Int { return type }
    func getName() -> String { return name }
    func getVendor() -> String { return vendor }
    func getVersion() -> Int { return version }
    func getMaximumRange() -> Float { return maximumRange }
    func getResolution() -> Float { return resolution }
    func getPower() -> Float { return power }
    func getMinDelay() -> Int { return minDelay }
    func getMaxDelay() -> Int { return maxDelay }
    func getStringType() -> String { return stringType }
    func getReportingMode() -> Int { return reportingMode }

    /// Sensor.getMaxLengthValuesArray (sSensorReportingModes): the length of this type's SensorEvent.values.
    static func getMaxLengthValuesArray(_ sensor: ASensor) -> Int {
        switch sensor.type {
        case TYPE_ACCELEROMETER, TYPE_MAGNETIC_FIELD, TYPE_ORIENTATION, TYPE_GYROSCOPE, TYPE_GRAVITY,
             TYPE_LINEAR_ACCELERATION:
            return 3
        case TYPE_LIGHT, TYPE_PRESSURE, TYPE_TEMPERATURE, TYPE_PROXIMITY, TYPE_RELATIVE_HUMIDITY,
             TYPE_AMBIENT_TEMPERATURE, TYPE_SIGNIFICANT_MOTION, TYPE_STEP_DETECTOR, TYPE_STEP_COUNTER:
            return 1
        case TYPE_ROTATION_VECTOR, TYPE_GEOMAGNETIC_ROTATION_VECTOR:
            return 5
        case TYPE_GAME_ROTATION_VECTOR:
            return 4
        case TYPE_MAGNETIC_FIELD_UNCALIBRATED, TYPE_GYROSCOPE_UNCALIBRATED:
            return 6
        default:
            return 16
        }
    }
}

// MARK: - SensorEvent

/// android.hardware.SensorEvent. As on Android, the sensor queue reuses one event object per (listener, sensor) and
/// overwrites its fields for every sample.
final class ASensorEvent {
    var values: [Float]
    var sensor: ASensor!
    var accuracy: Int = 0
    /// Nanoseconds, SystemClock.elapsedRealtimeNanos() time base.
    var timestamp: Int64 = 0
    var firstEventAfterDiscontinuity: Bool = false

    /// SensorEvent(int valueSize) (the queue's constructor).
    init(_ valueSize: Int) {
        values = [Float](repeating: 0, count: valueSize)
    }

    /// SensorEvent(Sensor sensor, int accuracy, long timestamp, float[] values) (public API 34 constructor).
    init(_ sensor: ASensor, _ accuracy: Int, _ timestamp: Int64, _ values: [Float]) {
        self.sensor = sensor
        self.accuracy = accuracy
        self.timestamp = timestamp
        self.values = values
    }
}

// MARK: - SensorEventListener

/// android.hardware.SensorEventListener. Callbacks run on the main thread.
protocol ASensorEventListener: AnyObject {
    func onSensorChanged(_ event: ASensorEvent)
    func onAccuracyChanged(_ sensor: ASensor?, _ accuracy: Int)
}

// MARK: - SensorManager

/// android.hardware.SensorManager (SystemSensorManager behaviour). `ASensorManager.shared` is
/// `context.getSystemService(Context.SENSOR_SERVICE) as SensorManager`.
final class ASensorManager {
    private static let TAG = "SensorManager"

    /// The app's sensor service; it owns the app's single CMMotionManager (Apple: create only one per app).
    nonisolated(unsafe) static let shared = ASensorManager(motionManager: CMMotionManager(), availableTypes: nil)

    static let SENSOR_DELAY_FASTEST = 0
    static let SENSOR_DELAY_GAME = 1
    static let SENSOR_DELAY_UI = 2
    static let SENSOR_DELAY_NORMAL = 3

    static let SENSOR_STATUS_NO_CONTACT = -1
    static let SENSOR_STATUS_UNRELIABLE = 0
    static let SENSOR_STATUS_ACCURACY_LOW = 1
    static let SENSOR_STATUS_ACCURACY_MEDIUM = 2
    static let SENSOR_STATUS_ACCURACY_HIGH = 3

    static let STANDARD_GRAVITY: Float = 9.80665
    static let GRAVITY_EARTH: Float = 9.80665

    /// The shortest period CoreMotion is driven at (100 Hz); SENSOR_DELAY_FASTEST maps here.
    static let MIN_SAMPLING_PERIOD_US = 10_000

    /// Device-motion sensors in delivery order for one CMDeviceMotion sample: rotation first, then the gyroscope
    /// (spec 20 §9.2: the ARMED → RELEASING test sees the newest pull), then gravity and linear acceleration.
    private static let DEVICE_MOTION_TYPES = [
        ASensor.TYPE_GAME_ROTATION_VECTOR, ASensor.TYPE_ROTATION_VECTOR, ASensor.TYPE_GYROSCOPE,
        ASensor.TYPE_GRAVITY, ASensor.TYPE_LINEAR_ACCELERATION,
    ]

    /// The single CMMotionManager of the app; nil for a hardware-less manager (unit tests).
    let motionManager: CMMotionManager?

    private let sensorList: [ASensor]
    /// One queue per registered listener, in registration order (SystemSensorManager.mSensorListeners).
    private var queues: [SensorEventQueue] = []
    /// Requested period (µs) per sensor type: the fastest requested by any listener of that type.
    private var periodByType: [Int: Int] = [:]
    /// CMLogItem.timestamp of the last sample delivered per device-motion type (per-type rate).
    private var lastDeliveredByType: [Int: TimeInterval] = [:]

    private(set) var deviceMotionRunning = false
    private(set) var deviceMotionFrame: CMAttitudeReferenceFrame = .xArbitraryZVertical
    private var deviceMotionGeneration = 0
    private(set) var deviceMotionPeriodUs = ASensorManager.MIN_SAMPLING_PERIOD_US
    private(set) var accelerometerRunning = false
    private var accelerometerGeneration = 0
    private(set) var accelerometerPeriodUs = ASensorManager.MIN_SAMPLING_PERIOD_US

    /// `availableTypes` nil probes the hardware; a list makes a manager with exactly these sensors (tests).
    init(motionManager: CMMotionManager?, availableTypes: [Int]?) {
        self.motionManager = motionManager
        let types: [Int]
        if let forced = availableTypes {
            types = forced
        } else if let m = motionManager {
            var probed: [Int] = []
            let frames = CMMotionManager.availableAttitudeReferenceFrames()
            if m.isAccelerometerAvailable { probed.append(ASensor.TYPE_ACCELEROMETER) }
            if m.isDeviceMotionAvailable && m.isGyroAvailable { probed.append(ASensor.TYPE_GYROSCOPE) }
            if m.isDeviceMotionAvailable {
                probed.append(ASensor.TYPE_GRAVITY)
                probed.append(ASensor.TYPE_LINEAR_ACCELERATION)
                if frames.contains(.xMagneticNorthZVertical) { probed.append(ASensor.TYPE_ROTATION_VECTOR) }
                if frames.contains(.xArbitraryZVertical) { probed.append(ASensor.TYPE_GAME_ROTATION_VECTOR) }
            }
            types = probed
        } else {
            types = []
        }
        sensorList = types.sorted().map { ASensorManager.makeSensor($0) }
    }

    private static func makeSensor(_ type: Int) -> ASensor {
        let g = ASensorManager.STANDARD_GRAVITY
        switch type {
        case ASensor.TYPE_ACCELEROMETER:
            return ASensor(type: type, name: "iOS Accelerometer (CoreMotion)", maximumRange: 16 * g,
                           resolution: 0.0024, power: 0.1, stringType: ASensor.STRING_TYPE_ACCELEROMETER)
        case ASensor.TYPE_GYROSCOPE:
            return ASensor(type: type, name: "iOS Gyroscope (CoreMotion device motion)", maximumRange: 34.906586,
                           resolution: 0.0011, power: 0.5, stringType: ASensor.STRING_TYPE_GYROSCOPE)
        case ASensor.TYPE_GRAVITY:
            return ASensor(type: type, name: "iOS Gravity (CoreMotion device motion)", maximumRange: g,
                           resolution: 0.0024, power: 0.6, stringType: ASensor.STRING_TYPE_GRAVITY)
        case ASensor.TYPE_LINEAR_ACCELERATION:
            return ASensor(type: type, name: "iOS Linear Acceleration (CoreMotion device motion)",
                           maximumRange: 16 * g, resolution: 0.0024, power: 0.6,
                           stringType: ASensor.STRING_TYPE_LINEAR_ACCELERATION)
        case ASensor.TYPE_ROTATION_VECTOR:
            return ASensor(type: type, name: "iOS Rotation Vector (CoreMotion xMagneticNorthZVertical)",
                           maximumRange: 1, resolution: 0.000001, power: 0.8,
                           stringType: ASensor.STRING_TYPE_ROTATION_VECTOR)
        case ASensor.TYPE_GAME_ROTATION_VECTOR:
            return ASensor(type: type, name: "iOS Game Rotation Vector (CoreMotion xArbitraryZVertical)",
                           maximumRange: 1, resolution: 0.000001, power: 0.6,
                           stringType: ASensor.STRING_TYPE_GAME_ROTATION_VECTOR)
        default:
            return ASensor(type: type, name: "iOS sensor \(type)")
        }
    }

    // MARK: sensor list

    func getSensorList(_ type: Int) -> [ASensor] {
        if type == ASensor.TYPE_ALL { return sensorList }
        return sensorList.filter { $0.type == type }
    }

    /// SensorManager.getDefaultSensor(type): the first non-wake-up sensor of that type, or nil.
    func getDefaultSensor(_ type: Int) -> ASensor? {
        // TODO: need to be smarter, for now, just return the 1st sensor
        let l = getSensorList(type)
        let wakeUpSensor = type == ASensor.TYPE_PROXIMITY || type == ASensor.TYPE_SIGNIFICANT_MOTION
        for sensor in l where sensor.isWakeUpSensor == wakeUpSensor {
            return sensor
        }
        return nil
    }

    // MARK: registration

    /// SensorManager.getDelay: SENSOR_DELAY_* constant → µs; any other value already is a period in µs.
    static func getDelay(_ rate: Int) -> Int {
        var delay = -1
        switch rate {
        case SENSOR_DELAY_FASTEST:
            delay = 0
        case SENSOR_DELAY_GAME:
            delay = 20000
        case SENSOR_DELAY_UI:
            delay = 66667
        case SENSOR_DELAY_NORMAL:
            delay = 200000
        default:
            delay = rate
        }
        return delay
    }

    @discardableResult
    func registerListener(_ listener: ASensorEventListener?, _ sensor: ASensor?, _ samplingPeriodUs: Int) -> Bool {
        let delay = ASensorManager.getDelay(samplingPeriodUs)
        return registerListenerImpl(listener, sensor, delay, 0)
    }

    @discardableResult
    func registerListener(_ listener: ASensorEventListener?, _ sensor: ASensor?, _ samplingPeriodUs: Int,
                          _ maxReportLatencyUs: Int) -> Bool {
        let delay = ASensorManager.getDelay(samplingPeriodUs)
        return registerListenerImpl(listener, sensor, delay, maxReportLatencyUs)
    }

    func unregisterListener(_ listener: ASensorEventListener?, _ sensor: ASensor?) {
        guard let listener = listener, let sensor = sensor else {
            return
        }
        unregisterListenerImpl(listener, sensor)
    }

    func unregisterListener(_ listener: ASensorEventListener?) {
        guard let listener = listener else {
            return
        }
        unregisterListenerImpl(listener, nil)
    }

    private func registerListenerImpl(_ listener: ASensorEventListener?, _ sensor: ASensor?, _ delayUs: Int,
                                      _ maxBatchReportLatencyUs: Int) -> Bool {
        guard let listener = listener, let sensor = sensor else {
            ALog.e(ASensorManager.TAG, "sensor or listener is null")
            return false
        }
        if sensor.reportingMode == ASensor.REPORTING_MODE_ONE_SHOT {
            ALog.e(ASensorManager.TAG, "Trigger Sensors should use the requestTriggerSensor.")
            return false
        }
        if maxBatchReportLatencyUs < 0 || delayUs < 0 {
            ALog.e(ASensorManager.TAG, "maxBatchReportLatencyUs and delayUs should be non-negative")
            return false
        }
        // enableSensor fails for a sensor this device does not have.
        guard sensorList.contains(where: { $0 === sensor }) else {
            return false
        }
        if let queue = queues.first(where: { $0.listener === listener }) {
            let added = queue.addSensor(sensor, delayUs)
            if added { reconfigure() }
            return added
        }
        let queue = SensorEventQueue(listener)
        if !queue.addSensor(sensor, delayUs) {
            return false
        }
        queues.append(queue)
        reconfigure()
        return true
    }

    private func unregisterListenerImpl(_ listener: ASensorEventListener, _ sensor: ASensor?) {
        guard let index = queues.firstIndex(where: { $0.listener === listener }) else {
            return
        }
        let queue = queues[index]
        let result: Bool
        if let sensor = sensor {
            result = queue.removeSensor(sensor)
        } else {
            result = queue.removeAllSensors()
        }
        if result && !queue.hasSensors() {
            queues.remove(at: index)
            queue.dispose()
        }
        if result {
            reconfigure()
        }
    }

    // MARK: CoreMotion streams

    /// Starts, retunes or stops the device-motion and accelerometer streams for the current registrations.
    private func reconfigure() {
        var periods: [Int: Int] = [:]
        for queue in queues {
            for (type, delayUs) in queue.activeDelays {
                periods[type] = min(periods[type] ?? Int.max, delayUs)
            }
        }
        periodByType = periods

        var motionPeriodUs = Int.max
        for type in ASensorManager.DEVICE_MOTION_TYPES {
            if let p = periods[type] { motionPeriodUs = min(motionPeriodUs, p) }
        }
        if motionPeriodUs == Int.max {
            stopDeviceMotion()
        } else {
            let frame: CMAttitudeReferenceFrame = periods[ASensor.TYPE_ROTATION_VECTOR] != nil
                ? .xMagneticNorthZVertical : .xArbitraryZVertical
            startDeviceMotion(max(ASensorManager.MIN_SAMPLING_PERIOD_US, motionPeriodUs), frame)
        }

        if let accelerometerUs = periods[ASensor.TYPE_ACCELEROMETER] {
            startAccelerometer(max(ASensorManager.MIN_SAMPLING_PERIOD_US, accelerometerUs))
        } else {
            stopAccelerometer()
        }
    }

    private func startDeviceMotion(_ periodUs: Int, _ frame: CMAttitudeReferenceFrame) {
        let interval = TimeInterval(periodUs) / 1_000_000
        deviceMotionPeriodUs = periodUs
        if deviceMotionRunning && deviceMotionFrame == frame {
            if let m = motionManager, m.deviceMotionUpdateInterval != interval {
                m.deviceMotionUpdateInterval = interval
            }
            return
        }
        if deviceMotionRunning {
            motionManager?.stopDeviceMotionUpdates()
        }
        deviceMotionGeneration += 1
        deviceMotionRunning = true
        deviceMotionFrame = frame
        lastDeliveredByType.removeAll()
        guard let m = motionManager else { return }
        let generation = deviceMotionGeneration
        m.deviceMotionUpdateInterval = interval
        m.startDeviceMotionUpdates(using: frame, to: OperationQueue.main) { [weak self] motion, _ in
            guard let self = self, generation == self.deviceMotionGeneration, let motion = motion else { return }
            self.onDeviceMotion(motion)
        }
    }

    private func stopDeviceMotion() {
        guard deviceMotionRunning else { return }
        deviceMotionRunning = false
        deviceMotionGeneration += 1
        lastDeliveredByType.removeAll()
        motionManager?.stopDeviceMotionUpdates()
    }

    private func startAccelerometer(_ periodUs: Int) {
        let interval = TimeInterval(periodUs) / 1_000_000
        accelerometerPeriodUs = periodUs
        if accelerometerRunning {
            if let m = motionManager, m.accelerometerUpdateInterval != interval {
                m.accelerometerUpdateInterval = interval
            }
            return
        }
        accelerometerGeneration += 1
        accelerometerRunning = true
        guard let m = motionManager else { return }
        let generation = accelerometerGeneration
        m.accelerometerUpdateInterval = interval
        m.startAccelerometerUpdates(to: OperationQueue.main) { [weak self] data, _ in
            guard let self = self, generation == self.accelerometerGeneration, let data = data else { return }
            self.deliverAccelerometer(timestamp: data.timestamp, values: Mapping.accelerometer(data.acceleration))
        }
    }

    private func stopAccelerometer() {
        guard accelerometerRunning else { return }
        accelerometerRunning = false
        accelerometerGeneration += 1
        motionManager?.stopAccelerometerUpdates()
    }

    private func onDeviceMotion(_ motion: CMDeviceMotion) {
        let accuracy = Mapping.accuracy(motion.magneticField.accuracy)
        deliverDeviceMotion(timestamp: motion.timestamp, magneticAccuracy: accuracy) { type in
            switch type {
            case ASensor.TYPE_GAME_ROTATION_VECTOR:
                return Mapping.gameRotationVector(attitude: motion.attitude.quaternion, gravity: motion.gravity)
            case ASensor.TYPE_ROTATION_VECTOR:
                return Mapping.rotationVector(attitude: motion.attitude.quaternion, gravity: motion.gravity)
            case ASensor.TYPE_GYROSCOPE:
                return Mapping.gyroscope(motion.rotationRate)
            case ASensor.TYPE_GRAVITY:
                return Mapping.gravity(motion.gravity)
            default:
                return Mapping.linearAcceleration(motion.userAcceleration)
            }
        }
    }

    /// One CMDeviceMotion sample → the due device-motion sensors, in DEVICE_MOTION_TYPES order. `timestamp` is
    /// CMLogItem.timestamp (seconds of system uptime). Internal so tests can inject samples.
    func deliverDeviceMotion(timestamp: TimeInterval, magneticAccuracy: Int, _ valuesFor: (Int) -> [Float]) {
        let timestampNanos = ASensorManager.elapsedRealtimeNanos(ofUptime: timestamp)
        for type in ASensorManager.DEVICE_MOTION_TYPES {
            guard let periodUs = periodByType[type], isDue(type, timestamp, periodUs) else { continue }
            lastDeliveredByType[type] = timestamp
            let accuracy = type == ASensor.TYPE_ROTATION_VECTOR
                ? magneticAccuracy : ASensorManager.SENSOR_STATUS_ACCURACY_HIGH
            dispatchSensorEvent(type, valuesFor(type), accuracy, timestampNanos)
        }
    }

    /// One accelerometer sample (CMAccelerometerData, already in Android units). Internal so tests can inject samples.
    func deliverAccelerometer(timestamp: TimeInterval, values: [Float]) {
        guard periodByType[ASensor.TYPE_ACCELEROMETER] != nil else { return }
        dispatchSensorEvent(ASensor.TYPE_ACCELEROMETER, values, ASensorManager.SENSOR_STATUS_ACCURACY_HIGH,
                            ASensorManager.elapsedRealtimeNanos(ofUptime: timestamp))
    }

    /// A sensor whose period equals the stream's gets every sample; a slower one gets the sample once its period
    /// has elapsed (half a stream period of tolerance absorbs CoreMotion's delivery jitter).
    private func isDue(_ type: Int, _ timestamp: TimeInterval, _ periodUs: Int) -> Bool {
        guard let last = lastDeliveredByType[type] else { return true }
        let period = TimeInterval(periodUs) / 1_000_000
        let tolerance = TimeInterval(deviceMotionPeriodUs) / 2_000_000
        return timestamp - last >= period - tolerance
    }

    private func dispatchSensorEvent(_ type: Int, _ values: [Float], _ accuracy: Int, _ timestamp: Int64) {
        guard let sensor = sensorList.first(where: { $0.type == type }) else { return }
        for queue in queues {   // a snapshot: listeners may (un)register from inside their callbacks
            queue.dispatchSensorEvent(sensor, values, accuracy, timestamp)
        }
    }

    /// CMLogItem.timestamp (seconds of uptime, the same time base as ProcessInfo.systemUptime) →
    /// SystemClock.elapsedRealtimeNanos() domain, the time base of Android SensorEvent.timestamp.
    private static func elapsedRealtimeNanos(ofUptime timestamp: TimeInterval) -> Int64 {
        let age = ProcessInfo.processInfo.systemUptime - timestamp
        let ageNanos: Int64 = age.isFinite && age > 0 ? Int64(age * 1_000_000_000) : 0
        return ASystemClock.elapsedRealtimeNanos() - ageNanos
    }

    // MARK: rotation math (verbatim AOSP SensorManager, android-37 sources)

    /// SensorManager.getRotationMatrixFromVector: `R` (9 or 16 values) from a rotation vector (3, 4 or 5 values).
    static func getRotationMatrixFromVector(_ R: inout [Float], _ rotationVector: [Float]) {

        var q0: Float
        let q1 = rotationVector[0]
        let q2 = rotationVector[1]
        let q3 = rotationVector[2]

        if rotationVector.count >= 4 {
            q0 = rotationVector[3]
        } else {
            q0 = 1 - q1 * q1 - q2 * q2 - q3 * q3
            q0 = (q0 > 0) ? Float(Double(q0).squareRoot()) : 0
        }

        let sq_q1: Float = 2 * q1 * q1
        let sq_q2: Float = 2 * q2 * q2
        let sq_q3: Float = 2 * q3 * q3
        let q1_q2: Float = 2 * q1 * q2
        let q3_q0: Float = 2 * q3 * q0
        let q1_q3: Float = 2 * q1 * q3
        let q2_q0: Float = 2 * q2 * q0
        let q2_q3: Float = 2 * q2 * q3
        let q1_q0: Float = 2 * q1 * q0

        if R.count == 9 {
            R[0] = 1 - sq_q2 - sq_q3
            R[1] = q1_q2 - q3_q0
            R[2] = q1_q3 + q2_q0

            R[3] = q1_q2 + q3_q0
            R[4] = 1 - sq_q1 - sq_q3
            R[5] = q2_q3 - q1_q0

            R[6] = q1_q3 - q2_q0
            R[7] = q2_q3 + q1_q0
            R[8] = 1 - sq_q1 - sq_q2
        } else if R.count == 16 {
            R[0] = 1 - sq_q2 - sq_q3
            R[1] = q1_q2 - q3_q0
            R[2] = q1_q3 + q2_q0
            R[3] = 0.0

            R[4] = q1_q2 + q3_q0
            R[5] = 1 - sq_q1 - sq_q3
            R[6] = q2_q3 - q1_q0
            R[7] = 0.0

            R[8] = q1_q3 - q2_q0
            R[9] = q2_q3 + q1_q0
            R[10] = 1 - sq_q1 - sq_q2
            R[11] = 0.0

            R[12] = 0.0
            R[13] = 0.0
            R[14] = 0.0
            R[15] = 1.0
        }
    }

    /// SensorManager.getOrientation: azimuth, pitch, roll (radians) from a 3×3 or 4×4 rotation matrix.
    @discardableResult
    static func getOrientation(_ R: [Float], _ values: inout [Float]) -> [Float] {
        /*
         * 4x4 (length=16) case:
         *   /  R[ 0]   R[ 1]   R[ 2]   0  \
         *   |  R[ 4]   R[ 5]   R[ 6]   0  |
         *   |  R[ 8]   R[ 9]   R[10]   0  |
         *   \      0       0       0   1  /
         *
         * 3x3 (length=9) case:
         *   /  R[ 0]   R[ 1]   R[ 2]  \
         *   |  R[ 3]   R[ 4]   R[ 5]  |
         *   \  R[ 6]   R[ 7]   R[ 8]  /
         *
         */
        if R.count == 9 {
            values[0] = Float(atan2(Double(R[1]), Double(R[4])))
            values[1] = Float(asin(Double(-R[7])))
            values[2] = Float(atan2(Double(-R[6]), Double(R[8])))
        } else {
            values[0] = Float(atan2(Double(R[1]), Double(R[5])))
            values[1] = Float(asin(Double(-R[9])))
            values[2] = Float(atan2(Double(-R[8]), Double(R[10])))
        }

        return values
    }

    /// SensorManager.getQuaternionFromVector: Q = (w, x, y, z) from a rotation vector.
    static func getQuaternionFromVector(_ Q: inout [Float], _ rv: [Float]) {
        if rv.count >= 4 {
            Q[0] = rv[3]
        } else {
            Q[0] = 1 - rv[0] * rv[0] - rv[1] * rv[1] - rv[2] * rv[2]
            Q[0] = (Q[0] > 0) ? Float(Double(Q[0]).squareRoot()) : 0
        }
        Q[1] = rv[0]
        Q[2] = rv[1]
        Q[3] = rv[2]
    }

    // MARK: CoreMotion → Android values

    /// Pure conversions from CoreMotion samples to Android SensorEvent.values (internal for tests).
    enum Mapping {
        /// TYPE_ACCELEROMETER from CMAccelerometerData.acceleration (g, iOS sign: flat face up = (0, 0, -1)).
        static func accelerometer(_ a: CMAcceleration) -> [Float] {
            let g = Double(ASensorManager.STANDARD_GRAVITY)
            return [Float(-a.x * g), Float(-a.y * g), Float(-a.z * g)]
        }

        /// TYPE_GRAVITY from CMDeviceMotion.gravity: the accelerometer's gravity part, Android sign.
        static func gravity(_ gravity: CMAcceleration) -> [Float] {
            return accelerometer(gravity)
        }

        /// TYPE_LINEAR_ACCELERATION from CMDeviceMotion.userAcceleration (accelerometer = gravity + linear).
        static func linearAcceleration(_ u: CMAcceleration) -> [Float] {
            return accelerometer(u)
        }

        /// TYPE_GYROSCOPE from CMDeviceMotion.rotationRate: same axes, rad/s, right-hand rule on both platforms.
        static func gyroscope(_ r: CMRotationRate) -> [Float] {
            return [Float(r.x), Float(r.y), Float(r.z)]
        }

        /// TYPE_GAME_ROTATION_VECTOR (x, y, z, w): the device → reference rotation of CMAttitude.quaternion
        /// (.xArbitraryZVertical: Z up, X an arbitrary horizontal direction; Android's game frame is the same kind).
        static func gameRotationVector(attitude q: CMQuaternion, gravity g: CMAcceleration) -> [Float] {
            let r = quaternion(fromMatrix: deviceToWorld(attitude: q, gravity: g))
            return [Float(r.x), Float(r.y), Float(r.z), Float(r.w)]
        }

        /// TYPE_ROTATION_VECTOR (x, y, z, w, headingAccuracy) in Android's world frame (X east, Y north, Z up) from
        /// the .xMagneticNorthZVertical attitude (X north, Y west, Z up). The heading accuracy is unavailable (-1).
        static func rotationVector(attitude q: CMQuaternion, gravity g: CMAcceleration) -> [Float] {
            var m = deviceToWorld(attitude: q, gravity: g)
            let north = (m[0], m[1], m[2])
            let west = (m[3], m[4], m[5])
            m[0] = -west.0
            m[1] = -west.1
            m[2] = -west.2
            m[3] = north.0
            m[4] = north.1
            m[5] = north.2
            let r = quaternion(fromMatrix: m)
            return [Float(r.x), Float(r.y), Float(r.z), Float(r.w), -1]
        }

        /// CMMagneticFieldCalibrationAccuracy → SensorManager.SENSOR_STATUS_*.
        static func accuracy(_ a: CMMagneticFieldCalibrationAccuracy) -> Int {
            switch a {
            case .high: return ASensorManager.SENSOR_STATUS_ACCURACY_HIGH
            case .medium: return ASensorManager.SENSOR_STATUS_ACCURACY_MEDIUM
            case .low: return ASensorManager.SENSOR_STATUS_ACCURACY_LOW
            default: return ASensorManager.SENSOR_STATUS_UNRELIABLE
            }
        }

        /// Row-major 3×3 device → reference matrix (rows = reference axes in device coordinates, the layout of
        /// SensorManager.getRotationMatrixFromVector). The vertical row is the documented device-frame gravity
        /// direction (up = -gravity); the heading comes from the attitude, made perpendicular to it.
        static func deviceToWorld(attitude q: CMQuaternion, gravity g: CMAcceleration) -> [Double] {
            let x = q.x, y = q.y, z = q.z, w = q.w
            var m: [Double] = [
                1 - 2 * y * y - 2 * z * z, 2 * x * y - 2 * z * w, 2 * x * z + 2 * y * w,
                2 * x * y + 2 * z * w, 1 - 2 * x * x - 2 * z * z, 2 * y * z - 2 * x * w,
                2 * x * z - 2 * y * w, 2 * y * z + 2 * x * w, 1 - 2 * x * x - 2 * y * y,
            ]
            let gn = (g.x * g.x + g.y * g.y + g.z * g.z).squareRoot()
            guard gn > 1e-6, gn.isFinite else { return m }
            let up = (-g.x / gn, -g.y / gn, -g.z / gn)
            func dot(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
                return a.0 * b.0 + a.1 * b.1 + a.2 * b.2
            }
            func cross(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> (Double, Double, Double) {
                return (a.1 * b.2 - a.2 * b.1, a.2 * b.0 - a.0 * b.2, a.0 * b.1 - a.1 * b.0)
            }
            func horizontal(_ v: (Double, Double, Double)) -> (Double, Double, Double)? {
                let d = dot(v, up)
                let h = (v.0 - d * up.0, v.1 - d * up.1, v.2 - d * up.2)
                let n = dot(h, h).squareRoot()
                return n < 1e-6 ? nil : (h.0 / n, h.1 / n, h.2 / n)
            }
            let yAxis: (Double, Double, Double)
            if let h = horizontal((m[3], m[4], m[5])) {
                yAxis = h
            } else if let hx = horizontal((m[0], m[1], m[2])) {
                yAxis = cross(up, hx)                      // Y = Z × X
            } else {
                return m
            }
            let xAxis = cross(yAxis, up)                   // X = Y × Z
            m = [xAxis.0, xAxis.1, xAxis.2, yAxis.0, yAxis.1, yAxis.2, up.0, up.1, up.2]
            return m
        }

        /// The unit quaternion (x, y, z, w ≥ 0) whose getRotationMatrixFromVector matrix is `m` (Shepperd).
        static func quaternion(fromMatrix m: [Double]) -> (x: Double, y: Double, z: Double, w: Double) {
            var x: Double, y: Double, z: Double, w: Double
            let trace = m[0] + m[4] + m[8]
            if trace > 0 {
                let s = (trace + 1).squareRoot() * 2       // 4w
                w = 0.25 * s
                x = (m[7] - m[5]) / s
                y = (m[2] - m[6]) / s
                z = (m[3] - m[1]) / s
            } else if m[0] > m[4] && m[0] > m[8] {
                let s = (1 + m[0] - m[4] - m[8]).squareRoot() * 2   // 4x
                w = (m[7] - m[5]) / s
                x = 0.25 * s
                y = (m[1] + m[3]) / s
                z = (m[2] + m[6]) / s
            } else if m[4] > m[8] {
                let s = (1 + m[4] - m[0] - m[8]).squareRoot() * 2   // 4y
                w = (m[2] - m[6]) / s
                x = (m[1] + m[3]) / s
                y = 0.25 * s
                z = (m[5] + m[7]) / s
            } else {
                let s = (1 + m[8] - m[0] - m[4]).squareRoot() * 2   // 4z
                w = (m[3] - m[1]) / s
                x = (m[2] + m[6]) / s
                y = (m[5] + m[7]) / s
                z = 0.25 * s
            }
            if w < 0 {
                x = -x
                y = -y
                z = -z
                w = -w
            }
            let n = (x * x + y * y + z * z + w * w).squareRoot()
            if n > 0 && n.isFinite {
                x /= n
                y /= n
                z /= n
                w /= n
            }
            return (x, y, z, w)
        }
    }

    // MARK: SensorEventQueue

    /// SystemSensorManager.SensorEventQueue: one per listener, one reused SensorEvent per active sensor, and the
    /// last accuracy reported per sensor (onAccuracyChanged only fires when it changes).
    private final class SensorEventQueue {
        let listener: ASensorEventListener          // strong while registered, as Android's listener map
        private(set) var activeDelays: [Int: Int] = [:]
        private var sensorsEvents: [Int: ASensorEvent] = [:]
        private var sensorAccuracies: [Int: Int] = [:]
        private var disposed = false

        init(_ listener: ASensorEventListener) {
            self.listener = listener
        }

        func addSensor(_ sensor: ASensor, _ delayUs: Int) -> Bool {
            // Check if already present.
            if activeDelays[sensor.type] != nil { return false }
            // Get ready to receive events before calling enable.
            activeDelays[sensor.type] = delayUs
            sensorsEvents[sensor.type] = ASensorEvent(ASensor.getMaxLengthValuesArray(sensor))
            return true
        }

        func removeAllSensors() -> Bool {
            activeDelays.removeAll()
            sensorsEvents.removeAll()
            return true
        }

        func removeSensor(_ sensor: ASensor) -> Bool {
            if activeDelays[sensor.type] != nil {
                activeDelays[sensor.type] = nil
                sensorsEvents[sensor.type] = nil
                return true
            }
            return false
        }

        func hasSensors() -> Bool {
            return !activeDelays.isEmpty
        }

        func dispose() {
            disposed = true
        }

        func dispatchSensorEvent(_ sensor: ASensor, _ values: [Float], _ inAccuracy: Int, _ timestamp: Int64) {
            // This may happen if the client has unregistered and there are pending events in the queue waiting
            // to be delivered. Ignore.
            guard !disposed, let t = sensorsEvents[sensor.type] else { return }
            // Copy from the values array.
            for i in 0..<t.values.count {
                t.values[i] = i < values.count ? values[i] : 0
            }
            t.timestamp = timestamp
            t.accuracy = inAccuracy
            t.sensor = sensor

            // call onAccuracyChanged() only if the value changes
            let accuracy = sensorAccuracies[sensor.type] ?? 0
            if t.accuracy >= 0 && accuracy != t.accuracy {
                sensorAccuracies[sensor.type] = t.accuracy
                listener.onAccuracyChanged(t.sensor, t.accuracy)
            }

            t.firstEventAfterDiscontinuity = false

            listener.onSensorChanged(t)
        }
    }
}

// MARK: - OrientationEventListener

/// android.view.OrientationEventListener: the device's physical rotation in degrees (0..359, ORIENTATION_UNKNOWN when
/// flat) from the raw accelerometer, independent of the UI orientation lock (not UIDevice.orientation). Subclass and
/// override `onOrientationChanged`, or pass the callback as a closure: a Kotlin
/// `object : OrientationEventListener(context) { override fun onOrientationChanged(orientation: Int) { ... } }` that
/// writes captured locals becomes `AOrientationEventListener(context) { orientation in ... }` (Swift local classes
/// cannot capture locals).
class AOrientationEventListener {
    private static let TAG = "OrientationEventListener"

    /// Returned from onOrientationChanged when the device orientation cannot be determined (close to flat).
    static let ORIENTATION_UNKNOWN = -1

    fileprivate var mOrientation = AOrientationEventListener.ORIENTATION_UNKNOWN
    private let mSensorManager: ASensorManager
    private var mEnabled = false
    private let mRate: Int
    private let mSensor: ASensor?
    private let mSensorEventListener: SensorEventListenerImpl?
    private var orientationChangedBlock: ((Int) -> Void)?

    /// OrientationEventListener(Context context, int rate) with an explicit sensor service: `context.getSystemService(
    /// Context.SENSOR_SERVICE)` is `sensorManager` (unit tests pass a hardware-less ASensorManager).
    init(_ rate: Int = ASensorManager.SENSOR_DELAY_NORMAL, sensorManager: ASensorManager) {
        mSensorManager = sensorManager
        mRate = rate
        mSensor = mSensorManager.getDefaultSensor(ASensor.TYPE_ACCELEROMETER)
        if mSensor != nil {
            // Create listener only if sensors do exist.
            mSensorEventListener = SensorEventListenerImpl()
        } else {
            mSensorEventListener = nil
        }
    }

    /// `OrientationEventListener(context)` (SENSOR_DELAY_NORMAL) / `OrientationEventListener(context, rate)`. The
    /// context only supplied the sensor service (ASensorManager.shared).
    convenience init(_ context: Any?, _ rate: Int = ASensorManager.SENSOR_DELAY_NORMAL) {
        self.init(rate, sensorManager: ASensorManager.shared)
    }

    /// The same without a context (AndroidKit initialisers take no context, VIEW-API).
    convenience init(_ rate: Int = ASensorManager.SENSOR_DELAY_NORMAL) {
        self.init(rate, sensorManager: ASensorManager.shared)
    }

    /// Kotlin `object : OrientationEventListener(context) { override fun onOrientationChanged(o: Int) { ... } }`.
    convenience init(_ context: Any?, _ rate: Int = ASensorManager.SENSOR_DELAY_NORMAL,
                     onOrientationChanged: @escaping (Int) -> Void) {
        self.init(rate, sensorManager: ASensorManager.shared)
        orientationChangedBlock = onOrientationChanged
    }

    /// The same without a context.
    convenience init(_ rate: Int = ASensorManager.SENSOR_DELAY_NORMAL,
                     onOrientationChanged: @escaping (Int) -> Void) {
        self.init(rate, sensorManager: ASensorManager.shared)
        orientationChangedBlock = onOrientationChanged
    }

    /// Enables the listener so it monitors the sensor and calls onOrientationChanged when the orientation changes.
    func enable() {
        guard let sensor = mSensor, let impl = mSensorEventListener else {
            ALog.w(AOrientationEventListener.TAG, "Cannot detect sensors. Not enabled")
            return
        }
        if mEnabled == false {
            impl.owner = self   // Java: the registered inner class keeps the outer listener reachable
            mSensorManager.registerListener(impl, sensor, mRate)
            mEnabled = true
        }
    }

    /// Disables the listener.
    func disable() {
        guard mSensor != nil, let impl = mSensorEventListener else {
            ALog.w(AOrientationEventListener.TAG, "Cannot detect sensors. Invalid disable")
            return
        }
        if mEnabled == true {
            mSensorManager.unregisterListener(impl)
            impl.owner = nil
            mEnabled = false
        }
    }

    /// True if the device has an accelerometer.
    func canDetectOrientation() -> Bool {
        return mSensor != nil
    }

    /// Called when the orientation changes: degrees 0..359 (0 = natural portrait, 90 = left side at the top,
    /// 180 = upside down, 270 = right side at the top) or ORIENTATION_UNKNOWN. Override point (abstract in Java).
    func onOrientationChanged(_ orientation: Int) {
        orientationChangedBlock?(orientation)
    }

    /// The angle of SensorEventListenerImpl.onSensorChanged (values = accelerometer, Android units and signs).
    static func orientation(fromAccelerometer values: [Float]) -> Int {
        var orientation = ORIENTATION_UNKNOWN
        let X: Float = -values[SensorEventListenerImpl._DATA_X]
        let Y: Float = -values[SensorEventListenerImpl._DATA_Y]
        let Z: Float = -values[SensorEventListenerImpl._DATA_Z]
        let magnitude: Float = X * X + Y * Y
        // Don't trust the angle if the magnitude is small compared to the y value
        if magnitude * 4 >= Z * Z {
            let OneEightyOverPi: Float = 57.29577957855
            let angle: Float = Float(atan2(Double(-Y), Double(X))) * OneEightyOverPi
            orientation = 90 - javaMathRound(angle)   // (int) Math.round(float)
            // normalize to 0 - 359 range
            while orientation >= 360 {
                orientation -= 360
            }
            while orientation < 0 {
                orientation += 360
            }
        }
        return orientation
    }

    fileprivate final class SensorEventListenerImpl: ASensorEventListener {
        static let _DATA_X = 0
        static let _DATA_Y = 1
        static let _DATA_Z = 2

        /// Set while enabled (the sensor manager then keeps this impl, and through it the outer listener, alive).
        var owner: AOrientationEventListener?

        func onSensorChanged(_ event: ASensorEvent) {
            guard let owner = owner else { return }
            let orientation = AOrientationEventListener.orientation(fromAccelerometer: event.values)
            if orientation != owner.mOrientation {
                owner.mOrientation = orientation
                owner.onOrientationChanged(orientation)
            }
        }

        func onAccuracyChanged(_ sensor: ASensor?, _ accuracy: Int) {

        }
    }
}
