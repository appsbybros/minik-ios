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
    if ((Get-Content -Raw -LiteralPath $path) -notmatch $Pattern) {
        $errors.Add($Message)
    }
}

Require-Pattern 'Sources/RemoveAdsReminder.swift' 'firstDelay: TimeInterval = 2 \* 24 \* 60 \* 60' 'Android two-day first reminder delay is missing.'
Require-Pattern 'Sources/RemoveAdsReminder.swift' 'repeatDelay: TimeInterval = 14 \* 24 \* 60 \* 60' 'Android fourteen-day reminder delay is missing.'
Require-Pattern 'Sources/RemoveAdsReminder.swift' 'state\.nextPresentationAt = now\.addingTimeInterval\(RemoveAdsReminderPolicy\.repeatDelay\)[\s\S]*wasShownThisSession = true' 'Reminder must defer on presentation and show once per session.'
Require-Pattern 'Sources/RemoveAdsReminder.swift' 'adsAreActive[\s\S]*purchaseIsAvailable[\s\S]*!state\.neverShowAgain[\s\S]*!wasShownThisSession' 'Reminder eligibility gates are incomplete.'
Require-Pattern 'Sources/RemoveAdsReminder.swift' 'ParentalGateView\(' 'Reminder purchase is not protected by a grown-up gate.'
Require-Pattern 'Sources/RootView.swift' 'isProviderReady\(\)[\s\S]*!commerceController\.isRemoveAdsActive[\s\S]*purchaseIsAvailable: commerceController\.removeAdsProduct != nil' 'Root reminder requires real ads, no entitlement, and a loaded product.'
Require-Pattern 'Sources/MinikReleaseInformation.swift' 'url\.scheme\?\.lowercased\(\) == "https"[\s\S]*url\.host != nil' 'External Parent destinations must validate HTTPS URLs.'
Require-Pattern 'Sources/ParentAreaView.swift' 'perform\(\.external\(destination\)\)[\s\S]*case \.external\(let destination\):[\s\S]*openURL\(url\)' 'External links are missing from the Parent Area.'
Require-Pattern 'Tests/ProductConfigurationTests/ParentAreaVisitTests.swift' 'testTheGrownUpCheckOpensOneVisitOnly' 'Parent Area visit tests are missing.'
Require-Pattern 'Sources/ParentAreaView.swift' 'LabeledContent\("App version", value: releaseInformation\.versionDescription\)' 'Version/build metadata is not exposed in Parent Area.'
Require-Pattern 'project.yml' 'MinikPrivacyPolicyURL: \$\(MINIK_PRIVACY_POLICY_URL\)[\s\S]*MinikTermsOfUseURL: \$\(MINIK_TERMS_OF_USE_URL\)[\s\S]*MinikSupportURL: \$\(MINIK_SUPPORT_URL\)' 'Configurable release URL hooks are incomplete.'
Require-Pattern 'Tests/ProductConfigurationTests/ParentReleaseSourceTests.swift' 'testRemoveAdsReminderUsesAndroidTwoDayFirstDelayAndFourteenDayRepeat' 'Reminder cadence tests are missing.'
Require-Pattern 'Tests/ProductConfigurationTests/ParentReleaseSourceTests.swift' 'testReleaseInformationAcceptsOnlyConfiguredHTTPSDestinations' 'Release URL validation tests are missing.'

$parent = Get-Content -Raw -LiteralPath (Join-Path $RepositoryRoot 'Sources/ParentAreaView.swift')
if ($parent -match '\bLink\s*\(') {
    $errors.Add('Parent Area must not bypass the grown-up gate with a direct Link.')
}
# Owner, 15 November 2026 (the App Review reply for Minik Plus): the grown-up check comes before the
# Parent Area opens in every app that shows ParentAreaView, and one check covers the whole visit.
if ($parent -match 'ParentalGateView\(') {
    $errors.Add('Parent Area actions must not ask for a second grown-up check during a visit.')
}
$hub = Get-Content -Raw -LiteralPath (Join-Path $RepositoryRoot 'Sources/MinikActivityHubView.swift')
$parentAreaHosts = @(Get-ChildItem -File -Recurse -LiteralPath (Join-Path $RepositoryRoot 'Sources') -Filter '*.swift' |
    Where-Object { $_.Name -ne 'ParentAreaView.swift' -and (Get-Content -Raw -LiteralPath $_.FullName) -match '\bParentAreaView\(' })
if ($parentAreaHosts.Count -ne 1 -or $parentAreaHosts[0].Name -ne 'MinikActivityHubView.swift') {
    $errors.Add("ParentAreaView must be shown only by MinikActivityHubView, behind its grown-up check; found: $($parentAreaHosts.Name -join ', ').")
}
# Every assignment that opens the Parent Area directly follows a passed grown-up check.
$openings = [regex]::Matches($hub, '(?m)^.*route = \.parentArea\s*$')
foreach ($opening in $openings) {
    $before = $hub.Substring(0, $opening.Index)
    if ($before -notmatch 'parentAreaVisit\.grownUpCheckPassed\(\)\s*$') {
        $errors.Add("The Parent Area opens without the grown-up check: $($opening.Value.Trim())")
    }
}
if ($openings.Count -lt 1 -or $hub -notmatch 'parentAreaVisit\.grownUpCheckPassed\(\)\s*route = \.parentArea\s*\}\s*\}\) \{\s*ParentalGateView\(') {
    $errors.Add('The Parent Area must open from the grown-up check sheet.')
}
if ($hub -notmatch 'route = parentAreaVisit\.backFromPageOpensParentArea \? \.parentArea : nil' -or
    $hub -notmatch '\.onChange\(of: routeBelongsToParentAreaVisit\)[\s\S]*?parentAreaVisit\.leave\(\)') {
    $errors.Add('The Parent Area pages must return into the Parent Area only within a visit the grown-up check opened.')
}
# Purchases reachable from outside the Parent Area keep their own grown-up check.
foreach ($gated in @('Sources/RemoveAdsReminder.swift', 'Sources/MinikPlusPaywallView.swift', 'Sources/LanguageShellViews.swift', 'Sources/MinikMathWeb/MinikMathWebRootView.swift', 'Sources/RetroPong/BounceRootView.swift', 'Sources/ModernPong/ModernPongView.swift')) {
    if ((Get-Content -Raw -LiteralPath (Join-Path $RepositoryRoot $gated)) -notmatch 'ParentalGateView\(') {
        $errors.Add("$gated sells or restores outside the Parent Area without the grown-up check.")
    }
}

Write-Output "PARENT_RELEASE_SOURCE_AUDIT_ERRORS=$($errors.Count)"
if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Output 'PARENT_RELEASE_SOURCE_AUDIT_OK'
