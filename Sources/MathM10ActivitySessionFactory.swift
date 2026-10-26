import Foundation

enum MathM10ActivitySession: Sendable {
    case learn(LearnSession)
    case pairs(PairsSession)
    case buildNumber(BuildSession)
    case buildQuantity(MathFractionConstructionSession)
    case visualToAnswer(MultipleChoiceSession)
    case answerToRepresentation(MultipleChoiceSession)
    case buildMath(BuildSession)
    case mixed(MathM10MixedSession)
    case cards(CardsSession)
    case soccer(SoccerSession)
    case tower(BuildSession)
    case memory(MemorySession)
}

struct MathM10MixedSession: Sendable {
    static let eligibleActivities: [MathProductionActivityID] = [
        .mathPairs, .buildNumber, .buildQuantity, .visualToAnswer,
        .answerToRepresentation, .buildMath, .mathSoccer, .mathTower, .mathMemory
    ]
    private(set) var currentActivity = Self.eligibleActivities.randomElement() ?? .visualToAnswer
    mutating func advance() {
        currentActivity = Self.eligibleActivities.filter { $0 != currentActivity }.randomElement() ?? currentActivity
    }
}

struct MathM10ActivitySessionFactory: Sendable {
    private static let challengeCount = 6
    private let provider: MathM10ContentProvider
    private let fitGate: MathContentFitGate

    init(configuration: ProductConfiguration, fitGate: MathContentFitGate = .production) {
        precondition(configuration.variant == .minikMath)
        provider = MathM10ContentProvider(fitGate: fitGate)
        self.fitGate = fitGate
    }

    func makeSession(for activity: MathProductionActivityID) -> MathM10ActivitySession? {
        switch activity {
        case .learnMath: return LearnSession(cards: provider.studyCards()).map(MathM10ActivitySession.learn)
        case .mathPairs: return PairsSession(equivalenceSets: provider.equivalenceSets()).map(MathM10ActivitySession.pairs)
        case .buildNumber: return build(provider.buildNumberChallenge).map(MathM10ActivitySession.buildNumber)
        case .buildQuantity:
            let probability = MathM10ContentProvider.problems.filter { $0.form == .probability }
            let rounds = (0..<Self.challengeCount).compactMap {
                provider.probabilityRound(problem: probability[$0 % probability.count])
            }
            return rounds.count == Self.challengeCount
                ? MathFractionConstructionSession(rounds: rounds).map(MathM10ActivitySession.buildQuantity) : nil
        // Android Math Plus ab3e427: Visual → Answer counts a picture at every level.
        case .visualToAnswer: return MathPictureQuestions.session(for: .m10, fitGate: fitGate).map(MathM10ActivitySession.visualToAnswer)
        case .answerToRepresentation: return choices(.answerToRepresentation).map(MathM10ActivitySession.answerToRepresentation)
        case .buildMath: return build(provider.buildMathChallenge).map(MathM10ActivitySession.buildMath)
        case .mathMixed: return .mixed(MathM10MixedSession())
        case .mathCards: return CardsSession(cards: provider.studyCards().shuffled()).map(MathM10ActivitySession.cards)
        case .mathSoccer: return provider.soccerRound().map { SoccerSession(round: $0) }.map(MathM10ActivitySession.soccer)
        case .mathTower: return build(provider.towerChallenge).map(MathM10ActivitySession.tower)
        case .mathMemory: return MemorySession(equivalenceSets: provider.equivalenceSets()).map(MathM10ActivitySession.memory)
        case .pingPong: return nil
        }
    }

    private var problems: [MathM10Problem] { provider.balancedProblems(count: Self.challengeCount) }
    private func choices(_ direction: MathM10ChoiceDirection) -> MultipleChoiceSession? {
        let values = problems.compactMap { provider.choiceChallenge(problem: $0, direction: direction) }
        return values.count == Self.challengeCount
            ? MultipleChoiceSession(challenges: values, progressionPolicy: .retryUntilCorrect) : nil
    }
    private func build(_ make: (MathM10Problem) -> BuildChallenge?) -> BuildSession? {
        let values = problems.compactMap(make)
        return values.count == Self.challengeCount ? BuildSession(challenges: values) : nil
    }
}
