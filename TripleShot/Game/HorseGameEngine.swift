import Foundation

// Port of game/HorseGameEngine.kt (Android snapshot dd722e5), statement by statement.
// Kotlin `check`/`require`/`error` become `throws` where an Android caller catches the exception
// (the human `configureChallenge` in `runCatching`, the Live rules inside Firebase transactions);
// everywhere else they stay crashes (`precondition`), as on Android.

/**
 * Pure turn-state engine for local/live HORSE-style play.
 *
 * It deliberately knows nothing about Android, Firebase, questions or basketball physics.
 * The caller supplies only the two facts that matter after an attempt: whether the answer
 * was correct and whether the real ball entered the basket.
 */
final class HorseGameEngine {

    /// Kotlin's IllegalArgumentException (`require`) and IllegalStateException (`check`, `error`),
    /// with the Kotlin messages.
    enum RuleError: Error, Equatable {
        case illegalArgument(String)
        case illegalState(String)
    }

    enum Player: String, KotlinEnum {
        case HUMAN
        case BOT

        func other() -> Player { return self == .HUMAN ? .BOT : .HUMAN }
    }

    struct Challenge: Hashable {
        var setter: Player
        var category: QuestionCategory
        var spotId: String
        var established: Bool
    }

    struct State: Hashable {
        var setter: Player
        var currentPlayer: Player
        var challenge: Challenge?
        var humanPenalties: Int
        var botPenalties: Int
        var winner: Player?

        var isGameOver: Bool { return winner != nil }

        var needsNewChallenge: Bool { return challenge == nil && !isGameOver }

        func penaltiesFor(player: Player) -> Int {
            return player == .HUMAN ? humanPenalties : botPenalties
        }

        /// Positional form (Kotlin `state.penaltiesFor(player)`).
        func penaltiesFor(_ player: Player) -> Int { return penaltiesFor(player: player) }
    }

    enum ResultType: String, KotlinEnum {
        case CHALLENGE_ESTABLISHED
        case SETTER_FAILED
        case CONTINUE_NO_PENALTY
        case CONTINUE_WITH_PENALTY
        case CHALLENGE_ENDED_NO_PENALTY
        case CHALLENGE_ENDED_WITH_PENALTY
        case GAME_OVER
    }

    struct Resolution: Hashable {
        var type: ResultType
        var actor: Player
        var answerCorrect: Bool
        var made: Bool
        var penaltyAdded: Bool
        var state: State
    }

    private let maxPenalties: Int

    private var setter: Player
    private var currentPlayer: Player
    private var challenge: Challenge? = nil
    private var humanPenalties = 0
    private var botPenalties = 0
    private var winner: Player? = nil

    init(firstSetter: Player = .HUMAN, maxPenalties: Int = 5) {
        self.maxPenalties = maxPenalties
        precondition(maxPenalties > 0, "Failed requirement.")
        self.setter = firstSetter
        self.currentPlayer = firstSetter
    }

    func snapshot() -> State {
        return State(
            setter: setter,
            currentPlayer: currentPlayer,
            challenge: challenge,
            humanPenalties: humanPenalties,
            botPenalties: botPenalties,
            winner: winner
        )
    }

    /**
     * Called once the setter has chosen both a topic and a physical shot location.
     */
    func configureChallenge(
        player: Player,
        category: QuestionCategory,
        spotId: String
    ) throws {
        try HorseGameEngine.check(winner == nil, "HORSE match already finished")
        try HorseGameEngine.check(challenge == nil, "A challenge is already active")
        try HorseGameEngine.check(
            player == setter && player == currentPlayer,
            "Only the current setter can configure a challenge"
        )

        challenge = Challenge(
            setter: player,
            category: category,
            spotId: spotId,
            established: false
        )
    }

