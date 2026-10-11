import Foundation

enum LanguageSoccerShotPhase: Equatable, Sendable {
    case idle
    case dragging(ballID: SoccerBallID)
    case launched(shotID: UUID, ballID: SoccerBallID)
    case inFlight(shotID: UUID, ballID: SoccerBallID)
    case rebounding(shotID: UUID, ballID: SoccerBallID)
    case finalized(shotID: UUID, ballID: SoccerBallID, outcome: GameOutcome)
}

struct LanguageSoccerShotLifecycle: Equatable, Sendable {
    private(set) var phase: LanguageSoccerShotPhase = .idle

    var acceptsNewDrag: Bool { phase == .idle }

    mutating func beginDragging(ballID: SoccerBallID) -> Bool {
        guard acceptsNewDrag else { return false }
        phase = .dragging(ballID: ballID)
        return true
    }

    mutating func cancelDrag(ballID: SoccerBallID) {
        guard phase == .dragging(ballID: ballID) else { return }
        phase = .idle
    }

    mutating func launch(ballID: SoccerBallID, shotID: UUID = UUID()) -> UUID? {
        guard phase == .dragging(ballID: ballID) else { return nil }
        phase = .launched(shotID: shotID, ballID: ballID)
        return shotID
    }

    mutating func beginFlight(shotID: UUID) -> Bool {
        guard case .launched(let activeID, let ballID) = phase,
              activeID == shotID else { return false }
        phase = .inFlight(shotID: shotID, ballID: ballID)
        return true
    }

    mutating func beginRebound(shotID: UUID) -> Bool {
        guard case .inFlight(let activeID, let ballID) = phase,
              activeID == shotID else { return false }
        phase = .rebounding(shotID: shotID, ballID: ballID)
        return true
    }

    mutating func finalize(shotID: UUID, outcome: GameOutcome) -> Bool {
        let ballID: SoccerBallID
        switch phase {
        case .inFlight(let activeID, let activeBallID),
             .rebounding(let activeID, let activeBallID):
            guard activeID == shotID else { return false }
            ballID = activeBallID
        default:
            return false
        }
        phase = .finalized(shotID: shotID, ballID: ballID, outcome: outcome)
        return true
    }

    mutating func resetAfterFinalized(shotID: UUID) -> Bool {
        guard case .finalized(let activeID, _, _) = phase,
              activeID == shotID else { return false }
        phase = .idle
        return true
    }

    mutating func cancelAll() {
        phase = .idle
    }
}

/// Android's LettersSoccerGame keeps no input lock between kicks: the next letter
/// can be dragged as soon as one is kicked, and up to three balls fly at once.
/// On iOS the finger's lifecycle hands each launched kick its own lifecycle,
/// which flies, lands and settles on its own.
extension LanguageSoccerShotLifecycle {
    /// Kicked and still on its way: launched, flying or bouncing back.
    var isAirborne: Bool {
        switch phase {
        case .launched, .inFlight, .rebounding:
            return true
        case .idle, .dragging, .finalized:
            return false
        }
    }

    /// How the shot ended, once its ball has landed.
    var landedOutcome: GameOutcome? {
        guard case .finalized(_, _, let outcome) = phase else { return nil }
        return outcome
    }
}

struct LanguageSoccerPoint: Equatable, Sendable {
    var x: Double
    var y: Double
}

struct LanguageSoccerVector: Equatable, Sendable {
    var dx: Double
    var dy: Double

    var magnitude: Double { (dx * dx + dy * dy).squareRoot() }

    func normalizedTowardGoal(minimumVerticalComponent: Double = 0.20) -> Self {
        let fallback = Self(dx: 0, dy: -1)
        guard magnitude > 0.000_001 else { return fallback }
        var unit = Self(dx: dx / magnitude, dy: -abs(dy / magnitude))
        if abs(unit.dy) < minimumVerticalComponent {
            unit.dy = -minimumVerticalComponent
            let horizontal = (1 - minimumVerticalComponent * minimumVerticalComponent).squareRoot()
            unit.dx = unit.dx < 0 ? -horizontal : horizontal
        }
        return unit
    }
}

struct LanguageSoccerRect: Equatable, Sendable {
    var minX: Double
    var minY: Double
    var width: Double
    var height: Double

    var maxX: Double { minX + width }
    var maxY: Double { minY + height }

