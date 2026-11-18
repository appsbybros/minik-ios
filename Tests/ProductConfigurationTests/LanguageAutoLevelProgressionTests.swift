import XCTest
@testable import MinikPlus

final class LanguageAutoLevelProgressionTests: XCTestCase {
    func test01AndroidDefaultsAreAutomaticAndLevelA() {
        XCTAssertEqual(LanguageParentLevelSettings.androidDefault.mode, .automatic)
        XCTAssertEqual(LanguageParentLevelSettings.androidDefault.wordLevel, .a)
    }

    func test02ManualLevelDirectlyDrivesProductionVocabulary() throws {
        let factory = LanguageActivitySessionFactory(
            configuration: .configuration(for: .minikPlus),
            vocabularyLevel: .d
        )
        XCTAssertEqual(
            try XCTUnwrap(factory.makeWordBuildSession(for: .english))
                .currentChallenge.curriculumStage,
            LanguageCurriculumStageIDs.wordsLevelD
        )
    }

    func test03ManualModeCannotPromote() {
        var state = passingState(activity: .write)
        var settings = settings(mode: .manual, level: .a)
        XCTAssertEqual(state.evaluate(boundary(.write, level: .a), settings: &settings), .ignored)
        XCTAssertEqual(settings.wordLevel, .a)
    }

    func test04PerContentCorrectAndWrongEvidencePersists() {
        var state = emptyState()
        let item = ContentItemID(rawValue: "apple")
        state.record(id: UUID(), evidence: evidence(item, .a, .tower, .correct))
        state.record(id: UUID(), evidence: evidence(item, .a, .tower, .incorrect))
        XCTAssertEqual(state.evidence.first?.correctCount, 1)
        XCTAssertEqual(state.evidence.first?.wrongCount, 1)
    }

    func test05EvidenceRetainsActivityAndVocabularyStage() {
        var state = emptyState()
        state.record(id: UUID(), evidence: evidence(ContentItemID(rawValue: "boat"), .c, .soccer, .correct))
        XCTAssertEqual(state.evidence.first?.activity, .soccer)
        XCTAssertEqual(state.evidence.first?.vocabularyLevel, .c)
    }

    func test06WriteBelow100AttemptsFails() {
        var state = state(activity: .write, correct: 99, wrong: 0)
        XCTAssertEqual(
            state.evaluate(boundary(.write, level: .a), mode: .automatic, persistedLevel: .a),
            .failed(attempts: 99, accuracyPercent: 100)
        )
    }

    func test07Write100AttemptsBelow90PercentFails() {
        var state = state(activity: .write, correct: 89, wrong: 11)
        XCTAssertEqual(
            state.evaluate(boundary(.write, level: .a), mode: .automatic, persistedLevel: .a),
            .failed(attempts: 100, accuracyPercent: 89)
        )
    }

    func test08Write90PercentBoundaryPasses() {
        var state = state(activity: .write, correct: 90, wrong: 10)
        XCTAssertEqual(
            state.evaluate(boundary(.write, level: .a), mode: .automatic, persistedLevel: .a),
            .passedOnce(attempts: 100, accuracyPercent: 90)
        )
    }

    func test09TowerBelow600AttemptsFails() {
        var state = state(activity: .tower, correct: 599, wrong: 0)
        XCTAssertEqual(
            state.evaluate(boundary(.tower, level: .a), mode: .automatic, persistedLevel: .a),
            .failed(attempts: 599, accuracyPercent: 100)
        )
    }

    func test10Tower80PercentBoundaryPasses() {
        var state = state(activity: .tower, correct: 480, wrong: 120)
        XCTAssertEqual(
            state.evaluate(boundary(.tower, level: .a), mode: .automatic, persistedLevel: .a),
            .passedOnce(attempts: 600, accuracyPercent: 80)
        )
    }

