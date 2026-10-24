import XCTest
@testable import MinikTripleShot

/// AndroidKit Firebase codec (AFirebaseCodec.swift, the value layer of AFirebase.swift).
///
/// Golden vectors come from the REAL firebase-database 22.0.1 classes (CustomClassMapper, NodeUtilities,
/// ChildrenNode, ChildKey, Utilities.tryParseInt, PushIdGenerator, Validation, DatabaseError) run on the JVM over
/// the REAL Kotlin model classes of the Android snapshot (harness: scratchpad/swish/work/kit-firebase/jvm/src/*.kt
/// and jvm2/src/ExtraGolden.kt).
///
/// Notation (as printed by the harness): S(string) L(Long) I(Integer) D(double bit pattern, hex)
/// F(float bit pattern, hex) B(boolean), {"key":value,...} with keys sorted, [list], null, EXC(DatabaseException
/// message). Integer and Long are the same JSON number on the wire, so serialized values print every integer as L.
final class FirebaseCodecTests: XCTestCase {

    // MARK: - Printing (mirrors the JVM harness)

    /// A plain value (AFirebaseCodec.serialize / plainValue / ADataSnapshot.value).
    private func wire(_ value: Any?) -> String {
        guard let value = value, !(value is NSNull) else { return "null" }
        if let text = value as? String, type(of: value) == String.self { return "S(" + text + ")" }
        if let flag = value as? Bool, type(of: value) == Bool.self { return "B(" + String(flag) + ")" }
        if let long = value as? Int64, type(of: value) == Int64.self { return "L(" + String(long) + ")" }
        if let double = value as? Double, type(of: value) == Double.self { return "D(" + String(double.bitPattern, radix: 16) + ")" }
        if let int = value as? Int, type(of: value) == Int.self { return "I(" + String(int) + ")" }
        if let float = value as? Float, type(of: value) == Float.self { return "F(" + String(float.bitPattern, radix: 16) + ")" }
        if let map = value as? [String: Any] {
            return "{" + map.keys.sorted().map { "\"" + $0 + "\":" + wire(map[$0]) }.joined(separator: ",") + "}"
        }
        if let list = value as? [Any] {
            return "[" + list.map { wire($0) }.joined(separator: ",") + "]"
        }
        return "?" + String(describing: type(of: value))
    }

    private func s(_ v: String) -> String { return "S(" + v + ")" }
    private func i(_ v: Int) -> String { return "I(" + String(v) + ")" }
    private func l(_ v: Int64) -> String { return "L(" + String(v) + ")" }
    private func f(_ v: Float) -> String { return "F(" + String(v.bitPattern, radix: 16) + ")" }
    private func b(_ v: Bool) -> String { return "B(" + String(v) + ")" }
    private func strings(_ v: [String]) -> String { return "[" + v.map { s($0) }.joined(separator: ",") + "]" }
    private func ints(_ v: [String: Int]) -> String {
        return "{" + v.keys.sorted().map { "\"" + $0 + "\":" + i(v[$0]!) }.joined(separator: ",") + "}"
    }

    private func describe(_ o: ShotReplaySample?) -> String {
        guard let o = o else { return "null" }
        return "Sample(tMs=" + l(o.tMs) + ",x=" + f(o.x) + ",y=" + f(o.y) + ",depth=" + f(o.depth) + ")"
    }

    private func describe(_ o: LiveHorseState?) -> String {
        guard let o = o else { return "null" }
        return "Horse(phase=" + s(o.phase) + ",setterUid=" + s(o.setterUid) + ",currentPlayerUid=" + s(o.currentPlayerUid)
            + ",challengeEstablished=" + b(o.challengeEstablished) + ",challengeCategory=" + s(o.challengeCategory)
            + ",challengeSpotId=" + s(o.challengeSpotId) + ",challengeSpotX=" + f(o.challengeSpotX)
            + ",challengeSpotY=" + f(o.challengeSpotY) + ",playerOrder=" + strings(o.playerOrder)
            + ",attemptedUids=" + strings(o.attemptedUids) + ",penalties=" + ints(o.penalties)
            + ",spectatorSlots=" + ints(o.spectatorSlots) + ",winnerUid=" + s(o.winnerUid) + ",turnNumber=" + i(o.turnNumber)
            + ",updatedAt=" + l(o.updatedAt) + ",isFinished=" + b(o.isFinished) + ")"
    }

    private func describe(_ o: RoomMeta?) -> String {
        guard let o = o else { return "null" }
        return "Meta(hostUid=" + s(o.hostUid) + ",status=" + s(o.status) + ",seed=" + l(o.seed) + ",createdAt=" + l(o.createdAt)
            + ",startedAt=" + l(o.startedAt) + ",gameType=" + s(o.gameType) + ",categories=" + strings(o.categories)
            + ",timeLimitSeconds=" + i(o.timeLimitSeconds) + ",maxPlayers=" + i(o.maxPlayers) + ")"
    }

    private func describe(_ o: LivePlayerState?) -> String {
        guard let o = o else { return "null" }
        return "Player(uid=" + s(o.uid) + ",name=" + s(o.name) + ",score=" + i(o.score) + ",knowledgeStreak=" + i(o.knowledgeStreak)
            + ",shootingStreak=" + i(o.shootingStreak) + ",bestKnowledgeStreak=" + i(o.bestKnowledgeStreak)
            + ",bestShootingStreak=" + i(o.bestShootingStreak) + ",correctAnswers=" + i(o.correctAnswers)
            + ",madeShots=" + i(o.madeShots) + ",shots=" + i(o.shots) + ",lastEvent=" + s(o.lastEvent)
            + ",finished=" + b(o.finished) + ",updatedAt=" + l(o.updatedAt) + ")"
    }

    private func describe(_ o: LeaderboardEntry?) -> String {
        guard let o = o else { return "null" }
        return "Entry(uid=" + s(o.uid) + ",name=" + s(o.name) + ",bestScore=" + i(o.bestScore)
            + ",bestShootingStreak=" + i(o.bestShootingStreak) + ",bestKnowledgeStreak=" + i(o.bestKnowledgeStreak)
            + ",bestCorrectAnswers=" + i(o.bestCorrectAnswers) + ",bestRunCorrectAnswers=" + i(o.bestRunCorrectAnswers)
            + ",bestRunShots=" + i(o.bestRunShots) + ",bestRunMadeShots=" + i(o.bestRunMadeShots)
            + ",bestRunKnowledgeAccuracyPercent=" + i(o.bestRunKnowledgeAccuracyPercent)
            + ",bestRunShootingPercent=" + i(o.bestRunShootingPercent) + ",bestRunCategories=" + strings(o.bestRunCategories)
            + ",updatedAt=" + l(o.updatedAt) + ")"
    }

    private func describe(_ o: LiveShotEvent?) -> String {
        guard let o = o else { return "null" }
        return "Shot(id=" + s(o.id) + ",playerUid=" + s(o.playerUid) + ",playerName=" + s(o.playerName)
            + ",shotSpotX=" + f(o.shotSpotX) + ",shotSpotY=" + f(o.shotSpotY) + ",aimError=" + f(o.aimError)
            + ",powerError=" + f(o.powerError) + ",arcError=" + f(o.arcError) + ",rawPeakGyro=" + f(o.rawPeakGyro)
            + ",rawReleasePitchDeg=" + f(o.rawReleasePitchDeg) + ",pullBack=" + f(o.pullBack) + ",hotHand=" + b(o.hotHand)
            + ",releasedAt=" + l(o.releasedAt) + ",made=" + b(o.made)
            + ",samples=[" + o.samples.map { describe($0) }.joined(separator: ",") + "])"
    }

    private func message(_ error: Error) -> String {
        return (error as? AFirebaseException)?.message ?? String(describing: error)
    }

    // MARK: - A: CustomClassMapper.serialize

    func testSerializeFloatsLikeCustomClassMapper() {
        // Float.doubleValue(); integral values within +-2^63 become a Long (`longValue()`, saturating).
        let vectors: [(UInt32, String)] = [
            (0x3f333333, "D(3fe6666660000000)"),   // 0.7f -> 0.699999988079071
            (0x3dcccccd, "D(3fb99999a0000000)"),   // 0.1f
            (0x44000000, "L(512)"),
            (0x80000000, "L(0)"),                  // -0f
            (0x00000000, "L(0)"),
            (0x5f0ac723, "D(43e158e460000000)"),   // 1e19f
            (0x5f000000, "L(9223372036854775807)"), // 2^63
            (0xdf000000, "L(-9223372036854775808)"),
            (0x00000001, "D(36a0000000000000)"),   // Float.MIN_VALUE
            (0x7f7fffff, "D(47efffffe0000000)"),   // Float.MAX_VALUE
            (0x4b800000, "L(16777216)"),
            (0x40200000, "D(4004000000000000)"),   // 2.5f
            (0xc0200000, "D(c004000000000000)"),
            (0x44c94000, "L(1610)"),
            (0xc3962000, "D(c072c40000000000)"),   // -300.25f
            (0x7fc00000, "D(7ff8000000000000)"),   // NaN
            (0x7f800000, "D(7ff0000000000000)"),   // +Infinity
            (0xff800000, "D(fff0000000000000)")    // -Infinity
        ]
        for (bits, expected) in vectors {
            XCTAssertEqual(wire(AFirebaseCodec.serialize(Float(bitPattern: bits))), expected, "float bits \(String(bits, radix: 16))")
        }
    }

