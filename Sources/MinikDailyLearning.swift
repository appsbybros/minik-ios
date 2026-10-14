import Foundation

/// The day a daily goal belongs to, written as Android's
/// SimpleDateFormat("yyyy-MM-dd", Locale.ROOT) writes it in the device's time zone.
enum MinikLearningDay {
    static func string(for date: Date = Date(), timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04ld-%02ld-%02ld", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

// MARK: - Minik Plus and Minik Plus English: five little wins a day

/// Android Minik helpers/DailyLearning.kt (a4ea9be): five "little wins" a day for each
/// child and learned language. A play that raises the child's points is one win; points
/// that stay the same or go down add nothing. A local celebration only: it never adds
/// leaderboard points, and a day off takes nothing away.
enum MinikDailyLearningPolicy {
    static let dailyGoal = 5
}

/// The playing child's little wins today, per learned language. The value lives under one
/// per-child key (ChildProfileStoredKey.learnerKeys), so each child keeps their own, as
/// Android keys them by the child's slot.
struct MinikDailyLearningRepository {
    private struct Entry: Codable, Equatable {
        var day: String
        var count: Int
    }

    private let userDefaults: UserDefaults
    private let storageKey: String

    init(product: ProductVariant, userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        storageKey = Self.storageKey(for: product)
    }

    static func storageKey(for product: ProductVariant) -> String {
        "minik.daily-learning.v1.\(product.rawValue)"
    }

    /// Android DailyLearning.count: today's wins in this learned language, 0 on a new day.
    func count(language: LanguageIdentifier, day: String = MinikLearningDay.string()) -> Int {
        guard let entry = load()[language.rawValue], entry.day == day else { return 0 }
        return min(MinikDailyLearningPolicy.dailyGoal, max(0, entry.count))
    }

    /// Android DailyLearning.record: a rise in points adds one win (at most five a day).
    /// True only for the win that completes today's five.
    @discardableResult
    func record(
        language: LanguageIdentifier,
        previousPoints: Int64,
        nextPoints: Int64,
        day: String = MinikLearningDay.string()
    ) -> Bool {
        guard nextPoints > previousPoints else { return false }
        let goal = MinikDailyLearningPolicy.dailyGoal
        let before = count(language: language, day: day)
        let after = min(goal, before + 1)
        var entries = load()
        entries[language.rawValue] = Entry(day: day, count: after)
        save(entries)
        return before < goal && after == goal
    }

    private func load() -> [String: Entry] {
        guard let data = userDefaults.data(forKey: storageKey),
              let entries = try? JSONDecoder().decode([String: Entry].self, from: data) else {
            return [:]
        }
        return entries
    }

    private func save(_ entries: [String: Entry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        userDefaults.set(data, forKey: storageKey)
    }
}

// MARK: - Minik Math Plus: the daily math journey

/// Android Minik Math Plus core/MathDaily.kt and AppState's daily route (7682b75): the
/// journey visits ten scored activities in turn, at the learner's current level. A stage
/// needs three correct answers in the first round of ten, four in the second and five from
/// then on. Facts tables, Learn Math and Ping Pong never count.
enum MathDailyJourneyPolicy {
    static let activities: [MathProductionActivityID] = [
        .visualToAnswer, .answerToRepresentation, .buildQuantity, .buildNumber, .mathPairs,
        .mathMemory, .buildMath, .mathSoccer, .mathTower, .mathMixed
    ]
    /// Practice stars for each completed stage.
    static let stageStars = 40
    /// More practice stars for the first stage completed on a day.
    static let firstStageOfTheDayBonus = 30

    static func activity(forStep step: Int) -> MathProductionActivityID {
        let count = activities.count
        return activities[((step % count) + count) % count]
    }

    static func goal(forStep step: Int) -> Int {
        3 + min(2, max(0, step / activities.count))
    }

    /// Android AppState.recordAnswer feeds the journey a correct first answer; Pairs and
    /// Memory record every matched pair as correct, so a match counts there whatever came
    /// before it.
    static func counts(_ attempt: ActivityAttemptData) -> Bool {
        guard attempt.result == .correct else { return false }
        switch attempt.activityFamily {
        case .pairs, .memory:
            return true
        default:
            return attempt.isFirstAttempt
        }
    }
}

/// Android's daily_step, daily_answers, daily_stars, daily_day and daily_receipts. Wrong
/// answers never take progress away; leaving an activity keeps the answers counted so far.
struct MathDailyJourneyState: Codable, Equatable, Sendable {
    var step = 0
    var answers = 0
    var stars = 0
    /// The day the last stage was completed: the first stage of a new day earns the bonus.
    var lastCompletedDay = ""
    /// One receipt per completed stage ("round/activity"), so a stage never pays twice.
    var receipts: [String] = []

    var activity: MathProductionActivityID {
        MathDailyJourneyPolicy.activity(forStep: step)
    }

    var goal: Int {
        MathDailyJourneyPolicy.goal(forStep: step)
    }

    /// Android AppState.recordDaily for a counted answer. True when the answer completes
    /// the stage: its stars are paid once and the journey moves on to the next activity.
    mutating func recordCountedAnswer(on day: String) -> Bool {
        answers += 1
        guard answers >= goal else { return false }
        let receipt = "\(step / MathDailyJourneyPolicy.activities.count)/\(activity.rawValue)"
        if !receipts.contains(receipt) {
            receipts.append(receipt)
            stars += MathDailyJourneyPolicy.stageStars
                + (lastCompletedDay == day ? 0 : MathDailyJourneyPolicy.firstStageOfTheDayBonus)
            lastCompletedDay = day
        }
        step += 1
        answers = 0
        return true
    }
}

struct MathDailyJourneyRepository {
    private let userDefaults: UserDefaults
    private let storageKey: String

    init(userDefaults: UserDefaults = .standard, storageKey: String = "minik.math-daily-journey.v1") {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
    }

    func load() -> MathDailyJourneyState {
        guard let data = userDefaults.data(forKey: storageKey),
              let state = try? JSONDecoder().decode(MathDailyJourneyState.self, from: data) else {
            return MathDailyJourneyState()
        }
        return state
    }

    func save(_ state: MathDailyJourneyState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        userDefaults.set(data, forKey: storageKey)
    }
}