    func expanded(by amount: Double) -> Self {
        Self(
            minX: minX - amount,
            minY: minY - amount,
            width: width + amount * 2,
            height: height + amount * 2
        )
    }
}

enum LanguageSoccerCollision: Equatable, Sendable {
    case keeper
    case leftPost
    case rightPost
    case crossbar
}

struct LanguageSoccerShotResolution: Equatable, Sendable {
    let outcome: GameOutcome
    let impactPoint: LanguageSoccerPoint
    let reboundPoint: LanguageSoccerPoint?
    let collision: LanguageSoccerCollision?
    let durationSeconds: Double
}

struct LanguageSoccerShotGeometry: Equatable, Sendable {
    let field: LanguageSoccerRect
    let goal: LanguageSoccerRect
    let keeper: LanguageSoccerRect
    let ballRadius: Double
    let postThickness: Double

    func resolve(start: LanguageSoccerPoint, dragVelocity: LanguageSoccerVector) -> LanguageSoccerShotResolution {
        let direction = dragVelocity.normalizedTowardGoal()
        let targetY = goal.minY - 40
        let verticalDistance = max(1, start.y - targetY)
        let travelDistance = verticalDistance / max(0.20, -direction.dy)
        let unclampedDuration = travelDistance / 420
        let duration = min(5, max(0.25, unclampedDuration))
        let rawEnd = LanguageSoccerPoint(
            x: start.x + direction.dx * travelDistance,
            y: targetY
        )
        let end = LanguageSoccerPoint(
            x: min(field.maxX - ballRadius, max(field.minX + ballRadius, rawEnd.x)),
            y: rawEnd.y
        )

        let leftPost = LanguageSoccerRect(
            minX: goal.minX - postThickness / 2,
            minY: goal.minY,
            width: postThickness,
            height: goal.height
        )
        let rightPost = LanguageSoccerRect(
            minX: goal.maxX - postThickness / 2,
            minY: goal.minY,
            width: postThickness,
            height: goal.height
        )
        let crossbar = LanguageSoccerRect(
            minX: goal.minX,
            minY: goal.minY - postThickness / 2,
            width: goal.width,
            height: postThickness
        )
        let keeperCore = LanguageSoccerRect(
            minX: keeper.minX + keeper.width * 0.35,
            minY: keeper.minY + keeper.height * 0.55,
            width: keeper.width * 0.30,
            height: keeper.height * 0.45
        )

        let candidates: [(LanguageSoccerCollision, LanguageSoccerRect)] = [
            (.keeper, keeperCore),
            (.leftPost, leftPost),
            (.rightPost, rightPost),
            (.crossbar, crossbar)
        ]
        let collision = candidates.compactMap { kind, rect -> (LanguageSoccerCollision, Double)? in
            intersectionFraction(from: start, to: end, rect: rect.expanded(by: ballRadius))
                .map { (kind, $0) }
        }.min { $0.1 < $1.1 }

        let goalEntryFraction = fractionAtY(goal.maxY, from: start, to: end).flatMap { fraction -> Double? in
            let entry = point(from: start, to: end, fraction: fraction)
            let inset = postThickness + ballRadius
            return entry.x > goal.minX + inset && entry.x < goal.maxX - inset ? fraction : nil
        }

        if let goalEntryFraction,
           collision.map({ $0.1 > goalEntryFraction }) ?? true {
            return LanguageSoccerShotResolution(
                outcome: .goal,
                impactPoint: point(from: start, to: end, fraction: goalEntryFraction),
                reboundPoint: nil,
                collision: nil,
                durationSeconds: max(0.1, duration * goalEntryFraction)
            )
        }

        if let collision {
            let impact = point(from: start, to: end, fraction: collision.1)
            let rebound = LanguageSoccerPoint(
                x: impact.x - direction.dx * 60,
                y: impact.y - direction.dy * 60
            )
            return LanguageSoccerShotResolution(
                outcome: collision.0 == .keeper ? .saved : .miss,
                impactPoint: impact,
                reboundPoint: rebound,
                collision: collision.0,
                durationSeconds: max(0.1, duration * collision.1)
            )
        }

        return LanguageSoccerShotResolution(
            outcome: .miss,
            impactPoint: end,
            reboundPoint: nil,
            collision: nil,
            durationSeconds: duration
        )
    }

