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

$project = Read-Required 'project.yml'
$release = Read-Required 'docs/release-configuration.md'
$website = Read-Required 'docs/privacy-policy-website-replacement.md'
$inventory = Read-Required 'docs/app-store-privacy-data-inventory.md'
$checklist = Read-Required 'docs/apple-release-checklist.md'
$privacy = Read-Required 'docs/public-leaderboard-privacy.md'
$firebaseContract = Read-Required 'docs/firebase-leaderboard-contract.md'
$firebaseMigration = Read-Required 'docs/firebase-leaderboard-migration.md'
$languageManifest = Read-Required 'Resources/Privacy/Language/PrivacyInfo.xcprivacy'
$localManifest = Read-Required 'Resources/Privacy/LocalOnly/PrivacyInfo.xcprivacy'
$commerce = Read-Required 'Sources/MinikCommerce.swift'
$pingPongHost = Read-Required 'Sources/MinikAds.swift'
$reminders = Read-Required 'Sources/LearningReminderNotifications.swift'

$bundleIdentifiers = @(
    'com.appsbybros.minik.plus',
    'com.appsbybros.minik.plus.english',
    'com.appsbybros.minik.math',
    'com.appsbybros.minik.math.plus',
    'com.appsbybros.minik.pingpong'
)
foreach ($identifier in $bundleIdentifiers) {
    Require $project ([regex]::Escape($identifier)) "Shipping configuration omits $identifier."
    Require $checklist ([regex]::Escape($identifier)) "Apple checklist omits $identifier."
}
Reject $project 'com\.example\.temporary\.|com\.minik\.' 'Shipping project configuration contains an obsolete Apple identifier.'
Require $project 'MINIK_MARKETING_VERSION: "1\.7\.9"[\s\S]*MINIK_BUILD_NUMBER: "79"' 'Explicit source version/build settings are missing.'
Require $release 'increment[\s\S]*build for every upload[\s\S]*per-target marketing version' 'The release version/build strategy is not explicit.'

foreach ($term in @(
    'generated public nickname',
    'optional curated avatar identifier',
    'opaque participant identifier',
    'product or app identifier',
    'timestamp',
    'local or real profile name is not uploaded',
    'email address, phone number, date of birth, photograph, real name, or free-text profile',
    'Turning it off stops future leaderboard uploads',
    'does not delete learning progress stored locally'
)) {
    Require $website ([regex]::Escape($term)) "Website replacement copy omits required disclosure: $term"
}
Reject $website '(?i)(deleted|removed) within \d+|retained for \d+|kept for \d+' 'Website replacement copy makes an unsupported retention/deletion-time promise.'
Require $privacy 'privacy-policy-website-replacement\.md' 'Canonical leaderboard privacy documentation does not route to the website replacement.'
Require $privacy 'Strict repository-owned Rules and indexes now exist' 'Leaderboard privacy documentation omits the strict Rules source.'
Require $privacy 'must not be deployed until the administrator archive/clear cutover' 'Leaderboard privacy documentation does not preserve the Rules migration blocker.'
Require $firebaseContract 'not deployable against legacy production data/clients' 'The Firebase identity/rules migration blocker is missing.'
Require $firebaseMigration 'Owner/admin cutover sequence' 'The coordinated Firebase cutover runbook is missing.'

foreach ($product in @('MinikPlus', 'MinikPlusEnglish', 'MinikMathPlus', 'MinikMath', 'MinikPingPong')) {
    Require $inventory ([regex]::Escape($product)) "Privacy inventory omits $product."
}
foreach ($dataPath in @('Firebase anonymous UID', 'Generated alias', 'Google Mobile Ads', 'StoreKit', 'Local notifications')) {
    Require $inventory ([regex]::Escape($dataPath)) "Privacy inventory omits source data path: $dataPath"
}
Require $inventory 'Answers that must not be guessed in source' 'Privacy inventory does not separate owner classifications.'
Require $languageManifest 'NSPrivacyCollectedDataTypeUserID[\s\S]*NSPrivacyCollectedDataTypeGameplayContent' 'Language privacy manifest omits leaderboard data types.'
Require $languageManifest '<key>NSPrivacyTracking</key>\s*<false/>' 'Language privacy manifest must declare tracking false.'
Require $localManifest '<key>NSPrivacyCollectedDataTypes</key>\s*<array/>' 'Local-only privacy manifest unexpectedly declares collected data.'

