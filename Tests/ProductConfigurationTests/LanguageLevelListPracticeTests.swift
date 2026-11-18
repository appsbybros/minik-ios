import XCTest
@testable import MinikPlus

/// Android WriteScreen's level word lists for the choice pages, the answers it counts
/// for each word, the Write check at the end of a list (LevelsHelper.passedTwiceInARow)
/// and the "Level up!" window's message (LevelUpDialogFragment, level_up_text).
final class LanguageLevelListPracticeTests: XCTestCase {
    private var configuration: ProductConfiguration {
        .configuration(for: .minikPlus)
    }

    func testImageToWordLevelListHasEachEligibleWordOfTheLevelOnce() throws {
        for level in [LanguageVocabularyLevel.a, .c] {
            let session = try XCTUnwrap(
                LanguageActivitySessionFactory(configuration: configuration, vocabularyLevel: level)
                    .makeImageToWordLevelListSession(for: .english)
            )
            let words = session.challenges.compactMap(\.languageContentItemID)

            XCTAssertEqual(words.count, session.challengeCount)
            XCTAssertEqual(Set(words).count, words.count)
            XCTAssertEqual(Set(words), eligibleWordChoiceItems(level: level))
            XCTAssertEqual(session.progressionPolicy, .retryUntilCorrect)
            for challenge in session.challenges {
                XCTAssertEqual(challenge.curriculumStage, level.curriculumStageID)
                XCTAssertEqual(challenge.primarySkill, LanguageSkillIDs.wordRecognition)
                XCTAssertEqual(challenge.choices.count, 4)
                guard case .semanticValue(.contentItem(let expected)) = challenge.expectedAnswer else {
                    return XCTFail("Expected the word as the answer.")
                }
                XCTAssertEqual(challenge.languageContentItemID, expected)
            }
        }
    }

    func testWordToImageLevelListHasEachEligibleWordOfTheLevelOnce() throws {
        let session = try XCTUnwrap(
            LanguageActivitySessionFactory(configuration: configuration, vocabularyLevel: .b)
                .makeWordToImageLevelListSession(for: .hebrew)
        )
        let words = session.challenges.compactMap(\.languageContentItemID)

        XCTAssertEqual(words.count, session.challengeCount)
        XCTAssertEqual(Set(words), eligibleWordChoiceItems(level: .b))
        XCTAssertEqual(Set(words).count, words.count)
        for challenge in session.challenges {
            XCTAssertEqual(challenge.curriculumStage, LanguageCurriculumStageIDs.wordsLevelB)
            XCTAssertEqual(challenge.primarySkill, LanguageSkillIDs.wordImageAssociation)
            XCTAssertTrue(challenge.choices.allSatisfy { choice in
                if case .imageAsset = choice.representation { return true }
                return false
            })
        }
    }

    func testLevelListMixesPreviousLevelWordsByTheRamp() throws {
        let previousCount = try XCTUnwrap(
            LanguageActivitySessionFactory(configuration: configuration, vocabularyLevel: .a)
                .makeWordToImageLevelListSession(for: .english)
        ).challengeCount
        let currentCount = try XCTUnwrap(
            LanguageActivitySessionFactory(configuration: configuration, vocabularyLevel: .b)
                .makeWordToImageLevelListSession(for: .english)
        ).challengeCount
        let session = try XCTUnwrap(
            LanguageActivitySessionFactory(
                configuration: configuration,
                vocabularyLevel: .b,
                vocabularyRamp: 90
            ).makeWordToImageLevelListSession(for: .english)
        )
        let stages = session.challenges.map(\.curriculumStage)

        XCTAssertEqual(
            stages.filter { $0 == LanguageCurriculumStageIDs.wordsLevelA }.count,
            Int((Double(previousCount) * 90 / 100).rounded())
        )
        XCTAssertEqual(
            stages.filter { $0 == LanguageCurriculumStageIDs.wordsLevelB }.count,
            Int((Double(currentCount) * 10 / 100).rounded())
        )
        let words = session.challenges.compactMap { LanguageAutoPoolItem(languageWordOf: $0) }
        XCTAssertEqual(words.count, session.challengeCount)
        XCTAssertEqual(Set(words).count, words.count)
        XCTAssertNotNil(LanguageAutoPoolTracker.writeChoices(
            evaluatedLevel: .b,
            challenges: session.challenges
        ))
    }

