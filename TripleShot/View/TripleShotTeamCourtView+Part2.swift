import Foundation

// Port of view/TripleShotTeamCourtView.kt (Android 6c38131), LINES 2328-4096, statement by statement
// (spec 12-team2). Part 2 of the split class (DESIGN 2.9/2.10): the class, every stored property, the nested types of
// lines 1-2327 and the `override func onDraw(_:) { onDraw_impl(_:) }` stub live in TripleShotTeamCourtView.swift
// (part 1). This file holds only methods, the nested `Transform` type (Kotlin L3786) and the companion object as
// static members.
//
// Units are Android pixels (DESIGN 2.5): `width`/`height`, `dp()`, every view-space point and `jumpPx` are px, so
// `dp(gap) / transform().scaleX` and every other formula keep Android's density handling.
//
// Fidelity notes (code wins over comments and over the spec text):
// * Kotlin `Float` maths stays `Float` in the same operation order; kotlin.math functions on Float go through the
//   AndroidKit k-functions (computed in Double like the JVM): `ksqrt`, `khypot`, `kpow`, `ksin`, `kexp`, `kmax`/`kmin`
//   (Math.max/min on Float).
// * `Int * Float` promotes the Int (`.toFloat()`), `Long - Float` is a Float operation, `Long / Float` converts the
//   Long first.
// * Kotlin `minByOrNull/maxByOrNull` = AndroidKit `kMinBy/kMaxBy` (first extreme wins); `sortedBy` = `kSortedBy`
//   (stable); `String < String` = `javaPrecedes`.
// * Every `random.nextFloat()` is drawn exactly where Kotlin's short-circuit evaluation draws it.
// * `chooseHelpDefender` (L2502-2507): Kotlin parses `assignmentThreat * if (stat) 54f else 44f - distance * 0.035f`
//   as `assignmentThreat * (if (stat) 54f else (44f - distance * 0.035f))` (the else branch takes the rest of the
//   expression; verified with kotlinc 2.3.21). Spec 12 §4.6/§7.3 reads it as separate terms; the Kotlin parse is
//   ported.
// * `postAction` callbacks are never cancelled; their guards are kept exactly (spec 12 §4.4).

extension TripleShotTeamCourtView {

    // MARK: - Opponent ball-handler helpers (L2328-2444)

    func startAiPumpFake(handler: Actor, defender: Actor, now: Int64) {
        if !handler.hasBall || ballInFlight { return }
        handler.motion = TripleShotPlayerRenderer.Motion.SHOT_LOW
        handler.actionLockUntil = now + 520
        let fakeRead: Float =
            (defender.profile.ratings.defense.toFloat() * 0.42 + defender.profile.ratings.agility.toFloat() * 0.32) / 100
        if random.nextFloat() < (0.52 - fakeRead * 0.22).coerceIn(0.18, 0.48) {
            beginDefensiveJump(actor: defender, motion: TripleShotPlayerRenderer.Motion.BLOCK)
            defender.screenedUntil = max(defender.screenedUntil, now + 420)
        }
        postAction(action: { [self] in
            if handler.hasBall && !ballInFlight && handler.motion == TripleShotPlayerRenderer.Motion.SHOT_LOW {
                handler.motion = TripleShotPlayerRenderer.Motion.DRIBBLE
                invalidate()
            }
        }, delay: 430)
    }

    func aiShotQuality(actor: Actor) -> Float {
        let dist = distanceToHoop(a: actor)
        let zoneRating: Int =
            dist < 165 ? actor.profile.ratings.inside
            : dist < 335 ? actor.profile.ratings.midRange
            : actor.profile.ratings.threePoint
        let shootingRating: Float = zoneRating.toFloat() / 100
        let offense: Float = actor.profile.ratings.offense.toFloat() / 100
        let openness: Float = 1 - contest01(shooter: actor)
        let distancePenalty: Float = dist < 165 ? 0 : dist < 335 ? 0.04 : 0.08
        let quality: Float =
            0.08 + shootingRating * 0.58 + offense * 0.13 + openness * 0.27 - distancePenalty
        return quality.coerceIn(0.08, 0.95)
    }

    /**
     * The current character model has no dedicated PASSING/VISION field. Ball handling, offense and
     * agility therefore form a local proxy until the roster model is deliberately extended.
     */
    func passingSkillProxy(actor: Actor) -> Float {
        let ratings = actor.profile.ratings
        let sum: Float =
            ratings.ballHandling.toFloat() * 0.48 + ratings.offense.toFloat() * 0.30 + ratings.agility.toFloat() * 0.22
        return sum / 100
    }

    /** Local ownership hook: H0 is the real player in bot-team matches. */
    func isHumanOwned(actor: Actor) -> Bool { return actor.id == "H0" }

    func aiPassScore(from: Actor, to: Actor) -> Float {
        let receiverDefenderDistance: Float =
            nearestDefender(actor: to, maxSource: 1000).map { distance(a: to, b: $0) } ?? 999
        let openness: Float = ((receiverDefenderDistance - 65) / 180).coerceIn(0, 1)
        let receiverShot = aiShotQuality(actor: to)
        let lane = passLaneSafety(from: from, to: to)
        let progress: Float = (1 - distanceToHoop(a: to) / 520).coerceIn(0, 1)
        let humanInvolvement: Float = (to.team == from.team && isHumanOwned(actor: to)) ? 0.16 : 0
        let roleFit: Float
        switch to.role {
        case .POINT_GUARD: roleFit = from.role != .POINT_GUARD ? 0.055 : 0
        case .WING: roleFit = (to.profile.ratings.threePoint >= 72 && openness > 0.55) ? 0.045 : 0
        case .INTERIOR: roleFit = distanceToHoop(a: to) < 210 ? 0.055 : 0
        }
        let score: Float =
            receiverShot * 0.34 + openness * 0.27 + lane * 0.24 + progress * 0.11 + humanInvolvement + roleFit
        return score.coerceIn(0, 1)
    }

    func passLaneSafety(from: Actor, to: Actor) -> Float {
        let start = APointF(from.x, from.y)
        let end = APointF(to.x, to.y)
        let nearestPathDefender: Float = teamCourtPart2MinOrNull(
            actors
                .filter { $0.team != from.team }
                .map { distancePointToSegment(p: APointF($0.x, $0.y), a: start, b: end) }
        ) ?? 180
        let geometric: Float = ((nearestPathDefender - 28) / 125).coerceIn(0, 1)
        let skill = passingSkillProxy(actor: from)
        return (geometric * 0.82 + skill * 0.18).coerceIn(0, 1)
    }

    func driveAdvantage(attacker: Actor, defender: Actor?) -> Float {
        guard let defender = defender else { return 0.35 }
        let a = attacker.profile.ratings
        let attack: Float =
            a.speed.toFloat() * 0.18 +
            a.agility.toFloat() * 0.22 +
            a.strength.toFloat() * 0.18 +
            a.inside.toFloat() * 0.20 +
            a.offense.toFloat() * 0.22
        let d = defender.profile.ratings
        let defense: Float =
            d.speed.toFloat() * 0.12 +
            d.agility.toFloat() * 0.18 +
            d.strength.toFloat() * 0.15 +
            d.height.toFloat() * 0.10 +
            d.defense.toFloat() * 0.30 +
            d.blocking.toFloat() * 0.15
        return ((attack - defense) / 100).coerceIn(-0.35, 0.35)
    }

    func primaryDefenderFor(offense: Actor) -> Actor? {
        guard let id = defensiveAssignments.first(where: { $0.value == offense.id })?.key else { return nil }
        return actors.first(where: { $0.id == id })
    }

    // MARK: - Defense (L2446-2817)

    func updateOffBallAndDefense(now: Int64) {
        guard let liveOffense = possession else { return }
        let handler = currentBallHandler()

        let expectedDefenders = actors.filter { $0.team != liveOffense }.count
        let expectedDefendingTeam: Team = liveOffense == .HUMAN ? .OPPONENT : .HUMAN
        if defendingTeam != expectedDefendingTeam ||
            defensiveAssignments.count != expectedDefenders ||
            defensiveAssignments.values.contains(where: { id in
                !actors.contains(where: { $0.id == id && $0.team == liveOffense })
            }) {
            prepareDefenseForPossession(offenseTeam: liveOffense, now: now)
        }

        let assignments = assignmentActors()
        let helperId: String? =
            activeDefenseScheme == .MAN_TO_MAN ? chooseHelpDefender(assignments: assignments, handler: handler, now: now)
            : nil

        for actor in actors {
            if possession != liveOffense { return }
            if actor.controlled || actor.hasBall { continue }

            if actor.team == liveOffense {
                updateOffBallOffense(actor: actor, handler: handler, now: now)
            } else {
                guard let assigned = assignments[actor.id] else { continue }
                updateAiDefender(defender: actor, assigned: assigned, handler: handler, helping: helperId == actor.id,
                                 now: now)
            }
        }
    }

    func chooseHelpDefender(assignments: KLinkedMap<String, Actor>, handler: Actor?, now: Int64) -> String? {
        guard let handler = handler else { return nil }
        let handlerDefender = assignments.first(where: { $0.value.id == handler.id })?.key
        let primary = handlerDefender.flatMap { id in actors.first(where: { $0.id == id }) }
        let beaten: Bool
        if let primary = primary {
            beaten = distance(a: primary, b: handler) > 150
        } else {
            beaten = true
        }
        let rimPressure = distanceToHoop(a: handler) < 220
        let idleMs = handlerIdleMs(handler: handler, now: now)
        let stationaryDoubleTeam =
            handler.team == .HUMAN &&
            idleMs >= Self.TEAM_DOUBLE_TEAM_TRIGGER_MS &&
            abs(handler.vx) + abs(handler.vy) <= Self.STATIONARY_HANDLER_SOURCE_EPS
        if !beaten && !rimPressure && !stationaryDoubleTeam { return nil }

        let scored: [(String, Float)] = assignments
            .filter { entry in entry.key != handlerDefender && !entry.value.hasBall }
            .compactMap { entry -> (String, Float)? in
                let defenderId = entry.key
                let assignment = entry.value
                guard let defender = actors.first(where: { $0.id == defenderId }) else { return nil }
                if defender.controlled { return nil }
                let assignmentThreat = aiShotQuality(actor: assignment)
                let doubleTeamBonus: Float = stationaryDoubleTeam ? 24 : 0
                let defenseTerm: Float = defender.profile.ratings.defense.toFloat() * 0.48
                let agilityTerm: Float = defender.profile.ratings.agility.toFloat() * 0.28
                // Kotlin: `assignmentThreat * if (stationaryDoubleTeam) 54f else 44f - distance(defender, handler) * 0.035f`
                // = `assignmentThreat * (if (stationaryDoubleTeam) 54f else (44f - distance(defender, handler) * 0.035f))`.
                let threatWeight: Float = stationaryDoubleTeam ? 54 : 44 - distance(a: defender, b: handler) * 0.035
                let score: Float = defenseTerm + agilityTerm + doubleTeamBonus - assignmentThreat * threatWeight
                return (defenderId, score)
            }
        guard let best = scored.kMaxBy({ $0.1 }) else { return nil }
        let threshold: Float = stationaryDoubleTeam ? 3 : 9
        return best.1 > threshold ? best.0 : nil
    }

    func handlerIdleMs(handler: Actor, now: Int64) -> Int64 {
        let since = max(handler.possessionReceivedAt, handler.lastMeaningfulMovementAt)
        return (now - since).coerceAtLeast(0)
    }

