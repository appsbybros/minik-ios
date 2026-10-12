import Foundation

/// Android `core/Models.kt` — world vectors, characters, settings, members and commands.
struct V: Hashable {
    var x: Double
    var y: Double

    init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    static let zero = V(0, 0)

    static func + (a: V, b: V) -> V { return V(a.x + b.x, a.y + b.y) }
    static func - (a: V, b: V) -> V { return V(a.x - b.x, a.y - b.y) }
    static func * (a: V, k: Double) -> V { return V(a.x * k, a.y * k) }

    func length() -> Double { return hypot(x, y) }

    func unit() -> V {
        let l = length()
        return l < 0.00001 ? V(0, -1) : self * (1 / l)
    }

    func finite() -> Bool { return x.isFinite && y.isFinite }
}

enum AmuduError: Error {
    case invalidConfig
    case invalidRoster
    case invalidValue(String)
}

/// The exact four-dimensional house-player ratings (DECISIONS.md).
struct Skills: Equatable {
    let accuracy: Int
    let power: Int
    let speed: Int
    let catching: Int

    init(_ accuracy: Int, _ power: Int, _ speed: Int, _ catching: Int) {
        self.accuracy = min(max(accuracy, 1), 5)
        self.power = min(max(power, 1), 5)
        self.speed = min(max(speed, 1), 5)
        self.catching = min(max(catching, 1), 5)
    }

    func catchProbability(wasRunning: Bool) -> Double {
        return Double(max(catching - (wasRunning ? 2 : 0), 0)) / 5.0
    }

    var runFactor: Double { return 0.58 + 0.14 * Double(speed) }
    var powerFactor: Double { return 0.75 + 0.10 * Double(power) }
}

struct AmuduCharacter: Equatable {
    let id: String
    let en: String
    let he: String
    let qualities: Skills

    func name(hebrew: Bool) -> String { return hebrew ? he : en }
}

enum AmuduCharacters {
    static let all: [AmuduCharacter] = [
        AmuduCharacter(id: "miniko", en: "Miniko", he: "מיניקו", qualities: Skills(1, 3, 3, 1)),
        AmuduCharacter(id: "minik", en: "Minik", he: "מיניק", qualities: Skills(2, 2, 3, 2)),
        AmuduCharacter(id: "kyra", en: "Kyra", he: "ספיר", qualities: Skills(5, 5, 5, 4)),
        AmuduCharacter(id: "flare", en: "Flare", he: "ברק", qualities: Skills(4, 5, 5, 5)),
        AmuduCharacter(id: "gaya", en: "Gaya", he: "גאיה", qualities: Skills(5, 5, 5, 5)),
        AmuduCharacter(id: "mia", en: "Mia", he: "מיה", qualities: Skills(5, 3, 4, 5)),
        AmuduCharacter(id: "amber", en: "Amber", he: "ענבר", qualities: Skills(4, 3, 2, 4)),
        AmuduCharacter(id: "comet", en: "Comet", he: "שביט", qualities: Skills(3, 4, 5, 4)),
        AmuduCharacter(id: "june", en: "June", he: "סהר", qualities: Skills(4, 3, 5, 5)),
        AmuduCharacter(id: "moshiko", en: "Bouncy Bob", he: "מושיק", qualities: Skills(4, 5, 1, 4)),
        AmuduCharacter(id: "coach67", en: "Coach", he: "המאמן", qualities: Skills(2, 3, 4, 4)),
    ]

    static var ids: [String] { return all.map { $0.id } }

    static func get(_ id: String) -> AmuduCharacter {
        return all.first { $0.id == id } ?? all[0]
    }

    static func exists(_ id: String) -> Bool {
        return all.contains { $0.id == id }
    }

    /// Human duplicates are allowed. Bots are distinct and never reuse a human avatar.
    static func availableBots(humans: [Member], requested: [String], fillTo: Int = 0) -> [String] {
        let occupied = Set(humans.map { $0.character })
        var seen = Set<String>()
        var selected: [String] = []
        for id in requested {
            if seen.contains(id) { continue }
            seen.insert(id)
            if !occupied.contains(id) && exists(id) { selected.append(id) }
        }
        for c in all where selected.count < fillTo && !occupied.contains(c.id) && !selected.contains(c.id) {
            selected.append(c.id)
        }
        return selected
    }
}

/// Android `Scene` (renamed: SwiftUI already has a `Scene` type). Raw values are the shared wire names.
enum ArenaScene: String, CaseIterable {
    case park = "PARK"
    case beach = "BEACH"
    case andromeda = "ANDROMEDA"

