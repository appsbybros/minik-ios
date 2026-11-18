import Foundation

enum LanguageAutoActivity: String, Codable, Hashable, Sendable {
    case write
    case tower
    case soccer

    var minimumAttempts: Int {
        switch self {
        case .write: return 100
        case .tower, .soccer: return 600
        }
    }

    var minimumAccuracyPercent: Int {
        switch self {
        case .write: return 90
        case .tower, .soccer: return 80
        }
    }
}

enum LanguageAutoEvidenceRouting {
    /// Android WriteScreen counts every tap on a choice for the word the page asks
    /// about (choose the word, choose the picture, the first-letter pages and those
    /// pages inside mixed practice). Only attempts that carry the word count: letter
    /// taps in a built word carry none here, as Android counts only the finished word.
    static func attemptActivity(for family: ActivityFamily) -> LanguageAutoActivity? {
        switch family {
        case .tower:
            return .tower
        case .soccer:
            return .soccer
        case .multipleChoice, .mixed:
            return .write
        default:
            return nil
        }
    }

    static func completionActivity(for activity: LanguageActivityKind) -> LanguageAutoActivity? {
        activity == .wordBuild || activity == .mixed ? .write : nil
    }
}

struct LanguageAutoScope: Codable, Hashable, Sendable {
    let product: ProductVariant
    let profileID: String

    init(product: ProductVariant, profileID: String = "local-default") {
        precondition(!profileID.isEmpty)
        self.product = product
        self.profileID = profileID
    }
}

struct LanguageAutoPoolItem: Codable, Hashable, Sendable {
    let contentItemID: ContentItemID
    let vocabularyLevel: LanguageVocabularyLevel
}

extension LanguageAutoPoolItem {
    /// The word a Language word page asks about and its level, for which Android
    /// WriteScreen counts each answer. Nil on a page without a level word (the
    /// alphabet pages, Math).
    init?(languageWordOf challenge: Challenge) {
        guard let contentItemID = challenge.languageContentItemID,
              let level = LanguageVocabularyLevel(
                  curriculumStageID: challenge.curriculumStage
              ) else { return nil }
        self.init(contentItemID: contentItemID, vocabularyLevel: level)
    }
}

struct LanguageAutoPoolBoundary: Codable, Hashable, Sendable {
    let id: UUID
    let activity: LanguageAutoActivity
    let evaluatedLevel: LanguageVocabularyLevel
    let items: [LanguageAutoPoolItem]

    init?(
        id: UUID = UUID(),
        activity: LanguageAutoActivity,
        evaluatedLevel: LanguageVocabularyLevel,
        items: [LanguageAutoPoolItem]
    ) {
        guard !items.isEmpty, Set(items).count == items.count else { return nil }
        self.id = id
        self.activity = activity
        self.evaluatedLevel = evaluatedLevel
        self.items = items
    }
}

struct LanguageAutoPoolTracker: Sendable {
    let activity: LanguageAutoActivity
    let evaluatedLevel: LanguageVocabularyLevel
    let items: [LanguageAutoPoolItem]
    private let boundaryID: UUID
    private var didEmitBoundary: Bool

    init?(
        activity: LanguageAutoActivity,
        evaluatedLevel: LanguageVocabularyLevel,
        items: [LanguageAutoPoolItem],
        boundaryID: UUID = UUID()
    ) {
        guard !items.isEmpty, Set(items).count == items.count else { return nil }
        self.activity = activity
        self.evaluatedLevel = evaluatedLevel
        self.items = items
        self.boundaryID = boundaryID
        self.didEmitBoundary = false
    }

    mutating func takeBoundary(isExhausted: Bool) -> LanguageAutoPoolBoundary? {
        guard isExhausted, !didEmitBoundary else { return nil }
        didEmitBoundary = true
        return LanguageAutoPoolBoundary(
            id: boundaryID,
            activity: activity,
            evaluatedLevel: evaluatedLevel,
            items: items
        )
    }

    /// The Write check over a choice practice's whole word list (Android WriteScreen):
    /// every page's word and level. Nil without a level, or when a page has no word,
    /// as such a list is not a level word list.
    static func writeChoices(
        evaluatedLevel: LanguageVocabularyLevel?,
        challenges: [Challenge]
    ) -> LanguageAutoPoolTracker? {
        guard let evaluatedLevel else { return nil }
        let items = challenges.compactMap { LanguageAutoPoolItem(languageWordOf: $0) }
        guard items.count == challenges.count else { return nil }
        return LanguageAutoPoolTracker(
            activity: .write,
            evaluatedLevel: evaluatedLevel,
            items: items
        )
    }
}

struct LanguageAutoAttemptEvidence: Codable, Hashable, Sendable {
    let contentItemID: ContentItemID
    let vocabularyLevel: LanguageVocabularyLevel
    let activity: LanguageAutoActivity
    let result: GradedAttemptResult
}

