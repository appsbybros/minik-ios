import CoreGraphics
import Foundation

// android.view.MotionEvent (touch-screen subset), VIEW-API "Views".
//
// Coordinates are Android pixels (Float), view-relative after dispatch (offsetLocation/transform), exactly as the
// ViewGroup dispatch of Android produces them. rawX/rawY stay in window pixels. Times: eventTime/downTime are
// SystemClock.uptimeMillis values; eventTimeNanos is the System.nanoTime domain (UITouch timestamps share it).
// Pointer indices are ordered by pointer id (Android's InputReader order); ids are small integers from 0.

final class AMotionEvent {
    // MARK: actions (MotionEvent constants)
    static let ACTION_DOWN = 0
    static let ACTION_UP = 1
    static let ACTION_MOVE = 2
    static let ACTION_CANCEL = 3
    static let ACTION_OUTSIDE = 4
    static let ACTION_POINTER_DOWN = 5
    static let ACTION_POINTER_UP = 6
    static let ACTION_HOVER_MOVE = 7
    static let ACTION_SCROLL = 8
    static let ACTION_HOVER_ENTER = 9
    static let ACTION_HOVER_EXIT = 10
    static let ACTION_BUTTON_PRESS = 11
    static let ACTION_BUTTON_RELEASE = 12
    static let ACTION_MASK = 0xff
    static let ACTION_POINTER_INDEX_MASK = 0xff00
    static let ACTION_POINTER_INDEX_SHIFT = 8

    // MARK: flags
    static let FLAG_WINDOW_IS_OBSCURED = 0x1
    static let FLAG_WINDOW_IS_PARTIALLY_OBSCURED = 0x2
    static let FLAG_IS_GENERATED_GESTURE = 0x8
    static let FLAG_CANCELED = 0x20

    // MARK: misc constants
    static let INVALID_POINTER_ID = -1
    static let TOOL_TYPE_UNKNOWN = 0
    static let TOOL_TYPE_FINGER = 1
    static let TOOL_TYPE_STYLUS = 2
    static let TOOL_TYPE_MOUSE = 3
    static let CLASSIFICATION_NONE = 0
    static let CLASSIFICATION_AMBIGUOUS_GESTURE = 1
    static let CLASSIFICATION_DEEP_PRESS = 2
    static let AXIS_X = 0
    static let AXIS_Y = 1
    static let EDGE_TOP = 0x1
    static let EDGE_BOTTOM = 0x2
    static let EDGE_LEFT = 0x4
    static let EDGE_RIGHT = 0x8
    /// android.view.InputDevice sources used by the framework code ported here.
    static let SOURCE_CLASS_POINTER = 0x2
    static let SOURCE_TOUCHSCREEN = 0x1002
    static let SOURCE_MOUSE = 0x2002

    // MARK: storage
    private var mAction: Int
    /// SystemClock.uptimeMillis of the gesture's first ACTION_DOWN.
    private(set) var downTime: Int64
    /// System.nanoTime domain; `eventTime` is derived from it like Android (nanos / 1_000_000).
    private(set) var eventTimeNanos: Int64
    private(set) var flags: Int = 0
    var metaState: Int = 0
    var buttonState: Int = 0
    var edgeFlags: Int = 0
    var source: Int = AMotionEvent.SOURCE_TOUCHSCREEN
    /// MotionEvent.getClassification(): iOS has no ambiguous/deep-press classification.
    private(set) var classification: Int = AMotionEvent.CLASSIFICATION_NONE

    private var ids: [Int]
    private var xs: [Float]
    private var ys: [Float]
    private var rawXs: [Float]
    private var rawYs: [Float]
    private var pressures: [Float]
    private var sizes: [Float]
    /// Historical samples, oldest first. Each sample holds one coordinate per pointer (same order as `ids`).
    private var historyTimesNanos: [Int64] = []
    private var historyXs: [[Float]] = []
    private var historyYs: [[Float]] = []

    private init(downTime: Int64, eventTimeNanos: Int64, action: Int, ids: [Int], xs: [Float], ys: [Float],
                 rawXs: [Float], rawYs: [Float], pressures: [Float], sizes: [Float]) {
        self.downTime = downTime
        self.eventTimeNanos = eventTimeNanos
        self.mAction = action
        self.ids = ids
        self.xs = xs
        self.ys = ys
        self.rawXs = rawXs
        self.rawYs = rawYs
        self.pressures = pressures
        self.sizes = sizes
    }

