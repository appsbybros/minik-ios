import XCTest
@testable import MinikPlus

final class LanguageMixedPracticeTests: XCTestCase {
    func testCurrentPolicyCyclesAtTwentyTenAndFiveAdvancesForTwoCompleteCycles() {
        var progression = LanguageMixedProgression()

        for _ in 0 ..< 2 {
            assertAdvance(
                progression: &progression,
                count: 20,
                from: .wordToPicture,
                to: .pictureToWord
            )
            assertAdvance(
                progression: &progression,
                count: 10,
                from: .pictureToWord,
                to: .wordBuild
            )
            assertAdvance(
                progression: &progression,
                count: 5,
                from: .wordBuild,
                to: .wordToPicture
            )
        }

        XCTAssertEqual(progression.currentMode, .wordToPicture)
        XCTAssertEqual(progression.advancesInCurrentMode, 0)
    }

    func testNonAdvancingInteractionDoesNotIncrementOrChangeMode() {
        var progression = LanguageMixedProgression()

        for _ in 0 ..< 25 {
            XCTAssertEqual(progression.record(.interactionDidNotAdvance), .ignored)
        }

        XCTAssertEqual(progression.currentMode, .wordToPicture)
        XCTAssertEqual(progression.advancesInCurrentMode, 0)
    }

    func testCapabilityPolicyCanOmitModeWithoutViewBranching() throws {
        let policy = try XCTUnwrap(LanguageMixedCapabilityPolicy(
            enabledModes: [.wordToPicture, .wordBuild]
        ))
        var progression = LanguageMixedProgression(capabilityPolicy: policy)

        for _ in 0 ..< 20 {
            progression.record(.advancedCurrentWord)
        }
        XCTAssertEqual(progression.currentMode, .wordBuild)
        XCTAssertEqual(progression.advancesInCurrentMode, 0)

        for _ in 0 ..< 5 {
            progression.record(.advancedCurrentWord)
        }
        XCTAssertEqual(progression.currentMode, .wordToPicture)
        XCTAssertEqual(progression.advancesInCurrentMode, 0)
    }

    func testPracticeSessionOwnsReplacementChildWhenModeChanges() throws {
        let factory = LanguageActivitySessionFactory(
            configuration: .configuration(for: .minikPlus)
        )
        var session = try XCTUnwrap(factory.makeMixedPracticeSession(for: .english))
        let initialChildID = session.currentChildActivity.id

        for _ in 0 ..< 19 {
            session.record(.advancedCurrentWord) { mode in
                factory.makeMixedChildActivity(for: mode, language: .english)
            }
        }

        XCTAssertEqual(session.currentMode, .wordToPicture)
        XCTAssertEqual(session.currentChildActivity.id, initialChildID)

        XCTAssertEqual(
            session.record(.advancedCurrentWord) { mode in
                factory.makeMixedChildActivity(for: mode, language: .english)
            },
            .modeChanged(from: .wordToPicture, to: .pictureToWord)
        )
        XCTAssertEqual(session.currentMode, .pictureToWord)
        XCTAssertEqual(session.advancesInCurrentMode, 0)
        XCTAssertEqual(session.currentChildActivity.mode, .pictureToWord)
        guard case .multipleChoice(let childSession) = session.currentChildActivity.session else {
            return XCTFail("Expected the replacement to use MultipleChoiceSession.")
        }
        // Android loadWords on the page change: the level's whole word list again.
        let levelList = try XCTUnwrap(factory.makeImageToWordLevelListSession(for: .english))
        XCTAssertEqual(childSession.challengeCount, levelList.challengeCount)
        XCTAssertEqual(session.currentChildActivity.vocabularyLevel, .a)
    }