    func testSerializeDoublesLikeCustomClassMapper() {
        let vectors: [(UInt64, String)] = [
            (0x3fb999999999999a, "D(3fb999999999999a)"),
            (0x7e37e43c8800759c, "D(7e37e43c8800759c)"),
            (0x8000000000000000, "L(0)"),
            (0x43e0000000000000, "L(9223372036854775807)"),
            (0xc3e0000000000000, "L(-9223372036854775808)"),
            (0x4012000000000000, "D(4012000000000000)"),
            (0x4010000000000000, "L(4)"),
            (0x42799c82cc000e66, "D(42799c82cc000e66)")
        ]
        for (bits, expected) in vectors {
            XCTAssertEqual(wire(AFirebaseCodec.serialize(Double(bitPattern: bits))), expected, "double bits \(String(bits, radix: 16))")
        }
    }

    func testSerializeIntegersBooleansStringsMapsAndLists() {
        XCTAssertEqual(wire(AFirebaseCodec.serialize(5)), "L(5)")
        XCTAssertEqual(wire(AFirebaseCodec.serialize(Int64(5))), "L(5)")
        XCTAssertEqual(wire(AFirebaseCodec.serialize(true)), "B(true)")
        XCTAssertEqual(wire(AFirebaseCodec.serialize("ענה נכון וקלע 🔥")), "S(ענה נכון וקלע 🔥)")
        XCTAssertNil(AFirebaseCodec.serialize(nil))
        XCTAssertNil(AFirebaseCodec.serialize(NSNull()))
        // A12.map: Kotlin hashMapOf("a" to 1, "b" to 2L, "c" to 0.5f, "d" to listOf(1f, 2.5f), "e" to ShotReplaySample(1, 2f, 3f, 4f))
        let map: [String: Any] = [
            "a": 1, "b": Int64(2), "c": Float(0.5), "d": [Float(1), Float(2.5)],
            "e": ShotReplaySample(tMs: 1, x: 2, y: 3, depth: 4)
        ]
        XCTAssertEqual(wire(AFirebaseCodec.serialize(map)),
                       "{\"a\":L(1),\"b\":L(2),\"c\":D(3fe0000000000000),\"d\":[L(1),D(4004000000000000)],\"e\":{\"depth\":L(4),\"tms\":L(1),\"x\":L(2),\"y\":L(3)}}")
        // A nil inside an update map stays as a delete marker.
        let optional: Int? = nil
        XCTAssertEqual(wire(AFirebaseCodec.serialize(["gone": optional as Any, "kept": "x"])), "{\"gone\":null,\"kept\":S(x)}")
        // An insertion-ordered Kotlin map is a plain object.
        var linked = KLinkedMap<String, Any>()
        linked["z"] = 1
        linked["a"] = Float(0.25)
        XCTAssertEqual(wire(AFirebaseCodec.serialize(linked)), "{\"a\":D(3fd0000000000000),\"z\":L(1)}")
    }

    /// The wire maps of the Kotlin wire classes (the model layer's codecs through AFirebaseCodec.serialize), equal to
    /// CustomClassMapper.convertToPlainJavaTypes(object) on Android: every getter's key, "tms" for tMs, "finished"
    /// for LiveHorseState.isFinished, empty lists and maps included (Firebase drops them as empty nodes).
    func testSerializeWireClassesExactlyAsAndroid() {
        XCTAssertEqual(wire(AFirebaseCodec.serialize(ShotReplaySample(tMs: 55, x: 410.5, y: 1100.25, depth: 0))),
                       "{\"depth\":L(0),\"tms\":L(55),\"x\":D(4079a80000000000),\"y\":D(4091310000000000)}")
        XCTAssertEqual(wire(AFirebaseCodec.serialize(ShotReplaySample(tMs: 0, x: 0.7, y: -12.3, depth: 0.1))),
                       "{\"depth\":D(3fb99999a0000000),\"tms\":L(0),\"x\":D(3fe6666660000000),\"y\":D(c0289999a0000000)}")
        XCTAssertEqual(wire(AFirebaseCodec.serialize(LiveHorseState())),
                       "{\"attemptedUids\":[],\"challengeCategory\":S(),\"challengeEstablished\":B(false),\"challengeSpotId\":S(),\"challengeSpotX\":L(0),\"challengeSpotY\":L(0),\"currentPlayerUid\":S(),\"finished\":B(false),\"penalties\":{},\"phase\":S(SETTING),\"playerOrder\":[],\"setterUid\":S(),\"spectatorSlots\":{},\"turnNumber\":L(0),\"updatedAt\":L(0),\"winnerUid\":S()}")
        let horse = LiveHorseState(phase: "ATTEMPT", setterUid: "uidA", currentPlayerUid: "uidB", challengeEstablished: true,
                                   challengeCategory: "MATH", challengeSpotId: "FREE_3", challengeSpotX: 402.75, challengeSpotY: 1210.5,
                                   playerOrder: ["uidA", "uidB", "uidC"], attemptedUids: ["uidB"],
                                   penalties: ["uidA": 0, "uidB": 1, "uidC": 0], spectatorSlots: ["uidC": 0],
                                   winnerUid: "", turnNumber: 4, updatedAt: 1760000030000)
        XCTAssertEqual(wire(AFirebaseCodec.serialize(horse)), Self.horseFullWire)
        XCTAssertEqual(wire(AFirebaseCodec.serialize(LiveHorseState(phase: "SETTING", challengeSpotX: 0.1, challengeSpotY: 1536, winnerUid: "uidB"))),
                       "{\"attemptedUids\":[],\"challengeCategory\":S(),\"challengeEstablished\":B(false),\"challengeSpotId\":S(),\"challengeSpotX\":D(3fb99999a0000000),\"challengeSpotY\":L(1536),\"currentPlayerUid\":S(),\"finished\":B(true),\"penalties\":{},\"phase\":S(SETTING),\"playerOrder\":[],\"setterUid\":S(),\"spectatorSlots\":{},\"turnNumber\":L(0),\"updatedAt\":L(0),\"winnerUid\":S(uidB)}")
        let shot = LiveShotEvent(id: "-OAbC", playerUid: "uidA", playerName: "Comet", shotSpotX: 402.75, shotSpotY: 1210.5,
                                 aimError: 0.12, powerError: -0.05, arcError: 0.02, rawPeakGyro: 9.4, rawReleasePitchDeg: 48,
                                 pullBack: 0.7, hotHand: false, releasedAt: 1760000009000, made: true,
                                 samples: [ShotReplaySample(tMs: 0, x: 410, y: 1100, depth: 0),
                                           ShotReplaySample(tMs: 55, x: 430.5, y: 1010.25, depth: 0)])
        XCTAssertEqual(wire(AFirebaseCodec.serialize(shot)),
                       "{\"aimError\":D(3fbeb851e0000000),\"arcError\":D(3f947ae140000000),\"hotHand\":B(false),\"id\":S(-OAbC),\"made\":B(true),\"playerName\":S(Comet),\"playerUid\":S(uidA),\"powerError\":D(bfa99999a0000000),\"pullBack\":D(3fe6666660000000),\"rawPeakGyro\":D(4022ccccc0000000),\"rawReleasePitchDeg\":L(48),\"releasedAt\":L(1760000009000),\"samples\":[{\"depth\":L(0),\"tms\":L(0),\"x\":L(410),\"y\":L(1100)},{\"depth\":L(0),\"tms\":L(55),\"x\":D(407ae80000000000),\"y\":D(408f920000000000)}],\"shotSpotX\":D(40792c0000000000),\"shotSpotY\":D(4092ea0000000000)}")
        XCTAssertEqual(wire(AFirebaseCodec.serialize(LiveShotEvent())),
                       "{\"aimError\":L(0),\"arcError\":L(0),\"hotHand\":B(false),\"id\":S(),\"made\":B(false),\"playerName\":S(),\"playerUid\":S(),\"powerError\":L(0),\"pullBack\":L(0),\"rawPeakGyro\":L(0),\"rawReleasePitchDeg\":L(0),\"releasedAt\":L(0),\"samples\":[],\"shotSpotX\":L(0),\"shotSpotY\":L(0)}")
        let entry = LeaderboardEntry(uid: "uidA", name: "Comet", bestScore: 212, bestShootingStreak: 8, bestKnowledgeStreak: 9,
                                     bestCorrectAnswers: 17, bestRunCorrectAnswers: 17, bestRunShots: 20, bestRunMadeShots: 14,
                                     bestRunKnowledgeAccuracyPercent: 85, bestRunShootingPercent: 70, bestRunCategories: ["MATH"],
                                     updatedAt: 1760000020000)
        XCTAssertEqual(wire(AFirebaseCodec.serialize(entry)),
                       "{\"bestCorrectAnswers\":L(17),\"bestKnowledgeStreak\":L(9),\"bestRunCategories\":[S(MATH)],\"bestRunCorrectAnswers\":L(17),\"bestRunKnowledgeAccuracyPercent\":L(85),\"bestRunMadeShots\":L(14),\"bestRunShootingPercent\":L(70),\"bestRunShots\":L(20),\"bestScore\":L(212),\"bestShootingStreak\":L(8),\"name\":S(Comet),\"uid\":S(uidA),\"updatedAt\":L(1760000020000)}")
        XCTAssertEqual(wire(AFirebaseCodec.serialize(LeaderboardEntry())),
                       "{\"bestCorrectAnswers\":L(0),\"bestKnowledgeStreak\":L(0),\"bestRunCategories\":[],\"bestRunCorrectAnswers\":L(0),\"bestRunKnowledgeAccuracyPercent\":L(0),\"bestRunMadeShots\":L(0),\"bestRunShootingPercent\":L(0),\"bestRunShots\":L(0),\"bestScore\":L(0),\"bestShootingStreak\":L(0),\"name\":S(),\"uid\":S(),\"updatedAt\":L(0)}")
        XCTAssertEqual(wire(AFirebaseCodec.serialize(RoomMeta(hostUid: "h", seed: -3141592653589793238, categories: ["AI", "MATH"]))),
                       "{\"categories\":[S(AI),S(MATH)],\"createdAt\":L(0),\"gameType\":S(SHOOTING_CHALLENGE),\"hostUid\":S(h),\"maxPlayers\":L(4),\"seed\":L(-3141592653589793238),\"startedAt\":L(0),\"status\":S(WAITING),\"timeLimitSeconds\":L(60)}")
        XCTAssertEqual(wire(AFirebaseCodec.serialize(LivePlayerState(uid: "u", name: "Comet", score: 7, finished: true, updatedAt: 5))),
                       "{\"bestKnowledgeStreak\":L(0),\"bestShootingStreak\":L(0),\"correctAnswers\":L(0),\"finished\":B(true),\"knowledgeStreak\":L(0),\"lastEvent\":S(),\"madeShots\":L(0),\"name\":S(Comet),\"score\":L(7),\"shootingStreak\":L(0),\"shots\":L(0),\"uid\":S(u),\"updatedAt\":L(5)}")
    }

