import XCTest
@testable import MinikTripleShot

/// Parity tests for spec 19 (ui/TripleShotBotMatchSetupDialog.kt, ui/TripleShotCharacterPickerDialog.kt, dd722e5).
///
/// Golden vectors come from the JVM: the state statements of `TripleShotBotMatchSetupDialog.show` (its local `var`s,
/// isAuthoredReady, teamSelectionPool, assignUniqueRoster, randomizeTeams, ensureSlots, selectedIdsExcept, the
/// CharacterSection callbacks, the mode / size / court listeners, refreshModes -> rebuildSlotCards + refreshPresentation,
/// the popup choice list and the Start checks) copied verbatim into a Kotlin harness and run on the real
/// model/TripleShotCharacters.kt, with `pool.shuffled()` given `Random(seed)` so KotlinRandom can follow it draw for draw
/// (scratchpad swish/work/s-dialogs/harness/src/harness/RosterGolden.kt). The OVR vectors are spec 19 section 7
/// (TripleShotLiveSetupFragment.overall over the roster ratings both dialogs display).
final class DialogsTests: XCTestCase {
    private typealias SetupState = TripleShotBotMatchSetupDialog.SetupState

    // MARK: Helpers (the harness's output format)

    private func ids(_ list: [TripleShotCharacterProfile]) -> String {
        return "[" + list.map { $0.id }.joined(separator: " ") + "]"
    }

    private func describe(_ s: SetupState) -> String {
        return s.selectedMode.name + " size=" + String(s.selectedTeamSize) + " court=" + s.selectedCourtId
            + " human=" + s.selectedHuman.id + " bot=" + s.selectedPrimaryBot.id
            + " mates=" + ids(s.selectedTeammates) + " opps=" + ids(s.selectedOpponents)
    }

    private func start(_ s: SetupState) -> String {
        guard let selection = s.startSelection() else { return "TOAST" }
        return "Selection(" + selection.gameType.name + "," + String(selection.teamSize) + "," + selection.human.id + ","
            + ids(selection.teammates) + "," + ids(selection.opponents) + "," + selection.courtId + ")"
    }

    private func profile(_ id: String) -> TripleShotCharacterProfile {
        return TripleShotCharacterRoster.find(id: id)!
    }

    private func makeState(
        currentHumanId: String,
        currentBotId: String,
        canSelectHuman: @escaping (TripleShotCharacterProfile) -> Bool = { _ in true },
        canSelectBot: @escaping (TripleShotCharacterProfile) -> Bool = { _ in true },
        seed: Int
    ) -> SetupState {
        let s = SetupState(
            humanProfiles: TripleShotCharacterRoster.humanSelectable(),
            botProfiles: TripleShotCharacterRoster.botSelectable(),
            currentHumanId: currentHumanId,
            currentBotId: currentBotId,
            canSelectHuman: canSelectHuman,
            canSelectBot: canSelectBot,
            physicalGameOrientation: TripleShotGameOrientation.PORTRAIT,
            random: KotlinRandom(seed: seed)
        )
        // `show` ends its construction with refreshModes().
        refreshModes(s)
        return s
    }

    // The state statements of the dialog's listeners, in their Kotlin order: refreshModes = rebuildSlotCards
    // (ensureSlots) then refreshPresentation (the court rules).
    private func refreshModes(_ s: SetupState) {
        s.ensureSlots()
        s.normalizeCourt()
    }

    private func tapShooting(_ s: SetupState) {
        s.selectedMode = GameType.SHOOTING_CHALLENGE
        refreshModes(s)
    }

    private func tapHorse(_ s: SetupState) {
        s.selectedMode = GameType.HORSE
        refreshModes(s)
    }

    private func tapGame(_ s: SetupState) {
        s.selectedMode = s.selectedTeamSize == 1 ? GameType.ONE_ON_ONE : GameType.TEAM_MATCH
        refreshModes(s)
    }

    private func tapSize(_ s: SetupState, _ size: Int) {
        let changed = s.selectedTeamSize != size
        s.selectedTeamSize = size
        s.selectedMode = size == 1 ? GameType.ONE_ON_ONE : GameType.TEAM_MATCH
        if changed && size >= 2 { s.randomizeTeams() } else { s.ensureSlots() }
        refreshModes(s)
    }