Require $project 'MINIK_REMOVE_ADS_PRODUCT_IDENTIFIER: remove_ads' 'Canonical Remove Ads product ID is missing.'
Require $commerce 'EntitlementID\(rawValue: "remove_ads"\)' 'App commerce does not use the canonical Remove Ads entitlement.'
Require $pingPongHost 'final class MinikPingPongHostServices[\s\S]*availableActions: Set<PingPongHostAction> = \[\]' 'Standalone Ping Pong no-commerce posture changed.'
Require $release 'MinikPlus, MinikPlusEnglish and MinikMath expose purchase/restore[\s\S]*MinikPingPong[\s\S]*does not expose purchase/restore' 'Per-product StoreKit exposure is not documented.'

Require $reminders 'UNUserNotificationCenter[\s\S]*requestAuthorization\(options: \[\.alert, \.sound\]\)[\s\S]*removePendingNotificationRequests[\s\S]*removeDeliveredNotifications' 'Local notification authorization/cancellation boundary is incomplete.'
$shippingSource = $project + "`n" + ((Get-ChildItem -LiteralPath (Join-Path $RepositoryRoot 'Sources') -Filter '*.swift' -File | ForEach-Object {
    [IO.File]::ReadAllText($_.FullName, [Text.Encoding]::UTF8)
}) -join "`n")
Reject $shippingSource 'FirebaseMessaging|registerForRemoteNotifications|aps-environment|UIBackgroundModes[\s\S]*remote-notification' 'A remote-push configuration path exists in shipping source/configuration.'
Require $release 'There is no Firebase Messaging dependency, remote-push[\s\S]*aps-environment' 'Release handoff does not state the local-only notification boundary.'

Require $checklist '## READY IN REPO[\s\S]*## OWNER ACTION.*Apple Developer and App Store Connect[\s\S]*## OWNER ACTION.*Firebase and AdMob[\s\S]*## LEGAL/POLICY DECISION[\s\S]*## MAC/XCODE REQUIRED' 'Apple checklist does not classify repository, owner-console, legal/policy, and Mac work.'
Require $checklist 'settings\.base\.CODE_SIGN_STYLE: Automatic[\s\S]*DEVELOPMENT_TEAM[\s\S]*PROVISIONING_PROFILE_SPECIFIER' 'Signing/provisioning insertion points are incomplete.'
Require $checklist 'Firebase Console\s*Authentication\s*Sign-in method\s*Anonymous\s*Enable' 'The exact Anonymous Auth console path is missing.'
foreach ($item in @(
    'App ID', 'Team ID', 'version/build', 'Kids', 'Privacy Policy URL',
    'Support URL', 'age-rating questionnaire', 'App Privacy', 'remove_ads',
    'review notes', 'export-compliance', 'screenshots'
)) {
    Require $checklist ([regex]::Escape($item)) "Apple checklist omits $item."
}
Require $checklist 'Enable \*\*Authentication.*Sign-in method.*Anonymous\*\*' 'Firebase Anonymous Auth console action is missing.'
Require $checklist 'Keep enforcement off[\s\S]*monitor Android and Apple validity metrics' 'Safe App Check rollout action is missing.'
Require $checklist 'AdMob application ID[\s\S]*interstitial ad-unit ID' 'Required production AdMob identifiers are not listed.'

$errors | ForEach-Object { "RELEASE_CLOSURE_ERROR=$_" }
"RELEASE_CLOSURE_PRODUCTS_AUDITED=$($bundleIdentifiers.Count)"
"RELEASE_CLOSURE_PRIVACY_DOCUMENTS=3"
"RELEASE_CLOSURE_ERRORS=$($errors.Count)"
if ($errors.Count -gt 0) { exit 1 }