    func updateAiDefender(
        defender: Actor,
        assigned: Actor,
        handler: Actor?,
        helping: Bool,
        now: Int64
    ) {
        if practiceQuiet { return }
        if activeDefenseScheme == .ZONE {
            /*
             * Zone still needs a real on-ball defender. The closest zone defender steps up and
             * applies the same screen-space pressure as man defense; the other two keep distinct
             * left/right/paint responsibilities instead of collapsing into the middle.
             */
            let liveHandler: Actor? = (handler?.hasBall == true) ? handler : nil
            let onBallId: String? = liveHandler.flatMap { zoneOnBallDefenderId(handler: $0) }
            if let liveHandler = liveHandler, onBallId == defender.id {
                let protectedHoop = attackingHoop(team: liveHandler.team)
                let hoopDx = protectedHoop.footX - liveHandler.x
                let hoopDy = protectedHoop.footY - liveHandler.y
                let hoopLen = ksqrt(hoopDx * hoopDx + hoopDy * hoopDy).coerceAtLeast(1)
                let shooterThreat: Float =
                    max(liveHandler.profile.ratings.midRange, liveHandler.profile.ratings.threePoint).toFloat() / 100
                let idleMs = handlerIdleMs(handler: liveHandler, now: now)
                let idlePressure01: Float =
                    ((idleMs - Self.TEAM_PRESSURE_TIGHTEN_START_MS).toFloat() /
                        (Self.TEAM_PRESSURE_TIGHTEN_FULL_MS - Self.TEAM_PRESSURE_TIGHTEN_START_MS).coerceAtLeast(1).toFloat())
                        .coerceIn(0, 1)
                let baseGapDp: Float = (61 - shooterThreat * 13).coerceIn(45, 61)
                let desiredGapDp: Float = (baseGapDp - idlePressure01 * 16).coerceAtLeast(30)
                let sourceGap = dp(v: desiredGapDp) / transform().scaleX.coerceAtLeast(0.001)
                let targetX = liveHandler.x + hoopDx / hoopLen * sourceGap
                let targetY = liveHandler.y + hoopDy / hoopLen * sourceGap
                let visualDistance = distanceView(a: viewPoint(actor: defender), b: viewPoint(actor: liveHandler))
                let urgency: Float =
                    (visualDistance > dp(v: 150) ? 1.22 : 1.04) + idlePressure01 * 0.14
                moveAiToward(actor: defender, tx: targetX, ty: targetY, speedScale: urgency)
                maybeAttemptAiSteal(defender: defender, handler: liveHandler, now: now, aggression01: idlePressure01)
            } else {
                let idleMs: Int64 = liveHandler.map { handlerIdleMs(handler: $0, now: now) } ?? 0
                let secondPressureId: String?
                if let liveHandler = liveHandler,
                   liveHandler.team == .HUMAN,
                   idleMs >= Self.TEAM_DOUBLE_TEAM_TRIGGER_MS {
                    secondPressureId = zoneSecondPressureDefenderId(handler: liveHandler, onBallId: onBallId)
                } else {
                    secondPressureId = nil
                }
                if let liveHandler = liveHandler, secondPressureId == defender.id {
                    let handlerView = viewPoint(actor: liveHandler)
                    let primary = onBallId.flatMap { id in actors.first(where: { $0.id == id }) }
                    let primaryView = primary.map { viewPoint(actor: $0) }
                    var vx: Float = primaryView.map { $0.x - handlerView.x } ?? 0
                    var vy: Float = primaryView.map { $0.y - handlerView.y } ?? -1
                    var len = ksqrt(vx * vx + vy * vy)
                    if len < 1 { vx = 0; vy = -1; len = 1 }
                    let gapPx = dp(v: 42)
                    let targetView = APointF(
                        handlerView.x - vx / len * gapPx,
                        handlerView.y - vy / len * gapPx
                    )
                    let sourceTarget = viewToSource(x: targetView.x, y: targetView.y)
                    moveAiToward(actor: defender, tx: sourceTarget.x, ty: sourceTarget.y, speedScale: 1.02)
                    defender.facing = stableIdleFacingTowardPoint(actor: defender, targetX: liveHandler.x,
                                                                  targetY: liveHandler.y)
                    maybeAttemptAiSteal(defender: defender, handler: liveHandler, now: now, aggression01: 0.55)
                } else {
                    let target = zoneDefenseTarget(defender: defender, assigned: assigned, handler: liveHandler)
                    let screenedScale: Float = defender.screenedUntil > now ? 0.40 : 0.86
                    moveAiToward(actor: defender, tx: target.x, ty: target.y, speedScale: screenedScale)
                }
            }
            return
        }

        let protectedHoop = attackingHoop(team: assigned.team)

        // The primary on-ball defender must actually GUARD the ball. Source-space gaps became
        // visually huge once the camera zoomed in, which is why a human handler could stand still
        // for seconds while the bot watched from several body lengths away. Keep the basketball
        // gap in screen dp, convert it back to court coordinates, and close it assertively.
        if assigned.hasBall {
            let hoopDxLive = protectedHoop.footX - assigned.x
            let hoopDyLive = protectedHoop.footY - assigned.y
            let hoopLenLive = ksqrt(hoopDxLive * hoopDxLive + hoopDyLive * hoopDyLive).coerceAtLeast(1)
            let shooterThreat: Float =
                max(assigned.profile.ratings.midRange, assigned.profile.ratings.threePoint).toFloat() / 100
            let idleMs = handlerIdleMs(handler: assigned, now: now)
            let idlePressure01: Float =
                ((idleMs - Self.TEAM_PRESSURE_TIGHTEN_START_MS).toFloat() /
                    (Self.TEAM_PRESSURE_TIGHTEN_FULL_MS - Self.TEAM_PRESSURE_TIGHTEN_START_MS).coerceAtLeast(1).toFloat())
                    .coerceIn(0, 1)
            // A stationary dribbler gradually loses cushion. We do NOT jump immediately to a steal;
            // the defender first closes the gap, then reaches more often if the handler keeps doing
            // nothing. This creates the requested basketball escalation instead of an arcade trap.
            let baseGapDp: Float = (58 - shooterThreat * 12).coerceIn(44, 58)
            let desiredGapDp: Float = (baseGapDp - idlePressure01 * 17).coerceAtLeast(29)
            let sourceGap = dp(v: desiredGapDp) / transform().scaleX.coerceAtLeast(0.001)
            let targetX = assigned.x + hoopDxLive / hoopLenLive * sourceGap
            let targetY = assigned.y + hoopDyLive / hoopLenLive * sourceGap
            let visualDistance = distanceView(a: viewPoint(actor: defender), b: viewPoint(actor: assigned))
            let closeUrgency: Float =
                (visualDistance > dp(v: 150) ? 1.22 : 1.06) + idlePressure01 * 0.16
            moveAiToward(actor: defender, tx: targetX, ty: targetY, speedScale: closeUrgency)
            maybeAttemptAiSteal(defender: defender, handler: assigned, now: now, aggression01: idlePressure01)
            return
        }

        if helping, let handler = handler, handler.hasBall {
            let idleMs = handlerIdleMs(handler: handler, now: now)
            if handler.team == .HUMAN &&
                idleMs >= Self.TEAM_DOUBLE_TEAM_TRIGGER_MS &&
                abs(handler.vx) + abs(handler.vy) <= Self.STATIONARY_HANDLER_SOURCE_EPS {
                let handlerView = viewPoint(actor: handler)
                let primary = primaryDefenderFor(offense: handler)
                let primaryView = primary.map { viewPoint(actor: $0) }
                var vx: Float = primaryView.map { $0.x - handlerView.x } ?? 0
                var vy: Float = primaryView.map { $0.y - handlerView.y } ?? -1
                var len = ksqrt(vx * vx + vy * vy)
                if len < 1 { vx = 0; vy = -1; len = 1 }
                // Arrive from the opposite shoulder so the double-team looks purposeful rather than
                // like two defenders stacking on one pixel.
                let gapPx = dp(v: 39)
                let targetView = APointF(
                    handlerView.x - vx / len * gapPx,
                    handlerView.y - vy / len * gapPx
                )
                let sourceTarget = viewToSource(x: targetView.x, y: targetView.y)
                moveAiToward(actor: defender, tx: sourceTarget.x, ty: sourceTarget.y, speedScale: 1.10)
                defender.facing = stableIdleFacingTowardPoint(actor: defender, targetX: handler.x, targetY: handler.y)
                let aggression: Float =
                    ((idleMs - Self.TEAM_DOUBLE_TEAM_TRIGGER_MS).toFloat() / 1800).coerceIn(0.45, 1)
                maybeAttemptAiSteal(defender: defender, handler: handler, now: now, aggression01: aggression)
                return
            }
        }

        let hoopDx = protectedHoop.footX - assigned.x
        let hoopDy = protectedHoop.footY - assigned.y
        let hoopLen = ksqrt(hoopDx * hoopDx + hoopDy * hoopDy).coerceAtLeast(1)
        let shooterThreat: Float =
            max(assigned.profile.ratings.midRange, assigned.profile.ratings.threePoint).toFloat() / 100
        // Off-ball denial distance also lives in screen dp. Source-space gaps expand with camera zoom
        // and were pushing defenders so far away that they disappeared from the active half court.
        let gapDp: Float = (70 - shooterThreat * 16).coerceIn(50, 70)
        let gapSource = dp(v: gapDp) / transform().scaleX.coerceAtLeast(0.001)
        var targetX = assigned.x + hoopDx / hoopLen * gapSource
        var targetY = assigned.y + hoopDy / hoopLen * gapSource

        // One helper only. The helper still keeps a foot in its own matchup so an ordinary drive does
        // not collapse all three defenders into the same pixel.
        if helping, let handler = handler {
            let helpHoop = attackingHoop(team: handler.team)
            let helpDx = helpHoop.footX - handler.x
            let helpDy = helpHoop.footY - handler.y
            let helpLen = ksqrt(helpDx * helpDx + helpDy * helpDy).coerceAtLeast(1)
            let helpX = handler.x + helpDx / helpLen * 82
            let helpY = handler.y + helpDy / helpLen * 82
            targetX = targetX * 0.62 + helpX * 0.38
            targetY = targetY * 0.62 + helpY * 0.38
        }

        let separated = applyTeammateSpacing(actor: defender, target: APointF(targetX, targetY), defenseSpacing: true)
        let screenedScale: Float = defender.screenedUntil > now ? 0.36 : 0.90
        moveAiToward(actor: defender, tx: separated.x, ty: separated.y, speedScale: screenedScale)

        // Unreachable on Android too (assigned.hasBall returned above); kept statement by statement.
        if assigned.hasBall { maybeAttemptAiSteal(defender: defender, handler: assigned, now: now) }
    }

    func zoneBaseAnchor(defender: Actor) -> APointF {
        let hoop = defendingHoop(team: defender.team)
        let towardCenter = towardCenterSign(hoop: hoop)
        let mirror: Float = defender.team == .HUMAN ? 1 : -1
        let anchor: APointF
        switch defender.role {
        case .INTERIOR:
            anchor = APointF(hoop.footX, hoop.footY + towardCenter * 96)
        case .WING:
            anchor = APointF(hoop.footX + mirror * 165, hoop.footY + towardCenter * 162)
        case .POINT_GUARD:
            anchor = APointF(hoop.footX - mirror * 205, hoop.footY + towardCenter * 220)
        }
        return clampPointToPlayable(point: anchor)
    }

    func zoneOnBallDefenderId(handler: Actor) -> String? {
        return actors
            .filter { $0.team != handler.team }
            .kMinBy { defender -> Float in
                let anchor = zoneBaseAnchor(defender: defender)
                let dx = handler.x - anchor.x
                let dy = (handler.y - anchor.y) * 0.78
                return dx * dx + dy * dy
            }?
            .id
    }

    func zoneSecondPressureDefenderId(handler: Actor, onBallId: String?) -> String? {
        return actors
            .filter { $0.team != handler.team && $0.id != onBallId && !$0.controlled }
            .kMinBy { distanceView(a: viewPoint(actor: $0), b: viewPoint(actor: handler)) }?
            .id
    }

