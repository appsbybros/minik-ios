import Foundation

/// App Store captures only. The "App Store screenshots" workflow (appstore/screenshots.json) launches a Simulator build
/// with `-MinikScreenshotScene home` or `-MinikScreenshotScene tripleshot.<scene>` and `-MinikScreenshotOrientation
/// portrait|landscape`. Normal launches never pass these arguments: `name` is nil, `preferences` is
/// UserDefaults.standard and every other entry point returns at once, so nothing here changes the game for players.
///
/// It plays the part of Android's debug-only TripleShotQaActivity (the source of the Play Store images): the production
/// activity, fragments, rules and controls, entered at a fixed seed with fixed characters, offline.
///
/// - Isolation: during a capture every SharedPreferences file (ASharedPreferences) lives in a separate defaults suite
///   that is emptied when the capture starts, so a capture starts from a fresh install's settings, stages only what it
///   needs there and never reads or writes the player's real saved data. Firebase stays unconfigured (AFirebaseApp).
/// - Staged settings: the name on Home, the chosen characters, game sounds off (Settings; the team-match whistle then
///   needs no audio device), and for the league scene a saved season, for the journey scene the reached stage.
/// - Taps: the scenes press the app's own buttons (performClick, the list row of the HORSE shot dialog) and, for the
///   HORSE aim, hold a real pull-back touch on the court, exactly like StoreReadyTest on Android.
enum TripleShotScreenshot {
    /// The seed of every captured match (Android's TripleShotQaActivity default).
    static let seed: Int64 = 31_337

    /// The defaults suite of a capture (never the app's own domain).
    private static let suiteName = "com.appsbybros.minik.swish.store-screenshots"

    /// The requested scene, e.g. "home" or "tripleshot.horse"; nil for a normal launch.
    static let name: String? = {
        guard let value = UserDefaults.standard.string(forKey: "MinikScreenshotScene")?
            .trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }()

    static var isActive: Bool { name != nil }

    static var wantsLandscape: Bool {
        UserDefaults.standard.string(forKey: "MinikScreenshotOrientation") == "landscape"
    }

    /// "home", or the part after "tripleshot." ("team", "oneOnOne", ...).
    private static var scene: String? {
        guard let name else { return nil }
        if name == "home" { return "home" }
        let prefix = "tripleshot."
        return name.hasPrefix(prefix) ? String(name.dropFirst(prefix.count)) : nil
    }

    /// Where ASharedPreferences stores its files: UserDefaults.standard, or during a capture the emptied capture suite.
    static let preferences: UserDefaults = {
        guard isActive, let capture = UserDefaults(suiteName: suiteName) else { return .standard }
        capture.removePersistentDomain(forName: suiteName)
        return capture
    }()

    // MARK: Staging (before Home reads its preferences)

    /// Called by TripleShotDemoActivity.onCreate before the navigator is added.
    static func prepare(activity: AActivity) {
        guard let scene else { return }
        let he = ["he", "iw"].contains(activity.resources.configuration.locales[0].language)
        _ = getSharedPreferences("triple_shot", MODE_PRIVATE).edit()
            .putString("player_name", he ? "שחקן" : "Player")
            .putString("player_character", TripleShotCharacterRoster.ID_WOMAN_DARK)
            .putString("bot_character", TripleShotCharacterRoster.ID_NOVA)
            .commit()
        let journey = getSharedPreferences("basketball_journey", 0).edit().putBoolean("sound", false).putInt("stageSchema", 2)
        if scene == "journey" { _ = journey.putInt("step", journeyStep) }
        _ = journey.commit()
        if scene == "league" {
            _ = getSharedPreferences("tripleshot_league_ui", 0).edit().putBoolean("qualities", false).commit()
            do { try stageLeagueSeason(he: he) } catch { ALog.w("TripleShotScreenshot", "league season not staged: \(error)") }
        }
    }

    /// Stage 14 of 23, "Three players, one ball" (a 3-player court).
    private static let journeyStep = 13