    /**
     * Applies the rules agreed for MinikSwish HORSE:
     *
     * Setter: only correct + made establishes the challenge. A failed setter attempt does not
     * earn a penalty; the other player becomes the next setter.
     *
     * Obligated player:
     *  - correct + made: no penalty, challenge continues;
     *  - wrong + made: penalty, challenge continues;
     *  - correct + miss: no penalty, challenge ends;
     *  - wrong + miss: penalty, challenge ends.
     */
    func resolveAttempt(
        player: Player,
        answerCorrect: Bool,
        made: Bool
    ) -> Resolution {
        precondition(winner == nil, "HORSE match already finished")
        precondition(player == currentPlayer, "It is not \(player.name)'s turn")

        guard let currentChallenge = challenge else {
            preconditionFailure("A shot cannot be resolved before a challenge is configured")
        }

        let isSetterAttempt =
            !currentChallenge.established &&
            currentChallenge.setter == player

        if isSetterAttempt {
            if answerCorrect && made {
                var established = currentChallenge
                established.established = true
                challenge = established
                currentPlayer = player.other()

                return Resolution(
                    type: .CHALLENGE_ESTABLISHED,
                    actor: player,
                    answerCorrect: true,
                    made: true,
                    penaltyAdded: false,
                    state: snapshot()
                )
            }

            challenge = nil
            setter = player.other()
            currentPlayer = setter

            return Resolution(
                type: .SETTER_FAILED,
                actor: player,
                answerCorrect: answerCorrect,
                made: made,
                penaltyAdded: false,
                state: snapshot()
            )
        }

        let penaltyAdded = !answerCorrect
        if penaltyAdded {
            addPenalty(player: player)
        }

        if penaltiesFor(player: player) >= maxPenalties {
            winner = player.other()
            return Resolution(
                type: .GAME_OVER,
                actor: player,
                answerCorrect: answerCorrect,
                made: made,
                penaltyAdded: true,
                state: snapshot()
            )
        }

        if made {
            currentPlayer = player.other()
            return Resolution(
                type: penaltyAdded ? .CONTINUE_WITH_PENALTY : .CONTINUE_NO_PENALTY,
                actor: player,
                answerCorrect: answerCorrect,
                made: true,
                penaltyAdded: penaltyAdded,
                state: snapshot()
            )
        }

        challenge = nil
        setter = player.other()
        currentPlayer = setter

        return Resolution(
            type: penaltyAdded ? .CHALLENGE_ENDED_WITH_PENALTY : .CHALLENGE_ENDED_NO_PENALTY,
            actor: player,
            answerCorrect: answerCorrect,
            made: false,
            penaltyAdded: penaltyAdded,
            state: snapshot()
        )
    }

    private func addPenalty(player: Player) {
        if player == .HUMAN {
            humanPenalties += 1
        } else {
            botPenalties += 1
        }
    }

    private func penaltiesFor(player: Player) -> Int {
        return player == .HUMAN ? humanPenalties : botPenalties
    }

    /// Kotlin `check(value) { message }`.
    fileprivate static func check(_ value: Bool, _ message: @autoclosure () -> String) throws {
        if !value { throw RuleError.illegalState(message()) }
    }

    /// Kotlin `require(value) { message }` (message "Failed requirement." when Kotlin gives none).
    fileprivate static func require(_ value: Bool, _ message: @autoclosure () -> String = "Failed requirement.") throws {
        if !value { throw RuleError.illegalArgument(message()) }
    }

    /**
     * Pure rules for Live HORSE with 2-4 real players.
     *
     * The Firebase layer owns persistence; this object only transforms one immutable
     * [LiveHorseState] after a completed knowledge+shot attempt.
     */
    enum Multiplayer {

        struct Resolution {
            var state: LiveHorseState
            var penaltyAdded: Bool
            var eliminatedUid: String? = nil
            var challengeEnded: Bool = false
        }

        static func initialState(
            playerOrder: [String],
            firstSetterUid: String
        ) -> LiveHorseState {
            let order = playerOrder.kDistinct().filter { !$0.kotlinIsBlank }
            precondition(order.count >= 2 && order.count <= 4, "Live HORSE requires 2-4 players")
            precondition(order.contains(firstSetterUid), "First setter must be in playerOrder")

            var state = LiveHorseState(
                phase: LiveHorseState.PHASE_SETTING,
                setterUid: firstSetterUid,
                currentPlayerUid: firstSetterUid,
                playerOrder: order,
                turnNumber: 1
            )
            // penalties = order.associateWith { 0 } (order is already distinct)
            for uid in order {
                state.penalties[uid] = 0
            }
            return state
        }