    var gravity: Double {
        switch self {
        case .park: return 9.8
        case .beach: return 8.6
        case .andromeda: return 4.8
        }
    }

    var run: Double {
        switch self {
        case .park: return 1.0
        case .beach: return 0.89
        case .andromeda: return 1.06
        }
    }

    var bounce: Double {
        switch self {
        case .park: return 0.8
        case .beach: return 0.55
        case .andromeda: return 1.0
        }
    }

    var en: String {
        switch self {
        case .park: return "Sunshine park"
        case .beach: return "Tropical beach"
        case .andromeda: return "Andromeda"
        }
    }

    var he: String {
        switch self {
        case .park: return "פארק השמש"
        case .beach: return "חוף טרופי"
        case .andromeda: return "אנדרומדה"
        }
    }

    /// Android art file base name (park.webp, beach.webp, andromeda.webp).
    var artName: String { return rawValue.lowercased() }
}

enum BallKind: String, CaseIterable {
    case foam = "FOAM"
    case beach = "BEACH"
    case neon = "NEON"
    case tennis = "TENNIS"

    var speed: Double {
        switch self {
        case .foam: return 7.3
        case .beach: return 6.2
        case .neon: return 9.4
        case .tennis: return 8.6
        }
    }

    var restitution: Double {
        switch self {
        case .foam: return 0.36
        case .beach: return 0.70
        case .neon: return 0.86
        case .tennis: return 0.78
        }
    }

    var catchRadius: Double {
        switch self {
        case .foam: return 0.72
        case .beach: return 0.82
        case .neon: return 0.65
        case .tennis: return 0.60
        }
    }

    var en: String {
        switch self {
        case .foam: return "Soft foam"
        case .beach: return "Beach ball"
        case .neon: return "Neon party"
        case .tennis: return "Tennis ball"
        }
    }

    var he: String {
        switch self {
        case .foam: return "כדור ספוג"
        case .beach: return "כדור ים"
        case .neon: return "כדור ניאון"
        case .tennis: return "כדור טניס"
        }
    }

    var visualScale: Double {
        switch self {
        case .tennis: return 0.72
        case .foam, .beach, .neon: return 1.0
        }
    }

    /// Asset name of the ball sprite (Android foam.webp, beachball.webp, neon.webp, tennis.png).
    var artName: String {
        switch self {
        case .foam: return "foam"
        case .beach: return "beachball"
        case .neon: return "neon"
        case .tennis: return "tennis"
        }
    }
}

enum Daylight: String, CaseIterable {
    case morning = "MORNING"
    case noon = "NOON"
    case evening = "EVENING"
    case night = "NIGHT"

    var en: String {
        switch self {
        case .morning: return "Morning"
        case .noon: return "Noon"
        case .evening: return "Evening"
        case .night: return "Night"
        }
    }

    var he: String {
        switch self {
        case .morning: return "בוקר"
        case .noon: return "צהריים"
        case .evening: return "ערב"
        case .night: return "לילה"
        }
    }
}

enum Wind: String, CaseIterable {
    case none = "NONE"
    case slow = "SLOW"
    case fast = "FAST"

    var acceleration: Double {
        switch self {
        case .none: return 0.0
        case .slow: return 0.45
        case .fast: return 1.5
        }
    }

    var en: String {
        switch self {
        case .none: return "No wind"
        case .slow: return "Light wind"
        case .fast: return "Strong wind"
        }
    }

    var he: String {
        switch self {
        case .none: return "ללא רוח"
        case .slow: return "רוח חלשה"
        case .fast: return "רוח חזקה"
        }
    }
}

enum ThrowMode: String, CaseIterable {
    case easy = "EASY"
    case standard = "STANDARD"

    var en: String {
        switch self {
        case .easy: return "Easy · low throws and ground bounces allowed"
        case .standard: return "Standard · control height; no ground bounce"
        }
    }

    var he: String {
        switch self {
        case .easy: return "קל · זריקה נמוכה ופגיעה אחרי קפיצה"
        case .standard: return "רגיל · שליטה בגובה, בלי קפיצה מהקרקע"
        }
    }
}

/// Android `RuleSet`: the two playable variants (funny nicknames, or four letters then watching).
enum RuleSet: String, CaseIterable {
    case nicknames = "NICKNAMES"
    case spud = "SPUD"
}