    private func point(
        from start: LanguageSoccerPoint,
        to end: LanguageSoccerPoint,
        fraction: Double
    ) -> LanguageSoccerPoint {
        LanguageSoccerPoint(
            x: start.x + (end.x - start.x) * fraction,
            y: start.y + (end.y - start.y) * fraction
        )
    }

    private func intersectionFraction(
        from start: LanguageSoccerPoint,
        to end: LanguageSoccerPoint,
        rect: LanguageSoccerRect
    ) -> Double? {
        let deltaX = end.x - start.x
        let deltaY = end.y - start.y
        var minimum = 0.0
        var maximum = 1.0
        for (origin, delta, lower, upper) in [
            (start.x, deltaX, rect.minX, rect.maxX),
            (start.y, deltaY, rect.minY, rect.maxY)
        ] {
            if abs(delta) < 0.000_001 {
                guard origin >= lower, origin <= upper else { return nil }
                continue
            }
            let first = (lower - origin) / delta
            let second = (upper - origin) / delta
            minimum = max(minimum, min(first, second))
            maximum = min(maximum, max(first, second))
            if minimum > maximum { return nil }
        }
        return minimum
    }


    private func fractionAtY(
        _ y: Double,
        from start: LanguageSoccerPoint,
        to end: LanguageSoccerPoint
    ) -> Double? {
        let delta = end.y - start.y
        guard abs(delta) > 0.000_001 else { return nil }
        let fraction = (y - start.y) / delta
        return (0 ... 1).contains(fraction) ? fraction : nil
    }
}

struct LanguageSoccerKeeperTuning: Equatable, Sendable {
    let level: LanguageSoccerLevel

    var initiallyMoves: Bool { level == .c }

    var referenceWidth: Double {
        switch level {
        case .a: 65
        case .b: 80
        case .c: 95
        }
    }

    var referenceHeight: Double {
        switch level {
        case .a: 80
        case .b: 97
        case .c: 115
        }
    }

    func shouldMove(atAttemptIndex attemptIndex: Int) -> Bool {
        switch level {
        case .a: return attemptIndex >= 3 && attemptIndex.isMultiple(of: 2) == false
        case .b: return attemptIndex >= 2
        case .c: return true
        }
    }

    func oneWaySweepDuration(totalShots: Int, goals: Int) -> Double {
        let values: (base: Double, adjustment: Double, minimum: Double)
        switch level {
        case .a: values = (3.0, 2.0, 1.0)
        case .b: values = (1.1, 0.5, 0.6)
        case .c: values = (0.8, 0.4, 0.4)
        }
        guard totalShots >= 10 else { return values.base }
        let goalRatio = Double(goals) / Double(max(1, totalShots))
        return max(values.minimum, values.base - values.adjustment * goalRatio)
    }

    func keeperMinX(
        at elapsed: TimeInterval,
        isMoving: Bool,
        totalShots: Int,
        goals: Int,
        goal: LanguageSoccerRect,
        keeperWidth: Double
    ) -> Double {
        let range = max(0, goal.width - keeperWidth)
        guard isMoving, range > 0 else {
            return goal.minX + range / 2
        }
        let duration = oneWaySweepDuration(totalShots: totalShots, goals: goals)
        let phase = elapsed.truncatingRemainder(dividingBy: duration * 2) / duration
        let progress = phase <= 1 ? phase : 2 - phase
        return goal.minX + range * progress
    }

    func settlesToCenterAfterMovingShot(
        recentGoals: Int,
        windowSize: Int,
        randomBucket: Int
    ) -> Bool {
        if windowSize >= 10, recentGoals >= 8 {
            return recentGoals > 8
                ? randomBucket % 10 != 1
                : randomBucket % 4 != 1
        }
        if windowSize >= 10, recentGoals < 3 {
            return randomBucket % 4 == 1
        }
        return randomBucket % 2 == 1
    }
}

struct LanguageSoccerProductionConfiguration: Equatable, Sendable {
    let keeperTuning: LanguageSoccerKeeperTuning

    init(parentSoccerLevel: LanguageSoccerLevel) {
        self.keeperTuning = LanguageSoccerKeeperTuning(level: parentSoccerLevel)
    }
}

enum LanguageSoccerLaunchPolicy {
    static func shouldLaunchDuringDrag(locationY: Double, releaseLineY: Double) -> Bool {
        locationY <= releaseLineY - 2
    }

    static func shouldLaunchOnRelease(locationY: Double, releaseLineY: Double) -> Bool {
        locationY <= releaseLineY + 10
    }
}
