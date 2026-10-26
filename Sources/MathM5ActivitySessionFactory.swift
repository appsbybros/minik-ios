import Foundation

enum MathM5ActivitySession: Sendable {
    case learn(LearnSession)
    case pairs(PairsSession)
    case buildNumber(BuildSession)
    case buildQuantity(MathStructuredConstructionSession)
    case visualToAnswer(MultipleChoiceSession)
    case answerToRepresentation(MultipleChoiceSession)
    case buildMath(BuildSession)
    case mixed(MathM5MixedSession)
    case cards(CardsSession)
    case soccer(SoccerSession)
    case towerCount(MathCountConstructionSession)
    case towerTokens(BuildSession)
    case memory(MemorySession)
}

struct MathM5MixedSession: Sendable {
    static let eligibleActivities: [MathProductionActivityID] = [
        .mathPairs, .buildNumber, .buildQuantity, .visualToAnswer,
        .answerToRepresentation, .buildMath, .mathSoccer, .mathTower, .mathMemory
    ]
    private(set) var currentActivity = Self.eligibleActivities.randomElement() ?? .visualToAnswer

    mutating func advance() {
        currentActivity = Self.eligibleActivities.filter { $0 != currentActivity }.randomElement() ?? currentActivity
    }
}

struct MathM5ActivitySessionFactory: Sendable {
    private static let challengeCount = 6
    private let provider: MathM5ContentProvider
    private let fitGate: MathContentFitGate
    private let towerModeSelector: @Sendable () -> MathTowerConstructionMode

    init(
        configuration: ProductConfiguration,
        fitGate: MathContentFitGate = .production,
        towerModeSelector: @escaping @Sendable () -> MathTowerConstructionMode = {
            Bool.random() ? .count : .answerTokens
        }
    ) {
        precondition(configuration.variant == .minikMath)
        provider = MathM5ContentProvider(fitGate: fitGate)
        self.fitGate = fitGate
        self.towerModeSelector = towerModeSelector
    }

    func makeSession(for activity: MathProductionActivityID) -> MathM5ActivitySession? {
        switch activity {
        case .learnMath:
            return LearnSession(cards: provider.studyCards()).map(MathM5ActivitySession.learn)
        case .mathPairs:
            return PairsSession(equivalenceSets: provider.equivalenceSets()).map(MathM5ActivitySession.pairs)
        case .buildNumber:
            return buildNumberSession().map(MathM5ActivitySession.buildNumber)
        case .buildQuantity:
            return structuredSession().map(MathM5ActivitySession.buildQuantity)
        case .visualToAnswer:
            // Android Math Plus ab3e427: Visual → Answer counts a picture at every level.
            return MathPictureQuestions.session(for: .m5, fitGate: fitGate)
                .map(MathM5ActivitySession.visualToAnswer)
        case .answerToRepresentation:
            return choiceSession(.answerToRepresentation).map(MathM5ActivitySession.answerToRepresentation)
        case .buildMath:
            return buildMathSession().map(MathM5ActivitySession.buildMath)
        case .mathMixed:
            return .mixed(MathM5MixedSession())
        case .mathCards:
            return CardsSession(cards: provider.studyCards().shuffled()).map(MathM5ActivitySession.cards)
        case .mathSoccer:
            return provider.soccerRound().map { SoccerSession(round: $0) }.map(MathM5ActivitySession.soccer)
        case .mathTower:
            switch towerModeSelector() {
            case .count: return countTowerSession().map(MathM5ActivitySession.towerCount)
            case .answerTokens: return tokenTowerSession().map(MathM5ActivitySession.towerTokens)
            }
        case .mathMemory:
            return MemorySession(equivalenceSets: provider.equivalenceSets()).map(MathM5ActivitySession.memory)
        case .pingPong:
            return nil
        }
    }

    private var problems: [MathM5Problem] { provider.balancedProblems(count: Self.challengeCount) }

    private func choiceSession(_ direction: MathM5ChoiceDirection) -> MultipleChoiceSession? {
        let values = problems.compactMap { provider.choiceChallenge(problem: $0, direction: direction) }
        return values.count == Self.challengeCount
            ? MultipleChoiceSession(challenges: values, progressionPolicy: .retryUntilCorrect) : nil
    }

    private func buildNumberSession() -> BuildSession? {
        let values = problems.compactMap(provider.buildNumberChallenge)
        return values.count == Self.challengeCount ? BuildSession(challenges: values) : nil
    }

    private func buildMathSession() -> BuildSession? {
        let values = problems.compactMap(provider.buildEquationChallenge)
        return values.count == Self.challengeCount ? BuildSession(challenges: values) : nil
    }

    private func structuredSession() -> MathStructuredConstructionSession? {
        let source = MathM5ContentProvider.problems.filter { $0.operation == .multiplication && $0.answer <= 50 }
        let values = (0..<Self.challengeCount).compactMap { provider.structuredRound(problem: source[$0 % source.count]) }
        return values.count == Self.challengeCount ? MathStructuredConstructionSession(rounds: values) : nil
    }

    private func countTowerSession() -> MathCountConstructionSession? {
        let source = MathM5ContentProvider.problems.filter { $0.answer <= 20 }
        let values = (0..<Self.challengeCount).compactMap { provider.countRound(problem: source[$0 % source.count]) }
        return values.count == Self.challengeCount ? MathCountConstructionSession(rounds: values) : nil
    }

    private func tokenTowerSession() -> BuildSession? {
        let source = MathM5ContentProvider.problems.filter { $0.answer > 20 }
        let values = (0..<Self.challengeCount).compactMap { provider.answerTokenTowerChallenge(problem: source[$0 % source.count]) }
        return values.count == Self.challengeCount ? BuildSession(challenges: values) : nil
    }
}
