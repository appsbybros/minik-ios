import Foundation
import XCTest
@testable import MinikTripleShot

// Parity tests for the t-modes area (spec 03-modes): the HORSE engine (local and Live rules), the bot
// opponent, the house league and its store, and the daily court journey.
// Part 1 ports the Android unit tests HorseGameEngineTest, TripleShotLeagueTest and BasketballJourneyTest
// with their exact assertions. Part 2 replays golden vectors printed by the real Kotlin classes on the JVM
// (scratch harness over Android snapshot dd722e5, Android's own org.json for the store format): exact Float
// bit patterns, random draw order, house results, standings, store JSON and journey picks.
// The league preferences of the test host are saved in setUp and restored in tearDown.

final class ModesTests: XCTestCase {

    private static let leaguePrefs = "tripleshot_house_league"
    private var savedLeague: String? = nil
    private var hadLeague = false

    override func setUp() {
        super.setUp()
        let prefs = getSharedPreferences(ModesTests.leaguePrefs, MODE_PRIVATE)
        hadLeague = prefs.contains("active")
        savedLeague = prefs.getString("active", nil)
        prefs.edit().remove("active").commit()
    }

    override func tearDown() {
        let prefs = getSharedPreferences(ModesTests.leaguePrefs, MODE_PRIVATE)
        if hadLeague {
            prefs.edit().putString("active", savedLeague).commit()
        } else {
            prefs.edit().remove("active").commit()
        }
        super.tearDown()
    }

    private func putLeague(_ json: String) {
        getSharedPreferences(ModesTests.leaguePrefs, MODE_PRIVATE).edit().putString("active", json).commit()
    }

    private func storedLeague() -> String? {
        return getSharedPreferences(ModesTests.leaguePrefs, MODE_PRIVATE).getString("active", nil)
    }

    /// `(inside + midRange + defense + speed) / 4` per character, averaged in Double, truncated (store `strength`).
    private static func strength(_ ids: [String]) -> Int {
        let values = ids.map { id -> Int in
            let r = TripleShotCharacterRoster.all.first { $0.id == id }!.ratings
            return (r.inside + r.midRange + r.defense + r.speed) / 4
        }
        return Int(Double(values.reduce(0, +)) / Double(values.count))
    }

    private static let houseNames = ["Golden Bolts", "Moon Dragons", "Tidal Waves", "Fire Stars", "Night Wolves", "Rainbow Wings", "Sun Lions"]

    // MARK: - HorseGameEngineTest.kt

    private let topic = QuestionCategory.KIDS_ARITHMETIC

    func testSetterFailureDoesNotPunishAndChangesTurn() throws {
        for correct in [false, true] {
            let e = HorseGameEngine()
            try e.configureChallenge(player: .HUMAN, category: topic, spotId: "S1")
            let r = e.resolveAttempt(player: .HUMAN, answerCorrect: correct, made: false)
            XCTAssertFalse(r.penaltyAdded)
            XCTAssertEqual(HorseGameEngine.Player.BOT, r.state.setter)
            XCTAssertNil(r.state.challenge)
        }
    }

    func testObligatedWrongAnswerCountsEvenWhenBasketGoesIn() throws {
        let e = HorseGameEngine()
        try e.configureChallenge(player: .HUMAN, category: topic, spotId: "S1")
        _ = e.resolveAttempt(player: .HUMAN, answerCorrect: true, made: true)
        let r = e.resolveAttempt(player: .BOT, answerCorrect: false, made: true)
        XCTAssertEqual(1, r.state.botPenalties)
        XCTAssertNotNil(r.state.challenge)
        XCTAssertEqual(HorseGameEngine.Player.HUMAN, r.state.currentPlayer)
    }

    func testCorrectMissEndsChallengeWithoutPenalty() throws {
        let e = HorseGameEngine()
        try e.configureChallenge(player: .HUMAN, category: topic, spotId: "S1")
        _ = e.resolveAttempt(player: .HUMAN, answerCorrect: true, made: true)
        let r = e.resolveAttempt(player: .BOT, answerCorrect: true, made: false)
        XCTAssertFalse(r.penaltyAdded)
        XCTAssertNil(r.state.challenge)
    }

    func testLiveCustomPenaltyLimitSkipsEliminatedPlayer() throws {
        let m = HorseGameEngine.Multiplayer.self
        var s = m.initialState(playerOrder: ["a", "b", "c"], firstSetterUid: "a")
        s = try m.configureChallenge(state: s, actorUid: "a", category: topic, spotId: "S1", spotX: 10, spotY: 20)
        s = try m.resolveAttempt(state: s, actorUid: "a", answerCorrect: true, made: true, maxPenalties: 1).state
        let r = try m.resolveAttempt(state: s, actorUid: "b", answerCorrect: false, made: true, maxPenalties: 1)
        XCTAssertEqual("b", r.eliminatedUid)
        XCTAssertEqual("c", r.state.currentPlayerUid)
        XCTAssertEqual("a", try m.resolveAttempt(state: r.state, actorUid: "c", answerCorrect: false, made: true, maxPenalties: 1).state.winnerUid)
    }

    /// Android: `@Test(expected = IllegalArgumentException::class)`.
    func testLiveRejectsOutOfTurnResolution() throws {
        let m = HorseGameEngine.Multiplayer.self
        let s = try m.configureChallenge(
            state: m.initialState(playerOrder: ["a", "b"], firstSetterUid: "a"),
            actorUid: "a", category: topic, spotId: "S1", spotX: 1, spotY: 2
        )
        XCTAssertThrowsError(try m.resolveAttempt(state: s, actorUid: "b", answerCorrect: true, made: true)) { error in
            XCTAssertEqual(error as? HorseGameEngine.RuleError, HorseGameEngine.RuleError.illegalArgument("Not this player's turn"))
        }
    }

    // MARK: - TripleShotLeagueTest.kt

    private func season() throws -> TripleShotLeague.Season {
        return try TripleShotLeague.Season(
            id: "s1", seed: 42, number: 1, createdAt: 1000,
            teams: (0...7).map {
                TripleShotLeague.Team(id: $0, name: "Team \($0)", color: TripleShotLeague.palette[$0 % 6], roster: ["a", "b"], strength: 50 + $0)
            }
        )
    }

    func testEveryPairMeetsHomeAndAwayAndNoTeamDoubleBooked() {
        let schedule = TripleShotLeague.schedule()
        XCTAssertEqual(56, schedule.count)
        for round in Set(schedule.map { $0.round }) {
            let teams = schedule.filter { $0.round == round }.flatMap { [$0.home, $0.away] }.sorted()
            XCTAssertEqual(Array(0...7), teams, "round \(round)")
        }
        for a in 0...7 {
            for b in 0...7 where a != b {
                XCTAssertEqual(1, schedule.filter { $0.home == a && $0.away == b }.count, "\(a) v \(b)")
            }
        }
    }

    /// `assertSame` in Kotlin: seasons are Swift values, so "returned unchanged" is checked as equality.
    func testOnlyNextFinishedFixtureCountsAndDuplicateCannotAwardAgain() throws {
        let s = try season()
        XCTAssertEqual(s, try TripleShotLeague.complete(season: s, fixtureKey: "unknown", ownScore: 11, rivalScore: 3))
        let key = s.next()!.key
        let finished = try TripleShotLeague.complete(season: s, fixtureKey: key, ownScore: 11, rivalScore: 3)
        XCTAssertEqual(1, finished.played)
        XCTAssertEqual(4, finished.results.count)
        XCTAssertEqual(finished, try TripleShotLeague.complete(season: finished, fixtureKey: key, ownScore: 11, rivalScore: 0))
        XCTAssertEqual(3, TripleShotLeague.standings(season: finished).first { $0.team.id == 0 }!.points)
    }

    func testCompleteSeasonHasBalancedTableAndDeterministicHouseResults() throws {
        var s = try season()
        var other = try season()
        for i in 0..<14 {
            s = try TripleShotLeague.complete(season: s, fixtureKey: s.next()!.key, ownScore: i % 2 == 0 ? 11 : 6, rivalScore: i % 2 == 0 ? 6 : 11)
            other = try TripleShotLeague.complete(season: other, fixtureKey: other.next()!.key, ownScore: i % 2 == 0 ? 11 : 6, rivalScore: i % 2 == 0 ? 6 : 11)
        }
        XCTAssertEqual(s, other)
        XCTAssertTrue(s.finished)
        XCTAssertNil(s.next())
        XCTAssertEqual(56, s.results.count)
        let rows = TripleShotLeague.standings(season: s)
        XCTAssertTrue(rows.allSatisfy { $0.played == 14 })
        XCTAssertEqual(56, rows.reduce(0) { $0 + $1.wins })
        XCTAssertEqual(rows.reduce(0) { $0 + $1.scored }, rows.reduce(0) { $0 + $1.conceded })
        XCTAssertEqual(7, rows.first { $0.team.id == 0 }!.wins)
    }

    /// Android: `@Test(expected = IllegalArgumentException::class)`.
    func testUnfinishedScoreIsRejected() throws {
        let s = try season()
        XCTAssertThrowsError(try TripleShotLeague.complete(season: s, fixtureKey: s.next()!.key, ownScore: 4, rivalScore: 3)) { error in
            XCTAssertEqual(error as? TripleShotLeague.RuleError, TripleShotLeague.RuleError.illegalArgument("Failed requirement."))
        }
    }

    func testNamesRetainHebrewButRejectDirectionalSpoofingAndLineBreaks() {
        let hebrew = "\u{05DE}\u{05D9}\u{05E0}\u{05D9}\u{05E7}"
        XCTAssertEqual(hebrew, TripleShotLeague.cleanName(raw: "  " + hebrew + "\u{0A}\u{202E}  "))
        XCTAssertEqual(24, TripleShotLeague.cleanName(raw: String(repeating: "a", count: 50)).utf16.count)
    }

    func testTimedSeasonAcceptsBelowElevenAndContinuesToRejectTies() throws {
        let s = try season().copy(matchSeconds: 120)
        XCTAssertEqual(1, try TripleShotLeague.complete(season: s, fixtureKey: s.next()!.key, ownScore: 6, rivalScore: 4).played)
        XCTAssertThrowsError(try TripleShotLeague.complete(season: s, fixtureKey: s.next()!.key, ownScore: 4, rivalScore: 4)) { error in
            XCTAssertEqual(error as? TripleShotLeague.RuleError, TripleShotLeague.RuleError.illegalArgument("Failed requirement."))
        }
    }

    func testEnoughPlayersNeverProducesDuplicateTeams() throws {
        let ids = (0...8).map { String($0) }
        for size in 2...3 {
            for seed in Int64(1)...Int64(50) {
                let squads = try TripleShotLeague.houseRosters(available: ids, size: size, count: 7, seed: seed)
                XCTAssertEqual(7, Set(squads.map { Set($0) }).count)
                XCTAssertTrue(squads.allSatisfy { Set($0).count == size })
                XCTAssertEqual(squads, try TripleShotLeague.houseRosters(available: ids, size: size, count: 7, seed: seed))
            }
        }
    }

    func testSmallPoolExhaustsCombinationsBeforeReusingTeams() throws {
        let squads = try TripleShotLeague.houseRosters(available: ["a", "b", "c"], size: 2, count: 7, seed: 42)
        XCTAssertEqual(3, Set(squads.prefix(3).map { Set($0) }).count)
        let counts = Dictionary(grouping: squads, by: { Set($0) }).values.map { $0.count }
        XCTAssertTrue(counts.max()! - counts.min()! <= 1)
    }

    // MARK: - BasketballJourneyTest.kt

    func testOnlyTheRequestedActionAdvancesAndFutureActionsAreNotBanked() {
        let p = BasketballPractice(step: 8)
        XCTAssertFalse(p.event(skill: .PASS, amount: 10.0))
        XCTAssertEqual(0, p.index)
        p.event(skill: .MOVE, amount: 10.0)
        XCTAssertEqual(1, p.index)
        XCTAssertEqual(0.0, p.progress(i: 1), accuracy: 0.0)
        p.event(skill: .PASS)
        p.event(skill: .PASS)
        XCTAssertFalse(p.won)
        p.event(skill: .PASS)
        XCTAssertTrue(p.won)
        let final = p.snapshot()
        XCTAssertFalse(p.event(skill: .PASS))
        XCTAssertEqual(final, p.snapshot())
    }

    func testAllStagesCanCompleteAndRestoreWithoutLosingPartialProgress() {
        for cycle in [0, 4] {
            for i in BasketballJourney.stages.indices {
                let p = BasketballPractice(step: cycle * BasketballJourney.stages.count + i)
                p.event(skill: p.active!, amount: 0.5)
                let copy = BasketballPractice(step: p.step, restored: p.snapshot())
                XCTAssertEqual(p.snapshot(), copy.snapshot())
                while !copy.won { copy.event(skill: copy.active!, amount: 1.0) }
                XCTAssertTrue(copy.won)
                XCTAssertEqual(copy.snapshot(), BasketballPractice(step: copy.step, restored: copy.snapshot()).snapshot())
            }
        }
    }

    func testPracticeRejectsInvalidProgressAndRanksBotsForThisSkill() {
        XCTAssertEqual(BasketballJourney.stages.count, Set(BasketballJourney.stages.map { $0.id }).count)
        let practised = Set(BasketballJourney.stages.flatMap { $0.goals }.map { $0.skill })
        XCTAssertTrue(practised.isSuperset(of: BasketballSkill.allCases))
        let p = BasketballPractice(step: 0)
        for v in [Double.nan, Double.infinity, -2.0, 0.0] { XCTAssertFalse(p.event(skill: .MOVE, amount: v)) }
        XCTAssertEqual(0.0, p.progress(i: 0), accuracy: 0.0)
        for s in BasketballJourney.stages {
            let a = s.bot(cycle: 0, excluded: ["woman_dark"], helper: true)
            let b = s.bot(cycle: 4, excluded: ["woman_dark"], helper: true)
            XCTAssertTrue(s.quality(r: a.ratings) >= s.quality(r: b.ratings), s.id)
            let x = s.bot(cycle: 0, excluded: ["woman_dark"], helper: false)
            let y = s.bot(cycle: 4, excluded: ["woman_dark"], helper: false)
            XCTAssertTrue(s.quality(r: x.ratings, helper: false) <= s.quality(r: y.ratings, helper: false), s.id)
        }
    }

    // MARK: - Spec 03-modes constants (section 9.5)

    func testSpecConstants() {
        XCTAssertEqual("0-0-7".javaHashCode, 45717181)
        XCTAssertEqual("7-7-0".javaHashCode, 52188548)
        // BOB never observes a shot in production: (0.55f - 0.30f) / (0.88f - 0.30f) = 0.4310345f.
        let level: Float = (Float(0.55) - Float(0.30)) / (Float(0.88) - Float(0.30))
        XCTAssertEqual(level.bitPattern, 0x3EDC_B08E)
        XCTAssertEqual(TripleShotLeague.palette, [-8988417, -18567, -3759873, -8330051, -26691, -666001])
        XCTAssertEqual(BasketballJourney.stages.count, 23)   // 6c38131 appends cross, behind_back and spin
        XCTAssertEqual(BasketballJourney.stage(step: 20).id, "cross")
        XCTAssertEqual(BasketballJourney.stage(step: 23).id, "move")
        XCTAssertEqual(BasketballJourney.stage(step: -1).id, "spin")
    }

    // MARK: - HORSE errors (the Kotlin messages; only the paths Android catches throw in Swift)

    func testHorseConfigureErrorsMatchKotlin() throws {
        func expectState(_ message: String, _ block: () throws -> Void) {
            XCTAssertThrowsError(try block()) { error in
                XCTAssertEqual(error as? HorseGameEngine.RuleError, HorseGameEngine.RuleError.illegalState(message))
            }
        }
        let e = HorseGameEngine()
        expectState("Only the current setter can configure a challenge") { try e.configureChallenge(player: .BOT, category: .AI, spotId: "S") }
        try e.configureChallenge(player: .HUMAN, category: .AI, spotId: "S")
        expectState("A challenge is already active") { try e.configureChallenge(player: .HUMAN, category: .AI, spotId: "S2") }
        let over = HorseGameEngine(maxPenalties: 1)
        try over.configureChallenge(player: .HUMAN, category: .AI, spotId: "S")
        _ = over.resolveAttempt(player: .HUMAN, answerCorrect: true, made: true)
        let end = over.resolveAttempt(player: .BOT, answerCorrect: false, made: true)
        XCTAssertEqual(HorseGameEngine.ResultType.GAME_OVER, end.type)
        XCTAssertTrue(end.penaltyAdded)
        XCTAssertEqual(HorseGameEngine.Player.HUMAN, end.state.winner)
        XCTAssertNotNil(end.state.challenge, "GAME_OVER keeps the challenge")
        XCTAssertEqual(1, end.state.penaltiesFor(player: .BOT))
        XCTAssertEqual(0, end.state.penaltiesFor(.HUMAN))
        expectState("HORSE match already finished") { try over.configureChallenge(player: .BOT, category: .AI, spotId: "S") }
    }

    /// The positional (Kotlin call-site) overloads resolve without ambiguity and delegate to the labelled API.
    func testPositionalForms() throws {
        let e = HorseGameEngine(firstSetter: .HUMAN)
        try e.configureChallenge(.HUMAN, .AI, "S")
        XCTAssertEqual(HorseGameEngine.ResultType.CHALLENGE_ESTABLISHED, e.resolveAttempt(.HUMAN, true, true).type)
        let m = HorseGameEngine.Multiplayer.self
        let live = try m.configureChallenge(m.initialState(["a", "b"], "a"), "a", .AI, "S", 1, 2)
        XCTAssertTrue(try m.resolveAttempt(live, "a", true, true).state.challengeEstablished)
        XCTAssertTrue(try m.resolveAttempt(live, "a", false, true, 1).challengeEnded)
        let bot = TripleShotBotOpponent("BOB", 1) { _ in }
        let q = TripleShotQuestion(id: "q", category: .AI, prompt: "", answers: [AnswerOption(text: "", qualityPercent: 100)], explanation: "")
        XCTAssertEqual(TripleShotBotOpponent.AnswerPlan(0, 100), bot.chooseAnswer(q))
        XCTAssertEqual(100, bot.prepareTurn(q).answerQualityPercent)
        XCTAssertEqual(100, bot.prepareTurn(q, .INSIDE).answerQualityPercent)
        XCTAssertEqual(0, bot.prepareTurn(q, .INSIDE, TripleShotBotOpponent.AnswerPlan(0, 100)).selectedAnswerIndex)
        let skill = ShotSkill(aimError: 0, powerError: 0, arcError: 0, rawPeakGyro: 0, rawReleasePitchDeg: 0)
        bot.start()
        bot.recordShot(TripleShotBotOpponent.TurnPlan(0, 100, skill, 0.7), true)
        XCTAssertEqual(9, bot.snapshot().score, "3 x multiplier 2 for the answer + 3 for the basket")
        bot.observeHumanShot(true)
        XCTAssertEqual("A", TripleShotLeague.cleanName(" A "))
        let fixture = TripleShotLeague.Fixture(0, 0, 7)
        XCTAssertEqual("0-0-7", fixture.key)
        let teams = (0...7).map { TripleShotLeague.Team($0, "T", TripleShotLeague.palette[0], ["a", "b"], 50) }
        let season = try TripleShotLeague.Season("s", 1, 1, 1, teams)
        let done = try TripleShotLeague.complete(season, "0-0-7", 11, 2)
        XCTAssertEqual(try TripleShotLeague.Result(fixture, 11, 2), done.results[0])
        XCTAssertEqual(8, TripleShotLeague.standings(done).count)
        XCTAssertEqual(7, try TripleShotLeague.houseRosters(["a", "b", "c"], 2, 7, 1).count)
        XCTAssertEqual(0, TripleShotLeague.Row(teams[0], 0, 0, 0, 0).points)
        let p = BasketballPractice(0)
        XCTAssertTrue(p.event(.MOVE, 8.0))
        XCTAssertEqual(8, p.goal(0))
        XCTAssertEqual(8.0, p.progress(0), accuracy: 0.0)
        let stage = BasketballJourney.stage(0)
        XCTAssertEqual("move", stage.id)
        XCTAssertEqual(stage.quality(TripleShotCharacterRoster.bob.ratings), stage.quality(r: TripleShotCharacterRoster.bob.ratings))
        XCTAssertEqual("rooza", stage.bot(0, ["woman_dark"], true).id)
        XCTAssertEqual(BasketballGoal(.MOVE, 8), stage.goals[0])
        let store = TripleShotLeagueStore(nil)
        XCTAssertNil(try store.complete("x", "0-0-7", 11, 0))
        store.discard("x")
    }

    func testLiveRuleErrorsMatchKotlin() throws {
        let m = HorseGameEngine.Multiplayer.self
        func expectArgument(_ message: String, _ block: () throws -> Void) {
            XCTAssertThrowsError(try block()) { error in
                XCTAssertEqual(error as? HorseGameEngine.RuleError, HorseGameEngine.RuleError.illegalArgument(message))
            }
        }
        let s0 = m.initialState(playerOrder: ["a", "b", "c"], firstSetterUid: "a")
        expectArgument("Only the current setter can configure a challenge") {
            _ = try m.configureChallenge(state: s0, actorUid: "b", category: .AI, spotId: "S", spotX: 1, spotY: 2)
        }
        let s1 = try m.configureChallenge(state: s0, actorUid: "a", category: .AI, spotId: "S", spotX: 1, spotY: 2)
        expectArgument("Not in setting phase") {
            _ = try m.configureChallenge(state: s1, actorUid: "a", category: .AI, spotId: "S", spotX: 1, spotY: 2)
        }
        var won = s0
        won.winnerUid = "a"
        expectArgument("Live HORSE already finished") {
            _ = try m.configureChallenge(state: won, actorUid: "a", category: .AI, spotId: "S", spotX: 1, spotY: 2)
        }
        var finishedPhase = s0
        finishedPhase.phase = LiveHorseState.PHASE_FINISHED
        expectArgument("Live HORSE already finished") {
            _ = try m.configureChallenge(state: finishedPhase, actorUid: "a", category: .AI, spotId: "S", spotX: 1, spotY: 2)
        }
        var blankWinner = s0
        blankWinner.winnerUid = " "
        XCTAssertNoThrow(try m.configureChallenge(state: blankWinner, actorUid: "a", category: .AI, spotId: "S", spotX: 1, spotY: 2), "a blank winner is not finished")
        expectArgument("No active attempt") { _ = try m.resolveAttempt(state: s0, actorUid: "a", answerCorrect: true, made: true) }
        expectArgument("Not this player's turn") { _ = try m.resolveAttempt(state: s1, actorUid: "b", answerCorrect: true, made: true) }
        expectArgument("Failed requirement.") { _ = try m.resolveAttempt(state: s1, actorUid: "a", answerCorrect: true, made: true, maxPenalties: 0) }
        var spectator = s1
        spectator.spectatorSlots["a"] = 0
        expectArgument("Spectators cannot shoot") { _ = try m.resolveAttempt(state: spectator, actorUid: "a", answerCorrect: true, made: true) }
        var penalised = s1
        penalised.penalties["a"] = 5
        expectArgument("Spectators cannot shoot") { _ = try m.resolveAttempt(state: penalised, actorUid: "a", answerCorrect: true, made: true) }
        var decided = s1
        decided.winnerUid = "b"
        expectArgument("Live HORSE already finished") { _ = try m.resolveAttempt(state: decided, actorUid: "a", answerCorrect: true, made: true) }
    }

    // MARK: - League store (TripleShotLeagueStore.kt; also the store assertions of LeagueDeviceTest)

    func testStoreCreateLoadCompleteDiscard() throws {
        let store = TripleShotLeagueStore()
        XCTAssertNil(try store.load())
        let roster = ["woman_dark", "rooza"]
        let s = try store.create(name: "  Sky Comets ", color: TripleShotLeague.palette[1], roster: roster, houseNames: ModesTests.houseNames)
        XCTAssertEqual(s, try store.load())
        XCTAssertEqual(s.id, s.id.lowercased())
        XCTAssertNotNil(UUID(uuidString: s.id))
        XCTAssertEqual(s.seed, s.createdAt)
        XCTAssertEqual(1, s.number)
        XCTAssertEqual(0, s.matchSeconds)
        XCTAssertTrue(s.results.isEmpty)
        XCTAssertEqual(0, s.played)
        XCTAssertEqual(TripleShotLeague.Team(id: 0, name: "Sky Comets", color: TripleShotLeague.palette[1], roster: roster, strength: 78), s.teams[0])
        let choices = TripleShotCharacterRoster.botSelectable().filter { !roster.contains($0.id) && !$0.adaptiveBot }.map { $0.id }
        XCTAssertFalse(choices.contains("bob"))
        let squads = try TripleShotLeague.houseRosters(available: choices, size: 2, count: 7, seed: s.seed)
        let colors = TripleShotLeague.palette.filter { $0 != TripleShotLeague.palette[1] }
        for i in 0..<7 {
            let t = s.teams[i + 1]
            XCTAssertEqual(i + 1, t.id)
            XCTAssertEqual(ModesTests.houseNames[i], t.name)
            XCTAssertEqual(colors[i % 5], t.color)
            XCTAssertEqual(squads[i], t.roster)
            XCTAssertEqual(ModesTests.strength(t.roster), t.strength)
        }
        XCTAssertThrowsError(try store.create(name: "X", color: TripleShotLeague.palette[0], roster: roster, houseNames: ModesTests.houseNames), "unfinished season")
        XCTAssertEqual(s, try store.complete(seasonId: "other", fixtureKey: s.next()!.key, own: 11, rival: 0))
        let before = storedLeague()
        XCTAssertEqual(s, try store.complete(seasonId: s.id, fixtureKey: "0-6-1", own: 11, rival: 0), "not the player's next fixture")
        XCTAssertEqual(before, storedLeague())
        let first = try store.complete(seasonId: s.id, fixtureKey: s.next()!.key, own: 11, rival: 0)!
        XCTAssertEqual(1, first.played)
        XCTAssertEqual(4, first.results.count)
        XCTAssertEqual(first, try store.load())
        XCTAssertEqual(first, try store.complete(seasonId: first.id, fixtureKey: s.next()!.key, own: 11, rival: 0), "re-persisting is idempotent")
        store.discard(id: "other")
        XCTAssertNotNil(try store.load())
        store.discard(id: s.id)
        XCTAssertNil(try store.load())
        XCTAssertNil(storedLeague())
        XCTAssertNil(try TripleShotLeagueStore().complete(seasonId: "x", fixtureKey: "0-0-7", own: 11, rival: 0))
    }

    func testStoreSeasonNumberContinuesAfterAFinishedSeason() throws {
        let store = TripleShotLeagueStore()
        var s = try store.create(name: "A", color: TripleShotLeague.palette[0], roster: ["woman_dark", "rooza", "nova"], houseNames: ModesTests.houseNames, matchSeconds: 300)
        XCTAssertEqual(300, s.matchSeconds)
        XCTAssertTrue(s.teams.allSatisfy { $0.roster.count == 3 })
        while !s.finished {
            s = try store.complete(seasonId: s.id, fixtureKey: s.next()!.key, own: 3, rival: 1)!
        }
        XCTAssertEqual(56, s.results.count)
        let next = try store.create(name: "B", color: TripleShotLeague.palette[2], roster: ["kyra_original", "buddy_23"], houseNames: ModesTests.houseNames)
        XCTAssertEqual(2, next.number)
        store.discard(id: next.id)
        XCTAssertEqual(1, try store.create(name: "C", color: TripleShotLeague.palette[3], roster: ["woman_dark", "rooza"], houseNames: ModesTests.houseNames).number)
    }

    func testStoreKeepsUnreadableLeagueData() {
        let store = TripleShotLeagueStore()
        let corrupt = [
            #"{"version":2}"#,
            #"{not json"#,
            #"{"version":1,"id":"x"}"#,
            #"{"version":"1","id":"x","seed":1,"number":1,"created":1,"teams":[],"results":[]}"#
        ]
        for json in corrupt {
            putLeague(json)
            XCTAssertThrowsError(try store.load(), json)
            XCTAssertThrowsError(try store.create(name: "A", color: TripleShotLeague.palette[0], roster: ["woman_dark", "rooza"], houseNames: ModesTests.houseNames), json)
            XCTAssertEqual(json, storedLeague(), "unreadable data is kept")
        }
    }

    func testStoreCreateRejectsInvalidTeams() {
        let store = TripleShotLeagueStore()
        let p0 = TripleShotLeague.palette[0]
        let names = ModesTests.houseNames
        let cases: [(name: String, color: Int, roster: [String], houses: [String], seconds: Int)] = [
            (" \u{202E} ", p0, ["woman_dark", "rooza"], names, 0),
            ("A", 0, ["woman_dark", "rooza"], names, 0),
            ("A", p0, ["woman_dark"], names, 0),
            ("A", p0, ["rooza", "rooza"], names, 0),
            ("A", p0, ["woman_dark", "rooza"], Array(names.prefix(6)), 0),
            ("A", p0, ["woman_dark", "nobody"], names, 0),
            ("A", p0, ["woman_dark", "rooza"], names, 60)
        ]
        for c in cases {
            XCTAssertThrowsError(try store.create(name: c.name, color: c.color, roster: c.roster, houseNames: c.houses, matchSeconds: c.seconds), "\(c)")
            XCTAssertNil(storedLeague(), "\(c)")
        }
    }

    // MARK: - Golden vectors (JVM): KotlinRandom and the bot opponent

    func testGoldenKotlinRandomNextFloat() {
        let rows = ModesGolden.rows("RNG_FLOAT")
        XCTAssertEqual(5, rows.count)
        for f in rows {
            let r = KotlinRandom(seed: Int64(f[1])!)
            XCTAssertEqual((0..<8).map { _ in ModesGolden.bits(r.nextFloat()) }.joined(separator: ","), f[2], "Random(\(f[1])).nextFloat()")
        }
    }

    func testGoldenBotOpponentDecisions() {
        var questions: [String: TripleShotQuestion] = [:]
        for f in ModesGolden.rows("BOTQ") {
            let answers: [AnswerOption] = f[3].isEmpty ? [] : f[3].split(separator: ",").map { part in
                let kv = part.split(separator: "=", omittingEmptySubsequences: false)
                return AnswerOption(text: ModesGolden.unescape(String(kv[0])), qualityPercent: Int(kv[1])!)
            }
            questions[f[1]] = TripleShotQuestion(id: f[1], category: QuestionCategory.named(f[2])!, prompt: "", answers: answers, explanation: "")
        }
        XCTAssertEqual(12, questions.count)
        var runs: [(profile: String, seed: String, ops: [[String]])] = []
        for f in ModesGolden.rows("BOT") {
            if let last = runs.last, last.profile == f[1], last.seed == f[2] {
                runs[runs.count - 1].ops.append(f)
            } else {
                runs.append((profile: f[1], seed: f[2], ops: [f]))
            }
        }
        XCTAssertEqual(3, runs.count)
        for run in runs {
            let profile = TripleShotCharacterRoster.all.first { $0.id == run.profile }!
            var events: [String] = []
            let bot = TripleShotBotOpponent(displayName: profile.displayName, seed: Int64(run.seed)!, characterProfile: profile) { state in
                events.append(ModesGolden.state(state))
            }
            for f in run.ops {
                let op = f[3].split(separator: ":", omittingEmptySubsequences: false).map(String.init)
                let expected = f[4]
                let context = "\(run.profile) seed \(run.seed) \(f[3])"
                switch op[0] {
                case "snapshot":
                    XCTAssertEqual(ModesGolden.state(bot.snapshot()), expected, context)
                case "start":
                    bot.start()
                    XCTAssertEqual("\(events.count);\(events.last ?? "")", expected, context)
                case "observe":
                    bot.observeHumanShot(made: op[1] == "true")
                case "choose":
                    let plan = bot.chooseAnswer(question: questions[op[1]]!)
                    XCTAssertEqual("\(plan.selectedAnswerIndex),\(plan.answerQualityPercent)", expected, context)
                case "prepare":
                    let question = questions[op[1]]!
                    var plan: TripleShotBotOpponent.AnswerPlan? = nil
                    if op[3] != "-" {
                        let p = op[3].split(separator: ",")
                        plan = TripleShotBotOpponent.AnswerPlan(selectedAnswerIndex: Int(p[0])!, answerQualityPercent: Int(p[1])!)
                    }
                    let turn: TripleShotBotOpponent.TurnPlan
                    if op[2] == "-" {
                        turn = bot.prepareTurn(question: question, answerPlan: plan)
                    } else {
                        turn = bot.prepareTurn(question: question, shotZone: ShotZone.named(op[2])!, answerPlan: plan)
                    }
                    XCTAssertEqual(ModesGolden.turn(turn), expected, context)
                case "record":
                    let skill = ShotSkill(aimError: 0, powerError: 0, arcError: 0, rawPeakGyro: 0, rawReleasePitchDeg: 0)
                    let turn = TripleShotBotOpponent.TurnPlan(selectedAnswerIndex: 0, answerQualityPercent: Int(op[1])!, skill: skill, pullBack: 0.7)
                    bot.recordShot(turn: turn, made: op[2] == "true")
                    XCTAssertEqual("\(events.count);\(events.last ?? "")", expected, context)
                case "stop":
                    bot.stop()
                default:
                    XCTFail("unknown op " + context)
                }
            }
        }
    }

    // MARK: - Golden vectors (JVM): league rules, house rosters, store JSON

    func testGoldenScheduleAndPalette() {
        let schedule = TripleShotLeague.schedule()
        let rows = ModesGolden.rows("SCHED")
        XCTAssertEqual(56, rows.count)
        for f in rows {
            let fixture = schedule[Int(f[1])!]
            XCTAssertEqual([fixture.round, fixture.home, fixture.away], [Int(f[2])!, Int(f[3])!, Int(f[4])!], f[5])
            XCTAssertEqual(fixture.key, f[5])
            XCTAssertEqual(fixture.key.javaHashCode, Int32(f[6])!, f[5])
        }
        XCTAssertEqual(TripleShotLeague.palette.map { String($0) }.joined(separator: ","), ModesGolden.rows("PALETTE")[0][1])
    }

    func testGoldenHouseRosters() {
        let rows = ModesGolden.rows("HR")
        XCTAssertEqual(34, rows.count)
        for f in rows {
            let ids = f[1].split(separator: ",").map(String.init)
            let size = Int(f[2])!
            let count = Int(f[3])!
            let seed = Int64(f[4])!
            let context = f.joined(separator: "|")
            if f[5].hasPrefix("ERR:") {
                XCTAssertThrowsError(try TripleShotLeague.houseRosters(available: ids, size: size, count: count, seed: seed), context)
            } else {
                let squads = try? TripleShotLeague.houseRosters(available: ids, size: size, count: count, seed: seed)
                XCTAssertEqual(squads?.map { $0.joined(separator: ",") }.joined(separator: ";"), f[5], context)
            }
        }
    }

    func testGoldenCharacterStrengths() {
        for f in ModesGolden.rows("STRENGTH") {
            XCTAssertEqual(ModesTests.strength([f[1]]), Int(f[2])!, f[1])
        }
        for f in ModesGolden.rows("STRENGTH_TEAM") {
            XCTAssertEqual(ModesTests.strength(f[1].split(separator: "+").map(String.init)), Int(f[2])!, f[1])
        }
    }

