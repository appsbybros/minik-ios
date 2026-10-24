import XCTest
@testable import MinikTripleShot

/// Pure parts of TripleShot/Firebase/TripleShotFirebaseRepository.swift (port of firebase/TripleShotFirebaseRepository.kt)
/// and the nickname storage of TripleShot/UI/TripleShotOnlineIdentity.swift: constants, payload maps and their JSON
/// types, the bucket / rank / percent maths, the UTC month and ISO-week keys, snapshot parsing and the transaction
/// handlers run on stand-alone AMutableData. Nothing here talks to the network.
///
/// JVM golden vectors (bucket and leaderboard percents, week/month keys, `take(n)` as Android's websocket encodes it)
/// come from the Kotlin statements of the repository run on the JVM (harness:
/// scratchpad/swish/work/w-firebase/src/Golden.kt, output golden.txt).
final class FirebaseRepositoryTests: XCTestCase {

    private static let identityKeys = ["tripleshot_online_identity.nickname", "tripleshot_online_identity.confirmed"]
    private var savedIdentity: [String: Any] = [:]

    override func setUp() {
        super.setUp()
        savedIdentity = [:]
        for key in Self.identityKeys {
            if let value = UserDefaults.standard.object(forKey: key) {
                savedIdentity[key] = value
            }
        }
        // Every name written online is the nickname: make it known.
        UserDefaults.standard.set("Gaya", forKey: "tripleshot_online_identity.nickname")
        UserDefaults.standard.removeObject(forKey: "tripleshot_online_identity.confirmed")
    }

