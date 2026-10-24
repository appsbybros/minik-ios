import Foundation

// Port of firebase/TripleShotFirebaseRepository.kt (TripleShotGame dd722e5), spec 05.
//
// Translated statement by statement onto AndroidKit's Android-shaped Firebase (AFirebase.swift,
// AFirebaseCodec.swift) and the wire codecs of Model/TripleShotModelsFirebase.swift, so every path, key, JSON type,
// transaction, onDisconnect operation, ServerValue placeholder, error text and constant is Android's, including the
// hard-coded database URL. Threading as on Android: Task listeners, value/child event callbacks and
// Transaction.Handler.onComplete run on the main thread (AndroidKit posts them there); doTransaction may run several
// times, first with the locally cached value.
//
// Kotlin -> Swift:
// - `Result<T>` callbacks -> `Result<T, Error>`; `Result<Unit>` -> `Result<Void, Error>`; `Pair<String, Long>` ->
//   `(first: String, second: Int64)`; `Map<String, KnowledgeBucket>` (LinkedHashMap) -> `KLinkedMap`.
// - The literal exceptions (IllegalStateException / IllegalArgumentException with Android's English texts) are the
//   nested AFirebaseException subclasses below, so `(error as? AFirebaseException)?.message` (also
//   LocalizedError.errorDescription) is Throwable.getMessage() for every failure; it is nil only for AndroidKit's
//   AFirebaseNotConfiguredException (iOS without a usable GoogleService-Info.plist), where the callers'
//   `message ?: getString(R.string.minik_swish_firebase_error)` shows the app's own text.
// - `Set<QuestionCategory>` parameters accept any sequence of topics and keep Kotlin Set semantics (KLinkedSet).
// - The pure parts of a few methods (payload maps, snapshot parsing, rank count, the transaction handlers) are
//   separate members so Tests/TripleShotTests/FirebaseRepositoryTests.swift can check them; the statements, their
//   order and the moment they run are the Kotlin ones. Kotlin-private members those tests need are internal.

final class TripleShotFirebaseRepository {
    private let auth = AFirebaseAuth.getInstance()
    private let database: AFirebaseDatabase
    private let root: ADatabaseReference

    init(databaseUrl: String? = TripleShotFirebaseRepository.DATABASE_URL) {
        if databaseUrl == nil || databaseUrl!.kotlinIsBlank {
            database = AFirebaseDatabase.getInstance()
        } else {
            // databaseUrl.trimEnd('/')
            var units = Array(databaseUrl!.utf16)
            while let last = units.last, last == 0x2F {
                units.removeLast()
            }
            database = AFirebaseDatabase.getInstance(String(decoding: units, as: UTF16.self))
        }
        root = database.reference.child(TripleShotFirebaseRepository.ROOT_NODE)
    }

    /** Kotlin `data class ListenerHandle(val remove: () -> Unit)`: `handle.remove()` detaches the listener. */
    struct ListenerHandle {
        let remove: () -> Void
    }

    struct KnowledgeBucket: Hashable {
        var total: Int = 0
        var correct: Int = 0

        /** `((correct * 100f) / total).toInt().coerceIn(0, 100)`: Float maths, truncation. */
        var accuracyPercent: Int {
            return total <= 0 ? 0 : ((correct.toFloat() * Float(100)) / total.toFloat()).toInt().coerceIn(0, 100)
        }
    }

    struct KnowledgeAttemptRecord: Hashable {
        var id: String = ""
        var questionId: String = ""
        var category: String = ""
        var prompt: String = ""
        var selectedAnswer: String = ""
        var correctAnswer: String = ""
        var qualityPercent: Int = 0
        var correct: Bool = false
        var gameType: String = ""
        var answeredAt: Int64 = 0
    }

    struct KnowledgeDashboard: Equatable {
        var allTime: KLinkedMap<String, KnowledgeBucket> = KLinkedMap()
        var currentMonth: KLinkedMap<String, KnowledgeBucket> = KLinkedMap()
        var currentWeek: KLinkedMap<String, KnowledgeBucket> = KLinkedMap()
        var attempts: [KnowledgeAttemptRecord] = []
    }

    /// `TripleShotOnlineIdentity.name(FirebaseApp.getInstance().applicationContext)`.
    private func onlineName() -> String {
        return TripleShotOnlineIdentity.name(c: AApplication.shared)
    }

    func currentUid() -> String? {
        return auth.currentUser?.uid
    }

    func ensureAnonymousAuth(callback: @escaping (Result<String, Error>) -> Void) {
        if let uid = auth.currentUser?.uid {
            callback(.success(uid))
            return
        }
        auth.signInAnonymously().addOnCompleteListener { task in
            let uid = self.auth.currentUser?.uid
            if task.isSuccessful && uid != nil {
                callback(.success(uid!))
            } else {
                callback(.failure(task.exception ?? IllegalStateException("Anonymous auth failed")))
            }
        }
    }

    func createRoom<S: Sequence>(
        playerName: String,
        selectedCategories: S,
        gameType: GameType = .SHOOTING_CHALLENGE,
        timeLimitSeconds: Int = 60,
        callback: @escaping (Result<(first: String, second: Int64), Error>) -> Void
    ) where S.Element == QuestionCategory {
        let selectedCategories = KLinkedSet(selectedCategories)
        ensureAnonymousAuth { authResult in
            let uid: String
            switch authResult {
            case .success(let value):
                uid = value
            case .failure(let error):
                callback(.failure(error))
                return
            }
            self.tryCreateRoom(
                uid: uid,
                playerName: playerName,
                selectedCategories: selectedCategories,
                gameType: gameType,
                timeLimitSeconds: timeLimitSeconds,
                attempt: 0,
                callback: callback
            )
        }
    }

    /** Backward-compatible helper for older callers. */
    func createRoom(playerName: String, callback: @escaping (Result<(first: String, second: Int64), Error>) -> Void) {
        createRoom(
            playerName: playerName,
            selectedCategories: KLinkedSet(QuestionCategory.allCases),
            callback: callback
        )
    }

