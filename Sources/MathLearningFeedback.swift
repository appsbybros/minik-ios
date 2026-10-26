import Foundation

// MARK: - Visual → Answer: a picture to count at every level

/// Android Minik Math Plus core/LearningActivities.kt pictureQuestion (ab3e427): "Picture →
/// Number always has a visible quantity, independently of arithmetic level". Level 1 keeps its
/// own 0 to 10 questions; from level 2 the activity counts a picture of 1 to 20 objects (levels
/// 2 and 3) or 1 to 30 (level 4 on), where it used to show an exercise without a picture.
enum MathPictureQuestions {
    static let challengeCount = 6
    private static let difficulty = Difficulty(0.5)!

    static func countLimit(for levelID: MathCurriculumLevelID) -> Int {
        if levelID == .m1 { return 10 }
        if levelID == .m2 || levelID == .m3 { return 20 }
        return 30
    }

    /// Six different amounts, each with four numbers to choose from. The level's fit gate
    /// still decides, so a gate that refuses everything leaves the activity unavailable.
    static func session(
        for levelID: MathCurriculumLevelID,
        fitGate: MathContentFitGate = .production
    ) -> MultipleChoiceSession? {
        let counts = Array((1...countLimit(for: levelID)).shuffled().prefix(challengeCount))
        let challenges = counts.compactMap { challenge(count: $0, levelID: levelID, fitGate: fitGate) }
        guard challenges.count == challengeCount else { return nil }
        return MultipleChoiceSession(challenges: challenges, progressionPolicy: .retryUntilCorrect)
    }

    static func challenge(
        count: Int,
        levelID: MathCurriculumLevelID,
        fitGate: MathContentFitGate = .production
    ) -> Challenge? {
        let limit = countLimit(for: levelID)
        guard (1...limit).contains(count),
              let values = choiceValues(for: count, limit: limit),
              let quantity = MathQuantityRepresentation(
                  count: count,
                  structureID: RepresentationStructureID(rawValue: "math.picture.quantity.\(count)")
              ),
              let prompt = Prompt(representations: [.math(.quantity(quantity))]) else { return nil }
        let instanceID = "\(levelID.rawValue.lowercased()).picture.\(count).\(UUID().uuidString)"
        let choices = values.enumerated().map { index, value in
            Choice(
                id: ChoiceID(rawValue: "\(instanceID).choice.\(index)"),
                representation: numeral(value),
                semanticValue: .integer(value)
            )
        }
        guard choices.count == 4,
              fitGate.allows(choices.map(\.representation), for: .choice) else { return nil }
        return Challenge(
            id: ChallengeID(rawValue: instanceID),
            prompt: prompt,
            choices: choices,
            interaction: .singleChoice,
            validationRule: .numericEquivalence,
            expectedAnswer: .semanticValue(.integer(count)),
            primarySkill: MathSkillIDs.quantityToNumber,
            secondarySkills: [],
            curriculumStage: levelID.curriculumStageID,
            difficulty: difficulty
        )
    }

    private static func choiceValues(for target: Int, limit: Int) -> [Int]? {
        let domain = Set((1...limit).map(ExactNumericValue.integer))
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

    private static func numeral(_ value: Int) -> Representation {
        .math(.numeral(MathNumeralRepresentation(
            value: value,
            structureID: RepresentationStructureID(rawValue: "math.picture.numeral.\(value)")
        )))
    }
}

// MARK: - Math Soccer: a directional, speed-sensitive swipe

/// Android core/LearningActivities.kt SoccerShot and soccerShot (ab3e427): the same swipe
/// direction moves the ball and decides the goal. Positions and movements are fractions of the
/// field (0 left, 1 right; 0 top, 1 bottom); the goal mouth spans 0.22 to 0.78 of the width.
struct MathSoccerShot: Equatable, Sendable {
    let endX: Double
    let durationMilliseconds: Int

    var isInsideGoal: Bool {
        (0.22...0.78).contains(endX)
    }

    /// VoiceOver's kick, and the kick without a swipe: the middle of the goal.
    static let straight = MathSoccerShot(endX: 0.5, durationMilliseconds: 650)