struct LanguageAutoContentEvidence: Codable, Hashable, Sendable {
    let contentItemID: ContentItemID
    let vocabularyLevel: LanguageVocabularyLevel
    let activity: LanguageAutoActivity
    private(set) var correctCount: Int
    private(set) var wrongCount: Int

    init(
        contentItemID: ContentItemID,
        vocabularyLevel: LanguageVocabularyLevel,
        activity: LanguageAutoActivity,
        correctCount: Int = 0,
        wrongCount: Int = 0
    ) {
        precondition(correctCount >= 0 && wrongCount >= 0)
        self.contentItemID = contentItemID
        self.vocabularyLevel = vocabularyLevel
        self.activity = activity
        self.correctCount = correctCount
        self.wrongCount = wrongCount
    }

    mutating func record(_ result: GradedAttemptResult) {
        switch result {
        case .correct:
            if correctCount < .max { correctCount += 1 }
        case .incorrect:
            if wrongCount < .max { wrongCount += 1 }
        case .skipped:
            break
        }
    }
}

enum LanguageAutoPoolEvaluation: Equatable, Sendable {
    case ignored
    case failed(attempts: Int, accuracyPercent: Int)
    case passedOnce(attempts: Int, accuracyPercent: Int)
    /// The accuracy is the passing check's, which Android's "Level up!" window shows.
    case promoted(
        from: LanguageVocabularyLevel,
        to: LanguageVocabularyLevel,
        accuracyPercent: Int
    )
}

/// Android LevelUpDialogFragment's message: the passing check's accuracy and the new
/// level, named as in Android getLevelLabel ("Easy - B").
struct LanguageLevelUpAnnouncement: Identifiable, Equatable, Sendable {
    let id: UUID
    let level: LanguageVocabularyLevel
    let accuracyPercent: Int

    init?(evaluation: LanguageAutoPoolEvaluation, id: UUID = UUID()) {
        guard case .promoted(_, let level, let accuracyPercent) = evaluation else {
            return nil
        }
        self.id = id
        self.level = level
        self.accuracyPercent = accuracyPercent
    }

    static var titleKey: String.LocalizationValue { "Level up!" }

    /// Android level_up_text.
    static var messageKey: String.LocalizationValue {
        "Awesome! %lld%% correct!\nYou're moving up a level (%@)!"
    }

    /// Android level_name_a ... level_name_e.
    static func levelNameKey(for level: LanguageVocabularyLevel) -> String.LocalizationValue {
        switch level {
        case .a: return "Beginner"
        case .b: return "Easy"
        case .c: return "Medium"
        case .d: return "Hard"
        case .e: return "Very Hard"
        }
    }

    /// Android getLevelLabel: the level's name, a dash and its letter.
    static func levelLabel(name: String, level: LanguageVocabularyLevel) -> String {
        "\(name) - \(level.rawValue)"
    }

    /// Android level_up_text with the accuracy and the level label filled in.
    func message(format: String, levelName: String) -> String {
        String(
            format: format,
            Int64(accuracyPercent),
            Self.levelLabel(name: levelName, level: level)
        )
    }
}

struct LanguageAutoProgressionState: Codable, Equatable, Sendable {
    let scope: LanguageAutoScope
    private(set) var currentLevel: LanguageVocabularyLevel
    private(set) var ramp: Int
    private(set) var evidence: [LanguageAutoContentEvidence]
    private(set) var consecutivePasses: [LanguageVocabularyLevel: Int]
    private(set) var appliedEvidenceIDs: Set<UUID>
    private(set) var appliedBoundaryIDs: Set<UUID>

    init(
        scope: LanguageAutoScope,
        currentLevel: LanguageVocabularyLevel = .a,
        ramp: Int = 0,
        evidence: [LanguageAutoContentEvidence] = [],
        consecutivePasses: [LanguageVocabularyLevel: Int] = [:],
        appliedEvidenceIDs: Set<UUID> = [],
        appliedBoundaryIDs: Set<UUID> = []
    ) {
        self.scope = scope
        self.currentLevel = currentLevel
        self.ramp = min(100, max(0, ramp))
        self.evidence = evidence
        self.consecutivePasses = consecutivePasses
        self.appliedEvidenceIDs = appliedEvidenceIDs
        self.appliedBoundaryIDs = appliedBoundaryIDs
    }

    mutating func synchronizeCurrentLevel(_ level: LanguageVocabularyLevel) {
        currentLevel = level
    }

    mutating func record(id: UUID, evidence newEvidence: LanguageAutoAttemptEvidence) {
        guard appliedEvidenceIDs.insert(id).inserted,
              newEvidence.result != .skipped else { return }
        if let index = evidence.firstIndex(where: {
            $0.contentItemID == newEvidence.contentItemID
                && $0.vocabularyLevel == newEvidence.vocabularyLevel
                && $0.activity == newEvidence.activity
        }) {
            evidence[index].record(newEvidence.result)
        } else {
            var record = LanguageAutoContentEvidence(
                contentItemID: newEvidence.contentItemID,
                vocabularyLevel: newEvidence.vocabularyLevel,
                activity: newEvidence.activity
            )
            record.record(newEvidence.result)
            evidence.append(record)
        }
    }