    /**
     * 3v3 2-1 zone shell:
     * - INTERIOR protects the paint,
     * - WING owns one elbow/side,
     * - POINT_GUARD owns the opposite higher side/perimeter.
     *
     * The whole shell slides toward the live ball only a limited amount, so three defenders never
     * turn into one pile in the middle. The closest defender is separately promoted to on-ball
     * pressure by [zoneOnBallDefenderId].
     */
    func zoneDefenseTarget(defender: Actor, assigned: Actor, handler: Actor?) -> APointF {
        let anchor = zoneBaseAnchor(defender: defender)

        var x = anchor.x
        var y = anchor.y

        if let live = handler {
            // Slide the shell, but cap the movement so the three zone lanes remain visibly distinct.
            x += (live.x - anchor.x).coerceIn(-120, 120) * 0.36
            y += (live.y - anchor.y).coerceIn(-95, 95) * 0.32
        }

        // Shade a nearby assigned threat without abandoning the defender's zone.
        let assignedDx = assigned.x - anchor.x
        let assignedDy = assigned.y - anchor.y
        if ksqrt(assignedDx * assignedDx + assignedDy * assignedDy) < 245 {
            x += assignedDx * 0.14
            y += assignedDy * 0.12
        }

        return clampPointToPlayable(point: APointF(x, y))
    }

    func maybeAttemptAiSteal(
        defender: Actor,
        handler: Actor,
        now: Int64,
        aggression01: Float = 0
    ) {
        let aggression = aggression01.coerceIn(0, 1)
        let retryMs: Int64 = (Self.TEAM_STEAL_RETRY_MS.toFloat() - aggression * 360).toLong().coerceAtLeast(560)
        if now - defender.lastStealAttempt < retryMs { return }

        // Reach is in court metres, like collision. Camera zoom never changes the rules.
        let gap = floorDistance(a: defender, b: handler)
        let idleMs = handlerIdleMs(handler: handler, now: now)
        if handler.team == .HUMAN && idleMs < Self.TEAM_STEAL_PATIENCE_MS && gap > 0.9 { return }
        let reach: Float = 1.15 + defender.profile.ratings.stealing.toFloat() * 0.003 + aggression * 0.15
        if gap > reach { return }

        defender.lastStealAttempt = now
        defender.facing = facingTowardActor(actor: defender, target: handler)
        defender.motion = TripleShotPlayerRenderer.Motion.STEAL
        defender.actionLockUntil = now + 390

        let steal: Float =
            defender.profile.ratings.stealing.toFloat() * 0.50 +
            defender.profile.ratings.agility.toFloat() * 0.24 +
            defender.profile.ratings.defense.toFloat() * 0.12
        let protect: Float =
            handler.profile.ratings.ballHandling.toFloat() * 0.52 +
            handler.profile.ratings.agility.toFloat() * 0.16 +
            handler.profile.ratings.strength.toFloat() * 0.10
        let chance: Float =
            (((steal - protect + 25) / 100) + aggression * 0.10)
                .coerceIn(0.04, 0.52)
        let success = random.nextFloat() < chance

        if success {
            // Show the steal action before transferring the ball. This makes the cause of the
            // turnover readable instead of making the ball suddenly appear in another sprite.
            handler.actionLockUntil = max(handler.actionLockUntil, now + 190)
            postAction(action: { [self] in
                if handler.hasBall && possession == handler.team {
                    handler.hasBall = false
                    giveBall(actor: defender)
                    listener?.onStatus(
                        message: context.getString(
                            defender.team == .HUMAN ? R.string.minik_swish_team_steal_success
                            : R.string.minik_swish_team_opponent_steal_success
                        ),
                        team: defender.team
                    )
                }
            }, delay: Self.STEAL_TRANSFER_DELAY_MS)
        } else {
            postAction(action: {
                if !defender.hasBall && defender.motion == TripleShotPlayerRenderer.Motion.STEAL {
                    defender.motion = TripleShotPlayerRenderer.Motion.IDLE
                }
            }, delay: 390)
        }
    }

    // MARK: - Off-ball offense (L2819-3070)

    func beginCut(actor: Actor, now: Int64) {
        actor.screenTargetId = nil
        actor.screenHoldUntil = 0
        let hoop = attackingHoop(team: actor.team)
        let side: Float = actor.x < hoop.footX ? -1 : 1
        let depth: Float = actor.role == .INTERIOR ? 54 : 78
        actor.cutUntil = max(actor.cutUntil, now + BasketballMovement.cutDurationMillis(
            dx: hoop.footX + side * 72 - actor.x,
            dy: hoop.footY + towardCenterSign(hoop: hoop) * depth - actor.y,
            speed: actor.profile.ratings.speed, agility: actor.profile.ratings.agility))
    }

    func updateOffBallOffense(actor: Actor, handler: Actor?, now: Int64) {
        guard let handler = handler else { return }

        if let screenTargetId = actor.screenTargetId {
            let foundTarget = actors.first(where: { $0.id == screenTargetId })
            if foundTarget == nil || foundTarget?.team != actor.team {
                actor.screenTargetId = nil
            } else if let target = foundTarget {
                let defender = actors.filter({ $0.team != target.team }).kMinBy { floorDistance(a: target, b: $0) }
                if let defender = defender {
                    let tx = (target.x + defender.x) * 0.5
                    let ty = (target.y + defender.y) * 0.5
                    moveAiToward(actor: actor, tx: tx, ty: ty, speedScale: 0.78)
                    let a = viewPoint(actor: actor); let d = viewPoint(actor: defender)
                    let contactX = dp(v: collisionHalfWidthDp(actor: actor) + collisionHalfWidthDp(actor: defender))
                    let contactY = dp(v: collisionHalfDepthDp(actor: actor) + collisionHalfDepthDp(actor: defender))
                    let bodyGap = kpow(abs(a.x - d.x) / contactX, 4) + kpow(abs(a.y - d.y) / contactY, 4)
                    if bodyGap <= 1.55 {
                        if actor.screenPlantedAt == 0 { actor.screenPlantedAt = now }
                        actor.travelScale = 0
                        actor.motion = TripleShotPlayerRenderer.Motion.IDLE
                        if now - actor.screenPlantedAt < 180 { return }
                        // A planted screen is brief physical obstruction, not a moving stun.
                        actor.screenHoldUntil = now + 650
                        actor.screenPlantedAt = 0
                        let success = random.nextFloat() < BasketballMoves.screenChance(defense: defender.profile.ratings.defense)
                        if success { defender.screenedUntil = now + 1100 + random.nextInt(501).toLong() }
                        ALog.i("TRIPLE_PLAY", "screen actor=\(actor.id) frees=\(target.id)")
                        // Kotlin `if (requestedPracticeScreens.remove(actor.id)) practiceEvent(SCREEN)`:
                        // remove() is true exactly when the id was present.
                        if requestedPracticeScreens.contains(actor.id) {
                            requestedPracticeScreens.remove(actor.id)
                            practiceEvent(skill: BasketballSkill.SCREEN)
                        }
                        actor.screenTargetId = nil
                        actor.screenCooldownUntil = now + Self.TEAM_SCREEN_COOLDOWN_MS
                        if success {
                            maybeSwitchAssignmentsForScreen(screener: actor, ballHandler: target, screenedDefender: defender,
                                                            now: now)
                        }

                        // A real screen should create a second action, not end with the screener
                        // becoming a statue. Strong finishers often roll; others pop back into space.
                        let rollSkill: Float =
                            (actor.profile.ratings.inside.toFloat() * 0.34 +
                                actor.profile.ratings.speed.toFloat() * 0.18 +
                                actor.profile.ratings.agility.toFloat() * 0.18 +
                                actor.profile.ratings.offense.toFloat() * 0.18 +
                                actor.profile.ratings.jumping.toFloat() * 0.12) / 100
                        if !target.hasBall {
                            // Off-ball screen: the freed teammate cuts first, while the screener can
                            // still roll on a later decision if the possession remains live.
                            beginCut(actor: target, now: now)
                        } else if random.nextFloat() < (0.34 + rollSkill * 0.34).coerceIn(0.36, 0.70) {
                            postAction(action: { [self] in
                                if possession != nil && actors.contains(actor) { beginCut(actor: actor, now: gameTime()) }
                            }, delay: 650)
                        }
                    } else {
                        actor.screenPlantedAt = 0
                    }
                    return
                }
            }
        }

        if actor.cutUntil > now {
            let hoop = attackingHoop(team: actor.team)
            let side: Float = actor.x < hoop.footX ? -1 : 1
            let finishDepth: Float = actor.role == .INTERIOR ? 54 : 78
            let target = applyTeammateSpacing(
                actor: actor,
                target: APointF(
                    hoop.footX + side * 72,
                    hoop.footY + towardCenterSign(hoop: hoop) * finishDepth
                )
            )
            moveAiToward(actor: actor, tx: target.x, ty: target.y, speedScale: 1.02)
            return
        }

        maybePlanOffBallAction(actor: actor, handler: handler, now: now)
        if actor.screenTargetId != nil || actor.cutUntil > now { return }

        let target = offBallSpacingTarget(actor: actor, handler: handler)
        moveAiToward(actor: actor, tx: target.x, ty: target.y, speedScale: 0.54)
    }

    func maybePlanOffBallAction(actor: Actor, handler: Actor, now: Int64) {
        if now - actor.lastAiDecision < Self.TEAM_OFF_BALL_DECISION_MS { return }
        actor.lastAiDecision = now
        if now - possessionStartedAt < Self.TEAM_OFF_BALL_SETUP_GRACE_MS { return }

        // One deliberate special action at a time prevents the classic three-player blob.
        let activeTeamAction =
            actors.contains(where: {
                $0.id != actor.id &&
                    $0.team == actor.team &&
                    ($0.screenTargetId != nil || $0.cutUntil > now)
            })
        if activeTeamAction { return }

        let handlerDefender = actors.filter({ $0.team != handler.team }).kMinBy { floorDistance(a: handler, b: $0) }
        let handlerPressure: Float = handlerDefender.map { distance(a: handler, b: $0) } ?? 999
        // A trapped child gets a teammate's real, collision-tested screen, not an invisible boost.
        if handler.controlled, let handlerDefender = handlerDefender,
           floorDistance(a: handler, b: handlerDefender) < Float(1.85), now >= actor.screenCooldownUntil {
            actor.screenTargetId = handler.id
            actor.actionLockUntil = now + 950
            return
        }
        let screenAbility: Float =
            (actor.profile.ratings.strength.toFloat() * 0.42 +
                actor.profile.ratings.height.toFloat() * 0.24 +
                actor.profile.ratings.offense.toFloat() * 0.34) / 100
        let screenRoleBias: Float
        switch actor.role {
        case .POINT_GUARD: screenRoleBias = 0.34
        case .WING: screenRoleBias = 0.83
        case .INTERIOR: screenRoleBias = 1.12
        }

        /*
         * Screens are not restricted to the ball. Prefer the handler when pressured, otherwise a
         * tightly-guarded off-ball teammate can receive a pin/down screen and cut into the space it
         * creates. Only one team action is active at once, so this remains readable in 3v3.
         */
        let offBallScreenTarget: Actor? =
            actors
                .filter { $0.team == actor.team && $0.id != actor.id && $0.id != handler.id }
                .compactMap { mate -> (Actor, Float)? in
                    let mateDefender = primaryDefenderFor(offense: mate) ?? nearestDefender(actor: mate, maxSource: 1000)
                    let pressure: Float = mateDefender.map { distance(a: mate, b: $0) } ?? 999
                    return pressure < 118 ? (mate, pressure) : nil
                }
                .kMinBy { $0.1 }?
                .0
        let preferredScreenTarget: Actor
        if handlerPressure < 132 {
            preferredScreenTarget = handler
        } else if let offBallScreenTarget = offBallScreenTarget {
            preferredScreenTarget = offBallScreenTarget
        } else {
            preferredScreenTarget = handler
        }
        let targetPressure: Float =
            preferredScreenTarget.id == handler.id ? handlerPressure
            : primaryDefenderFor(offense: preferredScreenTarget).map { distance(a: preferredScreenTarget, b: $0) } ?? 999

        if now >= actor.screenCooldownUntil &&
            screenAbility > 0.46 &&
            distance(a: actor, b: preferredScreenTarget) < 390 &&
            (targetPressure < 138 || now - trackedHandlerSince >= 1550) &&
            random.nextFloat() < (0.18 + screenAbility * 0.24) * screenRoleBias {
            actor.screenTargetId = preferredScreenTarget.id
            actor.actionLockUntil = now + 950
            return
        }

        let ownDefender = primaryDefenderFor(offense: actor) ?? nearestDefender(actor: actor, maxSource: 1000)
        let ownSpace: Float = ownDefender.map { distance(a: actor, b: $0) } ?? 999
        let cutAbility: Float =
            (actor.profile.ratings.speed.toFloat() * 0.22 +
                actor.profile.ratings.agility.toFloat() * 0.24 +
                actor.profile.ratings.inside.toFloat() * 0.25 +
                actor.profile.ratings.offense.toFloat() * 0.19 +
                actor.profile.ratings.jumping.toFloat() * 0.10) / 100
        let cutRoleBias: Float
        switch actor.role {
        case .POINT_GUARD: cutRoleBias = 0.38
        case .WING: cutRoleBias = 0.78
        case .INTERIOR: cutRoleBias = 1.18
        }
        if ownSpace > 120 &&
            cutAbility > 0.47 &&
            distanceToHoop(a: actor) > 145 &&
            random.nextFloat() < (0.10 + cutAbility * 0.18) * cutRoleBias {
            beginCut(actor: actor, now: now)
        }
    }

