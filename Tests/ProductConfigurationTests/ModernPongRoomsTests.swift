import XCTest
@testable import MinikPlus

/// Android 739f2f8..29f5dc7 room, menu and colour-challenge rules (PlacementAndHintTest, FriendlyFlowTest,
/// TournamentInputRegressionTest, ManualControlTournamentTest, ProfileAvatarTest, PongArenaTest room parts).
final class ModernPongRoomsTests: XCTestCase {
    private func identity(_ id: String) -> MPIdentity { MPIdentity(id: id, name: id.uppercased()) }
    private func defaults() throws -> UserDefaults {
        let suite = "modern-rooms-" + UUID().uuidString
        let d = try XCTUnwrap(UserDefaults(suiteName: suite)); addTeardownBlock { d.removePersistentDomain(forName: suite) }; return d
    }

    // MARK: Arena on the wire (PongModels / PongCodec a4174b6)

    func testArenaDefaultsPerKindAndIsWrittenOnlyWhenSet() throws {
        let host = identity("a")
        XCTAssertEqual(MPSession(code: "ABC234", kind: .friendly, host: host).arena, "beach")
        XCTAssertEqual(MPSession(code: "ABC234", kind: .tournament, host: host).arena, "park")
        XCTAssertEqual(MPSession(code: "ABC234", kind: .friendly, host: host, arena: "castle").arena, "castle")
        XCTAssertEqual(MPSession(code: "ABC234", kind: .friendly, host: host, arena: "moon").arena, "beach")
        var s = MPSession(code: "ABC234", kind: .friendly, host: host, arena: "indoors")
        var wire = try MPCodec.session(s)
        XCTAssertEqual(wire["arena"] as? String, "indoors")
        XCTAssertEqual(try MPCodec.session(wire).arena, "indoors")
        // An older room has no arena: nothing is written, and reading it gives the original court.
        s.arena = ""; wire = try MPCodec.session(s)
        XCTAssertNil(wire["arena"])
        XCTAssertEqual(try MPCodec.session(wire).arena, "")
        XCTAssertEqual(MPArena.read(try MPCodec.session(wire).arena), .legacy)
    }

    /// Android PlacementAndHintTest.allMenuPointChoicesRemainExact.
    func testAllMenuPointChoicesRemainExact() throws {
        for d in [0, 3, 4] { for arena in MPArena.choices { for target in [3, 5, 7, 11] {
            let s = MPSession(code: "ABCDEF", kind: .friendly, host: identity("test"), difficulty: d, target: target, arena: arena.wire)
            let decoded = try MPCodec.session(try MPCodec.session(s))
            XCTAssertEqual(decoded.target, target); XCTAssertEqual(decoded.arena, arena.wire)
        } } }
    }

    // MARK: Controls (ControlChoice 96ae066, FriendlyFlowTest)

    func testStarterIsTheFourthControlChoice() {
        XCTAssertEqual([0, 1, 2].map(MPControlChoice.normalize), [0, 1, 0])
        XCTAssertEqual([0, 1, 2, 3, 4, 7].map(MPLevel.control), [.easy, .medium, .easy, .superHard, .beginner, .beginner])
        XCTAssertEqual(MPLevel.controlChoices, [.beginner, .medium, .easy, .superHard])
        XCTAssertEqual(MPLevel.controlChoices.map { MPControlChoice.title($0.rawValue, hebrew: false) }, ["Beginner", "Starter", "Standard", "Pro"])
        XCTAssertEqual(MPLevel.controlChoices.map { MPControlChoice.title($0.rawValue, hebrew: true) }, ["מתחילים", "נינוחה", "רגילה", "מקצועני"])
        let defaults = UserDefaults(suiteName: "modern-control-" + UUID().uuidString)!
        let preferences = MPPreferences(defaults); preferences.control = .medium
        XCTAssertEqual(MPPreferences(defaults).control, .medium, "Starter is kept")
    }

    // MARK: Standings and podium

    /// Android TournamentInputRegressionTest.circularTieUsesScoreDifferenceThenPointsScored.
    func testCircularTieUsesScoreDifferenceThenPointsScored() {
        var s = MPSession(code: "ABC234", kind: .tournament, host: identity("a"), capacity: 3)
        for id in ["a", "b", "c"] { s.participants[id] = MPParticipant(identity: identity(id)) }
        func m(_ id: String, _ a: String, _ b: String, _ sa: Int, _ sb: Int) -> MPFixture {
            var f = MPFixture(id: id, a: a, b: b, seed: 1); f.phase = .finished; f.scoreA = sa; f.scoreB = sb; f.winner = sa > sb ? a : b; return f
        }
        for f in [m("ab", "a", "b", 3, 0), m("ac", "a", "c", 2, 3), m("bc", "b", "c", 3, 1)] { s.matches[f.id] = f }
        let result = MPRules.standings(s)
        XCTAssertEqual(result.map(\.id), ["a", "c", "b"])
        XCTAssertEqual(result.map(\.points), [3, 3, 3])
        XCTAssertEqual(result.map { $0.pointsFor - $0.pointsAgainst }, [2, -1, -1])
        XCTAssertEqual(result.map(\.pointsFor), [5, 4, 3])
    }

