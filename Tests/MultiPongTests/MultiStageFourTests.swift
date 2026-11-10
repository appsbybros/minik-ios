import XCTest
@testable import MinikMultiPingPong

// Multi Ping Pong iOS stage 4 (2026-11-09): rooms, from Android MinikCrossPong 5375378 / 3f13c40 (Play again and the Loading
// page), 1fc4bc2 (rematch rooms, saved friendly and team lineups, clockwise seats), 83b050d / 9adf1f1 (Back asks Save and exit /
// Exit without saving / Stay; explicit saves; discarding restores the save, through a Firebase transaction for an online lobby)
// and bb8acda (two-player tournaments stay pairs). Ported Kotlin tests: FriendlyRematchTest (5375378), SavedLobbyRollbackTest
// (9adf1f1) and TwoPlayerTournamentTest (bb8acda); the others pin the Android behaviour directly.
final class MultiStageFourTests: XCTestCase {
    override func setUp() { super.setUp(); MPText.configure("en") }
    override func tearDown() { MPText.configure("en"); super.tearDown() }

    private func defaults() throws -> (UserDefaults, String) {
        let suite = "multi.stage4." + UUID().uuidString
        return (try XCTUnwrap(UserDefaults(suiteName: suite)), suite)
    }
    private func bot(_ id: String, prefix: String = "bot_") -> MPParticipant {
        MPParticipant(identity: MPIdentity(id: prefix + id, name: id), bot: (MPRoster.find(id) ?? MPRoster.all[0]).profile)
    }
    @MainActor private func settle(_ done: () -> Bool) async {
        for _ in 0..<200 where !done() { await Task.yield() }
    }

    // ---- Kotlin FriendlyRematchTest (5375378) ----

    func testRematchPreservesConfigurationAndRosterButResetsMatchIdentity() throws {
        for n in 2...4 {
            var people: [String: MPParticipant] = ["me": MPParticipant(identity: MPIdentity(id: "me", name: "Me", avatar: 0, characterId: "miniko"))]
            for id in ["minik", "flare", "kyra"].prefix(n - 1) {
                people[id] = MPParticipant(identity: MPIdentity(id: id, name: id, avatar: 0, characterId: id), bot: MPRoster.find(id)?.profile)
            }
            var m = MPFixture(id: "old", players: people.keys.sorted(), seed: 21)
            m.phase = .finished; m.scores = (0..<n).map { 7 - $0 }; m.winner = "me"
            var s = MPSession(code: "ABCDEF", kind: .friendly, host: MPIdentity(id: "me", name: "Me"), capacity: n, tableSize: n, gameMode: .elimination)
            s.difficulty = 3; s.target = 11; s.participants = people; s.matches = [m.id: m]; s.state = "FINISHED"
            XCTAssertTrue(MPFriendlyRematch.available(s, uid: "me"))
            let next = try MPFriendlyRematch.create(s, uid: "me", code: "BCDEFG", now: 100)
            XCTAssertEqual(s.participants, next.participants)
            XCTAssertEqual(s.difficulty, next.difficulty)
            XCTAssertEqual(s.target, next.target)
            XCTAssertEqual(s.gameMode, next.gameMode)
            XCTAssertEqual("WAITING", next.state)
            XCTAssertTrue(next.matches.isEmpty)
            XCTAssertEqual(n, next.tableSize)
            XCTAssertEqual("BCDEFG", next.code)
            XCTAssertEqual(100, next.createdAt)
            XCTAssertEqual(100, next.lastActivityAt)
            XCTAssertEqual(s.seats, next.seats)
        }
    }

    func testRematchDoesNotForceHumanOpponentsIntoAnotherMatch() {
        var s = MPSession(code: "ABCDEF", kind: .friendly, host: MPIdentity(id: "me", name: "Me"))
        s.participants = ["me": MPParticipant(identity: MPIdentity(id: "me", name: "Me")), "other": MPParticipant(identity: MPIdentity(id: "other", name: "Other"))]
        var x = MPFixture(id: "x", a: "me", b: "other", seed: 21)
        x.phase = .finished
        s.matches = ["x": x]
        XCTAssertFalse(MPFriendlyRematch.available(s, uid: "me"))
        XCTAssertThrowsError(try MPFriendlyRematch.create(s, uid: "me", code: "BCDEFG", now: 1))
    }