    private func replaceTeam(_ s: SetupState, _ index: Int, _ replacement: TripleShotCharacterProfile) {
        if index == 0 { s.selectedHuman = replacement } else { s.selectedTeammates[index - 1] = replacement }
        s.ensureSlots()
    }

    private func replaceOpponent(_ s: SetupState, _ index: Int, _ replacement: TripleShotCharacterProfile) {
        s.selectedOpponents[index] = replacement
        s.selectedPrimaryBot = s.selectedOpponents.first!
        s.ensureSlots()
    }

    private func humanSectionChanged(_ s: SetupState, _ p: TripleShotCharacterProfile) {
        s.selectedHuman = p
    }

    private func botSectionChanged(_ s: SetupState, _ p: TripleShotCharacterProfile) {
        s.selectedPrimaryBot = p
        if s.selectedOpponents.isEmpty { s.selectedOpponents.append(p) } else { s.selectedOpponents[0] = p }
    }

    // MARK: Roster data shown by both dialogs

    func testRosterOrders() {
        XCTAssertEqual(ids(TripleShotCharacterRoster.humanSelectable()),
                       "[woman_dark rooza nova unicorn_32 coach_67 zephyr kyra kyra_original flare ace_23 buddy_23]")
        XCTAssertEqual(ids(TripleShotCharacterRoster.botSelectable()),
                       "[bob woman_dark rooza nova unicorn_32 coach_67 zephyr kyra kyra_original flare ace_23 buddy_23]")
        let s = makeState(currentHumanId: "woman_dark", currentBotId: "bob", seed: 42)
        // (humanProfiles + botProfiles).distinctBy { it.id }: the eleven human profiles, then BOB.
        XCTAssertEqual(ids(s.allTeamProfiles),
                       "[woman_dark rooza nova unicorn_32 coach_67 zephyr kyra kyra_original flare ace_23 buddy_23 bob]")
    }

    func testOverallRatingVectors() {
        // OVR = (inside + midRange + threePoint + speed + strength + height + blocking + stealing + ballHandling) / 9.
        let expected: [(id: String, name: String, ovr: Int)] = [
            ("bob", "BOB", 59), ("woman_dark", "Maya", 74), ("rooza", "Rooza", 75), ("nova", "Mia Essence Skies", 85),
            ("unicorn_32", "Sonic", 73), ("coach_67", "Coach 67", 74), ("zephyr", "Comet", 81), ("kyra", "Gaya", 81),
            ("kyra_original", "Kyra", 81), ("flare", "FLARE", 82), ("ace_23", "Ace 23", 78), ("buddy_23", "Buddy 23", 70)
        ]
        let all = TripleShotCharacterRoster.all
        XCTAssertEqual(all.map { $0.id }, expected.map { $0.id })
        for (p, e) in zip(all, expected) {
            let r = p.ratings
            let overall = (r.inside + r.midRange + r.threePoint + r.speed + r.strength
                + r.height + r.blocking + r.stealing + r.ballHandling) / 9
            XCTAssertEqual(p.displayName, e.name, p.id)
            XCTAssertEqual(overall, e.ovr, p.id)
        }
    }

    // MARK: Bot setup state (golden vectors)

