struct LanguageActivitySessionFactory: Sendable {
    private static let challengeCount = 6

    let configuration: ProductConfiguration
    let vocabularyLevel: LanguageVocabularyLevel
    let vocabularyRamp: Int

    init(
        configuration: ProductConfiguration,
        vocabularyLevel: LanguageVocabularyLevel = .a,
        vocabularyRamp: Int = 0
    ) {
        self.configuration = configuration
        self.vocabularyLevel = vocabularyLevel
        self.vocabularyRamp = min(100, max(0, vocabularyRamp))
    }

    private var vocabularyStage: CurriculumStageID {
        vocabularyLevel.curriculumStageID
    }

    func makeLearnSession(for language: LanguageIdentifier) -> LearnSession? {
        LearnSession(
            cards: LanguageLearnContentProvider(configuration: configuration).studyCards(for: language),
            progressionPolicy: .loopFromFinalCard
        )
    }

    func makeMultipleChoiceSession(for language: LanguageIdentifier) -> MultipleChoiceSession? {
        guard let difficulty = Difficulty(0.5) else {
            return nil
        }

        let request = ChallengeRequest(
            activityType: .multipleChoice,
            curriculumStage: LanguageCurriculumStageIDs.alphabet,
            primarySkill: LanguageSkillIDs.alphabetRecognition,
            difficulty: difficulty,
            interaction: .singleChoice,
            countRequirement: nil
        )
        let provider = LanguageMultipleChoiceContentProvider(configuration: configuration)

        guard let challenges = makeChallenges(
            count: Self.challengeCount,
            build: {
                provider.challenge(for: request, learnedLanguage: language)
            }
        ) else {
            return nil
        }

        return MultipleChoiceSession(challenges: challenges)
    }

    func makeFirstLetterChoicesSession(
        for language: LanguageIdentifier,
        categoryID: LanguageWordCategoryID? = nil
    ) -> MultipleChoiceSession? {
        makeInitialLetterSession(
            for: language,
            provider: LanguageFirstLetterChoiceContentProvider(
                configuration: configuration,
                categoryID: categoryID
            )
        )
    }

    func makeFirstLetterPicturesSession(
        for language: LanguageIdentifier,
        categoryID: LanguageWordCategoryID? = nil
    ) -> MultipleChoiceSession? {
        makeInitialLetterSession(
            for: language,
            provider: LanguageFirstLetterPictureContentProvider(
                configuration: configuration,
                categoryID: categoryID
            )
        )
    }

    /// Android WriteScreen's level word list for the first-letter page with the
    /// picture: every word of the level once, with previous-level words by the ramp.
    func makeFirstLetterChoicesLevelListSession(
        for language: LanguageIdentifier,
        categoryID: LanguageWordCategoryID? = nil
    ) -> MultipleChoiceSession? {
        makeInitialLetterLevelListSession(
            for: language,
            provider: LanguageFirstLetterChoiceContentProvider(
                configuration: configuration,
                categoryID: categoryID
            )
        )
    }

    /// Android WriteScreen's level word list for the first-letter page with the
    /// pictures: every word of the level once, with previous-level words by the ramp.
    func makeFirstLetterPicturesLevelListSession(
        for language: LanguageIdentifier,
        categoryID: LanguageWordCategoryID? = nil
    ) -> MultipleChoiceSession? {
        makeInitialLetterLevelListSession(
            for: language,
            provider: LanguageFirstLetterPictureContentProvider(
                configuration: configuration,
                categoryID: categoryID
            )
        )
    }

    /// Android WriteScreen's level word list for "choose the word for the picture":
    /// every word of the level once, with previous-level words by the ramp.
    func makeImageToWordLevelListSession(
        for language: LanguageIdentifier,
        categoryID: LanguageWordCategoryID? = nil
    ) -> MultipleChoiceSession? {
        makeWordChoiceLevelListSession(
            for: language,
            categoryID: categoryID,
            skill: LanguageSkillIDs.wordRecognition
        )
    }

