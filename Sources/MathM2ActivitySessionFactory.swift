enum MathM2ActivitySession: Sendable {
    case learn(LearnSession)
    case pairs(PairsSession)
    case buildNumber(BuildSession)
    case buildQuantity(MathCountConstructionSession)
    case visualToAnswer(MultipleChoiceSession)
    case answerToRepresentation(MultipleChoiceSession)
    case buildMath(BuildSession)
    case mixed(MathM2MixedSession)
    case cards(CardsSession)
    case soccer(SoccerSession)
    case tower(MathCountConstructionSession)
    case memory(MemorySession)
}

struct MathM2MixedSession: Sendable {
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
        let alternatives = Self.eligibleActivities.filter { $0 != currentActivity }
        currentActivity = alternatives.randomElement() ?? currentActivity
    }
}

struct MathM2ActivitySessionFactory: Sendable {
    private static let challengeCount = 6
    private let provider: MathM2ContentProvider
    private let fitGate: MathContentFitGate

    init(
        configuration: ProductConfiguration,
        fitGate: MathContentFitGate = .production
    ) {
        precondition(configuration.variant == .minikMath)
        provider = MathM2ContentProvider(fitGate: fitGate)
        self.fitGate = fitGate
    }

    func makeSession(for activity: MathProductionActivityID) -> MathM2ActivitySession? {
        switch activity {
        case .learnMath:
            return LearnSession(cards: provider.studyCards()).map(MathM2ActivitySession.learn)
        case .mathPairs:
            return PairsSession(equivalenceSets: provider.equivalenceSets())
                .map(MathM2ActivitySession.pairs)
        case .buildNumber:
            return buildNumberSession().map(MathM2ActivitySession.buildNumber)
        case .buildQuantity:
            return countSession().map(MathM2ActivitySession.buildQuantity)
        case .visualToAnswer:
            // Android Math Plus ab3e427: Visual → Answer counts a picture at every level.
            return MathPictureQuestions.session(for: .m2, fitGate: fitGate)
                .map(MathM2ActivitySession.visualToAnswer)
        case .answerToRepresentation:
            return choiceSession(direction: .answerToOperation)
                .map(MathM2ActivitySession.answerToRepresentation)
        case .buildMath:
            return buildEquationSession().map(MathM2ActivitySession.buildMath)
        case .mathMixed:
            return .mixed(MathM2MixedSession())
        case .mathCards:
            return CardsSession(cards: provider.studyCards().shuffled())
                .map(MathM2ActivitySession.cards)
        case .mathSoccer:
            return provider.soccerRound().map { SoccerSession(round: $0) }
                .map(MathM2ActivitySession.soccer)
        case .mathTower:
            return countSession().map(MathM2ActivitySession.tower)
        case .mathMemory:
            return MemorySession(equivalenceSets: provider.equivalenceSets())
                .map(MathM2ActivitySession.memory)
        case .pingPong:
            return nil
        }
    }

    private func choiceSession(direction: MathM2ChoiceDirection) -> MultipleChoiceSession? {
        let challenges = facts.compactMap { provider.choiceChallenge(fact: $0, direction: direction) }
        guard challenges.count == Self.challengeCount else { return nil }
        return MultipleChoiceSession(challenges: challenges, progressionPolicy: .retryUntilCorrect)
    }

    private func buildNumberSession() -> BuildSession? {
        let challenges = facts.compactMap(provider.buildNumberChallenge)
        guard challenges.count == Self.challengeCount else { return nil }
        return BuildSession(challenges: challenges)
    }

    private func buildEquationSession() -> BuildSession? {
        let challenges = facts.compactMap(provider.buildEquationChallenge)
        guard challenges.count == Self.challengeCount else { return nil }
        return BuildSession(challenges: challenges)
    }

    private func countSession() -> MathCountConstructionSession? {
        let rounds = facts.compactMap(provider.countRound)
        guard rounds.count == Self.challengeCount else { return nil }
        return MathCountConstructionSession(rounds: rounds)
    }

    private var facts: [MathM2Fact] {
        provider.balancedFacts(count: Self.challengeCount)
    }
}
