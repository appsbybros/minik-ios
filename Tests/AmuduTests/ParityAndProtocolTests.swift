import XCTest
@testable import MinikAmudu

/// iOS-only: the Kotlin/Java behaviors the Android engine and room protocol depend on.
/// Random reference values were printed by kotlin-stdlib 2.1.0 (`Random(42)`, `Random(-7)`, `Random(123456789012L)`).
final class KotlinParityTests: XCTestCase {
    private func check(_ seed: Int64, ints: [Int32], until10: [Int], until8: [Int], doubles: [Double], ranged: [Double]) {
        var r = KotlinRandom(seed: seed)
        var gotInts: [Int32] = []
        for _ in 0..<5 { gotInts.append(r.nextInt()) }
        XCTAssertEqual(ints, gotInts, "Random(\(seed)) nextInt")
        var gotTen: [Int] = []
        for _ in 0..<5 { gotTen.append(r.nextIndex(10)) }
        XCTAssertEqual(until10, gotTen, "Random(\(seed)) nextInt(10)")
        var gotEight: [Int] = []
        for _ in 0..<5 { gotEight.append(Int(r.nextInt(until: 8))) }
        XCTAssertEqual(until8, gotEight, "Random(\(seed)) nextInt(8)")
        var gotDoubles: [Double] = []
        for _ in 0..<3 { gotDoubles.append(r.nextDouble()) }
        XCTAssertEqual(doubles, gotDoubles, "Random(\(seed)) nextDouble")
        var gotRanged: [Double] = []
        for _ in 0..<3 { gotRanged.append(r.nextDouble(-1.5, 1.5)) }
        XCTAssertEqual(ranged, gotRanged, "Random(\(seed)) nextDouble(-1.5, 1.5)")
    }

    func testRandomFortyTwoMatchesKotlin() {
        check(42, ints: [972016666, 1740578880, -408207414, -112774692, 1162768683], until10: [2, 1, 0, 9, 7], until8: [4, 5, 2, 5, 1],
              doubles: [0.9427830814283763, 0.1134207410437057, 0.1915288662224609],
              ranged: [-0.057267540506247494, -0.6444650724930343, -0.04778420995603483])
    }

    func testNegativeSeedMatchesKotlin() {
        check(-7, ints: [493578350, -2123338769, -1218139981, -1791905413, -702750341], until10: [2, 0, 2, 2, 7], until8: [2, 3, 7, 4, 0],
              doubles: [0.6678116717184747, 0.9217776909132867, 0.6916452333769824],
              ranged: [1.4507590145353761, -0.24455280739717744, 0.5362980387251337])
    }

    func testLongSeedMatchesKotlin() {
        check(123456789012, ints: [1514313960, -2057386076, 1929340550, -963029355, 153644130], until10: [8, 3, 3, 2, 7], until8: [2, 3, 0, 4, 6],
              doubles: [0.8832516096727285, 0.7222040253725456, 0.389425753396616],
              ranged: [-0.9110162641397579, 1.422462088979008, 0.6067620351109202])
    }

    func testJavaHashCodeAndFloorMod() {
        XCTAssertEqual(99162322, Kotlin.hashCode("hello"))
        XCTAssertEqual(Kotlin.hashCode("Aa"), Kotlin.hashCode("BB"))
        XCTAssertEqual(0, Kotlin.hashCode(""))
        XCTAssertEqual(-1211425520, Kotlin.hashCode("house0"))
        XCTAssertEqual(1962710307, Kotlin.hashCode("houseAuto2"))
        XCTAssertEqual(1205962629, Kotlin.hashCode("הצפרדע"))
        XCTAssertEqual(5, Kotlin.floorMod(-1, 6))
        XCTAssertEqual(Int64(1), Kotlin.floorMod(Int64(-7), Int64(2)))
        // House-player suggestions in a room use Words.suggestion(bid.hashCode(), ...).
        XCTAssertEqual("pickle", Words.suggestion(Int(Kotlin.hashCode("house0")), hebrew: false))
        XCTAssertEqual("waffle", Words.suggestion(-1, hebrew: false))
    }

