import Foundation

// android.view.VelocityTracker with Android's default strategy for touch axes: LSQ2, the unweighted least-squares
// quadratic fit (AOSP frameworks/native/libs/input/VelocityTracker.cpp, Android 14+ behaviour, spec 20 §4.11/§9.6).
//
// - Every DOWN / POINTER_DOWN / MOVE sample (historical samples first, then the current one) is added per pointer and
//   per axis (X, then Y). The time base is the event's nanoseconds, like the native tracker.
// - A pointer that has not moved for more than 40 ms (ASSUME_POINTER_STOPPED_TIME) drops all samples; so does a lift
//   (UP / POINTER_UP) that comes more than 40 ms after the last sample ("stopped before lift-off"). DOWN and CANCEL
//   clear everything; POINTER_DOWN restarts that pointer.
// - Per pointer at most 20 samples (HISTORY_SIZE) within 100 ms (HORIZON) of the newest one are kept.
// - The velocity is the linear coefficient of the fit at the newest sample: 1 sample → none (0), 2 samples → the
//   degree-1 least-squares fit (Gram-Schmidt QR), 3+ samples → solveUnweightedLeastSquaresDeg2; a singular system
//   gives none. computeCurrentVelocity(units) scales by units / 1000 (pixels per second for 1000), in Float.
// Float arithmetic follows the C++ statement order (AOSP builds with -ffp-contract=off: no fused multiply-add).
final class AVelocityTracker {
    static let VELOCITY_TRACKER_STRATEGY_DEFAULT = -1
    static let VELOCITY_TRACKER_STRATEGY_IMPULSE = 0
    static let VELOCITY_TRACKER_STRATEGY_LSQ1 = 1
    static let VELOCITY_TRACKER_STRATEGY_LSQ2 = 2

    /// MotionEvent.AXIS_X / AXIS_Y / AXIS_SCROLL (the axes VelocityTracker can track).
    static let AXIS_X = 0
    static let AXIS_Y = 1
    static let AXIS_SCROLL = 26

    private static let ACTIVE_POINTER_ID = -1
    private static let MAX_POINTER_ID = 31
    /// Threshold for determining that a pointer has stopped moving (40 ms).
    private static let ASSUME_POINTER_STOPPED_TIME: Int64 = 40 * 1_000_000
    /// Axes specifying location on a 2D plane, in std::set order.
    private static let PLANAR_AXES = [AXIS_X, AXIS_Y]

    private var mLastEventTime: Int64 = 0
    /// Pointer ids currently tracked (BitSet32); iterated in ascending id order like clearFirstMarkedBit.
    private var mCurrentPointerIdBits: UInt32 = 0
    private var mActivePointerId: Int? = nil
    /// std::map<axis, strategy> (iterated in axis order).
    private var mConfiguredStrategies: [Int: LeastSquaresVelocityTrackerStrategy] = [:]
    /// The result of the last computeCurrentVelocity: axis → pointer id → velocity.
    private var mComputedVelocity: [Int: [Int: Float]] = [:]
    private let mStrategy: Int

    private init(_ strategy: Int) {
        mStrategy = strategy
    }

    /// VelocityTracker.obtain(): a tracker with the default strategy (LSQ2 for X and Y).
    static func obtain() -> AVelocityTracker {
        return AVelocityTracker(VELOCITY_TRACKER_STRATEGY_DEFAULT)
    }

    /// VelocityTracker.obtain(int strategy): only the default / LSQ2 strategy is implemented (the app uses obtain()).
    static func obtain(_ strategy: Int) -> AVelocityTracker {
        precondition(strategy == VELOCITY_TRACKER_STRATEGY_DEFAULT || strategy == VELOCITY_TRACKER_STRATEGY_LSQ2,
                     "VelocityTracker strategy \(strategy) is not implemented")
        return AVelocityTracker(strategy)
    }

