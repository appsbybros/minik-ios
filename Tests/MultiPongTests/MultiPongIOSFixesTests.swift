import XCTest
@testable import MinikMultiPingPong

// Multi Ping Pong iOS-only fixes (owner decision, 2026-11-10): iOS deliberately differs from Android dd94c09 here.
// 1. A 2-seat friendly game never restores (or saves) a lineup, so a stale `friendlyRoster2` cannot leave it waiting for a Start
//    button that only the 3/4-seat lobby has; the restored-lineup wait belongs to the room it was restored into.
// 2. The host of a friendly table with house players and another human is never kept behind "Loading…" while the match waits for
//    the host's own Ready.
// 3. Every MultiPong text has Spanish, Arabic, Hindi and Dutch (MPTextIOS where Android falls back to English).
final class MultiPongIOSFixesTests: XCTestCase {
    override func setUp() { super.setUp(); MPText.configure("en") }
    override func tearDown() { MPText.configure("en"); super.tearDown() }

    private func defaults() throws -> (UserDefaults, String) {
        let suite = "multi.iosfixes." + UUID().uuidString
        return (try XCTUnwrap(UserDefaults(suiteName: suite)), suite)
    }
    /// Polls (up to 4 s) for asynchronous transactions and the 700 ms full-roster pause.
    @MainActor private func wait(_ done: () -> Bool) async {
        for _ in 0..<80 where !done() { try? await Task.sleep(nanoseconds: 50_000_000) }
    }
    @MainActor private func makeController(_ store: UserDefaults) -> (MPController, MPPreferences, MPLocalRepository) {
        let preferences = MPPreferences(store), local = MPLocalRepository(defaults: store)
        let controller = MPController(experience: .full, preferences: preferences, repository: local, onClose: { _ in })
        controller.identity = MPIdentity(id: local.uid, name: "Me", characterId: "miniko")
        return (controller, preferences, local)
    }

    // ---- Fix 1: the 2-seat friendly game ----

    /// A lineup saved for two seats (Android's rule saves one) is ignored and cleared: the new 2-seat table holds only its host,
    /// does not wait for a Start it cannot show, and starts as soon as a house player is chosen; its start saves no lineup.
    @MainActor
    func testTwoSeatFriendlyWithAStaleSavedLineupStartsNormally() async throws {
        let (store, suite) = try defaults()
        defer { store.removePersistentDomain(forName: suite) }
        let (controller, preferences, local) = makeController(store)
        preferences.setFriendlyRoster(2, "kyra")
        await controller.create(.friendly, capacity: 2, legs: 1, winPoints: 3, target: 5, format: .roundRobin, tableSize: 2, gameMode: .winnerTakesAll, advance: 2)
        let created = try XCTUnwrap(controller.session)
        XCTAssertEqual([local.uid], Array(created.participants.keys), "no house player is restored at a 2-seat table")
        XCTAssertEqual("WAITING", created.state)
        XCTAssertFalse(controller.reviewRestoredRoster)
        XCTAssertEqual("", preferences.friendlyRoster(2), "the stale 2-seat lineup is cleared")

        await controller.addFriendlyHouse(try XCTUnwrap(MPRoster.find("mia")))
        await wait { controller.session.map { $0.state != "WAITING" } ?? true }
        XCTAssertNotEqual("WAITING", controller.session?.state, "the 2-seat table starts with its own Start")
        XCTAssertEqual("", preferences.friendlyRoster(2), "a 2-seat start saves no lineup")
    }

    /// 3/4-seat tables keep Android's behaviour: a saved lineup fills the table and waits for Start. The wait belongs to that
    /// room, so a 2-seat table created next never waits.
    @MainActor
    func testFourSeatLineupStillWaitsForStartAndTheWaitStaysWithItsRoom() async throws {
        let (store, suite) = try defaults()
        defer { store.removePersistentDomain(forName: suite) }
        let (controller, preferences, _) = makeController(store)
        preferences.setFriendlyRoster(4, "minik,flare,kyra")
        await controller.create(.friendly, capacity: 4, legs: 1, winPoints: 3, target: 5, format: .roundRobin, tableSize: 4, gameMode: .winnerTakesAll, advance: 2)
        let restored = try XCTUnwrap(controller.session)
        XCTAssertEqual(4, restored.participants.count)
        XCTAssertEqual("WAITING", restored.state)
        XCTAssertTrue(controller.reviewRestoredRoster)
        XCTAssertEqual("minik,flare,kyra", preferences.friendlyRoster(4), "the 4-seat lineup is kept")
        controller.saveForLater()

        await controller.create(.friendly, capacity: 2, legs: 1, winPoints: 3, target: 5, format: .roundRobin, tableSize: 2, gameMode: .winnerTakesAll, advance: 2)
        XCTAssertNotEqual(restored.id, controller.session?.id)
        XCTAssertFalse(controller.reviewRestoredRoster, "another room never inherits the restored lineup's wait")
    }