    func test11SoccerBelow600AttemptsFails() {
        var state = state(activity: .soccer, correct: 479, wrong: 120)
        XCTAssertEqual(
            state.evaluate(boundary(.soccer, level: .a), mode: .automatic, persistedLevel: .a),
            .failed(attempts: 599, accuracyPercent: 79)
        )
    }

    func test12Soccer80PercentBoundaryPasses() {
        var state = state(activity: .soccer, correct: 480, wrong: 120)
        XCTAssertEqual(
            state.evaluate(boundary(.soccer, level: .a), mode: .automatic, persistedLevel: .a),
            .passedOnce(attempts: 600, accuracyPercent: 80)
        )
    }

    func test13FirstPassingPoolDoesNotPromote() {
        var state = passingState(activity: .write)
        var settings = settings()
        _ = state.evaluate(boundary(.write, level: .a), settings: &settings)
        XCTAssertEqual(settings.wordLevel, .a)
        XCTAssertEqual(state.consecutivePasses[.a], 1)
    }

    func test14SecondPassingPoolPromotesExactlyOnce() {
        var state = passingState(activity: .write)
        var settings = settings()
        _ = state.evaluate(boundary(.write, level: .a), settings: &settings)
        XCTAssertEqual(
            state.evaluate(boundary(.write, level: .a), settings: &settings),
            .promoted(from: .a, to: .b, accuracyPercent: 100)
        )
        XCTAssertEqual(settings.wordLevel, .b)
    }

    func test15FailureBetweenPassesResetsStreak() {
        var state = state(activity: .write, correct: 90, wrong: 10)
        _ = state.evaluate(boundary(.write, level: .a), mode: .automatic, persistedLevel: .a)
        state = self.state(activity: .write, correct: 89, wrong: 11, passes: [.a: 1])
        _ = state.evaluate(boundary(.write, level: .a), mode: .automatic, persistedLevel: .a)
        XCTAssertEqual(state.consecutivePasses[.a], 0)
    }

    func test16StalePoolCannotPromoteLaterLevel() {
        var state = state(activity: .write, level: .b, correct: 100, wrong: 0, passes: [.b: 1])
        XCTAssertEqual(
            state.evaluate(boundary(.write, level: .a), mode: .automatic, persistedLevel: .b),
            .ignored
        )
        XCTAssertEqual(state.currentLevel, .b)
    }

    func test17OrderingAdvancesAThroughE() {
        XCTAssertEqual(LanguageVocabularyLevel.a.next, .b)
        XCTAssertEqual(LanguageVocabularyLevel.b.next, .c)
        XCTAssertEqual(LanguageVocabularyLevel.c.next, .d)
        XCTAssertEqual(LanguageVocabularyLevel.d.next, .e)
    }

    func test18LevelEClamps() {
        var state = state(activity: .write, level: .e, correct: 100, wrong: 0, passes: [.e: 1])
        XCTAssertEqual(
            state.evaluate(boundary(.write, level: .e), mode: .automatic, persistedLevel: .e),
            .ignored
        )
        XCTAssertEqual(state.currentLevel, .e)
        XCTAssertNil(LanguageVocabularyLevel.e.next)
    }

    func test19PromotionWritesSharedParentLevel() {
        var state = state(activity: .write, correct: 100, wrong: 0, passes: [.a: 1])
        var settings = settings()
        _ = state.evaluate(boundary(.write, level: .a), settings: &settings)
        XCTAssertEqual(settings.wordLevel, state.currentLevel)
        XCTAssertEqual(settings.wordLevel, .b)
    }

    func test20RestartRetainsEvidencePassRampAndLevel() throws {
        let suite = "LanguageAutoLevelProgressionTests.restart.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = LanguageAutoProgressRepository(userDefaults: defaults, storageKeyPrefix: "auto")
        var state = state(activity: .write, correct: 100, wrong: 0, passes: [.a: 1])
        var settings = settings()
        _ = state.evaluate(boundary(.write, level: .a), settings: &settings)
        repository.save(state)
        let restored = repository.load(scope: state.scope, currentLevel: settings.wordLevel)
        XCTAssertEqual(restored, state)
    }

