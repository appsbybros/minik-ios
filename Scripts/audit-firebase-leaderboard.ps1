[CmdletBinding()]
param(
    [string]$RepositoryRoot
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = Split-Path -Parent $PSScriptRoot
}
$errors = [System.Collections.Generic.List[string]]::new()

function Read-Required([string]$RelativePath) {
    $path = Join-Path $RepositoryRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $errors.Add("Missing $RelativePath")
        return ''
    }
    return [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
}

function Require([string]$Content, [string]$Pattern, [string]$Message) {
    if ($Content -notmatch $Pattern) { $errors.Add($Message) }
}

function Reject([string]$Content, [string]$Pattern, [string]$Message) {
    if ($Content -match $Pattern) { $errors.Add($Message) }
}

$fixtureText = Read-Required 'Config/Firebase/leaderboard-contract.json'
$remote = Read-Required 'Sources/RemoteRecords.swift'
$integration = Read-Required 'Sources/FirebaseRecordsIntegration.swift'
$rules = Read-Required 'firestore.rules'
$indexes = Read-Required 'firestore.indexes.json'
$firebase = Read-Required 'firebase.json'
$project = Read-Required 'project.yml'
$entitlements = Read-Required 'Resources/Entitlements/MinikLanguage.entitlements'
$tests = Read-Required 'Tests/ProductConfigurationTests/RemoteRecordsTests.swift'
$documentation = Read-Required 'docs/firebase-leaderboard-contract.md'
$migration = Read-Required 'docs/firebase-leaderboard-migration.md'

try {
    $fixture = $fixtureText | ConvertFrom-Json
    if ($fixture.contractVersion -ne 2 -or $fixture.appId -ne '3' -or $fixture.topRecordsLimit -ne 20) {
        $errors.Add('Contract fixture app ID or top-record limit changed.')
    }
    if ($fixture.ownership.collection -ne 'leaderboard_owners' -or
        @($fixture.ownership.fields).Count -ne 1 -or
        $fixture.ownership.fields[0] -ne 'owner_uid' -or
        $fixture.ownership.clientReadable -ne $false -or
        $fixture.ownership.legacyIDsClaimable -ne $false) {
        $errors.Add('Secure ownership fixture changed.')
    }
    $querySignatures = @($fixture.queries | ForEach-Object {
        "$($_.collection)|$($_.orderBy)|$($_.filter.equals)|$($_.limit)"
    })
    foreach ($expected in @(
        'score_records|score|3|20',
        'score_records_english_only|score|3|20',
        'correct_answers_in_row|correct_answers_in_row|3|20'
    )) {
        if ($expected -notin $querySignatures) { $errors.Add("Missing fixture query $expected") }
    }
} catch {
    $errors.Add("Contract fixture is invalid JSON: $($_.Exception.Message)")
}

try { [void]($indexes | ConvertFrom-Json) } catch { $errors.Add('firestore.indexes.json is invalid JSON.') }
try { [void]($firebase | ConvertFrom-Json) } catch { $errors.Add('firebase.json is invalid JSON.') }

$workspaceRoot = Split-Path -Parent $RepositoryRoot
$androidRecordsPath = Join-Path $workspaceRoot 'subscriptionlib\src\main\java\com\minik\subscription\RecordsDetails.kt'
$androidIntroPath = Join-Path $workspaceRoot 'android\app\src\main\java\com\minik\minik\fragments\IntroScreen.kt'
if (-not (Test-Path -LiteralPath $androidRecordsPath)) { $errors.Add('Android RecordsDetails.kt source is unavailable.') }
if (-not (Test-Path -LiteralPath $androidIntroPath)) { $errors.Add('Android IntroScreen.kt source is unavailable.') }
$androidRecords = if (Test-Path -LiteralPath $androidRecordsPath) { [IO.File]::ReadAllText($androidRecordsPath) } else { '' }
$androidIntro = if (Test-Path -LiteralPath $androidIntroPath) { [IO.File]::ReadAllText($androidIntroPath) } else { '' }

foreach ($pattern in @(
    'RECORDS_APP_ID = "3"',
    'TOP_RECORDS_LIMIT = 20L',
    'SCORE_RECORDS_COLLECTION = "score_records"',
    'SCORE_RECORDS_COLLECTION_ENG_ONLY = "score_records_english_only"',
    'STREAK_RECORDS_COLLECTION = "correct_answers_in_row"',
    'FIELD_DATE_ACHIEVED = "date_achived"',
    'whereEqualTo\(FIELD_APP_ID, RECORDS_APP_ID\)',
    '\.limit\(TOP_RECORDS_LIMIT\)',
    'db\.runBatch'
)) { Require $androidRecords $pattern "Android production contract missing pattern: $pattern" }
Require $androidIntro 'playerId = UUID\.randomUUID\(\)\.toString\(\)' 'Android player_id is no longer proven to be an auth-independent UUID.'

