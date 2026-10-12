import Foundation

/// Port of Android core/Gestures.kt. World-object hit testing stays in the view; recognition
/// and pointer ownership are pure: locked pointer targets and a delayed single/double tap.
enum TouchKind {
    case body, arc, balloon, opponent, world
}

struct TouchTarget: Equatable {
    var kind: TouchKind
    var balloon: Int = -1
    var questionId: String = ""
    var actorId: String = ""
}

struct TouchAction {
    var type: String
    var pointer: Int
    var target: TouchTarget
    var x: Double
    var y: Double
    var dx: Double = 0
    var dy: Double = 0
}

final class Gestures {
    let window: Int64
    let slop: Double
    let doubleDistance: Double
    private let emit: (TouchAction) -> Void

    private struct Pointer {
        let target: TouchTarget
        let x: Double
        let y: Double
        var lastX: Double
        var lastY: Double
        var dragged: Bool
        var isDouble: Bool
    }

    private struct Pending {
        let target: TouchTarget
        let x: Double
        let y: Double
        let at: Int64
        let pointer: Int
    }

    /// Insertion-ordered like Kotlin's `mutableMapOf`.
    private var active: [Int: Pointer] = [:]
    private var activeOrder: [Int] = []
    private var pending: Pending? = nil

    init(window: Int64 = 220, slop: Double = 11.0, doubleDistance: Double = 38.0, emit: @escaping (TouchAction) -> Void) {
        self.window = window
        self.slop = slop
        self.doubleDistance = doubleDistance
        self.emit = emit
    }

    var pointerCount: Int { return active.count }

    func down(_ id: Int, _ x: Double, _ y: Double, _ now: Int64, _ target: TouchTarget) {
        flush(now)
        var isDouble = false
        if let p = pending {
            isDouble = now - p.at <= window && hypot(x - p.x, y - p.y) <= doubleDistance && active.isEmpty
        }
        if isDouble { pending = nil }
        if active[id] == nil { activeOrder.append(id) }
        active[id] = Pointer(target: target, x: x, y: y, lastX: x, lastY: y, dragged: false, isDouble: isDouble)
        emit(TouchAction(type: "press", pointer: id, target: target, x: x, y: y))
    }

    func move(_ id: Int, _ x: Double, _ y: Double) {
        guard var p = active[id] else { return }
        if hypot(x - p.x, y - p.y) > slop { p.dragged = true }
        active[id] = p
        if p.dragged && (p.target.kind == .body || p.target.kind == .arc) {
            emit(TouchAction(type: "drag", pointer: id, target: p.target, x: x, y: y, dx: x - p.x, dy: y - p.y))
        }
        if var latest = active[id] {
            latest.lastX = x
            latest.lastY = y
            active[id] = latest
        }
    }

    func up(_ id: Int, _ x: Double, _ y: Double, _ now: Int64) {
        guard let p = active.removeValue(forKey: id) else { return }
        activeOrder.removeAll { $0 == id }
        if p.dragged {
            // The drag length tells a released Hard-throw swipe from a cancelled pointer.
            emit(TouchAction(type: "end", pointer: id, target: p.target, x: x, y: y, dx: hypot(x - p.x, y - p.y)))
            return
        }
        if p.isDouble {
            emit(TouchAction(type: "double", pointer: id, target: p.target, x: x, y: y))
            return
        }
        if let old = pending {
            emit(TouchAction(type: "tap", pointer: old.pointer, target: old.target, x: old.x, y: old.y))
        }
        pending = Pending(target: p.target, x: x, y: y, at: now, pointer: id)
    }

    func flush(_ now: Int64) {
        guard let p = pending else { return }
        if now - p.at >= window {
            pending = nil
            emit(TouchAction(type: "tap", pointer: p.pointer, target: p.target, x: p.x, y: p.y))
        }
    }

    func cancel() {
        let order = activeOrder
        let pointers = active
        for id in order {
            guard let p = pointers[id] else { continue }
            emit(TouchAction(type: "end", pointer: id, target: p.target, x: p.lastX, y: p.lastY))
        }
        active.removeAll()
        activeOrder.removeAll()
        pending = nil
    }
}