    /// S1: production rosters, every character ready, Home's defaults (woman_dark vs bob), seed 42.
    func testScenarioProductionRoster() {
        let s = makeState(currentHumanId: "woman_dark", currentBotId: "bob", seed: 42)
        XCTAssertEqual(describe(s), "SHOOTING_CHALLENGE size=1 court=enchanted_forest human=woman_dark bot=bob mates=[] opps=[bob]")
        XCTAssertEqual(start(s), "Selection(SHOOTING_CHALLENGE,1,woman_dark,[],[bob],enchanted_forest)")
        tapGame(s)
        XCTAssertEqual(describe(s), "ONE_ON_ONE size=1 court=enchanted_forest human=woman_dark bot=bob mates=[] opps=[bob]")
        XCTAssertEqual(ids(s.profilePickerChoices(current: s.selectedHuman)),
                       "[woman_dark rooza nova unicorn_32 coach_67 zephyr kyra kyra_original flare ace_23 buddy_23]")
        XCTAssertEqual(ids(s.profilePickerChoices(current: s.selectedOpponents[0])),
                       "[rooza nova unicorn_32 coach_67 zephyr kyra kyra_original flare ace_23 buddy_23 bob]")
        XCTAssertEqual(start(s), "Selection(ONE_ON_ONE,1,woman_dark,[],[bob],enchanted_forest)")
        tapSize(s, 2)
        XCTAssertEqual(describe(s), "TEAM_MATCH size=2 court=sunset_pulse human=kyra_original bot=unicorn_32 mates=[flare] opps=[unicorn_32 kyra]")
        XCTAssertEqual(ids(s.profilePickerChoices(current: s.selectedHuman)),
                       "[woman_dark rooza nova coach_67 zephyr kyra_original ace_23 buddy_23 bob]")
        XCTAssertEqual(start(s), "Selection(TEAM_MATCH,2,kyra_original,[flare],[unicorn_32 kyra],sunset_pulse)")
        tapSize(s, 3)
        XCTAssertEqual(describe(s), "TEAM_MATCH size=3 court=sunset_pulse human=flare bot=buddy_23 mates=[nova ace_23] opps=[buddy_23 rooza kyra]")
        tapSize(s, 3)   // the same size does not re-randomise
        XCTAssertEqual(describe(s), "TEAM_MATCH size=3 court=sunset_pulse human=flare bot=buddy_23 mates=[nova ace_23] opps=[buddy_23 rooza kyra]")
        XCTAssertEqual(ids(s.profilePickerChoices(current: s.selectedHuman)),
                       "[woman_dark unicorn_32 coach_67 zephyr kyra_original flare bob]")
        replaceTeam(s, 1, s.profilePickerChoices(current: s.selectedTeammates[0]).last!)
        XCTAssertEqual(describe(s), "TEAM_MATCH size=3 court=sunset_pulse human=flare bot=buddy_23 mates=[bob ace_23] opps=[buddy_23 rooza kyra]")
        replaceOpponent(s, 2, s.profilePickerChoices(current: s.selectedOpponents[2]).first!)
        XCTAssertEqual(describe(s), "TEAM_MATCH size=3 court=sunset_pulse human=flare bot=buddy_23 mates=[bob ace_23] opps=[buddy_23 rooza woman_dark]")
        replaceTeam(s, 0, s.profilePickerChoices(current: s.selectedHuman).first!)
        XCTAssertEqual(describe(s), "TEAM_MATCH size=3 court=sunset_pulse human=nova bot=buddy_23 mates=[bob ace_23] opps=[buddy_23 rooza woman_dark]")
        XCTAssertEqual(start(s), "Selection(TEAM_MATCH,3,nova,[bob ace_23],[buddy_23 rooza woman_dark],sunset_pulse)")
        tapSize(s, 1)   // keeps the first two entries: the former teammate becomes the opponent
        XCTAssertEqual(describe(s), "ONE_ON_ONE size=1 court=sunset_pulse human=nova bot=bob mates=[] opps=[bob]")
        XCTAssertEqual(start(s), "Selection(ONE_ON_ONE,1,nova,[],[bob],sunset_pulse)")
        tapSize(s, 2)
        XCTAssertEqual(describe(s), "TEAM_MATCH size=2 court=sunset_pulse human=ace_23 bot=bob mates=[unicorn_32] opps=[bob zephyr]")
        s.selectedCourtId = "neon_tide"   // court button listener
        tapGame(s)
        XCTAssertEqual(describe(s), "TEAM_MATCH size=2 court=neon_tide human=ace_23 bot=bob mates=[unicorn_32] opps=[bob zephyr]")
        tapSize(s, 1)
        XCTAssertEqual(describe(s), "ONE_ON_ONE size=1 court=sunset_pulse human=ace_23 bot=unicorn_32 mates=[] opps=[unicorn_32]")
        s.selectedCourtId = "frostline"
        tapHorse(s)
        XCTAssertEqual(describe(s), "HORSE size=1 court=frostline human=ace_23 bot=unicorn_32 mates=[] opps=[unicorn_32]")
        XCTAssertEqual(start(s), "Selection(HORSE,1,ace_23,[],[unicorn_32],frostline)")
        tapShooting(s)
        XCTAssertEqual(describe(s), "SHOOTING_CHALLENGE size=1 court=frostline human=ace_23 bot=unicorn_32 mates=[] opps=[unicorn_32]")
        XCTAssertEqual(start(s), "Selection(SHOOTING_CHALLENGE,1,ace_23,[],[unicorn_32],frostline)")
    }

