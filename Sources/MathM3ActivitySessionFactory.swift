import Foundation

enum MathM3ActivitySession: Sendable {
    case learn(LearnSession)
    case pairs(PairsSession)
    case buildNumber(BuildSession)
    case buildQuantity(MathCountConstructionSession)
    case visualToAnswer(MultipleChoiceSession)
    case answerToRepresentation(MultipleChoiceSession)
    case buildMath(BuildSession)
    case mixed(MathM3MixedSession)
    case cards(CardsSession)
    case soccer(SoccerSession)
    case tower(MathCountConstructionSession)
    case memory(MemorySession)
}

struct MathM3MixedSession: Sendable {
    static let eligibleActivities: [MathProductionActivityID] = [
        .mathPairs, .buildNumber, .buildQuantity, .visualToAnswer,
        .answerToRepresentation, .buildMath, .mathSoccer, .mathTower,
        .mathMemory
    ]

    private(set) var currentActivity: MathProductionActivityID

    init() {
        currentActivity = Self.eligibleActivities.randomElement() ?? .visualToAnswer
    }

    mutating func advance() {
        currentActivity = Self.eligibleActivities
            .filter { $0 != currentActivity }
            .randomElement() ?? currentActivity
    }
}

struct MathM3ActivitySessionFactory: Sendable {
    private static let challengeCount = 6
    private let provider: MathM3ContentProvider
    private let fitGate: MathContentFitGate

    init(configuration: ProductConfiguration, fitGate: MathContentFitGate = .production) {
        precondition(configuration.variant == .minikMath)
        provider = MathM3ContentProvider(fitGate: fitGate)
        self.fitGate = fitGate
    }

    func makeSession(for activity: MathProductionActivityID) -> MathM3ActivitySession? {
        switch activity {
        case .learnMath:
            return LearnSession(cards: provider.studyCards()).map(MathM3ActivitySession.learn)
        case .mathPairs:
            return PairsSession(equivalenceSets: provider.equivalenceSets()).map(MathM3ActivitySession.pairs)
        case .buildNumber:
            return buildNumberSession().map(MathM3ActivitySession.buildNumber)
        case .buildQuantity:
            return countSession().map(MathM3ActivitySession.buildQuantity)
        case .visualToAnswer:
            // Android Math Plus ab3e427: Visual → Answer counts a picture at every level.
            return MathPictureQuestions.session(for: .m3, fitGate: fitGate)
                .map(MathM3ActivitySession.visualToAnswer)
        case .answerToRepresentation:
            return choiceSession(direction: .answerToRelationship).map(MathM3ActivitySession.answerToRepresentation)
        case .buildMath:
            return buildEquationSession().map(MathM3ActivitySession.buildMath)
        case .mathMixed:
            return .mixed(MathM3MixedSession())
        case .mathCards:
            return CardsSession(cards: provider.studyCards().shuffled()).map(MathM3ActivitySession.cards)
        case .mathSoccer:
            return provider.soccerRound().map { SoccerSession(round: $0) }.map(MathM3ActivitySession.soccer)
        case .mathTower:
            return countSession().map(MathM3ActivitySession.tower)
        case .mathMemory:
            return MemorySession(equivalenceSets: provider.equivalenceSets()).map(MathM3ActivitySession.memory)
        case .pingPong:
            return nil
        }
    }

    private var relationships: [MathM3Relationship] {
        provider.balancedRelationships(count: Self.challengeCount)
    }

    private func choiceSession(direction: MathM3ChoiceDirection) -> MultipleChoiceSession? {
        let challenges = relationships.compactMap { provider.choiceChallenge(relationship: $0, direction: direction) }
        guard challenges.count == Self.challengeCount else { return nil }
        return MultipleChoiceSession(challenges: challenges, progressionPolicy: .retryUntilCorrect)
    }

    private func buildNumberSession() -> BuildSession? {
        let challenges = relationships.compactMap(provider.buildNumberChallenge)
        return challenges.count == Self.challengeCount ? BuildSession(challenges: challenges) : nil
    }

    private func buildEquationSession() -> BuildSession? {
        let challenges = relationships.compactMap(provider.buildEquationChallenge)
        return challenges.count == Self.challengeCount ? BuildSession(challenges: challenges) : nil
    }

    private func countSession() -> MathCountConstructionSession? {
        let rounds = relationships.compactMap(provider.countRound)
        return rounds.count == Self.challengeCount ? MathCountConstructionSession(rounds: rounds) : nil
    }
}
