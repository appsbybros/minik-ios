import XCTest
@testable import MinikPlus

final class LanguageWordCatalogTests: XCTestCase {
    func testVocabularyLevelsMapToStableCurriculumStages() {
        XCTAssertEqual(LanguageVocabularyLevel.allCases.map(\.rawValue), ["A", "B", "C", "D", "E"])
        XCTAssertEqual(LanguageVocabularyLevel.allCases.map(\.curriculumStageID.rawValue), [
            "language.words.levelA",
            "language.words.levelB",
            "language.words.levelC",
            "language.words.levelD",
            "language.words.levelE"
        ])
    }

    func testApprovedXMLContains1269UniqueNonEmptyStableKeys() {
        let stableKeys = LanguageWordCatalog.allItems.map(\.stableKey)

        XCTAssertEqual(LanguageWordCatalog.allItems.count, 1269)
        XCTAssertEqual(stableKeys.count, 1269)
        XCTAssertEqual(Set(stableKeys).count, 1269)
        XCTAssertTrue(stableKeys.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }

    func testAllLoadedContentItemIDsAreDerivedOnlyFromStableKey() {
        XCTAssertTrue(LanguageWordCatalog.allItems.allSatisfy {
            $0.id == ContentItemID(rawValue: "language.words.\($0.stableKey)")
        })
    }

    func testExactLexicalCountsMatchApprovedNormalizedVocabulary() {
        XCTAssertEqual(lexicalCount(for: .a), 181)
        XCTAssertEqual(lexicalCount(for: .b), 192)
        XCTAssertEqual(lexicalCount(for: .c), 240)
        XCTAssertEqual(lexicalCount(for: .d), 162)
        XCTAssertEqual(lexicalCount(for: .e), 179)
    }

    func testExactSentenceCountsMatchApprovedNormalizedVocabulary() {
        XCTAssertEqual(sentenceCount(for: .a), 0)
        XCTAssertEqual(sentenceCount(for: .b), 6)
        XCTAssertEqual(sentenceCount(for: .c), 9)
        XCTAssertEqual(sentenceCount(for: .d), 100)
        XCTAssertEqual(sentenceCount(for: .e), 200)
    }

    func testNormalizedParserIgnoresComments() throws {
        let xml = """
        <?xml version='1.0' encoding='utf-8'?>
        <resources>
            <!-- ignored -->
            <string-array name="fruits_a">
                <word key="fruits_apple" en="Apple" he="תפוח" />
                <!-- ignored -->
                <word key="fruits_banana" en="Banana" he="בננה" />
            </string-array>
        </resources>
        """

        let catalog = try LanguageVocabularyCatalogLoader.load(
            xmlData: Data(xml.utf8),
            manifestData: emptyManifestData(),
            availableAssetReferences: []
        )

        XCTAssertEqual(catalog.items(for: .a).map(\.stableKey), ["fruits_apple", "fruits_banana"])
    }

    func testArrayNameParsingUsesFullPrefixAndFinalLevelSuffix() throws {
        let parsed = try LanguageVocabularyCatalogLoader.parseArrayName("school_supplies_c")

        XCTAssertEqual(parsed.categoryID.rawValue, "school_supplies")
        XCTAssertEqual(parsed.level, .c)
    }

    func testMalformedArrayNamesFailCleanly() {
        XCTAssertThrowsError(try LanguageVocabularyCatalogLoader.parseArrayName("fruits")) { error in
            XCTAssertEqual(
                error as? LanguageVocabularyLoadError,
                .malformedArrayName("fruits")
            )
        }
        XCTAssertThrowsError(try LanguageVocabularyCatalogLoader.parseArrayName("_a"))
        XCTAssertThrowsError(try LanguageVocabularyCatalogLoader.parseArrayName("fruits_z"))
    }

    func testMissingOrBlankXMLKeysFailCleanly() {
        let missingKeyXML = fixtureXML(
            arrayName: "fruits_a",
            rows: [
                #"<word en="Apple" he="תפוח" />"#
            ]
        )
        XCTAssertThrowsError(
            try LanguageVocabularyCatalogLoader.load(
                xmlData: Data(missingKeyXML.utf8),
                manifestData: emptyManifestData(),
                availableAssetReferences: []
            )
        ) { error in
            XCTAssertEqual(
                error as? LanguageVocabularyLoadError,
                .missingXMLKey(arrayName: "fruits_a")
            )
        }

        let blankKeyXML = fixtureXML(
            arrayName: "fruits_a",
            rows: [
                #"<word key="   " en="Apple" he="תפוח" />"#
            ]
        )
        XCTAssertThrowsError(
            try LanguageVocabularyCatalogLoader.load(
                xmlData: Data(blankKeyXML.utf8),
                manifestData: emptyManifestData(),
                availableAssetReferences: []
            )
        ) { error in
            XCTAssertEqual(
                error as? LanguageVocabularyLoadError,
                .blankXMLKey(arrayName: "fruits_a")
            )
        }
    }

    func testDuplicateXMLKeyFailsCleanly() {
        let xml = fixtureXML(
            arrayName: "fruits_a",
            rows: [
                #"<word key="shared_key" en="Apple" he="תפוח" />"#,
                #"<word key="shared_key" en="Banana" he="בננה" />"#
            ]
        )

        XCTAssertThrowsError(
            try LanguageVocabularyCatalogLoader.load(
                xmlData: Data(xml.utf8),
                manifestData: emptyManifestData(),
                availableAssetReferences: []
            )
        ) { error in
            XCTAssertEqual(
                error as? LanguageVocabularyLoadError,
                .duplicateXMLKey("shared_key")
            )
        }
    }

    func testMissingEnglishOrHebrewFailCleanly() {
        let missingEnglishXML = fixtureXML(
            arrayName: "fruits_a",
            rows: [
                #"<word key="fruits_apple" he="תפוח" />"#
            ]
        )
        XCTAssertThrowsError(
            try LanguageVocabularyCatalogLoader.load(
                xmlData: Data(missingEnglishXML.utf8),
                manifestData: emptyManifestData(),
                availableAssetReferences: []
            )
        ) { error in
            XCTAssertEqual(
                error as? LanguageVocabularyLoadError,
                .missingXMLEnglish(key: "fruits_apple")
            )
        }

        let missingHebrewXML = fixtureXML(
            arrayName: "fruits_a",
            rows: [
                #"<word key="fruits_apple" en="Apple" />"#
            ]
        )
        XCTAssertThrowsError(
            try LanguageVocabularyCatalogLoader.load(
                xmlData: Data(missingHebrewXML.utf8),
                manifestData: emptyManifestData(),
                availableAssetReferences: []
            )
        ) { error in
            XCTAssertEqual(
                error as? LanguageVocabularyLoadError,
                .missingXMLHebrew(key: "fruits_apple")
            )
        }
    }

    func testApprovedManifestContains543UniqueStableKeysAllPresentInXML() {
        let stableKeys = LanguageWordCatalog.imageManifestEntries.map(\.stableKey)
        let xmlStableKeys = Set(LanguageWordCatalog.allItems.map(\.stableKey))

        XCTAssertEqual(stableKeys.count, 543)
        XCTAssertEqual(Set(stableKeys).count, 543)
        XCTAssertTrue(stableKeys.allSatisfy { xmlStableKeys.contains($0) })
    }

    func testMissingManifestStableKeyColumnFailsCleanly() {
        let manifest = """
        assetKey\tsource\tenglish\thebrew\tproposedBaseLevel\tproposedCategory\tiosAssetStatus\tandroidAssetStatus\timageAction
        apple\texisting:fruits_a\tApple\tתפוח\tA\tfruits\texisting_ios\texisting_android\treuse_ios
        """

        XCTAssertThrowsError(
            try LanguageVocabularyCatalogLoader.load(
                xmlData: Data(singleItemXML(stableKey: "fruits_apple").utf8),
                manifestData: Data(manifest.utf8),
                availableAssetReferences: []
            )
        ) { error in
            XCTAssertEqual(
                error as? LanguageVocabularyLoadError,
                .missingManifestStableKeyColumn
            )
        }
    }

    func testBlankDuplicateAndDanglingManifestStableKeysFailCleanly() {
        let blankManifest = """
        stableKey\tassetKey\tsource\tenglish\thebrew\tproposedBaseLevel\tproposedCategory\tiosAssetStatus\tandroidAssetStatus\timageAction
        \tapple\texisting:fruits_a\tApple\tתפוח\tA\tfruits\texisting_ios\texisting_android\treuse_ios
        """
        XCTAssertThrowsError(
            try LanguageVocabularyCatalogLoader.load(
                xmlData: Data(singleItemXML(stableKey: "fruits_apple").utf8),
                manifestData: Data(blankManifest.utf8),
                availableAssetReferences: []
            )
        ) { error in
            guard case .blankManifestStableKey(_) = error as? LanguageVocabularyLoadError else {
                return XCTFail("Expected a blank stable-key error.")
            }
        }

        let duplicateManifest = """
        stableKey\tassetKey\tsource\tenglish\thebrew\tproposedBaseLevel\tproposedCategory\tiosAssetStatus\tandroidAssetStatus\timageAction
        fruits_apple\tapple\texisting:fruits_a\tApple\tתפוח\tA\tfruits\texisting_ios\texisting_android\treuse_ios
        fruits_apple\tbanana\texisting:fruits_a\tBanana\tבננה\tA\tfruits\texisting_ios\texisting_android\treuse_ios
        """
        XCTAssertThrowsError(
            try LanguageVocabularyCatalogLoader.load(
                xmlData: Data(
                    fixtureXML(
                        arrayName: "fruits_a",
                        rows: [
                            #"<word key="fruits_apple" en="Apple" he="תפוח" />"#,
                            #"<word key="fruits_banana" en="Banana" he="בננה" />"#
                        ]
                    ).utf8
                ),
                manifestData: Data(duplicateManifest.utf8),
                availableAssetReferences: []
            )
        ) { error in
            XCTAssertEqual(
                error as? LanguageVocabularyLoadError,
                .duplicateManifestStableKey("fruits_apple")
            )
        }

        let danglingManifest = """
        stableKey\tassetKey\tsource\tenglish\thebrew\tproposedBaseLevel\tproposedCategory\tiosAssetStatus\tandroidAssetStatus\timageAction
        missing_key\tapple\texisting:fruits_a\tApple\tתפוח\tA\tfruits\texisting_ios\texisting_android\treuse_ios
        """
        XCTAssertThrowsError(
            try LanguageVocabularyCatalogLoader.load(
                xmlData: Data(singleItemXML(stableKey: "fruits_apple").utf8),
                manifestData: Data(danglingManifest.utf8),
                availableAssetReferences: []
            )
        ) { error in
            XCTAssertEqual(
                error as? LanguageVocabularyLoadError,
                .unknownManifestStableKey("missing_key")
            )
        }
    }

    func testDuplicateManifestAssetKeyFailsCleanly() {
        let manifest = """
        stableKey\tassetKey\tsource\tenglish\thebrew\tproposedBaseLevel\tproposedCategory\tiosAssetStatus\tandroidAssetStatus\timageAction
        fruits_apple\tshared_asset\texisting:fruits_a\tApple\tתפוח\tA\tfruits\texisting_ios\texisting_android\treuse_ios
        fruits_banana\tshared_asset\texisting:fruits_a\tBanana\tבננה\tA\tfruits\texisting_ios\texisting_android\treuse_ios
        """

        XCTAssertThrowsError(
            try LanguageVocabularyCatalogLoader.load(
                xmlData: Data(
                    fixtureXML(
                        arrayName: "fruits_a",
                        rows: [
                            #"<word key="fruits_apple" en="Apple" he="תפוח" />"#,
                            #"<word key="fruits_banana" en="Banana" he="בננה" />"#
                        ]
                    ).utf8
                ),
                manifestData: Data(manifest.utf8),
                availableAssetReferences: []
            )
        ) { error in
            XCTAssertEqual(
                error as? LanguageVocabularyLoadError,
                .duplicateManifestAssetKey("shared_asset")
            )
        }
    }

    func testManifestJoinUsesStableKeyWithMatchingMetadata() throws {
        let xml = fixtureXML(
            arrayName: "fruits_a",
            rows: [
                #"<word key="concept_alpha" en="Apple" he="תפוח" />"#
            ]
        )
        let manifest = manifestData(rows: [
            "concept_alpha\tapple\treviewed\tApple\tתפוח\tA\tfruits\texisting_ios\texisting_android\treuse_ios"
        ])

        let catalog = try LanguageVocabularyCatalogLoader.load(
            xmlData: Data(xml.utf8),
            manifestData: manifest,
            availableAssetReferences: [AssetReference(rawValue: "apple")]
        )
        let item = try XCTUnwrap(catalog.item(stableKey: "concept_alpha"))

        XCTAssertEqual(item.id.rawValue, "language.words.concept_alpha")
        XCTAssertEqual(item.englishText, "Apple")
        XCTAssertEqual(item.hebrewText, "תפוח")
        XCTAssertEqual(item.imageManifestEntry?.stableKey, "concept_alpha")
        XCTAssertEqual(item.imageManifestEntry?.assetReference, AssetReference(rawValue: "apple"))
    }

    func testManifestMetadataMismatchFailsForEnglish() {
        assertManifestMetadataMismatch(
            manifestRow: "concept_alpha\tapple\treviewed\tChanged English\tתפוח\tA\tfruits\texisting_ios\texisting_android\treuse_ios",
            expectedError: .manifestEnglishMismatch("concept_alpha")
        )
    }

    func testManifestMetadataMismatchFailsForHebrew() {
        assertManifestMetadataMismatch(
            manifestRow: "concept_alpha\tapple\treviewed\tApple\tשונה\tA\tfruits\texisting_ios\texisting_android\treuse_ios",
            expectedError: .manifestHebrewMismatch("concept_alpha")
        )
    }

    func testManifestMetadataMismatchFailsForLevel() {
        assertManifestMetadataMismatch(
            manifestRow: "concept_alpha\tapple\treviewed\tApple\tתפוח\tE\tfruits\texisting_ios\texisting_android\treuse_ios",
            expectedError: .manifestLevelMismatch("concept_alpha")
        )
    }

    func testManifestMetadataMismatchFailsForCategory() {
        assertManifestMetadataMismatch(
            manifestRow: "concept_alpha\tapple\treviewed\tApple\tתפוח\tA\ttechnology\texisting_ios\texisting_android\treuse_ios",
            expectedError: .manifestCategoryMismatch("concept_alpha")
        )
    }

    func testManifestAssetKeyControlsRuntimeAvailabilityForMultiwordStableKey() throws {
        let xml = fixtureXML(
            arrayName: "transport_b",
            rows: [
                #"<word key="transport_traffic_light" en="Traffic light" he="רמזור" />"#
            ]
        )
        let manifest = """
        stableKey\tassetKey\tsource\tenglish\thebrew\tproposedBaseLevel\tproposedCategory\tiosAssetStatus\tandroidAssetStatus\timageAction
        transport_traffic_light\ttraffic_light\texisting:transport_b\tTraffic light\tרמזור\tB\ttransport\texisting_ios\texisting_android\treuse_ios
        """

        let readyCatalog = try LanguageVocabularyCatalogLoader.load(
            xmlData: Data(xml.utf8),
            manifestData: Data(manifest.utf8),
            availableAssetReferences: [AssetReference(rawValue: "traffic_light")]
        )
        let readyItem = try XCTUnwrap(readyCatalog.item(stableKey: "transport_traffic_light"))

        XCTAssertEqual(readyItem.stableKey, "transport_traffic_light")
        XCTAssertEqual(readyItem.imageAssetReference, AssetReference(rawValue: "traffic_light"))
        XCTAssertTrue(readyItem.isImageReady)

        let suffixOnlyCatalog = try LanguageVocabularyCatalogLoader.load(
            xmlData: Data(xml.utf8),
            manifestData: Data(manifest.utf8),
            availableAssetReferences: [AssetReference(rawValue: "light")]
        )
        let suffixOnlyItem = try XCTUnwrap(suffixOnlyCatalog.item(stableKey: "transport_traffic_light"))

        XCTAssertEqual(suffixOnlyItem.imageAssetReference, AssetReference(rawValue: "traffic_light"))
        XCTAssertFalse(suffixOnlyItem.isImageReady)
    }

    func testManifestAssetReadinessSupportsAdditionalMultiwordAssetMappings() throws {
        let xml = fixtureXML(
            arrayName: "sports_c",
            rows: [
                #"<word key="sports_basketball_hoop" en="Basketball hoop" he="סל כדורסל" />"#,
                #"<word key="sports_scoreboard" en="Scoreboard" he="לוח תוצאות" />"#
            ]
        )
        let manifest = """
        stableKey\tassetKey\tsource\tenglish\thebrew\tproposedBaseLevel\tproposedCategory\tiosAssetStatus\tandroidAssetStatus\timageAction
        sports_basketball_hoop\tbasketball_hoop\treviewed\tBasketball hoop\tסל כדורסל\tC\tsports\texisting_ios\texisting_android\treuse_ios
        sports_scoreboard\tscoreboard\treviewed\tScoreboard\tלוח תוצאות\tC\tsports\texisting_ios\texisting_android\treuse_ios
        """

        let catalog = try LanguageVocabularyCatalogLoader.load(
            xmlData: Data(xml.utf8),
            manifestData: Data(manifest.utf8),
            availableAssetReferences: [
                AssetReference(rawValue: "basketball_hoop"),
                AssetReference(rawValue: "scoreboard")
            ]
        )

        let hoopItem = try XCTUnwrap(catalog.item(stableKey: "sports_basketball_hoop"))
        let scoreboardItem = try XCTUnwrap(catalog.item(stableKey: "sports_scoreboard"))

        XCTAssertEqual(hoopItem.imageAssetReference, AssetReference(rawValue: "basketball_hoop"))
        XCTAssertTrue(hoopItem.isImageReady)
        XCTAssertEqual(scoreboardItem.imageAssetReference, AssetReference(rawValue: "scoreboard"))
        XCTAssertTrue(scoreboardItem.isImageReady)
    }

    func testApprovedNormalizedXMLAndManifestLoadWithoutError() throws {
        let catalog = try LanguageVocabularyCatalogLoader.load(
            xmlData: try approvedData(named: "words-normalized", fileExtension: "xml"),
            manifestData: try approvedData(named: "vocabulary-image-manifest", fileExtension: "tsv"),
            availableAssetReferences: knownReadyAssets
        )

        XCTAssertEqual(catalog.allItems.count, 1269)
        XCTAssertEqual(catalog.imageManifestEntries.count, 543)
    }

    func testReorderingTwoKeyedRowsDoesNotChangeTheirIDs() throws {
        let firstXML = fixtureXML(
            arrayName: "fruits_a",
            rows: [
                #"<word key="alpha" en="Apple" he="תפוח" />"#,
                #"<word key="beta" en="Banana" he="בננה" />"#
            ]
        )
        let secondXML = fixtureXML(
            arrayName: "fruits_a",
            rows: [
                #"<word key="beta" en="Banana" he="בננה" />"#,
                #"<word key="alpha" en="Apple" he="תפוח" />"#
            ]
        )

        let firstCatalog = try LanguageVocabularyCatalogLoader.load(
            xmlData: Data(firstXML.utf8),
            manifestData: emptyManifestData(),
            availableAssetReferences: []
        )
        let secondCatalog = try LanguageVocabularyCatalogLoader.load(
            xmlData: Data(secondXML.utf8),
            manifestData: emptyManifestData(),
            availableAssetReferences: []
        )

        XCTAssertEqual(firstCatalog.item(stableKey: "alpha")?.id, secondCatalog.item(stableKey: "alpha")?.id)
        XCTAssertEqual(firstCatalog.item(stableKey: "beta")?.id, secondCatalog.item(stableKey: "beta")?.id)
    }

    func testChangingTextWhilePreservingKeyDoesNotChangeID() throws {
        let firstManifest = manifestData(rows: [
            "concept_alpha\tapple\treviewed\tApple\tתפוח\tA\tfruits\texisting_ios\texisting_android\treuse_ios"
        ])
        let secondManifest = manifestData(rows: [
            "concept_alpha\tapple\treviewed\tGreen Apple\tתפוח ירוק\tA\tfruits\texisting_ios\texisting_android\treuse_ios"
        ])
        let firstCatalog = try LanguageVocabularyCatalogLoader.load(
            xmlData: Data(singleItemXML(stableKey: "concept_alpha", english: "Apple", hebrew: "תפוח").utf8),
            manifestData: firstManifest,
            availableAssetReferences: [AssetReference(rawValue: "apple")]
        )
        let secondCatalog = try LanguageVocabularyCatalogLoader.load(
            xmlData: Data(singleItemXML(stableKey: "concept_alpha", english: "Green Apple", hebrew: "תפוח ירוק").utf8),
            manifestData: secondManifest,
            availableAssetReferences: [AssetReference(rawValue: "apple")]
        )

        XCTAssertEqual(firstCatalog.item(stableKey: "concept_alpha")?.id, secondCatalog.item(stableKey: "concept_alpha")?.id)
    }

    func testMovingKeyedItemBetweenCategoryAndLevelDoesNotChangeID() throws {
        let firstXML = fixtureXML(
            arrayName: "fruits_a",
            rows: [
                #"<word key="concept_alpha" en="Apple" he="תפוח" />"#
            ]
        )
        let secondXML = fixtureXML(
            arrayName: "technology_e",
            rows: [
                #"<word key="concept_alpha" en="Apple" he="תפוח" />"#
            ]
        )

        let firstCatalog = try LanguageVocabularyCatalogLoader.load(
            xmlData: Data(firstXML.utf8),
            manifestData: emptyManifestData(),
            availableAssetReferences: []
        )
        let secondCatalog = try LanguageVocabularyCatalogLoader.load(
            xmlData: Data(secondXML.utf8),
            manifestData: emptyManifestData(),
            availableAssetReferences: []
        )

        XCTAssertEqual(firstCatalog.item(stableKey: "concept_alpha")?.id, secondCatalog.item(stableKey: "concept_alpha")?.id)
        XCTAssertEqual(secondCatalog.item(stableKey: "concept_alpha")?.categoryID, LanguageWordCategoryID(rawValue: "technology"))
        XCTAssertEqual(secondCatalog.item(stableKey: "concept_alpha")?.baseLevel, .e)
    }

    func testSentenceItemsNeverExposeImages() {
        let sentenceItems = LanguageWordCatalog.allItems.filter { $0.contentKind == .sentence }

        XCTAssertEqual(sentenceItems.count, 315)
        XCTAssertTrue(sentenceItems.allSatisfy { $0.imageAssetReference == nil })
        XCTAssertTrue(sentenceItems.allSatisfy { !$0.isImageReady })
    }

    func testNonImageAbstractItemsHaveNoImageCapability() {
        let abstractItems = LanguageWordCatalog
            .items(for: .b)
            .filter { $0.categoryID.rawValue == "abstract_concepts" }

        XCTAssertFalse(abstractItems.isEmpty)
        XCTAssertTrue(abstractItems.allSatisfy { $0.imageAssetReference == nil })
        XCTAssertTrue(abstractItems.allSatisfy { !$0.isImageReady })
    }

    func testCurrentIOSReadyImageSubsetMatchesRuntimeManifest() {
        let runtimeReadyAssets = Set(LanguageWordCatalog.allItems.compactMap { item in
            item.isImageReady ? item.imageAssetReference : nil
        })
        let manifestReadyAssets = Set(
            LanguageWordCatalog.imageManifestEntries
                .filter(\.isReadyInCurrentIOS)
                .map(\.assetReference)
        )

        XCTAssertEqual(runtimeReadyAssets, manifestReadyAssets)
        XCTAssertEqual(LanguageWordCatalog.currentIOSReadyImageAssets, runtimeReadyAssets)
        XCTAssertEqual(runtimeReadyAssets.count, 409)
        XCTAssertEqual(
            LanguageWordCatalog.imageManifestEntries.filter { $0.imageAction == .migrateAndroid }.count,
            0
        )
        XCTAssertEqual(
            LanguageWordCatalog.imageManifestEntries.filter { $0.imageAction == .trustedAcquire }.count,
            33
        )
        XCTAssertEqual(
            LanguageWordCatalog.imageManifestEntries.filter { $0.imageAction == .createNew }.count,
            101
        )

        let migratedExamples = [
            (stableKey: "transport_traffic_light", assetKey: "traffic_light"),
            (stableKey: "verbs_catch", assetKey: "catch_img"),
            (stableKey: "verbs_throw", assetKey: "throw_img")
        ]
        for example in migratedExamples {
            let item = LanguageWordCatalog.item(stableKey: example.stableKey)

            XCTAssertEqual(item?.id.rawValue, "language.words.\(example.stableKey)")
            XCTAssertEqual(item?.imageAssetReference?.rawValue, example.assetKey)
            XCTAssertEqual(item?.imageManifestEntry?.iosAssetStatus, .existingIOS)
            XCTAssertEqual(item?.imageManifestEntry?.imageAction, .reuseIOS)
            XCTAssertTrue(item?.isImageReady == true)
        }
    }

    func testInvalidXMLStableKeyFormatsFailCleanly() {
        for invalidStableKey in [
            "bad key", "bad-key", "bad.key", "Bad_key",
            "café", "äpple", "αβγ", "ключ", "asset_١٢"
        ] {
            let xml = singleItemXML(stableKey: invalidStableKey)

            XCTAssertThrowsError(
                try LanguageVocabularyCatalogLoader.load(
                    xmlData: Data(xml.utf8),
                    manifestData: emptyManifestData(),
                    availableAssetReferences: []
                )
            ) { error in
                XCTAssertEqual(
                    error as? LanguageVocabularyLoadError,
                    .invalidXMLKey(invalidStableKey)
                )
            }
        }
    }

    func testXMLStableKeysWithSurroundingWhitespaceAreRejectedWithoutNormalization() {
        for invalidStableKey in [" fruits_apple", "fruits_apple ", " fruits_apple "] {
            let xml = singleItemXML(stableKey: invalidStableKey)

            XCTAssertThrowsError(
                try LanguageVocabularyCatalogLoader.load(
                    xmlData: Data(xml.utf8),
                    manifestData: emptyManifestData(),
                    availableAssetReferences: []
                )
            ) { error in
                XCTAssertEqual(
                    error as? LanguageVocabularyLoadError,
                    .invalidXMLKey(invalidStableKey)
                )
            }
        }
    }

    func testWhitespaceOnlyXMLStableKeyFailsAsBlankKey() {
        let xml = singleItemXML(stableKey: "   ")

        XCTAssertThrowsError(
            try LanguageVocabularyCatalogLoader.load(
                xmlData: Data(xml.utf8),
                manifestData: emptyManifestData(),
                availableAssetReferences: []
            )
        ) { error in
            XCTAssertEqual(
                error as? LanguageVocabularyLoadError,
                .blankXMLKey(arrayName: "fruits_a")
            )
        }
    }

    func testInvalidCategoryIdentifiersFailCleanly() {
        for invalidArrayName in ["bad-category_a", "Bad_category_a", "bad.category_a", "bad category_a"] {
            XCTAssertThrowsError(try LanguageVocabularyCatalogLoader.parseArrayName(invalidArrayName)) { error in
                XCTAssertEqual(
                    error as? LanguageVocabularyLoadError,
                    .invalidCategoryIdentifier(String(invalidArrayName.split(separator: "_").dropLast().joined(separator: "_")))
                )
            }
        }

        for invalidManifestCategory in [
            "bad-category", "Bad_category", "bad.category", "bad category",
            "café", "категория"
        ] {
            let manifest = manifestData(rows: [
                "concept_alpha\tapple\treviewed\tApple\tתפוח\tA\t\(invalidManifestCategory)\texisting_ios\texisting_android\treuse_ios"
            ])

            XCTAssertThrowsError(
                try LanguageVocabularyCatalogLoader.load(
                    xmlData: Data(singleItemXML(stableKey: "concept_alpha").utf8),
                    manifestData: manifest,
                    availableAssetReferences: [AssetReference(rawValue: "apple")]
                )
            ) { error in
                XCTAssertEqual(
                    error as? LanguageVocabularyLoadError,
                    .invalidManifestCategory(invalidManifestCategory)
                )
            }
        }
    }

    func testInvalidManifestStableAndAssetIdentifiersFailCleanly() {
        for invalidStableKey in ["bad key", "bad-key", "bad.key", "Bad_key", "café", "ключ", "asset_١٢"] {
            let manifest = manifestData(rows: [
                "\(invalidStableKey)\tapple\treviewed\tApple\tתפוח\tA\tfruits\texisting_ios\texisting_android\treuse_ios"
            ])

            XCTAssertThrowsError(
                try LanguageVocabularyCatalogLoader.load(
                    xmlData: Data(singleItemXML(stableKey: "concept_alpha").utf8),
                    manifestData: manifest,
                    availableAssetReferences: [AssetReference(rawValue: "apple")]
                )
            ) { error in
                XCTAssertEqual(
                    error as? LanguageVocabularyLoadError,
                    .invalidManifestStableKey(invalidStableKey)
                )
            }
        }

        XCTAssertThrowsError(
            try LanguageVocabularyCatalogLoader.load(
                xmlData: Data(singleItemXML(stableKey: "concept_alpha").utf8),
                manifestData: manifestData(rows: [
                    "concept_alpha\t   \treviewed\tApple\tתפוח\tA\tfruits\texisting_ios\texisting_android\treuse_ios"
                ]),
                availableAssetReferences: []
            )
        ) { error in
            guard case .blankManifestAssetKey(_) = error as? LanguageVocabularyLoadError else {
                return XCTFail("Expected a blank manifest asset-key error.")
            }
        }

        for invalidAssetKey in ["bad key", "bad-key", "bad.key", "Bad_key", "café", "ключ", "asset_١٢"] {
            let manifest = manifestData(rows: [
                "concept_alpha\t\(invalidAssetKey)\treviewed\tApple\tתפוח\tA\tfruits\texisting_ios\texisting_android\treuse_ios"
            ])

            XCTAssertThrowsError(
                try LanguageVocabularyCatalogLoader.load(
                    xmlData: Data(singleItemXML(stableKey: "concept_alpha").utf8),
                    manifestData: manifest,
                    availableAssetReferences: []
                )
            ) { error in
                XCTAssertEqual(
                    error as? LanguageVocabularyLoadError,
                    .invalidManifestAssetKey(invalidAssetKey)
                )
            }
        }
    }

    func testContradictoryManifestActionStatusCombinationsFailCleanly() {
        let contradictoryRows = [
            "concept_alpha\tapple\treviewed\tApple\tתפוח\tA\tfruits\tmissing_ios\texisting_android\treuse_ios",
            "concept_alpha\tapple\treviewed\tApple\tתפוח\tA\tfruits\texisting_ios\texisting_android\tmigrate_android",
            "concept_alpha\tapple\treviewed\tApple\tתפוח\tA\tfruits\tmissing_ios\tmissing_android\tmigrate_android",
            "concept_alpha\tapple\treviewed\tApple\tתפוח\tA\tfruits\tmissing_ios\texisting_android\ttrusted_acquire",
            "concept_alpha\tapple\treviewed\tApple\tתפוח\tA\tfruits\texisting_ios\ttrusted_external\ttrusted_acquire",
            "concept_alpha\tapple\treviewed\tApple\tתפוח\tA\tfruits\tmissing_ios\texisting_android\tcreate_new",
            "concept_alpha\tapple\treviewed\tApple\tתפוח\tA\tfruits\texisting_ios\tmissing_android\tcreate_new"
        ]

        for row in contradictoryRows {
            XCTAssertThrowsError(
                try LanguageVocabularyCatalogLoader.load(
                    xmlData: Data(singleItemXML(stableKey: "concept_alpha").utf8),
                    manifestData: manifestData(rows: [row]),
                    availableAssetReferences: [AssetReference(rawValue: "apple")]
                )
            ) { error in
                guard case .invalidManifestActionStatusCombination(_) = error as? LanguageVocabularyLoadError else {
                    return XCTFail("Expected an action/status integrity error.")
                }
            }
        }
    }

    func testTrustedExternalStatusParsesAndTrustedAcquireRemainsNotReady() throws {
        let catalog = try LanguageVocabularyCatalogLoader.load(
            xmlData: Data(singleItemXML(stableKey: "concept_alpha").utf8),
            manifestData: manifestData(rows: [
                "concept_alpha\tapple\treviewed\tApple\tתפוח\tA\tfruits\tmissing_ios\ttrusted_external\ttrusted_acquire"
            ]),
            availableAssetReferences: [AssetReference(rawValue: "apple")]
        )
        let item = try XCTUnwrap(catalog.item(stableKey: "concept_alpha"))

        XCTAssertEqual(item.imageManifestEntry?.androidAssetStatus, .trustedExternal)
        XCTAssertEqual(item.imageManifestEntry?.imageAction, .trustedAcquire)
        XCTAssertFalse(item.isImageReady)
    }

    func testCreateNewExactCombinationSucceedsButRemainsNotReady() throws {
        let catalog = try LanguageVocabularyCatalogLoader.load(
            xmlData: Data(singleItemXML(stableKey: "concept_alpha").utf8),
            manifestData: manifestData(rows: [
                "concept_alpha\tapple\treviewed\tApple\tתפוח\tA\tfruits\tmissing_ios\tmissing_android\tcreate_new"
            ]),
            availableAssetReferences: [AssetReference(rawValue: "apple")]
        )

        XCTAssertFalse(try XCTUnwrap(catalog.item(stableKey: "concept_alpha")).isImageReady)
    }

    func testReuseIOSExactCurrentReadinessBehaviorRemainsEnforced() throws {
        let manifest = manifestData(rows: [
            "concept_alpha\tapple\treviewed\tApple\tתפוח\tA\tfruits\texisting_ios\texisting_android\treuse_ios"
        ])

        let readyCatalog = try LanguageVocabularyCatalogLoader.load(
            xmlData: Data(singleItemXML(stableKey: "concept_alpha").utf8),
            manifestData: manifest,
            availableAssetReferences: [AssetReference(rawValue: "apple")]
        )
        XCTAssertTrue(try XCTUnwrap(readyCatalog.item(stableKey: "concept_alpha")).isImageReady)

        let unresolvedCatalog = try LanguageVocabularyCatalogLoader.load(
            xmlData: Data(singleItemXML(stableKey: "concept_alpha").utf8),
            manifestData: manifest,
            availableAssetReferences: []
        )
        XCTAssertFalse(try XCTUnwrap(unresolvedCatalog.item(stableKey: "concept_alpha")).isImageReady)
    }

    func testHistoricalFruitsIDsRemainExactlyUnchanged() throws {
        let items = try XCTUnwrap(LanguageWordCatalog.category(withID: .fruits)?.items)

        XCTAssertEqual(items.map(\.stableKey), [
            "fruits_apple", "fruits_lemon", "fruits_plum", "fruits_peach",
            "fruits_grapes", "fruits_mango", "fruits_banana", "fruits_orange",
            "fruits_lime", "fruits_kiwi"
        ])
        XCTAssertEqual(items.compactMap(\.androidWordID), items.map(\.stableKey))
        XCTAssertEqual(items.map(\.id.rawValue), items.map {
            "language.words.\($0.stableKey)"
        })
    }

    func testGarlicAndKingHistoricalIdentityIsPreserved() throws {
        let garlic = try XCTUnwrap(LanguageWordCatalog.item(stableKey: "vegetables_garlic"))
        let king = try XCTUnwrap(LanguageWordCatalog.item(stableKey: "other_king"))

        XCTAssertEqual(garlic.id.rawValue, "language.words.vegetables_garlic")
        XCTAssertEqual(garlic.androidWordID, "vegetables_garlic")
        XCTAssertEqual(king.categoryID, LanguageWordCategoryID(rawValue: "fantasy_adventure"))
        XCTAssertEqual(king.stableKey, "other_king")
        XCTAssertEqual(king.id.rawValue, "language.words.other_king")
        XCTAssertEqual(king.androidWordID, "other_king")
    }

    func testRepresentativeSemanticSamplingCategoryMovesMatchApprovedCatalog() throws {
        try assertCategory("toys_games", forStableKeys: ["transport_toy"])
        try assertCategory("transport", forStableKeys: [
            "home_boat",
            "home_truck",
            "home_taxi",
            "home_motorcycle",
            "tech_rocket"
        ])
        try assertCategory("sports", forStableKeys: [
            "sports_future_soccer",
            "shapes_ball",
            "shapes_basketball",
            "shapes_volleyball",
            "shapes_tennis_ball",
            "shapes_soccer_ball",
            "shapes_beach_ball"
        ])
        try assertCategory("fantasy_adventure", forStableKeys: ["other_king"])
        try assertCategory("music", forStableKeys: ["other_drum"])
        try assertCategory("science_objects", forStableKeys: ["school_microscope"])
        try assertCategory("school_work", forStableKeys: ["school_supplies_project"])
        try assertCategory("symbols", forStableKeys: ["tech_sign"])
        try assertCategory("family_people", forStableKeys: ["expressions_friend"])
        try assertCategory("directions", forStableKeys: [
            "expressions_in",
            "expressions_on",
            "expressions_under"
        ])
    }

    func testMixedOtherAndSportsFutureAreAbsentFromStandardCatalog() {
        let allCategoryIDs = Set(LanguageWordCatalog.allItems.map(\.categoryID))

        XCTAssertFalse(allCategoryIDs.contains(LanguageWordCategoryID(rawValue: "mixed_other")))
        XCTAssertFalse(allCategoryIDs.contains(LanguageWordCategoryID(rawValue: "sports_future")))

        for level in LanguageVocabularyLevel.allCases {
            XCTAssertFalse(LanguageWordCatalog.categories(for: level).contains {
                $0.id == LanguageWordCategoryID(rawValue: "mixed_other")
            })
            XCTAssertFalse(LanguageWordCatalog.categories(for: level).contains {
                $0.id == LanguageWordCategoryID(rawValue: "sports_future")
            })
        }
    }

    func testSemanticSamplingHebrewRepairsAreApplied() throws {
        XCTAssertEqual(
            try XCTUnwrap(LanguageWordCatalog.item(stableKey: "verbs_help")).hebrewText,
            "לעזור"
        )
        XCTAssertEqual(
            try XCTUnwrap(LanguageWordCatalog.item(stableKey: "verbs_clean")).hebrewText,
            "לנקות"
        )
        XCTAssertEqual(
            try XCTUnwrap(LanguageWordCatalog.item(stableKey: "time_century")).hebrewText,
            "מאה שנה"
        )
        XCTAssertEqual(
            try XCTUnwrap(LanguageWordCatalog.item(stableKey: "time_millennium")).hebrewText,
            "אלף שנה"
        )
    }

    func testNoSameLevelLexicalSurfaceCollisionsExistForEnglishOrHebrew() {
        for level in LanguageVocabularyLevel.allCases {
            assertNoNormalizedLexicalCollisions(for: level, language: .english)
            assertNoNormalizedLexicalCollisions(for: level, language: .hebrew)
        }
    }

    func testInitialLetterSupportItemsResolveActualCatalogItems() throws {
        let garlic = try XCTUnwrap(LanguageWordCatalog.item(stableKey: "vegetables_garlic"))
        let king = try XCTUnwrap(LanguageWordCatalog.item(stableKey: "other_king"))

        XCTAssertEqual(LanguageWordCatalog.initialLetterSupportItems.map(\.stableKey), [
            "vegetables_garlic",
            "other_king"
        ])
        XCTAssertTrue(LanguageWordCatalog.initialLetterSupportItems.contains(garlic))
        XCTAssertTrue(LanguageWordCatalog.initialLetterSupportItems.contains(king))
    }

    func testKiwiSpeechCorrectionIsPreservedInCatalog() throws {
        let kiwi = try XCTUnwrap(LanguageWordCatalog.item(stableKey: "fruits_kiwi"))

        XCTAssertEqual(kiwi.englishText, "Kiwi")
        XCTAssertEqual(kiwi.hebrewText, "קיווי")
        XCTAssertEqual(kiwi.hebrewSpeechText, "Kiwi")
    }

    private func lexicalCount(for level: LanguageVocabularyLevel) -> Int {
        LanguageWordCatalog.items(for: level).filter(\.isLexical).count
    }

    private func sentenceCount(for level: LanguageVocabularyLevel) -> Int {
        LanguageWordCatalog.items(for: level).filter { $0.contentKind == .sentence }.count
    }

    private func singleItemXML(
        stableKey: String,
        english: String = "Apple",
        hebrew: String = "תפוח"
    ) -> String {
        fixtureXML(
            arrayName: "fruits_a",
            rows: [
                #"<word key="\#(stableKey)" en="\#(english)" he="\#(hebrew)" />"#
            ]
        )
    }

    private func fixtureXML(
        arrayName: String,
        rows: [String]
    ) -> String {
        """
        <?xml version='1.0' encoding='utf-8'?>
        <resources>
            <string-array name="\(arrayName)">
        \(rows.map { "        \($0)" }.joined(separator: "\n"))
            </string-array>
        </resources>
        """
    }

    private func manifestData(
        rows: [String]
    ) -> Data {
        Data(
            """
            stableKey\tassetKey\tsource\tenglish\thebrew\tproposedBaseLevel\tproposedCategory\tiosAssetStatus\tandroidAssetStatus\timageAction
            \(rows.joined(separator: "\n"))
            """.utf8
        )
    }

    private func assertManifestMetadataMismatch(
        manifestRow: String,
        expectedError: LanguageVocabularyLoadError
    ) {
        XCTAssertThrowsError(
            try LanguageVocabularyCatalogLoader.load(
                xmlData: Data(singleItemXML(stableKey: "concept_alpha").utf8),
                manifestData: manifestData(rows: [manifestRow]),
                availableAssetReferences: [AssetReference(rawValue: "apple")]
            )
        ) { error in
            XCTAssertEqual(error as? LanguageVocabularyLoadError, expectedError)
        }
    }

    private func approvedData(
        named name: String,
        fileExtension: String,
        file: StaticString = #filePath
    ) throws -> Data {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let repoRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repoRoot
            .appendingPathComponent("docs")
            .appendingPathComponent("\(name).\(fileExtension)")
        return try Data(contentsOf: url)
    }

    private var knownReadyAssets: Set<AssetReference> {
        Set(
            LanguageWordCatalog.imageManifestEntries
                .filter {
                    $0.iosAssetStatus == .existingIOS &&
                        $0.imageAction == .reuseIOS
                }
                .map(\.assetReference)
        )
    }

    private func assertCategory(
        _ category: String,
        forStableKeys stableKeys: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        for stableKey in stableKeys {
            let item = try XCTUnwrap(
                LanguageWordCatalog.item(stableKey: stableKey),
                file: file,
                line: line
            )
            XCTAssertEqual(
                item.categoryID,
                LanguageWordCategoryID(rawValue: category),
                "Unexpected category for \(stableKey).",
                file: file,
                line: line
            )
        }
    }

    private func assertNoNormalizedLexicalCollisions(
        for level: LanguageVocabularyLevel,
        language: LanguageIdentifier,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let locale: Locale
        switch language {
        case .english:
            locale = Locale(identifier: "en_US_POSIX")
        case .hebrew:
            locale = Locale(identifier: "he_IL")
        default:
            locale = Locale(identifier: language.rawValue)
        }

        let lexicalItems = LanguageWordCatalog.items(for: level).filter(\.isLexical)
        let groupedStableKeys = Dictionary(grouping: lexicalItems) { item in
            let text: String
            switch language {
            case .english:
                text = item.englishText
            case .hebrew:
                text = item.hebrewText
            default:
                text = item.englishText
            }
            return text
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased(with: locale)
        }

        for (normalizedText, items) in groupedStableKeys {
            let stableKeys = Set(items.map(\.stableKey))
            XCTAssertEqual(
                stableKeys.count,
                1,
                "\(language.rawValue) level \(level.rawValue) collision for '\(normalizedText)': \(stableKeys.sorted())",
                file: file,
                line: line
            )
        }
    }

    private func emptyManifestData() -> Data {
        manifestData(rows: [])
    }
}