    private func tryCreateRoom(
        uid: String,
        playerName: String,
        selectedCategories: KLinkedSet<QuestionCategory>,
        gameType: GameType,
        timeLimitSeconds: Int,
        attempt: Int,
        callback: @escaping (Result<(first: String, second: Int64), Error>) -> Void
    ) {
        if attempt >= 6 {
            callback(.failure(IllegalStateException("Could not allocate room code")))
            return
        }
        // buildString { repeat(6) { append(ROOM_ALPHABET.random()) } }
        let alphabet = Array(TripleShotFirebaseRepository.ROOM_ALPHABET)
        var code = ""
        for _ in kuntil(0, 6) {
            code.append(alphabet.kRandom(KotlinRandom.Default))
        }
        let room = root.child("rooms").child(code)
        room.get().addOnSuccessListener { snapshot in
            if snapshot.exists() {
                self.tryCreateRoom(
                    uid: uid,
                    playerName: playerName,
                    selectedCategories: selectedCategories,
                    gameType: gameType,
                    timeLimitSeconds: timeLimitSeconds,
                    attempt: attempt + 1,
                    callback: callback
                )
                return
            }
            let seed = ASystem.currentTimeMillis() ^ KotlinRandom.Default.nextLong()
            let updates = self.roomCreationUpdates(
                uid: uid,
                playerName: playerName,
                selectedCategories: selectedCategories,
                gameType: gameType,
                timeLimitSeconds: timeLimitSeconds,
                seed: seed
            )
            room.updateChildren(updates)
                .addOnSuccessListener { _ in
                    let playerRef = room.child("players").child(uid)

                    // Keep the host player presence tidy as well. While the room is
                    // WAITING, the room-level disconnect below is the important fallback.
                    playerRef.onDisconnect().removeValue()

                    // A WAITING room belongs to the host. Queue its deletion on the
                    // Firebase server so a crash, killed process or lost connection does
                    // not leave a dead lobby behind. The security rules only allow this
                    // deletion while the room is still WAITING.
                    room.onDisconnect().removeValue()
                        .addOnSuccessListener { _ in
                            callback(.success((first: code, second: seed)))
                        }
                        .addOnFailureListener { error in
                            // The room is not useful if we could not arm its cleanup.
                            // Best-effort immediate cleanup; the failure is returned to UI.
                            room.removeValue()
                            callback(.failure(error))
                        }
                }
                .addOnFailureListener { error in
                    callback(.failure(error))
                }
        }.addOnFailureListener { error in
            callback(.failure(error))
        }
    }

    /// The `updates` map of tryCreateRoom (Kotlin 146-157): one atomic multi-path write of the room meta and the
    /// host's player node. `playerName` is passed on to playerMap, which ignores it (Android).
    func roomCreationUpdates(
        uid: String,
        playerName: String,
        selectedCategories: KLinkedSet<QuestionCategory>,
        gameType: GameType,
        timeLimitSeconds: Int,
        seed: Int64
    ) -> [String: Any] {
        return [
            "meta/hostUid": uid,
            "meta/status": "WAITING",
            "meta/seed": seed,
            "meta/createdAt": AServerValue.TIMESTAMP,
            "meta/startedAt": Int64(0),
            "meta/gameType": gameType.name,
            "meta/categories": selectedCategories.map { $0.name }.stableSorted { $0.javaPrecedes($1) },
            "meta/timeLimitSeconds": timeLimitSeconds.coerceIn(10, 600),
            "meta/maxPlayers": 4,
            "players/\(uid)": playerMap(uid: uid, name: playerName)
        ]
    }

    func joinRoom(codeRaw: String, playerName: String, callback: @escaping (Result<Int64, Error>) -> Void) {
        ensureAnonymousAuth { authResult in
            let uid: String
            switch authResult {
            case .success(let value):
                uid = value
            case .failure(let error):
                callback(.failure(error))
                return
            }
            let code = codeRaw.ktrim().uppercased()
            let room = self.root.child("rooms").child(code)
            room.get().addOnSuccessListener { snapshot in
                let meta = snapshot.child("meta").getValue(RoomMeta.self)
                if meta == nil || meta!.hostUid.kotlinIsBlank {
                    callback(.failure(IllegalArgumentException("Room not found")))
                    return
                }
                if meta!.status != "WAITING" {
                    callback(.failure(IllegalStateException("Room already started")))
                    return
                }
                let playersCount = snapshot.child("players").childrenCount
                if playersCount >= 4 && !snapshot.child("players").child(uid).exists() {
                    callback(.failure(IllegalStateException("Room is full")))
                    return
                }
                room.child("players").child(uid).setValue(self.playerMap(uid: uid, name: playerName))
                    .addOnSuccessListener { _ in
                        room.child("players").child(uid).onDisconnect().removeValue()
                        callback(.success(meta!.seed))
                    }
                    .addOnFailureListener { error in
                        callback(.failure(error))
                    }
            }.addOnFailureListener { error in
                callback(.failure(error))
            }
        }
    }

    func startRoom(codeRaw: String, callback: @escaping (Result<Void, Error>) -> Void) {
        let code = codeRaw.ktrim().uppercased()
        let room = root.child("rooms").child(code)

        room.get()
            .addOnSuccessListener { snapshot in
                let playersSnapshot = snapshot.child("players")
                let count = playersSnapshot.childrenCount
                if count < 2 || count > 4 {
                    callback(.failure(IllegalStateException("Live room requires 2-4 players")))
                    return
                }

                guard let meta = snapshot.child("meta").getValue(RoomMeta.self) else {
                    callback(.failure(IllegalStateException("Room metadata missing")))
                    return
                }

                let updates = TripleShotFirebaseRepository.startRoomUpdates(playersSnapshot: playersSnapshot, meta: meta)

                room.updateChildren(updates)
                    .addOnSuccessListener { _ in
                        /*
                         * The WAITING-room cleanup is no longer wanted after kickoff.
                         * Re-arm only this device's player presence after cancelling the
                         * room-level disconnect action.
                         */
                        room.onDisconnect().cancel()
                            .addOnCompleteListener { _ in
                                if let uid = self.currentUid() {
                                    room.child("players")
                                        .child(uid)
                                        .onDisconnect()
                                        .removeValue()
                                }
                                callback(.success(()))
                            }
                    }
                    .addOnFailureListener { error in
                        callback(.failure(error))
                    }
            }
            .addOnFailureListener { error in
                callback(.failure(error))
            }
    }

    /// The `updates` map of startRoom (Kotlin 238-263). For HORSE the initial turn state goes in the same write;
    /// `HorseGameEngine.Multiplayer.initialState` requires 2-4 distinct players including the host and crashes the
    /// success listener otherwise, as on Android.
    static func startRoomUpdates(playersSnapshot: ADataSnapshot, meta: RoomMeta) -> [String: Any] {
        var updates: [String: Any] = [
            "meta/status": "PLAYING",
            "meta/startedAt": AServerValue.TIMESTAMP
        ]

        if meta.gameType == GameType.HORSE.name {
            var ordered =
                playersSnapshot.children
                    .compactMap { $0.key }
                    .kDistinct()

            // Host sets first; the rest are deterministic by uid so every client sees
            // the same 2-4 player turn order.
            if let index = ordered.firstIndex(of: meta.hostUid) {
                ordered.remove(at: index)
            }
            ordered = ordered.stableSorted { $0.javaPrecedes($1) }
            ordered.insert(meta.hostUid, at: 0)

            let initial =
                HorseGameEngine.Multiplayer.initialState(
                    playerOrder: ordered,
                    firstSetterUid: meta.hostUid
                )

            updates["horse"] = initial
        }
        return updates
    }

