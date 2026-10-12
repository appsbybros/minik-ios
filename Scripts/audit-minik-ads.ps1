param(
    [string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$errors = [System.Collections.Generic.List[string]]::new()

function Require-Pattern([string]$RelativePath, [string]$Pattern, [string]$Message) {
    $path = Join-Path $RepositoryRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path)) {
        $errors.Add("Missing $RelativePath")
        return
    }
    $content = Get-Content -Raw -LiteralPath $path
    if ($content -notmatch $Pattern) {
        $errors.Add($Message)
    }
}

Require-Pattern 'project.yml' 'MINIK_ADS_ENABLED: NO' 'Ads must default disabled.'
Require-Pattern 'project.yml' 'MINIK_ADS_POLICY_APPROVED: NO' 'Policy approval must default false.'
Require-Pattern 'project.yml' 'GoogleMobileAds:[\s\S]*url: https://github\.com/googleads/swift-package-manager-google-mobile-ads\.git' 'Official Google Mobile Ads Swift package is missing.'
Require-Pattern 'project.yml' 'MinikAdsApplicationIdentifier: \$\(MINIK_ADS_APPLICATION_IDENTIFIER\)' 'Injectable provider application ID hook is missing.'
Require-Pattern 'project.yml' 'GADApplicationIdentifier: \$\(MINIK_ADS_APPLICATION_IDENTIFIER\)' 'Google Mobile Ads application ID hook is missing.'
Require-Pattern 'project.yml' 'MinikInterstitialAdUnitIdentifier: \$\(MINIK_INTERSTITIAL_AD_UNIT_IDENTIFIER\)' 'Injectable interstitial unit ID hook is missing.'
Require-Pattern 'Sources/GoogleMobileAdsInterstitialService.swift' 'requestConfiguration\.ageRestrictedTreatment = \.child[\s\S]*maxAdContentRating = GADMaxAdContentRating\.general[\s\S]*publisherPrivacyPersonalizationState = \.disabled' 'Google Mobile Ads child-treatment configuration is incomplete.'
Require-Pattern 'Sources/GoogleMobileAdsInterstitialService.swift' 'InterstitialAd\.load' 'Google Mobile Ads interstitial load boundary is missing.'
Require-Pattern 'Sources/GoogleMobileAdsInterstitialService.swift' 'canPresent\(from: nil\)[\s\S]*present\(from: nil\)' 'Google Mobile Ads interstitial presentation boundary is incomplete.'
Require-Pattern 'Sources/MinikAds.swift' 'service: service \?\? ProductionMinikInterstitialAdServiceFactory\.make\(\)' 'Production ad composition does not select the Google adapter.'
Require-Pattern 'Sources/MinikAds.swift' 'isChildDirected: true[\s\S]*treatsUserAsUnderAgeOfConsent: true[\s\S]*maximumContentRating: \.general[\s\S]*allowsPersonalizedAds: false' 'Child-directed, under-age, G-rated, non-personalized provider policy is incomplete.'
Require-Pattern 'Sources/MinikAds.swift' 'initialMinimumInterval: TimeInterval = 7 \* 60' 'Android seven-minute initial interval is missing.'
Require-Pattern 'Sources/MinikAds.swift' 'minimumInterval >= 7 \* 60[\s\S]*5 \* 60[\s\S]*minimumInterval >= 5 \* 60[\s\S]*4 \* 60[\s\S]*minimumIntervalFloor' 'Android background interval progression is missing.'
Require-Pattern 'Sources/MinikAds.swift' 'self == \.languagePictureMemory \? 3 : 1' 'Long Picture Memory rounds must carry Android weight three.'
Require-Pattern 'Sources/MinikAds.swift' 'guard !isRemoveAdsActive else \{ return \.suppressedByEntitlement \}' 'Remove Ads entitlement suppression is missing.'
Require-Pattern 'Sources/MinikAds.swift' '!isKnownGoogleSampleOrTestIdentifier\(value\)' 'Provider IDs do not fail closed for known Google sample/test identifiers.'
Require-Pattern 'Sources/MinikAds.swift' 'googleDemoPublisherID = \["394025", "6099942544"\]\.joined\(\)[\s\S]*/21775744923/example/' 'Known Google sample/test identifier families are not rejected.'
Require-Pattern 'Sources/RootView.swift' 'await adCoordinator\.start\(isRemoveAdsActive: commerceController\.isRemoveAdsActive\)' 'Entitlement-aware ad service startup is not connected.'
Require-Pattern 'Sources/RootView.swift' 'newPhase == \.background[\s\S]*applicationDidEnterBackground' 'Android-compatible background cadence update is not connected.'
Require-Pattern 'Sources/MinikActivityHubView.swift' 'onAdvance: \{ recordLanguageAdOpportunity\(\.languageWriteScreen\) \}' 'Android WriteScreen completion placement is missing.'
Require-Pattern 'Sources/MinikActivityHubView.swift' 'onRoundCompleted:[\s\S]*\.languagePictureMemory' 'Picture Memory completion placement is missing.'
Require-Pattern 'Sources/MinikActivityHubView.swift' 'onWordCompleted:[\s\S]*\.languageSoccer' 'Language Soccer completion placement is missing.'
Require-Pattern 'Sources/MinikActivityHubView.swift' 'recordLanguageTowerCompletion\(\$0\)[\s\S]*\.languageTower' 'Language Tower completion placement is missing.'
Require-Pattern 'Sources/MinikActivityHubView.swift' 'onCompletedRound:[\s\S]*\.languageTicTacToe' 'Language Tic-Tac-Toe between-round placement is missing.'
Require-Pattern 'Sources/PingPongOnlyRootView.swift' 'ModernPongView\(experience: \.full' 'Standalone Modern entry is missing.'
Require-Pattern 'Sources/ModernPong/MPAds.swift' 'total > 2[\s\S]*120_000[\s\S]*300_000[\s\S]*210_000' 'Modern cadence must preserve the first two free matches and bounded completion placements.'
Require-Pattern 'Sources/ModernPong/MPController.swift' 'ads\.completed\(id\)' 'Modern durable-result ad boundary is missing.'
Require-Pattern 'project.yml' 'MODERN_PONG_TEST_ADS: NO[\s\S]*Debug:[\s\S]*MODERN_PONG_TEST_ADS: YES' 'Modern test ads must be Debug-only.'
Require-Pattern 'Tests/ProductConfigurationTests/MinikAdsTests.swift' 'testRemoveAdsSuppressesBeforeCountersOrTimestampsChange' 'Remove Ads deterministic regression test is missing.'
Require-Pattern 'Tests/ProductConfigurationTests/MinikAdsTests.swift' 'testGoogleSampleAndTestIdentifiersFailClosed' 'Google sample/test identifier fail-closed regression test is missing.'