    func test21PromotionInitializesRampTo90() {
        var state = state(activity: .write, correct: 100, wrong: 0, passes: [.a: 1])
        _ = state.evaluate(boundary(.write, level: .a), mode: .automatic, persistedLevel: .a)
        XCTAssertEqual(state.ramp, 90)
    }

    func test22RampSelectionUsesRoundedPreviousAndCurrentListCounts() {
        var generator = FixedGenerator()
        let mixed = LanguageVocabularyPoolMixer.mix(
            previous: (0..<11).map { "p\($0)" },
            current: (0..<9).map { "c\($0)" },
            ramp: 50,
            using: &generator
        )
        XCTAssertEqual(mixed.filter { $0.hasPrefix("p") }.count, 6)
        XCTAssertEqual(mixed.filter { $0.hasPrefix("c") }.count, 5)
    }

    func testFactoryUsesPreviousLevelAtFullRampAndCurrentLevelAtZeroRamp() throws {
        let configuration = ProductConfiguration.configuration(for: .minikPlus)
        let previous = try XCTUnwrap(LanguageActivitySessionFactory(
            configuration: configuration,
            vocabularyLevel: .b,
            vocabularyRamp: 100
        ).makeWordBuildSession(for: .english))
        let current = try XCTUnwrap(LanguageActivitySessionFactory(
            configuration: configuration,
            vocabularyLevel: .b,
            vocabularyRamp: 0
        ).makeWordBuildSession(for: .english))
        XCTAssertTrue(previous.challenges.allSatisfy {
            $0.curriculumStage == LanguageCurriculumStageIDs.wordsLevelA
        })
        XCTAssertTrue(current.challenges.allSatisfy {
            $0.curriculumStage == LanguageCurriculumStageIDs.wordsLevelB
        })
    }

    func test23ApplicationStopDecrementsRampExactly10() {
        var state = LanguageAutoProgressionState(scope: scope(), currentLevel: .b, ramp: 90)
        state.applicationDidStop()
        XCTAssertEqual(state.ramp, 80)
    }

    func test24RampNeverPassesZeroFloor() {
        var state = LanguageAutoProgressionState(scope: scope(), currentLevel: .b, ramp: 5)
        state.applicationDidStop()
        XCTAssertEqual(state.ramp, 0)
    }

    func test25ManualAutoSwitchPreservesExistingPassState() {
        var state = passingState(activity: .write)
        _ = state.evaluate(boundary(.write, level: .a), mode: .automatic, persistedLevel: .a)
        _ = state.evaluate(boundary(.write, level: .a), mode: .manual, persistedLevel: .a)
        XCTAssertEqual(state.consecutivePasses[.a], 1)
        XCTAssertEqual(
            state.evaluate(boundary(.write, level: .a), mode: .automatic, persistedLevel: .a),
            .promoted(from: .a, to: .b, accuracyPercent: 100)
        )
    }

    func test26SoccerPoolBoundaryFiresOnce() {
        assertBoundaryFiresOnce(activity: .soccer)
    }

    func test27TowerPoolBoundaryFiresOnce() {
        assertBoundaryFiresOnce(activity: .tower)
    }

    func test28WritePoolBoundaryFiresOnce() {
        assertBoundaryFiresOnce(activity: .write)
    }

    func test29DuplicateEvidenceIDCannotDoubleCount() {
        var state = emptyState()
        let id = UUID()
        let value = evidence(ContentItemID(rawValue: "pear"), .a, .tower, .correct)
        state.record(id: id, evidence: value)
        state.record(id: id, evidence: value)
        XCTAssertEqual(state.evidence.first?.correctCount, 1)
    }

