import XCTest
@testable import MinikSplash

/// With the same seed and question secret, iOS deals the same private questions, option order,
/// balloon colours and layouts (one place / all over) and house-player timing as Android.
final class EngineParityTests: XCTestCase {
    private func engine(_ variant: Int, _ seed: Int64) -> SplashEngine {
        let chars = ["miniko", "minik", "kyra", "flare", "gaya", "mia"]
        var members: [Member] = []
        for i in 0..<6 {
            var subjects: Set<Topic> = [.math]
            if variant == 2 && i % 2 == 0 { subjects.insert(.world) }
            let settings = PlayerSettings(walk: .easy, throwing: .easy, arena: .beach, court: true,
                                          balloons: variant == 1 ? .allOver : .onePlace, subjects: subjects)
            members.append(Member("p\(i)", chars[i], team: i / 3, bot: false, name: chars[i], hebrew: false, settings: settings))
        }
        // The vectors were produced with Android's 20 x 20 arena of 2026-10-12 (now the online room size).
        var config = SplashConfig()
        config.width = 20.0
        config.depth = 20.0
        return SplashEngine(members: members, mode: .teams, topic: .math, seed: seed, config: config, hebrew: false,
                            profiles: [:], matchId: "local-\(seed)")
    }

    func testQuestionLayoutsMatchAndroid() {
        let rows = AndroidGolden.rows(AndroidGolden.engine)
        XCTAssertEqual(rows.count, 3 * 3 * 6)
        var engines: [Int64: SplashEngine] = [:]
        let variants: [Int64: Int] = [880: 0, 12345: 1, 4242: 2]
        for row in rows {
            let f = row.components(separatedBy: "|")
            guard f.count == 11, let seed = Int64(f[1]), let variant = variants[seed] else {
                XCTFail(row)
                continue
            }
            let e: SplashEngine
            if let existing = engines[seed] {
                e = existing
            } else {
                e = engine(variant, seed)
                e.restoreQuestionSecret(0)
                e.practice = true
                engines[seed] = e
            }
            let id = f[3]
            e.resetPracticeQuestion(id)
            guard let a = e.actor(id), let q = a.question else {
                XCTFail(row)
                continue
            }
            XCTAssertEqual(q.id, f[4], row)
            XCTAssertEqual(q.skill.rawValue, f[5], row)
            XCTAssertEqual(q.en, f[6], row)
            XCTAssertEqual(q.answer, f[7], row)
            XCTAssertEqual(q.options, f[8].components(separatedBy: ";"), row)
            XCTAssertEqual(a.nextBotThink, Double(f[9]) ?? -1, accuracy: 1e-9, row)
            let choices = f[10].split(separator: ";").map { String($0) }
            XCTAssertEqual(choices.count, a.choices.count, row)
            for (choice, expected) in zip(a.choices, choices) {
                let p = expected.components(separatedBy: ",")
                guard p.count == 5 else {
                    XCTFail(expected)
                    continue
                }
                XCTAssertEqual(String(choice.index), p[0], row)
                XCTAssertEqual(choice.text, p[1], row)
                XCTAssertEqual(choice.position.x, Double(p[2]) ?? -1, accuracy: 1e-9, row)
                XCTAssertEqual(choice.position.y, Double(p[3]) ?? -1, accuracy: 1e-9, row)
                XCTAssertEqual(String(choice.color), p[4], row)
            }
        }
    }
}
