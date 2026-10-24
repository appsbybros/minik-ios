import Foundation

// Port of game/TripleShotPhysics.kt (Android 6c38131), statement by statement.
// Bit-exact Float parity: every expression keeps the Kotlin operand order and Float types,
// kotlin.math goes through the AndroidKit k-functions (computed in Double like the JVM), and
// min/max/coerceIn/sign keep Kotlin/Java semantics (kmin/kmax, coerceIn, ksign).

/**
 * Small deterministic 2D basketball physics engine.
 *
 * There is intentionally no "made / missed" decision before the animation starts.
 * The ball receives an initial velocity and then moves under gravity. A basket is
 * recorded only when the ball physically crosses the rim plane from above while
 * its centre is inside the opening.
 *
 * The engine is intentionally lightweight: two circular rim colliders plus a
 * backboard plane are enough to create bank shots, rim bounces and multiple rim
 * contacts without adding a full Box2D dependency.
 */
enum TripleShotPhysics {

    /**
     * Internal shot family chosen automatically from the shooter geometry.
     * The player never needs another gesture for this: normal positions use NORMAL,
     * sharp right-side angles can get a gentle SIDE_ARC, and a truly obstructed
     * behind-the-board shot can become a HIGH_LOB when enough pull-back is supplied.
     */
    enum ShotPathMode: String, KotlinEnum {
        case NORMAL
        case SIDE_ARC
        case HIGH_LOB
    }

    /// Collision world in view pixels. Positional order matters (Kotlin positional constructor);
    /// the memberwise initialiser keeps the Kotlin parameter names, `init(_:...)` the positional form.
    struct Geometry: Hashable {
        var gravityPxPerSec2: Float
        var hoopCenterX: Float
        var hoopY: Float
        var leftRimX: Float
        var rightRimX: Float
        var rimColliderRadius: Float
        var backboardX: Float
        var backboardTopY: Float
        var backboardBottomY: Float
        var netBottomY: Float
        var netBottomLeftX: Float
        var netBottomRightX: Float
        var ballRadius: Float
    }

    /**
     * Mutable state owned by the renderer while a shot is in flight.
     *
     * Kotlin `data class` that is mutated in place by `step` and by the court view hooks, and whose
     * reference identity is observed (`TripleShotShotPresentation` uses `shot !== state`), so it is a
     * final class. `copy()` copies every constructor property like the Kotlin data-class `copy`.
     */
    final class ShotState {
        var x: Float
        var y: Float
        var vx: Float
        var vy: Float
        let startX: Float
        let startY: Float
        let targetX: Float
        let targetY: Float
        let initialVx: Float
        let initialVy: Float
        let gravity: Float
        let expectedFlightSeconds: Float
        let pathMode: ShotPathMode
        let initialCurveAccelerationX: Float
        var curveAccelerationX: Float
        var previousX: Float
        var previousY: Float
        var elapsedSeconds: Float
        var made: Bool
        var rimHits: Int
        var backboardHits: Int
        var maxHeightReachedY: Float
        var closestDistanceToHoop: Float
        var touchingNet: Bool
        /**
         * 1v1 uses a projected 2D court. A close finish must never visually travel upward through
         * the hoop/net and then be called a miss. When true, an upward cylinder entry is rejected
         * physically at the rim plane so the miss LOOKS like a miss.
         */
        let rejectUpwardBasketEntry: Bool
        /**
         * Once the ball has travelled up through the cylinder from below, the attempt can no
         * longer become a legal basket on the way back down. We keep simulating the flight for
         * visual continuity, but scoring remains invalidated for the rest of this shot.
         */
        var enteredBasketFromBelow: Bool

        /// Kotlin defaults that refer to other parameters (`curveAccelerationX = initialCurveAccelerationX`,
        /// `previousX = x`, `previousY = y`, `maxHeightReachedY = y`) are expressed with `nil`.
        init(
            x: Float,
            y: Float,
            vx: Float,
            vy: Float,
            startX: Float,
            startY: Float,
            targetX: Float,
            targetY: Float,
            initialVx: Float,
            initialVy: Float,
            gravity: Float,
            expectedFlightSeconds: Float,
            pathMode: ShotPathMode,
            initialCurveAccelerationX: Float,
            curveAccelerationX: Float? = nil,
            previousX: Float? = nil,
            previousY: Float? = nil,
            elapsedSeconds: Float = 0,
            made: Bool = false,
            rimHits: Int = 0,
            backboardHits: Int = 0,
            maxHeightReachedY: Float? = nil,
            closestDistanceToHoop: Float = Float.greatestFiniteMagnitude,
            touchingNet: Bool = false,
            rejectUpwardBasketEntry: Bool = false,
            enteredBasketFromBelow: Bool = false
        ) {
            self.x = x
            self.y = y
            self.vx = vx
            self.vy = vy
            self.startX = startX
            self.startY = startY
            self.targetX = targetX
            self.targetY = targetY
            self.initialVx = initialVx
            self.initialVy = initialVy
            self.gravity = gravity
            self.expectedFlightSeconds = expectedFlightSeconds
            self.pathMode = pathMode
            self.initialCurveAccelerationX = initialCurveAccelerationX
            self.curveAccelerationX = curveAccelerationX ?? initialCurveAccelerationX
            self.previousX = previousX ?? x
            self.previousY = previousY ?? y
            self.elapsedSeconds = elapsedSeconds
            self.made = made
            self.rimHits = rimHits
            self.backboardHits = backboardHits
            self.maxHeightReachedY = maxHeightReachedY ?? y
            self.closestDistanceToHoop = closestDistanceToHoop
            self.touchingNet = touchingNet
            self.rejectUpwardBasketEntry = rejectUpwardBasketEntry
            self.enteredBasketFromBelow = enteredBasketFromBelow
        }

