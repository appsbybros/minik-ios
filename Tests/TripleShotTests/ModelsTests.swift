import Foundation
import XCTest
@testable import MinikTripleShot

// Parity tests for area t-models (spec 01): model/TripleShotModels.kt, model/TripleShotCharacters.kt,
// model/OnlineNickname.kt, view/CourtTheme.kt, view/TripleShotCourtCatalog.kt and the Firebase wire codecs.
//
// - The first three tests port test/.../OnlineNicknameTest.kt with its exact assertions.
// - Every other expected value in TSModelsGolden was produced on the JVM by the original Kotlin sources
//   (TripleShotGame dd722e5) and, for the Firebase rows, by firebase-database 22.0.1's own CustomClassMapper
//   (convertToPlainJavaTypes / convertToCustomClass). Floats are compared by bit pattern.
// - TSModelsAndroidMessages holds Android's exact DatabaseException texts and ClassMapper warnings, produced by
//   the same CustomClassMapper on the plain values Firebase builds (NodeUtilities.NodeFromJSON(json).getValue():
//   HashMap / ArrayList / Long / Double / Boolean / String), so the class names and the HashMap visiting order
//   are Android's.

final class ModelsTests: XCTestCase {

    // MARK: - OnlineNicknameTest.kt

    func testAcceptsShortAliasesInDifferentScripts() {
        for s in ["Gaya", "Comet", "\u{5E0}\u{5D9}\u{5E6}\u{5D5}\u{5E5}", "Jos\u{E9}", "\u{C9}mile"] {
            XCTAssertTrue(OnlineNickname.valid(s), s)
        }
    }

    func testRejectsFullNamesNumbersAndBidiControls() {
        for s in ["", "Alexander", "John Smith", "Nir12", "ABC\u{202E}", "12345",
                  "\u{FF21}\u{FF22}\u{FF23}\u{FF24}\u{FF25}\u{FF26}"] {
            XCTAssertFalse(OnlineNickname.valid(s), s)
        }
    }

    func testNormalizesAccentsBeforeCounting() {
        XCTAssertTrue(OnlineNickname.valid("E\u{0301}mile"))
        XCTAssertFalse(OnlineNickname.valid("E\u{0301}milee"))
    }

    // MARK: - OnlineNickname golden vectors (trim, NFC, code points, Character.isLetter)

    func testNicknameGoldenVectors() {
        for (s, expected) in TSModelsGolden.nicknameVectors {
            let points = s.unicodeScalars.map { String(format: "%04X", $0.value) }.joined(separator: " ")
            XCTAssertEqual(OnlineNickname.valid(s), expected, "[\(points)]")
        }
    }

    // MARK: - QuestionCategory and the other enums

    func testQuestionCategoryOrderNamesAndLabels() {
        XCTAssertEqual(QuestionCategory.allCases.count, TSModelsGolden.categoryRows.count)
        for (category, row) in zip(QuestionCategory.allCases, TSModelsGolden.categoryRows) {
            XCTAssertEqual(category.ordinal, row.0)
            XCTAssertEqual(category.name, row.1)
            XCTAssertEqual(category.label, row.2)
            XCTAssertEqual(QuestionCategory.named(row.1), category)
            // English only for exactly "en", "EN", "En", "eN"; every other code gets the Hebrew label.
            for english in ["en", "EN", "En", "eN"] {
                XCTAssertEqual(category.labelFor(english), row.3, english)
            }
            for other in ["he", "iw", "en-US", "", " en", "ar", "fr"] {
                XCTAssertEqual(category.labelFor(other), row.2, other)
            }
        }
        // Room meta/categories are sorted by name (String.compareTo).
        XCTAssertEqual(QuestionCategory.allCases.map { $0.name }.sorted(), TSModelsGolden.categoryNamesSorted)
    }

    func testEnumCaseOrderMatchesKotlinOrdinals() {
        XCTAssertEqual(TripleShotGameOrientation.allCases.map { $0.name }, TSModelsGolden.orientationNames)
        XCTAssertEqual(GameType.allCases.map { $0.name }, TSModelsGolden.gameTypeNames)
        XCTAssertEqual(GameLimitMode.allCases.map { $0.name }, TSModelsGolden.limitModeNames)
        XCTAssertEqual(ShotZone.allCases.map { $0.name }, TSModelsGolden.shotZoneNames)
        XCTAssertEqual(CharacterGender.allCases.map { $0.name }, TSModelsGolden.genderNames)
        XCTAssertEqual(BotArchetype.allCases.map { $0.name }, TSModelsGolden.archetypeNames)
        XCTAssertEqual(TripleShotCourtAtmosphere.allCases.map { $0.name }, TSModelsGolden.atmosphereNames)
        XCTAssertEqual(GameType.allCases.map { $0.ordinal }, [0, 1, 2, 3, 4])
        XCTAssertEqual(QuestionCategory.MATRICULATION_MATH.ordinal, 10)
    }

    // MARK: - TripleShotGameConfig

    func testGameConfigDefaults() {
        let c = TripleShotGameConfig(playerName: "P", seed: 42)
        XCTAssertEqual(c.playerName, "P")
        XCTAssertEqual(c.gameType, .SHOOTING_CHALLENGE)
        XCTAssertEqual(c.limitMode, .TIME_ONLY)
        XCTAssertEqual(c.selectedCategories.elements, QuestionCategory.allCases)
        XCTAssertEqual(c.selectedCategories.elements.map { $0.name }, TSModelsGolden.categoryRows.map { $0.1 })
        XCTAssertNil(c.roomId)
        XCTAssertEqual(c.roomStartedAtMs, 0)
        XCTAssertFalse(c.botMatch)
        XCTAssertEqual(c.playerCharacterId, "woman_dark")
        XCTAssertEqual(c.botCharacterId, "bob")
        XCTAssertEqual(c.teamSize, 1)
        XCTAssertEqual(c.teammateCharacterIds, [])
        XCTAssertEqual(c.opponentCharacterIds, [])
        XCTAssertEqual(c.gameOrientation, .PORTRAIT)
        XCTAssertEqual(c.courtId, "enchanted_forest")
        XCTAssertEqual(c.seed, 42)
        XCTAssertEqual(c.ballLimit, 20)
        XCTAssertEqual(c.timeLimitSeconds, 60)
        XCTAssertEqual(c.leagueSeasonId, "")
        XCTAssertEqual(c.leagueFixtureKey, "")
        XCTAssertEqual(c.teamName, "")
        XCTAssertEqual(c.opponentTeamName, "")
        XCTAssertEqual(c.teamColor, -8988417)          // 0xff76d8ff.toInt()
        XCTAssertEqual(c.opponentTeamColor, -18567)    // 0xffffb779.toInt()
    }

    func testGameConfigSeedDefaultsToTheClockAtConstruction() {
        let before = ASystem.currentTimeMillis()
        let c = TripleShotGameConfig(playerName: "P")
        let after = ASystem.currentTimeMillis()
        XCTAssertTrue(c.seed >= before && c.seed <= after, "\(before) <= \(c.seed) <= \(after)")
    }

    func testGameConfigFlagsMatchKotlin() {
        func b(_ x: Bool) -> String { return x ? "1" : "0" }
        var lines: [String] = []
        let rooms: [String?] = [nil, "", " ", "R"]
        for g in GameType.allCases {
            for room in rooms {
                for bot in [false, true] {
                    for team in [1, 2, 3, 4] {
                        let c = TripleShotGameConfig(
                            playerName: "P", gameType: g, roomId: room, botMatch: bot, teamSize: team, seed: 1
                        )
                        let roomText = room.map { "'\($0)'" } ?? "null"
                        lines.append(
                            "\(g.name)|\(roomText)|\(b(bot))|\(team) -> M\(b(c.isMultiplayer)) P\(b(c.isPractice)) "
                                + "B\(b(c.isBotMatch)) O\(b(c.isOneOnOne)) T\(b(c.isTeamMatch)) R\(b(c.isRanked))"
                        )
                    }
                }
            }
        }
        XCTAssertEqual(lines, TSModelsGolden.configFlagLines.components(separatedBy: "\n"))
    }

    func testGameConfigCopyKeepsAndClearsLikeKotlin() {
        let c0 = TripleShotGameConfig(playerName: "P", seed: 42)
        let again = c0.copy(roomId: nil, seed: 7)
        XCTAssertEqual(again.seed, 7)
        XCTAssertNil(again.roomId)
        XCTAssertEqual(again.playerName, "P")

        let live = TripleShotGameConfig(playerName: "P", roomId: "ABCD", seed: 5)
        XCTAssertEqual(live.copy(seed: 9).roomId, "ABCD")
        XCTAssertNil(live.copy(roomId: nil).roomId)
        XCTAssertEqual(live.copy(roomId: "Q").roomId, "Q")
        XCTAssertEqual(live.copy().seed, 5)

        // GameFragment "play again": config.copy(seed = if (isMultiplayer) seed else now, roomId = null).
        // After a Live Shooting Challenge this is the only path to a ranked run.
        XCTAssertFalse(live.isRanked)
        let playAgain = live.copy(roomId: nil, seed: live.isMultiplayer ? live.seed : 0)
        XCTAssertEqual(playAgain.seed, 5)
        XCTAssertTrue(playAgain.isRanked)
    }

    func testGameConfigKeepsTheProducersCategoryOrder() {
        let topics: [QuestionCategory] = [.MATH, .AI, .MATH, .HISTORY]
        let c = TripleShotGameConfig(playerName: "P", selectedCategories: topics, seed: 1)
        XCTAssertEqual(c.selectedCategories.elements, [.MATH, .AI, .HISTORY])
        XCTAssertTrue(c.selectedCategories.contains(.AI))
        XCTAssertFalse(c.selectedCategories.contains(.SCIENCE))
    }

    // MARK: - Character roster

    func testRosterTableMatchesKotlin() {
        let rows = TripleShotCharacterRoster.all.map { p -> String in
            let r = p.ratings
            let t = p.tendencies
            let q = p.quiz
            let ovr = (r.inside + r.midRange + r.threePoint + r.speed + r.strength + r.height + r.blocking
                + r.stealing + r.ballHandling) / 9
            let league = (r.inside + r.midRange + r.defense + r.speed) / 4
            let ratings = [r.inside, r.midRange, r.threePoint, r.speed, r.strength, r.height, r.blocking, r.stealing,
                           r.ballHandling, r.dunking, r.defense, r.agility, r.offense, r.weight, r.jumping]
            let tendencies = [t.attackAggression, t.stealAggression, t.blockAggression, t.riskTaking]
            let shooting = [r.shootingFor(.INSIDE), r.shootingFor(.MID_RANGE), r.shootingFor(.THREE_POINT)]
            func join(_ values: [Int]) -> String { return values.map { String($0) }.joined(separator: ",") }
            return "\(p.id)|\(p.displayName)|\(p.gender.name)|\(p.archetype.name)|adaptive=\(p.adaptiveBot)"
                + "|human=\(p.selectableByHuman)|bot=\(p.selectableAsBot)|R=\(join(ratings))"
                + "|T=\(t.preferredZone?.name ?? "null"),\(join(tendencies))"
                + "|Q=\(join([q.knowledge, q.responseSpeed, q.guessiness]))|shoot=\(join(shooting))"
                + "|ovr=\(ovr)|league=\(league)"
        }
        XCTAssertEqual(rows, TSModelsGolden.rosterRows)
    }

    func testRosterSelectionAndLookup() {
        XCTAssertEqual(TripleShotCharacterRoster.humanSelectable().map { $0.id }, TSModelsGolden.humanSelectableIds)
        XCTAssertEqual(TripleShotCharacterRoster.botSelectable().map { $0.id }, TSModelsGolden.botSelectableIds)
        for (id, found, required) in TSModelsGolden.findRows {
            XCTAssertEqual(TripleShotCharacterRoster.find(id)?.id, found, String(describing: id))
            XCTAssertEqual(TripleShotCharacterRoster.requireProfile(id).id, required, String(describing: id))
        }
        XCTAssertEqual(
            [TripleShotCharacterRoster.ID_BOB, TripleShotCharacterRoster.ID_MINIK, TripleShotCharacterRoster.ID_WOMAN_DARK,
             TripleShotCharacterRoster.ID_ROOZA, TripleShotCharacterRoster.ID_NOVA, TripleShotCharacterRoster.ID_UNICORN_32,
             TripleShotCharacterRoster.ID_COACH_67, TripleShotCharacterRoster.ID_KYRA, TripleShotCharacterRoster.ID_ZEPHYR,
             TripleShotCharacterRoster.ID_FLARE, TripleShotCharacterRoster.ID_ACE_23, TripleShotCharacterRoster.ID_BUDDY_23],
            ["bob", "bob", "woman_dark", "rooza", "nova", "unicorn_32", "coach_67", "kyra", "zephyr", "flare", "ace_23",
             "buddy_23"]
        )
        XCTAssertEqual(TripleShotCharacterRoster.minik, TripleShotCharacterRoster.bob)
        // originalKyra = kyra.copy(id = "kyra_original", displayName = "Kyra")
        var kyraCopy = TripleShotCharacterRoster.kyra
        kyraCopy.id = "kyra_original"
        kyraCopy.displayName = "Kyra"
        XCTAssertEqual(TripleShotCharacterRoster.originalKyra, kyraCopy)
        XCTAssertEqual(TripleShotCharacterRoster.all.count, 12)
    }

    func testRatingAndProfileDefaults() {
        let t = BotTendencies()
        XCTAssertNil(t.preferredZone)
        XCTAssertEqual([t.attackAggression, t.stealAggression, t.blockAggression, t.riskTaking], [50, 50, 50, 50])
        let q = BotQuizProfile()
        XCTAssertEqual([q.knowledge, q.responseSpeed, q.guessiness], [60, 60, 25])
        let r = BasketballRatings(
            inside: 1, midRange: 2, threePoint: 3, speed: 4, strength: 5, height: 6, blocking: 7, stealing: 8,
            ballHandling: 9
        )
        XCTAssertEqual([r.dunking, r.defense, r.agility, r.offense, r.weight, r.jumping], [50, 50, 50, 50, 50, 50])
        // 0 and 100 are inside `0..100`; -1 and 101 trap (Kotlin require -> precondition, not testable here).
        let bounds = BasketballRatings(
            inside: 0, midRange: 100, threePoint: 0, speed: 100, strength: 0, height: 100, blocking: 0, stealing: 100,
            ballHandling: 0, dunking: 100, defense: 0, agility: 100, offense: 0, weight: 100, jumping: 0
        )
        XCTAssertEqual(bounds.shootingFor(.MID_RANGE), 100)
        let profile = TripleShotCharacterProfile(id: "x", displayName: "X", ratings: r, archetype: .DEFENDER)
        XCTAssertEqual(profile.gender, .NEUTRAL)
        XCTAssertEqual(profile.tendencies, BotTendencies())
        XCTAssertEqual(profile.quiz, BotQuizProfile())
        XCTAssertFalse(profile.adaptiveBot)
        XCTAssertFalse(profile.selectableByHuman)
        XCTAssertFalse(profile.selectableAsBot)
    }