    func testFirstLetterLevelListsAskEachWordOnceAndCarryTheWord() throws {
        let factory = LanguageActivitySessionFactory(configuration: configuration, vocabularyLevel: .a)
        let levelItems = LanguageWordLevelContent.content(for: .a).items

        for language in [LanguageIdentifier.english, .hebrew] {
            let choices = try XCTUnwrap(factory.makeFirstLetterChoicesLevelListSession(for: language))
            let pictures = try XCTUnwrap(factory.makeFirstLetterPicturesLevelListSession(for: language))

            for session in [choices, pictures] {
                let words = session.challenges.compactMap(\.languageContentItemID)
                XCTAssertEqual(words.count, session.challengeCount)
                XCTAssertEqual(Set(words).count, words.count)
                XCTAssertEqual(session.progressionPolicy, .retryUntilCorrect)
                XCTAssertNotNil(LanguageAutoPoolTracker.writeChoices(
                    evaluatedLevel: .a,
                    challenges: session.challenges
                ))
            }
            // The first letter of the pictured word.
            for challenge in choices.challenges {
                let word = try XCTUnwrap(levelItems.first { $0.id == challenge.languageContentItemID })
                XCTAssertEqual(challenge.prompt.representations, [.imageAsset(word.image)])
                XCTAssertEqual(challenge.curriculumStage, LanguageCurriculumStageIDs.wordsLevelA)
            }
            // The word's picture among the pictures for its first letter.
            for challenge in pictures.challenges {
                let word = try XCTUnwrap(levelItems.first { $0.id == challenge.languageContentItemID })
                let initial = try XCTUnwrap(LanguageLetterPairsContentProvider.initialLetter(
                    for: word,
                    language: language
                ))
                XCTAssertEqual(
                    challenge.expectedAnswer,
                    .semanticValue(.contentItem(LanguageLetterPairsContentProvider.initialConceptID(
                        language: language,
                        initial: initial
                    )))
                )
                XCTAssertTrue(challenge.choices.contains { $0.representation == .imageAsset(word.image) })
            }
        }
    }

    func testRandomChoicePagesStillMakeSixPagesThatCarryTheirWord() throws {
        let factory = LanguageActivitySessionFactory(configuration: configuration)
        let sessions = try [
            XCTUnwrap(factory.makeImageToWordSession(for: .english)),
            XCTUnwrap(factory.makeWordToImageSession(for: .english)),
            XCTUnwrap(factory.makeFirstLetterChoicesSession(for: .english)),
            XCTUnwrap(factory.makeFirstLetterPicturesSession(for: .english))
        ]
        for session in sessions {
            XCTAssertEqual(session.challengeCount, 6)
            XCTAssertTrue(session.challenges.allSatisfy { $0.languageContentItemID != nil })
        }
    }

    func testAlphabetChoicePagesHaveNoLevelWordAndNoLevelCheck() throws {
        let alphabet = try XCTUnwrap(
            LanguageActivitySessionFactory(configuration: configuration)
                .makeMultipleChoiceSession(for: .english)
        )
        XCTAssertNil(LanguageAutoPoolItem(languageWordOf: alphabet.currentChallenge))
        XCTAssertNil(LanguageAutoPoolTracker.writeChoices(
            evaluatedLevel: .a,
            challenges: alphabet.challenges
        ))
    }