    func testFailedModeTransitionDoesNotAdvanceOrDuplicateProgress() throws {
        let factory = LanguageActivitySessionFactory(
            configuration: .configuration(for: .minikPlus)
        )
        var session = try XCTUnwrap(factory.makeMixedPracticeSession(for: .english))
        let childID = session.currentChildActivity.id

        for _ in 0 ..< 19 {
            XCTAssertEqual(
                session.record(.advancedCurrentWord) { mode in
                    factory.makeMixedChildActivity(for: mode, language: .english)
                },
                .advanced
            )
        }

        XCTAssertEqual(
            session.record(.advancedCurrentWord) { _ in nil },
            .ignored
        )
        XCTAssertEqual(session.currentMode, .wordToPicture)
        XCTAssertEqual(session.advancesInCurrentMode, 19)
        XCTAssertEqual(session.currentChildActivity.id, childID)
    }

    func testStaleChildCallbacksCannotAdvanceOrReplaceCurrentChild() throws {
        let factory = LanguageActivitySessionFactory(
            configuration: .configuration(for: .minikPlus)
        )
        var session = try XCTUnwrap(factory.makeMixedPracticeSession(for: .english))
        let staleChildID = session.currentChildActivity.id

        for _ in 0 ..< 20 {
            _ = session.record(
                .advancedCurrentWord,
                fromChildWithID: staleChildID
            ) { mode in
                factory.makeMixedChildActivity(for: mode, language: .english)
            }
        }

        let currentChildID = session.currentChildActivity.id
        XCTAssertNotEqual(currentChildID, staleChildID)
        XCTAssertEqual(session.currentMode, .pictureToWord)
        XCTAssertEqual(session.advancesInCurrentMode, 0)
        XCTAssertEqual(
            session.record(.advancedCurrentWord, fromChildWithID: staleChildID) { mode in
                factory.makeMixedChildActivity(for: mode, language: .english)
            },
            .ignored
        )
        XCTAssertFalse(session.replaceCompletedChild(withID: staleChildID) { mode in
            factory.makeMixedChildActivity(for: mode, language: .english)
        })
        XCTAssertEqual(session.currentChildActivity.id, currentChildID)
        XCTAssertEqual(session.currentMode, .pictureToWord)
        XCTAssertEqual(session.advancesInCurrentMode, 0)
    }

    func testProductConfigurationControlsMixedAvailabilityAndLearnedLanguage() {
        let plusFactory = LanguageActivitySessionFactory(
            configuration: .configuration(for: .minikPlus)
        )
        let englishOnlyFactory = LanguageActivitySessionFactory(
            configuration: .configuration(for: .minikPlusEnglish)
        )
        let mathFactory = LanguageActivitySessionFactory(
            configuration: .configuration(for: .minikMath)
        )

        XCTAssertNotNil(plusFactory.makeMixedPracticeSession(for: .english))
        XCTAssertNotNil(plusFactory.makeMixedPracticeSession(for: .hebrew))
        XCTAssertNotNil(englishOnlyFactory.makeMixedPracticeSession(for: .english))
        XCTAssertNil(englishOnlyFactory.makeMixedPracticeSession(for: .hebrew))
        XCTAssertNil(mathFactory.makeMixedPracticeSession(for: .english))
    }

    func testMixedIsAProductionWordsActivity() throws {
        let sections = ActivityCatalog.languageSections(
            for: .configuration(for: .minikPlus)
        )
        let words = try XCTUnwrap(sections.first { $0.id == "words" })

        XCTAssertTrue(words.activities.contains(.mixed))
        XCTAssertTrue(sections
            .filter { $0.id != "words" }
            .allSatisfy { !$0.activities.contains(.mixed) })
    }