    @discardableResult
    func listenRoomMeta(codeRaw: String, callback: @escaping (RoomMeta?) -> Void) -> ListenerHandle {
        let ref = root.child("rooms").child(codeRaw.ktrim().uppercased()).child("meta")
        let listener = ASimpleValueEventListener(
            onDataChange: { snapshot in callback(snapshot.getValue(RoomMeta.self)) },
            onCancelled: { _ in callback(nil) }
        )
        ref.addValueEventListener(listener)
        return ListenerHandle(remove: { ref.removeEventListener(listener) })
    }

    @discardableResult
    func listenLiveHorseState(
        codeRaw: String,
        callback: @escaping (LiveHorseState?) -> Void
    ) -> ListenerHandle {
        let ref =
            root.child("rooms")
                .child(codeRaw.ktrim().uppercased())
                .child("horse")

        let listener = ASimpleValueEventListener(
            onDataChange: { snapshot in
                callback(snapshot.getValue(LiveHorseState.self))
            },
            onCancelled: { _ in
                callback(nil)
            }
        )

        ref.addValueEventListener(listener)
        return ListenerHandle(remove: { ref.removeEventListener(listener) })
    }

    func configureLiveHorseChallenge(
        roomCodeRaw: String,
        category: QuestionCategory,
        spotId: String,
        spotX: Float,
        spotY: Float,
        callback: @escaping (Result<Void, Error>) -> Void = { _ in }
    ) {
        guard let uid = currentUid() else {
            callback(.failure(IllegalStateException("Not authenticated")))
            return
        }

        let ref =
            root.child("rooms")
                .child(roomCodeRaw.ktrim().uppercased())
                .child("horse")

        ref.runTransaction(ConfigureLiveHorseChallengeHandler(
            uid: uid,
            category: category,
            spotId: spotId,
            spotX: spotX,
            spotY: spotY,
            callback: callback
        ))
    }

    func resolveLiveHorseAttempt(
        roomCodeRaw: String,
        answerCorrect: Bool,
        made: Bool,
        callback: @escaping (Result<LiveHorseState, Error>) -> Void = { _ in }
    ) {
        guard let uid = currentUid() else {
            callback(.failure(IllegalStateException("Not authenticated")))
            return
        }

        let room =
            root.child("rooms")
                .child(roomCodeRaw.ktrim().uppercased())
        let ref = room.child("horse")

        ref.runTransaction(ResolveLiveHorseAttemptHandler(
            room: room,
            uid: uid,
            answerCorrect: answerCorrect,
            made: made,
            callback: callback
        ))
    }

    @discardableResult
    func listenRoomPlayers(codeRaw: String, callback: @escaping ([LivePlayerState]) -> Void) -> ListenerHandle {
        let ref = root.child("rooms").child(codeRaw.ktrim().uppercased()).child("players")
        let listener = ASimpleValueEventListener(
            onDataChange: { snapshot in
                callback(snapshot.children.compactMap { $0.getValue(LivePlayerState.self) })
            },
            onCancelled: { _ in callback([]) }
        )
        ref.addValueEventListener(listener)
        return ListenerHandle(remove: { ref.removeEventListener(listener) })
    }

    func updateLiveState(roomCodeRaw: String, state: LivePlayerState) {
        guard let uid = currentUid() else { return }
        let code = roomCodeRaw.ktrim().uppercased()
        let map = liveStateMap(uid: uid, state: state)
        root.child("rooms").child(code).child("players").child(uid).updateChildren(map)
    }

    /// `playerMap(uid, state.name).apply { ... }` of updateLiveState (Kotlin 465-476): the full player node with the
    /// stats of `state`; `state.uid` and `state.name` are not used (the name is always the online nickname).
    func liveStateMap(uid: String, state: LivePlayerState) -> [String: Any] {
        var map = playerMap(uid: uid, name: state.name)
        map["score"] = state.score
        map["knowledgeStreak"] = state.knowledgeStreak
        map["shootingStreak"] = state.shootingStreak
        map["bestKnowledgeStreak"] = state.bestKnowledgeStreak
        map["bestShootingStreak"] = state.bestShootingStreak
        map["correctAnswers"] = state.correctAnswers
        map["madeShots"] = state.madeShots
        map["shots"] = state.shots
        map["lastEvent"] = state.lastEvent
        map["finished"] = state.finished
        return map
    }

    /**
     * Marks a Live room as FINISHED once the shared match itself is over.
     * (The Kotlin KDoc says the server rules allow PLAYING -> FINISHED only after the shared deadline; the deployed
     * rules have no such rule: only the host, or any member once `horse/winnerUid` is set, may write it, spec 05 4.9.)
     */
    func markRoomFinished(
        roomCodeRaw: String,
        callback: @escaping (Result<Void, Error>) -> Void = { _ in }
    ) {
        guard let uid = currentUid() else {
            callback(.failure(IllegalStateException("Not authenticated")))
            return
        }

        let code = roomCodeRaw.ktrim().uppercased()
        let room = root.child("rooms").child(code)

        room.child("players").child(uid).get()
            .addOnSuccessListener { membership in
                if !membership.exists() {
                    callback(.failure(IllegalStateException("Player is no longer in room")))
                    return
                }

                room.child("meta").child("status")
                    .setValue("FINISHED")
                    .addOnSuccessListener { _ in
                        self.armFinishedRoomCleanupIfLast(roomCodeRaw: code)
                        callback(.success(()))
                    }
                    .addOnFailureListener { error in
                        callback(.failure(error))
                    }
            }
            .addOnFailureListener { error in
                callback(.failure(error))
            }
    }