    /// Returns the tracker to the pool: it is cleared (Android's pool may hand it out again; here it is just reset).
    func recycle() {
        clear()
    }

    func getStrategyId() -> Int {
        return mStrategy
    }

    func isAxisSupported(_ axis: Int) -> Bool {
        return axis == AVelocityTracker.AXIS_X || axis == AVelocityTracker.AXIS_Y || axis == AVelocityTracker.AXIS_SCROLL
    }

    /// Resets the tracker to its initial state.
    func clear() {
        mCurrentPointerIdBits = 0
        mActivePointerId = nil
        mConfiguredStrategies.removeAll()
    }

    private func clearPointer(_ pointerId: Int) {
        mCurrentPointerIdBits &= ~(UInt32(1) << UInt32(pointerId))

        if let active = mActivePointerId, active == pointerId {
            // The active pointer id is being removed. Mark it invalid and try to find a new one
            // from the remaining pointers.
            mActivePointerId = nil
            if mCurrentPointerIdBits != 0 {
                mActivePointerId = mCurrentPointerIdBits.trailingZeroBitCount
            }
        }

        for (_, strategy) in mConfiguredStrategies {
            strategy.clearPointer(pointerId)
        }
    }

    /// Native VelocityTracker::addMovement(eventTime, pointerId, axis, position); `eventTime` in nanoseconds.
    func addMovement(_ eventTime: Int64, _ pointerId: Int, _ axis: Int, _ position: Float) {
        precondition(pointerId >= 0 && pointerId <= AVelocityTracker.MAX_POINTER_ID, "Invalid pointer ID \(pointerId)")
        let bit = UInt32(1) << UInt32(pointerId)

        if (mCurrentPointerIdBits & bit) != 0 && eventTime - mLastEventTime > AVelocityTracker.ASSUME_POINTER_STOPPED_TIME {
            // We have not received any movements for too long.  Assume that all pointers
            // have stopped.
            mConfiguredStrategies.removeAll()
        }
        mLastEventTime = eventTime

        mCurrentPointerIdBits |= bit
        if mActivePointerId == nil {
            // Let this be the new active pointer if no active pointer is currently set
            mActivePointerId = pointerId
        }

        let strategy: LeastSquaresVelocityTrackerStrategy
        if let configured = mConfiguredStrategies[axis] {
            strategy = configured
        } else {
            strategy = LeastSquaresVelocityTrackerStrategy(2)
            mConfiguredStrategies[axis] = strategy
        }
        strategy.addMovement(eventTime, pointerId, position)
    }

    /// VelocityTracker.addMovement(MotionEvent).
    func addMovement(_ event: AMotionEvent) {
        var axesToProcess: [Int] = []
        let actionMasked = event.actionMasked

        switch actionMasked {
        case AMotionEvent.ACTION_DOWN, AMotionEvent.ACTION_HOVER_ENTER:
            // Clear all pointers on down before adding the new movement.
            clear()
            axesToProcess = AVelocityTracker.PLANAR_AXES
        case AMotionEvent.ACTION_POINTER_DOWN:
            // Start a new movement trace for a pointer that just went down.
            // We do this on down instead of on up because the client may want to query the
            // final velocity for a pointer that just went up.
            clearPointer(event.getPointerId(event.actionIndex))
            axesToProcess = AVelocityTracker.PLANAR_AXES
        case AMotionEvent.ACTION_MOVE, AMotionEvent.ACTION_HOVER_MOVE:
            axesToProcess = AVelocityTracker.PLANAR_AXES
        case AMotionEvent.ACTION_POINTER_UP, AMotionEvent.ACTION_UP:
            if actionMasked == AMotionEvent.ACTION_POINTER_UP
                && (event.getFlags() & AMotionEvent.FLAG_CANCELED) != 0 {
                clearPointer(event.getPointerId(event.actionIndex))
                return
            }
            // Continue to ACTION_UP to ensure that the POINTER_STOPPED logic is triggered.
            let delaySinceLastEvent = event.eventTimeNanos - mLastEventTime
            if delaySinceLastEvent > AVelocityTracker.ASSUME_POINTER_STOPPED_TIME {
                // We have not received any movements for too long.  Assume that all pointers
                // have stopped.
                for axis in AVelocityTracker.PLANAR_AXES {
                    mConfiguredStrategies[axis] = nil
                }
            }
            // These actions because they do not convey any new information about
            // pointer movement. We also want to preserve the last known velocity of the pointers.
            return
        case AMotionEvent.ACTION_CANCEL:
            clear()
            return
        default:
            // Ignore all other actions (ACTION_SCROLL feeds AXIS_SCROLL, which touch screens never produce).
            return
        }

        let historySize = event.historySize
        for h in 0...historySize {
            let eventTime = h == historySize ? event.eventTimeNanos : event.getHistoricalEventTimeNanos(h)
            for i in 0..<event.pointerCount {
                let pointerId = event.getPointerId(i)
                for axis in axesToProcess {
                    let position: Float
                    if h == historySize {
                        position = axis == AVelocityTracker.AXIS_X ? event.getX(i) : event.getY(i)
                    } else {
                        position = axis == AVelocityTracker.AXIS_X ? event.getHistoricalX(i, h) : event.getHistoricalY(i, h)
                    }
                    addMovement(eventTime, pointerId, axis, position)
                }
            }
        }
    }