    /// Android WriteScreen's level word list for "choose the picture for the word":
    /// every word of the level once, with previous-level words by the ramp.
    func makeWordToImageLevelListSession(
        for language: LanguageIdentifier,
        categoryID: LanguageWordCategoryID? = nil
    ) -> MultipleChoiceSession? {
        makeWordChoiceLevelListSession(
            for: language,
            categoryID: categoryID,
            skill: LanguageSkillIDs.wordImageAssociation
        )
    }

    func makeBuildSession(for language: LanguageIdentifier) -> BuildSession? {
        guard let difficulty = Difficulty(0.5) else {
            return nil
        }

        let request = ChallengeRequest(
            activityType: .build,
            curriculumStage: LanguageCurriculumStageIDs.alphabet,
            primarySkill: LanguageSkillIDs.wordConstruction,
            difficulty: difficulty,
            interaction: .orderedTokens,
            countRequirement: nil
        )
        let provider = LanguageBuildContentProvider(configuration: configuration)

        guard let challenges = makeBuildChallenges(
            count: Self.challengeCount,
            build: {
                provider.buildChallenge(for: request, learnedLanguage: language)
            }
        ) else {
            return nil
        }

        return BuildSession(challenges: challenges)
    }

    func makeWordBuildSession(
        for language: LanguageIdentifier,
        categoryID: LanguageWordCategoryID? = nil
    ) -> BuildSession? {
        guard let difficulty = Difficulty(0.5) else { return nil }
        let provider = LanguageWordBuildContentProvider(
            configuration: configuration,
            categoryID: categoryID
        )
        let currentRequest = wordConstructionRequest(
            activityType: .build,
            level: vocabularyLevel,
            difficulty: difficulty
        )
        let current = provider.buildChallenges(for: currentRequest, learnedLanguage: language)
        let previous = vocabularyLevel.previous.map { previousLevel in
            provider.buildChallenges(
                for: wordConstructionRequest(
                    activityType: .build,
                    level: previousLevel,
                    difficulty: difficulty
                ),
                learnedLanguage: language
            )
        } ?? []
        return BuildSession(challenges: mixedPool(previous: previous, current: current))
    }

    func makeSoccerSession(
        for language: LanguageIdentifier,
        categoryID: LanguageWordCategoryID? = nil
    ) -> SoccerSession? {
        makeSoccerPracticeSession(
            for: language,
            categoryID: categoryID
        )?.currentSession
    }

    func makeTowerSession(
        for language: LanguageIdentifier,
        categoryID: LanguageWordCategoryID? = nil
    ) -> TowerSession? {
        makeTowerPracticeSession(
            for: language,
            categoryID: categoryID
        )?.currentSession
    }

    func makeTowerPracticeSession(
        for language: LanguageIdentifier,
        categoryID: LanguageWordCategoryID? = nil
    ) -> LanguageTowerPracticeSession? {
        guard let difficulty = Difficulty(0.5) else {
            return nil
        }

        let provider = LanguageTowerContentProvider(
            configuration: configuration,
            categoryID: categoryID
        )
        let current = provider.rounds(
            for: wordConstructionRequest(activityType: .tower, level: vocabularyLevel, difficulty: difficulty),
            learnedLanguage: language
        )
        let previous = vocabularyLevel.previous.map { previousLevel in
            provider.rounds(
                for: wordConstructionRequest(activityType: .tower, level: previousLevel, difficulty: difficulty),
                learnedLanguage: language
            )
        } ?? []

        return LanguageTowerPracticeSession(
            rounds: mixedPool(previous: previous, current: current),
            evaluatedLevel: vocabularyLevel
        )
    }

    func makeSoccerPracticeSession(
        for language: LanguageIdentifier,
        categoryID: LanguageWordCategoryID? = nil
    ) -> LanguageSoccerPracticeSession? {
        guard let difficulty = Difficulty(0.5) else {
            return nil
        }

        let provider = LanguageSoccerContentProvider(
            configuration: configuration,
            categoryID: categoryID
        )
        let current = provider.rounds(
            for: wordConstructionRequest(activityType: .soccer, level: vocabularyLevel, difficulty: difficulty),
            learnedLanguage: language
        )
        let previous = vocabularyLevel.previous.map { previousLevel in
            provider.rounds(
                for: wordConstructionRequest(activityType: .soccer, level: previousLevel, difficulty: difficulty),
                learnedLanguage: language
            )
        } ?? []

        return LanguageSoccerPracticeSession(
            rounds: mixedPool(previous: previous, current: current),
            evaluatedLevel: vocabularyLevel
        )
    }

