import XCTest
@testable import MinikSquash

/// Android core/SportsJourneyTest.kt and CourtLanguageTest.kt.
final class SportsJourneyTests: XCTestCase {
    override func tearDown() {
        AppText.configure("en")
        super.tearDown()
    }

    private func make(_ s: Sport, _ step: Int) -> SportsEngine {
        let d = SportsJourney.stage(s, step)
        var used: [String] = ["miniko"]
        func bot(_ id: String, _ team: Int) -> Participant {
            let c = d.bot(step / 30, s, Set(used))
            used.append(c.id)
            return Participant(id, c.id, team, true)
        }
        let roster = s == .squash
            ? [Participant("you", "miniko", 0, false), bot("coach", 1)]
            : [Participant("you", "miniko", 0, false), bot("friend", 0), bot("coach", 1), bot("other", 1)]
        return SportsEngine(sportsConfig(s, control: s == .squash && d.skill != .move ? .beginner : .standard, questionsEnabled: false,
                                         serveControl: .beginner, challengeStep: step), roster)
    }

    func testCataloguesTeachBasicsBeforeCombinedSkills() {
        for s in Sport.allCases {
            let stages = SportsJourney.stages(s)
            XCTAssertEqual(stages.count, 30)
            XCTAssertEqual(Set(stages.map { $0.id }).count, 30)
            XCTAssertTrue(stages.allSatisfy { (5...12).contains($0.base) })
        }
        let pass = SportsJourney.volley.firstIndex { $0.skill == .pass } ?? 99
        let spike = SportsJourney.volley.firstIndex { $0.skill == .spike } ?? -1
        XCTAssertTrue(pass < spike)
    }

    func testIdleCannotWinReturnsAndPauseStopsClocks() throws {
        for s in Sport.allCases {
            for (i, d) in SportsJourney.stages(s).enumerated() where ![.aim, .paint, .order, .serve].contains(d.skill) {
                let e = make(s, i)
                advance(e, seconds: 2.0)
                e.paused = true
                let time = e.clock
                advance(e, seconds: 3.0)
                XCTAssertEqual(e.clock, time)
                XCTAssertFalse(e.command("you", "paused", "jump"))
                e.paused = false
                advance(e, seconds: 40.0)
                let practice = try XCTUnwrap(e.practice)
                XCTAssertEqual(practice.successes, 0, "\(s) \(d.id)")
                XCTAssertTrue(practice.failed, "\(s) \(d.id) must end after misses")
            }
        }
    }

    func testEverySquashStageIsReachableThroughMatchPhysics() throws {
        for cycle in [0, 3] {
            for (i, d) in SportsJourney.squash.enumerated() {
                let e = make(.squash, cycle * 30 + i)
                let p = e.players[0]
                var nonce = 0
                for _ in 0..<(120 * 180) {
                    guard let drill = e.practice else { break }
                    if e.phase != .finished {
                        if !drill.serve && e.ball.active && e.canReturn(p) {
                            let intercept = e.predictIntercept()
                            e.command("you", "m\(nonce)", "move", intercept.x, intercept.y)
                            nonce += 1
                        }
                        let target = drill.targets()[drill.shape ? min(drill.painted.count, drill.goal - 1) : 0]
                        if e.clock > 1.6 && !drill.pending {
                            e.command("you", "h\(nonce)", "wall", target.x, target.y)
                            nonce += 1
                        }
                        e.update(1.0 / 120)
                    }
                }
                let practice = try XCTUnwrap(e.practice)
                XCTAssertTrue(practice.won, "Squash \(d.id) cycle \(cycle): \(practice.successes)/\(practice.goal), \(practice.mistakes) misses")
                XCTAssertEqual(e.earned("you"), 0)
            }
        }
    }

    func testEveryVolleySkillUsesRealContacts() throws {
        for cycle in [0, 3] {
            for i in SportsJourney.volley.indices {
                let e = make(.volley, cycle * 30 + i)
                let d = try XCTUnwrap(e.practice)
                var nonce = 0
                for _ in 0..<(120 * 210) {
                    if e.phase != .finished {
                        if e.ball.active && !d.pending {
                            let dest = d.stage.skill == .block ? Vec(e.ball.p.x, 0.65) : e.predictLanding()
                            e.command("you", "m\(nonce)", "move", dest.x, dest.y)
                            nonce += 1
                        }
                        let target: Vec
                        switch d.stage.skill {
                        case .pass, .set: target = e.players[1].p
                        default: target = d.targets()[0]
                        }
                        let kind: String
                        switch d.stage.skill {
                        case .block: kind = "volley_block"
                        case .spike, .set: kind = "volley_spike"
                        default: kind = "volley_tap"
                        }
                        if !d.pending && e.clock > 1.6 {
                            e.command("you", "h\(nonce)", kind, target.x, target.y)
                            nonce += 1
                        }
                        e.update(1.0 / 120)
                    }
                }
                XCTAssertTrue(d.won, "Volley \(d.stage.id): \(d.successes)/\(d.goal), \(d.mistakes) misses, phase \(e.phase), \(e.reason)")
                XCTAssertEqual(e.earned("you"), 0)
            }
        }
    }

    func testWrongWallTargetsNeverPaintAndOrderMatters() throws {
        let e = make(.squash, 9)
        advance(e, seconds: 2.0)
        e.command("you", "1", "wall", 2.8, 4.4)
        advance(e, seconds: 4.0)
        let practice = try XCTUnwrap(e.practice)
        XCTAssertEqual(practice.successes, 0)
        XCTAssertTrue(practice.painted.isEmpty)
        XCTAssertEqual(practice.mistakes, 1)
    }

    func testPartnersFollowSkillSpecificRankAndExcludeAvatar() {
        for s in Sport.allCases {
            for d in SportsJourney.stages(s) {
                let easy = d.bot(0, s, ["miniko"])
                let later = d.bot(8, s, ["miniko"])
                XCTAssertNotEqual(easy.id, "miniko")
                if d.cooperative { XCTAssertTrue(d.aptitude(easy, s) >= d.aptitude(later, s)) }
                if d.skill == .block { XCTAssertTrue(d.aptitude(easy, s) <= d.aptitude(later, s)) }
            }
        }
    }

    /// Android CourtLanguageTest: every challenge title, brief and role has four translations.
    func testEveryChallengeTitleBriefAndRoleHasFourAdditionalTranslations() {
        for s in Sport.allCases {
            for d in SportsJourney.stages(s) {
                for key in [d.en, d.brief(s, false), d.role(false)] {
                    for language in ["es", "ar", "hi", "nl"] {
                        AppText.configure(language)
                        let row = SportsText.journey(key)
                        XCTAssertNotNil(row, "Missing: \(key)")
                        XCTAssertFalse((row ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
                        XCTAssertNotEqual(row, key)
                    }
                }
            }
        }
    }
}