    /// computeCurrentVelocity(units): units per second for 1000; no maximum (Float.MAX_VALUE).
    func computeCurrentVelocity(_ units: Int) {
        computeCurrentVelocity(units, Float.greatestFiniteMagnitude)
    }

    /// computeCurrentVelocity(units, maxVelocity): every axis and tracked pointer, clamped to ±maxVelocity.
    func computeCurrentVelocity(_ units: Int, _ maxVelocity: Float) {
        var computed: [Int: [Int: Float]] = [:]
        for axis in mConfiguredStrategies.keys.sorted() {
            let strategy = mConfiguredStrategies[axis]!
            var copyIdBits = mCurrentPointerIdBits
            while copyIdBits != 0 {
                let id = copyIdBits.trailingZeroBitCount
                copyIdBits &= ~(UInt32(1) << UInt32(id))
                if let velocity = strategy.getVelocity(id) {
                    // std::clamp(*velocity * units / 1000, -maxVelocity, maxVelocity)
                    let scaled = velocity * Float(units) / Float(1000)
                    let adjustedVelocity = scaled < -maxVelocity ? -maxVelocity : (maxVelocity < scaled ? maxVelocity : scaled)
                    computed[axis, default: [:]][id] = adjustedVelocity
                }
            }
        }
        mComputedVelocity = computed
    }

    func getXVelocity() -> Float {
        return getXVelocity(AVelocityTracker.ACTIVE_POINTER_ID)
    }

    func getYVelocity() -> Float {
        return getYVelocity(AVelocityTracker.ACTIVE_POINTER_ID)
    }

    func getXVelocity(_ id: Int) -> Float {
        return getAxisVelocity(AVelocityTracker.AXIS_X, id)
    }

    func getYVelocity(_ id: Int) -> Float {
        return getAxisVelocity(AVelocityTracker.AXIS_Y, id)
    }

    /// Kotlin property syntax `velocityTracker.xVelocity` / `yVelocity`.
    var xVelocity: Float { return getXVelocity() }
    var yVelocity: Float { return getYVelocity() }

    func getAxisVelocity(_ axis: Int) -> Float {
        return getAxisVelocity(axis, AVelocityTracker.ACTIVE_POINTER_ID)
    }

    /// The velocity of the last computeCurrentVelocity for this axis and pointer (ACTIVE_POINTER_ID = the active
    /// pointer), or 0 when there was none.
    func getAxisVelocity(_ axis: Int, _ id: Int) -> Float {
        var pointerId = id
        if pointerId == AVelocityTracker.ACTIVE_POINTER_ID {
            pointerId = mActivePointerId ?? -1
        }
        return mComputedVelocity[axis]?[pointerId] ?? 0
    }