    private static let horseFullWire =
        "{\"attemptedUids\":[S(uidB)],\"challengeCategory\":S(MATH),\"challengeEstablished\":B(true),\"challengeSpotId\":S(FREE_3),\"challengeSpotX\":D(40792c0000000000),\"challengeSpotY\":D(4092ea0000000000),\"currentPlayerUid\":S(uidB),\"finished\":B(false),\"penalties\":{\"uidA\":L(0),\"uidB\":L(1),\"uidC\":L(0)},\"phase\":S(ATTEMPT),\"playerOrder\":[S(uidA),S(uidB),S(uidC)],\"setterUid\":S(uidA),\"spectatorSlots\":{\"uidC\":L(0)},\"turnNumber\":L(4),\"updatedAt\":L(1760000030000),\"winnerUid\":S()}"

    /// X1: CustomClassMapper writes an enum as its name.
    func testSerializeKotlinEnumsByName() {
        XCTAssertEqual(wire(AFirebaseCodec.serialize(GameType.HORSE)), "S(HORSE)")
        XCTAssertEqual(wire(AFirebaseCodec.serialize(QuestionCategory.KIDS_ARITHMETIC)), "S(KIDS_ARITHMETIC)")
        let map: [String: Any] = ["g": GameType.TEAM_MATCH, "l": [QuestionCategory.MATH, QuestionCategory.AI]]
        XCTAssertEqual(wire(AFirebaseCodec.serialize(map)), "{\"g\":S(TEAM_MATCH),\"l\":[S(MATH),S(AI)]}")
        // X2: a null value inside a map or a list is kept (Firebase drops it as an empty node).
        let withNull: [String: Any] = ["a": NSNull(), "b": 1]
        XCTAssertEqual(wire(AFirebaseCodec.serialize(withNull)), "{\"a\":null,\"b\":L(1)}")
        XCTAssertEqual(wire(AFirebaseCodec.serialize(["a", NSNull()] as [Any])), "[S(a),null]")
    }

    /// X3: Validation.validateWritableObject / validatePathString / validateRootPathString texts.
    func testWriteValidationMessagesAsAndroid() {
        let nan = "Invalid value: Value cannot be NaN, Inf or -Inf."
        XCTAssertEqual(AFirebaseCodec.writableObjectProblem(AFirebaseCodec.serialize(["x": Double.nan])), nan)
        XCTAssertEqual(AFirebaseCodec.writableObjectProblem(AFirebaseCodec.serialize([1.0, Double.infinity])), nan)
        XCTAssertEqual(AFirebaseCodec.writableObjectProblem(AFirebaseCodec.serialize(["a/b": 1])),
                       "Invalid key: a/b. Keys must not contain '/', '.', '#', '$', '[', or ']'")
        XCTAssertEqual(AFirebaseCodec.writableObjectProblem(AFirebaseCodec.serialize([".x": 1])),
                       "Invalid key: .x. Keys must not contain '/', '.', '#', '$', '[', or ']'")
        XCTAssertNil(AFirebaseCodec.writableObjectProblem(AFirebaseCodec.serialize([".priority": 1])))
        XCTAssertNil(AFirebaseCodec.writableObjectProblem(AFirebaseCodec.serialize([".sv": "timestamp", "a/b": 1] as [String: Any])))
        XCTAssertEqual(AFirebaseCodec.writableObjectProblem(AFirebaseCodec.serialize(LiveHorseState(challengeSpotX: Float.nan))), nan)
        XCTAssertEqual(AFirebaseCodec.pathProblem("AB.CDE"),
                       "Invalid Firebase Database path: AB.CDE. Firebase Database paths must not contain '.', '#', '$', '[', or ']'")
        XCTAssertNil(AFirebaseCodec.rootPathProblem(".info/connected"))
        XCTAssertEqual(AFirebaseCodec.rootPathProblem(".info/a.b"),
                       "Invalid Firebase Database path: /a.b. Firebase Database paths must not contain '.', '#', '$', '[', or ']'")
    }

    func testServerValuePlaceholders() {
        XCTAssertEqual(wire(AFirebaseCodec.serialize(AServerValue.TIMESTAMP)), "{\".sv\":S(timestamp)}")
        XCTAssertEqual(wire(AFirebaseCodec.serialize(AServerValue.increment(1))), "{\".sv\":{\"increment\":L(1)}}")
        XCTAssertEqual(wire(AFirebaseCodec.serialize(AServerValue.increment(1.5))), "{\".sv\":{\"increment\":D(3ff8000000000000)}}")
        // Placeholders are not validated as keys (".sv").
        XCTAssertNil(AFirebaseCodec.writableObjectProblem(AFirebaseCodec.serialize(["updatedAt": AServerValue.TIMESTAMP])))
    }

    func testFirebaseValuesForTheIOSSDKKeepTheJavaNumberTypes() {
        let plain = AFirebaseCodec.serialize(["l": Int64(7), "d": 0.5, "b": true, "s": "x", "list": [Int64(1), NSNull()], "n": NSNull()])
        guard let value = AFirebaseCodec.firebaseValue(fromPlain: plain) as? NSDictionary else {
            return XCTFail("expected an NSDictionary")
        }
        let long = value["l"] as? NSNumber
        XCTAssertEqual(long.map { String(cString: $0.objCType) }, "q")
        XCTAssertEqual(long?.int64Value, 7)
        let double = value["d"] as? NSNumber
        XCTAssertEqual(double.map { String(cString: $0.objCType) }, "d")
        XCTAssertEqual(double?.doubleValue, 0.5)
        let flag = value["b"] as? NSNumber
        XCTAssertEqual(flag.map { CFGetTypeID($0) }, CFBooleanGetTypeID())
        XCTAssertEqual(value["s"] as? String, "x")
        XCTAssertEqual((value["list"] as? NSArray)?.count, 2)
        XCTAssertTrue((value["list"] as? NSArray)?[1] is NSNull)
        XCTAssertTrue(value["n"] is NSNull)
        XCTAssertTrue(AFirebaseCodec.firebaseValue(fromPlain: nil) is NSNull)
    }

    // MARK: - B: node values (NodeFromJSON + ChildrenNode.getValue: the List-or-Map rule)

    private func plain(_ firebaseValue: Any?) -> String {
        return wire(AFirebaseCodec.plainValue(AFirebaseCodec.node(fromFirebaseValue: firebaseValue)))
    }

