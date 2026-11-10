import XCTest
@testable import MinikMultiPingPong

// Multi Ping Pong iOS stage 1 (2026-11-09): what a mixed iOS/Android room depends on from Android MinikCrossPong b0cdeb3 (the
// fourth control level, Starter, wire value 1; the final duel on the cross table and its legacy upgrade), 1fc4bc2 (the final's
// two-point lead, resumable elimination checkpoints, the friendly host's watched house final) and 452d82c. Ported Kotlin tests:
// EliminationResumeTest (1fc4bc2); the others pin the Android values and texts directly.
final class MultiStageOneTests: XCTestCase {
    override func setUp() { super.setUp(); MPText.configure("en") }
    override func tearDown() { MPText.configure("en"); super.tearDown() }

    // ---- Starter: wire value, preferences, titles ----

    /// Android ControlChoice.normalize (b0cdeb3): 0 and 2 Standard, 1 Starter, 3 Pro, anything else Beginner.
    func testControlChoiceNormalizesLikeAndroid() {
        let expected: [Int: MPLevel] = [-1: .beginner, 0: .easy, 1: .medium, 2: .easy, 3: .superHard, 4: .beginner, 5: .beginner, 9: .beginner]
        for (value, level) in expected { XCTAssertEqual(level, MPLevel.control(value), "\(value)") }
        let controls: [Int: CrossControl] = [0: .standard, 1: .starter, 2: .standard, 3: .pro, 4: .beginner, 9: .beginner]
        for (value, control) in controls { XCTAssertEqual(control, CrossControl.fromChoice(value), "\(value)") }
        XCTAssertEqual([4, 1, 0, 3], MPControlChoice.values)
        XCTAssertEqual([4, 1, 0, 3], MPControlChoice.values.map { CrossControl.fromChoice($0).choice })
    }

    /// A room created with Starter on either platform keeps wire value 1, and a value 1 from an Android phone is Starter here.
    func testStarterRoomRoundTripsAsWireValueOne() throws {
        var room = MPSession(code: "STA234", kind: .friendly, host: MPIdentity(id: "host", name: "Host"), capacity: 3, legs: 1, winPoints: 3,
                             difficulty: CrossControl.starter.choice, target: 5, tableSize: 3, gameMode: .elimination)
        room.createdAt = 0
        room.lastActivityAt = 0
        XCTAssertEqual(1, room.difficulty)
        XCTAssertEqual(5, room.target)
        let wire: MPWire = try MPCodec.session(room)
        XCTAssertEqual(1, (wire["difficulty"] as? NSNumber)?.intValue)
        let decoded: MPSession = try MPCodec.session(wire)
        XCTAssertEqual(1, decoded.difficulty)
        XCTAssertEqual(CrossControl.starter, CrossControl.fromChoice(decoded.difficulty))
        // The same room as an Android phone writes it: only the number 1.
        var android: MPWire = try MPCodec.session(MPSession(code: "STA235", kind: .friendly, host: MPIdentity(id: "host", name: "Host"), capacity: 3,
                                                    legs: 1, winPoints: 3, difficulty: 0, target: 5, tableSize: 3, gameMode: .elimination))
        android["difficulty"] = 1
        let fromAndroid: MPSession = try MPCodec.session(android)
        XCTAssertEqual(CrossControl.starter, CrossControl.fromChoice(fromAndroid.difficulty))
        XCTAssertEqual(MPLevel.medium, MPLevel.control(fromAndroid.difficulty)) // a classic pair plays Android Difficulty.EASY
        XCTAssertFalse(fromAndroid.level.needsTwoPointLead)
    }