        /// Kotlin positional constructor form, e.g. `ShotState(430f, 700f, 0f, -500f, ..., NORMAL, 0f)`.
        convenience init(
            _ x: Float,
            _ y: Float,
            _ vx: Float,
            _ vy: Float,
            _ startX: Float,
            _ startY: Float,
            _ targetX: Float,
            _ targetY: Float,
            _ initialVx: Float,
            _ initialVy: Float,
            _ gravity: Float,
            _ expectedFlightSeconds: Float,
            _ pathMode: ShotPathMode,
            _ initialCurveAccelerationX: Float,
            _ curveAccelerationX: Float? = nil,
            _ previousX: Float? = nil,
            _ previousY: Float? = nil,
            _ elapsedSeconds: Float = 0,
            _ made: Bool = false,
            _ rimHits: Int = 0,
            _ backboardHits: Int = 0,
            _ maxHeightReachedY: Float? = nil,
            _ closestDistanceToHoop: Float = Float.greatestFiniteMagnitude,
            _ touchingNet: Bool = false,
            _ rejectUpwardBasketEntry: Bool = false,
            _ enteredBasketFromBelow: Bool = false
        ) {
            self.init(
                x: x,
                y: y,
                vx: vx,
                vy: vy,
                startX: startX,
                startY: startY,
                targetX: targetX,
                targetY: targetY,
                initialVx: initialVx,
                initialVy: initialVy,
                gravity: gravity,
                expectedFlightSeconds: expectedFlightSeconds,
                pathMode: pathMode,
                initialCurveAccelerationX: initialCurveAccelerationX,
                curveAccelerationX: curveAccelerationX,
                previousX: previousX,
                previousY: previousY,
                elapsedSeconds: elapsedSeconds,
                made: made,
                rimHits: rimHits,
                backboardHits: backboardHits,
                maxHeightReachedY: maxHeightReachedY,
                closestDistanceToHoop: closestDistanceToHoop,
                touchingNet: touchingNet,
                rejectUpwardBasketEntry: rejectUpwardBasketEntry,
                enteredBasketFromBelow: enteredBasketFromBelow
            )
        }

        /// Kotlin data-class `copy(...)`: a new instance; every property not given keeps its current value.
        func copy(
            x: Float? = nil,
            y: Float? = nil,
            vx: Float? = nil,
            vy: Float? = nil,
            startX: Float? = nil,
            startY: Float? = nil,
            targetX: Float? = nil,
            targetY: Float? = nil,
            initialVx: Float? = nil,
            initialVy: Float? = nil,
            gravity: Float? = nil,
            expectedFlightSeconds: Float? = nil,
            pathMode: ShotPathMode? = nil,
            initialCurveAccelerationX: Float? = nil,
            curveAccelerationX: Float? = nil,
            previousX: Float? = nil,
            previousY: Float? = nil,
            elapsedSeconds: Float? = nil,
            made: Bool? = nil,
            rimHits: Int? = nil,
            backboardHits: Int? = nil,
            maxHeightReachedY: Float? = nil,
            closestDistanceToHoop: Float? = nil,
            touchingNet: Bool? = nil,
            rejectUpwardBasketEntry: Bool? = nil,
            enteredBasketFromBelow: Bool? = nil
        ) -> ShotState {
            return ShotState(
                x: x ?? self.x,
                y: y ?? self.y,
                vx: vx ?? self.vx,
                vy: vy ?? self.vy,
                startX: startX ?? self.startX,
                startY: startY ?? self.startY,
                targetX: targetX ?? self.targetX,
                targetY: targetY ?? self.targetY,
                initialVx: initialVx ?? self.initialVx,
                initialVy: initialVy ?? self.initialVy,
                gravity: gravity ?? self.gravity,
                expectedFlightSeconds: expectedFlightSeconds ?? self.expectedFlightSeconds,
                pathMode: pathMode ?? self.pathMode,
                initialCurveAccelerationX: initialCurveAccelerationX ?? self.initialCurveAccelerationX,
                curveAccelerationX: curveAccelerationX ?? self.curveAccelerationX,
                previousX: previousX ?? self.previousX,
                previousY: previousY ?? self.previousY,
                elapsedSeconds: elapsedSeconds ?? self.elapsedSeconds,
                made: made ?? self.made,
                rimHits: rimHits ?? self.rimHits,
                backboardHits: backboardHits ?? self.backboardHits,
                maxHeightReachedY: maxHeightReachedY ?? self.maxHeightReachedY,
                closestDistanceToHoop: closestDistanceToHoop ?? self.closestDistanceToHoop,
                touchingNet: touchingNet ?? self.touchingNet,
                rejectUpwardBasketEntry: rejectUpwardBasketEntry ?? self.rejectUpwardBasketEntry,
                enteredBasketFromBelow: enteredBasketFromBelow ?? self.enteredBasketFromBelow
            )
        }
    }

    struct StepResult: Hashable {
        var madeNow: Bool = false
        var rimImpactSpeed: Float = 0
        var backboardImpactSpeed: Float = 0
        var netImpactSpeed: Float = 0
    }

    private struct NetContact {
        let touching: Bool
        let impactSpeed: Float
    }