    func testNodeValueListOrMapRule() {
        XCTAssertEqual(plain(["0": "a", "1": "b"]), "[S(a),S(b)]")
        XCTAssertEqual(plain(["0": "a", "2": "c"]), "[S(a),null,S(c)]")
        XCTAssertEqual(plain(["0": "a", "3": "d"]), "[S(a),null,null,S(d)]")
        XCTAssertEqual(plain(["0": "a", "4": "e"]), "{\"0\":S(a),\"4\":S(e)}")
        XCTAssertEqual(plain(["1": "x"]), "[null,S(x)]")
        XCTAssertEqual(plain(["01": "x"]), "{\"01\":S(x)}")
        XCTAssertEqual(plain(["-1": "x"]), "{\"-1\":S(x)}")
        XCTAssertEqual(plain(["0": "a", "b": "c"]), "{\"0\":S(a),\"b\":S(c)}")
        XCTAssertEqual(plain(["2147483648": "x"]), "{\"2147483648\":S(x)}")
        XCTAssertEqual(plain(["0": "a", "00": "b"]), "{\"0\":S(a),\"00\":S(b)}")
        XCTAssertEqual(plain(["5": "x"]), "{\"5\":S(x)}")
        XCTAssertEqual(plain(["0": "a", "1": "b", "2": [String: Any]()]), "[S(a),S(b)]")
        XCTAssertEqual(plain(5), "L(5)")
        XCTAssertEqual(plain(Int64(5)), "L(5)")
        XCTAssertEqual(plain(5.0), "D(4014000000000000)")
        XCTAssertEqual(plain(5.5), "D(4016000000000000)")
        XCTAssertEqual(plain(true), "B(true)")
        XCTAssertEqual(plain([String: Any]()), "null")
        XCTAssertEqual(plain([Any]()), "null")
        XCTAssertEqual(plain(["a", NSNull(), "c"]), "[S(a),null,S(c)]")
        XCTAssertEqual(plain(["0": ["tMs": Int64(5), "x": 1.5], "1": ["x": Int64(2)]]), "[{\"tMs\":L(5),\"x\":D(3ff8000000000000)},{\"x\":L(2)}]")
        XCTAssertEqual(plain(["10": "k", "9": "j", "0": "a", "1": "b", "2": "c", "3": "d", "4": "e", "5": "f", "6": "g", "7": "h", "8": "i"]),
                       "[S(a),S(b),S(c),S(d),S(e),S(f),S(g),S(h),S(i),S(j),S(k)]")
    }

    func testNodeFromJSONDropsEmptyChildrenAndDotKeys() {
        let node = AFirebaseCodec.node(fromFirebaseValue: ["a": [String: Any](), "b": NSNull(), ".priority": 5, "c": 1, "d": [Any]()])
        XCTAssertEqual(node, .children([AFirebaseNamedNode(key: "c", node: .leaf(.long(1)))]))
        XCTAssertEqual(AFirebaseCodec.node(fromFirebaseValue: [".value": "x", ".priority": 1]), .leaf(.string("x")))
        if case .leaf(.long(let now)) = AFirebaseCodec.node(fromFirebaseValue: AServerValue.TIMESTAMP) {
            XCTAssertGreaterThan(now, 1_700_000_000_000)
        } else {
            XCTFail("a timestamp placeholder resolves to a Long")
        }
        XCTAssertEqual(AFirebaseCodec.node(fromFirebaseValue: NSNumber(value: true)), .leaf(.bool(true)))
        XCTAssertEqual(AFirebaseCodec.node(fromFirebaseValue: NSNumber(value: 1)), .leaf(.long(1)))
        XCTAssertEqual(AFirebaseCodec.node(fromFirebaseValue: NSNumber(value: 1.0)), .leaf(.double(1)))
        // JSONSerialization hands long literals out as NSDecimalNumber; Android parses them as Long / Double.
        XCTAssertEqual(AFirebaseCodec.node(fromFirebaseValue: NSDecimalNumber(string: "9007199254740993")), .leaf(.long(9007199254740993)))
        XCTAssertEqual(AFirebaseCodec.node(fromFirebaseValue: NSDecimalNumber(string: "0.070000000000000007")),
                       .leaf(.double(0.070000000000000007)))
    }

    // MARK: - Child keys (ChildKey.compareTo, Utilities.tryParseInt)

    func testChildKeyOrderAsAndroid() {
        let keys = ["10", "9", "a", "-1", "007", "7", "b", "A", "0", "2147483648", "2147483647", "-2147483648",
                    "uidB", "uidA", "-OAbC", "-OAbB", "_x", "Z", "z", "1", "01", "\u{e9}", "\u{5d0}"]
        XCTAssertEqual(keys.sorted(by: AFirebaseCodec.childKeyPrecedes),
                       ["-2147483648", "-1", "0", "1", "01", "7", "007", "9", "10", "2147483647", "-OAbB", "-OAbC",
                        "2147483648", "A", "Z", "_x", "a", "b", "uidA", "uidB", "z", "\u{e9}", "\u{5d0}"])
        let node = AFirebaseCodec.node(fromFirebaseValue: ["uidB": 2, "uidA": 1, "10": 4, "9": 3])
        XCTAssertEqual(node.namedChildren.map { $0.key }, ["9", "10", "uidA", "uidB"])
    }

    func testTryParseIntAsAndroid() {
        let vectors: [(String, Int32?)] = [
            ("0", 0), ("-0", 0), ("007", 7), ("2147483647", 2147483647), ("2147483648", nil), ("-2147483648", -2147483648),
            ("-2147483649", nil), ("12345678901", nil), ("-1234567890", -1234567890), ("-12345678901", nil), ("-", nil),
            ("", nil), ("1a", nil), ("+1", nil), (" 1", nil), ("99999999999", nil)
        ]
        for (text, expected) in vectors {
            XCTAssertEqual(AFirebaseCodec.tryParseInt(text), expected, "tryParseInt(\(text))")
        }
    }

    // MARK: - C: getValue(Int/Long/Double/Float/Boolean/String::class.java)

    private static let conversionInputs: [(String, Any)] = [
        ("L5", Int64(5)), ("D5.9", 5.9), ("D-5.9", -5.9), ("L2147483648", Int64(2147483648)), ("D2147483648", 2147483648.0),
        ("D2147483647.9", 2147483647.9), ("D-2147483648.9", -2147483648.9), ("D-2147483649", -2147483649.0), ("D1e19", 1e19),
        ("D2^63", 9.223372036854775807e18), ("D-2^63", -9.223372036854775808e18), ("LMAX", Int64.max),
        ("L2^53+1", Int64(9007199254740993)), ("L2^53", Int64(9007199254740992)), ("L16777217", Int64(16777217)),
        ("DNaN", Double.nan), ("D1.7600000000009E12", 1.7600000000009e12), ("Btrue", true), ("S5", "5"),
        ("Map", ["a": Int64(1)] as [String: Any]), ("List", ["a"] as [Any])
    ]

    private func conversion(_ type: String, _ input: Any) -> String {
        do {
            switch type {
            case "int": return "I(" + String(try AFirebaseCodec.convertInteger(input)) + ")"
            case "long": return "L(" + String(try AFirebaseCodec.convertLong(input)) + ")"
            case "double": return "D(" + String(try AFirebaseCodec.convertDouble(input).bitPattern, radix: 16) + ")"
            case "float": return "F(" + String(try AFirebaseCodec.convertFloat(input).bitPattern, radix: 16) + ")"
            case "boolean": return "B(" + String(try AFirebaseCodec.convertBoolean(input)) + ")"
            default: return "S(" + (try AFirebaseCodec.convertString(input)) + ")"
            }
        } catch {
            return "EXC(" + message(error) + ")"
        }
    }

