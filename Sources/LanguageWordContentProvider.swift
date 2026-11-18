import Foundation

extension LanguageCurriculumStageIDs {
    static let wordsLevelA = CurriculumStageID(rawValue: "language.words.levelA")
    static let wordsLevelB = CurriculumStageID(rawValue: "language.words.levelB")
    static let wordsLevelC = CurriculumStageID(rawValue: "language.words.levelC")
    static let wordsLevelD = CurriculumStageID(rawValue: "language.words.levelD")
    static let wordsLevelE = CurriculumStageID(rawValue: "language.words.levelE")
}

extension LanguageSkillIDs {
    static let wordRecognition = SkillID(rawValue: "language.wordRecognition")
    static let wordImageAssociation = SkillID(rawValue: "language.wordImageAssociation")
}

struct LanguageWordContentProvider: Sendable {
    private let configuration: ProductConfiguration
    private let categoryID: LanguageWordCategoryID?

    init(
        configuration: ProductConfiguration,
        categoryID: LanguageWordCategoryID? = nil
    ) {
        self.configuration = configuration
        self.categoryID = categoryID
    }

    func challenge(
        for request: ChallengeRequest,
        learnedLanguage: LanguageIdentifier
    ) -> Challenge? {
        guard let content = choiceContent(for: request, learnedLanguage: learnedLanguage),
              let correctItem = content.eligibleItems.randomElement() else {
            return nil
        }
        return challenge(
            for: request,
            learnedLanguage: learnedLanguage,
            content: content,
            correctItem: correctItem
        )
    }

    /// Android WriteScreen's word list for the level: one page for each eligible word,
    /// each word once, in a shuffled order, with the same answers as `challenge(for:)`.
    func challenges(
        for request: ChallengeRequest,
        learnedLanguage: LanguageIdentifier
    ) -> [Challenge] {
        guard let content = choiceContent(for: request, learnedLanguage: learnedLanguage) else {
            return []
        }
        var seen = Set<ContentItemID>()
        return content.eligibleItems
            .filter { seen.insert($0.id).inserted }
            .shuffled()
            .compactMap { item in
                challenge(
                    for: request,
                    learnedLanguage: learnedLanguage,
                    content: content,
                    correctItem: item
                )
            }
    }

    private struct ChoiceContent {
        let levelContent: LanguageWordLevelContent
        let choiceCount: Int
        let eligibleItems: [LanguageWordCatalogItem]
    }

    private func choiceContent(
        for request: ChallengeRequest,
        learnedLanguage: LanguageIdentifier
    ) -> ChoiceContent? {
        guard configuration.contentDomain == .language,
              configuration.allowsLearnedLanguage(learnedLanguage),
              request.activityType == .chooseRepresentation,
              let level = LanguageVocabularyLevel(curriculumStageID: request.curriculumStage),
              request.primarySkill == LanguageSkillIDs.wordRecognition
                || request.primarySkill == LanguageSkillIDs.wordImageAssociation,
              request.interaction == .singleChoice else {
            return nil
        }

        let levelContent = LanguageWordLevelContent.content(for: level)
        guard let choiceCount = resolvedChoiceCount(for: request.countRequirement) else {
            return nil
        }

        let eligibleCategoryItems = levelContent.eligibleItems(
            constrainedTo: categoryID,
            including: { $0.isImageReady },
            where: { $0.items.count >= choiceCount }
        )
        return ChoiceContent(
            levelContent: levelContent,
            choiceCount: choiceCount,
            eligibleItems: eligibleCategoryItems
        )
    }

    private func challenge(
        for request: ChallengeRequest,
        learnedLanguage: LanguageIdentifier,
        content: ChoiceContent,
        correctItem: LanguageWordCatalogItem
    ) -> Challenge? {
        let levelContent = content.levelContent
        let choiceCount = content.choiceCount
        guard let correctText = Self.learnedText(
                  for: correctItem,
                  language: learnedLanguage
              ) else {
            return nil
        }

        let categoryItems = levelContent.items(
            constrainedTo: correctItem.categoryID,
            including: { $0.isImageReady }
        ).shuffled()
        guard categoryItems.count >= choiceCount else {
            return nil
        }

        let distractors = categoryItems
            .filter { $0.id != correctItem.id }
            .shuffled()
            .prefix(choiceCount - 1)
        let selectedItems = ([correctItem] + distractors).shuffled()
        guard selectedItems.count == choiceCount else {
            return nil
        }

        let instanceID = UUID().uuidString
        let promptRepresentations: [Representation]
        let promptSpeechCue: LearningSpeechUtterance?
        let choices: [Choice]

        if request.primarySkill == LanguageSkillIDs.wordRecognition {
            promptRepresentations = [.imageAsset(correctItem.image)]
            promptSpeechCue = correctText.learningSpeechCue
            choices = selectedItems.enumerated().compactMap { index, item in
                guard let text = Self.learnedText(for: item, language: learnedLanguage) else {
                    return nil
                }
                return Choice(
                    id: ChoiceID(rawValue: "\(instanceID).choice.\(index)"),
                    representation: .learningText(text),
                    semanticValue: .contentItem(item.id)
                )
            }
        } else {
            promptRepresentations = [.learningText(correctText)]
            promptSpeechCue = correctText.learningSpeechCue
            choices = selectedItems.enumerated().compactMap { index, item in
                guard let learnedText = Self.learnedText(
                    for: item,
                    language: learnedLanguage
                ) else {
                    return nil
                }
                return Choice(
                    id: ChoiceID(rawValue: "\(instanceID).choice.\(index)"),
                    representation: .imageAsset(item.image),
                    semanticValue: .contentItem(item.id),
                    speechCue: learnedText.learningSpeechCue
                )
            }
        }

        guard choices.count == choiceCount,
              let prompt = Prompt(
                representations: promptRepresentations,
                speechCue: promptSpeechCue
              ) else {
            return nil
        }

        return Challenge(
            id: ChallengeID(rawValue: "\(instanceID).challenge"),
            prompt: prompt,
            choices: choices,
            interaction: .singleChoice,
            validationRule: .exactIdentity,
            expectedAnswer: .semanticValue(.contentItem(correctItem.id)),
            primarySkill: request.primarySkill,
            secondarySkills: [],
            curriculumStage: request.curriculumStage,
            difficulty: request.difficulty,
            languageContentItemID: correctItem.id
        )
    }

    private func resolvedChoiceCount(for requirement: ContentCountRequirement?) -> Int? {
        guard let requirement else {
            return 4
        }
        guard requirement.kind == .choices,
              (2 ... 4).contains(requirement.count) else {
            return nil
        }
        return requirement.count
    }

    static func learnedText(
        for item: LanguageWordCatalogItem,
        language: LanguageIdentifier
    ) -> LearningTextRepresentation? {
        switch language {
        case .english:
            return LearningTextRepresentation(
                text: item.englishText,
                language: .english,
                direction: .leftToRight
            )
        case .hebrew:
            return LearningTextRepresentation(
                text: item.hebrewText,
                language: .hebrew,
                direction: .rightToLeft,
                speechText: item.hebrewSpeechText
            )
        default:
            return nil
        }
    }

    static var levelAFruits: [LanguageWordCatalogItem] {
        LanguageWordCatalog.category(withID: .fruits)?.items ?? []
    }
}