    /// A room not yet complete, a tournament, or a house player never offers Play again.
    func testRematchOnlyForACompletedFriendlyGameOfThisHuman() {
        var s = MPSession(code: "ABCDEF", kind: .friendly, host: MPIdentity(id: "me", name: "Me"))
        s.participants["bot_kyra"] = bot("kyra")
        XCTAssertFalse(MPFriendlyRematch.available(s, uid: "me"), "no match yet")
        var m = MPFixture(id: "m", a: "me", b: "bot_kyra", seed: 1)
        m.phase = .finished
        s.matches = [m.id: m]
        XCTAssertTrue(MPFriendlyRematch.available(s, uid: "me"))
        XCTAssertFalse(MPFriendlyRematch.available(s, uid: "bot_kyra"))
        XCTAssertFalse(MPFriendlyRematch.available(s, uid: "outsider"))
        var tournament = s
        tournament.kind = .tournament
        XCTAssertFalse(MPFriendlyRematch.available(tournament, uid: "me"))
    }

    // ---- Kotlin SavedLobbyRollbackTest (9adf1f1) ----

    private let owner = MPParticipant(identity: MPIdentity(id: "host", name: "Owner"))
    private func savedLobby() -> MPSession {
        var s = MPSession(code: "ABC123", kind: .tournament, host: MPIdentity(id: "host", name: "Owner"), capacity: 8)
        s.participants = ["host": owner, "bot_minik": bot("minik")]
        return s
    }

    func testRollbackRestoresAddedAndRemovedPlayersKeepingPeerJoin() throws {
        let saved = savedLobby()
        var edited = saved
        edited.participants = ["host": owner, "bot_kyra": bot("kyra")]
        let guest = MPParticipant(identity: MPIdentity(id: "guest", name: "Guest"))
        var latest = edited
        latest.participants["guest"] = guest
        latest.connections = ["guest": ["live": true]]
        latest.lastActivityAt = 999
        let actual = try MPSavedLobbyRollback.restore(saved, edited: edited, latest: latest, uid: "host")
        var expected = saved.participants
        expected["guest"] = guest
        XCTAssertEqual(expected, actual.participants)
        XCTAssertEqual(latest.connections, actual.connections)
        XCTAssertEqual(999, actual.lastActivityAt)
    }

    func testRollbackRefusesToOverwriteStartedRoomOrConcurrentBotEdits() {
        let saved = savedLobby()
        var edited = saved
        edited.participants["bot_kyra"] = bot("kyra")
        var active = edited; active.state = "ACTIVE"
        var otherHost = edited; otherHost.host = "guest"
        var otherEdit = edited; otherEdit.participants["bot_flare"] = bot("flare")
        for latest in [active, otherHost, otherEdit] {
            XCTAssertThrowsError(try MPSavedLobbyRollback.restore(saved, edited: edited, latest: latest, uid: "host"))
        }
    }

    func testFriendlyRollbackRestoresBotSeatButNeverDisplacesHuman() throws {
        var before = savedLobby()
        before.kind = .friendly; before.capacity = 4; before.tableSize = 4; before.seats = ["host": 0, "bot_minik": 2]
        var edited = before
        edited.participants = ["host": owner, "bot_kyra": bot("kyra")]
        edited.seats = ["host": 0, "bot_kyra": 1]
        XCTAssertEqual(before.seats, try MPSavedLobbyRollback.restore(before, edited: edited, latest: edited, uid: "host").seats)
        var occupied = edited
        occupied.participants["guest"] = MPParticipant(identity: MPIdentity(id: "guest", name: "Guest"))
        occupied.seats["guest"] = 2
        XCTAssertThrowsError(try MPSavedLobbyRollback.restore(before, edited: edited, latest: occupied, uid: "host"))
    }

    // ---- Kotlin TwoPlayerTournamentTest (bb8acda) ----