    // ---- Fix 2: the host's Ready is never hidden behind "Loading…" ----

    /// `awaitsOwnReady`: a started friendly table where another human sits needs the host's own Ready; Start's house-player Ready
    /// covers a table whose only human is the host; a Ready already chosen, a waiting room or a tournament needs nothing.
    @MainActor
    func testAwaitsOwnReadyOnlyWhenTheHostMustStillChooseReady() throws {
        let (store, suite) = try defaults()
        defer { store.removePersistentDomain(forName: suite) }
        let (controller, _, local) = makeController(store)
        let uid = local.uid
        func room(guest: Bool) throws -> MPSession {
            var s = MPSession(code: "FXR234", kind: .friendly, host: MPIdentity(id: uid, name: "Host"), capacity: 3, legs: 1, winPoints: 3,
                              difficulty: 1, target: 5, tableSize: 3, gameMode: .winnerTakesAll)
            if guest { s = try MPRules.join(s, MPIdentity(id: "guest", name: "Guest", characterId: "mia")) }
            s = try MPRules.addFriendlyHousePlayer(s, actor: uid, bot: MPRules.housePlayer(try XCTUnwrap(MPRoster.find("kyra"))))
            if !guest { s = try MPRules.addFriendlyHousePlayer(s, actor: uid, bot: MPRules.housePlayer(try XCTUnwrap(MPRoster.find("flare")))) }
            XCTAssertEqual(3, s.participants.count)
            return s
        }
        let mixed = try room(guest: true)
        XCTAssertFalse(controller.awaitsOwnReady(mixed), "a waiting room")
        let started = try MPRules.start(mixed, actor: uid)
        XCTAssertEqual("ACTIVE", started.state)
        XCTAssertTrue(controller.awaitsOwnReady(started), "the host must choose Ready beside another human")
        let fixture = try XCTUnwrap(started.matches.values.first)
        let ready = try MPRules.ready(started, match: fixture.id, uid: uid, value: true)
        XCTAssertFalse(controller.awaitsOwnReady(ready), "the host's Ready is chosen")
        let houseOnly = try MPRules.start(try room(guest: false), actor: uid)
        XCTAssertFalse(controller.awaitsOwnReady(houseOnly), "Start is the host's Ready when the other players are house players")
    }

    /// The full flow: a 3-seat friendly table with a second human and a house player starts after its full-roster pause, and the
    /// host sees the room with its Ready button (no Loading page); the host's Ready then works from the room.
    @MainActor
    func testHostSeesTheRoomAndCanChooseReadyAfterAMixedTableStarts() async throws {
        let (store, suite) = try defaults()
        defer { store.removePersistentDomain(forName: suite) }
        let (controller, _, local) = makeController(store)
        await controller.create(.friendly, capacity: 3, legs: 1, winPoints: 3, target: 5, format: .roundRobin, tableSize: 3, gameMode: .winnerTakesAll, advance: 2)
        let created = try XCTUnwrap(controller.session)
        _ = try await local.mutate(created.kind, created.code) { try MPRules.join($0, MPIdentity(id: "guest", name: "Guest", characterId: "mia")) }
        await controller.addFriendlyHouse(try XCTUnwrap(MPRoster.find("kyra")))
        await wait { controller.session?.state == "ACTIVE" }
        let started = try XCTUnwrap(controller.session)
        XCTAssertEqual("ACTIVE", started.state)
        await wait { !controller.loadingMatch }
        XCTAssertFalse(controller.loadingMatch, "the Loading page never hides the host's Ready")
        XCTAssertEqual(.lobby, controller.route)
        XCTAssertTrue(controller.awaitsOwnReady(started))
        let fixture = try XCTUnwrap(started.matches.values.first { $0.contains(local.uid) })
        await controller.ready(fixture)
        let after = try XCTUnwrap(controller.session)
        XCTAssertEqual(true, after.matches[fixture.id]?.ready[local.uid], "the host's Ready reaches the room")
        XCTAssertFalse(controller.awaitsOwnReady(after))
        XCTAssertFalse(controller.loadingMatch)
    }