    // MARK: - LeastSquaresVelocityTrackerStrategy (AccumulatingVelocityTrackerStrategy, unweighted)

    private final class LeastSquaresVelocityTrackerStrategy {
        /// Sample horizon: 100 ms.
        static let HORIZON: Int64 = 100 * 1_000_000
        /// Number of samples to keep.
        static let HISTORY_SIZE = 20
        static let SECONDS_PER_NANO: Float = 1E-9

        private let mDegree: Int
        /// Per pointer: chronological samples (the native RingBuffer, oldest first).
        private var mMovements: [Int: [(eventTime: Int64, position: Float)]] = [:]

        init(_ degree: Int) {
            mDegree = degree
        }

        func clearPointer(_ pointerId: Int) {
            mMovements[pointerId] = nil
        }

        func addMovement(_ eventTime: Int64, _ pointerId: Int, _ position: Float) {
            var movements = mMovements[pointerId] ?? []
            if let last = movements.last, last.eventTime == eventTime {
                // When ACTION_POINTER_DOWN happens, we will first receive ACTION_MOVE with the coordinates
                // of the existing pointers, and then ACTION_POINTER_DOWN with the coordinates that include
                // the new pointer. If the eventtimes for both events are identical, just update the data
                // for this time (i.e. pop out the last element, and insert the updated movement).
                movements.removeLast()
            }

            movements.append((eventTime: eventTime, position: position))
            if movements.count > LeastSquaresVelocityTrackerStrategy.HISTORY_SIZE {
                movements.removeFirst()   // the full ring buffer overwrites its oldest sample
            }

            // Clear movements that do not fall within `HORIZON` of the latest movement.
            while eventTime - movements[0].eventTime > LeastSquaresVelocityTrackerStrategy.HORIZON {
                movements.removeFirst()
            }
            mMovements[pointerId] = movements
        }

        func getVelocity(_ pointerId: Int) -> Float? {
            guard let movements = mMovements[pointerId] else {
                return nil   // no data
            }
            let size = movements.count
            if size == 0 {
                return nil   // no data
            }

            var degree = mDegree
            if degree > size - 1 {
                degree = size - 1
            }

            if degree <= 0 {
                return nil
            }

            if degree == 2 {
                // Optimize unweighted, quadratic polynomial fit
                return solveUnweightedLeastSquaresDeg2(movements)
            }

            // Iterate over movement samples in reverse time order and collect samples.
            var positions: [Float] = []
            var w: [Float] = []
            var time: [Float] = []

            let newestMovement = movements[size - 1]
            for i in stride(from: size - 1, through: 0, by: -1) {
                let movement = movements[i]
                let age = newestMovement.eventTime - movement.eventTime
                positions.append(movement.position)
                w.append(1.0)   // Weighting::NONE
                time.append(Float(-age) * Float(0.000000001))
            }

            // General case for an Nth degree polynomial fit
            if let coeffs = LeastSquaresVelocityTrackerStrategy.solveLeastSquares(time, positions, w, degree + 1) {
                return coeffs[1]
            }
            return nil
        }