    private func tournament(_ n: Int, _ size: Int, _ format: MPTournamentFormat, kind: MPSessionKind = .tournament) -> MPSession {
        MPSession(code: "PARR23", kind: kind, host: MPIdentity(id: "host", name: "Host"), capacity: n, legs: 1, winPoints: 3, difficulty: 0,
                  target: 7, format: format, tableSize: size, gameMode: .elimination, advance: 1)
    }

    func testTwoPlayersRemainTwoAcrossFormatsAndStaleTableSettings() throws {
        for format in MPTournamentFormat.allCases {
            for size in 2...4 {
                let s = tournament(2, size, format)
                XCTAssertEqual(2, s.capacity); XCTAssertEqual(2, s.tableSize); XCTAssertFalse(s.grouped)
                let house = MPParticipant(identity: MPIdentity(id: "bot_house", name: "Opponent"), bot: MPRoster.all[0].profile)
                let ready = try MPRules.addBot(s, actor: "host", bot: house)
                let started = try MPRules.start(ready, actor: "host")
                XCTAssertEqual("ACTIVE", started.state, "\(format) \(size)")
                XCTAssertEqual(1, started.matches.count, "\(format) \(size)")
                XCTAssertEqual(["host", "bot_house"], Set(try XCTUnwrap(started.matches.values.first).players))
                let restored = try MPCodec.session(MPSaveComparison.json(try MPCodec.session(started)))
                XCTAssertEqual(2, restored.capacity); XCTAssertEqual(2, restored.tableSize)
            }
        }
    }

    func testLargerTournamentsAndFriendlyTablesKeepTheirSettings() {
        for format in MPTournamentFormat.allCases {
            for n in 3...8 {
                for size in 3...4 {
                    let s = tournament(n, size, format)
                    XCTAssertEqual(n, s.capacity); XCTAssertEqual(size, s.tableSize); XCTAssertTrue(s.grouped)
                }
            }
        }
        for size in 2...4 {
            let s = tournament(2, size, .roundRobin, kind: .friendly)
            XCTAssertEqual(size, s.capacity); XCTAssertEqual(size, s.tableSize)
        }
    }

    // ---- SaveComparison (83b050d) ----

    func testSaveComparisonIgnoresHousekeepingAndComparesNumbersAsDoubles() {
        let a: [String: Any] = ["a": 1, "connections": ["x": true], "lastActivityAt": 5,
                                "m": ["revision": 3, "serverAt": 4, "clientAt": 6, "v": [1, 2]] as [String: Any]]
        let b: [String: Any] = ["a": 1.0, "connections": [:] as [String: Any], "lastActivityAt": 9, "m": ["revision": 8, "v": [1.0, 2.0]] as [String: Any]]
        XCTAssertTrue(MPSaveComparison.equal(MPSaveComparison.meaningful(a), MPSaveComparison.meaningful(b)))
        let c: [String: Any] = ["a": 1, "m": ["v": [1, 3]]]
        XCTAssertFalse(MPSaveComparison.equal(MPSaveComparison.meaningful(a), MPSaveComparison.meaningful(c)))
        // A boolean is not the number 1 (Kotlin Boolean is not a Number).
        XCTAssertFalse(MPSaveComparison.equal(MPSaveComparison.meaningful(MPSaveComparison.json(["v": true])), MPSaveComparison.meaningful(MPSaveComparison.json(["v": 1]))))
    }

    func testSameRoomIgnoresPresenceAndActivity() {
        let s = savedLobby()
        var later = s
        later.connections = ["host": ["3": true]]
        later.lastActivityAt = s.lastActivityAt + 60_000
        XCTAssertTrue(MPSaveComparison.same(s, later))
        var edited = s
        edited.participants["bot_kyra"] = bot("kyra")
        XCTAssertFalse(MPSaveComparison.same(s, edited))
    }

    // ---- RoomBook explicit saves (83b050d) ----