/// Android `SpectatorReason`: why an actor is watching (`none` while playing).
enum SpectatorReason: String, CaseIterable {
    case none = "NONE"
    case inactive = "INACTIVE"
    case letters = "LETTERS"
}

enum FreezeRule: String, CaseIterable {
    case freeze = "FREEZE"
    case honor = "HONOR"
}

enum Phase: String, CaseIterable {
    case circle = "CIRCLE"
    case air = "AIR"
    case retrieve = "RETRIEVE"
    case shout = "SHOUT"
    case aim = "AIM"
    case flight = "FLIGHT"
    case resolve = "RESOLVE"
    case huddle = "HUDDLE"
    case returnVote = "RETURN_VOTE"
    case waiting = "WAITING"
    case finished = "FINISHED"
}

/// Android `GameConfig`. The validating initializer throws where Kotlin's `require` throws.
struct GameConfig: Equatable {
    /// Kotlin `actionSeconds in listOf(0,20,30,45,60)`.
    static let actionChoices = [0, 20, 30, 45, 60]

    let scene: ArenaScene
    let ball: BallKind
    let freezeRule: FreezeRule
    let participants: Int
    let turns: Int
    let width: Double
    let depth: Double
    let moveSpeed: Double
    let catchWindow: Double
    let duckSeconds: Double
    let duckHeight: Double
    let standingHeight: Double
    let doubleTapMs: Int
    let resolveSeconds: Double
    let huddleSeconds: Double
    let snapshotHz: Int
    let daylight: Daylight
    let throwMode: ThrowMode
    let wind: Wind
    let rules: RuleSet
    let requireCall: Bool
    let stepsAfterCall: Int
    let actionSeconds: Int
    let stepLengthFraction: Double
    let returnVoteSeconds: Double
    let idleLimit: Int
    let returnAttemptLimit: Int
    /// Kotlin `challengeStep`: the skill-journey challenge this engine practices (-1 for a regular game).
    let challengeStep: Int

    init(scene: ArenaScene = .park, ball: BallKind = .foam, freezeRule: FreezeRule = .freeze, participants: Int = 6, turns: Int = 0,
         width: Double = 16.0, depth: Double = 16.0, moveSpeed: Double = 4.4, catchWindow: Double = 0.7, duckSeconds: Double = 0.8,
         duckHeight: Double = 0.66, standingHeight: Double = 1.75, doubleTapMs: Int = 190, resolveSeconds: Double = 2.2,
         huddleSeconds: Double = 24.0, snapshotHz: Int = 12, daylight: Daylight = .noon, throwMode: ThrowMode = .standard,
         wind: Wind = .none, rules: RuleSet = .nicknames, requireCall: Bool = false, stepsAfterCall: Int = 0, actionSeconds: Int = 30,
         stepLengthFraction: Double = 0.03125, returnVoteSeconds: Double = 15.0, idleLimit: Int = 3, returnAttemptLimit: Int = 3,
         challengeStep: Int = -1) throws {
        let modes = GameConfig.actionChoices.contains(actionSeconds) && stepsAfterCall >= 0 && stepsAfterCall <= 4 &&
            stepLengthFraction >= 0.01 && stepLengthFraction <= 0.04 && returnVoteSeconds >= 10.0 && returnVoteSeconds <= 20.0 &&
            idleLimit == 3 && returnAttemptLimit == 3
        let basic = participants >= 2 && participants <= 10 && turns >= 0 && turns <= 100 && width >= 12.0 && width <= 40.0 &&
            depth >= 12.0 && depth <= 40.0 && moveSpeed > 0
        let timing = catchWindow >= 0.1 && catchWindow <= 0.8 && duckHeight > 0 && duckHeight < standingHeight
        let network = huddleSeconds >= 1 && snapshotHz >= 5 && snapshotHz <= 20
        guard modes && basic && timing && network else { throw AmuduError.invalidConfig }
        self.init(raw: scene, ball: ball, freezeRule: freezeRule, participants: participants, turns: turns, width: width, depth: depth,
                  moveSpeed: moveSpeed, catchWindow: catchWindow, duckSeconds: duckSeconds, duckHeight: duckHeight,
                  standingHeight: standingHeight, doubleTapMs: doubleTapMs, resolveSeconds: resolveSeconds, huddleSeconds: huddleSeconds,
                  snapshotHz: snapshotHz, daylight: daylight, throwMode: throwMode, wind: wind, rules: rules, requireCall: requireCall,
                  stepsAfterCall: stepsAfterCall, actionSeconds: actionSeconds, stepLengthFraction: stepLengthFraction,
                  returnVoteSeconds: returnVoteSeconds, idleLimit: idleLimit, returnAttemptLimit: returnAttemptLimit,
                  challengeStep: challengeStep)
    }