    /**
     * Creates a launch that would reach targetX/targetY with a neutral release.
     *
     * Pull-back changes the desired flight time, therefore visibly changing the
     * arc. Release speed is applied afterwards as a multiplier, so a weak throw
     * really falls short and a strong throw can fly long or hit the board.
     *
     * distanceDifficulty is 0 for an easy/short position and approaches 1 for a
     * farther position. This makes farther spots require a slightly stronger
     * physical release even though the same input mechanic is used everywhere.
     */
    static func createLaunch(
        skill: ShotSkill,
        startX: Float,
        startY: Float,
        targetX: Float,
        targetY: Float,
        pullBack01: Float,
        geometry: Geometry,
        distanceDifficulty: Float,
        neutralPowerHitsTarget: Bool = false,
        compactOneOnOneArc: Bool = false,
        rejectUpwardBasketEntry: Bool = false
    ) -> ShotState {
        let pull = pullBack01.coerceIn(0.22, 1.20)
        let g = geometry.gravityPxPerSec2

        // Practice/HORSE keep the expressive pull-back arc. In 1v1, hold time is a shot-quality
        // decision, not a "launch the ball into the treetops" control. Build the shortest natural
        // flight that still reaches the rim while DESCENDING, then add only a small distance margin.
        // This removes the huge 1.3-1.4s lobs without re-introducing the old upward-through-rim bug.
        let arc01 = ((pull - 0.22) / 0.98).coerceIn(0, 1)
        let expressiveFlightSeconds = lerp(0.72, 1.42, arc01)
        let difficulty01 = distanceDifficulty.coerceIn(0, 1)
        let verticalRise = (startY - targetY).coerceAtLeast(0)
        let minimumDescendingSeconds: Float
        if verticalRise <= 0 {
            minimumDescendingSeconds = 0.68
        } else {
            let descentSquared: Float = (2 * verticalRise / g.coerceAtLeast(1)).coerceAtLeast(0)
            minimumDescendingSeconds = ksqrt(descentSquared) + 0.055
        }
        let compactBaseFlightSeconds =
            kmax(
                minimumDescendingSeconds + lerp(0.035, 0.085, difficulty01),
                lerp(0.70, 0.91, difficulty01)
            ).coerceIn(0.70, 1.08)

        /*
         * A "made" 1v1 percentage roll reaches this function as a zero-error release. The old
         * compact arc was sometimes so flat that the geometric centre-line shot hit the FRONT rim
         * before it could descend through the hoop. That is why an open Maya could appear to put
         * the ball into the cylinder several times while the score stayed unchanged.
         *
         * Raise ONLY a clean 1v1 make as much as is physically necessary to clear the near rim.
         * This is not a generic high lob: we search from the compact flight time upward and stop at
         * the first normal basketball arc that clears the rim. Misses keep their authored miss
         * trajectory and can genuinely hit rim/backboard.
         */
        let cleanOneOnOneMake =
            compactOneOnOneArc && neutralPowerHitsTarget &&
                abs(skill.aimError) < 0.0005 &&
                abs(skill.powerError) < 0.0005 &&
                abs(skill.arcError) < 0.0005
        let compactFlightSeconds: Float
        if cleanOneOnOneMake {
            compactFlightSeconds = chooseOneOnOneMakeFlightTime(
                startX: startX,
                startY: startY,
                targetX: targetX,
                targetY: targetY,
                baseFlightSeconds: compactBaseFlightSeconds,
                geometry: geometry
            )
        } else {
            compactFlightSeconds = compactBaseFlightSeconds
        }
        let baseFlightSeconds =
            compactOneOnOneArc ? compactFlightSeconds : expressiveFlightSeconds

        /*
         * Extreme HORSE-style positions can live behind the photographed backboard.
         * A plain 2D parabola aimed at the rim may otherwise be mathematically blocked by
         * the board forever. We do NOT grant an automatic basket: when the player has built
         * a high enough arc, we lengthen the neutral flight just enough that a GOOD release
         * has a real path over the top of the board. Weak/flat/poorly-aimed releases still
         * hit the board or miss.
         *
         * Because the preview calls this exact same function, the player can actually SEE
         * the rare over-the-board path before attempting it.
         */
        let requestedPathMode = choosePathMode(
            startX: startX,
            startY: startY,
            targetX: targetX,
            targetY: targetY,
            baseFlightSeconds: baseFlightSeconds,
            geometry: geometry
        )
        // HIGH_LOB is a deliberate HORSE trick-shot helper. A live 1v1 possession should not
        // suddenly choose that ten-metre-looking camera arc just because the player reached an
        // unusual side angle; let the normal backboard/rim physics punish that position instead.
        let pathMode: ShotPathMode
        if compactOneOnOneArc {
            // 1v1 is read as a real basketball possession, not a HORSE trick-shot camera.
            // Disable BOTH HIGH_LOB and SIDE_ARC here. SIDE_ARC's synthetic horizontal
            // acceleration was the reason some side shots visibly travelled toward the hoop,
            // slowed, then curved back toward the shooter without touching anything.
            pathMode = .NORMAL
        } else {
            pathMode = requestedPathMode
        }

        let flightSeconds: Float
        if pathMode == .HIGH_LOB {
            flightSeconds = chooseReachableFlightTime(
                startX: startX,
                startY: startY,
                targetX: targetX,
                targetY: targetY,
                baseFlightSeconds: baseFlightSeconds,
                pullBack: pull,
                geometry: geometry
            )
        } else {
            flightSeconds = baseFlightSeconds
        }

        /*
         * SIDE_ARC is deliberately automatic. On the photograph, a player who stands
         * near the right side of the hoop can have only a tiny screen-space X distance
         * to the rim even though the real-world shot still has depth. A pure 2D parabola
         * then looks almost vertical and can become artificially impossible.
         *
         * We model the missing perspective with a small constant horizontal acceleration.
         * Neutral power still ends exactly at targetX, but the midpoint bows toward the
         * open court, creating the round "half-ball" outline the player expects.
         */
        let sideCurveAmplitudeX = chooseSideCurveAmplitude(
            mode: pathMode,
            startX: startX,
            targetX: targetX,
            geometry: geometry
        )
        let curveAccelerationX: Float
        if abs(sideCurveAmplitudeX) < 0.001 {
            curveAccelerationX = 0
        } else {
            let curveNumerator: Float = -8 * sideCurveAmplitudeX
            curveAccelerationX = curveNumerator /
                (flightSeconds * flightSeconds).coerceAtLeast(0.01)
        }

        // Solve X and Y independently so a neutral release still reaches the rim.
        let curveTravelX: Float = 0.5 * curveAccelerationX * flightSeconds * flightSeconds
        let requiredVx: Float =
            (targetX - startX - curveTravelX) /
                flightSeconds
        let gravityTravelY: Float = 0.5 * g * flightSeconds * flightSeconds
        let requiredVy: Float =
            (targetY - startY - gravityTravelY) /
                flightSeconds

        // skill.powerError is centred around zero by the input controller.
        let releaseStrength =
            (1 + skill.powerError * POWER_ERROR_TO_SPEED).coerceIn(0.58, 1.42)

        /*
         * Different positions still require different strength, but the neutral release stays
         * useful. Corner spots are a touch easier; the top/deeper spots need a touch more.
         */
        let difficulty =
            distanceDifficulty.coerceIn(0, 1)
        let requiredStrength: Float
        if neutralPowerHitsTarget {
            // 1v1 already rolled make/miss before launch. A neutral (zero-error) release must
            // therefore hit the geometric target exactly instead of being quietly shifted by
            // the practice-mode distance-strength calibration. Non-zero power errors still
            // move the shot long/short in the normal physical way.
            requiredStrength = 1
        } else {
            requiredStrength = (1 + (difficulty - 0.5) * DISTANCE_POWER_SPREAD)
                .coerceIn(0.96, 1.04)
        }

        let actualScale = releaseStrength / requiredStrength

        return ShotState(
            x: startX,
            y: startY,
            vx: requiredVx * actualScale,
            vy: requiredVy * actualScale,
            startX: startX,
            startY: startY,
            targetX: targetX,
            targetY: targetY,
            initialVx: requiredVx * actualScale,
            initialVy: requiredVy * actualScale,
            gravity: g,
            expectedFlightSeconds: flightSeconds,
            pathMode: pathMode,
            initialCurveAccelerationX: curveAccelerationX * actualScale,
            curveAccelerationX: curveAccelerationX * actualScale,
            rejectUpwardBasketEntry: rejectUpwardBasketEntry
        )
    }

