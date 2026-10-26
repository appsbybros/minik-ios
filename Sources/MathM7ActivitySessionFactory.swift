import Foundation

enum MathM7ActivitySession: Sendable {
    case learn(LearnSession), pairs(PairsSession), buildNumber(BuildSession)
    case buildQuantity(MathFractionConstructionSession)
    case visualToAnswer(MultipleChoiceSession), answerToRepresentation(MultipleChoiceSession)
    case buildMath(BuildSession), mixed(MathM7MixedSession), cards(CardsSession)
    case soccer(SoccerSession), tower(BuildSession), memory(MemorySession)
}

struct MathM7MixedSession: Sendable {
    static let eligibleActivities: [MathProductionActivityID] = [.mathPairs, .buildNumber, .buildQuantity,
        .visualToAnswer, .answerToRepresentation, .buildMath, .mathSoccer, .mathTower, .mathMemory]
    private(set) var currentActivity = Self.eligibleActivities.randomElement() ?? .visualToAnswer
    mutating func advance() { currentActivity = Self.eligibleActivities.filter { $0 != currentActivity }.randomElement() ?? currentActivity }
}

struct MathM7ActivitySessionFactory: Sendable {
    private static let count = 6
    private let provider: MathM7ContentProvider
    private let fitGate: MathContentFitGate
    init(configuration: ProductConfiguration, fitGate: MathContentFitGate = .production) {
        precondition(configuration.variant == .minikMath); provider = MathM7ContentProvider(fitGate: fitGate); self.fitGate = fitGate
    }
    func makeSession(for activity: MathProductionActivityID) -> MathM7ActivitySession? {
        switch activity {
        case .learnMath: return LearnSession(cards: provider.studyCards()).map(MathM7ActivitySession.learn)
        case .mathPairs: return PairsSession(equivalenceSets: provider.equivalenceSets()).map(MathM7ActivitySession.pairs)
        case .buildNumber: return build(provider.buildNumberChallenge).map(MathM7ActivitySession.buildNumber)
        case .buildQuantity:
            let source = provider.balancedProblems(count: Self.count).compactMap(provider.fractionRound)
            return source.count == Self.count ? MathFractionConstructionSession(rounds: source).map(MathM7ActivitySession.buildQuantity) : nil
        // Android Math Plus ab3e427: Visual → Answer counts a picture at every level.
        case .visualToAnswer: return MathPictureQuestions.session(for: .m7, fitGate: fitGate).map(MathM7ActivitySession.visualToAnswer)
        case .answerToRepresentation: return choices(.answerToRepresentation).map(MathM7ActivitySession.answerToRepresentation)
        case .buildMath: return build(provider.buildMathChallenge).map(MathM7ActivitySession.buildMath)
        case .mathMixed: return .mixed(MathM7MixedSession())
        case .mathCards: return CardsSession(cards: provider.studyCards().shuffled()).map(MathM7ActivitySession.cards)
        case .mathSoccer: return provider.soccerRound().map { SoccerSession(round: $0) }.map(MathM7ActivitySession.soccer)
        case .mathTower: return build(provider.towerChallenge).map(MathM7ActivitySession.tower)
        case .mathMemory: return MemorySession(equivalenceSets: provider.equivalenceSets()).map(MathM7ActivitySession.memory)
        case .pingPong: return nil
        }
    }
    private func choices(_ direction: MathM7ChoiceDirection) -> MultipleChoiceSession? {
        let values = provider.balancedProblems(count: Self.count).compactMap { provider.choiceChallenge(problem: $0, direction: direction) }
        return values.count == Self.count ? MultipleChoiceSession(challenges: values, progressionPolicy: .retryUntilCorrect) : nil
    }
    private func build(_ make: (MathM7Problem) -> BuildChallenge?) -> BuildSession? {
        let values = provider.balancedProblems(count: Self.count).compactMap(make)
        return values.count == Self.count ? BuildSession(challenges: values) : nil
    }
}