    /**
     * If this client is the only participant still connected to a FINISHED room, queue a
     * server-side deletion of the whole room for its eventual disconnect. Until that point
     * eliminated/finished players remain in /players and are free to spectate.
     */
    func armFinishedRoomCleanupIfLast(roomCodeRaw: String) {
        guard let uid = currentUid() else { return }
        let code = roomCodeRaw.ktrim().uppercased()
        let room = root.child("rooms").child(code)

        room.get().addOnSuccessListener { snapshot in
            let status =
                snapshot.child("meta").child("status")
                    .getValue(String.self)
                    ?? ""

            if status != "FINISHED" { return }

            let players = snapshot.child("players")
            let onlyMe =
                players.childrenCount == 1 &&
                players.child(uid).exists()

            if onlyMe {
                // Replace this client's player-only disconnect cleanup with room cleanup.
                room.onDisconnect().cancel()
                    .addOnCompleteListener { _ in
                        room.onDisconnect().removeValue()
                    }
            } else {
                // Make sure this client never owns a stale room-level disconnect action while
                // other spectators are still present, then restore its own presence cleanup.
                room.onDisconnect().cancel()
                    .addOnCompleteListener { _ in
                        room.child("players").child(uid)
                            .onDisconnect()
                            .removeValue()
                    }
            }
        }
    }

    /**
     * Explicit exit path from a PLAYING/FINISHED game. In a FINISHED room the final remaining
     * participant deletes the room; otherwise only this player's presence is removed.
     */
    func leaveRoomAndCleanupIfLast(
        roomCodeRaw: String,
        callback: @escaping (Result<Void, Error>) -> Void = { _ in }
    ) {
        guard let uid = currentUid() else {
            callback(.success(()))
            return
        }

        let code = roomCodeRaw.ktrim().uppercased()
        let room = root.child("rooms").child(code)

        room.get().addOnSuccessListener { snapshot in
            if !snapshot.exists() {
                callback(.success(()))
                return
            }

            let status =
                snapshot.child("meta").child("status")
                    .getValue(String.self)
                    ?? ""
            let players = snapshot.child("players")
            let isLastParticipant =
                status == "FINISHED" &&
                players.childrenCount == 1 &&
                players.child(uid).exists()

            let task: ATask<Void>
            if isLastParticipant {
                room.onDisconnect().cancel()
                task = room.removeValue()
            } else {
                room.child("players").child(uid)
                    .onDisconnect().cancel()
                task = room.child("players").child(uid).removeValue()
            }

            task.addOnSuccessListener { _ in callback(.success(())) }
                .addOnFailureListener { error in callback(.failure(error)) }
        }.addOnFailureListener { error in
            callback(.failure(error))
        }
    }

    /**
     * Publishes one completed Live shot. The path is sampled locally while the real ball is
     * flying, then uploaded once at the end; other devices replay those samples instead of
     * receiving dozens of position writes every second.
     */
    func publishLiveShot(
        roomCodeRaw: String,
        event: LiveShotEvent,
        callback: @escaping (Result<Void, Error>) -> Void = { _ in }
    ) {
        guard let uid = currentUid() else {
            callback(.failure(IllegalStateException("Not authenticated")))
            return
        }
        let code = roomCodeRaw.ktrim().uppercased()
        let ref = root.child("rooms").child(code).child("shots").push()
        let id = ref.key ?? (uid + "-" + String(ASystem.currentTimeMillis()))
        let safeName = onlineName()
        let value = TripleShotFirebaseRepository.liveShotValue(event: event, id: id, uid: uid, safeName: safeName)
        ref.setValue(value)
            .addOnSuccessListener { _ in callback(.success(())) }
            .addOnFailureListener { error in callback(.failure(error)) }
    }

    /// `event.copy(...)` of publishLiveShot (Kotlin 622-628): id, uid and nickname replaced, a missing release time
    /// set to now, at most MAX_REPLAY_SAMPLES samples.
    static func liveShotValue(event: LiveShotEvent, id: String, uid: String, safeName: String) -> LiveShotEvent {
        return event.copy(
            id: id,
            playerUid: uid,
            playerName: safeName,
            releasedAt: event.releasedAt > 0 ? event.releasedAt : ASystem.currentTimeMillis(),
            samples: Array(event.samples.prefix(MAX_REPLAY_SAMPLES))
        )
    }

    @discardableResult
    func listenLiveShots(
        roomCodeRaw: String,
        callback: @escaping (LiveShotEvent) -> Void
    ) -> ListenerHandle {
        let ref = root.child("rooms").child(roomCodeRaw.ktrim().uppercased()).child("shots")
        let query = ref.orderByChild("releasedAt")
            .startAt((ASystem.currentTimeMillis() - TripleShotFirebaseRepository.LIVE_EVENT_GRACE_MS).toDouble())
        // onChildChanged / onChildRemoved / onChildMoved / onCancelled = Unit
        let listener = ASimpleChildEventListener(onChildAdded: { snapshot, _ in
            if let event = snapshot.getValue(LiveShotEvent.self) {
                callback(event)
            }
        })
        query.addChildEventListener(listener)
        return ListenerHandle(remove: { query.removeEventListener(listener) })
    }

    /**
     * Host-only immediate cleanup for an explicitly abandoned WAITING lobby.
     * The database rules are the final authority: a PLAYING room cannot be removed
     * through this method even if a stale UI calls it by mistake.
     */
    func deleteWaitingRoom(
        roomCodeRaw: String,
        callback: @escaping (Result<Void, Error>) -> Void = { _ in }
    ) {
        let code = roomCodeRaw.ktrim().uppercased()
        root.child("rooms").child(code)
            .removeValue()
            .addOnSuccessListener { _ in callback(.success(())) }
            .addOnFailureListener { error in callback(.failure(error)) }
    }

    func leaveRoom(roomCodeRaw: String) {
        guard let uid = currentUid() else { return }
        root.child("rooms").child(roomCodeRaw.ktrim().uppercased()).child("players").child(uid).removeValue()
    }

    /**
     * Records one HUMAN knowledge answer.
     *
     * The same answer is written atomically to:
     *  - the player's all-time topic counters
     *  - the player's UTC-month topic counters
     *  - community all-time counters
     *  - community UTC-month counters
     * (and the player's UTC-week counters, the answer history entry and the profile).
     *
     * `qualityPercent` nil is Kotlin's default `if (correct) 100 else 0` (a Swift default cannot read `correct`).
     */
    func recordKnowledgeAnswer(
        playerName: String,
        category: QuestionCategory,
        correct: Bool,
        questionId: String = "",
        prompt: String = "",
        selectedAnswer: String = "",
        correctAnswer: String = "",
        qualityPercent: Int? = nil,
        gameType: String = "",
        callback: @escaping (Result<Void, Error>) -> Void = { _ in }
    ) {
        let qualityPercent = qualityPercent ?? (correct ? 100 : 0)
        ensureAnonymousAuth { authResult in
            let uid: String
            switch authResult {
            case .success(let value):
                uid = value
            case .failure(let error):
                callback(.failure(error))
                return
            }

            let categoryKey = category.name
            let monthKey = self.utcMonthKey()
            let weekKey = self.utcWeekKey()
            let safeName = self.onlineName()
            let attemptKey = self.root.child("users").child(uid).child("knowledgeAttempts").push().key
                ?? "\(ASystem.currentTimeMillis())-\(KotlinRandom.Default.nextInt(1000, 9999))"

            let updates = TripleShotFirebaseRepository.knowledgeAnswerUpdates(
                uid: uid,
                categoryKey: categoryKey,
                monthKey: monthKey,
                weekKey: weekKey,
                safeName: safeName,
                attemptKey: attemptKey,
                correct: correct,
                questionId: questionId,
                prompt: prompt,
                selectedAnswer: selectedAnswer,
                correctAnswer: correctAnswer,
                qualityPercent: qualityPercent,
                gameType: gameType
            )

            self.root.updateChildren(updates)
                .addOnSuccessListener { _ in callback(.success(())) }
                .addOnFailureListener { error in callback(.failure(error)) }
        }
    }

