import SwiftUI

struct LanguageMixedPracticeView: View {
    @State private var session: LanguageMixedPracticeSession

    private let sessionFactory: LanguageActivitySessionFactory
    private let makeSessionFactory: (() -> LanguageActivitySessionFactory)?
    private let learnedLanguage: LanguageIdentifier
    private let onAttempt: (ActivityAttemptData) -> Void
    private let onWordCompleted: (LanguageWordCompletion) -> Void
    private let onLanguagePoolExhausted: (LanguageAutoPoolBoundary) -> Void
    private let onAdOpportunity: () -> Void
    private let onExit: () -> Void

    /// `makeSessionFactory` gives the factory for each new child, so a child made after
    /// a level up uses the new level and ramp; without it every child uses
    /// `sessionFactory`.
    init(
        session: LanguageMixedPracticeSession,
        sessionFactory: LanguageActivitySessionFactory,
        makeSessionFactory: (() -> LanguageActivitySessionFactory)? = nil,
        learnedLanguage: LanguageIdentifier,
        onAttempt: @escaping (ActivityAttemptData) -> Void = { _ in },
        onWordCompleted: @escaping (LanguageWordCompletion) -> Void = { _ in },
        onLanguagePoolExhausted: @escaping (LanguageAutoPoolBoundary) -> Void = { _ in },
        onAdOpportunity: @escaping () -> Void = {},
        onExit: @escaping () -> Void = {}
    ) {
        _session = State(initialValue: session)
        self.sessionFactory = sessionFactory
        self.makeSessionFactory = makeSessionFactory
        self.learnedLanguage = learnedLanguage
        self.onAttempt = onAttempt
        self.onWordCompleted = onWordCompleted
        self.onLanguagePoolExhausted = onLanguagePoolExhausted
        self.onAdOpportunity = onAdOpportunity
        self.onExit = onExit
    }

    @ViewBuilder
    var body: some View {
        let childActivity = session.currentChildActivity

        switch childActivity.session {
        case .multipleChoice(let childSession):
            MultipleChoiceView(
                session: childSession,
                progressActivityFamily: .mixed,
                presentation: choicePresentation(for: childActivity.mode),
                onAttempt: mixedChoiceAttempt,
                languageAutoEvaluationLevel: childActivity.vocabularyLevel,
                onLanguagePoolExhausted: onLanguagePoolExhausted,
                onComplete: {
                    replaceCompletedChild(withID: childActivity.id)
                },
                onAdvance: {
                    recordAdvance(fromChildWithID: childActivity.id)
                },
                onExit: onExit
            )
            .id(childActivity.id)

        case .build(let childSession):
            BuildView(
                session: childSession,
                progressActivityFamily: .mixed,
                presentation: .word,
                onAttempt: mixedAttempt,
                onWordCompleted: onWordCompleted,
                languageAutoEvaluationLevel: childActivity.vocabularyLevel,
                onLanguagePoolExhausted: onLanguagePoolExhausted,
                onComplete: {
                    replaceCompletedChild(withID: childActivity.id)
                },
                onAdvance: {
                    recordAdvance(fromChildWithID: childActivity.id)
                },
                onExit: onExit
            )
            .id(childActivity.id)
        }
    }

    private var currentSessionFactory: LanguageActivitySessionFactory {
        makeSessionFactory?() ?? sessionFactory
    }

    private func choicePresentation(
        for mode: LanguageMixedPracticeMode
    ) -> MultipleChoicePresentation {
        switch mode {
        case .wordToPicture:
            return .wordToPicture
        case .pictureToWord:
            return .pictureToWord
        case .wordBuild:
            preconditionFailure("Word Build must use the Mixed build child presentation.")
        }
    }

    private func recordAdvance(fromChildWithID childID: UUID) {
        let factory = currentSessionFactory
        let result = session.record(.advancedCurrentWord, fromChildWithID: childID) { mode in
            factory.makeMixedChildActivity(
                for: mode,
                language: learnedLanguage
            )
        }
        if result != .ignored {
            onAdOpportunity()
        }
    }

    private func replaceCompletedChild(withID childID: UUID) {
        let factory = currentSessionFactory
        session.replaceCompletedChild(withID: childID) { mode in
            factory.makeMixedChildActivity(
                for: mode,
                language: learnedLanguage
            )
        }
    }

    /// A choice page's tap keeps its word, which Android WriteScreen counts.
    private func mixedChoiceAttempt(_ attempt: ActivityAttemptData) {
        guard let mixed = ActivityAttemptData(
            itemID: attempt.itemID,
            attemptIndex: attempt.attemptIndex,
            result: attempt.result,
            responseDurationSeconds: attempt.responseDurationSeconds,
            activityFamily: .mixed,
            skillID: attempt.skillID,
            languageContentItemID: attempt.languageContentItemID,
            languageVocabularyLevel: attempt.languageVocabularyLevel
        ) else { return }
        onAttempt(mixed)
    }

    /// A letter tap in a built word carries no word: Android counts only the finished
    /// word (onWordCompleted).
    private func mixedAttempt(_ attempt: ActivityAttemptData) {
        guard let mixed = ActivityAttemptData(
            itemID: attempt.itemID,
            attemptIndex: attempt.attemptIndex,
            result: attempt.result,
            responseDurationSeconds: attempt.responseDurationSeconds,
            activityFamily: .mixed,
            skillID: attempt.skillID
        ) else { return }
        onAttempt(mixed)
    }
}
