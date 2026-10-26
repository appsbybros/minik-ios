import Foundation

enum MathM9ActivitySession: Sendable {
    case learn(LearnSession)
    case pairs(PairsSession)
    case buildNumber(BuildSession)
    case buildQuantity(MathNumberLinePlacementSession)
    case visualToAnswer(MultipleChoiceSession)
    case answerToRepresentation(MultipleChoiceSession)
    case buildMath(BuildSession)
    case mixed(MathM9MixedSession)
    case cards(CardsSession)
    case soccer(SoccerSession)
    case tower(BuildSession)
    case memory(MemorySession)
}

struct MathM9MixedSession: Sendable {
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

struct MathM9ActivitySessionFactory: Sendable {
    private static let challengeCount = 6
    private let provider: MathM9ContentProvider
    private let fitGate: MathContentFitGate

    init(configuration: ProductConfiguration, fitGate: MathContentFitGate = .production) {
        precondition(configuration.variant == .minikMath)
        provider = MathM9ContentProvider(fitGate: fitGate)
        self.fitGate = fitGate
    }

    func makeSession(for activity: MathProductionActivityID) -> MathM9ActivitySession? {
        switch activity {
        case .learnMath:
            return LearnSession(cards: provider.studyCards()).map(MathM9ActivitySession.learn)
        case .mathPairs:
            return PairsSession(equivalenceSets: provider.equivalenceSets()).map(MathM9ActivitySession.pairs)
        case .buildNumber:
            return build(provider.buildNumberChallenge).map(MathM9ActivitySession.buildNumber)
        case .buildQuantity:
            let signedProblems = MathM9ContentProvider.problems.filter { $0.form == .signedNumberLine }
            let rounds = (0..<Self.challengeCount).compactMap {
                provider.numberLineRound(problem: signedProblems[$0 % signedProblems.count])
            }
            return rounds.count == Self.challengeCount
                ? MathNumberLinePlacementSession(rounds: rounds).map(MathM9ActivitySession.buildQuantity)
                : nil
        case .visualToAnswer:
            // Android Math Plus ab3e427: Visual → Answer counts a picture at every level.
            return MathPictureQuestions.session(for: .m9, fitGate: fitGate)
                .map(MathM9ActivitySession.visualToAnswer)
        case .answerToRepresentation:
            return choices(.answerToRepresentation).map(MathM9ActivitySession.answerToRepresentation)
        case .buildMath:
            return build(provider.buildMathChallenge).map(MathM9ActivitySession.buildMath)
        case .mathMixed:
            return .mixed(MathM9MixedSession())
        case .mathCards:
            return CardsSession(cards: provider.studyCards().shuffled()).map(MathM9ActivitySession.cards)
        case .mathSoccer:
            return provider.soccerRound().map { SoccerSession(round: $0) }.map(MathM9ActivitySession.soccer)
        case .mathTower:
            return build(provider.towerChallenge).map(MathM9ActivitySession.tower)
        case .mathMemory:
            return MemorySession(equivalenceSets: provider.equivalenceSets()).map(MathM9ActivitySession.memory)
        case .pingPong:
            return nil
        }
    }

    private var problems: [MathM9Problem] {
        provider.balancedProblems(count: Self.challengeCount)
    }

    private func choices(_ direction: MathM9ChoiceDirection) -> MultipleChoiceSession? {
        let challenges = problems.compactMap { provider.choiceChallenge(problem: $0, direction: direction) }
        return challenges.count == Self.challengeCount
            ? MultipleChoiceSession(challenges: challenges, progressionPolicy: .retryUntilCorrect)
            : nil
    }

    private func build(_ make: (MathM9Problem) -> BuildChallenge?) -> BuildSession? {
        let challenges = problems.compactMap(make)
        return challenges.count == Self.challengeCount ? BuildSession(challenges: challenges) : nil
    }
}