    /// The `updates` map of recordKnowledgeAnswer (Kotlin 714-748): 22 paths, 27 when the answer is correct.
    static func knowledgeAnswerUpdates(
        uid: String,
        categoryKey: String,
        monthKey: String,
        weekKey: String,
        safeName: String,
        attemptKey: String,
        correct: Bool,
        questionId: String,
        prompt: String,
        selectedAnswer: String,
        correctAnswer: String,
        qualityPercent: Int,
        gameType: String
    ) -> [String: Any] {
        var updates: [String: Any] = [
            "users/\(uid)/profile/uid": uid,
            "users/\(uid)/profile/displayName": safeName,
            "users/\(uid)/profile/updatedAt": AServerValue.TIMESTAMP,

            "users/\(uid)/knowledge/allTime/\(categoryKey)/total": AServerValue.increment(1),
            "users/\(uid)/knowledge/allTime/\(categoryKey)/updatedAt": AServerValue.TIMESTAMP,
            "users/\(uid)/knowledge/monthly/\(monthKey)/\(categoryKey)/total": AServerValue.increment(1),
            "users/\(uid)/knowledge/monthly/\(monthKey)/\(categoryKey)/updatedAt": AServerValue.TIMESTAMP,
            "users/\(uid)/knowledge/weekly/\(weekKey)/\(categoryKey)/total": AServerValue.increment(1),
            "users/\(uid)/knowledge/weekly/\(weekKey)/\(categoryKey)/updatedAt": AServerValue.TIMESTAMP,

            "communityKnowledge/allTime/\(categoryKey)/total": AServerValue.increment(1),
            "communityKnowledge/allTime/\(categoryKey)/updatedAt": AServerValue.TIMESTAMP,
            "communityKnowledge/monthly/\(monthKey)/\(categoryKey)/total": AServerValue.increment(1),
            "communityKnowledge/monthly/\(monthKey)/\(categoryKey)/updatedAt": AServerValue.TIMESTAMP,

            "users/\(uid)/knowledgeAttempts/\(attemptKey)/questionId": wireTake(questionId, 96),
            "users/\(uid)/knowledgeAttempts/\(attemptKey)/category": categoryKey,
            "users/\(uid)/knowledgeAttempts/\(attemptKey)/prompt": wireTake(prompt, 600),
            "users/\(uid)/knowledgeAttempts/\(attemptKey)/selectedAnswer": wireTake(selectedAnswer, 400),
            "users/\(uid)/knowledgeAttempts/\(attemptKey)/correctAnswer": wireTake(correctAnswer, 400),
            "users/\(uid)/knowledgeAttempts/\(attemptKey)/qualityPercent": qualityPercent.coerceIn(0, 100),
            "users/\(uid)/knowledgeAttempts/\(attemptKey)/correct": correct,
            "users/\(uid)/knowledgeAttempts/\(attemptKey)/gameType": wireTake(gameType, 32),
            "users/\(uid)/knowledgeAttempts/\(attemptKey)/answeredAt": AServerValue.TIMESTAMP
        ]

        if correct {
            updates["users/\(uid)/knowledge/allTime/\(categoryKey)/correct"] = AServerValue.increment(1)
            updates["users/\(uid)/knowledge/monthly/\(monthKey)/\(categoryKey)/correct"] = AServerValue.increment(1)
            updates["users/\(uid)/knowledge/weekly/\(weekKey)/\(categoryKey)/correct"] = AServerValue.increment(1)
            updates["communityKnowledge/allTime/\(categoryKey)/correct"] = AServerValue.increment(1)
            updates["communityKnowledge/monthly/\(monthKey)/\(categoryKey)/correct"] = AServerValue.increment(1)
        }
        return updates
    }

    /// Kotlin `value.take(n)` as the text reaches the database: the first n UTF-16 units; when the cut splits a
    /// surrogate pair, Android's websocket (`String.getBytes(UTF_8)`) sends the lone high surrogate as '?' (JVM
    /// vectors in FirebaseRepositoryTests). AndroidKit's `ktake` would leave U+FFFD instead.
    static func wireTake(_ value: String, _ n: Int) -> String {
        let units = Array(value.utf16)
        if units.count <= n {
            return value
        }
        var head = Array(units[0..<n])
        if let last = head.last, last >= 0xD800 && last <= 0xDBFF {
            head[head.count - 1] = 0x3F
        }
        return String(decoding: head, as: UTF16.self)
    }

    /** Loads all aggregate counters plus the newest answer history for the signed-in player. */
    func loadKnowledgeDashboard(
        attemptLimit: Int = 250,
        callback: @escaping (Result<KnowledgeDashboard, Error>) -> Void
    ) {
        ensureAnonymousAuth { authResult in
            let uid: String
            switch authResult {
            case .success(let value):
                uid = value
            case .failure(let error):
                callback(.failure(error))
                return
            }

            self.root.child("users").child(uid).get()
                .addOnSuccessListener { userSnap in
                    callback(.success(self.knowledgeDashboard(userSnap: userSnap, attemptLimit: attemptLimit)))
                }
                .addOnFailureListener { error in callback(.failure(error)) }
        }
    }

