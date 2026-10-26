import Foundation

enum MathM1ChoiceDirection: Hashable, Sendable {
    case quantityToNumeral
    case numeralToQuantity
}

struct MathM1ContentProvider: Sendable {
    static let values = Array(0...10)
    private static let difficulty = Difficulty(0.5)!

    func studyCards(shuffled: Bool = false) -> [StudyCard] {
        let values = shuffled ? Self.values.shuffled() : Self.values
        return values.compactMap { value in
            StudyCard(
                id: StudyCardID(rawValue: "m1.card.\(value)"),
                representations: [numeral(value), quantity(value)],
                primarySkill: MathSkillIDs.quantityToNumber,
                curriculumStage: MathCurriculumLevelID.m1.curriculumStageID
            )
        }
    }

    func equivalenceSets(count: Int = 4) -> [EquivalenceSet] {
        Array(Self.values.shuffled().prefix(count)).compactMap { value in
            EquivalenceSet(
                semanticValue: .integer(value),
                representations: [numeral(value), quantity(value)]
            )
        }
    }

    func choiceChallenge(
        target: Int,
        direction: MathM1ChoiceDirection
    ) -> Challenge? {
        guard Self.values.contains(target),
              let choices = choiceValues(for: target) else { return nil }
        let instanceID = "m1.\(direction).\(target).\(UUID().uuidString)"
        let promptRepresentation = direction == .quantityToNumeral
            ? quantity(target)
            : numeral(target)
        guard let prompt = Prompt(representations: [promptRepresentation]) else { return nil }
        let choiceModels = choices.enumerated().map { index, value in
            Choice(
                id: ChoiceID(rawValue: "\(instanceID).choice.\(index)"),
                representation: direction == .quantityToNumeral
                    ? numeral(value)
                    : quantity(value),
                semanticValue: .integer(value)
            )
        }
        return Challenge(
            id: ChallengeID(rawValue: instanceID),
            prompt: prompt,
            choices: choiceModels,
            interaction: .singleChoice,
            validationRule: .numericEquivalence,
            expectedAnswer: .semanticValue(.integer(target)),
            primarySkill: MathSkillIDs.quantityToNumber,
            secondarySkills: [],
            curriculumStage: MathCurriculumLevelID.m1.curriculumStageID,
            difficulty: Self.difficulty
        )
    }

    func buildNumberChallenge(target: Int) -> BuildChallenge? {
        guard Self.values.contains(target),
              let values = choiceValues(for: target),
              let prompt = Prompt(representations: [quantity(target)]) else { return nil }
        let instanceID = "m1.build-number.\(target).\(UUID().uuidString)"
        let tokens = values.enumerated().map { index, value in
            BuildToken(
                id: BuildTokenID(rawValue: "\(instanceID).token.\(index)"),
                representation: numeral(value)
            )
        }
        guard let correctIndex = values.firstIndex(of: target) else { return nil }
        return BuildChallenge(
            id: ChallengeID(rawValue: instanceID),
            prompt: prompt,
            availableTokens: tokens,
            expectedTokenSequence: [tokens[correctIndex].id],
            primarySkill: MathSkillIDs.quantityToNumber,
            curriculumStage: MathCurriculumLevelID.m1.curriculumStageID,
            difficulty: Self.difficulty
        )
    }

    func buildCountChallenge(target: Int) -> BuildChallenge? {
        guard (1...10).contains(target),
              let prompt = Prompt(representations: [quantity(target)]) else { return nil }
        let instanceID = "m1.build-count.\(target).\(UUID().uuidString)"
        let tokens = (0...target).map { value in
            BuildToken(
                id: BuildTokenID(rawValue: "\(instanceID).token.\(value)"),
                representation: numeral(value)
            )
        }
        return BuildChallenge(
            id: ChallengeID(rawValue: instanceID),
            prompt: prompt,
            availableTokens: tokens,
            expectedTokenSequence: Array(tokens.dropFirst().map(\.id)),
            primarySkill: MathSkillIDs.quantityToNumber,
            secondarySkills: [MathSkillIDs.orderValues],
            curriculumStage: MathCurriculumLevelID.m1.curriculumStageID,
            difficulty: Self.difficulty
        )
    }

    func countRound(target: Int) -> MathCountRound? {
        guard Self.values.contains(target) else { return nil }
        let availableCount = max(4, target + 3)
        let instanceID = "m1.count.\(target).\(UUID().uuidString)"
        return MathCountRound(
            id: ChallengeID(rawValue: instanceID),
            target: target,
            availableTokenIDs: (0..<availableCount).map {
                MathCountTokenID(rawValue: "\(instanceID).token.\($0)")
            }
        )
    }

    func soccerRound(answerCount: Int = 6) -> SoccerRound? {
        guard answerCount >= MathPresentationFitPolicy.minimumSoccerAnswerPool,
              answerCount <= Self.values.count else { return nil }
        let answers = Array(Self.values.shuffled().prefix(answerCount))
        let instanceID = "m1.soccer.\(UUID().uuidString)"
        let balls = answers.enumerated().map { index, value in
            SoccerAnswerBall(
                id: SoccerBallID(rawValue: "\(instanceID).ball.\(index)"),
                representation: numeral(value),
                semanticValue: .integer(value)
            )
        }
        let targets = balls.enumerated().compactMap { index, ball -> SoccerChallengeTarget? in
            guard case .integer(let value) = ball.semanticValue,
                  let prompt = Prompt(representations: [quantity(value)]) else { return nil }
            let challenge = Challenge(
                id: ChallengeID(rawValue: "\(instanceID).challenge.\(index)"),
                prompt: prompt,
                choices: [],
                interaction: .singleChoice,
                validationRule: .numericEquivalence,
                expectedAnswer: .semanticValue(.integer(value)),
                primarySkill: MathSkillIDs.quantityToNumber,
                secondarySkills: [],
                curriculumStage: MathCurriculumLevelID.m1.curriculumStageID,
                difficulty: Self.difficulty
            )
            return SoccerChallengeTarget(challenge: challenge, intendedBallID: ball.id)
        }
        guard targets.count == balls.count else { return nil }
        return SoccerRound(
            id: SoccerRoundID(rawValue: "\(instanceID).round"),
            answerBalls: balls,
            challengeTargets: targets
        )
    }

    private func choiceValues(for target: Int) -> [Int]? {
        let domain = Set(Self.values.map(ExactNumericValue.integer))
        guard let request = MathDistractorRequest(
            correctAnswer: .integer(target),
            choiceCount: 4,
            permittedDomain: domain,
            strategies: [
                .offByOne,
                .nearby(offsets: [-2, 2, -3, 3, -4, 4, -5, 5, -6, 6, -7, 7, -8, 8, -9, 9, -10, 10])
            ]
        ) else { return nil }
        // A fixed seed put the right answer in the same place every time a count came back.
        var generator = SystemRandomNumberGenerator()
        switch MathDistractorEngine().generate(for: request, using: &generator) {
        case .success(let values):
            return values.compactMap {
                guard case .integer(let value) = $0 else { return nil }
                return value
            }
        case .failure:
            return nil
        }
    }

    private func numeral(_ value: Int) -> Representation {
        .math(.numeral(MathNumeralRepresentation(
            value: value,
            structureID: RepresentationStructureID(rawValue: "math.m1.numeral.\(value)")
        )))
    }

    private func quantity(_ value: Int) -> Representation {
        .math(.quantity(MathQuantityRepresentation(
            count: value,
            structureID: RepresentationStructureID(rawValue: "math.m1.quantity.\(value)")
        )!))
    }
}
