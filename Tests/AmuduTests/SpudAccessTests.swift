import XCTest
@testable import MinikAmudu

/// iOS payment model (CLAUDE.md): pins every limit of the free tier, the product, the texts and the absence of ads, so
/// a sync from Android that breaks the model fails the iOS Compile Check.
final class SpudAccessTests: XCTestCase {
    // MARK: Helpers

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Jerusalem") ?? TimeZone(secondsFromGMT: 7200) ?? .current
        return c
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = day
        parts.hour = hour
        parts.minute = minute
        return calendar.date(from: parts) ?? Date(timeIntervalSince1970: 0)
    }

    private func freshDefaults(_ name: String = #function) -> UserDefaults {
        let suite = "SpudAccessTests." + name
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    /// The repository root, from this file's path (the simulator reads the Mac's file system).
    private func repoRoot(file: StaticString = #filePath) -> URL {
        return URL(fileURLWithPath: "\(file)").deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    // MARK: Product

    func testProductIdentifier() {
        XCTAssertEqual(SpudAccess.productIdentifier, "com.appsbybros.minik.spud.full_game")
        XCTAssertEqual(SpudAccess.productInfoKey, "SpudFullGameProductIdentifier")
        let configuration = SpudStoreConfiguration(productIdentifier: " com.appsbybros.minik.spud.full_game ")
        XCTAssertEqual(configuration.productIdentifier, SpudAccess.productIdentifier)
        XCTAssertNotNil(configuration.catalog)
        XCTAssertNil(SpudStoreConfiguration(productIdentifier: "").catalog)
        XCTAssertNil(SpudStoreConfiguration(productIdentifier: "$(SPUD_FULL_GAME_PRODUCT_IDENTIFIER)").catalog)
        // The app's Info.plist names the product (when the tests run inside the app).
        if Bundle.main.bundleIdentifier == "com.appsbybros.minik.spud" {
            XCTAssertEqual(SpudStoreConfiguration.load().productIdentifier, SpudAccess.productIdentifier)
        }
    }

    func testProjectNamesTheProductForMinikAmudu() throws {
        let yml = try String(contentsOf: repoRoot().appendingPathComponent("project.yml"), encoding: .utf8)
        let block = try XCTUnwrap(targetBlock("MinikAmudu", in: yml))
        XCTAssertTrue(block.contains("SpudFullGameProductIdentifier: $(SPUD_FULL_GAME_PRODUCT_IDENTIFIER)"))
        XCTAssertTrue(block.contains("SPUD_FULL_GAME_PRODUCT_IDENTIFIER: com.appsbybros.minik.spud.full_game"))
        XCTAssertTrue(block.contains("package: AppStoreCommerceKit"))
    }

    // MARK: Players, arenas, balls

    func testThreePlayersWithoutTheFullGame() {
        XCTAssertEqual(SpudAccess.freePlayers, 3)
        for n in 2...3 { XCTAssertFalse(SpudAccess.playersLocked(n, owner: false), "\(n)") }
        for n in 4...10 {
            XCTAssertTrue(SpudAccess.playersLocked(n, owner: false), "\(n)")
            XCTAssertFalse(SpudAccess.playersLocked(n, owner: true), "\(n)")
        }
    }

    func testOnlySunshineParkIsFree() {
        XCTAssertEqual(SpudAccess.freeScenes, [.park])
        XCTAssertFalse(SpudAccess.sceneLocked(.park, owner: false))
        XCTAssertTrue(SpudAccess.sceneLocked(.beach, owner: false))
        XCTAssertTrue(SpudAccess.sceneLocked(.andromeda, owner: false))
        for scene in ArenaScene.allCases { XCTAssertFalse(SpudAccess.sceneLocked(scene, owner: true)) }
        // Lessons: the space conditions are Andromeda.
        XCTAssertTrue(SpudAccess.conditionsLocked(.space, owner: false))
        XCTAssertFalse(SpudAccess.conditionsLocked(.space, owner: true))
        for c in PracticeConditions.allCases where c != .space { XCTAssertFalse(SpudAccess.conditionsLocked(c, owner: false), c.rawValue) }
    }

    func testOnlySoftFoamIsFreeAndThePaintBalloonIsMetered() {
        // Bug report 2026-11-22 (2.3): the Beach ball needs the full game too.
        XCTAssertEqual(SpudAccess.freeBalls, [.foam])
        XCTAssertFalse(SpudAccess.ballLocked(.foam, owner: false))
        XCTAssertTrue(SpudAccess.ballLocked(.beach, owner: false))
        XCTAssertTrue(SpudAccess.ballLocked(.neon, owner: false))
        XCTAssertTrue(SpudAccess.ballLocked(.tennis, owner: false))
        XCTAssertFalse(SpudAccess.ballLocked(.paint, owner: false))
        for kind in BallKind.allCases { XCTAssertFalse(SpudAccess.ballLocked(kind, owner: true)) }
    }

    // MARK: Characters (bug report 2026-11-22, 2.3)

    func testFlareKyraGayaAndMiaNeedTheFullGame() {
        XCTAssertEqual(Set(SpudAccess.lockedCharacters), ["flare", "kyra", "gaya", "mia"])
        for c in AmuduCharacters.all {
            let locked = ["flare", "kyra", "gaya", "mia"].contains(c.id)
            XCTAssertEqual(SpudAccess.characterLocked(c.id, owner: false), locked, c.id)
            XCTAssertFalse(SpudAccess.characterLocked(c.id, owner: true), c.id + ": everything unlocks after the purchase")
            XCTAssertEqual(SpudAccess.avatar(c.id, owner: true), c.id)
            XCTAssertEqual(SpudAccess.avatar(c.id, owner: false), locked ? "miniko" : c.id)
        }
        XCTAssertFalse(SpudAccess.characterLocked(SpudAccess.freeAvatar, owner: false))
        // Locked house players never join a free game, whatever was saved; owners keep them all.
        let saved = SpudAccess.Choices(players: 3, scene: .park, ball: .foam, house: ["kyra", "june", "mia", "comet"])
        XCTAssertEqual(SpudAccess.clamp(saved, owner: false).house, ["june", "comet"])
        XCTAssertEqual(SpudAccess.clamp(saved, owner: true).house, ["kyra", "june", "mia", "comet"])
    }

    func testEverythingUnlocksForAnOwner() {
        for n in 2...SpudAccess.fullPlayers { XCTAssertFalse(SpudAccess.playersLocked(n, owner: true)) }
        for s in ArenaScene.allCases { XCTAssertFalse(SpudAccess.sceneLocked(s, owner: true)) }
        for b in BallKind.allCases { XCTAssertFalse(SpudAccess.ballLocked(b, owner: true)) }
        for c in AmuduCharacters.all { XCTAssertFalse(SpudAccess.characterLocked(c.id, owner: true)) }
        for step in 0..<(SpudJourney.size * 3) { XCTAssertFalse(SpudAccess.challengeLocked(step, owner: true)) }
        for c in PracticeConditions.allCases { XCTAssertFalse(SpudAccess.conditionsLocked(c, owner: true)) }
    }

    // MARK: Paint balloon

    func testPaintBalloonThreeWelcomeGamesThenOneADay() throws {
        var a = PaintBalloonAllowance()
        let day1 = date(2026, 11, 19, 9)
        XCTAssertEqual(SpudAccess.welcomePaintGames, 3)
        XCTAssertEqual(a.gamesLeft(now: day1, calendar: calendar), 3)
        for left in [2, 1, 0] {
            a = try XCTUnwrap(a.consuming(now: day1, calendar: calendar))
            XCTAssertEqual(a.gamesLeft(now: day1, calendar: calendar), left)
        }
        // The day the last welcome game is used counts as that day's game.
        XCTAssertNil(a.consuming(now: date(2026, 11, 19, 23, 59), calendar: calendar))
        // Then exactly one a day.
        let day2 = date(2026, 11, 20, 0, 5)
        XCTAssertEqual(a.gamesLeft(now: day2, calendar: calendar), 1)
        a = try XCTUnwrap(a.consuming(now: day2, calendar: calendar))
        XCTAssertEqual(a.gamesLeft(now: day2, calendar: calendar), 0)
        XCTAssertNil(a.consuming(now: date(2026, 11, 20, 18), calendar: calendar))
    }

    func testPaintBalloonDaysDoNotAccumulate() throws {
        var a = PaintBalloonAllowance(welcomeUsed: 3, lastFreeDay: "2026-11-01")
        let later = date(2026, 11, 19, 10)
        XCTAssertEqual(a.gamesLeft(now: later, calendar: calendar), 1)
        a = try XCTUnwrap(a.consuming(now: later, calendar: calendar))
        XCTAssertEqual(a.gamesLeft(now: later, calendar: calendar), 0)
        XCTAssertNil(a.consuming(now: date(2026, 11, 19, 22), calendar: calendar))
    }

    func testPaintBalloonNewLocalDayResets() throws {
        // 23:30 in Jerusalem is still 21:30 UTC of the same date; 00:10 the next local day is a new day.
        var a = PaintBalloonAllowance(welcomeUsed: 3, lastFreeDay: nil)
        a = try XCTUnwrap(a.consuming(now: date(2026, 11, 19, 23, 30), calendar: calendar))
        XCTAssertEqual(a.lastFreeDay, "2026-11-19")
        XCTAssertEqual(a.gamesLeft(now: date(2026, 11, 19, 23, 59), calendar: calendar), 0)
        XCTAssertEqual(a.gamesLeft(now: date(2026, 11, 20, 0, 10), calendar: calendar), 1)
        XCTAssertEqual(PaintBalloonAllowance.day(date(2026, 1, 5, 8), calendar: calendar), "2026-01-05")
    }

    func testPaintBalloonAllowancePersists() {
        let defaults = freshDefaults()
        let repository = PaintBalloonAllowanceRepository(defaults: defaults)
        XCTAssertEqual(repository.load(), PaintBalloonAllowance())
        repository.save(PaintBalloonAllowance(welcomeUsed: 3, lastFreeDay: "2026-11-19"))
        XCTAssertEqual(repository.load(), PaintBalloonAllowance(welcomeUsed: 3, lastFreeDay: "2026-11-19"))
        XCTAssertEqual(defaults.integer(forKey: PaintBalloonAllowanceRepository.welcomeKey), 3)
        XCTAssertEqual(defaults.string(forKey: PaintBalloonAllowanceRepository.dayKey), "2026-11-19")
    }

    @MainActor
    func testStoreCountsPaintGamesPerGameAndOwnersAreUnlimited() {
        let defaults = freshDefaults()
        var now = date(2026, 11, 19, 10)
        let store = SpudStore(configuration: SpudStoreConfiguration(productIdentifier: nil), store: nil,
                              repository: SpudEntitlementRepository(defaults: defaults),
                              paintRepository: PaintBalloonAllowanceRepository(defaults: defaults),
                              clock: { now }, calendar: calendar, isStoreScreenshotCapture: false)
        XCTAssertFalse(store.fullGame)
        XCTAssertEqual(store.paintGamesLeft, 3)
        XCTAssertTrue(store.usePaintGame())
        XCTAssertTrue(store.usePaintGame())
        XCTAssertTrue(store.usePaintGame())
        XCTAssertFalse(store.usePaintGame())
        XCTAssertEqual(store.paintGamesLeft, 0)
        now = date(2026, 11, 20, 8)
        XCTAssertEqual(store.paintGamesLeft, 1)
        XCTAssertTrue(store.usePaintGame())
        XCTAssertFalse(store.usePaintGame())
        XCTAssertEqual(PaintBalloonAllowanceRepository(defaults: defaults).load().lastFreeDay, "2026-11-20")

        defaults.set(true, forKey: SpudEntitlementRepository.key)
        let owner = SpudStore(configuration: SpudStoreConfiguration(productIdentifier: nil), store: nil,
                              repository: SpudEntitlementRepository(defaults: defaults),
                              paintRepository: PaintBalloonAllowanceRepository(defaults: defaults),
                              clock: { now }, calendar: calendar, isStoreScreenshotCapture: false)
        XCTAssertTrue(owner.fullGame)
        for _ in 0..<20 { XCTAssertTrue(owner.usePaintGame()) }
        XCTAssertEqual(owner.paintGamesLeft, Int.max)
        XCTAssertEqual(owner.paint, PaintBalloonAllowance(welcomeUsed: 3, lastFreeDay: "2026-11-20"))
    }

    // MARK: Daily challenges

    func testFirstSevenChallengesAreFree() {
        XCTAssertEqual(SpudAccess.freeChallenges, 7)
        for step in 0..<7 {
            XCTAssertFalse(SpudAccess.challengeLocked(step, owner: false), "\(step)")
            // The free challenges are playable in the free arena.
            XCTAssertFalse(SpudAccess.conditionsLocked(PracticeCurriculum.conditions(step), owner: false), "\(step)")
        }
        for step in [7, 8, 20, SpudJourney.size - 1, SpudJourney.size, SpudJourney.size * 2 + 3] {
            XCTAssertTrue(SpudAccess.challengeLocked(step, owner: false), "\(step)")
            XCTAssertFalse(SpudAccess.challengeLocked(step, owner: true), "\(step)")
        }
    }

    // MARK: Online

    func testOnlyAHostWithoutTheFullGameIsLimited() {
        XCTAssertTrue(SpudAccess.limitsRoom(owner: false, hosting: true))
        XCTAssertFalse(SpudAccess.limitsRoom(owner: false, hosting: false), "a joiner is never limited")
        XCTAssertFalse(SpudAccess.limitsRoom(owner: true, hosting: false))
        XCTAssertFalse(SpudAccess.limitsRoom(owner: true, hosting: true))
    }

    // MARK: Old saved settings

    func testOldSavedSettingsAreClampedAtTheStart() {
        let saved = SpudAccess.Choices(players: 6, scene: .andromeda, ball: .neon, house: ["mia", "kyra", "gaya", "flare", "june"])
        let free = SpudAccess.clamp(saved, owner: false)
        XCTAssertEqual(free, SpudAccess.Choices(players: 3, scene: .park, ball: .foam, house: ["june"]))
        XCTAssertEqual(SpudAccess.clamp(saved, owner: true), saved, "owners keep their settings")
        // Free values pass unchanged; the paint balloon stays (it is metered when the game starts).
        let small = SpudAccess.Choices(players: 2, scene: .park, ball: .paint, house: ["amber", "comet"])
        XCTAssertEqual(SpudAccess.clamp(small, owner: false), SpudAccess.Choices(players: 2, scene: .park, ball: .paint, house: ["amber"]))
        XCTAssertEqual(SpudAccess.clamp(SpudAccess.Choices(players: 10, scene: .beach, ball: .tennis), owner: false).players, 3)
        // Challenges and lessons.
        XCTAssertEqual(SpudAccess.practiceBall(.neon, allowed: BallKind.allCases, owner: false), .foam)
        XCTAssertEqual(SpudAccess.practiceBall(.tennis, allowed: [.tennis, .beach], owner: false), .foam)
        XCTAssertEqual(SpudAccess.practiceBall(.beach, allowed: [.beach, .foam], owner: false), .foam)
        XCTAssertEqual(SpudAccess.practiceBall(.neon, allowed: BallKind.allCases, owner: true), .neon)
        XCTAssertEqual(SpudAccess.practiceBall(.paint, allowed: [.paint], owner: false), .paint)
        XCTAssertEqual(SpudAccess.practiceConditions(.space, owner: false), .calm)
        XCTAssertEqual(SpudAccess.practiceConditions(.windNight, owner: false), .windNight)
        XCTAssertEqual(SpudAccess.practiceConditions(.space, owner: true), .space)
    }

    // MARK: Texts

    func testEveryStoreTextIsInTheSixLanguages() {
        XCTAssertEqual(StoreText.languages, ["en", "he", "es", "ar", "hi", "nl"])
        for key in StoreText.Key.allCases {
            let values = StoreText.table[key] ?? []
            XCTAssertEqual(values.count, 6, key.rawValue)
            XCTAssertEqual(Set(values.map { $0.isEmpty }), [false], key.rawValue)
            for language in StoreText.languages where language != "en" && key != .thanksTitle {
                XCTAssertNotEqual(StoreText.get(key, language: language), StoreText.get(key, language: "en"), key.rawValue + " " + language)
            }
        }
        XCTAssertEqual(StoreText.get(.title, language: "he"), "פתיחת המשחק המלא")
        XCTAssertEqual(StoreText.get(.title, language: "fr"), "Unlock the full game", "other languages read English, as AppText")
        XCTAssertTrue(StoreText.buy(price: "$4.99", language: "en").hasPrefix("Unlock the full game · "))
        XCTAssertTrue(StoreText.buy(price: "$4.99", language: "en").contains("$4.99"))
        // The iOS-only texts stay out of the catalog generated from Android.
        let catalog = Set(AppText.keys())
        // "Try again" (bug report 2026-11-22, 2.2) is also an Android catalog row; its iOS translations are the store's own.
        for key in StoreText.Key.allCases where key != .reload {
            XCTAssertFalse(catalog.contains(StoreText.get(key, language: "en")), key.rawValue)
        }
    }

    func testPaintGamesLeftUsesEachLanguagesPlural() {
        XCTAssertEqual(StoreText.paintGamesLeft(1, language: "en"), "1 free paint balloon game left")
        XCTAssertEqual(StoreText.paintGamesLeft(3, language: "en"), "3 free paint balloon games left")
        XCTAssertEqual(StoreText.paintGamesLeft(1, language: "he"), "נשאר משחק חינם אחד עם בלון צבע")
        XCTAssertEqual(StoreText.paintGamesLeft(2, language: "he"), "נשארו 2 משחקי חינם עם בלון צבע")
        XCTAssertEqual(StoreText.paintGamesLeft(1, language: "es"), "Te queda 1 partida gratis con globo de pintura")
        XCTAssertEqual(StoreText.paintGamesLeft(3, language: "es"), "Te quedan 3 partidas gratis con globo de pintura")
        XCTAssertEqual(StoreText.plural(1, language: "ar"), .one)
        XCTAssertEqual(StoreText.plural(2, language: "ar"), .two)
        XCTAssertEqual(StoreText.plural(3, language: "ar"), .few)
        XCTAssertEqual(StoreText.plural(11, language: "ar"), .many)
        XCTAssertEqual(StoreText.plural(100, language: "ar"), .other)
        XCTAssertEqual(StoreText.paintGamesLeft(2, language: "ar"), "تبقّت لعبتان مجانيتان ببالون الألوان")
        XCTAssertEqual(StoreText.paintGamesLeft(3, language: "ar"), "تبقّت 3 ألعاب مجانية ببالون الألوان")
        XCTAssertEqual(StoreText.paintGamesLeft(1, language: "hi"), "रंग के गुब्बारे वाला 1 मुफ़्त गेम बाकी है")
        XCTAssertEqual(StoreText.paintGamesLeft(3, language: "hi"), "रंग के गुब्बारे वाले 3 मुफ़्त गेम बाकी हैं")
        XCTAssertEqual(StoreText.paintGamesLeft(1, language: "nl"), "Nog 1 gratis spel met de verfballon")
        XCTAssertEqual(StoreText.paintGamesLeft(2, language: "nl"), "Nog 2 gratis spellen met de verfballon")
        for language in StoreText.languages {
            for n in 1...3 {
                let text = StoreText.paintGamesLeft(n, language: language)
                XCTAssertFalse(text.isEmpty || text.contains("{0}"), language + " \(n)")
            }
            XCTAssertNotNil(StoreText.paintForms(language)[.one], language)
            XCTAssertNotNil(StoreText.paintForms(language)[.other], language)
            XCTAssertEqual(StoreText.paintLine(gamesLeft: 0, language: language), StoreText.get(.paintTomorrow, language: language))
        }
    }

    // MARK: No ads on iOS

    func testNoAdSDKInTheGame() throws {
        let root = repoRoot()
        let amudu = root.appendingPathComponent("Amudu")
        let texts: Set<String> = ["swift", "json", "strings", "plist", "xcprivacy", "html", "txt", "md"]
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: amudu, includingPropertiesForKeys: nil))
        var checked = 0
        for case let url as URL in enumerator where texts.contains(url.pathExtension.lowercased()) {
            let data = try Data(contentsOf: url)
            let text = (String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) ?? "").lowercased()
            checked += 1
            for banned in ["googlemobileads", "admob", "gadmobileads", "gadapplicationidentifier"] {
                XCTAssertFalse(text.contains(banned), url.lastPathComponent + " mentions " + banned)
            }
        }
        XCTAssertGreaterThan(checked, 40, "the Amudu sources were found at " + amudu.path)

        let yml = try String(contentsOf: root.appendingPathComponent("project.yml"), encoding: .utf8)
        let block = try XCTUnwrap(targetBlock("MinikAmudu", in: yml))
        XCTAssertFalse(block.contains("package: GoogleMobileAds"))
        XCTAssertFalse(block.contains("GADApplicationIdentifier"))
        XCTAssertFalse(block.contains("MinikAdSupportedApplication"))
        XCTAssertFalse(block.contains("product: GoogleMobileAds"))
    }

    /// The lines of one target in project.yml's `targets:` section, up to the next target.
    private func targetBlock(_ name: String, in yml: String) -> String? {
        let lines = yml.components(separatedBy: "\n").map { $0.replacingOccurrences(of: "\r", with: "") }
        guard let targets = lines.firstIndex(of: "targets:"),
              let start = lines[targets...].firstIndex(of: "  " + name + ":") else { return nil }
        var block: [String] = []
        for line in lines[(start + 1)...] {
            let isNextTarget = line.hasPrefix("  ") && !line.hasPrefix("   ") && line.hasSuffix(":") && !line.hasPrefix("  #")
            let isNextSection = !line.isEmpty && !line.hasPrefix(" ") && !line.hasPrefix("#")
            if isNextTarget || isNextSection { break }
            block.append(line)
        }
        return block.joined(separator: "\n")
    }
}