    /// Android ManualControlTournamentTest.podiumUsesFinalStandings.
    func testPodiumUsesFinalStandings() throws {
        var s = MPSession(code: "ABC234", kind: .tournament, host: identity("a"), capacity: 3, legs: 1, winPoints: 3, difficulty: 4, target: 3)
        s = try MPRules.join(MPRules.join(s, identity("b")), identity("c"))
        s = try MPRules.start(s, actor: "a")
        for m in s.matches.values.sorted(by: { $0.id < $1.id }) {
            var playing = m; playing.phase = .playing; s.matches[m.id] = playing
            s = try MPRules.finish(s, match: m.id, actor: s.authority(playing), a: 3, b: 0)
        }
        XCTAssertTrue(s.complete)
        XCTAssertEqual(MPRanking.podium(s), ["a", "b", "c"])
    }

    // MARK: Friendly house player (PongModels.addFriendlyHousePlayer / friendlyHouseReady)

    func testFriendlyHousePlayerTakesTheSingleSeatAndStartIsReady() throws {
        let host = identity("host")
        let empty = MPSession(code: "ABC234", kind: .friendly, host: host)
        let kyra = try XCTUnwrap(MPRoster.find("kyra"))
        let bot = MPRules.housePlayer(kyra.profile)
        XCTAssertTrue(bot.id.hasPrefix("bot_")); XCTAssertEqual(bot.identity.name, "Kyra")
        XCTAssertThrowsError(try MPRules.addFriendlyHousePlayer(empty, actor: "other", player: bot))
        var s = try MPRules.addFriendlyHousePlayer(empty, actor: "host", player: bot)
        XCTAssertEqual(s.participants.count, 2)
        // A friend who joined first keeps the seat: the full room is unchanged.
        XCTAssertEqual(try MPRules.addFriendlyHousePlayer(s, actor: "host", player: MPRules.housePlayer(kyra.profile)), s)
        XCTAssertEqual(MPRules.friendlyHouseReady(s, actor: "host"), s, "only an active room")
        s = try MPRules.start(s, actor: "host")
        let ready = MPRules.friendlyHouseReady(s, actor: "host")
        XCTAssertEqual(ready.matches.values.first?.ready["host"], true)
        XCTAssertEqual(ready.matches.values.first?.phase, .ready)
        XCTAssertEqual(MPRules.friendlyHouseReady(ready, actor: "host"), ready)
    }

    // MARK: Nicknames (ProfileAvatarTest 4bd6758)

    func testRenamedCharactersKeepTheirRegisteredNicknameBases() {
        XCTAssertEqual(MPRoster.find("minik")?.english, "Mega Minik"); XCTAssertEqual(MPRoster.find("miniko")?.hebrew, "מגה מיניקו")
        XCTAssertEqual(MPNames.candidate(6, hebrew: false, character: "miniko"), "BlueMiniko")
        XCTAssertEqual(MPNames.candidate(6, hebrew: true, character: "minik"), "מיניק בכחול")
    }

    // MARK: Colour challenge (ColorChallengeActivity + PongRanking.session)