    /// S2: the same character on both sides (allowed in Shooting / HORSE), then Game 1 x 1 picks the next pool profile.
    func testScenarioSameCharacterBothSides() {
        let s = makeState(currentHumanId: "woman_dark", currentBotId: "woman_dark", seed: 1)
        XCTAssertEqual(describe(s), "SHOOTING_CHALLENGE size=1 court=enchanted_forest human=woman_dark bot=woman_dark mates=[] opps=[woman_dark]")
        XCTAssertEqual(start(s), "Selection(SHOOTING_CHALLENGE,1,woman_dark,[],[woman_dark],enchanted_forest)")
        tapGame(s)
        XCTAssertEqual(describe(s), "ONE_ON_ONE size=1 court=enchanted_forest human=woman_dark bot=rooza mates=[] opps=[rooza]")
        tapShooting(s)
        humanSectionChanged(s, profile("flare"))
        botSectionChanged(s, profile("flare"))
        XCTAssertEqual(describe(s), "SHOOTING_CHALLENGE size=1 court=enchanted_forest human=flare bot=flare mates=[] opps=[flare]")
        tapGame(s)
        XCTAssertEqual(describe(s), "ONE_ON_ONE size=1 court=enchanted_forest human=flare bot=woman_dark mates=[] opps=[woman_dark]")
    }

    /// S3: a saved human id outside the human list (bob) falls back to the first ready human; an unknown bot id to the
    /// first ready bot.
    func testScenarioUnknownSavedIds() {
        let s = makeState(currentHumanId: "bob", currentBotId: "nobody", seed: 3)
        XCTAssertEqual(describe(s), "SHOOTING_CHALLENGE size=1 court=enchanted_forest human=woman_dark bot=bob mates=[] opps=[bob]")
        tapSize(s, 3)
        XCTAssertEqual(describe(s), "TEAM_MATCH size=3 court=sunset_pulse human=flare bot=nova mates=[kyra_original kyra] opps=[nova zephyr rooza]")
    }

    /// S4: only four characters ready: the pool fill-up path, TEAM_MATCH without an art check, the 1v1 and non-game
    /// art checks (the "choose ready" toast), seed 7.
    func testScenarioFewReadyCharacters() {
        let readyHumans: Set<String> = ["woman_dark", "rooza"]
        let readyBots: Set<String> = ["bob", "nova"]
        let s = makeState(currentHumanId: "zephyr", currentBotId: "kyra",
                          canSelectHuman: { readyHumans.contains($0.id) }, canSelectBot: { readyBots.contains($0.id) },
                          seed: 7)
        XCTAssertEqual(describe(s), "SHOOTING_CHALLENGE size=1 court=enchanted_forest human=woman_dark bot=bob mates=[] opps=[bob]")
        XCTAssertEqual(ids(s.teamSelectionPool(required: 6)),
                       "[woman_dark rooza nova bob unicorn_32 coach_67 zephyr kyra kyra_original flare ace_23 buddy_23]")
        XCTAssertEqual(ids(s.teamSelectionPool(required: 2)), "[woman_dark rooza nova bob]")
        XCTAssertEqual(start(s), "Selection(SHOOTING_CHALLENGE,1,woman_dark,[],[bob],enchanted_forest)")
        tapSize(s, 3)
        XCTAssertEqual(describe(s), "TEAM_MATCH size=3 court=sunset_pulse human=rooza bot=zephyr mates=[ace_23 flare] opps=[zephyr unicorn_32 woman_dark]")
        XCTAssertEqual(start(s), "Selection(TEAM_MATCH,3,rooza,[ace_23 flare],[zephyr unicorn_32 woman_dark],sunset_pulse)")
        tapSize(s, 1)
        XCTAssertEqual(describe(s), "ONE_ON_ONE size=1 court=sunset_pulse human=rooza bot=ace_23 mates=[] opps=[ace_23]")
        XCTAssertEqual(start(s), "TOAST")
        tapSize(s, 2)
        XCTAssertEqual(describe(s), "TEAM_MATCH size=2 court=sunset_pulse human=nova bot=woman_dark mates=[bob] opps=[woman_dark rooza]")
        tapSize(s, 1)
        XCTAssertEqual(describe(s), "ONE_ON_ONE size=1 court=sunset_pulse human=nova bot=bob mates=[] opps=[bob]")
        XCTAssertEqual(start(s), "TOAST")
        tapShooting(s)
        XCTAssertEqual(describe(s), "SHOOTING_CHALLENGE size=1 court=sunset_pulse human=nova bot=bob mates=[] opps=[bob]")
        XCTAssertEqual(start(s), "TOAST")
        humanSectionChanged(s, profile("zephyr"))
        XCTAssertEqual(start(s), "TOAST")
    }