    func testPrimitiveConversionsAsCustomClassMapper() {
        let range32 = { (v: String) in "EXC(Numeric value out of 32-bit integer range: \(v). Did you mean to use a long or double instead of an int?)" }
        let range64 = { (v: String) in "EXC(Numeric value out of 64-bit long range: \(v). Did you mean to use a double instead of a long?)" }
        let precision = "EXC(Loss of precision while converting number to double: 9007199254740993. Did you mean to use a 64-bit long instead?)"
        let expected: [String: [String]] = [
            "int": ["I(5)", "I(5)", "I(-5)", range32("2.147483648E9"), range32("2.147483648E9"), range32("2.1474836479E9"),
                    range32("-2.1474836489E9"), range32("-2.147483649E9"), range32("1.0E19"), range32("9.223372036854776E18"),
                    range32("-9.223372036854776E18"), range32("9.223372036854776E18"), range32("9.007199254740992E15"),
                    range32("9.007199254740992E15"), "I(16777217)", range32("NaN"), range32("1.7600000000009E12"),
                    "EXC(Failed to convert a value of type java.lang.Boolean to int)",
                    "EXC(Failed to convert a value of type java.lang.String to int)",
                    "EXC(Failed to convert a value of type java.util.HashMap to int)",
                    "EXC(Failed to convert a value of type java.util.ArrayList to int)"],
            "long": ["L(5)", "L(5)", "L(-5)", "L(2147483648)", "L(2147483648)", "L(2147483647)", "L(-2147483648)", "L(-2147483649)",
                     range64("1.0E19"), "L(9223372036854775807)", "L(-9223372036854775808)", "L(9223372036854775807)",
                     "L(9007199254740993)", "L(9007199254740992)", "L(16777217)", range64("NaN"), "L(1760000000000)",
                     "EXC(Failed to convert a value of type java.lang.Boolean to long)",
                     "EXC(Failed to convert a value of type java.lang.String to long)",
                     "EXC(Failed to convert a value of type java.util.HashMap to long)",
                     "EXC(Failed to convert a value of type java.util.ArrayList to long)"],
            "double": ["D(4014000000000000)", "D(401799999999999a)", "D(c01799999999999a)", "D(41e0000000000000)",
                       "D(41e0000000000000)", "D(41dffffffff9999a)", "D(c1e00000001ccccd)", "D(c1e0000000200000)",
                       "D(43e158e460913d00)", "D(43e0000000000000)", "D(c3e0000000000000)", "D(43e0000000000000)", precision,
                       "D(4340000000000000)", "D(4170000010000000)", "D(7ff8000000000000)", "D(42799c82cc000e66)",
                       "EXC(Failed to convert a value of type java.lang.Boolean to double)",
                       "EXC(Failed to convert a value of type java.lang.String to double)",
                       "EXC(Failed to convert a value of type java.util.HashMap to double)",
                       "EXC(Failed to convert a value of type java.util.ArrayList to double)"],
            "float": ["F(40a00000)", "F(40bccccd)", "F(c0bccccd)", "F(4f000000)", "F(4f000000)", "F(4f000000)", "F(cf000000)",
                      "F(cf000000)", "F(5f0ac723)", "F(5f000000)", "F(df000000)", "F(5f000000)", precision, "F(5a000000)",
                      "F(4b800000)", "F(7fc00000)", "F(53cce416)",
                      "EXC(Failed to convert a value of type java.lang.Boolean to double)",
                      "EXC(Failed to convert a value of type java.lang.String to double)",
                      "EXC(Failed to convert a value of type java.util.HashMap to double)",
                      "EXC(Failed to convert a value of type java.util.ArrayList to double)"],
            "boolean": ["EXC(Failed to convert value of type java.lang.Long to boolean)",
                        "EXC(Failed to convert value of type java.lang.Double to boolean)",
                        "EXC(Failed to convert value of type java.lang.Double to boolean)",
                        "EXC(Failed to convert value of type java.lang.Long to boolean)",
                        "EXC(Failed to convert value of type java.lang.Double to boolean)",
                        "EXC(Failed to convert value of type java.lang.Double to boolean)",
                        "EXC(Failed to convert value of type java.lang.Double to boolean)",
                        "EXC(Failed to convert value of type java.lang.Double to boolean)",
                        "EXC(Failed to convert value of type java.lang.Double to boolean)",
                        "EXC(Failed to convert value of type java.lang.Double to boolean)",
                        "EXC(Failed to convert value of type java.lang.Double to boolean)",
                        "EXC(Failed to convert value of type java.lang.Long to boolean)",
                        "EXC(Failed to convert value of type java.lang.Long to boolean)",
                        "EXC(Failed to convert value of type java.lang.Long to boolean)",
                        "EXC(Failed to convert value of type java.lang.Long to boolean)",
                        "EXC(Failed to convert value of type java.lang.Double to boolean)",
                        "EXC(Failed to convert value of type java.lang.Double to boolean)",
                        "B(true)",
                        "EXC(Failed to convert value of type java.lang.String to boolean)",
                        "EXC(Failed to convert value of type java.util.HashMap to boolean)",
                        "EXC(Failed to convert value of type java.util.ArrayList to boolean)"],
            "String": ["EXC(Failed to convert value of type java.lang.Long to String)",
                       "EXC(Failed to convert value of type java.lang.Double to String)",
                       "EXC(Failed to convert value of type java.lang.Double to String)",
                       "EXC(Failed to convert value of type java.lang.Long to String)",
                       "EXC(Failed to convert value of type java.lang.Double to String)",
                       "EXC(Failed to convert value of type java.lang.Double to String)",
                       "EXC(Failed to convert value of type java.lang.Double to String)",
                       "EXC(Failed to convert value of type java.lang.Double to String)",
                       "EXC(Failed to convert value of type java.lang.Double to String)",
                       "EXC(Failed to convert value of type java.lang.Double to String)",
                       "EXC(Failed to convert value of type java.lang.Double to String)",
                       "EXC(Failed to convert value of type java.lang.Long to String)",
                       "EXC(Failed to convert value of type java.lang.Long to String)",
                       "EXC(Failed to convert value of type java.lang.Long to String)",
                       "EXC(Failed to convert value of type java.lang.Long to String)",
                       "EXC(Failed to convert value of type java.lang.Double to String)",
                       "EXC(Failed to convert value of type java.lang.Double to String)",
                       "EXC(Failed to convert value of type java.lang.Boolean to String)",
                       "S(5)",
                       "EXC(Failed to convert value of type java.util.HashMap to String)",
                       "EXC(Failed to convert value of type java.util.ArrayList to String)"]
        ]
        for type in ["int", "long", "double", "float", "boolean", "String"] {
            let rows = expected[type]!
            XCTAssertEqual(rows.count, Self.conversionInputs.count)
            for (index, input) in Self.conversionInputs.enumerated() where index < rows.count {
                XCTAssertEqual(conversion(type, input.1), rows[index], "C.\(type).\(input.0)")
            }
        }
    }

    // MARK: - D: DataSnapshot.getValue(X::class.java)

    func testSnapshotGetValueOfWireClassesAsAndroid() {
        XCTAssertEqual(describe(ADataSnapshot(key: "s", value: ["tms": Int64(55), "x": 410.5, "y": 1100.25, "depth": Int64(0)])
                                    .getValue(ShotReplaySample.self)),
                       "Sample(tMs=L(0),x=F(43cd4000),y=F(44898800),depth=F(0))")   // "tms" is not read back
        XCTAssertEqual(describe(ADataSnapshot(key: "s", value: ["tMs": Int64(55), "x": 410.5, "y": 1100.25, "depth": Int64(0)])
                                    .getValue(ShotReplaySample.self)),
                       "Sample(tMs=L(55),x=F(43cd4000),y=F(44898800),depth=F(0))")
        let horse: [String: Any] = [
            "phase": "ATTEMPT", "setterUid": "uidA", "currentPlayerUid": "uidB", "challengeEstablished": true,
            "challengeCategory": "MATH", "challengeSpotId": "FREE_3", "challengeSpotX": Int64(402), "challengeSpotY": 1210.5,
            "playerOrder": ["uidA", "uidB", "uidC"], "penalties": ["uidA": Int64(0), "uidB": Int64(1), "uidC": Int64(0)],
            "winnerUid": "", "turnNumber": 4.9, "updatedAt": Int64(1760000030000), "finished": false
        ]
        XCTAssertEqual(describe(ADataSnapshot(key: "horse", value: horse).getValue(LiveHorseState.self)),
                       "Horse(phase=S(ATTEMPT),setterUid=S(uidA),currentPlayerUid=S(uidB),challengeEstablished=B(true),challengeCategory=S(MATH),challengeSpotId=S(FREE_3),challengeSpotX=F(43c90000),challengeSpotY=F(44975000),playerOrder=[S(uidA),S(uidB),S(uidC)],attemptedUids=[],penalties={\"uidA\":I(0),\"uidB\":I(1),\"uidC\":I(0)},spectatorSlots={},winnerUid=S(),turnNumber=I(4),updatedAt=L(1760000030000),isFinished=B(false))")
        let horseNode: [String: Any] = [
            "phase": "SETTING", "playerOrder": ["0": "uidA", "1": "uidB"], "challengeSpotX": 0.30000001192092896,
            "spectatorSlots": ["uidB": Int64(1)]
        ]
        XCTAssertEqual(describe(ADataSnapshot(key: "horse", value: horseNode).getValue(LiveHorseState.self)),
                       "Horse(phase=S(SETTING),setterUid=S(),currentPlayerUid=S(),challengeEstablished=B(false),challengeCategory=S(),challengeSpotId=S(),challengeSpotX=F(3e99999a),challengeSpotY=F(0),playerOrder=[S(uidA),S(uidB)],attemptedUids=[],penalties={},spectatorSlots={\"uidB\":I(1)},winnerUid=S(),turnNumber=I(0),updatedAt=L(0),isFinished=B(false))")
        XCTAssertEqual(describe(ADataSnapshot(key: "meta", value: ["hostUid": "h", "seed": 1.7600000000009e12, "categories": ["AI", "MATH"]])
                                    .getValue(RoomMeta.self)),
                       "Meta(hostUid=S(h),status=S(WAITING),seed=L(1760000000000),createdAt=L(0),startedAt=L(0),gameType=S(SHOOTING_CHALLENGE),categories=[S(AI),S(MATH)],timeLimitSeconds=I(60),maxPlayers=I(4))")
        // An empty map is no node: getValue(RoomMeta) is null.
        XCTAssertNil(ADataSnapshot(key: "meta", value: [String: Any]()).getValue(RoomMeta.self))
        let shot: [String: Any] = [
            "id": "-OAbC", "playerUid": "uidA", "playerName": "Comet", "shotSpotX": 402.75, "shotSpotY": 1210.5,
            "aimError": 0.11999999731779099, "powerError": -0.05000000074505806, "rawReleasePitchDeg": Int64(48),
            "pullBack": 0.699999988079071, "hotHand": false, "releasedAt": Int64(1760000009000), "made": true,
            "samples": [["depth": Int64(0), "tms": Int64(0), "x": Int64(410), "y": Int64(1100)],
                        ["depth": Int64(0), "tMs": Int64(55), "x": 430.5, "y": 1010.25]]
        ]
        XCTAssertEqual(describe(ADataSnapshot(key: "-OAbC", value: shot).getValue(LiveShotEvent.self)),
                       "Shot(id=S(-OAbC),playerUid=S(uidA),playerName=S(Comet),shotSpotX=F(43c96000),shotSpotY=F(44975000),aimError=F(3df5c28f),powerError=F(bd4ccccd),arcError=F(0),rawPeakGyro=F(0),rawReleasePitchDeg=F(42400000),pullBack=F(3f333333),hotHand=B(false),releasedAt=L(1760000009000),made=B(true),samples=[Sample(tMs=L(0),x=F(43cd0000),y=F(44898000),depth=F(0)),Sample(tMs=L(55),x=F(43d74000),y=F(447c9000),depth=F(0))])")
        XCTAssertEqual(describe(ADataSnapshot(key: "u", value: ["uid": "u", "bestScore": 212.0, "bestRunCategories": ["MATH"], "updatedAt": 1.76e12])
                                    .getValue(LeaderboardEntry.self)),
                       "Entry(uid=S(u),name=S(),bestScore=I(212),bestShootingStreak=I(0),bestKnowledgeStreak=I(0),bestCorrectAnswers=I(0),bestRunCorrectAnswers=I(0),bestRunShots=I(0),bestRunMadeShots=I(0),bestRunKnowledgeAccuracyPercent=I(0),bestRunShootingPercent=I(0),bestRunCategories=[S(MATH)],updatedAt=L(1760000000000))")
        XCTAssertEqual(describe(ADataSnapshot(key: "u", value: ["uid": "u", "name": "Comet", "score": Int64(7), "finished": true,
                                                                "updatedAt": Int64(5), "extra": "x"])
                                    .getValue(LivePlayerState.self)),
                       "Player(uid=S(u),name=S(Comet),score=I(7),knowledgeStreak=I(0),shootingStreak=I(0),bestKnowledgeStreak=I(0),bestShootingStreak=I(0),correctAnswers=I(0),madeShots=I(0),shots=I(0),lastEvent=S(),finished=B(true),updatedAt=L(5))")
        // A hole in a list: Android keeps a null element ([a, null, c]); the model codec skips it (documented).
        XCTAssertEqual(ADataSnapshot(key: "horse", value: ["playerOrder": ["0": "a", "2": "c"]]).getValue(LiveHorseState.self)?.playerOrder,
                       ["a", "c"])
    }