    /// The success listener of loadKnowledgeDashboard (Kotlin 768-812): buckets of all time and of the current UTC
    /// month and ISO week (read now, like Android), and the newest attempts.
    func knowledgeDashboard(userSnap: ADataSnapshot, attemptLimit: Int) -> KnowledgeDashboard {
        func parseBuckets(snapshot: ADataSnapshot) -> KLinkedMap<String, KnowledgeBucket> {
            // snapshot.children.associate { ... }.filterKeys { it.isNotBlank() }
            var associated = KLinkedMap<String, KnowledgeBucket>()
            for categorySnap in snapshot.children {
                let total = categorySnap.child("total").getValue(Int64.self)?.toInt() ?? 0
                let correctCount = categorySnap.child("correct").getValue(Int64.self)?.toInt() ?? 0
                associated[categorySnap.key ?? ""] = KnowledgeBucket(total: total, correct: correctCount)
            }
            var filtered = KLinkedMap<String, KnowledgeBucket>()
            for (key, bucket) in associated where !key.kotlinIsBlank {
                filtered[key] = bucket
            }
            return filtered
        }

        let allTime = parseBuckets(snapshot: userSnap.child("knowledge").child("allTime"))
        let currentMonth = parseBuckets(
            snapshot: userSnap.child("knowledge").child("monthly").child(utcMonthKey())
        )
        let currentWeek = parseBuckets(
            snapshot: userSnap.child("knowledge").child("weekly").child(utcWeekKey())
        )

        let records: [KnowledgeAttemptRecord] = userSnap.child("knowledgeAttempts").children
            .compactMap { (snap: ADataSnapshot) -> KnowledgeAttemptRecord? in
                guard let key = snap.key else { return nil }
                return KnowledgeAttemptRecord(
                    id: key,
                    questionId: snap.child("questionId").getValue(String.self) ?? "",
                    category: snap.child("category").getValue(String.self) ?? "",
                    prompt: snap.child("prompt").getValue(String.self) ?? "",
                    selectedAnswer: snap.child("selectedAnswer").getValue(String.self) ?? "",
                    correctAnswer: snap.child("correctAnswer").getValue(String.self) ?? "",
                    qualityPercent: snap.child("qualityPercent").getValue(Int64.self)?.toInt() ?? 0,
                    correct: snap.child("correct").getValue(Bool.self) ?? false,
                    gameType: snap.child("gameType").getValue(String.self) ?? "",
                    answeredAt: snap.child("answeredAt").getValue(Int64.self) ?? 0
                )
            }
        let attempts = Array(records
            .kSortedByDescending { $0.answeredAt }
            .prefix(attemptLimit.coerceIn(20, 1000)))

        return KnowledgeDashboard(
            allTime: allTime,
            currentMonth: currentMonth,
            currentWeek: currentWeek,
            attempts: attempts
        )
    }

    func saveLeaderboardBest<S: Sequence>(
        playerName: String,
        score: Int,
        bestShootingStreak: Int,
        bestKnowledgeStreak: Int,
        correctAnswers: Int,
        shots: Int,
        madeShots: Int,
        selectedCategories: S,
        callback: @escaping (Result<LeaderboardEntry, Error>) -> Void
    ) where S.Element == QuestionCategory {
        let selectedCategories = KLinkedSet(selectedCategories)
        ensureAnonymousAuth { authResult in
            let uid: String
            switch authResult {
            case .success(let value):
                uid = value
            case .failure(let error):
                callback(.failure(error))
                return
            }
            let ref = self.root.child("leaderboard").child(uid)
            ref.runTransaction(SaveLeaderboardBestHandler(
                repository: self,
                uid: uid,
                score: score,
                bestShootingStreak: bestShootingStreak,
                bestKnowledgeStreak: bestKnowledgeStreak,
                correctAnswers: correctAnswers,
                shots: shots,
                madeShots: madeShots,
                selectedCategories: selectedCategories,
                callback: callback
            ))
        }
    }

    func loadTopByScore(callback: @escaping (Result<[LeaderboardEntry], Error>) -> Void) {
        root.child("leaderboard").orderByChild("bestScore").limitToLast(20).get()
            .addOnSuccessListener { snap in
                callback(.success(TripleShotFirebaseRepository.topByScore(snap: snap)))
            }
            .addOnFailureListener { error in callback(.failure(error)) }
    }

    /// `snap.children.mapNotNull { getValue(LeaderboardEntry) }.sortedByDescending { it.bestScore }` (stable: equal
    /// scores keep the query's ascending key order).
    static func topByScore(snap: ADataSnapshot) -> [LeaderboardEntry] {
        return snap.children.compactMap { $0.getValue(LeaderboardEntry.self) }
            .kSortedByDescending { $0.bestScore }
    }

    func loadTopByShootingStreak(callback: @escaping (Result<[LeaderboardEntry], Error>) -> Void) {
        root.child("leaderboard").orderByChild("bestShootingStreak").limitToLast(20).get()
            .addOnSuccessListener { snap in
                callback(.success(TripleShotFirebaseRepository.topByShootingStreak(snap: snap)))
            }
            .addOnFailureListener { error in callback(.failure(error)) }
    }

    /// Same as topByScore, by `bestShootingStreak`.
    static func topByShootingStreak(snap: ADataSnapshot) -> [LeaderboardEntry] {
        return snap.children.compactMap { $0.getValue(LeaderboardEntry.self) }
            .kSortedByDescending { $0.bestShootingStreak }
    }

    func getScoreRank(score: Int, callback: @escaping (Result<Int, Error>) -> Void) {
        root.child("leaderboard").orderByChild("bestScore").startAt(score.toDouble()).get()
            .addOnSuccessListener { snap in
                callback(.success(TripleShotFirebaseRepository.scoreRank(snap: snap, score: score)))
            }
            .addOnFailureListener { error in callback(.failure(error)) }
    }

    /// `higher + 1` of getScoreRank: entries with `bestScore > score` (a missing score counts as 0); ties share a rank.
    static func scoreRank(snap: ADataSnapshot, score: Int) -> Int {
        let higher = snap.children.filter { ($0.child("bestScore").getValue(Int64.self)?.toInt() ?? 0) > score }.count
        return higher + 1
    }

    /// `SimpleDateFormat("yyyy-MM", Locale.US)` in UTC (private in Kotlin).
    func utcMonthKey(nowMs: Int64 = ASystem.currentTimeMillis()) -> String {
        let format = ASimpleDateFormat("yyyy-MM", ALocale.US)
        format.timeZone = ATimeZone.getTimeZone("UTC")
        return format.format(ADate(nowMs))
    }

    /// The ISO week-year and week (`"%04d-W%02d"`) of a UTC calendar with Monday first and 4 minimal days (private in
    /// Kotlin).
    func utcWeekKey(nowMs: Int64 = ASystem.currentTimeMillis()) -> String {
        let cal = ACalendar.getInstance(ATimeZone.getTimeZone("UTC"), ALocale.US)
        cal.timeInMillis = nowMs
        cal.firstDayOfWeek = ACalendar.MONDAY
        cal.minimalDaysInFirstWeek = 4
        let adjust: Int
        if cal.get(ACalendar.MONTH) == ACalendar.JANUARY && cal.get(ACalendar.WEEK_OF_YEAR) >= 52 {
            adjust = -1
        } else if cal.get(ACalendar.MONTH) == ACalendar.DECEMBER && cal.get(ACalendar.WEEK_OF_YEAR) == 1 {
            adjust = 1
        } else {
            adjust = 0
        }
        return AFormat.format(
            ALocale.US,
            "%04d-W%02d",
            cal.get(ACalendar.YEAR) + adjust,
            cal.get(ACalendar.WEEK_OF_YEAR)
        )
    }