    /// Every randomised roster is six unique identities, for many seeds (spec 19 section 4.1.5).
    func testRandomizedRostersAreUnique() {
        for seed in 0..<200 {
            let s = makeState(currentHumanId: "woman_dark", currentBotId: "bob", seed: seed)
            tapSize(s, 3)
            let whole = [s.selectedHuman] + s.selectedTeammates + s.selectedOpponents
            XCTAssertEqual(Set(whole.map { $0.id }).count, 6, "seed \(seed)")
            XCTAssertEqual(s.selectedTeammates.count, 2)
            XCTAssertEqual(s.selectedOpponents.count, 3)
            XCTAssertEqual(s.selectedPrimaryBot.id, s.selectedOpponents[0].id)
            XCTAssertEqual(s.profilePickerChoices(current: s.selectedHuman).count, 7)
            XCTAssertEqual(s.profilePickerChoices(current: s.selectedOpponents[1]).count, 7)
            XCTAssertNotNil(s.startSelection())
        }
    }

    func testSelectedIdsExcept() {
        let s = makeState(currentHumanId: "woman_dark", currentBotId: "bob", seed: 42)
        tapSize(s, 2)   // kyra_original + [flare] vs [unicorn_32 kyra]
        XCTAssertEqual(s.selectedIdsExcept(currentId: "flare"), ["kyra_original", "unicorn_32", "kyra"])
        XCTAssertEqual(s.selectedIdsExcept(currentId: "nobody"), ["kyra_original", "flare", "unicorn_32", "kyra"])
    }

    // MARK: Courts

    func testCourtButtonVisibilityRules() {
        // refreshPresentation: TEAM_MATCH shows only the four full courts, every other mode hides the team-only ones
        // (the buttons are added in catalog order).
        func visible(teamMatch: Bool) -> [String] {
            return TripleShotCourtCatalog.all.map { $0.id }.filter { id in
                SetupState.courtButtonVisibility(id: id, isTeamFullCourt: teamMatch) == AView.VISIBLE
            }
        }
        XCTAssertEqual(visible(teamMatch: true), ["sunset_pulse", "sunset_cove", "neon_tide", "neon_falls"])
        XCTAssertEqual(visible(teamMatch: false),
                       ["enchanted_forest", "sunset_pulse", "skyforge_peaks", "frostline", "rain_break", "midnight_arena"])
        XCTAssertEqual(TripleShotCourtCatalog.DEFAULT_ID, "enchanted_forest")
    }

    func testCourtNormalisation() {
        let s = makeState(currentHumanId: "woman_dark", currentBotId: "bob", seed: 42)
        for (mode, court, expected) in [
            (GameType.TEAM_MATCH, "enchanted_forest", "sunset_pulse"), (GameType.TEAM_MATCH, "neon_falls", "neon_falls"),
            (GameType.TEAM_MATCH, "frostline", "sunset_pulse"), (GameType.ONE_ON_ONE, "neon_tide", "sunset_pulse"),
            (GameType.ONE_ON_ONE, "sunset_pulse", "sunset_pulse"), (GameType.ONE_ON_ONE, "rain_break", "rain_break"),
            (GameType.HORSE, "sunset_cove", "sunset_pulse"), (GameType.SHOOTING_CHALLENGE, "midnight_arena", "midnight_arena")
        ] {
            s.selectedMode = mode
            s.selectedCourtId = court
            s.normalizeCourt()
            XCTAssertEqual(s.selectedCourtId, expected, "\(mode.name) \(court)")
        }
    }