    /// nil unless the swipe goes up toward the goal. A quicker swipe flies faster.
    static func make(
        startX: Double,
        startY: Double,
        dx: Double,
        dy: Double,
        elapsedMilliseconds: Double
    ) -> MathSoccerShot? {
        guard dy <= -0.045 else { return nil }
        let endX = min(1.15, max(-0.15, startX + dx / -dy * (startY - 0.17)))
        let speed = -dy / (max(60, elapsedMilliseconds) / 1000)
        let duration = min(850, max(400, Int(850 - speed * 220)))
        return MathSoccerShot(endX: endX, durationMilliseconds: duration)
    }
}

// MARK: - Math Cards: sixteen rules with examples

/// Android ActivityScreens.kt FactCards (ab3e427): sixteen useful rules, each with an example,
/// four to a page. A tap reads the rule and its example in the interface language.
enum MathRuleCard: Int, CaseIterable, Sendable {
    case countOrder, oneMore, addZero, takeZero, timesOne, timesZero, divideOne, sameSubtract
    case addOrder, multiplyOrder, tenOnes, tenTens, double, half, inverse, equalGroups

    static let pageSize = 4

    static var pageCount: Int {
        allCases.count / pageSize
    }

    static func page(_ index: Int) -> [MathRuleCard] {
        let start = min(max(0, index), pageCount - 1) * pageSize
        return Array(allCases[start..<(start + pageSize)])
    }

    var rule: String {
        switch self {
        case .countOrder: return String(localized: "Count each object once. The last number tells you how many there are.")
        case .oneMore: return String(localized: "Adding one gives the next number.")
        case .addZero: return String(localized: "Adding zero leaves the number unchanged.")
        case .takeZero: return String(localized: "Subtracting zero leaves the number unchanged.")
        case .timesOne: return String(localized: "Any number multiplied by one stays the same.")
        case .timesZero: return String(localized: "Any number multiplied by zero equals zero.")
        case .divideOne: return String(localized: "Dividing a number by one leaves it unchanged.")
        case .sameSubtract: return String(localized: "Subtracting a number from itself gives zero.")
        case .addOrder: return String(localized: "Swapping the two numbers in an addition gives the same sum.")
        case .multiplyOrder: return String(localized: "Swapping the two numbers in a multiplication gives the same answer.")
        case .tenOnes: return String(localized: "Ten ones make one ten.")
        case .tenTens: return String(localized: "Ten tens make one hundred.")
        case .double: return String(localized: "Doubling a number is the same as adding it to itself.")
        case .half: return String(localized: "Half means splitting into two equal parts.")
        case .inverse: return String(localized: "Subtraction can undo addition.")
        case .equalGroups: return String(localized: "Multiplication counts equal groups.")
        }
    }

    /// The example as Android writes it; it is never translated.
    var example: String {
        switch self {
        case .countOrder: return "1, 2, 3, 4, 5"
        case .oneMore: return "4 + 1 = 5"
        case .addZero: return "7 + 0 = 7"
        case .takeZero: return "8 − 0 = 8"
        case .timesOne: return "6 × 1 = 6"
        case .timesZero: return "9 × 0 = 0"
        case .divideOne: return "8 ÷ 1 = 8"
        case .sameSubtract: return "5 − 5 = 0"
        case .addOrder: return "3 + 4 = 4 + 3"
        case .multiplyOrder: return "2 × 5 = 5 × 2"
        case .tenOnes: return "10 × 1 = 10"
        case .tenTens: return "10 × 10 = 100"
        case .double: return "4 + 4 = 2 × 4"
        case .half: return "8 ÷ 2 = 4"
        case .inverse: return "3 + 5 = 8; 8 − 5 = 3"
        case .equalGroups: return "3 × 2 = 2 + 2 + 2"
        }
    }
}

// MARK: - Hands-on examples

/// Android AppState.needsDemo and finishDemo (dc12a5c): Number Building and Math Soccer open
/// with one guided example the first time. It awards no points and never changes the level;
/// finishing or skipping it is remembered.
struct MathActivityDemoRepository {
    static let activities: [MathProductionActivityID] = [.mathSoccer, .buildNumber]
    static let keyPrefix = "minik.math.demo-done."

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    static func storageKey(for activity: MathProductionActivityID) -> String {
        keyPrefix + activity.rawValue
    }

