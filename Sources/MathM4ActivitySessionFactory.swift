import Foundation

enum MathTowerConstructionMode: Hashable, Sendable {
    case count
    case answerTokens
}

enum MathM4ActivitySession: Sendable {
    case learn(LearnSession)
    case pairs(PairsSession)
    case buildNumber(BuildSession)
    case buildQuantity(MathStructuredConstructionSession)
    case visualToAnswer(MultipleChoiceSession)
    case answerToRepresentation(MultipleChoiceSession)
    case buildMath(BuildSession)
    case mixed(MathM4MixedSession)
    case cards(CardsSession)
    case soccer(SoccerSession)
    case towerCount(MathCountConstructionSession)
    case towerTokens(BuildSession)
    case memory(MemorySession)
}

struct MathM4MixedSession: Sendable {
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

struct MathM4ActivitySessionFactory: Sendable {
    private static let challengeCount = 6
    private let provider: MathM4ContentProvider
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
        provider = MathM4ContentProvider(fitGate: fitGate)
        self.fitGate = fitGate
        self.towerModeSelector = towerModeSelector
    }

    func makeSession(for activity: MathProductionActivityID) -> MathM4ActivitySession? {
        switch activity {
        case .learnMath:
            return LearnSession(cards: provider.studyCards()).map(MathM4ActivitySession.learn)
        case .mathPairs:
            return PairsSession(equivalenceSets: provider.equivalenceSets()).map(MathM4ActivitySession.pairs)
        case .buildNumber:
            return buildNumberSession().map(MathM4ActivitySession.buildNumber)
        case .buildQuantity:
            return structuredSession().map(MathM4ActivitySession.buildQuantity)
        case .visualToAnswer:
            // Android Math Plus ab3e427: Visual → Answer counts a picture at every level.
            return MathPictureQuestions.session(for: .m4, fitGate: fitGate)
                .map(MathM4ActivitySession.visualToAnswer)
        case .answerToRepresentation:
            return choiceSession(direction: .answerToRepresentation).map(MathM4ActivitySession.answerToRepresentation)
        case .buildMath:
            return buildEquationSession().map(MathM4ActivitySession.buildMath)
        case .mathMixed:
            return .mixed(MathM4MixedSession())
        case .mathCards:
            return CardsSession(cards: provider.studyCards().shuffled()).map(MathM4ActivitySession.cards)
        case .mathSoccer:
            return provider.soccerRound().map { SoccerSession(round: $0) }.map(MathM4ActivitySession.soccer)
        case .mathTower:
            switch towerModeSelector() {
            case .count:
                return countTowerSession().map(MathM4ActivitySession.towerCount)
            case .answerTokens:
                return tokenTowerSession().map(MathM4ActivitySession.towerTokens)
            }
        case .mathMemory:
            return MemorySession(equivalenceSets: provider.equivalenceSets()).map(MathM4ActivitySession.memory)
        case .pingPong:
            return nil
        }
    }

    private var problems: [MathM4Problem] {
        provider.balancedProblems(count: Self.challengeCount)
    }

    private func choiceSession(direction: MathM4ChoiceDirection) -> MultipleChoiceSession? {
        let challenges = problems.compactMap { provider.choiceChallenge(problem: $0, direction: direction) }
        guard challenges.count == Self.challengeCount else { return nil }
        return MultipleChoiceSession(challenges: challenges, progressionPolicy: .retryUntilCorrect)
    }

    private func buildNumberSession() -> BuildSession? {
        let challenges = problems.compactMap(provider.buildNumberChallenge)
        return challenges.count == Self.challengeCount ? BuildSession(challenges: challenges) : nil
    }

    private func buildEquationSession() -> BuildSession? {
        let challenges = problems.compactMap(provider.buildEquationChallenge)
        return challenges.count == Self.challengeCount ? BuildSession(challenges: challenges) : nil
    }

    private func structuredSession() -> MathStructuredConstructionSession? {
        let source = MathM4ContentProvider.problems.filter { (10...99).contains($0.answer) }
        let rounds = (0..<Self.challengeCount).compactMap {
            provider.structuredRound(problem: source[$0 % source.count])
        }
        return rounds.count == Self.challengeCount ? MathStructuredConstructionSession(rounds: rounds) : nil
    }

    private func countTowerSession() -> MathCountConstructionSession? {
        let source = MathM4ContentProvider.problems.filter { $0.answer <= 20 }
        let rounds = (0..<Self.challengeCount).compactMap {
            provider.countRound(problem: source[$0 % source.count])
        }
        return rounds.count == Self.challengeCount ? MathCountConstructionSession(rounds: rounds) : nil
    }

    private func tokenTowerSession() -> BuildSession? {
        let source = MathM4ContentProvider.problems.filter { $0.answer > 20 }
        let challenges = (0..<Self.challengeCount).compactMap {
            provider.answerTokenTowerChallenge(problem: source[$0 % source.count])
        }
        return challenges.count == Self.challengeCount ? BuildSession(challenges: challenges) : nil
    }
}