        static func configureChallenge(
            state: LiveHorseState,
            actorUid: String,
            category: QuestionCategory,
            spotId: String,
            spotX: Float,
            spotY: Float
        ) throws -> LiveHorseState {
            try HorseGameEngine.require(!state.isFinished, "Live HORSE already finished")
            try HorseGameEngine.require(state.phase == LiveHorseState.PHASE_SETTING, "Not in setting phase")
            try HorseGameEngine.require(
                actorUid == state.setterUid && actorUid == state.currentPlayerUid,
                "Only the current setter can configure a challenge"
            )

            var next = state
            next.phase = LiveHorseState.PHASE_ATTEMPT
            next.challengeEstablished = false
            next.challengeCategory = category.name
            next.challengeSpotId = spotId
            next.challengeSpotX = spotX
            next.challengeSpotY = spotY
            next.attemptedUids = []
            next.turnNumber = state.turnNumber + 1
            return next
        }

        static func resolveAttempt(
            state: LiveHorseState,
            actorUid: String,
            answerCorrect: Bool,
            made: Bool,
            maxPenalties: Int = 5
        ) throws -> Resolution {
            try HorseGameEngine.require(!state.isFinished, "Live HORSE already finished")
            try HorseGameEngine.require(state.phase == LiveHorseState.PHASE_ATTEMPT, "No active attempt")
            try HorseGameEngine.require(actorUid == state.currentPlayerUid, "Not this player's turn")

            try HorseGameEngine.require(maxPenalties > 0)
            let activeBefore = activePlayers(state: state, limit: maxPenalties)
            try HorseGameEngine.require(activeBefore.contains(actorUid), "Spectators cannot shoot")

            let isSetterAttempt =
                !state.challengeEstablished &&
                actorUid == state.setterUid

            if isSetterAttempt {
                if answerCorrect && made {
                    let next = nextActiveAfter(state: state, uid: actorUid, limit: maxPenalties)
                    var established = state
                    established.challengeEstablished = true
                    established.currentPlayerUid = next
                    established.attemptedUids = []
                    established.turnNumber = state.turnNumber + 1
                    return Resolution(
                        state: established,
                        penaltyAdded: false
                    )
                }

                let nextSetter = nextActiveAfter(state: state, uid: actorUid, limit: maxPenalties)
                return Resolution(
                    state: clearChallenge(
                        state: state,
                        nextSetterUid: nextSetter
                    ),
                    penaltyAdded: false,
                    challengeEnded: true
                )
            }

            var newPenalties = state.penalties
            var eliminatedUid: String? = nil
            var spectatorSlots = state.spectatorSlots

            if !answerCorrect {
                let newValue = (newPenalties[actorUid] ?? 0) + 1
                newPenalties[actorUid] = newValue

                if newValue >= maxPenalties {
                    eliminatedUid = actorUid
                    let used = Set(spectatorSlots.values)
                    let slot = [0, 1, 2].first { !used.contains($0) } ?? used.count
                    spectatorSlots[actorUid] = slot
                }
            }

            var base = state
            base.penalties = newPenalties
            base.spectatorSlots = spectatorSlots
            let activeAfter = activePlayers(state: base, limit: maxPenalties)

            if activeAfter.count == 1 {
                let winner = activeAfter[0]
                var finished = base
                finished.phase = LiveHorseState.PHASE_FINISHED
                finished.winnerUid = winner
                finished.currentPlayerUid = winner
                finished.challengeEstablished = false
                finished.turnNumber = state.turnNumber + 1
                return Resolution(
                    state: finished,
                    penaltyAdded: !answerCorrect,
                    eliminatedUid: eliminatedUid,
                    challengeEnded: true
                )
            }

            if !made {
                let nextSetter = nextActiveAfter(state: base, uid: actorUid, limit: maxPenalties)
                return Resolution(
                    state: clearChallenge(state: base, nextSetterUid: nextSetter),
                    penaltyAdded: !answerCorrect,
                    eliminatedUid: eliminatedUid,
                    challengeEnded: true
                )
            }

            // attemptedUids.toMutableSet() + actorUid: an insertion-ordered set.
            var attempted = state.attemptedUids.kDistinct()
            if !attempted.contains(actorUid) {
                attempted.append(actorUid)
            }

            let obligatedPlayers =
                activeAfter.filter { $0 != state.setterUid }

            let everyoneCompleted =
                !obligatedPlayers.isEmpty &&
                obligatedPlayers.allSatisfy { attempted.contains($0) }

            if everyoneCompleted {
                let nextSetter = nextActiveAfter(state: base, uid: state.setterUid, limit: maxPenalties)
                return Resolution(
                    state: clearChallenge(state: base, nextSetterUid: nextSetter),
                    penaltyAdded: !answerCorrect,
                    eliminatedUid: eliminatedUid,
                    challengeEnded: true
                )
            }

            let next = nextActiveAfter(state: base, uid: actorUid, limit: maxPenalties)
            var continued = base
            continued.currentPlayerUid = next
            continued.attemptedUids = attempted
            continued.turnNumber = state.turnNumber + 1
            return Resolution(
                state: continued,
                penaltyAdded: !answerCorrect,
                eliminatedUid: eliminatedUid
            )
        }