    mutating func evaluate(
        _ boundary: LanguageAutoPoolBoundary,
        mode: LanguageLevelMode,
        persistedLevel: LanguageVocabularyLevel
    ) -> LanguageAutoPoolEvaluation {
        guard appliedBoundaryIDs.insert(boundary.id).inserted else { return .ignored }
        synchronizeCurrentLevel(persistedLevel)
        guard mode == .automatic,
              boundary.evaluatedLevel == currentLevel,
              let nextLevel = currentLevel.next else {
            return .ignored
        }

        let itemIDs = Set(boundary.items.map(\.contentItemID))
        let relevantEvidence = evidence.filter { itemIDs.contains($0.contentItemID) }
        let correct = relevantEvidence.reduce(0) { $0 + $1.correctCount }
        let wrong = relevantEvidence.reduce(0) { $0 + $1.wrongCount }
        let attempts = correct + wrong
        let accuracy = attempts == 0 ? 0 : (correct * 100) / attempts
        let passed = attempts >= boundary.activity.minimumAttempts
            && accuracy >= boundary.activity.minimumAccuracyPercent

        guard passed else {
            consecutivePasses[currentLevel] = 0
            return .failed(attempts: attempts, accuracyPercent: accuracy)
        }

        let newPassCount = (consecutivePasses[currentLevel] ?? 0) + 1
        consecutivePasses[currentLevel] = newPassCount
        guard newPassCount >= 2 else {
            return .passedOnce(attempts: attempts, accuracyPercent: accuracy)
        }

        currentLevel = nextLevel
        consecutivePasses[nextLevel] = 0
        ramp = 90
        return .promoted(
            from: boundary.evaluatedLevel,
            to: nextLevel,
            accuracyPercent: accuracy
        )
    }

    mutating func evaluate(
        _ boundary: LanguageAutoPoolBoundary,
        settings: inout LanguageParentLevelSettings
    ) -> LanguageAutoPoolEvaluation {
        let result = evaluate(
            boundary,
            mode: settings.mode,
            persistedLevel: settings.wordLevel
        )
        if case .promoted(_, let level, _) = result {
            settings.wordLevel = level
        }
        return result
    }

    mutating func applicationDidStop() {
        ramp = max(0, ramp - 10)
    }
}

final class LanguageAutoProgressRepository {
    static let schemaVersion = 1

    private struct Envelope: Codable {
        let schemaVersion: Int
        let state: LanguageAutoProgressionState
    }

    private let userDefaults: UserDefaults
    private let storageKeyPrefix: String

    init(
        userDefaults: UserDefaults = .standard,
        storageKeyPrefix: String = "minik.language-auto-progress.v1"
    ) {
        self.userDefaults = userDefaults
        self.storageKeyPrefix = storageKeyPrefix
    }

    func load(
        scope: LanguageAutoScope,
        currentLevel: LanguageVocabularyLevel
    ) -> LanguageAutoProgressionState {
        guard let data = userDefaults.data(forKey: storageKey(for: scope)),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.schemaVersion == Self.schemaVersion,
              envelope.state.scope == scope else {
            return LanguageAutoProgressionState(scope: scope, currentLevel: currentLevel)
        }
        var state = envelope.state
        state.synchronizeCurrentLevel(currentLevel)
        return state
    }

    func save(_ state: LanguageAutoProgressionState) {
        guard let data = try? JSONEncoder().encode(Envelope(
            schemaVersion: Self.schemaVersion,
            state: state
        )) else { return }
        userDefaults.set(data, forKey: storageKey(for: state.scope))
    }

    private func storageKey(for scope: LanguageAutoScope) -> String {
        "\(storageKeyPrefix).\(scope.product.rawValue).\(scope.profileID)"
    }
}

enum LanguageVocabularyPoolMixer {
    static func mix<Element, Generator: RandomNumberGenerator>(
        previous: [Element],
        current: [Element],
        ramp: Int,
        using generator: inout Generator
    ) -> [Element] {
        guard !previous.isEmpty, ramp > 0 else {
            return current.shuffled(using: &generator)
        }
        let boundedRamp = min(100, max(0, ramp))
        let previousCount = min(
            previous.count,
            Int((Double(previous.count) * Double(boundedRamp) / 100).rounded())
        )
        let currentCount = min(
            current.count,
            Int((Double(current.count) * Double(100 - boundedRamp) / 100).rounded())
        )
        let selected = Array(previous.shuffled(using: &generator).prefix(previousCount))
            + Array(current.shuffled(using: &generator).prefix(currentCount))
        return selected.shuffled(using: &generator)
    }

    static func mix<Element>(
        previous: [Element],
        current: [Element],
        ramp: Int
    ) -> [Element] {
        var generator = SystemRandomNumberGenerator()
        return mix(previous: previous, current: current, ramp: ramp, using: &generator)
    }
}
