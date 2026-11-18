import Foundation

struct LanguageFirstLetterPictureContentProvider: Sendable {
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
              request.primarySkill == LanguageSkillIDs.initialLetterAssociation,
              request.interaction == .singleChoice else {
            return nil
        }

        let levelContent = LanguageWordLevelContent.content(for: level)
        guard let choiceCount = resolvedChoiceCount(for: request.countRequirement) else {
            return nil
        }

        let eligibleItems = levelContent.eligibleItems(
            constrainedTo: categoryID,
            including: { $0.isImageReady },
            where: { category in
                distinctInitials(
                    in: category.items,
                    learnedLanguage: learnedLanguage
                ).count >= choiceCount
            }
        )
        return ChoiceContent(
            levelContent: levelContent,
            choiceCount: choiceCount,
            eligibleItems: eligibleItems
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
        let categoryItems = levelContent.items(
            constrainedTo: correctItem.categoryID,
            including: { $0.isImageReady }
        ).shuffled()
        guard let correctInitial = LanguageLetterPairsContentProvider.initialLetter(
                for: correctItem,
                language: learnedLanguage
              ),
              let prompt = prompt(
                initial: correctInitial,
                learnedLanguage: learnedLanguage
              ) else {
            return nil
        }

        let distractors = categoryItems
            .filter { candidate in
                candidate.category == correctItem.category
                    && candidate.id != correctItem.id
            }
            .shuffled()
            .compactMap { candidate -> (LanguageWordCatalogItem, String)? in
                guard let initial = LanguageLetterPairsContentProvider.initialLetter(
                    for: candidate,
                    language: learnedLanguage
                ) else {
                    return nil
                }
                return (candidate, initial)
            }
            .filter { _, initial in
                initial != correctInitial
            }
            .reduce(into: [(LanguageWordCatalogItem, String)]()) { result, pair in
                guard !result.contains(where: { $0.1 == pair.1 }) else {
                    return
                }
                result.append(pair)
            }

        let distractorCount = choiceCount - 1
        guard distractors.count >= distractorCount else {
            return nil
        }

        let selectedItems = ([correctItem] + distractors.prefix(distractorCount).map(\.0)).shuffled()
        let instanceID = UUID().uuidString
        let choices = selectedItems.enumerated().compactMap { index, item -> Choice? in
            guard let initial = LanguageLetterPairsContentProvider.initialLetter(
                for: item,
                language: learnedLanguage
            ) else {
                return nil
            }

            guard let learnedText = LanguageWordContentProvider.learnedText(
                for: item,
                language: learnedLanguage
            ) else {
                return nil
            }

            return Choice(
                id: ChoiceID(rawValue: "\(instanceID).choice.\(index)"),
                representation: .imageAsset(item.image),
                semanticValue: .contentItem(
                    LanguageLetterPairsContentProvider.initialConceptID(
                        language: learnedLanguage,
                        initial: initial
                    )
                ),
                speechCue: learnedText.learningSpeechCue
            )
        }
        guard choices.count == choiceCount else {
            return nil
        }

        return Challenge(
            id: ChallengeID(rawValue: "\(instanceID).challenge"),
            prompt: prompt,
            choices: choices,
            interaction: .singleChoice,
            validationRule: .exactIdentity,
            expectedAnswer: .semanticValue(
                .contentItem(
                    LanguageLetterPairsContentProvider.initialConceptID(
                        language: learnedLanguage,
                        initial: correctInitial
                    )
                )
            ),
            primarySkill: request.primarySkill,
            secondarySkills: [],
            curriculumStage: request.curriculumStage,
            difficulty: request.difficulty,
            languageContentItemID: correctItem.id
        )
    }

    private func resolvedChoiceCount(
        for requirement: ContentCountRequirement?
    ) -> Int? {
        guard let requirement else {
            return 4
        }
        guard requirement.kind == .choices,
              (2 ... 4).contains(requirement.count) else {
            return nil
        }
        return requirement.count
    }

    private func prompt(
        initial: String,
        learnedLanguage: LanguageIdentifier
    ) -> Prompt? {
        let direction: ContentDirection
        switch learnedLanguage {
        case .english:
            direction = .leftToRight
        case .hebrew:
            direction = .rightToLeft
        default:
            return nil
        }

        return Prompt(representations: [
            .learningText(
                LearningTextRepresentation(
                    text: initial,
                    language: learnedLanguage,
                    direction: direction
                )
            )
        ])
    }

    private func distinctInitials(
        in items: [LanguageWordCatalogItem],
        learnedLanguage: LanguageIdentifier
    ) -> Set<String> {
        Set(items.compactMap {
            LanguageLetterPairsContentProvider.initialLetter(
                for: $0,
                language: learnedLanguage
            )
        })
    }
}