    func testKotlinStringOrderAndConversions() {
        XCTAssertTrue(Kotlin.less("Z", "a"))
        XCTAssertTrue(Kotlin.less("house10", "house2"))
        XCTAssertEqual(0, Kotlin.toInt(Double.nan))
        XCTAssertEqual(Int(Int32.max), Kotlin.toInt(1e20))
        XCTAssertEqual(-3, Kotlin.toInt(-3.9))
        XCTAssertTrue(Kotlin.isBlank(" \t\n"))
        XCTAssertEqual("a b", Kotlin.trim("  a b \n"))
        XCTAssertEqual("b", AmuduEngine.rankedWinner(keys: ["a", "b"], votes: ["b"]))
        XCTAssertEqual("a", AmuduEngine.rankedWinner(keys: ["b", "a"], votes: []))
    }

    func testNameNormalizationMatchesAndroid() {
        XCTAssertEqual("frog sparkly", Words.normalize("  Frog \t  SPARKLY "))
        XCTAssertTrue(Words.validName(" Alex "))
        XCTAssertFalse(Words.validName("12345"))
        XCTAssertFalse(Words.validName(String(repeating: "a", count: 23)))
        XCTAssertTrue(Words.validName("נועה"))
        XCTAssertFalse(Words.validSuggestion(String(repeating: "a", count: 25)))
    }
}

/// iOS-only: the Realtime Database wire format must stay identical to Android's `Codec` and the rules.
final class ProtocolTests: XCTestCase {
    private func world() throws -> AmuduEngine {
        let members = [Member("host", "miniko", "Alex"), Member("alice", "kyra", "Alice"), Member("house0", "gaya", "Gaya", bot: true)]
        return try AmuduEngine(members: members, config: GameConfig(participants: 3), seed: 7, id: "TEST23")
    }

    func testMemberAndConfigFieldsMatchTheRules() throws {
        let member = AmuduCodec.member(Member("alice", "kyra", "Alice", bot: false, hebrew: true))
        XCTAssertEqual(Set(["id", "character", "name", "bot", "hebrew", "ready", "connected"]), Set(member.keys))
        XCTAssertEqual(false, member["ready"] as? Bool)
        XCTAssertEqual(true, member["connected"] as? Bool)
        let config = AmuduCodec.config(try GameConfig(scene: .andromeda, ball: .tennis, freezeRule: .honor, participants: 10, turns: 50,
                                                      daylight: .night, throwMode: .easy, wind: .fast))
        XCTAssertEqual(Set(["challengeStep", "width", "depth", "stepLengthFraction", "scene", "ball", "freeze", "participants", "turns",
                            "huddleSeconds", "daylight", "throwMode", "wind", "rules", "requireCall", "stepsAfterCall", "actionSeconds"]),
                       Set(config.keys))
        XCTAssertEqual("ANDROMEDA", config["scene"] as? String)
        XCTAssertEqual("TENNIS", config["ball"] as? String)
        XCTAssertEqual("HONOR", config["freeze"] as? String)
        XCTAssertEqual("NIGHT", config["daylight"] as? String)
        XCTAssertEqual("EASY", config["throwMode"] as? String)
        XCTAssertEqual("FAST", config["wind"] as? String)
        XCTAssertEqual(10, config["participants"] as? Int)
    }

    func testEnumWireNamesMatchAndroid() {
        XCTAssertEqual(["PARK", "BEACH", "ANDROMEDA"], ArenaScene.allCases.map { $0.rawValue })
        XCTAssertEqual(["FOAM", "BEACH", "NEON", "TENNIS"], BallKind.allCases.map { $0.rawValue })
        XCTAssertEqual(["MORNING", "NOON", "EVENING", "NIGHT"], Daylight.allCases.map { $0.rawValue })
        XCTAssertEqual(["NONE", "SLOW", "FAST"], Wind.allCases.map { $0.rawValue })
        XCTAssertEqual(["EASY", "STANDARD"], ThrowMode.allCases.map { $0.rawValue })
        XCTAssertEqual(["FREEZE", "HONOR"], FreezeRule.allCases.map { $0.rawValue })
        XCTAssertEqual(["CIRCLE", "AIR", "RETRIEVE", "SHOUT", "AIM", "FLIGHT", "RESOLVE", "HUDDLE", "FINISHED"], Phase.allCases.map { $0.rawValue })
    }