    func makeMixedPracticeSession(
        for language: LanguageIdentifier,
        capabilityPolicy: LanguageMixedCapabilityPolicy = .current
    ) -> LanguageMixedPracticeSession? {
        guard configuration.contentDomain == .language,
              configuration.allowsLearnedLanguage(language),
              let childActivity = makeMixedChildActivity(
                  for: capabilityPolicy.initialMode,
                  language: language
              ) else {
            return nil
        }

        return LanguageMixedPracticeSession(
            capabilityPolicy: capabilityPolicy,
            currentChildActivity: childActivity
        )
    }

    /// Android WriteScreen in mixed mode loads the level's whole word list again
    /// (loadWords) each time the page kind changes, so every child walks the whole
    /// list, with previous-level words by the ramp, until the mode changes after its
    /// 20, 10 or 5 words. A list that ends first is checked for a level up.
    func makeMixedChildActivity(
        for mode: LanguageMixedPracticeMode,
        language: LanguageIdentifier
    ) -> LanguageMixedChildActivity? {
        switch mode {
        case .wordToPicture:
            guard let session = makeWordToImageLevelListSession(for: language) else {
                return nil
            }
            return LanguageMixedChildActivity(
                mode: mode,
                session: .multipleChoice(session),
                vocabularyLevel: vocabularyLevel
            )

        case .pictureToWord:
            guard let session = makeImageToWordLevelListSession(for: language) else {
                return nil
            }
            return LanguageMixedChildActivity(
                mode: mode,
                session: .multipleChoice(session),
                vocabularyLevel: vocabularyLevel
            )

        case .wordBuild:
            guard let session = makeWordBuildSession(for: language) else {
                return nil
            }
            return LanguageMixedChildActivity(
                mode: mode,
                session: .build(session),
                vocabularyLevel: vocabularyLevel
            )
        }
    }

    func makePairsSession(for language: LanguageIdentifier) -> PairsSession? {
        guard let difficulty = Difficulty(0.5) else {
            return nil
        }

        let request = ChallengeRequest(
            activityType: .pairs,
            curriculumStage: LanguageCurriculumStageIDs.alphabet,
            primarySkill: LanguageSkillIDs.letterWordAssociation,
            difficulty: difficulty,
            interaction: .matching,
            countRequirement: nil
        )
        let sets = LanguageMatchingContentProvider(configuration: configuration)
            .equivalenceSets(for: request, learnedLanguage: language)

        guard sets.count == 4 else {
            return nil
        }
        return PairsSession(equivalenceSets: sets)
    }

    func makeLetterPairsSession(
        for language: LanguageIdentifier,
        categoryID: LanguageWordCategoryID? = nil
    ) -> PairsSession? {
        guard let difficulty = Difficulty(0.5) else {
            return nil
        }

        let request = ChallengeRequest(
            activityType: .pairs,
            curriculumStage: vocabularyStage,
            primarySkill: LanguageSkillIDs.initialLetterAssociation,
            difficulty: difficulty,
            interaction: .matching,
            countRequirement: nil
        )
        let provider = LanguageLetterPairsContentProvider(
            configuration: configuration,
            categoryID: categoryID
        )
        guard let session = provider.makeSession(
            for: request,
            learnedLanguage: language
        ), session.equivalenceSets.count == 4 else {
            return nil
        }
        return session
    }

    func makeMemorySession(for language: LanguageIdentifier) -> MemorySession? {
        guard let difficulty = Difficulty(0.5) else {
            return nil
        }

        let request = ChallengeRequest(
            activityType: .memory,
            curriculumStage: LanguageCurriculumStageIDs.alphabet,
            primarySkill: LanguageSkillIDs.letterWordAssociation,
            difficulty: difficulty,
            interaction: .matching,
            countRequirement: nil
        )
        let sets = LanguageMatchingContentProvider(configuration: configuration)
            .equivalenceSets(for: request, learnedLanguage: language)

        guard sets.count == 4 else {
            return nil
        }
        return MemorySession(equivalenceSets: sets)
    }

