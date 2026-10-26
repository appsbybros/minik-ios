import Foundation

enum MathM6BuildQuantityMode: Hashable, Sendable {
    case equalGroups
    case fractionBar
}

enum MathM6BuildQuantitySession: Sendable {
    case equalGroups(MathStructuredConstructionSession)
    case fractionBar(MathFractionConstructionSession)
}

enum MathM6ActivitySession: Sendable {
    case learn(LearnSession)
    case pairs(PairsSession)
    case buildNumber(BuildSession)
    case buildQuantity(MathM6BuildQuantitySession)
    case visualToAnswer(MultipleChoiceSession)
    case answerToRepresentation(MultipleChoiceSession)
    case buildMath(BuildSession)
    case mixed(MathM6MixedSession)
    case cards(CardsSession)
    case soccer(SoccerSession)
    case towerCount(MathCountConstructionSession)
    case towerTokens(BuildSession)
    case memory(MemorySession)
}

struct MathM6MixedSession: Sendable {
    static let eligibleActivities: [MathProductionActivityID] = [
        .mathPairs, .buildNumber, .buildQuantity, .visualToAnswer,
        .answerToRepresentation, .buildMath, .mathSoccer, .mathTower, .mathMemory
    ]
    private(set) var currentActivity = Self.eligibleActivities.randomElement() ?? .visualToAnswer

    mutating func advance() {
        currentActivity = Self.eligibleActivities.filter { $0 != currentActivity }.randomElement() ?? currentActivity
    }
}

struct MathM6ActivitySessionFactory: Sendable {
    private static let challengeCount = 6
    private let provider: MathM6ContentProvider
    private let fitGate: MathContentFitGate
    private let towerModeSelector: @Sendable () -> MathTowerConstructionMode
    private let buildQuantityModeSelector: @Sendable () -> MathM6BuildQuantityMode

    init(
        configuration: ProductConfiguration,
        fitGate: MathContentFitGate = .production,
        towerModeSelector: @escaping @Sendable () -> MathTowerConstructionMode = {
            Bool.random() ? .count : .answerTokens
        },
        buildQuantityModeSelector: @escaping @Sendable () -> MathM6BuildQuantityMode = {
            Bool.random() ? .equalGroups : .fractionBar
        }
    ) {
        precondition(configuration.variant == .minikMath)
        provider = MathM6ContentProvider(fitGate: fitGate)
        self.fitGate = fitGate
        self.towerModeSelector = towerModeSelector
        self.buildQuantityModeSelector = buildQuantityModeSelector
    }

    func makeSession(for activity: MathProductionActivityID) -> MathM6ActivitySession? {
        switch activity {
        case .learnMath:
            return LearnSession(cards: provider.studyCards()).map(MathM6ActivitySession.learn)
        case .mathPairs:
            return PairsSession(equivalenceSets: provider.equivalenceSets()).map(MathM6ActivitySession.pairs)
        case .buildNumber:
            return buildNumberSession().map(MathM6ActivitySession.buildNumber)
        case .buildQuantity:
            switch buildQuantityModeSelector() {
            case .equalGroups: return structuredSession().map(MathM6BuildQuantitySession.equalGroups).map(MathM6ActivitySession.buildQuantity)
            case .fractionBar: return fractionSession().map(MathM6BuildQuantitySession.fractionBar).map(MathM6ActivitySession.buildQuantity)
            }
        case .visualToAnswer:
            // Android Math Plus ab3e427: Visual → Answer counts a picture at every level.
            return MathPictureQuestions.session(for: .m6, fitGate: fitGate)
                .map(MathM6ActivitySession.visualToAnswer)
        case .answerToRepresentation:
            return choiceSession(.answerToRepresentation).map(MathM6ActivitySession.answerToRepresentation)
        case .buildMath:
            return buildMathSession().map(MathM6ActivitySession.buildMath)
        case .mathMixed:
            return .mixed(MathM6MixedSession())
        case .mathCards:
            return CardsSession(cards: provider.studyCards().shuffled()).map(MathM6ActivitySession.cards)
        case .mathSoccer:
            return provider.soccerRound().map { SoccerSession(round: $0) }.map(MathM6ActivitySession.soccer)
        case .mathTower:
            switch towerModeSelector() {
            case .count: return countTowerSession().map(MathM6ActivitySession.towerCount)
            case .answerTokens: return tokenTowerSession().map(MathM6ActivitySession.towerTokens)
            }
        case .mathMemory:
            return MemorySession(equivalenceSets: provider.equivalenceSets()).map(MathM6ActivitySession.memory)
        case .pingPong:
            return nil
        }
    }

    private var problems: [MathM6Problem] { provider.balancedProblems(count: Self.challengeCount) }

    private func choiceSession(_ direction: MathM6ChoiceDirection) -> MultipleChoiceSession? {
        let values = problems.compactMap { provider.choiceChallenge(problem: $0, direction: direction) }
        return values.count == Self.challengeCount
            ? MultipleChoiceSession(challenges: values, progressionPolicy: .retryUntilCorrect) : nil
    }

    private func buildNumberSession() -> BuildSession? {
        let values = problems.compactMap(provider.buildNumberChallenge)
        return values.count == Self.challengeCount ? BuildSession(challenges: values) : nil
    }

    private func buildMathSession() -> BuildSession? {
        let values = problems.compactMap(provider.buildMathChallenge)
        return values.count == Self.challengeCount ? BuildSession(challenges: values) : nil
    }

    private func structuredSession() -> MathStructuredConstructionSession? {
        let source = MathM6ContentProvider.problems.filter {
            $0.category == .multiplication && ($0.integerAnswer ?? 101) <= 50
        }
        let values = (0..<Self.challengeCount).compactMap { provider.structuredRound(problem: source[$0 % source.count]) }
        return values.count == Self.challengeCount ? MathStructuredConstructionSession(rounds: values) : nil
    }

    private func fractionSession() -> MathFractionConstructionSession? {
        let source = MathM6ContentProvider.problems.filter { $0.category == .fraction }
        let values = (0..<Self.challengeCount).compactMap { provider.fractionRound(problem: source[$0 % source.count]) }
        return values.count == Self.challengeCount ? MathFractionConstructionSession(rounds: values) : nil
    }

    private func countTowerSession() -> MathCountConstructionSession? {
        let source = MathM6ContentProvider.problems.filter { ($0.integerAnswer ?? 101) <= 20 }
        let values = (0..<Self.challengeCount).compactMap { provider.countRound(problem: source[$0 % source.count]) }
        return values.count == Self.challengeCount ? MathCountConstructionSession(rounds: values) : nil
    }

    private func tokenTowerSession() -> BuildSession? {
        let source = MathM6ContentProvider.problems.filter { $0.integerAnswer == nil || ($0.integerAnswer ?? 0) > 20 }
        let values = (0..<Self.challengeCount).compactMap { provider.answerTokenTowerChallenge(problem: source[$0 % source.count]) }
        return values.count == Self.challengeCount ? BuildSession(challenges: values) : nil
    }
}