    /// AndroidKit factory used by AViewRoot: one event with all active pointers, coordinates in root pixels.
    static func obtainTouch(downTime: Int64, eventTimeNanos: Int64, action: Int, pointerIds: [Int],
                            xs: [Float], ys: [Float], rawXs: [Float], rawYs: [Float],
                            pressures: [Float]? = nil) -> AMotionEvent {
        let n = pointerIds.count
        return AMotionEvent(downTime: downTime, eventTimeNanos: eventTimeNanos, action: action, ids: pointerIds,
                            xs: xs, ys: ys, rawXs: rawXs, rawYs: rawYs,
                            pressures: pressures ?? [Float](repeating: 1, count: n),
                            sizes: [Float](repeating: 0, count: n))
    }

    /// AndroidKit: appends one historical sample (oldest first), as Android batches samples between frames.
    func addHistorySample(eventTimeNanos t: Int64, xs hx: [Float], ys hy: [Float]) {
        precondition(hx.count == ids.count && hy.count == ids.count, "history sample pointer count mismatch")
        historyTimesNanos.append(t)
        historyXs.append(hx)
        historyYs.append(hy)
    }

    // MARK: obtain / recycle

    /// MotionEvent.obtain(MotionEvent): a full copy.
    static func obtain(_ e: AMotionEvent) -> AMotionEvent {
        let c = AMotionEvent(downTime: e.downTime, eventTimeNanos: e.eventTimeNanos, action: e.mAction, ids: e.ids,
                             xs: e.xs, ys: e.ys, rawXs: e.rawXs, rawYs: e.rawYs, pressures: e.pressures, sizes: e.sizes)
        c.flags = e.flags
        c.metaState = e.metaState
        c.buttonState = e.buttonState
        c.edgeFlags = e.edgeFlags
        c.source = e.source
        c.classification = e.classification
        c.historyTimesNanos = e.historyTimesNanos
        c.historyXs = e.historyXs
        c.historyYs = e.historyYs
        return c
    }

    /// MotionEvent.obtain(long downTime, long eventTime, int action, float x, float y, int metaState).
    static func obtain(_ downTime: Int64, _ eventTime: Int64, _ action: Int, _ x: Float, _ y: Float,
                       _ metaState: Int) -> AMotionEvent {
        let e = AMotionEvent(downTime: downTime, eventTimeNanos: eventTime &* 1_000_000, action: action, ids: [0],
                             xs: [x], ys: [y], rawXs: [x], rawYs: [y], pressures: [1], sizes: [1])
        e.metaState = metaState
        return e
    }

    /// MotionEvent.obtainNoHistory(MotionEvent).
    static func obtainNoHistory(_ e: AMotionEvent) -> AMotionEvent {
        let c = obtain(e)
        c.historyTimesNanos = []
        c.historyXs = []
        c.historyYs = []
        return c
    }

    /// Android pools MotionEvents; here recycling is a no-op.
    func recycle() {}

    // MARK: action

    var action: Int { mAction }
    func getAction() -> Int { mAction }
    func setAction(_ action: Int) { mAction = action }
    var actionMasked: Int { mAction & AMotionEvent.ACTION_MASK }
    func getActionMasked() -> Int { actionMasked }
    var actionIndex: Int { (mAction & AMotionEvent.ACTION_POINTER_INDEX_MASK) >> AMotionEvent.ACTION_POINTER_INDEX_SHIFT }
    func getActionIndex() -> Int { actionIndex }

    // MARK: time

    var eventTime: Int64 { eventTimeNanos / 1_000_000 }
    func getEventTime() -> Int64 { eventTime }
    func getEventTimeNanos() -> Int64 { eventTimeNanos }
    func getDownTime() -> Int64 { downTime }
    func setDownTime(_ downTime: Int64) { self.downTime = downTime }

    // MARK: pointers

    var pointerCount: Int { ids.count }
    func getPointerCount() -> Int { ids.count }
    func getPointerId(_ pointerIndex: Int) -> Int { ids[pointerIndex] }
    func findPointerIndex(_ pointerId: Int) -> Int { ids.firstIndex(of: pointerId) ?? -1 }
    func getToolType(_ pointerIndex: Int) -> Int { _ = ids[pointerIndex]; return AMotionEvent.TOOL_TYPE_FINGER }
    /// Bit set of the pointer ids in this event (MotionEvent.getPointerIdBits, hidden API).
    var pointerIdBits: Int {
        var bits = 0
        for id in ids { bits |= 1 << id }
        return bits
    }