    /// A fresh player node (private in Kotlin). `name` is ignored: the online nickname is written.
    func playerMap(uid: String, name: String) -> [String: Any] {
        return [
            "uid": uid,
            "name": onlineName(),
            "score": 0,
            "knowledgeStreak": 0,
            "shootingStreak": 0,
            "bestKnowledgeStreak": 0,
            "bestShootingStreak": 0,
            "correctAnswers": 0,
            "madeShots": 0,
            "shots": 0,
            "lastEvent": "",
            "finished": false,
            "updatedAt": AServerValue.TIMESTAMP
        ]
    }

    // companion object (DATABASE_URL, ROOM_ALPHABET, MAX_REPLAY_SAMPLES and LIVE_EVENT_GRACE_MS are private in Kotlin;
    // internal here because the initialiser's default argument and the parity tests read them).
    static let ROOT_NODE = "tripleShot"

    static let DATABASE_URL =
        "https://minikswish-default-rtdb.europe-west1.firebasedatabase.app"

    static let ROOM_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    static let MAX_REPLAY_SAMPLES = 60
    static let LIVE_EVENT_GRACE_MS: Int64 = 750
}

// MARK: - Exceptions created by the repository

extension TripleShotFirebaseRepository {
    /// java.lang.IllegalStateException(message).
    final class IllegalStateException: AFirebaseException, @unchecked Sendable {
        override var javaClassName: String {
            return "java.lang.IllegalStateException"
        }
    }

    /// java.lang.IllegalArgumentException(message).
    final class IllegalArgumentException: AFirebaseException, @unchecked Sendable {
        override var javaClassName: String {
            return "java.lang.IllegalArgumentException"
        }
    }
}

// MARK: - Transaction.Handler objects (Kotlin `object : Transaction.Handler { ... }`)

extension TripleShotFirebaseRepository {
    /// The handler of configureLiveHorseChallenge: SETTING -> ATTEMPT for the current setter.
    final class ConfigureLiveHorseChallengeHandler: ATransaction.Handler {
        let uid: String
        let category: QuestionCategory
        let spotId: String
        let spotX: Float
        let spotY: Float
        let callback: (Result<Void, Error>) -> Void

        init(
            uid: String,
            category: QuestionCategory,
            spotId: String,
            spotX: Float,
            spotY: Float,
            callback: @escaping (Result<Void, Error>) -> Void
        ) {
            self.uid = uid
            self.category = category
            self.spotId = spotId
            self.spotX = spotX
            self.spotY = spotY
            self.callback = callback
        }

        func doTransaction(_ currentData: AMutableData) -> ATransaction.Result {
            guard let state = currentData.getValue(LiveHorseState.self) else {
                return ATransaction.abort()
            }

            let updated: LiveHorseState
            do {
                updated = try HorseGameEngine.Multiplayer.configureChallenge(
                    state: state,
                    actorUid: uid,
                    category: category,
                    spotId: spotId,
                    spotX: spotX,
                    spotY: spotY
                )
            } catch {
                return ATransaction.abort()
            }

            currentData.value =
                updated.copy(updatedAt: ASystem.currentTimeMillis())
            return ATransaction.success(currentData)
        }

        func onComplete(
            _ error: ADatabaseError?,
            _ committed: Bool,
            _ currentData: ADataSnapshot?
        ) {
            if let error = error {
                callback(.failure(error.toException()))
            } else if !committed {
                callback(
                    .failure(IllegalStateException("HORSE challenge was not accepted"))
                )
            } else {
                callback(.success(()))
            }
        }
    }

    /// The handler of resolveLiveHorseAttempt: one attempt applied; a finished match also marks the room FINISHED.
    final class ResolveLiveHorseAttemptHandler: ATransaction.Handler {
        let room: ADatabaseReference
        let uid: String
        let answerCorrect: Bool
        let made: Bool
        let callback: (Result<LiveHorseState, Error>) -> Void

        init(
            room: ADatabaseReference,
            uid: String,
            answerCorrect: Bool,
            made: Bool,
            callback: @escaping (Result<LiveHorseState, Error>) -> Void
        ) {
            self.room = room
            self.uid = uid
            self.answerCorrect = answerCorrect
            self.made = made
            self.callback = callback
        }

        func doTransaction(_ currentData: AMutableData) -> ATransaction.Result {
            guard let state = currentData.getValue(LiveHorseState.self) else {
                return ATransaction.abort()
            }

            let resolved: HorseGameEngine.Multiplayer.Resolution
            do {
                resolved = try HorseGameEngine.Multiplayer.resolveAttempt(
                    state: state,
                    actorUid: uid,
                    answerCorrect: answerCorrect,
                    made: made
                )
            } catch {
                return ATransaction.abort()
            }

            currentData.value =
                resolved.state.copy(updatedAt: ASystem.currentTimeMillis())
            return ATransaction.success(currentData)
        }

        func onComplete(
            _ error: ADatabaseError?,
            _ committed: Bool,
            _ currentData: ADataSnapshot?
        ) {
            if error != nil || !committed {
                let failure: Error = (error?.toException() as Error?)
                    ?? IllegalStateException("HORSE attempt was not accepted")
                callback(.failure(failure))
                return
            }

            guard let state = currentData?.getValue(LiveHorseState.self) else {
                callback(.failure(IllegalStateException("HORSE state missing")))
                return
            }

            if state.isFinished {
                room.child("meta").child("status").setValue("FINISHED")
            }

            callback(.success(state))
        }
    }

    /// The handler of saveLeaderboardBest: all-time maxima, and the snapshot of the run that owns bestScore.
    final class SaveLeaderboardBestHandler: ATransaction.Handler {
        let repository: TripleShotFirebaseRepository
        let uid: String
        let score: Int
        let bestShootingStreak: Int
        let bestKnowledgeStreak: Int
        let correctAnswers: Int
        let shots: Int
        let madeShots: Int
        let selectedCategories: KLinkedSet<QuestionCategory>
        let callback: (Result<LeaderboardEntry, Error>) -> Void