    /// A first season five games in, built like TripleShotLeagueStore.create (the page's default team name, the first
    /// three characters it offers, the house names it uses) but at the fixed seed. The five own results are staged; the
    /// other matches of each round come from TripleShotLeague.complete's own simulation.
    private static func stageLeagueSeason(he: Bool) throws {
        let available = TripleShotCharacterRoster.humanSelectable().filter { TripleShotCharacterVisualCatalog.hasVisuals(characterId: $0.id) }
        let roster = Array(available.prefix(3)).map { $0.id }
        let houseNames = he
            ? ["ברקי הזהב", "דרקוני הירח", "גלי הטורקיז", "כוכבי האש", "זאבי הלילה", "כנפי הקשת", "אריות השמש"]
            : ["Golden Bolts", "Moon Dragons", "Tidal Waves", "Fire Stars", "Night Wolves", "Rainbow Wings", "Sun Lions"]
        let color = TripleShotLeague.palette[1]
        func strength(_ ids: [String]) throws -> Int {
            var sum = 0.0
            for id in ids {
                guard let r = TripleShotCharacterRoster.find(id: id)?.ratings else {
                    throw TripleShotLeague.RuleError.nullPointer("Unknown character id \(id)")
                }
                sum += Double((r.inside + r.midRange + r.defense + r.speed) / 4)
            }
            return (sum / Double(ids.count)).toInt()
        }
        let choices = TripleShotCharacterRoster.botSelectable().filter { !roster.contains($0.id) && !$0.adaptiveBot }
        let squads = try TripleShotLeague.houseRosters(available: choices.map { $0.id }, size: roster.count, count: 7, seed: seed)
        let colors = TripleShotLeague.palette.filter { $0 != color }
        var teams = [TripleShotLeague.Team(id: 0, name: he ? "שביטי השמיים" : "Sky Comets", color: color, roster: roster,
                                           strength: try strength(roster))]
        for i in 0..<7 {
            teams.append(TripleShotLeague.Team(id: i + 1, name: houseNames[i], color: colors[i % colors.count],
                                               roster: squads[i], strength: try strength(squads[i])))
        }
        var season = try TripleShotLeague.Season(id: "store-screenshot-season", seed: seed, number: 1, createdAt: seed, teams: teams)
        for (own, rival) in [(11, 7), (11, 9), (8, 11), (11, 6), (11, 10)] {
            guard let next = season.next() else { break }
            season = try TripleShotLeague.complete(season: season, fixtureKey: next.key, ownScore: own, rivalScore: rival)
        }
        try TripleShotLeagueStore().save(s: season)
    }

    // MARK: Scenes (once Home is showing)

    /// Called at the end of TripleShotDemoActivity.onCreate.
    static func start(activity: AActivity) {
        guard let scene else { return }
        whenHomeReady(activity: activity) { host, home in
            run(scene: scene, activity: activity, host: host, home: home)
        }
    }

    private static func run(scene: String, activity: AActivity, host: TripleShotHostFragment, home: TripleShotHomeFragment) {
        let he = ["he", "iw"].contains(activity.resources.configuration.locales[0].language)
        let player = he ? "שחקן" : "Player"
        switch scene {
        case "roster":
            // Play vs bot: the image-first roster and mode setup.
            if let button: AView = home.view?.findViewById(R.id.botButton) { _ = button.performClick() }
        case "team":
            host.startGame(config: match(player: player, type: .TEAM_MATCH, human: TripleShotCharacterRoster.ID_WOMAN_DARK,
                                         teammates: [TripleShotCharacterRoster.ID_COACH_67, TripleShotCharacterRoster.ID_ZEPHYR],
                                         opponents: [TripleShotCharacterRoster.ID_NOVA, TripleShotCharacterRoster.ID_FLARE, TripleShotCharacterRoster.ID_KYRA],
                                         court: "sunset_pulse", categories: KLinkedSet()))
            holdLandscape(activity: activity)
            pressWhenShown(activity: activity, root: { activity.window.decorView },
                           text: activity.getString(R.string.minik_swish_team_intro_start), settle: 1500)
        case "oneOnOne":
            host.startGame(config: match(player: player, type: .ONE_ON_ONE, human: TripleShotCharacterRoster.ID_KYRA,
                                         teammates: [], opponents: [TripleShotCharacterRoster.ID_FLARE],
                                         court: "neon_falls", categories: KLinkedSet()))
            holdLandscape(activity: activity)
        case "horse":
            host.startGame(config: match(player: player, type: .HORSE, human: TripleShotCharacterRoster.ID_WOMAN_DARK,
                                         teammates: [], opponents: [TripleShotCharacterRoster.ID_NOVA],
                                         court: "sunset_pulse", categories: KLinkedSet([QuestionCategory.KIDS_ARITHMETIC]),
                                         landscape: false))
            horseAim(activity: activity, host: host)
        case "league":
            host.showLeague()
            showLeagueTable(activity: activity, host: host)
        case "journey":
            pressWhenShown(activity: activity, root: { activity.window.decorView },
                           text: activity.getString(R.string.daily_court_journey), settle: 300)
            // The journey brief, then its "Start challenge" button (the real court practice).
            pressWhenShown(activity: activity, root: { (AActivityHost.shared?.topActivity as? BasketballJourneyActivity)?.window.decorView },
                           text: he ? "מתחילים באתגר" : "Start challenge", settle: 600)
        default:
            break
        }
    }