    func testGoldenCleanName() {
        let rows = ModesGolden.rows("CLEAN")
        XCTAssertEqual(25, rows.count)
        for f in rows {
            let clean = TripleShotLeague.cleanName(raw: ModesGolden.unescape(f[1]))
            XCTAssertEqual(clean, ModesGolden.unescape(f[2]), f[1])
            XCTAssertEqual(clean.utf16.count, Int(f[3])!, f[1])
        }
    }

    /// Seven seasons: the unit-test season (untimed and 120 s) and five built exactly like
    /// `TripleShotLeagueStore.create` (real rosters, strengths, colours, Hebrew house names, a team name with
    /// "/" and quotes). Every fixture is played through the rules and, where the Android JSON is known,
    /// through the store; the stored JSON must match Android's org.json output byte for byte. Since 6c38131
    /// `load()` repairs house rosters that contain the learner's own players (the unit-test seasons, every roster
    /// "a","b"): the store then plays its repaired season (SEASON_REPAIRED), which the rules alone do not.
    func testGoldenSeasonsRulesStoreAndJson() throws {
        let repairedRows = ModesGolden.keyed("SEASON_REPAIRED")
        let json0 = ModesGolden.keyed("SEASON_JSON0")
        let json1 = ModesGolden.keyed("SEASON_JSON1")
        let jsonFinal = ModesGolden.keyed("SEASON_JSON")
        let tables = ModesGolden.keyed("SEASON_TABLE")
        let finishedRows = ModesGolden.keyed("SEASON_FINISHED")
        let steps = ModesGolden.rows("SEASON_STEP")
        let seasons = ModesGolden.rows("SEASON")
        XCTAssertEqual(7, seasons.count)
        for f in seasons {
            let tag = f[1]
            let start = try ModesGolden.season(f[2])
            var store: TripleShotLeagueStore? = nil
            var storeSeason: TripleShotLeague.Season? = nil
            let repaired = try repairedRows[tag].map { try ModesGolden.season($0[0]) }
            if let json = json0[tag]?.first {
                putLeague(ModesGolden.unescape(json))
                let loaded = TripleShotLeagueStore()
                XCTAssertEqual(try loaded.load(), repaired ?? start, tag + ": Android JSON loads")
                store = loaded
                storeSeason = repaired ?? start
            }
            var s = start
            var played = 0
            for step in steps where step[1] == tag {
                let key = step[3]
                let own = Int(step[4])!
                let rival = Int(step[5])!
                let context = tag + " " + key
                XCTAssertEqual(s.next()?.key, key, context)
                let direct = try TripleShotLeague.complete(season: s, fixtureKey: key, ownScore: own, rivalScore: rival)
                XCTAssertEqual(direct.played, Int(step[6])!, context)
                XCTAssertEqual(direct.results.count, Int(step[7])!, context)
                XCTAssertEqual(direct.results.suffix(4).map { "\($0.fixture.key)=\($0.homeScore)-\($0.awayScore)" }.joined(separator: " "), step[8], context)
                XCTAssertEqual(try TripleShotLeague.complete(season: direct, fixtureKey: key, ownScore: own, rivalScore: rival), direct, context + " stale repeat")
                if let store = store, let before = storeSeason {
                    let storeDirect = try TripleShotLeague.complete(season: before, fixtureKey: key, ownScore: own, rivalScore: rival)
                    if repaired == nil { XCTAssertEqual(storeDirect, direct, context) }
                    XCTAssertEqual(try store.complete(seasonId: s.id, fixtureKey: key, own: own, rival: rival), storeDirect, context + " via store")
                    storeSeason = storeDirect
                    if step[2] == "0", let json = json1[tag]?.first {
                        XCTAssertEqual(storedLeague(), ModesGolden.unescape(json), tag + ": JSON after the first fixture")
                    }
                }
                s = direct
                played += 1
            }
            XCTAssertEqual(14, played, tag)
            XCTAssertTrue(s.finished, tag)
            XCTAssertNil(s.next(), tag)
            XCTAssertEqual(["true", "null"], finishedRows[tag] ?? [], tag)
            let table = TripleShotLeague.standings(season: s).map {
                "\($0.team.id):\($0.played):\($0.wins):\($0.scored):\($0.conceded):\($0.points):\($0.difference)"
            }.joined(separator: " ")
            XCTAssertEqual(table, tables[tag]?.first, tag)
            if let json = jsonFinal[tag]?.first {
                XCTAssertEqual(storedLeague(), ModesGolden.unescape(json), tag + ": final JSON")
            }
        }
    }

    func testGoldenCompleteEdgeCases() throws {
        let s = try season()
        let key = s.next()!.key
        for (own, rival) in [(4, 3), (11, 11), (10, 10), (11, -1), (1000, 3)] {
            XCTAssertThrowsError(try TripleShotLeague.complete(season: s, fixtureKey: key, ownScore: own, rivalScore: rival), "\(own)-\(rival)")
        }
        func results(_ season: TripleShotLeague.Season) -> String {
            return season.results.map { "\($0.fixture.key)=\($0.homeScore)-\($0.awayScore)" }.joined(separator: " ")
        }
        XCTAssertEqual(results(try TripleShotLeague.complete(season: s, fixtureKey: key, ownScore: 12, rivalScore: 10)), "0-0-7=12-10 0-6-1=11-4 0-2-5=4-11 0-4-3=11-10")
        let timed = try s.copy(matchSeconds: 180)
        XCTAssertEqual(results(try TripleShotLeague.complete(season: timed, fixtureKey: key, ownScore: 0, rivalScore: 1)), "0-0-7=0-1 0-6-1=23-18 0-2-5=21-24 0-4-3=29-26")
        XCTAssertEqual(results(try TripleShotLeague.complete(season: timed, fixtureKey: key, ownScore: 999, rivalScore: 998)), "0-0-7=999-998 0-6-1=23-18 0-2-5=21-24 0-4-3=29-26")
        XCTAssertThrowsError(try TripleShotLeague.complete(season: timed, fixtureKey: key, ownScore: 4, rivalScore: 4))
        XCTAssertThrowsError(try TripleShotLeague.complete(season: timed, fixtureKey: key, ownScore: 0, rivalScore: 1000))
    }

    func testGoldenSeasonValidation() throws {
        let s = try season()
        let schedule = TripleShotLeague.schedule()
        func rejects(_ name: String, _ block: () throws -> Any) {
            XCTAssertThrowsError(try block(), name) { error in
                XCTAssertEqual(error as? TripleShotLeague.RuleError, TripleShotLeague.RuleError.illegalArgument("Failed requirement."), name)
            }
        }
        func withRosters(_ roster: (Int) -> [String]) -> [TripleShotLeague.Team] {
            return s.teams.map { var t = $0; t.roster = roster(t.id); return t }
        }
        rejects("matchSeconds60") { try s.copy(matchSeconds: 60) }
        rejects("blankId") { try s.copy(id: " \u{09}") }
        rejects("sevenTeams") { try s.copy(teams: Array(s.teams.prefix(7))) }
        rejects("teamOrder") { try s.copy(teams: Array(s.teams.reversed())) }
        rejects("rosterSize1") { try s.copy(teams: withRosters { _ in ["a"] }) }
        rejects("rosterSize4") { try s.copy(teams: withRosters { _ in ["a", "b", "c", "d"] }) }
        rejects("rosterDup") { try s.copy(teams: withRosters { _ in ["a", "a"] }) }
        rejects("rosterMixed") { try s.copy(teams: withRosters { $0 == 3 ? ["a", "b", "c"] : ["a", "b"] }) }
        XCTAssertNoThrow(try s.copy(teams: withRosters { _ in ["a", "b", "c"] }), "roster3")
        rejects("dupResult") {
            try s.copy(results: [
                try TripleShotLeague.Result(fixture: schedule[0], homeScore: 11, awayScore: 2),
                try TripleShotLeague.Result(fixture: schedule[0], homeScore: 11, awayScore: 3)
            ])
        }
        rejects("foreignFixture") {
            try s.copy(results: [try TripleShotLeague.Result(fixture: TripleShotLeague.Fixture(round: 0, home: 7, away: 0), homeScore: 11, awayScore: 2)])
        }
        rejects("untimedLow") { try s.copy(results: [try TripleShotLeague.Result(fixture: schedule[1], homeScore: 10, awayScore: 2)]) }
        XCTAssertNoThrow(try s.copy(results: [try TripleShotLeague.Result(fixture: schedule[1], homeScore: 10, awayScore: 2)], matchSeconds: 300), "timedLow")
        rejects("resultTie") { try TripleShotLeague.Result(fixture: schedule[1], homeScore: 5, awayScore: 5) }
        rejects("resultNeg") { try TripleShotLeague.Result(fixture: schedule[1], homeScore: -1, awayScore: 5) }
        rejects("result1000") { try TripleShotLeague.Result(fixture: schedule[1], homeScore: 1000, awayScore: 5) }
        XCTAssertNoThrow(try TripleShotLeague.Result(fixture: schedule[1], homeScore: 999, awayScore: 0), "result999")
    }

    // MARK: - Golden vectors (JVM): daily court journey

    func testGoldenJourneyStagesQualitiesAndPicks() {
        let stages = BasketballJourney.stages
        let stageRows = ModesGolden.rows("STAGE")
        XCTAssertEqual(23, stageRows.count)
        for f in stageRows {
            let s = stages[Int(f[1])!]
            XCTAssertEqual(s.id, f[2])
            XCTAssertEqual(s.en, ModesGolden.unescape(f[3]), s.id)
            XCTAssertEqual(s.he, ModesGolden.unescape(f[4]), s.id)
            XCTAssertEqual(s.goals.map { "\($0.skill.name)x\($0.amount)" }.joined(separator: ","), f[5], s.id)
            XCTAssertEqual(s.teamSize, Int(f[6])!, s.id)
            XCTAssertEqual(String(s.quiet), f[7], s.id)
            XCTAssertEqual(String(s.helping), f[8], s.id)
        }
        for f in ModesGolden.rows("QUAL") {
            let stage = stages.first { $0.id == f[1] }!
            for entry in f[2].split(separator: ",") {
                let kv = entry.split(separator: "=")
                let q = kv[1].split(separator: "/")
                let r = TripleShotCharacterRoster.all.first { $0.id == String(kv[0]) }!.ratings
                XCTAssertEqual(stage.quality(r: r), Int(q[0])!, "\(f[1]) \(kv[0]) helper")
                XCTAssertEqual(stage.quality(r: r, helper: false), Int(q[1])!, "\(f[1]) \(kv[0]) opponent")
            }
        }
        let picks = ModesGolden.rows("PICK")
        XCTAssertEqual(56, picks.count)
        for f in picks {
            let stage = stages.first { $0.id == f[1] }!
            let helper = f[2] == "true"
            let excluded = Set(f[3].split(separator: "+").map(String.init))
            for entry in f[4].split(separator: ",") {
                let kv = entry.split(separator: "=")
                XCTAssertEqual(stage.bot(cycle: Int(kv[0])!, excluded: excluded, helper: helper).id, String(kv[1]), "\(f[1]) helper \(helper) cycle \(kv[0]) excluded \(f[3])")
            }
        }
        let lineups = ModesGolden.rows("LINEUP")
        XCTAssertEqual(54, lineups.count)
        for f in lineups {
            // BasketballJourneyActivity.start: used = {woman_dark}; teamSize-1 helpers, then teamSize opponents.
            let p = BasketballPractice(step: Int(f[1])!)
            let stage = p.stage
            XCTAssertEqual(stage.id, f[2])
            XCTAssertEqual(p.cycle, Int(f[3])!)
            var used: Set<String> = ["woman_dark"]
            var helpers: [String] = []
            for _ in 1..<stage.teamSize {
                let bot = stage.bot(cycle: p.cycle, excluded: used, helper: true)
                used.insert(bot.id)
                helpers.append(bot.id)
            }
            var opponents: [String] = []
            for _ in 0..<stage.teamSize {
                let bot = stage.bot(cycle: p.cycle, excluded: used, helper: false)
                used.insert(bot.id)
                opponents.append(bot.id)
            }
            XCTAssertEqual(helpers.joined(separator: ","), f[4], "step \(f[1])")
            XCTAssertEqual(opponents.joined(separator: ","), f[5], "step \(f[1])")
            XCTAssertEqual(stage.goals.indices.map { String(p.goal(i: $0)) }.joined(separator: ","), f[6], "step \(f[1])")
        }
        for entry in ModesGolden.rows("STAGE_WRAP")[0][1].split(separator: ",") {
            let kv = entry.split(separator: "=")
            XCTAssertEqual(BasketballJourney.stage(step: Int(kv[0])!).id, String(kv[1]), "stage(\(kv[0]))")
        }
    }

    func testGoldenPracticeEventSequences() {
        var practice: BasketballPractice? = nil
        var sequences = 0
        for f in ModesGolden.rows("PRACTICE") {
            let context = f.joined(separator: "|")
            if f[3] == "init" {
                let restored = f[2].isEmpty ? [] : f[2].split(separator: ",").map { ModesGolden.double(String($0)) }
                practice = BasketballPractice(step: Int(f[1])!, restored: restored)
                sequences += 1
            } else {
                let op = f[3].split(separator: ":")
                let changed = practice!.event(skill: BasketballSkill.named(String(op[0]))!, amount: ModesGolden.double(String(op[1])))
                XCTAssertEqual(String(changed), f[4], context)
            }
            ModesGolden.assertPractice(practice!, f[5], context)
        }
        XCTAssertEqual(8, sequences)
        let parts = ModesGolden.rows("PRACTICE_DEFAULT")[0][1].split(separator: ";", maxSplits: 1).map(String.init)
        let p = BasketballPractice(step: 1)
        XCTAssertEqual(String(p.event(skill: .PASS)), parts[0])
        ModesGolden.assertPractice(p, parts[1], "default amount 1.0")
    }

    // MARK: - Golden vectors (JVM): HORSE games

    func testGoldenLocalHorseGames() throws {
        var engines: [String: HorseGameEngine] = [:]
        let rows = ModesGolden.rows("HL")
        XCTAssertEqual(142, rows.count)
        for f in rows {
            let context = f.joined(separator: "|")
            let op = f[4].split(separator: ":").map(String.init)
            if op[0] == "new" {
                let engine = HorseGameEngine(maxPenalties: Int(f[2])!)
                engines[f[1]] = engine
                XCTAssertEqual(ModesGolden.horse(engine.snapshot()), f[6], context)
                continue
            }
            let e = engines[f[1]]!
            if op[0] == "config" {
                try e.configureChallenge(player: HorseGameEngine.Player.named(op[1])!, category: QuestionCategory.named(op[2])!, spotId: op[3])
                XCTAssertEqual(ModesGolden.horse(e.snapshot()), f[6], context)
            } else {
                let r = e.resolveAttempt(player: HorseGameEngine.Player.named(op[1])!, answerCorrect: op[2] == "true", made: op[3] == "true")
                XCTAssertEqual("\(r.type.name);\(r.actor.name);\(r.answerCorrect);\(r.made);\(r.penaltyAdded)", f[5], context)
                XCTAssertEqual(ModesGolden.horse(r.state), f[6], context)
            }
        }
        XCTAssertEqual(ModesGolden.horse(HorseGameEngine(firstSetter: .BOT).snapshot()), ModesGolden.rows("HL_BOTFIRST")[0][1])
    }

    func testGoldenLiveHorseGames() throws {
        let m = HorseGameEngine.Multiplayer.self
        var states: [String: LiveHorseState] = [:]
        let rows = ModesGolden.rows("HV")
        XCTAssertEqual(174, rows.count)
        for f in rows {
            let context = f.joined(separator: "|")
            let op = f[4].split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            switch op[0] {
            case "init":
                states[f[1]] = m.initialState(playerOrder: op[1].split(separator: ",").map(String.init), firstSetterUid: op[2])
            case "config":
                states[f[1]] = try m.configureChallenge(
                    state: states[f[1]]!, actorUid: op[1], category: QuestionCategory.named(op[2])!, spotId: op[3],
                    spotX: ModesGolden.float(op[4]), spotY: ModesGolden.float(op[5])
                )
            default:
                let r = try m.resolveAttempt(state: states[f[1]]!, actorUid: op[1], answerCorrect: op[2] == "true", made: op[3] == "true", maxPenalties: Int(f[2])!)
                XCTAssertEqual("\(r.penaltyAdded);\(r.eliminatedUid ?? "null");\(r.challengeEnded)", f[5], context)
                states[f[1]] = r.state
            }
            ModesGolden.assertLive(states[f[1]]!, f[6], context)
        }
        ModesGolden.assertLive(
            m.initialState(playerOrder: ["a", "", "b", "a", " ", "\u{09}", "b", "c"], firstSetterUid: "b"),
            ModesGolden.rows("HV_INIT")[0][1], "initialState: distinct, no blanks"
        )
        var four = try m.configureChallenge(
            state: m.initialState(playerOrder: ["a", "b", "c", "d"], firstSetterUid: "a"),
            actorUid: "a", category: .AI, spotId: "S", spotX: 1, spotY: 2
        )
        four.challengeEstablished = true
        four.currentPlayerUid = "b"
        let slotRows = ModesGolden.keyed("HV_SLOT")
        let slotCases: [(name: String, slots: [(String, Int)])] = [
            ("gap", [("q", 0), ("r", 2)]),
            ("full", [("q", 0), ("r", 1), ("s", 2)]),
            ("dupValues", [("q", 0), ("r", 0), ("s", 1)])
        ]
        for c in slotCases {
            var s = four
            for (uid, slot) in c.slots { s.spectatorSlots[uid] = slot }
            let r = try m.resolveAttempt(state: s, actorUid: "b", answerCorrect: false, made: true, maxPenalties: 1)
            let parts = slotRows[c.name]![0].split(separator: ";", maxSplits: 1).map(String.init)
            XCTAssertEqual(r.eliminatedUid ?? "null", parts[0], c.name)
            ModesGolden.assertLive(r.state, parts[1], c.name)
        }
    }
}

// MARK: - Golden vector plumbing

private enum ModesGolden {
    static let all: [[String]] = modesGoldenText.split(separator: "\n").map {
        $0.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
    }

    static func rows(_ tag: String) -> [[String]] { return all.filter { $0[0] == tag } }

    /// tag rows keyed by their first field (the remaining fields as values).
    static func keyed(_ tag: String) -> [String: [String]] {
        var out: [String: [String]] = [:]
        for f in rows(tag) { out[f[1]] = Array(f.dropFirst(2)) }
        return out
    }

    /// Inverse of the harness `esc`: every backslash-u-XXXX sequence is one UTF-16 unit.
    static func unescape(_ s: String) -> String {
        let chars = Array(s.utf16)
        var units: [UInt16] = []
        var i = 0
        while i < chars.count {
            if chars[i] == 0x5C, i + 5 < chars.count, chars[i + 1] == 0x75,
               let unit = UInt16(String(decoding: chars[(i + 2)...(i + 5)], as: UTF16.self), radix: 16) {
                units.append(unit)
                i += 6
            } else {
                units.append(chars[i])
                i += 1
            }
        }
        return String(decoding: units, as: UTF16.self)
    }

    /// The harness `esc`: UTF-16 units outside printable ASCII and the separators | backslash ; , escaped.
    static func esc(_ s: String) -> String {
        var out = ""
        for unit in s.utf16 {
            if unit < 0x20 || unit > 0x7E || unit == 0x7C || unit == 0x5C || unit == 0x3B || unit == 0x2C {
                out += "\\u" + hex(UInt64(unit), 4)
            } else {
                out.append(Character(Unicode.Scalar(UInt8(unit))))
            }
        }
        return out
    }

    static func hex(_ value: UInt64, _ width: Int) -> String {
        let h = String(value, radix: 16)
        return String(repeating: "0", count: max(0, width - h.count)) + h
    }

    static func bits(_ f: Float) -> String { return hex(UInt64(f.bitPattern), 8) }

    static func float(_ hexBits: String) -> Float { return Float(bitPattern: UInt32(hexBits, radix: 16)!) }

    /// Java `Double.toString` output back to the same double.
    static func double(_ s: String) -> Double {
        switch s {
        case "NaN": return Double.nan
        case "Infinity": return Double.infinity
        case "-Infinity": return -Double.infinity
        default: return Double(s)!
        }
    }

    static func state(_ s: LivePlayerState) -> String {
        return [
            s.uid, esc(s.name), String(s.score), String(s.knowledgeStreak), String(s.shootingStreak),
            String(s.bestKnowledgeStreak), String(s.bestShootingStreak), String(s.correctAnswers), String(s.madeShots),
            String(s.shots), esc(s.lastEvent), String(s.finished)
        ].joined(separator: ",")
    }

    static func turn(_ t: TripleShotBotOpponent.TurnPlan) -> String {
        return [
            String(t.selectedAnswerIndex), String(t.answerQualityPercent), bits(t.skill.aimError), bits(t.skill.powerError),
            bits(t.skill.arcError), bits(t.skill.rawPeakGyro), bits(t.skill.rawReleasePitchDeg), bits(t.pullBack)
        ].joined(separator: ",")
    }

    static func horse(_ s: HorseGameEngine.State) -> String {
        let challenge = s.challenge.map { "\($0.setter.name)/\($0.category.name)/\(esc($0.spotId))/\($0.established)" } ?? "null"
        return [
            s.setter.name, s.currentPlayer.name, challenge, String(s.humanPenalties), String(s.botPenalties),
            s.winner?.name ?? "null", String(s.isGameOver), String(s.needsNewChallenge)
        ].joined(separator: ";")
    }

    /// `id=..;seed=..;number=..;created=..;ms=..;teams=id:name:color:strength:a+b/...`
    static func season(_ text: String) throws -> TripleShotLeague.Season {
        var fields: [String: String] = [:]
        for part in text.split(separator: ";") {
            let kv = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            fields[String(kv[0])] = String(kv[1])
        }
        let teams = fields["teams"]!.split(separator: "/").map { team -> TripleShotLeague.Team in
            let p = team.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            return TripleShotLeague.Team(
                id: Int(p[0])!, name: unescape(p[1]), color: Int(p[2])!,
                roster: p[4].split(separator: "+").map(String.init), strength: Int(p[3])!
            )
        }
        return try TripleShotLeague.Season(
            id: unescape(fields["id"]!), seed: Int64(fields["seed"]!)!, number: Int(fields["number"]!)!,
            createdAt: Int64(fields["created"]!)!, teams: teams, matchSeconds: Int(fields["ms"]!)!
        )
    }

    static func assertPractice(_ p: BasketballPractice, _ expected: String, _ context: String, file: StaticString = #filePath, line: UInt = #line) {
        var fields: [String: String] = [:]
        for part in expected.split(separator: ";") {
            let kv = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            fields[String(kv[0])] = String(kv[1])
        }
        XCTAssertEqual(String(p.index), fields["i"], context, file: file, line: line)
        XCTAssertEqual(String(p.won), fields["won"], context, file: file, line: line)
        XCTAssertEqual(p.active?.name ?? "null", fields["active"], context, file: file, line: line)
        let progress = fields["progress"]!.split(separator: ",").map { double(String($0)).bitPattern }
        XCTAssertEqual(p.stage.goals.indices.map { p.progress(i: $0).bitPattern }, progress, context, file: file, line: line)
        let snap = fields["snap"]!.split(separator: ",").map { double(String($0)).bitPattern }
        XCTAssertEqual(p.snapshot().map { $0.bitPattern }, snap, context, file: file, line: line)
    }

    static func pairs(_ text: String) -> [String: Int] {
        var out: [String: Int] = [:]
        for entry in text.split(separator: ",") {
            let kv = entry.split(separator: "=")
            out[unescape(String(kv[0]))] = Int(kv[1])!
        }
        return out
    }

    /// Works for a Swift dictionary or an insertion-ordered map (both iterate (key:, value:) pairs).
    static func map<S: Sequence>(_ entries: S) -> [String: Int] where S.Element == (key: String, value: Int) {
        var out: [String: Int] = [:]
        for entry in entries { out[entry.key] = entry.value }
        return out
    }

    /// `phase;setter;current;established;category;spot;x;y;order;attempted;penalties;spectators;winner;turn;updatedAt;finished`
    static func assertLive(_ s: LiveHorseState, _ expected: String, _ context: String, file: StaticString = #filePath, line: UInt = #line) {
        let e = expected.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
        XCTAssertEqual(16, e.count, context, file: file, line: line)
        guard e.count == 16 else { return }
        XCTAssertEqual(s.phase, e[0], context, file: file, line: line)
        XCTAssertEqual(esc(s.setterUid), e[1], context, file: file, line: line)
        XCTAssertEqual(esc(s.currentPlayerUid), e[2], context, file: file, line: line)
        XCTAssertEqual(String(s.challengeEstablished), e[3], context, file: file, line: line)
        XCTAssertEqual(s.challengeCategory, e[4], context, file: file, line: line)
        XCTAssertEqual(esc(s.challengeSpotId), e[5], context, file: file, line: line)
        XCTAssertEqual(bits(s.challengeSpotX), e[6], context, file: file, line: line)
        XCTAssertEqual(bits(s.challengeSpotY), e[7], context, file: file, line: line)
        XCTAssertEqual(s.playerOrder.map { esc($0) }.joined(separator: ","), e[8], context, file: file, line: line)
        XCTAssertEqual(s.attemptedUids.map { esc($0) }.joined(separator: ","), e[9], context, file: file, line: line)
        XCTAssertEqual(map(s.penalties), pairs(e[10]), context, file: file, line: line)
        XCTAssertEqual(map(s.spectatorSlots), pairs(e[11]), context, file: file, line: line)
        XCTAssertEqual(esc(s.winnerUid), e[12], context, file: file, line: line)
        XCTAssertEqual(String(s.turnNumber), e[13], context, file: file, line: line)
        XCTAssertEqual(String(s.updatedAt), e[14], context, file: file, line: line)
        XCTAssertEqual(String(s.isFinished), e[15], context, file: file, line: line)
    }
}