    func makeWordMemorySession(
        for language: LanguageIdentifier,
        categoryID: LanguageWordCategoryID? = nil
    ) -> MemorySession? {
        guard let difficulty = Difficulty(0.5) else {
            return nil
        }

        let request = ChallengeRequest(
            activityType: .memory,
            curriculumStage: vocabularyStage,
            primarySkill: LanguageSkillIDs.wordImageAssociation,
            difficulty: difficulty,
            interaction: .matching,
            countRequirement: nil
        )
        let content = LanguageWordMemoryContentProvider(
            configuration: configuration,
            categoryID: categoryID
        )
            .content(for: request, learnedLanguage: language)

        guard let content,
              content.equivalenceSets.count == 6 else {
            return nil
        }
        return MemorySession(
            equivalenceSets: content.equivalenceSets,
            revealSpeechCues: content.revealSpeechCues
        )
    }

    func makeImageToWordSession(
        for language: LanguageIdentifier,
        categoryID: LanguageWordCategoryID? = nil
    ) -> MultipleChoiceSession? {
        makeWordChoiceSession(
            for: language,
            categoryID: categoryID,
            skill: LanguageSkillIDs.wordRecognition,
            challengeCount: Self.challengeCount
        )
    }

    func makeWordToImageSession(
        for language: LanguageIdentifier,
        categoryID: LanguageWordCategoryID? = nil
    ) -> MultipleChoiceSession? {
        makeWordChoiceSession(
            for: language,
            categoryID: categoryID,
            skill: LanguageSkillIDs.wordImageAssociation,
            challengeCount: Self.challengeCount
        )
    }

    func makeWordCardsSession(
        for language: LanguageIdentifier,
        categoryID: LanguageWordCategoryID? = nil
    ) -> CardsSession? {
        guard let difficulty = Difficulty(0.5) else {
            return nil
        }

        let request = ChallengeRequest(
            activityType: .cards,
            curriculumStage: vocabularyStage,
            primarySkill: LanguageSkillIDs.wordRecognition,
            difficulty: difficulty,
            interaction: nil,
            countRequirement: nil
        )
        let cards = LanguageWordCardsContentProvider(
            configuration: configuration,
            categoryID: categoryID
        )
            .studyCards(for: request, learnedLanguage: language)

        guard !cards.isEmpty else {
            return nil
        }
        return CardsSession(cards: cards)
    }

    private func makeInitialLetterSession<Provider: InitialLetterChoiceProviding>(
        for language: LanguageIdentifier,
        provider: Provider
    ) -> MultipleChoiceSession? {
        guard let difficulty = Difficulty(0.5) else {
            return nil
        }

        let request = ChallengeRequest(
            activityType: .chooseRepresentation,
            curriculumStage: vocabularyStage,
            primarySkill: LanguageSkillIDs.initialLetterAssociation,
            difficulty: difficulty,
            interaction: .singleChoice,
            countRequirement: nil
        )

        guard let challenges = makeChallenges(
            count: Self.challengeCount,
            build: {
                provider.challenge(for: request, learnedLanguage: language)
            }
        ) else {
            return nil
        }

        return MultipleChoiceSession(
            challenges: challenges,
            progressionPolicy: .retryUntilCorrect
        )
    }

    private func makeWordChoiceSession(
        for language: LanguageIdentifier,
        categoryID: LanguageWordCategoryID?,
        skill: SkillID,
        challengeCount: Int
    ) -> MultipleChoiceSession? {
        guard let difficulty = Difficulty(0.5) else {
            return nil
        }

        let request = ChallengeRequest(
            activityType: .chooseRepresentation,
            curriculumStage: vocabularyStage,
            primarySkill: skill,
            difficulty: difficulty,
            interaction: .singleChoice,
            countRequirement: nil
        )
        let provider = LanguageWordContentProvider(
            configuration: configuration,
            categoryID: categoryID
        )

        guard let challenges = makeChallenges(
            count: challengeCount,
            build: {
                provider.challenge(for: request, learnedLanguage: language)
            }
        ) else {
            return nil
        }

        return MultipleChoiceSession(
            challenges: challenges,
            progressionPolicy: .retryUntilCorrect
        )
    }