    /**
     * Stable role spacing for players who are currently off the ball.
     *
     * This target must NOT animate every frame. The previous implementation used a sine wave based
     * on `now`, so an otherwise-open teammate was permanently chasing a moving point by a few source
     * pixels. At ~31fps that looked like the player was trembling / rapidly swapping direction even
     * while they were meant to be standing available for a pass.
     *
     * Real movement is already supplied by cuts, screens, defensive rotations and handler-relative
     * spacing. Here we keep the same average formation positions, but make the neutral target fixed
     * until basketball context actually changes.
     */
    func offBallSpacingTarget(actor: Actor, handler: Actor) -> APointF {
        let home = roleHomeSpot(team: actor.team, role: actor.role, attacking: true)
        let minX = playableMinX()
        let maxX = playableMaxX()
        let span = (maxX - minX).coerceAtLeast(180)

        let raw: APointF
        switch actor.role {
        case .POINT_GUARD:
            // Off-ball PG stays outside as the reset valve, offset from the current handler.
            let opposite: Float =
                handler.x > (minX + maxX) * 0.5 ? minX + span * 0.28
                : minX + span * 0.43
            raw = APointF(opposite, home.y)
        case .WING:
            // Hold the authored wide/corner home spot until a real cut or screen is planned.
            raw = APointF(home.x, home.y)
        case .INTERIOR:
            // Keep the previous animation's average short-seal depth, but make it stable.
            let insideIntent: Float =
                (actor.profile.ratings.inside +
                    actor.profile.ratings.height +
                    actor.profile.ratings.strength).toFloat() / 300
            let stepIn: Float = (34 + insideIntent * 46) * 0.5
            raw = APointF(home.x - stepIn * 0.35, home.y - stepIn)
        }
        return applyTeammateSpacing(actor: actor, target: raw)
    }

    /**
     * Steering-level separation complements physical collision. It starts before sprites overlap, so
     * teammates choose different lanes instead of waiting until resolveActorCollisions pushes them.
     */
    func applyTeammateSpacing(
        actor: Actor,
        target: APointF,
        defenseSpacing: Bool = false
    ) -> APointF {
        var x = target.x
        var y = target.y
        let desired: Float = defenseSpacing ? 102 : 118
        for mate in actors.filter({ $0.team == actor.team && $0.id != actor.id }) {
            let dx = actor.x - mate.x
            let dy = (actor.y - mate.y) * 0.72
            let d = ksqrt(dx * dx + dy * dy).coerceAtLeast(1)
            if d < desired {
                let strength = (desired - d) / desired
                x += dx / d * 74 * strength
                y += (dy / d) / 0.72 * 58 * strength
            }
        }
        return clampPointToPlayable(point: APointF(x, y))
    }

    func clampPointToPlayable(point: APointF) -> APointF {
        return APointF(
            point.x.coerceIn(playableMinX(), playableMaxX()),
            point.y.coerceIn(Self.SOURCE_PLAY_MIN_Y, Self.SOURCE_PLAY_MAX_Y)
        )
    }

    // MARK: - Rebounding (L3072-3189)

    func reboundRankScore(actor: Actor, targetX: Float, targetY: Float) -> Float {
        let dx = actor.x - targetX
        let dy = (actor.y - targetY) * 0.72
        let geometric = ksqrt(dx * dx + dy * dy)
        let reboundEdge = reboundSkillProxy(actor: actor) * 150
        let roleBonus: Float
        switch actor.role {
        case .INTERIOR: roleBonus = 38
        case .WING: roleBonus = 12
        case .POINT_GUARD: roleBonus = -10
        }
        return geometric - reboundEdge - roleBonus
    }

    /**
     * React while a shot is in the air. The two strongest/closest defenders normally crash the
     * glass in 3v3, the shooting team sends one offensive rebounder, and the remaining perimeter
     * player starts becoming an outlet/transition option. This is intentionally role-aware rather
     * than making all six sprites run under the rim.
     */
    func updateShotReboundAnticipation(now: Int64) {
        guard let shootingTeam = possession else { return }
        let hoop = attackingHoop(team: shootingTeam)
        let towardCenter = towardCenterSign(hoop: hoop)

        for team in Team.allCases {
            let candidates = actors.filter { $0.team == team && !$0.controlled }
            if candidates.isEmpty { continue }
            let ranked = candidates.kSortedBy { reboundRankScore(actor: $0, targetX: hoop.footX, targetY: hoop.footY) }
            let teamCount = actors.filter { $0.team == team }.count
            let crashCount: Int =
                (teamCount <= 2 ? 1 : team != shootingTeam ? 2 : 1).coerceAtMost(ranked.count)
            let crashers = Set(ranked.prefix(crashCount).map { $0.id })

            for actor in candidates {
                if crashers.contains(actor.id) {
                    let rankIndex = (ranked.firstIndex(where: { $0.id == actor.id }) ?? -1).coerceAtLeast(0)
                    let side: Float = rankIndex % 2 == 0 ? -1 : 1
                    let target = APointF(
                        hoop.footX + side * (50 + rankIndex.toFloat() * 28),
                        hoop.footY + towardCenter * (54 + rankIndex.toFloat() * 24)
                    )
                    moveAiToward(actor: actor, tx: target.x, ty: target.y,
                                 speedScale: 0.94 + reboundSkillProxy(actor: actor) * 0.14)
                    actor.facing = stableIdleFacingTowardPoint(actor: actor, targetX: hoop.rimX, targetY: hoop.rimY)
                    if abs(ballSourceY - hoop.rimY) < 88 &&
                        ksqrt(
                            kpow(actor.x - hoop.footX, 2) +
                                kpow((actor.y - hoop.footY) * 0.72, 2)
                        ) < 150 &&
                        actor.jumpUntil <= now {
                        beginDefensiveJump(actor: actor, motion: TripleShotPlayerRenderer.Motion.REBOUND)
                    }
                } else {
                    // Do not stand behind the rebounders. Perimeter players open a passing lane
                    // toward mid-court so a clean board can immediately become transition offense.
                    let outletSide: Float = actor.x < hoop.footX ? -1 : 1
                    let outlet = APointF(
                        hoop.footX + outletSide * 205,
                        hoop.footY + towardCenter * 245
                    )
                    moveAiToward(actor: actor, tx: outlet.x, ty: outlet.y, speedScale: 0.62)
                    actor.facing = stableIdleFacingTowardPoint(actor: actor, targetX: hoop.rimX, targetY: hoop.rimY)
                }
            }
        }
    }

    /** Rebound chase balances distance with jump/size/strength instead of sending a whole team. */
    func updateAiLooseBallChase(now: Int64) {
        if !ballVisible { return }
        let shootingTeam = possession

        for team in Team.allCases {
            let candidates = actors.filter { $0.team == team && !$0.controlled }
            if candidates.isEmpty { continue }
            let ranked = candidates.kSortedBy { reboundRankScore(actor: $0, targetX: ballSourceX, targetY: ballSourceY) }
            let teamCount = actors.filter { $0.team == team }.count
            let chaseCount: Int =
                (teamCount <= 2 ? 1 : team != shootingTeam ? 2 : 1).coerceAtMost(ranked.count)
            let chasers = Array(ranked.prefix(chaseCount))

            for chaser in chasers {
                let dx = chaser.x - ballSourceX
                let dy = chaser.y - ballSourceY
                let close = ksqrt(dx * dx + dy * dy) < 170
                if close && ballSourceY < chaser.y - 62 && chaser.jumpUntil <= now {
                    beginDefensiveJump(actor: chaser, motion: TripleShotPlayerRenderer.Motion.REBOUND)
                }
                moveAiToward(
                    actor: chaser,
                    tx: ballSourceX,
                    ty: ballSourceY,
                    speedScale: 1.08 + reboundSkillProxy(actor: chaser) * 0.14
                )
            }

            for outlet in ranked.dropFirst(chaseCount) {
                let hoop = shootingTeam.map { attackingHoop(team: $0) } ?? defendingHoop(team: team)
                let towardCenter = towardCenterSign(hoop: hoop)
                let side: Float = outlet.x < hoop.footX ? -1 : 1
                let target = APointF(
                    hoop.footX + side * 220,
                    hoop.footY + towardCenter * 260
                )
                moveAiToward(actor: outlet, tx: target.x, ty: target.y, speedScale: 0.58)
            }
        }
    }

    // MARK: - Movement, collisions, turnover (L3191-3274)

    func moveAiToward(actor: Actor, tx: Float, ty: Float, speedScale: Float) {
        actor.targetX = tx.coerceIn(Self.SOURCE_PLAY_MIN_X, Self.SOURCE_PLAY_MAX_X)
        actor.targetY = ty.coerceIn(Self.SOURCE_PLAY_MIN_Y, Self.SOURCE_PLAY_MAX_Y)
        actor.travelScale = speedScale.coerceIn(0, 1.35)
    }

    func advancePlannedMovement(now: Int64) {
        let dt: Float = movementAt == 0 ? Self.TEAM_FRAME_MS.toFloat() / 1000
            : ((now - movementAt).toFloat() / 1000).coerceIn(0, 0.08)
        movementAt = now
        for actor in actors {
            if actor.controlled { continue }
            let actionPose: Bool
            switch actor.motion {
            case .DUNK, .RELEASE, .SHOT_LOW, .SHOT_MID, .SHOT_SET, .BLOCK, .REBOUND: actionPose = true
            default: actionPose = false
            }
            if actor.travelScale <= 0 || now < actor.screenedUntil || now < actor.screenHoldUntil ||
                (actionPose && now < actor.actionLockUntil) ||
                (ballFlightKind == .PASS && actor.id == passReceiverId) {
                actor.vx = 0; actor.vy = 0
                continue
            }
            let step = BasketballMovement.step(
                dx: actor.targetX - actor.x, dy: actor.targetY - actor.y,
                speed: actor.profile.ratings.speed, agility: actor.profile.ratings.agility,
                scale: actor.travelScale * (1 + actor.boost01), dtSeconds: dt)
            let oldX = actor.x; let oldY = actor.y
            actor.x += step.x; actor.y += step.y
            clampActorToPlayableArea(actor: actor)
            resolveActorCollisions(moved: actor)
            actor.vx = actor.x - oldX; actor.vy = actor.y - oldY
            let moving = abs(actor.vx) + abs(actor.vy) > 0.1
            if moving { actor.lastMeaningfulMovementAt = now }
            if now - actor.lastStealAttempt > 360 && actor.jumpUntil <= now {
                actor.motion = actor.hasBall ? TripleShotPlayerRenderer.Motion.DRIBBLE
                    : moving ? TripleShotPlayerRenderer.Motion.WALK : TripleShotPlayerRenderer.Motion.IDLE
            }
            actor.facing = basketballFacing(actor: actor, moveDx: actor.vx, moveDy: actor.vy)
            if abs(step.x) > 1.4 { actor.mirror = step.x < 0 }
        }
    }