    func testChildActivitiesUseExistingWordProviderAndEngineSemantics() throws {
        let factory = LanguageActivitySessionFactory(
            configuration: .configuration(for: .minikPlus)
        )

        let wordToPicture = try XCTUnwrap(factory.makeMixedChildActivity(
            for: .wordToPicture,
            language: .english
        ))
        let pictureToWord = try XCTUnwrap(factory.makeMixedChildActivity(
            for: .pictureToWord,
            language: .hebrew
        ))
        let wordBuild = try XCTUnwrap(factory.makeMixedChildActivity(
            for: .wordBuild,
            language: .english
        ))

        try assertChoiceActivity(
            wordToPicture,
            expectedMode: .wordToPicture,
            expectedSkill: LanguageSkillIDs.wordImageAssociation,
            promptIsLearningText: true
        )
        try assertChoiceActivity(
            pictureToWord,
            expectedMode: .pictureToWord,
            expectedSkill: LanguageSkillIDs.wordRecognition,
            promptIsLearningText: false
        )

        XCTAssertEqual(wordBuild.mode, .wordBuild)
        guard case .build(let buildSession) = wordBuild.session else {
            return XCTFail("Expected Mixed Word Build to use BuildSession.")
        }
        // Android loadWords: the level's whole word list, not just the five words built
        // before the page changes.
        let levelList = try XCTUnwrap(factory.makeWordBuildSession(for: .english))
        XCTAssertEqual(buildSession.challengeCount, levelList.challengeCount)
        XCTAssertEqual(wordBuild.vocabularyLevel, .a)
        for challenge in buildSession.challenges {
            XCTAssertEqual(challenge.primarySkill, LanguageSkillIDs.wordConstruction)
            XCTAssertEqual(challenge.validationMode, .immediatePrefix)
            XCTAssertTrue(challenge.prompt.representations.allSatisfy(isImageAsset))
            XCTAssertTrue(challenge.availableTokens.allSatisfy {
                isLearningText($0.representation)
            })
        }
    }

    func testMixedChoiceTelemetryUsesStableVocabularyIdentityAndLearnedSpeech() throws {
        let factory = LanguageActivitySessionFactory(
            configuration: .configuration(for: .minikPlus)
        )

        for language in [LanguageIdentifier.english, .hebrew] {
            for mode in [LanguageMixedPracticeMode.wordToPicture, .pictureToWord] {
                let activity = try XCTUnwrap(factory.makeMixedChildActivity(
                    for: mode,
                    language: language
                ))
                guard case .multipleChoice(let session) = activity.session else {
                    return XCTFail("Expected a Mixed choice child.")
                }

                XCTAssertEqual(session.progressionPolicy, .retryUntilCorrect)
                for challenge in session.challenges {
                    guard case .semanticValue(.contentItem(let contentItemID)) = challenge.expectedAnswer else {
                        return XCTFail("Expected stable vocabulary identity.")
                    }
                    XCTAssertEqual(
                        MultipleChoiceAttemptIdentity.itemID(
                            for: challenge,
                            usesExpectedSemanticIdentity: true
                        ),
                        ActivityItemID(rawValue: contentItemID.rawValue)
                    )
                    XCTAssertNotNil(challenge.prompt.learningSpeechCue)
                    XCTAssertTrue(challenge.choices.allSatisfy {
                        $0.learningSpeechCue != nil
                    })
                }
            }
        }
    }