    private init(raw scene: ArenaScene, ball: BallKind, freezeRule: FreezeRule, participants: Int, turns: Int, width: Double,
                 depth: Double, moveSpeed: Double, catchWindow: Double, duckSeconds: Double, duckHeight: Double,
                 standingHeight: Double, doubleTapMs: Int, resolveSeconds: Double, huddleSeconds: Double, snapshotHz: Int,
                 daylight: Daylight, throwMode: ThrowMode, wind: Wind, rules: RuleSet, requireCall: Bool, stepsAfterCall: Int,
                 actionSeconds: Int, stepLengthFraction: Double, returnVoteSeconds: Double, idleLimit: Int, returnAttemptLimit: Int,
                 challengeStep: Int) {
        self.scene = scene
        self.ball = ball
        self.freezeRule = freezeRule
        self.participants = participants
        self.turns = turns
        self.width = width
        self.depth = depth
        self.moveSpeed = moveSpeed
        self.catchWindow = catchWindow
        self.duckSeconds = duckSeconds
        self.duckHeight = duckHeight
        self.standingHeight = standingHeight
        self.doubleTapMs = doubleTapMs
        self.resolveSeconds = resolveSeconds
        self.huddleSeconds = huddleSeconds
        self.snapshotHz = snapshotHz
        self.daylight = daylight
        self.throwMode = throwMode
        self.wind = wind
        self.rules = rules
        self.requireCall = requireCall
        self.stepsAfterCall = stepsAfterCall
        self.actionSeconds = actionSeconds
        self.stepLengthFraction = stepLengthFraction
        self.returnVoteSeconds = returnVoteSeconds
        self.idleLimit = idleLimit
        self.returnAttemptLimit = returnAttemptLimit
        self.challengeStep = challengeStep
    }

    /// The Kotlin defaults (6 players, park, foam, noon, standard, no wind, no turn limit, nickname rules, 16x16 court).
    static let defaults = GameConfig(raw: .park, ball: .foam, freezeRule: .freeze, participants: 6, turns: 0, width: 16.0, depth: 16.0,
                                     moveSpeed: 4.4, catchWindow: 0.7, duckSeconds: 0.8, duckHeight: 0.66, standingHeight: 1.75,
                                     doubleTapMs: 190, resolveSeconds: 2.2, huddleSeconds: 24.0, snapshotHz: 12, daylight: .noon,
                                     throwMode: .standard, wind: .none, rules: .nicknames, requireCall: false, stepsAfterCall: 0,
                                     actionSeconds: 30, stepLengthFraction: 0.03125, returnVoteSeconds: 15.0, idleLimit: 3,
                                     returnAttemptLimit: 3, challengeStep: -1)

    /// Kotlin `copy(...)`: every field that is not passed keeps its value; the copy is validated like the constructor.
    func copy(scene: ArenaScene? = nil, ball: BallKind? = nil, freezeRule: FreezeRule? = nil, participants: Int? = nil, turns: Int? = nil,
              width: Double? = nil, depth: Double? = nil, huddleSeconds: Double? = nil, daylight: Daylight? = nil,
              throwMode: ThrowMode? = nil, wind: Wind? = nil, rules: RuleSet? = nil, requireCall: Bool? = nil,
              stepsAfterCall: Int? = nil, actionSeconds: Int? = nil, stepLengthFraction: Double? = nil) throws -> GameConfig {
        return try GameConfig(scene: scene ?? self.scene, ball: ball ?? self.ball, freezeRule: freezeRule ?? self.freezeRule,
                              participants: participants ?? self.participants, turns: turns ?? self.turns, width: width ?? self.width,
                              depth: depth ?? self.depth, moveSpeed: moveSpeed, catchWindow: catchWindow, duckSeconds: duckSeconds,
                              duckHeight: duckHeight, standingHeight: standingHeight, doubleTapMs: doubleTapMs,
                              resolveSeconds: resolveSeconds, huddleSeconds: huddleSeconds ?? self.huddleSeconds, snapshotHz: snapshotHz,
                              daylight: daylight ?? self.daylight, throwMode: throwMode ?? self.throwMode, wind: wind ?? self.wind,
                              rules: rules ?? self.rules, requireCall: requireCall ?? self.requireCall,
                              stepsAfterCall: stepsAfterCall ?? self.stepsAfterCall, actionSeconds: actionSeconds ?? self.actionSeconds,
                              stepLengthFraction: stepLengthFraction ?? self.stepLengthFraction, returnVoteSeconds: returnVoteSeconds,
                              idleLimit: idleLimit, returnAttemptLimit: returnAttemptLimit, challengeStep: challengeStep)
    }