    /// Kotlin positional call form of `createLaunch`.
    static func createLaunch(
        _ skill: ShotSkill,
        _ startX: Float,
        _ startY: Float,
        _ targetX: Float,
        _ targetY: Float,
        _ pullBack01: Float,
        _ geometry: Geometry,
        _ distanceDifficulty: Float,
        _ neutralPowerHitsTarget: Bool = false,
        _ compactOneOnOneArc: Bool = false,
        _ rejectUpwardBasketEntry: Bool = false
    ) -> ShotState {
        return createLaunch(
            skill: skill,
            startX: startX,
            startY: startY,
            targetX: targetX,
            targetY: targetY,
            pullBack01: pullBack01,
            geometry: geometry,
            distanceDifficulty: distanceDifficulty,
            neutralPowerHitsTarget: neutralPowerHitsTarget,
            compactOneOnOneArc: compactOneOnOneArc,
            rejectUpwardBasketEntry: rejectUpwardBasketEntry
        )
    }

    /**
     * Finds the shortest compact 1v1 make arc that clears the approach-side rim collider.
     * The search is deterministic and bounded; it never affects HORSE/Challenge or intentional
     * misses. If the release is already horizontally inside the cylinder, the caller's finish-lane
     * protection owns that special case and we keep the compact base time.
     */
    private static func chooseOneOnOneMakeFlightTime(
        startX: Float,
        startY: Float,
        targetX: Float,
        targetY: Float,
        baseFlightSeconds: Float,
        geometry: Geometry
    ) -> Float {
        let dx = targetX - startX
        let verticalRise = startY - targetY
        if abs(dx) < geometry.ballRadius * 1.5 || verticalRise <= 0 {
            return baseFlightSeconds
        }

        let approachRimX = dx > 0 ? geometry.leftRimX : geometry.rightRimX
        let approachFraction = (approachRimX - startX) / dx
        if approachFraction <= 0.015 || approachFraction >= 0.985 {
            return baseFlightSeconds
        }

        let g = geometry.gravityPxPerSec2.coerceAtLeast(1)
        let combinedRimRadius =
            (geometry.ballRadius + geometry.rimColliderRadius) *
                ONE_ON_ONE_MAKE_RIM_CLEARANCE_SCALE
        let openingPadding =
            geometry.rimColliderRadius + geometry.ballRadius * 0.18
        let upwardSafeEdge =
            dx > 0 ? geometry.leftRimX + openingPadding
                : geometry.rightRimX - openingPadding

        var candidate = baseFlightSeconds
        while candidate <= ONE_ON_ONE_MAX_COMPACT_MAKE_FLIGHT_SECONDS + 0.0001 {
            let requiredVx = dx / candidate
            let gravityTravel: Float = 0.5 * g * candidate * candidate
            let requiredVy =
                (targetY - startY - gravityTravel) / candidate
            let vyAtTarget = requiredVy + g * candidate

            // The other y=hoopY root is the upward crossing. It must happen before the projected
            // cylinder, otherwise the screen first shows the ball travelling UP through the net.
            let upwardCrossTime =
                (2 * verticalRise / (g * candidate)).coerceIn(0, candidate)
            let upwardCrossX = startX + requiredVx * upwardCrossTime
            let upwardClear =
                dx > 0 ? upwardCrossX < upwardSafeEdge
                    : upwardCrossX > upwardSafeEdge

            // Also clear the physical approach rim circle, including ball radius. Sampling only the
            // small time window around that rim is cheap and catches tangent grazes that a single
            // y-at-rim-X test misses.
            let timeAtApproachRim = candidate * approachFraction
            let sampleHalfWindow =
                (combinedRimRadius / abs(requiredVx).coerceAtLeast(1)) * 1.35
            var minRimDistance = Float.greatestFiniteMagnitude
            for i in 0...ONE_ON_ONE_MAKE_RIM_CLEARANCE_SAMPLES {
                let f = i.toFloat() / ONE_ON_ONE_MAKE_RIM_CLEARANCE_SAMPLES.toFloat()
                let sampleT =
                    lerp(
                        timeAtApproachRim - sampleHalfWindow,
                        timeAtApproachRim + sampleHalfWindow,
                        f
                    ).coerceIn(0, candidate)
                let x = startX + requiredVx * sampleT
                let sampleGravityTravel: Float = 0.5 * g * sampleT * sampleT
                let y = startY + requiredVy * sampleT + sampleGravityTravel
                minRimDistance = kmin(
                    minRimDistance,
                    distance(x, y, approachRimX, geometry.hoopY)
                )
            }
            let rimClear = minRimDistance >= combinedRimRadius

            if vyAtTarget > ONE_ON_ONE_MIN_DESCENDING_TARGET_SPEED &&
                upwardClear &&
                rimClear {
                return candidate
            }
            candidate += ONE_ON_ONE_MAKE_FLIGHT_SEARCH_STEP_SECONDS
        }

        return ONE_ON_ONE_MAX_COMPACT_MAKE_FLIGHT_SECONDS
    }