    func testMixedWordBuildTelemetryIsPerTokenAndContainsNoMathFields() throws {
        let factory = LanguageActivitySessionFactory(
            configuration: .configuration(for: .minikPlus)
        )
        let activity = try XCTUnwrap(factory.makeMixedChildActivity(
            for: .wordBuild,
            language: .english
        ))
        guard case .build(let session) = activity.session,
              let contentItemID = session.currentChallenge.languageWordContent?.contentItemID else {
            return XCTFail("Expected typed Mixed Word Build content.")
        }

        var tracker = LanguageOrderedTokenAttemptTracker()
        let wrong = try XCTUnwrap(tracker.makeAttempt(
            presentationIndex: 1,
            contentItemID: contentItemID,
            tokenIndex: 0,
            result: .incorrect,
            responseDurationSeconds: 1,
            activityFamily: .mixed,
            skillID: LanguageSkillIDs.wordConstruction
        ))
        let retry = try XCTUnwrap(tracker.makeAttempt(
            presentationIndex: 1,
            contentItemID: contentItemID,
            tokenIndex: 0,
            result: .correct,
            responseDurationSeconds: 0.5,
            activityFamily: .mixed,
            skillID: LanguageSkillIDs.wordConstruction
        ))

        XCTAssertEqual(wrong.itemID.rawValue, "\(contentItemID.rawValue).ordered-token.0")
        XCTAssertEqual(wrong.attemptIndex, 1)
        XCTAssertEqual(wrong.activityFamily, .mixed)
        XCTAssertEqual(wrong.skillID, LanguageSkillIDs.wordConstruction)
        XCTAssertNil(wrong.mathLevelID)
        XCTAssertEqual(retry.itemID, wrong.itemID)
        XCTAssertEqual(retry.attemptIndex, 2)
        XCTAssertNil(retry.mathLevelID)
    }

    private func assertChoiceActivity(
        _ activity: LanguageMixedChildActivity,
        expectedMode: LanguageMixedPracticeMode,
        expectedSkill: SkillID,
        promptIsLearningText: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(activity.mode, expectedMode, file: file, line: line)
        guard case .multipleChoice(let choiceSession) = activity.session else {
            return XCTFail("Expected Mixed choice mode to use MultipleChoiceSession.", file: file, line: line)
        }
        // The level's whole word list, each word once (Android loadWords).
        let words = choiceSession.challenges.compactMap(\.languageContentItemID)
        XCTAssertEqual(words.count, choiceSession.challengeCount, file: file, line: line)
        XCTAssertEqual(Set(words).count, words.count, file: file, line: line)
        XCTAssertEqual(activity.vocabularyLevel, .a, file: file, line: line)

        for challenge in choiceSession.challenges {
            XCTAssertEqual(challenge.primarySkill, expectedSkill, file: file, line: line)
            XCTAssertEqual(challenge.validationRule, .exactIdentity, file: file, line: line)
            if promptIsLearningText {
                XCTAssertTrue(
                    challenge.prompt.representations.allSatisfy(isLearningText),
                    file: file,
                    line: line
                )
                XCTAssertTrue(challenge.choices.allSatisfy {
                    isImageAsset($0.representation)
                }, file: file, line: line)
            } else {
                XCTAssertTrue(
                    challenge.prompt.representations.allSatisfy(isImageAsset),
                    file: file,
                    line: line
                )
                XCTAssertTrue(challenge.choices.allSatisfy {
                    isLearningText($0.representation)
                }, file: file, line: line)
            }
        }
    }

    private func assertAdvance(
        progression: inout LanguageMixedProgression,
        count: Int,
        from source: LanguageMixedPracticeMode,
        to destination: LanguageMixedPracticeMode,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(progression.currentMode, source, file: file, line: line)
        XCTAssertEqual(progression.advancesInCurrentMode, 0, file: file, line: line)
        for expectedCount in 1 ..< count {
            XCTAssertEqual(progression.record(.advancedCurrentWord), .advanced, file: file, line: line)
            XCTAssertEqual(progression.currentMode, source, file: file, line: line)
            XCTAssertEqual(progression.advancesInCurrentMode, expectedCount, file: file, line: line)
        }
        XCTAssertEqual(
            progression.record(.advancedCurrentWord),
            .modeChanged(from: source, to: destination),
            file: file,
            line: line
        )
        XCTAssertEqual(progression.advancesInCurrentMode, 0, file: file, line: line)
    }

    private func isLearningText(_ representation: Representation) -> Bool {
        guard case .learningText = representation else {
            return false
        }
        return true
    }

    private func isImageAsset(_ representation: Representation) -> Bool {
        guard case .imageAsset = representation else {
            return false
        }
        return true
    }
}
