import Foundation

// Android cross/CrossPaddlePose.kt (MinikCrossPong d0bed3b; unchanged at dd94c09).

/// Contact is an animation excursion, never a new footwork/resting position: after the impact hold (0.07 s, at most the stroke's
/// end) the drawn paddle eases (smoothstep) from the contact point and height back to the resting paddle by the stroke's end.
enum CrossPaddlePose {
    static func at(_ stroke: MPStroke, _ rest: MPPoint) -> (point: MPPoint, height: Double) {
        if !stroke.active || !stroke.contacted { return (rest, 0) }
        let holdEnd = min(stroke.impactAt + 0.07, stroke.total)
        let t = ((stroke.age - holdEnd) / max(0.001, stroke.total - holdEnd)).mpClamp(0, 1)
        let eased = t * t * (3 - 2 * t)
        return (stroke.point * (1 - eased) + rest * eased, stroke.height * (1 - eased))
    }
}