        init(
            repository: TripleShotFirebaseRepository,
            uid: String,
            score: Int,
            bestShootingStreak: Int,
            bestKnowledgeStreak: Int,
            correctAnswers: Int,
            shots: Int,
            madeShots: Int,
            selectedCategories: KLinkedSet<QuestionCategory>,
            callback: @escaping (Result<LeaderboardEntry, Error>) -> Void
        ) {
            self.repository = repository
            self.uid = uid
            self.score = score
            self.bestShootingStreak = bestShootingStreak
            self.bestKnowledgeStreak = bestKnowledgeStreak
            self.correctAnswers = correctAnswers
            self.shots = shots
            self.madeShots = madeShots
            self.selectedCategories = selectedCategories
            self.callback = callback
        }

        func doTransaction(_ currentData: AMutableData) -> ATransaction.Result {
            let decoded = currentData.getValue(LeaderboardEntry.self)
            // Android: getValue throws a DatabaseException out of doTransaction for a malformed entry, so the
            // transaction aborts with that error before anything else runs (AndroidKit recorded it in `run`).
            if currentData.run.failure != nil {
                return ATransaction.abort()
            }
            let old =
                decoded
                    ?? LeaderboardEntry(uid: uid)

            /*
             * Keep a coherent snapshot of the run that actually owns bestScore.
             * Existing installations may already have a legacy bestScore but no
             * snapshot fields; an equal score is allowed to initialise them once.
             */
            let replacesBestRun =
                score > old.bestScore ||
                (score == old.bestScore && old.bestRunShots == 0)

            let knowledgeAccuracy =
                shots <= 0 ? 0
                : ((correctAnswers.toFloat() * Float(100)) / shots.toFloat()).toInt().coerceIn(0, 100)
            let shootingPercent =
                shots <= 0 ? 0
                : ((madeShots.toFloat() * Float(100)) / shots.toFloat()).toInt().coerceIn(0, 100)

            let updated = LeaderboardEntry(
                uid: uid,
                name: repository.onlineName(),
                bestScore: max(old.bestScore, score),

                // Independent all-time records remain available for the streak tab.
                bestShootingStreak:
                max(old.bestShootingStreak, bestShootingStreak),
                bestKnowledgeStreak:
                max(old.bestKnowledgeStreak, bestKnowledgeStreak),
                bestCorrectAnswers:
                max(old.bestCorrectAnswers, correctAnswers),

                // Best-score-run snapshot only changes when that record changes.
                bestRunCorrectAnswers:
                replacesBestRun ? correctAnswers : old.bestRunCorrectAnswers,
                bestRunShots:
                replacesBestRun ? shots : old.bestRunShots,
                bestRunMadeShots:
                replacesBestRun ? madeShots : old.bestRunMadeShots,
                bestRunKnowledgeAccuracyPercent:
                replacesBestRun ? knowledgeAccuracy
                : old.bestRunKnowledgeAccuracyPercent,
                bestRunShootingPercent:
                replacesBestRun ? shootingPercent
                : old.bestRunShootingPercent,
                bestRunCategories:
                replacesBestRun
                    ? selectedCategories
                        .map { $0.name }
                        .stableSorted { $0.javaPrecedes($1) }
                    : old.bestRunCategories,

                updatedAt: ASystem.currentTimeMillis()
            )
            currentData.value = updated
            return ATransaction.success(currentData)
        }

        func onComplete(
            _ error: ADatabaseError?,
            _ committed: Bool,
            _ currentData: ADataSnapshot?
        ) {
            if error != nil || !committed {
                let failure: Error = (error?.toException() as Error?)
                    ?? IllegalStateException("Leaderboard transaction failed")
                callback(.failure(failure))
            } else {
                let result = currentData?.getValue(LeaderboardEntry.self)
                if let result = result {
                    callback(.success(result))
                } else {
                    callback(
                        .failure(
                            IllegalStateException("Leaderboard result missing")
                        )
                    )
                }
            }
        }
    }
}

// MARK: - Positional (Kotlin call-site) forms

extension TripleShotFirebaseRepository {
    func joinRoom(_ codeRaw: String, _ playerName: String, _ callback: @escaping (Result<Int64, Error>) -> Void) {
        joinRoom(codeRaw: codeRaw, playerName: playerName, callback: callback)
    }

    func startRoom(_ codeRaw: String, _ callback: @escaping (Result<Void, Error>) -> Void) {
        startRoom(codeRaw: codeRaw, callback: callback)
    }

    @discardableResult
    func listenRoomMeta(_ codeRaw: String, _ callback: @escaping (RoomMeta?) -> Void) -> ListenerHandle {
        return listenRoomMeta(codeRaw: codeRaw, callback: callback)
    }

    @discardableResult
    func listenLiveHorseState(_ codeRaw: String, _ callback: @escaping (LiveHorseState?) -> Void) -> ListenerHandle {
        return listenLiveHorseState(codeRaw: codeRaw, callback: callback)
    }

    @discardableResult
    func listenRoomPlayers(_ codeRaw: String, _ callback: @escaping ([LivePlayerState]) -> Void) -> ListenerHandle {
        return listenRoomPlayers(codeRaw: codeRaw, callback: callback)
    }

    func updateLiveState(_ roomCodeRaw: String, _ state: LivePlayerState) {
        updateLiveState(roomCodeRaw: roomCodeRaw, state: state)
    }

    func markRoomFinished(_ roomCodeRaw: String, _ callback: @escaping (Result<Void, Error>) -> Void = { _ in }) {
        markRoomFinished(roomCodeRaw: roomCodeRaw, callback: callback)
    }

    func armFinishedRoomCleanupIfLast(_ roomCodeRaw: String) {
        armFinishedRoomCleanupIfLast(roomCodeRaw: roomCodeRaw)
    }

    func leaveRoomAndCleanupIfLast(_ roomCodeRaw: String, _ callback: @escaping (Result<Void, Error>) -> Void = { _ in }) {
        leaveRoomAndCleanupIfLast(roomCodeRaw: roomCodeRaw, callback: callback)
    }

    @discardableResult
    func listenLiveShots(_ roomCodeRaw: String, _ callback: @escaping (LiveShotEvent) -> Void) -> ListenerHandle {
        return listenLiveShots(roomCodeRaw: roomCodeRaw, callback: callback)
    }

    func deleteWaitingRoom(_ roomCodeRaw: String, _ callback: @escaping (Result<Void, Error>) -> Void = { _ in }) {
        deleteWaitingRoom(roomCodeRaw: roomCodeRaw, callback: callback)
    }

    func leaveRoom(_ roomCodeRaw: String) {
        leaveRoom(roomCodeRaw: roomCodeRaw)
    }

    func getScoreRank(_ score: Int, _ callback: @escaping (Result<Int, Error>) -> Void) {
        getScoreRank(score: score, callback: callback)
    }
}