    func test30PlusAndEnglishOnlyRepositoriesAreIsolated() throws {
        let suite = "LanguageAutoLevelProgressionTests.products.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = LanguageAutoProgressRepository(userDefaults: defaults, storageKeyPrefix: "auto")
        repository.save(LanguageAutoProgressionState(scope: scope(.minikPlus), currentLevel: .d, ramp: 40))
        XCTAssertEqual(repository.load(scope: scope(.minikPlus), currentLevel: .d).ramp, 40)
        XCTAssertEqual(repository.load(scope: scope(.minikPlusEnglish), currentLevel: .a).ramp, 0)
    }

    func test31LearnedLanguageDoesNotChangeLevelScopeOrPool() {
        let english = LanguageActivitySessionFactory(
            configuration: .configuration(for: .minikPlus), vocabularyLevel: .c
        )
        let hebrew = LanguageActivitySessionFactory(
            configuration: .configuration(for: .minikPlus), vocabularyLevel: .c
        )
        XCTAssertEqual(english.vocabularyLevel, hebrew.vocabularyLevel)
        XCTAssertNotNil(english.makeWordBuildSession(for: .english))
        XCTAssertNotNil(hebrew.makeWordBuildSession(for: .hebrew))
    }

    func test32LanguageProgressionDoesNotMutateMathState() {
        var math = MathLevelController()
        let original = math.state
        var language = passingState(activity: .write)
        _ = language.evaluate(boundary(.write, level: .a), mode: .automatic, persistedLevel: .a)
        XCTAssertEqual(math.state, original)
        math.returnToAutomatic()
        XCTAssertEqual(math.state.activeLevelID, original.activeLevelID)
    }

    func testSharedAndroidWordCountersAggregateAcrossEligibleActivities() {
        let item = ContentItemID(rawValue: "shared")
        var state = LanguageAutoProgressionState(
            scope: scope(),
            evidence: [
                LanguageAutoContentEvidence(contentItemID: item, vocabularyLevel: .a, activity: .tower, correctCount: 300),
                LanguageAutoContentEvidence(contentItemID: item, vocabularyLevel: .a, activity: .soccer, correctCount: 300)
            ]
        )
        XCTAssertEqual(
            state.evaluate(boundary(.tower, level: .a, item: item), mode: .automatic, persistedLevel: .a),
            .passedOnce(attempts: 600, accuracyPercent: 100)
        )
    }

    func testSkippedEvidenceDoesNotBecomeAndroidCorrectOrWrong() {
        var state = emptyState()
        state.record(id: UUID(), evidence: evidence(ContentItemID(rawValue: "skip"), .a, .write, .skipped))
        XCTAssertTrue(state.evidence.isEmpty)
    }

    func testDuplicatePoolBoundaryCannotPromote() {
        var state = passingState(activity: .write)
        let pool = boundary(.write, level: .a)
        _ = state.evaluate(pool, mode: .automatic, persistedLevel: .a)
        XCTAssertEqual(state.evaluate(pool, mode: .automatic, persistedLevel: .a), .ignored)
        XCTAssertEqual(state.currentLevel, .a)
    }

    func testAutoEvidenceRoutingIncludesOnlyWriteTowerAndSoccer() {
        XCTAssertEqual(
            LanguageAutoEvidenceRouting.completionActivity(for: .wordBuild),
            .write
        )
        XCTAssertEqual(
            LanguageAutoEvidenceRouting.attemptActivity(for: .tower),
            .tower
        )
        XCTAssertEqual(
            LanguageAutoEvidenceRouting.attemptActivity(for: .soccer),
            .soccer
        )
        // Android WriteScreen: choice taps (also inside mixed practice) and the words
        // built in mixed practice count for the Write check.
        XCTAssertEqual(LanguageAutoEvidenceRouting.attemptActivity(for: .multipleChoice), .write)
        XCTAssertEqual(LanguageAutoEvidenceRouting.attemptActivity(for: .mixed), .write)
        XCTAssertEqual(LanguageAutoEvidenceRouting.completionActivity(for: .mixed), .write)
        XCTAssertNil(LanguageAutoEvidenceRouting.completionActivity(for: .imageToWord))
        XCTAssertNil(LanguageAutoEvidenceRouting.completionActivity(for: .build))

        for family in ActivityFamily.allCasesForLanguageAutoExclusionTest {
            XCTAssertNil(LanguageAutoEvidenceRouting.attemptActivity(for: family))
        }
    }