    /**
     * Chooses a path family without exposing another control to the player.
     *
     * HIGH_LOB is reserved for a trajectory whose neutral path would actually cross
     * the physical backboard rectangle. SIDE_ARC is used only for sharp right-side
     * camera angles where screen-space depth collapses and a straight X path looks
     * unnaturally vertical. Everything else stays NORMAL.
     */
    private static func choosePathMode(
        startX: Float,
        startY: Float,
        targetX: Float,
        targetY: Float,
        baseFlightSeconds: Float,
        geometry: Geometry
    ) -> ShotPathMode {
        let clearlyBehindBoard =
            startX > geometry.backboardX + geometry.ballRadius * 0.25 &&
                targetX < geometry.backboardX - geometry.ballRadius * 0.25

        if clearlyBehindBoard {
            return .HIGH_LOB
        }

        if basePathIntersectsBackboard(
            startX: startX,
            startY: startY,
            targetX: targetX,
            targetY: targetY,
            flightSeconds: baseFlightSeconds,
            geometry: geometry
        ) {
            return .HIGH_LOB
        }

        let openingWidth =
            (geometry.rightRimX - geometry.leftRimX).coerceAtLeast(1)
        let horizontalDistance = abs(targetX - startX)
        let verticalDistance = abs(startY - targetY)
        let onRightSide = startX > geometry.hoopCenterX + openingWidth * 0.10
        let sharpCameraAngle =
            horizontalDistance < openingWidth * SIDE_ARC_MAX_HORIZONTAL_OPENINGS &&
                verticalDistance > openingWidth * SIDE_ARC_MIN_VERTICAL_OPENINGS

        if onRightSide && sharpCameraAngle {
            return .SIDE_ARC
        } else {
            return .NORMAL
        }
    }

    /**
     * Returns the desired midpoint bow in pixels. Negative X points away from the
     * photographed backboard and toward the open court. The amplitude is stronger
     * only when the shot is visually very steep; ordinary shots are untouched.
     */
    private static func chooseSideCurveAmplitude(
        mode: ShotPathMode,
        startX: Float,
        targetX: Float,
        geometry: Geometry
    ) -> Float {
        let openingWidth =
            (geometry.rightRimX - geometry.leftRimX).coerceAtLeast(1)

        if mode == .HIGH_LOB {
            /*
             * Behind the photographed backboard the useful curve is intentionally the
             * opposite of the near-side curve: the ball first travels farther BEHIND /
             * outside the board, gains height, then bends back toward the rim. That delays
             * crossing the board/rim plane until the ball is high enough, which is the
             * 2D equivalent of throwing over/around the board.
             */
            let side: Float = startX >= geometry.hoopCenterX ? 1 : -1
            return side * openingWidth * HIGH_LOB_SIDE_CURVE_OPENING_FRACTION
        }

        if mode != .SIDE_ARC { return 0 }

        let horizontalDistance = abs(targetX - startX)
        let sharpness =
            (1 - horizontalDistance /
                (openingWidth * SIDE_ARC_MAX_HORIZONTAL_OPENINGS))
                .coerceIn(0, 1)
        let rightness =
            ((startX - geometry.hoopCenterX) / openingWidth)
                .coerceIn(0, 1.35)

        let sharpnessStrength: Float = 0.45 + 0.55 * sharpness
        let rightnessStrength: Float = 0.72 + 0.28 * rightness.coerceIn(0, 1)
        let strength = sharpnessStrength * rightnessStrength

        return -openingWidth * SIDE_ARC_OPENING_FRACTION * strength
    }

    /**
     * Checks the actual finite backboard rectangle, not an infinite vertical wall.
     * This prevents a near-side shot from being promoted to a trick lob merely because
     * it happens to sit close to the board in the photograph.
     */
    private static func basePathIntersectsBackboard(
        startX: Float,
        startY: Float,
        targetX: Float,
        targetY: Float,
        flightSeconds: Float,
        geometry: Geometry
    ) -> Bool {
        let boardX = geometry.backboardX
        if (startX - boardX) * (targetX - boardX) >= 0 { return false }

        let vx = (targetX - startX) / flightSeconds
        if abs(vx) < 0.001 { return false }

        let t = (boardX - startX) / vx
        if t <= 0 || t >= flightSeconds { return false }

        let gravityTravel: Float =
            0.5 * geometry.gravityPxPerSec2 * flightSeconds * flightSeconds
        let vy =
            (targetY - startY - gravityTravel) /
                flightSeconds
        let gravityTravelAtBoard: Float = 0.5 * geometry.gravityPxPerSec2 * t * t
        let yAtBoard =
            startY + vy * t +
                gravityTravelAtBoard

        let margin = geometry.ballRadius
        return yAtBoard + margin >= geometry.backboardTopY &&
            yAtBoard - margin <= geometry.backboardBottomY
    }

    /**
     * Finds a high-but-still-physical parabola for a shooter standing behind the board.
     *
     * The normal court uses baseFlightSeconds unchanged. The special search only runs when
     * the straight horizontal segment from shooter to target actually crosses the backboard
     * plane AND the player pulled back enough to request a high arc.
     */
    private static func chooseReachableFlightTime(
        startX: Float,
        startY: Float,
        targetX: Float,
        targetY: Float,
        baseFlightSeconds: Float,
        pullBack: Float,
        geometry: Geometry
    ) -> Float {
        let boardX = geometry.backboardX

        if pullBack < MIN_PULL_FOR_BOARD_CLEARANCE {
            return baseFlightSeconds
        }

        let g = geometry.gravityPxPerSec2
        let safeTopY =
            geometry.backboardTopY -
                geometry.ballRadius * BOARD_CLEARANCE_BALL_RADII -
                geometry.rimColliderRadius

        var candidate = kmax(baseFlightSeconds, MIN_TRICK_FLIGHT_SECONDS)
        while candidate <= MAX_TRICK_FLIGHT_SECONDS {
            let vx = (targetX - startX) / candidate
            if abs(vx) < 0.001 { break }

            let timeAtBoard = (boardX - startX) / vx
            if timeAtBoard > 0 && timeAtBoard < candidate {
                let gravityTravel: Float = 0.5 * g * candidate * candidate
                let vy =
                    (targetY - startY - gravityTravel) /
                        candidate
                let gravityTravelAtBoard: Float = 0.5 * g * timeAtBoard * timeAtBoard
                let yAtBoard =
                    startY +
                        vy * timeAtBoard +
                        gravityTravelAtBoard

                if yAtBoard <= safeTopY {
                    return candidate
                }
            }

            candidate += TRICK_FLIGHT_SEARCH_STEP_SECONDS
        }

        // If the geometry is exceptionally nasty, return the highest supported lob.
        // This makes the route possible in principle but still very unforgiving in practice.
        return MAX_TRICK_FLIGHT_SECONDS
    }