    override func tearDown() {
        for key in Self.identityKeys {
            if let value = savedIdentity[key] {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        super.tearDown()
    }

    // MARK: - Printing (the notation of FirebaseCodecTests)

    /// A plain value after CustomClassMapper serialization: S(string) L(long) D(double bits) B(boolean),
    /// {"key":value,...} with sorted keys, [list], null.
    private func wire(_ value: Any?) -> String {
        guard let value = value, !(value is NSNull) else { return "null" }
        if let text = value as? String, type(of: value) == String.self { return "S(" + text + ")" }
        if let flag = value as? Bool, type(of: value) == Bool.self { return "B(" + String(flag) + ")" }
        if let long = value as? Int64, type(of: value) == Int64.self { return "L(" + String(long) + ")" }
        if let double = value as? Double, type(of: value) == Double.self { return "D(" + String(double.bitPattern, radix: 16) + ")" }
        if let map = value as? [String: Any] {
            return "{" + map.keys.sorted().map { "\"" + $0 + "\":" + wire(map[$0]) }.joined(separator: ",") + "}"
        }
        if let list = value as? [Any] {
            return "[" + list.map { wire($0) }.joined(separator: ",") + "]"
        }
        return "?" + String(describing: type(of: value))
    }

    /// The JSON a value becomes on the wire.
    private func json(_ value: Any?) -> String {
        return wire(AFirebaseCodec.serialize(value))
    }

    private static let timestamp = "{\".sv\":S(timestamp)}"
    private static let increment = "{\".sv\":{\"increment\":L(1)}}"

    /// Throwable.getMessage() of a repository failure.
    private func message(_ error: Error?) -> String? {
        return (error as? AFirebaseException)?.message
    }

    // MARK: - Constants

    func testCompanionConstantsMatchKotlin() {
        XCTAssertEqual(TripleShotFirebaseRepository.ROOT_NODE, "tripleShot")
        XCTAssertEqual(TripleShotFirebaseRepository.DATABASE_URL,
                       "https://minikswish-default-rtdb.europe-west1.firebasedatabase.app")
        XCTAssertEqual(TripleShotFirebaseRepository.ROOM_ALPHABET, "ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        XCTAssertEqual(TripleShotFirebaseRepository.ROOM_ALPHABET.count, 32)
        for confusable in ["I", "O", "0", "1"] {
            XCTAssertFalse(TripleShotFirebaseRepository.ROOM_ALPHABET.contains(confusable), confusable)
        }
        XCTAssertEqual(TripleShotFirebaseRepository.MAX_REPLAY_SAMPLES, 60)
        XCTAssertEqual(TripleShotFirebaseRepository.LIVE_EVENT_GRACE_MS, 750)
    }

    func testRepositoryErrorsCarryAndroidsMessages() {
        let state = TripleShotFirebaseRepository.IllegalStateException("Room is full")
        XCTAssertEqual(state.message, "Room is full")
        XCTAssertEqual(state.errorDescription, "Room is full")
        XCTAssertEqual(state.description, "java.lang.IllegalStateException: Room is full")
        let argument = TripleShotFirebaseRepository.IllegalArgumentException("Room not found")
        XCTAssertEqual(message(argument), "Room not found")
        XCTAssertEqual(argument.description, "java.lang.IllegalArgumentException: Room not found")
        // AndroidKit's "not configured" failure has no message, so callers fall back to minik_swish_firebase_error.
        XCTAssertNil(message(AFirebaseNotConfiguredException()))
    }

    // MARK: - KnowledgeBucket.accuracyPercent (Float maths, truncation)

    /// (total, correct, accuracyPercent) on the JVM.
    private static let buckets: [(Int, Int, Int)] = [
        (0, 0, 0),
        (0, 5, 0),
        (-3, 1, 0),
        (1, 0, 0),
        (1, 1, 100),
        (2, 1, 50),
        (3, 1, 33),
        (3, 2, 66),
        (6, 1, 16),
        (7, 1, 14),
        (7, 3, 42),
        (9, 7, 77),
        (10, 3, 30),
        (11, 7, 63),
        (13, 9, 69),
        (29, 17, 58),
        (100, 57, 57),
        (3, 4, 100),
        (5, -1, 0),
        (49, 48, 97),
        (97, 96, 98),
        (1000000, 999999, 99),
        (16777217, 16777216, 100),
        (16777216, 16777215, 99),
        (33554433, 33554431, 100),
        (2147483647, 2147483646, 100),
        (2147483647, 21474836, 1),
        (300, 299, 99),
        (1, 2147483647, 100),
        (999, 998, 99),
        (1001, 1000, 99),
        (70, 69, 98),
        (41, 29, 70),
        (20, 14, 70),
        (20, 17, 85),
        (60, 59, 98),
        (99999999, 99999998, 100),
    ]

    func testKnowledgeBucketAccuracyMatchesTheJvm() {
        XCTAssertEqual(TripleShotFirebaseRepository.KnowledgeBucket().accuracyPercent, 0)
        for (total, correct, expected) in Self.buckets {
            XCTAssertEqual(TripleShotFirebaseRepository.KnowledgeBucket(total: total, correct: correct).accuracyPercent,
                           expected, "total \(total) correct \(correct)")
        }
    }

    // MARK: - UTC month and ISO-week keys (shared path segments of users/ and communityKnowledge/)

    /// (ms, utcWeekKey, utcMonthKey) on the JVM: year boundaries with 52 and 53 weeks, leap day, epoch, 2100.
    private static let dateKeys: [(Int64, String, String)] = [
        (-259200000, "1970-W01", "1969-12"),
        (-259200001, "1969-W52", "1969-12"),
        (-172800000, "1970-W01", "1969-12"),
        (-172800001, "1970-W01", "1969-12"),
        (-86400000, "1970-W01", "1969-12"),
        (-86400001, "1970-W01", "1969-12"),
        (0, "1970-W01", "1970-01"),
        (-1, "1970-W01", "1969-12"),
        (86400000, "1970-W01", "1970-01"),
        (86399999, "1970-W01", "1970-01"),
        (172800000, "1970-W01", "1970-01"),
        (172799999, "1970-W01", "1970-01"),
        (259200000, "1970-W01", "1970-01"),
        (259199999, "1970-W01", "1970-01"),
        (-259200002, "1969-W52", "1969-12"),
        (-172800002, "1970-W01", "1969-12"),
        (-86400002, "1970-W01", "1969-12"),
        (-2, "1970-W01", "1969-12"),
        (86399998, "1970-W01", "1970-01"),
        (172799998, "1970-W01", "1970-01"),
        (259199998, "1970-W01", "1970-01"),
        (-259199999, "1970-W01", "1969-12"),
        (-172799999, "1970-W01", "1969-12"),
        (-86399999, "1970-W01", "1969-12"),
        (1, "1970-W01", "1970-01"),
        (86400001, "1970-W01", "1970-01"),
        (172800001, "1970-W01", "1970-01"),
        (259200001, "1970-W01", "1970-01"),
        (1545955200000, "2018-W52", "2018-12"),
        (1545955199999, "2018-W52", "2018-12"),
        (1546041600000, "2018-W52", "2018-12"),
        (1546041599999, "2018-W52", "2018-12"),
        (1546128000000, "2018-W52", "2018-12"),
        (1546127999999, "2018-W52", "2018-12"),
        (1546214400000, "2019-W01", "2018-12"),
        (1546214399999, "2018-W52", "2018-12"),
        (1546300800000, "2019-W01", "2019-01"),
        (1546300799999, "2019-W01", "2018-12"),
        (1546387200000, "2019-W01", "2019-01"),
        (1546387199999, "2019-W01", "2019-01"),
        (1546473600000, "2019-W01", "2019-01"),
        (1546473599999, "2019-W01", "2019-01"),
        (1609200000000, "2020-W53", "2020-12"),
        (1609199999999, "2020-W53", "2020-12"),
        (1609286400000, "2020-W53", "2020-12"),
        (1609286399999, "2020-W53", "2020-12"),
        (1609372800000, "2020-W53", "2020-12"),
        (1609372799999, "2020-W53", "2020-12"),
        (1609459200000, "2020-W53", "2021-01"),
        (1609459199999, "2020-W53", "2020-12"),
        (1609545600000, "2020-W53", "2021-01"),
        (1609545599999, "2020-W53", "2021-01"),
        (1609632000000, "2020-W53", "2021-01"),
        (1609631999999, "2020-W53", "2021-01"),
        (1609718400000, "2021-W01", "2021-01"),
        (1609718399999, "2020-W53", "2021-01"),
        (1640736000000, "2021-W52", "2021-12"),
        (1640735999999, "2021-W52", "2021-12"),
        (1640822400000, "2021-W52", "2021-12"),
        (1640822399999, "2021-W52", "2021-12"),
        (1640908800000, "2021-W52", "2021-12"),
        (1640908799999, "2021-W52", "2021-12"),
        (1640995200000, "2021-W52", "2022-01"),
        (1640995199999, "2021-W52", "2021-12"),
        (1641081600000, "2021-W52", "2022-01"),
        (1641081599999, "2021-W52", "2022-01"),
        (1641168000000, "2022-W01", "2022-01"),
        (1641167999999, "2021-W52", "2022-01"),
        (1641254400000, "2022-W01", "2022-01"),
        (1641254399999, "2022-W01", "2022-01"),
        (1735257600000, "2024-W52", "2024-12"),
        (1735257599999, "2024-W52", "2024-12"),
        (1735344000000, "2024-W52", "2024-12"),
        (1735343999999, "2024-W52", "2024-12"),
        (1735430400000, "2024-W52", "2024-12"),
        (1735430399999, "2024-W52", "2024-12"),
        (1735516800000, "2025-W01", "2024-12"),
        (1735516799999, "2024-W52", "2024-12"),
        (1735603200000, "2025-W01", "2024-12"),
        (1735603199999, "2025-W01", "2024-12"),
        (1735689600000, "2025-W01", "2025-01"),
        (1735689599999, "2025-W01", "2024-12"),
        (1735776000000, "2025-W01", "2025-01"),
        (1735775999999, "2025-W01", "2025-01"),
        (1766707200000, "2025-W52", "2025-12"),
        (1766707199999, "2025-W52", "2025-12"),
        (1766793600000, "2025-W52", "2025-12"),
        (1766793599999, "2025-W52", "2025-12"),
        (1766880000000, "2025-W52", "2025-12"),
        (1766879999999, "2025-W52", "2025-12"),
        (1766966400000, "2026-W01", "2025-12"),
        (1766966399999, "2025-W52", "2025-12"),
        (1767052800000, "2026-W01", "2025-12"),
        (1767052799999, "2026-W01", "2025-12"),
        (1767139200000, "2026-W01", "2025-12"),
        (1767139199999, "2026-W01", "2025-12"),
        (1767225600000, "2026-W01", "2026-01"),
        (1767225599999, "2026-W01", "2025-12"),
        (1798502400000, "2026-W53", "2026-12"),
        (1798502399999, "2026-W53", "2026-12"),
        (1798588800000, "2026-W53", "2026-12"),
        (1798588799999, "2026-W53", "2026-12"),
        (1798675200000, "2026-W53", "2026-12"),
        (1798675199999, "2026-W53", "2026-12"),
        (1798761600000, "2026-W53", "2027-01"),
        (1798761599999, "2026-W53", "2026-12"),
        (1798848000000, "2026-W53", "2027-01"),
        (1798847999999, "2026-W53", "2027-01"),
        (1798934400000, "2026-W53", "2027-01"),
        (1798934399999, "2026-W53", "2027-01"),
        (1799020800000, "2027-W01", "2027-01"),
        (1799020799999, "2026-W53", "2027-01"),
        (1830038400000, "2027-W52", "2027-12"),
        (1830038399999, "2027-W52", "2027-12"),
        (1830124800000, "2027-W52", "2027-12"),
        (1830124799999, "2027-W52", "2027-12"),
        (1830211200000, "2027-W52", "2027-12"),
        (1830211199999, "2027-W52", "2027-12"),
        (1830297600000, "2027-W52", "2028-01"),
        (1830297599999, "2027-W52", "2027-12"),
        (1830384000000, "2027-W52", "2028-01"),
        (1830383999999, "2027-W52", "2028-01"),
        (1830470400000, "2028-W01", "2028-01"),
        (1830470399999, "2027-W52", "2028-01"),
        (1830556800000, "2028-W01", "2028-01"),
        (1830556799999, "2028-W01", "2028-01"),
        (1924646400000, "2030-W52", "2030-12"),
        (1924646399999, "2030-W52", "2030-12"),
        (1924732800000, "2030-W52", "2030-12"),
        (1924732799999, "2030-W52", "2030-12"),
        (1924819200000, "2031-W01", "2030-12"),
        (1924819199999, "2030-W52", "2030-12"),
        (1924905600000, "2031-W01", "2030-12"),
        (1924905599999, "2031-W01", "2030-12"),
        (1924992000000, "2031-W01", "2031-01"),
        (1924991999999, "2031-W01", "2030-12"),
        (1925078400000, "2031-W01", "2031-01"),
        (1925078399999, "2031-W01", "2031-01"),
        (1925164800000, "2031-W01", "2031-01"),
        (1925164799999, "2031-W01", "2031-01"),
        (1760440800000, "2025-W42", "2025-10"),
        (1760440799999, "2025-W42", "2025-10"),
        (1760527200000, "2025-W42", "2025-10"),
        (1760527199999, "2025-W42", "2025-10"),
        (1760613600000, "2025-W42", "2025-10"),
        (1760613599999, "2025-W42", "2025-10"),
        (1760700000000, "2025-W42", "2025-10"),
        (1760699999999, "2025-W42", "2025-10"),
        (1760786400000, "2025-W42", "2025-10"),
        (1760786399999, "2025-W42", "2025-10"),
        (1760872800000, "2025-W42", "2025-10"),
        (1760872799999, "2025-W42", "2025-10"),
        (1760959200000, "2025-W43", "2025-10"),
        (1760959199999, "2025-W43", "2025-10"),
        (1703808000000, "2023-W52", "2023-12"),
        (1703807999999, "2023-W52", "2023-12"),
        (1703894400000, "2023-W52", "2023-12"),
        (1703894399999, "2023-W52", "2023-12"),
        (1703980800000, "2023-W52", "2023-12"),
        (1703980799999, "2023-W52", "2023-12"),
        (1704067200000, "2024-W01", "2024-01"),
        (1704067199999, "2023-W52", "2023-12"),
        (1704153600000, "2024-W01", "2024-01"),
        (1704153599999, "2024-W01", "2024-01"),
        (1704240000000, "2024-W01", "2024-01"),
        (1704239999999, "2024-W01", "2024-01"),
        (1704326400000, "2024-W01", "2024-01"),
        (1704326399999, "2024-W01", "2024-01"),
        (1262044800000, "2009-W53", "2009-12"),
        (1262044799999, "2009-W53", "2009-12"),
        (1262131200000, "2009-W53", "2009-12"),
        (1262131199999, "2009-W53", "2009-12"),
        (1262217600000, "2009-W53", "2009-12"),
        (1262217599999, "2009-W53", "2009-12"),
        (1262304000000, "2009-W53", "2010-01"),
        (1262303999999, "2009-W53", "2009-12"),
        (1262390400000, "2009-W53", "2010-01"),
        (1262390399999, "2009-W53", "2010-01"),
        (1262476800000, "2009-W53", "2010-01"),
        (1262476799999, "2009-W53", "2010-01"),
        (1262563200000, "2010-W01", "2010-01"),
        (1262563199999, "2009-W53", "2010-01"),
        (951523200000, "2000-W08", "2000-02"),
        (951523199999, "2000-W08", "2000-02"),
        (951609600000, "2000-W08", "2000-02"),
        (951609599999, "2000-W08", "2000-02"),
        (951696000000, "2000-W09", "2000-02"),
        (951695999999, "2000-W08", "2000-02"),
        (951782400000, "2000-W09", "2000-02"),
        (951782399999, "2000-W09", "2000-02"),
        (951868800000, "2000-W09", "2000-03"),
        (951868799999, "2000-W09", "2000-02"),
        (951955200000, "2000-W09", "2000-03"),
        (951955199999, "2000-W09", "2000-03"),
        (952041600000, "2000-W09", "2000-03"),
        (952041599999, "2000-W09", "2000-03"),
        (4102185600000, "2099-W53", "2099-12"),
        (4102185599999, "2099-W53", "2099-12"),
        (4102272000000, "2099-W53", "2099-12"),
        (4102271999999, "2099-W53", "2099-12"),
        (4102358400000, "2099-W53", "2099-12"),
        (4102358399999, "2099-W53", "2099-12"),
        (4102444800000, "2099-W53", "2100-01"),
        (4102444799999, "2099-W53", "2099-12"),
        (4102531200000, "2099-W53", "2100-01"),
        (4102531199999, "2099-W53", "2100-01"),
        (4102617600000, "2099-W53", "2100-01"),
        (4102617599999, "2099-W53", "2100-01"),
        (4102704000000, "2100-W01", "2100-01"),
        (4102703999999, "2099-W53", "2100-01"),
    ]

    func testMonthAndWeekKeysMatchTheJvm() {
        let repository = TripleShotFirebaseRepository()
        for (ms, week, month) in Self.dateKeys {
            XCTAssertEqual(repository.utcWeekKey(nowMs: ms), week, "utcWeekKey(\(ms))")
            XCTAssertEqual(repository.utcMonthKey(nowMs: ms), month, "utcMonthKey(\(ms))")
        }
    }

    // MARK: - Payloads

    func testPlayerMapIsAFreshNodeWithTheNickname() {
        let repository = TripleShotFirebaseRepository()
        let map = repository.playerMap(uid: "uidA", name: "Private Full Name")
        XCTAssertEqual(json(map),
                       "{\"bestKnowledgeStreak\":L(0),\"bestShootingStreak\":L(0),\"correctAnswers\":L(0),"
                       + "\"finished\":B(false),\"knowledgeStreak\":L(0),\"lastEvent\":S(),\"madeShots\":L(0),"
                       + "\"name\":S(Gaya),\"score\":L(0),\"shootingStreak\":L(0),\"shots\":L(0),\"uid\":S(uidA),"
                       + "\"updatedAt\":" + Self.timestamp + "}")
    }

    func testLiveStateMapOverridesTheStatsButNeverTheNameOrUid() {
        let repository = TripleShotFirebaseRepository()
        let state = LivePlayerState(uid: "someoneElse", name: "Private Full Name", score: 42, knowledgeStreak: 3,
                                    shootingStreak: 2, bestKnowledgeStreak: 5, bestShootingStreak: 4, correctAnswers: 9,
                                    madeShots: 7, shots: 11, lastEvent: "סיים", finished: true, updatedAt: 99)
        XCTAssertEqual(json(repository.liveStateMap(uid: "uidA", state: state)),
                       "{\"bestKnowledgeStreak\":L(5),\"bestShootingStreak\":L(4),\"correctAnswers\":L(9),"
                       + "\"finished\":B(true),\"knowledgeStreak\":L(3),\"lastEvent\":S(סיים),\"madeShots\":L(7),"
                       + "\"name\":S(Gaya),\"score\":L(42),\"shootingStreak\":L(2),\"shots\":L(11),\"uid\":S(uidA),"
                       + "\"updatedAt\":" + Self.timestamp + "}")
    }

    func testRoomCreationUpdatesAreTheAndroidMultiPathWrite() {
        let repository = TripleShotFirebaseRepository()
        let updates = repository.roomCreationUpdates(
            uid: "uidA",
            playerName: "Private Full Name",
            selectedCategories: KLinkedSet([QuestionCategory.MATH, .ENGLISH, .KIDS_ARITHMETIC, .MATH]),
            gameType: .HORSE,
            timeLimitSeconds: 60,
            seed: -3141592653589793238
        )
        XCTAssertEqual(updates.keys.sorted(), [
            "meta/categories", "meta/createdAt", "meta/gameType", "meta/hostUid", "meta/maxPlayers", "meta/seed",
            "meta/startedAt", "meta/status", "meta/timeLimitSeconds", "players/uidA"
        ])
        XCTAssertEqual(json(updates["meta/hostUid"]), "S(uidA)")
        XCTAssertEqual(json(updates["meta/status"]), "S(WAITING)")
        XCTAssertEqual(json(updates["meta/seed"]), "L(-3141592653589793238)")
        XCTAssertEqual(json(updates["meta/createdAt"]), Self.timestamp)
        XCTAssertEqual(json(updates["meta/startedAt"]), "L(0)")
        XCTAssertEqual(json(updates["meta/gameType"]), "S(HORSE)")
        // selectedCategories.map { it.name }.sorted(): alphabetical enum names (String.compareTo).
        XCTAssertEqual(json(updates["meta/categories"]), "[S(ENGLISH),S(KIDS_ARITHMETIC),S(MATH)]")
        XCTAssertEqual(json(updates["meta/timeLimitSeconds"]), "L(60)")
        XCTAssertEqual(json(updates["meta/maxPlayers"]), "L(4)")
        XCTAssertEqual(json(updates["players/uidA"]), json(repository.playerMap(uid: "uidA", name: "")))

        // timeLimitSeconds.coerceIn(10, 600)
        let short = repository.roomCreationUpdates(uid: "u", playerName: "", selectedCategories: KLinkedSet<QuestionCategory>(),
                                                   gameType: .SHOOTING_CHALLENGE, timeLimitSeconds: 5, seed: 1)
        XCTAssertEqual(json(short["meta/timeLimitSeconds"]), "L(10)")
        XCTAssertEqual(json(short["meta/categories"]), "[]")
        XCTAssertEqual(json(short["meta/gameType"]), "S(SHOOTING_CHALLENGE)")
        let long = repository.roomCreationUpdates(uid: "u", playerName: "", selectedCategories: KLinkedSet<QuestionCategory>(),
                                                  gameType: .SHOOTING_CHALLENGE, timeLimitSeconds: 900, seed: 1)
        XCTAssertEqual(json(long["meta/timeLimitSeconds"]), "L(600)")
    }

    func testStartRoomUpdatesPutTheHostFirstThenTheOthersByUid() {
        let players = ADataSnapshot(key: "players", value: [
            "uidC": ["uid": "uidC"], "host": ["uid": "host"], "uidA": ["uid": "uidA"], "Zed": ["uid": "Zed"]
        ])
        let horseMeta = RoomMeta(hostUid: "host", status: "WAITING", gameType: "HORSE")
        let updates = TripleShotFirebaseRepository.startRoomUpdates(playersSnapshot: players, meta: horseMeta)
        XCTAssertEqual(updates.keys.sorted(), ["horse", "meta/startedAt", "meta/status"])
        XCTAssertEqual(json(updates["meta/status"]), "S(PLAYING)")
        XCTAssertEqual(json(updates["meta/startedAt"]), Self.timestamp)
        guard let horse = updates["horse"] as? LiveHorseState else { return XCTFail("horse is a LiveHorseState") }
        // String natural order (UTF-16): upper case before lower case.
        XCTAssertEqual(horse.playerOrder, ["host", "Zed", "uidA", "uidC"])
        XCTAssertEqual(horse.phase, LiveHorseState.PHASE_SETTING)
        XCTAssertEqual(horse.setterUid, "host")
        XCTAssertEqual(horse.currentPlayerUid, "host")
        XCTAssertEqual(horse.penalties, ["host": 0, "Zed": 0, "uidA": 0, "uidC": 0])
        XCTAssertEqual(horse.turnNumber, 1)
        XCTAssertEqual(horse.updatedAt, 0)
        // Written as an object: the isFinished getter adds "finished".
        XCTAssertTrue(json(updates["horse"]).contains("\"finished\":B(false)"))

        let challengeMeta = RoomMeta(hostUid: "host", status: "WAITING", gameType: "SHOOTING_CHALLENGE")
        XCTAssertEqual(TripleShotFirebaseRepository.startRoomUpdates(playersSnapshot: players, meta: challengeMeta).keys.sorted(),
                       ["meta/startedAt", "meta/status"])
    }

    func testKnowledgeAnswerUpdatesWriteTwentyTwoOrTwentySevenPaths() {
        let wrong = TripleShotFirebaseRepository.knowledgeAnswerUpdates(
            uid: "u1", categoryKey: "MATH", monthKey: "2026-10", weekKey: "2026-W42", safeName: "Gaya",
            attemptKey: "-OAbC", correct: false, questionId: "q1", prompt: "2+2?", selectedAnswer: "5",
            correctAnswer: "4", qualityPercent: -5, gameType: "SHOOTING_CHALLENGE"
        )
        XCTAssertEqual(wrong.count, 22)
        XCTAssertEqual(wrong.keys.sorted(), [
            "communityKnowledge/allTime/MATH/total",
            "communityKnowledge/allTime/MATH/updatedAt",
            "communityKnowledge/monthly/2026-10/MATH/total",
            "communityKnowledge/monthly/2026-10/MATH/updatedAt",
            "users/u1/knowledge/allTime/MATH/total",
            "users/u1/knowledge/allTime/MATH/updatedAt",
            "users/u1/knowledge/monthly/2026-10/MATH/total",
            "users/u1/knowledge/monthly/2026-10/MATH/updatedAt",
            "users/u1/knowledge/weekly/2026-W42/MATH/total",
            "users/u1/knowledge/weekly/2026-W42/MATH/updatedAt",
            "users/u1/knowledgeAttempts/-OAbC/answeredAt",
            "users/u1/knowledgeAttempts/-OAbC/category",
            "users/u1/knowledgeAttempts/-OAbC/correct",
            "users/u1/knowledgeAttempts/-OAbC/correctAnswer",
            "users/u1/knowledgeAttempts/-OAbC/gameType",
            "users/u1/knowledgeAttempts/-OAbC/prompt",
            "users/u1/knowledgeAttempts/-OAbC/qualityPercent",
            "users/u1/knowledgeAttempts/-OAbC/questionId",
            "users/u1/knowledgeAttempts/-OAbC/selectedAnswer",
            "users/u1/profile/displayName",
            "users/u1/profile/uid",
            "users/u1/profile/updatedAt"
        ])
        XCTAssertEqual(json(wrong["users/u1/profile/uid"]), "S(u1)")
        XCTAssertEqual(json(wrong["users/u1/profile/displayName"]), "S(Gaya)")
        XCTAssertEqual(json(wrong["users/u1/profile/updatedAt"]), Self.timestamp)
        XCTAssertEqual(json(wrong["users/u1/knowledge/weekly/2026-W42/MATH/total"]), Self.increment)
        XCTAssertEqual(json(wrong["communityKnowledge/monthly/2026-10/MATH/updatedAt"]), Self.timestamp)
        XCTAssertEqual(json(wrong["users/u1/knowledgeAttempts/-OAbC/category"]), "S(MATH)")
        XCTAssertEqual(json(wrong["users/u1/knowledgeAttempts/-OAbC/qualityPercent"]), "L(0)")
        XCTAssertEqual(json(wrong["users/u1/knowledgeAttempts/-OAbC/correct"]), "B(false)")
        XCTAssertEqual(json(wrong["users/u1/knowledgeAttempts/-OAbC/gameType"]), "S(SHOOTING_CHALLENGE)")
        XCTAssertEqual(json(wrong["users/u1/knowledgeAttempts/-OAbC/answeredAt"]), Self.timestamp)

        let right = TripleShotFirebaseRepository.knowledgeAnswerUpdates(
            uid: "u1", categoryKey: "AI", monthKey: "2026-10", weekKey: "2026-W42", safeName: "Gaya",
            attemptKey: "-OAbD", correct: true, questionId: String(repeating: "q", count: 100),
            prompt: String(repeating: "p", count: 599) + "\u{1F600}", selectedAnswer: String(repeating: "s", count: 401),
            correctAnswer: String(repeating: "c", count: 400), qualityPercent: 150,
            gameType: String(repeating: "g", count: 33)
        )
        XCTAssertEqual(right.count, 27)
        for path in [
            "users/u1/knowledge/allTime/AI/correct",
            "users/u1/knowledge/monthly/2026-10/AI/correct",
            "users/u1/knowledge/weekly/2026-W42/AI/correct",
            "communityKnowledge/allTime/AI/correct",
            "communityKnowledge/monthly/2026-10/AI/correct"
        ] {
            XCTAssertEqual(json(right[path]), Self.increment, path)
        }
        XCTAssertNil(right["communityKnowledge/weekly/2026-W42/AI/correct"])   // no community weekly
        XCTAssertEqual(json(right["users/u1/knowledgeAttempts/-OAbD/qualityPercent"]), "L(100)")
        XCTAssertEqual(json(right["users/u1/knowledgeAttempts/-OAbD/correct"]), "B(true)")
        // take(96 / 600 / 400 / 400 / 32) in UTF-16 units; the split emoji goes out as '?' like on Android.
        XCTAssertEqual(right["users/u1/knowledgeAttempts/-OAbD/questionId"] as? String, String(repeating: "q", count: 96))
        XCTAssertEqual(right["users/u1/knowledgeAttempts/-OAbD/prompt"] as? String, String(repeating: "p", count: 599) + "?")
        XCTAssertEqual(right["users/u1/knowledgeAttempts/-OAbD/selectedAnswer"] as? String, String(repeating: "s", count: 400))
        XCTAssertEqual(right["users/u1/knowledgeAttempts/-OAbD/correctAnswer"] as? String, String(repeating: "c", count: 400))
        XCTAssertEqual(right["users/u1/knowledgeAttempts/-OAbD/gameType"] as? String, String(repeating: "g", count: 32))
    }

    /// (value, n, what Android's websocket sends for value.take(n)) on the JVM (`getBytes(UTF_8)` turns a lone high
    /// surrogate into '?').
    func testWireTakeMatchesTheJvm() {
        let vectors: [(String, Int, String)] = [
            ("ab\u{1F600}cd", 3, "ab?"),
            ("ab\u{1F600}cd", 4, "ab\u{1F600}"),
            ("ab\u{1F600}cd", 2, "ab"),
            ("\u{1F600}", 1, "?"),
            ("abc", 5, "abc"),
            ("\u{5E9}\u{5DC}\u{5D5}\u{5DD}", 2, "\u{5E9}\u{5DC}")
        ]
        for (value, n, expected) in vectors {
            XCTAssertEqual(TripleShotFirebaseRepository.wireTake(value, n), expected, "\(value).take(\(n))")
        }
    }

    func testLiveShotValueStampsTheShooterAndCapsTheSamples() {
        let samples = (0..<70).map { ShotReplaySample(tMs: Int64($0 * 55), x: Float($0), y: 1100.25, depth: 0) }
        let event = LiveShotEvent(id: "old", playerUid: "spoofed", playerName: "Private Full Name", shotSpotX: 402.75,
                                  shotSpotY: 1210.5, aimError: 0.12, powerError: -0.05, arcError: 0.02, rawPeakGyro: 9.4,
                                  rawReleasePitchDeg: 48, pullBack: 0.7, hotHand: true, releasedAt: 1760000009000,
                                  made: true, samples: samples)
        let value = TripleShotFirebaseRepository.liveShotValue(event: event, id: "-OAbC", uid: "uidA", safeName: "Gaya")
        XCTAssertEqual(value.id, "-OAbC")
        XCTAssertEqual(value.playerUid, "uidA")
        XCTAssertEqual(value.playerName, "Gaya")
        XCTAssertEqual(value.releasedAt, 1760000009000)
        XCTAssertEqual(value.samples, Array(samples.prefix(60)))
        var expected = event
        expected.id = "-OAbC"
        expected.playerUid = "uidA"
        expected.playerName = "Gaya"
        expected.samples = Array(samples.prefix(60))
        XCTAssertEqual(value, expected)

        var unset = event
        unset.releasedAt = 0
        let before = ASystem.currentTimeMillis()
        let stamped = TripleShotFirebaseRepository.liveShotValue(event: unset, id: "-OAbD", uid: "uidA", safeName: "Gaya")
        let after = ASystem.currentTimeMillis()
        XCTAssertTrue(stamped.releasedAt >= before && stamped.releasedAt <= after)
    }

    // MARK: - Reading

    func testKnowledgeDashboardParsesBucketsAndTheNewestAttempts() {
        let repository = TripleShotFirebaseRepository()
        let month = repository.utcMonthKey()
        let week = repository.utcWeekKey()
        var attempts: [String: Any] = [:]
        for i in 1...25 {
            let key = "-A" + (i < 10 ? "0" : "") + String(i)
            attempts[key] = ["answeredAt": Int64((i % 5) * 100)]
        }
        attempts["-A04"] = [
            "questionId": "q4", "category": "MATH", "prompt": "2+2?", "selectedAnswer": "4", "correctAnswer": "4",
            "qualityPercent": Int64(100), "correct": true, "gameType": "HORSE", "answeredAt": Int64(400)
        ]
        // Wrong JSON types read as the defaults (Android would throw in its listener; spec 05 8.2).
        attempts["-A09"] = ["prompt": Int64(5), "qualityPercent": "x", "correct": "yes", "answeredAt": Int64(400)]
        let user: [String: Any] = [
            "knowledge": [
                "allTime": [
                    "MATH": ["total": Int64(10), "correct": Int64(7), "updatedAt": Int64(1760000000000)],
                    "AI": ["total": Int64(4294967297), "correct": 2.9],
                    " ": ["total": Int64(3), "correct": Int64(3)],
                    "SCIENCE": ["correct": Int64(1)]
                ],
                "monthly": [
                    month: ["MATH": ["total": Int64(2), "correct": Int64(1)]],
                    "1999-01": ["AI": ["total": Int64(9), "correct": Int64(9)]]
                ],
                "weekly": [
                    week: ["ENGLISH": ["total": Int64(5)]],
                    "1999-W01": ["AI": ["total": Int64(9), "correct": Int64(9)]]
                ]
            ],
            "knowledgeAttempts": attempts
        ]
        // loadKnowledgeDashboard(attemptLimit = 5): coerceIn(20, 1000) keeps 20.
        let dashboard = repository.knowledgeDashboard(userSnap: ADataSnapshot(key: "u1", value: user), attemptLimit: 5)

        // Key order of the snapshot (Firebase child order); the blank key is dropped; Long -> Int truncates.
        XCTAssertEqual(dashboard.allTime.keys, ["AI", "MATH", "SCIENCE"])
        XCTAssertEqual(dashboard.allTime["AI"], TripleShotFirebaseRepository.KnowledgeBucket(total: 1, correct: 2))
        XCTAssertEqual(dashboard.allTime["MATH"], TripleShotFirebaseRepository.KnowledgeBucket(total: 10, correct: 7))
        XCTAssertEqual(dashboard.allTime["SCIENCE"], TripleShotFirebaseRepository.KnowledgeBucket(total: 0, correct: 1))
        XCTAssertEqual(dashboard.currentMonth.keys, ["MATH"])
        XCTAssertEqual(dashboard.currentMonth["MATH"], TripleShotFirebaseRepository.KnowledgeBucket(total: 2, correct: 1))
        XCTAssertEqual(dashboard.currentWeek.keys, ["ENGLISH"])
        XCTAssertEqual(dashboard.currentWeek["ENGLISH"], TripleShotFirebaseRepository.KnowledgeBucket(total: 5, correct: 0))

        // sortedByDescending { answeredAt } is stable: equal times keep the ascending push-key order.
        XCTAssertEqual(dashboard.attempts.map { $0.id }, [
            "-A04", "-A09", "-A14", "-A19", "-A24",
            "-A03", "-A08", "-A13", "-A18", "-A23",
            "-A02", "-A07", "-A12", "-A17", "-A22",
            "-A01", "-A06", "-A11", "-A16", "-A21"
        ])
        XCTAssertEqual(dashboard.attempts[0], TripleShotFirebaseRepository.KnowledgeAttemptRecord(
            id: "-A04", questionId: "q4", category: "MATH", prompt: "2+2?", selectedAnswer: "4", correctAnswer: "4",
            qualityPercent: 100, correct: true, gameType: "HORSE", answeredAt: 400))
        XCTAssertEqual(dashboard.attempts[1], TripleShotFirebaseRepository.KnowledgeAttemptRecord(id: "-A09", answeredAt: 400))
        XCTAssertEqual(dashboard.attempts[19], TripleShotFirebaseRepository.KnowledgeAttemptRecord(id: "-A21", answeredAt: 100))

        let empty = repository.knowledgeDashboard(userSnap: ADataSnapshot(key: "u1", value: nil), attemptLimit: 250)
        XCTAssertEqual(empty, TripleShotFirebaseRepository.KnowledgeDashboard())
    }

    func testScoreRankCountsStrictlyHigherScores() {
        let snap = ADataSnapshot(key: "leaderboard", value: [
            "a": ["bestScore": Int64(120)],
            "b": ["bestScore": Int64(100)],
            "c": ["bestScore": 150.7],
            "d": ["name": "no score"],
            "e": ["bestScore": Int64(101)]
        ])
        XCTAssertEqual(TripleShotFirebaseRepository.scoreRank(snap: snap, score: 100), 4)   // 120, 150, 101; ties share
        XCTAssertEqual(TripleShotFirebaseRepository.scoreRank(snap: snap, score: 150), 1)   // 150.7 reads as 150
        XCTAssertEqual(TripleShotFirebaseRepository.scoreRank(snap: snap, score: 0), 5)     // a missing score is 0
        XCTAssertEqual(TripleShotFirebaseRepository.scoreRank(snap: ADataSnapshot(key: "leaderboard", value: nil), score: 10), 1)
    }

    func testTopListsSortDescendingAndKeepTiesInQueryOrder() {
        let snap = ADataSnapshot(key: "leaderboard", value: [
            "u3": ["uid": "u3", "bestScore": Int64(50), "bestShootingStreak": Int64(9)],
            "u1": ["uid": "u1", "bestScore": Int64(80), "bestShootingStreak": Int64(2)],
            "u2": ["uid": "u2", "bestScore": Int64(50), "bestShootingStreak": Int64(9)],
            "u4": ["uid": "u4", "bestScore": "not a number"]
        ])
        XCTAssertEqual(TripleShotFirebaseRepository.topByScore(snap: snap).map { $0.uid }, ["u1", "u2", "u3"])
        XCTAssertEqual(TripleShotFirebaseRepository.topByShootingStreak(snap: snap).map { $0.uid }, ["u2", "u3", "u1"])
    }

    // MARK: - Transactions

    private struct LeaderboardCase {
        let old: LeaderboardEntry?
        let score: Int, bestShootingStreak: Int, bestKnowledgeStreak: Int, correctAnswers: Int, shots: Int, madeShots: Int
        let categories: [QuestionCategory]
        /// bestScore, bestShootingStreak, bestKnowledgeStreak, bestCorrectAnswers, bestRunCorrectAnswers, bestRunShots,
        /// bestRunMadeShots, bestRunKnowledgeAccuracyPercent, bestRunShootingPercent, bestRunCategories (JVM).
        let expected: (Int, Int, Int, Int, Int, Int, Int, Int, Int, [String])
    }

    private static let leaderboardCases: [LeaderboardCase] = [
        LeaderboardCase(old: nil, score: 120, bestShootingStreak: 4, bestKnowledgeStreak: 6, correctAnswers: 9, shots: 12,
                        madeShots: 7, categories: [.MATH, .ENGLISH, .AI],
                        expected: (120, 4, 6, 9, 9, 12, 7, 75, 58, ["AI", "ENGLISH", "MATH"])),
        LeaderboardCase(old: nil, score: 0, bestShootingStreak: 0, bestKnowledgeStreak: 0, correctAnswers: 0, shots: 0,
                        madeShots: 0, categories: [.SCIENCE],
                        expected: (0, 0, 0, 0, 0, 0, 0, 0, 0, ["SCIENCE"])),
        LeaderboardCase(old: LeaderboardEntry(uid: "u1", name: "Old", bestScore: 200, bestShootingStreak: 9, bestKnowledgeStreak: 3,
                                              bestCorrectAnswers: 11, bestRunCorrectAnswers: 11, bestRunShots: 20,
                                              bestRunMadeShots: 14, bestRunKnowledgeAccuracyPercent: 55,
                                              bestRunShootingPercent: 70, bestRunCategories: ["HISTORY"], updatedAt: 5),
                        score: 150, bestShootingStreak: 12, bestKnowledgeStreak: 2, correctAnswers: 13, shots: 19,
                        madeShots: 9, categories: [.MATH],
                        expected: (200, 12, 3, 13, 11, 20, 14, 55, 70, ["HISTORY"])),
        LeaderboardCase(old: LeaderboardEntry(uid: "u1", bestScore: 200, bestRunShots: 0, bestRunCategories: ["HISTORY"]),
                        score: 200, bestShootingStreak: 1, bestKnowledgeStreak: 1, correctAnswers: 7, shots: 9,
                        madeShots: 5, categories: [.PROGRAMMING, .AI],
                        expected: (200, 1, 1, 7, 7, 9, 5, 77, 55, ["AI", "PROGRAMMING"])),
        LeaderboardCase(old: LeaderboardEntry(uid: "u1", bestScore: 200, bestRunCorrectAnswers: 3, bestRunShots: 3,
                                              bestRunMadeShots: 3, bestRunKnowledgeAccuracyPercent: 100,
                                              bestRunShootingPercent: 100, bestRunCategories: ["HISTORY"]),
                        score: 200, bestShootingStreak: 15, bestKnowledgeStreak: 15, correctAnswers: 7, shots: 9,
                        madeShots: 5, categories: [.PROGRAMMING, .AI],
                        expected: (200, 15, 15, 7, 3, 3, 3, 100, 100, ["HISTORY"])),
        LeaderboardCase(old: LeaderboardEntry(uid: "u1", bestScore: 90, bestShootingStreak: 20, bestKnowledgeStreak: 20,
                                              bestCorrectAnswers: 30, bestRunShots: 10),
                        score: 342, bestShootingStreak: 3, bestKnowledgeStreak: 4, correctAnswers: 17, shots: 7,
                        madeShots: 6, categories: [.KIDS_ARITHMETIC, .MATRICULATION_MATH, .MATH, .GENERAL_KNOWLEDGE],
                        expected: (342, 20, 20, 30, 17, 7, 6, 100, 85,
                                   ["GENERAL_KNOWLEDGE", "KIDS_ARITHMETIC", "MATH", "MATRICULATION_MATH"])),
        LeaderboardCase(old: nil, score: 33, bestShootingStreak: 2, bestKnowledgeStreak: 2, correctAnswers: 3, shots: 0,
                        madeShots: 0, categories: [],
                        expected: (33, 2, 2, 3, 3, 0, 0, 0, 0, [])),
        LeaderboardCase(old: nil, score: 77, bestShootingStreak: 5, bestKnowledgeStreak: 5, correctAnswers: 9, shots: 3,
                        madeShots: 2, categories: [.PARADOX, .ASTRONOMY],
                        expected: (77, 5, 5, 9, 9, 3, 2, 100, 66, ["ASTRONOMY", "PARADOX"]))
    ]

    private func leaderboardHandler(
        _ repository: TripleShotFirebaseRepository,
        _ c: LeaderboardCase,
        _ callback: @escaping (Result<LeaderboardEntry, Error>) -> Void = { _ in }
    ) -> TripleShotFirebaseRepository.SaveLeaderboardBestHandler {
        return TripleShotFirebaseRepository.SaveLeaderboardBestHandler(
            repository: repository, uid: "u1", score: c.score, bestShootingStreak: c.bestShootingStreak,
            bestKnowledgeStreak: c.bestKnowledgeStreak, correctAnswers: c.correctAnswers, shots: c.shots,
            madeShots: c.madeShots, selectedCategories: KLinkedSet(c.categories), callback: callback
        )
    }

    func testLeaderboardTransactionMatchesTheJvm() {
        let repository = TripleShotFirebaseRepository()
        for (index, c) in Self.leaderboardCases.enumerated() {
            let data = AMutableData(value: nil)
            if let old = c.old {
                data.value = old
            }
            let before = ASystem.currentTimeMillis()
            let result = leaderboardHandler(repository, c).doTransaction(data)
            XCTAssertTrue(result.isSuccess, "case \(index)")
            XCTAssertNil(data.run.failure, "case \(index)")
            guard let entry = data.getValue(LeaderboardEntry.self) else {
                XCTFail("case \(index): an entry is written")
                continue
            }
            let e = c.expected
            XCTAssertEqual(entry.uid, "u1", "case \(index)")
            XCTAssertEqual(entry.name, "Gaya", "case \(index)")   // always the online nickname
            XCTAssertEqual(entry.bestScore, e.0, "case \(index)")
            XCTAssertEqual(entry.bestShootingStreak, e.1, "case \(index)")
            XCTAssertEqual(entry.bestKnowledgeStreak, e.2, "case \(index)")
            XCTAssertEqual(entry.bestCorrectAnswers, e.3, "case \(index)")
            XCTAssertEqual(entry.bestRunCorrectAnswers, e.4, "case \(index)")
            XCTAssertEqual(entry.bestRunShots, e.5, "case \(index)")
            XCTAssertEqual(entry.bestRunMadeShots, e.6, "case \(index)")
            XCTAssertEqual(entry.bestRunKnowledgeAccuracyPercent, e.7, "case \(index)")
            XCTAssertEqual(entry.bestRunShootingPercent, e.8, "case \(index)")
            XCTAssertEqual(entry.bestRunCategories, e.9, "case \(index)")
            XCTAssertTrue(entry.updatedAt >= before, "case \(index)")
        }
    }

    func testLeaderboardTransactionAbortsOnAMalformedEntry() {
        let repository = TripleShotFirebaseRepository()
        let data = AMutableData(value: ["uid": "u1", "bestScore": "not a number"])
        let result = leaderboardHandler(repository, Self.leaderboardCases[0]).doTransaction(data)
        // Android: getValue throws out of doTransaction; the transaction aborts with that error and writes nothing.
        XCTAssertFalse(result.isSuccess)
        XCTAssertNotNil(data.run.failure)
        XCTAssertEqual(json(data.value), "{\"bestScore\":S(not a number),\"uid\":S(u1)}")
    }

    func testLeaderboardTransactionCompletionAsAndroid() {
        let repository = TripleShotFirebaseRepository()
        var received: [Result<LeaderboardEntry, Error>] = []
        let handler = leaderboardHandler(repository, Self.leaderboardCases[0]) { received.append($0) }

        handler.onComplete(ADatabaseError.fromCode(ADatabaseError.PERMISSION_DENIED), false, nil)
        handler.onComplete(nil, false, nil)
        handler.onComplete(nil, true, nil)
        handler.onComplete(nil, true, ADataSnapshot(key: "u1", value: ["uid": "u1", "name": "Gaya", "bestScore": Int64(212)]))
        XCTAssertEqual(received.count, 4)
        guard received.count == 4 else { return }
        if case .failure(let error) = received[0] {
            XCTAssertEqual(message(error), "Firebase Database error: This client does not have permission to perform this operation")
        } else { XCTFail("permission denied fails") }
        if case .failure(let error) = received[1] {
            XCTAssertEqual(message(error), "Leaderboard transaction failed")
        } else { XCTFail("not committed fails") }
        if case .failure(let error) = received[2] {
            XCTAssertEqual(message(error), "Leaderboard result missing")
        } else { XCTFail("a missing result fails") }
        if case .success(let entry) = received[3] {
            XCTAssertEqual(entry, LeaderboardEntry(uid: "u1", name: "Gaya", bestScore: 212))
        } else { XCTFail("a committed entry succeeds") }
    }

    func testHorseChallengeTransactionAsAndroid() {
        let state = HorseGameEngine.Multiplayer.initialState(playerOrder: ["host", "uidB"], firstSetterUid: "host")
        var received: [Result<Void, Error>] = []
        let setter = TripleShotFirebaseRepository.ConfigureLiveHorseChallengeHandler(
            uid: "host", category: .MATH, spotId: "FREE_3", spotX: 402.75, spotY: 1210.5,
            callback: { received.append($0) }
        )
        let data = AMutableData(value: nil)
        data.value = state
        let before = ASystem.currentTimeMillis()
        XCTAssertTrue(setter.doTransaction(data).isSuccess)
        guard let updated = data.getValue(LiveHorseState.self) else { return XCTFail("the challenge is written") }
        XCTAssertEqual(updated.phase, LiveHorseState.PHASE_ATTEMPT)
        XCTAssertEqual(updated.challengeCategory, "MATH")
        XCTAssertEqual(updated.challengeSpotId, "FREE_3")
        XCTAssertEqual(updated.challengeSpotX, 402.75)
        XCTAssertEqual(updated.challengeSpotY, 1210.5)
        XCTAssertEqual(updated.turnNumber, 2)
        XCTAssertTrue(updated.updatedAt >= before)
        XCTAssertEqual((data.value as? [String: Any])?["finished"] as? Bool, false)

        // Not the setter: the engine's require fails and the transaction aborts without writing.
        let other = TripleShotFirebaseRepository.ConfigureLiveHorseChallengeHandler(
            uid: "uidB", category: .MATH, spotId: "FREE_3", spotX: 0, spotY: 0, callback: { _ in }
        )
        let untouched = AMutableData(value: nil)
        untouched.value = state
        XCTAssertFalse(other.doTransaction(untouched).isSuccess)
        XCTAssertEqual(untouched.getValue(LiveHorseState.self), state)
        // No cached horse node: abort (Android relies on the attached horse listener).
        XCTAssertFalse(setter.doTransaction(AMutableData(value: nil)).isSuccess)

        setter.onComplete(ADatabaseError.fromCode(ADatabaseError.DISCONNECTED), false, nil)
        setter.onComplete(nil, false, nil)
        setter.onComplete(nil, true, nil)
        XCTAssertEqual(received.count, 3)
        guard received.count == 3 else { return }
        if case .failure(let error) = received[0] {
            XCTAssertEqual(message(error), "Firebase Database error: The operation had to be aborted due to a network disconnect")
        } else { XCTFail("an error fails") }
        if case .failure(let error) = received[1] {
            XCTAssertEqual(message(error), "HORSE challenge was not accepted")
        } else { XCTFail("not committed fails") }
        if case .failure = received[2] { XCTFail("committed succeeds") }
    }

    func testHorseAttemptTransactionAsAndroid() {
        let initial = HorseGameEngine.Multiplayer.initialState(playerOrder: ["host", "uidB"], firstSetterUid: "host")
        let attempt = initial.copy(phase: LiveHorseState.PHASE_ATTEMPT, challengeCategory: "MATH", challengeSpotId: "FREE_3",
                                   turnNumber: 2)
        let room = AFirebaseDatabase.getInstance(TripleShotFirebaseRepository.DATABASE_URL).reference
            .child(TripleShotFirebaseRepository.ROOT_NODE).child("rooms").child("TESTXX")
        var received: [Result<LiveHorseState, Error>] = []
        let setter = TripleShotFirebaseRepository.ResolveLiveHorseAttemptHandler(
            room: room, uid: "host", answerCorrect: true, made: true, callback: { received.append($0) }
        )
        let data = AMutableData(value: nil)
        data.value = attempt
        XCTAssertTrue(setter.doTransaction(data).isSuccess)
        guard let established = data.getValue(LiveHorseState.self) else { return XCTFail("the attempt is written") }
        XCTAssertTrue(established.challengeEstablished)
        XCTAssertEqual(established.currentPlayerUid, "uidB")
        XCTAssertEqual(established.turnNumber, 3)
        XCTAssertTrue(established.updatedAt > 0)

        // Not this player's turn: abort.
        let wrongTurn = AMutableData(value: nil)
        wrongTurn.value = established
        XCTAssertFalse(setter.doTransaction(wrongTurn).isSuccess)

        setter.onComplete(ADatabaseError.fromCode(ADatabaseError.PERMISSION_DENIED), true, nil)
        setter.onComplete(nil, false, nil)
        setter.onComplete(nil, true, nil)
        // A committed, unfinished state (a finished one would also write meta/status, which tests never do).
        setter.onComplete(nil, true, ADataSnapshot(key: "horse", value: data.value))
        XCTAssertEqual(received.count, 4)
        guard received.count == 4 else { return }
        if case .failure(let error) = received[0] {
            XCTAssertEqual(message(error), "Firebase Database error: This client does not have permission to perform this operation")
        } else { XCTFail("an error fails") }
        if case .failure(let error) = received[1] {
            XCTAssertEqual(message(error), "HORSE attempt was not accepted")
        } else { XCTFail("not committed fails") }
        if case .failure(let error) = received[2] {
            XCTAssertEqual(message(error), "HORSE state missing")
        } else { XCTFail("a missing state fails") }
        if case .success(let state) = received[3] {
            XCTAssertEqual(state, established)
        } else { XCTFail("a committed state succeeds") }
    }

    // MARK: - TripleShotOnlineIdentity (prefs "tripleshot_online_identity")

    private static let defaultNicknames = ["Comet", "Sunny", "Bunny", "Spark", "Orbit"]

    func testNameKeepsAValidStoredNickname() {
        UserDefaults.standard.set("ניצוץ", forKey: "tripleshot_online_identity.nickname")
        XCTAssertEqual(TripleShotOnlineIdentity.name(c: AApplication.shared), "ניצוץ")
    }

    func testNameReplacesAnInvalidNicknameWithASavedEnglishDefault() {
        UserDefaults.standard.set("Alexander", forKey: "tripleshot_online_identity.nickname")
        let name = TripleShotOnlineIdentity.name(c: AApplication.shared)
        XCTAssertTrue(Self.defaultNicknames.contains(name), name)
        XCTAssertEqual(UserDefaults.standard.string(forKey: "tripleshot_online_identity.nickname"), name)
        XCTAssertNil(UserDefaults.standard.object(forKey: "tripleshot_online_identity.confirmed"))

        UserDefaults.standard.removeObject(forKey: "tripleshot_online_identity.nickname")
        let created = TripleShotOnlineIdentity.name(c: AApplication.shared)
        XCTAssertTrue(Self.defaultNicknames.contains(created), created)
        XCTAssertEqual(UserDefaults.standard.string(forKey: "tripleshot_online_identity.nickname"), created)
        XCTAssertEqual(TripleShotOnlineIdentity.name(c: AApplication.shared), created)   // persisted
    }

    func testChooseCallsReadyAtOnceWhenTheNicknameWasConfirmed() {
        UserDefaults.standard.set("Gaya", forKey: "tripleshot_online_identity.nickname")
        UserDefaults.standard.set(true, forKey: "tripleshot_online_identity.confirmed")
        var ready: [String] = []
        TripleShotOnlineIdentity.choose(c: AApplication.shared, always: false) { ready.append($0) }
        XCTAssertEqual(ready, ["Gaya"])   // synchronously, no dialog
    }

    func testOnlineNamesComeFromTheIdentityNotThePrivateName() {
        UserDefaults.standard.set("Kyra", forKey: "tripleshot_online_identity.nickname")
        let repository = TripleShotFirebaseRepository()
        XCTAssertEqual(repository.playerMap(uid: "u", name: "Private Full Name")["name"] as? String, "Kyra")
    }
}