    func testExplicitSaveKeepsACompletedRoomAndForgetDropsIt() throws {
        let (store, suite) = try defaults()
        defer { store.removePersistentDomain(forName: suite) }
        let book = MPPreferences(store)
        var s = MPSession(code: "SAV234", kind: .friendly, host: MPIdentity(id: "me", name: "Me"))
        s.participants["bot_kyra"] = bot("kyra")
        var m = MPFixture(id: "m", a: "me", b: "bot_kyra", seed: 1)
        m.phase = .finished
        s.matches = [m.id: m]
        XCTAssertTrue(s.complete)
        book.remember(s)
        XCTAssertTrue(book.rooms.isEmpty, "a completed room without an explicit save is not listed")
        XCTAssertTrue(book.completionKnown(s))
        try book.saveExplicitly(s)
        XCTAssertFalse(book.completionKnown(s), "an explicit save clears the completion mark")
        XCTAssertTrue(book.hasExplicitSave(s))
        XCTAssertEqual(s, book.explicitSave(s))
        XCTAssertEqual([s.id], book.rooms.map { $0.id })
        book.remember(s)
        XCTAssertEqual([s.id], book.rooms.map { $0.id }, "an explicitly saved completed room stays listed")
        book.dismissResult(s)
        XCTAssertFalse(book.hasExplicitSave(s))
        XCTAssertTrue(book.rooms.isEmpty)
        book.remember(s)
        XCTAssertTrue(book.rooms.isEmpty, "a late refresh after Done is ignored")
    }

    @MainActor
    func testMigrationMakesListedRoomsExplicitSavesOnce() async throws {
        let (store, suite) = try defaults()
        defer { store.removePersistentDomain(forName: suite) }
        let book = MPPreferences(store), local = MPLocalRepository(defaults: store)
        let created = try await local.create(MPSession(code: "MIG234", kind: .friendly, host: MPIdentity(id: local.uid, name: "Me")))
        book.remember(created)
        book.migrateExplicitSaves(local)
        XCTAssertTrue(book.hasExplicitSave(created))
        XCTAssertTrue(local.hasSavedCheckpoint(created))
        book.removed(created)
        book.remember(created)
        book.migrateExplicitSaves(local)
        XCTAssertFalse(book.hasExplicitSave(created), "the migration runs once")
    }

    // ---- LocalPongRepository explicit checkpoints (83b050d) ----

    @MainActor
    func testLocalCheckpointDetectsChangesAndRestoresTheSave() async throws {
        let (store, suite) = try defaults()
        defer { store.removePersistentDomain(forName: suite) }
        let local = MPLocalRepository(defaults: store)
        let created = try await local.create(MPSession(code: "LOC234", kind: .friendly, host: MPIdentity(id: local.uid, name: "Me"), capacity: 4, tableSize: 4))
        XCTAssertTrue(local.hasUnsavedChanges(created), "never saved")
        try local.saveCheckpoint(created)
        XCTAssertFalse(local.hasUnsavedChanges(created))
        // Presence and activity are housekeeping.
        let present = local.presence(created.kind, created.code)
        let fetched = try await local.get(created.kind, created.code)
        let shown = try XCTUnwrap(fetched)
        XCTAssertFalse(shown.connections.isEmpty)
        XCTAssertFalse(local.hasUnsavedChanges(shown))
        present.close()
        let uid = local.uid
        let edited = try await local.mutate(created.kind, created.code) { try MPRules.addFriendlyHousePlayer($0, actor: uid, bot: self.bot("kyra"), seat: 3) }
        XCTAssertTrue(local.hasUnsavedChanges(edited))
        let restored = try local.restoreSavedCheckpoint(edited)
        XCTAssertEqual([uid], Array(restored.participants.keys))
        XCTAssertTrue(restored.connections.isEmpty)
        let reread = try await local.get(created.kind, created.code)
        XCTAssertEqual(restored, reread)
        XCTAssertFalse(local.hasUnsavedChanges(restored))
        local.remove(restored)
        XCTAssertFalse(local.hasSavedCheckpoint(restored), "removing a room removes its save")
    }

    // ---- Back: Save and exit / Exit without saving / Stay (83b050d, 9adf1f1) ----