    /**
     * Advances the ball by one small physics step.
     *
     * Callers should sub-step long display frames (for example 1/180 s steps)
     * so a fast ball cannot tunnel through the thin rim colliders.
     */
    @discardableResult
    static func step(
        state: ShotState,
        geometry: Geometry,
        dtSeconds: Float
    ) -> StepResult {
        if dtSeconds <= 0 { return StepResult() }

        state.previousX = state.x
        state.previousY = state.y

        // Exact constant-acceleration travel: semi-implicit Euler dropped clean, near-rim
        // trajectories below their planned arc before the contact (frame-rate dependent).
        state.x += state.vx * dtSeconds + Float(0.5) * state.curveAccelerationX * dtSeconds * dtSeconds
        state.y += state.vy * dtSeconds + Float(0.5) * geometry.gravityPxPerSec2 * dtSeconds * dtSeconds
        state.vx += state.curveAccelerationX * dtSeconds
        state.vy += geometry.gravityPxPerSec2 * dtSeconds
        state.elapsedSeconds += dtSeconds
        state.maxHeightReachedY = kmin(state.maxHeightReachedY, state.y)

        let boardImpact =
            collideBackboard(state, geometry)

        // Kotlin evaluates both arguments, left rim first (each call mutates the state).
        var rimImpact = kmax(
            collideCircle(
                state: state,
                colliderX: geometry.leftRimX,
                colliderY: geometry.hoopY,
                colliderRadius: geometry.rimColliderRadius,
                ballRadius: geometry.ballRadius
            ),
            collideCircle(
                state: state,
                colliderX: geometry.rightRimX,
                colliderY: geometry.hoopY,
                colliderRadius: geometry.rimColliderRadius,
                ballRadius: geometry.ballRadius
            )
        )

        if rimImpact > 0 { state.rimHits += 1 }
        if boardImpact > 0 { state.backboardHits += 1 }

        // Once the ball physically hits something, rebounds own the rest of the path.
        if rimImpact > 0 || boardImpact > 0 {
            state.curveAccelerationX = 0
        }

        let distanceToHoop = distance(
            state.x,
            state.y,
            geometry.hoopCenterX,
            geometry.hoopY
        )
        state.closestDistanceToHoop = kmin(state.closestDistanceToHoop, distanceToHoop)

        var madeNow = false
        if !state.made {
            let openingPadding =
                geometry.rimColliderRadius + geometry.ballRadius * 0.12

            /*
             * Basket tests must use the X coordinate at the exact rim-plane crossing, not the
             * end-of-substep X. Even with 1/180s substeps a close 1v1 finish can move several
             * visible pixels laterally between those two points. Using state.x made an on-screen
             * centre-net drop occasionally look like a basket while the logical test saw the ball
             * just outside the opening.
             */
            func xAtHorizontalPlane(_ planeY: Float) -> Float {
                let dy = state.y - state.previousY
                if abs(dy) < 0.0001 { return state.x }
                let t = ((planeY - state.previousY) / dy).coerceIn(0, 1)
                return state.previousX + (state.x - state.previousX) * t
            }

            let crossedUpwardFromBelow =
                state.previousY > geometry.hoopY &&
                    state.y <= geometry.hoopY &&
                    state.vy < 0
            let upwardCrossX = xAtHorizontalPlane(geometry.hoopY)
            let upwardInsideOpening =
                upwardCrossX > geometry.leftRimX + openingPadding &&
                    upwardCrossX < geometry.rightRimX - openingPadding

            if crossedUpwardFromBelow && upwardInsideOpening {
                state.enteredBasketFromBelow = true

                if state.rejectUpwardBasketEntry {
                    /*
                     * Visual truth for 1v1: do not let a close shot pass upward through the
                     * photographed cylinder/net. That reads as a made basket to the eye even
                     * though a basketball travelling upward through the rim is not a score.
                     *
                     * Bounce it off the underside/front of the rim plane instead. The real rim
                     * circle colliders still own normal contacts; this only catches the projected
                     * "straight up through the opening" case that 2D perspective can create.
                     */
                    let incomingVy = state.vy
                    let side: Float
                    if state.x < geometry.hoopCenterX - geometry.ballRadius * 0.15 {
                        side = -1
                    } else if state.x > geometry.hoopCenterX + geometry.ballRadius * 0.15 {
                        side = 1
                    } else if state.initialVx < 0 {
                        side = -1
                    } else {
                        side = 1
                    }
                    state.y = geometry.hoopY + geometry.ballRadius * 0.88
                    state.vy = abs(incomingVy) * 0.34
                    state.vx += side * kmax(geometry.ballRadius * 2.2, abs(incomingVy) * 0.11)
                    state.curveAccelerationX = 0
                    state.rimHits += 1
                    rimImpact = kmax(rimImpact, abs(incomingVy))
                }
            }

            let crossedDownward =
                state.previousY < geometry.hoopY &&
                    state.y >= geometry.hoopY &&
                    state.vy > 0

            let downwardCrossX = xAtHorizontalPlane(geometry.hoopY)
            let downwardInsideOpening =
                downwardCrossX > geometry.leftRimX + openingPadding &&
                    downwardCrossX < geometry.rightRimX - openingPadding

            if crossedDownward &&
                downwardInsideOpening &&
                !state.enteredBasketFromBelow {
                state.made = true
                madeNow = true
            }
        }

        let netContact =
            interactWithNet(
                state: state,
                geometry: geometry,
                dtSeconds: dtSeconds
            )

        let netImpact: Float =
            netContact.touching && !state.touchingNet ? netContact.impactSpeed : 0
        state.touchingNet = netContact.touching

        return StepResult(
            madeNow: madeNow,
            rimImpactSpeed: rimImpact,
            backboardImpactSpeed: boardImpact,
            netImpactSpeed: netImpact
        )
    }