$projectText = Get-Content -Raw -LiteralPath (Join-Path $RepositoryRoot 'project.yml')
if ($projectText -notmatch '(?m)^        MINIK_ADS_ENABLED: NO$') {
    $errors.Add('Ads must stay disabled in the shared template until a target supplies real IDs.')
}
foreach ($forbiddenTestIdentifier in @(
    'ca-app-pub-3940256099942544',
    '/21775744923/example/'
)) {
    # The template may carry Google's published sample *app* ID only while ads are off,
    # so the linked SDK accepts launch; sample ad *units* stay forbidden.
    $checkedText = [regex]::Replace($projectText, '(?ms)^  MinikPingPong:.*?(?=^  ProductConfigurationTests:)', '')
    $checkedText = $checkedText.Replace('MINIK_ADS_APPLICATION_IDENTIFIER: "ca-app-pub-3940256099942544~1458002511"', '')
    if ($checkedText -match [regex]::Escape($forbiddenTestIdentifier)) {
        $errors.Add("Shipping project configuration contains Google sample/test identifier: $forbiddenTestIdentifier")
    }
}

$sourceFiles = Get-ChildItem -LiteralPath (Join-Path $RepositoryRoot 'Sources') -Filter '*.swift' -File
$hardcodedProviderIDs = @($sourceFiles | Select-String -Pattern 'ca-app-pub-[0-9]')
foreach ($match in $hardcodedProviderIDs) {
    $errors.Add("Hardcoded ad provider ID: $($match.Path):$($match.LineNumber)")
}

$project = $projectText
foreach ($target in @('MinikPlus', 'MinikPlusEnglish', 'MinikMathPlus', 'MinikMath', 'MinikPingPong')) {
    $match = [regex]::Match($project, "(?ms)^  ${target}:(?<body>[\s\S]*?)(?=^  [A-Za-z][A-Za-z0-9]+:|\z)")
    if (-not $match.Success -or $match.Groups['body'].Value -notmatch 'package: GoogleMobileAds') {
        $errors.Add("$target does not link the production Google Mobile Ads adapter.")
    }
}

$hub = Get-Content -Raw -LiteralPath (Join-Path $RepositoryRoot 'Sources/MinikActivityHubView.swift')
$mathBody = [regex]::Match(
    $hub,
    '(?ms)private func mathDestination\([\s\S]*?(?=private func curriculumEngineDestination)'
).Value
if ($mathBody -match 'recordLanguageAdOpportunity') {
    $errors.Add('Math curriculum routes must not inherit Android Language ad placements.')
}

Write-Output "MINIK_ADS_AUDIT_ERRORS=$($errors.Count)"
if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Output 'MINIK_ADS_AUDIT_OK'
