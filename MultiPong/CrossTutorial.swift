import Foundation

/// Android cross/CrossTutorial.kt (MinikCrossPong 5c1aa4d): the interactive guide for the 3/4-player
/// table. Real input, contact and landing rules decide success; nothing scores. Show me / Try it yourself / Try again, like the
/// classic guide. EN/HE texts verbatim; the other languages through `MPText`, call by call as on Android.
final class CrossTutorial {
    enum Phase { case intro, info, explain, demo, attempt, result }
    enum Kind { case table, serve, returning, team, scoring }
    struct Lesson {
        var kind: Kind
        var expected: Int? = nil
        var server: Int? = nil
    }
    private static let characters = ["minik", "kyra", "mia"]
    let players: Int
    let control: CrossControl
    private let hebrew: Bool
    private let geometry: CrossGeometry
    /// Left → right as seen from the learner.
    private let left: Int
    private let right: Int
    private let ahead: Int?
    let lessons: [Lesson]
    private(set) var index = 0
    var lesson: Lesson { lessons[index] }
    private(set) var phase = Phase.intro
    var changed = false
    let names: [String]
    private(set) var engine: CrossEngine
    private var demonstrated = false
    var highlight: Int? {
        switch phase {
        case .explain, .demo, .attempt, .result: return lesson.expected
        case .intro, .info: return nil
        }
    }
    var acceptsInput: Bool { phase == .attempt }