    // MARK: - Courts

    func testCourtCatalogTableMatchesKotlin() {
        let rows = TripleShotCourtCatalog.all.map { s in
            "\(s.id)|\(s.titleRes)|\(s.subtitleRes)|\(s.landscapeDrawableName)|\(s.portraitDrawableName ?? "null")"
                + "|\(s.atmosphere.name)"
        }
        XCTAssertEqual(rows, TSModelsGolden.courtRows.map { $0.components(separatedBy: "|P=")[0] })
    }

    /// Needs the Android drawable set bundled exactly (missing court art must fall back, spec 01 section 8.10).
    func testCourtBackgroundResolutionMatchesAndroid() {
        let rows = TripleShotCourtCatalog.all.map { s in
            "\(s.id)|\(s.titleRes)|\(s.subtitleRes)|\(s.landscapeDrawableName)|\(s.portraitDrawableName ?? "null")"
                + "|\(s.atmosphere.name)|P=\(s.resolveBackgroundResId(nil, .PORTRAIT))"
                + "|L=\(s.resolveBackgroundResId(nil, .LANDSCAPE))"
        }
        XCTAssertEqual(rows, TSModelsGolden.courtRows)
        XCTAssertEqual(
            TripleShotCourtCatalog.find("sunset_pulse").resolveBackgroundResId(.LANDSCAPE),
            "triple_shot_court_sunset_pulse_landscape"
        )
        XCTAssertEqual(
            TripleShotCourtCatalog.find(id: "skyforge_peaks").resolveBackgroundResId(context: nil, orientation: .PORTRAIT),
            R.drawable.triple_shot_court_background
        )
    }

    func testCourtFind() {
        for (id, expected) in TSModelsGolden.courtFindRows {
            XCTAssertEqual(TripleShotCourtCatalog.find(id).id, expected, String(describing: id))
        }
        XCTAssertEqual(TripleShotCourtCatalog.DEFAULT_ID, "enchanted_forest")
        XCTAssertEqual(TripleShotCourtCatalog.all.count, 9)
    }

    func testCourtThemeSpectatorSpotsBitExact() {
        let theme = CourtThemes.ENCHANTED_FOREST
        XCTAssertEqual(theme.id, "enchanted_forest")
        let spots = theme.spectatorArea.spots.map { [$0.sourceX.bitPattern, $0.sourceY.bitPattern, $0.scale.bitPattern] }
        XCTAssertEqual(spots, [
            [0x431b0000, 0x44938000, 0x3f51eb85],
            [0x44020000, 0x449d8000, 0x3f51eb85],
            [0x44494000, 0x448b6000, 0x3f51eb85]
        ])
        XCTAssertEqual(SpectatorSpot(sourceX: 1, sourceY: 2).scale.bitPattern, 0x3f51eb85)
    }

    // MARK: - LiveHorseState.isFinished

    func testHorseIsFinished() {
        XCTAssertFalse(LiveHorseState().isFinished)
        XCTAssertTrue(LiveHorseState(phase: LiveHorseState.PHASE_FINISHED).isFinished)
        XCTAssertTrue(LiveHorseState(phase: LiveHorseState.PHASE_SETTING, winnerUid: "u1").isFinished)
        // isNotBlank uses Kotlin whitespace: NBSP is blank.
        XCTAssertFalse(LiveHorseState(phase: LiveHorseState.PHASE_ATTEMPT, winnerUid: " \u{A0}").isFinished)
        XCTAssertEqual(
            [LiveHorseState.PHASE_SETTING, LiveHorseState.PHASE_ATTEMPT, LiveHorseState.PHASE_FINISHED],
            ["SETTING", "ATTEMPT", "FINISHED"]
        )
    }

    // MARK: - Firebase wire format: writing (CustomClassMapper.convertToPlainJavaTypes)

    static let sampleSamples: [ShotReplaySample] = [
        ShotReplaySample(tMs: 0, x: 410, y: 1100, depth: 0),
        ShotReplaySample(tMs: 55, x: 430.5, y: 1010.25, depth: 0)
    ]

    static let sampleHorse = LiveHorseState(
        phase: LiveHorseState.PHASE_ATTEMPT, setterUid: "u1", currentPlayerUid: "u2", challengeEstablished: true,
        challengeCategory: "MATH", challengeSpotId: "spot_3", challengeSpotX: 512, challengeSpotY: 0.7,
        playerOrder: ["u1", "u2", "u3"], attemptedUids: ["u2"],
        penalties: ["u1": 0, "u2": 2, "u3": 1], spectatorSlots: ["u3": 0],
        winnerUid: "", turnNumber: 4, updatedAt: 1760000030000
    )

    static let sampleShot = LiveShotEvent(
        id: "-Nabc", playerUid: "u2", playerName: "Gaya", shotSpotX: 512, shotSpotY: 1180.5,
        aimError: -0.25, powerError: 0.1, arcError: -1.7, rawPeakGyro: Float(3.05) + Float(0.5) * Float(1.35),
        rawReleasePitchDeg: Float(0.75) * Float(20), pullBack: 0.75, hotHand: true, releasedAt: 1760000031234,
        made: false, samples: sampleSamples
    )

    static let sampleBoard = LeaderboardEntry(
        uid: "u9", name: "Comet", bestScore: 57, bestShootingStreak: 6, bestKnowledgeStreak: 9,
        bestCorrectAnswers: 14, bestRunCorrectAnswers: 12, bestRunShots: 16, bestRunMadeShots: 11,
        bestRunKnowledgeAccuracyPercent: 75, bestRunShootingPercent: 68, bestRunCategories: ["AI", "MATH"],
        updatedAt: 1760000040000
    )

    static let sampleMeta = RoomMeta(
        hostUid: "u1", status: "PLAYING", seed: -4611686018427387904, createdAt: 1760000000000,
        startedAt: 1760000010000, gameType: "HORSE", categories: ["AI", "ASTRONOMY"], timeLimitSeconds: 60,
        maxPlayers: 4
    )

    static let samplePlayer = LivePlayerState(
        uid: "u2", name: "Gaya", score: 12, knowledgeStreak: 2, shootingStreak: 1, bestKnowledgeStreak: 3,
        bestShootingStreak: 2, correctAnswers: 5, madeShots: 4, shots: 6, lastEvent: "\u{5E1}\u{5D9}\u{5D9}\u{5DD}",
        finished: true, updatedAt: 1760000050000
    )

    func testFirebaseEncodingMatchesCustomClassMapper() {
        let objects: [String: [String: Any]] = [
            "horseDefault": LiveHorseState().toFirebaseMap(),
            "horse": Self.sampleHorse.toFirebaseMap(),
            "horseWinner": LiveHorseState(phase: "SETTING", winnerUid: "u1").toFirebaseMap(),
            "horseBlankWinner": LiveHorseState(phase: "SETTING", winnerUid: " \u{A0}").toFirebaseMap(),
            "horseFinishedPhase": LiveHorseState(phase: "FINISHED").toFirebaseMap(),
            "sample0": Self.sampleSamples[0].toFirebaseMap(),
            "sample1": Self.sampleSamples[1].toFirebaseMap(),
            "sampleEdges": ShotReplaySample(
                tMs: -3, x: Float(bitPattern: 0x5f000000), y: Float(bitPattern: 0xdf000000),
                depth: Float(bitPattern: 0x60ad78ec)
            ).toFirebaseMap(),
            "sampleTiny": ShotReplaySample(
                tMs: Int64.max, x: -0.0, y: Float(bitPattern: 0x00000001), depth: Float(bitPattern: 0x3dcccccd)
            ).toFirebaseMap(),
            "shotDefault": LiveShotEvent().toFirebaseMap(),
            "shot": Self.sampleShot.toFirebaseMap(),
            "boardDefault": LeaderboardEntry().toFirebaseMap(),
            "board": Self.sampleBoard.toFirebaseMap(),
            "metaDefault": RoomMeta().toFirebaseMap(),
            "meta": Self.sampleMeta.toFirebaseMap(),
            "playerDefault": LivePlayerState().toFirebaseMap(),
            "player": Self.samplePlayer.toFirebaseMap()
        ]
        XCTAssertEqual(Set(objects.keys), Set(TSModelsGolden.encodeRows.keys))
        for (label, expected) in TSModelsGolden.encodeRows {
            guard let map = objects[label] else {
                XCTFail("missing object \(label)")
                continue
            }
            XCTAssertEqual(Self.wire(map), expected, label)
        }
        // The replay sample key is "tms" (getter getTMs()), never "tMs".
        XCTAssertEqual(Set(Self.sampleSamples[1].toFirebaseMap().keys), ["tms", "x", "y", "depth"])
    }