    /// Kotlin `copy(participants = n)`.
    func with(participants n: Int) throws -> GameConfig {
        return try copy(participants: n)
    }

    /// Kotlin `copy(scene = ...)` for the settings a test or the setup screen changes.
    func with(scene newScene: ArenaScene) throws -> GameConfig {
        return try copy(scene: newScene)
    }
}

struct Member: Equatable {
    let id: String
    let character: String
    let name: String
    let bot: Bool
    let hebrew: Bool

    init(_ id: String, _ character: String, _ name: String, bot: Bool = false, hebrew: Bool = false) {
        self.id = id
        self.character = character
        self.name = name
        self.bot = bot
        self.hebrew = hebrew
    }

    func displayName(hebrew: Bool) -> String {
        return bot ? AmuduCharacters.get(character).name(hebrew: hebrew) : name
    }

    /// Kotlin `copy(id = ..., bot = ...)`.
    func copy(id newId: String? = nil, bot newBot: Bool? = nil) -> Member {
        return Member(newId ?? id, character, name, bot: newBot ?? bot, hebrew: hebrew)
    }
}

/// Android `Actor` (renamed: Swift reserves `Actor` for its concurrency protocol).
final class GameActor {
    let member: Member
    var position: V
    /// Colour-rank points this actor earned in this match (5 for a catch or a successful tag).
    var rankEarned = 0
    /// Kotlin `jumpHeight`/`jumpVelocity`: a practice jump (skill journey only).
    var jumpHeight = 0.0
    var jumpVelocity = 0.0
    var move = V.zero
    var direction = V(0, 1)
    var facing = V(0, 1)
    var penalties = 0
    var suffixes: [String] = []
    var duckUntil = 0.0
    var catchUntil = 0.0
    var catchRecoveryUntil = 0.0
    var catchReadyAt = 0.0
    var catchReach = 1.0
    var catchRoll = 0.0
    var catchProbability = 1.0
    var throwAt = -99.0
    var catchAt = -99.0
    var hitAt = -99.0
    var gait = 0.0
    var actuallyMoving = false
    var spectator = SpectatorReason.none
    var idleStrikes = 0
    var returnAttempts = 0
    var returnQueued = false
    var returnAfterBreak = 0
    var nextThink = 0.0
    var catchDecided = false
    var movementPenaltyTurn = -1

    /// Kotlin `active`: playing, not watching.
    var active: Bool { return spectator == SpectatorReason.none }

    init(member: Member, position: V) {
        self.member = member
        self.position = position
    }

    func fullName() -> String {
        return suffixes.isEmpty ? member.name : suffixes.joined(separator: " ")
    }

    func fullName(hebrew: Bool) -> String {
        return suffixes.isEmpty ? member.displayName(hebrew: hebrew) : suffixes.joined(separator: " ")
    }
}

struct Ball: Equatable {
    var position: V
    var height: Double
    var velocity: V
    var vz: Double
    var holder: String?
    var bounces: Int
    var flightId: String
    var launchAt: Double

    init(_ position: V, _ height: Double, _ velocity: V, _ vz: Double, _ holder: String? = nil, bounces: Int = 0,
         flightId: String = "", launchAt: Double = 0.0) {
        self.position = position
        self.height = height
        self.velocity = velocity
        self.vz = vz
        self.holder = holder
        self.bounces = bounces
        self.flightId = flightId
        self.launchAt = launchAt
    }
}

struct GameEvent: Equatable {
    let id: Int
    let kind: String
    let actor: String
    let text: String
    let at: Double
}

struct Outcome: Equatable {
    let id: String
    let penalties: [String: Int]
    let winners: [String]
    let elapsed: Double
}

