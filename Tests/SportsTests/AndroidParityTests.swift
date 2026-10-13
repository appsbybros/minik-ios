import XCTest
@testable import MinikSquash

/// Replays the reference traces of the real Android MinikSports core (android-golden.txt): whole
/// squash and volleyball matches with house players and scripted human input, and daily-journey
/// drills of every skill. Each sample (clock, phase, scores, ball, every athlete, the drill, the
/// reception slow motion and the current question) and every event must match Android.
final class AndroidParityTests: XCTestCase {
    private struct Scenario {
        let name: String
        let config: SportsConfig
        let roster: [Participant]
        let steps: Int
        let every: Int
        let cadence: Int
        let human: String
        let schedule: [(String, Double, Double, Double)]
    }

    private static let lines: [String] = {
        let bundle = Bundle(for: AndroidParityTests.self)
        guard let url = bundle.url(forResource: "android-golden", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        // A Windows checkout may carry CRLF line ends.
        return text.components(separatedBy: "\n").map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }()

    private static func rows(_ kind: String) -> [[String]] {
        return lines.filter { $0.hasPrefix(kind + "|") }.map { $0.components(separatedBy: "|") }
    }

    private func scenario(_ f: [String]) -> Scenario? {
        guard f.count == 22, let sport = Sport(rawValue: f[2]), let teamSize = Int(f[3]), let target = Int(f[4]),
              let control = Control(rawValue: f[6]), let serveControl = Control(rawValue: f[7]), let seed = Int(f[8]),
              let answerMode = AnswerMode(rawValue: f[9]), let serveQuestions = ServeQuestions(rawValue: f[10]),
              let answerSeconds = Int(f[11]), let challengeStep = Int(f[13]), let steps = Int(f[17]), let every = Int(f[18]),
              let cadence = Int(f[19]) else { return nil }
        var c = SportsConfig()
        c.sport = sport
        c.teamSize = teamSize
        c.target = target
        c.arena = f[5]
        c.control = control
        c.serveControl = serveControl
        c.seed = seed
        c.answerMode = answerMode
        c.serveQuestions = serveQuestions
        c.answerSeconds = answerSeconds
        c.questionsEnabled = f[12] == "true"
        c.challengeStep = challengeStep
        c.ballStyle = f[14]
        c.teamColors = f[15].components(separatedBy: ",")
        let roster = f[16].components(separatedBy: ";").compactMap { item -> Participant? in
            let p = item.components(separatedBy: ":")
            guard p.count == 4, let team = Int(p[2]) else { return nil }
            return Participant(p[0], p[1], team, p[3] == "true", p[0] == "you" ? "You" : "")
        }
        let schedule = f[21].isEmpty ? [] : f[21].components(separatedBy: ";").compactMap { item -> (String, Double, Double, Double)? in
            let p = item.components(separatedBy: ",")
            guard p.count == 4, let x = Double(p[1]), let y = Double(p[2]), let power = Double(p[3]) else { return nil }
            return (p[0], x, y, power)
        }
        return Scenario(name: f[1], config: c, roster: roster, steps: steps, every: every, cadence: cadence, human: f[20], schedule: schedule)
    }

    /// The same fields, in the same order, as the harness's `sig(e)`.
    private func signature(_ e: SportsEngine) -> String {
        let b = e.ball
        var s: [String] = ["\(e.clock)", e.phase.name, "\(e.scores[0])", "\(e.scores[1])", "\(e.server)", "\(e.expected)", "\(e.returnTeam)",
                           "\(e.winner)", "\(e.eventId)", "\(e.shotSerial)", "\(e.pointSerial)", "\(e.countdown)",
                           "B", "\(b.p.x)", "\(b.p.y)", "\(b.z)", "\(b.velocity.x)", "\(b.velocity.y)", "\(b.vz)", "\(b.active)",
                           b.hitter.isEmpty ? "-" : b.hitter, "\(b.touches)", "\(b.bounces)", "\(b.serve)"]
        for p in e.players {
            s += ["P", "\(p.p.x)", "\(p.p.y)", "\(p.jump)", p.pose, "\(p.contacts)", "\(p.correct)", "\(p.mistakes)", "\(p.steps)"]
        }
        if let d = e.practice {
            s += ["D", "\(d.successes)", "\(d.mistakes)", "\(d.attempts)", "\(d.pending)", d.painted.isEmpty ? "-" : d.painted.map { String($0) }.joined(separator: ",")]
        }
        s += ["S", "\(e.receptionScale)", "\(e.timeScale)", e.receptionReceiver.isEmpty ? "-" : e.receptionReceiver]
        s += ["Q", e.question.id, e.question.answer]
        return s.joined(separator: " ")
    }

    /// Numbers agree to 1e-6 (relative above 1); words exactly. Kotlin and Swift print doubles
    /// differently ("1.0E-5" / "1e-05"), so numeric tokens are compared as values.
    private func mismatch(_ expected: String, _ actual: String) -> String? {
        let a = expected.split(separator: " ").map(String.init)
        let b = actual.split(separator: " ").map(String.init)
        if a.count != b.count { return "token count \(a.count) vs \(b.count)" }
        for i in a.indices {
            let x = a[i]
            let y = b[i]
            if x == y { continue }
            if x != "true" && x != "false", let u = Double(x), let v = Double(y) {
                if u.isNaN && v.isNaN { continue }
                if abs(u - v) <= 1e-6 * max(1.0, abs(u), abs(v)) { continue }
            }
            return "token \(i): Android \(x), iOS \(y)"
        }
        return nil
    }

    func testMatchesAndDrillsReplayAndroid() {
        let scenarios = AndroidParityTests.rows("SCENARIO")
        XCTAssertEqual(scenarios.count, 29, "android-golden.txt is missing from the test bundle")
        let samples = AndroidParityTests.rows("S")
        let events = AndroidParityTests.rows("E")
        for f in scenarios {
            guard let s = scenario(f) else {
                XCTFail("unreadable scenario " + f.joined(separator: "|"))
                continue
            }
            XCTAssertTrue(s.config.isValid && SportsEngine.validRoster(s.roster, s.config), s.name)
            var expected: [Int: String] = [:]
            for row in samples where row.count == 4 && row[1] == s.name { expected[Int(row[2]) ?? -1] = row[3] }
            let e = SportsEngine(s.config, s.roster, matchId: "golden-\(s.name)")
            var actual: [Int: String] = [0: signature(e)]
            var next = 0
            if s.steps > 0 {
                for k in 1...s.steps {
                    if !s.human.isEmpty && k % s.cadence == 0 {
                        let m = s.schedule[next % s.schedule.count]
                        next += 1
                        e.command(s.human, "n\(k)", m.0, m.1, m.2, m.3)
                    }
                    e.update(1.0 / 60)
                    if k % s.every == 0 { actual[k] = signature(e) }
                    if e.phase == .finished && k % s.every != 0 {
                        actual[k] = signature(e)
                        break
                    }
                    if e.phase == .finished { break }
                }
            }
            XCTAssertEqual(Set(actual.keys), Set(expected.keys), "\(s.name): sampled steps differ")
            for k in expected.keys.sorted() {
                guard let a = actual[k], let x = expected[k] else { continue }
                if let problem = mismatch(x, a) {
                    XCTFail("\(s.name) step \(k): \(problem)\nAndroid: \(x)\niOS:     \(a)")
                    break
                }
            }
            let androidEvents = events.filter { $0.count == 6 && $0[1] == s.name }.map { "\($0[2])|\($0[3])|\($0[4])|\($0[5])" }
            let iosEvents = e.events.map { "\($0.id)|\($0.type)|\($0.player)|\($0.detail)" }
            XCTAssertEqual(iosEvents, androidEvents, "\(s.name): events differ")
        }
    }

    func testJourneyStagesMatchAndroid() {
        let rows = AndroidParityTests.rows("J")
        XCTAssertEqual(rows.count, 180)
        for f in rows {
            guard f.count == 10, let sport = Sport(rawValue: f[1]), let n = Int(f[2]), let goal = Int(f[7]), let radius = Double(f[8]) else {
                XCTFail(f.joined(separator: "|"))
                continue
            }
            let line = f.joined(separator: "|")
            let d = SportsJourney.stage(sport, n)
            let p = CourtPractice(sport, n)
            XCTAssertEqual(d.id, f[3], line)
            XCTAssertEqual(d.skill.name, f[4], line)
            XCTAssertEqual(d.bot(n / 30, sport, ["miniko"]).id, f[5], line)
            XCTAssertEqual(d.bot(n / 30, sport, []).id, f[6], line)
            XCTAssertEqual(p.goal, goal, line)
            XCTAssertEqual(p.radius, radius, accuracy: 1e-12, line)
            let targets = f[9].components(separatedBy: ";").map { $0.components(separatedBy: ",").compactMap { Double($0) } }
            XCTAssertEqual(p.targets().count, targets.count, line)
            for (t, e) in zip(p.targets(), targets) where e.count == 2 {
                XCTAssertEqual(t.x, e[0], accuracy: 1e-12, line)
                XCTAssertEqual(t.y, e[1], accuracy: 1e-12, line)
            }
        }
    }

    func testQuestionsMatchAndroid() {
        let rows = AndroidParityTests.rows("QE")
        XCTAssertEqual(rows.count, 30)
        var engines: [Int: SportsEngine] = [:]
        var drawn: [Int: Int] = [:]
        for f in rows {
            guard f.count == 9, let seed = Int(f[1]), let k = Int(f[2]) else {
                XCTFail(f.joined(separator: "|"))
                continue
            }
            var c = SportsConfig()
            c.sport = .squash
            c.seed = seed
            let e = engines[seed] ?? SportsEngine(c, [Participant("a", "minik", 0, false), Participant("b", "mia", 1, true)])
            engines[seed] = e
            let line = f.joined(separator: "|")
            let q = e.question
            XCTAssertEqual(q.id, f[3], line)
            XCTAssertEqual(q.skill.name, f[4], line)
            XCTAssertEqual(String(q.level), f[5], line)
            XCTAssertEqual(q.en, f[6], line)
            XCTAssertEqual(q.answer, f[7], line)
            XCTAssertEqual(q.options, f[8].components(separatedBy: ";"), line)
            XCTAssertEqual(k, drawn[seed, default: 0], line)
            drawn[seed, default: 0] += 1
            e.newQuestion()
        }
    }

    func testKotlinRandomMatchesAndroid() {
        let rows = AndroidParityTests.rows("R")
        XCTAssertEqual(rows.count, 5)
        for f in rows {
            guard f.count == 7, let seed = Int(f[1]) else {
                XCTFail(f.joined(separator: "|"))
                continue
            }
            let line = f.joined(separator: "|")
            let r = KotlinRandom(seed: Int64(seed))
            XCTAssertEqual((0..<3).map { _ in String(r.nextRawInt()) }, f[2].components(separatedBy: ";"), line)
            for expected in f[3].components(separatedBy: ";") { XCTAssertEqual(r.nextDouble(), Double(expected) ?? -1, line) }
            XCTAssertEqual((0..<3).map { _ in String(r.nextInt(4)) }, f[4].components(separatedBy: ";"), line)
            for expected in f[5].components(separatedBy: ";") { XCTAssertEqual(r.nextDouble(-0.25, 0.25), Double(expected) ?? -1, line) }
            for expected in f[6].components(separatedBy: ";") { XCTAssertEqual(r.nextDouble(-0.001, 0.001), Double(expected) ?? -1, line) }
        }
    }

    /// Android's `hypot` is Java's `StrictMath.hypot` (fdlibm); the values come from Java. The first
    /// four differ in the last bit from `sqrt(x * x + y * y)`; such a bit once moved Beginner
    /// assistance in squash-human-beginner.
    func testHypotMatchesJavaStrictMath() {
        let cases: [(Double, Double, Double)] = [
            (0.1444916969699659, -1.1269443794222038, 1.136169654939154),
            (-0.8769200625890525, 0.5775042890133476, 1.05),
            (3.5232606575682, 3.365558500524903, 4.872406970032711),
            (-1.3996915157896288, -0.6928767484492634, 1.561798491456274),
            (3.0, 4.0, 5.0),
            (-3.0, 0.0, 3.0),
            (0.0, -0.0, 0.0),
            (1e300, 1e300, 1.4142135623730952e300),
            (1e-200, 3e-200, 3.1622776601683794e-200)
        ]
        for (x, y, expected) in cases {
            XCTAssertEqual(KotlinMath.hypot(x, y).bitPattern, expected.bitPattern, "hypot(\(x), \(y))")
        }
        XCTAssertEqual(KotlinMath.hypot(.infinity, .nan), .infinity)
        XCTAssertTrue(KotlinMath.hypot(.nan, 1.0).isNaN)
    }
}
