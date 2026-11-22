import Foundation

/// The ball and conditions a challenge or lesson run starts with.
struct SpudPracticeStart: Equatable {
    let ball: BallKind
    let conditions: PracticeConditions
}

/// iOS payment model (CLAUDE.md): what this player may choose and start, as the pages and `AppModel`'s small hooks
/// ask it. Without the full game, the setup shows the free values (the saved settings stay as they are, so buying
/// brings them back), locked choices keep a 🔒 and open the unlock screen, and a paint-balloon game uses a free one.
extension AppModel {
    static let lockMark = "🔒 "

    /// The full game is owned (or shared through Family Sharing), or this is an App Store capture.
    var fullGame: Bool {
        return spud.fullGame
    }

    private var spudChoices: SpudAccess.Choices {
        return SpudAccess.clamp(SpudAccess.Choices(players: count, scene: scene, ball: ball, house: house), owner: fullGame)
    }

    /// The room capacity the setup shows and a game this player starts or hosts uses.
    var spudPlayers: Int {
        return spudChoices.players
    }

    var spudScene: ArenaScene {
        return spudChoices.scene
    }

    var spudBall: BallKind {
        return spudChoices.ball
    }

    /// The chosen house players that fit the places above.
    var spudHouse: [String] {
        return spudChoices.house
    }

    /// The character this player plays as (the saved one, or Miniko while the saved one is locked).
    var playAvatar: String {
        return SpudAccess.avatar(avatar, owner: fullGame)
    }

    func characterLocked(_ id: String) -> Bool {
        return SpudAccess.characterLocked(id, owner: fullGame)
    }

    func openUnlock() {
        spud.openUnlock()
    }

    /// The grown-up Settings page's entry: owned or not.
    var spudSettingsTitle: String {
        return StoreText.get(spud.ownsFullGame ? .settingsOwned : .settingsNotOwned)
    }

    /// "N free paint balloon games left" or "… comes tomorrow", while the paint balloon is chosen without the full game.
    func spudPaintLine(_ chosen: BallKind) -> String? {
        guard chosen == .paint, !fullGame else { return nil }
        return StoreText.paintLine(gamesLeft: spud.paintGamesLeft)
    }

    /// A game with `ball` is starting: a paint-balloon game uses a free one; with none left the unlock screen opens and
    /// the game does not start.
    func spudMayStart(_ ball: BallKind) -> Bool {
        if ball != .paint || spud.usePaintGame() { return true }
        spud.openUnlock()
        return false
    }

    // MARK: Setup choices

    func capacityTitle(_ n: Int) -> String {
        return (SpudAccess.playersLocked(n, owner: fullGame) ? AppModel.lockMark : "") + String(n)
    }

    func chooseCapacity(_ n: Int) {
        if SpudAccess.playersLocked(n, owner: fullGame) {
            openUnlock()
        } else {
            setCapacity(n)
        }
    }

    func sceneTitle(_ s: ArenaScene) -> String {
        return (SpudAccess.sceneLocked(s, owner: fullGame) ? AppModel.lockMark : "") + tr(s.en, s.he)
    }

    func chooseScene(_ s: ArenaScene) {
        if SpudAccess.sceneLocked(s, owner: fullGame) {
            openUnlock()
            return
        }
        scene = s
        persist()
    }

    func ballTitle(_ b: BallKind) -> String {
        return (SpudAccess.ballLocked(b, owner: fullGame) ? AppModel.lockMark : "") + tr(b.en, b.he)
    }

    func chooseBall(_ b: BallKind) {
        if SpudAccess.ballLocked(b, owner: fullGame) {
            openUnlock()
            return
        }
        ball = b
        persist()
    }

    // MARK: Challenges and lessons

    func conditionsTitle(_ c: PracticeConditions) -> String {
        return (SpudAccess.conditionsLocked(c, owner: fullGame) ? AppModel.lockMark : "") + conditionText(c)
    }

    func challengeLocked(_ step: Int) -> Bool {
        return SpudAccess.challengeLocked(step, owner: fullGame)
    }

    /// A challenge (empty topic) or lesson run is starting: challenges after the 7th need the full game; a locked ball
    /// or arena (an old saved choice) falls back to a free one; a paint balloon uses a free paint game. Nil when the
    /// run does not start (the unlock screen is open).
    func spudPractice(_ step: Int, _ ball: BallKind, _ conditions: PracticeConditions, _ topic: String) -> SpudPracticeStart? {
        if topic.isEmpty && challengeLocked(step) {
            openUnlock()
            return nil
        }
        let chosen = SpudAccess.practiceBall(ball, allowed: PracticeCurriculum.balls(step, topic), owner: fullGame)
        let place = SpudAccess.practiceConditions(conditions, owner: fullGame)
        guard spudMayStart(chosen) else { return nil }
        return SpudPracticeStart(ball: chosen, conditions: place)
    }
}