enum GameCommand: Equatable {
    case move(V)
    case aim(V)
    /// Kotlin `Command.Select(target, typedName = "")`.
    case select(target: String, typedName: String = "")
    case toss(power: Double, drift: Double)
    /// Kotlin `Command.Jump`: only skill-journey practice uses it.
    case jump
    case catchBall
    case duck
    case shout
    case throwBall(power: Double)
    case end
    /// Kotlin `Command.Pause(value)`: only the last active human can pause a shared match.
    case pause(value: Bool)
    /// Kotlin `Command.RequestReturn`: an inactive watcher asks to rejoin (nickname rules only).
    case requestReturn
    /// Kotlin `Command.ReturnVote(serial, yes)`.
    case returnVote(serial: Int, yes: Bool)
    case say(index: Int)
}

/// Android `Words`: funny-word lists, preset phrases and the name/nickname rules.
enum Words {
    static let en = ["happy", "bouncy", "cosmic", "tiny", "dancing", "sleepy", "sparkly", "flying", "funky", "frog", "turtle", "panda",
                     "noodle", "mango", "pickle", "cloud", "comet", "penguin", "waffle", "banana", "captain", "professor", "super",
                     "moon", "star"]
    static let he = ["הצפרדע", "הקופצנית", "הצב", "המרחף", "הפנדה", "המצחיקה", "המנגו", "הענן", "הפינגווין", "הבננה", "בננה", "הכוכב",
                     "המחייך", "הנודל", "המלפפון", "קפטן", "פרופסור", "חללית", "קופץ", "רוקד", "מנצנץ", "המנצנץ", "קטנטן"]
    static let phrasesEn = ["Nice catch!", "You almost got me!", "Ready for takeoff!", "Oops, slippery fingers!", "That was cosmic!",
                            "Here comes the bouncy ball!"]
    static let phrasesHe = ["תפיסה יפה!", "כמעט תפסת אותי!", "מוכנים להמראה!", "אופס, אצבעות חלקלקות!", "זה היה קוסמי!",
                            "הנה מגיע הכדור הקופצני!"]
    private static let suggestionsEn = ["frog", "banana", "noodle", "panda", "pickle", "waffle"]
    private static let suggestionsHe = ["הצפרדע", "הפנדה", "בננה", "הכוכב", "הצב", "הפינגווין"]

    static func isLetter(_ s: Unicode.Scalar) -> Bool {
        switch s.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter:
            return true
        default:
            return false
        }
    }

    static func isMark(_ s: Unicode.Scalar) -> Bool {
        switch s.properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark:
            return true
        default:
            return false
        }
    }

    static func isNumber(_ s: Unicode.Scalar) -> Bool {
        switch s.properties.generalCategory {
        case .decimalNumber, .letterNumber, .otherNumber:
            return true
        default:
            return false
        }
    }

    /// `Normalizer.normalize(text.trim(), NFKC)`.
    static func nfkcTrim(_ text: String) -> String {
        return Kotlin.trim(text).precomposedStringWithCompatibilityMapping
    }

    /// Private-room nicknames are one Unicode word, never links/control characters.
    static func validSuggestion(_ text: String) -> Bool {
        let word = nfkcTrim(text)
        let count = word.unicodeScalars.count
        if count < 1 || count > 24 { return false }
        if !word.unicodeScalars.contains(where: { isLetter($0) }) { return false }
        return word.unicodeScalars.allSatisfy { isLetter($0) || isMark($0) || isNumber($0) }
    }

    static func suggestion(_ index: Int, hebrew: Bool) -> String {
        let list = hebrew ? suggestionsHe : suggestionsEn
        return list[Kotlin.floorMod(index, 6)]
    }

    static func validName(_ name: String) -> Bool {
        let length = Kotlin.trim(name).utf16.count
        if length < 1 || length > 22 { return false }
        let allowed = name.unicodeScalars.allSatisfy { s in
            isLetter(s) || isMark(s) || isNumber(s) || s == " " || s == "'" || s == "-"
        }
        if name.isEmpty || !allowed { return false }
        return name.unicodeScalars.contains { isLetter($0) }
    }

    /// `NFKC(name.trim().replace(Regex("\\s+"), " ")).lowercase()` (Java `\s` is ASCII whitespace).
    static func normalize(_ name: String) -> String {
        let trimmed = Kotlin.trim(name)
        var view = String.UnicodeScalarView()
        var inSpace = false
        for s in trimmed.unicodeScalars {
            let space = s == " " || s == "\t" || s == "\n" || s.value == 0x0B || s.value == 0x0C || s == "\r"
            if space {
                if !inSpace { view.append(" ") }
                inSpace = true
            } else {
                view.append(s)
                inSpace = false
            }
        }
        return String(view).precomposedStringWithCompatibilityMapping.lowercased()
    }
}