    /// Android PlayActivity.savedControlDifficulty reads `controlDifficulty` through ControlChoice.normalize: a saved 1 is Starter.
    func testSavedControlKeepsAndroidMeaning() throws {
        let suite = "multi.stage1." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = MPPreferences(defaults)
        XCTAssertEqual(MPLevel.beginner, preferences.control)
        let saved: [(Int, MPLevel)] = [(1, .medium), (2, .easy), (0, .easy), (3, .superHard), (4, .beginner), (7, .beginner)]
        for (stored, level) in saved {
            defaults.set(stored, forKey: "modern.pong.v2.control")
            XCTAssertEqual(level, preferences.control, "\(stored)")
        }
        preferences.control = .medium
        XCTAssertEqual(1, defaults.integer(forKey: "modern.pong.v2.control"))
        XCTAssertEqual(CrossControl.starter, CrossControl.fromChoice(preferences.control.rawValue))
    }

    /// Android ControlChoice.title and the Starter texts in every language (the catalog row "Starter", issue_review.xml).
    func testStarterTexts() {
        XCTAssertEqual("נינוחה", MPControlChoice.title(1, hebrew: true))
        XCTAssertEqual("Starter", MPControlChoice.title(1, hebrew: false))
        let help = "Starter: move into reach, then tap or swipe to aim. You have a longer window to return the ball."
        XCTAssertEqual(help, MPText.issue(help))
        let expected: [String: (title: String, help: String)] = [
            "es": ("Inicial", "Relajado: acércate a la pelota y toca o desliza para apuntar. Tienes más tiempo para devolverla."),
            "ar": ("مبتدئ", "مريح: اقترب من الكرة، ثم انقر أو اسحب للتصويب. لديك وقت أطول لإعادة الكرة."),
            "hi": ("शुरुआती", "आरामदायक: गेंद की पहुँच में आएँ, फिर निशाना लगाने के लिए टैप या स्वाइप करें। गेंद लौटाने के लिए ज़्यादा समय मिलता है।"),
            "nl": ("Starter", "Ontspannen: ga binnen bereik staan en tik of veeg om te richten. Je hebt langer de tijd om de bal terug te slaan."),
            "he": ("נינוחה", "נינוחה: נעים אל הכדור, ואז מקישים או מחליקים כדי לכוון. יש יותר זמן להחזיר את הכדור."),
        ]
        for (language, texts) in expected {
            MPText.configure(language)
            XCTAssertEqual(texts.title, MPControlChoice.title(1, hebrew: language == "he"), language)
            XCTAssertEqual(texts.help, MPText.issue(help), language)
        }
        // Android AppText.t keeps the caller's trailing space around a catalog row.
        MPText.configure("es")
        XCTAssertEqual("Viendo el duelo final. ", MPText.t("Watching the final duel. ", "צופים בקרב הגמר. ", false))
        XCTAssertEqual("Ver el duelo final", MPText.t("Watch final duel", "צפייה בקרב הגמר", false))
        // "Finalists: " has no catalog row: Android shows it in English; iOS translates it (owner decision 2026-11-10, MPTextIOS).
        XCTAssertEqual("Finalistas: ", MPText.t("Finalists: ", "העולים לגמר: ", false))
    }

    // ---- The final duel on the cross table ----

    /// A three-seat friendly elimination table: the host goes out first, the two house players' final waits for the host to watch.
    private func watchedFinal(difficulty: Int = 1) throws -> (MPSession, MPFixture, MPFixture) {
        var room = MPSession(code: "WAT234", kind: .friendly, host: MPIdentity(id: "host", name: "Host"), capacity: 3, legs: 1, winPoints: 3,
                             difficulty: difficulty, target: 5, tableSize: 3, gameMode: .elimination)
        for c in MPRoster.all[1..<3] {
            let bot = MPParticipant(identity: MPIdentity(id: "bot_\(c.id)_1", name: c.english), bot: c.profile)
            room = try MPRules.addFriendlyHousePlayer(room, actor: "host", bot: bot)
        }
        room.connections = ["host": ["0": true]]
        let active = try MPRules.start(room, actor: "host")
        let table = try XCTUnwrap(active.matches.values.first)
        XCTAssertEqual(3, table.players.count)
        let bots = table.players.filter { $0 != "host" }
        XCTAssertEqual(2, bots.count)
        // The host goes out first holding 3; the house players hold 5 and 4.
        let points: [String: Int] = ["host": 3, bots[0]: 5, bots[1]: 4]
        let playing = MPRules.startReady(MPRules.friendlyHouseReady(active, actor: "host"), match: table.id)
        XCTAssertEqual(MPMatchPhase.playing, playing.matches[table.id]?.phase)
        let s = try MPRules.finish(playing, match: table.id, actor: "host", scores: table.players.map { points[$0] ?? 0 },
                                   placement: [bots[0], bots[1], "host"])
        let finished = try XCTUnwrap(s.matches[table.id])
        let duel = try XCTUnwrap(MPRules.duelOf(s, finished))
        return (s, finished, duel)
    }