    var x: Float { xs[0] }
    var y: Float { ys[0] }
    func getX() -> Float { xs[0] }
    func getY() -> Float { ys[0] }
    func getX(_ pointerIndex: Int) -> Float { xs[pointerIndex] }
    func getY(_ pointerIndex: Int) -> Float { ys[pointerIndex] }
    var rawX: Float { rawXs[0] }
    var rawY: Float { rawYs[0] }
    func getRawX() -> Float { rawXs[0] }
    func getRawY() -> Float { rawYs[0] }
    func getRawX(_ pointerIndex: Int) -> Float { rawXs[pointerIndex] }
    func getRawY(_ pointerIndex: Int) -> Float { rawYs[pointerIndex] }
    var pressure: Float { pressures[0] }
    func getPressure() -> Float { pressures[0] }
    func getPressure(_ pointerIndex: Int) -> Float { pressures[pointerIndex] }
    var size: Float { sizes[0] }
    func getSize(_ pointerIndex: Int) -> Float { sizes[pointerIndex] }
    func getAxisValue(_ axis: Int) -> Float { getAxisValue(axis, 0) }
    func getAxisValue(_ axis: Int, _ pointerIndex: Int) -> Float {
        switch axis {
        case AMotionEvent.AXIS_X: return xs[pointerIndex]
        case AMotionEvent.AXIS_Y: return ys[pointerIndex]
        default: return 0
        }
    }
    func isFromSource(_ source: Int) -> Bool { (self.source & source) == source }
    func getFlags() -> Int { flags }
    /// MotionEvent.setFlags (hidden API).
    func setFlags(_ flags: Int) { self.flags = flags }

    // MARK: history

    var historySize: Int { historyTimesNanos.count }
    func getHistorySize() -> Int { historyTimesNanos.count }
    func getHistoricalEventTime(_ pos: Int) -> Int64 { historyTimesNanos[pos] / 1_000_000 }
    func getHistoricalEventTimeNanos(_ pos: Int) -> Int64 { historyTimesNanos[pos] }
    func getHistoricalX(_ pos: Int) -> Float { historyXs[pos][0] }
    func getHistoricalY(_ pos: Int) -> Float { historyYs[pos][0] }
    func getHistoricalX(_ pointerIndex: Int, _ pos: Int) -> Float { historyXs[pos][pointerIndex] }
    func getHistoricalY(_ pointerIndex: Int, _ pos: Int) -> Float { historyYs[pos][pointerIndex] }
    /// Native getHistoricalAxisValue(axis, i, h) where h == historySize means the current sample.
    func historicalOrCurrentAxisValue(_ axis: Int, _ pointerIndex: Int, _ h: Int) -> Float {
        if h == historyTimesNanos.count { return getAxisValue(axis, pointerIndex) }
        return axis == AMotionEvent.AXIS_X ? historyXs[h][pointerIndex] : historyYs[h][pointerIndex]
    }
    func historicalOrCurrentEventTimeNanos(_ h: Int) -> Int64 {
        h == historyTimesNanos.count ? eventTimeNanos : historyTimesNanos[h]
    }

    // MARK: coordinate changes

    /// MotionEvent.offsetLocation: moves every pointer (and the history) by (dx, dy). Raw coordinates stay.
    func offsetLocation(_ deltaX: Float, _ deltaY: Float) {
        if deltaX == 0 && deltaY == 0 { return }
        for i in 0..<xs.count {
            xs[i] += deltaX
            ys[i] += deltaY
        }
        for h in 0..<historyXs.count {
            for i in 0..<historyXs[h].count {
                historyXs[h][i] += deltaX
                historyYs[h][i] += deltaY
            }
        }
    }

    /// MotionEvent.setLocation: offsetLocation(x - getX(), y - getY()).
    func setLocation(_ x: Float, _ y: Float) {
        let oldX = getX()
        let oldY = getY()
        offsetLocation(x - oldX, y - oldY)
    }

    /// MotionEvent.transform(Matrix) with the matrix given as an affine transform in pixels.
    func transform(_ t: CGAffineTransform) {
        func map(_ x: Float, _ y: Float) -> (Float, Float) {
            let px = Double(x), py = Double(y)
            let nx = Double(t.a) * px + Double(t.c) * py + Double(t.tx)
            let ny = Double(t.b) * px + Double(t.d) * py + Double(t.ty)
            return (Float(nx), Float(ny))
        }
        for i in 0..<xs.count {
            let (nx, ny) = map(xs[i], ys[i])
            xs[i] = nx
            ys[i] = ny
        }
        for h in 0..<historyXs.count {
            for i in 0..<historyXs[h].count {
                let (nx, ny) = map(historyXs[h][i], historyYs[h][i])
                historyXs[h][i] = nx
                historyYs[h][i] = ny
            }
        }
    }

