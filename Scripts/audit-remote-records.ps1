[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$errors = [System.Collections.Generic.List[string]]::new()

function Require-Pattern {
    param([string]$Path, [string]$Pattern, [string]$Message)
    $fullPath = Join-Path $root $Path
    if (-not (Test-Path -LiteralPath $fullPath)) {
        $errors.Add("Missing $Path ($Message)")
        return
    }
    $source = [IO.File]::ReadAllText($fullPath, [Text.Encoding]::UTF8)
    if ($source -notmatch $Pattern) {
        $errors.Add("${Path}: $Message")
    }
}

function Reject-Pattern {
    param([string]$Path, [string]$Pattern, [string]$Message)
    $fullPath = Join-Path $root $Path
    if (-not (Test-Path -LiteralPath $fullPath)) {
        $errors.Add("Missing $Path ($Message)")
        return
    }
    $source = [IO.File]::ReadAllText($fullPath, [Text.Encoding]::UTF8)
    if ($source -match $Pattern) {
        $errors.Add("${Path}: $Message")
    }
}

Require-Pattern 'Sources/RemoteRecords.swift' 'static let appID = "3"' 'Android app_id contract is missing'
Require-Pattern 'Sources/RemoteRecords.swift' 'static let topRecordsLimit = 20' 'top-20 limit is missing'
Require-Pattern 'Sources/RemoteRecords.swift' 'scoreCollection: "score_records"' 'Minik Plus score collection is missing'
Require-Pattern 'Sources/RemoteRecords.swift' 'scoreCollection: "score_records_english_only"' 'English Only score collection is missing'
Require-Pattern 'Sources/RemoteRecords.swift' 'streakCollection: "correct_answers_in_row"' 'shared streak collection is missing'
Require-Pattern 'Sources/RemoteRecords.swift' 'static let dateAchieved = "date_achived"' 'legacy date_achived spelling changed'
Require-Pattern 'Sources/RemoteRecords.swift' 'mergeAtomically\(writes\)' 'qualified score/streak writes are not atomic'
Require-Pattern 'Sources/RemoteRecords.swift' 'guard await participationProvider\.isLeaderboardParticipationEnabled\(\)' 'record submission is not protected by the persisted participation preference'
Require-Pattern 'Sources/RemoteRecords.swift' 'RemoteRecordsSchema\.userName: \.string\(publicAlias\.publicAlias\)' 'legacy user_name is not restricted to the curated public alias'
Require-Pattern 'Sources/RemoteRecords.swift' 'deleteParticipantRecords\(\)[\s\S]*deleteAtomically\(deletions\)' 'participant-scoped public-record deletion is missing'
Require-Pattern 'Sources/RemoteRecords.swift' 'SecureLeaderboardParticipantID[\s\S]*prefix = "v2_"[\s\S]*UUID\(\)\.uuidString\.lowercased\(\)' 'secure versioned per-profile participant identity is missing'
Require-Pattern 'Sources/RemoteRecords.swift' 'AuthenticatedRemoteRecordsOwnershipStore[\s\S]*authentication\.ensureAuthenticated\(\)[\s\S]*claimOwnership' 'authenticated private ownership binding is missing'
Require-Pattern 'Sources/RemoteRecords.swift' 'ownershipStore\.ensureOwnership\(of: playerID\)[\s\S]*dataSource\.mergeAtomically\(writes\)' 'record writes are not ownership-gated'
Require-Pattern 'Sources/RemoteRecords.swift' 'ownershipStore\.ensureOwnership\(of: playerID\)[\s\S]*dataSource\.deleteAtomically\(deletions\)' 'record deletion is not ownership-gated'
Require-Pattern 'Sources/FirebaseRecordsIntegration.swift' 'signInAnonymously\(\)' 'anonymous Firebase identity boundary is missing'
Require-Pattern 'Sources/FirebaseRecordsIntegration.swift' 'AndroidCompatibleRecordsIdentityStore\([\s\S]*product: product,[\s\S]*ownerID: ownerID' 'product/profile-scoped public participant identity is not composed'
Require-Pattern 'Sources/RemoteRecords.swift' 'struct AuthenticatedRemoteRecordsDataSource[\s\S]*authentication\.ensureAuthenticated\(\)[\s\S]*dataSource\.mergeAtomically' 'Firestore operations do not independently establish anonymous backend authentication'
Require-Pattern 'Sources/FirebaseRecordsIntegration.swift' 'path\(forResource: "GoogleService-Info", ofType: "plist"\)' 'injectable Firebase plist boundary is missing'
Require-Pattern 'Sources/FirebaseRecordsIntegration.swift' 'func deleteAtomically\(_ deletions:[\s\S]*batch\.deleteDocument' 'Firestore batch deletion is missing'
Require-Pattern 'Sources/FirebaseRecordsIntegration.swift' 'func claimOwnership[\s\S]*RemoteRecordsOwnershipSchema\.collection[\s\S]*RemoteRecordsOwnershipSchema\.ownerUID' 'Firestore private ownership write is missing'
Require-Pattern 'Sources/PublicLeaderboardPrivacy.swift' 'enum PublicLeaderboardAliasAdjective[\s\S]*enum PublicLeaderboardAliasNoun[\s\S]*numberRange = 1\.\.\.99' 'curated adjective + noun + number alias boundary is missing'
Require-Pattern 'Sources/PublicLeaderboardPrivacy.swift' 'func choices\(count:[\s\S]*SystemRandomNumberGenerator' 'curated alias choice/reroll generator is missing'
Require-Pattern 'Sources/PublicLeaderboardPrivacy.swift' 'minik\.public-leaderboard\.v1[\s\S]*scope\.product\.rawValue[\s\S]*scope\.ownerID\.rawValue' 'public alias/participation/pending state is not persisted per product/profile'
Require-Pattern 'Sources/RemoteRecords.swift' 'localState\.stage\(candidate\)[\s\S]*selectedAlias[\s\S]*participationEnabled' 'eligible records are not staged locally before alias and participation checks'
Require-Pattern 'Sources/RemoteRecords.swift' 'selectPublicAliasAndRetry[\s\S]*selectedAlias = alias[\s\S]*publishPendingCandidate\(\)' 'curated alias selection does not immediately publish an eligible pending record'
Require-Pattern 'Sources/RecordsLeaderboardView.swift' 'case loaded\(RemoteRecordsSnapshot\)[\s\S]*case notConfigured[\s\S]*case failed' 'leaderboard states are incomplete'
Require-Pattern 'Sources/RecordsLeaderboardView.swift' 'snapshot\.isFromCache' 'offline/cache state is not presented'
Require-Pattern 'Sources/MinikActivityHubView.swift' 'RecordsLeaderboardView\(' 'production records route is not connected'
Require-Pattern 'Sources/MinikActivityHubView.swift' 'publicAliasPromptIsPresented[\s\S]*Show different aliases[\s\S]*selectPublicAliasAndRetry' 'curated child alias choice/reroll flow is not connected'
Reject-Pattern 'Sources/MinikActivityHubView.swift' 'TextField\([\s\S]{0,300}(record|leaderboard|name)' 'leaderboard identity must not accept free text'
Reject-Pattern 'Resources/Localization/All/Localizable.xcstrings' '"Your name"\s*:|Enter your name to save the record' 'Full catalog retains the obsolete free-text leaderboard prompt'
Reject-Pattern 'Resources/Localization/EnglishOnly/Localizable.xcstrings' '"Your name"\s*:|Enter your name to save the record' 'English Only catalog retains the obsolete free-text leaderboard prompt'
Require-Pattern 'Sources/ParentAreaView.swift' 'Your child.s local name stays on this device\.' 'Parent Area does not disclose that the local name remains on-device'
Require-Pattern 'Sources/ParentAreaView.swift' 'Only an opaque participant identifier, generated alias or avatar, score or streak, product identifier, and timestamp are sent\.' 'Parent Area does not disclose the remote data allowlist'
Require-Pattern 'Sources/ParentAreaView.swift' 'Firebase stores the public leaderboard\.' 'Parent Area does not disclose Firebase storage'
Require-Pattern 'Sources/ParentAreaView.swift' 'publicLeaderboardController\.setParticipationEnabled\(enabled\)' 'Parent Area participation control is not directly connected'
Require-Pattern 'Sources/ParentAreaView.swift' 'publicLeaderboardController\.deletePublicRecords\(\)' 'Parent Area public-record deletion is not directly connected'
Require-Pattern 'Sources/ParentAreaView.swift' 'Show different aliases[\s\S]*publicLeaderboardController\.selectPublicAlias\(choice\)' 'Parent Area cannot change the curated public alias'
Reject-Pattern 'Sources/ParentAreaView.swift' 'leaderboardEnable|leaderboardDisable|leaderboardDelete' 'leaderboard controls still require a separate grown-up challenge'
Require-Pattern 'project.yml' 'url: https://github\.com/firebase/firebase-ios-sdk\.git' 'official Firebase Apple package is missing'
Require-Pattern 'Tests/ProductConfigurationTests/RemoteRecordsTests.swift' 'testTopTwentyRankingMatchesAndroidTieAndCutoffRules' 'ranking regression coverage is missing'
Require-Pattern 'Tests/ProductConfigurationTests/RemoteRecordsTests.swift' 'testRemotePayloadUsesOnlyAllowlistedFieldsAndNeverLocalName' 'remote allowlist/local-name exclusion coverage is missing'
Require-Pattern 'Tests/ProductConfigurationTests/RemoteRecordsTests.swift' 'testNoRemoteAccessBeforeAliasSelectionAndAliasSelectionPublishesPendingScore' 'alias-activated pending-publication coverage is missing'
Require-Pattern 'Tests/ProductConfigurationTests/RemoteRecordsTests.swift' 'testFutureRecordsReuseAliasAndDisablingStopsUploadsImmediately' 'stable alias and immediate-disable coverage is missing'
Require-Pattern 'Tests/ProductConfigurationTests/RemoteRecordsTests.swift' 'testDeletionRemovesPublicDocumentsWithoutDeletingLocalProgress' 'remote deletion/local-progress isolation coverage is missing'
Require-Pattern 'Tests/ProductConfigurationTests/RemoteRecordsTests.swift' 'testAliasGeneratorProducesOnlyCuratedTypedValuesAndRejectsFreeText' 'curated-only alias coverage is missing'
Require-Pattern 'Tests/ProductConfigurationTests/RemoteRecordsTests.swift' 'testNoRemoteWriteWithoutAuthAndPendingRetriesAfterAnonymousAuthIsAvailable' 'anonymous-auth failure/retry coverage is missing'
Require-Pattern 'Tests/ProductConfigurationTests/RemoteRecordsTests.swift' 'testPendingScoreSurvivesMissingFirebaseConfiguration' 'unconfigured pending-score coverage is missing'
Require-Pattern 'Tests/ProductConfigurationTests/RemoteRecordsTests.swift' 'testOneAnonymousUIDCanOwnMultipleDistinctChildProfiles' 'multiple-profile ownership coverage is missing'
Require-Pattern 'Tests/ProductConfigurationTests/RemoteRecordsTests.swift' 'testAnotherAnonymousUIDCannotTakeOverOwnedParticipant' 'ownership takeover rejection coverage is missing'
Require-Pattern 'Tests/ProductConfigurationTests/RemoteRecordsTests.swift' 'testLegacyParticipantCannotBeClaimedAndLocalBestRepublishesWithSecureID' 'secure migration/republish coverage is missing'
Reject-Pattern 'Sources/RemoteRecords.swift' 'records_name_|displayName|localChildName' 'remote records source retains a free-text/local-name identity path'
Reject-Pattern 'Sources/PublicLeaderboardPrivacy.swift' 'participationApproved|ParentApproval' 'obsolete mandatory-approval state remains in the privacy model'
Reject-Pattern 'Sources/RemoteRecords.swift' 'pendingParentApproval|participationNotApproved' 'obsolete mandatory-approval result remains in record submission'

$project = [IO.File]::ReadAllText((Join-Path $root 'project.yml'), [Text.Encoding]::UTF8)
foreach ($target in @('MinikPlus', 'MinikPlusEnglish')) {
    $match = [regex]::Match($project, "(?ms)^  ${target}:(?<body>[\s\S]*?)(?=^  [A-Za-z][A-Za-z0-9]+:|\z)")
    if (-not $match.Success -or
        $match.Groups['body'].Value -notmatch 'product: FirebaseAuth' -or
        $match.Groups['body'].Value -notmatch 'product: FirebaseFirestore') {
        $errors.Add("$target does not link FirebaseAuth and FirebaseFirestore.")
    }
}
foreach ($target in @('MinikMathPlus', 'MinikMath', 'MinikPingPong')) {
    $match = [regex]::Match($project, "(?ms)^  ${target}:(?<body>[\s\S]*?)(?=^  [A-Za-z][A-Za-z0-9]+:|\z)")
    if ($match.Success -and $match.Groups['body'].Value -match 'product: Firebase') {
        $errors.Add("$target must not link the Language records Firebase products.")
    }
}

$errors | ForEach-Object { "REMOTE_RECORDS_ERROR=$_" }
"REMOTE_RECORDS_ERRORS=$($errors.Count)"
if ($errors.Count -gt 0) { exit 1 }