        private static func clearChallenge(
            state: LiveHorseState,
            nextSetterUid: String
        ) -> LiveHorseState {
            var cleared = state
            cleared.phase = LiveHorseState.PHASE_SETTING
            cleared.setterUid = nextSetterUid
            cleared.currentPlayerUid = nextSetterUid
            cleared.challengeEstablished = false
            cleared.challengeCategory = ""
            cleared.challengeSpotId = ""
            cleared.challengeSpotX = 0
            cleared.challengeSpotY = 0
            cleared.attemptedUids = []
            cleared.turnNumber = state.turnNumber + 1
            return cleared
        }

        private static func activePlayers(state: LiveHorseState, limit: Int) -> [String] {
            return state.playerOrder.filter {
                (state.penalties[$0] ?? 0) < limit &&
                    state.spectatorSlots[$0] == nil
            }
        }

        private static func nextActiveAfter(
            state: LiveHorseState,
            uid: String,
            limit: Int
        ) -> String {
            let order = state.playerOrder
            if order.isEmpty { return uid }
            let index = order.firstIndex(of: uid) ?? -1
            let start = index >= 0 ? index : 0
            for offset in kuntil(0, order.count) {
                let candidate = order[(start + 1 + offset) % order.count]
                if (state.penalties[candidate] ?? 0) < limit &&
                    state.spectatorSlots[candidate] == nil {
                    return candidate
                }
            }
            return uid
        }
    }
}

// MARK: - Positional (Kotlin call-site) forms

extension HorseGameEngine {
    func configureChallenge(_ player: Player, _ category: QuestionCategory, _ spotId: String) throws {
        try configureChallenge(player: player, category: category, spotId: spotId)
    }

    func resolveAttempt(_ player: Player, _ answerCorrect: Bool, _ made: Bool) -> Resolution {
        return resolveAttempt(player: player, answerCorrect: answerCorrect, made: made)
    }
}

extension HorseGameEngine.Multiplayer {
    static func initialState(_ playerOrder: [String], _ firstSetterUid: String) -> LiveHorseState {
        return initialState(playerOrder: playerOrder, firstSetterUid: firstSetterUid)
    }

    static func configureChallenge(
        _ state: LiveHorseState, _ actorUid: String, _ category: QuestionCategory,
        _ spotId: String, _ spotX: Float, _ spotY: Float
    ) throws -> LiveHorseState {
        return try configureChallenge(
            state: state, actorUid: actorUid, category: category, spotId: spotId, spotX: spotX, spotY: spotY
        )
    }

    static func resolveAttempt(
        _ state: LiveHorseState, _ actorUid: String, _ answerCorrect: Bool, _ made: Bool, _ maxPenalties: Int = 5
    ) throws -> Resolution {
        return try resolveAttempt(
            state: state, actorUid: actorUid, answerCorrect: answerCorrect, made: made, maxPenalties: maxPenalties
        )
    }
}