    func floorDistance(a: Actor, b: Actor) -> Float { return khypot((a.x - b.x) * 0.014, (a.y - b.y) * 0.034) }

    func resolveActorCollisions(moved: Actor) {
        // Stable floor footprints, independent of sprite frame, perspective and zoom.
        for _ in kuntil(0, 2) {
            for other in actors.filter({ $0.id != moved.id }) {
                var dx = (moved.x - other.x) * 0.014
                let dz = (moved.y - other.y) * 0.034
                var d = khypot(dx, dz)
                if d < 0.001 { dx = moved.id.javaPrecedes(other.id) ? 0.001 : -0.001; d = 0.001 }
                let gap: Float = 0.88
                if d < gap {
                    moved.x += dx / d * (gap - d) / 0.014
                    moved.y += dz / d * (gap - d) / 0.034
                }
            }
            clampActorToPlayableArea(actor: moved)
        }
    }

    func turnover(team: Team, english: String, hebrew: String) {
        BasketballSoundscape.effect(context: context, kind: BasketballSoundscape.Effect.WHISTLE)
        clearForQuestion()
        let message = ["he", "iw"].contains(resources.configuration.locales[0].language) ? hebrew : english
        listener?.onStatus(message: message, team: team)
        listener?.onDeadBall(defaultNextTeam: team == .HUMAN ? .OPPONENT : .HUMAN)
    }

    func collisionHalfWidthDp(actor: Actor) -> Float {
        switch actor.characterId {
        // Lateral protection is deliberately wider than front/back depth. The previous values
        // stopped center-on-center overlap but still let shoes/legs visually pass through each
        // other when approaching from the side.
        case "flare": return 49
        case "coach_67": return 43
        case "zephyr": return 45
        case "kyra": return 45
        default: return 44.5
        }
    }

    func collisionHalfDepthDp(actor: Actor) -> Float {
        switch actor.characterId {
        case "coach_67": return 29
        default: return 30
        }
    }

    // MARK: - Ball lifecycle (L3276-3405)

    func startLooseBall(x: Float, y: Float, vx: Float, vy: Float) {
        let source = viewToSource(x: x, y: y)
        let t = transform()
        startLooseBallSource(
            sourceX: source.x,
            sourceY: source.y,
            vxSource: vx / t.scaleX.coerceAtLeast(0.001),
            vySource: vy / t.scaleY.coerceAtLeast(0.001)
        )
    }

    func startLooseBallSource(
        sourceX: Float,
        sourceY: Float,
        vxSource: Float,
        vySource: Float
    ) {
        premiumLooseAt = ASystem.nanoTime()
        premiumLooseOrigin = worldScene?.balls.first?.owner == nil ? premiumFlightBall
            : (worldScene?.balls.first?.position ?? premiumFlightBall)
        for it in actors { it.hasBall = false }
        ballVisible = true
        ballInFlight = false
        ballFlightKind = .NONE
        looseBall = true
        ballSourceX = sourceX
        ballSourceY = sourceY
        ballCameraFocusX = sourceX
        ballCameraFocusY = sourceY
        looseVxSource = vxSource
        looseVySource = vySource
        looseLastNanos = 0
        updateCamera()
        syncBallViewFromSource()
        listener?.onStatus(message: context.getString(R.string.minik_swish_team_ball_loose), team: nil)
    }

    func updateLooseBall(now: Int64) {
        let dt: Float = looseLastNanos == 0 ? 0.016
            : ((ASystem.nanoTime() - looseLastNanos).toFloat() / 1_000_000_000).coerceIn(0.005, 0.035)
        looseLastNanos = ASystem.nanoTime()

        looseVySource += Self.SOURCE_BALL_GRAVITY * dt
        ballSourceX += looseVxSource * dt
        ballSourceY += looseVySource * dt

        let floorY = Self.SOURCE_PLAY_MAX_Y + 22
        if ballSourceY > floorY {
            ballSourceY = floorY
            if abs(looseVySource) > 70 { looseVySource = -abs(looseVySource) * 0.42 }
            else { looseVySource = 0 }
            looseVxSource *= 0.72
        }
        looseVxSource *= 0.985

        ballCameraFocusX = ballSourceX
        // Loose-ball physics still bounce, but damp the camera target toward the floor projection
        // so the viewport does not bounce one-for-one with the ball.
        let looseFloorY = Self.SOURCE_PLAY_MAX_Y + 22
        ballCameraFocusY += (looseFloorY.coerceAtMost(ballSourceY + 34) - ballCameraFocusY) * 0.20
        updateCamera()
        syncBallViewFromSource()

        let claimant = actors.kMinBy { actor -> Float in
            let dx = actor.x - ballSourceX
            let dy = actor.y - ballSourceY
            return ksqrt(dx * dx + dy * dy)
        }
        if let claimant = claimant {
            let dx = claimant.x - ballSourceX
            let dy = claimant.y - ballSourceY
            if ksqrt(dx * dx + dy * dy) < 72 {
                looseBall = false
                giveBall(actor: claimant, fromRebound: true)
                return
            }
        }

        if ballSourceX < -45 || ballSourceX > Self.SOURCE_W + 45 || ballSourceY > Self.SOURCE_H + 55 {
            looseBall = false
            ballVisible = false
            listener?.onDeadBall(defaultNextTeam: possession == .HUMAN ? .OPPONENT : .HUMAN)
        }
    }

    func giveBall(actor: Actor, fromRebound: Bool = false) {
        let previousTeam = possession
        let now = gameTime()
        for it in actors { it.hasBall = false }
        actor.hasBall = true
        actor.motion = TripleShotPlayerRenderer.Motion.DRIBBLE
        actor.facing = facingTowardAttackingHoop(actor: actor)
        actor.possessionReceivedAt = now
        actor.lastMeaningfulMovementAt = now
        if fromRebound { actor.lastReboundClaimAt = now }
        possession = actor.team
        ballVisible = true
        trackedHandlerId = actor.id
        trackedHandlerSince = now

        if previousTeam != actor.team || fromRebound || possessionStartedAt == 0 {
            possessionStartedAt = now
            prepareDefenseForPossession(offenseTeam: actor.team, now: now)
        }

        if actor.team == .HUMAN { setControlled(id: actor.id) }
        updateCamera()
        updateHeldBall()
        if previousTeam != actor.team { listener?.onPossessionChanged(team: actor.team) }
        invalidate()
    }

    func currentBallHandler() -> Actor? { return actors.first(where: { $0.hasBall }) }

    func updateHeldBall() {
        guard let handler = currentBallHandler() else { return }
        let held = heldBallFor(actor: handler)
        ballX = held.x
        ballY = held.y
    }

    func heldBallFor(actor: Actor) -> APointF {
        let p = sourceToView(x: actor.x, y: actor.y)
        let state = rendererState(actor: actor, p: p)
        return renderer.heldBallPosition(state: state)
    }

    func heldBallSourceFor(actor: Actor) -> APointF {
        let view = heldBallFor(actor: actor)
        return viewToSource(x: view.x, y: view.y)
    }

    // MARK: - Spatial queries and jumps (L3407-3491)

    /**
     * Pass/switch hit testing must follow the BODY, not just the feet anchor. The old 56dp circle
     * around the shoes made a perfectly natural tap on a teammate's torso/head miss completely.
     */
    func actorAt(x: Float, y: Float) -> Actor? {
        return actors
            .compactMap { actor -> (Actor, Float)? in
                guard let bounds = gpuWorld.actorBounds(actor: worldActor(actor: actor)) else { return nil }
                let nx = (x - bounds.centerX()) / (bounds.width() * 0.5 + dp(v: 8))
                let ny = (y - bounds.centerY()) / (bounds.height() * 0.5 + dp(v: 8))
                let score = nx * nx + ny * ny
                let controlledPenalty: Float = actor.controlled ? 2 : 0
                return abs(nx) <= 1 && abs(ny) <= 1 ? (actor, score + controlledPenalty) : nil
            }
            .kMinBy { $0.1 }?
            .0
    }

    func nearestDefender(actor: Actor, maxSource: Float) -> Actor? {
        return actors
            .filter { $0.team != actor.team }
            .map { ($0, distance(a: actor, b: $0)) }
            .filter { $0.1 <= maxSource }
            .kMinBy { $0.1 }?
            .0
    }

    /// No caller on Android (dead code, spec 12 §8.15); ported for a mechanical diff.
    func nearestDefenderToViewPoint(attackingTeam: Team, point: APointF, maxDp: Float) -> Actor? {
        return actors
            .filter { $0.team != attackingTeam }
            .map { ($0, distanceView(a: viewPoint(actor: $0), b: point)) }
            .filter { $0.1 <= dp(v: maxDp) }
            .kMinBy { $0.1 }?
            .0
    }

    func nearestDefenderToSourcePoint(attackingTeam: Team, point: APointF, maxSource: Float) -> Actor? {
        return actors
            .filter { $0.team != attackingTeam }
            .map { actor -> (Actor, Float) in
                let dx = actor.x - point.x
                let dy = actor.y - point.y
                return (actor, ksqrt(dx * dx + dy * dy))
            }
            .filter { $0.1 <= maxSource }
            .kMinBy { $0.1 }?
            .0
    }

    func interceptionChance(actor: Actor) -> Float {
        let sum: Float =
            actor.profile.ratings.stealing.toFloat() * 0.55 +
            actor.profile.ratings.agility.toFloat() * 0.25 +
            actor.profile.ratings.defense.toFloat() * 0.20
        return (sum / 100).coerceIn(0.10, 0.94)
    }

    func contest01(shooter: Actor) -> Float {
        guard let defender = nearestDefender(actor: shooter, maxSource: 260) else { return 0 }
        let d = distance(a: shooter, b: defender)
        let raw: Float = (1 - (d - 55) / 185).coerceIn(0, 1)
        let defense: Float = defender.profile.ratings.defense.toFloat() / 100
        return (raw * (0.55 + defense * 0.45)).coerceIn(0, 1)
    }

    func beginDefensiveJump(actor: Actor, motion: TripleShotPlayerRenderer.Motion) {
        actor.motion = motion
        beginActorJump(actor: actor, contested: true)
        actor.actionLockUntil = actor.jumpUntil
        let started = actor.jumpStarted
        postAction(action: {
            if actor.jumpStarted == started && actor.motion == motion {
                actor.motion = actor.hasBall ? TripleShotPlayerRenderer.Motion.DRIBBLE
                    : TripleShotPlayerRenderer.Motion.IDLE
                actor.actionLockUntil = 0
            }
        }, delay: actor.jumpUntil - started + 20)
    }

    func beginActorJump(actor: Actor, contested: Bool) {
        let now = gameTime()
        actor.jumpStarted = now
        let duration: Int64 = ["kyra", "zephyr"].contains(actor.characterId) ? 820 : contested ? 650 : 520
        actor.jumpUntil = now + duration
        let jumpRating: Float = actor.profile.ratings.jumping.toFloat() / 100
        let contestFactor: Float = contested ? 1.05 : 0.88
        actor.jumpPx = dp(v: (30 + jumpRating * 42) * contestFactor)
    }