    func testCommandTypesMatchTheRules() {
        let types = [GameCommand.move(V(1, 0)), .aim(V(0, 1)), .select(target: "x"), .toss(power: 0.2, drift: 0), .catchBall, .duck, .shout,
                     .throwBall(power: 0.5), .end, .say(index: 1)].map { AmuduCodec.command($0)["type"] as? String ?? "" }
        XCTAssertEqual(["move", "aim", "select", "toss", "catch", "duck", "shout", "throw", "end", "say"], types)
        let select = AmuduCodec.command(.select(target: "p1", typedName: "frog"))
        XCTAssertEqual("p1", select["target"] as? String)
        XCTAssertEqual("frog", select["name"] as? String)
        let vector = AmuduCodec.command(.aim(V(3, -4)))["vector"] as? [Double] ?? []
        XCTAssertEqual(2, vector.count)
        XCTAssertEqual(0.6, vector.first ?? 0, accuracy: 1e-9)
        XCTAssertEqual(-0.8, vector.last ?? 0, accuracy: 1e-9)
    }

    func testPublicSnapshotHasRequiredChildrenAndIsValidJson() throws {
        let e = try world()
        let shared = AmuduCodec.shared(e)
        for key in ["time", "phase", "actors", "ball", "huddleTarget", "infoActor", "infoCode", "events", "config", "seed", "id"] {
            XCTAssertNotNil(shared[key], key)
        }
        XCTAssertTrue(shared["pickupAnchor"] is NSNull)
        XCTAssertTrue(shared["result"] is NSNull)
        XCTAssertTrue(JSONSerialization.isValidJSONObject(shared))
        XCTAssertTrue(JSONSerialization.isValidJSONObject(AmuduCodec.checkpoint(e)))
        let actors = AmuduCodec.node(shared["actors"])
        XCTAssertEqual(Set(["host", "alice", "house0"]), Set(actors.keys))
        let ball = AmuduCodec.node(shared["ball"])
        XCTAssertEqual("host", ball["holder"] as? String)
    }

    /// The local saved game goes through JSON text (as Android's SharedPreferences JSONObject does) and keeps roster order.
    func testSavedGameJsonRoundTripKeepsStateAndOrder() throws {
        let members = [Member("p0", "miniko", "Robin"), Member("house0", "kyra", "Kyra", bot: true), Member("house1", "gaya", "Gaya", bot: true)]
        let e = try AmuduEngine(members: members, config: GameConfig(ball: .beach, participants: 3, turns: 10, wind: .slow), seed: 99)
        e.command("p0", "s", .select(target: "house1"))
        e.command("p0", "t", .toss(power: 0.6, drift: 0.2))
        for _ in 0..<50 { e.tick(1.0 / 120) }
        e.actor("house0")!.suffixes = ["frog"]
        e.actor("house0")!.penalties = 3
        let wrapper: [String: Any] = ["checkpoint": AmuduCodec.checkpoint(e), "order": e.actors.map { $0.member.id }]
        let data = try JSONSerialization.data(withJSONObject: wrapper)
        let object = try JSONSerialization.jsonObject(with: data)
        let decoded = try XCTUnwrap(object as? [String: Any])
        let restored = try AmuduCodec.create(AmuduCodec.node(decoded["checkpoint"]), order: decoded["order"] as? [String])
        XCTAssertEqual(e.members, restored.members)
        XCTAssertEqual(e.config, restored.config)
        XCTAssertEqual(e.phase, restored.phase)
        XCTAssertEqual(e.time, restored.time, accuracy: 1e-9)
        XCTAssertEqual(e.ball.position.x, restored.ball.position.x, accuracy: 1e-9)
        XCTAssertEqual(e.ball.flightId, restored.ball.flightId)
        XCTAssertEqual(["frog"], restored.actor("house0")!.suffixes)
        XCTAssertEqual(3, restored.actor("house0")!.penalties)
        XCTAssertEqual(e.actor("p0")!.actuallyMoving, restored.actor("p0")!.actuallyMoving)
        XCTAssertEqual(e.events.count, restored.events.count)
        XCTAssertFalse(restored.command("p0", "t", .toss(power: 0.6, drift: 0.2)))
    }

    func testBooleansAndNumbersAreNotConfused() {
        let n: Node = ["one": NSNumber(value: 1), "flag": NSNumber(value: true), "real": true, "count": 1]
        XCTAssertEqual(1.0, n.num("one"))
        XCTAssertEqual(1.0, n.num("count"))
        XCTAssertEqual(5.0, n.num("flag", 5.0))
        XCTAssertTrue(n.flag("flag"))
        XCTAssertTrue(n.flag("real"))
        XCTAssertFalse(n.flag("one"))
    }
}