    func testChoiceTapsCountForTheWordAndTwoPassingListsMoveTheLevelUp() throws {
        let session = try XCTUnwrap(
            LanguageActivitySessionFactory(configuration: configuration, vocabularyLevel: .a)
                .makeImageToWordLevelListSession(for: .english)
        )
        XCTAssertNil(LanguageAutoPoolTracker.writeChoices(
            evaluatedLevel: nil,
            challenges: session.challenges
        ))
        var state = LanguageAutoProgressionState(scope: LanguageAutoScope(product: .minikPlus))

        // Each word answered right in enough lists for the Write check's 100 answers,
        // and one wrong tap first on the list's first word.
        let rounds = 100 / session.challengeCount + 1
        try recordTap(on: session.challenges[0], result: .incorrect, family: .multipleChoice, in: &state)
        for _ in 0 ..< rounds {
            for challenge in session.challenges {
                try recordTap(on: challenge, result: .correct, family: .multipleChoice, in: &state)
            }
        }
        let correct = rounds * session.challengeCount
        let attempts = correct + 1
        let accuracy = correct * 100 / attempts

        var settings = LanguageParentLevelSettings.androidDefault
        var firstList = try XCTUnwrap(LanguageAutoPoolTracker.writeChoices(
            evaluatedLevel: .a,
            challenges: session.challenges
        ))
        XCTAssertEqual(firstList.activity, .write)
        XCTAssertEqual(
            state.evaluate(try XCTUnwrap(firstList.takeBoundary(isExhausted: true)), settings: &settings),
            .passedOnce(attempts: attempts, accuracyPercent: accuracy)
        )
        XCTAssertEqual(settings.wordLevel, .a)

        var secondList = try XCTUnwrap(LanguageAutoPoolTracker.writeChoices(
            evaluatedLevel: .a,
            challenges: session.challenges
        ))
        let evaluation = state.evaluate(
            try XCTUnwrap(secondList.takeBoundary(isExhausted: true)),
            settings: &settings
        )
        XCTAssertEqual(evaluation, .promoted(from: .a, to: .b, accuracyPercent: accuracy))
        XCTAssertEqual(settings.wordLevel, .b)
        XCTAssertEqual(state.ramp, 90)

        let announcement = try XCTUnwrap(LanguageLevelUpAnnouncement(evaluation: evaluation))
        XCTAssertEqual(announcement.level, .b)
        XCTAssertEqual(announcement.accuracyPercent, accuracy)
    }

    func testMixedChoiceTapsCountAsWriteAnswers() throws {
        let child = try XCTUnwrap(
            LanguageActivitySessionFactory(configuration: configuration)
                .makeMixedChildActivity(for: .wordToPicture, language: .english)
        )
        guard case .multipleChoice(let session) = child.session else {
            return XCTFail("Expected a Mixed choice child.")
        }
        var state = LanguageAutoProgressionState(scope: LanguageAutoScope(product: .minikPlus))
        try recordTap(on: session.currentChallenge, result: .incorrect, family: .mixed, in: &state)
        try recordTap(on: session.currentChallenge, result: .correct, family: .mixed, in: &state)

        XCTAssertEqual(state.evidence.count, 1)
        XCTAssertEqual(state.evidence.first?.contentItemID, session.currentChallenge.languageContentItemID)
        XCTAssertEqual(state.evidence.first?.activity, .write)
        XCTAssertEqual(state.evidence.first?.correctCount, 1)
        XCTAssertEqual(state.evidence.first?.wrongCount, 1)
        XCTAssertNotNil(LanguageAutoPoolTracker.writeChoices(
            evaluatedLevel: child.vocabularyLevel,
            challenges: session.challenges
        ))
    }

    func testPromotionCarriesThePassingCheckAccuracy() throws {
        let word = ContentItemID(rawValue: "word")
        var state = LanguageAutoProgressionState(
            scope: LanguageAutoScope(product: .minikPlus),
            evidence: [LanguageAutoContentEvidence(
                contentItemID: word,
                vocabularyLevel: .a,
                activity: .write,
                correctCount: 95,
                wrongCount: 5
            )],
            consecutivePasses: [.a: 1]
        )
        let boundary = try XCTUnwrap(LanguageAutoPoolBoundary(
            activity: .write,
            evaluatedLevel: .a,
            items: [LanguageAutoPoolItem(contentItemID: word, vocabularyLevel: .a)]
        ))
        XCTAssertEqual(
            state.evaluate(boundary, mode: .automatic, persistedLevel: .a),
            .promoted(from: .a, to: .b, accuracyPercent: 95)
        )
    }

    func testLevelUpMessageUsesTheAccuracyAndAndroidLevelLabel() throws {
        XCTAssertNil(LanguageLevelUpAnnouncement(evaluation: .ignored))
        XCTAssertNil(LanguageLevelUpAnnouncement(
            evaluation: .passedOnce(attempts: 100, accuracyPercent: 95)
        ))
        XCTAssertNil(LanguageLevelUpAnnouncement(
            evaluation: .failed(attempts: 100, accuracyPercent: 80)
        ))
        let announcement = try XCTUnwrap(LanguageLevelUpAnnouncement(
            evaluation: .promoted(from: .a, to: .b, accuracyPercent: 93)
        ))

        XCTAssertEqual(LanguageLevelUpAnnouncement.levelLabel(name: "Easy", level: .b), "Easy - B")
        XCTAssertEqual(
            announcement.message(
                format: "Awesome! %lld%% correct!\nYou're moving up a level (%@)!",
                levelName: "Easy"
            ),
            "Awesome! 93% correct!\nYou're moving up a level (Easy - B)!"
        )
        XCTAssertEqual(
            announcement.message(format: "מעולה! %lld%% הצלחה!\nעליתם רמה (%@)!", levelName: "קל"),
            "מעולה! 93% הצלחה!\nעליתם רמה (קל - B)!"
        )
    }