    func testTheEliminationFinalIsPlayedOnTheCrossTable() throws {
        let (s, table, duel) = try watchedFinal()
        XCTAssertTrue(MPRules.isDuel(duel))
        XCTAssertTrue(MPCrossFixture.usesCross(duel))
        XCTAssertEqual(CrossGoal.win, MPCrossFixture.goal(s, duel))
        XCTAssertEqual(CrossGoal.topTwo, MPCrossFixture.goal(s, table))
        XCTAssertEqual(CrossMode.elimination, MPCrossFixture.mode(s))
        // A two-player tie-break and an ordinary pair stay classic.
        var tiebreak = MPFixture(id: "T1", players: duel.players, seed: 3)
        tiebreak.goal = .tiebreak
        XCTAssertFalse(MPCrossFixture.usesCross(tiebreak))
        XCTAssertEqual(CrossGoal.tiebreak, MPCrossFixture.goal(s, tiebreak))
        XCTAssertFalse(MPCrossFixture.usesCross(MPFixture(id: "P1", players: duel.players, seed: 3)))
        // The table names its finalists until the duel decides.
        XCTAssertTrue(MPRules.needsDuel(s, table))
        XCTAssertNil(MPRules.finalWinner(s, table))
    }

    func testOnlyTheFriendlyHostWatchesAHouseFinal() throws {
        let (s, _, duel) = try watchedFinal()
        XCTAssertEqual(MPMatchPhase.waiting, duel.phase)
        XCTAssertTrue(MPRules.spectatedDuel(s, duel, uid: "host"))
        XCTAssertFalse(MPRules.spectatedDuel(s, duel, uid: duel.players[0]))
        XCTAssertFalse(MPRules.spectatedDuel(s, duel, uid: "outsider"))
        var tournament = s
        tournament.kind = .tournament
        XCTAssertFalse(MPRules.spectatedDuel(tournament, duel, uid: "host"))
        let started = MPRules.startSpectatedDuel(s, id: duel.id, actor: "host")
        XCTAssertEqual(MPMatchPhase.playing, started.matches[duel.id]?.phase)
        XCTAssertEqual(1, started.matches[duel.id]?.starts)
        XCTAssertEqual(started, MPRules.startSpectatedDuel(started, id: duel.id, actor: "host"))
        // The watched court: every seat is a house player, so this phone only watches; the host is the authority.
        XCTAssertEqual("host", started.authority(duel))
    }

    /// Android 1fc4bc2 CrossMatch.build: the final keeps the control level's two-point lead (Pro), never in a tie-break.
    func testTheCrossFinalKeepsTheTwoPointLeadOfItsControlLevel() {
        let pair = houseTable("kyra", "mia")
        for control in CrossControl.allCases {
            let duel = CrossMatch(roster: pair, control: control, target: 5, seed: 7, mode: .elimination, goal: .win)
            XCTAssertEqual(control == .pro, duel.engine.classicWinByTwo, "\(control)")
            XCTAssertEqual(control == .pro, duel.engine.referee.winByTwo, "\(control)")
            let tiebreak = CrossMatch(roster: pair, control: control, target: 1, seed: 7, mode: .elimination, goal: .tiebreak)
            XCTAssertFalse(tiebreak.engine.classicWinByTwo, "\(control)")
            let table = CrossMatch(roster: houseTable("kyra", "mia", "june"), control: control, target: 5, seed: 7, mode: .elimination, goal: .topTwo)
            XCTAssertFalse(table.engine.classicWinByTwo, "\(control)")
        }
    }