    // ---- Fix 3: no English fallback ----

    /// Every iOS-only row (stage 5 and 2026-11-10) shows a non-English text in every catalog language, placeholders filled.
    func testEveryIOSOnlyTextIsTranslatedInEveryLanguage() {
        for (key, values) in MPTextIOS.rows {
            XCTAssertNil(MPTextCatalog.rows.first { $0.0 == key }, "an Android row must win: \(key)")
            XCTAssertEqual(4, values.count, key)
            let english = key.replacingOccurrences(of: "{0}", with: "7")
            for (index, language) in MPText.columns.enumerated() {
                MPText.configure(language)
                let shown = MPText.t(english, "עברית", false)
                XCTAssertNotEqual(english, shown, "\(language): \(key)")
                XCTAssertEqual(values[index].replacingOccurrences(of: "{0}", with: "7"), shown, "\(language): \(key)")
            }
        }
        MPText.configure("he")
        XCTAssertEqual("להישאר", MPText.t("Stay", "להישאר", true), "Hebrew stays the call site's text")
    }

    /// The texts the stage-4 report named, the online team room, the knockout texts and the template leaks.
    @MainActor
    func testNamedScreensShowTheirTranslations() throws {
        MPText.configure("es")
        XCTAssertEqual("Salir sin guardar", MPText.t("Exit without saving", "יציאה ללא שמירה", false))
        XCTAssertEqual("Quedarse", MPText.t("Stay", "להישאר", false))
        XCTAssertEqual("Dos jugadores usan la mesa clásica.", MPText.t("Two players use the classic table.", "שני שחקנים משחקים בשולחן הקלאסי.", false))
        XCTAssertEqual("Ver a todos los jugadores", MPText.t("Fit all players", "כל השחקנים במסך", false), "not the {0} players template")
        XCTAssertEqual("Jugando ahora", MPText.t("Playing now", "משחקים עכשיו", false), "not the Playing {0} template")
        XCTAssertEqual("Minik y Kyra", ["Minik", "Kyra"].joined(separator: MPText.t(" and ", " ו־", false)))
        let (store, suite) = try defaults()
        defer { store.removePersistentDomain(forName: suite) }
        let teams = CrossTeamsModel(players: 4, preferences: MPPreferences(store), hebrew: false, audio: MPAudio(), onClose: {})
        XCTAssertEqual("Toca para elegir", teams.tr("Tap to choose", "הקישו לבחירה"))
        XCTAssertEqual("Partido por equipos", teams.tr("Team match", "משחק קבוצתי"), "an Android catalog row now reaches the team room too")
        XCTAssertEqual("Elige un jugador", MPText.t("Choose a player", "בחירת שחקן", false))
        MPText.configure("nl")
        XCTAssertEqual("Kamercode: ", teams.tr("Room code: ", "קוד החדר: "))
        XCTAssertTrue(teams.tr("Join my Multiplayer Ping Pong team table! Open the app, choose Online team game, then enter room code: AB2CD3", "-")
            .hasSuffix("voer de kamercode in: AB2CD3"))
        MPText.configure("ar")
        XCTAssertEqual("البقاء", MPText.t("Stay", "להישאר", false))
        XCTAssertEqual("مينيك وكيرا", ["مينيك", "كيرا"].joined(separator: MPText.t(" and ", " ו־", false)))
        MPText.configure("hi")
        XCTAssertEqual("आप फ़ाइनल में पहुँच गए!", MPText.t("You reached the final!", "העפלת לגמר!", false))
        MPText.configure("he")
        XCTAssertEqual("הקישו לבחירה", CrossTeamsModel(players: 4, preferences: MPPreferences(store), hebrew: true, audio: MPAudio(), onClose: {})
            .tr("Tap to choose", "הקישו לבחירה"))
    }
}