    /// MotionEvent.split(int idBits) (hidden API used by ViewGroup): keeps the pointers in `idBits` and rewrites
    /// the action exactly like Android (POINTER_DOWN/UP of a kept pointer become DOWN/UP when it is alone,
    /// an unrelated POINTER_DOWN/UP becomes MOVE).
    func split(_ idBits: Int) -> AMotionEvent {
        let oldActionMasked = mAction & AMotionEvent.ACTION_MASK
        let oldActionPointerIndex = (mAction & AMotionEvent.ACTION_POINTER_INDEX_MASK) >> AMotionEvent.ACTION_POINTER_INDEX_SHIFT
        var newActionPointerIndex = -1
        var map: [Int] = []
        for i in 0..<ids.count {
            if ((1 << ids[i]) & idBits) != 0 {
                if i == oldActionPointerIndex {
                    newActionPointerIndex = map.count
                }
                map.append(i)
            }
        }
        precondition(!map.isEmpty, "idBits did not match any ids in the event")
        let newAction: Int
        if oldActionMasked == AMotionEvent.ACTION_POINTER_DOWN || oldActionMasked == AMotionEvent.ACTION_POINTER_UP {
            if newActionPointerIndex < 0 {
                newAction = AMotionEvent.ACTION_MOVE
            } else if map.count == 1 {
                newAction = oldActionMasked == AMotionEvent.ACTION_POINTER_DOWN
                    ? AMotionEvent.ACTION_DOWN
                    : ((flags & AMotionEvent.FLAG_CANCELED) == 0 ? AMotionEvent.ACTION_UP : AMotionEvent.ACTION_CANCEL)
            } else {
                newAction = oldActionMasked | (newActionPointerIndex << AMotionEvent.ACTION_POINTER_INDEX_SHIFT)
            }
        } else {
            newAction = mAction
        }
        let ev = AMotionEvent(downTime: downTime, eventTimeNanos: eventTimeNanos, action: newAction,
                              ids: map.map { ids[$0] }, xs: map.map { xs[$0] }, ys: map.map { ys[$0] },
                              rawXs: map.map { rawXs[$0] }, rawYs: map.map { rawYs[$0] },
                              pressures: map.map { pressures[$0] }, sizes: map.map { sizes[$0] })
        ev.flags = flags
        ev.metaState = metaState
        ev.buttonState = buttonState
        ev.edgeFlags = edgeFlags
        ev.source = source
        ev.classification = classification
        ev.historyTimesNanos = historyTimesNanos
        ev.historyXs = historyXs.map { sample in map.map { sample[$0] } }
        ev.historyYs = historyYs.map { sample in map.map { sample[$0] } }
        return ev
    }

    // MARK: debugging

    static func actionToString(_ action: Int) -> String {
        switch action {
        case ACTION_DOWN: return "ACTION_DOWN"
        case ACTION_UP: return "ACTION_UP"
        case ACTION_CANCEL: return "ACTION_CANCEL"
        case ACTION_OUTSIDE: return "ACTION_OUTSIDE"
        case ACTION_MOVE: return "ACTION_MOVE"
        case ACTION_HOVER_MOVE: return "ACTION_HOVER_MOVE"
        case ACTION_SCROLL: return "ACTION_SCROLL"
        case ACTION_HOVER_ENTER: return "ACTION_HOVER_ENTER"
        case ACTION_HOVER_EXIT: return "ACTION_HOVER_EXIT"
        case ACTION_BUTTON_PRESS: return "ACTION_BUTTON_PRESS"
        case ACTION_BUTTON_RELEASE: return "ACTION_BUTTON_RELEASE"
        default:
            let index = (action & ACTION_POINTER_INDEX_MASK) >> ACTION_POINTER_INDEX_SHIFT
            switch action & ACTION_MASK {
            case ACTION_POINTER_DOWN: return "ACTION_POINTER_DOWN(\(index))"
            case ACTION_POINTER_UP: return "ACTION_POINTER_UP(\(index))"
            default: return String(action)
            }
        }
    }

    var description: String {
        var s = "MotionEvent { action=\(AMotionEvent.actionToString(mAction))"
        for i in 0..<ids.count {
            s += ", id[\(i)]=\(ids[i]), x[\(i)]=\(xs[i]), y[\(i)]=\(ys[i])"
        }
        s += ", eventTime=\(eventTime), downTime=\(downTime), pointerCount=\(ids.count), historySize=\(historySize) }"
        return s
    }
}