foreach ($pattern in @(
    'scoreCollection: "score_records"',
    'scoreCollection: "score_records_english_only"',
    'streakCollection: "correct_answers_in_row"',
    'static let dateAchieved = "date_achived"',
    'RemoteRecordsSchema\.userName: \.string\(publicAlias\.publicAlias\)',
    'AuthenticatedRemoteRecordsDataSource',
    'authentication\.ensureAuthenticated\(\)',
    'SecureLeaderboardParticipantID',
    'RemoteRecordsOwnershipSchema',
    'AuthenticatedRemoteRecordsOwnershipStore',
    'ownershipStore\.ensureOwnership\(of: playerID\)'
)) { Require $remote $pattern "iOS leaderboard contract missing pattern: $pattern" }
Reject $remote 'localChildName|localProfileName|displayName' 'Remote source contains a local-name input path.'
Reject $remote 'playerID\s*=\s*try await authentication\.ensureAuthenticated' 'Firebase auth.uid must not replace the profile-scoped player_id.'
Reject $remote 'RemoteRecordsSchema[\s\S]*static let platform' 'A platform field would split the shared public schema.'

Require $integration 'signInAnonymously\(\)' 'Anonymous Firebase Auth sign-in is missing.'
Require $integration 'claimOwnership[\s\S]*leaderboard_owners|claimOwnership[\s\S]*RemoteRecordsOwnershipSchema\.collection' 'Firebase ownership claim source is missing.'
Require $integration 'FirebaseAppCheckBootstrap\.configureProvider\(\)[\s\S]*FirebaseApp\.configure\(options: options\)' 'App Check is not initialized before Firebase.'
Require $integration 'case \.debug:\s*#if DEBUG\s*AppCheck\.setAppCheckProviderFactory\(AppCheckDebugProviderFactory\(\)\)\s*#else\s*preconditionFailure\("Release builds cannot select the Firebase App Check debug provider\."\)\s*#endif' 'Debug App Check provider is not confined to DEBUG compilation.'
Require $integration 'case \.appAttest:[\s\S]*MinikAppAttestProviderFactory' 'Release App Attest provider is missing.'
if ([regex]::Matches($integration, 'AppCheckDebugProviderFactory').Count -ne 1) {
    $errors.Add('Expected exactly one DEBUG-confined AppCheckDebugProviderFactory reference.')
}

foreach ($collection in @('score_records', 'score_records_english_only', 'correct_answers_in_row')) {
    Require $rules "match /$collection/\{playerID\}" "Rules omit $collection."
}
foreach ($field in @('app_id', 'player_id', 'score', 'correct_answers_in_row', 'date_achived', 'user_name', 'avatar_id')) {
    Require $rules ([regex]::Escape("'$field'")) "Rules omit field $field."
}
Require $rules 'match /leaderboard_owners/\{playerID\}' 'Rules omit the private ownership collection.'
Require $rules 'match /leaderboard_owners/\{playerID\}[\s\S]*allow read: if false;[\s\S]*allow create:[\s\S]*request\.resource\.data\.owner_uid == request\.auth\.uid;[\s\S]*allow update:[\s\S]*resource\.data\.owner_uid == request\.auth\.uid[\s\S]*request\.resource\.data\.owner_uid == resource\.data\.owner_uid;[\s\S]*allow delete: if false;' 'Ownership documents are not private, immutable bindings.'
Require $rules 'exists\(/databases/\$\(database\)/documents/leaderboard_owners/\$\(playerID\)\)[\s\S]*get\(/databases/\$\(database\)/documents/leaderboard_owners/\$\(playerID\)\)\.data\.owner_uid[\s\S]*== request\.auth\.uid' 'Public mutations do not prove ownership through the private binding.'
Require $rules "playerID\.matches\('\^v2_\[0-9a-f\]\{8\}-\[0-9a-f\]\{4\}-\[1-5\]\[0-9a-f\]\{3\}-\[89ab\]\[0-9a-f\]\{3\}-\[0-9a-f\]\{12\}\$'\)" 'Rules do not require a versioned UUID and reject legacy participant IDs.'
Reject $rules 'playerID == request\.auth\.uid|data\.player_id == request\.auth\.uid' 'Rules incorrectly replace profile player_id with auth.uid.'
Reject $rules "'platform'" 'Rules unexpectedly allow a platform-specific public field.'
Require $rules 'data\.keys\(\)\.hasOnly' 'Rules do not reject extra fields.'
Require $rules 'data\.date_achived == request\.time' 'Rules do not require a server-compatible timestamp.'
Require $rules 'request\.query\.limit <= 20' 'Leaderboard list reads are not capped at 20.'
Require $rules 'match /\{document=\*\*\}[\s\S]*allow read, write: if false' 'Unrelated Firestore paths are not denied.'
Require $documentation 'not deployable against legacy production data/clients' 'Rules deployment blocker is not explicit.'
Require $documentation 'leaderboard_owners/\{player_id\}' 'Private ownership schema is undocumented.'
Require $migration 'Keep the established active public collection names[\s\S]*Archive the legacy contents[\s\S]*clear the active collections' 'Selected legacy migration strategy is missing.'
Require $migration 'Do not let a client claim a legacy UUID' 'Legacy records can be insecurely claimed.'
Require $migration 'Android reference repositories are read-only' 'Android implementation handoff is missing.'
Require $migration 'App Check sequence' 'App Check enforcement sequence is missing.'
Require $firebase '"rules"\s*:\s*"firestore\.rules"' 'firebase.json does not route Firestore Rules.'
Require $firebase '"indexes"\s*:\s*"firestore\.indexes\.json"' 'firebase.json does not route Firestore indexes.'