    /// App Store screenshot captures never show the example, as with the how-to card.
    func needsDemo(_ activity: MathProductionActivityID) -> Bool {
        Self.activities.contains(activity)
            && StoreScreenshotScene.name == nil
            && !userDefaults.bool(forKey: Self.storageKey(for: activity))
    }

    func finishDemo(_ activity: MathProductionActivityID) {
        userDefaults.set(true, forKey: Self.storageKey(for: activity))
    }
}

/// The two examples' content. Android builds 12 with one ten and two ones; iOS Build Number
/// puts an answer's digits in order, so its example shows 12 as one ten and two ones and asks
/// for 1, then 2. Android's soccer example is 1 + 1 with the balls 1, 2 and 3.
enum MathActivityDemoContent {
    private static let difficulty = Difficulty(0.1)!

    static func buildNumberSession() -> BuildSession? {
        let id = "demo.build-number.12"
        guard let ten = MathPlaceValueComponent(placeValue: 10, digit: 1),
              let ones = MathPlaceValueComponent(placeValue: 1, digit: 2),
              let blocks = MathPlaceValueRepresentation(
                  components: [ten, ones],
                  structureID: RepresentationStructureID(rawValue: "\(id).blocks")
              ),
              let prompt = Prompt(representations: [.math(.placeValue(blocks))]) else { return nil }
        let tokens = ["1", "2", "3", "0"].enumerated().map { index, digit in
            BuildToken(
                id: BuildTokenID(rawValue: "\(id).token.\(index)"),
                representation: .mathExpression(MathExpressionRepresentation(
                    expression: digit,
                    structureID: RepresentationStructureID(rawValue: "\(id).digit.\(index)")
                ))
            )
        }
        guard let challenge = BuildChallenge(
            id: ChallengeID(rawValue: id),
            prompt: prompt,
            availableTokens: tokens,
            expectedTokenSequence: [tokens[0].id, tokens[1].id],
            primarySkill: MathSkillIDs.placeValue,
            curriculumStage: MathCurriculumLevelID.m3.curriculumStageID,
            difficulty: difficulty
        ) else { return nil }
        return BuildSession(challenges: [challenge])
    }

    /// SoccerRound wants an exercise for every ball; the example only ever shows the first,
    /// 1 + 1, and starts it again until it is a goal.
    static func soccerRound() -> SoccerRound? {
        let id = "demo.soccer"
        let balls = [1, 2, 3].map { value in
            SoccerAnswerBall(
                id: SoccerBallID(rawValue: "\(id).ball.\(value)"),
                representation: .math(.numeral(MathNumeralRepresentation(
                    value: value,
                    structureID: RepresentationStructureID(rawValue: "\(id).numeral.\(value)")
                ))),
                semanticValue: .integer(value)
            )
        }
        let exercises = [(left: 1, right: 1), (left: 1, right: 0), (left: 1, right: 2)]
        let targets = exercises.enumerated().compactMap { index, exercise -> SoccerChallengeTarget? in
            let answer = exercise.left + exercise.right
            guard let ball = balls.first(where: { $0.semanticValue == .integer(answer) }),
                  let prompt = Prompt(representations: [.math(.arithmeticExpression(MathArithmeticRepresentation(
                      left: .integer(exercise.left),
                      operation: .addition,
                      right: .integer(exercise.right),
                      structureID: RepresentationStructureID(rawValue: "\(id).exercise.\(index)")
                  )))]) else { return nil }
            let challenge = Challenge(
                id: ChallengeID(rawValue: "\(id).challenge.\(index)"),
                prompt: prompt,
                choices: [],
                interaction: .singleChoice,
                validationRule: .numericEquivalence,
                expectedAnswer: .semanticValue(.integer(answer)),
                primarySkill: MathSkillIDs.quantityToNumber,
                secondarySkills: [],
                curriculumStage: MathCurriculumLevelID.m1.curriculumStageID,
                difficulty: difficulty
            )
            return SoccerChallengeTarget(challenge: challenge, intendedBallID: ball.id)
        }
        guard targets.count == balls.count else { return nil }
        return SoccerRound(
            id: SoccerRoundID(rawValue: "\(id).round"),
            answerBalls: balls,
            challengeTargets: targets
        )
    }
}