    private func scope(_ product: ProductVariant = .minikPlus) -> LanguageAutoScope {
        LanguageAutoScope(product: product)
    }

    private func settings(
        mode: LanguageLevelMode = .automatic,
        level: LanguageVocabularyLevel = .a
    ) -> LanguageParentLevelSettings {
        var value = LanguageParentLevelSettings.androidDefault
        value.mode = mode
        value.wordLevel = level
        return value
    }

    private func emptyState() -> LanguageAutoProgressionState {
        LanguageAutoProgressionState(scope: scope())
    }

    private func state(
        activity: LanguageAutoActivity,
        level: LanguageVocabularyLevel = .a,
        correct: Int,
        wrong: Int,
        passes: [LanguageVocabularyLevel: Int] = [:]
    ) -> LanguageAutoProgressionState {
        LanguageAutoProgressionState(
            scope: scope(),
            currentLevel: level,
            evidence: [LanguageAutoContentEvidence(
                contentItemID: ContentItemID(rawValue: "item"),
                vocabularyLevel: level,
                activity: activity,
                correctCount: correct,
                wrongCount: wrong
            )],
            consecutivePasses: passes
        )
    }

    private func passingState(activity: LanguageAutoActivity) -> LanguageAutoProgressionState {
        let attempts = activity == .write ? 100 : 600
        return state(activity: activity, correct: attempts, wrong: 0)
    }

    private func evidence(
        _ item: ContentItemID,
        _ level: LanguageVocabularyLevel,
        _ activity: LanguageAutoActivity,
        _ result: GradedAttemptResult
    ) -> LanguageAutoAttemptEvidence {
        LanguageAutoAttemptEvidence(
            contentItemID: item,
            vocabularyLevel: level,
            activity: activity,
            result: result
        )
    }

    private func boundary(
        _ activity: LanguageAutoActivity,
        level: LanguageVocabularyLevel,
        item: ContentItemID = ContentItemID(rawValue: "item")
    ) -> LanguageAutoPoolBoundary {
        LanguageAutoPoolBoundary(
            activity: activity,
            evaluatedLevel: level,
            items: [LanguageAutoPoolItem(contentItemID: item, vocabularyLevel: level)]
        )!
    }

    private func assertBoundaryFiresOnce(activity: LanguageAutoActivity) {
        var tracker = LanguageAutoPoolTracker(
            activity: activity,
            evaluatedLevel: .a,
            items: [LanguageAutoPoolItem(
                contentItemID: ContentItemID(rawValue: "item"),
                vocabularyLevel: .a
            )]
        )!
        XCTAssertNil(tracker.takeBoundary(isExhausted: false))
        XCTAssertNotNil(tracker.takeBoundary(isExhausted: true))
        XCTAssertNil(tracker.takeBoundary(isExhausted: true))
    }
}

private extension ActivityFamily {
    static let allCasesForLanguageAutoExclusionTest: [ActivityFamily] = [
        .learn, .buildNumber, .buildQuantity, .buildMath,
        .buildWord, .cards, .pairs, .memory, .ticTacToe, .pingPong
    ]
}

private struct FixedGenerator: RandomNumberGenerator {
    private var value: UInt64 = 0

    mutating func next() -> UInt64 {
        value &+= 0x9E3779B97F4A7C15
        return value
    }
}