    func updateJump(actor: Actor, now: Int64) {
        if actor.jumpUntil <= now {
            actor.jumpPx = 0
            return
        }
        let duration = (actor.jumpUntil - actor.jumpStarted).coerceAtLeast(1)
        let t: Float = ((now - actor.jumpStarted).toFloat() / duration.toFloat()).coerceIn(0, 1)
        let maxJump = dp(v: (28 + actor.profile.ratings.jumping.toFloat() * 0.46) * (1 + actor.boost01 * 0.5))
        actor.jumpPx = ksin(t * PI_F) * maxJump
    }

    // MARK: - Ball flight animator (L3493-3571)

    func animateBallArcSource(
        start: APointF,
        end: APointF,
        durationMs: Int64,
        apexSource: Float,
        cameraArcFollow01: Float = 0,
        worldStartOverride: CourtPoint? = nil,
        onFrame: ((Float, APointF) -> Void)? = nil,
        onEnd: @escaping () -> Void
    ) {
        cancelBallAnimator()
        let handler = currentBallHandler() ?? actors.kMinBy { actor -> Float in
            let held = heldBallSourceFor(actor: actor)
            return (held.x - start.x) * (held.x - start.x) + (held.y - start.y) * (held.y - start.y)
        }
        premiumFlightStart = worldStartOverride
            ?? handler.map {
                gpuWorld.actorSocket(actor: worldActor(actor: $0),
                                     inFront: $0.facing != TripleShotPlayerRenderer.Facing.BACK)
            }
            ?? premiumFlightBall
        let nearestHoop = [topHoop(), bottomHoop()].kMinBy { abs($0.rimY - end.y) }!
        if ballFlightKind == .SHOT || ballFlightKind == .ALLEY_OOP {
            let h = TripleShotWorldCoordinates.team(sourceX: nearestHoop.footX, sourceY: nearestHoop.footY,
                                                    lift: TripleShotWorldCoordinates.RIM_HEIGHT)
            premiumFlightEnd = CourtPoint(x: h.x + (end.x - nearestHoop.rimX) * 0.013,
                                          y: h.y - (end.y - nearestHoop.rimY) * 0.015,
                                          z: h.z)
        } else {
            let receiver = actors.kMinBy { a -> Float in
                let held = heldBallSourceFor(actor: a)
                return (held.x - end.x) * (held.x - end.x) + (held.y - end.y) * (held.y - end.y)
            }
            premiumFlightEnd = receiver.map {
                gpuWorld.actorSocket(actor: worldActor(actor: $0),
                                     inFront: $0.facing != TripleShotPlayerRenderer.Facing.BACK)
            } ?? TripleShotWorldCoordinates.team(sourceX: end.x, sourceY: end.y, lift: 1.4)
        }
        // Kotlin `ballAnimator = ValueAnimator.ofFloat(0f, 1f).apply { ...; start() }`: the apply block (including the
        // synchronous t = 0 update of start()) runs before the assignment, so ballAnimator is still null then.
        let animator = AValueAnimator.ofFloat(0, 1)
        animator.duration = durationMs
        animator.interpolator = ALinearInterpolator()
        animator.addUpdateListener { [self] animation in
            let t = animation.animatedValueFloat
            let sourceX = start.x + (end.x - start.x) * t
            let linearY = start.y + (end.y - start.y) * t
            let arc = 4 * t * (1 - t) * apexSource
            premiumFlightBall = CourtPoint(
                x: premiumFlightStart.x + (premiumFlightEnd.x - premiumFlightStart.x) * t,
                y: premiumFlightStart.y + (premiumFlightEnd.y - premiumFlightStart.y) * t + arc * 0.014,
                z: premiumFlightStart.z + (premiumFlightEnd.z - premiumFlightStart.z) * t)
            ballSourceX = sourceX
            ballSourceY = linearY - arc
            ballCameraFocusX = sourceX
            // Passes mostly follow their ground projection to avoid camera bobbing. Shots are
            // different: the viewer must actually see the ball rise. Blend part of the arc into
            // the camera focus so the frame lifts gently with the shot instead of letting the
            // ball or jumping shooter disappear out of the top edge.
            ballCameraFocusY = linearY - arc * cameraArcFollow01.coerceIn(0, 0.80)
            updateCamera()
            syncBallViewFromSource()
            onFrame?(t, APointF(ballSourceX, ballSourceY))
            invalidate()
        }
        // The Kotlin `object : AnimatorListenerAdapter() { private var cancelled = false ... }`.
        var cancelled = false
        animator.addListener(AAnimatorListenerAdapter(
            onEnd: { [self] _ in
                ballAnimator = nil
                if !cancelled { onEnd() }
            },
            onCancel: { _ in cancelled = true }
        ))
        animator.start()
        ballAnimator = animator
    }

    func setBallSource(sourceX: Float, sourceY: Float) {
        ballSourceX = sourceX
        ballSourceY = sourceY
        ballCameraFocusX = sourceX
        ballCameraFocusY = sourceY
        syncBallViewFromSource()
    }

    func syncBallViewFromSource() {
        if !ballVisible { return }
        let view = sourceToView(x: ballSourceX, y: ballSourceY)
        ballX = view.x
        ballY = view.y
    }

    func cancelBallAnimator() {
        ballAnimator?.cancel()
        ballAnimator = nil
    }

    // MARK: - Presentation (L3573-3645)

    /// Kotlin `leagueLabelColors = ownColor to rivalColor` (part 1 stores the Pair as `(first: Int, second: Int)?`).
    func setLeagueLabels(ownColor: Int, rivalColor: Int) {
        leagueLabelColors = (first: ownColor, second: rivalColor); invalidate()
    }

    func worldActor(actor: Actor) -> TripleShotWorldActor {
        let p = sourceToView(x: actor.x, y: actor.y)
        // `resources.displayMetrics.density` is the constant UIScreen scale (AResources.density).
        return TripleShotWorldActor(
            id: actor.id,
            position: TripleShotWorldCoordinates.team(sourceX: actor.x, sourceY: actor.y,
                                                      lift: actor.jumpPx / AResources.density * 0.012),
            state: rendererState(actor: actor, p: p),
            controlled: actor.controlled,
            team: actor.team == .HUMAN ? 1 : 2,
            label: leagueLabelColors != nil ? actor.profile.displayName : "",
            labelColor: leagueLabelColors.map { actor.team == .HUMAN ? $0.first : $0.second } ?? AColor.WHITE)
    }

    /// Body of the Kotlin `override fun onDraw(canvas: Canvas)` (L3583-3611); part 1's override forwards here
    /// (DESIGN 2.10). It draws nothing itself: it builds the world snapshot and presents it.
    func onDraw_impl(_ canvas: ACanvas) {
        super.onDraw(canvas)
        if width <= 0 || height <= 0 { return }
        let worldActors = actors.map { worldActor(actor: $0) }
        var worldBalls: [TripleShotWorldBall] = []
        worldBalls.reserveCapacity(1)
        let handler = currentBallHandler()
        if ballVisible {
            let actor = worldActors.first(where: { $0.id == handler?.id })
            let point: CourtPoint
            if ballInFlight {
                point = premiumFlightBall
            } else if looseBall {
                let target = TripleShotWorldCoordinates.team(sourceX: ballSourceX, sourceY: ballSourceY, lift: 0.21)
                let t: Float = ((ASystem.nanoTime() - premiumLooseAt).toFloat() / 450_000_000).coerceIn(0, 1)
                point = CourtPoint(x: premiumLooseOrigin.x + (target.x - premiumLooseOrigin.x) * t,
                                   y: premiumLooseOrigin.y + (target.y - premiumLooseOrigin.y) * t * t,
                                   z: premiumLooseOrigin.z + (target.z - premiumLooseOrigin.z) * t)
            } else if let actor = actor {
                point = gpuWorld.actorSocket(actor: actor, inFront: actor.state.facing != TripleShotPlayerRenderer.Facing.BACK)
            } else {
                point = TripleShotWorldCoordinates.team(sourceX: ballSourceX, sourceY: ballSourceY, lift: 0.17)
            }
            worldBalls.append(TripleShotWorldBall(
                position: point,
                resource: currentBallSkinResId,
                owner: !ballInFlight && !looseBall ? handler?.id : nil,
                inFront: actor?.state.facing != TripleShotPlayerRenderer.Facing.BACK))
        }
        let hoops = [topHoop(), bottomHoop()].map {
            TripleShotWorldCoordinates.team(sourceX: $0.footX, sourceY: $0.footY, lift: TripleShotWorldCoordinates.RIM_HEIGHT)
        }
        let scoredAge: Float = (ASystem.nanoTime() - premiumScoredAt).toFloat() / 1e9
        if !ballVisible && scoredAge < 0.30 {
            worldBalls.append(TripleShotWorldBall(
                position: premiumScoredPosition.copy(y: premiumScoredPosition.y - scoredAge * 3.7),
                resource: currentBallSkinResId,
                rotation: scoredAge * 240))
        }
        let sway: Float = scoredAge < 0.7 ? ksin(scoredAge * 35) * kexp(-scoredAge * 5) * 0.12 : 0
        present(scene: TripleShotWorldSnapshot(
            timeNanos: ASystem.nanoTime(),
            courtId: currentCourtStyleId,
            teamSize: teamSize,
            actors: worldActors,
            balls: worldBalls,
            hoops: hoops,
            atmosphere: courtAtmosphere,
            netSway: sway,
            activeHoopIndex: possession == .HUMAN ? 0 : 1))
    }

    func rendererState(actor: Actor, p: APointF) -> TripleShotPlayerRenderer.State {
        let pullBack: Float
        switch actor.motion {
        case .SHOT_LOW: pullBack = 0.08
        case .SHOT_MID: pullBack = 0.38
        case .SHOT_SET, .RELEASE: pullBack = 0.78
        default: pullBack = 0
        }
        // Kotlin passes pose after crossoverBehind and locomotionFrameIndex before movingFast; every argument is a plain
        // read (gameTime() has no side effects), so Swift's declaration order is used.
        let sinceSpin = gameTime() &- actor.spinAt
        let spinning = sinceSpin >= 0 && sinceSpin <= 479
        let facing: TripleShotPlayerRenderer.Facing
        if spinning {
            switch (sinceSpin / 120).toInt() {
            case 0, 2: facing = TripleShotPlayerRenderer.Facing.SIDE
            case 1: facing = TripleShotPlayerRenderer.Facing.FRONT
            default: facing = TripleShotPlayerRenderer.Facing.BACK
            }
        } else {
            facing = TripleShotPlayerRenderer.Facing.allCases[actor.visual.facing]
        }
        return TripleShotPlayerRenderer.State(
            x: p.x,
            footY: p.y - actor.jumpPx,
            fineAim: 0,
            pullBack: pullBack,
            dribbleBouncePx: dp(v: actor.dribbleBounce),
            hotHand: false,
            style: actor.team == .HUMAN ? TripleShotPlayerRenderer.Style.HUMAN : TripleShotPlayerRenderer.Style.BOT,
            pose: gameTime() < actor.fallenUntil ? TripleShotPlayerRenderer.Pose.LOSER : TripleShotPlayerRenderer.Pose.NORMAL,
            shotStyle: TripleShotPlayerRenderer.ShotStyle.PRO,
            facing: facing,
            motion: actor.motion,
            dribblePhase01: actor.dribblePhase,
            dribbleHandSign: actor.dribbleHandSign,
            crossoverProgress: ((gameTime() &- actor.crossAt).toFloat() / 420).coerceIn(0, 1),
            crossoverFrom: actor.crossFrom, crossoverBehind: actor.crossBehind,
            moving: actor.visual.moving && gameTime() >= actor.fallenUntil,
            movingFast: abs(actor.vx) + abs(actor.vy) > 11,
            locomotionFrameIndex: actor.visual.frameIndex,
            characterId: actor.characterId,
            mirrorX: spinning ? ((sinceSpin / 120 == 2) != (actor.spinSign < 0)) : actor.visual.mirror,
            // Camera zoom belongs to the WORLD, not to the sprite. Coupling these values was the
            // reason the court became larger but the people became larger too, preserving the
            // "giants on a tiny court" look. Keep player screen scale essentially stable.
            visualScale: Self.PLAYER_SCREEN_SCALE
        )
    }

