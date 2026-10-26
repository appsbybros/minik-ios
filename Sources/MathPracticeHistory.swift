import Foundation

/// Android Minik Math Plus core/PracticeHistory.kt PracticeRecord (dc12a5c): what one activity
/// was practised at one level on this device. It sits beside points, rewards and the automatic
/// level and never changes them. Accuracy waits for five answers and uses the latest twenty.
struct MathPracticeRecord: Equatable, Sendable {
    static let recentLimit = 20
    static let minimumAnswersForAccuracy = 5

    let activity: MathProductionActivityID
    let levelID: MathCurriculumLevelID
    var attempts: Int
    var correct: Int
    var rounds: Int
    /// The latest answers, oldest first: "1" for a correct answer, "0" for another.
    var recent: String

    init(
        activity: MathProductionActivityID,
        levelID: MathCurriculumLevelID,
        attempts: Int = 0,
        correct: Int = 0,
        rounds: Int = 0,
        recent: String = ""
    ) {
        self.activity = activity
        self.levelID = levelID
        self.attempts = attempts
        self.correct = correct
        self.rounds = rounds
        self.recent = recent
    }

    /// The percent of the recent answers that were correct, or nil before five answers.
    var accuracy: Int? {
        guard recent.count >= Self.minimumAnswersForAccuracy else { return nil }
        let correctCount = recent.filter { $0 == "1" }.count
        return Int(100.0 * Double(correctCount) / Double(recent.count))
    }

    /// 1 for M1 ... 10 for M10, as the Parent Area names the levels.
    var levelNumber: Int {
        Int(levelID.rawValue.dropFirst()) ?? 1
    }

    func answering(_ isCorrect: Bool) -> MathPracticeRecord {
        var next = self
        next.attempts += 1
        if isCorrect { next.correct += 1 }
        next.recent = String((recent + (isCorrect ? "1" : "0")).suffix(Self.recentLimit))
        return next
    }

    func completingRound() -> MathPracticeRecord {
        var next = self
        next.rounds += 1
        return next
    }
}

/// Android PracticeHistory: the saved form, its strict reading and the one suggestion for the
/// parent. A row that does not read back exactly is dropped, so an old install or a damaged
/// value starts with no history instead of an invented one.
enum MathPracticeHistory {
    /// The scored activities of the daily journey (Android MathDaily.activities).
    static var activities: [MathProductionActivityID] {
        MathDailyJourneyPolicy.activities
    }

    /// Android AppState.recordAnswer is called with the first answer to a question; Pairs and
    /// Memory record every matching attempt.
    static func counts(_ attempt: ActivityAttemptData) -> Bool {
        switch attempt.activityFamily {
        case .pairs, .memory:
            return true
        default:
            return attempt.isFirstAttempt
        }
    }

    /// One line per record: activity|level|attempts|correct|rounds|recent.
    static func encode(_ records: [MathPracticeRecord]) -> String {
        records.map { record in
            [
                record.activity.rawValue, record.levelID.rawValue, String(record.attempts),
                String(record.correct), String(record.rounds), record.recent
            ].joined(separator: "|")
        }
        .joined(separator: "\n")
    }

    static func decode(_ raw: String) -> [MathPracticeRecord] {
        var records: [MathPracticeRecord] = []
        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let record = decodeLine(String(line)),
                  !records.contains(where: { $0.activity == record.activity && $0.levelID == record.levelID }) else {
                continue
            }
            records.append(record)
        }
        return records
    }

    /// Android PracticeHistory.recommended: at the current level, the activity whose recent
    /// accuracy is lowest under 80%; otherwise the one with the fewest answers at that level.
    static func recommended(
        _ records: [MathPracticeRecord],
        levelID: MathCurriculumLevelID
    ) -> MathProductionActivityID {
        let current = records.filter { $0.levelID == levelID }
        let needingPractice = current.compactMap { record -> (activity: MathProductionActivityID, accuracy: Int)? in
            guard let accuracy = record.accuracy, accuracy < 80 else { return nil }
            return (record.activity, accuracy)
        }
        if let weakest = needingPractice.min(by: { $0.accuracy < $1.accuracy }) {
            return weakest.activity
        }
        func attempts(_ activity: MathProductionActivityID) -> Int {
            current.first(where: { $0.activity == activity })?.attempts ?? 0
        }
        return activities.min(by: { attempts($0) < attempts($1) }) ?? .visualToAnswer
    }

    /// Whether the suggestion is "a little more practice here" rather than "explore".
    static func needsPractice(
        _ activity: MathProductionActivityID,
        in records: [MathPracticeRecord],
        levelID: MathCurriculumLevelID
    ) -> Bool {
        records.contains { record in
            record.activity == activity && record.levelID == levelID
                && (record.accuracy.map { $0 < 80 } ?? false)
        }
    }

    private static func decodeLine(_ line: String) -> MathPracticeRecord? {
        let parts = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 6,
              let activity = MathProductionActivityID(rawValue: parts[0]),
              activities.contains(activity),
              !parts[1].isEmpty,
              MathCurriculumPolicy.levels.contains(where: { $0.id.rawValue == parts[1] }),
              let attempts = Int(parts[2]),
              let correct = Int(parts[3]),
              let rounds = Int(parts[4]) else {
            return nil
        }
        let recent = parts[5]
        guard attempts >= 0,
              (0...attempts).contains(correct),
              rounds >= 0,
              recent.count <= MathPracticeRecord.recentLimit,
              recent.count <= attempts,
              recent.allSatisfy({ $0 == "0" || $0 == "1" }) else {
            return nil
        }
        return MathPracticeRecord(
            activity: activity,
            levelID: MathCurriculumLevelID(rawValue: parts[1]),
            attempts: attempts,
            correct: correct,
            rounds: rounds,
            recent: recent
        )
    }
}

/// Android AppState's "practice_records_v1", in UserDefaults. The record that changed moves to
/// the end, so the newest practice comes last and the parent screen shows it first.
struct MathPracticeHistoryRepository {
    private let userDefaults: UserDefaults
    private let storageKey: String

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = "minik.math.practice-records.v1"
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
    }

    func load() -> [MathPracticeRecord] {
        MathPracticeHistory.decode(userDefaults.string(forKey: storageKey) ?? "")
    }

    func save(_ records: [MathPracticeRecord]) {
        userDefaults.set(MathPracticeHistory.encode(records), forKey: storageKey)
    }

    func recordAnswer(
        _ isCorrect: Bool,
        activity: MathProductionActivityID,
        levelID: MathCurriculumLevelID
    ) {
        update(activity: activity, levelID: levelID) { $0.answering(isCorrect) }
    }

    /// Android completePracticeRound: a finished round or a completed daily stage.
    func recordRound(activity: MathProductionActivityID, levelID: MathCurriculumLevelID) {
        update(activity: activity, levelID: levelID) { $0.completingRound() }
    }

    private func update(
        activity: MathProductionActivityID,
        levelID: MathCurriculumLevelID,
        _ change: (MathPracticeRecord) -> MathPracticeRecord
    ) {
        guard MathPracticeHistory.activities.contains(activity) else { return }
        var records = load()
        let previous = records.first { $0.activity == activity && $0.levelID == levelID }
            ?? MathPracticeRecord(activity: activity, levelID: levelID)
        records.removeAll { $0.activity == activity && $0.levelID == levelID }
        records.append(change(previous))
        save(records)
    }
}