    /// A local bot match as Play vs bot starts it (TripleShotHomeFragment.showBotMatchSetup), at the fixed seed.
    private static func match(player: String, type: GameType, human: String, teammates: [String], opponents: [String],
                              court: String, categories: KLinkedSet<QuestionCategory>, landscape: Bool? = nil) -> TripleShotGameConfig {
        let wide = landscape ?? wantsLandscape
        return TripleShotGameConfig(
            playerName: player, gameType: type, limitMode: .BALLS_ONLY, selectedCategories: categories, botMatch: true,
            playerCharacterId: human, botCharacterId: opponents.first ?? TripleShotCharacterRoster.ID_NOVA,
            teamSize: teammates.count + 1, teammateCharacterIds: teammates, opponentCharacterIds: opponents,
            gameOrientation: wide ? .LANDSCAPE : .PORTRAIT, courtId: court, seed: seed, ballLimit: Int(Int32.max),
            timeLimitSeconds: 0)
    }

    /// The device held in landscape (right): a team match follows the sensor and 1v1 accepts either landscape side,
    /// while the Simulator stands upright, so the capture turns the activity like Android's QA activity does.
    private static func holdLandscape(activity: AActivity) {
        guard wantsLandscape else { return }
        activity.requestedOrientation = AActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
    }

    // MARK: HORSE: the aiming arc

    /// Android StoreReadyTest.captureHorseAim: "Shot with aiming arc" in the shot dialog, "Ready to aim" on the free
    /// spot, the right answer to the real question, then a held pull-back on the court (the arc shows; never released).
    private static func horseAim(activity: AActivity, host: TripleShotHostFragment) {
        poll(activity: activity, until: { (activity.showingDialogs.last { $0.isShowing } as? AAlertDialog)?.listView != nil }) {
            guard let dialog = activity.showingDialogs.last(where: { $0.isShowing }) as? AAlertDialog else { return }
            _ = dialog.listView.performItemClick(0)
            pressWhenShown(activity: activity, root: { gameFragment(host)?.view },
                           text: activity.getString(R.string.minik_swish_horse_ready_to_aim), settle: 600) {
                poll(activity: activity, until: { horseAnswers(host) != nil }) {
                    guard let (game, answers) = horseAnswers(host), let question = game.horseQuestion else { return }
                    var correct = 0
                    for i in question.answers.indices where question.answers[i].qualityPercent > question.answers[correct].qualityPercent {
                        correct = i
                    }
                    _ = answers[correct].performClick()
                    after(activity: activity, 650) { holdPullBack(activity: activity, game: game) }
                }
            }
        }
    }

    private static func gameFragment(_ host: TripleShotHostFragment) -> TripleShotGameFragment? {
        host.childFragmentManager.findFragmentById(R.id.tripleShotChildContainer) as? TripleShotGameFragment
    }

    /// The four answer labels once the human's HORSE question is on screen.
    private static func horseAnswers(_ host: TripleShotHostFragment) -> (TripleShotGameFragment, [AView])? {
        guard let game = gameFragment(host), game.isAdded, game.horseQuestion != nil, let strip = game.answerStrip else { return nil }
        let labels = (0..<strip.childCount).compactMap { strip.getChildAt($0) as? OutlinedTextView }
        guard labels.count >= 4, labels.count == strip.childCount else { return nil }
        return (game, labels)
    }