    init(players requested: Int, control: CrossControl, names baseNames: [String], hebrew: Bool = false) {
        let n = min(4, max(3, requested))
        players = n; self.control = control; self.hebrew = hebrew
        let g = CrossGeometry(n)
        geometry = g
        let order = CrossAimMap(g).opponents(0)
        let leftSeat = order[0], rightSeat = order[order.count - 1]
        let aheadSeat: Int? = n == 4 ? order[1] : nil
        left = leftSeat; right = rightSeat; ahead = aheadSeat
        var built: [Lesson] = [Lesson(kind: .table), Lesson(kind: .serve, expected: rightSeat),
                               Lesson(kind: .returning, expected: leftSeat, server: rightSeat), Lesson(kind: .returning, expected: rightSeat, server: leftSeat)]
        if let aheadSeat { built.append(Lesson(kind: .returning, expected: aheadSeat, server: leftSeat)) }
        built.append(Lesson(kind: .team))
        built.append(Lesson(kind: .scoring))
        lessons = built
        let allNames = [baseNames.first ?? "You"] + CrossTutorial.characters.prefix(n - 1).map { CrossTutorial.character($0).name(hebrew: hebrew) }
        names = allNames
        engine = CrossTutorial.make(players: n, control: control, names: allNames, hebrew: hebrew, lesson: built[0])
    }
    private static func character(_ id: String) -> MPHousePlayer { MPRoster.find(id) ?? MPRoster.all[0] }
    private static func make(players: Int, control: CrossControl, names: [String], hebrew: Bool, lesson: Lesson) -> CrossEngine {
        var seats = [CrossSeat(index: 0, kind: .local, id: "learner", name: names.first ?? "You")]
        for (i, id) in characters.prefix(players - 1).enumerated() {
            let c = character(id)
            seats.append(CrossSeat(index: i + 1, kind: .house, id: "bot_" + id, name: c.name(hebrew: hebrew), bot: c.profile, characterId: id))
        }
        let exercise: CrossExercise
        switch lesson.kind {
        case .serve: exercise = CrossExercise(drill: .serve, expected: lesson.expected)
        case .returning: exercise = CrossExercise(drill: .returning, expected: lesson.expected, server: lesson.server)
        case .table, .team, .scoring: exercise = CrossExercise(drill: .serve)
        }
        let engine = CrossEngine(seats: seats, control: control, target: 5, seed: 42, exercise: exercise)
        engine.paused = true
        return engine
    }
    private func make() -> CrossEngine { CrossTutorial.make(players: players, control: control, names: names, hebrew: hebrew, lesson: lesson) }
    private var firstPhase: Phase { [Kind.table, .team, .scoring].contains(lesson.kind) ? .info : .explain }
    @discardableResult func next() -> Bool {
        if phase != .intro {
            if index == lessons.count - 1 { return false }
            index += 1
        }
        phase = firstPhase
        engine = make()
        return true
    }
    /// The card before this one: a lesson's result or practice goes back to its explanation, an explanation to the previous
    /// lesson, the first lesson to the introduction.
    var canGoBack: Bool { phase != .intro }
    func back() {
        switch phase {
        case .result, .demo, .attempt: phase = firstPhase
        default:
            if index == 0 { phase = .intro }
            else { index -= 1; phase = firstPhase }
        }
        engine = make()
    }
    /// The control level this tour teaches (the one chosen in Settings).
    func controlName(_ he: Bool) -> String {
        switch control {
        case .beginner: return MPText.t("Beginner", "מתחילים", he)
        case .standard: return MPText.t("Standard", "רגילה", he)
        case .pro: return MPText.t("Pro", "מקצועני", he)
        }
    }
    func demo() { engine = make(); phase = .demo; demonstrated = false }
    func practice() { engine = make(); phase = .attempt }
    private func drag(_ target: Int?) -> Double {
        if target == left { return players == 4 ? -80 : -55 }
        if target == right { return players == 4 ? 80 : 55 }
        return 0
    }
    func update() {
        if phase == .demo && !demonstrated { drive() }
        if engine.trainingResult != nil && (phase == .demo || phase == .attempt) {
            phase = phase == .demo ? .explain : .result
            engine.paused = true; changed = true
        }
    }
    private func ballAfter(_ ticks: Int) -> MPPoint {
        let probe = CrossBall(geometry, tuning: engine.physics, initial: engine.ballState)
        for _ in 0..<ticks { probe.step(CrossBall.substep) }
        return probe.position
    }
    /// Scripted input through the same touch API the finger uses.
    private func drive() {
        let e = engine
        switch lesson.kind {
        case .serve:
            guard e.status == .yourServe && e.trainingTime >= 0.8 else { return }
            demonstrated = true
            if control == .pro {
                let spot = geometry.toView(0, e.serveSpot(0))
                e.touch(geometry.fromView(0, spot + MPPoint(0, 0.10)))
                e.touch(geometry.fromView(0, spot - MPPoint(0, 0.04)), velocity: MPPoint(0.42, -1.0), down: false)
                e.endTouch()
            } else {
                let at = geometry.fromLocal(0, 0.15, 0.8)
                e.touch(at)
                e.touch(at, drag: MPPoint(drag(lesson.expected), 0), down: false)
                e.endTouch()
            }
        case .returning:
            guard e.referee.phase == .receivable && e.referee.receiver == 0 else { return }
            if control == .pro {
                let soon = ballAfter(8)
                if !geometry.inStrikeZone(0, soon) || geometry.toLocal(0, soon).v < CrossGeometry.reach - 0.25 { return }
                demonstrated = true
                let p = geometry.toView(0, soon)
                let lateral: Double
                if lesson.expected == left { lateral = players == 4 ? -0.44 : -0.33 }
                else if lesson.expected == right { lateral = players == 4 ? 0.44 : 0.33 }
                else { lateral = 0 }
                let forward = lesson.expected == ahead ? 0.9 : 0.72
                e.touch(geometry.fromView(0, p + MPPoint(0, 0.07)))
                e.touch(geometry.fromView(0, p - MPPoint(0, 0.05)), velocity: MPPoint(lateral, -forward), down: false)
                e.endTouch()
            } else {
                demonstrated = true
                let path = ballAfter(25)
                e.touch(path)
                e.touch(path, drag: MPPoint(drag(lesson.expected), 0), down: false)
                e.endTouch()
            }
        case .table, .team, .scoring: break
        }
    }
    private func who(_ seat: Int?) -> String {
        guard let seat, seat >= 0, seat < names.count else { return "" }
        return names[seat]
    }
    private func side(_ seat: Int?, _ he: Bool) -> String {
        if seat == left { return MPText.t("on your left", "משמאל", he) }
        if seat == right { return MPText.t("on your right", "מימין", he) }
        return MPText.t("straight ahead", "מולכם", he)
    }
    func card(_ he: Bool) -> (title: String, message: String) {
        func tr(_ en: String, _ hebrewText: String) -> String { MPText.t(en, hebrewText, he) }
        let dragHint: String
        switch control {
        case .beginner:
            dragHint = tr("Keep your paddle in the ball's path: it hits by itself. To choose the player, swipe a little LEFT or RIGHT any time before the ball reaches you; the 🎯 shows who will get it. No swipe sends it straight ahead.",
                          "השאירו את המחבט במסלול הכדור: החבטה אוטומטית. כדי לבחור שחקן, החליקו מעט שמאלה או ימינה בכל רגע לפני שהכדור מגיע אליכם; ה־🎯 מראה מי יקבל אותו. בלי החלקה הכדור הולך ישר.")
        case .standard:
            dragHint = tr("Tap when the ball reaches your paddle. Drag sideways to choose the player; a faster drag hits harder.", "הקישו כשהכדור מגיע למחבט. גררו הצידה כדי לבחור שחקן; גרירה מהירה חזקה יותר.")
        case .pro:
            dragHint = tr("Swipe through the ball. The swipe's angle picks the player, its speed sets the power — too wide or too hard goes out.", "החליקו דרך הכדור. זווית ההחלקה בוחרת את השחקן ומהירותה את העוצמה — רחב או חזק מדי יוצא החוצה.")
        }
        var title = ""
        var message = ""
        switch phase {
        case .intro:
            title = tr("Let's play Multiplayer Ping Pong!", "בואו נשחק פינג פונג מרובה משתתפים!")
            message = tr("\(players) players share one table and one ball. You are always at the bottom. Send the ball to ANY other player — everybody plays until someone reaches the target score.",
                         "\(players) שחקנים חולקים שולחן אחד וכדור אחד. אתם תמיד למטה. שלחו את הכדור לכל שחקן אחר — כולם משחקים עד שמישהו מגיע לניקוד היעד.")
        case .info:
            if lesson.kind == .team {
                title = CrossText.setTitle(he)
                message = CrossText.setHelp(he)
            } else if lesson.kind == .table {
                title = tr("Your table", "השולחן שלכם")
                message = tr("Each player owns one colored arm of the \(players == 4 ? "cross" : "Y") table. The nets run between the arms. A shot must clear the net and land on ANOTHER player's color. The yellow outline shows who the ball is going to.",
                             "לכל שחקן זרוע צבעונית משלו בשולחן המשותף. הרשתות עוברות בין הזרועות. החבטה צריכה לעבור מעל הרשת ולנחות בצבע של שחקן אחר. המסגרת הצהובה מראה אל מי הכדור בדרך.")
            } else {
                title = tr("How points work", "איך סופרים נקודות")
                message = tr("If someone misses your good shot: you +1, they −1.\nIf your shot hits the net, lands out or on your own side: you −1, nobody else changes.\nScores never go below 0 — at 0 a mistake just ends the rally.\nThe serve moves to the next player after every rally. First to the target wins!",
                             "אם מישהו מחמיץ חבטה טובה שלכם: אתם +1, הם −1.\nאם החבטה שלכם פוגעת ברשת, יוצאת או נוחתת בצד שלכם: אתם −1, לאף אחד אחר אין שינוי.\nהניקוד לא יורד מתחת ל־0 — ב־0 טעות רק מסיימת את הראלי.\nההגשה עוברת לשחקן הבא אחרי כל ראלי. הראשון שמגיע ליעד מנצח!")
            }
        case .explain:
            if lesson.kind == .serve {
                title = tr("Serve", "הגשה")
                if control == .pro {
                    message = tr("Swipe up through the ball. Serve to \(who(lesson.expected)) \(side(lesson.expected, false)): the ball bounces once on your side, then on theirs.",
                                 "החליקו למעלה דרך הכדור. הגישו אל \(who(lesson.expected)) \(side(lesson.expected, true)): הכדור קופץ פעם אחת בצד שלכם ואז אצלם.")
                } else {
                    message = tr("Tap your side of the table, then drag sideways toward \(who(lesson.expected)) \(side(lesson.expected, false)) before lifting your finger. The ball bounces once on your side, then on theirs.",
                                 "הקישו בצד שלכם של השולחן וגררו הצידה לעבר \(who(lesson.expected)) \(side(lesson.expected, true)) לפני שמרימים את האצבע. הכדור קופץ פעם אחת בצד שלכם ואז אצלם.")
                }
            } else {
                title = tr("Return the ball to \(who(lesson.expected))", "החזרה אל \(who(lesson.expected))")
                message = tr("\(who(lesson.server)) sends you the ball. Return it to \(who(lesson.expected)) \(side(lesson.expected, false)). \(dragHint)",
                             "\(who(lesson.server)) שולח/ת לכם את הכדור. החזירו אותו אל \(who(lesson.expected)) \(side(lesson.expected, true)). \(dragHint)")
            }
            message += "\n\n" + tr("Practice never costs points.", "בתרגול לא מפסידים נקודות.")
        case .result:
            let r = engine.trainingResult
            if r?.success == true {
                title = tr("Well done!", "כל הכבוד!")
                message = tr("The ball reached \(who(lesson.expected)).", "הכדור הגיע אל \(who(lesson.expected)).")
            } else {
                title = tr("Let's try again!", "בואו ננסה שוב!")
                if r?.kind == .net { message = tr("That hit the net. Hit a little later or gentler.", "הכדור פגע ברשת. נסו קצת מאוחר יותר או בעדינות.") }
                else if r?.kind == .out || r?.kind == .ownSide { message = tr("That landed out. Use a smaller sideways drag.", "הכדור יצא. נסו גרירה קטנה יותר הצידה.") }
                else if r?.kind == .badServe { message = tr("Swipe upward through the ball to serve.", "החליקו למעלה דרך הכדור כדי להגיש.") }
                else if r?.kind == .missed { message = tr("The ball got past you. \(dragHint)", "הכדור עבר אתכם. \(dragHint)") }
                else if let receiver = r?.receiver {
                    message = tr("It went to \(who(receiver)). Aim \(side(lesson.expected, false)) for \(who(lesson.expected)).",
                                 "הכדור הגיע אל \(who(receiver)). כוונו \(side(lesson.expected, true)) אל \(who(lesson.expected)).")
                } else { message = dragHint }
            }
        case .demo, .attempt: break
        }
        // Android: the English line is looked up first (its control name is already translated), then chosen against Hebrew.
        let prefix = MPText.t(MPText.t("Controls: \(controlName(false)) (change it in Settings ⚙)\n\n"), "רמת שליטה: \(controlName(true)) (אפשר לשנות בהגדרות ⚙)\n\n", he)
        return (title, prefix + message)
    }
    func statusText(_ he: Bool) -> String {
        func tr(_ en: String, _ hebrewText: String) -> String { MPText.t(en, hebrewText, he) }
        let step = "\(index + 1)/\(lessons.count) · \(controlName(he)) · "
        switch phase {
        case .demo: return step + tr("Watch how it's done", "צפו איך עושים את זה")
        case .attempt: return step + tr("Your turn! Send it to \(who(lesson.expected))", "תורכם! שלחו אל \(who(lesson.expected))")
        default: return step + tr("How to play", "איך משחקים")
        }
    }
}