    func testSnapshotGetValueTypeMismatchesReturnNilWhereAndroidThrows() {
        XCTAssertNil(ADataSnapshot(key: "h", value: ["turnNumber": "x"]).getValue(LiveHorseState.self))
        XCTAssertNil(ADataSnapshot(key: "h", value: ["playerOrder": ["a": "b"]]).getValue(LiveHorseState.self))
        XCTAssertNil(ADataSnapshot(key: "m", value: "string").getValue(RoomMeta.self))
        XCTAssertNil(ADataSnapshot(key: "h", value: ["penalties": ["x"]]).getValue(LiveHorseState.self))
        XCTAssertNil(ADataSnapshot(key: "p", value: ["finished": Int64(1)]).getValue(LivePlayerState.self))
        XCTAssertNil(ADataSnapshot(key: "h", value: ["turnNumber": 1e10]).getValue(LiveHorseState.self))
        XCTAssertNil(ADataSnapshot(key: "h", value: ["playerOrder": ["a", Int64(5)]]).getValue(LiveHorseState.self))
        XCTAssertNil(ADataSnapshot(key: "h", value: ["challengeSpotX": Int64(9007199254740993)]).getValue(LiveHorseState.self))
        XCTAssertNil(ADataSnapshot(key: "e", value: ["samples": ["x"]]).getValue(LiveShotEvent.self))
        XCTAssertNil(ADataSnapshot(key: "m", value: ["x"]).getValue(RoomMeta.self))
        // The repository's typed reads.
        XCTAssertEqual(ADataSnapshot(key: "total", value: 1.7600000000009e12).getValue(Int64.self), 1760000000000)
        XCTAssertNil(ADataSnapshot(key: "total", value: 1.7600000000009e12).getValue(Int.self))
        XCTAssertEqual(ADataSnapshot(key: "total", value: Int64(3)).getValue(Int64.self), 3)
        XCTAssertNil(ADataSnapshot(key: "total", value: "3").getValue(Int64.self))
        XCTAssertNil(ADataSnapshot(key: "total", value: nil).getValue(Int64.self))
        XCTAssertEqual(ADataSnapshot(key: "correct", value: true).getValue(Bool.self), true)
        XCTAssertNil(ADataSnapshot(key: "correct", value: Int64(1)).getValue(Bool.self))
        XCTAssertEqual(ADataSnapshot(key: "status", value: "FINISHED").getValue(String.self), "FINISHED")
        XCTAssertNil(ADataSnapshot(key: "status", value: Int64(1)).getValue(String.self))
        XCTAssertNil(ADataSnapshot(key: "status", value: NSNull()).getValue(String.self))
    }

    func testSnapshotNavigation() {
        let players: [String: Any] = [
            "uidB": ["uid": "uidB", "name": "Sunny", "score": Int64(3)],
            "uidA": ["uid": "uidA", "name": "Comet", "score": Int64(5)]
        ]
        let room = ADataSnapshot(key: "K7QW2M", value: ["meta": ["status": "WAITING", "hostUid": "uidA"], "players": players])
        XCTAssertTrue(room.exists())
        XCTAssertEqual(room.key, "K7QW2M")
        XCTAssertEqual(room.childrenCount, 2)
        XCTAssertEqual(room.child("players").childrenCount, 2)
        XCTAssertEqual(room.child("players").children.map { $0.key ?? "" }, ["uidA", "uidB"])
        XCTAssertEqual(room.child("players").children.compactMap { $0.getValue(LivePlayerState.self)?.name }, ["Comet", "Sunny"])
        XCTAssertTrue(room.child("players").child("uidB").exists())
        XCTAssertFalse(room.child("players").child("uidC").exists())
        XCTAssertEqual(room.child("meta/status").getValue(String.self), "WAITING")
        XCTAssertEqual(room.child("meta/status").key, "status")
        XCTAssertTrue(room.hasChild("meta/hostUid"))
        XCTAssertFalse(room.hasChild("meta/seed"))
        XCTAssertEqual(room.child("meta").child("status").child("x").childrenCount, 0)
        XCTAssertFalse(room.child("meta").child("status").hasChildren())
        XCTAssertFalse(ADataSnapshot(key: nil, value: nil).exists())
    }

    // MARK: - MutableData (transactions)

    func testMutableDataRoundTripAsAndroid() {
        let data = AMutableData(value: nil)
        XCTAssertNil(data.key)
        XCTAssertNil(data.value)
        XCTAssertNil(data.getValue(LiveHorseState.self))
        XCTAssertFalse(data.hasChildren())
        let horse = LiveHorseState(phase: "ATTEMPT", setterUid: "uidA", currentPlayerUid: "uidB", challengeEstablished: true,
                                   challengeCategory: "MATH", challengeSpotId: "FREE_3", challengeSpotX: 402.75, challengeSpotY: 1210.5,
                                   playerOrder: ["uidA", "uidB", "uidC"], attemptedUids: ["uidB"],
                                   penalties: ["uidA": 0, "uidB": 1, "uidC": 0], spectatorSlots: ["uidC": 0],
                                   winnerUid: "", turnNumber: 4, updatedAt: 1760000030000)
        data.value = horse
        XCTAssertNil(data.run.failure)
        XCTAssertEqual(wire(data.value), Self.horseFullWire)
        XCTAssertEqual(data.getValue(LiveHorseState.self), horse)
        XCTAssertEqual(data.child("penalties").child("uidB").getValue(Int.self), 1)
        XCTAssertEqual(data.child("penalties/uidB").key, "uidB")
        XCTAssertTrue(data.hasChild("playerOrder/2"))
        XCTAssertEqual(data.childrenCount, 16)
        data.child("winnerUid").value = "uidA"
        XCTAssertEqual(data.getValue(LiveHorseState.self)?.winnerUid, "uidA")
        XCTAssertEqual(data.getValue(LiveHorseState.self)?.isFinished, true)
        data.child("attemptedUids").value = nil
        XCTAssertEqual(data.getValue(LiveHorseState.self)?.attemptedUids, [])
        XCTAssertNil(data.run.failure)
    }

    func testMutableDataRecordsTheExceptionsAndroidThrowsOutOfDoTransaction() {
        let data = AMutableData(value: ["phase": "SETTING"])
        data.value = Double.nan
        XCTAssertEqual(data.run.failure.map { message($0) }, "Invalid value: Value cannot be NaN, Inf or -Inf.")
        XCTAssertEqual(data.getValue(LiveHorseState.self)?.phase, "SETTING")   // nothing was written

        let mismatch = AMutableData(value: ["turnNumber": "x"])
        XCTAssertNil(mismatch.getValue(LiveHorseState.self))
        XCTAssertNotNil(mismatch.run.failure)

        let badKey = AMutableData(value: nil)
        badKey.value = ["a/b": 1]
        XCTAssertEqual(badKey.run.failure.map { message($0) }, "Invalid key: a/b. Keys must not contain '/', '.', '#', '$', '[', or ']'")
        XCTAssertNil(badKey.value)

        let typed = AMutableData(value: Int64(5))
        XCTAssertNil(typed.getValue(String.self))
        XCTAssertEqual(typed.run.failure.map { message($0) }, "Failed to convert value of type java.lang.Long to String")
        XCTAssertTrue(ATransaction.success(typed).isSuccess)
        XCTAssertFalse(ATransaction.abort().isSuccess)

        // X4.userCode: the transaction's error is DatabaseError.fromException of a DatabaseException (Android's text
        // goes on with the stack trace after these two lines).
        guard let failure = mismatch.run.failure else { return XCTFail("the mismatch is recorded") }
        XCTAssertTrue(failure is ADatabaseException)
        let userError = ADatabaseError.fromException(failure)
        XCTAssertEqual(userError.code, ADatabaseError.USER_CODE_EXCEPTION)
        XCTAssertEqual(userError.code, -11)
        XCTAssertEqual(userError.message.components(separatedBy: "\n").prefix(2).joined(separator: "|"),
                       "User code called from the Firebase Database runloop threw an exception:|com.google.firebase.database.DatabaseException: Failed to convert a value of type java.lang.String to int")
    }