    // MARK: - Legacy virtual camera and transforms (L3647-3862)

    /**
     * Full-court game camera. The focus is the LIVE BALL, not only the current handler.
     * Because airborne/loose balls now live in source coordinates the court can pan and zoom
     * underneath a pass, shot or transition without visually detaching the ball from its path.
     */
    func updateCamera(force: Bool = false) {
        if width <= 0 || height <= 0 { return }

        let handler = currentBallHandler()
        let followLiveBall = ballVisible && (ballInFlight || looseBall)
        let sourceX: Float = followLiveBall ? ballCameraFocusX : handler?.x ?? Self.FULL_COURT_CENTER_X
        let sourceY: Float = followLiveBall ? ballCameraFocusY : handler?.y ?? Self.FULL_COURT_CENTER_Y
        let portrait = resources.configuration.orientation != AConfiguration.ORIENTATION_LANDSCAPE

        // Follow lateral movement, but keep enough central court around the play that a pass does
        // not cause seasick side-to-side hunting. Y is followed much more strongly because that is
        // the full-court travel direction between baskets.
        let lateralFollow: Float = portrait ? 0.88 : 0.68
        let targetX = Self.FULL_COURT_CENTER_X + (sourceX - Self.FULL_COURT_CENTER_X) * lateralFollow

        // Optical framing: anchoring the actor's FEET exactly at 50% screen height makes the whole
        // body live too high. Move the camera center a small amount toward the top baseline so the
        // predicted landing/feet point sits just below center. Keep it subtle -- this is the
        // requested sweet spot, not another large zoom/pan change.
        let offense = possession
        let opticalLiftSource: Float
        if portrait {
            opticalLiftSource = offense == .HUMAN ? 20 : 12
        } else {
            // Keep the controlled offense lower in frame so there is real headroom for a jump
            // shot. Opponent offense keeps a more neutral framing and only receives extra room
            // when an actual shot arc rises.
            opticalLiftSource = offense == .HUMAN ? 52 : 20
        }
        var targetY = sourceY - opticalLiftSource

        // Show only the relevant part of the oversized court. Landscape needs a much stronger
        // optical crop than portrait because its base fit otherwise exposes almost the whole court.
        // This is intentionally closer to an action-game camera than a TV broadcast camera.
        let halfCourtProgress: Float =
            (abs(sourceY - Self.FULL_COURT_CENTER_Y) / 285).coerceIn(0, 1)
        // These values are intentionally close. Even at mid-court we no longer show a TV-style
        // overview; the camera should show a useful local window and physically travel to the next
        // area of play. Near a basket it closes in further.
        let transitionZoom: Float = portrait ? 1.92 : 2.58
        /*
         * The photographed far/top basket is physically much smaller in the source perspective than
         * the near/bottom basket. A symmetric numeric zoom therefore makes the user's attacking rim
         * look toy-sized. Increase only the top-half settled zoom; player sprites remain screen-sized,
         * so the court/hoop grows without turning the players into giants.
         */
        let approachingTopHoop = sourceY < Self.FULL_COURT_CENTER_Y
        let settledZoom: Float
        if approachingTopHoop {
            settledZoom = portrait ? 3.55 : 5.15
        } else {
            settledZoom = portrait ? 2.48 : 3.38
        }
        let topHoopProximity: Float
        if approachingTopHoop {
            topHoopProximity = (1 - abs(sourceY - topHoop().footY) / 350).coerceIn(0, 1)
        } else {
            topHoopProximity = 0
        }
        // The far basket is optically tiny in the photograph. Ramp its perspective correction by
        // actual basket proximity, not only by distance from mid-court; otherwise a handler already
        // near the top arc still saw a toy-sized rim.
        let zoomProgress = approachingTopHoop ? kmax(halfCourtProgress, topHoopProximity) : halfCourtProgress
        var targetZoom = transitionZoom + (settledZoom - transitionZoom) * zoomProgress

        /*
         * Far/top basket framing. Portrait intentionally keeps the exact P15 behaviour.
         * Landscape uses two visual anchors so the photographed far rim cannot stay toy-sized while
         * the player sprites remain screen-sized: keep the rim high in frame and the handler's feet
         * lower in frame, then solve the required world scale from those two points.
         */
        if possession == .HUMAN && !followLiveBall && sourceY < Self.FULL_COURT_CENTER_Y + 70 {
            let hoop = topHoop()
            let baseScaleForFraming =
                kmax(width.toFloat() / Self.SOURCE_W, height.toFloat() / Self.SOURCE_H).coerceAtLeast(0.001)

            if portrait {
                // Preserve P15 portrait camera exactly; this patch is only for the far-hoop
                // proportion problem seen in LANDSCAPE.
                let topEdge = hoop.rimY - 105
                let trailingEdge = sourceY + 145
                let desiredSpan = (trailingEdge - topEdge).coerceAtLeast(255)
                let fitZoom: Float =
                    (height.toFloat() / (baseScaleForFraming * desiredSpan) * 0.90)
                        .coerceIn(1.72, 2.58)
                targetZoom = kmin(targetZoom, fitZoom)
                targetY = (topEdge + trailingEdge) * 0.5
            } else {
                /*
                 * LANDSCAPE ONLY. Solve framing instead of guessing a zoom constant.
                 * Rim target: 15% down from the top.
                 * Handler-feet target: 76% down from the top.
                 * As the handler approaches the hoop, this naturally enlarges the photographed
                 * basket while still leaving visible court behind the handler.
                 */
                let rimScreenY: Float = height.toFloat() * 0.15
                let handlerFeetScreenY: Float = height.toFloat() * 0.76
                let sourceAnchorSpan = (sourceY - hoop.rimY).coerceAtLeast(82)
                let screenAnchorSpan =
                    (handlerFeetScreenY - rimScreenY).coerceAtLeast(dp(v: 120))

                let solvedWorldScale = screenAnchorSpan / sourceAnchorSpan
                targetZoom =
                    (solvedWorldScale / baseScaleForFraming)
                        .coerceIn(2.72, 5.05)

                let solvedScale = baseScaleForFraming * targetZoom
                targetY =
                    hoop.rimY +
                    ((height.toFloat() * 0.5 - rimScreenY) / solvedScale.coerceAtLeast(0.001))
            }
        }

        if force || !cameraInitialized {
            cameraCenterX = targetX
            cameraCenterY = targetY
            cameraZoom = targetZoom
            cameraInitialized = true
            if followLiveBall { syncBallViewFromSource() }
            return
        }

        // More obvious than Playtest 2, while still easing rather than snapping. At ~31fps a long
        // transition visibly travels across the court in roughly 0.4-0.6s.
        let panEase: Float = followLiveBall ? 0.21 : 0.14
        let zoomEase: Float = 0.12
        cameraCenterX += (targetX - cameraCenterX) * panEase
        cameraCenterY += (targetY - cameraCenterY) * panEase
        cameraZoom += (targetZoom - cameraZoom) * zoomEase

        if followLiveBall { syncBallViewFromSource() }
    }

    /// Kotlin `private data class Transform` (L3786-3791).
    struct Transform: Hashable {
        var scaleX: Float
        var scaleY: Float
        var offsetX: Float
        var offsetY: Float

        init(scaleX: Float, scaleY: Float, offsetX: Float, offsetY: Float) {
            self.scaleX = scaleX
            self.scaleY = scaleY
            self.offsetX = offsetX
            self.offsetY = offsetY
        }

        /// Kotlin positional form `Transform(1f, 1f, 0f, 0f)`.
        init(_ scaleX: Float, _ scaleY: Float, _ offsetX: Float, _ offsetY: Float) {
            self.init(scaleX: scaleX, scaleY: scaleY, offsetX: offsetX, offsetY: offsetY)
        }
    }

    func transform() -> Transform {
        if width <= 0 || height <= 0 { return Transform(1, 1, 0, 0) }

        // Uniform scale is intentional: stretching X/Y independently changes perceived speed and
        // disconnects player positions from the photographed hoop geometry. The camera crops/pans
        // the oversized full court instead.
        let baseScale = kmax(width.toFloat() / Self.SOURCE_W, height.toFloat() / Self.SOURCE_H).coerceAtLeast(0.001)
        let scale = baseScale * cameraZoom.coerceIn(Self.CAMERA_MIN_ZOOM, Self.CAMERA_MAX_ZOOM)
        let halfVisibleW: Float = width.toFloat() * 0.5 / scale
        let halfVisibleH: Float = height.toFloat() * 0.5 / scale

        let minCx = halfVisibleW
        let maxCx = Self.SOURCE_W - halfVisibleW
        let minCy = halfVisibleH
        let maxCy = Self.SOURCE_H - halfVisibleH
        let cx = minCx <= maxCx ? cameraCenterX.coerceIn(minCx, maxCx) : Self.FULL_COURT_CENTER_X
        let cy = minCy <= maxCy ? cameraCenterY.coerceIn(minCy, maxCy) : Self.FULL_COURT_CENTER_Y

        return Transform(
            scaleX: scale,
            scaleY: scale,
            offsetX: width.toFloat() * 0.5 - cx * scale,
            offsetY: height.toFloat() * 0.5 - cy * scale
        )
    }

    func sourceToView(x: Float, y: Float) -> APointF {
        let t = transform()
        return APointF(t.offsetX + x * t.scaleX, t.offsetY + y * t.scaleY)
    }

    func viewToSource(x: Float, y: Float) -> APointF {
        let t = transform()
        return APointF(
            ((x - t.offsetX) / t.scaleX.coerceAtLeast(0.001)).coerceIn(0, Self.SOURCE_W),
            ((y - t.offsetY) / t.scaleY.coerceAtLeast(0.001)).coerceIn(0, Self.SOURCE_H)
        )
    }

    /** Players live on the whole court; the camera, not actor clamping, decides what is visible. */
    func playableMinX() -> Float { return Self.SOURCE_PLAY_MIN_X }

    func playableMaxX() -> Float { return Self.SOURCE_PLAY_MAX_X }

    func clampActorToPlayableArea(actor: Actor) {
        actor.x = actor.x.coerceIn(playableMinX(), playableMaxX())
        actor.y = actor.y.coerceIn(Self.SOURCE_PLAY_MIN_Y, Self.SOURCE_PLAY_MAX_Y)
    }

    func viewPoint(actor: Actor) -> APointF { return sourceToView(x: actor.x, y: actor.y) }

    func distance(a: Actor, b: Actor) -> Float {
        return ksqrt(kpow(a.x - b.x, 2) + kpow((a.y - b.y) * 0.72, 2))
    }

    func distanceToHoop(a: Actor) -> Float {
        let hoop = attackingHoop(team: a.team)
        return ksqrt(kpow(a.x - hoop.footX, 2) + kpow(a.y - hoop.footY, 2))
    }

    func distanceView(a: APointF, b: APointF) -> Float {
        return ksqrt(kpow(a.x - b.x, 2) + kpow(a.y - b.y, 2))
    }

    func distancePointToSegment(p: APointF, a: APointF, b: APointF) -> Float {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        if len2 <= 0.001 { return distanceView(a: p, b: a) }
        let t: Float = (((p.x - a.x) * dx + (p.y - a.y) * dy) / len2).coerceIn(0, 1)
        return distanceView(a: p, b: APointF(a.x + dx * t, a.y + dy * t))
    }

    // MARK: - Facing (L3864-4006)

    func facingForVelocity(dx: Float, dy: Float) -> TripleShotPlayerRenderer.Facing {
        if abs(dx) > abs(dy) * 0.8 { return .SIDE }
        if dy < 0 { return .BACK }
        return .FRONT
    }