    /// Kotlin positional call form `TripleShotPhysics.step(state, geometry, dt)`.
    @discardableResult
    static func step(_ state: ShotState, _ geometry: Geometry, _ dtSeconds: Float) -> StepResult {
        return step(state: state, geometry: geometry, dtSeconds: dtSeconds)
    }

    /**
     * Position of the collision-free preview trajectory at time t.
     * This is used only for the dashed pre-shot guide.
     * (Kotlin `Pair<Float, Float>`: `.first`/`.second`, or destructure `let (x, y) = ...`.)
     */
    static func previewPosition(state: ShotState, tSeconds: Float) -> (first: Float, second: Float) {
        let t = tSeconds.coerceAtLeast(0)
        let curveTravel: Float = 0.5 * state.initialCurveAccelerationX * t * t
        let x =
            state.startX +
                state.initialVx * t +
                curveTravel
        let gravityTravel: Float = 0.5 * state.gravity * t * t
        let y =
            state.startY +
                state.initialVy * t +
                gravityTravel
        return (x, y)
    }

    /// Kotlin positional call form of `previewPosition`.
    static func previewPosition(_ state: ShotState, _ tSeconds: Float) -> (first: Float, second: Float) {
        return previewPosition(state: state, tSeconds: tSeconds)
    }

    static func toOutcome(
        state: ShotState,
        geometry: Geometry
    ) -> ShotOutcome {
        let openingHalfWidth =
            ((geometry.rightRimX - geometry.leftRimX) * 0.5).coerceAtLeast(1)

        let xOffset =
            ((state.x - geometry.hoopCenterX) / openingHalfWidth)
                .coerceIn(-2, 2)

        let yOffset =
            ((state.y - geometry.hoopY) / (openingHalfWidth * 1.3))
                .coerceIn(-2, 2)

        let quality: Float
        if state.made && state.rimHits == 0 && state.backboardHits == 0 {
            quality = 1
        } else if state.made {
            quality = 0.86
        } else {
            let normalizedClosest =
                state.closestDistanceToHoop / (openingHalfWidth * 2)
            quality = (1 - normalizedClosest).coerceIn(0, 0.8)
        }

        return ShotOutcome(
            made: state.made,
            targetOffsetX: xOffset,
            targetOffsetY: yOffset,
            quality: quality
        )
    }

    /// Kotlin positional call form `TripleShotPhysics.toOutcome(state, geometry)`.
    static func toOutcome(_ state: ShotState, _ geometry: Geometry) -> ShotOutcome {
        return toOutcome(state: state, geometry: geometry)
    }

    private static func collideBackboard(
        _ state: ShotState,
        _ geometry: Geometry
    ) -> Float {
        let r = geometry.ballRadius
        let withinVerticalRange =
            state.y + r >= geometry.backboardTopY &&
                state.y - r <= geometry.backboardBottomY

        if !withinVerticalRange { return 0 }

        // Most shots approach the backboard from the left.
        if state.vx > 0 &&
            state.previousX + r <= geometry.backboardX &&
            state.x + r >= geometry.backboardX {
            let impact = abs(state.vx)
            state.x = geometry.backboardX - r
            state.vx = -abs(state.vx) * BACKBOARD_RESTITUTION
            state.vy *= BACKBOARD_VERTICAL_DAMPING
            return impact
        }

        // Kept for unusual rebound paths that approach the board from behind/right.
        if state.vx < 0 &&
            state.previousX - r >= geometry.backboardX &&
            state.x - r <= geometry.backboardX {
            let impact = abs(state.vx)
            state.x = geometry.backboardX + r
            state.vx = abs(state.vx) * BACKBOARD_RESTITUTION
            state.vy *= BACKBOARD_VERTICAL_DAMPING
            return impact
        }

        return 0
    }

    /**
     * Circle-vs-circle collision with restitution.
     *
     * The normal points from the rim collider towards the ball. Reflecting only
     * when velocity points into the collider avoids sticky repeated collisions.
     */
    private static func collideCircle(
        state: ShotState,
        colliderX: Float,
        colliderY: Float,
        colliderRadius: Float,
        ballRadius: Float
    ) -> Float {
        var dx = state.x - colliderX
        var dy = state.y - colliderY
        var dist = ksqrt(dx * dx + dy * dy)
        let minDist = colliderRadius + ballRadius

        if dist >= minDist { return 0 }

        if dist < 0.001 {
            dx = 0
            dy = -1
            dist = 1
        }

        let nx = dx / dist
        let ny = dy / dist

        // Push the ball outside the rim before reflecting it.
        let penetration = minDist - dist
        state.x += nx * penetration
        state.y += ny * penetration

        let normalVelocity = state.vx * nx + state.vy * ny
        if normalVelocity >= 0 { return 0 }

        let impactSpeed = abs(normalVelocity)

        state.vx -= (1 + RIM_RESTITUTION) * normalVelocity * nx
        state.vy -= (1 + RIM_RESTITUTION) * normalVelocity * ny

        // Tiny tangential energy loss makes repeated rim bounces settle naturally.
        state.vx *= RIM_TANGENTIAL_DAMPING
        state.vy *= RIM_TANGENTIAL_DAMPING

        return impactSpeed
    }