// Printed by the JVM harness (work/t-modes/src/ModesHarness.kt) from the Android classes of snapshot dd722e5.
// Format: TAG|field|...; non-ASCII and separator characters are written as backslash-u-XXXX UTF-16 units.
private let modesGoldenText = #"""
RNG_FLOAT|42|3e67bf30,3ecf7e40,3f67ab3f,3f794731,3e8a9ce2,3e1af6a8,3f787209,3f7a480c
RNG_FLOAT|0|3f0cb4c2,3ea7fd5c,3f594e97,3f294e6b,3f28baf9,3e3f31ec,3c02dfc0,3e4183a0
RNG_FLOAT|-1|3f6f4c6d,3f3d7c38,3f017a28,3ea5b0b0,3ea54d10,3e160c8c,3ecd3b58,3f69ddca
RNG_FLOAT|1760600000000|3de7d758,3f0b26c2,3ec94da0,3eb0e406,3ea65626,3dfe3ae0,3ee4ab98,3f6930c5
RNG_FLOAT|5569068490923661129|3e6331a0,3f0692bc,3edf9d3e,3f743499,3f1152b4,3f241898,3f614cff,3f4ed3ac
BOTQ|q0|KIDS_ARITHMETIC|a=0,b=100,c=0,d=0
BOTQ|q1|PARADOX|a=100,b=0,c=0,d=100
BOTQ|q2|ENGLISH|a=100
BOTQ|q3|GENERAL_KNOWLEDGE|
BOTQ|q4|MATH|a=50,b=0,c=50
BOTQ|q5|PROGRAMMING|x0=100,x1=0,x2=0,x3=0
BOTQ|q6|SCIENCE|x0=0,x1=100,x2=0,x3=0
BOTQ|q7|ASTRONOMY|x0=0,x1=0,x2=100,x3=0
BOTQ|q8|AI|x0=0,x1=0,x2=0,x3=100
BOTQ|q9|HISTORY|x0=100,x1=0,x2=0,x3=0
BOTQ|q10|MATRICULATION_MATH|x0=0,x1=100,x2=0,x3=0
BOTQ|one_on_one|GENERAL_KNOWLEDGE|=100
BOT|bob|1760600000000|snapshot|LOCAL_BOT,BOB,0,0,0,0,0,0,0,0,,false
BOT|bob|1760600000000|start|1;LOCAL_BOT,BOB,0,0,0,0,0,0,0,0,\u2026,false
BOT|bob|1760600000000|start|1;LOCAL_BOT,BOB,0,0,0,0,0,0,0,0,\u2026,false
BOT|bob|1760600000000|choose:q0|1,100
BOT|bob|1760600000000|prepare:q0:INSIDE:1,100|1,100,3cfbd2df,3d8d7e9c,bd3b9032,00000000,00000000,3f340458
BOT|bob|1760600000000|prepare:q0:MID_RANGE:-|1,100,be0164f7,3dce47a5,3da538a6,00000000,00000000,3f30e028
BOT|bob|1760600000000|prepare:q0:-:-|1,100,be452856,bd7f31c8,ba8b167a,00000000,00000000,3f287a9b
BOT|bob|1760600000000|choose:q1|0,100
BOT|bob|1760600000000|prepare:q1:MID_RANGE:0,100|0,100,bdc750e1,3d88a77a,3c8f6cbe,00000000,00000000,3f436301
BOT|bob|1760600000000|prepare:q1:THREE_POINT:-|3,100,3d74c932,3e004876,bdadcdb8,00000000,00000000,3f397d99
BOT|bob|1760600000000|prepare:q1:-:-|1,0,3e120699,3c2fbf23,3caf84ec,00000000,00000000,3f3205e3
BOT|bob|1760600000000|choose:q2|0,100
BOT|bob|1760600000000|prepare:q2:THREE_POINT:0,100|0,100,3b2c8d32,bda1356c,ba96706d,00000000,00000000,3f319abe
BOT|bob|1760600000000|prepare:q2:INSIDE:-|0,100,be8e0b38,be9ba7b9,3e2dfd24,00000000,00000000,3f36b443
BOT|bob|1760600000000|prepare:q2:-:-|0,100,3daa8aee,bd329bfd,bc8a5f06,00000000,00000000,3f2fa623
BOT|bob|1760600000000|choose:q3|0,0
BOT|bob|1760600000000|prepare:q3:INSIDE:0,0|0,0,be35a7a7,bbd52780,3db5478e,00000000,00000000,3f31b15b
BOT|bob|1760600000000|prepare:q3:MID_RANGE:-|0,0,be8b7074,3e33be3f,bd3f7f56,00000000,00000000,3f1e1592
BOT|bob|1760600000000|prepare:q3:-:-|0,0,bd86aa6e,3d2ecdcd,badad115,00000000,00000000,3f26eff4
BOT|bob|1760600000000|choose:q4|1,0
BOT|bob|1760600000000|prepare:q4:MID_RANGE:1,0|1,0,bd4daa7d,bdcbca45,3be0dc36,00000000,00000000,3f3a1e2c
BOT|bob|1760600000000|prepare:q4:THREE_POINT:-|1,0,3e0ad2fb,bd49dcd9,bd5d56f5,00000000,00000000,3f1ef076
BOT|bob|1760600000000|prepare:q4:-:-|1,0,bda75078,3d982b5c,baf2d657,00000000,00000000,3f452085
BOT|bob|1760600000000|choose:q5|0,100
BOT|bob|1760600000000|prepare:q5:THREE_POINT:0,100|0,100,bdf7eb06,be10ac24,3c39b9f4,00000000,00000000,3f3ced9d
BOT|bob|1760600000000|prepare:q5:INSIDE:-|0,100,bde35720,be019e7d,3ba788ef,00000000,00000000,3f484f40
BOT|bob|1760600000000|prepare:q5:-:-|0,100,bee4c1ce,3e573ddf,bd871230,00000000,00000000,3f437ae7
BOT|bob|1760600000000|choose:q6|1,100
BOT|bob|1760600000000|prepare:q6:INSIDE:1,100|1,100,3d87f22f,bdd3ea19,bd0d2107,00000000,00000000,3f38d72c
BOT|bob|1760600000000|prepare:q6:MID_RANGE:-|1,100,bd67304c,bdaf47fc,3d59419a,00000000,00000000,3f3d356b
BOT|bob|1760600000000|prepare:q6:-:-|1,100,be07dcd8,3df26016,bc794b3a,00000000,00000000,3f2867c4
BOT|bob|1760600000000|choose:q7|0,0
BOT|bob|1760600000000|prepare:q7:MID_RANGE:0,0|0,0,3b75bebd,baf860be,3cbe8b50,00000000,00000000,3f2ad2ac
BOT|bob|1760600000000|prepare:q7:THREE_POINT:-|0,0,be4547e5,3daec5e2,bcc679d4,00000000,00000000,3f36c019
BOT|bob|1760600000000|prepare:q7:-:-|3,0,3c3c4084,ba831008,3b721bc9,00000000,00000000,3f28266d
BOT|bob|1760600000000|choose:q8|3,100
BOT|bob|1760600000000|prepare:q8:THREE_POINT:3,100|3,100,be379999,bc911866,3ce837d3,00000000,00000000,3f40bbf0
BOT|bob|1760600000000|prepare:q8:INSIDE:-|2,0,bd68652d,3bc99200,3c4dba87,00000000,00000000,3f4019f1
BOT|bob|1760600000000|prepare:q8:-:-|1,0,bc276b80,bd8130cf,bdabf520,00000000,00000000,3f3971f5
BOT|bob|1760600000000|choose:q9|0,100
BOT|bob|1760600000000|prepare:q9:INSIDE:0,100|0,100,3cbfff9a,bddd20ba,3c98113e,00000000,00000000,3f1ed9d3
BOT|bob|1760600000000|prepare:q9:MID_RANGE:-|3,0,be5a1801,3d286359,bd536ea9,00000000,00000000,3f40ff66
BOT|bob|1760600000000|prepare:q9:-:-|0,100,be240ec2,bd7f70e3,bd912a06,00000000,00000000,3f35a436
BOT|bob|1760600000000|choose:q10|1,100
BOT|bob|1760600000000|prepare:q10:MID_RANGE:1,100|1,100,3d43365c,be92080c,3daedb31,00000000,00000000,3f2f7c2c
BOT|bob|1760600000000|prepare:q10:THREE_POINT:-|2,0,3d7ccae7,3e9448d6,3d368704,00000000,00000000,3f242245
BOT|bob|1760600000000|prepare:q10:-:-|1,100,3e76c036,3ea27216,bd71bcd7,00000000,00000000,3f1848ef
BOT|bob|1760600000000|choose:one_on_one|0,100
BOT|bob|1760600000000|prepare:one_on_one:THREE_POINT:0,100|0,100,bd8f1797,3d255efc,bbb548da,00000000,00000000,3f3ad5e8
BOT|bob|1760600000000|prepare:one_on_one:INSIDE:-|0,100,3e38907a,bea10a3b,be33367a,00000000,00000000,3f4099e0
BOT|bob|1760600000000|prepare:one_on_one:-:-|0,100,3d1495df,bdb992ef,be20682f,00000000,00000000,3f318b6c
BOT|bob|1760600000000|prepare:one_on_one:INSIDE:0,100|0,100,bc24a0f2,bcc37aae,bbc7720f,00000000,00000000,3f29beee
BOT|bob|1760600000000|prepare:one_on_one:MID_RANGE:0,100|0,100,3cbcf0e7,3db1c4b4,3cb3dd7c,00000000,00000000,3f386e44
BOT|bob|1760600000000|prepare:one_on_one:THREE_POINT:0,100|0,100,3cdfdd35,3d60701d,3ca87a93,00000000,00000000,3f3b7eec
BOT|bob|1760600000000|record:100:true|2;LOCAL_BOT,BOB,9,1,1,1,1,1,1,1,\u2705  \ud83c\udfc0,false
BOT|bob|1760600000000|record:100:false|3;LOCAL_BOT,BOB,18,2,0,2,1,2,1,2,\u2705  \u2716\ud83c\udfc0,false
BOT|bob|1760600000000|record:0:true|4;LOCAL_BOT,BOB,20,0,1,2,1,2,2,3,\u274c  \ud83c\udfc0,false
BOT|bob|1760600000000|record:100:true|5;LOCAL_BOT,BOB,29,1,2,2,2,3,3,4,\u2705  \ud83c\udfc0,false
BOT|bob|1760600000000|record:100:false|6;LOCAL_BOT,BOB,38,2,0,2,2,4,3,5,\u2705  \u2716\ud83c\udfc0,false
BOT|bob|1760600000000|record:100:true|7;LOCAL_BOT,BOB,53,3,1,3,2,5,4,6,\u2705  \ud83c\udfc0,false
BOT|bob|1760600000000|record:50:true|8;LOCAL_BOT,BOB,56,0,2,3,2,5,5,7,\u274c  \ud83c\udfc0,false
BOT|bob|1760600000000|record:100:false|9;LOCAL_BOT,BOB,62,1,0,3,2,6,5,8,\u2705  \u2716\ud83c\udfc0,false
BOT|bob|1760600000000|record:0:true|10;LOCAL_BOT,BOB,64,0,1,3,2,6,6,9,\u274c  \ud83c\udfc0,false
BOT|bob|1760600000000|record:100:true|11;LOCAL_BOT,BOB,73,1,2,3,2,7,7,10,\u2705  \ud83c\udfc0,false
BOT|bob|1760600000000|record:100:true|12;LOCAL_BOT,BOB,85,2,3,3,3,8,8,11,\u2705  \ud83c\udfc0,false
BOT|bob|1760600000000|record:100:true|13;LOCAL_BOT,BOB,100,3,4,3,4,9,9,12,\u2705  \ud83c\udfc0,false
BOT|bob|1760600000000|record:100:true|14;LOCAL_BOT,BOB,118,4,5,4,5,10,10,13,\u2705  \ud83c\udfc0,false
BOT|bob|1760600000000|stop|-
BOT|bob|1760600000000|record:100:true|14;LOCAL_BOT,BOB,118,4,5,4,5,10,10,13,\u2705  \ud83c\udfc0,false
BOT|bob|1760600000000|snapshot|LOCAL_BOT,BOB,118,4,5,4,5,10,10,13,\u2705  \ud83c\udfc0,false
BOT|bob|1760600000000|prepare:q0:MID_RANGE:-|1,100,bdc04f71,3c691da7,3c2eb7c3,00000000,00000000,3f1ce5c7
BOT|bob|77|snapshot|LOCAL_BOT,BOB,0,0,0,0,0,0,0,0,,false
BOT|bob|77|start|1;LOCAL_BOT,BOB,0,0,0,0,0,0,0,0,\u2026,false
BOT|bob|77|start|1;LOCAL_BOT,BOB,0,0,0,0,0,0,0,0,\u2026,false
BOT|bob|77|observe:true|-
BOT|bob|77|observe:true|-
BOT|bob|77|observe:false|-
BOT|bob|77|observe:true|-
BOT|bob|77|observe:true|-
BOT|bob|77|observe:true|-
BOT|bob|77|observe:true|-
BOT|bob|77|observe:true|-
BOT|bob|77|observe:true|-
BOT|bob|77|observe:true|-
BOT|bob|77|observe:true|-
BOT|bob|77|observe:true|-
BOT|bob|77|observe:true|-
BOT|bob|77|observe:false|-
BOT|bob|77|choose:q0|1,100
BOT|bob|77|prepare:q0:INSIDE:1,100|1,100,3bdf2957,3d2b59b5,bc5b3ac0,00000000,00000000,3f33480c
BOT|bob|77|prepare:q0:MID_RANGE:-|1,100,bd585671,bba00fe8,bc7bd932,00000000,00000000,3f330b91
BOT|bob|77|prepare:q0:-:-|1,100,3d9645de,3b59b82f,3d39b784,00000000,00000000,3f37536b
BOT|bob|77|choose:q1|1,0
BOT|bob|77|prepare:q1:MID_RANGE:1,0|1,0,bd602966,3d940744,3c6ea640,00000000,00000000,3f2f7d56
BOT|bob|77|prepare:q1:THREE_POINT:-|1,0,bc009081,bd1d921e,3ba181f3,00000000,00000000,3f32cc2d
BOT|bob|77|prepare:q1:-:-|2,0,bd0afe99,3ccd336d,bc1ef8d5,00000000,00000000,3f2e545a
BOT|bob|77|choose:q2|0,100
BOT|bob|77|prepare:q2:THREE_POINT:0,100|0,100,3d76a2a0,bdabe9e5,3d21bc06,00000000,00000000,3f31d728
BOT|bob|77|prepare:q2:INSIDE:-|0,100,bd5386ec,bd07f7b2,3bd2faf6,00000000,00000000,3f389ee0
BOT|bob|77|prepare:q2:-:-|0,100,3e0420b8,3c821c6c,bb708b13,00000000,00000000,3f3308a4
BOT|bob|77|choose:q3|0,0
BOT|bob|77|prepare:q3:INSIDE:0,0|0,0,3c3e45f6,bc0ae597,bd09007e,00000000,00000000,3f335b65
BOT|bob|77|prepare:q3:MID_RANGE:-|0,0,be299524,bcfd2638,3ccd6ffb,00000000,00000000,3f48e273
BOT|bob|77|prepare:q3:-:-|0,0,bd202e21,3c805369,bcdbce16,00000000,00000000,3f2d238c
BOT|bob|77|choose:q4|0,50
BOT|bob|77|prepare:q4:MID_RANGE:0,50|0,50,3de9bc26,3e505306,bc180793,00000000,00000000,3f40236f
BOT|bob|77|prepare:q4:THREE_POINT:-|1,0,3ca326a6,bd3dc173,3d916251,00000000,00000000,3f3e4ad2
BOT|bob|77|prepare:q4:-:-|1,0,be0fe80a,3d8e616e,bd493a28,00000000,00000000,3f3388a6
BOT|bob|77|choose:q5|0,100
BOT|bob|77|prepare:q5:THREE_POINT:0,100|0,100,bda3c0c1,3c226768,bc1331df,00000000,00000000,3f37edaf
BOT|bob|77|prepare:q5:INSIDE:-|3,0,bcbdb232,bb8313c0,3c4299c9,00000000,00000000,3f3fd373
BOT|bob|77|prepare:q5:-:-|0,100,bcce6cf7,3b0cbc42,3d74f165,00000000,00000000,3f28bcf1
BOT|bob|77|choose:q6|1,100
BOT|bob|77|prepare:q6:INSIDE:1,100|1,100,3d82f5e8,3d7e08a6,3d0a6191,00000000,00000000,3f41cf96
BOT|bob|77|prepare:q6:MID_RANGE:-|1,100,bcfa8f5a,3d3384c1,3bcdf321,00000000,00000000,3f250c66
BOT|bob|77|prepare:q6:-:-|1,100,3de33b21,ba3bbb9e,bce7531b,00000000,00000000,3f30603f
BOT|bob|77|choose:q7|1,0
BOT|bob|77|prepare:q7:MID_RANGE:1,0|1,0,3d1f72bb,bd8a6126,bbebfe0b,00000000,00000000,3f3a7039
BOT|bob|77|prepare:q7:THREE_POINT:-|2,100,3db7a19a,3c659cbf,3bbd1c64,00000000,00000000,3f2c4522
BOT|bob|77|prepare:q7:-:-|1,0,bd33820b,3d5556f0,bc3dee35,00000000,00000000,3f2e94e3
BOT|bob|77|choose:q8|3,100
BOT|bob|77|prepare:q8:THREE_POINT:3,100|3,100,3d8b4df9,bba9b804,bbd98b94,00000000,00000000,3f2d6cd3
BOT|bob|77|prepare:q8:INSIDE:-|1,0,bbbaa031,bcf763f6,bd327988,00000000,00000000,3f42d597
BOT|bob|77|prepare:q8:-:-|3,100,3e128812,bd3f50a1,bcdac1e4,00000000,00000000,3f31aea2
BOT|bob|77|choose:q9|2,0
BOT|bob|77|prepare:q9:INSIDE:2,0|2,0,be269855,3bc5d3bf,bd0daec7,00000000,00000000,3f37be62
BOT|bob|77|prepare:q9:MID_RANGE:-|2,0,bd596220,bc2c1f2f,bd2a839a,00000000,00000000,3f34c1ad
BOT|bob|77|prepare:q9:-:-|2,0,3cb872e5,3c57e0d2,3c356975,00000000,00000000,3f342c3b
BOT|bob|77|choose:q10|1,100
BOT|bob|77|prepare:q10:MID_RANGE:1,100|1,100,3eafbe3b,3c5ba97f,bd807631,00000000,00000000,3f2f95f0
BOT|bob|77|prepare:q10:THREE_POINT:-|1,100,3e09b1d8,bdbbc083,bcc93435,00000000,00000000,3f2e1bf9
BOT|bob|77|prepare:q10:-:-|1,100,3c1d2d61,3d4f699c,39ac0eb7,00000000,00000000,3f371b78
BOT|bob|77|choose:one_on_one|0,100
BOT|bob|77|prepare:one_on_one:THREE_POINT:0,100|0,100,3ddb5bbe,3dc9775e,b9e35ed9,00000000,00000000,3f337356
BOT|bob|77|prepare:one_on_one:INSIDE:-|0,100,be135591,bd4a3865,bd2344d6,00000000,00000000,3f30b9fa
BOT|bob|77|prepare:one_on_one:-:-|0,100,bcadeffb,bda40d38,bbc4b207,00000000,00000000,3f42090c
BOT|bob|77|prepare:one_on_one:INSIDE:0,100|0,100,bd57e0ac,bd0190d9,bc1a94f7,00000000,00000000,3f31fab0
BOT|bob|77|prepare:one_on_one:MID_RANGE:0,100|0,100,bbfe1427,3d98fc41,3b1a43eb,00000000,00000000,3f25a970
BOT|bob|77|prepare:one_on_one:THREE_POINT:0,100|0,100,3e198ca9,bc58460b,bb0a2c6d,00000000,00000000,3f2b35c3
BOT|bob|77|record:100:true|2;LOCAL_BOT,BOB,9,1,1,1,1,1,1,1,\u2705  \ud83c\udfc0,false
BOT|bob|77|record:100:false|3;LOCAL_BOT,BOB,18,2,0,2,1,2,1,2,\u2705  \u2716\ud83c\udfc0,false
BOT|bob|77|record:0:true|4;LOCAL_BOT,BOB,20,0,1,2,1,2,2,3,\u274c  \ud83c\udfc0,false
BOT|bob|77|record:100:true|5;LOCAL_BOT,BOB,29,1,2,2,2,3,3,4,\u2705  \ud83c\udfc0,false
BOT|bob|77|record:100:false|6;LOCAL_BOT,BOB,38,2,0,2,2,4,3,5,\u2705  \u2716\ud83c\udfc0,false
BOT|bob|77|record:100:true|7;LOCAL_BOT,BOB,53,3,1,3,2,5,4,6,\u2705  \ud83c\udfc0,false
BOT|bob|77|record:50:true|8;LOCAL_BOT,BOB,56,0,2,3,2,5,5,7,\u274c  \ud83c\udfc0,false
BOT|bob|77|record:100:false|9;LOCAL_BOT,BOB,62,1,0,3,2,6,5,8,\u2705  \u2716\ud83c\udfc0,false
BOT|bob|77|record:0:true|10;LOCAL_BOT,BOB,64,0,1,3,2,6,6,9,\u274c  \ud83c\udfc0,false
BOT|bob|77|record:100:true|11;LOCAL_BOT,BOB,73,1,2,3,2,7,7,10,\u2705  \ud83c\udfc0,false
BOT|bob|77|record:100:true|12;LOCAL_BOT,BOB,85,2,3,3,3,8,8,11,\u2705  \ud83c\udfc0,false
BOT|bob|77|record:100:true|13;LOCAL_BOT,BOB,100,3,4,3,4,9,9,12,\u2705  \ud83c\udfc0,false
BOT|bob|77|record:100:true|14;LOCAL_BOT,BOB,118,4,5,4,5,10,10,13,\u2705  \ud83c\udfc0,false
BOT|bob|77|stop|-
BOT|bob|77|record:100:true|14;LOCAL_BOT,BOB,118,4,5,4,5,10,10,13,\u2705  \ud83c\udfc0,false
BOT|bob|77|snapshot|LOCAL_BOT,BOB,118,4,5,4,5,10,10,13,\u2705  \ud83c\udfc0,false
BOT|bob|77|prepare:q0:MID_RANGE:-|1,100,3db6baa3,3c944236,3d0a4d84,00000000,00000000,3f382712
BOT|ace_23|42|snapshot|LOCAL_BOT,Ace 23,0,0,0,0,0,0,0,0,,false
BOT|ace_23|42|start|1;LOCAL_BOT,Ace 23,0,0,0,0,0,0,0,0,\u2026,false
BOT|ace_23|42|start|1;LOCAL_BOT,Ace 23,0,0,0,0,0,0,0,0,\u2026,false
BOT|ace_23|42|choose:q0|1,100
BOT|ace_23|42|prepare:q0:INSIDE:1,100|1,100,3d0c5f27,3d0ff69e,3c475975,00000000,00000000,3f307666
BOT|ace_23|42|prepare:q0:MID_RANGE:-|1,100,bdd488df,bc88d9ba,bc7914ce,00000000,00000000,3f2d5f18
BOT|ace_23|42|prepare:q0:-:-|1,100,3d6c804d,3c398c54,3c5e5125,00000000,00000000,3f2e01af
BOT|ace_23|42|choose:q1|2,0
BOT|ace_23|42|prepare:q1:MID_RANGE:2,0|2,0,3ba2af89,3d44f744,bcc3fb19,00000000,00000000,3f315e35
BOT|ace_23|42|prepare:q1:THREE_POINT:-|0,100,3d1f5210,bb93113f,bd4d0caa,00000000,00000000,3f272177
BOT|ace_23|42|prepare:q1:-:-|1,0,3e302c0c,3df97dfe,bd8b30c9,00000000,00000000,3f420f71
BOT|ace_23|42|choose:q2|0,100
BOT|ace_23|42|prepare:q2:THREE_POINT:0,100|0,100,3d8f421d,3d254430,3c4a4be8,00000000,00000000,3f2bc8b8
BOT|ace_23|42|prepare:q2:INSIDE:-|0,100,bcacd63f,3d38db12,3c4230fc,00000000,00000000,3f2d5c18
BOT|ace_23|42|prepare:q2:-:-|0,100,bd866582,3cf2bafc,3d08a134,00000000,00000000,3f33b45e
BOT|ace_23|42|choose:q3|0,0
BOT|ace_23|42|prepare:q3:INSIDE:0,0|0,0,3cb92c5e,3c2629e5,3d43b8d6,00000000,00000000,3f3f8ceb
BOT|ace_23|42|prepare:q3:MID_RANGE:-|0,0,3d54b11f,bd0e9d4c,bda2f676,00000000,00000000,3f272576
BOT|ace_23|42|prepare:q3:-:-|0,0,3c757183,bd856207,3cfa46b9,00000000,00000000,3f38e363
BOT|ace_23|42|choose:q4|0,50
BOT|ace_23|42|prepare:q4:MID_RANGE:0,50|0,50,3e095587,bd7d6f73,ba504048,00000000,00000000,3f428521
BOT|ace_23|42|prepare:q4:THREE_POINT:-|2,50,3dc06071,3d8f33b2,3d09c82b,00000000,00000000,3f3a8095
BOT|ace_23|42|prepare:q4:-:-|1,0,3e1c27aa,ba8550d5,bcfea895,00000000,00000000,3f35f8c0
BOT|ace_23|42|choose:q5|0,100
BOT|ace_23|42|prepare:q5:THREE_POINT:0,100|0,100,bd999093,bd1cf737,3cb035fc,00000000,00000000,3f32bca3
BOT|ace_23|42|prepare:q5:INSIDE:-|0,100,3d35305c,bd0bee03,3a8be716,00000000,00000000,3f3f6a2a
BOT|ace_23|42|prepare:q5:-:-|0,100,3da3bcec,bc9401c0,3d07cd67,00000000,00000000,3f2ceae5
BOT|ace_23|42|choose:q6|0,0
BOT|ace_23|42|prepare:q6:INSIDE:0,0|0,0,bdceb361,bd2e2bb4,3b9f22ef,00000000,00000000,3f264d79
BOT|ace_23|42|prepare:q6:MID_RANGE:-|3,0,3e9b2985,bdef36fc,be006a82,00000000,00000000,3f45aef6
BOT|ace_23|42|prepare:q6:-:-|1,100,bdb8b5fa,bc9788aa,3d133913,00000000,00000000,3f30161c
BOT|ace_23|42|choose:q7|2,100
BOT|ace_23|42|prepare:q7:MID_RANGE:2,100|2,100,3bfdf958,3c0e8ba7,3a7a2584,00000000,00000000,3f3037b8
BOT|ace_23|42|prepare:q7:THREE_POINT:-|2,100,bdda2307,bde18a1e,bc9f2684,00000000,00000000,3f37a0f9
BOT|ace_23|42|prepare:q7:-:-|1,0,3d006ac9,3d549c35,3c497585,00000000,00000000,3f3f35fb
BOT|ace_23|42|choose:q8|3,100
BOT|ace_23|42|prepare:q8:THREE_POINT:3,100|3,100,bd92d41d,3c98e708,3d37cd38,00000000,00000000,3f305777
BOT|ace_23|42|prepare:q8:INSIDE:-|3,100,be2aacb4,bd1054fb,bd30465f,00000000,00000000,3f2c2914
BOT|ace_23|42|prepare:q8:-:-|2,0,3c1a0e00,bbbdf909,bd2dabc3,00000000,00000000,3f347822
BOT|ace_23|42|choose:q9|2,0
BOT|ace_23|42|prepare:q9:INSIDE:2,0|2,0,3d580171,bd8ae676,3c8f4c63,00000000,00000000,3f3442fa
BOT|ace_23|42|prepare:q9:MID_RANGE:-|0,100,3e9a7db9,bdc1bccd,3d2c4050,00000000,00000000,3f228d38
BOT|ace_23|42|prepare:q9:-:-|1,0,bcdf1c23,3e1ce0b6,bc7ee52d,00000000,00000000,3f384ea8
BOT|ace_23|42|choose:q10|1,100
BOT|ace_23|42|prepare:q10:MID_RANGE:1,100|1,100,bc828815,bda3823f,3b2049ea,00000000,00000000,3f42310b
BOT|ace_23|42|prepare:q10:THREE_POINT:-|1,100,3d97d245,3ca34dd2,3d241e19,00000000,00000000,3f384879
BOT|ace_23|42|prepare:q10:-:-|1,100,3de1d135,bbb13d51,bcce44dd,00000000,00000000,3f392727
BOT|ace_23|42|choose:one_on_one|0,100
BOT|ace_23|42|prepare:one_on_one:THREE_POINT:0,100|0,100,bd61d7b6,bd9f551f,badc24ff,00000000,00000000,3f2e60e2
BOT|ace_23|42|prepare:one_on_one:INSIDE:-|0,100,bd5fa080,bcf3e9a4,3b43b1e2,00000000,00000000,3f38c90d
BOT|ace_23|42|prepare:one_on_one:-:-|0,100,bb05734e,3da4c765,3d0cecde,00000000,00000000,3f2a3d89
BOT|ace_23|42|prepare:one_on_one:INSIDE:0,100|0,100,3ccf31a6,3d90ffe3,3d56cc71,00000000,00000000,3f392e7f
BOT|ace_23|42|prepare:one_on_one:MID_RANGE:0,100|0,100,3d453ab8,bda8ae40,3bbfd0e4,00000000,00000000,3f353ada
BOT|ace_23|42|prepare:one_on_one:THREE_POINT:0,100|0,100,bcc43f7f,bc168873,3d11cbec,00000000,00000000,3f430ed9
BOT|ace_23|42|record:100:true|2;LOCAL_BOT,Ace 23,9,1,1,1,1,1,1,1,\u2705  \ud83c\udfc0,false
BOT|ace_23|42|record:100:false|3;LOCAL_BOT,Ace 23,18,2,0,2,1,2,1,2,\u2705  \u2716\ud83c\udfc0,false
BOT|ace_23|42|record:0:true|4;LOCAL_BOT,Ace 23,20,0,1,2,1,2,2,3,\u274c  \ud83c\udfc0,false
BOT|ace_23|42|record:100:true|5;LOCAL_BOT,Ace 23,29,1,2,2,2,3,3,4,\u2705  \ud83c\udfc0,false
BOT|ace_23|42|record:100:false|6;LOCAL_BOT,Ace 23,38,2,0,2,2,4,3,5,\u2705  \u2716\ud83c\udfc0,false
BOT|ace_23|42|record:100:true|7;LOCAL_BOT,Ace 23,53,3,1,3,2,5,4,6,\u2705  \ud83c\udfc0,false
BOT|ace_23|42|record:50:true|8;LOCAL_BOT,Ace 23,56,0,2,3,2,5,5,7,\u274c  \ud83c\udfc0,false
BOT|ace_23|42|record:100:false|9;LOCAL_BOT,Ace 23,62,1,0,3,2,6,5,8,\u2705  \u2716\ud83c\udfc0,false
BOT|ace_23|42|record:0:true|10;LOCAL_BOT,Ace 23,64,0,1,3,2,6,6,9,\u274c  \ud83c\udfc0,false
BOT|ace_23|42|record:100:true|11;LOCAL_BOT,Ace 23,73,1,2,3,2,7,7,10,\u2705  \ud83c\udfc0,false
BOT|ace_23|42|record:100:true|12;LOCAL_BOT,Ace 23,85,2,3,3,3,8,8,11,\u2705  \ud83c\udfc0,false
BOT|ace_23|42|record:100:true|13;LOCAL_BOT,Ace 23,100,3,4,3,4,9,9,12,\u2705  \ud83c\udfc0,false
BOT|ace_23|42|record:100:true|14;LOCAL_BOT,Ace 23,118,4,5,4,5,10,10,13,\u2705  \ud83c\udfc0,false
BOT|ace_23|42|stop|-
BOT|ace_23|42|record:100:true|14;LOCAL_BOT,Ace 23,118,4,5,4,5,10,10,13,\u2705  \ud83c\udfc0,false
BOT|ace_23|42|snapshot|LOCAL_BOT,Ace 23,118,4,5,4,5,10,10,13,\u2705  \ud83c\udfc0,false
BOT|ace_23|42|prepare:q0:MID_RANGE:-|1,100,bd8a7189,bd6fd8ec,bc9a7bb4,00000000,00000000,3f256dbf
SCHED|0|0|0|7|0-0-7|45717181
SCHED|1|0|6|1|0-6-1|45722941
SCHED|2|0|2|5|0-2-5|45719101
SCHED|3|0|4|3|0-4-3|45721021
SCHED|4|1|6|0|1-6-0|46646461
SCHED|5|1|7|5|1-7-5|46647427
SCHED|6|1|4|1|1-4-1|46644540
SCHED|7|1|2|3|1-2-3|46642620
SCHED|8|2|0|5|2-0-5|47564221
SCHED|9|2|4|6|2-4-6|47568066
SCHED|10|2|7|3|2-7-3|47570946
SCHED|11|2|2|1|2-2-1|47566139
SCHED|12|3|4|0|3-4-0|48491581
SCHED|13|3|5|3|3-5-3|48492545
SCHED|14|3|2|6|3-2-6|48489665
SCHED|15|3|7|1|3-7-1|48494465
SCHED|16|4|0|3|4-0-3|49411261
SCHED|17|4|2|4|4-2-4|49413184
SCHED|18|4|5|1|4-5-1|49416064
SCHED|19|4|7|6|4-7-6|49417991
SCHED|20|5|2|0|5-2-0|50336701
SCHED|21|5|3|1|5-3-1|50337663
SCHED|22|5|7|4|5-7-4|50341510
SCHED|23|5|5|6|5-5-6|50339590
SCHED|24|6|0|1|6-0-1|51258301
SCHED|25|6|7|2|6-7-2|51265029
SCHED|26|6|3|6|6-3-6|51261189
SCHED|27|6|5|4|6-5-4|51263109
SCHED|28|7|7|0|7-7-0|52188548
SCHED|29|7|1|6|7-1-6|52182788
SCHED|30|7|5|2|7-5-2|52186628
SCHED|31|7|3|4|7-3-4|52184708
SCHED|32|8|0|6|8-0-6|53105348
SCHED|33|8|5|7|8-5-7|53110154
SCHED|34|8|1|4|8-1-4|53106307
SCHED|35|8|3|2|8-3-2|53108227
SCHED|36|9|5|0|9-5-0|54033668
SCHED|37|9|6|4|9-6-4|54034633
SCHED|38|9|3|7|9-3-7|54031753
SCHED|39|9|1|2|9-1-2|54029826
SCHED|40|10|0|4|10-0-4|1448545577
SCHED|41|10|3|5|10-3-5|1448548461
SCHED|42|10|6|2|10-6-2|1448551341
SCHED|43|10|1|7|10-1-7|1448546541
SCHED|44|11|3|0|11-3-0|1449471977
SCHED|45|11|4|2|11-4-2|1449472940
SCHED|46|11|1|5|11-1-5|1449470060
SCHED|47|11|6|7|11-6-7|1449474867
SCHED|48|12|0|2|12-0-2|1450392617
SCHED|49|12|1|3|12-1-3|1450393579
SCHED|50|12|4|7|12-4-7|1450396466
SCHED|51|12|6|5|12-6-5|1450398386
SCHED|52|13|1|0|13-1-0|1451317097
SCHED|53|13|2|7|13-2-7|1451318065
SCHED|54|13|6|3|13-6-3|1451321905
SCHED|55|13|4|5|13-4-5|1451319985
PALETTE|-8988417,-18567,-3759873,-8330051,-26691,-666001
HR|0,1,2,3,4,5,6,7,8|2|7|1|1,6;0,3;4,5;2,8;6,7;1,5;3,7
HR|0,1,2,3,4,5,6,7,8|2|7|2|2,4;7,8;0,1;5,6;3,8;5,7;2,6
HR|0,1,2,3,4,5,6,7,8|2|7|42|2,4;1,3;0,5;6,7;4,8;1,6;5,7
HR|0,1,2,3,4,5,6,7,8|2|7|50|0,8;1,4;6,7;2,5;3,5;3,6;1,2
HR|0,1,2,3,4,5,6,7,8|2|7|-1|4,7;1,8;3,6;2,5;0,6;3,5;1,4
HR|0,1,2,3,4,5,6,7,8|2|7|1760600000000|1,2;3,8;6,7;0,4;3,5;0,6;1,8
HR|0,1,2,3,4,5,6,7,8|3|7|1|2,4,8;0,3,6;1,5,7;0,4,5;1,2,3;6,7,8;0,1,8
HR|0,1,2,3,4,5,6,7,8|3|7|2|4,7,8;2,3,6;0,1,5;0,2,7;1,3,8;4,5,6;0,3,4
HR|0,1,2,3,4,5,6,7,8|3|7|42|2,3,8;5,6,7;0,1,4;1,6,8;3,4,7;0,2,5;4,5,8
HR|0,1,2,3,4,5,6,7,8|3|7|50|1,3,8;5,6,7;0,2,4;3,4,7;0,1,5;2,6,8;0,3,6
HR|0,1,2,3,4,5,6,7,8|3|7|-1|5,6,7;1,2,4;0,3,8;2,3,6;1,7,8;0,4,5;1,3,5
HR|0,1,2,3,4,5,6,7,8|3|7|1760600000000|1,5,6;0,3,7;2,4,8;0,5,8;4,6,7;1,2,3;3,4,5
HR|a,b,c|2|7|42|a,c;a,b;b,c;a,b;b,c;a,c;a,b
HR|a,b,c,a|2|4|7|a,c;b,c;a,b;b,c
HR|a,b,c|3|3|9|a,b,c;a,b,c;a,b,c
HR|x,y|2|0|5|
HR|a,b,c,d|2|12|3|a,c;b,d;a,b;c,d;a,d;b,c;b,d;a,c;a,d;b,c;a,b;c,d
HR|a,b,c,d,e|3|15|11|a,d,e;b,c,e;b,c,d;a,c,e;a,b,d;a,b,c;c,d,e;a,b,e;b,d,e;a,c,d;a,c,e;a,b,d;c,d,e;b,d,e;a,b,c
HR|a,b|1|1|1|ERR:IllegalArgumentException
HR|a,b,c,d|4|1|1|ERR:IllegalArgumentException
HR|a|2|1|1|ERR:IllegalArgumentException
HR|a,b|2|-1|1|ERR:IllegalArgumentException
HR|nova,unicorn_32,coach_67,zephyr,kyra,kyra_original,flare,ace_23,buddy_23|2|7|1760600000000|unicorn_32,coach_67;zephyr,buddy_23;flare,ace_23;nova,kyra;zephyr,kyra_original;nova,flare;unicorn_32,buddy_23
HR|nova,unicorn_32,coach_67,zephyr,kyra,kyra_original,flare,ace_23,buddy_23|2|7|1760612345678|unicorn_32,kyra_original;ace_23,buddy_23;kyra,flare;nova,coach_67;zephyr,flare;nova,unicorn_32;zephyr,ace_23
HR|nova,unicorn_32,coach_67,zephyr,kyra,kyra_original,flare,ace_23,buddy_23|2|7|1|unicorn_32,flare;nova,zephyr;kyra,kyra_original;coach_67,buddy_23;flare,ace_23;unicorn_32,kyra_original;zephyr,ace_23
HR|unicorn_32,coach_67,zephyr,kyra,kyra_original,flare,ace_23,buddy_23|3|7|1760600000000|coach_67,kyra_original,buddy_23;unicorn_32,flare,ace_23;zephyr,kyra,kyra_original;unicorn_32,coach_67,kyra;zephyr,ace_23,buddy_23;coach_67,zephyr,flare;kyra,flare,buddy_23
HR|unicorn_32,coach_67,zephyr,kyra,kyra_original,flare,ace_23,buddy_23|3|7|1760612345678|zephyr,ace_23,buddy_23;kyra,kyra_original,flare;unicorn_32,coach_67,flare;coach_67,kyra,buddy_23;unicorn_32,zephyr,kyra_original;coach_67,kyra_original,ace_23;unicorn_32,kyra,ace_23
HR|unicorn_32,coach_67,zephyr,kyra,kyra_original,flare,ace_23,buddy_23|3|7|1|kyra_original,ace_23,buddy_23;unicorn_32,zephyr,kyra;coach_67,flare,buddy_23;coach_67,kyra,ace_23;unicorn_32,kyra_original,flare;zephyr,flare,ace_23;coach_67,zephyr,kyra_original
HR|woman_dark,rooza,nova,unicorn_32,coach_67,zephyr,kyra,flare,ace_23|2|7|1760600000000|rooza,nova;unicorn_32,ace_23;kyra,flare;woman_dark,coach_67;unicorn_32,zephyr;woman_dark,kyra;rooza,ace_23
HR|woman_dark,rooza,nova,unicorn_32,coach_67,zephyr,kyra,flare,ace_23|2|7|1760612345678|rooza,zephyr;flare,ace_23;coach_67,kyra;woman_dark,nova;unicorn_32,kyra;woman_dark,rooza;unicorn_32,flare
HR|woman_dark,rooza,nova,unicorn_32,coach_67,zephyr,kyra,flare,ace_23|2|7|1|rooza,kyra;woman_dark,unicorn_32;coach_67,zephyr;nova,ace_23;kyra,flare;rooza,zephyr;unicorn_32,flare
HR|woman_dark,rooza,nova,unicorn_32,coach_67,kyra,kyra_original,buddy_23|3|7|1760600000000|rooza,coach_67,buddy_23;woman_dark,kyra,kyra_original;nova,unicorn_32,coach_67;woman_dark,rooza,unicorn_32;nova,kyra_original,buddy_23;rooza,nova,kyra;unicorn_32,kyra,buddy_23
HR|woman_dark,rooza,nova,unicorn_32,coach_67,kyra,kyra_original,buddy_23|3|7|1760612345678|nova,kyra_original,buddy_23;unicorn_32,coach_67,kyra;woman_dark,rooza,kyra;rooza,unicorn_32,buddy_23;woman_dark,nova,coach_67;rooza,coach_67,kyra_original;woman_dark,unicorn_32,kyra_original
HR|woman_dark,rooza,nova,unicorn_32,coach_67,kyra,kyra_original,buddy_23|3|7|1|coach_67,kyra_original,buddy_23;woman_dark,nova,unicorn_32;rooza,kyra,buddy_23;rooza,unicorn_32,kyra_original;woman_dark,coach_67,kyra;nova,kyra,kyra_original;rooza,nova,coach_67
STRENGTH|bob|61
STRENGTH|woman_dark|77
STRENGTH|rooza|80
STRENGTH|nova|87
STRENGTH|unicorn_32|79
STRENGTH|coach_67|78
STRENGTH|zephyr|84
STRENGTH|kyra|84
STRENGTH|kyra_original|84
STRENGTH|flare|84
STRENGTH|ace_23|80
STRENGTH|buddy_23|78
STRENGTH_TEAM|woman_dark+rooza|78
STRENGTH_TEAM|woman_dark+rooza+nova|81
STRENGTH_TEAM|unicorn_32+coach_67+flare|80
SEASON|unit42|id=s1;seed=42;number=1;created=1000;ms=0;teams=0:Team 0:-8988417:50:a+b/1:Team 1:-18567:51:a+b/2:Team 2:-3759873:52:a+b/3:Team 3:-8330051:53:a+b/4:Team 4:-26691:54:a+b/5:Team 5:-666001:55:a+b/6:Team 6:-8988417:56:a+b/7:Team 7:-18567:57:a+b
SEASON_JSON0|unit42|{"version":1\u002c"id":"s1"\u002c"seed":42\u002c"number":1\u002c"created":1000\u002c"matchSeconds":0\u002c"teams":[{"id":0\u002c"name":"Team 0"\u002c"color":-8988417\u002c"strength":50\u002c"roster":["a"\u002c"b"]}\u002c{"id":1\u002c"name":"Team 1"\u002c"color":-18567\u002c"strength":51\u002c"roster":["a"\u002c"b"]}\u002c{"id":2\u002c"name":"Team 2"\u002c"color":-3759873\u002c"strength":52\u002c"roster":["a"\u002c"b"]}\u002c{"id":3\u002c"name":"Team 3"\u002c"color":-8330051\u002c"strength":53\u002c"roster":["a"\u002c"b"]}\u002c{"id":4\u002c"name":"Team 4"\u002c"color":-26691\u002c"strength":54\u002c"roster":["a"\u002c"b"]}\u002c{"id":5\u002c"name":"Team 5"\u002c"color":-666001\u002c"strength":55\u002c"roster":["a"\u002c"b"]}\u002c{"id":6\u002c"name":"Team 6"\u002c"color":-8988417\u002c"strength":56\u002c"roster":["a"\u002c"b"]}\u002c{"id":7\u002c"name":"Team 7"\u002c"color":-18567\u002c"strength":57\u002c"roster":["a"\u002c"b"]}]\u002c"results":[]}
SEASON_REPAIRED|unit42|id=s1;seed=42;number=1;created=1000;ms=0;teams=0:Team 0:-8988417:50:a+b/1:Team 1:-18567:78:woman_dark+rooza/2:Team 2:-3759873:78:woman_dark+rooza/3:Team 3:-8330051:78:woman_dark+rooza/4:Team 4:-26691:78:woman_dark+rooza/5:Team 5:-666001:78:woman_dark+rooza/6:Team 6:-8988417:78:woman_dark+rooza/7:Team 7:-18567:78:woman_dark+rooza
SEASON_STEP|unit42|0|0-0-7|11|6|1|4|0-0-7=11-6 0-6-1=11-4 0-2-5=4-11 0-4-3=11-10
SEASON_STEP|unit42|1|1-6-0|6|11|2|8|1-6-0=11-6 1-7-5=11-6 1-4-1=2-11 1-2-3=11-8
SEASON_STEP|unit42|2|2-0-5|11|6|3|12|2-0-5=11-6 2-4-6=8-11 2-7-3=11-4 2-2-1=11-2
SEASON_STEP|unit42|3|3-4-0|6|11|4|16|3-4-0=11-6 3-5-3=11-5 3-2-6=10-11 3-7-1=3-11
SEASON_STEP|unit42|4|4-0-3|11|6|5|20|4-0-3=11-6 4-2-4=11-3 4-5-1=3-11 4-7-6=6-11
SEASON_STEP|unit42|5|5-2-0|6|11|6|24|5-2-0=11-6 5-3-1=11-2 5-7-4=10-11 5-5-6=11-1
SEASON_STEP|unit42|6|6-0-1|11|6|7|28|6-0-1=11-6 6-7-2=11-9 6-3-6=3-11 6-5-4=1-11
SEASON_STEP|unit42|7|7-7-0|6|11|8|32|7-7-0=11-6 7-1-6=11-10 7-5-2=11-2 7-3-4=11-2
SEASON_STEP|unit42|8|8-0-6|11|6|9|36|8-0-6=11-6 8-5-7=11-2 8-1-4=5-11 8-3-2=11-1
SEASON_STEP|unit42|9|9-5-0|6|11|10|40|9-5-0=11-6 9-6-4=6-11 9-3-7=10-11 9-1-2=5-11
SEASON_STEP|unit42|10|10-0-4|11|6|11|44|10-0-4=11-6 10-3-5=11-10 10-6-2=11-10 10-1-7=6-11
SEASON_STEP|unit42|11|11-3-0|6|11|12|48|11-3-0=11-6 11-4-2=8-11 11-1-5=11-1 11-6-7=11-5
SEASON_STEP|unit42|12|12-0-2|11|6|13|52|12-0-2=11-6 12-1-3=5-11 12-4-7=11-8 12-6-5=4-11
SEASON_STEP|unit42|13|13-1-0|6|11|14|56|13-1-0=11-6 13-2-7=6-11 13-6-3=9-11 13-4-5=11-5
SEASON_TABLE|unit42|6:14:8:124:118:24:6 4:14:8:117:117:24:0 3:14:7:123:112:21:11 5:14:7:109:101:21:8 0:14:7:119:119:21:0 7:14:7:117:124:21:-7 2:14:6:114:120:18:-6 1:14:6:101:113:18:-12
SEASON_JSON|unit42|{"version":1\u002c"id":"s1"\u002c"seed":42\u002c"number":1\u002c"created":1000\u002c"matchSeconds":0\u002c"teams":[{"id":0\u002c"name":"Team 0"\u002c"color":-8988417\u002c"strength":50\u002c"roster":["a"\u002c"b"]}\u002c{"id":1\u002c"name":"Team 1"\u002c"color":-18567\u002c"strength":78\u002c"roster":["woman_dark"\u002c"rooza"]}\u002c{"id":2\u002c"name":"Team 2"\u002c"color":-3759873\u002c"strength":78\u002c"roster":["woman_dark"\u002c"rooza"]}\u002c{"id":3\u002c"name":"Team 3"\u002c"color":-8330051\u002c"strength":78\u002c"roster":["woman_dark"\u002c"rooza"]}\u002c{"id":4\u002c"name":"Team 4"\u002c"color":-26691\u002c"strength":78\u002c"roster":["woman_dark"\u002c"rooza"]}\u002c{"id":5\u002c"name":"Team 5"\u002c"color":-666001\u002c"strength":78\u002c"roster":["woman_dark"\u002c"rooza"]}\u002c{"id":6\u002c"name":"Team 6"\u002c"color":-8988417\u002c"strength":78\u002c"roster":["woman_dark"\u002c"rooza"]}\u002c{"id":7\u002c"name":"Team 7"\u002c"color":-18567\u002c"strength":78\u002c"roster":["woman_dark"\u002c"rooza"]}]\u002c"results":[{"round":0\u002c"home":0\u002c"away":7\u002c"a":11\u002c"b":6}\u002c{"round":0\u002c"home":6\u002c"away":1\u002c"a":4\u002c"b":11}\u002c{"round":0\u002c"home":2\u002c"away":5\u002c"a":4\u002c"b":11}\u002c{"round":0\u002c"home":4\u002c"away":3\u002c"a":11\u002c"b":10}\u002c{"round":1\u002c"home":6\u002c"away":0\u002c"a":11\u002c"b":6}\u002c{"round":1\u002c"home":7\u002c"away":5\u002c"a":11\u002c"b":6}\u002c{"round":1\u002c"home":4\u002c"away":1\u002c"a":2\u002c"b":11}\u002c{"round":1\u002c"home":2\u002c"away":3\u002c"a":11\u002c"b":8}\u002c{"round":2\u002c"home":0\u002c"away":5\u002c"a":11\u002c"b":6}\u002c{"round":2\u002c"home":4\u002c"away":6\u002c"a":8\u002c"b":11}\u002c{"round":2\u002c"home":7\u002c"away":3\u002c"a":11\u002c"b":4}\u002c{"round":2\u002c"home":2\u002c"away":1\u002c"a":11\u002c"b":2}\u002c{"round":3\u002c"home":4\u002c"away":0\u002c"a":11\u002c"b":6}\u002c{"round":3\u002c"home":5\u002c"away":3\u002c"a":11\u002c"b":5}\u002c{"round":3\u002c"home":2\u002c"away":6\u002c"a":10\u002c"b":11}\u002c{"round":3\u002c"home":7\u002c"away":1\u002c"a":3\u002c"b":11}\u002c{"round":4\u002c"home":0\u002c"away":3\u002c"a":11\u002c"b":6}\u002c{"round":4\u002c"home":2\u002c"away":4\u002c"a":11\u002c"b":3}\u002c{"round":4\u002c"home":5\u002c"away":1\u002c"a":3\u002c"b":11}\u002c{"round":4\u002c"home":7\u002c"away":6\u002c"a":6\u002c"b":11}\u002c{"round":5\u002c"home":2\u002c"away":0\u002c"a":11\u002c"b":6}\u002c{"round":5\u002c"home":3\u002c"away":1\u002c"a":11\u002c"b":2}\u002c{"round":5\u002c"home":7\u002c"away":4\u002c"a":10\u002c"b":11}\u002c{"round":5\u002c"home":5\u002c"away":6\u002c"a":11\u002c"b":1}\u002c{"round":6\u002c"home":0\u002c"away":1\u002c"a":11\u002c"b":6}\u002c{"round":6\u002c"home":7\u002c"away":2\u002c"a":11\u002c"b":9}\u002c{"round":6\u002c"home":3\u002c"away":6\u002c"a":3\u002c"b":11}\u002c{"round":6\u002c"home":5\u002c"away":4\u002c"a":1\u002c"b":11}\u002c{"round":7\u002c"home":7\u002c"away":0\u002c"a":11\u002c"b":6}\u002c{"round":7\u002c"home":1\u002c"away":6\u002c"a":11\u002c"b":10}\u002c{"round":7\u002c"home":5\u002c"away":2\u002c"a":11\u002c"b":2}\u002c{"round":7\u002c"home":3\u002c"away":4\u002c"a":11\u002c"b":2}\u002c{"round":8\u002c"home":0\u002c"away":6\u002c"a":11\u002c"b":6}\u002c{"round":8\u002c"home":5\u002c"away":7\u002c"a":11\u002c"b":2}\u002c{"round":8\u002c"home":1\u002c"away":4\u002c"a":5\u002c"b":11}\u002c{"round":8\u002c"home":3\u002c"away":2\u002c"a":11\u002c"b":1}\u002c{"round":9\u002c"home":5\u002c"away":0\u002c"a":11\u002c"b":6}\u002c{"round":9\u002c"home":6\u002c"away":4\u002c"a":6\u002c"b":11}\u002c{"round":9\u002c"home":3\u002c"away":7\u002c"a":10\u002c"b":11}\u002c{"round":9\u002c"home":1\u002c"away":2\u002c"a":5\u002c"b":11}\u002c{"round":10\u002c"home":0\u002c"away":4\u002c"a":11\u002c"b":6}\u002c{"round":10\u002c"home":3\u002c"away":5\u002c"a":11\u002c"b":10}\u002c{"round":10\u002c"home":6\u002c"away":2\u002c"a":11\u002c"b":10}\u002c{"round":10\u002c"home":1\u002c"away":7\u002c"a":6\u002c"b":11}\u002c{"round":11\u002c"home":3\u002c"away":0\u002c"a":11\u002c"b":6}\u002c{"round":11\u002c"home":4\u002c"away":2\u002c"a":8\u002c"b":11}\u002c{"round":11\u002c"home":1\u002c"away":5\u002c"a":11\u002c"b":1}\u002c{"round":11\u002c"home":6\u002c"away":7\u002c"a":11\u002c"b":5}\u002c{"round":12\u002c"home":0\u002c"away":2\u002c"a":11\u002c"b":6}\u002c{"round":12\u002c"home":1\u002c"away":3\u002c"a":5\u002c"b":11}\u002c{"round":12\u002c"home":4\u002c"away":7\u002c"a":11\u002c"b":8}\u002c{"round":12\u002c"home":6\u002c"away":5\u002c"a":4\u002c"b":11}\u002c{"round":13\u002c"home":1\u002c"away":0\u002c"a":11\u002c"b":6}\u002c{"round":13\u002c"home":2\u002c"away":7\u002c"a":6\u002c"b":11}\u002c{"round":13\u002c"home":6\u002c"away":3\u002c"a":9\u002c"b":11}\u002c{"round":13\u002c"home":4\u002c"away":5\u002c"a":11\u002c"b":5}]}
SEASON_FINISHED|unit42|true|null
SEASON|unit42t120|id=s1;seed=42;number=1;created=1000;ms=120;teams=0:Team 0:-8988417:50:a+b/1:Team 1:-18567:51:a+b/2:Team 2:-3759873:52:a+b/3:Team 3:-8330051:53:a+b/4:Team 4:-26691:54:a+b/5:Team 5:-666001:55:a+b/6:Team 6:-8988417:56:a+b/7:Team 7:-18567:57:a+b
SEASON_REPAIRED|unit42t120|id=s1;seed=42;number=1;created=1000;ms=120;teams=0:Team 0:-8988417:50:a+b/1:Team 1:-18567:78:woman_dark+rooza/2:Team 2:-3759873:78:woman_dark+rooza/3:Team 3:-8330051:78:woman_dark+rooza/4:Team 4:-26691:78:woman_dark+rooza/5:Team 5:-666001:78:woman_dark+rooza/6:Team 6:-8988417:78:woman_dark+rooza/7:Team 7:-18567:78:woman_dark+rooza
SEASON_STEP|unit42t120|0|0-0-7|7|5|1|4|0-0-7=7-5 0-6-1=16-11 0-2-5=14-17 0-4-3=22-19
SEASON_STEP|unit42t120|1|1-6-0|2|9|2|8|1-6-0=9-2 1-7-5=17-8 1-4-1=17-19 1-2-3=22-12
SEASON_STEP|unit42t120|2|2-0-5|15|14|3|12|2-0-5=15-14 2-4-6=16-20 2-7-3=19-17 2-2-1=20-11
SEASON_STEP|unit42t120|3|3-4-0|7|5|4|16|3-4-0=5-7 3-5-3=20-14 3-2-6=10-20 3-7-1=19-20
SEASON_STEP|unit42t120|4|4-0-3|2|9|5|20|4-0-3=2-9 4-2-4=16-7 4-5-1=11-18 4-7-6=21-22
SEASON_STEP|unit42t120|5|5-2-0|15|14|6|24|5-2-0=14-15 5-3-1=16-7 5-7-4=17-18 5-5-6=21-11
SEASON_STEP|unit42t120|6|6-0-1|7|5|7|28|6-0-1=7-5 6-7-2=19-12 6-3-6=11-17 6-5-4=10-17
SEASON_STEP|unit42t120|7|7-7-0|2|9|8|32|7-7-0=9-2 7-1-6=18-9 7-5-2=22-21 7-3-4=16-11
SEASON_STEP|unit42t120|8|8-0-6|15|14|9|36|8-0-6=15-14 8-5-7=22-12 8-1-4=12-17 8-3-2=21-14
SEASON_STEP|unit42t120|9|9-5-0|7|5|10|40|9-5-0=5-7 9-6-4=10-19 9-3-7=13-17 9-1-2=14-16
SEASON_STEP|unit42t120|10|10-0-4|2|9|11|44|10-0-4=2-9 10-3-5=17-9 10-6-2=18-17 10-1-7=14-22
SEASON_STEP|unit42t120|11|11-3-0|15|14|12|48|11-3-0=14-15 11-4-2=14-16 11-1-5=18-17 11-6-7=18-17
SEASON_STEP|unit42t120|12|12-0-2|7|5|13|52|12-0-2=7-5 12-1-3=9-17 12-4-7=17-14 12-6-5=13-19
SEASON_STEP|unit42t120|13|13-1-0|2|9|14|56|13-1-0=9-2 13-2-7=14-17 13-6-3=11-19 13-4-5=18-16
SEASON_TABLE|unit42t120|0:14:9:105:126:27:-21 4:14:8:207:194:24:13 6:14:8:208:216:24:-8 7:14:7:225:204:21:21 3:14:7:215:195:21:20 5:14:6:211:212:18:-1 1:14:6:185:206:18:-21 2:14:5:211:214:15:-3
SEASON_FINISHED|unit42t120|true|null
SEASON|en2|id=3f0c2b8e-1d2a-4c5b-9e6f-7a8b9c0d1e2f;seed=1760600000000;number=1;created=1760600000000;ms=0;teams=0:Sky Comets:-18567:78:woman_dark+rooza/1:Golden Bolts:-8988417:78:unicorn_32+coach_67/2:Moon Dragons:-3759873:81:zephyr+buddy_23/3:Tidal Waves:-8330051:82:flare+ace_23/4:Fire Stars:-26691:85:nova+kyra/5:Night Wolves:-666001:84:zephyr+kyra_original/6:Rainbow Wings:-8988417:85:nova+flare/7:Sun Lions:-3759873:78:unicorn_32+buddy_23
SEASON_JSON0|en2|{"version":1\u002c"id":"3f0c2b8e-1d2a-4c5b-9e6f-7a8b9c0d1e2f"\u002c"seed":1760600000000\u002c"number":1\u002c"created":1760600000000\u002c"matchSeconds":0\u002c"teams":[{"id":0\u002c"name":"Sky Comets"\u002c"color":-18567\u002c"strength":78\u002c"roster":["woman_dark"\u002c"rooza"]}\u002c{"id":1\u002c"name":"Golden Bolts"\u002c"color":-8988417\u002c"strength":78\u002c"roster":["unicorn_32"\u002c"coach_67"]}\u002c{"id":2\u002c"name":"Moon Dragons"\u002c"color":-3759873\u002c"strength":81\u002c"roster":["zephyr"\u002c"buddy_23"]}\u002c{"id":3\u002c"name":"Tidal Waves"\u002c"color":-8330051\u002c"strength":82\u002c"roster":["flare"\u002c"ace_23"]}\u002c{"id":4\u002c"name":"Fire Stars"\u002c"color":-26691\u002c"strength":85\u002c"roster":["nova"\u002c"kyra"]}\u002c{"id":5\u002c"name":"Night Wolves"\u002c"color":-666001\u002c"strength":84\u002c"roster":["zephyr"\u002c"kyra_original"]}\u002c{"id":6\u002c"name":"Rainbow Wings"\u002c"color":-8988417\u002c"strength":85\u002c"roster":["nova"\u002c"flare"]}\u002c{"id":7\u002c"name":"Sun Lions"\u002c"color":-3759873\u002c"strength":78\u002c"roster":["unicorn_32"\u002c"buddy_23"]}]\u002c"results":[]}
SEASON_STEP|en2|0|0-0-7|11|0|1|4|0-0-7=11-0 0-6-1=7-11 0-2-5=11-10 0-4-3=11-2
SEASON_JSON1|en2|{"version":1\u002c"id":"3f0c2b8e-1d2a-4c5b-9e6f-7a8b9c0d1e2f"\u002c"seed":1760600000000\u002c"number":1\u002c"created":1760600000000\u002c"matchSeconds":0\u002c"teams":[{"id":0\u002c"name":"Sky Comets"\u002c"color":-18567\u002c"strength":78\u002c"roster":["woman_dark"\u002c"rooza"]}\u002c{"id":1\u002c"name":"Golden Bolts"\u002c"color":-8988417\u002c"strength":78\u002c"roster":["unicorn_32"\u002c"coach_67"]}\u002c{"id":2\u002c"name":"Moon Dragons"\u002c"color":-3759873\u002c"strength":81\u002c"roster":["zephyr"\u002c"buddy_23"]}\u002c{"id":3\u002c"name":"Tidal Waves"\u002c"color":-8330051\u002c"strength":82\u002c"roster":["flare"\u002c"ace_23"]}\u002c{"id":4\u002c"name":"Fire Stars"\u002c"color":-26691\u002c"strength":85\u002c"roster":["nova"\u002c"kyra"]}\u002c{"id":5\u002c"name":"Night Wolves"\u002c"color":-666001\u002c"strength":84\u002c"roster":["zephyr"\u002c"kyra_original"]}\u002c{"id":6\u002c"name":"Rainbow Wings"\u002c"color":-8988417\u002c"strength":85\u002c"roster":["nova"\u002c"flare"]}\u002c{"id":7\u002c"name":"Sun Lions"\u002c"color":-3759873\u002c"strength":78\u002c"roster":["unicorn_32"\u002c"buddy_23"]}]\u002c"results":[{"round":0\u002c"home":0\u002c"away":7\u002c"a":11\u002c"b":0}\u002c{"round":0\u002c"home":6\u002c"away":1\u002c"a":7\u002c"b":11}\u002c{"round":0\u002c"home":2\u002c"away":5\u002c"a":11\u002c"b":10}\u002c{"round":0\u002c"home":4\u002c"away":3\u002c"a":11\u002c"b":2}]}
SEASON_STEP|en2|1|1-6-0|7|11|2|8|1-6-0=11-7 1-7-5=10-11 1-4-1=11-2 1-2-3=3-11
SEASON_STEP|en2|2|2-0-5|12|9|3|12|2-0-5=12-9 2-4-6=9-11 2-7-3=4-11 2-2-1=11-10
SEASON_STEP|en2|3|3-4-0|10|13|4|16|3-4-0=13-10 3-5-3=11-5 3-2-6=2-11 3-7-1=11-8
SEASON_STEP|en2|4|4-0-3|11|9|5|20|4-0-3=11-9 4-2-4=5-11 4-5-1=11-9 4-7-6=11-9
SEASON_STEP|en2|5|5-2-0|2|11|6|24|5-2-0=11-2 5-3-1=11-3 5-7-4=4-11 5-5-6=4-11
SEASON_STEP|en2|6|6-0-1|12|9|7|28|6-0-1=12-9 6-7-2=11-7 6-3-6=11-4 6-5-4=8-11
SEASON_STEP|en2|7|7-7-0|10|13|8|32|7-7-0=13-10 7-1-6=11-4 7-5-2=11-8 7-3-4=11-3
SEASON_STEP|en2|8|8-0-6|11|7|9|36|8-0-6=11-7 8-5-7=11-10 8-1-4=6-11 8-3-2=7-11
SEASON_STEP|en2|9|9-5-0|8|11|10|40|9-5-0=11-8 9-6-4=1-11 9-3-7=9-11 9-1-2=11-5
SEASON_STEP|en2|10|10-0-4|12|9|11|44|10-0-4=12-9 10-3-5=1-11 10-6-2=2-11 10-1-7=2-11
SEASON_STEP|en2|11|11-3-0|10|13|12|48|11-3-0=13-10 11-4-2=5-11 11-1-5=11-2 11-6-7=1-11
SEASON_STEP|en2|12|12-0-2|11|5|13|52|12-0-2=11-5 12-1-3=11-7 12-4-7=11-1 12-6-5=11-9
SEASON_STEP|en2|13|13-1-0|3|11|14|56|13-1-0=11-3 13-2-7=3-11 13-6-3=11-4 13-4-5=7-11
SEASON_TABLE|en2|4:14:9:134:95:27:39 5:14:8:130:125:24:5 7:14:8:119:115:24:4 0:14:7:130:131:21:-1 1:14:6:115:117:18:-2 3:14:6:112:115:18:-3 2:14:6:104:124:18:-20 6:14:6:101:123:18:-22
SEASON_FINISHED|en2|true|null
SEASON|he3|id=aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee;seed=1760612345678;number=2;created=1760612345678;ms=0;teams=0:\u05e9\u05d1\u05d9\u05d8\u05d9 \u05d4\u05e9\u05de\u05d9\u05d9\u05dd:-8988417:81:woman_dark+rooza+nova/1:\u05d1\u05e8\u05e7\u05d9 \u05d4\u05d6\u05d4\u05d1:-18567:80:zephyr+ace_23+buddy_23/2:\u05d3\u05e8\u05e7\u05d5\u05e0\u05d9 \u05d4\u05d9\u05e8\u05d7:-3759873:84:kyra+kyra_original+flare/3:\u05d2\u05dc\u05d9 \u05d4\u05d8\u05d5\u05e8\u05e7\u05d9\u05d6:-8330051:80:unicorn_32+coach_67+flare/4:\u05db\u05d5\u05db\u05d1\u05d9 \u05d4\u05d0\u05e9:-26691:80:coach_67+kyra+buddy_23/5:\u05d6\u05d0\u05d1\u05d9 \u05d4\u05dc\u05d9\u05dc\u05d4:-666001:82:unicorn_32+zephyr+kyra_original/6:\u05db\u05e0\u05e4\u05d9 \u05d4\u05e7\u05e9\u05ea:-18567:80:coach_67+kyra_original+ace_23/7:\u05d0\u05e8\u05d9\u05d5\u05ea \u05d4\u05e9\u05de\u05e9:-3759873:81:unicorn_32+kyra+ace_23
SEASON_JSON0|he3|{"version":1\u002c"id":"aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"\u002c"seed":1760612345678\u002c"number":2\u002c"created":1760612345678\u002c"matchSeconds":0\u002c"teams":[{"id":0\u002c"name":"\u05e9\u05d1\u05d9\u05d8\u05d9 \u05d4\u05e9\u05de\u05d9\u05d9\u05dd"\u002c"color":-8988417\u002c"strength":81\u002c"roster":["woman_dark"\u002c"rooza"\u002c"nova"]}\u002c{"id":1\u002c"name":"\u05d1\u05e8\u05e7\u05d9 \u05d4\u05d6\u05d4\u05d1"\u002c"color":-18567\u002c"strength":80\u002c"roster":["zephyr"\u002c"ace_23"\u002c"buddy_23"]}\u002c{"id":2\u002c"name":"\u05d3\u05e8\u05e7\u05d5\u05e0\u05d9 \u05d4\u05d9\u05e8\u05d7"\u002c"color":-3759873\u002c"strength":84\u002c"roster":["kyra"\u002c"kyra_original"\u002c"flare"]}\u002c{"id":3\u002c"name":"\u05d2\u05dc\u05d9 \u05d4\u05d8\u05d5\u05e8\u05e7\u05d9\u05d6"\u002c"color":-8330051\u002c"strength":80\u002c"roster":["unicorn_32"\u002c"coach_67"\u002c"flare"]}\u002c{"id":4\u002c"name":"\u05db\u05d5\u05db\u05d1\u05d9 \u05d4\u05d0\u05e9"\u002c"color":-26691\u002c"strength":80\u002c"roster":["coach_67"\u002c"kyra"\u002c"buddy_23"]}\u002c{"id":5\u002c"name":"\u05d6\u05d0\u05d1\u05d9 \u05d4\u05dc\u05d9\u05dc\u05d4"\u002c"color":-666001\u002c"strength":82\u002c"roster":["unicorn_32"\u002c"zephyr"\u002c"kyra_original"]}\u002c{"id":6\u002c"name":"\u05db\u05e0\u05e4\u05d9 \u05d4\u05e7\u05e9\u05ea"\u002c"color":-18567\u002c"strength":80\u002c"roster":["coach_67"\u002c"kyra_original"\u002c"ace_23"]}\u002c{"id":7\u002c"name":"\u05d0\u05e8\u05d9\u05d5\u05ea \u05d4\u05e9\u05de\u05e9"\u002c"color":-3759873\u002c"strength":81\u002c"roster":["unicorn_32"\u002c"kyra"\u002c"ace_23"]}]\u002c"results":[]}
SEASON_STEP|he3|0|0-0-7|11|0|1|4|0-0-7=11-0 0-6-1=11-5 0-2-5=8-11 0-4-3=10-11
SEASON_STEP|he3|1|1-6-0|1|11|2|8|1-6-0=11-1 1-7-5=8-11 1-4-1=11-8 1-2-3=11-7
SEASON_STEP|he3|2|2-0-5|11|2|3|12|2-0-5=11-2 2-4-6=11-9 2-7-3=11-6 2-2-1=11-10
SEASON_STEP|he3|3|3-4-0|3|11|4|16|3-4-0=11-3 3-5-3=11-7 3-2-6=6-11 3-7-1=11-2
SEASON_STEP|he3|4|4-0-3|11|4|5|20|4-0-3=11-4 4-2-4=11-5 4-5-1=11-3 4-7-6=11-5
SEASON_STEP|he3|5|5-2-0|5|11|6|24|5-2-0=11-5 5-3-1=3-11 5-7-4=11-6 5-5-6=11-6
SEASON_STEP|he3|6|6-0-1|11|6|7|28|6-0-1=11-6 6-7-2=11-3 6-3-6=11-10 6-5-4=11-6
SEASON_STEP|he3|7|7-7-0|7|11|8|32|7-7-0=11-7 7-1-6=6-11 7-5-2=11-8 7-3-4=11-3
SEASON_STEP|he3|8|8-0-6|11|8|9|36|8-0-6=11-8 8-5-7=8-11 8-1-4=8-11 8-3-2=11-5
SEASON_STEP|he3|9|9-5-0|9|11|10|40|9-5-0=11-9 9-6-4=9-11 9-3-7=3-11 9-1-2=5-11
SEASON_STEP|he3|10|10-0-4|11|10|11|44|10-0-4=11-10 10-3-5=3-11 10-6-2=4-11 10-1-7=2-11
SEASON_STEP|he3|11|11-3-0|1|11|12|48|11-3-0=11-1 11-4-2=5-11 11-1-5=11-8 11-6-7=11-1
SEASON_STEP|he3|12|12-0-2|11|1|13|52|12-0-2=11-1 12-1-3=11-3 12-4-7=5-11 12-6-5=11-1
SEASON_STEP|he3|13|13-1-0|3|11|14|56|13-1-0=11-3 13-2-7=11-9 13-6-3=2-11 13-4-5=11-7
SEASON_TABLE|he3|7:14:10:128:91:30:37 5:14:9:125:113:27:12 2:14:8:119:116:24:3 0:14:7:106:108:21:-2 6:14:6:119:108:18:11 4:14:6:116:132:18:-16 3:14:6:102:119:18:-17 1:14:4:99:127:12:-28
SEASON_JSON|he3|{"version":1\u002c"id":"aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"\u002c"seed":1760612345678\u002c"number":2\u002c"created":1760612345678\u002c"matchSeconds":0\u002c"teams":[{"id":0\u002c"name":"\u05e9\u05d1\u05d9\u05d8\u05d9 \u05d4\u05e9\u05de\u05d9\u05d9\u05dd"\u002c"color":-8988417\u002c"strength":81\u002c"roster":["woman_dark"\u002c"rooza"\u002c"nova"]}\u002c{"id":1\u002c"name":"\u05d1\u05e8\u05e7\u05d9 \u05d4\u05d6\u05d4\u05d1"\u002c"color":-18567\u002c"strength":80\u002c"roster":["zephyr"\u002c"ace_23"\u002c"buddy_23"]}\u002c{"id":2\u002c"name":"\u05d3\u05e8\u05e7\u05d5\u05e0\u05d9 \u05d4\u05d9\u05e8\u05d7"\u002c"color":-3759873\u002c"strength":84\u002c"roster":["kyra"\u002c"kyra_original"\u002c"flare"]}\u002c{"id":3\u002c"name":"\u05d2\u05dc\u05d9 \u05d4\u05d8\u05d5\u05e8\u05e7\u05d9\u05d6"\u002c"color":-8330051\u002c"strength":80\u002c"roster":["unicorn_32"\u002c"coach_67"\u002c"flare"]}\u002c{"id":4\u002c"name":"\u05db\u05d5\u05db\u05d1\u05d9 \u05d4\u05d0\u05e9"\u002c"color":-26691\u002c"strength":80\u002c"roster":["coach_67"\u002c"kyra"\u002c"buddy_23"]}\u002c{"id":5\u002c"name":"\u05d6\u05d0\u05d1\u05d9 \u05d4\u05dc\u05d9\u05dc\u05d4"\u002c"color":-666001\u002c"strength":82\u002c"roster":["unicorn_32"\u002c"zephyr"\u002c"kyra_original"]}\u002c{"id":6\u002c"name":"\u05db\u05e0\u05e4\u05d9 \u05d4\u05e7\u05e9\u05ea"\u002c"color":-18567\u002c"strength":80\u002c"roster":["coach_67"\u002c"kyra_original"\u002c"ace_23"]}\u002c{"id":7\u002c"name":"\u05d0\u05e8\u05d9\u05d5\u05ea \u05d4\u05e9\u05de\u05e9"\u002c"color":-3759873\u002c"strength":81\u002c"roster":["unicorn_32"\u002c"kyra"\u002c"ace_23"]}]\u002c"results":[{"round":0\u002c"home":0\u002c"away":7\u002c"a":11\u002c"b":0}\u002c{"round":0\u002c"home":6\u002c"away":1\u002c"a":11\u002c"b":5}\u002c{"round":0\u002c"home":2\u002c"away":5\u002c"a":8\u002c"b":11}\u002c{"round":0\u002c"home":4\u002c"away":3\u002c"a":10\u002c"b":11}\u002c{"round":1\u002c"home":6\u002c"away":0\u002c"a":11\u002c"b":1}\u002c{"round":1\u002c"home":7\u002c"away":5\u002c"a":8\u002c"b":11}\u002c{"round":1\u002c"home":4\u002c"away":1\u002c"a":11\u002c"b":8}\u002c{"round":1\u002c"home":2\u002c"away":3\u002c"a":11\u002c"b":7}\u002c{"round":2\u002c"home":0\u002c"away":5\u002c"a":11\u002c"b":2}\u002c{"round":2\u002c"home":4\u002c"away":6\u002c"a":11\u002c"b":9}\u002c{"round":2\u002c"home":7\u002c"away":3\u002c"a":11\u002c"b":6}\u002c{"round":2\u002c"home":2\u002c"away":1\u002c"a":11\u002c"b":10}\u002c{"round":3\u002c"home":4\u002c"away":0\u002c"a":11\u002c"b":3}\u002c{"round":3\u002c"home":5\u002c"away":3\u002c"a":11\u002c"b":7}\u002c{"round":3\u002c"home":2\u002c"away":6\u002c"a":6\u002c"b":11}\u002c{"round":3\u002c"home":7\u002c"away":1\u002c"a":11\u002c"b":2}\u002c{"round":4\u002c"home":0\u002c"away":3\u002c"a":11\u002c"b":4}\u002c{"round":4\u002c"home":2\u002c"away":4\u002c"a":11\u002c"b":5}\u002c{"round":4\u002c"home":5\u002c"away":1\u002c"a":11\u002c"b":3}\u002c{"round":4\u002c"home":7\u002c"away":6\u002c"a":11\u002c"b":5}\u002c{"round":5\u002c"home":2\u002c"away":0\u002c"a":11\u002c"b":5}\u002c{"round":5\u002c"home":3\u002c"away":1\u002c"a":3\u002c"b":11}\u002c{"round":5\u002c"home":7\u002c"away":4\u002c"a":11\u002c"b":6}\u002c{"round":5\u002c"home":5\u002c"away":6\u002c"a":11\u002c"b":6}\u002c{"round":6\u002c"home":0\u002c"away":1\u002c"a":11\u002c"b":6}\u002c{"round":6\u002c"home":7\u002c"away":2\u002c"a":11\u002c"b":3}\u002c{"round":6\u002c"home":3\u002c"away":6\u002c"a":11\u002c"b":10}\u002c{"round":6\u002c"home":5\u002c"away":4\u002c"a":11\u002c"b":6}\u002c{"round":7\u002c"home":7\u002c"away":0\u002c"a":11\u002c"b":7}\u002c{"round":7\u002c"home":1\u002c"away":6\u002c"a":6\u002c"b":11}\u002c{"round":7\u002c"home":5\u002c"away":2\u002c"a":11\u002c"b":8}\u002c{"round":7\u002c"home":3\u002c"away":4\u002c"a":11\u002c"b":3}\u002c{"round":8\u002c"home":0\u002c"away":6\u002c"a":11\u002c"b":8}\u002c{"round":8\u002c"home":5\u002c"away":7\u002c"a":8\u002c"b":11}\u002c{"round":8\u002c"home":1\u002c"away":4\u002c"a":8\u002c"b":11}\u002c{"round":8\u002c"home":3\u002c"away":2\u002c"a":11\u002c"b":5}\u002c{"round":9\u002c"home":5\u002c"away":0\u002c"a":11\u002c"b":9}\u002c{"round":9\u002c"home":6\u002c"away":4\u002c"a":9\u002c"b":11}\u002c{"round":9\u002c"home":3\u002c"away":7\u002c"a":3\u002c"b":11}\u002c{"round":9\u002c"home":1\u002c"away":2\u002c"a":5\u002c"b":11}\u002c{"round":10\u002c"home":0\u002c"away":4\u002c"a":11\u002c"b":10}\u002c{"round":10\u002c"home":3\u002c"away":5\u002c"a":3\u002c"b":11}\u002c{"round":10\u002c"home":6\u002c"away":2\u002c"a":4\u002c"b":11}\u002c{"round":10\u002c"home":1\u002c"away":7\u002c"a":2\u002c"b":11}\u002c{"round":11\u002c"home":3\u002c"away":0\u002c"a":11\u002c"b":1}\u002c{"round":11\u002c"home":4\u002c"away":2\u002c"a":5\u002c"b":11}\u002c{"round":11\u002c"home":1\u002c"away":5\u002c"a":11\u002c"b":8}\u002c{"round":11\u002c"home":6\u002c"away":7\u002c"a":11\u002c"b":1}\u002c{"round":12\u002c"home":0\u002c"away":2\u002c"a":11\u002c"b":1}\u002c{"round":12\u002c"home":1\u002c"away":3\u002c"a":11\u002c"b":3}\u002c{"round":12\u002c"home":4\u002c"away":7\u002c"a":5\u002c"b":11}\u002c{"round":12\u002c"home":6\u002c"away":5\u002c"a":11\u002c"b":1}\u002c{"round":13\u002c"home":1\u002c"away":0\u002c"a":11\u002c"b":3}\u002c{"round":13\u002c"home":2\u002c"away":7\u002c"a":11\u002c"b":9}\u002c{"round":13\u002c"home":6\u002c"away":3\u002c"a":2\u002c"b":11}\u002c{"round":13\u002c"home":4\u002c"away":5\u002c"a":11\u002c"b":7}]}
SEASON_FINISHED|he3|true|null
SEASON|t120|id=timed-120;seed=1760600001234;number=3;created=1760600001234;ms=120;teams=0:Night\u002fOwls "A":-666001:81:kyra_original+buddy_23/1:Golden Bolts:-8988417:79:unicorn_32+ace_23/2:Moon Dragons:-18567:85:nova+zephyr/3:Tidal Waves:-3759873:78:woman_dark+rooza/4:Fire Stars:-8330051:81:coach_67+flare/5:Night Wolves:-26691:82:rooza+kyra/6:Rainbow Wings:-8988417:81:unicorn_32+kyra/7:Sun Lions:-18567:77:woman_dark+coach_67
SEASON_JSON0|t120|{"version":1\u002c"id":"timed-120"\u002c"seed":1760600001234\u002c"number":3\u002c"created":1760600001234\u002c"matchSeconds":120\u002c"teams":[{"id":0\u002c"name":"Night\u005c/Owls \u005c"A\u005c""\u002c"color":-666001\u002c"strength":81\u002c"roster":["kyra_original"\u002c"buddy_23"]}\u002c{"id":1\u002c"name":"Golden Bolts"\u002c"color":-8988417\u002c"strength":79\u002c"roster":["unicorn_32"\u002c"ace_23"]}\u002c{"id":2\u002c"name":"Moon Dragons"\u002c"color":-18567\u002c"strength":85\u002c"roster":["nova"\u002c"zephyr"]}\u002c{"id":3\u002c"name":"Tidal Waves"\u002c"color":-3759873\u002c"strength":78\u002c"roster":["woman_dark"\u002c"rooza"]}\u002c{"id":4\u002c"name":"Fire Stars"\u002c"color":-8330051\u002c"strength":81\u002c"roster":["coach_67"\u002c"flare"]}\u002c{"id":5\u002c"name":"Night Wolves"\u002c"color":-26691\u002c"strength":82\u002c"roster":["rooza"\u002c"kyra"]}\u002c{"id":6\u002c"name":"Rainbow Wings"\u002c"color":-8988417\u002c"strength":81\u002c"roster":["unicorn_32"\u002c"kyra"]}\u002c{"id":7\u002c"name":"Sun Lions"\u002c"color":-18567\u002c"strength":77\u002c"roster":["woman_dark"\u002c"coach_67"]}]\u002c"results":[]}
SEASON_STEP|t120|0|0-0-7|3|1|1|4|0-0-7=3-1 0-6-1=20-22 0-2-5=15-20 0-4-3=22-17
SEASON_JSON1|t120|{"version":1\u002c"id":"timed-120"\u002c"seed":1760600001234\u002c"number":3\u002c"created":1760600001234\u002c"matchSeconds":120\u002c"teams":[{"id":0\u002c"name":"Night\u005c/Owls \u005c"A\u005c""\u002c"color":-666001\u002c"strength":81\u002c"roster":["kyra_original"\u002c"buddy_23"]}\u002c{"id":1\u002c"name":"Golden Bolts"\u002c"color":-8988417\u002c"strength":79\u002c"roster":["unicorn_32"\u002c"ace_23"]}\u002c{"id":2\u002c"name":"Moon Dragons"\u002c"color":-18567\u002c"strength":85\u002c"roster":["nova"\u002c"zephyr"]}\u002c{"id":3\u002c"name":"Tidal Waves"\u002c"color":-3759873\u002c"strength":78\u002c"roster":["woman_dark"\u002c"rooza"]}\u002c{"id":4\u002c"name":"Fire Stars"\u002c"color":-8330051\u002c"strength":81\u002c"roster":["coach_67"\u002c"flare"]}\u002c{"id":5\u002c"name":"Night Wolves"\u002c"color":-26691\u002c"strength":82\u002c"roster":["rooza"\u002c"kyra"]}\u002c{"id":6\u002c"name":"Rainbow Wings"\u002c"color":-8988417\u002c"strength":81\u002c"roster":["unicorn_32"\u002c"kyra"]}\u002c{"id":7\u002c"name":"Sun Lions"\u002c"color":-18567\u002c"strength":77\u002c"roster":["woman_dark"\u002c"coach_67"]}]\u002c"results":[{"round":0\u002c"home":0\u002c"away":7\u002c"a":3\u002c"b":1}\u002c{"round":0\u002c"home":6\u002c"away":1\u002c"a":20\u002c"b":22}\u002c{"round":0\u002c"home":2\u002c"away":5\u002c"a":15\u002c"b":20}\u002c{"round":0\u002c"home":4\u002c"away":3\u002c"a":22\u002c"b":17}]}
SEASON_STEP|t120|1|1-6-0|0|1|2|8|1-6-0=1-0 1-7-5=11-18 1-4-1=21-16 1-2-3=22-20
SEASON_STEP|t120|2|2-0-5|5|3|3|12|2-0-5=5-3 2-4-6=9-16 2-7-3=17-14 2-2-1=16-6
SEASON_STEP|t120|3|3-4-0|0|1|4|16|3-4-0=1-0 3-5-3=16-22 3-2-6=16-17 3-7-1=21-13
SEASON_STEP|t120|4|4-0-3|7|5|5|20|4-0-3=7-5 4-2-4=16-17 4-5-1=18-19 4-7-6=12-21
SEASON_STEP|t120|5|5-2-0|0|1|6|24|5-2-0=1-0 5-3-1=11-17 5-7-4=18-19 5-5-6=18-10
SEASON_STEP|t120|6|6-0-1|9|7|7|28|6-0-1=9-7 6-7-2=14-22 6-3-6=21-18 6-5-4=21-18
SEASON_STEP|t120|7|7-7-0|0|1|8|32|7-7-0=1-0 7-1-6=9-19 7-5-2=22-19 7-3-4=21-13
SEASON_STEP|t120|8|8-0-6|11|9|9|36|8-0-6=11-9 8-5-7=6-16 8-1-4=21-11 8-3-2=17-10
SEASON_STEP|t120|9|9-5-0|0|1|10|40|9-5-0=1-0 9-6-4=16-11 9-3-7=17-19 9-1-2=17-20
SEASON_STEP|t120|10|10-0-4|13|11|11|44|10-0-4=13-11 10-3-5=18-8 10-6-2=17-12 10-1-7=19-16
SEASON_STEP|t120|11|11-3-0|0|1|12|48|11-3-0=1-0 11-4-2=20-12 11-1-5=15-21 11-6-7=7-16
SEASON_STEP|t120|12|12-0-2|15|13|13|52|12-0-2=15-13 12-1-3=22-20 12-4-7=21-20 12-6-5=18-15
SEASON_STEP|t120|13|13-1-0|0|1|14|56|13-1-0=1-0 13-2-7=12-18 13-6-3=19-21 13-4-5=18-11
SEASON_TABLE|t120|6:14:8:208:193:24:15 4:14:8:212:218:24:-6 3:14:7:225:210:21:15 7:14:7:200:192:21:8 0:14:7:63:56:21:7 5:14:7:198:204:21:-6 1:14:7:204:223:21:-19 2:14:5:206:220:15:-14
SEASON_FINISHED|t120|true|null
SEASON|t180|id=timed-180;seed=1760600005678;number=3;created=1760600005678;ms=180;teams=0:Night\u002fOwls "A":-666001:81:kyra_original+buddy_23/1:Golden Bolts:-8988417:81:unicorn_32+zephyr/2:Moon Dragons:-18567:82:kyra+ace_23/3:Tidal Waves:-3759873:82:nova+coach_67/4:Fire Stars:-8330051:78:woman_dark+rooza/5:Night Wolves:-26691:80:woman_dark+flare/6:Rainbow Wings:-8988417:84:zephyr+flare/7:Sun Lions:-18567:78:unicorn_32+coach_67
SEASON_STEP|t180|0|0-0-7|3|1|1|4|0-0-7=3-1 0-6-1=19-27 0-2-5=28-25 0-4-3=25-26
SEASON_STEP|t180|1|1-6-0|0|1|2|8|1-6-0=1-0 1-7-5=21-24 1-4-1=16-23 1-2-3=22-28
SEASON_STEP|t180|2|2-0-5|5|3|3|12|2-0-5=5-3 2-4-6=18-23 2-7-3=29-20 2-2-1=22-24
SEASON_STEP|t180|3|3-4-0|0|1|4|16|3-4-0=1-0 3-5-3=28-20 3-2-6=21-28 3-7-1=29-27
SEASON_STEP|t180|4|4-0-3|7|5|5|20|4-0-3=7-5 4-2-4=23-26 4-5-1=20-29 4-7-6=18-27
SEASON_STEP|t180|5|5-2-0|0|1|6|24|5-2-0=1-0 5-3-1=24-28 5-7-4=27-20 5-5-6=22-24
SEASON_STEP|t180|6|6-0-1|9|7|7|28|6-0-1=9-7 6-7-2=16-26 6-3-6=20-27 6-5-4=24-19
SEASON_STEP|t180|7|7-7-0|0|1|8|32|7-7-0=1-0 7-1-6=29-23 7-5-2=29-22 7-3-4=25-23
SEASON_STEP|t180|8|8-0-6|11|9|9|36|8-0-6=11-9 8-5-7=24-22 8-1-4=29-25 8-3-2=26-21
SEASON_STEP|t180|9|9-5-0|0|1|10|40|9-5-0=1-0 9-6-4=17-24 9-3-7=23-21 9-1-2=16-23
SEASON_STEP|t180|10|10-0-4|13|11|11|44|10-0-4=13-11 10-3-5=24-14 10-6-2=18-27 10-1-7=25-16
SEASON_STEP|t180|11|11-3-0|0|1|12|48|11-3-0=1-0 11-4-2=26-16 11-1-5=19-29 11-6-7=21-24
SEASON_STEP|t180|12|12-0-2|15|13|13|52|12-0-2=15-13 12-1-3=23-29 12-4-7=28-19 12-6-5=24-15
SEASON_STEP|t180|13|13-1-0|0|1|14|56|13-1-0=1-0 13-2-7=24-14 13-6-3=23-19 13-4-5=28-29
SEASON_TABLE|t180|1:14:9:307:284:27:23 6:14:8:284:275:24:9 5:14:8:287:285:24:2 3:14:8:290:291:24:-1 0:14:7:63:56:21:7 2:14:6:289:291:18:-2 4:14:5:290:294:15:-4 7:14:5:258:292:15:-34
SEASON_FINISHED|t180|true|null
SEASON|t300|id=timed-300;seed=1760600009999;number=3;created=1760600009999;ms=300;teams=0:Night\u002fOwls "A":-666001:81:kyra_original+buddy_23/1:Golden Bolts:-8988417:85:nova+flare/2:Moon Dragons:-18567:78:woman_dark+ace_23/3:Tidal Waves:-3759873:78:unicorn_32+coach_67/4:Fire Stars:-8330051:84:zephyr+kyra/5:Night Wolves:-26691:83:rooza+nova/6:Rainbow Wings:-8988417:80:woman_dark+kyra/7:Sun Lions:-18567:82:rooza+zephyr
SEASON_STEP|t300|0|0-0-7|3|1|1|4|0-0-7=3-1 0-6-1=27-36 0-2-5=36-32 0-4-3=34-38
SEASON_STEP|t300|1|1-6-0|0|1|2|8|1-6-0=1-0 1-7-5=26-36 1-4-1=36-28 1-2-3=31-36
SEASON_STEP|t300|2|2-0-5|5|3|3|12|2-0-5=5-3 2-4-6=42-38 2-7-3=31-37 2-2-1=37-36
SEASON_STEP|t300|3|3-4-0|0|1|4|16|3-4-0=1-0 3-5-3=34-41 3-2-6=34-40 3-7-1=36-29
SEASON_STEP|t300|4|4-0-3|7|5|5|20|4-0-3=7-5 4-2-4=27-37 4-5-1=33-41 4-7-6=34-42
SEASON_STEP|t300|5|5-2-0|0|1|6|24|5-2-0=1-0 5-3-1=39-34 5-7-4=41-35 5-5-6=31-36
SEASON_STEP|t300|6|6-0-1|9|7|7|28|6-0-1=9-7 6-7-2=35-36 6-3-6=37-31 6-5-4=40-32
SEASON_STEP|t300|7|7-7-0|0|1|8|32|7-7-0=1-0 7-1-6=30-39 7-5-2=35-37 7-3-4=31-40
SEASON_STEP|t300|8|8-0-6|11|9|9|36|8-0-6=11-9 8-5-7=38-41 8-1-4=41-38 8-3-2=32-38
SEASON_STEP|t300|9|9-5-0|0|1|10|40|9-5-0=1-0 9-6-4=31-41 9-3-7=36-31 9-1-2=33-41
SEASON_STEP|t300|10|10-0-4|13|11|11|44|10-0-4=13-11 10-3-5=42-41 10-6-2=36-38 10-1-7=36-38
SEASON_STEP|t300|11|11-3-0|0|1|12|48|11-3-0=1-0 11-4-2=42-35 11-1-5=38-33 11-6-7=35-41
SEASON_STEP|t300|12|12-0-2|15|13|13|52|12-0-2=15-13 12-1-3=40-31 12-4-7=38-34 12-6-5=41-37
SEASON_STEP|t300|13|13-1-0|0|1|14|56|13-1-0=1-0 13-2-7=38-31 13-6-3=36-29 13-4-5=38-42
SEASON_TABLE|t300|3:14:9:435:428:27:7 2:14:9:442:440:27:2 4:14:8:465:439:24:26 0:14:7:63:56:21:7 6:14:7:442:441:21:1 1:14:6:430:437:18:-7 7:14:6:421:439:18:-18 5:14:4:436:454:12:-18
SEASON_FINISHED|t300|true|null
CLEAN|  \u05de\u05d9\u05e0\u05d9\u05e7\u000a\u202e  |\u05de\u05d9\u05e0\u05d9\u05e7|5
CLEAN|aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa|aaaaaaaaaaaaaaaaaaaaaaaa|24
CLEAN|\u2066Team\u2069 A|Team A|6
CLEAN|Tab\u0009Name|TabName|7
CLEAN|   ||0
CLEAN|Sky Comets|Sky Comets|10
CLEAN|\u00a0\u00a0Sky\u00a0|Sky|3
CLEAN|\u3000\u540d\u3000|\u540d|1
CLEAN|\u200bZW\u200b|\u200bZW\u200b|4
CLEAN|\ufeffBOM|\ufeffBOM|4
CLEAN|\u0085NEL\u0085|NEL|3
CLEAN|\u2028L\u2029|L|1
CLEAN|\u202aA\u202bB\u202cC\u202dD\u202eE|ABCDE|5
CLEAN|\u200fRLM\u200e|\u200fRLM\u200e|5
CLEAN|xxxxxxxxxxxxxxxxxxxxxxx\ud83d\ude00|xxxxxxxxxxxxxxxxxxxxxxx\ud83d|24
CLEAN|xxxxxxxxxxxxxxxxxxxxxx\ud83d\ude00z|xxxxxxxxxxxxxxxxxxxxxx\ud83d\ude00|24
CLEAN| \u0301abc |\u0301abc|4
CLEAN|a\u0000b\u001fc\u007fd\u009fe|abcde|5
CLEAN|\u1680ogham\u2007\u202f\u205f|ogham|5
CLEAN|  Night/Owls "A"  |Night/Owls "A"|14
CLEAN|\u2009\u200a\u2000\u2001X\u2002\u2003\u2004\u2005\u2006\u2008|X|1
CLEAN|1234567890123456789012345|123456789012345678901234|24
CLEAN|\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00|\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00|24
CLEAN|||0
CLEAN|\u0009\u000b\u000c\u001c\u001d\u001e\u001fA|A|1
STAGE|0|move|Find your feet|\u05de\u05ea\u05d7\u05d9\u05dc\u05d9\u05dd \u05dc\u05d6\u05d5\u05d6|MOVEx8|2|true|true
STAGE|1|pass|A pass that arrives|\u05de\u05e1\u05d9\u05e8\u05d4 \u05e9\u05de\u05d2\u05d9\u05e2\u05d4|PASSx2|2|true|true
STAGE|2|release|Feel the release|\u05de\u05e8\u05d2\u05d9\u05e9\u05d9\u05dd \u05d0\u05ea \u05d4\u05e9\u05d7\u05e8\u05d5\u05e8|RELEASEx3|2|true|true
STAGE|3|basket|First baskets|\u05d4\u05e1\u05dc\u05d9\u05dd \u05d4\u05e8\u05d0\u05e9\u05d5\u05e0\u05d9\u05dd|BASKETx2|2|true|true
STAGE|4|switch|Choose your defender|\u05d1\u05d5\u05d7\u05e8\u05d9\u05dd \u05d0\u05ea \u05d4\u05e9\u05d5\u05de\u05e8|SWITCHx3|2|true|false
STAGE|5|steal|Close enough to reach|\u05de\u05ea\u05e7\u05e8\u05d1\u05d9\u05dd \u05d5\u05d7\u05d5\u05d8\u05e4\u05d9\u05dd|STEALx1|2|true|false
STAGE|6|screen|Make a little space|\u05de\u05e4\u05e0\u05d9\u05dd \u05e7\u05e6\u05ea \u05de\u05e7\u05d5\u05dd|SCREENx1|2|false|true
STAGE|7|alley|A pass above the rim|\u05de\u05e1\u05d9\u05e8\u05d4 \u05de\u05e2\u05dc \u05d4\u05d8\u05d1\u05e2\u05ea|ALLEYx1|2|false|true
STAGE|8|move_pass|Move\u002c then share|\u05d6\u05d6\u05d9\u05dd \u05d5\u05d0\u05d6 \u05de\u05d5\u05e1\u05e8\u05d9\u05dd|MOVEx10,PASSx3|2|false|true
STAGE|9|shoot|Find your shooting rhythm|\u05de\u05d5\u05e6\u05d0\u05d9\u05dd \u05e7\u05e6\u05d1 \u05e7\u05dc\u05d9\u05e2\u05d4|RELEASEx4,BASKETx2|2|false|true
STAGE|10|defend|Read the ball|\u05e7\u05d5\u05e8\u05d0\u05d9\u05dd \u05d0\u05ea \u05d4\u05db\u05d3\u05d5\u05e8|SWITCHx2,STEALx2|2|false|false
STAGE|11|screen_pass|Space for a teammate|\u05de\u05e7\u05d5\u05dd \u05dc\u05d7\u05d1\u05e8 \u05d4\u05e7\u05d1\u05d5\u05e6\u05d4|SCREENx2,PASSx3|2|false|true
STAGE|12|alley_twice|Flying partnership|\u05e9\u05d5\u05ea\u05e4\u05d5\u05ea \u05d1\u05d0\u05d5\u05d5\u05d9\u05e8|ALLEYx2|2|false|true
STAGE|13|three_pass|Three players\u002c one ball|\u05e9\u05dc\u05d5\u05e9\u05d4 \u05e9\u05d7\u05e7\u05e0\u05d9\u05dd\u002c \u05db\u05d3\u05d5\u05e8 \u05d0\u05d7\u05d3|PASSx5|3|false|true
STAGE|14|three_move|Keep the team moving|\u05d4\u05e7\u05d1\u05d5\u05e6\u05d4 \u05d1\u05ea\u05e0\u05d5\u05e2\u05d4|MOVEx15,PASSx4|3|false|true
STAGE|15|three_screen|Open the lane|\u05e4\u05d5\u05ea\u05d7\u05d9\u05dd \u05e0\u05ea\u05d9\u05d1|SCREENx2,BASKETx2|3|false|true
STAGE|16|three_defend|Stay with the play|\u05e0\u05e9\u05d0\u05e8\u05d9\u05dd \u05d1\u05de\u05d4\u05dc\u05da|SWITCHx3,STEALx2|3|false|false
STAGE|17|three_shoot|Calm hands|\u05d9\u05d3\u05d9\u05d9\u05dd \u05e8\u05d2\u05d5\u05e2\u05d5\u05ea|RELEASEx5,BASKETx3|3|false|true
STAGE|18|three_alley|Above and beyond|\u05e2\u05d5\u05dc\u05d9\u05dd \u05d9\u05d7\u05d3|PASSx4,ALLEYx2|3|false|true
STAGE|19|final|Team all-rounder|\u05d0\u05dc\u05d5\u05e4\u05d9 \u05d4\u05de\u05e9\u05d7\u05e7 \u05d4\u05e7\u05d1\u05d5\u05e6\u05ea\u05d9|MOVEx12,PASSx4,BASKETx3|3|false|true
STAGE|20|cross|Change hands|\u05de\u05d7\u05dc\u05d9\u05e4\u05d9\u05dd \u05d9\u05d3\u05d9\u05d9\u05dd|CROSSOVERx2|2|true|true
STAGE|21|behind_back|Behind the back|\u05de\u05d0\u05d7\u05d5\u05e8\u05d9 \u05d4\u05d2\u05d1|BEHIND_BACKx2|2|true|true
STAGE|22|spin|Turn into space|\u05e1\u05d9\u05d1\u05d5\u05d1 \u05d0\u05dc \u05d4\u05e9\u05d8\u05d7 \u05d4\u05e4\u05e0\u05d5\u05d9|SPINx3|2|false|true
QUAL|move|bob=314/376,woman_dark=435/453,rooza=465/491,nova=449/531,unicorn_32=341/454,coach_67=321/439,zephyr=431/523,kyra=431/523,kyra_original=431/523,flare=441/495,ace_23=462/468,buddy_23=462/477
QUAL|pass|bob=318/298,woman_dark=439/375,rooza=470/429,nova=444/423,unicorn_32=305/283,coach_67=314/299,zephyr=429/433,kyra=429/433,kyra_original=429/433,flare=432/388,ace_23=462/404,buddy_23=470/437
QUAL|release|bob=310/334,woman_dark=439/354,rooza=464/361,nova=446/501,unicorn_32=337/536,coach_67=330/516,zephyr=427/494,kyra=427/494,kyra_original=427/494,flare=440/473,ace_23=464/370,buddy_23=460/327
QUAL|basket|bob=310/334,woman_dark=439/354,rooza=464/361,nova=446/501,unicorn_32=337/536,coach_67=330/516,zephyr=427/494,kyra=427/494,kyra_original=427/494,flare=440/473,ace_23=464/370,buddy_23=460/327
QUAL|switch|bob=300/326,woman_dark=356/435,rooza=387/474,nova=431/446,unicorn_32=380/293,coach_67=386/297,zephyr=430/434,kyra=430/434,kyra_original=430/434,flare=399/429,ace_23=367/459,buddy_23=374/477
QUAL|steal|bob=300/326,woman_dark=356/435,rooza=387/474,nova=431/446,unicorn_32=380/293,coach_67=386/297,zephyr=430/434,kyra=430/434,kyra_original=430/434,flare=399/429,ace_23=367/459,buddy_23=374/477
QUAL|screen|bob=291/308,woman_dark=361/369,rooza=362/396,nova=426/440,unicorn_32=413/392,coach_67=413/384,zephyr=402/434,kyra=402/434,kyra_original=402/434,flare=447/408,ace_23=384/378,buddy_23=332/381
QUAL|alley|bob=344/338,woman_dark=462/366,rooza=539/389,nova=543/507,unicorn_32=468/523,coach_67=431/495,zephyr=559/505,kyra=559/505,kyra_original=559/505,flare=554/487,ace_23=524/395,buddy_23=510/363
QUAL|move_pass|bob=314/376,woman_dark=435/453,rooza=465/491,nova=449/531,unicorn_32=341/454,coach_67=321/439,zephyr=431/523,kyra=431/523,kyra_original=431/523,flare=441/495,ace_23=462/468,buddy_23=462/477
QUAL|shoot|bob=310/334,woman_dark=439/354,rooza=464/361,nova=446/501,unicorn_32=337/536,coach_67=330/516,zephyr=427/494,kyra=427/494,kyra_original=427/494,flare=440/473,ace_23=464/370,buddy_23=460/327
QUAL|defend|bob=300/326,woman_dark=356/435,rooza=387/474,nova=431/446,unicorn_32=380/293,coach_67=386/297,zephyr=430/434,kyra=430/434,kyra_original=430/434,flare=399/429,ace_23=367/459,buddy_23=374/477
QUAL|screen_pass|bob=291/308,woman_dark=361/369,rooza=362/396,nova=426/440,unicorn_32=413/392,coach_67=413/384,zephyr=402/434,kyra=402/434,kyra_original=402/434,flare=447/408,ace_23=384/378,buddy_23=332/381
QUAL|alley_twice|bob=344/338,woman_dark=462/366,rooza=539/389,nova=543/507,unicorn_32=468/523,coach_67=431/495,zephyr=559/505,kyra=559/505,kyra_original=559/505,flare=554/487,ace_23=524/395,buddy_23=510/363
QUAL|three_pass|bob=318/298,woman_dark=439/375,rooza=470/429,nova=444/423,unicorn_32=305/283,coach_67=314/299,zephyr=429/433,kyra=429/433,kyra_original=429/433,flare=432/388,ace_23=462/404,buddy_23=470/437
QUAL|three_move|bob=314/376,woman_dark=435/453,rooza=465/491,nova=449/531,unicorn_32=341/454,coach_67=321/439,zephyr=431/523,kyra=431/523,kyra_original=431/523,flare=441/495,ace_23=462/468,buddy_23=462/477
QUAL|three_screen|bob=291/308,woman_dark=361/369,rooza=362/396,nova=426/440,unicorn_32=413/392,coach_67=413/384,zephyr=402/434,kyra=402/434,kyra_original=402/434,flare=447/408,ace_23=384/378,buddy_23=332/381
QUAL|three_defend|bob=300/326,woman_dark=356/435,rooza=387/474,nova=431/446,unicorn_32=380/293,coach_67=386/297,zephyr=430/434,kyra=430/434,kyra_original=430/434,flare=399/429,ace_23=367/459,buddy_23=374/477
QUAL|three_shoot|bob=310/334,woman_dark=439/354,rooza=464/361,nova=446/501,unicorn_32=337/536,coach_67=330/516,zephyr=427/494,kyra=427/494,kyra_original=427/494,flare=440/473,ace_23=464/370,buddy_23=460/327
QUAL|three_alley|bob=318/298,woman_dark=439/375,rooza=470/429,nova=444/423,unicorn_32=305/283,coach_67=314/299,zephyr=429/433,kyra=429/433,kyra_original=429/433,flare=432/388,ace_23=462/404,buddy_23=470/437
QUAL|final|bob=314/376,woman_dark=435/453,rooza=465/491,nova=449/531,unicorn_32=341/454,coach_67=321/439,zephyr=431/523,kyra=431/523,kyra_original=431/523,flare=441/495,ace_23=462/468,buddy_23=462/477
QUAL|cross|bob=314/376,woman_dark=435/453,rooza=465/491,nova=449/531,unicorn_32=341/454,coach_67=321/439,zephyr=431/523,kyra=431/523,kyra_original=431/523,flare=441/495,ace_23=462/468,buddy_23=462/477
QUAL|behind_back|bob=314/376,woman_dark=435/453,rooza=465/491,nova=449/531,unicorn_32=341/454,coach_67=321/439,zephyr=431/523,kyra=431/523,kyra_original=431/523,flare=441/495,ace_23=462/468,buddy_23=462/477
QUAL|spin|bob=314/376,woman_dark=435/453,rooza=465/491,nova=449/531,unicorn_32=341/454,coach_67=321/439,zephyr=431/523,kyra=431/523,kyra_original=431/523,flare=441/495,ace_23=462/468,buddy_23=462/477
PICK|move|true|woman_dark|-1=rooza,0=rooza,1=buddy_23,2=ace_23,3=nova,4=flare,5=zephyr,6=kyra_original,7=kyra,8=unicorn_32,9=coach_67,10=coach_67,11=coach_67,40=coach_67
PICK|move|false|woman_dark|-1=coach_67,0=coach_67,1=unicorn_32,2=ace_23,3=buddy_23,4=rooza,5=flare,6=kyra,7=kyra_original,8=zephyr,9=nova,10=nova,11=nova,40=nova
PICK|pass|true|woman_dark|-1=rooza,0=rooza,1=buddy_23,2=ace_23,3=nova,4=flare,5=zephyr,6=kyra_original,7=kyra,8=coach_67,9=unicorn_32,10=unicorn_32,11=unicorn_32,40=unicorn_32
PICK|pass|false|woman_dark|-1=unicorn_32,0=unicorn_32,1=coach_67,2=flare,3=ace_23,4=nova,5=rooza,6=kyra,7=kyra_original,8=zephyr,9=buddy_23,10=buddy_23,11=buddy_23,40=buddy_23
PICK|release|true|woman_dark|-1=rooza,0=rooza,1=ace_23,2=buddy_23,3=nova,4=flare,5=zephyr,6=kyra_original,7=kyra,8=unicorn_32,9=coach_67,10=coach_67,11=coach_67,40=coach_67
PICK|release|false|woman_dark|-1=buddy_23,0=buddy_23,1=rooza,2=ace_23,3=flare,4=kyra,5=kyra_original,6=zephyr,7=nova,8=coach_67,9=unicorn_32,10=unicorn_32,11=unicorn_32,40=unicorn_32
PICK|basket|true|woman_dark|-1=rooza,0=rooza,1=ace_23,2=buddy_23,3=nova,4=flare,5=zephyr,6=kyra_original,7=kyra,8=unicorn_32,9=coach_67,10=coach_67,11=coach_67,40=coach_67
PICK|basket|false|woman_dark|-1=buddy_23,0=buddy_23,1=rooza,2=ace_23,3=flare,4=kyra,5=kyra_original,6=zephyr,7=nova,8=coach_67,9=unicorn_32,10=unicorn_32,11=unicorn_32,40=unicorn_32
PICK|switch|true|woman_dark|-1=nova,0=nova,1=zephyr,2=kyra_original,3=kyra,4=flare,5=rooza,6=coach_67,7=unicorn_32,8=buddy_23,9=ace_23,10=ace_23,11=ace_23,40=ace_23
PICK|switch|false|woman_dark|-1=unicorn_32,0=unicorn_32,1=coach_67,2=flare,3=kyra,4=kyra_original,5=zephyr,6=nova,7=ace_23,8=rooza,9=buddy_23,10=buddy_23,11=buddy_23,40=buddy_23
PICK|steal|true|woman_dark|-1=nova,0=nova,1=zephyr,2=kyra_original,3=kyra,4=flare,5=rooza,6=coach_67,7=unicorn_32,8=buddy_23,9=ace_23,10=ace_23,11=ace_23,40=ace_23
PICK|steal|false|woman_dark|-1=unicorn_32,0=unicorn_32,1=coach_67,2=flare,3=kyra,4=kyra_original,5=zephyr,6=nova,7=ace_23,8=rooza,9=buddy_23,10=buddy_23,11=buddy_23,40=buddy_23
PICK|screen|true|woman_dark|-1=flare,0=flare,1=nova,2=unicorn_32,3=coach_67,4=zephyr,5=kyra_original,6=kyra,7=ace_23,8=rooza,9=buddy_23,10=buddy_23,11=buddy_23,40=buddy_23
PICK|screen|false|woman_dark|-1=ace_23,0=ace_23,1=buddy_23,2=coach_67,3=unicorn_32,4=rooza,5=flare,6=kyra,7=kyra_original,8=zephyr,9=nova,10=nova,11=nova,40=nova
PICK|alley|true|woman_dark|-1=zephyr,0=zephyr,1=kyra_original,2=kyra,3=flare,4=nova,5=rooza,6=ace_23,7=buddy_23,8=unicorn_32,9=coach_67,10=coach_67,11=coach_67,40=coach_67
PICK|alley|false|woman_dark|-1=buddy_23,0=buddy_23,1=rooza,2=ace_23,3=flare,4=coach_67,5=kyra,6=kyra_original,7=zephyr,8=nova,9=unicorn_32,10=unicorn_32,11=unicorn_32,40=unicorn_32
PICK|move_pass|true|woman_dark|-1=rooza,0=rooza,1=buddy_23,2=ace_23,3=nova,4=flare,5=zephyr,6=kyra_original,7=kyra,8=unicorn_32,9=coach_67,10=coach_67,11=coach_67,40=coach_67
PICK|move_pass|false|woman_dark|-1=coach_67,0=coach_67,1=unicorn_32,2=ace_23,3=buddy_23,4=rooza,5=flare,6=kyra,7=kyra_original,8=zephyr,9=nova,10=nova,11=nova,40=nova
PICK|shoot|true|woman_dark|-1=rooza,0=rooza,1=ace_23,2=buddy_23,3=nova,4=flare,5=zephyr,6=kyra_original,7=kyra,8=unicorn_32,9=coach_67,10=coach_67,11=coach_67,40=coach_67
PICK|shoot|false|woman_dark|-1=buddy_23,0=buddy_23,1=rooza,2=ace_23,3=flare,4=kyra,5=kyra_original,6=zephyr,7=nova,8=coach_67,9=unicorn_32,10=unicorn_32,11=unicorn_32,40=unicorn_32
PICK|defend|true|woman_dark|-1=nova,0=nova,1=zephyr,2=kyra_original,3=kyra,4=flare,5=rooza,6=coach_67,7=unicorn_32,8=buddy_23,9=ace_23,10=ace_23,11=ace_23,40=ace_23
PICK|defend|false|woman_dark|-1=unicorn_32,0=unicorn_32,1=coach_67,2=flare,3=kyra,4=kyra_original,5=zephyr,6=nova,7=ace_23,8=rooza,9=buddy_23,10=buddy_23,11=buddy_23,40=buddy_23
PICK|screen_pass|true|woman_dark|-1=flare,0=flare,1=nova,2=unicorn_32,3=coach_67,4=zephyr,5=kyra_original,6=kyra,7=ace_23,8=rooza,9=buddy_23,10=buddy_23,11=buddy_23,40=buddy_23
PICK|screen_pass|false|woman_dark|-1=ace_23,0=ace_23,1=buddy_23,2=coach_67,3=unicorn_32,4=rooza,5=flare,6=kyra,7=kyra_original,8=zephyr,9=nova,10=nova,11=nova,40=nova
PICK|alley_twice|true|woman_dark|-1=zephyr,0=zephyr,1=kyra_original,2=kyra,3=flare,4=nova,5=rooza,6=ace_23,7=buddy_23,8=unicorn_32,9=coach_67,10=coach_67,11=coach_67,40=coach_67
PICK|alley_twice|false|woman_dark|-1=buddy_23,0=buddy_23,1=rooza,2=ace_23,3=flare,4=coach_67,5=kyra,6=kyra_original,7=zephyr,8=nova,9=unicorn_32,10=unicorn_32,11=unicorn_32,40=unicorn_32
PICK|three_pass|true|woman_dark|-1=rooza,0=rooza,1=buddy_23,2=ace_23,3=nova,4=flare,5=zephyr,6=kyra_original,7=kyra,8=coach_67,9=unicorn_32,10=unicorn_32,11=unicorn_32,40=unicorn_32
PICK|three_pass|false|woman_dark|-1=unicorn_32,0=unicorn_32,1=coach_67,2=flare,3=ace_23,4=nova,5=rooza,6=kyra,7=kyra_original,8=zephyr,9=buddy_23,10=buddy_23,11=buddy_23,40=buddy_23
PICK|three_move|true|woman_dark|-1=rooza,0=rooza,1=buddy_23,2=ace_23,3=nova,4=flare,5=zephyr,6=kyra_original,7=kyra,8=unicorn_32,9=coach_67,10=coach_67,11=coach_67,40=coach_67
PICK|three_move|false|woman_dark|-1=coach_67,0=coach_67,1=unicorn_32,2=ace_23,3=buddy_23,4=rooza,5=flare,6=kyra,7=kyra_original,8=zephyr,9=nova,10=nova,11=nova,40=nova
PICK|three_screen|true|woman_dark|-1=flare,0=flare,1=nova,2=unicorn_32,3=coach_67,4=zephyr,5=kyra_original,6=kyra,7=ace_23,8=rooza,9=buddy_23,10=buddy_23,11=buddy_23,40=buddy_23
PICK|three_screen|false|woman_dark|-1=ace_23,0=ace_23,1=buddy_23,2=coach_67,3=unicorn_32,4=rooza,5=flare,6=kyra,7=kyra_original,8=zephyr,9=nova,10=nova,11=nova,40=nova
PICK|three_defend|true|woman_dark|-1=nova,0=nova,1=zephyr,2=kyra_original,3=kyra,4=flare,5=rooza,6=coach_67,7=unicorn_32,8=buddy_23,9=ace_23,10=ace_23,11=ace_23,40=ace_23
PICK|three_defend|false|woman_dark|-1=unicorn_32,0=unicorn_32,1=coach_67,2=flare,3=kyra,4=kyra_original,5=zephyr,6=nova,7=ace_23,8=rooza,9=buddy_23,10=buddy_23,11=buddy_23,40=buddy_23
PICK|three_shoot|true|woman_dark|-1=rooza,0=rooza,1=ace_23,2=buddy_23,3=nova,4=flare,5=zephyr,6=kyra_original,7=kyra,8=unicorn_32,9=coach_67,10=coach_67,11=coach_67,40=coach_67
PICK|three_shoot|false|woman_dark|-1=buddy_23,0=buddy_23,1=rooza,2=ace_23,3=flare,4=kyra,5=kyra_original,6=zephyr,7=nova,8=coach_67,9=unicorn_32,10=unicorn_32,11=unicorn_32,40=unicorn_32
PICK|three_alley|true|woman_dark|-1=rooza,0=rooza,1=buddy_23,2=ace_23,3=nova,4=flare,5=zephyr,6=kyra_original,7=kyra,8=coach_67,9=unicorn_32,10=unicorn_32,11=unicorn_32,40=unicorn_32
PICK|three_alley|false|woman_dark|-1=unicorn_32,0=unicorn_32,1=coach_67,2=flare,3=ace_23,4=nova,5=rooza,6=kyra,7=kyra_original,8=zephyr,9=buddy_23,10=buddy_23,11=buddy_23,40=buddy_23
PICK|final|true|woman_dark|-1=rooza,0=rooza,1=buddy_23,2=ace_23,3=nova,4=flare,5=zephyr,6=kyra_original,7=kyra,8=unicorn_32,9=coach_67,10=coach_67,11=coach_67,40=coach_67
PICK|final|false|woman_dark|-1=coach_67,0=coach_67,1=unicorn_32,2=ace_23,3=buddy_23,4=rooza,5=flare,6=kyra,7=kyra_original,8=zephyr,9=nova,10=nova,11=nova,40=nova
PICK|cross|true|woman_dark|-1=rooza,0=rooza,1=buddy_23,2=ace_23,3=nova,4=flare,5=zephyr,6=kyra_original,7=kyra,8=unicorn_32,9=coach_67,10=coach_67,11=coach_67,40=coach_67
PICK|cross|false|woman_dark|-1=coach_67,0=coach_67,1=unicorn_32,2=ace_23,3=buddy_23,4=rooza,5=flare,6=kyra,7=kyra_original,8=zephyr,9=nova,10=nova,11=nova,40=nova
PICK|behind_back|true|woman_dark|-1=rooza,0=rooza,1=buddy_23,2=ace_23,3=nova,4=flare,5=zephyr,6=kyra_original,7=kyra,8=unicorn_32,9=coach_67,10=coach_67,11=coach_67,40=coach_67
PICK|behind_back|false|woman_dark|-1=coach_67,0=coach_67,1=unicorn_32,2=ace_23,3=buddy_23,4=rooza,5=flare,6=kyra,7=kyra_original,8=zephyr,9=nova,10=nova,11=nova,40=nova
PICK|spin|true|woman_dark|-1=rooza,0=rooza,1=buddy_23,2=ace_23,3=nova,4=flare,5=zephyr,6=kyra_original,7=kyra,8=unicorn_32,9=coach_67,10=coach_67,11=coach_67,40=coach_67
PICK|spin|false|woman_dark|-1=coach_67,0=coach_67,1=unicorn_32,2=ace_23,3=buddy_23,4=rooza,5=flare,6=kyra,7=kyra_original,8=zephyr,9=nova,10=nova,11=nova,40=nova
PICK|move|true||0=rooza,3=nova,11=coach_67,12=coach_67
PICK|move|false||0=coach_67,3=ace_23,11=nova,12=nova
PICK|pass|true||0=rooza,3=nova,11=unicorn_32,12=unicorn_32
PICK|pass|false||0=unicorn_32,3=flare,11=buddy_23,12=buddy_23
PICK|release|true||0=rooza,3=nova,11=coach_67,12=coach_67
PICK|release|false||0=buddy_23,3=ace_23,11=unicorn_32,12=unicorn_32
PICK|move|true|woman_dark+rooza+nova+unicorn_32+coach_67+zephyr+kyra+kyra_original+flare|0=buddy_23,1=ace_23,2=ace_23,5=ace_23
PICK|move|false|woman_dark+rooza+nova+unicorn_32+coach_67+zephyr+kyra+kyra_original+flare|0=ace_23,1=buddy_23,2=buddy_23,5=buddy_23
PICK|pass|true|woman_dark+rooza+nova+unicorn_32+coach_67+zephyr+kyra+kyra_original+flare|0=buddy_23,1=ace_23,2=ace_23,5=ace_23
PICK|pass|false|woman_dark+rooza+nova+unicorn_32+coach_67+zephyr+kyra+kyra_original+flare|0=ace_23,1=buddy_23,2=buddy_23,5=buddy_23
LINEUP|0|move|0|rooza|coach_67,unicorn_32|8
LINEUP|1|pass|0|rooza|unicorn_32,coach_67|2
LINEUP|2|release|0|rooza|buddy_23,ace_23|3
LINEUP|3|basket|0|rooza|buddy_23,ace_23|2
LINEUP|4|switch|0|nova|unicorn_32,coach_67|3
LINEUP|5|steal|0|nova|unicorn_32,coach_67|1
LINEUP|6|screen|0|flare|ace_23,buddy_23|1
LINEUP|7|alley|0|zephyr|buddy_23,rooza|1
LINEUP|8|move_pass|0|rooza|coach_67,unicorn_32|10,3
LINEUP|9|shoot|0|rooza|buddy_23,ace_23|4,2
LINEUP|10|defend|0|nova|unicorn_32,coach_67|2,2
LINEUP|11|screen_pass|0|flare|ace_23,buddy_23|2,3
LINEUP|12|alley_twice|0|zephyr|buddy_23,rooza|2
LINEUP|13|three_pass|0|rooza,buddy_23|unicorn_32,coach_67,flare|5
LINEUP|14|three_move|0|rooza,buddy_23|coach_67,unicorn_32,ace_23|15,4
LINEUP|15|three_screen|0|flare,nova|ace_23,buddy_23,coach_67|2,2
LINEUP|16|three_defend|0|nova,zephyr|unicorn_32,coach_67,flare|3,2
LINEUP|17|three_shoot|0|rooza,ace_23|buddy_23,flare,kyra|5,3
LINEUP|18|three_alley|0|rooza,buddy_23|unicorn_32,coach_67,flare|4,2
LINEUP|19|final|0|rooza,buddy_23|coach_67,unicorn_32,ace_23|12,4,3
LINEUP|20|cross|0|rooza|coach_67,unicorn_32|2
LINEUP|21|behind_back|0|rooza|coach_67,unicorn_32|2
LINEUP|22|spin|0|rooza|coach_67,unicorn_32|3
LINEUP|23|move|1|buddy_23|unicorn_32,ace_23|10
LINEUP|24|pass|1|buddy_23|coach_67,flare|3
LINEUP|25|release|1|ace_23|rooza,flare|4
LINEUP|26|basket|1|ace_23|rooza,flare|3
LINEUP|27|switch|1|zephyr|coach_67,flare|4
LINEUP|28|steal|1|zephyr|coach_67,flare|2
LINEUP|29|screen|1|nova|buddy_23,coach_67|2
LINEUP|30|alley|1|kyra_original|rooza,ace_23|2
LINEUP|31|move_pass|1|buddy_23|unicorn_32,ace_23|12,4
LINEUP|32|shoot|1|ace_23|rooza,flare|5,3
LINEUP|33|defend|1|zephyr|coach_67,flare|3,3
LINEUP|34|screen_pass|1|nova|buddy_23,coach_67|3,4
LINEUP|35|alley_twice|1|kyra_original|rooza,ace_23|3
LINEUP|36|three_pass|1|buddy_23,ace_23|coach_67,flare,nova|6
LINEUP|37|three_move|1|buddy_23,ace_23|unicorn_32,rooza,flare|17,5
LINEUP|38|three_screen|1|nova,unicorn_32|buddy_23,coach_67,rooza|3,3
LINEUP|39|three_defend|1|zephyr,kyra_original|coach_67,flare,kyra|4,3
LINEUP|40|three_shoot|1|ace_23,buddy_23|flare,kyra,kyra_original|6,4
LINEUP|41|three_alley|1|buddy_23,ace_23|coach_67,flare,nova|5,3
LINEUP|42|final|1|buddy_23,ace_23|unicorn_32,rooza,flare|14,5,4
LINEUP|43|cross|1|buddy_23|unicorn_32,ace_23|3
LINEUP|44|behind_back|1|buddy_23|unicorn_32,ace_23|3
LINEUP|45|spin|1|buddy_23|unicorn_32,ace_23|4
LINEUP|99|alley|4|nova|coach_67,kyra|5
LINEUP|119|switch|5|rooza|zephyr,nova|8
LINEUP|120|steal|5|rooza|zephyr,nova|6
LINEUP|139|pass|6|kyra_original|kyra,zephyr|8
LINEUP|140|release|6|kyra_original|nova,coach_67|9
LINEUP|141|basket|6|kyra_original|nova,coach_67|8
LINEUP|200|three_defend|8|buddy_23,ace_23|rooza,nova,zephyr|9,8
LINEUP|399|move_pass|17|coach_67|nova,zephyr|22,9
STAGE_WRAP|0=move,19=final,20=cross,21=behind_back,-1=spin,-20=basket,-21=release,45=spin,1000000=screen
PRACTICE|0||init|-|i=0;won=false;active=MOVE;progress=0.0;snap=0.0
PRACTICE|0||SCREEN:NaN|false|i=0;won=false;active=MOVE;progress=0.0;snap=0.0
PRACTICE|0||MOVE:0.2|false|i=0;won=false;active=MOVE;progress=0.2;snap=0.2
PRACTICE|0||MOVE:0.25|false|i=0;won=false;active=MOVE;progress=0.45;snap=0.45
PRACTICE|0||MOVE:2.5|false|i=0;won=false;active=MOVE;progress=2.95;snap=2.95
PRACTICE|0||BASKET:Infinity|false|i=0;won=false;active=MOVE;progress=2.95;snap=2.95
PRACTICE|0||MOVE:NaN|false|i=0;won=false;active=MOVE;progress=2.95;snap=2.95
PRACTICE|0||MOVE:0.0|false|i=0;won=false;active=MOVE;progress=2.95;snap=2.95
PRACTICE|0||MOVE:0.0|false|i=0;won=false;active=MOVE;progress=2.95;snap=2.95
PRACTICE|0||MOVE:0.5|false|i=0;won=false;active=MOVE;progress=3.45;snap=3.45
PRACTICE|0||MOVE:-1.0|false|i=0;won=false;active=MOVE;progress=3.45;snap=3.45
PRACTICE|0||MOVE:1.0|false|i=0;won=false;active=MOVE;progress=4.45;snap=4.45
PRACTICE|0||MOVE:0.9999995|false|i=0;won=false;active=MOVE;progress=5.4499995000000006;snap=5.4499995000000006
PRACTICE|0||MOVE:Infinity|false|i=0;won=false;active=MOVE;progress=5.4499995000000006;snap=5.4499995000000006
PRACTICE|0||SWITCH:-0.0|false|i=0;won=false;active=MOVE;progress=5.4499995000000006;snap=5.4499995000000006
PRACTICE|0||MOVE:-0.0|false|i=0;won=false;active=MOVE;progress=5.4499995000000006;snap=5.4499995000000006
PRACTICE|0||MOVE:0.1|false|i=0;won=false;active=MOVE;progress=5.5499995;snap=5.5499995
PRACTICE|0||MOVE:0.5|false|i=0;won=false;active=MOVE;progress=6.0499995;snap=6.0499995
PRACTICE|0||MOVE:0.2|false|i=0;won=false;active=MOVE;progress=6.2499995;snap=6.2499995
PRACTICE|0||MOVE:0.1|false|i=0;won=false;active=MOVE;progress=6.3499995;snap=6.3499995
PRACTICE|0||MOVE:-0.0|false|i=0;won=false;active=MOVE;progress=6.3499995;snap=6.3499995
PRACTICE|0|1.5,NaN,-0.0,1.0E9|init|-|i=0;won=false;active=MOVE;progress=1.5;snap=1.5
PRACTICE|0|1.5,NaN,-0.0,1.0E9|MOVE:0.9999995|false|i=0;won=false;active=MOVE;progress=2.4999995;snap=2.4999995
PRACTICE|0|1.5,NaN,-0.0,1.0E9|ALLEY:-1.0|false|i=0;won=false;active=MOVE;progress=2.4999995;snap=2.4999995
PRACTICE|0|1.5,NaN,-0.0,1.0E9|MOVE:NaN|false|i=0;won=false;active=MOVE;progress=2.4999995;snap=2.4999995
PRACTICE|0|1.5,NaN,-0.0,1.0E9|MOVE:1.0|false|i=0;won=false;active=MOVE;progress=3.4999995;snap=3.4999995
PRACTICE|0|1.5,NaN,-0.0,1.0E9|MOVE:0.9999995|false|i=0;won=false;active=MOVE;progress=4.499999;snap=4.499999
PRACTICE|0|1.5,NaN,-0.0,1.0E9|SCREEN:2.5|false|i=0;won=false;active=MOVE;progress=4.499999;snap=4.499999
PRACTICE|0|1.5,NaN,-0.0,1.0E9|MOVE:3.0|false|i=0;won=false;active=MOVE;progress=7.499999;snap=7.499999
PRACTICE|0|1.5,NaN,-0.0,1.0E9|SWITCH:0.0|false|i=0;won=false;active=MOVE;progress=7.499999;snap=7.499999
PRACTICE|0|1.5,NaN,-0.0,1.0E9|MOVE:-0.0|false|i=0;won=false;active=MOVE;progress=7.499999;snap=7.499999
PRACTICE|0|1.5,NaN,-0.0,1.0E9|MOVE:1.0E-7|false|i=0;won=false;active=MOVE;progress=7.4999991;snap=7.4999991
PRACTICE|0|1.5,NaN,-0.0,1.0E9|MOVE:0.5|true|i=1;won=true;active=null;progress=7.9999991;snap=7.9999991
PRACTICE|0|1.5,NaN,-0.0,1.0E9|MOVE:1.0|false|i=1;won=true;active=null;progress=7.9999991;snap=7.9999991
PRACTICE|0|1.5,NaN,-0.0,1.0E9|MOVE:3.0|false|i=1;won=true;active=null;progress=7.9999991;snap=7.9999991
PRACTICE|0|1.5,NaN,-0.0,1.0E9|MOVE:-0.0|false|i=1;won=true;active=null;progress=7.9999991;snap=7.9999991
PRACTICE|0|1.5,NaN,-0.0,1.0E9|MOVE:2.5|false|i=1;won=true;active=null;progress=7.9999991;snap=7.9999991
PRACTICE|0|1.5,NaN,-0.0,1.0E9|STEAL:Infinity|false|i=1;won=true;active=null;progress=7.9999991;snap=7.9999991
PRACTICE|0|1.5,NaN,-0.0,1.0E9|MOVE:-0.0|false|i=1;won=true;active=null;progress=7.9999991;snap=7.9999991
PRACTICE|0|1.5,NaN,-0.0,1.0E9|MOVE:2.5|false|i=1;won=true;active=null;progress=7.9999991;snap=7.9999991
PRACTICE|0|1.5,NaN,-0.0,1.0E9|SCREEN:0.5|false|i=1;won=true;active=null;progress=7.9999991;snap=7.9999991
PRACTICE|0|1.5,NaN,-0.0,1.0E9|MOVE:3.0|false|i=1;won=true;active=null;progress=7.9999991;snap=7.9999991
PRACTICE|8||init|-|i=0;won=false;active=MOVE;progress=0.0,0.0;snap=0.0,0.0
PRACTICE|8||MOVE:1.0E-7|false|i=0;won=false;active=MOVE;progress=1.0E-7,0.0;snap=1.0E-7,0.0
PRACTICE|8||MOVE:0.0|false|i=0;won=false;active=MOVE;progress=1.0E-7,0.0;snap=1.0E-7,0.0
PRACTICE|8||MOVE:1.0E-7|false|i=0;won=false;active=MOVE;progress=2.0E-7,0.0;snap=2.0E-7,0.0
PRACTICE|8||MOVE:1.0E-7|false|i=0;won=false;active=MOVE;progress=3.0E-7,0.0;snap=3.0E-7,0.0
PRACTICE|8||SWITCH:0.0|false|i=0;won=false;active=MOVE;progress=3.0E-7,0.0;snap=3.0E-7,0.0
PRACTICE|8||MOVE:Infinity|false|i=0;won=false;active=MOVE;progress=3.0E-7,0.0;snap=3.0E-7,0.0
PRACTICE|8||MOVE:NaN|false|i=0;won=false;active=MOVE;progress=3.0E-7,0.0;snap=3.0E-7,0.0
PRACTICE|8||ALLEY:3.0|false|i=0;won=false;active=MOVE;progress=3.0E-7,0.0;snap=3.0E-7,0.0
PRACTICE|8||MOVE:-1.0|false|i=0;won=false;active=MOVE;progress=3.0E-7,0.0;snap=3.0E-7,0.0
PRACTICE|8||MOVE:0.0|false|i=0;won=false;active=MOVE;progress=3.0E-7,0.0;snap=3.0E-7,0.0
PRACTICE|8||MOVE:Infinity|false|i=0;won=false;active=MOVE;progress=3.0E-7,0.0;snap=3.0E-7,0.0
PRACTICE|8||MOVE:0.25|false|i=0;won=false;active=MOVE;progress=0.2500003,0.0;snap=0.2500003,0.0
PRACTICE|8||MOVE:NaN|false|i=0;won=false;active=MOVE;progress=0.2500003,0.0;snap=0.2500003,0.0
PRACTICE|8||MOVE:-1.0|false|i=0;won=false;active=MOVE;progress=0.2500003,0.0;snap=0.2500003,0.0
PRACTICE|8||MOVE:0.9999995|false|i=0;won=false;active=MOVE;progress=1.2499998,0.0;snap=1.2499998,0.0
PRACTICE|8||ALLEY:-1.0|false|i=0;won=false;active=MOVE;progress=1.2499998,0.0;snap=1.2499998,0.0
PRACTICE|8||MOVE:NaN|false|i=0;won=false;active=MOVE;progress=1.2499998,0.0;snap=1.2499998,0.0
PRACTICE|8||MOVE:0.0|false|i=0;won=false;active=MOVE;progress=1.2499998,0.0;snap=1.2499998,0.0
PRACTICE|8||MOVE:1.0|false|i=0;won=false;active=MOVE;progress=2.2499998000000003,0.0;snap=2.2499998000000003,0.0
PRACTICE|8||MOVE:-0.0|false|i=0;won=false;active=MOVE;progress=2.2499998000000003,0.0;snap=2.2499998000000003,0.0
PRACTICE|8|1.5,NaN,-0.0,1.0E9|init|-|i=0;won=false;active=MOVE;progress=1.5,0.0;snap=1.5,0.0
PRACTICE|8|1.5,NaN,-0.0,1.0E9|MOVE:3.0|false|i=0;won=false;active=MOVE;progress=4.5,0.0;snap=4.5,0.0
PRACTICE|8|1.5,NaN,-0.0,1.0E9|SCREEN:NaN|false|i=0;won=false;active=MOVE;progress=4.5,0.0;snap=4.5,0.0
PRACTICE|8|1.5,NaN,-0.0,1.0E9|MOVE:0.9999995|false|i=0;won=false;active=MOVE;progress=5.4999995,0.0;snap=5.4999995,0.0
PRACTICE|8|1.5,NaN,-0.0,1.0E9|MOVE:0.9999995|false|i=0;won=false;active=MOVE;progress=6.499999000000001,0.0;snap=6.499999000000001,0.0
PRACTICE|8|1.5,NaN,-0.0,1.0E9|MOVE:1.0E-7|false|i=0;won=false;active=MOVE;progress=6.499999100000001,0.0;snap=6.499999100000001,0.0
PRACTICE|8|1.5,NaN,-0.0,1.0E9|MOVE:0.0|false|i=0;won=false;active=MOVE;progress=6.499999100000001,0.0;snap=6.499999100000001,0.0
PRACTICE|8|1.5,NaN,-0.0,1.0E9|SWITCH:-1.0|false|i=0;won=false;active=MOVE;progress=6.499999100000001,0.0;snap=6.499999100000001,0.0
PRACTICE|8|1.5,NaN,-0.0,1.0E9|MOVE:0.9999995|false|i=0;won=false;active=MOVE;progress=7.499998600000001,0.0;snap=7.499998600000001,0.0
PRACTICE|8|1.5,NaN,-0.0,1.0E9|MOVE:-1.0|false|i=0;won=false;active=MOVE;progress=7.499998600000001,0.0;snap=7.499998600000001,0.0
PRACTICE|8|1.5,NaN,-0.0,1.0E9|MOVE:1.0E-7|false|i=0;won=false;active=MOVE;progress=7.499998700000002,0.0;snap=7.499998700000002,0.0
PRACTICE|8|1.5,NaN,-0.0,1.0E9|MOVE:-0.0|false|i=0;won=false;active=MOVE;progress=7.499998700000002,0.0;snap=7.499998700000002,0.0
PRACTICE|8|1.5,NaN,-0.0,1.0E9|MOVE:0.0|false|i=0;won=false;active=MOVE;progress=7.499998700000002,0.0;snap=7.499998700000002,0.0
PRACTICE|8|1.5,NaN,-0.0,1.0E9|PASS:1.0|false|i=0;won=false;active=MOVE;progress=7.499998700000002,0.0;snap=7.499998700000002,0.0
PRACTICE|8|1.5,NaN,-0.0,1.0E9|MOVE:0.5|false|i=0;won=false;active=MOVE;progress=7.999998700000002,0.0;snap=7.999998700000002,0.0
PRACTICE|8|1.5,NaN,-0.0,1.0E9|MOVE:0.25|false|i=0;won=false;active=MOVE;progress=8.249998700000003,0.0;snap=8.249998700000003,0.0
PRACTICE|8|1.5,NaN,-0.0,1.0E9|ALLEY:-1.0|false|i=0;won=false;active=MOVE;progress=8.249998700000003,0.0;snap=8.249998700000003,0.0
PRACTICE|8|1.5,NaN,-0.0,1.0E9|MOVE:1.0|false|i=0;won=false;active=MOVE;progress=9.249998700000003,0.0;snap=9.249998700000003,0.0
PRACTICE|8|1.5,NaN,-0.0,1.0E9|MOVE:1.0|true|i=1;won=false;active=PASS;progress=10.0,0.0;snap=10.0,0.0
PRACTICE|8|1.5,NaN,-0.0,1.0E9|PASS:0.5|false|i=1;won=false;active=PASS;progress=10.0,0.5;snap=10.0,0.5
PRACTICE|8|1.5,NaN,-0.0,1.0E9|PASS:1.0E-7|false|i=1;won=false;active=PASS;progress=10.0,0.5000001;snap=10.0,0.5000001
PRACTICE|19||init|-|i=0;won=false;active=MOVE;progress=0.0,0.0,0.0;snap=0.0,0.0,0.0
PRACTICE|19||PASS:2.5|false|i=0;won=false;active=MOVE;progress=0.0,0.0,0.0;snap=0.0,0.0,0.0
PRACTICE|19||MOVE:0.9999995|false|i=0;won=false;active=MOVE;progress=0.9999995,0.0,0.0;snap=0.9999995,0.0,0.0
PRACTICE|19||MOVE:0.25|false|i=0;won=false;active=MOVE;progress=1.2499995,0.0,0.0;snap=1.2499995,0.0,0.0
PRACTICE|19||MOVE:0.2|false|i=0;won=false;active=MOVE;progress=1.4499994999999999,0.0,0.0;snap=1.4499994999999999,0.0,0.0
PRACTICE|19||MOVE:0.2|false|i=0;won=false;active=MOVE;progress=1.6499994999999998,0.0,0.0;snap=1.6499994999999998,0.0,0.0
PRACTICE|19||MOVE:0.9999995|false|i=0;won=false;active=MOVE;progress=2.6499989999999998,0.0,0.0;snap=2.6499989999999998,0.0,0.0
PRACTICE|19||MOVE:NaN|false|i=0;won=false;active=MOVE;progress=2.6499989999999998,0.0,0.0;snap=2.6499989999999998,0.0,0.0
PRACTICE|19||SCREEN:1.0E-7|false|i=0;won=false;active=MOVE;progress=2.6499989999999998,0.0,0.0;snap=2.6499989999999998,0.0,0.0
PRACTICE|19||MOVE:-0.0|false|i=0;won=false;active=MOVE;progress=2.6499989999999998,0.0,0.0;snap=2.6499989999999998,0.0,0.0
PRACTICE|19||MOVE:0.9999995|false|i=0;won=false;active=MOVE;progress=3.6499984999999997,0.0,0.0;snap=3.6499984999999997,0.0,0.0
PRACTICE|19||MOVE:0.2|false|i=0;won=false;active=MOVE;progress=3.8499985,0.0,0.0;snap=3.8499985,0.0,0.0
PRACTICE|19||SWITCH:0.5|false|i=0;won=false;active=MOVE;progress=3.8499985,0.0,0.0;snap=3.8499985,0.0,0.0
PRACTICE|19||BASKET:1.0|false|i=0;won=false;active=MOVE;progress=3.8499985,0.0,0.0;snap=3.8499985,0.0,0.0
PRACTICE|19||SWITCH:1.0|false|i=0;won=false;active=MOVE;progress=3.8499985,0.0,0.0;snap=3.8499985,0.0,0.0
PRACTICE|19||PASS:Infinity|false|i=0;won=false;active=MOVE;progress=3.8499985,0.0,0.0;snap=3.8499985,0.0,0.0
PRACTICE|19||MOVE:Infinity|false|i=0;won=false;active=MOVE;progress=3.8499985,0.0,0.0;snap=3.8499985,0.0,0.0
PRACTICE|19||MOVE:-0.0|false|i=0;won=false;active=MOVE;progress=3.8499985,0.0,0.0;snap=3.8499985,0.0,0.0
PRACTICE|19||MOVE:Infinity|false|i=0;won=false;active=MOVE;progress=3.8499985,0.0,0.0;snap=3.8499985,0.0,0.0
PRACTICE|19||MOVE:-0.0|false|i=0;won=false;active=MOVE;progress=3.8499985,0.0,0.0;snap=3.8499985,0.0,0.0
PRACTICE|19||MOVE:-0.0|false|i=0;won=false;active=MOVE;progress=3.8499985,0.0,0.0;snap=3.8499985,0.0,0.0
PRACTICE|19|1.5,NaN,-0.0,1.0E9|init|-|i=0;won=false;active=MOVE;progress=1.5,0.0,-0.0;snap=1.5,0.0,-0.0
PRACTICE|19|1.5,NaN,-0.0,1.0E9|MOVE:3.0|false|i=0;won=false;active=MOVE;progress=4.5,0.0,-0.0;snap=4.5,0.0,-0.0
PRACTICE|19|1.5,NaN,-0.0,1.0E9|MOVE:1.0|false|i=0;won=false;active=MOVE;progress=5.5,0.0,-0.0;snap=5.5,0.0,-0.0
PRACTICE|19|1.5,NaN,-0.0,1.0E9|MOVE:-1.0|false|i=0;won=false;active=MOVE;progress=5.5,0.0,-0.0;snap=5.5,0.0,-0.0
PRACTICE|19|1.5,NaN,-0.0,1.0E9|MOVE:3.0|false|i=0;won=false;active=MOVE;progress=8.5,0.0,-0.0;snap=8.5,0.0,-0.0
PRACTICE|19|1.5,NaN,-0.0,1.0E9|MOVE:1.0E-7|false|i=0;won=false;active=MOVE;progress=8.5000001,0.0,-0.0;snap=8.5000001,0.0,-0.0
PRACTICE|19|1.5,NaN,-0.0,1.0E9|MOVE:0.2|false|i=0;won=false;active=MOVE;progress=8.700000099999999,0.0,-0.0;snap=8.700000099999999,0.0,-0.0
PRACTICE|19|1.5,NaN,-0.0,1.0E9|MOVE:0.1|false|i=0;won=false;active=MOVE;progress=8.800000099999998,0.0,-0.0;snap=8.800000099999998,0.0,-0.0
PRACTICE|19|1.5,NaN,-0.0,1.0E9|MOVE:0.5|false|i=0;won=false;active=MOVE;progress=9.300000099999998,0.0,-0.0;snap=9.300000099999998,0.0,-0.0
PRACTICE|19|1.5,NaN,-0.0,1.0E9|BASKET:0.2|false|i=0;won=false;active=MOVE;progress=9.300000099999998,0.0,-0.0;snap=9.300000099999998,0.0,-0.0
PRACTICE|19|1.5,NaN,-0.0,1.0E9|MOVE:0.5|false|i=0;won=false;active=MOVE;progress=9.800000099999998,0.0,-0.0;snap=9.800000099999998,0.0,-0.0
PRACTICE|19|1.5,NaN,-0.0,1.0E9|MOVE:0.25|false|i=0;won=false;active=MOVE;progress=10.050000099999998,0.0,-0.0;snap=10.050000099999998,0.0,-0.0
PRACTICE|19|1.5,NaN,-0.0,1.0E9|MOVE:3.0|true|i=1;won=false;active=PASS;progress=12.0,0.0,-0.0;snap=12.0,0.0,-0.0
PRACTICE|19|1.5,NaN,-0.0,1.0E9|PASS:-0.0|false|i=1;won=false;active=PASS;progress=12.0,0.0,-0.0;snap=12.0,0.0,-0.0
PRACTICE|19|1.5,NaN,-0.0,1.0E9|PASS:0.25|false|i=1;won=false;active=PASS;progress=12.0,0.25,-0.0;snap=12.0,0.25,-0.0
PRACTICE|19|1.5,NaN,-0.0,1.0E9|SWITCH:1.0E-7|false|i=1;won=false;active=PASS;progress=12.0,0.25,-0.0;snap=12.0,0.25,-0.0
PRACTICE|19|1.5,NaN,-0.0,1.0E9|PASS:1.0|false|i=1;won=false;active=PASS;progress=12.0,1.25,-0.0;snap=12.0,1.25,-0.0
PRACTICE|19|1.5,NaN,-0.0,1.0E9|PASS:Infinity|false|i=1;won=false;active=PASS;progress=12.0,1.25,-0.0;snap=12.0,1.25,-0.0
PRACTICE|19|1.5,NaN,-0.0,1.0E9|PASS:0.1|false|i=1;won=false;active=PASS;progress=12.0,1.35,-0.0;snap=12.0,1.35,-0.0
PRACTICE|19|1.5,NaN,-0.0,1.0E9|PASS:0.2|false|i=1;won=false;active=PASS;progress=12.0,1.55,-0.0;snap=12.0,1.55,-0.0
PRACTICE|19|1.5,NaN,-0.0,1.0E9|PASS:0.25|false|i=1;won=false;active=PASS;progress=12.0,1.8,-0.0;snap=12.0,1.8,-0.0
PRACTICE|139||init|-|i=0;won=false;active=PASS;progress=0.0;snap=0.0
PRACTICE|139||PASS:0.9999995|false|i=0;won=false;active=PASS;progress=0.9999995;snap=0.9999995
PRACTICE|139||PASS:3.0|false|i=0;won=false;active=PASS;progress=3.9999995;snap=3.9999995
PRACTICE|139||PASS:0.0|false|i=0;won=false;active=PASS;progress=3.9999995;snap=3.9999995
PRACTICE|139||PASS:1.0E-7|false|i=0;won=false;active=PASS;progress=3.9999995999999998;snap=3.9999995999999998
PRACTICE|139||PASS:0.9999995|false|i=0;won=false;active=PASS;progress=4.9999991;snap=4.9999991
PRACTICE|139||PASS:0.9999995|false|i=0;won=false;active=PASS;progress=5.9999986000000005;snap=5.9999986000000005
PRACTICE|139||PASS:1.0|false|i=0;won=false;active=PASS;progress=6.9999986000000005;snap=6.9999986000000005
PRACTICE|139||PASS:0.1|false|i=0;won=false;active=PASS;progress=7.0999986;snap=7.0999986
PRACTICE|139||STEAL:0.2|false|i=0;won=false;active=PASS;progress=7.0999986;snap=7.0999986
PRACTICE|139||PASS:0.25|false|i=0;won=false;active=PASS;progress=7.3499986;snap=7.3499986
PRACTICE|139||MOVE:2.5|false|i=0;won=false;active=PASS;progress=7.3499986;snap=7.3499986
PRACTICE|139||PASS:1.0|true|i=1;won=true;active=null;progress=8.0;snap=8.0
PRACTICE|139||MOVE:3.0|false|i=1;won=true;active=null;progress=8.0;snap=8.0
PRACTICE|139||MOVE:1.0E-7|false|i=1;won=true;active=null;progress=8.0;snap=8.0
PRACTICE|139||MOVE:-0.0|false|i=1;won=true;active=null;progress=8.0;snap=8.0
PRACTICE|139||MOVE:-0.0|false|i=1;won=true;active=null;progress=8.0;snap=8.0
PRACTICE|139||BASKET:-1.0|false|i=1;won=true;active=null;progress=8.0;snap=8.0
PRACTICE|139||MOVE:0.0|false|i=1;won=true;active=null;progress=8.0;snap=8.0
PRACTICE|139||PASS:-1.0|false|i=1;won=true;active=null;progress=8.0;snap=8.0
PRACTICE|139||MOVE:3.0|false|i=1;won=true;active=null;progress=8.0;snap=8.0
PRACTICE|139|1.5,NaN,-0.0,1.0E9|init|-|i=0;won=false;active=PASS;progress=1.5;snap=1.5
PRACTICE|139|1.5,NaN,-0.0,1.0E9|PASS:0.9999995|false|i=0;won=false;active=PASS;progress=2.4999995;snap=2.4999995
PRACTICE|139|1.5,NaN,-0.0,1.0E9|PASS:-1.0|false|i=0;won=false;active=PASS;progress=2.4999995;snap=2.4999995
PRACTICE|139|1.5,NaN,-0.0,1.0E9|PASS:3.0|false|i=0;won=false;active=PASS;progress=5.4999994999999995;snap=5.4999994999999995
PRACTICE|139|1.5,NaN,-0.0,1.0E9|PASS:NaN|false|i=0;won=false;active=PASS;progress=5.4999994999999995;snap=5.4999994999999995
PRACTICE|139|1.5,NaN,-0.0,1.0E9|PASS:3.0|true|i=1;won=true;active=null;progress=8.0;snap=8.0
PRACTICE|139|1.5,NaN,-0.0,1.0E9|MOVE:NaN|false|i=1;won=true;active=null;progress=8.0;snap=8.0
PRACTICE|139|1.5,NaN,-0.0,1.0E9|MOVE:-1.0|false|i=1;won=true;active=null;progress=8.0;snap=8.0
PRACTICE|139|1.5,NaN,-0.0,1.0E9|MOVE:0.0|false|i=1;won=true;active=null;progress=8.0;snap=8.0
PRACTICE|139|1.5,NaN,-0.0,1.0E9|MOVE:0.2|false|i=1;won=true;active=null;progress=8.0;snap=8.0
PRACTICE|139|1.5,NaN,-0.0,1.0E9|ALLEY:0.1|false|i=1;won=true;active=null;progress=8.0;snap=8.0
PRACTICE|139|1.5,NaN,-0.0,1.0E9|SCREEN:0.5|false|i=1;won=true;active=null;progress=8.0;snap=8.0
PRACTICE|139|1.5,NaN,-0.0,1.0E9|MOVE:1.0|false|i=1;won=true;active=null;progress=8.0;snap=8.0
PRACTICE|139|1.5,NaN,-0.0,1.0E9|SWITCH:0.5|false|i=1;won=true;active=null;progress=8.0;snap=8.0
PRACTICE|139|1.5,NaN,-0.0,1.0E9|MOVE:1.0E-7|false|i=1;won=true;active=null;progress=8.0;snap=8.0
PRACTICE|139|1.5,NaN,-0.0,1.0E9|MOVE:1.0E-7|false|i=1;won=true;active=null;progress=8.0;snap=8.0
PRACTICE|139|1.5,NaN,-0.0,1.0E9|MOVE:3.0|false|i=1;won=true;active=null;progress=8.0;snap=8.0
PRACTICE|139|1.5,NaN,-0.0,1.0E9|SCREEN:0.9999995|false|i=1;won=true;active=null;progress=8.0;snap=8.0
PRACTICE|139|1.5,NaN,-0.0,1.0E9|MOVE:3.0|false|i=1;won=true;active=null;progress=8.0;snap=8.0
PRACTICE|139|1.5,NaN,-0.0,1.0E9|SCREEN:0.1|false|i=1;won=true;active=null;progress=8.0;snap=8.0
PRACTICE|139|1.5,NaN,-0.0,1.0E9|MOVE:0.0|false|i=1;won=true;active=null;progress=8.0;snap=8.0
PRACTICE_DEFAULT|false;i=0;won=false;active=PASS;progress=1.0;snap=1.0
HL|0|5|-1|new|-|HUMAN;HUMAN;null;0;0;null;false;true
HL|0|5|0|config:HUMAN:KIDS_ARITHMETIC:FREE_5|-|HUMAN;HUMAN;HUMAN/KIDS_ARITHMETIC/FREE_5/false;0;0;null;false;false
HL|0|5|1|resolve:HUMAN:true:false|SETTER_FAILED;HUMAN;true;false;false|BOT;BOT;null;0;0;null;false;true
HL|0|5|2|config:BOT:SCIENCE:FREE_4|-|BOT;BOT;BOT/SCIENCE/FREE_4/false;0;0;null;false;false
HL|0|5|3|resolve:BOT:false:false|SETTER_FAILED;BOT;false;false;false|HUMAN;HUMAN;null;0;0;null;false;true
HL|0|5|4|config:HUMAN:HISTORY:FREE_15|-|HUMAN;HUMAN;HUMAN/HISTORY/FREE_15/false;0;0;null;false;false
HL|0|5|5|resolve:HUMAN:true:true|CHALLENGE_ESTABLISHED;HUMAN;true;true;false|HUMAN;BOT;HUMAN/HISTORY/FREE_15/true;0;0;null;false;false
HL|0|5|6|resolve:BOT:false:true|CONTINUE_WITH_PENALTY;BOT;false;true;true|HUMAN;HUMAN;HUMAN/HISTORY/FREE_15/true;0;1;null;false;false
HL|0|5|7|resolve:HUMAN:true:false|CHALLENGE_ENDED_NO_PENALTY;HUMAN;true;false;false|BOT;BOT;null;0;1;null;false;true
HL|0|5|8|config:BOT:MATRICULATION_MATH:FREE_38|-|BOT;BOT;BOT/MATRICULATION_MATH/FREE_38/false;0;1;null;false;false
HL|0|5|9|resolve:BOT:true:true|CHALLENGE_ESTABLISHED;BOT;true;true;false|BOT;HUMAN;BOT/MATRICULATION_MATH/FREE_38/true;0;1;null;false;false
HL|0|5|10|resolve:HUMAN:true:true|CONTINUE_NO_PENALTY;HUMAN;true;true;false|BOT;BOT;BOT/MATRICULATION_MATH/FREE_38/true;0;1;null;false;false
HL|0|5|11|resolve:BOT:false:false|CHALLENGE_ENDED_WITH_PENALTY;BOT;false;false;true|HUMAN;HUMAN;null;0;2;null;false;true
HL|0|5|12|config:HUMAN:MATH:FREE_7|-|HUMAN;HUMAN;HUMAN/MATH/FREE_7/false;0;2;null;false;false
HL|0|5|13|resolve:HUMAN:true:true|CHALLENGE_ESTABLISHED;HUMAN;true;true;false|HUMAN;BOT;HUMAN/MATH/FREE_7/true;0;2;null;false;false
HL|0|5|14|resolve:BOT:false:true|CONTINUE_WITH_PENALTY;BOT;false;true;true|HUMAN;HUMAN;HUMAN/MATH/FREE_7/true;0;3;null;false;false
HL|0|5|15|resolve:HUMAN:false:false|CHALLENGE_ENDED_WITH_PENALTY;HUMAN;false;false;true|BOT;BOT;null;1;3;null;false;true
HL|0|5|16|config:BOT:GENERAL_KNOWLEDGE:FREE_34|-|BOT;BOT;BOT/GENERAL_KNOWLEDGE/FREE_34/false;1;3;null;false;false
HL|0|5|17|resolve:BOT:true:true|CHALLENGE_ESTABLISHED;BOT;true;true;false|BOT;HUMAN;BOT/GENERAL_KNOWLEDGE/FREE_34/true;1;3;null;false;false
HL|0|5|18|resolve:HUMAN:false:true|CONTINUE_WITH_PENALTY;HUMAN;false;true;true|BOT;BOT;BOT/GENERAL_KNOWLEDGE/FREE_34/true;2;3;null;false;false
HL|0|5|19|resolve:BOT:false:false|CHALLENGE_ENDED_WITH_PENALTY;BOT;false;false;true|HUMAN;HUMAN;null;2;4;null;false;true
HL|0|5|20|config:HUMAN:HISTORY:FREE_30|-|HUMAN;HUMAN;HUMAN/HISTORY/FREE_30/false;2;4;null;false;false
HL|0|5|21|resolve:HUMAN:false:false|SETTER_FAILED;HUMAN;false;false;false|BOT;BOT;null;2;4;null;false;true
HL|0|5|22|config:BOT:KIDS_ARITHMETIC:FREE_12|-|BOT;BOT;BOT/KIDS_ARITHMETIC/FREE_12/false;2;4;null;false;false
HL|0|5|23|resolve:BOT:true:true|CHALLENGE_ESTABLISHED;BOT;true;true;false|BOT;HUMAN;BOT/KIDS_ARITHMETIC/FREE_12/true;2;4;null;false;false
HL|0|5|24|resolve:HUMAN:false:true|CONTINUE_WITH_PENALTY;HUMAN;false;true;true|BOT;BOT;BOT/KIDS_ARITHMETIC/FREE_12/true;3;4;null;false;false
HL|0|5|25|resolve:BOT:true:true|CONTINUE_NO_PENALTY;BOT;true;true;false|BOT;HUMAN;BOT/KIDS_ARITHMETIC/FREE_12/true;3;4;null;false;false
HL|0|5|26|resolve:HUMAN:true:true|CONTINUE_NO_PENALTY;HUMAN;true;true;false|BOT;BOT;BOT/KIDS_ARITHMETIC/FREE_12/true;3;4;null;false;false
HL|0|5|27|resolve:BOT:false:true|GAME_OVER;BOT;false;true;true|BOT;BOT;BOT/KIDS_ARITHMETIC/FREE_12/true;3;5;HUMAN;true;false
HL|3|2|-1|new|-|HUMAN;HUMAN;null;0;0;null;false;true
HL|3|2|0|config:HUMAN:PROGRAMMING:FREE_40|-|HUMAN;HUMAN;HUMAN/PROGRAMMING/FREE_40/false;0;0;null;false;false
HL|3|2|1|resolve:HUMAN:true:true|CHALLENGE_ESTABLISHED;HUMAN;true;true;false|HUMAN;BOT;HUMAN/PROGRAMMING/FREE_40/true;0;0;null;false;false
HL|3|2|2|resolve:BOT:false:true|CONTINUE_WITH_PENALTY;BOT;false;true;true|HUMAN;HUMAN;HUMAN/PROGRAMMING/FREE_40/true;0;1;null;false;false
HL|3|2|3|resolve:HUMAN:true:false|CHALLENGE_ENDED_NO_PENALTY;HUMAN;true;false;false|BOT;BOT;null;0;1;null;false;true
HL|3|2|4|config:BOT:HISTORY:FREE_3|-|BOT;BOT;BOT/HISTORY/FREE_3/false;0;1;null;false;false
HL|3|2|5|resolve:BOT:true:true|CHALLENGE_ESTABLISHED;BOT;true;true;false|BOT;HUMAN;BOT/HISTORY/FREE_3/true;0;1;null;false;false
HL|3|2|6|resolve:HUMAN:true:false|CHALLENGE_ENDED_NO_PENALTY;HUMAN;true;false;false|BOT;BOT;null;0;1;null;false;true
HL|3|2|7|config:BOT:SCIENCE:FREE_39|-|BOT;BOT;BOT/SCIENCE/FREE_39/false;0;1;null;false;false
HL|3|2|8|resolve:BOT:true:false|SETTER_FAILED;BOT;true;false;false|HUMAN;HUMAN;null;0;1;null;false;true
HL|3|2|9|config:HUMAN:PARADOX:FREE_35|-|HUMAN;HUMAN;HUMAN/PARADOX/FREE_35/false;0;1;null;false;false
HL|3|2|10|resolve:HUMAN:true:false|SETTER_FAILED;HUMAN;true;false;false|BOT;BOT;null;0;1;null;false;true
HL|3|2|11|config:BOT:GENERAL_KNOWLEDGE:FREE_27|-|BOT;BOT;BOT/GENERAL_KNOWLEDGE/FREE_27/false;0;1;null;false;false
HL|3|2|12|resolve:BOT:false:true|SETTER_FAILED;BOT;false;true;false|HUMAN;HUMAN;null;0;1;null;false;true
HL|3|2|13|config:HUMAN:ENGLISH:FREE_20|-|HUMAN;HUMAN;HUMAN/ENGLISH/FREE_20/false;0;1;null;false;false
HL|3|2|14|resolve:HUMAN:true:false|SETTER_FAILED;HUMAN;true;false;false|BOT;BOT;null;0;1;null;false;true
HL|3|2|15|config:BOT:GENERAL_KNOWLEDGE:FREE_26|-|BOT;BOT;BOT/GENERAL_KNOWLEDGE/FREE_26/false;0;1;null;false;false
HL|3|2|16|resolve:BOT:true:false|SETTER_FAILED;BOT;true;false;false|HUMAN;HUMAN;null;0;1;null;false;true
HL|3|2|17|config:HUMAN:PARADOX:FREE_27|-|HUMAN;HUMAN;HUMAN/PARADOX/FREE_27/false;0;1;null;false;false
HL|3|2|18|resolve:HUMAN:true:true|CHALLENGE_ESTABLISHED;HUMAN;true;true;false|HUMAN;BOT;HUMAN/PARADOX/FREE_27/true;0;1;null;false;false
HL|3|2|19|resolve:BOT:true:true|CONTINUE_NO_PENALTY;BOT;true;true;false|HUMAN;HUMAN;HUMAN/PARADOX/FREE_27/true;0;1;null;false;false
HL|3|2|20|resolve:HUMAN:true:true|CONTINUE_NO_PENALTY;HUMAN;true;true;false|HUMAN;BOT;HUMAN/PARADOX/FREE_27/true;0;1;null;false;false
HL|3|2|21|resolve:BOT:true:false|CHALLENGE_ENDED_NO_PENALTY;BOT;true;false;false|HUMAN;HUMAN;null;0;1;null;false;true
HL|3|2|22|config:HUMAN:ENGLISH:FREE_15|-|HUMAN;HUMAN;HUMAN/ENGLISH/FREE_15/false;0;1;null;false;false
HL|3|2|23|resolve:HUMAN:false:false|SETTER_FAILED;HUMAN;false;false;false|BOT;BOT;null;0;1;null;false;true
HL|3|2|24|config:BOT:SCIENCE:FREE_34|-|BOT;BOT;BOT/SCIENCE/FREE_34/false;0;1;null;false;false
HL|3|2|25|resolve:BOT:true:true|CHALLENGE_ESTABLISHED;BOT;true;true;false|BOT;HUMAN;BOT/SCIENCE/FREE_34/true;0;1;null;false;false
HL|3|2|26|resolve:HUMAN:true:true|CONTINUE_NO_PENALTY;HUMAN;true;true;false|BOT;BOT;BOT/SCIENCE/FREE_34/true;0;1;null;false;false
HL|3|2|27|resolve:BOT:true:true|CONTINUE_NO_PENALTY;BOT;true;true;false|BOT;HUMAN;BOT/SCIENCE/FREE_34/true;0;1;null;false;false
HL|3|2|28|resolve:HUMAN:true:true|CONTINUE_NO_PENALTY;HUMAN;true;true;false|BOT;BOT;BOT/SCIENCE/FREE_34/true;0;1;null;false;false
HL|3|2|29|resolve:BOT:true:false|CHALLENGE_ENDED_NO_PENALTY;BOT;true;false;false|HUMAN;HUMAN;null;0;1;null;false;true
HL|3|2|30|config:HUMAN:HISTORY:FREE_5|-|HUMAN;HUMAN;HUMAN/HISTORY/FREE_5/false;0;1;null;false;false
HL|3|2|31|resolve:HUMAN:true:true|CHALLENGE_ESTABLISHED;HUMAN;true;true;false|HUMAN;BOT;HUMAN/HISTORY/FREE_5/true;0;1;null;false;false
HL|3|2|32|resolve:BOT:true:true|CONTINUE_NO_PENALTY;BOT;true;true;false|HUMAN;HUMAN;HUMAN/HISTORY/FREE_5/true;0;1;null;false;false
HL|3|2|33|resolve:HUMAN:true:true|CONTINUE_NO_PENALTY;HUMAN;true;true;false|HUMAN;BOT;HUMAN/HISTORY/FREE_5/true;0;1;null;false;false
HL|3|2|34|resolve:BOT:true:true|CONTINUE_NO_PENALTY;BOT;true;true;false|HUMAN;HUMAN;HUMAN/HISTORY/FREE_5/true;0;1;null;false;false
HL|3|2|35|resolve:HUMAN:true:false|CHALLENGE_ENDED_NO_PENALTY;HUMAN;true;false;false|BOT;BOT;null;0;1;null;false;true
HL|3|2|36|config:BOT:HISTORY:FREE_3|-|BOT;BOT;BOT/HISTORY/FREE_3/false;0;1;null;false;false
HL|3|2|37|resolve:BOT:true:false|SETTER_FAILED;BOT;true;false;false|HUMAN;HUMAN;null;0;1;null;false;true
HL|3|2|38|config:HUMAN:ENGLISH:FREE_22|-|HUMAN;HUMAN;HUMAN/ENGLISH/FREE_22/false;0;1;null;false;false
HL|3|2|39|resolve:HUMAN:false:true|SETTER_FAILED;HUMAN;false;true;false|BOT;BOT;null;0;1;null;false;true
HL|3|2|40|config:BOT:KIDS_ARITHMETIC:FREE_30|-|BOT;BOT;BOT/KIDS_ARITHMETIC/FREE_30/false;0;1;null;false;false
HL|3|2|41|resolve:BOT:true:false|SETTER_FAILED;BOT;true;false;false|HUMAN;HUMAN;null;0;1;null;false;true
HL|3|2|42|config:HUMAN:SCIENCE:FREE_30|-|HUMAN;HUMAN;HUMAN/SCIENCE/FREE_30/false;0;1;null;false;false
HL|3|2|43|resolve:HUMAN:false:true|SETTER_FAILED;HUMAN;false;true;false|BOT;BOT;null;0;1;null;false;true
HL|3|2|44|config:BOT:HISTORY:FREE_16|-|BOT;BOT;BOT/HISTORY/FREE_16/false;0;1;null;false;false
HL|3|2|45|resolve:BOT:false:false|SETTER_FAILED;BOT;false;false;false|HUMAN;HUMAN;null;0;1;null;false;true
HL|3|2|46|config:HUMAN:AI:FREE_39|-|HUMAN;HUMAN;HUMAN/AI/FREE_39/false;0;1;null;false;false
HL|3|2|47|resolve:HUMAN:true:true|CHALLENGE_ESTABLISHED;HUMAN;true;true;false|HUMAN;BOT;HUMAN/AI/FREE_39/true;0;1;null;false;false
HL|3|2|48|resolve:BOT:false:false|GAME_OVER;BOT;false;false;true|HUMAN;BOT;HUMAN/AI/FREE_39/true;0;2;HUMAN;true;false
HL|4|1|-1|new|-|HUMAN;HUMAN;null;0;0;null;false;true
HL|4|1|0|config:HUMAN:KIDS_ARITHMETIC:FREE_1|-|HUMAN;HUMAN;HUMAN/KIDS_ARITHMETIC/FREE_1/false;0;0;null;false;false
HL|4|1|1|resolve:HUMAN:false:false|SETTER_FAILED;HUMAN;false;false;false|BOT;BOT;null;0;0;null;false;true
HL|4|1|2|config:BOT:KIDS_ARITHMETIC:FREE_25|-|BOT;BOT;BOT/KIDS_ARITHMETIC/FREE_25/false;0;0;null;false;false
HL|4|1|3|resolve:BOT:false:false|SETTER_FAILED;BOT;false;false;false|HUMAN;HUMAN;null;0;0;null;false;true
HL|4|1|4|config:HUMAN:MATRICULATION_MATH:FREE_1|-|HUMAN;HUMAN;HUMAN/MATRICULATION_MATH/FREE_1/false;0;0;null;false;false
HL|4|1|5|resolve:HUMAN:true:false|SETTER_FAILED;HUMAN;true;false;false|BOT;BOT;null;0;0;null;false;true
HL|4|1|6|config:BOT:ASTRONOMY:FREE_8|-|BOT;BOT;BOT/ASTRONOMY/FREE_8/false;0;0;null;false;false
HL|4|1|7|resolve:BOT:true:true|CHALLENGE_ESTABLISHED;BOT;true;true;false|BOT;HUMAN;BOT/ASTRONOMY/FREE_8/true;0;0;null;false;false
HL|4|1|8|resolve:HUMAN:true:true|CONTINUE_NO_PENALTY;HUMAN;true;true;false|BOT;BOT;BOT/ASTRONOMY/FREE_8/true;0;0;null;false;false
HL|4|1|9|resolve:BOT:true:true|CONTINUE_NO_PENALTY;BOT;true;true;false|BOT;HUMAN;BOT/ASTRONOMY/FREE_8/true;0;0;null;false;false
HL|4|1|10|resolve:HUMAN:false:false|GAME_OVER;HUMAN;false;false;true|BOT;HUMAN;BOT/ASTRONOMY/FREE_8/true;1;0;BOT;true;false
HL|7|4|-1|new|-|HUMAN;HUMAN;null;0;0;null;false;true
HL|7|4|0|config:HUMAN:ENGLISH:FREE_48|-|HUMAN;HUMAN;HUMAN/ENGLISH/FREE_48/false;0;0;null;false;false
HL|7|4|1|resolve:HUMAN:true:false|SETTER_FAILED;HUMAN;true;false;false|BOT;BOT;null;0;0;null;false;true
HL|7|4|2|config:BOT:PARADOX:FREE_35|-|BOT;BOT;BOT/PARADOX/FREE_35/false;0;0;null;false;false
HL|7|4|3|resolve:BOT:true:false|SETTER_FAILED;BOT;true;false;false|HUMAN;HUMAN;null;0;0;null;false;true
HL|7|4|4|config:HUMAN:GENERAL_KNOWLEDGE:FREE_5|-|HUMAN;HUMAN;HUMAN/GENERAL_KNOWLEDGE/FREE_5/false;0;0;null;false;false
HL|7|4|5|resolve:HUMAN:false:true|SETTER_FAILED;HUMAN;false;true;false|BOT;BOT;null;0;0;null;false;true
HL|7|4|6|config:BOT:SCIENCE:FREE_21|-|BOT;BOT;BOT/SCIENCE/FREE_21/false;0;0;null;false;false
HL|7|4|7|resolve:BOT:true:false|SETTER_FAILED;BOT;true;false;false|HUMAN;HUMAN;null;0;0;null;false;true
HL|7|4|8|config:HUMAN:SCIENCE:FREE_2|-|HUMAN;HUMAN;HUMAN/SCIENCE/FREE_2/false;0;0;null;false;false
HL|7|4|9|resolve:HUMAN:true:true|CHALLENGE_ESTABLISHED;HUMAN;true;true;false|HUMAN;BOT;HUMAN/SCIENCE/FREE_2/true;0;0;null;false;false
HL|7|4|10|resolve:BOT:true:true|CONTINUE_NO_PENALTY;BOT;true;true;false|HUMAN;HUMAN;HUMAN/SCIENCE/FREE_2/true;0;0;null;false;false
HL|7|4|11|resolve:HUMAN:false:true|CONTINUE_WITH_PENALTY;HUMAN;false;true;true|HUMAN;BOT;HUMAN/SCIENCE/FREE_2/true;1;0;null;false;false
HL|7|4|12|resolve:BOT:true:false|CHALLENGE_ENDED_NO_PENALTY;BOT;true;false;false|HUMAN;HUMAN;null;1;0;null;false;true
HL|7|4|13|config:HUMAN:MATH:FREE_27|-|HUMAN;HUMAN;HUMAN/MATH/FREE_27/false;1;0;null;false;false
HL|7|4|14|resolve:HUMAN:true:false|SETTER_FAILED;HUMAN;true;false;false|BOT;BOT;null;1;0;null;false;true
HL|7|4|15|config:BOT:GENERAL_KNOWLEDGE:FREE_21|-|BOT;BOT;BOT/GENERAL_KNOWLEDGE/FREE_21/false;1;0;null;false;false
HL|7|4|16|resolve:BOT:true:true|CHALLENGE_ESTABLISHED;BOT;true;true;false|BOT;HUMAN;BOT/GENERAL_KNOWLEDGE/FREE_21/true;1;0;null;false;false
HL|7|4|17|resolve:HUMAN:true:false|CHALLENGE_ENDED_NO_PENALTY;HUMAN;true;false;false|BOT;BOT;null;1;0;null;false;true
HL|7|4|18|config:BOT:ENGLISH:FREE_41|-|BOT;BOT;BOT/ENGLISH/FREE_41/false;1;0;null;false;false
HL|7|4|19|resolve:BOT:false:true|SETTER_FAILED;BOT;false;true;false|HUMAN;HUMAN;null;1;0;null;false;true
HL|7|4|20|config:HUMAN:ASTRONOMY:FREE_40|-|HUMAN;HUMAN;HUMAN/ASTRONOMY/FREE_40/false;1;0;null;false;false
HL|7|4|21|resolve:HUMAN:false:false|SETTER_FAILED;HUMAN;false;false;false|BOT;BOT;null;1;0;null;false;true
HL|7|4|22|config:BOT:SCIENCE:FREE_43|-|BOT;BOT;BOT/SCIENCE/FREE_43/false;1;0;null;false;false
HL|7|4|23|resolve:BOT:true:true|CHALLENGE_ESTABLISHED;BOT;true;true;false|BOT;HUMAN;BOT/SCIENCE/FREE_43/true;1;0;null;false;false
HL|7|4|24|resolve:HUMAN:false:true|CONTINUE_WITH_PENALTY;HUMAN;false;true;true|BOT;BOT;BOT/SCIENCE/FREE_43/true;2;0;null;false;false
HL|7|4|25|resolve:BOT:true:true|CONTINUE_NO_PENALTY;BOT;true;true;false|BOT;HUMAN;BOT/SCIENCE/FREE_43/true;2;0;null;false;false
HL|7|4|26|resolve:HUMAN:true:false|CHALLENGE_ENDED_NO_PENALTY;HUMAN;true;false;false|BOT;BOT;null;2;0;null;false;true
HL|7|4|27|config:BOT:SCIENCE:FREE_18|-|BOT;BOT;BOT/SCIENCE/FREE_18/false;2;0;null;false;false
HL|7|4|28|resolve:BOT:false:true|SETTER_FAILED;BOT;false;true;false|HUMAN;HUMAN;null;2;0;null;false;true
HL|7|4|29|config:HUMAN:SCIENCE:FREE_30|-|HUMAN;HUMAN;HUMAN/SCIENCE/FREE_30/false;2;0;null;false;false
HL|7|4|30|resolve:HUMAN:true:true|CHALLENGE_ESTABLISHED;HUMAN;true;true;false|HUMAN;BOT;HUMAN/SCIENCE/FREE_30/true;2;0;null;false;false
HL|7|4|31|resolve:BOT:true:false|CHALLENGE_ENDED_NO_PENALTY;BOT;true;false;false|HUMAN;HUMAN;null;2;0;null;false;true
HL|7|4|32|config:HUMAN:PROGRAMMING:FREE_7|-|HUMAN;HUMAN;HUMAN/PROGRAMMING/FREE_7/false;2;0;null;false;false
HL|7|4|33|resolve:HUMAN:false:true|SETTER_FAILED;HUMAN;false;true;false|BOT;BOT;null;2;0;null;false;true
HL|7|4|34|config:BOT:MATH:FREE_25|-|BOT;BOT;BOT/MATH/FREE_25/false;2;0;null;false;false
HL|7|4|35|resolve:BOT:true:true|CHALLENGE_ESTABLISHED;BOT;true;true;false|BOT;HUMAN;BOT/MATH/FREE_25/true;2;0;null;false;false
HL|7|4|36|resolve:HUMAN:true:true|CONTINUE_NO_PENALTY;HUMAN;true;true;false|BOT;BOT;BOT/MATH/FREE_25/true;2;0;null;false;false
HL|7|4|37|resolve:BOT:false:true|CONTINUE_WITH_PENALTY;BOT;false;true;true|BOT;HUMAN;BOT/MATH/FREE_25/true;2;1;null;false;false
HL|7|4|38|resolve:HUMAN:true:true|CONTINUE_NO_PENALTY;HUMAN;true;true;false|BOT;BOT;BOT/MATH/FREE_25/true;2;1;null;false;false
HL|7|4|39|resolve:BOT:false:true|CONTINUE_WITH_PENALTY;BOT;false;true;true|BOT;HUMAN;BOT/MATH/FREE_25/true;2;2;null;false;false
HL|7|4|40|resolve:HUMAN:true:true|CONTINUE_NO_PENALTY;HUMAN;true;true;false|BOT;BOT;BOT/MATH/FREE_25/true;2;2;null;false;false
HL|7|4|41|resolve:BOT:false:false|CHALLENGE_ENDED_WITH_PENALTY;BOT;false;false;true|HUMAN;HUMAN;null;2;3;null;false;true
HL|7|4|42|config:HUMAN:ENGLISH:FREE_5|-|HUMAN;HUMAN;HUMAN/ENGLISH/FREE_5/false;2;3;null;false;false
HL|7|4|43|resolve:HUMAN:false:false|SETTER_FAILED;HUMAN;false;false;false|BOT;BOT;null;2;3;null;false;true
HL|7|4|44|config:BOT:GENERAL_KNOWLEDGE:FREE_11|-|BOT;BOT;BOT/GENERAL_KNOWLEDGE/FREE_11/false;2;3;null;false;false
HL|7|4|45|resolve:BOT:true:true|CHALLENGE_ESTABLISHED;BOT;true;true;false|BOT;HUMAN;BOT/GENERAL_KNOWLEDGE/FREE_11/true;2;3;null;false;false
HL|7|4|46|resolve:HUMAN:true:true|CONTINUE_NO_PENALTY;HUMAN;true;true;false|BOT;BOT;BOT/GENERAL_KNOWLEDGE/FREE_11/true;2;3;null;false;false
HL|7|4|47|resolve:BOT:true:true|CONTINUE_NO_PENALTY;BOT;true;true;false|BOT;HUMAN;BOT/GENERAL_KNOWLEDGE/FREE_11/true;2;3;null;false;false
HL|7|4|48|resolve:HUMAN:true:true|CONTINUE_NO_PENALTY;HUMAN;true;true;false|BOT;BOT;BOT/GENERAL_KNOWLEDGE/FREE_11/true;2;3;null;false;false
HL|7|4|49|resolve:BOT:false:false|GAME_OVER;BOT;false;false;true|BOT;BOT;BOT/GENERAL_KNOWLEDGE/FREE_11/true;2;4;HUMAN;true;false
HL_BOTFIRST|BOT;BOT;null;0;0;null;false;true
HV|0|5|-1|init:a,b:a|-|SETTING;a;a;false;;;00000000;00000000;a,b;;a=0,b=0;;;1;0;false
HV|0|5|0|config:a:ASTRONOMY:FREE_98:4440f289:42e1e1b4|-|ATTEMPT;a;a;false;ASTRONOMY;FREE_98;4440f289;42e1e1b4;a,b;;a=0,b=0;;;2;0;false
HV|0|5|1|resolve:a:false:true|false;null;true|SETTING;b;b;false;;;00000000;00000000;a,b;;a=0,b=0;;;3;0;false
HV|0|5|2|config:b:SCIENCE:FREE_69:44702edd:44a46f86|-|ATTEMPT;b;b;false;SCIENCE;FREE_69;44702edd;44a46f86;a,b;;a=0,b=0;;;4;0;false
HV|0|5|3|resolve:b:false:false|false;null;true|SETTING;a;a;false;;;00000000;00000000;a,b;;a=0,b=0;;;5;0;false
HV|0|5|4|config:a:MATRICULATION_MATH:FREE_10:4327889c:433a954c|-|ATTEMPT;a;a;false;MATRICULATION_MATH;FREE_10;4327889c;433a954c;a,b;;a=0,b=0;;;6;0;false
HV|0|5|5|resolve:a:false:true|false;null;true|SETTING;b;b;false;;;00000000;00000000;a,b;;a=0,b=0;;;7;0;false
HV|0|5|6|config:b:PARADOX:FREE_64:44438eeb:44aaf270|-|ATTEMPT;b;b;false;PARADOX;FREE_64;44438eeb;44aaf270;a,b;;a=0,b=0;;;8;0;false
HV|0|5|7|resolve:b:false:false|false;null;true|SETTING;a;a;false;;;00000000;00000000;a,b;;a=0,b=0;;;9;0;false
HV|0|5|8|config:a:ENGLISH:FREE_70:44725666:4451c188|-|ATTEMPT;a;a;false;ENGLISH;FREE_70;44725666;4451c188;a,b;;a=0,b=0;;;10;0;false
HV|0|5|9|resolve:a:true:true|false;null;false|ATTEMPT;a;b;true;ENGLISH;FREE_70;44725666;4451c188;a,b;;a=0,b=0;;;11;0;false
HV|0|5|10|resolve:b:false:false|true;null;true|SETTING;a;a;false;;;00000000;00000000;a,b;;a=0,b=1;;;12;0;false
HV|0|5|11|config:a:HISTORY:FREE_4:43e39cec:4459d601|-|ATTEMPT;a;a;false;HISTORY;FREE_4;43e39cec;4459d601;a,b;;a=0,b=1;;;13;0;false
HV|0|5|12|resolve:a:true:true|false;null;false|ATTEMPT;a;b;true;HISTORY;FREE_4;43e39cec;4459d601;a,b;;a=0,b=1;;;14;0;false
HV|0|5|13|resolve:b:true:false|false;null;true|SETTING;a;a;false;;;00000000;00000000;a,b;;a=0,b=1;;;15;0;false
HV|0|5|14|config:a:AI:FREE_32:443f632d:43f55cfe|-|ATTEMPT;a;a;false;AI;FREE_32;443f632d;43f55cfe;a,b;;a=0,b=1;;;16;0;false
HV|0|5|15|resolve:a:true:false|false;null;true|SETTING;b;b;false;;;00000000;00000000;a,b;;a=0,b=1;;;17;0;false
HV|0|5|16|config:b:HISTORY:FREE_42:43b0f4e8:44af5a3c|-|ATTEMPT;b;b;false;HISTORY;FREE_42;43b0f4e8;44af5a3c;a,b;;a=0,b=1;;;18;0;false
HV|0|5|17|resolve:b:true:true|false;null;false|ATTEMPT;b;a;true;HISTORY;FREE_42;43b0f4e8;44af5a3c;a,b;;a=0,b=1;;;19;0;false
HV|0|5|18|resolve:a:false:true|true;null;true|SETTING;a;a;false;;;00000000;00000000;a,b;;a=1,b=1;;;20;0;false
HV|0|5|19|config:a:MATRICULATION_MATH:FREE_2:440d843a:44a9baa0|-|ATTEMPT;a;a;false;MATRICULATION_MATH;FREE_2;440d843a;44a9baa0;a,b;;a=1,b=1;;;21;0;false
HV|0|5|20|resolve:a:true:true|false;null;false|ATTEMPT;a;b;true;MATRICULATION_MATH;FREE_2;440d843a;44a9baa0;a,b;;a=1,b=1;;;22;0;false
HV|0|5|21|resolve:b:false:true|true;null;true|SETTING;b;b;false;;;00000000;00000000;a,b;;a=1,b=2;;;23;0;false
HV|0|5|22|config:b:ENGLISH:FREE_32:4425c1e7:423c0f10|-|ATTEMPT;b;b;false;ENGLISH;FREE_32;4425c1e7;423c0f10;a,b;;a=1,b=2;;;24;0;false
HV|0|5|23|resolve:b:false:false|false;null;true|SETTING;a;a;false;;;00000000;00000000;a,b;;a=1,b=2;;;25;0;false
HV|0|5|24|config:a:ASTRONOMY:FREE_39:44238e34:425a82c0|-|ATTEMPT;a;a;false;ASTRONOMY;FREE_39;44238e34;425a82c0;a,b;;a=1,b=2;;;26;0;false
HV|0|5|25|resolve:a:true:true|false;null;false|ATTEMPT;a;b;true;ASTRONOMY;FREE_39;44238e34;425a82c0;a,b;;a=1,b=2;;;27;0;false
HV|0|5|26|resolve:b:true:false|false;null;true|SETTING;a;a;false;;;00000000;00000000;a,b;;a=1,b=2;;;28;0;false
HV|0|5|27|config:a:ENGLISH:FREE_2:4450f3bf:4244f0f8|-|ATTEMPT;a;a;false;ENGLISH;FREE_2;4450f3bf;4244f0f8;a,b;;a=1,b=2;;;29;0;false
HV|0|5|28|resolve:a:false:true|false;null;true|SETTING;b;b;false;;;00000000;00000000;a,b;;a=1,b=2;;;30;0;false
HV|0|5|29|config:b:HISTORY:FREE_16:44341ea1:448e1075|-|ATTEMPT;b;b;false;HISTORY;FREE_16;44341ea1;448e1075;a,b;;a=1,b=2;;;31;0;false
HV|0|5|30|resolve:b:true:true|false;null;false|ATTEMPT;b;a;true;HISTORY;FREE_16;44341ea1;448e1075;a,b;;a=1,b=2;;;32;0;false
HV|0|5|31|resolve:a:true:false|false;null;true|SETTING;b;b;false;;;00000000;00000000;a,b;;a=1,b=2;;;33;0;false
HV|0|5|32|config:b:HISTORY:FREE_89:430db200:4447deee|-|ATTEMPT;b;b;false;HISTORY;FREE_89;430db200;4447deee;a,b;;a=1,b=2;;;34;0;false
HV|0|5|33|resolve:b:false:true|false;null;true|SETTING;a;a;false;;;00000000;00000000;a,b;;a=1,b=2;;;35;0;false
HV|0|5|34|config:a:ASTRONOMY:FREE_19:42c308c8:43c3ccd2|-|ATTEMPT;a;a;false;ASTRONOMY;FREE_19;42c308c8;43c3ccd2;a,b;;a=1,b=2;;;36;0;false
HV|0|5|35|resolve:a:true:true|false;null;false|ATTEMPT;a;b;true;ASTRONOMY;FREE_19;42c308c8;43c3ccd2;a,b;;a=1,b=2;;;37;0;false
HV|0|5|36|resolve:b:true:true|false;null;true|SETTING;b;b;false;;;00000000;00000000;a,b;;a=1,b=2;;;38;0;false
HV|0|5|37|config:b:KIDS_ARITHMETIC:FREE_74:43a4851a:444f9f60|-|ATTEMPT;b;b;false;KIDS_ARITHMETIC;FREE_74;43a4851a;444f9f60;a,b;;a=1,b=2;;;39;0;false
HV|0|5|38|resolve:b:true:false|false;null;true|SETTING;a;a;false;;;00000000;00000000;a,b;;a=1,b=2;;;40;0;false
HV|0|5|39|config:a:MATRICULATION_MATH:FREE_46:43c11014:43895e75|-|ATTEMPT;a;a;false;MATRICULATION_MATH;FREE_46;43c11014;43895e75;a,b;;a=1,b=2;;;41;0;false
HV|0|5|40|resolve:a:false:true|false;null;true|SETTING;b;b;false;;;00000000;00000000;a,b;;a=1,b=2;;;42;0;false
HV|0|5|41|config:b:PROGRAMMING:FREE_91:438d37d6:44a2b669|-|ATTEMPT;b;b;false;PROGRAMMING;FREE_91;438d37d6;44a2b669;a,b;;a=1,b=2;;;43;0;false
HV|0|5|42|resolve:b:true:true|false;null;false|ATTEMPT;b;a;true;PROGRAMMING;FREE_91;438d37d6;44a2b669;a,b;;a=1,b=2;;;44;0;false
HV|0|5|43|resolve:a:true:true|false;null;true|SETTING;a;a;false;;;00000000;00000000;a,b;;a=1,b=2;;;45;0;false
HV|0|5|44|config:a:AI:FREE_72:445330cc:44561b77|-|ATTEMPT;a;a;false;AI;FREE_72;445330cc;44561b77;a,b;;a=1,b=2;;;46;0;false
HV|0|5|45|resolve:a:false:true|false;null;true|SETTING;b;b;false;;;00000000;00000000;a,b;;a=1,b=2;;;47;0;false
HV|0|5|46|config:b:SCIENCE:FREE_83:43fc4c4e:44622144|-|ATTEMPT;b;b;false;SCIENCE;FREE_83;43fc4c4e;44622144;a,b;;a=1,b=2;;;48;0;false
HV|0|5|47|resolve:b:true:true|false;null;false|ATTEMPT;b;a;true;SCIENCE;FREE_83;43fc4c4e;44622144;a,b;;a=1,b=2;;;49;0;false
HV|0|5|48|resolve:a:true:true|false;null;true|SETTING;a;a;false;;;00000000;00000000;a,b;;a=1,b=2;;;50;0;false
HV|2|2|-1|init:h,x,y,z:y|-|SETTING;y;y;false;;;00000000;00000000;h,x,y,z;;h=0,x=0,y=0,z=0;;;1;0;false
HV|2|2|0|config:y:ASTRONOMY:FREE_13:442c202b:4351a3fc|-|ATTEMPT;y;y;false;ASTRONOMY;FREE_13;442c202b;4351a3fc;h,x,y,z;;h=0,x=0,y=0,z=0;;;2;0;false
HV|2|2|1|resolve:y:false:true|false;null;true|SETTING;z;z;false;;;00000000;00000000;h,x,y,z;;h=0,x=0,y=0,z=0;;;3;0;false
HV|2|2|2|config:z:ASTRONOMY:FREE_52:441074c6:4427ec11|-|ATTEMPT;z;z;false;ASTRONOMY;FREE_52;441074c6;4427ec11;h,x,y,z;;h=0,x=0,y=0,z=0;;;4;0;false
HV|2|2|3|resolve:z:true:false|false;null;true|SETTING;h;h;false;;;00000000;00000000;h,x,y,z;;h=0,x=0,y=0,z=0;;;5;0;false
HV|2|2|4|config:h:ENGLISH:FREE_35:43a53d9a:420253d8|-|ATTEMPT;h;h;false;ENGLISH;FREE_35;43a53d9a;420253d8;h,x,y,z;;h=0,x=0,y=0,z=0;;;6;0;false
HV|2|2|5|resolve:h:true:true|false;null;false|ATTEMPT;h;x;true;ENGLISH;FREE_35;43a53d9a;420253d8;h,x,y,z;;h=0,x=0,y=0,z=0;;;7;0;false
HV|2|2|6|resolve:x:false:true|true;null;false|ATTEMPT;h;y;true;ENGLISH;FREE_35;43a53d9a;420253d8;h,x,y,z;x;h=0,x=1,y=0,z=0;;;8;0;false
HV|2|2|7|resolve:y:true:true|false;null;false|ATTEMPT;h;z;true;ENGLISH;FREE_35;43a53d9a;420253d8;h,x,y,z;x,y;h=0,x=1,y=0,z=0;;;9;0;false
HV|2|2|8|resolve:z:false:false|true;null;true|SETTING;h;h;false;;;00000000;00000000;h,x,y,z;;h=0,x=1,y=0,z=1;;;10;0;false
HV|2|2|9|config:h:SCIENCE:FREE_16:42c227a8:43a4ce14|-|ATTEMPT;h;h;false;SCIENCE;FREE_16;42c227a8;43a4ce14;h,x,y,z;;h=0,x=1,y=0,z=1;;;11;0;false
HV|2|2|10|resolve:h:true:false|false;null;true|SETTING;x;x;false;;;00000000;00000000;h,x,y,z;;h=0,x=1,y=0,z=1;;;12;0;false
HV|2|2|11|config:x:PARADOX:FREE_35:43e14cd2:420c78a0|-|ATTEMPT;x;x;false;PARADOX;FREE_35;43e14cd2;420c78a0;h,x,y,z;;h=0,x=1,y=0,z=1;;;13;0;false
HV|2|2|12|resolve:x:false:true|false;null;true|SETTING;y;y;false;;;00000000;00000000;h,x,y,z;;h=0,x=1,y=0,z=1;;;14;0;false
HV|2|2|13|config:y:PROGRAMMING:FREE_23:43db1ea0:448e8f9e|-|ATTEMPT;y;y;false;PROGRAMMING;FREE_23;43db1ea0;448e8f9e;h,x,y,z;;h=0,x=1,y=0,z=1;;;15;0;false
HV|2|2|14|resolve:y:false:true|false;null;true|SETTING;z;z;false;;;00000000;00000000;h,x,y,z;;h=0,x=1,y=0,z=1;;;16;0;false
HV|2|2|15|config:z:MATRICULATION_MATH:FREE_5:42ad9a18:44a8a3df|-|ATTEMPT;z;z;false;MATRICULATION_MATH;FREE_5;42ad9a18;44a8a3df;h,x,y,z;;h=0,x=1,y=0,z=1;;;17;0;false
HV|2|2|16|resolve:z:true:true|false;null;false|ATTEMPT;z;h;true;MATRICULATION_MATH;FREE_5;42ad9a18;44a8a3df;h,x,y,z;;h=0,x=1,y=0,z=1;;;18;0;false
HV|2|2|17|resolve:h:true:false|false;null;true|SETTING;x;x;false;;;00000000;00000000;h,x,y,z;;h=0,x=1,y=0,z=1;;;19;0;false
HV|2|2|18|config:x:PARADOX:FREE_39:44263f42:43dba947|-|ATTEMPT;x;x;false;PARADOX;FREE_39;44263f42;43dba947;h,x,y,z;;h=0,x=1,y=0,z=1;;;20;0;false
HV|2|2|19|resolve:x:true:true|false;null;false|ATTEMPT;x;y;true;PARADOX;FREE_39;44263f42;43dba947;h,x,y,z;;h=0,x=1,y=0,z=1;;;21;0;false
HV|2|2|20|resolve:y:true:false|false;null;true|SETTING;z;z;false;;;00000000;00000000;h,x,y,z;;h=0,x=1,y=0,z=1;;;22;0;false
HV|2|2|21|config:z:PARADOX:FREE_61:444e8288:43d0b65a|-|ATTEMPT;z;z;false;PARADOX;FREE_61;444e8288;43d0b65a;h,x,y,z;;h=0,x=1,y=0,z=1;;;23;0;false
HV|2|2|22|resolve:z:true:true|false;null;false|ATTEMPT;z;h;true;PARADOX;FREE_61;444e8288;43d0b65a;h,x,y,z;;h=0,x=1,y=0,z=1;;;24;0;false
HV|2|2|23|resolve:h:true:true|false;null;false|ATTEMPT;z;x;true;PARADOX;FREE_61;444e8288;43d0b65a;h,x,y,z;h;h=0,x=1,y=0,z=1;;;25;0;false
HV|2|2|24|resolve:x:true:false|false;null;true|SETTING;y;y;false;;;00000000;00000000;h,x,y,z;;h=0,x=1,y=0,z=1;;;26;0;false
HV|2|2|25|config:y:ENGLISH:FREE_40:4473413b:433d4c4a|-|ATTEMPT;y;y;false;ENGLISH;FREE_40;4473413b;433d4c4a;h,x,y,z;;h=0,x=1,y=0,z=1;;;27;0;false
HV|2|2|26|resolve:y:false:true|false;null;true|SETTING;z;z;false;;;00000000;00000000;h,x,y,z;;h=0,x=1,y=0,z=1;;;28;0;false
HV|2|2|27|config:z:PROGRAMMING:FREE_63:447b4691:44b66446|-|ATTEMPT;z;z;false;PROGRAMMING;FREE_63;447b4691;44b66446;h,x,y,z;;h=0,x=1,y=0,z=1;;;29;0;false
HV|2|2|28|resolve:z:true:false|false;null;true|SETTING;h;h;false;;;00000000;00000000;h,x,y,z;;h=0,x=1,y=0,z=1;;;30;0;false
HV|2|2|29|config:h:ENGLISH:FREE_43:445cf4a5:438b467c|-|ATTEMPT;h;h;false;ENGLISH;FREE_43;445cf4a5;438b467c;h,x,y,z;;h=0,x=1,y=0,z=1;;;31;0;false
HV|2|2|30|resolve:h:true:true|false;null;false|ATTEMPT;h;x;true;ENGLISH;FREE_43;445cf4a5;438b467c;h,x,y,z;;h=0,x=1,y=0,z=1;;;32;0;false
HV|2|2|31|resolve:x:true:true|false;null;false|ATTEMPT;h;y;true;ENGLISH;FREE_43;445cf4a5;438b467c;h,x,y,z;x;h=0,x=1,y=0,z=1;;;33;0;false
HV|2|2|32|resolve:y:true:true|false;null;false|ATTEMPT;h;z;true;ENGLISH;FREE_43;445cf4a5;438b467c;h,x,y,z;x,y;h=0,x=1,y=0,z=1;;;34;0;false
HV|2|2|33|resolve:z:true:true|false;null;true|SETTING;x;x;false;;;00000000;00000000;h,x,y,z;;h=0,x=1,y=0,z=1;;;35;0;false
HV|2|2|34|config:x:MATRICULATION_MATH:FREE_14:42b12f78:42ed29c4|-|ATTEMPT;x;x;false;MATRICULATION_MATH;FREE_14;42b12f78;42ed29c4;h,x,y,z;;h=0,x=1,y=0,z=1;;;36;0;false
HV|2|2|35|resolve:x:false:false|false;null;true|SETTING;y;y;false;;;00000000;00000000;h,x,y,z;;h=0,x=1,y=0,z=1;;;37;0;false
HV|2|2|36|config:y:PARADOX:FREE_56:4477b49d:44a626d9|-|ATTEMPT;y;y;false;PARADOX;FREE_56;4477b49d;44a626d9;h,x,y,z;;h=0,x=1,y=0,z=1;;;38;0;false
HV|2|2|37|resolve:y:false:false|false;null;true|SETTING;z;z;false;;;00000000;00000000;h,x,y,z;;h=0,x=1,y=0,z=1;;;39;0;false
HV|2|2|38|config:z:ASTRONOMY:FREE_92:424a45b0:43f26484|-|ATTEMPT;z;z;false;ASTRONOMY;FREE_92;424a45b0;43f26484;h,x,y,z;;h=0,x=1,y=0,z=1;;;40;0;false
HV|2|2|39|resolve:z:true:true|false;null;false|ATTEMPT;z;h;true;ASTRONOMY;FREE_92;424a45b0;43f26484;h,x,y,z;;h=0,x=1,y=0,z=1;;;41;0;false
HV|2|2|40|resolve:h:true:false|false;null;true|SETTING;x;x;false;;;00000000;00000000;h,x,y,z;;h=0,x=1,y=0,z=1;;;42;0;false
HV|2|2|41|config:x:PROGRAMMING:FREE_8:4323d490:44b62148|-|ATTEMPT;x;x;false;PROGRAMMING;FREE_8;4323d490;44b62148;h,x,y,z;;h=0,x=1,y=0,z=1;;;43;0;false
HV|2|2|42|resolve:x:false:true|false;null;true|SETTING;y;y;false;;;00000000;00000000;h,x,y,z;;h=0,x=1,y=0,z=1;;;44;0;false
HV|2|2|43|config:y:PROGRAMMING:FREE_73:4461dcee:448a73bd|-|ATTEMPT;y;y;false;PROGRAMMING;FREE_73;4461dcee;448a73bd;h,x,y,z;;h=0,x=1,y=0,z=1;;;45;0;false
HV|2|2|44|resolve:y:false:true|false;null;true|SETTING;z;z;false;;;00000000;00000000;h,x,y,z;;h=0,x=1,y=0,z=1;;;46;0;false
HV|2|2|45|config:z:PROGRAMMING:FREE_79:445f3ef8:4416d416|-|ATTEMPT;z;z;false;PROGRAMMING;FREE_79;445f3ef8;4416d416;h,x,y,z;;h=0,x=1,y=0,z=1;;;47;0;false
HV|2|2|46|resolve:z:true:true|false;null;false|ATTEMPT;z;h;true;PROGRAMMING;FREE_79;445f3ef8;4416d416;h,x,y,z;;h=0,x=1,y=0,z=1;;;48;0;false
HV|2|2|47|resolve:h:true:false|false;null;true|SETTING;x;x;false;;;00000000;00000000;h,x,y,z;;h=0,x=1,y=0,z=1;;;49;0;false
HV|2|2|48|config:x:PROGRAMMING:FREE_85:43d63fcc:43cd6329|-|ATTEMPT;x;x;false;PROGRAMMING;FREE_85;43d63fcc;43cd6329;h,x,y,z;;h=0,x=1,y=0,z=1;;;50;0;false
HV|2|2|49|resolve:x:false:false|false;null;true|SETTING;y;y;false;;;00000000;00000000;h,x,y,z;;h=0,x=1,y=0,z=1;;;51;0;false
HV|2|2|50|config:y:KIDS_ARITHMETIC:FREE_83:443c8994:42fda598|-|ATTEMPT;y;y;false;KIDS_ARITHMETIC;FREE_83;443c8994;42fda598;h,x,y,z;;h=0,x=1,y=0,z=1;;;52;0;false
HV|2|2|51|resolve:y:false:true|false;null;true|SETTING;z;z;false;;;00000000;00000000;h,x,y,z;;h=0,x=1,y=0,z=1;;;53;0;false
HV|2|2|52|config:z:MATH:FREE_46:42971a30:43624112|-|ATTEMPT;z;z;false;MATH;FREE_46;42971a30;43624112;h,x,y,z;;h=0,x=1,y=0,z=1;;;54;0;false
HV|2|2|53|resolve:z:true:true|false;null;false|ATTEMPT;z;h;true;MATH;FREE_46;42971a30;43624112;h,x,y,z;;h=0,x=1,y=0,z=1;;;55;0;false
HV|2|2|54|resolve:h:true:false|false;null;true|SETTING;x;x;false;;;00000000;00000000;h,x,y,z;;h=0,x=1,y=0,z=1;;;56;0;false
HV|2|2|55|config:x:GENERAL_KNOWLEDGE:FREE_14:43f6766a:4411ff52|-|ATTEMPT;x;x;false;GENERAL_KNOWLEDGE;FREE_14;43f6766a;4411ff52;h,x,y,z;;h=0,x=1,y=0,z=1;;;57;0;false
HV|2|2|56|resolve:x:false:true|false;null;true|SETTING;y;y;false;;;00000000;00000000;h,x,y,z;;h=0,x=1,y=0,z=1;;;58;0;false
HV|2|2|57|config:y:KIDS_ARITHMETIC:FREE_3:43c5813a:426233c8|-|ATTEMPT;y;y;false;KIDS_ARITHMETIC;FREE_3;43c5813a;426233c8;h,x,y,z;;h=0,x=1,y=0,z=1;;;59;0;false
HV|2|2|58|resolve:y:true:true|false;null;false|ATTEMPT;y;z;true;KIDS_ARITHMETIC;FREE_3;43c5813a;426233c8;h,x,y,z;;h=0,x=1,y=0,z=1;;;60;0;false
HV|2|2|59|resolve:z:false:false|true;z;true|SETTING;h;h;false;;;00000000;00000000;h,x,y,z;;h=0,x=1,y=0,z=2;z=0;;61;0;false
HV|2|2|60|config:h:MATH:FREE_89:4384f518:43bf00ac|-|ATTEMPT;h;h;false;MATH;FREE_89;4384f518;43bf00ac;h,x,y,z;;h=0,x=1,y=0,z=2;z=0;;62;0;false
HV|2|2|61|resolve:h:true:false|false;null;true|SETTING;x;x;false;;;00000000;00000000;h,x,y,z;;h=0,x=1,y=0,z=2;z=0;;63;0;false
HV|2|2|62|config:x:AI:FREE_76:4402cd5c:442983f2|-|ATTEMPT;x;x;false;AI;FREE_76;4402cd5c;442983f2;h,x,y,z;;h=0,x=1,y=0,z=2;z=0;;64;0;false
HV|2|2|63|resolve:x:true:true|false;null;false|ATTEMPT;x;y;true;AI;FREE_76;4402cd5c;442983f2;h,x,y,z;;h=0,x=1,y=0,z=2;z=0;;65;0;false
HV|2|2|64|resolve:y:false:false|true;null;true|SETTING;h;h;false;;;00000000;00000000;h,x,y,z;;h=0,x=1,y=1,z=2;z=0;;66;0;false
HV|2|2|65|config:h:PARADOX:FREE_39:439565ac:43e8db35|-|ATTEMPT;h;h;false;PARADOX;FREE_39;439565ac;43e8db35;h,x,y,z;;h=0,x=1,y=1,z=2;z=0;;67;0;false
HV|2|2|66|resolve:h:true:false|false;null;true|SETTING;x;x;false;;;00000000;00000000;h,x,y,z;;h=0,x=1,y=1,z=2;z=0;;68;0;false
HV|2|2|67|config:x:HISTORY:FREE_92:4420c9c0:42a967b8|-|ATTEMPT;x;x;false;HISTORY;FREE_92;4420c9c0;42a967b8;h,x,y,z;;h=0,x=1,y=1,z=2;z=0;;69;0;false
HV|2|2|68|resolve:x:true:false|false;null;true|SETTING;y;y;false;;;00000000;00000000;h,x,y,z;;h=0,x=1,y=1,z=2;z=0;;70;0;false
HV|2|2|69|config:y:ASTRONOMY:FREE_77:444df38e:4305f4e8|-|ATTEMPT;y;y;false;ASTRONOMY;FREE_77;444df38e;4305f4e8;h,x,y,z;;h=0,x=1,y=1,z=2;z=0;;71;0;false
HV|2|2|70|resolve:y:true:false|false;null;true|SETTING;h;h;false;;;00000000;00000000;h,x,y,z;;h=0,x=1,y=1,z=2;z=0;;72;0;false
HV|2|2|71|config:h:MATRICULATION_MATH:FREE_1:41e9e140:44828de5|-|ATTEMPT;h;h;false;MATRICULATION_MATH;FREE_1;41e9e140;44828de5;h,x,y,z;;h=0,x=1,y=1,z=2;z=0;;73;0;false
HV|2|2|72|resolve:h:true:false|false;null;true|SETTING;x;x;false;;;00000000;00000000;h,x,y,z;;h=0,x=1,y=1,z=2;z=0;;74;0;false
HV|2|2|73|config:x:PROGRAMMING:FREE_28:44482c21:44a32973|-|ATTEMPT;x;x;false;PROGRAMMING;FREE_28;44482c21;44a32973;h,x,y,z;;h=0,x=1,y=1,z=2;z=0;;75;0;false
HV|2|2|74|resolve:x:true:true|false;null;false|ATTEMPT;x;y;true;PROGRAMMING;FREE_28;44482c21;44a32973;h,x,y,z;;h=0,x=1,y=1,z=2;z=0;;76;0;false
HV|2|2|75|resolve:y:true:true|false;null;false|ATTEMPT;x;h;true;PROGRAMMING;FREE_28;44482c21;44a32973;h,x,y,z;y;h=0,x=1,y=1,z=2;z=0;;77;0;false
HV|2|2|76|resolve:h:true:true|false;null;true|SETTING;y;y;false;;;00000000;00000000;h,x,y,z;;h=0,x=1,y=1,z=2;z=0;;78;0;false
HV|2|2|77|config:y:HISTORY:FREE_83:44648297:41a5a590|-|ATTEMPT;y;y;false;HISTORY;FREE_83;44648297;41a5a590;h,x,y,z;;h=0,x=1,y=1,z=2;z=0;;79;0;false
HV|2|2|78|resolve:y:true:true|false;null;false|ATTEMPT;y;h;true;HISTORY;FREE_83;44648297;41a5a590;h,x,y,z;;h=0,x=1,y=1,z=2;z=0;;80;0;false
HV|2|2|79|resolve:h:true:true|false;null;false|ATTEMPT;y;x;true;HISTORY;FREE_83;44648297;41a5a590;h,x,y,z;h;h=0,x=1,y=1,z=2;z=0;;81;0;false
HV|2|2|80|resolve:x:true:true|false;null;true|SETTING;h;h;false;;;00000000;00000000;h,x,y,z;;h=0,x=1,y=1,z=2;z=0;;82;0;false
HV|2|2|81|config:h:MATRICULATION_MATH:FREE_52:43c69038:44b83d0e|-|ATTEMPT;h;h;false;MATRICULATION_MATH;FREE_52;43c69038;44b83d0e;h,x,y,z;;h=0,x=1,y=1,z=2;z=0;;83;0;false
HV|2|2|82|resolve:h:true:false|false;null;true|SETTING;x;x;false;;;00000000;00000000;h,x,y,z;;h=0,x=1,y=1,z=2;z=0;;84;0;false
HV|2|2|83|config:x:KIDS_ARITHMETIC:FREE_0:43c395b2:442e9364|-|ATTEMPT;x;x;false;KIDS_ARITHMETIC;FREE_0;43c395b2;442e9364;h,x,y,z;;h=0,x=1,y=1,z=2;z=0;;85;0;false
HV|2|2|84|resolve:x:true:true|false;null;false|ATTEMPT;x;y;true;KIDS_ARITHMETIC;FREE_0;43c395b2;442e9364;h,x,y,z;;h=0,x=1,y=1,z=2;z=0;;86;0;false
HV|2|2|85|resolve:y:false:false|true;y;true|SETTING;h;h;false;;;00000000;00000000;h,x,y,z;;h=0,x=1,y=2,z=2;y=1,z=0;;87;0;false
HV|2|2|86|config:h:MATRICULATION_MATH:FREE_45:446ee93d:441bc3a3|-|ATTEMPT;h;h;false;MATRICULATION_MATH;FREE_45;446ee93d;441bc3a3;h,x,y,z;;h=0,x=1,y=2,z=2;y=1,z=0;;88;0;false
HV|2|2|87|resolve:h:false:true|false;null;true|SETTING;x;x;false;;;00000000;00000000;h,x,y,z;;h=0,x=1,y=2,z=2;y=1,z=0;;89;0;false
HV|2|2|88|config:x:PARADOX:FREE_62:43ced75c:43a5f98a|-|ATTEMPT;x;x;false;PARADOX;FREE_62;43ced75c;43a5f98a;h,x,y,z;;h=0,x=1,y=2,z=2;y=1,z=0;;90;0;false
HV|2|2|89|resolve:x:false:false|false;null;true|SETTING;h;h;false;;;00000000;00000000;h,x,y,z;;h=0,x=1,y=2,z=2;y=1,z=0;;91;0;false
HV|2|2|90|config:h:HISTORY:FREE_95:441ccefb:44783253|-|ATTEMPT;h;h;false;HISTORY;FREE_95;441ccefb;44783253;h,x,y,z;;h=0,x=1,y=2,z=2;y=1,z=0;;92;0;false
HV|2|2|91|resolve:h:true:true|false;null;false|ATTEMPT;h;x;true;HISTORY;FREE_95;441ccefb;44783253;h,x,y,z;;h=0,x=1,y=2,z=2;y=1,z=0;;93;0;false
HV|2|2|92|resolve:x:false:false|true;x;true|FINISHED;h;h;false;HISTORY;FREE_95;441ccefb;44783253;h,x,y,z;;h=0,x=2,y=2,z=2;x=2,y=1,z=0;h;94;0;true
HV|3|1|-1|init:h,z,y,x:x|-|SETTING;x;x;false;;;00000000;00000000;h,z,y,x;;h=0,z=0,y=0,x=0;;;1;0;false
HV|3|1|0|config:x:PROGRAMMING:FREE_61:43b9a536:43819cc3|-|ATTEMPT;x;x;false;PROGRAMMING;FREE_61;43b9a536;43819cc3;h,z,y,x;;h=0,z=0,y=0,x=0;;;2;0;false
HV|3|1|1|resolve:x:true:true|false;null;false|ATTEMPT;x;h;true;PROGRAMMING;FREE_61;43b9a536;43819cc3;h,z,y,x;;h=0,z=0,y=0,x=0;;;3;0;false
HV|3|1|2|resolve:h:false:true|true;h;false|ATTEMPT;x;z;true;PROGRAMMING;FREE_61;43b9a536;43819cc3;h,z,y,x;h;h=1,z=0,y=0,x=0;h=0;;4;0;false
HV|3|1|3|resolve:z:true:true|false;null;false|ATTEMPT;x;y;true;PROGRAMMING;FREE_61;43b9a536;43819cc3;h,z,y,x;h,z;h=1,z=0,y=0,x=0;h=0;;5;0;false
HV|3|1|4|resolve:y:true:true|false;null;true|SETTING;z;z;false;;;00000000;00000000;h,z,y,x;;h=1,z=0,y=0,x=0;h=0;;6;0;false
HV|3|1|5|config:z:ASTRONOMY:FREE_24:4308d1d8:43072946|-|ATTEMPT;z;z;false;ASTRONOMY;FREE_24;4308d1d8;43072946;h,z,y,x;;h=1,z=0,y=0,x=0;h=0;;7;0;false
HV|3|1|6|resolve:z:false:true|false;null;true|SETTING;y;y;false;;;00000000;00000000;h,z,y,x;;h=1,z=0,y=0,x=0;h=0;;8;0;false
HV|3|1|7|config:y:ASTRONOMY:FREE_18:4438353f:40e88fc0|-|ATTEMPT;y;y;false;ASTRONOMY;FREE_18;4438353f;40e88fc0;h,z,y,x;;h=1,z=0,y=0,x=0;h=0;;9;0;false
HV|3|1|8|resolve:y:false:false|false;null;true|SETTING;x;x;false;;;00000000;00000000;h,z,y,x;;h=1,z=0,y=0,x=0;h=0;;10;0;false
HV|3|1|9|config:x:PARADOX:FREE_89:43ed7f2a:44b32e14|-|ATTEMPT;x;x;false;PARADOX;FREE_89;43ed7f2a;44b32e14;h,z,y,x;;h=1,z=0,y=0,x=0;h=0;;11;0;false
HV|3|1|10|resolve:x:false:true|false;null;true|SETTING;z;z;false;;;00000000;00000000;h,z,y,x;;h=1,z=0,y=0,x=0;h=0;;12;0;false
HV|3|1|11|config:z:GENERAL_KNOWLEDGE:FREE_16:43dcb4e0:44bf8436|-|ATTEMPT;z;z;false;GENERAL_KNOWLEDGE;FREE_16;43dcb4e0;44bf8436;h,z,y,x;;h=1,z=0,y=0,x=0;h=0;;13;0;false
HV|3|1|12|resolve:z:true:true|false;null;false|ATTEMPT;z;y;true;GENERAL_KNOWLEDGE;FREE_16;43dcb4e0;44bf8436;h,z,y,x;;h=1,z=0,y=0,x=0;h=0;;14;0;false
HV|3|1|13|resolve:y:false:true|true;y;false|ATTEMPT;z;x;true;GENERAL_KNOWLEDGE;FREE_16;43dcb4e0;44bf8436;h,z,y,x;y;h=1,z=0,y=1,x=0;h=0,y=1;;15;0;false
HV|3|1|14|resolve:x:true:true|false;null;true|SETTING;x;x;false;;;00000000;00000000;h,z,y,x;;h=1,z=0,y=1,x=0;h=0,y=1;;16;0;false
HV|3|1|15|config:x:MATRICULATION_MATH:FREE_19:443c2fd9:42e706fc|-|ATTEMPT;x;x;false;MATRICULATION_MATH;FREE_19;443c2fd9;42e706fc;h,z,y,x;;h=1,z=0,y=1,x=0;h=0,y=1;;17;0;false
HV|3|1|16|resolve:x:true:true|false;null;false|ATTEMPT;x;z;true;MATRICULATION_MATH;FREE_19;443c2fd9;42e706fc;h,z,y,x;;h=1,z=0,y=1,x=0;h=0,y=1;;18;0;false
HV|3|1|17|resolve:z:true:true|false;null;true|SETTING;z;z;false;;;00000000;00000000;h,z,y,x;;h=1,z=0,y=1,x=0;h=0,y=1;;19;0;false
HV|3|1|18|config:z:MATRICULATION_MATH:FREE_63:445ab6a3:44455281|-|ATTEMPT;z;z;false;MATRICULATION_MATH;FREE_63;445ab6a3;44455281;h,z,y,x;;h=1,z=0,y=1,x=0;h=0,y=1;;20;0;false
HV|3|1|19|resolve:z:true:true|false;null;false|ATTEMPT;z;x;true;MATRICULATION_MATH;FREE_63;445ab6a3;44455281;h,z,y,x;;h=1,z=0,y=1,x=0;h=0,y=1;;21;0;false
HV|3|1|20|resolve:x:false:true|true;x;true|FINISHED;z;z;false;MATRICULATION_MATH;FREE_63;445ab6a3;44455281;h,z,y,x;;h=1,z=0,y=1,x=1;h=0,x=2,y=1;z;22;0;true
HV|6|1|-1|init:p,q:p|-|SETTING;p;p;false;;;00000000;00000000;p,q;;p=0,q=0;;;1;0;false
HV|6|1|0|config:p:HISTORY:FREE_80:4464f68c:43d2d36b|-|ATTEMPT;p;p;false;HISTORY;FREE_80;4464f68c;43d2d36b;p,q;;p=0,q=0;;;2;0;false
HV|6|1|1|resolve:p:false:true|false;null;true|SETTING;q;q;false;;;00000000;00000000;p,q;;p=0,q=0;;;3;0;false
HV|6|1|2|config:q:PARADOX:FREE_17:443d961a:449ade49|-|ATTEMPT;q;q;false;PARADOX;FREE_17;443d961a;449ade49;p,q;;p=0,q=0;;;4;0;false
HV|6|1|3|resolve:q:false:false|false;null;true|SETTING;p;p;false;;;00000000;00000000;p,q;;p=0,q=0;;;5;0;false
HV|6|1|4|config:p:HISTORY:FREE_45:440455b3:4465f436|-|ATTEMPT;p;p;false;HISTORY;FREE_45;440455b3;4465f436;p,q;;p=0,q=0;;;6;0;false
HV|6|1|5|resolve:p:true:true|false;null;false|ATTEMPT;p;q;true;HISTORY;FREE_45;440455b3;4465f436;p,q;;p=0,q=0;;;7;0;false
HV|6|1|6|resolve:q:false:false|true;q;true|FINISHED;p;p;false;HISTORY;FREE_45;440455b3;4465f436;p,q;;p=0,q=1;q=0;p;8;0;true
HV_INIT|SETTING;b;b;false;;;00000000;00000000;a,b,c;;a=0,b=0,c=0;;;1;0;false
HV_SLOT|gap|b;ATTEMPT;a;c;true;AI;S;3f800000;40000000;a,b,c,d;b;a=0,b=1,c=0,d=0;b=1,q=0,r=2;;3;0;false
HV_SLOT|full|b;ATTEMPT;a;c;true;AI;S;3f800000;40000000;a,b,c,d;b;a=0,b=1,c=0,d=0;b=3,q=0,r=1,s=2;;3;0;false
HV_SLOT|dupValues|b;ATTEMPT;a;c;true;AI;S;3f800000;40000000;a,b,c,d;b;a=0,b=1,c=0,d=0;b=2,q=0,r=0,s=1;;3;0;false
"""#