    // Kotlin EliminationResumeTest (1fc4bc2): proSpectatorDuelKeepsTwoPointLead
    func testProSpectatorDuelKeepsTwoPointLead() throws {
        let r = CrossReferee(CrossGeometry(2), target: 3, firstServer: 0, scoring: .classic, winByTwo: true)
        var state = r.exportState()
        state.scores = [2, 2]
        try r.restore(state)
        _ = r.serveFault(0)
        XCTAssertNil(r.winner)
        r.nextRally()
        _ = r.serveFault(1)
        XCTAssertNil(r.winner)
        // A score past the target is a valid two-point-lead checkpoint only there.
        var deuce = r.exportState()
        deuce.scores = [4, 4]
        XCTAssertNoThrow(try r.restore(deuce))
        let plain = CrossReferee(CrossGeometry(2), target: 3, firstServer: 0, scoring: .classic)
        XCTAssertThrowsError(try plain.restore(deuce))
    }

    // Kotlin EliminationResumeTest (1fc4bc2): everyEliminationAndFinalCheckpointCanReopen
    func testEveryEliminationAndFinalCheckpointCanReopen() throws {
        for goal in [CrossGoal.topTwo, .win] {
            let seats = houseTable("minik", "flare", "amber", "kyra")
            let m = CrossMatch(roster: seats, control: .standard, target: 3, seed: 823, mode: .elimination, goal: goal)
            var transitions = 0, previous = "", steps = 0
            while !m.finished && steps < 200_000 {
                steps += 1
                m.advance(0.025)
                m.discardEvents()
                let key = "\(m.stage)/\(m.eliminated.count)/\(m.finished)/\(m.transition != nil)"
                if key != previous {
                    previous = key
                    let restored = CrossMatch(roster: seats, control: .standard, target: 3, seed: 823, mode: .elimination, goal: goal)
                    try restored.restoreState(CrossMatchState.read(m.exportState().wire()))
                    XCTAssertEqual(m.eliminated, restored.eliminated, "\(goal) \(key)")
                    XCTAssertEqual(m.active, restored.active, "\(goal) \(key)")
                    if m.transition != nil { transitions += 1 }
                }
            }
            XCTAssertTrue(m.finished, "\(goal)")
            XCTAssertTrue(transitions > 0, "\(goal)")
            let restored = CrossMatch(roster: seats, control: .standard, target: 3, seed: 823, mode: .elimination, goal: goal)
            try restored.restoreState(CrossMatchState.read(m.exportState().wire()))
            XCTAssertEqual(m.placement, restored.placement, "\(goal)")
        }
    }

    /// Android ScoreState.read of an older classic final's checkpoint (protocol 1).
    func testLegacyClassicScoreReadsLikeAndroid() throws {
        let score = try CrossLink.legacyScore(["child": 3, "minik": 5, "rallies": 8, "server": "MINIK", "winner": "", "streak": 2])
        XCTAssertEqual(MPScore(child: 3, minik: 5, rallies: 8, server: .minik, winner: nil, streak: 2), score)
        XCTAssertEqual(MPScore(), try CrossLink.legacyScore([:]))
        XCTAssertEqual(MPSide.child, try CrossLink.legacyScore(["winner": "CHILD"]).winner)
        XCTAssertThrowsError(try CrossLink.legacyScore(["server": "LEFT"]))
    }
}
