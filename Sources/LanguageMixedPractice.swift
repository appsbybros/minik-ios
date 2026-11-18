import Foundation

enum LanguageMixedPracticeMode: String, CaseIterable, Hashable, Sendable {
    case wordToPicture
    case pictureToWord
    case wordBuild

    var advanceThreshold: Int {
        switch self {
        case .wordToPicture:
            20
        case .pictureToWord:
            10
        case .wordBuild:
            5
        }
    }
}

struct LanguageMixedCapabilityPolicy: Equatable, Sendable {
    private let enabledModes: Set<LanguageMixedPracticeMode>

    init?(enabledModes: Set<LanguageMixedPracticeMode>) {
        guard !enabledModes.isEmpty else {
            return nil
        }
        self.enabledModes = enabledModes
    }

    static let current: LanguageMixedCapabilityPolicy = {
        guard let policy = LanguageMixedCapabilityPolicy(
            enabledModes: Set(LanguageMixedPracticeMode.allCases)
        ) else {
            preconditionFailure("Current Mixed capability policy must enable a mode.")
        }
        return policy
    }()

    var initialMode: LanguageMixedPracticeMode {
        guard let mode = LanguageMixedPracticeMode.allCases.first(where: enabledModes.contains) else {
            preconditionFailure("Mixed capability policy must enable a mode.")
        }
        return mode
    }

    func allows(_ mode: LanguageMixedPracticeMode) -> Bool {
        enabledModes.contains(mode)
    }

    func nextMode(after currentMode: LanguageMixedPracticeMode) -> LanguageMixedPracticeMode {
        let modes = LanguageMixedPracticeMode.allCases
        guard let currentIndex = modes.firstIndex(of: currentMode) else {
            return initialMode
        }

        for offset in 1 ... modes.count {
            let candidate = modes[(currentIndex + offset) % modes.count]
            if enabledModes.contains(candidate) {
                return candidate
            }
        }

        return initialMode
    }
}

enum LanguageMixedProgressEvent: Hashable, Sendable {
    case advancedCurrentWord
    case interactionDidNotAdvance
}

enum LanguageMixedProgressResult: Hashable, Sendable {
    case ignored
    case advanced
    case modeChanged(
        from: LanguageMixedPracticeMode,
        to: LanguageMixedPracticeMode
    )
}

struct LanguageMixedProgression: Sendable {
    let capabilityPolicy: LanguageMixedCapabilityPolicy
    private(set) var currentMode: LanguageMixedPracticeMode
    private(set) var advancesInCurrentMode: Int

    init(capabilityPolicy: LanguageMixedCapabilityPolicy = .current) {
        self.capabilityPolicy = capabilityPolicy
        self.currentMode = capabilityPolicy.initialMode
        self.advancesInCurrentMode = 0
    }

    @discardableResult
    mutating func record(
        _ event: LanguageMixedProgressEvent
    ) -> LanguageMixedProgressResult {
        guard event == .advancedCurrentWord else {
            return .ignored
        }

        advancesInCurrentMode += 1
        guard advancesInCurrentMode >= currentMode.advanceThreshold else {
            return .advanced
        }

        let previousMode = currentMode
        currentMode = capabilityPolicy.nextMode(after: previousMode)
        advancesInCurrentMode = 0
        return .modeChanged(from: previousMode, to: currentMode)
    }
}

enum LanguageMixedChildSession: Sendable {
    case multipleChoice(MultipleChoiceSession)
    case build(BuildSession)
}

struct LanguageMixedChildActivity: Identifiable, Sendable {
    let id: UUID
    let mode: LanguageMixedPracticeMode
    let session: LanguageMixedChildSession
    /// The word level the child's list was made for: the end of the list checks it
    /// for a level up. Nil makes no check.
    let vocabularyLevel: LanguageVocabularyLevel?

    init(
        id: UUID = UUID(),
        mode: LanguageMixedPracticeMode,
        session: LanguageMixedChildSession,
        vocabularyLevel: LanguageVocabularyLevel? = nil
    ) {
        self.id = id
        self.mode = mode
        self.session = session
        self.vocabularyLevel = vocabularyLevel
    }
}

struct LanguageMixedPracticeSession: Sendable {
    private(set) var progression: LanguageMixedProgression
    private(set) var currentChildActivity: LanguageMixedChildActivity

    init?(
        capabilityPolicy: LanguageMixedCapabilityPolicy = .current,
        currentChildActivity: LanguageMixedChildActivity
    ) {
        let progression = LanguageMixedProgression(capabilityPolicy: capabilityPolicy)
        guard currentChildActivity.mode == progression.currentMode else {
            return nil
        }
        self.progression = progression
        self.currentChildActivity = currentChildActivity
    }

    var currentMode: LanguageMixedPracticeMode {
        progression.currentMode
    }

    var advancesInCurrentMode: Int {
        progression.advancesInCurrentMode
    }

    @discardableResult
    mutating func record(
        _ event: LanguageMixedProgressEvent,
        makeChildActivity: (LanguageMixedPracticeMode) -> LanguageMixedChildActivity?
    ) -> LanguageMixedProgressResult {
        let previousProgression = progression
        let result = progression.record(event)

        guard case .modeChanged(_, let nextMode) = result else {
            return result
        }
        guard let nextActivity = makeChildActivity(nextMode),
              nextActivity.mode == nextMode else {
            progression = previousProgression
            return .ignored
        }

        currentChildActivity = nextActivity
        return result
    }

    @discardableResult
    mutating func record(
        _ event: LanguageMixedProgressEvent,
        fromChildWithID childID: UUID,
        makeChildActivity: (LanguageMixedPracticeMode) -> LanguageMixedChildActivity?
    ) -> LanguageMixedProgressResult {
        guard currentChildActivity.id == childID else {
            return .ignored
        }
        return record(event, makeChildActivity: makeChildActivity)
    }

    @discardableResult
    mutating func replaceCompletedChild(
        withID childID: UUID,
        makeChildActivity: (LanguageMixedPracticeMode) -> LanguageMixedChildActivity?
    ) -> Bool {
        guard currentChildActivity.id == childID,
              let replacement = makeChildActivity(currentMode),
              replacement.mode == currentMode else {
            return false
        }

        currentChildActivity = replacement
        return true
    }
}