        /// Optimized unweighted second-order least squares fit: y = a·x² + b·x + c with x = the age (seconds,
        /// negative) of each movement; returns b, the velocity at the newest movement.
        private func solveUnweightedLeastSquaresDeg2(_ movements: [(eventTime: Int64, position: Float)]) -> Float? {
            var sxi: Float = 0, sxiyi: Float = 0, syi: Float = 0, sxi2: Float = 0, sxi3: Float = 0
            var sxi2yi: Float = 0, sxi4: Float = 0

            let count = movements.count
            let newestMovement = movements[count - 1]
            for i in 0..<count {
                let movement = movements[i]
                let age = newestMovement.eventTime - movement.eventTime
                let xi: Float = Float(-age) * LeastSquaresVelocityTrackerStrategy.SECONDS_PER_NANO
                let yi: Float = movement.position

                let xi2: Float = xi * xi
                let xi3: Float = xi2 * xi
                let xi4: Float = xi3 * xi
                let xiyi: Float = xi * yi
                let xi2yi: Float = xi2 * yi

                sxi += xi
                sxi2 += xi2
                sxiyi += xiyi
                sxi2yi += xi2yi
                syi += yi
                sxi3 += xi3
                sxi4 += xi4
            }

            let n = Float(count)
            let Sxx: Float = sxi2 - sxi * sxi / n
            let Sxy: Float = sxiyi - sxi * syi / n
            let Sxx2: Float = sxi3 - sxi * sxi2 / n
            let Sx2y: Float = sxi2yi - sxi2 * syi / n
            let Sx2x2: Float = sxi4 - sxi2 * sxi2 / n

            let denominator: Float = Sxx * Sx2x2 - Sxx2 * Sxx2
            if denominator == 0 {
                return nil
            }

            return (Sxy * Sx2x2 - Sx2y * Sxx2) / denominator
        }

        private static func vectorDot(_ a: [Float], _ b: [Float], _ m: Int) -> Float {
            var r: Float = 0
            for i in 0..<m {
                r += a[i] * b[i]
            }
            return r
        }

        private static func vectorNorm(_ a: [Float], _ m: Int) -> Float {
            var r: Float = 0
            for i in 0..<m {
                let t = a[i]
                r += t * t
            }
            return r.squareRoot()
        }

        /// Linear least squares (Gram-Schmidt QR of the weighted Vandermonde matrix), n coefficients; nil when the
        /// columns are linearly dependent.
        private static func solveLeastSquares(_ x: [Float], _ y: [Float], _ w: [Float], _ n: Int) -> [Float]? {
            let m = x.count

            // Expand the X vector to a matrix A, pre-multiplied by the weights.
            var a = [[Float]](repeating: [Float](repeating: 0, count: m), count: n)   // column-major order
            for h in 0..<m {
                a[0][h] = w[h]
                for i in stride(from: 1, to: n, by: 1) {
                    a[i][h] = a[i - 1][h] * x[h]
                }
            }

            // Apply the Gram-Schmidt process to A to obtain its QR decomposition.
            var q = [[Float]](repeating: [Float](repeating: 0, count: m), count: n)   // orthonormal basis
            var r = [[Float]](repeating: [Float](repeating: 0, count: n), count: n)   // upper triangular, row-major
            for j in 0..<n {
                for h in 0..<m {
                    q[j][h] = a[j][h]
                }
                for i in 0..<j {
                    let dot = vectorDot(q[j], q[i], m)
                    for h in 0..<m {
                        q[j][h] -= dot * q[i][h]
                    }
                }

                let norm = vectorNorm(q[j], m)
                if norm < 0.000001 {
                    // vectors are linearly dependent or zero so no solution
                    return nil
                }

                let invNorm: Float = 1.0 / norm
                for h in 0..<m {
                    q[j][h] *= invNorm
                }
                for i in 0..<n {
                    r[j][i] = i < j ? 0 : vectorDot(q[j], a[i], m)
                }
            }

            // Solve R B = Qt W Y to find B.  This is easy because R is upper triangular.
            // We just work from bottom-right to top-left calculating B's coefficients.
            var wy = [Float](repeating: 0, count: m)
            for h in 0..<m {
                wy[h] = y[h] * w[h]
            }
            var outB = [Float](repeating: 0, count: n)
            var i = n
            while i != 0 {
                i -= 1
                outB[i] = vectorDot(q[i], wy, m)
                var j = n - 1
                while j > i {
                    outB[i] -= r[i][j] * outB[j]
                    j -= 1
                }
                outB[i] /= r[i][i]
            }
            return outB
        }
    }
}