    private func challengeRoom(_ control: Int, bot: MPBot) throws -> MPSession {
        var s = MPSession(code: "QWE234", kind: .friendly, host: identity("me"), difficulty: control, target: 11, arena: MPArena.park.wire)
        s = try MPRules.addFriendlyHousePlayer(s, actor: "me", player: MPRules.housePlayer(bot))
        s = try MPRules.start(s, actor: "me"); s.connections["me"] = ["0": true]
        let id = try XCTUnwrap(s.matches.keys.first)
        return MPRules.startReady(MPRules.friendlyHouseReady(s, actor: "me"), match: id)
    }
    private func finish(_ s: MPSession, won: Bool) throws -> MPSession {
        let m = try XCTUnwrap(s.matches.values.first)
        let mine = m.a == "me"
        return try MPRules.finish(s, match: m.id, actor: "me", a: won == mine ? 11 : 5, b: won == mine ? 5 : 11)
    }
    func testLocalChallengeWinCountsTowardTheNextColourOnce() throws {
        let ranking = MPRanking(try defaults())
        XCTAssertTrue(ranking.award("seed", 400))
        XCTAssertEqual(ranking.state.level, 1); XCTAssertTrue(ranking.state.eligible); XCTAssertEqual(ranking.state.next, 2)
        let bot = MPRankPromotion.bots(2)[0].profile
        let s = try challengeRoom(1, bot: bot)
        XCTAssertEqual(s.matches.values.first?.phase, .playing); XCTAssertEqual(s.arena, "park")
        XCTAssertTrue(ranking.registerTrial(s, target: 2, champion: false))
        XCTAssertEqual(ranking.activeTrialCode, s.code); XCTAssertEqual(ranking.trial(s), 2)
        XCTAssertFalse(ranking.session(s, uid: "me", online: false), "a playing match only records that it was played")
        let done = try finish(s, won: true)
        XCTAssertTrue(ranking.session(done, uid: "me", online: false))
        XCTAssertEqual(ranking.state.botWins, 1)
        XCTAssertEqual(ranking.state.points, 400 + MPRanks.bot(bot, control: 1))
        XCTAssertNil(ranking.activeTrialCode, "a paid trial is no longer paused")
        XCTAssertFalse(ranking.session(done, uid: "me", online: false), "a receipt pays once")
    }
    func testOnlineOrDisallowedControlsNeverQualify() throws {
        let ranking = MPRanking(try defaults()); ranking.award("seed", 400)
        let bot = MPRankPromotion.bots(2)[0].profile
        let beginner = try challengeRoom(4, bot: bot)
        ranking.registerTrial(beginner, target: 2, champion: false)
        ranking.session(beginner, uid: "me", online: false)
        ranking.session(try finish(beginner, won: true), uid: "me", online: false)
        XCTAssertEqual(ranking.state.botWins, 0, "Beginner is below Starter")
        XCTAssertEqual([1, 0, 3].filter { MPRankPromotion.allowedControl(2, $0) }, [1, 0, 3])
        XCTAssertEqual([1, 0, 3].filter { MPRankPromotion.allowedControl(8, $0) }, [0, 3])
        XCTAssertEqual([1, 0, 3].filter { MPRankPromotion.allowedControl(11, $0) }, [3])
    }
    @MainActor func testColorChallengeStartsALocalParkMatchToElevenAndBackPausesIt() async throws {
        let d = try defaults(), preferences = MPPreferences(d); preferences.skipGuide = true
        let model = MPController(experience: .full, preferences: preferences, repository: MPLocalRepository(defaults: d)) { _ in }
        model.ranking.award("seed", 400)
        model.openColorChallenge(); XCTAssertEqual(model.route, .colorChallenge)
        let bot = MPRankPromotion.bots(2)[0].profile
        model.startChallenge(bot: bot, target: 2, champion: false)
        for _ in 0..<200 { await Task.yield(); if model.route == .game { break } }
        XCTAssertEqual(model.route, .game)
        let s = try XCTUnwrap(model.session)
        XCTAssertEqual(s.arena, "park"); XCTAssertEqual(s.target, 11); XCTAssertEqual(s.difficulty, 1)
        XCTAssertTrue(model.challenge(s)); XCTAssertEqual(model.ranking.activeTrialCode, s.code)
        XCTAssertEqual(model.scene?.selectedArena, .park)
        XCTAssertEqual(model.scene?.engine.level, .medium)
        XCTAssertFalse(model.rooms.contains { $0.code == s.code }, "a challenge is not a saved game")
        model.back()
        XCTAssertEqual(model.route, .colorChallenge); XCTAssertNil(model.session)
        XCTAssertEqual(model.ranking.activeTrialCode, s.code, "the paused match can be resumed")
        model.forfeitChallenge()
        XCTAssertNil(model.ranking.activeTrialCode)
        model.close()
    }

    // MARK: Presentation helpers

    func testAdaptiveOutlineInvertsRankLuminance() {
        XCTAssertEqual(MPHudText.rim(0xff795548) & 0xff, 227, "Brown gets a light rim")
        XCTAssertEqual(MPHudText.rim(0xffffcf40), 0xff000000, "Gold gets a dark rim")
    }
    /// Android PlacementAndHintTest.landscapeSuppressesTipsForRestOfRunIncludingAdReturn.
    func testLandscapeTipIsOfferedOnceAndNeverAfterLandscapePlay() {
        var s = MPLandscapeTipSession(); s.observe(true); s.observe(false); XCTAssertFalse(s.claim(true))
        var p = MPLandscapeTipSession(); XCTAssertFalse(p.claim(false)); XCTAssertTrue(p.claim(true)); XCTAssertFalse(p.claim(true))
    }
    func testArenaPreferencesDefaultPerKind() throws {
        let preferences = MPPreferences(try defaults())
        XCTAssertEqual(preferences.arena(.friendly), .beach); XCTAssertEqual(preferences.arena(.tournament), .park)
        preferences.setArena(.castle, for: .friendly)
        XCTAssertEqual(preferences.arena(.friendly), .castle); XCTAssertEqual(preferences.arena(.tournament), .park)
    }
}