    /// Touch down on open court (not on an answer station) and pull back 70% of the way, in steps, then hold.
    private static func holdPullBack(activity: AActivity, game: TripleShotGameFragment) {
        guard game.isAdded, let court = game.courtView, court.width > 0, court.height > 0 else { return }
        let w = Float(court.width), h = Float(court.height)
        let spots: [(Float, Float)] = [(0.53, 0.52), (0.5, 0.58), (0.47, 0.46), (0.36, 0.55), (0.64, 0.55)]
        guard let spot = spots.first(where: { court.findStationAt(x: w * $0.0, y: h * $0.1) == nil }) else { return }
        let x = w * spot.0, y = h * spot.1, pull = h * Float(0.19) * Float(0.70)
        let down = ASystemClock.uptimeMillis()
        _ = court.dispatchTouchEvent(AMotionEvent.obtain(down, down, AMotionEvent.ACTION_DOWN, x, y, 0))
        for step in 1...5 {
            after(activity: activity, Int64(step) * 80) {
                guard game.isAdded else { return }
                let now = ASystemClock.uptimeMillis()
                _ = court.dispatchTouchEvent(AMotionEvent.obtain(down, now, AMotionEvent.ACTION_MOVE, x, y + pull * Float(step) / 5, 0))
            }
        }
    }

    // MARK: League

    /// The saved season page scrolled to the next fixture and the league table.
    private static func showLeagueTable(activity: AActivity, host: TripleShotHostFragment) {
        let nextUp = ["Next up: ", "המשחק הבא: "]
        poll(activity: activity, until: { leagueView(host).map { find(in: $0) { v in nextUp.contains { v.text.hasPrefix($0) } } != nil } ?? false }) {
            after(activity: activity, 500) {
                guard let scroll = leagueView(host) as? AScrollView,
                      let title = find(in: scroll, where: { v in nextUp.contains { v.text.hasPrefix($0) } }),
                      let card = title.parentGroup else { return }
                var y = 0
                var v: AView? = card
                while let current = v, current !== scroll { y += current.top; v = current.parentGroup }
                let margin = (Float(12) * activity.resources.displayMetrics.density).toInt()
                scroll.scrollTo(0, max(0, y - margin))
            }
        }
    }

    private static func leagueView(_ host: TripleShotHostFragment) -> AView? {
        (host.childFragmentManager.findFragmentById(R.id.tripleShotChildContainer) as? TripleShotLeagueFragment)?.view
    }

    // MARK: Helpers

    /// Home is the navigator's resumed child and laid out, then a short settle (the menu's own entrance).
    private static func whenHomeReady(activity: AActivity, then block: @escaping (TripleShotHostFragment, TripleShotHomeFragment) -> Void) {
        func ready() -> (TripleShotHostFragment, TripleShotHomeFragment)? {
            guard activity.isResumedState,
                  let host = activity.supportFragmentManager.findFragmentById(R.id.tripleShotDemoContainer) as? TripleShotHostFragment,
                  let home = host.childFragmentManager.findFragmentById(R.id.tripleShotChildContainer) as? TripleShotHomeFragment,
                  home.isResumed, let view = home.view, view.width > 0 else { return nil }
            return (host, home)
        }
        poll(activity: activity, until: { ready() != nil }) {
            after(activity: activity, 900) {
                guard let (host, home) = ready() else { return }
                block(host, home)
            }
        }
    }

    /// Presses the shown, enabled button with this text under `root` once it appears (and `settle` ms later).
    private static func pressWhenShown(activity: AActivity, root: @escaping () -> AView?, text: String, settle: Int64,
                                       then next: (() -> Void)? = nil) {
        func button() -> ATextView? {
            guard let root = root() else { return nil }
            return find(in: root) { $0 is AButton && $0.isEnabled && $0.text == text }
        }
        poll(activity: activity, until: { button() != nil }) {
            after(activity: activity, settle) {
                guard let target = button() else { return }
                _ = target.performClick()
                next?()
            }
        }
    }

    /// The first shown text view under `root` that matches.
    private static func find(in root: AView, where match: (ATextView) -> Bool) -> ATextView? {
        guard root.isShown else { return nil }
        if let text = root as? ATextView, match(text) { return text }
        if let group = root as? AViewGroup {
            for i in 0..<group.childCount {
                if let child = group.getChildAt(i), let found = find(in: child, where: match) { return found }
            }
        }
        return nil
    }

    /// Checks `condition` every 100 ms (at most 20 s), then runs `block` once.
    private static func poll(activity: AActivity, attempt: Int = 0, until condition: @escaping () -> Bool,
                             then block: @escaping () -> Void) {
        if condition() { block(); return }
        if attempt >= 200 { ALog.w("TripleShotScreenshot", "\(name ?? "") did not become ready"); return }
        after(activity: activity, 100) { poll(activity: activity, attempt: attempt + 1, until: condition, then: block) }
    }

    private static func after(activity: AActivity, _ delay: Int64, _ block: @escaping () -> Void) {
        _ = activity.window.decorView.postDelayed(block, delay)
    }
}