    // MARK: Physical orientation

    func testPhysicalOrientationMapping() {
        let s = makeState(currentHumanId: "woman_dark", currentBotId: "bob", seed: 42)
        XCTAssertEqual(s.physicalGameOrientation, TripleShotGameOrientation.PORTRAIT)
        let vectors: [(Int, TripleShotGameOrientation)] = [
            (0, .PORTRAIT), (44, .PORTRAIT), (45, .LANDSCAPE), (90, .LANDSCAPE), (134, .LANDSCAPE), (135, .PORTRAIT),
            (180, .PORTRAIT), (224, .PORTRAIT), (225, .LANDSCAPE), (270, .LANDSCAPE), (314, .LANDSCAPE),
            (315, .PORTRAIT), (359, .PORTRAIT)
        ]
        for (orientation, expected) in vectors {
            s.onOrientationChanged(orientation: orientation)
            XCTAssertEqual(s.physicalGameOrientation, expected, "\(orientation)")
        }
        // ORIENTATION_UNKNOWN (device flat) keeps the last value.
        s.onOrientationChanged(orientation: 90)
        s.onOrientationChanged(orientation: AOrientationEventListener.ORIENTATION_UNKNOWN)
        XCTAssertEqual(s.physicalGameOrientation, TripleShotGameOrientation.LANDSCAPE)
        s.onOrientationChanged(orientation: 0)
        s.onOrientationChanged(orientation: AOrientationEventListener.ORIENTATION_UNKNOWN)
        XCTAssertEqual(s.physicalGameOrientation, TripleShotGameOrientation.PORTRAIT)
    }

    func testAccelerometerAngles() {
        // Android accelerometer values (m/s^2): upright (0, g, 0) = 0 degrees, (-g, 0, 0) = 90, upside down = 180,
        // (g, 0, 0) = 270, flat = ORIENTATION_UNKNOWN.
        let g: Float = 9.80665
        let cases: [([Float], Int, TripleShotGameOrientation)] = [
            ([0, g, 0], 0, .PORTRAIT), ([-g, 0, 0], 90, .LANDSCAPE), ([0, -g, 0], 180, .PORTRAIT),
            ([g, 0, 0], 270, .LANDSCAPE), ([0, 0, g], AOrientationEventListener.ORIENTATION_UNKNOWN, .LANDSCAPE)
        ]
        let s = makeState(currentHumanId: "woman_dark", currentBotId: "bob", seed: 42)
        for (values, angle, expected) in cases {
            let orientation = AOrientationEventListener.orientation(fromAccelerometer: values)
            XCTAssertEqual(orientation, angle, "\(values)")
            s.onOrientationChanged(orientation: orientation)
            XCTAssertEqual(s.physicalGameOrientation, expected, "\(values)")
        }
    }

    // MARK: Selection

    func testSelectionCarriesOrientationAndCourt() {
        let s = makeState(currentHumanId: "woman_dark", currentBotId: "bob", seed: 42)
        s.onOrientationChanged(orientation: 270)
        tapGame(s)
        XCTAssertEqual(
            s.startSelection(),
            TripleShotBotMatchSetupDialog.Selection(
                gameType: GameType.ONE_ON_ONE,
                teamSize: 1,
                human: profile("woman_dark"),
                teammates: [],
                opponents: [profile("bob")],
                gameOrientation: TripleShotGameOrientation.LANDSCAPE,
                courtId: "enchanted_forest"
            )
        )
        // A stale team size travels with Shooting Challenge / HORSE (harmless downstream).
        tapSize(s, 2)
        tapShooting(s)
        let selection = s.startSelection()
        XCTAssertEqual(selection?.gameType, GameType.SHOOTING_CHALLENGE)
        XCTAssertEqual(selection?.teamSize, 2)
        XCTAssertEqual(selection?.teammates.count, 0)
        XCTAssertEqual(selection?.opponents.map { $0.id }, [s.selectedPrimaryBot.id])
    }

    func testPickerModeNames() {
        XCTAssertEqual(TripleShotCharacterPickerDialog.Mode.allCases.map { $0.name }, ["HUMAN", "BOT"])
    }
}