    // MARK: - Validation, paths, push ids

    func testPathAndKeyValidationAsAndroid() {
        XCTAssertEqual(AFirebaseCodec.pathSegments("rooms//K7QW2M/players/"), ["rooms", "K7QW2M", "players"])
        XCTAssertEqual(AFirebaseCodec.pathSegments(""), [])
        XCTAssertNil(AFirebaseCodec.pathProblem("tripleShot/rooms/K7QW2M"))
        XCTAssertNil(AFirebaseCodec.pathProblem(""))
        XCTAssertEqual(AFirebaseCodec.pathProblem("AB.CDE"),
                       "Invalid Firebase Database path: AB.CDE. Firebase Database paths must not contain '.', '#', '$', '[', or ']'")
        XCTAssertNotNil(AFirebaseCodec.pathProblem("a#b"))
        XCTAssertNotNil(AFirebaseCodec.pathProblem("a$b"))
        XCTAssertNotNil(AFirebaseCodec.pathProblem("a[0]"))
        XCTAssertNil(AFirebaseCodec.rootPathProblem(".info/connected"))
        XCTAssertNotNil(AFirebaseCodec.rootPathProblem(".info/a.b"))
        XCTAssertNil(AFirebaseCodec.writableKeyProblem("uidA"))
        XCTAssertNil(AFirebaseCodec.writableKeyProblem(".priority"))
        XCTAssertNotNil(AFirebaseCodec.writableKeyProblem(".x"))
        XCTAssertNotNil(AFirebaseCodec.writableKeyProblem(""))
        XCTAssertNotNil(AFirebaseCodec.writableKeyProblem("a\u{7}b"))
        XCTAssertNil(AFirebaseCodec.writableObjectProblem(AFirebaseCodec.serialize(LiveShotEvent())))
        XCTAssertEqual(AFirebaseCodec.writableObjectProblem(AFirebaseCodec.serialize(["x": [Double.infinity]])),
                       "Invalid value: Value cannot be NaN, Inf or -Inf.")
    }

    func testPushIdTimePrefixAndIncrementAsAndroid() {
        let first = AFirebaseCodec.generatePushChildName(1760000000000)
        let second = AFirebaseCodec.generatePushChildName(1760000000000)
        XCTAssertEqual(first.count, 20)
        XCTAssertTrue(first.hasPrefix("-Ob7AB--"))
        XCTAssertTrue(second.hasPrefix("-Ob7AB--"))
        let chars = Array("-0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz")
        let a = first.dropFirst(8).map { chars.firstIndex(of: $0)! }
        let b = second.dropFirst(8).map { chars.firstIndex(of: $0)! }
        var expected = a
        for index in stride(from: 11, through: 0, by: -1) {
            if expected[index] != 63 {
                expected[index] += 1
                break
            }
            expected[index] = 0
        }
        XCTAssertEqual(b, expected)
        XCTAssertEqual(String(AFirebaseCodec.generatePushChildName(0).prefix(8)), "--------")
        XCTAssertEqual(String(AFirebaseCodec.generatePushChildName(1).prefix(8)), "-------0")
        XCTAssertEqual(String(AFirebaseCodec.generatePushChildName(281474976710655).prefix(8)), "zzzzzzzz")
    }

    // MARK: - DatabaseError

    func testDatabaseErrorAsAndroid() {
        let denied = ADatabaseError.fromStatus("permission_denied", "Permission denied")
        XCTAssertEqual(denied.code, ADatabaseError.PERMISSION_DENIED)
        XCTAssertEqual(denied.message, "Permission denied")
        XCTAssertEqual(denied.toException().message, "Firebase Database error: Permission denied")
        XCTAssertEqual(denied.description, "DatabaseError: Permission denied")
        XCTAssertEqual(ADatabaseError.fromStatus("PERMISSION_DENIED").message,
                       "This client does not have permission to perform this operation")
        XCTAssertEqual(ADatabaseError.fromStatus("nonsense").code, ADatabaseError.UNKNOWN_ERROR)
        XCTAssertEqual(ADatabaseError.fromCode(ADatabaseError.MAX_RETRIES).message, "The transaction had too many retries")
        XCTAssertTrue(ADatabaseError.fromException(ADatabaseException("Failed to convert a value of type java.lang.String to int"))
                        .message.hasPrefix("User code called from the Firebase Database runloop threw an exception:\n"))
        // FirebaseDatabase iOS errors (FUtilities errorForStatus).
        let iosDenied = NSError(domain: "com.firebase", code: 1, userInfo: [NSLocalizedDescriptionKey: "Permission denied"])
        XCTAssertEqual(ADatabaseError.fromFirebaseError(iosDenied).code, ADatabaseError.PERMISSION_DENIED)
        XCTAssertEqual(ADatabaseError.fromFirebaseError(iosDenied).toException().message, "Firebase Database error: Permission denied")
        let iosRetries = NSError(domain: "com.firebase", code: 9999, userInfo: [NSLocalizedDescriptionKey: "maxretry"])
        XCTAssertEqual(ADatabaseError.fromFirebaseError(iosRetries).code, ADatabaseError.MAX_RETRIES)
        let iosSet = NSError(domain: "com.firebase", code: 9999, userInfo: [NSLocalizedDescriptionKey: "set"])
        XCTAssertEqual(ADatabaseError.fromFirebaseError(iosSet).message, "The transaction was overridden by a subsequent set")
        let iosCanceled = NSError(domain: "com.firebase", code: 3, userInfo: [NSLocalizedDescriptionKey: "Write cancelled by user"])
        XCTAssertEqual(ADatabaseError.fromFirebaseError(iosCanceled).message, "The write was canceled by the user.")
        // X4: the remaining Android texts.
        XCTAssertEqual(ADatabaseError.fromCode(ADatabaseError.UNAVAILABLE).message, "The service is unavailable")
        XCTAssertEqual(ADatabaseError.fromCode(ADatabaseError.UNAVAILABLE).toException().message,
                       "Firebase Database error: The service is unavailable")
        XCTAssertEqual(ADatabaseError.fromStatus("nonsense").code, -999)
        XCTAssertEqual(ADatabaseError.fromStatus("nonsense").message, "An unknown error occurred")
        XCTAssertEqual(ADatabaseError.fromStatus("write_canceled").message, "The write was canceled by the user.")
        XCTAssertEqual(ADatabaseError.fromCode(ADatabaseError.OVERRIDDEN_BY_SET).message,
                       "The transaction was overridden by a subsequent set")
        XCTAssertEqual(ADatabaseError.fromCode(ADatabaseError.DISCONNECTED).message,
                       "The operation had to be aborted due to a network disconnect")
        XCTAssertEqual(ADatabaseError.fromStatus("permission_denied", "Permission denied", "more").details, "more")
        XCTAssertEqual(ADatabaseError.fromStatus("permission_denied", "Permission denied").details, "")
        // iOS transaction aborts: "disconnect" and a server status with its reason.
        let iosDisconnect = NSError(domain: "com.firebase", code: 9999, userInfo: [NSLocalizedDescriptionKey: "disconnect"])
        XCTAssertEqual(ADatabaseError.fromFirebaseError(iosDisconnect).code, ADatabaseError.DISCONNECTED)
        let iosUnavailable = NSError(domain: "com.firebase", code: 2, userInfo: [NSLocalizedDescriptionKey: "Service is unavailable"])
        XCTAssertEqual(ADatabaseError.fromFirebaseError(iosUnavailable).code, ADatabaseError.UNAVAILABLE)
    }

    // MARK: - Tasks

    func testTaskListenersArePostedInOrderAlsoAfterCompletion() {
        let source = ATaskCompletionSource<Int>()
        var events: [String] = []
        let done = expectation(description: "listeners")
        done.expectedFulfillmentCount = 3
        source.task.addOnSuccessListener { value in
            events.append("success\(value)")
            done.fulfill()
        }
        source.task.addOnFailureListener { _ in events.append("failure") }
        source.task.addOnCompleteListener { task in
            events.append("complete\(task.isSuccessful)")
            done.fulfill()
        }
        source.setResult(7)
        XCTAssertEqual(events, [])   // never inline
        source.task.addOnSuccessListener { value in
            events.append("late\(value)")
            done.fulfill()
        }
        XCTAssertEqual(events, [])
        wait(for: [done], timeout: 5)
        XCTAssertEqual(events, ["success7", "completetrue", "late7"])
        XCTAssertTrue(source.task.isComplete)
        XCTAssertEqual(source.task.result, 7)
        XCTAssertNil(source.task.exception)
        XCTAssertFalse(source.trySetResult(8))
        XCTAssertEqual(source.task.result, 7)
    }