    @MainActor
    func testBackAsksUntilSavedThenDiscardRestoresTheSave() async throws {
        let (store, suite) = try defaults()
        defer { store.removePersistentDomain(forName: suite) }
        let preferences = MPPreferences(store), local = MPLocalRepository(defaults: store)
        let controller = MPController(experience: .full, preferences: preferences, repository: local, onClose: { _ in })
        controller.identity = MPIdentity(id: local.uid, name: "Me", characterId: "miniko")
        await controller.create(.friendly, capacity: 4, legs: 1, winPoints: 3, target: 5, format: .roundRobin, tableSize: 4, gameMode: .winnerTakesAll, advance: 2)
        let room = try XCTUnwrap(controller.session)
        XCTAssertEqual(.lobby, controller.route)
        // Never saved: Back asks, and Stay keeps the room.
        controller.back()
        XCTAssertEqual(MPRoomExitPrompt(roomId: room.id, message: .neverSaved), controller.roomExitPrompt)
        controller.roomExitStay()
        XCTAssertNil(controller.roomExitPrompt)
        XCTAssertEqual(.lobby, controller.route)
        // Save and exit.
        controller.back()
        controller.roomExitSave()
        XCTAssertEqual(.menu, controller.route)
        XCTAssertTrue(preferences.hasExplicitSave(room))
        XCTAssertTrue(local.hasSavedCheckpoint(room))
        // An unchanged save leaves without a question.
        let saved = try await local.get(room.kind, room.code)
        controller.enter(try XCTUnwrap(saved))
        controller.back()
        XCTAssertNil(controller.roomExitPrompt)
        XCTAssertEqual(.menu, controller.route)
        // A change since the save asks again; Exit without saving restores the save.
        let again = try await local.get(room.kind, room.code)
        controller.enter(try XCTUnwrap(again))
        await controller.addFriendlyHouse(try XCTUnwrap(MPRoster.find("kyra")))
        XCTAssertEqual(2, controller.session?.participants.count)
        controller.back()
        XCTAssertEqual(MPRoomExitPrompt(roomId: room.id, message: .discardsChanges), controller.roomExitPrompt)
        controller.roomExitDiscard()
        await settle { controller.route == .menu }
        XCTAssertEqual(.menu, controller.route)
        let after = try await local.get(room.kind, room.code)
        let stored = try XCTUnwrap(after)
        XCTAssertEqual([local.uid], Array(stored.participants.keys))
        XCTAssertEqual([local.uid], preferences.explicitSave(room).map { Array($0.participants.keys) })
    }

    /// Android 1fc4bc2: "Add house player" takes the highest free seat; a new table of a remembered size is filled clockwise from
    /// the host (the first saved character in seat tableSize − 1) and waits for Start.
    @MainActor
    func testSavedFriendlyLineupFillsTheTableClockwiseAndWaitsForStart() async throws {
        let (store, suite) = try defaults()
        defer { store.removePersistentDomain(forName: suite) }
        let preferences = MPPreferences(store), local = MPLocalRepository(defaults: store)
        let controller = MPController(experience: .full, preferences: preferences, repository: local, onClose: { _ in })
        controller.identity = MPIdentity(id: local.uid, name: "Me", characterId: "miniko")
        await controller.create(.friendly, capacity: 4, legs: 1, winPoints: 3, target: 5, format: .roundRobin, tableSize: 4, gameMode: .winnerTakesAll, advance: 2)
        XCTAssertFalse(controller.reviewRestoredRoster)
        await controller.addFriendlyHouse(try XCTUnwrap(MPRoster.find("mia")))
        let first = try XCTUnwrap(controller.session)
        let mia = try XCTUnwrap(first.participants.values.first { $0.bot?.characterId == "mia" })
        XCTAssertEqual(3, first.seating()[mia.id])
        controller.saveForLater()

        preferences.setFriendlyRoster(4, "minik,unknown,flare,minik,kyra,june")
        await controller.create(.friendly, capacity: 4, legs: 1, winPoints: 3, target: 5, format: .roundRobin, tableSize: 4, gameMode: .winnerTakesAll, advance: 2)
        let s = try XCTUnwrap(controller.session)
        XCTAssertTrue(controller.reviewRestoredRoster)
        XCTAssertEqual("WAITING", s.state, "a restored lineup waits for Start")
        let seating = s.seating()
        func seat(_ character: String) -> Int? { s.participants.values.first { $0.bot?.characterId == character }.flatMap { seating[$0.id] } }
        XCTAssertEqual(3, seat("minik")); XCTAssertEqual(2, seat("flare")); XCTAssertEqual(1, seat("kyra")); XCTAssertNil(seat("june"))
        XCTAssertEqual(0, seating[local.uid])
        // The seat lobby lists the host's seat first, then clockwise.
        XCTAssertEqual([0, 3, 2, 1], (0..<4).map { MPLobbyAnchor.seat($0, tableSize: 4) })
        XCTAssertEqual([0, 2, 1], (0..<3).map { MPLobbyAnchor.seat($0, tableSize: 3) })
    }