    func facingTowardAttackingHoop(actor: Actor) -> TripleShotPlayerRenderer.Facing {
        /*
         * Team court has a fixed world orientation by design: humans always attack the TOP basket
         * and opponents always attack the BOTTOM basket. Do not infer facing from whether a player
         * happened to drift a few source pixels past the hoop foot -- that made a dribbler suddenly
         * turn around under the rim.
         */
        return actor.team == .HUMAN ? .BACK : .FRONT
    }

    func facingTowardPoint(
        actor: Actor,
        targetX: Float,
        targetY: Float
    ) -> TripleShotPlayerRenderer.Facing {
        let dx = targetX - actor.x
        let dy = targetY - actor.y
        if abs(dx) > abs(dy) * 0.92 {
            return .SIDE
        } else if dy < 0 {
            return .BACK
        } else {
            return .FRONT
        }
    }

    func facingTowardActor(actor: Actor, target: Actor) -> TripleShotPlayerRenderer.Facing {
        return facingTowardPoint(actor: actor, targetX: target.x, targetY: target.y)
    }

    /**
     * The current runtime pack has FRONT/BACK standing art but no true SIDE idle/defensive stance.
     * Returning SIDE during tiny lateral shuffles therefore renders as the back-standing frame and
     * looks like the player suddenly turned away from the ball. Keep idle orientation vertical and
     * hysteretic; explicit steal/block/shot actions still use facingTowardPoint() and therefore get
     * the real SIDE action sprite when the geometry calls for it.
     */
    func stableIdleFacingTowardPoint(
        actor: Actor,
        targetX: Float,
        targetY: Float
    ) -> TripleShotPlayerRenderer.Facing {
        let dy = targetY - actor.y
        if abs(dy) <= Self.IDLE_FACING_VERTICAL_DEADBAND_SOURCE {
            switch actor.facing {
            case .FRONT: return .FRONT
            case .BACK: return .BACK
            case .SIDE: return actor.team == .HUMAN ? .BACK : .FRONT
            }
        }
        return dy < 0 ? .BACK : .FRONT
    }

    /** Basketball-facing is intent-aware, not just the direction of the last tiny movement. */
    func refreshLiveFacing(now: Int64) {
        for actor in actors {
            // Do not rotate a sprite out from underneath a committed action pose. For normal
            // dribble/walk/idle states, however, facing is refreshed every frame so a defender who
            // has already arrived beside the handler still turns toward the live ball.
            let committed: Bool
            switch actor.motion {
            case .STEAL, .BLOCK, .REBOUND, .DUNK, .SHOT_LOW, .SHOT_MID, .SHOT_SET, .RELEASE: committed = true
            default: committed = false
            }
            if !committed {
                actor.facing = basketballFacing(actor: actor, moveDx: actor.vx, moveDy: actor.vy)
            }
            actor.visual.update(now: now, nextX: actor.x, nextY: actor.y, wantedFacing: actor.facing.ordinal,
                                sideFacing: TripleShotPlayerRenderer.Facing.SIDE.ordinal, wantedMirror: actor.mirror,
                                committedAction: committed)
        }
    }

    func basketballFacing(actor: Actor, moveDx: Float, moveDy: Float) -> TripleShotPlayerRenderer.Facing {
        /*
         * Until true run/dribble sheets exist, orientation should communicate basketball intent, not
         * every one-pixel steering correction. That avoids FRONT/BACK tremor while players slowly
         * adjust spacing.
         */
        if actor.hasBall {
            return facingTowardAttackingHoop(actor: actor)
        }

        let handler = currentBallHandler()
        let now = gameTime()

        // A screener approaches the ball action looking at it, not alternating with velocity.
        if actor.screenTargetId != nil, let handler = handler, handler.team == actor.team {
            return stableIdleFacingTowardPoint(actor: actor, targetX: handler.x, targetY: handler.y)
        }

        // Cuts/rebounds are committed travel actions; movement direction may intentionally dominate.
        let committedTravel =
            actor.cutUntil > now ||
            actor.motion == TripleShotPlayerRenderer.Motion.REBOUND

        if !committedTravel {
            // Every defender near live half-court play should read the ball-handler, even after they
            // have stopped moving. Turning away from the player with the ball is never the neutral
            // defensive pose.
            if let handler = handler, handler.team != actor.team {
                return stableIdleFacingTowardPoint(actor: actor, targetX: handler.x, targetY: handler.y)
            }

            if ballVisible && (ballInFlight || looseBall) {
                let actorView = sourceToView(x: actor.x, y: actor.y)
                let liveBallView = sourceToView(x: ballSourceX, y: ballSourceY)
                if distanceView(a: actorView, b: liveBallView) <= dp(v: Self.BALL_FACING_PROXIMITY_DP) {
                    return stableIdleFacingTowardPoint(actor: actor, targetX: ballSourceX, targetY: ballSourceY)
                }
            }

            // Ordinary off-ball offense always presents body/hands to the passer. Previously the
            // same player could face the handler while idle, then flip away for one tiny spacing
            // step, then face back again -- the visible "shaking" reported in testing.
            if let handler = handler, handler.team == actor.team, handler.id != actor.id {
                return stableIdleFacingTowardPoint(actor: actor, targetX: handler.x, targetY: handler.y)
            }
        }

        if abs(moveDx) + abs(moveDy) < Self.FACING_MOVEMENT_EPSILON_SOURCE {
            return actor.facing
        }
        return facingForVelocity(dx: moveDx, dy: moveDy)
    }

    /// Kotlin `private fun dp(v: Float) = v * resources.displayMetrics.density` (px, DESIGN 2.5; the density is the
    /// constant UIScreen scale).
    func dp(v: Float) -> Float { return v * AResources.density }

    /// Unlabelled form: inside this class the member `dp(v:)` shadows AndroidKit's global `dp(_:)`, so callers that
    /// write the AndroidKit form still resolve (same value).
    func dp(_ v: Float) -> Float { return dp(v: v) }

    // MARK: - Companion object (L4008-4095)

    /*
     * 210ms matches the already-proven 1v1 press-to-aim timing closely, while swipe detection
     * uses Android's scaledTouchSlop and therefore cancels this timer as soon as movement is
     * unambiguous.
     */
    static let SHOT_HOLD_DELAY_MS: Int64 = 210

    // ~31fps keeps the dynamic ball/dribble readable without running six-player AI at 60Hz.
    static let TEAM_FRAME_MS: Int64 = 32

    // Team dribble intentionally mirrors the mature 1v1 visual cadence.
    static let TEAM_DRIBBLE_PERIOD_MS: Int64 = 740
    static let TEAM_DRIBBLE_AMPLITUDE_DP: Float = 46

    // Independent AI heartbeats/cooldowns. Team possessions are deliberately readable, not
    // arcade-fast; open-rim exceptions are handled explicitly in the decision loop.
    static let TEAM_BALL_HANDLER_DECISION_MS: Int64 = 360
    static let TEAM_OFF_BALL_DECISION_MS: Int64 = 680
    static let TEAM_STEAL_RETRY_MS: Int64 = 980
    static let TEAM_SCREEN_COOLDOWN_MS: Int64 = 2200
    static let TEAM_EARLY_ACTION_GRACE_MS: Int64 = 850
    static let TEAM_OFF_BALL_SETUP_GRACE_MS: Int64 = 700
    static let TEAM_MIN_FAST_FINISH_MS: Int64 = 1800
    static let TEAM_MIN_NORMAL_SHOT_MS: Int64 = 2400
    static let TEAM_MIN_PASS_HOLD_MS: Int64 = 760
    static let TEAM_MIN_DRIVE_HOLD_MS: Int64 = 980
    static let TEAM_STUCK_HANDLER_MS: Int64 = 2700
    static let TEAM_REBOUND_PUTBACK_WINDOW_MS: Int64 = 1150
    static let TEAM_SCREEN_REQUEST_HOLD_MS: Int64 = 1250
    static let TEAM_FORCE_SCREEN_HOLD_MS: Int64 = 2350
    static let TEAM_FORCED_BALL_MOVEMENT_MS: Int64 = 1850
    static let TEAM_ABSOLUTE_STALL_MS: Int64 = 3000
    static let TEAM_PRESSURE_TIGHTEN_START_MS: Int64 = 1400
    static let TEAM_PRESSURE_TIGHTEN_FULL_MS: Int64 = 3600
    static let TEAM_DOUBLE_TEAM_TRIGGER_MS: Int64 = 4200
    static let TEAM_STEAL_PATIENCE_MS: Int64 = 900
    static let STATIONARY_HANDLER_SOURCE_EPS: Float = 1.25
    static let HUMAN_STEAL_REACH_DP: Float = 82
    static let AI_STEAL_BASE_REACH_DP: Float = 54
    static let AI_STEAL_MAX_REACH_DP: Float = 76
    static let STEAL_TRANSFER_DELAY_MS: Int64 = 150

    // Calibrated against triple_shot_court_sunset_pulse_landscape.webp (1672 x 941).
    static let FULL_COURT_STYLE_ID = "sunset_pulse"
    /// Kotlin `setOf(...)`; only used for membership (`style.id in TEAM_FULL_COURT_STYLE_IDS`).
    static let TEAM_FULL_COURT_STYLE_IDS: Set<String> = [
        "sunset_pulse",
        "sunset_cove",
        "neon_tide",
        "neon_falls"
    ]
    static let SOURCE_W: Float = 1672
    static let SOURCE_H: Float = 941
    static let FULL_COURT_CENTER_X: Float = SOURCE_W * 0.5
    static let FULL_COURT_CENTER_Y: Float = SOURCE_H * 0.5

    static let SUNSET_GEOMETRY = CourtGeometryProfile(
        top: HoopGeometry(rimX: 834, rimY: 210, footX: 834, footY: 304),
        bottom: HoopGeometry(rimX: 834, rimY: 620, footX: 834, footY: 758),
        nearHoopLayerY: 715
    )

    // Calibrated against the supplied 1672x941 neon waterfall court.
    static let NEON_FALLS_GEOMETRY = CourtGeometryProfile(
        top: HoopGeometry(rimX: 834, rimY: 246, footX: 834, footY: 338),
        bottom: HoopGeometry(rimX: 834, rimY: 672, footX: 834, footY: 794),
        nearHoopLayerY: 748
    )

    static let SOURCE_PLAY_MIN_X: Float = 309
    static let SOURCE_PLAY_MAX_X: Float = 1359
    static let SOURCE_PLAY_MIN_Y: Float = 255
    static let SOURCE_PLAY_MAX_Y: Float = 805
    static let THREE_POINT_DISTANCE_SOURCE: Float = 335

    static let CAMERA_MIN_ZOOM: Float = 1.0
    static let CAMERA_MAX_ZOOM: Float = 5.25
    static let QUESTION_CAMERA_ZOOM: Float = 2.15
    static let PLAYER_SCREEN_SCALE: Float = 1.0
    // Collision dimensions are now character-aware lower-body half-width/depth values.
    static let COLLISION_PUSH_FRACTION: Float = 0.96
    static let FOOT_COLLISION_BAND_DP: Float = 24
    static let FOOT_COLLISION_PUSH_FRACTION: Float = 1.0
    static let BALL_FACING_PROXIMITY_DP: Float = 280
    static let FACING_MOVEMENT_EPSILON_SOURCE: Float = 0.55
    static let IDLE_FACING_VERTICAL_DEADBAND_SOURCE: Float = 18
    static let SOURCE_BALL_GRAVITY: Float = 720
}

/// Kotlin `Sequence<Float>.minOrNull()`: nil when empty, else a fold with `minOf` (Math.min, NaN-propagating).
private func teamCourtPart2MinOrNull(_ values: [Float]) -> Float? {
    guard var minimum = values.first else { return nil }
    for value in values.dropFirst() { minimum = kmin(minimum, value) }
    return minimum
}