    func testLevelUpStringsAreTranslatedInBothCatalogs() throws {
        let allLanguages = ["am", "ar", "de", "en", "es", "fr", "he", "nl", "pt-BR", "pt-PT", "ru"]
        let message = "Awesome! %lld%% correct!\nYou're moving up a level (%@)!"
        let keys = ["Level up!", message, "Close", "Beginner", "Easy", "Medium", "Hard", "Very Hard"]

        for (variant, languages) in [
            ("All", allLanguages),
            ("EnglishOnly", allLanguages.filter { $0 != "he" })
        ] {
            let strings = try catalogStrings(variant: variant)
            for key in keys {
                let localizations = try XCTUnwrap(
                    (strings[key] as? [String: Any])?["localizations"] as? [String: Any],
                    "\(variant): \(key)"
                )
                XCTAssertTrue(
                    Set(languages).isSubset(of: Set(localizations.keys)),
                    "\(variant): \(key)"
                )
            }
            let messageLocalizations = try XCTUnwrap(
                (strings[message] as? [String: Any])?["localizations"] as? [String: [String: Any]]
            )
            for language in languages {
                let value = try XCTUnwrap(
                    (messageLocalizations[language]?["stringUnit"] as? [String: Any])?["value"] as? String,
                    "\(variant): \(language)"
                )
                XCTAssertEqual(value.components(separatedBy: "%lld").count, 2, "\(variant): \(language)")
                XCTAssertEqual(value.components(separatedBy: "%%").count, 2, "\(variant): \(language)")
                XCTAssertEqual(value.components(separatedBy: "%@").count, 2, "\(variant): \(language)")
                XCTAssertTrue(value.contains("\n"), "\(variant): \(language)")
            }
        }
    }

    private func eligibleWordChoiceItems(level: LanguageVocabularyLevel) -> Set<ContentItemID> {
        Set(LanguageWordLevelContent.content(for: level).eligibleItems(
            constrainedTo: nil,
            including: { $0.isImageReady },
            where: { $0.items.count >= 4 }
        ).map(\.id))
    }

    /// One tap as the hub records it (MinikActivityHubView.recordLanguageAttempt).
    private func recordTap(
        on challenge: Challenge,
        result: GradedAttemptResult,
        family: ActivityFamily,
        in state: inout LanguageAutoProgressionState
    ) throws {
        let word = try XCTUnwrap(LanguageAutoPoolItem(languageWordOf: challenge))
        let attempt = try XCTUnwrap(ActivityAttemptData(
            itemID: ActivityItemID(rawValue: word.contentItemID.rawValue),
            attemptIndex: 1,
            result: result,
            activityFamily: family,
            skillID: challenge.primarySkill,
            languageContentItemID: word.contentItemID,
            languageVocabularyLevel: word.vocabularyLevel
        ))
        let activity = try XCTUnwrap(LanguageAutoEvidenceRouting.attemptActivity(for: attempt.activityFamily))
        state.record(
            id: UUID(),
            evidence: LanguageAutoAttemptEvidence(
                contentItemID: try XCTUnwrap(attempt.languageContentItemID),
                vocabularyLevel: try XCTUnwrap(attempt.languageVocabularyLevel),
                activity: activity,
                result: attempt.result
            )
        )
    }

    private func catalogStrings(variant: String, file: StaticString = #filePath) throws -> [String: Any] {
        let repoRoot = URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repoRoot
            .appendingPathComponent("Resources")
            .appendingPathComponent("Localization")
            .appendingPathComponent(variant)
            .appendingPathComponent("Localizable.xcstrings")
        let data = try Data(contentsOf: url)
        let catalog = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        return try XCTUnwrap(catalog["strings"] as? [String: Any])
    }
}
