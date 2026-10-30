import Foundation

/// The day the daily math journey belongs to, written as Android's
/// SimpleDateFormat("yyyy-MM-dd", Locale.ROOT) writes it in the device's time zone.
enum MinikLearningDay {
    static func string(for date: Date = Date(), timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04ld-%02ld-%02ld", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
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
