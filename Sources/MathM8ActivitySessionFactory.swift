import Foundation

enum MathM8ActivitySession: Sendable {
    case learn(LearnSession)
    case pairs(PairsSession)
    case buildNumber(BuildSession)
    case buildQuantity(MathFractionConstructionSession)
    case visualToAnswer(MultipleChoiceSession)
    case answerToRepresentation(MultipleChoiceSession)
    case buildMath(BuildSession)
    case mixed(MathM8MixedSession)
    case cards(CardsSession)
    case soccer(SoccerSession)
    case tower(BuildSession)
    case memory(MemorySession)
}

struct MathM8MixedSession: Sendable {
    static let eligibleActivities: [MathProductionActivityID] = [
        .mathPairs, .buildNumber, .buildQuantity, .visualToAnswer,
        .answerToRepresentation, .buildMath, .mathSoccer, .mathTower, .mathMemory
    ]
    private(set) var currentActivity = Self.eligibleActivities.randomElement() ?? .visualToAnswer

    mutating func advance() {
        currentActivity = Self.eligibleActivities
            .filter { $0 != currentActivity }
            .randomElement() ?? currentActivity
    }
}

struct MathM8ActivitySessionFactory: Sendable {
    private static let challengeCount = 6
    private let provider: MathM8ContentProvider
    private let fitGate: MathContentFitGate

    init(configuration: ProductConfiguration, fitGate: MathContentFitGate = .production) {
        precondition(configuration.variant == .minikMath)
        provider = MathM8ContentProvider(fitGate: fitGate)
        self.fitGate = fitGate
    }

    func makeSession(for activity: MathProductionActivityID) -> MathM8ActivitySession? {
        switch activity {
        case .learnMath:
            return LearnSession(cards: provider.studyCards()).map(MathM8ActivitySession.learn)
        case .mathPairs:
            return PairsSession(equivalenceSets: provider.equivalenceSets()).map(MathM8ActivitySession.pairs)
        case .buildNumber:
            return build(provider.buildNumberChallenge).map(MathM8ActivitySession.buildNumber)
        case .buildQuantity:
            let rounds = problems.compactMap(provider.proportionRound)
            return rounds.count == Self.challengeCount
                ? MathFractionConstructionSession(rounds: rounds).map(MathM8ActivitySession.buildQuantity)
                : nil
        case .visualToAnswer:
            // Android Math Plus ab3e427: Visual → Answer counts a picture at every level.
            return MathPictureQuestions.session(for: .m8, fitGate: fitGate)
                .map(MathM8ActivitySession.visualToAnswer)
        case .answerToRepresentation:
            return choices(.answerToRepresentation).map(MathM8ActivitySession.answerToRepresentation)
        case .buildMath:
            return build(provider.buildMathChallenge).map(MathM8ActivitySession.buildMath)
        case .mathMixed:
            return .mixed(MathM8MixedSession())
        case .mathCards:
            return CardsSession(cards: provider.studyCards().shuffled()).map(MathM8ActivitySession.cards)
        case .mathSoccer:
            return provider.soccerRound().map { SoccerSession(round: $0) }.map(MathM8ActivitySession.soccer)
        case .mathTower:
            return build(provider.towerChallenge).map(MathM8ActivitySession.tower)
        case .mathMemory:
            return MemorySession(equivalenceSets: provider.equivalenceSets()).map(MathM8ActivitySession.memory)
        case .pingPong:
            return nil
        }
    }

    private var problems: [MathM8Problem] {
        provider.balancedProblems(count: Self.challengeCount)
    }

    private func choices(_ direction: MathM8ChoiceDirection) -> MultipleChoiceSession? {
        let challenges = problems.compactMap { provider.choiceChallenge(problem: $0, direction: direction) }
        return challenges.count == Self.challengeCount
            ? MultipleChoiceSession(challenges: challenges, progressionPolicy: .retryUntilCorrect)
            : nil
    }

    private func build(_ make: (MathM8Problem) -> BuildChallenge?) -> BuildSession? {
        let challenges = problems.compactMap(make)
        return challenges.count == Self.challengeCount ? BuildSession(challenges: challenges) : nil
    }
}