foreach ($target in @('MinikPlus', 'MinikPlusEnglish')) {
    $body = [regex]::Match($project, "(?ms)^  ${target}:(?<body>[\s\S]*?)(?=^  [A-Za-z][A-Za-z0-9]+:|\z)").Groups['body'].Value
    Require $body 'product: FirebaseAppCheck' "$target does not link FirebaseAppCheck."
    Require $body 'CODE_SIGN_ENTITLEMENTS: Resources/Entitlements/MinikLanguage\.entitlements' "$target lacks the App Attest entitlement route."
}
foreach ($target in @('MinikMathPlus', 'MinikMath', 'MinikPingPong')) {
    $body = [regex]::Match($project, "(?ms)^  ${target}:(?<body>[\s\S]*?)(?=^  [A-Za-z][A-Za-z0-9]+:|\z)").Groups['body'].Value
    if ($body -match 'FirebaseAppCheck|CODE_SIGN_ENTITLEMENTS') { $errors.Add("$target must remain outside Firebase App Check.") }
}
Require $entitlements 'com\.apple\.developer\.devicecheck\.appattest-environment[\s\S]*<string>production</string>' 'Language entitlement is not production App Attest.'
Require $tests 'testAndroidProductionDocumentDecodesAndIOSWriteMatchesItsSchema' 'Cross-platform record fixture test is missing.'
Require $tests 'testNoRemoteWriteWithoutAuthAndPendingRetriesAfterAnonymousAuthIsAvailable' 'Anonymous-auth retry test is missing.'
Require $tests 'testPendingScoreSurvivesMissingFirebaseConfiguration' 'Missing-configuration pending-score test is missing.'
Require $tests 'testReleaseAppCheckPolicyCannotSelectDebugProvider' 'Release App Check selection test is missing.'
Require $tests 'testOneAnonymousUIDCanOwnMultipleDistinctChildProfiles' 'Multiple-profile ownership test is missing.'
Require $tests 'testAnotherAnonymousUIDCannotTakeOverOwnedParticipant' 'Cross-auth ownership isolation test is missing.'
Require $tests 'testLegacyParticipantCannotBeClaimedAndLocalBestRepublishesWithSecureID' 'Secure republish migration test is missing.'
Require $tests 'testLegacyPlayerIDCannotReachOwnershipClaimSource' 'Legacy claim rejection test is missing.'
foreach ($testName in @(
    'testAndroidCompatibleConfigurationPreservesProductCollections',
    'testAndroidProductionDocumentDecodesAndIOSWriteMatchesItsSchema',
    'testRemotePayloadUsesOnlyAllowlistedFieldsAndNeverLocalName',
    'testNoRemoteAccessBeforeAliasSelectionAndAliasSelectionPublishesPendingScore',
    'testFutureRecordsReuseAliasAndDisablingStopsUploadsImmediately',
    'testDeletionRemovesPublicDocumentsWithoutDeletingLocalProgress',
    'testAliasGeneratorProducesOnlyCuratedTypedValuesAndRejectsFreeText',
    'testIdentityIsStableAndScopedByProductAndLocalProfile'
)) {
    Require $tests $testName "Required secure-leaderboard test is missing: $testName"
}

$errors | ForEach-Object { "FIREBASE_LEADERBOARD_ERROR=$_" }
"FIREBASE_LEADERBOARD_CONTRACT_QUERIES=3"
"FIREBASE_LEADERBOARD_RULE_COLLECTIONS=3"
"FIREBASE_LEADERBOARD_OWNERSHIP_COLLECTION=leaderboard_owners"
"FIREBASE_LEADERBOARD_OWNERSHIP_MODE=PRIVATE_PROFILE_BINDING"
"FIREBASE_LEADERBOARD_DEPLOYMENT=LEGACY_CUTOVER_REQUIRED"
"FIREBASE_LEADERBOARD_REQUIRED_CASES=19"
"FIREBASE_APP_CHECK_RELEASE_PROVIDER=APP_ATTEST"
"FIREBASE_LEADERBOARD_ERRORS=$($errors.Count)"
if ($errors.Count -gt 0) { exit 1 }