    func testFailedTaskCallsOnlyFailureAndCompleteListeners() {
        let task: ATask<Void> = ATasks.forException(ADatabaseException("Firebase Database error: Permission denied"))
        var events: [String] = []
        let done = expectation(description: "listeners")
        done.expectedFulfillmentCount = 2
        task.addOnSuccessListener { events.append("success") }
            .addOnFailureListener { error in
                events.append("failure:" + ((error as? AFirebaseException)?.message ?? ""))
                done.fulfill()
            }
            .addOnCompleteListener { task in
                events.append("complete\(task.isSuccessful)")
                done.fulfill()
            }
        wait(for: [done], timeout: 5)
        XCTAssertEqual(events, ["failure:Firebase Database error: Permission denied", "completefalse"])
        XCTAssertNil(task.result)
    }

    // MARK: - App registration

    func testGoogleAppIDFormatThatFirebaseCoreAccepts() {
        XCTAssertTrue(AFirebaseApp.isValidGoogleAppID("1:12298786440:ios:6f2c7a3e9d1b4c5a8e7f01"))
        XCTAssertFalse(AFirebaseApp.isValidGoogleAppID("1:12298786440:android:6f2c7a3e9d1b4c5a"))
        XCTAssertFalse(AFirebaseApp.isValidGoogleAppID("1:12298786440:ios:REPLACE_ME"))
        XCTAssertFalse(AFirebaseApp.isValidGoogleAppID(""))
        XCTAssertFalse(AFirebaseApp.isValidGoogleAppID("x:1:ios:ab"))
        XCTAssertTrue(AFirebaseApp.isValidGoogleAppID("2:anything"))
    }

    /// TripleShotFirebaseRepository: ROOT_NODE "tripleShot" on DATABASE_URL (after `trimEnd('/')`), project minikswish.
    func testRegistrationConstantsAsAndroid() {
        XCTAssertEqual(AFirebaseApp.APP_NAME, "tripleshot")
        XCTAssertEqual(AFirebaseApp.PROJECT_ID, "minikswish")
        XCTAssertEqual(AFirebaseApp.DATABASE_URL, "https://minikswish-default-rtdb.europe-west1.firebasedatabase.app")
        XCTAssertEqual(AFirebaseApp.trimmedURL("https://minikswish-default-rtdb.europe-west1.firebasedatabase.app//"),
                       AFirebaseApp.DATABASE_URL)
        XCTAssertEqual(AFirebaseApp.trimmedURL(""), "")
        XCTAssertTrue(AFirebaseApp.isDatabaseRootURL(AFirebaseApp.DATABASE_URL))
        XCTAssertTrue(AFirebaseApp.isDatabaseRootURL(AFirebaseApp.DATABASE_URL + "/"))
        XCTAssertFalse(AFirebaseApp.isDatabaseRootURL(AFirebaseApp.DATABASE_URL + "/tripleShot"))
        XCTAssertFalse(AFirebaseApp.isDatabaseRootURL("minikswish-default-rtdb"))
        XCTAssertFalse(AFirebaseApp.isDatabaseRootURL(""))
        // FirebaseApp.getInstance().applicationContext (the repository's onlineName()).
        XCTAssertTrue(AFirebaseApp.getInstance().applicationContext === AApplication.shared)
        XCTAssertTrue(AFirebaseApp.getInstance() === AFirebaseApp.getInstance())
    }

    /// Without TripleShot's GoogleService-Info.plist (minikswish) every call fails gracefully instead of crashing.
    func testMissingRegistrationFailsGracefully() throws {
        let app = AFirebaseApp.getInstance()
        try XCTSkipIf(app.isAvailable, "a real Firebase registration is bundled with the test host")
        XCTAssertEqual(app.name, "tripleshot")
        XCTAssertNotNil(app.unavailableReason)
        let auth = AFirebaseAuth.getInstance()
        XCTAssertNil(auth.currentUser)
        let signedIn = expectation(description: "sign-in fails")
        auth.signInAnonymously().addOnCompleteListener { task in
            XCTAssertFalse(task.isSuccessful)
            XCTAssertTrue(task.exception is AFirebaseNotConfiguredException)
            XCTAssertNil((task.exception as? AFirebaseException)?.message)
            signedIn.fulfill()
        }
        let root = AFirebaseDatabase.getInstance("https://minikswish-default-rtdb.europe-west1.firebasedatabase.app").reference.child("tripleShot")
        XCTAssertEqual(root.child("rooms").child("K7QW2M").key, "K7QW2M")
        XCTAssertEqual(root.child("users/u/knowledgeAttempts").push().key?.count, 20)
        let read = expectation(description: "get fails")
        root.child("leaderboard").orderByChild("bestScore").limitToLast(20).get().addOnFailureListener { error in
            XCTAssertTrue(error is AFirebaseNotConfiguredException)
            read.fulfill()
        }
        let written = expectation(description: "write fails")
        root.child("rooms").child("K7QW2M").updateChildren(["meta/status": "PLAYING", "meta/startedAt": AServerValue.TIMESTAMP])
            .addOnFailureListener { _ in written.fulfill() }
        let handler = AbortingHandler(expectation(description: "transaction completes"))
        root.child("leaderboard").child("u").runTransaction(handler)
        wait(for: [signedIn, read, written, handler.done], timeout: 5)
        XCTAssertEqual(handler.errorCode, ADatabaseError.UNAVAILABLE)
        XCTAssertEqual(handler.committed, false)
    }

    /// Without a registration, listeners are cancelled with UNAVAILABLE (posted). Removal follows Android's rules:
    /// by listener identity, per query spec, and through the plain reference for every query at the location
    /// (orderByPriority() alone is the default spec).
    func testMissingRegistrationCancelsListenersAndRemovalFollowsAndroid() throws {
        try XCTSkipIf(AFirebaseApp.getInstance().isAvailable, "a real Firebase registration is bundled with the test host")
        let shots = AFirebaseDatabase.getInstance(AFirebaseApp.DATABASE_URL).reference.child("tripleShot/rooms/K7QW2M/shots")
        let meta = RecordingValueListener()
        shots.parent?.child("meta").addValueEventListener(meta)
        let added = RecordingChildListener()
        shots.orderByChild("releasedAt").startAt(1760000000000.0).addChildEventListener(added)
        let removedByRef = RecordingValueListener()
        shots.orderByChild("releasedAt").addValueEventListener(removedByRef)
        shots.removeEventListener(removedByRef)                      // default spec: every query at this location
        let otherSpec = RecordingValueListener()
        shots.orderByChild("releasedAt").addValueEventListener(otherSpec)
        shots.orderByKey().removeEventListener(otherSpec)            // another spec: not removed
        let priority = RecordingValueListener()
        shots.addValueEventListener(priority)
        shots.orderByPriority().removeEventListener(priority)        // QuerySpec.isDefault(): removed as well
        let single = RecordingValueListener()
        shots.addListenerForSingleValueEvent(single)
        shots.removeEventListener(single)                            // the internal wrapper is registered, not `single`
        XCTAssertEqual(meta.cancelled + added.cancelled + otherSpec.cancelled + single.cancelled, [])   // never inline
        let drained = expectation(description: "main looper drained")
        AHandler(ALooper.getMainLooper()).post { drained.fulfill() }
        wait(for: [drained], timeout: 5)
        XCTAssertEqual(meta.cancelled, [ADatabaseError.UNAVAILABLE])
        XCTAssertEqual(added.cancelled, [ADatabaseError.UNAVAILABLE])
        XCTAssertEqual(removedByRef.cancelled, [])
        XCTAssertEqual(otherSpec.cancelled, [ADatabaseError.UNAVAILABLE])
        XCTAssertEqual(priority.cancelled, [])
        XCTAssertEqual(single.cancelled, [ADatabaseError.UNAVAILABLE])
        XCTAssertEqual(meta.changes + removedByRef.changes + otherSpec.changes + priority.changes + single.changes, 0)
        XCTAssertEqual(added.added, 0)
    }
}

private final class RecordingValueListener: AValueEventListener {
    var changes = 0
    var cancelled: [Int] = []

    func onDataChange(_ snapshot: ADataSnapshot) {
        changes += 1
    }

    func onCancelled(_ error: ADatabaseError) {
        cancelled.append(error.code)
    }
}

private final class RecordingChildListener: AChildEventListener {
    var added = 0
    var cancelled: [Int] = []

    func onChildAdded(_ snapshot: ADataSnapshot, _ previousChildName: String?) {
        added += 1
    }

    func onChildChanged(_ snapshot: ADataSnapshot, _ previousChildName: String?) {}

    func onChildRemoved(_ snapshot: ADataSnapshot) {}

    func onChildMoved(_ snapshot: ADataSnapshot, _ previousChildName: String?) {}

    func onCancelled(_ error: ADatabaseError) {
        cancelled.append(error.code)
    }
}

private final class AbortingHandler: ATransaction.Handler {
    let done: XCTestExpectation
    var errorCode: Int?
    var committed: Bool?

    init(_ done: XCTestExpectation) {
        self.done = done
    }

    func doTransaction(_ currentData: AMutableData) -> ATransaction.Result {
        return ATransaction.abort()
    }

    func onComplete(_ error: ADatabaseError?, _ committed: Bool, _ currentData: ADataSnapshot?) {
        errorCode = error?.code
        self.committed = committed
        done.fulfill()
    }
}