    /// The wire value in the notation of the JVM harness: S:"text", L:integer, D:0x<double bits>, B:bool, [..], {..}.
    static func wire(_ value: Any) -> String {
        if let text = value as? String {
            return "S:\"\(text)\""
        }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return "B:\(number.boolValue)"
            }
            if CFNumberIsFloatType(number as CFNumber) {
                return String(format: "D:0x%016llx", number.doubleValue.bitPattern)
            }
            return "L:\(number.int64Value)"
        }
        if let list = value as? [Any] {
            return "[" + list.map { wire($0) }.joined(separator: ", ") + "]"
        }
        if let map = value as? [String: Any] {
            return "{" + map.keys.sorted().map { "\($0)=\(wire(map[$0]!))" }.joined(separator: ", ") + "}"
        }
        return "?\(type(of: value))"
    }

    // MARK: - Firebase wire format: reading (DataSnapshot.getValue(X::class.java))

    static func bits(_ f: Float) -> String {
        return String(format: "0x%08x", f.bitPattern)
    }

    static func list(_ values: [String]) -> String {
        return "[" + values.joined(separator: ", ") + "]"
    }

    static func sortedMap(_ map: [String: Int]) -> String {
        return "{" + map.keys.sorted().map { "\($0)=\(map[$0]!)" }.joined(separator: ", ") + "}"
    }

    static func horseText(_ s: LiveHorseState) -> String {
        return "phase=\(s.phase)|setter=\(s.setterUid)|current=\(s.currentPlayerUid)|est=\(s.challengeEstablished)"
            + "|cat=\(s.challengeCategory)|spot=\(s.challengeSpotId)|x=\(bits(s.challengeSpotX))|y=\(bits(s.challengeSpotY))"
            + "|order=\(list(s.playerOrder))|attempted=\(list(s.attemptedUids))|penalties=\(sortedMap(s.penalties))"
            + "|slots=\(sortedMap(s.spectatorSlots))|winner=\(s.winnerUid)|turn=\(s.turnNumber)|updatedAt=\(s.updatedAt)"
            + "|isFinished=\(s.isFinished)"
    }

    static func sampleText(_ s: ShotReplaySample) -> String {
        return "tMs=\(s.tMs)|x=\(bits(s.x))|y=\(bits(s.y))|depth=\(bits(s.depth))"
    }

    static func shotText(_ e: LiveShotEvent) -> String {
        return "id=\(e.id)|uid=\(e.playerUid)|name=\(e.playerName)|sx=\(bits(e.shotSpotX))|sy=\(bits(e.shotSpotY))"
            + "|aim=\(bits(e.aimError))|power=\(bits(e.powerError))|arc=\(bits(e.arcError))|gyro=\(bits(e.rawPeakGyro))"
            + "|pitch=\(bits(e.rawReleasePitchDeg))|pull=\(bits(e.pullBack))|hot=\(e.hotHand)|releasedAt=\(e.releasedAt)"
            + "|made=\(e.made)|samples=\(list(e.samples.map { sampleText($0) }))"
    }

    static func boardText(_ e: LeaderboardEntry) -> String {
        return "uid=\(e.uid)|name=\(e.name)|bestScore=\(e.bestScore)|bss=\(e.bestShootingStreak)"
            + "|bks=\(e.bestKnowledgeStreak)|bca=\(e.bestCorrectAnswers)|brca=\(e.bestRunCorrectAnswers)"
            + "|brs=\(e.bestRunShots)|brms=\(e.bestRunMadeShots)|brka=\(e.bestRunKnowledgeAccuracyPercent)"
            + "|brsp=\(e.bestRunShootingPercent)|cats=\(list(e.bestRunCategories))|updatedAt=\(e.updatedAt)"
    }

    static func metaText(_ m: RoomMeta) -> String {
        return "host=\(m.hostUid)|status=\(m.status)|seed=\(m.seed)|createdAt=\(m.createdAt)|startedAt=\(m.startedAt)"
            + "|gameType=\(m.gameType)|cats=\(list(m.categories))|time=\(m.timeLimitSeconds)|max=\(m.maxPlayers)"
    }

    static func playerText(_ p: LivePlayerState) -> String {
        return "uid=\(p.uid)|name=\(p.name)|score=\(p.score)|ks=\(p.knowledgeStreak)|ss=\(p.shootingStreak)"
            + "|bks=\(p.bestKnowledgeStreak)|bss=\(p.bestShootingStreak)|ca=\(p.correctAnswers)|ms=\(p.madeShots)"
            + "|shots=\(p.shots)|last=\(p.lastEvent)|finished=\(p.finished)|updatedAt=\(p.updatedAt)"
    }

    /// "EXC": Android throws DatabaseException -> fromFirebaseOrThrow throws and fromFirebase is nil.
    /// "NULL": no node -> nil without throwing. "OK <fields>": both decoders return exactly these fields.
    private func checkDecode<T>(
        _ label: String,
        _ input: Any?,
        _ strict: (Any?) throws -> T?,
        _ lenient: (Any?) -> T?,
        _ show: (T) -> String,
        expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if expected == "EXC" {
            XCTAssertThrowsError(try strict(input), label, file: file, line: line)
            XCTAssertNil(lenient(input), label, file: file, line: line)
        } else if expected == "NULL" {
            XCTAssertNil(try strict(input), label, file: file, line: line)
            XCTAssertNil(lenient(input), label, file: file, line: line)
        } else {
            do {
                let strictValue = try strict(input)
                XCTAssertEqual(strictValue.map { "OK " + show($0) }, expected, label, file: file, line: line)
            } catch {
                XCTFail("\(label): unexpected \(error)", file: file, line: line)
            }
            XCTAssertEqual(lenient(input).map { "OK " + show($0) }, expected, label, file: file, line: line)
        }
    }

    func testFirebaseDecodingMatchesGetValue() {
        var seen = Set<String>()
        func golden(_ label: String, _ override: String?) -> String {
            seen.insert(label)
            return override ?? TSModelsGolden.decodeRows[label] ?? "missing golden row \(label)"
        }
        func horse(_ label: String, _ input: Any?, _ override: String? = nil, line: UInt = #line) {
            checkDecode(label, input, LiveHorseState.fromFirebaseOrThrow, LiveHorseState.fromFirebase, Self.horseText,
                        expected: golden(label, override), line: line)
        }
        func sample(_ label: String, _ input: Any?, _ override: String? = nil, line: UInt = #line) {
            checkDecode(label, input, ShotReplaySample.fromFirebaseOrThrow, ShotReplaySample.fromFirebase,
                        Self.sampleText, expected: golden(label, override), line: line)
        }
        func shot(_ label: String, _ input: Any?, _ override: String? = nil, line: UInt = #line) {
            checkDecode(label, input, LiveShotEvent.fromFirebaseOrThrow, LiveShotEvent.fromFirebase, Self.shotText,
                        expected: golden(label, override), line: line)
        }
        func board(_ label: String, _ input: Any?, _ override: String? = nil, line: UInt = #line) {
            checkDecode(label, input, LeaderboardEntry.fromFirebaseOrThrow, LeaderboardEntry.fromFirebase,
                        Self.boardText, expected: golden(label, override), line: line)
        }
        func meta(_ label: String, _ input: Any?, _ override: String? = nil, line: UInt = #line) {
            checkDecode(label, input, RoomMeta.fromFirebaseOrThrow, RoomMeta.fromFirebase, Self.metaText,
                        expected: golden(label, override), line: line)
        }
        func player(_ label: String, _ input: Any?, _ override: String? = nil, line: UInt = #line) {
            checkDecode(label, input, LivePlayerState.fromFirebaseOrThrow, LivePlayerState.fromFirebase,
                        Self.playerText, expected: golden(label, override), line: line)
        }

        horse("horseRoundTrip", Self.sampleHorse.toFirebaseMap())
        horse("horseNull", nil)
        horse("horseEmpty", [String: Any]())
        horse("horseString", "SETTING")
        horse("horseList", ["a"])
        horse("horseLong", Int64(5))
        horse("turnDouble4.9", ["turnNumber": 4.9])
        horse("turnDouble-4.9", ["turnNumber": -4.9])
        horse("turnDoubleMax", ["turnNumber": 2147483647.0])
        horse("turnDoubleMin", ["turnNumber": -2147483648.0])
        horse("turnDoubleOver", ["turnNumber": 2147483648.0])
        horse("turnDoubleOverHalf", ["turnNumber": 2147483647.5])
        horse("turnDoubleUnderHalf", ["turnNumber": -2147483648.5])
        horse("turnLongOver", ["turnNumber": Int64(2147483648)])
        horse("turnLongMin", ["turnNumber": Int64(-2147483648)])
        horse("turnInt", ["turnNumber": 7])
        horse("turnBool", ["turnNumber": true])
        horse("turnString", ["turnNumber": "4"])
        horse("updatedDouble1.5", ["updatedAt": 1.5])
        horse("updatedDouble-1.5", ["updatedAt": -1.5])
        horse("updatedDouble2p63", ["updatedAt": 9.223372036854775807E18])
        horse("updatedDouble-2p63", ["updatedAt": -9.223372036854775808E18])
        horse("updatedDouble1e19", ["updatedAt": 1e19])
        horse("updatedInt", ["updatedAt": 12])
        horse("updatedBool", ["updatedAt": false])
        horse("spotXLong", ["challengeSpotX": Int64(16777217)])
        horse("spotXLong2p53p1", ["challengeSpotX": Int64(9007199254740993)])
        horse("spotXLong2p53", ["challengeSpotX": Int64(9007199254740992)])
        horse("spotXDouble0.1", ["challengeSpotX": 0.1])
        horse("spotXDouble1e40", ["challengeSpotX": 1e40])
        horse("spotXDoubleTinyRound", ["challengeSpotX": 0.30000001192092896])
        horse("spotXBool", ["challengeSpotX": true])
        horse("spotXString", ["challengeSpotX": "1"])
        horse("estLong", ["challengeEstablished": Int64(1)])
        horse("estString", ["challengeEstablished": "true"])
        horse("estTrue", ["challengeEstablished": true])
        horse("phaseLong", ["phase": Int64(3)])
        horse("phaseBool", ["phase": true])
        horse("orderMap", ["playerOrder": ["a": "u1"]])
        horse("orderString", ["playerOrder": "u1"])
        // Deviation (impossible on Firebase): Android keeps a null element, a Swift [String] cannot hold one.
        horse(
            "orderNullHole", ["playerOrder": ["u1", NSNull(), "u3"] as [Any]],
            "OK phase=SETTING|setter=|current=|est=false|cat=|spot=|x=0x00000000|y=0x00000000|order=[u1, u3]"
                + "|attempted=[]|penalties={}|slots={}|winner=|turn=0|updatedAt=0|isFinished=false"
        )
        horse("orderNumber", ["playerOrder": ["u1", Int64(2)] as [Any]])
        horse("penaltiesList", ["penalties": [Int64(1), Int64(2)]])
        horse("penaltiesDouble", ["penalties": ["u1": 1.7, "u2": -2.2]])
        horse("penaltiesBool", ["penalties": ["u1": true]])
        horse("penaltiesString", ["penalties": "x"])
        horse("slotsOver", ["spectatorSlots": ["u1": Int64(3000000000)]])
        horse("unknownKeys", ["Phase": "ATTEMPT", "finished": true, "extra": Int64(5), "phase": "ATTEMPT"] as [String: Any])
        // Deviation (impossible on Firebase): Android stores the JSON null into the non-null field (the harness
        // then fails in isFinished); iOS skips it and keeps the default.
        horse(
            "nullField", ["winnerUid": NSNull(), "turnNumber": Int64(3)] as [String: Any],
            "OK phase=SETTING|setter=|current=|est=false|cat=|spot=|x=0x00000000|y=0x00000000|order=[]"
                + "|attempted=[]|penalties={}|slots={}|winner=|turn=3|updatedAt=0|isFinished=false"
        )

        sample("sampleTms", ["tms": Int64(55), "x": 430.5, "y": 1010.25, "depth": Int64(0)] as [String: Any])
        sample("sampleTMs", ["tMs": Int64(55), "x": 430.5, "y": 1010.25, "depth": Int64(0)] as [String: Any])
        sample("sampleBoth", ["tMs": Int64(70), "tms": Int64(55)])
        sample("sampleTMsDouble", ["tMs": 55.9])

        shot("shotRoundTrip", Self.sampleShot.toFirebaseMap())
        shot("shotEmpty", [String: Any]())
        shot("shotSampleString", ["id": "x", "samples": ["bad"]] as [String: Any])
        // Deviation (impossible on Firebase): Android keeps the null sample element, iOS skips it.
        shot(
            "shotSampleNull", ["id": "x", "samples": [["tMs": Int64(1)], NSNull()] as [Any]] as [String: Any],
            "OK id=x|uid=|name=|sx=0x00000000|sy=0x00000000|aim=0x00000000|power=0x00000000|arc=0x00000000"
                + "|gyro=0x00000000|pitch=0x00000000|pull=0x00000000|hot=false|releasedAt=0|made=false"
                + "|samples=[tMs=1|x=0x00000000|y=0x00000000|depth=0x00000000]"
        )
        shot("shotSamplesMap", ["samples": ["a": ["tMs": Int64(1)]]])
        shot("shotHotLong", ["hotHand": Int64(0)])
        shot("shotReleasedDouble", ["releasedAt": 1760000031234.75])

        board("boardRoundTrip", Self.sampleBoard.toFirebaseMap())
        board("boardEmpty", [String: Any]())
        board("boardScoreDouble", ["bestScore": 57.99, "name": "N"] as [String: Any])
        board("boardCatsNumber", ["bestRunCategories": [Int64(1)]])
        board("boardNameNumber", ["name": Int64(5)])

        meta("metaRoundTrip", Self.sampleMeta.toFirebaseMap())
        meta("metaEmpty", [String: Any]())
        meta("metaExtra", ["hostUid": "h", "selectedCategories": ["AI"], "seed": 1.8446744073709552E19] as [String: Any])
        meta("metaSeedDouble", ["seed": -4.611686018427388E18])
        meta("metaMaxDouble", ["maxPlayers": 4.0, "timeLimitSeconds": Int64(600)] as [String: Any])

        player("playerRoundTrip", Self.samplePlayer.toFirebaseMap())
        player("playerEmpty", [String: Any]())
        player("playerFinishedLong", ["finished": Int64(1)])
        player("playerServerTs", ["uid": "u", "updatedAt": [".sv": "timestamp"]] as [String: Any])

        XCTAssertEqual(seen, Set(TSModelsGolden.decodeRows.keys))
    }

    /// Values as the iOS Firebase SDK delivers them: Foundation objects from JSON (NSNumber, CFBoolean, NSString,
    /// NSArray, NSDictionary, possibly NSDecimalNumber), and NSNull for an empty MutableData.
    func testDecodingFoundationValuesFromJSON() throws {
        let json = #"{"phase":"ATTEMPT","turnNumber":4,"challengeSpotX":0.699999988079071,"challengeSpotY":512,"#
            + #""challengeEstablished":true,"updatedAt":1760000030000,"penalties":{"u1":2},"playerOrder":["u1","u2"],"#
            + #""finished":true}"#
        let value = try JSONSerialization.jsonObject(with: Data(json.utf8))
        let state = try XCTUnwrap(LiveHorseState.fromFirebaseOrThrow(value))
        XCTAssertEqual(state.phase, "ATTEMPT")
        XCTAssertEqual(state.turnNumber, 4)
        XCTAssertEqual(state.challengeSpotX.bitPattern, 0x3f333333)
        XCTAssertEqual(state.challengeSpotY.bitPattern, 0x44000000)
        XCTAssertTrue(state.challengeEstablished)
        XCTAssertEqual(state.updatedAt, 1760000030000)
        XCTAssertEqual(state.penalties, ["u1": 2])
        XCTAssertEqual(state.playerOrder, ["u1", "u2"])
        XCTAssertFalse(state.isFinished) // the "finished" key is ignored; isFinished comes from phase/winnerUid

        // A JSON boolean is not a number and a number is not a boolean.
        let boolTurn = try JSONSerialization.jsonObject(with: Data(#"{"turnNumber":true}"#.utf8))
        XCTAssertThrowsError(try LiveHorseState.fromFirebaseOrThrow(boolTurn))
        let numberFlag = try JSONSerialization.jsonObject(with: Data(#"{"challengeEstablished":1}"#.utf8))
        XCTAssertThrowsError(try LiveHorseState.fromFirebaseOrThrow(numberFlag))
        XCTAssertNil(LiveHorseState.fromFirebase(numberFlag))

        // NSDecimalNumber is read from its exact decimal text.
        let decimal = try XCTUnwrap(LiveShotEvent.fromFirebaseOrThrow([
            "aimError": NSDecimalNumber(string: "0.10000000149011612"),
            "releasedAt": NSDecimalNumber(string: "1760000031234")
        ] as [String: Any]))
        XCTAssertEqual(decimal.aimError.bitPattern, 0x3dcccccd)
        XCTAssertEqual(decimal.releasedAt, 1760000031234)

        // MutableData.value of an empty node is NSNull: no object, no error.
        XCTAssertNil(try LiveHorseState.fromFirebaseOrThrow(NSNull()))
        XCTAssertNil(try LeaderboardEntry.fromFirebaseOrThrow(nil))
    }

    /// toFirebaseMap -> JSON (what the SDK sends) -> Foundation objects -> fromFirebase, like an Android receiver.
    func testWireRoundTripKeepsTheAndroidQuirks() throws {
        func throughJSON(_ map: [String: Any]) throws -> Any {
            return try JSONSerialization.jsonObject(with: try JSONSerialization.data(withJSONObject: map))
        }

        let shotNode = try throughJSON(Self.sampleShot.toFirebaseMap())
        let shot = try XCTUnwrap(LiveShotEvent.fromFirebaseOrThrow(shotNode))
        // Replay timing is lost exactly as on Android: "tms" is written, only "tMs" would be read.
        XCTAssertEqual(shot.samples.map { $0.tMs }, [0, 0])
        var expected = Self.sampleShot
        expected.samples = Self.sampleShot.samples.map { sample in
            var copy = sample
            copy.tMs = 0
            return copy
        }
        XCTAssertEqual(shot, expected)
        let sampleKeys = try XCTUnwrap((shotNode as? [String: Any])?["samples"] as? [[String: Any]]).map { Set($0.keys) }
        XCTAssertEqual(sampleKeys, [["tms", "x", "y", "depth"], ["tms", "x", "y", "depth"]])

        let horseNode = try throughJSON(Self.sampleHorse.toFirebaseMap())
        XCTAssertEqual(try LiveHorseState.fromFirebaseOrThrow(horseNode), Self.sampleHorse)
        XCTAssertEqual((horseNode as? [String: Any])?["finished"] as? Bool, false)

        XCTAssertEqual(try LeaderboardEntry.fromFirebaseOrThrow(try throughJSON(Self.sampleBoard.toFirebaseMap())),
                       Self.sampleBoard)
        XCTAssertEqual(try RoomMeta.fromFirebaseOrThrow(try throughJSON(Self.sampleMeta.toFirebaseMap())), Self.sampleMeta)
        XCTAssertEqual(try LivePlayerState.fromFirebaseOrThrow(try throughJSON(Self.samplePlayer.toFirebaseMap())),
                       Self.samplePlayer)
    }

    // MARK: - Firebase wire format: Android's exception texts and ClassMapper warnings

    /// The exact DatabaseException texts (they reach the UI through a transaction's onComplete error) and the
    /// "No setter/field" warnings, in Android's order: the entries are visited in java.util.HashMap order, so
    /// with several bad keys the same key fails first. Inputs are the plain values DataSnapshot.getValue()
    /// hands to CustomClassMapper (maps, lists, Int64 for Long, Double, Bool, String).
    func testFirebaseDecodingErrorsAndWarningsMatchAndroid() {
        var warnings: [String] = []
        TripleShotModelsFirebaseCodec.warningSink = { warnings.append(TripleShotModelsFirebaseCodec.LOG_TAG + ": " + $0) }
        defer { TripleShotModelsFirebaseCodec.warningSink = nil }
        var seen = Set<String>()

        func check<T>(_ label: String, _ input: Any, _ decode: (Any?) throws -> T?, line: UInt = #line) {
            seen.insert(label)
            warnings.removeAll()
            var outcome: String
            do {
                outcome = try decode(input) == nil ? "NULL" : "OK"
            } catch let error as ADatabaseException {
                outcome = "EXC com.google.firebase.database.DatabaseException: " + (error.message ?? "")
            } catch {
                outcome = "UNEXPECTED \(error)"
            }
            XCTAssertEqual(outcome + " ## " + warnings.joined(separator: " ;; "), TSModelsAndroidMessages.rows[label],
                           label, line: line)
        }

        check("horseString", "SETTING", LiveHorseState.fromFirebaseOrThrow)
        check("horseList", ["a"] as [Any], LiveHorseState.fromFirebaseOrThrow)
        check("horseLong", Int64(5), LiveHorseState.fromFirebaseOrThrow)
        check("horseDouble", 2.5, LiveHorseState.fromFirebaseOrThrow)
        check("horseBool", true, LiveHorseState.fromFirebaseOrThrow)
        check("turnDoubleOver", ["turnNumber": 2147483648.0] as [String: Any], LiveHorseState.fromFirebaseOrThrow)
        check("turnDoubleUnderHalf", ["turnNumber": -2147483648.5] as [String: Any], LiveHorseState.fromFirebaseOrThrow)
        check("turnLongOver", ["turnNumber": Int64(2147483648)] as [String: Any], LiveHorseState.fromFirebaseOrThrow)
        check("turnBool", ["turnNumber": true] as [String: Any], LiveHorseState.fromFirebaseOrThrow)
        check("turnString", ["turnNumber": "4"] as [String: Any], LiveHorseState.fromFirebaseOrThrow)
        check("turnList", ["turnNumber": [Int64(1)] as [Any]] as [String: Any], LiveHorseState.fromFirebaseOrThrow)
        check("turnMap", ["turnNumber": ["a": Int64(1)] as [String: Any]] as [String: Any], LiveHorseState.fromFirebaseOrThrow)
        check("updatedDouble1e19", ["updatedAt": 1e19] as [String: Any], LiveHorseState.fromFirebaseOrThrow)
        check("updatedDoubleMinus1e19", ["updatedAt": -1e19] as [String: Any], LiveHorseState.fromFirebaseOrThrow)
        check("updatedBool", ["updatedAt": false] as [String: Any], LiveHorseState.fromFirebaseOrThrow)
        check("updatedString", ["updatedAt": "1"] as [String: Any], LiveHorseState.fromFirebaseOrThrow)
        check("spotXLong2p53p1", ["challengeSpotX": Int64(9007199254740993)] as [String: Any], LiveHorseState.fromFirebaseOrThrow)
        check("spotXLongMin", ["challengeSpotX": Int64.min] as [String: Any], LiveHorseState.fromFirebaseOrThrow)
        check("spotXBool", ["challengeSpotX": true] as [String: Any], LiveHorseState.fromFirebaseOrThrow)
        check("spotXString", ["challengeSpotX": "1"] as [String: Any], LiveHorseState.fromFirebaseOrThrow)
        check("estLong", ["challengeEstablished": Int64(1)] as [String: Any], LiveHorseState.fromFirebaseOrThrow)
        check("estDouble", ["challengeEstablished": 1.5] as [String: Any], LiveHorseState.fromFirebaseOrThrow)
        check("estString", ["challengeEstablished": "true"] as [String: Any], LiveHorseState.fromFirebaseOrThrow)
        check("phaseLong", ["phase": Int64(3)] as [String: Any], LiveHorseState.fromFirebaseOrThrow)
        check("phaseDouble", ["phase": 3.5] as [String: Any], LiveHorseState.fromFirebaseOrThrow)
        check("phaseBool", ["phase": true] as [String: Any], LiveHorseState.fromFirebaseOrThrow)
        check("phaseList", ["phase": ["a"] as [Any]] as [String: Any], LiveHorseState.fromFirebaseOrThrow)
        check("phaseMap", ["phase": ["a": "b"] as [String: Any]] as [String: Any], LiveHorseState.fromFirebaseOrThrow)
        check("orderMap", ["playerOrder": ["a": "u1"] as [String: Any]] as [String: Any], LiveHorseState.fromFirebaseOrThrow)
        check("orderSparse", ["playerOrder": ["0": "a", "5": "b"] as [String: Any]] as [String: Any], LiveHorseState.fromFirebaseOrThrow)
        check("orderString", ["playerOrder": "u1"] as [String: Any], LiveHorseState.fromFirebaseOrThrow)
        check("orderNumber", ["playerOrder": ["u1", Int64(2)] as [Any]] as [String: Any], LiveHorseState.fromFirebaseOrThrow)
        check("penaltiesList", ["penalties": [Int64(1), Int64(2)] as [Any]] as [String: Any], LiveHorseState.fromFirebaseOrThrow)
        check("penaltiesBool", ["penalties": ["u1": true] as [String: Any]] as [String: Any], LiveHorseState.fromFirebaseOrThrow)
        check("penaltiesString", ["penalties": "x"] as [String: Any], LiveHorseState.fromFirebaseOrThrow)
        check("slotsOver", ["spectatorSlots": ["u1": Int64(3000000000)] as [String: Any]] as [String: Any], LiveHorseState.fromFirebaseOrThrow)
        check("unknownKeys", ["Phase": "ATTEMPT", "finished": true, "extra": Int64(5), "phase": "ATTEMPT", "zzz": Int64(1), "PLAYERORDER": "x"] as [String: Any], LiveHorseState.fromFirebaseOrThrow)
        check("twoBadKeys", ["turnNumber": "x", "phase": Int64(3), "winnerUid": true] as [String: Any], LiveHorseState.fromFirebaseOrThrow)
        check("threeBadKeys", ["updatedAt": "u", "setterUid": Int64(1), "challengeSpotY": false, "turnNumber": 1e10] as [String: Any], LiveHorseState.fromFirebaseOrThrow)
        check("badPenaltyOrder", ["penalties": ["uidA": "x", "uidB": true, "uidC": Int64(3000000000)] as [String: Any]] as [String: Any], LiveHorseState.fromFirebaseOrThrow)
        check("sampleTms", ["tms": Int64(55), "x": 430.5, "y": 1010.25, "depth": Int64(0)] as [String: Any], ShotReplaySample.fromFirebaseOrThrow)
        check("sampleString", "s", ShotReplaySample.fromFirebaseOrThrow)
        check("sampleBadX", ["x": "1", "tms": Int64(3)] as [String: Any], ShotReplaySample.fromFirebaseOrThrow)
        check("shotSampleString", ["id": "x", "samples": ["bad"] as [Any]] as [String: Any], LiveShotEvent.fromFirebaseOrThrow)
        check("shotSamplesMap", ["samples": ["a": ["tMs": Int64(1)] as [String: Any]] as [String: Any]] as [String: Any], LiveShotEvent.fromFirebaseOrThrow)
        check("shotHotLong", ["hotHand": Int64(0)] as [String: Any], LiveShotEvent.fromFirebaseOrThrow)
        check("shotSampleBadTms", ["samples": [["tMs": "1"] as [String: Any]] as [Any]] as [String: Any], LiveShotEvent.fromFirebaseOrThrow)
        check("shotWarnings", ["samples": [["tms": Int64(0), "x": Int64(1)] as [String: Any], ["tms": Int64(55), "y": Int64(2)] as [String: Any]] as [Any], "finished": true, "tMs": Int64(3)] as [String: Any], LiveShotEvent.fromFirebaseOrThrow)
        check("boardCatsNumber", ["bestRunCategories": [Int64(1)] as [Any]] as [String: Any], LeaderboardEntry.fromFirebaseOrThrow)
        check("boardNameNumber", ["name": Int64(5)] as [String: Any], LeaderboardEntry.fromFirebaseOrThrow)
        check("boardScoreString", ["bestScore": "57"] as [String: Any], LeaderboardEntry.fromFirebaseOrThrow)
        check("boardCatsMap", ["bestRunCategories": ["x": "AI"] as [String: Any]] as [String: Any], LeaderboardEntry.fromFirebaseOrThrow)
        check("metaSeedOver", ["seed": 1.8446744073709552E19] as [String: Any], RoomMeta.fromFirebaseOrThrow)
        check("metaExtra", ["hostUid": "h", "selectedCategories": ["AI"] as [Any], "seed": 1.8446744073709552E19] as [String: Any], RoomMeta.fromFirebaseOrThrow)
        check("metaCatsString", ["categories": "AI"] as [String: Any], RoomMeta.fromFirebaseOrThrow)
        check("playerFinishedLong", ["finished": Int64(1)] as [String: Any], LivePlayerState.fromFirebaseOrThrow)
        check("playerScoreDouble", ["score": 1e12] as [String: Any], LivePlayerState.fromFirebaseOrThrow)
        check("playerUnknown", ["Uid": "u", "isFinished": true] as [String: Any], LivePlayerState.fromFirebaseOrThrow)

        XCTAssertEqual(seen, Set(TSModelsAndroidMessages.rows.keys))

        // Reading back what this app writes logs the same warnings as Android ("finished", "tms").
        warnings.removeAll()
        XCTAssertNotNil(LiveHorseState.fromFirebase(Self.sampleHorse.toFirebaseMap()))
        XCTAssertEqual(warnings, [
            "ClassMapper: No setter/field for finished found on class com.appsbybros.minik.swish.model.LiveHorseState"
                + " (fields/setters are case sensitive!)"
        ])
        warnings.removeAll()
        XCTAssertNotNil(LiveShotEvent.fromFirebase(Self.sampleShot.toFirebaseMap()))
        XCTAssertEqual(warnings, [String](repeating:
            "ClassMapper: No setter/field for tms found on class com.appsbybros.minik.swish.model.ShotReplaySample"
                + " (fields/setters are case sensitive!)", count: 2))
        warnings.removeAll()
        XCTAssertNotNil(LeaderboardEntry.fromFirebase(Self.sampleBoard.toFirebaseMap()))
        XCTAssertNotNil(RoomMeta.fromFirebase(Self.sampleMeta.toFirebaseMap()))
        XCTAssertNotNil(LivePlayerState.fromFirebase(Self.samplePlayer.toFirebaseMap()))
        XCTAssertEqual(warnings, [])
    }

    // MARK: - Data-class equality and the Kotlin named-argument forms

    func testGameConfigEqualityIsKotlinDataClassEquality() {
        let a = TripleShotGameConfig(playerName: "P", selectedCategories: [QuestionCategory.AI, .MATH], seed: 1)
        let b = TripleShotGameConfig(playerName: "P", selectedCategories: [QuestionCategory.MATH, .AI], seed: 1)
        // Set equality ignores the order (java.util.AbstractSet.equals); iteration keeps the producer's order.
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.hashValue, b.hashValue)
        XCTAssertEqual(a.selectedCategories.elements, [.AI, .MATH])
        XCTAssertEqual(b.selectedCategories.elements, [.MATH, .AI])
        XCTAssertNotEqual(a, a.copy(seed: 2))
        XCTAssertNotEqual(a, a.copy(roomId: "R"))
        XCTAssertEqual(a, a.copy(roomId: "R").copy(roomId: nil))
        XCTAssertEqual(LiveHorseState(phase: "SETTING"), LiveHorseState())
        XCTAssertEqual(LiveHorseState(penalties: ["a": 1, "b": 0]), LiveHorseState(penalties: ["b": 0, "a": 1]))
    }

    func testKotlinNamedArgumentForms() {
        XCTAssertEqual(QuestionCategory.AI.labelFor(languageCode: "en"), "Artificial intelligence")
        XCTAssertEqual(QuestionCategory.AI.labelFor(languageCode: "he"), QuestionCategory.AI.label)
        XCTAssertEqual(QuestionCategory.AI.labelFor("EN"), "Artificial intelligence")
        XCTAssertEqual(TripleShotCharacterRoster.find(id: "minik")?.id, "bob")
        XCTAssertNil(TripleShotCharacterRoster.find(id: nil))
        XCTAssertEqual(TripleShotCharacterRoster.requireProfile(id: "nope").id, "woman_dark")
        XCTAssertEqual(TripleShotCharacterRoster.ace23.ratings.shootingFor(zone: .THREE_POINT), 88)
        XCTAssertEqual(TripleShotCharacterRoster.unicorn32.ratings.shootingFor(.INSIDE), 92)
        XCTAssertTrue(OnlineNickname.valid(value: " Gaya "))
        XCTAssertFalse(OnlineNickname.valid(value: "Nir12"))
        XCTAssertEqual(TripleShotCourtCatalog.find(id: "neon_tide").id, "neon_tide")
        XCTAssertEqual(TripleShotCourtCatalog.find(id: nil).id, TripleShotCourtCatalog.DEFAULT_ID)
    }
}

/// JVM golden values (generated from the harness output; see the header comment).
private enum TSModelsGolden {
    /// OnlineNickname.valid on the JVM (Kotlin trim + java.text.Normalizer NFC + Character.isLetter).
    static let nicknameVectors: [(String, Bool)] = [
        ("\u{47}\u{61}\u{79}\u{61}", true),
        ("\u{43}\u{6F}\u{6D}\u{65}\u{74}", true),
        ("\u{5E0}\u{5D9}\u{5E6}\u{5D5}\u{5E5}", true),
        ("\u{4A}\u{6F}\u{73}\u{E9}", true),
        ("\u{C9}\u{6D}\u{69}\u{6C}\u{65}", true),
        ("", false),
        ("\u{41}\u{6C}\u{65}\u{78}\u{61}\u{6E}\u{64}\u{65}\u{72}", false),
        ("\u{4A}\u{6F}\u{68}\u{6E}\u{20}\u{53}\u{6D}\u{69}\u{74}\u{68}", false),
        ("\u{4E}\u{69}\u{72}\u{31}\u{32}", false),
        ("\u{41}\u{42}\u{43}\u{202E}", false),
        ("\u{31}\u{32}\u{33}\u{34}\u{35}", false),
        ("\u{FF21}\u{FF22}\u{FF23}\u{FF24}\u{FF25}\u{FF26}", false),
        ("\u{45}\u{301}\u{6D}\u{69}\u{6C}\u{65}", true),
        ("\u{45}\u{301}\u{6D}\u{69}\u{6C}\u{65}\u{65}", false),
        ("\u{20}\u{47}\u{61}\u{79}\u{61}\u{20}", true),
        ("\u{A0}\u{47}\u{61}\u{79}\u{61}\u{A0}", true),
        ("\u{2007}\u{41}\u{62}\u{202F}", true),
        ("\u{9}\u{41}\u{62}\u{A}", true),
        ("\u{1C}\u{41}\u{62}\u{1F}", true),
        ("\u{85}\u{41}\u{62}", false),
        ("\u{200B}\u{41}\u{62}", false),
        ("\u{3000}\u{41}\u{62}", true),
        ("\u{41}\u{62}\u{2028}", true),
        ("\u{41}\u{62}\u{2029}", true),
        ("\u{FF21}\u{FF22}\u{FF23}\u{FF24}\u{FF25}", true),
        ("\u{5E9}\u{5B8}\u{5C1}\u{5DC}\u{5D5}\u{5B9}\u{5DD}", false),
        ("\u{5E9}\u{5DC}\u{5D5}\u{5DD}", true),
        ("\u{1C5}\u{61}", true),
        ("\u{2B0}\u{61}", true),
        ("\u{61}\u{301}", true),
        ("\u{1F600}", false),
        ("\u{1D49C}\u{62}\u{63}", true),
        ("\u{1D49C}\u{1D49C}\u{1D49C}\u{1D49C}\u{1D49C}", true),
        ("\u{1D49C}\u{1D49C}\u{1D49C}\u{1D49C}\u{1D49C}\u{1D49C}", false),
        ("\u{61}\u{200D}\u{62}", false),
        ("\u{61}\u{200C}\u{62}", false),
        ("\u{216B}", false),
        ("\u{AA}", true),
        ("\u{2170}", false),
        ("\u{AC00}\u{B098}\u{B2E4}\u{B77C}\u{B9C8}", true),
        ("\u{AC00}\u{B098}\u{B2E4}\u{B77C}\u{B9C8}\u{BC14}", false),
        ("\u{1100}\u{1161}", true),
        ("\u{1100}\u{1161}\u{1100}\u{1161}\u{1100}\u{1161}\u{1100}\u{1161}\u{1100}\u{1161}\u{1100}\u{1161}", false),
        ("\u{212B}", true),
        ("\u{2126}", true),
        ("\u{212A}", true),
        ("\u{FB01}", true),
        ("\u{5D2}\u{5F3}", false),
        ("\u{633}\u{644}\u{627}\u{645}", true),
        ("\u{633}\u{64E}\u{644}\u{627}\u{645}", false),
        ("\u{4E}\u{69}\u{72}\u{20}", true),
        ("\u{20}", false),
        ("\u{A0}", false),
        ("\u{301}", false),
        ("\u{661}\u{662}\u{663}", false),
        ("\u{61}\u{62}\u{63}\u{64}\u{65}", true),
        ("\u{61}\u{62}\u{63}\u{64}\u{65}\u{66}", false),
        ("\u{41}\u{20}\u{42}", false),
        ("\u{5F}\u{61}\u{62}", false),
        ("\u{61}\u{62}\u{2D}\u{63}", false),
        ("\u{1E9E}", true),
    ]

    /// (ordinal, name, Hebrew label, English label) from QuestionCategory.values().
    static let categoryRows: [(Int, String, String, String)] = [
        (0, "GENERAL_KNOWLEDGE", "\u{5D9}\u{5D3}\u{5E2} \u{5DB}\u{5DC}\u{5DC}\u{5D9}", "General knowledge"),
        (1, "PROGRAMMING", "\u{5E8}\u{5D0}\u{5D9}\u{5D5}\u{5DF} \u{5EA}\u{5DB}\u{5E0}\u{5D5}\u{5EA}", "Programming interview"),
        (2, "SCIENCE", "\u{5DE}\u{5D3}\u{5E2}", "Science"),
        (3, "ASTRONOMY", "\u{5D0}\u{5E1}\u{5D8}\u{5E8}\u{5D5}\u{5E0}\u{5D5}\u{5DE}\u{5D9}\u{5D4}", "Astronomy"),
        (4, "PARADOX", "\u{5E4}\u{5E8}\u{5D3}\u{5D5}\u{5E7}\u{5E1}\u{5D9}\u{5DD} \u{5D1}\u{5DE}\u{5D3}\u{5E2} \u{5D5}\u{5DE}\u{5D7}\u{5E9}\u{5D1}\u{5D4}", "Science & thought paradoxes"),
        (5, "AI", "\u{5D1}\u{5D9}\u{5E0}\u{5D4} \u{5DE}\u{5DC}\u{5D0}\u{5DB}\u{5D5}\u{5EA}\u{5D9}\u{5EA}", "Artificial intelligence"),
        (6, "HISTORY", "\u{5D4}\u{5D9}\u{5E1}\u{5D8}\u{5D5}\u{5E8}\u{5D9}\u{5D4}", "History"),
        (7, "ENGLISH", "\u{5DC}\u{5D9}\u{5DE}\u{5D5}\u{5D3} \u{5D0}\u{5E0}\u{5D2}\u{5DC}\u{5D9}\u{5EA}", "Learn English"),
        (8, "KIDS_ARITHMETIC", "\u{5D7}\u{5E9}\u{5D1}\u{5D5}\u{5DF} \u{5DC}\u{5D9}\u{5DC}\u{5D3}\u{5D9}\u{5DD}", "Kids arithmetic"),
        (9, "MATH", "\u{5DE}\u{5EA}\u{5DE}\u{5D8}\u{5D9}\u{5E7}\u{5D4}", "Mathematics"),
        (10, "MATRICULATION_MATH", "\u{5DE}\u{5EA}\u{5DE}\u{5D8}\u{5D9}\u{5E7}\u{5D4} \u{5DC}\u{5D1}\u{5D2}\u{5E8}\u{5D5}\u{5EA} - \u{5EA}\u{5E8}\u{5D2}\u{5D5}\u{5DC}", "Matriculation math practice"),
    ]

    static let categoryNamesSorted = ["AI", "ASTRONOMY", "ENGLISH", "GENERAL_KNOWLEDGE", "HISTORY", "KIDS_ARITHMETIC", "MATH", "MATRICULATION_MATH", "PARADOX", "PROGRAMMING", "SCIENCE"]

    static let orientationNames = ["PORTRAIT", "LANDSCAPE"]
    static let gameTypeNames = ["PRACTICE", "SHOOTING_CHALLENGE", "HORSE", "ONE_ON_ONE", "TEAM_MATCH"]
    static let limitModeNames = ["RANKED_BOTH", "BALLS_ONLY", "TIME_ONLY"]
    static let shotZoneNames = ["INSIDE", "MID_RANGE", "THREE_POINT"]
    static let genderNames = ["FEMALE", "MALE", "NEUTRAL"]
    static let archetypeNames = ["ADAPTIVE_TRAINER", "BALANCED", "SHARPSHOOTER", "SLASHER", "DEFENDER", "BIG"]
    static let atmosphereNames = ["NONE", "COLORED_LIGHTS", "LIGHT_SNOW", "LIGHT_RAIN"]

    /// GameType|roomId|botMatch|teamSize -> isMultiplayer isPractice isBotMatch isOneOnOne isTeamMatch isRanked
    static let configFlagLines = """
        PRACTICE|null|0|1 -> M0 P1 B0 O0 T0 R0
        PRACTICE|null|0|2 -> M0 P1 B0 O0 T0 R0
        PRACTICE|null|0|3 -> M0 P1 B0 O0 T0 R0
        PRACTICE|null|0|4 -> M0 P1 B0 O0 T0 R0
        PRACTICE|null|1|1 -> M0 P0 B1 O0 T0 R0
        PRACTICE|null|1|2 -> M0 P0 B1 O0 T0 R0
        PRACTICE|null|1|3 -> M0 P0 B1 O0 T0 R0
        PRACTICE|null|1|4 -> M0 P0 B1 O0 T0 R0
        PRACTICE|''|0|1 -> M0 P1 B0 O0 T0 R0
        PRACTICE|''|0|2 -> M0 P1 B0 O0 T0 R0
        PRACTICE|''|0|3 -> M0 P1 B0 O0 T0 R0
        PRACTICE|''|0|4 -> M0 P1 B0 O0 T0 R0
        PRACTICE|''|1|1 -> M0 P0 B1 O0 T0 R0
        PRACTICE|''|1|2 -> M0 P0 B1 O0 T0 R0
        PRACTICE|''|1|3 -> M0 P0 B1 O0 T0 R0
        PRACTICE|''|1|4 -> M0 P0 B1 O0 T0 R0
        PRACTICE|' '|0|1 -> M1 P0 B0 O0 T0 R0
        PRACTICE|' '|0|2 -> M1 P0 B0 O0 T0 R0
        PRACTICE|' '|0|3 -> M1 P0 B0 O0 T0 R0
        PRACTICE|' '|0|4 -> M1 P0 B0 O0 T0 R0
        PRACTICE|' '|1|1 -> M1 P0 B0 O0 T0 R0
        PRACTICE|' '|1|2 -> M1 P0 B0 O0 T0 R0
        PRACTICE|' '|1|3 -> M1 P0 B0 O0 T0 R0
        PRACTICE|' '|1|4 -> M1 P0 B0 O0 T0 R0
        PRACTICE|'R'|0|1 -> M1 P0 B0 O0 T0 R0
        PRACTICE|'R'|0|2 -> M1 P0 B0 O0 T0 R0
        PRACTICE|'R'|0|3 -> M1 P0 B0 O0 T0 R0
        PRACTICE|'R'|0|4 -> M1 P0 B0 O0 T0 R0
        PRACTICE|'R'|1|1 -> M1 P0 B0 O0 T0 R0
        PRACTICE|'R'|1|2 -> M1 P0 B0 O0 T0 R0
        PRACTICE|'R'|1|3 -> M1 P0 B0 O0 T0 R0
        PRACTICE|'R'|1|4 -> M1 P0 B0 O0 T0 R0
        SHOOTING_CHALLENGE|null|0|1 -> M0 P0 B0 O0 T0 R1
        SHOOTING_CHALLENGE|null|0|2 -> M0 P0 B0 O0 T0 R1
        SHOOTING_CHALLENGE|null|0|3 -> M0 P0 B0 O0 T0 R1
        SHOOTING_CHALLENGE|null|0|4 -> M0 P0 B0 O0 T0 R1
        SHOOTING_CHALLENGE|null|1|1 -> M0 P0 B1 O0 T0 R1
        SHOOTING_CHALLENGE|null|1|2 -> M0 P0 B1 O0 T0 R1
        SHOOTING_CHALLENGE|null|1|3 -> M0 P0 B1 O0 T0 R1
        SHOOTING_CHALLENGE|null|1|4 -> M0 P0 B1 O0 T0 R1
        SHOOTING_CHALLENGE|''|0|1 -> M0 P0 B0 O0 T0 R1
        SHOOTING_CHALLENGE|''|0|2 -> M0 P0 B0 O0 T0 R1
        SHOOTING_CHALLENGE|''|0|3 -> M0 P0 B0 O0 T0 R1
        SHOOTING_CHALLENGE|''|0|4 -> M0 P0 B0 O0 T0 R1
        SHOOTING_CHALLENGE|''|1|1 -> M0 P0 B1 O0 T0 R1
        SHOOTING_CHALLENGE|''|1|2 -> M0 P0 B1 O0 T0 R1
        SHOOTING_CHALLENGE|''|1|3 -> M0 P0 B1 O0 T0 R1
        SHOOTING_CHALLENGE|''|1|4 -> M0 P0 B1 O0 T0 R1
        SHOOTING_CHALLENGE|' '|0|1 -> M1 P0 B0 O0 T0 R0
        SHOOTING_CHALLENGE|' '|0|2 -> M1 P0 B0 O0 T0 R0
        SHOOTING_CHALLENGE|' '|0|3 -> M1 P0 B0 O0 T0 R0
        SHOOTING_CHALLENGE|' '|0|4 -> M1 P0 B0 O0 T0 R0
        SHOOTING_CHALLENGE|' '|1|1 -> M1 P0 B0 O0 T0 R0
        SHOOTING_CHALLENGE|' '|1|2 -> M1 P0 B0 O0 T0 R0
        SHOOTING_CHALLENGE|' '|1|3 -> M1 P0 B0 O0 T0 R0
        SHOOTING_CHALLENGE|' '|1|4 -> M1 P0 B0 O0 T0 R0
        SHOOTING_CHALLENGE|'R'|0|1 -> M1 P0 B0 O0 T0 R0
        SHOOTING_CHALLENGE|'R'|0|2 -> M1 P0 B0 O0 T0 R0
        SHOOTING_CHALLENGE|'R'|0|3 -> M1 P0 B0 O0 T0 R0
        SHOOTING_CHALLENGE|'R'|0|4 -> M1 P0 B0 O0 T0 R0
        SHOOTING_CHALLENGE|'R'|1|1 -> M1 P0 B0 O0 T0 R0
        SHOOTING_CHALLENGE|'R'|1|2 -> M1 P0 B0 O0 T0 R0
        SHOOTING_CHALLENGE|'R'|1|3 -> M1 P0 B0 O0 T0 R0
        SHOOTING_CHALLENGE|'R'|1|4 -> M1 P0 B0 O0 T0 R0
        HORSE|null|0|1 -> M0 P0 B0 O0 T0 R0
        HORSE|null|0|2 -> M0 P0 B0 O0 T0 R0
        HORSE|null|0|3 -> M0 P0 B0 O0 T0 R0
        HORSE|null|0|4 -> M0 P0 B0 O0 T0 R0
        HORSE|null|1|1 -> M0 P0 B1 O0 T0 R0
        HORSE|null|1|2 -> M0 P0 B1 O0 T0 R0
        HORSE|null|1|3 -> M0 P0 B1 O0 T0 R0
        HORSE|null|1|4 -> M0 P0 B1 O0 T0 R0
        HORSE|''|0|1 -> M0 P0 B0 O0 T0 R0
        HORSE|''|0|2 -> M0 P0 B0 O0 T0 R0
        HORSE|''|0|3 -> M0 P0 B0 O0 T0 R0
        HORSE|''|0|4 -> M0 P0 B0 O0 T0 R0
        HORSE|''|1|1 -> M0 P0 B1 O0 T0 R0
        HORSE|''|1|2 -> M0 P0 B1 O0 T0 R0
        HORSE|''|1|3 -> M0 P0 B1 O0 T0 R0
        HORSE|''|1|4 -> M0 P0 B1 O0 T0 R0
        HORSE|' '|0|1 -> M1 P0 B0 O0 T0 R0
        HORSE|' '|0|2 -> M1 P0 B0 O0 T0 R0
        HORSE|' '|0|3 -> M1 P0 B0 O0 T0 R0
        HORSE|' '|0|4 -> M1 P0 B0 O0 T0 R0
        HORSE|' '|1|1 -> M1 P0 B0 O0 T0 R0
        HORSE|' '|1|2 -> M1 P0 B0 O0 T0 R0
        HORSE|' '|1|3 -> M1 P0 B0 O0 T0 R0
        HORSE|' '|1|4 -> M1 P0 B0 O0 T0 R0
        HORSE|'R'|0|1 -> M1 P0 B0 O0 T0 R0
        HORSE|'R'|0|2 -> M1 P0 B0 O0 T0 R0
        HORSE|'R'|0|3 -> M1 P0 B0 O0 T0 R0
        HORSE|'R'|0|4 -> M1 P0 B0 O0 T0 R0
        HORSE|'R'|1|1 -> M1 P0 B0 O0 T0 R0
        HORSE|'R'|1|2 -> M1 P0 B0 O0 T0 R0
        HORSE|'R'|1|3 -> M1 P0 B0 O0 T0 R0
        HORSE|'R'|1|4 -> M1 P0 B0 O0 T0 R0
        ONE_ON_ONE|null|0|1 -> M0 P0 B0 O0 T0 R0
        ONE_ON_ONE|null|0|2 -> M0 P0 B0 O0 T0 R0
        ONE_ON_ONE|null|0|3 -> M0 P0 B0 O0 T0 R0
        ONE_ON_ONE|null|0|4 -> M0 P0 B0 O0 T0 R0
        ONE_ON_ONE|null|1|1 -> M0 P0 B1 O1 T0 R0
        ONE_ON_ONE|null|1|2 -> M0 P0 B1 O1 T0 R0
        ONE_ON_ONE|null|1|3 -> M0 P0 B1 O1 T0 R0
        ONE_ON_ONE|null|1|4 -> M0 P0 B1 O1 T0 R0
        ONE_ON_ONE|''|0|1 -> M0 P0 B0 O0 T0 R0
        ONE_ON_ONE|''|0|2 -> M0 P0 B0 O0 T0 R0
        ONE_ON_ONE|''|0|3 -> M0 P0 B0 O0 T0 R0
        ONE_ON_ONE|''|0|4 -> M0 P0 B0 O0 T0 R0
        ONE_ON_ONE|''|1|1 -> M0 P0 B1 O1 T0 R0
        ONE_ON_ONE|''|1|2 -> M0 P0 B1 O1 T0 R0
        ONE_ON_ONE|''|1|3 -> M0 P0 B1 O1 T0 R0
        ONE_ON_ONE|''|1|4 -> M0 P0 B1 O1 T0 R0
        ONE_ON_ONE|' '|0|1 -> M1 P0 B0 O0 T0 R0
        ONE_ON_ONE|' '|0|2 -> M1 P0 B0 O0 T0 R0
        ONE_ON_ONE|' '|0|3 -> M1 P0 B0 O0 T0 R0
        ONE_ON_ONE|' '|0|4 -> M1 P0 B0 O0 T0 R0
        ONE_ON_ONE|' '|1|1 -> M1 P0 B0 O0 T0 R0
        ONE_ON_ONE|' '|1|2 -> M1 P0 B0 O0 T0 R0
        ONE_ON_ONE|' '|1|3 -> M1 P0 B0 O0 T0 R0
        ONE_ON_ONE|' '|1|4 -> M1 P0 B0 O0 T0 R0
        ONE_ON_ONE|'R'|0|1 -> M1 P0 B0 O0 T0 R0
        ONE_ON_ONE|'R'|0|2 -> M1 P0 B0 O0 T0 R0
        ONE_ON_ONE|'R'|0|3 -> M1 P0 B0 O0 T0 R0
        ONE_ON_ONE|'R'|0|4 -> M1 P0 B0 O0 T0 R0
        ONE_ON_ONE|'R'|1|1 -> M1 P0 B0 O0 T0 R0
        ONE_ON_ONE|'R'|1|2 -> M1 P0 B0 O0 T0 R0
        ONE_ON_ONE|'R'|1|3 -> M1 P0 B0 O0 T0 R0
        ONE_ON_ONE|'R'|1|4 -> M1 P0 B0 O0 T0 R0
        TEAM_MATCH|null|0|1 -> M0 P0 B0 O0 T0 R0
        TEAM_MATCH|null|0|2 -> M0 P0 B0 O0 T0 R0
        TEAM_MATCH|null|0|3 -> M0 P0 B0 O0 T0 R0
        TEAM_MATCH|null|0|4 -> M0 P0 B0 O0 T0 R0
        TEAM_MATCH|null|1|1 -> M0 P0 B1 O0 T0 R0
        TEAM_MATCH|null|1|2 -> M0 P0 B1 O0 T1 R0
        TEAM_MATCH|null|1|3 -> M0 P0 B1 O0 T1 R0
        TEAM_MATCH|null|1|4 -> M0 P0 B1 O0 T0 R0
        TEAM_MATCH|''|0|1 -> M0 P0 B0 O0 T0 R0
        TEAM_MATCH|''|0|2 -> M0 P0 B0 O0 T0 R0
        TEAM_MATCH|''|0|3 -> M0 P0 B0 O0 T0 R0
        TEAM_MATCH|''|0|4 -> M0 P0 B0 O0 T0 R0
        TEAM_MATCH|''|1|1 -> M0 P0 B1 O0 T0 R0
        TEAM_MATCH|''|1|2 -> M0 P0 B1 O0 T1 R0
        TEAM_MATCH|''|1|3 -> M0 P0 B1 O0 T1 R0
        TEAM_MATCH|''|1|4 -> M0 P0 B1 O0 T0 R0
        TEAM_MATCH|' '|0|1 -> M1 P0 B0 O0 T0 R0
        TEAM_MATCH|' '|0|2 -> M1 P0 B0 O0 T0 R0
        TEAM_MATCH|' '|0|3 -> M1 P0 B0 O0 T0 R0
        TEAM_MATCH|' '|0|4 -> M1 P0 B0 O0 T0 R0
        TEAM_MATCH|' '|1|1 -> M1 P0 B0 O0 T0 R0
        TEAM_MATCH|' '|1|2 -> M1 P0 B0 O0 T0 R0
        TEAM_MATCH|' '|1|3 -> M1 P0 B0 O0 T0 R0
        TEAM_MATCH|' '|1|4 -> M1 P0 B0 O0 T0 R0
        TEAM_MATCH|'R'|0|1 -> M1 P0 B0 O0 T0 R0
        TEAM_MATCH|'R'|0|2 -> M1 P0 B0 O0 T0 R0
        TEAM_MATCH|'R'|0|3 -> M1 P0 B0 O0 T0 R0
        TEAM_MATCH|'R'|0|4 -> M1 P0 B0 O0 T0 R0
        TEAM_MATCH|'R'|1|1 -> M1 P0 B0 O0 T0 R0
        TEAM_MATCH|'R'|1|2 -> M1 P0 B0 O0 T0 R0
        TEAM_MATCH|'R'|1|3 -> M1 P0 B0 O0 T0 R0
        TEAM_MATCH|'R'|1|4 -> M1 P0 B0 O0 T0 R0
        """

    /// One row per TripleShotCharacterRoster.all entry, in order (with the OVR and league-strength formulas).
    static let rosterRows: [String] = [
        "bob|BOB|MALE|ADAPTIVE_TRAINER|adaptive=true|human=false|bot=true|R=60,60,60,68,55,55,52,58,64,45,58,66,60,55,62|T=null,50,45,48,45|Q=68,58,18|shoot=60,60,60|ovr=59|league=61",
        "woman_dark|Maya|FEMALE|SHARPSHOOTER|adaptive=false|human=true|bot=true|R=78,83,86,84,62,70,48,74,88,72,66,87,88,60,78|T=THREE_POINT,62,68,38,58|Q=74,63,14|shoot=78,83,86|ovr=74|league=77",
        "rooza|Rooza|FEMALE|SLASHER|adaptive=false|human=true|bot=true|R=76,82,79,95,58,60,43,88,94,78,68,97,91,52,96|T=MID_RANGE,88,84,35,78|Q=52,94,58|shoot=76,82,79|ovr=75|league=80",
        "nova|Mia Essence Skies|FEMALE|BALANCED|adaptive=false|human=true|bot=true|R=86,88,84,91,82,88,79,82,88,88,86,91,89,82,92|T=MID_RANGE,74,74,72,66|Q=91,88,6|shoot=86,88,84|ovr=85|league=87",
        "unicorn_32|Sonic|MALE|BIG|adaptive=false|human=true|bot=true|R=92,72,58,62,94,89,92,45,58,86,91,57,74,96,78|T=INSIDE,84,32,96,48|Q=84,34,8|shoot=92,72,58|ovr=73|league=79",
        "coach_67|Coach 67|MALE|BIG|adaptive=false|human=true|bot=true|R=90,75,64,55,97,85,86,52,64,80,93,50,72,98,72|T=INSIDE,79,38,88,42|Q=78,47,10|shoot=90,75,64|ovr=74|league=78",
        "zephyr|Comet|MALE|SLASHER|adaptive=false|human=true|bot=true|R=84,81,78,89,76,75,76,86,85,91,85,90,84,72,96|T=INSIDE,82,82,69,68|Q=70,86,18|shoot=84,81,78|ovr=81|league=84",
        "kyra|Gaya|FEMALE|SLASHER|adaptive=false|human=true|bot=true|R=84,81,78,89,76,75,76,86,85,91,85,90,84,72,96|T=INSIDE,82,82,69,68|Q=70,86,18|shoot=84,81,78|ovr=81|league=84",
        "kyra_original|Kyra|FEMALE|SLASHER|adaptive=false|human=true|bot=true|R=84,81,78,89,76,75,76,86,85,91,85,90,84,72,96|T=INSIDE,82,82,69,68|Q=70,86,18|shoot=84,81,78|ovr=81|league=84",
        "flare|FLARE|MALE|SLASHER|adaptive=false|human=true|bot=true|R=88,82,80,87,91,82,74,75,86,94,79,84,90,88,93|T=INSIDE,88,66,64,72|Q=64,82,25|shoot=88,82,80|ovr=82|league=84",
        "ace_23|Ace 23|MALE|SHARPSHOOTER|adaptive=false|human=true|bot=true|R=82,86,88,90,66,72,50,82,92,82,65,93,93,64,90|T=THREE_POINT,72,78,42,70|Q=36,97,86|shoot=82,86,88|ovr=78|league=80",
        "buddy_23|Buddy 23|MALE|SLASHER|adaptive=false|human=true|bot=true|R=76,79,74,96,48,38,35,92,94,60,62,99,89,38,98|T=INSIDE,91,93,25,82|Q=24,72,96|shoot=76,79,74|ovr=70|league=78",
    ]

    static let humanSelectableIds = ["woman_dark", "rooza", "nova", "unicorn_32", "coach_67", "zephyr", "kyra", "kyra_original", "flare", "ace_23", "buddy_23"]
    static let botSelectableIds = ["bob", "woman_dark", "rooza", "nova", "unicorn_32", "coach_67", "zephyr", "kyra", "kyra_original", "flare", "ace_23", "buddy_23"]

    /// (id passed to find, find(id)?.id, requireProfile(id).id)
    static let findRows: [(String?, String?, String)] = [
        (nil, nil, "woman_dark"),
        ("", nil, "woman_dark"),
        ("minik", "bob", "bob"),
        ("bob", "bob", "bob"),
        ("BOB", nil, "woman_dark"),
        ("kyra_original", "kyra_original", "kyra_original"),
        ("kyra", "kyra", "kyra"),
        ("woman_dark", "woman_dark", "woman_dark"),
        ("nope", nil, "woman_dark"),
        (" bob", nil, "woman_dark"),
        ("Minik", nil, "woman_dark"),
    ]

    /// id|titleRes|subtitleRes|landscapeDrawableName|portraitDrawableName|atmosphere|P=resolved|L=resolved
    static let courtRows: [String] = [
        "enchanted_forest|minik_swish_court_enchanted_forest|minik_swish_court_enchanted_forest_desc|triple_shot_court_enchanted_forest_landscape|triple_shot_court_background|NONE|P=triple_shot_court_background|L=triple_shot_court_background",
        "sunset_pulse|minik_swish_court_sunset_pulse|minik_swish_court_sunset_pulse_desc|triple_shot_court_sunset_pulse_landscape|triple_shot_court_sunset_pulse_portrait|COLORED_LIGHTS|P=triple_shot_court_sunset_pulse_portrait|L=triple_shot_court_sunset_pulse_landscape",
        "sunset_cove|minik_swish_court_sunset_cove|minik_swish_court_sunset_cove_desc|triple_shot_court_sunset_cove_landscape|null|COLORED_LIGHTS|P=triple_shot_court_sunset_cove_landscape|L=triple_shot_court_sunset_cove_landscape",
        "neon_tide|minik_swish_court_neon_tide|minik_swish_court_neon_tide_desc|triple_shot_court_neon_tide_landscape|null|COLORED_LIGHTS|P=triple_shot_court_neon_tide_landscape|L=triple_shot_court_neon_tide_landscape",
        "neon_falls|minik_swish_court_neon_falls|minik_swish_court_neon_falls_desc|triple_shot_court_neon_falls_landscape|null|COLORED_LIGHTS|P=triple_shot_court_neon_falls_landscape|L=triple_shot_court_neon_falls_landscape",
        "skyforge_peaks|minik_swish_court_skyforge_peaks|minik_swish_court_skyforge_peaks_desc|triple_shot_court_skyforge_peaks_landscape|triple_shot_court_skyforge_peaks_portrait|NONE|P=triple_shot_court_background|L=triple_shot_court_background",
        "frostline|minik_swish_court_frostline|minik_swish_court_frostline_desc|triple_shot_court_frostline_landscape|triple_shot_court_frostline_portrait|LIGHT_SNOW|P=triple_shot_court_background|L=triple_shot_court_background",
        "rain_break|minik_swish_court_rain_break|minik_swish_court_rain_break_desc|triple_shot_court_rain_break_landscape|triple_shot_court_rain_break_portrait|LIGHT_RAIN|P=triple_shot_court_background|L=triple_shot_court_background",
        "midnight_arena|minik_swish_court_midnight_arena|minik_swish_court_midnight_arena_desc|triple_shot_court_midnight_arena_landscape|triple_shot_court_midnight_arena_portrait|NONE|P=triple_shot_court_background|L=triple_shot_court_background",
    ]

    static let courtFindRows: [(String?, String)] = [
        (nil, "enchanted_forest"),
        ("", "enchanted_forest"),
        ("unknown", "enchanted_forest"),
        ("sunset_cove", "sunset_cove"),
        ("SUNSET_COVE", "enchanted_forest"),
        ("enchanted_forest", "enchanted_forest"),
        ("midnight_arena", "midnight_arena"),
    ]

    /// CustomClassMapper.convertToPlainJavaTypes(object) on the JVM. Integer and Long are both written as
    /// JSON integers (L:), Doubles are compared by bit pattern (D:0x...).
    static let encodeRows: [String: String] = [
        "horseDefault": "{attemptedUids=[], challengeCategory=S:\"\", challengeEstablished=B:false, challengeSpotId=S:\"\", challengeSpotX=L:0, challengeSpotY=L:0, currentPlayerUid=S:\"\", finished=B:false, penalties={}, phase=S:\"SETTING\", playerOrder=[], setterUid=S:\"\", spectatorSlots={}, turnNumber=L:0, updatedAt=L:0, winnerUid=S:\"\"}",
        "horse": "{attemptedUids=[S:\"u2\"], challengeCategory=S:\"MATH\", challengeEstablished=B:true, challengeSpotId=S:\"spot_3\", challengeSpotX=L:512, challengeSpotY=D:0x3fe6666660000000, currentPlayerUid=S:\"u2\", finished=B:false, penalties={u1=L:0, u2=L:2, u3=L:1}, phase=S:\"ATTEMPT\", playerOrder=[S:\"u1\", S:\"u2\", S:\"u3\"], setterUid=S:\"u1\", spectatorSlots={u3=L:0}, turnNumber=L:4, updatedAt=L:1760000030000, winnerUid=S:\"\"}",
        "horseWinner": "{attemptedUids=[], challengeCategory=S:\"\", challengeEstablished=B:false, challengeSpotId=S:\"\", challengeSpotX=L:0, challengeSpotY=L:0, currentPlayerUid=S:\"\", finished=B:true, penalties={}, phase=S:\"SETTING\", playerOrder=[], setterUid=S:\"\", spectatorSlots={}, turnNumber=L:0, updatedAt=L:0, winnerUid=S:\"u1\"}",
        "horseBlankWinner": "{attemptedUids=[], challengeCategory=S:\"\", challengeEstablished=B:false, challengeSpotId=S:\"\", challengeSpotX=L:0, challengeSpotY=L:0, currentPlayerUid=S:\"\", finished=B:false, penalties={}, phase=S:\"SETTING\", playerOrder=[], setterUid=S:\"\", spectatorSlots={}, turnNumber=L:0, updatedAt=L:0, winnerUid=S:\" \u{A0}\"}",
        "horseFinishedPhase": "{attemptedUids=[], challengeCategory=S:\"\", challengeEstablished=B:false, challengeSpotId=S:\"\", challengeSpotX=L:0, challengeSpotY=L:0, currentPlayerUid=S:\"\", finished=B:true, penalties={}, phase=S:\"FINISHED\", playerOrder=[], setterUid=S:\"\", spectatorSlots={}, turnNumber=L:0, updatedAt=L:0, winnerUid=S:\"\"}",
        "sample0": "{depth=L:0, tms=L:0, x=L:410, y=L:1100}",
        "sample1": "{depth=L:0, tms=L:55, x=D:0x407ae80000000000, y=D:0x408f920000000000}",
        "sampleEdges": "{depth=D:0x4415af1d80000000, tms=L:-3, x=L:9223372036854775807, y=L:-9223372036854775808}",
        "sampleTiny": "{depth=D:0x3fb99999a0000000, tms=L:9223372036854775807, x=L:0, y=D:0x36a0000000000000}",
        "shotDefault": "{aimError=L:0, arcError=L:0, hotHand=B:false, id=S:\"\", made=B:false, playerName=S:\"\", playerUid=S:\"\", powerError=L:0, pullBack=L:0, rawPeakGyro=L:0, rawReleasePitchDeg=L:0, releasedAt=L:0, samples=[], shotSpotX=L:0, shotSpotY=L:0}",
        "shot": "{aimError=D:0xbfd0000000000000, arcError=D:0xbffb333340000000, hotHand=B:true, id=S:\"-Nabc\", made=B:false, playerName=S:\"Gaya\", playerUid=S:\"u2\", powerError=D:0x3fb99999a0000000, pullBack=D:0x3fe8000000000000, rawPeakGyro=D:0x400dccccc0000000, rawReleasePitchDeg=L:15, releasedAt=L:1760000031234, samples=[{depth=L:0, tms=L:0, x=L:410, y=L:1100}, {depth=L:0, tms=L:55, x=D:0x407ae80000000000, y=D:0x408f920000000000}], shotSpotX=L:512, shotSpotY=D:0x4092720000000000}",
        "boardDefault": "{bestCorrectAnswers=L:0, bestKnowledgeStreak=L:0, bestRunCategories=[], bestRunCorrectAnswers=L:0, bestRunKnowledgeAccuracyPercent=L:0, bestRunMadeShots=L:0, bestRunShootingPercent=L:0, bestRunShots=L:0, bestScore=L:0, bestShootingStreak=L:0, name=S:\"\", uid=S:\"\", updatedAt=L:0}",
        "board": "{bestCorrectAnswers=L:14, bestKnowledgeStreak=L:9, bestRunCategories=[S:\"AI\", S:\"MATH\"], bestRunCorrectAnswers=L:12, bestRunKnowledgeAccuracyPercent=L:75, bestRunMadeShots=L:11, bestRunShootingPercent=L:68, bestRunShots=L:16, bestScore=L:57, bestShootingStreak=L:6, name=S:\"Comet\", uid=S:\"u9\", updatedAt=L:1760000040000}",
        "metaDefault": "{categories=[], createdAt=L:0, gameType=S:\"SHOOTING_CHALLENGE\", hostUid=S:\"\", maxPlayers=L:4, seed=L:0, startedAt=L:0, status=S:\"WAITING\", timeLimitSeconds=L:60}",
        "meta": "{categories=[S:\"AI\", S:\"ASTRONOMY\"], createdAt=L:1760000000000, gameType=S:\"HORSE\", hostUid=S:\"u1\", maxPlayers=L:4, seed=L:-4611686018427387904, startedAt=L:1760000010000, status=S:\"PLAYING\", timeLimitSeconds=L:60}",
        "playerDefault": "{bestKnowledgeStreak=L:0, bestShootingStreak=L:0, correctAnswers=L:0, finished=B:false, knowledgeStreak=L:0, lastEvent=S:\"\", madeShots=L:0, name=S:\"\", score=L:0, shootingStreak=L:0, shots=L:0, uid=S:\"\", updatedAt=L:0}",
        "player": "{bestKnowledgeStreak=L:3, bestShootingStreak=L:2, correctAnswers=L:5, finished=B:true, knowledgeStreak=L:2, lastEvent=S:\"\u{5E1}\u{5D9}\u{5D9}\u{5DD}\", madeShots=L:4, name=S:\"Gaya\", score=L:12, shootingStreak=L:1, shots=L:6, uid=S:\"u2\", updatedAt=L:1760000050000}",
    ]

    /// DataSnapshot.getValue(X::class.java) on the JVM: OK <fields> (Floats by bit pattern), NULL, or EXC.
    static let decodeRows: [String: String] = [
        "horseRoundTrip": "OK phase=ATTEMPT|setter=u1|current=u2|est=true|cat=MATH|spot=spot_3|x=0x44000000|y=0x3f333333|order=[u1, u2, u3]|attempted=[u2]|penalties={u1=0, u2=2, u3=1}|slots={u3=0}|winner=|turn=4|updatedAt=1760000030000|isFinished=false",
        "horseNull": "NULL",
        "horseEmpty": "OK phase=SETTING|setter=|current=|est=false|cat=|spot=|x=0x00000000|y=0x00000000|order=[]|attempted=[]|penalties={}|slots={}|winner=|turn=0|updatedAt=0|isFinished=false",
        "horseString": "EXC",
        "horseList": "EXC",
        "horseLong": "EXC",
        "turnDouble4.9": "OK phase=SETTING|setter=|current=|est=false|cat=|spot=|x=0x00000000|y=0x00000000|order=[]|attempted=[]|penalties={}|slots={}|winner=|turn=4|updatedAt=0|isFinished=false",
        "turnDouble-4.9": "OK phase=SETTING|setter=|current=|est=false|cat=|spot=|x=0x00000000|y=0x00000000|order=[]|attempted=[]|penalties={}|slots={}|winner=|turn=-4|updatedAt=0|isFinished=false",
        "turnDoubleMax": "OK phase=SETTING|setter=|current=|est=false|cat=|spot=|x=0x00000000|y=0x00000000|order=[]|attempted=[]|penalties={}|slots={}|winner=|turn=2147483647|updatedAt=0|isFinished=false",
        "turnDoubleMin": "OK phase=SETTING|setter=|current=|est=false|cat=|spot=|x=0x00000000|y=0x00000000|order=[]|attempted=[]|penalties={}|slots={}|winner=|turn=-2147483648|updatedAt=0|isFinished=false",
        "turnDoubleOver": "EXC",
        "turnDoubleOverHalf": "EXC",
        "turnDoubleUnderHalf": "EXC",
        "turnLongOver": "EXC",
        "turnLongMin": "OK phase=SETTING|setter=|current=|est=false|cat=|spot=|x=0x00000000|y=0x00000000|order=[]|attempted=[]|penalties={}|slots={}|winner=|turn=-2147483648|updatedAt=0|isFinished=false",
        "turnInt": "OK phase=SETTING|setter=|current=|est=false|cat=|spot=|x=0x00000000|y=0x00000000|order=[]|attempted=[]|penalties={}|slots={}|winner=|turn=7|updatedAt=0|isFinished=false",
        "turnBool": "EXC",
        "turnString": "EXC",
        "updatedDouble1.5": "OK phase=SETTING|setter=|current=|est=false|cat=|spot=|x=0x00000000|y=0x00000000|order=[]|attempted=[]|penalties={}|slots={}|winner=|turn=0|updatedAt=1|isFinished=false",
        "updatedDouble-1.5": "OK phase=SETTING|setter=|current=|est=false|cat=|spot=|x=0x00000000|y=0x00000000|order=[]|attempted=[]|penalties={}|slots={}|winner=|turn=0|updatedAt=-1|isFinished=false",
        "updatedDouble2p63": "OK phase=SETTING|setter=|current=|est=false|cat=|spot=|x=0x00000000|y=0x00000000|order=[]|attempted=[]|penalties={}|slots={}|winner=|turn=0|updatedAt=9223372036854775807|isFinished=false",
        "updatedDouble-2p63": "OK phase=SETTING|setter=|current=|est=false|cat=|spot=|x=0x00000000|y=0x00000000|order=[]|attempted=[]|penalties={}|slots={}|winner=|turn=0|updatedAt=-9223372036854775808|isFinished=false",
        "updatedDouble1e19": "EXC",
        "updatedInt": "OK phase=SETTING|setter=|current=|est=false|cat=|spot=|x=0x00000000|y=0x00000000|order=[]|attempted=[]|penalties={}|slots={}|winner=|turn=0|updatedAt=12|isFinished=false",
        "updatedBool": "EXC",
        "spotXLong": "OK phase=SETTING|setter=|current=|est=false|cat=|spot=|x=0x4b800000|y=0x00000000|order=[]|attempted=[]|penalties={}|slots={}|winner=|turn=0|updatedAt=0|isFinished=false",
        "spotXLong2p53p1": "EXC",
        "spotXLong2p53": "OK phase=SETTING|setter=|current=|est=false|cat=|spot=|x=0x5a000000|y=0x00000000|order=[]|attempted=[]|penalties={}|slots={}|winner=|turn=0|updatedAt=0|isFinished=false",
        "spotXDouble0.1": "OK phase=SETTING|setter=|current=|est=false|cat=|spot=|x=0x3dcccccd|y=0x00000000|order=[]|attempted=[]|penalties={}|slots={}|winner=|turn=0|updatedAt=0|isFinished=false",
        "spotXDouble1e40": "OK phase=SETTING|setter=|current=|est=false|cat=|spot=|x=0x7f800000|y=0x00000000|order=[]|attempted=[]|penalties={}|slots={}|winner=|turn=0|updatedAt=0|isFinished=false",
        "spotXDoubleTinyRound": "OK phase=SETTING|setter=|current=|est=false|cat=|spot=|x=0x3e99999a|y=0x00000000|order=[]|attempted=[]|penalties={}|slots={}|winner=|turn=0|updatedAt=0|isFinished=false",
        "spotXBool": "EXC",
        "spotXString": "EXC",
        "estLong": "EXC",
        "estString": "EXC",
        "estTrue": "OK phase=SETTING|setter=|current=|est=true|cat=|spot=|x=0x00000000|y=0x00000000|order=[]|attempted=[]|penalties={}|slots={}|winner=|turn=0|updatedAt=0|isFinished=false",
        "phaseLong": "EXC",
        "phaseBool": "EXC",
        "orderMap": "EXC",
        "orderString": "EXC",
        "orderNullHole": "OK phase=SETTING|setter=|current=|est=false|cat=|spot=|x=0x00000000|y=0x00000000|order=[u1, null, u3]|attempted=[]|penalties={}|slots={}|winner=|turn=0|updatedAt=0|isFinished=false",
        "orderNumber": "EXC",
        "penaltiesList": "EXC",
        "penaltiesDouble": "OK phase=SETTING|setter=|current=|est=false|cat=|spot=|x=0x00000000|y=0x00000000|order=[]|attempted=[]|penalties={u1=1, u2=-2}|slots={}|winner=|turn=0|updatedAt=0|isFinished=false",
        "penaltiesBool": "EXC",
        "penaltiesString": "EXC",
        "slotsOver": "EXC",
        "unknownKeys": "OK phase=ATTEMPT|setter=|current=|est=false|cat=|spot=|x=0x00000000|y=0x00000000|order=[]|attempted=[]|penalties={}|slots={}|winner=|turn=0|updatedAt=0|isFinished=false",
        "nullField": "EXC",
        "sampleTms": "OK tMs=0|x=0x43d74000|y=0x447c9000|depth=0x00000000",
        "sampleTMs": "OK tMs=55|x=0x43d74000|y=0x447c9000|depth=0x00000000",
        "sampleBoth": "OK tMs=70|x=0x00000000|y=0x00000000|depth=0x00000000",
        "sampleTMsDouble": "OK tMs=55|x=0x00000000|y=0x00000000|depth=0x00000000",
        "shotRoundTrip": "OK id=-Nabc|uid=u2|name=Gaya|sx=0x44000000|sy=0x44939000|aim=0xbe800000|power=0x3dcccccd|arc=0xbfd9999a|gyro=0x406e6666|pitch=0x41700000|pull=0x3f400000|hot=true|releasedAt=1760000031234|made=false|samples=[tMs=0|x=0x43cd0000|y=0x44898000|depth=0x00000000, tMs=0|x=0x43d74000|y=0x447c9000|depth=0x00000000]",
        "shotEmpty": "OK id=|uid=|name=|sx=0x00000000|sy=0x00000000|aim=0x00000000|power=0x00000000|arc=0x00000000|gyro=0x00000000|pitch=0x00000000|pull=0x00000000|hot=false|releasedAt=0|made=false|samples=[]",
        "shotSampleString": "EXC",
        "shotSampleNull": "EXC",
        "shotSamplesMap": "EXC",
        "shotHotLong": "EXC",
        "shotReleasedDouble": "OK id=|uid=|name=|sx=0x00000000|sy=0x00000000|aim=0x00000000|power=0x00000000|arc=0x00000000|gyro=0x00000000|pitch=0x00000000|pull=0x00000000|hot=false|releasedAt=1760000031234|made=false|samples=[]",
        "boardRoundTrip": "OK uid=u9|name=Comet|bestScore=57|bss=6|bks=9|bca=14|brca=12|brs=16|brms=11|brka=75|brsp=68|cats=[AI, MATH]|updatedAt=1760000040000",
        "boardEmpty": "OK uid=|name=|bestScore=0|bss=0|bks=0|bca=0|brca=0|brs=0|brms=0|brka=0|brsp=0|cats=[]|updatedAt=0",
        "boardScoreDouble": "OK uid=|name=N|bestScore=57|bss=0|bks=0|bca=0|brca=0|brs=0|brms=0|brka=0|brsp=0|cats=[]|updatedAt=0",
        "boardCatsNumber": "EXC",
        "boardNameNumber": "EXC",
        "metaRoundTrip": "OK host=u1|status=PLAYING|seed=-4611686018427387904|createdAt=1760000000000|startedAt=1760000010000|gameType=HORSE|cats=[AI, ASTRONOMY]|time=60|max=4",
        "metaEmpty": "OK host=|status=WAITING|seed=0|createdAt=0|startedAt=0|gameType=SHOOTING_CHALLENGE|cats=[]|time=60|max=4",
        "metaExtra": "EXC",
        "metaSeedDouble": "OK host=|status=WAITING|seed=-4611686018427387904|createdAt=0|startedAt=0|gameType=SHOOTING_CHALLENGE|cats=[]|time=60|max=4",
        "metaMaxDouble": "OK host=|status=WAITING|seed=0|createdAt=0|startedAt=0|gameType=SHOOTING_CHALLENGE|cats=[]|time=600|max=4",
        "playerRoundTrip": "OK uid=u2|name=Gaya|score=12|ks=2|ss=1|bks=3|bss=2|ca=5|ms=4|shots=6|last=\u{5E1}\u{5D9}\u{5D9}\u{5DD}|finished=true|updatedAt=1760000050000",
        "playerEmpty": "OK uid=|name=|score=0|ks=0|ss=0|bks=0|bss=0|ca=0|ms=0|shots=0|last=|finished=false|updatedAt=0",
        "playerFinishedLong": "EXC",
        "playerServerTs": "EXC",
    ]
}

/// Android's outcome per input of testFirebaseDecodingErrorsAndWarningsMatchAndroid: OK / NULL /
/// EXC <exception class>: <message>, then " ## " and the ClassMapper warnings in Android's log order
/// (" ;; "-separated). Generated by the JVM harness: firebase-database 22.0.1 CustomClassMapper on
/// NodeUtilities.NodeFromJSON(json).getValue(), the plain value DataSnapshot.getValue() decodes.
private enum TSModelsAndroidMessages {
    static let rows: [String: String] = [
        "horseString": "EXC com.google.firebase.database.DatabaseException: Can't convert object of type java.lang.String to type com.appsbybros.minik.swish.model.LiveHorseState ## ",
        "horseList": "EXC com.google.firebase.database.DatabaseException: Can't convert object of type java.util.ArrayList to type com.appsbybros.minik.swish.model.LiveHorseState ## ",
        "horseLong": "EXC com.google.firebase.database.DatabaseException: Can't convert object of type java.lang.Long to type com.appsbybros.minik.swish.model.LiveHorseState ## ",
        "horseDouble": "EXC com.google.firebase.database.DatabaseException: Can't convert object of type java.lang.Double to type com.appsbybros.minik.swish.model.LiveHorseState ## ",
        "horseBool": "EXC com.google.firebase.database.DatabaseException: Can't convert object of type java.lang.Boolean to type com.appsbybros.minik.swish.model.LiveHorseState ## ",
        "turnDoubleOver": "EXC com.google.firebase.database.DatabaseException: Numeric value out of 32-bit integer range: 2.147483648E9. Did you mean to use a long or double instead of an int? ## ",
        "turnDoubleUnderHalf": "EXC com.google.firebase.database.DatabaseException: Numeric value out of 32-bit integer range: -2.1474836485E9. Did you mean to use a long or double instead of an int? ## ",
        "turnLongOver": "EXC com.google.firebase.database.DatabaseException: Numeric value out of 32-bit integer range: 2.147483648E9. Did you mean to use a long or double instead of an int? ## ",
        "turnBool": "EXC com.google.firebase.database.DatabaseException: Failed to convert a value of type java.lang.Boolean to int ## ",
        "turnString": "EXC com.google.firebase.database.DatabaseException: Failed to convert a value of type java.lang.String to int ## ",
        "turnList": "EXC com.google.firebase.database.DatabaseException: Failed to convert a value of type java.util.ArrayList to int ## ",
        "turnMap": "EXC com.google.firebase.database.DatabaseException: Failed to convert a value of type java.util.HashMap to int ## ",
        "updatedDouble1e19": "EXC com.google.firebase.database.DatabaseException: Numeric value out of 64-bit long range: 1.0E19. Did you mean to use a double instead of a long? ## ",
        "updatedDoubleMinus1e19": "EXC com.google.firebase.database.DatabaseException: Numeric value out of 64-bit long range: -1.0E19. Did you mean to use a double instead of a long? ## ",
        "updatedBool": "EXC com.google.firebase.database.DatabaseException: Failed to convert a value of type java.lang.Boolean to long ## ",
        "updatedString": "EXC com.google.firebase.database.DatabaseException: Failed to convert a value of type java.lang.String to long ## ",
        "spotXLong2p53p1": "EXC com.google.firebase.database.DatabaseException: Loss of precision while converting number to double: 9007199254740993. Did you mean to use a 64-bit long instead? ## ",
        "spotXLongMin": "OK ## ",
        "spotXBool": "EXC com.google.firebase.database.DatabaseException: Failed to convert a value of type java.lang.Boolean to double ## ",
        "spotXString": "EXC com.google.firebase.database.DatabaseException: Failed to convert a value of type java.lang.String to double ## ",
        "estLong": "EXC com.google.firebase.database.DatabaseException: Failed to convert value of type java.lang.Long to boolean ## ",
        "estDouble": "EXC com.google.firebase.database.DatabaseException: Failed to convert value of type java.lang.Double to boolean ## ",
        "estString": "EXC com.google.firebase.database.DatabaseException: Failed to convert value of type java.lang.String to boolean ## ",
        "phaseLong": "EXC com.google.firebase.database.DatabaseException: Failed to convert value of type java.lang.Long to String ## ",
        "phaseDouble": "EXC com.google.firebase.database.DatabaseException: Failed to convert value of type java.lang.Double to String ## ",
        "phaseBool": "EXC com.google.firebase.database.DatabaseException: Failed to convert value of type java.lang.Boolean to String ## ",
        "phaseList": "EXC com.google.firebase.database.DatabaseException: Failed to convert value of type java.util.ArrayList to String ## ",
        "phaseMap": "EXC com.google.firebase.database.DatabaseException: Failed to convert value of type java.util.HashMap to String ## ",
        "orderMap": "EXC com.google.firebase.database.DatabaseException: Expected a List while deserializing, but got a class java.util.HashMap ## ",
        "orderSparse": "EXC com.google.firebase.database.DatabaseException: Expected a List while deserializing, but got a class java.util.HashMap ## ",
        "orderString": "EXC com.google.firebase.database.DatabaseException: Expected a List while deserializing, but got a class java.lang.String ## ",
        "orderNumber": "EXC com.google.firebase.database.DatabaseException: Failed to convert value of type java.lang.Long to String ## ",
        "penaltiesList": "EXC com.google.firebase.database.DatabaseException: Expected a Map while deserializing, but got a class java.util.ArrayList ## ",
        "penaltiesBool": "EXC com.google.firebase.database.DatabaseException: Failed to convert a value of type java.lang.Boolean to int ## ",
        "penaltiesString": "EXC com.google.firebase.database.DatabaseException: Expected a Map while deserializing, but got a class java.lang.String ## ",
        "slotsOver": "EXC com.google.firebase.database.DatabaseException: Numeric value out of 32-bit integer range: 3.0E9. Did you mean to use a long or double instead of an int? ## ",
        "unknownKeys": "OK ## ClassMapper: No setter/field for Phase found on class com.appsbybros.minik.swish.model.LiveHorseState (fields/setters are case sensitive!) ;; ClassMapper: No setter/field for PLAYERORDER found on class com.appsbybros.minik.swish.model.LiveHorseState (fields/setters are case sensitive!) ;; ClassMapper: No setter/field for extra found on class com.appsbybros.minik.swish.model.LiveHorseState ;; ClassMapper: No setter/field for finished found on class com.appsbybros.minik.swish.model.LiveHorseState (fields/setters are case sensitive!) ;; ClassMapper: No setter/field for zzz found on class com.appsbybros.minik.swish.model.LiveHorseState",
        "twoBadKeys": "EXC com.google.firebase.database.DatabaseException: Failed to convert value of type java.lang.Long to String ## ",
        "threeBadKeys": "EXC com.google.firebase.database.DatabaseException: Numeric value out of 32-bit integer range: 1.0E10. Did you mean to use a long or double instead of an int? ## ",
        "badPenaltyOrder": "EXC com.google.firebase.database.DatabaseException: Failed to convert a value of type java.lang.Boolean to int ## ",
        "sampleTms": "OK ## ClassMapper: No setter/field for tms found on class com.appsbybros.minik.swish.model.ShotReplaySample (fields/setters are case sensitive!)",
        "sampleString": "EXC com.google.firebase.database.DatabaseException: Can't convert object of type java.lang.String to type com.appsbybros.minik.swish.model.ShotReplaySample ## ",
        "sampleBadX": "EXC com.google.firebase.database.DatabaseException: Failed to convert a value of type java.lang.String to double ## ",
        "shotSampleString": "EXC com.google.firebase.database.DatabaseException: Can't convert object of type java.lang.String to type com.appsbybros.minik.swish.model.ShotReplaySample ## ",
        "shotSamplesMap": "EXC com.google.firebase.database.DatabaseException: Expected a List while deserializing, but got a class java.util.HashMap ## ",
        "shotHotLong": "EXC com.google.firebase.database.DatabaseException: Failed to convert value of type java.lang.Long to boolean ## ",
        "shotSampleBadTms": "EXC com.google.firebase.database.DatabaseException: Failed to convert a value of type java.lang.String to long ## ",
        "shotWarnings": "OK ## ClassMapper: No setter/field for finished found on class com.appsbybros.minik.swish.model.LiveShotEvent ;; ClassMapper: No setter/field for tMs found on class com.appsbybros.minik.swish.model.LiveShotEvent ;; ClassMapper: No setter/field for tms found on class com.appsbybros.minik.swish.model.ShotReplaySample (fields/setters are case sensitive!) ;; ClassMapper: No setter/field for tms found on class com.appsbybros.minik.swish.model.ShotReplaySample (fields/setters are case sensitive!)",
        "boardCatsNumber": "EXC com.google.firebase.database.DatabaseException: Failed to convert value of type java.lang.Long to String ## ",
        "boardNameNumber": "EXC com.google.firebase.database.DatabaseException: Failed to convert value of type java.lang.Long to String ## ",
        "boardScoreString": "EXC com.google.firebase.database.DatabaseException: Failed to convert a value of type java.lang.String to int ## ",
        "boardCatsMap": "EXC com.google.firebase.database.DatabaseException: Expected a List while deserializing, but got a class java.util.HashMap ## ",
        "metaSeedOver": "EXC com.google.firebase.database.DatabaseException: Numeric value out of 64-bit long range: 1.8446744073709552E19. Did you mean to use a double instead of a long? ## ",
        "metaExtra": "EXC com.google.firebase.database.DatabaseException: Numeric value out of 64-bit long range: 1.8446744073709552E19. Did you mean to use a double instead of a long? ## ",
        "metaCatsString": "EXC com.google.firebase.database.DatabaseException: Expected a List while deserializing, but got a class java.lang.String ## ",
        "playerFinishedLong": "EXC com.google.firebase.database.DatabaseException: Failed to convert value of type java.lang.Long to boolean ## ",
        "playerScoreDouble": "EXC com.google.firebase.database.DatabaseException: Numeric value out of 32-bit integer range: 1.0E12. Did you mean to use a long or double instead of an int? ## ",
        "playerUnknown": "OK ## ClassMapper: No setter/field for Uid found on class com.appsbybros.minik.swish.model.LivePlayerState (fields/setters are case sensitive!) ;; ClassMapper: No setter/field for isFinished found on class com.appsbybros.minik.swish.model.LivePlayerState",
    ]
}

// MARK: - ShootingLeaderboardEligibilityTest.kt (Android 6c38131)

final class ShootingLeaderboardEligibilityTest: XCTestCase {
    private let challenge = TripleShotGameConfig(playerName: "Test", gameType: .SHOOTING_CHALLENGE, limitMode: .TIME_ONLY,
                                                 botMatch: true, timeLimitSeconds: 60)

    func testCurrentMenuChallengeAndLegacySoloBothSubmitPersonalBests() {
        XCTAssertTrue(challenge.isRanked)
        XCTAssertTrue(challenge.copy(botMatch: false).isRanked)
    }

    func testOnlyComparableLocalSixtySecondChallengesQualify() {
        XCTAssertFalse(challenge.copy(roomId: "ROOM").isRanked)
        XCTAssertFalse(challenge.copy(timeLimitSeconds: 120).isRanked)
        XCTAssertFalse(challenge.copy(limitMode: .BALLS_ONLY).isRanked)
        for mode in [GameType.PRACTICE, .HORSE, .ONE_ON_ONE, .TEAM_MATCH] {
            XCTAssertFalse(challenge.copy(gameType: mode).isRanked)
        }
    }
}