    /// Android 1fc4bc2 CrossJourneyActivity restoreTeamRoster / rememberTeamRoster (NovemberSixRosterDeviceTest's team part).
    @MainActor
    func testTeamLineupsAreRememberedPerSize() throws {
        let (store, suite) = try defaults()
        defer { store.removePersistentDomain(forName: suite) }
        let preferences = MPPreferences(store)
        let team = CrossJourneyModel(page: .teams, players: 4, preferences: preferences, hebrew: false, audio: MPAudio(), onClose: {}, onOnlineTeams: { _ in })
        XCTAssertEqual(["miniko"] + MPRoster.all.map { $0.id }.filter { $0 != "miniko" }.prefix(3), team.ids)
        team.ids = ["miniko", "minik", "flare", "kyra"]
        team.rememberTeamRoster()
        team.twoOpponents = false
        team.ids = ["miniko", "mia", "comet", "june"]
        team.rememberTeamRoster()
        team.twoOpponents = true
        XCTAssertEqual(["minik", "flare", "kyra"], Array(team.ids.dropFirst()))
        team.twoOpponents = false
        XCTAssertEqual(["mia", "comet", "june"], Array(team.ids.dropFirst()))
        XCTAssertEqual("mia,comet,june", preferences.teamRoster(3))
        XCTAssertEqual("minik,flare,kyra", preferences.teamRoster(4))
        // The player's own character never takes another place; unknown names are skipped.
        preferences.setTeamRoster(4, "miniko,ghost,kyra")
        team.twoOpponents = true
        XCTAssertEqual(["miniko", "kyra"], Array(team.ids.prefix(2)))
        XCTAssertEqual(4, Set(team.ids).count)
    }

    // ---- Texts (3f13c40, 452d82c, 83b050d) ----

    func testLoadingAndExitTextsInEveryLanguage() {
        let loading = ["en": "Loading…", "es": "Cargando…", "ar": "جارٍ التحميل…", "hi": "लोड हो रहा है…", "nl": "Laden…"]
        for (language, text) in loading { MPText.configure(language); XCTAssertEqual(text, MPText.t("Loading…", "טוענים…", false), language) }
        let save = ["en": "Save and exit", "es": "Guardar y salir", "ar": "حفظ وخروج", "hi": "सहेजें और बाहर निकलें", "nl": "Opslaan en afsluiten"]
        for (language, text) in save { MPText.configure(language); XCTAssertEqual(text, MPText.t("Save and exit", "שמירה ויציאה", false), language) }
        // Android has no catalog rows for the rest of the question (English outside Hebrew there); iOS translates them (owner
        // decision 2026-11-10, MPTextIOS).
        for language in ["es", "ar", "hi", "nl"] {
            MPText.configure(language)
            for english in ["Are you sure you want to delete?", "Exit without saving", "Stay", "This has never been saved. Exit without saving removes it.",
                            "Exit without saving discards only your changes since the last save. Your earlier save will be kept.",
                            "Your earlier saved entry will be kept. Shared online play continues; other players' progress is not rolled back.",
                            "Two players use the classic table."] {
                XCTAssertNotEqual(english, MPText.t(english, "-", false), language)
                XCTAssertNotNil(MPTextIOS.rows.first { $0.0 == english }, english)
            }
        }
        MPText.configure("nl")
        XCTAssertEqual("Afsluiten zonder opslaan", MPText.t("Exit without saving", "יציאה ללא שמירה", false))
        XCTAssertEqual("למחוק את השינויים שלא נשמרו?", MPText.t("Are you sure you want to delete?", "למחוק את השינויים שלא נשמרו?", true))
        MPText.configure("en")
    }
}