    /**
     * Lightweight net interaction.
     *
     * The net is deliberately soft rather than a rigid collider. A missed ball can brush
     * the side and animate it, while a MADE ball is gently funnelled toward the middle
     * and loses horizontal speed so it visibly drops through instead of escaping sideways.
     */
    private static func interactWithNet(
        state: ShotState,
        geometry: Geometry,
        dtSeconds: Float
    ) -> NetContact {
        let r = geometry.ballRadius
        let topY = geometry.hoopY - r * 0.10
        let bottomY = geometry.netBottomY

        if state.y + r < topY ||
            state.y - r > bottomY + r * 1.4 {
            return NetContact(touching: false, impactSpeed: 0)
        }

        let progress =
            ((state.y - geometry.hoopY) /
                (bottomY - geometry.hoopY).coerceAtLeast(1))
                .coerceIn(0, 1)

        let bottomCenter =
            (geometry.netBottomLeftX + geometry.netBottomRightX) * 0.5
        let centerX =
            lerp(geometry.hoopCenterX, bottomCenter, progress)

        let topHalfWidth =
            (geometry.rightRimX - geometry.leftRimX) * 0.46
        let bottomHalfWidth =
            ((geometry.netBottomRightX - geometry.netBottomLeftX) * 0.5)
                .coerceAtLeast(r * 0.55)
        let halfWidth =
            lerp(topHalfWidth, bottomHalfWidth, progress)
                .coerceAtLeast(r * 0.55)

        let edgeDistance =
            abs(state.x - centerX) - halfWidth
        // Kotlin `edgeDistance in (-r * 1.15f)..(r * 1.25f)`.
        let touching =
            edgeDistance >= -r * 1.15 && edgeDistance <= r * 1.25

        var impact: Float =
            touching ? abs(state.vx) + abs(state.vy) * 0.16 : 0

        if state.made {
            // Strong but smooth horizontal drag makes the net catch the ball visually.
            let damping =
                exp((-NET_HORIZONTAL_DAMPING_PER_SEC * dtSeconds).toDouble())
                    .toFloat()
            state.vx *= damping
            state.vx +=
                (centerX - state.x) *
                    NET_CENTER_SPRING_PER_SEC2 *
                    dtSeconds

            // Prevent a very hard make from shooting through the side of the net.
            let maxOffset = halfWidth + r * 0.35
            let offset = state.x - centerX
            if abs(offset) > maxOffset {
                state.x =
                    centerX + offset.ksign * maxOffset
                impact = kmax(impact, abs(state.vx))
                state.vx = -state.vx * NET_SIDE_RESTITUTION
            }

            // Once below the rim, the net should never throw the ball back upwards.
            if state.y > geometry.hoopY + r * 0.35 && state.vy < 0 {
                state.vy *= 0.35
            }
        }

        return NetContact(touching: touching, impactSpeed: impact)
    }

    private static func distance(
        _ x1: Float,
        _ y1: Float,
        _ x2: Float,
        _ y2: Float
    ) -> Float {
        let dx = x2 - x1
        let dy = y2 - y1
        return ksqrt(dx * dx + dy * dy)
    }

    private static func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float {
        return a + (b - a) * t.coerceIn(0, 1)
    }

    private static let MIN_PULL_FOR_BOARD_CLEARANCE: Float = 0.62
    private static let MIN_TRICK_FLIGHT_SECONDS: Float = 1.44
    private static let MAX_TRICK_FLIGHT_SECONDS: Float = 2.12
    private static let TRICK_FLIGHT_SEARCH_STEP_SECONDS: Float = 0.045
    private static let BOARD_CLEARANCE_BALL_RADII: Float = 1.35

    // Automatic side-arc tuning. These only affect steep right-side camera angles.
    private static let SIDE_ARC_MAX_HORIZONTAL_OPENINGS: Float = 0.92
    private static let SIDE_ARC_MIN_VERTICAL_OPENINGS: Float = 2.20
    private static let SIDE_ARC_OPENING_FRACTION: Float = 0.62
    private static let HIGH_LOB_SIDE_CURVE_OPENING_FRACTION: Float = 0.82

    private static let POWER_ERROR_TO_SPEED: Float = 0.23
    private static let DISTANCE_POWER_SPREAD: Float = 0.035

    private static let ONE_ON_ONE_MAKE_RIM_CLEARANCE_SCALE: Float = 1.02
    private static let ONE_ON_ONE_MAX_COMPACT_MAKE_FLIGHT_SECONDS: Float = 1.34
    private static let ONE_ON_ONE_MAKE_FLIGHT_SEARCH_STEP_SECONDS: Float = 0.012
    private static let ONE_ON_ONE_MAKE_RIM_CLEARANCE_SAMPLES = 18
    private static let ONE_ON_ONE_MIN_DESCENDING_TARGET_SPEED: Float = 70

    private static let RIM_RESTITUTION: Float = 0.70
    private static let RIM_TANGENTIAL_DAMPING: Float = 0.985
    private static let BACKBOARD_RESTITUTION: Float = 0.72
    private static let BACKBOARD_VERTICAL_DAMPING: Float = 0.96

    private static let NET_HORIZONTAL_DAMPING_PER_SEC: Float = 7.5
    private static let NET_CENTER_SPRING_PER_SEC2: Float = 4.2
    private static let NET_SIDE_RESTITUTION: Float = 0.18
}

extension TripleShotPhysics.Geometry {
    /// Kotlin positional constructor form, e.g. `Geometry(1200f, 750f, 340f, ..., 20f)`.
    init(
        _ gravityPxPerSec2: Float,
        _ hoopCenterX: Float,
        _ hoopY: Float,
        _ leftRimX: Float,
        _ rightRimX: Float,
        _ rimColliderRadius: Float,
        _ backboardX: Float,
        _ backboardTopY: Float,
        _ backboardBottomY: Float,
        _ netBottomY: Float,
        _ netBottomLeftX: Float,
        _ netBottomRightX: Float,
        _ ballRadius: Float
    ) {
        self.init(
            gravityPxPerSec2: gravityPxPerSec2,
            hoopCenterX: hoopCenterX,
            hoopY: hoopY,
            leftRimX: leftRimX,
            rightRimX: rightRimX,
            rimColliderRadius: rimColliderRadius,
            backboardX: backboardX,
            backboardTopY: backboardTopY,
            backboardBottomY: backboardBottomY,
            netBottomY: netBottomY,
            netBottomLeftX: netBottomLeftX,
            netBottomRightX: netBottomRightX,
            ballRadius: ballRadius
        )
    }
}