    private func makeInitialLetterLevelListSession<Provider: InitialLetterChoiceProviding>(
        for language: LanguageIdentifier,
        provider: Provider
    ) -> MultipleChoiceSession? {
        guard let difficulty = Difficulty(0.5) else {
            return nil
        }

        let current = provider.challenges(
            for: choiceRequest(
                skill: LanguageSkillIDs.initialLetterAssociation,
                level: vocabularyLevel,
                difficulty: difficulty
            ),
            learnedLanguage: language
        )
        let previous = vocabularyLevel.previous.map { previousLevel in
            provider.challenges(
                for: choiceRequest(
                    skill: LanguageSkillIDs.initialLetterAssociation,
                    level: previousLevel,
                    difficulty: difficulty
                ),
                learnedLanguage: language
            )
        } ?? []
        return MultipleChoiceSession(
            challenges: mixedPool(previous: previous, current: current),
            progressionPolicy: .retryUntilCorrect
        )
    }

    private func makeWordChoiceLevelListSession(
        for language: LanguageIdentifier,
        categoryID: LanguageWordCategoryID?,
        skill: SkillID
    ) -> MultipleChoiceSession? {
        guard let difficulty = Difficulty(0.5) else {
            return nil
        }

        let provider = LanguageWordContentProvider(
            configuration: configuration,
            categoryID: categoryID
        )
        let current = provider.challenges(
            for: choiceRequest(skill: skill, level: vocabularyLevel, difficulty: difficulty),
            learnedLanguage: language
        )
        let previous = vocabularyLevel.previous.map { previousLevel in
            provider.challenges(
                for: choiceRequest(skill: skill, level: previousLevel, difficulty: difficulty),
                learnedLanguage: language
            )
        } ?? []
        return MultipleChoiceSession(
            challenges: mixedPool(previous: previous, current: current),
            progressionPolicy: .retryUntilCorrect
        )
    }

    private func choiceRequest(
        skill: SkillID,
        level: LanguageVocabularyLevel,
        difficulty: Difficulty
    ) -> ChallengeRequest {
        ChallengeRequest(
            activityType: .chooseRepresentation,
            curriculumStage: level.curriculumStageID,
            primarySkill: skill,
            difficulty: difficulty,
            interaction: .singleChoice,
            countRequirement: nil
        )
    }

    private func makeChallenges(
        count: Int,
        build: () -> Challenge?
    ) -> [Challenge]? {
        var challenges: [Challenge] = []
        challenges.reserveCapacity(count)

        for _ in 0 ..< count {
            guard let challenge = build() else {
                return nil
            }
            challenges.append(challenge)
        }

        return challenges
    }

    private func makeBuildChallenges(
        count: Int,
        build: () -> BuildChallenge?
    ) -> [BuildChallenge]? {
        var challenges: [BuildChallenge] = []
        challenges.reserveCapacity(count)

        for _ in 0 ..< count {
            guard let challenge = build() else {
                return nil
            }
            challenges.append(challenge)
        }

        return challenges
    }

    private func wordConstructionRequest(
        activityType: ActivityType,
        level: LanguageVocabularyLevel,
        difficulty: Difficulty
    ) -> ChallengeRequest {
        ChallengeRequest(
            activityType: activityType,
            curriculumStage: level.curriculumStageID,
            primarySkill: LanguageSkillIDs.wordConstruction,
            difficulty: difficulty,
            interaction: .orderedTokens,
            countRequirement: nil
        )
    }

    private func mixedPool<Element>(previous: [Element], current: [Element]) -> [Element] {
        LanguageVocabularyPoolMixer.mix(
            previous: previous,
            current: current,
            ramp: vocabularyRamp
        )
    }
}

private protocol InitialLetterChoiceProviding: Sendable {
    func challenge(
        for request: ChallengeRequest,
        learnedLanguage: LanguageIdentifier
    ) -> Challenge?

    func challenges(
        for request: ChallengeRequest,
        learnedLanguage: LanguageIdentifier
    ) -> [Challenge]
}

extension LanguageFirstLetterChoiceContentProvider: InitialLetterChoiceProviding {}
extension LanguageFirstLetterPictureContentProvider: InitialLetterChoiceProviding {}
