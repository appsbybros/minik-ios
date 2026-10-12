import XCTest
@testable import MinikSquash

/// Kotlin `SportsConfig(...)` with named arguments and Android's defaults (`serveControl = control`).
func sportsConfig(_ sport: Sport = .squash, teamSize: Int = 2, target: Int = 11, arena: String = "beach", control: Control = .beginner,
                  seed: Int = 17, tutorial: Bool = false, answerMode: AnswerMode = .serves, serveQuestions: ServeQuestions = .fullTime,
                  answerSeconds: Int = 15, questionsEnabled: Bool = true, serveControl: Control? = nil, challengeStep: Int = -1) -> SportsConfig {
    var c = SportsConfig()
    c.sport = sport
    c.teamSize = teamSize
    c.target = target
    c.arena = arena
    c.control = control
    c.seed = seed
    c.tutorial = tutorial
    c.answerMode = answerMode
    c.serveQuestions = serveQuestions
    c.answerSeconds = answerSeconds
    c.questionsEnabled = questionsEnabled
    c.serveControl = serveControl ?? control
    c.challengeStep = challengeStep
    return c
}

/// Kotlin `repeat(n) { e.update(dt) }`.
func advance(_ e: SportsEngine, steps: Int, dt: Double) {
    for _ in 0..<max(steps, 0) { e.update(dt) }
}

/// Kotlin `repeat((seconds * 120).toInt()) { e.update(1.0 / 120) }`.
func advance(_ e: SportsEngine, seconds: Double) {
    advance(e, steps: KotlinNumber.int(seconds * 120), dt: 1.0 / 120)
}
